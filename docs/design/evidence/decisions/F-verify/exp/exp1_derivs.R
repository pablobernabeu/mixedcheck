# F-verify exp1: how much of F's measured fit time is lme4's finite-difference derivative
# step (deriv12), which lme4 >= 1.1-38 skips for singular fits, for lmer models with >= 10
# covariance parameters and for glmer models with >= 20 parameters (fixed effects included)?
# Paired, interleaved timings with calc.derivs = TRUE (lme4 1.1-35.1 default) vs FALSE.
# Also times one 2x2 maximal lmer at 96 x 64 = 6,144 rows to test F's extrapolated 23 s.
# Usage: Rscript exp1_derivs.R <out_csv>
suppressPackageStartupMessages(library(lme4))
args <- commandArgs(trailingOnly = TRUE); out_csv <- args[1]
set.seed(20261107)
gen_2x2 <- function(S, I) {               # same generator as F's time_grid2.R
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  cell <- (as.integer(d$subj) + as.integer(d$item)) %% 4
  d$A <- ifelse(cell %in% c(0, 1), -0.5, 0.5); d$B <- ifelse(cell %in% c(0, 2), -0.5, 0.5)
  mk <- function(n, sds) { R <- matrix(0.3, 4, 4); diag(R) <- 1; MASS::mvrnorm(n, rep(0, 4), diag(sds) %*% R %*% diag(sds)) }
  us <- mk(S, c(0.5, 0.2, 0.2, 0.1)); ui <- mk(I, c(0.4, 0.2, 0.2, 0.1))
  s <- as.integer(d$subj); i <- as.integer(d$item)
  X <- cbind(1, d$A, d$B, d$A * d$B)
  eta <- drop(X %*% c(0, 0.2, 0.1, 0.05)) + rowSums(X * us[s, ]) + rowSums(X * ui[i, ])
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta)); d
}
gen_1f <- function(S, I) {                # F's one-factor crossed generator
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  s <- as.integer(d$subj); i <- as.integer(d$item)
  eta <- 0.2 * d$A + rnorm(S, 0, .5)[s] + rnorm(S, 0, .3)[s] * d$A + rnorm(I, 0, .4)[i] + rnorm(I, 0, .3)[i] * d$A
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta)); d
}
tm <- function(expr) { t0 <- proc.time()[["elapsed"]]; v <- suppressWarnings(suppressMessages(expr)); list(t = proc.time()[["elapsed"]] - t0, v = v) }
rows <- list()
rec <- function(design, n, engine, derivs, rep, r) {
  f <- r$v
  rows[[length(rows) + 1]] <<- data.frame(design, n_obs = n, engine, calc_derivs = derivs, rep, elapsed = r$t,
    singular = isSingular(f), npar = length(getME(f, "theta")) + if (engine == "glmer") length(fixef(f)) else 0,
    deviance = if (engine == "glmer") deviance(f) else REMLcrit(f))
}
f2 <- y ~ A * B + (1 + A * B | subj) + (1 + A * B | item)
f2b <- yb ~ A * B + (1 + A * B | subj) + (1 + A * B | item)
f1 <- y ~ A + (1 + A | subj) + (1 + A | item)
t_start <- proc.time()[["elapsed"]]
for (sz in list(c(24, 16, 3), c(48, 32, 2), c(96, 64, 1))) {
  for (r in seq_len(sz[3])) {
    d <- gen_2x2(sz[1], sz[2])
    ord <- if (r %% 2) c(TRUE, FALSE) else c(FALSE, TRUE)          # alternate order
    for (cd in ord) rec("crossed2x2", nrow(d), "lmer", cd, r, tm(lmer(f2, d, control = lmerControl(calc.derivs = cd))))
    cat(sprintf("[%5.0fs] 2x2 lmer %d rows rep %d\n", proc.time()[["elapsed"]] - t_start, nrow(d), r))
  }
}
for (sz in list(c(24, 16), c(48, 32))) {     # glmer 2x2 maximal, one pair per size
  d <- gen_2x2(sz[1], sz[2])
  for (cd in c(FALSE, TRUE)) rec("crossed2x2", nrow(d), "glmer", cd, 1, tm(glmer(f2b, d, family = binomial, control = glmerControl(calc.derivs = cd))))
  cat(sprintf("[%5.0fs] 2x2 glmer %d rows\n", proc.time()[["elapsed"]] - t_start, nrow(d)))
}
for (r in 1:3) {                             # one-factor crossed maximal, 1,536 rows
  d <- gen_1f(48, 32)
  for (cd in c(TRUE, FALSE)) rec("crossed1f", nrow(d), "lmer", cd, r, tm(lmer(f1, d, control = lmerControl(calc.derivs = cd))))
}
cat(sprintf("[%5.0fs] 1f done\n", proc.time()[["elapsed"]] - t_start))
out <- do.call(rbind, rows); write.csv(out, out_csv, row.names = FALSE)
agg <- aggregate(elapsed ~ design + engine + n_obs + calc_derivs, data = out, FUN = median)
print(agg)
cat("Max |deviance difference| between paired fits (same data):\n")
w <- reshape(out[, c("design","engine","n_obs","rep","calc_derivs","deviance")], idvar = c("design","engine","n_obs","rep"), timevar = "calc_derivs", direction = "wide")
print(cbind(w[, 1:4], ddev = w$deviance.TRUE - w$deviance.FALSE))
cat(sprintf("Total %.0f s\n", proc.time()[["elapsed"]] - t_start))
