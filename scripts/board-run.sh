#!/bin/sh
# Development only. Run one command in the board's shell (U-Boot or Linux) over its USB console and print its output.
# Usage: scripts/board-run.sh 'CMD'
# Env: TTY (default /dev/ga36-linux; /dev/ga36-uboot for U-Boot), TIMEOUT seconds (default 30).
set -eu
TTY=${TTY:-/dev/ga36-linux}
TIMEOUT=${TIMEOUT:-30}
[ $# -eq 1 ] || { echo "usage: $0 'CMD'" >&2; exit 2; }
[ -e "$TTY" ] || { echo "$TTY missing: board not booted, cable out, or scripts/70-ga36-usb.rules not installed" >&2; exit 1; }
log=$(mktemp)
stty -F "$TTY" 115200 raw -echo
cat "$TTY" > "$log" &
cat_pid=$!
trap 'kill $cat_pid 2>/dev/null; rm -f "$log"' EXIT
# The first open of a new ACM tty echoes the board's backlog back to it, which leaves stray input in its shell:
# Ctrl-C plus a newline drops it, and the pause lets readline redraw (else it eats the command's first character).
# The "" keeps the shell's echo of the command line from matching the markers;
# the begin pattern is unanchored because bash may print a bracketed-paste escape before the marker.
printf '\003\n' > "$TTY"
sleep 0.5
printf 'echo __begin_""%s__; %s; echo __end_""%s__\n' $$ "$1" $$ > "$TTY"
end=$(( $(date +%s) + TIMEOUT ))
until tr -d '\r' < "$log" | grep -qx "__end_$$__"; do
	[ "$(date +%s)" -lt "$end" ] || { echo "timeout after ${TIMEOUT}s: $1" >&2; exit 1; }
	sleep 0.2
done
tr -d '\r' < "$log" | sed -n "/__begin_$$__\$/,/^__end_$$__\$/p" | sed '1d;$d'
