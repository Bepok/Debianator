# Boot and kernel (sub-projects 1 and 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot mainline U-Boot v2026.10 and Linux 6.18.56 on the GA36-MB V1.0 from the PC over USB FEL and from an SD
card, with the panel, buttons, audio, battery, sleep, thermal limits and the USB serial gadget working.

**Architecture:** A host-side `build.sh` runs every build stage in a pinned Debian trixie container. U-Boot and Linux
are pinned upstream trees in `out/src/`, kept as git repositories with this repo's `git format-patch` series applied;
board work is authored in those trees and exported back as patches. Bring-up happens over FEL with a throwaway test
initramfs. The only link to the board is the USB OTG port: U-Boot's ACM console on FEL boots, the kernel's gadget
console `ttyGS0`, and crash logs read back from pstore after the board resets into FEL. A test SD image proves the
card boot path. The release rootfs and image are sub-projects 3 and 4.

**Tech Stack:** POSIX sh, Docker or Podman, Debian trixie `gcc-arm-linux-gnueabihf`, mmdebstrap (fakechroot mode),
U-Boot Kconfig, Linux device tree and DRM panel driver (C), dt-schema, sunxi-fel, mtools.

**Spec:** [`docs/specs/2026-10-14-firmware-design.md`](../specs/2026-10-14-firmware-design.md)

## Global Constraints

Copied from the spec; every task must satisfy them.

- Kernel: "mainline Linux 6.18 LTS" - "Linux 6.18 LTS (6.18.56 on 2026-10-14)".
- Bootloader: "mainline U-Boot v2026.10".
- Build: "shell scripts + mmdebstrap in a pinned Debian trixie container"; "the host needs only Podman or Docker".
- Sources: "Patches are kept as `git format-patch` series; bumping a pin means rebasing the series."
- "No saved U-Boot environment."
- SD layout: "MBR; a GPT would overlap the SPL at 8 KiB"; "The boot ROM loads `u-boot-sunxi-with-spl.bin` from
  8 KiB"; "p1 `BOOT` | 256 MiB FAT32 | zImage, DTB, extlinux.conf".
- Guard rails: "AXP rail and CPU OPP voltages never above the vendor values"; "charge voltage and current only from
  the vendor `[pmu1_para]`".
- From the user's standing rules: everything on disk in English; test code (test initramfs, FEL and serial helpers,
  `tests/`) never ends up in a release image; commits authored by `Bepok <wojtekjakubiszyn@gmail.com>` with no AI
  trailers; parallel jobs capped at `nproc`.

## Spec deviations (applied to the spec in Task 12)

Found while planning; each is forced by a hardware or upstream fact.

1. **Console: USB OTG only** instead of UART2. The UART pads of the development board are damaged. U-Boot gets a
   USB ACM console on FEL boots without a boot script (`scripts/fel-boot.sh uboot`), the kernel the built-in serial
   gadget `ttyGS0`, and crashes are kept in a ramoops region (its own DTS patch, kept in this repository only) and read from
   `/sys/fs/pstore` after the reset. SD
   boots never wait for a USB host. The board DTS describes no debug UART: using one means soldering to small pads,
   which owners are unlikely to do.
2. **Buttons: `gpio-keys-polled`** instead of `gpio-keys`. On the A33 only the PB and PG banks raise interrupts; 15
   of the 17 buttons are on PE.
3. **Silent charging:** U-Boot's `AXP_DISABLE_BOOT_ON_POWERON` does not clear the AXP power-on-by-charger setting.
   When the power-on source was the charger, the SPL switches the board off again (`board/sunxi/board.c:592`). The
   result is the same for the user (no boot on plug-in), and nothing persists in the AXP, so the "stock firmware
   charging animation" caveat in the spec no longer applies.
4. **Thermal test load:** busybox (`md5sum /dev/zero` x4) instead of `stress-ng`, which pulls in Mesa and LLVM
   (208 MB) into the test initramfs.
5. **Bindings: three dt-bindings patches** (vendor prefix, panel compatible, board compatible) instead of one;
   upstream takes each binding file as its own patch.
6. **One U-Boot patch:** `board_usb_init()` probes the MUSB gadget. Upstream sunxi probes it only for USB Ethernet,
   so without that patch the ACM console cannot start.

## Review Focus

The five failure modes most likely to bite during this work. None is covered by the spec's test list; each has a
test in the task named.

1. **Board powered on by plugging in the cable.** U-Boot then switches it off by design, so an FEL session silently
   dies, and with no UART the SPL's message is invisible. Expected: `fel-boot.sh` says so and exits non-zero.
   Test: Task 4, step 6.
2. **SD boot with no PC attached.** U-Boot's ACM console blocks until a USB host enumerates it, so enabling it on
   a card boot would hang a board on a charger forever. Expected: the card boots to Linux with no cable, and the
   gadget console appears when the cable is plugged in later. Tests: Task 3, step 1 (`tests/uboot-config.sh`, the
   preboot condition); Task 11, step 7.
3. **CPU rail misidentified, so the wrong rail is overvolted.** The Q8 reference design uses DCDC2 for the CPU; this
   board is believed to use DCDC3. Expected: no DT rail or OPP ever exceeds a vendor value, and the 1.32 V OPPs come
   only after the stock OPPs run stable. Tests: Task 6, step 1 (`tests/dtb.sh`); Task 10.
4. **Kernel turns off a rail U-Boot enabled.** The unused-regulator cleanup runs 30 s after boot and disables any
   regulator without a consumer or `regulator-always-on` (`dldo3`, `aldo3` have no known consumer). Expected: all
   vendor rails still on after 60 s. Test: Task 8, step 8.
5. **VBUS driven toward the PC or charger, or `PB2` (BTN_THUMBR) driven as a backlight enable.** The base defconfig
   enables MUSB host and the LCD backlight enable on `PB2`. Expected: U-Boot drives neither, Linux leaves VBUS off
   while connected as a gadget. Tests: Task 3, step 1 (`tests/uboot-config.sh`); Task 8, step 9.

## Execution notes

- Work in a git worktree per superpowers:using-git-worktrees: from the repository root, `git worktree add -b boot-kernel
  .claude/worktrees/boot-kernel` (with `.claude/worktrees/` in `.git/info/exclude`). All paths below are relative to
  that worktree. Fast-forward `main` when the plan is done.
- Host facts: Docker is installed. `sunxi-fel` runs on the host (it needs the USB device): before Task 4, the user
  installs it with `sudo apt install sunxi-tools`, joins the `sunxi-fel` group (`sudo usermod -aG sunxi-fel $USER`; the
  package's udev rule gives the FEL device to that group) and starts a fresh login before running Claude Code; `SUNXI_FEL` can point at another build. There is no UART: every console is a USB ACM device on the OTG cable, named by
  `scripts/70-ga36-usb.rules` (Task 4) as `/dev/ga36-uboot` and `/dev/ga36-linux`. The rule also keeps
  ModemManager, which is active on the host, from probing these ports with AT commands.
- **FEL entry:** remove the SD card, press the power key. The board enumerates as `1f3a:efe8`. One upload per
  power-on; power off (hold the power key ~8 s) before the next one. A kernel panic resets the board (`panic=5`)
  and, with no card, it comes back in FEL.
- **Risks:** U-Boot's ACM console has no in-tree sunxi user; it relies on the `board_usb_init()` patch of Task 3. If
  `/dev/ga36-uboot` never appears (Task 4, step 5),
  set `# CONFIG_USE_PREBOOT is not set`, drop its lines from `tests/uboot-config.sh` and continue: U-Boot then runs
  blind and only the kernel console exists. Whether ramoops survives the reset is unknown until Task 8, step 10; if it
  does not, early crashes are visible only on the panel's framebuffer console once Task 9, step 2 passes. A hang
  before the gadget or ramoops comes up shows nothing.
- Steps marked **[person]** need the user at the device. Batch them: when a task reaches its first such step, ask
  for all of that task's person steps in one message.
- Commits use the host git identity (Bepok) and carry no trailers. Commits inside `out/src/linux` and `out/src/u-boot` are
  made with `git commit -s`, because they are upstream-form patches (the user's standing DCO authorization covers this).

---

### Task 1: Build container and entry point

**Files:**
- Create: `container/Containerfile`
- Create: `versions.env`
- Create: `build.sh`
- Test: `tests/container.sh`

**Interfaces:**
- Produces: `./build.sh <stage>`; stages `uboot`, `kernel`, `initramfs`, `sdcard` (added by later tasks) and
  `run <cmd> [args]` (any command in the container, repo root as working directory, host uid/gid, `HOME=/tmp`).
- Produces: `versions.env` variables `UBOOT_GIT`, `UBOOT_TAG`, `UBOOT_COMMIT`, `LINUX_VERSION`, `LINUX_SHA256`.

- [ ] **Step 1: Write the failing test**

`tests/container.sh`:

```sh
#!/bin/sh
# The build container has every tool the stages use. Run: ./build.sh run tests/container.sh
set -eu
fail=0
for tool in arm-linux-gnueabihf-gcc gcc make bison flex bc python3 swig git curl xz cpio rsync \
	fdtget dtc dt-validate mmdebstrap fakechroot mcopy mkfs.vfat sfdisk; do
	command -v "$tool" >/dev/null || { echo "FAIL: $tool missing"; fail=1; }
done
[ "$(id -u)" != 0 ] || { echo "FAIL: running as root"; fail=1; }
[ $fail = 0 ] && echo PASS
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/container.sh && ./build.sh run tests/container.sh`
Expected: FAIL, `./build.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

`versions.env`:

```sh
# Pinned upstream sources. Bumping a pin means rebasing the matching patch series.
# No 2026.10 release tarball exists on the denx server yet, so U-Boot is pinned by tag and verified by commit.
UBOOT_GIT=https://source.denx.de/u-boot/u-boot.git
UBOOT_TAG=v2026.10
UBOOT_COMMIT=5508406582f6f7120dce0c4b3059819a41788db2
LINUX_VERSION=6.18.56
LINUX_SHA256=4633bbda2ab95eaf2a7af4041236451d6759c72e6946265531af4b3aacefbf89
```

`container/Containerfile`:

```dockerfile
# Build environment for every stage of ./build.sh.
FROM debian:trixie@sha256:913f6706df59a68922d1dd08f78c2476560a8d367897200a6005b00e5f67c2d5
RUN echo 'deb http://deb.debian.org/debian trixie-backports main' > /etc/apt/sources.list.d/backports.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
	gcc-arm-linux-gnueabihf gcc libc6-dev make bison flex bc python3 python3-setuptools python3-dev \
	libssl-dev libgnutls28-dev uuid-dev swig git ca-certificates curl xz-utils cpio kmod rsync \
	device-tree-compiler mmdebstrap debian-archive-keyring fakeroot fakechroot mtools dosfstools fdisk \
 && apt-get install -y --no-install-recommends -t trixie-backports dt-schema yamllint \
 && rm -rf /var/lib/apt/lists/*
```

`build.sh`:

```sh
#!/bin/sh
# Build entry point. Every stage runs inside the pinned build container (container/Containerfile).
# Usage: ./build.sh uboot|kernel|initramfs|sdcard
#        ./build.sh run <command> [args]     run any command in the container
# Env: ENGINE=docker|podman (default: whichever is installed, docker first).
set -eu
cd "$(dirname "$0")"

usage() { echo "usage: ./build.sh uboot|kernel|initramfs|sdcard | run <command> [args]" >&2; exit 2; }
[ $# -gt 0 ] || usage

ENGINE=${ENGINE:-$(command -v docker || command -v podman)}
IMAGE=r36s-a33-ga36-build
case $(basename "$ENGINE") in podman) userns=--userns=keep-id ;; *) userns= ;; esac
if [ -t 0 ]; then it=-it; else it=; fi
mkdir -p out   # git-ignored, so absent in a fresh worktree; created here so the host user owns it

"$ENGINE" build -q -t "$IMAGE" -f container/Containerfile container >/dev/null

run() {
	"$ENGINE" run --rm $it $userns --user "$(id -u):$(id -g)" -e HOME=/tmp \
		-v "$PWD:/work" -w /work "$IMAGE" "$@"
}

stage=$1
shift
case $stage in
	run) [ $# -gt 0 ] || usage; run "$@" ;;
	*) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x build.sh && ./build.sh run tests/container.sh && ./build.sh run touch out/.owner && stat -c %U out/.owner && rm out/.owner`
Expected: `PASS`, then `bepok` (files written by the container belong to the host user).

- [ ] **Step 5: Commit**

```bash
git add container/Containerfile versions.env build.sh tests/container.sh
git commit -m "Add build container and build.sh entry point"
```

---

### Task 2: Pinned source trees with patch series

**Files:**
- Create: `scripts/tree.sh`
- Test: `tests/tree.sh`

**Interfaces:**
- Consumes: `versions.env` (Task 1).
- Produces: `scripts/tree.sh prep u-boot|linux` - creates `out/src/u-boot` or `out/src/linux` (git repo, base tagged
  `ga36-base`, `uboot/patches/*.patch` or `kernel/patches/*.patch` applied with `git am`); rebuilds it only when the
  pin or the patch set changed; exits 1 instead of discarding uncommitted or unexported work.
- Produces: `scripts/tree.sh export u-boot|linux` - rewrites the patch directory from `ga36-base..HEAD` of the tree.

- [ ] **Step 1: Write the failing test**

`tests/tree.sh` (runs against a throwaway local upstream in a temp copy, never the real trees):

```sh
#!/bin/sh
# tree.sh keeps a current tree, rebuilds a stale one and refuses to discard local work.
# Run: ./build.sh run tests/tree.sh
set -eu
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
id="-c user.name=t -c user.email=t@example.org"

mkdir -p "$t/scripts" "$t/uboot/patches" "$t/kernel/patches"
cp scripts/tree.sh "$t/scripts/"
up=$t/upstream
git init -q "$up"
echo a > "$up/f"
git -C "$up" add f
git -C "$up" $id commit -q -m base
git -C "$up" tag v1
cat > "$t/versions.env" <<EOF
UBOOT_GIT=file://$up
UBOOT_TAG=v1
UBOOT_COMMIT=$(git -C "$up" rev-parse HEAD)
LINUX_VERSION=0
LINUX_SHA256=0
EOF
src=$t/out/src/u-boot

"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(cat "$src/f")" = a ] || fail "fresh tree not created"

# A commit exported as the patch set: prep keeps the tree as it is.
echo b > "$src/f"
git -C "$src" $id commit -qam change
"$t/scripts/tree.sh" export u-boot >/dev/null
ls "$t"/uboot/patches/0001-*.patch >/dev/null 2>&1 || fail "export wrote no patch"
head=$(git -C "$src" rev-parse HEAD)
"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(git -C "$src" rev-parse HEAD)" = "$head" ] || fail "current tree was rebuilt"

# Unexported commit while the patch set changes: refuse and keep the work.
echo c > "$src/f"
git -C "$src" $id commit -qam unexported
rm "$t"/uboot/patches/*.patch
if "$t/scripts/tree.sh" prep u-boot 2>/dev/null; then fail "prep discarded unexported work"; fi
[ "$(cat "$src/f")" = c ] || fail "local work lost"

# Uncommitted change: refuse as well.
git -C "$src" reset -q --hard "$head"
echo d > "$src/f"
if "$t/scripts/tree.sh" prep u-boot 2>/dev/null; then fail "prep discarded uncommitted work"; fi
[ "$(cat "$src/f")" = d ] || fail "uncommitted work lost"

# Clean tree, patch set changed (now empty): rebuilt from upstream.
git -C "$src" checkout -q f
"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(cat "$src/f")" = a ] || fail "stale tree not rebuilt"
echo PASS
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/tree.sh && ./build.sh run tests/tree.sh`
Expected: FAIL, `cp: cannot stat 'scripts/tree.sh'`.

- [ ] **Step 3: Write the implementation**

`scripts/tree.sh`:

```sh
#!/bin/sh
# Pinned upstream source trees in out/src, with this repo's patch series applied by git am.
# Usage: scripts/tree.sh prep|export u-boot|linux
#   prep    create out/src/<tree>, or rebuild it when the pin or the patch set changed. Refuses (exit 1)
#           instead of discarding uncommitted changes or commits not yet exported.
#   export  write the commits on top of the pinned base (tag ga36-base) to the patch directory.
# Authoring: edit and commit in out/src/<tree>, then export.
set -eu
cd "$(dirname "$0")/.."
. ./versions.env

usage() { echo "usage: $0 prep|export u-boot|linux" >&2; exit 2; }
[ $# -eq 2 ] || usage
verb=$1 name=$2
case $name in
	u-boot) patches=uboot/patches pin=$UBOOT_COMMIT ;;
	linux) patches=kernel/patches pin=$LINUX_SHA256 ;;
	*) usage ;;
esac
src=out/src/$name
state=$src/.git/ga36-state
git_id="-c user.name=ga36-build -c user.email=ga36-build@localhost"

inputs() { { echo "$pin"; cat "$patches"/*.patch 2>/dev/null || true; } | sha256sum | cut -d' ' -f1; }
record() { echo "$(inputs) $(git -C "$src" rev-parse HEAD)" > "$state"; }
has_local_work() {
	[ -n "$(git -C "$src" status --porcelain)" ] && return 0
	read -r _ head < "$state"
	[ "$(git -C "$src" rev-parse HEAD)" != "$head" ]
}

fetch() {
	mkdir -p out/src
	case $name in
	u-boot)
		git clone -q --depth 1 --branch "$UBOOT_TAG" "$UBOOT_GIT" "$src"
		if [ "$(git -C "$src" rev-parse HEAD)" != "$UBOOT_COMMIT" ]; then
			echo "$UBOOT_TAG is not $UBOOT_COMMIT" >&2
			exit 1
		fi
		;;
	linux)
		tarball=out/dl/linux-$LINUX_VERSION.tar.xz
		mkdir -p out/dl
		if [ ! -f "$tarball" ]; then
			curl -fL -o "$tarball.part" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX_VERSION.tar.xz"
			mv "$tarball.part" "$tarball"
		fi
		echo "$LINUX_SHA256  $tarball" | sha256sum -c --quiet -
		tar -xf "$tarball" -C out/src
		mv "out/src/linux-$LINUX_VERSION" "$src"
		git -C "$src" init -q
		git -C "$src" add -A
		git -C "$src" $git_id commit -q -m "Linux $LINUX_VERSION"
		;;
	esac
	git -C "$src" tag ga36-base
}

case $verb in
prep)
	if [ -f "$state" ]; then
		read -r have _ < "$state"
		[ "$have" = "$(inputs)" ] && exit 0
		if has_local_work; then
			echo "$src has work not exported to $patches: commit it and run scripts/tree.sh export $name" >&2
			exit 1
		fi
		rm -rf "$src"
	elif [ -e "$src" ]; then
		echo "$src was not made by scripts/tree.sh; move it away" >&2
		exit 1
	fi
	fetch
	for p in "$patches"/*.patch; do
		[ -e "$p" ] || continue
		git -C "$src" $git_id am -q "$PWD/$p"
	done
	record
	;;
export)
	[ -z "$(git -C "$src" status --porcelain)" ] || { echo "$src has uncommitted changes" >&2; exit 1; }
	mkdir -p "$patches"
	rm -f "$patches"/*.patch
	git -C "$src" format-patch -q --zero-commit --no-signature -o "$PWD/$patches" ga36-base..HEAD
	record
	;;
*) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/tree.sh && ./build.sh run tests/tree.sh`
Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tree.sh tests/tree.sh
git commit -m "Add pinned source trees with patch series export"
```

---

### Task 3: U-Boot for the GA36

**Files:**
- Create: `uboot/ga36_defconfig`
- Modify (in `out/src/u-boot`): `board/sunxi/board.c`
- Create: `uboot/patches/0001-sunxi-probe-the-MUSB-gadget-in-board_usb_init.patch` (by `scripts/tree.sh export u-boot`)
- Create: `scripts/build-uboot.sh`
- Modify: `build.sh` (stage dispatch)
- Test: `tests/uboot-config.sh`

**Interfaces:**
- Consumes: `scripts/tree.sh prep u-boot` (Task 2).
- Produces: `out/u-boot/u-boot-sunxi-with-spl.bin`; on a FEL boot without a script, U-Boot skips autoboot and its
  console is USB ACM `1f3a:1010` (host `/dev/ga36-uboot`, Task 4); `out/u-boot/fel.scr` (boots zImage at
  `0x42000000`, uImage ramdisk at `0x43400000`, DTB at `0x43000000`, `console=tty0 console=ttyGS0,115200 panic=5`;
  if `bootz` fails it switches U-Boot's console to ACM); `out/build/u-boot/tools/mkimage` (used by Task 8);
  `out/build/u-boot/.config`.

- [ ] **Step 1: Write the failing test**

`tests/uboot-config.sh`:

```sh
#!/bin/sh
# The built U-Boot config carries the vendor DRAM and rail values, no saved environment, and drives
# neither PB2 (BTN_THUMBR, the base config's backlight enable) nor VBUS. Its USB ACM console starts only on a
# FEL boot without a script, so a card boot never waits for a USB host; the board code probes the MUSB gadget,
# which upstream sunxi does only for USB Ethernet. Run: ./build.sh run tests/uboot-config.sh
set -eu
c=out/build/u-boot/.config
[ -f "$c" ] || { echo "FAIL: $c missing (./build.sh uboot)"; exit 1; }
fail=0
on() { grep -qxF "$1" "$c" || { echo "FAIL: want $1"; fail=1; }; }
off() { ! grep -q "^$1=" "$c" || { echo "FAIL: $1 must be off"; fail=1; }; }

on CONFIG_MACH_SUN8I_A33=y
on CONFIG_DRAM_CLK=552
on CONFIG_DRAM_ZQ=15291
on CONFIG_DRAM_ODT_EN=y
# vendor [power_sply]: dcdc1 3000, dcdc2 1100, dcdc3 1200, dcdc5 1500, aldo2 2500, aldo3 3000, dldo3 3000.
# aldo1 is not in the fex: 3000 is U-Boot's MACH_SUN8I default and the A33 reference design's vcc-io.
on CONFIG_AXP_DCDC1_VOLT=3000
on CONFIG_AXP_DCDC2_VOLT=1100
on CONFIG_AXP_DCDC3_VOLT=1200
on CONFIG_AXP_DCDC5_VOLT=1500
on CONFIG_AXP_ALDO1_VOLT=3000
on CONFIG_AXP_ALDO2_VOLT=2500
on CONFIG_AXP_ALDO3_VOLT=3000
on CONFIG_AXP_DLDO3_VOLT=3000
on CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y
on CONFIG_ENV_IS_NOWHERE=y
off CONFIG_REGULATOR_AXP           # DM regulators would apply the OLinuXino DT's 3.3 V rails
off CONFIG_VIDEO_SUNXI
off CONFIG_USB_MUSB_HOST
off CONFIG_REGULATOR_AXP_DRIVEVBUS
on CONFIG_USB_MUSB_GADGET=y
on CONFIG_USB_FUNCTION_ACM=y
on CONFIG_CONSOLE_MUX=y
off CONFIG_USB_ETHER                # would claim the gadget controller at boot
on 'CONFIG_PREBOOT="if test -n \"${fel_booted}\" && test -z \"${fel_scriptaddr}\"; then setenv bootdelay -1; setenv stdin serial,usbacm; setenv stdout serial,usbacm; setenv stderr serial,usbacm; fi"'
if grep '^CONFIG_ENV_IS_IN_.*=y' "$c"; then echo "FAIL: saved environment enabled"; fail=1; fi
# Strong symbol (T), not the weak no-op (W) of g_dnl.c: without it usbacm finds no controller.
arm-linux-gnueabihf-nm out/build/u-boot/u-boot | grep -q ' T board_usb_init$' \
	|| { echo "FAIL: board_usb_init not overridden"; fail=1; }
[ $fail = 0 ] && echo PASS
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/uboot-config.sh && ./build.sh run tests/uboot-config.sh`
Expected: `FAIL: out/build/u-boot/.config missing`.

- [ ] **Step 3: Write the implementation**

`uboot/ga36_defconfig` (from `A33-OLinuXino_defconfig`; changes: DRAM 552 MHz, rails, no video, MUSB as a gadget
instead of host, no USB Ethernet, no saved environment, power-off on plug-in power-on, and the ACM console on FEL
boots without a script. `CONS_INDEX` stays at its default 1: U-Boot's serial output goes to UART0 on `PB0`/`PB1`,
where nothing reads it. `fel_booted` and `fel_scriptaddr` are set in `board/sunxi/board.c` before the preboot runs,
and the preboot runs before `bootdelay` is read):

```
CONFIG_ARM=y
CONFIG_ARCH_SUNXI=y
CONFIG_DEFAULT_DEVICE_TREE="sun8i-a33-olinuxino"
CONFIG_DRAM_CLK=552
CONFIG_SPL=y
CONFIG_MACH_SUN8I_A33=y
CONFIG_DRAM_ZQ=15291
CONFIG_DRAM_ODT_EN=y
CONFIG_AXP_GPIO=y
CONFIG_AXP_DISABLE_BOOT_ON_POWERON=y
# CONFIG_VIDEO_SUNXI is not set
# CONFIG_SYS_MALLOC_CLEAR_ON_INIT is not set
CONFIG_ENV_IS_NOWHERE=y
# CONFIG_ENV_IS_IN_FAT is not set
CONFIG_AXP_DCDC1_VOLT=3000
CONFIG_AXP_DLDO3_VOLT=3000
# CONFIG_USB_MUSB_HOST is not set
CONFIG_USB_MUSB_GADGET=y
CONFIG_USB_GADGET=y
CONFIG_USB_GADGET_DOWNLOAD=y
CONFIG_USB_FUNCTION_ACM=y
# CONFIG_USB_ETHER is not set
CONFIG_CONSOLE_MUX=y
CONFIG_USE_PREBOOT=y
CONFIG_PREBOOT="if test -n \"${fel_booted}\" && test -z \"${fel_scriptaddr}\"; then setenv bootdelay -1; setenv stdin serial,usbacm; setenv stdout serial,usbacm; setenv stderr serial,usbacm; fi"
```

The ACM console needs one U-Boot patch. Without `DM_USB_GADGET`, `usbacm` asks `board_usb_init()` for the
controller, and sunxi leaves that as the weak no-op of `g_dnl.c`; the only code that probes `sunxi-musb` is
`usb_ether_init()`, which then holds the gadget itself. Create the tree and author the patch:

```bash
./build.sh run scripts/tree.sh prep u-boot
```

In `out/src/u-boot/board/sunxi/board.c`, add `#include <usb.h>` after `#include <spl.h>`, and insert before
`int board_late_init(void)`:

```c
#if defined(CONFIG_USB_MUSB_GADGET) && !defined(CONFIG_XPL_BUILD)
/* Probe the MUSB controller for gadget users other than USB Ethernet (usbacm, ums, fastboot). */
int board_usb_init(int index, enum usb_init_type init)
{
	struct udevice *dev;

	if (init != USB_INIT_DEVICE)
		return 0;

	return uclass_get_device(UCLASS_USB_GADGET_GENERIC, index, &dev);
}
#endif

```

```bash
git -C out/src/u-boot commit -s -am "sunxi: probe the MUSB gadget in board_usb_init" \
  -m "Without DM_USB_GADGET, gadget users find the controller through board_usb_init(), which sunxi leaves as the weak no-op. Only usb_ether_init() probes the sunxi-musb device, so with USB_ETHER off the ACM console, ums and fastboot fail with \"Controller uninitialized\". Probe the gadget device there."
./build.sh run scripts/tree.sh export u-boot && ls uboot/patches
```

Expected: `0001-sunxi-probe-the-MUSB-gadget-in-board_usb_init.patch`.

`scripts/build-uboot.sh`:

```sh
#!/bin/sh
# Build U-Boot for the GA36 and the FEL boot script. Runs inside the build container (./build.sh uboot).
set -eu
scripts/tree.sh prep u-boot
b=$PWD/out/build/u-boot
mkdir -p "$b" out/u-boot
cp uboot/ga36_defconfig "$b/.config"
make -C out/src/u-boot O="$b" CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
make -C out/src/u-boot O="$b" CROSS_COMPILE=arm-linux-gnueabihf- -j"$(nproc)"
cp "$b/u-boot-sunxi-with-spl.bin" out/u-boot/

# Sourced by U-Boot's "fel" boot target when sunxi-fel uploaded it (scripts/fel-boot.sh kernel).
# bootz returns only on failure; the console then moves to USB ACM so the error can be read.
cat > "$b/fel.cmd" <<'EOF'
setenv bootargs console=tty0 console=ttyGS0,115200 panic=5
bootz 0x42000000 0x43400000 0x43000000
setenv stdin serial,usbacm; setenv stdout serial,usbacm; setenv stderr serial,usbacm
echo bootz failed
EOF
"$b/tools/mkimage" -A arm -T script -C none -d "$b/fel.cmd" out/u-boot/fel.scr >/dev/null
```

In `build.sh`, replace the stage dispatch:

```sh
case $stage in
	run) [ $# -gt 0 ] || usage; run "$@" ;;
	*) usage ;;
esac
```

with:

```sh
case $stage in
	uboot) run scripts/build-uboot.sh ;;
	run) [ $# -gt 0 ] || usage; run "$@" ;;
	*) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/build-uboot.sh && ./build.sh uboot && ./build.sh run tests/uboot-config.sh && ls -l out/u-boot/`
Expected: `PASS`; `u-boot-sunxi-with-spl.bin` and `fel.scr` listed. Then check the series applies from scratch:
`mv out/src/u-boot out/src/u-boot.authoring && ./build.sh uboot && ./build.sh run tests/uboot-config.sh` prints
`PASS`; the authoring copy is then superseded (its commit is in `uboot/patches`): `rm -rf out/src/u-boot.authoring`. A `want CONFIG_PREBOOT=...` failure with the
option present means Kconfig re-escaped the string: compare `grep ^CONFIG_PREBOOT out/build/u-boot/.config` with the
test line and fix the test's quoting, not the condition.

- [ ] **Step 5: Commit**

```bash
git add uboot/ga36_defconfig uboot/patches scripts/build-uboot.sh build.sh tests/uboot-config.sh
git commit -m "Add GA36 U-Boot config and build stage"
```

---

### Task 4: FEL development loop

**Files:**
- Create: `scripts/70-ga36-usb.rules` (host udev rule, development only)
- Create: `scripts/board-run.sh` (host-side, development only)
- Create: `scripts/fel-boot.sh` (host-side, development only)

**Interfaces:**
- Consumes: `out/u-boot/u-boot-sunxi-with-spl.bin`, `out/u-boot/fel.scr` (Task 3); for `kernel` also
  `out/kernel/zImage`, `out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb` (Tasks 5, 6), `out/initramfs/initrd.uimg`
  (Task 8).
- Produces: host device links `/dev/ga36-uboot` (U-Boot ACM, `1f3a:1010`) and `/dev/ga36-linux` (kernel serial
  gadget, `0525:a4a7`), both ignored by ModemManager.
- Produces: `scripts/board-run.sh 'CMD'` - runs `CMD` in the board's shell (U-Boot or Linux), prints its output,
  exits 1 on timeout. Env: `TTY` (default `/dev/ga36-linux`), `TIMEOUT` seconds (default 30).
- Produces: `scripts/fel-boot.sh uboot|kernel` - uploads over FEL, waits for `/dev/ga36-uboot` or
  `/dev/ga36-linux`, then prints the output of `version` (U-Boot) or `uname -r` (Linux). Exit 1 on timeout, missing
  FEL device, plug-in power-off, a board that resets back into FEL, or (kernel) a failed `bootz`. Env: `SUNXI_FEL`,
  `TIMEOUT` seconds (default 90).

- [ ] **Step 1: Write the scripts**

`scripts/70-ga36-usb.rules`:

```
# Development only. Install: sudo cp scripts/70-ga36-usb.rules /etc/udev/rules.d/ && sudo udevadm control --reload
# GA36 consoles on the USB OTG cable. ModemManager would otherwise send AT commands into the shells.
# 1f3a:1010 U-Boot ACM console (FEL boots); 0525:a4a7 Linux serial gadget (g_serial, ttyGS0).
ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="1010", ENV{ID_MM_DEVICE_IGNORE}="1"
ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a7", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="1010", SYMLINK+="ga36-uboot"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a7", SYMLINK+="ga36-linux"
```

`scripts/board-run.sh`:

```sh
#!/bin/sh
# Development only. Run one command in the board's shell (U-Boot or Linux) over its USB console and print its output.
# Usage: scripts/board-run.sh 'CMD'
# Env: TTY (default /dev/ga36-linux; /dev/ga36-uboot for U-Boot), TIMEOUT seconds (default 30).
set -eu
TTY=${TTY:-/dev/ga36-linux}
TIMEOUT=${TIMEOUT:-30}
[ $# -eq 1 ] || { echo "usage: $0 'CMD'" >&2; exit 2; }
[ -e "$TTY" ] || { echo "$TTY missing: board not booted, cable out, or scripts/70-ga36-usb.rules not installed" >&2; exit 1; }
marker=__done_$$__
log=$(mktemp)
stty -F "$TTY" 115200 raw -echo
cat "$TTY" > "$log" &
cat_pid=$!
trap 'kill $cat_pid 2>/dev/null; rm -f "$log"' EXIT
printf '%s; echo %s\n' "$1" "$marker" > "$TTY"
end=$(( $(date +%s) + TIMEOUT ))
until tr -d '\r' < "$log" | grep -qx "$marker"; do
	[ "$(date +%s)" -lt "$end" ] || { echo "timeout after ${TIMEOUT}s: $1" >&2; exit 1; }
	sleep 0.2
done
# Print what follows the echoed command line, up to the marker line.
tr -d '\r' < "$log" | awk -v m="$marker" '$0 == m {exit} seen {print} index($0, m) {seen = 1}'
```

`scripts/fel-boot.sh`:

```sh
#!/bin/sh
# Development only, never part of an image.
# Boot the board over USB FEL and wait for its console on the same cable.
# Usage: scripts/fel-boot.sh uboot|kernel
#   uboot   U-Boot only; it skips autoboot and its prompt comes up on /dev/ga36-uboot
#   kernel  U-Boot, zImage, GA36 DTB and the test initramfs, booted by out/u-boot/fel.scr; shell on /dev/ga36-linux
# Env: SUNXI_FEL (default sunxi-fel), TIMEOUT seconds (default 90).
# Needs scripts/70-ga36-usb.rules installed. Prints `version` or `uname -r` from the board; exit 0 when it answered.
set -eu
cd "$(dirname "$0")/.."
FEL=${SUNXI_FEL:-sunxi-fel}
TIMEOUT=${TIMEOUT:-90}
usage() { echo "usage: $0 uboot|kernel" >&2; exit 2; }
[ $# -eq 1 ] || usage
mode=$1
in_fel() { lsusb -d 1f3a:efe8 >/dev/null; }

case $mode in
	uboot) dev=/dev/ga36-uboot probe=version
		set -- uboot out/u-boot/u-boot-sunxi-with-spl.bin ;;
	kernel) dev=/dev/ga36-linux probe='uname -r'
		set -- uboot out/u-boot/u-boot-sunxi-with-spl.bin \
		write 0x42000000 out/kernel/zImage \
		write 0x43000000 out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb \
		write 0x43400000 out/initramfs/initrd.uimg \
		write 0x43100000 out/u-boot/fel.scr ;;
	*) usage ;;
esac

# The boot ROM runs one upload per power-on; a second one hangs in usb_bulk_send().
if ! timeout 5 "$FEL" ver >/dev/null 2>&1; then
	echo "no board in FEL: power it off, remove the SD card, press the power key (one upload per power-on)" >&2
	exit 1
fi

if ! "$FEL" -v "$@"; then
	sleep 2
	if in_fel; then
		echo "FEL upload failed" >&2
	else
		# The SPL switches the board off when the power-on source was the charger (no UART to say so).
		echo "the board switched itself off during the upload: it was powered on by plugging in the cable; power it on with the power key" >&2
	fi
	exit 1
fi

sleep 3   # the boot ROM's FEL device disappears once U-Boot runs
end=$(( $(date +%s) + TIMEOUT ))
until [ -e "$dev" ]; do
	if in_fel; then
		echo "the board reset back into FEL (kernel panic?): FEL-boot again and read /sys/fs/pstore" >&2
		exit 1
	fi
	if [ "$mode" = kernel ] && [ -e /dev/ga36-uboot ]; then
		echo "bootz failed; U-Boot's console is on /dev/ga36-uboot:" >&2
		TTY=/dev/ga36-uboot scripts/board-run.sh 'printenv bootargs' >&2 || true
		exit 1
	fi
	if [ "$(date +%s)" -ge "$end" ]; then
		echo "timeout after ${TIMEOUT}s waiting for $dev" >&2
		exit 1
	fi
	sleep 1
done
TTY=$dev scripts/board-run.sh "$probe"
```

- [ ] **Step 2: Check it refuses without a board**

With the board off: `chmod +x scripts/board-run.sh scripts/fel-boot.sh && scripts/fel-boot.sh uboot`
Expected: exit 1, `no board in FEL: ...`.

- [ ] **Step 3: [person] Install the udev rule**

Person runs: `! sudo cp scripts/70-ga36-usb.rules /etc/udev/rules.d/ && sudo udevadm control --reload`
Check: `udevadm verify /etc/udev/rules.d/70-ga36-usb.rules` reports no errors (skip if this udev has no `verify`).

- [ ] **Step 4: [person] Enter FEL** - SD card out, cable to the PC, press the power key.

Check: `lsusb -d 1f3a:efe8` prints one line.

- [ ] **Step 5: Boot U-Boot to its USB console**

Run: `scripts/fel-boot.sh uboot`
Expected: output contains `U-Boot 2026.10`. Then prove the console is the ACM function and is ignored by
ModemManager: `lsusb -d 1f3a:1010` prints one line, `readlink -f /dev/ga36-uboot` is a `/dev/ttyACM*`, and
`udevadm info -q property /dev/ga36-uboot | grep -x ID_MM_DEVICE_IGNORE=1` matches. Then
`TTY=/dev/ga36-uboot scripts/board-run.sh 'echo $fel_booted; printenv bootdelay; coninfo'` prints `1`,
`bootdelay=-1`, and `usbacm` among the devices. If `/dev/ga36-uboot` never appears, take the U-Boot console risk
path in the Execution notes.

- [ ] **Step 6: [person] Plug-in power-on is refused (Review Focus 1)**

Person: power the board off, unplug the cable, wait 5 s, plug the cable in again and do **not** press the power key.
If the board powered on from the plug-in (`lsusb -d 1f3a:efe8` prints a line), run: `scripts/fel-boot.sh uboot`
Expected: exit 1 with `the board switched itself off during the upload ...`, and afterwards
`lsusb -d 1f3a:efe8` prints nothing (the injection took effect: the board is off, not hung). If `lsusb` showed
nothing before the run, the board does not power on from the plug-in; record that (Task 9, step 10) and skip.

- [ ] **Step 7: Second upload is refused**

Person: power-cycle into FEL (step 4). Run `scripts/fel-boot.sh uboot`, then in the same power cycle again:
`time scripts/fel-boot.sh uboot`
Expected: the second run exits 1 with `no board in FEL: ...` in about 5 s instead of hanging.

- [ ] **Step 8: Commit**

```bash
git add scripts/70-ga36-usb.rules scripts/board-run.sh scripts/fel-boot.sh
git commit -m "Add FEL boot and USB console helpers for the development loop"
```

---

### Task 5: Kernel tree, config fragment and build

**Files:**
- Create: `kernel/ga36.config`
- Create: `scripts/build-kernel.sh`
- Modify: `build.sh` (stage dispatch)
- Test: `tests/kernel-config.sh`

**Interfaces:**
- Consumes: `scripts/tree.sh prep linux` (Task 2).
- Produces: `out/kernel/zImage`; build dir `out/build/linux` (`.config` there); helper to run kernel make targets:
  `./build.sh run make -C out/src/linux O=/work/out/build/linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- <target>`.

- [ ] **Step 1: Write the failing test**

`tests/kernel-config.sh`:

```sh
#!/bin/sh
# Every option in kernel/ga36.config survived merge_config and olddefconfig (a dropped option means a
# missing dependency or a renamed symbol). Run: ./build.sh run tests/kernel-config.sh
set -eu
c=out/build/linux/.config
[ -f "$c" ] || { echo "FAIL: $c missing (./build.sh kernel)"; exit 1; }
fail=0
for opt in $(grep '^CONFIG_' kernel/ga36.config); do
	grep -qx "$opt" "$c" || { echo "FAIL: $opt not in final config ($(grep "^${opt%%=*}=" "$c" || echo unset))"; fail=1; }
done
[ $fail = 0 ] && echo PASS
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/kernel-config.sh && ./build.sh run tests/kernel-config.sh`
Expected: `FAIL: out/build/linux/.config missing`.

- [ ] **Step 3: Write the implementation**

`kernel/ga36.config` (applied on top of `sunxi_defconfig`; everything built in, the bring-up loop loads no modules):

```
# Display: A33 display engine, DSI, NV3051D panel, Mali-400, backlight, fbdev for the test pattern
CONFIG_DRM=y
CONFIG_DRM_SUN4I=y
CONFIG_DRM_SUN6I_DSI=y
CONFIG_PHY_SUN6I_MIPI_DPHY=y
CONFIG_DRM_PANEL_NEWVISION_NV3051D=y
CONFIG_DRM_LIMA=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_PWM=y
CONFIG_PWM_SUN4I=y
CONFIG_BACKLIGHT_CLASS_DEVICE=y
CONFIG_BACKLIGHT_PWM=y
# Input: polled buttons (PE has no interrupts), AXP power key
CONFIG_INPUT_EVDEV=y
CONFIG_KEYBOARD_GPIO_POLLED=y
CONFIG_INPUT_AXP20X_PEK=y
# Power: AXP223 on RSB, rails, ADC, charger, battery, USB power
CONFIG_MFD_AXP20X_RSB=y
CONFIG_REGULATOR_AXP20X=y
CONFIG_AXP20X_ADC=y
CONFIG_AXP20X_POWER=y
CONFIG_CHARGER_AXP20X=y
CONFIG_BATTERY_AXP20X=y
# Audio: internal codec, I2S, simple card, speaker amplifier enable
CONFIG_SND_SUN8I_CODEC=y
CONFIG_SND_SUN8I_CODEC_ANALOG=y
CONFIG_SND_SUN4I_I2S=y
CONFIG_SND_SIMPLE_CARD=y
CONFIG_SND_SOC_SIMPLE_AMPLIFIER=y
# CPU frequency and thermal
CONFIG_CPUFREQ_DT=y
CONFIG_THERMAL=y
CONFIG_CPU_THERMAL=y
CONFIG_SUN8I_THERMAL=y
# Storage and memory
CONFIG_EXFAT_FS=y
CONFIG_ZRAM=y
# USB OTG; the built-in serial gadget is the console (ttyGS0, host sees 0525:a4a7) from boot
CONFIG_USB_MUSB_HDRC=y
CONFIG_USB_MUSB_DUAL_ROLE=y
CONFIG_USB_MUSB_SUNXI=y
CONFIG_PHY_SUN4I_USB=y
CONFIG_USB_GADGET=y
CONFIG_USB_G_SERIAL=y
CONFIG_U_SERIAL_CONSOLE=y
# Console on the panel once it works
CONFIG_FRAMEBUFFER_CONSOLE=y
# Crash logs kept in RAM across the reset (ramoops region in the DTS), reset on panic by the watchdog
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_WATCHDOG=y
CONFIG_SUNXI_WATCHDOG=y
CONFIG_MAGIC_SYSRQ=y
# Boot and debugging
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_SUSPEND=y
CONFIG_DEBUG_FS=y
```

`scripts/build-kernel.sh`:

```sh
#!/bin/sh
# Build the GA36 kernel: sunxi_defconfig plus kernel/ga36.config. Runs inside the build container (./build.sh kernel).
set -eu
scripts/tree.sh prep linux
src=out/src/linux
b=$PWD/out/build/linux
mkdir -p "$b" out/kernel
k() { make -C "$src" O="$b" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- "$@"; }
k sunxi_defconfig
"$src/scripts/kconfig/merge_config.sh" -m -O "$b" "$b/.config" kernel/ga36.config
k olddefconfig
k -j"$(nproc)" zImage
cp "$b/arch/arm/boot/zImage" out/kernel/
```

In `build.sh`, add the stage below the `uboot)` line:

```sh
	kernel) run scripts/build-kernel.sh ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/build-kernel.sh && ./build.sh kernel && ./build.sh run tests/kernel-config.sh`
Expected: `PASS`. If an option is reported dropped, the message shows its final value; fix the fragment with the
missing dependency (check `make ... menuconfig` search output via `./build.sh run make ... menuconfig`), never by
deleting the line from the test's view.

- [ ] **Step 5: Commit**

```bash
git add kernel/ga36.config scripts/build-kernel.sh build.sh tests/kernel-config.sh
git commit -m "Add kernel config fragment and build stage"
```

---

### Task 6: Bindings and board DTS

**Files:**
- Modify (in `out/src/linux`): `Documentation/devicetree/bindings/vendor-prefixes.yaml`,
  `Documentation/devicetree/bindings/display/panel/newvision,nv3051d.yaml`,
  `Documentation/devicetree/bindings/arm/sunxi.yaml`, `arch/arm/boot/dts/allwinner/Makefile`
- Create (in `out/src/linux`): `arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`
- Create: `kernel/patches/0001..0004-*.patch` (by `scripts/tree.sh export linux`)
- Modify: `scripts/build-kernel.sh`
- Test: `tests/dtb.sh`, `tests/dt-schema.sh`

**Interfaces:**
- Consumes: Task 5 build.
- Produces: `out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb`. DT facts later tasks rely on: root compatible
  `"gameconsole,r36s-ga36", "allwinner,sun8i-a33"`; panel compatible `"gameconsole,r36s-ga36-panel",
  "newvision,nv3051d"`; backlight `/sys/class/backlight/backlight`; input device name `gpio-keys`; regulator names
  `vcc-3v0 vdd-sys vdd-cpu vcc-dram vcc-io vdd-dll vcc-pll-avcc vcc-dldo3 vdd-cpus vcc-lcd usb0-vbus`.

- [ ] **Step 1: Write the failing tests**

`tests/dtb.sh`:

```sh
#!/bin/sh
# Guard rails and wiring of the GA36 DTB: no rail or OPP above the vendor (or, where the vendor sets none, the
# A33 reference design) values, U-Boot's rails always on,
# CPU on DCDC3, charge limits from [pmu1_para], all 17 buttons. Run: ./build.sh run tests/dtb.sh
set -eu
d=out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb
[ -f "$d" ] || { echo "FAIL: $d missing (./build.sh kernel)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
R=/soc/rsb@1f03400/pmic@3a3/regulators   # node names from axp22x.dtsi

[ "$(fdtget "$d" / compatible)" = "gameconsole,r36s-ga36 allwinner,sun8i-a33" ] || bad "root compatible"

# Limits: vendor [power_sply] (dcdc3: the highest vendor DVFS voltage allowed so far); aldo1 and dc5ldo are not in
# the fex, so theirs are the A33 reference design's (sina33).
for row in vendor:dcdc1:3000000 vendor:dcdc2:1100000 vendor:dcdc3:1200000 vendor:dcdc5:1500000 \
	vendor:aldo2:2500000 vendor:aldo3:3000000 vendor:dldo3:3000000 reference:aldo1:3000000 reference:dc5ldo:1400000; do
	src=${row%%:*} row=${row#*:}
	n=${row%%:*} lim=${row#*:}
	max=$(fdtget -t u "$d" "$R/$n" regulator-max-microvolt) || { bad "$n has no voltage limit"; continue; }
	[ "$max" -le "$lim" ] || bad "$n max $max uV above $src $lim uV"
	fdtget "$d" "$R/$n" regulator-always-on >/dev/null 2>&1 || bad "$n not always-on"
done

[ "$(fdtget -t x "$d" /cpus/cpu@0 cpu-supply)" = "$(fdtget -t x "$d" "$R/dcdc3" phandle)" ] \
	|| bad "cpu-supply is not dcdc3"

# Vendor [dvfs_table]: 648 MHz 1.04 V, 816 MHz 1.10 V, 1008 MHz 1.20 V, 1200 MHz 1.32 V; max_freq 1.2 GHz.
vendor_uv() {
	for row in 648000000:1040000 816000000:1100000 1008000000:1200000 1200000000:1320000; do
		[ "$1" -le "${row%%:*}" ] && { echo "${row#*:}"; return; }
	done
	echo 0
}
for n in $(fdtget -l "$d" /opp-table-cpu); do
	f=${n#opp-}
	uv=$(fdtget -t u "$d" "/opp-table-cpu/$n" opp-microvolt | cut -d' ' -f1)
	lim=$(vendor_uv "$f")
	[ "$uv" -le "$lim" ] || bad "$n at $uv uV above vendor $lim uV"
done

# Charging from [pmu1_para]: pmu_runtime_chgcur 300 mA, pmu_init_chgvol 4200 mV.
[ "$(fdtget -t u "$d" /battery constant-charge-current-max-microamp)" = 300000 ] || bad "charge current"
[ "$(fdtget -t u "$d" /battery constant-charge-voltage-max-microvolt)" = 4200000 ] || bad "charge voltage"

# BTN_SOUTH..BTN_THUMBR, KEY_FN, BTN_DPAD_*.
codes=$(for n in $(fdtget -l "$d" /gpio-keys); do fdtget -t u "$d" "/gpio-keys/$n" linux,code; done | sort -n | tr '\n' ' ')
[ "$codes" = "304 305 307 308 310 311 312 313 314 315 317 318 464 544 545 546 547 " ] || bad "button codes: $codes"

[ $fail = 0 ] && echo PASS
exit $fail
```

`tests/dt-schema.sh`:

```sh
#!/bin/sh
# Schema checks: the bindings this series touches, and the GA36 DTB against all schemas.
# Run: ./build.sh run tests/dt-schema.sh
set -eu
k() { make -C out/src/linux O="$PWD/out/build/linux" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- "$@"; }
log=out/build/dt-schema.log
{
	k dt_binding_check DT_SCHEMA_FILES="vendor-prefixes.yaml:newvision,nv3051d.yaml:arm/sunxi.yaml"
	k CHECK_DTBS=y allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb
} > "$log" 2>&1 || { tail -30 "$log"; echo "FAIL: make failed"; exit 1; }
if grep -E 'sun8i-a33-gameconsole|nv3051d|vendor-prefixes|sunxi.yaml' "$log" | grep -iE 'warning|error'; then
	echo "FAIL: schema warnings above"
	exit 1
fi
echo PASS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `chmod +x tests/dtb.sh tests/dt-schema.sh && ./build.sh run tests/dtb.sh; ./build.sh run tests/dt-schema.sh`
Expected: `FAIL: out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb missing`; `FAIL: make failed` (no rule for the DTB).

- [ ] **Step 3: Vendor prefix commit (in `out/src/linux`)**

In `Documentation/devicetree/bindings/vendor-prefixes.yaml`, after the `"^galaxycore,.*"` entry and before
`"^gameforce,.*"`, insert:

```yaml
  "^gameconsole,.*":
    description: GameConsole
```

```bash
git -C out/src/linux commit -s -am "dt-bindings: vendor-prefixes: add GameConsole" \
  -m "GameConsole is the brand on R36S handheld clones, among them the Allwinner A33 based GA36-MB board."
```

- [ ] **Step 4: Panel binding commit**

In `Documentation/devicetree/bindings/display/panel/newvision,nv3051d.yaml`, the compatible enum becomes:

```yaml
      - enum:
          - anbernic,rg351v-panel
          - anbernic,rg353p-panel
          - gameconsole,r36s-ga36-panel
          - powkiddy,rk2023-panel
```

```bash
git -C out/src/linux commit -s -am "dt-bindings: display: panel: nv3051d: add GA36 panel" \
  -m "The GameConsole R36S GA36-MB uses an NV3051D based 640x480 panel on a 2-lane DSI link."
```

- [ ] **Step 5: Board binding commit**

In `Documentation/devicetree/bindings/arm/sunxi.yaml`, after the `FriendlyARM ZeroPi` entry and before
`Gemei G9 Tablet`, insert:

```yaml
      - description: GameConsole R36S GA36-MB
        items:
          - const: gameconsole,r36s-ga36
          - const: allwinner,sun8i-a33
```

```bash
git -C out/src/linux commit -s -am "dt-bindings: arm: sunxi: add GameConsole R36S GA36-MB"
```

- [ ] **Step 6: Board DTS commit**

In `arch/arm/boot/dts/allwinner/Makefile` (alphabetical list), after the line `	sun8i-a33-ga10h-v1.1.dtb \`
and before `	sun8i-a33-inet-d978-rev2.dtb \`, insert:

```make
	sun8i-a33-gameconsole-r36s-ga36.dtb \
```

Create `arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`:

```dts
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/*
 * GameConsole R36S clone with the GA36-MB V1.0-20250730 board (Allwinner A33, AXP223).
 */

/dts-v1/;
#include "sun8i-a33.dtsi"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	model = "GameConsole R36S GA36-MB";
	compatible = "gameconsole,r36s-ga36", "allwinner,sun8i-a33";

	backlight: backlight {
		compatible = "pwm-backlight";
		pwms = <&pwm 0 50000 0>;
		brightness-levels = <0 10 20 30 40 50 60 70 80 90 100>;
		default-brightness-level = <8>;
	};

	battery: battery {
		compatible = "simple-battery";
		charge-full-design-microamp-hours = <3000000>;
		voltage-min-design-microvolt = <3300000>;
		constant-charge-voltage-max-microvolt = <4200000>;
		constant-charge-current-max-microamp = <300000>;
	};

	gpio-keys {
		compatible = "gpio-keys-polled";
		pinctrl-names = "default";
		pinctrl-0 = <&key_pins>;
		poll-interval = <10>;

		button-south {
			label = "SOUTH";
			linux,code = <BTN_SOUTH>;
			gpios = <&pio 4 13 GPIO_ACTIVE_LOW>; /* PE13 */
		};

		button-east {
			label = "EAST";
			linux,code = <BTN_EAST>;
			gpios = <&pio 4 12 GPIO_ACTIVE_LOW>; /* PE12 */
		};

		button-north {
			label = "NORTH";
			linux,code = <BTN_NORTH>;
			gpios = <&pio 4 11 GPIO_ACTIVE_LOW>; /* PE11 */
		};

		button-west {
			label = "WEST";
			linux,code = <BTN_WEST>;
			gpios = <&pio 4 10 GPIO_ACTIVE_LOW>; /* PE10 */
		};

		button-tl {
			label = "TL";
			linux,code = <BTN_TL>;
			gpios = <&pio 4 15 GPIO_ACTIVE_LOW>; /* PE15 */
		};

		button-tr {
			label = "TR";
			linux,code = <BTN_TR>;
			gpios = <&pio 4 17 GPIO_ACTIVE_LOW>; /* PE17 */
		};

		button-tl2 {
			label = "TL2";
			linux,code = <BTN_TL2>;
			gpios = <&pio 4 14 GPIO_ACTIVE_LOW>; /* PE14 */
		};

		button-tr2 {
			label = "TR2";
			linux,code = <BTN_TR2>;
			gpios = <&pio 4 16 GPIO_ACTIVE_LOW>; /* PE16 */
		};

		button-select {
			label = "SELECT";
			linux,code = <BTN_SELECT>;
			gpios = <&pio 4 5 GPIO_ACTIVE_LOW>; /* PE5 */
		};

		button-start {
			label = "START";
			linux,code = <BTN_START>;
			gpios = <&pio 4 4 GPIO_ACTIVE_LOW>; /* PE4 */
		};

		button-thumbl {
			label = "THUMBL";
			linux,code = <BTN_THUMBL>;
			gpios = <&pio 1 3 GPIO_ACTIVE_LOW>; /* PB3 */
		};

		button-thumbr {
			label = "THUMBR";
			linux,code = <BTN_THUMBR>;
			gpios = <&pio 1 2 GPIO_ACTIVE_LOW>; /* PB2 */
		};

		button-up {
			label = "DPAD-UP";
			linux,code = <BTN_DPAD_UP>;
			gpios = <&pio 4 9 GPIO_ACTIVE_LOW>; /* PE9 */
		};

		button-down {
			label = "DPAD-DOWN";
			linux,code = <BTN_DPAD_DOWN>;
			gpios = <&pio 4 8 GPIO_ACTIVE_LOW>; /* PE8 */
		};

		button-left {
			label = "DPAD-LEFT";
			linux,code = <BTN_DPAD_LEFT>;
			gpios = <&pio 4 7 GPIO_ACTIVE_LOW>; /* PE7 */
		};

		button-right {
			label = "DPAD-RIGHT";
			linux,code = <BTN_DPAD_RIGHT>;
			gpios = <&pio 4 6 GPIO_ACTIVE_LOW>; /* PE6 */
		};

		button-fn {
			label = "FN";
			linux,code = <KEY_FN>;
			gpios = <&pio 4 1 GPIO_ACTIVE_LOW>; /* PE1 */
		};
	};

	speaker_amp: audio-amplifier {
		compatible = "simple-audio-amplifier";
		enable-gpios = <&pio 7 9 GPIO_ACTIVE_HIGH>; /* PH9 */
		sound-name-prefix = "Speaker Amp";
	};

};

&ac_power_supply {
	status = "okay";
};

&battery_power_supply {
	monitored-battery = <&battery>;
	status = "okay";
};

&codec {
	status = "okay";
};

&cpu0 {
	cpu-supply = <&reg_dcdc3>;
};

&dai {
	status = "okay";
};

&de {
	status = "okay";
};

&dphy {
	status = "okay";
};

&dsi {
	status = "okay";

	panel@0 {
		compatible = "gameconsole,r36s-ga36-panel", "newvision,nv3051d";
		reg = <0>;
		backlight = <&backlight>;
		reset-gpios = <&pio 7 7 GPIO_ACTIVE_LOW>; /* PH7 */
		vdd-supply = <&reg_dc1sw>;
	};
};

&mmc0 {
	vmmc-supply = <&reg_dcdc1>;
	bus-width = <4>;
	cd-gpios = <&pio 1 4 GPIO_ACTIVE_LOW>; /* PB4 */
	status = "okay";
};

&pio {
	key_pins: key-pins {
		pins = "PB2", "PB3", "PE1", "PE4", "PE5", "PE6", "PE7", "PE8", "PE9",
		       "PE10", "PE11", "PE12", "PE13", "PE14", "PE15", "PE16", "PE17";
		function = "gpio_in";
		bias-pull-up;
	};
};

&pwm {
	pinctrl-names = "default";
	pinctrl-0 = <&pwm0_pin>;
	status = "okay";
};

&r_rsb {
	status = "okay";

	axp22x: pmic@3a3 {
		compatible = "x-powers,axp223";
		reg = <0x3a3>;
		interrupt-parent = <&r_intc>;
		interrupts = <GIC_SPI 32 IRQ_TYPE_LEVEL_LOW>;
		eldoin-supply = <&reg_dcdc1>;
		x-powers,drive-vbus-en;
	};
};

#include "axp223.dtsi"

/*
 * Every rail U-Boot sets is always-on: without a consumer the kernel would switch it off 30 s after boot.
 * Voltages are the vendor [power_sply] values, never higher. ALDO1 and DC5LDO are not in [power_sply]: their
 * values are the A33 reference design's (sina33), and ALDO1's 3.0 V is also U-Boot's default, which the SPL
 * already set during the FEL tests.
 */
&reg_aldo1 {
	regulator-always-on;
	regulator-min-microvolt = <3000000>;
	regulator-max-microvolt = <3000000>;
	regulator-name = "vcc-io";
};

&reg_aldo2 {
	regulator-always-on;
	regulator-min-microvolt = <2500000>;
	regulator-max-microvolt = <2500000>;
	regulator-name = "vdd-dll";
};

&reg_aldo3 {
	regulator-always-on;
	regulator-min-microvolt = <3000000>;
	regulator-max-microvolt = <3000000>;
	regulator-name = "vcc-pll-avcc";
};

&reg_dc1sw {
	regulator-name = "vcc-lcd";
};

&reg_dc5ldo {
	regulator-always-on;
	regulator-min-microvolt = <900000>;
	regulator-max-microvolt = <1400000>;
	regulator-name = "vdd-cpus";
};

&reg_dcdc1 {
	regulator-always-on;
	regulator-min-microvolt = <3000000>;
	regulator-max-microvolt = <3000000>;
	regulator-name = "vcc-3v0";
};

&reg_dcdc2 {
	regulator-always-on;
	regulator-min-microvolt = <1100000>;
	regulator-max-microvolt = <1100000>;
	regulator-name = "vdd-sys";
};

/* Vendor boot value 1.2 V; raised to the 1.2 GHz DVFS value only in a later step. */
&reg_dcdc3 {
	regulator-always-on;
	regulator-min-microvolt = <1040000>;
	regulator-max-microvolt = <1200000>;
	regulator-name = "vdd-cpu";
};

&reg_dcdc5 {
	regulator-always-on;
	regulator-min-microvolt = <1500000>;
	regulator-max-microvolt = <1500000>;
	regulator-name = "vcc-dram";
};

/* Set by the vendor firmware; consumer unknown. */
&reg_dldo3 {
	regulator-always-on;
	regulator-min-microvolt = <3000000>;
	regulator-max-microvolt = <3000000>;
	regulator-name = "vcc-dldo3";
};

&reg_drivevbus {
	regulator-name = "usb0-vbus";
	status = "okay";
};

&sound {
	simple-audio-card,aux-devs = <&codec_analog>, <&speaker_amp>;
	simple-audio-card,widgets = "Headphone", "Headphone Jack",
				    "Speaker", "Internal Speaker";
	simple-audio-card,routing =
		"Left DAC", "DACL",
		"Right DAC", "DACR",
		"HP", "HPCOM",
		"Headphone Jack", "HP",
		"Speaker Amp INL", "HP",
		"Speaker Amp INR", "HP",
		"Internal Speaker", "Speaker Amp OUTL",
		"Internal Speaker", "Speaker Amp OUTR";
	status = "okay";
};

&tcon0 {
	status = "okay";
};

/* The analog stick MCU; its driver comes in v1.1. */
&uart1 {
	pinctrl-names = "default";
	pinctrl-0 = <&uart1_pg_pins>;
	status = "okay";
};

&usb_otg {
	dr_mode = "otg";
	status = "okay";
};

&usb_power_supply {
	status = "okay";
};

&usbphy {
	usb0_id_det-gpios = <&pio 7 8 (GPIO_ACTIVE_HIGH | GPIO_PULL_UP)>; /* PH8 */
	usb0_vbus_power-supply = <&usb_power_supply>;
	usb0_vbus-supply = <&reg_drivevbus>;
	status = "okay";
};
```

```bash
git -C out/src/linux add arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts
git -C out/src/linux commit -s -am "ARM: dts: sun8i: a33: add GA36-MB V1.0" \
  -m "Add the GameConsole R36S clone built on the GA36-MB V1.0 board: AXP223 rails at the vendor values, DSI panel, PWM backlight, polled buttons (the PE bank has no interrupts), SD card, codec with speaker amplifier, and USB OTG."
```

- [ ] **Step 7: Build the DTB in the kernel stage and export the series**

In `scripts/build-kernel.sh`, replace the last two lines:

```sh
k -j"$(nproc)" zImage
cp "$b/arch/arm/boot/zImage" out/kernel/
```

with:

```sh
k -j"$(nproc)" zImage allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb
cp "$b/arch/arm/boot/zImage" "$b/arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb" out/kernel/
```

Run: `scripts/tree.sh export linux && ls kernel/patches`
Expected: four files, `0001-dt-bindings-vendor-prefixes-add-GameConsole.patch` through
`0004-ARM-dts-sun8i-a33-add-GA36-MB-V1.0.patch`.

- [ ] **Step 8: Run tests to verify they pass**

Run: `./build.sh kernel && ./build.sh run tests/dtb.sh && ./build.sh run tests/dt-schema.sh`
Expected: `PASS`, `PASS`. A failing `tests/dtb.sh` path means a node name differs from `axp22x.dtsi`; fix the path
in the test after checking `fdtget -l out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb /soc/rsb@1f03400/pmic@3a3/regulators`,
never the limit.

- [ ] **Step 9: Check the series applies from scratch**

Run: `mv out/src/linux out/src/linux.authoring && ./build.sh kernel && ./build.sh run tests/dtb.sh && git -C out/src/linux log --oneline ga36-base..HEAD`
Expected: `PASS`, four commits. Then the authoring copy is superseded (its commits are in `kernel/patches`):
`rm -rf out/src/linux.authoring`.

- [ ] **Step 10: Commit**

```bash
git add kernel/patches scripts/build-kernel.sh tests/dtb.sh tests/dt-schema.sh
git commit -m "Add GA36 board DTS and bindings"
```

---

### Task 7: NV3051D panel variant

**Files:**
- Modify (in `out/src/linux`): `drivers/gpu/drm/panel/panel-newvision-nv3051d.c`
- Create: `scripts/panel-init-to-c.sh`
- Create: `kernel/patches/0005-*.patch`, `kernel/patches/0006-*.patch` (by export)
- Test: `tests/panel-init.sh`

**Interfaces:**
- Consumes: `docs/hardware/panel-init.txt`; Task 6 DT (panel compatible `gameconsole,r36s-ga36-panel`).
- Produces: `struct nv3051d_panel_info` gains `unsigned int lanes` and
  `int (*init_sequence)(struct panel_nv3051d *ctx)`; `scripts/panel-init-to-c.sh FILE` prints the
  `mipi_dsi_dcs_write_seq_multi()` lines for every table entry before `11` (exit sleep).

- [ ] **Step 1: Write the failing test**

`scripts/panel-init-to-c.sh`:

```sh
#!/bin/sh
# Print the vendor DSI init table (docs/hardware/panel-init.txt) as mipi_dsi_dcs_write_seq_multi() lines.
# Stops at "11" (exit sleep): the driver sends exit sleep and display on itself.
# Usage: scripts/panel-init-to-c.sh docs/hardware/panel-init.txt
set -eu
awk '/^#/ {next} $1 == "11" {exit} {printf "\tmipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x%s, 0x%s);\n", toupper($1), toupper($2)}' "$1"
```

`tests/panel-init.sh`:

```sh
#!/bin/sh
# The GA36 init sequence in the kernel patch is exactly the vendor table, in order (146 writes).
# Run: ./build.sh run tests/panel-init.sh
set -eu
p=$(ls kernel/patches/*-drm-panel-nv3051d-add-GA36-panel.patch 2>/dev/null) || { echo "FAIL: GA36 panel patch missing"; exit 1; }
want=$(scripts/panel-init-to-c.sh docs/hardware/panel-init.txt)
have=$(grep '^+	mipi_dsi_dcs_write_seq_multi' "$p" | sed 's/^+//')
[ "$(echo "$want" | wc -l)" = 146 ] || { echo "FAIL: table has $(echo "$want" | wc -l) entries, expected 146"; exit 1; }
[ "$want" = "$have" ] || { echo "FAIL: patch differs from panel-init.txt"; exit 1; }
echo PASS
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/panel-init-to-c.sh tests/panel-init.sh && ./build.sh run tests/panel-init.sh`
Expected: `FAIL: GA36 panel patch missing`.

- [ ] **Step 3: Per-panel lanes and init sequence (in `out/src/linux`)**

In `drivers/gpu/drm/panel/panel-newvision-nv3051d.c`:

Replace the `struct nv3051d_panel_info` definition with:

```c
struct panel_nv3051d;

struct nv3051d_panel_info {
	const struct drm_display_mode *display_modes;
	unsigned int num_modes;
	u16 width_mm, height_mm;
	u32 bus_flags;
	u32 mode_flags;
	unsigned int lanes;
	int (*init_sequence)(struct panel_nv3051d *ctx);
};
```

In `panel_nv3051d_prepare()`, replace `ret = panel_nv3051d_init_sequence(ctx);` with:

```c
	ret = ctx->panel_info->init_sequence(ctx);
```

In `panel_nv3051d_probe()`, replace `dsi->lanes = 4;` with:

```c
	dsi->lanes = ctx->panel_info->lanes;
```

In each of `nv3051d_rg351v_info`, `nv3051d_rg353p_info` and `nv3051d_rk2023_info`, add after the `.mode_flags`
initializer:

```c
	.lanes = 4,
	.init_sequence = panel_nv3051d_init_sequence,
```

Build: `./build.sh kernel` (no warnings in `panel-newvision-nv3051d.c`).

```bash
git -C out/src/linux commit -s -am "drm/panel: nv3051d: make lane count and init sequence per-panel" \
  -m "All supported panels use four DSI lanes and share one init sequence. Move both into the panel info so a panel with a different lane count and its own vendor sequence can be added. No functional change for the existing panels."
```

- [ ] **Step 4: Add the GA36 panel**

In the same file, after the closing brace of `panel_nv3051d_init_sequence()`, add the function. The 146 write
lines come from `scripts/panel-init-to-c.sh docs/hardware/panel-init.txt` (run it on the host; paste its output in
place of the marked line):

```c
static int panel_nv3051d_ga36_init_sequence(struct panel_nv3051d *ctx)
{
	struct mipi_dsi_device *dsi = to_mipi_dsi_device(ctx->dev);
	struct mipi_dsi_multi_context dsi_ctx = {.dsi = dsi};

	/* Taken from the vendor lcd.ko of the GA36-MB, no documentation. */
	/* <output of scripts/panel-init-to-c.sh docs/hardware/panel-init.txt> */

	return dsi_ctx.accum_err;
}
```

One way to do the paste exactly:

```bash
f=out/src/linux/drivers/gpu/drm/panel/panel-newvision-nv3051d.c
scripts/panel-init-to-c.sh docs/hardware/panel-init.txt > out/ga36-init.inc
sed -i -e '/\/\* <output of scripts\/panel-init-to-c.sh/{r out/ga36-init.inc' -e 'd}' "$f"
rm out/ga36-init.inc
```

After `nv3051d_rk2023_modes[]`, add:

```c
/* Vendor timings: lcd_ht 1040, lcd_hbp 120 (includes hspw 40), lcd_vt 518, lcd_vbp 12 (includes vspw 6). */
static const struct drm_display_mode nv3051d_ga36_modes[] = {
	{ /* 55.7 Hz */
		.hdisplay	= 640,
		.hsync_start	= 640 + 280,
		.hsync_end	= 640 + 280 + 40,
		.htotal		= 640 + 280 + 40 + 80,
		.vdisplay	= 480,
		.vsync_start	= 480 + 26,
		.vsync_end	= 480 + 26 + 6,
		.vtotal		= 480 + 26 + 6 + 6,
		.clock		= 30000,
		.flags		= DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC,
	},
};
```

After `nv3051d_rk2023_info`, add:

```c
static const struct nv3051d_panel_info nv3051d_ga36_info = {
	.display_modes = nv3051d_ga36_modes,
	.num_modes = ARRAY_SIZE(nv3051d_ga36_modes),
	.width_mm = 71,
	.height_mm = 53,
	.bus_flags = DRM_BUS_FLAG_DE_LOW | DRM_BUS_FLAG_PIXDATA_DRIVE_NEGEDGE,
	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST |
		      MIPI_DSI_MODE_LPM,
	.lanes = 2,
	.init_sequence = panel_nv3051d_ga36_init_sequence,
};
```

In `newvision_nv3051d_of_match[]`, after the `anbernic,rg353p-panel` entry, add:

```c
	{ .compatible = "gameconsole,r36s-ga36-panel", .data = &nv3051d_ga36_info },
```

Build: `./build.sh kernel`.

```bash
git -C out/src/linux commit -s -am "drm/panel: nv3051d: add GA36 panel" \
  -m "Add the 640x480 panel of the GameConsole R36S GA36-MB board. It uses two DSI lanes with EoT packets, its own vendor init sequence and a 30 MHz mode (55.7 Hz) taken from the vendor timings."
```

- [ ] **Step 5: Export and run tests**

Run: `scripts/tree.sh export linux && ./build.sh kernel && ./build.sh run tests/panel-init.sh && ./build.sh run tests/dtb.sh`
Expected: six patches in `kernel/patches`; `PASS`, `PASS`.

- [ ] **Step 6: Commit**

```bash
git add kernel/patches scripts/panel-init-to-c.sh tests/panel-init.sh
git commit -m "Add NV3051D GA36 panel patches"
```

---

### Task 8: Test initramfs and first kernel boot over FEL

**Files:**
- Create: `scripts/make-test-initramfs.sh`
- Create: `tests/initramfs/init`
- Modify: `build.sh` (stage dispatch)
- Modify (in `out/src/linux`): `arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`
- Create: `kernel/patches/0007-ARM-dts-sun8i-a33-ga36-reserve-a-ramoops-region.patch` (by export; kept in this
  repository only, never sent upstream)
- Test: `tests/dtb.sh`

**Interfaces:**
- Consumes: `out/build/u-boot/tools/mkimage` (Task 3); `scripts/fel-boot.sh kernel`, `scripts/board-run.sh`
  (Task 4); kernel and DTB (Tasks 5-7).
- Produces: a ramoops region at `0x49000000` (1 MiB) in the GA36 DTB, as its own last patch.
- Produces: `out/initramfs/initrd.cpio.gz` (raw, for extlinux) and `out/initramfs/initrd.uimg` (for FEL); on the
  board a root shell on the serial gadget `ttyGS0` (host `/dev/ga36-linux`), pstore mounted at `/sys/fs/pstore`,
  `/bars.raw` (640x480 XRGB8888).

- [ ] **Step 1: Add the failing ramoops check**

The crash-log region is a repo-only patch on top of the series: upstream does not take memory reservations for a
debugging aid in a board DTS, so patch 0004 stays in upstream form. In `tests/dtb.sh`, add before the
`# Charging from [pmu1_para]` comment:

```sh
# ramoops below U-Boot (0x4a000000), clear of the FEL loads (zImage 0x42000000 .. initrd 0x43400000 + ~12 MB).
[ "$(fdtget -t x "$d" /reserved-memory/ramoops@49000000 reg 2>/dev/null)" = "49000000 100000" ] || bad "ramoops region"
```

and add `ramoops region (repo-only patch),` after `CPU on DCDC3,` in its header comment.

Run: `./build.sh run tests/dtb.sh`
Expected: FAIL, `FAIL: ramoops region`.

- [ ] **Step 2: Reserve the region and verify**

In `out/src/linux/arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`, add at the end of the root
node, after the `speaker_amp` node:

```dts
	reserved-memory {
		#address-cells = <1>;
		#size-cells = <1>;
		ranges;

		/*
		 * Crash log kept across a reset, read back from /sys/fs/pstore: the board's
		 * only console is USB. Below U-Boot (0x4a000000) and above the FEL load area.
		 */
		ramoops@49000000 {
			compatible = "ramoops";
			reg = <0x49000000 0x100000>;
			record-size = <0x20000>;
			console-size = <0x20000>;
			no-map;
		};
	};
```

```bash
git -C out/src/linux commit -s -am "ARM: dts: sun8i: a33: ga36: reserve a ramoops region" \
  -m "The board's only console is USB, so a crash before or after the gadget is up leaves no log. Keep one in RAM across the panic reset and read it back from /sys/fs/pstore. Not for upstream: kept in r36s-a33-ga36-debian only."
scripts/tree.sh export linux && ls kernel/patches
```

Run: `./build.sh kernel && ./build.sh run tests/dtb.sh && ./build.sh run tests/dt-schema.sh`
Expected: seven patches, the last `0007-ARM-dts-sun8i-a33-ga36-reserve-a-ramoops-region.patch`; `PASS`, `PASS`.

- [ ] **Step 3: Write the initramfs**

`tests/initramfs/init`:

```sh
#!/usr/bin/busybox sh
# /init of the FEL bring-up initramfs. Test-only, never part of an image.
/usr/bin/busybox --install -s
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mount -t debugfs debugfs /sys/kernel/debug
mount -t pstore pstore /sys/fs/pstore
dmesg -n 1

# The built-in serial gadget (host /dev/ga36-linux) is the only console. ttyGS0 appears once the USB
# controller has probed; the shell restarts after every disconnect.
while :; do
	[ -e /dev/ttyGS0 ] && setsid sh -i < /dev/ttyGS0 > /dev/ttyGS0 2>&1
	sleep 1
done
```

`scripts/make-test-initramfs.sh`:

```sh
#!/bin/sh
# FEL bring-up initramfs: busybox, evtest, alsa-utils, modetest, a colour-bar test image.
# Test-only, never part of an image. Needs ./build.sh uboot (mkimage). Runs inside the build container.
set -eu
r=out/build/initramfs
o=out/initramfs
rm -rf "$r"
mkdir -p "$o"
mmdebstrap --mode=fakechroot --variant=extract --architectures=armhf \
	--include=busybox-static,evtest,alsa-utils,libdrm-tests trixie "$r"
rm -rf "$r/usr/share/doc" "$r/usr/share/man" "$r/usr/share/locale" "$r/usr/share/info" "$r/var/cache" "$r/var/lib/apt"
# The extract variant creates no merged-usr links; the ELF interpreter is /lib/ld-linux-armhf.so.3.
for d in lib bin sbin; do
	if [ -e "$r/$d" ] && [ ! -L "$r/$d" ]; then echo "$r/$d is a real directory; cannot link it to usr/$d" >&2; exit 1; fi
	[ -L "$r/$d" ] || ln -s "usr/$d" "$r/$d"
done
mkdir -p "$r/proc" "$r/sys" "$r/dev" "$r/tmp"
install -m 755 tests/initramfs/init "$r/init"

# 8 vertical bars, left to right: white yellow cyan green magenta red blue black.
# A black 80x48 block in the top-left corner marks the orientation.
python3 - "$r/bars.raw" <<'EOF'
import sys
bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
w, h = 640, 480
out = bytearray()
for y in range(h):
    for x in range(w):
        r, g, b = (0, 0, 0) if x < 80 and y < 48 else bars[x * 8 // w]
        out += bytes((b, g, r, 0))
open(sys.argv[1], "wb").write(out)
EOF

(cd "$r" && find . | cpio -o -H newc -R 0:0 --quiet) | gzip -9 > "$o/initrd.cpio.gz"
out/build/u-boot/tools/mkimage -A arm -T ramdisk -C none -d "$o/initrd.cpio.gz" "$o/initrd.uimg" >/dev/null
# FEL loads it at 0x43400000; it must end below the ramoops region at 0x49000000.
[ $((0x43400000 + $(stat -c %s "$o/initrd.uimg"))) -le $((0x49000000)) ] \
	|| { echo "initrd.uimg too large: it would overlap ramoops" >&2; exit 1; }
```

In `build.sh`, add the stage below the `kernel)` line:

```sh
	initramfs) run scripts/make-test-initramfs.sh ;;
```

- [ ] **Step 4: Build it**

Run: `chmod +x tests/initramfs/init scripts/make-test-initramfs.sh && ./build.sh initramfs && ls -l out/initramfs`
Expected: `initrd.cpio.gz` around 12 MB and `initrd.uimg` 64 bytes larger.

- [ ] **Step 5: Check the initramfs contents**

Run: `./build.sh run sh -c 'zcat out/initramfs/initrd.cpio.gz | cpio -t --quiet' | grep -xE 'init|bars.raw|usr/bin/busybox|usr/bin/evtest|usr/bin/modetest|usr/bin/speaker-test|lib'`
Expected: all seven names.

- [ ] **Step 6: [person] Enter FEL** (SD card out, press the power key).

- [ ] **Step 7: Boot the kernel to a shell**

Run: `scripts/fel-boot.sh kernel`
Expected: exactly `6.18.56`. Then `scripts/board-run.sh 'dmesg | grep -E "Linux version 6.18.56|Machine model: GameConsole R36S GA36-MB"; cat /proc/cmdline'`
prints both dmesg lines and `console=tty0 console=ttyGS0,115200 panic=5`. A `bootz failed` from `fel-boot.sh` shows
U-Boot's bootargs; a timeout with no FEL device means the kernel died before the gadget came up: the next FEL boot's
`/sys/fs/pstore` may hold the log (step 10), otherwise only the panel can show it (Task 9, step 2).

- [ ] **Step 8: Rails survive the regulator cleanup (Review Focus 4)**

Run (once `cat /proc/uptime` on the board is past 60 s):
`scripts/board-run.sh 'cut -d. -f1 /proc/uptime; for r in /sys/class/regulator/regulator.*; do echo "$(cat $r/name) $(cat $r/state 2>/dev/null)"; done'`
Expected: first line 60 or more; `vcc-3v0 vdd-sys vdd-cpu vcc-dram vcc-io vdd-dll vcc-pll-avcc vcc-dldo3 vdd-cpus`
each listed as `enabled`. A missing name means the DT label did not apply; a `disabled` one is a bug to fix in the
DTS before going on.

- [ ] **Step 9: USB gadget console; VBUS not driven (Review Focus 5)**

Run: `udevadm info -q property /dev/ga36-linux | grep -x ID_MM_DEVICE_IGNORE=1 && scripts/board-run.sh 'cat /sys/class/udc/*/state; for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name)" = usb0-vbus ] && cat $r/state; done'`
Expected: `ID_MM_DEVICE_IGNORE=1`; `configured`; `disabled`.

- [ ] **Step 10: A crash is kept in pstore across the reset**

Inject a panic and prove it happened (the board resets into FEL within ~10 s, `panic=5`):

```bash
scripts/board-run.sh 'ls /sys/fs/pstore | wc -l; grep -c ramoops /proc/iomem'
printf 'echo c > /proc/sysrq-trigger\n' > /dev/ga36-linux
timeout 30 sh -c 'until lsusb -d 1f3a:efe8 >/dev/null; do sleep 1; done' && echo back-in-fel
scripts/fel-boot.sh kernel
scripts/board-run.sh 'ls /sys/fs/pstore; grep -h "sysrq triggered crash" /sys/fs/pstore/*'
```

Expected: first `0` and `1` (empty store, region reserved); `back-in-fel` (the panic and the reset took effect); after
the new boot a `dmesg-ramoops-0` file and its `Kernel panic - not syncing: sysrq triggered crash` line. If the board
is back in FEL but the store is empty, DRAM did not keep the region through the reset: record it in the bring-up
table (Task 9) and rely on the panel console for early crashes. Then `scripts/board-run.sh 'rm /sys/fs/pstore/*'`.

- [ ] **Step 11: Commit**

```bash
git add scripts/make-test-initramfs.sh tests/initramfs/init build.sh tests/dtb.sh kernel/patches
git commit -m "Add test initramfs and ramoops region; first kernel boot over FEL"
```

---

### Task 9: Device bring-up checklist

**Files:**
- Modify: `docs/hardware/hardwareAnalysis.md` (new section "Mainline bring-up (V1.0)")
- Modify, only if a check fails: the DTS or driver in `out/src/linux`, then `scripts/tree.sh export linux`

**Interfaces:**
- Consumes: the board booted as in Task 8, steps 6-7 (one FEL boot per power-on); `scripts/board-run.sh`; the
  pstore result of Task 8, step 10.
- Produces: a results table in `hardwareAnalysis.md`; open items carried to the spec in Task 12.

Ask the person for steps 2, 4, 5, 6, 8 and 10 in one message before starting. Each check has a fix path; after any DTS
or driver fix: commit in `out/src/linux`, `scripts/tree.sh export linux`, `./build.sh kernel`, re-run
`tests/dtb.sh`, FEL-boot again and repeat the failed check.

- [ ] **Step 1: Panel driver state**

Run: `scripts/board-run.sh 'dmesg | grep -iE "dsi|panel|drm|lima" ; modetest -M sun4i-drm -c | grep -A2 -E "^Connectors|640x480"'`
Expected: no `failed`/`error` lines from the panel or DSI; a connected DSI connector with mode `640x480` and a
refresh around 56. Fix path for a probe error: compare the DSI and DPHY clocks in `cat /sys/kernel/debug/clk/clk_summary`
against 30 MHz x 24 bpp / 2 lanes = 360 Mbit/s per lane.

- [ ] **Step 2: [person] Panel picture**

Run: `scripts/board-run.sh 'echo 0 > /sys/class/graphics/fbcon/cursor_blink; cat /bars.raw > /dev/fb0'`
Person checks: 8 vertical bars left to right white, yellow, cyan, green, magenta, red, blue, black; a black block
in the top-left corner; no rolling, tearing or flicker for 30 s. Fix paths: black screen with a lit backlight means
the DSI link or init (re-check step 1); a rolling or shifted picture means timing: try the alternative reading of
the fex values (`hbp`/`vbp` excluding sync: `.hsync_start = 640 + 240`, `.hsync_end = 640 + 240 + 40`,
`.htotal = 1040`; `.vsync_start = 480 + 20`, `.vsync_end = 480 + 20 + 6`, `.vtotal = 518`), then a 60 Hz mode at
`.clock = 32300`; swapped colours or a mirrored picture are recorded for a panel fix (`0x36` value in the table).

- [ ] **Step 3: Backlight polarity**

Run: `scripts/board-run.sh 'echo 1 > /sys/class/backlight/backlight/brightness; sleep 3; echo 10 > /sys/class/backlight/backlight/brightness'`
Person: the screen ends brighter than it was during the 3 s. If it ends darker, change the DTS to
`pwms = <&pwm 0 50000 PWM_POLARITY_INVERTED>;` with `#include <dt-bindings/pwm/pwm.h>`, and repeat.

- [ ] **Step 4: [person] Buttons**

Run: `TIMEOUT=100 scripts/board-run.sh 'e=$(grep -l "^gpio-keys$" /sys/class/input/event*/device/name | cut -d/ -f5); timeout 90 evtest /dev/input/$e | grep "value 1"'`
Person, during the 90 s, presses once each, in this order: A, B, X, Y, L1, R1, L2, R2, SELECT, START, L3, R3, UP,
DOWN, LEFT, RIGHT, FN, then Vol+, Vol-, then the power key (short).
Expected: 17 `value 1` lines; record the code each physical button produced against the table in
`hardwareAnalysis.md` "Input". Vol+/Vol- produce nothing here (not mapped yet; record as an open item).
A swapped pair is fixed in the DTS (`linux,code`), not in userspace.

- [ ] **Step 5: [person] Power key**

Run: `TIMEOUT=40 scripts/board-run.sh 'e=$(grep -l "axp20x-pek" /sys/class/input/event*/device/name | cut -d/ -f5); timeout 30 evtest /dev/input/$e | grep "value 1"'`
Person: short press on the power key within 30 s. Expected: one `KEY_POWER` line.

- [ ] **Step 6: [person] Audio on both outputs**

Run: `scripts/board-run.sh 'aplay -l; amixer scontrols'`, then:
`TIMEOUT=60 scripts/board-run.sh 'amixer -q sset Headphone 40% unmute; amixer -q sset DAC 80% unmute 2>/dev/null; speaker-test -c 2 -t sine -f 440 -l 2'`
Person: the tone plays on the speaker without headphones, and in the headphones with them plugged in (run twice).
Expected: `aplay -l` lists `sun8i-a33-audio`. Use the control names `amixer scontrols` printed if `Headphone` or
`DAC` differ, keep the volume at or below 40 % (speaker protection), and record the names used.

- [ ] **Step 7: Battery and charger**

Run: `scripts/board-run.sh 'cd /sys/class/power_supply; for p in *; do echo "$p: $(cat $p/online 2>/dev/null) $(cat $p/status 2>/dev/null) $(cat $p/capacity 2>/dev/null) $(cat $p/voltage_now 2>/dev/null)"; done; cat axp20x-battery/constant_charge_current_max'`
Expected: `axp20x-battery` with a status and capacity; `constant_charge_current_max` `300000`.

- [ ] **Step 8: [person] Charger plug and unplug**

The gadget console drops while the OTG cable is out, so the board logs to `/tmp` on its own for 60 s:
`scripts/board-run.sh '(setsid sh -c '\''cd /sys/class/power_supply; for i in $(seq 60); do echo "$(cat */online | tr "\n" " ")$(cat axp20x-battery/status)"; sleep 1; done > /tmp/chg.log'\'' > /dev/null 2>&1 &)'`
Person, within those 60 s: unplug the charger and the USB cable for about 15 s, then plug both back in. Once the
60 s are over:
`timeout 60 sh -c 'until [ -e /dev/ga36-linux ]; do sleep 1; done' && scripts/board-run.sh 'wc -l < /tmp/chg.log; uniq /tmp/chg.log'`
Expected: 60 lines logged (the logger outlived the disconnect); the `online` values change while unplugged and
battery status goes from `Charging` (or `Full`) to `Discharging` and back.

- [ ] **Step 9: Sleep and wake**

The USB console may drop while the board sleeps, so the sleep runs detached and logs to `/tmp`. Unattended wake by
RTC, asserting the board actually slept:
`scripts/board-run.sh 'rm -f /tmp/sleep.log; (setsid sh -c '\''t=$(date +%s); echo +10 > /sys/class/rtc/rtc0/wakealarm; echo freeze > /sys/power/state; echo slept $(( $(date +%s) - t ))s > /tmp/sleep.log'\'' > /dev/null 2>&1 &)'`
(the subshell keeps the `&` from ending the line, which `board-run.sh` extends with `; echo`), then `timeout 120 sh -c 'until scripts/board-run.sh "cat /tmp/sleep.log" 2>/dev/null | grep slept; do sleep 2; done'`
Expected: `slept 10s` (9 to 12). Then the power key wake: run the same two commands without the `wakealarm` part;
person presses the power key after about 20 s. Expected: the panel turns off, then `slept` around 20 s or more.

- [ ] **Step 10: [person] SD card detect**

Person inserts a card, waits 3 s, removes it. Run afterwards: `scripts/board-run.sh 'dmesg | grep -E "mmc0: (new|card)"'`
Expected: a `new ... card` line then a `card ... removed` line. No line at all: the CD polarity or pin is wrong; check
`cat /sys/kernel/debug/gpio | grep -i cd` and fix `cd-gpios`.
Also record the plug-in result from Task 4, step 6 here.

- [ ] **Step 11: Thermal under load at the stock maximum (1008 MHz)**

Run: `TIMEOUT=700 scripts/board-run.sh 'for i in 1 2 3 4; do md5sum /dev/zero & done; sleep 5; cat /proc/loadavg; for i in $(seq 20); do echo "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) $(cat /sys/class/thermal/thermal_zone0/temp)"; sleep 30; done; kill $(jobs -p)'`
Expected: load average first field at or above 3.5 by the end (the load ran); the first frequency `1008000`; no
temperature above `90000`; if it passes 75 C the frequency drops (throttling works). The board still answers
`scripts/board-run.sh 'echo ok'` afterwards.

- [ ] **Step 12: Record results and commit**

Add to `docs/hardware/hardwareAnalysis.md` a section:

```markdown
## Mainline bring-up (V1.0)

Linux 6.18.56 and U-Boot v2026.10 from this repository, booted over FEL with the test initramfs. Date: <run date>.

| Check | Result | Notes |
|---|---|---|
| Panel picture (bars, orientation, stability) | | |
| Backlight polarity | | |
| Buttons (17) | | |
| Vol+/Vol- | not mapped | source unknown (LRADC likely) |
| Power key | | |
| Speaker / headphones | | mixer controls used: |
| Battery, charger online | | |
| s2idle: RTC wake / power key wake | | |
| SD card detect | | |
| pstore crash log kept across the reset | | |
| Power-on by plug-in | | |
| Thermal at 1008 MHz, 10 min, 4 threads | | max temperature: |
```

Fill every cell from the runs above (the date is the day of the run). Then:

```bash
git add docs/hardware/hardwareAnalysis.md kernel/patches
git commit -m "Record mainline bring-up results on GA36 V1.0"
```

---

### Task 10: CPU OPPs 1.104 and 1.2 GHz

Do this only after Task 9, step 11 passed: the CPU ran stable at the stock OPPs with DCDC3 at most at its vendor
boot value. Evidence that DCDC3 is the CPU rail: the vendor fex sets `dcdc3_vol = 1200`, matching its 1008 MHz DVFS
point, and the vendor U-Boot carries `axp_set_dcdc3 fail` next to its DVFS code; the Q8 reference design's DCDC2
choice does not match the vendor values (`dcdc2_vol = 1100`).

**Files:**
- Modify (in `out/src/linux`): `arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dts`
- Modify: `kernel/patches/0004-ARM-dts-sun8i-a33-add-GA36-MB-V1.0.patch` (by export)
- Test: `tests/dtb.sh`

**Interfaces:**
- Consumes: Task 6 DTS and `tests/dtb.sh`.
- Produces: cpufreq maximum 1200000 kHz at 1.32 V.

- [ ] **Step 1: Update the test**

In `tests/dtb.sh`, change `dcdc3:1200000` to `dcdc3:1320000` in the rail list, and add before the
`# Charging from [pmu1_para]` comment:

```sh
[ "$(fdtget -t u "$d" /opp-table-cpu/opp-1200000000 opp-microvolt 2>/dev/null | cut -d' ' -f1)" = 1320000 ] \
	|| bad "no 1.2 GHz OPP at 1.32 V"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./build.sh run tests/dtb.sh`
Expected: `FAIL: no 1.2 GHz OPP at 1.32 V`.

- [ ] **Step 3: Add the OPPs**

In the DTS, change `regulator-max-microvolt = <1200000>;` in `&reg_dcdc3` to `<1320000>`, replace its comment with
`/* Up to the vendor DVFS value for 1.2 GHz. */`, and add after `&cpu0`:

```dts
/* Vendor DVFS table: 1200 MHz at 1.32 V; max_freq 1.2 GHz. */
&cpu0_opp_table {
	opp-1104000000 {
		opp-hz = /bits/ 64 <1104000000>;
		opp-microvolt = <1320000>;
		clock-latency-ns = <244144>; /* 8 32k periods */
	};

	opp-1200000000 {
		opp-hz = /bits/ 64 <1200000000>;
		opp-microvolt = <1320000>;
		clock-latency-ns = <244144>; /* 8 32k periods */
	};
};
```

Fold it into the DTS commit and export:

```bash
git -C out/src/linux commit -a --fixup=":/ARM: dts: sun8i: a33: add GA36-MB"
GIT_SEQUENCE_EDITOR=true git -C out/src/linux rebase -q --autosquash ga36-base
scripts/tree.sh export linux
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build.sh kernel && ./build.sh run tests/dtb.sh && ./build.sh run tests/dt-schema.sh`
Expected: `PASS`, `PASS`.

- [ ] **Step 5: [person] FEL-boot and run the thermal test at 1.2 GHz**

Person: enter FEL. Run `scripts/fel-boot.sh kernel`, then the command of Task 9, step 11.
Expected: same as there, with the first frequency `1200000`. Then
`scripts/board-run.sh 'for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name)" = vdd-cpu ] && cat $r/microvolts; done'`
prints at most `1320000`. Any hang or reboot under load: revert this task's DTS change (the rail is suspect) and
record it.

- [ ] **Step 6: Record and commit**

Add a row `| Thermal at 1200 MHz, 10 min, 4 threads | | max temperature: |` to the bring-up table, filled in.

```bash
git add tests/dtb.sh kernel/patches docs/hardware/hardwareAnalysis.md
git commit -m "Add 1.104 and 1.2 GHz CPU OPPs at the vendor DVFS voltage"
```

---

### Task 11: Test SD card boot

**Files:**
- Create: `scripts/make-test-sdcard.sh`
- Modify: `build.sh` (stage dispatch)
- Test: `tests/sdcard.sh`

**Interfaces:**
- Consumes: `out/u-boot/u-boot-sunxi-with-spl.bin`, `out/kernel/zImage`, the DTB, `out/initramfs/initrd.cpio.gz`.
- Produces: `out/sdcard/ga36-test.img` - MBR, U-Boot at 8 KiB, p1 FAT32 `BOOT` (256 MiB at 16 MiB, bootable) with
  `zImage`, the DTB, `initrd.cpio.gz` and `extlinux/extlinux.conf`. Test-only (it boots the test initramfs); the
  release image is sub-project 4.

- [ ] **Step 1: Write the failing test**

`tests/sdcard.sh`:

```sh
#!/bin/sh
# Test SD image layout: U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files and extlinux.conf.
# Run: ./build.sh run tests/sdcard.sh
set -eu
img=out/sdcard/ga36-test.img
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -f "$img" ] || { echo "FAIL: $img missing (./build.sh sdcard)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sfdisk -d "$img" | grep -q 'start= *32768, size= *524288, type=c, bootable' || bad "p1 not at 16 MiB / 256 MiB / FAT32 LBA / bootable"
dd if="$img" bs=1024 skip=8 status=none | head -c "$(stat -c %s "$u")" | cmp -s - "$u" || bad "U-Boot not at 8 KiB"
for f in zImage sun8i-a33-gameconsole-r36s-ga36.dtb initrd.cpio.gz; do
	mdir -b -i "$img@@16M" "::/$f" >/dev/null 2>&1 || bad "$f missing on p1"
done
mtype -i "$img@@16M" ::/extlinux/extlinux.conf | grep -q 'fdt /sun8i-a33-gameconsole-r36s-ga36.dtb' || bad "extlinux.conf fdt"
mtype -i "$img@@16M" ::/extlinux/extlinux.conf | grep -q 'append .*console=ttyGS0' || bad "extlinux.conf console"
[ $fail = 0 ] && echo PASS
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/sdcard.sh && ./build.sh run tests/sdcard.sh`
Expected: `FAIL: out/sdcard/ga36-test.img missing`.

- [ ] **Step 3: Write the implementation**

`scripts/make-test-sdcard.sh`:

```sh
#!/bin/sh
# Test SD card image: U-Boot at 8 KiB, p1 FAT32 BOOT with the kernel, DTB, test initramfs and extlinux.conf.
# Test-only; the release image is built by sub-project 4. Rootless, no loop mounts. Runs inside the build container.
set -eu
o=out/sdcard
img=$o/ga36-test.img
p1=$o/p1.vfat
mkdir -p "$o"
rm -f "$img" "$p1"

cat > "$o/extlinux.conf" <<'EOF'
label ga36-test
	kernel /zImage
	fdt /sun8i-a33-gameconsole-r36s-ga36.dtb
	initrd /initrd.cpio.gz
	append console=tty0 console=ttyGS0,115200 panic=5 ga36_boot=sdcard
EOF
mkfs.vfat -F 32 -n BOOT -C "$p1" $((256 * 1024)) >/dev/null
mmd -i "$p1" ::/extlinux
mcopy -i "$p1" "$o/extlinux.conf" ::/extlinux/
mcopy -i "$p1" out/kernel/zImage out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb out/initramfs/initrd.cpio.gz ::/

truncate -s $(( (16 + 256) * 1024 * 1024 )) "$img"
echo 'start=32768, size=524288, type=c, bootable' | sfdisk -q "$img"
dd if=out/u-boot/u-boot-sunxi-with-spl.bin of="$img" bs=1024 seek=8 conv=notrunc status=none
dd if="$p1" of="$img" bs=1M seek=16 conv=notrunc status=none
rm "$p1" "$o/extlinux.conf"
```

In `build.sh`, add the stage below the `initramfs)` line:

```sh
	sdcard) run scripts/make-test-sdcard.sh ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/make-test-sdcard.sh && ./build.sh sdcard && ./build.sh run tests/sdcard.sh`
Expected: `PASS`.

- [ ] **Step 5: [person] Write the image to a spare card**

Not the stock card. Person identifies the card with `lsblk -o NAME,SIZE,MODEL,TRAN`, then runs
`! sudo dd if=out/sdcard/ga36-test.img of=/dev/sdX bs=4M conv=fsync status=progress` with the right `sdX`.

- [ ] **Step 6: [person] Boot from the card**

Person: insert the card, cable to the PC, press the power key. Run:
`timeout 60 sh -c 'until [ -e /dev/ga36-linux ]; do lsusb -d 1f3a:efe8 >/dev/null && exit 1; sleep 1; done' && scripts/board-run.sh 'cat /proc/cmdline; dmesg | grep "Machine model"; cat /sys/block/mmcblk0/size'`
Expected: the command line ends in `ga36_boot=sdcard` (the kernel came from the card's extlinux.conf, not FEL),
`Machine model: GameConsole R36S GA36-MB`, and a non-zero sector count. Exit 1 without output means the board fell
back to FEL: the card did not boot (check it was written to the right device).

- [ ] **Step 7: [person] Card boot with no PC attached (Review Focus 2)**

Person: power off (hold the power key ~8 s), unplug the USB cable and the charger, press the power key, wait 60 s,
then plug the cable into the PC. Run:
`timeout 30 sh -c 'until [ -e /dev/ga36-linux ]; do sleep 1; done' && scripts/board-run.sh 'cut -d. -f1 /proc/uptime; cat /proc/cmdline'`
Expected: uptime 55 s or more (the board booted while nothing was attached, so U-Boot did not wait for a USB host)
and `ga36_boot=sdcard`. Uptime under 30 s means the board started only when the cable arrived: U-Boot waited, so
check the `CONFIG_PREBOOT` condition.

- [ ] **Step 8: [person] Silent charging with the card in**

Person: power off (hold the power key ~8 s), unplug everything, then plug in the charger without pressing anything;
if the charger is the OTG port, use the PC cable. Run: `sleep 20; lsusb | grep -E '1f3a:|0525:a4a7'`
Expected: no line (nothing booted: either the SPL switched the board off again or it never powered on from the
plug-in), the panel stays dark, and after a few minutes the person confirms charging (battery warmer or the charge
LED, if any). Record the result in the bring-up table.

- [ ] **Step 9: Commit**

```bash
git add scripts/make-test-sdcard.sh build.sh tests/sdcard.sh docs/hardware/hardwareAnalysis.md
git commit -m "Add test SD card image and verify card boot"
```

---

### Task 12: Spec, notes and README

**Files:**
- Modify: `docs/specs/2026-10-14-firmware-design.md`
- Modify: `docs/hardware/hardwareAnalysis.md` (mapping table, Console row)
- Modify: `docs/porting-plan.md` (Open risks)
- Modify: `README.md` (status, development)

**Interfaces:**
- Consumes: results of Tasks 4, 9, 10, 11.

- [ ] **Step 1: Apply the spec deviations**

In `docs/specs/2026-10-14-firmware-design.md`:
- Section 2, step 2: replace `; console on UART2 (\`CONS_INDEX=3\`)` with
  `; U-Boot's default serial output (UART0 on \`PB0\`/\`PB1\`) is unused, the console is USB (section "Testing")`.
- Section 2, step 3: replace `U-Boot bootstd finds` with `U-Boot's distro boot (\`distro_bootcmd\`) finds`.
- Section 2, step 6: append `One U-Boot patch: \`board_usb_init()\` probes the MUSB gadget, so the ACM console
  works without USB Ethernet.`
- Section 2, step 5: replace `(it needs only UART2 and MMC0)` with `(it needs only MMC0 and the USB OTG gadget)`.
- Section 2, the "Charging while off" bullet: replace it with
  `- Charging while off: U-Boot's \`AXP_DISABLE_BOOT_ON_POWERON\` switches the board off again in the SPL when the
  power-on source was the charger. Nothing is written to the AXP.`
- Section 2, the "Development loop" bullet: replace it with
  `- Development loop: \`sunxi-fel uboot ... write <addr> zImage dtb\` boots kernels from the PC with a USB console
  (U-Boot ACM on FEL boots without a script, kernel serial gadget \`ttyGS0\`); SD card images only for release
  testing.`
- Section 3, patch 4: replace `A dt-bindings patch for the new compatible.` with
  `Three dt-bindings patches: GameConsole vendor prefix, panel compatible, board compatible.`
- Section 3, patch 1: replace `gpio-keys,` with `gpio-keys-polled (the PE bank has no interrupts),` and
  `UART2 console, UART1` with `no debug UART, UART1`.
- Section 3, after patch 4: add
  `  5. \`ARM: dts: sun8i: a33: ga36: reserve a ramoops region\`: crash logs across the panic reset; kept in this
  repository only, not sent upstream.`
- Section 4, "Rootfs": replace `Serial getty on UART2 and on the USB gadget ACM port \`ttyGS0\`.` with
  `Serial getty on the USB gadget ACM port \`ttyGS0\`.`
- Section 3, "Buttons": replace `one \`gpio-keys\` device` with `one \`gpio-keys-polled\` device (10 ms)`.
- Section 3, "Test on each FEL boot": replace `\`stress-ng\` at 1.2 GHz` with `four busy threads at 1.2 GHz`.
- Testing: replace `Development setup: USB OTG (FEL) and an FT232 adapter on UART2.` with
  `Development setup: USB OTG only; the development board's UART pads are damaged.`; in the table header replace
  `Unattended over FEL and UART2` with `Unattended over FEL and the USB console`, and `(UART timestamps)` with
  `(dmesg timestamps)`; in the row `thermal under \`stress-ng\`` replace `\`stress-ng\`` with `load`.
- Testing: replace the bullet starting `FEL only loads code` with
  `- FEL only loads code; it shows nothing. The console is USB only: U-Boot's ACM console on FEL boots without a
  script, then the kernel's serial gadget \`ttyGS0\`. A panic resets the board into FEL and its log is read from
  pstore (ramoops) on the next boot. A hang before the gadget or ramoops starts shows nothing, except on the panel's
  framebuffer console once the panel works.`
- Recovery and safety: delete the bullet starting `The AXP power-on-by-charger setting persists`.
- Status line: `Date: 2026-10-14. Status: design approved; sub-projects 1 and 2 implemented (plan
  [\`../plans/2026-10-14-boot-kernel.md\`](../plans/2026-10-14-boot-kernel.md)).`

- [ ] **Step 2: Hardware notes and porting plan**

In `docs/hardware/hardwareAnalysis.md`, mapping table row `| Console | \`&uart2\` | \`PB0\`/\`PB1\`, 115200 |`
becomes `| Console | USB gadget \`ttyGS0\` | USB OTG; the UART2 pads on \`PB0\`/\`PB1\` are not used (damaged on the V1.0 development board) |`, and
the Buttons row names `gpio-keys-polled`. In the same file, the Debug UART row gets `; pad ripped off on the V1.0
development board after these tests (2026-10-14)` appended to its last cell, and under "On-device tests", test 4,
after the `Cause:` line, add `Later on 2026-10-14 the UART2 pad was ripped off the development board; development
continues over the USB OTG console only.`
In `docs/porting-plan.md`, "Before v1.1": add `- Read the stock system's rail voltages
(\`/sys/class/regulator/*/microvolts\` via the cron probe), to confirm ALDO1 (3.0 V, from the reference design)
and DC5LDO, which \`[power_sply]\` does not list.` In "Open risks": delete `A33 DSI bring-up` and the panel timing line if Task 9 passed;
replace the AXP register line with `Vol+/Vol- source unknown (likely LRADC); needed by sub-project 3.`

- [ ] **Step 3: README**

Replace the status line with:

```markdown
**Status: boot and kernel bring-up.** Mainline U-Boot and Linux boot on GA36 V1.0 over USB and from a test card; no
installable image yet. See [`docs/porting-plan.md`](docs/porting-plan.md) for the roadmap and
[`docs/specs/2026-10-14-firmware-design.md`](docs/specs/2026-10-14-firmware-design.md) for the design.
```

Add before `## Licence`:

```markdown
## Development

Needs Docker or Podman; everything else runs in the build container.

- `./build.sh uboot|kernel|initramfs|sdcard` builds into `out/`; `./build.sh run tests/<name>.sh` runs a check.
- Board work lives in `out/src/linux` and `out/src/u-boot` as git commits; `scripts/tree.sh export linux` turns them
  into `kernel/patches/`.
- `scripts/fel-boot.sh kernel` boots the board from the PC over USB (no card, power key) and
  `scripts/board-run.sh 'cmd'` runs commands on it over the USB console. Install `scripts/70-ga36-usb.rules` in
  `/etc/udev/rules.d/` first: it names the console `/dev/ga36-linux` and keeps ModemManager off it.
```

- [ ] **Step 4: Check links and commit**

Run: `grep -o '](\([^)]*\))' README.md docs/specs/2026-10-14-firmware-design.md | sed 's/.*](//; s/)$//' | sort -u`
and confirm each relative path exists from its file's directory.

```bash
git add docs/specs/2026-10-14-firmware-design.md docs/hardware/hardwareAnalysis.md docs/porting-plan.md README.md
git commit -m "Update spec, notes and README after boot and kernel bring-up"
```

- [ ] **Step 5: Run the whole offline suite**

Run: `for t in container tree uboot-config kernel-config dtb dt-schema panel-init sdcard; do ./build.sh run tests/$t.sh || break; done`
Expected: eight `PASS` lines.
