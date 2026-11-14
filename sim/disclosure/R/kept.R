# The class kept-levels (docs/spec/privacy.md, Guarantees, and
# docs/design/02-decisions.md, Q5, with its amendment of 14 November 2026): a
# document may show, by whatever written values, statuses, relations and
# declarations, that no level of a grouping factor and no member of the
# disclosure unit lost every outcome, or that no such level or member of two
# rows or more kept fewer than two analysed rows. The number of such levels
# then takes the single value 0, and the analysed levels, levels with two
# rows and contributors equal those of the design sample. privacy.md accepts
# the value 0 alone: a count above 0, the rows of a sample or of a level,
# which rows lack an outcome and a count of levels or members whose levels
# are the rows themselves stay outside the class. The attacks report the
# determinations of the class apart, under KEPT-LEVELS. dh_kept_levels()
# decides from the run whether a target is of the class, and
# dh_kept_levels_selftest() shows on tables just inside and just outside the
# class that it accepts no more.

# The quantities of the design sample that a target of the class can
# compare with the analysis sample, by the names that dh_difference_targets()
# gives them: the rows, the contributors and, for each grouping factor, its
# levels and its levels with two rows or more. Each has its value in the
# design sample and whether its levels are the rows themselves: a factor each
# of whose levels holds one row of the design sample, and the contributors
# when they have the basis rows, when each member of the disclosure unit
# holds one row, or, with the basis grouping_factors, when such a factor has
# the fewest levels, since the contributors are then its levels.
dh_kept_quantities <- function(ns, run) {
  design <- run$design
  sizes <- function(codes) {
    counts <- tabulate(codes[!is.na(codes)])
    counts[counts > 0L]
  }
  factors <- lapply(names(run$factors), function(f) {
    sizes(ns$value_codes(run, ns$factor_keys(run, f))[design])
  })
  names(factors) <- names(run$factors)
  out <- list(rows = list(design = length(design), rows = FALSE))
  support <- ns$rows_support(run, design)
  out$contributors <- list(design = support$distinct, rows = switch(
    support$basis,
    disclosure_unit = all(sizes(run$disclosure$codes[design]) == 1L),
    grouping_factors = {
      levels <- vapply(factors, length, 0L)
      any(vapply(factors[levels == min(levels)], function(s) all(s == 1L), NA))
    },
    TRUE))
  for (f in names(factors)) {
    rows <- all(factors[[f]] == 1L)
    out[[paste("levels", f)]] <- list(design = length(factors[[f]]), rows = rows)
    out[[paste("levels_with_two_rows", f)]] <- list(design = sum(factors[[f]] >= 2L), rows = rows)
  }
  out
}

# The quantity of dh_kept_quantities() that a target measures, as a list
# with its name and whether the target is its difference between the design
# sample and the analysis sample, or NULL: a difference of the design sample
# from the analysis sample (dh_difference_targets()), or a count of a finding
# on the analysis sample that measures its rows, its contributors or the
# levels, or levels with two rows, of the grouping factor that its scope
# names. The difference of the table from the analysis sample, a status and
# every other target measure none.
dh_kept_quantity <- function(finding, member, findings, ids, entries) {
  if (identical(finding, "D design minus analysis")) {
    return(list(name = member, difference = TRUE))
  }
  i <- match(finding, ids)
  if (is.na(i)) {
    return(NULL)
  }
  written <- findings[[i]]
  entry <- entries[[written$check]]
  if (!identical(entry[["sample"]], "analysis")) {
    return(NULL)
  }
  name <- switch(member, support.distinct = "contributors", support.rows = "rows", {
    defined <- entry[["statistics"]][[member]]
    measure <- defined[["measures"]]
    if (identical(measure, "analysis_rows")) {
      "rows"
    } else if (!is.null(measure) && measure %in% c("levels", "levels_with_two_rows")) {
      item <- iv_item(written, defined)
      if (!is.null(item)) paste(measure, item)
    }
  })
  if (is.null(name)) NULL else list(name = name, difference = FALSE)
}

# Whether each target of one table is a value that rule 1 or 3 of Across
# findings exists to hide: a difference of the table or the design sample
# from the analysis sample, or a count of a finding on the analysis sample
# that measures its rows, its contributors or the levels, or levels with
# two rows, of a grouping factor (dh_kept_quantity()). A determination of
# such a value that only the full reduction makes is traced or reported as
# a candidate (dh_determinations()), since privacy.md (Guarantees) asks the
# filter to close it where a narrow rule exists.
dh_rule_hides <- function(result, targets) {
  hides <- grepl("^D (table|design) minus analysis$", targets$finding)
  document <- result$document
  if (!nrow(targets) || is.null(result$run$analysis) || is.null(document)) {
    return(hides)
  }
  ids <- vapply(document$findings, dh_finding_id, "")
  for (j in which(!hides)) {
    hides[j] <- !is.null(dh_kept_quantity(targets$finding[j], targets$member[j],
                                          document$findings, ids, dh_capture$entries))
  }
  hides
}

# Whether each target of one table is a determination of the class
# kept-levels, as a logical vector. A target is of the class when three
# conditions hold:
# - its value shows that none is lost: a difference of 0, or a count of the
#   analysis sample equal to the same count of the design sample
# - it measures the levels of a grouping factor or its levels with two rows,
#   or the contributors, so that the number lost is the number of levels or
#   members without any outcome or with fewer than two analysed rows
# - those levels or members are not the rows themselves.
# The rows, the difference of the table, a status and every other target
# are outside the class.
dh_kept_levels <- function(ns, result, targets) {
  run <- result$run
  document <- result$document
  kept <- rep(FALSE, nrow(targets))
  if (!nrow(targets) || is.null(run$analysis) || is.null(document)) {
    return(kept)
  }
  quantities <- dh_kept_quantities(ns, run)
  ids <- vapply(document$findings, dh_finding_id, "")
  for (j in seq_len(nrow(targets))) {
    q <- dh_kept_quantity(targets$finding[j], targets$member[j], document$findings, ids,
                          dh_capture$entries)
    quantity <- if (!is.null(q)) quantities[[q$name]]
    if (is.null(quantity)) {
      next
    }
    value <- suppressWarnings(as.numeric(targets$value[j]))
    lost <- if (q$difference) value else quantity$design - value
    kept[j] <- isTRUE(lost == 0) &&
      grepl("^(levels|levels_with_two_rows) .|^contributors$", q$name) &&
      !quantity$rows
  }
  kept
}

# A determination that the classifier would count as a leak is of the class
# kept-levels when the predicate holds in every table of its group, and it
# then has the verdict 'kept-levels'. Applied after dh_alternatives(), so
# that a determination that an alternative traces counts as traced.
dh_kept_verdict <- function(found) {
  found$verdict[found$verdict == "leak" & found$kept] <- "kept-levels"
  found
}

# --- The self-test of the predicate ------------------------------------------------

# The tables of the self-test, each with its k and the verdict that the
# predicate must give on some of its targets: TRUE for a determination of
# the class, FALSE for one just outside it. Each condition of the predicate
# decides targets of its own, so that the self-test fails when any is
# removed. The value 0 decides the subjects without any outcome, their
# contributors and the subjects with fewer than two analysed rows of a table
# in which one subject lost every outcome, a count of 1 that the full
# reduction fixes beside the observation key (subject, item), and the
# combinations without any outcome, the levels of h with fewer than two
# analysed rows and the analysed combinations with two rows of crossed (1, 0,
# 2). The kinds of the class decide the rows without an outcome where none
# lacks one and the analysed rows equal to the design sample's. The exclusion
# of levels that are the rows decides the combinations of g and h that hold
# one row each, whose levels the analysis sample keeps, pupils of one row as
# the disclosure unit, the contributors with the basis rows in y ~ x and the
# contributors with the basis grouping_factors of 12 subjects of one row
# each, so that each of its three clauses for the contributors decides a
# target of its own. The tables
# that the class accepts include the example of privacy.md, 20 subjects
# crossed with 12 items at k = 10, and one example of each kind of
# determination that the class settled on 14 November 2026: crossed (0, 0,
# 0), whose levels with two rows rest on the dominance rule, crossed (1, 0,
# 2), whose contributors and levels rest on the detail 'dominance' and the
# written counts of combinations, zoo-separation, whose analysed subjects rest
# on a status inferred within a tolerance, and the table of the former
# regression attack R14-product-bound, whose subjects without any outcome the
# written rows of the design sample and the relation crossed fix.
dh_kept_levels_cases <- function() {
  targets <- function(finding = "D design minus analysis", ...) {
    expected <- c(...)
    data.frame(finding = finding, member = names(expected), expected = unname(expected),
               stringsAsFactors = FALSE)
  }
  crossed <- function(g, h, single, empty, y_missing) {
    function() dh_family_crossed(unit = FALSE)$build(list(g = g, h = h, single = single,
                                                          empty = empty, y_missing = y_missing))
  }
  one_row <- function(unit) {
    function() dh_crossed_case(matrix(1L, 4L, 4L), matrix(0L, 4L, 4L), unit = unit)
  }
  list(
    list(name = "20 subjects by 12 items, one row each, 3 outcomes missing", k = 10,
         build = function() dh_kept_levels_subjects_items(c(1L, 7L, 13L)),
         targets = rbind(targets("levels subject" = TRUE, "levels item" = TRUE,
                                 "contributors" = TRUE, "levels_with_two_rows subject" = TRUE,
                                 "rows" = FALSE),
                         targets("outcome.constant_clusters factor=subject",
                                 "multi_row_levels" = TRUE),
                         targets("outcome.constant_clusters factor=item", "support.rows" = FALSE))),
    list(name = "20 subjects by 12 items, one row each, no outcome missing", k = 10,
         build = function() dh_kept_levels_subjects_items(integer(0)),
         targets = rbind(targets("levels_with_two_rows subject" = TRUE, "rows" = FALSE),
                         targets("outcome.constant_clusters factor=item", "support.rows" = FALSE))),
    list(name = "20 subjects by 12 items, one row each, 6 outcomes of s01 and 6 of s02 missing",
         k = 10, build = dh_kept_levels_two_subjects,
         targets = targets("levels subject" = TRUE, "contributors" = TRUE)),
    list(name = "20 subjects by 12 items, one row each, the key (subject, item), s01 without an outcome",
         k = 10, build = dh_kept_levels_one_lost,
         targets = rbind(targets("levels subject" = FALSE, "contributors" = FALSE,
                                 "levels_with_two_rows subject" = FALSE, "levels item" = TRUE),
                         targets("outcome.constant_clusters factor=subject",
                                 "multi_row_levels" = FALSE))),
    list(name = "crossed (0, 0, 0), g and h of 3 levels and two rows a combination", k = 3,
         build = crossed(3L, 3L, 0L, 0L, 0L),
         targets = rbind(targets("levels_with_two_rows g" = TRUE, "levels_with_two_rows h" = TRUE,
                                 "rows" = FALSE),
                         targets("outcome.zero_shares factor=g:h", "levels" = TRUE))),
    list(name = "crossed (1, 0, 2), g and h of 3 levels, one combination of one row", k = 3,
         build = crossed(3L, 3L, 1L, 0L, 2L),
         targets = rbind(targets("contributors" = TRUE, "levels g" = TRUE, "levels h" = TRUE,
                                 "levels_with_two_rows h" = FALSE, "levels g:h" = FALSE,
                                 "rows" = FALSE),
                         targets("outcome.zero_shares factor=g", "levels" = TRUE,
                                 "rows" = FALSE),
                         targets("outcome.constant_clusters factor=g:h",
                                 "multi_row_levels" = FALSE))),
    list(name = "zoo-separation, subjects 3, items per condition 1, ceiling 0, y_missing 0",
         k = 3,
         build = function() dz_family_separation()$build(
           list(subjects = 3L, items_per_condition = 1L, ceiling = 0L, y_missing = 0L)),
         targets = rbind(targets("contributors" = TRUE, "levels item" = TRUE, "rows" = FALSE),
                         targets("outcome.minority_events factor=subject", "levels" = TRUE,
                                 "support.distinct" = TRUE, "support.rows" = FALSE))),
    list(name = "g crossed with h, 4 by 4, one row a combination, nothing missing", k = 3,
         build = one_row(FALSE),
         targets = rbind(targets("levels g" = TRUE, "contributors" = TRUE, "levels g:h" = FALSE,
                                 "rows" = FALSE),
                         targets("outcome.zero_shares factor=g:h", "levels" = FALSE))),
    list(name = "g crossed with h, 4 by 4, one pupil of one row a combination, nothing missing",
         k = 3, build = one_row(TRUE),
         targets = rbind(targets("levels g" = TRUE, "contributors" = FALSE),
                         targets("outcome.zero_shares factor=g", "support.distinct" = FALSE))),
    list(name = "zoo-reuse, schools 3, classes 3, pupils 2, y_missing 1", k = 3,
         build = function() dz_family_reuse()$build(list(schools = 3L, classes = 3L,
                                                         pupils = 2L, y_missing = 1L)),
         targets = targets("levels school" = TRUE, "levels class" = TRUE,
                           "levels_with_two_rows school" = TRUE, "rows" = FALSE,
                           "contributors" = FALSE)),
    list(name = "y ~ x, 12 rows, nothing missing, the contributors with the basis rows", k = 3,
         build = function() list(data = data.frame(y = dh_outcome(12L), x = dh_covariate(12L)),
                                 formula = "y ~ x", args = dh_t1()),
         targets = targets("contributors" = FALSE, "rows" = FALSE)),
    list(name = "y ~ x + (1 | subject), 12 subjects of one row each, nothing missing", k = 3,
         build = function() list(data = data.frame(y = dh_outcome(12L), x = dh_covariate(12L),
                                                   subject = dh_labels("s", 12L)),
                                 formula = "y ~ x + (1 | subject)", args = dh_t1()),
         targets = targets("contributors" = FALSE, "levels subject" = FALSE, "rows" = FALSE))
  )
}

# The example of privacy.md (Guarantees): 20 subjects crossed with 12 items,
# one row in each combination, the subjects the disclosure unit and the
# rows given of the last item without an outcome, in a gaussian T1 run,
# whose outcome.constant_clusters for 'item' writes the 12 analysed items
# and the 20 analysed subjects as its contributors.
dh_kept_levels_subjects_items <- function(missing) {
  data <- expand.grid(item = dh_labels("i", 12L), subject = dh_labels("s", 20L),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  n <- nrow(data)
  data$y <- dh_outcome(n)
  data$y[which(data$item == "i12")[missing]] <- NA
  data$x <- dh_covariate(n)
  declaration <- dh_declaration(units = list(dh_participant("subject")))
  list(data = data, formula = "y ~ x + (1 | subject) + (1 | item)",
       args = c(list(declaration = declaration), dh_t1()))
}

# The table of the former regression attack R14-product-bound: the design of
# privacy.md's example with the first 6 outcomes of s01 and of s02 missing. The 240 written rows of the
# design sample and the relation crossed bound the subjects of the design
# sample by 240 over the 12 analysed items, the 20 analysed subjects, so that
# no subject lost every outcome.
dh_kept_levels_two_subjects <- function() {
  data <- expand.grid(item = dh_labels("i", 12L), subject = dh_labels("s", 20L),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  n <- nrow(data)
  data$y <- dh_outcome(n)
  data$y[c(which(data$subject == "s01")[1:6], which(data$subject == "s02")[1:6])] <- NA
  data$x <- dh_covariate(n)
  declaration <- dh_declaration(units = list(dh_participant("subject")))
  list(data = data, formula = "y ~ x + (1 | subject) + (1 | item)",
       args = c(list(declaration = declaration), dh_t1()))
}

# The design of privacy.md's example with the observation key (subject,
# item) and every outcome of s01 missing, in a gaussian T1 run. The document
# writes the 240 rows of the design sample beside the 228 analysed rows,
# which the key exceeds by 12, and the 19 analysed subjects and 12 analysed
# items of outcome.constant_clusters for 'item'. With the relation crossed
# and the status of keys.duplicates, which the full reduction holds, the
# subjects and items of the design sample multiply to 240, so they are 20
# and 12 and the subjects without any outcome are 1. The strict reduction
# reads alike with 21 subjects, two of which hold 6 items each without an
# outcome (sim/disclosure/README.md, The attacks).
dh_kept_levels_one_lost <- function() {
  data <- expand.grid(item = dh_labels("i", 12L), subject = dh_labels("s", 20L),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  n <- nrow(data)
  data$y <- dh_outcome(n)
  data$y[data$subject == "s01"] <- NA
  data$x <- dh_covariate(n)
  declaration <- dh_declaration(
    units = list(dh_participant("subject")),
    table = list(fields = list(list(name = "subject", type = "string"),
                               list(name = "item", type = "string"))),
    observation = list(key = list("subject", "item")))
  list(data = data, formula = "y ~ x + (1 | subject) + (1 | item)",
       args = c(list(declaration = declaration), dh_t1()))
}

# Runs the self-test and returns one line for each target whose verdict
# differs from the expected one, or that the table does not hide. An empty
# result means that the predicate accepts the targets of the class and
# refuses those just outside it.
dh_kept_levels_selftest <- function(ns) {
  wrong <- character(0)
  for (case in dh_kept_levels_cases()) {
    old <- dh_set_k(ns, case$k)
    result <- tryCatch(dh_run(ns, case$build()), error = function(e) list(error = conditionMessage(e)))
    dh_set_k(ns, old)
    if (!is.null(result$error)) {
      wrong <- c(wrong, sprintf("the self-test of kept-levels cannot audit '%s': %s",
                                case$name, result$error))
      next
    }
    targets <- dh_targets(result)
    difference <- dh_difference_targets(ns, result)
    if (!is.null(difference)) {
      targets <- rbind(targets, difference[names(targets)])
    }
    kept <- dh_kept_levels(ns, result, targets)
    for (j in seq_len(nrow(case$targets))) {
      want <- case$targets[j, ]
      hit <- which(targets$finding == want$finding & targets$member == want$member)
      if (!length(hit)) {
        wrong <- c(wrong, sprintf("the self-test of kept-levels: '%s' does not hide %s | %s",
                                  case$name, want$finding, want$member))
      } else if (!identical(any(kept[hit]), want$expected)) {
        wrong <- c(wrong, sprintf(
          "the self-test of kept-levels: the predicate %s %s | %s in '%s'",
          if (want$expected) "refuses" else "accepts", want$finding, want$member, case$name))
      }
    }
  }
  wrong
}
