# The checks of the prefix identifiability
# (spec/registry/checks/identifiability.*.yaml).

# identifiability.gram_rank: the rank of the Gram matrix of the bases of the
# covariance parameters, projected by the fixed effects for the class
# gaussian and unprojected on the latent scale otherwise, the parameters
# that vanish and those that the eigenvectors of the vanishing eigenvalues
# confound.
audit_check_identifiability_gram_rank <- function(run, entry, elements) {
  parameters <- entry[["parameters"]]
  if (ncol(run$z) > json_number_values(parameters[["max_z_columns"]][["value"]])) {
    return(check_unavailable("too_large", "max_z_columns"))
  }
  if (!length(run$ir$random)) {
    return(list(NULL))
  }
  bases <- covariance_bases(run)
  if (length(bases$names) > json_number_values(parameters[["max_parameters"]][["value"]])) {
    return(check_unavailable("too_large", "max_parameters"))
  }
  tolerance <- json_number_values(parameters[["rank_tolerance"]][["value"]])
  null_loading <- json_number_values(parameters[["null_loading"]][["value"]])
  gaussian <- run$family_class == "gaussian"
  scaled <- scaled_random_columns(run)
  q <- NULL
  if (gaussian) {
    kept <- run$x[, run$x_kept, drop = FALSE]
    if (ncol(kept)) {
      # Scaling the columns leaves their span, and so P, unchanged.
      for (j in seq_len(ncol(kept))) {
        kept[, j] <- kept[, j] / max(abs(kept[, j]))
      }
      q <- qr.Q(qr(kept, LAPACK = TRUE))
    }
  }
  zq <- if (is.null(q)) NULL else as.matrix(Matrix::crossprod(scaled$z, q))
  found <- gram_of_bases(scaled, zq, bases)
  gram <- found$gram
  original <- found$original
  names <- bases$names
  if (gaussian) {
    residual <- residual_gram(run, bases, scaled, q, zq, found$traces)
    gram <- rbind(cbind(gram, residual$cross), c(residual$cross, residual$own))
    original <- c(original, residual$basis)
    names <- c(names, "residual")
  }
  total <- length(names)
  ratio <- diag(gram) / original
  vanishing <- diag(gram) <= tolerance * original
  others <- which(!vanishing)
  eigenvalues <- numeric(0)
  confounded <- character(0)
  if (length(others)) {
    scale <- sqrt(diag(gram)[others])
    scaled_gram <- gram[others, others, drop = FALSE] / outer(scale, scale)
    decomposition <- eigen(scaled_gram, symmetric = TRUE)
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

# The number of elements of the matrix V of gram_of_bases() above which the
# levels of a random term are split into chunks, 32 MB of doubles.
gram_chunk_elements <- 2^22

# Z with each column of a random term, in every level, divided by the
# largest absolute value of that column over the design sample, or left as
# it is when the column is 0 in every row, so that no product of its values
# overflows or underflows. The bases of a term's parameters cover all its
# levels alike, so the scaling multiplies the Gram matrix on both sides by a
# positive diagonal matrix, which leaves C and the vanishing ratios
# unchanged. Returns z, for each random term the positions in Z of each of
# its columns in level order (positions), and the scaled values of its
# columns in each row with the level of the row (terms).
scaled_random_columns <- function(run) {
  z <- run$z
  divisor <- rep(1, ncol(z))
  positions <- list()
  terms <- list()
  for (t in seq_along(run$ir$random)) {
    columns <- which(run$z_columns$term == t)
    q <- length(run$ir$random[[t]]$columns)
    found <- random_term_values(run, t)
    largest <- apply(abs(found$values), 2L, max)
    largest[largest == 0] <- 1
    divisor[columns] <- rep(largest, length.out = length(columns))
    positions[[t]] <- lapply(seq_len(q), function(c) columns[seq(c, length(columns), by = q)])
    terms[[t]] <- list(values = found$values / rep(largest, each = nrow(found$values)),
                       level = found$level, count = found$count)
  }
  column <- rep(seq_len(ncol(z)), diff(z@p))
  z@x <- z@x / divisor[column]
  list(z = z, positions = positions, terms = terms)
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

# The Gram matrix M_kl = tr(A_k W A_l W) of the covariance parameters, with
# W = Z'Z - (Z'Q)(Z'Q)' for zq = Z'Q, or W = Z'Z without zq, for Z scaled as
# scaled_random_columns() scales it, the same elements tr(A_k Z'Z A_k Z'Z) of
# the unprojected bases (original) and, for each random term, the trace of
# each block of W between two of its columns (traces). For blocks (x, y) of
# A_k and (u, v) of A_l, the trace adds the sum over the levels L and L' of
# W[y_L, u_L'] W[v_L', x_L], the sum of the elements of W[y, u] times those
# of W[x, v]. For two terms t and s, each block of W between a column of t
# and a column of s, restricted to a chunk of the levels of s, is one column
# of a matrix V, so that the sum of crossprod(V) over the chunks holds every
# such sum. W is never held whole, and Z'Z is summed over the rows of each
# pair of levels. The blocks of Z'Z within a term are diagonal, since each
# row lies in one level.
gram_of_bases <- function(scaled, zq, bases, chunk = gram_chunk_elements) {
  positions <- scaled$positions
  terms <- scaled$terms
  count <- length(positions)
  sums <- list()
  traces <- list()
  diagonals <- list()
  for (t in seq_len(count)) {
    qt <- length(positions[[t]])
    jt <- terms[[t]]$count
    traces[[t]] <- matrix(0, qt, qt)
    diagonals[[t]] <- list()
    for (s in t:count) {
      qs <- length(positions[[s]])
      # The levels of s in chunks, so that V for a chunk holds at most about
      # chunk elements, or the levels of t times q_t q_s.
      per_chunk <- max(1L, floor(chunk / (jt * qt * qs)))
      chunks <- split(seq_len(terms[[s]]$count),
                      ceiling(seq_len(terms[[s]]$count) / per_chunk))
      level_s <- terms[[s]]$level
      sum_ts <- matrix(0, qt * qs, qt * qs)
      for (chunk in chunks) {
        rows <- which(level_s >= chunk[1L] & level_s <= chunk[length(chunk)])
        cell <- (level_s[rows] - chunk[1L]) * jt + terms[[t]]$level[rows]
        cells <- sort(unique(cell))
        v <- matrix(0, jt * length(chunk), qt * qs)
        for (d in seq_len(qs)) {
          for (c in seq_len(qt)) {
            product <- rowsum(terms[[t]]$values[rows, c] * terms[[s]]$values[rows, d], cell,
                              reorder = TRUE)[, 1L]
            block <- if (is.null(zq)) {
              numeric(nrow(v))
            } else {
              -tcrossprod(zq[positions[[t]][[c]], , drop = FALSE],
                          zq[positions[[s]][[d]][chunk], , drop = FALSE])
            }
            dim(block) <- NULL
            block[cells] <- block[cells] + product
            if (s == t) {
              # The diagonal of a block of Z'Z within a term, in its own rows.
              traces[[t]][c, d] <- traces[[t]][c, d] + sum(block[cells])
              index <- (d - 1L) * qt + c
              diagonals[[t]][[index]] <- c(diagonals[[t]][index][[1L]], product)
            }
            v[, (d - 1L) * qt + c] <- block
          }
        }
        sum_ts <- sum_ts + crossprod(v)
        rm(v)
      }
      sums[[paste(t, s)]] <- sum_ts
    }
  }
  # The sum of the elements of W[y, u] times those of W[x, v] for blocks a
  # = (x, y) and b = (u, v), from the matrix of the two terms in ascending
  # order, transposing both blocks when the term of a comes after that of b.
  element <- function(a, b) {
    if (a$term <= b$term) {
      q <- length(positions[[a$term]])
      sums[[paste(a$term, b$term)]][(b$column_x - 1L) * q + a$column_y,
                                    (b$column_y - 1L) * q + a$column_x]
    } else {
      q <- length(positions[[b$term]])
      sums[[paste(b$term, a$term)]][(a$column_y - 1L) * q + b$column_x,
                                    (a$column_x - 1L) * q + b$column_y]
    }
  }
  parameters <- length(bases$blocks)
  gram <- matrix(0, parameters, parameters)
  for (k in seq_len(parameters)) {
    for (l in seq_len(k)) {
      total <- 0
      for (a in bases$blocks[[k]]) {
        for (b in bases$blocks[[l]]) {
          total <- total + element(a, b)
        }
      }
      gram[k, l] <- gram[l, k] <- total
    }
  }
  original <- vapply(bases$blocks, function(blocks) {
    diagonal <- diagonals[[blocks[[1L]]$term]]
    q <- length(positions[[blocks[[1L]]$term]])
    total <- 0
    for (a in blocks) {
      for (b in blocks) {
        total <- total + sum(diagonal[[(b$column_x - 1L) * q + a$column_y]] *
                               diagonal[[(b$column_y - 1L) * q + a$column_x]])
      }
    }
    total
  }, 0)
  list(gram = gram, original = original, traces = traces)
}

# The elements of the Gram matrix that involve the residual for the class
# gaussian: tr(A_k Z'PDPZ) for each parameter k, tr(PDPD) and, for the
# vanishing test, tr(DD), with D the identity or diag(m/w) for weights w
# with the smallest weight m, which is diag(1/w) divided by its largest
# element, and P = I - QQ' for an orthonormal basis Q of the kept
# fixed-effects columns, from Z scaled as scaled_random_columns() scales it.
residual_gram <- function(run, bases, scaled, q, zq, traces) {
  n <- nrow(scaled$z)
  k <- if (is.null(q)) 0L else ncol(q)
  count <- length(bases$blocks)
  if (is.null(run$weights)) {
    cross <- vapply(seq_len(count), function(p) {
      sum(vapply(bases$blocks[[p]], function(block) {
        traces[[block$term]][block$column_y, block$column_x]
      }, 0))
    }, 0)
    return(list(cross = cross, own = n - k, basis = n))
  }
  d <- min(run$weights) / run$weights
  # tr(A_k Z'PDPZ) = tr(A_k (Z'DZ - Z'DQ Q'Z - Z'Q Q'DZ + Z'Q Q'DQ Q'Z)), where
  # the elements of Z'DZ at the two columns of a term in one level sum d
  # times the product of the term's columns over the level's rows.
  zdq <- if (k) as.matrix(Matrix::crossprod(scaled$z, d * q)) else NULL
  qdq <- if (k) crossprod(q, d * q) else NULL
  cross <- vapply(seq_len(count), function(p) {
    sum(vapply(bases$blocks[[p]], function(block) {
      y <- block$y
      x <- block$x
      values <- scaled$terms[[block$term]]$values
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
# grouping factor that remain after the fixed effects, J - k + rank(X_d) for
# the k kept fixed-effects columns X, where X_d is X with the first row of
# each level subtracted from the level's rows and the columns constant
# within the levels up to rounding set to 0 (level_differences()). A
# combination of the columns of X lies in the span of the indicators exactly
# when it is constant within levels, which X_d tests without the J indicator
# columns.
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
    within <- sequential_rule(level_differences(run$x[, kept, drop = FALSE], levels$code, j))
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
