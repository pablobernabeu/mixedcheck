# The identifiability checks, in the parts that the audit corpus cannot
# reach: the Gram matrix against its definition on dense matrices, at
# extreme magnitudes and in chunks of levels, the proximity band of
# rank_tolerance, the limits of max_z_columns and max_parameters, the budget
# against the literal sequential rule and the rank of each level.

identifiability_key <- paste(sprintf("%02x", 0:31), collapse = "")

identifiability_finding <- function(data, formula, check, ...) {
  results <- audit(data, formula, ..., privacy = "internal", key = identifiability_key)
  Filter(function(finding) finding$check == check, results$document$findings)[[1L]]
}

# The Gram matrix of identifiability.gram_rank by its definition, with P, D,
# Z and the bases A_k as dense matrices, and its rank and smallest
# eigenvalue as the entry decides them.
gram_by_definition <- function(data, formula, weights = NULL, gaussian = TRUE) {
  ir <- formula_ir(formula, data = data, weights = weights)
  m <- design_matrices(ir, data)
  z <- as.matrix(m$z)
  x <- m$x[, !colnames(m$x) %in% m$x_dropped, drop = FALSE]
  n <- nrow(z)
  p <- diag(n) - x %*% solve(crossprod(x), t(x))
  d <- if (is.null(weights)) diag(n) else diag(1 / m$weights)
  w <- if (gaussian) t(z) %*% p %*% z else crossprod(z)
  w0 <- crossprod(z)
  bases <- list()
  for (t in seq_along(ir$random)) {
    q <- length(ir$random[[t]]$columns)
    positions <- which(m$z_columns$term == t)
    columns <- lapply(seq_len(q), function(c) positions[seq(c, length(positions), by = q)])
    for (j in seq_len(q)) {
      for (k in j:q) {
        a <- matrix(0, ncol(z), ncol(z))
        a[cbind(columns[[j]], columns[[k]])] <- 1
        a[cbind(columns[[k]], columns[[j]])] <- 1
        bases[[length(bases) + 1L]] <- a
      }
    }
  }
  trace <- function(a) sum(diag(a))
  gram <- outer(seq_along(bases), seq_along(bases), Vectorize(function(k, l) {
    trace(bases[[k]] %*% w %*% bases[[l]] %*% w)
  }))
  original <- vapply(bases, function(a) trace(a %*% w0 %*% a %*% w0), 0)
  if (gaussian) {
    cross <- vapply(bases, function(a) trace(a %*% t(z) %*% p %*% d %*% p %*% z), 0)
    gram <- rbind(cbind(gram, cross), c(cross, trace(p %*% d %*% p %*% d)))
    original <- c(original, trace(d %*% d))
  }
  vanishing <- diag(gram) <= 1e-10 * original
  others <- which(!vanishing)
  scaled <- gram[others, others] / sqrt(outer(diag(gram)[others], diag(gram)[others]))
  values <- eigen(scaled, symmetric = TRUE, only.values = TRUE)$values
  list(rank = nrow(gram) - sum(vanishing) - sum(values <= 1e-10), smallest = min(values))
}

test_that("identifiability.gram_rank agrees with the Gram matrix of its definition", {
  local_seed(7)
  formulas <- c("y ~ x + (1 + x | g)", "y ~ x + cond + (1 | g) + (0 + z | h)",
                "y ~ 1 + (1 + x + z | g) + (1 | h)", "y ~ x + (1 | g) + (1 | g:h)",
                "y ~ cond + (1 + cond | g)")
  for (i in seq_along(formulas)) {
    n <- 24L
    data <- data.frame(y = rnorm(n), x = round(rnorm(n), 1), z = round(runif(n), 1),
                       cond = sample(c("A", "B", "C"), n, TRUE),
                       g = sample(sprintf("g%d", 1:4), n, TRUE),
                       h = sample(sprintf("h%d", 1:3), n, TRUE),
                       w = sample(c(0.5, 1, 2, 4), n, TRUE))
    for (setting in list(list(), list(weights = "w"), list(family = "poisson"))) {
      found <- do.call(identifiability_finding, c(list(data, formulas[i],
                                                       "identifiability.gram_rank"), setting))
      expected <- gram_by_definition(data, formulas[i], setting$weights,
                                     gaussian = is.null(setting$family))
      label <- paste(formulas[i], names(setting))
      expect_identical(found$statistics$rank$value, as.double(expected$rank), label = label)
      expect_equal(found$statistics$smallest_eigenvalue$value, expected$smallest,
                   tolerance = 1e-9, label = label)
    }
  }
})

test_that("identifiability.gram_rank is near_threshold for values in the band of rank_tolerance", {
  # Two slopes whose columns differ by eps make the smallest eigenvalue of C
  # of the order of eps^2.
  x <- c(1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4)
  noise <- c(1, -1, 1, -1, -1, 1, -1, 1, 1, 1, -1, -1)
  slopes <- function(eps) {
    data <- data.frame(y = 1:12, x = x, x2 = x + eps * noise, g = rep(c("a", "b", "c"), each = 4L))
    identifiability_finding(data, "y ~ 1 + (0 + x | g) + (0 + x2 | g)",
                            "identifiability.gram_rank", family = "poisson")
  }
  found <- slopes(3e-5)
  expect_identical(found$status$threshold_proximity$value, "near_threshold")
  expect_identical(found$statistics$verdict$value, "necessary_condition_met")
  found <- slopes(1e-5)
  expect_identical(found$status$threshold_proximity$value, "near_threshold")
  expect_identical(found$statistics$verdict$value, "not_identified")
  found <- slopes(1e-3)
  expect_identical(found$status$threshold_proximity$value, "clear")
  found <- slopes(1e-6)
  expect_identical(found$status$threshold_proximity$value, "clear")
  expect_identical(found$statistics$confounded_parameters$value,
                   list("0 + x | g: var(x)", "0 + x2 | g: var(x2)"))
})

test_that("identifiability.gram_rank runs up to max_z_columns columns of Z", {
  data <- data.frame(y = 1:6, g = c("a", "a", "b", "b", "c", "c"))
  table <- run_data(data, NULL)$table
  ir <- formula_ir("y ~ 1 + (1 | g)", data = data)
  model <- design_model(ir, table, analysis = FALSE)
  run <- new_run(NULL, table, ir, "gaussian", "T0", model, design_build(ir, model, table))
  entry <- registry_entry("identifiability.gram_rank")
  entry$parameters$max_z_columns$value <- "2"
  expect_identical(run_check(run, entry)[[1L]]$availability,
                   list(value = "not_available", reason = "too_large", detail = "max_z_columns"))
  entry$parameters$max_z_columns$value <- "3"
  expect_true(run_check(run, entry)[[1L]]$available)
  # A random term whose column is 0 in every row has a basis of 0, which
  # vanishes.
  data$z <- 0
  found <- identifiability_finding(data, "y ~ 1 + (1 | g) + (0 + z | g)",
                                   "identifiability.gram_rank", family = "poisson")
  expect_identical(found$statistics$vanishing_parameters$value, list("0 + z | g: var(z)"))
})

# The budget of identifiability.df_budget as the number of indicator columns
# of the levels of 'g' that the sequential rule keeps after the kept
# fixed-effects columns of the terms up to each term, which J - k + r, with r
# the rank within the levels (within_level_rank()), equals up to the
# tolerances, and the consuming terms that it gives.
budget_by_indicators <- function(data, formula) {
  ir <- formula_ir(formula, data = data)
  m <- design_matrices(ir, data)
  indicators <- outer(match(data$g, sort(unique(data$g))), seq_along(unique(data$g)), "==") + 0
  columns <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  budgets <- vapply(seq_along(ir$fixed$terms), function(t) {
    x <- m$x[, columns <= t & !colnames(m$x) %in% m$x_dropped, drop = FALSE]
    sum(mixedcheck:::sequential_rule(cbind(x, indicators))[ncol(x) + seq_len(ncol(indicators))])
  }, 0)
  terms <- vapply(ir$fixed$terms, function(term) term$name, "")
  list(budget = budgets[length(budgets)],
       consuming = as.list(terms[budgets < c(ncol(indicators), budgets[-length(budgets)])]))
}

test_that("identifiability.gram_rank gives the same verdict at extreme magnitudes", {
  # The columns of a random term and the inverse weights are divided by
  # their largest absolute values before any product, so that values near
  # 1e300 or 1e-300 give the findings of the same data at unit scale.
  local_seed(20)
  base <- data.frame(y = rnorm(40L), x = rnorm(40L), g = rep(sprintf("g%d", 1:8), 5L),
                     w = rep(c(0.5, 1, 2, 4), 10L))
  expected <- lapply(list(NULL, "w"), function(weights) {
    identifiability_finding(base, "y ~ x + (1 + x | g)", "identifiability.gram_rank",
                            weights = weights)
  })
  expect_identical(expected[[1L]]$statistics$verdict$value, "identified")
  for (scale in c(1e-300, 1e-100, 1e100, 1e300)) {
    data <- base
    data$x <- base$x * scale
    data$w <- base$w * scale
    for (i in 1:2) {
      weights <- if (i == 2L) "w"
      found <- identifiability_finding(data, "y ~ x + (1 + x | g)", "identifiability.gram_rank",
                                       weights = weights)
      label <- paste(scale, !is.null(weights))
      expect_identical(found$statistics$verdict$value, "identified", label = label)
      expect_identical(found$statistics$rank$value, 4, label = label)
      expect_equal(found$statistics$smallest_eigenvalue$value,
                   expected[[i]]$statistics$smallest_eigenvalue$value, tolerance = 1e-9,
                   label = label)
    }
  }
})

test_that("identifiability.gram_rank sums the Gram matrix over chunks of levels", {
  # Chunks of one or a few levels give the Gram matrix of a single chunk.
  local_seed(5)
  n <- 60L
  data <- data.frame(y = rnorm(n), x = rnorm(n), z = rnorm(n), g = sample(sprintf("g%d", 1:7), n, TRUE),
                     h = sample(sprintf("h%d", 1:5), n, TRUE))
  for (formula in c("y ~ x + (1 + x | g) + (0 + z | h)", "y ~ x + (x | g) + (1 + z | h) + (1 | g:h)")) {
    for (gaussian in c(TRUE, FALSE)) {
      table <- run_data(data, NULL)$table
      ir <- formula_ir(formula, data = data)
      model <- design_model(ir, table, analysis = FALSE)
      run <- new_run(NULL, table, ir, if (gaussian) "gaussian" else "other", "T0", model,
                     design_build(ir, model, table))
      scaled <- scaled_random_columns(run)
      zq <- if (gaussian) {
        as.matrix(Matrix::crossprod(scaled$z, qr.Q(qr(run$x[, run$x_kept, drop = FALSE]))))
      }
      bases <- covariance_bases(run)
      whole <- gram_of_bases(scaled, zq, bases)
      for (chunk in c(1, 7, 40)) {
        found <- gram_of_bases(scaled, zq, bases, chunk = chunk)
        expect_equal(found$gram, whole$gram, tolerance = 1e-12, label = paste(formula, chunk))
        expect_equal(found$original, whole$original, tolerance = 1e-12)
        expect_equal(found$traces, whole$traces, tolerance = 1e-12)
      }
    }
  }
})

test_that("identifiability.gram_rank is not available above max_parameters", {
  data <- data.frame(y = 1:12, x = c(1, 4, 2, 5, 3, 6, 2, 1, 4, 3, 6, 5), z = c(1:6, 6:1),
                     g = rep(c("a", "b", "c"), 4L))
  table <- run_data(data, NULL)$table
  ir <- formula_ir("y ~ x + (1 + x + z | g)", data = data)
  model <- design_model(ir, table, analysis = FALSE)
  run <- new_run(NULL, table, ir, "gaussian", "T0", model, design_build(ir, model, table))
  entry <- registry_entry("identifiability.gram_rank")
  entry$parameters$max_parameters$value <- "5"
  expect_identical(run_check(run, entry)[[1L]]$availability,
                   list(value = "not_available", reason = "too_large", detail = "max_parameters"))
  entry$parameters$max_parameters$value <- "6"
  expect_true(run_check(run, entry)[[1L]]$available)
  entry$parameters$max_z_columns$value <- "8"
  expect_identical(run_check(run, entry)[[1L]]$availability,
                   list(value = "not_available", reason = "too_large", detail = "max_z_columns"))
})

test_that("identifiability.df_budget equals the indicator columns that the sequential rule keeps", {
  literal <- budget_by_indicators
  local_seed(11)
  formulas <- c("y ~ x + b + (1 | g)", "y ~ x + s + b + (1 | g)", "y ~ g + (1 | g)",
                "y ~ 0 + x + (1 | g)", "y ~ cond * b + (1 | g)", "y ~ s + x + (1 | g)")
  for (formula in formulas) {
    n <- 30L
    g <- sample(sprintf("g%d", 1:6), n, TRUE)
    level <- round(rnorm(6L), 2)
    data <- data.frame(y = rnorm(n), x = round(rnorm(n), 1), b = level[match(g, sprintf("g%d", 1:6))],
                       g = g, cond = sample(c("A", "B"), n, TRUE))
    data$s <- data$b + data$x
    found <- identifiability_finding(data, formula, "identifiability.df_budget")
    expected <- literal(data, formula)
    expect_identical(found$statistics$budget$value, expected$budget, label = formula)
    expect_identical(found$statistics$consuming_terms$value, expected$consuming, label = formula)
  }
})

test_that("identifiability.df_budget counts no rank within levels for a column constant within them up to rounding", {
  # wn differs from its level's value by one unit in the last place in some
  # rows, wn2 by about 1e-9 and wn3 by 1e-4 relative to its scale, which the
  # indicator columns do not absorb.
  local_seed(6)
  n <- 96L
  data <- data.frame(y = rnorm(n), g = rep(sprintf("g%02d", 1:12), each = 8L), x = rnorm(n))
  base <- rep(rnorm(12L, 10, 3), each = 8L)
  f <- runif(n, 1, 3)
  data$wn <- (base * f) / f
  data$wn2 <- base + rnorm(n, sd = 1e-9)
  data$wn3 <- base + rnorm(n, sd = 1e-3)
  expect_true(any(data$wn != base))
  for (formula in c("y ~ wn + x + (1 | g)", "y ~ wn2 + x + (1 | g)", "y ~ x + wn3 + (1 | g)",
                    "y ~ wn * x + (1 | g)")) {
    found <- identifiability_finding(data, formula, "identifiability.df_budget")
    expected <- budget_by_indicators(data, formula)
    expect_identical(found$statistics$budget$value, expected$budget, label = formula)
    expect_identical(found$statistics$consuming_terms$value, expected$consuming, label = formula)
  }
  expect_identical(identifiability_finding(data, "y ~ wn + x + (1 | g)",
                                           "identifiability.df_budget")$statistics$budget$value, 10)
  expect_identical(identifiability_finding(data, "y ~ x + wn3 + (1 | g)",
                                           "identifiability.df_budget")$statistics$budget$value, 11)
})

test_that("identifiability.df_budget does not change when a constant is added to a column", {
  # Times of 30 sessions on different days, each up to 60 seconds long, in
  # seconds from 0 and from 1.7e9, near the Unix time of 2023. The time
  # varies within every subject, alone and in the interaction, from either
  # origin, which the earlier comparison with 1e-7 times the largest
  # absolute value of the column missed from 1.7e9.
  local_seed(1)
  subject <- rep(sprintf("s%02d", 1:30), each = 8L)
  day <- rep(sample(0:29), each = 8L)
  seconds <- day * 86400 + runif(240L, 0, 60)
  base <- data.frame(y = rnorm(240L), cond = rep(rep(c("A", "B"), 15L), each = 8L),
                     g = subject)
  for (origin in c(0, 1.7e9)) {
    data <- base
    data$time <- origin + seconds
    for (formula in c("y ~ cond + time + (1 | g)", "y ~ cond * time + (1 | g)",
                      "y ~ 0 + time + cond + (1 | g)")) {
      found <- identifiability_finding(data, formula, "identifiability.df_budget")
      expected <- budget_by_indicators(data, formula)
      label <- paste(origin, formula)
      expect_identical(found$statistics$budget$value, expected$budget, label = label)
      expect_identical(found$statistics$consuming_terms$value, expected$consuming, label = label)
    }
    expect_identical(identifiability_finding(data, "y ~ cond * time + (1 | g)",
                                             "identifiability.df_budget")$statistics$budget$value,
                     28)
  }
  # Values near the largest double, whose differences within the levels
  # would overflow before the columns are scaled.
  data <- base
  data$time <- (2 * seconds / max(seconds) - 1) * 1.7e308
  expect_identical(identifiability_finding(data, "y ~ cond + time + (1 | g)",
                                           "identifiability.df_budget")$statistics$budget$value,
                   28)
})

test_that("the rank of each level follows the sequential rule", {
  local_seed(2)
  level <- sample(1:12, 60L, TRUE)
  values <- cbind(1, round(rnorm(60L)), sample(0:1, 60L, TRUE))
  values[level == 3L, 2L] <- 5
  values[level == 4L, 3L] <- 0
  full <- function(v, difference) {
    vapply(1:12, function(l) {
      rows <- values[level == l, v, drop = FALSE]
      if (difference) {
        rows <- sweep(rows, 2L, rows[1L, ])
      }
      sum(mixedcheck:::sequential_rule(rows)) == length(v)
    }, NA)
  }
  for (v in list(1L, 2L, 3L, 1:2, 2:3, 1:3)) {
    for (difference in c(FALSE, TRUE)) {
      expect_identical(levels_of_full_rank(values[, v, drop = FALSE], level, 12L,
                                           difference = difference),
                       full(v, difference))
    }
  }
})
