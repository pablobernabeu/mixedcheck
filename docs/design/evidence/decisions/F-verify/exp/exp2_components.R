# F-verify exp2: check component-cost ratios that F's budget.R assumes.
#  (a) allFit: which optimisers actually ran here (optimx and dfoptim are not installed), and cost
#  (b) Satterthwaite (lmerTest) cost relative to the fit for 2x2 maximal models (20 theta), which F
#      sets to 0.7 x fit from one-factor models only
#  (c) Kenward-Roger cost on a 2x2 maximal model at 384 rows (F's V1 protocol uses KR for n <= 400,
#      but budget.R includes no KR cost in V1)
# Usage: Rscript exp2_components.R <out_csv>
suppressPackageStartupMessages({ library(lme4); library(lmerTest) })
args <- commandArgs(trailingOnly = TRUE); out_csv <- args[1]
set.seed(20261109)
gen_2x2 <- function(S, I) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  cell <- (as.integer(d$subj) + as.integer(d$item)) %% 4
  d$A <- ifelse(cell %in% c(0, 1), -0.5, 0.5); d$B <- ifelse(cell %in% c(0, 2), -0.5, 0.5)
  mk <- function(n, sds) { R <- matrix(0.3, 4, 4); diag(R) <- 1; MASS::mvrnorm(n, rep(0, 4), diag(sds) %*% R %*% diag(sds)) }
  us <- mk(S, c(0.5, 0.2, 0.2, 0.1)); ui <- mk(I, c(0.4, 0.2, 0.2, 0.1))
  s <- as.integer(d$subj); i <- as.integer(d$item); X <- cbind(1, d$A, d$B, d$A * d$B)
  d$y <- drop(X %*% c(0, 0.2, 0.1, 0.05)) + rowSums(X * us[s, ]) + rowSums(X * ui[i, ]) + rnorm(nrow(d)); d
}
gen_nested <- function(J, m) {
  g <- factor(rep(seq_len(J), each = m)); n <- J * m; x <- rnorm(J, 0, .5)[g] + rnorm(n)
  z <- rep(rep(c(-.5, .5), length.out = J), each = m)
  data.frame(g, x, z, y = 0.2 * x + 0.3 * z + rnorm(J, 0, .65)[g] + rnorm(J, 0, .15)[g] * x + rnorm(n))
}
tm <- function(expr) { t0 <- proc.time()[["elapsed"]]; v <- suppressWarnings(suppressMessages(expr)); list(t = proc.time()[["elapsed"]] - t0, v = v) }
rows <- list(); rec <- function(...) rows[[length(rows) + 1]] <<- data.frame(...)

## (a) allFit on two nested data sets
for (J in c(10, 30)) {
  d <- gen_nested(J, if (J == 10) 5 else 20)
  f <- tm(lme4::lmer(y ~ x + z + (1 + x | g), d))
  a <- tm(allFit(f$v, verbose = FALSE))
  ok <- vapply(a$v, function(z) !inherits(z, "error"), TRUE)
  rec(what = "allFit", design = sprintf("nested J%d", J), n_obs = nrow(d), fit_s = f$t, comp_s = a$t,
      ratio = a$t / f$t, note = paste0(sum(ok), " optimisers ran: ", paste(names(a$v)[ok], collapse = ",")))
}
## (b) Satterthwaite and (c) KR on 2x2 maximal fits
for (sz in list(c(24, 16), c(48, 32))) {
  d <- gen_2x2(sz[1], sz[2])
  f0 <- tm(lme4::lmer(y ~ A * B + (1 + A * B | subj) + (1 + A * B | item), d))
  f0n <- tm(lme4::lmer(y ~ A * B + (1 + A * B | subj) + (1 + A * B | item), d, control = lmerControl(calc.derivs = FALSE)))
  s <- tm(summary(as_lmerModLmerTest(f0$v), ddf = "Satterthwaite")$coefficients)
  rec(what = "satterthwaite", design = sprintf("2x2 S%d I%d", sz[1], sz[2]), n_obs = nrow(d), fit_s = f0$t, comp_s = s$t,
      ratio = s$t / f0$t, note = sprintf("fit without derivs %.2f s; ratio to that %.2f; singular=%s", f0n$t, s$t / f0n$t, isSingular(f0$v)))
  if (nrow(d) <= 400) {
    k <- tm(summary(as_lmerModLmerTest(f0$v), ddf = "Kenward-Roger")$coefficients)
    rec(what = "kenward_roger", design = sprintf("2x2 S%d I%d", sz[1], sz[2]), n_obs = nrow(d), fit_s = f0$t, comp_s = k$t,
        ratio = k$t / f0$t, note = sprintf("ratio to fit without derivs %.2f", k$t / f0n$t))
  }
}
out <- do.call(rbind, rows); write.csv(out, out_csv, row.names = FALSE); print(out)
