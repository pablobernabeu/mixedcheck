# The privacy filter of shareable mode (docs/spec/privacy.md), step 12 of
# audit() (03-execution-plan.md, M2). It takes the internal findings of a run
# in the order of documents.md (Findings), with their by_unit counts
# resolved, and marks the values that a shareable document does not write.
# document_finding() then writes each finding from its marks. Step 7, the
# rules across findings, is in privacy-across.R.
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
# detail. A statistic that an earlier step suppressed keeps its detail,
# unless replace is TRUE and that detail is 'min_count': a rule after step 3
# that suppresses a count then gives it the detail 'secondary', so that the
# detail does not show on which side of k the count lies (privacy.md, Steps).
privacy_suppress <- function(finding, names, detail, replace = FALSE) {
  if (replace) {
    small <- intersect(names, names(finding$suppressed)[finding$suppressed == "min_count"])
    finding$suppressed[small] <- detail
  }
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
# of quantiles, with step 5, until no value or detail changes. part_of reads
# the internal values of a person total and of the parts that steps 1 to 5
# left written, so that its result does not depend on the order of the
# rules. suppress_with, part_of and the n of a quantile also replace the
# detail 'min_count' that step 3 gave, which would show that the value is
# below k and so bound the suppressed statistic, its partner or the n:
# 'secondary' when a statistic that suppress_with names is suppressed, and
# that statistic names this one back, as the parts of a total do, or is
# suppressed with another detail, 'secondary' for a part of a person total,
# and 'quantile' when the count that gives n is suppressed.
privacy_within <- function(finding, k) {
  defined <- finding$entry[["statistics"]]
  repeat {
    before <- finding$suppressed
    for (name in names(finding$values)) {
      with <- intersect(unlist(defined[[name]][["suppress_with"]]), names(finding$suppressed))
      if (length(with)) {
        finding <- privacy_suppress(finding, name, "secondary")
        # The parts of a total name each other, and a statistic derived from
        # another names it alone.
        back <- vapply(with, function(s) name %in% unlist(defined[[s]][["suppress_with"]]), NA)
        if (identical(finding$suppressed[[name]], "min_count") &&
            any(back | finding$suppressed[with] != "min_count")) {
          finding$suppressed[name] <- "secondary"
        }
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
        finding <- privacy_suppress(finding, parts, "secondary", replace = TRUE)
      }
      # A part below k has the detail 'secondary', since the rule above
      # suppresses the parts at least k whose remainder is below k.
      small <- parts[vapply(parts, function(part) {
        !is.null(finding$values[[part]]) && finding$values[[part]] < k
      }, NA)]
      finding <- privacy_suppress(finding, small, "secondary", replace = TRUE)
    }
    for (name in names(finding$values)) {
      n <- finding$statistics[[name]]$quantile[["n"]]
      if (!is.null(n) && n %in% names(finding$suppressed)) {
        finding <- privacy_suppress(finding, name, "quantile")
        if (identical(finding$suppressed[[name]], "min_count")) {
          finding$suppressed[name] <- "quantile"
        }
      }
    }
    finding <- privacy_ratios(finding, k)
    if (identical(finding$suppressed, before)) {
      return(finding)
    }
  }
}

# --- Steps 8 and 9 ------------------------------------------------------------------------

# Step 8: a statistic that its entry marks internal_only and that its
# definition leaves absent, a ratio that its definition leaves absent, when
# its numerator or denominator is suppressed, and a quantile that its
# definition leaves absent, when the count that gives its n is suppressed,
# are written as suppressed. A by_unit ratio or quantile takes the class of
# the count it derives from, and a by_unit internal_only count, which
# resolves over no levels, the class person.
privacy_absent <- function(finding) {
  defined <- finding$entry[["statistics"]]
  for (name in setdiff(names(defined), names(finding$values))) {
    statistic <- defined[[name]]
    if (isTRUE(statistic[["internal_only"]])) {
      written <- list(kind = statistic[["kind"]])
      if (statistic[["kind"]] %in% c("count", "ratio")) {
        written$count_class <- statistic[["count_class"]]
        if (identical(written$count_class, "by_unit")) {
          written$count_class <- "person"
        }
      }
      finding$statistics[[name]] <- written
      finding$suppressed[name] <- "internal_only"
      next
    }
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
# beyond the rule on its decision: when the design sample, or the analysis
# sample on which the check ran, has at most two kept columns, kept of
# design.rank_deficiency or 0 without its finding for the design sample,
# when its kept columns other than the intercept belong to terms that read
# one variable alone, or when two of its rows share the values of every
# kept column, and, for the class binomial, when the rows with k = 0, with
# k = n or with both classes, which the rows of the analysis sample, events
# and non_events give back, number fewer than k, 0 included.
privacy_separation <- function(finding, run, k) {
  required <- run$results[["design.rank_deficiency"]]
  kept <- if (length(required)) required[[1L]]$values$kept else 0
  analysis <- match(run$analysis, run$design)
  if (kept <= 2 || sum(run$analysis_kept) <= 2 ||
      separation_one_variable(run, run$x_kept) ||
      separation_one_variable(run, run$analysis_kept) ||
      separation_shared_values(run$x[, run$x_kept, drop = FALSE]) ||
      separation_shared_values(run$x[analysis, run$analysis_kept, drop = FALSE])) {
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

# Whether the kept fixed-effects columns other than the intercept, as a
# logical over the columns of X, belong to terms that read one variable
# alone, or to none.
separation_one_variable <- function(run, kept) {
  terms <- run$ir$fixed$terms
  column_terms <- vapply(run$ir$fixed$columns, function(column) column$term + 1, 0)
  variables <- unique(unlist(lapply(terms[unique(column_terms[kept])], function(term) {
    vapply(term$variables, function(v) v$variable, "")
  })))
  length(variables) <= 1L
}

# Whether two rows of a matrix of kept columns hold equal values in every
# column, so that the columns divide the rows into combinations of which one
# holds two rows or more. The rows are sorted and each compared with the
# next.
separation_shared_values <- function(x) {
  n <- nrow(x)
  if (n < 2L) {
    return(FALSE)
  }
  # Adding 0 turns -0 into 0, which the sort could otherwise place apart.
  x <- x + 0
  x <- x[do.call(order, c(unname(lapply(seq_len(ncol(x)), function(j) x[, j])),
                          list(method = "radix"))), , drop = FALSE]
  any(rowSums(x[-1L, , drop = FALSE] == x[-n, , drop = FALSE]) == ncol(x))
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
