#!/bin/bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y build-essential bison flex texinfo gawk m4 patchelf zstd wget
sudo ln -sf bash /bin/sh          # Ubuntu defaults to dash; LFS needs bash
sudo mkdir -p $LFS/{sources,tools,usr/{bin,lib,sbin},etc,var}
for i in bin lib sbin; do sudo ln -sfn usr/$i $LFS/$i; done
sudo chown -R "$USER" $LFS
mkdir -p logs
