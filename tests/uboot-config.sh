#!/bin/sh
# The built U-Boot config carries the vendor DRAM and rail values, no saved environment, and drives
# neither PB2 (BTN_THUMBR, the base config's backlight enable) nor VBUS. Its USB ACM console starts only on a
# FEL boot without a script, so a card boot never waits for a USB host; the board code probes the MUSB gadget,
# which upstream sunxi does only for USB Ethernet. Run: ./build.sh run tests/uboot-config.sh
set -eu
c=out/build/u-boot/.config
[ -f "$c" ] || { echo "FAIL: $c missing (./build.sh uboot)"; exit 1; }
fail=0
on() { grep -qxF "$1" "$c" || { echo "FAIL: want $1"; fail=1; }; }
off() { ! grep -q "^$1=" "$c" || { echo "FAIL: $1 must be off"; fail=1; }; }

on CONFIG_MACH_SUN8I_A33=y
on CONFIG_DRAM_CLK=552
on CONFIG_DRAM_ZQ=15291
on CONFIG_DRAM_ODT_EN=y
# vendor [power_sply]: dcdc1 3000, dcdc2 1100, dcdc3 1200, dcdc5 1500, aldo2 2500, aldo3 3000, dldo3 3000.
# aldo1 is not in the fex: 3000 is U-Boot's MACH_SUN8I default and the A33 reference design's vcc-io.
on CONFIG_AXP_DCDC1_VOLT=3000
on CONFIG_AXP_DCDC2_VOLT=1100
on CONFIG_AXP_DCDC3_VOLT=1200
on CONFIG_AXP_DCDC5_VOLT=1500
on CONFIG_AXP_ALDO1_VOLT=3000
on CONFIG_AXP_ALDO2_VOLT=2500
on CONFIG_AXP_ALDO3_VOLT=3000
on CONFIG_AXP_DLDO3_VOLT=3000
on CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y
on CONFIG_ENV_IS_NOWHERE=y
off CONFIG_REGULATOR_AXP           # DM regulators would apply the OLinuXino DT's 3.3 V rails
off CONFIG_VIDEO_SUNXI
off CONFIG_USB_MUSB_HOST
off CONFIG_REGULATOR_AXP_DRIVEVBUS
on CONFIG_USB_MUSB_GADGET=y
on CONFIG_USB_FUNCTION_ACM=y
on CONFIG_CONSOLE_MUX=y
off CONFIG_USB_ETHER                # would claim the gadget controller at boot
# initrd_high on every boot path: bootm_size (0xa000000) would move a large initrd onto ramoops (0x49000000).
on 'CONFIG_PREBOOT="setenv initrd_high 0xffffffff; if test -n \"${fel_booted}\" && test -z \"${fel_scriptaddr}\"; then setenv bootdelay -1; setenv stdin serial,usbacm; setenv stdout serial,usbacm; setenv stderr serial,usbacm; fi"'
if grep '^CONFIG_ENV_IS_IN_.*=y' "$c"; then echo "FAIL: saved environment enabled"; fail=1; fi
# Strong symbol (T), not the weak no-op (W) of g_dnl.c: without it usbacm finds no controller.
arm-linux-gnueabihf-nm out/build/u-boot/u-boot | grep -q ' T board_usb_init$' \
	|| { echo "FAIL: board_usb_init not overridden"; fail=1; }
[ $fail = 0 ] && echo PASS
exit $fail
