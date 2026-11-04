#!/bin/bash
set -euo pipefail
LOGS=$GITHUB_WORKSPACE/logs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH=$LFS/tools/bin:$PATH
cd $LFS/sources
tar xf binutils-*.tar.xz
cd binutils-*/
mkdir build && cd build
../configure --prefix=$LFS/tools --with-sysroot=$LFS --target=$LFS_TGT \
  --disable-nls --enable-gprofng=no --disable-werror \
  --enable-new-dtags --enable-default-hash-style=gnu 2>&1 | tee $LOGS/binutils-cfg.log
make -j$(nproc) 2>&1 | tee $LOGS/binutils-make.log | tail -n 20
make install
