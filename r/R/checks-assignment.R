# The checks of the prefix assignment
# (spec/registry/checks/assignment.*.yaml).

# The assignment of a scope element (registry.md, Terms): the rows of the
# assignment, the rows of the design sample in which every label column of
# its unit and the assigned column are present, the level of the unit in
# each of these rows, numbered from 1 in the order of first appearance, the
# number of levels, the level of the assignment, declared or inferred with
# the parameter agreement, and the entry of the assignment block. Returns
# NULL when the unit counts as absent.
assignment_rows <- function(run, entry, element) {
  declaration <- run$declaration
  if (is.null(declared_units(declaration)[[element$unit]])) {
    return(NULL)
  }
  assignment <- declaration[["assignment"]]
  i <- match(element$column, vapply(assignment, function(a) a[["column"]], ""))
  present <- function(member) {
    if (declaration_inferred(declaration, path_pointer("assignment", i - 1L, member))) NULL
    else assignment[[i]][[member]]
  }
  labels <- unit_label_columns(declaration, element$unit)
  column <- comparison_form(element$column)
  rows <- run$design[!is.na(value_codes(run, c(labels, column), run$design))]
  unit <- value_codes(run, labels, rows)
  unit <- match(unit, unique(unit))
  assigned <- value_codes(run, column, rows)
  level <- present("level")
  source <- "declared"
  if (is.null(level)) {
    source <- "inferred_from_the_data"
    constant <- pooled_constancy(unit, assigned, agreement_fraction(entry))$constant
    level <- if (constant) "between_unit" else "within_unit"
  }
  list(rows = rows, unit = unit, count = max(c(unit, 0L)), assigned = assigned,
       level = level, source = source, randomised = isTRUE(present("randomised")),
       blocks = as.character(unlist(present("blocks"))))
}

# Whether the assignment checks apply to an assignment: its level is
# between_unit and some level of the unit has at least two rows of the
# assignment.
assignment_applies <- function(found) {
  !is.null(found) && found$level == "between_unit" && any(tabulate(found$unit) >= 2L)
}

# The checks of the prefix assignment are not available without an
# assignment block (declarations.md, assignment), or when every entry of the
# block counts as absent.
assignment_block_missing <- function(run) {
  !length(assignment_elements(run$declaration))
}

# assignment.constant_within_unit: the levels of the unit within which the
# assigned column takes more than one value.
audit_check_assignment_constant_within_unit <- function(run, entry, elements) {
  if (assignment_block_missing(run)) {
    return(check_unavailable("declaration_missing"))
  }
  lapply(elements, function(element) {
    found <- assignment_rows(run, entry, element)
    if (!assignment_applies(found)) {
      return(NULL)
    }
    cells <- !duplicated(pair_codes(found$unit, found$assigned))
    mixed <- sum(tabulate(found$unit[cells], nbins = found$count) > 1L)
    check_element(list(units = found$count, mixed_units = mixed, level_source = found$source),
                  rules = mixed > 0, rows = found$rows)
  })
}

# assignment.unit_in_random_part: whether a grouping factor with a random
# intercept divides the rows of the assignment into the levels of the unit,
# and the grouping factors each of whose levels contains whole levels of the
# unit.
audit_check_assignment_unit_in_random_part <- function(run, entry, elements) {
  if (assignment_block_missing(run)) {
    return(check_unavailable("declaration_missing"))
  }
  lapply(elements, function(element) {
    found <- assignment_rows(run, entry, element)
    if (!assignment_applies(found) || !found$randomised) {
      return(NULL)
    }
    positions <- match(found$rows, run$design)
    coverage <- "absent"
    coarser <- character(0)
    for (factor in names(run$factors)) {
      code <- factor_levels(run, factor)$code[positions]
      pairs <- sum(!duplicated(pair_codes(found$unit, code)))
      if (pairs == found$count && pairs == length(unique(code))) {
        if (factor_has_intercept(run, factor)) {
          coverage <- "present"
        }
      } else if (pairs == found$count) {
        coarser <- c(coarser, factor)
      }
    }
    check_element(list(units = found$count, coverage = coverage, coarser_factors = coarser,
                       level_source = found$source),
                  rules = c(coverage == "absent" && length(coarser) > 0L, coverage == "absent"),
                  rows = found$rows)
  })
}

# assignment.design_df: the degrees of freedom between the levels of the unit
# after the fixed effects, J + rank(X_d) - rank(X) on the rows of the
# assignment, where X_d is X with the first row of each level subtracted from
# the level's rows and the columns constant within the levels up to rounding
# set to 0 (level_differences()), and the declared blocks that the fixed part
# leaves out.
audit_check_assignment_design_df <- function(run, entry, elements) {
  if (assignment_block_missing(run)) {
    return(check_unavailable("declaration_missing"))
  }
  fixed <- comparison_form(unlist(lapply(run$ir$fixed$terms, function(term) {
    vapply(term$variables, function(v) v$variable, "")
  })))
  units <- declared_units(run$declaration)
  lapply(elements, function(element) {
    found <- assignment_rows(run, entry, element)
    if (!assignment_applies(found)) {
      return(NULL)
    }
    x <- run$x[match(found$rows, run$design), , drop = FALSE]
    within <- level_differences(x, found$unit, found$count)
    design_df <- found$count + sum(sequential_rule(within)) - sum(sequential_rule(x))
    blocks <- Filter(function(block) {
      !is.null(units[[block]]) &&
        !all(unit_label_columns(run$declaration, block) %in% fixed)
    }, found$blocks)
    statistics <- list(units = found$count, design_df = design_df,
                       missing_blocks = as.character(blocks), level_source = found$source)
    check_element(statistics, rules = c(design_df == 0, length(blocks) > 0L), rows = found$rows)
  })
}
