# Charge mode design

Date: 2026-10-16. Status: implemented, checked on V1.0 (hardware notes, "Charge mode (v1.1)"). Release: v1.1 ("Charging animation" in [`../porting-plan.md`](../porting-plan.md)).
Parent design: [`2026-10-14-firmware-design.md`](2026-10-14-firmware-design.md).

## Why

In v1.0, plugging the charger into a powered-off GA36 shows nothing: the SPL sees a plug-in power-on, switches the
board off again (`CONFIG_AXP_DISABLE_BOOT_ON_POWERON`), and only the charge LED is lit. The owner cannot tell that
it is charging or how full it is without booting. v1.1 shows it.

## Behaviour (decided with the owner)

- Charger plugged into a powered-off console: a battery icon with the current charge level appears, then the
  screen turns off. Charging continues.
- Short power-key press while in charge mode: the icon shows again.
- Long power-key press while in charge mode: the console boots into EmulationStation, as a normal power-on does.

Our calls, played back to the owner and not objected to:

- The icon stays up about 5 s, then the screen goes dark.
- Unplugging the charger in charge mode powers the board fully off.
- A full battery shows a full icon. The charge LED is whatever the AXP does on its own.
- A few seconds pass between plug-in and the icon: Linux has to boot to draw it (mainline U-Boot has no A33 DSI
  support, so U-Boot cannot draw it).
- No sound; no other key does anything.
- Normal power-on (power key), sleep, power-off and the 3 % low-battery shutdown are unchanged.

## Non-goals

- Animation beyond a static icon (a fill that steps while charging is not required).
- Charge mode from sleep or while running: only from powered off.
- Changing charge current or voltage (they stay the vendor `[pmu1_para]` values).

## Anti-goals

Even if the icon works, it is a failure if:

- a normal power-key power-on gets slower than about 0.5 s, or behaves differently;
- the console can get stuck on with the charger unplugged (drains the battery in a drawer);
- a crash in charge mode leaves the screen lit, or loops reboots.

## How it works

### Boot path

1. `CONFIG_AXP_DISABLE_BOOT_ON_POWERON` is removed from `uboot/ga36_defconfig`, so a plug-in power-on runs U-Boot.
2. A U-Boot board patch (next to `uboot/patches/0001-*`) reads AXP221 register `AXP_POWER_STATUS` (0x00) bit 0
   (`AXP_POWER_STATUS_ALDO_IN`, the plug-in boot source the SPL checks today) in U-Boot proper and sets one
   environment variable, `ga36_init`: the charge-mode program on a plug-in power-on, `/sbin/init` otherwise.
3. The extlinux `append` line in `scripts/make-image.sh` gains `init=${ga36_init}`. U-Boot's `pxe_utils` expands
   `${...}` in `append` (`cli_simple_process_macros`), so no second boot label is needed.
4. The kernel mounts p2 as usual and runs the charge-mode program as PID 1.
5. Long press: the program `exec`s `/sbin/init`, and systemd boots EmulationStation from there.
6. Charger unplugged: the program powers off (`reboot(RB_POWER_OFF)`, AXP power-off through the mainline driver).

Our call: **no initramfs**, against the roadmap line "charge mode from initramfs". The charge program runs as
`init=` on the existing rootfs. It adds no boot stage, no `switch_root`, and nothing to the normal boot, which
meets the first anti-goal by construction. The parent spec's "an initramfs arrives with the v1.1 charge mode" and
the roadmap line are corrected when this lands.

### The program

One small C program, our call, built in the apps stage (`scripts/build-apps.sh`, armhf chroot) and installed under
`/usr/local`, like the other apps. As PID 1 it does only this:

- mount `/proc`, `/sys`, `/dev` (devtmpfs), since nothing else has;
- read `/sys/class/power_supply/axp20x-battery/capacity` and the charger `online` files (`axp20x-usb`,
  `axp22x-ac`);
- draw the icon on the panel through a DRM dumb buffer on `sun4i-drm` (there is no `/dev/fb0`), then after about
  5 s disable the CRTC (the panel driver's disable turns the backlight off);
- read the power key from the `axp20x-pek` input device: short press redraws, a hold over 2 s (the same threshold
  as `HandlePowerKeyLongPress` in `rootfs/overlay/etc/systemd/logind.conf.d/ga36.conf`) execs `/sbin/init`;
- while dark, wait in s2idle (`/sys/power/state` `freeze`), woken by the power key (proven in v1.0) and by an RTC
  alarm every 60 s at most, to check the charger. Unplugged: power off.
- on any error it cannot handle: panel off, then power off. It never returns (PID 1 exiting panics the kernel, and
  `panic=5` reboots; the boot-source bit is clear after a reboot, so that boots the system with the charger in).

The icon is our call and the builder's to draw: a battery outline with a fill proportional to `capacity`, no text
(no font to ship). Panel orientation is the same as the one ES uses.

## Constraints

- Everything builds in the pinned container through `./build.sh`; no new host dependency.
- The rootfs is read-only at that point (the kernel mounts root read-only until systemd remounts it); the program
  writes nothing to the card.
- Battery limits stay as v1.0: power-off at 3.3 V / 3 %.

## Open risks (check on the device first)

Measured answers are in the hardware notes.

- **Boot-source bit in U-Boot proper.** Answered: U-Boot proper sees register 0x00 bit 0 set on a cold plug-in
  start, and the bit is clear after any reboot, so a reboot never lands in charge mode (no marker needed).
- **Charger unplug as a wake source.** Answered: VBUS removal does not wake s2idle; the 60 s RTC alarm is what
  notices an unplug. `CONFIG_RTC_INTF_SYSFS` is unset, so the alarm is set through `/dev/rtc0` ioctls.
- **Flat battery.** Open: plug-in at the 3 % cutoff was not run. If it loops, U-Boot skips charge mode below a
  voltage read from the AXP and powers off as v1.0 does.
- **Power key held through boot.** Answered: power-key power-ons, with and without the charger, boot into ES.

## Testing

Unattended (FEL, `ttyGS0`): U-Boot sets `ga36_init` for each boot source; the program's log on the serial gadget;
DRM state with the panel off; s2idle entry and RTC wake. Needs a person: the picture, short and long press, unplug
to power-off, a normal power-on unchanged, the flat-battery plug-in. Added to the device checklist in
`docs/hardware/hardwareAnalysis.md` like the v1.0 items.

## Left to the builder

- The exact icon geometry and colours.
- The program's source layout and name, and how it logs.
- The U-Boot hook point (`misc_init_r`, `board_late_init` or similar) and the default value of `ga36_init` when the
  read fails (`/sbin/init`: fail towards a normal boot).
