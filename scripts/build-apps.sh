#!/bin/sh
# Builds ES and the libretro cores for armhf in a throwaway trixie chroot, so build dependencies stay out of the
# release rootfs. Output: out/apps/usr/local and out/apps/runtime-deps.list.
# Runs as root in the build container (./build.sh apps); armhf runs through the host's qemu-user-binfmt.
set -eu
o=out/apps
rm -rf "$o"
mkdir -p "$o"
trap 'chown -R "$HOST_UID:$HOST_GID" "$o"' EXIT
mmdebstrap --mode=root --variant=apt --architectures=armhf \
	--include="$(grep -v '^#' apps/build-deps.list | grep . | paste -sd, -)" \
	--customize-hook='mkdir -p "$1/src"' \
	--customize-hook='copy-in out/src/emulationstation out/src/snes9x2010 out/src/gpsp out/src/picodrive out/src/beetle-pce-fast out/src/pcsx_rearmed apps/build-in-chroot.sh /src' \
	--customize-hook='chroot "$1" sh /src/build-in-chroot.sh' \
	--customize-hook='sync-out /stage out/apps' \
	trixie /dev/null
