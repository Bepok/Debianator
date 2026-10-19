#!/bin/sh
# Cross-compiles the heavy libretro cores for the A7 with the container's armhf toolchain and Debian multiarch
# headers: under qemu they would take hours. Output: out/cross/usr/local, staged by apps/build-in-chroot.sh.
# Runs as the user in the build container (./build.sh apps).
set -eu
cd "$(dirname "$0")/.."
o=out/cross
lr=$o/usr/local/lib/libretro
rm -rf "$o"
mkdir -p "$lr"
x=arm-linux-gnueabihf-

# The platform selects -marm -mcpu=cortex-a7 -mfpu=neon hard-float and the ARM dynarec; CPUFLAGS must not be set here,
# it would replace -DARM -marm. STRINGS reads the ARM object that the dynarec's asm_defines are generated from.
make -C out/src/mupen64plus-next platform=unix-armv7-neon-hardfloat FORCE_GLES=1 \
	CC=${x}gcc CXX=${x}g++ AR=${x}ar STRINGS=${x}strings -j"$(nproc)"
cp out/src/mupen64plus-next/mupen64plus_next_libretro.so "$lr/"

