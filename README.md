# r36s-a33-ga36-debian

Debian-based firmware for the **GA36-MB** R36S clone (Allwinner A33, 512 MiB RAM), the board sold as an "R36S"
whose stock system is a vendor EmuELEC on a Linux 3.4 kernel. No existing R36S custom firmware supports it; they
all target the Rockchip RK3326.

**Status: boot and kernel bring-up.** Mainline U-Boot and Linux boot on GA36 V1.0 over USB and from a test card; no
installable image yet. See [`docs/porting-plan.md`](docs/porting-plan.md) for the roadmap and
[`docs/specs/2026-10-14-firmware-design.md`](docs/specs/2026-10-14-firmware-design.md) for the design.

## What it will be

- Mainline Linux (6.18 LTS) and mainline U-Boot, with the board patches kept in this repository.
- Debian trixie armhf, EmulationStation (fcamod) and RetroArch.
- Runs from the SD card only; the stock card is not touched.

## Hardware

Board revisions seen so far: V1.0-20250730, V1.1-20251025, V1.2-20260416. Development happens on V1.0; other
revisions are untested. Hardware research is in [`docs/hardware/`](docs/hardware/).

## Development

Needs Docker or Podman; everything else runs in the build container.

- `./build.sh uboot|kernel|initramfs|sdcard` builds into `out/`; `./build.sh run tests/<name>.sh` runs a check.
- Board work lives in `out/src/linux` and `out/src/u-boot` as git commits; `scripts/tree.sh export linux` turns them
  into `kernel/patches/`.
- `scripts/fel-boot.sh kernel` boots the board from the PC over USB (no card, power key) and
  `scripts/board-run.sh 'cmd'` runs commands on it over the USB console. Install `scripts/70-ga36-usb.rules` in
  `/etc/udev/rules.d/` first: it names the console `/dev/ga36-linux` and keeps ModemManager off it.
- Power on with a power key press longer than 1 s. Plugging in the cable or charger does not power the board on:
  the SPL switches it off again, so it charges while off.

## Licence

GPL-2.0, see [`LICENSE`](LICENSE).
