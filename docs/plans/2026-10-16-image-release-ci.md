# Release image, CI and install guide (sub-project 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone with the repository can get a named, checksummed SD card image built by `./build.sh all`, locally or
by GitHub Actions, and install it from the README.

**Architecture:** `scripts/make-image.sh` replaces `scripts/make-test-sdcard.sh` (same layout, same contents) and
adds the versioned name, the `.img.xz` and `SHA256SUMS`. `build.sh` gains `image` (replacing `sdcard`) and `all`.
One workflow, `.github/workflows/image.yml`, runs `./build.sh all` on tag push and manual dispatch: a dispatch
uploads a workflow artifact, a tag creates a draft GitHub Release.

**Tech Stack:** POSIX sh, the existing build container (Debian trixie: xz-utils, coreutils, yamllint), GitHub
Actions (`actions/checkout@v4`, `docker/setup-qemu-action@v3`, `actions/upload-artifact@v4`, the runner's `gh`).

**Spec:** [`docs/specs/2026-10-14-firmware-design.md`](../specs/2026-10-14-firmware-design.md), section 5 ("Image,
release and CI"); section 1 for the layout and `build.sh` stages.

## Global Constraints

- "`scripts/make-image.sh` works rootless, with no loop mounts: p1 via `mkfs.vfat -C` and `mcopy`; p2 via
  `mkfs.ext4 -d`; `sfdisk` writes the MBR; `dd` places p1 and p2 at their offsets and U-Boot at 8 KiB."
- "Output: a sparse image compressed to `r36s-a33-ga36-debian-vX.Y.Z.img.xz`, plus `SHA256SUMS`."
- "p2 is a fixed 3 GiB, so p3 always starts at the same offset." "The disk id is fixed at `0x47413336`."
- "Versions: semver tags, `v1.0.0` for the v1.0 scope." "Release gate: the section 4 device checklist passes on
  V1.0; release notes name the tested revision and the items checked by a person."
- "CI: one GitHub Actions workflow on tag push and manual dispatch. It runs `./build.sh all` in the same container
  and attaches the `.img.xz` and `SHA256SUMS` to the GitHub Release."
- "No CHANGELOG; release notes live on GitHub Releases."
- `build.sh` runs every stage inside the container; the host needs only Docker or Podman (plus binfmt for armhf).
- Everything on disk in English. Commits: author `Bepok <wojtekjakubiszyn@gmail.com>`, no trailers, no AI
  attribution, no em dashes or decorative emoji in commit messages, release notes or anything else outward.
- Parallelism: never more workers than `nproc` (16 here) across concurrent runs.

Decisions taken with the person when planning (2026-10-16):
- The repository goes to GitHub as **private** `Bepok/r36s-a33-ga36-debian`; the workflow is run once for real.
- A tag push creates a **draft** release; the person publishes it after the device checklist.
- One image script for development and release (contents are identical).
- GPL sources: the release notes and README **link** this repository at the tag (patches, configs, pins in
  `versions.env`) and Debian's source archive. No source bundle, no snapshot.debian.org pin.

Decisions on the plan's open questions (2026-10-16):
- **6 h job limit:** no fallback planned; the Task 4 run shows how close the build gets.
- **Private repository = maintainers only for now.** The README says so, and it does not invite outside testers
  or issues yet.
- **Card size, from the numbers:**
  - the image is 3344 MiB (3.51 GB), so a smaller card cannot hold it;
  - `ga36-roms-part` makes ROMS only with at least 1 GiB after p2, so a card needs 4368 MiB (4.58 GB) for one;
  - on a smaller card, the ROMs go to p2, which has 1.7 GiB available to users (measured with `dumpe2fs` on the
    current image: 488061 free blocks, 39321 reserved, 4 KiB each).

  So: 4 GB minimum, 8 GB or more recommended. Task 3 writes this into the README and the spec.
- **Tests:**
  - CI runs every test that needs no board: the whole `tests/*.sh` suite after `./build.sh all`.
  - The worktree runs only the tests whose `out/` input is present.
  - Checking on the device is the developer's job. Task 3 says so prominently in the README; it is expected before
    a release but not required to merge a pull request.

Deviations from the spec, recorded in the spec by Task 3:
- No `image/` directory: the layout stays inline in `make-image.sh`, as it was in `make-test-sdcard.sh`.
- The development stage `sdcard` becomes `image`; `out/sdcard/ga36-test.img` becomes `out/image/<name>.img`.
- On the CI runner, armhf binfmt comes from `docker/setup-qemu-action` (F flag), not `apt install qemu-user-binfmt`.

## Review Focus

1. **A clone or checkout without tags** (every manual dispatch before `v1.0.0`): `git describe --tags --always`
   gives a bare commit id, which must still make a valid file name. Pinned by the name check in `tests/image.sh`
   (Task 1, Steps 1 and 5).
2. **A rebuild over an old `out/image`** must leave exactly one image, its `.xz` and a `SHA256SUMS` that matches,
   never an older image next to the new one. Pinned by the file-set check, injected in Task 1 Step 6.
3. **A runner without armhf emulation** must fail in minutes, not after the U-Boot and kernel builds. Pinned by the
   ordering check in `tests/workflow.sh` (Task 2).
4. **Runner limits**: about 14-30 GB free disk, 4 cores, a 6 h job limit, and 500 MB artifact storage on a private
   free-plan repository. Covered by the free-space step, `retention-days: 1` and `compression-level: 0`; measured by
   the real run in Task 4, which records duration, disk and artifact size.
5. **The tag path** (`gh release create --draft`) first runs at `v1.0.0`. Statically checked by
   `tests/workflow.sh`; the first tag run is watched, and a bad draft is deleted and recreated without loss.

---

## Setup

- Worktree `.claude/worktrees/image`, branch `image`, from `main` at `0754139`. This plan is its first commit.
- The previous `out/` lives in the main checkout. The worktree's `out/` starts empty; Task 1 needs `out/u-boot`,
  `out/kernel` and `out/rootfs/rootfs.tar`. Copy them, do not rebuild:

```bash
M=/home/bepok/wrk/MojGit/r36s-a33-ga36-debian
cd $M/.claude/worktrees/image
mkdir -p out && cp -a $M/out/u-boot $M/out/kernel $M/out/rootfs out/
```

- `./build.sh run tests/<name>.sh` runs any test in the container. Local suite: the tests whose input is in the
  worktree's `out/`, since the full suite runs in CI (Task 2, proven in Task 4):
  `for t in container rootfs power roms-part dtb panel-init image workflow; do [ -f tests/$t.sh ] && { ./build.sh run tests/$t.sh >/dev/null 2>&1 || echo "FAILED $t"; }; done; echo suite-done`.
  Not run locally: `apps`, `es-patches`, `kernel-config`, `uboot-config`, `tree`, `dt-schema`, which need
  `out/apps`, `out/src` or `out/build` (about 4 GB, not copied).

### Task 1: Release image (`./build.sh image`, `./build.sh all`)

**Files:**
- Rename and modify: `scripts/make-test-sdcard.sh` → `scripts/make-image.sh`
- Rename and modify: `tests/sdcard.sh` → `tests/image.sh`
- Modify: `build.sh`

**Interfaces:**
- Consumes: `out/u-boot/u-boot-sunxi-with-spl.bin`, `out/kernel/zImage`,
  `out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb`, `out/rootfs/rootfs.tar` (existing stages).
- Produces: `./build.sh image` and `./build.sh all`; the directory `out/image/` holding exactly
  `r36s-a33-ga36-debian-$VERSION.img`, `r36s-a33-ga36-debian-$VERSION.img.xz` and `SHA256SUMS` (one line, for the
  `.img.xz`). `$VERSION` is `git describe --tags --always --dirty` on the host, `dev` if that fails.
  `./build.sh run tests/image.sh` prints `PASS`. Task 2 uses all of these names.

- [ ] **Step 1: Failing test.** `git mv tests/sdcard.sh tests/image.sh`, then replace its contents:

```sh
#!/bin/sh
# Release image in out/image: exactly r36s-a33-ga36-debian-<version>.img, its .img.xz and SHA256SUMS. The image has
# U-Boot at 8 KiB, p1 FAT32 at 16 MiB with the boot files and p2 ext4 ROOTFS (3 GiB) right after.
# Run: ./build.sh run tests/image.sh
set -eu
o=out/image
u=out/u-boot/u-boot-sunxi-with-spl.bin
[ -d "$o" ] || { echo "FAIL: $o missing (./build.sh image)"; exit 1; }
set -- "$o"/*.img
[ $# = 1 ] && [ -f "$1" ] || { echo "FAIL: want one .img in $o, found: $*"; exit 1; }
img=$1
n=$(basename "$img" .img)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# Name, file set and checksums. The version part is a tag (v1.0.0), a describe string (v1.0.0-3-g0754139-dirty) or,
# with no tags, a bare commit id.
echo "$n" | grep -Eq '^r36s-a33-ga36-debian-[0-9A-Za-z][0-9A-Za-z.+-]*$' || bad "image name $n"
[ "$(ls "$o" | sort)" = "$(printf '%s\n' "$n.img" "$n.img.xz" SHA256SUMS | sort)" ] ||
	bad "$o holds: $(ls "$o" | paste -sd' '); want $n.img $n.img.xz SHA256SUMS"
[ "$(cat "$o/SHA256SUMS" 2>/dev/null | wc -l)" = 1 ] && grep -q "  $n.img.xz\$" "$o/SHA256SUMS" ||
	bad "SHA256SUMS is not one line for $n.img.xz"
(cd "$o" && sha256sum -c --status SHA256SUMS) || bad "SHA256SUMS does not verify"
xz -dc "$o/$n.img.xz" 2>/dev/null | cmp -s - "$img" || bad "$n.img.xz does not unpack to $n.img"

# Layout.
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

- [ ] **Step 2: Run it, watch it fail.**

Run: `./build.sh run tests/image.sh`
Expected: `FAIL: out/image missing (./build.sh image)`, exit 1.

- [ ] **Step 3: Image script.** `git mv scripts/make-test-sdcard.sh scripts/make-image.sh`, then replace its
contents:

```sh
#!/bin/sh
# SD card image: U-Boot at 8 KiB, p1 FAT32 BOOT (kernel, DTB, extlinux.conf), p2 ext4 ROOTFS from
# out/rootfs/rootfs.tar. p3 (ROMS) is made on the device at first boot (ga36-roms.service).
# Output in out/image: r36s-a33-ga36-debian-$VERSION.img (sparse, for writing a card locally), its .img.xz (the
# release asset) and SHA256SUMS. Rootless, no loop mounts. Runs inside the build container (./build.sh image).
set -eu
o=out/image
name=r36s-a33-ga36-debian-${VERSION:-dev}
img=$o/$name.img
p1=$o/p1.vfat
p2=$o/p2.ext4
rm -rf "$o"
mkdir -p "$o"

# root=PARTUUID matches label-id below and rootfs/overlay/etc/fstab.
cat > "$o/extlinux.conf" <<'EOT'
label ga36
	kernel /zImage
	fdt /sun8i-a33-gameconsole-r36s-ga36.dtb
	append console=ttyGS0,115200 console=tty0 panic=5 root=PARTUUID=47413336-02 rootwait
EOT
mkfs.vfat -F 32 -n BOOT -C "$p1" $((256 * 1024)) >/dev/null
mmd -i "$p1" ::/extlinux
mcopy -i "$p1" "$o/extlinux.conf" ::/extlinux/
mcopy -i "$p1" out/kernel/zImage out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb ::/
mkfs.ext4 -q -L ROOTFS -d out/rootfs/rootfs.tar "$p2" 3G

# p2 is a fixed 3 GiB so p3 always starts at sector 6848512 (spec section 5).
truncate -s $(( (16 + 256 + 3072) * 1024 * 1024 )) "$img"
sfdisk -q "$img" <<'EOT'
label: dos
label-id: 0x47413336
start=32768, size=524288, type=c, bootable
start=557056, size=6291456, type=83
EOT
dd if=out/u-boot/u-boot-sunxi-with-spl.bin of="$img" bs=1024 seek=8 conv=notrunc status=none
dd if="$p1" of="$img" bs=1M seek=16 conv=notrunc status=none
dd if="$p2" of="$img" bs=1M seek=272 conv=notrunc,sparse status=none
rm "$p1" "$p2" "$o/extlinux.conf"

xz -T0 -k "$img"
(cd "$o" && sha256sum "$name.img.xz" > SHA256SUMS)
```

Everything above `xz` is the old script with `o`, `img` and the extlinux label changed; the `append` line is
byte-identical (it carries the Task 8 console-order fix).

- [ ] **Step 4: build.sh.** Replace the header usage line, the `usage()` line and the stage `case`:

```sh
# Usage: ./build.sh uboot|kernel|initramfs|apps|rootfs|image|all
```

```sh
usage() { echo "usage: ./build.sh uboot|kernel|initramfs|apps|rootfs|image|all | run <command> [args]" >&2; exit 2; }
```

```sh
case $stage in
	uboot) run scripts/build-uboot.sh ;;
	kernel) run scripts/build-kernel.sh ;;
	initramfs) run scripts/make-test-initramfs.sh ;;
	apps) run scripts/fetch-apps.sh; root scripts/build-apps.sh ;;
	rootfs) root scripts/build-rootfs.sh ;;
	# The version is read on the host: the container has no view of a worktree's .git file target.
	image) run env VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)" scripts/make-image.sh ;;
	# initramfs is FEL-only, so not part of a release.
	all) for s in uboot kernel apps rootfs image; do ./build.sh "$s"; done ;;
	run) [ $# -gt 0 ] || usage; run "$@" ;;
	*) usage ;;
esac
```

`./build.sh` is right inside `all`: the script `cd`s to its own directory first. `set -e` stops `all` at the first
failing stage.

- [ ] **Step 5: Run it, watch it pass.**

Run: `./build.sh image && ./build.sh run tests/image.sh && ls out/image && git describe --tags --always --dirty`
Expected: `PASS`; `ls` shows `SHA256SUMS`, `r36s-a33-ga36-debian-<V>.img`, `r36s-a33-ga36-debian-<V>.img.xz`,
where `<V>` equals the `git describe` output (a bare commit id plus `-dirty`, since this repo has no tags yet and
the tree is modified). That is Review Focus 1 exercised for real.

- [ ] **Step 6: Inject a stale image (Review Focus 2).**

Run: `touch out/image/r36s-a33-ga36-debian-old.img && ./build.sh run tests/image.sh; echo rc=$?`
Expected: `FAIL: want one .img in out/image, found: ...old.img ...` and `rc=1`. This proves the check sees a stale
file.

Run: `./build.sh image && ./build.sh run tests/image.sh && ls out/image | wc -l`
Expected: `PASS` and `3`: the rebuild removed the stale file.

- [ ] **Step 7: No stale references.**

Run: `grep -rn 'make-test-sdcard\|sdcard)' build.sh scripts tests`
Expected: no output.

- [ ] **Step 8: Local suite** (command in Setup). Expected: `suite-done` with no `FAILED` line (`workflow` is
skipped until Task 2 creates it).

- [ ] **Step 9: Commit.**

```bash
git add build.sh scripts/make-image.sh tests/image.sh
git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit -q \
  -m "Build the release image: ./build.sh image and all" \
  -m "scripts/make-image.sh replaces make-test-sdcard.sh: same layout and contents, named r36s-a33-ga36-debian-<git describe>.img, plus its .img.xz and SHA256SUMS in out/image. ./build.sh all runs uboot, kernel, apps, rootfs and image."
```

- [ ] **Step 10 [person]: card check.** The image content is unchanged, so this is a smoke check of the rename:
`lsblk`, then `sudo dd if=out/image/r36s-a33-ga36-debian-<V>.img of=/dev/sdX bs=4M conv=fsync status=progress`
with the right `sdX`. Expected: the board boots to ES; ga36-roms.service logs `ROMS partition present` (or restores
it) and the ROMs are listed. Record in the ledger.

### Task 2: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/image.yml`
- Create: `tests/workflow.sh`

**Interfaces:**
- Consumes: `./build.sh all`, `./build.sh run tests/container.sh`, `./build.sh run tests/image.sh`, and the
  `out/image/*.img.xz` / `out/image/SHA256SUMS` names from Task 1.
- Produces: workflow `image` (file `image.yml`); on `workflow_dispatch` an artifact named `image`; on a `v*` tag a
  draft release named after the tag. Task 4 uses `gh workflow run image.yml` and `gh run download -n image`.

- [ ] **Step 1: Failing test.** `tests/workflow.sh`:

```sh
#!/bin/sh
# CI workflow: builds the image on tag push and manual dispatch, stops early without armhf emulation, uploads the
# image on a dispatch and drafts a release on a tag. Static check only; the real run is recorded in
# docs/hardware/hardwareAnalysis.md. Run: ./build.sh run tests/workflow.sh
set -eu
w=.github/workflows/image.yml
[ -f "$w" ] || { echo "FAIL: $w missing"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
has() { grep -qE -- "$1" "$w" || bad "$2"; }
yamllint -d relaxed "$w" >/dev/null || bad "yamllint: $(yamllint -d relaxed -f parsable "$w" | head -1)"
has "tags: \['v\*'\]" "no v* tag trigger"
has '^  workflow_dispatch:' "no manual dispatch"
has 'contents: write' "no contents: write permission (needed for the release)"
has 'fetch-depth: 0' "checkout without tags: git describe would not see the version"
has 'docker/setup-qemu-action@v3' "no armhf binfmt on the runner"
has 'platforms: arm$' "setup-qemu-action without platforms: arm"
has 'for t in tests/\*\.sh' "the test suite does not run after the build"
has 'actions/upload-artifact@v4' "no artifact on manual dispatch"
has 'retention-days: 1' "artifact kept longer than a day (500 MB storage on a private free plan)"
has 'gh release create .*--draft' "release is not a draft (the person publishes after the device checklist)"
has 'out/image/\*\.img\.xz out/image/SHA256SUMS' "release does not attach the .img.xz and SHA256SUMS"
c=$(grep -n 'tests/container\.sh' "$w" | head -1 | cut -d: -f1)
a=$(grep -n '\./build\.sh all' "$w" | head -1 | cut -d: -f1)
[ -n "$c" ] && [ -n "$a" ] && [ "$c" -lt "$a" ] || bad "tests/container.sh must run before ./build.sh all"
[ $fail = 0 ] && echo PASS
exit $fail
```

- [ ] **Step 2: Run it, watch it fail.**

Run: `chmod +x tests/workflow.sh && ./build.sh run tests/workflow.sh`
Expected: `FAIL: .github/workflows/image.yml missing`, exit 1.

- [ ] **Step 3: Workflow.** `.github/workflows/image.yml`:

```yaml
# Builds the SD card image with ./build.sh all in the pinned build container.
# Manual dispatch: the image is a workflow artifact (kept one day). Tag push (vX.Y.Z): it goes to a draft GitHub
# Release, published by hand after the device checklist (spec section 5, release gate).
name: image
on:
  push:
    tags: ['v*']
  workflow_dispatch:
permissions:
  contents: write
jobs:
  image:
    runs-on: ubuntu-24.04
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Free disk space
        run: |
          sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache
          df -h /
      # apps and rootfs chroot into armhf; the F flag lets the privileged build container use the host's qemu.
      - uses: docker/setup-qemu-action@v3
        with:
          platforms: arm
      - name: Check the build container and armhf emulation
        run: ./build.sh run tests/container.sh
      - name: Build
        run: ./build.sh all
      # Every test that needs no board; checking on the device is the developer's job (README, Development).
      - name: Test
        run: |
          fail=0
          for t in tests/*.sh; do echo "== $t"; ./build.sh run "$t" || fail=1; done
          ls -l out/image
          df -h /
          exit $fail
      - if: github.event_name == 'workflow_dispatch'
        uses: actions/upload-artifact@v4
        with:
          name: image
          path: |
            out/image/*.img.xz
            out/image/SHA256SUMS
          compression-level: 0
          retention-days: 1
      - if: startsWith(github.ref, 'refs/tags/v')
        name: Draft release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          cat > notes.md <<EOF
          Tested board revision: FILL IN before publishing (for example GA36-MB V1.0-20250730).
          Checked by a person: FILL IN before publishing (the device checklist, spec section 4).

          Install: see README.md, section Install. Check the download with: sha256sum -c SHA256SUMS

          Sources: everything built into this image comes from this repository at $GITHUB_REF_NAME
          ($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/tree/$GITHUB_REF_NAME): the U-Boot, Linux and app patch
          series, the configs, and the pinned upstream versions in versions.env. Debian trixie package
          sources: https://sources.debian.org/
          EOF
          gh release create "$GITHUB_REF_NAME" out/image/*.img.xz out/image/SHA256SUMS --draft --title "$GITHUB_REF_NAME" --notes-file notes.md
```

The `FILL IN` lines are the release gate's two required facts, left for the person on purpose: the draft cannot be
published honestly without them.

- [ ] **Step 4: Run it, watch it pass.**

Run: `./build.sh run tests/workflow.sh`
Expected: `PASS`.

- [ ] **Step 5: Inject the ordering fault (Review Focus 3).** Temporarily move the container check after the build:

Run: `cp .github/workflows/image.yml "$W/image.yml.bak" && sed -i 's|run: ./build.sh run tests/container.sh|run: true|; s|run: ./build.sh all|run: ./build.sh all \&\& ./build.sh run tests/container.sh|' .github/workflows/image.yml && ./build.sh run tests/workflow.sh; echo rc=$?; cp "$W/image.yml.bak" .github/workflows/image.yml && ./build.sh run tests/workflow.sh`
Expected: `FAIL: tests/container.sh must run before ./build.sh all`, `rc=1`, then `PASS` after the restore
(`$W` is the plan workspace from the executing skill). `git diff --stat .github` afterwards shows nothing.

- [ ] **Step 6: Local suite** (command in Setup). Expected: `suite-done` with no `FAILED` line.

- [ ] **Step 7: Commit.**

```bash
git add .github/workflows/image.yml tests/workflow.sh
git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit -q \
  -m "Build the image in GitHub Actions on tag push and manual dispatch" \
  -m "One workflow runs ./build.sh all in the build container, with armhf binfmt from setup-qemu-action and the container check first. A manual dispatch uploads the image as an artifact; a v* tag creates a draft release with the .img.xz and SHA256SUMS, published by hand after the device checklist."
```

### Task 3: README install guide and spec

**Files:**
- Modify: `README.md`
- Modify: `docs/specs/2026-10-14-firmware-design.md` (status line, section 1 tree, section 5)

**Interfaces:**
- Consumes: the names from Tasks 1 and 2 (`out/image/r36s-a33-ga36-debian-<version>.img`, `.img.xz`,
  `SHA256SUMS`, `./build.sh image|all`, workflow `image`).
- Produces: nothing code depends on.

- [ ] **Step 1: Failing check.**

Run: `grep -n 'Install\|image|all' README.md; grep -n 'image/  \|sub-project 4 implemented' docs/specs/2026-10-14-firmware-design.md`
Expected: no `## Install` heading and no `image|all` in README; the spec still lists `image/` and does not say
sub-project 4 is implemented.

- [ ] **Step 2: README.** Replace the `**Status: ...**` paragraph and the `## What it will be` section with:

```markdown
**Status: v1.0 scope implemented and tested on GA36 V1.0.** EmulationStation with RetroArch, buttons, sound,
battery level, sleep, power-off and charging while off work from an SD card image built with `./build.sh all`,
locally or by the project's GitHub Actions workflow. **The repository is private: for now, images, issues and testing are for maintainers
only.** See
[`docs/porting-plan.md`](docs/porting-plan.md) for the roadmap and
[`docs/specs/2026-10-14-firmware-design.md`](docs/specs/2026-10-14-firmware-design.md) for the design.

## What it is

- Mainline Linux (6.18 LTS) and mainline U-Boot, with the board patches kept in this repository.
- Debian trixie armhf, EmulationStation (fcamod) and RetroArch.
- Runs from the SD card only; the stock card is not touched.
- Not yet: analog sticks and the charging animation (planned for v1.1).

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
   (check `sdX` with `lsblk` first: dd overwrites whatever it is given).
5. Insert the card and power on (hold the power key for more than 1 s). The first boot creates the `ROMS`
   partition on the rest of the card; put ROMs in its system folders (`/roms/<system>`) and BIOS files in
   `/roms/bios`.

- **Upgrading:** flashing a new release keeps the `ROMS` partition and its files, but back up `/roms/saves` (and
  anything else you care about on it) before you upgrade.
- **Back to stock:** power off and insert the stock card. Nothing on the console itself is changed.
- **V1.1 and V1.2 boards:** untested. A maintainer trying one should keep the boot log from the USB console (no
  soldering: connect the console's USB OTG port to a PC and open the serial port it shows, 115200 baud); UART
  only if the board does not get that far.

## Sources

Everything in an image comes from this repository at the release tag: the U-Boot, Linux and app patch series, the
configs, and the upstream versions pinned in [`versions.env`](versions.env). The Debian packages come from Debian
trixie; their sources are at <https://sources.debian.org/>.
```

In `## Development`, replace the stage list line with:

```markdown
- `./build.sh uboot|kernel|initramfs|apps|rootfs|image|all` builds into `out/`; `./build.sh run tests/<name>.sh` runs a
```

and add one bullet after the board-run bullet:

```markdown
- `./build.sh image` writes `out/image/r36s-a33-ga36-debian-<git describe>.img` (write it to a card with `dd`), its
  `.img.xz` and `SHA256SUMS`. Pushing a `vX.Y.Z` tag makes GitHub Actions build the same and attach it to a draft
  release, which is published by hand after the device checklist.
- **Tests:** CI runs every `tests/*.sh` after `./build.sh all`. **Nothing in CI touches a board: checking on the
  device (boot, picture, buttons, sound, sleep, charging) is the developer's job**, recorded in
  `docs/hardware/hardwareAnalysis.md`. It is expected before a release, not required to merge a pull request.
```

Keep line length within the file's existing 120-column wrap.

- [ ] **Step 3: Spec.**
  - Status line: replace `sub-project 3 implemented (plan [`../plans/implementation-plan.md`](../plans/implementation-plan.md)).`
    with `sub-project 3 implemented (plan [`../plans/implementation-plan.md`](../plans/implementation-plan.md));
    sub-project 4 implemented (plan [`../plans/2026-10-16-image-release-ci.md`](../plans/2026-10-16-image-release-ci.md)).`
  - Section 1 tree: delete the line `  image/                   sfdisk layout, extlinux template`. The `build.sh`
    line already reads `[uboot|kernel|rootfs|apps|image|all]`; leave it.
  - Section 5, first bullet: append `It also makes the development card: the uncompressed, sparse `.img` stays in
    `out/image` next to the `.img.xz`; the layout lives in the script (no `image/` directory).`
  - Section 5, CI bullet: append `On the runner, armhf binfmt comes from `docker/setup-qemu-action`; a manual
    dispatch uploads the image as a one-day artifact, a tag push creates a draft release that a person publishes
    after the release gate. The workflow runs every `tests/*.sh` after the build; device checks stay with the
    developer and gate releases, not pull requests. The repository is private, for maintainers only, for now.`
  - Section 5, ROMS bullet (the sentence wraps over two lines in the spec): replace `On a card too small for p3 the mount fails, the unit continues, and the
    folders are made on the rootfs.` with `On a card too small for p3 (under 4.58 GB: the image's 3.51 GB plus the
    1 GiB minimum of `ga36-roms-part`) the mount fails, the unit continues, and the folders are made on the rootfs,
    which has about 1.7 GiB available. Minimum card 4 GB, 8 GB or more recommended.`

- [ ] **Step 4: Check.**

Run: `grep -rn 'make-test-sdcard\|build.sh sdcard\|out/sdcard\|tests/sdcard' README.md docs/specs docs/hardware; grep -c '—' README.md docs/specs/2026-10-14-firmware-design.md; grep -n '^## Install\|^## Sources\|image|all' README.md; grep -n 'sub-project 4 implemented\|setup-qemu-action' docs/specs/2026-10-14-firmware-design.md; awk 'length > 120 {print FILENAME": "FNR}' README.md`
Expected: no match from the first grep; both em dash counts `0`; the README shows the two headings and the stage
list; the spec shows both new phrases; awk prints nothing.

- [ ] **Step 5: Commit.**

```bash
git add README.md docs/specs/2026-10-14-firmware-design.md
git -c user.name=Bepok -c user.email=wojtekjakubiszyn@gmail.com commit -q \
  -m "Document installing the release image and mark sub-project 4 in the spec" \
  -m "README: status, install guide (backup, flashing, revision check, upgrade, return to stock), sources. Spec: no image/ directory, the image script also makes the development card, CI binfmt from setup-qemu-action, private repository for now."
```

### Task 4: First real CI run (outward)

Runs after the final whole-branch review and the fast-forward of `main` (the workflow must be on the default
branch for `gh workflow run`). The `image` worktree stays until this task's commit is on `main` and pushed.
Every outward step is reported with its result before the next one.

- [ ] **Step 1 [person]: gh.** `sudo apt install gh`, then in this session `! gh auth login` (GitHub.com, SSH,
browser login). Expected: `gh auth status` shows `Logged in to github.com account Bepok`.

- [ ] **Step 2: Repository.** From the main checkout:

Run: `gh repo create Bepok/r36s-a33-ga36-debian --private --source=. --remote=origin --push && git ls-remote origin`
Expected: `refs/heads/main` at the local `main` commit. Only `main` is pushed.

- [ ] **Step 3: Run the workflow.**

Run: `gh workflow run image.yml --ref main`, then `gh run watch <id> --exit-status` in the background.
Expected: success, with every `== tests/...` in the `Test` step passing. Record from the log: total duration, the duration of the `Build` step, `df -h /` before and
after the build, and the `.img.xz` size.

- [ ] **Step 4: Check the artifact.**

Run: `gh run download <id> -n image -D out/ci && cd out/ci && sha256sum -c SHA256SUMS && xz -t *.img.xz`
Expected: `OK` and no xz error. The name carries the bare commit id of `main` (no tags yet).

- [ ] **Step 5 [person]: device.** `lsblk`, then
`xzcat out/ci/r36s-a33-ga36-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`.
Expected: boots to ES; the ROMS partition is restored with its files; a game runs with sound.

- [ ] **Step 6: Record and push.** In the `image` worktree, add a row to `docs/hardware/hardwareAnalysis.md`,
section "Userspace (V1.0)": `| CI image (GitHub Actions) | pass | <date>, run <id>: <total> total, Build <time>,
.img.xz <size> MB, disk free <before> -> <after>; the CI-built image boots to ES on V1.0 |`. Commit
("Record the first CI-built image"), fast-forward `main`, and `git push origin main`.

## Verification

- `tests/image.sh` and `tests/workflow.sh` pass, with the stale-file and ordering injections shown failing first.
- Local suite green; the full suite green in the Task 4 CI run.
- Task 1 card and Task 4 CI image both boot to ES on V1.0.
- Final whole-branch review on the most capable model, one fix pass, then `main` fast-forwarded and pushed.
