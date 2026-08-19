#!/usr/bin/env bash
set -euo pipefail

# Local WSL safety wrapper for 32 GiB Windows hosts.
# LLVM/Clang host-tool bootstrap can exhaust RAM when the main gate inherits
# all logical CPUs from nproc. Keep the entire resume at four make jobs so the
# existing build/download/staging cache is reused without memory thrashing.
# This changes only local build parallelism; it does not change firmware config,
# source, packages, RF behavior, networking, or generated binaries.

export JOBS="${JOBS:-4}"

BUILDER="$(cd "$(dirname "$0")/.." && pwd)"
WORKROOT="${N60PRO_WORKROOT:-$HOME/n60pro-hwaccel-56-work}"
SOURCE="$WORKROOT/source"
DONOR="$WORKROOT/mtk-donor"

echo "#56 safe local resume: JOBS=$JOBS"

# The HNAT/WARP vendor path uses the shared MediaTek ra_nat.h skb metadata ABI.
# The donor keeps this as a target files-6.12 kernel header; copy that exact
# header into the official source overlay before target/linux is cleaned and
# rebuilt so both HNAT and WARP compile against the same ABI.
RA_NAT_SRC="$DONOR/target/linux/mediatek/files-6.12/include/net/ra_nat.h"
RA_NAT_DST="$SOURCE/target/linux/mediatek/files-6.12/include/net/ra_nat.h"
test -f "$RA_NAT_SRC" || { echo "missing donor ra_nat.h: $RA_NAT_SRC" >&2; exit 1; }
mkdir -p "$(dirname "$RA_NAT_DST")"
install -m0644 "$RA_NAT_SRC" "$RA_NAT_DST"
test -f "$RA_NAT_DST"
echo "#56 shared HNAT/WARP ra_nat.h ABI: OK"

# Install the coherent HNAT flow-path prerequisites before the existing resume
# reapplies the HNAT Ethernet patch and cleans target/linux.
bash "$BUILDER/scripts/install-hnat-flow-prereqs-56.sh" "$SOURCE" "$DONOR"

exec bash "$BUILDER/scripts/resume-hwaccel-56-after-hnat-reject.sh"
