# The preregistration text of a plan (02-decisions.md, Q3) and the formula
# of an IR, which both packages write identically from the plan alone.

#' Write the preregistration text of a plan
#'
#' Writes the text that states a plan in words: its hashes, the outcome
#' access when it was frozen, the ceiling with its counts, every rung of the
#' ladder with the step that leads to it, the protected set, the stopping rule
#' and the terminal state. Both packages write the same text for the same
#' plan. Plans written by 0.x releases are not for preregistration, and the
#' text says so.
#'
#' @param plan A plan, as [validate_plan()] accepts it.
#' @return The text, a character string of lines that each end with a line
#'   feed.
#' @section Errors: The errors of [validate_plan()].
#' @family plans
#' @export
#' @examples
#' fixture <- pathology_zoo("Z05N")
#' plan <- design_plan(fixture$data, fixture$formula, fixture$declaration)
#' cat(preregistration_text(plan))
preregistration_text <- function(plan) {
  plan <- validate_plan(plan)
  plan <- parse_json_bytes(canonical_bytes(mark_input_strings(plan), "hashable"), "hashable")
  design <- plan$design
  rungs <- design$rungs
  quote <- function(x) paste0("'", x, "'")
  join <- function(items) {
    if (length(items) <= 1L) {
      return(paste(items, collapse = ""))
    }
    paste(paste(items[-length(items)], collapse = ", "), "and", items[length(items)])
  }
  # A count with its noun: the number, 'fewer than k' or, for a count that
  # the privacy filter suppressed by another rule, a number it withholds.
  count <- function(value, noun) {
    if (is.list(value) && !is.null(value$below)) {
      paste("fewer than", format_integer(value$below), noun)
    } else if (is.list(value)) {
      paste0("a number of ", noun, " that the privacy filter withholds (", value$suppressed, ")")
    } else {
      paste(format_integer(value), noun)
    }
  }
  lines <- c(
    "Analysis plan",
    "",
    paste0("Design-plan hash: ", plan$design_plan_hash),
    paste0("Plan version ", plan$plan_version, ", written by mixedcheck ",
           plan$versions$package, " (", plan$language, ") with registry ",
           plan$versions$registry, ", schemas ", plan$versions$schemas, " and canonicaliser ",
           plan$versions$canonicaliser, "."),
    paste("This plan is not for preregistration: plans written by 0.x releases are not,",
          "until the plan schema and the canonicaliser carry versions that later releases",
          "can verify."),
    if (plan$outcome_access == "T0") {
      "The plan was frozen without reading the outcome (T0)."
    } else {
      paste0("The plan was frozen after the outcome had been read at ", plan$outcome_access,
             ", so it was planned after outcome inspection.")
    },
    if (is.null(design$declaration_hash)) {
      "The plan was built without a declaration."
    } else {
      paste0("Declaration hash: ", design$declaration_hash)
    },
    "",
    "Ceiling",
    "",
    paste0("The design-implied ceiling is ", ir_formula(plan$ceiling$ir),
           ", and its identifiability verdict is ", plan$ceiling$verdict$value, ".")
  )
  for (factor in plan$ceiling$factors) {
    groups <- vapply(factor$terms, function(t) {
      paste(count(t$informative_groups, "informative groups"), "behind", quote(t$term))
    }, "")
    lines <- c(lines, paste0("Grouping factor ", quote(factor$factor), ": ",
                             count(factor$levels, "levels"), ", ",
                             count(factor$df_budget, "degrees of freedom between levels"),
                             " and ", join(groups), "."))
  }
  if (length(plan$ceiling$excluded)) {
    lines <- c(lines, paste0("Left out of rung 0 as not identifiable: ",
                             join(vapply(plan$ceiling$excluded, function(e) quote(e$term), "")),
                             "."))
  }
  lines <- c(lines, "", paste0("Ladder (", design$ladder, ")"), "")
  for (r in seq_along(rungs)) {
    rung <- rungs[[r]]
    head <- paste0("Rung ", r - 1L)
    if (!is.null(rung$step)) {
      terms <- join(vapply(rung$step$terms, quote, ""))
      head <- paste0(head, ", ", switch(rung$step$kind,
        decorrelate = paste("decorrelating", terms),
        complex_intercepts = paste("replacing", terms, "by complex random intercepts, which",
                                   "restrict the correlations between its levels to be",
                                   "non-negative"),
        drop_terms = paste("dropping", terms)
      ))
    }
    lines <- c(lines, paste0(head, ": ", ir_formula(rung$ir), " (", plan$verdicts[[r]]$value, ")."))
  }
  if (identical(design$ladder, "protected")) {
    reasons <- c(replication_unit = "replication unit", randomisation_unit = "randomisation unit",
                 focal_slope = "focal slope", focal_interaction_slope = "focal interaction slope",
                 cross_level_interaction_slope = "cross-level interaction slope")
    components <- vapply(design$protected, function(c) {
      what <- if (!length(c$variables)) {
        "the random intercept"
      } else {
        paste("the slope of", quote(term_name_of(unlist(c$variables))))
      }
      paste0(what, " by ", quote(c$factor), " (", reasons[[c$reason]], ")")
    }, "")
    rule <- design$rule
    parameters <- vapply(names(rule$parameters), function(name) {
      paste(name, rule$parameters[[name]])
    }, "")
    terminal <- switch(design$terminal$state,
      no_confirmatory_model = "no confirmatory model, which reports the failure",
      cluster_robust_cr2 = "CR2 cluster-robust inference, which is engine-specific"
    )
    lines <- c(lines,
      paste0("The ladder never removes the protected set: ", join(components), "."),
      paste0("Rung ", length(rungs) - 1L, " is the protected rung."),
      "",
      "Stopping rule and terminal state",
      "",
      paste0("The confirmatory model is the rung that the stopping rule ", rule$id, ", version ",
             format_integer(rule$version),
             if (length(parameters)) paste0(" with ", join(parameters)) else "",
             ", selects from this ladder."),
      paste("The operating characteristics of the rule are known only for simulated",
            "conditions until study H1 has run."),
      paste0("If the protected rung fails, the analysis ends in the terminal state ",
             terminal, "."),
      paste("The selected rung is reported with the protected rung and the adjacent rung",
            "as pre-declared sensitivity analyses.")
    )
  } else {
    lines <- c(lines,
      "",
      paste("Without a focal estimand, the protected set cannot be defined, so the ladder",
            "is exploratory and no stopping rule is executed.")
    )
  }
  if (length(plan$bindings)) {
    lines <- c(lines, "", "Execution bindings", "")
    for (entry in plan$bindings) {
      binding <- entry$binding
      lines <- c(lines, paste0(binding$engine$name, " ", binding$engine$version, " (",
                               binding$language, "): ", entry$hash))
    }
  }
  paste0(paste(lines, collapse = "\n"), "\n")
}

# The formula of an IR in the grammar of ir.md: the response, the fixed part
# by the names of its terms, the offsets and the random terms, where the
# terms that '||' has split from one term of a frozen factor are written as
# that term with '||'.
ir_formula <- function(ir) {
  response <- ir$response
  lhs <- if (is.null(response)) {
    ""
  } else {
    text <- formula_variable_text(response$variable)
    paste0(if (response$transform == "log") paste0("log(", text, ")") else text, " ")
  }
  terms <- vapply(ir$fixed$terms, function(t) t$name, "")
  fixed <- if (length(terms) && terms[1L] == "(Intercept)") c("1", terms[-1L]) else c("0", terms)
  offsets <- vapply(ir$offsets, function(o) {
    text <- formula_variable_text(o$variable)
    paste0("offset(", if (o$transform == "log") paste0("log(", text, ")") else text, ")")
  }, "")
  random <- character(0)
  previous <- NULL
  for (term in ir$random) {
    levels <- if (length(term$terms) == 1L) {
      Filter(Negate(is.null), lapply(term$terms[[1L]]$variables, function(v) v$level))
    }
    if (length(levels)) {
      variables <- vapply(term$terms[[1L]]$variables, function(v) v$variable, "")
      key <- paste(term$factor, paste(variables, collapse = "\001"), sep = "\002")
      if (!identical(key, previous)) {
        random <- c(random, paste0("(0 + ", term_name_of(variables), " || ", term$factor, ")"))
      }
      previous <- key
    } else {
      random <- c(random, paste0("(", term$name, ")"))
      previous <- NULL
    }
  }
  paste0(lhs, "~ ", paste(c(fixed, offsets, random), collapse = " + "))
}
