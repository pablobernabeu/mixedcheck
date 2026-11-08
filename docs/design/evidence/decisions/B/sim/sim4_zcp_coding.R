# Sim 4: are zero-correlation (||) random-slope models invariant to coding/centring? (deterministic demo)
# Same data, two codings of a two-level within-subject factor: treatment (0/1) and deviation (-0.5/+0.5).
# The unstructured model (1 + x | s) is invariant (same logLik, same SE for the slope); (1 + x || s) is not.
# Also: a 3-level factor with '||' in lme4 (expands to (1|s) + (0 + f|s), redundant) vs numeric contrasts.
suppressPackageStartupMessages({library(lme4); library(lmerTest)})
set.seed(42)
S <- 30; m <- 20
d <- expand.grid(rep = 1:m, s = factor(1:S))
d$cond <- rep(c("a", "b"), length.out = nrow(d))
u0 <- rnorm(S, 0, 0.6); u1 <- rnorm(S, 0, 0.4)
# true random effects correlated (rho = .6) in the deviation-coded parameterisation
u1 <- 0.6 * u0 / 0.6 * 0.4 + sqrt(1 - 0.36) * u1
xdev <- ifelse(d$cond == "b", 0.5, -0.5)
d$y <- 0.2 * xdev + u0[d$s] + u1[d$s] * xdev + rnorm(nrow(d))
d$x_trt <- as.numeric(d$cond == "b"); d$x_dev <- xdev
fits <- list(
  us_trt  = lmer(y ~ x_trt + (1 + x_trt | s), d),
  us_dev  = lmer(y ~ x_dev + (1 + x_dev | s), d),
  zcp_trt = lmer(y ~ x_trt + (1 + x_trt || s), d),
  zcp_dev = lmer(y ~ x_dev + (1 + x_dev || s), d))
tab <- t(sapply(fits, function(f) {
  co <- summary(f)$coefficients; nm <- rownames(co)[2]
  c(REMLcrit = round(REMLcrit(f), 4), slope_SE = round(co[nm, "Std. Error"], 5), slope_t = round(co[nm, "t value"], 4),
    satt_df = round(co[nm, "df"], 2), singular = isSingular(f))
}))
print(tab)
cat("\nThree-level factor: lme4 expansion of (1 + f || s) and its parameter count\n")
d$f3 <- factor(rep(c("a", "b", "c"), length.out = nrow(d)))
d$y3 <- d$y + 0.1 * (d$f3 == "c")
f_bad <- suppressMessages(suppressWarnings(lmer(y3 ~ f3 + (1 + f3 || s), d)))
print(VarCorr(f_bad)); cat("theta length:", length(getME(f_bad, "theta")), "\n")
mm <- model.matrix(~ f3, d, contrasts.arg = list(f3 = contr.sum(3)))
d$c1 <- mm[, 2]; d$c2 <- mm[, 3]
f_ok <- suppressMessages(suppressWarnings(lmer(y3 ~ c1 + c2 + (1 + c1 + c2 || s), d)))
print(VarCorr(f_ok)); cat("theta length:", length(getME(f_ok, "theta")), "\n")
