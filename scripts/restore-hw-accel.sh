#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: restore-hw-accel.sh <official-source> <mtk-donor> [builder-root]}"
DONOR="${2:?usage: restore-hw-accel.sh <official-source> <mtk-donor> [builder-root]}"
BUILDER="${3:-$(dirname "$SOURCE")}" 
EXPECTED_DONOR="eb724bb94de346f36b35bdb0f7de31b529bbc885"

# #50 RF/Wi-Fi is frozen. This script restores only the acceleration sidecar
# from the already pinned Linux 6.12 donor: HNAT -> WARP -> mtk_warp_proxy -> mt_wifi.
test -d "$SOURCE"
test -d "$DONOR/.git"
test "$(git -C "$DONOR" rev-parse HEAD)" = "$EXPECTED_DONOR"

# 1) Restore the donor's WARP package verbatim. prepare.sh intentionally omitted
# it during RF isolation; do not import any unrelated MTK package tree.
WARP_SRC="$DONOR/package/mtk/drivers/warp"
WARP_DST="$SOURCE/package/mtk/drivers/warp"
test -f "$WARP_SRC/Makefile"
rm -rf "$WARP_DST"
mkdir -p "$(dirname "$WARP_DST")"
rsync -a "$WARP_SRC/" "$WARP_DST/"

# 2) Restore only the vendor HNAT kernel sidecar and its pinned 6.12 patches.
HNAT_SRC="$DONOR/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat"
HNAT_DST="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat"
test -f "$HNAT_SRC/Makefile"
rm -rf "$HNAT_DST"
mkdir -p "$(dirname "$HNAT_DST")"
rsync -a "$HNAT_SRC/" "$HNAT_DST/"

PATCH_SRC="$DONOR/target/linux/mediatek/patches-6.12"
PATCH_DST="$SOURCE/target/linux/mediatek/patches-6.12"
mkdir -p "$PATCH_DST"
ETH_HNAT_PATCH="$PATCH_SRC/999-eth-91-mtk_eth_soc-add-mtkhnat-driver-support.patch"
test -f "$ETH_HNAT_PATCH"
install -m0644 "$ETH_HNAT_PATCH" "$PATCH_DST/$(basename "$ETH_HNAT_PATCH")"

shopt -s nullglob
hnat_patches=("$PATCH_SRC"/999-hnat-*.patch)
((${#hnat_patches[@]} > 0))
for patch in "${hnat_patches[@]}"; do
  install -m0644 "$patch" "$PATCH_DST/$(basename "$patch")"
done
shopt -u nullglob

# 3) Import only the mediatek_hnat package definition from the pinned donor's
# netdevices.mk. Never replace the complete official netdevices.mk.
DONOR_NETDEV="$DONOR/package/kernel/linux/modules/netdevices.mk"
SOURCE_NETDEV="$SOURCE/package/kernel/linux/modules/netdevices.mk"
test -f "$DONOR_NETDEV"
test -f "$SOURCE_NETDEV"
python3 - "$DONOR_NETDEV" "$SOURCE_NETDEV" <<'PY'
from pathlib import Path
import sys

donor = Path(sys.argv[1]).read_text()
dst_path = Path(sys.argv[2])
dst = dst_path.read_text()
start_mark = "define KernelPackage/mediatek_hnat\n"
end_mark = "$(eval $(call KernelPackage,mediatek_hnat))"
start = donor.find(start_mark)
if start < 0:
    raise SystemExit("pinned donor has no KernelPackage/mediatek_hnat")
end = donor.find(end_mark, start)
if end < 0:
    raise SystemExit("pinned donor mediatek_hnat eval marker missing")
end += len(end_mark)
block = donor[start:end].rstrip() + "\n"

old_start = dst.find(start_mark)
if old_start >= 0:
    old_end = dst.find(end_mark, old_start)
    if old_end < 0:
        raise SystemExit("destination has incomplete mediatek_hnat block")
    old_end += len(end_mark)
    dst = dst[:old_start] + block.rstrip() + dst[old_end:]
else:
    dst = dst.rstrip() + "\n\n" + block

if dst.count(start_mark) != 1 or dst.count(end_mark) != 1:
    raise SystemExit("mediatek_hnat package block count is not exactly one")
dst_path.write_text(dst)
PY

# 4) Restore the untouched Golden 7.6.6.1 mt_wifi packaging so the proxy is
# built and loaded again. The RF sources/firmware/6.12 compatibility patches
# remain exactly the #50 Golden enclave; only its Makefile is restored.
GOLDEN_MK="$BUILDER/.golden-mt_wifi-exact/package/mtk/drivers/mt_wifi/Makefile"
MT_WIFI_MK="$SOURCE/package/mtk/drivers/mt_wifi/Makefile"
test -f "$GOLDEN_MK"
install -m0644 "$GOLDEN_MK" "$MT_WIFI_MK"
python3 - "$MT_WIFI_MK" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "PKG_VERSION:=7.6.6.1-$(PKG_SUFFIX)\n"
new = "PKG_VERSION:=7.6.6.1\n"
if s.count(old) != 1:
    raise SystemExit(f"Golden mt_wifi PKG_VERSION pattern count != 1: {s.count(old)}")
p.write_text(s.replace(old, new, 1))
PY

# Restore the donor ucode driver load order removed for RF isolation.
DRIVER_UC_SRC="$DONOR/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"
DRIVER_UC_DST="$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"
test -f "$DRIVER_UC_SRC"
install -m0644 "$DRIVER_UC_SRC" "$DRIVER_UC_DST"

# Static build gates: prove the complete glue chain exists and that no broad
# Ethernet/DSA tree was imported.
grep -q '^PKG_BUILD_DEPENDS:=warp' "$MT_WIFI_MK"
grep -q '+kmod-mediatek_hnat' "$MT_WIFI_MK"
grep -q '+kmod-warp' "$MT_WIFI_MK"
grep -q 'mtk_warp_proxy\.ko' "$MT_WIFI_MK"
grep -Eq 'AutoProbe,mt_wifi mtk_warp_proxy|AutoLoad,[^,]+,mt_wifi mtk_warp_proxy' "$MT_WIFI_MK"
grep -Fqx 'const DRIVERS = ["mtk_warp_proxy", "mtk_warp", "mt_wifi"];' "$DRIVER_UC_DST"
grep -q 'define KernelPackage/mediatek_hnat' "$SOURCE_NETDEV"
test -f "$PATCH_DST/999-eth-91-mtk_eth_soc-add-mtkhnat-driver-support.patch"
test -f "$HNAT_DST/Makefile"
test -f "$WARP_DST/Makefile"

echo "MediaTek hardware acceleration sidecar restored: HNAT -> WARP -> mtk_warp_proxy -> mt_wifi"
