# Z14 Rank-deficient fixed effects from an empty cell, and its matched
# negative Z14N. In Z14, the subjects at level a3 of A never see level b2 of
# B, so the interaction A:B has an empty cell and its column for a3 and b2 is
# 0 in every row. In Z14N, every cell has rows.

# The data: K levels of A with m subjects each, s01 onwards in the order of
# A, and T trials for each subject. B is b1 in the first half of the trials
# and b2 in the second, except at the last level of A with empty_cell true,
# where it is b1 in every trial. The rows are ordered by subject and trial.
# Draws, in this order: K m subject effects and the residuals in row order.
# y is the subject effect plus the residual, rounded to the stored grid. No
# property is drawn.
zoo_Z14 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z14_design(p)
    S <- p$levels_A * p$subjects_per_level
    subject_effect <- stats::rnorm(S, 0, as.numeric(p$sd_subject))
    residual <- stats::rnorm(length(design$subject), 0, as.numeric(p$sd_residual))
    data <- data.frame(
      subject = zoo_label("s", design$subject, S),
      A = paste0("a", zoo_digits(design$a)),
      B = paste0("b", zoo_digits(design$b)),
      trial = design$trial,
      y = zoo_round(subject_effect[design$subject] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: subject, level of A, level of B and trial.
zoo_Z14_design <- function(p) {
  K <- p$levels_A
  m <- p$subjects_per_level
  T <- p$trials
  subject <- rep(seq_len(K * m), each = T)
  a <- (subject - 1L) %/% m + 1L
  trial <- rep(seq_len(T), times = K * m)
  b <- ifelse(trial <= T / 2 | (p$empty_cell & a == K), 1L, 2L)
  list(subject = subject, a = a, b = b, trial = trial)
}

zoo_Z14_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "A", type = "string",
           categories = zn(paste0("a", zoo_digits(seq_len(p$levels_A))))),
      list(name = "B", type = "string", categories = zn("b1", "b2")),
      list(name = "trial", type = "integer"),
      list(name = "y", type = "number")
    )),
    units = list(list(name = "subject", columns = zn("subject"), role = "participant")),
    observation = list(key = zn("subject", "trial")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The fixed-effects columns of A * B under treatment coding: (Intercept),
# A[a2] to A[aK], B[b2] and A[ak]:B[b2] for k from 2 to K.
zoo_Z14_X <- function(p) {
  design <- zoo_Z14_design(p)
  K <- p$levels_A
  A <- sapply(2:K, function(k) as.numeric(design$a == k))
  colnames(A) <- paste0("A[a", zoo_digits(2:K), "]")
  b2 <- as.numeric(design$b == 2L)
  AB <- A * b2
  colnames(AB) <- paste0(colnames(A), ":B[b2]")
  X <- cbind("(Intercept)" = 1, A, "B[b2]" = b2, AB)
  X
}

zoo_Z14_gram <- function(p) {
  design <- zoo_Z14_design(p)
  list(X = zoo_Z14_X(p),
       terms = list(list(factor = design$subject, columns = matrix(1, length(design$subject), 1L))))
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit and holds T rows, and each level of A, of B
# and of trial holds several subjects.
zoo_Z14_expected <- function(p, data) {
  K <- p$levels_A
  m <- p$subjects_per_level
  T <- p$trials
  stopifnot(K == 3, m >= 2, T >= 2, T %% 2 == 0)
  S <- K * m
  N <- S * T
  P <- "person"
  NP <- zoo_count_class(m)
  X <- zoo_Z14_X(p)
  main <- X[, c("A[a2]", "A[a3]", "B[b2]")]
  gvif_A <- zoo_gvif(main, c("A[a2]", "A[a3]"))
  gvif_B <- zoo_gvif(main, "B[b2]")
  half <- T / 2
  # With the empty cell, B[b2] has the means 1/2, 1/2 and 0 at a1, a2 and a3
  # and the overall mean 1/3, so the share of its variance between the
  # levels of A is (1/18)/(2/9) = 1/4 and each GVIF is 1/(1 - 1/4) = 4/3.
  # Without it, B[b2] has the mean 1/2 at every level and each GVIF is 1.
  stopifnot(abs(gvif_B$gvif - if (p$empty_cell) 4 / 3 else 1) < 1e-12)
  findings <- c(
    zoo_na3(),
    list(
      zoo_finding(
        "design.collinearity", list(term = "A"), "consistent", "low",
        list(df = zv(2), gvif = zv(gvif_A$gvif), gvif_per_df = zv(gvif_A$gvif_per_df)),
        why = if (p$empty_cell) {
          "The share of the variance of B[b2] between the levels of A is 1/4, so the GVIF is 4/3."
        } else {
          paste("B[b2] has the mean 1/2 at every level of A, so it is uncorrelated with A and",
                "the GVIF is 1.")
        }
      ),
      zoo_finding(
        "design.collinearity", list(term = "B"), "consistent", "low",
        list(df = zv(1), gvif = zv(gvif_B$gvif), gvif_per_df = zv(gvif_B$gvif_per_df)),
        why = if (p$empty_cell) {
          "The share of the variance of B[b2] between the levels of A is 1/4, so the GVIF is 4/3."
        } else {
          paste("B[b2] has the mean 1/2 at every level of A, so it is uncorrelated with A and",
                "the GVIF is 1.")
        }
      ),
      zoo_db("subject", P, S, S - 3, c("(Intercept)", "A"),
             paste0("J - k + r = ", S, " - ", if (p$empty_cell) "5 + 2" else "6 + 3",
                    ", since A is constant within subjects and B and the kept interaction ",
                    "columns vary within them.")),
      zoo_gr(zoo_Z14_gram(p),
             "The subject variance and the residual, as zoo_gram() computes them."),
      zoo_ld1("subject", P, S),
      zoo_rc1("subject", P, S, paste0(T, " rows in each level.")),
      zoo_kd(c("subject", "trial"), N,
             paste0("Each of the ", N, " pairs of subject and trial has one row.")),
      zoo_lu("A", NP),
      zoo_lu("B", NP),
      zoo_lu("subject", P),
      zoo_lu("trial", zoo_count_class(S), "The trials are the integers 1 to 4."),
      zoo_sr(N),
      zoo_cs("subject", P, rep(T, S)),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "A"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(0, P),
             informative_levels = zv(0, P), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Each subject is at one level of A."
      )
    )
  )
  if (p$empty_cell) {
    findings <- c(findings, list(
      zoo_finding(
        "design.rank_deficiency", finding = "consequential", message = "focal",
        statistics = list(columns = zv(6), kept = zv(5),
                          dropped_columns = zv(zn("A[a3]:B[b2]")), dropped_terms = zv(zn("A:B")),
                          empty_cells = zv(1), focal_dropped = zv(TRUE)),
        why = paste0("No subject at a3 sees b2, so A[a3]:B[b2] is 0 in every row, and with no ",
                     "estimand declared every term is focal.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "A:B"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(m, P),
             informative_levels = zv(m, P), status = zv("partially_within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("The kept column A[a2]:B[b2] varies within the ", m, " subjects at a2 only, ",
                     "so the pooled agreement is ", N - m * half, "/", N, ".")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "B"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(2 * m, P),
             informative_levels = zv(2 * m, P), status = zv("partially_within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("B varies within the ", 2 * m, " subjects at a1 and a2 and not at a3, so ",
                     "the pooled agreement is ", N - 2 * m * half, "/", N, ".")
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_rd(6, "Every cell of A and B has rows, so the six columns are linearly independent."),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "A:B"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(2 * m, P),
             informative_levels = zv(0, P), status = zv("partially_within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("The subjects at a2 and a3 vary in one of the two kept columns only, so ",
                     "none has rank 2, and the pooled agreement is ", N - 2 * m * half, "/", N,
                     ".")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "B"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(S, P),
             informative_levels = zv(S, P), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every subject sees b1 and b2."
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z14_parameters <- function(empty_cell) {
  list(levels_A = 3, subjects_per_level = 6, trials = 4, empty_cell = empty_cell,
       sd_subject = "0.5", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z14", name = "empty-cell", title = "Rank-deficient fixed effects from an empty cell",
  role = "fixture", matched = "Z14N", negative_of = character(0), domain = "any",
  catalogue = c("L1-12", "L2-05"),
  planted = paste("The subjects at a3 never see b2, so the interaction A:B has an empty cell",
                  "and its column for a3 and b2 is 0 in every row."),
  seed = 202611140, parameters = zoo_Z14_parameters(TRUE), generate = zoo_Z14,
  declaration = function(p) {
    zoo_Z14_declaration(p, "Z14 Rank-deficient fixed effects from an empty cell")
  },
  formula = function(p) "y ~ A * B + (1 | subject)",
  run = zoo_access("Z14", "T0"), expected = zoo_Z14_expected,
  signal = list(zoo_signal("design.rank_deficiency", list(), "focal"))
)

zoo_define(
  id = "Z14N", name = "full-cells", title = "Every cell of the interaction has rows",
  role = "negative", matched = "Z14", negative_of = "Z14", domain = "any",
  catalogue = c("L1-12", "L2-05"),
  planted = paste("The subjects at every level of A see b1 and b2, so every cell of A and B",
                  "has rows and the fixed effects have full rank."),
  seed = 202611140, parameters = zoo_Z14_parameters(FALSE), generate = zoo_Z14,
  declaration = function(p) zoo_Z14_declaration(p, "Z14N Every cell of the interaction has rows"),
  formula = function(p) "y ~ A * B + (1 | subject)",
  run = zoo_access("Z14N", "T0"), expected = zoo_Z14_expected,
  signal = list()
)
