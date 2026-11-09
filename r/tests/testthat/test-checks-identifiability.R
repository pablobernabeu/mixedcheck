# The identifiability checks, in the parts that the audit corpus cannot
# reach: the Gram matrix against its definition on dense matrices, the
# proximity band of rank_tolerance, the limit of max_z_columns, the budget
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
  set.seed(7)
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

test_that("identifiability.df_budget equals the indicator columns that the sequential rule keeps", {
  # The budget by its literal definition: the indicator columns of the
  # levels that the sequential rule keeps after the kept fixed-effects
  # columns of the terms up to each term.
  literal <- function(data, formula) {
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
  set.seed(11)
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

test_that("the rank of each level follows the sequential rule", {
  set.seed(2)
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

test_that("every identifiability check has its function", {
  ids <- grep("^identifiability[.]", names(registry_entries_by_id()), value = TRUE)
  expect_length(ids, 4L)
  expect_true(all(ids %in% implemented_checks()))
})
