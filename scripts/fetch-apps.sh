#!/bin/sh
# Fetches the pinned app trees into out/src with their patch series applied. Runs as the user in the build container.
set -eu
cd "$(dirname "$0")/.."
for a in emulationstation es-theme-carbon snes9x2010 gpsp picodrive beetle-pce-fast pcsx_rearmed; do
	scripts/tree.sh prep "$a"
done
