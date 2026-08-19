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
ISTORE_COMMIT="6f795b7640390ab28a2f1aaa14b33292aa5f2128"

mkdir -p "$WORKROOT" "$LOGDIR"

for cmd in git make rsync curl python3 awk sed grep find tee; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 2
  }
done

clone_pinned() {
  local url="$1" dir="$2" commit="$3"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$commit"
  git -C "$dir" checkout --detach FETCH_HEAD
  git -C "$dir" reset --hard "$commit"
  git -C "$dir" clean -fdx
  test "$(git -C "$dir" rev-parse HEAD)" = "$commit"
}

run_stage() {
  local name="$1" target="$2"
  local fast_log="$LOGDIR/${name}.log"
  local verbose_log="$LOGDIR/${name}-verbose.log"
  echo
  echo "===== #56 stage: $name ====="
  if make -C "$SOURCE" "$target" -j"$JOBS" V=sc 2>&1 | tee "$fast_log"; then
    echo "PASS: $name"
    return 0
  fi

  echo "Parallel stage failed; rerunning once with -j1 V=s for a readable failure log." >&2
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

echo "#56 workroot: $WORKROOT"
echo "builder branch: $(git -C "$BUILDER" rev-parse --abbrev-ref HEAD)"
test "$(git -C "$BUILDER" rev-parse --abbrev-ref HEAD)" = "agent/hwaccel-56" || {
  echo "builder must be on agent/hwaccel-56" >&2
  exit 2
}

# Fresh pinned source trees inside the WSL Linux filesystem. They do not reuse
# a previous failed source tree, but the workroot itself can be kept for logs.
clone_pinned https://github.com/immortalwrt/immortalwrt.git "$SOURCE" "$OFFICIAL_COMMIT"
clone_pinned https://github.com/chasey-dev/immortalwrt-mt798x-rebase.git "$DONOR" "$MTK_COMMIT"

grep -q '25.12.1' "$SOURCE/include/version.mk"

# Recreate the proven #55 baseline first, then add only the #56 acceleration
# overlay. Never copy the donor target/linux/mediatek tree wholesale.
bash "$BUILDER/scripts/prepare.sh" "$SOURCE" "$DONOR" "$BUILDER"
bash "$BUILDER/scripts/fix-wifi-utility-module.sh" "$SOURCE"
bash "$BUILDER/scripts/prepare-hwaccel-56.sh" "$SOURCE" "$DONOR" "$BUILDER"

# Keep the same final app/feed inputs as #55 so the only functional delta under
# this gate is the hardware-acceleration chain.
bash "$BUILDER/scripts/prepare-final-apps.sh" "$SOURCE" "$BUILDER"
(
  cd "$SOURCE"
  ./scripts/feeds update -a
  git -C feeds/istore checkout --detach "$ISTORE_COMMIT"
  test "$(git -C feeds/istore rev-parse HEAD)" = "$ISTORE_COMMIT"
  ./scripts/feeds install -a
)

# Build the kernel sidecar while the new HNAT KernelPackage is already visible.
bash "$BUILDER/scripts/rebase-official-release-config.sh" "$SOURCE" "$BUILDER"

# Same package trimming used by the successful #55 build. Do this BEFORE
# enabling #56 so MTK_WHNAT_SUPPORT=m is not removed afterwards.
(
  cd "$SOURCE"
  sed -i -E '/^CONFIG_PACKAGE_.*=m$/d' .config
  for sym in ALL_KMODS ALL_NONSHARED SDK SDK_LLVM_BPF IB MAKE_TOOLCHAIN COLLECT_KERNEL_DEBUG; do
    sed -i -E "/^CONFIG_${sym}=y$/d; /^# CONFIG_${sym} is not set$/d" .config
    echo "# CONFIG_${sym} is not set" >> .config
  done
  make defconfig
)

bash "$BUILDER/scripts/enable-hwaccel-config-56.sh" "$SOURCE" "$BUILDER"

# Config-level stop gate before spending time compiling.
grep -qx 'CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-warp=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_FAST_NAT_SUPPORT=y' "$SOURCE/.config"
grep -Eq '^CONFIG_MTK_WHNAT_SUPPORT=(m|y)$' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_WARP_V2=y' "$SOURCE/.config"
grep -qx 'CONFIG_WARP_CHIPSET="mt7986"' "$SOURCE/.config"
grep -qx 'CONFIG_WARP_VERSION=2' "$SOURCE/.config"
grep -qx 'CONFIG_WED_HW_RRO_SUPPORT=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0' "$SOURCE/.config"
grep -qx '# CONFIG_MTK_MT7986_NEW_FW is not set' "$SOURCE/.config"
grep -q 'N60PRO_HWACCEL_56_DTS_BEGIN' "$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"
grep -q 'mtketh-soc = <&eth>;' "$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"
grep -q 'compatible = "mediatek,wed", "mediatek,mt7986-wed", "syscon";' "$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"
grep -q 'compatible = "mediatek,wed2", "mediatek,mt7986-wed", "syscon";' "$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

echo "Config/DTS gate: PASS"

# Download only after all static gates pass.
make -C "$SOURCE" download -j"$JOBS"
find "$SOURCE/dl" -type f -size -1024c -delete || true

# Gate 1: Linux + minimal HNAT hooks. This catches patch/DTS/Kconfig failures
# before building proprietary Wi-Fi.
run_stage 01-target-linux target/linux/compile

KCONF="$(find "$SOURCE/build_dir" -type f -path '*/linux-mediatek_filogic/linux-6.12*/.config' -print -quit 2>/dev/null || true)"
test -n "$KCONF" || {
  echo "kernel .config not found after target/linux/compile" >&2
  exit 1
}
grep -Eq '^CONFIG_NET_MEDIATEK_HNAT=m$' "$KCONF"
grep -Eq '^CONFIG_NET_MEDIATEK_SOC_WED=y$' "$KCONF"
find_one mtkhnat.ko 'HNAT module'

# Gate 2: proprietary WARP against Linux 6.12 + HNAT.
run_stage 02-warp package/mtk/drivers/warp/compile
find_one mtk_warp.ko 'WARP module'

# Gate 3: #55 helper/conninfra chain remains buildable before mt_wifi.
run_stage 03-wifi-utility package/mtk/drivers/wifi_utility/compile
run_stage 04-conninfra package/mtk/drivers/conninfra/compile
find_one mtk_wifi_utility.ko 'WiFi utility module'
find_one conninfra.ko 'conninfra module'

# Gate 4: exact Golden 7.6.6.1 mt_wifi + WARP proxy.
run_stage 05-mt-wifi package/mtk/drivers/mt_wifi/compile
find_one mt_wifi.ko 'Golden mt_wifi module'
find_one mtk_warp_proxy.ko 'WARP proxy module'

grep -Fqx '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi) $(call AutoLoad,61,mtk_warp_proxy)' \
  "$SOURCE/package/mtk/drivers/mt_wifi/Makefile"

echo
echo '============================================================'
echo '#56 HARDWARE-ACCELERATION COMPILE GATE: PASS'
echo 'No sysupgrade image was built and nothing should be flashed yet.'
echo "Logs: $LOGDIR"
echo '============================================================'
