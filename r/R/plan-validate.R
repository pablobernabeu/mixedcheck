# The validator of plans (docs/spec/documents.md, Plan, Validation) and the
# rule of ir.md (The IR document, Validation) that it applies to every IR.

#' Validate a plan
#'
#' Validates a plan in the four stages of the plan specification and stops
#' after the first stage that finds a problem: reading in the hashable
#' profile, the version at `/plan_version`, the structure against the plan
#' schema, with the IR schema for every IR, and the rules in code: the
#' recorded hashes, the rungs and verdicts of the design and its bindings, the
#' protected set in every rung, a terminal state that this package can run
#' and that suits the design, the unique grouping factors of the ceiling and
#' the rule of ir.md for every IR.
#'
#' @param plan A plan: the path of a file or the value that
#'   [read_json_strict()] returns, as [design_plan()] returns it.
#' @return The plan, invisibly: the value read from a file, or the plan
#'   given in memory.
#' @section Errors: A plan that is not valid gives an error of class
#'   `mixedcheck_error`, whose element `issues` lists the problems of the
#'   first stage that finds any, as [validate_results()] reports them: one
#'   from reading, E1441 for the version, the structural issues, or the
#'   issues of the rules in code, E1321, E6101 and E7301 to E7309, sorted by
#'   pointer, code and message and capped at 100.
#' @family plans
#' @export
#' @examples
#' fixture <- pathology_zoo("Z05N")
#' plan <- design_plan(fixture$data, fixture$formula, fixture$declaration)
#' validate_plan(plan)
#'
#' # A plan whose design was edited after its hash was recorded.
#' plan$design$rule$parameters <- list(alpha = "0.05")
#' problem <- tryCatch(validate_plan(plan), mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
validate_plan <- function(plan) {
  if (!is_string(plan) && !is_plain_list(plan)) {
    stop("'plan' must be a file path or a value that read_json_strict() returns.",
         call. = FALSE)
  }
  bytes <- if (is.character(plan)) {
    read_input_bytes(plan)
  } else {
    canonical_bytes(mark_input_strings(plan), "hashable")
  }
  value <- parse_json_bytes(bytes, "hashable")
  issues <- plan_issues(value)
  if (length(issues)) {
    signal_issues(issues)
  }
  invisible(if (is.character(plan)) value else plan)
}

# The supported line of plans.
plan_version_pattern <- "^0\\.1\\.(0|[1-9][0-9]*)\\z"

# Stages 2 to 4 on a plan read in stage 1.
plan_issues <- function(value) {
  version <- if (is_json_object(value)) value[["plan_version"]]
  if (is.character(version) && !version_supported(version, plan_version_pattern)) {
    return(list(new_issue("E1441", list(version = version, supported = "0.1.x"),
                          pointer = "/plan_version")))
  }
  for (stage in list(function(p) schema_issues(p, "urn:mixedcheck:schema:plan"),
                     plan_rule_issues)) {
    raw <- stage(value)
    if (length(raw)) {
      return(finish_issues(raw))
    }
  }
  list()
}

# Stage 4: the rules in code on a plan whose structure is valid.
plan_rule_issues <- function(p) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  design <- p[["design"]]
  rungs <- design[["rungs"]]
  if (!identical(canonical_hash(design, "hashable"), p[["design_plan_hash"]])) {
    add("E1321", "/design_plan_hash")
  }
  for (i in seq_along(p[["bindings"]])) {
    entry <- p[["bindings"]][[i]]
    here <- path_pointer("bindings", i - 1L)
    if (!identical(canonical_hash(entry[["binding"]], "hashable"), entry[["hash"]])) {
      add("E1321", paste0(here, "/hash"))
    }
    if (length(entry[["binding"]][["rungs"]]) != length(rungs)) {
      add("E7301", paste0(here, "/binding/rungs"))
    }
    if (!identical(entry[["binding"]][["design_plan_hash"]], p[["design_plan_hash"]])) {
      add("E7302", paste0(here, "/binding/design_plan_hash"))
    }
  }
  if (length(p[["verdicts"]]) != length(rungs)) {
    add("E7303", "/verdicts")
  }
  for (i in seq_along(p[["verdicts"]])) {
    if (identical(p[["verdicts"]][[i]][["value"]], "not_identified")) {
      add("E7304", path_pointer("verdicts", i - 1L))
    }
  }
  protected <- design[["protected"]]
  for (i in seq_along(protected)) {
    here <- path_pointer("design", "protected", i - 1L)
    component <- protected[[i]]
    variables <- comparison_form(as.character(unlist(component[["variables"]])))
    for (j in seq_len(i - 1L)) {
      earlier <- protected[[j]]
      if (identical(comparison_form(earlier[["factor"]]), comparison_form(component[["factor"]])) &&
          setequal(comparison_form(as.character(unlist(earlier[["variables"]]))), variables)) {
        add("E7305", here)
        break
      }
    }
    for (r in seq_along(rungs)) {
      if (!component_in_rung(component, rungs[[r]][["ir"]])) {
        add("E7306", here, list(rung = r - 1L))
      }
    }
  }
  terminal <- design[["terminal"]][["state"]]
  if (identical(terminal, "cluster_robust_cr2") && !factors_nested(rungs[[1L]][["ir"]])) {
    add("E7309", "/design/terminal/state")
  }
  factors <- comparison_form(vapply(p[["ceiling"]][["factors"]], function(f) f[["factor"]], ""))
  for (i in which(duplicated(factors))) {
    add("E7308", path_pointer("ceiling", "factors", i - 1L, "factor"))
  }
  irs <- c(list(list(ir = p[["ceiling"]][["ir"]], pointer = "/ceiling/ir")),
           lapply(seq_along(rungs), function(r) {
             list(ir = rungs[[r]][["ir"]], pointer = path_pointer("design", "rungs", r - 1L, "ir"))
           }))
  for (item in irs) {
    pointer <- ir_rule_pointer(item$ir)
    if (!is.null(pointer)) {
      add("E6101", paste0(item$pointer, pointer))
    }
  }
  issues
}

# Whether a rung holds a protected component (documents.md, E7306): a random
# term of its grouping factor with a term whose set of variables is the
# component's, or the intercept for an empty list, or, for one categorical
# variable f, the random intercept of the factor joined with f, which
# complex random intercepts give.
component_in_rung <- function(component, ir) {
  factor <- comparison_form(component[["factor"]])
  variables <- comparison_form(as.character(unlist(component[["variables"]])))
  for (term in ir[["random"]]) {
    grouping <- comparison_form(as.character(unlist(term[["grouping"]])))
    if (identical(comparison_form(term[["factor"]]), factor)) {
      for (t in term[["terms"]]) {
        found <- comparison_form(vapply(t[["variables"]], function(v) v[["variable"]], ""))
        if (setequal(found, variables) && length(found) == length(variables)) {
          return(TRUE)
        }
      }
    }
    if (length(variables) == 1L &&
        identical(named_member(ir[["predictors"]], variables)[["kind"]], "categorical") &&
        random_term_has_intercept(term) && length(grouping) >= 2L &&
        identical(grouping[length(grouping)], variables) &&
        identical(paste(formula_variable_text(grouping[-length(grouping)]), collapse = ":"),
                  factor)) {
      return(TRUE)
    }
  }
  FALSE
}

# Whether one grouping factor of an IR has columns that every other grouping
# factor includes (documents.md, E7309).
factors_nested <- function(ir) {
  groupings <- lapply(ir[["random"]], function(term) {
    comparison_form(as.character(unlist(term[["grouping"]])))
  })
  any(vapply(groupings, function(outer) {
    all(vapply(groupings, function(g) all(outer %in% g), NA))
  }, NA))
}

# --- The rule of ir.md for an IR document -------------------------------------------

# The JSON Pointer, within the IR, of the first member in the order of the
# canonical serialisation that differs from what the rules of ir.md give, or
# NULL for an IR that follows them (ir.md, The IR document, Validation).
ir_rule_pointer <- function(ir) {
  found <- character(0)
  flag <- function(pointer) found <<- c(found, pointer)
  predictors <- list()
  for (name in names(ir[["predictors"]])) {
    entry <- ir[["predictors"]][[name]]
    info <- list(kind = entry[["kind"]], frozen = isTRUE(entry[["frozen"]]))
    if (identical(entry[["kind"]], "categorical")) {
      info$levels <- entry[["levels"]]
      info$reference <- level_position(entry[["reference"]], entry[["levels"]])
      if (is.na(info$reference)) {
        flag(path_pointer("predictors", name, "reference"))
        info$reference <- 1L
      }
    }
    named_member(predictors, name) <- info
  }
  expected <- ir
  # The variables of the terms of a part, which must be predictors.
  part_terms <- function(terms, pointer) {
    intercept <- length(terms) > 0L && !length(terms[[1L]][["variables"]])
    variable_sets <- list()
    for (i in seq_along(terms)) {
      variables <- vapply(terms[[i]][["variables"]], function(v) v[["variable"]], "")
      for (j in seq_along(variables)) {
        if (is.null(named_member(predictors, variables[j]))) {
          flag(path_pointer_from(pointer, i - 1L, "variables", j - 1L, "variable"))
        }
      }
      if (i > 1L || !intercept) {
        variable_sets[[length(variable_sets) + 1L]] <- variables
      }
    }
    keys <- vapply(variable_sets, term_key, "")
    for (k in which(duplicated(keys))) {
      flag(path_pointer_from(pointer, k - 1L + intercept))
    }
    list(intercept = intercept, terms = variable_sets)
  }
  if (length(found)) {
    return(earliest_pointer(found))
  }
  fixed <- part_terms(ir[["fixed"]][["terms"]], "/fixed/terms")
  if (length(found)) {
    return(earliest_pointer(found))
  }
  expected$fixed <- ir_part_document(part_columns(fixed$intercept, fixed$terms, predictors))
  identities <- character(0)
  columns_of <- list()
  for (r in seq_along(ir[["random"]])) {
    term <- ir[["random"]][[r]]
    here <- path_pointer("random", r - 1L)
    parts <- part_terms(term[["terms"]], paste0(here, "/terms"))
    if (length(found)) {
      break
    }
    part <- part_columns(parts$intercept, parts$terms, predictors)
    carried <- lapply(term[["terms"]], function(t) {
      lapply(t[["variables"]], function(v) v[["level"]])
    })
    split <- any(vapply(carried, function(x) any(!vapply(x, is.null, NA)), NA))
    if (split) {
      # Levels are carried only in a random term with one term and no
      # intercept, only by frozen predictors and only for a level of a
      # column of that term.
      t <- term[["terms"]][[length(term[["terms"]])]]
      levels <- list()
      for (j in seq_along(t[["variables"]])) {
        v <- t[["variables"]][[j]]
        if (!is.null(v[["level"]])) {
          named_member(levels, v[["variable"]]) <- v[["level"]]
        }
      }
      chosen <- which(vapply(part$columns, function(column) {
        length(column$levels) == length(levels) &&
          all(vapply(names(levels), function(name) {
            json_equal(named_member(column$levels, name), named_member(levels, name))
          }, NA))
      }, NA))
      valid <- !parts$intercept && length(parts$terms) == 1L && length(chosen) == 1L &&
        all(vapply(names(levels), function(name) named_member(predictors, name)$frozen, NA))
      if (!valid) {
        first_level <- which(!vapply(carried[[length(carried)]], is.null, NA))[1L]
        flag(paste0(here, "/terms/", length(term[["terms"]]) - 1L, "/variables/",
                    first_level - 1L, "/level"))
        break
      }
      column <- part$columns[[chosen]]
      part$columns <- list(column)
      part$labels <- list(column$level_labels)
      part$levels <- list(column$levels)
    }
    document <- ir_part_document(part)
    grouping <- as.character(unlist(term[["grouping"]]))
    factor <- paste(formula_variable_text(grouping), collapse = ":")
    names_here <- vapply(document$terms, function(t) t$name, "")
    if (parts$intercept) {
      names_here <- names_here[-1L]
    }
    expected$random[[r]] <- c(
      list(name = random_term_name(parts$intercept, names_here, factor), factor = factor,
           grouping = term[["grouping"]], covariance = "unstructured"),
      document
    )
    identity <- paste(factor, parts$intercept,
                      paste(sort(names_here, method = "radix"), collapse = "\002"), sep = "\003")
    if (identity %in% identities) {
      flag(here)
    }
    identities <- c(identities, identity)
    column_names <- vapply(document$columns, function(c) c$name, "")
    shared <- intersect(column_names, named_member(columns_of, factor))
    if (length(shared)) {
      flag(paste0(here, "/columns/", match(shared[1L], column_names) - 1L, "/name"))
    }
    named_member(columns_of, factor) <- c(named_member(columns_of, factor), column_names)
  }
  offsets <- ir[["offsets"]]
  if (length(offsets)) {
    order <- order(comparison_form(vapply(offsets, function(o) o[["variable"]], "")),
                   vapply(offsets, function(o) o[["transform"]], ""), method = "radix")
    expected$offsets <- offsets[order]
  }
  sample <- as.character(unlist(ir[["sample_columns"]]))
  if (length(sample)) {
    read <- comparison_form(c(
      names(ir[["predictors"]]),
      unlist(lapply(ir[["random"]], function(term) term[["grouping"]])),
      vapply(offsets, function(o) o[["variable"]], ""),
      ir[["weights"]][["variable"]], ir[["response"]][["variable"]], ir[["response"]][["trials"]]
    ))
    kept <- sample[!comparison_form(sample) %in% read]
    expected$sample_columns <- as.list(kept[order(comparison_form(kept), method = "radix")])
  }
  difference <- json_first_difference(ir, expected, "")
  earliest_pointer(c(found, difference))
}

# A JSON Pointer that extends a pointer by tokens.
path_pointer_from <- function(pointer, ...) {
  paste0(pointer, path_pointer(...))
}

# The pointer of the first member, in the order of the canonical
# serialisation, at which two JSON values differ, or NULL.
json_first_difference <- function(a, b, pointer) {
  if (is_json_object(a) && is_json_object(b)) {
    keys <- sort(unique(c(names(a), names(b))), method = "radix")
    for (key in keys) {
      here <- paste0(pointer, path_pointer(key))
      if (is.na(match(key, names(a))) || is.na(match(key, names(b)))) {
        return(here)
      }
      found <- json_first_difference(named_member(a, key), named_member(b, key), here)
      if (!is.null(found)) {
        return(found)
      }
    }
    return(NULL)
  }
  if (is_json_array(a) && is_json_array(b) && !is_json_object(a) && !is_json_object(b)) {
    for (i in seq_len(max(length(a), length(b)))) {
      here <- paste0(pointer, "/", i - 1L)
      if (i > length(a) || i > length(b)) {
        return(here)
      }
      found <- json_first_difference(a[[i]], b[[i]], here)
      if (!is.null(found)) {
        return(found)
      }
    }
    return(NULL)
  }
  if (json_equal(a, b)) NULL else pointer
}

# The earliest of some JSON Pointers in the order of the canonical
# serialisation: token by token, array indices by value and keys by code
# point, with a pointer before every pointer that extends it.
earliest_pointer <- function(pointers) {
  if (!length(pointers)) {
    return(NULL)
  }
  best <- pointers[1L]
  for (p in pointers[-1L]) {
    if (pointer_before(p, best)) {
      best <- p
    }
  }
  best
}

pointer_before <- function(p, q) {
  tokens <- function(x) if (identical(x, "")) character(0) else strsplit(substring(x, 2L), "/", fixed = TRUE)[[1L]]
  a <- tokens(p)
  b <- tokens(q)
  for (j in seq_len(min(length(a), length(b)))) {
    if (a[j] != b[j]) {
      numeric <- grepl("^[0-9]+$", a[j]) && grepl("^[0-9]+$", b[j])
      if (numeric) {
        return(as.numeric(a[j]) < as.numeric(b[j]))
      }
      x <- gsub("~0", "~", gsub("~1", "/", a[j], fixed = TRUE), fixed = TRUE)
      y <- gsub("~0", "~", gsub("~1", "/", b[j], fixed = TRUE), fixed = TRUE)
      return(identical(order(c(x, y), method = "radix"), 1:2))
    }
  }
  length(a) < length(b)
}
