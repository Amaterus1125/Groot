#!/bin/bash
# Stage 8, runs INSIDE the chroot: libffi rebuild + small BLFS set (CA bundle, curl, git, openssh).
set -euo pipefail
export LOGS="/sources/chroot-stg8-logs"   # inside /sources, which is not packed into the tarball
mkdir -p "$LOGS"
export S="/sources"

echo "==> Versions already present in the system:"
(gcc --version     | head -n 1) || echo "(gcc missing)"
(perl -v           | sed -n 2p) || echo "(perl missing)"
(python3 --version | head -n 1) || echo "(python3 missing)"
(vim --version     | head -n 1) || echo "(vim missing)"

# --- Build functions ---

# libffi was built with --with-gcc-arch=native on the runner CPU. Rebuild for a generic ARMv8-A
# baseline so it does not crash with "illegal instruction" on a different CPU (for example a phone).
pkg_libffi() {
  cd "$S"; tar -xf libffi-*.tar.*; cd libffi-*/
  ./configure --prefix=/usr --disable-static --with-gcc-arch=armv8-a
  make
  make install
  cd "$S"; rm -rf libffi-*/
}

# CA bundle: Mozilla's list from curl.se (checked against its SHA-256 on the host), used instead of
# BLFS make-ca to avoid pulling in p11-kit and libtasn1. OpenSSL finds /etc/ssl/cert.pem by default.
pkg_cacerts() {
  install -v -d -m755 /etc/ssl/certs
  install -v -m644 "$S/cacert.pem" /etc/ssl/cert.pem
  ln -sfv ../cert.pem /etc/ssl/certs/ca-bundle.crt
  ln -sfv ../cert.pem /etc/ssl/certs/ca-certificates.crt
  test -s /etc/ssl/cert.pem
}

pkg_curl() {
  cd "$S"; tar -xf curl-*.tar.*; cd curl-*/
  # BLFS recommends libpsl and nghttp2; they are not part of this small set, so libpsl is disabled.
  ./configure --prefix=/usr --disable-static --with-openssl \
              --with-ca-bundle=/etc/ssl/cert.pem --without-libpsl
  make
  make install
  rm -rf docs/examples/.deps
  find docs \( -name 'Makefile*' -o -name '*.1' -o -name '*.3' -o -name CMakeLists.txt \) -delete
  cp -R docs -T "/usr/share/doc/$(basename "$PWD")"
  curl --version | head -n 3
  curl --version | grep -qi openssl
  cd "$S"; rm -rf curl-*/
}

pkg_git() {
  cd "$S"; tar -xf git-*.tar.*; cd git-*/
  ./configure --prefix=/usr --with-gitconfig=/etc/gitconfig \
              --with-python=python3 --with-libpcre2
  # No Tk in this system, so skip gitk/git-gui. NO_RUST is ignored by versions that do not use it.
  make NO_TCLTK=1 NO_RUST=1
  make NO_TCLTK=1 NO_RUST=1 perllibdir=/usr/lib/perl5/5.42/site_perl install
  git --version
  cd "$S"; rm -rf git-*/
}

pkg_openssh() {
  cd "$S"; tar -xf openssh-*.tar.*; cd openssh-*/
  install -v -g sys -m700 -d /var/lib/sshd
  getent group sshd  >/dev/null || groupadd -g 50 sshd
  getent passwd sshd >/dev/null || useradd -c 'sshd PrivSep' -d /var/lib/sshd \
                                           -g sshd -s /bin/false -u 50 sshd
  ./configure --prefix=/usr                            \
              --sysconfdir=/etc/ssh                    \
              --with-privsep-path=/var/lib/sshd        \
              --with-default-path=/usr/bin             \
              --with-superuser-path=/usr/sbin:/usr/bin \
              --with-pid-dir=/run
  make
  make install
  install -v -m755    contrib/ssh-copy-id /usr/bin
  install -v -m644    contrib/ssh-copy-id.1 /usr/share/man/man1
  install -v -m755 -d "/usr/share/doc/$(basename "$PWD")"
  install -v -m644    INSTALL LICENCE OVERVIEW README* "/usr/share/doc/$(basename "$PWD")"
  # "make install" generates SSH host keys. Never ship them: every copy of a public tarball would
  # share the same private keys. Generate fresh ones on first use with: ssh-keygen -A
  rm -fv /etc/ssh/ssh_host_*
  ssh -V
  cd "$S"; rm -rf openssh-*/
}

# Lock the root password (stage 5 had set it to "root", which is public in a public release),
# and clear leftover temporary files.
pkg_finalize() {
  passwd -l root
  rm -rf /tmp/* /var/tmp/* /root/.bash_history
}

export -f pkg_libffi pkg_cacerts pkg_curl pkg_git pkg_openssh pkg_finalize

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
for p in libffi cacerts curl git openssh finalize; do
  run_pkg "$p" || FAILED_PKGS="$FAILED_PKGS $p"
done

if [ -n "$FAILED_PKGS" ]; then
  echo "==> Stage 8 finished WITH FAILURES:$FAILED_PKGS"
  exit 1
fi
echo "==> Stage 8 Chroot Build Complete!"s
