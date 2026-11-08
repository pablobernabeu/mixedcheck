# Key F, task 3 (second batch): harder but typical designs, extra families, and
# per-core throughput when 4 fits run concurrently (as on a packed HTC node).
# Usage: Rscript time_grid2.R <out_dir> [budget_seconds]
suppressPackageStartupMessages({ library(lme4); library(glmmTMB); library(parallel) })
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "."
budget  <- if (length(args) >= 2) as.numeric(args[2]) else 540
set.seed(20261108)
t_start <- proc.time()[["elapsed"]]; elapsed <- function() proc.time()[["elapsed"]] - t_start

quiet_time <- function(expr_fun) {
  msgs <- character(0); t0 <- proc.time()
  val <- tryCatch(withCallingHandlers(expr_fun(),
      warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }),
    error = function(e) { msgs <<- c(msgs, paste("ERROR:", conditionMessage(e))); NULL })
  tt <- proc.time() - t0
  list(elapsed = tt[["elapsed"]], value = val, msgs = unique(msgs))
}
flag_sing <- function(f) {
  if (is.null(f)) return(NA)
  if (inherits(f, "merMod")) return(isSingular(f))
  if (inherits(f, "glmmTMB")) return(!isTRUE(f$sdr$pdHess))
  NA
}
rows <- list()
rec <- function(design, size, n, task, eng, rep, res)
  rows[[length(rows) + 1]] <<- data.frame(design = design, size = size, n_obs = n, task = task,
    engine_family = eng, rep = rep, elapsed = res$elapsed, singular_or_nonpd = flag_sing(res$value),
    n_msgs = length(res$msgs), first_msg = substr(paste(res$msgs, collapse = " | "), 1, 160))

## 1. Crossed 2x2 within-subject and within-item design, maximal 4x4 covariances
gen_2x2 <- function(S, I) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  cell <- (as.integer(d$subj) + as.integer(d$item)) %% 4          # Latin square over 4 cells
  d$A <- ifelse(cell %in% c(0, 1), -0.5, 0.5); d$B <- ifelse(cell %in% c(0, 2), -0.5, 0.5)
  mk <- function(n, sds) { R <- matrix(0.3, 4, 4); diag(R) <- 1; MASS::mvrnorm(n, rep(0, 4), diag(sds) %*% R %*% diag(sds)) }
  us <- mk(S, c(0.5, 0.2, 0.2, 0.1)); ui <- mk(I, c(0.4, 0.2, 0.2, 0.1))
  s <- as.integer(d$subj); i <- as.integer(d$item)
  X <- cbind(1, d$A, d$B, d$A * d$B)
  eta <- drop(X %*% c(0, 0.2, 0.1, 0.05)) + rowSums(X * us[s, ]) + rowSums(X * ui[i, ])
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta)); d
}
f2 <- ~ A * B + (1 + A * B | subj) + (1 + A * B | item)
f2zcp <- ~ A * B + (1 + A * B || subj) + (1 + A * B || item)
for (sz in list(c(24, 16), c(48, 32))) {
  for (r in 1:2) {
    if (elapsed() > budget) break
    d <- gen_2x2(sz[1], sz[2]); lab <- sprintf("S%d_I%d", sz[1], sz[2])
    rec("crossed2x2", lab, nrow(d), "fit_max", "lmer_gauss", r, quiet_time(function() lmer(update(f2, y ~ .), d)))
    rec("crossed2x2", lab, nrow(d), "fit_zcp", "lmer_gauss", r, quiet_time(function() lmer(update(f2zcp, y ~ .), d)))
    rec("crossed2x2", lab, nrow(d), "fit_max", "tmb_gauss", r, quiet_time(function() glmmTMB(update(f2, y ~ .), d, REML = TRUE)))
    if (r == 1) {
      rec("crossed2x2", lab, nrow(d), "fit_max", "glmer_bern", r, quiet_time(function() glmer(update(f2, yb ~ .), d, family = binomial)))
      rec("crossed2x2", lab, nrow(d), "fit_max", "tmb_bern", r, quiet_time(function() glmmTMB(update(f2, yb ~ .), d, family = binomial)))
    }
    cat(sprintf("[%6.1fs] crossed2x2 %s rep %d\n", elapsed(), lab, r)); flush.console()
  }
}

## 2. Three-level nested: pupils in classes in schools, class-level random slope
gen_3l <- function(K, C, m) {
  sch <- rep(seq_len(K), each = C * m); cls <- rep(seq_len(K * C), each = m)
  n <- length(sch); x <- rnorm(n); z <- rep(rep(c(-0.5, 0.5), length.out = K * C), each = m)
  eta <- 0.2 * x + 0.3 * z + rnorm(K, 0, 0.3)[sch] + rnorm(K * C, 0, 0.4)[cls] + rnorm(K * C, 0, 0.2)[cls] * x
  data.frame(school = factor(sch), class = factor(cls), x, z, y = eta + rnorm(n), yb = rbinom(n, 1, plogis(eta)))
}
for (sz in list(c(20, 4, 15), c(40, 4, 25))) {
  for (r in 1:2) {
    if (elapsed() > budget) break
    d <- gen_3l(sz[1], sz[2], sz[3]); lab <- sprintf("K%d_C%d_m%d", sz[1], sz[2], sz[3])
    rec("nested3", lab, nrow(d), "fit", "lmer_gauss", r, quiet_time(function() lmer(y ~ x + z + (1 | school) + (1 + x | class), d)))
    rec("nested3", lab, nrow(d), "fit", "tmb_gauss", r, quiet_time(function() glmmTMB(y ~ x + z + (1 | school) + (1 + x | class), d, REML = TRUE)))
    rec("nested3", lab, nrow(d), "fit", "glmer_bern", r, quiet_time(function() glmer(yb ~ x + z + (1 | school) + (1 + x | class), d, family = binomial)))
    rec("nested3", lab, nrow(d), "fit", "tmb_bern", r, quiet_time(function() glmmTMB(yb ~ x + z + (1 | school) + (1 + x | class), d, family = binomial)))
    cat(sprintf("[%6.1fs] nested3 %s rep %d\n", elapsed(), lab, r)); flush.console()
  }
}

## 3. Growth model: persons x waves, (1 + time | id); AR(1) residual in glmmTMB
gen_long <- function(P, Tn) {
  d <- expand.grid(time = seq_len(Tn) - 1, id = factor(seq_len(P))); d$times <- factor(d$time)
  u <- MASS::mvrnorm(P, c(0, 0), matrix(c(1, 0.1, 0.1, 0.09), 2)); i <- as.integer(d$id)
  ar <- unlist(lapply(seq_len(P), function(k) as.numeric(arima.sim(list(ar = 0.5), Tn, sd = 0.7))))
  d$y <- 2 + 0.25 * d$time + u[i, 1] + u[i, 2] * d$time + ar; d
}
for (sz in list(c(100, 6), c(400, 8))) {
  for (r in 1:2) {
    if (elapsed() > budget) break
    d <- gen_long(sz[1], sz[2]); lab <- sprintf("P%d_T%d", sz[1], sz[2])
    rec("growth", lab, nrow(d), "fit", "lmer_gauss", r, quiet_time(function() lmer(y ~ time + (1 + time | id), d)))
    rec("growth", lab, nrow(d), "fit", "tmb_gauss", r, quiet_time(function() glmmTMB(y ~ time + (1 + time | id), d, REML = TRUE)))
    rec("growth", lab, nrow(d), "fit_ar1", "tmb_gauss", r, quiet_time(function() glmmTMB(y ~ time + (1 + time | id) + ar1(times + 0 | id), d, REML = TRUE)))
    cat(sprintf("[%6.1fs] growth %s rep %d\n", elapsed(), lab, r)); flush.console()
  }
}

## 4. Other glmmTMB families on the nested J30 x m20 design (random slope)
gen_fam <- function(J, m) {
  g <- factor(rep(seq_len(J), each = m)); n <- J * m; x <- rnorm(n); z <- rep(rep(c(-.5, .5), length.out = J), each = m)
  eta <- 0.2 * x + 0.3 * z + rnorm(J, 0, 0.5)[g] + rnorm(J, 0, 0.3)[g] * x
  mu <- plogis(eta)
  data.frame(g, x, z, ynb = rnbinom(n, mu = exp(0.5 + eta), size = 2), ypois = rpois(n, exp(0.5 + eta)),
             ybeta = rbeta(n, mu * 10, (1 - mu) * 10))
}
for (r in 1:3) {
  if (elapsed() > budget) break
  d <- gen_fam(30, 20)
  rec("nested", "J30_m20_cv0.0", nrow(d), "fit", "glmer_pois", r, quiet_time(function() glmer(ypois ~ x * z + (1 + x | g), d, family = poisson)))
  rec("nested", "J30_m20_cv0.0", nrow(d), "fit", "tmb_pois", r, quiet_time(function() glmmTMB(ypois ~ x * z + (1 + x | g), d, family = poisson)))
  rec("nested", "J30_m20_cv0.0", nrow(d), "fit", "tmb_nb2", r, quiet_time(function() glmmTMB(ynb ~ x * z + (1 + x | g), d, family = nbinom2)))
  rec("nested", "J30_m20_cv0.0", nrow(d), "fit", "tmb_beta", r, quiet_time(function() glmmTMB(ybeta ~ x * z + (1 + x | g), d, family = beta_family())))
  cat(sprintf("[%6.1fs] families rep %d\n", elapsed(), r)); flush.console()
}

## 5. Throughput: 1 vs 4 concurrent processes, same 16 fits (crossed S48 x I32, lmer and glmer)
gen_c <- function(S, I) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  d$A <- ifelse((as.integer(d$subj) + as.integer(d$item)) %% 2 == 0, -0.5, 0.5)
  s <- as.integer(d$subj); i <- as.integer(d$item)
  eta <- 0.2 * d$A + rnorm(S, 0, .5)[s] + rnorm(S, 0, .3)[s] * d$A + rnorm(I, 0, .4)[i] + rnorm(I, 0, .3)[i] * d$A
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta)); d
}
job <- function(k) {
  set.seed(1000 + k); d <- gen_c(48, 32)
  t0 <- proc.time()[["elapsed"]]
  suppressWarnings(suppressMessages({
    lmer(y ~ A + (1 + A | subj) + (1 + A | item), d)
    glmer(yb ~ A + (1 + A | subj) + (1 + A | item), d, family = binomial)
  }))
  proc.time()[["elapsed"]] - t0
}
if (elapsed() < budget) {
  t0 <- proc.time()[["elapsed"]]; ser <- unlist(lapply(1:8, job)); wall1 <- proc.time()[["elapsed"]] - t0
  t0 <- proc.time()[["elapsed"]]; par4 <- unlist(mclapply(1:8, job, mc.cores = 4, mc.preschedule = FALSE)); wall4 <- proc.time()[["elapsed"]] - t0
  thr <- data.frame(mode = c("serial_1proc", "concurrent_4proc"), jobs = 8,
                    median_job_s = c(median(ser), median(par4)), wall_s = c(wall1, wall4))
  write.csv(thr, file.path(out_dir, "throughput.csv"), row.names = FALSE)
  print(thr)
}
out <- do.call(rbind, rows)
write.csv(out, file.path(out_dir, "timing_raw2.csv"), row.names = FALSE)
cat(sprintf("Total elapsed %.1f s; rows %d\n", elapsed(), nrow(out)))
