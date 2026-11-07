# Per-model-class cost of fitting and of simulation-based diagnostics.
# Key C (Q2). Engines: lme4 1.1-35.1, glmmTMB 1.1.8, nlme 3.1-164 (as installed).
# Usage: Rscript class_cost.R <out_dir>
suppressPackageStartupMessages({
  library(lme4); library(glmmTMB); library(nlme)
})
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args)) args[1] else "."
set.seed(20261107)
options(warn = 1)

## ---- crossed design: 40 subjects x 40 items, Latin-square condition -------
n_s <- 40; n_i <- 40
d <- expand.grid(subj = factor(seq_len(n_s)), item = factor(seq_len(n_i)))
d$cond <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
S <- function(sd1, sd2, r) { m <- diag(c(sd1, sd2)); m %*% matrix(c(1, r, r, 1), 2) %*% m }
us <- MASS::mvrnorm(n_s, c(0, 0), S(0.6, 0.3, 0.3))
ui <- MASS::mvrnorm(n_i, c(0, 0), S(0.4, 0.2, -0.2))
eta <- with(d, us[subj, 1] + ui[item, 1] + (0.3 + us[subj, 2] + ui[item, 2]) * cond)
d$y_gauss <- 1 + eta + rnorm(nrow(d), 0, 1)
d$y_bin   <- rbinom(nrow(d), 1, plogis(0.5 + eta))
d$y_pois  <- rpois(nrow(d), exp(0.7 + eta))
d$y_nb    <- rnbinom(nrow(d), mu = exp(0.7 + eta), size = 2)
mu_b <- plogis(eta); phi <- 10
d$y_beta  <- rbeta(nrow(d), mu_b * phi, (1 - mu_b) * phi)
zi <- rbinom(nrow(d), 1, 0.25)
d$y_zip   <- ifelse(zi == 1, 0L, rpois(nrow(d), exp(0.7 + eta)))

## ---- longitudinal design: 100 persons x 8 occasions, AR(1) errors --------
n_p <- 100; n_t <- 8
L <- expand.grid(time = seq_len(n_t) - 1, id = factor(seq_len(n_p)))
L$times <- factor(L$time)
ar <- unlist(lapply(seq_len(n_p), function(i) as.numeric(arima.sim(list(ar = 0.6), n_t, sd = 0.8))))
L$y <- 2 + 0.25 * L$time + rnorm(n_p, 0, 1)[as.integer(L$id)] + ar

f_cross <- ~ cond + (1 + cond | subj) + (1 + cond | item)
fits <- list(
  gauss_lmer   = function(dd) lmer(update(f_cross, y_gauss ~ .), data = dd, REML = TRUE),
  gauss_tmb    = function(dd) glmmTMB(update(f_cross, y_gauss ~ .), data = dd, REML = TRUE),
  bern_glmer   = function(dd) glmer(update(f_cross, y_bin ~ .), data = dd, family = binomial),
  bern_tmb     = function(dd) glmmTMB(update(f_cross, y_bin ~ .), data = dd, family = binomial),
  pois_glmer   = function(dd) glmer(update(f_cross, y_pois ~ .), data = dd, family = poisson),
  nb2_tmb      = function(dd) glmmTMB(update(f_cross, y_nb ~ .), data = dd, family = nbinom2),
  beta_tmb     = function(dd) glmmTMB(update(f_cross, y_beta ~ .), data = dd, family = beta_family()),
  zip_tmb      = function(dd) glmmTMB(update(f_cross, y_zip ~ .), data = dd, family = poisson, ziformula = ~ 1),
  ar1_nlme     = function(dd) lme(y ~ time, random = ~ 1 | id, data = L, correlation = corAR1(form = ~ time | id), method = "REML"),
  ar1_tmb      = function(dd) glmmTMB(y ~ time + (1 | id) + ar1(times + 0 | id), data = L, REML = TRUE)
)

time_it <- function(expr_fun, reps = 3) {
  ts <- numeric(reps); val <- NULL; msgs <- character(0)
  for (r in seq_len(reps)) {
    t0 <- proc.time()[["elapsed"]]
    val <- withCallingHandlers(expr_fun(),
      warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    ts[r] <- proc.time()[["elapsed"]] - t0
  }
  list(time = median(ts), value = val, msgs = unique(msgs))
}

res <- list()
for (nm in names(fits)) {
  ft <- time_it(function() fits[[nm]](d))
  fit <- ft$value
  sim_t <- NA_real_; sim_msg <- ""
  st <- tryCatch(time_it(function() simulate(fit, nsim = 250, seed = 1), reps = 1),
                 error = function(e) { sim_msg <<- conditionMessage(e); NULL })
  if (!is.null(st)) sim_t <- st$time
  sing <- tryCatch({
    if (inherits(fit, "merMod")) isSingular(fit) else NA
  }, error = function(e) NA)
  res[[nm]] <- data.frame(model = nm, fit_sec = round(ft$time, 3),
                          sim250_sec = round(sim_t, 3),
                          singular_lme4 = sing,
                          n_warn_or_msg = length(ft$msgs),
                          first_msg = substr(paste(ft$msgs, collapse = " | "), 1, 160),
                          sim_error = substr(sim_msg, 1, 120))
  cat(sprintf("%-11s fit %6.2fs  sim250 %6.2fs  singular=%s  msgs=%d %s\n", nm, ft$time, sim_t,
              sing, length(ft$msgs), substr(paste(ft$msgs, collapse = " | "), 1, 100)))
}
tab <- do.call(rbind, res)

## Projected CPU-hours for one validation grid per class (inference, not a measurement):
## 24 design cells x 1000 replicates; per replicate either
##  (a) one fit + one 250-draw simulation (simulation-based residual checks), or
##  (b) one fit + 200 parametric-bootstrap refits (bootstrap-calibrated checks).
cells <- 24; reps <- 1000
tab$cpu_h_grid_simresid <- round(cells * reps * (tab$fit_sec + tab$sim250_sec) / 3600, 1)
tab$cpu_h_grid_boot200  <- round(cells * reps * (tab$fit_sec * 201) / 3600, 1)
print(tab[, c("model", "fit_sec", "sim250_sec", "cpu_h_grid_simresid", "cpu_h_grid_boot200", "singular_lme4", "n_warn_or_msg")], row.names = FALSE)
write.csv(tab, file.path(out_dir, "class_cost.csv"), row.names = FALSE)
cat("nrow crossed", nrow(d), " nrow longitudinal", nrow(L), "\n")
sessionInfo()
