PKG_NAME = dovecot
PKG_VERS = 2.3.21.1
PKG_EXT = tar.gz
PKG_DIST_NAME = dovecot-2.3.21.1.tar.gz
PKG_DIST_SITE = https://dovecot.org/releases/2.3
PKG_DIST_FILE = dovecot-2.3.21.1.tar.gz
PKG_DIR = dovecot-2.3.21.1

DEPENDS = cross/openssl3 cross/zlib

HOMEPAGE = https://www.dovecot.org
COMMENT  = Dovecot is an open source IMAP and POP3 email server for Linux/UNIX-like systems, written with security primarily in mind.
LICENSE  = GPLv2/LGPL

# Autoconf-based: makes spksrc inject --host/--build (real cross) + --prefix +
# --localstatedir. Without it, configure got no --prefix (libtool install path
# mismatch on plugins) and no cross triplet.
GNU_CONFIGURE = 1

# Minimal IMAP + submission server build.
CONFIGURE_ARGS  = --with-ssl=openssl
CONFIGURE_ARGS += --without-pam
CONFIGURE_ARGS += --without-ldap
CONFIGURE_ARGS += --without-sql
CONFIGURE_ARGS += --without-pgsql
CONFIGURE_ARGS += --without-mysql
CONFIGURE_ARGS += --without-sqlite
CONFIGURE_ARGS += --without-lucene
CONFIGURE_ARGS += --without-icu
CONFIGURE_ARGS += --without-libcap
CONFIGURE_ARGS += --without-libwrap
CONFIGURE_ARGS += --without-bzip2
CONFIGURE_ARGS += --without-lzma
CONFIGURE_ARGS += --without-lz4
CONFIGURE_ARGS += --without-zstd
CONFIGURE_ARGS += --with-zlib
CONFIGURE_ARGS += --disable-static

# Dovecot's configure runs target binaries for several feature checks which is
# impossible when cross-compiling.  Pre-seed the autoconf cache for these.
# (i_cv_signed_char is set conditionally below: no on ARM, yes on x86.)
CONFIGURE_ARGS += i_cv_signed_size_t=no
CONFIGURE_ARGS += i_cv_signed_time_t=yes
CONFIGURE_ARGS += i_cv_gmtoff_in_tm=yes
CONFIGURE_ARGS += i_cv_mmap_plays_with_write=yes
CONFIGURE_ARGS += i_cv_fd_passing=yes
CONFIGURE_ARGS += i_cv_c99_vsnprintf=yes
CONFIGURE_ARGS += i_cv_epoll_works=yes
CONFIGURE_ARGS += i_cv_typeof_works=yes
CONFIGURE_ARGS += lib_cv_va_copy=yes
CONFIGURE_ARGS += lib_cv___va_copy=yes
CONFIGURE_ARGS += lib_cv_va_val_copy=yes
# Run-tests sans alternative compile-only (enumeres depuis configure) :
CONFIGURE_ARGS += i_cv_posix_fallocate_works=yes
CONFIGURE_ARGS += i_cv_gmtime_max_time_t=40
CONFIGURE_ARGS += i_cv_gssapi_spnego=no
CONFIGURE_ARGS += ac_cv_lib_dl_dlopen=yes

include ../../mk/spksrc.common.mk

# char non signe sur ARM (ARMv5/v7/v8), signe sur x86. Les familles d'archi
# sont definies par spksrc.common.mk (inclus ci-dessus).
ifeq ($(findstring $(ARCH),$(ARMv5_ARCHS) $(ARMv7_ARCHS) $(ARMv7L_ARCHS) $(ARMv8_ARCHS)),$(ARCH))
CONFIGURE_ARGS += i_cv_signed_char=no
else
CONFIGURE_ARGS += i_cv_signed_char=yes
endif

include ../../mk/spksrc.cross-cc.mk
