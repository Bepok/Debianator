# Analog sticks design

Date: 2026-10-19. Status: implemented, checked on V1.0 (hardware notes, "Analog sticks (v1.1)"). Release: v1.1 ("Analog sticks" in [`../porting-plan.md`](../porting-plan.md)).
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
- A small dead zone around the centre, applied in the driver (RetroArch and SDL ignore the input `flat` value), so a
  resting stick does not drift.
- The target is every board the public image boots on, not only the owner's unit: calibration is fixed with margins
  (rest `0x80`, 80 counts per half, 10-count dead zone) rather than tuned to one unit. The measured unit rests within
  2 counts of `0x80` and its shortest half is 90 counts. Sampling or learning the range was considered and dropped:
  it adds failure modes (a stick held at boot) for no measured need; stored per-unit calibration only if drift reports
  come in.
- The challenge reply is not a gate: frames are used whether or not the check passes (the check is the vendor's
  anti-clone measure, not ours). No frames at all leaves buttons only.
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
- All four axes move (two 20 s captures, each stick turned in full circles, 622 frames each, trailer byte always 0;
  rest identical in both, extremes differ by up to 7 counts; the table gives the widest seen):

  | Byte | Axis | Rest | Min | Max |
  |---|---|---|---|---|
  | 3 | left X | `80` | `08` | `DE` |
  | 4 | left Y | `81` | `27` | `EA` |
  | 5 | right X | `7E` | `14` | `E6` |
  | 6 | right Y | `7F` | `1D` | `DE` |

  No axis reaches `00` or `FF`, and the two halves of an axis are not equal (left X: 120 counts below rest, 94
  above), so the driver scales each half separately and clamps. The vendor driver inverts bytes 3 and 4; which way is
  "up" and "left" is checked with `evtest`.
- The stream can start with a few stray bytes before the first `A7 10 00` (`FD 01 FE` in both captures that sent the ack 0.1 s after the challenge; possibly the MCU's answer to the
  ack): the parser
  resynchronises on the header.

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
- It reports `ABS_X`/`ABS_Y` (left) and `ABS_RX`/`ABS_RY` (right) on the same input device as the buttons, with the
  dead zone applied before reporting.
- The handshake runs once, in the background (challenge, ack 100 ms later, as the device capture and goodluckOS's
  driver for this board do). Probe never waits on the MCU; if it never streams, the axes stay at centre.
- After system sleep: whether the MCU needs a new handshake is unknown; the device check decides, and only then does
  the driver resend it on resume.

Why one driver and not two: RetroArch's udev joypad driver and ES bind one device per player, so sticks on a second
device would be "player 2". A user-space merger (uinput daemon) would add a process and latency.

### Userspace

- The device name and GUID change, so `es_input.cfg` gets the new `deviceName`/`deviceGUID` and axis entries for the
  left stick (ES fcamod navigates with them), and the RetroArch config gets `input_player1_l_x_plus_axis` and
  friends for both sticks.
- RetroArch's menu follows the left stick once it is bound (builder to confirm the setting for RGUI).
- PCSX-ReARMed: port 1 device DualShock, set in the core's remap file in the image (RetroArch 1.20 ignores the pad
  type in a core override). It starts in digital mode like the real pad, so digital-only games keep working; games
  that use the sticks switch to analog themselves, others take L1+R1+Select (README).

### Tests

- `tests/dtb.sh`: the gamepad node replaces `gpio-keys`, lists the same 17 buttons with the same codes, and is a
  child of `uart1`.
- `tests/kernel-config.sh`: the driver and `CONFIG_SERIAL_DEV_BUS` are built in.
- `tests/rootfs.sh`: `es_input.cfg` names the new device and binds the left-stick axes; the RetroArch config binds
  all four stick axes.

### Checks on the device

- `evtest`: every button, and each stick in all four directions; resting values and range.
- ES: left stick moves through the menus; nothing moves at rest.
- RetroArch: Ape Escape (both sticks), Tony Hawk if the owner has it; one digital-only PSX game that worked in v1.0
  (for example Crash Bandicoot 1) still plays. Doom with DOSBox Pure's Doom map is checked on the DOS branch once this
  one is merged (this branch has no DOS core).
- Sleep and wake: sticks still work afterwards.

## Risks

- The MCU might stop streaming later: the captures show 21 s without a gap; the device check plays for minutes.
- Digital-only PS1 games and DualShock analog mode.

## Left to the builder

- Driver name, compatible string, file layout, whether it goes upstream-shaped.
- Dead zone and fuzz values (from `evtest` on the device).
- Axis inversion and the mapping of bytes to axes after checking all four directions.
- The PSX digital-game approach.
