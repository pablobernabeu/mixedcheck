# Sim 5: is a REML-based random-effects selection invariant to the focal fixed effect?
# Theory: the REML criterion depends on y only through error contrasts K'y with K'X = 0, so adding X %*% b
# for any b leaves REML fits (theta, REMLcrit, singularity) unchanged. Profiled ML should also be invariant
# (beta is profiled out); GLMMs lack the property because y cannot be shifted along X*beta.
# Check on 200 simulated crossed datasets: fit each ladder rung on y and on y + A*b_mask (b_mask = 3.7)
# and compare theta, criterion, singular flag and warning status (REML and ML).
suppressPackageStartupMessages(library(lme4))
set.seed(7)
S <- 24; I <- 16
forms <- list(max = y ~ A + (1 + A | subj) + (1 + A | item), zcp = y ~ A + (1 + A || subj) + (1 + A || item),
              noIs = y ~ A + (1 + A || subj) + (1 | item), ri = y ~ A + (1 | subj) + (1 | item))
res <- NULL
for (r in 1:200) {
  d <- expand.grid(subj = factor(1:S), item = factor(1:I))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  tau <- sample(c(0, 0.2, 0.4), 1)
  us <- cbind(rnorm(S, 0, .5), rnorm(S, 0, tau)); wi <- cbind(rnorm(I, 0, .5), rnorm(I, 0, tau))
  s <- as.integer(d$subj); i <- as.integer(d$item)
  d$y <- 0.25 * d$A + us[s, 1] + us[s, 2] * d$A + wi[i, 1] + wi[i, 2] * d$A + rnorm(nrow(d))
  dm <- d; dm$y <- d$y + 3.7 * d$A
  for (k in names(forms)) {
    q <- function(dd, REML) { w <- character(0)
      f <- withCallingHandlers(lmer(forms[[k]], dd, REML = REML),
             warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") },
             message = function(x) invokeRestart("muffleMessage"))
      list(th = getME(f, "theta"), crit = deviance(f, REML = REML), sing = isSingular(f), warn = length(w) > 0,
           b = fixef(f)["A"]) }
    a <- q(d, TRUE); b <- q(dm, TRUE); am <- q(d, FALSE); bm <- q(dm, FALSE)
    res <- rbind(res, data.frame(rep = r, rung = k, tau = tau,
      reml_max_abs_dtheta = max(abs(a$th - b$th)), reml_dcrit = abs(a$crit - b$crit),
      reml_same_sing = a$sing == b$sing, reml_same_warn = a$warn == b$warn,
      reml_dbeta_minus_mask = abs((b$b - a$b) - 3.7),
      ml_max_abs_dtheta = max(abs(am$th - bm$th)), ml_dcrit = abs(am$crit - bm$crit), ml_same_sing = am$sing == bm$sing))
  }
}
cat("REML: max |d theta| =", signif(max(res$reml_max_abs_dtheta), 3), "; max |d REMLcrit| =", signif(max(res$reml_dcrit), 3),
    "; singular flag identical in", mean(res$reml_same_sing) * 100, "% of fits; warning status identical in",
    mean(res$reml_same_warn) * 100, "%\n")
cat("REML: max |(beta_masked - beta) - b_mask| =", signif(max(res$reml_dbeta_minus_mask), 3), "\n")
cat("ML:   max |d theta| =", signif(max(res$ml_max_abs_dtheta), 3), "; max |d deviance| =", signif(max(res$ml_dcrit), 3),
    "; singular flag identical in", mean(res$ml_same_sing) * 100, "%\n")
write.csv(res, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim/out/sim5_reml_masking.csv", row.names = FALSE)
