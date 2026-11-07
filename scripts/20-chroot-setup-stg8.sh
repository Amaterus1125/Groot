#!/bin/bash
# Stage 8: prepare the virtual kernel filesystems and run the build script inside the chroot.
# Run with sudo from the repository root.
set -euo pipefail
LFS=${LFS:-/mnt/lfs}      # sudo may not pass the variable through
HERE=$(cd "$(dirname "$0")" && pwd)

echo "==> Preparing Virtual Kernel File Systems..."
mkdir -p "$LFS"/{dev,proc,sys,run}

mountpoint -q "$LFS/dev"     || mount -v --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
mountpoint -q "$LFS/proc"    || mount -vt proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"     || mount -vt sysfs sysfs "$LFS/sys"
mountpoint -q "$LFS/run"     || mount -vt tmpfs tmpfs "$LFS/run"
if [ -h "$LFS/dev/shm" ]; then
  install -v -d -m 1777 "$LFS$(realpath /dev/shm)"
else
  mountpoint -q "$LFS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
fi

echo "==> Copying build script..."
install -v -m755 "$HERE/21-chroot-build-stg8.sh" "$LFS/sources/21-chroot-build-stg8.sh"

echo "==> Entering Chroot for Stage 8..."
chroot "$LFS" /usr/bin/env -i \
  HOME=/root \
  TERM="${TERM:-xterm}" \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$(nproc)" \
  /bin/bash /sources/21-chroot-build-stg8.sh
