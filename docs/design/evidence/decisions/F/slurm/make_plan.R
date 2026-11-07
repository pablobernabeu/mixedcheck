# Build cells.csv and plan.csv for one study: split each cell's replicates into chunks of
# `chunk_reps`, give every chunk a unique stream index, then pack chunks into array tasks so
# that each task holds about `target_s` seconds of work (per-replicate cost from the budget).
# Usage: Rscript make_plan.R <study_dir> <reps_per_cell> <chunk_reps> <target_s> <sec_per_rep_col_or_value>
args <- commandArgs(trailingOnly = TRUE)
dir <- args[1]; reps <- as.integer(args[2]); chunk_reps <- as.integer(args[3]); target_s <- as.numeric(args[4])
cells <- read.csv(file.path(dir, "cells.csv"))
spr <- if (args[5] %in% names(cells)) cells[[args[5]]] else rep(as.numeric(args[5]), nrow(cells))
ch <- do.call(rbind, lapply(seq_len(nrow(cells)), function(i) {
  k <- ceiling(reps / chunk_reps)
  data.frame(cell_id = cells$cell_id[i], chunk = seq_len(k), rep_from = (seq_len(k) - 1) * chunk_reps + 1,
             rep_to = pmin(seq_len(k) * chunk_reps, reps), sec = spr[i] * chunk_reps)
}))
ch$stream <- seq_len(nrow(ch))                         # unique across the study, never reused
ch <- ch[order(-ch$sec), ]; load <- numeric(0); ch$task <- NA_integer_
for (r in seq_len(nrow(ch))) {                         # greedy packing into tasks of ~target_s
  i <- which(load + ch$sec[r] <= target_s)[1]
  if (is.na(i)) { load <- c(load, 0); i <- length(load) }
  load[i] <- load[i] + ch$sec[r]; ch$task[r] <- i
}
ch <- ch[order(ch$task, ch$cell_id, ch$chunk), c("task", "cell_id", "chunk", "rep_from", "rep_to", "stream", "sec")]
write.csv(ch, file.path(dir, "plan.csv"), row.names = FALSE)
cat(sprintf("%d cells, %d chunks, %d tasks; max task load %.0f s\n", nrow(cells), nrow(ch), max(ch$task), max(load)))
