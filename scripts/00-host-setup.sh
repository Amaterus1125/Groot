#!/bin/bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y build-essential bison flex texinfo gawk m4 zstd wget
sudo ln -sf bash /bin/sh
sudo mkdir -p $LFS/sources $LFS/tools $LFS/usr/bin $LFS/usr/lib $LFS/usr/sbin $LFS/etc $LFS/var
for i in bin lib sbin; do sudo ln -sfn usr/$i $LFS/$i; done
sudo chown -R "$USER" $LFS
mkdir -p "$GITHUB_WORKSPACE/logs"
