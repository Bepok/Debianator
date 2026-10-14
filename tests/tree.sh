#!/bin/sh
# tree.sh keeps a current tree, rebuilds a stale one and refuses to discard local work.
# Run: ./build.sh run tests/tree.sh
set -eu
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
id="-c user.name=t -c user.email=t@example.org"

mkdir -p "$t/scripts" "$t/uboot/patches" "$t/kernel/patches"
cp scripts/tree.sh "$t/scripts/"
up=$t/upstream
git init -q "$up"
echo a > "$up/f"
git -C "$up" add f
git -C "$up" $id commit -q -m base
git -C "$up" tag v1
cat > "$t/versions.env" <<EOF
UBOOT_GIT=file://$up
UBOOT_TAG=v1
UBOOT_COMMIT=$(git -C "$up" rev-parse HEAD)
LINUX_VERSION=0
LINUX_SHA256=0
EOF
src=$t/out/src/u-boot

"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(cat "$src/f")" = a ] || fail "fresh tree not created"

# A commit exported as the patch set: prep keeps the tree as it is.
echo b > "$src/f"
git -C "$src" $id commit -qam change
"$t/scripts/tree.sh" export u-boot >/dev/null
ls "$t"/uboot/patches/0001-*.patch >/dev/null 2>&1 || fail "export wrote no patch"
head=$(git -C "$src" rev-parse HEAD)
"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(git -C "$src" rev-parse HEAD)" = "$head" ] || fail "current tree was rebuilt"

# Unexported commit while the patch set changes: refuse and keep the work.
echo c > "$src/f"
git -C "$src" $id commit -qam unexported
rm "$t"/uboot/patches/*.patch
if "$t/scripts/tree.sh" prep u-boot 2>/dev/null; then fail "prep discarded unexported work"; fi
[ "$(cat "$src/f")" = c ] || fail "local work lost"

# Uncommitted change: refuse as well.
git -C "$src" reset -q --hard "$head"
echo d > "$src/f"
if "$t/scripts/tree.sh" prep u-boot 2>/dev/null; then fail "prep discarded uncommitted work"; fi
[ "$(cat "$src/f")" = d ] || fail "uncommitted work lost"

# Clean tree, patch set changed (now empty): rebuilt from upstream.
git -C "$src" checkout -q f
"$t/scripts/tree.sh" prep u-boot >/dev/null
[ "$(cat "$src/f")" = a ] || fail "stale tree not rebuilt"
echo PASS
