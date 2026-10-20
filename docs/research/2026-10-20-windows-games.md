# Windows games research

Date: 2026-10-20. Status: desk research only, nothing run on the device. For the "Windows games" row of
[`../porting-plan.md`](../porting-plan.md) (Box86 and i386 Wine with a per-game X server and gptokeyb, experimental).

## Summary

Box86 plus i386 Wine can start on this board, but only **2D Windows games** (GDI or DirectDraw without 3D, about
640x480) are a realistic target. 3D games are out: the Mali-400 is GLES 2.0 only, Wine's Direct3D needs desktop
OpenGL, and the box86 README itself says gl4es on its GLES2 backend "have issue with Wine". RAM (493 MB) and disk
(Wine is about 650 MB installed) are tight, and nobody has published a game running on a Cortex-A7 this way.

Recommendation: do not plan the sub-project yet. Either run a short on-device spike first (below), or move the row to
"Revisit later". Several of the 2D games people would want already have native armhf ports, which will run far
better than Wine.

## Findings

| Question | Answer | Source |
|---|---|---|
| Does Box86 run on a Cortex-A7? | Yes. CMake profile `RPI2` = `-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard`. A Pi 2 hit a dynarec SIGILL (`str r8, [r8, #-4]!`, UNPREDICTABLE on ARMv7) at Wine start; fixed upstream, after which `winecfg` starts | box86 `CMakeLists.txt`, `docs/COMPILE.md`; Raspberry Pi forum t=342001 |
| Is Box86 maintained? | Yes: commits on 2026-09-11, 2026-09-27, 2026-10-20; not archived. No releases on GitHub, so it would be pinned by commit like the cores | GitHub API |
| Kernel memory split | Wine needs 3G/1G. Our kernel has `CONFIG_VMSPLIT_3G=y` and `CONFIG_HIGHMEM=y`: no change | `out/build/linux/.config` |
| Which Wine | The i386 build, not `wine-armhf` (Box86 runs x86 Wine, with native armhf libraries wrapped). WineHQ publishes `wine-stable-i386` 11.0 for trixie, 663 MB installed (staging 11.20, 803 MB) | box86 `X86WINE.md`; WineHQ trixie `binary-i386/Packages.gz` |
| 3D (Direct3D, OpenGL) | Not viable. wined3d translates Direct3D to desktop OpenGL; gl4es maps OpenGL 2.1 onto GLES2 with "crude shader conversion, only simple shaders"; box86: "gl4es with ES2 backend have issue with Wine for now". Even where it worked, lima is the limit we already hit (GTA GPU-bound at 27 fps) | box86 README; gl4es README |
| 2D without OpenGL | Wine still has it: `HKCU\Software\Wine\Direct3D\renderer` = `gdi` (or `no3d`) disables 3D, so DirectDraw 2D runs through GDI with no GL at all. Some games misdraw under it | `dlls/wined3d/wined3d_main.c` (master); wine-bugs threads |
| Speed | Box86 is about half native speed on CPU-bound code (FOSDEM 2021 figures). Wine's own DLLs are x86 and run emulated too; only Linux libraries (X11, libc) are native. No game figures for any Cortex-A7. The Pi 2 user: usable "only for a low speed application", not games | Phoronix; Raspberry Pi forum t=342001 |
| Memory | No published minimum. The same app took about 696 MB on a Pi 4. Wine starts several processes (wineserver, services, explorer), each under Box86. With ES stopped we have about 400 MB; zram swap (256 MiB) helps a little | Raspberry Pi forum t=342001; hardware notes |
| Other A33 devices | Nothing found: no Box86 or Wine on the Miyoo A30 (spruceOS) or the SNES Classic | web search |

## What the sub-project would add

- Box86 cross-built (`RPI2` profile) in `scripts/build-cross.sh`, pinned in `versions.env`.
- Wine i386 (about 650 MB): on the rootfs it fits (about 1.7 GiB free) but grows the image and the CI run; on `ROMS`
  (exFAT) it needs a check for symlinks and exec permissions.
- An X server per game (Xorg with modesetting, no glamor needed for GDI), started by a launcher instead of
  `ga36-retroarch`, with ES stopped for memory.
- gptokeyb for pad to mouse and keys (uinput is already in the kernel config), with a default map.
- A Wine prefix per game or a shared one on `ROMS`, `renderer=gdi` set, an ES system and `.exe`/`.bat` launch.

## Native ports instead

Many 2D Windows games people would pick have native engines that build for armhf and need no Wine: Diablo
(devilutionX), Fallout 1 and 2 (fallout1-ce, fallout2-ce), Heroes of Might and Magic 2 and 3 (fheroes2, VCMI),
Warcraft 2 (Stratagus/Wargus), Transport Tycoon (OpenTTD). Most are already packaged for this class of handheld by
PortMaster. That route avoids every risk above, at the cost of being per game.

## Spike, if wanted (about half a day)

1. Cross-build Box86 with `-DRPI2=1`; unpack `wine-stable-i386` 11.0 on the card; add `xserver-xorg-core` and
   `xserver-xorg-video-modesetting` by hand.
2. With ES stopped: `winecfg` starts; then one 2D game the owner has (an 8-bit DirectDraw game at 640x480, such as
   StarCraft or Age of Empires).
3. Record: memory (`free`, RSS per process), CPU per thread, a felt or measured frame rate, start time.

Go if the game is playable (steady, sound intact) with at least about 50 MB available. Otherwise the row moves to
"Revisit later" with these numbers.

## Sources

- Box86: https://github.com/ptitSeb/box86 (README, `docs/COMPILE.md`, `CMakeLists.txt`); Wine under Box86:
  https://ptitseb.github.io/box86/X86WINE.html
- Pi 2 SIGILL and fix, memory note: https://forums.raspberrypi.com/viewtopic.php?t=342001
- Box86 speed: https://phoronix.com/news/Box86-x86-On-Other-Archs ; https://box86.org/2021/06/game-performances/
- gl4es: https://github.com/ptitSeb/gl4es
- Wine `renderer` key: `dlls/wined3d/wined3d_main.c` in https://gitlab.winehq.org/wine/wine ; DirectDraw on GDI:
  https://mail.winehq.org/mailman3/hyperkitty/list/wine-devel@winehq.org/thread/K6BLN43EMTIF7CCHNWGOZR6342UPKTKP
- WineHQ trixie i386 packages: https://dl.winehq.org/wine-builds/debian/dists/trixie/main/binary-i386/
- PortMaster: https://portmaster.games/
