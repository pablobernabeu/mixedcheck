# Z17 Duplicate keys from a double import, and its matched negative Z17N. In
# Z17, the trials 1 to 5 of subject s03 were imported twice, so the declared
# key (subject, trial) repeats with identical rows. Z17N holds the same
# trial-level data without the trial column and without a declared key, in
# which identical rows are legitimate and keys.duplicates has no key to judge
# them by.

# The data: subjects s01 onwards with T trials each, cond A in odd trials and
# B in even ones, and the binary accuracy acc, ordered by subject and trial,
# followed by copies of the rows of the duplicated subject with the
# duplicated trials, in trial order. Without trial_column, the column trial
# is left out. Draws: acc for each of the S T rows in order, 1 when a uniform
# draw is below accuracy. The copies repeat their originals. No property is
# drawn, since no expectation of this run at T0 reads acc.
zoo_Z17 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    S <- p$subjects
    T <- p$trials
    acc <- as.integer(stats::runif(S * T) < as.numeric(p$accuracy))
    subject <- rep(seq_len(S), each = T)
    trial <- rep(seq_len(T), times = S)
    copies <- which(subject == p$duplicated_subject & trial %in% unlist(p$duplicated_trials))
    rows <- c(seq_len(S * T), copies)
    data <- data.frame(
      subject = zoo_label("s", subject[rows], S),
      trial = trial[rows],
      cond = ifelse(trial[rows] %% 2 == 1, "A", "B"),
      acc = acc[rows]
    )
    if (!p$trial_column) {
      data$trial <- NULL
    }
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z17_declaration <- function(p, title) {
  fields <- list(list(name = "subject", type = "string"))
  if (p$trial_column) {
    fields <- c(fields, list(list(name = "trial", type = "integer")))
  }
  fields <- c(fields, list(
    list(name = "cond", type = "string", categories = zn("A", "B")),
    list(name = "acc", type = "integer")
  ))
  declaration <- list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("trial_level"),
    table = list(fields = fields),
    units = list(list(name = "subject", columns = zn("subject"), role = "participant"))
  )
  if (p$trial_column) {
    declaration$observation <- list(key = zn("subject", "trial"))
  }
  declaration$variables <- list(acc = list(role = "outcome", measurement = "binary"))
  declaration
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# cond[B] and the term 1 + cond | subject with the same columns, over every
# row of the table, the copies included. The family class is bernoulli, so
# the Gram matrix has no residual.
zoo_Z17_gram <- function(p) {
  S <- p$subjects
  T <- p$trials
  subject <- rep(seq_len(S), each = T)
  trial <- rep(seq_len(T), times = S)
  copies <- which(subject == p$duplicated_subject & trial %in% unlist(p$duplicated_trials))
  rows <- c(seq_len(S * T), copies)
  X <- cbind(1, as.numeric(trial[rows] %% 2 == 0))
  list(X = X, terms = list(list(factor = subject[rows], columns = X)), gaussian = FALSE)
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit, so the levels of subject and the cells of
# subject and pattern resolve as person counts, and the levels of cond and
# trial, which hold every subject, as non-person counts.
zoo_Z17_expected <- function(p, data) {
  S <- p$subjects
  T <- p$trials
  d <- length(unlist(p$duplicated_trials))
  stopifnot(S >= 3, T >= 4, T %% 2 == 0, p$duplicated_subject <= S)
  N <- S * T + d
  P <- "person"
  NP <- zoo_count_class(S)
  sizes <- rep(T, S)
  sizes[p$duplicated_subject] <- T + d
  design <- zoo_Z17_gram(p)
  gram <- zoo_gram(design$X, design$terms, gaussian = FALSE)
  stopifnot(length(gram$vanishing) == 0L, gram$smallest_eigenvalue > 1e-3)
  term <- "1 + cond | subject"
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and cond[B] are linearly independent."),
      zoo_db("subject", P, S, S - 1, "(Intercept)",
             paste0("J - k + r = ", S, " - 2 + 1, since cond varies within every subject.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "necessary_only",
        statistics = list(parameters = zv(gram$parameters), rank = zv(gram$parameters),
                          verdict = zv("necessary_condition_met"),
                          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
                          smallest_eigenvalue = zv(gram$smallest_eigenvalue)),
        why = paste0("Three covariance parameters on the latent scale, without a residual, ",
                     "separated by both conditions in every subject, as zoo_gram() computes them.")
      ),
      zoo_finding(
        "identifiability.levels_vs_dimension", list(factor = "subject", term = term),
        "consistent", "adequate",
        list(dimension = zv(2), levels = zv(S, P), informative_levels = zv(S, P),
             counterparts = zv(TRUE), bound = zv(S - 1, P)),
        why = paste0("[1, cond[B]] has rank 2 within every subject, and the bound ", S - 1,
                     " is at least 2.")
      ),
      zoo_finding(
        "identifiability.residual_confounding", list(factor = "subject", term = term),
        "consistent", "replicated",
        list(columns = zv(2), correlated = zv(TRUE), pattern_terms = zv(zn(term)),
             cells = zv(2 * S, P), replicated_cells = zv(2 * S, P), intercept_alone = zv(FALSE)),
        why = paste0("Each subject has both conditions, each in at least ", T / 2, " rows.")
      ),
      zoo_lu("cond", NP),
      zoo_lu("subject", P),
      zoo_sr(N),
      zoo_cs("subject", P, sizes, why = if (d > 0) {
        paste0(S - 1, " subjects with ", T, " rows and s", zoo_label("", p$duplicated_subject, S),
               " with ", T + d, ".")
      } else {
        paste0(S, " subjects with ", T, " rows each.")
      }),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(S, P),
             informative_levels = zv(S, P), status = zv("within"),
             slope_requested = zv(TRUE), icc = za(), within_share = za()),
        why = "Every subject has trials of both conditions."
      )
    )
  )
  if (p$trial_column) {
    findings <- c(findings, list(
      if (d > 0) {
        zoo_finding(
          "keys.duplicates", finding = "consequential", message = "double_import",
          statistics = list(rows = zv(N), key_columns = zv(zn("subject", "trial")),
                            missing_key_rows = zv(0), duplicated_keys = zv(d),
                            conflicting_keys = zv(0), identical_keys = zv(d),
                            duplicate_rows = zv(2 * d)),
          why = paste0("The ", d, " copies equal their originals in every compared column, acc ",
                       "being the outcome, so ", d, " keys repeat with identical rows.")
        )
      } else {
        zoo_kd(c("subject", "trial"), N)
      },
      zoo_lu("trial", NP, "The trials are integers.")
    ))
  } else {
    findings <- c(findings, list(
      zoo_not_available("keys.duplicates", "declaration_missing", "/observation/key",
                        "The declaration has no observation key.")
    ))
  }
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z17_parameters <- function(duplicated) {
  list(subjects = 10, trials = 20, accuracy = "0.8", duplicated_subject = 3,
       duplicated_trials = zoo_array(if (duplicated) c(1, 2, 3, 4, 5) else numeric(0)),
       trial_column = duplicated)
}

zoo_define(
  id = "Z17", name = "duplicate-keys", title = "Duplicate keys from a double import",
  role = "fixture", matched = "Z17N", negative_of = character(0), domain = "trial-level",
  catalogue = c("L1-15", "L7-19"),
  planted = paste("The trials 1 to 5 of subject s03 were imported twice, so the declared key",
                  "(subject, trial) repeats with identical rows."),
  seed = 202611170, parameters = zoo_Z17_parameters(TRUE), generate = zoo_Z17,
  declaration = function(p) zoo_Z17_declaration(p, "Z17 Duplicate keys from a double import"),
  formula = function(p) "acc ~ cond + (1 + cond | subject)",
  run = zoo_access("Z17", "T0"), expected = zoo_Z17_expected,
  signal = list(zoo_signal("keys.duplicates", list(), "double_import"))
)

zoo_define(
  id = "Z17N", name = "identical-rows-without-key",
  title = "Identical trial rows without a declared key",
  role = "negative", matched = "Z17", negative_of = "Z17", domain = "trial-level",
  catalogue = c("L1-15", "L7-19"),
  planted = paste("The trial-level data have no trial column and no declared key, so rows that",
                  "are identical are legitimate repetitions."),
  seed = 202611170, parameters = zoo_Z17_parameters(FALSE), generate = zoo_Z17,
  declaration = function(p) {
    zoo_Z17_declaration(p, "Z17N Identical trial rows without a declared key")
  },
  formula = function(p) "acc ~ cond + (1 + cond | subject)",
  run = zoo_access("Z17N", "T0"), expected = zoo_Z17_expected,
  signal = list()
)
