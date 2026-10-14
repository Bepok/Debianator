#!/bin/sh
# Schema checks: the bindings this series touches, and the GA36 DTB against all schemas.
# Run: ./build.sh run tests/dt-schema.sh
set -eu
k() { make -C out/src/linux O="$PWD/out/build/linux" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- "$@"; }
log=out/build/dt-schema.log
# Both checks are skipped when their outputs are current; remove them so every run validates.
rm -f out/build/linux/Documentation/devicetree/bindings/.dt-binding.checked \
	out/build/linux/Documentation/devicetree/bindings/.yamllint.checked \
	out/build/linux/Documentation/devicetree/bindings/display/panel/newvision,nv3051d.example.dtb \
	out/build/linux/arch/arm/boot/dts/allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb
{
	k dt_binding_check DT_SCHEMA_FILES="vendor-prefixes.yaml:newvision,nv3051d.yaml:arm/sunxi.yaml"
	k CHECK_DTBS=y allwinner/sun8i-a33-gameconsole-r36s-ga36.dtb
} > "$log" 2>&1 || { tail -30 "$log"; echo "FAIL: make failed"; exit 1; }
# Any line naming these files, other than make's progress lines ("  DTC [C] ..."), is a schema complaint.
if grep -E 'sun8i-a33-gameconsole|nv3051d|vendor-prefixes|sunxi.yaml' "$log" | grep -vE '^ +[A-Z_]+ '; then
	echo "FAIL: schema warnings above"
	exit 1
fi
echo PASS
