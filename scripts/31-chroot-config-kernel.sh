#!/bin/bash
# LFS 13.1-systemd, chapter 9 (system configuration) + chapter 10 (fstab, kernel).
# Runs INSIDE the chroot. GRUB / disk image is done on the host by 33-make-image.sh.
set -euo pipefail
export LOGS="/sources/chroot-boot-logs"
mkdir -p "$LOGS"
export S="/sources"
# Must match DISK_ID in scripts/33-make-image.sh: the kernel finds / via PARTUUID=<id>-01
DISK_ID=4c465331

# ---------------------------------------------------------------- chapter 9
pkg_config() {
  # 9.2.3 hostname, 9.2.4 hosts (localhost is handled by nss-myhostname)
  echo "lfs" > /etc/hostname
  cat > /etc/hosts << "EOF"
# Begin /etc/hosts
::1 ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
# End /etc/hosts
EOF

  # 9.2.1.3 DHCP via systemd-networkd (any en* interface, so it works for QEMU's NIC)
  mkdir -pv /etc/systemd/network
  cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=en*

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF

  # 9.2.2.1 systemd-resolved: resolv.conf is the stub symlink (created at boot if absent)
  rm -f /etc/resolv.conf
  ln -sv ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  # 9.6 console
  echo FONT=Lat2-Terminus16 > /etc/vconsole.conf

  # 9.7 locale (only use en_US.UTF-8 if glibc actually has it)
  if locale -a 2>/dev/null | grep -qix 'en_US.utf-\?8'; then LOC=en_US.UTF-8; else LOC=C.UTF-8; fi
  echo "LANG=$LOC" > /etc/locale.conf
  cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
      export $key
    fi
  done
fi

# End /etc/profile
EOF

  # 9.8 inputrc
  cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# uncomment for history search mode with up/down
# "\e[A": history-search-backward
# "\e[B": history-search-forward

# End /etc/inputrc
EOF

  # 9.9 shells
  cat > /etc/shells << "EOF"
# Begin /etc/shells
/bin/sh
/bin/bash
# End /etc/shells
EOF

  # release info
  echo 13.1-systemd > /etc/lfs-release
  cat > /etc/os-release << "EOF"
NAME="Linux From Scratch"
VERSION="13.1-systemd"
ID=lfs
PRETTY_NAME="Linux From Scratch 13.1-systemd"
HOME_URL="https://www.linuxfromscratch.org/lfs/"
EOF

  # first boot must generate its own machine-id (empty file = uninitialised)
  : > /etc/machine-id

  # test-image root password: CHANGE IT with passwd after the first login
  echo 'root:lfs' | chpasswd

  # 10.2 fstab (root is the only partition of the image)
  cat > /etc/fstab << EOF
# Begin /etc/fstab
# file system     mount-point  type  options   dump  fsck
PARTUUID=${DISK_ID}-01  /       ext4  defaults  1     1
# End /etc/fstab
EOF
}

# ---------------------------------------------------------------- chapter 10
pkg_kernel() {
  cd "$S"; tar -xf linux-[0-9]*.tar.xz; cd linux-[0-9]*/
  make mrproper
  make defconfig
  make kvm_guest.config        # virtio disk/net etc. for QEMU

  cfg=./scripts/config
  # --- the book's section 10.3 list (all set at once, so the menuconfig ordering note
  #     about PCI_MSI -> IRQ_REMAP -> X86_X2APIC does not matter; olddefconfig resolves it)
  for o in PSI CGROUPS MEMCG CGROUP_SCHED RELOCATABLE RANDOMIZE_BASE \
           STACKPROTECTOR STACKPROTECTOR_STRONG NET INET IPV6 \
           DEVTMPFS DEVTMPFS_MOUNT DMIID SYSFB_SIMPLEFB TTY \
           DRM DRM_PANIC DRM_FBDEV_EMULATION DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE \
           INOTIFY_USER TMPFS TMPFS_POSIX_ACL \
           PCI PCI_MSI IOMMU_SUPPORT IRQ_REMAP X86_X2APIC BLK_DEV_NVME; do
    $cfg --enable $o
  done
  $cfg --set-str DRM_PANIC_SCREEN kmsg
  for o in WERROR PSI_DEFAULT_DISABLED IKHEADERS RT_GROUP_SCHED UEVENT_HELPER \
           FW_LOADER_USER_HELPER LEGACY_TIOCSTI; do
    $cfg --disable $o
  done

  # --- extras for a QEMU guest / systemd, not in the book's list. Everything is built in
  #     (no initramfs). Module signing and the key rings are turned off because their kernel
  #     build tools would be compiled against OpenSSL 4. No BTF (needs pahole).
  for o in SIGNALFD TIMERFD EPOLL FHANDLE AUTOFS_FS TMPFS_XATTR SECCOMP SECCOMP_FILTER UNIX \
           PACKET PROC_FS SYSFS NAMESPACES UTS_NS IPC_NS USER_NS PID_NS NET_NS \
           CRYPTO_USER_API_HASH CRYPTO_HMAC CRYPTO_SHA256 BLK_DEV_BSG \
           EXT4_FS EXT4_FS_POSIX_ACL EXT4_FS_SECURITY \
           VIRTIO_BLK VIRTIO_PCI VIRTIO_NET E1000 E1000E \
           SERIAL_8250 SERIAL_8250_CONSOLE; do
    $cfg --enable $o
  done
  for o in MODULE_SIG SYSTEM_TRUSTED_KEYRING SYSTEM_REVOCATION_LIST \
           SECONDARY_TRUSTED_KEYRING DEBUG_INFO_BTF; do
    $cfg --disable $o
  done
  make olddefconfig

  # fail early (before the long build) if something the book requires did not stick
  missing=""
  for o in PSI CGROUPS MEMCG CGROUP_SCHED NET INET IPV6 DEVTMPFS DEVTMPFS_MOUNT \
           INOTIFY_USER TMPFS TMPFS_POSIX_ACL PCI EXT4_FS VIRTIO_BLK VIRTIO_PCI; do
    grep -q "^CONFIG_$o=y" .config || missing="$missing $o"
  done
  for o in WERROR PSI_DEFAULT_DISABLED RT_GROUP_SCHED UEVENT_HELPER \
           FW_LOADER_USER_HELPER LEGACY_TIOCSTI; do
    grep -q "^CONFIG_$o=y" .config && missing="$missing (not $o)"
  done
  if [ -n "$missing" ]; then
    echo "KERNEL CONFIG: wrong or missing options:$missing"
    echo "compare with section 10.3 of the book"
    exit 1
  fi
  # not fatal, but tell me about it
  for o in RELOCATABLE RANDOMIZE_BASE STACKPROTECTOR_STRONG DMIID SYSFB_SIMPLEFB TTY DRM \
           DRM_PANIC DRM_FBDEV_EMULATION DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE X86_X2APIC \
           PCI_MSI IRQ_REMAP BLK_DEV_NVME SIGNALFD TIMERFD EPOLL FHANDLE AUTOFS_FS \
           TMPFS_XATTR SECCOMP SECCOMP_FILTER NAMESPACES USER_NS NET_NS \
           CRYPTO_USER_API_HASH CRYPTO_HMAC CRYPTO_SHA256 E1000 VIRTIO_NET \
           SERIAL_8250_CONSOLE; do
    grep -qE "^CONFIG_$o=(y|m)" .config || echo "WARNING: CONFIG_$o is not enabled"
  done
  grep -E '^CONFIG_DRM_PANIC_SCREEN=' .config || echo "WARNING: DRM_PANIC_SCREEN not set"

  make
  make INSTALL_MOD_STRIP=1 modules_install

  # file names as in the book (10.3)
  KVER=$(make -s kernelrelease)
  install -d /boot
  cp -iv arch/x86/boot/bzImage "/boot/vmlinuz-$KVER-lfs-13.1-systemd"
  cp -iv System.map "/boot/System.map-$KVER"
  cp -iv .config "/boot/config-$KVER"
  cp -r Documentation -T "/usr/share/doc/linux-$KVER"
  ls -l /boot
  cd "$S"; rm -rf linux-[0-9]*/
}

export -f pkg_config pkg_kernel
export DISK_ID

run_pkg() {
  echo "==> $1"
  set +e
  bash -euo pipefail -c "pkg_$1" > "$LOGS/$1.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "FAILED: $1 (exit $rc), last lines of log:"
    tail -n 80 "$LOGS/$1.log"
    exit 1
  fi
  echo "ok: $1"
}

for p in config kernel; do run_pkg "$p"; done
echo "==> Chapters 9-10 complete"
