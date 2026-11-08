# Sim 2: cross-level interaction (Heisig & Schaeffer 2019 setting, education-like two-level data).
# Pupils (n per cluster) in J clusters. x = level-1 predictor (cluster-mean centred), z = level-2 predictor.
# y = 0.3x + 0.3z + b3*x*z + u0 + u1*x + e. Tests b3 (cross-level interaction) under each strategy.
# Strategies: RI only; random slope (correlated) kept regardless; back-off on singular-or-nonconvergent
# (RS -> RS zero-corr -> RI); LRT(alpha=.2) backward; AIC backward.
# Usage: Rscript sim2_crosslevel.R <J> <n> <tau1> <b3> <nrep> <seed> <outfile>
suppressPackageStartupMessages({library(lme4); library(lmerTest); library(parallel)})
a <- commandArgs(trailingOnly = TRUE)
J <- as.integer(a[1]); n <- as.integer(a[2]); tau1 <- as.numeric(a[3]); b3 <- as.numeric(a[4])
nrep <- as.integer(a[5]); seed <- as.integer(a[6]); outfile <- a[7]

sim_data <- function() {
  g <- rep(seq_len(J), each = n)
  x <- rnorm(J * n); x <- x - ave(x, g)            # purely within-cluster predictor
  z <- rnorm(J)[g]
  u0 <- rnorm(J, 0, 0.5)[g]; u1 <- rnorm(J, 0, tau1)[g]
  y <- 0.3 * x + 0.3 * z + b3 * x * z + u0 + u1 * x + rnorm(J * n)
  data.frame(g = factor(g), x, z, y)
}
fit1 <- function(form, d) {
  warn <- character(0)
  f <- withCallingHandlers(tryCatch(lmer(form, data = d, REML = TRUE), error = function(e) NULL),
    warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) invokeRestart("muffleMessage"))
  if (is.null(f)) return(list(ok = FALSE, conv = FALSE, sing = NA, p = NA, ll = NA, aic = NA))
  list(ok = TRUE, conv = !any(grepl("converge|unidentifiable|degenerate", warn)), sing = isSingular(f),
       p = tryCatch(summary(f)$coefficients["x:z", "Pr(>|t|)"], error = function(e) NA),
       ll = as.numeric(logLik(f)), aic = AIC(f))
}
forms <- list(rs = y ~ x * z + (1 + x | g), zcp = y ~ x * z + (1 + x || g), ri = y ~ x * z + (1 | g))
one_rep <- function(r) {
  d <- sim_data(); F <- lapply(forms, fit1, d = d)
  good <- function(k) F[[k]]$ok && F[[k]]$conv && !isTRUE(F[[k]]$sing)
  b_sing <- "ri"; for (k in c("rs", "zcp", "ri")) if (good(k)) { b_sing <- k; break }
  lr <- function(b, s, df) pchisq(max(2 * (F[[b]]$ll - F[[s]]$ll), 0), df, lower.tail = FALSE)
  path <- function(keep) { if (keep("rs", "zcp", 1)) "rs" else if (keep("zcp", "ri", 1)) "zcp" else "ri" }
  sel <- c(ri_only = "ri", rs_always = "rs", backoff_sing_or_conv = b_sing,
           lrt02 = path(function(b, s, df) lr(b, s, df) < 0.2),
           aic = path(function(b, s, df) F[[b]]$aic < F[[s]]$aic))
  data.frame(rep = r, strategy = names(sel), rung = unname(sel), p = sapply(sel, function(k) F[[k]]$p),
             rs_sing = F$rs$sing, rs_conv = F$rs$conv, stringsAsFactors = FALSE)
}
RNGkind("L'Ecuyer-CMRG"); set.seed(seed); t0 <- Sys.time()
res <- do.call(rbind, mclapply(seq_len(nrep), one_rep, mc.cores = 4, mc.set.seed = TRUE))
res$J <- J; res$n <- n; res$tau1 <- tau1; res$b3 <- b3
write.csv(res, outfile, row.names = FALSE)
cat(sprintf("done J=%d n=%d tau1=%.2f b3=%.2f nrep=%d in %.1f s\n", J, n, tau1, b3, nrep, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
