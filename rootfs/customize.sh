#!/bin/sh
# mmdebstrap customize hook of scripts/build-rootfs.sh; $1 is the new root. Runs as root in the build container.
set -eu
r=$1
# cp -r, not cp -a: existing directories (/ included) keep their owner and mode, new files are root's with the
# source mode minus the umask. cp -a would put the checkout's uid and mode on /, /etc and /usr.
cp -r out/apps/usr/local/. "$r/usr/local/"
cp -r rootfs/overlay/. "$r/"
mkdir -p "$r/etc/emulationstation/themes"
cp -r out/src/es-theme-carbon "$r/etc/emulationstation/themes/carbon"
rm -rf "$r/etc/emulationstation/themes/carbon/.git"
chmod 0440 "$r/etc/sudoers.d/ga36"
chroot "$r" useradd -m -u 1000 -U -G video,render,input,audio -s /bin/bash ga36
mkdir -p "$r/roms" "$r/var/log/journal"
chown 1000:1000 "$r/roms"
chroot "$r" systemctl enable emulationstation.service serial-getty@ttyGS0.service
