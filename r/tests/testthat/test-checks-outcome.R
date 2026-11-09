# The outcome checks, in the parts that the audit corpus cannot reach: how
# they read the outcome, counts of binomial outcomes over many levels,
# decimal bounds, and the solver of outcome.separation: its failure, which
# gives the message no_solution, the verification of its solutions, rounding
# residues, the 2,000 rows of the review of registry 0.1.0 and its absence.

outcome_key <- paste(sprintf("%02x", 0:31), collapse = "")

# The findings of one check for an audit in internal mode at a tier.
outcome_findings <- function(data, formula, check, tier = "T1", ...) {
  results <- audit(data, formula, ..., outcome_access = tier, reason = "Test.",
                   exploratory = tier == "T2", privacy = "internal", key = outcome_key)
  Filter(function(finding) finding$check == check, results$document$findings)
}

outcome_statistics <- function(finding) {
  lapply(finding$statistics, function(statistic) statistic$value)
}

# The finding of outcome.separation for y ~ x with the family binomial.
separation_finding <- function(data, formula = "y ~ x") {
  outcome_findings(data, formula, "outcome.separation", tier = "T2", family = "binomial")[[1L]]
}

alternating <- function() {
  data.frame(y = c(0, 1, 0, 1, 0, 1), x = c(-2, -1, 0, 1, 2, 3))
}

separated <- function() {
  data.frame(y = c(0, 0, 0, 1, 1, 1), x = c(-3, -2, -1, 1, 2, 3))
}

test_that("a check reads the outcome only at a tier that its entry states and the run reached", {
  run <- new.env()
  run$tier <- "T1"
  run$analysis <- 1:3
  expect_error(outcome_values(run, list(id = "a.t0", tier = "T0")), "Internal error")
  expect_error(outcome_values(run, list(id = "a.t2", tier = "T2")), "Internal error")
  run$analysis <- NULL
  expect_error(outcome_values(run, list(id = "a.t1", tier = "T1")), "Internal error")
  # Step 13 refuses an access log without an entry for a column read.
  run$outcome_reads <- list(list(tier = "T2", columns = c("k", "n")))
  logged <- list(list(tier = "T0"), list(tier = "T2", outcome = list(column = "k")))
  expect_error(outcome_reads_logged(run, logged), "access log does not record")
  logged[[3L]] <- list(tier = "T2", outcome = list(column = "n"))
  expect_true(outcome_reads_logged(run, logged))
})

test_that("the minority events and constant levels of a binomial outcome are counted by level", {
  set.seed(7)
  subject <- rep(sprintf("s%02d", 1:30), each = 3)
  n <- sample(1:4, length(subject), replace = TRUE)
  k <- rbinom(length(n), n, rep(c(0, 0.5, 1, 0.3, 0.7), 6)[match(subject, unique(subject))])
  data <- data.frame(k = k, n = n, x = seq_along(k), subject = subject)
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")))
  formula <- "k ~ x + (1 | subject)"
  minority <- outcome_findings(data, formula, "outcome.minority_events",
                               declaration = declaration)[[1L]]
  values <- outcome_statistics(minority)
  events <- tapply(k, subject, sum)
  non_events <- tapply(n - k, subject, sum)
  level_minority <- pmin(events, non_events)
  expect_identical(values$events, sum(as.double(k)))
  expect_identical(values$non_events, sum(as.double(n - k)))
  expect_identical(values$levels, 30)
  expect_identical(values$levels_without_minority, as.double(sum(level_minority == 0)))
  expect_identical(values$median_minority, as.double(sort(level_minority)[15L]))
  expect_identical(minority$statistics$median_minority$quantile[c("p", "n")],
                   list(p = 0.5, n = 30))
  expect_equal(values$events_per_column, min(sum(k), sum(n - k)) / 2)
  constant <- outcome_findings(data, formula, "outcome.constant_clusters",
                               declaration = declaration)[[1L]]
  expected <- sum(tapply(k == 0, subject, all) | tapply(k == n, subject, all))
  expect_identical(outcome_statistics(constant)$constant_levels, as.double(expected))
  expect_identical(outcome_statistics(constant)$multi_row_levels, 30)
})

test_that("outcome.boundary_shares compares with the doubles nearest to decimal bounds", {
  data <- data.frame(score = c(0.5, 0.5, 9.5, 3, 4.25, 9.5, 9.5, 2), x = 1:8)
  declaration <- list(vocabulary = "0.1.0", variables = list(
    score = list(role = "outcome", measurement = "bounded_score", bounds = list(0.5, 9.5))))
  found <- outcome_findings(data, "score ~ x", "outcome.boundary_shares",
                            declaration = declaration)[[1L]]
  values <- outcome_statistics(found)
  expect_identical(c(values$at_floor, values$at_ceiling), c(2, 3))
  expect_identical(found$message$id, "at_bounds")
  # A measurement that /provenance/inferred lists counts as absent.
  declaration$provenance <- list(inferred = list("/variables/score/measurement"))
  found <- outcome_findings(data, "score ~ x", "outcome.boundary_shares",
                            declaration = declaration)[[1L]]
  expect_identical(found$status$availability$reason, "declaration_missing")
})

test_that("outcome.separation reports no_solution when the solver gives no optimum", {
  skip_if_not_installed("lpSolve")
  local_mocked_bindings(separation_solver = function(...) list(status = 2L, solution = numeric(0)))
  found <- separation_finding(separated())
  expect_identical(found$message, list(id = "no_solution", text = paste(
    "The solver gave no verified optimum of the linear programs, so separation could not be",
    "assessed.")))
  expect_identical(found$status$finding$value, "consistent")
  expect_identical(found$status$assessability[c("value", "reason", "detail")],
                   list(value = "not_assessable", reason = "prerequisite_unmet",
                        detail = "verified_solution"))
  values <- outcome_statistics(found)
  expect_null(values$verdict)
  expect_null(values$optimum)
  expect_null(values$margin)
  expect_identical(values$columns, 2)
})

test_that("outcome.separation verifies each solution in double arithmetic", {
  skip_if_not_installed("lpSolve")
  # A returned c whose b violates a constraint by more than
  # feasibility_tolerance is not verified.
  local_mocked_bindings(separation_solver = function(direction, objective, ...) {
    list(status = 0L, solution = c(1 + 1e-6, 1, numeric(length(objective) - 2L)))
  })
  expect_identical(separation_finding(alternating())$message$id, "no_solution")
})

test_that("rounding residues leave a finding clear and larger violations make it near_threshold", {
  skip_if_not_installed("lpSolve")
  # For the alternating data, b = (e, 0) gives u = -e for each non-event.
  with_offset <- function(e) {
    local_mocked_bindings(separation_solver = function(direction, objective, ...) {
      list(status = 0L, solution = c(1 + e, 1, numeric(length(objective) - 2L)))
    })
    separation_finding(alternating())
  }
  for (e in c(0, 2e-13, 9e-12)) {
    found <- with_offset(e)
    expect_identical(found$status$threshold_proximity$value, "clear", label = format(e))
    expect_identical(outcome_statistics(found)$verdict, "none")
  }
  for (e in c(1.1e-11, 1e-9, 9e-8)) {
    found <- with_offset(e)
    expect_identical(found$status$threshold_proximity$value, "near_threshold", label = format(e))
  }
})

test_that("a bound program without a verified solution leaves the bounds absent", {
  skip_if_not_installed("lpSolve")
  solver <- separation_solver
  calls <- 0L
  local_mocked_bindings(separation_solver = function(...) {
    calls <<- calls + 1L
    if (calls > 2L) list(status = 5L, solution = numeric(0)) else solver(...)
  })
  found <- separation_finding(separated())
  values <- outcome_statistics(found)
  expect_identical(values$verdict, "complete")
  expect_null(values$bounds)
  expect_null(values$columns_involved)
  expect_identical(found$message$text, paste(
    "The fixed effects separate the events from the non-events completely, so the estimates of",
    "some coefficients diverge and their Wald statistics are unreliable."))
})

test_that("outcome.separation names lpSolve, and is not available without it", {
  skip_if_not_installed("lpSolve")
  results <- audit(separated(), "y ~ x", family = "binomial", outcome_access = "T2",
                   reason = "Test.", exploratory = TRUE, privacy = "internal", key = outcome_key)
  expect_identical(results$document$software$packages,
                   list(lpSolve = getNamespaceVersion("lpSolve")[[1L]]))
  # Without kept columns, the only solution is b = () and the verdict none.
  data <- data.frame(y = c(1, 0, 1, 0, 1, 1), g = c("a", "a", "b", "b", "c", "c"))
  values <- outcome_statistics(separation_finding(data, "y ~ 0 + (1 | g)"))
  expect_identical(values[c("columns", "verdict", "optimum", "margin")],
                   list(columns = 0, verdict = "none", optimum = 0, margin = 0))
  local_mocked_bindings(package_installed = function(package) package != "lpSolve")
  found <- separation_finding(separated())
  expect_identical(found$status$availability[c("value", "reason", "detail")],
                   list(value = "not_available", reason = "package_missing", detail = "lpSolve"))
})

test_that("on 2,000 rows that only b = 0 separates, a violating solution is near_threshold", {
  skip_if_not_installed("lpSolve")
  # One event and one non-event a gap g apart around 0.5, first in the
  # table, and the other events above and non-events below 0.5.
  for (g in c(1e-8, 1e-9)) {
    data <- data.frame(
      y = c(1, 0, rep(0, 999), rep(1, 999)),
      x = c(0.5 - g, 0.5 + g, seq(0.0005, 0.4995, length.out = 999),
            seq(0.5005, 0.9995, length.out = 999))
    )
    found <- separation_finding(data)
    values <- outcome_statistics(found)
    expect_true(identical(values$verdict, "none") ||
                  found$status$threshold_proximity$value == "near_threshold", label = format(g))
  }
})

test_that("every outcome check has its function", {
  ids <- grep("^outcome[.]", names(registry_entries_by_id()), value = TRUE)
  expect_length(ids, 5L)
  expect_true(all(ids %in% implemented_checks()))
})
