# The code-first builders of declarations and draft_design(), which writes a
# draft declaration from the data (02-decisions.md, Q4, and
# docs/spec/declarations.md). Both give the JSON that a hand-written
# declaration gives, and validate_declaration() checks it.

#' Build a design declaration in code
#'
#' Assembles a declaration of vocabulary 0.1 from its blocks and validates it
#' with [validate_declaration()]. The entries of the blocks come from
#' `declare_unit()`, `declare_crossing()`, `declare_observation()`,
#' `declare_assignment()`, `declare_variable()` and `declare_estimand()`, or
#' are written as named lists. A block left `NULL` is absent. The result is
#' the declaration that the same JSON file gives, with the same hash.
#'
#' @param units `NULL` or a list of units, from `declare_unit()`.
#' @param crossings `NULL` or a list of crossings, from `declare_crossing()`.
#' @param observation `NULL` or the observation block, from
#'   `declare_observation()`.
#' @param assignment `NULL` or a list of assignments, from
#'   `declare_assignment()`.
#' @param variables `NULL` or a list of variables named by column, each from
#'   `declare_variable()`.
#' @param estimands `NULL` or a list of estimands, from `declare_estimand()`.
#' @param table `NULL` or the table block, a named list in the form of
#'   declarations.md (table).
#' @param title,goal,disclosure_unit `NULL` or a string.
#' @param features `NULL` or a character vector of features.
#' @param provenance `NULL` or the provenance block as a named list.
#' @param vocabulary The vocabulary version.
#' @param minimal Whether the declaration must be a minimal declaration.
#' @return The declaration, as [validate_declaration()] returns it.
#' @section Errors: Arguments of the wrong type give an ordinary error, and
#'   a declaration that is not valid the error of [validate_declaration()].
#' @family declarations
#' @export
#' @examples
#' # Pupils in classes randomised within schools.
#' d <- declaration(
#'   units = list(
#'     declare_unit("school", "school", role = "cluster"),
#'     declare_unit("class", "class", nested_in = "school", id_scope = "within_parent",
#'                  role = "cluster"),
#'     declare_unit("pupil", "pupil", nested_in = "class", id_scope = "global",
#'                  role = "participant")
#'   ),
#'   observation = declare_observation(key = "pupil", unit = "pupil"),
#'   assignment = list(declare_assignment("arm", "class", randomised = TRUE,
#'                                        level = "between_unit", blocks = "school")),
#'   variables = list(score = declare_variable("outcome", measurement = "continuous"),
#'                    arm = declare_variable("assigned")),
#'   estimands = list(declare_estimand("itt", "arm", kind = "total_effect")),
#'   features = "cluster_randomised",
#'   goal = "confirmatory"
#' )
#' canonical_hash(d, "hashable")
declaration <- function(units = NULL, crossings = NULL, observation = NULL, assignment = NULL,
                        variables = NULL, estimands = NULL, table = NULL, title = NULL,
                        goal = NULL, features = NULL, disclosure_unit = NULL,
                        provenance = NULL, vocabulary = "0.1.0", minimal = FALSE) {
  value <- list(vocabulary = builder_string(vocabulary, "vocabulary"))
  value$title <- builder_string(title, "title")
  value$goal <- builder_string(goal, "goal")
  value$features <- builder_strings(features, "features")
  value$disclosure_unit <- builder_string(disclosure_unit, "disclosure_unit")
  value$table <- builder_object(table, "table")
  value$units <- builder_entries(units, "units")
  value$crossings <- builder_entries(crossings, "crossings")
  value$observation <- builder_object(observation, "observation")
  value$assignment <- builder_entries(assignment, "assignment")
  if (!is.null(variables) && (!is.list(variables) || is.null(names(variables)) ||
                              anyNA(names(variables)) || !all(nzchar(names(variables))))) {
    stop("'variables' must be NULL or a list named by column.", call. = FALSE)
  }
  value$variables <- variables
  value$estimands <- builder_entries(estimands, "estimands")
  value$provenance <- builder_object(provenance, "provenance")
  validate_declaration(value, minimal = minimal)
}

#' @rdname declaration
#' @param name The name of the unit.
#' @param columns The columns that label a member of the unit.
#' @param nested_in,id_scope,membership `NULL` or a string, as
#'   declarations.md (units) defines them.
#' @export
declare_unit <- function(name, columns, nested_in = NULL, id_scope = NULL, membership = NULL,
                         role = NULL) {
  builder_entry(name = builder_string(name, "name"),
                columns = builder_strings(columns, "columns"),
                nested_in = builder_string(nested_in, "nested_in"),
                id_scope = builder_string(id_scope, "id_scope"),
                membership = builder_string(membership, "membership"),
                role = builder_string(role, "role"))
}

#' @rdname declaration
#' @param list_column `NULL` or the column that holds the counterbalancing
#'   list, the member `list` of a crossing.
#' @export
declare_crossing <- function(units, list_column = NULL) {
  builder_entry(units = builder_strings(units, "units"),
                list = builder_string(list_column, "list_column"))
}

#' @rdname declaration
#' @param key `NULL` or the columns that identify a row.
#' @param unit `NULL` or the unit of which each row is one member, or, for
#'   `declare_assignment()`, the unit whose members were assigned.
#' @param time_column,time_kind,time_within `NULL` or the column, kind and
#'   unit of the time of a row, the members of `time`.
#' @export
declare_observation <- function(key = NULL, unit = NULL, time_column = NULL, time_kind = NULL,
                                time_within = NULL) {
  time <- builder_entry(column = builder_string(time_column, "time_column"),
                        kind = builder_string(time_kind, "time_kind"),
                        within = builder_string(time_within, "time_within"))
  builder_entry(unit = builder_string(unit, "unit"), key = builder_strings(key, "key"),
                time = if (length(time)) time)
}

#' @rdname declaration
#' @param column The assigned column.
#' @param randomised Whether the assignment was randomised.
#' @param level `NULL`, 'between_unit' or 'within_unit'.
#' @param blocks `NULL` or the units within whose members assignment was made.
#' @export
declare_assignment <- function(column, unit, randomised, level = NULL, blocks = NULL) {
  if (!is_flag(randomised)) {
    stop("'randomised' must be TRUE or FALSE.", call. = FALSE)
  }
  builder_entry(column = builder_string(column, "column"), unit = builder_string(unit, "unit"),
                randomised = randomised, level = builder_string(level, "level"),
                blocks = builder_strings(blocks, "blocks"))
}

#' @rdname declaration
#' @param role For `declare_unit()`, `NULL` or the role of the members of
#'   the unit, and for `declare_variable()`, the role of the column.
#' @param measurement `NULL` or the measurement level.
#' @param derived_from `NULL` or the columns the column was computed from.
#' @param bounds `NULL` or the lowest and highest possible values.
#' @param event_level `NULL` or the value of a binary outcome that counts as
#'   the event.
#' @param trials `NULL` or the column of the number of trials.
#' @param exposure_column,exposure_scale `NULL` or the column and scale, 'raw'
#'   or 'log', of the exposure, the members of `exposure`.
#' @export
declare_variable <- function(role, measurement = NULL, derived_from = NULL, bounds = NULL,
                             event_level = NULL, trials = NULL, exposure_column = NULL,
                             exposure_scale = NULL) {
  if (!is.null(bounds) && (!is.numeric(bounds) || length(bounds) != 2L || anyNA(bounds))) {
    stop("'bounds' must be NULL or two numbers.", call. = FALSE)
  }
  if (!is.null(event_level) &&
      !((is.character(event_level) || is.numeric(event_level)) && length(event_level) == 1L &&
          !is.na(event_level))) {
    stop("'event_level' must be NULL, a string or a number.", call. = FALSE)
  }
  exposure <- builder_entry(column = builder_string(exposure_column, "exposure_column"),
                            scale = builder_string(exposure_scale, "exposure_scale"))
  builder_entry(role = builder_string(role, "role"),
                measurement = builder_string(measurement, "measurement"),
                derived_from = builder_strings(derived_from, "derived_from"),
                bounds = if (!is.null(bounds)) as.list(as.double(bounds)),
                event_level = event_level,
                trials = builder_string(trials, "trials"),
                exposure = if (length(exposure)) exposure)
}

#' @rdname declaration
#' @param id The identifier of the estimand.
#' @param term The fixed-effect term, its variables joined by ':'.
#' @param kind `NULL`, 'total_effect', 'direct_effect' or 'association'.
#' @param focal `NULL`, `TRUE` or `FALSE`. Absent, an estimand is focal.
#' @param outcome `NULL` or the outcome column of the estimand.
#' @export
declare_estimand <- function(id, term, kind = NULL, focal = NULL, outcome = NULL) {
  if (!is.null(focal) && !is_flag(focal)) {
    stop("'focal' must be NULL, TRUE or FALSE.", call. = FALSE)
  }
  builder_entry(id = builder_string(id, "id"), term = builder_string(term, "term"),
                kind = builder_string(kind, "kind"), focal = focal,
                outcome = builder_string(outcome, "outcome"))
}

# A named list of the members that are not NULL.
builder_entry <- function(...) {
  members <- list(...)
  members[!vapply(members, is.null, NA)]
}

builder_string <- function(x, name) {
  if (!is.null(x) && !is_string(x)) {
    stop(sprintf("'%s' must be NULL or a character string.", name), call. = FALSE)
  }
  x
}

# A character vector as a JSON array.
builder_strings <- function(x, name) {
  if (is.null(x)) {
    return(NULL)
  }
  if (!is.character(x) || anyNA(x)) {
    stop(sprintf("'%s' must be NULL or a character vector.", name), call. = FALSE)
  }
  as.list(x)
}

builder_object <- function(x, name) {
  if (!is.null(x) && (!is.list(x) || (length(x) && is.null(names(x))))) {
    stop(sprintf("'%s' must be NULL or a named list.", name), call. = FALSE)
  }
  x
}

builder_entries <- function(x, name) {
  if (!is.null(x) && (!is.list(x) || !is.null(names(x)))) {
    stop(sprintf("'%s' must be NULL or an unnamed list of entries.", name), call. = FALSE)
  }
  x
}

#' Draft a design declaration from the data
#'
#' Writes a declaration pre-filled from what the data and the formula show,
#' with every entry listed in `/provenance/inferred`, so that it is a draft:
#' each entry counts as absent for every check until the user accepts it by
#' removing its pointer (declarations.md, provenance). The draft reads only
#' the grouping columns of the formula and never the outcome, whose column it
#' names from the formula alone.
#'
#' The draft holds a unit for each grouping column that is not a predictor,
#' in the order of the formula. A unit is nested, with id_scope 'global', in
#' the unit with the most labels among those of which each of its labels
#' meets exactly one label in the rows where both are present, when the
#' reverse does not hold. Labels reused within parents, as class labels 1, 2
#' and 3 in every school, look like crossed units in the data (02-decisions.md,
#' Q4), so the draft never infers id_scope 'within_parent', and a grouping
#' such as `(1 | school/class)` does not decide it either, since the formula
#' writes crossed factors in the same way. Two units neither of which is
#' nested in the other, directly or through other units, are crossed when a
#' label of each meets two or more labels of the other. The observation key
#' is the first set of grouping columns, by size and then in the order of the
#' units, whose values identify every row and are never missing. The
#' response is declared with the role outcome. Roles of units, assignments,
#' measurement levels and estimands cannot be read from the data and are
#' left to the user.
#'
#' @inheritParams audit
#' @param coding `NULL`, or the coding of the model, as [formula_ir()] takes
#'   it.
#' @return The draft declaration, as [validate_declaration()] returns it.
#' @section Errors: The errors of [audit()] for the data, the formula and
#'   the coding.
#' @family declarations
#' @export
#' @examples
#' fixture <- pathology_zoo("Z01")
#' draft <- draft_design(fixture$data, fixture$formula)
#' unlist(draft$provenance$inferred)
draft_design <- function(data, formula, coding = NULL) {
  arguments <- audit_arguments(data, formula, NULL, coding, NULL, NULL, "T0", NULL, FALSE,
                               NULL, "shareable", plan_key)
  table <- run_data(data, NULL)$table
  ir <- build_formula_ir(arguments$formula, NULL, table, arguments$coding, NULL, character(0))
  run <- new.env(parent = emptyenv())
  run$table <- table
  run$cache <- new.env(parent = emptyenv())
  # The grouping columns in order, other than predictors, such as the
  # factor f of (1 | g:f).
  columns <- character(0)
  for (term in ir$random) {
    for (column in unlist(term$grouping)) {
      if (!column %in% c(columns, names(ir$predictors))) {
        columns <- c(columns, column)
      }
    }
  }
  names <- draft_unit_names(columns)
  rows_of <- function(a, b) {
    which(!table$missing[[column_index(run, a)]] & !table$missing[[column_index(run, b)]])
  }
  # Whether each label of a meets exactly one label of b where both are present.
  within <- function(a, b) {
    rows <- rows_of(a, b)
    if (!length(rows)) {
      return(FALSE)
    }
    codes_a <- column_codes(run, a)[rows]
    pairs <- unique(paste(codes_a, column_codes(run, b)[rows]))
    length(pairs) == length(unique(codes_a))
  }
  label_count <- function(a) length(unique(stats::na.omit(column_codes(run, a))))
  units <- list()
  parent_of <- rep(NA_integer_, length(columns))
  for (i in seq_along(columns)) {
    unit <- list(name = names[i], columns = list(columns[i]))
    candidates <- which(vapply(seq_along(columns), function(j) {
      j != i && within(columns[i], columns[j]) && !within(columns[j], columns[i])
    }, NA))
    if (length(candidates)) {
      counts <- vapply(candidates, function(j) label_count(columns[j]), 0L)
      parent_of[i] <- candidates[which.max(counts)]
      unit$nested_in <- names[parent_of[i]]
      unit$id_scope <- "global"
    }
    units[[i]] <- unit
  }
  ancestors <- function(i) {
    found <- integer(0)
    while (!is.na(parent_of[i]) && !parent_of[i] %in% found) {
      i <- parent_of[i]
      found <- c(found, i)
    }
    found
  }
  crossings <- list()
  for (i in seq_along(columns)) {
    for (j in seq_along(columns)) {
      if (j <= i || j %in% ancestors(i) || i %in% ancestors(j)) {
        next
      }
      if (draft_crossed(run, rows_of(columns[i], columns[j]), columns[i], columns[j])) {
        crossings[[length(crossings) + 1L]] <- list(units = list(names[i], names[j]))
      }
    }
  }
  key <- draft_key(run, columns)
  draft <- list(vocabulary = "0.1.0")
  inferred <- character(0)
  if (length(units)) {
    draft$units <- units
    inferred <- c(inferred, vapply(seq_along(units), function(i) path_pointer("units", i - 1L), ""))
  }
  if (length(crossings)) {
    draft$crossings <- crossings
    inferred <- c(inferred, vapply(seq_along(crossings), function(i) {
      path_pointer("crossings", i - 1L)
    }, ""))
  }
  if (length(key)) {
    draft$observation <- list(key = as.list(key))
    inferred <- c(inferred, "/observation/key")
  }
  response <- ir$response$variable
  if (!is.null(response)) {
    draft$variables <- structure(list(list(role = "outcome")), names = response)
    inferred <- c(inferred, path_pointer("variables", response))
  }
  draft$provenance <- list(created = utc_timestamp(run_time()))
  if (length(inferred)) {
    draft$provenance$inferred <- as.list(inferred)
  }
  validate_declaration(draft)
}

# Unit names for grouping columns: the column name when it is a valid name
# of a unit (defs.schema.json, name), and otherwise 'unit' followed by the
# position of the column, counted from 1, with '_' and a number added until
# the name differs from those before it.
draft_unit_names <- function(columns) {
  found <- character(0)
  for (i in seq_along(columns)) {
    name <- if (grepl("^[A-Za-z][A-Za-z0-9_.]{0,63}$", columns[i])) columns[i] else
      paste0("unit", i)
    base <- name
    k <- 1L
    while (name %in% found) {
      k <- k + 1L
      name <- paste0(substr(base, 1L, 60L), "_", k)
    }
    found <- c(found, name)
  }
  found
}

# Whether a label of each of two columns meets two or more labels of the
# other in the rows given.
draft_crossed <- function(run, rows, a, b) {
  if (!length(rows)) {
    return(FALSE)
  }
  codes_a <- column_codes(run, a)[rows]
  codes_b <- column_codes(run, b)[rows]
  pairs <- !duplicated(paste(codes_a, codes_b))
  any(tabulate(codes_a[pairs]) >= 2L) && any(tabulate(codes_b[pairs]) >= 2L)
}

# The first set of columns, by size and then in the order given, whose
# values are present in every row and identify the rows of the table.
draft_key <- function(run, columns) {
  present <- columns[vapply(columns, function(c) !any(run$table$missing[[column_index(run, c)]]), NA)]
  for (size in seq_along(present)) {
    for (set in utils::combn(length(present), size, simplify = FALSE)) {
      codes <- value_codes(run, present[set])
      if (!anyDuplicated(codes)) {
        return(present[set])
      }
    }
  }
  character(0)
}
