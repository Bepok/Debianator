#!/bin/sh
# Release image in out/image: exactly r36s-a33-ga36-debian-<version>.img, its .img.xz and SHA256SUMS. The image has
# U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files and p2 ext4 ROOTFS (3 GiB) right after.
# Run: ./build.sh run tests/image.sh
set -eu
o=out/image
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -d "$o" ] || { echo "FAIL: $o missing (./build.sh image)"; exit 1; }
set -- "$o"/*.img
[ $# = 1 ] && [ -f "$1" ] || { echo "FAIL: want one .img in $o, found: $*"; exit 1; }
img=$1
n=$(basename "$img" .img)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# Name, file set and checksums. The version part is a tag (v1.0.0), a describe string (v1.0.0-3-g0754139-dirty) or,
# with no tags, a bare commit id.
echo "$n" | grep -Eq '^r36s-a33-ga36-debian-[0-9A-Za-z][0-9A-Za-z.+-]*$' || bad "image name $n"
[ "$(ls "$o" | sort)" = "$(printf '%s\n' "$n.img" "$n.img.xz" SHA256SUMS | sort)" ] ||
	bad "$o holds: $(ls "$o" | paste -sd' '); want $n.img $n.img.xz SHA256SUMS"
[ "$(cat "$o/SHA256SUMS" 2>/dev/null | wc -l)" = 1 ] && grep -q "  $n.img.xz\$" "$o/SHA256SUMS" ||
	bad "SHA256SUMS is not one line for $n.img.xz"
(cd "$o" && sha256sum -c --status SHA256SUMS) || bad "SHA256SUMS does not verify"
xz -dc "$o/$n.img.xz" 2>/dev/null | cmp -s - "$img" || bad "$n.img.xz does not unpack to $n.img"

# Layout.
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
echo "$x" | grep -q 'append .*console=ttyGS0.* root=PARTUUID=47413336-02 rootwait init=${ga36_init}$' || bad "extlinux.conf root and init"
echo "$x" | grep -q initrd && bad "extlinux.conf still loads an initrd"
dd if="$img" of="$t/p2" bs=1M skip=272 count=3072 conv=sparse status=none
[ "$(dumpe2fs -h "$t/p2" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = ROOTFS ] || bad "p2 not ext4 ROOTFS"
debugfs -R 'stat /usr/local/lib/emulationstation/emulationstation' "$t/p2" 2>/dev/null | grep -q 'User: *0' || bad "ES missing on p2"
[ $fail = 0 ] && echo PASS
exit $fail
