# Does lme4 1.1-35.1's reported Laplace -2logLik equal its own deviance function at its estimates?
suppressPackageStartupMessages({library(lme4); library(glmmTMB)})
cat("lme4", as.character(packageVersion("lme4")), " glmmTMB", as.character(packageVersion("glmmTMB")), "\n")
d <- read.csv(file.path(commandArgs(TRUE)[1], "binxd.csv"), stringsAsFactors = FALSE)
chk <- function(fit, label) {
  dd <- update(fit, devFunOnly = TRUE)
  par <- c(getME(fit, "theta"), fixef(fit))
  dv1 <- dd(par)                    # lme4's own Laplace deviance at its estimates (fresh PIRLS)
  dv2 <- dd(par)                    # second evaluation (PIRLS state now at these estimates)
  rep <- -2 * as.numeric(logLik(fit))
  cat(sprintf("%-14s reported -2logL %.6f | devfun at estimates %.6f, again %.6f | reported - devfun = %.3e\n",
              label, rep, dv1, dv2, rep - dv2))
  invisible(c(rep = rep, devfun = dv2))
}
g1 <- glmer(cbind(incidence, size - incidence) ~ period + (1 | herd), data = cbpp, family = binomial)
chk(g1, "cbpp_laplace")
g2 <- glmer(cbind(y, n - y) ~ cond + (1 + cond | subj) + (1 | item), data = d, family = binomial)
chk(g2, "binxd_laplace")
# same estimates in glmmTMB: evaluate glmmTMB's objective at lme4's estimates (start + map fixes all params)
m0 <- glmmTMB(cbind(incidence, size - incidence) ~ period + (1 | herd), data = cbpp, family = binomial)
cat(sprintf("glmmTMB cbpp -2logL at its optimum %.6f\n", -2 * as.numeric(logLik(m0))))
