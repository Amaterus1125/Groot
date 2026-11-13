#!/bin/bash
# Enter the chroot and run chapter 9 + 10 (config + kernel)
set -euo pipefail
LFS=/mnt/lfs

echo "==> Preparing Virtual Kernel File Systems..."
mkdir -pv $LFS/{dev,proc,sys,run}
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
cp scripts/31-chroot-config-kernel.sh $LFS/sources/
chmod +x $LFS/sources/31-chroot-config-kernel.sh

echo "==> Entering Chroot for chapters 9-10..."
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-xterm}" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" \
    /bin/bash --login -c "/sources/31-chroot-config-kernel.sh"
