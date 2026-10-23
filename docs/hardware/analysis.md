# R36S clone (GA36-MB V1.0-20250730) - analysis notes

Paths in "Sources" and below refer to the original research workspace; only the text artifacts are kept in
this repository (`docs/hardware/`).

Date: 2026-10-13

## Sources

| What | Where |
|---|---|
| Upstream notes and partial dumps | `R36S-console-clone---GA36-MB-V1.0-20250730/` (clone of github.com/phaseloop/R36S-console-clone---GA36-MB-V1.0-20250730, HEAD `e4d07d9`) |
| Stock recovery image | `recovery-img/r36-a33-recovery-img.zip` (877 MB) -> `recovery-img/r36s-a33-recovery.img` (2,543,237,120 bytes, dated 2025-12-26) |
| Carved partitions and extracted content | `recovery-img/parts/` (`SHA256SUMS` covers the eight carved files) |

The upstream repo contains no code - only notes and partial dumps: MBR (1 KB), p5 U-Boot env, p6 boot image,
`.dtbo` overlays from the rootfs, and a 512-byte `magic.bin` the README itself says is not the board config.
The bootloader area, the `SYSTEM` squashfs, p2 and p8 are missing from it; the recovery image supplies all of them.

## Hardware (per upstream README)

- SoC marked `RK3326` is actually an **Allwinner A33** (sun8i, Cortex-A7, Mali400). Same family as the
  Nintendo NES Classic (R16 = renamed A33), so linux-sunxi research on that device applies.
- Runs a vendor EmuELEC build on the legacy linux-sunxi 3.4 kernel; public EmuELEC/R36S images do not boot.

## Recovery image layout

DOS label `0x815d9b77`, 512-byte sectors. Same layout as the upstream original except p1.

| Part | Start | Sectors | Type | Carved file | Contents |
|---|---|---|---|---|---|
| - | 0 | 1 | MBR | `mbr.bin` | partition table |
| - | 1 | 73727 | raw | `bootloader-area.bin` | EBR at sector 1, `eGON.BT0` (boot0) at byte 8192 of the disk |
| p1 | 4956161 | 11099 | 0x0b | `p1-fat32-roms.img` | FAT12 (5.4 MB), grows to fill the card on first boot |
| p2 | 73728 | 65536 | 0x06, boot | `p2-fat16-boot.img` | FAT16, boot logo / battery images / fonts |
| p3 | 1 | 4956160 | 0x85 | - | extended container for p5-p8 |
| p5 | 139264 | 32768 | 0x83 | `p5-uboot-env.img` | raw U-Boot environment |
| p6 | 172032 | 65536 | 0x83 | `p6-bootimg.img` | Android boot image |
| p7 | 237568 | 1572864 | 0x83 | `p7-emuelec.img` | FAT16 labelled `EMUELEC`: `SYSTEM`, `LOW_PWR.BMP` |
| p8 | 1810432 | 3145728 | 0x83 | `p8-storage.img` | ext4 (UUID `8318c954-97a7-4b3f-968b-76f68a587427`), config, logs, swap, cores |

Observations:

- **p5 and p6 are byte-identical** to the upstream repo's `uboot-partition.img` and `kernel.img`: the recovery
  image carries the same boot chain as the dumped console.
- **p1 starts one sector later** than on the original card (4956161 vs 4956160). On the original, p1 overlapped the
  last sector of the extended partition; the recovery image fixes that.
- **p2's FAT16 boot sector claims 262144 sectors (128 MB)** while the partition is 32 MB. Tools that trust the
  boot sector may read past the partition end.

## Hardware

See [`hardwareAnalysis.md`](hardwareAnalysis.md): decoded board config, kernel config, pin map and input table.

## Boot chain

1. boot0 (`eGON.BT0`) at 8 KB, then U-Boot 2017.09 at sector 38192 (19096 KiB) with the board config
   (`sys_config`, script.bin format) appended. Details in `hardwareAnalysis.md`.
2. U-Boot env (p5): `bootcmd=run setargs_mmc boot_normal`, `boot_normal=sunxi_flash read 40007800 boot; boota 40007800`,
   `root=/dev/mmcblk0p7`, `disk=/dev/mmcblk0p8`, `console=ttyS2,115200`, `init=/init`.
3. Android boot image (p6), header v0, extracted to `parts/p6-bootimg/`:

   | Field | Value |
   |---|---|
   | name | `sun8i` |
   | cmdline | empty (supplied by U-Boot env) |
   | page size | 2048 |
   | kernel | 13,213,848 bytes at `0x40008000`, offset `0x800` |
   | ramdisk | 3,040,904 bytes (gzip cpio) at `0x41000000`, offset `0xc9b000` |
   | second | none (`second_addr=0x40f00000`) |
   | tags | `0x40000100` |

   - `kernel` is an **uncompressed** ARM Image (no zImage magic):
     `Linux version 3.4.39 (lxl@lxl) (gcc 4.6.3, Linaro GCC 2012.02) #493 SMP PREEMPT Mon Aug 18 10:47:18 CST 2025`.
   - `ramdisk-root/`: 117 files, LibreELEC-style `init` and `functions`.
   - `ramdisk-root/` contains a `.git` directory, but it is an empty repository (no refs, no objects) -
     nothing to recover.
4. Ramdisk `init` (`mount_sysroot()`, line 280) loop-mounts `/flash/SYSTEM` read-only at `/sysroot`
   (copied to RAM first if `SYSTEM_TORAM=yes`). `/flash` is p7; p8 (`disk=`) is the writable `/storage`.

## Root filesystem (`SYSTEM`)

Extracted to `parts/p7-emuelec/system-root/` (1.1 GB). p7 has no `SYSTEM.md5`, so there is no vendor checksum.

- Squashfs 4.0, lzo (`lzo1x_999`, level 9), block size 512 KiB, 12276 inodes, 425,447,076 bytes,
  created 2025-08-22.
- Extraction complete: compared with `unsquashfs -lc`, the only differences are empty mount-point directories.
- `os-release`:
  - `VERSION="4.7-Nexus_devel_20250822204445"`, `BUILD_ID=821dd42b865cfcace883d5fb5c951252afb25949`
  - `LIBREELEC_PROJECT="Allwinner"`, `COREELEC_DEVICE="A33"`
  - `BUG_REPORT_URL="git@192.168.0.55:emuelec/emuelec"` - vendor's private git server
- **Architecture label is wrong:** `LIBREELEC_ARCH`/`COREELEC_ARCH` say `OdroidGoAdvance.aarch64`, but binaries
  are 32-bit ARM (`busybox`: ELF 32-bit LSB, ARM, EABI5). The vendor reused the OGA arch string on an
  ARMv7 build.
- `share/bootloader/overlays/*.dtbo` are A64/H3/H5/H6 overlays - none are for A33; likely unused leftovers.

## Open questions

- Stick UART baud rate and frame header: answered, 9600 8N1 with `A7 10 00` frames (`hardwareAnalysis.md`, "Analog
  sticks").
- p2 (boot assets) not unpacked; p8 only partly read (`init.log`, `joypads/`).

## Method notes

No `mtools`, `abootimg` or `binwalk` were installed. Partitions were carved with `dd`; the boot image was split
and p7 read with two small ad-hoc Python scripts (Android boot header v0 parser, FAT16 cluster-chain reader),
not kept in the workspace. Squashfs extracted with `unsquashfs -no-xattrs`; ramdisk with
`cpio -idm --no-absolute-filenames`.
