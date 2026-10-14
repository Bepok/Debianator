#!/bin/sh
# Print the vendor DSI init table (docs/hardware/panel-init.txt) as mipi_dsi_dcs_write_seq_multi() lines.
# Stops at "11" (exit sleep): the driver sends exit sleep and display on itself.
# Usage: scripts/panel-init-to-c.sh docs/hardware/panel-init.txt
set -eu
awk '/^#/ {next} $1 == "11" {exit} {printf "\tmipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x%s, 0x%s);\n", toupper($1), toupper($2)}' "$1"
