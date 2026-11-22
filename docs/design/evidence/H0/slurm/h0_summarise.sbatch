#!/bin/bash
# H0: build the summary tables that compare the pilot runs with the earlier evidence runs,
# with docs/design/evidence/H0/scripts/summarise_h0.py from the copy of the repository in the
# project space. Reads the outputs of the H0 runs and the earlier outputs stored in the
# evidence (simulated data and benchmark results only). Can be rerun as more runs finish.
#   sbatch --job-name=mixedcheck-h0-summarise h0_summarise.sbatch
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
REPO=/data/educ-intract/educ1242/mixedcheck
run() { apptainer exec --home "$H0/home" --bind "$H0" --bind "$REPO" "$SIF" "$@"; }

run "$H0/envs/venv312/bin/python" -I "$REPO/docs/design/evidence/H0/scripts/summarise_h0.py" \
    "$H0/runs/h0-2026-11-21/decisions" "$H0/results" "$H0/summaries"
ls -l "$H0/summaries"
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
