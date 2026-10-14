#!/bin/sh
# Test SD card image: U-Boot at 8 KiB, p1 FAT32 BOOT with the kernel, DTB, test initramfs and extlinux.conf.
# Test-only; the release image is built by sub-project 4. Rootless, no loop mounts. Runs inside the build container.
set -eu
o=out/sdcard
img=$o/ga36-test.img
p1=$o/p1.vfat
mkdir -p "$o"
rm -f "$img" "$p1"

cat > "$o/extlinux.conf" <<'EOF'
label ga36-test
	kernel /zImage
	fdt /sun8i-a33-gameconsole-r36s-ga36.dtb
	initrd /initrd.cpio.gz
	append console=tty0 console=ttyGS0,115200 panic=5 ga36_boot=sdcard
EOF
mkfs.vfat -F 32 -n BOOT -C "$p1" $((256 * 1024)) >/dev/null
mmd -i "$p1" ::/extlinux
mcopy -i "$p1" "$o/extlinux.conf" ::/extlinux/
mcopy -i "$p1" out/kernel/zImage out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb out/initramfs/initrd.cpio.gz ::/

truncate -s $(( (16 + 256) * 1024 * 1024 )) "$img"
echo 'start=32768, size=524288, type=c, bootable' | sfdisk -q "$img"
dd if=out/u-boot/u-boot-sunxi-with-spl.bin of="$img" bs=1024 seek=8 conv=notrunc status=none
dd if="$p1" of="$img" bs=1M seek=16 conv=notrunc status=none
rm "$p1" "$o/extlinux.conf"
