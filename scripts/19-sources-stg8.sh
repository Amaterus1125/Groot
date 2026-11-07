#!/bin/bash
# Stage 8: extra sources for the small BLFS set. Runs on the host, not in the chroot.
# (libffi comes from the normal scripts/01-sources.sh, which the workflow runs first.)
set -euo pipefail
LFS=${LFS:-/mnt/lfs}      # sudo may not pass the variable through
cd "$LFS/sources"

# fetch <url> <md5> : download if missing or wrong, then verify
fetch() {
  local url=$1 md5=$2 f
  f=$(basename "$url")
  if [ -f "$f" ] && echo "$md5  $f" | md5sum -c --quiet -; then
    echo "have $f"
    return 0
  fi
  rm -f "$f"
  wget -nv -O "$f" "$url"
  echo "$md5  $f" | md5sum -c -
}

# versions and MD5 sums as published in the BLFS book
fetch https://curl.se/download/curl-8.23.0.tar.xz                              f28835fef6d894c0559d5dbc0c071760
fetch https://www.kernel.org/pub/software/scm/git/git-2.53.0.tar.xz            3857733169a6443e48d20c75ee32f732
fetch https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.6p2.tar.gz 24fb1fb2c6ee537582c566dd9ed0e7cb

# Mozilla CA bundle from curl.se, checked against the SHA-256 curl.se publishes
wget -nv -O cacert.pem        https://curl.se/ca/cacert.pem
wget -nv -O cacert.pem.sha256 https://curl.se/ca/cacert.pem.sha256
want=$(cut -d' ' -f1 cacert.pem.sha256)
echo "$want  cacert.pem" | sha256sum -c -
rm -f cacert.pem.sha256

echo "stage 8 sources ready"
