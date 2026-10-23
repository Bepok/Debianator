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

## Supported now

Tested on board revision V1.0 only.

| System | ROM folder | File types | Core |
|---|---|---|---|
| NES | `nes` | `.nes` `.zip` | Nestopia |
| Game Boy, Game Boy Color | `gb`, `gbc` | `.gb`, `.gbc`, `.zip` | Gambatte |
| Game Boy Advance | `gba` | `.gba` `.zip` | gpSP |
| Super Nintendo | `snes` | `.smc` `.sfc` `.zip` | Snes9x 2010 |
| Mega Drive | `megadrive` | `.md` `.gen` `.smd` `.bin` `.zip` | PicoDrive |
| Master System, Game Gear | `mastersystem`, `gamegear` | `.sms`, `.gg`, `.zip` | PicoDrive |
| PC Engine | `pcengine` | `.pce` `.zip` | Beetle PCE Fast |
| PlayStation | `psx` | `.cue` `.chd` `.pbp` `.m3u` | PCSX ReARMed |
| DOS | `pc` | `.zip` `.dosz` `.exe` `.com` `.bat` `.conf` | DOSBox Pure |
| Nintendo 64 (experimental) | `n64` | `.n64` `.z64` `.v64` `.zip` | ParaLLEl N64 |
| PSP (experimental) | `psp` | `.iso` `.cso` `.pbp` `.chd` | PPSSPP |
| Heroes of Might and Magic III | `heroes3` | the GOG data folders | VCMI |

- **Works:** D-pad, face and shoulder buttons, Start and Select; both analog sticks in games that use a stick, and
  the left stick in the ES and RetroArch menus (on PlayStation the pad is a DualShock: some games switch it to
  analog themselves, otherwise L1+R1+Select does); speaker and headphones; volume keys; FN+Vol for
  brightness; FN+Start back to ES, FN+X for the RetroArch menu; battery level; power key short press to sleep and
  wake, held over 2 s to power off; charge screen with the battery level when the charger is plugged in while
  off; saves in `saves` on the `ROMS` partition.
- **Not yet:** Wi-Fi and networking; arcade and Nintendo DS.
- **Known limitations:** screen tearing is possible in 50 Hz (PAL) games, which run without vsync lock; button
  remapping in ES is not saved; a faint hiss while the ES menu is open; DOS games run at the speed of a 486
  (Doom about 19 fps), limited by the CPU.

**Adding a DOS game:** zip the game's folder and put the `.zip` in `pc`. On the first launch DOSBox Pure lists the
programs in the zip: pick the game's (`DOOM.EXE`); Left or Right on it sets it to start straight away next time. A
game that comes as an installer (the official shareware Doom, `doom19s.zip`) runs `INSTALL.BAT` from that list; the
installed files go into its save in `saves/DOSBox-pure`, and the next launch lists the installed `DOOM.EXE`. L3
opens DOSBox Pure's menu: on-screen keyboard and controller mapper (Doom gets a stick map by itself; other games can
take a preset such as "Mouse w/ Right Analog"). Doom runs at about 19 fps, like a 486DX2-66 PC of its time.

**Heroes 3:** runs on VCMI with the data from your own copy (Complete or Shadow of Death). On a PC, extract the GOG
offline installer with `innoextract`, then copy its `Data`, `Maps` and `Mp3` folders into `heroes3` on the `ROMS`
partition; `Data/VIDEO.VID` (629 MB of cutscenes) can be left out, the game then skips them. The ES entry appears
after the next boot. Controls: the left stick moves the pointer and the right stick scrolls the map, X and Y are left
and right click, A and B accept and cancel, D-pad right and left zoom in and out, Select ends the turn; FN+Start or
the in-game Quit goes back to ES. Saves are in `heroes3/Saves` and survive a reflash. AI turns are the slow part:
on an extra-large map in the third month, a round of 4 AI players took 30 to 50 s, and up to 2 minutes when they
fought a large battle; pick a smaller map or fewer AI players for shorter waits.

**N64 and PSP (experimental):** this chip is at the bottom of what these systems need. Measured: Mario Kart 64 about
48 fps of 60 and Super Smash Bros. about 35, both with crackling audio; on PSP, Castlevania: The Dracula X Chronicles
at full speed and Grand Theft Auto: Vice City Stories at about 27 fps, with choppy sound. N64 controls: left stick is the N64 stick, right stick the C-buttons, L2 is Z (R2 held with the face buttons
also gives the C-buttons). N64 draws at 320x240. PSP runs without frame skip, so a game too heavy for the chip slows
down, music included; for such a game, Frameskip 1 saved as a game option (below) brings the sound back to speed (GTA
plays much better with it). Per-game settings: FN+X → Core Options, then Manage Core Options → Save Game Options; a
reflash resets them.

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
   (check `sdX` with `lsblk` first: dd overwrites whatever it is given). Unmount the card's partitions before
   writing and eject the card (`sudo eject /dev/sdX`) before removing it: a card written while mounted can end up
   unbootable.
5. Insert the card and power on (hold the power key for more than 1 s). The first boot creates the `ROMS`
   partition on the rest of the card; put ROMs in its system folders (`/roms/<system>`) and BIOS files in
   `/roms/bios`.

- **Upgrading:** writing a new release with `xzcat ... | sudo dd` keeps the `ROMS` partition and its files.
  Raspberry Pi Imager erases the whole card first, so ROMs and saves are lost. Other flashers may do the same.
  Whichever you use, copy everything off `ROMS` (at least the `saves` folder) before you upgrade.
- **Back to stock:** power off and insert the stock card. Nothing on the console itself is changed.
- **V1.1 and V1.2 boards:** untested. A maintainer trying one should keep the boot log from the USB console (no
  soldering: connect the console's USB OTG port to a PC and open the serial port it shows, 115200 baud); UART
  only if the board does not get that far.

## Build and flash it yourself

Needs a Linux PC with Docker, `qemu-user-binfmt` (`sudo apt install qemu-user-binfmt`), git, and about 15 GB free.

1. Get the sources (the repository is private for now, so this needs maintainer access):
   `git clone git@github.com:Bepok/r36s-a33-ga36-debian.git && cd r36s-a33-ga36-debian`
2. Build everything: `./build.sh all`. The apps build under emulation and take the longest: the whole build took
   1 h 17 min on GitHub's runner.
3. Check the image: `./build.sh run tests/image.sh` should end with `PASS`. The image is
   `out/image/r36s-a33-ga36-debian-<version>.img`, next to its `.img.xz` and `SHA256SUMS`.
4. Insert the card into the PC, find it with `lsblk` (`sdX` below), and unmount its partitions:
   `for p in /dev/sdX?; do udisksctl unmount -b $p; done` ("not mounted" errors are fine).
5. Write it, then eject before removing the card:
   `sudo dd if=out/image/r36s-a33-ga36-debian-<version>.img of=/dev/sdX bs=4M conv=fsync status=progress`
   `sudo eject /dev/sdX`
6. Insert the card into the console and power on (hold the power key for more than 1 s). An existing `ROMS`
   partition is kept, as in Install.

After a change, rebuild only what changed, then the image: for example `./build.sh kernel && ./build.sh image`.
Stages: `uboot`, `kernel`, `apps`, `rootfs`, `image`.

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
- Power on with a power key press longer than 1 s. Plugging in the cable or charger while off starts the charge
  screen: the battery icon, then a dark screen while it charges. A short press shows the icon again, a press held
  over 2 s boots into ES, and unplugging powers the board off within a minute.

## Licence

GPL-2.0, see [`LICENSE`](LICENSE).
