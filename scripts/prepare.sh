#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
DONOR="${2:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
BUILDER="${3:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"

# Official ImmortalWrt 25.12.1 stays the platform/kernel baseline. Import only
# the proprietary MTK Wi-Fi userspace/out-of-tree modules required by N60 Pro.
rm -rf "$SOURCE/package/mtk"
for rel in \
  drivers/conninfra \
  drivers/mt_wifi \
  drivers/wifi-profile \
  applications/datconf \
  applications/l1parser \
  applications/mtwifi-cfg-ucode \
  applications/luci-app-mtwifi-cfg; do
  mkdir -p "$SOURCE/package/mtk/$(dirname "$rel")"
  rsync -a "$DONOR/package/mtk/$rel/" "$SOURCE/package/mtk/$rel/"
done

for rel in \
  package/network/utils/iwinfo \
  package/network/utils/iwinfo-ucode; do
  rm -rf "$SOURCE/$rel"
  mkdir -p "$(dirname "$SOURCE/$rel")"
  rsync -a "$DONOR/$rel/" "$SOURCE/$rel/"
done

# 当前诊断阶段暂不引入 donor WARP/HNAT；最终产品需要保留/恢复硬件加速能力。
# Keep official Ethernet,
# DSA, PHY, WED and PPE untouched.
MT_WIFI_MAKEFILE="$SOURCE/package/mtk/drivers/mt_wifi/Makefile"
python3 - "$MT_WIFI_MAKEFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
replacements = [
    ("PKG_BUILD_DEPENDS:=warp\n", ""),
    ("  DEPENDS:=+wifi-dats +kmod-conninfra +kmod-mediatek_hnat +kmod-warp\n",
     "  DEPENDS:=+wifi-dats +kmod-conninfra\n"),
    ("  FILES:=$(PKG_BUILD_DIR)/mt_wifi_ap/mt_wifi.ko \\\n\t$(PKG_BUILD_DIR)/mt_wifi/embedded/plug_in/warp_proxy/mtk_warp_proxy.ko\n",
     "  FILES:=$(PKG_BUILD_DIR)/mt_wifi_ap/mt_wifi.ko\n"),
    ("  AUTOLOAD:=$(call AutoProbe,mt_wifi mtk_warp_proxy)\n",
     "  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)\n"),
]
for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit(f'mt_wifi Makefile pattern count != 1: {old!r}: {s.count(old)}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

MTWIFI_UCODE_MAKEFILE="$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/Makefile"
python3 - "$MTWIFI_UCODE_MAKEFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "  DEPENDS:=$(UCODE_DEPENDS) +wifi-scripts +iwinfo-ucode\n"
new = "  DEPENDS:=$(UCODE_DEPENDS) +wifi-scripts +iwinfo-ucode +wireless-tools\n"
if s.count(old) != 1:
    raise SystemExit(f'mtwifi-cfg-ucode DEPENDS pattern count != 1: {s.count(old)}')
p.write_text(s.replace(old, new, 1))
PY

MTWIFI_DRIVER_UC="$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"
python3 - "$MTWIFI_DRIVER_UC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'const DRIVERS = ["mtk_warp_proxy", "mtk_warp", "mt_wifi"];\n'
new = 'const DRIVERS = ["mt_wifi"];\n'
if s.count(old) != 1:
    raise SystemExit(f'mtwifi driver list pattern count != 1: {s.count(old)}')
p.write_text(s.replace(old, new, 1))
PY

MT_WIFI_CONFIG_IN="$SOURCE/package/mtk/drivers/mt_wifi/config.in"
python3 - "$MT_WIFI_CONFIG_IN" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = """config  MTK_RT_FIRST_IF_RF_OFFSET
        hex
        depends on ! MTK_FIRST_IF_NONE
        default 0xc0000
"""
new = """config  MTK_RT_FIRST_IF_RF_OFFSET
        hex
        depends on ! MTK_FIRST_IF_NONE
        default 0x0 if MTK_FIRST_IF_MT7986
        default 0xc0000
"""
if s.count(old) != 1:
    raise SystemExit(f'MTK_RT_FIRST_IF_RF_OFFSET config.in pattern count != 1: {s.count(old)}')
p.write_text(s.replace(old, new, 1))
PY

python3 - "$MT_WIFI_CONFIG_IN" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old_choice = """\tconfig MTK_MT_WIFI_MT7986_20260601
\tbool \"mt7986-fw-20260601\"
endchoice
"""
new_choice = """\tconfig MTK_MT_WIFI_MT7986_20260601
\tbool \"mt7986-fw-20260601\"

\tconfig MTK_MT_WIFI_MT7986_GOLDEN_7661
\tbool \"mt7986-fw-golden-7661\"
endchoice
"""
old_path = """\tdefault mt7986-fw-20250408 if MTK_MT_WIFI_MT7986_20250408
\tdefault mt7986-fw-20260601 if MTK_MT_WIFI_MT7986_20260601
"""
new_path = """\tdefault mt7986-fw-20250408 if MTK_MT_WIFI_MT7986_20250408
\tdefault mt7986-fw-20260601 if MTK_MT_WIFI_MT7986_20260601
\tdefault mt7986-fw-golden-7661 if MTK_MT_WIFI_MT7986_GOLDEN_7661
"""
for old, new, name in (
    (old_choice, new_choice, "MT7986 golden firmware choice"),
    (old_path, new_path, "MT7986 golden firmware path"),
):
    if s.count(old) != 1:
        raise SystemExit(f'{name} pattern count != 1: {s.count(old)}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

GOLDEN_FW_COMMIT="4c657c93546c86cd9f9d83cd5931b5056e652dbb"
GOLDEN_FW_DIR="$SOURCE/package/mtk/drivers/mt_wifi/files/mt7986-fw-golden-7661"
GOLDEN_FW_BASE="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/${GOLDEN_FW_COMMIT}/package/mtk/drivers/mt_wifi/src/bin/mt7986/rebb"
rm -rf "$GOLDEN_FW_DIR"
mkdir -p "$GOLDEN_FW_DIR"
for f in \
  7986_WACPU_RAM_CODE_release.bin \
  WIFI_RAM_CODE_MT7986.bin \
  WIFI_RAM_CODE_MT7986_MT7975.bin \
  mt7986_patch_e1_hdr.bin \
  mt7986_patch_e1_hdr_mt7975.bin; do
  curl -fL --retry 5 --retry-delay 5 -o "$GOLDEN_FW_DIR/$f" "$GOLDEN_FW_BASE/$f"
done
(cd "$GOLDEN_FW_DIR" && sha256sum -c - <<'EOF'
0237b7a6376d9f477d18cc54ffef153444098643d72b55942401cedbb6955c6a  7986_WACPU_RAM_CODE_release.bin
d473692bb6856370cda487db9264a0eeb63af60e76c4dac23cc9bb90211e6bbb  WIFI_RAM_CODE_MT7986.bin
3717fb957f3e4f1acdd2d8cc613c309345d189a2e341b00c904ade67a6092bd3  WIFI_RAM_CODE_MT7986_MT7975.bin
2f593cf19b2b6b50c963bd94c8d5a3838e3d9681527c200f496e4899a3144237  mt7986_patch_e1_hdr.bin
0a1492b0d36a31556bbf951ab1ff3e7d372a5e50866f0efd12e9908cacc793c1  mt7986_patch_e1_hdr_mt7975.bin
EOF
)
test "$(find "$GOLDEN_FW_DIR" -mindepth 1 -maxdepth 1 -print | wc -l)" = 5
for f in \
  7986_WACPU_RAM_CODE_release.bin \
  WIFI_RAM_CODE_MT7986.bin \
  WIFI_RAM_CODE_MT7986_MT7975.bin \
  mt7986_patch_e1_hdr.bin \
  mt7986_patch_e1_hdr_mt7975.bin; do
  test -f "$GOLDEN_FW_DIR/$f"
done
test ! -e "$GOLDEN_FW_DIR/SHA256SUMS"

# Legacy WEXT is the only intentional change to the official built-in wireless
# kernel code. The proprietary driver still needs these hidden 6.12 symbols.
WEXT_PATCH_DST="$SOURCE/target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
mkdir -p "$(dirname "$WEXT_PATCH_DST")"
sed -e 's/@TAB@/\t/g' -e 's/^ @EMPTY@$/ /' > "$WEXT_PATCH_DST" <<'PATCH'
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
grep -Eq 'WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY' "$WEXT_PATCH_DST"
! grep -Eq 'LIB80211' "$WEXT_PATCH_DST"
GENERIC_CONFIG="$SOURCE/target/linux/generic/config-6.12"
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  if grep -qx "# CONFIG_${sym} is not set" "$GENERIC_CONFIG"; then
    sed -i "s/^# CONFIG_${sym} is not set$/CONFIG_${sym}=y/" "$GENERIC_CONFIG"
  elif ! grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"; then
    echo "CONFIG_${sym}=y" >> "$GENERIC_CONFIG"
  fi
done

# wifi_utility used to be obj-y in #22. That changed vmlinux and is now removed.
# Keep the donor EEPROM/RBUS code, but build all four objects as one loadable kmod
# before conninfra/mt_wifi. 5200 (parent obj-y hook) is deliberately NOT imported.
WIFI_UTILITY_SRC="$DONOR/target/linux/mediatek/files-6.12/drivers/net/wireless/wifi_utility"
WIFI_UTILITY_DST="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/wireless/wifi_utility"
test -d "$WIFI_UTILITY_SRC"
mkdir -p "$(dirname "$WIFI_UTILITY_DST")"
rm -rf "$WIFI_UTILITY_DST"
rsync -a "$WIFI_UTILITY_SRC/" "$WIFI_UTILITY_DST/"

for patch in \
  999-zzz-5202-mtk-wifi_utility-since-v6.11-fix-rbus_remove-return-type.patch \
  999-zzz-5203-mtk-wifi_utility-add-universal-eeprom-read-write-backend.patch; do
  src="$DONOR/target/linux/mediatek/patches-6.12/$patch"
  dst="$SOURCE/target/linux/mediatek/patches-6.12/$patch"
  test -f "$src"
  install -m0644 "$src" "$dst"
done

# After donor 5203 adds mt_wifi_of/eeprom, build the helper as an unconditional
# kernel MODULE. It participates in the normal kernel modules pass/Module.symvers,
# but is never linked into vmlinux.
cat > "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch" <<'PATCH'
--- a/drivers/net/wireless/Makefile
+++ b/drivers/net/wireless/Makefile
@@ -11,6 +11,7 @@ obj-$(CONFIG_WLAN_VENDOR_INTEL) += intel
 obj-$(CONFIG_WLAN_VENDOR_INTERSIL) += intersil/
 obj-$(CONFIG_WLAN_VENDOR_MARVELL) += marvell/
 obj-$(CONFIG_WLAN_VENDOR_MEDIATEK) += mediatek/
+obj-m += wifi_utility/
 obj-$(CONFIG_WLAN_VENDOR_MICROCHIP) += microchip/
 obj-$(CONFIG_WLAN_VENDOR_PURELIFI) += purelifi/
 obj-$(CONFIG_WLAN_VENDOR_QUANTENNA) += quantenna/
--- a/drivers/net/wireless/wifi_utility/Makefile
+++ b/drivers/net/wireless/wifi_utility/Makefile
@@ -1,6 +1,2 @@
-#always build-in
-obj-y += mt_wifi_mtd.o
-obj-y += mt_wifi_of.o
-obj-y += mt_wifi_eeprom.o
-obj-y += pci_mediatek_rbus.o
-
+obj-m += mtk_wifi_utility.o
+mtk_wifi_utility-y := mt_wifi_mtd.o mt_wifi_of.o mt_wifi_eeprom.o pci_mediatek_rbus.o
PATCH
python3 - "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch" <<'PY'
from pathlib import Path
import sys

patch = Path(sys.argv[1])
patch.write_text(patch.read_text() + (
    "--- a/drivers/net/wireless/wifi_utility/pci_mediatek_rbus.c\n"
    "+++ b/drivers/net/wireless/wifi_utility/pci_mediatek_rbus.c\n"
    "@@ -293,6 +293,7 @@ static int rbus_probe(struct platform_device *pdev)\n"
    " {\n"
    " \tstruct device_node *node = NULL;\n"
    " \tstruct rbus_dev *rbus;\n"
    "+\tint ret;\n"
    " \n"
    " \tnode = of_find_compatible_node(NULL, NULL, OF_RBUS_NAME);\n"
    " \tif (!node)\n"
    "@@ -318,8 +319,11 @@ static int rbus_probe(struct platform_device *pdev)\n"
    " \t/*init config, need run before add port*/\n"
    " \trbus_init_config(rbus);\n"
    " \t/*add pci bus & device*/\n"
    "-\trbus_add_port(rbus, pdev);\n"
    "-\treturn -ENODEV;\n"
    "+\tret = rbus_add_port(rbus, pdev);\n"
    "+\tif (ret)\n"
    "+\t\treturn ret;\n"
    "+\n"
    "+\treturn 0;\n"
    " }\n"
    " \n"
    " /*\n"
))
PY

# Package the module produced by the kernel's normal modules pass.
WIFI_PKG="$SOURCE/package/mtk/drivers/wifi_utility"
mkdir -p "$WIFI_PKG"
cat > "$WIFI_PKG/Makefile" <<'MAKE'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=mt-wifi-utility
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define KernelPackage/mt-wifi-utility
  CATEGORY:=MTK Properties
  SUBMENU:=Drivers
  TITLE:=MediaTek proprietary WiFi EEPROM/RBUS utility
  FILES:=$(LINUX_DIR)/drivers/net/wireless/wifi_utility/mtk_wifi_utility.ko
  AUTOLOAD:=$(call AutoLoad,09,mtk_wifi_utility,1)
endef

define KernelPackage/mt-wifi-utility/description
 MediaTek EEPROM and RBUS compatibility helpers required by proprietary mt_wifi.
endef

define Build/Prepare
	true
endef

define Build/Compile
	true
endef

$(eval $(call KernelPackage,mt-wifi-utility))
MAKE

# conninfra references the EEPROM helper symbols, so force utility module first.
CONNINFRA_MAKEFILE="$SOURCE/package/mtk/drivers/conninfra/Makefile"
python3 - "$CONNINFRA_MAKEFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
anchor = "\tTITLE:= Conninfra driver\n"
insert = anchor + "\tDEPENDS:=+kmod-mt-wifi-utility\n"
if s.count(anchor) != 1:
    raise SystemExit(f'conninfra TITLE anchor count != 1: {s.count(anchor)}')
s = s.replace(anchor, insert, 1)
p.write_text(s)
PY

# Exact 237 MT7986 radio data only; no 237/donor Linux platform tree.
PROFILE_DIR="$SOURCE/package/mtk/drivers/wifi-profile/files/mt7986"
RADIO_COMMIT="${RADIO_COMMIT:-ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8}"
PROFILE_BASE="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/${RADIO_COMMIT}/package/mtk/drivers/wifi-profile/files/mt7986"
mkdir -p "$PROFILE_DIR"
for f in \
  l1profile.dat \
  mt7986-ax6000.dbdc.b0.dat \
  mt7986-ax6000.dbdc.b1.dat \
  mt7986-sku.dat \
  mt7986-sku-bf.dat; do
  curl -fL --retry 5 --retry-delay 2 "$PROFILE_BASE/$f" -o "$PROFILE_DIR/$f"
done

# Hardware-only DTS adaptation plus the minimum proprietary Wi-Fi bindings.
# Do not import donor Ethernet/WED/PPE/PHY DTS changes.
DTS="$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"
python3 - "$DTS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old_mem = 'reg = <0 0x40000000 0 0x20000000>;'
new_mem = 'reg = <0 0x40000000 0 0x80000000>;'
old_ubi = 'reg = <0x0580000 0x7a80000>;'
new_ubi = 'reg = <0x0580000 0x1fa80000>;'
old_chosen = '''chosen {
\t\tbootargs = "root=/dev/fit0 rootwait";
\t\trootdisk = <&ubi_rootdisk>;
\t\tstdout-path = "serial0:115200n8";
\t};'''
new_chosen = '''chosen {
\t\tstdout-path = "serial0:115200n8";
\t};'''
old_fit_volume = '''
\t\t\t\tvolumes {
\t\t\t\t\tubi_rootdisk: ubi-volume-fit {
\t\t\t\t\t\tvolname = "fit";
\t\t\t\t\t};
\t\t\t\t};
'''
old_linux_ubi = '\t\t\t\tcompatible = "linux,ubi";\n'
old_wifi = '''&wifi {
\tnvmem-cells = <&eeprom_factory_0>;
\tnvmem-cell-names = "eeprom";
\tpinctrl-names = "default";
\tpinctrl-0 = <&wf_2g_5g_pins>;
\tstatus = "okay";
};'''
new_wifi = '''&wifi {
\tcompatible = "mediatek,wbsys", "mediatek,mt7986-wmac";
\tchip_id = <0x7986>;
\tnvmem-cells = <&eeprom_factory_0>;
\tnvmem-cell-names = "eeprom";
\tpinctrl-names = "default";
\tpinctrl-0 = <&wf_2g_5g_pins>;
\tstatus = "okay";
};'''
for name, old in [('RAM', old_mem), ('UBI', old_ubi), ('chosen', old_chosen),
                  ('fit-volume', old_fit_volume), ('linux,ubi', old_linux_ubi),
                  ('wifi', old_wifi)]:
    if s.count(old) != 1:
        raise SystemExit(f'{name} pattern count != 1: {s.count(old)}')
s = (s.replace(old_mem, new_mem, 1)
       .replace(old_ubi, new_ubi, 1)
       .replace(old_chosen, new_chosen, 1)
       .replace(old_fit_volume, '\n', 1)
       .replace(old_linux_ubi, '', 1)
       .replace(old_wifi, new_wifi, 1))

# Board-local overrides for conninfra; these are Wi-Fi-only and leave official
# networking nodes untouched.
s += '''

&wmcpu_emi {
\tcompatible = "mediatek,wmcpu-reserved";
};

&{/soc} {
\tconsys: consys@10000000 {
\t\tcompatible = "mediatek,mt7986-consys";
\t\treg = <0 0x10000000 0 0x8600000>;
\t\tmemory-region = <&wmcpu_emi>;
\t\tclocks = <&topckgen CLK_TOP_CONN_MCUSYS_SEL>,
\t\t\t <&topckgen CLK_TOP_AP2CNN_HOST_SEL>;
\t\tclock-names = "mcu", "ap2conn";
\t};
};
'''
p.write_text(s)
PY

# Proven classic NAND/UBI sysupgrade route. Keep initramfs recipe available but
# persistent firmware is the classic sysupgrade tar/bin used by the bootable test.
FILOGIC_MK="$SOURCE/target/linux/mediatek/image/filogic.mk"
python3 - "$FILOGIC_MK" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '''define Device/netcore_n60-pro
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_DTS := mt7986a-netcore-n60-pro
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | \\
\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-usb3 automount
  ARTIFACTS := preloader.bin bl31-uboot.fip
  ARTIFACT/preloader.bin := mt7986-bl2 spim-nand-ddr4
  ARTIFACT/bl31-uboot.fip := mt7986-bl31-uboot netcore_n60-pro
endef'''
new = '''define Device/netcore_n60-pro
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_DTS := mt7986a-netcore-n60-pro
  DEVICE_DTS_DIR := ../dts
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGES := sysupgrade.bin
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-usb3 automount
endef'''
if s.count(old) != 1:
    raise SystemExit(f'N60 Pro official profile pattern count != 1: {s.count(old)}')
p.write_text(s.replace(old, new, 1))
PY

PLATFORM_SH="$SOURCE/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
python3 - "$PLATFORM_SH" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old_upgrade = '''\topenwrt,one|\\
\tnetcore,n60|\\
\tnetcore,n60-pro|\\
\tqihoo,360t7|\\'''
new_upgrade = '''\topenwrt,one|\\
\tnetcore,n60|\\
\tqihoo,360t7|\\'''
classic_case = '''\tnetcore,n60-pro)
\t\tnand_do_upgrade "$1"
\t\t;;
'''
old_check = old_upgrade
new_check = new_upgrade
old_tar_check = '''\tcreatlentem,clt-r30b1|\\
\tcreatlentem,clt-r30b1-112m|\\
\tnradio,c8-668gl)'''
new_tar_check = '''\tnetcore,n60-pro|\\
\tcreatlentem,clt-r30b1|\\
\tcreatlentem,clt-r30b1-112m|\\
\tnradio,c8-668gl)'''
if s.count(old_upgrade) != 2:
    raise SystemExit(f'N60 Pro FIT case pattern count != 2: {s.count(old_upgrade)}')
if s.count(old_tar_check) != 1:
    raise SystemExit(f'classic tar check anchor count != 1: {s.count(old_tar_check)}')
s = s.replace(old_upgrade, new_upgrade, 1)
s = s.replace(new_upgrade, classic_case + new_upgrade, 1)
s = s.replace(old_check, new_check, 1)
s = s.replace(old_tar_check, new_tar_check, 1)
p.write_text(s)
PY

# Keep the existing proven 237 package config; add only the new helper kmod.
cp "$BUILDER/config/n60pro-extra.config" "$SOURCE/.config"
cat >> "$SOURCE/.config" <<'CFG'
CONFIG_PACKAGE_kmod-mt-wifi-utility=y
CFG

# Static guard rails: official platform survives, Wi-Fi helper is modular, and
# the known-good hardware/storage/radio invariants are all present.
for f in mt7986-ax6000.dbdc.b0.dat mt7986-ax6000.dbdc.b1.dat; do
  grep -qx 'CountryCode=CN' "$PROFILE_DIR/$f"
  grep -qx 'E2pAccessMode=2' "$PROFILE_DIR/$f"
  grep -qx 'SKUenable=0' "$PROFILE_DIR/$f"
  grep -qx 'TxPower=100' "$PROFILE_DIR/$f"
done

! grep -q 'mxl,led-config' "$DTS"
grep -q 'led@3' "$DTS"
grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"
! grep -q 'compatible = "linux,ubi"' "$DTS"
! grep -q 'root=/dev/fit0' "$DTS"
! grep -q 'rootdisk' "$DTS"
! grep -q 'ubi-volume-fit' "$DTS"
grep -q 'compatible = "mediatek,wbsys", "mediatek,mt7986-wmac";' "$DTS"
grep -q 'compatible = "mediatek,mt7986-consys";' "$DTS"
grep -q '^LUCI_DEPENDS:=+mtwifi-cfg-ucode$' "$SOURCE/package/mtk/applications/luci-app-mtwifi-cfg/Makefile"
test ! -e "$SOURCE/package/mtk/applications/mtwifi-cfg"
test ! -f "$SOURCE/package/mtk/applications/mtwifi-cfg/files/netifd/mtwifi.sh"
test "$(head -n 1 "$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/lib/netifd/wireless/mtwifi.sh")" = '#!/usr/bin/ucode'
grep -q '+iwinfo-ucode' "$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/Makefile"
grep -q '+wireless-tools' "$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/Makefile"
grep -Fqx 'const DRIVERS = ["mt_wifi"];' "$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"
! grep -Eq 'mtk_warp_proxy|mtk_warp' "$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/usr/share/ucode/mtwifi/driver.uc"
grep -q '@!PACKAGE_iwinfo' "$SOURCE/package/network/utils/iwinfo-ucode/Makefile"
grep -q 'BACKENDS="nl80211 mtk"' "$SOURCE/package/network/utils/iwinfo/Makefile"
grep -q '+libl1parser' "$SOURCE/package/network/utils/iwinfo/Makefile"
WIFI_SCRIPTS_HACK="$SOURCE/package/mtk/applications/mtwifi-cfg-ucode/files/etc/uci-defaults/99-hack-wifi-scripts"
test -f "$WIFI_SCRIPTS_HACK"
grep -q '/lib/netifd/wireless/mac80211.sh' "$WIFI_SCRIPTS_HACK"
grep -q 'mv "$MAC80211_SCRIPT"' "$WIFI_SCRIPTS_HACK"
test ! -f "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5200-mtk-add-wifi-utility-rbus.patch"
grep -q '^+obj-m += mtk_wifi_utility.o$' "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch"
grep -Eq '^\+[[:space:]]+ret = rbus_add_port\(rbus, pdev\);$' "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch"
grep -Eq '^\+[[:space:]]+if \(ret\)$' "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch"
grep -Eq '^\+[[:space:]]+return ret;$' "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch"
grep -Eq '^\+[[:space:]]+return 0;$' "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5204-mtk-wifi-utility-build-as-module.patch"
grep -A4 '^config  MTK_RT_FIRST_IF_RF_OFFSET$' "$MT_WIFI_CONFIG_IN" | grep -q 'default 0x0 if MTK_FIRST_IF_MT7986'
grep -A4 '^config  MTK_RT_FIRST_IF_RF_OFFSET$' "$MT_WIFI_CONFIG_IN" | grep -q 'default 0xc0000'
grep -Eq '^[[:space:]]*config MTK_MT_WIFI_MT7986_GOLDEN_7661$' "$MT_WIFI_CONFIG_IN"
grep -q 'default mt7986-fw-golden-7661 if MTK_MT_WIFI_MT7986_GOLDEN_7661' "$MT_WIFI_CONFIG_IN"
grep -q 'DEPENDS:=+kmod-mt-wifi-utility' "$CONNINFRA_MAKEFILE"
grep -Fq 'AUTOLOAD:=$(call AutoLoad,09,mtk_wifi_utility,1)' "$SOURCE/package/mtk/drivers/wifi_utility/Makefile"
grep -Fq 'AUTOLOAD:=$(call AutoLoad,10,conninfra,1)' "$CONNINFRA_MAKEFILE"
grep -Fq 'AUTOLOAD:=$(call AutoLoad,11,mt_wifi)' "$MT_WIFI_MAKEFILE"
! grep -Fq 'AUTOLOAD:=$(call AutoLoad,11,mt_wifi,' "$MT_WIFI_MAKEFILE"
! grep -Eq 'AUTOLOAD:=.*mtk_warp_proxy' "$MT_WIFI_MAKEFILE"
! grep -Eq 'AUTOLOAD:=.*mtk_warp' "$MT_WIFI_MAKEFILE"
grep -q '^CONFIG_PACKAGE_kmod-mt-wifi-utility=y$' "$SOURCE/.config"
grep -q '^CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0$' "$SOURCE/.config"
! grep -Eq '^CONFIG_PACKAGE_kmod-mt7915e=(y|m)$' "$SOURCE/.config"
! grep -Eq '^CONFIG_PACKAGE_kmod-mt7986-firmware=(y|m)$' "$SOURCE/.config"
! grep -Eq '^CONFIG_PACKAGE_mt7986-wo-firmware=(y|m)$' "$SOURCE/.config"
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"
done
! grep -Eq 'LIB80211' "$WEXT_PATCH_DST"
! test -d "$SOURCE/package/mtk/drivers/warp"
! grep -q '^PKG_BUILD_DEPENDS:=warp$' "$MT_WIFI_MAKEFILE"
! grep -q 'kmod-mediatek_hnat' "$MT_WIFI_MAKEFILE"
! grep -q 'kmod-warp' "$MT_WIFI_MAKEFILE"
! grep -q 'mtk_warp_proxy\.ko' "$MT_WIFI_MAKEFILE"
grep -A14 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q '^  IMAGES := sysupgrade.bin$'
grep -A14 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q '^  DEVICE_PACKAGES := kmod-usb3 automount$'
grep -A4 $'^\tnetcore,n60-pro)' "$PLATFORM_SH" | grep -q 'nand_do_upgrade "$1"'

echo 'prepare #23: OK'
