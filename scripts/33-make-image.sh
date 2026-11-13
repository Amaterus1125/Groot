#!/bin/bash
# Host side (run with sudo from the repo root): rootfs in $LFS -> BIOS-bootable raw disk image.
# GRUB is installed with the host's grub-install (the LFS GRUB is built without a way to
# target a loop device from inside CI); grub.cfg is written by hand.
set -euo pipefail
LFS=${LFS:-/mnt/lfs}
IMG=${IMG:-lfs-13.1-x86_64.img}
SIZE=${SIZE:-8G}
DISK_ID=0x4c465331        # PARTUUID = 4c465331-01, same value as in 31-chroot-config-kernel.sh
MNT=/mnt/lfsimg

apt-get install -y --no-install-recommends grub-pc-bin grub2-common zstd e2fsprogs fdisk

LOOP=""
cleanup() {
  set +e
  mountpoint -q "$MNT" && umount "$MNT"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
}
trap cleanup EXIT

rm -f "$IMG" "$IMG.zst"
truncate -s "$SIZE" "$IMG"
sfdisk "$IMG" << EOF
label: dos
label-id: $DISK_ID
unit: sectors

start=2048, type=83, bootable
EOF

LOOP=$(losetup --find --show --partscan "$IMG")
udevadm settle || true
mkfs.ext4 -q -L lfsroot "${LOOP}p1"
mkdir -p "$MNT"
mount "${LOOP}p1" "$MNT"

echo "==> Copying rootfs..."
tar -C "$LFS" --numeric-owner \
    --exclude=./sources --exclude=./tools \
    --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./run/*' \
    -cf - . | tar -C "$MNT" --numeric-owner -xpf -
mkdir -p "$MNT"/{dev,proc,sys,run,boot}

echo "==> Fixing ownership (earlier stages chown'ed files to the runner user)..."
find "$MNT" -xdev -uid +999 -exec chown -h 0 {} +
find "$MNT" -xdev -gid +999 -exec chgrp -h 0 {} +
# that chown also dropped the setuid bits: restore them
for f in su passwd newgrp gpasswd chfn chsh expiry chage mount umount; do
  for d in usr/bin usr/sbin; do
    if [ -f "$MNT/$d/$f" ]; then chmod 4755 "$MNT/$d/$f"; fi
  done
done

KIMG=$(ls "$MNT"/boot/vmlinuz-* | head -n 1)
KNAME=$(basename "$KIMG")
echo "==> Kernel: $KNAME"

echo "==> Installing GRUB (BIOS)..."
mkdir -p "$MNT/boot/grub"
grub-install --target=i386-pc --boot-directory="$MNT/boot" \
             --modules="part_msdos ext2" --no-floppy "$LOOP"
cat > "$MNT/boot/grub/grub.cfg" << EOF
set default=0
set timeout=3

insmod part_msdos
insmod ext2

set gfxpayload=1024x768x32

menuentry "LFS 13.1 (systemd)" {
  set root=(hd0,msdos1)
  linux /boot/$KNAME root=PARTUUID=${DISK_ID#0x}-01 ro console=tty0 console=ttyS0,115200
}
EOF

cp "$KIMG" "./$KNAME"
sync
umount "$MNT"
e2fsck -fn "${LOOP}p1" || true
losetup -d "$LOOP"; LOOP=""

echo "==> Compressing..."
zstd -T0 -12 -f "$IMG" -o "$IMG.zst"
rm -f "$IMG"
ls -lh "$IMG.zst"
if [ "$(stat -c %s "$IMG.zst")" -ge 2147483648 ]; then
  echo "WARNING: image is over the 2 GiB GitHub release asset limit; use the workflow artifact"
fi
