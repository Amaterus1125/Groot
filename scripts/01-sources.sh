#!/bin/bash
set -euo pipefail
cd $LFS/sources
BASE=https://www.linuxfromscratch.org/lfs/view/development
wget -q $BASE/wget-list-sysv -O wget-list
wget -q $BASE/md5sums -O md5sums
wget -q --input-file=wget-list --continue
md5sum -c md5sums
