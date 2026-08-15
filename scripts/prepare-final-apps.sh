#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?source tree required}"
BUILDER="${2:?builder root required}"

OPENCLASH_REPO="https://github.com/vernesong/OpenClash.git"
OPENCLASH_COMMIT="c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593"
OPENCLASH_VERSION="0.47.156"
ISTORE_FEED="src-git istore https://github.com/linkease/istore.git;main"

test -d "$SOURCE"
test -d "$BUILDER"

FEEDS_CONF="$SOURCE/feeds.conf.default"
test -f "$FEEDS_CONF"
if ! grep -Fxq "$ISTORE_FEED" "$FEEDS_CONF"; then
  printf '%s\n' "$ISTORE_FEED" >> "$FEEDS_CONF"
fi

OPENCLASH_TMP="$BUILDER/.openclash-pinned"
rm -rf "$OPENCLASH_TMP"
git init "$OPENCLASH_TMP"
git -C "$OPENCLASH_TMP" remote add origin "$OPENCLASH_REPO"
git -C "$OPENCLASH_TMP" sparse-checkout init --cone
git -C "$OPENCLASH_TMP" sparse-checkout set luci-app-openclash
git -C "$OPENCLASH_TMP" fetch --depth=1 origin "$OPENCLASH_COMMIT"
git -C "$OPENCLASH_TMP" checkout --detach FETCH_HEAD
test "$(git -C "$OPENCLASH_TMP" rev-parse HEAD)" = "$OPENCLASH_COMMIT"

OPENCLASH_DST="$SOURCE/package/luci-app-openclash"
rm -rf "$OPENCLASH_DST"
cp -a "$OPENCLASH_TMP/luci-app-openclash" "$OPENCLASH_DST"
grep -qx "PKG_VERSION:=$OPENCLASH_VERSION" "$OPENCLASH_DST/Makefile"
