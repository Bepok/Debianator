# Firmware design

Date: 2026-10-14. Status: design approved; sub-projects 1 to 4 implemented.

**Note, 2026-10-23:** this is the original design, kept as written. Since then:
- The kernel patch series is the one in [`../../kernel/patches/`](../../kernel/patches/): the buttons moved from
  `gpio-keys` into the `ga36-gamepad` driver on UART1, and the panel runs at 60 Hz (29.7 MHz, htotal 955).
- v1.1 grew beyond sticks and charging: 60 Hz, DOS, N64 and PSP (experimental) and Heroes 3, each with its own
  design in this folder; the [porting plan](../porting-plan.md) has the roadmap.
- The kernel risks below are resolved: the sticks share one driver with the buttons, the panel reached 60 Hz, and
  headphones mute the speaker in hardware.
- `build.sh` also has the `initramfs` and `run` stages, and `docs/` also holds `research/` and `patches/`.

Background, findings and roadmap: [`../porting-plan.md`](../porting-plan.md). Hardware facts referenced below come
from [`../hardware/hardwareAnalysis.md`](../hardware/hardwareAnalysis.md).

## Goal

An installable firmware for the GA36-MB (Allwinner A33, 512 MiB) that other owners can flash to an SD card,
built entirely from this repository: mainline U-Boot and Linux with board patches, a Debian armhf rootfs,
EmulationStation and RetroArch.

## Scope

- **v1.0:** EmulationStation frontend, buttons, audio, battery level, power-off, s2idle sleep, silent charging
  while off.
- **v1.1:** analog sticks (stick MCU protocol unknown), charging animation (Linux-side charge mode run as `init=`; mainline
  U-Boot has no A33 DSI support).
- **Not planned yet:** N64, arcade (FBNeo), PSP, Nintendo DS (see porting plan, "Revisit later").

## Decisions

| Topic | Decision | Main reason |
|---|---|---|
| Kernel | mainline Linux 6.18 LTS | vendor 3.4 has no source; only maintainable route |
| Bootloader | mainline U-Boot v2026.10 | A33 support upstream; values already proven over FEL |
| Userspace base | Debian trixie armhf | glibc, familiar, apt on device; RetroPie-style systems run on 512 MiB |
| Frontend | EmulationStation fcamod (christianhaitian) with a small patch series | ArkOS/R36S look and handheld menus |
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
Debianator/
  README.md                users: what, status, flashing
  build.sh                 ./build.sh [uboot|kernel|rootfs|apps|image|all]
  versions.env             pinned upstream versions + sha256
  container/Containerfile  debian:trixie + armhf cross gcc, mmdebstrap; host qemu-user-binfmt for apps/rootfs
  scripts/                 one script per stage
  uboot/                   ga36_defconfig, patches/
  kernel/                  ga36.config fragment, patches/
  rootfs/                  packages.list, overlay/, customize.sh
  apps/                    per-app patch series (apps/<name>/patches/), build-deps.list, build-in-chroot.sh
  docs/                    hardware/, porting-plan.md, specs/
  out/                     gitignored
```

- `build.sh` runs every stage inside the container; the host needs only Podman or Docker.
- Order: U-Boot and kernel cross-built from pinned tags with patches; ES and cores built in a throwaway armhf chroot;
  `mmdebstrap` armhf rootfs; image assembled.
- Patches are kept as `git format-patch` series; bumping a pin means rebasing the series.

## 2. Boot chain and SD layout

Boot flow:
1. The boot ROM loads `u-boot-sunxi-with-spl.bin` from 8 KiB (replaces vendor boot0 and lichee U-Boot).
2. SPL: DRAM 552 MHz, ZQ 15291, ODT on; AXP rails DCDC1 3.0 V, DLDO3 3.0 V; U-Boot's default serial output (UART0 on `PB0`/`PB1`) is unused, the console is USB (section "Testing").
   Based on `A33-OLinuXino_defconfig` (values proven over FEL, hardware notes "On-device tests").
3. U-Boot's distro boot (`distro_bootcmd`) finds `extlinux/extlinux.conf` on p1: zImage, GA36 DTB, `root=PARTUUID=...`.
4. No initramfs (MMC and ext4 built in). From v1.1 extlinux passes `init=${ga36_init}`: U-Boot sets it to the
   charge program on a plug-in power-on and to `/sbin/init` otherwise.
5. U-Boot runs on the upstream A33-OLinuXino device tree (it needs only MMC0 and the USB OTG gadget); the kernel gets the GA36
   DTB through extlinux. If card detect (`PB4`) does not match, the GA36 DTS joins the U-Boot patch set.
6. No saved U-Boot environment. Two U-Boot patches: `board_usb_init()` probes the MUSB gadget, so the ACM console
   works without USB Ethernet; `misc_init_r()` sets `ga36_init` from the AXP boot source (charge mode).

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
- Charging while off: v1.0 used U-Boot's `AXP_DISABLE_BOOT_ON_POWERON` to switch the board off again in the SPL
  when the power-on source was the charger. From v1.1 a plug-in power-on boots Linux with `init=` set to the
  charge program (`apps/ga36-charge.c`), which shows the battery icon and sleeps until a long press or an unplug.
  Nothing is written to the AXP.
- Power-off: mainline AXP driver.
- Development loop: `sunxi-fel uboot ... write <addr> zImage dtb` boots kernels from the PC with a USB console
  (U-Boot ACM on FEL boots without a script, kernel serial gadget `ttyGS0`); SD card images only for release
  testing.

## 3. Kernel

- Linux 6.18 LTS (6.18.56 on 2026-10-14). Config: `sunxi_defconfig` plus the `kernel/ga36.config` fragment via
  `merge_config.sh`: DRM sun4i, sun6i DSI, lima, NV3051D panel, pwm-backlight, gpio-keys, AXP20x regulators,
  battery, ADC and power key, sun8i codec, simple-audio-amplifier, exFAT, zram, cpufreq-dt, thermal, MUSB OTG with
  the USB serial gadget.
- Patch series:
  1. `ARM: dts: sun8i: a33: add GA36-MB V1.0`, from the hardware mapping table: `r_rsb` and AXP223 rails,
     `cpu-supply` DCDC3, DSI with the panel child (reset `PH7`, power `dc1sw`), PWM0 backlight node named
     `backlight`, gpio-keys-polled (the PE bank has no interrupts), MMC0 (card detect `PB4`), codec with the amplifier on `PH9`, USB OTG (ID `PH8`),
     no debug UART, UART1 enabled without a child.
  2. `drm/panel: nv3051d: make lane count and init sequence per-panel`. v6.18 hardcodes `dsi->lanes = 4` and
     shares `panel_nv3051d_init_sequence()`; existing panels keep 4 lanes and their sequence.
  3. `drm/panel: nv3051d: add GA36 panel`: 2 lanes, the table from `panel-init.txt`, 640x480 at 30 MHz,
     htotal 1040, vtotal 518 (~55.7 Hz).
  4. Three dt-bindings patches: GameConsole vendor prefix, panel compatible, board compatible.
  5. `ARM: dts: sun8i: a33: ga36: reserve a ramoops region`: pstore crash logs (did not survive the panic reset on V1.0); kept in this
     repository only, not sent upstream.
- Buttons: one `gpio-keys-polled` device (10 ms) with gamepad codes; FN on `PE1`.
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
  sleep and wake on the power key, four busy threads at 1.2 GHz with the temperature watched.

## 4. Userspace

- **Frontend:** ES fcamod branch 351v renders through SDL2 and links no libgo2, so no libgo2 or RGA patching is
  needed. It is built with `-DGLES=ON` (a GLES1 renderer), but Debian Mesa has no GLES1: the rootfs ships `libgl1`, so
  SDL kmsdrm creates a desktop "2.1 Mesa" compatibility context and the renderer runs on that. Patch series in
  `apps/emulationstation/patches/`: drop the stale libgo2 audio include, find the `axp20x-battery` supply by name,
  build the menu status line without shell calls, use the `Headphone` mixer for volume, keep the backlight at 20 % or
  more. The backlight path `/sys/class/backlight/backlight` already matches the DT node name.
- **Rootfs:** `mmdebstrap` trixie armhf minbase plus `rootfs/packages.list`: systemd, udev, Mesa (lima: EGL, GLES,
  GBM), ALSA, SDL2, exfatprogs, systemd-zram-generator, triggerhappy (only when the Vol keys are mapped, which they are
  on V1.0). No networking in v1.0 (no Wi-Fi). Serial getty on the USB gadget ACM port `ttyGS0`, which logs root in
  without a password (physical access only; there is no network). User `ga36` is logged in on tty1 by a systemd unit
  (`PAMName=login`) that starts ES and restarts it on exit.
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
  - a 60 s systemd timer powers off cleanly at 3 % while discharging (`axp20x_battery` sends no uevent on capacity
    changes, so a udev rule would never fire); the AXP also cuts power at 3.3 V;
  - triggerhappy: Vol+/Vol- (LRADC, kernel patch 0008) step the `Headphone` mixer, whose maximum 63 is the vendor
    cap; the digital controls stay at 0 dB and no user-facing control raises them (accepted risk); FN+Vol sets
    backlight brightness; there is no headphone/speaker toggle, since headphones mute the speaker in hardware;
  - RetroArch: FN+Start exits to ES.
- **Carried from the kernel bring-up** (hardware notes, "Mainline bring-up (V1.0)"):
  - the default ALSA state sets `AIF1 DA0` to 0 dB (it boots at 0, muted) and `AIF1 DA0 Stereo` to `Reverse Stereo`
    (the headphone channels are swapped otherwise); the vendor volume cap is `Headphone` 63 of 63;
  - the codec register reset at every stream stop did not reproduce on the V1.0 device (idle, `aplay`, `speaker-test`),
    so no kernel patch was made; the codec registers do reset over s2idle (`Headphone` back to 0, muted), and the
    `ga36-alsa` sleep hook restores them;
  - the USB gadget does not re-enumerate after s2idle resume until the cable is replugged;
  - Vol+/Vol- are mapped through the LRADC; backlight level 1 looks off, so the userspace minimum is level 2;
  - `CONFIG_RTC_INTF_SYSFS` is unset: RTC wake goes through `rtcwake` (the ioctl), not `wakealarm`; the RTC has no
    wakealarm, so only the power key and a cable replug wake the board;
  - known limitations: ES keeps the audio device open in its menu, which gives a faint hiss at idle; `es_input.cfg`
    is root-owned in `/etc/emulationstation`, so remapping inside ES cannot save on a release card; ROMS is
    mounted by `LABEL=ROMS`, so a partition relabelled on a PC stays unmounted;
  - game speed: the panel runs at 55.69 Hz and most cores at 50 or 60 Hz, outside RetroArch's default
    `audio_max_timing_skew` of 0.05, so RetroArch drops vsync and runs games at their own speed and pitch. A skew of
    0.10 keeps 60 Hz games vsync-locked, but about 7 % slow with the pitch lowered to match; that was the first
    choice and was lowered back to 0.05 because the music sounded too slow and no tearing was seen. Settled in
    v1.1: the panel mode runs at 60.04 Hz, so 60 Hz games stay vsync-locked at the default skew.
- **First boot:** create or restore p3 (section 5) and the per-system folders that `es_systems.cfg` points at.
- **Test on the device:** cold boot to ES (timed), each core at full speed on a test ROM, RAM use with ES and
  pcsx_rearmed running, hotkeys and the volume cap, suspend and resume in and out of a game, low-battery shutdown.

## 5. Image, release and CI

- `scripts/make-image.sh` works rootless, with no loop mounts: p1 via `mkfs.vfat -C` and `mcopy`; p2 via
  `mkfs.ext4 -d`; `sfdisk` writes the MBR; `dd` places p1 and p2 at their offsets and U-Boot at 8 KiB. It also
  makes the development card: the uncompressed, sparse `.img` stays in `out/image` next to the `.img.xz`; the
  layout lives in the script (no `image/` directory).
- Output: a sparse image compressed to `debianator-vX.Y.Z.img.xz`, plus `SHA256SUMS`.
- p2 is a fixed 3 GiB, so p3 always starts at the same offset. Reflashing drops the p3 MBR entry but not its data.
  The disk id is fixed at `0x47413336`. The first-boot unit `ga36-roms.service` probes that offset with `blkid`: if
  any filesystem is there it only restores the partition entry; it formats only when nothing is there. It then runs
  `fsck.exfat -p` before mounting, because the exfat driver keeps the dirty flag from an unclean power-off until a
  check clears it. On a card too small for p3 (under 4.58 GB: the image's 3.51 GB plus the 1 GiB minimum of
  `ga36-roms-part`) the mount fails, the unit continues, and the folders are made on the rootfs, which has about
  1.7 GiB available. Minimum card 4 GB, 8 GB or more recommended. The README still says to back up saves
  before upgrading.
- README install guide: back up the stock card; flash with balenaEtcher, Raspberry Pi Imager or `xzcat | dd` to a
  separate card; identify the GA36 revision by the board marking; return to stock.
- Versions: semver tags, `v1.0.0` for the v1.0 scope, `v1.1.0` for sticks and the charging animation.
  Release gate: the section 4 device checklist passes on V1.0; release notes name the tested revision and the items
  checked by a person.
- CI: one GitHub Actions workflow on tag push and manual dispatch. It runs `./build.sh all` in the same container
  and attaches the `.img.xz` and `SHA256SUMS` to the GitHub Release. On the runner, armhf binfmt comes from
  `docker/setup-qemu-action`; a manual dispatch uploads the image as a one-day artifact, a tag push creates a draft
  release that a person publishes after the release gate. The workflow runs every `tests/*.sh` after the build;
  device checks stay with the developer and gate releases, not pull requests. The repository is public; the owner is
  the only maintainer.
- Docs: README (users), `docs/porting-plan.md`, `docs/specs/`, `docs/hardware/`. No CHANGELOG; release notes live on
  GitHub Releases.

## Testing

Development setup: USB OTG only; the development board's UART pads are damaged.

| Unattended over FEL and the USB console | Needs a person at the device |
|---|---|
| build everything, FEL-boot kernels, read boot logs | power key presses (FEL entry, power-on, sleep/wake) |
| DRM/panel state (`modetest`, dmesg), not the pixels | confirm the picture (colours, orientation, flicker) |
| `evtest` capture | press each button and combo on request |
| ALSA state, `speaker-test` runs | listen: speaker, headphones, volume cap |
| battery/charger sysfs, thermal under load, RAM use | plug/unplug the charger; swap SD cards |
| boot time (dmesg timestamps), RetroArch FPS from logs | judge game smoothness and input feel |
| suspend/resume via `rtcwake` or `/sys/power/state` | wake from sleep with the power key |

- FEL only loads code; it shows nothing. The console is USB only: U-Boot's ACM console on FEL boots without a
  script, then the kernel's serial gadget `ttyGS0`. A panic resets the board into FEL; the ramoops region does not
  survive that reset on the V1.0 board (DRAM is not refreshed through it), so a crash before the gadget is up shows
  only on the panel's framebuffer console.
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
- README install guide: back up the stock card first, flash this firmware to a separate card, keep the stock card.
