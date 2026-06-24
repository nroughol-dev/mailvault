#!/bin/bash
#
# mailvault-root-sync.sh
#
# Tache ROOT pour le paquet SynoDovecot. A planifier dans DSM (Planificateur de
# taches -> Tache declenchee -> Au demarrage, ET une tache planifiee quotidienne),
# executee par root :
#     /volume1/scripts/mailvault-root-sync.sh
#
# Fait trois choses (le paquet, non-root, ne peut pas) :
#   1. SYNCHRO MOTS DE PASSE : copie le hash crypt de chaque utilisateur choisi
#      depuis /etc/shadow vers le passwd-file de Dovecot -> mot de passe IMAP =
#      mot de passe NAS.
#   2. SYNCHRO CERTIFICAT : pousse le certificat Let's Encrypt DSM dans le paquet.
#   3. REDIRECTION PORTS : 993->10993 et 465->10465 (LAN), Dovecot ne pouvant pas
#      binder les ports <1024 en non-root.
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
#   vide  => AUTO : utilise le certificat par defaut de DSM (recommande, aucun reglage).
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
# Determine le repertoire du certificat a utiliser (stdout), "" si rien.
find_cert_dir() {
    local c
    # 1. Domaine force -> cert dont le SAN contient $DOMAIN
    if [ -n "$DOMAIN" ]; then
        for c in "$ARCHIVE_DIR"/*/; do
            [ -f "${c}cert.pem" ] || continue
            openssl x509 -in "${c}cert.pem" -text -noout 2>/dev/null | grep -q "DNS:${DOMAIN}\b" && { echo "${c%/}"; return; }
        done
        return
    fi
    # 2. AUTO : certificat par defaut de DSM (suit le symlink vers _archive/<id>)
    if [ -f "${SYSTEM_DEFAULT_CERT}/cert.pem" ] && [ -f "${SYSTEM_DEFAULT_CERT}/privkey.pem" ]; then
        readlink -f "${SYSTEM_DEFAULT_CERT}" 2>/dev/null || echo "${SYSTEM_DEFAULT_CERT}"
        return
    fi
    # 3. Fallback : premier cert trouve dans _archive
    for c in "$ARCHIVE_DIR"/*/; do
        [ -f "${c}cert.pem" ] && { echo "${c%/}"; return; }
    done
}

sync_cert() {
    command -v openssl >/dev/null || { log "cert: openssl introuvable"; return; }
    [ -d "$ARCHIVE_DIR" ] || { log "cert: ${ARCHIVE_DIR} absent"; return; }

    local src; src=$(find_cert_dir)
    [ -n "$src" ] || { log "cert: aucun certificat trouve (ni defaut DSM ni _archive)${DOMAIN:+ pour domaine $DOMAIN}"; return; }
    local dom; dom=$(openssl x509 -in "$src/cert.pem" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p' | head -1)
    log "cert: certificat detecte ${src} (domaine: ${dom:-inconnu})"

    local key crt chn
    key="$src/RSA-privkey.pem"; [ -f "$key" ] || key="$src/privkey.pem"
    crt="$src/RSA-cert.pem";    [ -f "$crt" ] || crt="$src/cert.pem"
    chn="$src/RSA-chain.pem";   [ -f "$chn" ] || chn="$src/chain.pem"
    for f in "$key" "$crt" "$chn"; do [ -f "$f" ] || { log "cert: fichier manquant $f"; return; }; done

    local km cm
    km=$(openssl rsa  -in "$key" -modulus -noout 2>/dev/null | openssl md5 | awk '{print $NF}')
    cm=$(openssl x509 -in "$crt" -modulus -noout 2>/dev/null | openssl md5 | awk '{print $NF}')
    [ -n "$km" ] && [ "$km" = "$cm" ] || { log "cert: cle/cert ne correspondent pas"; return; }

    local tmp; tmp=$(mktemp -d)
    cp "$key" "$tmp/privkey.pem"
    { cat "$crt"; printf '\n'; cat "$chn"; } > "$tmp/fullchain.pem"
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
redirect_ports() {
    command -v iptables >/dev/null || { log "ports: iptables introuvable"; return; }
    local m std high
    for m in $PORT_MAP; do
        std="${m%%:*}"; high="${m##*:}"
        if ! iptables -t nat -C PREROUTING -p tcp --dport "$std" -j REDIRECT --to-ports "$high" 2>/dev/null; then
            iptables -t nat -A PREROUTING -p tcp --dport "$std" -j REDIRECT --to-ports "$high" \
                && log "ports: REDIRECT ${std}->${high} ajoute" \
                || log "ports: ECHEC REDIRECT ${std}->${high}"
        fi
    done
}

log "=== mailvault-root-sync : debut ==="
sync_passwords
sync_cert
redirect_ports
log "=== fin ==="
exit 0
