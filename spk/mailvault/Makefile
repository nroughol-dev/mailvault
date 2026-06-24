SPK_NAME = mailvault
SPK_VERS = 1.0.0
SPK_REV = 1
SPK_ICON = src/mailvault.png

MAINTAINER = nroughol-dev
MAINTAINER_URL = https://github.com/nroughol-dev/mailvault
DISPLAY_NAME = MailVault
DESCRIPTION = MailVault - standalone Dovecot IMAP server that serves your existing .Maildir folders. A lightweight replacement for Synology Mail Server to keep browsing your mail archives. IMAP plus submission, virtual users, login with your NAS password, TLS pushed by a scheduled task.
DESCRIPTION_FRE = MailVault - serveur IMAP Dovecot autonome servant vos dossiers .Maildir existants. Remplacant leger de Synology Mail Server pour continuer a consulter vos archives mail. IMAP plus submission, utilisateurs virtuels, connexion avec votre mot de passe NAS, TLS pousse par une tache planifiee.
STARTABLE = yes
HOMEPAGE = https://github.com/nroughol-dev/mailvault
LICENSE  = MIT, LGPL-2.1
REQUIRED_MIN_DSM = 7.0

CONF_DIR = src/conf

# 'auto' -> user de service nomme d'apres le paquet, non-root
SERVICE_USER = auto
SERVICE_SETUP = src/service-setup.sh

SERVICE_PORT = 10993
SERVICE_PORT_TITLE = MailVault IMAPS high port

DEPENDS = cross/dovecot

include ../../mk/spksrc.common.mk
include ../../mk/spksrc.spk-meta.mk
