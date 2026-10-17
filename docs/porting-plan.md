# Porting plan

Date: 2026-10-14

## Context

The GA36-MB V1.0-20250730 is an R36S clone built on an Allwinner A33 (4x Cortex-A7, Mali-400 MP2, 512 MiB RAM),
sold as "RK3326". It runs only a vendor EmuELEC 4.7 on a linux-sunxi 3.4 kernel whose source is not published.
This repository builds a firmware other GA36 owners can install. The design is in
[`specs/2026-10-14-firmware-design.md`](specs/2026-10-14-firmware-design.md); hardware research is in
[`hardware/`](hardware/).

## Findings: custom firmware support

Source: handhelds.wiki `R36S_Clones`, read via the Wayback Machine (the live site blocks scripted fetches).

- No firmware in "Custom Firmware for the EmuELEC Clone" supports the GA36: dArkOS4Clone, ArkOS4clone
  (lcdyk0517/arkos4clone), dArkOSRE (southoz/dArkOS-G80CA-RE), dArkOS (christianhaitian), ArkOS K36 (AeolusUX,
  stopped 2025-08-25), ROCKNIX, UnofficialOS. All target the RK3326; their clone and panel variants are DTB swaps.
- The wiki lists the GA36 under "Fakes": "No custom firmware support as of 2026". Revisions: V1.0-20250730,
  V1.1-20251025, V1.2-20260416 (some may be A23, dual-core). Stock backups exist from phaseloop (V1.0),
  TheAlexClavijo and k8alfa (V1.1).
- A DTB swap cannot work: different SoC vendor, bootloader, kernel and GPU (Mali-400 vs Mali-G31), and a 32-bit
  userspace. Details: [`hardware/hardwareAnalysis.md`](hardware/hardwareAnalysis.md), "Porting notes: arkos4clone".
- ROCKNIX's Allwinner support is the H700 (sun50i, aarch64); all its builds are aarch64.
- EmuELEC itself is stalled: the lead developer stepped back in April 2023, the last test build is
  v4.8-TEST-04212024.

## Roadmap

| Sub-project | Content | Release |
|---|---|---|
| 1. Boot | U-Boot for GA36, SD layout, FEL development loop | v1.0 |
| 2. Kernel | board DTS, NV3051D panel variant, kernel config | v1.0 |
| 3. Userspace | Debian armhf rootfs, ES fcamod with patched libgo2, RetroArch and cores | v1.0 |
| 4. Image and release | `.img.xz`, install guide, CI | v1.0 |
| Analog sticks | `ga36-gamepad` serdev driver for the buttons and the stick MCU on UART1 | v1.1 |
| Charging animation | Linux-side charge mode as `init=` | v1.1 |
| Panel at 60 Hz | 29.7 MHz, htotal 955 (60.04 Hz); performance governor while a game runs | v1.1 |
| DOS | DOSBox Pure libretro core | v1.1 |
| N64 and PSP | mupen64plus-next and PPSSPP, shipped as experimental however they measure | v1.1 |
| Windows games | Box86 and i386 Wine with a per-game X server and gptokeyb, experimental | v1.1 |

Sub-projects 1 and 2 are planned first; each sub-project gets its own implementation plan.

### Before v1.1

- Read the stock system's rail voltages (`/sys/class/regulator/*/microvolts` via the cron probe), to confirm ALDO1
  (3.0 V, from the reference design) and DC5LDO, which `[power_sply]` does not list.
- Charge mode, still to check on the device (hardware notes, "Charge mode at the 3 % cutoff" and "Low-battery
  drain"): drain the battery to the 3 % shutdown, then plug in. Expected: the charge screen or a clean power-off.
  If it restart-loops, U-Boot has to skip charge mode below a battery voltage read from the AXP.
- Charge mode with a charger on the AC jack (`axp22x-ac`): only the USB cable has been checked.
- Charge mode, deferred from the review: if entering s2idle fails, `ga36-charge` retries every 500 ms while awake,
  with no backoff. `tests/charge.c` covers only the helpers, and `tests/uboot-config.sh` checks only that the U-Boot
  strings exist, not the boot-source bit test; the device checks are the real coverage.
- Sticks, still to check on the device (hardware notes, "Analog sticks (v1.1)"): a digital-only PSX game that
  worked in v1.0 still takes the D-pad with the DualShock pad; Ape Escape (both sticks) and Tony Hawk.
- Sticks, deferred from the review: if the stick MCU stops sending (a reset or brown-out), `ga36-gamepad` keeps the
  last frame, so a stick held at that moment stays held until reboot. Never seen; the fix is to report centre when no
  frame came for about 200 ms.

### Revisit later

Not in v1; to be measured on the device first.

- Arcade (FBNeo): heavy core and build.
- Nintendo DS.

## Open risks

- Headphone detect source unknown; fallback is both outputs on plus a manual toggle.
- Vol+/Vol- source unknown (likely LRADC); needed by sub-project 3.
