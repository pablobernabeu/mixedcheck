# Sim 3: does the order of dropping slopes matter? Focal within-unit predictor x1, nuisance within-unit x2.
# S units, m observations each. Both slopes vary across units (SD tau each). x1, x2 correlated within unit (r).
# Fits (all zero-correlation to isolate the slope question; x1, x2 continuous so '||' is well defined):
#   full: (1 + x1 + x2 || s); drop_nuis: (1 + x1 || s); drop_focal: (1 + x2 || s); ri: (1 | s).
# Reports Type I error / power for beta1 (Satterthwaite).
# Usage: Rscript sim3_nuisance_order.R <S> <m> <tau> <r> <beta1> <nrep> <seed> <outfile>
suppressPackageStartupMessages({library(lme4); library(lmerTest); library(parallel)})
a <- commandArgs(trailingOnly = TRUE)
S <- as.integer(a[1]); m <- as.integer(a[2]); tau <- as.numeric(a[3]); r <- as.numeric(a[4])
beta1 <- as.numeric(a[5]); nrep <- as.integer(a[6]); seed <- as.integer(a[7]); outfile <- a[8]
sim_data <- function() {
  s <- rep(seq_len(S), each = m)
  x1 <- rnorm(S * m); x2 <- r * x1 + sqrt(1 - r^2) * rnorm(S * m)
  u0 <- rnorm(S, 0, 0.5)[s]; u1 <- rnorm(S, 0, tau)[s]; u2 <- rnorm(S, 0, tau)[s]
  y <- beta1 * x1 + 0.3 * x2 + u0 + u1 * x1 + u2 * x2 + rnorm(S * m)
  data.frame(s = factor(s), x1, x2, y)
}
fit_p <- function(form, d) {
  warn <- character(0)
  f <- withCallingHandlers(tryCatch(lmer(form, data = d), error = function(e) NULL),
    warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) invokeRestart("muffleMessage"))
  if (is.null(f)) return(c(p = NA, sing = NA, se = NA))
  co <- summary(f)$coefficients
  c(p = co["x1", "Pr(>|t|)"], sing = isSingular(f), se = co["x1", "Std. Error"])
}
forms <- list(full = y ~ x1 + x2 + (1 + x1 + x2 || s), drop_nuis = y ~ x1 + x2 + (1 + x1 || s),
              drop_focal = y ~ x1 + x2 + (1 + x2 || s), ri = y ~ x1 + x2 + (1 | s))
one_rep <- function(i) {
  d <- sim_data(); R <- t(sapply(forms, fit_p, d = d))
  data.frame(rep = i, model = rownames(R), p = R[, "p"], sing = R[, "sing"], se = R[, "se"])
}
RNGkind("L'Ecuyer-CMRG"); set.seed(seed); t0 <- Sys.time()
res <- do.call(rbind, mclapply(seq_len(nrep), one_rep, mc.cores = 4, mc.set.seed = TRUE))
res$S <- S; res$m <- m; res$tau <- tau; res$r <- r; res$beta1 <- beta1
write.csv(res, outfile, row.names = FALSE)
cat(sprintf("done S=%d m=%d tau=%.2f r=%.2f beta1=%.2f nrep=%d in %.1f s\n", S, m, tau, r, beta1, nrep, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
