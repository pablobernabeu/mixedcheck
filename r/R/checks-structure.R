# The checks of the prefix structure (spec/registry/checks/structure.*.yaml).

# structure.label_incidence: how the labels of two grouping columns occur
# together in the rows of the design sample in which both are present, and
# the relation that the declaration states for the units they label.
audit_check_structure_label_incidence <- function(run, entry, elements) {
  lapply(elements, function(element) {
    first <- element$first
    second <- element$second
    pair <- column_pair_rows(run, first, second)
    incidence <- label_incidence(pair$first, pair$second)
    relation <- if (!incidence$first_in_several && !incidence$second_in_several) {
      "identical"
    } else if (!incidence$first_in_several) {
      "first_nested_in_second"
    } else if (!incidence$second_in_several) {
      "second_nested_in_first"
    } else if (incidence$combinations == incidence$levels_first * incidence$levels_second) {
      "crossed"
    } else {
      "partially_crossed"
    }
    declared <- declared_relation(run$declaration, first, second)
    nested <- startsWith(declared$value, "nested_")
    factors <- run$factors
    alone <- function(column, other) {
      any(vapply(factors, function(keys) column %in% keys && !other %in% keys, NA))
    }
    inner_alone <- nested && alone(declared$inner, declared$outer)
    # The IR splits the units of a column that appears in no grouping factor
    # without the other column of the pair: the inner column of a pair
    # declared nested, and either column of any other pair.
    split <- if (nested) !inner_alone else !(alone(first, second) && alone(second, first))
    composite <- split && any(vapply(factors, function(keys) all(c(first, second) %in% keys), NA))
    statistics <- list(
      levels_first = incidence$levels_first,
      levels_second = incidence$levels_second,
      combinations = incidence$combinations,
      first_in_several = incidence$first_in_several,
      second_in_several = incidence$second_in_several,
      relation = relation,
      declared = declared$value,
      inner = if (nested) declared$inner else character(0),
      outer = if (nested) declared$outer else character(0),
      composite = composite,
      inner_alone = inner_alone
    )
    if (nested) {
      statistics$inner_in_several <- if (identical(declared$inner, first)) {
        incidence$first_in_several
      } else {
        incidence$second_in_several
      }
    }
    several <- nested && statistics$inner_in_several > 0
    check_element(statistics, rules = c(
      declared$value == "nested_within_parent" && inner_alone && several,
      declared$value == "nested_global" && several,
      declared$value == "nested_mobile" && composite && several,
      declared$value == "crossed" && composite
    ), rows = pair$rows)
  })
}

# The rows of the design sample in which both columns of a pair are present,
# with the codes of the two columns in those rows, compared by value.
column_pair_rows <- function(run, first, second) {
  a <- column_codes(run, first)[run$design]
  b <- column_codes(run, second)[run$design]
  both <- !is.na(a) & !is.na(b)
  list(rows = run$design[both], first = a[both], second = b[both])
}

# The counts of structure.label_incidence for the codes of two columns in
# the same rows: the labels of each, their distinct combinations and the
# labels of each that occur with more than one label of the other.
label_incidence <- function(a, b) {
  combined <- !duplicated(pair_codes(a, b))
  list(
    levels_first = length(unique(a)),
    levels_second = length(unique(b)),
    combinations = sum(combined),
    first_in_several = sum(tabulate(a[combined]) > 1L),
    second_in_several = sum(tabulate(b[combined]) > 1L)
  )
}

# The relation that a declaration states for the units whose columns member
# lists one column of a pair alone (the statistic declared of
# structure.label_incidence), with the inner and outer column of a pair
# declared nested.
declared_relation <- function(declaration, first, second) {
  none <- list(value = "none", inner = NULL, outer = NULL)
  units <- declared_units(declaration)
  alone <- function(column) {
    Filter(function(unit) {
      columns <- comparison_form(as.character(unlist(unit[["columns"]])))
      length(columns) == 1L && columns == column
    }, units)
  }
  unit_first <- alone(first)
  unit_second <- alone(second)
  if (length(unit_first) != 1L || length(unit_second) != 1L) {
    return(none)
  }
  unit_first <- unit_first[[1L]]
  unit_second <- unit_second[[1L]]
  nesting <- function(inner, outer, unit) {
    value <- if (identical(unit[["id_scope"]], "within_parent")) {
      "nested_within_parent"
    } else if (is.null(unit[["membership"]]) || identical(unit[["membership"]], "fixed")) {
      "nested_global"
    } else {
      "nested_mobile"
    }
    list(value = value, inner = inner, outer = outer)
  }
  parent <- unit_parent(declaration, unit_first)
  if (!is.null(parent) && identical(parent[["name"]], unit_second[["name"]])) {
    return(nesting(first, second, unit_first))
  }
  parent <- unit_parent(declaration, unit_second)
  if (!is.null(parent) && identical(parent[["name"]], unit_first[["name"]])) {
    return(nesting(second, first, unit_second))
  }
  crossings <- declaration[["crossings"]]
  for (i in seq_along(crossings)) {
    pointers <- c(path_pointer("crossings", i - 1L, "units", 0L),
                  path_pointer("crossings", i - 1L, "units", 1L))
    if (any(vapply(pointers, function(p) declaration_inferred(declaration, p), NA))) {
      next
    }
    named <- as.character(unlist(crossings[[i]][["units"]]))
    if (setequal(named, c(unit_first[["name"]], unit_second[["name"]]))) {
      return(list(value = "crossed", inner = NULL, outer = NULL))
    }
  }
  none
}

# structure.id_scope_evidence: for a crossed pair that the declaration does
# not relate and the IR does not combine, the attributes that are constant
# within most combinations of the two columns, in each direction, and how
# many shared labels of the labels column change them.
audit_check_structure_id_scope_evidence <- function(run, entry, elements) {
  incidence <- run$results[["structure.label_incidence"]]
  agreement <- agreement_fraction(entry)
  pool <- compared_key_columns(run)
  lapply(elements, function(element) {
    found <- scope_finding(incidence, element)
    if (is.null(found) || !identical(found$values$declared, "none") ||
        !identical(found$values$composite, FALSE) ||
        !found$values$relation %in% c("crossed", "partially_crossed")) {
      return(NULL)
    }
    first <- element$first
    second <- element$second
    pair <- column_pair_rows(run, first, second)
    candidates <- setdiff(pool, c(first, second))
    forward <- scope_direction(run, pair$first, pair$second, pair$rows, candidates, agreement)
    backward <- scope_direction(run, pair$second, pair$first, pair$rows, candidates, agreement)
    has_forward <- length(forward$attributes) > 0L
    has_backward <- length(backward$attributes) > 0L
    reverse <- if (has_forward != has_backward) {
      has_backward
    } else {
      has_forward && backward$changing > 0 && forward$changing == 0
    }
    reported <- if (reverse) backward else forward
    statistics <- list(
      labels_column = if (reverse) second else first,
      context_column = if (reverse) first else second,
      levels = if (reverse) found$values$levels_second else found$values$levels_first,
      shared_labels = reported$shared,
      attributes = reported$attributes,
      tied = has_forward && has_backward && forward$changing > 0 && backward$changing > 0
    )
    if (length(reported$attributes)) {
      statistics$changing_labels <- reported$changing
      statistics$changing_attribute <- reported$attribute
    }
    values <- statistics
    if (length(reported$attributes) && reported$shared > 0) {
      values$changing_share <- reported$changing / reported$shared
    }
    empty <- !length(reported$attributes)
    check_element(statistics, rules = c(
      empty,
      statistics$tied,
      threshold_holds(entry, "most_change", values),
      threshold_holds(entry, "any_change", values)
    ), assessability = empty, rows = pair$rows)
  })
}

# One direction of structure.id_scope_evidence, with labels and context the
# codes of the two columns in the given rows: the shared labels, the
# candidate attributes in code-point order and the smallest number of shared
# labels that change one of them, with the first attribute that gives it.
# Attribute values are compared by value, with missing values equal to each
# other.
scope_direction <- function(run, labels, context, rows, candidates, agreement) {
  combination <- pair_codes(labels, context)
  combination <- match(combination, unique(combination))
  distinct <- !duplicated(combination)
  shared <- tabulate(labels[distinct], nbins = max(labels)) > 1L
  n <- max(combination)
  attributes <- character(0)
  counts <- numeric(0)
  for (key in candidates) {
    values <- value_codes(run, key, rows, missing_level = TRUE)
    varies <- function(groups) {
      cells <- !duplicated(pair_codes(groups, values))
      tabulate(groups[cells], nbins = max(groups)) > 1L
    }
    constant <- sum(!varies(combination))
    if (constant * 10^agreement$d >= agreement$m * n && any(varies(context))) {
      attributes <- c(attributes, key)
      counts <- c(counts, sum(varies(labels) & shared))
    }
  }
  found <- list(shared = sum(shared), attributes = attributes)
  if (length(attributes)) {
    found$changing <- min(counts)
    found$attribute <- attributes[which.min(counts)]
  }
  found
}

# structure.aliased_factors: whether two grouping factors divide the design
# sample into the same groups, one into finer groups than the other or
# neither, and whether their random terms share a column.
audit_check_structure_aliased_factors <- function(run, entry, elements) {
  lapply(elements, function(element) {
    first <- factor_levels(run, element$first)
    second <- factor_levels(run, element$second)
    combined <- !duplicated(pair_codes(first$code, second$code))
    first_single <- all(tabulate(first$code[combined], nbins = first$count) == 1L)
    second_single <- all(tabulate(second$code[combined], nbins = second$count) == 1L)
    partition <- if (first_single && second_single) {
      "identical"
    } else if (first_single) {
      "first_finer"
    } else if (second_single) {
      "second_finer"
    } else {
      "other"
    }
    statistics <- list(
      partition = partition,
      shared_columns = factors_share_column(run, element$first, element$second),
      finer = character(0),
      coarser = character(0),
      rows = length(run$design)
    )
    if (partition %in% c("first_finer", "second_finer")) {
      finer <- if (partition == "first_finer") first else second
      coarser <- if (partition == "first_finer") second else first
      statistics$finer <- if (partition == "first_finer") element$first else element$second
      statistics$coarser <- if (partition == "first_finer") element$second else element$first
      contained <- tabulate(coarser$code[combined], nbins = coarser$count)
      informative <- contained >= 2L
      statistics$coarser_levels <- coarser$count
      statistics$informative_levels <- sum(informative)
      statistics$informative_rows <- sum(informative[coarser$code])
    }
    check_element(statistics, rules = c(
      partition == "identical" && statistics$shared_columns,
      partition == "identical",
      partition %in% c("first_finer", "second_finer")
    ))
  })
}

# Whether a random term of one grouping factor and a random term of another
# have a column in common: two columns with the same name, or two columns
# whose values are equal in every row of the design sample.
factors_share_column <- function(run, first, second) {
  random <- run$ir$random
  of <- function(factor) which(vapply(random, function(term) identical(term$factor, factor), NA))
  column_names <- function(t) vapply(random[[t]]$columns, function(column) column$name, "")
  for (s in of(first)) {
    for (t in of(second)) {
      if (length(intersect(column_names(s), column_names(t)))) {
        return(TRUE)
      }
      a <- random_term_values(run, s)$values
      b <- random_term_values(run, t)$values
      for (i in seq_len(ncol(a))) {
        for (j in seq_len(ncol(b))) {
          if (all(a[, i] == b[, j])) {
            return(TRUE)
          }
        }
      }
    }
  }
  FALSE
}

# structure.cluster_sizes: the distribution of the rows of the design sample
# over the levels of a grouping factor.
audit_check_structure_cluster_sizes <- function(run, entry, elements) {
  lapply(elements, function(element) {
    levels <- factor_levels(run, element$factor)
    sizes <- sort(tabulate(levels$code, nbins = levels$count))
    j <- levels$count
    n <- length(run$design)
    # The quantile p of the J sizes is the size at position ceil(J x p).
    at <- function(numerator, denominator) sizes[(j * numerator + denominator - 1) %/% denominator]
    squares <- sum(sizes^2)
    statistics <- list(
      levels = j,
      rows = n,
      smallest = sizes[1L],
      lower_quartile = at(1, 4),
      median = at(1, 2),
      upper_quartile = at(3, 4),
      largest = sizes[j],
      singletons = sum(sizes == 1L),
      effective_size = (n - squares / n) / (j - 1),
      intercept = factor_has_intercept(run, element$factor)
    )
    one_row <- j == n && statistics$intercept
    family <- run$family_class
    check_element(statistics, rules = c(
      one_row && family %in% c("gaussian", "other"),
      one_row && family == "bernoulli",
      one_row && family %in% c("binomial", "poisson")
    ))
  })
}

# Whether a random term of a grouping factor has an intercept.
factor_has_intercept <- function(run, factor) {
  any(vapply(run$ir$random, function(term) {
    identical(term$factor, factor) && random_term_has_intercept(term)
  }, NA))
}

# Whether a random term has an intercept, a term without variables.
random_term_has_intercept <- function(term) {
  any(vapply(term$terms, function(t) !length(t$variables), NA))
}

# structure.within_between: for a fixed term and a grouping factor, the
# levels in which the term's kept columns vary, the levels in which they
# vary in every direction, the status inferred with the tolerance of
# agreement and, for one numeric column, its intraclass correlation.
audit_check_structure_within_between <- function(run, entry, elements) {
  agreement <- agreement_fraction(entry)
  ir <- run$ir
  term_names <- vapply(ir$fixed$terms, function(term) term$name, "")
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  lapply(elements, function(element) {
    t <- match(element$term, term_names)
    kept <- which(run$x_kept & column_terms == t)
    if (!length(kept)) {
      return(NULL)
    }
    term <- ir$fixed$terms[[t]]
    values <- run$x[, kept, drop = FALSE]
    patterns <- row_patterns(values)
    levels <- factor_levels(run, element$factor)
    sizes <- tabulate(levels$code, nbins = levels$count)
    several <- sizes >= 2L
    cells <- !duplicated(pair_codes(levels$code, patterns))
    varying <- several & tabulate(levels$code[cells], nbins = levels$count) > 1L
    informative <- levels_of_full_rank(values, levels$code, levels$count, among = varying,
                                       difference = TRUE)
    statistics <- list(
      multi_row_levels = sum(several),
      varying_levels = sum(varying),
      informative_levels = sum(informative),
      slope_requested = slope_requested(run, term, element$factor)
    )
    if (any(several)) {
      statistics$status <- if (pooled_constancy(levels$code, patterns, agreement)$constant) {
        "between"
      } else if (all(varying[several])) {
        "within"
      } else {
        "partially_within"
      }
    }
    numeric <- vapply(term$variables, function(v) {
      identical(named_member(ir$predictors, v$variable)$kind, "numeric")
    }, NA)
    if (length(kept) == 1L && all(numeric)) {
      statistics <- c(statistics, intraclass_correlation(values[, 1L], levels$code,
                                                         levels$count, sizes))
    }
    none <- !any(several)
    between <- identical(statistics$status, "between")
    slope <- statistics$slope_requested
    check_element(statistics, rules = c(
      none,
      between && slope && statistics$varying_levels == 0,
      between && slope,
      identical(statistics$status, "partially_within") && slope
    ), assessability = none)
  })
}

# Whether a random term of a grouping factor has a term whose set of
# variables equals that of a fixed term, as estimands are matched with terms.
slope_requested <- function(run, term, factor) {
  wanted <- vapply(term$variables, function(v) v$variable, "")
  any(vapply(run$ir$random, function(random) {
    identical(random$factor, factor) && any(vapply(random$terms, function(t) {
      variables <- vapply(t$variables, function(v) v$variable, "")
      length(variables) > 0L && setequal(variables, wanted)
    }, NA))
  }, NA))
}

# The ANOVA intraclass correlation of a column over the levels of a factor
# and the share of its variation within levels (structure.within_between).
# The column is divided by its largest absolute value, which changes neither
# statistic, so that the squares neither overflow nor underflow, and the
# overall and level means of the scaled column are summed exactly and
# divided once. Both are absent for a column that is constant, compared by
# value, and the share also when SSB + SSW is 0. The correlation is NaN when
# J is 1, when N equals J or when its denominator is 0, so that its absence
# depends on no count of levels or rows.
intraclass_correlation <- function(x, level, count, sizes) {
  found <- list()
  n <- length(x)
  if (all(x == x[1L])) {
    return(found)
  }
  x <- x / max(abs(x))
  mean <- exact_sum(x) / n
  means <- exact_group_sums(x, level, count) / sizes
  ssb <- sum(sizes * (means - mean)^2)
  ssw <- sum((x - means[level])^2)
  if (ssb + ssw != 0) {
    found$within_share <- ssw / (ssb + ssw)
  }
  found$icc <- NaN
  if (count > 1L && n > count) {
    msb <- ssb / (count - 1)
    msw <- ssw / (n - count)
    n0 <- (n - sum(sizes^2) / n) / (count - 1)
    denominator <- msb + (n0 - 1) * msw
    if (denominator != 0) {
      found$icc <- (msb - msw) / denominator
    }
  }
  found
}

# structure.connectivity: the crossed groups of levels of two grouping
# factors that rows link, and the fixed terms that are constant within them.
audit_check_structure_connectivity <- function(run, entry, elements) {
  aliased <- run$results[["structure.aliased_factors"]]
  agreement <- agreement_fraction(entry)
  ir <- run$ir
  column_terms <- vapply(ir$fixed$columns, function(column) column$term + 1, 0)
  lapply(elements, function(element) {
    found <- scope_finding(aliased, element)
    if (is.null(found) || !identical(found$values$partition, "other")) {
      return(NULL)
    }
    first <- factor_levels(run, element$first)
    second <- factor_levels(run, element$second)
    component <- bipartite_components(first$code, second$code, first$count, second$count)
    of_first <- component[seq_len(first$count)]
    of_second <- component[first$count + seq_len(second$count)]
    crossed <- tabulate(of_first, nbins = length(component)) >= 2L &
      tabulate(of_second, nbins = length(component)) >= 2L
    if (!any(crossed)) {
      return(NULL)
    }
    row_component <- of_first[first$code]
    inside <- crossed[row_component]
    groups <- row_component[inside]
    terms <- character(0)
    exact <- TRUE
    for (t in seq_along(ir$fixed$terms)) {
      term <- ir$fixed$terms[[t]]
      kept <- which(run$x_kept & column_terms == t)
      if (!length(term$variables) || !length(kept)) {
        next
      }
      patterns <- row_patterns(run$x[inside, kept, drop = FALSE])
      constancy <- pooled_constancy(groups, patterns, agreement)
      if (constancy$constant) {
        terms <- c(terms, term$name)
        exact <- exact && constancy$exact
      }
    }
    components <- sum(crossed)
    several <- components >= 2L
    check_element(list(components = components, between_component_terms = terms,
                       exact = exact), rules = c(
      several && length(terms) > 0L && exact,
      several && length(terms) > 0L,
      several
    ))
  })
}

# The connected components of the graph whose vertices are the levels of two
# factors, the first's from 1 and the second's after them, and whose edges
# join two levels that occur together in a row. Each round hooks every root
# that has an edge to a root with a smaller number onto the smallest such
# root and then follows the hooks to their roots, so that each round takes
# time that grows with the rows. Returns the component of each vertex,
# numbered from 1 in the order of their smallest vertices.
bipartite_components <- function(first, second, first_count, second_count) {
  edges <- !duplicated(pair_codes(first, second))
  u <- first[edges]
  v <- first_count + second[edges]
  parent <- seq_len(first_count + second_count)
  repeat {
    a <- parent[u]
    b <- parent[v]
    open <- a != b
    if (!any(open)) {
      break
    }
    low <- pmin(a[open], b[open])
    high <- pmax(a[open], b[open])
    ordered <- order(high, low, method = "radix")
    hooked <- !duplicated(high[ordered])
    parent[high[ordered][hooked]] <- low[ordered][hooked]
    repeat {
      jumped <- parent[parent]
      if (all(jumped == parent)) {
        break
      }
      parent <- jumped
    }
  }
  match(parent, unique(parent))
}
