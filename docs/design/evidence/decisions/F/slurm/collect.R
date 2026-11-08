# Collect chunk outputs for one study, check completeness against plan.csv, and compute
# per-cell performance with Monte Carlo SEs (Morris et al., 2019): rates p with
# MCSE = sqrt(p(1-p)/n); failures are counted, never silently dropped (Pawel et al., 2026).
# Usage: Rscript collect.R <study_dir> <out_dir> <result_csv>
args <- commandArgs(trailingOnly = TRUE); sdir <- args[1]; odir <- args[2]; res_csv <- args[3]
plan <- read.csv(file.path(sdir, "plan.csv")); cells <- read.csv(file.path(sdir, "cells.csv"))
fs <- list.files(odir, pattern = "_chunk[0-9]+\\.csv$", full.names = TRUE)
d <- do.call(rbind, lapply(fs, read.csv))
expected <- aggregate(cbind(n_expected = rep_to - rep_from + 1) ~ cell_id, data = plan, FUN = sum)
flags <- intersect(c("singular_lme4", "conv_msg", "bartlett_raw_flag", "cover_x"), names(d))
d$min_eig_cor_lt_1e4 <- d$min_eig_cor < 1e-4; flags <- c(flags, "min_eig_cor_lt_1e4")
out <- do.call(rbind, lapply(split(d, d$cell_id), function(s) {
  n <- nrow(s); ok <- s$status == "ok"
  r <- data.frame(cell_id = s$cell_id[1], n_done = n, n_error = sum(!ok), mean_elapsed_s = mean(s$elapsed_s))
  for (f in flags) { p <- mean(as.logical(s[[f]][ok])); r[[f]] <- p; r[[paste0(f, "_mcse")]] <- sqrt(p * (1 - p) / sum(ok)) }
  r }))
out <- merge(merge(cells, expected, by = "cell_id"), out, by = "cell_id")
out$complete <- out$n_done == out$n_expected
write.csv(out, res_csv, row.names = FALSE)
print(out[, c("cell_id", "J", "m", "cv", "n_expected", "n_done", "n_error", "singular_lme4", "singular_lme4_mcse",
              "min_eig_cor_lt_1e4", "bartlett_raw_flag", "bartlett_raw_flag_mcse", "cover_x", "cover_x_mcse")], digits = 3, row.names = FALSE)
