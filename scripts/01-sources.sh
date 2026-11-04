#!/bin/bash
set -euo pipefail
cd $LFS/sources
BASE=https://www.linuxfromscratch.org/lfs/downloads/development
wget -q $BASE/wget-list-systemd -O wget-list   # use wget-list-sysv if you want sysvinit
wget -q $BASE/md5sums -O md5sums
wget -q --input-file=wget-list --continue
md5sum -c md5sums 2>&1 | tee ~/logs-md5.txt || true
