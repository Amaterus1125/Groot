#!/bin/bash
set -euo pipefail
LFS=/mnt/lfs

echo "==> Changing Ownership to root..."
chown -R root:root $LFS/{usr,var,etc,tools}
case $(uname -m) in
  x86_64) chown -R root:root $LFS/lib64 ;;
esac

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

echo "==> [FIXED] Copying build script..."
mkdir -p $LFS/sources
cp scripts/05-chroot-build.sh $LFS/sources/
chmod +x $LFS/sources/05-chroot-build.sh

echo "==> Entering Chroot..."
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-xterm}" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login -c "/sources/05-chroot-build.sh"
