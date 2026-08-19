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

# The latest compile proved the standalone HNAT source needs the donor's narrow
# virtual flow-path ABI (VLAN/bridge/PPPoE/DSA/macvlan) plus two tiny tunnel-path
# declarations. Install only those prerequisites before the existing resume
# reapplies the HNAT Ethernet patch and cleans target/linux.
bash "$BUILDER/scripts/install-hnat-flow-prereqs-56.sh" "$SOURCE" "$DONOR"

exec bash "$BUILDER/scripts/resume-hwaccel-56-after-hnat-reject.sh"
