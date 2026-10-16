#!/bin/sh
# The charge screen program's helpers: battery fill width and sysfs integer reads, built for the host.
# Run: ./build.sh run tests/charge.sh
set -eu
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
gcc -Wall -Werror -o "$t/charge" tests/charge.c
"$t/charge" "$t"
