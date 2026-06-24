<div align="center">

<img src="icon-256.png" width="120" alt="MailVault"/>

# MailVault

**A lightweight Dovecot IMAP server packaged for Synology DSM 7 — keep browsing your mail archives after Mail Server is gone.**

**Un serveur IMAP Dovecot léger empaqueté pour Synology DSM 7 — continuez à consulter vos archives mail après la disparition de Mail Server.**

🇬🇧 [English](#english) · 🇫🇷 [Français](#français)

</div>

---

## English

A Synology package (`.spk`) running a standalone **Dovecot IMAP/IMAPS** server, designed as a
**minimal replacement for Synology Mail Server** for **browsing e-mail archives**.

> **Why?** **DSM 7.4 removes Mail Server** in favour of the **MailPlus** suite — heavy (calendars,
> contacts… 2 GB RAM), with a flaky importer, and unavailable on small ARM NAS units. If you use
> Mail Server *only* as an IMAP archive store (mail collected from several accounts, read from any
> client), MailVault replaces it **identically**: same `~/.Maildir`, same host, same port 993, same
> certificate, **same password as your DSM account**.

### ✨ Features

- **Dovecot 2.3.21.1** compiled for Synology (apollolake / x86-64; an ARM recipe is possible).
- **Serves your existing `~/.Maildir` untouched** — no data migration.
- **Non-root**: follows the DSM 7 sandbox model (dedicated service user), no Synology signature required.
- **Login with your NAS account password**: the `$6$` (SHA512-CRYPT) hash is synced from `/etc/shadow`
  into Dovecot's `passwd-file`. No separate password.
- **Let's Encrypt certificate** managed by DSM, pushed automatically to Dovecot (transparent renewal).
- **IMAP + submission** (the submission service satisfies mail clients' SMTP check; actual sending
  stays disabled — use case is *archive*).
- **Transparent** to already-configured desktop & mobile clients.

### 🧩 Architecture (and why)

DSM 7 **forbids non-Synology-signed third-party packages** from running as root **or** getting Linux
*capabilities* (verified empirically). Hence:

| DSM 7 constraint | Workaround |
|---|---|
| No `run-as: root` | Dovecot runs as the service user `mailvault` (the "Plex" model) |
| No `cap_net_bind_service` → can't bind ports < 1024 | Dovecot listens on **high ports**: `10143 / 10993 / 10587 / 10465` |
| The non-root daemon can read neither `/etc/shadow`, the cert key, nor add iptables rules | A **root task** (DSM Task Scheduler) does these 3 things and "pushes" the results to the package |

So the solution has **3 parts**:

```
┌─ .spk package "mailvault" (non-root) ──────────────────────────┐
│  Dovecot serves the .Maildir over IMAPS on HIGH ports            │
└──────────────────────────────────────────────────────────────────┘
        ▲ password hash + cert pushed     ▲ REDIRECT 993→10993, 465→10465
┌───────┴───────────────────────────────────────────────────────────┐
│  scripts/mailvault-root-sync.sh   (root task, boot + daily)       │
│   • reads /etc/shadow → Dovecot passwd-file (NAS password)         │
│   • finds the DSM Let's Encrypt cert → pushes it to the package    │
│   • adds the iptables REDIRECT rules (LAN)                         │
└───────────────────────────────────────────────────────────────────┘
+ External access: the router forwards 993/465 to the NAS (unchanged).
```

### 🔨 Building the `.spk`

Built with the **spksrc** framework in Docker. On macOS/Apple Silicon, **an ext4 Docker volume is
required** (the virtiofs bind-mount breaks the toolchain extraction).

```bash
# 1. Get spksrc and drop these recipes in
git clone --depth 1 https://github.com/SynoCommunity/spksrc.git
cp -r cross/dovecot   spksrc/cross/
cp -r spk/mailvault spksrc/spk/

# 2. Build inside a Docker volume (ext4) — example apollolake / DSM 7.3
docker volume create spksrc-build
docker run --rm --platform=linux/amd64 -v "$PWD/spksrc":/src:ro -v spksrc-build:/spksrc \
  ghcr.io/synocommunity/spksrc bash -c \
  'cd /src && tar --exclude=./toolchain/*/work --exclude=./.git -cf - . | (cd /spksrc && tar -xpf -)'
docker run --rm --platform=linux/amd64 -v spksrc-build:/spksrc -w /spksrc \
  -e TAR_CMD="fakeroot tar" ghcr.io/synocommunity/spksrc \
  bash -c 'cd spk/mailvault && make arch-apollolake-7.3'
# the .spk lands in the volume under /spksrc/packages/
```

> **Porting notes (learned the hard way):** the `cross/dovecot` recipe sets `GNU_CONFIGURE = 1`
> (otherwise no `--prefix`/`--host`) and pre-seeds Dovecot's cross-compile cache vars
> (`i_cv_posix_fallocate_works`, `i_cv_gmtime_max_time_t=40`, …). The package needs an empty
> `cross/dovecot/PLIST.auto`, otherwise the Dovecot binaries aren't packaged.

### 🖥️ Supported NAS / architecture

DSM checks the `arch` field inside each package and only installs one that lists **your model's
arch** (find yours via Synology's *"What kind of CPU does my NAS have"*). A package built with a
given toolchain declares the **whole family** that toolchain serves, so a single `.spk` covers many
models. The [**Releases**](../../releases) provide:

- **`apollolake`** — Intel, **DS918+** and family (DS218+, DS718+, DS418play…).
- **`aarch64`** — ARM 64-bit: **rtd1296** (e.g. DS220j), rtd1619b, armada37xx.

For another family, rebuild by changing only the make target:

```bash
make arch-x64-7.3       # one package for ALL Intel x86-64 models
make arch-aarch64-7.2   # ARM 64-bit family: rtd1296, rtd1619b, armada37xx
```
*(Tip: the toolchain `TC_ARCH` for an ARM model can move between DSM versions — rtd1296 is served
by `syno-aarch64-7.2`, not a `7.3` toolchain. Build against the DSM version whose toolchain lists
your arch; the binary still runs on newer DSM.)*

### 🚀 Install & deploy

1. **Install the package** — download the `.spk` for your model from the
   [**Releases**](../../releases) page, then *Package Center → Manual Install →* select it (confirm
   the signature warning). It starts on its own and serves the Maildir on the high ports.
2. **Grant Maildir access** — *Control Panel → Shared Folder → `homes` → Edit → Permissions*: in the
   user dropdown, switch to **System internal user** (the `mailvault` service account is *not* in the
   regular *Local users* list), then grant **`mailvault`** **Read/Write** (apply to subfolders) →
   covers every account at once.
3. **Install the root task**
   ```bash
   scp scripts/mailvault-root-sync.sh user@nas:/volume1/scripts/
   ssh user@nas 'sudo chmod 755 /volume1/scripts/mailvault-root-sync.sh'
   ```
   In **DSM Task Scheduler**, create 2 **root** tasks running
   `/volume1/scripts/mailvault-root-sync.sh`: one **at boot** (re-adds the iptables rules, which don't
   survive a reboot) and one **daily** (re-syncs passwords + certificate). Run it once manually.
4. **External access (router)** — forward **TCP 993 → NAS:993** (IMAPS, required) and optionally
   **TCP 465 → NAS:465** (submission). The NAS iptables rule maps to the high ports — **router
   forwards stay the same as Mail Server**.

### ⚙️ Configuration

- **Domain**: set `SUBJECT_DOMAIN` at the top of `scripts/mailvault-root-sync.sh`, and the
  `postmaster_address` / placeholder-cert CN in `spk/mailvault/src/service-setup.sh`.
- **Served accounts**: by default **every** home user with a `.Maildir` is served. To restrict, list
  the wanted users (one per line) in `/var/packages/mailvault/var/imap-users.list`.
- **Listen ports**: `10143` (IMAP), `10993` (IMAPS), `10587`/`10465` (submission).

### ⚠️ Limitations

- **No real sending**: submission satisfies client setup but does not send (use case = archive).
- **Security**: NAS `$6$` hashes are copied into the `passwd-file` (0600, readable only by the
  `mailvault` user) — same exposure as any mail server with local auth.
- **iptables not persistent**: hence the mandatory "at boot" task.
- **Per-architecture build**: this repo targets **apollolake (x86-64)**. For an ARM NAS
  (e.g. `rtd1296`/aarch64), recompile `cross/dovecot` for that arch.

---

## Français

Un paquet Synology (`.spk`) faisant tourner un serveur **Dovecot IMAP/IMAPS** autonome, pensé comme
**remplaçant minimal de Synology Mail Server** pour la **consultation d'archives e-mail**.

> **Pourquoi ?** **DSM 7.4 supprime Mail Server** au profit de la suite **MailPlus** — lourde
> (calendriers, contacts… 2 Go de RAM), à l'import capricieux, et indisponible sur les petits NAS
> ARM. Si vous utilisez Mail Server *uniquement* comme dépôt IMAP d'archives (mails relevés depuis
> plusieurs comptes, consultés depuis n'importe quel client), MailVault le remplace **à l'identique** :
> mêmes `~/.Maildir`, même hôte, même port 993, même certificat, **même mot de passe que le compte DSM**.

### ✨ Caractéristiques

- **Dovecot 2.3.21.1** compilé pour Synology (apollolake / x86-64 ; recette ARM possible).
- **Sert les `~/.Maildir` existants intacts** — aucune migration.
- **Non-root** : suit le modèle de sandbox DSM 7 (utilisateur de service dédié), sans signature Synology.
- **Connexion avec le mot de passe du compte NAS** : le hash `$6$` (SHA512-CRYPT) est synchronisé depuis
  `/etc/shadow` vers le `passwd-file` de Dovecot. Pas de mot de passe dédié.
- **Certificat Let's Encrypt** géré par DSM, poussé automatiquement vers Dovecot (renouvellement transparent).
- **IMAP + submission** (le service submission satisfait la vérif SMTP des clients ; l'envoi réel reste
  désactivé — usage = archive).
- **Transparent** pour les clients déjà configurés (desktop & mobile).

### 🧩 Architecture (et pourquoi)

DSM 7 **interdit aux paquets tiers non signés par Synology** de tourner en root **ou** d'obtenir des
*capabilities* (vérifié empiriquement). D'où :

| Contrainte DSM 7 | Parade |
|---|---|
| Pas de `run-as: root` | Dovecot tourne sous l'utilisateur de service `mailvault` (modèle « Plex ») |
| Pas de `cap_net_bind_service` → pas de bind < 1024 | Dovecot écoute sur des **ports hauts** : `10143 / 10993 / 10587 / 10465` |
| Le daemon non-root ne peut lire ni `/etc/shadow`, ni la clé du certif, ni poser d'iptables | Une **tâche root** (Planificateur DSM) fait ces 3 choses et « pousse » les résultats au paquet |

La solution repose donc sur **3 morceaux** :

```
┌─ Paquet .spk « mailvault » (non-root) ─────────────────────────┐
│  Dovecot sert les .Maildir en IMAPS sur les ports HAUTS          │
└──────────────────────────────────────────────────────────────────┘
        ▲ hash mdp + cert poussés        ▲ REDIRECT 993→10993, 465→10465
┌───────┴───────────────────────────────────────────────────────────┐
│  scripts/mailvault-root-sync.sh  (tâche root, boot + quotidien)   │
│   • lit /etc/shadow → passwd-file Dovecot (mot de passe NAS)       │
│   • détecte le cert Let's Encrypt DSM → le pousse au paquet        │
│   • pose les règles iptables REDIRECT (LAN)                       │
└───────────────────────────────────────────────────────────────────┘
+ Accès externe : le routeur forwarde 993/465 vers le NAS (inchangé).
```

### 🔨 Compilation du `.spk`

Build via **spksrc** dans Docker. Sur macOS/Apple Silicon, **un volume Docker ext4 est obligatoire**
(le montage virtiofs casse l'extraction du toolchain).

```bash
# 1. Récupérer spksrc et y déposer les recettes
git clone --depth 1 https://github.com/SynoCommunity/spksrc.git
cp -r cross/dovecot   spksrc/cross/
cp -r spk/mailvault spksrc/spk/

# 2. Builder dans un volume Docker (ext4) — exemple apollolake / DSM 7.3
docker volume create spksrc-build
docker run --rm --platform=linux/amd64 -v "$PWD/spksrc":/src:ro -v spksrc-build:/spksrc \
  ghcr.io/synocommunity/spksrc bash -c \
  'cd /src && tar --exclude=./toolchain/*/work --exclude=./.git -cf - . | (cd /spksrc && tar -xpf -)'
docker run --rm --platform=linux/amd64 -v spksrc-build:/spksrc -w /spksrc \
  -e TAR_CMD="fakeroot tar" ghcr.io/synocommunity/spksrc \
  bash -c 'cd spk/mailvault && make arch-apollolake-7.3'
# le .spk est dans le volume sous /spksrc/packages/
```

> **Notes de portage (apprises à la dure)** : la recette `cross/dovecot` pose `GNU_CONFIGURE = 1`
> (sinon pas de `--prefix`/`--host`) et pré-renseigne les cache vars de cross-compile de Dovecot
> (`i_cv_posix_fallocate_works`, `i_cv_gmtime_max_time_t=40`, …). Le paquet nécessite un
> `cross/dovecot/PLIST.auto` (vide), sinon les binaires Dovecot ne sont pas empaquetés.

### 🖥️ Modèles NAS / architecture supportés

DSM vérifie le champ `arch` dans chaque paquet et n'installe que celui qui liste **l'arch de votre
modèle** (trouvez la vôtre via *« Quel type de processeur possède mon NAS »* de Synology). Un paquet
compilé avec un toolchain déclare **toute la famille** que ce toolchain sert → un seul `.spk` couvre
plusieurs modèles. Les [**Releases**](../../releases) fournissent :

- **`apollolake`** — Intel, **DS918+** et famille (DS218+, DS718+, DS418play…).
- **`aarch64`** — ARM 64-bit : **rtd1296** (ex. DS220j), rtd1619b, armada37xx.

Pour une autre famille, recompiler en changeant juste la cible :

```bash
make arch-x64-7.3       # un seul paquet pour TOUS les modèles Intel x86-64
make arch-aarch64-7.2   # famille ARM 64-bit : rtd1296, rtd1619b, armada37xx
```
*(Astuce : le `TC_ARCH` d'un modèle ARM peut changer de version DSM — rtd1296 est servi par
`syno-aarch64-7.2`, pas un toolchain `7.3`. Compilez avec la version DSM dont le toolchain liste
votre arch ; le binaire tourne quand même sur DSM plus récent.)*

### 🚀 Installation & déploiement

1. **Installer le paquet** — télécharger le `.spk` correspondant à votre modèle depuis la page
   [**Releases**](../../releases), puis *Centre de paquets → Installation manuelle →* le sélectionner
   (confirmer l'avertissement de signature). Il démarre seul et sert les Maildir sur les ports hauts.
2. **Donner l'accès aux Maildir** — *Panneau de configuration → Dossier partagé → `homes` → Éditer →
   Permissions* : dans le menu déroulant, basculer sur **Utilisateur du système interne** (le compte
   de service `mailvault` n'apparaît *pas* dans la liste *Utilisateurs locaux*), puis accorder à
   **`mailvault`** la **Lecture/Écriture** (avec sous-dossiers) → couvre tous les comptes d'un coup.
3. **Installer la tâche root**
   ```bash
   scp scripts/mailvault-root-sync.sh user@nas:/volume1/scripts/
   ssh user@nas 'sudo chmod 755 /volume1/scripts/mailvault-root-sync.sh'
   ```
   Dans le **Planificateur de tâches DSM**, créer 2 tâches **root** lançant
   `/volume1/scripts/mailvault-root-sync.sh` : une **« au démarrage »** (repose les iptables, qui ne
   survivent pas au reboot) et une **quotidienne** (resync mots de passe + certificat). La lancer une
   fois manuellement.
4. **Accès externe (routeur)** — forwarder **TCP 993 → NAS:993** (IMAPS, requis) et éventuellement
   **TCP 465 → NAS:465** (submission). La règle iptables du NAS bascule vers les ports hauts — **les
   redirections routeur restent celles de Mail Server**.

### ⚙️ Configuration

- **Domaine** : régler `SUBJECT_DOMAIN` en tête de `scripts/mailvault-root-sync.sh`, ainsi que
  `postmaster_address` / le CN du cert placeholder dans `spk/mailvault/src/service-setup.sh`.
- **Comptes servis** : par défaut **tous** les utilisateurs home ayant un `.Maildir`. Pour restreindre,
  lister les utilisateurs voulus (un par ligne) dans `/var/packages/mailvault/var/imap-users.list`.
- **Ports d'écoute** : `10143` (IMAP), `10993` (IMAPS), `10587`/`10465` (submission).

### ⚠️ Limites

- **Pas d'envoi réel** : submission valide la config client mais n'envoie pas (usage = archive).
- **Sécurité** : les hashes `$6$` des comptes NAS sont copiés dans le `passwd-file` (0600, lisible par
  le seul user `mailvault`) — exposition équivalente à tout serveur mail à auth locale.
- **iptables non persistants** : d'où la tâche « au démarrage » obligatoire.
- **Build par architecture** : ce dépôt cible **apollolake (x86-64)**. Pour un NAS ARM
  (ex. `rtd1296`/aarch64), recompiler `cross/dovecot`.

---

## 📜 License & credits / Licence & crédits

[Dovecot](https://www.dovecot.org) (MIT / LGPLv2.1) · packaged with
[spksrc](https://github.com/SynoCommunity/spksrc) (SynoCommunity) · recipes & scripts in this repo:
free to reuse / libre réutilisation.
