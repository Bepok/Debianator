# Firmware design

Date: 2026-10-14. Status: design approved; awaiting implementation plans for sub-projects 1 (boot) and 2 (kernel).

Background, findings and roadmap: [`../porting-plan.md`](../porting-plan.md). Hardware facts referenced below come
from [`../hardware/hardwareAnalysis.md`](../hardware/hardwareAnalysis.md).

## Goal

An installable firmware for the GA36-MB (Allwinner A33, 512 MiB) that other owners can flash to an SD card,
built entirely from this repository: mainline U-Boot and Linux with board patches, a Debian armhf rootfs,
EmulationStation and RetroArch.

## Scope

- **v1.0:** EmulationStation frontend, buttons, audio, battery level, power-off, s2idle sleep, silent charging
  while off.
- **v1.1:** analog sticks (stick MCU protocol unknown), charging animation (Linux-side charge mode; mainline U-Boot
  has no A33 DSI support).
- **Not planned yet:** N64, arcade (FBNeo), PSP, Nintendo DS (see porting plan, "Revisit later").

## Decisions

| Topic | Decision | Main reason |
|---|---|---|
| Kernel | mainline Linux 6.18 LTS | vendor 3.4 has no source; only maintainable route |
| Bootloader | mainline U-Boot v2026.10 | A33 support upstream; values already proven over FEL |
| Userspace base | Debian trixie armhf | glibc, familiar, apt on device; RetroPie-style systems run on 512 MiB |
| Frontend | EmulationStation fcamod (christianhaitian) with patched libgo2 | ArkOS/R36S look and handheld menus |
| U-Boot/kernel sources | patch series on pinned upstream tags | small repo, upstream-form patches |
| Build | shell scripts + mmdebstrap in a pinned Debian trixie container | no framework |
| Licence | GPL-2.0 | matches kernel and U-Boot patches |

Rejected:
- **Buildroot:** fast cross builds, ~100-150 MB rootfs, faster boot and more free RAM; but no RetroArch or libretro
  packages upstream (about nine packages to write) and no apt on the device.
- **Armbian:** the userspace is Debian anyway (same size and boot cost, apps still built here), a large framework
  aimed at general SBC images, and the board would be an unmaintained community config (`lime-a33.csc` is the only
  A33 one).
- **Alpine armv7:** musl, needs edge/testing pinning.
- **EmuELEC build system:** upstream stalled since 2023.
- Also rejected: forks as submodules, debos, an own apt repository, RetroPie EmulationStation (no handheld menus).

## 1. Repository layout and build flow

```
r36s-a33-ga36-debian/
  README.md                users: what, status, flashing
  build.sh                 ./build.sh [uboot|kernel|rootfs|apps|image|all]
  versions.env             pinned upstream versions + sha256
  container/Containerfile  debian:trixie + armhf cross gcc, mmdebstrap, qemu-user-static
  scripts/                 one script per stage
  uboot/                   ga36_defconfig, patches/
  kernel/                  ga36.config fragment, patches/
  rootfs/                  packages.list, overlay/, customize.sh
  apps/                    per-app build recipe (ES fcamod, libgo2 + patches/, cores)
  image/                   sfdisk layout, extlinux template
  docs/                    hardware/, porting-plan.md, specs/
  out/                     gitignored
```

- `build.sh` runs every stage inside the container; the host needs only Podman or Docker.
- Order: U-Boot and kernel cross-built from pinned tags with patches; `mmdebstrap` armhf rootfs; ES and cores built
  inside the rootfs under qemu-user; image assembled.
- Patches are kept as `git format-patch` series; bumping a pin means rebasing the series.

## 2. Boot chain and SD layout

Boot flow:
1. The boot ROM loads `u-boot-sunxi-with-spl.bin` from 8 KiB (replaces vendor boot0 and lichee U-Boot).
2. SPL: DRAM 552 MHz, ZQ 15291, ODT on; AXP rails DCDC1 3.0 V, DLDO3 3.0 V; console on UART2 (`CONS_INDEX=3`).
   Based on `A33-OLinuXino_defconfig` (values proven over FEL, hardware notes "On-device tests").
3. U-Boot bootstd finds `extlinux/extlinux.conf` on p1: zImage, GA36 DTB, `root=PARTUUID=...`.
4. No initramfs in v1.0 (MMC and ext4 built in); an initramfs arrives with the v1.1 charge mode.
5. U-Boot runs on the upstream A33-OLinuXino device tree (it needs only UART2 and MMC0); the kernel gets the GA36
   DTB through extlinux. If card detect (`PB4`) does not match, the GA36 DTS joins the U-Boot patch set.
6. No saved U-Boot environment.

SD layout (MBR; a GPT would overlap the SPL at 8 KiB):

| Region | Size | Contents |
|---|---|---|
| 0-8 KiB | | MBR |
| 8 KiB-16 MiB | | U-Boot + SPL, raw |
| p1 `BOOT` | 256 MiB FAT32 | zImage, DTB, extlinux.conf |
| p2 `ROOTFS` | 3 GiB ext4, fixed in every release | Debian armhf |
| p3 `ROMS` | rest of the card, exFAT | ROMs, BIOS, saves |

- The image ships p1 and p2. p3 is handled by a first-boot unit (section 5).
- Swap: zram (~256 MiB), no swap on the SD card; re-measure with ES and a PS1 game running.
- Charging while off: U-Boot board init disables the AXP power-on-by-charger-insertion. To verify on the device:
  the exact AXP223 register (datasheet) and that the board powers on at charger insertion today.
- Power-off: mainline AXP driver.
- Development loop: `sunxi-fel uboot ... write <addr> zImage dtb` boots kernels from the PC with the UART2
  console; SD card images only for release testing.

## 3. Kernel

- Linux 6.18 LTS (6.18.56 on 2026-10-14). Config: `sunxi_defconfig` plus the `kernel/ga36.config` fragment via
  `merge_config.sh`: DRM sun4i, sun6i DSI, lima, NV3051D panel, pwm-backlight, gpio-keys, AXP20x regulators,
  battery, ADC and power key, sun8i codec, simple-audio-amplifier, exFAT, zram, cpufreq-dt, thermal, MUSB OTG with
  the USB serial gadget.
- Patch series:
  1. `ARM: dts: sun8i: a33: add GA36-MB V1.0`, from the hardware mapping table: `r_rsb` and AXP223 rails,
     `cpu-supply` DCDC3, DSI with the panel child (reset `PH7`, power `dc1sw`), PWM0 backlight node named
     `backlight`, gpio-keys, MMC0 (card detect `PB4`), codec with the amplifier on `PH9`, USB OTG (ID `PH8`),
     UART2 console, UART1 enabled without a child.
  2. `drm/panel: nv3051d: make lane count and init sequence per-panel`. v6.18 hardcodes `dsi->lanes = 4` and
     shares `panel_nv3051d_init_sequence()`; existing panels keep 4 lanes and their sequence.
  3. `drm/panel: nv3051d: add GA36 panel`: 2 lanes, the table from `panel-init.txt`, 640x480 at 30 MHz,
     htotal 1040, vtotal 518 (~55.7 Hz).
  4. A dt-bindings patch for the new compatible.
- Buttons: one `gpio-keys` device with gamepad codes; FN on `PE1`.
- CPU: add 1.104 and 1.2 GHz OPPs with the vendor DVFS voltages (never above vendor values); the dtsi thermal
  zones throttle.
- Battery: `simple-battery` (3000 mAh, 4.2 V, 3.3 V minimum); level from the AXP fuel gauge.
- Sleep: `s2idle` (deep suspend is not available for the A33 in mainline), wake on the AXP power key.
- Risks:
  1. A33 DSI bring-up: no in-tree A33 board uses DSI.
  2. The fex `hbp`/`vbp` may include the sync width; verify on the panel and try a 60 Hz mode (~32.3 MHz).
  3. Headphone detect source unknown; fallback is both outputs on plus a manual toggle.
  4. v1.1 sticks likely need one combined buttons and sticks driver, so SDL sees a single joypad.
- Test on each FEL boot: panel image, `evtest` on all buttons, `speaker-test` on both outputs, battery sysfs,
  sleep and wake on the power key, `stress-ng` at 1.2 GHz with the temperature watched.

## 4. Userspace

- **Frontend:** ES fcamod with a patched libgo2. ES fcamod renders through libgo2 (the Odroid Go Advance library),
  which calls the Rockchip RGA blitter (`c_RkRgaBlit`, `c_RkRgaColorFill`) and hardcodes
  `/sys/class/power_supply/battery`; the A33 has no RGA. Patch series in `apps/libgo2/patches/`: pixman instead of
  RGA, battery path of `axp20x-battery`. The backlight path `/sys/class/backlight/backlight` already matches the
  DT node name.
- **Rootfs:** `mmdebstrap` trixie armhf minbase plus `rootfs/packages.list`: systemd, udev, Mesa (lima: EGL, GLES,
  GBM), ALSA, SDL2, pixman, exfatprogs, systemd-zram-generator, triggerhappy. No networking in v1.0 (no Wi-Fi).
  Serial getty on UART2 and on the USB gadget ACM port `ttyGS0`. Autologin user `ga36` on tty1 starts ES through
  a systemd unit that restarts it on exit.
- **RetroArch and cores:** the Debian package when one exists and is fast enough on the A7; otherwise built from a
  pinned commit in `apps/`.

  | System | Core | Source |
  |---|---|---|
  | NES | nestopia | Debian |
  | GB/GBC | gambatte | Debian |
  | SNES | snes9x2010 | build |
  | GBA | gpsp | build |
  | Mega Drive / SMS / Game Gear | picodrive | build |
  | PC Engine | beetle-pce-fast | build |
  | PS1 | pcsx_rearmed | build |
  | RetroArch | 1.20.0 | Debian |

- **Power and controls:**
  - power key short press suspends (s2idle), long press powers off (logind `HandlePowerKeyLongPress`); the AXP's
    hardware forced-off stays as the last resort;
  - a udev rule powers off cleanly at 3 % while discharging; the AXP also cuts power at 3.3 V;
  - triggerhappy: Vol+/Vol- set ALSA volume, clamped at the vendor maximum; FN+Vol sets backlight brightness;
    a headphone/speaker toggle if headphone detection stays unsolved;
  - RetroArch: FN+Start exits to ES.
- **First boot:** create or restore p3 (section 5) and the per-system folders that `es_systems.cfg` points at.
- **Test on the device:** cold boot to ES (timed), each core at full speed on a test ROM, RAM use with ES and
  pcsx_rearmed running, hotkeys and the volume cap, suspend and resume in and out of a game, low-battery shutdown.

## 5. Image, release and CI

- `scripts/make-image.sh` works rootless, with no loop mounts: p1 via `mkfs.vfat -C` and `mcopy`; p2 via
  `mkfs.ext4 -d`; `sfdisk` writes the MBR; `dd` places p1 and p2 at their offsets and U-Boot at 8 KiB.
- Output: a sparse image compressed to `r36s-a33-ga36-debian-vX.Y.Z.img.xz`, plus `SHA256SUMS`.
- p2 is a fixed 3 GiB, so p3 always starts at the same offset. Reflashing drops the p3 MBR entry but not its data.
  The first-boot unit checks that offset: if an exFAT filesystem is there it only restores the partition entry;
  it formats only when nothing is there. The README still says to back up saves before upgrading.
- README install guide: back up the stock card; flash with balenaEtcher, Raspberry Pi Imager or `xzcat | dd` to a
  separate card; identify the GA36 revision by the board marking; return to stock.
- Versions: semver tags, `v1.0.0` for the v1.0 scope, `v1.1.0` for sticks and the charging animation.
  Release gate: the section 4 device checklist passes on V1.0; release notes name the tested revision and the items
  checked by a person.
- CI: one GitHub Actions workflow on tag push and manual dispatch. It runs `./build.sh all` in the same container
  and attaches the `.img.xz` and `SHA256SUMS` to the GitHub Release.
- Docs: README (users), `docs/porting-plan.md`, `docs/specs/`, `docs/hardware/`. No CHANGELOG; release notes live on
  GitHub Releases.

## Testing

Development setup: USB OTG (FEL) and an FT232 adapter on UART2.

| Unattended over FEL and UART2 | Needs a person at the device |
|---|---|
| build everything, FEL-boot kernels, read boot logs | power key presses (FEL entry, power-on, sleep/wake) |
| DRM/panel state (`modetest`, dmesg), not the pixels | confirm the picture (colours, orientation, flicker) |
| `evtest` capture | press each button and combo on request |
| ALSA state, `speaker-test` runs | listen: speaker, headphones, volume cap |
| battery/charger sysfs, thermal under `stress-ng`, RAM use | plug/unplug the charger; swap SD cards |
| boot time (UART timestamps), RetroArch FPS from logs | judge game smoothness and input feel |
| suspend/resume via `rtcwake` or `/sys/power/state` | wake from sleep with the power key |

- FEL only loads code; it shows nothing. UART2 is required for bring-up (U-Boot and kernel logs, earlycon, panics
  before USB, a black panel during DSI bring-up). Once the kernel is up, the USB gadget console `ttyGS0` on the OTG
  port gives a shell and logs without a UART adapter; it misses only crashes before USB starts.
- Revisions V1.1 and V1.2 are untested until community testers report back. The README says so and asks testers
  for logs over the USB gadget console (no soldering), UART only if the board does not boot that far.
- Each test stage gets a checklist; items needing a person are batched.

## Recovery and safety

- Software changes are fully reversible: the board has no eMMC or NAND, everything lives on the SD card. Restore by
  writing the stock image or the user's own card backup.
- The board cannot be soft-bricked: with no bootable card the boot ROM enters USB FEL.
- The irreversible risks are hardware ones. Guard rails: AXP rail and CPU OPP voltages never above the vendor
  values; speaker volume capped at the vendor level (the wiki reports ArkOS4Clone overdriving speakers on V20
  clones); charge voltage and current only from the vendor `[pmu1_para]`.
- The AXP power-on-by-charger setting persists while the battery is connected, so the stock firmware may not show
  its charging animation until the battery drains or is disconnected. Recoverable; documented in the README.
- README install guide: back up the stock card first, flash this firmware to a separate card, keep the stock card.
