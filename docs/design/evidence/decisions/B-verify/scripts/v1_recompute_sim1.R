# B-verify v1: independent recomputation of report B's Sim 1 summaries from the raw per-replicate CSVs.
# Checks: (1) which files the published small-design summary used (original vs rerun);
# (2) whether shared strategies reproduce exactly between original and rerun;
# (3) paired power / Type I differences between rules with Monte Carlo SEs (paired, same data sets).
B <- "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim/out"
rd <- function(dir, pat) { fs <- list.files(dir, pat, full.names = TRUE); do.call(rbind, lapply(fs, read.csv, stringsAsFactors = FALSE)) }
orig <- rd(B, "^sim1_S24_I16_.*\\.csv$")
rer  <- rd(file.path(B, "rerun"), "^sim1_S24_I16_.*\\.csv$")
lrg  <- rd(B, "^sim1_S48_I32_.*\\.csv$")
cat("strategies in original small files:\n"); print(table(orig$strategy, paste(orig$tau1, orig$beta))[, 1:8] > 0)
cat("\nstrategies in rerun small files:\n"); print(unique(rer$strategy))
# (2) reproducibility of shared strategies
key <- c("tau1", "beta", "rep", "strategy")
m <- merge(orig, rer, by = key, suffixes = c(".o", ".r"))
cat("\nshared rows:", nrow(m), "; identical p:", sum(abs(m$p.o - m$p.r) < 1e-12 | (is.na(m$p.o) & is.na(m$p.r))),
    "; identical rung:", sum(m$rung.o == m$rung.r), "\n")
# (1) recompute rejection rates from rerun files
rate <- function(d) { a <- aggregate(p ~ tau1 + beta + strategy, d, function(x) mean(x < .05), na.action = na.pass)
  n <- aggregate(p ~ tau1 + beta + strategy, d, length, na.action = na.pass); a$n <- n$p; a$mcse <- sqrt(a$p * (1 - a$p) / a$n); a }
r1 <- rate(rer); r1 <- r1[order(r1$beta, r1$tau1, r1$strategy), ]
pub <- read.csv(file.path(B, "sim1_summary_small.csv"))
cmp <- merge(r1, pub[, c("tau1", "beta", "strategy", "reject_rate")], by = c("tau1", "beta", "strategy"))
cat("\nmax |recomputed - published| (small, from rerun files):", max(abs(round(cmp$p, 3) - cmp$reject_rate)), "\n")
r0 <- rate(orig); cmp0 <- merge(r0, pub[, c("tau1", "beta", "strategy", "reject_rate")], by = c("tau1", "beta", "strategy"))
cat("max |recomputed - published| (small, from original files, shared strategies):", max(abs(round(cmp0$p, 3) - cmp0$reject_rate)), "\n")
rl <- rate(lrg); publ <- read.csv(file.path(B, "sim1_summary_large.csv"))
cmpl <- merge(rl, publ[, c("tau1", "beta", "strategy", "reject_rate")], by = c("tau1", "beta", "strategy"))
cat("max |recomputed - published| (large):", max(abs(round(cmpl$p, 3) - cmpl$reject_rate)), "\n")
# (3) paired differences vs the protected rule
pd <- function(d, s1, s2) {
  w <- reshape(d[d$strategy %in% c(s1, s2), c("tau1", "beta", "rep", "strategy", "p")], idvar = c("tau1", "beta", "rep"),
               timevar = "strategy", direction = "wide")
  w$x <- (w[[paste0("p.", s1)]] < .05) - (w[[paste0("p.", s2)]] < .05)
  a <- aggregate(x ~ tau1 + beta, w, function(z) c(diff = mean(z), mcse = sd(z) / sqrt(length(z)), discordant = mean(z != 0)))
  a <- do.call(data.frame, a); a$cmp <- paste(s1, "-", s2); a }
out <- rbind(pd(rer, "backoff_sing_or_conv", "backoff_protected"), pd(rer, "lrt02_data", "backoff_protected"),
             pd(rer, "aic_data", "backoff_protected"), pd(rer, "backoff_protected", "maximal"),
             pd(rer, "lrt02_design", "lrt02_data"),
             pd(lrg, "backoff_sing_or_conv", "backoff_protected"), pd(lrg, "lrt02_data", "backoff_protected"), pd(lrg, "aic_data", "backoff_protected"))
out$design <- rep(c(rep("24x16", 5 * 8), rep("48x32", 3 * 4)), length.out = nrow(out))
num <- sapply(out, is.numeric); out[num] <- lapply(out[num], round, 4)
print(out, row.names = FALSE)
write.csv(out, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify/out/v1_paired_differences.csv", row.names = FALSE)
