# The outcome checks, in the parts that the audit corpus cannot reach: how
# they read the outcome, counts of binomial outcomes over many levels,
# decimal bounds, and the solver of outcome.separation: its failure, which
# gives the message no_solution, the verification of its solutions, the
# program solved itself when its dual fails, rounding residues, the 2,000
# rows of the review of registry 0.1.0, tables of the benchmark that chose
# the formulation and the solver's absence.

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
  local_seed(7)
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
  local_mocked_bindings(separation_solver = function(...) NULL)
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
  # A returned b that violates a constraint by more than
  # feasibility_tolerance is not verified, from the dual or the program.
  local_mocked_bindings(separation_solver = function(formulation, a, objective, ...) {
    c(1e-6, numeric(length(objective) - 1L))
  })
  expect_identical(separation_finding(alternating())$message$id, "no_solution")
})

test_that("a program whose dual has no verified solution is solved itself", {
  skip_if_not_installed("lpSolve")
  solver <- separation_solver
  for (failure in list(NULL, c(1e-6, 0))) {
    formulations <- character(0)
    local_mocked_bindings(separation_solver = function(formulation, ...) {
      formulations <<- c(formulations, formulation)
      if (formulation == "dual") failure else solver(formulation, ...)
    })
    values <- outcome_statistics(separation_finding(separated()))
    expect_identical(values$verdict, "complete")
    expect_identical(formulations, rep(c("dual", "primal"), 6L))
    # Complete separation by 'x', scaled to -1 to 1: b = (0, 1) gives the
    # margin 1/3, and every b_1 from -1/3 to 1/3 with b_2 = 1 the optimum 4.
    expect_equal(values$margin, 1 / 3, tolerance = 1e-12)
    expect_equal(values$optimum, 4, tolerance = 1e-12)
    expect_equal(unlist(values$bounds), c(-1 / 3, 1 / 3, 1 - 1e-6 / 4, 1), tolerance = 1e-9)
  }
  # The dual and the program itself give the same values.
  expect_identical(outcome_statistics(separation_finding(separated()))[c("verdict", "columns")],
                   list(verdict = "complete", columns = 2))
})

test_that("rounding residues leave a finding clear and larger violations make it near_threshold", {
  skip_if_not_installed("lpSolve")
  # For the alternating data, b = (e, 0) gives u = -e for each non-event.
  with_offset <- function(e) {
    local_mocked_bindings(separation_solver = function(formulation, a, objective, ...) {
      c(e, numeric(length(objective) - 1L))
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
  # The dual of the first and of the second program succeed, then neither
  # the dual nor the program of the first bound gives a solution.
  local_mocked_bindings(separation_solver = function(...) {
    calls <<- calls + 1L
    if (calls > 2L) NULL else solver(...)
  })
  found <- separation_finding(separated())
  values <- outcome_statistics(found)
  expect_identical(calls, 4L)
  expect_identical(values$verdict, "complete")
  expect_null(values$bounds)
  expect_null(values$columns_involved)
  expect_identical(found$message$text, paste(
    "The fixed effects separate the events from the non-events completely, so the estimates of",
    "some coefficients diverge and their Wald statistics are unreliable."))
})

test_that("outcome.separation names lpSolve whenever it is available, and is not available without it", {
  skip_if_not_installed("lpSolve")
  packages <- list(lpSolve = getNamespaceVersion("lpSolve")[[1L]])
  for (y in list(c(0, 0, 0, 1, 1, 1), rep(0, 6))) {
    data <- data.frame(y = y, x = c(-3, -2, -1, 1, 2, 3))
    results <- audit(data, "y ~ x", family = "binomial", outcome_access = "T2",
                     reason = "Test.", exploratory = TRUE, privacy = "internal", key = outcome_key)
    expect_identical(results$document$software$packages, packages)
  }
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
  # table, and the other events above and non-events below 0.5. The dual
  # returns b = 0 for g = 1e-8, as HiGHS does, and lpSolve reports no
  # optimum for the dual for g = 1e-9, whose program itself reaches an
  # optimum near 500 through violations of g.
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

# Tables of the benchmark that chose the formulation of outcome.separation
# (03-execution-plan.md, M2, M2b-2), generated as there: x1 to x11 standard
# normal rounded to 6 decimals, the factors f, with 3 levels for S7 and 4
# otherwise, and h, with 5 levels, a grouping column and, for the class
# binomial, trials from 1 to 6. The formulation of the build of M2b-2
# reported no optimum for some program of each of them.
benchmark_table <- function(seed, structure, type, binomial = FALSE, n = 200) {
  local_seed(seed)
  d <- data.frame(row = seq_len(n))
  for (j in 1:11) d[[paste0("x", j)]] <- round(rnorm(n), 6)
  d$f <- sample(letters[seq_len(if (structure == "S7") 3 else 4)], n, replace = TRUE)
  d$h <- sample(c("p", "q", "r", "s", "t"), n, replace = TRUE)
  d$g <- sprintf("g%03d", sample.int(max(5, n %/% 20), n, replace = TRUE))
  m <- if (binomial) sample(1:6, n, replace = TRUE) else rep(1L, n)
  mild <- 0.6 * d$x1 - 0.4 * d$x2 + 0.3 * (d$f == "b") - 0.2 * (d$h == "q")
  if (type == "none") {
    k <- rbinom(n, m, plogis(mild))
  } else if (type == "complete") {
    # S7: x1 x2 + 0.2 x1 above its median.
    z <- d$x1 * d$x2 + 0.2 * d$x1
    k <- ifelse(z - median(z) > 0, m, 0L)
  } else if (structure == "S4") {
    # Only events at the level 'r' of h.
    k <- rbinom(n, m, plogis(mild))
    k[d$h == "r"] <- m[d$h == "r"]
  } else {
    # S8: events above the median of x1 on a grid of integers, non-events
    # below it, both at the median.
    d$x1 <- round(d$x1 * 2)
    t <- d$x1 - median(d$x1)
    k <- ifelse(t > 0, m, ifelse(t < 0, 0L, rbinom(n, m, 0.5)))
  }
  d$y <- as.integer(if (binomial) k else k > 0)
  d$n <- as.integer(m)
  d
}

benchmark_finding <- function(data, formula, binomial = FALSE) {
  declaration <- if (binomial) {
    list(vocabulary = "0.1.0", variables = list(
      y = list(role = "outcome", measurement = "binomial", trials = "n")))
  }
  outcome_findings(data, formula, "outcome.separation", tier = "T2", family = "binomial",
                   declaration = declaration)[[1L]]
}

test_that("outcome.separation agrees with HiGHS on tables of its benchmark", {
  skip_if_not_installed("lpSolve")
  # The values of HiGHS through scipy.optimize.linprog() with method
  # 'highs-ds' and feasibility tolerances 1e-9 on the same programs.
  x11 <- paste("y ~", paste0("x", 1:11, collapse = " + "))
  cases <- list(
    list(1028, "S4", "none", TRUE, "y ~ x1 + x2 + x3 + f + h", "none", 0, 0, NULL),
    list(1031, "S4", "quasi", FALSE, "y ~ x1 + x2 + x3 + f + h", "quasi", 47, 0, "h[r]"),
    list(1061, "S7", "complete", FALSE, "y ~ x1 * x2 + f", "complete", 23.9130217356076,
         0.000741775070744744, c("(Intercept)", "x1", "x2", "f[b]", "f[c]", "x1:x2")),
    list(1067, "S8", "quasi", FALSE, x11, "quasi", 59.1666666666667, 0, "x1")
  )
  for (case in cases) {
    data <- benchmark_table(case[[1L]], case[[2L]], case[[3L]], binomial = case[[4L]])
    found <- benchmark_finding(data, case[[5L]], binomial = case[[4L]])
    values <- outcome_statistics(found)
    label <- paste(case[[1L]], case[[2L]], case[[3L]])
    expect_identical(values$verdict, case[[6L]], label = label)
    expect_identical(found$status$threshold_proximity$value, "clear", label = label)
    expect_lte(abs(values$optimum - case[[7L]]), 1e-6 * max(1, case[[7L]]), label = label)
    expect_lte(abs(values$margin - case[[8L]]), 1e-6, label = label)
    expect_identical(unlist(values$columns_involved), case[[9L]], label = label)
  }
})
