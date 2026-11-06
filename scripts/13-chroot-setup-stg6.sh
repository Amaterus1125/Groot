#!/bin/bash
set -euo pipefail
LFS=/mnt/lfs

echo "==> Preparing Virtual Kernel File Systems..."
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

echo "==> Copying build script..."
cp scripts/14-chroot-build-stg6.sh $LFS/sources/
chmod +x $LFS/sources/14-chroot-build-stg6.sh

echo "==> Entering Chroot for Stage 6..."
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-xterm}" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" \
    /bin/bash --login -c "/sources/14-chroot-build-stg6.sh"
