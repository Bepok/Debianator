#!/bin/sh
# The ES tree carries the GA36 patches: no libgo2, the AXP battery, the Headphone mixer, a backlight floor and no
# ArkOS shell calls in the main menu.
# Run: ./build.sh run tests/es-patches.sh
set -eu
s=out/src/emulationstation
[ -d "$s" ] || { echo "FAIL: $s missing (./build.sh run scripts/fetch-apps.sh)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
grep -rqs '^#include <go2/' "$s/es-core/src" "$s/es-app/src" && bad "go2 include left"
grep -q 'find("battery")' "$s/es-core/src/platform.cpp" || bad "battery lookup does not match axp20x-battery"
grep -q 'mStringMap\["AudioDevice"\] = "Headphone";' "$s/es-core/src/Settings.cpp" || bad "AudioDevice default not Headphone"
grep -q 'current_volume\|/sys/class/power_supply/battery/capacity' "$s/es-app/src/guis/GuiMenu.cpp" && bad "menu status line shells out"
grep -q 'if (value < 20)' "$s/es-app/src/ApiSystem.cpp" || bad "no backlight floor"
[ $fail = 0 ] && echo PASS
exit $fail
