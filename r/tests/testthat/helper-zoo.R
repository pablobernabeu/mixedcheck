# Helpers for the tests of the pathology zoo: the directories to test, the run
# of a fixture and the comparison of its findings with its expected findings
# by the rules of fixtures/zoo/README.md (Comparison), which
# parity/parity.py applies too.

zoo_key <- paste(sprintf("%02x", 0:31), collapse = "")

# The directories to test, named by identifier: those under the directory
# that MIXEDCHECK_ZOO_DIR names when it is set, such as fixtures/zoo/ of the
# source tree, and otherwise those that the installed index.json lists.
zoo_test_directories <- function() {
  root <- Sys.getenv("MIXEDCHECK_ZOO_DIR")
  if (nzchar(root)) {
    names <- list.files(root, pattern = "^Z[0-9]{2}N?-")
    names <- names[dir.exists(file.path(root, names))]
  } else {
    root <- system.file("fixtures", "zoo", package = "mixedcheck")
    if (!nzchar(root)) {
      return(character(0))
    }
    index <- read_json_strict(file.path(root, "index.json"), "data")
    names <- vapply(index[["fixtures"]], function(entry) {
      paste0(entry[["id"]], "-", entry[["name"]])
    }, "")
  }
  stats::setNames(file.path(root, names), sub("-.*$", "", names))
}

# Runs audit() on a fixture read through the internal reader, with the
# commitment key 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0. Returns
# list(value = results) or list(issues = ) for an error of class
# mixedcheck_error.
zoo_run <- function(fixture, privacy) {
  args <- c(list(fixture$data, fixture$formula, fixture$declaration), fixture$arguments,
            list(privacy = privacy, key = zoo_key))
  with_audit_time(capture_issues(function() do.call(audit, args)))
}

zoo_show <- function(x) {
  if (is.null(x)) {
    return("nothing")
  }
  text <- tryCatch(rawToChar(canonical_bytes(x, "data")), error = function(e) NULL)
  if (is.null(text)) paste(deparse(x), collapse = " ") else text
}

zoo_same <- function(x, y) {
  identical(canonical_bytes(list(x), "data"), canonical_bytes(list(y), "data"))
}

# The status of an expected finding with the defaults of the zoo: available,
# adequate, clear and descriptive, unless the finding is not available.
zoo_expected_status <- function(status) {
  status <- lapply(status, function(field) if (is.character(field)) list(value = field) else field)
  if (identical(status[["availability"]][["value"]], "not_available")) {
    return(status)
  }
  defaults <- list(availability = "available", assessability = "adequate",
                   threshold_proximity = "clear", validation = "descriptive")
  for (name in names(defaults)) {
    if (is.null(status[[name]])) {
      status[[name]] <- list(value = defaults[[name]])
    }
  }
  status
}

zoo_scope_key <- function(finding) {
  rawToChar(canonical_bytes(list(finding[["check"]], finding[["scope"]]), "data"))
}

# Without lpSolve, outcome.separation is not available with the reason
# package_missing, as the job of R CMD check without Suggests runs it.
zoo_without_solver <- function(finding) {
  if (!identical(finding[["check"]], "outcome.separation") ||
      requireNamespace("lpSolve", quietly = TRUE)) {
    return(finding)
  }
  list(check = finding[["check"]], scope = finding[["scope"]],
       status = list(availability = list(value = "not_available", reason = "package_missing",
                                         detail = "lpSolve")))
}

# How one written statistic differs from its expectation.
zoo_statistic_differences <- function(actual, wanted, check, name, here) {
  found <- character(0)
  add <- function(text) found <<- c(found, paste0(here, ": ", text))
  if (!is.null(wanted[["count_class"]]) &&
      !identical(actual[["count_class"]], wanted[["count_class"]])) {
    add(paste0("count class ", zoo_show(actual[["count_class"]]), " and ",
               zoo_show(wanted[["count_class"]])))
  }
  value <- actual[["value"]]
  if (isTRUE(wanted[["absent"]])) {
    add(paste0(zoo_show(value), " and absent"))
  } else if (!is.null(wanted[["ratio"]])) {
    quotient <- wanted[["ratio"]][[1L]] / wanted[["ratio"]][[2L]]
    if (!identical(value, quotient)) {
      add(paste0(zoo_show(value), " and the ratio ", zoo_show(wanted[["ratio"]])))
    }
  } else if (!is.null(wanted[["interval"]])) {
    low <- wanted[["interval"]][[1L]]
    high <- wanted[["interval"]][[2L]]
    values <- unlist(value)
    if (!is.numeric(values) || !length(values) || any(values < low | values > high)) {
      add(paste0(zoo_show(value), " and the interval ", zoo_show(wanted[["interval"]])))
    }
  } else if (actual[["kind"]] %in% c("real", "reals")) {
    x <- unlist(value)
    y <- unlist(wanted[["value"]])
    same <- length(x) == length(y) &&
      all(vapply(seq_along(x), function(i) reals_match(x[[i]], y[[i]], check, name), NA))
    if (!same) {
      add(paste0(zoo_show(value), " and ", zoo_show(wanted[["value"]])))
    }
  } else if (!zoo_same(value, wanted[["value"]])) {
    add(paste0(zoo_show(value), " and ", zoo_show(wanted[["value"]])))
  }
  found
}

# How one finding of a run differs from its expectation in a privacy mode.
zoo_finding_differences <- function(actual, wanted, samples, privacy, here) {
  check <- wanted[["check"]]
  shareable <- privacy == "shareable"
  status <- actual[["status"]]
  if (shareable && !identical(actual[["tier"]], "T0") &&
      identical(status[["availability"]][["reason"]], "privacy_suppressed") &&
      identical(status[["availability"]][["detail"]], "decision")) {
    return(character(0))
  }
  found <- character(0)
  add <- function(where, text) found <<- c(found, paste0(here, where, ": ", text))
  expanded <- zoo_expected_status(wanted[["status"]])
  if (!zoo_same(status, expanded)) {
    add("/status", paste0(zoo_show(status), " and ", zoo_show(expanded)))
    return(found)
  }
  if (!identical(status[["availability"]][["value"]], "available")) {
    return(found)
  }
  if (!identical(actual[["message"]][["id"]], wanted[["message"]])) {
    add("/message", paste0(zoo_show(actual[["message"]][["id"]]), " and ",
                           zoo_show(wanted[["message"]])))
  }
  statistics <- actual[["statistics"]]
  expected <- wanted[["statistics"]]
  for (name in names(expected)) {
    statistic <- statistics[[name]]
    where <- paste0(here, "/statistics/", name)
    if (is.null(statistic)) {
      if (!isTRUE(expected[[name]][["absent"]])) {
        found <- c(found, paste0(where, ": nothing and ", zoo_show(expected[[name]])))
      }
      next
    }
    if (shareable && is.null(statistic[["value"]])) {
      if (!is.null(expected[[name]][["count_class"]]) &&
          !identical(statistic[["count_class"]], expected[[name]][["count_class"]])) {
        found <- c(found, paste0(where, ": count class ", zoo_show(statistic[["count_class"]]),
                                 " and ", zoo_show(expected[[name]][["count_class"]])))
      }
      next
    }
    found <- c(found, zoo_statistic_differences(statistic, expected[[name]], check, name, where))
  }
  for (name in setdiff(names(statistics), names(expected))) {
    if (!statistics[[name]][["kind"]] %in% c("real", "reals")) {
      found <- c(found, paste0(here, "/statistics/", name, ": ",
                               zoo_show(statistics[[name]][["value"]]), " and nothing"))
    }
  }
  sample <- samples[[registry_entry(check)[["sample"]]]]
  support <- actual[["support"]]
  written <- function(x) !shareable || !is.null(x)
  rows <- support[["rows"]][["value"]]
  if (written(rows) && !identical(rows, sample[["rows"]])) {
    add("/support/rows", paste0(zoo_show(support[["rows"]]), " and ", sample[["rows"]]))
  }
  contributors <- support[["contributors"]]
  if (!identical(contributors[["basis"]], sample[["basis"]]) ||
      !identical(contributors[["dominated"]], sample[["dominated"]]) ||
      (written(contributors[["distinct"]][["value"]]) &&
       !identical(contributors[["distinct"]][["value"]], sample[["distinct"]]))) {
    add("/support/contributors", paste0(zoo_show(contributors), " and ", zoo_show(sample)))
  }
  found
}

# How the result of a run differs from the expected findings of its fixture,
# as lines that name the JSON Pointer of the member and both values. The
# result is list(value = results) or list(issues = ).
zoo_differences <- function(result, expected, privacy) {
  issue <- expected[["issue"]]
  if (!is.null(issue)) {
    issues <- result[["issues"]]
    if (is.null(issues)) {
      return("/issue: a document and the issue")
    }
    got <- issues[[1L]][c("code", "message", "pointer")]
    want <- issue[c("code", "message", "pointer")]
    present <- function(x) Filter(Negate(is.null), x)
    if (length(issues) != 1L || !zoo_same(present(got), present(want))) {
      return(paste0("/issue: ", zoo_show(issues), " and ", zoo_show(issue)))
    }
    return(character(0))
  }
  if (!is.null(result[["issues"]])) {
    return(paste0("/findings: the issue ", zoo_show(result[["issues"]]), " and findings"))
  }
  found <- character(0)
  if (privacy == "shareable") {
    problem <- tryCatch(withCallingHandlers(
      {
        validate_results(result[["value"]])
        NULL
      },
      warning = function(w) stop(w)
    ), error = function(e) conditionMessage(e))
    if (!is.null(problem)) {
      found <- c(found, paste0("validate_results(): ", problem))
    }
  }
  findings <- result[["value"]][["document"]][["findings"]]
  wanted <- lapply(expected[["findings"]], zoo_without_solver)
  keys <- vapply(findings, zoo_scope_key, "")
  wanted_keys <- vapply(wanted, zoo_scope_key, "")
  if (!identical(keys, wanted_keys)) {
    return(c(found, paste0("/findings: the run has ", zoo_show(as.list(setdiff(keys, wanted_keys))),
                           " beyond the expectation and lacks ",
                           zoo_show(as.list(setdiff(wanted_keys, keys))),
                           if (setequal(keys, wanted_keys)) ", in another order")))
  }
  for (i in seq_along(findings)) {
    found <- c(found, zoo_finding_differences(findings[[i]], wanted[[i]], expected[["samples"]],
                                              privacy, paste0("/findings/", i - 1L)))
  }
  found
}

# Fails with every difference, each prefixed with the identifier and mode.
expect_zoo_findings <- function(result, expected, privacy, id) {
  found <- zoo_differences(result, expected, privacy)
  expect(length(found) == 0L,
         paste0(paste0(id, " ", privacy, " ", found), collapse = "\n"))
  invisible(found)
}
