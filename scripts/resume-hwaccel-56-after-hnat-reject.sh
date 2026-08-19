#!/usr/bin/env bash
set -euo pipefail

BUILDER="$(cd "$(dirname "$0")/.." && pwd)"
WORKROOT="${N60PRO_WORKROOT:-$HOME/n60pro-hwaccel-56-work}"
SOURCE="$WORKROOT/source"
DONOR="$WORKROOT/mtk-donor"
LOGDIR="$WORKROOT/logs"
JOBS="${JOBS:-$(nproc)}"

OFFICIAL_COMMIT="a3378d1a2c15beb2faf4b0bce9c00f07143efa29"
MTK_COMMIT="eb724bb94de346f36b35bdb0f7de31b529bbc885"
PATCH_NAME="999-eth-91-mtk_eth_soc-add-mtkhnat-driver-support.patch"
PATCH="$SOURCE/target/linux/mediatek/patches-6.12/$PATCH_NAME"
DONOR_PATCH="$DONOR/target/linux/mediatek/patches-6.12/$PATCH_NAME"

run_stage() {
  local name="$1" target="$2"
  local fast_log="$LOGDIR/${name}-resume.log"
  local verbose_log="$LOGDIR/${name}-resume-verbose.log"
  echo
  echo "===== #56 resume stage: $name ====="
  if make -C "$SOURCE" "$target" -j"$JOBS" V=sc 2>&1 | tee "$fast_log"; then
    echo "PASS: $name"
    return 0
  fi
  echo "Parallel stage failed; rerunning once with -j1 V=s for readable failure." >&2
  make -C "$SOURCE" "$target" -j1 V=s 2>&1 | tee "$verbose_log"
}

find_one() {
  local pattern="$1" label="$2"
  local found
  found="$(find "$SOURCE/build_dir" -type f -name "$pattern" -print -quit 2>/dev/null || true)"
  test -n "$found" || {
    echo "missing expected output: $label ($pattern)" >&2
    exit 1
  }
  echo "$label: $found"
}

mkdir -p "$LOGDIR"

test "$(git -C "$BUILDER" rev-parse --abbrev-ref HEAD)" = "agent/hwaccel-56"
test -z "$(git -C "$BUILDER" status --porcelain)" || {
  echo "builder worktree is not clean; stop before resume" >&2
  git -C "$BUILDER" status --short >&2
  exit 2
}
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$OFFICIAL_COMMIT"
test "$(git -C "$DONOR" rev-parse HEAD)" = "$MTK_COMMIT"
test -f "$SOURCE/.config"
test -f "$DONOR_PATCH"
test -f "$BUILDER/scripts/rebase-hnat-eth-patch-56.py"

grep -qx 'CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-warp=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_FAST_NAT_SUPPORT=y' "$SOURCE/.config"
grep -Eq '^CONFIG_MTK_WHNAT_SUPPORT=(m|y)$' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_WARP_V2=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0' "$SOURCE/.config"
grep -qx '# CONFIG_MTK_MT7986_NEW_FW is not set' "$SOURCE/.config"

# Restore only the failed donor Ethernet HNAT patch, then rebase its three
# incompatible PPE ownership hunks to the official 25.12.1 / Linux 6.12 layout.
# Everything else in the already-prepared #56 source tree is left untouched.
install -m0644 "$DONOR_PATCH" "$PATCH"
python3 "$BUILDER/scripts/rebase-hnat-eth-patch-56.py" "$PATCH"

# The previous stage stopped while kernel patches were being applied. Clean only
# target/linux so the corrected patch stack is reapplied; preserve host tools,
# feeds, downloads, staging/toolchain and the prepared #56 source/config.
make -C "$SOURCE" target/linux/clean
run_stage 01-target-linux target/linux/compile

KCONF="$(find "$SOURCE/build_dir" -type f -path '*/linux-mediatek_filogic/linux-6.12*/.config' -print -quit 2>/dev/null || true)"
test -n "$KCONF" || { echo "kernel .config not found" >&2; exit 1; }
grep -Eq '^CONFIG_NET_MEDIATEK_HNAT=m$' "$KCONF"
grep -Eq '^CONFIG_NET_MEDIATEK_SOC_WED=y$' "$KCONF"
find_one mtkhnat.ko 'HNAT module'

run_stage 02-warp package/mtk/drivers/warp/compile
find_one mtk_warp.ko 'WARP module'

run_stage 03-wifi-utility package/mtk/drivers/wifi_utility/compile
run_stage 04-conninfra package/mtk/drivers/conninfra/compile
find_one mtk_wifi_utility.ko 'WiFi utility module'
find_one conninfra.ko 'conninfra module'

run_stage 05-mt-wifi package/mtk/drivers/mt_wifi/compile
find_one mt_wifi.ko 'Golden mt_wifi module'
find_one mtk_warp_proxy.ko 'WARP proxy module'

grep -Fqx '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi) $(call AutoLoad,61,mtk_warp_proxy)' \
  "$SOURCE/package/mtk/drivers/mt_wifi/Makefile"

echo
echo '============================================================'
echo '#56 HARDWARE-ACCELERATION COMPILE GATE: PASS'
echo 'Resume path reused the existing local toolchain/download/staging state.'
echo 'No sysupgrade image was built and nothing should be flashed yet.'
echo "Logs: $LOGDIR"
echo '============================================================'
