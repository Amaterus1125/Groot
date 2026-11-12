#!/bin/bash
set -euo pipefail
export LOGS="/tmp/logs"
mkdir -p "$LOGS"
export S="/sources"

echo "==> Creating Directories (7.5)"
mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/local/{bin,include,lib,sbin,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/local/share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/local/share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

echo "==> Creating Essential Files and Symlinks (7.6)"
ln -sfv /proc/self/mounts /etc/mtab || true
cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664 /var/log/lastlog
chmod -v 600 /var/log/btmp

# --- Build Functions ---
pkg_gettext() {
  cd "$S"; tar -xf gettext-*.tar.xz; cd gettext-*/
  ./configure --disable-shared
  make
  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
  cd "$S"; rm -rf gettext-*/
}

pkg_bison() {
  cd "$S"; tar -xf bison-*.tar.xz; cd bison-*/
  ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
  make
  make install
  cd "$S"; rm -rf bison-*/
}

pkg_perl() {
  cd "$S"; tar -xf perl-*.tar.xz; cd perl-*/
  sh Configure -des \
    -D prefix=/usr \
    -D vendorprefix=/usr \
    -D useshrplib \
    -D privlib=/usr/lib/perl5/5.44/core_perl \
    -D archlib=/usr/lib/perl5/5.44/core_perl \
    -D sitelib=/usr/lib/perl5/5.44/site_perl \
    -D sitearch=/usr/lib/perl5/5.44/site_perl \
    -D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
    -D vendorarch=/usr/lib/perl5/5.44/vendor_perl
  make
  make install
  cd "$S"; rm -rf perl-*/
}

pkg_zlib() {
  cd "$S"; tar -xf zlib-*.tar.*; cd zlib-*/
  ./configure --prefix=/usr
  make
  make install
  rm -fv /usr/lib/libz.a
  cd "$S"; rm -rf zlib-*/
}

pkg_mpdecimal() {
  cd "$S"; tar -xf mpdecimal-*.tar.*; cd mpdecimal-*/
  ./configure --prefix=/usr \
    --disable-static \
    --docdir=/usr/share/doc/mpdecimal-4.0.1
  make
  make install
  cd "$S"; rm -rf mpdecimal-*/
}

pkg_python() {
  cd "$S"; tar -xf Python-*.tar.xz; cd Python-*/
  ./configure --prefix=/usr \
    --enable-shared \
    --without-ensurepip \
    --without-static-libpython
  make
  make install
  cd "$S"; rm -rf Python-*/
}

pkg_texinfo() {
  cd "$S"; tar -xf texinfo-*.tar.xz; cd texinfo-*/
  ./configure --prefix=/usr
  make
  make install
  cd "$S"; rm -rf texinfo-*/
}

pkg_utillinux() {
  cd "$S"; tar -xf util-linux-*.tar.xz; cd util-linux-*/
  mkdir -pv /var/lib/hwclock
  ./configure --libdir=/usr/lib \
    --runstatedir=/run \
    --disable-chfn-chsh \
    --disable-login \
    --disable-nologin \
    --disable-su \
    --disable-setpriv \
    --disable-runuser \
    --disable-pylibmount \
    --disable-static \
    --disable-liblastlog2 \
    --without-python \
    ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --docdir=/usr/share/doc/util-linux-2.42.2
  make
  make install
  cd "$S"; rm -rf util-linux-*/
}

export -f pkg_gettext pkg_bison pkg_perl pkg_zlib pkg_mpdecimal pkg_python pkg_texinfo pkg_utillinux

run_pkg() {
  echo "==> $1"
  set +e
  bash -euo pipefail -c "pkg_$1" > "$LOGS/$1.log" 2>&1
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "FAILED: $1 (exit $rc), last lines of log:"
    tail -n 80 "$LOGS/$1.log"
    exit 1
  fi
  echo "ok: $1"
}

for p in gettext bison perl zlib mpdecimal python texinfo utillinux; do
  run_pkg "$p"
done

echo "==> Cleaning up (7.13)"
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools

# Move logs to /sources so the runner can easily upload them
cp -r $LOGS /sources/chroot-logs
