# The machinery of the checks of the registry (docs/spec/registry.md and
# documents.md, Findings), which audit() runs in steps 10 and 11
# (03-execution-plan.md, M2). The compiled registry drives it: the order of
# the checks, the family filter, availability, the scope elements, the kinds
# and count classes of the statistics, ratios, quantiles, the decision with
# its thresholds, threshold proximity, validation, assessability, the
# rendering of messages, the support, the resolution of by_unit counts and
# the order of the findings.
#
# A check is one function, named audit_check_ followed by its identifier
# with '.' written as '_', such as audit_check_keys_duplicates(), in the file
# of its prefix (checks-keys.R). It is called as f(run, entry, elements):
#
# - run is the environment of the run (new_run()), with the declaration, the
#   table, the IR, the samples, X and Z, the response at T1 and T2, the
#   results of the checks that the entry requires in run$results and helpers
#   such as sample_rows(), value_codes(), factor_keys(), factor_levels(),
#   random_term_values() and unit_label_columns().
# - entry is the registry entry of the check.
# - elements are the elements of the entry's scope (scope_elements()), each a
#   named list of its parts.
#
# It returns check_unavailable(reason) when an availability rule of the entry
# other than package_missing holds, the first in the entry's order, since the
# machinery checks the package_missing rules, which come first in every
# entry, before calling it. Otherwise it returns a list with one item for
# each element: NULL when applies_when does not hold for the element, and
# otherwise check_element() with the statistics of the element and the
# conditions of the decision and assessability rules. The machinery computes
# the ratios from their counts and does everything else.

# --- What a check returns -----------------------------------------------------------

# The result of a check for one scope element:
# - statistics: the internal values of the statistics, by name, leaving out
#   those that the definition leaves absent and every ratio, which the
#   machinery computes from its numerator and denominator. A count is a
#   whole number, a real a double (NaN and the infinities included), reals a
#   double vector, a category a string, a boolean a logical value, names and
#   labels character vectors.
# - rules: whether the condition of each rule of the decision holds, in the
#   entry's order. threshold_holds() compares a statistic with a threshold.
# - assessability: whether the condition of each assessability rule holds,
#   in the entry's order.
# - items: for a by_unit statistic resolved by a statistic of kind names,
#   the item that the statistic holds, by the statistic's name: the column
#   keys whose combined values form its levels, or the level of each row of
#   the table as integer codes with NA for a row without a level. Without
#   it, the one name that the statistic holds is taken as a grouping factor,
#   a column or a unit, in that order.
# - proximity: for each parameter with a proximity_factor, by name, the
#   computed values that the entry compares with it.
# - near_threshold: TRUE when the definition makes the finding near_threshold
#   for another reason.
# - rows: the rows of the table that the statistics count, over which by_unit
#   counts are resolved, by default the rows of the entry's sample. The
#   privacy filter treats other rows, such as the rows of an assignment, as a
#   sample of their own.
# - label_factors: for a statistic of kind labels, the grouping factor or
#   column whose labels it holds, by the statistic's name, which the privacy
#   filter pairs with each label to give it a pseudonym.
check_element <- function(statistics, rules = logical(0), assessability = logical(0),
                          items = list(), proximity = list(), near_threshold = FALSE,
                          rows = NULL, label_factors = list()) {
  structure(list(statistics = statistics, rules = rules, assessability = assessability,
                 items = items, proximity = proximity, near_threshold = near_threshold,
                 rows = rows, label_factors = label_factors),
            class = "mixedcheck_check_element")
}

# A check that is not available, for the first availability rule of the
# entry with this reason or, for too_large, for the rule whose parameter is
# detail when it is given. detail is needed otherwise only for
# capability_missing, whose rule names no capability.
check_unavailable <- function(reason, detail = NULL) {
  structure(list(reason = reason, detail = detail), class = "mixedcheck_check_unavailable")
}

# An internal error, which indicates a bug in a check or in the machinery.
internal_error <- function(text) {
  stop(paste("Internal error:", text), call. = FALSE)
}

# --- The run ------------------------------------------------------------------------

# The environment of a run after step 8, which the checks read. analysis,
# response and trials are set in step 9 at T1 and T2.
new_run <- function(declaration, table, ir, family_class, tier, model, built) {
  run <- new.env(parent = emptyenv())
  run$declaration <- declaration
  run$table <- table
  run$ir <- ir
  run$family_class <- family_class
  run$tier <- tier
  run$design <- model$design
  run$analysis <- NULL
  run$response <- NULL
  run$trials <- NULL
  run$x <- built$x
  run$x_columns <- built$x_columns
  run$x_kept <- built$kept
  run$z <- built$z
  run$z_columns <- built$z_columns
  run$offset <- built$offset
  run$weights <- built$weights
  # Names of columns and factors are looked up with match(), which compares
  # them in UTF-8, since `[[`, assign() and get() translate a name to the
  # native encoding, which merges distinct names under LC_ALL=C.
  first <- !duplicated(vapply(ir$random, function(term) term$factor, ""))
  factors <- lapply(ir$random[first], function(term) unlist(term$grouping))
  names(factors) <- vapply(ir$random[first], function(term) term$factor, "")
  run$factors <- if (length(factors)) factors else empty_object()
  run$grouping_columns <- unique(unlist(lapply(ir$random, function(term) unlist(term$grouping))))
  run$results <- list()
  run$outcome_reads <- list()
  run$packages <- list()
  run$cache <- new.env(parent = emptyenv())
  run$disclosure <- disclosure_unit(run)
  run
}

# The rows of the table, counted from 1, in a sample: 'table', 'design' or
# 'analysis'.
sample_rows <- function(run, sample) {
  switch(sample,
    table = seq_len(run$table$rows),
    design = run$design,
    analysis = run$analysis %||% internal_error("the analysis sample was not read.")
  )
}

# The position of a column in the table, by its comparison form.
column_index <- function(run, key) {
  j <- match(key, run$table$keys)
  if (is.na(j)) {
    internal_error(sprintf("the table has no column '%s'.", display_text(key)))
  }
  j
}

# The codes of the values of one column in every row of the table, compared
# by value as the table reader compares keys (registry.md, Terms): strings
# after NFC, numbers by value with NaN equal to NaN and negative zero equal
# to zero, and booleans by value. A missing value has the code NA. The cache
# holds them by the column's position, which needs no translation.
column_codes <- function(run, key) {
  j <- column_index(run, key)
  cached <- run$cache[[paste0("codes:", j)]]
  if (!is.null(cached)) {
    return(cached)
  }
  values <- run$table$values[[j]]
  if (is.character(values)) {
    values <- comparison_form(values)
  }
  missing <- run$table$missing[[j]]
  codes <- match(values, unique(values[!missing]))
  codes[missing] <- NA_integer_
  assign(paste0("codes:", j), codes, envir = run$cache)
  codes
}

# The codes of the combined values of several columns in the rows given, by
# default every row of the table, so that two rows have the same code when
# every value is equal. A row with a missing value has the code NA, or, with
# missing_level TRUE, a missing value counts as a value equal only to a
# missing value.
value_codes <- function(run, keys, rows = NULL, missing_level = FALSE) {
  combined <- rep(1, run$table$rows)
  for (key in keys) {
    codes <- column_codes(run, key)
    if (missing_level) {
      codes[is.na(codes)] <- 0L
    }
    combined <- combined * (max(c(codes, 0L), na.rm = TRUE) + 2) + codes
    combined <- match(combined, unique(combined[!is.na(combined)]))
  }
  combined <- as.integer(combined)
  if (is.null(rows)) combined else combined[rows]
}

# The column keys of one grouping factor of the IR.
factor_keys <- function(run, factor) {
  keys <- named_member(run$factors, factor)
  if (is.null(keys)) {
    internal_error(sprintf("the IR has no grouping factor '%s'.", display_text(factor)))
  }
  keys
}

# The member of a named list with a name, compared in UTF-8, or NULL.
named_member <- function(x, name) {
  i <- match(name, names(x))
  if (is.na(i)) NULL else x[[i]]
}

# --- The declaration ----------------------------------------------------------------

# The declared units that do not count as absent, by name, each with its
# position in the units block.
declared_units <- function(declaration) {
  units <- declaration[["units"]]
  found <- list()
  for (i in seq_along(units)) {
    if (!declaration_inferred(declaration, path_pointer("units", i - 1L))) {
      unit <- units[[i]]
      unit$index <- i
      found[[unit[["name"]]]] <- unit
    }
  }
  found
}

# The parent of a declared unit, or NULL when the unit is not nested or its
# nesting counts as absent (registry.md, Terms).
unit_parent <- function(declaration, unit) {
  parent <- unit[["nested_in"]]
  if (is.null(parent)) {
    return(NULL)
  }
  for (member in c("nested_in", "id_scope", "membership")) {
    if (declaration_inferred(declaration, path_pointer("units", unit$index - 1L, member))) {
      return(NULL)
    }
  }
  declared_units(declaration)[[parent]]
}

# The label columns of a declared unit, as keys: its columns, preceded, while
# it is nested in its parent with id_scope 'within_parent', by the label
# columns of the parent, recursively (registry.md, Terms).
unit_label_columns <- function(declaration, name) {
  unit <- declared_units(declaration)[[name]]
  if (is.null(unit)) {
    internal_error(sprintf("no declared unit is named '%s'.", display_text(name)))
  }
  columns <- comparison_form(as.character(unlist(unit[["columns"]])))
  parent <- unit_parent(declaration, unit)
  if (!is.null(parent) && identical(unit[["id_scope"]], "within_parent")) {
    columns <- unique(c(unit_label_columns(declaration, parent[["name"]]), columns))
  }
  columns
}

# The disclosure unit (conventions.md, Declaration fields): the unit that
# disclosure_unit names, with the source 'declared', or the one declared unit
# with the role 'participant', with the source 'participant', with the code
# of the member of each row of the table, NA when a label column is missing.
disclosure_unit <- function(run) {
  declaration <- run$declaration
  units <- declared_units(declaration)
  name <- declaration[["disclosure_unit"]]
  source <- "declared"
  if (is.null(name) || declaration_inferred(declaration, "/disclosure_unit") ||
      is.null(units[[name]])) {
    participants <- names(units)[vapply(units, function(unit) {
      identical(unit[["role"]], "participant") &&
        !declaration_inferred(declaration, path_pointer("units", unit$index - 1L, "role"))
    }, NA)]
    if (length(participants) != 1L) {
      return(NULL)
    }
    name <- participants
    source <- "participant"
  }
  columns <- unit_label_columns(declaration, name)
  list(name = name, source = source, columns = columns, codes = value_codes(run, columns))
}

# --- Scope elements -------------------------------------------------------------------

# An empty JSON object, the scope of a finding for the model.
empty_object <- function() {
  structure(list(), names = character(0))
}

# The elements of a scope (registry.md, Scopes), each a named list of its
# parts, before applies_when.
scope_elements <- function(run, scope) {
  ir <- run$ir
  factors <- names(run$factors)
  pair <- function(a, b) {
    ordered <- sort(c(a, b), method = "radix")
    list(first = ordered[1L], second = ordered[2L])
  }
  pairs_of <- function(names) {
    found <- list()
    for (i in seq_along(names)) {
      for (j in seq_along(names)) {
        if (i < j) {
          found[[length(found) + 1L]] <- pair(names[i], names[j])
        }
      }
    }
    found
  }
  terms <- Filter(function(term) length(term$variables) > 0L, ir$fixed$terms)
  term_names <- vapply(terms, function(term) term$name, "")
  switch(scope,
    model = list(empty_object()),
    grouping_factor = lapply(factors, function(factor) list(factor = factor)),
    grouping_factor_or_model = if (length(factors)) {
      lapply(factors, function(factor) list(factor = factor))
    } else {
      list(empty_object())
    },
    grouping_factor_pair = pairs_of(factors),
    grouping_column_pair = grouping_column_pairs(run, pair, pairs_of),
    fixed_term = lapply(term_names, function(term) list(term = term)),
    fixed_term_by_factor = unlist(lapply(term_names, function(term) {
      lapply(factors, function(factor) list(term = term, factor = factor))
    }), recursive = FALSE) %||% list(),
    random_term = lapply(ir$random, function(term) list(term = term$name, factor = term$factor)),
    assignment = assignment_elements(run$declaration),
    column = lapply(sort_identifiers(run$table$keys), function(key) list(column = key)),
    internal_error(sprintf("the scope '%s' is not known.", scope))
  )
}

# The pairs of grouping columns, and the pair of a grouping column with the
# column of the direct parent of its unit when that column is not a grouping
# column, where the unit of a column and its parent list that column alone.
grouping_column_pairs <- function(run, pair, pairs_of) {
  columns <- run$grouping_columns
  found <- pairs_of(columns)
  units <- declared_units(run$declaration)
  single <- function(unit) {
    columns <- comparison_form(as.character(unlist(unit[["columns"]])))
    if (length(columns) == 1L) columns else NA_character_
  }
  unit_columns <- vapply(units, single, "")
  for (column in columns) {
    for (unit in units[unit_columns %in% column]) {
      parent <- unit_parent(run$declaration, unit)
      parent_column <- if (!is.null(parent)) single(parent) else NA_character_
      if (!is.na(parent_column) && !parent_column %in% columns) {
        found[[length(found) + 1L]] <- pair(column, parent_column)
      }
    }
  }
  keys <- vapply(found, function(p) paste(p$first, p$second, sep = "\001"), "")
  found[!duplicated(keys)]
}

# The entries of the assignment block that do not count as absent: an entry
# counts as absent when it, its column or its unit is inferred.
assignment_elements <- function(declaration) {
  assignment <- declaration[["assignment"]]
  found <- list()
  for (i in seq_along(assignment)) {
    entry <- path_pointer("assignment", i - 1L)
    pointers <- c(entry, paste0(entry, c("/column", "/unit")))
    if (!any(vapply(pointers, declaration_inferred, NA, declaration = declaration))) {
      found[[length(found) + 1L]] <- list(column = assignment[[i]][["column"]],
                                          unit = assignment[[i]][["unit"]])
    }
  }
  found
}

# --- What several checks compute -----------------------------------------------------

# The parameter agreement of an entry, m / 10^d, as list(m, d).
agreement_fraction <- function(entry) {
  decimal_fraction(entry[["parameters"]][["agreement"]][["value"]])
}

# The finding of a required check for the same scope element, or NULL when
# that check yields none for it.
scope_finding <- function(findings, element) {
  for (finding in findings) {
    if (identical(finding$scope[["first"]], element[["first"]]) &&
        identical(finding$scope[["second"]], element[["second"]])) {
      return(finding)
    }
  }
  NULL
}

# The columns of a random term over the rows of the design sample, read from
# the stored entries of Z: values, a matrix with one column for each column of
# the term, level, the level of each row as its position in the level order
# of ir.md (Z), and count, the number of levels.
random_term_values <- function(run, t) {
  key <- paste0("random:", t)
  cached <- run$cache[[key]]
  if (!is.null(cached)) {
    return(cached)
  }
  z <- run$z
  columns <- which(run$z_columns$term == t)
  q <- length(run$ir$random[[t]]$columns)
  n <- nrow(z)
  stored <- diff(z@p)[columns]
  entries <- seq.int(z@p[columns[1L]] + 1L, length.out = sum(stored))
  position <- rep(columns - columns[1L], stored)
  column <- position %% q + 1L
  row <- z@i[entries] + 1L
  values <- matrix(0, n, q)
  values[cbind(row, column)] <- z@x[entries]
  level <- integer(n)
  first <- column == 1L
  level[row[first]] <- as.integer(position[first] %/% q + 1L)
  found <- list(values = values, level = level, count = length(columns) %/% q)
  assign(key, found, envir = run$cache)
  found
}

# The level of each row of the design sample in a grouping factor, as its
# position in the level order of ir.md (Z), with the number of levels, from
# the first random term of the factor.
factor_levels <- function(run, factor) {
  t <- which(vapply(run$ir$random, function(term) identical(term$factor, factor), NA))[1L]
  if (is.na(t)) {
    internal_error(sprintf("the IR has no grouping factor '%s'.", display_text(factor)))
  }
  found <- random_term_values(run, t)
  list(code = found$level, count = found$count)
}

# The rows of a matrix of doubles as codes, compared by value, so that two
# rows have the same code when every value is equal (registry.md, Terms).
row_patterns <- function(values) {
  combined <- rep(1L, nrow(values))
  for (j in seq_len(ncol(values))) {
    codes <- match(values[, j], unique(values[, j]))
    paired <- pair_codes(combined, codes)
    combined <- match(paired, unique(paired))
  }
  combined
}

# Whether groups are constant in a pattern with the parameter agreement,
# pooled over the groups with at least two rows (registry.md, Terms): the
# rows whose pattern is the most frequent of their group number c, out of n
# rows in these groups, and c x 10^d >= m x n. exact is whether every group
# has one pattern. groups and patterns are positive integer codes, one for
# each row.
pooled_constancy <- function(groups, patterns, agreement) {
  sizes <- tabulate(groups)
  several <- sizes[groups] >= 2L
  groups <- groups[several]
  patterns <- patterns[several]
  paired <- pair_codes(groups, patterns)
  cell <- match(paired, unique(paired))
  counts <- tabulate(cell)
  owner <- groups[match(seq_along(counts), cell)]
  ordered <- order(owner, -counts, method = "radix")
  largest <- counts[ordered][!duplicated(owner[ordered])]
  n <- length(groups)
  list(constant = sum(largest) * 10^agreement$d >= agreement$m * n,
       exact = length(counts) == length(largest))
}

# For each level of a grouping factor among those given, whether the rank by
# the sequential rule of some columns restricted to the level's rows, after
# the level's first row is subtracted from every row when difference is
# TRUE, equals the number of columns. The sequential rule keeps a single
# column exactly when it is not 0 in every row, and q columns need at least
# q rows, so the rule itself is applied only to levels with two or more
# columns and at least as many rows.
levels_of_full_rank <- function(values, level, count, among = rep(TRUE, count),
                                difference = FALSE) {
  q <- ncol(values)
  if (difference) {
    first <- match(seq_len(count), level)
    values <- values - values[first[level], , drop = FALSE]
  }
  if (q == 1L) {
    return(among & tabulate(level[values[, 1L] != 0], nbins = count) > 0L)
  }
  sizes <- tabulate(level, nbins = count)
  full <- logical(count)
  candidates <- which(among & sizes >= q)
  if (length(candidates)) {
    rows <- split(seq_along(level), factor(level, levels = seq_len(count)))
    for (l in candidates) {
      full[l] <- sum(sequential_rule(values[rows[[l]], , drop = FALSE])) == q
    }
  }
  full
}

# X_d of assignment.design_df and identifiability.df_budget: the columns of
# x with the first row of each level, in table order, subtracted from every
# row of the level, and a column set to 0 when its largest absolute value is
# at most the tolerance of the sequential rule times that of the same column
# of x, so that a column constant within the levels up to rounding adds
# nothing to the rank of X_d, as the indicator columns of the levels would
# absorb it.
level_differences <- function(x, level, count) {
  first <- match(seq_len(count), level)
  differences <- x - x[first[level], , drop = FALSE]
  for (j in seq_len(if (nrow(x)) ncol(x) else 0L)) {
    if (max(abs(differences[, j])) <= sequential_tolerance * max(abs(x[, j]))) {
      differences[, j] <- 0
    }
  }
  differences
}

# --- Running the checks ---------------------------------------------------------------

# The function of a check, or NULL for an identifier without one.
check_implementation <- function(id) {
  get0(paste0("audit_check_", chartr(".", "_", id)), envir = environment(check_implementation),
       mode = "function", inherits = FALSE)
}

# The checks that a run of a tier runs, in ascending order of identifier
# after the checks they require (03-execution-plan.md, M2, step 10).
check_order <- function(entries, tier) {
  ids <- names(entries)[vapply(entries, function(entry) {
    match(entry[["tier"]], tier_names) <= match(tier, tier_names)
  }, NA)]
  ids <- ids[order(ids, method = "radix")]
  ordered <- character(0)
  while (length(ids)) {
    ready <- vapply(ids, function(id) {
      required <- unlist(entries[[id]][["links"]][["requires"]])
      all(required[required %in% ids] %in% ordered)
    }, NA)
    if (!any(ready)) {
      internal_error("the links of the registry form a cycle.")
    }
    ordered <- c(ordered, ids[which(ready)[1L]])
    ids <- ids[-which(ready)[1L]]
  }
  ordered
}

# Step 10: each check whose tier the run reached, with the time at which the
# checks of each tier started. Returns the internal findings and the times.
run_checks <- function(run) {
  entries <- registry_entries_by_id()
  started <- list()
  findings <- list()
  for (id in check_order(entries, run$tier)) {
    entry <- entries[[id]]
    if (is.null(started[[entry[["tier"]]]])) {
      started[[entry[["tier"]]]] <- run_time()
    }
    found <- run_check(run, entry)
    run$results[[id]] <- found
    findings <- c(findings, found)
  }
  # The time of a tier none of whose checks ran is the time at which the
  # checks ended, and no tier starts before the tier below it.
  times <- list()
  previous <- -Inf
  for (tier in tier_names[seq_len(match(run$tier, tier_names))]) {
    time <- max(started[[tier]] %||% run_time(), previous)
    times[[tier]] <- utc_timestamp(time)
    previous <- time
  }
  list(findings = findings, times = times)
}

# One check: the family filter, the availability rules package_missing, the
# function of the check and the findings of the elements for which
# applies_when holds. Every entry of the registry has a function, so an
# entry without one is an internal error.
run_check <- function(run, entry) {
  families <- unlist(entry[["families"]])
  if (length(families) && !run$family_class %in% families) {
    return(list())
  }
  implementation <- check_implementation(entry[["id"]])
  if (is.null(implementation)) {
    internal_error(sprintf("the check %s has no function.", entry[["id"]]))
  }
  for (rule in entry[["availability"]]) {
    if (!identical(rule[["reason"]], "package_missing")) {
      break
    }
    for (package in unlist(rule[["packages"]][["R"]])) {
      if (!package_installed(package)) {
        return(list(unavailable_finding(run, entry, "package_missing", package)))
      }
    }
  }
  elements <- scope_elements(run, entry[["scope"]])
  result <- implementation(run, entry, elements)
  if (inherits(result, "mixedcheck_check_unavailable")) {
    return(list(unavailable_finding(run, entry, result$reason, result$detail)))
  }
  if (!is.list(result) || length(result) != length(elements)) {
    internal_error(sprintf("%s returned no result for some scope element.", entry[["id"]]))
  }
  findings <- list()
  for (i in seq_along(elements)) {
    if (!is.null(result[[i]])) {
      findings[[length(findings) + 1L]] <- assemble_finding(run, entry, elements[[i]], result[[i]])
    }
  }
  findings
}

# The finding of a check that is not available as a whole, with the detail
# of its availability rule (registry.md, Availability): the declaration
# field, with {outcome} standing for the escaped name of the response, the
# package or the parameter that holds the limit.
unavailable_finding <- function(run, entry, reason, detail = NULL) {
  rules <- Filter(function(rule) {
    identical(rule[["reason"]], reason) &&
      (reason != "too_large" || is.null(detail) || identical(rule[["parameter"]], detail))
  }, entry[["availability"]])
  if (!length(rules)) {
    internal_error(sprintf("%s has no availability rule '%s'.", entry[["id"]], reason))
  }
  rule <- rules[[1L]]
  if (reason == "declaration_missing") {
    outcome <- gsub("/", "~1", gsub("~", "~0", run$ir$response$variable %||% "", fixed = TRUE),
                    fixed = TRUE)
    detail <- gsub("{outcome}", outcome, rule[["pointer"]], fixed = TRUE)
  } else if (reason == "too_large") {
    detail <- rule[["parameter"]]
  }
  availability <- list(value = "not_available", reason = reason)
  if (!is.null(detail)) {
    availability$detail <- detail
  }
  list(check = entry[["id"]], check_version = entry[["version"]], tier = entry[["tier"]],
       scope = empty_object(), available = FALSE, availability = availability)
}

# --- Assembling a finding ---------------------------------------------------------------

# Checks that a value has the form of its kind.
statistic_value_valid <- function(value, kind) {
  switch(kind,
    count = is.numeric(value) && length(value) == 1L && is.finite(value) && value >= 0 &&
      value == floor(value),
    real = is.double(value) && length(value) == 1L,
    reals = is.double(value),
    category = is_string(value),
    boolean = is_flag(value),
    names = , labels = is.character(value) && !anyNA(value),
    FALSE
  )
}

# The finding of one scope element from what the check returned: its
# statistics, with the ratios computed from their counts, its status fields,
# its message and its support. The count classes of by_unit statistics are
# resolved in step 11 from the items kept with the finding.
assemble_finding <- function(run, entry, scope, element) {
  if (!inherits(element, "mixedcheck_check_element")) {
    internal_error(sprintf("%s returned a result that is not check_element().", entry[["id"]]))
  }
  defined <- entry[["statistics"]]
  values <- element$statistics
  unknown <- setdiff(names(values), names(defined))
  if (length(unknown)) {
    internal_error(sprintf("%s has no statistic '%s'.", entry[["id"]], unknown[1L]))
  }
  for (name in names(values)) {
    kind <- defined[[name]][["kind"]]
    if (kind == "ratio" || !statistic_value_valid(values[[name]], kind)) {
      internal_error(sprintf("the statistic '%s' of %s is not a valid %s.", name, entry[["id"]],
                             kind))
    }
  }
  for (name in names(defined)) {
    statistic <- defined[[name]]
    if (statistic[["kind"]] == "ratio") {
      a <- values[[statistic[["numerator"]]]]
      b <- values[[statistic[["denominator"]]]]
      if (!is.null(a) && !is.null(b) && b > 0) {
        values[[name]] <- a / b
      }
    }
  }
  values <- values[intersect(names(defined), names(values))]
  rules <- entry[["decision"]][["rules"]]
  if (length(element$rules) != length(rules) || anyNA(element$rules)) {
    internal_error(sprintf("%s gave no condition for some rule of its decision.", entry[["id"]]))
  }
  chosen <- which(element$rules)[1L]
  decided <- if (is.na(chosen)) entry[["decision"]][["otherwise"]] else rules[[chosen]]
  status <- list(
    assessability = finding_assessability(entry, element),
    finding = list(value = decided[["finding"]]),
    threshold_proximity = list(
      value = if (finding_near_threshold(entry, values, element)) "near_threshold" else "clear"
    ),
    validation = list(value = finding_validation(entry))
  )
  if (isTRUE(entry[["fitted_model"]])) {
    internal_error("checks of fitted models arrive with Stream A.")
  }
  message_id <- decided[["message"]]
  statistics <- lapply(names(values), function(name) {
    statistic <- defined[[name]]
    found <- list(kind = statistic[["kind"]], value = values[[name]])
    if (statistic[["kind"]] %in% c("count", "ratio")) {
      found$count_class <- statistic[["count_class"]]
    }
    if (!is.null(statistic[["quantile"]])) {
      found$quantile <- statistic[["quantile"]]
    }
    found
  })
  names(statistics) <- names(values)
  for (name in names(values)) {
    if (defined[[name]][["kind"]] == "labels" && !is_string(element$label_factors[[name]])) {
      internal_error(sprintf("%s gave no factor for the labels of '%s'.", entry[["id"]], name))
    }
  }
  list(
    check = entry[["id"]], check_version = entry[["version"]], tier = entry[["tier"]],
    scope = scope, available = TRUE, status = status,
    message = list(id = message_id,
                   text = render_message(entry, message_id, scope, values)),
    statistics = statistics,
    values = values,
    support = sample_support(run, entry[["sample"]]),
    items = finding_items(run, entry, scope, element, values),
    rows = element$rows %||% sample_rows(run, entry[["sample"]]),
    entry = entry,
    rule = chosen,
    label_factors = element$label_factors
  )
}

# The assessability status: the first rule whose condition holds, or
# adequate.
finding_assessability <- function(entry, element) {
  rules <- entry[["assessability"]]
  if (length(element$assessability) != length(rules) || anyNA(element$assessability)) {
    internal_error(sprintf("%s gave no condition for some assessability rule.", entry[["id"]]))
  }
  chosen <- which(element$assessability)[1L]
  if (is.na(chosen)) {
    return(list(value = "adequate"))
  }
  rule <- rules[[chosen]]
  status <- list(value = rule[["value"]])
  if (!is.null(rule[["reason"]])) {
    status$reason <- rule[["reason"]]
  }
  if (identical(rule[["reason"]], "prerequisite_unmet")) {
    status$detail <- rule[["prerequisite"]]
  }
  status
}

# The validation status: descriptive when the decision names no threshold
# or a descriptive one (registry.md, Thresholds). Validated thresholds need
# the validation studies that later registries add.
finding_validation <- function(entry) {
  named <- decision_thresholds(entry)
  values <- vapply(named, function(name) {
    entry[["thresholds"]][[name]][["validation"]][["value"]]
  }, "")
  if (!length(values) || any(values == "descriptive")) {
    return("descriptive")
  }
  internal_error("validated thresholds arrive with the validation studies.")
}

# The thresholds that the rules of a decision name.
decision_thresholds <- function(entry) {
  unique(unlist(lapply(entry[["decision"]][["rules"]], function(rule) unlist(rule[["thresholds"]]))))
}

# Whether the finding is near_threshold: a real statistic within the
# proximity band of a threshold that a rule of the decision names, a value
# compared with a parameter that has a proximity factor within its band, or
# the check's own flag (registry.md, Thresholds and Parameters).
finding_near_threshold <- function(entry, values, element) {
  if (isTRUE(element$near_threshold)) {
    return(TRUE)
  }
  for (name in decision_thresholds(entry)) {
    threshold <- entry[["thresholds"]][[name]]
    s <- values[[threshold[["statistic"]]]]
    band <- threshold[["proximity"]]
    if (is.null(band) || is.null(s)) {
      next
    }
    t <- json_number_values(threshold[["value"]])
    width <- json_number_values(band[["absolute"]]) +
      json_number_values(band[["relative"]]) * abs(t)
    if (isTRUE(abs(s - t) <= width)) {
      return(TRUE)
    }
  }
  for (name in names(element$proximity)) {
    factor <- entry[["parameters"]][[name]][["proximity_factor"]]
    if (is.null(factor)) {
      internal_error(sprintf("the parameter '%s' of %s has no proximity factor.", name,
                             entry[["id"]]))
    }
    t <- json_number_values(entry[["parameters"]][[name]][["value"]])
    f <- json_number_values(factor)
    s <- abs(element$proximity[[name]])
    if (any(s >= t / f & s <= t * f, na.rm = TRUE)) {
      return(TRUE)
    }
  }
  FALSE
}

# Whether a threshold's comparison holds for the statistic it applies to:
# a count in integer arithmetic, a ratio a/b with the value m/10^d by
# comparing a x 10^d with m x b, and a real with the double nearest to the
# value (registry.md, Thresholds). An absent statistic does not satisfy it.
threshold_holds <- function(entry, name, values) {
  threshold <- entry[["thresholds"]][[name]]
  if (is.null(threshold)) {
    internal_error(sprintf("%s has no threshold '%s'.", entry[["id"]], name))
  }
  statistic <- entry[["statistics"]][[threshold[["statistic"]]]]
  value <- values[[threshold[["statistic"]]]]
  if (is.null(value)) {
    return(FALSE)
  }
  if (statistic[["kind"]] == "ratio") {
    parts <- decimal_fraction(threshold[["value"]])
    left <- values[[statistic[["numerator"]]]] * 10^parts$d
    right <- parts$m * values[[statistic[["denominator"]]]]
  } else {
    left <- value
    right <- json_number_values(threshold[["value"]])
  }
  isTRUE(switch(threshold[["comparator"]],
    "<" = left < right,
    "<=" = left <= right,
    ">" = left > right,
    ">=" = left >= right
  ))
}

# A non-negative decimal string as m / 10^d with integers m and d.
decimal_fraction <- function(text) {
  fraction <- if (grepl(".", text, fixed = TRUE)) sub("^[^.]*\\.", "", text) else ""
  list(m = as.numeric(paste0(sub("\\..*$", "", text), fraction)), d = nchar(fraction))
}

# --- Support ------------------------------------------------------------------------------

# The support of the findings of a sample (documents.md, Support): its rows,
# the basis of its contributors, the number of distinct contributors, whether
# the dominance rule fails and, for the privacy filter, the summed rows of
# the largest contributors, by grouping factor for the basis
# grouping_factors. Computed once for each sample.
sample_support <- function(run, sample) {
  cached <- run$cache[[paste0("support:", sample)]]
  if (!is.null(cached)) {
    return(cached)
  }
  support <- rows_support(run, sample_rows(run, sample))
  assign(paste0("support:", sample), support, envir = run$cache)
  support
}

# The support of some rows of the table, as sample_support() gives it for
# the rows of a sample.
rows_support <- function(run, rows) {
  n <- length(rows)
  dominance <- read_registry()[["privacy"]][["dominance"]]
  share <- decimal_fraction(dominance[["share"]])
  contributors <- function(codes) {
    counts <- tabulate(codes[!is.na(codes)])
    counts <- counts[counts > 0L]
    largest <- sum(largest_counts(counts, dominance[["contributors"]]))
    list(distinct = length(counts), largest = largest,
         dominated = n > 0L && largest * 10^share$d >= share$m * n)
  }
  if (!is.null(run$disclosure)) {
    found <- contributors(run$disclosure$codes[rows])
    return(list(rows = n, basis = "disclosure_unit", distinct = found$distinct,
                dominated = found$dominated, largest = found$largest))
  }
  if (length(run$factors)) {
    found <- lapply(run$factors, function(keys) contributors(value_codes(run, keys, rows)))
    largest <- vapply(found, function(f) f$largest, 0)
    names(largest) <- names(run$factors)
    return(list(rows = n, basis = "grouping_factors",
                distinct = min(vapply(found, function(f) f$distinct, 0)),
                dominated = any(vapply(found, function(f) f$dominated, NA)),
                largest = largest))
  }
  found <- contributors(seq_len(n))
  list(rows = n, basis = "rows", distinct = n, dominated = found$dominated,
       largest = found$largest)
}

# The k largest of some counts.
largest_counts <- function(counts, k) {
  sorted <- sort(counts, decreasing = TRUE)
  sorted[seq_len(min(k, length(sorted)))]
}

# --- Count classes ------------------------------------------------------------------------

# The items of the by_unit statistics of a finding, by statistic, as the
# level codes of each row of the table: one item, or two for combinations,
# or NULL for an item that the finding lacks, such as the factor of a
# finding for the model as a whole.
finding_items <- function(run, entry, scope, element, values) {
  items <- list()
  for (name in names(values)) {
    statistic <- entry[["statistics"]][[name]]
    if (!identical(statistic[["count_class"]], "by_unit") || is.null(statistic[["resolved_by"]])) {
      next
    }
    items[[name]] <- lapply(statistic[["resolved_by"]], function(reference) {
      item_codes(run, reference, entry[["scope"]], scope, element, values)
    })
  }
  items
}

# The level codes of one item of resolved_by. The parts first and second
# name grouping factors in the scope grouping_factor_pair and columns in the
# scope grouping_column_pair.
item_codes <- function(run, reference, kind, scope, element, values) {
  name <- reference[["name"]]
  if (identical(reference[["source"]], "scope")) {
    value <- scope[[name]]
    if (is.null(value)) {
      return(NULL)
    }
    keys <- switch(name,
      column = comparison_form(value),
      first = , second = if (identical(kind, "grouping_factor_pair")) factor_keys(run, value) else
        comparison_form(value),
      factor = factor_keys(run, value),
      unit = unit_label_columns(run$declaration, value),
      internal_error(sprintf("the scope part '%s' is not an item.", name))
    )
    return(value_codes(run, keys))
  }
  given <- element$items[[name]]
  if (is.character(given)) {
    return(value_codes(run, given))
  }
  if (!is.null(given)) {
    return(as.integer(given))
  }
  held <- values[[name]]
  if (length(held) != 1L) {
    internal_error(sprintf("the item of '%s' must be given with the statistic.", name))
  }
  if (held %in% names(run$factors)) {
    return(value_codes(run, factor_keys(run, held)))
  }
  if (comparison_form(held) %in% run$table$keys) {
    return(value_codes(run, comparison_form(held)))
  }
  if (!is.null(declared_units(run$declaration)[[held]])) {
    return(value_codes(run, unit_label_columns(run$declaration, held)))
  }
  internal_error(sprintf("'%s' is neither a grouping factor, a column nor a unit.",
                         display_text(held)))
}

# The class to which a by_unit count resolves over the rows of its finding
# (registry.md, Statistics and counts): person without a disclosure unit or
# when some level of its item, or some combination of the levels of its two
# items that occurs in a row, has at most one member of the disclosure unit,
# and non_person otherwise.
resolve_count_class <- function(run, items, rows) {
  if (is.null(run$disclosure) || !length(items) || any(vapply(items, is.null, NA))) {
    return("person")
  }
  level <- items[[1L]][rows]
  if (length(items) == 2L) {
    level <- pair_codes(level, items[[2L]][rows])
  }
  member <- run$disclosure$codes[rows]
  present <- !is.na(level)
  level <- match(level[present], unique(level[present]))
  member <- member[present]
  known <- !is.na(member)
  level_known <- level[known]
  pairs <- !duplicated(pair_codes(level_known, member[known]))
  members <- tabulate(level_known[pairs], nbins = max(c(level, 0L)))
  if (any(members <= 1L)) "person" else "non_person"
}

# One code for each pair of positive integer codes, exact in doubles while
# the product of their largest values stays below 2^53, and NA for a pair
# with a missing code.
pair_codes <- function(first, second) {
  first * (max(c(second, 0), na.rm = TRUE) + 1) + second
}

# Step 11: the count class of each by_unit statistic of a finding, resolved
# for the finding. A ratio takes the class of its numerator, which counts the
# levels of the same item as its denominator.
resolve_finding_classes <- function(run, finding) {
  if (!isTRUE(finding$available)) {
    return(finding)
  }
  for (name in names(finding$statistics)) {
    if (!identical(finding$statistics[[name]]$count_class, "by_unit")) {
      next
    }
    source <- name
    if (finding$statistics[[name]]$kind == "ratio") {
      source <- finding$entry[["statistics"]][[name]][["numerator"]]
    }
    finding$statistics[[name]]$count_class <-
      resolve_count_class(run, finding$items[[source]], finding$rows)
  }
  finding
}

# --- Order and document form ----------------------------------------------------------------

# Step 11: the findings in the order of documents.md (Findings): by check and
# then by the list of the names and NFC values of their scope parts, in
# ascending order of part name, compared code point by code point with a
# prefix first. U+0001, which no identifier holds, separates the strings, so
# that the radix method compares the lists by their bytes.
order_findings <- function(findings) {
  if (!length(findings)) {
    return(findings)
  }
  keys <- vapply(findings, function(finding) {
    paste(finding_order_key(finding), collapse = "\001")
  }, "")
  findings[order(keys, method = "radix")]
}

# A finding in the form that a results document writes it (documents.md,
# Findings and Statistics). An internal document writes every value. A
# shareable document writes the marks of the privacy filter (privacy.R): a
# suppressed value as null with its availability, a finding suppressed as a
# whole as not available, and the n of a quantile only when the count that
# gives n is written.
document_finding <- function(finding) {
  scope <- finding$scope
  if (!length(scope)) {
    scope <- empty_object()
  }
  found <- list(check = finding$check, check_version = finding$check_version,
                tier = finding$tier, scope = scope)
  if (!isTRUE(finding$available)) {
    found$status <- list(availability = finding$availability)
    return(found)
  }
  if (isTRUE(finding$whole)) {
    found$status <- list(availability = suppressed_availability("decision"))
    return(found)
  }
  found$status <- c(list(availability = list(value = "available")), finding$status)
  found$message <- finding$message
  suppressed <- finding$suppressed %||% character(0)
  statistics <- lapply(names(finding$statistics), function(name) {
    statistic <- finding$statistics[[name]]
    written <- if (name %in% names(suppressed)) {
      list(kind = statistic$kind, value = NULL,
           availability = suppressed_availability(suppressed[[name]]))
    } else {
      list(kind = statistic$kind, value = document_value(finding$values[[name]], statistic$kind))
    }
    if (!is.null(statistic$count_class)) {
      written$count_class <- statistic$count_class
    }
    if (!is.null(statistic$quantile)) {
      written$quantile <- list(p = json_number_values(statistic$quantile[["p"]]))
      n <- statistic$quantile[["n"]]
      if (!is.null(finding$values[[n]]) && !n %in% names(suppressed)) {
        written$quantile$n <- finding$values[[n]]
      }
    }
    written
  })
  names(statistics) <- names(finding$statistics)
  found$statistics <- if (length(statistics)) statistics else empty_object()
  support <- finding$support
  hidden <- finding$support_suppressed %||% character(0)
  reported <- function(member) {
    if (member %in% names(hidden)) {
      list(value = NULL, availability = suppressed_availability(hidden[[member]]))
    } else {
      list(value = support[[member]])
    }
  }
  found$support <- list(
    rows = reported("rows"),
    contributors = list(basis = support$basis, distinct = reported("distinct"),
                        dominated = support$dominated)
  )
  found
}

# The availability of a value or a finding that the privacy filter
# suppressed, with the detail of the rule that suppressed it.
suppressed_availability <- function(detail) {
  list(value = "not_available", reason = "privacy_suppressed", detail = detail)
}

# A value of a statistic as a document writes it: lists of names, labels and
# reals as arrays, and non-finite reals as the strings that the data profile
# writes.
document_value <- function(value, kind) {
  if (kind %in% c("names", "labels", "reals")) {
    return(as.list(unname(value)))
  }
  value
}
