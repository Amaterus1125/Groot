#!/bin/bash
set -euo pipefail

# Remove the broken Azure mirror lists and force the default Ubuntu archives
sudo rm -f /etc/apt/apt-mirrors.txt
sudo sed -i 's/azure.archive.ubuntu.com/archive.ubuntu.com/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
sudo sed -i 's/azure.archive.ubuntu.com/archive.ubuntu.com/g' /etc/apt/sources.list 2>/dev/null || true

sudo apt-get update
sudo apt-get install -y build-essential bison flex texinfo gawk m4 zstd wget
sudo ln -sf bash /bin/sh
sudo mkdir -p $LFS/sources $LFS/tools $LFS/usr/bin $LFS/usr/lib $LFS/usr/sbin $LFS/etc $LFS/var
for i in bin lib sbin; do sudo ln -sfn usr/$i $LFS/$i; done
sudo chown -R "$USER" $LFS
mkdir -p "$GITHUB_WORKSPACE/logs"
