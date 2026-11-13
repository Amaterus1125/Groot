#!/bin/bash
set -euo pipefail
export LOGS="/tmp/logs"
mkdir -p "$LOGS"
export S="/sources"

# --- Build Functions ---

pkg_sqlite() {
  cd "$S"
  ls sqlite-*.tar.* | grep -v doc | xargs tar -xf
  cd sqlite-*/
  ./configure --prefix=/usr --disable-static \
    --enable-fts4 --enable-fts5 \
    CPPFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_UNLOCK_NOTIFY=1 -DSQLITE_ENABLE_DBSTAT_VTAB=1 -DSQLITE_SECURE_DELETE=1"
  make LDFLAGS.rpath=""
  make install
  cd "$S"; rm -rf sqlite-*/
}

pkg_mpdecimal() {
  cd "$S"; tar -xf mpdecimal-*.tar.*; cd mpdecimal-*/
  ./configure --prefix=/usr \
    --disable-static \
    --docdir=/usr/share/doc/mpdecimal-4.0.1
  make
  make install
  cd "$S"; rm -rf mpdecimal-*/
}

pkg_python3() {
  cd "$S"; tar -xf Python-*.tar.*; cd Python-*/
  # LFS 13.1: required so the ssl/hashlib modules build against OpenSSL 4
  ls ../Python-*-openssl_4-1.patch >/dev/null || { echo "MISSING Python openssl_4 patch in $S"; exit 1; }
  patch -Np1 -i ../Python-*-openssl_4-1.patch
  ./configure --prefix=/usr \
    --enable-shared \
    --with-system-expat \
    --enable-optimizations \
    --without-static-libpython
  make
  make install
  # make install normally installs pip; only fall back to ensurepip if it did not,
  # and fail here (with the real error in the log) instead of in every later package
  python3 -m pip --version || python3 -m ensurepip --upgrade
  python3 -m pip --version
  cat > /etc/pip.conf << "EOF"
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
  cd "$S"; rm -rf Python-*/
}

pkg_flitcore() {
  cd "$S"; tar -xf flit_core-*.tar.*; cd flit_core-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist flit_core
  cd "$S"; rm -rf flit_core-*/
}

pkg_packaging() {
  cd "$S"; tar -xf packaging-*.tar.*; cd packaging-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist packaging
  cd "$S"; rm -rf packaging-*/
}

pkg_wheel() {
  cd "$S"; tar -xf wheel-*.tar.*; cd wheel-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist wheel
  cd "$S"; rm -rf wheel-*/
}

pkg_setuptools() {
  cd "$S"; tar -xf setuptools-*.tar.*; cd setuptools-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist setuptools
  cd "$S"; rm -rf setuptools-*/
}

pkg_ninja() {
  cd "$S"; tar -xf ninja-*.tar.*; cd ninja-*/
  export NINJAJOBS=$(nproc)
  python3 configure.py --bootstrap
  install -vm755 ninja /usr/bin/
  install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
  install -vDm644 misc/zsh-completion /usr/share/zsh/site-functions/_ninja
  cd "$S"; rm -rf ninja-*/
}

pkg_meson() {
  cd "$S"; tar -xf meson-*.tar.*; cd meson-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist meson
  install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
  install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
  cd "$S"; rm -rf meson-*/
}

pkg_kmod() {
  cd "$S"; tar -xf kmod-*.tar.*; cd kmod-*/
  mkdir -p build; cd build
  meson setup --prefix=/usr --buildtype=release -D manpages=false ..
  ninja
  ninja install
  cd "$S"; rm -rf kmod-*/
}

pkg_coreutils() {
  cd "$S"; tar -xf coreutils-*.tar.*; cd coreutils-*/
  if ls ../coreutils-*-i18n-1.patch 1> /dev/null 2>&1; then
    patch -Np1 -i ../coreutils-*-i18n-1.patch
    autoreconf -fv
    automake -a -f
  fi
  FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
  make
  make install
  mv -v /usr/bin/chroot /usr/sbin || true
  mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8 || true
  sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8 || true
  cd "$S"; rm -rf coreutils-*/
}

pkg_diffutils() {
  cd "$S"; tar -xf diffutils-*.tar.*; cd diffutils-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf diffutils-*/
}

pkg_findutils() {
  cd "$S"; tar -xf findutils-*.tar.*; cd findutils-*/
  ./configure --prefix=/usr --localstatedir=/var/lib/locate
  make
  make install
  cd "$S"; rm -rf findutils-*/
}

pkg_groff() {
  cd "$S"; tar -xf groff-*.tar.*; cd groff-*/
  PAGE=A4 ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf groff-*/
}

pkg_grub() {
  cd "$S"; tar -xf grub-*.tar.*; cd grub-*/
  sed -i 's/--image-base/--nonexist-linker-option/' configure
  ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror
  make
  make install
  cd "$S"; rm -rf grub-*/
}

pkg_gzip() {
  cd "$S"; tar -xf gzip-*.tar.*; cd gzip-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf gzip-*/
}

pkg_iproute2() {
  cd "$S"; tar -xf iproute2-*.tar.*; cd iproute2-*/
  sed -i /ARPD/d Makefile
  rm -fv man/man8/arpd.8
  make NETNS_RUN_DIR=/run/netns
  make SBINDIR=/usr/sbin install
  cd "$S"; rm -rf iproute2-*/
}

pkg_kbd() {
  cd "$S"; tar -xf kbd-*.tar.*; cd kbd-*/
  if ls ../kbd-*-backspace-1.patch 1> /dev/null 2>&1; then
    patch -Np1 -i ../kbd-*-backspace-1.patch
  fi
  sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
  sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
  ./configure --prefix=/usr --disable-vlock
  make
  make install
  cd "$S"; rm -rf kbd-*/
}

pkg_libpipeline() {
  cd "$S"; tar -xf libpipeline-*.tar.*; cd libpipeline-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf libpipeline-*/
}

export -f pkg_sqlite pkg_mpdecimal pkg_python3 pkg_flitcore pkg_packaging pkg_wheel pkg_setuptools pkg_ninja pkg_meson pkg_kmod pkg_coreutils pkg_diffutils pkg_findutils pkg_groff pkg_grub pkg_gzip pkg_iproute2 pkg_kbd pkg_libpipeline

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
for p in sqlite mpdecimal python3 flitcore packaging wheel setuptools ninja meson kmod coreutils diffutils findutils groff grub gzip iproute2 kbd libpipeline; do
  run_pkg "$p" || FAILED_PKGS="$FAILED_PKGS $p"
done

cp -r $LOGS /sources/chroot-stg6-logs
if [ -n "$FAILED_PKGS" ]; then
  echo "==> Stage 6 finished WITH FAILURES:$FAILED_PKGS"
  exit 1
fi
echo "==> Stage 6 Chroot Build Complete!"
