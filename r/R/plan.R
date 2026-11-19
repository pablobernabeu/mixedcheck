# The Stream B plan (02-decisions.md, Q3, and docs/spec/documents.md, Plan,
# version 0.1): design_plan() derives the design-implied ceiling, restricts
# it to identifiable terms, builds the outcome-free ladder with its protected
# set and writes the plan with its design-plan hash and an execution binding.

# The stopping rules of the first 0.x release, with their versions and
# parameters as decimal strings (documents.md, The design section).
plan_rule_menu <- list(
  localised_backoff = list(id = "localised_backoff", version = 1,
                           parameters = structure(list(), names = character(0))),
  protected_lrt = list(id = "protected_lrt", version = 1, parameters = list(alpha = "0.2")),
  no_reduction = list(id = "no_reduction", version = 1,
                      parameters = structure(list(), names = character(0)))
)

# The terminal states that this package can run.
plan_terminal_states <- c("no_confirmatory_model", "cluster_robust_cr2")

# The commitment key of the audits that a plan runs internally. Their
# documents are discarded, so no commitment or pseudonym made with it leaves
# design_plan().
plan_key <- strrep("00", 32L)

#' Build a Stream B plan
#'
#' Builds the plan of 02-decisions.md (Q3) for a design, without reading the
#' outcome: the design-implied ceiling of each grouping factor, its
#' identifiability verdict, an outcome-free ladder of nested rungs with its
#' protected set, the stopping rule, the terminal state, the design-plan hash
#' and, when lme4 is installed, an execution binding for lme4.
#'
#' The formula gives the fixed part and the grouping factors. The random
#' slopes it writes are ignored, since the ceiling of each grouping factor is
#' derived from the design: its random intercept and a correlated slope for
#' every fixed term all of whose variables vary within the factor (Barr et
#' al., 2013). A variable varies within a factor unless its value is the same
#' within the levels of the factor for at least the share of rows that the
#' parameter agreement of structure.within_between gives, pooled over the
#' levels with two rows or more, or unless an assignment of the declaration
#' declares its level for the unit of the factor. Every categorical predictor
#' is frozen as numeric contrast columns, with the contrast and reference
#' level of `coding`, and every rung reads the columns of the ceiling as its
#' sample columns, so that all rungs share one design sample.
#'
#' Rung 0 is the ceiling restricted to identifiable terms: the random
#' intercepts and then the slopes are added one at a time, in the order of
#' the IR, and each is kept when the model with it is identified by
#' identifiability.gram_rank. The ladder then simplifies correlations before
#' it removes variances, one grouping factor at a time in the order of the IR:
#' a categorical slope of three or more levels becomes the complex random
#' intercepts `(1 | g) + (1 | g:f)`, and the rest of the block becomes
#' uncorrelated terms, as `||` writes them. It then drops the unprotected
#' slopes, higher-order terms before their marginal terms, and last the
#' unprotected random intercepts of factors that have no slope left, one step
#' for each rung. A rung that is not identified is left out. The last rung is
#' the protected rung.
#'
#' The protected set comes from the declaration: the random intercept of
#' every grouping factor whose columns are the label columns of a declared
#' unit, with the reason randomisation_unit for the unit of a randomised
#' assignment and replication_unit otherwise, and for each focal estimand and
#' each grouping factor, the slope of the variables of its term that vary
#' within the factor: focal_slope for a main effect, focal_interaction_slope
#' for an interaction all of whose variables vary within the factor and
#' cross_level_interaction_slope for the lower-level part of an interaction
#' that some variable crosses levels in. Without a focal estimand, the ladder
#' is exploratory: it has no protected set, rule or terminal state and drops
#' slopes only. A declaration with focal estimands must be a minimal
#' declaration (declarations.md).
#'
#' The design section of the plan, which the design-plan hash covers, holds
#' every IR with each 'mean' centring as its rule and significant digits, as
#' before the data are seen, since a plan is a document to share
#' (documents.md, inputs). The counts of the ceiling are those that a
#' shareable audit of the ceiling writes, a count that the privacy filter
#' suppresses written as `{"below": k}` or `{"suppressed": detail}`.
#'
#' @inheritParams audit
#' @param data A data frame or the path of a CSV file. It must hold the
#'   columns that the formula reads, but the outcome is never read, so a plan
#'   made before the data are collected can use a column of missing values.
#' @param rule The stopping rule: 'localised_backoff', the default,
#'   'protected_lrt', with alpha 0.2, or 'no_reduction'.
#' @param terminal The terminal state for when the protected rung fails:
#'   'no_confirmatory_model' or 'cluster_robust_cr2', which needs nested
#'   grouping factors.
#' @param outcome_access The highest tier at which the outcome had been read
#'   when the plan is made: 'T0' for a plan made outcome-blind, and 'T1' or
#'   'T2' for one made after outcome inspection, which the plan records.
#' @return The plan, a named list in the form that [read_json_strict()]
#'   returns in the hashable profile, which [validate_plan()] accepts. Write
#'   it with `writeBin(canonical_bytes(plan, "hashable"), path)`.
#' @section Errors: A plan that cannot be built gives an error of class
#'   `mixedcheck_error` with one issue: the errors of [audit()] for its
#'   inputs, the issues of a declaration with focal estimands that is not a
#'   minimal declaration, E7315 for a formula without a random term, E7314
#'   for a focal estimand whose term is not a fixed term, E7316 for a
#'   randomisation unit that is not a grouping factor, E7311 for a protected
#'   term that cannot enter rung 0, E7312 when the declaration protects no
#'   random term, E7313 when identifiability.gram_rank is not available and
#'   E7309 for cluster_robust_cr2 without nested grouping factors.
#' @references Barr, D. J., Levy, R., Scheepers, C., & Tily, H. J. (2013).
#'   Random effects structure for confirmatory hypothesis testing: Keep it
#'   maximal. *Journal of Memory and Language, 68*(3), 255-278.
#'   \doi{10.1016/j.jml.2012.11.001}
#' @family plans
#' @export
#' @examples
#' # Fixture Z05N of the pathology zoo: a slope of a predictor that varies
#' # within pupils.
#' fixture <- pathology_zoo("Z05N")
#' plan <- design_plan(fixture$data, fixture$formula, fixture$declaration)
#' plan$design_plan_hash
#' cat(preregistration_text(plan))
design_plan <- function(data, formula, declaration = NULL, family = NULL, coding = NULL,
                        weights = NULL, sample_columns = NULL, rule = "localised_backoff",
                        terminal = "no_confirmatory_model", outcome_access = "T0") {
  if (!is_string(rule) || !rule %in% names(plan_rule_menu)) {
    stop("'rule' must be 'localised_backoff', 'protected_lrt' or 'no_reduction'.", call. = FALSE)
  }
  if (!is_string(terminal) || !terminal %in% plan_terminal_states) {
    stop("'terminal' must be 'no_confirmatory_model' or 'cluster_robust_cr2'.", call. = FALSE)
  }
  if (!is_string(outcome_access) || !outcome_access %in% tier_names) {
    stop("'outcome_access' must be 'T0', 'T1' or 'T2'.", call. = FALSE)
  }
  arguments <- audit_arguments(data, formula, family, coding, weights, sample_columns,
                               "T0", NULL, FALSE, NULL, "shareable", plan_key)
  if (!is.null(declaration)) {
    declaration <- validate_declaration(declaration)
  }
  focal <- focal_estimands(declaration)
  if (length(focal)) {
    validate_declaration(declaration, minimal = TRUE)
  }
  table <- run_data(data, declaration)$table
  declared_columns_present(declaration, table)
  base <- build_formula_ir(arguments$formula, declaration, table, arguments$coding,
                           arguments$weights, arguments$sample_columns)
  outcome_blind_columns(base, declaration)
  if (!length(base$random)) {
    raise_issue("E7315")
  }
  family_class <- audit_family_class(arguments$family, base, declaration)
  # The coding with every categorical predictor frozen, and the IR of the
  # formula under it, whose fixed part every rung shares.
  coding <- frozen_coding(coding, base)
  base <- build_formula_ir(arguments$formula, declaration, table, coding_input(coding),
                           arguments$weights, arguments$sample_columns)
  setting <- list(declaration = declaration, table = table, family_class = family_class,
                  coding = coding_input(coding), raw_coding = coding,
                  weights = arguments$weights,
                  sample_columns = c(arguments$sample_columns, ceiling_read_columns(base)),
                  fixed_text = formula_fixed_text(arguments$formula),
                  response_text = formula_response_text(base))
  base_run <- plan_run(base, setting)
  within <- varying_within(base_run, declaration)
  # The ceiling, its components and the protected set.
  ceiling_state <- ceiling_state(base, within)
  ceiling_ir <- rung_ir(ceiling_state, setting)
  protected <- if (length(focal)) {
    protected_components(base, declaration, focal, within)
  }
  # Rung 0 and the terms left out of it.
  restricted <- identifiable_state(ceiling_state, setting)
  check_protected_entered(protected, restricted)
  ladder <- ladder_states(restricted$state, protected, setting)
  rung_irs <- lapply(ladder$states, rung_ir, setting = setting)
  design <- list()
  if (!is.null(declaration)) {
    design$declaration_hash <- canonical_hash(declaration, "hashable")
  }
  design$ladder <- if (length(focal)) "protected" else "exploratory"
  design$rungs <- lapply(seq_along(rung_irs), function(i) {
    rung <- list(ir = ir_without_means(rung_irs[[i]]))
    if (i > 1L) {
      rung$step <- ladder$steps[[i]]
    }
    rung
  })
  if (length(focal)) {
    design$protected <- lapply(protected, function(component) {
      list(factor = component$factor, variables = as.list(component$variables),
           reason = component$reason)
    })
    design$rule <- plan_rule_menu[[rule]]
    design$terminal <- list(state = terminal)
    if (terminal == "cluster_robust_cr2") {
      check_nested_factors(rung_irs[[1L]])
    }
  }
  design <- parse_json_bytes(canonical_bytes(design, "hashable"), "hashable")
  design_hash <- canonical_hash(design, "hashable")
  plan <- list(
    plan_version = "0.1.0",
    created = utc_timestamp(run_time()),
    language = "R",
    versions = c(list(package = getNamespaceVersion("mixedcheck")[[1L]]), spec_versions()),
    outcome_access = outcome_access,
    for_preregistration = FALSE
  )
  if (length(focal)) {
    plan$rule_evidence <- "simulated_conditions_only"
  }
  plan$design <- design
  plan$design_plan_hash <- design_hash
  plan$ceiling <- ceiling_section(data, ceiling_state, ceiling_ir, restricted, setting,
                                  arguments)
  plan$verdicts <- lapply(ladder$verdicts, function(verdict) list(value = verdict))
  binding <- lme4_binding(design, design_hash)
  plan$bindings <- if (is.null(binding)) list() else list(binding)
  plan <- parse_json_bytes(canonical_bytes(plan, "hashable"), "hashable")
  validate_plan(plan)
}

# --- Inputs ---------------------------------------------------------------------

# The focal estimands of a declaration that do not count as absent, each with
# its position in /estimands, counted from 1, and the comparison forms of the
# variables of its term.
focal_estimands <- function(declaration) {
  estimands <- declaration[["estimands"]]
  found <- list()
  for (i in seq_along(estimands)) {
    entry <- path_pointer("estimands", i - 1L)
    pointers <- c(entry, paste0(entry, c("/term", "/focal")))
    if (any(vapply(pointers, declaration_inferred, NA, declaration = declaration))) {
      next
    }
    if (isFALSE(estimands[[i]][["focal"]])) {
      next
    }
    found[[length(found) + 1L]] <- list(
      index = i,
      variables = comparison_form(term_variables(estimands[[i]][["term"]]))
    )
  }
  found
}

# The coding argument, as the caller gives it, with frozen set to TRUE for
# every categorical predictor of the IR, since a plan freezes the coding of
# factors before it builds its ladder (02-decisions.md, Q3).
frozen_coding <- function(coding, ir) {
  coding <- coding %||% list()
  keys <- comparison_form(as.character(names(coding)))
  for (name in names(ir$predictors)) {
    if (!identical(ir$predictors[[name]]$kind, "categorical")) {
      next
    }
    k <- match(name, keys)
    if (is.na(k)) {
      coding[[length(coding) + 1L]] <- list(frozen = TRUE)
      names(coding)[length(coding)] <- name
      keys <- c(keys, name)
    } else {
      entry <- coding[[k]]
      entry[["frozen"]] <- TRUE
      coding[[k]] <- entry
    }
  }
  coding
}

# The columns that the ceiling reads other than the response and its trials:
# the predictors, the grouping variables, the offsets and the weights. Every
# rung names them as sample columns (ir.md, Samples).
ceiling_read_columns <- function(ir) {
  unique(c(
    as.character(names(ir$predictors)),
    as.character(unlist(lapply(ir$random, function(term) term$grouping))),
    vapply(ir$offsets, function(o) o$variable, ""),
    ir$weights$variable
  ))
}

# The text of the fixed part and the offsets of a formula, cut from the
# formula between the summands that are not random terms, with their signs,
# so that every rung writes the fixed part as the caller wrote it and its
# terms keep the order of their variables (ir.md, Order of terms and
# variables).
formula_fixed_text <- function(formula) {
  tree <- formula_tree(formula)
  bytes <- charToRaw(enc2utf8(formula))
  summands <- tree$rhs$summands
  starts <- vapply(summands, function(s) s$sign_at %||% s$expr$start, 0L)
  ends <- c(starts[-1L], length(bytes))
  kept <- !vapply(summands, function(s) formula_is_random(s$expr), NA)
  pieces <- vapply(which(kept), function(i) {
    text <- rawToChar(bytes[(starts[i] + 1L):ends[i]])
    Encoding(text) <- "UTF-8"
    trimws(text)
  }, "")
  paste(pieces, collapse = " ")
}

# The response as a formula writes it, or '' for a one-sided formula.
formula_response_text <- function(ir) {
  response <- ir$response
  if (is.null(response)) {
    return("")
  }
  text <- formula_variable_text(response$variable)
  if (identical(response$transform, "log")) paste0("log(", text, ")") else text
}

# --- Runs and verdicts --------------------------------------------------------------

# The run of an IR whose checks a plan reads: the design sample, X and Z.
plan_run <- function(ir, setting) {
  model <- design_model(ir, setting$table, analysis = FALSE)
  if (!length(model$design)) {
    raise_issue("E7007", list(sample = "design"))
  }
  built <- design_build(ir, model, setting$table)
  new_run(setting$declaration, setting$table, ir, setting$family_class, "T0", model, built)
}

# The verdict of identifiability.gram_rank for an IR, or E7313 when the
# check is not available.
identifiability_verdict <- function(ir, setting) {
  run <- plan_run(ir, setting)
  entry <- registry_entries_by_id()[["identifiability.gram_rank"]]
  result <- audit_check_identifiability_gram_rank(run, entry, list(empty_object()))
  if (inherits(result, "mixedcheck_check_unavailable")) {
    raise_issue("E7313", list(parameter = result$detail))
  }
  result[[1L]]$statistics$verdict
}

# Whether each predictor varies within each grouping factor of the run: a
# list by factor of logical vectors named by predictor. A declared level of
# an assignment of the predictor to the unit of the factor decides, and
# otherwise the predictor varies unless it is constant within the levels
# with the parameter agreement of structure.within_between (registry.md,
# Terms).
varying_within <- function(run, declaration) {
  agreement <- agreement_fraction(registry_entries_by_id()[["structure.within_between"]])
  predictors <- as.character(names(run$ir$predictors))
  declared <- declared_levels(declaration)
  found <- lapply(names(run$factors), function(factor) {
    levels <- factor_levels(run, factor)$code
    keys <- factor_keys(run, factor)
    vapply(predictors, function(name) {
      for (level in declared) {
        if (level$column == name && setequal(level$columns, keys)) {
          return(level$level == "within_unit")
        }
      }
      values <- value_codes(run, name, rows = run$design)
      !pooled_constancy(levels, values, agreement)$constant
    }, NA)
  })
  names(found) <- names(run$factors)
  found
}

# The declared levels of the assignments that do not count as absent, each
# with the comparison form of its column and the label columns of its unit.
declared_levels <- function(declaration) {
  assignment <- declaration[["assignment"]]
  found <- list()
  for (element in assignment_elements(declaration)) {
    i <- which(vapply(assignment, function(a) identical(a[["column"]], element$column), NA))[1L]
    level <- assignment[[i]][["level"]]
    if (is.null(level) ||
        declaration_inferred(declaration, path_pointer("assignment", i - 1L, "level"))) {
      next
    }
    found[[length(found) + 1L]] <- list(
      column = comparison_form(element$column), level = level,
      columns = unit_label_columns(declaration, element$unit)
    )
  }
  found
}

# --- The ceiling and the protected set ---------------------------------------------

# The state of a rung: for each grouping factor of the IR, in its order, its
# name, whether it has its random intercept, the names of its slope terms in
# the order of the fixed part, whether they are correlated with each other
# and the intercept, and the names of the categorical variables whose slopes
# are complex random intercepts (1 | g:f).
ceiling_state <- function(ir, within) {
  first <- !duplicated(vapply(ir$random, function(term) term$factor, ""))
  lapply(ir$random[first], function(term) {
    varying <- within[[match(term$factor, names(within))]]
    slopes <- Filter(function(t) {
      variables <- vapply(t$variables, function(v) v$variable, "")
      length(variables) > 0L && all(varying[match(variables, names(varying))])
    }, ir$fixed$terms)
    list(factor = term$factor, intercept = TRUE,
         slopes = vapply(slopes, function(t) t$name, ""),
         slope_variables = lapply(slopes, function(t) vapply(t$variables, function(v) v$variable, "")),
         correlated = TRUE, complex = character(0))
  })
}

# The protected components (02-decisions.md, Q3, and documents.md, The
# design section), in the order of the grouping factors of the IR: the
# random intercept of each factor that is a declared unit, then the slopes
# that focal estimands protect, in the order of the estimands.
protected_components <- function(ir, declaration, focal, within) {
  units <- declared_units(declaration)
  randomised <- randomisation_units(declaration)
  factor_columns <- lapply(within, function(x) NULL)
  first <- !duplicated(vapply(ir$random, function(term) term$factor, ""))
  for (term in ir$random[first]) {
    factor_columns[[match(term$factor, names(within))]] <- unlist(term$grouping)
  }
  unit_of <- function(columns) {
    for (name in names(units)) {
      if (setequal(unit_label_columns(declaration, name), columns)) {
        return(name)
      }
    }
    NULL
  }
  for (unit in randomised) {
    columns <- unit_label_columns(declaration, unit$name)
    if (!any(vapply(factor_columns, function(x) setequal(x, columns), NA))) {
      raise_issue("E7316", pointer = path_pointer("assignment", unit$index - 1L, "unit"))
    }
  }
  fixed_terms <- lapply(ir$fixed$terms, function(t) vapply(t$variables, function(v) v$variable, ""))
  term_names <- vapply(ir$fixed$terms, function(t) t$name, "")
  components <- list()
  add <- function(factor, variables, reason) {
    for (c in components) {
      if (c$factor == factor && setequal(c$variables, variables)) {
        return(invisible())
      }
    }
    components[[length(components) + 1L]] <<- list(factor = factor, variables = variables,
                                                   reason = reason)
  }
  for (factor in names(within)) {
    unit <- unit_of(factor_columns[[match(factor, names(within))]])
    if (!is.null(unit)) {
      add(factor, character(0),
          if (unit %in% vapply(randomised, function(u) u$name, "")) "randomisation_unit"
          else "replication_unit")
    }
  }
  for (estimand in focal) {
    t <- which(vapply(fixed_terms, function(v) setequal(v, estimand$variables), NA))
    if (!length(t)) {
      raise_issue("E7314", pointer = path_pointer("estimands", estimand$index - 1L, "term"))
    }
    variables <- fixed_terms[[t]]
    for (factor in names(within)) {
      varying <- within[[factor]]
      inside <- variables[varying[match(variables, names(varying))]]
      if (!length(inside)) {
        next
      }
      reason <- if (length(inside) < length(variables)) {
        "cross_level_interaction_slope"
      } else if (length(variables) == 1L) {
        "focal_slope"
      } else {
        "focal_interaction_slope"
      }
      slope <- which(vapply(fixed_terms, function(v) setequal(v, inside), NA))
      if (!length(slope)) {
        raise_issue("E7311", list(term = term_name_of(inside), factor = factor,
                                  reason = "the fixed part has no term of its variables"))
      }
      add(factor, fixed_terms[[slope]], reason)
    }
  }
  if (!length(components)) {
    raise_issue("E7312")
  }
  components
}

# The units of the randomised assignments that do not count as absent, by
# name, each with the position of its first assignment, counted from 1,
# other than the declared observation unit, of which each row is one member,
# so that it has no random intercept.
randomisation_units <- function(declaration) {
  assignment <- declaration[["assignment"]]
  observation <- declaration[["observation"]][["unit"]]
  if (!is.null(observation) &&
      any(vapply(c("/observation", "/observation/unit"), declaration_inferred, NA,
                 declaration = declaration))) {
    observation <- NULL
  }
  found <- list()
  for (i in seq_along(assignment)) {
    a <- assignment[[i]]
    entry <- path_pointer("assignment", i - 1L)
    pointers <- c(entry, paste0(entry, c("/unit", "/randomised")))
    if (!isTRUE(a[["randomised"]]) ||
        any(vapply(pointers, declaration_inferred, NA, declaration = declaration)) ||
        is.null(named_member(declared_units(declaration), a[["unit"]])) ||
        identical(a[["unit"]], observation) ||
        a[["unit"]] %in% vapply(found, function(u) u$name, "")) {
      next
    }
    found[[length(found) + 1L]] <- list(name = a[["unit"]], index = i)
  }
  found
}

# --- Rung 0 ---------------------------------------------------------------------------

# Rung 0 (02-decisions.md, Q3): the ceiling restricted to identifiable
# terms. The random intercepts are added one at a time in the order of the
# factors, then the slopes of each factor in turn, and each is kept when the
# model with it is identified. Returns the state, the verdict of rung 0 and
# the random terms left out, each with its factor and its name as a random
# term of its own.
identifiable_state <- function(state, setting) {
  current <- lapply(state, function(s) {
    s$intercept <- FALSE
    s$slopes <- character(0)
    s$slope_variables <- list()
    s
  })
  excluded <- list()
  verdict <- NULL
  identified <- function(candidate) {
    found <- identifiability_verdict(rung_ir(candidate, setting), setting)
    if (found == "not_identified") NULL else found
  }
  for (f in seq_along(state)) {
    candidate <- current
    candidate[[f]]$intercept <- TRUE
    found <- identified(candidate)
    if (is.null(found)) {
      excluded[[length(excluded) + 1L]] <- list(
        factor = state[[f]]$factor,
        term = random_term_name(TRUE, state[[f]]$slopes, state[[f]]$factor)
      )
    } else {
      current <- candidate
      verdict <- found
    }
  }
  for (f in seq_along(state)) {
    if (!current[[f]]$intercept) {
      next
    }
    for (k in seq_along(state[[f]]$slopes)) {
      candidate <- current
      candidate[[f]]$slopes <- c(candidate[[f]]$slopes, state[[f]]$slopes[k])
      candidate[[f]]$slope_variables <- c(candidate[[f]]$slope_variables,
                                          state[[f]]$slope_variables[k])
      found <- identified(candidate)
      if (is.null(found)) {
        excluded[[length(excluded) + 1L]] <- list(
          factor = state[[f]]$factor,
          term = random_term_name(FALSE, state[[f]]$slopes[k], state[[f]]$factor)
        )
      } else {
        current <- candidate
        verdict <- found
      }
    }
  }
  if (is.null(verdict)) {
    raise_issue("E7311", list(term = "1", factor = state[[1L]]$factor,
                              reason = "the design does not identify it"))
  }
  list(state = current, verdict = verdict, excluded = excluded)
}

# E7311 for the first protected component that rung 0 lacks.
check_protected_entered <- function(protected, restricted) {
  for (component in protected) {
    s <- restricted$state[[match(component$factor, vapply(restricted$state, function(x) x$factor, ""))]]
    present <- if (!length(component$variables)) {
      s$intercept
    } else {
      any(vapply(s$slope_variables, function(v) setequal(v, component$variables), NA))
    }
    if (!present) {
      raise_issue("E7311", list(term = if (length(component$variables))
                                  term_name_of(component$variables) else "1",
                                factor = component$factor,
                                reason = "the design does not identify it"))
    }
  }
  invisible()
}

# --- The ladder -------------------------------------------------------------------

# The ladder from rung 0 (02-decisions.md, Q3, and documents.md, The design
# section): the states of its rungs, the step that leads to each rung after
# the first and the verdict of each. Correlations are simplified first, one
# grouping factor at a time: each categorical slope of three or more levels
# becomes complex random intercepts, then the rest of the block becomes
# uncorrelated. The unprotected slopes are then dropped, higher-order terms
# first and, among terms of one order, by factor and from the last term back,
# and last the unprotected random intercepts of factors without slopes. An
# exploratory ladder protects nothing but keeps every random intercept. A
# candidate rung that is not identified is left out and the ladder continues
# from the rung before it.
ladder_states <- function(state, protected, setting) {
  states <- list(state)
  steps <- list(NULL)
  verdicts <- c(identifiability_verdict(rung_ir(state, setting), setting))
  try_step <- function(candidate, step) {
    verdict <- identifiability_verdict(rung_ir(candidate, setting), setting)
    if (verdict == "not_identified") {
      return(FALSE)
    }
    states[[length(states) + 1L]] <<- candidate
    steps[[length(steps) + 1L]] <<- step
    verdicts <<- c(verdicts, verdict)
    TRUE
  }
  predictors <- rung_ir(state, setting)$predictors
  levels_of <- function(variables) {
    if (length(variables) != 1L) {
      return(0L)
    }
    info <- named_member(predictors, variables)
    if (identical(info$kind, "categorical")) length(info$levels) else 0L
  }
  for (f in seq_along(state)) {
    for (slope in state[[f]]$slopes) {
      current <- states[[length(states)]]
      k <- match(slope, current[[f]]$slopes)
      if (is.na(k) || levels_of(current[[f]]$slope_variables[[k]]) < 3L) {
        next
      }
      candidate <- current
      candidate[[f]]$slopes <- current[[f]]$slopes[-k]
      candidate[[f]]$slope_variables <- current[[f]]$slope_variables[-k]
      candidate[[f]]$complex <- c(current[[f]]$complex, slope)
      try_step(candidate, list(kind = "complex_intercepts", factor = current[[f]]$factor,
                               terms = list(block_name(current[[f]]))))
    }
    current <- states[[length(states)]]
    s <- current[[f]]
    if (s$correlated && block_columns(s, predictors) >= 2L) {
      candidate <- current
      candidate[[f]]$correlated <- FALSE
      try_step(candidate, list(kind = "decorrelate", factor = s$factor,
                               terms = list(block_name(s))))
    }
  }
  # Variances, in the order of the drops.
  protects <- function(factor, variables) {
    any(vapply(protected, function(c) c$factor == factor && setequal(c$variables, variables), NA))
  }
  repeat {
    current <- states[[length(states)]]
    drops <- droppable(current, protected, protects, exploratory = is.null(protected))
    done <- TRUE
    for (drop in drops) {
      candidate <- current
      step <- apply_drop(candidate, drop, rung_ir(current, setting))
      if (try_step(step$state, step$step)) {
        done <- FALSE
        break
      }
    }
    if (done) {
      break
    }
  }
  list(states = states, steps = steps, verdicts = verdicts)
}

# The number of columns of the correlated block of a factor: one for the
# intercept, one for each numeric slope and one for each contrast column.
block_columns <- function(s, predictors) {
  count <- as.integer(s$intercept)
  for (variables in s$slope_variables) {
    width <- 1L
    for (v in variables) {
      info <- named_member(predictors, v)
      if (identical(info$kind, "categorical")) {
        width <- width * (length(info$levels) - 1L)
      }
    }
    count <- count + width
  }
  count
}

# The name of the block of a factor as one random term, as ir.md names it.
block_name <- function(s) {
  random_term_name(s$intercept, s$slopes, s$factor)
}

# The drops that a state allows, in the order in which the ladder tries
# them: unprotected slopes and complex random intercepts, by order of term,
# highest first, then by factor and from the last term back, and then the
# unprotected random intercepts of factors with nothing else left, by
# factor. An exploratory ladder keeps every random intercept.
droppable <- function(state, protected, protects, exploratory) {
  candidates <- list()
  for (f in seq_along(state)) {
    s <- state[[f]]
    for (k in rev(seq_along(s$slopes))) {
      if (!protects(s$factor, s$slope_variables[[k]])) {
        candidates[[length(candidates) + 1L]] <- list(
          kind = "slope", f = f, k = k, order = length(s$slope_variables[[k]]))
      }
    }
    for (k in rev(seq_along(s$complex))) {
      variable <- complex_variable(s, k)
      if (!protects(s$factor, variable)) {
        candidates[[length(candidates) + 1L]] <- list(kind = "complex", f = f, k = k, order = 1L)
      }
    }
  }
  if (length(candidates)) {
    order <- order(-vapply(candidates, function(c) c$order, 0L), method = "radix")
    candidates <- candidates[order]
  }
  if (!exploratory) {
    for (f in seq_along(state)) {
      s <- state[[f]]
      if (s$intercept && !length(s$slopes) && !length(s$complex) &&
          !protects(s$factor, character(0))) {
        candidates[[length(candidates) + 1L]] <- list(kind = "intercept", f = f, k = 0L, order = 0L)
      }
    }
  }
  candidates
}

# The variable of the k-th complex random intercept of a factor.
complex_variable <- function(s, k) {
  term_variables(s$complex[k])
}

# Applies a drop to a state: the new state and the step, which names the
# random terms of the rung before that the drop removes.
apply_drop <- function(state, drop, ir) {
  s <- state[[drop$f]]
  random_names <- vapply(ir$random, function(t) t$name, "")
  random_factors <- vapply(ir$random, function(t) t$factor, "")
  if (drop$kind == "slope") {
    variables <- s$slope_variables[[drop$k]]
    if (s$correlated) {
      factor <- s$factor
      terms <- block_name(s)
    } else {
      # The uncorrelated terms of the slope: one, or one for each column of
      # a frozen factor that '||' has split.
      factor <- s$factor
      terms <- random_names[random_factors == factor & vapply(ir$random, function(t) {
        length(t$terms) == 1L && !random_term_has_intercept(t) &&
          setequal(vapply(t$terms[[1L]]$variables, function(v) v$variable, ""), variables)
      }, NA)]
    }
    s$slopes <- s$slopes[-drop$k]
    s$slope_variables <- s$slope_variables[-drop$k]
  } else if (drop$kind == "complex") {
    factor <- complex_factor(s, drop$k)
    terms <- paste0("1 | ", factor)
    s$complex <- s$complex[-drop$k]
  } else {
    factor <- s$factor
    terms <- paste0("1 | ", factor)
    s$intercept <- FALSE
  }
  state[[drop$f]] <- s
  list(state = state, step = list(kind = "drop_terms", factor = factor, terms = as.list(terms)))
}

# The name of the grouping factor of the k-th complex random intercept of a
# factor, its variables followed by the categorical variable.
complex_factor <- function(s, k) {
  paste0(s$factor, ":", s$complex[k])
}

# --- IRs of rungs -------------------------------------------------------------------

# The formula of a state: the response, the fixed part as the caller wrote
# it and, for each grouping factor, its block, written with '||' once it is
# uncorrelated, and its complex random intercepts.
rung_formula <- function(state, setting) {
  random <- character(0)
  for (s in state) {
    parts <- s$slopes
    if (s$intercept || length(parts)) {
      lhs <- paste(c(if (s$intercept) "1" else "0", parts), collapse = " + ")
      bar <- if (!s$correlated && length(parts)) " || " else " | "
      random <- c(random, paste0("(", lhs, bar, s$factor, ")"))
    }
    for (k in seq_along(s$complex)) {
      random <- c(random, paste0("(1 | ", complex_factor(s, k), ")"))
    }
  }
  rhs <- paste(c(if (nzchar(setting$fixed_text)) setting$fixed_text, random), collapse = " + ")
  paste(setting$response_text, "~", rhs)
}

# The IR of a state, built from its formula with the frozen coding and the
# sample columns of the ceiling.
rung_ir <- function(state, setting) {
  build_formula_ir(rung_formula(state, setting), setting$declaration, setting$table,
                   setting$coding, setting$weights, setting$sample_columns)
}

# E7309 when rung 0 has no grouping factor whose columns every other
# grouping factor includes.
check_nested_factors <- function(ir) {
  groupings <- lapply(ir$random, function(term) unlist(term$grouping))
  nested <- any(vapply(groupings, function(outer) {
    all(vapply(groupings, function(g) all(outer %in% g), NA))
  }, NA))
  if (!nested) {
    raise_issue("E7309", pointer = "/design/terminal/state")
  }
  invisible()
}

# --- The ceiling section ---------------------------------------------------------------

# The ceiling of the plan (documents.md, Ceiling, verdicts and counts): its
# IR, its verdict, the random terms left out of rung 0 and, for each
# grouping factor, the counts that a shareable audit of the ceiling writes.
ceiling_section <- function(data, state, ir, restricted, setting, arguments) {
  verdict <- identifiability_verdict(ir, setting)
  results <- audit(data, rung_formula(state, setting), setting$declaration,
                   family = arguments$family, coding = setting$raw_coding,
                   weights = arguments$weights, sample_columns = setting$sample_columns,
                   key = plan_key)
  findings <- results$document$findings
  find <- function(check, scope) {
    for (finding in findings) {
      if (identical(finding$check, check) && identical(finding$scope[names(scope)], scope)) {
        return(finding)
      }
    }
    internal_error(sprintf("the audit of the ceiling has no finding of %s.", check))
  }
  min_count <- read_registry()[["privacy"]][["min_count"]]
  factors <- lapply(ir$random, function(term) {
    budget <- find("identifiability.df_budget", list(factor = term$factor))
    dimension <- find("identifiability.levels_vs_dimension",
                      list(factor = term$factor, term = term$name))
    list(
      factor = term$factor,
      levels = plan_count(budget, "levels", min_count),
      df_budget = plan_count(budget, "budget", min_count),
      terms = list(list(term = term$name,
                        informative_groups = plan_count(dimension, "informative_levels",
                                                        min_count)))
    )
  })
  section <- list(ir = ir_without_means(ir), verdict = list(value = verdict), factors = factors)
  if (length(restricted$excluded)) {
    section$excluded <- restricted$excluded
  }
  section
}

# A count of a shareable finding as a plan writes it: the value, {"below": k}
# for a person count that the filter suppressed below k, and
# {"suppressed": detail} for one that it suppressed by another rule or with
# the whole finding.
plan_count <- function(finding, name, min_count) {
  statistic <- finding$statistics[[name]]
  if (!is.null(statistic) && !is.null(statistic$value)) {
    return(statistic$value)
  }
  detail <- if (is.null(statistic)) {
    finding$status$availability$detail
  } else {
    statistic$availability$detail
  }
  if (identical(detail, "min_count") && !is.null(statistic)) {
    return(list(below = min_count))
  }
  if (identical(detail, "min_count")) {
    detail <- "min_count_rule"
  }
  if (!detail %in% c("dominance", "min_count_rule", "secondary")) {
    detail <- "secondary"
  }
  list(suppressed = detail)
}

# --- The execution binding ---------------------------------------------------------------

# The execution binding of the plan for lme4 (documents.md, Execution
# bindings), when lme4 is installed: its version, the optimisers in order of
# use, the second serving as the restart, and the formula of each rung over
# columns named as the IR names the columns of X, which hold the values of X,
# so that frozen factors and centred predictors enter as the plan codes them.
lme4_binding <- function(design, design_hash) {
  if (!package_installed("lme4")) {
    return(NULL)
  }
  binding <- list(
    design_plan_hash = design_hash,
    language = "R",
    engine = list(name = "lme4", version = utils::packageDescription("lme4")[["Version"]]),
    optimisers = list(list(name = "nloptwrap", settings = empty_object()),
                      list(name = "Nelder_Mead", settings = empty_object())),
    rungs = lapply(design$rungs, function(rung) {
      list(availability = list(value = "available"), encoding = lme4_encoding(rung$ir))
    })
  )
  binding <- parse_json_bytes(canonical_bytes(binding, "hashable"), "hashable")
  list(binding = binding, hash = canonical_hash(binding, "hashable"))
}

# The lme4 formula of an IR over columns named as its columns: the response,
# the columns of X, the offsets and each random term with its columns.
lme4_encoding <- function(ir) {
  quote <- function(name) {
    if (identical(name, "(Intercept)")) "1" else paste0("`", name, "`")
  }
  columns <- vapply(ir$fixed$columns, function(c) c$name, "")
  fixed <- if (length(columns) && columns[1L] == "(Intercept)") {
    c("1", vapply(columns[-1L], quote, ""))
  } else {
    c("0", vapply(columns, quote, ""))
  }
  offsets <- vapply(ir$offsets, function(o) {
    column <- paste0("`", o$variable, "`")
    paste0("offset(", if (o$transform == "log") paste0("log(", column, ")") else column, ")")
  }, "")
  random <- vapply(ir$random, function(term) {
    columns <- vapply(term$columns, function(c) c$name, "")
    lhs <- if (length(columns) && columns[1L] == "(Intercept)") {
      c("1", vapply(columns[-1L], quote, ""))
    } else {
      c("0", vapply(columns, quote, ""))
    }
    grouping <- paste(paste0("`", unlist(term$grouping), "`"), collapse = ":")
    paste0("(", paste(lhs, collapse = " + "), " | ", grouping, ")")
  }, "")
  response <- ir$response
  lhs <- if (is.null(response)) "" else {
    column <- paste0("`", response$variable, "`")
    if (response$transform == "log") paste0("log(", column, ") ") else paste0(column, " ")
  }
  paste0(lhs, "~ ", paste(c(fixed, offsets, random), collapse = " + "))
}
