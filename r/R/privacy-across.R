# Step 7 of the privacy filter, the rules across findings (docs/spec/privacy.md,
# Across findings). They compare the quantities of the samples that the
# findings of a document read: the table, the design sample, the analysis
# sample when the run read the outcome and the rows that an available finding
# reads when they are not its entry's sample, the rows of an assignment or of
# a pair of columns, which are the design sample, or else the analysis sample,
# when they hold its rows, and one sample when two findings read the same
# rows. The quantities of a sample are its rows, its contributors and, for
# each item, its levels, its levels with at least two rows and its levels with
# one row. The marks of a sample record which of them the document hides, as
# the logical members rows and contributors and, for each item, a logical
# vector named by privacy_measures. Each rule suppresses the counts that
# measure a hidden quantity with the detail 'secondary', which replaces the
# detail 'min_count' of a count below k.
#
# The rules run in this order. The clauses at the end of rule 1, under which
# the analysis sample loses a value, and rules 2 and 3 apply to the analysis
# sample first, and steps 6, 8 and 9 to the findings on it, which decides
# whether the analysis sample is shown. Before that, privacy_crossed_guarded()
# names the items of crossed columns whose findings of the T1 and T2 checks
# step 9 suppresses as a whole. Rule 1 then compares the other samples with
# the analysis sample when it is shown, the sizes of the levels
# that keep an analysed row included, and they lose what the analysis
# sample loses. Rule 5 extends what they lose there, the chain clause of
# rule 1 compares with the analysis sample the samples that a losing sample
# would have been compared with, rule 1 compares the other samples with one
# another, rule 2 applies to every sample and each finding takes the marks
# of its samples, rule 4, rule 5 and rule 6.

privacy_measures <- c("levels", "levels_with_two_rows", "levels_with_one_row")

# The values of measures that mark a count of columns, which gives back the
# levels of the items of its terms with an offset and which rule 6 alone
# suppresses.
privacy_term_measures <- c("term_levels", "table_term_levels")

privacy_across <- function(run, findings, k) {
  available <- vapply(findings, function(finding) isTRUE(finding$available), NA)
  if (!any(available)) {
    return(findings)
  }
  samples <- list(table = sample_rows(run, "table"), design = run$design)
  if (!is.null(run$analysis)) {
    samples$analysis <- run$analysis
  }
  main <- names(samples)
  finding_samples <- character(length(findings))
  for (i in which(available)) {
    finding <- findings[[i]]
    sample <- finding$entry[["sample"]]
    if (!identical(finding$rows, samples[[sample]])) {
      same <- Filter(function(name) identical(samples[[name]], finding$rows), names(samples))
      sample <- if (length(same)) same[1L] else paste0("rows ", length(samples))
      samples[[sample]] <- finding$rows
    }
    finding_samples[i] <- sample
  }
  items <- privacy_items(run, findings[available])
  quantities <- lapply(samples, function(rows) {
    support <- rows_support(run, rows)
    list(rows = length(rows), contributors = support$distinct,
         items = lapply(items, function(codes) privacy_item_quantities(run, codes, rows)))
  })
  # The items that the contributors count: the grouping factors with the
  # basis grouping_factors and the disclosure unit with the basis
  # disclosure_unit.
  basis <- rows_support(run, samples$table)$basis
  factor_items <- vapply(run$factors, function(keys) {
    privacy_item_index(items, list(value_codes(run, keys)))
  }, 0L)
  unit_item <- if (is.null(run$disclosure)) NA_integer_ else
    privacy_item_index(items, list(run$disclosure$codes))
  comparisons <- privacy_comparisons(samples, main)
  written <- privacy_written_items(run, findings[available], finding_samples[available], items,
                                   comparisons, samples)
  marks <- privacy_blank_marks(quantities)
  shown <- FALSE
  if (!is.null(samples$analysis)) {
    holders <- Filter(function(s) {
      s != "analysis" && all(samples$analysis %in% samples[[s]])
    }, names(samples))
    marks$analysis <- privacy_analysis_marks(findings[available], finding_samples[available], run,
                                             items, quantities, written, holders, basis,
                                             unit_item, k)
    guarded <- privacy_crossed_guarded(run, findings[available], finding_samples[available],
                                       items, samples, quantities, k)
    for (i in which(available)) {
      findings[[i]]$guarded <- findings[[i]]$tier %in% c("T1", "T2") &&
        !is.null(findings[[i]]$scope$factor) &&
        privacy_item_index(items, privacy_scope_item(run, findings[[i]])) %in% guarded
    }
    on_analysis <- which(available & finding_samples == "analysis")
    probes <- lapply(on_analysis, function(i) {
      finding <- privacy_across_finding(run, findings[[i]], "analysis", items, factor_items,
                                        unit_item, quantities, marks, k)
      privacy_absent(privacy_within(finding, k))
    })
    # The findings on the analysis sample share its rows and contributors, so
    # the bound that their written values place on the contributors decides
    # for all of them (privacy.md, Decisions).
    bounded <- privacy_contributors_bound(run, probes) >= k - 1L
    for (i in on_analysis) {
      findings[[i]]$bounded <- bounded
    }
    for (finding in probes) {
      finding$bounded <- bounded
      finding <- privacy_decision(finding, run, k)
      shown <- shown || !finding$whole
    }
  }
  beside <- vapply(comparisons, function(comparison) {
    "analysis" %in% c(comparison$larger, comparison$smaller)
  }, NA)
  # Rule 1 between the samples other than the analysis sample, as in a
  # document that does not show it, and the items whose levels a count
  # measures in each sample, which rule 6 reads.
  structural <- privacy_rule_1(quantities, comparisons[!beside], privacy_blank_marks(quantities),
                               privacy_blank_marks(quantities), k)
  measured <- privacy_measured_items(run, findings[available], finding_samples[available], items,
                                     k)
  lost <- privacy_lost(samples, quantities, comparisons, beside, shown, items, written,
                       marks$analysis, factor_items, unit_item, basis, k)
  marks <- privacy_rule_1(quantities, comparisons[!beside], lost, marks, k)
  for (s in names(marks)) {
    marks[[s]] <- privacy_or_marks(marks[[s]], lost[[s]])
    if (s != "analysis") {
      marks[[s]] <- privacy_rule_2(quantities[[s]], marks[[s]], k)
    }
  }
  # Rule 6 reads the marks of rule 1 between the samples other than the
  # analysis sample alone for those samples, and the final marks for the
  # analysis sample.
  ruled <- structural
  if (!is.null(samples$analysis)) {
    ruled$analysis <- marks$analysis
  }
  # Rule 4 compares the analysis sample only when it is shown, and no sample
  # that loses its rows beside it.
  keyed <- Filter(function(s) {
    s != "table" && (s != "analysis" || shown) && !lost[[s]]$rows
  }, names(samples))
  for (i in which(available)) {
    s <- finding_samples[i]
    findings[[i]] <- privacy_across_finding(run, findings[[i]], s, items, factor_items, unit_item,
                                            quantities, marks, k)
    if (findings[[i]]$check == "keys.duplicates" &&
        privacy_missing_key_close(run, samples[keyed], k)) {
      findings[[i]] <- privacy_suppress(findings[[i]], "missing_key_rows", "secondary",
                                        replace = TRUE)
    }
    if (s != "analysis") {
      findings[[i]] <- privacy_rule_5(run, findings[[i]], items, lost[[s]])
    }
    findings[[i]] <- privacy_rule_6(run, findings[[i]], s, samples, items, quantities, measured,
                                    ruled, k)
  }
  findings
}

# --- Marks ------------------------------------------------------------------------------

# The marks of every sample with no quantity hidden.
privacy_blank_marks <- function(quantities) {
  lapply(quantities, function(sample) {
    list(rows = FALSE, contributors = FALSE,
         items = lapply(sample$items, function(item) {
           structure(logical(length(privacy_measures)), names = privacy_measures)
         }))
  })
}

# The marks of one sample that hide what either of two marks hides.
privacy_or_marks <- function(a, b) {
  a$rows <- a$rows || b$rows
  a$contributors <- a$contributors || b$contributors
  for (i in seq_along(a$items)) {
    a$items[[i]] <- a$items[[i]] | b$items[[i]]
  }
  a
}

# Whether a quantity a of the larger of two samples exceeds the quantity b of
# the smaller by fewer than k, 0 included. A quantity that is 0 in the larger
# sample is not compared, since the difference is then 0 whatever the data.
privacy_close <- function(a, b, k) {
  a > 0 && a - b >= 0 && a - b < k
}

# The value of a quantity of a sample, the rows or the contributors when item
# is NULL, and otherwise the measure of the item at that position.
privacy_quantity <- function(quantity, member, item = NULL) {
  if (is.null(item)) quantity[[member]] else quantity$items[[item]][[member]]
}

# --- The analysis sample ----------------------------------------------------------------

# The marks of the analysis sample: the clauses at the end of rule 1, under
# which it loses a value, then rules 2 and 3. They compare quantities that
# the run computes whether or not the analysis sample is shown, so that the
# findings on it are final before step 7 decides whether it is shown.
#
# written lists the items whose levels a sample beside the analysis sample
# writes whatever rule 1 hides, by privacy_written_items(). Since rule 1
# cannot hide those levels, the analysis sample loses its levels of such an
# item when the other sample's exceed them by fewer than k. The written
# levels also bound the rows of the other sample from below, by twice the
# levels of an item that resolves as non-person there and by the levels
# otherwise, and with the basis disclosure_unit its contributors by twice the
# levels of a non-person item, so the analysis sample loses its rows, or its
# contributors, when the other sample's exceed them by fewer than k and that
# bound exceeds them. The levels with two rows that the written levels and
# rows of the other sample bound from above are protected by the sizes of
# the levels in privacy_lost(). With the basis disclosure_unit, the
# contributors are the levels of the disclosure unit, at unit_item, which
# the analysis sample loses with them.
#
# Each level of an item whose counts resolve as non-person in a sample
# holds two members or more, so that the rows of the sample, and with the
# basis disclosure_unit its contributors, are at least twice its levels,
# which the analysed levels bound from below. holders names the samples
# that hold the analysis sample's rows. Of their rows and contributors,
# those that exceed the analysis sample's by k or more, which rule 1 does
# not hide beside it, bound the levels that lose every outcome, and the
# analysis sample loses its levels of such an item when the fewer of them
# exceeds twice those levels by fewer than k, since they would then confine
# the levels that lose every outcome to fewer than k / 2 values, a single
# one when every level holds two members.
privacy_analysis_marks <- function(findings, finding_samples, run, items, quantities, written,
                                   holders, basis, unit_item, k) {
  analysis <- quantities$analysis
  marks <- privacy_blank_marks(quantities["analysis"])$analysis
  for (w in written) {
    if (w$smaller != "analysis" && w$larger != "analysis") {
      next
    }
    i <- w$item
    larger <- quantities[[w$larger]]
    smaller <- quantities[[w$smaller]]
    if (privacy_close(larger$items[[i]]$levels, smaller$items[[i]]$levels, k)) {
      marks$items[[i]][["levels"]] <- TRUE
    }
    if (w$smaller != "analysis") {
      next
    }
    item <- larger$items[[i]]
    least <- item$levels * (if (item$person) 1 else 2)
    if (privacy_close(larger$rows, analysis$rows, k) && least > analysis$rows) {
      marks$rows <- TRUE
    }
    if (identical(basis, "disclosure_unit") && !item$person &&
        privacy_close(larger$contributors, analysis$contributors, k) &&
        least > analysis$contributors) {
      marks$contributors <- TRUE
    }
  }
  for (s in holders) {
    other <- quantities[[s]]
    members <- c(if (other$rows - analysis$rows >= k) other$rows,
                 if (identical(basis, "disclosure_unit") &&
                     other$contributors - analysis$contributors >= k) other$contributors)
    if (!length(members)) {
      next
    }
    for (i in seq_along(other$items)) {
      if (!other$items[[i]]$person && min(members) - 2 * analysis$items[[i]]$levels < k) {
        marks$items[[i]][["levels"]] <- TRUE
      }
    }
  }
  if (privacy_close(privacy_key_bound(run, findings, k), analysis$rows, k)) {
    marks$rows <- TRUE
  }
  if (marks$contributors && identical(basis, "disclosure_unit") && !is.na(unit_item)) {
    marks$items[[unit_item]][["levels"]] <- TRUE
  }
  quartiles <- list()
  for (j in seq_along(findings)) {
    finding <- findings[[j]]
    if (finding$check == "structure.cluster_sizes" && finding_samples[j] == "analysis") {
      quartiles[[length(quartiles) + 1L]] <- list(
        item = privacy_item_index(items, privacy_scope_item(run, finding)),
        quantiles = privacy_written_quantiles(finding)
      )
    }
  }
  marks <- privacy_single_row_items(quantities$design, marks, basis, unit_item)
  marks <- privacy_rule_3(analysis, quantities$design, privacy_rule_2(analysis, marks, k),
                          quartiles, k)
  privacy_rule_2(analysis, privacy_single_row_items(quantities$design, marks, basis, unit_item),
                 k)
}

# The bound that a declared observation key places on the rows of the design
# sample, or 0 when keys.duplicates does not run, or when a column of the key
# is none whose levels the document or the declaration can give
# (privacy_bounded_columns()). The design sample holds at most as many
# distinct key values as the product of the levels of the key's columns
# there, and its rows exceed its distinct key values by its rows with a key
# value that repeat one, which duplicate_rows less duplicated_keys of
# keys.duplicates bound in the table, and by its rows without a key value,
# which missing_key_rows bounds. Beside the firing of rule 1, which shows
# fewer than k rows without an outcome, the levels of crossed columns that it
# shows to have kept an outcome, a column's declared categories, the two
# values of a column declared boolean or the columns of a fixed factor can
# give that product, which beside the analysed rows would give back the rows
# without an outcome (privacy.md, Across findings, the end of rule 1). The
# bound counts the repeated rows and the rows without a key value of the
# design sample, no more than those that the written counts of the table
# bound, so that it comes within k of the analysed rows wherever theirs
# does. A column other than a predictor or a column whose levels the
# declaration gives (privacy_declared_level_columns()) that has a level of
# fewer than k rows of the design sample, as the label of a pupil of two rows
# does, also gives 0: beside the firing of rule 1 such a level may have lost
# every outcome, so its analysed levels do not give its levels there, which
# rule 1 hides as the levels of an item, or no count writes, wherever the
# bound would come within k of the analysed rows.
privacy_key_bound <- function(run, findings, k) {
  declared <- any(vapply(findings, function(finding) {
    finding$check == "keys.duplicates" && isTRUE(finding$available)
  }, NA))
  if (!declared) {
    return(0)
  }
  key <- comparison_form(as.character(observation_key_columns(run$declaration)))
  if (!all(key %in% privacy_bounded_columns(run))) {
    return(0)
  }
  given <- c(names(run$ir$predictors), privacy_declared_level_columns(run$declaration))
  levels <- vapply(key, function(column) {
    codes <- value_codes(run, column, run$design)
    sizes <- table(codes[!is.na(codes)])
    if (!column %in% given && (!length(sizes) || any(sizes < k))) {
      return(NA_real_)
    }
    as.numeric(length(sizes))
  }, 0)
  if (anyNA(levels)) {
    return(0)
  }
  codes <- value_codes(run, key, run$design)
  keyed <- codes[!is.na(codes)]
  prod(levels) + length(keyed) - length(unique(keyed)) + sum(is.na(codes))
}

# The columns whose levels in the design sample the document or the
# declaration can give: the predictors and grouping columns of the IR, the
# label columns of the declared units and the columns whose levels the
# declaration gives (privacy_declared_level_columns()), as keys.
privacy_bounded_columns <- function(run) {
  declaration <- run$declaration
  units <- lapply(names(declared_units(declaration)), function(name) {
    unit_label_columns(declaration, name)
  })
  unique(c(names(run$ir$predictors), run$grouping_columns, unlist(units),
           privacy_declared_level_columns(declaration)))
}

# The columns of the table block whose levels the declaration gives, those
# with declared categories, which the table reader and audit() keep within
# them whether or not the formula reads the column, and those of type
# 'boolean', which hold the values false and true alone (tables.md), as keys.
privacy_declared_level_columns <- function(declaration) {
  declared <- Filter(function(field) {
    !is.null(field[["categories"]]) || identical(field[["type"]], "boolean")
  }, declaration[["table"]][["fields"]])
  comparison_form(vapply(declared, function(field) field[["name"]], ""))
}

# The items of two crossed columns whose findings of the T1 and T2 checks
# step 9 suppresses as a whole (privacy.md, Decisions). When
# structure.label_incidence finds two columns crossed in the rows that it
# reads, those of the design sample in which both columns are present, each
# level of one column's item holds every level of the other's there. When
# the item's counts resolve as non-person there and some level of it would
# keep at most one member after losing fewer than k of its rows, the class
# person of its counts in the analysis sample, which a finding suppressed as
# a whole by Decisions shows, would bound from below the rows without an
# outcome in that level, which rule 1 can show to be fewer than k. The
# conditions read no outcome.
privacy_crossed_guarded <- function(run, findings, finding_samples, items, samples, quantities,
                                    k) {
  out <- integer(0)
  if (is.null(samples$analysis) || is.null(run$disclosure)) {
    return(out)
  }
  for (j in seq_along(findings)) {
    finding <- findings[[j]]
    s <- finding_samples[j]
    if (finding$check != "structure.label_incidence" ||
        !identical(finding$values[["relation"]], "crossed")) {
      next
    }
    ends <- vapply(finding$items[["combinations"]], function(codes) {
      privacy_item_index(items, list(codes))
    }, 0L)
    for (a in ends[!is.na(ends)]) {
      if (!quantities[[s]]$items[[a]]$person &&
          privacy_reducible(items[[a]], run$disclosure$codes, samples[[s]], k)) {
        out <- c(out, a)
      }
    }
  }
  unique(out)
}

# Whether some level of an item, in the rows given, would hold at most one
# member of the disclosure unit after losing fewer than k of its rows: its
# rows less those of its member with the most rows there and less those
# without a member number fewer than k. codes are the level codes of the
# item and members the codes of the members, in every row of the table.
privacy_reducible <- function(codes, members, rows, k) {
  level <- codes[rows]
  member <- members[rows]
  keep <- !is.na(level)
  level <- level[keep]
  member <- member[keep]
  if (!length(level)) {
    return(FALSE)
  }
  sizes <- tabulate(level)
  labelled <- !is.na(member)
  most <- integer(length(sizes))
  if (any(labelled)) {
    # The rows of each pair of a level and a member, numbered in the order of
    # first appearance, and the largest of them in each level.
    key <- (level[labelled] - 1) * (max(member[labelled]) + 1) + member[labelled]
    first <- !duplicated(key)
    rows_of_pair <- tabulate(match(key, key[first]))
    largest <- tapply(rows_of_pair, level[labelled][first], max)
    most[as.integer(names(largest))] <- largest
  }
  removal <- sizes - most - tabulate(level[!labelled], nbins = length(sizes))
  any(sizes > 0L & removal < k)
}

# The lower bound that the findings on the analysis sample place on its
# contributors (privacy.md, Decisions): 2 when a by_unit count or ratio
# resolves as non-person over rows that hold a level of its item, since each
# level then holds two members or more, twice the largest written by_unit
# count of class non_person whose item holds each member of the disclosure
# unit in one level of the design sample, and dominance.contributors + 1
# when `dominated` of a finding whose support counts the analysis sample is
# false, 0 without any of these.
privacy_contributors_bound <- function(run, findings) {
  bound <- 0
  dominance <- read_registry()[["privacy"]][["dominance"]][["contributors"]]
  for (finding in findings) {
    if (identical(finding$entry[["sample"]], "analysis") && isFALSE(finding$support$dominated)) {
      bound <- max(bound, dominance + 1)
    }
    defined <- finding$entry[["statistics"]]
    for (name in names(finding$values)) {
      statistic <- finding$statistics[[name]]
      if (!identical(defined[[name]][["count_class"]], "by_unit") ||
          !identical(statistic$count_class, "non_person")) {
        next
      }
      item <- finding$items[[name]]
      if (is.null(item) && !is.null(finding$scope$factor)) {
        item <- privacy_scope_item(run, finding)
      }
      if (is.null(item) || any(vapply(item, is.null, NA))) {
        next
      }
      codes <- privacy_item_codes(item)
      if (all(is.na(codes[finding$rows]))) {
        next
      }
      bound <- max(bound, 2)
      if (statistic$kind == "count" && privacy_written(finding, name) && !is.null(run$disclosure) &&
          privacy_members_nested(codes, run$disclosure$codes, run$design)) {
        bound <- max(bound, 2 * finding$values[[name]])
      }
    }
  }
  bound
}

# Whether each member of the disclosure unit lies in one level of an item in
# the rows given, among the rows that hold both. codes and members are the
# codes of every row of the table.
privacy_members_nested <- function(codes, members, rows) {
  level <- codes[rows]
  member <- members[rows]
  keep <- !is.na(level) & !is.na(member)
  if (!any(keep)) {
    return(TRUE)
  }
  level <- level[keep]
  member <- member[keep]
  first <- !duplicated(cbind(member, level))
  !anyDuplicated(member[first])
}

# The levels of an item none of whose levels holds two rows of the design
# sample are the analysis sample's rows whatever the outcome (rule 3 of
# Across findings), and with the basis disclosure_unit, when the item is the
# disclosure unit, its contributors too. So the analysis sample loses its
# rows when it loses its levels of such an item, or the contributors that
# count them, and it loses its levels of every such item, and the
# contributors that count them, when it loses its rows.
privacy_single_row_items <- function(design, marks, basis, unit_item) {
  single <- which(vapply(design$items, function(item) {
    item$levels > 0L && item$levels_with_two_rows == 0L
  }, NA))
  if (!length(single)) {
    return(marks)
  }
  unit <- identical(basis, "disclosure_unit") && !is.na(unit_item) && unit_item %in% single
  if (any(vapply(single, function(i) marks$items[[i]][["levels"]], NA)) ||
      (unit && marks$contributors)) {
    marks$rows <- TRUE
  }
  if (marks$rows) {
    for (i in single) {
      marks$items[[i]][["levels"]] <- TRUE
    }
    marks$contributors <- marks$contributors || unit
  }
  marks
}

# The items whose levels a sample writes whatever rule 1 hides, each as a
# list of the item's position and the two samples compared, the larger and
# the smaller, one of which is the analysis sample. A categorical variable of
# a term of the IR, or the combination of the categorical variables of a
# term, that divides the rows of the design sample, or of the table, into
# the levels of an item gives the term columns that count the item's levels
# there: in the design sample, which kept and empty_cells of
# design.rank_deficiency and df of design.collinearity count, and in the
# table, which columns of design.rank_deficiency and dimension of
# identifiability.levels_vs_dimension count, all of them non-person counts
# that no comparison with the analysis sample suppresses (rule 6 of Across
# findings). So does a fixed term on the rows of an assignment that hold the
# analysis sample's rows or lie in them, whose columns design_df of
# assignment.design_df counts there, and more generally a term of a count
# of columns, marked term_levels, of a finding on a sample other than these
# three. When structure.label_incidence finds two columns crossed in a
# sample, of which one holds the analysis sample's rows, the levels of their
# combinations there are the product of the levels of the two columns, which
# that sample writes or the analysis sample's bound from below.
privacy_written_items <- function(run, findings, finding_samples, items, comparisons, samples) {
  written <- list()
  add <- function(i, larger, smaller) {
    written[[length(written) + 1L]] <<- list(item = i, larger = larger, smaller = smaller)
  }
  # Every pair of compared samples of which one is the analysis sample and
  # the other the sample given.
  beside_analysis <- function(sample) {
    Filter(function(comparison) {
      setequal(c(comparison$larger, comparison$smaller), c(sample, "analysis"))
    }, comparisons)
  }
  if (!any(vapply(comparisons, function(c) "analysis" %in% c(c$larger, c$smaller), NA))) {
    return(written)
  }
  for (larger in c("design", "table")) {
    for (i in privacy_variable_items(run, items, samples[[larger]])) {
      add(i, larger, "analysis")
    }
  }
  for (j in seq_along(findings)) {
    finding <- findings[[j]]
    sample <- finding_samples[j]
    if (sample %in% c("table", "design", "analysis")) {
      next
    }
    defined <- finding$entry[["statistics"]]
    if (!any(vapply(names(finding$values), function(name) {
      identical(defined[[name]][["measures"]], "term_levels")
    }, NA))) {
      next
    }
    terms <- privacy_finding_terms(run, finding)
    for (i in privacy_term_items(run, items, terms, samples[[sample]])) {
      for (comparison in beside_analysis(sample)) {
        add(i, comparison$larger, comparison$smaller)
      }
    }
  }
  for (j in seq_along(findings)) {
    finding <- findings[[j]]
    sample <- finding_samples[j]
    if (finding$check != "structure.label_incidence" || sample == "analysis" ||
        !identical(finding$values[["relation"]], "crossed")) {
      next
    }
    i <- privacy_item_index(items, finding$items[["combinations"]])
    if (is.na(i)) {
      next
    }
    for (comparison in beside_analysis(sample)) {
      add(i, comparison$larger, comparison$smaller)
    }
  }
  written
}

# The items into whose levels a categorical variable of a term of the IR, in
# the fixed part or in a random term, or the combination of the categorical
# variables of a term, divides the rows given.
privacy_variable_items <- function(run, items, rows) {
  terms <- c(run$ir$fixed$terms,
             unlist(lapply(run$ir$random, function(random) random$terms), recursive = FALSE))
  privacy_term_items(run, items, terms, rows)
}

# The positions of the items into whose levels a categorical variable of one
# of the terms given, or the combination of the categorical variables of one
# of them, divides the rows given, the rows without a level included. The
# variables and the items are compared on those rows alone, since a row that
# the rows leave out, such as a row whose grouping column alone is missing,
# changes no count of columns over them. A variable that carries a level, in
# a term that '||' has split, gives the term one column whatever its levels,
# so it divides the rows into no levels here.
privacy_term_items <- function(run, items, terms, rows) {
  found <- integer(0)
  for (term in terms) {
    categorical <- character(0)
    for (variable in term$variables) {
      if (isTRUE(variable$coding %in% c("contrast", "indicator")) && is.null(variable$level)) {
        categorical <- c(categorical, variable$variable)
      }
    }
    sets <- as.list(categorical)
    if (length(categorical) > 1L) {
      sets[[length(sets) + 1L]] <- categorical
    }
    for (set in sets) {
      found <- c(found, privacy_items_in(items, value_codes(run, comparison_form(set)), rows))
    }
  }
  unique(found)
}

# The positions of the items that divide the rows given into the same levels
# as the codes, every such item when two items divide them alike although
# they divide the table differently.
privacy_items_in <- function(items, codes, rows) {
  target <- privacy_item_codes(codes[rows])
  which(vapply(items, function(item) identical(privacy_item_codes(item[rows]), target), NA))
}

# --- Rules 1 and 5 ----------------------------------------------------------------------

# The quantities that the samples lose beside the analysis sample, as marks.
# Rule 1 compares each sample with the analysis sample when it is shown: the
# rows, the contributors and the levels of every item whose counts of levels
# resolve as person counts there. A sample whose written levels and counts
# can give back the sizes of its levels of an item, because it keeps those
# levels or writes them through the columns of a term, loses its rows when
# those sizes, beside the analysis sample's rows, would give back an
# outcome-derived value (privacy_sizes_close). The levels of an item whose
# counts resolve as non-person are compared when the sample loses its rows or
# its contributors, since each such level holds two members or more, so that
# its written levels would bound the members and rows that the sample loses.
# A sample that holds the analysis sample's rows loses the rows, contributors,
# levels and levels with two rows of an item that the analysis sample loses,
# since its written quantity would show that rule 1 did not fire against the
# hidden one. Rule 5 then extends a loss of the levels, or of the levels with
# two rows, of an item to every count of its levels and, when the
# contributors count the item's levels, to the contributors. A quantity that
# a sample loses is compared with no other sample (privacy_rule_1), since
# whether that comparison fires would bound it, and a sample that it would
# have been compared with, which lies in it and does not hold the analysis
# sample's rows, loses the quantity unless the analysis sample's exceeds it
# by k or more. The two steps repeat until nothing changes.
privacy_lost <- function(samples, quantities, comparisons, beside, shown, items, written,
                         hidden, factor_items, unit_item, basis, k) {
  lost <- privacy_blank_marks(quantities)
  if (!shown) {
    return(lost)
  }
  for (comparison in comparisons[beside]) {
    larger <- quantities[[comparison$larger]]
    smaller <- quantities[[comparison$smaller]]
    loser <- comparison$loser
    for (member in c("rows", "contributors")) {
      if (privacy_close(larger[[member]], smaller[[member]], k)) {
        lost[[loser]][[member]] <- TRUE
      }
    }
    # A quantity that the analysis sample loses is lost by every sample that
    # holds its rows, whose written quantity would show that rule 1 did not
    # fire and so bound the hidden one from above, unless it is 0 there,
    # which rule 1 does not compare.
    if (comparison$smaller == "analysis" && comparison$loser == comparison$larger) {
      for (member in c("rows", "contributors")) {
        lost[[loser]][[member]] <- lost[[loser]][[member]] || hidden[[member]]
      }
      for (i in seq_along(larger$items)) {
        for (measure in privacy_measures[1:2]) {
          if (hidden$items[[i]][[measure]] && larger$items[[i]][[measure]] > 0) {
            lost[[loser]]$items[[i]][[measure]] <- TRUE
          }
        }
      }
    }
    compare_items <- function(person) {
      for (i in seq_along(larger$items)) {
        if (larger$items[[i]]$person != person) {
          next
        }
        for (measure in privacy_measures[1:2]) {
          if (privacy_close(larger$items[[i]][[measure]], smaller$items[[i]][[measure]], k)) {
            lost[[loser]]$items[[i]][[measure]] <<- TRUE
          }
        }
      }
    }
    compare_items(TRUE)
    if (comparison$smaller == "analysis" && comparison$loser == comparison$larger) {
      for (i in seq_along(larger$items)) {
        through_columns <- any(vapply(written, function(w) {
          identical(w$item, i) && w$larger == comparison$larger && w$smaller == "analysis"
        }, NA))
        if ((through_columns || !any(lost[[loser]]$items[[i]][1:2])) &&
            privacy_sizes_close(items[[i]], samples[[comparison$larger]], samples$analysis,
                                quantities$analysis$items[[i]]$person, k)) {
          lost[[loser]]$rows <- TRUE
        }
      }
    }
    if (lost[[loser]]$rows || lost[[loser]]$contributors) {
      compare_items(FALSE)
    }
  }
  holds_analysis <- function(s) all(samples$analysis %in% samples[[s]])
  repeat {
    before <- lost
    for (s in setdiff(names(lost), "analysis")) {
      for (i in seq_along(lost[[s]]$items)) {
        if (any(lost[[s]]$items[[i]][1:2])) {
          lost[[s]]$items[[i]][] <- TRUE
          if ((identical(basis, "grouping_factors") && i %in% factor_items) ||
              identical(i, unit_item)) {
            lost[[s]]$contributors <- TRUE
          }
        }
      }
    }
    for (comparison in comparisons[!beside]) {
      larger <- comparison$larger
      smaller <- comparison$smaller
      if (holds_analysis(smaller)) {
        next
      }
      chain <- function(member, item = NULL) {
        is_lost <- function(s) {
          if (is.null(item)) lost[[s]][[member]] else lost[[s]]$items[[item]][[member]]
        }
        if (is_lost(larger) && !is_lost(smaller) &&
            privacy_quantity(quantities$analysis, member, item) -
              privacy_quantity(quantities[[smaller]], member, item) < k) {
          if (is.null(item)) {
            lost[[smaller]][[member]] <<- TRUE
          } else {
            lost[[smaller]]$items[[item]][[member]] <<- TRUE
          }
        }
      }
      for (member in c("rows", "contributors")) {
        chain(member)
      }
      for (i in seq_along(quantities[[larger]]$items)) {
        if (quantities[[larger]]$items[[i]]$person) {
          for (measure in privacy_measures[1:2]) {
            chain(measure, i)
          }
        }
      }
    }
    if (identical(lost, before)) {
      return(lost)
    }
  }
}

# Whether the sizes in a larger sample of the levels of an item that hold an
# analysed row would, beside the rows of the analysis sample, give back an
# outcome-derived value: the rows that the larger sample holds in those of
# them that have two rows or more there exceed the analysed rows in them by
# fewer than k, 0 included, or, for an item whose counts of levels resolve as
# person counts in the analysis sample, they leave its levels with one row a
# single possible value. Besides the levels of one row in the larger sample,
# the fewest that can have one analysed row are as many as the rows lost
# beyond those that leave each level two rows, and the most as many as the
# rows lost reduce to one row, from the smallest. When fewer than k levels
# can have one analysed row, rule 2 hides the analysed levels with two rows,
# and the larger sample loses them. codes are the level codes of the item in
# every row of the table.
privacy_sizes_close <- function(codes, larger_rows, analysis_rows, person, k) {
  bins <- max(c(codes, 0L), na.rm = TRUE)
  analysed <- tabulate(codes[analysis_rows], nbins = bins)
  sizes <- tabulate(codes[larger_rows], nbins = bins)
  kept <- analysed > 0L
  several <- kept & sizes >= 2L
  if (!any(several)) {
    return(FALSE)
  }
  lost_rows <- sum(sizes[several]) - sum(analysed[several])
  if (lost_rows < k) {
    return(TRUE)
  }
  if (!person) {
    return(FALSE)
  }
  most <- sum(cumsum(sort(sizes[several] - 1L)) <= lost_rows)
  fewest <- max(0, lost_rows - sum(sizes[several] - 2L))
  fewest == most
}

# Rule 1 between the samples other than the analysis sample: the rows and
# contributors, and the levels and levels with two rows of each item whose
# counts of levels resolve as person counts in the larger sample, which
# holds the levels that the difference counts. A quantity that either sample
# loses beside the analysis sample is not compared.
privacy_rule_1 <- function(quantities, comparisons, lost, marks, k) {
  for (comparison in comparisons) {
    larger <- comparison$larger
    smaller <- comparison$smaller
    loser <- comparison$loser
    for (member in c("rows", "contributors")) {
      if (!lost[[larger]][[member]] && !lost[[smaller]][[member]] &&
          privacy_close(quantities[[larger]][[member]], quantities[[smaller]][[member]], k)) {
        marks[[loser]][[member]] <- TRUE
      }
    }
    for (i in seq_along(quantities[[larger]]$items)) {
      if (!quantities[[larger]]$items[[i]]$person) {
        next
      }
      for (measure in privacy_measures[1:2]) {
        if (!lost[[larger]]$items[[i]][[measure]] && !lost[[smaller]]$items[[i]][[measure]] &&
            privacy_close(quantities[[larger]]$items[[i]][[measure]],
                          quantities[[smaller]]$items[[i]][[measure]], k)) {
          marks[[loser]]$items[[i]][[measure]] <- TRUE
        }
      }
    }
  }
  marks
}

# Rule 5 for one finding on a sample other than the analysis sample, given
# what the sample loses beside the analysis sample: every real when it loses
# its rows, and for each item whose levels or levels with two rows it loses,
# the counts that name a count of the item's levels in part_of, directly or
# through another such count, the counts of an item that combines it with
# another, and the reals of a finding whose scope names it as its factor, or
# names no factor while its entry reads grouping_factors. The counts that
# measure the item's levels take the marks of the sample.
privacy_rule_5 <- function(run, finding, items, lost) {
  defined <- finding$entry[["statistics"]]
  reals <- Filter(function(name) finding$statistics[[name]]$kind %in% c("real", "reals"),
                  names(finding$values))
  if (lost$rows) {
    finding <- privacy_suppress(finding, reals, "secondary")
  }
  hit <- which(vapply(lost$items, function(item) any(item[1:2]), NA))
  if (!length(hit)) {
    return(finding)
  }
  factor <- if (is.null(finding$scope$factor)) NULL else privacy_scope_item(run, finding)
  counted <- Filter(function(name) {
    isTRUE(defined[[name]][["measures"]] %in% privacy_measures) &&
      privacy_item_index(items, finding$items[[name]] %||% factor) %in% hit
  }, names(finding$values))
  counted <- c(counted, privacy_parts(finding, counted, person = FALSE))
  combined <- Filter(function(name) {
    item <- finding$items[[name]]
    length(item) == 2L && !any(vapply(item, is.null, NA)) &&
      any(vapply(item, function(codes) privacy_item_index(items, list(codes)) %in% hit, NA))
  }, names(finding$values))
  reads_item <- if (is.null(factor)) {
    "grouping_factors" %in% unlist(finding$entry[["reads"]])
  } else {
    privacy_item_index(items, factor) %in% hit
  }
  names <- c(counted, combined, if (reads_item) reals)
  privacy_suppress(finding, unique(names), "secondary", replace = TRUE)
}

# --- Rule 6 ----------------------------------------------------------------------------

# Rule 6 for one finding on a sample: a count of columns that measures the
# levels of the items of its terms with an offset, marked term_levels for the
# columns kept over the rows of the finding and table_term_levels for the
# columns of the IR, which count the levels of the table and so give back
# those of these rows too, is suppressed when the document hides the levels
# of one of these items in those rows, or in the table for table_term_levels.
# The items of the terms in some rows are those into whose levels a variable
# of the terms divides those rows. The document hides them there when a
# finding there has a count that measures them, and that count resolves as a
# person count below k or every such finding fails the minimum-count or the
# dominance rule (steps 2 and 3), or rule 1 between samples other than the
# analysis sample, compared as in a document that does not show it, hides
# them, or, in the analysis sample, any rule does. In the table, where no
# finding of registry 0.1.0 has such a count, it hides them when rule 1 does
# and a finding on a sample other than the analysis sample has a count that
# measures them. marks are those of rule 1 alone for a sample other than the
# analysis sample and the final marks for the analysis sample, so that
# whether the rule suppresses a count of a design-structure sample depends on
# no outcome-derived value.
privacy_rule_6 <- function(run, finding, sample, samples, items, quantities, measured, marks, k) {
  defined <- finding$entry[["statistics"]]
  names <- Filter(function(name) {
    isTRUE(defined[[name]][["measures"]] %in% privacy_term_measures)
  }, names(finding$values))
  if (!length(names)) {
    return(finding)
  }
  terms <- privacy_finding_terms(run, finding)
  # Whether a finding on a sample other than the analysis sample has a count
  # that measures the levels of the item at position i.
  counted_elsewhere <- function(i) {
    any(vapply(setdiff(names(measured), "analysis"), function(s) {
      !is.null(measured[[s]][[as.character(i)]])
    }, NA))
  }
  hidden <- function(s) {
    any(vapply(privacy_term_items(run, items, terms, samples[[s]]), function(i) {
      counted <- measured[[s]][[as.character(i)]]
      item <- quantities[[s]]$items[[i]]
      ruled <- isTRUE(marks[[s]]$items[[i]][["levels"]])
      if (is.null(counted)) {
        return(s == "table" && ruled && counted_elsewhere(i))
      }
      (item$person && (item$levels < k || counted$fails)) || ruled
    }, NA))
  }
  here <- hidden(sample)
  table <- sample != "table" && !here &&
    any(vapply(names, function(name) defined[[name]][["measures"]] == "table_term_levels", NA)) &&
    hidden("table")
  suppressed <- Filter(function(name) {
    here || (table && defined[[name]][["measures"]] == "table_term_levels")
  }, names)
  privacy_suppress(finding, suppressed, "secondary", replace = TRUE)
}

# The items whose levels a count of an available finding measures, for each
# sample, as a list by sample of lists named by the position of the item,
# each recording whether every finding on the sample with such a count fails
# the minimum-count or the dominance rule (step 2), which then suppresses
# every such count of a person item.
privacy_measured_items <- function(run, findings, finding_samples, items, k) {
  measured <- list()
  for (j in seq_along(findings)) {
    finding <- findings[[j]]
    s <- finding_samples[j]
    defined <- finding$entry[["statistics"]]
    fails <- finding$support$distinct < k || isTRUE(finding$support$dominated)
    for (name in names(finding$values)) {
      if (!identical(defined[[name]][["measures"]], "levels")) {
        next
      }
      i <- privacy_item_index(items, finding$items[[name]] %||% privacy_scope_item(run, finding))
      if (is.na(i)) {
        next
      }
      key <- as.character(i)
      before <- measured[[s]][[key]]
      measured[[s]][[key]] <- list(fails = fails && (is.null(before) || before$fails))
    }
  }
  measured
}

# The terms whose columns the counts of a finding count: the term of its
# scope element, fixed or random, or every fixed term when the element names
# no term.
privacy_finding_terms <- function(run, finding) {
  term <- finding$scope$term
  if (is.null(term)) {
    return(run$ir$fixed$terms)
  }
  if (identical(finding$entry[["scope"]], "random_term")) {
    for (random in run$ir$random) {
      if (identical(random$name, term) && identical(random$factor, finding$scope$factor)) {
        return(random$terms)
      }
    }
    return(list())
  }
  Filter(function(fixed) identical(fixed$name, term), run$ir$fixed$terms)
}

# --- Rules 2 and 3 ----------------------------------------------------------------------

# Rule 2 in one sample: for an item whose counts of levels resolve as person
# counts there, the levels with one and with at least two rows when either
# numbers fewer than k, the levels with at least two rows when the levels are
# hidden, and the levels with one row when the levels with at least two rows
# are hidden. For a non-person item, the levels with at least two rows are
# the levels, so that either hides the other.
privacy_rule_2 <- function(quantity, marks, k) {
  for (i in seq_along(quantity$items)) {
    item <- quantity$items[[i]]
    hidden <- marks$items[[i]]
    if (item$person) {
      small <- item$levels_with_one_row < k || item$levels_with_two_rows < k
      if (small || hidden[["levels"]]) {
        hidden[["levels_with_two_rows"]] <- TRUE
      }
      if (small || hidden[["levels_with_two_rows"]]) {
        hidden[["levels_with_one_row"]] <- TRUE
      }
    } else if (any(hidden[1:2])) {
      hidden[1:2] <- TRUE
    }
    marks$items[[i]] <- hidden
  }
  marks
}

# Rule 3 in the analysis sample: the rows hold one row of each level with
# one row and at least two of each other level, and at least each written
# quantile of the level sizes from its position on, so that rows below that
# sum without a level of one row, beside the levels, show that some level has
# one row and so that the smallest level size is 1. When rule 2 hides the
# levels with one row of a person item, the levels are hidden in that case,
# and the rows too when they are fewer than 2k beside k contributors or more,
# since a finding that passes the minimum-count rule shows that each grouping
# factor has k levels or more. An item none of whose levels holds two rows of
# the design sample is left out, since its levels in the analysis sample are
# its rows whatever the outcome. quartiles lists, for each finding of
# structure.cluster_sizes on the sample, the position of its item and the
# quantiles that it writes.
privacy_rule_3 <- function(quantity, design, marks, quartiles, k) {
  for (i in seq_along(quantity$items)) {
    item <- quantity$items[[i]]
    if (!item$person || !marks$items[[i]][["levels_with_one_row"]] ||
        design$items[[i]]$levels_with_two_rows == 0L) {
      next
    }
    written <- list()
    for (q in quartiles) {
      if (identical(q$item, i)) {
        written <- q$quantiles
      }
    }
    if (quantity$rows < privacy_rows_without_singletons(item$levels, written)) {
      marks$items[[i]][["levels"]] <- TRUE
      if (quantity$rows < 2 * k && quantity$contributors >= k) {
        marks$rows <- TRUE
      }
    }
  }
  marks
}

# The quantiles of the level sizes that a finding of structure.cluster_sizes
# writes after steps 1 to 6, as a list of their p and values.
privacy_written_quantiles <- function(finding) {
  out <- list()
  for (name in names(finding$values)) {
    quantile <- finding$statistics[[name]]$quantile
    if (!is.null(quantile) && identical(quantile[["n"]], "levels") &&
        privacy_written(finding, name)) {
      out[[length(out) + 1L]] <- list(p = quantile[["p"]], value = finding$values[[name]])
    }
  }
  out
}

# The fewest rows that J levels can hold when none has one row and each
# written quantile of their sizes, at position ceil(J p) of the sizes in
# increasing order, bounds the sizes from it on: the sum over the positions
# of the larger of 2 and the largest quantile at or before the position.
privacy_rows_without_singletons <- function(levels, quantiles) {
  floor <- rep(2, levels)
  for (quantile in quantiles) {
    position <- quantile_position(levels, quantile$p)
    if (position >= 1L && position <= levels) {
      later <- position:levels
      floor[later] <- pmax(floor[later], quantile$value)
    }
  }
  sum(floor)
}

# The position ceil(n p), counted from 1, of the p-quantile of n values, p a
# decimal string m / 10^d, in integer arithmetic, and 1 for the minimum.
quantile_position <- function(n, p) {
  if (p %in% c("0", "1")) {
    return(if (p == "0") 1 else n)
  }
  digits <- sub("^0\\.", "", p)
  scale <- 10^nchar(digits)
  max(1, (n * as.numeric(digits) + scale - 1) %/% scale)
}

# --- Rule 4 -----------------------------------------------------------------------------

# Rule 4: whether the rows of the table with a missing value in a column of
# the observation key and the rows of the table that one of the samples
# given leaves out, one of which holds the other, differ by fewer than k
# rows, 0 included, so that missing_key_rows of keys.duplicates beside the
# rows of the table and of that sample would give back the rows by which
# they differ, such as the rows with a key value but no value of a predictor.
privacy_missing_key_close <- function(run, samples, k) {
  key <- comparison_form(as.character(observation_key_columns(run$declaration)))
  missing <- which(is.na(value_codes(run, key)))
  for (rows in samples) {
    left_out <- setdiff(seq_len(run$table$rows), rows)
    nested <- all(missing %in% left_out) || all(left_out %in% missing)
    if (nested && abs(length(left_out) - length(missing)) < k) {
      return(TRUE)
    }
  }
  FALSE
}

# --- Samples, items and findings --------------------------------------------------------

# The comparisons of rule 1: every two samples one of which holds the
# other's rows, as the larger and the smaller, the table before the design
# sample and the design sample before the analysis sample when they hold the
# same rows, with the sample that loses its value. The rows of an assignment
# or of a pair lose against the table, the design sample and the analysis
# sample, and otherwise the larger sample loses.
privacy_comparisons <- function(samples, main) {
  comparisons <- list()
  for (a in seq_along(samples)) {
    for (b in seq_along(samples)) {
      larger <- samples[[a]]
      smaller <- samples[[b]]
      if (a == b || length(smaller) > length(larger) ||
          (length(smaller) == length(larger) && b < a) || !all(smaller %in% larger)) {
        next
      }
      pair <- names(samples)[c(a, b)]
      loser <- if (pair[1L] %in% main && !pair[2L] %in% main) pair[2L] else pair[1L]
      comparisons[[length(comparisons) + 1L]] <- list(larger = pair[1L], smaller = pair[2L],
                                                      loser = loser)
    }
  }
  comparisons
}

# The items whose quantities the rules across findings compare: the grouping
# factors of the IR, the declared units that do not count as absent and the
# items by which the by_unit counts of the findings resolve, each as the
# level codes of every row of the table. Items that divide the rows into the
# same levels are one item.
privacy_items <- function(run, findings) {
  candidates <- lapply(run$factors, function(keys) value_codes(run, keys))
  for (unit in names(declared_units(run$declaration))) {
    candidates[[length(candidates) + 1L]] <-
      value_codes(run, unit_label_columns(run$declaration, unit))
  }
  for (finding in findings) {
    for (item in finding$items) {
      if (!any(vapply(item, is.null, NA))) {
        candidates[[length(candidates) + 1L]] <- privacy_item_codes(item)
      }
    }
  }
  items <- list()
  for (codes in lapply(candidates, privacy_item_codes)) {
    if (!any(vapply(items, identical, NA, codes))) {
      items[[length(items) + 1L]] <- codes
    }
  }
  items
}

# The level codes of an item given as the codes of one item, or of two whose
# combinations form its levels, numbered in the order of first appearance,
# with NA for a row without a level.
privacy_item_codes <- function(item) {
  if (!is.list(item)) {
    item <- list(item)
  }
  level <- as.numeric(item[[1L]])
  if (length(item) == 2L) {
    level <- pair_codes(level, as.numeric(item[[2L]]))
  }
  present <- !is.na(level)
  codes <- rep(NA_integer_, length(level))
  codes[present] <- match(level[present], unique(level[present]))
  codes
}

# The position of an item among the items of the rules, or NA for an item
# that the finding lacks.
privacy_item_index <- function(items, item) {
  if (is.null(item) || any(vapply(item, is.null, NA))) {
    return(NA_integer_)
  }
  codes <- privacy_item_codes(item)
  found <- which(vapply(items, identical, NA, codes))
  if (length(found)) found[1L] else NA_integer_
}

# The quantities of an item in some rows: whether its counts of levels
# resolve as person counts there, its levels, those with at least two rows
# and those with one row.
privacy_item_quantities <- function(run, codes, rows) {
  sizes <- tabulate(codes[rows])
  list(person = resolve_count_class(run, list(codes), rows) == "person",
       levels = sum(sizes > 0L), levels_with_two_rows = sum(sizes >= 2L),
       levels_with_one_row = sum(sizes == 1L))
}

# One finding on a sample with the marks of the samples: its support and the
# counts that measure a hidden quantity, with the detail 'secondary' in place
# of 'min_count', apart from support.contributors.distinct, whose detail
# 'min_count' shows that the finding fails the minimum-count rule, as the
# details of its statistics show too. The support counts the sample that the
# entry names, and the counts of levels the sample of the finding. On the
# analysis sample, the counts that name such a person count in part_of,
# directly or through another such count, are suppressed too, since a
# written part shows that the count exceeds it by k or more (Within a
# finding, part_of). So are those other than 0 that name a non-person count
# of levels that the sample loses when the design sample's levels of the item
# exceed them by fewer than k, since they would bound the hidden levels from
# below, which the design sample's bound from above. events and non_events of
# a bernoulli outcome, which add up to the rows, are suppressed when the
# analysis sample loses its rows.
privacy_across_finding <- function(run, finding, sample, items, factor_items, unit_item,
                                   quantities, marks, k) {
  own <- finding$entry[["sample"]]
  for (member in c("rows", "distinct")) {
    quantity <- if (member == "rows") "rows" else "contributors"
    detail <- finding$support_suppressed[member]
    if (marks[[own]][[quantity]] &&
        (is.na(detail) || (member == "rows" && detail == "min_count"))) {
      finding$support_suppressed[member] <- "secondary"
    }
  }
  # With the basis grouping_factors, the distinct contributors are the levels
  # of the factors with the fewest levels, and with the basis
  # disclosure_unit, the levels of the disclosure unit, and they measure
  # them.
  if (!"distinct" %in% names(finding$support_suppressed)) {
    counted <- switch(finding$support$basis,
      grouping_factors = Filter(function(i) {
        quantities[[own]]$items[[i]]$levels == finding$support$distinct
      }, factor_items[!is.na(factor_items)]),
      disclosure_unit = unit_item[!is.na(unit_item)],
      integer(0)
    )
    if (any(vapply(counted, function(i) marks[[own]]$items[[i]][["levels"]], NA))) {
      finding$support_suppressed["distinct"] <- "secondary"
    }
  }
  defined <- finding$entry[["statistics"]]
  hidden <- character(0)
  # The hidden counts of levels, with their items.
  levels <- list()
  for (name in names(finding$values)) {
    measure <- defined[[name]][["measures"]]
    if (is.null(measure) || measure %in% privacy_term_measures) {
      next
    }
    rows <- c(table_rows = "table", design_rows = "design", analysis_rows = "analysis")
    i <- NA_integer_
    suppressed <- if (measure %in% names(rows)) {
      marks[[rows[[measure]]]]$rows
    } else {
      i <- privacy_item_index(items, finding$items[[name]] %||% privacy_scope_item(run, finding))
      !is.na(i) && marks[[sample]]$items[[i]][[measure]]
    }
    if (suppressed) {
      finding <- privacy_suppress(finding, name, "secondary", replace = TRUE)
      hidden <- c(hidden, name)
      if (!is.na(i)) {
        levels[[name]] <- i
      }
    }
  }
  if (sample == "analysis") {
    person <- privacy_parts(finding, hidden, person = TRUE)
    finding <- privacy_suppress(finding, person, "secondary", replace = TRUE)
    # constant_levels 10 beside the 10 levels of an item that the columns of
    # a factor give the design sample would show that no level lacks every
    # outcome, and none_constant shows constant_levels 0 anyway.
    for (total in names(levels)) {
      i <- levels[[total]]
      parts <- setdiff(privacy_parts(finding, total, person = FALSE), person)
      close <- Filter(function(part) {
        value <- finding$values[[part]]
        value > 0 && quantities$design$items[[i]]$levels - value < k
      }, parts)
      finding <- privacy_suppress(finding, close, "secondary", replace = TRUE)
    }
    # Those that this rule alone suppresses are k or more, and step 9 reads
    # them as written.
    pair <- c("events", "non_events")
    if (marks$analysis$rows && identical(run$family_class, "bernoulli") &&
        all(pair %in% names(finding$values))) {
      finding$with_rows <- pair[vapply(pair, privacy_written, NA, finding = finding)]
      finding <- privacy_suppress(finding, pair, "secondary", replace = TRUE)
    }
  }
  finding
}

# The item of the factor of a finding's scope, which the counts of the
# finding without resolved_by count, as privacy_item_index() takes it.
privacy_scope_item <- function(run, finding) {
  list(value_codes(run, factor_keys(run, finding$scope$factor)))
}

# The counts of a finding that name one of the counts given in part_of,
# directly or through another such count, only through totals of class
# person when person is TRUE.
privacy_parts <- function(finding, names, person) {
  defined <- finding$entry[["statistics"]]
  found <- character(0)
  repeat {
    parts <- Filter(function(name) {
      total <- defined[[name]][["part_of"]]
      !name %in% c(names, found) && isTRUE(total %in% c(names, found)) &&
        (!person || privacy_person(finding, total))
    }, names(finding$values))
    if (!length(parts)) {
      return(found)
    }
    found <- c(found, parts)
  }
}
