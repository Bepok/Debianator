#!/bin/sh
# Build entry point. Every stage runs inside the pinned build container (container/Containerfile).
# Usage: ./build.sh uboot|kernel|initramfs|sdcard
#        ./build.sh run <command> [args]     run any command in the container
# Env: ENGINE=docker|podman (default: whichever is installed, docker first).
set -eu
cd "$(dirname "$0")"

usage() { echo "usage: ./build.sh uboot|kernel|initramfs|sdcard | run <command> [args]" >&2; exit 2; }
[ $# -gt 0 ] || usage

ENGINE=${ENGINE:-$(command -v docker || command -v podman)}
IMAGE=r36s-a33-ga36-build
case $(basename "$ENGINE") in podman) userns=--userns=keep-id ;; *) userns= ;; esac
if [ -t 0 ]; then it=-it; else it=; fi
mkdir -p out   # git-ignored, so absent in a fresh worktree; created here so the host user owns it

"$ENGINE" build -q -t "$IMAGE" -f container/Containerfile container >/dev/null

run() {
	"$ENGINE" run --rm $it $userns --user "$(id -u):$(id -g)" -e HOME=/tmp \
		-v "$PWD:/work" -w /work "$IMAGE" "$@"
}

stage=$1
shift
case $stage in
	uboot) run scripts/build-uboot.sh ;;
	kernel) run scripts/build-kernel.sh ;;
	run) [ $# -gt 0 ] || usage; run "$@" ;;
	*) usage ;;
esac
