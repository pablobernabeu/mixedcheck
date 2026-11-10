# The audit corpus: every case runs through audit() with the commitment key
# 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0, and its findings, or the issue
# that refuses the run, are compared with the expected ones as
# fixtures/conformance/audits/README.md describes. Every document that
# audit() returns is validated with validate_results(), and every program of
# outcome.separation is solved through its dual.

audit_corpus_key <- paste(sprintf("%02x", 0:31), collapse = "")

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
  with_audit_time(capture_issues(function() do.call(audit, args)))
}

# Whether two real values match within the tolerance of conventions.md
# (Comparison across languages), with its exceptions for design.collinearity,
# design.scale_disparity and outcome.separation. 'NaN', 'Infinity' and
# '-Infinity' match only themselves.
reals_match <- function(x, y, check, name) {
  if (is.character(x) || is.character(y)) {
    return(identical(x, y))
  }
  m <- max(abs(x), abs(y))
  if (check == "design.collinearity" && name %in% c("gvif", "gvif_per_df")) {
    return(abs(x - y) <= 1e-12 + max(1e-9, 1e-13 * m) * m)
  }
  if (check == "design.scale_disparity" && name == "condition_number") {
    return(abs(x - y) <= 1e-12 + max(1e-9, 1e-14 * m) * m)
  }
  if (check == "outcome.separation") {
    tolerance <- 1e-6
    return(abs(x - y) <= if (name == "bounds") tolerance else tolerance * max(1, m))
  }
  abs(x - y) <= 1e-12 + 1e-9 * m
}

# The value of a real statistic that a finding writes, as a double, with
# 'NaN', 'Infinity' and '-Infinity' read as those values, or NULL when the
# finding does not write it.
written_real <- function(finding, name) {
  value <- unlist(finding[["statistics"]][[name]][["value"]])
  if (is.null(value)) {
    return(NULL)
  }
  if (is.character(value)) c("NaN" = NaN, "Infinity" = Inf, "-Infinity" = -Inf)[[value]] else value
}

# The form of a message that the text of a finding renders, the template or
# the fallback, with the renderings of its arguments other than real
# statistics, in the order of the form. A real statistic must render as
# registry.md (Messages) renders the value that the finding writes, so that
# the form can render only when the finding writes it. NULL when the text
# renders neither form.
message_form <- function(finding) {
  entry <- registry_entry(finding[["check"]])
  message <- entry[["messages"]][[finding[["message"]][["id"]]]]
  text <- finding[["message"]][["text"]]
  for (form in c("template", "fallback")) {
    template <- message[[form]]
    if (is.null(template)) {
      next
    }
    pieces <- regmatches(template, gregexpr("\\{[a-z][a-z0-9_]*\\}", template),
                         invert = NA)[[1L]]
    pattern <- character(0)
    renders <- TRUE
    for (i in seq_along(pieces)) {
      piece <- pieces[i]
      if (i %% 2L == 1L) {
        pattern <- c(pattern, regex_literal(piece))
        next
      }
      arg <- message[["args"]][[substr(piece, 2L, nchar(piece) - 1L)]]
      kind <- if (identical(arg[["source"]], "statistic")) {
        entry[["statistics"]][[arg[["name"]]]][["kind"]]
      }
      if (!identical(kind, "real")) {
        pattern <- c(pattern, "(.*?)")
        next
      }
      value <- written_real(finding, arg[["name"]])
      if (is.null(value)) {
        renders <- FALSE
        break
      }
      pattern <- c(pattern, regex_literal(real_text(value, arg[["digits"]])))
    }
    if (!renders) {
      next
    }
    found <- regmatches(text, regexec(paste0("^", paste(pattern, collapse = ""), "$"), text,
                                      perl = TRUE))[[1L]]
    if (length(found)) {
      return(list(form = form, arguments = found[-1L]))
    }
  }
  NULL
}

# A regular expression that matches the text literally.
regex_literal <- function(text) {
  gsub("([][{}()|^$.*+?\\\\])", "\\\\\\1", text, perl = TRUE)
}

# Whether the messages of two findings of a check match (conventions.md,
# Comparison across languages): they have the same identifier, both texts
# render its template, or both its fallback, every argument other than a
# real statistic renders identically, the two values of every real statistic
# that the form renders match within the tolerance, and each text renders
# the values of its own finding. The renderings of a real may then differ in
# any way, as neighbouring roundings, in their notation on either side of
# 1e15 or as under 0.1 and 0.1.
message_texts_match <- function(actual, expected) {
  if (!identical(actual[["message"]][["id"]], expected[["message"]][["id"]])) {
    return(FALSE)
  }
  a <- message_form(actual)
  b <- message_form(expected)
  if (is.null(a) || !identical(a, b)) {
    return(FALSE)
  }
  check <- expected[["check"]]
  entry <- registry_entry(check)
  message <- entry[["messages"]][[expected[["message"]][["id"]]]]
  template <- message[[a$form]]
  for (placeholder in names(message[["args"]])) {
    name <- message[["args"]][[placeholder]][["name"]]
    if (!identical(message[["args"]][[placeholder]][["source"]], "statistic") ||
        !identical(entry[["statistics"]][[name]][["kind"]], "real") ||
        !grepl(paste0("{", placeholder, "}"), template, fixed = TRUE)) {
      next
    }
    x <- written_real(actual, name)
    y <- written_real(expected, name)
    same <- if (all(is.finite(c(x, y)))) reals_match(x, y, check, name) else identical(x, y)
    if (!same) {
      return(FALSE)
    }
  }
  TRUE
}

# Compares one finding with its expected form: exactly, apart from the
# values of real statistics, compared within the tolerance or bit for bit
# for those that 'exact' lists, the message text, and, for a finding that is
# near_threshold in the expected findings or in the run, the finding status,
# the message and threshold_proximity, and for outcome.separation and
# identifiability.gram_rank also the values that their solver or their
# comparisons with rank_tolerance decide (conventions.md, Comparison across
# languages).
expect_audit_finding <- function(actual, expected, exact, label) {
  check <- expected[["check"]]
  near <- function(finding) {
    identical(finding[["status"]][["threshold_proximity"]][["value"]], "near_threshold")
  }
  near <- near(expected) || near(actual)
  solved <- if (near && check == "outcome.separation") {
    c("verdict", "optimum", "margin", "bounds", "columns_involved")
  } else if (near && check == "identifiability.gram_rank") {
    c("rank", "verdict", "vanishing_parameters", "confounded_parameters", "smallest_eigenvalue")
  } else {
    character(0)
  }
  reals <- setdiff(names(Filter(function(s) s[["kind"]] %in% c("real", "reals"),
                                expected[["statistics"]])), solved)
  strip <- function(finding) {
    for (name in intersect(reals, names(finding[["statistics"]]))) {
      finding[["statistics"]][[name]][["value"]] <- "real"
    }
    if (!is.null(finding[["message"]])) {
      finding[["message"]][["text"]] <- "text"
    }
    if (near) {
      finding[["status"]][["finding"]] <- NULL
      finding[["status"]][["threshold_proximity"]] <- NULL
      finding[["message"]] <- NULL
      finding[["statistics"]][solved] <- NULL
    }
    finding
  }
  expect_same(rawToChar(canonical_bytes(strip(actual), "data")),
              rawToChar(canonical_bytes(strip(expected), "data")), label = label)
  for (name in reals) {
    x <- actual[["statistics"]][[name]][["value"]]
    y <- expected[["statistics"]][[name]][["value"]]
    if (is.null(x) || is.null(y)) {
      next
    }
    here <- paste(label, name)
    if (paste0(check, ":", name) %in% exact) {
      expect_same(mixedcheck:::double_bits(unlist(x)), mixedcheck:::double_bits(unlist(y)),
                  label = here)
    } else {
      expect_length(x, length(y))
      if (length(x) == length(y)) {
        expect_holds(all(mapply(reals_match, x, y, check, name)), label = here)
      }
    }
  }
  if (!near && !is.null(expected[["message"]])) {
    if (message_texts_match(actual, expected)) {
      succeed()
    } else {
      fail(sprintf("%s message: '%s' does not match the expected '%s'.", label,
                   actual[["message"]][["text"]], expected[["message"]][["text"]]))
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
  # With it, the dual gives a verified solution of every program of the
  # corpus, so that the program itself is never solved.
  formulations <- character(0)
  if ("outcome.separation" %in% unlist(case[["checks"]])) {
    skip_if_not_installed("lpSolve")
    solver <- separation_solver
    local_mocked_bindings(separation_solver = function(formulation, ...) {
      formulations <<- c(formulations, formulation)
      solver(formulation, ...)
    })
  }
  expect_audit_findings(run_audit_case(case, "internal"), expected[["findings"]], case, case$id)
  expect_false("primal" %in% formulations, label = paste(case$id, "solves a program itself"))
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

# A finding of a check with the given statistics and message, whose text is
# rendered from them unless 'text' gives it.
message_finding <- function(check, id, values, scope = list(), text = NULL,
                            written = names(values)) {
  entry <- registry_entry(check)
  statistics <- lapply(names(values), function(name) {
    list(kind = entry[["statistics"]][[name]][["kind"]],
         value = if (name %in% written) values[[name]])
  })
  names(statistics) <- names(values)
  list(check = check, scope = scope, statistics = statistics,
       message = list(id = id, text = text %||% render_message(entry, id, scope, values, written)))
}

test_that("messages match by their values, whatever the renderings of their reals", {
  gvif <- function(value, term = "x", id = "high") {
    message_finding("design.collinearity", id, list(df = 1, gvif = value, gvif_per_df = value),
                    scope = list(term = term))
  }
  ratio <- function(value) {
    message_finding("design.scale_disparity", "disparate",
                    list(scaled_columns = c("x1", "x2"), sd_ratio = value))
  }
  events <- function(per_column, events = 1, text = NULL, written = c("events", "non_events",
                                                                       "events_per_column")) {
    message_finding("outcome.minority_events", "events_model",
                    list(events = events, non_events = 20, events_per_column = per_column),
                    text = text, written = written)
  }
  # Values within the tolerance whose renderings differ by several units of
  # the last place, in notation, as under 0.1 and 0.1 or as neighbouring
  # roundings. The doubles before 1e15 and 0.05 are built by arithmetic, since
  # R's parser can misround literals of 17 significant digits on macOS on arm64.
  pairs <- list(list(gvif(4e5), gvif(400000.015)), list(ratio(2e9), ratio(2000000001.5)),
                list(ratio(1e15 - 0.125), ratio(1e15)),
                list(events(0.05 - 2^-57), events(0.05)),
                list(gvif(1.255), gvif(1.255 + 1e-12)))
  for (pair in pairs) {
    expect_false(identical(pair[[1L]]$message$text, pair[[2L]]$message$text))
    expect_true(message_texts_match(pair[[1L]], pair[[2L]]))
    expect_true(message_texts_match(pair[[2L]], pair[[1L]]))
  }
  expect_true(message_texts_match(events(1 / 21), events(1 / 21)))
  fallback <- events(1 / 21, written = c("events", "non_events"))
  expect_true(message_texts_match(fallback, fallback))
  # An argument other than a real that differs, values outside the
  # tolerance, a text that does not render its own value, a template against
  # its fallback and two messages.
  expect_false(message_texts_match(gvif(2, term = "x"), gvif(2, term = "z")))
  expect_false(message_texts_match(events(1 / 21, events = 1), events(1 / 21, events = 2)))
  expect_false(message_texts_match(events(1 / 21), events(0.1)))
  expect_false(message_texts_match(gvif(4e5), gvif(400000.02)))
  wrong <- "The outcome has 1 event and 20 non-events, or 0.0 minority events per fixed-effects column."
  expect_false(message_texts_match(events(1 / 21), events(1 / 21, text = wrong)))
  expect_false(message_texts_match(events(1 / 21, text = wrong), events(1 / 21, text = wrong)))
  expect_false(message_texts_match(events(1 / 21), fallback))
  expect_false(message_texts_match(gvif(7, id = "moderate"), gvif(7, id = "high")))
})
