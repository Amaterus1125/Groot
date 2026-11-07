#!/bin/bash
# Repair ownership and setuid/setgid bits lost to the workflow's recursive chown.
# Usage: sudo bash fix-perms.sh /path/to/extracted/lfsroot
# Extract first with:  sudo tar --numeric-owner --zstd -xpf stage7.tar.zst -C lfsroot
set -euo pipefail
R=${1:?usage: sudo bash fix-perms.sh /path/to/lfsroot}
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# the runner's uid, read from a file the build left behind
RUID=$(stat -c %u "$R/usr/bin/passwd")
[ "$RUID" -ne 0 ] || { echo "passwd is already root-owned; nothing to do"; exit 0; }
echo "runner uid/gid in the archive: $RUID"

# 1. everything the runner owns goes back to root (other owners and groups stay)
chown -R --from="$RUID:$RUID" 0:0 "$R"
chown -R --from="$RUID" 0 "$R"
chown -R --from=":$RUID" :0 "$R"

# 2. shadow's setuid-root programs
for f in chage chfn chsh expiry gpasswd newgrp passwd su newuidmap newgidmap; do
  [ -e "$R/usr/bin/$f" ] && chmod 4755 "$R/usr/bin/$f" && echo "setuid  $f"
done

# 3. util-linux's mount/umount (setuid) and write/wall (setgid tty, gid 5)
for f in mount umount; do
  [ -e "$R/usr/bin/$f" ] && chmod 4755 "$R/usr/bin/$f" && echo "setuid  $f"
done
for f in write wall; do
  [ -e "$R/usr/bin/$f" ] && chown 0:5 "$R/usr/bin/$f" && chmod 2755 "$R/usr/bin/$f" && echo "setgid  $f"
done

echo "--- setuid/setgid files now:"
find "$R/usr" -xdev -type f -perm /6000 -printf '%M %u:%g %p\n'
echo "--- files still owned by uid $RUID (expect 0):"
find "$R" -xdev \( -uid "$RUID" -o -gid "$RUID" \) | wc -l
