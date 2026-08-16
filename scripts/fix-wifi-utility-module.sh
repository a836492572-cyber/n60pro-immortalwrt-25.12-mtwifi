#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: fix-wifi-utility-module.sh <official-source>}"
BUILDER="$(dirname "$SOURCE")"
DONOR="$BUILDER/mtk-donor"
PATCH="$SOURCE/target/linux/mediatek/patches-6.12/999-zzz-5203-mtk-wifi_utility-add-universal-eeprom-read-write-backend.patch"

test -f "$PATCH"
# for_each_of_allnodes() expands to __of_find_all_nodes(), which is not exported
# to loadable modules on Linux 6.12. N60 Pro's board-local Wi-Fi override adds
# compatible="mediatek,wbsys", so use the module-safe compatible-node iterator.
old=$'+\tfor_each_of_allnodes(np) {'
new=$'+\tfor_each_compatible_node(np, NULL, "mediatek,wbsys") {'
[ "$(grep -Fxc "$old" "$PATCH")" -eq 1 ]
sed -i 's/for_each_of_allnodes(np)/for_each_compatible_node(np, NULL, "mediatek,wbsys")/' "$PATCH"
grep -Fqx "$new" "$PATCH"
! grep -Fq 'for_each_of_allnodes(np)' "$PATCH"

echo 'wifi_utility module export fix: OK'

# Donor iwinfo patch 0001 widens the fixed WEXT userspace ABI fields
# iw_param.value and iw_range.bitrate[] from 32 to 64 bits. Linux 6.12 still
# returns the standard 32-bit layout, so the widened iw_param reads the
# following fixed/disabled/flags bytes as the upper half of bitrate.value.
# Keep only the donor's required scan_capa layout correction.
IWINFO_WEXT_PATCH="$SOURCE/package/network/utils/iwinfo/patches/0001-fix-wext-h.patch"
test -f "$IWINFO_WEXT_PATCH"
[ "$(grep -Fc 'uint64_t' "$IWINFO_WEXT_PATCH")" -eq 2 ]
grep -Fq 'scan_capa' "$IWINFO_WEXT_PATCH"
cat > "$IWINFO_WEXT_PATCH" <<'PATCH'
--- a/api/wext.h
+++ b/api/wext.h
@@ -988,6 +988,9 @@
 	uint16_t		old_num_channels;
 	uint8_t		old_num_frequency;
 
+	/* Scan capabilities */
+	uint8_t		scan_capa; 	/* IW_SCAN_CAPA_* bit field */
+
 	/* Wireless event capability bitmasks */
 	uint32_t		event_capa[6];
 
PATCH
! grep -Fq 'uint64_t' "$IWINFO_WEXT_PATCH"
grep -Fq 'scan_capa' "$IWINFO_WEXT_PATCH"

echo 'iwinfo WEXT userspace ABI fix: OK'

# Restore the pinned Linux 6.12 MediaTek acceleration sidecar only after the
# #50 RF enclave and wifi_utility fixes are in place.
bash "$BUILDER/scripts/restore-hw-accel.sh" "$SOURCE" "$DONOR" "$BUILDER"
