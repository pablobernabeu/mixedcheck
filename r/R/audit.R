# The entry point of Stream B: audit() runs the checks of the registry on the
# design of a model and returns a results object (03-execution-plan.md, M2,
# and docs/spec/documents.md, Results document).

#' Audit the design of a mixed-effects model
#'
#' Runs the checks of the registry on the design of a model before it is
#' fitted and returns a results object. The checks of tier T0 read the table
#' and the design sample and never the outcome. The checks of tier T1 read
#' the outcome marginally or by grouping factor and run only when
#' `outcome_access` asks for them with a reason, and the exploratory check of
#' tier T2 relates the outcome to the predictors by linear programs, which the
#' suggested package lpSolve solves, so that it is not available without
#' lpSolve. The access log of the results document records every access to
#' the outcome with a keyed commitment to the column read.
#'
#' The check of tier T2, outcome.separation, solves two linear programs over
#' every observation and, when it finds separation, two more for each kept
#' fixed-effects column. Limits on the size of these programs, which grows
#' with the observations and the kept columns, bound its time: beyond the
#' parameter max_size of its registry entry, the check is not available,
#' and beyond max_bound_programs or max_bound_size, its finding leaves out
#' the bounds of the coefficients and the columns involved.
#'
#' A run takes the steps of the execution plan in order and stops at the
#' first that fails: the arguments, the declaration, the data, the columns
#' that the declaration names, the IR, the columns that the outcome-blind
#' checks may read, the family class, the design sample with X and Z, at T1
#' and T2 the analysis sample with the response, the checks, the order of
#' the findings, the privacy filter, the access log and the inputs of the
#' document. The data are converted as [formula_ir()] converts them, after
#' the missing values that the declaration's table block lists are applied
#' to a data frame. Every column of the data must hold numbers, strings or
#' logical values, since the commitment to the analysis table covers every
#' column.
#'
#' The family class decides which checks apply. 'gaussian' gives the class
#' gaussian, 'binomial' the class binomial when the response has a trials
#' column and bernoulli otherwise, 'poisson' and 'negative_binomial' the
#' class poisson, and 'beta', 'gamma', 'inverse_gaussian' and 'cumulative'
#' the class other. Without a family, the class follows the measurement level
#' that the declaration gives the response: binary gives bernoulli, binomial
#' gives binomial, count gives poisson, ordinal gives other, and any other
#' level, or none, gives gaussian.
#'
#' The times of the run are UTC times truncated to whole seconds. When the
#' environment variable MIXEDCHECK_TIME is set to a whole number of seconds
#' since 1970-01-01T00:00:00Z, written as one or more of the ASCII digits 0
#' to 9 and nothing else, every time of the run is that time instead, so that
#' a run can be repeated byte for byte.
#'
#' Shareable mode, the default, passes the findings through the privacy
#' filter of the
#' [privacy specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/privacy.md).
#' It writes as null, with the reason privacy_suppressed and the rule that
#' applied, the values that could disclose a person's data: counts of
#' persons below the minimum count of the registry, values of findings with
#' too few contributors or dominated by their largest contributors, values
#' that would give back a suppressed one by a sum, difference or ratio,
#' minima and maxima, quantiles of too few values and any value from which
#' a reader could infer a suppressed value that depends on the outcome. A
#' finding of an outcome check whose decision rests on a suppressed count is
#' suppressed as a whole, messages are rendered from the written values and
#' labels are replaced by pseudonyms, which the sidecar maps back to them.
#' Internal mode writes every value, and its documents must stay on the
#' analyst's machine.
#'
#' @param data A data frame, whose columns hold numbers (double or integer),
#'   strings (character, or a factor, whose labels are used) or logical
#'   values, with `NA` for a missing value, or the path of a CSV file, which
#'   [read_table()] reads with the declaration.
#' @param formula The formula, as a character string, such as
#'   `"rt ~ cond + (1 + cond | subject)"`.
#' @param declaration `NULL`, or a declaration as [validate_declaration()]
#'   accepts it: the path of a JSON or YAML file or a named list.
#' @param family `NULL`, or the name of the family of the model that will be
#'   fitted: 'gaussian', 'binomial', 'poisson', 'negative_binomial', 'beta',
#'   'gamma', 'inverse_gaussian' or 'cumulative'.
#' @param coding,weights,sample_columns The coding, weights and sample
#'   columns of the model, as [formula_ir()] takes them.
#' @param outcome_access The highest tier of checks to run: 'T0', 'T1' or
#'   'T2'.
#' @param reason The reason for reading the outcome, a text of 1 to 4000
#'   characters without control characters, which the access log records as
#'   given. It is required at T1 and T2 and refused at T0.
#' @param exploratory Whether the run is exploratory, which T2 requires.
#' @param outcome_seen `NULL`, `TRUE` or `FALSE`: whether the outcome had
#'   been seen before the run, as for secondary data. `NULL` takes
#'   `/provenance/outcome_seen` of the declaration, when it has one, and a
#'   value that differs from it is refused.
#' @param privacy 'shareable' or 'internal'. Only an explicit 'internal'
#'   skips the privacy filter.
#' @param key `NULL`, or the commitment key of the run as 64 lower-case
#'   hexadecimal digits. Without it, the run creates a key as
#'   [new_commitment_key()] does.
#' @return A results object, a list of class 'mixedcheck_results' with the
#'   elements `document`, the results document in the form that
#'   [read_json_strict()] returns in the data profile, and `sidecar`, the
#'   internal sidecar without `results_hash`: its version, the commitment key
#'   of the run and the pseudonyms. Printing it shows the banner of its
#'   privacy mode and one line for each finding. [write_results()] writes it
#'   and [validate_results()] validates it.
#' @section Errors: A run that cannot proceed gives an error of class
#'   `mixedcheck_error`, whose element `issues` holds one issue: E7008 for a
#'   family that is not accepted, E7009 for an access at T1 or T2 without a
#'   valid reason, at T2 without the exploratory mode or with a formula
#'   without a response, E1311 for a key of the wrong form, E1312 when no
#'   secure source of random bytes is available to create one, the error of
#'   [validate_declaration()] or [read_table()], E5011 for a column that the
#'   declaration names and the data lack, the error of [formula_ir()], E6069
#'   for a predictor, grouping variable, offset, weights column, sample
#'   column, column of the observation key, column of a declared unit or
#'   assigned column that is the response, holds its trials or is declared an
#'   outcome or derived from one, E7007 for a design sample, or at T1 and T2 an
#'   analysis sample, without rows, and the errors of [design_matrices()] for
#'   the values that the samples read. Arguments of the wrong type, a reason
#'   at T0, an `outcome_seen` that differs from the declaration, columns of
#'   other types, such as dates, and an invalid MIXEDCHECK_TIME give an
#'   ordinary error.
#' @family results documents
#' @export
#' @examples
#' # Fixture Z08 of the pathology zoo: classes randomised within schools,
#' # with a formula that leaves out the class (pathology_zoo()).
#' fixture <- pathology_zoo("Z08")
#' key <- paste(sprintf("%02x", 0:31), collapse = "")
#' results <- audit(fixture$data, fixture$formula, fixture$declaration, key = key)
#' results
#'
#' # Internal mode writes every value.
#' audit(fixture$data, fixture$formula, fixture$declaration, privacy = "internal", key = key)
#'
#' # A family that audit() does not accept.
#' problem <- tryCatch(audit(fixture$data, "y ~ arm", family = "logit", privacy = "internal"),
#'                     mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
audit <- function(data, formula, declaration = NULL, family = NULL, coding = NULL,
                  weights = NULL, sample_columns = NULL, outcome_access = "T0",
                  reason = NULL, exploratory = FALSE, outcome_seen = NULL,
                  privacy = "shareable", key = NULL) {
  # Step 1: the arguments.
  arguments <- audit_arguments(data, formula, family, coding, weights, sample_columns,
                               outcome_access, reason, exploratory, outcome_seen, privacy, key)
  tier <- arguments$tier
  # Step 2: the declaration, validated again as a minimal declaration.
  minimal <- NULL
  if (!is.null(declaration)) {
    declaration <- validate_declaration(declaration)
    minimal <- tryCatch({
      validate_declaration(declaration, minimal = TRUE)
      TRUE
    }, mixedcheck_error = function(e) FALSE)
  }
  outcome_seen <- audit_outcome_seen(arguments$outcome_seen, declaration)
  # Step 3: the data.
  data <- run_data(data, declaration)
  table <- data$table
  # Step 4: the columns that the declaration names.
  declared_columns_present(declaration, table)
  # Step 5: the IR, and a response for an access to the outcome.
  ir <- build_formula_ir(arguments$formula, declaration, table, arguments$coding,
                         arguments$weights, arguments$sample_columns)
  if (tier != "T0" && is.null(ir$response)) {
    raise_issue("E7009", list(tier = tier, requirement = "a formula with a response"))
  }
  # Step 6: the columns that the outcome-blind checks may read.
  outcome_blind_columns(ir, declaration)
  # Step 7: the family class.
  family_class <- audit_family_class(arguments$family, ir, declaration)
  # Step 8: the design sample, X and Z, without the response.
  model <- design_model(ir, table, analysis = FALSE)
  if (!length(model$design)) {
    raise_issue("E7007", list(sample = "design"))
  }
  built <- design_build(ir, model, table)
  run <- new_run(declaration, table, ir, family_class, tier, model, built)
  # Step 9: at T1 and T2, the analysis sample and the response.
  if (tier != "T0") {
    analysis <- analysis_rows(ir, table, model$design, model$column)
    if (!length(analysis)) {
      raise_issue("E7007", list(sample = "analysis"))
    }
    vectors <- design_response(ir, model, table, analysis)
    run$analysis <- analysis
    run$response <- vectors$response
    run$trials <- vectors$trials
  }
  # Steps 10 and 11: the checks, the resolution of by_unit counts and the
  # order of the findings.
  checked <- run_checks(run)
  findings <- order_findings(lapply(checked$findings, function(finding) {
    resolve_finding_classes(run, finding)
  }))
  # Step 12: the privacy filter.
  pseudonyms <- list()
  if (arguments$privacy == "shareable") {
    filtered <- privacy_filter(run, findings, arguments$key)
    findings <- filtered$findings
    pseudonyms <- filtered$pseudonyms
  }
  # Step 13: the access log.
  access_log <- list(entries = access_log_entries(run, arguments, checked$times, data,
                                                  declaration))
  if (!is.null(outcome_seen)) {
    access_log$outcome_seen <- outcome_seen
  }
  # Step 14: the inputs and the time of creation.
  response <- ir$response$variable
  inputs <- list(registry_hash = registry_hash())
  if (!is.null(declaration)) {
    inputs$declaration <- list(
      hash = canonical_hash(declaration, "hashable"),
      vocabulary = declaration[["vocabulary"]],
      draft = !is.null(declaration[["provenance"]][["inferred"]]),
      minimal = minimal
    )
  }
  # A shareable document hashes the IR without the constants of its 'mean'
  # centrings, which are means over the design sample (documents.md, inputs).
  hashed <- if (arguments$privacy == "shareable") ir_without_means(ir) else ir
  inputs$model <- list(formula = arguments$formula, family_class = family_class,
                       ir_hash = canonical_hash(hashed, "hashable"))
  inputs$data <- data_commitments(data, declaration, response, arguments$key)
  document <- list(
    results_version = "0.1.0",
    created = utc_timestamp(run_time()),
    stream = "B",
    versions = c(list(package = getNamespaceVersion("mixedcheck")[[1L]]), spec_versions()),
    software = audit_software(run),
    privacy = audit_privacy(run, arguments$privacy),
    inputs = inputs,
    access_log = access_log,
    findings = lapply(findings, document_finding)
  )
  document <- parse_json_bytes(canonical_bytes(document, "data"), "data")
  sidecar <- list(
    sidecar_version = "0.1.0",
    keys = list(list(created = arguments$key_created, key = arguments$key,
                     key_id = commitment_key_id(arguments$key))),
    pseudonyms = pseudonyms
  )
  new_results(document, sidecar)
}

# --- Arguments ------------------------------------------------------------------

# The family names that audit() accepts, in the order that E7008 lists them.
family_names <- c("gaussian", "binomial", "poisson", "negative_binomial", "beta", "gamma",
                  "inverse_gaussian", "cumulative")

# The tiers in order.
tier_names <- c("T0", "T1", "T2")

is_flag <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

# Step 1: the arguments, checked for their types with ordinary errors, then
# E7008, E7009 for the reason and for T2 without the exploratory mode, and
# E1311 or E1312 for the key. Strings cross the input boundary. Returns the
# arguments that later steps use, with the key and the time of its creation.
audit_arguments <- function(data, formula, family, coding, weights, sample_columns,
                            outcome_access, reason, exploratory, outcome_seen, privacy, key) {
  if (!is.data.frame(data) && !is_string(data)) {
    stop("'data' must be a data frame or the path of a CSV file.", call. = FALSE)
  }
  if (!is_string(formula)) {
    stop("'formula' must be a character string.", call. = FALSE)
  }
  if (!is.null(family) && !is_string(family)) {
    stop("'family' must be NULL or a character string.", call. = FALSE)
  }
  check_coding_argument(coding)
  if (!is.null(weights) && !is_string(weights)) {
    stop("'weights' must be NULL or a column name.", call. = FALSE)
  }
  if (!is.null(sample_columns) && (!is.character(sample_columns) || anyNA(sample_columns))) {
    stop("'sample_columns' must be NULL or a character vector of column names.", call. = FALSE)
  }
  if (!is_string(outcome_access) || !outcome_access %in% tier_names) {
    stop("'outcome_access' must be 'T0', 'T1' or 'T2'.", call. = FALSE)
  }
  if (!is.null(reason) && !is_string(reason)) {
    stop("'reason' must be NULL or a character string.", call. = FALSE)
  }
  if (outcome_access == "T0" && !is.null(reason)) {
    stop("'reason' is given only for outcome access at T1 or T2.", call. = FALSE)
  }
  if (!is_flag(exploratory)) {
    stop("'exploratory' must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.null(outcome_seen) && !is_flag(outcome_seen)) {
    stop("'outcome_seen' must be NULL, TRUE or FALSE.", call. = FALSE)
  }
  if (!is_string(privacy) || !privacy %in% c("shareable", "internal")) {
    stop("'privacy' must be 'shareable' or 'internal'.", call. = FALSE)
  }
  if (!is.null(key) && !is_string(key)) {
    stop("'key' must be NULL or a character string.", call. = FALSE)
  }
  formula <- input_strings(formula, function(i) "/formula")
  if (!is.null(weights)) {
    weights <- input_strings(weights, function(i) "/weights")
  }
  sample_columns <- if (length(sample_columns)) {
    input_strings(sample_columns, function(i) json_pointer(c("sample_columns", i - 1L)))
  } else {
    character(0)
  }
  coding <- coding_input(coding)
  if (!is.null(family) && !family %in% family_names) {
    raise_issue("E7008", list(name = input_strings(family, function(i) "/family"),
                              expected = as.list(family_names)))
  }
  if (outcome_access != "T0") {
    reason_valid <- FALSE
    if (!is.null(reason)) {
      reason <- input_strings(reason, function(i) "/reason")
      codepoints <- utf8ToInt(reason)
      reason_valid <- length(codepoints) >= 1L && length(codepoints) <= 4000L &&
        !any(codepoints <= 0x1FL | codepoints == 0x7FL)
    }
    if (!reason_valid) {
      raise_issue("E7009", list(
        tier = outcome_access,
        requirement = "a reason of 1 to 4000 characters without control characters"
      ))
    }
    if (outcome_access == "T2" && !exploratory) {
      raise_issue("E7009", list(tier = outcome_access, requirement = "the exploratory mode"))
    }
  }
  key_created <- utc_timestamp(run_time())
  if (is.null(key)) {
    key <- paste(as.character(random_key_bytes()), collapse = "")
  } else {
    commitment_key_bytes(key)
  }
  list(formula = formula, family = family, coding = coding, weights = weights,
       sample_columns = sample_columns, tier = outcome_access, reason = reason,
       outcome_seen = outcome_seen, privacy = privacy, key = key, key_created = key_created)
}

# The attestation of the access log: the argument, or /provenance/outcome_seen
# of the declaration when the argument is NULL. The two must agree when both
# are given.
audit_outcome_seen <- function(argument, declaration) {
  declared <- declaration[["provenance"]][["outcome_seen"]]
  if (!is.null(argument) && !is.null(declared) && !identical(argument, declared)) {
    stop("'outcome_seen' differs from /provenance/outcome_seen of the declaration.",
         call. = FALSE)
  }
  argument %||% declared
}

# --- Times ----------------------------------------------------------------------

# The time of the run, in whole seconds since 1970-01-01T00:00:00Z: the value
# of MIXEDCHECK_TIME when it is set and not empty, and otherwise the current
# time truncated to whole seconds. Windows cannot hold an empty variable, so
# an empty value counts as unset in every system.
run_time <- function() {
  value <- Sys.getenv("MIXEDCHECK_TIME", unset = "")
  if (!nzchar(value)) {
    return(floor(unclass(Sys.time())))
  }
  # Only the ASCII digits count, compared as bytes, whatever the locale. The
  # last second of the year 9999 is the last that a UTC timestamp can write.
  ascii <- grepl("^[0123456789]+$", value, useBytes = TRUE)
  digits <- if (ascii) sub("^0+(?=[0-9])", "", value, perl = TRUE) else ""
  if (!ascii || nchar(digits) > 12L || as.numeric(digits) > 253402300799) {
    stop(paste("The environment variable MIXEDCHECK_TIME must be a whole number of seconds",
               "since 1970-01-01T00:00:00Z, written in the digits 0 to 9, up to the end of the",
               "year 9999."), call. = FALSE)
  }
  as.numeric(digits)
}

# A whole number of seconds since 1970-01-01T00:00:00Z written as a UTC
# timestamp, YYYY-MM-DDTHH:MM:SSZ, with the days converted to a date of the
# proleptic Gregorian calendar in integer arithmetic, so that no time zone or
# platform routine is involved.
utc_timestamp <- function(seconds) {
  days <- floor(seconds / 86400)
  rest <- seconds - days * 86400
  z <- days + 719468
  era <- floor(z / 146097)
  day_of_era <- z - era * 146097
  year_of_era <- floor((day_of_era - floor(day_of_era / 1460) + floor(day_of_era / 36524) -
                          floor(day_of_era / 146096)) / 365)
  day_of_year <- day_of_era - (365 * year_of_era + floor(year_of_era / 4) -
                                 floor(year_of_era / 100))
  month_index <- floor((5 * day_of_year + 2) / 153)
  day <- day_of_year - floor((153 * month_index + 2) / 5) + 1
  month <- month_index + ifelse(month_index < 10, 3, -9)
  year <- year_of_era + era * 400 + (month <= 2)
  sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", as.integer(year), as.integer(month),
          as.integer(day), as.integer(rest %/% 3600), as.integer(rest %% 3600 %/% 60),
          as.integer(rest %% 60))
}

# --- Declaration and data ---------------------------------------------------------

# Whether the entry at a pointer of the declaration counts as absent because
# /provenance/inferred lists the pointer or one above it (declarations.md,
# provenance).
declaration_inferred <- function(declaration, pointer) {
  inferred <- as.character(unlist(declaration[["provenance"]][["inferred"]]))
  any(inferred == pointer | startsWith(pointer, paste0(inferred, "/")))
}

# The columns that a declaration names, with their pointers, in the order of
# the places that E2007 lists (declarations.md, Stage 4): unit columns,
# crossing lists, the observation key, the time column, assigned columns,
# the keys of variables, derived_from, trials, exposure columns, the outcomes
# of estimands, the primary key, the unique keys and the variables of
# estimand terms, each place in the order of its entries and the keys of
# variables in code-point order.
declared_column_places <- function(declaration) {
  places <- list()
  add <- function(name, ...) {
    if (!is.null(name)) {
      places[[length(places) + 1L]] <<- list(name = name, pointer = path_pointer(...))
    }
  }
  units <- declaration[["units"]]
  for (i in seq_along(units)) {
    for (j in seq_along(units[[i]][["columns"]])) {
      add(units[[i]][["columns"]][[j]], "units", i - 1L, "columns", j - 1L)
    }
  }
  crossings <- declaration[["crossings"]]
  for (i in seq_along(crossings)) {
    add(crossings[[i]][["list"]], "crossings", i - 1L, "list")
  }
  observation <- declaration[["observation"]]
  for (j in seq_along(observation[["key"]])) {
    add(observation[["key"]][[j]], "observation", "key", j - 1L)
  }
  add(observation[["time"]][["column"]], "observation", "time", "column")
  assignment <- declaration[["assignment"]]
  for (i in seq_along(assignment)) {
    add(assignment[[i]][["column"]], "assignment", i - 1L, "column")
  }
  variables <- declaration[["variables"]]
  columns <- as.character(names(variables))
  ordered <- order(columns, method = "radix")
  for (k in ordered) {
    add(columns[k], "variables", columns[k])
  }
  for (k in ordered) {
    derived <- variables[[k]][["derived_from"]]
    for (j in seq_along(derived)) {
      add(derived[[j]], "variables", columns[k], "derived_from", j - 1L)
    }
  }
  for (k in ordered) {
    add(variables[[k]][["trials"]], "variables", columns[k], "trials")
  }
  for (k in ordered) {
    add(variables[[k]][["exposure"]][["column"]], "variables", columns[k], "exposure", "column")
  }
  estimands <- declaration[["estimands"]]
  for (i in seq_along(estimands)) {
    add(estimands[[i]][["outcome"]], "estimands", i - 1L, "outcome")
  }
  table <- declaration[["table"]]
  for (j in seq_along(table[["primaryKey"]])) {
    add(table[["primaryKey"]][[j]], "table", "primaryKey", j - 1L)
  }
  for (i in seq_along(table[["uniqueKeys"]])) {
    for (j in seq_along(table[["uniqueKeys"]][[i]])) {
      add(table[["uniqueKeys"]][[i]][[j]], "table", "uniqueKeys", i - 1L, j - 1L)
    }
  }
  for (i in seq_along(estimands)) {
    for (name in unique(term_variables(estimands[[i]][["term"]]))) {
      add(name, "estimands", i - 1L, "term")
    }
  }
  places
}

# Step 4: E5011 for the first column that the declaration names and the data
# lack, compared after NFC, whatever the table block.
declared_columns_present <- function(declaration, table) {
  for (place in declared_column_places(declaration)) {
    if (!comparison_form(place$name) %in% table$keys) {
      raise_issue("E5011", list(column = place$name), pointer = place$pointer)
    }
  }
  invisible()
}

# The comparison forms of the columns that the declaration gives one of the
# roles, whether or not /provenance/inferred lists the role, since a column
# that may hold the outcome is kept from the outcome-blind checks either way.
declared_role_columns <- function(declaration, roles) {
  variables <- declaration[["variables"]]
  found <- vapply(variables, function(entry) isTRUE(entry[["role"]] %in% roles), NA)
  comparison_form(as.character(names(variables))[found])
}

# The columns, as the declaration names them, to which it gives a role that
# /provenance/inferred does not list, or one of the roles given.
role_columns <- function(declaration, roles = NULL) {
  variables <- declaration[["variables"]]
  named <- as.character(names(variables))
  named[vapply(seq_along(named), function(i) {
    role <- variables[[i]][["role"]]
    !is.null(role) && (is.null(roles) || role %in% roles) &&
      !declaration_inferred(declaration, path_pointer("variables", named[i], "role"))
  }, NA)]
}

# Step 6: E6069 for the first column that the outcome-blind checks would
# read and that is the response, its trials column or a column that the
# declaration gives the role outcome or outcome_derived (registry.md, Tier
# and inputs). The columns come in this order: the predictors in code-point
# order, the grouping variables in the order of the IR, the offsets, the
# weights, the sample columns of the IR, the key in its declared order, the
# columns of the declared units and the assigned columns, each block in its
# declared order and leaving out what counts as absent.
outcome_blind_columns <- function(ir, declaration) {
  refused <- c(declared_role_columns(declaration, c("outcome", "outcome_derived")),
               ir$response$variable, ir$response$trials)
  if (!length(refused)) {
    return(invisible())
  }
  given <- c(
    sort_identifiers(as.character(names(ir$predictors))),
    unlist(lapply(ir$random, function(term) unlist(term$grouping))),
    vapply(ir$offsets, function(o) o$variable, ""),
    ir$weights$variable,
    as.character(unlist(ir$sample_columns)),
    observation_key_columns(declaration),
    as.character(unlist(lapply(declared_units(declaration), function(unit) unit[["columns"]]))),
    vapply(assignment_elements(declaration), function(a) a$column, "")
  )
  found <- which(comparison_form(as.character(given)) %in% refused)
  if (length(found)) {
    raise_issue("E6069", list(column = given[found[1L]]))
  }
  invisible()
}

# Step 7: the family class (registry.md, Family classes).
audit_family_class <- function(family, ir, declaration) {
  if (!is.null(family)) {
    return(switch(family,
      gaussian = "gaussian",
      binomial = if (is.null(ir$response$trials)) "bernoulli" else "binomial",
      poisson = , negative_binomial = "poisson",
      "other"
    ))
  }
  measurement <- NULL
  response <- ir$response$variable
  if (!is.null(response)) {
    variables <- declaration[["variables"]]
    found <- match(response, comparison_form(as.character(names(variables))))
    if (!is.na(found)) {
      pointer <- json_pointer(c("variables", names(variables)[found], "measurement"))
      if (!declaration_inferred(declaration, pointer)) {
        measurement <- variables[[found]][["measurement"]]
      }
    }
  }
  switch(measurement %||% "",
    binary = "bernoulli",
    binomial = "binomial",
    count = "poisson",
    ordinal = "other",
    "gaussian"
  )
}

# --- The document -----------------------------------------------------------------

# Step 13: one entry at T0 and, for each further tier that the run reached,
# one entry for the response and then one for its trials column when the
# IR's response has one, whether or not a check of the tier read them, each
# with its outcome commitment, computed once for each column, and the
# reason. The time of each tier is the time at which its checks started.
access_log_entries <- function(run, arguments, times, data, declaration) {
  entries <- list(list(tier = "T0", time = times[["T0"]], mode = "outcome_blind"))
  reached <- tier_names[seq_len(match(run$tier, tier_names))][-1L]
  columns <- c(run$ir$response$variable, run$ir$response$trials)
  if (length(reached)) {
    commitments <- lapply(columns, function(column) {
      outcome_commitment(data, declaration, column, arguments$key)
    })
  }
  for (tier in reached) {
    for (j in seq_along(columns)) {
      entries[[length(entries) + 1L]] <- list(
        tier = tier, time = times[[tier]], mode = "exploratory",
        outcome = list(column = columns[j], commitment = commitments[[j]]),
        reason = arguments$reason
      )
    }
  }
  outcome_reads_logged(run, entries)
  entries
}

# software: the language, the version of R, the NFC library and the
# packages that the checks record in run$packages, such as the solver of
# outcome.separation, which that check records whenever it is available.
audit_software <- function(run) {
  software <- list(
    language = "R",
    runtime = paste(R.version$major, R.version$minor, sep = "."),
    unicode = list(library = "utf8", version = getNamespaceVersion("utf8")[[1L]])
  )
  if (length(run$packages)) {
    software$packages <- run$packages
  }
  software
}

# privacy: the mode, the parameters of the filter, copied from the compiled
# registry, and the disclosure unit.
audit_privacy <- function(run, mode) {
  parameters <- read_registry()[["privacy"]]
  privacy <- list(
    mode = mode,
    min_count = parameters[["min_count"]],
    dominance = parameters[["dominance"]],
    rounding_base = parameters[["rounding_base"]],
    zeros_disclosive = parameters[["zeros_disclosive"]]
  )
  if (!is.null(run$disclosure)) {
    privacy$disclosure_unit <- list(name = run$disclosure$name, source = run$disclosure$source)
  }
  privacy
}

# The IR that the IR hash of a shareable document covers: each 'mean'
# centring holds the significant digits of its constant in place of the
# constant, as before the data are seen (ir.md, The IR document), since the
# constant is a mean over the design sample, which an unkeyed hash would let
# a reader confirm by search.
ir_without_means <- function(ir) {
  for (i in seq_along(ir$predictors)) {
    centring <- ir$predictors[[i]]$centring
    if (identical(centring$rule, "mean") && !is.null(centring$constant)) {
      ir$predictors[[i]]$centring <- list(
        rule = "mean", sample = centring$sample,
        significant_digits = centring$constant$significant_digits
      )
    }
  }
  ir
}
