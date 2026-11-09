# The audit corpus: every case runs through audit() with the commitment key
# 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0, and its findings, or the issue
# that refuses the run, are compared with the expected ones as
# fixtures/conformance/audits/README.md describes. Every document that
# audit() returns is validated with validate_results().

audit_corpus_key <- paste(sprintf("%02x", 0:31), collapse = "")

# Runs code with an environment variable set, and restores it afterwards.
with_environment_variable <- function(name, value, code) {
  set <- function(value) {
    values <- list(value)
    names(values) <- name
    do.call(Sys.setenv, values)
  }
  old <- Sys.getenv(name, unset = NA)
  set(value)
  on.exit(if (is.na(old)) Sys.unsetenv(name) else set(old), add = TRUE)
  force(code)
}

# The arguments of audit() for a case, in the given privacy mode.
audit_case_arguments <- function(case, privacy) {
  args <- list(data = corpus_data_frame(case[["data"]]), formula = case[["formula"]])
  for (member in c("declaration", "family", "coding", "weights", "outcome_access", "reason",
                   "exploratory")) {
    if (!is.null(case[[member]])) {
      args[[member]] <- case[[member]]
    }
  }
  if (!is.null(case[["sample_columns"]])) {
    args$sample_columns <- unlist(case[["sample_columns"]])
  }
  args$privacy <- privacy
  args$key <- audit_corpus_key
  args
}

run_audit_case <- function(case, privacy) {
  args <- audit_case_arguments(case, privacy)
  with_environment_variable("MIXEDCHECK_TIME", "0", capture_issues(function() {
    do.call(audit, args)
  }))
}

# Whether two real values match within the tolerance of conventions.md
# (Comparison across languages), with its exceptions for design.collinearity
# and outcome.separation. 'NaN', 'Infinity' and '-Infinity' match only
# themselves.
reals_match <- function(x, y, check, name) {
  if (is.character(x) || is.character(y)) {
    return(identical(x, y))
  }
  m <- max(abs(x), abs(y))
  if (check == "design.collinearity" && name %in% c("gvif", "gvif_per_df")) {
    return(abs(x - y) <= 1e-12 + max(1e-9, 1e-13 * m) * m)
  }
  if (check == "outcome.separation") {
    tolerance <- 1e-6
    return(abs(x - y) <= if (name == "bounds") tolerance else tolerance * max(1, m))
  }
  abs(x - y) <= 1e-12 + 1e-9 * m
}

# Whether two message texts match: identical, or different only in numbers
# that are the neighbouring roundings, at the same number of decimal places,
# on either side of one rounding boundary.
message_texts_match <- function(a, b) {
  if (identical(a, b)) {
    return(TRUE)
  }
  pattern <- "-?[0-9]+(\\.[0-9]+)?"
  numbers_a <- regmatches(a, gregexpr(pattern, a))[[1L]]
  numbers_b <- regmatches(b, gregexpr(pattern, b))[[1L]]
  if (length(numbers_a) != length(numbers_b) ||
      !identical(gsub(pattern, "#", a), gsub(pattern, "#", b))) {
    return(FALSE)
  }
  differ <- numbers_a != numbers_b
  places <- function(x) nchar(sub("^[^.]*\\.?", "", x))
  units <- function(x) as.numeric(gsub(".", "", x, fixed = TRUE))
  all(places(numbers_a[differ]) == places(numbers_b[differ]) &
        abs(units(numbers_a[differ]) - units(numbers_b[differ])) == 1)
}

# Compares one finding with its expected form: exactly, apart from the
# values of real statistics, compared within the tolerance or bit for bit
# for those that 'exact' lists, the message text, and, for a finding that is
# near_threshold, the finding status and the message.
expect_audit_finding <- function(actual, expected, exact, label) {
  check <- expected[["check"]]
  near <- identical(expected[["status"]][["threshold_proximity"]][["value"]], "near_threshold")
  reals <- names(Filter(function(s) s[["kind"]] %in% c("real", "reals"), expected[["statistics"]]))
  strip <- function(finding) {
    for (name in intersect(reals, names(finding[["statistics"]]))) {
      finding[["statistics"]][[name]][["value"]] <- "real"
    }
    if (!is.null(finding[["message"]])) {
      finding[["message"]][["text"]] <- "text"
    }
    if (near) {
      finding[["status"]][["finding"]] <- NULL
      finding[["message"]] <- NULL
    }
    finding
  }
  expect_identical(rawToChar(canonical_bytes(strip(actual), "data")),
                   rawToChar(canonical_bytes(strip(expected), "data")), label = label)
  for (name in reals) {
    x <- actual[["statistics"]][[name]][["value"]]
    y <- expected[["statistics"]][[name]][["value"]]
    if (is.null(x) || is.null(y)) {
      next
    }
    here <- paste(label, name)
    if (paste0(check, ":", name) %in% exact) {
      expect_identical(mixedcheck:::double_bits(unlist(x)), mixedcheck:::double_bits(unlist(y)),
                       label = here)
    } else {
      expect_length(x, length(y))
      if (length(x) == length(y)) {
        expect_true(all(mapply(reals_match, x, y, check, name)), label = here)
      }
    }
  }
  if (!near && !is.null(expected[["message"]])) {
    text <- actual[["message"]][["text"]]
    if (!message_texts_match(text, expected[["message"]][["text"]])) {
      expect_identical(text, expected[["message"]][["text"]], label = paste(label, "message"))
    } else {
      succeed()
    }
  }
}

expect_audit_findings <- function(result, expected, case, label) {
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected findings, got %s: %s", label, result$issues[[1L]][["code"]],
                 result$issues[[1L]][["message"]]))
    return(invisible())
  }
  # Every document that audit() returns is valid.
  expect_silent(validate_results(result$value))
  checks <- unlist(case[["checks"]])
  findings <- Filter(function(finding) finding[["check"]] %in% checks,
                     result$value$document$findings)
  expect_length(findings, length(expected))
  exact <- unlist(case[["exact"]])
  for (i in seq_len(min(length(findings), length(expected)))) {
    expect_audit_finding(findings[[i]], expected[[i]], exact, paste(label, "finding", i))
  }
}

run_audit_corpus_case <- function(case) {
  expected <- case[["expected"]]
  if (!is.null(expected[["issue"]])) {
    # The run stops before any check, so the case needs no check.
    expect_issue(run_audit_case(case, case[["privacy"]] %||% "internal"), expected[["issue"]],
                 case$id)
    return(invisible())
  }
  # Without lpSolve, outcome.separation is not available (package_missing).
  if ("outcome.separation" %in% unlist(case[["checks"]])) {
    skip_if_not_installed("lpSolve")
  }
  expect_audit_findings(run_audit_case(case, "internal"), expected[["findings"]], case, case$id)
  if (!is.null(expected[["shareable"]])) {
    expect_audit_findings(run_audit_case(case, "shareable"), expected[["shareable"]], case,
                          paste(case$id, "shareable"))
  }
}

for (file in c("assignment.json", "design.json", "identifiability.json", "keys.json",
               "labels.json", "outcome.json", "privacy.json", "sample.json", "structure.json")) {
  for (case in corpus_cases("audits", file)) {
    local({
      case <- case
      test_that(paste("audit corpus case", case$id, "passes"), {
        run_audit_corpus_case(case)
      })
    })
  }
}
