#!/bin/sh
# out/apps holds armhf hard-float ES, cores and the charge screen built against trixie, plus the packages they need at run time.
# Run: ./build.sh run tests/apps.sh
set -eu
a=out/apps
[ -d "$a/usr/local" ] || { echo "FAIL: $a missing (./build.sh apps)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
arm() { readelf -h "$1" | grep -q 'Machine: *ARM$' && readelf -A "$1" | grep -q 'Tag_ABI_VFP_args: VFP registers'; }
es=$a/usr/local/lib/emulationstation/emulationstation
if [ -f "$es" ]; then
	arm "$es" || bad "ES is not armhf"
	readelf -d "$es" | grep -q 'libgo2' && bad "ES links libgo2"
	readelf -d "$es" | grep -q 'libGLESv1_CM' || bad "ES does not link GLES1"
else
	bad "ES missing"
fi
[ -d "$a/usr/local/lib/emulationstation/resources" ] || bad "ES resources missing"
ch=$a/usr/local/sbin/ga36-charge
if [ -f "$ch" ]; then arm "$ch" || bad "ga36-charge is not armhf"; else bad "ga36-charge missing"; fi
for c in snes9x2010 gpsp picodrive mednafen_pce_fast pcsx_rearmed dosbox_pure parallel_n64 ppsspp; do
	so=$a/usr/local/lib/libretro/${c}_libretro.so
	[ -f "$so" ] || { bad "$c missing"; continue; }
	arm "$so" || bad "$c is not armhf"
	readelf --dyn-syms "$so" | grep -qw retro_api_version || bad "$c exports no retro_api_version"
done
readelf -A "$a/usr/local/lib/libretro/dosbox_pure_libretro.so" 2>/dev/null | grep -q 'Tag_CPU_arch: v7$' \
	|| bad "dosbox_pure is not built for ARMv7 (the A33 is a Cortex-A7)"
# N64: cross-compiled for GLES2 with the ARM dynarec (arm_cpu_features.c is built only with it).
m=$a/usr/local/lib/libretro/parallel_n64_libretro.so
readelf -A "$m" 2>/dev/null | grep -q 'Tag_CPU_arch: v7$' || bad "parallel_n64 is not built for ARMv7"
readelf -d "$m" 2>/dev/null | grep -q 'libGLESv2' || bad "parallel_n64 does not link GLESv2"
readelf -d "$m" 2>/dev/null | grep -q 'libGL\.so' && bad "parallel_n64 links desktop GL"
grep -aq 'ARM CPU Features:' "$m" 2>/dev/null || bad "parallel_n64 has no ARM dynarec"
# PSP: cross-compiled for GLES2 with the ARM32 JIT (the string comes only from Core/MIPS/ARM/ArmJit.cpp), plus the
# assets PPSSPP needs at run time and the version that decides when they are copied to ROMS again.
p=$a/usr/local/lib/libretro/ppsspp_libretro.so
readelf -A "$p" 2>/dev/null | grep -q 'Tag_CPU_arch: v7$' || bad "ppsspp is not built for ARMv7"
readelf -d "$p" 2>/dev/null | grep -q 'libGLESv2' || bad "ppsspp does not link GLESv2"
readelf -d "$p" 2>/dev/null | grep -q 'libGL\.so' && bad "ppsspp links desktop GL"
grep -aq 'ARM JIT initialized:' "$p" 2>/dev/null || bad "ppsspp has no ARM JIT"
[ -f "$a/usr/local/share/ppsspp/assets/ppge_atlas.zim" ] || bad "PPSSPP assets missing"
[ "$(cat "$a/usr/local/share/ppsspp/version" 2>/dev/null)" = v1.20.4 ] || bad "PPSSPP assets version"
for p in libsdl2-2.0-0 libfreeimage3 libgles1; do
	grep -qx "$p" "$a/runtime-deps.list" || bad "runtime-deps.list lacks $p"
done
grep -q -- '-dev$' "$a/runtime-deps.list" && bad "runtime-deps.list names a -dev package"
[ "$(stat -c %u "$a/runtime-deps.list")" = "$(id -u)" ] || bad "out/apps not handed back to the user"
[ $fail = 0 ] && echo PASS
exit $fail
