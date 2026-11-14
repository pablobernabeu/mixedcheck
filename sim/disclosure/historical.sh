#!/bin/sh
# Runs the disclosure-attack tests against the R package as it was at an
# earlier commit (sim/disclosure/README.md, the historical check). The
# package's files at that commit are read with git archive into a scratch
# directory and installed there, so that the working tree and its git state
# do not change.
#
#   sh sim/disclosure/historical.sh COMMIT SCRATCH [run.R options]
#
# SCRATCH must be a new or empty directory, such as one under /dev/shm.
set -eu
commit=$1
scratch=$2
shift 2
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$scratch/src" "$scratch/lib"
git -C "$root" archive "$commit" r | tar -x -C "$scratch/src"
R CMD INSTALL --no-test-load -l "$scratch/lib" "$scratch/src/r" > "$scratch/install.log" 2>&1
Rscript "$root/sim/disclosure/run.R" --lib "$scratch/lib" --no-fail \
  --out "$scratch/report-$commit.rds" "$@"
