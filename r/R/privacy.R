# The privacy filter of shareable mode (docs/spec/privacy.md), step 12 of
# audit() (03-execution-plan.md, M2). It takes the internal findings of a run
# in the order of documents.md (Findings), with their by_unit counts
# resolved, and marks the values that a shareable document does not write.
# document_finding() then writes each finding from its marks.
#
# The marks of a finding are:
# - suppressed: the detail of each statistic that the filter suppressed, by
#   name, which includes the absent statistics of step 8
# - support_suppressed: the detail of support.rows and of
#   support.contributors.distinct, by 'rows' and 'distinct', when suppressed
# - whole: TRUE for a finding that step 9 suppresses as a whole
# - left_written: the statistics that steps 1 to 5 left written, which the
#   rule part_of reads

# Step 12: the shareable findings of a run and the pseudonyms of their
# labels, in the form that the internal sidecar records them. key is the
# commitment key of the run, as 64 hexadecimal digits.
privacy_filter <- function(run, findings, key) {
  k <- read_registry()[["privacy"]][["min_count"]]
  findings <- lapply(findings, function(finding) {
    if (!isTRUE(finding$available)) {
      return(finding)
    }
    finding$suppressed <- structure(character(0), names = character(0))
    finding$support_suppressed <- structure(character(0), names = character(0))
    finding$whole <- FALSE
    finding <- privacy_internal_only(finding)
    finding <- privacy_minimum_rules(finding, k)
    finding <- privacy_small_counts(finding, k)
    finding <- privacy_quantiles(finding, k)
    finding <- privacy_ratios(finding, k)
    finding$left_written <- setdiff(names(finding$values), names(finding$suppressed))
    privacy_within(finding, k)
  })
  findings <- privacy_across(run, findings, k)
  findings <- lapply(findings, function(finding) {
    if (!isTRUE(finding$available)) {
      return(finding)
    }
    privacy_decision(privacy_absent(privacy_within(finding, k)), run, k)
  })
  pseudonyms <- privacy_pseudonyms(findings, key)
  findings <- lapply(findings, privacy_render, pseudonyms = pseudonyms)
  list(findings = findings,
       pseudonyms = lapply(seq_len(nrow(pseudonyms)), function(i) {
         list(pseudonym = pseudonyms$pseudonym[i], factor = pseudonyms$factor[i],
              label = pseudonyms$label[i])
       }))
}

# --- Marks --------------------------------------------------------------------------

# Whether a statistic of a finding is written: present and not suppressed.
privacy_written <- function(finding, name) {
  !is.null(finding$values[[name]]) && !name %in% names(finding$suppressed)
}

# Suppresses the statistics of a finding that are still written with a
# detail. A statistic that an earlier step suppressed keeps its detail.
privacy_suppress <- function(finding, names, detail) {
  names <- unique(names[vapply(names, privacy_written, NA, finding = finding)])
  if (length(names)) {
    finding$suppressed[names] <- detail
  }
  finding
}

# Whether a statistic of a finding is a count, or with ratio TRUE a count or
# a ratio, of class person as resolved for the finding.
privacy_person <- function(finding, name, ratio = FALSE) {
  statistic <- finding$statistics[[name]]
  kinds <- if (ratio) c("count", "ratio") else "count"
  !is.null(statistic) && statistic$kind %in% kinds &&
    identical(statistic$count_class, "person")
}

# --- Steps 1 to 6 ---------------------------------------------------------------------

# Step 1: the statistics that the entry marks internal_only.
privacy_internal_only <- function(finding) {
  defined <- finding$entry[["statistics"]]
  internal <- names(defined)[vapply(defined, function(s) isTRUE(s[["internal_only"]]), NA)]
  privacy_suppress(finding, internal, "internal_only")
}

# Step 2: in a finding that fails the minimum-count or the dominance rule,
# every real, reals and labels value and every person count and ratio.
privacy_minimum_rules <- function(finding, k) {
  support <- finding$support
  fails_minimum <- support$distinct < k
  if (!fails_minimum && !isTRUE(support$dominated)) {
    return(finding)
  }
  names <- Filter(function(name) {
    finding$statistics[[name]]$kind %in% c("real", "reals", "labels") ||
      privacy_person(finding, name, ratio = TRUE)
  }, names(finding$values))
  privacy_suppress(finding, names, if (fails_minimum) "min_count_rule" else "dominance")
}

# Step 3: every person count still written that is below k, 0 included,
# support.rows and support.contributors.distinct among them, other than a
# quantile that step 4 suppresses, a minimum or a maximum among them, which
# step 4 suppresses whatever its value, so that its detail does not show on
# which side of k it lies.
privacy_small_counts <- function(finding, k) {
  names <- Filter(function(name) {
    privacy_person(finding, name) && finding$values[[name]] < k &&
      !privacy_quantile_hidden(finding, name, k)
  }, names(finding$values))
  finding <- privacy_suppress(finding, names, "min_count")
  for (member in c("rows", "distinct")) {
    if (finding$support[[member]] < k) {
      finding$support_suppressed[member] <- "min_count"
    }
  }
  finding
}

# Step 4: a p-quantile of n values unless n x min(m, 10^d - m) >= k x 10^d,
# with n the internal value of the count that the entry names.
privacy_quantiles <- function(finding, k) {
  names <- Filter(function(name) privacy_quantile_hidden(finding, name, k),
                  names(finding$values))
  privacy_suppress(finding, names, "quantile")
}

# Whether a statistic is a quantile that step 4 suppresses: its n, the
# internal value of the count that its entry names, is absent or fails the
# quantile rule, as it always does for a minimum or a maximum.
privacy_quantile_hidden <- function(finding, name, k) {
  quantile <- finding$statistics[[name]]$quantile
  if (is.null(quantile)) {
    return(FALSE)
  }
  n <- finding$values[[quantile[["n"]]]]
  is.null(n) || !quantile_shown(n, quantile[["p"]], k)
}

# Step 5: a ratio whose numerator or denominator is a person count that is
# suppressed or below k.
privacy_ratios <- function(finding, k) {
  defined <- finding$entry[["statistics"]]
  names <- Filter(function(name) {
    statistic <- defined[[name]]
    if (statistic[["kind"]] != "ratio") {
      return(FALSE)
    }
    parts <- c(statistic[["numerator"]], statistic[["denominator"]])
    any(vapply(parts, function(part) {
      privacy_person(finding, part) &&
        (part %in% names(finding$suppressed) || finding$values[[part]] < k)
    }, NA))
  }, names(finding$values))
  privacy_suppress(finding, names, "ratio")
}

# Step 6: the relations within a finding, suppress_with, part_of and the n
# of quantiles, with step 5, until no value changes. part_of reads the
# internal values of a person total and of the parts that steps 1 to 5 left
# written, so that its result does not depend on the order of the rules.
privacy_within <- function(finding, k) {
  defined <- finding$entry[["statistics"]]
  repeat {
    before <- length(finding$suppressed)
    for (name in names(finding$values)) {
      with <- unlist(defined[[name]][["suppress_with"]])
      if (any(with %in% names(finding$suppressed))) {
        finding <- privacy_suppress(finding, name, "secondary")
      }
    }
    part_of <- unlist(lapply(defined, function(s) s[["part_of"]] %||% NA_character_))
    for (total in unique(part_of[!is.na(part_of)])) {
      value <- finding$values[[total]]
      if (is.null(value) || !privacy_person(finding, total)) {
        next
      }
      parts <- names(part_of)[part_of %in% total]
      left <- intersect(parts, finding$left_written)
      counts <- vapply(left, function(part) finding$values[[part]], 0)
      if (length(left) && (any(value - counts < k) || value - sum(counts) < k)) {
        finding <- privacy_suppress(finding, parts, "secondary")
      }
    }
    for (name in names(finding$values)) {
      n <- finding$statistics[[name]]$quantile[["n"]]
      if (!is.null(n) && n %in% names(finding$suppressed)) {
        finding <- privacy_suppress(finding, name, "quantile")
      }
    }
    finding <- privacy_ratios(finding, k)
    if (length(finding$suppressed) == before) {
      return(finding)
    }
  }
}

# --- Step 7: across findings ------------------------------------------------------------

# Step 7: the rules across findings (privacy.md, Across findings). The
# samples are the table, the design sample, the analysis sample when the run
# read the outcome and the rows that an available finding reads when they
# are not its entry's sample, the rows of an assignment or of a pair of
# columns, which are the design sample, or else the analysis sample, when
# they hold its rows, and one sample when two findings read the same rows.
# Rule 1 compares every two samples one of which holds the other's rows,
# rule 2 compares the levels of an item with its levels with one and with two
# or more rows, rule 3 suppresses the counts that equal a suppressed quantity
# and rule 4 compares the rows without a key value with the rows that each
# other sample leaves out. Each suppresses the written counts concerned with
# the detail 'secondary'.
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
  crossed <- list()
  for (i in which(available)) {
    finding <- findings[[i]]
    if (finding$check == "structure.label_incidence" &&
        identical(finding$values[["relation"]], "crossed")) {
      crossed[[length(crossed) + 1L]] <- list(
        sample = finding_samples[i],
        combinations = privacy_item_index(items, finding$items[["combinations"]]),
        first = privacy_item_index(items, finding$items[["levels_first"]]),
        second = privacy_item_index(items, finding$items[["levels_second"]])
      )
    }
  }
  marks <- privacy_quantity_marks(quantities, privacy_comparisons(samples, main), crossed, k)
  factor_items <- vapply(run$factors, function(keys) {
    privacy_item_index(items, list(value_codes(run, keys)))
  }, 0L)
  for (i in which(available)) {
    findings[[i]] <- privacy_across_finding(run, findings[[i]], finding_samples[i], items,
                                            factor_items, quantities, marks)
    if (findings[[i]]$check == "keys.duplicates" &&
        privacy_missing_key_close(run, samples[setdiff(names(samples), "table")], k)) {
      findings[[i]] <- privacy_suppress(findings[[i]], "missing_key_rows", "secondary")
    }
  }
  findings
}

# Rule 4: whether the rows of the table with a missing value in a column of
# the observation key and the rows of the table that one of the other
# samples leaves out, one of which holds the other, differ by fewer than k
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

# The quantities of an item in some rows: whether its counts of levels
# resolve as person counts there, its levels, those with at least two rows
# and those with one row.
privacy_item_quantities <- function(run, codes, rows) {
  sizes <- tabulate(codes[rows])
  list(person = resolve_count_class(run, list(codes), rows) == "person",
       levels = sum(sizes > 0L), levels_with_two_rows = sum(sizes >= 2L),
       levels_with_one_row = sum(sizes == 1L))
}

# Rules 1 and 2: the quantities that are suppressed, by sample, as the
# logical members rows and contributors and, for each item, levels,
# levels_with_two_rows and levels_with_one_row. A quantity of an item is
# compared when the item's counts of levels resolve as person counts in the
# larger sample, which holds the levels that the difference counts, and rule
# 2 applies to such items only, in each sample. When
# rule 1 suppresses the levels of the combinations of two columns that
# structure.label_incidence finds crossed in a sample in which the levels of
# both columns stay written, their product gives the value back, so the
# levels of the combinations in the other sample of each comparison that
# suppressed them are suppressed too. crossed lists such pairs, each with its
# sample and the positions of the items of the combinations and of the two
# columns.
privacy_quantity_marks <- function(quantities, comparisons, crossed, k) {
  measures <- c("levels", "levels_with_two_rows", "levels_with_one_row")
  marks <- lapply(quantities, function(sample) {
    list(rows = FALSE, contributors = FALSE,
         items = lapply(sample$items, function(item) {
           structure(logical(3L), names = measures)
         }))
  })
  close <- function(a, b) a - b >= 0 && a - b < k
  lost <- list()
  for (comparison in comparisons) {
    larger <- quantities[[comparison$larger]]
    smaller <- quantities[[comparison$smaller]]
    loser <- comparison$loser
    other <- if (loser == comparison$larger) comparison$smaller else comparison$larger
    for (member in c("rows", "contributors")) {
      if (close(larger[[member]], smaller[[member]])) {
        marks[[loser]][[member]] <- TRUE
      }
    }
    for (i in seq_along(larger$items)) {
      if (!larger$items[[i]]$person) {
        next
      }
      for (measure in measures[1:2]) {
        if (close(larger$items[[i]][[measure]], smaller$items[[i]][[measure]])) {
          marks[[loser]]$items[[i]][[measure]] <- TRUE
          if (measure == "levels") {
            lost[[length(lost) + 1L]] <- list(sample = loser, other = other, item = i)
          }
        }
      }
    }
  }
  for (pair in crossed) {
    sample <- pair$sample
    written <- function(i) {
      item <- quantities[[sample]]$items[[i]]
      !marks[[sample]]$items[[i]][["levels"]] && (!item$person || item$levels >= k)
    }
    if (anyNA(unlist(pair)) || !marks[[sample]]$items[[pair$combinations]][["levels"]] ||
        !written(pair$first) || !written(pair$second)) {
      next
    }
    for (found in lost) {
      if (found$sample == sample && found$item == pair$combinations) {
        marks[[found$other]]$items[[found$item]][["levels"]] <- TRUE
      }
    }
  }
  for (sample in names(quantities)) {
    for (i in seq_along(quantities[[sample]]$items)) {
      item <- quantities[[sample]]$items[[i]]
      if (!item$person) {
        next
      }
      first <- marks[[sample]]$items[[i]]
      if (item$levels_with_one_row < k || first[["levels"]]) {
        marks[[sample]]$items[[i]][["levels_with_two_rows"]] <- TRUE
      }
      if (first[["levels_with_two_rows"]]) {
        marks[[sample]]$items[[i]][["levels_with_one_row"]] <- TRUE
      }
    }
  }
  marks
}

# Rules 1 to 3 for one finding on a sample: the support and the counts that
# measure a suppressed quantity, and then the counts that measure no
# quantity, are not of class non_person and equal a suppressed quantity of
# the sample.
privacy_across_finding <- function(run, finding, sample, items, factor_items, quantities,
                                   marks) {
  own <- finding$entry[["sample"]]
  for (member in c("rows", "distinct")) {
    quantity <- if (member == "rows") "rows" else "contributors"
    if (marks[[own]][[quantity]] && !member %in% names(finding$support_suppressed)) {
      finding$support_suppressed[member] <- "secondary"
    }
  }
  # With the basis grouping_factors, the distinct contributors are the levels
  # of the factors with the fewest levels, and measure them.
  if (identical(finding$support$basis, "grouping_factors") &&
      !"distinct" %in% names(finding$support_suppressed)) {
    for (i in factor_items[!is.na(factor_items)]) {
      if (quantities[[own]]$items[[i]]$levels == finding$support$distinct &&
          marks[[own]]$items[[i]][["levels"]]) {
        finding$support_suppressed["distinct"] <- "secondary"
      }
    }
  }
  defined <- finding$entry[["statistics"]]
  for (name in names(finding$values)) {
    measure <- defined[[name]][["measures"]]
    if (is.null(measure)) {
      next
    }
    rows <- c(table_rows = "table", design_rows = "design", analysis_rows = "analysis")
    suppressed <- if (measure %in% names(rows)) {
      marks[[rows[[measure]]]]$rows
    } else {
      item <- finding$items[[name]] %||%
        list(value_codes(run, factor_keys(run, finding$scope$factor)))
      i <- privacy_item_index(items, item)
      !is.na(i) && marks[[sample]]$items[[i]][[measure]]
    }
    if (suppressed) {
      finding <- privacy_suppress(finding, name, "secondary")
    }
  }
  equal <- privacy_suppressed_values(quantities[[sample]], marks[[sample]])
  names <- Filter(function(name) {
    is.null(defined[[name]][["measures"]]) && privacy_person(finding, name) &&
      finding$values[[name]] %in% equal
  }, names(finding$values))
  privacy_suppress(finding, names, "secondary")
}

# The position of an item among the items of the rules, or NA for an item
# that the finding lacks.
privacy_item_index <- function(items, item) {
  if (any(vapply(item, is.null, NA))) {
    return(NA_integer_)
  }
  codes <- privacy_item_codes(item)
  found <- which(vapply(items, identical, NA, codes))
  if (length(found)) found[1L] else NA_integer_
}

# The values of the quantities of a sample that rules 1 and 2 suppress.
privacy_suppressed_values <- function(quantities, marks) {
  values <- c(if (marks$rows) quantities$rows, if (marks$contributors) quantities$contributors)
  for (i in seq_along(quantities$items)) {
    item <- quantities$items[[i]]
    for (measure in names(marks$items[[i]])[marks$items[[i]]]) {
      values <- c(values, item[[measure]])
    }
  }
  values
}

# --- Steps 8 and 9 ------------------------------------------------------------------------

# Step 8: a ratio that its definition leaves absent, when its numerator or
# denominator is suppressed, and a quantile that its definition leaves
# absent, when the count that gives its n is suppressed, are written as
# suppressed. A by_unit statistic takes the class of the count it derives
# from.
privacy_absent <- function(finding) {
  defined <- finding$entry[["statistics"]]
  for (name in setdiff(names(defined), names(finding$values))) {
    statistic <- defined[[name]]
    parts <- if (statistic[["kind"]] == "ratio") {
      c(statistic[["numerator"]], statistic[["denominator"]])
    } else {
      statistic[["quantile"]][["n"]]
    }
    found <- intersect(parts, names(finding$suppressed))
    if (!length(found)) {
      next
    }
    written <- list(kind = statistic[["kind"]])
    if (statistic[["kind"]] %in% c("count", "ratio")) {
      written$count_class <- statistic[["count_class"]]
      if (identical(written$count_class, "by_unit")) {
        written$count_class <- finding$statistics[[found[1L]]]$count_class
      }
    }
    if (!is.null(statistic[["quantile"]])) {
      written$quantile <- statistic[["quantile"]]
    }
    finding$statistics[[name]] <- written
    finding$suppressed[name] <- if (statistic[["kind"]] == "ratio") "ratio" else "quantile"
  }
  finding
}

# Step 9: a finding of tier T1 or T2 is suppressed as a whole when a person
# count or ratio that a rule of its decision reads, in the rule that held or
# a rule before it, or in any rule when none held, is suppressed, and a
# finding of outcome.separation by the rules of privacy.md (Decisions).
privacy_decision <- function(finding, run, k) {
  if (!finding$tier %in% c("T1", "T2")) {
    return(finding)
  }
  rules <- finding$entry[["decision"]][["rules"]]
  read <- if (is.na(finding$rule)) rules else rules[seq_len(finding$rule)]
  names <- unique(unlist(lapply(read, function(rule) rule[["statistics"]])))
  hidden <- vapply(names, function(name) {
    privacy_person(finding, name, ratio = TRUE) && name %in% names(finding$suppressed)
  }, NA)
  if (any(hidden) || (finding$check == "outcome.separation" && privacy_separation(finding, run, k))) {
    finding$whole <- TRUE
  }
  finding
}

# Whether the filter suppresses a finding of outcome.separation as a whole
# beyond the rule on its decision: when the design sample has at most two
# kept columns, kept of design.rank_deficiency or 0 without its finding, or
# when its kept columns other than the intercept belong to terms that read
# one variable alone, and, for the class binomial, when the rows with k = 0,
# with k = n or with both classes, which the rows of the analysis sample,
# events and non_events give back, number fewer than k, 0 included.
privacy_separation <- function(finding, run, k) {
  required <- run$results[["design.rank_deficiency"]]
  kept <- if (length(required)) required[[1L]]$values$kept else 0
  terms <- run$ir$fixed$terms
  column_terms <- vapply(run$ir$fixed$columns, function(column) column$term + 1, 0)
  variables <- unique(unlist(lapply(terms[unique(column_terms[run$x_kept])], function(term) {
    vapply(term$variables, function(v) v$variable, "")
  })))
  if (kept <= 2 || length(variables) <= 1L) {
    return(TRUE)
  }
  if (run$family_class != "binomial") {
    return(FALSE)
  }
  rows <- finding$support$rows
  events <- finding$values$events
  non_events <- finding$values$non_events
  any(c(rows - events, rows - non_events, events + non_events - rows) < k)
}

# --- Steps 10 and 11 ----------------------------------------------------------------------

# Step 10: the pseudonyms of the labels that the shareable findings write,
# as a data frame with the columns factor, label and pseudonym: one for each
# distinct pair of a factor and a label, numbered in increasing order of the
# HMAC-SHA-256 of the canonical bytes of the array of the two under the
# commitment key, the digests compared as lower-case hexadecimal strings.
privacy_pseudonyms <- function(findings, key) {
  factor <- character(0)
  label <- character(0)
  for (finding in findings) {
    if (!isTRUE(finding$available) || finding$whole) {
      next
    }
    for (name in names(finding$values)) {
      if (finding$statistics[[name]]$kind == "labels" && privacy_written(finding, name)) {
        values <- finding$values[[name]]
        factor <- c(factor, rep(finding$label_factors[[name]], length(values)))
        label <- c(label, values)
      }
    }
  }
  pairs <- data.frame(factor = enc2utf8(factor), label = enc2utf8(label),
                      stringsAsFactors = FALSE)
  pairs <- pairs[!duplicated(paste(pairs$factor, pairs$label, sep = "\001")), , drop = FALSE]
  bytes <- commitment_key_bytes(key)
  digests <- vapply(seq_len(nrow(pairs)), function(i) {
    hmac_sha256(bytes, canonical_bytes(list(pairs$factor[i], pairs$label[i]), "data"))
  }, "")
  pairs <- pairs[order(digests, method = "radix"), , drop = FALSE]
  pairs$pseudonym <- sprintf("#%d", seq_len(nrow(pairs)))
  rownames(pairs) <- NULL
  pairs
}

# Steps 10 and 11 for one finding: its labels replaced by their pseudonyms
# and its message rendered again from the written values, the template when
# every statistic that it renders is written and the fallback otherwise.
privacy_render <- function(finding, pseudonyms) {
  if (!isTRUE(finding$available) || finding$whole) {
    return(finding)
  }
  for (name in names(finding$values)) {
    if (finding$statistics[[name]]$kind == "labels" && privacy_written(finding, name)) {
      factor <- finding$label_factors[[name]]
      mine <- pseudonyms[pseudonyms$factor == factor, , drop = FALSE]
      finding$values[[name]] <- mine$pseudonym[match(finding$values[[name]], mine$label)]
    }
  }
  written <- Filter(function(name) privacy_written(finding, name), names(finding$values))
  finding$message$text <- render_message(finding$entry, finding$message$id, finding$scope,
                                         finding$values, written)
  finding
}
