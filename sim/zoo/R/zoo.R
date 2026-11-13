# The shared helpers of the pathology zoo (sim/zoo/README.md): the registry of
# definitions, the pinned random number generator, the checks of drawn
# properties, the builders of expected findings and their standard blocks,
# computations of statistics from their definitions in the registry, the
# order of findings and the writers of the stored files. Base R only: nothing
# here calls mixedcheck or any other package, so that the expectations are
# derived independently of both packages, and nothing depends on the locale.

# Definitions --------------------------------------------------------------

zoo_state <- new.env(parent = emptyenv())
zoo_state$definitions <- list()
zoo_state$file <- NA_character_

zoo_rng <- c("Mersenne-Twister", "Inversion", "Rejection")
zoo_domains <- c("education", "crossed", "families", "dyads", "eeg", "trial-level", "ild", "any")
zoo_blocks <- c("dyad", "eeg", "intensive_longitudinal")

# Registers the definition of one directory of fixtures/zoo/. generate(p,
# checks, seed) returns the data frame, declaration(p) the declaration as a
# named list, formula(p) the formula, run the named list of the run and
# expected(p, data) a named list with samples and findings, or with issue.
# The file and the generator function are those of the generator file that
# regenerate.R is sourcing.
zoo_define <- function(id, name, title, role, matched, negative_of, domain, catalogue, planted,
                       seed, parameters, generate, declaration, formula, run, expected, signal,
                       planned = list(), deferred = NULL,
                       csv = list(eol = "\n", digits = list(), missing = list())) {
  stopifnot(
    zoo_is_string(id), grepl("^Z(0[1-9]|[12][0-9]|3[01])N?$", id),
    zoo_is_string(name), grepl("^[a-z0-9]+(-[a-z0-9]+)*$", name), nchar(name) <= 40L,
    zoo_is_string(title), nchar(title) <= 100L,
    role %in% c("fixture", "negative"), zoo_is_string(matched),
    is.character(negative_of), domain %in% zoo_domains, is.character(catalogue),
    zoo_is_string(planted), is.numeric(seed), length(seed) == 1L,
    is.list(parameters), !is.null(names(parameters)),
    is.function(generate), is.function(declaration), is.function(formula),
    is.list(run), identical(run, zoo_access(id, run$outcome_access)), is.function(expected),
    is.list(signal), is.list(planned), is.null(deferred) || deferred$block %in% zoo_blocks
  )
  if (!is.null(zoo_state$definitions[[id]])) {
    stop(paste0("The zoo defines '", id, "' twice."), call. = FALSE)
  }
  file <- zoo_state$file
  stem <- if (is.na(file)) NA_character_ else sub("[.]R$", "", basename(file))
  csv <- utils::modifyList(list(eol = "\n", digits = list(), missing = list()), csv)
  zoo_state$definitions[[id]] <- list(
    id = id, name = name, title = title, role = role, matched = matched,
    negative_of = negative_of, domain = domain, catalogue = catalogue, planted = planted,
    seed = seed, parameters = parameters, generate = generate, declaration = declaration,
    formula = formula, run = run, expected = expected, signal = signal, planned = planned,
    deferred = deferred, csv = csv,
    file = if (is.na(file)) NA_character_ else paste0("sim/zoo/R/", basename(file)),
    "function" = paste0("zoo_", stem)
  )
  invisible(id)
}

zoo_is_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x)

# The run of a directory: its outcome access and, at T1 and T2, the reason
# 'Pathology zoo fixture Zn.' and, at T2, exploratory true.
zoo_access <- function(id, tier = c("T0", "T1", "T2")) {
  tier <- match.arg(tier)
  run <- list(outcome_access = tier)
  if (tier != "T0") {
    run$reason <- paste0("Pathology zoo fixture ", id, ".")
  }
  if (tier == "T2") {
    run$exploratory <- TRUE
  }
  run
}

# One planned check beyond registry 0.1.0: its provisional identifier, tier,
# catalogue items, the registry version that adds it or NULL, the milestone,
# what it needs and a description.
zoo_planned <- function(check, tier, catalogue, registry = NULL, milestone, needs, description) {
  stopifnot(zoo_is_string(check), tier %in% c("T0", "T1", "T2", "Stream A"),
            is.character(catalogue), is.null(registry) || zoo_is_string(registry),
            zoo_is_string(milestone), zoo_is_string(needs), zoo_is_string(description))
  planned <- list(check = check, tier = tier, catalogue = zn(catalogue))
  if (!is.null(registry)) {
    planned$registry <- registry
  }
  c(planned, list(milestone = milestone, needs = needs, description = description))
}

# The directory of a definition under fixtures/zoo/.
zoo_directory <- function(definition) paste0(definition$id, "-", definition$name)

# Random numbers and drawn properties -------------------------------------

# Evaluates code with the RNG kind of the zoo and the seed, and restores the
# caller's kind and state, or its absence, on exit.
zoo_with_rng <- function(seed, code) {
  kind <- RNGkind()
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  state <- if (had) get(".Random.seed", envir = globalenv())
  on.exit({
    suppressWarnings(RNGkind(kind[1L], kind[2L], kind[3L]))
    if (had) {
      assign(".Random.seed", state, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)
  RNGkind(zoo_rng[1L], zoo_rng[2L], zoo_rng[3L])
  set.seed(seed)
  code
}

# Applies the drawn properties of a generator (sim/zoo/README.md, Generators).
# properties is a named list of functions, each returning the units whose
# stored values fail the property, in label order. redraw(data, unit) draws
# the values of one unit again from the continuing stream. With checks
# 'redraw', every failing unit is drawn again, property by property and unit
# by unit, until every property holds, and the data carry the number of
# redraws in the attribute zoo_redraws. A unit that still fails a property
# after 100 redraws stops the generator. With 'flag', nothing is drawn again
# and the attribute zoo_failed names each failing property and unit. With
# 'none', the data are returned as they are.
zoo_check <- function(data, properties, redraw, checks = c("redraw", "flag", "none")) {
  checks <- match.arg(checks)
  if (checks == "none") {
    return(data)
  }
  if (checks == "flag") {
    failed <- character(0)
    for (name in names(properties)) {
      units <- properties[[name]](data)
      if (length(units)) {
        failed <- c(failed, paste0(name, ": ", as.character(units)))
      }
    }
    attr(data, "zoo_failed") <- failed
    return(data)
  }
  attempts <- list()
  redraws <- 0L
  repeat {
    clean <- TRUE
    for (name in names(properties)) {
      repeat {
        units <- properties[[name]](data)
        if (!length(units)) {
          break
        }
        clean <- FALSE
        for (unit in as.list(units)) {
          key <- paste0(name, "/", as.character(unit))
          count <- if (is.null(attempts[[key]])) 1L else attempts[[key]] + 1L
          if (count > 100L) {
            stop(paste0("The property '", name, "' still fails for the unit '",
                        as.character(unit), "' after 100 redraws."), call. = FALSE)
          }
          attempts[[key]] <- count
          data <- redraw(data, unit)
          redraws <- redraws + 1L
        }
      }
    }
    if (clean) {
      break
    }
  }
  attr(data, "zoo_redraws") <- redraws
  data
}

# Values and labels -------------------------------------------------------

# Rounds to the stored grid of data.csv: floor(x * 10^d + 0.5) / 10^d, or
# x itself when digits is NA, as the studies of M6 may ask.
zoo_round <- function(x, digits) {
  if (is.na(digits)) {
    return(x)
  }
  floor(x * 10^digits + 0.5) / 10^digits
}

# The decimal digits of whole non-negative doubles below 2^53, without
# format(), which may write 1e+05.
zoo_digits <- function(n) {
  vapply(n, function(v) {
    if (!is.finite(v) || v < 0 || v != floor(v) || v >= 2^53) {
      stop("zoo_digits() takes whole numbers from 0 to 2^53.", call. = FALSE)
    }
    if (v == 0) {
      return("0")
    }
    digits <- integer(0)
    while (v > 0) {
      digits <- c(v %% 10, digits)
      v <- v %/% 10
    }
    paste0(as.character(0:9)[digits + 1L], collapse = "")
  }, "")
}

# Labels made of a prefix and a number zero-padded to the width of n, such
# as 'S01' to 'S10', so that code-point order is numeric order.
zoo_label <- function(prefix, i, n = max(i)) {
  width <- nchar(zoo_digits(n))
  text <- zoo_digits(i)
  paste0(prefix, strrep("0", width - nchar(text)), text)
}

# The text of a number column of data.csv: the value times 10^d rounded half
# up with floor(x * 10^d + 0.5), written with its sign, integer part and d
# decimal digits. NA gives NA.
zoo_number <- function(x, digits) {
  vapply(x, function(v) {
    if (is.na(v)) {
      return(NA_character_)
    }
    scaled <- floor(v * 10^digits + 0.5)
    sign <- if (scaled < 0) "-" else ""
    a <- abs(scaled)
    if (digits == 0) {
      return(paste0(sign, zoo_digits(a)))
    }
    fraction <- zoo_digits(a %% 10^digits)
    paste0(sign, zoo_digits(a %/% 10^digits), ".",
           strrep("0", digits - nchar(fraction)), fraction)
  }, "", USE.NAMES = FALSE)
}

# A decimal constant held as written, such as zoo_decimal("0.25"), which the
# JSON writer writes as that number token.
zoo_decimal <- function(x) {
  stopifnot(zoo_is_string(x), grepl("^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?$", x))
  structure(x, class = "zoo_decimal")
}

# An atomic vector that the JSON writer writes as an array at any length.
zoo_array <- function(x) structure(x, class = "zoo_array")

# An empty object, such as the scope of the model.
zoo_object <- function() structure(list(), names = character(0))

# Expected findings ---------------------------------------------------------

# Statistics: an exact value, a ratio of two counts, an interval for a real
# that the design bounds, given as two decimal strings, an absent statistic
# and a list of names, always an array. class is the resolved count class of
# a statistic whose entry gives the class by_unit, and is left out otherwise.
zv <- function(value, class = NULL) zoo_statistic(list(value = value), class)
zr <- function(numerator, denominator, class = NULL) {
  zoo_statistic(list(ratio = zoo_array(c(numerator, denominator))), class)
}
zi <- function(low, high) list(interval = list(zoo_decimal(low), zoo_decimal(high)))
za <- function() list(absent = TRUE)
zn <- function(...) zoo_array(as.character(c(...)))

zoo_statistic <- function(statistic, class) {
  if (!is.null(class)) {
    stopifnot(class %in% c("person", "non_person"))
    statistic$count_class <- class
  }
  statistic
}

zoo_status_fields <- c("availability", "assessability", "finding", "threshold_proximity",
                       "validation")

# One expected finding. finding is its finding status, and status holds any
# other status field that differs from the defaults of expected.json
# (fixtures/zoo/README.md), as a string or as a list with value, reason and
# detail.
zoo_finding <- function(check, scope = zoo_object(), finding = NULL, message = NULL,
                        statistics = zoo_object(), status = NULL, why) {
  fields <- if (is.null(status)) list() else status
  if (!is.null(finding)) {
    fields$finding <- finding
  }
  stopifnot(all(names(fields) %in% zoo_status_fields), zoo_is_string(why))
  fields <- fields[intersect(zoo_status_fields, names(fields))]
  result <- list(check = check, scope = zoo_scope(scope),
                 status = if (length(fields)) fields else zoo_object())
  if (!is.null(message)) {
    result$message <- message
  }
  if (length(statistics)) {
    result$statistics <- statistics
  }
  result$why <- why
  result
}

# A finding that is not available, which lists its availability alone.
zoo_not_available <- function(check, reason, detail = NULL, why, scope = zoo_object()) {
  availability <- list(value = "not_available", reason = reason)
  if (!is.null(detail)) {
    availability$detail <- detail
  }
  list(check = check, scope = zoo_scope(scope), status = list(availability = availability),
       why = why)
}

# One element of a fixture's signal (fixtures/zoo/README.md). statistics,
# where the problem shows only in counts, is a named list of plain values.
zoo_signal <- function(check, scope, message, statistics = NULL) {
  signal <- list(check = check, scope = zoo_scope(scope), message = message)
  if (!is.null(statistics)) {
    signal$statistics <- statistics
  }
  signal
}

zoo_scope <- function(scope) {
  if (!length(scope)) {
    return(zoo_object())
  }
  stopifnot(!is.null(names(scope)),
            all(names(scope) %in% c("factor", "first", "second", "term", "column", "unit")))
  scope[order(names(scope), method = "radix")]
}

# The class to which a by_unit count resolves (registry.md, Statistics and
# counts), from the number of members of the disclosure unit in each level of
# its item, or in each combination for a count of two items: person when some
# level has at most one member, and non_person otherwise.
zoo_count_class <- function(members) if (min(members) <= 1) "person" else "non_person"

# The support of the findings on one sample.
zoo_sample <- function(rows, distinct = rows, basis = "disclosure_unit", dominated = FALSE) {
  list(rows = rows, basis = basis, distinct = distinct, dominated = dominated)
}

# Standard expectations ----------------------------------------------------

# The three assignment checks without an assignment block.
zoo_na3 <- function() {
  why <- "The declaration has no assignment block."
  lapply(c("assignment.constant_within_unit", "assignment.design_df",
           "assignment.unit_in_random_part"),
         function(check) zoo_not_available(check, "declaration_missing", "/assignment", why))
}

zoo_rd <- function(columns, why = NULL) {
  zoo_finding(
    "design.rank_deficiency", finding = "consistent", message = "full_rank",
    statistics = list(columns = zv(columns), dropped_columns = zv(zn()),
                      dropped_terms = zv(zn()), empty_cells = zv(0), focal_dropped = zv(FALSE),
                      kept = zv(columns)),
    why = zoo_why(why, paste0("The ", columns,
                              " fixed-effects columns are linearly independent."))
  )
}

zoo_sr <- function(rows, why = NULL) {
  zoo_finding(
    "sample.raw_vs_analysis", finding = "consistent", message = "complete",
    statistics = list(rows_raw = zv(rows), rows_kept = zv(rows), rows_dropped = zv(0),
                      incomplete_columns = zv(zn()), emptied_factors = zv(zn()),
                      reference_emptied = zv(zn()), factors_losing_levels = zv(zn()),
                      new_singletons = zv(zn())),
    why = zoo_why(why, "No value that the model reads is missing.")
  )
}

zoo_kd <- function(key, rows, why = NULL) {
  zoo_finding(
    "keys.duplicates", finding = "consistent", message = "unique",
    statistics = list(rows = zv(rows), key_columns = zv(zn(key)), missing_key_rows = zv(0),
                      duplicated_keys = zv(0), conflicting_keys = zv(0),
                      identical_keys = zv(0), duplicate_rows = zv(0)),
    why = zoo_why(why, "Every row has its own value of the observation key.")
  )
}

zoo_lu <- function(column, class, why = NULL) {
  zoo_finding(
    "labels.unicode_forms", scope = list(column = column), finding = "consistent",
    message = "distinct",
    statistics = list(spellings = zv(0, class), labels = zv(0, class)),
    why = zoo_why(why, "The labels are ASCII, so no two differ only in their Unicode form.")
  )
}

# structure.cluster_sizes with the message sizes, from the vector of level
# sizes: the order statistics at positions 1, ceil(J/4), ceil(J/2),
# ceil(3J/4) and J, the levels of one row and the effective size, with S
# summed exactly and the rest in double arithmetic, as the entry states.
zoo_cs <- function(factor, class, sizes, intercept = TRUE, why = NULL) {
  sorted <- sort(sizes, method = "radix")
  J <- length(sorted)
  N <- sum(sorted)
  S <- sum(sorted^2)
  at <- function(position) sorted[position]
  zoo_finding(
    "structure.cluster_sizes", scope = list(factor = factor), finding = "consistent",
    message = "sizes",
    statistics = list(
      levels = zv(J, class), rows = zv(N), smallest = zv(at(1L)),
      lower_quartile = zv(at(ceiling(J / 4))), median = zv(at(ceiling(J / 2))),
      upper_quartile = zv(at(ceiling(3 * J / 4))), largest = zv(at(J)),
      singletons = zv(sum(sorted == 1)), effective_size = zv((N - S / N) / (J - 1)),
      intercept = zv(intercept)
    ),
    why = zoo_why(why, paste0(J, " levels with ", N, " rows in all."))
  )
}

# identifiability.gram_rank for an identified design, with the smallest
# eigenvalue that zoo_gram() computes from it. design is a list with X, terms
# and, optionally, gaussian.
zoo_gr <- function(design, why = NULL) {
  gaussian <- if (is.null(design$gaussian)) TRUE else design$gaussian
  gram <- zoo_gram(design$X, design$terms, gaussian)
  if (length(gram$vanishing)) {
    stop("zoo_gr() is for identified designs, and this design has a vanishing parameter.",
         call. = FALSE)
  }
  zoo_finding(
    "identifiability.gram_rank", finding = "consistent", message = "identified",
    statistics = list(parameters = zv(gram$parameters), rank = zv(gram$parameters),
                      verdict = zv("identified"), vanishing_parameters = zv(zn()),
                      confounded_parameters = zv(zn()),
                      smallest_eigenvalue = zv(gram$smallest_eigenvalue)),
    why = zoo_why(why, paste0("The design separates its ", gram$parameters,
                              " covariance parameters, and zoo_gram() gives the eigenvalue."))
  )
}

zoo_db <- function(factor, class, levels, budget, terms, why = NULL) {
  zoo_finding(
    "identifiability.df_budget", scope = list(factor = factor), finding = "consistent",
    message = "budget",
    statistics = list(levels = zv(levels, class), budget = zv(budget, class),
                      consuming_terms = zv(zn(terms))),
    why = zoo_why(why, paste0(levels, " levels leave ", budget,
                              " degrees of freedom after the fixed effects."))
  )
}

zoo_ld1 <- function(factor, class, levels, why = NULL) {
  zoo_finding(
    "identifiability.levels_vs_dimension",
    scope = list(factor = factor, term = paste0("1 | ", factor)),
    finding = "consistent", message = "adequate",
    statistics = list(dimension = zv(1), levels = zv(levels, class),
                      informative_levels = zv(levels, class), counterparts = zv(TRUE),
                      bound = zv(levels - 1, class)),
    why = zoo_why(why, paste0("Every one of the ", levels, " levels informs the intercept."))
  )
}

zoo_rc1 <- function(factor, class, levels, why = NULL) {
  zoo_finding(
    "identifiability.residual_confounding",
    scope = list(factor = factor, term = paste0("1 | ", factor)),
    finding = "consistent", message = "replicated",
    statistics = list(columns = zv(1), correlated = zv(FALSE),
                      pattern_terms = zv(zn(paste0("1 | ", factor))), cells = zv(levels, class),
                      replicated_cells = zv(levels, class), intercept_alone = zv(TRUE)),
    why = zoo_why(why, "Every level holds two rows or more.")
  )
}

zoo_why <- function(why, default) if (is.null(why)) default else why

# The range of some counts as text: the count when they are all equal, and
# otherwise the smallest and the largest, as '2 to 4'.
zoo_range <- function(x) {
  if (min(x) == max(x)) as.character(min(x)) else paste0(min(x), " to ", max(x))
}

# Statistics from their definitions in the registry ------------------------

# The Gram matrix of identifiability.gram_rank for a design without weights
# (registry.md). X holds the fixed-effects columns,
# terms the random terms in IR order, each a list with factor, the level of
# each row, and columns, the matrix of the term's columns. Returns the number
# of parameters, the vanishing ones and the smallest eigenvalue of C.
zoo_gram <- function(X, terms, gaussian = TRUE, tolerance = 1e-10) {
  X <- as.matrix(X)
  n <- nrow(X)
  blocks <- list()
  parameters <- list()
  offset <- 0L
  for (term in terms) {
    columns <- as.matrix(term$columns)
    levels <- sort(unique(term$factor), method = "radix")
    q <- ncol(columns)
    position <- matrix(0L, q, length(levels))
    block <- matrix(0, n, q * length(levels))
    for (l in seq_along(levels)) {
      for (c in seq_len(q)) {
        j <- (l - 1L) * q + c
        block[, j] <- columns[, c] * (term$factor == levels[l])
        position[c, l] <- offset + j
      }
    }
    blocks[[length(blocks) + 1L]] <- block
    for (c in seq_len(q)) {
      parameters[[length(parameters) + 1L]] <- list(a = position[c, ], b = position[c, ])
    }
    for (c in seq_len(q - 1L)) {
      for (d in (c + 1L):q) {
        parameters[[length(parameters) + 1L]] <- list(a = position[c, ], b = position[d, ])
      }
    }
    offset <- offset + ncol(block)
  }
  Z <- do.call(cbind, blocks)
  m <- ncol(Z)
  decomposition <- qr(X)
  Q <- qr.Q(decomposition)[, seq_len(decomposition$rank), drop = FALSE]
  W0 <- crossprod(Z)
  W <- if (gaussian) crossprod(Z, Z - Q %*% crossprod(Q, Z)) else W0
  basis <- function(a, b) {
    A <- matrix(0, m, m)
    A[cbind(a, b)] <- 1
    A[cbind(b, a)] <- 1
    A
  }
  product <- function(A, B, V) sum((A %*% V) * t(B %*% V))
  K <- length(parameters)
  A <- lapply(parameters, function(p) basis(p$a, p$b))
  M <- matrix(0, K + gaussian, K + gaussian)
  for (k in seq_len(K)) {
    for (l in k:K) M[k, l] <- M[l, k] <- product(A[[k]], A[[l]], W)
  }
  if (gaussian) {
    for (k in seq_len(K)) M[k, K + 1L] <- M[K + 1L, k] <- sum(diag(A[[k]] %*% W))
    M[K + 1L, K + 1L] <- n - decomposition$rank
  }
  vanishing <- logical(K + gaussian)
  for (k in seq_len(K)) {
    p <- parameters[[k]]
    within <- vapply(seq_along(p$a), function(l) {
      AL <- basis(p$a[l], p$b[l])
      c(product(AL, AL, W), product(AL, AL, W0))
    }, numeric(2))
    ratios <- within[1L, within[2L, ] != 0] / within[2L, within[2L, ] != 0]
    total <- sum(within[1L, ])
    vanishing[k] <- length(ratios) == 0L || max(ratios) <= tolerance ||
      total <= 0 || M[k, k] / total <= tolerance
  }
  if (gaussian) vanishing[K + 1L] <- n == decomposition$rank
  keep <- which(!vanishing)
  scale <- sqrt(diag(M)[keep])
  C <- M[keep, keep, drop = FALSE] / outer(scale, scale)
  values <- eigen(C, symmetric = TRUE, only.values = TRUE)$values
  list(parameters = K + gaussian, vanishing = which(vanishing),
       smallest_eigenvalue = if (length(values)) min(values) else NULL)
}

# The values of smallest_eigenvalue that section 4 of the design gives, to
# seven significant digits, for the directories whose design states one.
# regenerate.R --check compares the value that each present definition
# writes with its reference, so that a change to zoo_gram() that would move
# an expectation shows as a failure here rather than as a regenerated file.
zoo_gram_reference <- c(
  Z01 = 0.7854654, Z01N = 0.4167159, Z02 = 0.2755653, Z02N = 0.2870861, Z03 = 0.7854654,
  Z04N = 0.08780482, Z05N = 0.06262614, Z06 = 0.6755572, Z06N = 0.1376835,
  Z07N = 0.02085748, Z08 = 0.8877278, Z08N = 0.7156568, Z09 = 0.8877278,
  Z10 = 0.5322493, Z10N = 0.6889145, Z12 = 0.2928932, Z12N = 0.2928932,
  Z13 = 0.5499648, Z13N = 0.5507501, Z14 = 0.5268398, Z14N = 0.5232687,
  Z15 = 0.6666667, Z15N = 0.6837722, Z16 = 0.8015811, Z16N = 0.8015811,
  Z17 = 0.06961268, Z17N = 0.06854609, Z18 = 0.3361072, Z18N = 0.3361072,
  Z20 = 0.5310240, Z20N = 0.5370900, Z21 = 1, Z21N = 0.6094333, Z22 = 0.8130106,
  Z22N = 0.4295899, Z24 = 0.9254644, Z25 = 0.7346276, Z25N = 0.7346276, Z27 = 1,
  Z27N = 1, Z28 = 0.2928932, Z29 = 0.007362356, Z29N = 0.007362356, Z30 = 0.04236970,
  Z30N = 0.06144329
)

# icc and within_share of structure.within_between for one numeric column,
# in double arithmetic: (MSB - MSW) / (MSB + (n0 - 1) MSW) and
# SSW / (SSB + SSW), with n0 as structure.cluster_sizes defines it.
zoo_anova <- function(values, levels) {
  groups <- split(values, factor(levels, levels = sort(unique(levels), method = "radix")))
  sizes <- vapply(groups, length, 0)
  N <- length(values)
  J <- length(groups)
  mean_all <- sum(values) / N
  means <- vapply(groups, function(g) sum(g) / length(g), 0)
  ssb <- sum(sizes * (means - mean_all)^2)
  ssw <- sum(vapply(seq_along(groups), function(j) sum((groups[[j]] - means[j])^2), 0))
  n0 <- (N - sum(sizes^2) / N) / (J - 1)
  msb <- ssb / (J - 1)
  msw <- ssw / (N - J)
  list(icc = (msb - msw) / (msb + (n0 - 1) * msw), within_share = ssw / (ssb + ssw))
}

# The GVIF of design.collinearity for the columns term of X, the kept columns
# of the main-effect terms without the intercept: det(R_TT) det(R_OO) /
# det(R) of their correlation matrix, with gvif_per_df and df.
zoo_gvif <- function(X, term) {
  X <- as.matrix(X)
  R <- stats::cor(X)
  inside <- if (is.character(term)) match(term, colnames(X)) else term
  outside <- setdiff(seq_len(ncol(X)), inside)
  minor <- function(index) if (length(index)) det(R[index, index, drop = FALSE]) else 1
  gvif <- minor(inside) * minor(outside) / det(R)
  list(gvif = gvif, gvif_per_df = gvif^(1 / length(inside)), df = length(inside))
}

# The standard deviation with denominator n - 1, 0 for a constant column.
zoo_sd <- function(x) {
  if (all(x == x[1L])) {
    return(0)
  }
  m <- sum(x) / length(x)
  sqrt(sum((x - m)^2) / (length(x) - 1))
}

# The condition number of design.scale_disparity: the ratio of the largest
# to the smallest singular value of the kept columns, each divided by its
# largest absolute value and scaled to unit length.
zoo_condition <- function(X) {
  X <- as.matrix(X)
  X <- sweep(X, 2L, apply(abs(X), 2L, max), "/")
  X <- sweep(X, 2L, sqrt(colSums(X^2)), "/")
  d <- svd(X, nu = 0L, nv = 0L)$d
  max(d) / min(d)
}

# The order of findings (documents.md, Findings) -----------------------------

# Compares two strings code point by code point, a prefix first: -1, 0 or 1.
zoo_compare_text <- function(a, b) {
  x <- utf8ToInt(enc2utf8(a))
  y <- utf8ToInt(enc2utf8(b))
  n <- min(length(x), length(y))
  differ <- which(x[seq_len(n)] != y[seq_len(n)])
  if (length(differ)) {
    return(if (x[differ[1L]] < y[differ[1L]]) -1L else 1L)
  }
  sign(length(x) - length(y))
}

zoo_compare_findings <- function(f, g) {
  order <- zoo_compare_text(f$check, g$check)
  if (order != 0L) {
    return(order)
  }
  # Part names are ASCII, which the radix method sorts by code point.
  parts <- function(scope) {
    lapply(sort(names(scope), method = "radix"), function(name) c(name, scope[[name]]))
  }
  x <- parts(f$scope)
  y <- parts(g$scope)
  for (i in seq_len(min(length(x), length(y)))) {
    for (j in 1:2) {
      order <- zoo_compare_text(x[[i]][j], y[[i]][j])
      if (order != 0L) {
        return(order)
      }
    }
  }
  sign(length(x) - length(y))
}

# Sorts findings by check and then by scope, comparing the parts of a scope
# in ascending order of part name, as pairs of name and value, code point by
# code point. Stops on two findings with the same check and scope.
zoo_order <- function(findings) {
  sorted <- list()
  for (finding in findings) {
    position <- length(sorted) + 1L
    while (position > 1L) {
      order <- zoo_compare_findings(sorted[[position - 1L]], finding)
      if (order == 0L) {
        stop(paste0("Two expected findings of ", finding$check, " have the same scope."),
             call. = FALSE)
      }
      if (order < 0L) {
        break
      }
      position <- position - 1L
    }
    sorted <- append(sorted, list(finding), after = position - 1L)
  }
  sorted
}

# Writers -----------------------------------------------------------------

# Writes the bytes of a string marked UTF-8.
zoo_write_text <- function(text, path) {
  connection <- file(path, "wb")
  on.exit(close(connection))
  writeBin(charToRaw(enc2utf8(text)), connection)
}

# A field of a CSV file, quoted as RFC 4180 writes it, with each '"'
# doubled, when it holds ',', '"', CR or LF.
zoo_csv_field <- function(text) {
  vapply(text, function(s) {
    points <- utf8ToInt(s)
    if (!any(points %in% c(44L, 34L, 13L, 10L))) {
      return(s)
    }
    doubled <- unlist(lapply(points, function(p) if (p == 34L) c(34L, 34L) else p))
    intToUtf8(c(34L, doubled, 34L))
  }, "", USE.NAMES = FALSE)
}

# Writes a data frame as data.csv (fixtures/zoo/README.md). fields are the
# fields of the table block, which name the columns in order, digits the
# digits of each number column, 2 unless given, and missing the text written
# for a missing value of a column, the empty field unless given.
zoo_write_csv <- function(data, fields, path, eol = "\n", digits = list(), missing = list()) {
  names <- vapply(fields, function(field) field$name, "")
  types <- vapply(fields, function(field) if (is.null(field$type)) "string" else field$type, "")
  if (!identical(names(data), names)) {
    stop("The columns of the data are not the fields of the table block.", call. = FALSE)
  }
  columns <- lapply(seq_along(names), function(i) {
    name <- names[i]
    values <- data[[name]]
    text <- switch(
      types[i],
      number = zoo_number(values, if (is.null(digits[[name]])) 2L else digits[[name]]),
      integer = zoo_number(values, 0L),
      boolean = ifelse(values, "true", "false"),
      enc2utf8(as.character(values))
    )
    text[is.na(text)] <- if (is.null(missing[[name]])) "" else missing[[name]]
    zoo_csv_field(text)
  })
  records <- c(paste0(zoo_csv_field(enc2utf8(names)), collapse = ","),
               do.call(paste, c(columns, sep = ",")))
  zoo_write_text(paste0(records, eol, collapse = ""), path)
}

# The JSON text of a string, escaping '"', '\' and the control characters.
zoo_json_string <- function(s) {
  points <- utf8ToInt(enc2utf8(s))
  hex <- c(as.character(0:9), letters[1:6])
  escaped <- lapply(points, function(p) {
    if (p == 34L || p == 92L) {
      return(c(92L, p))
    }
    if (p >= 32L) {
      return(p)
    }
    short <- c("8" = 98L, "9" = 116L, "10" = 110L, "12" = 102L, "13" = 114L)[as.character(p)]
    if (!is.na(short)) {
      return(c(92L, unname(short)))
    }
    utf8ToInt(paste0("\\u00", hex[p %/% 16L + 1L], hex[p %% 16L + 1L]))
  })
  intToUtf8(c(34L, unlist(escaped), 34L))
}

# The JSON number of a double: a whole number below 2^53 as its digits, a
# non-finite value as the string 'NaN', 'Infinity' or '-Infinity', and any
# other value rounded to the significant digits given, 17 by default, which
# give back the double, without trailing zeros. The digits come from the
# correctly rounded decimal expansion that C's printf gives for a double,
# since 17 digits exceed what integer arithmetic in doubles holds, and are
# then placed by integer arithmetic. No string is formatted.
zoo_json_number <- function(x, digits = 17L) {
  if (is.nan(x)) {
    return("\"NaN\"")
  }
  if (is.na(x)) {
    stop("A missing value cannot be written as JSON.", call. = FALSE)
  }
  if (is.infinite(x)) {
    return(if (x > 0) "\"Infinity\"" else "\"-Infinity\"")
  }
  sign <- if (x < 0) "-" else ""
  if (x == floor(x) && abs(x) < 2^53) {
    return(if (x == 0) "0" else paste0(sign, zoo_digits(abs(x))))
  }
  expansion <- sprintf(paste0("%.", digits - 1L, "e"), abs(x))
  exponent <- as.integer(substring(expansion, digits + 3L))
  digits <- paste0(substr(expansion, 1L, 1L), substr(expansion, 3L, digits + 1L))
  digits <- sub("0+$", "", digits)
  k <- nchar(digits)
  if (exponent >= 21L || exponent <= -7L) {
    mantissa <- if (k > 1L) paste0(substr(digits, 1L, 1L), ".", substring(digits, 2L)) else digits
    return(paste0(sign, mantissa, "e", if (exponent < 0L) "-" else "+", zoo_digits(abs(exponent))))
  }
  if (exponent < 0L) {
    return(paste0(sign, "0.", strrep("0", -exponent - 1L), digits))
  }
  if (k <= exponent + 1L) {
    return(paste0(sign, digits, strrep("0", exponent + 1L - k)))
  }
  paste0(sign, substr(digits, 1L, exponent + 1L), ".", substring(digits, exponent + 2L))
}

zoo_json_scalar <- function(x, digits = 17L) {
  if (inherits(x, "zoo_decimal")) {
    return(unclass(x))
  }
  if (is.logical(x)) {
    return(if (is.na(x)) "null" else if (x) "true" else "false")
  }
  if (is.numeric(x)) {
    return(zoo_json_number(as.double(x), digits))
  }
  if (is.character(x)) {
    return(if (is.na(x)) "null" else zoo_json_string(x))
  }
  stop("A value of class ", class(x)[1L], " cannot be written as JSON.", call. = FALSE)
}

zoo_json_kind <- function(x) {
  if (is.null(x)) {
    return("null")
  }
  if (is.list(x)) {
    return(if (!is.null(names(x))) "object" else "array")
  }
  if (inherits(x, "zoo_array") || length(x) != 1L) "array" else "scalar"
}

# JSON text of a value. A named list is an object, an unnamed list or an
# atomic vector made with zoo_array() or zn(), or of a length other than 1,
# an array, and NULL is null. indent gives the indentation of each level as
# Python's json.dumps(indent = 2) writes it, or NULL for compact text, and
# digits the significant digits of a real (zoo_json_number()).
zoo_json <- function(x, indent = NULL, depth = 0L, digits = 17L) {
  kind <- zoo_json_kind(x)
  if (kind == "null") {
    return("null")
  }
  if (kind == "scalar") {
    return(zoo_json_scalar(x, digits))
  }
  if (kind == "object") {
    keys <- names(x)
    items <- vapply(seq_along(x), function(i) {
      separator <- if (is.null(indent)) ":" else ": "
      paste0(zoo_json_string(keys[i]), separator,
             zoo_json(x[[i]], indent, depth + 1L, digits))
    }, "")
    open <- "{"
    close <- "}"
  } else {
    values <- if (is.list(x)) x else as.list(unclass(x))
    items <- vapply(values, function(v) zoo_json(v, indent, depth + 1L, digits), "")
    open <- "["
    close <- "]"
  }
  if (!length(items)) {
    return(paste0(open, close))
  }
  if (is.null(indent)) {
    return(paste0(open, paste0(items, collapse = ","), close))
  }
  inner <- strrep(" ", indent * (depth + 1L))
  outer <- strrep(" ", indent * depth)
  paste0(open, "\n", paste0(inner, items, collapse = ",\n"), "\n", outer, close)
}

# The significant digits of the reals of expected.json. The helpers of this
# file compute some of its reals, such as the smallest eigenvalue of
# zoo_gram(), with sums and matrix products whose last bits depend on the
# platform's long double and on the BLAS of the R that runs them, and 12
# digits lie well within the tolerance of conventions.md (Comparison across
# languages) while leaving those bits out. regenerate.R --check compares the
# reals of expected.json within a tolerance, since rounding can still fall
# on either side of a boundary.
zoo_real_digits <- 12L

# Compares two texts of expected.json: their strings, punctuation and whole
# numbers exactly, and each other number within a relative tolerance of
# 1e-10, far inside the tolerance of conventions.md for reals and far above
# the last digit that zoo_real_digits writes. Returns NULL when they match
# and otherwise where they first differ.
zoo_same_expected <- function(a, b) {
  pattern <- "\"(?:[^\"\\\\]|\\\\.)*\"|-?[0-9]+(?:[.][0-9]+)?(?:[eE][-+]?[0-9]+)?"
  split <- function(text) {
    found <- gregexpr(pattern, text, perl = TRUE)[[1L]]
    tokens <- regmatches(text, list(found))[[1L]]
    between <- regmatches(text, list(found), invert = TRUE)[[1L]]
    list(tokens = tokens, between = between)
  }
  x <- split(a)
  y <- split(b)
  if (length(x$tokens) != length(y$tokens) || !identical(x$between, y$between)) {
    return("in its structure")
  }
  for (i in seq_along(x$tokens)) {
    s <- x$tokens[i]
    t <- y$tokens[i]
    if (identical(s, t)) {
      next
    }
    real <- !startsWith(s, "\"") && !startsWith(t, "\"") && grepl("[.eE]", paste0(s, t))
    if (!real) {
      return(paste0("at the value ", t))
    }
    u <- as.numeric(s)
    v <- as.numeric(t)
    if (abs(u - v) > 1e-10 * max(abs(u), abs(v))) {
      return(paste0("at the real ", t, ", which the generator writes as ", s))
    }
  }
  NULL
}

# Writes a JSON file with a final LF in one of two layouts: 'declaration',
# indented by two spaces at each level, and 'expected', the layout of
# expected.json and index.json, with each top-level member on a line of its
# own in compact JSON, apart from the elements of findings and fixtures,
# which take a line each, and its reals rounded to zoo_real_digits.
zoo_write_json <- function(x, path, layout = c("declaration", "expected")) {
  layout <- match.arg(layout)
  text <- if (layout == "declaration") {
    zoo_json(x, indent = 2L)
  } else {
    compact <- function(value) zoo_json(value, digits = zoo_real_digits)
    members <- vapply(names(x), function(name) {
      value <- x[[name]]
      body <- if (name %in% c("findings", "fixtures") && length(value)) {
        paste0("[\n", paste0("  ", vapply(value, compact, ""), collapse = ",\n"), "\n ]")
      } else {
        compact(value)
      }
      paste0(" ", zoo_json_string(name), ": ", body)
    }, "")
    paste0("{\n", paste0(members, collapse = ",\n"), "\n}")
  }
  zoo_write_text(paste0(text, "\n"), path)
}

# Self-test ----------------------------------------------------------------

# Known answers for the writers, the labels, the order of findings and the
# checks of drawn properties, which regenerate.R --check runs. Returns one
# message for each answer that differs.
zoo_self_test <- function() {
  problems <- character(0)
  expect <- function(label, actual, wanted) {
    if (!identical(actual, wanted)) {
      problems <<- c(problems, paste0("zoo.R self-test: ", label))
    }
  }
  expect("zoo_number", zoo_number(c(1.006, -0.004, -0.006, 12, NA, 0.125), 2),
         c("1.01", "0.00", "-0.01", "12.00", NA, "0.13"))
  expect("zoo_number with no digits", zoo_number(c(2.5, -2.5), 0), c("3", "-2"))
  expect("zoo_label", zoo_label("P", c(1, 24, 240)), c("P001", "P024", "P240"))
  expect("zoo_access", zoo_access("Z24", "T2"),
         list(outcome_access = "T2", reason = "Pathology zoo fixture Z24.", exploratory = TRUE))
  expect("zoo_round", zoo_round(c(0.125, -1.234), 2), c(0.13, -1.23))
  expect("zoo_json_number", vapply(c(0.5, 0.1, 80, -3, 1e-7, 1.5e21, 123.25, NaN, -Inf),
                                   zoo_json_number, ""),
         c("0.5", "0.10000000000000001", "80", "-3", "9.9999999999999995e-8", "1.5e+21",
           "123.25", "\"NaN\"", "\"-Infinity\""))
  expect("zoo_json_number with 12 digits",
         vapply(c(0.1, 0.27556532819175461, 0.2755653281917807, 1e-7, 2 / 3, 1234567.8912345),
                zoo_json_number, "", digits = 12L),
         c("0.1", "0.275565328192", "0.275565328192", "1e-7", "0.666666666667",
           "1234567.89123"))
  jose <- intToUtf8(c(74L, 111L, 115L, 233L))
  expect("zoo_json_string", charToRaw(zoo_json_string(paste0(jose, "\"\\\n", intToUtf8(1L)))),
         charToRaw(enc2utf8(paste0("\"", jose, "\\\"\\\\\\n\\u0001\""))))
  expect("zoo_json", zoo_json(list(a = zn("x"), b = list(), c = zoo_object(), d = NULL,
                                   e = zoo_decimal("0.25"), f = c(1, 2))),
         "{\"a\":[\"x\"],\"b\":[],\"c\":{},\"d\":null,\"e\":0.25,\"f\":[1,2]}")
  expect("zoo_same_expected", list(
    zoo_same_expected("{\"a\":[0.275565328192,2,\"x 1.5\"]}",
                      "{\"a\":[0.2755653281917807,2,\"x 1.5\"]}"),
    zoo_same_expected("{\"a\":[0.275565328192]}", "{\"a\":[0.275565329]}"),
    zoo_same_expected("{\"a\":[2]}", "{\"a\":[3]}"),
    zoo_same_expected("{\"a\":\"x 1.5\"}", "{\"a\":\"x 1.6\"}"),
    zoo_same_expected("{\"a\":1.5}", "{\"a\":[1.5]}")),
    list(NULL, "at the real 0.275565329, which the generator writes as 0.275565328192",
         "at the value 3", "at the value \"x 1.6\"", "in its structure"))
  expect("zoo_json indented", zoo_json(list(a = zn("x"), b = list()), indent = 2L),
         "{\n  \"a\": [\n    \"x\"\n  ],\n  \"b\": []\n}")
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  zoo_write_csv(
    data.frame(id = c("1,2", "\"3\"", jose), n = c(1, NA, 2), x = c(0.5, -1, NA)),
    list(list(name = "id", type = "string"), list(name = "n", type = "integer"),
         list(name = "x", type = "number")),
    path, eol = "\r\n", missing = list(x = "-99")
  )
  expect("zoo_write_csv", readBin(path, "raw", 100L),
         charToRaw(enc2utf8(paste0("id,n,x\r\n\"1,2\",1,0.50\r\n\"\"\"3\"\"\",,-1.00\r\n",
                                   jose, ",2,-99\r\n"))))
  findings <- list(
    zoo_finding("b.c", list(term = "x"), "consistent", "m", why = "w"),
    zoo_finding("b.c", list(factor = "z", term = "a"), "consistent", "m", why = "w"),
    zoo_finding("b.c", list(factor = "z"), "consistent", "m", why = "w"),
    zoo_finding("a.b", why = "w"),
    zoo_finding("b.c", list(factor = "Z", term = "a"), "consistent", "m", why = "w")
  )
  scopes <- vapply(zoo_order(findings), function(f) zoo_json(list(f$check, f$scope)), "")
  expect("zoo_order", scopes, c("[\"a.b\",{}]", "[\"b.c\",{\"factor\":\"Z\",\"term\":\"a\"}]",
                                "[\"b.c\",{\"factor\":\"z\"}]",
                                "[\"b.c\",{\"factor\":\"z\",\"term\":\"a\"}]",
                                "[\"b.c\",{\"term\":\"x\"}]"))
  data <- zoo_with_rng(1, {
    values <- c(a = 0, b = 5, c = 0)
    zoo_check(values, list(positive = function(v) names(v)[v <= 0]),
              function(v, unit) {
                v[unit] <- v[unit] + 1
                v
              })
  })
  expect("zoo_check redraws", attr(data, "zoo_redraws"), 2L)
  flagged <- zoo_check(c(a = 0, b = 5), list(positive = function(v) names(v)[v <= 0]), NULL,
                       "flag")
  expect("zoo_check flag", attr(flagged, "zoo_failed"), "positive: a")
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  before <- if (had) get(".Random.seed", envir = globalenv())
  first <- zoo_with_rng(5, stats::runif(1))
  expect("zoo_with_rng repeats the stream", zoo_with_rng(5, stats::runif(1)), first)
  expect("zoo_with_rng restores the state",
         if (had) get(".Random.seed", envir = globalenv()) else
           exists(".Random.seed", envir = globalenv(), inherits = FALSE),
         if (had) before else FALSE)
  problems
}
