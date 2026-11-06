#!/bin/bash
set -euo pipefail
export LOGS="/tmp/logs"
mkdir -p "$LOGS"
export S="/sources"
export BLD_TGT="$(uname -m)-unknown-linux-gnu"

# --- Build Functions ---

pkg_manpages() {
  cd "$S"; tar -xf man-pages-*.tar.*; cd man-pages-*/
  rm -v man3/crypt*
  make -R GIT=false prefix=/usr install
  cd "$S"; rm -rf man-pages-*/
}

pkg_iana() {
  cd "$S"; tar -xf iana-etc-*.tar.*; cd iana-etc-*/
  cp -v services protocols /etc
  cd "$S"; rm -rf iana-etc-*/
}

pkg_glibc() {
  cd "$S"; tar -xf glibc-*.tar.*; cd glibc-*/
  patch -Np1 -i ../glibc-fhs-1.patch
  mkdir -v build; cd build
  echo "rootsbindir=/usr/sbin" > configparms
  ../configure --prefix=/usr --build=$BLD_TGT --disable-werror --disable-nscd libc_cv_slibdir=/usr/lib --enable-stack-protector=strong --enable-kernel=5.4
  make
  touch /etc/ld.so.conf
  sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
  make install
  sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
  make localedata/install-locales
  
  cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf
passwd: files systemd
group: files systemd
shadow: files systemd
hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
# End /etc/nsswitch.conf
EOF

  cd ..
  mkdir -v tzdata; cd tzdata
  tar -xf "$S"/tzdata2025c.tar.gz
  ZONEINFO=/usr/share/zoneinfo
  mkdir -pv $ZONEINFO/{posix,right}
  for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
    zic -L /dev/null -d $ZONEINFO ${tz}
    zic -L /dev/null -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
  done
  cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
  zic -d $ZONEINFO -p America/New_York
  
  # Set localtime to Asia/Kolkata for you
  ln -sfv /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

  cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
include /etc/ld.so.conf.d/*.conf
EOF
  mkdir -pv /etc/ld.so.conf.d
  cd "$S"; rm -rf glibc-*/
}

pkg_zlib() {
  cd "$S"; tar -xf zlib-*.tar.*; cd zlib-*/
  ./configure --prefix=/usr 
  make
  make install
  rm -fv /usr/lib/libz.a
  cd "$S"; rm -rf zlib-*/
}

pkg_bzip2() {
  cd "$S"; tar -xf bzip2-*.tar.*; cd bzip2-*/
  patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
  sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
  sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
  make -f Makefile-libbz2_so
  make clean
  make
  make PREFIX=/usr install
  cp -av libbz2.so.* /usr/lib
  ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
  ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
  cp -v bzip2-shared /usr/bin/bzip2
  for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 $i; done
  rm -fv /usr/lib/libbz2.a
  cd "$S"; rm -rf bzip2-*/
}

pkg_xz() {
  cd "$S"; tar -xf xz-*.tar.*; cd xz-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --docdir=/usr/share/doc/xz-5.8.2
  make
  make install
  cd "$S"; rm -rf xz-*/
}

pkg_lz4() {
  cd "$S"; tar -xf lz4-*.tar.*; cd lz4-*/
  make BUILD_STATIC=no PREFIX=/usr
  make BUILD_STATIC=no PREFIX=/usr install
  cd "$S"; rm -rf lz4-*/
}

pkg_zstd() {
  cd "$S"; tar -xf zstd-*.tar.*; cd zstd-*/
  make prefix=/usr
  make prefix=/usr install
  rm -v /usr/lib/libzstd.a
  cd "$S"; rm -rf zstd-*/
}

pkg_file() {
  cd "$S"; tar -xf file-*.tar.*; cd file-*/
  ./configure --prefix=/usr --build=$BLD_TGT
  make
  make install
  cd "$S"; rm -rf file-*/
}

pkg_readline() {
  cd "$S"; tar -xf readline-*.tar.*; cd readline-*/
  sed -i '/MV.*old/d' Makefile.in
  sed -i '/{OLDSUFF}/c:' support/shlib-install
  sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
  
  sed -e '270a\
else\
  chars_avail = 1;' \
      -e '2881 i\
  result = -1;' \
      -i.orig input.c
      
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --with-curses --docdir=/usr/share/doc/readline-8.3
  make SHLIB_LIBS="-lncursesw"
  make install
  install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3 || true
  cd "$S"; rm -rf readline-*/
}

pkg_pcre2() {
  cd "$S"; tar -xf pcre2-*.tar.*; cd pcre2-*/
  ./configure --prefix=/usr --build=$BLD_TGT --docdir=/usr/share/doc/pcre2-10.47 \
    --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 \
    --enable-pcre2grep-libz --enable-pcre2grep-libbz2 \
    --enable-pcre2test-libreadline --disable-static
  make
  make install
  cd "$S"; rm -rf pcre2-*/
}

pkg_m4() {
  cd "$S"; tar -xf m4-*.tar.*; cd m4-*/
  ./configure --prefix=/usr --build=$BLD_TGT
  make
  make install
  cd "$S"; rm -rf m4-*/
}

pkg_bc() {
  cd "$S"; tar -xf bc-*.tar.*; cd bc-*/
  CC='gcc -std=c99' ./configure --prefix=/usr --build=$BLD_TGT -G -O3 -r
  make
  make install
  cd "$S"; rm -rf bc-*/
}

pkg_flex() {
  cd "$S"; tar -xf flex-*.tar.*; cd flex-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --docdir=/usr/share/doc/flex-2.6.4
  make
  make install
  ln -sv flex /usr/bin/lex
  ln -sv flex.1 /usr/share/man/man1/lex.1
  cd "$S"; rm -rf flex-*/
}

pkg_tcl() {
  cd "$S"; tar -xf tcl*-src.tar.*; cd tcl*/
  SRCDIR=$(pwd)
  cd unix
  ./configure --prefix=/usr --build=$BLD_TGT --mandir=/usr/share/man --disable-rpath
  make
  sed -e "s|$SRCDIR/unix|/usr/lib|" -e "s|$SRCDIR|/usr/include|" -i tclConfig.sh
  sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
      -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|" \
      -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|" \
      -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|" -i pkgs/tdbc1.1.12/tdbcConfig.sh
  sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
      -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|" \
      -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|" -i pkgs/itcl4.3.4/itclConfig.sh
  make install
  chmod -v u+w /usr/lib/libtcl8.6.so
  make install-private-headers
  ln -sfv tclsh8.6 /usr/bin/tclsh
  mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
  cd "$S"; rm -rf tcl*/
}

pkg_expect() {
  cd "$S"; tar -xf expect*.tar.*; cd expect*/
  patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
  ./configure --prefix=/usr --build=$BLD_TGT --with-tcl=/usr/lib --enable-shared --disable-rpath --mandir=/usr/share/man --with-tclinclude=/usr/include
  make
  make install
  ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
  cd "$S"; rm -rf expect*/
}

pkg_dejagnu() {
  cd "$S"; tar -xf dejagnu-*.tar.*; cd dejagnu-*/
  mkdir -v build; cd build
  ../configure --prefix=/usr --build=$BLD_TGT
  makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
  makeinfo --plaintext -o doc/dejagnu.txt ../doc/dejagnu.texi
  make install
  install -v -d -m755 /usr/share/doc/dejagnu-1.6.3
  install -v -m644 doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
  cd "$S"; rm -rf dejagnu-*/
}

pkg_pkgconf() {
  cd "$S"; tar -xf pkgconf-*.tar.*; cd pkgconf-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --docdir=/usr/share/doc/pkgconf-2.5.1
  make
  make install
  ln -sv pkgconf /usr/bin/pkg-config
  ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
  cd "$S"; rm -rf pkgconf-*/
}

pkg_binutils() {
  cd "$S"; tar -xf binutils-*.tar.*; cd binutils-*/
  mkdir -v build; cd build
  ../configure --prefix=/usr --build=$BLD_TGT --sysconfdir=/etc --enable-ld=default \
    --enable-plugins --enable-shared --disable-werror \
    --enable-64-bit-bfd --enable-new-dtags --with-system-zlib \
    --enable-default-hash-style=gnu
  make tooldir=/usr
  make tooldir=/usr install
  rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a /usr/share/doc/gprofng/
  cd "$S"; rm -rf binutils-*/
}

pkg_gmp() {
  cd "$S"; tar -xf gmp-*.tar.*; cd gmp-*/
  sed -i '/long long t1/,+1s/()/(...)/' configure
  ./configure --prefix=/usr --build=$BLD_TGT --enable-cxx --disable-static --docdir=/usr/share/doc/gmp-6.3.0
  make
  make html
  make install
  make install-html
  cd "$S"; rm -rf gmp-*/
}

pkg_mpfr() {
  cd "$S"; tar -xf mpfr-*.tar.*; cd mpfr-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --enable-thread-safe --docdir=/usr/share/doc/mpfr-4.2.2
  make
  make html
  make install
  make install-html
  cd "$S"; rm -rf mpfr-*/
}

pkg_mpc() {
  cd "$S"; tar -xf mpc-*.tar.*; cd mpc-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --docdir=/usr/share/doc/mpc-1.3.1
  make
  make html
  make install
  make install-html
  cd "$S"; rm -rf mpc-*/
}

pkg_attr() {
  cd "$S"; tar -xf attr-*.tar.*; cd attr-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --sysconfdir=/etc --docdir=/usr/share/doc/attr-2.5.2
  make
  make install
  cd "$S"; rm -rf attr-*/
}

pkg_acl() {
  cd "$S"; tar -xf acl-*.tar.*; cd acl-*/
  ./configure --prefix=/usr --build=$BLD_TGT --disable-static --docdir=/usr/share/doc/acl-2.3.2
  make
  make install
  cd "$S"; rm -rf acl-*/
}

export -f pkg_manpages pkg_iana pkg_glibc pkg_zlib pkg_bzip2 pkg_xz pkg_lz4 pkg_zstd pkg_file pkg_readline pkg_pcre2 pkg_m4 pkg_bc pkg_flex pkg_tcl pkg_expect pkg_dejagnu pkg_pkgconf pkg_binutils pkg_gmp pkg_mpfr pkg_mpc pkg_attr pkg_acl

run_pkg() {
  echo "==> Building $1..."
  set +e
  bash -euo pipefail -c "pkg_$1" > "$LOGS/$1.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "FAILED: $1 (exit $rc), last lines of log:"
    tail -n 80 "$LOGS/$1.log"
    exit 1
  fi
  echo "ok: $1"
}

# The ordered list of Chapter 8 packages for Stage 4
for p in manpages iana glibc zlib bzip2 xz lz4 zstd file readline pcre2 m4 bc flex tcl expect dejagnu pkgconf binutils gmp mpfr mpc attr acl; do
  run_pkg "$p"
done

# Save logs to /sources so we can view them via artifacts
cp -r $LOGS /sources/chroot-stg4-logs
echo "==> Stage 4 Chroot Build Complete!"
