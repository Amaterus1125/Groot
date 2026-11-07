# Testing the LFS stage 7 root filesystem with chroot and proot

This document records, step by step, how the `stage7.tar.zst` root filesystem
(an LFS 13.0-systemd system built for **aarch64** on GitHub Actions) was
inspected, repaired and tested on an **x86_64 Arch Linux** PC. It also explains
how proot works, because proot is the same mechanism that will be used on a
phone through Termux.

Everything in the "What we did" sections was actually run. Anything not run is
marked **(untested)**.

---

## 1. Summary

| Item | Value |
|---|---|
| What was built | LFS 13.0-systemd root filesystem, glibc 2.43, GCC 15.2.0 |
| Target architecture | aarch64 (ARM64) |
| Built on | GitHub Actions, `ubuntu-24.04-arm` runner (native, no cross emulation) |
| Test machine | x86_64 PC running Arch Linux |
| Final artifact | `stage7.tar.zst` (about 313 MB compressed, about 1.48 GB unpacked) |
| Boots with its own kernel? | **No.** There is no kernel and no boot configuration (book chapters 9 and 10 are not done). It runs as a root filesystem under chroot or proot. |
| Tested on a real phone? | **No (untested).** Only on the x86_64 PC through ARM emulation. |

Result of the tests: the system extracts, enters, reports `aarch64`, and its
compiler (GCC 15.2.0) compiles and runs a program, both under a real
`chroot` and under `proot` without root.

---

## 2. How the pieces fit together

```
 GitHub Actions (ARM runner)           your x86_64 PC (Arch)
 ---------------------------           ------------------------------------------
 stage1 ... stage7 workflows   ->      download stage7.tar.zst
 each stage restores the               inspect -> extract -> repair permissions
 previous tarball, builds on           -> chroot test (needs root)
 top, packs everything again           -> proot test (no root, same as a phone)

 ARM programs run on x86 through qemu-user (binfmt_misc), so the PC can
 execute the aarch64 binaries inside the filesystem.
```

Two different tools are involved, and it helps to keep them apart:

- **qemu-user-static** translates ARM instructions to x86 one by one so that
  aarch64 programs can run on an x86 PC. This is only needed on the PC. A real
  ARM phone runs the programs natively and needs no emulator.
- **proot** lets an ordinary user run a program "inside" a directory as if it
  were the root of the filesystem, without root privileges and without a real
  `chroot`. It intercepts system calls with `ptrace` and rewrites file paths.
  This is what Termux uses on Android and what makes the project work on a
  phone with a locked bootloader.

proot does not give you a real kernel or a real init system. You get a shell
(and any programs you install), not a booted system with systemd.

---

## 3. Requirements

On the Arch PC:

- Arch Linux, x86_64, with `sudo`
- About 4 GB of free disk space (tarball, one root-owned copy, one proot copy)
- Packages: `zstd`, `tar`, `qemu-user-static`, `qemu-user-static-binfmt`
- For the proot part: `proot` from the **AUR** (it is not in the official
  repositories), plus `base-devel` and `git`

Files used from this project:

- `stage7.tar.zst`, downloaded from the `stage7` release of your repository
- `fix-perms.sh` (repairs ownership and setuid/setgid bits, see section 5)

---

## 4. Step 1: inspect the tarball before extracting

Look inside without extracting anything:

```bash
cd ~/Documents
tar --zstd -tvf stage7.tar.zst | grep -E '\./usr/bin/(su|passwd|mount)$'
```

What we saw on the original `stage7.tar.zst`:

```
-rwsr-xr-x root/root     84576 ... ./usr/bin/mount
-rwxr-xr-x runner/runner 168448 ... ./usr/bin/passwd
-rwxr-xr-x runner/runner  85864 ... ./usr/bin/su
```

This showed a real defect:

- `passwd` and `su` were owned by `runner/runner` (the GitHub Actions user)
  instead of `root/root`.
- They had lost the setuid bit (`s` in `-rwsr-xr-x`).
- `mount` was fine only because stage 7 had reinstalled it as root.

**Cause.** The restore step of the workflows ran
`sudo chown -R $(id -u):$(id -g) $LFS` on the whole tree after downloading the
previous stage. That gives every file to the runner user, and on Linux
`chown` clears the setuid and setgid bits of executables. The damage
accumulated over several stages.

**How to read the listing.** In the WinRAR/7-Zip view, most top-level entries
show size 0. That is normal:

- `boot dev home media mnt opt proc root run srv sys tools` are empty
  directories (mount points or intentionally emptied folders).
- `bin lib sbin` are symlinks to `usr/bin`, `usr/lib`, `usr/sbin`.
- The real content is in `usr` (about 1.44 GB), `tmp`, `etc` and `var`.

---

## 5. Step 2: repair ownership and setuid bits

Extract into a folder using the numeric ids stored in the archive (Arch has no
user called `runner`, so names would be meaningless):

```bash
mkdir lfsroot
sudo tar --numeric-owner --zstd -xpf stage7.tar.zst -C lfsroot
sudo bash fix-perms.sh lfsroot
```

What `fix-perms.sh` does:

1. Reads the runner's uid from `lfsroot/usr/bin/passwd` (it was `1001`).
2. Changes everything owned by that uid or gid back to root, using
   `chown --from` so that files that legitimately belong to other groups
   (for example group `tty`) are not flattened.
3. Restores `chmod 4755` on shadow's programs: `chage chfn chsh expiry gpasswd
   newgrp passwd su newuidmap newgidmap`, and on `mount` and `umount`.
4. Restores setgid `tty` (mode 2755, group 5) on `write` and `wall` if present.
5. Prints every setuid/setgid file and a count of files still owned by the
   runner (it must be `0`).

Output we got: all of the above were set, the final count was `0`, and `wall`
became `root:tty` setgid. `write` is not in this build, so it was skipped.
One file, `usr/libexec/dbus-daemon-launch-helper`, showed mode `---s--x---`
with group `18`. The script does not touch it. The book normally uses 4750 for
it, so `sudo chmod 4750 lfsroot/usr/libexec/dbus-daemon-launch-helper` is an
optional cleanup.

**Do not** run a blanket `chown -R 0:0 .` afterwards. It would reset the dbus
helper's group (18) to 0.

Repack the repaired tree and verify it:

```bash
sudo tar --numeric-owner -C lfsroot -I 'zstd -T0 -12' -cpf stage7-fixed.tar.zst .
tar --zstd -tvf stage7-fixed.tar.zst | grep -E '\./usr/bin/(su|passwd|mount)$'
```

Expected (and observed):

```
-rwsr-xr-x 0/0   85864 ... ./usr/bin/su
-rwsr-xr-x 0/0   84576 ... ./usr/bin/mount
-rwsr-xr-x 0/0  168448 ... ./usr/bin/passwd
```

**Keep `stage7-fixed.tar.zst`.** It is the good copy used for everything below.

---

## 6. Step 3: install ARM emulation on Arch

```bash
sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt
sudo systemctl restart systemd-binfmt
ls /proc/sys/fs/binfmt_misc/ | grep aarch64
```

Expected: the last command prints `qemu-aarch64` (and `qemu-aarch64_be`).
That means the kernel will now hand any aarch64 program to QEMU automatically.

**If pacman hangs at 0 B/s** even though the network is fine, one mirror is
usually dead or slow. Put a reliable mirror first and retry:

```bash
sudo sed -i '1i Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' /etc/pacman.d/mirrorlist
sudo pacman -Syu qemu-user-static qemu-user-static-binfmt
```

(`-Syu` upgrades the whole system. Arch does not support refreshing the
package database and installing one package alone.) Do not interrupt pacman
with Ctrl+C. If it later reports `unable to lock database`, make sure no
pacman is running (`pgrep pacman`) and then `sudo rm /var/lib/pacman/db.lck`.

---

## 7. Step 4: test with a real chroot (needs root)

```bash
sudo mount --bind /dev lfsroot/dev
sudo mount -t proc proc lfsroot/proc
sudo chroot lfsroot /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
```

Inside, the prompt becomes `bash-5.3#`. Run:

```bash
uname -m
echo 'int main(){return 0;}' > /tmp/t.c && gcc /tmp/t.c -o /tmp/a.out && /tmp/a.out && echo gcc-works
```

Observed: `aarch64`, then `gcc-works`. The first compile pauses for a few
seconds because every instruction is emulated.

Leave and **always unmount before doing anything else**:

```bash
exit
sudo umount lfsroot/dev lfsroot/proc
mount | grep lfsroot        # must print nothing
```

> **Warning.** Never delete the folder while `/dev` or `/proc` is still
> mounted inside it. A recursive delete can reach your real `/dev`. Check
> `mount | grep lfsroot` first. Never point `chroot`, `chown` or the repair
> script at `/`. A typo in the path is the only real danger in this guide.

---

## 8. Step 5: install proot on Arch (AUR)

`pacman -S proot` fails with `target not found` because proot is not in the
official repositories. Build it from the AUR:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/proot.git
cd proot
less PKGBUILD            # read it first; AUR packages are unreviewed
makepkg -si
```

**The checksum failure we hit.** The build stopped with:

```
proot ... Passed
tracee_include.patch ... FAILED
py313-imp-importlib.patch ... FAILED
==> ERROR: One or more files did not pass the validity check!
```

The package downloads two patches from GitHub pull requests (proot PRs 397
and 398). GitHub generates `.patch` files on request, so their contents can
change slightly over time and the checksum stored in the package goes stale.
The proot source itself passed.

Before building anyway, read the two patches:

```bash
ls *.patch
less tracee_include.patch
less py313-imp-importlib.patch
```

What they contain (we checked both):

- `tracee_include.patch` adds one line, `#include "mem.h"`, to
  `src/tracee/tracee.c` to fix an implicit-declaration error with newer GCC.
- `py313-imp-importlib.patch` replaces the removed Python `imp` module with
  `importlib.util` in `src/extension/python/python_extension.py`.

Neither downloads or runs anything. If you ever see `curl`, `wget`, `base64`
or similar in a patch, stop. Then build with the already-downloaded files:

```bash
makepkg -si --skipchecksums
```

If the test phase (`check()`) fails, add `--nocheck`. Afterwards `cd ..` back
to your working folder. The build also pulls in some build-only packages
(such as `python-docutils`), which are harmless.

---

## 9. Step 6: test with proot (no root), the same way a phone works

### 9.1 First attempt: why a root-owned copy gives "Permission denied"

We first ran proot on the `lfsroot` folder that had been extracted with `sudo`:

```bash
proot -q qemu-aarch64-static -0 -r lfsroot -w /root \
  /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
```

It started and showed a `bash-5.3#` prompt, but also:

```
bash: /root/.bash_profile: Permission denied
```

proot's `-0` only *pretends* to be root. The real user is still you, so Arch
refuses to let you read files owned by real root (`/root` is mode 0700). This is
an artifact of mixing a `sudo`-extracted tree with an unprivileged proot, not
a defect in the system.

### 9.2 Correct way: extract inside proot

Extracting from inside proot makes every file belong to your normal user, and
`--link2symlink` emulates hard links (many filesystems and Android do not
allow them in the same way). No `sudo` is used anywhere here:

```bash
mkdir lfs-proot
proot --link2symlink -0 tar --zstd -xpf stage7-fixed.tar.zst -C lfs-proot
proot -q qemu-aarch64-static -0 -r lfs-proot -w /root \
  /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
```

Then:

```bash
uname -m
gcc --version | head -1
echo 'int main(){return 0;}' > /tmp/t.c && gcc /tmp/t.c -o /tmp/a.out && /tmp/a.out && echo gcc-works
```

Observed:

```
aarch64
gcc (GCC) 15.2.0
gcc-works
```

No permission errors. This is the full proot test that passed.

What the proot options mean:

| Option | Meaning |
|---|---|
| `-r lfs-proot` | use this folder as the root of the filesystem |
| `-0` | pretend to be uid 0 (root) inside |
| `-w /root` | start in `/root` |
| `-q qemu-aarch64-static` | run the ARM programs through QEMU (needed only because this PC is x86; on a phone, leave it out) |
| `--link2symlink` | emulate hard links with symlinks (use when extracting) |
| `-b /dev -b /proc -b /sys` | optional: bind those host paths into the system if a program needs them |

If proot complains about the emulator, try again without `-q ...`, because the
system already has the ARM handler registered through binfmt_misc.

---

## 10. Cleaning up

```bash
exit
mount | grep lfsroot            # must print nothing; otherwise: sudo umount lfsroot/dev lfsroot/proc
sudo rm -rf lfsroot             # root-owned copy, only after the line above printed nothing
rm -rf lfs-proot                # your own copy, no sudo needed
rm -rf proot                    # AUR build folder (optional)
```

Keep `stage7-fixed.tar.zst`.

---

## 11. Known limitations

- **No kernel, no boot, no systemd as init.** The system is a root filesystem
  only. Book chapters 9 (boot configuration) and 10 (kernel) are not done. Under
  proot you get a shell, not a booted system.
- **setuid does not work under proot.** Programs like `su` and `passwd` will not
  behave as on a real system, because proot runs everything as your normal user.
  The repaired setuid bits matter for real `chroot` use and for a future
  real-boot image.
- **libffi was built with `--with-gcc-arch=native`**, which tunes it to the
  GitHub runner's CPU. On a phone with a different CPU, programs that use libffi
  (Python for example) could crash with "illegal instruction". It should be
  rebuilt for generic ARMv8 before relying on the system on a phone.
- **The root password is set to `root`** by the stage 5 script. The tarball
  is published in a public repository, so change it before real use.
- **The workflow restore step still has the recursive `chown`.** Until it is
  fixed, every new stage will damage setuid bits again. Replace
  `sudo chown -R $(id -u):$(id -g) $LFS` with
  `sudo chown $(id -u):$(id -g) $LFS $LFS/sources`.
- Stage 7's cleanup removed the cross toolchain and temporary files, which
  cannot be undone. Keep an earlier stage tarball until you are satisfied with
  the final one. Note that `file /usr/bin/bash` reports **not stripped**, so
  debug symbols were not removed from at least that binary; the system is
  larger than a fully stripped one would be.

### Proof output from the tested system

Run inside the proot system:

```
$ uname -m; ldd --version | head -1; gcc --version | head -1; file /usr/bin/bash
aarch64
ldd (GNU libc) 2.43
gcc (GCC) 15.2.0
/usr/bin/bash: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV),
dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux 5.4.0,
not stripped
```

The "for GNU/Linux 5.4.0" part is the minimum kernel version the system's
glibc was built for (`--enable-kernel=5.4`), so a real kernel under it must
be 5.4 or newer.

---

## 12. Adapting this to a phone with Termux (untested)

This part has not been tried on a real phone. The idea is identical to
section 9.2, with no QEMU (the phone CPU is already aarch64):

```bash
pkg install proot zstd tar
mkdir ~/lfs && cd ~/lfs
proot --link2symlink -0 tar --zstd -xpf ~/stage7-fixed.tar.zst
echo 'nameserver 1.1.1.1' > ~/lfs/etc/resolv.conf
proot -0 -r ~/lfs -b /dev -b /proc -b /sys -w /root \
  /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
```

Things that may need adjusting:

- If you get a "kernel too old" style error, the glibc here was built for
  kernel 5.4 or newer. Try adding `-k 5.4` to the proot command so it reports
  a newer kernel. Some system calls still will not exist on an older kernel.
- Newer Android versions restrict some of what proot does, so options may need
  tweaking.
- No root and no unlocked bootloader are needed for this method.

---

## 13. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `error: target not found: proot` | proot is AUR-only. Build it from the AUR (section 8). |
| AUR build: patch checksum `FAILED` | GitHub regenerated the PR patches. Read both patches, then `makepkg -si --skipchecksums` (section 8). |
| pacman stuck at `0 B/s` | Dead mirror. Add a reliable mirror at the top of the list (section 6). |
| `exec format error` when entering the chroot | ARM handler not registered. Re-run `sudo systemctl restart systemd-binfmt` and check `ls /proc/sys/fs/binfmt_misc/ \| grep aarch64`. |
| `bash: /root/.bash_profile: Permission denied` | You used proot on a `sudo`-extracted folder. Extract inside proot (section 9.2). |
| `unable to lock database` | Another pacman is running, or an interrupted run left `db.lck`. Check `pgrep pacman` first. |
| Very slow compile | Normal. Every instruction is emulated on an x86 PC. |
| `passwd`/`su` owned by `runner` | The workflow's recursive `chown`. Run `fix-perms.sh` (section 5) and fix the workflow (section 11). |
| Something still mounted in `lfsroot` | Run `sudo umount lfsroot/dev lfsroot/proc` before deleting the folder. |

---

## 14. Quick reference: the whole test in one place

```bash
# 0. tools
sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt zstd
sudo systemctl restart systemd-binfmt

# 1. repair and repack
mkdir lfsroot
sudo tar --numeric-owner --zstd -xpf stage7.tar.zst -C lfsroot
sudo bash fix-perms.sh lfsroot
sudo tar --numeric-owner -C lfsroot -I 'zstd -T0 -12' -cpf stage7-fixed.tar.zst .

# 2. chroot test (root)
sudo mount --bind /dev lfsroot/dev && sudo mount -t proc proc lfsroot/proc
sudo chroot lfsroot /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
#   inside: uname -m ; gcc test ; exit
sudo umount lfsroot/dev lfsroot/proc ; mount | grep lfsroot

# 3. proot test (no root)
mkdir lfs-proot
proot --link2symlink -0 tar --zstd -xpf stage7-fixed.tar.zst -C lfs-proot
proot -q qemu-aarch64-static -0 -r lfs-proot -w /root \
  /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/bin:/usr/sbin /bin/bash --login
#   inside: uname -m ; gcc --version ; compile and run a test program
```
