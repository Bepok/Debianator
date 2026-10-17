# DOS design

Date: 2026-10-18. Status: design. Release: v1.1 ("DOS" in [`../porting-plan.md`](../porting-plan.md)).
Parent design: [`2026-10-14-firmware-design.md`](2026-10-14-firmware-design.md).

## Why

The owner wants PC games on the GA36, named by example: Doom. DOS games are what this hardware (4x Cortex-A7
1.2 GHz, 512 MiB, Mali-400) can run well; Windows games come later as a separate, experimental item. DOS is the
full-support part of "PC games" in v1.1.

## Behaviour (decided with the owner)

- A new **DOS** system in EmulationStation, launched like the existing ones.
- Full support, not experimental: listed in the README systems table like the console systems.
- Checked with the **shareware DOS Doom** package (`DOOM.EXE` plus `DOOM1.WAD`). A WAD on its own (as in the
  Steam/GOG re-releases) is not supported: no Doom source-port core.
- **No ScummVM.** Considered and dropped: its build is the most expensive part (about 1-2 h under qemu) and the
  owner does not care about the adventure games it is for. It can come in a later release.

Our calls, played back to the owner and not objected to:

- The core is **DOSBox Pure** (libretro), so hotkeys (FN+Start to ES, FN+X for the menu), the performance governor
  (`ga36-retroarch`) and input setup are the same as for every other system.
- Controls: the core's own gamepad-to-key mapping and its on-screen keyboard on L3 (already button 10).
  Mouse-driven DOS games need the analog sticks, a separate v1.1 item; until then they are not expected to be
  playable.

## Goals

- Shareware Doom, copied to the ROMS card from a PC as the README says, starts from ES and is playable with the pad
  (move, turn, fire, open doors, weapon change, menu).
- Games and saves live on the `ROMS` partition and survive a reflash.
- Existing systems and tests unchanged.

## Non-goals

- ScummVM, Windows games, a Doom source port.
- Mouse emulation from the D-pad (waits for the sticks).
- Any game data in the image: nothing copyrighted ships, including the shareware Doom files (the owner supplies
  them for the check).
- Per-game key maps beyond what DOSBox Pure provides on its own.

## Anti-goals

Even if the core runs, it is a failure if:

- a game can only be started by editing files on the console (copying it to the ROMS card from a PC, following the
  README, must be enough);
- the CI build no longer fits in a GitHub Actions job (6 h) or the existing cores' build breaks;
- an existing system's launch, speed or controls change.

## How it works

### Build

DOSBox Pure is built like the existing cores: pinned in `versions.env`, fetched by `scripts/fetch-apps.sh` through
`scripts/tree.sh`, copied into the throwaway armhf chroot by `scripts/build-apps.sh`, built in
`apps/build-in-chroot.sh`.

- Upstream moved to `https://codeberg.org/schelling/dosbox-pure` (the GitHub repository is a README only); pin a
  commit there.
- It does not fit the `core()` helper (its Makefile does not know `platform=classic_armv7_a7`), so it gets its own
  line.
- The Makefile picks CPU flags from `uname -m`, which under qemu reports `armv7l` and leads to
  `-mcpu=cortex-a72 -mfpu=neon-fp-armv8`: code that can crash on the A7. Override with
  `CPUFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"`. The ARMv7 dynarec is on by default.
- Output: `dosbox_pure_libretro.so`. Licence GPL-2.0-or-later, like the other cores.

### Runtime

- `es_systems.cfg` gains `pc` ("DOS"), path `/roms/pc`, through `ga36-retroarch` like the other systems, theme
  `pc` (the carbon theme has it). Extensions: those of the core's accepted types that make sense as ES entries,
  at least `.zip` and `.dosz`, both cases.
- `ga36-roms-dirs` creates `/roms/pc` from `es_systems.cfg` as it does today.
- The README says how to add a game: the recommended form (a `.zip` of the game folder, which DOSBox Pure mounts
  directly and runs or offers a start menu for), with shareware Doom as the example.

### Tests

- `tests/apps.sh`: the `.so` is built.
- `tests/rootfs.sh`: system count 10 → 11; the existing checks that every `es_systems` command goes through
  `ga36-retroarch` and names an installed core cover the new entry.
- `tests/roms-part.sh`: the folder list includes `pc`.

### Checks on the device

- Shareware Doom from a `.zip`: starts from ES, the first level is playable with the pad, FN+Start returns to ES.
- Measured speed (RetroArch's FPS display, and how it feels), recorded in the hardware notes whatever it is.
- The governor is `performance` while it runs (as for the other cores).
- A save made in Doom is still there after a reflash.

## Risks

- **Doom speed.** No Cortex-A7 measurement found; scaled from Pi 3 reports, about 12-18 fps is a guess. Full
  support here means it runs and is playable; the measured number goes in the README if it is low. 386 and
  early-486 games are expected to be fine.
- **Build time.** DOSBox Pure is guessed at 10-20 min under qemu-user, on top of today's 1 h 24 min CI run.

## Left to the builder

- The exact DOSBox Pure commit.
- The final extension list.
- Core option defaults (for example cycles or the default key mapping), if the device check calls for any.
- README wording and where DOS goes in the systems table.
