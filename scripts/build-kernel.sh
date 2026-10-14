#!/bin/sh
# Build the GA36 kernel: sunxi_defconfig plus kernel/ga36.config. Runs inside the build container (./build.sh kernel).
set -eu
scripts/tree.sh prep linux
src=out/src/linux
b=$PWD/out/build/linux
mkdir -p "$b" out/kernel
k() { make -C "$src" O="$b" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- "$@"; }
k sunxi_defconfig
"$src/scripts/kconfig/merge_config.sh" -m -O "$b" "$b/.config" kernel/ga36.config
k olddefconfig
k -j"$(nproc)" zImage allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb
cp "$b/arch/arm/boot/zImage" "$b/arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb" out/kernel/
