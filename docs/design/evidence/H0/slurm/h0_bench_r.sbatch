#!/bin/bash
# H0 benchmark, step 1: regenerate the benchmark datasets and refit the R reference
# (lme4 and glmmTMB) with the current engines, by running A/bench/r_reference.R unchanged.
# Reads the benchmark's simulated datasets and the lme4 and glmmTMB example datasets
# (sleepstudy, Penicillin, Pastes, cbpp, Owls) that r_reference.R loads.
# Runs in the copy of evidence/decisions under the project space, never in the clone.
#   sbatch --job-name=mixedcheck-h0-bench-r h0_bench_r.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
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
ENVS=$H0/envs
RUN=$H0/runs/h0-2026-11-21/decisions
export R_LIBS=$H0/lib/R-4.6.2-p3m-$SNAP R_LIBS_USER=$H0/lib/R-4.6.2-p3m-$SNAP
export LC_ALL=C.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 FLEXIBLAS_NUM_THREADS=1
run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" "$@"; }

echo "== $(hostname) $(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //') $(date -Is)"
B=$RUN/A/bench

# Path change: drive.py points R_HOME at /usr/lib/R; the image's R home is /usr/local/lib/R.
sed -i 's#R_HOME="/usr/lib/R"#R_HOME="/usr/local/lib/R"#' "$B/drive.py"
grep -n 'R_HOME=' "$B/drive.py"
# drive.py looks for its interpreters at ../venv312 and ../venv_pymer4.
ln -sfn "$ENVS/venv312" "$RUN/A/venv312"
ln -sfn "$ENVS/venv_pymer4" "$RUN/A/venv_pymer4"

# Keep the repository's outputs for comparison before the rerun overwrites them.
if [ ! -d "$B/repo_copy" ]; then
  mkdir -p "$B/repo_copy"
  cp -a "$B/data" "$B/r_reference.json" "$B/comparison_rows.json" "$B/benchmark_table.csv" \
        "$B/benchmark_table.md" "$B/engine_summary.md" "$B/repo_copy/"
fi

cd "$B"
run Rscript r_reference.R "$B"

echo "== regenerated datasets against the repository's copies"
for f in repo_copy/data/*.csv; do
  n=$(basename "$f")
  if cmp -s "$f" "data/$n"; then echo "identical: $n"; else echo "DIFFERS: $n"; fi
done
ls -l data/
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
