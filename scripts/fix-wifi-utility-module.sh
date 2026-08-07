#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: fix-wifi-utility-module.sh <official-source>}"
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
