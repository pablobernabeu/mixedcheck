# The design checks, in the parts that the audit corpus cannot reach: the
# generalised variance inflation factor against its definition as a ratio of
# determinants on designs of more terms and levels, the condition number and
# standard deviations against base R, these values at extreme magnitudes,
# empty cells of three factors and the estimands that /provenance/inferred
# marks.

design_key <- paste(sprintf("%02x", 0:31), collapse = "")

# The findings of one check for an audit in internal mode.
design_findings <- function(data, formula, check, ...) {
  results <- audit(data, formula, ..., privacy = "internal", key = design_key)
  Filter(function(finding) finding$check == check, results$document$findings)
}

design_values <- function(finding) {
  lapply(finding$statistics, function(statistic) statistic$value)
}

# A design of 60 rows with two correlated numeric predictors, a factor of
# four levels and a factor of three levels.
collinear_data <- function(seed) {
  local_seed(seed)
  n <- 60
  a <- sample(c("A1", "A2", "A3", "A4"), n, replace = TRUE)
  b <- sample(c("B1", "B2", "B3"), n, replace = TRUE)
  x1 <- rnorm(n) + (a == "A2") * 1.5
  x2 <- 0.7 * x1 + rnorm(n, sd = 0.6) + (b == "B3")
  data.frame(y = rnorm(n), x1 = x1, x2 = x2, a = a, b = b, stringsAsFactors = FALSE)
}

test_that("design.collinearity gives det(R_TT) det(R_OO) / det(R) for each main-effect term", {
  for (seed in 1:3) {
    data <- collinear_data(seed)
    findings <- design_findings(data, "y ~ x1 + a + x2 + b + x1:b", "design.collinearity")
    expect_identical(vapply(findings, function(f) f$scope$term, ""), c("a", "b", "x1", "x2"))
    # The definition with the columns of the main-effect terms coded by
    # treatment contrasts and base R's correlations and determinants.
    columns <- cbind(x1 = data$x1, model.matrix(~ a, data)[, -1L], x2 = data$x2,
                     model.matrix(~ b, data)[, -1L])
    owner <- c("x1", "a", "a", "a", "x2", "b", "b")
    r <- stats::cor(columns)
    for (finding in findings) {
      own <- owner == finding$scope$term
      expected <- det(r[own, own, drop = FALSE]) * det(r[!own, !own, drop = FALSE]) / det(r)
      values <- design_values(finding)
      expect_equal(values$gvif, expected, tolerance = 1e-10)
      expect_identical(values$df, as.double(sum(own)))
      expect_equal(values$gvif_per_df, expected^(1 / sum(own)), tolerance = 1e-10)
    }
  }
})

test_that("design.collinearity does not change with the contrasts or the order of the terms", {
  data <- collinear_data(11)
  value <- function(formula, term, ...) {
    findings <- design_findings(data, formula, "design.collinearity", ...)
    design_values(Filter(function(f) f$scope$term == term, findings)[[1L]])$gvif
  }
  reference <- value("y ~ x1 + a + x2", "a")
  expect_equal(value("y ~ x1 + a + x2", "a", coding = list(a = list(contrast = "sum"))),
               reference, tolerance = 1e-12)
  expect_equal(value("y ~ a + x2 + x1", "a"), reference, tolerance = 1e-12)
  expect_equal(value("y ~ 0 + x1 + a + x2", "a"), reference, tolerance = 1e-12)
})

test_that("design.scale_disparity agrees with base R's standard deviations and condition number", {
  local_seed(3)
  data <- data.frame(y = rnorm(50), x1 = rnorm(50, sd = 20), x2 = runif(50) / 50,
                     d = rbinom(50, 1, 0.5), a = rep(c("A", "B"), 25))
  found <- design_findings(data, "y ~ x1 * x2 + d + a", "design.scale_disparity")[[1L]]
  values <- design_values(found)
  expect_identical(values$scaled_columns, list("x1", "x2", "x1:x2"))
  deviations <- c(stats::sd(data$x1), stats::sd(data$x2), stats::sd(data$x1 * data$x2))
  expect_equal(values$sd_largest, max(deviations), tolerance = 1e-12)
  expect_equal(values$sd_smallest, min(deviations), tolerance = 1e-12)
  expect_equal(values$sd_ratio, max(deviations) / min(deviations), tolerance = 1e-12)
  x <- model.matrix(~ x1 * x2 + d + a, data)
  x <- sweep(x, 2L, sqrt(colSums(x^2)), "/")
  expect_equal(values$condition_number, kappa(x, exact = TRUE), tolerance = 1e-10)
  expect_identical(found$message$id, "disparate")
})

test_that("design.collinearity and design.scale_disparity hold at extreme magnitudes", {
  # Each column is divided by its largest absolute value before any sum or
  # product, so that columns near 1e300 or 1e-300 give the values of the
  # same data at unit scale, multiplied by the scale for the standard
  # deviations.
  local_seed(21)
  z <- rnorm(40L)
  base <- data.frame(y = rnorm(40L), x = z + rnorm(40L), z = z, g = rep(sprintf("g%d", 1:8), 5L))
  findings <- function(data) {
    results <- audit(data, "y ~ x + z + (1 | g)", privacy = "internal", key = design_key)
    found <- Filter(function(finding) finding$check %in% c("design.collinearity",
                                                           "design.scale_disparity"),
                    results$document$findings)
    lapply(found, design_values)
  }
  reference <- findings(base)
  for (scale in c(1e-300, 1e-100, 1e100, 1e300)) {
    data <- base
    data$x <- base$x * scale
    found <- findings(data)
    for (i in 1:2) {
      expect_equal(found[[i]]$gvif, reference[[i]]$gvif, tolerance = 1e-12, label = paste(scale, i))
    }
    expect_equal(found[[3L]]$condition_number, reference[[3L]]$condition_number, tolerance = 1e-12)
    deviation <- if (scale > 1) found[[3L]]$sd_largest else found[[3L]]$sd_smallest
    expect_equal(deviation / scale, column_sd(base$x), tolerance = 1e-12, label = paste(scale))
  }
})

test_that("column_sd sums the squared differences exactly", {
  # The squares 2^-64 of the last 2^16 values are each below half a unit of
  # the last place of 2 in a long double, so that sum() loses them and gives
  # 2, whereas their exact sum adds 2^-48 and moves the result by 6 units of
  # the last place.
  t <- 2^-32
  x <- c(1, -1, rep(c(t, -t), 2^15))
  n <- length(x)
  expect_identical(column_sd(x), sqrt((2 + 2^-48) / (n - 1)))
  expect_false(identical(column_sd(x), sqrt(2 / (n - 1))))
})

test_that("design.rank_deficiency counts empty cells of factors only", {
  data <- data.frame(
    y = 1:12,
    a = rep(c("A1", "A2"), each = 6),
    b = rep(c("B1", "B2", "B3"), 4),
    c = rep(c("C1", "C1", "C2"), 4),
    x = c(1, 4, 2, 5, 3, 6, 2, 7, 1, 8, 9, 3)
  )
  found <- design_findings(data, "y ~ a * b * c + b:x", "design.rank_deficiency")[[1L]]
  values <- design_values(found)
  # a:b has every cell. a:c and b:c lack A?:C2 with B1 or B2 and B3 with C1,
  # and a:b:c sums those of all three factors. b:x is left out.
  levels <- function(...) length(unique(paste(...)))
  expected <- (2 * 3 - levels(data$a, data$b)) + (2 * 2 - levels(data$a, data$c)) +
    (3 * 2 - levels(data$b, data$c)) + (2 * 3 * 2 - levels(data$a, data$b, data$c))
  expect_identical(values$empty_cells, expected)
  expect_gt(expected, 0)
})

test_that("an estimand that /provenance/inferred lists counts as absent", {
  data <- data.frame(y = c(1.2, 2.9, 3.1, 4.8, 4.4, 6.5), x1 = 1:6, x2 = c(2, 0, 1, 3, 1, 2),
                     x3 = c(3, 2, 4, 7, 6, 8))
  declaration <- list(vocabulary = "0.1.0",
                      estimands = list(list(id = "slope", term = "x1", kind = "association")))
  found <- design_findings(data, "y ~ x1 + x2 + x3", "design.rank_deficiency",
                           declaration = declaration)[[1L]]
  expect_identical(found$message$id, "nonfocal")
  # Without the estimand, every term is focal and x3 makes it consequential.
  declaration$provenance <- list(inferred = list("/estimands/0"))
  found <- design_findings(data, "y ~ x1 + x2 + x3", "design.rank_deficiency",
                           declaration = declaration)[[1L]]
  expect_identical(found$message$id, "focal")
  expect_true(design_values(found)$focal_dropped)
  # An inferred focal member counts as absent, so the estimand is focal.
  declaration$estimands[[1L]]$term <- "x3"
  declaration$estimands[[1L]]$focal <- FALSE
  declaration$provenance <- list(inferred = list("/estimands/0/focal"))
  found <- design_findings(data, "y ~ x1 + x2 + x3", "design.rank_deficiency",
                           declaration = declaration)[[1L]]
  expect_identical(found$message$id, "focal")
})

test_that("the residuals of the sequential rule are the norms it compares", {
  local_seed(5)
  x <- cbind(rnorm(30), rnorm(30), 0, rnorm(30))
  x <- cbind(x, x[, 1L] + 2 * x[, 2L])
  found <- sequential_residuals(x)
  expect_identical(found$kept, sequential_rule(x))
  expect_identical(found$kept, c(TRUE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(found$residual[3L], 0)
  scaled <- x[, 2L] / max(abs(x[, 2L]))
  first <- x[, 1L] / sqrt(sum(x[, 1L]^2))
  expect_equal(found$residual[2L], sqrt(sum((scaled - sum(scaled * first) * first)^2)),
               tolerance = 1e-12)
  expect_lt(found$residual[5L], 1e-12)
})

test_that("every check of the registry has its function, and an entry without one is an internal error", {
  ids <- names(registry_entries_by_id())
  expect_length(ids, 24L)
  expect_true(all(vapply(ids, function(id) !is.null(check_implementation(id)), NA)))
  run <- new.env()
  run$family_class <- "gaussian"
  entry <- registry_entry("design.rank_deficiency")
  entry$id <- "design.no_such_check"
  expect_error(run_check(run, entry),
               "Internal error: the check design.no_such_check has no function")
})
