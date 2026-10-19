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
	etc/triggerhappy/triggers.d/ga36.conf usr/sbin/thd usr/local/sbin/ga36-charge; do
	has "$p" || bad "$p missing"
done
file etc/emulationstation/es_input.cfg > "$t/input.cfg" 2>/dev/null || true
[ "$(grep -c '<input ' "$t/input.cfg")" -ge 17 ] || bad "es_input.cfg has fewer than 17 inputs"
# thd combos are EVENT+MODIFIER: the modifier (FN) comes last.
file etc/triggerhappy/triggers.d/ga36.conf > "$t/thd.conf"
grep -q "^KEY_VOLUMEUP+KEY_FN" "$t/thd.conf" || bad "thd: no KEY_VOLUMEUP+KEY_FN trigger"
grep -q "^KEY_VOLUMEDOWN+KEY_FN" "$t/thd.conf" || bad "thd: no KEY_VOLUMEDOWN+KEY_FN trigger"
grep -q "^KEY_FN+" "$t/thd.conf" && bad "thd: KEY_FN+ order is not valid"
file etc/fstab | grep -q '^LABEL=ROMS /roms exfat ' || bad "fstab ROMS"
file etc/systemd/system/ga36-roms.service | grep ^ExecStart= | sed -n 2,3p | tr "\n" " " | grep -q "^ExecStart=-/usr/sbin/fsck.exfat -p /dev/mmcblk0p3 ExecStart=-/bin/mount /roms " || bad "ga36-roms fsck then tolerant mount"
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
file etc/locale.conf | grep -qx LANG=C.UTF-8 || bad "locale.conf"
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
[ "$(echo "$es" | grep -c '<system>')" = 13 ] || bad "es_systems does not list 13 systems"
echo "$es" | grep -A3 '<name>pc</name>' | grep '<extension>' | tr ' <>' '\n\n\n' > "$t/pcext"
for e in .zip .ZIP .dosz .DOSZ; do grep -qx -- "$e" "$t/pcext" || bad "DOS extension $e missing"; done
echo "$es" | grep '<command>' | grep -qv '<command>ga36-retroarch ' && bad "es_systems command not through ga36-retroarch"
has usr/local/bin/ga36-retroarch || bad "ga36-retroarch missing"
file etc/tmpfiles.d/ga36-cpufreq.conf | grep -q '^z .*/scaling_governor 0664 root ga36 ' || bad "governor not writable by ga36"
ra=$(file home/ga36/.config/retroarch/retroarch.cfg 2>/dev/null || true)
for kv in 'video_context_driver = "kms"' 'video_refresh_rate = "60.037600"' 'video_vsync = "true"' \
	'audio_volume = "0.000000"' 'input_joypad_driver = "udev"' 'input_enable_hotkey_btn = "12"' \
	'input_exit_emulator_btn = "9"' 'input_player1_a_btn = "0"' 'input_player1_b_btn = "1"' \
	'input_player1_up_btn = "13"' 'config_save_on_exit = "false"' 'audio_max_timing_skew = "0.050000"'; do
	echo "$ra" | grep -qxF "$kv" || bad "retroarch.cfg lacks $kv"
done
[ "$(owner home/ga36/.config/retroarch/retroarch.cfg | cut -d' ' -f2)" = 1000/1000 ] || bad "retroarch.cfg not owned by ga36"
# One gamepad for buttons and sticks (GA36 Gamepad driver); the left stick navigates ES; in games no stick-as-D-pad.
grep -q 'deviceName="GA36 Gamepad" deviceGUID="19008d50010000000100000000010000"' "$t/input.cfg" || bad "es_input.cfg not for GA36 Gamepad"
for m in 'leftanalogup".*id="1" value="-1"' 'leftanalogdown".*id="1" value="1"' 'leftanalogleft".*id="0" value="-1"' 'leftanalogright".*id="0" value="1"'; do
	grep -q "name=\"$m" "$t/input.cfg" || bad "es_input.cfg lacks $m"
done
for kv in 'input_player1_l_x_plus_axis = "+0"' 'input_player1_l_x_minus_axis = "-0"' 'input_player1_l_y_plus_axis = "+1"' \
	'input_player1_l_y_minus_axis = "-1"' 'input_player1_r_x_plus_axis = "+2"' 'input_player1_r_x_minus_axis = "-2"' \
	'input_player1_r_y_plus_axis = "+3"' 'input_player1_r_y_minus_axis = "-3"'; do
	echo "$ra" | grep -qxF "$kv" || bad "retroarch.cfg lacks $kv"
done
echo "$ra" | grep -q '^input_player1_analog_dpad_mode = "[^0]' && bad "left stick acts as D-pad"
# 517 is RETRO_DEVICE_PSE_DUALSHOCK. RetroArch takes the pad type from a remap file, not from a core override.
file home/ga36/.config/retroarch/config/remaps/PCSX-ReARMed/PCSX-ReARMed.rmp 2>/dev/null | grep -qxF 'input_libretro_device_p1 = "517"' || bad "PSX pad is not a DualShock"
has usr/bin/evtest || bad "evtest missing"
# N64 and PSP: both letter cases of every extension (files copied from Windows are often upper case).
for s in 'n64:.n64 .z64 .v64 .zip' 'psp:.iso .cso .pbp .chd'; do
	n=${s%%:*}
	echo "$es" | grep -A3 "<name>$n</name>" | grep '<extension>' | tr ' <>' '\n\n\n' > "$t/ext"
	for e in ${s#*:}; do
		u=$(echo "$e" | tr a-z A-Z)
		grep -qx -- "$e" "$t/ext" && grep -qx -- "$u" "$t/ext" || bad "$n extension $e/$u missing"
	done
done
# Starting core options: PSP without frame skip, N64 at 320x240 without framebuffer emulation.
o=home/ga36/.config/retroarch/config
file $o/PPSSPP/PPSSPP.opt 2>/dev/null > "$t/psp.opt" || true
file $o/Mupen64Plus-Next/Mupen64Plus-Next.opt 2>/dev/null > "$t/n64.opt" || true
grep -qxF 'ppsspp_frameskip = "disabled"' "$t/psp.opt" || bad "PSP frame skip not off"
grep -qxF 'ppsspp_auto_frameskip = "disabled"' "$t/psp.opt" || bad "PSP auto frame skip not off"
grep -qxF 'mupen64plus-43screensize = "320x240"' "$t/n64.opt" || bad "N64 not 320x240"
grep -qxF 'mupen64plus-EnableFBEmulation = "False"' "$t/n64.opt" || bad "N64 framebuffer emulation on"
has usr/local/share/ppsspp/assets/ppge_atlas.zim || bad "PPSSPP assets not in the rootfs"
# Every library the cross-built cores need is installed (a cross build can link one the rootfs lacks).
for c in mupen64plus_next ppsspp; do
	file usr/local/lib/libretro/${c}_libretro.so > "$t/core" 2>/dev/null || { bad "$c not in the rootfs"; continue; }
	for l in $(readelf -d "$t/core" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
		grep -q "/$l\( -> .*\)\?\$" "$t/list" || bad "$c needs $l, not in the rootfs"
	done
done
[ $fail = 0 ] && echo PASS
exit $fail
