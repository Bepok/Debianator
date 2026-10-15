# r36s-a33-ga36-debian

Debian-based firmware for the **GA36-MB** R36S clone (Allwinner A33, 512 MiB RAM), the board sold as an "R36S"
whose stock system is a vendor EmuELEC on a Linux 3.4 kernel. No existing R36S custom firmware supports it; they
all target the Rockchip RK3326.

**Status: v1.0 scope implemented and tested on GA36 V1.0.** EmulationStation with RetroArch, buttons, sound,
battery level, sleep, power-off and charging while off work from an SD card image built with `./build.sh all`,
locally or by the project's GitHub Actions workflow. **The repository is private: for now, images, issues and
testing are for maintainers only.** See [`docs/porting-plan.md`](docs/porting-plan.md) for the roadmap and
[`docs/specs/2026-10-14-firmware-design.md`](docs/specs/2026-10-14-firmware-design.md) for the design.

## What it is

- Mainline Linux (6.18 LTS) and mainline U-Boot, with the board patches kept in this repository.
- Debian trixie armhf, EmulationStation (fcamod) and RetroArch.
- Runs from the SD card only; the stock card is not touched.
- Not yet: analog sticks and the charging animation (planned for v1.1).

## Install

1. **Keep the stock card.** Back it up first (for example `sudo dd if=/dev/sdX of=stock.img bs=4M status=progress`)
   and put it away; this firmware goes on a *separate* card.
   - **Card size:** 4 GB minimum, 8 GB or more recommended.
   - The image takes 3.51 GB.
   - The `ROMS` partition is made only when at least 1 GiB is left after it, which means cards from 4.58 GB.
   - On a 4 GB card, ROMs go to the system partition instead, which has about 1.7 GiB free.
2. Check the board revision: the marking on the board reads `GA36-MB V1.0-20250730`, `V1.1-20251025` or
   `V1.2-20260416`. Only V1.0 is tested.
3. Download `r36s-a33-ga36-debian-vX.Y.Z.img.xz` and `SHA256SUMS` from the release, then check them:
   `sha256sum -c SHA256SUMS`.
4. Flash the `.img.xz` with balenaEtcher or Raspberry Pi Imager (both take it as is), or on Linux:
   `xzcat r36s-a33-ga36-debian-vX.Y.Z.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`
   (check `sdX` with `lsblk` first: dd overwrites whatever it is given).
5. Insert the card and power on (hold the power key for more than 1 s). The first boot creates the `ROMS`
   partition on the rest of the card; put ROMs in its system folders (`/roms/<system>`) and BIOS files in
   `/roms/bios`.

- **Upgrading:** flashing a new release keeps the `ROMS` partition and its files, but back up `/roms/saves` (and
  anything else you care about on it) before you upgrade.
- **Back to stock:** power off and insert the stock card. Nothing on the console itself is changed.
- **V1.1 and V1.2 boards:** untested. A maintainer trying one should keep the boot log from the USB console (no
  soldering: connect the console's USB OTG port to a PC and open the serial port it shows, 115200 baud); UART
  only if the board does not get that far.

## Sources

Everything in an image comes from this repository at the release tag: the U-Boot, Linux and app patch series, the
configs, and the upstream versions pinned in [`versions.env`](versions.env). The Debian packages come from Debian
trixie; their sources are at <https://sources.debian.org/>.

## Hardware

Board revisions seen so far: V1.0-20250730, V1.1-20251025, V1.2-20260416. Development happens on V1.0; other
revisions are untested. Hardware research is in [`docs/hardware/`](docs/hardware/).

## Development

Needs Docker or Podman; everything else runs in the build container.

- `./build.sh uboot|kernel|initramfs|apps|rootfs|image|all` builds into `out/`; `./build.sh run tests/<name>.sh`
  runs a check. `apps` and `rootfs` run as root in a privileged container and need Docker and `qemu-user-binfmt` on the
  host (`sudo apt install qemu-user-binfmt`); `apps` builds under emulation and takes a long time.
- Board work lives in `out/src/linux`, `out/src/u-boot` and the app trees (`scripts/fetch-apps.sh`) as git commits;
  `scripts/tree.sh export <tree>` turns them into its patch directory.
- `scripts/fel-boot.sh kernel` boots the board from the PC over USB (no card, power key) and
  `scripts/board-run.sh 'cmd'` runs commands on it over the USB console. Install `scripts/70-ga36-usb.rules` in
  `/etc/udev/rules.d/` first: it names the console `/dev/ga36-linux` and keeps ModemManager off it.
- `./build.sh image` writes `out/image/r36s-a33-ga36-debian-<git describe>.img` (write it to a card with `dd`), its
  `.img.xz` and `SHA256SUMS`. Pushing a `vX.Y.Z` tag makes GitHub Actions build the same and attach it to a draft
  release, which is published by hand after the device checklist.
- **Tests:** CI runs every `tests/*.sh` after `./build.sh all`. **Nothing in CI touches a board: checking on the
  device (boot, picture, buttons, sound, sleep, charging) is the developer's job**, recorded in
  `docs/hardware/hardwareAnalysis.md`. It is expected before a release, not required to merge a pull request.
- Power on with a power key press longer than 1 s. Plugging in the cable or charger does not power the board on:
  the SPL switches it off again, so it charges while off.

## Licence

GPL-2.0, see [`LICENSE`](LICENSE).
