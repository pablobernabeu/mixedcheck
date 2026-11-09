# The checks of the prefix identifiability
# (spec/registry/checks/identifiability.*.yaml).

# identifiability.gram_rank: the rank of the Gram matrix of the bases of the
# covariance parameters, projected by the fixed effects for the class
# gaussian and unprojected on the latent scale otherwise, the parameters
# that vanish and those that the eigenvectors of the vanishing eigenvalues
# confound.
audit_check_identifiability_gram_rank <- function(run, entry, elements) {
  parameters <- entry[["parameters"]]
  if (ncol(run$z) > decimal_value(parameters[["max_z_columns"]][["value"]])) {
    return(check_unavailable("too_large"))
  }
  if (!length(run$ir$random)) {
    return(list(NULL))
  }
  tolerance <- decimal_value(parameters[["rank_tolerance"]][["value"]])
  null_loading <- decimal_value(parameters[["null_loading"]][["value"]])
  gaussian <- run$family_class == "gaussian"
  bases <- covariance_bases(run)
  unprojected <- as.matrix(Matrix::crossprod(run$z))
  count <- length(bases$names)
  original <- vapply(seq_len(count), function(k) {
    gram_element(unprojected, bases$blocks[[k]], bases$blocks[[k]])
  }, 0)
  projected <- unprojected
  q <- NULL
  if (gaussian) {
    kept <- run$x[, run$x_kept, drop = FALSE]
    if (ncol(kept)) {
      q <- qr.Q(qr(kept, LAPACK = TRUE))
      zq <- as.matrix(Matrix::crossprod(run$z, q))
      projected <- unprojected - tcrossprod(zq)
    }
  }
  rm(unprojected)
  gram <- matrix(0, count, count)
  for (k in seq_len(count)) {
    for (l in seq_len(k)) {
      gram[k, l] <- gram[l, k] <- gram_element(projected, bases$blocks[[k]], bases$blocks[[l]])
    }
  }
  names <- bases$names
  if (gaussian) {
    residual <- residual_gram(run, bases, projected, q)
    gram <- rbind(cbind(gram, residual$cross), c(residual$cross, residual$own))
    original <- c(original, residual$basis)
    names <- c(names, "residual")
  }
  rm(projected)
  total <- length(names)
  ratio <- diag(gram) / original
  vanishing <- diag(gram) <= tolerance * original
  others <- which(!vanishing)
  eigenvalues <- numeric(0)
  confounded <- character(0)
  if (length(others)) {
    scale <- sqrt(diag(gram)[others])
    scaled <- gram[others, others, drop = FALSE] / outer(scale, scale)
    decomposition <- eigen(scaled, symmetric = TRUE)
    eigenvalues <- decomposition$values
    null <- eigenvalues <= tolerance
    if (any(null)) {
      loadings <- sqrt(rowSums(decomposition$vectors[, null, drop = FALSE]^2))
      confounded <- names[others][loadings >= null_loading * max(loadings)]
    }
  }
  rank <- total - sum(vanishing) - sum(eigenvalues <= tolerance)
  verdict <- if (rank < total) {
    "not_identified"
  } else if (gaussian) {
    "identified"
  } else {
    "necessary_condition_met"
  }
  statistics <- list(
    parameters = total,
    rank = rank,
    verdict = verdict,
    vanishing_parameters = names[vanishing],
    confounded_parameters = confounded
  )
  if (length(eigenvalues)) {
    statistics$smallest_eigenvalue <- min(eigenvalues)
  }
  list(check_element(statistics, rules = c(
    verdict == "not_identified",
    verdict == "necessary_condition_met"
  ), proximity = list(rank_tolerance = c(eigenvalues, ratio[is.finite(ratio)]))))
}

# The covariance parameters of the random terms in IR order (ir.md,
# Covariance parameters), each named as the IR names it and with its basis
# as blocks: pairs of columns x and y of a term, by their positions in Z in
# level order and their positions in the term, with A = the sum over the
# levels L of e(x_L) e(y_L)'. A variance has the block (x, x) and a
# covariance the blocks (x, y) and (y, x).
covariance_bases <- function(run) {
  names <- character(0)
  blocks <- list()
  for (t in seq_along(run$ir$random)) {
    term <- run$ir$random[[t]]
    q <- length(term$columns)
    positions <- which(run$z_columns$term == t)
    columns <- lapply(seq_len(q), function(c) positions[seq(c, length(positions), by = q)])
    labels <- vapply(term$columns, function(column) column$name, "")
    block <- function(x, y) {
      list(x = columns[[x]], y = columns[[y]], term = t, column_x = x, column_y = y)
    }
    for (j in seq_len(q)) {
      names <- c(names, sprintf("%s: var(%s)", term$name, labels[j]))
      blocks[[length(blocks) + 1L]] <- list(block(j, j))
      for (k in seq_len(q)[seq_len(q) > j]) {
        names <- c(names, sprintf("%s: cov(%s, %s)", term$name, labels[j], labels[k]))
        blocks[[length(blocks) + 1L]] <- list(block(j, k), block(k, j))
      }
    }
  }
  list(names = names, blocks = blocks)
}

# tr(A_k W A_l W) for the bases of two parameters given as blocks and a
# symmetric W: for blocks (x, y) of A_k and (u, v) of A_l, the trace adds
# the sum over the levels L and L' of W[y_L, u_L'] W[v_L', x_L], the sum of
# the elements of W[y, u] times those of W[x, v].
gram_element <- function(w, first, second) {
  total <- 0
  for (a in first) {
    for (b in second) {
      total <- total + sum(w[a$y, b$x, drop = FALSE] * w[a$x, b$y, drop = FALSE])
    }
  }
  total
}

# The elements of the Gram matrix that involve the residual for the class
# gaussian: tr(A_k Z'PDPZ) for each parameter k, tr(PDPD) and, for the
# vanishing test, tr(DD), with D the identity or diag(1/w) for weights w and
# P = I - QQ' for an orthonormal basis Q of the kept fixed-effects columns.
residual_gram <- function(run, bases, projected, q) {
  n <- nrow(run$z)
  k <- if (is.null(q)) 0L else ncol(q)
  count <- length(bases$blocks)
  if (is.null(run$weights)) {
    cross <- vapply(seq_len(count), function(p) {
      sum(vapply(bases$blocks[[p]], function(block) {
        sum(projected[cbind(block$y, block$x)])
      }, 0))
    }, 0)
    return(list(cross = cross, own = n - k, basis = n))
  }
  d <- 1 / run$weights
  # tr(A_k Z'PDPZ) = tr(A_k (Z'DZ - Z'DQ Q'Z - Z'Q Q'DZ + Z'Q Q'DQ Q'Z)), where
  # the elements of Z'DZ at the two columns of a term in one level sum d
  # times the product of the term's columns over the level's rows.
  zq <- if (k) as.matrix(Matrix::crossprod(run$z, q)) else NULL
  zdq <- if (k) as.matrix(Matrix::crossprod(run$z, d * q)) else NULL
  qdq <- if (k) crossprod(q, d * q) else NULL
  cross <- vapply(seq_len(count), function(p) {
    sum(vapply(bases$blocks[[p]], function(block) {
      y <- block$y
      x <- block$x
      values <- random_term_values(run, block$term)$values
      total <- sum(d * values[, block$column_y] * values[, block$column_x])
      if (k) {
        total <- total - sum(zdq[y, , drop = FALSE] * zq[x, , drop = FALSE]) -
          sum(zq[y, , drop = FALSE] * zdq[x, , drop = FALSE]) +
          sum((zq[y, , drop = FALSE] %*% qdq) * zq[x, , drop = FALSE])
      }
      total
    }, 0))
  }, 0)
  # tr(PDPD) = tr(DD) - 2 tr(Q'DDQ) + tr(Q'DQ Q'DQ).
  own <- sum(d^2)
  if (k) {
    own <- own - 2 * sum(rowSums(q^2) * d^2) + sum(qdq^2)
  }
  list(cross = cross, own = own, basis = sum(d^2))
}

# identifiability.df_budget: the degrees of freedom between the levels of a
# grouping factor that remain after the fixed effects. The sequential rule
# keeps, of the indicator columns that follow the kept fixed-effects columns
# X, as many as J + rank(X_d) - rank(X), where X_d is X with the first row of
# each level subtracted from the level's rows, since a combination of the
# columns of X lies in the span of the indicators exactly when it is
# constant within levels, which X_d tests without the J indicator columns.
audit_check_identifiability_df_budget <- function(run, entry, elements) {
  ir <- run$ir
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  kept <- which(run$x_kept)
  lapply(elements, function(element) {
    if (!factor_has_intercept(run, element$factor)) {
      return(NULL)
    }
    levels <- factor_levels(run, element$factor)
    j <- levels$count
    values <- run$x[, kept, drop = FALSE]
    first <- match(seq_len(j), levels$code)
    within <- sequential_rule(values - values[first[levels$code], , drop = FALSE])
    term_of <- column_terms[kept]
    budgets <- vapply(seq_along(ir$fixed$terms), function(t) {
      j - sum(term_of <= t) + sum(within[term_of <= t])
    }, 0)
    consuming <- budgets < c(j, budgets[-length(budgets)])
    names <- vapply(ir$fixed$terms, function(term) term$name, "")
    budget <- if (length(budgets)) budgets[length(budgets)] else j
    check_element(list(levels = j, budget = budget, consuming_terms = names[consuming]),
                  rules = budget == 0)
  })
}

# identifiability.levels_vs_dimension: the levels of a random term's factor
# against the number of its columns, and the levels in which its columns
# have full rank.
audit_check_identifiability_levels_vs_dimension <- function(run, entry, elements) {
  lapply(seq_along(elements), function(t) {
    found <- random_term_values(run, t)
    q <- ncol(found$values)
    j <- found$count
    informative <- sum(levels_of_full_rank(found$values, found$level, j))
    kept <- sequential_rule(cbind(run$x, found$values))
    counterparts <- !any(kept[ncol(run$x) + seq_len(q)])
    bound <- if (counterparts) j - 1 else j
    check_element(list(dimension = q, levels = j, informative_levels = informative,
                       counterparts = counterparts, bound = bound),
                  rules = c(bound < q, informative <= q))
  })
}

# identifiability.residual_confounding: the combinations of a level of a
# random term's factor and a pattern of the columns of its pattern terms,
# and those that hold two or more rows.
audit_check_identifiability_residual_confounding <- function(run, entry, elements) {
  random <- run$ir$random
  predictors <- run$ir$predictors
  lapply(seq_along(elements), function(t) {
    term <- random[[t]]
    q <- length(term$columns)
    correlated <- q >= 2L
    pattern <- if (correlated) t else which(vapply(random, function(other) {
      identical(other$factor, term$factor) && length(other$columns) == 1L
    }, NA))
    coded <- all(vapply(random[pattern], function(other) {
      all(vapply(other$terms, function(each) {
        all(vapply(each$variables, function(v) {
          identical(predictors[[v$variable]]$kind, "categorical")
        }, NA))
      }, NA))
    }, NA))
    if (!coded) {
      return(NULL)
    }
    values <- do.call(cbind, lapply(pattern, function(s) random_term_values(run, s)$values))
    patterns <- row_patterns(values)
    levels <- factor_levels(run, term$factor)
    cell <- pair_codes(levels$code, patterns)
    sizes <- tabulate(match(cell, unique(cell)))
    family <- run$family_class
    column <- term$terms[[term$columns[[1L]]$term + 1]]
    intercept_alone <- q == 1L && !length(column$variables) && identical(pattern, t)
    replicated <- sum(sizes >= 2L)
    codes <- rep(NA_integer_, run$table$rows)
    codes[run$design] <- patterns
    statistics <- list(
      columns = q,
      correlated = correlated,
      pattern_terms = vapply(random[pattern], function(other) other$name, ""),
      cells = length(sizes),
      replicated_cells = replicated,
      intercept_alone = intercept_alone
    )
    none <- replicated == 0
    check_element(statistics, rules = c(
      none && family %in% c("gaussian", "other") && (correlated || intercept_alone),
      none && family == "bernoulli",
      none && family %in% c("gaussian", "other"),
      none
    ), items = list(pattern_terms = codes))
  })
}
