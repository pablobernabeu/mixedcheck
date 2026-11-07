# B-verify v3: (a) probability that a rule with true Type I error .05 exceeds report B's .06 switching threshold in
# at least one of k cells (2,000 replicates per cell); (b) timing of Satterthwaite vs Kenward-Roger df and of one
# parametric-bootstrap LRT replicate set for the 48 x 32 crossed design (lme4 1.1-35.1, lmerTest 3.1-3, pbkrtest 0.5.2).
suppressPackageStartupMessages({library(lme4); library(lmerTest)})
p1 <- pbinom(floor(.06 * 2000), 2000, .05, lower.tail = FALSE)   # P(phat > .06)
cat(sprintf("P(phat > .06 | p = .05, n = 2000) = %.4f\n", p1))
for (k in c(10, 20, 50, 100, 200)) cat(sprintf("  P(at least one of %3d cells > .06) = %.3f\n", k, 1 - (1 - p1)^k))
p2 <- pbinom(floor(.06 * 2000), 2000, .055, lower.tail = FALSE)
cat(sprintf("If true rate is .055: P(phat > .06) per cell = %.3f\n", p2))
set.seed(1)
mk <- function(S, I) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  s <- as.integer(d$subj); i <- as.integer(d$item)
  d$y <- 0.2 * d$A + rnorm(S, 0, .5)[s] + rnorm(S, 0, .2)[s] * d$A + rnorm(I, 0, .5)[i] + rnorm(I, 0, .2)[i] * d$A + rnorm(nrow(d))
  d }
for (sz in list(c(24, 16), c(48, 32), c(96, 64))) {
  d <- mk(sz[1], sz[2])
  t_fit <- system.time(f <- suppressMessages(lmer(y ~ A + (1 + A || subj) + (1 + A || item), d)))[["elapsed"]]
  t_sat <- system.time(s1 <- summary(f, ddf = "Satterthwaite"))[["elapsed"]]
  t_kr <- if (nrow(d) <= 3072) system.time(s2 <- summary(f, ddf = "Kenward-Roger"))[["elapsed"]] else NA
  cat(sprintf("S=%d I=%d n=%d: fit %.2fs; Satterthwaite %.2fs; KR %s s\n", sz[1], sz[2], nrow(d), t_fit, t_sat,
              if (is.na(t_kr)) "skipped (n > 3072)" else sprintf("%.2f", t_kr)))
}
# parametric bootstrap LRT for the focal fixed effect: B refits of two models per replicate
d <- mk(48, 32)
f1 <- suppressMessages(lmer(y ~ A + (1 + A || subj) + (1 + A || item), d, REML = FALSE))
f0 <- suppressMessages(lmer(y ~ 1 + (1 + A || subj) + (1 + A || item), d, REML = FALSE))
B <- 50
tb <- system.time(for (b in seq_len(B)) { ys <- simulate(f0)[[1]]; suppressMessages({refit(f0, ys); refit(f1, ys)}) })[["elapsed"]]
cat(sprintf("Parametric bootstrap, 48 x 32: %.3f s per bootstrap draw (two refits); 1,000 draws x 2,000 replicates = %.0f CPU-hours per cell\n",
            tb / B, tb / B * 1000 * 2000 / 3600))
