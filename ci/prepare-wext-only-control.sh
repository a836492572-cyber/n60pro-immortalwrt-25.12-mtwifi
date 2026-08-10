#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare-wext-only-control.sh <official-source>}"
OFFICIAL_COMMIT="${OFFICIAL_COMMIT:-a3378d1a2c15beb2faf4b0bce9c00f07143efa29}"
OFFICIAL_CONFIG_URL="${OFFICIAL_CONFIG_URL:-https://downloads.immortalwrt.org/releases/25.12.1/targets/mediatek/filogic/config.buildinfo}"
PACKAGES_COMMIT="${PACKAGES_COMMIT:-e93a938c63124832d549c41da3157e2ec40fbe05}"
LUCI_COMMIT="${LUCI_COMMIT:-ed7692cb08a953e2e503287e0337c8b548cf4ba5}"
ROUTING_COMMIT="${ROUTING_COMMIT:-76c933906c616a4cdf865611af0a381787bd87b8}"
TELEPHONY_COMMIT="${TELEPHONY_COMMIT:-2618106d5846a4a542fdf5809f0d3ed228ce439b}"
WEXT_PATCH="target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
GENERIC_CONFIG="$SOURCE/target/linux/generic/config-6.12"
N60PRO_DTS="$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

test "$(git -C "$SOURCE" rev-parse HEAD)" = "$OFFICIAL_COMMIT"
grep -q '25.12.1' "$SOURCE/include/version.mk"
test "$(git -C "$SOURCE/feeds/packages" rev-parse HEAD)" = "$PACKAGES_COMMIT"
test "$(git -C "$SOURCE/feeds/luci" rev-parse HEAD)" = "$LUCI_COMMIT"
test "$(git -C "$SOURCE/feeds/routing" rev-parse HEAD)" = "$ROUTING_COMMIT"
test "$(git -C "$SOURCE/feeds/telephony" rev-parse HEAD)" = "$TELEPHONY_COMMIT"
test ! -e "$SOURCE/package/mtk"
test -f "$N60PRO_DTS"
! grep -Eq 'mediatek,wbsys|mediatek,mt7986-consys' "$N60PRO_DTS"

for pat in '*5202*' '*5203*' '*5204*'; do
  test -z "$(find "$SOURCE/target/linux" -type f -name "$pat" -print -quit)"
done

mkdir -p "$SOURCE/$(dirname "$WEXT_PATCH")"
sed -e 's/@TAB@/\t/g' -e 's/^ @EMPTY@$/ /' > "$SOURCE/$WEXT_PATCH" <<'PATCH'
--- a/net/wireless/Kconfig
+++ b/net/wireless/Kconfig
@@ -1,6 +1,6 @@
 # SPDX-License-Identifier: GPL-2.0-only
 config WIRELESS_EXT
-@TAB@bool
+	bool "Wireless extensions"
 @EMPTY@
 config WEXT_CORE
 @TAB@def_bool y
@@ -12,10 +12,10 @@ config WEXT_PROC
 @TAB@depends on WEXT_CORE
 @EMPTY@
 config WEXT_SPY
-@TAB@bool
+	bool "WEXT_SPY"
 @EMPTY@
 config WEXT_PRIV
-@TAB@bool
+	bool "WEXT_PRIV"
 @EMPTY@
 config CFG80211
 @TAB@tristate "cfg80211 - wireless configuration API"
PATCH
grep -Eq 'WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY' "$SOURCE/$WEXT_PATCH"
! grep -Eq 'LIB80211' "$SOURCE/$WEXT_PATCH"
! grep -Eiq 'mt_wifi|conninfra|wifi_utility|wbsys|mt7986-consys|hnat|warp|whnat|fast.nat|rfbin|mt7986.*dbdc' "$SOURCE/$WEXT_PATCH"

git -C "$SOURCE" checkout -- target/linux/generic/config-6.12
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  if grep -qx "# CONFIG_${sym} is not set" "$GENERIC_CONFIG"; then
    sed -i "s/^# CONFIG_${sym} is not set$/CONFIG_${sym}=y/" "$GENERIC_CONFIG"
  elif ! grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"; then
    echo "CONFIG_${sym}=y" >> "$GENERIC_CONFIG"
  fi
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fL --retry 5 --retry-delay 2 "$OFFICIAL_CONFIG_URL" -o "$tmp"
grep -q '^CONFIG_TARGET_mediatek=y$' "$tmp"
grep -q '^CONFIG_TARGET_mediatek_filogic=y$' "$tmp"
cp "$tmp" "$SOURCE/.config"
make -C "$SOURCE" defconfig
cp "$SOURCE/.config" "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_TARGET_mediatek=y' "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_TARGET_mediatek_filogic=y' "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_KMODS=y' "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_NONSHARED=y' "$SOURCE/.config.kernel-official"

KERNEL_DEFAULTS="$SOURCE/include/kernel-defaults.mk"
python3 - "$KERNEL_DEFAULTS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old_kernel = '\tawk \'/^(#[[:space:]]+)?CONFIG_KERNEL/{sub("CONFIG_KERNEL_","CONFIG_");print}\' $(TOPDIR)/.config >> $(LINUX_DIR)/.config.target\n'
new_kernel = '\tawk \'/^(#[[:space:]]+)?CONFIG_KERNEL/{sub("CONFIG_KERNEL_","CONFIG_");print}\' $(TOPDIR)/.config.kernel-official >> $(LINUX_DIR)/.config.target\n'
old_metadata = '\t$(SCRIPT_DIR)/package-metadata.pl kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config $(KERNEL_PATCHVER) > $(LINUX_DIR)/.config.override\n'
new_metadata = '\t[ -f $(TOPDIR)/.config.kernel-official ]\n\t$(SCRIPT_DIR)/package-metadata.pl kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config.kernel-official $(KERNEL_PATCHVER) > $(LINUX_DIR)/.config.override\n'
for name, old in [('CONFIG_KERNEL awk input', old_kernel), ('kernel package-metadata input', old_metadata)]:
    if s.count(old) != 1:
        raise SystemExit(f'{name} pattern count != 1: {s.count(old)}')
s = s.replace(old_kernel, new_kernel, 1).replace(old_metadata, new_metadata, 1)
p.write_text(s)
PY
grep -Fq '$(TOPDIR)/.config.kernel-official >> $(LINUX_DIR)/.config.target' "$KERNEL_DEFAULTS"
grep -Fq '$(TOPDIR)/.config.kernel-official $(KERNEL_PATCHVER) > $(LINUX_DIR)/.config.override' "$KERNEL_DEFAULTS"
! grep -Fq '$(TOPDIR)/.config >> $(LINUX_DIR)/.config.target' "$KERNEL_DEFAULTS"
! grep -Fq 'package-metadata.pl kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config $(KERNEL_PATCHVER)' "$KERNEL_DEFAULTS"

cp "$SOURCE/.config.kernel-official" "$SOURCE/.config"
sed -i -E '/^CONFIG_PACKAGE_.*=m$/d' "$SOURCE/.config"
for sym in ALL_KMODS ALL_NONSHARED SDK SDK_LLVM_BPF IB MAKE_TOOLCHAIN COLLECT_KERNEL_DEBUG BUILDBOT AUTOREMOVE AUTOREBUILD; do
  sed -i -E "/^CONFIG_${sym}=y$/d; /^# CONFIG_${sym} is not set$/d" "$SOURCE/.config"
  echo "# CONFIG_${sym} is not set" >> "$SOURCE/.config"
done
sed -i -E '/^(# )?CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/d' "$SOURCE/.config"
sed -i -E '/^(# )?CONFIG_TARGET_ALL_PROFILES(=| )/d' "$SOURCE/.config"
cat >> "$SOURCE/.config" <<'CFG'
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_netcore_n60-pro=""
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CFG

make -C "$SOURCE" defconfig

grep -qx 'CONFIG_TARGET_mediatek=y' "$SOURCE/.config"
grep -qx 'CONFIG_TARGET_mediatek_filogic=y' "$SOURCE/.config"
grep -qx 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y' "$SOURCE/.config"
grep -qx 'CONFIG_TARGET_ROOTFS_INITRAMFS=y' "$SOURCE/.config"
grep -qx '# CONFIG_ALL_KMODS is not set' "$SOURCE/.config"
grep -qx '# CONFIG_ALL_NONSHARED is not set' "$SOURCE/.config"
for sym in BUILDBOT AUTOREMOVE AUTOREBUILD; do
  grep -qx "# CONFIG_${sym} is not set" "$SOURCE/.config"
done
! grep -Eq '^CONFIG_PACKAGE_(kmod-mt_wifi|kmod-conninfra|kmod-mt-wifi-utility|mtwifi-cfg|luci-app-mtwifi-cfg|kmod-warp|kmod-mediatek_hnat)=' "$SOURCE/.config"
! grep -Eq '^CONFIG_MTK_|^CONFIG_first_card' "$SOURCE/.config"
test -f "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_KMODS=y' "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_NONSHARED=y' "$SOURCE/.config.kernel-official"

for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"
done

unexpected="$({ git -C "$SOURCE" diff --unified=0 -- target/linux/generic/config-6.12 || true; } \
  | grep -E '^[+-](CONFIG_|# CONFIG_)' \
  | grep -Ev '^[+-](CONFIG_(WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY)=y|# CONFIG_(WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY) is not set)$' \
  || true)"
test -z "$unexpected"

kernel_status="$(git -C "$SOURCE" status --short -- target/linux/generic target/linux/mediatek)"
printf '%s\n' "$kernel_status" \
  | grep -Ev '^( M target/linux/generic/config-6\.12|\?\? target/linux/generic/hack-6\.12/299-add-wext-kconfig\.patch)?$' \
  > "$SOURCE/wext-only-unexpected-kernel-status.txt" || true
test ! -s "$SOURCE/wext-only-unexpected-kernel-status.txt"

git -C "$SOURCE" diff --quiet -- target/linux/mediatek
test "$(git -C "$SOURCE" diff --name-only -- target/linux/mediatek | wc -l)" -eq 0
test -f "$SOURCE/$WEXT_PATCH"
! grep -Eq 'LIB80211' "$SOURCE/$WEXT_PATCH"

echo 'WEXT-only recovery control config: official release kernel sidecar + five WEXT symbols only'
