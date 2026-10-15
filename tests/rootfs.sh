#!/bin/sh
# The release rootfs tarball: packages, apps, overlay, user, services, mixer defaults, no build tools.
# Run: ./build.sh run tests/rootfs.sh
set -eu
r=out/rootfs/rootfs.tar
[ -f "$r" ] || { echo "FAIL: $r missing (./build.sh rootfs)"; exit 1; }
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
tar --numeric-owner -tvf "$r" > "$t/list"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
has() { awk -v p="./$1" '$6 == p {f=1} END {exit !f}' "$t/list"; }
owner() { awk -v p="./$1" '$6 == p {print $1, $2}' "$t/list"; }
file() { tar -xOf "$r" "./$1"; }

for p in usr/local/lib/emulationstation/emulationstation usr/local/lib/libretro/pcsx_rearmed_libretro.so \
	usr/bin/retroarch usr/lib/arm-linux-gnueabihf/libGL.so.1 usr/lib/arm-linux-gnueabihf/libretro/nestopia_libretro.so \
	usr/lib/arm-linux-gnueabihf/libretro/gambatte_libretro.so etc/emulationstation/themes/carbon/readme.txt etc/emulationstation/es_input.cfg \
	etc/systemd/system/multi-user.target.wants/emulationstation.service \
	etc/systemd/system/multi-user.target.wants/ga36-roms.service usr/local/sbin/ga36-roms-part \
	etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service var/log/journal/ home/ga36/ roms/ \
	etc/systemd/system/timers.target.wants/ga36-lowbat.timer usr/lib/systemd/system-sleep/ga36-alsa etc/systemd/logind.conf.d/ga36.conf \
	etc/triggerhappy/triggers.d/ga36.conf usr/sbin/thd; do
	has "$p" || bad "$p missing"
done
file etc/emulationstation/es_input.cfg > "$t/input.cfg" 2>/dev/null || true
[ "$(grep -c '<input ' "$t/input.cfg")" -ge 17 ] || bad "es_input.cfg has fewer than 17 inputs"
grep -q 'deviceName="gpio-keys"' "$t/input.cfg" || bad "es_input.cfg not for gpio-keys"
# thd combos are EVENT+MODIFIER: the modifier (FN) comes last.
file etc/triggerhappy/triggers.d/ga36.conf > "$t/thd.conf"
grep -q "^KEY_VOLUMEUP+KEY_FN" "$t/thd.conf" || bad "thd: no KEY_VOLUMEUP+KEY_FN trigger"
grep -q "^KEY_VOLUMEDOWN+KEY_FN" "$t/thd.conf" || bad "thd: no KEY_VOLUMEDOWN+KEY_FN trigger"
grep -q "^KEY_FN+" "$t/thd.conf" && bad "thd: KEY_FN+ order is not valid"
file etc/fstab | grep -q '^LABEL=ROMS /roms exfat ' || bad "fstab ROMS"
for p in usr/bin/gcc usr/bin/cmake etc/emulationstation/themes/carbon/.git/; do
	has "$p" && bad "$p present"
done
# The Debian RetroArch build must carry the KMS/GBM context (video_driver gl without X11).
file usr/bin/retroarch > "$t/retroarch" 2>/dev/null || true
readelf -d "$t/retroarch" | grep -q 'libgbm\.so\.1' || bad "retroarch does not link libgbm"
[ "$(owner usr/local/lib/emulationstation/emulationstation)" = "-rwxr-xr-x 0/0" ] || bad "ES not root-owned 755"
[ "$(owner etc/sudoers.d/ga36)" = "-r--r----- 0/0" ] || bad "sudoers drop-in not root 0440"
[ "$(owner home/ga36/ | cut -d' ' -f2)" = 1000/1000 ] || bad "home not owned by ga36"
for d in ./ etc/ usr/ usr/local/ var/; do
	[ "$(owner "${d#./}")" = "drwxr-xr-x 0/0" ] || bad "$d not root 755"
done
for g in video render input audio; do
	file etc/group | grep -q "^$g:.*[:,]ga36\(,\|$\)" || bad "ga36 not in $g"
done
file etc/fstab | grep -q '^PARTUUID=47413336-02 / ext4 ' || bad "fstab root"
file etc/systemd/zram-generator.conf | grep -qx 'zram-size = 256' || bad "zram size"
a=$(file var/lib/alsa/asound.state)
echo "$a" | grep -A4 "name 'AIF1 DA0 Playback Volume'" | grep -q 'value.0 160' || bad "AIF1 DA0 not 0 dB"
echo "$a" | grep -A4 "name 'AIF1 DA0 Stereo Playback Route'" | grep -q "value.0 'Reverse Stereo'" || bad "stereo not reversed"
echo "$a" | grep -A4 "name 'DAC Playback Volume'" | grep -q 'value.0 160' || bad "DAC not 0 dB"
echo "$a" | grep -A4 "name 'Headphone Playback Volume'" | grep -q 'value 50' || bad "Headphone default not 50"
es=$(file etc/emulationstation/es_systems.cfg)
for c in $(echo "$es" | sed -n 's:.*-L \([^ ]*\) .*:\1:p'); do
	has "${c#/}" || bad "es_systems core $c missing"
done
[ "$(echo "$es" | grep -c '<system>')" = 10 ] || bad "es_systems does not list 10 systems"
ra=$(file home/ga36/.config/retroarch/retroarch.cfg 2>/dev/null || true)
for kv in 'video_context_driver = "kms"' 'video_refresh_rate = "55.690000"' 'video_vsync = "true"' \
	'audio_volume = "0.000000"' 'input_joypad_driver = "udev"' 'input_enable_hotkey_btn = "12"' \
	'input_exit_emulator_btn = "9"' 'input_player1_a_btn = "0"' 'input_player1_b_btn = "1"' \
	'input_player1_up_btn = "13"' 'config_save_on_exit = "false"' 'audio_max_timing_skew = "0.100000"'; do
	echo "$ra" | grep -qxF "$kv" || bad "retroarch.cfg lacks $kv"
done
[ "$(owner home/ga36/.config/retroarch/retroarch.cfg | cut -d' ' -f2)" = 1000/1000 ] || bad "retroarch.cfg not owned by ga36"
[ $fail = 0 ] && echo PASS
exit $fail
