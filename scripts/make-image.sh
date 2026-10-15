#!/bin/sh
# SD card image: U-Boot at 8 KiB, p1 FAT32 BOOT (kernel, DTB, extlinux.conf), p2 ext4 ROOTFS from
# out/rootfs/rootfs.tar. p3 (ROMS) is made on the device at first boot (ga36-roms.service).
# Output in out/image: r36s-a33-ga36-debian-$VERSION.img (sparse, for writing a card locally), its .img.xz (the
# release asset) and SHA256SUMS. Rootless, no loop mounts. Runs inside the build container (./build.sh image).
set -eu
o=out/image
name=r36s-a33-ga36-debian-${VERSION:-dev}
img=$o/$name.img
p1=$o/p1.vfat
p2=$o/p2.ext4
rm -rf "$o"
mkdir -p "$o"

# root=PARTUUID matches label-id below and rootfs/overlay/etc/fstab.
cat > "$o/extlinux.conf" <<'EOT'
label ga36
	kernel /zImage
	fdt /sun8i-a33-gameconsole-r36s-ga36.dtb
	append console=ttyGS0,115200 console=tty0 panic=5 root=PARTUUID=47413336-02 rootwait
EOT
mkfs.vfat -F 32 -n BOOT -C "$p1" $((256 * 1024)) >/dev/null
mmd -i "$p1" ::/extlinux
mcopy -i "$p1" "$o/extlinux.conf" ::/extlinux/
mcopy -i "$p1" out/kernel/zImage out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb ::/
mkfs.ext4 -q -L ROOTFS -d out/rootfs/rootfs.tar "$p2" 3G

# p2 is a fixed 3 GiB so p3 always starts at sector 6848512 (spec section 5).
truncate -s $(( (16 + 256 + 3072) * 1024 * 1024 )) "$img"
sfdisk -q "$img" <<'EOT'
label: dos
label-id: 0x47413336
start=32768, size=524288, type=c, bootable
start=557056, size=6291456, type=83
EOT
dd if=out/u-boot/u-boot-sunxi-with-spl.bin of="$img" bs=1024 seek=8 conv=notrunc status=none
dd if="$p1" of="$img" bs=1M seek=16 conv=notrunc status=none
dd if="$p2" of="$img" bs=1M seek=272 conv=notrunc,sparse status=none
rm "$p1" "$p2" "$o/extlinux.conf"

xz -T0 -k "$img"
(cd "$o" && sha256sum "$name.img.xz" > SHA256SUMS)
