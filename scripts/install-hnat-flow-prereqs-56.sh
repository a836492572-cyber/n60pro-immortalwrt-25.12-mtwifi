#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: install-hnat-flow-prereqs-56.sh <official-prepared-source> <6.12-donor>}"
DONOR="${2:?usage: install-hnat-flow-prereqs-56.sh <official-prepared-source> <6.12-donor>}"

PATCH_DIR="$SOURCE/target/linux/mediatek/patches-6.12"
DONOR_PATCH_DIR="$DONOR/target/linux/mediatek/patches-6.12"
HNAT_H="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat/hnat.h"
HNAT_DEBUGFS="$SOURCE/target/linux/mediatek/files-6.12/drivers/net/ethernet/mediatek/mtk_hnat/hnat_debugfs.c"

# The standalone MediaTek HNAT driver is not self-contained: its virtual-path
# code relies on the donor's small nf_flow_table/net_device plumbing for VLAN,
# bridge, PPPoE, DSA and macvlan. Carry the coherent flow-path series, the
# required net_device path progression, and the matching offload-stat callbacks.
# Do not import unrelated donor Ethernet/DSA/PHY/PPE trees.
patches=(
  999-hnat-03-netfilter-nf_flow_table-support-hw-offload-through-v.patch
  999-hnat-04-net-8021q-support-hardware-flow-table-offload.patch
  999-hnat-05-net-bridge-support-hardware-flow-table-offload.patch
  999-hnat-06-net-pppoe-support-hardware-flow-table-offload.patch
  999-hnat-07-net-dsa-support-hardware-flow-table-offload.patch
  999-hnat-08-net-macvlan-support-hardware-flow-table-offload.patch
  999-hnat-09-mtkhnat-add-support-for-virtual-interface-acceleration.patch
  999-hnat-14-net-vlan-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch
  999-hnat-15-ppp-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch
  999-net-01-netdevice-add-macvlan-device-path-type.patch
  999-net-02-netdevice-add-dslite-device-path-type.patch
  999-net-03-netdevice-add-tnl-device-path-type.patch
  999-net-04-netdevice-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch
  999-tnl-01-mtk-tunnel-offload-support.patch
)

for patch in "${patches[@]}"; do
  src="$DONOR_PATCH_DIR/$patch"
  dst="$PATCH_DIR/$patch"
  test -f "$src" || { echo "missing donor HNAT prerequisite: $src" >&2; exit 1; }
  install -m0644 "$src" "$dst"
done

test -f "$HNAT_H"
test -f "$HNAT_DEBUGFS"

# The net_device path patches are a strict donor sequence:
#   MACVLAN -> DSLITE/6RD -> TNL -> offload-stat callback ABI.
# Keep the matching VLAN/PPP callback implementations so hardware-offloaded
# traffic remains visible in their software statistics instead of compiling a
# dead callback slot with no consumers.
for patch in \
  999-net-01-netdevice-add-macvlan-device-path-type.patch \
  999-net-02-netdevice-add-dslite-device-path-type.patch \
  999-net-03-netdevice-add-tnl-device-path-type.patch \
  999-net-04-netdevice-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch \
  999-hnat-14-net-vlan-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch \
  999-hnat-15-ppp-add-ndo_flow_offload_stats64_add-for-offload-stats-correction.patch; do
  test -f "$PATCH_DIR/$patch"
done

# Two compile-only donor assumptions live in unrelated broad patch families:
# - MXL862 DSA tag support (not used by N60 Pro)
# - the PPPQ queue-index mask (16 queues on this MT7986 baseline)
# Localize those assumptions inside the standalone HNAT source instead of
# importing the MXL862 DSA stack or the donor PPPQ/shaper Ethernet series.
python3 - "$HNAT_H" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
marker = "N60PRO_HWACCEL_56_HNAT_SOURCE_COMPAT"

if marker not in s:
    guard = "#define NF_HNAT_H\n"
    if s.count(guard) != 1:
        raise SystemExit(f"unexpected NF_HNAT_H guard count: {s.count(guard)}")
    compat = r'''#define NF_HNAT_H

/* N60PRO_HWACCEL_56_HNAT_SOURCE_COMPAT
 * Keep donor-only PPPQ/MXL862 prerequisites out of the official Ethernet/DSA
 * baseline. MT7986 uses 16 QDMA queues, hence the queue-index mask is 0x0f.
 */
#ifndef MTK_QDMA_QUEUE_MASK
#define MTK_QDMA_QUEUE_MASK 0x0f
#endif
'''
    s = s.replace(guard, compat, 1)

lines = s.splitlines()
start = next((i for i, line in enumerate(lines)
              if line.startswith("#define IS_DSA_TAG_PROTO_8021Q(dp)")), None)
if start is None:
    raise SystemExit("IS_DSA_TAG_PROTO_8021Q macro not found")

# If the pristine donor's MXL862-only alternative is still present, remove only
# that alternative. N60 Pro keeps the standard DSA_TAG_PROTO_8021Q path.
window = "\n".join(lines[start:start + 4])
if "DSA_TAG_PROTO_MXL862_8021Q" in window:
    end = start + 1
    while end < len(lines) and lines[end - 1].rstrip().endswith("\\"):
        end += 1
    replacement = [
        "#define IS_DSA_TAG_PROTO_8021Q(dp)\\",
        "\t(dp->cpu_dp->tag_ops->proto == DSA_TAG_PROTO_8021Q)",
    ]
    lines[start:end] = replacement
    s = "\n".join(lines) + "\n"
elif "DSA_TAG_PROTO_8021Q" not in window:
    raise SystemExit("unexpected DSA tag compatibility macro shape")

if marker not in s:
    raise SystemExit("HNAT source compat marker missing after edit")
if "DSA_TAG_PROTO_MXL862_8021Q" in s:
    raise SystemExit("MXL862-only DSA tag dependency survived compatibility edit")
if s.count("#define MTK_QDMA_QUEUE_MASK 0x0f") != 1:
    raise SystemExit("QDMA queue mask compatibility definition count != 1")

p.write_text(s)
PY

# The donor HNAT debugfs file carries an include of mtk_eth_dbg.h even though
# it does not use the proprietary Ethernet debugfs API. That header is created
# only by donor patch 999-eth-90, which also replaces/extends thousands of lines
# in the Ethernet debug stack and has its own PPPQ dependencies. Keep the
# official 25.12.1 Ethernet implementation and remove only this stale include.
python3 - "$HNAT_DEBUGFS" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
include = '#include "../mtk_eth_dbg.h"\n'
marker = 'N60PRO_HWACCEL_56_HNAT_DEBUGFS_COMPAT'

if marker not in s:
    if s.count(include) != 1:
        raise SystemExit(f"unexpected mtk_eth_dbg.h include count: {s.count(include)}")
    s = s.replace(
        include,
        '/* N60PRO_HWACCEL_56_HNAT_DEBUGFS_COMPAT: donor Ethernet debugfs header is unused here. */\n',
        1,
    )

if marker not in s:
    raise SystemExit("HNAT debugfs compatibility marker missing after edit")
if 'mtk_eth_dbg.h' in s:
    raise SystemExit("donor mtk_eth_dbg.h dependency survived HNAT debugfs compatibility edit")

p.write_text(s)
PY

for patch in "${patches[@]}"; do
  test -f "$PATCH_DIR/$patch"
done
grep -q 'N60PRO_HWACCEL_56_HNAT_SOURCE_COMPAT' "$HNAT_H"
! grep -q 'DSA_TAG_PROTO_MXL862_8021Q' "$HNAT_H"
grep -qx '#define MTK_QDMA_QUEUE_MASK 0x0f' "$HNAT_H"
grep -q 'N60PRO_HWACCEL_56_HNAT_DEBUGFS_COMPAT' "$HNAT_DEBUGFS"
! grep -q 'mtk_eth_dbg.h' "$HNAT_DEBUGFS"

echo "#56 HNAT flow-path prerequisites + netdev/stat ABI + N60 Pro source/debugfs compat: OK"
