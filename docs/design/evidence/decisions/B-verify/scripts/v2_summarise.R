# Summarise v2 (SR-P as specified vs localised SR-P vs protected LRT(.2)/AIC).
d <- do.call(rbind, lapply(list.files("/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify/out",
                                      "^v2_tf.*\\.csv$", full.names = TRUE), read.csv, stringsAsFactors = FALSE))
d$rej <- d$p < .05
cells <- c("tau_f", "tau_n", "r", "beta1")
agg <- aggregate(cbind(rej = rej, se = se, drop_nuis = rung == "r2") ~ tau_f + tau_n + r + beta1 + rule, d, mean, na.action = na.pass)
n <- aggregate(rej ~ tau_f + tau_n + r + beta1 + rule, d, length, na.action = na.pass); agg$n <- n$rej
agg$mcse <- sqrt(agg$rej * (1 - agg$rej) / agg$n)
# reps where SRP_global dropped the nuisance slope although that slope was not at the boundary (theta_x2 >= 1e-4)
g <- d[d$rule == "SRP_global", ]
g$strip <- g$rung == "r2" & !is.na(g$r1_thx2) & g$r1_thx2 >= 1e-4
st <- aggregate(cbind(strip_nonzero_nuisance = strip, r1_singular = r1_sing, r1_focal_at_zero = r1_thx1 < 1e-4) ~ tau_f + tau_n + r + beta1, g, mean)
ord <- c("rung0", "rung1", "rung2", "SRP_global", "SRP_local", "LRT02_prot", "AIC_prot")
agg$rule <- factor(agg$rule, ord); agg <- agg[order(agg$beta1, agg$r, agg$tau_n, agg$tau_f, agg$rule), ]
num <- sapply(agg, is.numeric); agg[num] <- lapply(agg[num], round, 4)
print(agg, row.names = FALSE)
cat("\nSRP_global: share of data sets in which the non-zero nuisance slope was removed because a protected term was singular\n")
st[, 5:7] <- lapply(st[, 5:7], round, 3); print(st, row.names = FALSE)
# paired differences in rejection (same data sets)
pd <- function(s1, s2) {
  w <- merge(d[d$rule == s1, c(cells, "rep", "rej")], d[d$rule == s2, c(cells, "rep", "rej")], by = c(cells, "rep"))
  w$x <- w$rej.x - w$rej.y
  a <- aggregate(x ~ tau_f + tau_n + r + beta1, w, function(z) c(diff = mean(z), mcse = sd(z) / sqrt(length(z))))
  a <- do.call(data.frame, a); a$cmp <- paste(s1, "-", s2); a }
pp <- rbind(pd("SRP_local", "SRP_global"), pd("LRT02_prot", "SRP_local"), pd("AIC_prot", "SRP_local"), pd("rung1", "SRP_global"))
num <- sapply(pp, is.numeric); pp[num] <- lapply(pp[num], round, 4)
cat("\nPaired differences in rejection rate\n"); print(pp[order(pp$cmp, pp$beta1, pp$r, pp$tau_f), ], row.names = FALSE)
write.csv(agg, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify/out/v2_summary.csv", row.names = FALSE)
write.csv(st, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify/out/v2_strip_rates.csv", row.names = FALSE)
write.csv(pp, "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify/out/v2_paired.csv", row.names = FALSE)
