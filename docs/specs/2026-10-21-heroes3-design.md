# Heroes 3 design

Date: 2026-10-21. Status: implemented, checked on V1.0 (hardware notes, "Heroes 3 (v1.1)"). Release: v1.1 ("Heroes 3" in [`../porting-plan.md`](../porting-plan.md)).
Parent design: [`2026-10-14-firmware-design.md`](2026-10-14-firmware-design.md).

## Why

The owner wants Heroes of Might and Magic III, which they own on GOG (Heroes 3 Complete, English). Running the
Windows game through Box86 and Wine is not realistic on this board
([`../research/2026-10-20-windows-games.md`](../research/2026-10-20-windows-games.md)); VCMI, an open
reimplementation of the engine that reads the original game data, is native armhf code and needs no emulation.

## Behaviour (decided with the owner)

- A new **Heroes 3** system in EmulationStation, started like the other systems.
- **VCMI 1.6.5 from Debian trixie** (`contrib`, armhf binary package), not built by us. The owner accepted its one
  gap against 1.7.3: no saved map zoom, so the map starts at the original zoom each session.
- The owner copies the game data from a PC to the ROMS card. Nothing of the game ships in the image.
- Controls: an analog stick moves the mouse pointer, buttons do everything else (clicks, shortcuts). Map zoom in
  and out on two buttons.
- UI at **80 %**, the most VCMI allows at 640x480 (its windows are a fixed 800x600; the limit is
  `getSupportedScalingRange` in `client/renderSDL/ScreenHandler.cpp`). Patching VCMI past that was considered and
  dropped: full-size windows (town, hero) would be cut off.
- Text: VCMI's scalable fonts (`fontsType` `scalable`) at `fontScalingFactor` 1.4. The owner judged this on the
  PC (VCMI 1.7.3, 640x480 window, their data) and accepted it.
  **Changed on 2026-10-21 (owner):** 1.25 was the PC check; on the device the owner asked for slightly larger text
  and accepted 1.4 after checking the dense screens.
- Slow AI turns are the owner's main worry after text: **a turn of up to about 3 minutes is acceptable**.
- **ES is stopped while Heroes 3 runs** and comes back when it exits, to leave VCMI the memory (owner, 2026-10-21:
  fix it in this plan, not as a follow-up). Only the Heroes 3 launch changes; the other systems still run with ES
  resident.
- If text on 1.6.5 turns out worse than the PC check (which ran 1.7.3), it ships anyway and is revisited later.

Our calls, played back to the owner and approved with the design:

- The system is named `heroes3`, folder `/roms/heroes3`, theme `ports` (the carbon theme has no Heroes 3 entry).
- One ES entry, "Heroes of Might and Magic III", backed by a marker file (below), so the data folders are not
  listed as games. Like the other systems, it only shows once the game is on the card: the marker is created only
  when `/roms/heroes3/Data` exists.
- `porting-plan.md` gets its own "Heroes 3" row (v1.1); the "Windows games" row stays as it is.
- FN+Start quits VCMI back to ES, as it leaves RetroArch for the other systems. Unsaved progress is lost, as it is
  there.

## Goals

- With `Data`, `Maps` and `Mp3` from the GOG install copied into `/roms/heroes3` from a PC, Heroes 3 starts from ES
  and a skirmish map is playable with the pad: pointer, left and right click, end turn, zoom, menus, a battle.
- Saves live on the `ROMS` partition and survive a reflash.
- Text at least as readable as in the owner's PC check (same settings, same pixel count).
- AI turn time measured on the device and recorded, with the map size and AI player count at which a turn stays
  within about 3 minutes.
- Existing systems and tests unchanged.

## Non-goals

- Building VCMI, or any version other than trixie's 1.6.5.
- A UI above 80 %, VCMI patches, VCMI mods (HD textures, extra towns), the Qt launcher (`vcmilauncher`).
- Online or hotseat multiplayer.
- Extracting the GOG installer on the device (`innoextract` is a PC step, in the README).
- Other native ports, Wine.

## Anti-goals

Even if VCMI runs, it is a failure if:

- starting the game needs editing files on the console (copying folders to the ROMS card from a PC must be enough);
- the settings above are not applied (another font type, size or scaling is in effect);
- ES does not come back after Heroes 3 exits, however it exits (menu, FN+Start, a crash);
- an existing system's launch, speed or controls change;
- the image no longer builds in one GitHub Actions job.

## How it works

### Package

- `scripts/build-rootfs.sh`: `mmdebstrap` gains `--components=main,contrib` (today it uses the default, `main`).
- `rootfs/packages.list`: `vcmi`. Its hard dependencies include Qt 5 (for `vcmilauncher`), Boost, TBB, ffmpeg
  libraries and SDL2 with image, mixer and ttf. Recommends (`ffmpeg`, `innoextract`, `unshield`, `unzip`) are not
  needed; check they are not installed.
- Licence GPL-2.0-or-later. It is in `contrib` only because it needs non-free game data.

### Data and saves

- The owner's copy goes to `/roms/heroes3/{Data,Maps,Mp3}`. `Data/VIDEO.VID` (629 MB of cutscenes) is optional and
  can be left out to save space; the README says so.
- VCMI looks for game data and writes saves under `$XDG_DATA_HOME/vcmi` (default `~/.local/share/vcmi`). That path
  points at `/roms/heroes3`, so data and `Saves/` both live on the card. The mechanism (a symlink in `skel`, or
  `XDG_DATA_HOME` set by the launcher) is the builder's call; mind that `/roms` is exFAT (no symlinks on it, case
  insensitive).
- `~/.config/vcmi/settings.json` ships in `rootfs/overlay/etc/skel` with:
  `video.fontsType` `scalable`, `video.fontScalingFactor` 1.4, `video.fullscreen` true,
  `video.resolution` 640x480 with `scaling` 0, `input.enableController` true, and the intro videos skipped.
  VCMI rewrites this file and drops values equal to its defaults; that is fine. The button map ships the same way,
  as a partial `~/.config/vcmi/shortcutsConfig.json`, which 1.6.5 reads.

### Launch

- `es_systems.cfg` gains `heroes3` ("Heroes of Might and Magic III"), path `/roms/heroes3`, extension `.vcmi`, theme
  `ports`.
- `ga36-roms-dirs` already creates `/roms/heroes3` from `es_systems.cfg`; at boot it also creates the empty marker
  `Heroes of Might and Magic III.vcmi` there when `Data/` exists and the marker is missing. Data copied in while the
  console runs shows up after the next boot.
- ES cannot stop itself from a child it launched, so the game runs as its own service. The ES command,
  `ga36-vcmi`, only starts `ga36-vcmi.service` and returns. That unit has `Conflicts=emulationstation.service`
  (starting it stops ES), runs as `ga36` on tty1 like ES (`PAMName=login`, `TTYPath=/dev/tty1`), and starts
  `emulationstation.service` again when it stops, however `vcmiclient` ended. Letting `ga36` start the unit needs
  a narrow sudo rule (as for `shutdown`) or a polkit rule; the builder picks.
- The unit sets the performance governor while the game runs and schedutil after, as `ga36-retroarch` does, and
  runs `vcmiclient` (the `%ROM%` marker is not passed on). SDL must use KMS/DRM and GLES 2 (the `opengles2`
  render driver, which lima supports).
- FN+Start: a `triggerhappy` rule that ends `vcmiclient`; it does nothing while RetroArch runs.

### Controls

- VCMI's own SDL game controller support. SDL has to recognise the `ga36-gamepad` device as a game controller; if
  its database does not, the launcher sets `SDL_GAMECONTROLLERCONFIG` from the device GUID (as in `es_input.cfg`).
- Pointer on the left stick, left and right click and end turn on face buttons, zoom in and out (VCMI's
  `adventureZoomIn` and `adventureZoomOut`) on two buttons. VCMI's default pad map uses every button and has no
  zoom, so two default bindings give way. The exact map is the builder's, set from what VCMI 1.6.5
  allows and checked on the device.

### Tests

- `tests/rootfs.sh`: system count 13 → 14; `ga36-vcmi.service` conflicts with `emulationstation.service` and
  restarts it on stop; the sudo or polkit rule allows only that unit; the check that every `es_systems` command goes through `ga36-retroarch`
  also accepts `ga36-vcmi`; `vcmiclient` is installed; the `skel` settings file is valid JSON with the values above;
  `ffmpeg`, `innoextract` are not installed.
- `tests/roms-part.sh`: the folder list includes `heroes3`; no marker without `Data/`; with `Data/` the marker is
  created once and not overwritten.

### Checks on the device

- Text on 1.6.5 compared with the PC check (1.7.3), recorded either way; worse is a later revisit, not a stop.
- Starts from ES with the owner's data; a skirmish is playable with the pad (pointer, clicks, zoom, a battle);
  FN+Start returns to ES.
- AI turn time, measured with a stopwatch from "end turn" to control returning: a small map with one and with three
  AI players, a medium map with three. Recorded in the hardware notes, whatever it is.
- Memory: `free` and RSS of `vcmiclient` and `vcmiserver` during an AI turn, with ES stopped.
- ES comes back after quitting from the menu, after FN+Start, and after `kill -9` of `vcmiclient`.
- The governor is `performance` while VCMI runs and `schedutil` after.
- A save made in the game is still there after a reflash.

## Risks

- **AI speed.** VCMI's Nullkiller AI is CPU-heavy; no Cortex-A7 figures found. If small maps exceed 3 minutes, the
  README says so and recommends the largest size that stays within it; the system still ships.
- **Memory.** Not measured: VCMI 1.7.3's `--headless` mode exited without playing on the PC. 493 MB with zram
  swap (256 MiB); stopping ES frees what it holds. If VCMI still runs out, the measurement goes in the hardware
  notes and the README limits map size, as for AI speed.
- **Controller recognition and button labels.** VCMI 1.6.5 maps buttons by SDL's game controller layout; a wrong or
  missing mapping makes clicks land on the wrong buttons.
- **Rootfs size.** Qt 5 and the ffmpeg libraries add an estimated 100-150 MB; about 1.7 GiB is free today.

## Left to the builder

- How `~/.local/share/vcmi` reaches `/roms/heroes3`.
- The sudo or polkit rule, and whether `ga36-vcmi` is a script or the unit start is the ES command itself.
- The button map, and the `SDL_GAMECONTROLLERCONFIG` string if needed.
- The exact `settings.json` keys for VCMI 1.6.5 (for example the render driver and intro skip), checked against its
  schema.
- README wording: the PC steps (`innoextract` on the GOG installer, which three folders to copy) and where Heroes 3
  goes in the systems table.
