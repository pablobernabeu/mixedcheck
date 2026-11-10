# The checks of the prefix outcome (spec/registry/checks/outcome.*.yaml).

# The outcome over the rows of the analysis sample, for a check of tier T1 or
# T2 that the run reached: the response and trials vectors of step 9, the
# values of the response column as the table reader returns them, with their
# type, and the rows. Every check reads the outcome through this function,
# which records the columns it reads with the check's tier, and step 13
# refuses to write an access log that lacks an entry for a recorded read
# (outcome_reads_logged()).
outcome_values <- function(run, entry) {
  tier <- entry[["tier"]]
  if (tier == "T0" || is.null(run$analysis) ||
      match(tier, tier_names) > match(run$tier, tier_names)) {
    internal_error(sprintf("%s read the outcome at a tier that the run did not reach.",
                           entry[["id"]]))
  }
  response <- run$ir$response
  columns <- c(response$variable, response$trials)
  run$outcome_reads[[length(run$outcome_reads) + 1L]] <- list(tier = tier, columns = columns)
  j <- column_index(run, comparison_form(response$variable))
  list(response = run$response, trials = run$trials,
       values = run$table$values[[j]][run$analysis], type = run$table$types[j],
       rows = run$analysis)
}

# Whether the access log has an entry for every column that a check read
# through outcome_values() at its tier.
outcome_reads_logged <- function(run, entries) {
  logged <- vapply(entries, function(e) paste(e$tier, e$outcome$column %||% ""), "")
  for (read in run$outcome_reads) {
    if (!all(paste(read$tier, read$columns) %in% logged)) {
      internal_error("a check read an outcome column that the access log does not record.")
    }
  }
  invisible(TRUE)
}

# The level of each row of the analysis sample in a grouping factor, from 1,
# and the number of levels, counting only those that occur in the sample.
analysis_levels <- function(run, factor) {
  code <- factor_levels(run, factor)$code[match(run$analysis, run$design)]
  code <- match(code, unique(code))
  list(code = code, count = max(c(code, 0L)))
}

# The member of the declaration's entry for the response, or NULL when it is
# absent or counts as absent (registry.md, Terms).
response_declared <- function(run, member) {
  declaration <- run$declaration
  variables <- declaration[["variables"]]
  response <- run$ir$response$variable
  found <- match(response, comparison_form(as.character(names(variables))))
  if (is.null(response) || is.na(found) ||
      declaration_inferred(declaration, path_pointer("variables", names(variables)[found],
                                                     member))) {
    return(NULL)
  }
  variables[[found]][[member]]
}

# The availability rule declaration_missing of outcome.minority_events and
# outcome.separation: the class is bernoulli, the outcome takes values other
# than 0 and 1, as numbers or logical values, in the analysis sample, and the
# response has no event level.
event_level_missing <- function(run, outcome) {
  if (run$family_class != "bernoulli" || !is.null(run$ir$response$event_level)) {
    return(FALSE)
  }
  switch(outcome$type,
    boolean = FALSE,
    number = !all(outcome$values == 0 | outcome$values == 1),
    TRUE
  )
}

# The events and trials of each row of the analysis sample: the response
# vector and 1 for the class bernoulli, and the events and trials of a
# binomial response.
outcome_events <- function(run, outcome) {
  if (run$family_class == "binomial" && !is.null(outcome$trials)) {
    return(list(events = outcome$response, trials = outcome$trials))
  }
  list(events = outcome$response, trials = rep(1, length(outcome$response)))
}

# outcome.boundary_shares: the rows of the analysis sample at the lower and at
# the upper declared bound of a bounded score.
audit_check_outcome_boundary_shares <- function(run, entry, elements) {
  measurement <- response_declared(run, "measurement")
  if (is.null(measurement)) {
    return(check_unavailable("declaration_missing"))
  }
  if (measurement != "bounded_score") {
    return(list(NULL))
  }
  bounds <- response_declared(run, "bounds")
  if (is.null(bounds)) {
    return(check_unavailable("declaration_missing", "/variables/{outcome}/bounds"))
  }
  outcome <- outcome_values(run, entry)
  if (outcome$type != "number") {
    return(list(NULL))
  }
  statistics <- list(
    rows = length(outcome$values),
    at_floor = sum(outcome$values == as.double(bounds[[1L]])),
    at_ceiling = sum(outcome$values == as.double(bounds[[2L]]))
  )
  values <- statistics
  values$floor_share <- statistics$at_floor / statistics$rows
  values$ceiling_share <- statistics$at_ceiling / statistics$rows
  list(check_element(statistics, rules = threshold_holds(entry, "floor", values) ||
    threshold_holds(entry, "ceiling", values)))
}

# outcome.constant_clusters: the levels of a grouping factor with two or more
# rows of the analysis sample within which the outcome takes one value.
audit_check_outcome_constant_clusters <- function(run, entry, elements) {
  if (!length(elements)) {
    return(list())
  }
  outcome <- outcome_values(run, entry)
  # For the class binomial, a row is coded 1 without events, 2 with as many
  # events as trials and 3 otherwise, and a level is constant when its rows
  # share the code 1 or the code 2.
  binomial <- run$family_class == "binomial" && !is.null(outcome$trials)
  observed <- if (binomial) {
    ifelse(outcome$response == 0, 1, ifelse(outcome$response == outcome$trials, 2, 3))
  } else if (!is.null(outcome$response)) {
    outcome$response
  } else {
    comparison_form(outcome$values)
  }
  codes <- match(observed, unique(observed))
  lapply(elements, function(element) {
    levels <- analysis_levels(run, element$factor)
    several <- tabulate(levels$code, nbins = levels$count) >= 2L
    cells <- !duplicated(pair_codes(levels$code, codes))
    constant <- several & tabulate(levels$code[cells], nbins = levels$count) == 1L
    if (binomial) {
      constant <- constant & tabulate(levels$code[observed == 3], nbins = levels$count) == 0L
    }
    statistics <- list(multi_row_levels = sum(several), constant_levels = sum(constant))
    values <- statistics
    if (statistics$multi_row_levels > 0) {
      values$constant_share <- statistics$constant_levels / statistics$multi_row_levels
    }
    none <- statistics$multi_row_levels == 0
    check_element(statistics, rules = c(
      none,
      threshold_holds(entry, "many", values),
      threshold_holds(entry, "any", values)
    ), assessability = none)
  })
}

# outcome.minority_events: the events and non-events of the analysis sample,
# the levels of a grouping factor without one of the two classes, the median
# level minority count and the minority events per kept fixed-effects column.
audit_check_outcome_minority_events <- function(run, entry, elements) {
  outcome <- outcome_values(run, entry)
  if (event_level_missing(run, outcome)) {
    return(check_unavailable("declaration_missing"))
  }
  counts <- outcome_events(run, outcome)
  events <- sum(counts$events)
  non_events <- sum(counts$trials) - events
  # kept of design.rank_deficiency, which yields no finding without columns.
  required <- run$results[["design.rank_deficiency"]]
  kept <- if (length(required)) required[[1L]]$values$kept else 0
  lapply(elements, function(element) {
    statistics <- list(events = events, non_events = non_events)
    if (kept > 0) {
      statistics$events_per_column <- min(events, non_events) / kept
    }
    model <- is.null(element$factor)
    if (!model) {
      levels <- analysis_levels(run, element$factor)
      level_events <- exact_group_sums(counts$events, levels$code, levels$count)
      level_trials <- exact_group_sums(counts$trials, levels$code, levels$count)
      minority <- pmin(level_events, level_trials - level_events)
      statistics$levels <- levels$count
      statistics$levels_without_minority <- sum(minority == 0)
      statistics$median_minority <- sort(minority)[(levels$count + 1L) %/% 2L]
    }
    check_element(statistics, rules = model)
  })
}

# outcome.zero_shares: the rows of the analysis sample whose count is 0 and
# the levels of a grouping factor in which every count is 0.
audit_check_outcome_zero_shares <- function(run, entry, elements) {
  outcome <- outcome_values(run, entry)
  zero <- if (outcome$type == "number") outcome$values == 0 else rep(FALSE, length(outcome$rows))
  lapply(elements, function(element) {
    statistics <- list(rows = length(zero), zeros = sum(zero))
    model <- is.null(element$factor)
    if (!model) {
      levels <- analysis_levels(run, element$factor)
      statistics$levels <- levels$count
      statistics$all_zero_levels <- sum(tabulate(levels$code[!zero], nbins = levels$count) == 0L)
    }
    check_element(statistics, rules = model)
  })
}

# outcome.separation: whether the kept fixed-effects columns of the analysis
# sample separate the events from the non-events, by the two linear programs
# of the entry, solved by lpSolve and verified in double arithmetic, with the
# range of each coefficient over the optimal face of the first.
audit_check_outcome_separation <- function(run, entry, elements) {
  outcome <- outcome_values(run, entry)
  if (event_level_missing(run, outcome)) {
    return(check_unavailable("declaration_missing"))
  }
  # The solver is named whenever the check passes its family filter and
  # availability rules, also when it solves nothing and when the privacy
  # filter suppresses its finding, so that the list of packages shows nothing
  # about the outcome (documents.md, Results document).
  run$packages[["lpSolve"]] <- getNamespaceVersion("lpSolve")[[1L]]
  parameter <- function(name) json_number_values(entry[["parameters"]][[name]][["value"]])
  tolerances <- list(separation = parameter("separation_tolerance"),
                     feasibility = parameter("feasibility_tolerance"),
                     residue = parameter("residue_tolerance"),
                     involvement = parameter("involvement_tolerance"))
  x <- run$x[match(run$analysis, run$design), , drop = FALSE]
  kept <- sequential_rule(x)
  # The privacy filter reads the kept columns of the analysis sample.
  run$analysis_kept <- kept
  x <- x[, kept, drop = FALSE]
  for (j in seq_len(ncol(x))) {
    x[, j] <- x[, j] / max(abs(x[, j]))
  }
  # One observation with s = 1 for each row with an event and one with
  # s = -1 for each row with a non-event, in the order of the rows.
  counts <- outcome_events(run, outcome)
  rows <- c(which(counts$events > 0), which(counts$events < counts$trials))
  signs <- rep(c(1, -1), c(sum(counts$events > 0), sum(counts$events < counts$trials)))
  ordered <- order(rows, -signs, method = "radix")
  a <- signs[ordered] * x[rows[ordered], , drop = FALSE]
  events <- sum(signs == 1)
  non_events <- sum(signs == -1)
  statistics <- list(columns = ncol(x), events = events, non_events = non_events,
                     both_classes = events > 0 && non_events > 0)
  near <- FALSE
  proximity <- list()
  if (statistics$both_classes) {
    found <- separation_programs(a, tolerances)
    statistics <- c(statistics, found$statistics)
    near <- found$near_threshold
    if (!is.null(statistics$bounds)) {
      statistics$columns_involved <- run$x_columns[kept][
        statistics$bounds[c(FALSE, TRUE)] > tolerances$involvement |
          statistics$bounds[c(TRUE, FALSE)] < -tolerances$involvement]
    }
    proximity <- list(
      separation_tolerance = c(statistics$optimum, statistics$margin, numeric(0)),
      involvement_tolerance = c(statistics$bounds, numeric(0))
    )
  }
  verdict <- statistics$verdict
  one_class <- !statistics$both_classes
  list(check_element(statistics, rules = c(
    one_class,
    is.null(verdict),
    identical(verdict, "complete"),
    identical(verdict, "quasi")
  ), assessability = c(one_class, !one_class && is.null(verdict)),
  proximity = proximity, near_threshold = near))
}

# The programs of outcome.separation on the rows a of s x' for every
# observation: the first, which maximises the sum of s x'b subject to
# s x'b >= 0, the second, which maximises t subject to s x'b >= t, both with
# -1 <= b_j <= 1 and t <= 1, and, for a verdict of quasi or complete, the
# smallest and largest b_j over the optimal face of the first. Returns the
# statistics optimum, margin, verdict and bounds, each when the definition
# gives it, and whether a verified solution makes the finding near_threshold.
separation_programs <- function(a, tolerances) {
  p <- ncol(a)
  sums <- colSums(a)
  near <- FALSE
  # The verified solution of the program that maximises objective'b, or t
  # with margin TRUE, subject to s x'b >= 0, or >= t, sums'b >= floor when
  # floor is given and the bounds: the b of its dual, or of the program
  # itself when the dual has no verified solution. A solution is verified
  # when every u = s x'b is at least minus the feasibility tolerance, and
  # one with some u below minus the residue tolerance makes the finding
  # near_threshold. Without kept columns, b = () is the one solution and
  # needs no solver.
  solve <- function(objective, margin = FALSE, floor = NULL) {
    if (!p) {
      return(list(b = numeric(0), u = numeric(nrow(a))))
    }
    for (formulation in c("dual", "primal")) {
      b <- separation_solver(formulation, a, objective, margin, sums, floor)
      if (is.null(b)) {
        next
      }
      u <- drop(a %*% b)
      if (isTRUE(all(u >= -tolerances$feasibility))) {
        if (any(u < -tolerances$residue)) {
          near <<- TRUE
        }
        return(list(b = b, u = u))
      }
    }
    NULL
  }
  statistics <- list()
  first <- solve(sums)
  if (!is.null(first)) {
    statistics$optimum <- exact_sum(first$u)
  }
  second <- solve(numeric(p), margin = TRUE)
  if (!is.null(second)) {
    statistics$margin <- min(1, second$u)
  }
  if (is.null(first) || is.null(second)) {
    return(list(statistics = statistics, near_threshold = near))
  }
  statistics$verdict <- if (statistics$margin > tolerances$separation) {
    "complete"
  } else if (statistics$optimum > tolerances$separation) {
    "quasi"
  } else {
    "none"
  }
  if (statistics$verdict != "none") {
    # The optimal face: the constraints of the first program with a sum of
    # s x'b of at least the optimum minus the separation tolerance. The
    # smallest b_j maximises -b_j.
    floor <- statistics$optimum - tolerances$separation
    bounds <- numeric(0)
    for (j in seq_len(p)) {
      for (sign in c(-1, 1)) {
        unit <- numeric(p)
        unit[j] <- sign
        found <- solve(unit, floor = floor)
        if (is.null(found)) {
          return(list(statistics = statistics, near_threshold = near))
        }
        bounds <- c(bounds, found$b[j])
      }
    }
    statistics$bounds <- bounds
  }
  list(statistics = statistics, near_threshold = near)
}

# One program of outcome.separation solved by lpSolve::lp() with scale = 0,
# since the columns are already scaled: b for an optimum, NULL otherwise.
# The program maximises objective'b, or t with margin TRUE, subject to
# A b >= 0, or A b - t >= 0, sums'b >= floor when floor is given,
# -1 <= b_j <= 1 and t <= 1, where A is a.
# - 'dual': its dual, which minimises 1'(w+ + w-) - floor r + z over
#   y, r, w+, w-, z >= 0 subject to w+ - w- - A'y - sums r = objective and,
#   with margin TRUE, 1'y + z = 1, with r only when floor is given and z only
#   with margin TRUE. Its p equality constraints have the dual values b,
#   which lp() returns with compute.sens = 1. The program has one constraint
#   for each coefficient, so that its basis has p or p + 1 rows whatever the
#   number of observations.
# - 'primal': the program itself in b = b+ - b- with 0 <= b+_j, b-_j <= 1,
#   the upper bounds written as constraints, so that every right-hand side
#   other than the bounds and floor is 0.
separation_solver <- function(formulation, a, objective, margin, sums, floor) {
  n <- nrow(a)
  p <- ncol(a)
  ident <- diag(1, p)
  if (formulation == "dual") {
    # The constraints in columns and the variables y, r, w+, w- and z in rows.
    columns <- rbind(-a, if (!is.null(floor)) -sums, ident, -ident)
    cost <- c(numeric(n), if (!is.null(floor)) -floor, rep(1, 2 * p))
    rhs <- objective
    if (margin) {
      columns <- rbind(cbind(columns, c(rep(1, n), numeric(2 * p))), c(numeric(p), 1))
      cost <- c(cost, 1)
      rhs <- c(rhs, 1)
    }
    found <- lpSolve::lp("min", cost, columns, rep("=", length(rhs)), rhs,
                         transpose.constraints = FALSE, scale = 0, compute.sens = 1)
    return(if (found$status == 0L) found$duals[seq_len(p)] else NULL)
  }
  rows <- rbind(cbind(a, -a), if (!is.null(floor)) c(sums, -sums),
                cbind(ident, 0 * ident), cbind(0 * ident, ident))
  directions <- c(rep(">=", n), if (!is.null(floor)) ">=", rep("<=", 2 * p))
  rhs <- c(numeric(n), floor, rep(1, 2 * p))
  gain <- c(objective, -objective)
  if (margin) {
    rows <- rbind(cbind(rows, c(rep(-1, n), numeric(2 * p))), c(numeric(2 * p), 1))
    directions <- c(directions, "<=")
    rhs <- c(rhs, 1)
    gain <- c(gain, 1)
  }
  found <- lpSolve::lp("max", gain, rows, directions, rhs, scale = 0)
  if (found$status != 0L) {
    return(NULL)
  }
  found$solution[seq_len(p)] - found$solution[p + seq_len(p)]
}
