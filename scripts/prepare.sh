#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
DONOR="${2:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
BUILDER="${3:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"

# Keep the official ImmortalWrt tree as the base. Import only the MTK packages
# required by the proprietary N60 Pro Wi-Fi path. WARP/HNAT is intentionally
# excluded: 237 RF power does not require it, and it touches the Ethernet/PPE
# path that must stay identical to official N60 Pro.
rm -rf "$SOURCE/package/mtk"
for rel in \
  drivers/conninfra \
  drivers/mt_wifi \
  drivers/wifi-profile \
  applications/datconf \
  applications/mtwifi-cfg \
  applications/luci-app-mtwifi-cfg; do
  mkdir -p "$SOURCE/package/mtk/$(dirname "$rel")"
  rsync -a "$DONOR/package/mtk/$rel/" "$SOURCE/package/mtk/$rel/"
done

# The donor mt_wifi package hard-depends on its legacy WARP/HNAT acceleration
# stack even though the driver itself supports running without WHNAT/WARP.
# Remove only those package/build/install dependencies; CONFIG_MTK_WHNAT_SUPPORT,
# CONFIG_MTK_WARP_V2 and CONFIG_MTK_FAST_NAT_SUPPORT stay disabled in our config.
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
     "  AUTOLOAD:=$(call AutoProbe,mt_wifi)\n"),
]
for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit(f'mt_wifi Makefile pattern count != 1: {old!r}: {s.count(old)}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

# IMPORTANT: keep target/linux/mediatek from the official 25.12.1 release.
# The previous whole-tree donor overlay built successfully but the flashed image
# had no working LAN, while the official 25.12.1 N60 Pro initramfs had working
# DHCP/LAN on the same hardware. Therefore donor target files must not replace
# the official N60 Pro Ethernet/DSA/PHY/kernel integration. Add only compatibility
# pieces that are proven necessary below.

# mt_wifi still relies on legacy Wireless Extensions. Linux 6.12 keeps the
# implementation, but WIRELESS_EXT/WEXT_* are hidden Kconfig symbols upstream.
# Import only the donor patch that makes them selectable, then enable them.
WEXT_PATCH_SRC="$DONOR/target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
WEXT_PATCH_DST="$SOURCE/target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
test -f "$WEXT_PATCH_SRC"
install -m0644 "$WEXT_PATCH_SRC" "$WEXT_PATCH_DST"

GENERIC_CONFIG="$SOURCE/target/linux/generic/config-6.12"
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  if grep -qx "# CONFIG_${sym} is not set" "$GENERIC_CONFIG"; then
    sed -i "s/^# CONFIG_${sym} is not set$/CONFIG_${sym}=y/" "$GENERIC_CONFIG"
  elif ! grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"; then
    echo "CONFIG_${sym}=y" >> "$GENERIC_CONFIG"
  fi
done

# conninfra/mt_wifi use MediaTek's in-kernel wifi_utility API for EEPROM access
# and RBUS glue. Keep the official MediaTek target intact: import only this small
# donor utility directory plus the three Linux 6.12 patches that build/fix it and
# export mt_eeprom_read_wifi()/mt_eeprom_write_wifi().
WIFI_UTILITY_SRC="$DONOR/target/linux/mediatek/files-6.12/drivers/net/wireless/wifi_utility"
WIFI_UTILITY_DST="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/wireless/wifi_utility"
test -d "$WIFI_UTILITY_SRC"
mkdir -p "$(dirname "$WIFI_UTILITY_DST")"
rm -rf "$WIFI_UTILITY_DST"
rsync -a "$WIFI_UTILITY_SRC/" "$WIFI_UTILITY_DST/"

for patch in \
  999-zzz-5200-mtk-add-wifi-utility-rbus.patch \
  999-zzz-5202-mtk-wifi_utility-since-v6.11-fix-rbus_remove-return-type.patch \
  999-zzz-5203-mtk-wifi_utility-add-universal-eeprom-read-write-backend.patch; do
  src="$DONOR/target/linux/mediatek/patches-6.12/$patch"
  dst="$SOURCE/target/linux/mediatek/patches-6.12/$patch"
  test -f "$src"
  install -m0644 "$src" "$dst"
done

# Use the classic Lua mtwifi-cfg used by the running 237 firmware. The donor's
# LuCI package defaults to the ucode frontend, so point it at mtwifi-cfg instead.
sed -i 's/LUCI_DEPENDS:=+mtwifi-cfg-ucode/LUCI_DEPENDS:=+mtwifi-cfg/' \
  "$SOURCE/package/mtk/applications/luci-app-mtwifi-cfg/Makefile"

# Reproduce the 237 MT7986 radio profiles only; do not import its Linux 6.6 tree.
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

# N60 Pro hard-mod: 2 GiB RAM and WildEdition 512 MiB MAX NAND layout.
# This edits the official 25.12.1 N60 Pro DTS, not the donor DTS.
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
if s.count(old_mem) != 1:
    raise SystemExit(f'RAM pattern count != 1: {s.count(old_mem)}')
if s.count(old_ubi) != 1:
    raise SystemExit(f'UBI pattern count != 1: {s.count(old_ubi)}')
if s.count(old_chosen) != 1:
    raise SystemExit(f'chosen fit0 pattern count != 1: {s.count(old_chosen)}')
if s.count(old_fit_volume) != 1:
    raise SystemExit(f'ubi fit volume pattern count != 1: {s.count(old_fit_volume)}')
s = (
    s.replace(old_mem, new_mem, 1)
     .replace(old_ubi, new_ubi, 1)
     .replace(old_chosen, new_chosen, 1)
     .replace(old_fit_volume, '\n', 1)
)
p.write_text(s)
PY

# Switch only N60 Pro from the official fit0/rootdisk sysupgrade.itb path to the
# classic NAND sysupgrade tar/bin path used by the proven bootable N60 Pro line.
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
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-usb3 automount
endef'''
if s.count(old) != 1:
    raise SystemExit(f'N60 Pro official ITB image block count != 1: {s.count(old)}')
s = s.replace(old, new, 1)
p.write_text(s)
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
old_check = '''\topenwrt,one|\\
\tnetcore,n60|\\
\tnetcore,n60-pro|\\
\tqihoo,360t7|\\'''
new_check = '''\topenwrt,one|\\
\tnetcore,n60|\\
\tqihoo,360t7|\\'''
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
insert_before = new_upgrade
if s.count(insert_before) < 1:
    raise SystemExit('FIT upgrade case insertion anchor missing')
s = s.replace(insert_before, classic_case + insert_before, 1)
s = s.replace(old_check, new_check, 1)
s = s.replace(old_tar_check, new_tar_check, 1)
p.write_text(s)
PY

# Start from a minimal N60 Pro config, never from the donor AX6000 defconfig.
cp "$BUILDER/config/n60pro-extra.config" "$SOURCE/.config"

# Guard rails: exact 237 high-power profile behavior requested for this build.
for f in mt7986-ax6000.dbdc.b0.dat mt7986-ax6000.dbdc.b1.dat; do
  grep -qx 'CountryCode=CN' "$PROFILE_DIR/$f"
  grep -qx 'E2pAccessMode=2' "$PROFILE_DIR/$f"
  grep -qx 'SKUenable=0' "$PROFILE_DIR/$f"
  grep -qx 'TxPower=100' "$PROFILE_DIR/$f"
done

# Official N60 Pro DTS fingerprint: the release DTS uses LED child nodes for the
# MaxLinear PHYs; the donor DTS replaces these with mxl,led-config. Refuse to
# build if the donor N60 Pro DTS has accidentally been overlaid again.
! grep -q 'mxl,led-config' "$DTS"
grep -q 'led@3' "$DTS"
grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"
! grep -q 'root=/dev/fit0' "$DTS"
! grep -q 'rootdisk' "$DTS"
! grep -q 'ubi-volume-fit' "$DTS"
! grep -q 'volname = "fit"' "$DTS"
grep -A12 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q '^  IMAGES := sysupgrade.bin$'
grep -A12 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q '^  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata$'
! grep -A20 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q 'sysupgrade.itb'
! grep -A20 '^define Device/netcore_n60-pro$' "$FILOGIC_MK" | grep -q 'KERNEL_IN_UBI'
grep -A4 $'^\tnetcore,n60-pro)' "$PLATFORM_SH" | grep -q 'nand_do_upgrade "$1"'
! grep -B60 -A2 'fit_do_upgrade "$1"' "$PLATFORM_SH" | grep -q $'\tnetcore,n60-pro'
! grep -B60 -A2 'fit_check_image "$1"' "$PLATFORM_SH" | grep -q $'\tnetcore,n60-pro'
grep -A8 $'^\tnetcore,n60-pro|\\\\' "$PLATFORM_SH" | grep -q 'magic="$(dd if="$1" bs=1 skip=257 count=5'
grep -q '^LUCI_DEPENDS:=+mtwifi-cfg$' "$SOURCE/package/mtk/applications/luci-app-mtwifi-cfg/Makefile"
test -f "$WEXT_PATCH_DST"
test -f "$WIFI_UTILITY_DST/mt_wifi_mtd.c"
grep -q 'EXPORT_SYMBOL(mt_eeprom_read_wifi);' \
  "$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5203-mtk-wifi_utility-add-universal-eeprom-read-write-backend.patch"
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"
done
! test -d "$SOURCE/package/mtk/drivers/warp"
! grep -q '^PKG_BUILD_DEPENDS:=warp$' "$MT_WIFI_MAKEFILE"
! grep -q 'kmod-mediatek_hnat' "$MT_WIFI_MAKEFILE"
! grep -q 'kmod-warp' "$MT_WIFI_MAKEFILE"
! grep -q 'mtk_warp_proxy\.ko' "$MT_WIFI_MAKEFILE"

echo 'prepare: OK'
