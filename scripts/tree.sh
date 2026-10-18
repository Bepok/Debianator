#!/bin/sh
# Pinned upstream source trees in out/src, with this repo's patch series applied by git am.
# Usage: scripts/tree.sh prep|export u-boot|linux|<app in apps/>
#   prep    create out/src/<tree>, or rebuild it when the pin or the patch set changed. Refuses (exit 1)
#           instead of discarding uncommitted changes or commits not yet exported.
#   export  write the commits on top of the pinned base (tag ga36-base) to the patch directory.
# Authoring: edit and commit in out/src/<tree>, then export.
set -eu
cd "$(dirname "$0")/.."
. ./versions.env

usage() { echo "usage: $0 prep|export u-boot|linux|<app in apps/>" >&2; exit 2; }
[ $# -eq 2 ] || usage
verb=$1 name=$2
case $name in
	u-boot) patches=uboot/patches pin=$UBOOT_COMMIT ;;
	linux) patches=kernel/patches pin=$LINUX_SHA256 ;;
	emulationstation|es-theme-carbon|snes9x2010|gpsp|picodrive|beetle-pce-fast|pcsx_rearmed|dosbox-pure)
		patches=apps/$name/patches
		v=$(echo "$name" | tr 'a-z-' 'A-Z_')
		eval "url=\$${v}_GIT pin=\$${v}_COMMIT"
		;;
	*) usage ;;
esac
src=out/src/$name
state=$src/.git/ga36-state
git_id="-c user.name=ga36-build -c user.email=ga36-build@localhost"

inputs() { { echo "$pin"; cat "$patches"/*.patch 2>/dev/null || true; } | sha256sum | cut -d' ' -f1; }
record() { echo "$(inputs) $(git -C "$src" rev-parse HEAD)" > "$state"; }
has_local_work() {
	[ -n "$(git -C "$src" status --porcelain)" ] && return 0
	read -r _ head < "$state"
	[ "$(git -C "$src" rev-parse HEAD)" != "$head" ]
}

fetch() {
	mkdir -p out/src
	case $name in
	u-boot)
		git -c advice.detachedHead=false clone -q --depth 1 --branch "$UBOOT_TAG" "$UBOOT_GIT" "$src"
		if [ "$(git -C "$src" rev-parse HEAD)" != "$UBOOT_COMMIT" ]; then
			echo "$UBOOT_TAG is not $UBOOT_COMMIT" >&2
			exit 1
		fi
		;;
	linux)
		tarball=out/dl/linux-$LINUX_VERSION.tar.xz
		mkdir -p out/dl
		if [ ! -f "$tarball" ]; then
			curl -fL -o "$tarball.part" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX_VERSION.tar.xz"
			mv "$tarball.part" "$tarball"
		fi
		echo "$LINUX_SHA256  $tarball" | sha256sum -c --quiet -
		tar -xf "$tarball" -C out/src
		mv "out/src/linux-$LINUX_VERSION" "$src"
		git -C "$src" init -q
		git -C "$src" add -A
		git -C "$src" $git_id commit -q -m "Linux $LINUX_VERSION"
		;;
	*)
		git init -q "$src"
		git -C "$src" fetch -q --depth 1 "$url" "$pin"
		git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
		git -C "$src" submodule -q update --init --recursive
		;;
	esac
	git -C "$src" tag ga36-base
}

case $verb in
prep)
	if [ -f "$state" ]; then
		read -r have _ < "$state"
		[ "$have" = "$(inputs)" ] && exit 0
		if has_local_work; then
			echo "$src has work not exported to $patches: commit it and run scripts/tree.sh export $name" >&2
			exit 1
		fi
		rm -rf "$src"
	elif [ -e "$src" ]; then
		echo "$src was not made by scripts/tree.sh; move it away" >&2
		exit 1
	fi
	fetch
	for p in "$patches"/*.patch; do
		[ -e "$p" ] || continue
		git -C "$src" $git_id am -q "$PWD/$p"
	done
	record
	;;
export)
	[ -z "$(git -C "$src" status --porcelain)" ] || { echo "$src has uncommitted changes" >&2; exit 1; }
	mkdir -p "$patches"
	rm -f "$patches"/*.patch
	git -C "$src" format-patch -q --zero-commit --no-signature -o "$PWD/$patches" ga36-base..HEAD
	record
	;;
*) usage ;;
esac
