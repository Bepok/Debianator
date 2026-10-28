# Development

Building the image, the hardware notes and the development loop. For using the image, see the
[README](../README.md); for contributing, [CONTRIBUTING.md](../CONTRIBUTING.md). The roadmap is in
[`porting-plan.md`](porting-plan.md), the designs in [`specs/`](specs/) (start with
[`specs/2026-10-14-firmware-design.md`](specs/2026-10-14-firmware-design.md)), research in [`research/`](research/).

## Build and flash it yourself

Needs a Linux PC with Docker (Podman works for the `uboot`, `kernel` and `image` stages; `apps` and `rootfs` are
tested with Docker only), `qemu-user-binfmt` (`sudo apt install qemu-user-binfmt`), git, and about 15 GB free.

1. Get the sources:
   `git clone https://github.com/Bepok/Debianator.git && cd Debianator`
2. Build everything: `./build.sh all`. The apps build under emulation and take the longest: the v1.1.0 build took
   about 2.5 h on GitHub's runner.
3. Check the image: `./build.sh run tests/image.sh` should end with `PASS`. The image is
   `out/image/debianator-<version>.img`, next to its `.img.xz` and `SHA256SUMS`.
4. Insert the card into the PC, find it with `lsblk` (`sdX` below), and unmount its partitions:
   `for p in /dev/sdX?; do udisksctl unmount -b $p; done` ("not mounted" errors are fine).
5. Write it, then eject before removing the card:
   `sudo dd if=out/image/debianator-<version>.img of=/dev/sdX bs=4M conv=fsync status=progress`
   `sudo eject /dev/sdX`
6. Insert the card into the console and power on (hold the power key for more than 1 s). An existing `ROMS`
   partition is kept, as in [Install](../README.md#install).

After a change, rebuild only what changed, then the image: for example `./build.sh kernel && ./build.sh image`.
Stages: `uboot`, `kernel`, `apps`, `rootfs`, `image`.

## Hardware

Board revisions seen so far: V1.0-20250730, V1.1-20251025, V1.2-20260416. Development happens on V1.0, the only
supported revision; the others are untested and may behave unexpectedly. Hardware research is in
[`hardware/`](hardware/).

Trying a V1.1 or V1.2 board: keep the boot log from the USB console (no soldering: connect the console's USB OTG port
to a PC and open the serial port it shows, 115200 baud), and attach it to a device test report; UART only if the
board does not get that far.

## Development loop

Needs Docker (or Podman, see above); everything else runs in the build container.

- `./build.sh uboot|kernel|initramfs|apps|rootfs|image|all` builds into `out/`; `./build.sh run tests/<name>.sh`
  runs a check. `apps` and `rootfs` run as root in a privileged container and need Docker and `qemu-user-binfmt` on the
  host (`sudo apt install qemu-user-binfmt`); `apps` builds under emulation and takes a long time.
- Board work lives in `out/src/linux`, `out/src/u-boot` and the app trees (`scripts/fetch-apps.sh`) as git commits;
  `scripts/tree.sh export <tree>` turns them into its patch directory.
- `scripts/fel-boot.sh kernel` boots the board from the PC over USB (no card, power key) and
  `scripts/board-run.sh 'cmd'` runs commands on it over the USB console. Install `scripts/70-ga36-usb.rules` in
  `/etc/udev/rules.d/` first: it names the console `/dev/ga36-linux` and keeps ModemManager off it.
- **Shell on the device:** with the console's USB OTG port connected to a PC, `picocom -b 115200 /dev/ga36-linux`
  (or `/dev/ttyACM0` without the udev rule) opens a root shell, logged in without a password. It is there once Linux
  is up; the charge screen has none, and U-Boot has its own (`/dev/ga36-uboot`) only on FEL boots. Close it before
  running `scripts/board-run.sh`, which uses the same port.
- `./build.sh image` writes `out/image/debianator-<git describe>.img` (write it to a card with `dd`), its
  `.img.xz` and `SHA256SUMS`. Pushing a `vX.Y.Z` tag makes GitHub Actions build the same and attach it to a draft
  release, which is published by hand after the device checklist.
- **Tests:** CI runs every `tests/*.sh` after `./build.sh all`. **Nothing in CI touches a board: checking on the
  device (boot, picture, buttons, sound, sleep, charging) is the developer's job**, recorded in
  `docs/hardware/hardwareAnalysis.md`. It is expected before a release, not required to merge a pull request.
- Power on with a power key press longer than 1 s. Plugging in the cable or charger while off starts the charge
  screen: the battery icon, then a dark screen while it charges. A short press shows the icon again, a press held
  over 2 s boots into ES, and unplugging powers the board off within a minute.
