#!/bin/bash
# H0: rerun the random-effects simulations of evidence/decisions/B/sim (Sim 1 to 6) with the
# current engines, in the order of run_sim1_small.sh, run_queue2.sh and run_queue3.sh, then the
# summaries. The scripts run unchanged apart from their hard-coded /tmp root, which is replaced
# by the path of the copy. Reads only data that the scripts simulate.
# The scripts call mclapply with mc.cores = 4, hence four CPUs.
#   sbatch --job-name=mixedcheck-h0-bsim h0_bsim.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=medium
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=24:00:00
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
S=$RUN/B/sim
# The scripts hard-code the /tmp root of the environment where they first ran
# (evidence/decisions/README.md); that root ends in /r2/B/sim and is matched by pattern.
OLDRE='/tmp/[^"'"'"' ]*/r2/B/sim'
sed -i -E "s#$OLDRE#$S#g" "$S"/*.sh "$S"/*.R
grep -lE "$OLDRE" "$S"/*.sh "$S"/*.R || echo "no hard-coded /tmp root left"

# Keep the repository's summaries apart; the scripts write into out/.
if [ ! -d "$S/out_repo" ]; then mv "$S/out" "$S/out_repo"; fi
mkdir -p "$S/out"
cd "$S"

stamp() { echo "== $1 $(date -Is)"; }
stamp sim1_small; run bash run_sim1_small.sh
stamp queue2;     run bash run_queue2.sh
stamp queue3;     run bash run_queue3.sh
stamp sim4;       run Rscript sim4_zcp_coding.R   > out/sim4_zcp_coding.txt   2> out/sim4.err
stamp sim5;       run Rscript sim5_reml_masking.R > out/sim5_reml_masking.txt 2> out/sim5.err
stamp sim6;       run Rscript sim6_singular_df.R  > out/sim6_singular_df.txt  2> out/sim6.err

stamp summaries
run Rscript summarise_sim1.R '^sim1_S24_I16_.*\.csv$' "$S/out"
mv out/sim1_summary.csv out/sim1_summary_small.csv
run Rscript summarise_sim1.R '^sim1_S48_I32_.*\.csv$' "$S/out"
mv out/sim1_summary.csv out/sim1_summary_large.csv
run Rscript summarise_sim1.R '^sim1_S24_I16_.*\.csv$' "$S/out/rerun"
run Rscript summarise_sim23.R > out/sim23_summary.txt
ls -l out out/rerun
rm -rf "$TMPDIR"
stamp done
