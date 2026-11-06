#!/bin/bash
set -euo pipefail
LFS=/mnt/lfs

echo "Moving Stage 5 logs to workspace..."
mkdir -p logs
cp -r $LFS/sources/chroot-stg5-logs/* logs/ || true

echo "Unmounting virtual file systems..."
mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm || true
umount $LFS/dev/pts || true
umount $LFS/{sys,proc,run,dev} || true
