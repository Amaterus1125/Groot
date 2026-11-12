#!/bin/bash
set -euo pipefail
export LOGS="/tmp/logs"
mkdir -p "$LOGS"
export S="/sources"

# --- Build Functions ---

pkg_libcap() {
  cd "$S"; tar -xf libcap-*.tar.*; cd libcap-*/
  sed -i '/install -m.*STA/d' libcap/Makefile
  make prefix=/usr lib=lib
  make prefix=/usr lib=lib install
  cd "$S"; rm -rf libcap-*/
}

pkg_libxcrypt() {
  cd "$S"; tar -xf libxcrypt-*.tar.*; cd libxcrypt-*/
  sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
  ./configure --prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=no --disable-static --disable-failure-tokens
  make
  make install
  cd "$S"; rm -rf libxcrypt-*/
}

pkg_shadow() {
  cd "$S"; tar -xf shadow-*.tar.*; cd shadow-*/
  # drop the pages that man-pages already provides
  find man -name Makefile.in -exec sed -i -E \
    's#(man[0-9]/)?groups\.1 ##; s#(man[0-9]/)?getspnam\.3 ##; s#(man[0-9]/)?passwd\.5 ##' {} \;
  sed -e 's:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:' \
      -e 's:/var/spool/mail:/var/mail:' \
      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
      -i etc/login.defs
  touch /usr/bin/passwd
  ./configure --sysconfdir=/etc --disable-static --with-bcrypt --with-yescrypt --without-libbsd --disable-logind --with-group-name-max-length=32
  make
  make exec_prefix=/usr install
  make -C man install-man || true
  pwconv
  grpconv
  mkdir -p /etc/default
  useradd -D --gid 999
  echo "root:root" | chpasswd
  cd "$S"; rm -rf shadow-*/
}

pkg_gawk() {
  cd "$S"; tar -xf gawk-*.tar.*; cd gawk-*/
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr
  make
  rm -f /usr/bin/gawk-5.4.1
  make install
  ln -sfv gawk.1 /usr/share/man/man1/awk.1
  cd "$S"; rm -rf gawk-*/
}

pkg_gcc() {
  cd "$S"; tar -xf gcc-*.tar.*; cd gcc-*/
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
  esac
  mkdir -v build; cd build
  ../configure --prefix=/usr LD=ld --enable-languages=c,c++ \
    --enable-default-pie --enable-default-ssp --enable-host-pie \
    --enable-targets=all --disable-multilib --disable-bootstrap \
    --disable-fixincludes --with-system-zlib
  make
  make install
  chown -v -R root:root $(gcc -print-file-name=include) $(gcc -print-file-name=include-fixed)
  ln -svr /usr/bin/cpp /usr/lib
  ln -sv gcc.1 /usr/share/man/man1/cc.1
  ln -sfvr $(gcc -print-prog-name=liblto_plugin.so) /usr/lib/bfd-plugins/
  mkdir -pv /usr/share/gdb/auto-load/usr/lib
  mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib || true
  cd "$S"; rm -rf gcc-*/
}

pkg_ncurses() {
  cd "$S"; tar -xf ncurses-*.tar.*; cd ncurses-*/
  ./configure --prefix=/usr --mandir=/usr/share/man \
    --with-shared --without-debug --without-normal --with-cxx-shared \
    --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig
  make
  make DESTDIR=$PWD/dest install
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
  cp -av --remove-destination dest/* /
  for lib in ncurses form panel menu; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc /usr/lib/pkgconfig/${lib}.pc
  done
  ln -sfv libncursesw.so /usr/lib/libcurses.so
  cp -v -R doc -T /usr/share/doc/ncurses-6.6 || true
  cd "$S"; rm -rf ncurses-*/
}

pkg_sed() {
  cd "$S"; tar -xf sed-*.tar.*; cd sed-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf sed-*/
}

pkg_psmisc() {
  cd "$S"; tar -xf psmisc-*.tar.*; cd psmisc-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf psmisc-*/
}

pkg_gettext() {
  cd "$S"; tar -xf gettext-*.tar.*; cd gettext-*/
  ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext-1.0
  make
  make install
  chmod -v 0755 /usr/lib/preloadable_libintl.so
  cd "$S"; rm -rf gettext-*/
}

pkg_bison() {
  cd "$S"; tar -xf bison-*.tar.*; cd bison-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
  make
  make install
  cd "$S"; rm -rf bison-*/
}

pkg_grep() {
  cd "$S"; tar -xf grep-*.tar.*; cd grep-*/
  sed -i "s/echo/#echo/" src/egrep.sh
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf grep-*/
}

pkg_bash() {
  cd "$S"; tar -xf bash-*.tar.*; cd bash-*/
  ./configure --prefix=/usr --without-bash-malloc --with-installed-readline --docdir=/usr/share/doc/bash-5.3
  make
  make install
  cd "$S"; rm -rf bash-*/
}

pkg_libtool() {
  cd "$S"; tar -xf libtool-*.tar.*; cd libtool-*/
  ./configure --prefix=/usr
  make
  make install
  rm -fv /usr/lib/libltdl.a
  cd "$S"; rm -rf libtool-*/
}

pkg_gdbm() {
  cd "$S"; tar -xf gdbm-*.tar.*; cd gdbm-*/
  ./configure --prefix=/usr --disable-static --enable-libgdbm-compat
  make
  make install
  cd "$S"; rm -rf gdbm-*/
}

pkg_gperf() {
  cd "$S"; tar -xf gperf-*.tar.*; cd gperf-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
  make
  make install
  cd "$S"; rm -rf gperf-*/
}

pkg_expat() {
  cd "$S"; tar -xf expat-*.tar.*; cd expat-*/
  ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/expat-2.8.3
  make
  make install
  cd "$S"; rm -rf expat-*/
}

pkg_inetutils() {
  cd "$S"; tar -xf inetutils-*.tar.*; cd inetutils-*/
  sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
  ./configure --prefix=/usr --bindir=/usr/bin --localstatedir=/var --disable-logger --disable-whois --disable-rcp --disable-rexec --disable-rlogin --disable-rsh --disable-servers
  make
  make install
  mv -v /usr/bin/ifconfig /usr/sbin/ifconfig
  cd "$S"; rm -rf inetutils-*/
}

pkg_less() {
  cd "$S"; tar -xf less-*.tar.*; cd less-*/
  ./configure --prefix=/usr --sysconfdir=/etc
  make
  make install
  cd "$S"; rm -rf less-*/
}

pkg_perl() {
  cd "$S"; tar -xf perl-*.tar.*; cd perl-*/
  export BUILD_ZLIB=False
  export BUILD_BZIP2=0
  sh Configure -des \
    -D prefix=/usr \
    -D vendorprefix=/usr \
    -D privlib=/usr/lib/perl5/5.44/core_perl \
    -D archlib=/usr/lib/perl5/5.44/core_perl \
    -D sitelib=/usr/lib/perl5/5.44/site_perl \
    -D sitearch=/usr/lib/perl5/5.44/site_perl \
    -D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
    -D vendorarch=/usr/lib/perl5/5.44/vendor_perl \
    -D man1dir=/usr/share/man/man1 \
    -D man3dir=/usr/share/man/man3 \
    -D pager="/usr/bin/less -isR" \
    -D useshrplib \
    -D usethreads
  make
  make install
  unset BUILD_ZLIB BUILD_BZIP2
  cd "$S"; rm -rf perl-*/
}

pkg_autoconf() {
  cd "$S"; tar -xf autoconf-*.tar.*; cd autoconf-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf autoconf-*/
}

pkg_automake() {
  cd "$S"; tar -xf automake-*.tar.*; cd automake-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
  make
  make install
  cd "$S"; rm -rf automake-*/
}

pkg_openssl() {
  cd "$S"; tar -xf openssl-*.tar.*; cd openssl-*/
  ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
  make
  make INSTALL_LIBS= MANSUFFIX=ssl install
  mv -v /usr/share/doc/openssl /usr/share/doc/openssl-4.0.1 || true
  cd "$S"; rm -rf openssl-*/
}

pkg_libelf() {
  cd "$S"; tar -xf elfutils-*.tar.*; cd elfutils-*/
  ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
  make -C lib
  make -C libelf
  make -C libelf install
  install -vm644 config/libelf.pc /usr/lib/pkgconfig
  rm -f /usr/lib/libelf.a
  cd "$S"; rm -rf elfutils-*/
}

pkg_libffi() {
  cd "$S"; tar -xf libffi-*.tar.*; cd libffi-*/
  ./configure --prefix=/usr --disable-static --with-gcc-arch=native
  make
  make install
  cd "$S"; rm -rf libffi-*/
}

export -f pkg_libcap pkg_libxcrypt pkg_shadow pkg_gawk pkg_gcc pkg_ncurses pkg_sed pkg_psmisc pkg_gettext pkg_bison pkg_grep pkg_bash pkg_libtool pkg_gdbm pkg_gperf pkg_expat pkg_inetutils pkg_less pkg_perl pkg_autoconf pkg_automake pkg_openssl pkg_libelf pkg_libffi

run_pkg() {
  echo "==> Building $1..."
  set +e
  bash -euo pipefail -c "pkg_$1" > "$LOGS/$1.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "FAILED: $1 (exit $rc), last lines of log:"
    tail -n 80 "$LOGS/$1.log"
    return 1
  fi
  echo "ok: $1"
}

FAILED_PKGS=""
for p in libcap libxcrypt shadow gawk gcc ncurses sed psmisc gettext bison grep bash libtool gdbm gperf expat inetutils less perl autoconf automake openssl libelf libffi; do
  run_pkg "$p" || FAILED_PKGS="$FAILED_PKGS $p"
done

cp -r $LOGS /sources/chroot-stg5-logs
if [ -n "$FAILED_PKGS" ]; then
  echo "==> Stage 5 finished WITH FAILURES:$FAILED_PKGS"
  exit 1
fi
echo "==> Stage 5 Chroot Build Complete!"
