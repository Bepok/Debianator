#!/bin/sh
# Runs inside the throwaway armhf chroot of scripts/build-apps.sh. Builds into /stage and writes the Debian packages
# the results link at run time to /stage/runtime-deps.list.
set -eu
j=$(nproc)
es=/stage/usr/local/lib/emulationstation
lr=/stage/usr/local/lib/libretro
mkdir -p "$es" "$lr"

cmake -S /src/emulationstation -B /tmp/es -DGLES=ON -DCMAKE_BUILD_TYPE=Release
make -C /tmp/es -j"$j"
# ES writes its binary into the source directory and looks for resources/ beside it.
cp /src/emulationstation/emulationstation "$es/"
cp -r /src/emulationstation/resources "$es/"

core() { # tree makefile output
	make -C "/src/$1" -f "$2" platform=classic_armv7_a7 LIBM=-lm -j"$j"
	cp "/src/$1/$3" "$lr/"
}
core snes9x2010 Makefile.libretro snes9x2010_libretro.so
core gpsp Makefile gpsp_libretro.so
core picodrive Makefile.libretro picodrive_libretro.so
core beetle-pce-fast Makefile mednafen_pce_fast_libretro.so
core pcsx_rearmed Makefile.libretro pcsx_rearmed_libretro.so

# Charge screen, run as init= on a charger power-on (apps/ga36-charge.c).
mkdir -p /stage/usr/local/sbin
cc -O2 -Wall -Wextra -Werror -o /stage/usr/local/sbin/ga36-charge /src/ga36-charge.c

for f in "$es/emulationstation" "$lr"/*.so /stage/usr/local/sbin/ga36-charge; do ldd "$f"; done | awk '/=> \//{print $3}' | sort -u > /tmp/libs
while read -r lib; do
	dpkg -S "$(realpath "$lib")" 2>/dev/null || dpkg -S "$lib"
done < /tmp/libs > /tmp/owners
cut -d: -f1 /tmp/owners | sort -u > /stage/runtime-deps.list
