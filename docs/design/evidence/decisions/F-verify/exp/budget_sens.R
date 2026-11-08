# Key F, task 3: extrapolate measured fit times to the validation programme
# (replicates x conditions x checks) and size SLURM job arrays for ARC 'htc'.
# Inputs: cost_model_powerlaw.csv and timing_medians.csv (from fit_cost_model.R),
#         timing_statsmodels*.csv. Output: budget_cells.csv, budget_by_study.csv, array_plan.csv
# Usage: Rscript budget.R <budget_dir> <timing_out_dir>
args <- commandArgs(trailingOnly = TRUE); bdir <- args[1]; tdir <- args[2]
pl  <- read.csv(file.path(bdir, "cost_model_powerlaw.csv"))
med <- read.csv(file.path(bdir, "timing_medians.csv"))

## ---------- time per fit (seconds, this VM, lme4 1.1-35.1 / glmmTMB 1.1.8) ----------
two_point <- function(model) {          # log-log line through the two measured sizes
  s <- med[med$model == model, ]; s <- aggregate(elapsed ~ n_obs, data = s, FUN = median)
  b <- diff(log(s$elapsed)) / diff(log(s$n_obs)); a <- log(s$elapsed[1]) - b * log(s$n_obs[1])
  c(a = a, b = b)
}
coef_for <- function(model) {
  r <- pl[pl$model == model, ]
  if (nrow(r) && !is.na(r$a)) return(c(a = r$a, b = r$b))
  if (nrow(r) && r$k == 2) return(two_point(model))
  stop("no cost model for ", model)
}
# single-point families borrow the exponent of the closest measured family
borrow <- function(model, donor) {
  s <- med[med$model == model, ]; b <- coef_for(donor)[["b"]]
  c(a = log(median(s$elapsed)) - b * log(median(s$n_obs)), b = b)
}
CM <- list(
  nested_lmer   = coef_for("nested|fit|lmer_gauss"),
  nested_glmer  = coef_for("nested|fit|glmer_bern"),
  nested_glmerP = borrow("nested|fit|glmer_pois", "nested|fit|glmer_bern"),
  nested_tmbG   = coef_for("nested|fit|tmb_gauss"),
  nested_tmbB   = coef_for("nested|fit|tmb_bern"),
  nested_tmbNB  = borrow("nested|fit|tmb_nb2", "nested|fit|tmb_bern"),
  crossed_lmer  = coef_for("crossed|fit|lmer_gauss"),
  crossed_glmer = coef_for("crossed|fit|glmer_bern"),
  crossed_tmbG  = coef_for("crossed|fit|tmb_gauss"),
  crossed_tmbB  = coef_for("crossed|fit|tmb_bern"),
  x22_lmer      = coef_for("crossed2x2|fit|lmer_gauss"),
  x22_lmer_zcp  = coef_for("crossed2x2|fit_zcp|lmer_gauss"),
  x22_glmer     = coef_for("crossed2x2|fit|glmer_bern"),
  x22_tmbG      = coef_for("crossed2x2|fit|tmb_gauss"),
  x22_tmbB      = coef_for("crossed2x2|fit|tmb_bern"),
  n3_lmer       = coef_for("nested3|fit|lmer_gauss"),
  n3_tmbG       = coef_for("nested3|fit|tmb_gauss"),
  n3_glmer      = coef_for("nested3|fit|glmer_bern"),
  gr_lmer       = coef_for("growth|fit|lmer_gauss"),
  gr_tmbG       = coef_for("growth|fit|tmb_gauss"),
  gr_tmb_ar1    = coef_for("growth|fit_ar1|tmb_gauss")
)
# statsmodels (Python): nested (power law over 4 sizes) and crossed variance components
sm <- rbind(read.csv(file.path(tdir, "timing_statsmodels.csv")), read.csv(file.path(tdir, "timing_statsmodels_big.csv")))
smn <- aggregate(elapsed ~ n_obs, data = sm[sm$design == "nested", ], FUN = median)
smc <- aggregate(elapsed ~ n_obs, data = sm[sm$design == "crossed_vc", ], FUN = median)
CM$sm_nested  <- { m <- lm(log(elapsed) ~ log(n_obs), smn); c(a = coef(m)[[1]], b = coef(m)[[2]]) }
CM$sm_crossed <- { m <- lm(log(elapsed) ~ log(n_obs), smc); c(a = coef(m)[[1]], b = coef(m)[[2]]) }
tf <- function(key, n) exp(CM[[key]][["a"]] + CM[[key]][["b"]] * log(n))

## ---------- ratios measured in timing_raw.csv (rounded up) ----------
R_ML <- 0.5; R_SATT <- 0.7; R_SIM <- 0.5; R_ALLFIT <- 20; R_OVERHEAD <- 1.0  # suite's own check code: assumption, calibrate in pilot
R_RI <- 0.7; R_ZCP1 <- 0.5; R_AGQ <- 0.7

cells <- list()
add <- function(study, phase, df, reps, per_rep_s, note) {
  df$study <- study; df$phase <- phase; df$reps <- reps; df$sec_per_rep <- per_rep_s; df$note <- note
  cells[[length(cells) + 1]] <<- df
}

## ===================== Phase 1: Gaussian LMMs (release v1.0) =====================
# V1a nested two-level null bank
g <- expand.grid(J = c(6, 10, 20, 40, 100), m = c(2, 5, 20, 50), cv = c(0, .5), icc = c(.1, .3), tau1 = c(0, .15, .3))
g$n <- g$J * g$m
add("V1a", 1, g, 2000, with(g, tf("nested_lmer", n) * (1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("nested_tmbG", n)),
    "focal lmer + ML refit + RI alternative + Satterthwaite + simulate(250) + suite checks; glmmTMB on 20% for parity")
# V1b crossed one-factor null bank
g <- data.frame(S = rep(c(12, 24, 48, 96), 3), I = rep(c(8, 16, 32, 64), 3), tau1 = rep(c(0, .1, .3), each = 4)); g$n <- g$S * g$I
add("V1b", 1, g, 2000, with(g, tf("crossed_lmer", n) * (1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("crossed_tmbG", n)),
    "maximal + zcp + RI + Satterthwaite + simulate + suite checks; glmmTMB on 20%")
# V1c crossed 2x2 null bank (maximal 4x4 covariance per factor)
g <- expand.grid(SI = c("24x16", "48x32"), tau = c(0, .2)); g$n <- ifelse(g$SI == "24x16", 384, 1536)
add("V1c", 1, g, 2000, with(g, tf("x22_lmer", n) * (1 + 0.1 + R_SATT + R_SIM + R_OVERHEAD) + tf("x22_lmer_zcp", n) + 0.2 * tf("x22_tmbG", n)),
    "maximal + zcp + RI + Satterthwaite + simulate + suite checks; glmmTMB on 20%")
# V1d three-level / cluster-randomised null bank
g <- expand.grid(K = c(4, 10, 20, 40), C = c(2, 4), m = c(10, 25), rand = c("class", "school")); g$n <- g$K * g$C * g$m
add("V1d", 1, g, 2000, with(g, tf("n3_lmer", n) * (1 + 1 + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("n3_tmbG", n)),
    "focal 3-level + model omitting a level + Satterthwaite + simulate + suite checks")
# V1e growth null bank
g <- expand.grid(P = c(50, 200, 800), T = c(3, 5, 8), tau_time = c(0, .3)); g$n <- g$P * g$T
add("V1e", 1, g, 2000, with(g, tf("gr_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD) + tf("gr_tmb_ar1", n)),
    "focal (1+time|id) + glmmTMB AR(1) alternative + Satterthwaite + simulate + suite checks")
# V2 Gaussian misspecification modules: 12 modules x 3 magnitudes x ~6 applicable cells (of 8 representative)
rep_cells <- data.frame(key = c(rep("nested", 4), rep("crossed", 2), "n3", "growth"),
                        n = c(50, 200, 200, 800, 384, 1536, 400, 1000))
per_cell <- function(key, n) switch(key,
  nested  = tf("nested_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD) + tf("nested_tmbG", n),
  crossed = tf("crossed_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD) + tf("crossed_tmbG", n),
  n3      = tf("n3_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD) + tf("n3_tmbG", n),
  growth  = tf("gr_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD) + tf("gr_tmb_ar1", n))
rep_cells$s <- mapply(per_cell, rep_cells$key, rep_cells$n)
g <- expand.grid(module = sprintf("M%02d", 1:12), magnitude = 1:3, cell = 1:8)
g$n <- rep_cells$n[g$cell]; g$sec <- rep_cells$s[g$cell]
g <- g[(as.integer(sub("M", "", g$module)) + g$cell) %% 4 != 0, ]   # ~3/4 of module x cell pairs apply
add("V2", 1, g[, c("module", "magnitude", "cell", "n")], 1000, g$sec,
    "focal fit + registry alternative (glmmTMB variant) + Satterthwaite + simulate + suite checks")
# V2-infl: cluster-deletion influence, 200 reps x J refits on nested cells with J = 10 and 40
g <- expand.grid(J = c(10, 40), m = c(5, 20), magnitude = 0:3); g$n <- g$J * g$m
add("V2-infl", 1, g, 200, with(g, J * tf("nested_lmer", n) + tf("nested_lmer", n) * 2), "J deletion refits per replicate")
# V3 singularity and convergence criteria (nested + crossed), with allFit-style triage as reference
g <- expand.grid(J = c(6, 10, 20), m = c(5, 20), tau1 = c(0, .05, .1, .2), scale = c(.1, 1, 10)); g$n <- g$J * g$m
add("V3-nested", 1, g, 1000, with(g, tf("nested_lmer", n) * (1 + R_ALLFIT + 2 + R_OVERHEAD) + tf("nested_tmbG", n)),
    "lmer + glmmTMB + allFit (7 optimisers) + boundary probe (2 refits) + suite checks")
g <- expand.grid(SI = c(384, 1536), tau = c(0, .05, .2), design = c("1f", "2x2")); g$n <- g$SI
add("V3-crossed", 1, g, 500, with(g, ifelse(design == "1f",
      tf("crossed_lmer", n) * (1 + R_ALLFIT + R_OVERHEAD) + tf("crossed_tmbG", n),
      tf("x22_lmer", n) * (1 + R_ALLFIT + R_OVERHEAD) + tf("x22_tmbG", n))), "as V3-nested on crossed designs")
# V4 variance-component tests: chi-bar-square vs parametric bootstrap (B = 199)
g <- expand.grid(J = c(5, 10, 20), m = c(5, 20), sigma2 = c(0, .05, .15)); g$n <- g$J * g$m
add("V4", 1, g, 1000, with(g, tf("nested_lmer", n) * (2 + 2 * 199)), "null + alternative fits + 199 bootstrap refit pairs")
# V5 reduction ladder / stopping rules (sibling key B, H1): 200 Latin-hypercube cells, 8 fits per replicate
SI <- expand.grid(S = c(12, 24, 48, 96), I = c(8, 16, 32, 64)); SI$n <- SI$S * SI$I
h1_1f  <- mean(tf("crossed_lmer", SI$n)) * (1 + 7 * 0.5)
h1_22  <- mean(tf("x22_lmer", SI$n)) * (1 + 7 * 0.5)
h1_22r <- mean(tf("x22_lmer", SI$n[SI$n <= 1536])) * (1 + 7 * 0.5)
g <- data.frame(design = c("1f", "2x2", "2x2_capped_1536rows"), cells = c(100, 100, 100), n = NA)
add("V5-H1", 1, g[1:2, ], 1500, c(h1_1f, h1_22), "B's H1 grid as specified (2x2 up to 96 x 64)")
add("V5-H1-capped", 1, g[c(1, 3), ], 1500, c(h1_1f, h1_22r), "same, 2x2 cells capped at 1536 rows (recommended)")
# V5 other ladder questions (B's H2, H5): nested designs, cheap fits
g <- data.frame(q = c("H2", "H5"), cells = c(100, 96), n = c(600, 300))
add("V5-H2H5", 1, g, 1500, with(g, tf("nested_lmer", n) * c(6, 3 + 5 + 1)), "H2: 6 lmer fits; H5: 3 fits + KR + CR2")
# V6 outcome-blind design analysis calibration (L1-18; B's H6): 500 outer x 200 inner simulations
g <- data.frame(design = c(rep("nested", 14), rep("crossed", 6)), n = c(rep(c(50, 200, 400, 800, 1000, 2000, 300), 2), rep(c(96, 384, 1536), 2)))
add("V6", 1, g, 500, with(g, 200 * ifelse(design == "nested", tf("nested_lmer", n), tf("crossed_lmer", n))), "200 inner fits per outer replicate")
# V7 cross-language parity (statsmodels) on V1 subsets
g <- rbind(data.frame(design = "nested", n = rep(c(50, 200, 800, 2000, 5000, 400), 2)), data.frame(design = "crossed", n = c(96, 384)))
add("V7", 1, g, 500, with(g, ifelse(design == "nested", tf("sm_nested", n), tf("sm_crossed", n)) + 0.2), "statsmodels fit + suite checks (Python); R side reused from V1")

## ===================== Phase 2: GLMMs (release v1.1) =====================
g0 <- expand.grid(J = c(10, 20, 40, 100), m = c(5, 20, 50), icc = c(.1, .3), tau1 = c(0, .3)); g0$n <- g0$J * g0$m
for (fam in c("bernoulli", "binomial5", "poisson")) {
  key <- if (fam == "poisson") "nested_glmerP" else "nested_glmer"
  add(paste0("V8-", fam), 2, g0, 2000, with(g0, tf(key, n) * (1 + 0.5 + R_AGQ * 0.5 + R_SIM + R_OVERHEAD) + tf("nested_tmbB", n)),
      "glmer focal + glmmTMB focal + glmer RI + nAGQ=10 RI + simulate(250) + suite checks")
  gx <- data.frame(SI = c(384, 384, 1536, 1536), tau = c(0, .3, 0, .3)); gx$n <- gx$SI
  add(paste0("V8x-", fam), 2, gx, 2000, with(gx, tf("crossed_glmer", n) * (1 + R_SIM + R_OVERHEAD) + tf("crossed_tmbB", n)),
      "crossed one-factor GLMM null bank")
}
g <- expand.grid(module = sprintf("G%02d", 1:6), magnitude = 1:3, n = c(50, 200, 400, 800, 1000, 384))
add("V9", 2, g, 1000, with(g, ifelse(n == 384, tf("crossed_glmer", n) + tf("crossed_tmbB", n), tf("nested_glmer", n) + tf("nested_tmbNB", n)) * 1.5 +
                                  ifelse(n == 384, tf("crossed_glmer", n), tf("nested_glmer", n)) * (R_SIM + R_OVERHEAD)),
    "glmer focal + glmmTMB alternative (NB/ZI/OLRE) + simulate + suite checks")
g <- expand.grid(J = c(10, 20), m = c(5, 20), sigma2 = c(0, .3)); g <- g[1:6, ]; g$n <- g$J * g$m
add("V10", 2, g, 500, with(g, tf("nested_glmer", n) * (2 + 2 * 199)), "GLMM parametric bootstrap LRT, B = 199")

cells <- do.call(rbind, lapply(cells, function(d) { d$n <- if (is.null(d$n)) NA else d$n
  d[, c("study", "phase", "reps", "sec_per_rep", "n", "note")] }))
cells$ncell <- 1
# V5 rows stand for 100 / 96 cells each
k <- cells$study %in% c("V5-H1", "V5-H1-capped", "V5-H2H5")
cells$ncell[k] <- c(100, 100, 100, 100, 100, 96)
cells$cpu_s <- cells$ncell * cells$reps * cells$sec_per_rep
write.csv(cells, file.path(bdir, "budget_cells.csv"), row.names = FALSE)

## ---------- multipliers ----------
M_CONTENTION <- 1.38   # measured: 4 concurrent processes vs 1 (throughput.csv)
M_RERUN <- 1.15        # failed/timed-out tasks, reruns of missing replicates
M_PILOT <- 1.10        # pilot runs (200 reps on ~10% of cells) and debugging
central <- M_CONTENTION * M_RERUN * M_PILOT
low  <- central * 0.6  # faster ARC cores / lme4 2.x speedups (assumption)
high <- central * 2.0  # slower nodes, heavier suite checks than assumed (assumption)

by <- aggregate(cbind(cpu_s, cells = ncell, reps_total = ncell * reps) ~ study + phase, data = cells, FUN = sum)
by$cpu_h_vm <- by$cpu_s / 3600
by$cpu_h_central <- by$cpu_h_vm * central; by$cpu_h_low <- by$cpu_h_vm * low; by$cpu_h_high <- by$cpu_h_vm * high
by <- by[order(by$phase, by$study), ]
write.csv(by, file.path(bdir, "budget_by_study.csv"), row.names = FALSE)
print(by[, c("study", "phase", "cells", "reps_total", "cpu_h_vm", "cpu_h_central", "cpu_h_high")], digits = 3, row.names = FALSE)
tot <- function(ph, excl) colSums(by[by$phase %in% ph & !by$study %in% excl, c("cpu_h_vm", "cpu_h_central", "cpu_h_low", "cpu_h_high")])
cat("\nPhase 1 (H1 capped):\n"); print(round(tot(1, "V5-H1")))
cat("Phase 1 (H1 uncapped):\n"); print(round(tot(1, "V5-H1-capped")))
cat("Phase 2:\n"); print(round(tot(2, character(0))))

## ---------- array sizing: target ~4 h per task at central speed, wall request 2x, short partition (12 h) ----------
TARGET_S <- 4 * 3600
ap <- do.call(rbind, lapply(split(cells, cells$study), function(d) {
  tot_s <- sum(d$cpu_s) * central
  per_cell_s <- d$reps * d$sec_per_rep * central
  # big cells are split into replicate chunks; small cells are packed together
  chunks <- pmax(1, ceiling(per_cell_s / TARGET_S))
  tasks <- if (all(chunks == 1)) ceiling(tot_s / TARGET_S) else sum(chunks * d$ncell)
  data.frame(study = d$study[1], cells = sum(d$ncell), cpu_h_central = tot_s / 3600,
             max_cell_h = max(per_cell_s) / 3600, array_tasks = max(1, tasks),
             est_task_h = tot_s / 3600 / max(1, tasks))
}))
ap$time_request <- sprintf("%02d:00:00", pmin(12, ceiling(2 * ap$est_task_h) + 1))
ap$partition <- "short"; ap$mem_per_cpu <- "2G"
ap$array_spec <- sprintf("1-%d%%%d", ap$array_tasks, pmin(ap$array_tasks, 200))
ap <- ap[order(ap$study), ]
write.csv(ap, file.path(bdir, "array_plan.csv"), row.names = FALSE)
print(ap, digits = 3, row.names = FALSE)
cat("\nMultipliers: central", round(central, 3), " low", round(low, 3), " high", round(high, 3), "\n")
