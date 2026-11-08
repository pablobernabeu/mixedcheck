# R reference fits for the Python-engine benchmark (key A).
# Generates/exports datasets to CSV and fits lme4 (and glmmTMB where applicable).
# Usage: Rscript r_reference.R <outdir>
suppressPackageStartupMessages({
  library(lme4); library(glmmTMB); library(jsonlite)
})
args <- commandArgs(trailingOnly = TRUE)
outdir <- if (length(args)) args[1] else "."
dir.create(file.path(outdir, "data"), showWarnings = FALSE, recursive = TRUE)
nrep <- as.integer(Sys.getenv("BENCH_NREP", "3"))

## ---------------------------------------------------------------- datasets
ds <- list()
ds$sleep <- lme4::sleepstudy
ds$sleep$Subject <- as.character(ds$sleep$Subject)
ds$penicillin <- lme4::Penicillin
ds$penicillin$plate <- as.character(ds$penicillin$plate)
ds$penicillin$sample <- as.character(ds$penicillin$sample)
ds$pastes <- lme4::Pastes
ds$pastes$batch <- as.character(ds$pastes$batch)
ds$pastes$cask <- as.character(ds$pastes$cask)
ds$pastes$sample <- as.character(ds$pastes$sample)   # = batch:cask
cb <- lme4::cbpp
cb$herd <- as.character(cb$herd); cb$period <- as.character(cb$period)
cb$prop <- cb$incidence / cb$size
ds$cbpp <- cb
ow <- glmmTMB::Owls
ds$owls <- data.frame(Nest = as.character(ow$Nest),
                      FoodTreatment = as.character(ow$FoodTreatment),
                      SexParent = as.character(ow$SexParent),
                      SiblingNegotiation = ow$SiblingNegotiation,
                      BroodSize = ow$BroodSize,
                      logBroodSize = log(ow$BroodSize))

sim_crossed <- function(nsubj, nitem, seed) {
  set.seed(seed)
  d <- expand.grid(subj = sprintf("s%03d", 1:nsubj), item = sprintf("i%03d", 1:nitem),
                   stringsAsFactors = FALSE)
  si <- as.integer(factor(d$subj)); ii <- as.integer(factor(d$item))
  d$cond <- ifelse((si + ii) %% 2 == 0, -0.5, 0.5)   # within subject and within item, counterbalanced
  Ss <- matrix(c(30^2, 0.3 * 30 * 15, 0.3 * 30 * 15, 15^2), 2)
  Si <- matrix(c(20^2, -0.2 * 20 * 10, -0.2 * 20 * 10, 10^2), 2)
  bs <- MASS::mvrnorm(nsubj, c(0, 0), Ss); bi <- MASS::mvrnorm(nitem, c(0, 0), Si)
  d$y <- 500 + 25 * d$cond + bs[si, 1] + bs[si, 2] * d$cond + bi[ii, 1] + bi[ii, 2] * d$cond +
    rnorm(nrow(d), 0, 50)
  d$y <- round(d$y, 6)
  d
}
ds$crossed <- sim_crossed(60, 40, 101)
ds$crossedbig <- sim_crossed(150, 80, 202)

set.seed(303)  # unbalanced three-level school design
nsch <- 50
rows <- list(); k <- 0
u_s <- MASS::mvrnorm(nsch, c(0, 0), matrix(c(4, 0.4 * 2 * 0.7, 0.4 * 2 * 0.7, 0.49), 2))
w_s <- rnorm(nsch)
for (s in 1:nsch) {
  ncl <- sample(1:6, 1)
  for (c in 1:ncl) {
    npup <- sample(3:30, 1); uc <- rnorm(1, 0, 1.2)
    x <- rnorm(npup)
    y <- 10 + 1.5 * x + 0.8 * w_s[s] + u_s[s, 1] + u_s[s, 2] * x + uc + rnorm(npup, 0, 3)
    k <- k + 1
    rows[[k]] <- data.frame(school = sprintf("sch%02d", s), class = sprintf("c%d", c),
                            x = round(x, 6), w = round(w_s[s], 6), y = round(y, 6))
  }
}
sc <- do.call(rbind, rows)
sc$schoolclass <- paste(sc$school, sc$class, sep = ":")
ds$school <- sc

# near-singular: random slope with zero true variance, few groups
set.seed(404)
J <- 6; n <- 8
ns <- data.frame(g = rep(sprintf("g%d", 1:J), each = n), t = rep(0:(n - 1), J))
b0 <- rnorm(J, 0, 1)
ns$y <- round(2 + 0.5 * ns$t + b0[as.integer(factor(ns$g))] + rnorm(nrow(ns), 0, 1), 6)
ds$nearsing <- ns

# weighted LMM: rows are means of w replicates (precision weights)
set.seed(505)
G <- 30
wl <- do.call(rbind, lapply(1:G, function(g) {
  m <- sample(5:15, 1)
  data.frame(g = sprintf("g%02d", g), x = round(rnorm(m), 6), w = sample(1:10, m, replace = TRUE))
}))
bg <- rnorm(G, 0, 1.5)
wl$y <- round(3 + 2 * wl$x + bg[as.integer(factor(wl$g))] + rnorm(nrow(wl), 0, 2 / sqrt(wl$w)), 6)
ds$weighted <- wl

# stress 1: binary crossed subject x item GLMM with a correlated by-subject slope
set.seed(606)
bx <- expand.grid(subj = sprintf("s%02d", 1:40), item = sprintf("i%02d", 1:30), stringsAsFactors = FALSE)
si <- as.integer(factor(bx$subj)); ii <- as.integer(factor(bx$item))
bx$cond <- ifelse((si + ii) %% 2 == 0, -0.5, 0.5)
bs <- MASS::mvrnorm(40, c(0, 0), matrix(c(1, 0.3, 0.3, 0.5), 2)); bi <- rnorm(30, 0, 0.7)
eta <- -0.5 + 0.8 * bx$cond + bs[si, 1] + bs[si, 2] * bx$cond + bi[ii]
bx$y <- rbinom(nrow(bx), 1, plogis(eta)); bx$n <- 1
ds$binxd <- bx
# stress 2: J <= q (3 groups, 3 random effects per group): singular optimum guaranteed
set.seed(707)
jq <- data.frame(g = rep(sprintf("g%d", 1:3), each = 20), x1 = round(rnorm(60), 6), x2 = round(rnorm(60), 6))
bj <- MASS::mvrnorm(3, c(0, 0, 0), diag(c(1, 0.25, 0.25)))
gi <- as.integer(factor(jq$g))
jq$y <- round(1 + 0.5 * jq$x1 - 0.3 * jq$x2 + bj[gi, 1] + bj[gi, 2] * jq$x1 + bj[gi, 3] * jq$x2 + rnorm(60), 6)
ds$jq <- jq
for (nm in names(ds)) write.csv(ds[[nm]], file.path(outdir, "data", paste0(nm, ".csv")), row.names = FALSE)

## ---------------------------------------------------------------- model specs
specs <- list(
  list(id = "sleep_REML",   data = "sleep", type = "lmer", REML = TRUE,
       f = Reaction ~ Days + (Days | Subject)),
  list(id = "sleep_ML",     data = "sleep", type = "lmer", REML = FALSE,
       f = Reaction ~ Days + (Days | Subject)),
  list(id = "sleep_zcp_ML", data = "sleep", type = "lmer", REML = FALSE,
       f = Reaction ~ Days + (1 | Subject) + (0 + Days | Subject)),
  list(id = "pen_REML",     data = "penicillin", type = "lmer", REML = TRUE,
       f = diameter ~ 1 + (1 | plate) + (1 | sample)),
  list(id = "pen_ML",       data = "penicillin", type = "lmer", REML = FALSE,
       f = diameter ~ 1 + (1 | plate) + (1 | sample)),
  list(id = "pastes_REML",  data = "pastes", type = "lmer", REML = TRUE,
       f = strength ~ 1 + (1 | batch) + (1 | sample)),
  list(id = "pastes_ML",    data = "pastes", type = "lmer", REML = FALSE,
       f = strength ~ 1 + (1 | batch) + (1 | sample)),
  list(id = "cbpp_laplace", data = "cbpp", type = "glmer", nAGQ = 1, family = "binomial",
       f = cbind(incidence, size - incidence) ~ period + (1 | herd)),
  list(id = "cbpp_agq25",   data = "cbpp", type = "glmer", nAGQ = 25, family = "binomial",
       f = cbind(incidence, size - incidence) ~ period + (1 | herd)),
  list(id = "crossed_REML", data = "crossed", type = "lmer", REML = TRUE,
       f = y ~ cond + (1 + cond | subj) + (1 + cond | item)),
  list(id = "crossed_ML",   data = "crossed", type = "lmer", REML = FALSE,
       f = y ~ cond + (1 + cond | subj) + (1 + cond | item)),
  list(id = "crossed_zcp_REML", data = "crossed", type = "lmer", REML = TRUE,
       f = y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)),
  list(id = "crossed_zcp_ML", data = "crossed", type = "lmer", REML = FALSE,
       f = y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)),
  list(id = "crossedbig_REML", data = "crossedbig", type = "lmer", REML = TRUE,
       f = y ~ cond + (1 + cond | subj) + (1 + cond | item)),
  list(id = "crossedbig_zcp_REML", data = "crossedbig", type = "lmer", REML = TRUE,
       f = y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)),
  list(id = "school_REML",  data = "school", type = "lmer", REML = TRUE,
       f = y ~ x + w + (1 + x | school) + (1 | schoolclass)),
  list(id = "school_ML",    data = "school", type = "lmer", REML = FALSE,
       f = y ~ x + w + (1 + x | school) + (1 | schoolclass)),
  list(id = "school_zcp_ML", data = "school", type = "lmer", REML = FALSE,
       f = y ~ x + w + (1 | school) + (0 + x | school) + (1 | schoolclass)),
  list(id = "nearsing_REML", data = "nearsing", type = "lmer", REML = TRUE,
       f = y ~ t + (1 + t | g)),
  list(id = "nearsing_ML",  data = "nearsing", type = "lmer", REML = FALSE,
       f = y ~ t + (1 + t | g)),
  list(id = "nearsing_zcp_ML", data = "nearsing", type = "lmer", REML = FALSE,
       f = y ~ t + (1 | g) + (0 + t | g)),
  list(id = "owls_pois",    data = "owls", type = "glmer", nAGQ = 1, family = "poisson",
       f = SiblingNegotiation ~ FoodTreatment * SexParent + offset(logBroodSize) + (1 | Nest)),
  list(id = "owls_pois_agq25", data = "owls", type = "glmer", nAGQ = 25, family = "poisson",
       f = SiblingNegotiation ~ FoodTreatment * SexParent + offset(logBroodSize) + (1 | Nest)),
  list(id = "binxd_laplace", data = "binxd", type = "glmer", nAGQ = 1, family = "binomial",
       f = cbind(y, n - y) ~ cond + (1 + cond | subj) + (1 | item)),
  list(id = "jq_REML", data = "jq", type = "lmer", REML = TRUE,
       f = y ~ x1 + x2 + (1 + x1 + x2 | g)),
  list(id = "weighted_REML", data = "weighted", type = "lmer", REML = TRUE, weights = "w",
       f = y ~ x + (1 | g)),
  list(id = "weighted_ML",  data = "weighted", type = "lmer", REML = FALSE, weights = "w",
       f = y ~ x + (1 | g))
)

## ---------------------------------------------------------------- helpers
vc_list <- function(vc) {
  out <- list()
  for (g in names(vc)) {
    m <- as.matrix(vc[[g]]); attr(m, "stddev") <- NULL; attr(m, "correlation") <- NULL
    out[[g]] <- list(terms = colnames(m), cov = unname(m))
  }
  out
}
time_fit <- function(expr_fun, nrep) {
  ts <- numeric(nrep); fit <- NULL
  for (r in seq_len(nrep)) { t0 <- proc.time()[["elapsed"]]; fit <- expr_fun(); ts[r] <- proc.time()[["elapsed"]] - t0 }
  list(fit = fit, times = ts)
}
capture_warn <- function(fun) {
  w <- character(); m <- character()
  val <- withCallingHandlers(fun(),
    warning = function(cw) { w <<- c(w, conditionMessage(cw)); invokeRestart("muffleWarning") },
    message = function(cm) { m <<- c(m, conditionMessage(cm)); invokeRestart("muffleMessage") })
  list(value = val, warnings = w, messages = m)
}

res <- list()
only <- Sys.getenv("BENCH_ONLY", "")
if (nzchar(only)) specs <- Filter(function(sp) sp$id %in% strsplit(only, ",")[[1]], specs)
for (sp in specs) {
  d <- ds[[sp$data]]
  ## ---- lme4
  fun <- if (sp$type == "lmer") {
    if (!is.null(sp$weights)) function() lmer(sp$f, data = d, REML = sp$REML, weights = d[[sp$weights]])
    else function() lmer(sp$f, data = d, REML = sp$REML)
  } else {
    function() glmer(sp$f, data = d, family = sp$family, nAGQ = sp$nAGQ)
  }
  cw <- capture_warn(function() time_fit(fun, nrep))
  fit <- cw$value$fit
  vc <- VarCorr(fit)
  r <- list(model = sp$id, engine = "lme4", engine_version = as.character(packageVersion("lme4")),
            nobs = nobs(fit),
            beta = as.list(fixef(fit)), se = as.list(sqrt(diag(as.matrix(vcov(fit))))),
            vcov = unname(as.matrix(vcov(fit))),
            re = vc_list(vc), sigma = sigma(fit), theta = unname(getME(fit, "theta")),
            logLik = as.numeric(logLik(fit)), deviance_or_REMLcrit = if (isREML(fit)) REMLcrit(fit) else deviance(fit),
            REML = isREML(fit), singular = isSingular(fit),
            optinfo_conv = fit@optinfo$conv$opt, optinfo_msgs = unlist(fit@optinfo$conv$lme4$messages),
            warnings = cw$warnings, messages = cw$messages,
            times = cw$value$times, time_median = median(cw$value$times))
  if (sp$type == "glmer") {
    r$nAGQ <- sp$nAGQ
    r$devfun_value <- tryCatch({
      df <- update(fit, devFunOnly = TRUE)
      if (sp$nAGQ == 0) NA else df(c(getME(fit, "theta"), fixef(fit)))
    }, error = function(e) NA)
  }
  ## ranef + condvar summary for the first grouping factor
  re <- ranef(fit, condVar = TRUE)
  g1 <- names(re)[1]
  pv <- attr(re[[g1]], "postVar")
  if (is.list(pv)) pv <- pv[[1]]
  r$ranef_first <- list(group = g1, levels = rownames(re[[g1]]), values = unname(as.matrix(re[[g1]])),
                        condvar_diag = if (!is.null(pv)) { q <- dim(pv)[1]; t(vapply(seq_len(dim(pv)[3]), function(i) diag(matrix(pv[, , i], q, q)), numeric(q))) } else NULL)
  res[[length(res) + 1]] <- r
  cat(sprintf("%-18s lme4    logLik=%.6f crit=%.6f  t=%.3f sing=%s warn=%d\n", sp$id, r$logLik,
              r$deviance_or_REMLcrit, r$time_median, r$singular, length(r$warnings)))

  ## ---- glmmTMB (skip AGQ specs; glmmTMB is Laplace only)
  if (is.null(sp$nAGQ) || sp$nAGQ == 1) {
    funT <- if (sp$type == "lmer") {
      if (!is.null(sp$weights)) function() glmmTMB(sp$f, data = d, REML = sp$REML, weights = d[[sp$weights]])
      else function() glmmTMB(sp$f, data = d, REML = sp$REML)
    } else {
      if (sp$family == "binomial") function() glmmTMB(sp$f, data = d, family = binomial)
      else function() glmmTMB(sp$f, data = d, family = poisson)
    }
    cwT <- capture_warn(function() time_fit(funT, nrep))
    ft <- cwT$value$fit
    vcT <- VarCorr(ft)$cond
    bT <- fixef(ft)$cond
    vT <- as.matrix(vcov(ft)$cond)
    rT <- list(model = sp$id, engine = "glmmTMB", engine_version = as.character(packageVersion("glmmTMB")),
               nobs = nobs(ft), beta = as.list(bT), se = as.list(sqrt(diag(vT))), vcov = unname(vT),
               re = vc_list(vcT), sigma = sigma(ft),
               logLik = as.numeric(logLik(ft)), objective = ft$fit$objective,
               REML = isTRUE(sp$REML), pdHess = ft$sdr$pdHess, convergence = ft$fit$convergence,
               fit_message = ft$fit$message,
               warnings = cwT$warnings, messages = cwT$messages,
               times = cwT$value$times, time_median = median(cwT$value$times))
    res[[length(res) + 1]] <- rT
    cat(sprintf("%-18s glmmTMB logLik=%.6f            t=%.3f pdHess=%s warn=%d\n", sp$id, rT$logLik,
                rT$time_median, rT$pdHess, length(rT$warnings)))
  }
}
sess <- list(R = R.version.string, lme4 = as.character(packageVersion("lme4")),
             glmmTMB = as.character(packageVersion("glmmTMB")), Matrix = as.character(packageVersion("Matrix")),
             TMB = as.character(packageVersion("TMB")), blas = extSoftVersion()[["BLAS"]],
             nrep = nrep, date = as.character(Sys.time()))
writeLines(toJSON(list(session = sess, results = res), auto_unbox = TRUE, digits = NA, null = "null", na = "null",
                  pretty = TRUE), file.path(outdir, if (nzchar(only)) "r_reference_extra.json" else "r_reference.json"))
cat("done\n")
