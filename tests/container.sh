#!/bin/sh
# The build container has every tool the stages use. Run: ./build.sh run tests/container.sh
set -eu
fail=0
for tool in arm-linux-gnueabihf-gcc gcc make bison flex bc python3 swig git curl xz cpio rsync \
	fdtget dtc dt-validate mmdebstrap fakechroot mcopy mkfs.vfat sfdisk; do
	command -v "$tool" >/dev/null || { echo "FAIL: $tool missing"; fail=1; }
done
[ "$(id -u)" != 0 ] || { echo "FAIL: running as root"; fail=1; }
[ $fail = 0 ] && echo PASS
exit $fail
