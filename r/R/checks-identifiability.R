# The checks of the prefix identifiability
# (spec/registry/checks/identifiability.*.yaml).

# identifiability.gram_rank: the rank of the Gram matrix of the bases of the
# covariance parameters, projected by the fixed effects for the class
# gaussian and unprojected on the latent scale otherwise, the parameters
# that vanish and those that the eigenvectors of the vanishing eigenvalues
# confound. Each value that the entry compares with rank_tolerance carries a
# bound on its rounding error, and the finding is near_threshold when the
# value lies within its bound of the tolerance.
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
  eta <- 0
  if (gaussian) {
    kept <- run$x[, run$x_kept, drop = FALSE]
    if (ncol(kept)) {
      # Scaling the columns leaves their span, and so P, unchanged.
      for (j in seq_len(ncol(kept))) {
        kept[, j] <- kept[, j] / max(abs(kept[, j]))
      }
      decomposition <- qr(kept, LAPACK = TRUE)
      q <- qr.Q(decomposition)
      eta <- projector_error(kept, decomposition, q)
    }
  }
  zq <- if (is.null(q)) NULL else as.matrix(Matrix::crossprod(scaled$z, q))
  n <- nrow(scaled$z)
  p <- if (is.null(q)) 0L else ncol(q)
  found <- gram_of_bases(scaled, zq, bases, level_margins(scaled, q), eta)
  gram <- found$gram
  bound <- found$bound
  names <- bases$names
  largest <- found$largest
  # A covariance parameter vanishes when its largest level ratio, or its
  # cancellation ratio, is at or below the tolerance, or when no level
  # holds a part of its unprojected basis.
  cancellation <- diag(gram) / found$level_sums
  vanishing <- is.na(largest) | largest <= tolerance | diag(gram) <= tolerance * found$level_sums
  held <- !is.na(largest)
  # The cancellation ratio decides only for a parameter whose largest level
  # ratio exceeds the tolerance.
  decides <- held & largest > tolerance
  values <- c(largest[held], cancellation[decides])
  bounds <- c(found$largest_bound[held], cancellation_bound(gram, bound, found)[decides])
  if (gaussian) {
    residual <- residual_gram(run, bases, scaled, q, zq, found, eta)
    gram <- rbind(cbind(gram, residual$cross), c(residual$cross, residual$own))
    bound <- rbind(cbind(bound, residual$cross_bound),
                   c(residual$cross_bound, residual$own_bound))
    names <- c(names, "residual")
    # PDP is 0 exactly when P is, since D has a positive diagonal.
    vanishing <- c(vanishing, n == p)
  }
  total <- length(names)
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
    values <- c(values, eigenvalues)
    bounds <- c(bounds, rep(eigenvalue_bound(gram[others, others, drop = FALSE],
                                             bound[others, others, drop = FALSE],
                                             scaled_gram, eigenvalues), length(eigenvalues)))
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
  ), proximity = list(rank_tolerance = compared_values(values, bounds))))
}

# A bound eta on ||QQ' - Pi||_2 for the computed basis Q of the scaled kept
# columns X and the projector Pi onto the span of X (rank_tolerance): the
# departure of Q from orthonormality, ||Q'Q - I||_F with each element of
# Q'Q summed pairwise over the rows, plus p (ceiling(log2(n)) + 1) e for the
# rounding of those sums, plus, by Wedin's theorem, the residual
# ||X - QR||_F of the decomposition, with X in the order of the columns of
# R, plus (p + 2)(1 + sqrt(p)) e ||X||_F for its computation and the
# rounding of the scaling of X, divided by the smallest singular value of R.
projector_error <- function(kept, decomposition, q) {
  e <- 2^-52
  n <- nrow(kept)
  p <- ncol(kept)
  r <- qr.R(decomposition)
  departure <- matrix(0, p, p)
  for (i in seq_len(p)) {
    for (j in seq_len(i)) {
      departure[i, j] <- departure[j, i] <- pairwise_sum(q[, i] * q[, j]) - (i == j)
    }
  }
  residual <- kept[, decomposition$pivot, drop = FALSE] - q %*% r
  smallest <- min(svd(r, nu = 0L, nv = 0L)$d)
  sqrt(sum(departure^2)) + p * (ceiling(log2(n)) + 1) * e +
    (sqrt(sum(residual^2)) + (p + 2) * (1 + sqrt(p)) * e * sqrt(sum(kept^2))) / smallest
}

# The sum of a vector by pairwise summation: the sums of its elements in
# pairs, then of those sums in pairs, until one remains, so that each
# element passes through at most ceiling(log2(length)) additions.
pairwise_sum <- function(values) {
  while (length(values) > 1L) {
    if (length(values) %% 2L) {
      values <- c(values, 0)
    }
    values <- values[c(TRUE, FALSE)] + values[c(FALSE, TRUE)]
  }
  sum(values)
}

# For each random term, the bound alpha_L for each level L on its share of
# the rounding error of an element of W between a column in L and a column
# in any level L', which lies within (alpha_L + alpha_L') times the root of
# the product of the sums of the squares of the two columns, apart from the
# error of the basis Q (rank_tolerance): alpha_L =
# e (n_L (1 + 2 sqrt(h_L h)) + (p + 2) h_L + 3) / 2, for n_L the rows of L,
# h_L the sum of the squares of the rows of Q in L, 0 without Q, and h the
# largest h_L over the levels of every random term.
level_margins <- function(scaled, q) {
  p <- if (is.null(q)) 0L else ncol(q)
  leverage <- if (is.null(q)) numeric(nrow(scaled$z)) else rowSums(q^2)
  shares <- lapply(scaled$terms, function(term) {
    h <- numeric(term$count)
    summed <- rowsum(leverage, term$level, reorder = TRUE)
    h[as.integer(rownames(summed))] <- summed[, 1L]
    list(rows = tabulate(term$level, term$count), leverage = h)
  })
  largest <- max(0, unlist(lapply(shares, `[[`, "leverage")))
  lapply(shares, function(share) {
    h <- share$leverage
    2^-52 * (share$rows * (1 + 2 * sqrt(h * largest)) + (p + 2) * h + 3) / 2
  })
}

# The bound on the rounding error of the cancellation ratio M_kk / T_k of
# each covariance parameter, from the bound B_kk on M_kk and the bound V_k on
# the sum T_k of its elements in the levels, infinite when V_k reaches T_k.
cancellation_bound <- function(gram, bound, found) {
  sums <- found$level_sums
  margin <- found$level_sums_bound
  ratio <- abs(diag(gram) / sums)
  out <- (diag(bound) + ratio * margin) / (sums - margin)
  out[!(sums > margin)] <- Inf
  out
}

# The bound on the rounding error of every eigenvalue of C, by Weyl's
# inequality: the Frobenius norm of the bounds E_kl on its elements off the
# diagonal, where C_kl lies within
# (|M_kl| + B_kl) / sqrt((M_kk - B_kk)(M_ll - B_ll)) - |C_kl| of its
# computed value, plus 2^-52 times the largest eigenvalue for the solver,
# or Inf when some B_kk reaches M_kk.
eigenvalue_bound <- function(gram, bound, scaled_gram, eigenvalues) {
  lower <- diag(gram) - diag(bound)
  if (!all(lower > 0)) {
    return(Inf)
  }
  e <- (abs(gram) + bound) / sqrt(outer(lower, lower)) - abs(scaled_gram)
  diag(e) <- 0
  sqrt(sum(e^2)) + 2^-52 * max(abs(eigenvalues))
}

# Values that a check compares with a parameter that has a proximity
# factor, each with a bound on its rounding error, so that a value within
# its bound of the parameter's value makes the finding near_threshold
# (registry.md, Parameters).
compared_values <- function(values, bounds) {
  structure(values, bound = bounds)
}

# The number of elements of a block of W in gram_of_bases() above which the
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
# scaled_random_columns() scales it, for each parameter the largest ratio of
# the element tr(A_kL W A_kL W) of its basis in a level L to the same element
# of its unprojected basis, over the levels where the latter is not 0
# (largest, NA without such a level), and the sum of the former over the
# levels (level_sums), and, for each random term, the trace of each block of
# W between two of its columns (traces). For blocks (x, y) of
# A_k and (u, v) of A_l, the trace adds the sum over the levels L and L' of
# W[y_L, u_L'] W[v_L', x_L], the sum of the elements of W[y, u] times those
# of W[x, v]. For each random term t and each chunk of its levels, one
# sparse product forms the rows of W at the chunk's columns of t and the
# columns of t and of every term after it. For each such term s, the blocks
# between a column of t and a column of s are then the columns of a matrix
# V, so that the sum of crossprod(V) over the chunks holds every such sum,
# and for two terms with one column each this sum is the sum of the squares
# of the block, computed for all such terms s at once. crossprod(V) is
# summed over groups of rows of at most J + J' products, for the numbers of
# levels J of t and J' of s, and the sums of squares over the rows of a
# chunk and then over the levels of s, so that each product passes through
# at most 2 (J + J') additions. W is never held whole, and the time grows
# with the number of rows times the square of the number of random terms.
# The blocks of Z'Z within a term are diagonal, since each row lies in one
# level.
#
# With the margins alpha_L of level_margins() and eta of projector_error(),
# which bound the rounding error of the elements of W (identifiability.
# gram_rank.yaml, rank_tolerance), it also returns the bounds on the
# rounding errors of the elements of M (bound), of each largest level ratio
# (largest_bound) and of each sum of the elements in the levels
# (level_sums_bound), and the sums of the squares of the columns of the
# terms in each level (level_norms) and over all levels (norms).
gram_of_bases <- function(scaled, zq, bases, margins = NULL, eta = 0,
                          chunk = gram_chunk_elements) {
  positions <- scaled$positions
  terms <- scaled$terms
  count <- length(positions)
  z <- scaled$z
  # The columns of Z of each term in level order and, within a level, in the
  # order of the term's columns, with the term and the column of each.
  widths <- lengths(positions)
  columns <- lapply(positions, function(p) as.vector(t(do.call(cbind, p))))
  owner <- rep(seq_len(count), lengths(columns))
  within <- unlist(lapply(seq_len(count), function(t) {
    rep(seq_len(widths[t]), length(positions[[t]][[1L]]))
  }))
  all_columns <- unlist(columns)
  sums <- lapply(seq_len(count), function(t) {
    lapply(seq_len(count), function(s) if (s >= t) matrix(0, widths[t] * widths[s], widths[t] * widths[s]))
  })
  traces <- list()
  diagonals <- list()
  projected <- list()
  for (t in seq_len(count)) {
    qt <- widths[t]
    jt <- terms[[t]]$count
    values <- terms[[t]]$values
    # The diagonal of each block of Z'Z and of W within the term, an
    # element for each level, and the trace of the block of W.
    traces[[t]] <- matrix(0, qt, qt)
    diagonals[[t]] <- list()
    projected[[t]] <- list()
    for (d in seq_len(qt)) {
      for (c in seq_len(qt)) {
        product <- rowsum(values[, c] * values[, d], terms[[t]]$level, reorder = TRUE)[, 1L]
        diagonals[[t]][[(d - 1L) * qt + c]] <- product
        if (!is.null(zq)) {
          product <- product - rowSums(zq[positions[[t]][[c]], , drop = FALSE] *
                                         zq[positions[[t]][[d]], , drop = FALSE])
        }
        projected[[t]][[(d - 1L) * qt + c]] <- product
        traces[[t]][c, d] <- sum(product)
      }
    }
    later <- which(owner >= t)
    later_owner <- owner[later]
    single <- later_owner[widths[later_owner] == 1L]
    single_columns <- later[widths[later_owner] == 1L]
    several <- unique(later_owner[widths[later_owner] > 1L | qt > 1L])
    z_later <- z[, all_columns[later], drop = FALSE]
    zq_later <- if (is.null(zq)) NULL else zq[all_columns[later], , drop = FALSE]
    # The levels of t in chunks, so that the rows of W for a chunk hold at
    # most about chunk elements, or one level.
    per_chunk <- max(1L, floor(chunk / (qt * length(later))))
    for (part in split(seq_len(jt), ceiling(seq_len(jt) / per_chunk))) {
      size <- length(part)
      rows <- unlist(lapply(seq_len(qt), function(c) positions[[t]][[c]][part]))
      b <- as.matrix(Matrix::crossprod(z[, rows, drop = FALSE], z_later))
      if (!is.null(zq)) {
        b <- b - tcrossprod(zq[rows, , drop = FALSE], zq_later)
      }
      if (qt == 1L && length(single)) {
        squares <- rowsum(colSums(b[, match(single_columns, later), drop = FALSE]^2), single,
                          reorder = FALSE)
        for (i in seq_len(nrow(squares))) {
          s <- as.integer(rownames(squares)[i])
          sums[[t]][[s]] <- sums[[t]][[s]] + squares[i, 1L]
        }
      }
      for (s in several) {
        qs <- widths[s]
        js <- terms[[s]]$count
        of_s <- which(later_owner == s)
        of_column <- lapply(seq_len(qs), function(d) of_s[within[later[of_s]] == d])
        # The rows of V hold the levels of the chunk for each level of s in
        # turn, formed and summed in groups of the rows of g levels of s, at
        # most jt + js rows each.
        g <- max(1L, floor((jt + js) / size))
        for (first in seq(1L, js, by = g)) {
          group <- seq.int(first, min(first + g - 1L, js))
          v <- matrix(0, size * length(group), qt * qs)
          for (d in seq_len(qs)) {
            for (c in seq_len(qt)) {
              v[, (d - 1L) * qt + c] <- b[(c - 1L) * size + seq_len(size), of_column[[d]][group]]
            }
          }
          sums[[t]][[s]] <- sums[[t]][[s]] + crossprod(v)
        }
      }
      rm(b)
    }
  }
  # The sum of the elements of W[y, u] times those of W[x, v] for blocks a
  # = (x, y) and b = (u, v), from the matrix of the two terms in ascending
  # order, transposing both blocks when the term of a comes after that of b.
  element <- function(a, b) {
    if (a$term <= b$term) {
      q <- widths[a$term]
      sums[[a$term]][[b$term]][(b$column_x - 1L) * q + a$column_y,
                               (b$column_y - 1L) * q + a$column_x]
    } else {
      q <- widths[b$term]
      sums[[b$term]][[a$term]][(a$column_y - 1L) * q + b$column_x,
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
  # The columns of all terms in one index, the sum of the squares of each
  # (norms) and the root sum of squares of the elements of W between every
  # two of them (frobenius), whose square the diagonal of the sum of
  # crossprod(V) holds.
  offsets <- c(0L, cumsum(widths))
  norms <- unlist(lapply(terms, function(term) colSums(term$values^2)))
  frobenius <- matrix(0, offsets[count + 1L], offsets[count + 1L])
  for (t in seq_len(count)) {
    for (s in seq_len(count)[seq_len(count) >= t]) {
      block <- matrix(sqrt(pmax(diag(sums[[t]][[s]]), 0)), widths[t], widths[s])
      frobenius[offsets[t] + seq_len(widths[t]), offsets[s] + seq_len(widths[s])] <- block
      frobenius[offsets[s] + seq_len(widths[s]), offsets[t] + seq_len(widths[t])] <- t(block)
    }
  }
  # The sums of the squares of the columns of the terms in each level, and,
  # for each column c of all terms, A_c = sqrt(sum over the levels L of
  # alpha_L^2 s_cL), with s_cL its sum of squares in L.
  level_norms <- lapply(seq_len(count), function(t) {
    q <- widths[t]
    matrix(vapply(seq_len(q), function(c) diagonals[[t]][[(c - 1L) * q + c]],
                  numeric(terms[[t]]$count)), terms[[t]]$count, q)
  })
  if (is.null(margins)) {
    margins <- lapply(terms, function(term) numeric(term$count))
  }
  spreads <- unlist(lapply(seq_len(count), function(t) {
    sqrt(colSums(margins[[t]]^2 * level_norms[[t]]))
  }))
  # For the blocks a = (x, y) of A_k and b = (u, v) of A_l, the computed
  # products of W[y, u] and W[x, v], summed over the levels, differ from the
  # exact ones by at most
  # (A_y sqrt(s_u) + sqrt(s_y) A_u) G[x, v] + G[y, u] (A_x sqrt(s_v) + sqrt(s_x) A_v)
  # by the Cauchy-Schwarz inequality, for the sums of squares s of the
  # columns and G the norm of a block of W raised by the bound on the norm
  # of its error, which bounds the exact norm, and summing the products adds
  # at most 2^-51 (J + J' + 2) times the sum of their absolute values.
  # The error of the projector adds 2 eta sqrt(X_k X_l) to the whole of
  # M_kl, for X_k = tr(A_k W A_k Z'Z), the square of the norm of
  # PZA_kZ', which the sum of mu^2 over the levels below bounds.
  all_blocks <- unlist(bases$blocks, recursive = FALSE)
  block_owner <- rep(seq_len(parameters), lengths(bases$blocks))
  bx <- vapply(all_blocks, function(a) offsets[a$term] + a$column_x, 0)
  by <- vapply(all_blocks, function(a) offsets[a$term] + a$column_y, 0)
  block_levels <- vapply(all_blocks, function(a) terms[[a$term]]$count, 0)
  root <- sqrt(norms)
  error_norm <- outer(spreads, root) + outer(root, spreads)
  raised <- frobenius + error_norm + eta * outer(root, root)
  pair <- error_norm[by, bx, drop = FALSE] * raised[bx, by, drop = FALSE] +
    raised[by, bx, drop = FALSE] * error_norm[bx, by, drop = FALSE] +
    2^-51 * outer(block_levels, block_levels, "+") * frobenius[by, bx, drop = FALSE] *
      frobenius[bx, by, drop = FALSE] + 2^-50 * frobenius[by, bx, drop = FALSE] *
      frobenius[bx, by, drop = FALSE]
  bound <- t(rowsum(t(rowsum(pair, block_owner, reorder = FALSE)), block_owner, reorder = FALSE))
  bound <- (bound + t(bound)) / 2
  dimnames(bound) <- NULL
  # For each parameter, the element tr(A_kL W A_kL W) of its basis in each
  # level L, from the diagonals of the blocks of W, and the same element of
  # its unprojected basis, from those of Z'Z: the sum over its blocks a and
  # b of the products of the diagonals of the blocks (a$y, b$x) and
  # (a$x, b$y), level by level. The former lies within 3 delta_L mu^2 of
  # its computed value, for delta_L = 2 alpha_L + eta, which bounds the error
  # of an element of W within L relative to the root of the product of the
  # sums of squares of its columns, and mu the sum over the blocks (x, y) of
  # sqrt(omega_x s_y), where s_c is the sum of the squares of column c in the
  # level and omega_c the computed diagonal element of W, or 0 when it is
  # negative, plus delta_L s_c, which bounds the exact one.
  level_element <- function(blocks, diagonal) {
    q <- widths[blocks[[1L]]$term]
    total <- 0
    for (a in blocks) {
      for (b in blocks) {
        total <- total + diagonal[[(b$column_x - 1L) * q + a$column_y]] *
          diagonal[[(b$column_y - 1L) * q + a$column_x]]
      }
    }
    total
  }
  largest <- rep(NA_real_, parameters)
  largest_bound <- rep(NA_real_, parameters)
  level_sums <- numeric(parameters)
  level_sums_bound <- numeric(parameters)
  whole <- numeric(parameters)
  for (k in seq_len(parameters)) {
    blocks <- bases$blocks[[k]]
    t <- blocks[[1L]]$term
    q <- widths[t]
    delta <- 2 * margins[[t]] + eta
    part <- level_element(blocks, projected[[t]])
    unprojected <- level_element(blocks, diagonals[[t]])
    mu <- 0
    for (a in blocks) {
      own <- diagonals[[t]][[(a$column_x - 1L) * q + a$column_x]]
      omega <- pmax(projected[[t]][[(a$column_x - 1L) * q + a$column_x]], 0) + delta * own
      mu <- mu + sqrt(omega * diagonals[[t]][[(a$column_y - 1L) * q + a$column_y]])
    }
    level_sums[k] <- sum(part)
    whole[k] <- sum(mu^2)
    level_sums_bound[k] <- 3 * sum(delta * mu^2) + 2^-52 * length(part) * sum(abs(part))
    held <- unprojected > 0
    if (any(held)) {
      ratios <- part[held] / unprojected[held]
      largest[k] <- max(ratios)
      largest_bound[k] <- max(delta[held] * (3 * mu[held]^2 / unprojected[held] + abs(ratios)))
    }
  }
  bound <- bound + 2 * eta * sqrt(outer(whole, whole))
  list(gram = gram, largest = largest, level_sums = level_sums, traces = traces,
       bound = bound, largest_bound = largest_bound, level_sums_bound = level_sums_bound,
       level_norms = level_norms, norms = norms, offsets = offsets, margins = margins)
}

# The elements of the Gram matrix that involve the residual for the class
# gaussian, tr(A_k Z'PDPZ) for each parameter k (cross) and tr(PDPD) (own),
# with the bounds on their rounding errors (cross_bound and own_bound), for
# D the identity or diag(m/w) for weights w with the smallest weight m,
# which is diag(1/w) divided by its largest element, and P = I - QQ' for an
# orthonormal basis Q of the kept fixed-effects columns, from Z scaled as
# scaled_random_columns() scales it, and eta the bound on the error of QQ'
# of projector_error().
residual_gram <- function(run, bases, scaled, q, zq, found, eta) {
  n <- nrow(scaled$z)
  k <- if (is.null(q)) 0L else ncol(q)
  count <- length(bases$blocks)
  norms <- found$norms
  offsets <- found$offsets
  # The sum over the blocks (x, y) of a parameter of sqrt(s_x s_y), for the
  # sums of squares s of the columns of its term over the design sample.
  spread <- vapply(bases$blocks, function(blocks) {
    sum(vapply(blocks, function(a) {
      sqrt(norms[offsets[a$term] + a$column_x] * norms[offsets[a$term] + a$column_y])
    }, 0))
  }, 0)
  if (is.null(run$weights)) {
    # tr(A_k Z'PZ) sums the diagonals of the blocks of W over the levels,
    # each within 2 alpha_L sqrt(s_xL s_yL), the error of the projector adds
    # eta times the sum over the blocks of sqrt(s_x s_y), and tr(PP) = n - k
    # exactly.
    cross <- vapply(seq_len(count), function(p) {
      sum(vapply(bases$blocks[[p]], function(block) {
        found$traces[[block$term]][block$column_y, block$column_x]
      }, 0))
    }, 0)
    within <- vapply(bases$blocks, function(blocks) {
      sum(vapply(blocks, function(a) {
        norms <- found$level_norms[[a$term]]
        sum(2 * found$margins[[a$term]] * sqrt(norms[, a$column_x] * norms[, a$column_y]))
      }, 0))
    }, 0)
    counts <- vapply(bases$blocks, function(blocks) scaled$terms[[blocks[[1L]]$term]]$count, 0)
    return(list(cross = cross, own = n - k, cross_bound = within + (eta + 2^-52 * counts) * spread,
                own_bound = 0))
  }
  # With weights, the sums over all rows lie within n (1 + k) 2^-52 of their
  # scale and the elements of QQ' within (1 + k) 2^-52, each plus eta.
  epsilon <- (1 + k) * 2^-52
  weighted_residual_gram(run, bases, scaled, q, zq, found, n * epsilon + eta, epsilon + eta, spread)
}

# The elements of the Gram matrix that involve the residual with weights.
# The rows whose leverage H_rr = q_r'q_r exceeds 1/2, of which there are
# fewer than 2k since the leverages sum to k, form A, and the others B.
# Since P_rs = [r = s] - q_r'q_s, tr(PDPD) is the sum of d_r d_s P_rs^2 over
# the pairs of rows, which adds for the rows of A the products of the
# explicit elements P_rs, and for the pairs within B
# sum(d_r^2 (1 - 2 H_rr)) + ||Q_B'D_B Q_B||^2, two sums without negative
# terms. tr(A_k Z'PDPZ) adds over the levels L and the
# blocks (x, y) the sum of d_r (P z_yL)_r (P z_xL)_r, explicit for the rows
# of A and expanded as z_y'D_B z_x - z_y'D_B Q Q'z_x - z_y'Q Q'D_B z_x +
# z_y'Q Q'D_B Q Q'z_x for those of B. A row with a weight far below the
# others and with a leverage near 1, such as a row that a factor of the
# fixed part isolates, then cancels nothing, so that the elements keep
# their precision for weights that differ by many orders of magnitude.
# delta bounds the relative error of a sum over the rows and epsilon that of
# an element of QQ', each with eta, the error of the basis Q.
weighted_residual_gram <- function(run, bases, scaled, q, zq, found, delta, epsilon, spread) {
  n <- nrow(scaled$z)
  k <- if (is.null(q)) 0L else ncol(q)
  count <- length(bases$blocks)
  d <- min(run$weights) / run$weights
  leverage <- if (k) rowSums(q^2) else numeric(n)
  a <- which(leverage > 0.5)
  outside <- d
  outside[a] <- 0
  largest_outside <- max(outside)
  # The pairs within B.
  g <- if (k) crossprod(q, outside * q) else NULL
  own <- sum(outside^2 * (1 - 2 * leverage)) + (if (k) sum(g^2) else 0)
  own_bound <- delta * own + 2 * epsilon * sum(outside^2)
  # The rows of A against the rows of B, in chunks of rows, each element
  # P_rs within epsilon of its computed value. Between two rows of A, P_rs
  # is taken as (PP)_rs, the inner product of their rows of P, which lies
  # within epsilon sqrt(n) (sqrt(P_rr) + sqrt(P_ss)) + 2 n epsilon^2 of the
  # exact value, so that a row that P takes to 0 gives an error of order
  # n epsilon^2, where 1 - H_rr carries one of order epsilon.
  if (length(a)) {
    per_chunk <- max(1L, floor(gram_chunk_elements / length(a)))
    across <- 0
    margin <- 0
    square <- matrix(0, length(a), length(a))
    for (part in split(seq_len(n), ceiling(seq_len(n) / per_chunk))) {
      p_a <- -tcrossprod(q[a, , drop = FALSE], q[part, , drop = FALSE])
      diagonal <- match(a, part)
      at <- !is.na(diagonal)
      p_a[cbind(which(at), diagonal[at])] <- p_a[cbind(which(at), diagonal[at])] + 1
      square <- square + tcrossprod(p_a)
      weight <- 2 * outside[part]
      across <- across + sum(d[a] * (p_a^2 %*% weight))
      margin <- margin + sum(d[a] * ((2 * abs(p_a) + epsilon) %*% weight))
    }
    root <- sqrt(abs(diag(square)))
    error <- epsilon * sqrt(n) * outer(root, root, "+") + 2 * n * epsilon^2
    within <- sum(outer(d[a], d[a]) * square^2)
    own <- own + across + within
    own_bound <- own_bound + delta * (across + within) + epsilon * margin +
      sum(outer(d[a], d[a]) * (2 * abs(square) + error) * error)
  }
  zdq <- if (k) as.matrix(Matrix::crossprod(scaled$z, outside * q)) else NULL
  cross <- numeric(count)
  cross_bound <- 2 * delta * largest_outside * spread
  for (p in seq_len(count)) {
    for (block in bases$blocks[[p]]) {
      t <- block$term
      y <- block$y
      x <- block$x
      values <- scaled$terms[[t]]$values
      total <- sum(outside * values[, block$column_y] * values[, block$column_x])
      if (k) {
        total <- total - sum(zdq[y, , drop = FALSE] * zq[x, , drop = FALSE]) -
          sum(zq[y, , drop = FALSE] * zdq[x, , drop = FALSE]) +
          sum((zq[y, , drop = FALSE] %*% g) * zq[x, , drop = FALSE])
      }
      if (length(a)) {
        # (P z_cL)_r for the rows r of A and every level L, each within
        # 2 delta sqrt(s_cL) of its computed value.
        level <- scaled$terms[[t]]$level[a]
        residuals <- function(c, positions) {
          r <- -tcrossprod(q[a, , drop = FALSE], zq[positions, , drop = FALSE])
          r[cbind(seq_along(a), level)] <- r[cbind(seq_along(a), level)] + values[a, c]
          r
        }
        r_y <- residuals(block$column_y, y)
        r_x <- residuals(block$column_x, x)
        g_y <- 2 * delta * sqrt(found$level_norms[[t]][, block$column_y])
        g_x <- 2 * delta * sqrt(found$level_norms[[t]][, block$column_x])
        products <- rowSums(r_y * r_x)
        total <- total + sum(d[a] * products)
        cross_bound[p] <- cross_bound[p] +
          sum(d[a] * ((abs(r_y) + rep(g_y, each = length(a))) %*% g_x +
                        abs(r_x) %*% g_y + delta * rowSums(abs(r_y * r_x))))
      }
      cross[p] <- cross[p] + total
    }
  }
  list(cross = cross, own = own, cross_bound = cross_bound, own_bound = own_bound)
}

# identifiability.df_budget: the degrees of freedom between the levels of a
# grouping factor that remain after the fixed effects, J - k + r for the k
# kept fixed-effects columns X and the within-level rank r of X
# (within_level_rank()). A combination of the columns of X lies in the span
# of the indicators exactly when it is constant within levels, which the
# within-level rank tests without the J indicator columns, and the rank of
# the columns of the terms up to each term gives the budget after it.
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
    within <- within_level_rank(run$x[, kept, drop = FALSE], levels$code, j)
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
          identical(named_member(predictors, v$variable)$kind, "categorical")
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
