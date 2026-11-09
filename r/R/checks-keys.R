# The check of the prefix keys (spec/registry/checks/keys.duplicates.yaml).

# keys.duplicates: the rows of the table that share a value of the declared
# observation key, whether they differ in a compared column, and the rows
# with a missing key value. Key values and compared columns are compared by
# value, and missing values of a compared column equal each other.
audit_check_keys_duplicates <- function(run, entry, elements) {
  declaration <- run$declaration
  key <- observation_key_columns(declaration)
  if (!length(key)) {
    return(check_unavailable("declaration_missing"))
  }
  rows <- run$table$rows
  codes <- value_codes(run, comparison_form(as.character(key)))
  complete <- !is.na(codes)
  counts <- tabulate(codes[complete], nbins = max(c(codes, 0L), na.rm = TRUE))
  duplicated_codes <- which(counts >= 2L)
  shared <- complete & codes %in% duplicated_codes
  patterns <- value_codes(run, compared_key_columns(run), missing_level = TRUE)
  conflicting <- if (length(duplicated_codes)) {
    first <- !duplicated(pair_codes(codes[shared], patterns[shared]))
    sum(tabulate(codes[shared][first], nbins = length(counts))[duplicated_codes] > 1L)
  } else {
    0
  }
  missing <- rows - sum(complete)
  identical_keys <- length(duplicated_codes) - conflicting
  statistics <- list(
    key_columns = as.character(key),
    rows = rows,
    missing_key_rows = missing,
    duplicated_keys = length(duplicated_codes),
    conflicting_keys = conflicting,
    identical_keys = identical_keys,
    duplicate_rows = sum(shared)
  )
  list(check_element(statistics, rules = c(conflicting > 0, identical_keys > 0, missing > 0)))
}

# The columns that keys.duplicates compares: those that the IR reads and
# those that the declaration gives a role, other than the response, its
# trials column and the columns that the declaration gives the role outcome
# or outcome_derived, as keys in code-point order.
compared_key_columns <- function(run) {
  ir <- run$ir
  declaration <- run$declaration
  variables <- declaration[["variables"]]
  named <- as.character(names(variables))
  roles <- named[vapply(seq_along(named), function(i) {
    !is.null(variables[[i]][["role"]]) &&
      !declaration_inferred(declaration, json_pointer(c("variables", named[i], "role")))
  }, NA)]
  read <- c(
    names(ir$predictors),
    run$grouping_columns,
    vapply(ir$offsets, function(o) o$variable, ""),
    ir$weights$variable,
    comparison_form(roles)
  )
  excluded <- c(ir$response$variable, ir$response$trials,
                declared_role_columns(declaration, c("outcome", "outcome_derived")))
  sort_identifiers(setdiff(unique(read), excluded))
}
