# F-verify exp3: does F's pilot (naive Bartlett test across clusters on raw conditional residuals,
# false-flag rate .036-.062) test what catalogue item L5-03 predicts? L5-03 says the artefact
# appears in comparisons ACROSS CLUSTER SIZES. Here, under a correctly specified model, compare
#   T1 Bartlett across clusters, raw residuals (F's operationalisation)
#   T2 Brown-Forsythe (Levene, median-centred) across cluster-size strata, raw residuals
#   T3 the same on studentised conditional residuals r / (sigma_hat * sqrt(1 - h_ii))
# Usage: Rscript exp3_l503.R <out_csv> [reps]
suppressPackageStartupMessages(library(lme4))
args <- commandArgs(trailingOnly = TRUE); out_csv <- args[1]
reps <- if (length(args) >= 2) as.integer(args[2]) else 500
RNGkind("L'Ecuyer-CMRG"); set.seed(20261110)
bf_test <- function(r, grp) {            # Brown-Forsythe: one-way ANOVA on |r - group median|
  grp <- droplevels(factor(grp)); dev <- abs(r - ave(r, grp, FUN = median))
  anova(lm(dev ~ grp))[["Pr(>F)"]][1]
}
cells <- list(
  list(id = "F-pilot cell 4: J40 m5 cv.5 icc.3 slope.15", J = 40, sizes = "gamma", m = 5, cv = .5, icc = .3, tau1 = .15),
  list(id = "J40 sizes 2/5/20/50 icc.3 RI", J = 40, sizes = "fixed", icc = .3, tau1 = 0),
  list(id = "J40 sizes 2/5/20/50 icc.5 RI", J = 40, sizes = "fixed", icc = .5, tau1 = 0),
  list(id = "J100 sizes 2/5/20/50 icc.3 RI", J = 100, sizes = "fixed", icc = .3, tau1 = 0))
res <- list()
for (cl in cells) {
  flags <- matrix(NA, reps, 3)
  for (r in seq_len(reps)) {
    J <- cl$J
    sz <- if (cl$sizes == "gamma") pmax(2L, round(cl$m * rgamma(J, 1 / cl$cv^2, 1 / cl$cv^2))) else rep(c(2L, 5L, 20L, 50L), each = J / 4)
    g <- factor(rep(seq_len(J), sz)); n <- length(g); gi <- as.integer(g)
    x <- rnorm(J, 0, .5)[gi] + rnorm(n); z <- rep(rep(c(-.5, .5), length.out = J), sz)
    tau0 <- sqrt(cl$icc / (1 - cl$icc))
    y <- 0.2 * x + 0.3 * z + rnorm(J, 0, tau0)[gi] + rnorm(J, 0, cl$tau1)[gi] * x + rnorm(n)
    d <- data.frame(g, x, z, y)
    f <- suppressMessages(suppressWarnings(if (cl$tau1 > 0) lmer(y ~ x + z + (1 + x | g), d) else lmer(y ~ x + z + (1 | g), d)))
    e <- residuals(f); h <- hatvalues(f); es <- e / (sigma(f) * sqrt(pmax(1 - h, 1e-12)))
    nj <- sz[gi]
    stratum <- if (cl$sizes == "gamma") cut(nj, c(0, 3, 6, Inf)) else factor(nj)
    keep <- nj >= 2
    flags[r, 1] <- isTRUE(tryCatch(bartlett.test(e[keep], droplevels(g[keep]))$p.value, error = function(err) NA) < .05)
    flags[r, 2] <- isTRUE(bf_test(e, stratum) < .05)
    flags[r, 3] <- isTRUE(bf_test(es, stratum) < .05)
  }
  p <- colMeans(flags)
  res[[length(res) + 1]] <- data.frame(cell = cl$id, reps = reps,
    test = c("T1 Bartlett by cluster, raw (F pilot)", "T2 Brown-Forsythe by size stratum, raw", "T3 Brown-Forsythe by size stratum, studentised"),
    false_flag_rate = p, mcse = sqrt(p * (1 - p) / reps))
  cat(cl$id, round(p, 3), "\n")
}
out <- do.call(rbind, res); write.csv(out, out_csv, row.names = FALSE); print(out, digits = 3)
