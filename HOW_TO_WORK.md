# LFS ARM64 Build Guide & Permissions Fix

This guide covers the execution of the 7-stage GitHub Actions pipeline used to cross-compile a Linux From Scratch (LFS) 13.0-systemd ARM64 root filesystem, along with the critical post-build permissions repair.

## Part 1: Running the 7-Stage Pipeline

The LFS build was split into 7 sequential GitHub Actions workflows to bypass the 6-hour runner timeout. 

1. **Sequential Execution**: Each stage relies on the tarball artifact produced by the previous stage. You must trigger them in order: `stage1` -> `stage2` -> `stage3` -> `stage4` -> `stage5` -> `stage6` -> `stage7`.
2. **The Restore & Pack Loop**: 
   * Each job starts by downloading the `.tar.zst` from the previous stage release.
   * It extracts it, builds a chunk of the LFS book, and then packs the updated `/mnt/lfs` directory into a new `.tar.zst` artifact.
3. **The Final Artifact**: Once `stage7` completes, the `stage7.tar.zst` file contains the complete, stripped, and finalized root filesystem. You do not need to retain the tarballs from Stages 1-6.

---

## Part 2: The Ownership Bug & Future Prevention

**The Problem:** 
In the `Restore` step of the pipeline, the following command was used:
`sudo chown -R $(id -u):$(id -g) $LFS`

This recursive `chown` stripped the `setuid` bits (e.g., `-rwsr-xr-x` became `-rwxr-xr-x`) from critical system binaries like `passwd` and `su`. It also assigned the ownership of the entire root filesystem to the `runner` user instead of `root`.

**The Fix for Future Builds:**
If you ever run this pipeline again from scratch, you must update the Restore step in every `.yml` workflow file (stages 2 through 7). 

**Change this:**
```yaml
sudo chown -R $(id -u):$(id -g) $LFS
```
**To this:**
```yaml
sudo chown $(id -u):$(id -g) $LFS $LFS/sources
```
*Why?* Only the root `$LFS` directory and the `sources` folder need to be writable by the GitHub runner to inject scripts and download tarballs. The `chroot` build scripts run as root and will handle the rest without destroying the existing file permissions.

---

## Part 3: Repairing the Existing Stage 7 Tarball (Arch Linux)

Since rebuilding takes hours, we can easily repair the permissions of your existing `stage7.tar.zst` directly on your Arch Linux host using a bash script.

### 1. Create the Repair Script
Save the following code as `fix-perms.sh` in your Documents folder:

```bash
#!/bin/bash
# fix-perms.sh - Repairs LFS rootfs permissions

TARGET=$1
if [ -z "$TARGET" ]; then
    echo "Usage: sudo bash $0 <lfs-root-dir>"
    exit 1
fi

# Find the UID of the 'runner' user (usually 1001 on GitHub Actions)
# We pull it by checking who owns the /sources directory, which is guaranteed to be the runner.
RUNNER_UID=$(stat -c '%u' "$TARGET/sources")

echo "==> Resetting ownership from runner (UID $RUNNER_UID) to root..."
find "$TARGET" -user "$RUNNER_UID" -exec chown 0:0 {} +

echo "==> Restoring setuid bits (4755)..."
# Shadow and util-linux programs requiring setuid
SETUID_PROGS="su passwd chage chfn chsh expiry gpasswd newgrp newuidmap newgidmap mount umount"
for prog in $SETUID_PROGS; do
    if [ -f "$TARGET/usr/bin/$prog" ]; then
        chmod 4755 "$TARGET/usr/bin/$prog"
        echo "  Set setuid on /usr/bin/$prog"
    fi
done

echo "==> Restoring setgid-tty bits (2755)..."
for prog in write wall; do
    if [ -f "$TARGET/usr/bin/$prog" ]; then
        chmod 2755 "$TARGET/usr/bin/$prog"
        echo "  Set setgid-tty on /usr/bin/$prog"
    fi
done

echo "==> Verifying..."
REMAINING=$(find "$TARGET" -user "$RUNNER_UID" | wc -l)
echo "Files still owned by runner ($RUNNER_UID): $REMAINING (Should be 0)"
```

### 2. Extract, Repair, and Repack
Open your terminal in the directory containing `stage7.tar.zst` and `fix-perms.sh`, and run the following commands:

```bash
# 1. Create the working directory
mkdir lfsroot

# 2. Extract using --numeric-owner to preserve the raw UID/GIDs from the archive
sudo tar --numeric-owner --zstd -xpf stage7.tar.zst -C lfsroot

# 3. Execute the repair script
sudo bash fix-perms.sh lfsroot

# 4. Repack into a clean, finalized tarball
sudo tar --numeric-owner -C lfsroot -I 'zstd -T0 -12' -cpf stage7-fixed.tar.zst .
```

*Note on limitations:* The `fix-perms.sh` script hardcodes the list of `setuid` programs based on standard Shadow and Util-linux installations. If you add additional packages in the future that require `setuid` (e.g., `sudo`), you will need to add them to the script.

---

## Part 4: Booting the Repaired System

You can now boot your fully repaired ARM64 root filesystem on your x86_64 Arch Linux host using `systemd-nspawn` and QEMU user-mode emulation.

```bash
# Ensure ARM64 emulation is installed and enabled on Arch
sudo pacman -S qemu-user-static qemu-user-static-binfmt
sudo systemctl restart systemd-binfmt.service

# Boot the repaired LFS environment
sudo systemd-nspawn -D lfsroot /bin/bash --login
```