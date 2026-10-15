#!/bin/sh
# Release root filesystem: Debian trixie armhf minbase, rootfs/packages.list, the run-time packages of out/apps, and
# rootfs/customize.sh. Output: out/rootfs/rootfs.tar.
# Runs as root in the build container (./build.sh rootfs); armhf runs through the host's qemu-user-binfmt.
set -eu
o=out/rootfs
[ -f out/apps/runtime-deps.list ] || { echo "out/apps missing: ./build.sh apps" >&2; exit 1; }
rm -rf "$o"
mkdir -p "$o"
trap 'chown -R "$HOST_UID:$HOST_GID" "$o"' EXIT
mmdebstrap --mode=root --variant=minbase --architectures=armhf \
	--include="$(cat rootfs/packages.list out/apps/runtime-deps.list | grep -v '^#' | grep . | sort -u | paste -sd, -)" \
	--customize-hook='sh rootfs/customize.sh "$1"' \
	trixie "$o/rootfs.tar"
