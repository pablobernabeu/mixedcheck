# Key F, task 3: time a representative grid of lme4 and glmmTMB fits (and the
# per-replicate costs of typical check components) to budget the HPC validation study.
# Engines as installed: lme4 1.1-35.1, glmmTMB 1.1.8, lmerTest 3.1-3, pbkrtest 0.5.2
# (older than current CRAN; timings are indicative, see README notes in the report).
# Usage: Rscript time_grid.R <out_dir> [budget_seconds]
suppressPackageStartupMessages({
  library(lme4); library(glmmTMB); library(lmerTest); library(pbkrtest)
})
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "."
budget  <- if (length(args) >= 2) as.numeric(args[2]) else 780   # hard guard, seconds
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
set.seed(20261107)
t_start <- proc.time()[["elapsed"]]
elapsed <- function() proc.time()[["elapsed"]] - t_start

## ---------------- data generators ----------------------------------------
gen_nested <- function(J, m, cv = 0, icc = 0.2, slope_sd = 0.3) {
  if (cv > 0) {
    sz <- pmax(2L, round(m * rgamma(J, shape = 1 / cv^2, rate = 1 / cv^2)))
  } else sz <- rep(as.integer(m), J)
  g <- factor(rep(seq_len(J), sz))
  n <- length(g)
  z <- rep(rep(c(-0.5, 0.5), length.out = J), sz)            # cluster-level treatment
  xb <- rnorm(J, 0, 0.5)[as.integer(g)]                       # between part of x
  x <- xb + rnorm(n)                                           # level-1 predictor
  tau0 <- sqrt(icc / (1 - icc))                                # residual SD = 1
  u0 <- rnorm(J, 0, tau0)[as.integer(g)]
  u1 <- rnorm(J, 0, slope_sd)[as.integer(g)]
  eta <- 0.2 * x + 0.3 * z + 0.1 * x * z + u0 + u1 * x
  data.frame(g, x, z, y = eta + rnorm(n), yb = rbinom(n, 1, plogis(eta)))
}
gen_crossed <- function(S, I, slope_sd = 0.3) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  us <- cbind(rnorm(S, 0, 0.5), rnorm(S, 0, slope_sd))
  ui <- cbind(rnorm(I, 0, 0.4), rnorm(I, 0, slope_sd))
  s <- as.integer(d$subj); i <- as.integer(d$item)
  eta <- 0.2 * d$A + us[s, 1] + us[s, 2] * d$A + ui[i, 1] + ui[i, 2] * d$A
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta))
  d
}

## ---------------- timing helper --------------------------------------------
quiet_time <- function(expr_fun) {
  msgs <- character(0)
  invisible(gc(reset = TRUE, full = TRUE))
  t0 <- proc.time()
  val <- tryCatch(withCallingHandlers(expr_fun(),
      warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }),
    error = function(e) { msgs <<- c(msgs, paste("ERROR:", conditionMessage(e))); NULL })
  tt <- proc.time() - t0
  gg <- gc()
  list(elapsed = tt[["elapsed"]], cpu = tt[["user.self"]] + tt[["sys.self"]],
       maxmem_mb = sum(gg[, ncol(gg)]),   # 'max used' (Mb) Ncells + Vcells since reset
       value = val, msgs = unique(msgs))
}

rows <- list()
add_row <- function(...) rows[[length(rows) + 1]] <<- data.frame(..., stringsAsFactors = FALSE)
flag_sing <- function(f) {
  if (is.null(f)) return(NA)
  if (inherits(f, "merMod")) return(isSingular(f))
  if (inherits(f, "glmmTMB")) return(!isTRUE(f$sdr$pdHess))
  NA
}

fitters_nested <- list(
  lmer_gauss    = function(d) lmer(y ~ x * z + (1 + x | g), data = d, REML = TRUE),
  glmer_bern    = function(d) glmer(yb ~ x * z + (1 + x | g), data = d, family = binomial),
  tmb_gauss     = function(d) glmmTMB(y ~ x * z + (1 + x | g), data = d, REML = TRUE),
  tmb_bern      = function(d) glmmTMB(yb ~ x * z + (1 + x | g), data = d, family = binomial)
)
fitters_crossed <- list(
  lmer_gauss    = function(d) lmer(y ~ A + (1 + A | subj) + (1 + A | item), data = d, REML = TRUE),
  glmer_bern    = function(d) glmer(yb ~ A + (1 + A | subj) + (1 + A | item), data = d, family = binomial),
  tmb_gauss     = function(d) glmmTMB(y ~ A + (1 + A | subj) + (1 + A | item), data = d, REML = TRUE),
  tmb_bern      = function(d) glmmTMB(yb ~ A + (1 + A | subj) + (1 + A | item), data = d, family = binomial)
)

run_cfg <- function(design, size_label, n_groups, gen, fitters, reps, extra = list()) {
  for (r in seq_len(reps)) {
    d <- gen()
    for (nm in names(fitters)) {
      if (elapsed() > budget) return(invisible(FALSE))
      res <- quiet_time(function() fitters[[nm]](d))
      add_row(design = design, size = size_label, n_obs = nrow(d), n_groups = n_groups,
              task = "fit", engine_family = nm, rep = r, elapsed = res$elapsed, cpu = res$cpu,
              maxmem_mb = res$maxmem_mb, singular_or_nonpd = flag_sing(res$value),
              n_msgs = length(res$msgs), first_msg = substr(paste(res$msgs, collapse = " | "), 1, 160))
      # check-component costs on the first replicate of selected sizes
      if (r == 1 && length(extra) && !is.null(res$value)) {
        for (en in names(extra)) {
          if (!startsWith(en, paste0(nm, "::"))) next
          if (elapsed() > budget) return(invisible(FALSE))
          fit <- res$value
          rx <- quiet_time(function() extra[[en]](fit, d))
          add_row(design = design, size = size_label, n_obs = nrow(d), n_groups = n_groups,
                  task = sub("^[^:]+::", "", en), engine_family = nm, rep = r,
                  elapsed = rx$elapsed, cpu = rx$cpu, maxmem_mb = rx$maxmem_mb,
                  singular_or_nonpd = NA, n_msgs = length(rx$msgs),
                  first_msg = substr(paste(rx$msgs, collapse = " | "), 1, 160))
        }
      }
    }
  }
  invisible(TRUE)
}

extras <- list(
  "lmer_gauss::refitML"          = function(f, d) refitML(f),
  "lmer_gauss::satterthwaite"    = function(f, d) summary(as_lmerModLmerTest(f), ddf = "Satterthwaite")$coefficients,
  "lmer_gauss::kenward_roger"    = function(f, d) summary(as_lmerModLmerTest(f), ddf = "Kenward-Roger")$coefficients,
  "lmer_gauss::simulate250"      = function(f, d) simulate(f, nsim = 250),
  "lmer_gauss::allFit"           = function(f, d) summary(allFit(f, verbose = FALSE))$llik,
  "glmer_bern::simulate250"      = function(f, d) simulate(f, nsim = 250),
  "glmer_bern::nAGQ10_ri"        = function(f, d) glmer(yb ~ x * z + (1 | g), data = d, family = binomial, nAGQ = 10),
  "glmer_bern::laplace_ri"       = function(f, d) glmer(yb ~ x * z + (1 | g), data = d, family = binomial),
  "tmb_gauss::simulate250"       = function(f, d) simulate(f, nsim = 250),
  "tmb_bern::simulate250"        = function(f, d) simulate(f, nsim = 250)
)
extras_crossed <- extras[!grepl("AGQ|laplace_ri", names(extras))]

## ---------------- the grid ----------------------------------------------------
# Nested two-level (pupils in classes): J x m, balanced and imbalanced (CV .5)
nested_grid <- expand.grid(J = c(10, 30, 100), m = c(5, 20, 50), cv = c(0, 0.5))
nested_grid <- nested_grid[order(nested_grid$J * nested_grid$m), ]
for (k in seq_len(nrow(nested_grid))) {
  J <- nested_grid$J[k]; m <- nested_grid$m[k]; cv <- nested_grid$cv[k]
  lab <- sprintf("J%d_m%d_cv%.1f", J, m, cv)
  ex <- if (cv == 0 && ((J == 30 && m == 20) || (J == 10 && m == 5) || (J == 100 && m == 50))) extras else list()
  if (J == 100 && m == 50) ex <- ex[!grepl("kenward_roger|allFit", names(ex))]   # KR is O(n^3) memory/time here
  ok <- run_cfg("nested", lab, J, function() gen_nested(J, m, cv), fitters_nested,
                reps = if (J * m >= 5000) 2 else 3, extra = ex)
  cat(sprintf("[%6.1fs] nested %s done\n", elapsed(), lab)); flush.console()
  if (!ok) break
}
# Crossed subjects x items, maximal model
crossed_grid <- data.frame(S = c(24, 48, 96), I = c(16, 32, 64))
for (k in seq_len(nrow(crossed_grid))) {
  if (elapsed() > budget) break
  S <- crossed_grid$S[k]; I <- crossed_grid$I[k]
  lab <- sprintf("S%d_I%d", S, I)
  ex <- if (S <= 48) extras_crossed else list()
  if (S == 48) ex <- ex[!grepl("kenward_roger|allFit", names(ex))]
  ok <- run_cfg("crossed", lab, S + I, function() gen_crossed(S, I), fitters_crossed,
                reps = if (S >= 96) 1 else 2, extra = ex)
  cat(sprintf("[%6.1fs] crossed %s done\n", elapsed(), lab)); flush.console()
  if (!ok) break
}

out <- do.call(rbind, rows)
write.csv(out, file.path(out_dir, "timing_raw.csv"), row.names = FALSE)
cat(sprintf("Total elapsed %.1f s; rows %d\n", elapsed(), nrow(out)))
writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
