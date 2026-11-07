# Fit per-(design family, engine) power laws log(t) = a + b log(n) to the measured fit times.
args <- commandArgs(trailingOnly = TRUE); tdir <- args[1]; odir <- args[2]
a <- read.csv(file.path(tdir, "timing_raw.csv")); b <- read.csv(file.path(tdir, "timing_raw2.csv"))
a$task[a$task == "fit"] <- "fit"; b$task[b$task == "fit_max"] <- "fit"
keep <- c("design", "size", "n_obs", "task", "engine_family", "elapsed")
d <- rbind(a[, keep], b[, keep])
d <- d[d$task %in% c("fit", "fit_zcp", "fit_ar1"), ]
d$model <- paste(d$design, d$task, d$engine_family, sep = "|")
med <- aggregate(elapsed ~ model + design + task + engine_family + size + n_obs, data = d, FUN = median)
fits <- do.call(rbind, lapply(split(med, med$model), function(s) {
  if (length(unique(s$n_obs)) >= 3) {
    m <- lm(log(elapsed) ~ log(n_obs), data = s)
    data.frame(model = s$model[1], k = nrow(s), a = coef(m)[1], b = coef(m)[2],
               r2 = summary(m)$r.squared, n_min = min(s$n_obs), n_max = max(s$n_obs),
               t_min = min(s$elapsed), t_max = max(s$elapsed))
  } else data.frame(model = s$model[1], k = nrow(s), a = NA, b = NA, r2 = NA,
                    n_min = min(s$n_obs), n_max = max(s$n_obs), t_min = min(s$elapsed), t_max = max(s$elapsed))
}))
rownames(fits) <- NULL
write.csv(med, file.path(odir, "timing_medians.csv"), row.names = FALSE)
write.csv(fits, file.path(odir, "cost_model_powerlaw.csv"), row.names = FALSE)
print(fits, digits = 3)
