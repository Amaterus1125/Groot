#!/bin/bash
set -uo pipefail
cd $LFS/sources
BASE=https://www.linuxfromscratch.org/lfs/downloads/13.1-systemd

wget --tries=3 --timeout=30 $BASE/wget-list -O wget-list || { echo "FAILED: wget-list"; exit 1; }
wget --tries=3 --timeout=30 $BASE/md5sums -O md5sums   || { echo "FAILED: md5sums"; exit 1; }
grep -q 'linux-7.1.8' wget-list || { echo "wrong LFS version"; exit 1; }

# Remove documentation files from the list so they don't break the build
sed -i '/-html\.tar/d' wget-list
sed -i '/sqlite-doc/d' wget-list
sed -i '/-man-pages/d' wget-list

wc -l wget-list

# keep going if single files fail, then show exactly which ones
wget --no-verbose --tries=3 --timeout=30 --continue --input-file=wget-list 2>&1 | tee ../wget.log
echo "---- failed downloads ----"
grep -iE 'ERROR|failed|unable' ../wget.log || echo "none"

echo "---- checksum check ----"
md5sum -c md5sums --ignore-missing | grep -v ': OK$' || echo "all OK"
md5sum -c md5sums --ignore-missing --quiet
