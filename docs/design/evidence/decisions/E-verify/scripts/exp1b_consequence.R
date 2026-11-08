# Extension of report E's E1: does the choice between nested and crossed models
# matter most where the outcome discriminates them worst (small label variance)?
# Truth: class labels 1..4 reused in every school (true nesting); treatment is
# randomised to 2 of the 4 classes in each school (class-level CRT, blocked by
# school); true treatment effect 0. Fit the correct nested model
# (1|school)+(1|school:lab) and the crossed model a label-based audit would
# suggest, (1|school)+(1|lab). Report the empirical Type I error of the Wald z
# test for treatment (|z| > 1.96) and how often the ML log-likelihood picks
# the true (nested) model.
# Usage: Rscript exp1b_consequence.R <out_csv> [n_rep]
suppressPackageStartupMessages(library(lme4))
args <- commandArgs(trailingOnly = TRUE)
out <- args[1]; n_rep <- if (length(args) > 1) as.integer(args[2]) else 300L
ctrl <- lmerControl(calc.derivs = FALSE)
set.seed(20261107)
one <- function(J, n, sd_lab) {
  d <- expand.grid(pupil = seq_len(n), lab = 1:4, school = seq_len(J))
  d$school <- factor(d$school); d$lab <- factor(d$lab)
  tr <- unlist(lapply(seq_len(J), function(j) sample(c(0, 0, 1, 1))))
  d$trt <- tr[(as.integer(d$school) - 1) * 4 + as.integer(d$lab)]
  cell <- interaction(d$school, d$lab, drop = TRUE)
  d$y <- rnorm(J, 0, 0.4)[d$school] + rnorm(nlevels(cell), 0, sd_lab)[cell] + rnorm(nrow(d))
  fn <- suppressMessages(lmer(y ~ trt + (1 | school) + (1 | school:lab), d, REML = FALSE, control = ctrl))
  fc <- suppressMessages(lmer(y ~ trt + (1 | school) + (1 | lab), d, REML = FALSE, control = ctrl))
  zn <- coef(summary(fn))["trt", "t value"]; zc <- coef(summary(fc))["trt", "t value"]
  c(rej_nested = abs(zn) > 1.96, rej_crossed = abs(zc) > 1.96,
    picks_true = as.numeric(logLik(fn)) - as.numeric(logLik(fc)) > 1e-6)
}
grid <- expand.grid(sd_lab = c(0.05, 0.1, 0.2, 0.4), J = 20, n = c(5, 25))
res <- do.call(rbind, lapply(seq_len(nrow(grid)), function(g) {
  r <- t(replicate(n_rep, one(grid$J[g], grid$n[g], grid$sd_lab[g])))
  icc <- grid$sd_lab[g]^2 / (grid$sd_lab[g]^2 + 0.16 + 1)
  data.frame(grid[g, ], icc_class = round(icc, 4), deff = round(1 + (grid$n[g] - 1) * icc, 3), n_rep = n_rep,
             typeI_nested = mean(r[, "rej_nested"]), typeI_crossed = mean(r[, "rej_crossed"]),
             p_loglik_picks_true = mean(r[, "picks_true"]))
}))
res$mcse_typeI <- round(sqrt(0.05 * 0.95 / n_rep), 4)
write.csv(res, out, row.names = FALSE)
print(res, row.names = FALSE)
