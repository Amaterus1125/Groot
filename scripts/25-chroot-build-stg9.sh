#!/bin/bash
# Stage 9, runs INSIDE the chroot: more everyday tools from BLFS.
# libevent, libarchive, tmux, nano, wget, rsync, tree, htop, which
set -euo pipefail
export LOGS="/sources/chroot-stg9-logs"   # inside /sources, which is not packed into the tarball
mkdir -p "$LOGS"
export S="/sources"

# --- Build functions ---
# (Version output uses "sed -n 1p" instead of "head -n 1": head can close the pipe early and
#  make the program die with SIGPIPE, which "set -o pipefail" would turn into a failure.)

# Needed by tmux
pkg_libevent() {
  cd "$S"; tar -xf libevent-*.tar.gz; cd libevent-*/
  sed -i 's/python/&3/' event_rpcgen.py
  ./configure --prefix=/usr --disable-static
  make
  make install
  cd "$S"; rm -rf libevent-*/
}

pkg_tmux() {
  cd "$S"; tar -xf tmux-*.tar.gz; cd tmux-*/
  ./configure --prefix=/usr
  make
  make install
  tmux -V
  cd "$S"; rm -rf tmux-*/
}

pkg_nano() {
  cd "$S"; tar -xf nano-*.tar.xz; cd nano-*/
  ./configure --prefix=/usr --sysconfdir=/etc --enable-utf8 \
              --docdir="/usr/share/doc/$(basename "$PWD")"
  make
  make install
  install -v -d -m755 "/usr/share/doc/$(basename "$PWD")"
  install -v -m644 doc/nano.html doc/sample.nanorc "/usr/share/doc/$(basename "$PWD")" || true
  nano --version | sed -n 1p
  cd "$S"; rm -rf nano-*/
}

# TLS certificates come from the CA bundle installed in stage 8 (/etc/ssl/cert.pem).
# libpsl is not installed, so it is disabled explicitly.
pkg_wget() {
  cd "$S"; tar -xf wget-*.tar.gz; cd wget-*/
  ./configure --prefix=/usr --sysconfdir=/etc --with-ssl=openssl --without-libpsl
  make
  make install
  grep -q '^ca_certificate' /etc/wgetrc 2>/dev/null || echo 'ca_certificate=/etc/ssl/cert.pem' >> /etc/wgetrc
  wget --version | sed -n 1p
  cd "$S"; rm -rf wget-*/
}

# Client use only (no rsync daemon user or unit). popt is not installed, so the bundled copy is used.
# libidn2 is not installed either, so IDN (internationalized host name) support is disabled.
pkg_rsync() {
  cd "$S"; tar -xf rsync-*.tar.gz; cd rsync-*/
  ./configure --prefix=/usr --disable-xxhash --without-included-zlib --disable-idn
  make
  make install
  rsync --version | sed -n 1p
  cd "$S"; rm -rf rsync-*/
}

# bsdtar, bsdcpio, bsdcat and bsdunzip; "unzip" becomes a symlink to bsdunzip, as in the book.
pkg_libarchive() {
  cd "$S"; tar -xf libarchive-*.tar.xz; cd libarchive-*/
  ./configure --prefix=/usr --disable-static
  make
  make install
  ln -sfv bsdunzip /usr/bin/unzip
  bsdtar --version
  cd "$S"; rm -rf libarchive-*/
}

pkg_tree() {
  cd "$S"; tar -xf tree-*.tar.gz; cd tree-*/
  make
  make PREFIX=/usr MANDIR=/usr/share/man install
  tree --version
  cd "$S"; rm -rf tree-*/
}

pkg_htop() {
  cd "$S"; tar -xf htop-*.tar.xz; cd htop-*/
  ./configure --prefix=/usr --sysconfdir=/etc
  make
  make install
  htop --version | sed -n 1p
  cd "$S"; rm -rf htop-*/
}

# A tiny "which", as suggested in the book instead of building the GNU package.
pkg_which() {
  cat > /usr/bin/which << "EOF"
#!/bin/bash
type -pa "$@" | head -n 1 ; exit ${PIPESTATUS[0]}
EOF
  chmod -v 755 /usr/bin/which
  chown -v root:root /usr/bin/which
  test "$(which ls)" = /usr/bin/ls
}

pkg_finalize() {
  rm -rf /tmp/* /var/tmp/* /root/.bash_history
}

export -f pkg_libevent pkg_tmux pkg_nano pkg_wget pkg_rsync pkg_libarchive pkg_tree pkg_htop pkg_which pkg_finalize

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
for p in libevent tmux nano wget rsync libarchive tree htop which finalize; do
  run_pkg "$p" || FAILED_PKGS="$FAILED_PKGS $p"
done

if [ -n "$FAILED_PKGS" ]; then
  echo "==> Stage 9 finished WITH FAILURES:$FAILED_PKGS"
  exit 1
fi
echo "==> Stage 9 Chroot Build Complete!"
