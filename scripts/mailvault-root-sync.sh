#!/bin/bash
#
# mailvault-root-sync.sh
#
# Tache ROOT pour le paquet MailVault. A planifier dans DSM (Planificateur de
# taches -> Tache declenchee -> Au demarrage, ET une tache planifiee quotidienne),
# executee par root :
#     /volume1/scripts/mailvault-root-sync.sh
#
# Fait trois choses (le paquet, non-root, ne peut pas) :
#   1. SYNCHRO MOTS DE PASSE : copie le hash crypt de chaque utilisateur choisi
#      depuis /etc/shadow vers le passwd-file de Dovecot -> mot de passe IMAP =
#      mot de passe NAS.
#   2. SYNCHRO CERTIFICAT : pousse le certificat Let's Encrypt DSM dans le paquet.
#   3. REDIRECTION PORTS : 993->10993 et 465->10465 (LAN, IPv4 ET IPv6), Dovecot
#      ne pouvant pas binder les ports <1024 en non-root.
#
set -u

# Repertoire stable : ce script redemarre le paquet mailvault, ce qui invalide
# le cwd si on l'avait lance depuis /var/packages/mailvault (bruit getcwd).
cd / 2>/dev/null || true

PKG="mailvault"
PKGVAR="/var/packages/${PKG}/var"
SVC_USER="${PKG}"
USERLIST="${PKGVAR}/imap-users.list"
USERS="${PKGVAR}/users"
CERT_DST="${PKGVAR}/certs"
# Domaine du certificat a servir :
#   vide  => AUTO (recommande, aucun reglage) : prend le certificat Let's Encrypt
#            valide le plus durable de _archive ; a defaut le certificat par
#            defaut de DSM ; a defaut le premier cert valide trouve.
#   sinon => force un domaine precis (le cert dont le SAN contient ce domaine).
DOMAIN=""
ARCHIVE_DIR="/usr/syno/etc/certificate/_archive"
SYSTEM_DEFAULT_CERT="/usr/syno/etc/certificate/system/default"
# Mappages port_standard:port_haut pour la redirection
PORT_MAP="993:10993 465:10465 143:10143 587:10587"
LOG_FILE="/var/log/mailvault-root-sync.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

[ "$(id -u)" -eq 0 ] || { echo "ERREUR: doit tourner en root"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Synchro des mots de passe (hash /etc/shadow -> passwd-file Dovecot)
# ---------------------------------------------------------------------------
sync_passwords() {
    local users
    if [ -f "$USERLIST" ] && [ -s "$USERLIST" ]; then
        # liste explicite de restriction
        users=$(grep -vE '^[[:space:]]*$' "$USERLIST")
        log "passwords: liste explicite ($USERLIST)"
    else
        # auto-detection : tout utilisateur home ayant un .Maildir
        users=$(for d in /var/services/homes/*/.Maildir; do [ -d "$d" ] && basename "$(dirname "$d")"; done)
        log "passwords: auto-detection des utilisateurs home avec .Maildir"
    fi
    local tmp; tmp=$(mktemp)
    local u h
    for u in $users; do
        [ -n "$u" ] || continue
        h=$(grep "^${u}:" /etc/shadow 2>/dev/null | cut -d: -f2)
        case "$h" in
            '$6$'*|'$5$'*|'$2'*)
                echo "${u}:{CRYPT}${h}" >> "$tmp"
                log "passwords: ${u} synchronise"
                ;;
            *)
                log "passwords: hash inexploitable pour ${u} (compte verrouille/sans mot de passe) -> ignore"
                ;;
        esac
    done

    if ! cmp -s "$tmp" "$USERS" 2>/dev/null; then
        cp "$tmp" "$USERS"
        chown "${SVC_USER}:${SVC_USER}" "$USERS"
        chmod 600 "$USERS"
        log "passwords: passwd-file mis a jour ($(wc -l < "$USERS") compte(s))"
    else
        log "passwords: deja a jour"
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 2. Synchro du certificat Let's Encrypt (modele sync-letsencrypt-to-containers)
# ---------------------------------------------------------------------------
# Un certificat auto-signe porte le meme sujet que son emetteur. Sert a ne pas
# retenir le placeholder Synology quand un vrai certificat existe.
is_self_signed() {
    [ "$(openssl x509 -in "$1" -noout -subject 2>/dev/null | sed 's/^subject=//')" \
      = "$(openssl x509 -in "$1" -noout -issuer  2>/dev/null | sed 's/^issuer=//')" ]
}

# Score de validite restante d'un cert : nombre de paliers franchis, 0 = expire.
# On procede par paliers plutot qu'en comparant les dates parce que le busybox
# date de DSM ne sait pas lire le format openssl ("Jun 24 12:00:00 2026 GMT").
# Sert a departager plusieurs certificats de facon deterministe : un cert LE
# fraichement renouvele (90 j) l'emporte sur un qui expire dans 5 jours.
cert_score() {
    local s=0 t
    for t in 0 604800 2592000 5184000 7776000 15552000 31536000 63072000; do
        openssl x509 -in "$1" -noout -checkend "$t" >/dev/null 2>&1 || break
        s=$((s + 1))
    done
    echo "$s"
}

# Meilleur cert NON EXPIRE de _archive parmi ceux passant le filtre $1
# ("le" = issuer Let's Encrypt, "domain" = SAN contenant $DOMAIN, "any" = tous).
pick_best_cert() {
    local mode="$1" c s best="" best_score=0
    for c in "$ARCHIVE_DIR"/*/; do
        [ -f "${c}cert.pem" ] || continue
        case "$mode" in
            le)     openssl x509 -in "${c}cert.pem" -noout -issuer 2>/dev/null | grep -qi "let.s encrypt" || continue ;;
            domain) openssl x509 -in "${c}cert.pem" -text -noout 2>/dev/null | grep -q "DNS:${DOMAIN}\b" || continue ;;
        esac
        s=$(cert_score "${c}cert.pem")
        [ "$s" -gt "$best_score" ] || continue   # 0 = expire -> jamais retenu
        best_score="$s"; best="${c%/}"
    done
    [ -n "$best" ] && echo "$best"
}

# Determine le repertoire du certificat a utiliser (stdout), "" si rien.
# Un certificat expire n'est jamais retenu : mieux vaut garder celui deja en
# place que de casser le TLS des clients.
find_cert_dir() {
    local d
    # 1. Domaine force -> cert valide dont le SAN contient $DOMAIN
    if [ -n "$DOMAIN" ]; then
        pick_best_cert domain
        return
    fi
    # 2. AUTO : le certificat par DEFAUT de DSM, s'il est valide et pas auto-signe.
    #    C'est celui que l'admin a designe pour la machine, donc celui dont le SAN
    #    couvre le nom reellement servi.
    #    ⛔ 2026-09-12 : sans cette etape, la suivante a choisi un Let's Encrypt d'un
    #    AUTRE sous-domaine au seul motif qu'il expirait plus tard -- un certificat
    #    residuel, laisse dans _archive apres qu'un service eut change d'adresse.
    #    Tous les clients IMAP sont alors passes en "hostname mismatch". Trier par
    #    duree de validite ne dit RIEN du nom couvert.
    if [ -f "${SYSTEM_DEFAULT_CERT}/cert.pem" ] && [ -f "${SYSTEM_DEFAULT_CERT}/privkey.pem" ] \
       && [ "$(cert_score "${SYSTEM_DEFAULT_CERT}/cert.pem")" -gt 0 ] \
       && ! is_self_signed "${SYSTEM_DEFAULT_CERT}/cert.pem"; then
        readlink -f "${SYSTEM_DEFAULT_CERT}" 2>/dev/null || echo "${SYSTEM_DEFAULT_CERT}"
        return
    fi
    # 3. Sinon : cert Let's Encrypt (issuer = Let's Encrypt) -> le vrai cert du domaine
    #    externe, meme si le certificat "par defaut" de DSM est l'auto-signe Synology.
    d=$(pick_best_cert le)
    [ -n "$d" ] && { echo "$d"; return; }
    # 4. Sinon : certificat par defaut de DSM meme auto-signe (suit le symlink)
    if [ -f "${SYSTEM_DEFAULT_CERT}/cert.pem" ] && [ -f "${SYSTEM_DEFAULT_CERT}/privkey.pem" ] \
       && [ "$(cert_score "${SYSTEM_DEFAULT_CERT}/cert.pem")" -gt 0 ]; then
        readlink -f "${SYSTEM_DEFAULT_CERT}" 2>/dev/null || echo "${SYSTEM_DEFAULT_CERT}"
        return
    fi
    # 5. Fallback : meilleur cert valide de _archive, tous emetteurs confondus
    pick_best_cert any
}

sync_cert() {
    command -v openssl >/dev/null || { log "cert: openssl introuvable"; return; }
    [ -d "$ARCHIVE_DIR" ] || { log "cert: ${ARCHIVE_DIR} absent"; return; }

    local src; src=$(find_cert_dir)
    [ -n "$src" ] || { log "cert: aucun certificat valide trouve (ni defaut DSM ni _archive)${DOMAIN:+ pour domaine $DOMAIN} -> cert en place conserve"; return; }
    local dom; dom=$(openssl x509 -in "$src/cert.pem" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p' | head -1)
    log "cert: certificat detecte ${src} (domaine: ${dom:-inconnu})"

    # DSM prefixe en RSA-* quand une entree porte a la fois un cert RSA et un ECC.
    # Le prefixe se choisit en bloc : melanger RSA-privkey.pem et cert.pem (ECC)
    # donnerait une paire incoherente.
    local pfx=""
    [ -f "$src/RSA-privkey.pem" ] && [ -f "$src/RSA-cert.pem" ] && pfx="RSA-"
    local key crt chn fc
    key="$src/${pfx}privkey.pem"
    crt="$src/${pfx}cert.pem"
    chn="$src/${pfx}chain.pem"
    fc="$src/${pfx}fullchain.pem"
    for f in "$key" "$crt"; do [ -f "$f" ] || { log "cert: fichier manquant $f"; return; }; done

    # Comparaison sur la cle publique, pas sur le modulus : "openssl rsa" echoue
    # sur une cle ECDSA (DSM et acme.sh en emettent), ce qui ferait passer une
    # paire valide pour incoherente et bloquerait la synchro indefiniment.
    local kp cp
    kp=$(openssl pkey -in "$key" -pubout      2>/dev/null | openssl md5 | awk '{print $NF}')
    cp=$(openssl x509 -in "$crt" -pubkey -noout 2>/dev/null | openssl md5 | awk '{print $NF}')
    [ -n "$kp" ] && [ "$kp" = "$cp" ] || { log "cert: cle/cert ne correspondent pas"; return; }

    local tmp; tmp=$(mktemp -d)
    cp "$key" "$tmp/privkey.pem"
    if [ -f "$fc" ]; then
        cp "$fc" "$tmp/fullchain.pem"                          # fullchain DSM directement
    elif [ -f "$chn" ]; then
        { cat "$crt"; printf '\n'; cat "$chn"; } > "$tmp/fullchain.pem"   # cert + chaine
    else
        cp "$crt" "$tmp/fullchain.pem"                         # cert seul (pas de chaine)
    fi
    sed -i 's/\r$//' "$tmp"/*.pem 2>/dev/null

    mkdir -p "$CERT_DST"
    local changed=0 f
    for f in privkey.pem fullchain.pem; do
        if [ ! -f "$CERT_DST/$f" ] || ! cmp -s "$tmp/$f" "$CERT_DST/$f"; then
            cp "$tmp/$f" "$CERT_DST/$f"; changed=1
        fi
    done
    chown -R "${SVC_USER}:${SVC_USER}" "$CERT_DST"
    chmod 600 "$CERT_DST/privkey.pem"; chmod 644 "$CERT_DST/fullchain.pem"
    rm -rf "$tmp"

    if [ "$changed" -eq 1 ]; then
        log "cert: mis a jour -> redemarrage de ${PKG}"
        /usr/syno/bin/synopkg restart "$PKG" >/dev/null 2>&1 && log "cert: ${PKG} redemarre" || log "cert: WARNING restart echoue"
    else
        log "cert: deja a jour"
    fi
}

# ---------------------------------------------------------------------------
# 3. Redirection des ports standards vers les ports hauts de Dovecot
# ---------------------------------------------------------------------------
# Pose les REDIRECT pour une famille d'adresses. $1 = binaire, $2 = libelle.
# ⛔ "-m addrtype --dst-type LOCAL" est OBLIGATOIRE : sans lui, PREROUTING capture
# aussi le trafic qui ne fait que TRAVERSER le NAS (clients OpenVPN routes par lui,
# a plus forte raison en full-tunnel). Constate le 2026-09-12 : les sessions IMAP et
# SMTP vers ssl0.ovh.net, imap.gmail.com ou o2switch se terminaient sur le NAS, qui
# presentait SON certificat a la place de celui du serveur vise.
redirect_family() {
    local bin="$1" fam="$2" m std high
    command -v "$bin" >/dev/null || { log "ports: ${bin} introuvable -> ${fam} ignore"; return; }
    # DSM 7 peut livrer un ip6tables SANS table nat (module ip6table_nat absent du
    # noyau) : constate le 2026-09-12 sur un DS918+ en DSM 7.2, "can't initialize ip6tables
    # table nat". Sans ce test, chaque execution echouerait sur les quatre ports et
    # remplirait le journal sans rien pouvoir corriger.
    "$bin" -t nat -L -n >/dev/null 2>&1 || { log "ports: ${fam} sans table nat -> ignore"; return; }
    for m in $PORT_MAP; do
        std="${m%%:*}"; high="${m##*:}"
        # ⛔ Retirer d'abord l'ancienne forme, SANS addrtype : ajoutee par une version
        # anterieure, elle precede la nouvelle dans la chaine et continue de capturer
        # le transit -- le correctif serait inoperant, et en silence. Constate le
        # 2026-09-12 en deployant sur un second NAS deja equipe. Boucle car la regle
        # peut avoir ete ajoutee plusieurs fois.
        while "$bin" -t nat -D PREROUTING -p tcp --dport "$std" -j REDIRECT --to-ports "$high" 2>/dev/null; do
            log "ports: ${fam} ancienne regle ${std}->${high} sans addrtype retiree"
        done
        if ! "$bin" -t nat -C PREROUTING -p tcp --dport "$std" -m addrtype --dst-type LOCAL -j REDIRECT --to-ports "$high" 2>/dev/null; then
            "$bin" -t nat -A PREROUTING -p tcp --dport "$std" -m addrtype --dst-type LOCAL -j REDIRECT --to-ports "$high" \
                && log "ports: ${fam} REDIRECT ${std}->${high} ajoute" \
                || log "ports: ${fam} ECHEC REDIRECT ${std}->${high}"
        fi
    done
}

redirect_ports() {
    redirect_family iptables  IPv4
    # Indispensable des que le NAS a une IPv6 routable (delegation de prefixe
    # frequente, IPv6 actif par defaut en DSM) : un client qui resout l'AAAA se
    # connecte en IPv6, ou aucune regle NAT IPv4 ne s'applique.
    redirect_family ip6tables IPv6
}

log "=== mailvault-root-sync : debut ==="
sync_passwords
sync_cert
redirect_ports
log "=== fin ==="
exit 0
