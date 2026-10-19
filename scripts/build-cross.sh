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

# PPSSPP with its ARM32 JIT and GLES2; FFmpeg comes prebuilt for linux/armv7 from its submodule. The assets go to
# /usr/local/share/ppsspp, from where ga36-roms-dirs copies them to RetroArch's system folder on ROMS.
f="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
cmake -S out/src/ppsspp -B out/build/ppsspp -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=armv7l \
	-DCMAKE_C_COMPILER=${x}gcc -DCMAKE_CXX_COMPILER=${x}g++ \
	-DCMAKE_C_FLAGS="$f" -DCMAKE_CXX_FLAGS="$f" -DCMAKE_ASM_FLAGS="$f" \
	-DLIBRETRO=ON -DUSING_GLES2=ON -DVULKAN=OFF -DUSE_DISCORD=OFF -DUSE_MINIUPNPC=OFF -DHEADLESS=OFF -DUNITTEST=OFF \
	-DCMAKE_BUILD_TYPE=Release
make -C out/build/ppsspp -j"$(nproc)" ppsspp_libretro
cp out/build/ppsspp/lib/ppsspp_libretro.so "$lr/"
s=$o/usr/local/share/ppsspp
mkdir -p "$s"
cp -r out/src/ppsspp/assets "$s/"
# A new pin means new assets: bump this with PPSSPP_COMMIT.
echo v1.20.4 > "$s/version"
