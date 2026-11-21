#!/bin/bash
# H0, A8: does lme4 2.x install on R 4.2.0, 4.2.2, 4.2.3 and 4.3.3 with the Matrix that each
# R release bundles? One array task per R version, each in a rocker/r-ver image pulled by
# digest. Reads no project data; the load test fits lme4's own example data (sleepstudy).
# Submit from ~/mixedcheck-h0 on ARC:
#   sbatch --job-name=mixedcheck-h0-a8-rversions h0_a8_rversions.sbatch
#
# Attempt 1 installs the snapshot's lme4 and its missing dependencies into an empty library,
# with R's own library (and so its bundled Matrix) behind it and the site library left out.
# Only if attempt 1 fails does attempt 2, in a fresh R process, add the snapshot's Matrix,
# to tell a Matrix requirement apart from other causes. Results: $OUT/a8_<R version>.tsv.
#SBATCH --clusters=htc
#SBATCH --account=educ-intract
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --array=1-4
#SBATCH --output=logs/%x-%A_%a.out

set -euo pipefail

H0=/data/educ-intract/educ1242/mixedcheck-h0
export APPTAINER_CACHEDIR=$H0/cache/apptainer
export APPTAINER_TMPDIR=$H0/tmp/apptainer
export XDG_CACHE_HOME=$H0/cache/xdg
export R_USER_CACHE_DIR=$H0/cache/R
export TMPDIR=$H0/tmp/job-${SLURM_JOB_ID:-manual}-${SLURM_ARRAY_TASK_ID:-0}
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$XDG_CACHE_HOME" "$R_USER_CACHE_DIR" \
         "$TMPDIR" "$H0/images" "$H0/home"

# rocker/r-ver linux/amd64 manifests, read from Docker Hub's tag API on 21 November 2026.
TAGS=(4.2.0 4.2.2 4.2.3 4.3.3)
DIGESTS=(
  sha256:53e27eaf50320246234dc960c19143161797b721b67d69f4fd4c2a5157b23b54
  sha256:5a588f124f4108c56f874bce244e252c641b49f23c32a0b55f5fad67269929d5
  sha256:22202dfb31f3a1b515936bac559a9f56b67585adce2c14d063f97478940d374a
  sha256:20ede1f846d2423b483b1019a499cc0f8c1d15192f47812c92d0900af4029039
)
i=$(( ${SLURM_ARRAY_TASK_ID:-1} - 1 ))
TAG=${TAGS[$i]}
DIGEST=${DIGESTS[$i]}
SIF=$H0/images/rocker-r-ver-$TAG-${DIGEST:7:12}.sif
export SNAP=2026-11-20                          # the same Posit Package Manager snapshot as the pilot
export OUT=$H0/results/A8
export TAG NCPUS=${SLURM_CPUS_PER_TASK:-1} LC_ALL=C.UTF-8
mkdir -p "$OUT" "$H0/lib/a8"
rm -rf "$H0/lib/a8/R-$TAG-attempt1" "$H0/lib/a8/R-$TAG-attempt2"   # libraries of this script only

echo "== $(hostname) $(date -Is) R $TAG $DIGEST"
if [ ! -s "$SIF" ]; then
  apptainer pull "$SIF" "docker://rocker/r-ver@$DIGEST"
fi
sha256sum "$SIF"

# One attempt per R process: Rscript a8.R ATTEMPT (1 = bundled Matrix, 2 = snapshot Matrix).
cat > "$TMPDIR/a8.R" <<'EOF'
k <- as.integer(commandArgs(TRUE)[1])
snap <- Sys.getenv("SNAP"); tag <- Sys.getenv("TAG"); out <- Sys.getenv("OUT")
ncpus <- as.integer(Sys.getenv("NCPUS"))
lib <- file.path(Sys.getenv("H0"), "lib", "a8", sprintf("R-%s-attempt%d", tag, k))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
os <- system("bash -c '. /etc/os-release; echo $VERSION_CODENAME'", intern = TRUE)
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
        paste(getRversion(), R.version$platform, R.version$arch, R.version$os)))
bin <- sprintf("https://p3m.dev/cran/__linux__/%s/%s", os, snap)
src <- sprintf("https://p3m.dev/cran/%s", snap)
bundled <- as.character(packageVersion("Matrix", lib.loc = .Library))
ap <- available.packages(repos = src)
cat("R:", R.version.string, "| OS:", os, "| bundled Matrix:", bundled,
    "| snapshot lme4:", ap["lme4", "Version"], "| snapshot Matrix:", ap["Matrix", "Version"], "\n")
for (f in c("Depends", "Imports", "LinkingTo")) cat("lme4", f, ":", gsub("\\s+", " ", ap["lme4", f]), "\n")

.libPaths(c(lib, .Library))                     # leaves the image's site library out
pk <- if (k == 2) c("Matrix", "lme4") else "lme4"
msgs <- character()
withCallingHandlers(
  tryCatch(install.packages(pk, lib = lib, repos = c(bin, src), dependencies = NA, Ncpus = ncpus),
           error = function(e) msgs <<- c(msgs, conditionMessage(e))),
  warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") })
ok <- requireNamespace("lme4", lib.loc = lib, quietly = TRUE)
fit <- NA_character_
if (ok) {
  fit <- tryCatch({
    suppressPackageStartupMessages(library(lme4, lib.loc = lib))
    m <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)
    sprintf("REML %.4f", REMLcrit(m))
  }, error = function(e) paste("fit failed:", conditionMessage(e)))
}
res <- data.frame(r_version = as.character(getRversion()), os = os, attempt = k,
                  bundled_matrix = bundled, snapshot = snap, snapshot_lme4 = ap["lme4", "Version"],
                  lme4_depends = gsub("\\s+", " ", ap["lme4", "Depends"]),
                  lme4_imports = gsub("\\s+", " ", ap["lme4", "Imports"]),
                  installed = ok,
                  lme4 = if (ok) as.character(packageVersion("lme4", lib.loc = lib)) else NA_character_,
                  matrix_used = as.character(packageVersion("Matrix", lib.loc = c(lib, .Library))),
                  fit = fit, messages = substr(paste(unique(msgs), collapse = " | "), 1, 2000))
f <- file.path(out, sprintf("a8_%s.tsv", tag))
write.table(res, f, sep = "\t", row.names = FALSE, quote = TRUE, append = k == 2, col.names = k == 1)
cat("attempt", k, ": installed =", ok, "| lme4", res$lme4, "| Matrix", res$matrix_used, "|", fit, "\n",
    res$messages, "\n")
if (!ok) quit(status = 3)
EOF

export H0
run() { apptainer exec --home "$H0/home" --bind "$H0" "$SIF" Rscript --vanilla "$TMPDIR/a8.R" "$1"; }
if run 1; then
  echo "attempt 1 succeeded; attempt 2 not needed"
else
  echo "attempt 1 failed; running attempt 2 with the snapshot's Matrix"
  run 2 || echo "attempt 2 failed too"
fi
rm -rf "$TMPDIR"
echo "== done $(date -Is)"
