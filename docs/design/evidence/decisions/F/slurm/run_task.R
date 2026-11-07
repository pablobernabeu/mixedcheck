# Array-task driver for the lmecheck validation study (key F). Base R + parallel only.
# One SLURM array task runs the (cell, chunk) pairs assigned to it in plan.csv.
#   * Reproducible streams: chunk k uses the k-th L'Ecuyer-CMRG stream from iseed;
#     replicate j inside a chunk uses the j-th substream, so any single data set can be
#     regenerated from (iseed, k, j) without rerunning the chunk.
#   * Idempotent: a chunk whose output file exists is skipped, so failed tasks can simply
#     be resubmitted (sbatch --array=<failed ids>).
#   * Raw replicate-level results are stored (not only summaries), with provenance.
# Usage: Rscript run_task.R <study_dir> <task_id> <out_dir>
#   <study_dir> holds cells.csv (one row per DGM cell), plan.csv (task, cell_id, chunk, rep_from,
#   rep_to, stream) and study.R (defines generate(cell), analyse(cell, dat), iseed, study_id).
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(trailingOnly = TRUE)
study_dir <- args[1]
task_id <- as.integer(if (length(args) >= 2 && nzchar(args[2])) args[2] else Sys.getenv("SLURM_ARRAY_TASK_ID", "1"))
out_dir <- if (length(args) >= 3) args[3] else file.path(Sys.getenv("SCRATCH", tempdir()), "out")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(study_dir, "study.R"))           # generate(), analyse(), iseed, study_id
cells <- read.csv(file.path(study_dir, "cells.csv"), stringsAsFactors = FALSE)
plan  <- read.csv(file.path(study_dir, "plan.csv"))
mine  <- plan[plan$task == task_id, ]
if (!nrow(mine)) stop("no work assigned to task ", task_id)

stream_for <- function(k) {                        # k-th stream after iseed (k >= 1)
  RNGkind("L'Ecuyer-CMRG", "Inversion", "Rejection"); set.seed(iseed)
  s <- .Random.seed; for (i in seq_len(k)) s <- nextRNGStream(s); s
}
substream <- function(s, j) { for (i in seq_len(j)) s <- nextRNGSubStream(s); s }

run_one <- function(cell, s) {
  assign(".Random.seed", s, envir = .GlobalEnv)
  t0 <- proc.time()[["elapsed"]]; msgs <- character(0)
  res <- tryCatch(withCallingHandlers({
      dat <- generate(cell); analyse(cell, dat) },
    warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }),
    error = function(e) list(status = "error", error = conditionMessage(e)))
  res$elapsed_s <- proc.time()[["elapsed"]] - t0
  res$n_conditions <- length(msgs)
  res$conditions <- substr(paste(unique(msgs), collapse = " | "), 1, 300)
  res
}

cpu <- tryCatch(sub(".*: ", "", grep("model name", readLines("/proc/cpuinfo"), value = TRUE)[1]), error = function(e) NA)
interrupted <- FALSE
for (r in seq_len(nrow(mine))) {
  p <- mine[r, ]; cell <- cells[cells$cell_id == p$cell_id, , drop = FALSE]
  f <- file.path(out_dir, sprintf("%s_cell%04d_chunk%03d.csv", study_id, p$cell_id, p$chunk))
  if (file.exists(f)) next
  s0 <- stream_for(p$stream); out <- vector("list", p$rep_to - p$rep_from + 1)
  for (j in seq_along(out)) {
    rep_j <- p$rep_from + j - 1
    out[[j]] <- tryCatch({
      v <- run_one(cell, substream(s0, j))
      data.frame(study = study_id, cell_id = p$cell_id, chunk = p$chunk, stream = p$stream,
                 substream = j, rep = rep_j, as.data.frame(v, stringsAsFactors = FALSE))
    }, interrupt = function(e) { interrupted <<- TRUE; NULL })
    if (interrupted) break
  }
  res <- do.call(rbind, lapply(out[!vapply(out, is.null, TRUE)], function(d) d[, sort(names(d))]))
  if (!is.null(res) && nrow(res)) {
    tmp <- paste0(f, ".part"); write.csv(res, tmp, row.names = FALSE)
    if (!interrupted) file.rename(tmp, f)          # only complete chunks get the final name
  }
  writeLines(c(sprintf('{"study":"%s","task":%d,"cell_id":%d,"chunk":%d,"stream":%d,"iseed":%d,',
                       study_id, task_id, p$cell_id, p$chunk, p$stream, iseed),
               sprintf('"node":"%s","cpu":"%s","R":"%s","complete":%s,', Sys.getenv("SLURMD_NODENAME", Sys.info()[["nodename"]]),
                       cpu, R.version.string, tolower(!interrupted)),
               sprintf('"packages":"%s"}', paste(vapply(c("lme4", "glmmTMB", "Matrix"), function(k)
                 paste0(k, "=", tryCatch(as.character(packageVersion(k)), error = function(e) "NA")), ""), collapse = ";"))),
             sub("\\.csv$", ".json", f))
  if (interrupted) break
}
cat(sprintf("task %d finished (%s)\n", task_id, if (interrupted) "interrupted, partial outputs kept as .part" else "complete"))
