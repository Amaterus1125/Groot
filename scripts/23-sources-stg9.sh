#!/bin/bash
# Stage 9: sources for the extra BLFS packages. Runs on the host, not in the chroot.
set -euo pipefail
LFS=${LFS:-/mnt/lfs}      # sudo may not pass the variable through
mkdir -p "$LFS/sources"
cd "$LFS/sources"

# fetch <url> <md5|sha256> <checksum> [output-file-name]
fetch() {
  local url=$1 algo=$2 sum=$3 f=${4:-$(basename "$1")} tool
  case $algo in
    md5)    tool=md5sum ;;
    sha256) tool=sha256sum ;;
    *) echo "unknown checksum type: $algo"; return 1 ;;
  esac
  if [ -f "$f" ] && echo "$sum  $f" | $tool -c --quiet -; then
    echo "have $f"
    return 0
  fi
  rm -f "$f"
  wget -nv -O "$f" "$url"
  echo "$sum  $f" | $tool -c -
}

# MD5 sums are the ones published in the BLFS book.
fetch https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz                    md5 c70ba58b36f944e8ba1d655ace552881
fetch https://www.samba.org/ftp/rsync/src/rsync-3.5.2.tar.gz             md5 5402db5b3778b6cfef496bed612845d7
fetch https://www.nano-editor.org/dist/v8/nano-8.0.tar.xz                md5 328e7a8c30095178997b9925c89d99e5
fetch https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz \
                                                                         md5 b5333f021f880fe76490d8a799cd79f4

# SHA-256 sums for GitHub-hosted releases, computed from the official release files over HTTPS
# (the book's MD5 for libevent was also cross-checked against the same download).
fetch https://github.com/libarchive/libarchive/releases/download/v3.8.9/libarchive-3.8.9.tar.xz \
                                                                         sha256 888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde
fetch https://github.com/tmux/tmux/releases/download/3.6b/tmux-3.6b.tar.gz \
                                                                         sha256 390759d25fdba016887ec982b808927e637070fd7d03a8021f8ef3102b9ae3c7
fetch https://github.com/htop-dev/htop/releases/download/3.5.3/htop-3.5.3.tar.xz \
                                                                         sha256 a8b164386494cb85bb255a415a3f5f80afe7a0c4491da5d113b3a0f951087e65
fetch https://github.com/Old-Man-Programmer/tree/archive/refs/tags/2.3.2.tar.gz \
                                                                         sha256 22cf32e84e3eb508d97a9e991c2c3cc006b9dcf4afed201d96311c5c57d08fcf tree-2.3.2.tar.gz

echo "stage 9 sources ready"
