# The class kept-levels (docs/spec/privacy.md, Guarantees, and
# docs/design/02-decisions.md, Q5): the document can show an upper bound u on
# the rows without an outcome, k - 1 when the rows of the design sample
# exceed those of the analysis sample by fewer than k, so that the first
# paragraph of rule 1 of Across findings hides them, or the written rows of a
# sample that holds the design sample less the written analysed rows. A level
# that the document shows to hold n rows or more of the design sample keeps
# n - u analysed rows or more, so that none of its item's levels lost every
# outcome when n > u, and none kept fewer than two analysed rows when
# n > u + 1. privacy.md accepts the values that this fixes, and the attacks
# report them apart, under KEPT-LEVELS. dh_kept_levels() decides from the run
# and the document whether a target is of the class, and
# dh_kept_levels_selftest() shows on tables just inside and just outside the
# class that it accepts no more.

# The number that a written statistic holds, or NA.
dh_written_count <- function(statistic) {
  value <- statistic$value
  if (is.numeric(value) && length(value) == 1L) value else NA_real_
}

# The written rows of the table, the design sample and the analysis sample,
# by sample, from the support.rows of the findings, which counts the sample
# that the entry names. A count that measures the rows of a sample is
# written only beside the support.rows of a finding on it, which measures
# them too.
dh_written_rows <- function(document, entries = dh_capture$entries) {
  out <- list()
  for (finding in document$findings) {
    if (!identical(finding$status$availability$value, "available")) {
      next
    }
    entry <- entries[[finding$check]]
    value <- dh_written_count(finding$support$rows)
    if (!is.na(value)) {
      out[[entry[["sample"]]]] <- value
    }
  }
  out
}

# The upper bound u that the document shows on the rows without an outcome,
# or Inf when it shows none: k - 1 when the rows of the design sample exceed
# those of the analysis sample by fewer than k and no count writes the rows
# of the design sample, so that the first paragraph of rule 1 hides them, and
# the written rows of the table or of the design sample less the written
# analysed rows. The clause of rule 1 on the sizes of levels can also hide
# the rows of the design sample, and only the written rows bound the rows
# without an outcome then.
dh_kept_bound <- function(run, document, k, entries = dh_capture$entries) {
  bound <- Inf
  measures <- dh_measures(document, entries)
  if (length(run$design) - length(run$analysis) < k &&
      !any(measures$written[measures$key == "design rows"])) {
    bound <- k - 1
  }
  written <- dh_written_rows(document, entries)
  if (!is.null(written$analysis)) {
    for (s in c("table", "design")) {
      if (!is.null(written[[s]])) {
        bound <- min(bound, written[[s]] - written$analysis)
      }
    }
  }
  bound
}

# The columns of the item by which a count of levels resolves (registry.md,
# Statistics and counts, resolved_by): those of the grouping factor that its
# scope names, the label columns of the declared unit that its scope names,
# with those of its parent when it is declared within_parent, or the column
# that its scope names. NULL for a count that resolves by two items or by a
# statistic.
dh_count_columns <- function(ns, run, finding, defined) {
  refs <- defined[["resolved_by"]]
  if (length(refs) != 1L || !identical(refs[[1L]][["source"]], "scope")) {
    return(NULL)
  }
  name <- refs[[1L]][["name"]]
  value <- finding$scope[[name]]
  if (is.null(value)) {
    return(NULL)
  }
  switch(name,
    factor = unlist(run$factors[[value]]),
    unit = ns$unit_label_columns(run$declaration, value),
    first = , second = , column = value,
    NULL
  )
}

# A lower bound on the levels of the grouping column column in the design
# sample that the document gives through relations that the specifications
# fix: the written counts of a sample that lies in the design sample that
# measure the levels of an item whose columns are that column alone, or its
# levels with two rows or one row, and the contributors of the basis
# disclosure_unit of such a sample when the unit is the column. The table
# can hold levels that the design sample does not, so its counts are left
# out. Contributors with the detail 'secondary' are k or more, since
# support.contributors.distinct below k keeps the detail 'min_count'
# whatever rule suppresses it later (privacy.md, Across findings).
dh_column_levels_floor <- function(ns, run, document, column, k, entries = dh_capture$entries) {
  floor <- 1
  unit <- run$disclosure$columns
  for (finding in document$findings) {
    if (!identical(finding$status$availability$value, "available")) {
      next
    }
    entry <- entries[[finding$check]]
    if (identical(entry[["sample"]], "table")) {
      next
    }
    for (name in names(finding$statistics)) {
      defined <- entry[["statistics"]][[name]]
      measure <- defined[["measures"]]
      if (is.null(measure) || !measure %in% c("levels", "levels_with_two_rows",
                                               "levels_with_one_row")) {
        next
      }
      if (identical(dh_count_columns(ns, run, finding, defined), column)) {
        floor <- max(floor, dh_written_count(finding$statistics[[name]]), na.rm = TRUE)
      }
    }
    contributors <- finding$support$contributors
    value <- dh_written_count(contributors$distinct)
    if (is.na(value) && identical(contributors$distinct$availability$detail, "secondary")) {
      value <- k
    }
    if (!is.na(value) && identical(contributors$basis, "disclosure_unit") &&
        identical(unit, column)) {
      floor <- max(floor, value)
    }
  }
  floor
}

# A lower bound on the rows of every level of the grouping factor f in the
# design sample that the document gives: for a factor of one column that
# structure.label_incidence finds crossed with another grouping column of
# the IR, every level holds a row with each level of the other column, so
# at least the lower bound on that column's levels. Both columns are
# grouping columns of the IR, so that the rows of the pair are the design
# sample. 1 otherwise.
dh_level_floor <- function(ns, run, document, f, k, entries = dh_capture$entries) {
  columns <- unlist(run$factors[[f]])
  if (length(columns) != 1L) {
    return(1)
  }
  grouping <- unlist(Filter(function(c) length(c) == 1L, run$factors))
  floor <- 1
  for (finding in document$findings) {
    if (!identical(finding$check, "structure.label_incidence") ||
        !identical(finding$status$availability$value, "available") ||
        !identical(finding$statistics$relation$value, "crossed")) {
      next
    }
    pair <- c(finding$scope$first, finding$scope$second)
    if (!columns %in% pair || !all(pair %in% grouping)) {
      next
    }
    other <- setdiff(pair, columns)
    floor <- max(floor, dh_column_levels_floor(ns, run, document, other, k, entries))
  }
  floor
}

# Whether each target of one table is a determination of the class
# kept-levels, as a logical vector. With u the bound of dh_kept_bound() and n
# the bound of dh_level_floor() on the rows of every level of the grouping
# factor F in the design sample, the class holds:
# - the number of levels of F without any outcome (D design minus analysis
#   | levels F), 0 when n > u, and a count of the analysis sample that
#   measures the levels of F, which then equals the design sample's
# - the difference of the levels with two rows of F (D design minus
#   analysis | levels_with_two_rows F) and a count of the analysis sample
#   that measures them, when n > u + 1, so that every level keeps two
#   analysed rows, or when n > u and the analysed counts of F resolve as
#   non-person, so that every analysed level holds two members
# - the contributors, and the difference of the contributors, when they
#   count the levels of a factor for which n > u: the disclosure unit with
#   the basis disclosure_unit, or a factor with the fewest analysed levels
#   with the basis grouping_factors.
# The rows, the counts of combinations, a status and every other target
# are outside the class as the predicate checks it.
dh_kept_levels <- function(ns, result, targets) {
  run <- result$run
  document <- result$document
  kept <- rep(FALSE, nrow(targets))
  if (!nrow(targets) || is.null(run$analysis) || is.null(document)) {
    return(kept)
  }
  k <- document$privacy$min_count
  entries <- dh_capture$entries
  u <- dh_kept_bound(run, document, k, entries)
  if (!is.finite(u)) {
    return(kept)
  }
  floors <- list()
  floor_of <- function(f) {
    if (is.null(f) || !f %in% names(run$factors)) {
      return(0)
    }
    if (is.null(floors[[f]])) {
      floors[[f]] <<- dh_level_floor(ns, run, document, f, k, entries)
    }
    floors[[f]]
  }
  none_lost <- function(f) floor_of(f) > u
  non_person <- function(f) {
    codes <- ns$value_codes(run, ns$factor_keys(run, f))
    identical(ns$resolve_count_class(run, list(codes), run$analysis), "non_person")
  }
  two_kept <- function(f) none_lost(f) && (floor_of(f) > u + 1 || non_person(f))
  support <- ns$rows_support(run, run$analysis)
  unit <- if (!is.null(run$disclosure)) {
    Find(function(f) setequal(unlist(run$factors[[f]]), run$disclosure$columns),
         names(run$factors))
  }
  contributors <- function() {
    if (identical(support$basis, "disclosure_unit")) {
      return(none_lost(unit))
    }
    if (identical(support$basis, "grouping_factors")) {
      # A factor with the fewest analysed levels counts the contributors of
      # both samples when it lost no level.
      fewest <- Filter(function(f) {
        sum(tabulate(ns$value_codes(run, ns$factor_keys(run, f))[run$analysis]) > 0L) ==
          support$distinct
      }, names(run$factors))
      return(any(vapply(fewest, none_lost, NA)))
    }
    FALSE
  }
  ids <- vapply(document$findings, dh_finding_id, "")
  for (j in seq_len(nrow(targets))) {
    member <- targets$member[j]
    if (identical(targets$finding[j], "D design minus analysis")) {
      kept[j] <- if (startsWith(member, "levels ")) {
        none_lost(sub("^levels ", "", member))
      } else if (startsWith(member, "levels_with_two_rows ")) {
        two_kept(sub("^levels_with_two_rows ", "", member))
      } else if (identical(member, "contributors")) {
        contributors()
      } else {
        FALSE
      }
      next
    }
    i <- match(targets$finding[j], ids)
    if (is.na(i)) {
      next
    }
    finding <- document$findings[[i]]
    entry <- entries[[finding$check]]
    if (!identical(entry[["sample"]], "analysis")) {
      next
    }
    if (identical(member, "support.distinct")) {
      kept[j] <- contributors()
      next
    }
    defined <- entry[["statistics"]][[member]]
    measure <- defined[["measures"]]
    item <- iv_item(finding, defined)
    kept[j] <- if (identical(measure, "levels")) {
      none_lost(item)
    } else if (identical(measure, "levels_with_two_rows")) {
      two_kept(item)
    } else {
      FALSE
    }
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
# decides at least one target, so that the self-test fails when any is
# removed: the bound of rule 1 only when fewer than k rows lack an outcome
# (crossed 3 by 3 with four rows without an outcome) and no count writes the
# rows of the design sample (a crossed gaussian design whose analysis sample
# the document does not show), the bound of the written rows of the design
# sample (4 subjects by 4 items with three outcomes of one subject missing)
# and of the table (crossed 4 by 4 with three outcomes missing in two
# combinations, whose rule 1 hides the rows of the design sample through its
# clause on level sizes), a level of u rows for the levels without any
# outcome (crossed 4 by 2, whose 2 levels of h the non-person counts of the
# analysed pupils write, and 20 subjects by 12 items with 12 rows without an
# outcome), a level of u + 1 rows of a person item for the
# levels with two rows (crossed 3 by 3 with one row in each combination),
# the class non_person of an item's analysed counts (zoo-separation), the
# contributors by their basis (zoo-reuse and crossed 4 by 2, whose pupils
# hold one row, crossed 3 by 3 and the binomial rows), the counts of the
# analysis sample alone (structure.cluster_sizes in crossed 4 by 4), the
# analysed levels and contributors that the columns of a fixed factor make
# the analysis sample hide, and the bound on the levels of a column, which
# the relation crossed requires (crossed 4 by 4 with an empty combination),
# which a count of a declared unit within_parent does not give (6 schools
# with the class labels c01 and c02), nor the contributors of the table (2
# subjects by 4 items beside subjects outside the design sample), and which
# contributors with the detail 'secondary' give (zoo-separation). The rows
# without an outcome, the analysed rows and the combinations of crossed
# columns are refused throughout. Three guards of dh_count_columns() and
# dh_level_floor() decide nothing in registry 0.1.0 at these k: a count that
# resolves by a statistic or by two items, whose combinations the end of
# rule 1 hides beside the analysis sample, and a pair of columns that are
# not both grouping columns of the IR.
dh_kept_levels_cases <- function() {
  targets <- function(finding = "D design minus analysis", ...) {
    expected <- c(...)
    data.frame(finding = finding, member = names(expected), expected = unname(expected),
               stringsAsFactors = FALSE)
  }
  crossed <- function(g, h, y_missing) {
    function() dh_family_crossed(unit = FALSE)$build(list(g = g, h = h, single = 0L, empty = 0L,
                                                          y_missing = y_missing))
  }
  one_row <- function(g, h, unit = FALSE) {
    sizes <- matrix(1L, g, h)
    missing <- matrix(0L, g, h)
    missing[1L, 1L] <- 1L
    function() dh_crossed_case(sizes, missing, unit = unit)
  }
  partial <- matrix(2L, 4L, 4L)
  partial[4L, 4L] <- 0L
  lost <- matrix(0L, 4L, 4L)
  lost[1L, 1L] <- 1L
  two_rows <- matrix(2L, 4L, 4L)
  lost_three <- matrix(0L, 4L, 4L)
  lost_three[1L, 1L] <- 2L
  lost_three[2L, 2L] <- 1L
  list(
    list(name = "zoo-reuse, schools 3, classes 3, pupils 2, y_missing 1", k = 3,
         build = function() dz_family_reuse()$build(list(schools = 3L, classes = 3L,
                                                         pupils = 2L, y_missing = 1L)),
         targets = targets("levels school" = TRUE, "levels class" = TRUE,
                           "levels_with_two_rows school" = TRUE, "rows" = FALSE,
                           "contributors" = FALSE)),
    list(name = "crossed 4 by 4, two rows a combination, one combination without an outcome",
         k = 3, build = crossed(4L, 4L, 1L),
         targets = rbind(targets("levels g" = TRUE, "levels h" = TRUE, "contributors" = TRUE,
                                 "levels_with_two_rows g" = TRUE, "levels g:h" = FALSE,
                                 "rows" = FALSE),
                         targets("structure.cluster_sizes factor=g", "levels" = FALSE))),
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
                         targets("outcome.constant_clusters factor=subject",
                                 "multi_row_levels" = TRUE))),
    list(name = "20 subjects by 12 items, one row each, 6 outcomes of s01 and 6 of s02 missing",
         k = 10, build = dh_kept_levels_two_subjects,
         targets = targets("levels subject" = FALSE, "contributors" = FALSE)),
    list(name = "crossed 4 by 2, one pupil of one row a combination, one outcome missing", k = 3,
         build = one_row(4L, 2L, unit = TRUE),
         targets = targets("levels g" = FALSE, "contributors" = FALSE)),
    list(name = "crossed 3 by 3, one row a combination, one outcome missing", k = 3,
         build = one_row(3L, 3L),
         targets = rbind(targets("levels g" = TRUE, "levels_with_two_rows g" = FALSE),
                         targets("outcome.constant_clusters factor=g",
                                 "multi_row_levels" = FALSE))),
    list(name = "crossed 3 by 3, two rows a combination, two combinations without an outcome",
         k = 3, build = crossed(3L, 3L, 2L),
         targets = targets("levels g" = FALSE, "levels h" = FALSE, "contributors" = FALSE)),
    list(name = "crossed 4 by 4 with an empty combination, one outcome missing", k = 3,
         build = function() dh_crossed_case(partial, lost, unit = FALSE),
         targets = targets("levels g" = FALSE, "levels h" = FALSE, "contributors" = FALSE)),
    list(name = "crossed 4 by 4, two rows a combination, gaussian, one outcome missing", k = 3,
         build = dh_kept_levels_gaussian,
         targets = targets("levels g" = FALSE, "levels h" = FALSE)),
    list(name = "4 subjects by 4 items, three outcomes of one subject missing", k = 3,
         build = dh_kept_levels_one_subject,
         targets = targets("levels subject" = TRUE, "levels item" = TRUE, "contributors" = TRUE,
                           "levels_with_two_rows subject" = FALSE)),
    list(name = "crossed 4 by 4, two rows a combination, three outcomes missing in two", k = 3,
         build = function() dh_crossed_case(two_rows, lost_three, unit = FALSE),
         targets = targets("levels g" = TRUE, "levels h" = TRUE, "contributors" = TRUE,
                           "levels_with_two_rows g" = FALSE, "rows" = FALSE)),
    list(name = "2 subjects by 4 items and two subjects whose one row lacks the covariate", k = 3,
         build = dh_kept_levels_outside,
         targets = targets("levels item" = FALSE)),
    list(name = "g fixed and crossed with h, 4 by 4, two rows a combination, two outcomes missing",
         k = 3, build = dh_kept_levels_fixed,
         targets = targets("outcome.zero_shares factor=g", "levels" = TRUE,
                           "support.distinct" = TRUE)),
    list(name = "4 subjects by 4 items by 2 replicates, nothing missing", k = 3,
         build = dh_kept_levels_replicates,
         targets = targets("levels subject" = TRUE, "rows" = FALSE)),
    list(name = "zoo-separation, subjects 3, items per condition 1, ceiling 0, y_missing 0",
         k = 3,
         build = function() dz_family_separation()$build(
           list(subjects = 3L, items_per_condition = 1L, ceiling = 0L, y_missing = 0L)),
         targets = rbind(targets("levels item" = TRUE, "contributors" = FALSE),
                         targets("outcome.constant_clusters factor=item", "multi_row_levels" = TRUE),
                         targets("outcome.constant_clusters factor=subject",
                                 "multi_row_levels" = FALSE),
                         targets("outcome.minority_events factor=subject", "levels" = FALSE))),
    list(name = "binomial rows, one without events, two with some, one without an outcome", k = 3,
         build = function() dh_family_binomial()$build(list(none = 1L, all = 0L, some = 2L,
                                                            y_missing = 1L)),
         targets = targets("contributors" = FALSE)),
    list(name = "6 schools with the class labels c01 and c02, class declared within_parent",
         k = 10, build = dh_kept_levels_within_parent,
         targets = rbind(targets("levels school" = FALSE, "levels_with_two_rows school" = FALSE),
                         targets("outcome.constant_clusters factor=school",
                                 "multi_row_levels" = FALSE)))
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

# The design of privacy.md's example with the first 6 outcomes of s01 and of
# s02 missing. The written rows of the design sample less the analysed rows
# bound the rows without an outcome by 12, the rows of each subject, so that
# the bound leaves open whether a subject lost every outcome. The written
# rows of the design sample, 240, and the relation crossed fix it, as
# R14-product-bound shows, a kind of determination that privacy.md
# (Guarantees) names as not yet covered and the predicate refuses.
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

# 4 subjects crossed with 4 items, one row in each combination, the subjects
# the disclosure unit and three outcomes of the first subject missing, in a
# gaussian T1 run. Rule 1 does not hide the rows of the design sample, which
# the document writes beside the analysed rows.
dh_kept_levels_one_subject <- function() {
  data <- expand.grid(item = dh_labels("i", 4L), subject = dh_labels("s", 4L),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  n <- nrow(data)
  data$y <- dh_outcome(n)
  data$y[1:3] <- NA
  data$x <- dh_covariate(n)
  declaration <- dh_declaration(units = list(dh_participant("subject")))
  list(data = data, formula = "y ~ x + (1 | subject) + (1 | item)",
       args = c(list(declaration = declaration), dh_t1()))
}

# g crossed with h, 4 levels each and two rows in each combination, with a
# gaussian outcome that no level holds constant and one outcome missing, so
# that outcome.constant_clusters rests on suppressed counts and the
# document shows no value of the analysis sample and writes the rows of the
# design sample.
dh_kept_levels_gaussian <- function() {
  data <- expand.grid(rep = 1:2, h = dh_labels("h", 4L), g = dh_labels("g", 4L),
                      stringsAsFactors = FALSE)[, c("g", "h")]
  n <- nrow(data)
  data$y <- dh_outcome(n)
  data$y[1L] <- NA
  data$x <- dh_covariate(n)
  list(data = data, formula = "y ~ x + (1 | g) + (1 | h)", args = dh_t1())
}

# g crossed with h, 4 levels each and two rows in each combination, and g
# also a fixed factor, whose columns write its levels in the design sample,
# so that the analysis sample hides its own and the contributors that count
# them, with two outcomes missing in a Poisson T1 run.
dh_kept_levels_fixed <- function() {
  data <- expand.grid(rep = 1:2, h = dh_labels("h", 4L), g = dh_labels("g", 4L),
                      stringsAsFactors = FALSE)[, c("g", "h")]
  n <- nrow(data)
  data$count <- (seq_len(n) %% 4L) + 1
  data$count[1:2] <- NA
  list(data = data, formula = "count ~ g + (1 | g) + (1 | h)",
       args = c(list(family = "poisson"), dh_t1()))
}

# 2 subjects crossed with 4 items, one row in each combination, the subjects
# the disclosure unit and one outcome missing, and two further subjects whose
# one row lacks the covariate, so that they leave the design sample, in a
# Poisson T1 run. The contributors of the table, which sample.raw_vs_analysis
# hides with the detail 'secondary', count 4 subjects, which bound no level
# of the design sample.
dh_kept_levels_outside <- function() {
  data <- expand.grid(item = dh_labels("i", 4L), subject = dh_labels("s", 2L),
                      stringsAsFactors = FALSE)[, c("subject", "item")]
  data <- rbind(data, data.frame(subject = c("t01", "t02"), item = c("i01", "i02")))
  n <- nrow(data)
  data$count <- (seq_len(n) %% 4L) + 1
  data$count[1L] <- NA
  data$x <- dh_covariate(n)
  data$x[9:10] <- NA
  declaration <- dh_declaration(units = list(dh_participant("subject")))
  list(data = data, formula = "count ~ x + (1 | subject) + (1 | item)",
       args = c(list(family = "poisson", declaration = declaration), dh_t1()))
}

# 6 schools with the class labels c01 and c02 and two pupils in each
# combination, so that each school holds 4 rows, class declared within_parent
# in school with z assigned to it and missing in its last unit, and one pupil
# of each of the first two schools without an outcome, in a gaussian T1 run.
# The assignment checks count the 11 units of class, which are combinations
# of school and class and bound no level of the column class.
dh_kept_levels_within_parent <- function() {
  data <- expand.grid(rep = 1:2, class = dh_labels("c", 2L), school = dh_labels("S", 6L),
                      stringsAsFactors = FALSE)[, c("school", "class")]
  n <- nrow(data)
  data$pupil <- dh_labels("p", n)
  data$y <- dh_outcome(n)
  data$y[c(1L, 5L)] <- NA
  data$x <- dh_covariate(n)
  unit <- match(paste(data$school, data$class), unique(paste(data$school, data$class)))
  data$z <- ifelse(unit %% 2L == 1L, "a", "b")
  data$z[unit == max(unit)] <- NA
  declaration <- dh_declaration(
    units = list(dh_unit("school"),
                 dh_unit("class", nested_in = "school", id_scope = "within_parent"),
                 dh_unit("pupil", role = "participant", nested_in = "class")),
    assignment = list(list(column = "z", unit = "class", randomised = TRUE,
                           level = "between_unit")))
  list(data = data, formula = "y ~ x + (1 | school) + (1 | class)",
       args = c(list(declaration = declaration), dh_t1()))
}

# 4 subjects crossed with 4 items, each combination twice, with the key
# (subject, item, rep), rep declared with the categories 1 and 2, and no
# outcome missing, in a Poisson T1 run.
dh_kept_levels_replicates <- function() {
  data <- expand.grid(rep = 1:2, item = dh_labels("i", 4L), subject = dh_labels("s", 4L),
                      stringsAsFactors = FALSE)[, c("subject", "item", "rep")]
  n <- nrow(data)
  data$count <- (seq_len(n) %% 4L) + 1
  declaration <- dh_declaration(
    table = list(fields = list(list(name = "subject", type = "string"),
                               list(name = "item", type = "string"),
                               list(name = "rep", type = "integer",
                                    categories = list(1L, 2L)))),
    observation = list(key = list("subject", "item", "rep")))
  list(data = data, formula = "count ~ rep + (1 | subject) + (1 | item)",
       args = c(list(declaration = declaration, family = "poisson"), dh_t1()))
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
