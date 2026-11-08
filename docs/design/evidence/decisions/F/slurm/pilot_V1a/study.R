# Pilot slice of study V1a (Gaussian nested null bank). Correctly specified model, so every
# flag here is a false flag. Records: lme4 singular flag (theta < 1e-4), a unit-free rank
# criterion (smallest eigenvalue of the RE correlation-scale covariance relative to its largest),
# a naive Bartlett test of equal residual variance across clusters on raw conditional residuals
# (catalogue L5-03 predicts over-flagging with small, unequal clusters), and Wald 95% CI coverage
# for the level-1 slope (true value 0.2).
suppressPackageStartupMessages(library(lme4))
study_id <- "V1a-pilot"
iseed <- 20261107L
generate <- function(cell) {
  J <- cell$J; m <- cell$m; cv <- cell$cv
  sz <- if (cv > 0) pmax(2L, round(m * rgamma(J, 1 / cv^2, 1 / cv^2))) else rep(as.integer(m), J)
  g <- factor(rep(seq_len(J), sz)); n <- length(g); gi <- as.integer(g)
  x <- rnorm(J, 0, .5)[gi] + rnorm(n); z <- rep(rep(c(-.5, .5), length.out = J), sz)
  tau0 <- sqrt(cell$icc / (1 - cell$icc))
  y <- 0.2 * x + 0.3 * z + rnorm(J, 0, tau0)[gi] + rnorm(J, 0, cell$tau1)[gi] * x + rnorm(n)
  data.frame(g, x, z, y)
}
analyse <- function(cell, dat) {
  f <- lmer(y ~ x + z + (1 + x | g), data = dat, REML = TRUE)
  vc <- VarCorr(f)$g; S <- as.matrix(vc); D <- diag(1 / sqrt(pmax(diag(S), 1e-300)), nrow(S))
  ev <- eigen(S, symmetric = TRUE, only.values = TRUE)$values
  ev_cor <- eigen(D %*% S %*% D, symmetric = TRUE, only.values = TRUE)$values
  cf <- summary(f)$coefficients
  r <- residuals(f); keep <- table(dat$g)[as.character(dat$g)] >= 2
  bt <- tryCatch(bartlett.test(r[keep], droplevels(dat$g[keep]))$p.value, error = function(e) NA_real_)
  est <- cf["x", "Estimate"]; se <- cf["x", "Std. Error"]
  list(status = "ok", singular_lme4 = isSingular(f), min_eig_rel = min(ev) / max(ev),
       min_eig_cor = min(ev_cor), conv_msg = length(f@optinfo$conv$lme4$messages) > 0,
       bartlett_raw_flag = isTRUE(bt < .05), est_x = est, se_x = se,
       cover_x = abs(est - 0.2) <= 1.959964 * se, n_obs = nrow(dat))
}
