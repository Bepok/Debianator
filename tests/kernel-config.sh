#!/bin/sh
# Every option in kernel/ga36.config survived merge_config and olddefconfig (a dropped option means a
# missing dependency or a renamed symbol). Run: ./build.sh run tests/kernel-config.sh
set -eu
c=out/build/linux/.config
[ -f "$c" ] || { echo "FAIL: $c missing (./build.sh kernel)"; exit 1; }
fail=0
for opt in $(grep '^CONFIG_' kernel/ga36.config); do
	grep -qx "$opt" "$c" || { echo "FAIL: $opt not in final config ($(grep "^${opt%%=*}=" "$c" || echo unset))"; fail=1; }
done
[ $fail = 0 ] && echo PASS
exit $fail
