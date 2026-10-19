#!/bin/sh
# The build container has every tool the stages use. Run: ./build.sh run tests/container.sh
set -eu
fail=0
for tool in arm-linux-gnueabihf-gcc arm-linux-gnueabihf-g++ cmake pkg-config gcc make bison flex bc python3 swig git curl xz cpio rsync \
	fdtget dtc dt-validate mmdebstrap fakechroot mcopy mkfs.vfat sfdisk mkfs.ext4 debugfs mkfs.exfat arch-test; do
	command -v "$tool" >/dev/null || { echo "FAIL: $tool missing"; fail=1; }
done
# Cores are cross-compiled against armhf GLES2/EGL, zlib and libpng from Debian multiarch.
for f in /usr/lib/arm-linux-gnueabihf/libGLESv2.so /usr/lib/arm-linux-gnueabihf/libEGL.so \
	/usr/lib/arm-linux-gnueabihf/libz.so /usr/lib/arm-linux-gnueabihf/libpng.so /usr/include/GLES2/gl2.h; do
	[ -e "$f" ] || { echo "FAIL: armhf $f missing"; fail=1; }
done
[ "$(id -u)" != 0 ] || { echo "FAIL: running as root"; fail=1; }
# rootfs and apps chroot into armhf; binfmt_misc is the host's.
arch-test armhf >/dev/null 2>&1 || { echo "FAIL: armhf binaries do not run: install qemu-user-binfmt on the host (its qemu-arm entry needs the F flag)"; fail=1; }
# The test card's p2 is made with mkfs.ext4 -d <tarball>, which needs libarchive.
t=$(mktemp -d)
mkdir "$t/r"
echo x > "$t/r/f"
tar -C "$t/r" -cf "$t/r.tar" .
if ! mkfs.ext4 -q -d "$t/r.tar" "$t/fs" 8M 2>/dev/null || [ "$(debugfs -R 'cat /f' "$t/fs" 2>/dev/null)" != x ]; then
	echo "FAIL: mkfs.ext4 -d cannot read a tarball"; fail=1
fi
rm -rf "$t"
[ $fail = 0 ] && echo PASS
exit $fail
