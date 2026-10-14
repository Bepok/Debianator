# Response to the implementation plan review

Answers `docs/review/implementation-plan-review.md`, one entry per claim, for the plan
`docs/plans/implementation-plan.md`.

Each claim was checked against these sources:
- the kernel tree `out/src/linux` and the built `out/build/linux/.config`;
- the board DTS;
- EmulationStation-fcamod at `74498be`;
- the RetroArch `v1.20.0` source;
- the five core Makefiles at their pinned commits;
- the Debian trixie armhf `retroarch` package page.

Date: 2026-10-15.

## Summary

| # | Claim | Verdict | Fix the plan? |
|---|-------|---------|---------------|
| 1 | `Headphone` asound.state grep | Correct, plus a second case the review missed | Yes |
| 2 | `cp -a` puts host ownership on `/` | Correct | Yes, with a simpler fix |
| 3 | Deviation 6 claim is false | Correct claim, overstated paths | Yes: rewrite the text, needs your ruling |
| 4 | fps includes startup | Correct | Yes |
| 5 | 60 Hz vs 55.69 Hz is outside the default skew | Correct premise, wrong outcome | Yes, with a different fix |
| 6 | s2idle RED premise not measured | Correct; the `/run` reason is wrong | Yes |
| 7 | Expected-RED lists incomplete | Correct | Yes |
| U1 | Debian `retroarch` without KMS | Lower risk than stated | Small test only |
| U2 | `classic_armv7_a7` missing in cores | Incorrect: present in all five | No |
| U3 | `ldd` misses dlopened libraries | Correct, harmless | No |
| U4 | systemd kernel options unset | Facts correct, impact overstated | No |
| U5 | `Conflicts=getty@tty1` race | Incorrect | No |
| U6 | rtcwake, render group, theme licence | rtcwake is valid | Yes (rtcwake only) |
| E1 | Two brightness write paths | Incorrect as a problem | No |
| E2 | Battery discovery | Correct, already patched | Device check only |
| K1 | `force_enable_pin` without sync | Covered by the device GREEN step | No |
| K2 | LRADC keydown threshold | Correct | Yes |
| H1 | binfmt F flag | Already caught by a test | Wording only |
| H2, H3, pins | e2fsprogs, Podman, pins | Agree | No |

## Definite errors

### 1. Headphone asound.state check: correct, and the review missed a second case

- `Headphone Playback Volume` is a `SOC_SINGLE_TLV` (`sound/soc/sunxi/sun8i-codec-analog.c:318`). For a
  one-channel control, `alsactl store` writes `value 50`, so the plan's `value.0 50` never matches.
- **Missed case:** `AIF1 DA0 Stereo Playback Route` is a `SOC_ENUM_DOUBLE` (`sun8i-codec.c:916`), which has two
  channels. alsactl writes `value.0 'Reverse Stereo'` / `value.1 ...`, so the plan's `value 'Reverse Stereo'` also
  never matches.
- `AIF1 DA0 Playback Volume` is a `SOC_DOUBLE_TLV` (`sun8i-codec.c:785`); its `value.0 160` check is right.

**Fix (Task 7 Step 1):**
- grep for `value 50` on Headphone;
- grep for `value.0 'Reverse Stereo'` on the route.

### 2. `cp -a` puts host ownership on `/`: correct

- `cp -a rootfs/overlay/. "$r/"` gives the existing `/` the owner and mode of the checkout directory.
- The chown loop uses `find . -mindepth 1`, so it does chown `./etc`, `./usr` and `./var` (they are in the
  overlay), but never `/`. It fixes no modes anywhere.
- Result: `/` belongs to uid 1000 (`ga36`). Under umask 002 the directories are also 775.

**Fix, simpler than the review's tar pipe.** In `rootfs/customize.sh`, change all three copies (the overlay,
`out/apps/usr/local`, the theme) from `cp -a` to `cp -r`.
- Running as root without `-p`, `cp -r` leaves existing directories as they are.
- New files and directories are owned by root, with the source mode minus the container umask (022).
- The `chown -R` line and the chown loop then go away. `chmod 0440` on the sudoers drop-in stays.

Test, added to `tests/rootfs.sh`: `./`, `./etc/`, `./usr/`, `./usr/local/` and `./var/` are all
`drwxr-xr-x 0/0`.

### 3. Deviation 6 ("no mixer path goes above them"): the claim is false, but the risk is smaller than stated

**True:** `AIF1 DA0 Playback Volume` and `DAC Playback Volume` go up to raw `0xc0`, which is +24 dB
(`sun8i-codec.c:777-809`).

**Overstated:** the review names ES and alsactl persistence as paths above 0 dB.
- ES drives `Headphone` only (ES patch 4). Headphone's maximum, 63, is the vendor cap.
- `alsactl store` at shutdown therefore only saves what ES could set.

**The only ways above 0 dB:**
- `alsamixer` in the root shell on `ttyGS0`, which needs physical access and is for testers;
- RetroArch's own software gain, up to +12 dB. It clips at digital full scale, the same as the vendor firmware's
  RetroArch.

**Recommendation:** rewrite deviation 6 as a fact plus an accepted risk:

> The digital controls reach +24 dB, but no user-facing control touches them: ES drives `Headphone`, capped at 63.
> RetroArch's software gain above 0 dB clips at full scale, as on the vendor firmware.

This sets how the spec's "capped at the vendor level" guard rail is read, so it needs your ruling. If you also
want the root-shell path closed, there is a hard-clamp alternative: in patch 0008, lower the TLV max of the two
digital controls to `0xa0` (0 dB).

### 4. The fps measurement includes startup: correct

- 3600 frames at 55.69 Hz take 64.6 s.
- 2 s of startup brings that to 54.0 fps, which is exactly the pass threshold.

**Fix (Task 10 Step 4):** run each core twice, for 1800 and 3600 frames. Then fps = 1800 / (t3600 - t1800), and
the startup time cancels out.

### 5. 60 Hz vs 55.69 Hz: the premise is correct, the outcome is wrong, and so is the plan's own premise

The skew is above the default 0.05: that part is true. But in RetroArch 1.20.0 (`retroarch.c:1330-1442`), when the
skew exceeds `audio_max_timing_skew` and the core fps is above the refresh rate, RetroArch:
- logs `Timings deviate too much` and `Game FPS > Monitor FPS. Cannot rely on VSync.`;
- switches video to non-blocking.

What actually happens:
- The game runs at full speed, paced by audio, at the correct pitch.
- Video tears and drops about 4 frames per second.
- There are no audio underruns, contrary to the review.

The plan is wrong as well. Its `retroarch.cfg` comment ("60 Hz games run about 7 % slow") and Review Focus 3
describe a mode the plan never turns on.

The skew per system:
- NES (Nestopia at 60.10 Hz) is 7.9 %, so the review's 0.08 is too tight for it.
- The other systems run at 59.7-59.9 Hz, a skew of 7.3-7.6 %.

**Fix.** This keeps the plan's stated intent: smooth video, 7 % slow, pitch lowered by the same amount.
- `retroarch.cfg`: add `audio_max_timing_skew = "0.100000"`.
- `tests/rootfs.sh`: grep for that key.
- Task 10 device step: run with `--verbose --log-file`. `Cannot rely on VSync` must appear 0 times. This proves the
  setting took effect.

The other policy (keep the default skew: correct speed, juddering video) is a valid choice too. The person's
judgement in Task 10 decides whether the lower pitch is acceptable.

### 6. The s2idle RED premise has not been measured: correct; the reason for `/run` is wrong

**Branching the step: agree.** If the RED read after patch 0008 is already `Playback 40`, drop the sleep hook and
record that in the ledger.

**"store overwrites the boot defaults": not a real issue.** Debian's `alsa-restore.service` already runs
`alsactl store` at every shutdown, so after the first shutdown `asound.state` is no longer the shipped default
anyway.

Use `/run` all the same (`alsactl -f /run/ga36-alsa.state store|restore`). It costs nothing extra and saves one
SD-card write per suspend.

**Also (from U6):** replace `rtcwake -m no -s 15` with `echo +15 > /sys/class/rtc/rtc0/wakealarm`. A test step
should not pull in a package.

### 7. Expected-RED lists are incomplete: correct

- **Task 2 Step 2:** the base dtsi has lradc `status = "disabled"` and no child nodes. The step prints
  `lradc not enabled` plus two `lradc has no key` lines.
- **Task 8 Step 1:** today's image is 272 MiB with p1 only. `p2 not ext4 ROOTFS` and `ES missing on p2` also fail.

## Uncertainties

### U1. Debian `retroarch` and KMS: lower risk than stated

- Trixie's armhf `retroarch` package depends on `libdrm2`, `libgbm1`, `libegl1` and `libgles2`: a GLES build with
  the libraries a KMS context needs.
- That does not prove the KMS context is compiled in.
- `video_driver = "gl"` also selects the GLES build.

**Fix:** add a cheap check to `tests/rootfs.sh`: `readelf -d` on `usr/bin/retroarch` lists `libgbm.so.1`. The real
proof stays the device boot in Tasks 8 and 10. No early probe is needed.

### U2. `classic_armv7_a7`: incorrect

All five Makefiles at their pinned commits define the target:
- snes9x2010 `Makefile.libretro:351`
- gpsp `Makefile:323`
- picodrive `Makefile.libretro:339`
- beetle-pce-fast `Makefile:111`
- pcsx_rearmed `Makefile.libretro:511`

No action.

### U3. `ldd` misses dlopened libraries: correct, harmless

- ES links `libvlc`, but the VLC plugins are dlopened, so video snaps will not play.
- ES checks `mVLC` before using it (`VideoVlcComponent.cpp:520`), so nothing crashes.
- Video snaps are not in the spec.
- On a `pkg1, pkg2: path` line, `cut -d: -f1` keeps the first owner, which is enough.

No change. Task 12 records "no video snaps" as a v1.0 limitation.

### U4. systemd kernel options: the facts are correct, the impact is overstated

- All five options are unset in `out/build/linux/.config`.
- `CONFIG_BINFMT_MISC` is also unset, so systemd's only default automount (`proc-sys-fs-binfmt_misc.automount`) is
  skipped by its condition.
- uaccess ACLs are not needed: `ga36` is in the `video`, `render`, `input` and `audio` groups.
- Nothing on this device uses memory accounting or BPF.

No change. Task 8's `systemctl --failed` check catches any unit that does fail.

### U5. `Conflicts=getty@tty1` race: incorrect

- gdm3 and sddm ship this exact pattern: `Conflicts=getty@tty1.service` while `getty@tty1` stays enabled.
- systemd settles the conflict on getty's job; it does not drop the display-manager unit.
- The Task 8 device step (`ActiveState=active`, `NRestarts=0`) would show a failure. Mask getty only if it does.
- Root autologin on `ttyGS0` is already recorded as deviation 8.

No change.

### U6. Smaller items

- **rtcwake:** valid. Replaced by sysfs, see 6.
- **`render` group:** if it is missing, `useradd -G` fails and the rootfs build stops, so it cannot slip through.
- **Theme licence:** already handled by the plan.

### E (verified anchors): agree.

### E1. Two brightness write paths: incorrect as a problem

- The only caller of `DisplayPanelControl::setBrightnessLevel` is `SystemScreenSaver` (lines 179 and 211), for the
  "black" screensaver, which dims on purpose.
- The default screensaver mode is `dim` (`Settings.cpp:155`), which does not call it.
- The menu slider (`GuiMenu.cpp:113`) is the only user path, and it goes through `setBrighness`, which the plan
  patches.

20 % maps to level 2, confirmed:
- the DTS has 11 `brightness-levels`, so `max_brightness` is 10;
- `setBrighness` computes 20 / 100 × 10 + 0.5, which truncates to 2.

No change.

### E2. Battery discovery: correct, and the plan already patches both reads

Add to Task 8 Step 4: the person confirms the ES menu status line shows `BAT: NN%` with a number.

### K1. `force_enable_pin` without an explicit sync: no change

- The graph is powered at card bind, when `snd_soc_dapm_new_widgets` runs.
- Task 1 Step 4's device GREEN step is the proof.
- The extra idle power is the price of the fix. Accepted.

### K2. LRADC keydown threshold: correct, worth a change

- The driver leaves `LEVELB_VOL` at 0 (`sun4i-lradc-keys.c:172`). KEYDOWN therefore fires only below the default
  level-B threshold, 0x3C according to the A33 manual.
- **Fix:** in Task 2 Step 1, take Branch A only if both raw values are below 0x3C.
- **vref:** the board DTS sets `reg_aldo3` to 3.0 V (`dts:282-285`), so the plan's 2.0 V matches what the driver
  computes.
- **Clock:** the lradc node has no `clocks` property (`sun8i-a23-a33.dtsi:476-482`), so devmem needs no gate.

### H1. binfmt F flag: already caught by a test

- The F flag is needed: true.
- `tests/container.sh` already runs `arch-test armhf` inside a container that has no qemu. That can only pass when
  the F flag is set, and mmdebstrap needs exactly the same thing.
- **Wording fix only:**
  - Execution notes: replace the `ls | grep qemu-arm` host check with `./build.sh run tests/container.sh`.
  - Have that FAIL message mention the F flag.
- No `qemu-arm` entry is registered on the build host yet.

### H2, H3, pins: agree, no action.

## Plan changes to make

1. **Deviation 6:** rewrite as in 3 (your ruling). Review Focus 3: describe the 0.10-skew mode.
2. **Task 2:** Step 1 gets the 0x3C condition for Branch A. Step 2 gets the full Expected list.
3. **Task 7:**
   - fix the asound.state greps (`value 50`, `value.0 'Reverse Stereo'`);
   - `cp -r` in `customize.sh`, without the chown lines;
   - the top-level directory owner/mode test;
   - the `readelf` libgbm check.
4. **Task 8:** Step 1 gets the full Expected list. Step 4 gets the battery percentage check.
5. **Task 10:**
   - `audio_max_timing_skew = "0.100000"`, with its test and the corrected comment;
   - the two-run fps formula;
   - the `Cannot rely on VSync` log check.
6. **Task 11 Step 6:** branch on the measured RED; state file in `/run`; sysfs `wakealarm` instead of rtcwake.
7. **Execution notes:** binfmt check through `tests/container.sh`.
