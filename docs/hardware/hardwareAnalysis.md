# R36S clone (GA36-MB V1.0-20250730) - hardware description

Static analysis of the recovery image (see `analysis.md`), plus on-device tests over USB FEL and UART2
(section "On-device tests"; rows marked **hardware**).

**Status legend**
- **confirmed** - two independent sources agree (e.g. board config + driver code, or driver + userspace mapping)
- **config-only** - stated by `sys_config.fex` alone; may be stale template data
- **inferred** - reasoned from names/strings, not directly stated anywhere
- **hardware** - measured on a real unit

## Extracted files

| File | What | Origin |
|---|---|---|
| `sys_config.bin` (vendor binary, not in this repo) | compiled board config (`script.bin` format, v1.2, 78 sections, 49152 bytes) | appended to U-Boot: `bootloader-area.bin` offset 19553792 + 0xc0000 |
| `sys_config.fex` | the same, decoded with `bin2fex` (sunxi-tools `bc96c0a`) | |
| `u-boot.bin` (vendor binary, not in this repo) | U-Boot `2017.09-g05bceb2-dirty #lxl (Jul 14 2025 - 11:58:12 +0800)`, 0xc0000 bytes | `bootloader-area.bin` offset 19553792 (disk sector 38192 = 19096 KiB) |
| `kernel-3.4.39.config` | kernel config embedded in the kernel (`IKCFG_ST`) | `p6-bootimg/kernel` |
| `panel-init.txt` | DSI panel init command table, decoded | `lcd.ko` `.data` + 0xd688 (`LCM_LT080B21BA94_setting`) |

U-Boot image header: magic `uboot`, `length=0xcc000`, `uboot_length=0xc0000`, version `1.1.0`, platform `1.0.0`,
`run_addr=0x4a000000`. The sunxi checksum (stamp `0x5F0A6C39`) recomputes to the stored `0x05eace0c`, so the carve
boundaries are right. The 48 KiB after `uboot_length` is the board config - this is the "script.bin" the upstream
README was looking for (`magic.bin` is not it).

## Summary

| Subsystem | Value | Status |
|---|---|---|
| SoC | Allwinner A33 (sun8iw5p1), quad Cortex-A7 | **hardware** - FEL `soc=00001667(A33)`; also `CONFIG_ARCH_SUN8IW5P1=y`, Mali400 |
| CPU DVFS | 120 MHz - 1.2 GHz (`max_freq`), extremity 1.344 GHz, boot 1008 MHz | config-only - `[dvfs_table]`, `[target]` |
| DRAM | DDR3 (`dram_type = 3`) @ 552 MHz, **512 MiB** | **hardware** - mainline SPL inits it at 552 MHz and reports 512 MiB |
| PMIC | X-Powers AXP22x family (probably AXP223) on RSB (`PL00`/`PL01`) | AXP22x confirmed - `[pmu1_para]`, `[power_sply]`, `CONFIG_AW_AXP22=y`; AXP223 inferred |
| Battery | 3000 mAh, charge 4.2 V, power-off 3.3 V | config-only - `[pmu1_para]` |
| Display | MIPI DSI, 2 lanes, 640x480, panel driver `jd9366_8inch`, PWM0 backlight | confirmed - `[lcd0_para]` + `jd9366_8inch.c` compiled into `lcd.ko` |
| Buttons | 16 GPIO buttons (PE04-PE17, PB02, PB03) via `udt_joystick.ko` | confirmed - driver table + RetroArch/SDL mapping |
| Analog sticks | 2 sticks, 4 axes, 8-bit values from an MCU on UART1 (`/dev/ttyS1`), with a challenge-response check | confirmed on the device: 9600 8N1, handshake, 8-byte frames (see "Analog sticks") |
| Audio | A33 internal codec, PA enable on `PH09`, headphone detect via switch `h2w` | config-only + `CONFIG_SND_SUNXI_SOC_AUDIOCODEC=y` |
| Storage | SD card on SDC0 (`PF00`-`PF05`), card detect `PB04`; no eMMC/NAND | confirmed - `[mmc0_para]`, `card_ctrl = 0` boot, U-Boot env `mmcblk0` |
| Debug UART | UART2 on `PB00`/`PB01` = `ttyS2`, 115200 | **hardware** - mainline SPL output captured; also `[uart2]` + U-Boot env; pad ripped off on the V1.0 development board after these tests (2026-10-14) |
| USB | one OTG port (USB0), ID pin `PH08`, VBUS via AXP | config-only - `[usbc0]` |
| Wi-Fi / BT | none (`wifi_used = 0`, `bt_used = 0`; RTL8723BS entries are template leftovers) | config-only |

## Power (`[power_sply]`, `[pmu1_para]`, `[s_rsb0]`)

| Rail | Voltage | Note |
|---|---|---|
| DCDC1 | 3.0 V | SD card supply (`sdc_power_supply = "axp22_dcdc1"`), USB ID/VBUS reference |
| DCDC2 | 1.1 V | system / GPU - inferred (mainline A33 boards name it `vdd-sys`) |
| DCDC3 | 1.2 V | CPU - inferred (mainline A33 boards, e.g. `sun8i-a33-sinlinx-sina33.dts`, name it `vdd-cpu`) |
| DCDC5 | 1.5 V | DRAM (DDR3) - inferred from voltage |
| ALDO2 / ALDO3 / DLDO3 | 2.5 / 3.0 / 3.0 V | |
| DC1SW | switch from DCDC1 | LCD power (`lcd_power = "axp22_dc1sw"`) |

- Bus: `[s_rsb0] s_rsb_used = 1` on `PL00` (SCK) / `PL01` (SDA); all `[twi0-2]` have `twi_used = 0`, so the
  `pmu_twi_addr = 52` (0x34) / `pmu_twi_id = 1` fields are legacy and the PMIC is reached over RSB.
  The kernel never reads `s_rsb_used` (`CONFIG_SUNXI_ARISC=y`: the ARISC co-processor firmware owns the bus),
  so the RSB wiring is config-only.
- Battery: `pmu_battery_cap = 3000`, `pmu_battery_rdc = 119`, OCV table `pmu_bat_para1..32`, charge current
  300 mA running / 600 mA suspended or off, warning at 15 %.
- Power key: long press 1.5 s, forced off at 6 s (`pmu_peklong_time`, `pmu_pekoff_time`).
  Userspace power handling: `/usr/bin/udt_pwr_events.sh` polls `/sys/devices/platform/micro_gamepad/power_key`.

## Display (`[lcd0_para]`, `[pwm0_para]`, `[disp_init]`)

| Field | Value |
|---|---|
| Interface | `lcd_if = 4` (DSI), `lcd_dsi_lane = 2`, `lcd_dsi_if = 2`, format 0 (RGB888), EoTp on |
| Resolution | 640 x 480 |
| Timing | `lcd_dclk_freq = 30` MHz, `ht = 1040`, `hbp = 120`, `hspw = 40`, `vt = 518`, `vbp = 12`, `vspw = 6` (about 55.7 Hz) |
| Panel driver | `jd9366_8inch` - the name is reused; the timing says 640x480, not an 8" panel |
| Reset/enable | `lcd_gpio_0 = PH07` output |
| Power | `axp22_dc1sw` |
| Backlight | PWM0 on `PH00`, 20 kHz, `lcd0_backlight = 204` default; userspace writes `/sys/devices/virtual/disp/disp/attr/lcdbl` |

Panel sequence, from the disassembly of the `jd9366_8inch.c` functions in `lcd.ko` (confirmed):

1. Open flow: `LCD_power_on` (`axp22_dc1sw` on, pins to function) - 30 ms - `LCD_panel_init` - 50 ms -
   TCON enable - 100 ms - backlight (PWM, then enable).
2. `LCD_panel_init`: reset on `lcd_gpio_0` (`PH07`): high, 5 ms, low, 10 ms, high, 10 ms. Then it walks the table
   `LCM_LT080B21BA94_setting` (151 entries of 72 bytes: `u8 cmd`, `u32 len`, `u8 para[64]`; `len 0xFE` = delay,
   `0xFF` = end), sending each with `dsi_dcs_wr`. Then DSI HS clock on, 20 ms.
3. The table: 4 register pages selected with `FF 30`, `FF 52`, `FF 0n` (n = 1, 2, 3, 0), 133 register writes, then
   `36 02`, `11` (sleep out), 120 ms, `29` (display on), 20 ms. Full list in `panel-init.txt`.
4. Close flow: backlight off - TCON off - `28` (display off), 10 ms, `10` (sleep in), 10 ms - power off.

The `FF 30 52 0n` page-select is not the JD9366 command set (JD9366 pages with `E0`); it matches the
Newvision NV3051D. **Confirmed:** mainline `drivers/gpu/drm/panel/panel-newvision-nv3051d.c` (Anbernic RG351V/RG353P,
Powkiddy RK2023 panels, also 640x480) opens with the same `FF 30`, `FF 52`, `FF 01`, `E3 00` and ends with `36 02`;
the register values differ. The file name `jd9366_8inch` and the table name `LT080B21BA94` are reused labels.

## Input (`udt_joystick.ko`)

Vendor driver `drivers/input/joystick/udt_joystick.c` (author `lxl/lxl@163.com`, "micro gamepad drvier"),
built from `/home/lxl/work/a33_git/lichee/linux-3.4` (`CONFIG_JOYSTICK_UDT=m`). The module still has full DWARF debug info.
It registers platform device `micro_gamepad` with sysfs attributes `power_key`, `fn_key`, `wake_lock`, `first_start`,
and a second input device `udt_keyboard`.

### Buttons

From the driver's `.rodata` tables `joy_gpio_key[16]` / `joy_gpio_key_map[16]` (plain ints, no relocations).
GPIO numbers decoded as `bank * 32 + pin` (PA = 0). The joydev index is the order of the key codes; it matches
`/etc/retroarch-joypad-autoconfig/micro_gamepad.cfg` and the SDL entry `190000006d6963726f5f67616d657000`
exactly, so every row is **confirmed**.

| GPIO | Pin | Key code | Linux name | joydev # | RetroArch / SDL |
|---|---|---|---|---|---|
| 141 | PE13 | 304 | BTN_SOUTH (A) | 0 | b / a |
| 140 | PE12 | 305 | BTN_EAST (B) | 1 | a / b |
| 139 | PE11 | 307 | BTN_NORTH (X) | 2 | x / x |
| 138 | PE10 | 308 | BTN_WEST (Y) | 3 | y / y |
| 143 | PE15 | 310 | BTN_TL | 4 | l / leftshoulder |
| 145 | PE17 | 311 | BTN_TR | 5 | r / rightshoulder |
| 142 | PE14 | 312 | BTN_TL2 | 6 | l2 / lefttrigger |
| 144 | PE16 | 313 | BTN_TR2 | 7 | r2 / righttrigger |
| 133 | PE05 | 314 | BTN_SELECT | 8 | select (hotkey) / back |
| 132 | PE04 | 315 | BTN_START | 9 | start / start |
| 35 | PB03 | 317 | BTN_THUMBL | 11 | l3 / leftstick |
| 34 | PB02 | 318 | BTN_THUMBR | 12 | r3 / rightstick |
| 137 | PE09 | 544 | BTN_DPAD_UP | 13 | up / dpup |
| 136 | PE08 | 545 | BTN_DPAD_DOWN | 14 | down / dpdown |
| 135 | PE07 | 546 | BTN_DPAD_LEFT | 15 | left / dpleft |
| 134 | PE06 | 547 | BTN_DPAD_RIGHT | 16 | right / dpright |

- All buttons are active-low (the event value is `!gpio_get_value`), polled every 10 ms by delayed work; the first
  poll runs 1 s after probe.
- **FN key: GPIO 129 = `PE01`**, requested as `fn_key`. `464` in `.data` is not a GPIO but the key code
  (`KEY_FN`, 0x1d0), readable/writable via sysfs `fn_key`. With the default `464` the FN event goes to the second
  input device `udt_keyboard`; any other value sends that code on the joystick device instead
  (`emuelecRunEmu.sh` has commented-out writes of `318` and `464`). joydev #10 stays unused in the shipped mapping.
- PE04-PE17 are CSI data pins (`[csi0] vip_used = 0`, camera unused); PE12/PE13 overlap the disabled `[twi2]`.
- `[gpio_para]` additionally exports `PH01`, `PH02`, `PH03`, `PL04`, `PG13` as plain outputs (purpose unknown, config-only).

### Analog sticks

- Userspace: 4 axes (`leftx a0`, `lefty a1`, `rightx a2`, `righty a3`) in both RetroArch and SDL mappings - confirmed.
From the disassembly of `udt_joystick.ko` (confirmed unless marked):

- An input-polled device `micro_gamepad` (bus 0x19, 20 ms poll) reads 4 bytes `buff_rcv[3..6]`. `buff_rcv` is an
  undefined (imported) symbol: another kernel component fills it from the MCU on UART1 (`[uart1]` `PG06` TX /
  `PG07` RX). The module itself only writes to `/dev/ttyS1` (`filp_open` + `vfs_write`). The filler is a vendor
  hook in the UART IRQ handler `sw_uart_irq` that acts on IRQ 33 (UART1) only; it stores frames that start with
  `A7 10 00`. The port runs at the driver default, 9600 8N1 (no `stty`, no `[uart1]` baud key).
- Protocol, confirmed on V1.0 with our kernel (2026-10-19): the MCU is silent until the challenge; it answers once with
  `A7 10 00 b3 b4 b5 b6 00`, `b[2+k] = (r_k + k) ^ 0x5A ^ b6`; after the ack `A6 01 01 01 01 01` it streams 8-byte
  frames `A7 10 00 X Y RX RY 00` at about 29 Hz, no checksum. A few stray bytes (`FD 01 FE`) can come first. Rest
  `80 81 7E 7F`; widest seen left X `08`-`DE`, left Y `27`-`EA`, right X `14`-`E6`, right Y `1D`-`DE` (two 20 s
  captures, rest identical in both).
- Mapping: `[3]` -> ABS_X (inverted), `[4]` -> ABS_Y (inverted), `[5]` -> ABS_RX, `[6]` -> ABS_RY; range 0-18.
- `adc_val_to_axis` (0-255 -> 0-18, centre 9): <=50 -> 0; 51-108 -> (v-50)/7+1; 109-147 -> 9 (deadzone);
  148-204 -> (v-148)/7+10; >204 -> 18. Only 19 steps per axis.

Anti-clone check (runs only while `encry_flag == 0`, skipped when all four stick bytes are 0):

- `encry_rw(0)` writes `A6 01 00 r1 r2 r3` (3 random bytes) to `/dev/ttyS1`.
- The reply is accepted when, for k = 1..3, `(buff_rcv[6] ^ buff_rcv[2+k] ^ 0x5A) - k == r_k`.
  Success: `encry_flag = 1`, acknowledge `A6 01 01 01 01 01` (`encry_rw(1)`).
- Failure: resend after 30 ms, `encry_retry++`. On the 3rd failure a delayed work fires `tty_work_func` after
  120 s, which calls `panic("kernel panic: memory malloc fail")` - a deliberate kill switch disguised as an
  out-of-memory crash. A board without the vendor MCU firmware reboot-loops 2 minutes after boot.
- `call_udt_recovery` runs the usermode helper `/usr/bin/lsz G28 recovery` and logs `udt recovery 11`. It has no
  caller in the module and is not exported, so it is dead code here. `lsz` is the vendor's 32-bit ARM GUI tool
  (ThorVG/LodePNG, strings `System recovery completed`, `jd_mcu_load`/`jd_mcu_output`, `/storage/roms/udt_result.txt`)
  - a factory test / recovery app that likely also flashes the MCU (inferred).

## Audio (`[audio0]`)

Internal A33 codec (`CONFIG_SND_SUNXI_SOC_AUDIOCODEC=y`), `headphone_direct_used = 1`, `pa_double_used = 1`,
speaker amplifier enable `audio_pa_ctrl = PH09`. Headphone state is read in userspace from
`/sys/class/switch/h2w/state` (`udt_pwr_events.sh`). `[i2s0]` is disabled.

## Storage, boot and USB

- SD card: SDC0 4-bit on `PF00-PF05`, card detect `PB04` (`sdc_detmode = 2`), supply `axp22_dcdc1`.
  Boot media `[card0_boot_para]` = SDC0. `[mmc2_para]` (eMMC) and `[nand0_para]` are disabled.
- `[mmc1_para]` (`PG00-PG05`, `sdc_isio = 1`) is enabled, but Wi-Fi and BT are off.
  Probably a template leftover - config-only.
- FEL / recovery keys: `[fel_key] fel_key_min = 2`, `fel_key_max = 6`; U-Boot env `recovery_key_value_*`
  `0x10-0x13`, `fastboot_key_value_*` `0x2-0x8`. These are LRADC ranges; which physical button produces them is unknown.
- USB0 OTG: `usb_port_type = 2`, ID pin `PH08`, VBUS detect via AXP, VBUS drive `power4` (AXP GPIO).
  `[usbc1]` disabled. Kernel modules `cdc_ether.ko`, `meig_cdc_driver.ko` suggest USB network/modem support.

## Other leftovers in the config

`ctp_para` (FT5x touch, 800x480), `gsensor_para`, `gy_para`, `ls_para`, `motor_para`, `leds_para`, `csi0`,
`wifi_para`, `bt_para`, `3g_para` are all `*_used = 0`. They come from the Allwinner A33 tablet reference config
and say nothing about this board.

## Ramdisk `.git`

`p6-bootimg/ramdisk-root/.git` is an empty repository: `HEAD -> refs/heads/master`, no refs, no packed refs,
12 KiB of empty `objects/`, only sample hooks. No history to recover.

## Method

- Board config: U-Boot and the appended `sys_config` carved from `bootloader-area.bin` by the legacy sunxi header,
  boundaries checked by recomputing the header checksum; decoded with `bin2fex` built from sunxi-tools source.
- Kernel config: the gzip stream after `IKCFG_ST` in `p6-bootimg/kernel`.
- Drivers: `udt_joystick.ko` and `lcd.ko` from `system-root/usr/lib/modules` disassembled with
  `arm-linux-gnueabihf-objdump -dr` (binutils 2.46, unpacked from the Debian package without installing).
  Pin numbers come from `.rodata` tables and `gpio_request` arguments; the panel table was located from the
  `LCD_panel_init` literal pool (`.data` + 0xd688) and decoded by its loop (72-byte entries).
- Userspace cross-checks: RetroArch/SDL joypad configs and `udt_pwr_events.sh` in the `SYSTEM` squashfs,
  `joypads/` and `init.log` from p8 read with `debugfs`.

## Porting notes: arkos4clone

[arkos4clone](https://github.com/lcdyk0517/arkos4clone) ports ArkOS/dArkOS to RK3326 clones: one Rockchip
kernel and U-Boot, plus a DTB per clone. This board cannot be added there as a supported device. Each of these
blocks it on its own:

1. **CPU architecture:** the A33 is a Cortex-A7, 32-bit ARMv7 only (the vendor `busybox` is an ELF 32-bit ARM EABI5
   binary). ArkOS userspace is aarch64.
2. **Kernel and bootloader:** a Rockchip 4.4 kernel and Rockchip U-Boot cannot boot an Allwinner SoC. The vendor
   3.4 kernel has no device tree support (`# CONFIG_USE_OF is not set`), so there is no DTB to adapt.
3. **GPU:** Mali-400 (lima) instead of the RK3326's Mali-G31 (panfrost).
4. **Sticks:** they come from the vendor MCU over UART1 through `udt_joystick.ko`, and no upstream driver exists.

A workable route would be a separate port: a mainline kernel, a hand-written DTS based on `sun8i-a33.dtsi`
using the pin map above, the panel added to the NV3051D driver, a small serdev driver for the stick MCU
(it would not need the anti-clone check), and an armhf distribution. See "Device tree on A33 (mainline)".

## Device tree on A33 (mainline)

The vendor BSP (linux-sunxi 3.4, lichee U-Boot) describes the board with `sys_config` and has no device tree.
Mainline Linux and mainline U-Boot use only device tree, and the A33 is well supported there. Checked against
upstream `master`, 2026-10-13:

- **SoC description:** `arch/arm/boot/dts/allwinner/sun8i-a33.dtsi` (includes `sun8i-a23-a33.dtsi`). It already
  has nodes for every block this board uses:
  - display: `tcon0`, display frontend/backend, `dsi@1ca0000` (`allwinner,sun6i-a31-mipi-dsi`), `d-phy@1ca1000`;
  - GPU `mali` (lima) with OPPs 144-384 MHz;
  - codec `allwinner,sun8i-a33-codec`, `usb_otg` (`sun8i-a33-musb`), thermal `ths`, CPU OPPs 120 MHz-1.008 GHz,
    `pio`.

  DSI, D-PHY and codec are `disabled` in the dtsi; a board file enables them.
- **Existing boards:** 8 A33 (`sun8i-a33-olinuxino`, `-sinlinx-sina33`, `-q8-tablet`, `-ga10h-v1.1`, ...) and 4 R16
  (`sun8i-r16-nintendo-nes-classic`, `-super-nes-classic`, `-bananapi-m2m`, `-parrot`). `sun8i-a33-sinlinx-sina33`
  drives an RGB panel from `tcon0`, not DSI; whether any in-tree A33 board uses DSI was not checked.
- **PMIC:** AXP223 on `&r_rsb` (`x-powers,axp223`, `reg = <0x3a3>`, `#include "axp223.dtsi"`), e.g.
  `sun8i-a33-sinlinx-sina33.dts`.
- **Panel:** `panel-newvision-nv3051d.c` hardcodes 4 DSI lanes and has its own init table and modes; this board needs
  2 lanes, the table in `panel-init.txt` and its 640x480 mode. That is a new compatible and per-panel data
  in an existing driver, not a new driver.
- **Bootloader:** mainline U-Boot has A33 defconfigs (e.g. `A33-OLinuXino_defconfig`), with SPL doing DRAM init.
  This replaces boot0 and lichee U-Boot, so `dram_para` values above would go into the defconfig.

What a board DTS for this console would contain (mapping of the vendor config onto mainline bindings):

| Function | Mainline binding | Values from this doc |
|---|---|---|
| PMIC, rails | `&r_rsb` + `axp223.dtsi` regulators | DCDC1 3.0 V, DCDC2 1.1 V, DCDC3 1.2 V, DCDC5 1.5 V, ALDO2/3, DLDO3, DC1SW |
| Panel | `&dsi` child, NV3051D compatible | reset `PH7`, power `dc1sw`, 2 lanes |
| Backlight | `pwm-backlight` on `&pwm` | PWM0 `PH0`, 20 kHz |
| Buttons | `gameconsole,ga36-gamepad` node under `&uart1` (driver `ga36-gamepad`), `GPIO_ACTIVE_LOW` | pins and codes from the Input table, FN on `PE1` |
| Sticks | the same node, a `serdev` child of `&uart1` | MCU protocol in "Analog sticks" |
| SD | `&mmc0`, `cd-gpios` | `PF0-PF5`, CD `PB4` |
| Audio | `&codec`, `&dai`, sound card, amplifier enable GPIO | PA `PH9` |
| USB | `&usb_otg`, `&usbphy`, `usb0_id_det-gpios` | ID `PH8` |
| Console | USB gadget `ttyGS0` | USB OTG; the UART2 pads on `PB0`/`PB1` are not used (damaged on the V1.0 development board) |

Closest models to start from: `sun8i-a33-olinuxino.dts` (A33, AXP223, codec, USB OTG) and
`sun8i-r16-nintendo-nes-classic.dts` (minimal consumer device on the same SoC).

## Getting at the device

The analysis above is static. These are the ways to get facts from a real unit, checked against the image.

### Readiness for a board DTS

Enough is known for a first draft: panel (table, timings, `PH7` reset, `dc1sw`, 2 lanes), PWM backlight, all
buttons and FN, AXP223 rails, SD, USB OTG, codec and PA, UART2 console. Gaps:

1. ~~**Sticks**~~ - solved in v1.1: protocol in "Analog sticks", our `ga36-gamepad` driver.
2. ~~DRAM parameters~~ - solved: mainline SPL works with `DRAM_CLK=552`, `DRAM_ZQ=15291`, `DRAM_ODT_EN=y`.
3. **No electrical confirmation:** polarities and rail roles come from `sys_config` only.
4. **Headphone detect:** the vendor reports it via switch `h2w`; the source (probably codec jack detect) is unknown.

### USB OTG

- **FEL mode (most useful).** The A33 boot ROM falls back to USB FEL when it finds no bootable media. This board
  has only the SD card, so booting with the card removed enters FEL (tested, see "On-device tests"). From a PC, `sunxi-fel` (sunxi-tools)
  can then:
  - read the SID;
  - run a mainline U-Boot SPL from RAM, which tests DRAM init and gives the RAM size;
  - load a kernel, DTB and initramfs into RAM and boot them, with nothing written to the card;
  - peek and poke registers.
- **Vendor system running: no access.** The kernel has the Android gadget built in (`CONFIG_USB_G_ANDROID=y`,
  `CONFIG_USB_GADGET=y`), but `SYSTEM` has no `adbd`, `sshd`, `dropbear` or `telnetd`.
- **Host mode (keyboard, mouse): configured, not tested.** Our device tree sets `&usb_otg` to `dr_mode = "otg"`, with
  ID detection on `PH8` and VBUS from the AXP's `drivevbus` (`x-powers,drive-vbus-en`); the kernel has
  `CONFIG_USB_MUSB_DUAL_ROLE` and `CONFIG_HID`, `CONFIG_HID_GENERIC`, `CONFIG_USB_HID` built in, and no
  `CONFIG_USB_STORAGE`. So an OTG adapter should switch the port to host mode and a USB keyboard or mouse should work
  without new drivers. Unknown: whether the board wires the 5 V VBUS output (if not, a powered hub is needed). Limits:
  one port, so a keyboard and a mouse need a hub or a combo receiver; while in host mode the USB console is gone.

### Running commands on the vendor system without a serial adapter

Cron is enabled by default:
- `cron.service` is in `multi-user.target.wants`, and runs `/sbin/crond -f -S`;
- the service's condition file `/storage/.cache/services/crond.conf` already exists on p8;
- `/storage/.cache/cron/crontabs/` exists on p8 and is empty.

A busybox crontab file `root` placed there from a PC (p8 is ext4, `/storage`) runs as root. A probe script can save
these to the card:
- `dmesg` and `/proc/meminfo` (RAM size);
- `stty -a -F /dev/ttyS1` (stick MCU baud rate);
- a raw capture of `/dev/ttyS1`;
- GPIO state.

The `custom_start.sh` hook in `emuelec_autostart.sh` is commented out, so it does not work.

### Serial console

FEL and cron do not replace UART2 (`PB0`/`PB1`, 115200, 3.3 V). A new kernel that fails before USB or the panel
comes up can only be debugged there. Plan: FEL for safe iteration, UART2 for early boot.

## On-device tests (2026-10-14)

Setup: no SD card, OTG cable to the PC, FT232 3.3 V adapter on UART2 (`PB0` TX, `PB1` RX, GND), 115200 8N1.
`sunxi-fel` built from sunxi-tools `bc96c0a`; it needs a udev rule for USB `1f3a:efe8` (group `plugdev`).

1. **FEL entry:** with no card the board enumerates as `1f3a:efe8`.
   `sunxi-fel ver`: `AWUSBFEX soc=00001667(A33) 00000001 ver=0001 44 08 scratchpad=00007e00`.
   `sunxi-fel sid` works; the SID is unit-specific, not recorded here.
2. **Mainline U-Boot SPL v2026.10:**
   - Built from `A33-OLinuXino_defconfig` with these changes:
     - `DRAM_CLK=552`, `DRAM_ZQ=15291` (0x3bbb), `DRAM_ODT_EN=y` (from `[dram_para]`);
     - `CONS_INDEX=3` (UART2 on `PB0`/`PB1`);
     - `AXP_DCDC1_VOLT=3000`, `AXP_DLDO3_VOLT=3000`.
   - All other AXP defaults already equal `[power_sply]`: DCDC2 1.1 V, DCDC3 1.2 V, DCDC5 1.5 V, ALDO2 2.5 V, ALDO3 3.0 V.
   - U-Boot's Kconfig help names DCDC2 VDD-SYS and DCDC3 VDD-CPU on A33.
   - Built in a Debian trixie container (`gcc-arm-linux-gnueabihf`).
   - Run with `sunxi-fel spl spl/sunxi-spl.bin`. UART2 shows:
     ```
     U-Boot SPL 2026.10 (Oct 14 2026 - 09:30:33 +0000)
     DRAM: 512 MiB
     Trying to boot from FEL
     ```
3. **DRAM check over FEL:**
   - markers written at offsets 0, 128 MiB, 256 MiB, 512 MiB and 1 GiB: 512 MiB and 1 GiB wrap to offset 0, while
     128 and 256 MiB keep their values, so the size is 512 MiB, matching the SPL;
   - 1 MiB of random data written to `0x42000000` and read back unchanged.
4. **UART2 debugging:** with the board-side setup verified over FEL, the adapter received nothing. The registers
   showed UART2 was working:
   - `PB_CFG0 = 0x77777722` (`PB0`/`PB1` in UART2 function);
   - CCU bus gate and reset bit 18 set;
   - `LCR = 0x03` (8N1);
   - `LSR = 0x60` after writing to THR, so the bytes were sent.

   Cause: adapter RX/TX swapped. Writing bytes to UART2 THR (`0x01c28800`) via `sunxi-fel writel` is a quick wiring test.
   Later on 2026-10-14 the UART2 pad was ripped off the development board; development continues over the USB OTG
   console only.
5. **FEL hang:** a second `spl` upload in the same FEL session (after the first SPL run and many register
   accesses) failed with `usb_bulk_send() ERROR -7` and FEL stopped answering. A power cycle fixed it. Do one SPL
   run per power-on.

## Mainline bring-up (V1.0)

Linux 6.18.56 and U-Boot v2026.10 from this repository, booted over FEL with the test initramfs. Date: 2026-10-14.

| Check | Result | Notes |
|---|---|---|
| Panel picture (bars, orientation, stability) | pass | `modetest -M sun4i-drm -s 51:640x480 -F smpte` (no `/dev/fb0`: `CONFIG_FB_DEVICE` unset); colours and orientation correct, stable; DSI-1 640x480 55.69 Hz, 71x53 mm; vendor timings as read, no alternative needed |
| Backlight polarity | pass | normal polarity; `max_brightness` 10, default 8; level 1 looks fully off, so userspace minimum should be higher |
| Buttons (17) | pass | every code matches the "Buttons" table above, FN = `KEY_FN` (464); `gpio-keys` is `event0` |
| Vol+/Vol- | pass, LRADC ch0, raw 4 (Vol+) / 11 (Vol-) (idle 0x3f) | mapped as `KEY_VOLUMEUP` (115) / `KEY_VOLUMEDOWN` (114) |
| Power key | pass | `KEY_POWER` (116) on `axp20x-pek` (`event1`) |
| Speaker / headphones | pass, with open items | mixer controls used: `AIF1 DA0` 160 (0 dB; defaults to 0 = muted), `DAC` 80 %, `AIF1 Slot 0 Digital DAC` on, `Headphone Source` DAC, `Headphone` 50 and 63 (vendor `headphone_vol = 63`), clean at both; headphones mute the speaker in hardware, no jack-detect event; headphone L/R swapped, correct with `AIF1 DA0 Stereo` = `Reverse Stereo`; pop when the PH9 amplifier switches |
| Battery, charger online | pass | `axp20x-battery` Charging 99 % 4.127 V, `constant_charge_current_max` 300000; unplugging USB and the charger: `axp20x-usb` and `axp22x-ac` go offline, Discharging, then back to Charging |
| s2idle: RTC wake / power key wake | pass / pass | `rtcwake -m freeze -s 10`: slept 12 s (no RTC sysfs: `CONFIG_RTC_INTF_SYSFS` unset); power key: slept 27 s; panel off while asleep. The USB gadget comes back only after a cable replug |
| SD card detect | pass | `mmc0: new high speed SDXC card`, then `card ... removed`; CD on `PB4`, active low |
| pstore crash log kept across the reset | no | ramoops at 0x49000000 is registered, but DRAM is not refreshed through the reset and the seconds in FEL: a pattern written there reads back corrupted; early crashes need the panel console |
| Power-on by plug-in | board stays off | plugging in the charger powers the board on and the SPL switches it off again; power on with a power key press longer than 1 s (3 s works) |
| Thermal at 1008 MHz, 10 min, 4 threads | pass | max temperature: 68.9 C (52.7 C after 30 s, flattening at 68-69 C); 1008 MHz held, load average 4.00; the 75 C trip was not reached, so throttling was not exercised |
| Thermal at 1200 MHz, 10 min, 4 threads | pass | max temperature: 77.0 C; 71.4 C after 30 s, the 75 C trip reached after 60 s, then step_wise throttling between 1008 and 1200 MHz held it at 73-77 C; load average 4.00; `vdd-cpu` 1.32 V at 1200 MHz, no oops |
| SD card boot (test image) | pass | U-Boot from the card, extlinux.conf on p1 (`ga36_boot=sdcard`); also with nothing attached (uptime 67 s when the cable arrived). First attempt looped: without `initrd_high` U-Boot moved the initrd onto ramoops, kernel panic and reset; now set in `CONFIG_PREBOOT` |
| Silent charging when off, card in | pass | charger plugged into the powered-off board: nothing boots (no USB device), panel dark, charge LED on |

## Userspace (V1.0)

Test card with the Debian trixie armhf rootfs, kernel 6.18.56 with patches 0001-0008. Date: 2026-10-15.

| Check | Result | Notes |
|---|---|---|
| Cold boot to ES | pass | about 20 s by stopwatch (power key to first ES screen); `systemd-analyze`: 1.870 s kernel + 11.512 s userspace = 13.382 s |
| fps per core | pass | measured with `audio_max_timing_skew` 0.10 (vsync-locked; the shipped default is now 0.05, see Game speed): all cores at the 55.69 Hz panel rate within about +/-1 fps measurement noise, vsync lost 0, rc 0: nes 56.7 (reruns 54.2, 55.2), gb 55.0, gbc 55.0, snes 55.7, gba 55.2, megadrive 55.7, pcengine 55.6, psx 54.5; mastersystem and gamegear not timed (no ROM; same picodrive core as megadrive) |
| MemAvailable with ES and pcsx_rearmed | pass | MemTotal 504924 kB, MemAvailable 378444 kB in game, `/dev/zram0` 256M with 0 B used, no OOM kill |
| Codec after stream stop | no reset seen | `Headphone` and the other analog and digital controls unchanged after idle (30/120/300 s), `aplay` and `speaker-test`; no kernel patch |
| Mixer after suspend | pass | s2idle without the sleep hook leaves `Headphone` at `Playback 0 [off]`; with the `ga36-alsa` hook it returns to `Playback 40 [on]`; the game resumed with music |
| ROMS partition create / restore | pass | blank p3 entry: created (p3 start 6848512, exFAT on `/roms`, 12 folders); entry deleted and rebooted: restored, marker file intact; present: no change. Never formats when any filesystem is at the offset. `fsck.exfat -p` runs before the mount: the boot after an unclean power-off logged "Volume was not properly unmounted", the next reported clean |
| Power key short / long | pass | short press suspends (s2idle) and wakes, in a game too; held over 2 s powers off |
| Hotkeys | pass | FN+Start returns to ES, FN+X opens the RetroArch menu; FN held plus Vol steps the backlight only, plain Vol steps the volume only (triggerhappy syntax is EVENT+MODIFIER) |
| Volume cap | pass | Vol+ and the ES maximum reach `Headphone` 63 with `AIF1 DA0` 160; the shipped default is `Headphone` 50 |
| Game speed | 0.05 chosen | Sonic 1 run back to back at skew 0.10 (vsync kept, about 7 % slow) and 0.05 (RetroArch logs "Cannot rely on VSync", normal speed): at 0.10 the music sounded too slow; at 0.05, over 20, 30 and 40 s runs with play, no tearing was noticed. Shipped default lowered to 0.05 |
| Game audio | pass | Sonic 1 (picodrive) title music heard at `Headphone` 45; 16-bit, 24-bit and float test tones heard. An earlier "static only" report was a low volume and the silent Super Mario Bros title screen |
| Low-battery drain | not run | overnight drain to the 3 % shutdown was not run |
| CI image (GitHub Actions) | pass | 2026-10-16, run 38822790547: 1 h 24 min in all (build 1 h 17 min, of which apps chroot 56 min and rootfs mmdebstrap 4.5 min; disk cleanup 5 min; tests 1 min, all 14 pass). `r36s-a33-ga36-debian-260544b.img.xz` 367600348 bytes, `.img` 3506438144 bytes; runner disk 35G free after cleanup, 28G after the build. Flashed with `xzcat \| dd` over a card holding a ROMS partition: ES came up, `ga36-roms-part` logged "ROMS partition entry restored" with the 21 ROM and save files intact, a game ran with sound. Writing the card while the PC had its partitions mounted left p1 unreadable and the board dark; unmount before `dd` and eject before removing the card. logind and journald log "Failed to apply ACLs: Operation not supported" (`CONFIG_EXT4_FS_POSIX_ACL` is off), harmless |
| AXP boot source (register 0x00 bit 0) | measured | 2026-10-16, U-Boot without `AXP_DISABLE_BOOT_ON_POWERON`, read from `/sys/kernel/debug/regmap/sunxi-rsb-3a3/registers`: power-key power-on `0x38` (bit 0 clear); USB plug-in power-on `0x39` (set); `reboot` after a plug-in power-on `0x38` (clear); cable unplugged and replugged while running `0x3c` (clear), then `reboot` `0x38` (clear). The bit marks only a cold plug-in start and does not survive a reboot, so a reboot never lands in charge mode. The USB cable to a PC counts as a plug-in (VBUS) |
| Charger unplug as an s2idle wake source | no | 2026-10-16: unplugging the USB cable during `echo freeze > /sys/power/state` does not wake the board; the AXP `VBUS_REMOVAL` interrupt does not fire while suspended (count 0 after resume) but does fire while running. Replugging wakes it (`VBUS_PLUGIN`). Charge mode needs a periodic RTC wake to notice an unplug |
| Charge mode (v1.1) | pass | 2026-10-17, image `v1.0.0-5-gd14d270` on V1.0, USB cable to a PC as the charger: plug-in with the board off shows the battery icon about 5 s after plug-in (stopwatch), dark 5 s later; a short press shows the icon on key-down, dark again after 5 s; unplugged while dark: off when checked 60 s later; unplugged while the icon shows: off within about 1 s; a press held over 2 s while the icon shows boots into ES (a hold from dark booted ES in the Task 2 smoke test); Restart System from ES with the charger in boots into ES, not charge mode; power-key power-on with and without the charger boots into ES; powered off from ES with the charger in, the board stays off. Image `v1.0.0-7-g4dfa964`, long press from dark after an s2idle: 48 s after boot the RTC alarm reads off (`rtcwake -m show`; the earlier image left it armed), PID 1 is `/sbin/init`, `/proc` and `/sys` are `nosuid,nodev,noexec` (the earlier image: `ga36-charge` and no flags) |
| Charge mode at the 3 % cutoff | not run | plug-in on a nearly flat battery (brown-out restart loop risk) was not run |
| Panel at 60 Hz (v1.1) | pass | 2026-10-18, V1.0. The v1.0 mode (30 MHz, 1040 x 518) ran at 55.13 Hz, not 55.69: `clk_summary` showed pll-video 297 MHz (locked by the DSI), pll-mipi and lcd-ch0 356.4 MHz, tcon-data-clock 89.1 MHz, so a 29.7 MHz pixel clock (dclk = 3 x pixel clock for 24 bpp on 2 lanes). Image `v1.0.0-11-g14972d0-dirty` with 29.7 MHz and htotal 955 (60.04 Hz): same clocks, DRM mode `60 29700 640 835 875 955 480 506 512 518`, no picture faults; RetroArch's estimated screen framerate about 59.5 (the estimate includes missed frames). Sonic 1 smoother; the remaining stutter was the CPU governor (next row). No ACL or `pam_env` warnings, `LANG=C.UTF-8` |
| CPU governor in games | performance | 2026-10-18, Sonic 1 under schedutil: the `sugov:0` thread (SCHED_DEADLINE) used 4 s of CPU in 10 s (RetroArch 6 s) with `rate_limit_us` 366, and the clock moved between 1008 and 1200 MHz; picture and sound stuttered from time to time. Performance (fixed 1200 MHz): RetroArch 2 s in 10 s, clearly smoother. Schedutil with `rate_limit_us` 20000: `sugov:0` still 2 s in 10 s and the clock mostly 408-816 MHz, so each change itself is costly. Games now run under performance (`ga36-retroarch`), ES and idle stay on schedutil. A short stutter where Sonic 1 breaks floors into many pieces remains; the game slows down there on a real Mega Drive too |
| Analog sticks (v1.1) | pass | 2026-10-19, V1.0, image `v1.0.0-22-gfe21f1a-dirty`. `GA36 Gamepad` (driver `ga36-gamepad`, serdev on UART1) owns the 17 buttons and the sticks; udev tags it a joystick, ES matches it from `es_input.cfg`. `evtest`: up and left negative on both sticks, ±32767 at every end, 0 at rest, all 17 buttons; pressing L3 moves the left Y axis to -936 for 20 ms (the stick moves under the press). Left stick moves through the ES and RetroArch menus; FN combos work; sticks work after sleep and wake with no resume code. PSX: RetroArch 1.20 ignores the pad type in a core override (Device Type stayed Standard) and takes it from the remap file; with DualShock, Sanvein reads the stick after L1+R1+Select (it does not switch to analog itself). Not tested: Ape Escape, Tony Hawk and a digital-only PSX game (not on the card) |
| DOS (v1.1) | pass | 2026-10-19, V1.0, image `v1.0.0-32-g03a2d18` (DOS on top of the sticks). DOSBox Pure starts `Doom shareware.zip` from ES (the space in the name passes through); governor `performance` at 1.2 GHz, 171 MiB RAM used, no swap. Controls: DOSBox Pure detects Doom and applies its pad map, left stick walks and right stick turns; a preset picked in the controller mapper is kept in the game's save and overrides it (a Generic Keyboard preset from a D-pad-only test did). Saves: `/roms/saves/DOSBox-pure/<game>.pure.zip` holds the in-game saves and the mapper choice; it survived the reflash from the earlier image, and a save loads after relaunch. The start menu shows on every launch until Left/Right on a program sets auto start, which then works. Speed: RetroArch's FPS display shows 70 (the VGA mode's rate, not Doom's); `doom -timedemo demo1` 5026 gametics in 9779 realtics (18.0 fps), `demo3` 2134 in 3844 (19.4 fps), about a 486DX2-66; it feels choppy. The emulation thread takes 100 % of one core with the ARMv7 dynrec, so the limit is the CPU. `doom19s.zip` (official installer): `INSTALL.BAT` runs (Keyboard + Mouse, Sound Blaster), the installed files land in `doom19s.pure.zip` (5.5 MB), and the next launch starts `DOOM.EXE` |
| N64 and PSP (v1.1) | pass, N64 slow | 2026-10-20, V1.0, image `v1.0.0-44-gaa1bdca`. lima: Mesa 25.0.7, OpenGL ES 2.0, 71 extensions (`GL_OES_depth_texture` and `GL_OES_packed_depth_stencil` yes, `GL_OES_texture_float` no). N64 on parallel-n64 (dynarec, gln64 at accuracy low, 320x240): Mario Kart 64 about 48 fps of 60 in a race, 211 MiB RSS, 254 MiB available, main thread 80 % of a core; Super Smash Bros. about 35 fps in a match, menus correct, 233 MiB RSS, 221 MiB available, one core at 100 % (CPU-bound). Audio crackles and the game stutters now and then, since both run below full speed. mupen64plus-next with GLideN64, the original choice, was GPU-bound (Mario Kart 30 fps, 45 with its threaded renderer; Smash black in its menus): [`../research/2026-10-20-n64-performance.md`](../research/2026-10-20-n64-performance.md). PSP on PPSSPP: Castlevania Dracula X Chronicles about 60 fps in the first stage, music clean, 157 MiB RSS, 288 MiB available; no option changes needed. Grand Theft Auto: Vice City Stories (3D city, driving): about 27 fps, choppy sound, 185 MiB RSS, 262 MiB available, CPU 77 % idle; with the GPU capped at 240 MHz it drops to about 15 fps, so it is GPU-bound. With `ppsspp_frameskip = "1"` as a game option the sound is better and the game plays much better (owner); RetroArch's counter then shows about 11 (drawn frames), both PPSSPP threads mostly sleep and the CPU is 94 % idle, so the emulation keeps pace. A text file renamed `broken.z64` returns to ES within seconds. Saves: `/roms/saves/ParaLLEl N64/<game>.srm` and `/roms/saves/PPSSPP/PSP/SAVEDATA/`; Smash VS records and the Castlevania save load after relaunch. No OOM. |
| Heroes 3 (v1.1) | pass | 2026-10-23, V1.0, image `v1.0.0-58-g56a9fc3`, VCMI 1.6.5, GOG data without `VIDEO.VID`. ES lists "Heroes of Might and Magic III"; launching it (`ga36-vcmi` as `ga36`, as ES does) stops ES (`inactive`) and sets governor `performance`; `schedutil` again after. Back to ES: in-game Quit (2 s, unit deactivated), FN+Start (2 s) and `kill -9 $(pidof vcmiclient)` (1 s); the unit is left `failed` after a kill and the next launch still works. Pad (owner): pointer on the left stick, map scroll on the right stick, X/Y left/right click, A/B accept/cancel, D-pad right/left zoom, Select end turn, a battle fought. Text: raised from 1.25 to 1.4 after a look on the device; 1.4 is fine (owner). A reflash keeps `/roms/heroes3/Saves` (md5 of a save unchanged) and gives `~/.config/vcmi/settings.json` with `scalable` and 1.4. A campaign starts without `VIDEO.VID`. AI turns, timed from VCMI's log: XL map (War of the Mighty) at day 1 with 7 AI players, one round 35 s; the same map at days 60 to 67 (saved from an all-AI run of VCMI 1.6.5 on a PC, 4 AI players left), rounds 31 to 50 s, one of 124 s whose 97 s AI turn held a 55 s AI-against-AI battle; single AI turns 6 to 24 s. Memory: 110 MiB RSS in the menu; XL day 1 peak 253 MiB RSS, 240 MiB available; XL day 60+ peak 328 MiB RSS, 165 MiB available, 2 MiB swap. VCMI's `--testsave` aborts (SIGABRT) in the lobby even with a save made on the device, so a save is loaded from the menu. |
| Fixes after v1.1 features | pass | 2026-10-23, V1.0, image `v1.0.0-59-ga452378-dirty` (the fixes below, before their commit). `/etc/hosts` maps `ga36` to 127.0.1.1 and `sudo` no longer prints "unable to resolve host ga36" (checked with and without the file). Sticks with the stale-frame timeout: all four axes reach -32767 and 32767 and read 0 at rest; no false centring while moving (one 0 between -16851 and 21532 within 66 ms is a pass across the dead zone). The MCU going silent cannot be forced, so the timeout itself is untested. `ga36-charge` with the wait-awake fallback: the charge screen shows the icon, goes dark, a short press shows it again and a hold boots (owner); the failure path was not forced. RetroArch game and Heroes 3 (FN+Start back) run; 28 save files on `ROMS` unchanged by the reflash. |
| Stock rail voltages | pass | 2026-10-23, V1.0. Read on the stock system (kernel 3.4.39) by a one-shot cron probe on `/storage` (`/sys/class/regulator/*`; no debugfs summary there), removed afterwards. On: DCDC1 3.0 V, DCDC2 1.1 V, DCDC3 1.32 V at that moment (CPU, scaled), DCDC5 1.5 V, ALDO1 3.0 V, ALDO2 2.5 V, ALDO3 3.0 V, DLDO3 3.0 V, DC5LDO 1.1 V, DC1SW. Off: DCDC4, DLDO1/2/4, ELDO1-3, LDOIO0/1. This confirms the two rails `[power_sply]` does not list: ALDO1 `vcc-io` 3.0 V as in our device tree, and DC5LDO `vdd-cpus` 1.1 V, inside our 0.9-1.4 V range; our image reads `vdd-cpus` 1.1 V and `vcc-io` 3.0 V too. |

Known limitations: ES holds the audio device while in the menu, which gives a faint hiss at idle; `es_input.cfg` is
root-owned, so remapping inside ES does not save on a release card; the RTC has no wakealarm; 50 Hz (PAL) games run
without vsync lock on the 60 Hz panel, so tearing is possible there; ROMS is mounted by label, so a relabelled partition stays
unmounted.

Open items found during bring-up:

- Reported after every stream stop: the analog codec registers return to their reset values (`Headphone` 0 and
  muted), when the DAPM `mod` supply gates `ac-dig`. Did not reproduce in the userspace bring-up (idle 30/120/300 s,
  `aplay`, `speaker-test`: all analog and digital controls unchanged), so no kernel patch was made; the registers
  do reset over s2idle, handled by a sleep hook.
- USB gadget console: no re-enumeration after s2idle resume until the cable is replugged; the OTG connector or cable
  drops the link when moved (reproduced by wiggling it).
- Thermal sensor: `allwinner,sun8i-a33-ths` needs `CONFIG_SUN4I_GPADC` (the GPADC driver), not `sun8i_thermal`.
- Game speed against the 55.69 Hz panel: settled in v1.1 by the 60.04 Hz panel mode (60 Hz games vsync-locked at
  normal speed and pitch with the default skew of 0.05).
- CPU frequency changes are slow: under schedutil each change costs milliseconds of CPU in `sugov:0`, likely the
  DCDC3 voltage step over RSB. Games avoid it with the performance governor; a fix in the OPP table or regulator
  ramp would also help ES and battery life. Not investigated.
- Boot log warnings (2026-10-17, `journalctl -b -p warning`, image `v1.0.0-7-g4dfa964`). Real: "Failed to apply
  ACLs" (POSIX ACL kernel options off) and `pam_env` "Unable to open env file: /etc/default/locale", because
  `/etc/default/locale` links to `../locale.conf`, which does not exist, so `LANG` is empty and programs run in the
  `POSIX` locale. Both fixed in v1.1 (kernel options and `/etc/locale.conf`). Harmless: triggerhappy's `th-cmd` fails at
  udev time (before `thd` runs; the hotkeys work); Debian's `90-alsa-restore.rules` has an unmatched `GOTO` label;
  systemd finds no `autofs4` module and no BPF firewall support; `zram` is reported as not found as a module
  because it is built in (`CONFIG_ZRAM=y`, the 256 MiB swap is active); deferred probes (`-517`) and dummy
  regulators for the pin banks are normal for this board.

## Open items

- Electrical confirmation of anything marked config-only - device access now works (FEL + UART2).
