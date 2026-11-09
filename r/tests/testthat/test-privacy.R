# The privacy filter of shareable mode (docs/spec/privacy.md): each channel
# of disclosure by differencing that the filter closes, tried on inputs of
# these tests, the pseudonyms of labels, which registry 0.1.0 does not write,
# and the steps that the audit corpus cannot reach. Every shareable document
# that a test produces must pass validate_results().

privacy_key <- paste(sprintf("%02x", 0:31), collapse = "")

# Runs audit() at the time 0 in both modes with the example key, and checks
# that the shareable document is valid.
audit_both <- function(data, formula, ...) {
  old <- Sys.getenv("MIXEDCHECK_TIME", unset = NA)
  Sys.setenv(MIXEDCHECK_TIME = "0")
  on.exit(if (is.na(old)) Sys.unsetenv("MIXEDCHECK_TIME") else
    Sys.setenv(MIXEDCHECK_TIME = old), add = TRUE)
  run <- function(privacy) {
    audit(data, formula, ..., privacy = privacy, key = privacy_key)
  }
  shareable <- run("shareable")
  expect_silent(validate_results(shareable))
  list(internal = run("internal")$document, shareable = shareable$document)
}

# The finding of a check whose scope has the given parts.
finding_of <- function(document, check, ...) {
  scope <- list(...)
  for (finding in document$findings) {
    if (identical(finding$check, check) &&
        all(vapply(names(scope), function(part) identical(finding$scope[[part]], scope[[part]]),
                   NA))) {
      return(finding)
    }
  }
  stop(sprintf("no finding of %s", check))
}

# The written value of a statistic, or of support.rows or
# support.contributors.distinct, and NULL when it is not written.
written <- function(finding, name) {
  if (name == "support_rows") {
    return(finding$support$rows$value)
  }
  if (name == "contributors") {
    return(finding$support$contributors$distinct$value)
  }
  finding$statistics[[name]]$value
}

detail <- function(finding, name) {
  finding$statistics[[name]]$availability$detail
}

# The difference a - b of two written counts, as an attempt to recover a
# suppressed one, or NULL when either is not written.
recover_difference <- function(a, b) {
  if (is.null(a) || is.null(b)) NULL else a - b
}

# The message of a shareable finding is its fallback, which holds no
# number.
expect_message_falls_back <- function(finding, id) {
  expect_identical(finding$message$id, id)
  expect_false(grepl("[0-9]", finding$message$text))
}

test_that("shareable mode is the default and writes no commitment key", {
  data <- data.frame(y = 1:24 + 0.5, x = rep(1:12, 2), subject = rep(sprintf("s%02d", 1:12), 2))
  old <- Sys.getenv("MIXEDCHECK_TIME", unset = NA)
  Sys.setenv(MIXEDCHECK_TIME = "0")
  on.exit(if (is.na(old)) Sys.unsetenv("MIXEDCHECK_TIME") else
    Sys.setenv(MIXEDCHECK_TIME = old), add = TRUE)
  results <- audit(data, "y ~ x + (1 | subject)", key = privacy_key)
  expect_identical(results$document$privacy$mode, "shareable")
  expect_identical(capture.output(print(results))[1L], paste(
    "Shareable output: the privacy filter has reduced the risk of disclosure,",
    "but this report is not anonymous data."
  ))
  expect_identical(results$sidecar$pseudonyms, list())
  expect_silent(validate_results(results))
  path <- tempfile(fileext = ".json")
  sidecar <- tempfile(fileext = ".internal.json")
  on.exit(unlink(c(path, sidecar)), add = TRUE)
  write_results(results, path, sidecar)
  expect_false(grepl(privacy_key, rawToChar(readBin(path, "raw", file.size(path))), fixed = TRUE))
  expect_silent(validate_results(path, sidecar, data = data))
})

test_that("a part of a total cannot be recovered from the total and the other part", {
  # 40 subjects of two rows, 3 of which lack 'x', so that 3 rows leave the
  # design sample: rows_raw - rows_kept would give rows_dropped.
  data <- data.frame(y = seq_len(80) / 4, x = c(NA, NA, NA, seq_len(77) %% 7),
                     subject = rep(sprintf("s%02d", 1:40), each = 2))
  found <- audit_both(data, "y ~ x + (1 | subject)")
  internal <- finding_of(found$internal, "sample.raw_vs_analysis")
  expect_identical(written(internal, "rows_dropped"), 3)
  shared <- finding_of(found$shareable, "sample.raw_vs_analysis")
  expect_identical(detail(shared, "rows_dropped"), "min_count")
  expect_null(recover_difference(written(shared, "rows_raw"), written(shared, "rows_kept")))
  expect_identical(detail(shared, "rows_kept"), "secondary")
  # Nor from the sizes of the table and the design sample, which other
  # findings write in their supports and statistics.
  design <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(design, "support_rows"), 77)
  expect_null(written(shared, "support_rows"))
  expect_null(written(shared, "rows_raw"))
  expect_message_falls_back(shared, "rows_dropped")
})

test_that("parts of a total whose remainder is below min_count are suppressed", {
  # 40 rows, 12 under 6 repeated key values, 22 without a key and 6 with a
  # key of their own: the rows minus both parts would give back the 6, which
  # no statistic counts. 'x' is missing in 10 rows, so that the table keeps
  # its size and its contributors, the rows.
  data <- data.frame(y = seq_len(40) / 2, x = c(seq_len(30), rep(NA, 10)),
                     id = c(rep(1:6, each = 2), rep(NA, 22), 7:12))
  declaration <- list(vocabulary = "0.1.0", observation = list(key = list("id")))
  found <- audit_both(data, "y ~ x", declaration = declaration)
  internal <- finding_of(found$internal, "keys.duplicates")
  expect_identical(c(written(internal, "rows"), written(internal, "duplicate_rows"),
                     written(internal, "missing_key_rows")), c(40, 12, 22))
  shared <- finding_of(found$shareable, "keys.duplicates")
  expect_identical(written(shared, "rows"), 40)
  expect_identical(written(shared, "support_rows"), 40)
  expect_identical(detail(shared, "duplicate_rows"), "secondary")
  expect_identical(detail(shared, "missing_key_rows"), "secondary")
  # In a T1 finding, the suppressed parts are shares that the decision
  # reads, so the finding is suppressed as a whole: 14 and 20 of 40 rows at
  # the bounds leave 6 between them.
  score <- c(rep(0, 14), rep(10, 20), 3, 4, 5, 6, 7, 8)
  data <- data.frame(score = score, pupil = rep(sprintf("p%02d", 1:20), each = 2))
  declaration <- list(vocabulary = "0.1.0", variables = list(
    score = list(role = "outcome", measurement = "bounded_score", bounds = list(0, 10))
  ))
  found <- audit_both(data, "score ~ 1 + (1 | pupil)", declaration = declaration,
                      outcome_access = "T1", reason = "Bounds.")
  internal <- finding_of(found$internal, "outcome.boundary_shares")
  expect_identical(c(written(internal, "at_floor"), written(internal, "at_ceiling"),
                     written(internal, "rows")), c(14, 20, 40))
  shared <- finding_of(found$shareable, "outcome.boundary_shares")
  expect_identical(shared$status$availability$detail, "decision")
})

test_that("a product of written counts does not give back a suppressed count of levels", {
  # 15 subjects, the disclosure unit, meet both items once in one of five
  # sessions, the first of which holds one subject, so that the 5 levels of
  # 'session' are a person count below min_count, while the 10 combinations
  # divided by the 2 written levels of 'item' would give them back.
  subject <- rep(sprintf("s%02d", 1:15), each = 2)
  session <- rep(c("k1", rep("k2", 3), rep("k3", 3), rep("k4", 4), rep("k5", 4)), each = 2)
  data <- data.frame(y = seq_along(subject) + 0.5, subject = subject,
                     item = rep(c("i1", "i2"), 15), session = session)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ))
  found <- audit_both(data, "y ~ 1 + (1 | item) + (1 | session)", declaration = declaration)
  internal <- finding_of(found$internal, "structure.label_incidence", first = "item",
                         second = "session")
  expect_identical(c(written(internal, "combinations"), written(internal, "levels_first"),
                     written(internal, "levels_second")), c(10, 2, 5))
  shared <- finding_of(found$shareable, "structure.label_incidence", first = "item",
                       second = "session")
  expect_identical(written(shared, "levels_first"), 2)
  expect_identical(detail(shared, "levels_second"), "min_count")
  expect_identical(detail(shared, "combinations"), "secondary")
})

test_that("a ratio or a real with a written denominator does not give back its numerator", {
  # 6 zeros among 40 counts: zero_share times the written rows would give
  # back zeros.
  counts <- c(0, 0, 0, 0, 0, 0, rep(1:4, length.out = 34))
  data <- data.frame(count = counts, x = seq(0, 3.9, by = 0.1))
  found <- audit_both(data, "count ~ x", family = "poisson", outcome_access = "T1",
                      reason = "Zeros.")
  shared <- finding_of(found$shareable, "outcome.zero_shares")
  expect_identical(written(shared, "rows"), 40)
  expect_identical(detail(shared, "zeros"), "min_count")
  expect_identical(detail(shared, "zero_share"), "ratio")
  # 7 events among 40 rows: events_per_column times the written number of
  # kept columns would give back the minority events.
  data <- data.frame(y = c(rep(1, 7), rep(0, 33)), x = seq_len(40) / 8)
  found <- audit_both(data, "y ~ x", family = "binomial", outcome_access = "T1",
                      reason = "Events.")
  kept <- written(finding_of(found$shareable, "design.rank_deficiency"), "kept")
  expect_identical(kept, 2)
  shared <- finding_of(found$shareable, "outcome.minority_events")
  expect_identical(detail(shared, "events"), "min_count")
  expect_identical(detail(shared, "non_events"), "secondary")
  expect_identical(detail(shared, "events_per_column"), "secondary")
})

# A T1 run on 11 subjects of two rows with a binary outcome, none missing,
# so that the design and analysis samples hold the same rows and levels.
same_samples <- function() {
  data <- data.frame(y = rep(c(0, 1, 1, 0), length.out = 22), x = seq_len(22) / 2,
                     subject = rep(sprintf("s%02d", 1:11), each = 2))
  audit_both(data, "y ~ x + (1 | subject)", family = "binomial", outcome_access = "T1",
             reason = "Events.")
}

test_that("counts derived from a suppressed count of levels and the n of quantiles are hidden", {
  found <- same_samples()
  internal <- finding_of(found$internal, "identifiability.df_budget", factor = "subject")
  expect_identical(c(written(internal, "levels"), written(internal, "budget")), c(11, 10))
  # The 11 levels of the design sample equal those of the analysis sample,
  # so the design sample loses them, and the budget, a person count of at
  # least min_count, would give them back with the rank of X.
  shared <- finding_of(found$shareable, "identifiability.df_budget", factor = "subject")
  expect_identical(detail(shared, "levels"), "secondary")
  expect_identical(detail(shared, "budget"), "secondary")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_null(written(sizes, "levels"))
  for (name in c("smallest", "lower_quartile", "median", "upper_quartile", "largest")) {
    expect_null(sizes$statistics[[name]]$quantile$n)
    expect_type(sizes$statistics[[name]]$quantile$p, "double")
  }
  # The analysis sample keeps its levels in the T1 findings.
  minority <- finding_of(found$shareable, "outcome.minority_events", factor = "subject")
  expect_identical(written(minority, "levels"), 11)
})

test_that("quartiles of many levels are written, and minima and maxima never", {
  # 40 levels of 10 to 13 rows: a quartile of 40 values passes the quantile
  # rule, the quantiles 0 and 1 never do.
  sizes <- rep(10:13, 10)
  data <- data.frame(y = seq_len(sum(sizes)) / 7, subject = rep(sprintf("s%02d", 1:40), sizes))
  found <- audit_both(data, "y ~ 1 + (1 | subject)")
  shared <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(shared, "levels"), 40)
  expect_identical(c(written(shared, "lower_quartile"), written(shared, "median"),
                     written(shared, "upper_quartile")), c(10, 11, 12))
  expect_identical(shared$statistics$median$quantile, list(n = 40, p = 0.5))
  expect_identical(detail(shared, "smallest"), "quantile")
  expect_identical(detail(shared, "largest"), "quantile")
  expect_identical(detail(shared, "singletons"), "min_count")
})

test_that("the sizes of two samples do not give back the rows that a missing outcome removes", {
  # 3 of 40 rows lack the outcome: the rows of the design sample minus those
  # of the analysis sample would give 3.
  counts <- c(NA, NA, NA, rep(0:5, length.out = 37))
  data <- data.frame(count = counts, x = seq_len(40) / 4,
                     subject = rep(sprintf("s%02d", 1:20), each = 2))
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  analysis <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  design <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(analysis, "rows"), 37)
  expect_null(recover_difference(written(design, "rows"), written(analysis, "rows")))
  expect_null(recover_difference(written(design, "support_rows"),
                                 written(analysis, "support_rows")))
  # The levels of 'subject' with two rows in the design sample, 20, minus
  # those in the analysis sample, 17, would give back the 3 subjects
  # concerned.
  expect_null(written(finding_of(found$shareable, "structure.within_between", factor = "subject",
                                 term = "x"), "multi_row_levels"))
})

test_that("levels and levels with two rows do not give back the levels with one row", {
  # 20 subjects, 3 of them with one row.
  subject <- c(rep(sprintf("s%02d", 1:17), each = 2), sprintf("s%02d", 18:20))
  data <- data.frame(y = seq_along(subject) / 3, x = seq_along(subject) %% 5,
                     subject = subject)
  found <- audit_both(data, "y ~ x + (1 | subject)")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  between <- finding_of(found$shareable, "structure.within_between", factor = "subject",
                        term = "x")
  expect_identical(written(sizes, "levels"), 20)
  expect_identical(detail(sizes, "singletons"), "min_count")
  expect_null(recover_difference(written(sizes, "levels"), written(between, "multi_row_levels")))
  expect_identical(detail(between, "multi_row_levels"), "secondary")
})

test_that("the rows of a pair of columns are a sample of their own", {
  # 14 classes of two rows, declared within schools, of which 2 have no
  # school: structure.label_incidence counts the 12 classes with a school,
  # and the 14 classes of the design sample minus them would give 2.
  data <- data.frame(y = seq_len(28) / 3, class = rep(sprintf("c%02d", 1:14), each = 2),
                     school = rep(c("S1", "S2", "S3", "S4", "S5", "S6", NA), each = 4))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "class", columns = list("class"), nested_in = "school", id_scope = "global",
         role = "cluster")
  ))
  found <- audit_both(data, "y ~ 1 + (1 | class)", declaration = declaration)
  internal <- finding_of(found$internal, "structure.label_incidence", first = "class",
                         second = "school")
  expect_identical(written(internal, "levels_first"), 12)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "class")
  shared <- finding_of(found$shareable, "structure.label_incidence", first = "class",
                       second = "school")
  expect_identical(written(sizes, "levels"), 14)
  expect_null(recover_difference(written(sizes, "levels"), written(shared, "levels_first")))
  expect_identical(detail(shared, "levels_first"), "secondary")
})

test_that("counts that equal a suppressed quantity are suppressed", {
  # 15 subjects of two rows, the second outcome of two missing: the 15
  # levels of the design sample exceed the 15 of the analysis sample by 0,
  # and cells of identifiability.residual_confounding counts the same levels.
  y <- seq_len(30) / 2
  y[c(2, 4)] <- NA
  data <- data.frame(y = y, x = seq_len(30) %% 4, subject = rep(sprintf("s%02d", 1:15), each = 2))
  found <- audit_both(data, "y ~ x + (1 | subject)", outcome_access = "T1", reason = "Sizes.")
  internal <- finding_of(found$internal, "identifiability.residual_confounding",
                         factor = "subject", term = "1 | subject")
  expect_identical(written(internal, "cells"), 15)
  shared <- finding_of(found$shareable, "identifiability.residual_confounding",
                       factor = "subject", term = "1 | subject")
  expect_identical(detail(shared, "cells"), "secondary")
  expect_identical(detail(shared, "replicated_cells"), "secondary")
})

test_that("a count that resolves as non-person is not suppressed for an equal value", {
  # Ten pupils, the disclosure unit, in five schools of two, one pupil with
  # two rows and the outcome constant within school S1. The analysis sample
  # has 1 level of 'pupil' with two rows, which rule 2 suppresses, and the 1
  # constant school is a non-person count, which stays written with its
  # share, as its message shows.
  data <- data.frame(
    y = c(5, 5, 5, 1, 2, 3, 4, 6, 7, 8, 9),
    school = c("S1", "S1", "S1", "S2", "S2", "S3", "S3", "S4", "S4", "S5", "S5"),
    pupil = c("p01", "p01", "p02", "p03", "p04", "p05", "p06", "p07", "p08", "p09", "p10")
  )
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ))
  found <- audit_both(data, "y ~ 1 + (1 | school) + (1 | pupil)", declaration = declaration,
                      outcome_access = "T1", reason = "Constant levels.")
  shared <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(shared$statistics$constant_levels,
                   list(count_class = "non_person", kind = "count", value = 1))
  expect_identical(written(shared, "multi_row_levels"), 5)
  expect_match(shared$message$text, "within 1 of the 5 levels", fixed = TRUE)
})

test_that("nested parts of totals are suppressed whatever the order of the rules", {
  # 12 levels of 3 rows, a varying in 11 and taking all three of its levels
  # in 10: multi_row_levels 12, varying_levels 11 and informative_levels 10.
  a <- c(rep(c("a1", "a2", "a3"), 10), "a1", "a1", "a2", "a1", "a1", "a1")
  data <- data.frame(y = seq_along(a) / 3, a = a, g = rep(sprintf("g%02d", 1:12), each = 3))
  found <- audit_both(data, "y ~ a + (1 | g)")
  internal <- finding_of(found$internal, "structure.within_between", factor = "g", term = "a")
  expect_identical(c(written(internal, "multi_row_levels"), written(internal, "varying_levels"),
                     written(internal, "informative_levels")), c(12, 11, 10))
  shared <- finding_of(found$shareable, "structure.within_between", factor = "g", term = "a")
  expect_identical(detail(shared, "varying_levels"), "secondary")
  expect_identical(detail(shared, "informative_levels"), "secondary")
})

test_that("an absent ratio whose denominator is suppressed is written as suppressed", {
  # Three subjects crossed with four items, with no candidate attribute, so
  # that changing_share is absent: its absence would show nothing more than
  # the suppressed shared_labels.
  data <- data.frame(y = seq_len(12) + 0.5, subject = rep(c("s1", "s2", "s3"), each = 4),
                     item = rep(c("i1", "i2", "i3", "i4"), 3))
  found <- audit_both(data, "y ~ 1 + (1 | subject) + (1 | item)")
  internal <- finding_of(found$internal, "structure.id_scope_evidence", first = "item",
                         second = "subject")
  expect_null(internal$statistics$changing_share)
  shared <- finding_of(found$shareable, "structure.id_scope_evidence", first = "item",
                       second = "subject")
  expect_identical(shared$statistics$changing_share$count_class, "person")
  expect_identical(detail(shared, "changing_share"), "ratio")
  expect_null(shared$statistics$changing_labels)
})

test_that("the dominance rule is written as a boolean without the share", {
  # 12 subjects, two of which hold 100 of the 110 rows.
  sizes <- c(50, 50, rep(1, 10))
  data <- data.frame(y = seq_len(110) / 9, subject = rep(sprintf("s%02d", 1:12), sizes))
  found <- audit_both(data, "y ~ 1 + (1 | subject)")
  shared <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  contributors <- shared$support$contributors
  expect_identical(sort(names(contributors)), c("basis", "distinct", "dominated"))
  expect_true(contributors$dominated)
  expect_identical(contributors$distinct$value, 12)
  expect_identical(detail(shared, "levels"), "dominance")
  expect_identical(detail(shared, "effective_size"), "dominance")
})

test_that("a T1 finding that rests on a suppressed outcome count is suppressed as a whole", {
  found <- same_samples()
  shared <- finding_of(found$shareable, "outcome.constant_clusters", factor = "subject")
  expect_identical(shared$status, list(availability = list(
    detail = "decision", reason = "privacy_suppressed", value = "not_available"
  )))
  expect_null(shared$message)
  expect_null(shared$statistics)
  expect_null(shared$support)
})

test_that("the values of outcome.separation that locate a cell are never written", {
  skip_if_not_installed("lpSolve")
  # Complete separation by 'x' with a balanced 'z', three kept columns.
  data <- data.frame(y = c(rep(0, 12), rep(1, 12)), x = rep(c(-2, 2), each = 12),
                     z = rep(c(-3, 3), 12))
  found <- audit_both(data, "y ~ x + z", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  internal <- finding_of(found$internal, "outcome.separation")
  expect_identical(written(internal, "verdict"), "complete")
  shared <- finding_of(found$shareable, "outcome.separation")
  expect_identical(written(shared, "verdict"), "complete")
  for (name in c("bounds", "columns_involved", "margin", "optimum")) {
    expect_identical(detail(shared, name), "internal_only")
  }
  # With two kept columns, the verdict would name a cell of one predictor.
  found <- audit_both(data, "y ~ x", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  shared <- finding_of(found$shareable, "outcome.separation")
  expect_identical(shared$status$availability$detail, "decision")
})

# --- Pseudonyms ---------------------------------------------------------------------------

# A check whose findings write labels, which registry 0.1.0 does not have.
labels_entry <- function() {
  list(
    id = "structure.flagged_levels", version = 1, tier = "T0", sample = "design",
    scope = "grouping_factor",
    statistics = list(
      flagged = list(kind = "labels"),
      flagged_levels = list(kind = "count", count_class = "person")
    ),
    decision = list(
      rules = list(list(finding = "detectable_inconsequential", statistics = list("flagged"),
                        message = "listed")),
      otherwise = list(finding = "consistent", message = "listed")
    ),
    messages = list(listed = list(
      template = "Flagged levels of '{factor}': {flagged}.",
      fallback = "Some levels of '{factor}' are flagged.",
      args = list(factor = list(source = "scope", name = "factor"),
                  flagged = list(source = "statistic", name = "flagged"))
    ))
  )
}

# An internal finding of that check, as the filter receives it after step 9.
labels_finding <- function(factor, labels, distinct = 50) {
  finding <- list(
    check = "structure.flagged_levels", check_version = 1, tier = "T0",
    scope = list(factor = factor), available = TRUE,
    status = list(assessability = list(value = "adequate"),
                  finding = list(value = "detectable_inconsequential"),
                  threshold_proximity = list(value = "clear"),
                  validation = list(value = "descriptive")),
    message = list(id = "listed", text = ""),
    statistics = list(flagged = list(kind = "labels"),
                      flagged_levels = list(kind = "count", count_class = "person")),
    values = list(flagged = labels, flagged_levels = 12),
    support = list(rows = 200, basis = "grouping_factors", distinct = distinct,
                   dominated = FALSE),
    items = list(), rows = seq_len(200), entry = labels_entry(), rule = 1L,
    label_factors = list(flagged = factor),
    suppressed = structure(character(0), names = character(0)),
    support_suppressed = structure(character(0), names = character(0)),
    whole = FALSE
  )
  privacy_minimum_rules(finding, 10)
}

test_that("pseudonyms follow the HMAC of the factor and the label, as privacy.md shows", {
  expect_identical(
    hmac_sha256(commitment_key_bytes(privacy_key), canonical_bytes(list("school", "A"), "data")),
    "40ad110dcd8fe9389548ba9f7881f4f4865ceb7d1fa9dc216b4b5dfae0a2d0bb"
  )
  findings <- list(labels_finding("school", c("B", "A")), labels_finding("school", c("C", "A")))
  pseudonyms <- privacy_pseudonyms(findings, privacy_key)
  expect_identical(pseudonyms$label, c("C", "A", "B"))
  expect_identical(pseudonyms$pseudonym, c("#1", "#2", "#3"))
  rendered <- lapply(findings, privacy_render, pseudonyms = pseudonyms)
  # The same label gets the same pseudonym in every finding, and the numbers
  # follow neither the labels nor the findings.
  expect_identical(rendered[[1L]]$values$flagged, c("#3", "#2"))
  expect_identical(rendered[[2L]]$values$flagged, c("#1", "#2"))
  expect_identical(rendered[[1L]]$message$text, "Flagged levels of 'school': '#3' and '#2'.")
  written <- document_finding(rendered[[1L]])
  expect_identical(written$statistics$flagged$value, list("#3", "#2"))
  expect_identical(shareable_finding_issues(written, "/findings/0", 10), list())
  # The same label of two factors gets two pseudonyms.
  findings <- list(labels_finding("school", "A"), labels_finding("class", "A"))
  pseudonyms <- privacy_pseudonyms(findings, privacy_key)
  expect_identical(nrow(pseudonyms), 2L)
  expect_setequal(pseudonyms$factor, c("school", "class"))
})

test_that("labels of a finding that fails the minimum-count rule get no pseudonym", {
  finding <- labels_finding("school", c("A", "B"), distinct = 4)
  expect_identical(finding$suppressed[["flagged"]], "min_count_rule")
  pseudonyms <- privacy_pseudonyms(list(finding), privacy_key)
  expect_identical(nrow(pseudonyms), 0L)
  rendered <- privacy_render(finding, pseudonyms)
  expect_identical(rendered$message$text, "Some levels of 'school' are flagged.")
  written <- document_finding(rendered)
  expect_null(written$statistics$flagged$value)
  expect_identical(written$statistics$flagged$availability$detail, "min_count_rule")
})

test_that("a check that writes labels must name their factor", {
  entry <- labels_entry()
  run <- new.env()
  run$cache <- new.env()
  element <- check_element(list(flagged = c("A", "B"), flagged_levels = 12), rules = TRUE)
  expect_error(assemble_finding(run, entry, list(factor = "school"), element),
               "gave no factor for the labels")
})
