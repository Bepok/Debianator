# Review: implementation plan

Reviewed: `docs/plans/implementation-plan.md` (untracked draft, 1667 lines), against
`docs/specs/2026-10-14-firmware-design.md`, the repository scripts and tests
(`build.sh`, `tree.sh`, `tests/`, `Containerfile`, `make-test-sdcard.sh`,
`make-test-initramfs.sh`, `board-run.sh`, `fel-boot.sh`), the hardware notes, the
board DTS, the built kernel `.config`, the kernel sources in `out/src/linux`, and the
upstream sources at the pinned commits.

Date: 2026-10-15.

## Verdict

The plan is structurally sound and is valid as a sequence: tasks are ordered so each
one builds on verified ground, every task has a failing-first test, person steps are
batched, the ledger is consistent, the partition layout arithmetic is correct, and
the `tree.sh` / `tests/` extensions fit the existing code.

It is **not free of errors**. Before execution it needs:

| # | Kind | Where | Severity |
|---|------|-------|----------|
| 1 | Test can never pass | Task 7, `asound.state` check | Bug |
| 2 | Ownership/mode of `/` taken from the host | Task 7, `customize.sh` overlay copy | Bug (security) |
| 3 | False safety claim | Deviation 6, volume ceiling | Logic error |
| 4 | Measurement includes startup time | Task 10, fps check | Flawed test |
| 5 | Audio timing skew outside RetroArch default | Task 10 / Review Focus 3 | Probable defect |
| 6 | Unmeasured RED premise | Task 11 Step 6, s2idle mixer loss | Logic gap |
| 7 | Incomplete expected-RED lists | Task 2 Step 2, Task 8 Step 1 | Minor |

The largest unmitigated risk is not in the plan's logic but in an assumption it never
probes: that Debian trixie's `retroarch` armhf package has a KMS/EGL context usable
without X or Wayland (see U1).

## Definite errors

### 1. Task 7: `Headphone Playback Volume` test matches the wrong alsactl syntax

The test greps `asound.state` for `value.0 50`. `Headphone Playback Volume` is a
`SOC_SINGLE_TLV` control (`sound/soc/sunxi/sun8i-codec.c`, range 0..0x3f, one
channel). `alsactl store` writes `value N` for count-1 controls and `value.0` /
`value.1` only for multi-channel ones. The check can never succeed.

Fix: match `value 50` for the headphone control. Stereo controls (`AIF1 DA0 Playback
Volume`, `DAC Playback Volume`, the `SOC_ENUM_DOUBLE` stereo route) keep the
`value.0` / `value.1` form.

### 2. Task 7: `cp -a rootfs/overlay/. "$r/"` copies host ownership onto `/`

`cp -a` with a trailing `/.` copies the attributes of the overlay directories onto
the existing target directories: `/`, `/etc`, `/usr`, `/var` in the rootfs take the
owner, group and mode of the checkout's directories. On a host where the checkout
belongs to uid 1000 (which is also `ga36` in the image) and umask is 002 (Ubuntu
default), the rootfs `/` ends up owned by `ga36` and group-writable.

The following chown loop uses `find "$r/..." -mindepth 1`, so it never fixes the top
directory. No test looks at the owner or mode of `./`, `./etc`, `./usr`.

Fix (any one):

- `tar -C rootfs/overlay --owner=0 --group=0 -cf - . | tar -C "$r" --no-overwrite-dir -xf -`;
- or keep `cp -a` and follow it with `chown 0:0 "$r" "$r/etc" "$r/usr" "$r/var"` and
  `chmod 755` on the same list.

Add a test: `tar -tvf rootfs.tar ./ ./etc/ ./usr/` shows `root/root` and `drwxr-xr-x`.

### 3. Deviation 6: "no mixer path goes above them" is false

The deviation justifies the speaker volume defaults by claiming the stored values are
a ceiling. They are not:

- `AIF1 DA0 Playback Volume` and `DAC Playback Volume` are TLV -120 dB, step 0.75 dB,
  max raw 192 = **+24 dB** each; 160 = 0 dB. The plan's 80 % DAC (raw ~154) is
  about -4.5 dB, so 34 dB of digital gain remains reachable from `alsamixer`, ES's
  volume control (it drives `Master`/the configured control), or RetroArch's own
  `audio_volume` (up to +12 dB in-menu).
- Digital gain past 0 dBFS clips. Peak amplitude stays at full scale, but RMS and
  high-frequency energy rise (a hard-clipped sine approaches a square, about +3 dB
  RMS). That is more speaker stress than the vendor level, which contradicts the
  spec guard rail "speaker volume capped at the vendor level".
- `alsactl store` at shutdown persists whatever the user set, so a raised value
  survives reboots.

Fix: either enforce a ceiling (clamp the digital controls at 0 dB: a kernel patch to
the TLV max, or a `restore`-time clamp in a unit plus a test), or rewrite the
deviation as an explicit accepted risk with the person's ruling recorded in the
ledger. Do not leave the current claim, because Review Focus relies on it.

### 4. Task 10: fps measurement includes process start and content load

The check runs RetroArch for a fixed frame count and divides by wall-clock time. That
time includes process start, core load, ROM load and BIOS load. With a ceiling of
55.69 fps and a pass threshold of 54.0, about 2 s of startup is enough to push a
healthy core below the threshold over a typical run length. The test produces false
failures and cannot tell slow emulation from slow startup.

Fix: run twice (N and 2N frames) and use the difference, or take frame timing from
RetroArch's own log/statistics instead of wall-clock time.

### 5. Task 10: 60 to 55.69 Hz is outside RetroArch's default timing skew

The panel refreshes at 55.69 Hz; the cores run at about 60 Hz. The skew is ~7.2 %.
RetroArch's dynamic rate control only adjusts within `audio_max_timing_skew`, default
0.05. Beyond that it keeps the core's nominal audio rate while vsync throttles video
to the panel, so the audio buffer drains: expect periodic underruns (crackle) rather
than smooth slow-down. Review Focus 3 leaves this to the person's ear.

Fix: decide the policy up front and put it in the shipped `retroarch.cfg`, with a
test that greps for it:

- `audio_max_timing_skew = "0.08"` (or higher): sync to video, audio pitch drops
  ~7 %; or
- `video_vsync = "false"` and sync to audio: correct pitch, tearing/judder.

### 6. Task 11 Step 6: the RED premise has never been measured

Step 6 expects the codec to lose its registers across s2idle, so the RED read is
`Playback 0` and the sleep hook makes it 40. Nothing in the hardware notes records
that loss. With patch 0008 (Task 1) forcing the codec `mod` clock supply on, the
register file may well survive s2idle; then the RED step reads 40 and passes before
any hook exists, which the plan treats as an impossible outcome.

Fix: branch the step. If the RED read is 40, the hook is unnecessary: record that in
the ledger and drop it. Separately, the hook as written runs `alsactl store` on every
suspend, overwriting `/var/lib/alsa/asound.state` (the boot defaults) each time. Store
to a file under `/run` and restore from there.

### 7. Expected-RED lists are incomplete

Not wrong, but an executor comparing output to the list will see "unexpected" lines:

- Task 2 Step 2 also prints `lradc has no key` twice (one per DTB check).
- Task 8 Step 1 also fails `p2 not ext4 ROOTFS` and `ES missing on p2`.

## Uncertainties

Grouped by area; ordered by risk within each group. "Verified" items are listed
where the review cleared an earlier doubt.

### Userspace stack

- **U1. Debian `retroarch` KMS support (highest risk).** The plan sets
  `video_driver = "gl"` and `video_context_driver = "kms"`. Whether trixie's armhf
  build enables KMS/EGL and desktop GL vs GLES is not checked anywhere before
  Task 10. Without a KMS context there is no fullscreen path without X/Wayland, and
  Task 10 is the first place it would show. Recommend an early probe in Task 6 or 7:
  `chroot "$r" retroarch --features` and a test grepping `KMS/EGL: yes`. Lima's desktop
  GL 2.1 throughput on this core is also unmeasured.
- **U2. libretro `platform=classic_armv7_a7`.** Not confirmed to exist in all five
  core Makefiles (snes9x2010, gpsp, picodrive, beetle-pce-fast, pcsx_rearmed). A
  missing target silently falls back to generic flags. Building under qemu-user
  will take hours; the plan accepted that over cross-compiling.
- **U3. `runtime-deps` via `ldd`** misses `dlopen`ed libraries (VLC plugins:
  ES video snaps will probably not play). `dpkg -S` can print `pkg1, pkg2: path`
  lines; the parser handles them by accident.
- **U4. Kernel options systemd 257 prefers** are unset in the built `.config`:
  `AUTOFS_FS`, `TMPFS_POSIX_ACL`, `TMPFS_XATTR`, `MEMCG`, `BPF_SYSCALL`. systemd
  boots but logs warnings and loses automount, memory accounting and uaccess ACLs on
  tmpfs. The plan has no userspace-driven kernel config task; Task 8's "degraded"
  handling may surface this late. Required ones (`CGROUPS`, `FHANDLE`, `DEVTMPFS`,
  `TMPFS`, `INOTIFY`, `SIGNALFD`, `TIMERFD`, `EPOLL`, `SECCOMP`, `VT`, `EXT4`,
  `EXFAT`, `ZRAM`, `PM_SLEEP`, `RTC_DRV_SUN6I`) are set: verified.
- **U5. `emulationstation.service` with `Conflicts=getty@tty1.service`** while
  `getty@tty1` stays enabled: both are queued in the same boot transaction and
  systemd may drop either job. Mask `getty@tty1` in `customize.sh` instead. Root
  autologin on `ttyGS0` is a deliberate deviation (physical access only); record it
  as an accepted risk.
- **U6. Smaller items.** `rtcwake` may live in `util-linux-extra` in trixie (Task 11
  Step 6 on the release rootfs). The `render` group is assumed to come from systemd
  sysusers. Theme licence file name `readme.txt` (plan already tolerates absence).

### EmulationStation (fcamod at `74498be`)

- **Verified:** the pinned commit exists upstream; the cited anchors match:
  `Renderer_GLES10.cpp:17` is `#include <go2/audio.h>`, `GuiMenu.cpp:85` is the
  BAT/SND/BRT/WIFI status line, `Settings.cpp` ~222 sets `AudioDevice = "Master"`,
  `queryBatteryInformation`, `VolumeControl::getVolume` and
  `ApiSystem::getBrightnessLevel` exist, the `GLES` CMake option exists, and the
  binary goes to the source directory (`EXECUTABLE_OUTPUT_PATH`).
- **Verified:** `InputManager::getConfigPath()` is hard-coded to
  `/etc/emulationstation/es_input.cfg`, and `es_systems.cfg` falls back to
  `/etc/emulationstation/`. The plan's `/etc` paths are correct.
- **E1. Two brightness write paths.** The settings slider calls
  `ApiSystem::setBrighness` (clamp 1..100 %, scaled to `max_brightness`);
  `DisplayPanelControl::setBrightnessLevel` clamps to 5 % or shells out to
  `brightnessctl` if present. A brightness floor added to only one of them can be
  bypassed by the other. The percent-to-level mapping (20 % to level 2) depends on
  `max_brightness` of the mainline backlight node; confirm on the device.
- **E2. Battery discovery.** `queryBatteryInformation` picks the first
  `/sys/class/power_supply/*` entry containing `/bat`; the status line reads
  `/sys/class/power_supply/battery/capacity`. Mainline AXP223 registers
  `axp20x-battery`, which matches neither. The plan patches both; the device step
  should confirm the menu shows a percentage, not an empty string.

### Kernel and hardware (Tasks 1, 2, 11)

- **K1. Task 1 root cause** (gating the codec `mod` clock resets the analog block) is
  a hypothesis from the bring-up notes. `snd_soc_dapm_force_enable_pin` in component
  probe is applied without an explicit `snd_soc_dapm_sync`; it is very likely synced
  at card bind, but that is unverified. Keeping PLL_AUDIO and `mod` on costs idle and
  s2idle power. The device GREEN step mitigates the correctness side.
- **K2. Task 2 LRADC.** The node (`/soc/lradc@1c22800`, `sun4i-a10-lradc-keys`) and
  `CONFIG_KEYBOARD_SUN4I_LRADC=y` are verified. The driver computes
  `vref = regulator * 2/3` and only raises KEYDOWN below the hardware threshold, so
  key levels near idle (0x3F) may never fire. The vref supply assumption (`reg_aldo3`,
  3.0 V, as on sina33) is unverified on GA36; the vendor fex gives LRADC ranges
  (`fel_key` 2..6, recovery 0x10..0x13) as hints. The `devmem` probe assumes no clock
  gate is needed.

### Build host

- **H1. binfmt F flag.** Running armhf binaries inside a chroot or container needs
  `qemu-arm` registered with the fix-binary (F) flag. The plan checks only that the
  entry exists. Use `grep -q '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-arm`. The host
  is Ubuntu, whose `qemu-user-binfmt` packaging may differ from Debian's.
- **H2. `mkfs.ext4 -d <tarball>`** requires e2fsprogs built with libarchive support;
  the plan's test covers it, so a failure is caught early.
- **H3. Podman** is untested for root stages (stated in the plan). Rootless Podman
  with `--privileged` will not work for loop devices and chroots.

### Pins

- **Verified:** all seven pinned commits exist upstream (EmulationStation-fcamod,
  es-theme-carbon, snes9x2010, gpsp, picodrive, beetle-pce-fast-libretro,
  pcsx_rearmed).

## Consistency with the spec

The plan lists ten deviations from the spec (libgo2 and pixman dropped, chroot build
instead of qemu-user-static inside the container, timer instead of a udev rule, and
others). Each is stated and justified; none silently contradicts the spec, with the
exception of deviation 6 (error 3 above), whose justification is false.

## Recommended changes, in order

1. Fix errors 1 and 2 in Task 7 and add the `./` owner/mode test.
2. Add the `retroarch --features` probe (U1) to Task 6 or 7, before anything depends
   on it.
3. Resolve deviation 6: clamp or recorded ruling.
4. Rewrite the Task 10 fps measurement and fix the audio sync policy in
   `retroarch.cfg`.
5. Branch Task 11 Step 6 on the measured RED result; store suspend state in `/run`.
6. Mask `getty@tty1`; check the binfmt F flag; complete the expected-RED lists.
