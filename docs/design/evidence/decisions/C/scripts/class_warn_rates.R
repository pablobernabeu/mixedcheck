# Warning, singularity and NA-SE rates per model class under a correctly specified model.
# Key C (Q2). Same generating design as class_cost.R, 30 replicate datasets.
# Usage: Rscript class_warn_rates.R <out_dir> [n_rep]
suppressPackageStartupMessages({ library(lme4); library(glmmTMB) })
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args)) args[1] else "."
n_rep <- if (length(args) > 1) as.integer(args[2]) else 30L
S <- function(sd1, sd2, r) { m <- diag(c(sd1, sd2)); m %*% matrix(c(1, r, r, 1), 2) %*% m }
gen <- function(seed) {
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
  d$y_nb    <- rnbinom(nrow(d), mu = exp(0.7 + eta), size = 2)
  mu_b <- plogis(eta); d$y_beta <- rbeta(nrow(d), mu_b * 10, (1 - mu_b) * 10)
  zi <- rbinom(nrow(d), 1, 0.25); d$y_zip <- ifelse(zi == 1, 0L, rpois(nrow(d), exp(0.7 + eta)))
  d
}
f <- ~ cond + (1 + cond | subj) + (1 + cond | item)
mods <- list(
  gauss_lmer = function(d) lmer(update(f, y_gauss ~ .), data = d),
  gauss_tmb  = function(d) glmmTMB(update(f, y_gauss ~ .), data = d, REML = TRUE),
  bern_glmer = function(d) glmer(update(f, y_bin ~ .), data = d, family = binomial),
  bern_tmb   = function(d) glmmTMB(update(f, y_bin ~ .), data = d, family = binomial),
  pois_glmer = function(d) glmer(update(f, y_pois ~ .), data = d, family = poisson),
  nb2_tmb    = function(d) glmmTMB(update(f, y_nb ~ .), data = d, family = nbinom2),
  beta_tmb   = function(d) glmmTMB(update(f, y_beta ~ .), data = d, family = beta_family()),
  zip_tmb    = function(d) glmmTMB(update(f, y_zip ~ .), data = d, family = poisson, ziformula = ~ 1)
)
rows <- list()
for (r in seq_len(n_rep)) {
  d <- gen(1000 + r)
  for (nm in names(mods)) {
    msgs <- character(0)
    fit <- withCallingHandlers(tryCatch(mods[[nm]](d), error = function(e) e),
      warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    err <- inherits(fit, "error")
    sing <- if (!err && inherits(fit, "merMod")) isSingular(fit) else NA
    na_se <- if (!err && inherits(fit, "glmmTMB")) any(!is.finite(sqrt(diag(vcov(fit)$cond)))) else NA
    pdh <- if (!err && inherits(fit, "glmmTMB")) isTRUE(fit$sdr$pdHess) else NA
    conv_msg <- any(grepl("converge|Hessian|singular", msgs, ignore.case = TRUE))
    rows[[length(rows) + 1]] <- data.frame(rep = r, model = nm, error = err,
      any_msg = length(msgs) > 0, conv_or_sing_msg = conv_msg, singular_lme4 = sing,
      tmb_pdHess = pdh, tmb_na_se = na_se, msg = substr(paste(unique(msgs), collapse = " | "), 1, 140))
  }
}
tab <- do.call(rbind, rows)
write.csv(tab, file.path(out_dir, "class_warn_rates_raw.csv"), row.names = FALSE)
agg <- do.call(rbind, lapply(split(tab, tab$model), function(x) data.frame(
  model = x$model[1], n = nrow(x), error = sum(x$error),
  any_msg = sum(x$any_msg), conv_or_sing_msg = sum(x$conv_or_sing_msg),
  singular_lme4 = sum(x$singular_lme4, na.rm = TRUE),
  tmb_not_pdHess = sum(x$tmb_pdHess == FALSE, na.rm = TRUE),
  tmb_na_se = sum(x$tmb_na_se, na.rm = TRUE))))
agg <- agg[match(names(mods), agg$model), ]
print(agg, row.names = FALSE)
write.csv(agg, file.path(out_dir, "class_warn_rates.csv"), row.names = FALSE)
