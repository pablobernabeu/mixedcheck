# Gaussian weights semantics: lme4 precision weights vs glmmTMB log-likelihood multipliers,
# and whether a dispersion offset makes glmmTMB reproduce lme4's weighted model.
suppressPackageStartupMessages({library(lme4); library(glmmTMB)})
d <- read.csv(file.path(commandArgs(TRUE)[1], "weighted.csv"))
cat("lme4", as.character(packageVersion("lme4")), "glmmTMB", as.character(packageVersion("glmmTMB")), "\n")
cat("mean weight", mean(d$w), "\n")
m1 <- lmer(y ~ x + (1 | g), d, weights = w, REML = FALSE)
m2 <- glmmTMB(y ~ x + (1 | g), d, weights = w, REML = FALSE)
cat(sprintf("lme4 weights: sigma %.4f  -2logL %.4f  beta %s\n", sigma(m1), -2*logLik(m1), paste(round(fixef(m1), 4), collapse=" ")))
cat(sprintf("glmmTMB weights: sigma %.4f  -2logL %.4f  beta %s\n", sigma(m2), -2*logLik(m2), paste(round(fixef(m2)$cond, 4), collapse=" ")))
d$lw <- log(d$w)
for (k in c(0.5, 1)) {
  m3 <- try(glmmTMB(y ~ x + (1 | g), d, dispformula = ~ 1 + offset(-k * lw), REML = FALSE), silent = TRUE)
  if (inherits(m3, "try-error")) { cat("dispformula offset k =", k, ": ERROR", conditionMessage(attr(m3, "condition")), "\n"); next }
  cat(sprintf("glmmTMB dispformula offset(-%.1f*log w): exp(betadisp) %.4f  -2logL %.4f  beta %s\n", k,
              exp(fixef(m3)$disp), -2*logLik(m3), paste(round(fixef(m3)$cond, 4), collapse=" ")))
}
# frequency-weight equivalence of glmmTMB: expand rows w times (integer weights)
de <- d[rep(seq_len(nrow(d)), d$w), ]
m4 <- glmmTMB(y ~ x + (1 | g), de, REML = FALSE)
cat(sprintf("glmmTMB on rows replicated w times: sigma %.4f  -2logL %.4f  beta %s\n", sigma(m4), -2*logLik(m4), paste(round(fixef(m4)$cond, 4), collapse=" ")))
