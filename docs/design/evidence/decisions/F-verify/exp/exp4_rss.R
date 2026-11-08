# F-verify exp4: peak resident memory (whole process, incl. C/C++ allocations) of the largest fits
# F budgets for; F reported R-heap 'max used' from gc() only. Usage: Rscript exp4_rss.R <which>
suppressPackageStartupMessages({ library(lme4); library(glmmTMB) })
which <- commandArgs(trailingOnly = TRUE)[1]; set.seed(1)
gen_2x2 <- function(S, I) {
  d <- expand.grid(subj = factor(seq_len(S)), item = factor(seq_len(I)))
  cell <- (as.integer(d$subj) + as.integer(d$item)) %% 4
  d$A <- ifelse(cell %in% c(0, 1), -0.5, 0.5); d$B <- ifelse(cell %in% c(0, 2), -0.5, 0.5)
  mk <- function(n, sds) { R <- matrix(0.3, 4, 4); diag(R) <- 1; MASS::mvrnorm(n, rep(0, 4), diag(sds) %*% R %*% diag(sds)) }
  us <- mk(S, c(0.5, 0.2, 0.2, 0.1)); ui <- mk(I, c(0.4, 0.2, 0.2, 0.1))
  s <- as.integer(d$subj); i <- as.integer(d$item); X <- cbind(1, d$A, d$B, d$A * d$B)
  eta <- drop(X %*% c(0, 0.2, 0.1, 0.05)) + rowSums(X * us[s, ]) + rowSums(X * ui[i, ])
  d$y <- eta + rnorm(nrow(d)); d$yb <- rbinom(nrow(d), 1, plogis(eta)); d
}
if (which == "lmer6144") { d <- gen_2x2(96, 64); f <- suppressWarnings(suppressMessages(lmer(y ~ A * B + (1 + A * B | subj) + (1 + A * B | item), d))) }
if (which == "tmbB1536") { d <- gen_2x2(48, 32); f <- suppressWarnings(suppressMessages(glmmTMB(yb ~ A * B + (1 + A * B | subj) + (1 + A * B | item), d, family = binomial))) }
cat(which, "done\n")
