#!/bin/sh
# Development only. Run one command in the board's shell (U-Boot or Linux) over its USB console and print its output.
# Usage: scripts/board-run.sh 'CMD'
# Env: TTY (default /dev/ga36-linux; /dev/ga36-uboot for U-Boot), TIMEOUT seconds (default 30).
set -eu
TTY=${TTY:-/dev/ga36-linux}
TIMEOUT=${TIMEOUT:-30}
[ $# -eq 1 ] || { echo "usage: $0 'CMD'" >&2; exit 2; }
[ -e "$TTY" ] || { echo "$TTY missing: board not booted, cable out, or scripts/70-ga36-usb.rules not installed" >&2; exit 1; }
marker=__done_$$__
log=$(mktemp)
stty -F "$TTY" 115200 raw -echo
cat "$TTY" > "$log" &
cat_pid=$!
trap 'kill $cat_pid 2>/dev/null; rm -f "$log"' EXIT
printf '%s; echo %s\n' "$1" "$marker" > "$TTY"
end=$(( $(date +%s) + TIMEOUT ))
until tr -d '\r' < "$log" | grep -qx "$marker"; do
	[ "$(date +%s)" -lt "$end" ] || { echo "timeout after ${TIMEOUT}s: $1" >&2; exit 1; }
	sleep 0.2
done
# Print what follows the echoed command line, up to the marker line.
tr -d '\r' < "$log" | awk -v m="$marker" '$0 == m {exit} seen {print} index($0, m) {seen = 1}'
