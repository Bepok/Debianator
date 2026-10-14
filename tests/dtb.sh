#!/bin/sh
# Guard rails and wiring of the GA36 DTB: no rail or OPP above the vendor (or, where the vendor sets none, the
# A33 reference design) values, U-Boot's rails always on,
# CPU on DCDC3, ramoops region (repo-only patch), charge limits from [pmu1_para], all 17 buttons. Run: ./build.sh run tests/dtb.sh
set -eu
d=out/kernel/sun8i-a33-gameconsole-r36s-ga36.dtb
[ -f "$d" ] || { echo "FAIL: $d missing (./build.sh kernel)"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
R=/soc/rsb@1f03400/pmic@3a3/regulators   # node names from axp22x.dtsi

[ "$(fdtget "$d" / compatible)" = "gameconsole,r36s-ga36 allwinner,sun8i-a33" ] || bad "root compatible"

# Limits: vendor [power_sply] (dcdc3: the highest vendor DVFS voltage allowed so far); aldo1 and dc5ldo are not in
# the fex, so theirs are the A33 reference design's (sina33).
for row in vendor:dcdc1:3000000 vendor:dcdc2:1100000 vendor:dcdc3:1320000 vendor:dcdc5:1500000 \
	vendor:aldo2:2500000 vendor:aldo3:3000000 vendor:dldo3:3000000 reference:aldo1:3000000 reference:dc5ldo:1400000; do
	src=${row%%:*} row=${row#*:}
	n=${row%%:*} lim=${row#*:}
	max=$(fdtget -t u "$d" "$R/$n" regulator-max-microvolt) || { bad "$n has no voltage limit"; continue; }
	[ "$max" -le "$lim" ] || bad "$n max $max uV above $src $lim uV"
	fdtget "$d" "$R/$n" regulator-always-on >/dev/null 2>&1 || bad "$n not always-on"
done

[ "$(fdtget -t x "$d" /cpus/cpu@0 cpu-supply)" = "$(fdtget -t x "$d" "$R/dcdc3" phandle)" ] \
	|| bad "cpu-supply is not dcdc3"

# Vendor [dvfs_table]: 648 MHz 1.04 V, 816 MHz 1.10 V, 1008 MHz 1.20 V, 1200 MHz 1.32 V; max_freq 1.2 GHz.
vendor_uv() {
	for row in 648000000:1040000 816000000:1100000 1008000000:1200000 1200000000:1320000; do
		[ "$1" -le "${row%%:*}" ] && { echo "${row#*:}"; return; }
	done
	echo 0
}
for n in $(fdtget -l "$d" /opp-table-cpu); do
	f=${n#opp-}
	uv=$(fdtget -t u "$d" "/opp-table-cpu/$n" opp-microvolt | cut -d' ' -f1)
	lim=$(vendor_uv "$f")
	[ "$uv" -le "$lim" ] || bad "$n at $uv uV above vendor $lim uV"
done

# ramoops below U-Boot (0x4a000000), clear of the FEL loads (zImage 0x42000000 .. initrd 0x43400000 + ~12 MB).
[ "$(fdtget -t x "$d" /reserved-memory/ramoops@49000000 reg 2>/dev/null)" = "49000000 100000" ] || bad "ramoops region"
[ "$(fdtget -t u "$d" /opp-table-cpu/opp-1200000000 opp-microvolt 2>/dev/null | cut -d' ' -f1)" = 1320000 ] \
	|| bad "no 1.2 GHz OPP at 1.32 V"
# Charging from [pmu1_para]: pmu_runtime_chgcur 300 mA, pmu_init_chgvol 4200 mV.
[ "$(fdtget -t u "$d" /battery constant-charge-current-max-microamp)" = 300000 ] || bad "charge current"
[ "$(fdtget -t u "$d" /battery constant-charge-voltage-max-microvolt)" = 4200000 ] || bad "charge voltage"

# BTN_SOUTH..BTN_THUMBR, KEY_FN, BTN_DPAD_*.
codes=$(for n in $(fdtget -l "$d" /gpio-keys); do fdtget -t u "$d" "/gpio-keys/$n" linux,code; done | sort -n | tr '\n' ' ')
[ "$codes" = "304 305 307 308 310 311 312 313 314 315 317 318 464 544 545 546 547 " ] || bad "button codes: $codes"

[ $fail = 0 ] && echo PASS
exit $fail
