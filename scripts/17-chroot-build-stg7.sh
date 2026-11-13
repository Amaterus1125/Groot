#!/bin/bash
set -euo pipefail
# Save logs directly to sources so they survive /tmp cleanup
export LOGS="/sources/chroot-stg7-logs"
mkdir -p "$LOGS"
export S="/sources"

# --- Build Functions ---

pkg_make() {
  cd "$S"; tar -xf make-*.tar.*; cd make-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf make-*/
}

pkg_patch() {
  cd "$S"; tar -xf patch-*.tar.*; cd patch-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf patch-*/
}

pkg_tar() {
  cd "$S"; tar -xf tar-*.tar.*; cd tar-*/
  # LFS 13.1: required, tar-1.35 does not compile against acl-2.4.0 without it
  ls ../tar-1.35-acl_fix-1.patch >/dev/null || { echo "MISSING tar acl_fix patch in $S"; exit 1; }
  patch -Np1 -i ../tar-1.35-acl_fix-1.patch
  FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf tar-*/
}

pkg_texinfo() {
  cd "$S"; tar -xf texinfo-*.tar.*; cd texinfo-*/
  sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm || true   # Perl>=5.42 warning fix, may be unneeded in 7.3
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf texinfo-*/
}

pkg_vim() {
  cd "$S"; tar -xf vim-*.tar.*; cd vim-*/
  echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
  ./configure --prefix=/usr
  make
  make install
  ln -sv vim /usr/bin/vi || true
  for L in /usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1 || true
  done
  cat > /etc/vimrc << "EOF"
"Begin /etc/vimrc
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1
set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
set background=dark
endif
"End /etc/vimrc
EOF
  cd "$S"; rm -rf vim-*/
}

pkg_markupsafe() {
  # Use case-insensitive wildcard for lowercase PyPI tarballs
  cd "$S"; tar -xf *arkup*afe-*.tar.*; cd *arkup*afe-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist MarkupSafe
  cd "$S"; rm -rf *arkup*afe-*/
}

pkg_jinja2() {
  # Use case-insensitive wildcard for lowercase PyPI tarballs
  cd "$S"; tar -xf *inja2-*.tar.*; cd *inja2-*/
  python3 -m pip wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  python3 -m pip install --no-index --find-links dist Jinja2
  cd "$S"; rm -rf *inja2-*/
}

pkg_systemd() {
  cd "$S"; tar -xf systemd-2*.tar.*; cd systemd-*/
  sed -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' -i rules.d/50-udev-default.rules.in
  mkdir -p build; cd build
  meson setup --prefix=/usr --buildtype=release -D default-dnssec=no -D firstboot=false -D install-tests=false -D ldconfig=false -D sysusers=false -D rpmmacrosdir=no -D homed=disabled -D man=disabled -D mode=release -D pamconfdir=no -D dev-kvm-mode=0660 -D nobody-group=nogroup -D sysupdate=disabled -D ukify=disabled -D docdir=/usr/share/doc/systemd-261.2 ..
  ninja
  ninja install
  tar -xf $S/systemd-man-pages-*.tar.* --no-same-owner --strip-components=1 -C /usr/share/man || true
  systemd-machine-id-setup
  systemctl preset-all
  cd "$S"; rm -rf systemd-*/
}

pkg_dbus() {
  cd "$S"; tar -xf dbus-*.tar.*; cd dbus-*/
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
  ninja
  ninja install
  ln -sfv /etc/machine-id /var/lib/dbus || true
  cd "$S"; rm -rf dbus-*/
}

pkg_mandb() {
  cd "$S"; tar -xf man-db-*.tar.*; cd man-db-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/man-db-2.13.1 \
    --sysconfdir=/etc --disable-setuid --enable-cache-owner=bin \
    --with-browser=/usr/bin/lynx --with-vgrind=/usr/bin/vgrind --with-grap=/usr/bin/grap
  make
  make install
  cd "$S"; rm -rf man-db-*/
}

pkg_procpsng() {
  cd "$S"; tar -xf procps-ng-*.tar.*; cd procps-ng-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/procps-ng-4.0.7 \
    --disable-static --disable-kill --enable-watch8bit --with-systemd
  make
  make install
  cd "$S"; rm -rf procps-ng-*/
}

pkg_utillinux() {
  cd "$S"; tar -xf util-linux-*.tar.*; cd util-linux-*/
  ./configure --bindir=/usr/bin --libdir=/usr/lib --runstatedir=/run \
    --sbindir=/usr/sbin --disable-chfn-chsh --disable-login --disable-nologin \
    --disable-su --disable-setpriv --disable-runuser --disable-pylibmount \
    --disable-liblastlog2 --disable-static --without-python \
    ADJTIME_PATH=/var/lib/hwclock/adjtime --docdir=/usr/share/doc/util-linux-2.42.2
  make
  make install
  cd "$S"; rm -rf util-linux-*/
}

pkg_e2fsprogs() {
  cd "$S"; tar -xf e2fsprogs-*.tar.*; cd e2fsprogs-*/
  mkdir -v build; cd build
  ../configure --prefix=/usr --sysconfdir=/etc --enable-elf-shlibs \
    --disable-libblkid --disable-libuuid --disable-uuidd --disable-fsck
  make
  make install
  rm -fv /usr/lib/lib{com_err,e2p,ext2fs,ss}.a
  cd "$S"; rm -rf e2fsprogs-*/
}

pkg_stripping() {
  echo "Stripping binaries and libraries..."
  
  save_usrlib="$(cd /usr/lib; ls ld-linux*[^g] 2>/dev/null || true) libc.so.6 libthread_db.so.1 $(cd /usr/lib; ls libstdc++.so.6.0.[0-9]* 2>/dev/null || true) libitm.so.1.0.0 libatomic.so.1.2.0"
  if [ -f /usr/lib/libquadmath.so.0.0.0 ]; then
      save_usrlib="$save_usrlib libquadmath.so.0.0.0"
  fi

  cd /usr/lib
  for LIB in $save_usrlib; do
      if [ -f "$LIB" ]; then
          objcopy --only-keep-debug --compress-debug-sections=zstd $LIB $LIB.dbg
          cp $LIB /tmp/$LIB
          strip --strip-debug /tmp/$LIB
          objcopy --add-gnu-debuglink=$LIB.dbg /tmp/$LIB
          install -vm755 /tmp/$LIB /usr/lib
          rm /tmp/$LIB
      fi
  done

  online_usrbin="bash find strip"
  online_usrlib="$(cd /usr/lib; ls libbfd-*.so libsframe.so.*.*.* 2>/dev/null || true) libhistory.so.8.3 libncursesw.so.6.6 libm.so.6 libreadline.so.8.3 libz.so.1.3.2 libzstd.so.1.5.7 $(cd /usr/lib; find libnss*.so* -type f 2>/dev/null || true)"
  
  for BIN in $online_usrbin; do
      if [ -f "/usr/bin/$BIN" ]; then
          cp /usr/bin/$BIN /tmp/$BIN
          strip --strip-debug /tmp/$BIN
          install -vm755 /tmp/$BIN /usr/bin
          rm /tmp/$BIN
      fi
  done
  
  for LIB in $online_usrlib; do
      if [ -f "/usr/lib/$LIB" ]; then
          cp /usr/lib/$LIB /tmp/$LIB
          strip --strip-debug /tmp/$LIB
          install -vm755 /tmp/$LIB /usr/lib
          rm /tmp/$LIB
      fi
  done
  
  for i in $(find /usr/lib -type f -name \*.so* ! -name \*dbg) \
           $(find /usr/lib -type f -name \*.a) \
           $(find /usr/bin /usr/sbin /usr/libexec -type f); do
      case "$online_usrbin $online_usrlib $save_usrlib" in
          *$(basename $i)* ) ;;
          * ) strip --strip-debug $i 2>/dev/null || true ;;
      esac
  done
  echo "Stripping complete."
}

pkg_cleanup() {
  echo "Running final system cleanup..."
  find /tmp -mindepth 1 -maxdepth 1 ! -name 'logs' -exec rm -rf {} + || true
  find /usr/lib /usr/libexec -name \*.la -delete || true
  find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf || true
  userdel -r tester 2>/dev/null || true
  echo "Cleanup complete."
}

export -f pkg_make pkg_patch pkg_tar pkg_texinfo pkg_vim pkg_markupsafe pkg_jinja2 pkg_systemd pkg_dbus pkg_mandb pkg_procpsng pkg_utillinux pkg_e2fsprogs pkg_stripping pkg_cleanup

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
for p in make patch tar texinfo vim markupsafe jinja2 systemd dbus mandb procpsng utillinux e2fsprogs stripping cleanup; do
  run_pkg "$p" || FAILED_PKGS="$FAILED_PKGS $p"
done

if [ -n "$FAILED_PKGS" ]; then
  echo "==> Stage 7 finished WITH FAILURES:$FAILED_PKGS"
  exit 1
fi
echo "==> Stage 7 Chroot Build Complete!"
