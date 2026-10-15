#!/bin/sh
# ga36-lowbat fires only while discharging at 3 % or less; ga36-brightness stays within 2..max.
# Run: ./build.sh run tests/power.sh
set -eu
s=rootfs/overlay/usr/local/sbin
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
bat() { printf '%s\n' "$1" > "$t/status"; printf '%s\n' "$2" > "$t/capacity"; }

bat Discharging 3
out=$("$s/ga36-lowbat" "$t") || bad "3 % discharging: no power off"
echo "$out" | grep -q '3 %' || bad "3 % discharging: did not read the fake battery ('$out')"
bat Discharging 0;  "$s/ga36-lowbat" "$t" >/dev/null || bad "0 % discharging: no power off"
bat Discharging 4;  "$s/ga36-lowbat" "$t" >/dev/null && bad "4 % discharging: power off"
bat Charging 2;     "$s/ga36-lowbat" "$t" >/dev/null && bad "2 % charging: power off"
bat 'Not charging' 1; "$s/ga36-lowbat" "$t" >/dev/null && bad "1 % not charging: power off"
"$s/ga36-lowbat" "$t/missing" >/dev/null 2>&1 && bad "missing battery: power off"

echo 10 > "$t/max_brightness"
echo 3 > "$t/brightness"; "$s/ga36-brightness" "$t" down; [ "$(cat "$t/brightness")" = 2 ] || bad "3 down"
"$s/ga36-brightness" "$t" down; [ "$(cat "$t/brightness")" = 2 ] || bad "went below 2"
echo 10 > "$t/brightness"; "$s/ga36-brightness" "$t" up; [ "$(cat "$t/brightness")" = 10 ] || bad "went above max"
echo 1 > "$t/brightness"; "$s/ga36-brightness" "$t" up; [ "$(cat "$t/brightness")" = 2 ] || bad "1 up"
[ $fail = 0 ] && echo PASS
exit $fail
