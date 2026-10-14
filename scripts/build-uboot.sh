#!/bin/sh
# Build U-Boot for the GA36 and the FEL boot script. Runs inside the build container (./build.sh uboot).
set -eu
scripts/tree.sh prep u-boot
b=$PWD/out/build/u-boot
mkdir -p "$b" out/u-boot
cp uboot/ga36_defconfig "$b/.config"
make -C out/src/u-boot O="$b" CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
make -C out/src/u-boot O="$b" CROSS_COMPILE=arm-linux-gnueabihf- -j"$(nproc)"
cp "$b/u-boot-sunxi-with-spl.bin" out/u-boot/

# Sourced by U-Boot's "fel" boot target when sunxi-fel uploaded it (scripts/fel-boot.sh kernel).
# bootz returns only on failure; the console then moves to USB ACM so the error can be read.
cat > "$b/fel.cmd" <<'EOF'
setenv bootargs console=tty0 console=ttyGS0,115200 panic=5
bootz 0x42000000 0x43400000 0x43000000
setenv stdin serial,usbacm; setenv stdout serial,usbacm; setenv stderr serial,usbacm
echo bootz failed
EOF
"$b/tools/mkimage" -A arm -T script -C none -d "$b/fel.cmd" out/u-boot/fel.scr >/dev/null
