# Userspace (sub-project 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A test SD card that boots the GA36 into EmulationStation on a Debian trixie armhf rootfs, runs the seven
spec'd systems through RetroArch, keeps the volume within the vendor cap, suspends and powers off cleanly, and
creates or restores the ROMS partition on first boot.

**Architecture:** Two new root-run build stages in the pinned container. `./build.sh apps` builds ES fcamod and five
libretro cores from pinned commits in a throwaway armhf chroot (mmdebstrap root mode, host qemu-user binfmt) into
`out/apps/`. `./build.sh rootfs` makes the release rootfs tarball from `rootfs/packages.list`, the apps' run-time
packages, `rootfs/overlay/` and `rootfs/customize.sh`. The test card carries it as p2 (ext4, `mkfs.ext4 -d`). One
kernel patch fixes the A33 analog codec reset; a second one maps Vol+/Vol- if the LRADC probe finds them.

**Tech Stack:** POSIX sh, mmdebstrap 1.5 (`--mode=root`), qemu-user binfmt (host), Debian trixie armhf (RetroArch
1.20.0, Mesa lima, SDL2, libglvnd GLES1), EmulationStation-fcamod (branch 351v), libretro cores, systemd units,
e2fsprogs/exfatprogs/sfdisk, Linux 6.18.56 patches.

**Spec:** [`docs/specs/2026-10-14-firmware-design.md`](../specs/2026-10-14-firmware-design.md), section 4 (and
the p3 rules of section 5).

## Global Constraints

- Spec: "Debian trixie armhf"; "`mmdebstrap` trixie armhf minbase plus `rootfs/packages.list`"; "No networking in
  v1.0 (no Wi-Fi)".
- Spec: "Serial getty on the USB gadget ACM port `ttyGS0`. Autologin user `ga36` on tty1 starts ES through a systemd
  unit that restarts it on exit."
- Spec: cores table: nestopia, gambatte, RetroArch 1.20.0 from Debian; snes9x2010, gpsp, picodrive, beetle-pce-fast,
  pcsx_rearmed built from pinned commits.
- Spec: "the vendor volume cap is `Headphone` 63 of 63"; "`AIF1 DA0` to 0 dB" (160) and "`AIF1 DA0 Stereo` to
  `Reverse Stereo`"; "backlight level 1 looks off, so the userspace minimum must be above 1".
- Spec: "p2 is a fixed 3 GiB, so p3 always starts at the same offset"; "if an exFAT filesystem is there it only
  restores the partition entry; it formats only when nothing is there".
- Spec: "Swap: zram (~256 MiB), no SD swap".
- Spec: "speaker volume capped at the vendor level".
- Everything written to disk is English. No test code, test hooks or fixtures in the rootfs or any image.
- Commits: author `Bepok <wojtekjakubiszyn@gmail.com>`, no Co-Authored-By or "Generated with" trailers, no em dashes
  or decorative emoji in commit messages.
- Parallel jobs capped at `nproc` (16); only one build runs at a time.

## Spec deviations (applied to the spec in the last task)

1. **No libgo2, no pixman.** ES fcamod branch 351v (commit 74498be) renders through SDL2 with GLES1
   (`-DGLES=ON` → `USE_OPENGLES_10`) and links no libgo2; only one stale `#include <go2/audio.h>` remains. ES gets its
   own patch series in `apps/emulationstation/patches/` instead. pixman leaves the package list.
2. **Apps build in a throwaway chroot, not inside the rootfs.** Keeps compilers and `-dev` packages out of the 3 GiB
   release rootfs; the rootfs installs only the run-time packages the binaries link (`out/apps/runtime-deps.list`).
   Layout: `apps/<name>/patches/`, `apps/build-deps.list`, `apps/build-in-chroot.sh`.
3. **`rootfs` and `apps` stages run as root in a privileged container** and use the host's `qemu-user-binfmt`
   (binfmt_misc is not namespaced; Docker is rootful and AppArmor blocks unprivileged user namespaces here, so
   `--mode=unshare` is out). The host needs Docker plus that package; Podman is untested for these two stages.
4. **Low battery: a 60 s systemd timer, not a udev rule.** `axp20x_battery` sends no uevent when the capacity changes,
   so a udev rule would never fire.
5. **No headphone/speaker toggle.** Headphones mute the speaker in hardware (hardware notes).
6. **No separate volume clamp (accepted risk, owner's ruling 2026-10-15).** The spec's "speaker volume capped at
   the vendor level" is read as the analog amplifier gain: `Headphone` 63 is both the register maximum and the vendor
   cap, and the only control ES drives. `AIF1 DA0` and `DAC` ship at 160 (0 dB) but reach 0xc0 (+24 dB); no
   user-facing control touches them, only `alsamixer` in the root shell on `ttyGS0` (physical access). Digital gain,
   there or in RetroArch's software volume, clips at digital full scale, so the peak drive into the amplifier stays
   DAC full scale at `Headphone` 63; clipping raises only the average power, as on the vendor firmware. A kernel
   clamp was rejected: it would close the codec path but not RetroArch's, so it would not enforce the cap.
7. **Autologin = ES service with `PAMName=login`** on tty1 (`Conflicts=getty@tty1`), not a getty autologin chaining
   into a shell profile.
8. **`ttyGS0` getty logs in root without a password.** Testers and `scripts/board-run.sh` need a shell over USB; the
   device has no network, so this needs physical access.
9. **Vol+/Vol- (decided in Task 2):** mapped through the LRADC (kernel patch 0009, triggerhappy) if the probe sees
   them; otherwise unmapped in v1.0, volume set in the ES menu, triggerhappy and FN+Vol brightness dropped.
10. **The test card carries the rootfs** until sub-project 4's `make-image.sh` exists; FEL keeps the test initramfs.

## Review Focus

1. **Reflash over a card that already has ROMs:** p3's entry is missing but its exFAT data is not; the first-boot
   unit must restore the entry and never format. A card too small for p3 is skipped, not failed. Tests:
   `tests/roms-part.sh` cases "restore" and "too small" (Task 9), device step "delete p3 entry, reboot, marker
   survives" (Task 9).
2. **Low battery while charging** (capacity ≤ 3 % but status `Charging` or `Not charging`) must not power off.
   Test: `tests/power.sh` charging cases (Task 11).
3. **Game speed on a 55.69 Hz panel with vsync** (about 7 % slow for 60 Hz systems, only because
   `audio_max_timing_skew` is raised to 0.10; at the default 0.05 RetroArch gives up vsync and the video tears):
   measured fps per core, a log with no `Cannot rely on VSync`, and a person's judgement of audio. Test: Task 10 fps
   run and [person] step.
4. **Suspend inside a game:** after resume the mixer is back to its pre-sleep values (the analog codec loses its
   registers in s2idle). Test: Task 11 device step "Headphone 40 survives systemctl suspend".
5. **First boot with an empty ROMS partition:** ES shows its no-games screen and stays up instead of crash-looping
   under `Restart=always`. Test: Task 9 device step `NRestarts=0` after 60 s.

## Execution notes

- Worktree: `git worktree add -b userspace .claude/worktrees/userspace` from the repo root; all work there. `out/` is
  per worktree: run `./build.sh uboot kernel initramfs` equivalents (`./build.sh uboot`, `./build.sh kernel`,
  `./build.sh initramfs`) once before Task 1.
- Every repo commit: `git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit ...` (written below as
  `git commit`). Kernel commits inside `out/src/linux` add `-s` (DCO); re-check `Signed-off-by` is present right
  after `scripts/tree.sh export linux`.
- Host prerequisite [person], once: `sudo apt install qemu-user-binfmt`. Check it with `./build.sh run
  tests/container.sh` after Task 3: `arch-test armhf` inside the container (which has no qemu) passes only when the
  host entry is registered with the F (fix-binary) flag, which mmdebstrap needs too.
- [person] steps are batched per task: ask for all of a task's person actions in one message.
- FEL entry: no card in the slot, press the power key; `scripts/fel-boot.sh kernel` waits for it.
- Card writes [person]: `sudo dd if=out/sdcard/ga36-test.img of=/dev/sdX bs=4M conv=fsync status=progress`
  (whole-device node of the card reader; check `lsblk` first).
- Board shell: `scripts/board-run.sh 'CMD'` (`TIMEOUT=` for long commands). After s2idle resume the USB console
  returns only after a cable replug.
- Long build output goes to a file in the workspace (`> "$W/apps.log" 2>&1`); read its tail.

---

### Task 1: A33 codec keeps its analog registers between streams (kernel patch 0008)

**Files:**
- Modify: `out/src/linux/sound/soc/sunxi/sun8i-codec.c` (struct `sun8i_codec_quirks` ~211, `sun8i_codec_component_probe` ~1288, `sun8i_a33_quirks` ~1683)
- Create: `kernel/patches/0008-ASoC-sun8i-codec-keep-the-module-clock-on-for-the-A33.patch` (by export)

**Interfaces:**
- Consumes: `./build.sh kernel`, `scripts/fel-boot.sh kernel`, `scripts/board-run.sh`.
- Produces: a kernel where `Headphone` keeps its value after a stream stops; Tasks 7 and 11 rely on it.

- [ ] **Step 1: Device RED.** Build and boot the unpatched kernel, then run the stream-stop check.

```bash
./build.sh kernel > "$W/kernel.log" 2>&1 && scripts/fel-boot.sh kernel
TIMEOUT=60 scripts/board-run.sh "amixer -q sset 'AIF1 DA0' 160; amixer -q sset 'AIF1 Slot 0 Digital DAC' on; amixer -q sset 'Headphone Source' DAC; amixer -q sset Headphone 63 unmute; echo before \$(amixer sget Headphone | grep -o 'Playback [0-9]*' | head -1); speaker-test -t sine -f 440 -c 2 -l 1 >/dev/null 2>&1; sleep 8; echo after \$(amixer sget Headphone | grep -o 'Playback [0-9]*' | head -1)"
```

Expected: `after Playback 0` (the analog block reset after the stream stopped and pmdown expired).

- [ ] **Step 2: Patch.** In `out/src/linux/sound/soc/sunxi/sun8i-codec.c`:

Struct (keep the tab alignment of the neighbours):
```c
struct sun8i_codec_quirks {
	bool	bus_clock	: 1;
	bool	jack_detection	: 1;
	bool	legacy_widgets	: 1;
	bool	lrck_inversion	: 1;
	bool	mod_always_on	: 1;
};
```

In `sun8i_codec_component_probe`, right after the closing brace of the `legacy_widgets` block:
```c
	/*
	 * On the A33 the analog codec in the PRCM block returns to its reset
	 * values (outputs muted) whenever the module clock is gated, which DAPM
	 * does after every stream. Keep the module clock running.
	 */
	if (scodec->quirks->mod_always_on) {
		ret = snd_soc_dapm_force_enable_pin(dapm, "mod");
		if (ret)
			return ret;
	}
```

A33 quirks:
```c
static const struct sun8i_codec_quirks sun8i_a33_quirks = {
	.bus_clock	= true,
	.legacy_widgets	= true,
	.lrck_inversion	= true,
	.mod_always_on	= true,
};
```

- [ ] **Step 3: Commit and export.**

```bash
cd out/src/linux
git add sound/soc/sunxi/sun8i-codec.c
git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit -s -m "ASoC: sun8i-codec: keep the module clock on for the A33" -m "On the A33 the analog codec registers in the PRCM block return to their reset values whenever the codec module clock is gated. DAPM gates it after every stream, so each new stream starts with the headphone output muted at volume 0.

Add a quirk that keeps the \"mod\" clock supply forced on and set it for the A33."
cd ../../..
./build.sh run scripts/tree.sh export linux
grep -c '^Signed-off-by: Bepok <wojtekjakubiszyn@gmail.com>' kernel/patches/0008-*.patch
```

Expected: `1`.

- [ ] **Step 4: Device GREEN.** Rebuild, FEL-boot, rerun the Step 1 command.

Expected: `before Playback 63` and `after Playback 63`. If `after` is still 0: superpowers:systematic-debugging
on the device (dump the analog registers with `busybox devmem` before and after the stream) and do not start Task 7's
ALSA capture until this passes.

- [ ] **Step 5: Kernel checks still pass.**

Run: `./build.sh run tests/kernel-config.sh && ./build.sh run tests/dtb.sh`
Expected: `PASS` twice.

- [ ] **Step 6: Commit.**

```bash
git add kernel/patches/0008-*.patch
git commit -m "Keep the A33 codec module clock on so the mixer survives stream stops"
```

### Task 2: Vol+/Vol- on the LRADC (probe, then kernel patch 0009 or a recorded deviation)

**Files:**
- Modify (Branch A): `out/src/linux/arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`
- Create (Branch A): `kernel/patches/0009-ARM-dts-sun8i-a33-ga36-add-the-volume-keys.patch` (by export)
- Ledger (Branch B): `Task 2: Ruling: Vol keys not on LRADC ...`

**Interfaces:**
- Consumes: FEL kernel from Task 1.
- Produces: `VOLKEYS=yes|no` in the ledger. Task 11 reads it; `yes` means input events `KEY_VOLUMEUP` (115) and
  `KEY_VOLUMEDOWN` (114) from a device whose name contains `lradc`.

- [ ] **Step 1: Probe [person].** FEL-boot (`scripts/fel-boot.sh kernel`). Ask the person: "When I say go: hands off
  for 5 s, hold Vol+ for 5 s, hold Vol- for 5 s." Then run:

```bash
TIMEOUT=40 scripts/board-run.sh 'busybox devmem 0x01c22800 32 1; sleep 1; i=0; while [ $i -lt 15 ]; do echo "$i $(busybox devmem 0x01c2280c 32)"; sleep 1; i=$((i+1)); done'
```

Expected: 15 lines of `<second> 0x000000NN`. Seconds 0-4 give the idle value (about `0x3F`). If seconds 5-9 and
10-14 show two values different from idle and from each other, and both below `0x3C`: **Branch A**, record
`VOLKEYS=yes` and the two raw values `UP_RAW`, `DOWN_RAW` (low 6 bits). Otherwise **Branch B**. (The driver leaves
`LEVELB_VOL` at 0, so KEYDOWN fires only below the default level-B threshold 0x3C; a key that reads 0x3C or above
never reports a press.)

- [ ] **Step 2 (Branch A): Write the failing dtb check.** Append to `tests/dtb.sh` before its final `[ $fail = 0 ]`
  line, in its existing style (it reads the built DTB with `fdtget`; use its DTB variable name):

```sh
fdtget "$dtb" /soc/lradc@1c22800 status | grep -qx okay || bad "lradc not enabled"
for k in 114 115; do
	fdtget -l "$dtb" /soc/lradc@1c22800 | while read -r n; do fdtget "$dtb" "/soc/lradc@1c22800/$n" linux,code; done | grep -qx "$k" || bad "lradc has no key $k"
done
```

Run: `./build.sh run tests/dtb.sh`
Expected: `FAIL: lradc not enabled`, `FAIL: lradc has no key 114`, `FAIL: lradc has no key 115`.

- [ ] **Step 3 (Branch A): DTS.** Compute the voltages: vref = 3.0 V (`reg_aldo3`) × 2/3 = 2.0 V, so
  `UP_UV=$((UP_RAW * 2000000 / 63))` and `DOWN_UV=$((DOWN_RAW * 2000000 / 63))`. The driver picks the closest
  entry, so the computed values need no margin. Add to the board DTS, after `&reg_aldo3`'s node, with
  `#include <dt-bindings/input/input.h>` already present for gpio-keys:

```dts
&lradc {
	vref-supply = <&reg_aldo3>;
	status = "okay";

	button-<UP_UV/1000> {
		label = "Volume Up";
		linux,code = <KEY_VOLUMEUP>;
		channel = <0>;
		voltage = <UP_UV>;
	};

	button-<DOWN_UV/1000> {
		label = "Volume Down";
		linux,code = <KEY_VOLUMEDOWN>;
		channel = <0>;
		voltage = <DOWN_UV>;
	};
};
```

(`<UP_UV>` etc. are the integers just computed; node names are `button-` plus the value in mV.)

- [ ] **Step 4 (Branch A): GREEN.**

Run: `./build.sh kernel > "$W/kernel.log" 2>&1 && ./build.sh run tests/dtb.sh && ./build.sh run tests/dt-schema.sh`
Expected: `PASS` twice.

- [ ] **Step 5 (Branch A): Device check [person].** FEL-boot; ask the person to press Vol+ then Vol- within 10 s.

```bash
TIMEOUT=30 scripts/board-run.sh 'for e in /sys/class/input/event*; do grep -q lradc $e/device/name && ev=/dev/input/${e##*/}; done; echo dev $ev; timeout 10 evtest $ev | grep "value 1"'
```

Expected: `dev /dev/input/eventN`, then a line with `code 115 (KEY_VOLUMEUP)` and one with `code 114 (KEY_VOLUMEDOWN)`.

- [ ] **Step 6 (Branch A): Commit and export.**

```bash
cd out/src/linux
git add arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts
git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit -s -m "ARM: dts: sun8i: a33: ga36: add the volume keys" -m "Vol+ and Vol- are a resistor ladder on LRADC channel 0, referenced to ALDO3. Voltages measured on a GA36-MB V1.0."
cd ../../..
./build.sh run scripts/tree.sh export linux
grep -c '^Signed-off-by: Bepok' kernel/patches/0009-*.patch
git add kernel/patches/0009-*.patch tests/dtb.sh
git commit -m "Map Vol+ and Vol- on the LRADC"
```

Expected: `1` before the commit.

- [ ] **Step 2-6 (Branch B):** no code. Ledger: `Task 2: Ruling: VOLKEYS=no; LRADC DATA0 does not change with Vol+/Vol- (values: ...) - volume via the ES menu in v1.0, triggerhappy dropped - cost if wrong: two keys unused until v1.1`.

### Task 3: Root runner, armhf emulation and filesystem tools in the build container

**Files:**
- Modify: `container/Containerfile` (package list)
- Modify: `build.sh` (usage, `root()`, `apps`/`rootfs` cases)
- Modify: `tests/container.sh`

**Interfaces:**
- Produces: `root <cmd>` in `build.sh`: runs `<cmd>` as root, `--privileged`, cwd `/work`, env `HOST_UID`, `HOST_GID`.
  Stage scripts run by `root` must `chown -R "$HOST_UID:$HOST_GID"` their output on exit. Stage names `apps` and
  `rootfs` (scripts added in Tasks 6 and 7).

- [ ] **Step 1: Failing test.** Replace `tests/container.sh` with:

```sh
#!/bin/sh
# The build container has every tool the stages use. Run: ./build.sh run tests/container.sh
set -eu
fail=0
for tool in arm-linux-gnueabihf-gcc gcc make bison flex bc python3 swig git curl xz cpio rsync \
	fdtget dtc dt-validate mmdebstrap fakechroot mcopy mkfs.vfat sfdisk mkfs.ext4 debugfs mkfs.exfat arch-test; do
	command -v "$tool" >/dev/null || { echo "FAIL: $tool missing"; fail=1; }
done
[ "$(id -u)" != 0 ] || { echo "FAIL: running as root"; fail=1; }
# rootfs and apps chroot into armhf; binfmt_misc is the host's.
arch-test armhf >/dev/null 2>&1 || { echo "FAIL: armhf binaries do not run: install qemu-user-binfmt on the host (its qemu-arm entry needs the F flag)"; fail=1; }
# The test card's p2 is made with mkfs.ext4 -d <tarball>, which needs libarchive.
t=$(mktemp -d)
mkdir "$t/r"
echo x > "$t/r/f"
tar -C "$t/r" -cf "$t/r.tar" .
if ! mkfs.ext4 -q -d "$t/r.tar" "$t/fs" 8M 2>/dev/null || [ "$(debugfs -R 'cat /f' "$t/fs" 2>/dev/null)" != x ]; then
	echo "FAIL: mkfs.ext4 -d cannot read a tarball"; fail=1
fi
rm -rf "$t"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/container.sh`
Expected: `FAIL: mkfs.exfat missing`, `FAIL: arch-test missing`, `FAIL: armhf binaries do not run...`, and the
mkfs.ext4 tarball failure.

- [ ] **Step 2: Containerfile.** Add `arch-test e2fsprogs exfatprogs libarchive13t64` to the main `apt-get install`
  list (alphabetical position, same line style as the neighbours).

- [ ] **Step 3: build.sh.** Usage line and header comment list `uboot|kernel|initramfs|apps|rootfs|sdcard`. After
  `run()`:

```sh
# apps and rootfs run mmdebstrap --mode=root and chroot into armhf: root in a privileged container, armhf through the
# host's qemu-user-binfmt (binfmt_misc is not namespaced). Their scripts hand their output back to HOST_UID:HOST_GID.
root() {
	"$ENGINE" run --rm $it --privileged -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
		-v "$PWD:/work" -w /work "$IMAGE" "$@"
}
```

Cases (after `initramfs)`):
```sh
	apps) run scripts/fetch-apps.sh; root scripts/build-apps.sh ;;
	rootfs) root scripts/build-rootfs.sh ;;
```

- [ ] **Step 4: GREEN.**

Run: `./build.sh run tests/container.sh`
Expected: `PASS` (after the [person] host prerequisite from the execution notes).

- [ ] **Step 5: Commit.**

```bash
git add container/Containerfile build.sh tests/container.sh
git commit -m "Add a root container runner and armhf, ext4 and exFAT tools for the userspace stages"
```

### Task 4: Pinned app source trees

**Files:**
- Modify: `scripts/tree.sh` (usage, `case $name`, `fetch()`)
- Modify: `versions.env`
- Create: `scripts/fetch-apps.sh`
- Modify: `tests/tree.sh`

**Interfaces:**
- Produces: `scripts/tree.sh prep|export <app>` for `emulationstation es-theme-carbon snes9x2010 gpsp picodrive
  beetle-pce-fast pcsx_rearmed`; tree at `out/src/<app>`, patches in `apps/<app>/patches/`; versions
  `<APP>_GIT`/`<APP>_COMMIT` with the name upper-cased and `-` → `_`. `scripts/fetch-apps.sh` preps all seven.

- [ ] **Step 1: Failing test.** In `tests/tree.sh` change the mkdir line to
  `mkdir -p "$t/scripts" "$t/uboot/patches" "$t/kernel/patches" "$t/apps"` and insert before `echo PASS`:

```sh
# App trees are fetched by commit: prep checks out the pin even after upstream moved on.
git -C "$up" config uploadpack.allowAnySHA1InWant true
pin=$(git -C "$up" rev-parse v1)
echo tip > "$up/f"
git -C "$up" $id commit -qam tip
cat >> "$t/versions.env" <<EOF
GPSP_GIT=file://$up
GPSP_COMMIT=$pin
EOF
"$t/scripts/tree.sh" prep gpsp >/dev/null || fail "app tree prep failed"
[ "$(cat "$t/out/src/gpsp/f")" = a ] || fail "app tree not at its pin"
```

Run: `./build.sh run tests/tree.sh`
Expected: `FAIL: app tree prep failed`.

- [ ] **Step 2: tree.sh.** Usage comment and `usage()` become `prep|export u-boot|linux|<app in apps/>`. Case:

```sh
case $name in
	u-boot) patches=uboot/patches pin=$UBOOT_COMMIT ;;
	linux) patches=kernel/patches pin=$LINUX_SHA256 ;;
	emulationstation|es-theme-carbon|snes9x2010|gpsp|picodrive|beetle-pce-fast|pcsx_rearmed)
		patches=apps/$name/patches
		v=$(echo "$name" | tr 'a-z-' 'A-Z_')
		eval "url=\$${v}_GIT pin=\$${v}_COMMIT"
		;;
	*) usage ;;
esac
```

New branch in `fetch()`'s case, after `linux)`'s `;;`:
```sh
	*)
		git init -q "$src"
		git -C "$src" fetch -q --depth 1 "$url" "$pin"
		git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
		git -C "$src" submodule -q update --init --recursive
		;;
```

- [ ] **Step 3: versions.env.** Append:

```sh
# Apps (sub-project 3), fetched by commit.
EMULATIONSTATION_GIT=https://github.com/christianhaitian/EmulationStation-fcamod
EMULATIONSTATION_COMMIT=74498be31cd016af6a42d00310f876d7256eff52
ES_THEME_CARBON_GIT=https://github.com/RetroPie/es-theme-carbon
ES_THEME_CARBON_COMMIT=b09973e0b0c589cb11fe772c169a6ff5d588b390
SNES9X2010_GIT=https://github.com/libretro/snes9x2010
SNES9X2010_COMMIT=fe690dd321fa5a46b5234a2bde089d2518c62b0e
GPSP_GIT=https://github.com/libretro/gpsp
GPSP_COMMIT=5819380c2ffb0900219d700a382ee68c464ebb99
PICODRIVE_GIT=https://github.com/libretro/picodrive
PICODRIVE_COMMIT=1890c2932234c9d30f4cd3851d02228baae8f09e
BEETLE_PCE_FAST_GIT=https://github.com/libretro/beetle-pce-fast-libretro
BEETLE_PCE_FAST_COMMIT=3f946f277aef3aa99a95551618bbcd1dd2bda0d9
PCSX_REARMED_GIT=https://github.com/libretro/pcsx_rearmed
PCSX_REARMED_COMMIT=c8816799b50388e61cfe237fe2cdbb7d8175f20a
```

- [ ] **Step 4: scripts/fetch-apps.sh** (mode 755):

```sh
#!/bin/sh
# Fetches the pinned app trees into out/src with their patch series applied. Runs as the user in the build container.
set -eu
cd "$(dirname "$0")/.."
for a in emulationstation es-theme-carbon snes9x2010 gpsp picodrive beetle-pce-fast pcsx_rearmed; do
	scripts/tree.sh prep "$a"
done
```

- [ ] **Step 5: GREEN, then the real trees.**

Run: `./build.sh run tests/tree.sh && ./build.sh run scripts/fetch-apps.sh && ls out/src`
Expected: `PASS`; `out/src` lists the seven app trees beside `linux` and `u-boot`; each is at its pin
(`git -C out/src/gpsp rev-parse HEAD` = `GPSP_COMMIT`).

- [ ] **Step 6: Commit.**

```bash
git add scripts/tree.sh scripts/fetch-apps.sh versions.env tests/tree.sh
git commit -m "Fetch pinned ES, theme and libretro core trees"
```

### Task 5: ES patch series

**Files:**
- Modify (in `out/src/emulationstation`): `es-core/src/renderers/Renderer_GLES10.cpp:17`, `es-core/src/platform.cpp` (`queryBatteryRootPath`), `es-app/src/guis/GuiMenu.cpp:85`, `es-core/src/Settings.cpp:222`, `es-app/src/ApiSystem.cpp` (`setBrighness`)
- Create: `apps/emulationstation/patches/0001-*.patch` … `0005-*.patch` (by export)
- Create: `tests/es-patches.sh`

**Interfaces:**
- Consumes: `out/src/emulationstation` from Task 4.
- Produces: ES that builds without go2 headers, finds `/sys/class/power_supply/axp20x-battery`, drives the
  `Headphone` mixer, never sets the backlight below 20 % (level 2 of 10).

- [ ] **Step 1: Failing test.** `tests/es-patches.sh` (mode 755):

```sh
#!/bin/sh
# The ES tree carries the GA36 patches: no libgo2, the AXP battery, the Headphone mixer, a backlight floor and no
# ArkOS shell calls in the main menu.
# Run: ./build.sh run tests/es-patches.sh
set -eu
s=out/src/emulationstation
[ -d "$s" ] || { echo "FAIL: $s missing (./build.sh run scripts/fetch-apps.sh)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
grep -rqs '^#include <go2/' "$s/es-core/src" "$s/es-app/src" && bad "go2 include left"
grep -q 'find("battery")' "$s/es-core/src/platform.cpp" || bad "battery lookup does not match axp20x-battery"
grep -q 'mStringMap\["AudioDevice"\] = "Headphone";' "$s/es-core/src/Settings.cpp" || bad "AudioDevice default not Headphone"
grep -q 'current_volume\|/sys/class/power_supply/battery/capacity' "$s/es-app/src/guis/GuiMenu.cpp" && bad "menu status line shells out"
grep -q 'if (value < 20)' "$s/es-app/src/ApiSystem.cpp" || bad "no backlight floor"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/es-patches.sh`
Expected: five FAIL lines (the go2 one included).

- [ ] **Step 2: Patches, one commit each** (in `out/src/emulationstation`, `git -c user.name=Bepok -c
  user.email=wojtekjakubiszyn@gmail.com commit -am "<subject>"`):
  1. "Drop the unused libgo2 audio include": delete line 17 `#include <go2/audio.h>` of
     `es-core/src/renderers/Renderer_GLES10.cpp`.
  2. "Find batteries whose name contains battery": in `queryBatteryRootPath`, `find("/bat")` → `find("battery")`
     (`axp20x-battery` has no `/bat`).
  3. "Build the menu status line without shell calls": replace the `addEntry(_("BAT") ...` line with
     ```cpp
     	addEntry(_("BAT") + ": " + std::to_string(queryBatteryInformation(true).level) + "% | " + _("SND") + ": " + std::to_string(VolumeControl::getInstance()->getVolume()) + "% | " + _("BRT") + ": " + std::to_string(ApiSystem::getInstance()->getBrightnessLevel()) + "%", false, [this] {  });
     ```
     (`VolumeControl.h` and `platform.h` are already included; the device has no Wi-Fi.)
  4. "Use the Headphone mixer for volume": in `Settings.cpp`, the non-RPI `mStringMap["AudioDevice"] = "Master";` →
     `"Headphone"` (the sun8i codec has no Master control).
  5. "Keep the backlight at 20 % or more": in `ApiSystem::setBrighness`,
     ```cpp
     	// Backlight level 1 of 10 looks off on the GA36 panel.
     	if (value < 20)
     		value = 20;
     ```
     replacing `if (value < 1) value = 1;`.

- [ ] **Step 3: Export and GREEN.**

Run: `./build.sh run scripts/tree.sh export emulationstation && ./build.sh run tests/es-patches.sh && ls apps/emulationstation/patches`
Expected: `PASS`; five `000N-*.patch` files.

- [ ] **Step 4: Commit.**

```bash
git add apps/emulationstation/patches tests/es-patches.sh
git commit -m "Patch ES fcamod for the GA36: no libgo2, AXP battery, Headphone mixer, backlight floor"
```

### Task 6: Build ES and the cores in a throwaway armhf chroot

**Files:**
- Create: `apps/build-deps.list`, `apps/build-in-chroot.sh`, `scripts/build-apps.sh`, `tests/apps.sh`

**Interfaces:**
- Consumes: `root` runner (Task 3), app trees (Tasks 4, 5).
- Produces: `out/apps/usr/local/lib/emulationstation/{emulationstation,resources/}`,
  `out/apps/usr/local/lib/libretro/{snes9x2010,gpsp,picodrive,mednafen_pce_fast,pcsx_rearmed}_libretro.so`,
  `out/apps/runtime-deps.list` (one Debian package name per line, user-owned).

- [ ] **Step 1: Failing test.** `tests/apps.sh` (mode 755):

```sh
#!/bin/sh
# out/apps holds armhf hard-float ES and cores built against trixie, plus the packages they need at run time.
# Run: ./build.sh run tests/apps.sh
set -eu
a=out/apps
[ -d "$a/usr/local" ] || { echo "FAIL: $a missing (./build.sh apps)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
arm() { readelf -h "$1" | grep -q 'Machine: *ARM$' && readelf -A "$1" | grep -q 'Tag_ABI_VFP_args: VFP registers'; }
es=$a/usr/local/lib/emulationstation/emulationstation
if [ -f "$es" ]; then
	arm "$es" || bad "ES is not armhf"
	readelf -d "$es" | grep -q 'libgo2' && bad "ES links libgo2"
	readelf -d "$es" | grep -q 'libGLESv1_CM' || bad "ES does not link GLES1"
else
	bad "ES missing"
fi
[ -d "$a/usr/local/lib/emulationstation/resources" ] || bad "ES resources missing"
for c in snes9x2010 gpsp picodrive mednafen_pce_fast pcsx_rearmed; do
	so=$a/usr/local/lib/libretro/${c}_libretro.so
	[ -f "$so" ] || { bad "$c missing"; continue; }
	arm "$so" || bad "$c is not armhf"
	readelf --dyn-syms "$so" | grep -qw retro_api_version || bad "$c exports no retro_api_version"
done
for p in libsdl2-2.0-0 libfreeimage3 libgles1; do
	grep -qx "$p" "$a/runtime-deps.list" || bad "runtime-deps.list lacks $p"
done
grep -q -- '-dev$' "$a/runtime-deps.list" && bad "runtime-deps.list names a -dev package"
[ "$(stat -c %u "$a/runtime-deps.list")" = "$(id -u)" ] || bad "out/apps not handed back to the user"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/apps.sh`
Expected: `FAIL: out/apps missing (./build.sh apps)`.

- [ ] **Step 2: apps/build-deps.list**

```
# Build dependencies of ES fcamod and the libretro cores (scripts/build-apps.sh). Never installed in the rootfs.
build-essential
cmake
git
pkgconf
libfreeimage-dev
libfreetype-dev
libcurl4-openssl-dev
libasound2-dev
libsdl2-dev
libsdl2-mixer-dev
rapidjson-dev
libvlc-dev
libvlccore-dev
libgles-dev
libdrm-dev
libeigen3-dev
zlib1g-dev
```

- [ ] **Step 3: apps/build-in-chroot.sh** (mode 755):

```sh
#!/bin/sh
# Runs inside the throwaway armhf chroot of scripts/build-apps.sh. Builds into /stage and writes the Debian packages
# the results link at run time to /stage/runtime-deps.list.
set -eu
j=$(nproc)
es=/stage/usr/local/lib/emulationstation
lr=/stage/usr/local/lib/libretro
mkdir -p "$es" "$lr"

cmake -S /src/emulationstation -B /tmp/es -DGLES=ON -DCMAKE_BUILD_TYPE=Release
make -C /tmp/es -j"$j"
# ES writes its binary into the source directory and looks for resources/ beside it.
cp /src/emulationstation/emulationstation "$es/"
cp -r /src/emulationstation/resources "$es/"

core() { # tree makefile output
	make -C "/src/$1" -f "$2" platform=classic_armv7_a7 -j"$j"
	cp "/src/$1/$3" "$lr/"
}
core snes9x2010 Makefile.libretro snes9x2010_libretro.so
core gpsp Makefile gpsp_libretro.so
core picodrive Makefile.libretro picodrive_libretro.so
core beetle-pce-fast Makefile mednafen_pce_fast_libretro.so
core pcsx_rearmed Makefile.libretro pcsx_rearmed_libretro.so

for f in "$es/emulationstation" "$lr"/*.so; do ldd "$f"; done | awk '/=> \//{print $3}' | sort -u > /tmp/libs
while read -r lib; do
	dpkg -S "$(realpath "$lib")" 2>/dev/null || dpkg -S "$lib"
done < /tmp/libs > /tmp/owners
cut -d: -f1 /tmp/owners | sort -u > /stage/runtime-deps.list
```

- [ ] **Step 4: scripts/build-apps.sh** (mode 755):

```sh
#!/bin/sh
# Builds ES and the libretro cores for armhf in a throwaway trixie chroot, so build dependencies stay out of the
# release rootfs. Output: out/apps/usr/local and out/apps/runtime-deps.list.
# Runs as root in the build container (./build.sh apps); armhf runs through the host's qemu-user-binfmt.
set -eu
o=out/apps
rm -rf "$o"
mkdir -p "$o"
trap 'chown -R "$HOST_UID:$HOST_GID" "$o"' EXIT
mmdebstrap --mode=root --variant=apt --architectures=armhf \
	--include="$(grep -v '^#' apps/build-deps.list | grep . | paste -sd, -)" \
	--customize-hook='mkdir -p "$1/src"' \
	--customize-hook='copy-in out/src/emulationstation out/src/snes9x2010 out/src/gpsp out/src/picodrive out/src/beetle-pce-fast out/src/pcsx_rearmed apps/build-in-chroot.sh /src' \
	--customize-hook='chroot "$1" sh /src/build-in-chroot.sh' \
	--customize-hook='sync-out /stage out/apps' \
	trixie /dev/null
```

- [ ] **Step 5: Build and GREEN.** The build runs under qemu-user and takes a long time; run it in the background and
  wait for its completion notice.

Run: `./build.sh apps > "$W/apps.log" 2>&1; tail -5 "$W/apps.log"; ./build.sh run tests/apps.sh`
Expected: `PASS`. A compile error from a missing header: add the owning `-dev` package to `apps/build-deps.list`
(ledger ruling); a source error in ES: one more ES patch via Task 5's commit-and-export flow, with a matching
`tests/es-patches.sh` check written first.

- [ ] **Step 6: Commit.**

```bash
git add apps/build-deps.list apps/build-in-chroot.sh scripts/build-apps.sh tests/apps.sh
git commit -m "Build ES and the libretro cores in a throwaway armhf chroot"
```

### Task 7: Release rootfs

**Files:**
- Create: `rootfs/packages.list`, `rootfs/customize.sh`, `scripts/build-rootfs.sh`, `tests/rootfs.sh`
- Create (overlay): `rootfs/overlay/etc/hostname`, `etc/fstab`, `etc/sudoers.d/ga36`,
  `etc/systemd/system/emulationstation.service`, `etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf`,
  `etc/systemd/zram-generator.conf`, `etc/emulationstation/es_systems.cfg`, `var/lib/alsa/asound.state`

**Interfaces:**
- Consumes: `out/apps` (Task 6), `out/src/es-theme-carbon` (Task 4), Task 1 kernel for the ALSA capture.
- Produces: `out/rootfs/rootfs.tar` (mmdebstrap tar, members `./path`, user-owned file). Root filesystem
  `PARTUUID=47413336-02` (Task 8's card uses that disk id). User `ga36` uid/gid 1000. ES at
  `/usr/local/lib/emulationstation/emulationstation`. `customize.sh` ends with one `systemctl enable` line that later
  tasks extend. `es_systems.cfg` system paths are `/roms/<name>` (Task 9 creates them).

- [ ] **Step 1: Failing test.** `tests/rootfs.sh` (mode 755):

```sh
#!/bin/sh
# The release rootfs tarball: packages, apps, overlay, user, services, mixer defaults, no build tools.
# Run: ./build.sh run tests/rootfs.sh
set -eu
r=out/rootfs/rootfs.tar
[ -f "$r" ] || { echo "FAIL: $r missing (./build.sh rootfs)"; exit 1; }
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
tar --numeric-owner -tvf "$r" > "$t/list"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
has() { awk -v p="./$1" '$6 == p {f=1} END {exit !f}' "$t/list"; }
owner() { awk -v p="./$1" '$6 == p {print $1, $2}' "$t/list"; }
file() { tar -xOf "$r" "./$1"; }

for p in usr/local/lib/emulationstation/emulationstation usr/local/lib/libretro/pcsx_rearmed_libretro.so \
	usr/bin/retroarch usr/lib/arm-linux-gnueabihf/libretro/nestopia_libretro.so \
	usr/lib/arm-linux-gnueabihf/libretro/gambatte_libretro.so etc/emulationstation/themes/carbon/readme.txt \
	etc/systemd/system/multi-user.target.wants/emulationstation.service \
	etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service var/log/journal/ home/ga36/ roms/; do
	has "$p" || bad "$p missing"
done
for p in usr/bin/gcc usr/bin/cmake etc/emulationstation/themes/carbon/.git/; do
	has "$p" && bad "$p present"
done
# The Debian RetroArch build must carry the KMS/GBM context (video_driver gl without X11).
file usr/bin/retroarch > "$t/retroarch" 2>/dev/null || true
readelf -d "$t/retroarch" | grep -q 'libgbm\.so\.1' || bad "retroarch does not link libgbm"
[ "$(owner usr/local/lib/emulationstation/emulationstation)" = "-rwxr-xr-x 0/0" ] || bad "ES not root-owned 755"
[ "$(owner etc/sudoers.d/ga36)" = "-r--r----- 0/0" ] || bad "sudoers drop-in not root 0440"
[ "$(owner home/ga36/ | cut -d' ' -f2)" = 1000/1000 ] || bad "home not owned by ga36"
for d in ./ etc/ usr/ usr/local/ var/; do
	[ "$(owner "${d#./}")" = "drwxr-xr-x 0/0" ] || bad "$d not root 755"
done
for g in video render input audio; do
	file etc/group | grep -q "^$g:.*[:,]ga36\(,\|$\)" || bad "ga36 not in $g"
done
file etc/fstab | grep -q '^PARTUUID=47413336-02 / ext4 ' || bad "fstab root"
file etc/systemd/zram-generator.conf | grep -qx 'zram-size = 256' || bad "zram size"
a=$(file var/lib/alsa/asound.state)
echo "$a" | grep -A4 "name 'AIF1 DA0 Playback Volume'" | grep -q 'value.0 160' || bad "AIF1 DA0 not 0 dB"
echo "$a" | grep -A4 "name 'AIF1 DA0 Stereo Playback Route'" | grep -q "value.0 'Reverse Stereo'" || bad "stereo not reversed"
echo "$a" | grep -A4 "name 'DAC Playback Volume'" | grep -q 'value.0 160' || bad "DAC not 0 dB"
echo "$a" | grep -A4 "name 'Headphone Playback Volume'" | grep -q 'value 50' || bad "Headphone default not 50"
es=$(file etc/emulationstation/es_systems.cfg)
for c in $(echo "$es" | sed -n 's:.*-L \([^ ]*\) .*:\1:p'); do
	has "${c#/}" || bad "es_systems core $c missing"
done
[ "$(echo "$es" | grep -c '<system>')" = 10 ] || bad "es_systems does not list 10 systems"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/rootfs.sh`
Expected: `FAIL: out/rootfs/rootfs.tar missing (./build.sh rootfs)`.

- [ ] **Step 2: ALSA defaults from the device.** FEL-boot the Task 1 kernel and capture the state the codec really
  has (no handwritten control ids):

```bash
scripts/fel-boot.sh kernel
mkdir -p rootfs/overlay/var/lib/alsa
TIMEOUT=30 scripts/board-run.sh "amixer -q sset 'AIF1 DA0' 160; amixer -q sset 'AIF1 DA0 Stereo' 'Reverse Stereo'; amixer -q sset DAC 160; amixer -q sset 'AIF1 Slot 0 Digital DAC' on; amixer -q sset 'Headphone Source' DAC; amixer -q sset Headphone 50 unmute; alsactl -f /tmp/a store; cat /tmp/a" | tr -d '\r' > rootfs/overlay/var/lib/alsa/asound.state
grep -c '^control\.' rootfs/overlay/var/lib/alsa/asound.state
```

Expected: a count above 10 and the file starts with `state.`. (Headphone 50 is the boot default; 63, the cap, stays
reachable from the ES volume menu.)

- [ ] **Step 3: rootfs/packages.list**

```
# Release rootfs packages (scripts/build-rootfs.sh) on top of mmdebstrap minbase and out/apps/runtime-deps.list.
systemd
systemd-sysv
udev
dbus
libpam-systemd
sudo
alsa-utils
libgl1-mesa-dri
libegl-mesa0
libgbm1
libgles1
libgles2
retroarch
libretro-nestopia
libretro-gambatte
exfatprogs
fdisk
systemd-zram-generator
procps
less
```

- [ ] **Step 4: Overlay files.**

`rootfs/overlay/etc/hostname`:
```
ga36
```

`rootfs/overlay/etc/fstab`:
```
PARTUUID=47413336-02 / ext4 defaults,noatime 0 1
```

`rootfs/overlay/etc/sudoers.d/ga36`:
```
# ES runs `sudo shutdown -h now` and `sudo shutdown -r now` from its quit menu.
ga36 ALL=(root) NOPASSWD: /usr/sbin/shutdown
```

`rootfs/overlay/etc/systemd/system/emulationstation.service`:
```ini
[Unit]
Description=EmulationStation on tty1 for user ga36
After=systemd-user-sessions.service
Conflicts=getty@tty1.service

[Service]
User=ga36
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
StandardError=journal
WorkingDirectory=/home/ga36
ExecStart=/usr/local/lib/emulationstation/emulationstation
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

`rootfs/overlay/etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf`:
```ini
# Root shell on the USB console for logs and testers; the device has no network.
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --keep-baud 115200 %I $TERM
```

`rootfs/overlay/etc/systemd/zram-generator.conf`:
```ini
[zram0]
zram-size = 256
```

`rootfs/overlay/etc/emulationstation/es_systems.cfg` (10 systems; core paths are absolute, ROM folders under `/roms`):
```xml
<?xml version="1.0"?>
<systemList>
	<system>
		<name>nes</name>
		<fullname>Nintendo Entertainment System</fullname>
		<path>/roms/nes</path>
		<extension>.nes .NES .zip .ZIP</extension>
		<command>retroarch -L /usr/lib/arm-linux-gnueabihf/libretro/nestopia_libretro.so %ROM%</command>
		<platform>nes</platform>
		<theme>nes</theme>
	</system>
	<system>
		<name>gb</name>
		<fullname>Game Boy</fullname>
		<path>/roms/gb</path>
		<extension>.gb .GB .zip .ZIP</extension>
		<command>retroarch -L /usr/lib/arm-linux-gnueabihf/libretro/gambatte_libretro.so %ROM%</command>
		<platform>gb</platform>
		<theme>gb</theme>
	</system>
	<system>
		<name>gbc</name>
		<fullname>Game Boy Color</fullname>
		<path>/roms/gbc</path>
		<extension>.gbc .GBC .zip .ZIP</extension>
		<command>retroarch -L /usr/lib/arm-linux-gnueabihf/libretro/gambatte_libretro.so %ROM%</command>
		<platform>gbc</platform>
		<theme>gbc</theme>
	</system>
	<system>
		<name>snes</name>
		<fullname>Super Nintendo</fullname>
		<path>/roms/snes</path>
		<extension>.smc .SMC .sfc .SFC .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/snes9x2010_libretro.so %ROM%</command>
		<platform>snes</platform>
		<theme>snes</theme>
	</system>
	<system>
		<name>gba</name>
		<fullname>Game Boy Advance</fullname>
		<path>/roms/gba</path>
		<extension>.gba .GBA .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/gpsp_libretro.so %ROM%</command>
		<platform>gba</platform>
		<theme>gba</theme>
	</system>
	<system>
		<name>megadrive</name>
		<fullname>Mega Drive</fullname>
		<path>/roms/megadrive</path>
		<extension>.md .MD .gen .GEN .smd .SMD .bin .BIN .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/picodrive_libretro.so %ROM%</command>
		<platform>megadrive</platform>
		<theme>megadrive</theme>
	</system>
	<system>
		<name>mastersystem</name>
		<fullname>Master System</fullname>
		<path>/roms/mastersystem</path>
		<extension>.sms .SMS .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/picodrive_libretro.so %ROM%</command>
		<platform>mastersystem</platform>
		<theme>mastersystem</theme>
	</system>
	<system>
		<name>gamegear</name>
		<fullname>Game Gear</fullname>
		<path>/roms/gamegear</path>
		<extension>.gg .GG .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/picodrive_libretro.so %ROM%</command>
		<platform>gamegear</platform>
		<theme>gamegear</theme>
	</system>
	<system>
		<name>pcengine</name>
		<fullname>PC Engine</fullname>
		<path>/roms/pcengine</path>
		<extension>.pce .PCE .zip .ZIP</extension>
		<command>retroarch -L /usr/local/lib/libretro/mednafen_pce_fast_libretro.so %ROM%</command>
		<platform>pcengine</platform>
		<theme>pcengine</theme>
	</system>
	<system>
		<name>psx</name>
		<fullname>PlayStation</fullname>
		<path>/roms/psx</path>
		<extension>.cue .CUE .chd .CHD .pbp .PBP .m3u .M3U</extension>
		<command>retroarch -L /usr/local/lib/libretro/pcsx_rearmed_libretro.so %ROM%</command>
		<platform>psx</platform>
		<theme>psx</theme>
	</system>
</systemList>
```

- [ ] **Step 5: rootfs/customize.sh** (mode 755):

```sh
#!/bin/sh
# mmdebstrap customize hook of scripts/build-rootfs.sh; $1 is the new root. Runs as root in the build container.
set -eu
r=$1
# cp -r, not cp -a: existing directories (/ included) keep their owner and mode, new files are root's with the
# source mode minus the umask. cp -a would put the checkout's uid and mode on /, /etc and /usr.
cp -r out/apps/usr/local/. "$r/usr/local/"
cp -r rootfs/overlay/. "$r/"
mkdir -p "$r/etc/emulationstation/themes"
cp -r out/src/es-theme-carbon "$r/etc/emulationstation/themes/carbon"
rm -rf "$r/etc/emulationstation/themes/carbon/.git"
chmod 0440 "$r/etc/sudoers.d/ga36"
chroot "$r" useradd -m -u 1000 -U -G video,render,input,audio -s /bin/bash ga36
mkdir -p "$r/roms" "$r/var/log/journal"
chown 1000:1000 "$r/roms"
chroot "$r" systemctl enable emulationstation.service serial-getty@ttyGS0.service
```

- [ ] **Step 6: scripts/build-rootfs.sh** (mode 755):

```sh
#!/bin/sh
# Release root filesystem: Debian trixie armhf minbase, rootfs/packages.list, the run-time packages of out/apps, and
# rootfs/customize.sh. Output: out/rootfs/rootfs.tar.
# Runs as root in the build container (./build.sh rootfs); armhf runs through the host's qemu-user-binfmt.
set -eu
o=out/rootfs
[ -f out/apps/runtime-deps.list ] || { echo "out/apps missing: ./build.sh apps" >&2; exit 1; }
rm -rf "$o"
mkdir -p "$o"
trap 'chown -R "$HOST_UID:$HOST_GID" "$o"' EXIT
mmdebstrap --mode=root --variant=minbase --architectures=armhf \
	--include="$(cat rootfs/packages.list out/apps/runtime-deps.list | grep -v '^#' | grep . | sort -u | paste -sd, -)" \
	--customize-hook='sh rootfs/customize.sh "$1"' \
	trixie "$o/rootfs.tar"
```

- [ ] **Step 7: GREEN.**

Run: `./build.sh rootfs > "$W/rootfs.log" 2>&1; tail -3 "$W/rootfs.log"; ./build.sh run tests/rootfs.sh`
Expected: `PASS`. (If the test FAILs on `readme.txt`, check the theme's licence file name with
`ls out/src/es-theme-carbon`; the check must name the file that carries the CC BY-NC-SA text.)

- [ ] **Step 8: Commit.**

```bash
git add rootfs scripts/build-rootfs.sh tests/rootfs.sh
git commit -m "Build the release rootfs with ES, RetroArch, cores and the GA36 defaults"
```

### Task 8: Test SD card with the rootfs; first boot to ES

**Files:**
- Modify: `scripts/make-test-sdcard.sh`, `tests/sdcard.sh`
- Create (overlay): `rootfs/overlay/etc/emulationstation/es_input.cfg` (captured on the device)

**Interfaces:**
- Consumes: `out/rootfs/rootfs.tar`, `out/kernel/*`, `out/u-boot/u-boot-sunxi-with-spl.bin`.
- Produces: `out/sdcard/ga36-test.img`: disk id `0x47413336`; p1 FAT32 at sector 32768, 524288 sectors; p2 ext4
  `ROOTFS` at sector 557056, 6291456 sectors (3 GiB); p3 starts at sector 6848512 (Task 9).

- [ ] **Step 1: Failing test.** Replace `tests/sdcard.sh`:

```sh
#!/bin/sh
# Test SD image layout: U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files, p2 ext4 ROOTFS (3 GiB) right after.
# Run: ./build.sh run tests/sdcard.sh
set -eu
img=out/sdcard/ga36-test.img
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -f "$img" ] || { echo "FAIL: $img missing (./build.sh sdcard)"; exit 1; }
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d=$(sfdisk -d "$img")
echo "$d" | grep -q '^label-id: 0x47413336$' || bad "disk id not 0x47413336"
echo "$d" | grep -q 'start= *32768, size= *524288, type=c, bootable' || bad "p1 not at 16 MiB / 256 MiB / FAT32 LBA / bootable"
echo "$d" | grep -q 'start= *557056, size= *6291456, type=83' || bad "p2 not at 272 MiB / 3 GiB / Linux"
dd if="$img" bs=1024 skip=8 status=none | head -c "$(stat -c %s "$u")" | cmp -s - "$u" || bad "U-Boot not at 8 KiB"
for f in zImage sun8i-a33-gameconsole-r36s-ga36.dtb; do
	mdir -b -i "$img@@16M" "::/$f" >/dev/null 2>&1 || bad "$f missing on p1"
done
x=$(mtype -i "$img@@16M" ::/extlinux/extlinux.conf)
echo "$x" | grep -q 'fdt /sun8i-a33-gameconsole-r36s-ga36.dtb' || bad "extlinux.conf fdt"
echo "$x" | grep -q 'append .*console=ttyGS0.* root=PARTUUID=47413336-02 rootwait' || bad "extlinux.conf root"
echo "$x" | grep -q initrd && bad "extlinux.conf still loads an initrd"
dd if="$img" of="$t/p2" bs=1M skip=272 count=3072 conv=sparse status=none
[ "$(dumpe2fs -h "$t/p2" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = ROOTFS ] || bad "p2 not ext4 ROOTFS"
debugfs -R 'stat /usr/local/lib/emulationstation/emulationstation' "$t/p2" 2>/dev/null | grep -q 'User: *0' || bad "ES missing on p2"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh sdcard && ./build.sh run tests/sdcard.sh`
Expected: FAIL lines for disk id, p2 layout, extlinux.conf root, initrd, `p2 not ext4 ROOTFS` and `ES missing on p2`.

- [ ] **Step 2: scripts/make-test-sdcard.sh** (replace):

```sh
#!/bin/sh
# Test SD card image: U-Boot at 8 KiB, p1 FAT32 BOOT (kernel, DTB, extlinux.conf), p2 ext4 ROOTFS from
# out/rootfs/rootfs.tar. p3 (ROMS) is made on the device at first boot.
# Test-only; the release image is built by sub-project 4. Rootless, no loop mounts. Runs inside the build container.
set -eu
o=out/sdcard
img=$o/ga36-test.img
p1=$o/p1.vfat
p2=$o/p2.ext4
mkdir -p "$o"
rm -f "$img" "$p1" "$p2"

# root=PARTUUID matches label-id below and rootfs/overlay/etc/fstab.
cat > "$o/extlinux.conf" <<'EOF'
label ga36-test
	kernel /zImage
	fdt /sun8i-a33-gameconsole-r36s-ga36.dtb
	append console=tty0 console=ttyGS0,115200 panic=5 root=PARTUUID=47413336-02 rootwait
EOF
mkfs.vfat -F 32 -n BOOT -C "$p1" $((256 * 1024)) >/dev/null
mmd -i "$p1" ::/extlinux
mcopy -i "$p1" "$o/extlinux.conf" ::/extlinux/
mcopy -i "$p1" out/kernel/zImage out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb ::/
mkfs.ext4 -q -L ROOTFS -d out/rootfs/rootfs.tar "$p2" 3G

# p2 is a fixed 3 GiB so p3 always starts at sector 6848512 (spec section 5).
truncate -s $(( (16 + 256 + 3072) * 1024 * 1024 )) "$img"
sfdisk -q "$img" <<'EOF'
label: dos
label-id: 0x47413336
start=32768, size=524288, type=c, bootable
start=557056, size=6291456, type=83
EOF
dd if=out/u-boot/u-boot-sunxi-with-spl.bin of="$img" bs=1024 seek=8 conv=notrunc status=none
dd if="$p1" of="$img" bs=1M seek=16 conv=notrunc status=none
dd if="$p2" of="$img" bs=1M seek=272 conv=notrunc,sparse status=none
rm "$p1" "$p2" "$o/extlinux.conf"
```

- [ ] **Step 3: GREEN.**

Run: `./build.sh sdcard && ./build.sh run tests/sdcard.sh`
Expected: `PASS`.

- [ ] **Step 4: Device: first boot [person].** One message: write the card (execution notes), insert, press the
  power key > 1 s, start a stopwatch, stop it when ES draws its first screen; ES then asks to configure input: hold
  any button, then map A = right face button (EAST), B = bottom (SOUTH), X = top (NORTH), Y = left (WEST), D-pad,
  L1/R1/L2/R2, Start, Select, L3/R3, Hotkey = FN; skip the analog axes. Report the stopwatch time, whether the
  picture looks right, and whether the ES main menu status line shows `BAT: NN%` with a number.

```bash
TIMEOUT=30 scripts/board-run.sh 'systemctl is-system-running; systemctl show emulationstation -p ActiveState -p NRestarts; systemd-analyze; journalctl -b -u emulationstation --no-pager | tail -5'
```

Expected: `running` (or `degraded` with only `ga36-roms`-free units failing: list them with
`systemctl --failed`, each needs a fix or a ruling), `ActiveState=active`, `NRestarts=0`, a `systemd-analyze` total.
Record the stopwatch and `systemd-analyze` numbers in the ledger for Task 12.

- [ ] **Step 5: Capture the input config.**

```bash
scripts/board-run.sh 'cat /home/ga36/.emulationstation/es_input.cfg' | tr -d '\r' > rootfs/overlay/etc/emulationstation/es_input.cfg
grep -c '<input ' rootfs/overlay/etc/emulationstation/es_input.cfg
grep -o 'deviceName="[^"]*"' rootfs/overlay/etc/emulationstation/es_input.cfg
```

Expected: a count ≥ 17 and `deviceName="gpio-keys"`. Add to `tests/rootfs.sh`'s first `for p in` list:
`etc/emulationstation/es_input.cfg`.

- [ ] **Step 6: Rebuild, recheck, commit.**

Run: `./build.sh rootfs > "$W/rootfs.log" 2>&1; ./build.sh run tests/rootfs.sh && ./build.sh sdcard && ./build.sh run tests/sdcard.sh`
Expected: `PASS` twice.

```bash
git add scripts/make-test-sdcard.sh tests/sdcard.sh tests/rootfs.sh rootfs/overlay/etc/emulationstation/es_input.cfg
git commit -m "Put the rootfs on the test card and ship the GA36 ES input config"
```

### Task 9: First boot creates or restores the ROMS partition

**Files:**
- Create: `rootfs/overlay/usr/local/sbin/ga36-roms-part`, `rootfs/overlay/usr/local/sbin/ga36-roms-dirs`,
  `rootfs/overlay/etc/systemd/system/ga36-roms.service`, `tests/roms-part.sh`
- Modify: `rootfs/overlay/etc/fstab`, `rootfs/overlay/etc/systemd/system/emulationstation.service` (`After=`),
  `rootfs/customize.sh` (enable line), `tests/rootfs.sh`

**Interfaces:**
- Consumes: card layout of Task 8 (p3 start 6848512), `es_systems.cfg` `<path>/roms/<name></path>`.
- Produces: `ga36-roms-part DISK PART` (exit 0 on create, restore, already present or too small; prints one line
  saying which); `ga36-roms-dirs ES_SYSTEMS_CFG ROMS_DIR`; `/roms` mounted from `LABEL=ROMS`, owned by uid 1000.

- [ ] **Step 1: Failing test.** `tests/roms-part.sh` (mode 755):

```sh
#!/bin/sh
# ga36-roms-part creates p3 on free space, restores the entry over existing exFAT data without formatting, leaves an
# existing p3 alone and skips a card too small. ga36-roms-dirs makes one folder per es_systems.cfg path.
# Run: ./build.sh run tests/roms-part.sh
set -eu
s=rootfs/overlay/usr/local/sbin
start=6848512
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
# A card as the test image leaves it, plus $1 MiB of free space after p2.
card() {
	rm -f "$t/d"
	truncate -s $(( (3344 + $1) * 1024 * 1024 )) "$t/d"
	printf 'label: dos\nstart=32768, size=524288, type=c\nstart=557056, size=6291456, type=83\n' | sfdisk -q "$t/d"
}
p3() { sfdisk -d "$t/d" | grep -q "start= *$start, .*type=7"; }
sig() { dd if="$1" bs=1 skip=$(( ${2:-0} + 3 )) count=8 status=none; }

# fresh: p3 appended and formatted.
card 1100
rm -f "$t/p"; truncate -s 64M "$t/p"
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "fresh: exit status"
p3 || bad "fresh: no p3 entry"
[ "$(sig "$t/p")" = "EXFAT   " ] || bad "fresh: p3 not formatted"
echo "$out" | grep -q created || bad "fresh: says '$out'"

# restore: exFAT already at the p3 offset, entry missing (a reflash). Entry back, data untouched.
card 1100
rm -f "$t/x"; truncate -s 64M "$t/x"
mkfs.exfat -L ROMS "$t/x" >/dev/null
dd if="$t/x" of="$t/d" bs=512 seek=$start conv=notrunc status=none
[ "$(sig "$t/d" $((start * 512)))" = "EXFAT   " ] || bad "restore: setup did not place exFAT at the offset"
rm -f "$t/p"; printf keep > "$t/p"; truncate -s 64M "$t/p"
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "restore: exit status"
p3 || bad "restore: no p3 entry"
[ "$(head -c 4 "$t/p")" = keep ] || bad "restore: formatted over existing data"
echo "$out" | grep -q restored || bad "restore: says '$out'"

# present: second run changes nothing.
before=$(sfdisk -d "$t/d")
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "present: exit status"
[ "$(sfdisk -d "$t/d")" = "$before" ] || bad "present: table changed"
[ "$(head -c 4 "$t/p")" = keep ] || bad "present: data touched"

# too small: under 1 GiB free, no p3, still exit 0.
card 100
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "small: exit status"
p3 && bad "small: p3 created"
echo "$out" | grep -q 'too small' || bad "small: says '$out'"

# dirs: one folder per es_systems.cfg path plus bios and saves.
mkdir "$t/roms"
"$s/ga36-roms-dirs" rootfs/overlay/etc/emulationstation/es_systems.cfg "$t/roms"
for d in nes gb gbc snes gba megadrive mastersystem gamegear pcengine psx bios saves; do
	[ -d "$t/roms/$d" ] || bad "dirs: $d missing"
done
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/roms-part.sh`
Expected: fails (`ga36-roms-part: not found` reported as `fresh: exit status` and the rest).

- [ ] **Step 2: rootfs/overlay/usr/local/sbin/ga36-roms-part** (mode 755):

```sh
#!/bin/sh
# Usage: ga36-roms-part DISK PART
# Makes p3 (ROMS, exFAT) on DISK from the fixed offset to the end. When an exFAT filesystem is already at that offset
# (a reflash drops the partition entry, not the data) it only restores the entry and never formats. Does nothing when
# p3 exists or the card has less than 1 GiB left.
set -eu
disk=$1 part=$2
start=6848512 # (16 + 256 + 3072) MiB in 512-byte sectors: the end of p2 in every release
sfdisk -d "$disk" | grep -q "start= *$start," && { echo "ROMS partition present"; exit 0; }
sectors=$(sfdisk -l "$disk" | sed -n '1s/.*, \([0-9]*\) sectors$/\1/p')
if [ "$sectors" -lt $((start + 2097152)) ]; then
	echo "card too small for a ROMS partition"
	exit 0
fi
sig=$(dd if="$disk" bs=512 skip=$start count=1 status=none | dd bs=1 skip=3 count=8 status=none)
echo "start=$start, type=7" | sfdisk -q --no-reread --append "$disk"
i=0
until [ -e "$part" ]; do
	i=$((i + 1))
	[ $i -le 50 ] || { echo "$part did not appear" >&2; exit 1; }
	sleep 0.2
done
if [ "$sig" = "EXFAT   " ]; then
	echo "ROMS partition entry restored"
else
	mkfs.exfat -L ROMS "$part" >/dev/null
	echo "ROMS partition created"
fi
```

- [ ] **Step 3: rootfs/overlay/usr/local/sbin/ga36-roms-dirs** (mode 755):

```sh
#!/bin/sh
# Usage: ga36-roms-dirs ES_SYSTEMS_CFG ROMS_DIR
# Creates the folder each es_systems.cfg <path> under /roms points at, plus bios and saves for RetroArch.
set -eu
cd "$2"
mkdir -p bios saves $(sed -n 's:.*<path>/roms/\(.*\)</path>.*:\1:p' "$1")
```

- [ ] **Step 4: GREEN (container).**

Run: `./build.sh run tests/roms-part.sh`
Expected: `PASS`.

- [ ] **Step 5: Unit, fstab, ordering.**

`rootfs/overlay/etc/systemd/system/ga36-roms.service`:
```ini
[Unit]
Description=Create or restore the ROMS partition and its folders
Before=emulationstation.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/ga36-roms-part /dev/mmcblk0 /dev/mmcblk0p3
ExecStart=/bin/mount /roms
ExecStart=/usr/local/sbin/ga36-roms-dirs /etc/emulationstation/es_systems.cfg /roms

[Install]
WantedBy=multi-user.target
```

Append to `rootfs/overlay/etc/fstab`:
```
LABEL=ROMS /roms exfat noauto,uid=1000,gid=1000 0 0
```

`emulationstation.service`: `After=systemd-user-sessions.service ga36-roms.service`.
`rootfs/customize.sh` enable line: add `ga36-roms.service`.
`tests/rootfs.sh`: add `etc/systemd/system/multi-user.target.wants/ga36-roms.service` and
`usr/local/sbin/ga36-roms-part` to the first `has` list, and
`file etc/fstab | grep -q '^LABEL=ROMS /roms exfat ' || bad "fstab ROMS"`.

- [ ] **Step 6: Build and container GREEN.**

Run: `./build.sh rootfs > "$W/rootfs.log" 2>&1; ./build.sh run tests/rootfs.sh && ./build.sh sdcard && ./build.sh run tests/sdcard.sh`
Expected: `PASS` twice.

- [ ] **Step 7: Device [person].** One message: write the card, insert, power on, wait for ES (no ROMs anywhere).

```bash
sleep 60; TIMEOUT=30 scripts/board-run.sh 'journalctl -b -u ga36-roms --no-pager | grep ROMS; sfdisk -d /dev/mmcblk0 | tail -1; findmnt -n -o SOURCE,FSTYPE /roms; ls /roms; systemctl show emulationstation -p NRestarts -p ActiveState'
```

Expected: `ROMS partition created`, a p3 line `start= 6848512`, `/dev/mmcblk0p3 exfat`, the 12 folders,
`NRestarts=0`, `ActiveState=active` (Review Focus 5).

Then the reflash case (Review Focus 1):

```bash
TIMEOUT=30 scripts/board-run.sh 'echo marker > /roms/bios/ga36-marker; sync; sfdisk -q --no-reread --delete /dev/mmcblk0 3; sync; systemctl reboot'
# wait for the board to come back (about 60 s), then:
TIMEOUT=30 scripts/board-run.sh 'journalctl -b -u ga36-roms --no-pager | grep ROMS; cat /roms/bios/ga36-marker'
```

Expected: `ROMS partition entry restored` and `marker`.

- [ ] **Step 8: Commit.**

```bash
git add rootfs tests/roms-part.sh tests/rootfs.sh
git commit -m "Create or restore the ROMS partition at first boot"
```

### Task 10: RetroArch configuration; per-core speed and memory on the device

**Files:**
- Create: `rootfs/overlay/etc/skel/.config/retroarch/retroarch.cfg`
- Modify: `tests/rootfs.sh`

**Interfaces:**
- Consumes: gpio-keys joypad indices (SOUTH 0, EAST 1, NORTH 2, WEST 3, TL 4, TR 5, TL2 6, TR2 7, SELECT 8,
  START 9, THUMBL 10, THUMBR 11, FN 12, D-pad up 13, down 14, left 15, right 16); `/roms/bios`, `/roms/saves`
  from Task 9.
- Produces: `/home/ga36/.config/retroarch/retroarch.cfg` (copied from skel by `useradd -m`, which runs after the
  overlay copy in `customize.sh`).

- [ ] **Step 1: Failing test.** Append to `tests/rootfs.sh` before the final `[ $fail = 0 ]`:

```sh
ra=$(file home/ga36/.config/retroarch/retroarch.cfg 2>/dev/null || true)
for kv in 'video_context_driver = "kms"' 'video_refresh_rate = "55.690000"' 'video_vsync = "true"' \
	'audio_volume = "0.000000"' 'input_joypad_driver = "udev"' 'input_enable_hotkey_btn = "12"' \
	'input_exit_emulator_btn = "9"' 'input_player1_b_btn = "0"' 'input_player1_a_btn = "1"' \
	'input_player1_up_btn = "13"' 'config_save_on_exit = "false"' 'audio_max_timing_skew = "0.100000"'; do
	echo "$ra" | grep -qxF "$kv" || bad "retroarch.cfg lacks $kv"
done
[ "$(owner home/ga36/.config/retroarch/retroarch.cfg | cut -d' ' -f2)" = 1000/1000 ] || bad "retroarch.cfg not owned by ga36"
```

Run: `./build.sh run tests/rootfs.sh`
Expected: `FAIL: retroarch.cfg lacks ...` lines.

- [ ] **Step 2: rootfs/overlay/etc/skel/.config/retroarch/retroarch.cfg**

```
# GA36 defaults. The panel runs at 55.69 Hz. 60 Hz cores are 7.3-7.9 % off (NES 60.10 Hz), above the default
# skew of 0.05, where RetroArch drops vsync and the video tears. 0.10 keeps vsync: 60 Hz games run about 7 % slow,
# smooth, with the audio pitch lowered by the same amount.
audio_max_timing_skew = "0.100000"
video_driver = "gl"
video_context_driver = "kms"
video_fullscreen = "true"
video_refresh_rate = "55.690000"
video_vsync = "true"
audio_driver = "alsa"
# 0 dB: the amplifier limit is the Headphone mixer (vendor cap 63), set from ES.
audio_volume = "0.000000"
input_driver = "udev"
input_joypad_driver = "udev"
menu_driver = "rgui"
libretro_directory = "/usr/local/lib/libretro"
system_directory = "/roms/bios"
savefile_directory = "/roms/saves"
savestate_directory = "/roms/saves"
config_save_on_exit = "false"
# gpio-keys buttons, numbered as RetroArch's udev joypad driver sees them.
input_player1_b_btn = "0"
input_player1_a_btn = "1"
input_player1_x_btn = "2"
input_player1_y_btn = "3"
input_player1_l_btn = "4"
input_player1_r_btn = "5"
input_player1_l2_btn = "6"
input_player1_r2_btn = "7"
input_player1_select_btn = "8"
input_player1_start_btn = "9"
input_player1_l3_btn = "10"
input_player1_r3_btn = "11"
input_player1_up_btn = "13"
input_player1_down_btn = "14"
input_player1_left_btn = "15"
input_player1_right_btn = "16"
# FN is the hotkey: FN+Start exits to ES, FN+X opens the menu.
input_enable_hotkey_btn = "12"
input_exit_emulator_btn = "9"
input_menu_toggle_btn = "2"
```

- [ ] **Step 3: GREEN (container).**

Run: `./build.sh rootfs > "$W/rootfs.log" 2>&1; ./build.sh run tests/rootfs.sh && ./build.sh sdcard`
Expected: `PASS`.

- [ ] **Step 4: Device [person].** One message: write the card; boot once so p3 exists; power off; put the card in
  the PC and copy one ROM the person owns into each of `nes gb gbc snes gba megadrive mastersystem gamegear
  pcengine psx` on the `ROMS` partition; put it back and boot. Then, from ES: start a PS1 game and leave it running
  for 2 minutes; then FN+X (menu opens), close it, FN+Start (back to ES); report how the game sounded and played and
  whether every button did what its label says.

  While the PS1 game runs (Review Focus 3 and the spec's RAM check):
```bash
TIMEOUT=30 scripts/board-run.sh 'grep MemAvailable /proc/meminfo; swapon --show=NAME,USED --noheadings; dmesg | grep -ci "out of memory"'
```
Expected: `MemAvailable` ≥ 65536 kB, zram listed, `0`.

  Then the timed run per core (ES stopped; `--max-frames` runs a fixed number of frames; with vsync the ceiling is
  55.69 fps). Each core runs 1800 and then 3600 frames; fps = 1800 / (t3600 - t1800), so the start-up time cancels
  out. The 3600-frame run logs verbosely; `Cannot rely on VSync` there means the skew setting did not take effect:
```bash
TIMEOUT=1500 scripts/board-run.sh 'systemctl stop emulationstation; run() { a=$(date +%s%N); HOME=/home/ga36 retroarch -c /home/ga36/.config/retroarch/retroarch.cfg -L "$1" "$2" --max-frames=$3 --verbose --log-file=/tmp/ra.log >/dev/null 2>&1; b=$(date +%s%N); echo $(( (b - a) / 1000000 )); }; for e in nes:/usr/lib/arm-linux-gnueabihf/libretro/nestopia gb:/usr/lib/arm-linux-gnueabihf/libretro/gambatte gbc:/usr/lib/arm-linux-gnueabihf/libretro/gambatte snes:/usr/local/lib/libretro/snes9x2010 gba:/usr/local/lib/libretro/gpsp megadrive:/usr/local/lib/libretro/picodrive mastersystem:/usr/local/lib/libretro/picodrive gamegear:/usr/local/lib/libretro/picodrive pcengine:/usr/local/lib/libretro/mednafen_pce_fast psx:/usr/local/lib/libretro/pcsx_rearmed; do s=${e%%:*}; rom=$(ls /roms/$s/* | head -1); t1=$(run ${e#*:}_libretro.so "$rom" 1800); t2=$(run ${e#*:}_libretro.so "$rom" 3600); echo "$s $(awk -v a=$t1 -v b=$t2 "BEGIN{printf \"%.1f\", 1800000/(b-a)}") fps vsync-lost $(grep -c "Cannot rely on VSync" /tmp/ra.log)"; done; systemctl start emulationstation'
```
Expected: ten lines `<system> NN.N fps vsync-lost 0`, every fps between 54.0 and 55.8. Record them for Task 12. A
`vsync-lost` above 0: the skew key is not applied; fix the config, do not record the numbers. A core below 54: stop and
report it to the user (swapping a core is a spec decision), do not tune silently.

- [ ] **Step 5: Commit.**

```bash
git add rootfs/overlay/etc/skel tests/rootfs.sh
git commit -m "Configure RetroArch for the GA36 panel and buttons"
```

### Task 11: Power and controls

**Files:**
- Create: `rootfs/overlay/etc/systemd/logind.conf.d/ga36.conf`, `rootfs/overlay/usr/local/sbin/ga36-lowbat`,
  `rootfs/overlay/etc/systemd/system/ga36-lowbat.service`, `rootfs/overlay/etc/systemd/system/ga36-lowbat.timer`,
  `rootfs/overlay/usr/lib/systemd/system-sleep/ga36-alsa`, `tests/power.sh`
- Create (only if `VOLKEYS=yes`): `rootfs/overlay/usr/local/sbin/ga36-brightness`,
  `rootfs/overlay/etc/triggerhappy/triggers.d/ga36.conf`,
  `rootfs/overlay/etc/systemd/system/triggerhappy.service.d/root.conf`
- Modify: `rootfs/customize.sh` (enable line), `rootfs/packages.list` (`triggerhappy` if `VOLKEYS=yes`),
  `tests/rootfs.sh`

**Interfaces:**
- Consumes: `VOLKEYS` from Task 2's ledger; `axp20x-battery` sysfs; backlight `max_brightness` 10.
- Produces: `ga36-lowbat BATTERY_DIR` (exit 0 = power off now, prints the reason; any other status = keep running);
  `ga36-brightness BACKLIGHT_DIR up|down` (steps 1, clamps to 2..max).

- [ ] **Step 1: Failing test.** `tests/power.sh` (mode 755); the brightness block only when `VOLKEYS=yes`:

```sh
#!/bin/sh
# ga36-lowbat fires only while discharging at 3 % or less; ga36-brightness stays within 2..max.
# Run: ./build.sh run tests/power.sh
set -eu
s=rootfs/overlay/usr/local/sbin
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
bat() { printf '%s\n' "$1" > "$t/status"; printf '%s\n' "$2" > "$t/capacity"; }

bat Discharging 3
out=$("$s/ga36-lowbat" "$t") || bad "3 % discharging: no power off"
echo "$out" | grep -q '3 %' || bad "3 % discharging: did not read the fake battery ('$out')"
bat Discharging 0;  "$s/ga36-lowbat" "$t" >/dev/null || bad "0 % discharging: no power off"
bat Discharging 4;  "$s/ga36-lowbat" "$t" >/dev/null && bad "4 % discharging: power off"
bat Charging 2;     "$s/ga36-lowbat" "$t" >/dev/null && bad "2 % charging: power off"
bat 'Not charging' 1; "$s/ga36-lowbat" "$t" >/dev/null && bad "1 % not charging: power off"
"$s/ga36-lowbat" "$t/missing" >/dev/null 2>&1 && bad "missing battery: power off"

# VOLKEYS=yes only:
echo 10 > "$t/max_brightness"
echo 3 > "$t/brightness"; "$s/ga36-brightness" "$t" down; [ "$(cat "$t/brightness")" = 2 ] || bad "3 down"
"$s/ga36-brightness" "$t" down; [ "$(cat "$t/brightness")" = 2 ] || bad "went below 2"
echo 10 > "$t/brightness"; "$s/ga36-brightness" "$t" up; [ "$(cat "$t/brightness")" = 10 ] || bad "went above max"
echo 1 > "$t/brightness"; "$s/ga36-brightness" "$t" up; [ "$(cat "$t/brightness")" = 2 ] || bad "1 up"
[ $fail = 0 ] && echo PASS
exit $fail
```

Run: `./build.sh run tests/power.sh`
Expected: `FAIL: 3 % discharging: no power off` and the other firing cases.

- [ ] **Step 2: rootfs/overlay/usr/local/sbin/ga36-lowbat** (mode 755):

```sh
#!/bin/sh
# Usage: ga36-lowbat BATTERY_DIR
# Exit 0 when the battery is discharging at 3 % or less (ga36-lowbat.service then powers off), non-zero otherwise.
# axp20x_battery sends no uevent when the capacity changes, so a timer polls this instead of a udev rule.
set -eu
status=$(cat "$1/status")
capacity=$(cat "$1/capacity")
if [ "$status" = Discharging ] && [ "$capacity" -le 3 ]; then
	echo "battery at $capacity %, discharging: powering off"
	exit 0
fi
exit 1
```

- [ ] **Step 3 (VOLKEYS=yes): rootfs/overlay/usr/local/sbin/ga36-brightness** (mode 755):

```sh
#!/bin/sh
# Usage: ga36-brightness BACKLIGHT_DIR up|down
# Steps the backlight by one level, between 2 and max_brightness: level 1 looks off on the GA36 panel.
set -eu
max=$(cat "$1/max_brightness")
cur=$(cat "$1/brightness")
case $2 in
	up) new=$((cur + 1)) ;;
	down) new=$((cur - 1)) ;;
	*) echo "usage: $0 BACKLIGHT_DIR up|down" >&2; exit 2 ;;
esac
if [ $new -lt 2 ]; then new=2; fi
if [ $new -gt "$max" ]; then new=$max; fi
echo $new > "$1/brightness"
```

- [ ] **Step 4: GREEN (container).**

Run: `./build.sh run tests/power.sh`
Expected: `PASS`.

- [ ] **Step 5: Units and config.**

`rootfs/overlay/etc/systemd/system/ga36-lowbat.service`:
```ini
[Unit]
Description=Power off at 3 % battery while discharging

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if /usr/local/sbin/ga36-lowbat /sys/class/power_supply/axp20x-battery; then systemctl poweroff; fi'
```

`rootfs/overlay/etc/systemd/system/ga36-lowbat.timer`:
```ini
[Unit]
Description=Check the battery every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
```

`rootfs/overlay/etc/systemd/logind.conf.d/ga36.conf`:
```ini
[Login]
HandlePowerKey=suspend
HandlePowerKeyLongPress=poweroff
```

`rootfs/overlay/usr/lib/systemd/system-sleep/ga36-alsa` (mode 755):
```sh
#!/bin/sh
# The A33 analog codec loses its registers in s2idle (Headphone back to 0, muted): save the mixer before sleep and
# restore it after resume. systemd-sleep calls this with pre|post. The state goes to /run: no SD write per suspend.
case $1 in
	pre) alsactl -f /run/ga36-alsa.state store ;;
	post) alsactl -f /run/ga36-alsa.state restore ;;
esac
```

VOLKEYS=yes only: add `triggerhappy` to `rootfs/packages.list`;

`rootfs/overlay/etc/triggerhappy/triggers.d/ga36.conf`:
```
# Vol+/Vol- step the Headphone mixer; 63, its maximum, is the vendor cap. FN+Vol steps the backlight.
KEY_VOLUMEUP	1	/usr/bin/amixer -q sset Headphone 3+
KEY_VOLUMEUP	2	/usr/bin/amixer -q sset Headphone 3+
KEY_VOLUMEDOWN	1	/usr/bin/amixer -q sset Headphone 3-
KEY_VOLUMEDOWN	2	/usr/bin/amixer -q sset Headphone 3-
KEY_FN+KEY_VOLUMEUP	1	/usr/local/sbin/ga36-brightness /sys/class/backlight/backlight up
KEY_FN+KEY_VOLUMEDOWN	1	/usr/local/sbin/ga36-brightness /sys/class/backlight/backlight down
```

`rootfs/overlay/etc/systemd/system/triggerhappy.service.d/root.conf`:
```ini
# The backlight needs root; Debian runs thd as nobody.
[Service]
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --deviceglob /dev/input/event*
```

`rootfs/customize.sh` enable line: add `ga36-lowbat.timer`.
`tests/rootfs.sh` first `has` list: add `etc/systemd/system/timers.target.wants/ga36-lowbat.timer`,
`usr/lib/systemd/system-sleep/ga36-alsa`, `etc/systemd/logind.conf.d/ga36.conf` (and with VOLKEYS=yes
`etc/triggerhappy/triggers.d/ga36.conf`, `usr/sbin/thd`).

- [ ] **Step 6: Device RED for the sleep hook, on the Task 10 card** (hook not installed yet; [person] replugs the
  USB cable when asked):

```bash
TIMEOUT=20 scripts/board-run.sh "amixer -q sset Headphone 40; (echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +15 > /sys/class/rtc/rtc0/wakealarm; systemctl suspend; sleep 25; amixer sget Headphone | grep -o 'Playback [0-9]*' | head -1 > /root/after.txt) >/dev/null 2>&1 &"
# about 45 s later, after the person replugs the cable:
scripts/board-run.sh 'cat /root/after.txt; journalctl -b --no-pager | grep -c "PM: suspend exit"'
```
Expected: `Playback 0` and a count ≥ 1 (proves it really slept).

If it prints `Playback 40` with a count ≥ 1 (patch 0008 already keeps the registers through s2idle), the hook has
no RED: drop `ga36-alsa` from the overlay and from the `tests/rootfs.sh` `has` list, and ledger `Task 11: Ruling: no
sleep hook; Headphone 40 survives s2idle without it (Step 6 read) - cost if wrong: volume reset after resume`.
Step 7's Review Focus 4 check stays.

- [ ] **Step 7: Build, container GREEN, device GREEN [person].**

Run: `./build.sh rootfs > "$W/rootfs.log" 2>&1; ./build.sh run tests/rootfs.sh && ./build.sh run tests/power.sh && ./build.sh sdcard`
Expected: `PASS` twice.

  One message to the person: write the card, boot; then: (a) when asked, replug the cable after the board sleeps;
  (b) in a game, short-press power (screen off), wait 10 s, short-press power: the game continues with sound;
  replug the cable; (c) in ES, set volume to maximum in the menu; (d) VOLKEYS=yes: Vol+/Vol- change the volume,
  FN+Vol+/FN+Vol- change brightness and leave the volume alone; (e) hold power > 2 s: it powers off; report each.

```bash
# before (a): rerun the Step 6 commands
# after (b) and (c):
scripts/board-run.sh "journalctl -b -u systemd-suspend --no-pager | tail -3; amixer sget Headphone | grep -o 'Playback [0-9]*' | head -1; amixer sget 'AIF1 DA0' | grep -o 'Playback [0-9]*' | head -1; systemctl list-timers ga36-lowbat.timer --no-pager | grep -c ga36"
```
Expected: Step 6 now prints `Playback 40` (Review Focus 4; with the hook, or without it under the Step 6
ruling); after (c) `Headphone` `Playback 63` and `AIF1 DA0` `Playback 160`; timer count `1`; person confirms (b), (d), (e).

  Low-battery drain [person], optional before release, run overnight: unplugged, ES idle with backlight on; the
  next morning boot and run `scripts/board-run.sh 'journalctl -b -1 --no-pager | grep -E "battery at|Power-Off"'`.
  Expected: `battery at 3 %, discharging: powering off` (or 2/1/0) followed by the power-off. Record the result for
  Task 12; if not run, Task 12 lists it as unchecked.

- [ ] **Step 8: Commit.**

```bash
git add rootfs tests/power.sh tests/rootfs.sh
git commit -m "Power key, low-battery power-off, mixer restore after sleep and volume keys"
```

### Task 12: Device checklist results, spec, hardware notes and README

**Files:**
- Modify: `docs/specs/2026-10-14-firmware-design.md` (sections 1, 4, 5 "first-boot unit", Testing)
- Modify: `docs/hardware/hardwareAnalysis.md` (Vol+/Vol- row ~357; new "Userspace (V1.0)" results table after the
  "Mainline bring-up (V1.0)" table)
- Modify: `README.md` ("## Development")

**Interfaces:**
- Consumes: ledger numbers from Tasks 2, 8, 9, 10, 11.

- [ ] **Step 1: Full suite.**

Run: `for t in tests/*.sh; do ./build.sh run "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"; done`
Expected: every line `PASS`.

- [ ] **Step 2: hardwareAnalysis.md.** Vol+/Vol- row: `pass, LRADC ch0, raw UP_RAW / DOWN_RAW (idle 0x3f)` for
  VOLKEYS=yes, else `not on LRADC (DATA0 unchanged); unmapped in v1.0`. New table "Userspace (V1.0)" with rows:
  cold boot to ES (stopwatch and `systemd-analyze`), each core's fps, MemAvailable with ES + pcsx_rearmed, codec after
  stream stop (Task 1), mixer after suspend (Task 11), ROMS create / restore, power key short/long, hotkeys,
  volume cap (Headphone 63, AIF1 DA0 160), low-battery drain (result or "not run").

- [ ] **Step 3: Spec.** Apply deviations 1-10 from this plan's header: section 1 tree (`apps/` = per-app patch series,
  `build-deps.list`, `build-in-chroot.sh`; build order "ES and cores built in a throwaway armhf chroot";
  Containerfile line drops qemu-user-static, adds "host qemu-user-binfmt for apps/rootfs"); section 4 frontend
  paragraph (ES 351v over SDL2 GLES1, ES patch list), package list (no pixman; triggerhappy only with VOLKEYS=yes),
  power list (timer, no toggle, inherent cap, Vol keys outcome), carried items (codec reset fixed by patch 0008,
  sleep hook), autologin wording, root shell on ttyGS0; section 5: disk id `0x47413336` is fixed and the first-boot
  unit is `ga36-roms.service`. Keep each change to the sentence it replaces.

- [ ] **Step 4: README "## Development".** Replace the first bullet with:

```markdown
- `./build.sh uboot|kernel|initramfs|apps|rootfs|sdcard` builds into `out/`; `./build.sh run tests/<name>.sh` runs a
  check. `apps` and `rootfs` run as root in a privileged container and need Docker and `qemu-user-binfmt` on the
  host (`sudo apt install qemu-user-binfmt`); `apps` builds under emulation and takes a long time.
```

  and the second bullet's tree list becomes "`out/src/linux`, `out/src/u-boot` and the app trees
  (`scripts/fetch-apps.sh`)", "`scripts/tree.sh export <tree>` turns them into its patch directory".

- [ ] **Step 5: Docs check.**

Run: `grep -n 'libgo2\|pixman' docs/specs/2026-10-14-firmware-design.md README.md; grep -c '—' README.md docs/specs/2026-10-14-firmware-design.md`
Expected: `libgo2`/`pixman` appear only inside the deviation note that says they were dropped; em-dash counts unchanged
from before the edit.

- [ ] **Step 6: Commit.**

```bash
git add docs README.md
git commit -m "Record the userspace bring-up results and update the spec and README"
```
