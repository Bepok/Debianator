#!/bin/sh
# Development only, never part of an image.
# Boot the board over USB FEL and wait for its console on the same cable.
# Usage: scripts/fel-boot.sh uboot|kernel
#   uboot   U-Boot only; it skips autoboot and its prompt comes up on /dev/ga36-uboot
#   kernel  U-Boot, zImage, GA36 DTB and the test initramfs, booted by out/u-boot/fel.scr; shell on /dev/ga36-linux
# Env: SUNXI_FEL (default sunxi-fel), TIMEOUT seconds (default 90).
# Needs scripts/70-ga36-usb.rules installed. Prints `version` or `uname -r` from the board; exit 0 when it answered.
set -eu
cd "$(dirname "$0")/.."
FEL=${SUNXI_FEL:-sunxi-fel}
TIMEOUT=${TIMEOUT:-90}
usage() { echo "usage: $0 uboot|kernel" >&2; exit 2; }
[ $# -eq 1 ] || usage
mode=$1
in_fel() { lsusb -d 1f3a:efe8 >/dev/null; }

case $mode in
	uboot) dev=/dev/ga36-uboot probe=version
		set -- uboot out/u-boot/u-boot-sunxi-with-spl.bin ;;
	kernel) dev=/dev/ga36-linux probe='uname -r'
		set -- uboot out/u-boot/u-boot-sunxi-with-spl.bin \
		write 0x42000000 out/kernel/zImage \
		write 0x43000000 out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb \
		write 0x43400000 out/initramfs/initrd.uimg \
		write 0x43100000 out/u-boot/fel.scr ;;
	*) usage ;;
esac

# The boot ROM runs one upload per power-on; a second one hangs in usb_bulk_send().
if ! timeout 5 "$FEL" ver >/dev/null 2>&1; then
	echo "no board in FEL: power it off, remove the SD card, press the power key (one upload per power-on)" >&2
	exit 1
fi

if ! "$FEL" -v "$@"; then
	sleep 2
	if in_fel; then
		echo "FEL upload failed" >&2
	else
		# The SPL switches the board off when the power-on source was the charger (no UART to say so).
		echo "the board switched itself off during the upload: it was powered on by plugging in the cable; power it on with the power key" >&2
	fi
	exit 1
fi

sleep 3   # the boot ROM's FEL device disappears once U-Boot runs
end=$(( $(date +%s) + TIMEOUT ))
until [ -e "$dev" ]; do
	if in_fel; then
		echo "the board reset back into FEL (kernel panic?): FEL-boot again and read /sys/fs/pstore" >&2
		exit 1
	fi
	if [ "$mode" = kernel ] && [ -e /dev/ga36-uboot ]; then
		echo "bootz failed; U-Boot's console is on /dev/ga36-uboot:" >&2
		TTY=/dev/ga36-uboot scripts/board-run.sh 'printenv bootargs' >&2 || true
		exit 1
	fi
	if [ "$(date +%s)" -ge "$end" ]; then
		echo "timeout after ${TIMEOUT}s waiting for $dev" >&2
		exit 1
	fi
	sleep 1
done
TTY=$dev scripts/board-run.sh "$probe"
