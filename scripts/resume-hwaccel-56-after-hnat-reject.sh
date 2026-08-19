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
KERNEL_CFG="$SOURCE/target/linux/mediatek/filogic/config-6.12"

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
# Only tracked/staged edits can invalidate this resume. The builder intentionally
# keeps local download/source caches such as .golden-mt-wifi-exact/ and
# .openclash-pinned/ untracked so they can be reused without another download.
if ! git -C "$BUILDER" diff --quiet || ! git -C "$BUILDER" diff --cached --quiet; then
  echo "builder has tracked or staged changes; stop before resume" >&2
  git -C "$BUILDER" status --short >&2
  exit 2
fi
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$OFFICIAL_COMMIT"
test "$(git -C "$DONOR" rev-parse HEAD)" = "$MTK_COMMIT"
test -f "$SOURCE/.config"
test -f "$DONOR_PATCH"
test -f "$KERNEL_CFG"
test -f "$BUILDER/scripts/rebase-hnat-eth-patch-56.py"

grep -qx 'CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-warp=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_FAST_NAT_SUPPORT=y' "$SOURCE/.config"
grep -Eq '^CONFIG_MTK_WHNAT_SUPPORT=(m|y)$' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_WARP_V2=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0' "$SOURCE/.config"
grep -qx '# CONFIG_MTK_MT7986_NEW_FW is not set' "$SOURCE/.config"

# The donor HNAT patch adds NETSYS generation prompts to the kernel Kconfig.
# MT7986 is NETSYS V2, matching the pinned donor filogic/config-6.12. Pin both
# generation symbols here before target/linux/clean so syncconfig cannot stop
# on a NEW prompt and leave include/config/auto.conf missing.
python3 - "$KERNEL_CFG" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
syms = ('MEDIATEK_NETSYS_V2', 'MEDIATEK_NETSYS_V3')
out = [
    line for line in lines
    if not any(re.match(rf'^(?:# )?CONFIG_{sym}(?:=| is not set$)', line) for sym in syms)
]
out += [
    'CONFIG_MEDIATEK_NETSYS_V2=y',
    '# CONFIG_MEDIATEK_NETSYS_V3 is not set',
]
p.write_text('\n'.join(out).rstrip() + '\n')
PY
grep -qx 'CONFIG_MEDIATEK_NETSYS_V2=y' "$KERNEL_CFG"
grep -qx '# CONFIG_MEDIATEK_NETSYS_V3 is not set' "$KERNEL_CFG"

# Restore only the failed donor Ethernet HNAT patch, then rebase its three
# incompatible PPE ownership hunks to the official 25.12.1 / Linux 6.12 layout.
# Everything else in the already-prepared #56 source tree is left untouched.
install -m0644 "$DONOR_PATCH" "$PATCH"
python3 "$BUILDER/scripts/rebase-hnat-eth-patch-56.py" "$PATCH"

# The first local run proved that this fresh workroot had never completed the
# OpenWrt host-tool/cross-toolchain bootstrap. target/linux cannot be compiled
# until staging_dir/host/bin/m4 and aarch64-openwrt-linux-musl-gcc are usable.
# Build those prerequisites now and keep them for every later resume.
run_stage 00-tools tools/install
run_stage 00-toolchain toolchain/install

test -x "$SOURCE/staging_dir/host/bin/m4" || {
  echo "host m4 missing after tools/install" >&2
  exit 1
}
"$SOURCE/staging_dir/host/bin/m4" --version >/dev/null

TOOLCHAIN_GCC="$(find "$SOURCE/staging_dir" -path '*/bin/aarch64-openwrt-linux-musl-gcc' -print -quit 2>/dev/null || true)"
test -n "$TOOLCHAIN_GCC" && test -x "$TOOLCHAIN_GCC" || {
  echo "aarch64-openwrt-linux-musl-gcc missing after toolchain/install" >&2
  exit 1
}
"$TOOLCHAIN_GCC" --version >/dev/null

echo "Host tools/toolchain gate: PASS"

# The previous stage stopped while kernel configuration/build was starting.
# Clean only target/linux so the corrected HNAT patch stack is reapplied while
# preserving downloads, feeds, host tools, cross toolchain and staging state.
make -C "$SOURCE" target/linux/clean
run_stage 01-target-linux target/linux/compile

KCONF="$(find "$SOURCE/build_dir" -type f -path '*/linux-mediatek_filogic/linux-6.12*/.config' -print -quit 2>/dev/null || true)"
test -n "$KCONF" || { echo "kernel .config not found" >&2; exit 1; }
grep -Eq '^CONFIG_NET_MEDIATEK_HNAT=m$' "$KCONF"
grep -Eq '^CONFIG_NET_MEDIATEK_SOC_WED=y$' "$KCONF"
grep -Eq '^CONFIG_MEDIATEK_NETSYS_V2=y$' "$KCONF"
grep -Eq '^# CONFIG_MEDIATEK_NETSYS_V3 is not set$' "$KCONF"
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
echo 'Resume path reused the existing local downloads/feeds/staging state.'
echo 'No sysupgrade image was built and nothing should be flashed yet.'
echo "Logs: $LOGDIR"
echo '============================================================'
