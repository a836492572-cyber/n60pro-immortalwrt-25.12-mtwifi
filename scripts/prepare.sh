#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
DONOR="${2:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"
BUILDER="${3:?usage: prepare.sh <official-source> <mtk-donor> <builder-root>}"

# Import only the MTK package stack and MediaTek target/kernel integration.
rm -rf "$SOURCE/package/mtk" "$SOURCE/target/linux/mediatek"
mkdir -p "$SOURCE/package" "$SOURCE/target/linux"
rsync -a "$DONOR/package/mtk/" "$SOURCE/package/mtk/"
rsync -a "$DONOR/target/linux/mediatek/" "$SOURCE/target/linux/mediatek/"

# Use the 237 MT7986 radio profiles verbatim (radio-only donor, not 6.6 kernel code).
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

# Match the user's WildEdition 512 MiB MAX layout and 2 GiB RAM.
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

# Start from the MT7986 AX6000 6.12 driver config, then keep only N60 Pro.
cp "$DONOR/defconfig/mt7986-ax6000.config" "$SOURCE/.config"
sed -i \
  -e '/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/d' \
  -e '/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_/d' \
  -e '/^CONFIG_TARGET_MULTI_PROFILE=/d' \
  -e '/^CONFIG_PACKAGE_mtwifi-cfg=/d' \
  -e '/^CONFIG_PACKAGE_mtwifi-cfg-ucode=/d' \
  -e '/^CONFIG_PACKAGE_luci=/d' \
  -e '/^CONFIG_PACKAGE_luci-ssl=/d' \
  -e '/^CONFIG_PACKAGE_luci-app-mtwifi-cfg=/d' \
  -e '/^CONFIG_PACKAGE_luci-i18n-base-zh-cn=/d' \
  -e '/^CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=/d' \
  "$SOURCE/.config"
cat "$BUILDER/config/n60pro-extra.config" >> "$SOURCE/.config"

# Guard rails: fail early if the 237 radio profile is not the expected one.
for f in mt7986-ax6000.dbdc.b0.dat mt7986-ax6000.dbdc.b1.dat; do
  grep -qx 'CountryCode=CN' "$PROFILE_DIR/$f"
  grep -qx 'E2pAccessMode=2' "$PROFILE_DIR/$f"
  grep -qx 'SKUenable=0' "$PROFILE_DIR/$f"
  grep -qx 'TxPower=100' "$PROFILE_DIR/$f"
done

grep -q 'reg = <0 0x40000000 0 0x80000000>;' "$DTS"
grep -q 'reg = <0x0580000 0x1fa80000>;' "$DTS"

echo 'prepare: OK'
