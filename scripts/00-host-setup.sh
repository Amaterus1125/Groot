#!/bin/bash
set -euo pipefail

# Force apt to use IPv4 to bypass GitHub Actions DNS timeouts
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 > /dev/null

# Use the highly reliable Kernel.org mirror
echo "http://mirrors.kernel.org/ubuntu/" | sudo tee /etc/apt/apt-mirrors.txt > /dev/null

sudo apt-get update
sudo apt-get install -y build-essential bison flex texinfo gawk m4 zstd wget
sudo ln -sf bash /bin/sh

# ADDED $LFS/lib64 here for x86_64 compatibility
sudo mkdir -p $LFS/sources $LFS/tools $LFS/usr/bin $LFS/usr/lib $LFS/usr/sbin $LFS/etc $LFS/var $LFS/lib64

for i in bin lib sbin; do sudo ln -sfn usr/$i $LFS/$i; done
sudo chown -R "$USER" $LFS
mkdir -p "$GITHUB_WORKSPACE/logs"
