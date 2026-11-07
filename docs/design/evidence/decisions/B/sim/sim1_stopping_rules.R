# Sim 1: stopping rules for random-effects reduction in a crossed subjects x items design.
# One two-level focal factor A (coded -0.5/+0.5), within subject and within item (Latin square).
# Compares: maximal (no reduction), random intercepts only, back-off on singular-or-nonconvergent
# (role/design ordered ladder), back-off on nonconvergence only, LRT(alpha=.2) backward with
# data-driven order (Matuschek/Bates style), LRT(.2) with fixed design order, AIC backward.
# Inference on beta_A: Satterthwaite t-test (lmerTest) on the REML fit of the selected model.
# Usage: Rscript sim1_stopping_rules.R <nsubj> <nitem> <slopeSD> <beta> <nrep> <seed> <outfile>
suppressPackageStartupMessages({library(lme4); library(lmerTest); library(parallel)})
args <- commandArgs(trailingOnly = TRUE)
S <- as.integer(args[1]); I <- as.integer(args[2]); tau1 <- as.numeric(args[3])
beta <- as.numeric(args[4]); nrep <- as.integer(args[5]); seed <- as.integer(args[6]); outfile <- args[7]

sim_data <- function(S, I, tau1, beta, tau0s = 0.5, tau0i = 0.5, rho = 0.3, sigma = 1) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  mk <- function(n, t0, t1) {
    if (t1 == 0) return(cbind(rnorm(n, 0, t0), 0))
    Sig <- matrix(c(t0^2, rho * t0 * t1, rho * t0 * t1, t1^2), 2)
    MASS::mvrnorm(n, c(0, 0), Sig)
  }
  us <- mk(S, tau0s, tau1); wi <- mk(I, tau0i, tau1)
  s <- as.integer(d$subj); i <- as.integer(d$item)
  d$y <- beta * d$A + us[s, 1] + us[s, 2] * d$A + wi[i, 1] + wi[i, 2] * d$A + rnorm(nrow(d), 0, sigma)
  d
}

fit1 <- function(form, d) {
  warn <- character(0)
  f <- withCallingHandlers(
    tryCatch(lmer(form, data = d, REML = TRUE), error = function(e) NULL),
    warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) invokeRestart("muffleMessage"))
  if (is.null(f)) return(list(fit = NULL, ok = FALSE, sing = NA, conv = FALSE, p = NA, ll = NA, aic = NA, npar = NA, vc = NA))
  conv <- !any(grepl("converge|unidentifiable|degenerate", warn))
  sing <- isSingular(f)
  p <- tryCatch(suppressMessages(suppressWarnings(summary(f)$coefficients["A", "Pr(>|t|)"])), error = function(e) NA)
  vc <- as.data.frame(VarCorr(f))
  list(fit = f, ok = TRUE, sing = sing, conv = conv, p = p, ll = as.numeric(logLik(f)),
       npar = attr(logLik(f), "df"), aic = AIC(f), vc = vc)
}

forms <- list(
  max  = y ~ A + (1 + A | subj) + (1 + A | item),
  zcp  = y ~ A + (1 + A || subj) + (1 + A || item),
  noIs = y ~ A + (1 + A || subj) + (1 | item),   # item slope dropped (fewer levels -> lower design information)
  noSs = y ~ A + (1 | subj) + (1 + A || item),   # subject slope dropped
  ri   = y ~ A + (1 | subj) + (1 | item)
)

slopevar <- function(r, grp) { v <- r$vc; x <- v$vcov[v$grp == grp & v$var1 == "A" & is.na(v$var2)]; if (length(x)) x else NA }
lrt_p <- function(big, small, df) { st <- 2 * (big$ll - small$ll); pchisq(max(st, 0), df = df, lower.tail = FALSE) }

one_rep <- function(r) {
  d <- sim_data(S, I, tau1, beta)
  F <- lapply(forms, fit1, d = d)
  good <- function(x) x$ok && x$conv && !isTRUE(x$sing)
  okconv <- function(x) x$ok && x$conv
  # (1) back-off on singular OR nonconvergent, design/role order: max -> zcp -> drop item slope -> ri
  lad <- c("max", "zcp", "noIs", "ri")
  b_sing <- "ri"; for (k in lad) if (good(F[[k]])) { b_sing <- k; break }
  # (2) back-off on nonconvergence only
  b_conv <- "ri"; for (k in lad) if (okconv(F[[k]])) { b_conv <- k; break }
  # (2b) protected back-off: focal slopes never dropped; correlations removed on failure; zcp kept even if singular
  b_prot <- if (good(F$max)) "max" else if (F$zcp$ok) "zcp" else "max"
  # (3) LRT alpha .2 backward, data-driven order (smaller estimated slope variance dropped first)
  lrt_path <- function(alpha, order = c("data", "design"), crit = c("lrt", "aic")) {
    order <- match.arg(order); crit <- match.arg(crit)
    keep_big <- function(big, small, df) {
      if (!big$ok) return(FALSE); if (!small$ok) return(TRUE)
      if (crit == "lrt") lrt_p(big, small, df) < alpha else big$aic < small$aic
    }
    if (keep_big(F$max, F$zcp, 2)) return("max")
    vS <- slopevar(F$zcp, "subj"); vI <- slopevar(F$zcp, "item")
    first <- if (order == "design") "item" else if (isTRUE(vI <= vS)) "item" else "subj"
    if (first == "item") {
      if (keep_big(F$zcp, F$noIs, 1)) return("zcp")
      if (keep_big(F$noIs, F$ri, 1)) return("noIs") else return("ri")
    } else {
      if (keep_big(F$zcp, F$noSs, 1)) return("zcp")
      if (keep_big(F$noSs, F$ri, 1)) return("noSs") else return("ri")
    }
  }
  sel <- c(maximal = "max", ri_only = "ri", backoff_sing_or_conv = b_sing, backoff_conv_only = b_conv,
           backoff_protected = b_prot,
           lrt02_data = lrt_path(0.2, "data", "lrt"), lrt02_design = lrt_path(0.2, "design", "lrt"),
           lrt05_data = lrt_path(0.05, "data", "lrt"), aic_data = lrt_path(NA, "data", "aic"))
  out <- data.frame(rep = r, strategy = names(sel), rung = unname(sel),
                    p = sapply(sel, function(k) F[[k]]$p),
                    sing_rung = sapply(sel, function(k) F[[k]]$sing),
                    conv_rung = sapply(sel, function(k) F[[k]]$conv), stringsAsFactors = FALSE)
  out$max_sing <- F$max$sing; out$max_conv <- F$max$conv
  out
}

RNGkind("L'Ecuyer-CMRG"); set.seed(seed)
t0 <- Sys.time()
res <- do.call(rbind, mclapply(seq_len(nrep), one_rep, mc.cores = 4, mc.set.seed = TRUE))
res$S <- S; res$I <- I; res$tau1 <- tau1; res$beta <- beta
write.csv(res, outfile, row.names = FALSE)
cat(sprintf("done S=%d I=%d tau1=%.2f beta=%.2f nrep=%d in %.1f s\n", S, I, tau1, beta, nrep, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
