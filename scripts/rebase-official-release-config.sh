#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: rebase-official-release-config.sh <official-source> <builder-root>}"
BUILDER="${2:?usage: rebase-official-release-config.sh <official-source> <builder-root>}"
OFFICIAL_CONFIG_URL="https://downloads.immortalwrt.org/releases/25.12.1/targets/mediatek/filogic/config.buildinfo"

# Restore the official 25.12.1 generic kernel baseline first.
# The only intentional generic-kernel delta kept below is legacy WEXT, which
# proprietary mt_wifi 7.6.7.3 requires for iwe_stream_add_* symbols.
git -C "$SOURCE" checkout -- target/linux/generic/config-6.12
WEXT_PATCH="target/linux/generic/hack-6.12/299-add-wext-kconfig.patch"
GENERIC_CONFIG="$SOURCE/target/linux/generic/config-6.12"

# prepare.sh installs this exact Kconfig-only patch from the pinned donor. It
# only makes the legacy WEXT options selectable; it does not import donor
# Ethernet/WED/PPE/PHY code.
test -f "$SOURCE/$WEXT_PATCH"
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  if grep -qx "# CONFIG_${sym} is not set" "$GENERIC_CONFIG"; then
    sed -i "s/^# CONFIG_${sym} is not set$/CONFIG_${sym}=y/" "$GENERIC_CONFIG"
  elif ! grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"; then
    echo "CONFIG_${sym}=y" >> "$GENERIC_CONFIG"
  fi
done

# Start from ImmortalWrt's actual 25.12.1 filogic release build configuration.
# Expand it before any package pruning so kernel package->Kconfig generation can
# keep using the official full release package scope.
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

# OpenWrt's kernel configure step normally feeds the final top-level .config to
# package-metadata.pl. Our final .config is intentionally package-trimmed, so
# route only kernel override generation through the official sidecar above.
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

# Now derive the actual build config from that full official sidecar. Preserve
# target/kernel settings, but remove buildbot cleanup/rebuild controls that are
# unsafe for this single-device GitHub Actions build.
cp "$SOURCE/.config.kernel-official" "$SOURCE/.config"

# The release buildinfo is generated for ImmortalWrt's buildbot. #33 proved
# that CONFIG_BUILDBOT causes concurrent toolchain .ver_check cleanup to remove
# target/toolchain state during this clean parallel build. AUTOREMOVE and the
# DEVEL-default AUTOREBUILD are also destructive/rebuild-oriented controls that
# are unnecessary for a one-shot device image. Keep them explicitly disabled.
for sym in BUILDBOT AUTOREMOVE AUTOREBUILD; do
  sed -i -E "/^CONFIG_${sym}=y$/d; /^# CONFIG_${sym} is not set$/d" "$SOURCE/.config"
  echo "# CONFIG_${sym} is not set" >> "$SOURCE/.config"
done

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
    'CONFIG_PACKAGE_iwinfo',
    'CONFIG_PACKAGE_iwinfo-ucode',
    'CONFIG_PACKAGE_mtwifi-cfg',
    'CONFIG_PACKAGE_mtwifi-cfg-ucode',
    'CONFIG_PACKAGE_luci-app-mtwifi-cfg',
    'CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn',
    'CONFIG_PACKAGE_kmod-mt-wifi-utility',
    'CONFIG_PACKAGE_kmod-warp',
    'CONFIG_PACKAGE_kmod-mediatek_hnat',
    'CONFIG_CONNINFRA_AUTO_UP',
    'CONFIG_CONNINFRA_EMI_SUPPORT',
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
grep -E '^(CONFIG_MTK_|# CONFIG_MTK_|CONFIG_CONNINFRA_AUTO_UP=|CONFIG_CONNINFRA_EMI_SUPPORT=|CONFIG_first_card|CONFIG_PACKAGE_kmod-conninfra=|CONFIG_PACKAGE_kmod-mt_wifi=|CONFIG_PACKAGE_mtwifi-cfg-ucode=|# CONFIG_PACKAGE_iwinfo is not set|CONFIG_PACKAGE_iwinfo-ucode=|CONFIG_PACKAGE_luci-app-mtwifi-cfg=|CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=|CONFIG_PACKAGE_luci-app-openclash=|CONFIG_PACKAGE_luci-app-store=|# CONFIG_PACKAGE_kmod-warp is not set|# CONFIG_PACKAGE_kmod-mediatek_hnat is not set)' \
    "$BUILDER/config/n60pro-extra.config" >> "$SOURCE/.config"
echo 'CONFIG_PACKAGE_kmod-mt-wifi-utility=y' >> "$SOURCE/.config"

# Guard: keep the official generic baseline except for the five required WEXT
# selections above. No other generic kernel config drift is allowed.
for sym in WIRELESS_EXT WEXT_CORE WEXT_PRIV WEXT_PROC WEXT_SPY; do
  grep -qx "CONFIG_${sym}=y" "$GENERIC_CONFIG"
done
unexpected="$({ git -C "$SOURCE" diff --unified=0 -- target/linux/generic/config-6.12 || true; } \
  | grep -E '^[+-](CONFIG_|# CONFIG_)' \
  | grep -Ev '^[+-](CONFIG_(WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY)=y|# CONFIG_(WIRELESS_EXT|WEXT_CORE|WEXT_PRIV|WEXT_PROC|WEXT_SPY) is not set)$' \
  || true)"
test -z "$unexpected"
test -f "$SOURCE/$WEXT_PATCH"

for sym in BUILDBOT AUTOREMOVE AUTOREBUILD; do
  grep -qx "# CONFIG_${sym} is not set" "$SOURCE/.config"
done
grep -qx 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_netcore_n60-pro=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-mt_wifi=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_kmod-mt-wifi-utility=y' "$SOURCE/.config"
grep -qx 'CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0' "$SOURCE/.config"
grep -qx 'CONFIG_CONNINFRA_AUTO_UP=y' "$SOURCE/.config"
grep -qx 'CONFIG_CONNINFRA_EMI_SUPPORT=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_mtwifi-cfg-ucode=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_luci-app-openclash=y' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_luci-app-store=y' "$SOURCE/.config"
grep -qx '# CONFIG_PACKAGE_iwinfo is not set' "$SOURCE/.config"
grep -qx 'CONFIG_PACKAGE_iwinfo-ucode=y' "$SOURCE/.config"
! grep -Eq '^CONFIG_PACKAGE_mtwifi-cfg=(y|m)$' "$SOURCE/.config"
test -f "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_KMODS=y' "$SOURCE/.config.kernel-official"
grep -qx 'CONFIG_ALL_NONSHARED=y' "$SOURCE/.config.kernel-official"

echo 'official 25.12.1 filogic release config sidecar + required WEXT + buildbot cleanup disabled: OK'
