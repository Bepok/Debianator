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
