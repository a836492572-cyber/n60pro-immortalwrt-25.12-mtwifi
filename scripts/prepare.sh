#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
DONOR="${2:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
BUILDER="${3:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"

# Keep the official ImmortalWrt tree as the base. Import only the MTK packages
# required by the proprietary N60 Pro Wi-Fi path.
rm -rf "$SOURCE/package/mtk"
for rel in \
  drivers/conninfra \
  drivers/mt_wifi \
  drivers/warp \
  drivers/wifi-profile \
  applications/datconf \
  applications/mtwifi-cfg \
  applications/luci-app-mtwifi-cfg; do
  mkdir -p "$SOURCE/package/mtk/$(dirname "$rel")"
  rsync -a "$DONOR/package/mtk/$rel/" "$SOURCE/package/mtk/$rel/"
done

# MTK proprietary WARP/HNAT needs the donor's Linux 6.12 MediaTek integration.
# Overlay it on the official target instead of replacing the official tree.
rsync -a "$DONOR/target/linux/mediatek/" "$SOURCE/target/linux/mediatek/"

# kmod-mediatek_hnat is defined by the donor in the generic kernel modules file,
# not under package/mtk. Import only that single KernelPackage stanza.
HNAT_DST="$SOURCE/package/kernel/linux/modules/netdevices.mk"
if ! grep -q '^define KernelPackage/mediatek_hnat$' "$HNAT_DST"; then
  tmp="$(mktemp)"
  sed -n '/^define KernelPackage\/mediatek_hnat$/,/^\$(eval \$(call KernelPackage,mediatek_hnat))$/p' \
    "$DONOR/package/kernel/linux/modules/netdevices.mk" > "$tmp"
  test -s "$tmp"
  printf '\n' >> "$HNAT_DST"
  cat "$tmp" >> "$HNAT_DST"
  rm -f "$tmp"
fi

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
if s.count(old_mem) != 1:
    raise SystemExit(f'RAM pattern count != 1: {s.count(old_mem)}')
if s.count(old_ubi) != 1:
    raise SystemExit(f'UBI pattern count != 1: {s.count(old_ubi)}')
s = s.replace(old_mem, new_mem, 1).replace(old_ubi, new_ubi, 1)
p.write_text(s)
PY

# Start from a minimal N60 Pro config, never from the donor AX6000 defconfig.
cp "$BUILDER/config/n60pro-extra.config" "$SOURCE/.config"

# Pin unrelated donor PHY options off so kernel syncconfig stays noninteractive.
KERNEL_CONFIG="$SOURCE/target/linux/mediatek/filogic/config-6.12"
for sym in AIROHA_AN8801_PHY AIR_AN8811HB_PHY; do
  if ! grep -qx "# CONFIG_${sym} is not set" "$KERNEL_CONFIG"; then
    echo "# CONFIG_${sym} is not set" >> "$KERNEL_CONFIG"
  fi
done

# Guard rails: exact 237 high-power profile behavior requested for this build.
for f in mt7986-ax6000.dbdc.b0.dat mt7986-ax6000.dbdc.b1.dat; do
  grep -qx 'CountryCode=CN' "$PROFILE_DIR/$f"
  grep -qx 'E2pAccessMode=2' "$PROFILE_DIR/$f"
  grep -qx 'SKUenable=0' "$PROFILE_DIR/$f"
  grep -qx 'TxPower=100' "$PROFILE_DIR/$f"
done

grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"
grep -q '^define KernelPackage/mediatek_hnat$' "$HNAT_DST"
grep -q '^LUCI_DEPENDS:=+mtwifi-cfg$' "$SOURCE/package/mtk/applications/luci-app-mtwifi-cfg/Makefile"
grep -qx '# CONFIG_AIR_AN8811HB_PHY is not set' "$KERNEL_CONFIG"

echo 'prepare: OK'
