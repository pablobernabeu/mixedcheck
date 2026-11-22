#!/bin/bash
# H0: the six-task array of the V1 pilot (evidence/decisions/F/slurm/pilot_V1a with run_task.R),
# adapted from F/slurm/lmc_array.sbatch. Only job settings differ from the template: the R
# image and the H0 library in place of the R module, paths under the project space (the
# working directory replaces $SCRATCH, which is the shared /scratch on ARC), no --mail-type,
# and no CPU-generation constraint (03-execution-plan.md, M6: the image is portable).
# Reads only data that study.R simulates.
#   sbatch --job-name=mixedcheck-h0-v1 --array=1-6 h0_v1.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=00:30:00
#SBATCH --signal=B:SIGINT@180
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
RUN=$H0/runs/h0-2026-11-21/decisions
export R_LIBS=$H0/lib/R-4.6.2-p3m-$SNAP R_LIBS_USER=$H0/lib/R-4.6.2-p3m-$SNAP
export LC_ALL=C.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 FLEXIBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" "$@"; }

STUDY=V1a-pilot
CODE=$RUN/F/slurm
STUDY_DIR=$CODE/pilot_V1a
RESULTS=$H0/results/$STUDY
WORK=$H0/scratch/${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}
mkdir -p "$RESULTS" "$WORK/out"
cd "$WORK"
trap 'echo "SIGINT: saving completed chunks"; rsync -a --exclude="*.part" out/ "$RESULTS/"; exit 2' INT
rsync -a --include='*/' --include='*.csv' --include='*.json' --exclude='*' "$RESULTS/" out/ 2>/dev/null || true

rc=0
run Rscript --vanilla "$CODE/run_task.R" "$STUDY_DIR" "$SLURM_ARRAY_TASK_ID" "$WORK/out" &
wait $! || rc=$?
rsync -a --exclude="*.part" out/ "$RESULTS/"
echo "done: $STUDY task $SLURM_ARRAY_TASK_ID rc=$rc on $(hostname) $(date -Is)"
rm -rf "$WORK" "$TMPDIR"
exit $rc
