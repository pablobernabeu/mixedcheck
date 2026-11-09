# The checks of the prefix design (spec/registry/checks/design.*.yaml).

# design.rank_deficiency: the fixed-effects columns that the sequential rule
# drops on the design sample, the terms that own them, whether a focal term
# is among those terms and the empty cells of interactions between factors.
audit_check_design_rank_deficiency <- function(run, entry, elements) {
  ir <- run$ir
  if (!length(ir$fixed$columns)) {
    return(list(NULL))
  }
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  term_names <- vapply(ir$fixed$terms, function(term) term$name, "")
  dropped <- !run$x_kept
  owners <- sort(unique(column_terms[dropped]))
  focal_dropped <- any(focal_terms(run)[owners])
  statistics <- list(
    columns = length(ir$fixed$columns),
    kept = sum(run$x_kept),
    dropped_columns = run$x_columns[dropped],
    dropped_terms = term_names[owners],
    empty_cells = empty_cells(run),
    focal_dropped = focal_dropped
  )
  list(check_element(statistics, rules = c(focal_dropped, any(dropped))))
}

# Whether each fixed term of the IR is focal (registry.md, Terms). An
# estimand counts for the model when its outcome, the one it names or else
# the one declared outcome, is the response, when it names none and no
# outcome is declared, and always for a one-sided formula. A focal estimand
# that counts makes focal the term whose set of variables equals that of its
# term. When no estimand counts, every term with variables is focal.
focal_terms <- function(run) {
  declaration <- run$declaration
  terms <- run$ir$fixed$terms
  response <- run$ir$response$variable
  has_variables <- vapply(terms, function(term) length(term$variables) > 0L, NA)
  variables <- declaration[["variables"]]
  declared <- as.character(names(variables))
  outcomes <- declared[vapply(seq_along(variables), function(i) {
    identical(variables[[i]][["role"]], "outcome") &&
      !declaration_inferred(declaration, path_pointer("variables", declared[i], "role"))
  }, NA)]
  counting <- FALSE
  wanted <- list()
  estimands <- declaration[["estimands"]]
  for (i in seq_along(estimands)) {
    if (declaration_inferred(declaration, path_pointer("estimands", i - 1L))) {
      next
    }
    estimand <- estimands[[i]]
    present <- function(member) {
      if (declaration_inferred(declaration, path_pointer("estimands", i - 1L, member))) NULL
      else estimand[[member]]
    }
    outcome <- present("outcome")
    counts <- if (is.null(response)) {
      TRUE
    } else if (!is.null(outcome)) {
      comparison_form(outcome) == response
    } else if (length(outcomes) == 1L) {
      comparison_form(outcomes) == response
    } else {
      !length(outcomes)
    }
    if (!counts) {
      next
    }
    counting <- TRUE
    if (!isFALSE(present("focal"))) {
      term <- present("term")
      if (!is.null(term)) {
        wanted[[length(wanted) + 1L]] <- comparison_form(term_variables(term))
      }
    }
  }
  if (!counting) {
    return(has_variables)
  }
  vapply(terms, function(term) {
    names <- comparison_form(vapply(term$variables, function(v) v$variable, ""))
    length(names) > 0L && any(vapply(wanted, function(w) setequal(w, names), NA))
  }, NA)
}

# The combinations of levels without a row in the design sample, summed over
# the interaction terms whose variables are all categorical, with the levels
# of each variable that occur in the design sample.
empty_cells <- function(run) {
  total <- 0
  for (term in run$ir$fixed$terms) {
    names <- vapply(term$variables, function(v) v$variable, "")
    categorical <- vapply(names, function(name) {
      identical(run$ir$predictors[[name]]$kind, "categorical")
    }, NA)
    if (length(names) < 2L || !all(categorical)) {
      next
    }
    keys <- comparison_form(names)
    levels <- vapply(keys, function(key) {
      length(unique(column_codes(run, key)[run$design]))
    }, 0)
    total <- total + prod(levels) - length(unique(value_codes(run, keys, run$design)))
  }
  total
}

# design.collinearity: the generalised variance inflation factor of each
# main-effect term (Fox & Monette, 1992) over the columns of the main-effect
# terms that the sequential rule keeps after a column of ones, computed as a
# product of ratios of residual norms rather than as a ratio of
# determinants.
audit_check_design_collinearity <- function(run, entry, elements) {
  ir <- run$ir
  term_names <- vapply(ir$fixed$terms, function(term) term$name, "")
  main <- which(vapply(ir$fixed$terms, function(term) length(term$variables) == 1L, NA))
  if (length(main) < 2L) {
    return(lapply(elements, function(element) NULL))
  }
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  columns <- which(column_terms %in% main)
  kept <- sequential_rule(cbind(1, run$x[, columns, drop = FALSE]))[-1L]
  owner <- column_terms[columns][kept]
  pool <- unit_centred_columns(run$x[, columns[kept], drop = FALSE])
  lapply(elements, function(element) {
    own <- owner == match(element$term, term_names)
    df <- sum(own)
    if (!df) {
      return(NULL)
    }
    term <- pool[, own, drop = FALSE]
    others <- pool[, !own, drop = FALSE]
    # b: the residuals after the other columns and the earlier columns of the
    # term, a: after the earlier columns of the term alone.
    b <- sequential_residuals(cbind(others, term))$residual[ncol(others) + seq_len(df)]
    a <- sequential_residuals(term)$residual
    gvif <- prod((a / b)^2)
    values <- list(df = df, gvif = gvif, gvif_per_df = gvif^(1 / df))
    check_element(values, rules = c(
      threshold_holds(entry, "high", values),
      threshold_holds(entry, "moderate", values)
    ))
  })
}

# The columns centred by their means, each summed exactly and divided once as
# ir.md (Centring) computes means, and scaled to unit Euclidean length.
unit_centred_columns <- function(x) {
  n <- nrow(x)
  for (j in seq_len(ncol(x))) {
    centred <- x[, j] - exact_sum(x[, j]) / n
    x[, j] <- centred / sqrt(drop(crossprod(centred)))
  }
  x
}

# design.scale_disparity: the standard deviations of the kept fixed-effects
# columns of numeric terms that take a value other than 0 and 1, and the
# condition number of the kept columns scaled to unit length.
audit_check_design_scale_disparity <- function(run, entry, elements) {
  ir <- run$ir
  n <- length(run$design)
  numeric_terms <- vapply(ir$fixed$terms, function(term) {
    length(term$variables) > 0L && all(vapply(term$variables, function(v) {
      identical(ir$predictors[[v$variable]]$kind, "numeric")
    }, NA))
  }, NA)
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  candidates <- which(run$x_kept & numeric_terms[column_terms])
  scaled <- candidates[vapply(candidates, function(j) {
    any(run$x[, j] != 0 & run$x[, j] != 1)
  }, NA)]
  if (n < 2L || !length(scaled)) {
    return(list(NULL))
  }
  deviations <- vapply(scaled, function(j) column_sd(run$x[, j]), 0)
  statistics <- list(
    scaled_columns = run$x_columns[scaled],
    sd_largest = max(deviations),
    sd_smallest = min(deviations)
  )
  if (statistics$sd_smallest > 0) {
    statistics$sd_ratio <- statistics$sd_largest / statistics$sd_smallest
  }
  kept <- run$x[, run$x_kept, drop = FALSE]
  for (j in seq_len(ncol(kept))) {
    kept[, j] <- kept[, j] / sqrt(drop(crossprod(kept[, j])))
  }
  singular <- svd(kept, nu = 0L, nv = 0L)$d
  statistics$condition_number <- max(singular) / min(singular)
  list(check_element(statistics, rules = threshold_holds(entry, "ratio", statistics) ||
    threshold_holds(entry, "high", statistics) || threshold_holds(entry, "low", statistics)))
}

# The standard deviation of a column with denominator n - 1: 0 when its
# values are all equal, and otherwise the square root of the sum of the
# squared differences from its mean, summed exactly and divided once, over
# n - 1.
column_sd <- function(x) {
  if (all(x == x[1L])) {
    return(0)
  }
  n <- length(x)
  sqrt(sum((x - exact_sum(x) / n)^2) / (n - 1))
}
