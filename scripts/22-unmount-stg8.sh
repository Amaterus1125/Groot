#!/bin/bash
# Stage 8: copy the chroot logs out and unmount everything. Safe to run even if the build failed.
set -uo pipefail
LFS=${LFS:-/mnt/lfs}      # sudo may not pass the variable through

if [ -d "$LFS/sources/chroot-stg8-logs" ]; then
  WS=${GITHUB_WORKSPACE:-$PWD}
  mkdir -p "$WS/logs"
  cp -r "$LFS/sources/chroot-stg8-logs/." "$WS/logs/"
  chmod -R a+rX "$WS/logs"
fi

for m in dev/shm dev/pts run sys proc dev; do
  if mountpoint -q "$LFS/$m"; then
    umount -v "$LFS/$m" || umount -vl "$LFS/$m"
  fi
done

echo "remaining mounts under $LFS:"
mount | grep " $LFS" || echo "none"
exit 0
