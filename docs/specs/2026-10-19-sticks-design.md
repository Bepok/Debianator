# Analog sticks design

Date: 2026-10-19. Status: design. Release: v1.1 ("Analog sticks" in [`../porting-plan.md`](../porting-plan.md)).
Parent design: [`2026-10-14-firmware-design.md`](2026-10-14-firmware-design.md).

## Why

The GA36 has two analog sticks, but v1.0 does not read them: the owner can only play with the D-pad. Games that
want a stick (Tony Hawk's Pro Skater on PSX, Doom with DOSBox Pure's Doom map, later N64) are hard or unplayable.
v1.1 makes both sticks work.

## Behaviour (decided with the owner)

- Both sticks work in games. The everyday case is Tony Hawk on PSX: the left stick steers the skater. The right
  stick works wherever a game uses it (Tony Hawk itself probably ignores it).
- The left stick also moves through the menus of EmulationStation and RetroArch.
- In games the sticks work only where the game reads a stick. The left stick does not stand in for the D-pad in
  games without stick support (NES, SNES, Mega Drive, GBA, digital-only PSX games): there it does nothing.
- With sticks working, DOSBox Pure's automatic game pad maps stay on (its Doom map puts walk and turn on the sticks).
  The DOS branch's "auto maps off until the sticks work" change is then not needed (see
  [`../plans/2026-10-18-dos.md`](../plans/2026-10-18-dos.md), "Where it stands").
- The vendor system's sticks felt fine to the owner, with no drift; that is the bar.

Our calls, played back to the owner and not objected to:

- One gamepad: buttons and sticks are a single input device, so RetroArch and ES see one controller with sticks.
- The axes use the MCU's full 8-bit resolution (the vendor driver reduced them to 19 steps).
- A small dead zone around the centre, so a resting stick does not drift.
- The target is every board the public image boots on, not only the owner's unit: the driver must not depend on one
  unit's centre and range (for example: centre taken from the first frames after the handshake when it is near the
  middle, otherwise the nominal centre, and margins so every unit reaches full deflection).
- The challenge reply is not a gate: frames are used whether or not the check passes (the check is the vendor's
  anti-clone measure, not ours). Only "no frames at all" falls back to buttons only.
- The PSX core reports a DualShock, so analog games see the sticks.
- Test games: Ape Escape (needs both sticks), Doom (DOS), Tony Hawk.

## Goals

- Left and right stick, both axes each, reach games through RetroArch as the RetroPad analog sticks.
- Left stick navigates ES and the RetroArch menu.
- A resting stick reports centre; full deflection reaches (close to) the end of the range in all four directions.
- Every button keeps working as in v1.0, including the FN hotkeys and the ES and RetroArch mappings.

## Non-goals

- Per-user calibration UI. A fixed calibration in the driver is enough while the vendor bar (no drift) holds.
- Mouse emulation from a stick for DOS or Windows games (DOSBox Pure already offers stick-as-mouse presets).
- Rumble, or any other feature of the MCU beyond the four axes.
- The vendor anti-clone kill switch: we do not reproduce it.

## Anti-goals

Even if the sticks work, it is a failure if:

- any button stops working, is slower, or the FN hotkeys break;
- a PSX game that works today with the D-pad stops accepting input (some digital-only PS1 games reject a DualShock
  in analog mode);
- a stick at rest moves the cursor in ES or the character in a game;
- boot hangs or slows when the MCU does not answer (a board with a dead or different MCU must still boot and play
  with buttons).

## What we know about the MCU (confirmed on the device, 2026-10-19)

Static analysis of the vendor kernel (`sw_uart_irq` hook on UART1) and a capture on our own system:

- UART1 (`PG06` TX, `PG07` RX), `/dev/ttyS0` on our kernel (`1c28400.serial`), 9600 8N1, no flow control.
- The MCU is silent until the host sends the challenge `A6 01 00 r1 r2 r3`. It answers once with
  `A7 10 00 b3 b4 b5 b6 00` where `b[2+k] = (r_k + k) ^ 0x5A ^ b6`, k = 1..3 (checked on the device with r =
  11 22 33: reply `A7 10 00 9B AD BF D3 00`).
- After the ack `A6 01 01 01 01 01` it streams 8-byte frames `A7 10 00 X Y RX RY 00`, about 29 per second
  (920 bytes in 4 s), with no checksum.
- Axes are 8-bit; in the capture they spanned about `1E`-`EA` with rest near `7E`-`80`. The vendor driver inverts X
  and Y (left stick). One axis (byte 5) did not move in the capture; whether the owner moved that direction is
  unknown, so all four axes are to be checked.

Details of the vendor driver (buttons, `adc_val_to_axis`, the kill switch) are in
[`../hardware/hardwareAnalysis.md`](../hardware/hardwareAnalysis.md), "Analog sticks"; that section gets these
findings too.

## How it works

### Kernel

A new driver, added to the kernel patch series, owns the whole gamepad:

- It reads the button GPIOs the `gpio-keys` node lists today (same pins, same `linux,code` values, same 10 ms poll),
  and replaces that node.
- It is a serdev child of `&uart1`: at probe it sets 9600 raw, sends the challenge, checks the reply, sends the ack,
  then parses the frame stream (resynchronising on `A7 10 00`).
- It reports `ABS_X`/`ABS_Y` (left) and `ABS_RX`/`ABS_RY` (right) with a centre dead zone (`flat`) and fuzz on the
  same input device as the buttons.
- If the MCU does not answer, it retries a few times and then runs with buttons only (axes stay at centre). It never
  blocks probe for long.
- After system sleep it redoes the handshake (whether the MCU loses power in sleep is unknown).

Why one driver and not two: RetroArch's udev joypad driver and ES bind one device per player, so sticks on a second
device would be "player 2". A user-space merger (uinput daemon) would add a process and latency.

### Userspace

- The device name and GUID change, so `es_input.cfg` gets the new `deviceName`/`deviceGUID` and axis entries for the
  left stick (ES fcamod navigates with them), and the RetroArch config gets `input_player1_l_x_plus_axis` and
  friends for both sticks.
- RetroArch's menu follows the left stick once it is bound (builder to confirm the setting for RGUI).
- PCSX-ReARMed: port 1 device DualShock, set as a core option default in the image. The builder chooses how a
  digital-only game still gets input (for example starting in digital mode with the core's analog toggle combo, or
  a per-game override), and documents it in the README.

### Tests

- `tests/dtb.sh`: the gamepad node replaces `gpio-keys`, lists the same 17 buttons with the same codes, and is a
  child of `uart1`.
- `tests/kernel-config.sh`: the driver and `CONFIG_SERIAL_DEV_BUS` are built in.
- `tests/rootfs.sh`: `es_input.cfg` names the new device and binds the left-stick axes; the RetroArch config binds
  all four stick axes.

### Checks on the device

- `evtest`: every button, and each stick in all four directions; resting values and range.
- ES: left stick moves through the menus; nothing moves at rest.
- RetroArch: Ape Escape (both sticks), Doom with DOSBox Pure's Doom map, Tony Hawk if the owner has it; one
  digital-only PSX game that worked in v1.0 (for example Crash Bandicoot 1) still plays.
- Sleep and wake: sticks still work afterwards.
- A silent MCU cannot be produced on a real board (the UART pins are not reachable), so the no-reply path is checked
  with a throwaway kernel build that never sends the ack: buttons work, boot is not slower.

## Risks

- The MCU might need the ack within a time window, or re-challenges later: the capture shows streaming for 4 s only.
- Digital-only PS1 games and DualShock analog mode.

## Left to the builder

- Driver name, compatible string, file layout, whether it goes upstream-shaped.
- Dead zone and fuzz values (from `evtest` on the device).
- Axis inversion and the mapping of bytes to axes after checking all four directions.
- The PSX digital-game approach.
