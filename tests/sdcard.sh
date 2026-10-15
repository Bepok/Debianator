#!/bin/sh
# Test SD image layout: U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files, p2 ext4 ROOTFS (3 GiB) right after.
# Run: ./build.sh run tests/sdcard.sh
set -eu
img=out/sdcard/ga36-test.img
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -f "$img" ] || { echo "FAIL: $img missing (./build.sh sdcard)"; exit 1; }
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d=$(sfdisk -d "$img")
echo "$d" | grep -q '^label-id: 0x47413336$' || bad "disk id not 0x47413336"
echo "$d" | grep -q 'start= *32768, size= *524288, type=c, bootable' || bad "p1 not at 16 MiB / 256 MiB / FAT32 LBA / bootable"
echo "$d" | grep -q 'start= *557056, size= *6291456, type=83' || bad "p2 not at 272 MiB / 3 GiB / Linux"
dd if="$img" bs=1024 skip=8 status=none | head -c "$(stat -c %s "$u")" | cmp -s - "$u" || bad "U-Boot not at 8 KiB"
for f in zImage sun8i-a33-gameconsole-r36s-ga36.dtb; do
	mdir -b -i "$img@@16M" "::/$f" >/dev/null 2>&1 || bad "$f missing on p1"
done
x=$(mtype -i "$img@@16M" ::/extlinux/extlinux.conf)
echo "$x" | grep -q 'fdt /sun8i-a33-gameconsole-r36s-ga36.dtb' || bad "extlinux.conf fdt"
echo "$x" | grep -q 'append .*console=ttyGS0.* root=PARTUUID=47413336-02 rootwait' || bad "extlinux.conf root"
echo "$x" | grep -q initrd && bad "extlinux.conf still loads an initrd"
dd if="$img" of="$t/p2" bs=1M skip=272 count=3072 conv=sparse status=none
[ "$(dumpe2fs -h "$t/p2" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = ROOTFS ] || bad "p2 not ext4 ROOTFS"
debugfs -R 'stat /usr/local/lib/emulationstation/emulationstation' "$t/p2" 2>/dev/null | grep -q 'User: *0' || bad "ES missing on p2"
[ $fail = 0 ] && echo PASS
exit $fail
