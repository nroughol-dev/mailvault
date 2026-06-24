
# Syno IMAP (Dovecot) — service setup
# Source par l'installeur generique et par start-stop-status

DOVECOT="${SYNOPKG_PKGDEST}/sbin/dovecot"
DOVEADM="${SYNOPKG_PKGDEST}/bin/doveadm"
OPENSSL="${SYNOPKG_PKGDEST}/bin/openssl"
CONF="${SYNOPKG_PKGVAR}/dovecot.conf"
USERS="${SYNOPKG_PKGVAR}/users"
CERT_DIR="${SYNOPKG_PKGVAR}/certs"

# Les binaires trouvent leurs libs dovecot
export LD_LIBRARY_PATH="${SYNOPKG_PKGDEST}/lib:${SYNOPKG_PKGDEST}/lib/dovecot:${LD_LIBRARY_PATH}"

# Lancement : dovecot -F (avant-plan), spksrc le background. nohup pour survivre
# au SIGHUP envoye quand start-stop-status se termine ; nohup exec dovecot donc
# $! = PID du master. SVC_WRITE_PID pour que spksrc ecrive ce PID (sinon
# daemon_status lit un PID_FILE vide et croit le service arrete).
SERVICE_COMMAND="nohup ${DOVECOT} -F -c ${CONF}"
SVC_BACKGROUND=yes
SVC_WRITE_PID=yes

service_postinst ()
{
    mkdir -p "${SYNOPKG_PKGVAR}/run" "${CERT_DIR}"

    # Generer dovecot.conf (modele Mail Server, adapte non-root + ports hauts)
    cat > "${CONF}" <<EOF
protocols = imap submission

service imap-login {
  inet_listener imap {
    port = 10143
  }
  inet_listener imaps {
    port = 10993
    ssl = yes
  }
  process_limit = 256
  service_count = 0
  chroot =
}
service submission-login {
  inet_listener submission {
    port = 10587
  }
  inet_listener submissions {
    port = 10465
    ssl = yes
  }
  chroot =
}

# Sockets internes : forcer NOTRE groupe (sinon Dovecot tente un chown vers le
# groupe compile par defaut "dovecot" (gid 143), impossible en non-root).
service stats {
  unix_listener stats-writer {
    group = ${SYNOPKG_PKGNAME}
  }
}
service dict {
  unix_listener dict {
    group = ${SYNOPKG_PKGNAME}
  }
}
service dict-async {
  unix_listener dict-async {
    group = ${SYNOPKG_PKGNAME}
  }
}
service imap-hibernate {
  unix_listener imap-hibernate {
    group = ${SYNOPKG_PKGNAME}
  }
}
service anvil {
  chroot =
}

default_internal_user = ${SYNOPKG_PKGNAME}
default_login_user    = ${SYNOPKG_PKGNAME}
first_valid_uid = 1
last_valid_uid  = 0

disable_plaintext_auth = yes
auth_mechanisms = plain login
passdb {
  driver = passwd-file
  args = username_format=%u ${USERS}
}
userdb {
  driver = static
  args = uid=${SYNOPKG_PKGNAME} gid=${SYNOPKG_PKGNAME} home=/var/services/homes/%u
}

mail_location = maildir:/var/services/homes/%u/.Maildir
namespace inbox {
  inbox = yes
  prefix =
  mailbox Drafts {
    special_use = \\Drafts
  }
  mailbox Junk {
    special_use = \\Junk
  }
  mailbox Sent {
    special_use = \\Sent
  }
  mailbox "Sent Messages" {
    special_use = \\Sent
  }
  mailbox Trash {
    special_use = \\Trash
  }
}

ssl = yes
ssl_cert = <${CERT_DIR}/fullchain.pem
ssl_key  = <${CERT_DIR}/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes

submission_relay_host =

mail_max_userip_connections = 30
postmaster_address = postmaster@localhost

base_dir = ${SYNOPKG_PKGVAR}/run
log_path = ${SYNOPKG_PKGVAR}/dovecot.log
info_log_path = ${SYNOPKG_PKGVAR}/dovecot.log
EOF

    # passwd-file vide pour que Dovecot demarre ; rempli par la tache root.
    touch "${USERS}"
    chmod 600 "${USERS}"

    # Liste optionnelle de restriction (vide = la tache root auto-detecte tous
    # les utilisateurs home ayant un .Maildir).
    [ -f "${SYNOPKG_PKGVAR}/imap-users.list" ] || : > "${SYNOPKG_PKGVAR}/imap-users.list"

    # Certificat placeholder auto-signe, genere ICI (postinst tourne toujours)
    # pour que Dovecot puisse demarrer des l'install. Le vrai Let's Encrypt sera
    # pousse ensuite par la tache root.
    if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
        "${OPENSSL}" req -new -x509 -days 3650 -nodes \
            -subj "/CN=$(hostname 2>/dev/null || echo localhost)" \
            -keyout "${CERT_DIR}/privkey.pem" \
            -out "${CERT_DIR}/fullchain.pem" >/dev/null 2>&1
        chmod 600 "${CERT_DIR}/privkey.pem"
        chmod 644 "${CERT_DIR}/fullchain.pem"
    fi
}

service_prestart ()
{
    # Cert placeholder auto-signe si le vrai Let's Encrypt n'est pas encore pousse
    if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
        echo "Generation d'un certificat placeholder auto-signe" >> "${LOG_FILE}"
        "${OPENSSL}" req -new -x509 -days 3650 -nodes \
            -subj "/CN=$(hostname 2>/dev/null || echo localhost)" \
            -keyout "${CERT_DIR}/privkey.pem" \
            -out "${CERT_DIR}/fullchain.pem" >> "${LOG_FILE}" 2>&1
        chmod 600 "${CERT_DIR}/privkey.pem"
        chmod 644 "${CERT_DIR}/fullchain.pem"
    fi
}
