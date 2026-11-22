#!/bin/bash
# H0 benchmark, step 2: run each Python engine on all 27 benchmark models with
# A/bench/drive.py, unchanged apart from the R_HOME path set in step 1. One array task per engine.
# Reads the datasets written by step 1 (simulated, and the lme4 and glmmTMB examples).
#   sbatch --job-name=mixedcheck-h0-bench-py --array=1-6 --dependency=afterok:<step 1> h0_bench_py.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH --output=logs/%x-%A_%a.out

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
SNAP=2026-11-20
ENVS=$H0/envs
RUN=$H0/runs/h0-2026-11-21/decisions
export R_LIBS=$H0/lib/R-4.6.2-p3m-$SNAP R_LIBS_USER=$H0/lib/R-4.6.2-p3m-$SNAP
export LC_ALL=C.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 FLEXIBLAS_NUM_THREADS=1
# The image's R is built from source and its libR.so is not registered with the linker, so the
# rpy2 engine's embedded R needs R's lib directory on LD_LIBRARY_PATH (Ubuntu's own R needs none).
run() { apptainer exec --home "$H0/home" --bind "$H0" \
          --env LD_LIBRARY_PATH=/usr/local/lib/R/lib:/.singularity.d/libs "$SIF" "$@"; }

ENGINES=(statsmodels mixedlm glmm gpboost gpboost_chol rpy2_lme4)
ENGINE=${ENGINES[$((SLURM_ARRAY_TASK_ID - 1))]}
echo "== $ENGINE on $(hostname) $(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //') $(date -Is)"

cd "$RUN/A/bench"
run "$ENVS/venv312/bin/python" -I drive.py "$ENGINE" all
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
