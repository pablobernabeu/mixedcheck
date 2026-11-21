#!/bin/bash
# H0: re-time fits with the current lme4 and glmmTMB. Runs, unchanged, F/timing/time_grid.R
# (lme4, glmmTMB, lmerTest and pbkrtest over a grid, with its own 780 s budget), F/timing/time_grid2.R
# (540 s budget, four concurrent fits for throughput, hence four CPUs) and
# A-verify/scripts/lme4_timing.R on the benchmark's crossed datasets.
# Reads only simulated data (the grids simulate their own; crossed and crossedbig come from step 1
# of the benchmark).
#   sbatch --job-name=mixedcheck-h0-timing --dependency=afterok:<benchmark step 1> h0_timing.sbatch
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
RUN=$H0/runs/h0-2026-11-21/decisions
export R_LIBS=$H0/lib/R-4.6.2-p3m-$SNAP R_LIBS_USER=$H0/lib/R-4.6.2-p3m-$SNAP
export LC_ALL=C.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 FLEXIBLAS_NUM_THREADS=1
run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" "$@"; }

echo "== $(hostname) $(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //') $(date -Is)"
T=$RUN/F/timing
mkdir -p "$T/out_h0"
cd "$T"
echo "== time_grid.R $(date -Is)";  run Rscript --vanilla time_grid.R "$T/out_h0"
echo "== time_grid2.R $(date -Is)"; run Rscript --vanilla time_grid2.R "$T/out_h0"
echo "== lme4_timing.R $(date -Is)"
run Rscript --vanilla "$RUN/A-verify/scripts/lme4_timing.R" "$RUN/A/bench/data" | tee "$T/out_h0/lme4_timing.txt"
ls -l "$T/out_h0"
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
