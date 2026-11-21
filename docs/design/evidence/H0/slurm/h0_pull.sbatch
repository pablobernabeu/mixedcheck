#!/bin/bash
# H0: pull the R image by digest into the project space and record what it contains.
# Reads no data. Submit from ~/mixedcheck-h0 on ARC:
#   sbatch --job-name=mixedcheck-h0-pull h0_pull.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=logs/%x-%j.out

set -euo pipefail

H0=/data/educ-intract/educ1242/mixedcheck-h0
export APPTAINER_CACHEDIR=$H0/cache/apptainer
export APPTAINER_TMPDIR=$H0/tmp/apptainer
export PIP_CACHE_DIR=$H0/cache/pip
export PYTHONUSERBASE=$H0/pyuserbase
export XDG_CACHE_HOME=$H0/cache/xdg
export XDG_DATA_HOME=$H0/share
export R_USER_CACHE_DIR=$H0/cache/R
export TMPDIR=$H0/tmp/job-${SLURM_JOB_ID:-manual}
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$PIP_CACHE_DIR" "$PYTHONUSERBASE" \
         "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$R_USER_CACHE_DIR" "$TMPDIR" "$H0/images" "$H0/home"

# rocker/r-ver:4.6.2, linux/amd64 manifest, read from Docker Hub on 21 November 2026.
DIGEST=sha256:1ca5bfbc810a4e176d74e05267a670e84de86b23a4a5791fa06862bfa35369ba
SIF=$H0/images/rocker-r-ver-4.6.2-${DIGEST:7:12}.sif   # first 12 hex digits of the digest

if [ ! -s "$SIF" ]; then
  apptainer pull "$SIF" "docker://rocker/r-ver@$DIGEST"
fi
ls -l "$SIF"
sha256sum "$SIF"

# What the image provides, run with a home under the project space.
apptainer exec --home "$H0/home" "$SIF" bash -c '
  . /etc/os-release; echo "OS: $PRETTY_NAME ($VERSION_CODENAME)"
  R --version | head -1
  echo "R_HOME=$(R RHOME)"
  ls "$(R RHOME)/lib" | grep -E "libR\.so" || echo "no libR.so"
  Rscript -e "cat(\"repos:\", getOption(\"repos\"), \"\n\"); print(rownames(installed.packages(priority = \"recommended\")))"
  for c in python3 gcc g++ gfortran make cmake pkg-config; do printf "%s: " "$c"; command -v "$c" || echo missing; done
'
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
