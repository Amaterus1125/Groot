#!/bin/bash
# LFS 13.1-systemd, chapter 6: cross compiling temporary tools (6.2 - 6.18)
set -euo pipefail

LOGS=$GITHUB_WORKSPACE/logs
mkdir -p "$LOGS"

# Environment from book section 4.4
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH=$LFS/tools/bin:$PATH
export CONFIG_SITE=$LFS/usr/share/config.site
export LC_ALL=POSIX
export MAKEFLAGS="-j$(nproc)"
umask 022
unset CFLAGS CXXFLAGS

cd "$LFS/sources"

CUR=""
trap 'rc=$?; if [ $rc -ne 0 ] && [ -n "$CUR" ]; then echo "FAILED: $CUR"; tail -n 60 "$LOGS/$CUR.log"; fi' EXIT

step() {
  CUR=$1
  local tarball dir
  tarball=$(set +o pipefail; ls "$1"-[0-9]*.tar.* | head -n 1)
  dir=$(set +o pipefail; tar -tf "$tarball" | head -n 1 | cut -d/ -f1)
  tar -xf "$tarball"
  pushd "$dir" >/dev/null
  "build_$1" >"$LOGS/$1.log" 2>&1
  popd >/dev/null
  rm -rf "$dir"
  echo "ok: $1"
  CUR=""
}

build_m4() {
  cat > $LFS/usr/share/config.site << EOF
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
  ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_ncurses() {
  mkdir build
  pushd build
    ../configure --prefix=$LFS/tools AWK=gawk
    make -C include
    make -C progs tic
    mkdir -p $LFS/tools/bin
    install progs/tic $LFS/tools/bin
  popd
  ./configure --prefix=/usr                \
              --host=$LFS_TGT              \
              --build=$(./config.guess)    \
              --mandir=/usr/share/man      \
              --with-manpage-format=normal \
              --with-shared                \
              --without-normal             \
              --with-cxx-shared            \
              --without-debug              \
              --without-ada                \
              --disable-stripping          \
              AWK=gawk
  make
  make DESTDIR=$LFS install
  ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $LFS/usr/include/curses.h
}

build_bash() {
  ./configure --prefix=/usr                      \
              --build=$(sh support/config.guess) \
              --host=$LFS_TGT                    \
              --without-bash-malloc
  make
  make DESTDIR=$LFS install
  ln -sv bash $LFS/bin/sh
}

build_coreutils() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --enable-install-program=hostname \
              --enable-no-install-program=kill,uptime
  make
  make DESTDIR=$LFS install
  mv -v $LFS/usr/bin/chroot $LFS/usr/sbin
  mkdir -pv $LFS/usr/share/man/man8
  mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
  sed -i 's/"1"/"8"/' $LFS/usr/share/man/man8/chroot.8
}

build_diffutils() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              gl_cv_func_strcasecmp_works=yes \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_file() {
  mkdir build
  pushd build
    ../configure --disable-bzlib      \
                 --disable-libseccomp \
                 --disable-xzlib      \
                 --disable-zlib
    make
  popd
  ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
  make FILE_COMPILE=$(pwd)/build/src/file
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/libmagic.la
}

build_findutils() {
  ./configure --prefix=/usr                   \
              --localstatedir=/var/lib/locate \
              --host=$LFS_TGT                 \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_gawk() {
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_grep() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_gzip() {
  ./configure --prefix=/usr --host=$LFS_TGT
  make
  make DESTDIR=$LFS install
}

build_make() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_patch() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_sed() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_tar() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

build_xz() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --disable-static                  \
              --docdir=/usr/share/doc/xz-5.8.3
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/liblzma.la
}

build_binutils() {
  sed -n '6031p' ltmain.sh | grep -q '\$add_dir' || {
    echo "ltmain.sh line 6031 has no \$add_dir: check the book (6.17 Binutils) for the new line number"
    grep -n '\$add_dir' ltmain.sh; exit 1; }
  sed '6031s/$add_dir//' -i ltmain.sh
  mkdir -v build
  cd build
  ../configure                   \
      --prefix=/usr              \
      --build=$(../config.guess) \
      --host=$LFS_TGT            \
      --disable-nls              \
      --enable-shared            \
      --enable-gprofng=no        \
      --disable-werror           \
      --enable-64-bit-bfd        \
      --enable-new-dtags         \
      --enable-default-hash-style=gnu
  make
  make DESTDIR=$LFS install
  rm -fv $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

build_gcc() {
  tar -xf ../mpfr-*.tar.xz
  mv -v mpfr-* mpfr
  tar -xf ../gmp-*.tar.xz
  mv -v gmp-* gmp
  tar -xf ../mpc-*.tar.xz
  mv -v mpc-* mpc

  # AMD x86_64 specific library configuration
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    ;;
  esac

  sed '/thread_header =/s/@.*@/gthr-posix.h/' \
      -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

  mkdir -v build
  cd build
  ../configure                                       \
      --build=$(../config.guess)                     \
      --host=$LFS_TGT                                \
      --target=$LFS_TGT                              \
      --prefix=/usr                                  \
      --with-build-sysroot=$LFS                      \
      --enable-default-pie                           \
      --enable-default-ssp                           \
      --disable-nls                                  \
      --disable-multilib                             \
      --disable-libatomic                            \
      --disable-libgomp                              \
      --disable-libquadmath                          \
      --disable-libsanitizer                         \
      --disable-libssp                               \
      --disable-libvtv                               \
      --enable-languages=c,c++                       \
      LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
  make
  make DESTDIR=$LFS install
  ln -sv gcc $LFS/usr/bin/cc
}

for p in m4 ncurses bash coreutils diffutils file findutils gawk grep gzip \
         make patch sed tar xz binutils gcc; do
  step "$p"
done

echo "chapter 6 complete"
