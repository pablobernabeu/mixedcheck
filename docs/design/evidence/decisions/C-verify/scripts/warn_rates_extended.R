# C-verify: reproduce and extend C's warning-rate study (C-E02).
# Questions:
#  (1) Does C's 30-replicate result reproduce with the same seeds (1001-1030)?
#  (2) With 100 replicates, what are the rates and their Wilson 95% intervals?
#  (3) Is the Bernoulli excess a property of the model class or of the information in
#      the data? Test: (a) Gaussian LMM with residual SD = pi/sqrt(3) (the latent
#      logistic residual SD) and the same random-effect SDs; (b) Bernoulli GLMM with
#      all random-effect SDs doubled.
# Engines as installed: lme4 1.1-35.1, glmmTMB 1.1.8 (older than current CRAN).
# Usage: Rscript warn_rates_extended.R <out_dir> [n_rep]
suppressPackageStartupMessages({ library(lme4); library(glmmTMB) })
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args)) args[1] else "."
n_rep <- if (length(args) > 1) as.integer(args[2]) else 100L
S <- function(sd1, sd2, r) { m <- diag(c(sd1, sd2)); m %*% matrix(c(1, r, r, 1), 2) %*% m }
gen <- function(seed) {
  # identical to C's gen() for the first draws, so y_gauss and y_bin reproduce C exactly
  set.seed(seed)
  n_s <- 40; n_i <- 40
  d <- expand.grid(subj = factor(seq_len(n_s)), item = factor(seq_len(n_i)))
  d$cond <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  us <- MASS::mvrnorm(n_s, c(0, 0), S(0.6, 0.3, 0.3))
  ui <- MASS::mvrnorm(n_i, c(0, 0), S(0.4, 0.2, -0.2))
  eta <- with(d, us[subj, 1] + ui[item, 1] + (0.3 + us[subj, 2] + ui[item, 2]) * cond)
  d$y_gauss <- 1 + eta + rnorm(nrow(d))
  d$y_bin   <- rbinom(nrow(d), 1, plogis(0.5 + eta))
  d$y_pois  <- rpois(nrow(d), exp(0.7 + eta))
  # extra outcomes drawn AFTER C's draws (C drew y_nb, y_beta, zi, y_zip next; we skip
  # those, so the extra outcomes below use a fresh stream and do not affect C's columns)
  set.seed(seed + 500000)
  d$y_gauss_latent <- 1 + eta + rnorm(nrow(d), 0, pi / sqrt(3))
  eta2 <- with(d, 2 * us[subj, 1] + 2 * ui[item, 1] + (0.3 + 2 * us[subj, 2] + 2 * ui[item, 2]) * cond)
  d$y_bin_sd2 <- rbinom(nrow(d), 1, plogis(0.5 + eta2))
  d
}
f <- ~ cond + (1 + cond | subj) + (1 + cond | item)
mods <- list(
  gauss_lmer        = function(d) lmer(update(f, y_gauss ~ .), data = d),
  gauss_lmer_latent = function(d) lmer(update(f, y_gauss_latent ~ .), data = d),
  bern_glmer        = function(d) glmer(update(f, y_bin ~ .), data = d, family = binomial),
  bern_tmb          = function(d) glmmTMB(update(f, y_bin ~ .), data = d, family = binomial),
  bern_glmer_sd2    = function(d) glmer(update(f, y_bin_sd2 ~ .), data = d, family = binomial),
  pois_glmer        = function(d) glmer(update(f, y_pois ~ .), data = d, family = poisson)
)
rows <- list()
for (r in seq_len(n_rep)) {
  d <- gen(1000 + r)
  for (nm in names(mods)) {
    msgs <- character(0)
    t0 <- proc.time()[["elapsed"]]
    fit <- withCallingHandlers(tryCatch(mods[[nm]](d), error = function(e) e),
      warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    el <- proc.time()[["elapsed"]] - t0
    err <- inherits(fit, "error")
    sing <- if (!err && inherits(fit, "merMod")) isSingular(fit) else NA
    pdh <- if (!err && inherits(fit, "glmmTMB")) isTRUE(fit$sdr$pdHess) else NA
    rows[[length(rows) + 1]] <- data.frame(rep = r, model = nm, error = err,
      any_msg = length(msgs) > 0, singular_msg = any(grepl("singular", msgs, ignore.case = TRUE)),
      grad_msg = any(grepl("max\\|grad\\||failed to converge", msgs, ignore.case = TRUE)),
      singular_lme4 = sing, tmb_pdHess = pdh, fit_sec = el,
      msg = substr(paste(unique(msgs), collapse = " | "), 1, 140))
  }
  if (r %% 10 == 0) cat("rep", r, "done\n")
}
tab <- do.call(rbind, rows)
write.csv(tab, file.path(out_dir, "warn_ext_raw.csv"), row.names = FALSE)
wilson <- function(x, n, z = 1.959964) {
  p <- x / n; den <- 1 + z^2 / n
  c((p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / den,
    (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / den)
}
agg <- do.call(rbind, lapply(names(mods), function(nm) {
  x <- tab[tab$model == nm, ]
  x30 <- x[x$rep <= 30, ]
  ci <- wilson(sum(x$any_msg), nrow(x))
  data.frame(model = nm,
    any_msg_first30 = sum(x30$any_msg), n_first30 = nrow(x30),
    any_msg = sum(x$any_msg), n = nrow(x),
    rate = round(mean(x$any_msg), 3), wilson_lo = round(ci[1], 3), wilson_hi = round(ci[2], 3),
    singular_lme4 = sum(x$singular_lme4, na.rm = TRUE),
    grad_msg = sum(x$grad_msg), tmb_not_pdHess = sum(x$tmb_pdHess == FALSE, na.rm = TRUE),
    median_fit_sec = round(median(x$fit_sec), 3))
}))
print(agg, row.names = FALSE)
write.csv(agg, file.path(out_dir, "warn_ext_summary.csv"), row.names = FALSE)
cat(R.version.string, " lme4", as.character(packageVersion("lme4")),
    " glmmTMB", as.character(packageVersion("glmmTMB")), "\n")
