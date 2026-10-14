#!/bin/sh
# Test SD image layout: U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files and extlinux.conf.
# Run: ./build.sh run tests/sdcard.sh
set -eu
img=out/sdcard/ga36-test.img
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -f "$img" ] || { echo "FAIL: $img missing (./build.sh sdcard)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sfdisk -d "$img" | grep -q 'start= *32768, size= *524288, type=c, bootable' || bad "p1 not at 16 MiB / 256 MiB / FAT32 LBA / bootable"
dd if="$img" bs=1024 skip=8 status=none | head -c "$(stat -c %s "$u")" | cmp -s - "$u" || bad "U-Boot not at 8 KiB"
for f in zImage sun8i-a33-gameconsole-r36s-ga36.dtb initrd.cpio.gz; do
	mdir -b -i "$img@@16M" "::/$f" >/dev/null 2>&1 || bad "$f missing on p1"
done
mtype -i "$img@@16M" ::/extlinux/extlinux.conf | grep -q 'fdt /sun8i-a33-gameconsole-r36s-ga36.dtb' || bad "extlinux.conf fdt"
mtype -i "$img@@16M" ::/extlinux/extlinux.conf | grep -q 'append .*console=ttyGS0' || bad "extlinux.conf console"
[ $fail = 0 ] && echo PASS
exit $fail
