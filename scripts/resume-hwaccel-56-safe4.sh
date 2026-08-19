#!/usr/bin/env bash
set -euo pipefail

# Local WSL safety wrapper for 32 GiB Windows hosts.
# LLVM/Clang host-tool bootstrap can exhaust RAM when the main gate inherits
# all logical CPUs from nproc. Keep the entire resume at four make jobs so the
# existing build/download/staging cache is reused without memory thrashing.
# This changes only local build parallelism; it does not change firmware config,
# source, packages, RF behavior, networking, or generated binaries.

export JOBS="${JOBS:-4}"

echo "#56 safe local resume: JOBS=$JOBS"
exec bash "$(cd "$(dirname "$0")" && pwd)/resume-hwaccel-56-after-hnat-reject.sh"
