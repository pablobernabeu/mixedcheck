# The declaration validator (docs/spec/declarations.md, Validation). It works
# in five stages, reading, version, structure, names and references, and
# meaning, and stops after the first stage that reports an issue.

#' Validate a design declaration
#'
#' Reads a declaration of declaration vocabulary 0.1 and checks it in five
#' stages, stopping after the first stage that finds a problem: reading, the
#' vocabulary version, the structure against the declaration schema, names
#' and references, and the rules on meaning, including those of the minimal
#' declaration. A file whose name ends in '.yaml' or '.yml' is read as YAML,
#' with every scalar read as a string and converted to the type that the
#' schema requires at its position, which needs the package yaml. Any other
#' file is read as JSON with the strict reader in the hashable profile, and a
#' value in memory, such as a list written by hand, must pass the writer's
#' checks of the hashable profile.
#'
#' The declaration hash is the hash of the canonical bytes of the value
#' returned, so a YAML file and the JSON file it converts to have the same
#' hash. The value returned holds strings marked UTF-8, which
#' [canonical_hash()] accepts in every locale, whereas an unmarked string
#' outside ASCII in the value passed in is marked only in a UTF-8 session.
#'
#' @param declaration The path of a file, as a character string, or the
#'   declaration as a named list.
#' @param minimal Whether the declaration must be a minimal declaration, as
#'   the outcome-blind and preregistration exports require. A confirmatory
#'   goal and the features cluster_randomised, stepped_wedge and
#'   partially_nested require one whatever this argument says.
#' @return The declaration, invisibly: objects as named lists, arrays as
#'   unnamed lists, strings marked UTF-8, numbers as doubles and booleans as
#'   logical values, as [read_json_strict()] returns them.
#' @section Errors: A declaration that is not valid gives an error of class
#'   `mixedcheck_error`, whose element `issues` lists the problems found, each
#'   with the `code` of the shared error catalogue and the rendered `message`.
#'   Reading reports one problem, located by the byte `offset` in the file or
#'   by the JSON Pointer of the converted YAML value as `pointer`. The later
#'   stages report every problem they find, located by JSON Pointer as
#'   `pointer`, sorted by pointer, code and message and capped at 100.
#' @export
#' @examples
#' declaration <- list(
#'   vocabulary = "0.1.0",
#'   units = list(list(name = "subject", columns = list("Subject"), role = "participant")),
#'   variables = list(Reaction = list(role = "outcome", measurement = "positive_duration"))
#' )
#' value <- validate_declaration(declaration)
#' canonical_hash(value, "hashable")
#'
#' # A unit nested in a unit that is not declared.
#' declaration$units[[1]]$nested_in <- "school"
#' declaration$units[[1]]$id_scope <- "within_parent"
#' problem <- tryCatch(validate_declaration(declaration), mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
#'
#' path <- tempfile(fileext = ".json")
#' writeBin(charToRaw('{"vocabulary": "0.1.0", "goal": "confirmatory"}'), path)
#' problem <- tryCatch(validate_declaration(path), mixedcheck_error = function(e) e)
#' vapply(problem$issues, function(issue) issue$code, "")
#' unlink(path)
validate_declaration <- function(declaration, minimal = FALSE) {
  if (!is.logical(minimal) || length(minimal) != 1L || is.na(minimal)) {
    stop("'minimal' must be TRUE or FALSE.", call. = FALSE)
  }
  value <- read_declaration_input(declaration)
  issues <- declaration_issues(value, minimal)
  if (length(issues)) {
    signal_issues(issues)
  }
  invisible(value)
}

# Stage 1: the declaration as read from a YAML or JSON file, or a value in
# memory after the input boundary and the writer's checks of the hashable
# profile, as the strict reader returns it.
read_declaration_input <- function(declaration) {
  if (is.character(declaration)) {
    if (length(declaration) != 1L || is.na(declaration)) {
      stop("'declaration' must be a file path or a named list.", call. = FALSE)
    }
    if (is_yaml_path(declaration)) {
      return(read_yaml_declaration(declaration))
    }
    return(read_json_strict(declaration, "hashable"))
  }
  parse_json_bytes(canonical_bytes(mark_input_strings(declaration), "hashable"), "hashable")
}

# Whether a file name ends in '.yaml' or '.yml', compared in ASCII lower case.
is_yaml_path <- function(path) {
  lower <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", path)
  grepl("\\.ya?ml$", lower, useBytes = TRUE)
}

# The supported line of the vocabulary and the form of its versions.
vocabulary_pattern <- "^0\\.1\\.(0|[1-9][0-9]*)\\z"

# Whether a version string lies in a supported line: it matches the pattern of
# the line and has at most 32 characters.
version_supported <- function(version, pattern) {
  is.character(version) && length(version) == 1L && codepoint_length(version) <= 32L &&
    grepl(paste0("(*UTF)", pattern), version, perl = TRUE)
}

# Stages 2 to 5 on a value read in stage 1. Returns the issues of the first
# stage that finds any, rendered, sorted and capped.
declaration_issues <- function(value, minimal = FALSE) {
  version <- if (is_json_object(value)) value[["vocabulary"]]
  if (is.character(version) && !version_supported(version, vocabulary_pattern)) {
    return(list(new_issue("E1441", list(version = version, supported = "0.1.x"),
                          pointer = "/vocabulary")))
  }
  for (stage in list(
    function(d) schema_issues(d, "urn:mixedcheck:schema:declaration"),
    declaration_reference_issues,
    function(d) declaration_meaning_issues(d, minimal)
  )) {
    raw <- stage(value)
    if (length(raw)) {
      return(finish_issues(raw))
    }
  }
  list()
}

# Helpers for the rules in code, which run on a structurally valid
# declaration, so each member has the type the schema gives it.
declaration_strings <- function(x, member) {
  vapply(x, function(entry) entry[[member]] %||% NA_character_, "")
}

# The pointer of a path of tokens, numbers being array indices from 0.
path_pointer <- function(...) {
  json_pointer(as.character(c(...)))
}

# Stage 4: names and references (E2001 to E2009).
declaration_reference_issues <- function(d) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  units <- d[["units"]]
  unit_names <- declaration_strings(units, "name")
  fields <- d[["table"]][["fields"]]
  field_names <- declaration_strings(fields, "name")
  has_table <- !is.null(d[["table"]])
  estimands <- d[["estimands"]]
  assignment <- d[["assignment"]]
  crossings <- d[["crossings"]]
  variables <- d[["variables"]]

  repeated <- function(values, block, member) {
    for (i in which(duplicated(values))) {
      add(switch(block, units = "E2001", fields = "E2002", estimands = "E2003",
                 assignment = "E2004"),
          if (block == "fields") path_pointer("table", "fields", i - 1L, member)
          else path_pointer(block, i - 1L, member),
          list(name = values[i]))
    }
  }
  repeated(unit_names, "units", "name")
  repeated(field_names, "fields", "name")
  repeated(declaration_strings(estimands, "id"), "estimands", "id")
  repeated(declaration_strings(assignment, "column"), "assignment", "column")

  pairs <- vapply(crossings, function(crossing) {
    paste(sort(unlist(crossing[["units"]]), method = "radix"), collapse = " ")
  }, "")
  for (i in which(duplicated(pairs))) {
    add("E2005", path_pointer("crossings", i - 1L, "units"))
  }

  unit_reference <- function(name, ...) {
    if (!is.null(name) && !name %in% unit_names) {
      add("E2006", path_pointer(...), list(name = name))
    }
  }
  column_reference <- function(name, ...) {
    if (has_table && !is.null(name) && !name %in% field_names) {
      add("E2007", path_pointer(...), list(name = name))
    }
  }
  for (i in seq_along(units)) {
    unit_reference(units[[i]][["nested_in"]], "units", i - 1L, "nested_in")
    for (j in seq_along(units[[i]][["columns"]])) {
      column_reference(units[[i]][["columns"]][[j]], "units", i - 1L, "columns", j - 1L)
    }
  }
  for (i in seq_along(crossings)) {
    for (j in seq_along(crossings[[i]][["units"]])) {
      unit_reference(crossings[[i]][["units"]][[j]], "crossings", i - 1L, "units", j - 1L)
    }
    column_reference(crossings[[i]][["list"]], "crossings", i - 1L, "list")
  }
  observation <- d[["observation"]]
  unit_reference(observation[["unit"]], "observation", "unit")
  unit_reference(observation[["time"]][["within"]], "observation", "time", "within")
  for (j in seq_along(observation[["key"]])) {
    column_reference(observation[["key"]][[j]], "observation", "key", j - 1L)
  }
  column_reference(observation[["time"]][["column"]], "observation", "time", "column")
  for (i in seq_along(assignment)) {
    unit_reference(assignment[[i]][["unit"]], "assignment", i - 1L, "unit")
    for (j in seq_along(assignment[[i]][["blocks"]])) {
      unit_reference(assignment[[i]][["blocks"]][[j]], "assignment", i - 1L, "blocks", j - 1L)
    }
    column_reference(assignment[[i]][["column"]], "assignment", i - 1L, "column")
  }
  unit_reference(d[["disclosure_unit"]], "disclosure_unit")
  # Column names are looked up by position or with match(), since `[[`
  # translates a name to the native encoding (named_member()).
  for (k in seq_along(variables)) {
    column <- names(variables)[k]
    entry <- variables[[k]]
    column_reference(column, "variables", column)
    for (j in seq_along(entry[["derived_from"]])) {
      column_reference(entry[["derived_from"]][[j]], "variables", column, "derived_from", j - 1L)
    }
    column_reference(entry[["trials"]], "variables", column, "trials")
    column_reference(entry[["exposure"]][["column"]], "variables", column, "exposure", "column")
  }
  for (i in seq_along(estimands)) {
    estimand <- estimands[[i]]
    column_reference(estimand[["outcome"]], "estimands", i - 1L, "outcome")
    variables_of_term <- term_variables(estimand[["term"]])
    for (name in unique(variables_of_term)) {
      column_reference(name, "estimands", i - 1L, "term")
    }
    for (name in unique(variables_of_term[duplicated(variables_of_term)])) {
      add("E2008", path_pointer("estimands", i - 1L, "term"), list(name = name))
    }
  }
  table <- d[["table"]]
  for (j in seq_along(table[["primaryKey"]])) {
    column_reference(table[["primaryKey"]][[j]], "table", "primaryKey", j - 1L)
  }
  for (i in seq_along(table[["uniqueKeys"]])) {
    for (j in seq_along(table[["uniqueKeys"]][[i]])) {
      column_reference(table[["uniqueKeys"]][[i]][[j]], "table", "uniqueKeys", i - 1L, j - 1L)
    }
  }

  inferred <- d[["provenance"]][["inferred"]]
  for (j in seq_along(inferred)) {
    pointer <- inferred[[j]]
    excluded <- pointer %in% c("", "/vocabulary", "/provenance") ||
      startsWith(pointer, "/provenance/")
    if (excluded || !pointer_resolves(d, pointer)) {
      add("E2009", path_pointer("provenance", "inferred", j - 1L), list(pointer = pointer))
    }
  }
  issues
}

# Whether RFC 6901 evaluation of a pointer finds a value, an array index token
# being '0' or a decimal number without leading zeros below the array's
# length.
pointer_resolves <- function(x, pointer) {
  if (identical(pointer, "")) {
    return(TRUE)
  }
  tokens <- strsplit(substring(pointer, 2L), "/", fixed = TRUE)[[1L]]
  if (endsWith(pointer, "/")) {
    tokens <- c(tokens, "")
  }
  for (token in tokens) {
    token <- gsub("~0", "~", gsub("~1", "/", token, fixed = TRUE), fixed = TRUE)
    if (is_json_object(x)) {
      if (!token %in% names(x)) {
        return(FALSE)
      }
      x <- named_member(x, token)
    } else if (is_json_array(x)) {
      if (!grepl("^(0|[1-9][0-9]*)$", token) || as.numeric(token) >= length(x)) {
        return(FALSE)
      }
      x <- x[[as.integer(token) + 1L]]
    } else {
      return(FALSE)
    }
  }
  TRUE
}

# The value of a plain item of a list of categories or missing values, or the
# member `value` of an object item.
list_item_value <- function(item) {
  if (is_json_object(item)) item[["value"]] else item
}

# Stage 5: meaning (E2010 to E2032), on a declaration whose names are unique
# and whose references resolve.
declaration_meaning_issues <- function(d, minimal = FALSE) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  units <- d[["units"]]
  unit_names <- declaration_strings(units, "name")
  parents <- declaration_strings(units, "nested_in")
  names(parents) <- unit_names
  table <- d[["table"]]
  fields <- table[["fields"]]
  field_names <- declaration_strings(fields, "name")
  variables <- d[["variables"]]
  columns <- names(variables)
  roles <- vapply(variables, function(entry) entry[["role"]], "")
  outcomes <- columns[roles == "outcome"]
  outcome_derived <- columns[roles == "outcome_derived"]
  estimands <- d[["estimands"]]
  assignment <- d[["assignment"]]
  features <- unlist(d[["features"]])
  observation <- d[["observation"]]
  has_time <- !is.null(observation[["time"]])

  # The units reached by following nested_in from a unit, stopping when a
  # unit repeats.
  ancestors <- function(unit) {
    found <- character(0)
    current <- parents[[unit]]
    while (!is.na(current) && !current %in% found) {
      found <- c(found, current)
      current <- parents[[current]]
    }
    found
  }
  for (i in seq_along(units)) {
    if (unit_names[i] %in% ancestors(unit_names[i])) {
      add("E2010", path_pointer("units", i - 1L, "nested_in"), list(name = unit_names[i]))
    }
  }
  for (i in seq_along(d[["crossings"]])) {
    pair <- unlist(d[["crossings"]][[i]][["units"]])
    if (pair[2L] %in% ancestors(pair[1L]) || pair[1L] %in% ancestors(pair[2L])) {
      add("E2011", path_pointer("crossings", i - 1L, "units"))
    }
  }

  derived <- lapply(variables, function(entry) unlist(entry[["derived_from"]]))
  for (column in columns) {
    pending <- named_member(derived, column)
    seen <- character(0)
    while (length(pending)) {
      current <- pending[1L]
      pending <- pending[-1L]
      if (current == column) {
        add("E2012", path_pointer("variables", column, "derived_from"), list(name = column))
        break
      }
      if (!current %in% seen) {
        seen <- c(seen, current)
        if (current %in% columns) {
          pending <- c(pending, named_member(derived, current))
        }
      }
    }
  }

  identifiers <- unique(c(unlist(lapply(units, function(unit) unlist(unit[["columns"]]))),
                          columns[roles == "id"]))
  value_lists <- list()
  if (!is.null(table[["missingValues"]])) {
    value_lists <- list(list(items = table[["missingValues"]], path = c("table", "missingValues")))
  }
  for (i in seq_along(fields)) {
    field <- fields[[i]]
    path <- c("table", "fields", i - 1L)
    categories <- field[["categories"]]
    if (!is.null(categories)) {
      type <- field[["type"]]
      for (j in seq_along(categories)) {
        item <- categories[[j]]
        object <- is_json_object(item)
        category <- list_item_value(item)
        wrong <- (type == "string" && !is.character(category)) ||
          (type == "integer" && !is_json_integer(category))
        if (wrong) {
          add("E2013", path_pointer(path, "categories", j - 1L, if (object) "value"),
              list(type = if (type == "string") "a string" else "an integer"))
        }
      }
      value_lists <- c(value_lists, list(list(items = categories, path = c(path, "categories"))))
      if (field_names[i] %in% identifiers) {
        add("E2016", path_pointer(path, "categories"), list(name = field_names[i]))
      }
    }
    if (!is.null(field[["missingValues"]])) {
      value_lists <- c(value_lists, list(list(items = field[["missingValues"]],
                                              path = c(path, "missingValues"))))
    }
  }
  for (entry in value_lists) {
    objects <- vapply(entry$items, is_json_object, NA)
    if (any(objects) && !all(objects)) {
      add("E2014", path_pointer(entry$path))
    }
    values <- lapply(entry$items, list_item_value)
    for (j in seq_along(values)[-1L]) {
      if (any(vapply(values[seq_len(j - 1L)], json_equal, NA, values[[j]]))) {
        add("E2015", path_pointer(entry$path, j - 1L), list(value = list(values[[j]])))
      }
    }
  }

  for (k in seq_along(columns)) {
    column <- columns[k]
    bounds <- variables[[k]][["bounds"]]
    if (!is.null(bounds) && !(bounds[[1L]] < bounds[[2L]])) {
      add("E2017", path_pointer("variables", column, "bounds"))
    }
  }
  for (entry in assignment) {
    column <- entry[["column"]]
    if (column %in% columns && named_member(roles, column) != "assigned") {
      add("E2018", path_pointer("variables", column, "role"), list(name = column))
    }
  }

  misused <- function(name, ...) {
    if (!is.null(name) && name %in% outcomes) {
      add("E2019", path_pointer(...), list(name = name))
    }
  }
  for (i in seq_along(units)) {
    for (j in seq_along(units[[i]][["columns"]])) {
      misused(units[[i]][["columns"]][[j]], "units", i - 1L, "columns", j - 1L)
    }
  }
  for (i in seq_along(d[["crossings"]])) {
    misused(d[["crossings"]][[i]][["list"]], "crossings", i - 1L, "list")
  }
  for (j in seq_along(observation[["key"]])) {
    misused(observation[["key"]][[j]], "observation", "key", j - 1L)
  }
  misused(observation[["time"]][["column"]], "observation", "time", "column")
  for (k in seq_along(columns)) {
    misused(variables[[k]][["trials"]], "variables", columns[k], "trials")
    misused(variables[[k]][["exposure"]][["column"]], "variables", columns[k], "exposure", "column")
  }
  for (j in seq_along(table[["primaryKey"]])) {
    misused(table[["primaryKey"]][[j]], "table", "primaryKey", j - 1L)
  }
  for (i in seq_along(table[["uniqueKeys"]])) {
    for (j in seq_along(table[["uniqueKeys"]][[i]])) {
      misused(table[["uniqueKeys"]][[i]][[j]], "table", "uniqueKeys", i - 1L, j - 1L)
    }
  }
  for (i in seq_along(estimands)) {
    for (name in unique(term_variables(estimands[[i]][["term"]]))) {
      misused(name, "estimands", i - 1L, "term")
    }
  }

  for (k in seq_along(columns)) {
    if (any(derived[[k]] %in% c(outcomes, outcome_derived)) &&
        !roles[k] %in% c("outcome", "outcome_derived")) {
      add("E2020", path_pointer("variables", columns[k], "role"), list(name = columns[k]))
    }
  }
  for (i in seq_along(estimands)) {
    outcome <- estimands[[i]][["outcome"]]
    if (!is.null(outcome) && !outcome %in% outcomes) {
      add("E2021", path_pointer("estimands", i - 1L, "outcome"), list(name = outcome))
    }
    if (length(outcomes) > 1L && is.null(outcome)) {
      add("E2022", path_pointer("estimands", i - 1L))
    }
  }

  for (k in seq_along(columns)) {
    column <- columns[k]
    level <- variables[[k]][["event_level"]]
    field <- if (column %in% field_names) fields[[match(column, field_names)]]
    type <- field[["type"]]
    if (is.null(level) || is.null(type)) {
      next
    }
    matches <- (type == "string" && is.character(level)) ||
      (type %in% c("integer", "number") && is_json_integer(level))
    if (!matches) {
      add("E2023", path_pointer("variables", column, "event_level"), list(type = type))
    } else if (!is.null(field[["categories"]]) &&
               !any(vapply(lapply(field[["categories"]], list_item_value), json_equal, NA, level))) {
      add("E2024", path_pointer("variables", column, "event_level"), list(value = list(level)))
    }
  }

  trial_features <- c("cluster_randomised", "stepped_wedge", "partially_nested")
  requirements <- list(
    cluster_randomised = "/assignment",
    stepped_wedge = c("/assignment", "/observation/time"),
    partially_nested = "/assignment",
    longitudinal = "/observation/time",
    intensive_longitudinal = "/observation/time"
  )
  present <- c("/assignment" = !is.null(assignment), "/observation/time" = has_time)
  for (j in seq_along(features)) {
    for (required in requirements[[features[j]]]) {
      if (!present[[required]]) {
        add("E2025", path_pointer("features", j - 1L),
            list(feature = features[j], required = required))
      }
    }
  }
  for (i in seq_along(units)) {
    if (identical(units[[i]][["membership"]], "may_change_over_time") && !has_time) {
      add("E2026", path_pointer("units", i - 1L, "membership"))
    }
  }
  observational <- "observational" %in% features
  if (observational) {
    if (!is.null(assignment)) {
      add("E2027", "/assignment")
    }
    for (column in columns[roles == "assigned"]) {
      add("E2027", path_pointer("variables", column, "role"))
    }
    for (j in which(features %in% trial_features)) {
      add("E2027", path_pointer("features", j - 1L))
    }
  }

  if (isTRUE(minimal) || identical(d[["goal"]], "confirmatory") || any(features %in% trial_features)) {
    for (block in c("units", "observation", "variables", "estimands")) {
      if (is.null(d[[block]])) {
        add("E2028", "", list(key = block))
      }
    }
    if (!is.null(observation) && is.null(observation[["key"]])) {
      add("E2028", "/observation", list(key = "key"))
    }
    if (!is.null(variables) && length(outcomes) == 0L) {
      add("E2029", "/variables")
    }
    if (is.null(assignment) && !any(roles == "assigned") && !observational) {
      add("E2030", "")
    }
    focal <- vapply(estimands, function(estimand) !isFALSE(estimand[["focal"]]), NA)
    if (!is.null(estimands) && !any(focal)) {
      add("E2031", "/estimands")
    }
    if (!is.null(d[["provenance"]][["inferred"]])) {
      add("E2032", "/provenance/inferred")
    }
  }
  issues
}
