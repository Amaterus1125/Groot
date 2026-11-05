#!/bin/bash
set -euo pipefail
cd $LFS/sources
BASE=https://www.linuxfromscratch.org/lfs/downloads/13.0-systemd
wget -q $BASE/wget-list-systemd -O wget-list
wget -q $BASE/md5sums -O md5sums
grep -q 'linux-6.18.10' wget-list || { echo "wrong LFS version: linux-6.18.10 not in list"; exit 1; }
wget -q --input-file=wget-list --continue
md5sum -c md5sums
