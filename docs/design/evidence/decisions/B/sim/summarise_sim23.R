# Summaries for Sim 2 (cross-level interaction) and Sim 3 (nuisance-slope ordering).
dir <- "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim/out"
rate <- function(p) c(rate = mean(p < 0.05, na.rm = TRUE), nrep = sum(!is.na(p)), n_na = sum(is.na(p)))
f2 <- list.files(dir, "^sim2_J.*\\.csv$", full.names = TRUE)
if (length(f2)) {
  d2 <- do.call(rbind, lapply(f2, read.csv))
  a2 <- do.call(data.frame, aggregate(p ~ J + n + tau1 + b3 + strategy, d2, rate, na.action = na.pass))
  names(a2) <- sub("^p\\.", "", names(a2)); a2$mcse <- sqrt(a2$rate * (1 - a2$rate) / a2$nrep)
  rs <- aggregate(cbind(rs_singular = rs_sing, rs_nonconv = !rs_conv) ~ J + tau1 + b3, unique(d2[, c("J", "tau1", "b3", "rep", "rs_sing", "rs_conv")]), mean)
  rung <- as.data.frame.matrix(xtabs(~ interaction(J, tau1, b3, strategy, sep = "|") + rung, d2))
  rung$key <- rownames(rung)
  a2$key <- paste(a2$J, a2$tau1, a2$b3, a2$strategy, sep = "|")
  a2 <- merge(merge(a2, rung, by = "key"), rs, by = c("J", "tau1", "b3")); a2$key <- NULL
  a2 <- a2[order(a2$b3, a2$J, a2$tau1, match(a2$strategy, c("rs_always", "backoff_sing_or_conv", "lrt02", "aic", "ri_only"))), ]
  num <- sapply(a2, is.numeric); a2[num] <- lapply(a2[num], function(x) round(x, 3))
  cat("Sim 2: cross-level interaction x:z (rate = rejection at .05)\n"); print(a2, row.names = FALSE)
  write.csv(a2, file.path(dir, "sim2_summary.csv"), row.names = FALSE)
}
f3 <- list.files(dir, "^sim3_S.*\\.csv$", full.names = TRUE)
if (length(f3)) {
  d3 <- do.call(rbind, lapply(f3, read.csv))
  a3 <- do.call(data.frame, aggregate(p ~ S + m + tau + r + beta1 + model, d3, rate, na.action = na.pass))
  names(a3) <- sub("^p\\.", "", names(a3)); a3$mcse <- sqrt(a3$rate * (1 - a3$rate) / a3$nrep)
  se <- aggregate(cbind(mean_se = se, singular = sing) ~ S + m + tau + r + beta1 + model, d3, mean)
  a3 <- merge(a3, se, by = c("S", "m", "tau", "r", "beta1", "model"))
  a3 <- a3[order(a3$beta1, a3$r, match(a3$model, c("full", "drop_nuis", "drop_focal", "ri"))), ]
  num <- sapply(a3, is.numeric); a3[num] <- lapply(a3[num], function(x) round(x, 4))
  cat("\nSim 3: focal x1 test when dropping nuisance (x2) vs focal (x1) slopes\n"); print(a3, row.names = FALSE)
  write.csv(a3, file.path(dir, "sim3_summary.csv"), row.names = FALSE)
}
