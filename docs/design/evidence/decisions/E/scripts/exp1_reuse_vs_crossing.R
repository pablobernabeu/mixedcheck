# Experiment E1: can data distinguish reused class labels (true nesting) from
# genuine crossing (the same label is the same unit in every school)?
#
# Part A (outcome-free, T0): the label incidence is identical by construction,
#   so any classifier that reads only IDs gives the same answer for both truths.
# Part B (outcome-aware, T2): compare ML log-likelihoods of the nested model
#   y ~ 1 + (1|school) + (1|school:lab) and the crossed model
#   y ~ 1 + (1|school) + (1|lab). Both have 4 parameters, so AIC and BIC
#   choose the same model as the log-likelihood.
#
# Usage: Rscript exp1_reuse_vs_crossing.R <out_dir> [n_rep]
suppressPackageStartupMessages(library(lme4))
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "."
n_rep <- if (length(args) >= 2) as.integer(args[2]) else 200L
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

make_ids <- function(J, K, n) {
  d <- expand.grid(pupil = seq_len(n), lab = seq_len(K), school = seq_len(J))
  d$school <- factor(sprintf("S%02d", d$school))
  d$lab <- factor(as.character(d$lab))
  d
}

# ---- Part A: incidence summaries (outcome-free) ----
incidence_summary <- function(d, outer = "school", inner = "lab") {
  tab <- table(d[[inner]], d[[outer]]) > 0
  m <- rowSums(tab)                      # outer levels per inner label
  list(n_inner = nrow(tab), n_outer = ncol(tab),
       share_inner_multi_outer = mean(m > 1),
       fill_rate = mean(tab),
       labels_per_outer = paste(sort(unique(colSums(tab))), collapse = ","))
}
dA <- make_ids(J = 20, K = 4, n = 10)
partA <- incidence_summary(dA)
# The same ID table serves both truths: nothing outcome-free can separate them.

# ---- Part B: outcome-based discrimination ----
sim_y <- function(d, truth, sd_school, sd_lab, sd_res = 1) {
  J <- nlevels(d$school); K <- nlevels(d$lab)
  u_s <- rnorm(J, 0, sd_school)[as.integer(d$school)]
  if (truth == "nested") {
    cell <- interaction(d$school, d$lab, drop = TRUE)
    u_c <- rnorm(nlevels(cell), 0, sd_lab)[as.integer(cell)]
  } else {
    u_c <- rnorm(K, 0, sd_lab)[as.integer(d$lab)]
  }
  u_s + u_c + rnorm(nrow(d), 0, sd_res)
}

ctrl <- lmerControl(calc.derivs = FALSE)
one_rep <- function(d, truth, sd_lab) {
  d$y <- sim_y(d, truth, sd_school = 0.4, sd_lab = sd_lab)
  fn <- suppressMessages(lmer(y ~ 1 + (1 | school) + (1 | school:lab), data = d,
                              REML = FALSE, control = ctrl))
  fc <- suppressMessages(lmer(y ~ 1 + (1 | school) + (1 | lab), data = d,
                              REML = FALSE, control = ctrl))
  dl <- as.numeric(logLik(fn)) - as.numeric(logLik(fc))
  c(dl = dl, sing_n = isSingular(fn), sing_c = isSingular(fc))
}

set.seed(20261107)
grid <- expand.grid(truth = c("nested", "crossed"), sd_lab = c(0.05, 0.1, 0.2, 0.4),
                    J = c(8, 20), n = c(5, 25), stringsAsFactors = FALSE)
res <- vector("list", nrow(grid))
t0 <- proc.time()[["elapsed"]]
for (g in seq_len(nrow(grid))) {
  d <- make_ids(J = grid$J[g], K = 4, n = grid$n[g])
  r <- t(replicate(n_rep, one_rep(d, grid$truth[g], grid$sd_lab[g])))
  correct <- if (grid$truth[g] == "nested") r[, "dl"] > 1e-6 else r[, "dl"] < -1e-6
  tie <- abs(r[, "dl"]) <= 1e-6
  res[[g]] <- data.frame(grid[g, ], n_rep = n_rep,
                         p_correct = mean(correct), p_tie = mean(tie),
                         mcse = sqrt(mean(correct) * (1 - mean(correct)) / n_rep),
                         median_abs_dloglik = median(abs(r[, "dl"])),
                         p_sing_nested_model = mean(r[, "sing_n"]),
                         p_sing_crossed_model = mean(r[, "sing_c"]))
}
elapsed <- proc.time()[["elapsed"]] - t0
out <- do.call(rbind, res)
write.csv(out, file.path(out_dir, "exp1_reuse_vs_crossing.csv"), row.names = FALSE)
sink(file.path(out_dir, "exp1_reuse_vs_crossing.txt"))
cat("lme4", as.character(packageVersion("lme4")), "R", R.version.string, "\n")
cat("Part A (identical for both truths; J=20, K=4):\n"); str(partA)
cat("\nPart B: proportion of replicates in which the true structure has the higher ML log-likelihood\n")
print(out, row.names = FALSE, digits = 3)
cat("\nElapsed seconds:", round(elapsed, 1), "\n")
sink()
cat(readLines(file.path(out_dir, "exp1_reuse_vs_crossing.txt")), sep = "\n")
