#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: rebase-official-release-config.sh <official-source> <builder-root>}"
BUILDER="${2:?usage: rebase-official-release-config.sh <official-source> <builder-root>}"
OFFICIAL_CONFIG_URL="https://downloads.immortalwrt.org/releases/25.12.1/targets/mediatek/filogic/config.buildinfo"

# Restore the official 25.12.1 generic kernel baseline byte-for-byte.
# The proprietary Wi-Fi stack must adapt to the official kernel, not vice versa.
git -C "$SOURCE" checkout -- target/linux/generic/config-6.12
WEXT_PATCH="target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
if git -C "$SOURCE" cat-file -e "HEAD:$WEXT_PATCH" 2>/dev/null; then
    git -C "$SOURCE" checkout -- "$WEXT_PATCH"
else
    rm -f "$SOURCE/$WEXT_PATCH"
fi

# Start from ImmortalWrt's actual 25.12.1 filogic release build configuration.
# Keep ALL_KMODS/target kernel selections so the generated kernel matches the
# official release baseline as closely as possible, but build only N60 Pro.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fL --retry 5 --retry-delay 2 "$OFFICIAL_CONFIG_URL" -o "$tmp"
grep -q '^CONFIG_TARGET_mediatek=y$' "$tmp"
grep -q '^CONFIG_TARGET_mediatek_filogic=y$' "$tmp"
cp "$tmp" "$SOURCE/.config"

# Limit image generation to N60 Pro. Do not discard shared target/kernel config.
sed -i -E '/^(# )?CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/d' "$SOURCE/.config"
sed -i -E '/^(# )?CONFIG_TARGET_ALL_PROFILES(=| )/d' "$SOURCE/.config"
cat >> "$SOURCE/.config" <<'CFG'
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y
CFG

# Remove any release values for the proprietary stack before appending our
# pinned 237/mt_wifi 7.6.7.3 choices.
python3 - "$SOURCE/.config" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
exact = {
    'CONFIG_PACKAGE_kmod-conninfra',
    'CONFIG_PACKAGE_kmod-mt_wifi',
    'CONFIG_PACKAGE_mtwifi-cfg',
    'CONFIG_PACKAGE_mtwifi-cfg-ucode',
    'CONFIG_PACKAGE_luci-app-mtwifi-cfg',
    'CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn',
    'CONFIG_PACKAGE_kmod-mt-wifi-utility',
    'CONFIG_PACKAGE_kmod-warp',
    'CONFIG_PACKAGE_kmod-mediatek_hnat',
}
out = []
for line in lines:
    m = re.match(r'^(?:# )?(CONFIG_[A-Za-z0-9_\-]+)', line)
    sym = m.group(1) if m else ''
    if sym.startswith('CONFIG_MTK_') or sym.startswith('CONFIG_first_card') or sym in exact:
        continue
    out.append(line)
p.write_text('\n'.join(out) + '\n')
PY

# Append only the proprietary Wi-Fi package/Kconfig selections from our fragment.
grep -E '^(CONFIG_MTK_|# CONFIG_MTK_|CONFIG_first_card|CONFIG_PACKAGE_kmod-conninfra=|CONFIG_PACKAGE_kmod-mt_wifi=|CONFIG_PACKAGE_mtwifi-cfg=|CONFIG_PACKAGE_luci-app-mtwifi-cfg=|CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=|# CONFIG_PACKAGE_kmod-warp is not set|# CONFIG_PACKAGE_kmod-mediatek_hnat is not set)' \
    "$BUILDER/config/n60pro-extra.config" >> "$SOURCE/.config"
echo 'CONFIG_PACKAGE_kmod-mt-wifi-utility=y' >> "$SOURCE/.config"

# Guard: generic Linux config is now exactly the official release source again.
git -C "$SOURCE" diff --exit-code -- target/linux/generic/config-6.12
if ! git -C "$SOURCE" cat-file -e "HEAD:$WEXT_PATCH" 2>/dev/null; then
    test ! -e "$SOURCE/$WEXT_PATCH"
fi

grep -qx 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-mt_wifi=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-mt-wifi-utility=y' "$SOURCE/.config"

echo 'official 25.12.1 filogic release config rebased: OK'
