# docs/hardware/

Research on the GA36-MB V1.0-20250730 board, done on the stock recovery image and on a real unit.

| File | What |
|---|---|
| [`hardwareAnalysis.md`](hardwareAnalysis.md) | hardware description: pin mapping, power, display, input, audio, on-device tests |
| [`analysis.md`](analysis.md) | stock image layout and boot chain |
| `sys_config.fex` | vendor board config, decoded with `bin2fex` |
| `kernel-3.4.39.config` | config of the vendor 3.4 kernel |
| `panel-init.txt` | DSI panel init command table, decoded from the vendor `lcd.ko` |

The text artifacts were extracted from the vendor image for interoperability. Vendor binaries are not kept here.
