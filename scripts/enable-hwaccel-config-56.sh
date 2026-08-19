#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: enable-hwaccel-config-56.sh <prepared-source> <builder-root>}"
BUILDER="${2:?usage: enable-hwaccel-config-56.sh <prepared-source> <builder-root>}"
EXTRA="$BUILDER/config/n60pro-hwaccel-56.config"
CONFIG="$SOURCE/.config"
MT_WIFI_MAKEFILE="$SOURCE/package/mtk/drivers/mt_wifi/Makefile"
KERNEL_CFG="$SOURCE/target/linux/mediatek/filogic/config-6.12"

test -f "$CONFIG"
test -f "$EXTRA"
test -f "$MT_WIFI_MAKEFILE"
test -f "$KERNEL_CFG"
test -d "$SOURCE/package/mtk/drivers/warp"
test -d "$SOURCE/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat"
grep -q 'N60PRO_HWACCEL_56_HNAT_BEGIN' "$SOURCE/package/kernel/linux/modules/netdevices.mk"
grep -q 'N60PRO_HWACCEL_56_DTS_BEGIN' "$SOURCE/target/linux/mediatek/dts/mt7986a-netcore-n60-pro.dts"

# Remove only conflicting #55 diagnostic-disable lines, then append #56.
python3 - "$CONFIG" "$EXTRA" <<'PY'
from pathlib import Path
import re, sys
cfg = Path(sys.argv[1])
extra = Path(sys.argv[2])
s = cfg.read_text()
syms = [
    'PACKAGE_kmod-mediatek_hnat',
    'PACKAGE_kmod-warp',
    'MTK_FAST_NAT_SUPPORT',
    'MTK_WHNAT_SUPPORT',
    'MTK_WARP_V2',
    'WARP_CHIPSET',
    'WARP_VERSION',
    'WED_HW_RRO_SUPPORT',
    'WARP_DBG_SUPPORT',
    'WARP_MEMORY_LEAK_DBG',
    'WARP_WO_EMBEDDED_LOAD',
]
lines = s.splitlines()
out = []
for line in lines:
    if any(re.match(rf'^(?:# )?CONFIG_{re.escape(sym)}(?:=| is not set$)', line) for sym in syms):
        continue
    out.append(line)
cfg.write_text('\n'.join(out).rstrip() + '\n\n' + extra.read_text().strip() + '\n')
PY

# The donor HNAT Ethernet patch introduces NETSYS generation Kconfig symbols.
# MT7986 is NETSYS V2, and the donor's own filogic/config-6.12 pins exactly
# V2=y / V3=n. Without these lines Linux syncconfig stops on a NEW prompt
# before auto.conf can be generated.
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

# #55 proved the early mt_wifi load order. Keep mt_wifi at 11, let kmod-warp
# load at its vendor-defined 60, then load mtk_warp_proxy at 61 to connect the
# already-running Wi-Fi driver to WARP without disturbing the proven boot gate.
python3 - "$MT_WIFI_MAKEFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi)\n'
new = '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi) $(call AutoLoad,61,mtk_warp_proxy)\n'
if old in s:
    if s.count(old) != 1:
        raise SystemExit(f'mt_wifi AutoLoad old anchor count != 1: {s.count(old)}')
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('mt_wifi AutoLoad is neither #55 nor #56 expected form')
p.write_text(s)
PY

make -C "$SOURCE" defconfig

# Package/config gates. WED is already part of the official filogic kernel base;
# #56 must keep it enabled while adding HNAT/WARP/WHNAT.
grep -qx 'CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$CONFIG"
grep -qx 'CONFIG_PACKAGE_kmod-warp=y' "$CONFIG"
grep -qx 'CONFIG_MTK_FAST_NAT_SUPPORT=y' "$CONFIG"
grep -Eq '^CONFIG_MTK_WHNAT_SUPPORT=(m|y)$' "$CONFIG"
grep -qx 'CONFIG_MTK_WARP_V2=y' "$CONFIG"
grep -qx 'CONFIG_WARP_CHIPSET="mt7986"' "$CONFIG"
grep -qx 'CONFIG_WARP_VERSION=2' "$CONFIG"
grep -qx 'CONFIG_WED_HW_RRO_SUPPORT=y' "$CONFIG"

# HNAT KernelPackage KCONFIG must resolve into the Linux build config path.
# This symbol may not be copied literally into top-level .config, so the actual
# kernel compile gate below remains authoritative for CONFIG_NET_MEDIATEK_HNAT.

grep -qx 'CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0' "$CONFIG"
grep -qx '# CONFIG_MTK_MT7986_NEW_FW is not set' "$CONFIG"
! grep -Eq '^CONFIG_PACKAGE_kmod-mt7915e=(y|m)$' "$CONFIG"
! grep -Eq '^CONFIG_PACKAGE_kmod-mt7986-firmware=(y|m)$' "$CONFIG"
! grep -Eq '^CONFIG_PACKAGE_mt7986-wo-firmware=(y|m)$' "$CONFIG"

# The official 6.12 filogic baseline already carries WED; never disable it to
# make HNAT compile. The #56 donor HNAT overlay additionally requires the
# MT7986 NETSYS generation to be explicit so kernel syncconfig stays noninteractive.
grep -qx 'CONFIG_NET_MEDIATEK_SOC_WED=y' "$KERNEL_CFG"
grep -qx 'CONFIG_MEDIATEK_NETSYS_V2=y' "$KERNEL_CFG"
grep -qx '# CONFIG_MEDIATEK_NETSYS_V3 is not set' "$KERNEL_CFG"
grep -Fqx '  AUTOLOAD:=$(call AutoLoad,11,mt_wifi) $(call AutoLoad,61,mtk_warp_proxy)' "$MT_WIFI_MAKEFILE"

echo 'enable hardware acceleration config #56: OK'
