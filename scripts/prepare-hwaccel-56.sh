#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"
DONOR="${2:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"
BUILDER="${3:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"

# #56 is deliberately a narrow overlay on top of the proven #55 tree.
# It MUST NOT replace target/linux/mediatek, Ethernet, DSA, PHY, switch or PPE.
# Restore only the vendor HNAT/WARP pieces and their minimum 6.12 hooks.

MT_WIFI="$SOURCE/package/mtk/drivers/mt_wifi"
MT_WIFI_MAKEFILE="$MT_WIFI/Makefile"
WARP_SRC="$DONOR/package/mtk/drivers/warp"
WARP_DST="$SOURCE/package/mtk/drivers/warp"
HNAT_SRC="$DONOR/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat"
HNAT_DST="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat"
PATCH_DIR="$SOURCE/target/linux/mediatek/patches-6.12"
NETDEVICES="$SOURCE/package/kernel/linux/modules/netdevices.mk"
DTS="$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"
DRIVER_UC="$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"

for f in "$MT_WIFI_MAKEFILE" "$NETDEVICES" "$DTS" "$DRIVER_UC"; do
  test -f "$f" || { echo "missing #55 prepared file: $f" >&2; exit 1; }
done
test -d "$WARP_SRC"
test -d "$HNAT_SRC"

# Hard gate: #55 RF / storage / module-order baseline must still be present.
grep -qx 'PKG_VERSION:=7.6.6.1' "$MT_WIFI_MAKEFILE"
grep -Fqx '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)' "$MT_WIFI_MAKEFILE"
grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"
grep -q 'mediatek,mtd-eeprom = <&factory 0x0>;' "$DTS"

# 1) Vendor WARP package only. No other donor package/target tree is copied.
rm -rf "$WARP_DST"
mkdir -p "$(dirname "$WARP_DST")"
rsync -a "$WARP_SRC/" "$WARP_DST/"
test -f "$WARP_DST/Makefile"

# 2) Vendor HNAT driver only.
rm -rf "$HNAT_DST"
mkdir -p "$(dirname "$HNAT_DST")"
rsync -a "$HNAT_SRC/" "$HNAT_DST/"
test -f "$HNAT_DST/Makefile"
test -f "$HNAT_DST/hnat.c"
test -f "$HNAT_DST/nf_hnat_mtk.h"

# 3) Minimum Linux 6.12 Ethernet hooks required by the standalone HNAT module.
for patch in \
  999-eth-91-mtk_eth_soc-add-mtkhnat-driver-support.patch \
  999-zzz-5101-net-ethernet-mtk_eth_soc-mtkhnat-add-hnat-skb-magic-check.patch; do
  src="$DONOR/target/linux/mediatek/patches-6.12/$patch"
  dst="$PATCH_DIR/$patch"
  test -f "$src"
  install -m0644 "$src" "$dst"
done

# 4) Package mtkhnat.ko without replacing the official netdevices.mk.
python3 - "$NETDEVICES" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
begin = '# N60PRO_HWACCEL_56_HNAT_BEGIN\n'
end = '# N60PRO_HWACCEL_56_HNAT_END\n'
block = r'''# N60PRO_HWACCEL_56_HNAT_BEGIN
define KernelPackage/mediatek_hnat
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=MediaTek hardware NAT support
  KCONFIG:= \
    CONFIG_BRIDGE_NETFILTER=y \
    CONFIG_NET_MEDIATEK_HNAT=y \
    CONFIG_NETFILTER_FAMILY_BRIDGE=y \
    CONFIG_NETFILTER_NETLINK_GLUE_CT=y \
    CONFIG_NETFILTER_NETLINK_GLUE_CT_TIMEOUT=y \
    CONFIG_NETFILTER_XT_MARK=y \
    CONFIG_NF_FLOW_TABLE_INET=y \
    CONFIG_NF_FLOW_TABLE_IPV4=y \
    CONFIG_NF_FLOW_TABLE_IPV6=y \
    CONFIG_NF_NAT=y
  DEPENDS:=@TARGET_mediatek +kmod-ipt-raw +kmod-ipt-conntrack +kmod-ipt-nat +kmod-nf-conntrack-netlink +kmod-nf-flow +kmod-nf-flow6
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
  AUTOLOAD:=$(call AutoLoad,30,mtkhnat)
endef

define KernelPackage/mediatek_hnat/description
 MediaTek hardware NAT offload driver used by the proprietary Wi-Fi/WARP path.
endef

$(eval $(call KernelPackage,mediatek_hnat))
# N60PRO_HWACCEL_56_HNAT_END
'''
if begin in s or end in s:
    raise SystemExit('HNAT package marker already present; refusing ambiguous reapply')
p.write_text(s.rstrip() + '\n\n' + block)
PY

# 5) Restore only the mt_wifi HNAT/WARP dependencies stripped by #55.
# Keep #55's proven mt_wifi AutoLoad=11 and all RF/EEPROM edits intact.
python3 - "$MT_WIFI_MAKEFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
repls = [
    ('PKG_VERSION:=7.6.6.1\n',
     'PKG_BUILD_DEPENDS:=warp\nPKG_VERSION:=7.6.6.1\n'),
    ('  DEPENDS:=+wifi-dats\n  DEPENDS+=+kmod-conninfra\n',
     '  DEPENDS:=+wifi-dats\n  DEPENDS+=+kmod-conninfra\n  DEPENDS+=+kmod-mediatek_hnat\n'),
    ('  FILES:=$(PKG_BUILD_DIR)/mt_wifi_ap/mt_wifi.ko\n  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)\n',
     '  FILES:=$(PKG_BUILD_DIR)/mt_wifi_ap/mt_wifi.ko \\\n\t$(PKG_BUILD_DIR)/mt_wifi/embedded/plug_in/warp_proxy/mtk_warp_proxy.ko\n  DEPENDS+=+kmod-warp\n  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)\n'),
]
for old, new in repls:
    if s.count(old) != 1:
        raise SystemExit(f'mt_wifi #55 anchor count != 1: {old!r}: {s.count(old)}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

# Golden 7.6.6.1 already contains the external-WARP compatibility patch and
# the proxy/whnat source. Do not substitute a different mt_wifi host tree.
test -f "$MT_WIFI/patches/005-use-ext-warp-code.patch"
test -d "$MT_WIFI/src/mt_wifi/embedded/plug_in/warp_proxy"
test -d "$MT_WIFI/src/mt_wifi/embedded/plug_in/whnat"

# Restore the vendor driver's WARP reload chain. This changes userspace module
# reload order only; mt_wifi's boot AutoLoad remains the proven #55 value 11.
python3 - "$DRIVER_UC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'const DRIVERS = ["mt_wifi"];\n'
new = 'const DRIVERS = ["mtk_warp_proxy", "mtk_warp", "mt_wifi"];\n'
if s.count(old) != 1:
    raise SystemExit(f'mtwifi #55 driver list anchor count != 1: {s.count(old)}')
p.write_text(s.replace(old, new, 1))
PY

# 6) N60-Pro-local HNAT platform node. Do not modify shared mt7986a.dtsi.
python3 - "$DTS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
marker = 'N60PRO_HWACCEL_56_DTS_BEGIN'
if marker in s:
    raise SystemExit('HNAT DTS marker already present; refusing ambiguous reapply')
s += r'''

/* N60PRO_HWACCEL_56_DTS_BEGIN
 * Board-local vendor HNAT node. Official Ethernet/DSA/PHY nodes stay untouched.
 */
/ {
	hnat: hnat@15100000 {
		compatible = "mediatek,mtk-hnat_v4";
		reg = <0 0x15100000 0 0x80000>;
		resets = <&ethsys 0>;
		reset-names = "mtketh";
		mtketh-ppd = "eth0";
		mtketh-wan = "eth1";
		mtketh-lan = "lan";
		mtketh-max-gmac = <2>;
		mtketh-soc = "mt7986";
		status = "okay";
	};
};
/* N60PRO_HWACCEL_56_DTS_END */
'''
p.write_text(s)
PY

# Final static guards: minimum overlay present, stable #55 invariants unchanged.
test -d "$WARP_DST"
test -d "$HNAT_DST"
grep -q '^PKG_BUILD_DEPENDS:=warp$' "$MT_WIFI_MAKEFILE"
grep -q 'kmod-mediatek_hnat' "$MT_WIFI_MAKEFILE"
grep -q 'kmod-warp' "$MT_WIFI_MAKEFILE"
grep -q 'mtk_warp_proxy\.ko' "$MT_WIFI_MAKEFILE"
grep -Fqx '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)' "$MT_WIFI_MAKEFILE"
grep -Fqx 'const DRIVERS = ["mtk_warp_proxy", "mtk_warp", "mt_wifi"];' "$DRIVER_UC"
grep -q 'N60PRO_HWACCEL_56_HNAT_BEGIN' "$NETDEVICES"
grep -q 'N60PRO_HWACCEL_56_DTS_BEGIN' "$DTS"
grep -q 'compatible = "mediatek,mtk-hnat_v4";' "$DTS"
grep -q 'mediatek,mtd-eeprom = <&factory 0x0>;' "$DTS"
grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"

# Explicitly reject the old failure mode: this script contains no broad target copy.
! grep -Eq 'rsync .*target/linux/mediatek/?[" ]' "$0"

echo 'prepare hardware acceleration #56: OK'
