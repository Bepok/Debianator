#!/bin/sh
# ga36-roms-part creates p3 on free space, restores the entry over existing exFAT data without formatting, leaves an
# existing p3 alone and skips a card too small. ga36-roms-dirs makes one folder per es_systems.cfg path.
# Run: ./build.sh run tests/roms-part.sh
set -eu
s=rootfs/overlay/usr/local/sbin
start=6848512
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
# A card as the test image leaves it, plus $1 MiB of free space after p2.
card() {
	rm -f "$t/d"
	truncate -s $(( (3344 + $1) * 1024 * 1024 )) "$t/d"
	printf 'label: dos\nstart=32768, size=524288, type=c\nstart=557056, size=6291456, type=83\n' | sfdisk -q "$t/d"
}
p3() { sfdisk -d "$t/d" | grep -q "start= *$start, .*type=7"; }
sig() { dd if="$1" bs=1 skip=$(( ${2:-0} + 3 )) count=8 status=none; }

# fresh: p3 appended and formatted.
card 1100
rm -f "$t/p"; truncate -s 64M "$t/p"
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "fresh: exit status"
p3 || bad "fresh: no p3 entry"
[ "$(sig "$t/p")" = "EXFAT   " ] || bad "fresh: p3 not formatted"
echo "$out" | grep -q created || bad "fresh: says '$out'"

# restore: exFAT already at the p3 offset, entry missing (a reflash). Entry back, data untouched.
card 1100
rm -f "$t/x"; truncate -s 64M "$t/x"
mkfs.exfat -L ROMS "$t/x" >/dev/null
dd if="$t/x" of="$t/d" bs=512 seek=$start conv=notrunc status=none
[ "$(sig "$t/d" $((start * 512)))" = "EXFAT   " ] || bad "restore: setup did not place exFAT at the offset"
rm -f "$t/p"; printf keep > "$t/p"; truncate -s 64M "$t/p"
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "restore: exit status"
p3 || bad "restore: no p3 entry"
[ "$(head -c 4 "$t/p")" = keep ] || bad "restore: formatted over existing data"
echo "$out" | grep -q restored || bad "restore: says '$out'"

# present: second run changes nothing.
before=$(sfdisk -d "$t/d")
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "present: exit status"
[ "$(sfdisk -d "$t/d")" = "$before" ] || bad "present: table changed"
[ "$(head -c 4 "$t/p")" = keep ] || bad "present: data touched"

# interrupted: entry exists, no exFAT at the offset (first boot died before mkfs). Formatted on the next run.
card 1100
echo "start=$start, type=7" | sfdisk -q --append "$t/d"
rm -f "$t/p"; truncate -s 64M "$t/p"
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "interrupted: exit status"
[ "$(sig "$t/p")" = "EXFAT   " ] || bad "interrupted: p3 not formatted"
echo "$out" | grep -q created || bad "interrupted: says '$out'"

# too small: under 1 GiB free, no p3, still exit 0.
card 100
out=$("$s/ga36-roms-part" "$t/d" "$t/p") || bad "small: exit status"
p3 && bad "small: p3 created"
echo "$out" | grep -q 'too small' || bad "small: says '$out'"

# dirs: one folder per es_systems.cfg path plus bios and saves.
mkdir "$t/roms"
"$s/ga36-roms-dirs" rootfs/overlay/etc/emulationstation/es_systems.cfg "$t/roms"
for d in nes gb gbc snes gba megadrive mastersystem gamegear pcengine psx bios saves; do
	[ -d "$t/roms/$d" ] || bad "dirs: $d missing"
done
[ $fail = 0 ] && echo PASS
exit $fail
