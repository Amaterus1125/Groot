#!/bin/bash
# LFS 13.0-systemd, chapter 5: cross toolchain, built on a native aarch64 host
set -euo pipefail

: "${LFS:?LFS not set}"
[ "$(id -u)" -ne 0 ] || { echo "do not run as root"; exit 1; }

export LOGS="${GITHUB_WORKSPACE:-$PWD}/logs"
mkdir -p "$LOGS"
export LC_ALL=POSIX
export LFS_TGT="$(uname -m)-lfs-linux-gnu"
export PATH="$LFS/tools/bin:$PATH"
export MAKEFLAGS="-j$(nproc)"
export S="$LFS/sources"
umask 022

# 5.2 Binutils pass 1
pkg_binutils() {
  cd "$S"; tar -xf binutils-2.46.0.tar.xz; cd binutils-2.46.0
  mkdir -v build; cd build
  ../configure --prefix=$LFS/tools \
               --with-sysroot=$LFS \
               --target=$LFS_TGT \
               --disable-nls \
               --enable-gprofng=no \
               --disable-werror \
               --enable-new-dtags \
               --enable-default-hash-style=gnu
  make
  make install
  cd "$S"; rm -rf binutils-2.46.0
}

# 5.3 GCC pass 1
pkg_gcc() {
  cd "$S"; tar -xf gcc-15.2.0.tar.xz; cd gcc-15.2.0
  tar -xf ../mpfr-4.2.2.tar.xz; mv -v mpfr-4.2.2 mpfr
  tar -xf ../gmp-6.3.0.tar.xz;  mv -v gmp-6.3.0 gmp
  tar -xf ../mpc-1.3.1.tar.gz;  mv -v mpc-1.3.1 mpc
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    aarch64)   # NOT in the book text (it covers x86_64 only): use "lib" instead of "lib64"
      test -f gcc/config/aarch64/t-aarch64-linux
      sed -e '/lp64=/s/lib64/lib/' -i.orig gcc/config/aarch64/t-aarch64-linux ;;
  esac
  mkdir -v build; cd build
  ../configure \
      --target=$LFS_TGT \
      --prefix=$LFS/tools \
      --with-glibc-version=2.43 \
      --with-sysroot=$LFS \
      --with-newlib \
      --without-headers \
      --enable-default-pie \
      --enable-default-ssp \
      --disable-nls \
      --disable-shared \
      --disable-multilib \
      --disable-threads \
      --disable-libatomic \
      --disable-libgomp \
      --disable-libquadmath \
      --disable-libssp \
      --disable-libvtv \
      --disable-libstdcxx \
      --enable-languages=c,c++
  make
  make install
  cd ..
  cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
    "$(dirname "$($LFS_TGT-gcc -print-libgcc-file-name)")/include/limits.h"
  cd "$S"; rm -rf gcc-15.2.0
}

# 5.4 Linux API headers
pkg_headers() {
  cd "$S"; tar -xf linux-6.18.10.tar.xz; cd linux-6.18.10
  make mrproper
  make headers
  find usr/include -type f ! -name '*.h' -delete
  cp -rv usr/include "$LFS/usr"
  cd "$S"; rm -rf linux-6.18.10
}

# 5.5 Glibc
pkg_glibc() {
  cd "$S"; tar -xf glibc-2.43.tar.xz; cd glibc-2.43
  case $(uname -m) in
    x86_64)
      ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
      ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;;
    aarch64)   # NOT in the book text: LSB compliance link only; the loader lives in /lib
      ln -sfv ld-linux-aarch64.so.1 $LFS/lib/ld-lsb-aarch64.so.3 ;;
  esac
  patch -Np1 -i ../glibc-fhs-1.patch
  mkdir -v build; cd build
  echo "rootsbindir=/usr/sbin" > configparms
  ../configure --prefix=/usr \
               --host=$LFS_TGT \
               --build=$(../scripts/config.guess) \
               --disable-nscd \
               libc_cv_slibdir=/usr/lib \
               --enable-kernel=5.4
  make || make -j1
  make DESTDIR=$LFS install
  sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd

  # sanity checks from the book
  echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
  readelf -l a.out | grep ': /lib' | tee interp.txt
  grep -q 'ld-linux-aarch64.so.1' interp.txt || [ "$(uname -m)" != aarch64 ]
  ! grep -q "$LFS" interp.txt
  grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
  grep -B3 "^ $LFS/usr/include" dummy.log
  grep "/lib.*/libc.so.6 " dummy.log | grep -q succeeded
  grep found dummy.log
  rm -v a.out dummy.log interp.txt
  cd "$S"; rm -rf glibc-2.43
}

# 5.6 Libstdc++
pkg_libstdcxx() {
  cd "$S"; tar -xf gcc-15.2.0.tar.xz; cd gcc-15.2.0
  mkdir -v build; cd build
  ../libstdc++-v3/configure \
      --host=$LFS_TGT \
      --build=$(../config.guess) \
      --prefix=/usr \
      --disable-multilib \
      --disable-nls \
      --disable-libstdcxx-pch \
      --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
  cd "$S"; rm -rf gcc-15.2.0
}

export -f pkg_binutils pkg_gcc pkg_headers pkg_glibc pkg_libstdcxx

run_pkg() {
  echo "==> $1"
  set +e
  bash -euo pipefail -c "pkg_$1" > "$LOGS/$1.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "FAILED: $1 (exit $rc), last lines of its log:"
    tail -n 80 "$LOGS/$1.log"
    exit 1
  fi
  echo "ok: $1"
  df -h "$LFS" | tail -1
}

for p in binutils gcc headers glibc libstdcxx; do run_pkg "$p"; done
ls "$LFS/tools/bin" | head
