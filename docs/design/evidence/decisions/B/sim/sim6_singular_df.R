# Sim 6: when the protected (zero-correlation) rung is singular because a focal slope variance is ~0,
# does keeping the zero-variance term change the SE or only the Satterthwaite df, relative to the
# rung without that term? Small crossed design of Sim 1 (24 x 16), tau = 0 and 0.1, H1 beta = .25.
suppressPackageStartupMessages({library(lme4); library(lmerTest); library(parallel)})
S <- 24; I <- 16
sim_data <- function(tau1, beta) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  s <- as.integer(d$subj); i <- as.integer(d$item)
  us <- cbind(rnorm(S, 0, .5), rnorm(S, 0, tau1)); wi <- cbind(rnorm(I, 0, .5), rnorm(I, 0, tau1))
  d$y <- beta * d$A + us[s, 1] + us[s, 2] * d$A + wi[i, 1] + wi[i, 2] * d$A + rnorm(nrow(d)); d
}
q <- function(form, d) {
  f <- suppressMessages(suppressWarnings(lmer(form, d)))
  co <- summary(f)$coefficients["A", ]; vc <- as.data.frame(VarCorr(f))
  list(se = co[["Std. Error"]], df = co[["df"]], p = co[["Pr(>|t|)"]],
       vS = vc$vcov[vc$grp == "subj.1"], vI = vc$vcov[vc$grp == "item.1"], sing = isSingular(f))
}
one <- function(r, tau1) {
  d <- sim_data(tau1, 0.25)
  z <- q(y ~ A + (1 + A || subj) + (1 + A || item), d)
  if (!isTRUE(z$sing)) return(NULL)
  # drop exactly the slope terms whose variance is estimated at (near) zero
  zeroS <- z$vS < 1e-8; zeroI <- z$vI < 1e-8
  if (!zeroS && !zeroI) return(data.frame(r, tau1, kind = "singular_but_no_zero_slope", se_keep = z$se, se_drop = NA, df_keep = z$df, df_drop = NA, p_keep = z$p, p_drop = NA))
  form <- as.formula(paste("y ~ A +", if (zeroS) "(1 | subj)" else "(1 + A || subj)", "+", if (zeroI) "(1 | item)" else "(1 + A || item)"))
  dd <- q(form, d)
  data.frame(r, tau1, kind = paste0("zero:", if (zeroS) "S" else "", if (zeroI) "I" else ""),
             se_keep = z$se, se_drop = dd$se, df_keep = z$df, df_drop = dd$df, p_keep = z$p, p_drop = dd$p)
}
RNGkind("L'Ecuyer-CMRG"); set.seed(606)
res <- do.call(rbind, c(mclapply(1:400, one, tau1 = 0, mc.cores = 4), mclapply(1:400, one, tau1 = 0.1, mc.cores = 4)))
write.csv(res, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim/out/sim6_singular_df.csv", row.names = FALSE)
k <- res[res$kind != "singular_but_no_zero_slope", ]
cat("singular protected fits analysed:", nrow(res), "; with a zero focal-slope variance:", nrow(k), "\n")
cat("median |SE_keep/SE_drop - 1|:", signif(median(abs(k$se_keep / k$se_drop - 1)), 3), "; max:", signif(max(abs(k$se_keep / k$se_drop - 1)), 3), "\n")
cat("median df keep vs drop:", round(median(k$df_keep), 1), "vs", round(median(k$df_drop), 1), "; share with df_keep < df_drop:", round(mean(k$df_keep < k$df_drop), 3), "\n")
cat("rejection at .05 (H1, beta=.25): keep", round(mean(k$p_keep < .05), 3), "drop", round(mean(k$p_drop < .05), 3), "\n")
print(table(res$kind, res$tau1))
