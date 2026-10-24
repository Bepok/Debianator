# Multi-board research

Date: 2026-10-24. Status: open; no change made, waiting for a second board.
Context: [`../porting-plan.md`](../porting-plan.md), [`../specs/2026-10-14-firmware-design.md`](../specs/2026-10-14-firmware-design.md).

## Summary

Handheld firmwares build one kernel and rootfs per SoC and treat a board as a DTB name, an optional U-Boot defconfig
and a few overlay files; on mainline the DTB is fixed per image. For this repository: three cheap changes now (one
board file, devices found rather than named, one gamepad name), the board layer only once a second board is in hand.
An A23 GA36 is SoC work, an RK3326 R36S is a second architecture.

## Question

What would it take for this repository to build images for boards other than the GA36-MB V1.0, and how do other
handheld firmwares organise many boards? Sources: the source trees of ROCKNIX, knulli, Batocera, Armbian, dArkOS,
arkos4clone, dArkOS-G80CA-RE and ArkOS, read as shallow clones and through the GitHub API (no code from them run).

## Candidate boards

| Board | What differs from the GA36 V1.0 | Cost |
|---|---|---|
| GA36 V1.1, V1.2 (A33) | probably nothing; V1.1 and V1.2 vendor fex files are identical | a test report |
| GA36 V1.2 with an A23 | other SoC inside the same revision (`sunxi-fel version`: `1650` A23, `1667` A33), 2 cores | own U-Boot SPL (likely: `MACH_SUN8I_A23`), own DTS; mainline `sun8i-a23.dtsi` has no DSI, D-PHY or thermal nodes, which would have to be written |
| Other A33/A23/R16 devices | mainline has only tablets and dev boards (Q8, OLinuXino, SinA33, NES/SNES Classic); no handheld | test bench at most |
| Original R36S (RK3326) | arm64; no R36S DTS or U-Boot defconfig in mainline (ROCKNIX carries one out of tree with ~30 patches); U-Boot needs TF-A and an rkbin DDR blob; panel varies by batch | a second architecture: every app rebuilt for arm64 |

Open facts: one V1.1 report says 1 GiB RAM where others say 512 MiB; the A23 SPL split is inferred, not checked in
U-Boot's Kconfig.

## How others do it

- **The SoC is the build unit, the board is a thin layer** (ROCKNIX, knulli, Batocera, Armbian). One kernel config
  and one rootfs per SoC; a board is a DTB name, sometimes a U-Boot defconfig, and a few files.
  - Armbian: `config/boards/<board>.conf` (flat variables: `BOARDFAMILY`, `BOOTCONFIG`, ...), a family file, and
    `sunxi_common.inc`. Board rootfs files are overlays stacked common, arch, family, board.
  - Batocera/knulli: `configs/<soc>.board` plus `board/batocera/<vendor>/<soc>/<board>/` holding only image glue.
    One rootfs per SoC, one `.img` per board, the DTB fixed in each board's `extlinux.conf`.
- **DTB choice.** Simplest and most common on mainline: fixed at image-build time, one image per board (Batocera
  H700). Boot-time detection exists only where clones share one U-Boot (ROCKNIX RK3326: an ADC reading in
  `boot.ini`). Panel variants are handled by shipping several DTBs and copying one into place (dArkOS, arkos4clone,
  dArkOS-G80CA-RE); arkos4clone needs a host-side Go tool for it.
- **Runtime board identity.** Good: DT `model` (ROCKNIX `QUIRK_DEVICE` from `/sys/firmware/devicetree/base/model`)
  or a board name stamped at build time (Batocera `/boot/boot/batocera.board`, dArkOS `~/.config/.DEVICE`). Bad:
  testing which DTB file exists in `/boot` (ArkOS, hundreds of copied OR-chains) and `/proc/cpuinfo` `Hardware:`,
  which mainline does not fill from the DT.
- **Per-board settings are data, not code.** ROCKNIX quirk scripts write `DEVICE_*` variables (mixer path, LED GPIO,
  temperature sensor); dArkOS-G80CA-RE keys an INI by DT `model`; arkos4clone branches on attributes (`dualJoy`,
  `rotate`) instead of board names. The counter-example is dArkOS: per-device near-copy build scripts and ~90
  inline `if [ "$UNIT" = ... ]`, with a real silent bug (`KERNEL_DTB_ALT_RGB10S` never set).
- **Names are fixed low down.** ROCKNIX patches the kernel so the battery is `battery` and gives every pad of a SoC
  family one input name ("H700 Gamepad"), so one `es_input.cfg` entry covers all boards. Scripts glob
  `/sys/class/power_supply/[Bb][Aa][Tt]*`.
- **CI is a matrix** over SoCs (ROCKNIX) or boards, calling one build with a parameter.

## Where this repository is tied to the GA36

- Boot: `uboot/ga36_defconfig`; the DTB name in `scripts/build-kernel.sh`, `scripts/make-image.sh`,
  `scripts/fel-boot.sh`; `ga36_init` from uboot patch 0002 (AXP221 only).
- Build: Cortex-A7 flags and `platform=classic_armv7_a7` in `apps/build-in-chroot.sh` and `scripts/build-cross.sh`;
  armhf in `build-rootfs.sh`, `build-apps.sh`, `build-kernel.sh`.
- Runtime: `axp20x-battery`, `axp20x-usb`, `axp22x-ac` (`apps/ga36-charge.c`, `ga36-lowbat.service`),
  `/sys/class/backlight/backlight`, mixer `Headphone` (triggerhappy, `asound.state`, ES patch 0004),
  `/dev/mmcblk0p3` (`ga36-roms.service`), `cpufreq/policy0`, `GA36 Gamepad` in `es_input.cfg`.
- Tests assert these values directly.
- Naming: ~60 files carry `ga36` (user, services, scripts, the `ga36-base` tag). Most are not board-specific and can
  keep the name.

## Recommendation

**Do not restructure until a second board is in hand.** Without a unit to test, a board layer is designed for
guesses. The likely first one, an A23 GA36, needs SoC work (SPL, DSI nodes) far larger than any repository change.

Cheap now, useful whatever the next board is:

1. **One board file.** `boards/ga36.env` with `ARCH`, `UBOOT_DEFCONFIG`, `DTB`, `KERNEL_CONFIG`; the build scripts
   source `boards/$BOARD.env` (default `ga36`) instead of naming the DTB in three places. Write the extlinux `fdt`
   line from `$DTB`.
2. **Find devices instead of naming them** where the name is the board's, not the design's: the backlight as the
   one entry under `/sys/class/backlight/`, the ROMS partition from the root device rather than `/dev/mmcblk0`. The
   AXP power-supply names stay: they are the PMIC driver's names, shared by every AXP22x board.
3. **Keep one gamepad name** for every board this project supports (set by its driver or DTS), so `es_input.cfg`
   and RetroArch autoconfig stay single files.

When a second board exists:

4. **One image per board, DTB fixed at build time.** Image name `debianator-<board>-vX.Y.Z.img.xz`. The A23/A33
   split forces this anyway (different SPL), and it needs no boot-time logic.
5. **Overlay stack** `rootfs/overlay/` (common) then `boards/<board>/overlay/`, copied in that order by
   `rootfs/customize.sh`. Stamp the board name into the image (`/etc/debianator-board`) for scripts and bug reports.
6. **Per-SoC, not per-board, kernel config and app flags.** One kernel build per SoC shipping every board's DTB;
   CPU flags from the board file's SoC.
7. **Tests take `BOARD`**; CI becomes a matrix over boards that reuses one `apps` build per architecture.

Avoid: per-board copies of build scripts, `if [ "$BOARD" = ... ]` scattered through scripts, detecting the board by
which DTB is present, and a boot-time DTB selector before two boards share one U-Boot.

**An arm64 board (RK3326 R36S) is a different project size.** The board layer above is the same, but `apps` must
be built twice (about 2.5 h each on GitHub's runner today), U-Boot needs TF-A and a Rockchip DDR blob at a 32 KiB
offset, and the kernel image is `Image` without `bootz`. Keep `ARCH`, the cross-compiler, the kernel image name and
the U-Boot offset in the board/SoC file from the first step so this stays possible.
