#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"
DONOR="${2:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"
BUILDER="${3:?usage: prepare-hwaccel-56.sh <official-prepared-source> <6.12-donor> <builder-root>}"

# #56 is deliberately a narrow overlay on top of the proven #55 tree.
# It MUST NOT replace target/linux/mediatek, Ethernet, DSA, PHY, switch or PPE.
# Restore only the vendor HNAT/WARP pieces and their minimum Linux 6.12 hooks.

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

# 1) Linux-6.12 donor WARP package only. Its current 20250408 archive keeps the
# same 5f71ec driver source revision as the previous 20231229 archive; the SDK
# update changed firmware/util binaries, not the WARP driver API.
rm -rf "$WARP_DST"
mkdir -p "$(dirname "$WARP_DST")"
rsync -a "$WARP_SRC/" "$WARP_DST/"
test -f "$WARP_DST/Makefile"
grep -q '^PKG_SOURCE:=warp_20250408-5f71ec.tar.xz$' "$WARP_DST/Makefile"

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

# 4) Package mtkhnat.ko without replacing the official netdevices.mk. Keep the
# donor's module-style KCONFIG exactly: do NOT force NET_MEDIATEK_HNAT=y or the
# expected mtkhnat.ko would become inconsistent with the package FILES entry.
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
  TITLE:=Mediatek HNAT module
  DEPENDS:=@TARGET_mediatek +kmod-nf-conntrack
  KCONFIG:= \
	CONFIG_BRIDGE_NETFILTER=y \
	CONFIG_NETFILTER_FAMILY_BRIDGE=y \
	CONFIG_NET_MEDIATEK_HNAT
  FILES:= \
        $(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
endef

define KernelPackage/mediatek_hnat/description
  Kernel modules for MediaTek HW NAT offloading
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

# 6) Board-local DTS bridge for vendor HNAT/WARP. The standard N60 Pro
# Ethernet/DSA/PHY definitions are not replaced. Existing upstream WED/WO
# nodes retain their official compatible strings as fallbacks, while the
# vendor strings/resources required by WARP are added only on this board.
python3 - "$DTS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
marker = 'N60PRO_HWACCEL_56_DTS_BEGIN'
if marker in s:
    raise SystemExit('hardware-accel DTS marker already present; refusing ambiguous reapply')
s += r'''

/* N60PRO_HWACCEL_56_DTS_BEGIN
 * Board-local vendor HNAT/WARP bridge. Keep the official N60 Pro Ethernet,
 * DSA, PHY and shared mt7986a platform baseline intact.
 */
/ {
	hnat: hnat@15000000 {
		compatible = "mediatek,mtk-hnat_v4";
		reg = <0 0x15100000 0 0x80000>;
		resets = <&ethsys 0>;
		reset-names = "mtketh";
		mtketh-soc = <&eth>;
		mtketh-wan = "eth1";
		mtketh-lan = "lan";
		mtketh-max-gmac = <2>;
		status = "okay";
	};
};

/* WARP 5f71ec expects a combined WDMA node and indexes resource 0/1. */
&{/soc} {
	warp_wdma: wdma@15104800 {
		compatible = "mediatek,wed-wdma";
		reg = <0 0x15104800 0 0x400>,
		      <0 0x15104c00 0 0x400>;
	};
};

/* Keep official WED compatibles as fallbacks while exposing the proprietary
 * names and two-resource/two-IRQ layout required by mtk_warp. */
&wed0 {
	compatible = "mediatek,wed", "mediatek,mt7986-wed", "syscon";
	wed_num = <2>;
	pci_slot_map = <0>, <1>;
	reg = <0 0x15010000 0 0x1000>,
	      <0 0x15011000 0 0x1000>;
	interrupts = <GIC_SPI 205 IRQ_TYPE_LEVEL_HIGH>,
	             <GIC_SPI 206 IRQ_TYPE_LEVEL_HIGH>;
};

&wed1 {
	compatible = "mediatek,wed2", "mediatek,mt7986-wed", "syscon";
	reg = <0 0x15010000 0 0x1000>,
	      <0 0x15011000 0 0x1000>;
	interrupts = <GIC_SPI 205 IRQ_TYPE_LEVEL_HIGH>,
	             <GIC_SPI 206 IRQ_TYPE_LEVEL_HIGH>;
};

/* WARP searches this exact compatible for the PCIe interrupt bridge. */
&wed_pcie {
	compatible = "mediatek,wed_pcie", "mediatek,mt7986-wed-pcie", "syscon";
};

/* Reuse the upstream reserved-memory/WO nodes, adding only the vendor aliases
 * WARP looks up with of_find_compatible_node(). */
&wo_emi0 {
	compatible = "mediatek,wocpu0_emi";
	shared = <0>;
};

&wo_emi1 {
	compatible = "mediatek,wocpu1_emi";
	shared = <0>;
};

&wo_data {
	compatible = "mediatek,wocpu_data";
	shared = <1>;
};

&wo_ilm0 {
	compatible = "mediatek,wocpu0_ilm", "mediatek,mt7986-wo-ilm", "syscon";
};

&wo_ilm1 {
	compatible = "mediatek,wocpu1_ilm", "mediatek,mt7986-wo-ilm", "syscon";
};

/* WARP indexes DLM resource 0/1 from one compatible node. */
&wo_dlm0 {
	compatible = "mediatek,wocpu_dlm", "mediatek,mt7986-wo-dlm", "syscon";
	reg = <0 0x151e8000 0 0x2000>,
	      <0 0x151f8000 0 0x2000>;
};

&wo_cpuboot {
	compatible = "mediatek,wocpu_boot", "mediatek,mt7986-wo-cpuboot", "syscon";
};

/* WARP CCIF likewise indexes resource/IRQ 0/1 from a single node. */
&wo_ccif0 {
	compatible = "mediatek,ap2woccif", "mediatek,mt7986-wo-ccif", "syscon";
	reg = <0 0x151a5000 0 0x1000>,
	      <0 0x151ad000 0 0x1000>;
	interrupts = <GIC_SPI 211 IRQ_TYPE_LEVEL_HIGH>,
	             <GIC_SPI 212 IRQ_TYPE_LEVEL_HIGH>;
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
grep -q '^[[:space:]]*CONFIG_NET_MEDIATEK_HNAT$' "$NETDEVICES"
! grep -q 'CONFIG_NET_MEDIATEK_HNAT=y' "$NETDEVICES"
grep -q 'N60PRO_HWACCEL_56_DTS_BEGIN' "$DTS"
grep -q 'compatible = "mediatek,mtk-hnat_v4";' "$DTS"
grep -q 'mtketh-soc = <&eth>;' "$DTS"
! grep -q 'mtketh-soc = "mt7986"' "$DTS"
grep -q 'compatible = "mediatek,wed", "mediatek,mt7986-wed", "syscon";' "$DTS"
grep -q 'compatible = "mediatek,wed2", "mediatek,mt7986-wed", "syscon";' "$DTS"
grep -q 'wed_num = <2>;' "$DTS"
grep -q 'pci_slot_map = <0>, <1>;' "$DTS"
grep -q 'compatible = "mediatek,wed-wdma";' "$DTS"
grep -q 'compatible = "mediatek,ap2woccif", "mediatek,mt7986-wo-ccif", "syscon";' "$DTS"
grep -q 'compatible = "mediatek,wocpu0_emi";' "$DTS"
grep -q 'compatible = "mediatek,wocpu1_emi";' "$DTS"
grep -q 'compatible = "mediatek,wocpu_data";' "$DTS"
grep -q 'compatible = "mediatek,wocpu_dlm", "mediatek,mt7986-wo-dlm", "syscon";' "$DTS"
grep -q 'mediatek,mtd-eeprom = <&factory 0x0>;' "$DTS"
grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"

# Explicitly reject the old failure mode: this script contains no broad target copy.
! grep -Eq 'rsync .*target/linux/mediatek/?[" ]' "$0"

echo 'prepare hardware acceleration #56: OK'
