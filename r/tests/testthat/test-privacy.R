# The privacy filter of shareable mode (docs/spec/privacy.md): each channel
# of disclosure by differencing that the filter closes, tried on inputs of
# these tests, the pseudonyms of labels, which registry 0.1.0 does not write,
# and the steps that the audit corpus cannot reach. Every shareable document
# that a test produces must pass validate_results().

privacy_key <- paste(sprintf("%02x", 0:31), collapse = "")

# Runs audit() at the time 0 in both modes with the example key, and checks
# that the shareable document is valid.
audit_both <- function(data, formula, ...) {
  run <- function(privacy) {
    with_audit_time(audit(data, formula, ..., privacy = privacy, key = privacy_key))
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
  results <- with_audit_time(audit(data, "y ~ x + (1 | subject)", key = privacy_key))
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
  # design sample: rows_raw - rows_kept would give rows_dropped. The two parts
  # name each other and both have the detail 'secondary', so that neither
  # shows which part is below k.
  data <- data.frame(y = seq_len(80) / 4, x = c(NA, NA, NA, seq_len(77) %% 7),
                     subject = rep(sprintf("s%02d", 1:40), each = 2))
  found <- audit_both(data, "y ~ x + (1 | subject)")
  internal <- finding_of(found$internal, "sample.raw_vs_analysis")
  expect_identical(written(internal, "rows_dropped"), 3)
  shared <- finding_of(found$shareable, "sample.raw_vs_analysis")
  expect_identical(detail(shared, "rows_dropped"), "secondary")
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

test_that("a product of written counts is hidden only beside the analysis sample", {
  # 15 subjects, the disclosure unit, meet both items once in one of five
  # sessions, the first of which holds one subject, so that the 5 levels of
  # 'session' are a person count below min_count, while the 10 combinations
  # divided by the 2 written levels of 'item' give them back. At T0 this
  # product is residual risk on design-structure values (privacy.md,
  # Guarantees), so the combinations are written.
  subject <- rep(sprintf("s%02d", 1:15), each = 2)
  session <- rep(c("k1", rep("k2", 3), rep("k3", 3), rep("k4", 4), rep("k5", 4)), each = 2)
  data <- data.frame(y = seq_along(subject) %% 4, subject = subject,
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
  expect_identical(c(written(shared, "levels_first"), written(shared, "combinations")), c(2, 10))
  expect_identical(detail(shared, "levels_second"), "min_count")
  # At T1, outcome.zero_shares shows the analysis sample, which holds every
  # row, so the design sample loses its levels beside it and rule 5 every
  # count of them, the combinations among them.
  found <- audit_both(data, "y ~ 1 + (1 | item) + (1 | session)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "item"),
                           "levels"), 2)
  shared <- finding_of(found$shareable, "structure.label_incidence", first = "item",
                       second = "session")
  for (name in c("levels_first", "levels_second", "combinations")) {
    expect_identical(detail(shared, name), "secondary")
  }
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
  # A part of a person total below k has the detail 'secondary'.
  expect_identical(detail(shared, "zeros"), "secondary")
  expect_identical(detail(shared, "zero_share"), "ratio")
  # 7 events among 40 rows: events_per_column times the written number of
  # kept columns would give back the minority events.
  data <- data.frame(y = c(rep(1, 7), rep(0, 33)), x = seq_len(40) / 8)
  found <- audit_both(data, "y ~ x", family = "binomial", outcome_access = "T1",
                      reason = "Events.")
  kept <- written(finding_of(found$shareable, "design.rank_deficiency"), "kept")
  expect_identical(kept, 2)
  shared <- finding_of(found$shareable, "outcome.minority_events")
  expect_identical(detail(shared, "events"), "secondary")
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
  expect_identical(detail(shared, "singletons"), "secondary")
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
  # 20 subjects, 3 of them with one row and 17 with three. The levels with
  # one row and with two or more are parts of the levels, and both have the
  # detail 'secondary', which does not show which part is below k.
  subject <- c(rep(sprintf("s%02d", 1:17), each = 3), sprintf("s%02d", 18:20))
  data <- data.frame(y = seq_along(subject) / 3, x = seq_along(subject) %% 5,
                     subject = subject)
  found <- audit_both(data, "y ~ x + (1 | subject)")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  between <- finding_of(found$shareable, "structure.within_between", factor = "subject",
                        term = "x")
  expect_identical(written(sizes, "levels"), 20)
  expect_identical(detail(sizes, "singletons"), "secondary")
  expect_null(recover_difference(written(sizes, "levels"), written(between, "multi_row_levels")))
  expect_identical(detail(between, "multi_row_levels"), "secondary")
  # 15 subjects of one row and 5 of six: the 5 levels with two or more rows
  # are below k, and the 15 levels with one row would give them back beside
  # the 20 levels.
  subject <- c(rep(sprintf("s%02d", 1:5), each = 6), sprintf("s%02d", 6:20))
  data <- data.frame(y = seq_along(subject) / 3, x = seq_along(subject) %% 5,
                     subject = subject)
  found <- audit_both(data, "y ~ x + (1 | subject)")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  between <- finding_of(found$shareable, "structure.within_between", factor = "subject",
                        term = "x")
  expect_identical(written(sizes, "levels"), 20)
  expect_identical(detail(sizes, "singletons"), "secondary")
  expect_identical(detail(between, "multi_row_levels"), "secondary")
})

test_that("two parts of a written total do not show which is below k", {
  # 20 subjects of three trials, the first 9 keys repeated identically and
  # the next 9 with another x: 18 duplicated keys, 9 identical and 9
  # conflicting. Details that showed both below k would bound each by
  # 18 - 9 from below and give back 9 and 9.
  keys <- data.frame(subject = rep(sprintf("s%02d", 1:20), each = 3), trial = rep(1:3, 20),
                     x = seq_len(60) %% 7 + 0.5)
  conflicting <- keys[10:18, ]
  conflicting$x <- conflicting$x + 1
  data <- rbind(keys, keys[1:9, ], conflicting)
  data$y <- seq_len(78) %% 11 + 0.5
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration)
  shared <- finding_of(found$shareable, "keys.duplicates")
  expect_identical(written(shared, "duplicated_keys"), 18)
  expect_identical(c(detail(shared, "identical_keys"), detail(shared, "conflicting_keys")),
                   c("secondary", "secondary"))
})

test_that("a count below k that no rule across findings suppresses keeps 'min_count'", {
  # 20 subjects of two rows, 4 of them with the assigned column z: the 4
  # units of the assignment's rows keep the detail 'min_count', which beside
  # the 20 written levels of the design sample shows that these exceed them
  # by k or more. The difference counts subjects without the assigned
  # column, a design-structure value that rule 1 compares with no losing
  # quantity below k (privacy.md, Guarantees).
  subject <- rep(sprintf("s%02d", 1:20), each = 2)
  z <- ifelse(subject <= "s04", c("a", "b")[(seq_along(subject) %/% 2) %% 2 + 1], NA)
  data <- data.frame(y = seq_along(subject) / 3, subject = subject, z = z,
                     stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), assignment = list(list(column = "z", unit = "subject", randomised = TRUE,
                            level = "between_unit")))
  found <- audit_both(data, "y ~ 1 + (1 | subject)", declaration = declaration)
  shared <- finding_of(found$shareable, "assignment.constant_within_unit", column = "z")
  expect_identical(detail(shared, "units"), "min_count")
  expect_identical(written(finding_of(found$shareable, "structure.cluster_sizes",
                                      factor = "subject"), "levels"), 20)
})

test_that("a count that measures no quantity is written whatever a suppressed quantity holds", {
  # 20 subjects, 2 of one row and 18 of three, with x constant within each:
  # the budget of 20 - 2 = 18 equals the 18 levels with two or more rows,
  # which rule 2 suppresses, and is written, since writing it shows nothing
  # that the levels and the consuming terms do not.
  sizes <- c(1, 1, rep(3, 18))
  subject <- rep(sprintf("s%02d", seq_along(sizes)), sizes)
  data <- data.frame(y = (seq_along(subject) * 5) %% 13 + 0.25,
                     x = rep(seq_along(sizes) %% 3 + 0.5, sizes), subject = subject)
  found <- audit_both(data, "y ~ x + (1 | subject)")
  budget <- finding_of(found$shareable, "identifiability.df_budget", factor = "subject")
  expect_identical(c(written(budget, "levels"), written(budget, "budget")), c(20, 18))
  expect_identical(detail(finding_of(found$shareable, "structure.within_between",
                                     factor = "subject", term = "x"), "multi_row_levels"),
                   "secondary")
})

test_that("the rows and levels of the analysis sample do not show that a level has one row", {
  # 12 subjects in the analysis sample, 9 of two rows and 3 of one, and 10
  # subjects of four rows without an outcome: 21 analysed rows are fewer
  # than twice the 12 levels, so at least 3 subjects have one analysed row
  # and the smallest analysed size is 1, an outcome-derived value.
  subject <- c(rep(sprintf("s%02d", 1:9), each = 2), sprintf("t%02d", 1:3),
               rep(sprintf("u%02d", 1:10), each = 4))
  data <- data.frame(count = c(seq_len(21) %% 4, rep(NA, 40)),
                     x = seq_along(subject) %% 7 + 0.5, subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ))
  # With the basis grouping_factors and with the basis disclosure_unit, the
  # contributors measure the levels of subject and are suppressed with them.
  for (declared in list(NULL, declaration)) {
    found <- audit_both(data, "count ~ x + (1 | subject)", declaration = declared,
                        family = "poisson", outcome_access = "T1", reason = "Zeros.")
    shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
    expect_identical(written(shares, "rows"), 21)
    expect_identical(detail(shares, "levels"), "secondary")
    expect_identical(shares$support$contributors$distinct$availability$detail, "secondary")
  }
  # In the design sample the same bound concerns design-structure values,
  # which the filter leaves as residual risk (privacy.md, Guarantees): the
  # 21 rows of a T0 run are written beside its 12 levels.
  found <- audit_both(data[seq_len(21), ], "count ~ x + (1 | subject)")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(c(written(sizes, "rows"), written(sizes, "levels")), c(21, 12))
})

test_that("the rows and levels of the design sample do not bound what it loses", {
  # 20 subjects of two rows, 10 of them with a constant outcome, 10 subjects
  # of one row with an outcome and 10 of one row without one. The 20 levels
  # with two rows of the analysis sample, which outcome.constant_clusters
  # writes, equal the design sample's, which beside its 60 rows and 40
  # levels would show that no subject lost its second outcome, so rule 5
  # hides every count of the levels of subject in the design sample.
  y <- c(rep(c(3, 3), 10), rep(c(1, 2), 10), (1:10) / 7, rep(NA, 10))
  data <- data.frame(y = y, x = seq_along(y) %% 7 + 0.5,
                     subject = c(rep(sprintf("s%02d", 1:20), each = 2), sprintf("t%02d", 1:20)))
  found <- audit_both(data, "y ~ x + (1 | subject)", outcome_access = "T1", reason = "Sizes.")
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "subject")
  expect_identical(written(constant, "multi_row_levels"), 20)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "rows"), 60)
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "singletons"), "secondary")
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

test_that("nested samples other than the design sample are compared with each other", {
  # 60 subjects of three rows, two of them assigned. z1 is missing for
  # subjects 1 to 20 and z2 for subjects 1 to 15, so the units of z2, 45,
  # minus those of z1, 40, would give back 5 subjects.
  subject <- rep(sprintf("s%02d", 1:60), each = 3)
  z1 <- rep(rep(c("a", "b"), 30), each = 3)
  z2 <- rep(rep(c("c", "c", "d", "d"), 15), each = 3)
  z1[subject <= "s20"] <- NA
  z2[subject <= "s15"] <- NA
  data <- data.frame(y = seq_along(subject) %% 7, x = seq_along(subject) %% 5,
                     subject = subject, z1 = z1, z2 = z2)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), assignment = list(
    list(column = "z1", unit = "subject", randomised = TRUE, level = "between_unit"),
    list(column = "z2", unit = "subject", randomised = TRUE, level = "between_unit")
  ))
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration)
  first <- finding_of(found$shareable, "assignment.design_df", column = "z1")
  second <- finding_of(found$shareable, "assignment.design_df", column = "z2")
  expect_identical(written(first, "units"), 40)
  expect_identical(detail(second, "units"), "secondary")
  # The analysis sample within the rows of an assignment: the outcome is
  # missing for subjects 1 to 20, so the 45 units of z2 minus the 40 levels
  # of the analysis sample would give back 5 randomised subjects without an
  # outcome.
  data$y[subject <= "s20"] <- NA
  declaration$assignment <- declaration$assignment[2L]
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Loss.")
  zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  assigned <- finding_of(found$shareable, "assignment.design_df", column = "z2")
  expect_identical(written(zeros, "levels"), 40)
  expect_identical(detail(assigned, "units"), "secondary")
  # Rows of an assignment equal to the analysis sample count as the analysis
  # sample, against which the design sample loses its value: z2 and the
  # outcome are missing for subjects 1 to 5.
  data$y <- seq_along(subject) %% 7
  data$z2 <- rep(rep(c("c", "c", "d", "d"), 15), each = 3)
  data$y[subject <= "s05"] <- NA
  data$z2[subject <= "s05"] <- NA
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Loss.")
  assigned <- finding_of(found$shareable, "assignment.design_df", column = "z2")
  budget <- finding_of(found$shareable, "identifiability.df_budget", factor = "subject")
  expect_identical(written(assigned, "units"), 55)
  expect_identical(detail(budget, "levels"), "secondary")
})

test_that("the contributors of the basis grouping_factors measure the levels of a factor", {
  # Without a disclosure unit, the contributors are the levels of the factor
  # with the fewest levels: 'g', with 20 levels in the design sample, where
  # 'h' has 40. 'g' keeps 15 levels in the analysis sample, so its 20 levels
  # in the design sample, which the contributors would give back, are
  # suppressed. The 10 analysed levels of 'h', three of one row among 17
  # rows, are hidden by rule 3, and with them its 40 levels in the design
  # sample.
  n <- 80
  counts <- rep(c(0, 1, 3, 2), 20)
  counts[-c(1:15, 21, 23)] <- NA
  data <- data.frame(count = counts, x = seq_len(n) %% 9,
                     g = sprintf("g%02d", (seq_len(n) - 1) %% 20 + 1),
                     h = sprintf("h%02d", (seq_len(n) + 1) %/% 2))
  found <- audit_both(data, "count ~ x + (1 | g) + (1 | h)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "g")
  other <- finding_of(found$shareable, "structure.cluster_sizes", factor = "h")
  expect_identical(sizes$statistics$levels$availability$detail, "secondary")
  expect_identical(detail(other, "levels"), "secondary")
  expect_identical(sizes$support$contributors$distinct$availability$detail, "secondary")
})

test_that("crossed columns do not give back the combinations that lack an outcome", {
  # 12 levels of g crossed with 12 of h, two pupils in each combination but
  # one, so that g and h count non-persons and their combinations persons.
  # The outcome is missing in the 10 rows of 5 combinations. The design
  # sample's levels of g and h, compared beside the analysis sample whatever
  # their class, lose their value, and its combinations, the product of the
  # two, too. The analysis sample's levels of g and h, which outcome.zero_shares
  # writes, bound the design sample's from below, and the firing of rule 1
  # bounds their product from above, so the analysis sample loses its count
  # of combinations too: 12 x 12 is the only product within k of its 139.
  cells <- expand.grid(g = sprintf("g%02d", 1:12), h = sprintf("h%02d", 1:12),
                       stringsAsFactors = FALSE)
  crossed <- function(rows) {
    data <- cells[rows, ]
    data$pupil <- sprintf("p%03d", seq_len(nrow(data)))
    data$count <- seq_len(nrow(data)) %% 4
    data$x <- seq_len(nrow(data)) %% 7
    lost <- paste(cells$g, cells$h)[c(10, 30, 50, 70, 90)]
    data$count[paste(data$g, data$h) %in% lost] <- NA
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "pupil", columns = list("pupil"), role = "participant")
    ))
    audit_both(data, "count ~ x + (1 | g) + (1 | h) + (1 | g:h)", declaration = declaration,
               family = "poisson", outcome_access = "T1", reason = "Zeros.")$shareable
  }
  # With every combination of two rows, the 278 analysed rows are twice the
  # 139 analysed combinations, so rule 3 leaves them, and the clause on
  # crossed columns alone hides them.
  pairs <- rep(seq_len(nrow(cells)), each = 2)
  for (rows in list(pairs[-1L], pairs)) {
    shareable <- crossed(rows)
    incidence <- finding_of(shareable, "structure.label_incidence", first = "g", second = "h")
    expect_identical(written(incidence, "relation"), "crossed")
    for (name in c("levels_first", "levels_second", "combinations")) {
      expect_identical(detail(incidence, name), "secondary")
    }
    expect_identical(written(finding_of(shareable, "outcome.zero_shares", factor = "g"), "levels"),
                     12)
    expect_identical(detail(finding_of(shareable, "outcome.zero_shares", factor = "g:h"), "levels"),
                     "secondary")
  }
})

test_that("the labels that repeat do not give back the labels that occur once", {
  # 25 class labels, 20 of which occur in two of 12 schools. The labels in
  # several schools, 20, written beside the 25 labels of 'class', would give
  # back the 5 that occur in one school, which part_of suppresses in both
  # checks that count them.
  combinations <- rbind(
    data.frame(class = sprintf("c%02d", 1:20), school = sprintf("S%02d", (0:19 %% 12) + 1)),
    data.frame(class = sprintf("c%02d", 1:20), school = sprintf("S%02d", ((5:24) %% 12) + 1)),
    data.frame(class = sprintf("c%02d", 21:25), school = sprintf("S%02d", 1:5))
  )
  data <- combinations[rep(seq_len(nrow(combinations)), each = 2), ]
  data$tx <- ave(seq_len(nrow(data)), data$class, data$school, FUN = function(i) i[1L] %% 3)
  data$stype <- as.integer(substr(data$school, 2L, 3L)) %% 2
  data$y <- seq_len(nrow(data)) %% 7
  data$x <- seq_len(nrow(data)) %% 5
  found <- audit_both(data, "y ~ x + tx + stype + (1 | school) + (1 | class)")
  evidence <- finding_of(found$shareable, "structure.id_scope_evidence", first = "class",
                         second = "school")
  incidence <- finding_of(found$shareable, "structure.label_incidence", first = "class",
                          second = "school")
  expect_identical(written(evidence, "levels"), 25)
  expect_identical(written(incidence, "levels_first"), 25)
  expect_identical(detail(incidence, "first_in_several"), "secondary")
  expect_identical(detail(evidence, "shared_labels"), "secondary")
})

test_that("counts that equal a suppressed quantity are suppressed", {
  # 15 subjects of two rows, the second outcome of two missing: the 15
  # levels of the design sample exceed the 15 of the analysis sample by 0,
  # and cells of identifiability.residual_confounding counts the same levels.
  # outcome.zero_shares of the Poisson outcome shows the analysis sample.
  y <- seq_len(30) %% 4
  y[c(2, 4)] <- NA
  data <- data.frame(y = y, x = seq_len(30) %% 4, subject = rep(sprintf("s%02d", 1:15), each = 2))
  found <- audit_both(data, "y ~ x + (1 | subject)", family = "poisson", outcome_access = "T1",
                      reason = "Sizes.")
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
  separation <- function(data, formula) {
    found <- audit_both(data, formula, family = "binomial", outcome_access = "T2",
                        reason = "Separation.", exploratory = TRUE)
    lapply(found, finding_of, check = "outcome.separation")
  }
  # Complete separation by 'x' with 'z', three kept columns whose values no
  # two rows share.
  data <- data.frame(y = c(rep(0, 12), rep(1, 12)), x = 1:24,
                     z = rep(c(-3, 3, -1, 1), 6))
  found <- separation(data, "y ~ x + z")
  expect_identical(written(found$internal, "verdict"), "complete")
  expect_identical(written(found$shareable, "verdict"), "complete")
  for (name in c("bounds", "columns_involved", "margin", "optimum")) {
    expect_identical(detail(found$shareable, name), "internal_only")
  }
  # With two kept columns, the verdict would name a cell of one predictor.
  expect_identical(separation(data, "y ~ x")$shareable$status$availability$detail, "decision")
  # With two factors of two levels, complete shows that each combination
  # holds one class, so the finding is suppressed whatever its verdict.
  data$x <- rep(c(-2, 2), each = 12)
  found <- separation(data, "y ~ x + z")
  expect_identical(written(found$internal, "verdict"), "complete")
  expect_identical(found$shareable$status$availability$detail, "decision")
  # A column that varies only in rows without an outcome leaves the analysis
  # sample two kept columns, on which the verdict would name a cell of 'x'.
  data <- data.frame(y = c(rep(0, 12), rep(1, 12), NA, NA), x = c(1:24, 7.5, 18.5),
                     z = c(rep(0, 24), 1, 1))
  found <- separation(data, "y ~ x + z")
  expect_identical(written(found$internal, "verdict"), "complete")
  expect_identical(found$shareable$status$availability$detail, "decision")
})

test_that("two rows share the values of the kept columns of outcome.separation", {
  expect_false(separation_shared_values(cbind(1, c(1, 2, 3))))
  expect_true(separation_shared_values(cbind(1, c(1, 2, 1))))
  # -0 and 0 are the same value.
  expect_true(separation_shared_values(cbind(1, c(0, 2, -0), c(5, 6, 5))))
  expect_false(separation_shared_values(cbind(1, c(0, 2, 0), c(5, 6, 4))))
  expect_false(separation_shared_values(cbind(1, 3)))
})

test_that("the software of a document does not show that an outcome class is empty", {
  skip_if_not_installed("lpSolve")
  # With 0 or 3 events in 200 rows, the finding of outcome.separation is
  # suppressed as a whole, and the solver is named in both documents.
  documents <- lapply(c(0, 3), function(events) {
    data <- data.frame(y = c(rep(1, events), rep(0, 200 - events)), x = seq_len(200) %% 7,
                       g = rep(sprintf("g%02d", 1:20), each = 10))
    audit_both(data, "y ~ x + (1 | g)", family = "binomial", outcome_access = "T2",
               reason = "Separation.", exploratory = TRUE)$shareable
  })
  for (document in documents) {
    expect_identical(finding_of(document, "outcome.separation")$status$availability$detail,
                     "decision")
  }
  expect_identical(documents[[1L]]$software, documents[[2L]]$software)
  expect_identical(names(documents[[1L]]$software$packages), "lpSolve")
})

test_that("binomial events and non-events beside the rows do not give back small classes of rows", {
  skip_if_not_installed("lpSolve")
  # The rows with k = 0, with k = n and with both classes are the rows minus
  # events, the rows minus non_events and their overlap.
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")))
  run <- function(k) {
    local_seed(3)
    data <- data.frame(k = k, n = 5, x = round(rnorm(40), 3), z = round(rnorm(40), 3))
    found <- audit_both(data, "k ~ x + z", declaration = declaration, outcome_access = "T2",
                        reason = "Separation.", exploratory = TRUE)
    list(internal = finding_of(found$internal, "outcome.separation"),
         shareable = finding_of(found$shareable, "outcome.separation"))
  }
  for (k in list(c(rep(0, 3), rep(5, 12), rep(2, 25)), c(rep(0, 12), rep(5, 3), rep(2, 25)),
                 c(rep(0, 15), rep(5, 25)))) {
    found <- run(k)
    expect_identical(c(written(found$internal, "events"), written(found$internal, "non_events")),
                     as.double(c(sum(k > 0), sum(k < 5))))
    expect_identical(found$shareable$status$availability$detail, "decision")
  }
  found <- run(c(rep(0, 12), rep(5, 12), rep(2, 16)))
  expect_identical(found$shareable$status$availability$value, "available")
  expect_identical(written(found$shareable, "verdict"), written(found$internal, "verdict"))
  expect_identical(c(written(found$shareable, "events"), written(found$shareable, "non_events")),
                   c(28, 28))
})

test_that("outcome.separation does not show that missing outcomes emptied a cell", {
  skip_if_not_installed("lpSolve")
  # The outcome is missing in the 3 rows with smoker 's2', which leaves 3
  # kept columns in the analysis sample against 4 in the design sample, or
  # in 3 rows with smoker 's1', which leaves 4 in both.
  local_seed(5)
  data <- data.frame(y = rbinom(40, 1, 0.5), x1 = round(rnorm(40), 3), x2 = round(rnorm(40), 3),
                     smoker = c(rep("s2", 3), rep("s1", 37)))
  shared <- lapply(list(1:3, c(4, 25, 30)), function(missing) {
    data$y[missing] <- NA
    found <- audit_both(data, "y ~ x1 + x2 + smoker", family = "binomial",
                        outcome_access = "T2", reason = "Separation.", exploratory = TRUE)
    expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "kept"), 4)
    internal <- finding_of(found$internal, "outcome.separation")
    expect_identical(written(internal, "columns"), if (missing[1L] == 1) 3 else 4)
    finding_of(found$shareable, "outcome.separation")
  })
  for (finding in shared) {
    expect_identical(detail(finding, "columns"), "internal_only")
    expect_identical(finding$status$availability$value, "available")
  }
  expect_identical(shared[[1L]]$status, shared[[2L]]$status)
})

test_that("outcome.separation with the levels of one factor is suppressed whatever its verdict", {
  skip_if_not_installed("lpSolve")
  # Three arms of 40 rows, with events exactly in arm 'b': complete would
  # show that each arm holds one class, and events which.
  data <- data.frame(arm = rep(c("a", "b", "c"), each = 40), g = rep(sprintf("g%02d", 1:20), 6))
  data$y <- as.numeric(data$arm == "b")
  found <- audit_both(data, "y ~ arm + (1 | g)", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "kept"), 3)
  expect_identical(written(finding_of(found$internal, "outcome.separation"), "verdict"), "complete")
  shared <- finding_of(found$shareable, "outcome.separation")
  expect_identical(shared$status$availability$detail, "decision")
  # Without separation, the finding is suppressed alike.
  data$y <- rep(c(0, 1), 60)
  found <- audit_both(data, "y ~ arm + (1 | g)", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  expect_identical(written(finding_of(found$internal, "outcome.separation"), "verdict"), "none")
  expect_identical(finding_of(found$shareable, "outcome.separation")$status$availability$detail,
                   "decision")
})

test_that("the smallest eigenvalue does not give back the rows without an outcome", {
  # 20 subjects of 4 rows with a condition balanced within subjects: the
  # eigenvalue is 1 - sqrt((J - 1) / (N - 2)), which gives back N. At T0
  # this is residual risk on the rows of the design sample, so it is
  # written. At T1, outcome.zero_shares writes the 80 rows of the analysis
  # sample, beside which rule 1 hides the design sample's and rule 5 the
  # eigenvalue, which would show that no outcome is missing.
  data <- data.frame(y = seq_len(80) %% 9, condition = rep(c("a", "b"), 40),
                     subject = rep(sprintf("s%02d", 1:20), each = 4))
  found <- audit_both(data, "y ~ condition + (1 | subject)")
  internal <- finding_of(found$internal, "identifiability.gram_rank")
  expect_equal(written(internal, "smallest_eigenvalue"), 1 - sqrt(19 / 78), tolerance = 1e-12)
  shared <- finding_of(found$shareable, "identifiability.gram_rank")
  expect_equal(written(shared, "smallest_eigenvalue"), 1 - sqrt(19 / 78), tolerance = 1e-12)
  found <- audit_both(data, "y ~ condition + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "subject"),
                           "rows"), 80)
  shared <- finding_of(found$shareable, "identifiability.gram_rank")
  expect_identical(detail(shared, "smallest_eigenvalue"), "secondary")
})

test_that("a quartile that is the minimum is suppressed by the quantile rule whatever its value", {
  # Three schools of pupils, the disclosure unit: the lower quartile of 3
  # sizes is the smallest, and its detail must not show whether it is
  # below min_count.
  details <- vapply(list(c(6, 40, 54), c(12, 40, 48)), function(sizes) {
    school <- rep(c("A", "B", "C"), sizes)
    data <- data.frame(y = seq_along(school) %% 5, school = school,
                       pupil = sprintf("p%03d", seq_along(school)))
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "school", columns = list("school"), role = "cluster"),
      list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ))
    found <- audit_both(data, "y ~ 1 + (1 | school)", declaration = declaration)
    sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
    vapply(c("lower_quartile", "median", "upper_quartile"), detail, "", finding = sizes)
  }, character(3))
  expect_true(all(details == "quantile"))
})

test_that("levels that an assignment removes from a person sample are compared", {
  # 29 schools of 4 pupils and S30 of 1 pupil, whose rows alone lack 'arm':
  # the schools are person counts in the design sample and not in the rows
  # of the assignment, and 30 levels minus 29 units would count S30.
  school <- c(rep(sprintf("S%02d", 1:29), each = 8), rep("S30", 2))
  pupil <- c(rep(sprintf("P%03d", 1:116), each = 2), rep("P117", 2))
  arm <- ifelse(seq_along(school) %% 16 < 8, "a", "b")
  arm[school == "S30"] <- NA
  data <- data.frame(y = seq_along(school) %% 7, school = school, pupil = pupil, arm = arm)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ), assignment = list(list(column = "arm", unit = "school", randomised = TRUE,
                            level = "between_unit")))
  found <- audit_both(data, "y ~ 1 + (1 | school)", declaration = declaration)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
  assigned <- finding_of(found$shareable, "assignment.constant_within_unit", column = "arm")
  expect_identical(written(sizes, "levels"), 30)
  expect_identical(finding_of(found$internal, "assignment.constant_within_unit",
                              column = "arm")$statistics$units$count_class, "non_person")
  expect_null(recover_difference(written(sizes, "levels"), written(assigned, "units")))
  expect_identical(detail(assigned, "units"), "secondary")
})

test_that("rows without a key value do not give back the rows that a predictor removes", {
  # 30 subjects of 10 trials, with 'subject' missing in rows 1 to 15 and
  # 'x' in rows 100 and 200: 17 rows leave the design sample, 15 of them
  # without a key value.
  data <- data.frame(y = seq_len(300) %% 11, x = seq_len(300) %% 13,
                     subject = rep(sprintf("s%02d", 1:30), each = 10), trial = rep(1:10, 30))
  data$subject[1:15] <- NA
  data$x[c(100, 200)] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration)
  expect_identical(written(finding_of(found$internal, "keys.duplicates"), "missing_key_rows"), 15)
  keys <- finding_of(found$shareable, "keys.duplicates")
  dropped <- finding_of(found$shareable, "sample.raw_vs_analysis")
  expect_identical(written(dropped, "rows_dropped"), 17)
  expect_null(recover_difference(written(dropped, "rows_dropped"),
                                 written(keys, "missing_key_rows")))
  expect_identical(detail(keys, "missing_key_rows"), "secondary")
  # With 12 rows that only 'x' removes, the count stays.
  data$x[c(100, 200)] <- 1
  data$x[seq(20, 240, by = 20)] <- NA
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration)
  expect_identical(written(finding_of(found$shareable, "keys.duplicates"), "missing_key_rows"),
                   15)
})

# --- The analysis sample, shown or not, and the samples beside it ----------------------

# The values of a shareable document that a reader may not use against an
# outcome-derived value, with the T0 statuses, messages, categories,
# booleans and names that privacy.md (Guarantees) accepts to show left out:
# for each finding, its availability, its counts, ratios and reals with their
# details and its support, and the whole of a finding of a T1 or T2 check.
strict_values <- function(document) {
  lapply(document$findings, function(finding) {
    if (!identical(finding$tier, "T0")) {
      return(finding)
    }
    statistics <- Filter(function(s) s$kind %in% c("count", "ratio", "real", "reals"),
                         finding$statistics)
    list(check = finding$check, scope = finding$scope,
         availability = finding$status$availability,
         statistics = lapply(statistics, function(s) list(s$value, s$availability$detail)),
         support = finding$support)
  })
}

# Two shareable documents of tables that differ only in a hidden
# outcome-derived value must read alike.
expect_same_reading <- function(first, second) {
  expect_identical(strict_values(first), strict_values(second))
}

test_that("a gaussian T1 run that shows no value of the analysis sample writes the T0 values", {
  # 10 subjects of one row and 30 of two, the trial of subjects s01 to s10
  # missing and both outcomes of s01 to s06 missing. Without a constant
  # subject, outcome.constant_clusters rests on a suppressed count and is
  # suppressed as a whole, so the document shows no value of the analysis
  # sample and writes the reals and counts of the design sample as a T0
  # document does. missing_key_rows, 20, is written: the 12 rows that the
  # analysis sample leaves out, 8 fewer, are not compared with it.
  subject <- c(rep(sprintf("s%02d", 1:30), each = 2), sprintf("t%02d", 1:10))
  trial <- c(rep(1:2, 30), rep(1, 10))
  trial[subject <= "s10"] <- NA
  y <- seq_along(subject) / 3 + rep(c(0, 0.5), 35)
  y[subject <= "s06"] <- NA
  data <- data.frame(y = y, x = seq_along(subject) %% 4 + 0.5, subject = subject, trial = trial)
  declaration <- list(vocabulary = "0.1.0", observation = list(key = list("subject", "trial")))
  run <- function(data) {
    audit_both(data, "y ~ x + (1 | subject)", declaration = declaration, outcome_access = "T1",
               reason = "Constant levels.")$shareable
  }
  shareable <- run(data)
  expect_identical(finding_of(shareable, "outcome.constant_clusters",
                              factor = "subject")$status$availability$detail, "decision")
  sizes <- finding_of(shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(c(written(sizes, "rows"), written(sizes, "levels")), c(70, 40))
  expect_false(is.null(written(sizes, "effective_size")))
  within <- finding_of(shareable, "structure.within_between", factor = "subject", term = "x")
  expect_false(is.null(written(within, "within_share")))
  expect_false(is.null(written(finding_of(shareable, "identifiability.gram_rank"),
                               "smallest_eigenvalue")))
  expect_identical(written(finding_of(shareable, "keys.duplicates"), "missing_key_rows"), 20)
  # With 10 constant subjects outcome.constant_clusters is written, the
  # analysis sample is shown and its 34 levels beside the design sample's 40
  # hide these, the reals that read them and missing_key_rows.
  data$y[subject %in% sprintf("s%02d", 11:20)] <- rep(seq(11, 20), each = 2)
  shareable <- run(data)
  constant <- finding_of(shareable, "outcome.constant_clusters", factor = "subject")
  expect_identical(written(constant, "constant_levels"), 10)
  sizes <- finding_of(shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "rows"), 70)
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "effective_size"), "secondary")
  within <- finding_of(shareable, "structure.within_between", factor = "subject", term = "x")
  expect_identical(detail(within, "within_share"), "secondary")
  expect_identical(detail(finding_of(shareable, "identifiability.gram_rank"),
                          "smallest_eigenvalue"), "secondary")
  expect_identical(detail(finding_of(shareable, "keys.duplicates"), "missing_key_rows"),
                   "secondary")
})

test_that("a sample that loses a quantity beside the analysis sample is compared with no other", {
  # 50 subjects of four rows and 10 of one row: the 10 rows lack the
  # covariate, or 9 lack it and 1 lacks the outcome. The design sample
  # loses its rows beside the 200 analysed rows in both tables, and were
  # the table compared with it, its 210 rows would be written beside a
  # design sample of 200 rows and hidden beside one of 201.
  chain <- function(y_missing) {
    count <- c(rep(c(0, 1, 2, 3), 50), rep(1, 10))
    x <- c(seq_len(200) %% 7 + 0.5, rep(NA, 10))
    if (y_missing) {
      x[201] <- 0.5
      count[201] <- NA
    }
    data <- data.frame(count = count, x = x,
                       g = c(rep(sprintf("g%02d", 1:50), each = 4), sprintf("h%02d", 1:10)))
    audit_both(data, "count ~ x + (1 | g)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.")$shareable
  }
  pair <- lapply(c(FALSE, TRUE), chain)
  expect_same_reading(pair[[1L]], pair[[2L]])
  expect_identical(written(finding_of(pair[[1L]], "sample.raw_vs_analysis"), "rows_raw"), 210)
  expect_identical(detail(finding_of(pair[[1L]], "structure.cluster_sizes", factor = "g"), "rows"),
                   "secondary")
  # Rule 4 likewise leaves out the design sample, which loses its rows: 10
  # rows without a subject and 10 without the covariate, or 9 and one
  # without an outcome. missing_key_rows, 10, would be written beside a
  # design sample of 200 rows and hidden beside one of 201.
  keyed <- function(y_missing) {
    subject <- c(rep(sprintf("s%02d", 1:50), each = 4), rep(NA, 10), sprintf("u%02d", 1:10))
    x <- c(seq_len(210) %% 7 + 0.5, rep(NA, 10))
    count <- c(rep(c(0, 1, 2, 3), 50), rep(1, 20))
    if (y_missing) {
      x[211] <- 0.5
      count[211] <- NA
    }
    data <- data.frame(count = count, x = x, subject = subject,
                       trial = c(rep(1:4, 50), 1:10, rep(1, 10)))
    audit_both(data, "count ~ x + (1 | subject)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.", declaration = list(
                 vocabulary = "0.1.0", observation = list(key = list("subject", "trial"))
               ))$shareable
  }
  pair <- lapply(c(FALSE, TRUE), keyed)
  expect_same_reading(pair[[1L]], pair[[2L]])
  expect_identical(written(finding_of(pair[[1L]], "keys.duplicates"), "missing_key_rows"), 10)
})

test_that("contributors, parts and combined items do not bound the levels that a sample loses", {
  # 40 levels of f crossed with 42 of g over 168 rows with an outcome, and 20
  # rows without one in 10 new levels of f, in 9 new levels of g of two rows
  # and 2 rows of existing levels, or in 8 new levels and 4 rows. The
  # contributors, the 50 levels of f, would be written beside 51 levels of g
  # and hidden beside 50, so rule 5 hides them with the levels of g.
  contributors <- function(new_g) {
    r <- 1:168
    extra <- c(rep(sprintf("G%02d", 42 + seq_len(new_g)), each = 2),
               sprintf("G%02d", seq_len(20 - 2 * new_g)))
    data <- data.frame(count = c(r %% 4, rep(NA, 20)), x = c(r %% 7 + 0.5, (1:20) / 3),
                       f = c(sprintf("F%02d", (r - 1) %% 40 + 1),
                             rep(sprintf("F%02d", 41:50), each = 2)),
                       g = c(sprintf("G%02d", (r - 1) %% 42 + 1), extra))
    audit_both(data, "count ~ x + (1 | f) + (1 | g)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.")$shareable
  }
  pair <- lapply(c(9, 8), contributors)
  expect_same_reading(pair[[1L]], pair[[2L]])
  sizes <- finding_of(pair[[1L]], "structure.cluster_sizes", factor = "f")
  expect_identical(sizes$support$contributors$distinct$availability$detail, "secondary")
  # 49 subjects of two rows: 30 keep both outcomes, 10 one and 9 none. A
  # part of the hidden levels written beside the 40 analysed subjects, such
  # as informative_levels 39, would show 49 or more of them.
  subject <- rep(sprintf("s%02d", 1:49), each = 2)
  x <- rep(c(0.5, 1.5), 49)
  x[subject %in% sprintf("s%02d", 40:49)] <- 0.5
  data <- data.frame(count = c(rep(c(2, 2), 15), rep(c(1, 3), 15), rep(c(4, NA), 10), rep(NA, 18)),
                     x = x, subject = subject)
  found <- audit_both(data, "count ~ x + (1 + x | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "subject"),
                           "levels"), 40)
  dimension <- finding_of(found$shareable, "identifiability.levels_vs_dimension",
                          factor = "subject")
  expect_identical(detail(dimension, "informative_levels"), "secondary")
  within <- finding_of(found$shareable, "structure.within_between", factor = "subject", term = "x")
  for (name in c("multi_row_levels", "varying_levels", "informative_levels")) {
    expect_identical(detail(within, name), "secondary")
  }
  # 25 crossed components of two levels of f and two of g, the outcome of 9
  # levels of g missing: twice the components would bound the hidden levels
  # of g by 50 beside the 41 analysed.
  rows <- expand.grid(rep = 1:2, b = 1:2, a = 1:2, c = 1:25)
  data <- data.frame(f = sprintf("F%02d_%d", rows$c, rows$a),
                     g = sprintf("G%02d_%d", rows$c, rows$b))
  data$count <- seq_len(nrow(data)) %% 4
  data$count[data$g %in% sprintf("G%02d_2", 1:9)] <- NA
  data$x <- seq_len(nrow(data)) %% 7 + 0.5
  found <- audit_both(data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "g"),
                           "levels"), 41)
  expect_identical(detail(finding_of(found$shareable, "structure.connectivity"), "components"),
                   "secondary")
})

test_that("the counts of the design sample do not bound the levels that it loses", {
  # 50 levels of f in the design sample, 10 of one row without an outcome,
  # so that the rows and the levels lost are equal: the 10 singletons of f
  # beside them would show that no analysed level of f has one row.
  r <- 1:168
  data <- data.frame(count = c(r %% 4, rep(NA, 10)), x = c(r %% 7 + 0.5, (1:10) / 3),
                     f = c(sprintf("F%02d", (r - 1) %% 40 + 1), sprintf("F%02d", 41:50)),
                     g = c(sprintf("G%02d", (r - 1) %% 42 + 1), sprintf("G%02d", 43:51), "G01"))
  found <- audit_both(data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "f")
  expect_identical(written(sizes, "rows"), 178)
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "singletons"), "secondary")
  # 20 subjects of one row and 30 of two, the second outcome of 10 missing:
  # 80 rows and 20 singletons would bound the levels by 50, the 50 analysed
  # subjects, and show that no subject lost every outcome.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("s%02d", 1:30), each = 2))
  count <- seq_along(subject) %% 4
  count[21 + 2 * (0:9) + 1] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "subject"),
                           "levels"), 50)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "rows"), 80)
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "singletons"), "secondary")
})

test_that("the levels of a non-person item are compared beside the analysis sample", {
  # 50 schools of two pupils of one row each, 9 pupils without an outcome in
  # 9 schools: the 50 schools, a non-person count, would show 100 rows or
  # more in the design sample beside the 91 analysed.
  school <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- seq_len(100) %% 4
  count[seq(1, 17, 2)] <- NA
  data <- data.frame(count = count, x = seq_len(100) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%03d", 1:100))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ))
  found <- audit_both(data, "count ~ x + (1 | school)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "school"),
                           "rows"), 91)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
  expect_identical(finding_of(found$internal, "structure.cluster_sizes",
                              factor = "school")$statistics$levels$count_class, "non_person")
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "rows"), "secondary")
})

test_that("the columns of a factor that is also a predictor do not give back its lost levels", {
  # 50 schools of four rows, 9 without an outcome: df 49 of design.collinearity
  # gives the 50 schools of the design sample, so the analysis sample loses
  # its 41, whether the schools count persons or, with two pupils or more
  # each, not.
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- seq_len(200) %% 5
  count[school %in% sprintf("s%02d", 42:50)] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%03d", 1:200))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ))
  for (declared in list(NULL, declaration)) {
    found <- audit_both(data, "count ~ x + school + (1 | school)", declaration = declared,
                        family = "poisson", outcome_access = "T1", reason = "Zeros.")
    expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "school"),
                             "df"), 49)
    shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
    expect_identical(detail(shares, "levels"), "secondary")
  }
  expect_identical(finding_of(found$internal, "outcome.zero_shares",
                              factor = "school")$statistics$levels$count_class, "non_person")
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(detail(constant, "multi_row_levels"), "secondary")
  # The dimension of a random term over the indicators of school counts the
  # 50 schools of the table in the same way.
  data$district <- sprintf("d%02d", rep(1:10, 20))
  found <- audit_both(data, "count ~ x + (1 | school) + (0 + school | district)",
                      declaration = declaration, family = "poisson", outcome_access = "T1",
                      reason = "Zeros.")
  dimension <- finding_of(found$shareable, "identifiability.levels_vs_dimension",
                          factor = "district")
  expect_identical(written(dimension, "dimension"), 50)
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(detail(shares, "levels"), "secondary")
})

test_that("the columns of a factor do not give back the levels that the filter hides", {
  # 20 subjects of two rows nested in 2 sites, site a fixed term and a
  # declared unit: structure.label_incidence counts the 2 sites as a person
  # count below k, which df 1 of design.collinearity, kept 3 and columns 3
  # of design.rank_deficiency and budget 18 beside 20 subjects would give
  # back (privacy.md, Across findings, rule 6).
  subject <- rep(sprintf("s%02d", 1:20), each = 2)
  data <- data.frame(y = seq_len(40) %% 7 + 0.25, treatment = rep(c(-0.5, 0.5), 20),
                     site = rep(c("S1", "S2"), each = 20), subject = subject)
  units <- list(list(name = "site", columns = list("site"), role = "cluster"),
                list(name = "subject", columns = list("subject"), role = "cluster",
                     nested_in = "site", id_scope = "global"))
  declaration <- list(vocabulary = "0.1.0", units = units)
  formula <- "y ~ treatment + site + (1 | subject)"
  found <- audit_both(data, formula, declaration = declaration)
  incidence <- finding_of(found$shareable, "structure.label_incidence", first = "site")
  expect_identical(detail(incidence, "levels_first"), "min_count")
  site <- finding_of(found$shareable, "design.collinearity", term = "site")
  expect_identical(detail(site, "df"), "secondary")
  expect_identical(detail(site, "gvif_per_df"), "secondary")
  expect_identical(site$message$text,
                   "'site' has a generalised variance inflation factor per degree of freedom below 5.")
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "treatment"),
                           "df"), 1)
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  for (name in c("kept", "columns", "empty_cells")) {
    expect_identical(detail(rank, name), "secondary")
  }
  expect_message_falls_back(rank, "full_rank")
  budget <- finding_of(found$shareable, "identifiability.df_budget", factor = "subject")
  expect_identical(detail(budget, "budget"), "secondary")
  expect_identical(written(budget, "levels"), 20)
  # With the subjects as the disclosure unit, each site holds 10 members, so
  # its levels are a non-person count that the document writes, and so are
  # the counts of its columns.
  units[[2L]]$role <- "participant"
  found <- audit_both(data, formula, declaration = list(vocabulary = "0.1.0", units = units))
  incidence <- finding_of(found$shareable, "structure.label_incidence", first = "site")
  expect_identical(written(incidence, "levels_first"), 2)
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "site"), "df"),
                   1)
  expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "kept"), 3)
  # A factor whose levels no count measures, such as an arm that only
  # labels.unicode_forms reads, keeps the counts of its columns.
  data$arm <- rep(c("a", "b", "c", "c"), 10)
  found <- audit_both(data, "y ~ treatment + arm + (1 | subject)")
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "arm"), "df"),
                   2)
  expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "columns"), 4)
})

test_that("the absence of an internal_only statistic does not show the kept columns", {
  skip_if_not_installed("lpSolve")
  # 90 rows of 49 covariates and three indicators that are 1 in one row
  # each: the analysis sample keeps 53 columns, more than max_bound_programs
  # allows, so bounds is absent, whereas it would be present had the
  # outcomes of the three rows been missing. It is written as suppressed.
  local_seed(7)
  data <- as.data.frame(matrix(stats::rnorm(90 * 49), 90, 49))
  names(data) <- sprintf("x%02d", 1:49)
  data$y <- stats::rbinom(90, 1, 0.5)
  for (j in 1:3) {
    data[[sprintf("d%d", j)]] <- as.numeric(seq_len(90) == j)
  }
  formula <- paste("y ~", paste(c(names(data)[1:49], "d1", "d2", "d3"), collapse = " + "))
  found <- audit_both(data, formula, family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  internal <- finding_of(found$internal, "outcome.separation")
  expect_null(internal$statistics$bounds)
  expect_null(internal$statistics$columns_involved)
  shared <- finding_of(found$shareable, "outcome.separation")
  for (name in c("columns", "optimum", "margin", "bounds", "columns_involved")) {
    expect_identical(detail(shared, name), "internal_only")
  }
})

test_that("the columns of the combination of a term's factors do not give back its lost levels", {
  # 19 cells of A and B of three rows, the cell (a4, b5) empty, with
  # count ~ x + A * B + (1 | A:B): df 3 and 4 of A and B and empty_cells 1
  # give the 19 combinations of the design sample, which beside the analysed
  # combinations would show how many lack an outcome. structure.label_incidence
  # counts the 4 levels of A and the 5 of B, person counts below k, so rule 6
  # suppresses these counts of columns too, and the analysis sample loses its
  # combinations all the same.
  cells <- expand.grid(A = paste0("a", 1:4), B = paste0("b", 1:5), stringsAsFactors = FALSE)
  cells <- cells[!(cells$A == "a4" & cells$B == "b5"), ]
  data <- cells[rep(seq_len(nrow(cells)), each = 3), ]
  data$x <- seq_len(nrow(data)) %% 7 + 0.5
  data$count <- seq_len(nrow(data)) %% 4
  data$count[data$A == "a1" & data$B == "b1"] <- NA
  found <- audit_both(data, "count ~ x + A * B + (1 | A:B)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  expect_identical(written(finding_of(found$internal, "design.rank_deficiency"), "empty_cells"), 1)
  for (name in c("empty_cells", "kept", "columns")) {
    expect_identical(detail(rank, name), "secondary")
  }
  expect_identical(detail(finding_of(found$shareable, "design.collinearity", term = "A"), "df"),
                   "secondary")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "A:B")
  expect_identical(written(shares, "rows"), 54)
  expect_identical(detail(shares, "levels"), "secondary")
})

test_that("the sizes of the levels of the design sample do not give back what the analysed ones lost", {
  # 20 subjects of one row and 40 of two, 10 of these without an outcome: the
  # 100 rows, 20 subjects of one row and 40 of two of the design sample show
  # that no subject has three rows, which beside 50 analysed subjects of 80
  # rows would show that no analysed subject of two rows lost an outcome, so
  # the design sample and the table lose their rows.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("t%02d", 1:40), each = 2))
  count <- seq_along(subject) %% 4
  count[subject >= "t31"] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  expect_identical(c(written(shares, "rows"), written(shares, "levels")), c(80, 50))
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(c(written(sizes, "levels"), written(sizes, "singletons")), c(60, 20))
  expect_identical(detail(sizes, "rows"), "secondary")
  expect_identical(detail(sizes, "effective_size"), "secondary")
  expect_identical(detail(finding_of(found$shareable, "sample.raw_vs_analysis"), "rows_raw"),
                   "secondary")
  # With 10 more subjects of two rows that lose their second outcome, 30
  # analysed subjects of one row out of 60 and 90 rows are the only value
  # that the sizes leave, so the design sample loses its rows again.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("t%02d", 1:50), each = 2))
  count <- seq_along(subject) %% 4
  count[subject >= "t41"] <- NA
  count[subject %in% sprintf("t%02d", 31:40) & duplicated(subject)] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "levels"), 70)
  expect_identical(detail(sizes, "rows"), "secondary")
  # 40 subjects of two rows, 10 without an outcome: no analysed subject has
  # one row, so rule 2 hides the analysed subjects with two rows, and the
  # design sample loses its own, with every count of its subjects and the
  # reals that read them, while it writes its rows. 80 rows, 40 levels and
  # effective_size 2 would otherwise show the analysed sizes.
  subject <- rep(sprintf("s%02d", 1:40), each = 2)
  count <- seq_along(subject) %% 4
  count[subject >= "s31"] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "rows"), 80)
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(detail(sizes, "effective_size"), "secondary")
})

test_that("a written part does not bound a hidden count of the analysis sample", {
  # 50 schools of four rows, 40 with zero counts, the outcome of one school
  # missing or not: the levels hidden beside df 49, all_zero_levels 40 would
  # show 50 analysed schools, so that none lacks an outcome.
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- ifelse(school <= "s40", 0, seq_along(school) %% 3 + 1)
  data <- data.frame(count = count, x = seq_along(school) %% 7 + 0.5, school = school)
  found <- audit_both(data, "count ~ x + school + (1 | school)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(detail(shares, "levels"), "secondary")
  expect_identical(detail(shares, "all_zero_levels"), "secondary")
  # 50 subjects of two rows, 30 with zero counts, 10 without an outcome and
  # one without its second: rule 3 hides the 40 analysed subjects beside 79
  # rows, which all_zero_levels 30 would bound from below by 40.
  subject <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- ifelse(subject <= "s30", 0, seq_along(subject) %% 3 + 1)
  count[subject >= "s41"] <- NA
  count[80] <- NA
  data <- data.frame(count = count, time = rep(0:1, 50), subject = subject)
  found <- audit_both(data, "count ~ time + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  expect_identical(written(shares, "rows"), 79)
  expect_identical(detail(shares, "levels"), "secondary")
  expect_identical(detail(shares, "all_zero_levels"), "secondary")
})

test_that("the rows and the columns of a factor that is also a predictor do not bound its lost levels", {
  # 30 schools of two rows and 20 of one, the 10 schools s41 to s50 of one
  # row without an outcome: df 49 and 80 rows would bound the design
  # sample's schools with two rows by 30, which outcome.constant_clusters
  # writes for the analysis sample, showing that none lost an outcome. The
  # analysed schools with two rows hold all their rows, so the design sample
  # loses its rows.
  school <- c(rep(sprintf("s%02d", 1:30), each = 2), sprintf("s%02d", 31:50))
  y <- seq_along(school) / 7 + rep(c(0, 0.5), length.out = length(school))
  y[school <= "s10"] <- rep(seq(1, 10), each = 2)
  y[school >= "s41"] <- NA
  data <- data.frame(y = y, x = seq_along(school) %% 5 + 0.5, school = school)
  found <- audit_both(data, "y ~ x + school + (1 | school)", outcome_access = "T1",
                      reason = "Constant levels.")
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(written(constant, "multi_row_levels"), 30)
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "school"),
                           "df"), 49)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
  expect_identical(detail(sizes, "rows"), "secondary")
  # 50 schools of two pupils, the disclosure unit, 9 of them without an
  # outcome: df 49 and two pupils or more in each school bound the rows of
  # the design sample, hidden beside the 91 analysed, by 100, so the analysis
  # sample loses its rows.
  school <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- seq_len(100) %% 4
  count[seq(1, 17, 2)] <- NA
  data <- data.frame(count = count, x = seq_len(100) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%03d", 1:100))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ))
  found <- audit_both(data, "count ~ x + school + (1 | school)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(detail(shares, "rows"), "secondary")
  expect_identical(shares$support$rows$availability$detail, "secondary")
  expect_identical(shares$support$contributors$distinct$availability$detail, "secondary")
})

test_that("the levels that the analysis sample hides are hidden in the design sample too", {
  # 20 subjects of two rows, 10 without an outcome and one without its
  # second: rule 3 hides the 10 analysed subjects beside 19 rows, which the
  # minimum-count rule bounds by 10 from below, and 20 written levels of the
  # design sample, k or more above them, would leave 10.
  subject <- rep(sprintf("s%02d", 1:20), each = 2)
  count <- seq_along(subject) %% 4
  count[subject >= "s11"] <- NA
  count[2] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  expect_identical(detail(shares, "levels"), "secondary")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(detail(sizes, "levels"), "secondary")
  # 20 subjects of four rows, 15 of which lose two outcomes each: the design
  # sample keeps its rows and loses its levels, and the reals that read the
  # subjects would give the levels of the balanced design from the rows.
  subject <- rep(sprintf("s%02d", 1:20), each = 4)
  count <- seq_along(subject) %% 4
  count[subject <= "s15" & rep(1:4, 20) <= 2] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
  expect_identical(written(sizes, "rows"), 80)
  expect_identical(detail(sizes, "effective_size"), "secondary")
  expect_identical(detail(finding_of(found$shareable, "identifiability.gram_rank"),
                          "smallest_eigenvalue"), "secondary")
})

test_that("the analysed rows are hidden beside k contributors or more when fewer than 2k", {
  # 9 subjects of one row and one of two, every outcome present: the
  # minimum-count rule holds for 10 subjects, which beside 11 written rows
  # would show that 9 have one analysed row.
  data <- data.frame(count = c(0, 1, 2, 3, 0, 1, 2, 3, 1, 2, 0), x = (1:11) / 3,
                     subject = c(sprintf("s%02d", 1:9), "s10", "s10"))
  found <- audit_both(data, "count ~ x + (1 | subject)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "subject")
  expect_identical(detail(shares, "rows"), "secondary")
  expect_identical(shares$support$rows$availability$detail, "secondary")
})

test_that("step 7 applies steps 6 and 9 to the findings on the analysis sample before it is shown", {
  # 50 schools of two pupils, a fixed term and a declared cluster, and a
  # bounded score without its value for 9 pupils: df 49 and the two pupils
  # or more of each school bound the 100 rows of the design sample, so the
  # analysis sample loses its 91 rows. Step 5 then suppresses the shares of
  # outcome.boundary_shares, whose decision reads them, so that the finding,
  # the only one on the analysis sample, is suppressed as a whole and the
  # document does not show the analysis sample: the design sample writes its
  # rows.
  score <- rep(c(0.5, 9.5, 3, 4, 5), 20)
  score[seq(1, 17, 2)] <- NA
  data <- data.frame(score = score, x = seq_len(100) %% 7 + 0.5,
                     school = rep(sprintf("s%02d", 1:50), each = 2),
                     pupil = sprintf("p%03d", 1:100))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ), variables = list(
    score = list(role = "outcome", measurement = "bounded_score", bounds = list(0.5, 9.5))))
  found <- audit_both(data, "score ~ x + school", declaration = declaration,
                      outcome_access = "T1", reason = "Bounds.")
  bounds <- finding_of(found$shareable, "outcome.boundary_shares")
  expect_identical(bounds$status$availability$detail, "decision")
  expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "support_rows"),
                   100)
})

test_that("a count of levels lost beside the analysis sample is compared with no other sample", {
  # 20 subjects of one row and 30 of four rows: 10 of these lack the
  # covariate, or 9 lack it and one lacks every outcome. The design sample
  # loses the levels of subject beside the 40 analysed in both tables, and
  # the table's 50 contributors would be written beside 40 subjects of the
  # design sample and hidden beside 41. The analysed subjects of one row and
  # of four rows both number k or more, so rule 2 hides neither.
  make <- function(y_missing) {
    g <- c(sprintf("o%02d", 1:20), rep(sprintf("s%02d", 1:30), each = 4))
    data <- data.frame(count = seq_along(g) %% 4, x = seq_along(g) %% 7 + 0.5, g = g)
    data$x[g %in% sprintf("s%02d", if (y_missing) 21:29 else 21:30)] <- NA
    if (y_missing) {
      data$count[g == "s30"] <- NA
    }
    audit_both(data, "count ~ x + (1 | g)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.")$shareable
  }
  pair <- lapply(c(FALSE, TRUE), make)
  expect_same_reading(pair[[1L]], pair[[2L]])
  expect_identical(written(finding_of(pair[[1L]], "sample.raw_vs_analysis"), "contributors"), 50)
})

test_that("a ratio is suppressed with its numerator or denominator whatever their class", {
  # 50 schools of 3 pupils with one row each, pupils the disclosure unit, so
  # that the schools count as non-person, school a fixed term and a grouping
  # factor, and the outcome constant within 12 schools and missing in 3. The
  # end of rule 1 hides the 47 analysed schools beside the 50 that kept
  # counts, and constant_levels 12 over constant_share would give them back.
  school <- rep(sprintf("s%02d", 1:50), each = 3)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  for (lacking in c(0L, 3L)) {
    y <- (seq_along(school) * 7) %% 11 + 0.5
    y[school %in% sprintf("s%02d", 21:32)] <- 2.5
    y[school %in% sprintf("s%02d", seq_len(lacking))] <- NA
    data <- data.frame(y = y, x = seq_along(school) %% 5 + 0.25, school = school,
                       pupil = sprintf("p%03d", seq_along(school)))
    found <- audit_both(data, "y ~ x + school + (1 | school)", outcome_access = "T1",
                        reason = "Constant.", declaration = declaration)
    constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
    expect_identical(constant$statistics$multi_row_levels$count_class, "non_person")
    expect_identical(detail(constant, "multi_row_levels"), "secondary")
    expect_identical(written(constant, "constant_levels"), 12)
    expect_identical(detail(constant, "constant_share"), "ratio")
  }
  # 30 class labels in 3 schools, 12 of which recur in a second school, two
  # pupils of one row in each combination, so that the classes count as
  # non-person, and no outcome missing: rule 1 hides the classes of the
  # design sample beside the analysed ones, rule 5 their shared and changing
  # labels, and changing_share would give back one beside the other.
  schools <- c("S1", "S2", "S3")
  combos <- rbind(data.frame(class = sprintf("c%02d", 1:30), school = schools[(0:29) %% 3 + 1]),
                  data.frame(class = sprintf("c%02d", 1:12), school = schools[(1:12) %% 3 + 1]))
  combos$tx <- as.numeric(seq_len(nrow(combos)) %in% 31:34)
  data <- combos[rep(seq_len(nrow(combos)), each = 2), ]
  data$pupil <- sprintf("p%03d", seq_len(nrow(data)))
  data$x <- seq_len(nrow(data)) %% 7 + 0.5
  data$count <- seq_len(nrow(data)) %% 3
  found <- audit_both(data, "count ~ x + tx + (1 | school) + (1 | class)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.",
                      declaration = list(vocabulary = "0.1.0", units = list(
                        list(name = "pupil", columns = list("pupil"), role = "participant"))))
  internal <- finding_of(found$internal, "structure.id_scope_evidence")
  expect_identical(written(internal, "changing_labels"), 4)
  expect_identical(written(internal, "shared_labels"), 12)
  evidence <- finding_of(found$shareable, "structure.id_scope_evidence")
  expect_identical(evidence$statistics$shared_labels$count_class, "non_person")
  for (name in c("shared_labels", "changing_labels")) {
    expect_identical(detail(evidence, name), "secondary")
  }
  expect_identical(detail(evidence, "changing_share"), "ratio")
})

test_that("the analysis sample loses the levels of the disclosure unit with its contributors", {
  # 50 schools of 2 pupils with two rows each, pupils the disclosure unit and
  # a grouping factor, school a fixed term. With 9 pupils without an
  # outcome, the 50 schools of two pupils or more that the columns of school
  # count bound the pupils of the design sample by 100, so that the analysis
  # sample loses its 91 contributors, and with them its pupils, which the
  # levels of outcome.zero_shares would give back. With 0 or 12, both stay.
  pupil <- rep(sprintf("p%03d", 1:100), each = 2)
  school <- sprintf("s%02d", (match(pupil, unique(pupil)) - 1L) %/% 2L + 1L)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  for (lacking in c(0L, 9L, 12L)) {
    count <- seq_along(pupil) %% 4
    count[pupil %in% sprintf("p%03d", seq(1, by = 2, length.out = lacking))] <- NA
    data <- data.frame(count = count, x = seq_along(pupil) %% 7 + 0.5, school = school,
                       pupil = pupil)
    found <- audit_both(data, "count ~ x + school + (1 | pupil)", family = "poisson",
                        outcome_access = "T1", reason = "Zeros.", declaration = declaration)
    zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "pupil")
    if (lacking == 9L) {
      expect_identical(zeros$support$contributors$distinct$availability$detail, "secondary")
      expect_identical(detail(zeros, "levels"), "secondary")
    } else {
      expect_identical(written(zeros, "contributors"), 100 - lacking)
      expect_identical(written(zeros, "levels"), 100 - lacking)
    }
  }
})

test_that("the analysis sample loses the levels of a non-person item that the members bound", {
  # 30 schools of two pupils with one row each, pupils the disclosure unit,
  # and the second pupil of 10 schools without an outcome: the 60 rows and
  # pupils of the design sample, which rule 1 leaves written beside the 50
  # analysed, hold at most 30 schools of two pupils or more, so that 30
  # analysed schools would show that none lacks every outcome. With a third
  # pupil in those 10 schools, the 70 pupils leave 35 possible schools, and
  # the analysed schools stay written.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  for (third in c(0L, 10L)) {
    pupils <- rep(2L, 30L)
    pupils[seq_len(third)] <- 3L
    school <- rep(sprintf("s%02d", 1:30), pupils)
    count <- seq_along(school) %% 3
    count[sequence(pupils) == rep(pupils, pupils) & school %in% sprintf("s%02d", 1:10)] <- NA
    data <- data.frame(count = count, x = seq_along(school) %% 7 + 0.5, school = school,
                       pupil = sprintf("p%02d", seq_along(school)))
    found <- audit_both(data, "count ~ x + (1 | school)", family = "poisson",
                        outcome_access = "T1", reason = "Zeros.", declaration = declaration)
    sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
    expect_identical(sizes$statistics$levels$count_class, "non_person")
    expect_identical(written(sizes, "contributors"), 60 + third)
    zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
    if (third == 0L) {
      expect_identical(detail(zeros, "levels"), "secondary")
    } else {
      expect_identical(written(zeros, "levels"), 30)
    }
  }
})

test_that("a disclosure unit whose members each have one row keeps its counts", {
  # 200 pupils of one row each in 20 schools, 30 of them without an
  # outcome: the analysed pupils are the analysed rows whatever the outcome,
  # so rule 3 leaves the pupils out, and the pupils' levels with two rows,
  # 0 in every sample, are not compared, so the design sample keeps its 200
  # contributors. The schools, which count non-persons, keep their counts
  # and reals, since the design sample loses neither its rows nor its
  # pupils beside the analysis sample.
  count <- (seq_len(200) * 5L) %% 4L
  count[c(seq(3, 200, 20), seq(5, 200, 20), seq(8, 200, 20))] <- NA
  data <- data.frame(count = count, x = (seq_len(200) * 7L) %% 11L + 0.5,
                     school = sprintf("S%02d", rep(1:20, each = 10)),
                     pupil = sprintf("p%03d", seq_len(200)))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  found <- audit_both(data, "count ~ x + (1 | school)", declaration = declaration,
                      family = "poisson", outcome_access = "T1", reason = "Zeros.")
  shares <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(c(written(shares, "support_rows"), written(shares, "contributors")),
                   c(170, 170))
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
  expect_identical(c(written(sizes, "rows"), written(sizes, "contributors"),
                     written(sizes, "levels")), c(200, 200, 20))
  expect_false(is.null(written(sizes, "effective_size")))
  within <- finding_of(found$shareable, "structure.within_between", factor = "school", term = "x")
  expect_false(is.null(written(within, "within_share")))
})

test_that("the analysis sample loses its rows with the levels of an item of one row a level", {
  # 11 class labels reused in 11 schools, one pupil of one row in each
  # combination, the pupils the disclosure unit. The crossing of class and
  # school writes the 121 combinations of the design sample, which are the
  # pupils, so the end of rule 1 hides the analysed pupils, and with them
  # the analysed rows, which equal them whatever the outcome: written rows of
  # 121 would show that no outcome is missing, as hidden rows show that one
  # or more is. With 11 pupils in each school and label, none can be left
  # one pupil by losing fewer than k rows, so that Decisions leaves the
  # findings of outcome.constant_clusters written.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "class", columns = list("class"), role = "cluster", nested_in = "school",
         id_scope = "within_parent"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "class",
         id_scope = "global")),
    observation = list(unit = "pupil", key = list("pupil")))
  data <- expand.grid(class = sprintf("%02d", 1:11), school = sprintf("S%02d", 1:11),
                      stringsAsFactors = FALSE)
  data$pupil <- sprintf("P%03d", 1:121)
  for (lacking in c(0L, 1L)) {
    data$y <- round(sin(1:121) * 3, 2)
    data$y[seq_len(lacking)] <- NA
    found <- audit_both(data, "y ~ 1 + (1 | school) + (1 | class)", declaration = declaration,
                        outcome_access = "T1", reason = "Constant classes.")
    constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
    expect_identical(constant$support$rows$availability$detail, "secondary")
    expect_identical(constant$support$contributors$distinct$availability$detail, "secondary")
  }
  # 67 schools, the first of two pupils and the others of one, one row for
  # each pupil and 9 pupils without an outcome. The 67 schools that kept
  # writes bound the rows of the design sample from below beside the 59
  # analysed rows, so the end of rule 1 hides the analysed rows, and the
  # analysed pupils, which equal them, are hidden with them. With 10
  # without an outcome and a third pupil in the first school, both stay.
  pupil_declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")),
    observation = list(unit = "pupil", key = list("pupil")))
  for (lacking in c(9L, 10L)) {
    school <- sprintf("s%02d", c(rep(1L, lacking - 7L), 2:67))
    count <- seq_along(school) %% 4
    count[2L + seq_len(lacking)] <- NA
    data <- data.frame(count = count, x = round(cos(seq_along(school)) * 3, 1), school = school,
                       pupil = sprintf("p%02d", seq_along(school)))
    found <- audit_both(data, "count ~ x + school + (1 | school)", family = "poisson",
                        outcome_access = "T1", reason = "Zeros.",
                        declaration = pupil_declaration)
    zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
    if (lacking == 9L) {
      expect_identical(zeros$support$rows$availability$detail, "secondary")
      expect_identical(zeros$support$contributors$distinct$availability$detail, "secondary")
    } else {
      expect_identical(c(written(zeros, "support_rows"), written(zeros, "contributors")),
                       c(59, 59))
    }
  }
})

test_that("outcome.separation with one kept column of two variables or one factor is suppressed", {
  skip_if_not_installed("lpSolve")
  # One kept column besides the intercept, which reads x and z: a verdict of
  # quasi or complete would name a cell of x:z.
  x <- 1:40
  z <- 100 + (1:40) %% 7
  data <- data.frame(y = as.numeric(x * z > stats::median(x * z)), x = x, z = z)
  found <- audit_both(data, "y ~ x:z", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  expect_identical(finding_of(found$internal, "outcome.separation")$statistics$verdict$value,
                   "complete")
  expect_identical(finding_of(found$shareable, "outcome.separation")$status$availability$detail,
                   "decision")
  # A factor of 24 levels of one row each: no two rows share the values of
  # the kept columns, and the verdict would show the class of each level.
  data <- data.frame(y = rep(c(1, 0), 12), g = sprintf("g%02d", 1:24))
  found <- audit_both(data, "y ~ g", family = "binomial", outcome_access = "T2",
                      reason = "Separation.", exploratory = TRUE)
  expect_identical(finding_of(found$internal, "outcome.separation")$statistics$verdict$value,
                   "complete")
  expect_identical(finding_of(found$shareable, "outcome.separation")$status$availability$detail,
                   "decision")
})

test_that("only the rows of assignments that yield findings are samples", {
  # 30 classes of 2 rows without a disclosure unit. 'arm' is missing in
  # classes 1 to 10 and 'dose' in classes 1 to 11, so the rows of 'dose'
  # lie in those of 'arm' and differ by one class.
  class <- rep(sprintf("c%02d", 1:30), each = 2)
  arm <- rep(c("a", "b"), 30)[match(class, unique(class))]
  dose <- rep(c("d1", "d2", "d3"), 10)[match(class, unique(class))]
  arm[class <= "c10"] <- NA
  dose[class <= "c11"] <- NA
  data <- data.frame(y = seq_along(class) %% 7, x = seq_along(class) %% 5, class = class,
                     arm = arm, dose = dose)
  units <- function(level) {
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "class", columns = list("class"), role = "cluster")
    ), assignment = list(
      list(column = "arm", unit = "class", randomised = TRUE, level = "between_unit"),
      list(column = "dose", unit = "class", randomised = TRUE, level = level)
    ))
    found <- audit_both(data, "y ~ x + (1 | class)", declaration = declaration)
    finding_of(found$shareable, "assignment.design_df", column = "arm")
  }
  # 'dose' within units yields no finding, so its rows are not a sample.
  expect_identical(written(units("within_unit"), "units"), 20)
  expect_identical(detail(units("between_unit"), "units"), "secondary")
})

test_that("the rows of two pairs of columns that hold the same rows are one sample", {
  # 24 classes and 24 teachers in 12 schools, which are not in the formula
  # and are missing in schools 7 to 12: the pairs (class, school) and
  # (school, teacher) read the same 24 rows.
  index <- rep(1:24, each = 2)
  school <- sprintf("S%02d", (index + 1) %/% 2)
  school[index > 12] <- NA
  data <- data.frame(y = seq_along(index) %% 7, x = seq_along(index) %% 5,
                     class = sprintf("c%02d", index), teacher = sprintf("t%02d", index),
                     school = school)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "class", columns = list("class"), nested_in = "school", id_scope = "global",
         role = "cluster"),
    list(name = "teacher", columns = list("teacher"), nested_in = "school", id_scope = "global",
         role = "cluster")
  ))
  found <- audit_both(data, "y ~ x + (1 | class) + (1 | teacher)", declaration = declaration)
  classes <- finding_of(found$shareable, "structure.label_incidence", first = "class",
                        second = "school")
  teachers <- finding_of(found$shareable, "structure.label_incidence", first = "school",
                         second = "teacher")
  expect_identical(written(classes, "levels_first"), 12)
  expect_identical(written(teachers, "levels_second"), 12)
})

test_that("a draft declaration has the disclosure unit of the units that do not count as absent", {
  data <- data.frame(y = seq_len(24) %% 5, x = seq_len(24) %% 7,
                     class = rep(sprintf("c%d", 1:6), each = 4),
                     pupil = rep(sprintf("p%02d", 1:12), each = 2))
  draft <- function(inferred, disclosure_unit = NULL) {
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "class", columns = list("class"), role = "cluster"),
      list(name = "pupil", columns = list("pupil"), role = "participant")
    ), provenance = list(inferred = inferred))
    declaration$disclosure_unit <- disclosure_unit
    with_audit_time(audit(data, "y ~ x + (1 | class)", declaration = declaration,
                          key = privacy_key))$document
  }
  # A disclosure_unit that names a unit that counts as absent counts as
  # absent itself, so that the one participant unit is the default.
  document <- draft(list("/units/0"), "class")
  expect_identical(document$privacy$disclosure_unit, list(name = "pupil", source = "participant"))
  # A unit one of whose columns is inferred counts as absent, so that no
  # unit is the disclosure unit.
  for (inferred in c("/units/1/columns", "/units/1/columns/0", "/units/1/name")) {
    document <- draft(list(inferred))
    expect_null(document$privacy$disclosure_unit)
    sizes <- finding_of(document, "structure.cluster_sizes", factor = "class")
    expect_identical(sizes$support$contributors$basis, "grouping_factors")
  }
})

# --- Counts of columns, chains and the clauses of steps 6 and 7 -----------------------

test_that("a term's variables are matched to an item on the rows that its counts read", {
  # 99 cells of A and B with three rows each, the outcome missing in one,
  # and cell, which labels them, missing in one row, which leaves the
  # design sample: A:B divides the design sample, though not the table, into
  # the levels of cell, so kept 100 and empty_cells 1 give its 99 levels
  # there, and the 98 analysed levels must be hidden.
  cells <- expand.grid(B = sprintf("b%02d", 1:10), A = sprintf("a%02d", 1:10),
                       stringsAsFactors = FALSE)
  cells <- cells[!(cells$A == "a10" & cells$B == "b10"), ]
  last <- which(cells$A == "a09" & cells$B == "b10")
  cells <- rbind(cells[-last, ], cells[last, ])
  data <- cells[rep(seq_len(nrow(cells)), each = 3), c("A", "B")]
  rownames(data) <- NULL
  n <- nrow(data)
  data$x <- seq_len(n) %% 7 + 0.5
  data$count <- seq_len(n) %% 4
  data$count[data$A == "a01" & data$B == "b01"] <- NA
  data$cell <- paste(data$A, data$B, sep = "-")
  data$cell[n] <- NA
  found <- audit_both(data, "count ~ x + A * B + (1 | cell)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$internal, "outcome.zero_shares", factor = "cell"),
                           "levels"), 98)
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  expect_identical(written(rank, "kept"), 100)
  expect_identical(written(rank, "empty_cells"), 1)
  shared <- finding_of(found$shareable, "outcome.zero_shares", factor = "cell")
  expect_identical(detail(shared, "levels"), "secondary")
  # school2 copies the grouping factor school but lacks a label in one row:
  # df 49 gives the 50 schools of the design sample beside 41 analysed ones.
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- seq_len(200) %% 5
  count[school %in% sprintf("s%02d", 42:50)] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school,
                     school2 = replace(school, 1L, NA))
  found <- audit_both(data, "count ~ x + school2 + (1 | school)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "school2"),
                           "df"), 49)
  expect_identical(detail(finding_of(found$shareable, "outcome.zero_shares", factor = "school"),
                          "levels"), "secondary")
  # site2 copies the declared unit site, whose 4 levels step 3 hides, but
  # lacks its label in one row: its columns count the sites of the design
  # sample.
  subject <- rep(sprintf("s%02d", 1:40), each = 5)
  data <- data.frame(y = (seq_len(200) * 5L) %% 13L + 0.25,
                     treatment = rep(c(0.5, -0.5), 100),
                     site = sprintf("S%d", (match(subject, unique(subject)) - 1L) %/% 10L + 1L),
                     subject = subject)
  data$site2 <- replace(data$site, 1L, NA)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")))
  found <- audit_both(data, "y ~ treatment + site2 + (1 | subject)", declaration = declaration)
  expect_identical(detail(finding_of(found$shareable, "structure.label_incidence", first = "site"),
                          "levels_first"), "min_count")
  site <- finding_of(found$shareable, "design.collinearity", term = "site2")
  expect_identical(detail(site, "df"), "secondary")
  expect_identical(detail(site, "gvif_per_df"), "secondary")
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  for (name in c("kept", "columns", "empty_cells")) {
    expect_identical(detail(rank, name), "secondary")
  }
  expect_identical(detail(finding_of(found$shareable, "identifiability.df_budget",
                                     factor = "subject"), "budget"), "secondary")
})

test_that("the columns of the IR do not give back the levels that rule 1 hides in the table", {
  # 12 sites crossed with 20 districts, two rows each, and x missing in
  # every row of S12: dimension 12 of (0 + site | district), and columns 12
  # of identifiability.residual_confounding, count the sites of the table,
  # which rule 1 hides beside the 11 that structure.cluster_sizes counts in
  # the design sample.
  rows <- expand.grid(rep = 1:2, site = sprintf("S%02d", 1:12),
                      district = sprintf("d%02d", 1:20), stringsAsFactors = FALSE)
  n <- nrow(rows)
  data <- data.frame(y = (seq_len(n) * 7) %% 11 + 0.5, x = seq_len(n) %% 5 + 0.25,
                     site = rows$site, district = rows$district)
  data$x[data$site == "S12"] <- NA
  found <- audit_both(data, "y ~ x + (0 + site | district) + (1 | site)")
  expect_identical(written(finding_of(found$internal, "identifiability.levels_vs_dimension",
                                      factor = "district"), "dimension"), 12)
  expect_identical(written(finding_of(found$shareable, "structure.cluster_sizes",
                                      factor = "site"), "levels"), 11)
  shared <- finding_of(found$shareable, "identifiability.levels_vs_dimension", factor = "district")
  expect_identical(detail(shared, "dimension"), "secondary")
  expect_identical(detail(finding_of(found$shareable, "identifiability.residual_confounding",
                                     factor = "district"), "columns"), "secondary")
  expect_identical(written(finding_of(found$shareable, "identifiability.levels_vs_dimension",
                                      factor = "site"), "dimension"), 1)
  # Without the grouping factor site, no count measures the levels of site,
  # a predictor that only labels.unicode_forms reads, and dimension stays.
  found <- audit_both(data, "y ~ x + (0 + site | district)")
  expect_identical(written(finding_of(found$shareable, "identifiability.levels_vs_dimension",
                                      factor = "district"), "dimension"), 12)
})

test_that("the random terms that '||' splits from a frozen factor keep their dimension", {
  # 3 sites, whose levels step 3 hides, split by '||' into random terms of
  # one column each, whose dimension is 1 whatever the levels.
  subject <- rep(sprintf("s%02d", 1:40), each = 6)
  data <- data.frame(y = (seq_len(240) * 7) %% 11 + 0.5,
                     site = sprintf("S%d", (match(subject, unique(subject)) - 1L) %% 3L + 1L),
                     subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")))
  found <- audit_both(data, "y ~ 1 + (1 + site || subject)", declaration = declaration,
                      coding = list(site = list(frozen = TRUE)))
  expect_identical(detail(finding_of(found$shareable, "structure.label_incidence", first = "site"),
                          "levels_first"), "min_count")
  for (term in c("0 + site[S2] | subject", "0 + site[S3] | subject")) {
    expect_identical(written(finding_of(found$shareable, "identifiability.levels_vs_dimension",
                                        term = term), "dimension"), 1)
    expect_identical(written(finding_of(found$shareable, "identifiability.residual_confounding",
                                        term = term), "columns"), 1)
  }
})

test_that("the columns of a term on analysed rows are suppressed with the levels hidden there", {
  # 50 schools of 4 pupils with two rows each, and 9 schools without the
  # outcome or treat, which is assigned to the pupils, so that the rows of
  # the assignment are the analysis sample: units 164 less design_df would
  # give the 41 analysed schools, which beside the 50 of kept show that 9
  # lack an outcome.
  school <- rep(sprintf("s%02d", 1:50), each = 8)
  pupil <- rep(sprintf("p%03d", 1:200), each = 2)
  data <- data.frame(count = seq_along(school) %% 4, school = school, pupil = pupil,
                     treat = ifelse(match(pupil, unique(pupil)) %% 2 == 0, "a", "b"))
  lacking <- school %in% sprintf("s%02d", 42:50)
  data$count[lacking] <- NA
  data$treat[lacking] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "cluster", nested_in = "school",
         id_scope = "global")),
    assignment = list(list(column = "treat", unit = "pupil", randomised = TRUE,
                           level = "between_unit")))
  found <- audit_both(data, "count ~ school + (1 | school)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.", declaration = declaration)
  expect_identical(written(finding_of(found$internal, "assignment.design_df", column = "treat"),
                           "design_df"), 123)
  assignment <- finding_of(found$shareable, "assignment.design_df", column = "treat")
  expect_identical(written(assignment, "units"), 164)
  expect_identical(detail(assignment, "design_df"), "secondary")
  expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "kept"), 50)
  expect_identical(detail(finding_of(found$shareable, "outcome.zero_shares", factor = "school"),
                          "levels"), "secondary")
})

test_that("the columns of a factor are hidden when every finding that counts its levels fails", {
  # 12 sites of two rows beside a grouping factor of 3 levels, so that every
  # finding fails the minimum-count rule, which hides the 12 sites although
  # they are k or more.
  site <- rep(sprintf("S%02d", 1:12), each = 2)
  data <- data.frame(y = (seq_along(site) * 7) %% 11 + 0.5, x = seq_along(site) %% 5 + 0.25,
                     site = site, g2 = rep(c("g1", "g2", "g3"), 8))
  found <- audit_both(data, "y ~ x + site + (1 | g2) + (1 | site)")
  expect_identical(detail(finding_of(found$shareable, "structure.cluster_sizes", factor = "site"),
                          "levels"), "min_count_rule")
  expect_identical(detail(finding_of(found$shareable, "design.collinearity", term = "site"), "df"),
                   "secondary")
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "x"), "df"),
                   1)
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  for (name in c("kept", "columns", "empty_cells")) {
    expect_identical(detail(rank, name), "secondary")
  }
  # A grouping factor of 10 levels, two of which hold 180 of the 196 rows,
  # makes every finding fail the dominance rule instead.
  n <- 196
  data <- data.frame(y = (seq_len(n) * 7) %% 11 + 0.5, x = seq_len(n) %% 5 + 0.25,
                     site = sprintf("S%02d", (seq_len(n) - 1L) %% 12L + 1L),
                     g2 = c(rep("g01", 95), rep("g02", 85), rep(sprintf("g%02d", 3:10), each = 2)))
  found <- audit_both(data, "y ~ x + site + (1 | g2) + (1 | site)")
  expect_identical(detail(finding_of(found$shareable, "structure.cluster_sizes", factor = "site"),
                          "levels"), "dominance")
  expect_identical(detail(finding_of(found$shareable, "design.collinearity", term = "site"), "df"),
                   "secondary")
  expect_identical(detail(finding_of(found$shareable, "design.rank_deficiency"), "kept"),
                   "secondary")
})

test_that("the columns of a term on the rows of an assignment are hidden with their levels there", {
  # 12 sites of 10 subjects with two rows each. dose, assigned to the
  # subjects, and arm, assigned to the sites, are both missing for the first
  # subject of every site, so that their rows are one sample, which keeps
  # the 12 sites. Rule 1 hides its sites beside the 12 of the design sample,
  # and design_df of dose, 96 beside 108 units, would give them back.
  site <- rep(sprintf("S%02d", 1:12), each = 20)
  subject <- rep(sprintf("u%03d", 1:120), each = 2)
  data <- data.frame(y = (seq_along(site) * 7) %% 11 + 0.5, site = site, subject = subject,
                     dose = ifelse(match(subject, unique(subject)) %% 2 == 0, "lo", "hi"),
                     arm = ifelse(match(site, unique(site)) %% 2 == 0, "a", "b"))
  first <- subject %in% sprintf("u%03d", seq(1, 120, by = 10))
  data$dose[first] <- NA
  data$arm[first] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")),
    assignment = list(
      list(column = "dose", unit = "subject", randomised = TRUE, level = "between_unit"),
      list(column = "arm", unit = "site", randomised = TRUE, level = "between_unit")))
  found <- audit_both(data, "y ~ site + (1 | subject)", declaration = declaration)
  expect_identical(written(finding_of(found$internal, "assignment.design_df", column = "dose"),
                           "design_df"), 96)
  dose <- finding_of(found$shareable, "assignment.design_df", column = "dose")
  expect_identical(written(dose, "units"), 108)
  expect_identical(detail(dose, "design_df"), "secondary")
  expect_identical(detail(finding_of(found$shareable, "assignment.design_df", column = "arm"),
                          "units"), "secondary")
  expect_identical(written(finding_of(found$shareable, "structure.label_incidence",
                                      first = "site"), "levels_first"), 12)
})

test_that("the columns of a term on rows of an assignment beside the analysed rows hide the analysed levels", {
  # 60 schools of 2 pupils of one row and 2 of two rows, school a fixed term
  # and a grouping factor, and treat assigned to the pupils. Neither treat
  # nor the outcome is present in schools 51 to 60. When the outcome is
  # also missing in schools 1 to 9, the rows of the assignment hold the 50
  # schools 1 to 50 and the analysis sample 41 of them, and when treat
  # alone is missing there, the rows of the assignment hold 41 schools and
  # the analysis sample 50. Rule 1 hides the schools of the rows of the
  # assignment beside the analysed ones, and units less design_df would give
  # them back, so that beside the analysed schools they would show the 9
  # that lack an outcome, or treat. The end of rule 1 hides the analysed
  # schools instead.
  school <- rep(sprintf("s%02d", 1:60), each = 6)
  pupil <- paste0(rep(sprintf("p%02d_", 1:60), each = 6), rep(c(1, 2, 3, 3, 4, 4), 60))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "cluster", nested_in = "school",
         id_scope = "global")),
    assignment = list(list(column = "treat", unit = "pupil", randomised = TRUE,
                           level = "between_unit")))
  for (missing in c("count", "treat")) {
    data <- data.frame(count = seq_along(school) %% 4, school = school, pupil = pupil,
                       treat = ifelse(match(pupil, unique(pupil)) %% 2 == 0, "a", "b"))
    data[school %in% sprintf("s%02d", 51:60), c("count", "treat")] <- NA
    data[[missing]][school %in% sprintf("s%02d", 1:9)] <- NA
    found <- audit_both(data, "count ~ school + (1 | school)", family = "poisson",
                        outcome_access = "T1", reason = "Zeros.", declaration = declaration)
    assignment <- finding_of(found$shareable, "assignment.design_df", column = "treat")
    units <- if (missing == "count") 200 else 164
    expect_identical(written(assignment, "units"), units)
    expect_identical(written(assignment, "design_df"), units - if (missing == "count") 50 else 41)
    expect_identical(written(finding_of(found$shareable, "design.rank_deficiency"), "kept"), 60)
    zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
    expect_identical(written(finding_of(found$internal, "outcome.zero_shares", factor = "school"),
                             "levels"), if (missing == "count") 41 else 50)
    expect_identical(detail(zeros, "levels"), "secondary")
  }
})

test_that("the columns of the combination of a term's factors are hidden with its levels", {
  # 13 subjects, the disclosure unit, each with a row in each combination of
  # A and B apart from (a2, b3), which one subject holds: step 3 hides the 6
  # levels of the grouping factor A:B, which kept, columns and empty_cells
  # would give back beside the levels of A and B.
  combos <- expand.grid(B = c("b1", "b2", "b3"), A = c("a1", "a2"), stringsAsFactors = FALSE)
  rows <- list()
  for (s in 1:13) {
    for (j in seq_len(nrow(combos))) {
      if (s < 13 && combos$A[j] == "a2" && combos$B[j] == "b3") {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(subject = sprintf("s%02d", s), A = combos$A[j],
                                              B = combos$B[j])
    }
  }
  data <- do.call(rbind, rows)
  data$x <- seq_len(nrow(data)) %% 5 + 0.5
  data$y <- (seq_len(nrow(data)) * 7) %% 11 + 0.5
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")))
  found <- audit_both(data, "y ~ x + A * B + (1 | subject) + (1 | A:B)",
                      declaration = declaration)
  expect_identical(detail(finding_of(found$shareable, "structure.cluster_sizes", factor = "A:B"),
                          "levels"), "min_count")
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "A"), "df"),
                   1)
  expect_identical(written(finding_of(found$shareable, "design.collinearity", term = "B"), "df"),
                   2)
  rank <- finding_of(found$shareable, "design.rank_deficiency")
  for (name in c("kept", "columns", "empty_cells")) {
    expect_identical(detail(rank, name), "secondary")
  }
})

test_that("a count of columns below k that rule 6 suppresses has the detail 'secondary'", {
  # 18 subjects of two rows nested in 9 sites: step 3 hides the 9 sites, and
  # budget 18 - 9 = 9 with the detail 'min_count' would bound them by
  # 18 - 9, so that they would be 9.
  subject <- rep(sprintf("s%02d", 1:18), each = 2)
  data <- data.frame(y = (seq_along(subject) * 7) %% 11 + 0.5,
                     treatment = rep(c(-0.5, 0.5), 18),
                     site = rep(sprintf("S%d", 1:9), each = 4), subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")))
  found <- audit_both(data, "y ~ treatment + site + (1 | subject)", declaration = declaration)
  expect_identical(written(finding_of(found$internal, "identifiability.df_budget",
                                      factor = "subject"), "budget"), 9)
  budget <- finding_of(found$shareable, "identifiability.df_budget", factor = "subject")
  expect_identical(detail(budget, "budget"), "secondary")
  expect_identical(budget$statistics$budget$count_class, "person")
  expect_identical(written(budget, "levels"), 18)
})

test_that("a sample inside one that loses its levels beside the analysis sample is compared", {
  # 50 subjects of four rows, the unit to which z is assigned, z missing for
  # s50, and s01 without the covariate or without the outcome. The design
  # sample loses its subjects beside the 49 analysed ones either way, and
  # the rows of the assignment, which lie in it but leave out s50, lose
  # theirs beside the analysis sample, whose 49 exceed their 48 or 49 by
  # fewer than k, so that the two tables read alike.
  make <- function(y_missing) {
    subject <- rep(sprintf("s%02d", 1:50), each = 4)
    data <- data.frame(count = rep(c(0, 1, 2, 3), 50), x = seq_len(200) %% 7 + 0.5,
                       subject = subject,
                       z = ifelse(match(subject, unique(subject)) %% 2 == 0, "a", "b"))
    data$z[subject == "s50"] <- NA
    if (y_missing) {
      data$count[subject == "s01"] <- NA
    } else {
      data$x[subject == "s01"] <- NA
    }
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "subject", columns = list("subject"), role = "participant")),
      assignment = list(list(column = "z", unit = "subject", randomised = TRUE,
                             level = "between_unit")))
    audit_both(data, "count ~ x + (1 | subject)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.", declaration = declaration)
  }
  first <- make(FALSE)
  second <- make(TRUE)
  expect_identical(written(finding_of(second$internal, "assignment.design_df", column = "z"),
                           "units"), 49)
  for (found in list(first, second)) {
    for (check in c("assignment.design_df", "assignment.constant_within_unit")) {
      expect_identical(detail(finding_of(found$shareable, check, column = "z"), "units"),
                       "secondary")
    }
  }
  expect_same_reading(first$shareable, second$shareable)
})

test_that("the rows that the analysis sample hides are hidden in the samples that hold its rows", {
  # 12 subjects of two rows, each with one outcome or two: 13 or 15
  # analysed rows, which rule 3 hides beside 12 contributors. Beside 15, rule
  # 1 hides the 24 rows of the design sample, and beside 13 the design sample
  # loses them because the analysis sample hides its own, so that the two
  # tables read alike.
  make <- function(second) {
    count <- rep(c(1, 2), 12)
    count[seq(2, 24, by = 2)[-seq_len(second)]] <- NA
    data <- data.frame(count = count, x = seq_len(24) %% 5 + 0.5,
                       subject = rep(sprintf("s%02d", 1:12), each = 2))
    audit_both(data, "count ~ x + (1 | subject)", family = "poisson", outcome_access = "T1",
               reason = "Zeros.")
  }
  first <- make(1L)
  second <- make(3L)
  for (found in list(first, second)) {
    sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "subject")
    expect_identical(detail(sizes, "rows"), "secondary")
    expect_null(written(sizes, "support_rows"))
  }
  expect_same_reading(first$shareable, second$shareable)
})

test_that("the contributors of a factor that the design sample loses are hidden with its levels", {
  # Crossed factors f and g: 40 analysed rows in 20 levels of f and 22 of g,
  # and 20 rows without an outcome in 10 more levels of f and 9 more of g.
  # The design sample loses the levels of g, 31 beside 22 analysed, and
  # keeps those of f, 30 beside 20, so that written contributors of 30, the
  # levels of f, would show that g has more than 30 levels.
  f <- c(sprintf("f%02d", 1:10), rep(sprintf("f%02d", 11:20), each = 3),
         rep(sprintf("f%02d", 21:30), each = 2))
  g <- c(sprintf("g%02d", 1:12), rep(sprintf("g%02d", 13:20), each = 3),
         rep(sprintf("g%02d", 21:22), each = 2), sprintf("g%02d", 23 + (0:19) %% 9))
  data <- data.frame(count = c(seq_len(40) %% 4, rep(NA, 20)), x = seq_len(60) %% 7 + 0.5,
                     f = f, g = g)
  found <- audit_both(data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                      outcome_access = "T1", reason = "Zeros.")
  expect_identical(written(finding_of(found$internal, "structure.cluster_sizes", factor = "g"),
                           "contributors"), 30)
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "g")
  expect_identical(detail(sizes, "levels"), "secondary")
  expect_identical(sizes$support$contributors$distinct$availability$detail, "secondary")
  expect_identical(written(finding_of(found$shareable, "outcome.zero_shares", factor = "g"),
                           "levels"), 22)
})

test_that("part_of reads the parts that steps 1 to 5 leave written", {
  # 30 rows of 22 subjects: 8 subjects have two rows of the same trial, 9
  # one row and 5 one row without a trial. The total of 30 rows less the 16
  # duplicate rows, the only part that step 3 leaves written, is 14, so
  # duplicate_rows stays, although 30 - 5 - 16 is below k.
  data <- data.frame(y = seq_len(30) %% 7 + 0.5,
                     subject = c(rep(sprintf("s%02d", 1:8), each = 2), sprintf("s%02d", 9:22)),
                     trial = c(rep(1, 25), rep(NA, 5)))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  found <- audit_both(data, "y ~ 1 + (1 | subject)", declaration = declaration)
  internal <- finding_of(found$internal, "keys.duplicates")
  expect_identical(written(internal, "rows"), 30)
  expect_identical(written(internal, "missing_key_rows"), 5)
  expect_identical(written(internal, "duplicate_rows"), 16)
  keys <- finding_of(found$shareable, "keys.duplicates")
  expect_identical(written(keys, "duplicate_rows"), 16)
  expect_false(identical(detail(keys, "missing_key_rows"), NULL))
})

test_that("rule 4 compares the rows without a key value only with rows nested with them", {
  # 20 subjects of three trials: 12 rows lack their trial and 12 other rows
  # lack x, so that neither set of rows holds the other, and the 12 rows
  # without a key value give back nothing about the 12 that x removes.
  data <- data.frame(y = seq_len(60) %% 7 + 0.5, x = seq_len(60) %% 5 + 0.25,
                     subject = rep(sprintf("s%02d", 1:20), each = 3), trial = rep(1:3, 20))
  data$trial[1:12] <- NA
  data$x[25:36] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  found <- audit_both(data, "y ~ x + (1 | subject)", declaration = declaration)
  expect_identical(written(finding_of(found$shareable, "keys.duplicates"), "missing_key_rows"), 12)
  expect_identical(written(finding_of(found$shareable, "sample.raw_vs_analysis"), "rows_dropped"),
                   12)
})

test_that("the written quantiles of the level sizes raise the rows that rule 3 requires", {
  # Registry 0.1.0 writes no quantile of level sizes on the analysis sample,
  # so these helpers of rule 3 are called directly.
  expect_identical(quantile_position(12, "0"), 1)
  expect_identical(quantile_position(12, "1"), 12)
  expect_identical(quantile_position(12, "0.25"), 3)
  expect_identical(quantile_position(12, "0.5"), 6)
  expect_identical(quantile_position(12, "0.333"), 4)
  expect_identical(quantile_position(3, "0.25"), 1)
  expect_identical(privacy_rows_without_singletons(12, list()), 24)
  # A written median of 3 raises the sizes from position 6 on to 3, and an
  # upper quartile of 4 those from position 9 on to 4.
  expect_identical(privacy_rows_without_singletons(12, list(list(p = "0.5", value = 3))), 31)
  expect_identical(privacy_rows_without_singletons(
    12, list(list(p = "0.5", value = 3), list(p = "0.75", value = 4))), 35)
  item <- list(person = TRUE, levels = 12, levels_with_two_rows = 9, levels_with_one_row = 3)
  analysis <- list(rows = 30, contributors = 12, items = list(item))
  design <- list(rows = 40, contributors = 12,
                 items = list(list(person = TRUE, levels = 12, levels_with_two_rows = 12,
                                   levels_with_one_row = 0)))
  marks <- privacy_blank_marks(list(analysis = analysis))$analysis
  marks$items[[1L]][["levels_with_one_row"]] <- TRUE
  # 30 rows of 12 levels can have no level of one row, but not with a
  # written median of 3, which needs 31.
  expect_false(privacy_rule_3(analysis, design, marks, list(), 10)$items[[1L]][["levels"]])
  quartiles <- list(list(item = 1L, quantiles = list(list(p = "0.5", value = 3))))
  expect_true(privacy_rule_3(analysis, design, marks, quartiles, 10)$items[[1L]][["levels"]])
})

test_that("an absent internal_only by_unit count is written as a suppressed person count", {
  # No internal_only statistic of registry 0.1.0 is a by_unit count, so
  # privacy_absent() is called on an entry that has one.
  entry <- list(statistics = list(
    hidden = list(kind = "count", count_class = "by_unit", internal_only = TRUE),
    shown = list(kind = "count", count_class = "non_person")))
  finding <- list(entry = entry, values = list(shown = 3),
                  statistics = list(shown = list(kind = "count", count_class = "non_person")),
                  suppressed = structure(character(0), names = character(0)))
  out <- privacy_absent(finding)
  expect_identical(out$statistics$hidden, list(kind = "count", count_class = "person"))
  expect_identical(out$suppressed[["hidden"]], "internal_only")
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

test_that("the IR hash of a shareable document leaves out the constants of mean centrings", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"), list(name = "x", type = "number")
  )))
  data <- data.frame(y = c(1, 2, 3, 4), x = c(1, 2, 4, 8))
  coding <- list(x = list(centring = "mean", significant_digits = 4))
  found <- audit_both(data, "y ~ x", declaration = declaration, coding = coding)
  # The shareable document hashes the IR as it is before the data are seen.
  before <- formula_ir("y ~ x", declaration, coding = coding)
  expect_null(before$predictors$x$centring$constant)
  expect_identical(found$shareable$inputs$model$ir_hash, canonical_hash(before, "hashable"))
  after <- formula_ir("y ~ x", declaration, data, coding = coding)
  expect_identical(after$predictors$x$centring$constant$value, "3.75")
  expect_identical(found$internal$inputs$model$ir_hash, canonical_hash(after, "hashable"))
})

# Runs code with min_count set to k in the registry that the package has
# read, as the disclosure-attack tests do, and restores it after.
with_min_count <- function(k, code) {
  registry <- read_registry()
  old <- registry$privacy$min_count
  registry$privacy$min_count <- k
  assign("registry", registry, envir = mixedcheck_cache)
  on.exit({
    registry$privacy$min_count <- old
    assign("registry", registry, envir = mixedcheck_cache)
  }, add = TRUE)
  force(code)
}

test_that("the findings on an item of crossed columns that can be left one member are suppressed", {
  # Class labels 01 to 10 reused in 4 schools and declared within_parent, one
  # pupil of one row in each combination. Each school holds every label, so
  # that a school or a label left with one analysed pupil, which the class
  # person of its counts in the analysis sample shows, lost all its other
  # rows, as many as the levels of the other column less one, while rule 1
  # shows the rows without an outcome below k. A label can be left one pupil
  # by losing 3 rows and a school by losing 9, fewer than k, so the findings
  # of outcome.constant_clusters for both are suppressed as a whole whatever
  # the outcome, although they pass the minimum-count rule, and the documents
  # with two, one and no pupils of school S01 without an outcome read alike:
  # no finding then shows the analysis sample, and the design sample writes
  # its levels, 4 schools.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "class", columns = list("class"), role = "cluster", nested_in = "school",
         id_scope = "within_parent"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "class",
         id_scope = "global")),
    observation = list(unit = "pupil", key = list("pupil")))
  data <- expand.grid(class = sprintf("%02d", 1:10), school = sprintf("S%02d", 1:4),
                      stringsAsFactors = FALSE)
  data$pupil <- sprintf("P%03d", 1:40)
  documents <- list()
  for (lacking in 0:2) {
    data$y <- ((1:40 * 7) %% 13) / 4
    data$y[seq_len(lacking)] <- NA
    found <- audit_both(data, "y ~ 1 + (1 | school) + (1 | class)", declaration = declaration,
                        outcome_access = "T1", reason = "Constant classes.")
    for (factor in c("class", "school")) {
      internal <- finding_of(found$internal, "outcome.constant_clusters", factor = factor)
      expect_gte(internal$support$contributors$distinct$value, 10)
      constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = factor)
      expect_identical(constant$status$availability$detail, "decision")
    }
    sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
    expect_identical(written(sizes, "levels"), 4)
    documents[[lacking + 1L]] <- found$shareable$findings
  }
  expect_identical(documents[[1L]], documents[[2L]])
  expect_identical(documents[[1L]], documents[[3L]])
})

# Schools of two pupils with waves rows each, the outcome kept in the waves
# observed of the schools analysed and, with constant TRUE, the same in every
# row of school s01.
small_sample <- function(schools, waves, analysed, observed = 1L, constant = FALSE) {
  school <- rep(sprintf("s%02d", seq_len(schools)), each = 2L * waves)
  wave <- rep(seq_len(waves), 2L * schools)
  y <- (seq_along(school) * 5L) %% 13L + 0.25
  if (constant) {
    y[school == "s01"] <- 0.25
  }
  y[!(wave %in% observed & school %in% sprintf("s%02d", analysed))] <- NA
  data <- data.frame(y = y, x = (seq_along(school) * 7L) %% 11L + 0.5, school = school,
                     pupil = rep(sprintf("p%02d", seq_len(2L * schools)), each = waves),
                     stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  audit_both(data, "y ~ x + (1 | school)", declaration = declaration, outcome_access = "T1",
             reason = "Constant.")
}

test_that("a T1 finding below the minimum count with fewer than k rows is suppressed", {
  # 6 schools of 2 pupils, one row each, and the outcome of school s01 alone.
  # outcome.constant_clusters writes multi_row_levels 1 non_person, which
  # shows two analysed pupils or more, and the 12 pupils of the design
  # sample written beside it would show that rule 1 did not fire, so that
  # the analysed pupils are at most 12 - 10 = 2, and 10 lack an outcome.
  found <- small_sample(6L, 1L, 1L)
  internal <- finding_of(found$internal, "outcome.constant_clusters", factor = "school")
  expect_identical(internal$statistics$multi_row_levels$count_class, "non_person")
  shared <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(shared$status$availability$detail, "decision")
  # Schools of 2, 2, 2, 2, 2 and 1 pupils, one row each, and a Poisson
  # outcome for the first pupil alone. The 11 written rows of the design
  # sample would leave the analysed rows of outcome.zero_shares, shown below
  # k, the single value 1.
  school <- c(rep(sprintf("s%02d", 1:5), each = 2), "s06")
  count <- c(1, rep(NA, 10))
  data <- data.frame(count = count, x = (seq_along(school) * 7) %% 11 + 0.5, school = school,
                     pupil = sprintf("p%02d", seq_along(school)))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  found <- audit_both(data, "count ~ x + (1 | school)", family = "poisson",
                      declaration = declaration, outcome_access = "T1", reason = "Zeros.")
  shared <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(shared$status$availability$detail, "decision")
  sizes <- finding_of(found$shareable, "structure.cluster_sizes", factor = "school")
  expect_identical(written(sizes, "rows"), 11)
})

test_that("at k = 3 such a finding is suppressed as a whole whatever its rows", {
  # 6 schools of 2 pupils with 4 waves, the outcome of waves 1 to 3 of school
  # s01: 6 analysed rows of 2 pupils. The class non_person of multi_row_levels
  # shows two analysed pupils or more, which beside contributors below 3 are
  # 2, so at k = 3 the finding is suppressed. At k = 4, the contributors can
  # be 2 or 3, and the finding is written with its 6 rows.
  shared <- with_min_count(3L, small_sample(6L, 4L, 1L, 1:3))$shareable
  constant <- finding_of(shared, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$detail, "decision")
  shared <- with_min_count(4L, small_sample(6L, 4L, 1L, 1:3))$shareable
  constant <- finding_of(shared, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$value, "available")
  expect_identical(constant$support$contributors$distinct$availability$detail, "min_count")
  expect_identical(written(constant, "support_rows"), 6)
})

test_that("constant_share does not give back analysed rows below an odd k", {
  # 8 schools of 2 pupils with 2 waves, wave 1 of schools s01 to s04
  # analysed, so 8 analysed rows, and the outcome of s01 constant. Its
  # constant_share of 1/4 would make multi_row_levels a multiple of 4 and the
  # analysed rows at least 8, which beside rows below 9 would be 8. The rows
  # are below k, so the finding is suppressed.
  found <- with_min_count(9L, small_sample(8L, 2L, 1:4, constant = TRUE))
  internal <- finding_of(found$internal, "outcome.constant_clusters", factor = "school")
  expect_identical(written(internal, "constant_share"), 0.25)
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$detail, "decision")
})

test_that("a written part of the analysed levels of a non-person item is suppressed beside the design sample's levels", {
  # 10 subjects who each answer 5 of 10 items, item j alone in condition
  # c_j, and an outcome constant within every item. The end of rule 1 hides
  # the analysed items beside the 10 that kept gives, and constant_levels 10
  # would show that none lacks every outcome. The second table answers
  # items 1 to 9 with the same 50 analysed rows and adds item 10, which 5
  # subjects answer without an outcome.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant"),
    list(name = "item", columns = list("item"), role = "item")),
    observation = list(key = list("subject", "item")))
  make <- function(lost) {
    pairs <- do.call(rbind, lapply(1:10, function(s) {
      data.frame(s = s, j = ((s - 1L + 0:4) %% (if (lost) 9L else 10L)) + 1L)
    }))
    if (lost) {
      pairs <- rbind(pairs, data.frame(s = 1:5, j = 10L))
    }
    data <- data.frame(subject = sprintf("s%02d", pairs$s), item = sprintf("i%02d", pairs$j),
                       cond = sprintf("c%02d", pairs$j), y = pairs$j + 0.25,
                       stringsAsFactors = FALSE)
    data$y[pairs$j == 10L & lost] <- NA
    audit_both(data, "y ~ cond + (1 | subject) + (1 | item)", outcome_access = "T1",
               reason = "Constant items.", declaration = declaration)$shareable
  }
  pair <- lapply(c(FALSE, TRUE), make)
  expect_same_reading(pair[[1L]], pair[[2L]])
  constant <- finding_of(pair[[1L]], "outcome.constant_clusters", factor = "item")
  expect_identical(detail(constant, "constant_levels"), "secondary")
  expect_identical(detail(constant, "multi_row_levels"), "secondary")
})

test_that("events and non_events are suppressed with the analysed rows of a bernoulli outcome", {
  # 10 subjects crossed with 10 items, one row in each combination. Rule 3
  # hides the analysed rows, which the product of the analysed levels would
  # give, and events plus non_events would give them back, so that 60 and 40
  # would show that no outcome is missing. An item can be left one subject
  # by losing 9 rows, so Decisions suppresses its findings as a whole.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant"),
    list(name = "item", columns = list("item"), role = "item")),
    crossings = list(list(units = list("subject", "item"))),
    observation = list(key = list("subject", "item")),
    variables = list(acc = list(role = "outcome", measurement = "binary")))
  make <- function(lacking) {
    data <- expand.grid(item = sprintf("i%02d", 1:10), subject = sprintf("s%02d", 1:10),
                        stringsAsFactors = FALSE)[, c("subject", "item")]
    data$cond <- ifelse(data$item <= "i05", "A", "B")
    data$acc <- as.integer((seq_len(nrow(data)) * 7) %% 10 < 6)
    data$acc[seq_len(lacking)] <- NA
    audit_both(data, "acc ~ cond + (1 | subject) + (1 | item)", outcome_access = "T1",
               reason = "Accuracy.", declaration = declaration)$shareable
  }
  pair <- lapply(0:1, make)
  expect_same_reading(pair[[1L]], pair[[2L]])
  minority <- finding_of(pair[[1L]], "outcome.minority_events", factor = "subject")
  expect_identical(detail(minority, "events"), "secondary")
  expect_identical(detail(minority, "non_events"), "secondary")
  minority <- finding_of(pair[[1L]], "outcome.minority_events", factor = "item")
  expect_identical(minority$status$availability$detail, "decision")
})

test_that("the verdict of outcome.separation stays written beside events hidden with the rows", {
  skip_if_not_installed("lpSolve")
  # 12 subjects crossed with 15 items, one row in each combination, a binary
  # accuracy and two predictors whose values differ between every two rows,
  # in a T2 run. Rule 3 hides the analysed rows, so events and non_events,
  # which add up to them, are suppressed with the detail 'secondary'. Both
  # are 10 or more, and the first rule of the decision shows only that each
  # is at least 1, so the verdict is written, with no outcome missing or 5.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant"),
    list(name = "item", columns = list("item"), role = "item")),
    observation = list(key = list("subject", "item")),
    variables = list(acc = list(role = "outcome", measurement = "binary")))
  data <- expand.grid(item = sprintf("i%02d", 1:15), subject = sprintf("s%02d", 1:12),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  n <- nrow(data)
  data$x1 <- ((seq_len(n) * 37) %% 101) / 10
  data$x2 <- ((seq_len(n) * 53) %% 97) / 10
  for (lacking in c(0L, 5L)) {
    data$acc <- as.integer(((seq_len(n) * 7919) %% 13) < 7)
    data$acc[seq_len(lacking)] <- NA
    found <- audit_both(data, "acc ~ x1 + x2 + (1 | subject) + (1 | item)",
                        outcome_access = "T2", exploratory = TRUE, reason = "Accuracy.",
                        declaration = declaration)
    internal <- finding_of(found$internal, "outcome.separation")
    expect_gte(min(written(internal, "events"), written(internal, "non_events")), 10)
    separation <- finding_of(found$shareable, "outcome.separation")
    expect_identical(separation$status$availability$value, "available")
    expect_identical(written(separation, "verdict"), written(internal, "verdict"))
    expect_identical(detail(separation, "events"), "secondary")
    expect_identical(detail(separation, "non_events"), "secondary")
  }
})

# Schools of two pupils with two rows each, the outcome kept in the rows of
# the first analysed pupils.
small_pupils <- function(pupils, analysed, family = "gaussian", formula = NULL) {
  pupil <- rep(sprintf("p%02d", seq_len(pupils)), each = 2L)
  school <- rep(sprintf("s%02d", (seq_len(pupils) + 1L) %/% 2L), each = 2L)
  y <- if (family == "poisson") rep(c(0, 1, 2, 3, 1, 4, 2), length.out = 2L * pupils) else
    round(sin(seq_along(pupil)) * 3, 2) + 0.001
  y[pupil > sprintf("p%02d", analysed)] <- NA
  data <- data.frame(y = y, x = (seq_along(pupil) * 7) %% 11 + 0.5, school = school,
                     pupil = pupil, stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "school",
         id_scope = "global")))
  audit_both(data, formula %||% "y ~ x + (1 | school)",
             family = if (family == "poisson") "poisson", declaration = declaration,
             outcome_access = "T1", reason = "Small samples.")
}

test_that("findings below the minimum count are suppressed when written values bound their contributors by k - 1", {
  # At k = 3, 2 analysed pupils of one school: the class non_person of the
  # levels of outcome.zero_shares for school shows two analysed pupils or
  # more, which beside contributors below 3 are 2. The findings on the
  # analysis sample share its contributors, so outcome.zero_shares for
  # pupil, whose counts are person counts, is suppressed too.
  shared <- with_min_count(3L, small_pupils(7L, 2L, "poisson",
                                            "y ~ x + (1 | school) + (1 | pupil)"))$shareable
  for (factor in c("school", "pupil")) {
    zeros <- finding_of(shared, "outcome.zero_shares", factor = factor)
    expect_identical(zeros$status$availability$detail, "decision")
  }
  # At k = 4, 3 analysed pupils of two rows each: `dominated` false shows
  # more than two contributors, which beside contributors below 4 are 3.
  found <- with_min_count(4L, small_pupils(7L, 3L, "poisson"))
  internal <- finding_of(found$internal, "outcome.zero_shares", factor = "school")
  expect_false(internal$support$contributors$dominated)
  zeros <- finding_of(found$shareable, "outcome.zero_shares", factor = "school")
  expect_identical(zeros$status$availability$detail, "decision")
  # At k = 5, 4 analysed pupils in 2 schools: multi_row_levels 2 non_person
  # of outcome.constant_clusters, with each pupil in one school, shows 4
  # analysed pupils or more, which beside contributors below 5 are 4. At
  # k = 6, they can be 4 or 5, and the finding is written with its 8 rows.
  found <- with_min_count(5L, small_pupils(10L, 4L))
  internal <- finding_of(found$internal, "outcome.constant_clusters", factor = "school")
  expect_identical(written(internal, "multi_row_levels"), 2)
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$detail, "decision")
  shared <- with_min_count(6L, small_pupils(10L, 4L))$shareable
  constant <- finding_of(shared, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$value, "available")
  expect_identical(constant$support$contributors$distinct$availability$detail, "min_count")
  expect_identical(written(constant, "support_rows"), 8)
})

test_that("a part of 0 of the hidden analysed levels of a non-person item stays written", {
  # 10 subjects who each answer 4 of 5 items, item j alone in condition c_j,
  # and an outcome that varies within every item. The end of rule 1 hides
  # the analysed items beside the 5 that kept gives, and the message
  # none_constant shows constant_levels to be 0, which bounds nothing.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant"),
    list(name = "item", columns = list("item"), role = "item")),
    observation = list(key = list("subject", "item")))
  pairs <- do.call(rbind, lapply(1:10, function(s) data.frame(s = s, j = ((s - 1L + 0:3) %% 5L) + 1L)))
  data <- data.frame(subject = sprintf("s%02d", pairs$s), item = sprintf("i%02d", pairs$j),
                     cond = sprintf("c%02d", pairs$j), y = pairs$j + 0.25 + pairs$s * 0.01,
                     stringsAsFactors = FALSE)
  shared <- audit_both(data, "y ~ cond + (1 | subject) + (1 | item)", outcome_access = "T1",
                       reason = "Constant items.", declaration = declaration)$shareable
  constant <- finding_of(shared, "outcome.constant_clusters", factor = "item")
  expect_identical(constant$message$id, "none_constant")
  expect_identical(written(constant, "constant_levels"), 0)
  expect_identical(detail(constant, "multi_row_levels"), "secondary")
})

test_that("a part of the hidden analysed levels is written when the design sample's levels exceed it by k", {
  # 10 subjects who each answer 5 of 12 items, item j alone in condition c_j,
  # and an outcome constant within the first 2 or 3 items. The end of rule 1
  # hides the 12 analysed items beside the 12 that kept gives. constant_levels
  # 3 lies k - 1 below them and is suppressed, and 2 lies k below and is
  # written.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant"),
    list(name = "item", columns = list("item"), role = "item")),
    observation = list(key = list("subject", "item")))
  pairs <- do.call(rbind, lapply(1:10, function(s) data.frame(s = s, j = ((s - 1L + 0:4) %% 12L) + 1L)))
  for (constant in 2:3) {
    data <- data.frame(subject = sprintf("s%02d", pairs$s), item = sprintf("i%02d", pairs$j),
                       cond = sprintf("c%02d", pairs$j),
                       y = pairs$j + 0.25 + ifelse(pairs$j <= constant, 0, pairs$s * 0.01),
                       stringsAsFactors = FALSE)
    found <- audit_both(data, "y ~ cond + (1 | subject) + (1 | item)", outcome_access = "T1",
                        reason = "Constant items.", declaration = declaration)
    internal <- finding_of(found$internal, "outcome.constant_clusters", factor = "item")
    expect_identical(written(internal, "constant_levels"), as.numeric(constant))
    expect_identical(written(internal, "multi_row_levels"), 12)
    shared <- finding_of(found$shareable, "outcome.constant_clusters", factor = "item")
    expect_identical(detail(shared, "multi_row_levels"), "secondary")
    if (constant == 3L) {
      expect_identical(detail(shared, "constant_levels"), "secondary")
    } else {
      expect_identical(written(shared, "constant_levels"), 2)
    }
  }
})

test_that("the rows of a level without a member count towards its loss to one member", {
  # 10 class labels reused in 10 schools, one pupil of one row in each
  # combination, and in every school a further row of class 01 without a
  # pupil. A school holds 11 rows, and losing those of 9 pupils, fewer than
  # k, leaves it one pupil and the row without one, so the findings for
  # school are suppressed as a whole.
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "class", columns = list("class"), role = "cluster", nested_in = "school",
         id_scope = "within_parent"),
    list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "class",
         id_scope = "global")),
    observation = list(unit = "pupil", key = list("pupil")))
  data <- expand.grid(class = sprintf("%02d", 1:10), school = sprintf("S%02d", 1:10),
                      stringsAsFactors = FALSE)
  data$pupil <- sprintf("P%03d", 1:100)
  data <- rbind(data, data.frame(class = "01", school = sprintf("S%02d", 1:10), pupil = NA))
  data$y <- round(sin(seq_len(nrow(data))) * 3, 2)
  found <- audit_both(data, "y ~ 1 + (1 | school) + (1 | class)", declaration = declaration,
                      outcome_access = "T1", reason = "Constant classes.")
  internal <- finding_of(found$internal, "outcome.constant_clusters", factor = "school")
  expect_gte(internal$support$contributors$distinct$value, 10)
  constant <- finding_of(found$shareable, "outcome.constant_clusters", factor = "school")
  expect_identical(constant$status$availability$detail, "decision")
})
