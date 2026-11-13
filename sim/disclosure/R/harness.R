# The machinery of the disclosure-attack tests (sim/disclosure/README.md):
# loading the package, setting the minimum count, running audit() in
# shareable mode with the internal findings captured, the values that a
# shareable document hides and the reduction of a document to what the
# adversary of docs/spec/privacy.md can use.

# The commitment key of every run. The adversary cannot invert keyed
# commitments, so the reductions below replace their digests, and a fixed key
# only makes runs repeatable.
dh_key <- paste(sprintf("%02x", 0:31), collapse = "")

# Loads mixedcheck from a library, or from the default libraries without
# one, and returns its namespace. Every time of a run is 0.
dh_load <- function(lib = NULL) {
  suppressPackageStartupMessages(library("mixedcheck", lib.loc = lib, character.only = TRUE))
  Sys.setenv(MIXEDCHECK_TIME = "0")
  ns <- asNamespace("mixedcheck")
  dh_capture$entries <- ns$registry_entries_by_id()
  ns
}

# Replaces a binding of the namespace and returns the value it replaced.
dh_assign <- function(ns, name, value) {
  old <- get(name, envir = ns, inherits = FALSE)
  locked <- bindingIsLocked(name, ns)
  if (locked) {
    unlockBinding(name, ns)
  }
  assign(name, value, envir = ns)
  if (locked) {
    lockBinding(name, ns)
  }
  invisible(old)
}

# Sets min_count in the cached registry, which the filter, the document's
# /privacy and the validator all read, so that a run with a smaller k than
# the registry's stays consistent. The rules of privacy.md are written for
# any k. Returns the previous k.
dh_set_k <- function(ns, k) {
  registry <- ns$read_registry()
  old <- registry$privacy$min_count
  registry$privacy$min_count <- k
  assign("registry", registry, envir = ns$mixedcheck_cache)
  invisible(old)
}

dh_k <- function(ns) {
  ns$read_registry()$privacy$min_count
}

# The internal findings that the filter receives, captured by a wrapper of
# privacy_filter() that dh_capture_on() installs.
dh_capture <- new.env()

dh_capture_on <- function(ns) {
  original <- get("privacy_filter", envir = ns)
  dh_assign(ns, "privacy_filter", function(run, findings, key) {
    dh_capture$run <- run
    dh_capture$findings <- findings
    original(run, findings, key)
  })
  invisible(original)
}

# A case is a list with data, formula and args, the further arguments of
# audit(). dh_run() runs it in shareable mode and returns the document, the
# internal findings and run that the filter received and the issues of
# stages 4 and 5 of validation, or the error of the run.
dh_run <- function(ns, case) {
  dh_capture$findings <- NULL
  dh_capture$run <- NULL
  args <- c(list(case$data, case$formula), case$args, list(key = dh_key))
  results <- tryCatch(do.call(ns$audit, args), error = function(e) e)
  if (inherits(results, "error")) {
    # A table whose design or analysis sample has no rows has no document.
    codes <- vapply(results$issues %||% list(), function(issue) issue$code %||% "", "")
    if ("E7007" %in% codes) {
      return(list(error = "E7007", empty = TRUE))
    }
    return(list(error = conditionMessage(results)))
  }
  list(document = results$document, findings = dh_capture$findings, run = dh_capture$run,
       issues = dh_validation_issues(ns, results))
}

# The codes of the issues that stages 4 and 5 of validate_results() report
# for a document whose structure is valid. Stages 1 to 3 check the form that
# the writer gives every document, and stages 4 and 5 hold the invariants of
# a shareable document (documents.md, Shareable documents).
dh_validation_issues <- function(ns, results) {
  document <- results$document
  issues <- if (exists("results_rule_issues", envir = ns) &&
                exists("results_registry_issues", envir = ns)) {
    c(ns$results_rule_issues(document), ns$results_registry_issues(document))
  } else {
    found <- tryCatch({
      suppressWarnings(ns$validate_results(results))
      list()
    }, mixedcheck_error = function(e) e$issues)
    found
  }
  vapply(issues, function(issue) paste(issue$code, issue$pointer %||% ""), "")
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# JSON text of a value, exact for doubles.
dh_json <- function(value) {
  if (is.null(value)) {
    return("absent")
  }
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, digits = NA, null = "null"))
}

# The identity of a finding in a document: its check and scope.
dh_finding_id <- function(finding) {
  scope <- finding$scope
  if (!length(scope)) {
    return(finding$check)
  }
  scope <- scope[order(names(scope))]
  paste(finding$check, paste(names(scope), unlist(scope), sep = "=", collapse = ","))
}

# The values that a shareable document hides, as a data frame with one row
# for each: the finding, the member (a statistic, support.rows,
# support.distinct or, for a finding suppressed as a whole, its status), its
# kind and count class, the detail of its suppression, its internal value
# as JSON, its tier (dh_tier()) and the check of its finding.
dh_targets <- function(result) {
  internal <- result$findings
  shared <- result$document$findings
  measures <- dh_measures(result$document)
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- list(...)
  for (i in seq_along(internal)) {
    f <- internal[[i]]
    d <- shared[[i]]
    if (!isTRUE(f$available)) {
      next
    }
    id <- dh_finding_id(f)
    whole <- identical(d$status$availability$reason, "privacy_suppressed")
    names <- union(names(f$values), names(d$statistics))
    if (whole) {
      # A finding suppressed as a whole hides its decision: the status and
      # the statistics that the rules of its decision read, in the rule that
      # held and those before it, or in every rule when none held. Its other
      # values may be written by other findings.
      rules <- f$entry[["decision"]][["rules"]]
      read <- if (is.na(f$rule %||% NA)) rules else rules[seq_len(f$rule)]
      names <- intersect(names, unlist(lapply(read, function(rule) rule[["statistics"]])))
    }
    for (name in names) {
      s <- d$statistics[[name]]
      detail <- if (whole) {
        "decision"
      } else if (!is.null(s) && is.null(s$value) && !is.null(s$availability)) {
        s$availability$detail
      }
      if (is.null(detail)) {
        next
      }
      defined <- f$statistics[[name]] %||% s
      # A count derived through suppress_with from statistics that are all
      # written, or one that measures a quantity that another count writes,
      # gives back no more than the written values.
      partners <- unlist(f$entry[["statistics"]][[name]][["suppress_with"]])
      derived <- if (whole) {
        # A count that a finding suppressed as a whole reads, such as the
        # events of outcome.separation, may be written by another finding
        # on the same rows. The values are compared as JSON, since a
        # written count is a double and an internal count can be an
        # integer.
        any(vapply(shared[-i], function(other) {
          !is.null(other$statistics[[name]]$value) &&
            identical(dh_json(other$statistics[[name]]$value), dh_json(f$values[[name]])) &&
            identical(entries_sample(other$check), f$entry[["sample"]])
        }, NA))
      } else {
        (length(partners) > 0L &&
           all(vapply(partners, function(p) !is.null(d$statistics[[p]]$value), NA))) ||
          dh_written_elsewhere(measures, i, name) ||
          # The kept columns of the analysis sample, which only the
          # suppression of outcome.separation as a whole can show, as
          # privacy.md (Decisions) accepts.
          (f$check == "outcome.separation" && name == "columns")
      }
      add(finding = id, member = name, kind = defined$kind,
          class = (f$statistics[[name]]$count_class %||% s$count_class) %||% "",
          detail = detail, value = dh_json(f$values[[name]]), tier = f$tier, check = f$check,
          derived = derived)
    }
    # both_classes of outcome.separation is whether events and non_events
    # are both above 0 (its definition), so it is derived when both are.
    if (whole && f$check == "outcome.separation") {
      mine <- which(vapply(rows, function(r) identical(r$finding, id), NA))
      member <- vapply(rows[mine], function(r) r$member, "")
      given <- vapply(rows[mine], function(r) isTRUE(r$derived), NA)
      if (all(c("events", "non_events") %in% member[given]) && "both_classes" %in% member) {
        rows[[mine[member == "both_classes"]]]$derived <- TRUE
      }
    }
    for (member in c("rows", "distinct")) {
      given <- if (member == "rows") d$support$rows else d$support$contributors$distinct
      if (!whole && !is.null(given) && is.null(given$value)) {
        add(finding = id, member = paste0("support.", member), kind = "count", class = "person",
            detail = given$availability$detail,
            value = dh_json(f$support[[member]]), tier = f$tier, check = f$check,
            derived = dh_written_elsewhere(measures, i, paste0("support.", member)) ||
              (member == "rows" && dh_rows_from_events(result, f, f$support$rows)))
      }
    }
    if (whole) {
      add(finding = id, member = "status", kind = "category", class = "", detail = "decision",
          value = paste(f$status$finding$value, f$message$id), tier = f$tier, check = f$check,
          derived = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(finding = character(0), member = character(0), kind = character(0),
                      class = character(0), detail = character(0), value = character(0),
                      tier = character(0), check = character(0), derived = logical(0),
                      stringsAsFactors = FALSE))
  }
  targets <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  targets$tier <- dh_tier(paste(targets$finding, "|", targets$member))
  targets
}

# --- Reduction --------------------------------------------------------------------

# The document as the adversary can use it: without the time of creation
# and with the digest of every keyed commitment replaced, so that two
# documents compare equal when they differ only in what the adversary cannot
# invert. Unkeyed hashes, such as the IR hash, stay as values to match. With
# strict TRUE, the reduction also removes what privacy.md accepts to show
# (dh_strict_finding()), so that a value that the strict reduction still
# determines is determined by what privacy.md undertakes to hide.
dh_reduce <- function(document, strict = FALSE) {
  document$created <- NULL
  document <- dh_neutralise(document)
  document$access_log$entries <- lapply(document$access_log$entries, function(entry) {
    entry$time <- NULL
    entry
  })
  if (strict) {
    document$findings <- lapply(document$findings, dh_strict_finding,
                                k = document$privacy$min_count)
  }
  cli::hash_raw_sha256(serialize(document, NULL, version = 2))
}

dh_neutralise <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  if (identical(x$algorithm, "hmac-sha256")) {
    x$digest <- "keyed"
  }
  for (i in seq_along(x)) {
    if (is.list(x[[i]])) {
      x[[i]] <- dh_neutralise(x[[i]])
    }
  }
  x
}

# A finding without the values that privacy.md (Decisions and Guarantees)
# accepts to show: the statuses, messages, categories, booleans and names of
# the T0 checks and of outcome.separation, the availability of a finding
# that is not available, the suppression as a whole of outcome.separation,
# the class of by_unit counts and the boolean dominated. The message of
# such a finding renders statistics that it writes beside it, and names,
# whose digits it would otherwise add, so it is left out whole.
dh_strict_finding <- function(finding, k) {
  base <- list(check = finding$check, scope = finding$scope, tier = finding$tier)
  availability <- finding$status$availability
  if (!identical(availability$value, "available")) {
    if (identical(availability$reason, "privacy_suppressed") &&
        finding$check != "outcome.separation") {
      return(finding)
    }
    return(c(base, list(status = "not available or suppressed")))
  }
  statistics <- finding$statistics
  t0 <- identical(finding$tier, "T0")
  separation <- identical(finding$check, "outcome.separation")
  keep <- vapply(statistics, function(s) {
    !((t0 || separation) && s$kind %in% c("category", "boolean", "names"))
  }, NA)
  entry <- dh_capture$entries[[finding$check]]
  statistics <- lapply(names(statistics)[keep], function(name) {
    s <- statistics[[name]]
    value <- s$value
    detail <- s$availability$detail
    # A by_unit count is written below k only when it resolves as non_person,
    # which the class person of privacy.md (Guarantees) accepts to show, so
    # the strict reduction writes it as if suppressed below k.
    if (identical(s$count_class, "non_person") && is.numeric(value) && value < k &&
        identical(entry[["statistics"]][[name]][["count_class"]], "by_unit")) {
      value <- NULL
      detail <- "min_count"
    }
    Filter(Negate(is.null), list(kind = s$kind, value = value, detail = detail,
                                 quantile = s$quantile))
  })
  names(statistics) <- names(finding$statistics)[keep]
  support <- finding$support
  support$contributors$dominated <- NULL
  if (t0 || separation) {
    return(c(base, list(statistics = statistics, support = support)))
  }
  c(base, list(status = finding$status, message = finding$message, statistics = statistics,
               support = support))
}

# The quantity that each count of a document measures (registry.md,
# Statistics and counts), as the key of its sample, measure and item, with
# whether the document writes it. support.rows and support.distinct measure
# the rows and the contributors of the sample that the entry names, and the
# counts of columns, which measure levels with an offset, are left out. Returns
# a data frame with one row for each count that measures a quantity.
dh_measures <- function(document, entries = dh_capture$entries) {
  rows <- list()
  for (i in seq_along(document$findings)) {
    finding <- document$findings[[i]]
    if (!identical(finding$status$availability$value, "available")) {
      next
    }
    entry <- entries[[finding$check]]
    own <- entry[["sample"]]
    sample <- if (startsWith(finding$check, "assignment.")) {
      paste("assignment", finding$scope$column)
    } else if (finding$check %in% c("structure.label_incidence", "structure.id_scope_evidence")) {
      paste("pair", finding$scope$first, finding$scope$second)
    } else {
      own
    }
    for (name in names(finding$statistics)) {
      measure <- entry[["statistics"]][[name]][["measures"]]
      # A count of columns measures the levels of the items of its terms with
      # an offset, so it writes no quantity that another count measures.
      if (is.null(measure) || measure %in% c("term_levels", "table_term_levels")) {
        next
      }
      key <- switch(measure,
        table_rows = "table rows", design_rows = "design rows", analysis_rows = "analysis rows", {
          ref <- entry[["statistics"]][[name]][["resolved_by"]][[1L]]
          item <- if (is.null(ref)) {
            finding$scope$factor
          } else if (identical(ref[["source"]], "scope")) {
            finding$scope[[ref[["name"]]]]
          } else {
            unlist(finding$statistics[[ref[["name"]]]]$value)
          }
          paste(sample, measure, paste(item, collapse = ","))
        })
      rows[[length(rows) + 1L]] <- data.frame(finding = i, member = name, key = key,
                                              written = !is.null(finding$statistics[[name]]$value),
                                              stringsAsFactors = FALSE)
    }
    for (member in c("rows", "distinct")) {
      given <- if (member == "rows") finding$support$rows else finding$support$contributors$distinct
      key <- paste(own, if (member == "rows") "rows" else "contributors")
      rows[[length(rows) + 1L]] <- data.frame(finding = i, member = paste0("support.", member),
                                              key = key, written = !is.null(given$value),
                                              stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(finding = integer(0), member = character(0), key = character(0),
                      written = logical(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

entries_sample <- function(check) dh_capture$entries[[check]][["sample"]]

# --- Tiers -------------------------------------------------------------------------

# The tier of each hidden value or parameter, by the definition of
# docs/spec/privacy.md (Tiers): 'A' for an outcome-derived value, which would
# change if only the outcome column or its trials column changed, their
# values or which rows lack them, and 'B' for a design-structure value, or NA
# for a target of no kind that the definition names, which the harness
# reports as an error of its own. Each target is named as the attacks name
# it:
# - 'parameter NAME', a parameter of the family, whose tier the family states
#   and dh_parameter_tier_issues() checks
# - 'D SAMPLE minus analysis | QUANTITY', a quantity of the table or of the
#   design sample minus that of the analysis sample, tier A
# - 'Q SAMPLE | QUANTITY', a quantity of a sample, tier A in the analysis
#   sample and B in the others
# - 'CHECK SCOPE | MEMBER', a statistic, support count or status of a finding,
#   tier A when the check reads the outcome (tier T1 or T2) and B when it does
#   not (T0), also when the finding lies on rows that equal the analysis
#   sample's
dh_tier <- function(target, family = NULL, entries = dh_capture$entries) {
  vapply(target, function(t) {
    if (startsWith(t, "parameter ")) {
      tier <- family$params[[sub("^parameter ", "", t)]]$tier
      return(if (length(tier) == 1L && tier %in% c("A", "B")) tier else NA_character_)
    }
    if (grepl("^D (table|design) minus analysis \\| ", t)) {
      return("A")
    }
    if (startsWith(t, "Q ")) {
      return(if (startsWith(t, "Q analysis | ")) "A" else "B")
    }
    tier <- entries[[sub("[ |].*$", "", t)]][["tier"]]
    if (identical(tier, "T0")) "B" else if (isTRUE(tier %in% c("T1", "T2"))) "A" else NA_character_
  }, "", USE.NAMES = FALSE)
}

# Hashes of a case, of what it holds besides its outcome (the data without
# the outcome column and its trials column, the formula and the arguments)
# and of all of it. Two tables of a family with the same first hash differ
# only in the outcome and its trials, and with the same second hash not at
# all.
dh_design_key <- function(case) {
  whole <- case[c("data", "formula", "args")]
  outcome <- all.vars(stats::as.formula(case$formula)[[2L]])
  # The trials column of the outcome sets which rows the analysis sample
  # holds, as the outcome does (privacy.md, Tiers).
  for (variable in case$args$declaration$variables) {
    if (identical(variable$role, "outcome") && is.character(variable$trials)) {
      outcome <- c(outcome, variable$trials)
    }
  }
  case$data <- case$data[setdiff(names(case$data), outcome)]
  hash <- function(x) cli::hash_raw_sha256(serialize(x, NULL, version = 2))
  c(design = hash(case[c("data", "formula", "args")]), table = hash(whole))
}

# The parameters of a family whose stated tier the definition contradicts on
# its tables (privacy.md, Tiers). Among the tables with the same design
# structure, a parameter whose values no single value fits, since every
# table that holds the same data admits only its own values, changes with
# the outcome column alone: one of tier B must never do so, and one of tier
# A that takes two values must do so for some design structure. keys holds
# the two hashes of dh_design_key() for each table of grid, as the columns
# design and table, NA for a table that was not built.
dh_parameter_tier_issues <- function(family, grid, keys) {
  issues <- character(0)
  built <- !is.na(keys[, "design"])
  for (name in names(family$params)) {
    values <- grid[[name]][built]
    changes <- vapply(split(seq_along(values), keys[built, "design"]), function(rows) {
      admitted <- split(values[rows], keys[built, "table"][rows])
      length(Reduce(intersect, admitted)) == 0L
    }, NA)
    tier <- dh_tier(paste("parameter", name), family)
    if (is.na(tier)) {
      issues <- c(issues, sprintf("%s: the parameter %s has no tier", family$name, name))
    } else if (tier == "B" && any(changes)) {
      issues <- c(issues, sprintf(
        "%s: the parameter %s of tier B changes with the outcome column alone", family$name, name))
    } else if (tier == "A" && !any(changes) && length(unique(values)) > 1L) {
      issues <- c(issues, sprintf(
        "%s: the parameter %s of tier A never changes with the outcome column alone",
        family$name, name))
    }
  }
  issues
}

# Whether a hidden count of finding i measures a quantity that the document
# writes in another count.
dh_written_elsewhere <- function(measures, i, member) {
  key <- measures$key[measures$finding == i & measures$member == member]
  length(key) == 1L && any(measures$written[measures$key == key])
}

# Whether the rows of the analysis sample, the support.rows of finding f,
# equal events plus non_events that a finding of outcome.minority_events
# writes on that sample for a bernoulli outcome, whose definitions add up to
# the rows (registry, outcome.minority_events), as the interval audit reads
# them (iv_written_point()). The difference from the design sample stays a
# target of its own (dh_difference_targets()).
dh_rows_from_events <- function(result, f, value) {
  if (!identical(f$entry[["sample"]], "analysis") ||
      !identical(result$run$family_class, "bernoulli")) {
    return(FALSE)
  }
  any(vapply(result$document$findings, function(other) {
    events <- other$statistics$events$value
    non_events <- other$statistics$non_events$value
    identical(other$check, "outcome.minority_events") && !is.null(events) &&
      !is.null(non_events) && isTRUE(events + non_events == value)
  }, NA))
}

# The differences between a quantity of the table or the design sample and
# the same quantity of the analysis sample, which privacy.md (Tiers) makes
# outcome-derived, as targets of tier A of attack (a): the rows, the
# contributors and, for each grouping factor of the IR, the levels and the
# levels with two rows or more. A difference is hidden unless the document
# writes both quantities in counts that measure them (dh_measures()), and
# the levels with two rows of an item whose counts resolve as non-person in
# a sample are its levels there, so that a count of either measures both. A
# design-structure count determined beside a written count of the analysis
# sample determines the difference, which attack (a) would otherwise report
# only as a design-structure value. A difference whose larger quantity is 0
# is marked forced, since every table of the design gives it (privacy.md,
# Guarantees).
dh_difference_targets <- function(ns, result) {
  run <- result$run
  if (is.null(run$analysis)) {
    return(NULL)
  }
  measures <- dh_measures(result$document)
  written <- unique(measures$key[measures$written])
  samples <- list(table = ns$sample_rows(run, "table"), design = run$design,
                  analysis = run$analysis)
  quantity <- function(rows) {
    q <- list(rows = length(rows), contributors = ns$rows_support(run, rows)$distinct)
    for (f in names(run$factors)) {
      codes <- ns$value_codes(run, run$factors[[f]])
      sizes <- tabulate(codes[rows])
      person <- identical(ns$resolve_count_class(run, list(codes), rows), "person")
      q[[paste("levels", f)]] <- list(value = sum(sizes > 0L), person = person)
      q[[paste("levels_with_two_rows", f)]] <- list(value = sum(sizes >= 2L), person = person)
    }
    q
  }
  q <- lapply(samples, quantity)
  # Without a disclosure unit and grouping factors the contributors have the
  # basis rows and are the rows (documents.md, Support).
  basis_rows <- is.null(run$disclosure) && !length(run$factors)
  is_written <- function(s, name) {
    if (paste(s, name) %in% written) {
      return(TRUE)
    }
    if (basis_rows && name %in% c("rows", "contributors")) {
      return(paste(s, setdiff(c("rows", "contributors"), name)) %in% written)
    }
    parts <- strsplit(name, " ", fixed = TRUE)[[1L]]
    if (length(parts) == 2L && is.list(q[[s]][[name]]) && !q[[s]][[name]]$person) {
      other <- if (parts[1L] == "levels") "levels_with_two_rows" else "levels"
      return(paste(s, other, parts[2L]) %in% written)
    }
    FALSE
  }
  value <- function(x) if (is.list(x)) x$value else x
  rows <- list()
  # The table is the design sample when it holds the same rows, and one
  # sample then gives back nothing that the other does not.
  compared <- if (identical(samples$table, samples$design)) "design" else c("table", "design")
  for (s in compared) {
    for (name in names(q$analysis)) {
      if (is_written(s, name) && is_written("analysis", name)) {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(
        finding = paste("D", s, "minus analysis"), member = name, kind = "count", class = "",
        detail = "difference", value = dh_json(value(q[[s]][[name]]) - value(q$analysis[[name]])),
        tier = "A", check = "difference", derived = FALSE,
        forced = value(q[[s]][[name]]) == 0, stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) NULL else do.call(rbind, rows)
}

# Whether each target of a table is a value that the design forces: the
# statistics and status of a finding of outcome.constant_clusters whose
# factor has no level of two rows in the design sample, which every outcome
# column leaves at 0 and no_levels (privacy.md, Guarantees, the exception of
# a value that every table of the design gives).
dh_forced_targets <- function(ns, result, targets) {
  run <- result$run
  forced <- rep(FALSE, nrow(targets))
  if (!nrow(targets) || is.null(run$analysis)) {
    return(forced)
  }
  for (f in result$findings) {
    if (!isTRUE(f$available) || f$check != "outcome.constant_clusters") {
      next
    }
    codes <- ns$value_codes(run, ns$factor_keys(run, f$scope$factor))
    if (any(tabulate(codes[run$design]) >= 2L)) {
      next
    }
    forced <- forced | (targets$finding == dh_finding_id(f) &
                          targets$member %in% c("multi_row_levels", "constant_levels",
                                                "constant_share", "status"))
  }
  forced
}
