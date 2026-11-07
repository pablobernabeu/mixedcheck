# Summarise Sim 1 output files: rejection rate (alpha = .05) with Monte Carlo SE, rung distribution,
# singular / nonconvergence rates of the maximal model.
a <- commandArgs(trailingOnly = TRUE)
pattern <- if (length(a)) a[1] else "^sim1_S.*\\.csv$"
dir <- if (length(a) > 1) a[2] else "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim/out"
fs <- list.files(dir, pattern = pattern, full.names = TRUE)
d <- do.call(rbind, lapply(fs, read.csv, stringsAsFactors = FALSE))
d$rej <- as.integer(d$p < 0.05)
key <- c("S", "I", "tau1", "beta", "strategy")
agg <- aggregate(rej ~ S + I + tau1 + beta + strategy, data = d, FUN = function(x) c(rate = mean(x), n = length(x)))
agg <- do.call(data.frame, agg)
names(agg)[names(agg) == "rej.rate"] <- "reject_rate"; names(agg)[names(agg) == "rej.n"] <- "n"
agg$mcse <- sqrt(agg$reject_rate * (1 - agg$reject_rate) / agg$n)
# NA p-values (failed fits) counted separately
nas <- aggregate(is.na(p) ~ S + I + tau1 + beta + strategy, data = transform(d, p = p), FUN = sum, na.action = na.pass)
names(nas)[6] <- "n_na"
agg <- merge(agg, nas, by = key)
# rung distribution
tab <- as.data.frame.matrix(xtabs(~ interaction(S, I, tau1, beta, strategy, sep = "|") + rung, data = d))
tab$cell <- rownames(tab)
rd <- do.call(rbind, strsplit(tab$cell, "|", fixed = TRUE))
tab <- data.frame(S = as.integer(rd[, 1]), I = as.integer(rd[, 2]), tau1 = as.numeric(rd[, 3]), beta = as.numeric(rd[, 4]),
                  strategy = rd[, 5], tab[, setdiff(names(tab), "cell")], check.names = FALSE)
out <- merge(agg, tab, by = key)
# maximal-model singular and nonconvergence rates per condition
mx <- unique(d[, c("S", "I", "tau1", "beta", "rep", "max_sing", "max_conv")])
mxr <- aggregate(cbind(max_singular = max_sing, max_nonconv = !max_conv) ~ S + I + tau1 + beta, data = mx, FUN = mean)
out <- merge(out, mxr, by = c("S", "I", "tau1", "beta"))
ord <- c("maximal", "backoff_conv_only", "backoff_protected", "backoff_sing_or_conv", "lrt02_design", "lrt02_data", "lrt05_data", "aic_data", "ri_only")
out$strategy <- factor(out$strategy, levels = ord)
out <- out[order(out$S, out$beta, out$tau1, out$strategy), ]
out$reject_rate <- round(out$reject_rate, 3); out$mcse <- round(out$mcse, 3)
out$max_singular <- round(out$max_singular, 3); out$max_nonconv <- round(out$max_nonconv, 3)
print(out, row.names = FALSE)
write.csv(out, file.path(dir, "sim1_summary.csv"), row.names = FALSE)
