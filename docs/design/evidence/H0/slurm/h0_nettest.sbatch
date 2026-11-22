#!/bin/bash
# H0 environment check on an htc compute node: Apptainer runtime, CPU, scratch and
# outbound network access to the hosts that the image pull and the library builds need.
# Reads no data. Submit from ~/mixedcheck-h0 on ARC:
#   sbatch --job-name=mixedcheck-h0-nettest h0_nettest.sbatch
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:10:00
#SBATCH --output=logs/%x-%j.out

set -uo pipefail

# Keep caches, image layers and temporary files out of the ARC home.
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
         "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$R_USER_CACHE_DIR" "$TMPDIR"

echo "== node"
hostname
date -Is
grep -m1 'model name' /proc/cpuinfo
nproc
echo "SLURM_CPUS_ON_NODE=${SLURM_CPUS_ON_NODE:-} SLURM_JOB_CPUS_PER_NODE=${SLURM_JOB_CPUS_PER_NODE:-}"
echo "SCRATCH=${SCRATCH:-unset}"
[ -n "${SCRATCH:-}" ] && df -h "$SCRATCH" | tail -1

echo "== apptainer"
if command -v apptainer >/dev/null 2>&1; then
  command -v apptainer
  apptainer --version
else
  echo "apptainer not on PATH; trying modules"
  module -t avail 2>&1 | grep -iE 'apptainer|singularity' || echo "no apptainer or singularity module"
fi
command -v singularity && singularity --version

echo "== outbound network (HTTP status, seconds)"
for url in \
  https://packagemanager.posit.co/ \
  https://p3m.dev/cran/latest/src/contrib/PACKAGES \
  https://registry-1.docker.io/v2/ \
  https://auth.docker.io/token \
  https://cloud.r-project.org/ \
  https://pypi.org/simple/ \
  https://conda.anaconda.org/conda-forge/noarch/repodata.json \
  https://github.com/ \
  https://julialang-s3.julialang.org/ ; do
  printf '%s ' "$url"
  curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 20 -r 0-0 "$url" 2>&1 | tail -1
done

rm -rf "$TMPDIR"
echo "== done $(date -Is)"
