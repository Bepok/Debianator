#!/bin/sh
# CI workflow: builds the image on tag push and manual dispatch, stops early without armhf emulation, uploads the
# image on a dispatch and drafts a release on a tag. Static check only; the real run is recorded in
# docs/hardware/hardwareAnalysis.md. Run: ./build.sh run tests/workflow.sh
set -eu
w=.github/workflows/image.yml
[ -f "$w" ] || { echo "FAIL: $w missing"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
has() { grep -qE -- "$1" "$w" || bad "$2"; }
yamllint -d relaxed "$w" >/dev/null || bad "yamllint: $(yamllint -d relaxed -f parsable "$w" | head -1)"
has "tags: \['v\*'\]" "no v* tag trigger"
has '^  workflow_dispatch:' "no manual dispatch"
has 'contents: write' "no contents: write permission (needed for the release)"
has 'fetch-depth: 0' "checkout without tags: git describe would not see the version"
has 'persist-credentials: false' "checkout leaves a write token in .git/config, readable by the build containers"
has 'docker/setup-qemu-action@v3' "no armhf binfmt on the runner"
has 'platforms: arm$' "setup-qemu-action without platforms: arm"
has 'for t in tests/\*\.sh' "the test suite does not run after the build"
has 'actions/upload-artifact@v4' "no artifact on manual dispatch"
has 'retention-days: 1' "artifact kept longer than a day (500 MB storage on a private free plan)"
has 'gh release create .*--draft' "release is not a draft (the person publishes after the device checklist)"
has 'out/image/\*\.img\.xz out/image/SHA256SUMS' "release does not attach the .img.xz and SHA256SUMS"
c=$(grep -n '^ *run: .*tests/container\.sh' "$w" | head -1 | cut -d: -f1)
a=$(grep -n '^ *run: .*\./build\.sh all' "$w" | head -1 | cut -d: -f1)
[ -n "$c" ] && [ -n "$a" ] && [ "$c" -lt "$a" ] || bad "tests/container.sh must run before ./build.sh all"
[ $fail = 0 ] && echo PASS
exit $fail
