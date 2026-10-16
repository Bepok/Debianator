# Charge mode (v1.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A charger plugged into a powered-off GA36 shows a battery icon with the charge level, then the screen goes
dark while it charges; a short power-key press shows the icon again, a long press boots into EmulationStation.

**Architecture:** U-Boot no longer switches the board off on a plug-in power-on. It reads the AXP boot source and sets
`ga36_init`, which the extlinux `append` passes as `init=`. On a plug-in power-on the kernel runs `ga36-charge`, a
small C program on the rootfs, as PID 1. The program draws through a DRM dumb buffer, sleeps in s2idle, and on a long
press execs `/sbin/init`. No initramfs.

**Tech Stack:** U-Boot v2026.10 board patch, C (glibc, raw DRM and evdev ioctls, no libdrm), POSIX sh tests, the
pinned build container.

**Spec:** [`docs/specs/2026-10-16-charge-mode-design.md`](../specs/2026-10-16-charge-mode-design.md)

## Global Constraints

- Every build and test runs through `./build.sh` in the container; no new host dependency.
- Patches to upstream trees: edit and commit in `out/src/<tree>`, then `scripts/tree.sh export <tree>`.
- Commits: author `Bepok <wojtekjakubiszyn@gmail.com>`, no trailers, no AI attribution, no em dashes or emoji.
- Everything on disk is English.
- Parallelism: never more workers than `nproc` (16) across concurrent runs.
- Normal power-key power-on, sleep, power-off and the 3 % shutdown behave exactly as in v1.0.
- Times: icon up 5 s; long press is a hold of 2000 ms (same as `HandlePowerKeyLongPress`); RTC wake at most every 60 s.

## Review Focus

1. **Reboot after a charge-mode long press.** If the AXP boot-source bit stays set across a SoC reset, a reboot
   from ES lands in charge mode. Expected: a reboot boots the system. Measured in Task 1; fixed in Task 4 if needed.
2. **Unreadable sysfs or no DRM device.** Expected: panel off and power off, never a PID 1 exit (that would panic
   and, with `panic=5`, reboot into charge mode again). Pinned by `read_int` tests in Task 2 and the device check
   in Task 5.
3. **Charger unplugged while the screen is dark.** Expected: power off within 60 s. Device check in Task 5.
4. **Power key held across the 2 s mark while the screen is dark.** Expected: the press that woke the board counts
   from the key-down event, so a hold boots ES. Device check in Task 5.
5. **`ga36_init` unset or empty.** Expected: impossible, because the patch sets it on every boot, defaulting to
   `/sbin/init`. Pinned by the `strings` check in Task 3.

---

### Task 1: Device probe: boot-source bit and unplug wake

Needs a person at the device. It answers the spec's first two open risks and decides whether Task 4 runs.

**Files:**
- Modify: `docs/hardware/hardwareAnalysis.md` (on-device test table: one row per measurement)

- [ ] **Step 1: Build a probe U-Boot.** In `uboot/ga36_defconfig` delete `CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y`.
  Run `./build.sh uboot`. Do not commit yet (Task 3 commits it).
- [ ] **Step 2: Put it on a v1.0.0 card.** Write `out/u-boot/u-boot-sunxi-with-spl.bin` at 8 KiB:
  `sudo dd if=out/u-boot/u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8 conv=fsync`. Ask the person first and
  confirm `/dev/sdX`.
- [ ] **Step 3: Read the bit on each boot source.** On each boot read AXP register 0x00 over `ttyGS0`:
  `grep '^00:' /sys/kernel/debug/regmap/*axp*/registers`, after `mount -t debugfs debugfs /sys/kernel/debug` if
  needed. Do this for:
  - (a) power-key power-on, no charger;
  - (b) charger plugged into the powered-off board, which now boots the normal system;
  - (c) `reboot` from (b);
  - (d) `reboot` from (a) with the charger plugged in.
  Expected: bit 0 is set in (b) and clear in (a). (c) and (d) are the open questions.
- [ ] **Step 4: Unplug wake.** In (b), run `echo freeze > /sys/power/state` with the charger plugged in, then unplug
  it. Record whether the shell returns, and after how long.
- [ ] **Step 5: Record and commit.** Add the four bit values and the wake result to the table.
  `git commit -m "Measure the AXP boot source across reboots and unplug wake"` (docs file only).

Task 4 runs if bit 0 is set in (c) or (d). If unplug does not wake s2idle, the 60 s RTC alarm in Task 2 is the only
unplug check (already planned).

### Task 2: `ga36-charge` program

**Files:**
- Create: `apps/ga36-charge.c`
- Create: `tests/charge.c` (host unit test, includes the program source)
- Create: `tests/charge.sh`
- Modify: `apps/build-in-chroot.sh` (compile and install), `scripts/build-apps.sh` (copy-in the source),
  `tests/apps.sh` (binary present and armhf), `tests/rootfs.sh` (file list gains `usr/local/sbin/ga36-charge`)

**Interfaces:**
- Produces: `/usr/local/sbin/ga36-charge` on the rootfs (Task 3 points `ga36_init` at it).
- Produces, in `apps/ga36-charge.c`: `int read_int(const char *path)` returns the leading decimal integer of the
  file, or -1 if it cannot be opened or parsed. `int fill_width(int capacity, int inner)` returns
  `inner * capacity / 100`, with `capacity` clamped to 0..100 and -1 mapped to 0.

- [ ] **Step 1: Write the failing test.** `tests/charge.c` starts with `#define main ga36_charge_main` and
  `#include "../apps/ga36-charge.c"`, and has its own `main` with these assertions:
  - `fill_width(50, 200) == 100`, `fill_width(100, 200) == 200`, `fill_width(0, 200) == 0`,
    `fill_width(-1, 200) == 0`, `fill_width(150, 200) == 200`;
  - `read_int` of a temp file holding `"87\n"` is 87; of a missing path is -1; of a file holding `"x\n"` is -1.

  It prints `PASS` and exits 0, or prints `FAIL: <what>` and exits 1. `tests/charge.sh` follows the header style of
  `tests/apps.sh` and runs `gcc -Wall -Werror -o "$t/charge" tests/charge.c && "$t/charge"` (host gcc in the
  container).
- [ ] **Step 2: Run it.** `./build.sh run tests/charge.sh` fails: `apps/ga36-charge.c` does not exist.
- [ ] **Step 3: Implement `apps/ga36-charge.c`.** It uses only glibc and the kernel uapi headers (`drm/drm.h`,
  `drm/drm_mode.h`, `linux/input.h`, `linux/rtc.h`). Pinned behaviour:
  - Log lines go to `/dev/kmsg` as `ga36-charge: <text>`.
  - `die(const char *why)`: log the reason, then panel off, then `reboot(RB_POWER_OFF)`, then loop on `pause()`. The
    program never returns from `main`.
  - At start: mount `proc`, `sysfs` and `devtmpfs` on `/proc`, `/sys` and `/dev` (ignore `EBUSY`).
  - Battery: `/sys/class/power_supply/axp20x-battery/capacity`. Charger: online if either
    `/sys/class/power_supply/axp20x-usb/online` or `/sys/class/power_supply/axp22x-ac/online` reads 1.
  - Key: the `/dev/input/event*` whose `EVIOCGNAME` is `axp20x-pek`, `KEY_POWER`.
  - DRM: the first `/dev/dri/card*` with a connected connector. Dumb buffer at the connector's preferred mode,
    XRGB8888, `DRM_IOCTL_MODE_SETCRTC`. Panel off is `SETCRTC` with `fb_id` 0. All fds are `O_CLOEXEC`. The DRM fd
    stays open until `exec`: closing it would hand the CRTC back to fbcon and light the panel.
  - The icon: a battery outline and nub with a fill of `fill_width(capacity, inner)`, centred, on black. Geometry
    and colours are the builder's call.
  - Loop:
    - show the icon for 5 s; a key-down during that time restarts the 5 s;
    - then panel off, set an RTC alarm 60 s ahead (`RTC_WKALM_SET` on `/dev/rtc0`), and write `freeze` to
      `/sys/power/state`;
    - on return, poll the key fd for 500 ms;
    - charger offline: log and `reboot(RB_POWER_OFF)`;
    - key-down: show the icon again;
    - otherwise go back to sleep.
  - Long press: a key held 2000 ms from its key-down, whether the screen is on or the press woke the board. Then
    close the DRM fd and `execv("/sbin/init", ...)` with the original `argv`. If exec fails: `die`.
- [ ] **Step 4: Run it.** `./build.sh run tests/charge.sh` prints PASS.
- [ ] **Step 5: Build it into the apps stage.**
  - `scripts/build-apps.sh`: add `apps/ga36-charge.c` to the `copy-in` list.
  - `apps/build-in-chroot.sh`: `cc -O2 -Wall -Werror -o /stage/usr/local/sbin/ga36-charge /src/ga36-charge.c`,
    with `mkdir -p /stage/usr/local/sbin`. Add it to the `ldd` loop.
  - `tests/apps.sh`: `usr/local/sbin/ga36-charge` exists and passes `arm`.
  - `tests/rootfs.sh`: the file list includes `usr/local/sbin/ga36-charge`.

  Run `./build.sh apps && ./build.sh rootfs`, then `./build.sh run tests/apps.sh` and `./build.sh run tests/rootfs.sh`.
  Both print PASS.
- [ ] **Step 6: Smoke test on the device.** On a card with this rootfs, stop ES (`systemctl stop emulationstation`)
  and run `ga36-charge` from `ttyGS0`. Check:
  - the icon appears at the right level, then the panel goes dark after 5 s;
  - a short press shows it again.

  Not PID 1 here, so a long press only logs the failed exec. Ctrl-C ends it.
- [ ] **Step 7: Commit.** `git commit -m "Add the charge screen program"`

### Task 3: Boot into charge mode on a plug-in power-on

**Files:**
- Modify: `uboot/ga36_defconfig` (drop `CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y`)
- Create: `uboot/patches/0002-sunxi-ga36-pick-init-from-the-AXP-boot-source.patch` (via `scripts/tree.sh export u-boot`)
- Modify: `scripts/make-image.sh:20` (`append`), `tests/uboot-config.sh`, `tests/image.sh`

**Interfaces:**
- Consumes: `/usr/local/sbin/ga36-charge` (Task 2).
- Produces: U-Boot env `ga36_init`, either `/usr/local/sbin/ga36-charge` or `/sbin/init`.

- [ ] **Step 1: Write the failing tests.**
  - `tests/uboot-config.sh`: replace `on CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y` with
    `off CONFIG_AXP_DISABLE_BOOT_ON_POWERON` and update the header comment. Add: `strings out/build/u-boot/u-boot`
    contains both `ga36_init` and `/usr/local/sbin/ga36-charge`.
  - `tests/image.sh`: the extlinux check becomes
    `append .*console=ttyGS0.* root=PARTUUID=47413336-02 rootwait init=\${ga36_init}`.
- [ ] **Step 2: Run them.** `./build.sh run tests/uboot-config.sh` and `./build.sh run tests/image.sh` both FAIL,
  on the config option and the `init=` part.
- [ ] **Step 3: U-Boot patch.** In `out/src/u-boot/board/sunxi/board.c`, at the end of `misc_init_r()` before
  `return 0`, under `#ifdef CONFIG_AXP221_POWER`:
  - `env_set("ga36_init", "/sbin/init")`;
  - then, if `pmic_bus_read(AXP_POWER_STATUS, &status) == 0` and `status & AXP_POWER_STATUS_ALDO_IN`,
    `env_set("ga36_init", "/usr/local/sbin/ga36-charge")`.

  Comment it in one line: GA36, a charger plug-in power-on runs the charge screen. Commit in the tree with subject
  `sunxi: ga36: pick init from the AXP boot source`, signed off as `0001` is, then `scripts/tree.sh export u-boot`.
  Delete the defconfig line, which Task 1 already did in the working tree.
- [ ] **Step 4: Append line.** In `scripts/make-image.sh`, add `init=${ga36_init}` to the end of `append`. The heredoc
  is quoted (`<<'EOT'`), so the literal `${ga36_init}` reaches the card.
- [ ] **Step 5: Run them.** `./build.sh uboot && ./build.sh image`, then both tests print PASS. Also run
  `./build.sh run tests/tree.sh`.
- [ ] **Step 6: Commit.** `git commit -m "Boot into the charge screen on a charger power-on"`

### Task 4 (only if Task 1 shows bit 0 set after a reboot): tell a reboot from a cold plug-in

Approach: a warm-reset marker in a sun6i RTC general-purpose data register. The RTC domain stays powered from the
battery, so it survives both reboot and power-off.
- `ga36-charge` writes the marker just before it execs `/sbin/init`.
- A shutdown hook clears it on power-off only.
- U-Boot picks charge mode only when bit 0 is set **and** the marker is absent.

**Files:**
- Modify: the Task 3 U-Boot patch (read the marker), `apps/ga36-charge.c` (set it through `/dev/mem`; needs
  `CONFIG_DEVMEM=y` in `kernel/ga36.config` if absent)
- Create: `rootfs/overlay/usr/lib/systemd/system-shutdown/ga36-charge-marker` (clears it when `$1` is `poweroff`)
- Test: extend `tests/uboot-config.sh`, `tests/rootfs.sh`, `tests/kernel-config.sh` accordingly

Pin these before writing code, from the A33 user manual:
- the register: the first GP data register not used by U-Boot's or Linux's sunxi code (grep both trees for its offset);
- the marker value: `0x47413336`, the disk id, already the project's magic.

A hard power-off (AXP 6 s hold, flat battery) leaves the marker set. The next plug-in then boots normally instead of
showing the icon. That is acceptable and goes in the spec as a known limit. Device check: the Task 1 cases (c) and
(d) now boot the system, and a plug-in after a clean power-off shows the icon. Commit:
`git commit -m "Keep a reboot out of charge mode"`.

### Task 5: Device checklist, docs

Needs a person at the device.

**Files:**
- Modify: `docs/hardware/hardwareAnalysis.md`, `docs/specs/2026-10-16-charge-mode-design.md` (status, measured
  answers to its open risks), `docs/specs/2026-10-14-firmware-design.md` (lines 21 and 76, and the
  `AXP_DISABLE_BOOT_ON_POWERON` bullet in section 2: no initramfs, the charge program is `init=`),
  `docs/porting-plan.md` (roadmap row: "Linux-side charge mode as `init=`"), `README.md` (move the charging
  animation from "Not yet" to the supported list, and change "plugging in ... does not power the board on")

- [ ] **Step 1: Full image.** `./build.sh all`, then run every `tests/*.sh` the way `.github/workflows/image.yml`
  does. All PASS. Flash it.
- [ ] **Step 2: Person checks**, each a table row:
  - plug-in from off: the icon at the right level, dark after 5 s;
  - short press: the icon again;
  - long press: ES;
  - unplug while dark: off within 60 s;
  - unplug while the icon shows: off;
  - power-key power-on with and without the charger: ES as in v1.0;
  - reboot from ES after a charge-mode long press: the system, not charge mode;
  - plug-in at the 3 % cutoff: the icon or a clean off, no reboot loop;
  - time from plug-in to icon, by stopwatch.

  If the 3 % plug-in loops, stop and bring it back to the person. The spec's fallback (skip charge mode below a
  voltage) is a new task.
- [ ] **Step 3: Docs and commit.** Update the files above with the results.
  `git commit -m "Record the charge mode device checks"`
