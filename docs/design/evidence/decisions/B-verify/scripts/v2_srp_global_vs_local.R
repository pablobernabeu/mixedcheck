# B-verify v2: does report B's default rule SR-P, as specified ("accept an unprotected rung only if ... no
# random-effects covariance block is rank-deficient"), strip non-zero nuisance slopes whenever a PROTECTED focal
# slope is estimated at zero? And how do protected LRT(.2)/AIC (registered alternatives restricted to unprotected
# terms, never simulated by report B) compare with SR-P for the focal test?
# Design (Sim 3 of report B, extended): S units x m obs; focal x1 and nuisance x2 within units, correlation r;
# slope SDs tau_f (focal) and tau_n (nuisance); intercept SD .5; residual SD 1.
# Ladder (report B's ordering keys): rung0 = (1 + x1 + x2 | s) [ceiling]; rung1 = diag: (1 + x1 + x2 || s);
# rung2 = protected: (1 + x1 || s). Protected set = intercept + x1 slope.
# Rules:  SRP_global  : accept rung0 if converged & !isSingular; else rung1 if converged & !isSingular; else rung2.
#         SRP_local   : as SRP_global, but at rung1 step down only if non-convergent or the UNPROTECTED x2 slope is
#                       at the boundary (theta_x2 < 1e-4); singularity confined to protected terms is accepted.
#         LRT02_prot  : rung0 vs rung1 (3 correlations, naive chi2 df 3) at .2; then rung1 vs rung2 (df 1) at .2.
#         AIC_prot    : same path with AIC.
#         and fixed rungs 0, 1, 2.
# Inference: Satterthwaite t-test for x1 (lmerTest 3.1-3), REML. lme4 1.1-35.1.
# Usage: Rscript v2_srp_global_vs_local.R <S> <m> <tau_f> <tau_n> <r> <beta1> <nrep> <seed> <outfile>
suppressPackageStartupMessages({library(lme4); library(lmerTest); library(parallel)})
a <- commandArgs(trailingOnly = TRUE)
S <- as.integer(a[1]); m <- as.integer(a[2]); tau_f <- as.numeric(a[3]); tau_n <- as.numeric(a[4])
r <- as.numeric(a[5]); beta1 <- as.numeric(a[6]); nrep <- as.integer(a[7]); seed <- as.integer(a[8]); outfile <- a[9]
sim_data <- function() {
  s <- rep(seq_len(S), each = m)
  x1 <- rnorm(S * m); x2 <- r * x1 + sqrt(1 - r^2) * rnorm(S * m)
  y <- beta1 * x1 + 0.3 * x2 + rnorm(S, 0, .5)[s] + rnorm(S, 0, tau_f)[s] * x1 + rnorm(S, 0, tau_n)[s] * x2 + rnorm(S * m)
  data.frame(s = factor(s), x1, x2, y)
}
fit1 <- function(form, d) {
  w <- character(0)
  f <- withCallingHandlers(tryCatch(lmer(form, data = d, REML = TRUE), error = function(e) NULL),
         warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") },
         message = function(x) invokeRestart("muffleMessage"))
  if (is.null(f)) return(list(ok = FALSE, conv = FALSE, sing = NA, p = NA, se = NA, df = NA, ll = NA, aic = NA, thx2 = NA, thx1 = NA))
  co <- tryCatch(summary(f)$coefficients, error = function(e) NULL)
  th <- getME(f, "theta"); nm <- names(th)
  list(ok = TRUE, conv = !any(grepl("converge|unidentifiable|degenerate", w)), sing = isSingular(f),
       p = if (is.null(co)) NA else co["x1", "Pr(>|t|)"], se = if (is.null(co)) NA else co["x1", "Std. Error"],
       df = if (is.null(co)) NA else co["x1", "df"], ll = as.numeric(logLik(f)), aic = AIC(f),
       thx2 = { i <- grep("x2$", nm); if (length(i) == 1) unname(th[i]) else NA },
       thx1 = { i <- grep("x1$", nm); if (length(i) == 1) unname(th[i]) else NA })
}
forms <- list(r0 = y ~ x1 + x2 + (1 + x1 + x2 | s), r1 = y ~ x1 + x2 + (1 + x1 + x2 || s), r2 = y ~ x1 + x2 + (1 + x1 || s))
one_rep <- function(i) {
  d <- sim_data(); F <- lapply(forms, fit1, d = d)
  good <- function(k) F[[k]]$ok && F[[k]]$conv && !isTRUE(F[[k]]$sing)
  srp_g <- if (good("r0")) "r0" else if (good("r1")) "r1" else "r2"
  r1_local_ok <- F$r1$ok && F$r1$conv && isTRUE(F$r1$thx2 >= 1e-4)
  srp_l <- if (good("r0")) "r0" else if (r1_local_ok) "r1" else "r2"
  lrt <- function(b, s, df) pchisq(max(2 * (F[[b]]$ll - F[[s]]$ll), 0), df, lower.tail = FALSE)
  keep <- function(b, s, df, crit) { if (!F[[b]]$ok) return(FALSE); if (!F[[s]]$ok) return(TRUE)
    if (crit == "lrt") lrt(b, s, df) < .2 else F[[b]]$aic < F[[s]]$aic }
  path <- function(crit) if (keep("r0", "r1", 3, crit)) "r0" else if (keep("r1", "r2", 1, crit)) "r1" else "r2"
  sel <- c(SRP_global = srp_g, SRP_local = srp_l, LRT02_prot = path("lrt"), AIC_prot = path("aic"),
           rung0 = "r0", rung1 = "r1", rung2 = "r2")
  data.frame(rep = i, rule = names(sel), rung = unname(sel), p = sapply(sel, function(k) F[[k]]$p),
             se = sapply(sel, function(k) F[[k]]$se), df = sapply(sel, function(k) F[[k]]$df),
             r0_sing = F$r0$sing, r0_conv = F$r0$conv, r1_sing = F$r1$sing, r1_conv = F$r1$conv,
             r1_thx1 = F$r1$thx1, r1_thx2 = F$r1$thx2, stringsAsFactors = FALSE)
}
RNGkind("L'Ecuyer-CMRG"); set.seed(seed); t0 <- Sys.time()
res <- do.call(rbind, mclapply(seq_len(nrep), one_rep, mc.cores = 4, mc.set.seed = TRUE))
res$S <- S; res$m <- m; res$tau_f <- tau_f; res$tau_n <- tau_n; res$r <- r; res$beta1 <- beta1
write.csv(res, outfile, row.names = FALSE)
cat(sprintf("done S=%d m=%d tau_f=%.2f tau_n=%.2f r=%.2f beta1=%.2f nrep=%d in %.1f s\n", S, m, tau_f, tau_n, r, beta1, nrep,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
