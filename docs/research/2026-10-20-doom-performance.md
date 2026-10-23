# Doom performance research

Date: 2026-10-20. Status: research, nothing implemented or measured yet. Answers the "Open question: can games run
faster?" note in [`../porting-plan.md`](../porting-plan.md).
Context: [`../specs/2026-10-18-dos-design.md`](../specs/2026-10-18-dos-design.md), hardware notes "DOS (v1.1)" in
[`../hardware/hardwareAnalysis.md`](../hardware/hardwareAnalysis.md).

## Summary

Shareware DOS Doom in DOSBox Pure runs `demo3` at 19.4 fps (2134 gametics in 3844 realtics), about a 486DX2-66.
Doom's game logic runs at 35 Hz, so 35 fps is the ceiling; reaching it needs +80 % throughput. The emulation thread
holds one Cortex-A7 at 100 %, and DOSBox Pure's automatic cycles fill whatever time that thread has. Only work
removed from that one thread, or a faster core clock, can raise the number. Nothing the image can change in services,
the kernel or the RetroArch frontend comes close.

Ranked by gain for the risk:

1. **A native Doom engine (libretro PrBoom) next to DOS Doom.** Expected to reach the 35 fps cap with most of a core
   idle (estimate, the only lever that gets there). Cost: one more core and ES system. It reverses a non-goal of the
   DOS design ("a Doom source port"), so it needs the owner's decision.
2. **In-game Doom settings** (detail, screen size, sound). Zero image cost, a README tip. Each step is worth roughly
   +10-40 % (estimates, partly measured on a real 486).
3. **FastDoom** (an optimised DOS Doom executable the user drops into the game zip). Zero image cost. +15-30 %
   expected in DOSBox (estimate from +44 % on a real 486).
4. **`dosbox_pure_audiorate` 22050** in a shipped core options file. +1-4 % (estimate). Measure first.

Everything else is rejected: the 1.344 GHz CPU point needs 1.46 V that no known A33 board supplies (+10-12 % at
best), DRAM above 552 MHz risks silent corruption for 0-5 %, and the frontend items in the porting-plan note
(threaded video, the nearest resampler) cannot help this core because its frontend work already runs in parallel on
another core.

The porting-plan note was wrong in two places (since corrected): the 1.344 GHz point needs 1.46 V, not about 1.4 V
(`sys_config.fex` `LV2_volt = 1460`), and threaded video is not the first candidate (see "RetroArch threaded video").

## Open decisions

To be taken by the owner, in this order:

1. **Throttling baseline.** Run the "Thermal throttling check" before anything else; every other number is compared
   against it.
2. **PrBoom.** Lift the DOS design's "a Doom source port" non-goal and add libretro PrBoom as its own ES system, or
   keep Doom DOS-only. Needs one on-device fps check (see "Native engine: libretro PrBoom", "Measure").
3. **README tips.** After timing them on `demo3`: whether to document in-game Doom settings and FastDoom.
4. **Audio rate.** After timing it: whether to ship `dosbox_pure_audiorate` 22050 in a core options file, or drop it.

## All pointers

| Pointer | Verdict | Expected gain on demo3 | Risk | Source |
| --- | --- | --- | --- | --- |
| Native engine: libretro PrBoom | ACCEPT, owner decision | 35 fps cap, core mostly idle (estimate) | low; reverses a DOS non-goal | libretro-prboom Makefile, docs.libretro.com/library/prboom |
| Standalone Debian engine (chocolate-doom, crispy-doom, dsda-doom) | REJECT | same as PrBoom | loses hotkeys, governor wrapper, pad setup | packages.debian.org (trixie) |
| In-game detail, screen size, sound | MEASURE FIRST (README tip) | +10-40 % per step (estimate) | none; picture or sound quality | fabiensanglard.net/2168/doom |
| FastDoom executable | MEASURE FIRST (README tip) | +15-30 % (estimate) | pad auto map may not detect it | github.com/viti95/FastDoom, fabiensanglard.net/fastdoom |
| `dosbox_pure_audiorate` 22050 | MEASURE FIRST | +1-4 % (estimate) | duller OPL music | DOSBox Pure source |
| `dosbox_pure_force60fps` 35 | REJECT | about +1 % | uneven pacing, up to about 28 ms more latency | DOSBox Pure source |
| CPU 1.344 GHz at 1.46 V | REJECT | +10-12 % at most | instability, heat on the busy core | `sys_config.fex`, LKML 2016 |
| DRAM above 552 MHz | REJECT | 0-5 % | silent corruption | Pine64 forum (A64) |
| RetroArch threaded video | REJECT | about 0 % | one frame of input lag | DOSBox Pure source |
| RetroArch nearest resampler | REJECT | about 0 % | worse audio | DOSBox Pure source |
| Compiler: -O3, -ffast-math, LTO | REJECT | 0-3 % (guess) | dynrec miscompile history | DOSBox Pure Makefile |
| Core options: cycles, CPU core, CPU type, machine | REJECT | 0 % | inflated benchmark | DOSBox Pure source |
| Other DOSBox cores (dosbox-core, dosbox-svn) | REJECT | unknown, same dynrec lineage | a second DOS path | forum anecdotes only |
| Other firmware or OS | REJECT | 0 %; none supports the A33 | - | ROCKNIX, ArkOS, Knulli, MuOS |
| Stop ES, services, timers | REJECT | 0 % | launcher redesign | our rootfs |
| CPU isolation, affinity, priority | REJECT | 0-1 % | FIFO can starve the main thread | our rootfs |
| Kernel config, `mitigations=off`, `nohz_full` | REJECT | 0-0.1 % | - | our kernel config |
| LPAE with transparent huge pages | REJECT | unknown, 0-5 % (guess) | large kernel change, cannot be measured today | - |
| Thermal throttling check at 1.2 GHz | MEASURE FIRST | 0 % or recovers up to 16 % | none | hardware notes |

## How the speed is set

The facts every verdict below rests on, read from DOSBox Pure at the pinned commit `cdaea10`
(`dosbox_pure_libretro.cpp`):

- **Two threads.** `retro_run` on RetroArch's main thread waits for the emulation thread to finish a frame
  (`TCM_FINISH_FRAME`), copies the mixed audio (`MIXER_CallBack`, :3655, the only serialised step, microseconds),
  starts the next emulated frame (`TCM_NEXT_FRAME`, :3664), and only then submits audio and video to RetroArch. Texture
  upload to lima, resampling, the ALSA write and the page flip all run on another core while the next frame
  emulates.
- **Automatic cycles fill the thread.** In protected mode (Doom runs under DOS/4GW) the default `auto` cycles
  adjust `CPU_CycleMax` so the emulation thread is busy for 99.25 % of each frame (`dbp_auto_target`, :2426; the
  adjust loop :1716-1793). Time spent waiting for the frontend is subtracted. So any other work on that thread (VGA
  line rendering, OPL and Sound Blaster emulation, the mixer at the audio rate) comes straight out of the x86 budget,
  and `max` or a higher fixed cycles value cannot add speed.
- **The dynrec is the cost.** The ARMv7 backend is DOSBox's generic dynrec: every guest memory access is a C call
  with a TLB lookup (`core_dynrec/decoder_basic.h`). Doom's column and span drawers (about two loads and one store
  per pixel) are its worst case. At 1.2 GHz and about 27 million guest cycle units per second, that is roughly 40-45
  host cycles per guest cycle unit (estimate).
- **Pacing is unexplained.** RetroArch's FPS overlay is the wall-clock rate of frames from the core
  (`gfx/video_driver.c`), and it read 70 on the 60.04 Hz panel with vsync on. So `retro_run` ran 70 times a second
  and vsync did not hold it at 60. Why (a failing page flip, or a refresh rate other than 60.04 reported to
  RetroArch) is not known from source. It does not change throughput, since the cycles controller fills the
  thread at any cadence, but it may explain part of "it feels choppy". See "Measurement method".

## Measurement method

Every lever is timed the same way, three runs per variant, mean and spread recorded:

- `doom -timedemo demo3` with `DEFAULT.CFG` detail and screen size stated (timedemo uses them).
- **Wall clock as well as realtics.** Doom's realtics come from the emulated timer. If emulated time ran slower
  than real time (cycles above host capacity, or the frontend calling the core less often), timedemo would report
  an inflated fps. 3844 realtics must take 3844 / 35 = 109.8 s on a stopwatch or between log timestamps.
- `dosbox_pure_perfstats` = `detailed`: "Speed" must read about 100 %; "Cycles" is the direct throughput number;
  the decoder name proves the dynrec is in use; "Actual" and "Drawn" fps show the pacing.
- `top -H`: the emulation thread's CPU share.
- Once per configuration, a 10-minute loop logging `scaling_cur_freq` and `thermal_zone*/temp` every second. Today's
  19.4 fps has not been checked for throttling: the 4-thread test reached the 75 C trip at 1.2 GHz after 60 s and
  stepped down to 1008 MHz (hardware notes, "Thermal at 1200 MHz"). If Doom throttles too, that alone costs up to
  16 %.
- For a time split of the emulation thread: `perf record -e cpu-clock -t <tid>` (software events only, the A33
  device tree has no Cortex-A7 PMU node). Needs `linux-perf` copied in and the core built with `BUILD=RELEASEDBG`.
  Dynrec code shows as anonymous memory; that bucket is the x86 time.

## Native engine: libretro PrBoom

**Verdict: ACCEPT, if the owner lifts the non-goal.** Expected: the 35 fps cap with most of one core idle
(estimate).

Mechanism. The x86 emulation layer goes away entirely: Doom's C code runs as ARM code. DOSBox spends about 40-45
host cycles per guest cycle unit; native code for the same renderer needs a few cycles per x86-equivalent
instruction, so the same work costs an order of magnitude less (estimate). A second check: vanilla Doom runs about
55 fps on a Pentium 100, an in-order dual-issue CPU like the A7, which here has 12 times the clock.

Evidence. No measured Cortex-A7 frame rate for any Doom source port was found (Pi 2, Miyoo Mini, Orange Pi H3 and
RK3326 searched). Qualitative: PrBoom-Plus runs "at full speed at the lowest settings" on a Pi Zero (ARM11 at
1 GHz, slower than one A7) (forums.raspberrypi.com/viewtopic.php?t=293761). Every RK3326 handheld firmware ships
lr-prboom. The gain over 19.4 fps is not in doubt by order of magnitude; the exact headroom is an estimate until a
one-minute device run.

Cost.

- Build: `libretro/libretro-prboom` has a `classic_armv7_a7` platform block, so it fits the `core()` helper in
  `apps/build-in-chroot.sh` as one line, plus a pin in `versions.env`. `prboom.wad` is built into the core; nothing
  goes into `/roms/bios`. Small C code base, minutes under qemu (estimate).
- Runtime: a new ES system (for example `doom`, `/roms/doom`, `.wad`) through `ga36-retroarch`, so hotkeys, the
  governor and pad setup are shared with every other core. Tests: system count and the ROMS folder list.
- Side benefit: WAD-only Doom (Steam, GOG, `DOOM1.WAD` from the shareware zip, Freedoom) becomes playable.
- It reverses "Non-goals: a Doom source port" in the DOS design. DOS Doom in DOSBox Pure stays as it is.

Measure. Whether lr-prboom accepts `-timedemo` from the libretro side is unknown. Fallback: RetroArch's FPS overlay
in a fixed busy spot of E1M1, plus `top -H` for the core thread's share. Demo sync (complevel chosen from the IWAD)
is from documentation, not checked.

## Standalone Debian engine

**Verdict: REJECT, fallback only if lr-prboom fails to build.** Same gain as PrBoom.

Debian trixie armhf ships `chocolate-doom` 3.1.0, `crispy-doom` 7.0, `dsda-doom` 0.29 (`prboom-plus` is now a
transitional package for it), all on SDL2 2.32 with the KMSDRM backend (packages.debian.org). No build is needed,
but each one loses the `ga36-retroarch` path: FN hotkeys, the performance governor and the pad setup would have to
be rebuilt for SDL. More glue for the same result.

## In-game Doom settings

**Verdict: MEASURE FIRST, then a README tip.** No image change. Expected: +10-40 % per step (estimate).

Mechanism. Doom's renderer cost scales with pixels drawn. Low detail halves the width the column and span drawers
write; a smaller view (screen size 10 to 8) draws about 64 % of the area. Sound off removes Doom's own DMX mixing
(x86 work) and DOSBox's Sound Blaster and OPL work driven by it.

Evidence. On a real 486DX2-66 with `demo3`: screen size 10 to 9, and sound off, each gave a measured step of about
+15 % (25, 29, 33 fps; fabiensanglard.net/2168/doom). FastDoom's README table: Doom 1.9 at 19.56 fps with audio,
21.68 without (+10 %). The low-detail gain (+33-43 %) is derived from an assumed 50-60 % renderer share, not
measured.

Cost. Picture or sound quality, the user's choice. `DEFAULT.CFG` lives in the user's own game zip; the image cannot
ship it.

Measure. `demo3` with each setting changed alone, through `SETUP.EXE` (whether DOS Doom 1.9 accepts `-nosound`,
`-nosfx`, `-nomusic` on the command line was not confirmed). The sound-off run is also the upper bound for every
audio lever below.

## FastDoom

**Verdict: MEASURE FIRST, then a README tip.** No image change. Expected: +15-30 % in DOSBox (estimate).

Mechanism. FastDoom (GPL-2.0, github.com/viti95/FastDoom) is DOS Doom with fewer instructions and fewer VGA writes
per frame. Fewer guest instructions transfer to DOSBox directly; fewer VGA writes transfer too, since each one is a
page-handler call in DOSBox. Its tuning for the 486 L1 cache, 386-vs-486 instruction scheduling and ISA bus timing
does not transfer.

Evidence. Real 486DX2-66, `demo3`, screen 10, sound on: vanilla 25 fps, FastDoom 36 fps (+44 %), with the same
gametic count, so the demo plays in sync (fabiensanglard.net/2168/doom). The FastDoom README lists further opt-in
steps (flat visplanes +32 %, with no audio and Saturn transparency +49 % over vanilla). It runs in DOSBox
(vogons.org/viewtopic.php?p=1241792; a VESA crash with more than 8 MB VRAM was fixed in 0.9.9b), uses DOS/32A
instead of DOS/4GW, and supports `DOOM1.WAD`. No DOSBox frame rate was found; the +15-30 % assumes half to two
thirds of the real-486 gain survives.

Cost. The user adds `FDOOM.EXE` to the game zip. DOSBox Pure applies its Doom pad map by detecting the game; it may
not detect FastDoom, which would leave the user to pick a preset in the mapper (not checked). Try both the mode 13h
build (`FDOOM13H`) and the default Mode Y build: chained 13h writes are likely cheaper in DOSBox (estimate).

Measure. `FDOOM -timedemo demo3` against `DOOM -timedemo demo3`, same settings, wall clock checked.

## DOSBox Pure audio rate

**Verdict: MEASURE FIRST.** Expected: +1-4 % (estimate).

Mechanism. The OPL synthesiser and the mixer run on the emulation thread as timer ticks, at the core's audio rate
(OPL rate set from it, :2375; mixer :2358). On Linux the default is 48000 (:52-54; 32000 is only for GEKKO and
MIYOO builds). 22050 cuts the samples made by 54 %. RetroArch then resamples to 48000 on the main thread, off the
critical path. If synthesis and mixing are 4-8 % of the emulation thread, the gain is about half of that.

Evidence. Source only; the 4-8 % share is an estimate.

Cost. Duller top end on OPL music; Doom's sound effects are 11 kHz anyway. One new file,
`rootfs/overlay/etc/skel/.config/retroarch/config/DOSBox-pure/DOSBox-pure.opt` with
`dosbox_pure_audiorate = "22050"`. RetroArch 1.20 reads per-core options from that path (`runloop.c`
`validate_per_core_options`; `global_core_options` defaults to false). A per-game options file saved from the Quick
Menu overrides it for that game. Keep `sblaster_adlib_emu` at `default`, never `nuked`.

Measure. `demo3` at 48000 against 22050, three runs each, with "Cycles" from the performance statistics; RetroArch's
verbose log must show the 22050 input rate. Upper bound first: Doom with sound and music set to none in `SETUP.EXE`.
If that run is within noise of the baseline, drop this lever.

## Forced output rate

**Verdict: REJECT.** Expected: about +1 %.

Mechanism. `dosbox_pure_force60fps` = `35` makes the core report 35 fps; `DBP_NeedFrameSkip` (:651) then skips VGA
line rendering on the emulation thread for half of the 70 VGA frames, while emulated time keeps running. Doom never
draws more than 35 frames anyway. The saving is half the VGA render share, a few hundred microseconds per frame
(estimate).

Cost. 35 fps on a 60.04 Hz panel is outside the 0.05 timing skew, so RetroArch runs it unsynced like the PAL case:
uneven frame pacing and up to about 28 ms more latency. Not worth 1 %. A forced 60 might help the pacing question
(see "How the speed is set"), but that is not a speed lever.

## CPU at 1.344 GHz

**Verdict: REJECT.** Expected: +10-12 % at most (+8-11 % if part of the time is DRAM stalls).

Mechanism. The vendor's "extremity" point. Dynrec code and cache-resident data scale with the clock.

Evidence against.

- It needs 1.46 V: `sys_config.fex` `LV2_freq = 1344000000`, `LV2_volt = 1460`, 140 mV above the 1.32 V of our
  1.2 GHz point. The porting-plan note's "about 1.4 V" was wrong (since corrected).
- The 2016 mainline A33 OPP patch had the same point at 1460000 µV; the sunxi maintainer replied that it is not used
  by Allwinner and no A33 board known could supply it, and it was dropped
  (lkml.iu.edu/hypermail/linux/kernel/1612.1/03263.html, 1612.2/01230.html).
- Power on the busy core rises about 1.37 times (1.12 x (1.46 / 1.32)^2), on the one core that already runs flat
  out. The 4-thread test hit the 75 C trip at 1.2 GHz.

Cost. Silent instability at a voltage outside every mainline OPP; heat. How it would be done, if ever reopened: an
`opp-1344000000` with `turbo-mode` in the board device tree, `reg_dcdc3` max raised to 1460000 (AXP22x DCDC3 reaches
1.86 V), and `ga36-retroarch` writing `/sys/devices/system/cpu/cpufreq/boost` (cpufreq-dt's software boost, works
without `CPU_FREQ_STAT`), with the tmpfiles rule extended to that file.

Measure (only to reopen). `demo3` at both clocks, then the 10-minute frequency and temperature log, then a long
stability soak. Not worth doing before PrBoom and the in-game settings, which give more for nothing.

## DRAM above 552 MHz

**Verdict: REJECT.** Expected: 0-5 %.

Doom in DOSBox is bound by helper calls and an 8 MB guest working set, not by memory bandwidth; a faster DRAM clock
mainly helps bandwidth. 552 MHz is the SinA33 U-Boot default with DDR3-1333 timings; no A33 overclock report was
found, and on the A64 552 was stable only after power fixes while 624 crashed (forum.pine64.org/showthread.php?pid=75016).
The failure mode is silent memory corruption, worse than a crash.

## RetroArch threaded video

**Verdict: REJECT.** Expected: about 0 %.

The porting-plan note ranked it first. DOSBox Pure already hands video and audio to RetroArch after starting the next
emulated frame (:3664), so texture upload and page flips run on another core and the emulation thread never pays for
them. `top -H` shows it at 100 %: it is never idle waiting for the frontend. Threaded video could only help if the main
thread missed a frame deadline; with `retro_run` at 70 per second it does not. It would add a frame of input lag.

## RetroArch nearest resampler

**Verdict: REJECT.** Expected: about 0 %. The resampler runs on the main thread in parallel with emulation, like the
video work above. At most a little less L2 pollution (the A33 has 512 KB shared), below measurement noise.

## Compiler flags

**Verdict: REJECT.** Expected: 0-3 % (guess). The release build is `-O2` (`-O3` is only for the Vita). Our
`CPUFLAGS` override drops the upstream `-ffast-math`, which does not matter: Doom is fixed point and the dynrec's
generated code is not compiled by gcc. A command-line `CFLAGS` would also wipe the Makefile's own additions, so `-O3`
needs a Makefile patch, and the Makefile records a gcc miscompile of `core_dynrec.cpp`. No profile shows the C++
helpers are hot.

## Core options: cycles, CPU core, CPU type, machine

**Verdict: REJECT.** Expected: 0 %. The defaults are the fast path: `cpu_core` `auto` uses the dynrec in protected
mode, `cpu_type` `auto` is documented as the fastest, `cycle_limit` is 100 %. Raising cycles above capacity only
slows emulated time and inflates timedemo (see "Measurement method").

## Other DOSBox cores and other firmware

**Verdict: REJECT.** dosbox-core and dosbox-svn use the same ARM dynrec lineage; only forum anecdotes claim they are
faster. No other handheld firmware supports the A33 (ROCKNIX, ArkOS and dArkOS target RK3326; Knulli and MuOS the
H700); their good Doom speed comes from native ports, which is the PrBoom pointer.

## Services, ES, scheduling, kernel, memory

**Verdict: REJECT.** Expected: 0-1 %. A single busy thread on a 4-core CPU with about two busy threads in total has
no contention to remove.

- ES deinitialises its audio and window and blocks while the game runs; stopping it would need a launcher redesign.
- Enabled timers (apt, dpkg-db-backup, fstrim, tmpfiles-clean) fire daily or weekly; `ga36-lowbat` forks once a
  minute. Daemons (journald, udevd, dbus, logind, triggerhappy, a getty) are idle and land on the three free cores.
- `isolcpus`, `taskset`, `nice`: nothing to win; `chrt` FIFO risks starving the main thread.
- The kernel is already throughput-shaped (`PREEMPT_NONE`, `HZ=100`, no debug options); the Cortex-A7 needs no
  Spectre branch-predictor flush, so `mitigations=off` is 0 %; `nohz_full` saves about 0.1 %.
- 171 MiB used, no swap, no I/O during timedemo.
- LPAE with transparent huge pages could cut TLB misses for the guest memory and dynrec cache, but without a PMU
  node TLB misses cannot be counted, and it is a large kernel change for a guessed 0-5 %.

## Thermal throttling check

**Verdict: MEASURE FIRST.** Not a speedup but a check on the baseline. If a 10-minute Doom session at 1.2 GHz
reaches the 75 C trip, step_wise drops the clock to 1008 MHz (-16 %), and the fix would be cooling or a lower load,
not any lever above. Doom loads one core instead of four, so throttling is unlikely; it has not been measured.
