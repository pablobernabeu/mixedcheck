# Attack (b), the interval audit of linear relations (sim/disclosure/README.md).
# From one shareable document alone, the adversary collects the linear
# relations that the specification fixes between its counts: the parts of a
# total, sums and differences that definitions state, the quantities that
# several counts measure in one sample, the nesting of samples, the numerator
# and denominator of a written ratio, the bounds that the detail of a
# suppression implies and, in the full model, the conditions of the decision
# rule that a status shows. Linear programs, with binary variables for the
# relations that need a choice, then give the smallest and the largest value
# of every suppressed count. A count whose interval is
# a single value is determined, and a quantile whose interval lies wholly
# below k shows the side of k that its detail hides.

# A model under construction: variables with bounds and constraints, each
# constraint marked accepted when it reads a value that privacy.md accepts to
# show (the statuses, messages, categories and booleans of the T0 checks).
iv_new <- function(k) {
  env <- new.env(parent = emptyenv())
  env$k <- k
  env$vars <- character(0)
  env$lower <- numeric(0)
  env$upper <- numeric(0)
  env$binary <- logical(0)
  env$constraints <- list()
  env$targets <- list()
  env$qclass <- list()
  env$written_q <- list()
  env
}

iv_big <- 1e6

iv_var <- function(m, name, lower = 0, upper = iv_big, binary = FALSE) {
  i <- match(name, m$vars)
  if (is.na(i)) {
    m$vars <- c(m$vars, name)
    m$lower <- c(m$lower, lower)
    m$upper <- c(m$upper, upper)
    m$binary <- c(m$binary, binary)
  } else {
    m$lower[i] <- max(m$lower[i], lower)
    m$upper[i] <- min(m$upper[i], upper)
  }
  name
}

iv_has <- function(m, name) !is.null(name) && name %in% m$vars

# A constraint sum(coefs * vars) dir rhs. Variables that the model lacks make
# the constraint unusable, and it is dropped.
# structural TRUE marks an inequality or combinatorial relation of the
# design structure, such as rows at least the levels plus the levels with two
# or more rows or the bounds that the position of a quantile implies. Such
# relations determine design-structure values only as residual risk
# (privacy.md, Tiers), so the linear model leaves them out.
iv_add <- function(m, coefs, dir, rhs = 0, accepted = FALSE, structural = FALSE) {
  if (!length(coefs) || !all(vapply(names(coefs), iv_has, NA, m = m))) {
    return(invisible(FALSE))
  }
  m$constraints[[length(m$constraints) + 1L]] <- list(coefs = coefs, dir = dir, rhs = rhs,
                                                      accepted = accepted,
                                                      structural = structural)
  invisible(TRUE)
}

iv_coefs <- function(...) {
  x <- c(...)
  x
}

# The name of the variable of a member of a finding.
iv_name <- function(finding, member) paste0(dh_finding_id(finding), " | ", member)

# The sample on whose rows a finding lies, as the adversary can name it.
iv_sample <- function(finding, entry) {
  if (startsWith(finding$check, "assignment.")) {
    return(paste0("rows of assignment ", finding$scope$column))
  }
  if (finding$check %in% c("structure.label_incidence", "structure.id_scope_evidence")) {
    return(paste0("rows of pair ", finding$scope$first, ",", finding$scope$second))
  }
  entry[["sample"]]
}

iv_q <- function(m, sample, quantity, item = NULL) {
  iv_var(m, paste0("Q ", sample, " | ", quantity, if (!is.null(item)) paste0(" | ", item)))
}

# The item whose levels a by_unit count measures or counts, by name.
iv_item <- function(finding, defined) {
  refs <- defined[["resolved_by"]]
  if (!length(refs)) {
    return(NULL)
  }
  # The combinations of two items are the levels of the item that joins
  # them, as the factor g:h of the grouping columns g and h.
  values <- vapply(refs, function(ref) {
    value <- if (identical(ref[["source"]], "scope")) {
      finding$scope[[ref[["name"]]]]
    } else {
      finding$statistics[[ref[["name"]]]]$value
    }
    value <- unlist(value)
    if (length(value) != 1L) NA_character_ else as.character(value)
  }, "")
  if (anyNA(values)) NULL else paste(values, collapse = ":")
}

# The model of one shareable document. entries are the registry entries by
# identifier. Returns the model with its targets: the suppressed counts, each
# with its detail, kind, class and whether it is a quantile. With details
# FALSE, the model leaves out the bounds that the details of suppression
# imply, and with only the name of a target, it holds no hidden count but
# that one, so that it states what the written values alone give.
iv_model <- function(document, entries, details = TRUE, only = NULL) {
  k <- document$privacy$min_count
  m <- iv_new(k)
  family_class <- document$inputs$model$family_class
  samples <- character(0)
  for (finding in document$findings) {
    if (!identical(finding$status$availability$value, "available")) {
      next
    }
    entry <- entries[[finding$check]]
    sample <- iv_sample(finding, entry)
    samples <- union(samples, sample)
    t0 <- identical(finding$tier, "T0")
    # The counts of the finding, written or suppressed.
    for (name in names(finding$statistics)) {
      s <- finding$statistics[[name]]
      defined <- entry[["statistics"]][[name]]
      if (!identical(s$kind, "count")) {
        next
      }
      v <- iv_name(finding, name)
      if (!is.null(s$value)) {
        iv_var(m, v, s$value, s$value)
      } else if (identical(s$availability$reason, "privacy_suppressed")) {
        if (!is.null(only) && v != only) {
          next
        }
        detail <- s$availability$detail
        iv_var(m, v)
        # The detail 'min_count' marks only values below k (privacy.md,
        # Steps, 3). 'secondary' shows nothing about the side of k, since
        # the rules after step 3 replace 'min_count' with it.
        if (details && identical(detail, "min_count")) {
          iv_var(m, v, upper = k - 1)
        }
        m$targets[[v]] <- list(detail = detail, class = s$count_class %||% "",
                               quantile = !is.null(defined[["quantile"]]),
                               check = finding$check, member = name,
                               finding = dh_finding_id(finding), tier = dh_tier(v))
      } else {
        next
      }
      measure <- defined[["measures"]]
      # The counts of columns give back the levels of the items of their
      # terms with an offset that the coding and the other terms set
      # (registry.md, Statistics and counts), which the audit does not
      # model: the regression attack R8-column-levels gates rule 6, which
      # suppresses them.
      if (!is.null(measure) && !measure %in% c("term_levels", "table_term_levels")) {
        q <- switch(measure,
          table_rows = iv_q(m, "table", "rows"),
          design_rows = iv_q(m, "design", "rows"),
          analysis_rows = iv_q(m, "analysis", "rows"),
          {
            item <- iv_item(finding, defined) %||% finding$scope$factor
            if (is.null(item)) NULL else iv_q(m, sample, measure, item)
          }
        )
        if (!is.null(q)) {
          iv_add(m, stats::setNames(c(1, -1), c(v, q)), "=")
          m$qclass[[q]] <- c(m$qclass[[q]], s$count_class %||% "")
          if (!is.null(s$value)) {
            m$written_q[[q]] <- s$value
          }
        }
      }
    }
    # The support.
    for (member in c("rows", "distinct")) {
      given <- if (member == "rows") finding$support$rows else finding$support$contributors$distinct
      v <- iv_name(finding, paste0("support.", member))
      if (!is.null(given$value)) {
        iv_var(m, v, given$value, given$value)
      } else if (is.null(only) || v == only) {
        detail <- given$availability$detail
        # support.contributors.distinct keeps 'min_count' below k, so with
        # 'secondary' it is at least k, as validation reads it (documents.md,
        # Shareable documents).
        at_least_k <- details && member == "distinct" && identical(detail, "secondary")
        iv_var(m, v, upper = if (details && identical(detail, "min_count")) k - 1 else iv_big,
               lower = if (at_least_k) k else 0)
        m$targets[[v]] <- list(detail = detail, class = "person", quantile = FALSE,
                               check = finding$check, member = paste0("support.", member),
                               finding = dh_finding_id(finding), tier = dh_tier(v))
      }
    }
    # The support counts the sample that the entry names, also for a finding
    # on the rows of an assignment or of a pair (documents.md, Support).
    own <- entry[["sample"]]
    iv_add(m, stats::setNames(c(1, -1), c(iv_name(finding, "support.rows"), iv_q(m, own, "rows"))),
           "=")
    for (member in c("rows", "distinct")) {
      given <- if (member == "rows") finding$support$rows else finding$support$contributors$distinct
      if (!is.null(given$value)) {
        m$written_q[[iv_q(m, own, if (member == "rows") "rows" else "contributors")]] <- given$value
      }
    }
    basis <- finding$support$contributors$basis
    distinct <- iv_name(finding, "support.distinct")
    iv_add(m, stats::setNames(c(1, -1), c(distinct, iv_q(m, own, "contributors"))), "=")
    if (identical(basis, "grouping_factors")) {
      iv_grouping_contributors(m, document, own)
    } else if (identical(basis, "rows")) {
      iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, own, "contributors"), iv_q(m, own, "rows"))),
             "=")
    }
    iv_check_relations(m, finding, entry, family_class, t0)
    iv_part_bounds(m, finding, entry)
    iv_ratios(m, finding, entry)
    iv_status_relations(m, finding, entry, t0)
  }
  iv_sample_relations(m, samples)
  iv_difference_targets(m)
  iv_firing_bounds(m, document)
  iv_quantity_targets(m, only)
  m
}

# The quantities by which the table and the design sample exceed the
# analysis sample, which are outcome-derived (privacy.md, Tiers): the rows
# and contributors without an outcome and, for each item, the levels and
# the levels with two or more rows that lose every outcome, or all but one.
# Each is a target of tier A that the audit reports when it has one value
# below k.
iv_difference_targets <- function(m) {
  pattern <- "^Q analysis \\| (.*)$"
  for (v in grep(pattern, m$vars, value = TRUE)) {
    quantity <- sub(pattern, "\\1", v)
    if (grepl("^levels_with_one_row", quantity)) next
    for (s in c("table", "design")) {
      other <- paste0("Q ", s, " | ", quantity)
      if (!iv_has(m, other)) next
      # The levels of an item whose counts resolve as non-person in the
      # larger sample differ by levels that hold two members or more, which
      # are not person counts: written beside each other they show their
      # difference as other non-person counts do, and only a difference that
      # the written values give although the larger sample's levels are
      # hidden is a determination (privacy.md, Across findings, rule 1).
      non_person <- grepl("^levels", quantity) && "non_person" %in% m$qclass[[other]]
      d <- iv_var(m, paste0("D ", s, " minus analysis | ", quantity))
      iv_add(m, stats::setNames(c(1, -1, 1), c(d, other, v)), "=")
      m$targets[[d]] <- list(detail = "", class = if (non_person) "non_person" else "person",
                             quantile = FALSE, check = "difference", member = quantity,
                             finding = paste(s, "minus analysis"), tier = dh_tier(d),
                             difference = TRUE, larger = other)
    }
  }
}

# The quantities of the analysis sample that no written count measures, its
# rows, contributors and, for each item, its levels, its levels with two rows
# or more and its levels with one row, as targets of tier A (privacy.md,
# Tiers). A quantity that a written count measures is not hidden.
iv_quantity_targets <- function(m, only = NULL) {
  if (!is.null(only)) {
    return()
  }
  for (v in grep("^Q analysis \\| ", m$vars, value = TRUE)) {
    if (!is.null(m$written_q[[v]]) || !is.null(m$targets[[v]])) {
      next
    }
    m$targets[[v]] <- list(detail = "", class = "person", quantile = FALSE, check = "quantity",
                           member = sub("^Q analysis \\| ", "", v), finding = "analysis",
                           tier = dh_tier(v), quantity = TRUE)
  }
}

# The bounds that the part_of rule implies when it does not fire (privacy.md,
# Within a finding): a written part of a person total that is hidden shows
# that the total exceeds it, and the sum of the written parts, by k or more.
iv_part_bounds <- function(m, finding, entry) {
  defined <- entry[["statistics"]]
  k <- m$k
  for (total in unique(unlist(lapply(defined, function(s) s[["part_of"]])))) {
    t <- finding$statistics[[total]]
    if (is.null(t) || !is.null(t$value) || !identical(t$count_class, "person")) {
      next
    }
    parts <- Filter(function(name) {
      identical(defined[[name]][["part_of"]], total) && !is.null(finding$statistics[[name]]$value)
    }, names(finding$statistics))
    if (!length(parts)) {
      next
    }
    tv <- iv_name(finding, total)
    for (part in parts) {
      iv_add(m, stats::setNames(c(1, -1), c(tv, iv_name(finding, part))), ">=", k,
             structural = TRUE)
    }
    iv_add(m, stats::setNames(c(1, rep(-1, length(parts))),
                              c(tv, vapply(parts, function(p) iv_name(finding, p), ""))), ">=", k,
           structural = TRUE)
  }
}

# The bounds that rule 1 implies when it does not fire beside the analysis
# sample (privacy.md, Across findings): a quantity of the table or the design
# sample that a written count measures was compared with the analysis
# sample's, which it exceeds by k or more unless it is 0. The rows and
# contributors are always compared, and the levels and the levels with two
# rows of an item whose counts resolve as person counts in the larger sample.
# The analysis sample is shown when a finding of a T1 or T2 check is
# available.
iv_firing_bounds <- function(m, document) {
  shown <- any(vapply(document$findings, function(f) {
    f$tier %in% c("T1", "T2") && identical(f$status$availability$value, "available")
  }, NA))
  if (!shown) {
    return()
  }
  pattern <- "^Q (table|design) \\| (.*)$"
  for (q in grep(pattern, names(m$written_q), value = TRUE)) {
    value <- m$written_q[[q]]
    quantity <- sub(pattern, "\\2", q)
    if (value == 0 || grepl("^levels_with_one_row", quantity)) {
      next
    }
    if (grepl("^levels", quantity) && !("person" %in% m$qclass[[q]])) {
      next
    }
    analysed <- paste0("Q analysis | ", quantity)
    if (iv_has(m, analysed)) {
      iv_add(m, stats::setNames(1, analysed), "<=", value - m$k, structural = TRUE)
    }
  }
}

# With the basis grouping_factors, the contributors of a sample are the
# levels of the factor with the fewest levels there: no more than the levels
# of each factor and equal to those of one, which binary variables choose,
# once for each sample.
iv_grouping_contributors <- function(m, document, sample) {
  factors <- iv_document_factors(document)
  distinct <- iv_q(m, sample, "contributors")
  if (!length(factors) || iv_has(m, paste0("B ", distinct, " = ", factors[1L]))) {
    return()
  }
  choices <- character(0)
  for (f in factors) {
    levels <- iv_q(m, sample, "levels", f)
    iv_add(m, stats::setNames(c(1, -1), c(distinct, levels)), "<=")
    b <- iv_var(m, paste0("B ", distinct, " = ", f), 0, 1, binary = TRUE)
    iv_add(m, stats::setNames(c(1, -1, -iv_big), c(distinct, levels, b)), ">=", -iv_big)
    choices <- c(choices, b)
  }
  iv_add(m, stats::setNames(rep(1, length(choices)), choices), "=", 1)
}

# The grouping factors of a document, by name, as the scopes of its
# findings of structure.cluster_sizes name them: the check yields one finding
# for each grouping factor, whatever the syntax of its random terms.
iv_document_factors <- function(document) {
  unique(unlist(lapply(document$findings, function(finding) {
    if (identical(finding$check, "structure.cluster_sizes")) finding$scope$factor
  })))
}

# The quantities of nested samples: the analysis sample within the design
# sample within the table, and the rows of an assignment or of a pair within
# the design sample. Within a sample, the levels of an item are its levels
# with one row and with two or more, and the rows hold at least one row of
# each level with one row and two of each other level.
iv_sample_relations <- function(m, samples) {
  items <- unique(sub("^Q [^|]+\\| (levels|levels_with_two_rows|levels_with_one_row) \\| ", "",
                      grep("^Q .*\\| levels", m$vars, value = TRUE)))
  chain <- c("table", "design", "analysis")
  for (i in 1:2) {
    iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, chain[i], "rows"), iv_q(m, chain[i + 1L], "rows"))),
           ">=")
  }
  nested <- list(c("design", "analysis"))
  for (s in samples[startsWith(samples, "rows of ")]) {
    nested[[length(nested) + 1L]] <- c("design", s)
  }
  for (pair in nested) {
    for (q in c("rows", "contributors")) {
      iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, pair[1L], q), iv_q(m, pair[2L], q))), ">=")
    }
    for (item in items) {
      for (q in c("levels", "levels_with_two_rows")) {
        iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, pair[1L], q, item), iv_q(m, pair[2L], q, item))),
               ">=")
      }
      # Every level that the smaller sample lacks holds rows of the larger.
      iv_add(m, stats::setNames(c(1, -1, -1, 1), c(iv_q(m, pair[1L], "rows"), iv_q(m, pair[2L], "rows"),
                                                  iv_q(m, pair[1L], "levels", item),
                                                  iv_q(m, pair[2L], "levels", item))), ">=",
             structural = TRUE)
    }
  }
  for (s in union(c("table", "design", "analysis"), samples)) {
    iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, s, "rows"), iv_q(m, s, "contributors"))), ">=",
           structural = TRUE)
    # The levels of the combinations of two items are at least those of
    # each.
    for (item in items[grepl(":", items, fixed = TRUE)]) {
      for (part in intersect(strsplit(item, ":", fixed = TRUE)[[1L]], items)) {
        iv_add(m, stats::setNames(c(1, -1), c(iv_q(m, s, "levels", item), iv_q(m, s, "levels", part))),
               ">=", structural = TRUE)
      }
    }
    for (item in items) {
      levels <- iv_q(m, s, "levels", item)
      one <- iv_q(m, s, "levels_with_one_row", item)
      two <- iv_q(m, s, "levels_with_two_rows", item)
      iv_add(m, stats::setNames(c(1, -1, -1), c(levels, one, two)), "=")
      iv_add(m, stats::setNames(c(1, -1, -2), c(iv_q(m, s, "rows"), one, two)), ">=",
             structural = TRUE)
    }
  }
}

# The relations that the definitions of registry.md and the entries state
# between the counts of one finding.
iv_check_relations <- function(m, finding, entry, family_class, t0) {
  n <- function(name) iv_name(finding, name)
  rel <- function(coefs, names, dir, rhs = 0, accepted = FALSE, structural = FALSE) {
    iv_add(m, stats::setNames(coefs, vapply(names, n, "")), dir, rhs, accepted, structural)
  }
  value <- function(name) finding$statistics[[name]]$value
  switch(finding$check,
    sample.raw_vs_analysis = {
      rel(c(1, -1, -1), c("rows_raw", "rows_kept", "rows_dropped"), "=")
    },
    keys.duplicates = {
      rel(c(1, -1, -1), c("duplicated_keys", "identical_keys", "conflicting_keys"), "=")
      rel(c(1, -2), c("duplicate_rows", "duplicated_keys"), ">=", structural = TRUE)
      rel(c(1, -1, -1), c("rows", "duplicate_rows", "missing_key_rows"), ">=")
    },
    structure.cluster_sizes = {
      rel(c(1, -1), c("rows", "levels"), ">=", structural = TRUE)
      rel(c(1, -1), c("levels", "singletons"), ">=")
      rel(c(1, -2, 1), c("rows", "levels", "singletons"), ">=", structural = TRUE)
      order <- c("smallest", "lower_quartile", "median", "upper_quartile", "largest")
      for (i in 1:4) rel(c(1, -1), order[i + 1:0], ">=", structural = TRUE)
      iv_var(m, n("smallest"), lower = 1)
      # smallest is 1 exactly when some level has one row.
      if (iv_has(m, n("smallest")) && iv_has(m, n("singletons"))) {
        b <- iv_var(m, paste0("B ", n("smallest"), " is 1"), 0, 1, binary = TRUE)
        iv_add(m, stats::setNames(c(1, -iv_big), c(n("singletons"), b)), "<=", structural = TRUE)
        iv_add(m, stats::setNames(c(1, -1), c(n("singletons"), b)), ">=", structural = TRUE)
        iv_add(m, stats::setNames(c(1, iv_big), c(n("smallest"), b)), "<=", 1 + iv_big, structural = TRUE)
        iv_add(m, stats::setNames(c(1, 1), c(n("smallest"), b)), ">=", 2, structural = TRUE)
      }
      j <- value("levels")
      if (!is.null(j)) {
        for (q in c("smallest", "largest")) {
          bound <- if (q == "smallest") "<=" else ">="
          rel(c(1, -j), c("rows", q), if (q == "smallest") ">=" else "<=", structural = TRUE)
        }
        # The quantile at position p of J values: the J - pos + 1 values from
        # it are at least it, and it is 1 exactly when singletons reach pos.
        for (q in c("lower_quartile", "median", "upper_quartile")) {
          pos <- ceiling(c(lower_quartile = 0.25, median = 0.5, upper_quartile = 0.75)[[q]] * j)
          rel(c(1, -(j - pos + 1)), c("rows", q), ">=", pos - 1, structural = TRUE)
          if (iv_has(m, n(q)) && iv_has(m, n("singletons"))) {
            b <- iv_var(m, paste0("B ", n(q), " is 1"), 0, 1, binary = TRUE)
            iv_add(m, stats::setNames(c(1, -pos), c(n("singletons"), b)), ">=", structural = TRUE)
            iv_add(m, stats::setNames(c(1, -iv_big), c(n("singletons"), b)), "<=", pos - 1, structural = TRUE)
            iv_add(m, stats::setNames(c(1, iv_big), c(n(q), b)), "<=", 1 + iv_big, structural = TRUE)
            iv_add(m, stats::setNames(c(1, 1), c(n(q), b)), ">=", 2, structural = TRUE)
          }
        }
      }
    },
    structure.within_between = {
      rel(c(1, -1), c("varying_levels", "informative_levels"), ">=")
      rel(c(1, -1), c("multi_row_levels", "varying_levels"), ">=")
      if (identical(value("status"), "within")) {
        rel(c(1, -1), c("multi_row_levels", "varying_levels"), "=", accepted = TRUE)
      }
    },
    identifiability.df_budget = {
      rel(c(1, -1), c("levels", "budget"), ">=")
    },
    identifiability.levels_vs_dimension = {
      counterparts <- value("counterparts")
      if (is.null(counterparts)) {
        rel(c(1, -1), c("levels", "bound"), ">=")
        rel(c(1, -1), c("levels", "bound"), "<=", 1)
      } else {
        rel(c(1, -1), c("levels", "bound"), "=", if (isTRUE(counterparts)) 1 else 0,
            accepted = TRUE)
      }
      rel(c(1, -1), c("levels", "informative_levels"), ">=")
    },
    identifiability.residual_confounding = {
      rel(c(1, -1), c("cells", "replicated_cells"), ">=")
    },
    structure.label_incidence = {
      rel(c(1, -1), c("combinations", "levels_first"), ">=", structural = TRUE)
      rel(c(1, -1), c("combinations", "levels_second"), ">=", structural = TRUE)
      rel(c(1, -1), c("levels_first", "first_in_several"), ">=")
      rel(c(1, -1), c("levels_second", "second_in_several"), ">=")
      # A label in several combinations holds two of them or more. These
      # bound a part to 0 only when the relation, a category of a T0 check
      # that privacy.md accepts to show, says that its column is nested.
      rel(c(1, -1, -1), c("combinations", "levels_first", "first_in_several"), ">=",
          accepted = t0, structural = TRUE)
      rel(c(1, -1, -1), c("combinations", "levels_second", "second_in_several"), ">=",
          accepted = t0, structural = TRUE)
      relation <- value("relation")
      if (identical(relation, "crossed")) {
        for (side in c("levels_first", "levels_second")) {
          other <- setdiff(c("levels_first", "levels_second"), side)
          if (!is.null(value(other))) {
            rel(c(1, -value(other)), c("combinations", side), "=", accepted = TRUE)
          }
        }
      } else if (identical(relation, "first_nested_in_second")) {
        rel(c(1, -1), c("combinations", "levels_first"), "=", accepted = TRUE)
      } else if (identical(relation, "second_nested_in_first")) {
        rel(c(1, -1), c("combinations", "levels_second"), "=", accepted = TRUE)
      }
    },
    structure.id_scope_evidence = {
      rel(c(1, -1), c("levels", "shared_labels"), ">=")
      rel(c(1, -1), c("shared_labels", "changing_labels"), ">=")
    },
    structure.aliased_factors = {
      rel(c(1, -1), c("coarser_levels", "informative_levels"), ">=")
      rel(c(1, -1), c("rows", "informative_rows"), ">=")
      rel(c(1, -2), c("informative_rows", "informative_levels"), ">=", structural = TRUE)
      # The finer factor has a level for each coarser level and a further one
      # for each coarser level that holds two or more.
      coarser <- unlist(value("coarser"))
      finer <- setdiff(unlist(finding$scope[c("first", "second")]), coarser)
      if (length(coarser) == 1L && length(finer) == 1L) {
        iv_add(m, stats::setNames(c(1, -1, -1), c(iv_q(m, "design", "levels", finer),
                                                 n("coarser_levels"), n("informative_levels"))),
               ">=", structural = TRUE)
      }
    },
    labels.unicode_forms = {
      rel(c(1, -2), c("spellings", "labels"), ">=", structural = TRUE)
    },
    assignment.constant_within_unit = {
      rel(c(1, -1), c("units", "mixed_units"), ">=")
    },
    assignment.design_df = {
      rel(c(1, -1), c("units", "design_df"), ">=")
    },
    design.rank_deficiency = {
      rel(c(1, -1), c("columns", "kept"), ">=")
    },
    outcome.boundary_shares = {
      rel(c(1, -1, -1), c("rows", "at_floor", "at_ceiling"), ">=")
    },
    outcome.constant_clusters = {
      rel(c(1, -1), c("multi_row_levels", "constant_levels"), ">=")
    },
    outcome.minority_events = {
      if (family_class == "bernoulli") {
        rel(c(1, 1, -1), c("events", "non_events", "support.rows"), "=")
      }
      rel(c(1, -1), c("levels", "levels_without_minority"), ">=")
    },
    outcome.zero_shares = {
      rel(c(1, -1), c("rows", "zeros"), ">=")
      rel(c(1, -1), c("levels", "all_zero_levels"), ">=")
      rel(c(1, -1), c("zeros", "all_zero_levels"), ">=", structural = TRUE)
    },
    outcome.separation = {
      if (family_class == "bernoulli") {
        rel(c(1, 1, -1), c("events", "non_events", "support.rows"), "=")
      } else {
        rel(c(1, -1), c("support.rows", "events"), ">=")
        rel(c(1, -1), c("support.rows", "non_events"), ">=")
        rel(c(1, 1, -1), c("events", "non_events", "support.rows"), ">=")
      }
    }
  )
}

# A written ratio r of a numerator and a denominator: numerator = r times
# the denominator, within the rounding of r.
iv_ratios <- function(m, finding, entry) {
  for (name in names(finding$statistics)) {
    s <- finding$statistics[[name]]
    defined <- entry[["statistics"]][[name]]
    if (!identical(s$kind, "ratio") || is.null(s$value) || !is.numeric(s$value)) {
      next
    }
    num <- iv_name(finding, defined[["numerator"]])
    den <- iv_name(finding, defined[["denominator"]])
    r <- s$value
    iv_add(m, stats::setNames(c(1, -r), c(num, den)), "<=", 1e-6)
    iv_add(m, stats::setNames(c(1, -r), c(num, den)), ">=", -1e-6)
  }
}

# The conditions of a decision rule that a written status shows, for the
# conditions of the form 'X is above 0.' and 'X is 0.': the rule that held,
# found by its finding status and message, and the rules before it, which
# did not hold. These read the statuses and messages that privacy.md
# accepts to show for the T0 checks.
iv_status_relations <- function(m, finding, entry, t0) {
  rules <- entry[["decision"]][["rules"]]
  status <- finding$status$finding$value
  message <- finding$message$id
  if (is.null(status) || is.null(message) || !length(rules)) {
    return()
  }
  held <- which(vapply(rules, function(r) identical(r[["finding"]], status) &&
                         identical(r[["message"]], message), NA))
  otherwise <- identical(entry[["decision"]][["otherwise"]][["message"]], message) &&
    identical(entry[["decision"]][["otherwise"]][["finding"]], status)
  if (length(held) != 1L && !otherwise) {
    return()
  }
  last <- if (length(held) == 1L) held else length(rules)
  for (i in seq_len(last)) {
    condition <- rules[[i]][["condition"]]
    holds <- length(held) == 1L && i == held
    above <- regmatches(condition, regexec("^(\\w+) is above 0\\.$", condition))[[1L]]
    zero <- regmatches(condition, regexec("^(\\w+) is 0\\.$", condition))[[1L]]
    if (length(above) == 2L) {
      v <- iv_name(finding, above[2L])
      if (holds) iv_add(m, stats::setNames(1, v), ">=", 1, accepted = t0)
      else iv_add(m, stats::setNames(1, v), "=", 0, accepted = t0)
    } else if (length(zero) == 2L) {
      v <- iv_name(finding, zero[2L])
      if (holds) iv_add(m, stats::setNames(1, v), "=", 0, accepted = t0)
      else iv_add(m, stats::setNames(1, v), ">=", 1, accepted = t0)
    }
  }
}

# The program of a model, without the constraints marked accepted when
# strict is TRUE, as the matrix, directions and right-hand sides of lp(),
# with every variable bounded.
iv_program <- function(m, strict, linear = FALSE) {
  keep <- Filter(function(c) !(strict && c$accepted) && !(linear && isTRUE(c$structural)),
                 m$constraints)
  nv <- length(m$vars)
  lower <- which(m$lower > 0)
  a <- matrix(0, length(keep) + length(lower) + nv, nv)
  for (i in seq_along(keep)) {
    a[i, match(names(keep[[i]]$coefs), m$vars)] <- keep[[i]]$coefs
  }
  a[cbind(length(keep) + seq_along(lower), lower)] <- 1
  a[cbind(length(keep) + length(lower) + seq_len(nv), seq_len(nv))] <- 1
  # lp() takes the constraints as triplets of row, column and value, which
  # it reads faster than a dense matrix.
  nonzero <- which(a != 0, arr.ind = TRUE)
  list(triplets = cbind(nonzero[, 1L], nonzero[, 2L], a[nonzero]),
       dir = c(vapply(keep, function(c) c$dir, ""), rep(">=", length(lower)), rep("<=", nv)),
       rhs = c(vapply(keep, function(c) c$rhs, 0), m$lower[lower], m$upper))
}

# The smallest and largest value of a variable under a program, or NA when
# the program has no solution.
iv_bounds <- function(m, program, target) {
  objective <- replace(numeric(length(m$vars)), match(target, m$vars), 1)
  # The binary variables are integers. The counts are not, which keeps the
  # programs fast, and the interval is that of the continuous program rounded
  # inwards to integers, so it still holds every integer solution.
  binary <- which(m$binary)
  solve <- function(direction) {
    out <- lpSolve::lp(direction, objective, , program$dir, program$rhs,
                       dense.const = program$triplets, int.vec = binary)
    if (out$status != 0L) NA_real_ else out$objval
  }
  c(lower = ceiling(solve("min") - 1e-7) + 0, upper = floor(solve("max") + 1e-7) + 0)
}

# The interval audit of one document. internal maps the name of each target
# to its internal value, when known, to check the model: an interval that
# excludes the internal value is reported as an error of the harness.
# Returns a data frame with one row for each finding: the target, its
# detail, its interval in the strict model, the verdict and, for a
# determination that only the full model makes, 'accepted'.
iv_audit <- function(document, entries, internal = NULL, shared = NULL) {
  m <- iv_model(document, entries)
  k <- m$k
  measures <- dh_measures(document, entries)
  ids <- vapply(document$findings, dh_finding_id, "")
  out <- list()
  programs <- list(full = iv_program(m, FALSE))
  for (target in names(m$targets)) {
    t <- m$targets[[target]]
    full <- iv_bounds(m, programs$full, target)
    # The strict program has fewer constraints, so its interval holds that
    # of the full program, and it is solved only when the full interval
    # could make a finding.
    strict <- full
    if (!anyNA(full) && (full[1L] == full[2L] || full[2L] < k)) {
      if (is.null(programs$strict)) {
        programs$strict <- iv_program(m, TRUE)
      }
      strict <- iv_bounds(m, programs$strict, target)
    }
    truth <- internal[[target]]
    if (!is.null(truth) && (length(truth) != 1L || is.na(truth))) {
      truth <- NULL
    }
    verdict <- NULL
    if (is.na(t$tier)) {
      verdict <- "no tier"
    } else if (anyNA(full) || anyNA(strict)) {
      verdict <- "model error"
    } else if (!is.null(truth) && (truth < full[1L] - 1e-6 || truth > full[2L] + 1e-6)) {
      verdict <- "model error"
    } else if (isTRUE(t$difference)) {
      # A difference that one value below k gives is determined, and one of
      # k or more is not hidden by any rule. A difference of 0 that the
      # design structure forces, because the quantity of the larger sample is
      # 0, takes that value whatever the outcome, and is accepted. A
      # difference of the levels of a non-person item is written as the
      # other non-person counts are when a written count measures the levels
      # of the larger sample.
      if (strict[1L] == strict[2L] && strict[1L] < k) {
        larger <- t$larger
        forced <- strict[1L] == 0 &&
          iv_bounds(m, programs$strict, larger)[[2L]] == 0
        shown <- identical(t$class, "non_person") && !is.null(m$written_q[[larger]])
        verdict <- if (forced || shown) "accepted" else "determined"
      }
    } else if (isTRUE(t$quantity)) {
      # A quantity of the analysis sample that no written count measures is
      # determined when the strict program gives it one value, unless the
      # design structure forces that value, as it forces 0 levels with two
      # rows where the design sample has none, or the value is k or more and
      # the written values alone give it, as they give the levels with one
      # row of the levels and the levels with two rows when both are written.
      if (strict[1L] == strict[2L]) {
        same <- sub("^Q analysis ", "Q design ", target)
        forced <- strict[1L] == 0 && iv_has(m, same) &&
          iv_bounds(m, programs$strict, same)[[2L]] == 0
        # The class non_person of the analysed levels of an item, which the
        # document writes, shows that none has one row.
        item <- sub("^Q analysis \\| levels_with_one_row \\| ", "", target)
        classes <- unlist(m$qclass[paste0("Q analysis | ", c("levels", "levels_with_two_rows"),
                                          " | ", item)])
        forced <- forced || (strict[1L] == 0 && item != target && "non_person" %in% classes)
        derived <- strict[1L] >= k && iv_written_point(document, entries, target)
        verdict <- if (forced || derived) "accepted" else "determined"
      }
    } else if (t$quantile && (iv_implied_quantile(document, t, strict) ||
                                isTRUE(shared[[target]] >= k))) {
      verdict <- "accepted"
    } else if (t$member == "singletons" && strict[2L] == 0 && iv_non_person(document, t)) {
      verdict <- "accepted"
    } else if (t$member == "smallest" && strict[2L] == 1 && iv_one_row_members(document, t)) {
      # The class person of the levels shows that a level holds at most one
      # member, and so one row when every member has one row (privacy.md,
      # Guarantees).
      verdict <- "accepted"
    } else if (t$detail %in% c("min_count_rule", "dominance") && strict[1L] >= k) {
      # Step 2 hides every person count of a finding with few contributors
      # and leaves its support to step 3, so a count of k or more that the
      # written supports give back shows no count below k.
      verdict <- "accepted"
    } else if (strict[1L] == strict[2L] &&
               dh_written_elsewhere(measures, match(t$finding, ids), t$member)) {
      verdict <- "accepted"
    } else if (strict[1L] == strict[2L] && strict[1L] >= k &&
               iv_written_point(document, entries, target)) {
      # A count of k or more that the written values give back without the
      # details or any other hidden count is derived from what the document
      # writes, such as rows_dropped as rows_raw minus the written rows of
      # the design sample (README, Threat model).
      verdict <- "accepted"
    } else if (strict[1L] == strict[2L] && identical(t$tier, "B")) {
      # A design-structure value is a leak only when the linear relations
      # alone determine it, and residual risk otherwise (privacy.md, Tiers).
      if (is.null(programs$linear)) {
        programs$linear <- iv_program(m, TRUE, linear = TRUE)
      }
      linear <- iv_bounds(m, programs$linear, target)
      verdict <- if (!anyNA(linear) && linear[1L] == linear[2L]) "determined" else "residual"
    } else if (strict[1L] == strict[2L]) {
      verdict <- "determined"
    } else if (full[1L] == full[2L]) {
      verdict <- "accepted"
    } else if (strict[2L] < k && identical(t$class, "person")) {
      # A count that the written values show below k gives back no more than
      # the detail 'min_count' would, and the details of the minimum-count and
      # dominance rules show values below k themselves.
      verdict <- if (t$detail %in% c("min_count", "min_count_rule", "dominance")) NULL else "bound"
      # A bound that only the bounds of details give shows no more than the
      # report's '<' k of the counts that carry them (privacy.md,
      # Guarantees): it is a leak when the written values without details
      # still show the target below k.
      if (identical(verdict, "bound") && identical(t$tier, "A") &&
          !iv_bound_without_details(document, entries, target, k)) {
        verdict <- "bound via details"
      }
    }
    if (!is.null(verdict)) {
      out[[length(out) + 1L]] <- data.frame(
        target = target, detail = t$detail %||% "", class = t$class, lower = strict[1L],
        upper = strict[2L], full_lower = full[1L], full_upper = full[2L],
        truth = if (is.null(truth)) NA_real_ else truth, verdict = verdict,
        tier = t$tier %||% "B", stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) {
    return(data.frame(target = character(0), detail = character(0), class = character(0),
                      lower = numeric(0), upper = numeric(0), full_lower = numeric(0),
                      full_upper = numeric(0), truth = numeric(0), verdict = character(0),
                      tier = character(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}

# Whether the written values alone give one value to a target: a model of
# the document without the bounds that details imply and without any hidden
# count but the target, in which the target still has one value.
iv_written_point <- function(document, entries, target) {
  m <- iv_model(document, entries, details = FALSE, only = target)
  if (!target %in% m$vars) {
    return(FALSE)
  }
  bounds <- iv_bounds(m, iv_program(m, TRUE), target)
  !anyNA(bounds) && bounds[[1L]] == bounds[[2L]]
}

# Whether a quantile is implied by a written count of the levels that hold
# its value, which privacy.md (Guarantees) accepts: singletons of
# structure.cluster_sizes, written and so at least k, implies a quantile of 1
# up to its position, and levels_without_minority of outcome.minority_events
# a median_minority of 0.
iv_implied_quantile <- function(document, target, interval) {
  if (interval[[2L]] > 1) {
    return(FALSE)
  }
  finding <- Find(function(f) identical(f$check, target$check) &&
                    identical(f$status$availability$value, "available"), document$findings)
  count <- switch(target$check,
    structure.cluster_sizes = if (interval[[1L]] >= 1) finding$statistics$singletons$value,
    outcome.minority_events = if (interval[[2L]] == 0) finding$statistics$levels_without_minority$value
  )
  !is.null(count)
}

# Whether the counts of the levels of the factor of a finding of
# structure.cluster_sizes resolve as non_person, which shows that every
# level holds two members or more and so two rows or more (privacy.md,
# Across findings, rule 2, and Guarantees).
iv_non_person <- function(document, target) {
  finding <- Find(function(f) identical(dh_finding_id(f), target$finding), document$findings)
  identical(finding$statistics$levels$count_class, "non_person")
}

# Whether the levels of the factor of a finding of structure.cluster_sizes
# resolve as person counts with a disclosure unit whose members each have one
# row, as written rows equal to written contributors show.
iv_one_row_members <- function(document, target) {
  finding <- Find(function(f) identical(dh_finding_id(f), target$finding), document$findings)
  support <- finding$support
  identical(finding$statistics$levels$count_class, "person") &&
    identical(support$contributors$basis, "disclosure_unit") &&
    !is.null(support$rows$value) && identical(support$rows$value, support$contributors$distinct$value)
}

# The internal values of the targets of a run, by the names of iv_model().
iv_internal <- function(result) {
  values <- list()
  for (i in seq_along(result$findings)) {
    f <- result$findings[[i]]
    if (!isTRUE(f$available)) {
      next
    }
    for (name in names(f$values)) {
      v <- f$values[[name]]
      if (is.numeric(v) && length(v) == 1L) {
        values[[iv_name(f, name)]] <- v
      }
    }
    values[[iv_name(f, "support.rows")]] <- f$support$rows
    values[[iv_name(f, "support.distinct")]] <- f$support$distinct
  }
  values
}

# Whether the written values without the bounds of details show a target
# below k.
iv_bound_without_details <- function(document, entries, target, k) {
  m <- iv_model(document, entries, details = FALSE)
  if (!target %in% m$vars) {
    return(FALSE)
  }
  bounds <- iv_bounds(m, iv_program(m, TRUE), target)
  !anyNA(bounds) && bounds[[2L]] < k
}
