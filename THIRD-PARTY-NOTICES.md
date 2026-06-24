# Third-party notices / Avis de tiers

The MailVault **source** in this repository (spksrc recipes, scripts, configuration, docs) is
licensed under the **MIT License** (see `LICENSE`).

The **`.spk` package built from it bundles** the following third-party components, each under its
own license:

| Component | Version | License | Source |
|---|---|---|---|
| **Dovecot** | 2.3.21.1 | MIT and LGPL-2.1 | https://www.dovecot.org / https://github.com/dovecot/core |
| **OpenSSL** | 3.x | Apache License 2.0 | https://www.openssl.org |
| **zlib** | 1.3.x | zlib License | https://zlib.net |

Built with the [spksrc](https://github.com/SynoCommunity/spksrc) framework (SynoCommunity).

---

- **Dovecot** is distributed by its authors under the **MIT** and **LGPL-2.1** licenses. MailVault
  links against it dynamically and does not modify its source. Full license text:
  https://github.com/dovecot/core/blob/main/COPYING
- **OpenSSL 3** is distributed under the **Apache License 2.0**. License and NOTICE:
  https://github.com/openssl/openssl/blob/master/LICENSE.txt
- **zlib** is distributed under the permissive **zlib License**: https://zlib.net/zlib_license.html

These notices are provided to satisfy the attribution requirements of the above licenses when the
`.spk` package is redistributed.

---

*FR — Le **code source** de MailVault dans ce dépôt (recettes spksrc, scripts, configuration, doc)
est sous **licence MIT** (`LICENSE`). Le **paquet `.spk`** qui en est issu **embarque** Dovecot
(MIT/LGPL-2.1), OpenSSL 3 (Apache-2.0) et zlib (zlib License), chacun sous sa propre licence. Ces
avis sont fournis pour respecter leurs exigences d'attribution lors de la redistribution du `.spk`.*
