#!/bin/sh
# FEL bring-up initramfs: busybox, evtest, alsa-utils, modetest, a colour-bar test image.
# Test-only, never part of an image. Needs ./build.sh uboot (mkimage). Runs inside the build container.
set -eu
r=out/build/initramfs
o=out/initramfs
rm -rf "$r"
mkdir -p "$o"
mmdebstrap --mode=fakechroot --variant=extract --architectures=armhf \
	--include=busybox-static,evtest,alsa-utils,libdrm-tests trixie "$r"
rm -rf "$r/usr/share/doc" "$r/usr/share/man" "$r/usr/share/locale" "$r/usr/share/info" "$r/var/cache" "$r/var/lib/apt"
# The extract variant creates no merged-usr links; the ELF interpreter is /lib/ld-linux-armhf.so.3.
for d in lib bin sbin; do
	if [ -e "$r/$d" ] && [ ! -L "$r/$d" ]; then echo "$r/$d is a real directory; cannot link it to usr/$d" >&2; exit 1; fi
	[ -L "$r/$d" ] || ln -s "usr/$d" "$r/$d"
done
mkdir -p "$r/proc" "$r/sys" "$r/dev" "$r/tmp"
install -m 755 tests/initramfs/init "$r/init"

# 8 vertical bars, left to right: white yellow cyan green magenta red blue black.
# A black 80x48 block in the top-left corner marks the orientation.
python3 - "$r/bars.raw" <<'EOF'
import sys
bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
w, h = 640, 480
out = bytearray()
for y in range(h):
    for x in range(w):
        r, g, b = (0, 0, 0) if x < 80 and y < 48 else bars[x * 8 // w]
        out += bytes((b, g, r, 0))
open(sys.argv[1], "wb").write(out)
EOF

(cd "$r" && find . | cpio -o -H newc -R 0:0 --quiet) | gzip -9 > "$o/initrd.cpio.gz"
out/build/u-boot/tools/mkimage -A arm -T ramdisk -C none -d "$o/initrd.cpio.gz" "$o/initrd.uimg" >/dev/null
# FEL loads it at 0x43400000; it must end below the ramoops region at 0x49000000.
[ $((0x43400000 + $(stat -c %s "$o/initrd.uimg"))) -le $((0x49000000)) ] \
	|| { echo "initrd.uimg too large: it would overlap ramoops" >&2; exit 1; }
