#!/bin/bash
# H0: collect the V1 pilot chunks with evidence/decisions/F/slurm/collect.R, unchanged.
# Reads the chunk outputs of the V1 array (simulated data only).
#   sbatch --job-name=mixedcheck-h0-v1-collect --dependency=afterany:<V1 array> h0_v1_collect.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:15:00
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
export CONDA_PKGS_DIRS=$H0/conda/pkgs
export CONDA_ENVS_PATH=$H0/conda/envs
export MAMBA_ROOT_PREFIX=$H0/micromamba
export UV_CACHE_DIR=$H0/cache/uv
export UV_PYTHON_INSTALL_DIR=$H0/python
export JULIA_DEPOT_PATH=$H0/julia/depot
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$PIP_CACHE_DIR" "$PYTHONUSERBASE" \
         "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$R_USER_CACHE_DIR" "$TMPDIR" "$H0/home"

DIGEST=sha256:1ca5bfbc810a4e176d74e05267a670e84de86b23a4a5791fa06862bfa35369ba
SIF=$H0/images/rocker-r-ver-4.6.2-${DIGEST:7:12}.sif
RUN=$H0/runs/h0-2026-11-21/decisions
export LC_ALL=C.UTF-8
run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" "$@"; }

STUDY=V1a-pilot
run Rscript --vanilla "$RUN/F/slurm/collect.R" "$RUN/F/slurm/pilot_V1a" "$H0/results/$STUDY" \
    "$H0/results/${STUDY}_summary.csv"
cat "$H0/results/$STUDY"/*.json | grep -o '"node":"[^"]*","cpu":"[^"]*","R":"[^"]*"' | sort | uniq -c
grep -ho '"packages":"[^"]*"' "$H0/results/$STUDY"/*.json | sort | uniq -c
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
