#!/bin/bash
# H0: build the R library and the Python environments for the pilot inside the R image,
# then write the lockfile. Reads no data. Submit from ~/mixedcheck-h0 on ARC:
#   sbatch --job-name=mixedcheck-h0-build h0_build.sbatch
#
# R packages come from a dated Posit Package Manager snapshot. Python is a standalone
# CPython installed by uv (unpacked binary, no installer), and the environments are
# created and used inside the image, so that rpy2 loads the image's R and the library below.
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
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
         "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$R_USER_CACHE_DIR" "$TMPDIR" "$UV_CACHE_DIR" \
         "$UV_PYTHON_INSTALL_DIR" "$H0/bin" "$H0/envs" "$H0/lib" "$H0/lock" "$H0/home"

DIGEST=sha256:1ca5bfbc810a4e176d74e05267a670e84de86b23a4a5791fa06862bfa35369ba
export SIF=$H0/images/rocker-r-ver-4.6.2-${DIGEST:7:12}.sif
export SNAP=2026-11-20                          # Posit Package Manager snapshot date
export EXCLUDE_NEWER=2026-11-21T00:00:00Z       # the same day for PyPI
export RLIB=$H0/lib/R-4.6.2-p3m-$SNAP
export ENVS=$H0/envs
export PYVER=3.12                               # as the earlier benchmark's venv312
export NCPUS=${SLURM_CPUS_PER_TASK:-1}
export LC_ALL=C.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
mkdir -p "$RLIB"

# uv 0.13.9 (released 2026-11-17), checked against the release's published SHA-256.
UV_VERSION=0.13.9
UV_SHA256=a7fbaff2b9a271d85c1bdb540941090fd1ce011797b4abeb48e4dcd39c2471d5
if [ ! -x "$H0/bin/uv" ]; then
  curl -fsSL -o "$TMPDIR/uv.tar.gz" \
    "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz"
  echo "$UV_SHA256  $TMPDIR/uv.tar.gz" | sha256sum -c -
  tar -xzf "$TMPDIR/uv.tar.gz" -C "$TMPDIR"
  cp "$TMPDIR/uv-x86_64-unknown-linux-gnu/uv" "$TMPDIR/uv-x86_64-unknown-linux-gnu/uvx" "$H0/bin/"
fi
export PATH=$H0/bin:$PATH
uv --version

run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" "$@"; }

echo "== R library ($(date -Is))"
run Rscript --vanilla - <<'EOF'
lib <- Sys.getenv("RLIB"); snap <- Sys.getenv("SNAP")
os <- readLines("/etc/os-release")
codename <- sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", os, value = TRUE))
repo <- sprintf("https://p3m.dev/cran/__linux__/%s/%s", codename, snap)
# Posit Package Manager serves Linux binaries only to clients that name their R and platform.
options(repos = c(CRAN = repo), Ncpus = as.integer(Sys.getenv("NCPUS")),
        HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
                                paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))
.libPaths(c(lib, .libPaths()))
cat("repo:", repo, "\nlibPaths:", .libPaths(), sep = "\n")
pkgs <- c("lme4", "glmmTMB", "lmerTest", "pbkrtest", "clubSandwich", "jsonlite")
# The snapshot is fixed, so a library that already holds every package is left as it is.
if (!all(pkgs %in% rownames(installed.packages(lib.loc = lib)))) {
  install.packages(pkgs, lib = lib, dependencies = c("Depends", "Imports", "LinkingTo"))
}
for (p in c(pkgs, "Matrix", "MASS")) {
  suppressPackageStartupMessages(library(p, character.only = TRUE))
  cat(sprintf("%-14s %-10s %s\n", p, as.character(packageVersion(p)), dirname(find.package(p))))
}
stopifnot(packageVersion("lme4") >= "2.1-0", packageVersion("glmmTMB") >= "1.1.15")
EOF

echo "== Python environments ($(date -Is))"
# Apptainer does not pass the host's PATH into the container, so uv is called by its path.
export UV=$H0/bin/uv
run bash -euo pipefail -c '
  "$UV" python install "$PYVER"
  "$UV" venv --clear --python "$PYVER" "$ENVS/venv312"
  "$UV" pip install --python "$ENVS/venv312/bin/python" --exclude-newer "$EXCLUDE_NEWER" \
      numpy pandas scipy statsmodels mixedlm glmm gpboost
  "$UV" venv --clear --python "$PYVER" "$ENVS/venv_pymer4"
  "$UV" pip install --python "$ENVS/venv_pymer4/bin/python" --exclude-newer "$EXCLUDE_NEWER" \
      numpy pandas scipy rpy2
  "$ENVS/venv312/bin/python" -I -c "import statsmodels, mixedlm, glmm, gpboost, sys; print(sys.version.split()[0], statsmodels.__version__, mixedlm.__version__ if hasattr(mixedlm, \"__version__\") else \"\", gpboost.__version__)"
  # The image builds R from source and does not register libR.so with the linker, so an
  # embedded R (rpy2) needs R'"'"'s lib directory on LD_LIBRARY_PATH.
  R_LIBS="$RLIB" R_HOME="$(R RHOME)" LD_LIBRARY_PATH="$(R RHOME)/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$ENVS/venv_pymer4/bin/python" -I -c "import rpy2, rpy2.robjects as ro; from rpy2.robjects.packages import importr; importr(\"lme4\"); print(\"rpy2\", rpy2.__version__, \"R\", ro.r(\"R.version.string\")[0], \"lme4\", ro.r(\"as.character(packageVersion(\\\"lme4\\\"))\")[0])"
'

echo "== lockfile ($(date -Is))"
LOCK=$H0/lock/h0-lock-$SNAP.csv
run Rscript --vanilla - <<'EOF'
lib <- Sys.getenv("RLIB"); snap <- Sys.getenv("SNAP"); sif <- Sys.getenv("SIF")
os <- readLines("/etc/os-release")
codename <- sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", os, value = TRUE))
ip <- installed.packages(lib.loc = c(lib, .libPaths()), fields = "Repository")
ip <- ip[!duplicated(ip[, "Package"]), , drop = FALSE]   # first on the search path wins
src <- ifelse(ip[, "LibPath"] == lib,
              sprintf("Posit Package Manager https://p3m.dev/cran/__linux__/%s/%s", codename, snap),
              ifelse(is.na(ip[, "Priority"]), "image (site library)",
                     sprintf("image (%s)", ip[, "Priority"])))
out <- data.frame(environment = "R", language = "R", package = ip[, "Package"],
                  version = ip[, "Version"], source = src, row.names = NULL)
write.csv(out[order(out$package), ], file.path(dirname(lib), "..", "lock", "r-part.csv"), row.names = FALSE)
EOF
{
  echo "environment,language,package,version,source"
  tail -n +2 "$H0/lock/r-part.csv"
  for env in venv312 venv_pymer4; do
    py=$("$ENVS/$env/bin/python" -I -c "import sys; print(sys.version.split()[0])")
    echo "\"$env\",\"Python\",\"python\",\"$py\",\"CPython standalone build installed by uv $UV_VERSION\""
    uv pip list --python "$ENVS/$env/bin/python" --format freeze \
      | awk -F'==' -v e="$env" -v d="$EXCLUDE_NEWER" '{printf "\"%s\",\"Python\",\"%s\",\"%s\",\"PyPI, uploaded before %s\"\n", e, $1, $2, d}'
  done
} > "$LOCK"
rm -f "$H0/lock/r-part.csv"
echo "image,rocker/r-ver:4.6.2@$DIGEST" > "$H0/lock/h0-image.txt"
echo "snapshot,$SNAP" >> "$H0/lock/h0-image.txt"
wc -l "$LOCK"
grep -E '"(lme4|glmmTMB|lmerTest|pbkrtest|clubSandwich|Matrix|statsmodels|mixedlm|glmm|gpboost|rpy2|python)"' "$LOCK"

rm -rf "$TMPDIR"
echo "== done $(date -Is)"
