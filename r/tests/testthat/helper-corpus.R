# Helpers that run the cases of the conformance corpora, which
# spec/tools/vendor.py copies from fixtures/conformance/ into tests/conformance/
# (fixtures/conformance/<corpus>/README.md describes each corpus).
# Inputs are built from bytes and strings read by the strict reader, never
# from non-ASCII string literals, which a C locale would leave unmarked.

# The directory of a corpus, or the conformance directory itself.
corpus_directory <- function(...) {
  test_path("..", "conformance", ...)
}

corpus_cases <- function(directory, file) {
  path <- corpus_directory(directory, file)
  if (!file.exists(path)) {
    stop(sprintf("The corpus file %s/%s is missing.", directory, file))
  }
  cases <- read_json_strict(path, "data")[["cases"]]
  # Cases that only another language can hold are left to it.
  Filter(function(case) is.null(case[["languages"]]) || "R" %in% unlist(case[["languages"]]), cases)
}

hex_raw <- function(hex) {
  mixedcheck:::hex_to_raw(hex)
}

utf8_bytes <- function(text) {
  charToRaw(enc2utf8(text))
}

# The input of a reader case: a raw vector, or a path for the cases of files.
reader_input <- function(case) {
  if (!is.null(case[["input"]])) {
    return(utf8_bytes(case[["input"]]))
  }
  if (!is.null(case[["input_hex"]])) {
    return(hex_raw(case[["input_hex"]]))
  }
  switch(case[["file"]],
    missing = file.path(tempdir(), "mixedcheck-no-such-file.json"),
    directory = tempdir(),
    stop("Unknown file case.")
  )
}

# Calls f and returns either list(value = ) or list(issues = ) for an error of
# class mixedcheck_error.
capture_issues <- function(f) {
  tryCatch(list(value = f()), mixedcheck_error = function(e) list(issues = e$issues))
}

# Compares the one issue of a result with the expected issue, its code, its
# message as bytes and its offset or pointer, or their absence, in one
# expectation.
expect_issue <- function(result, expected, label) {
  if (is.null(result$issues)) {
    fail(sprintf("%s: expected %s, got no issue.", label, expected[["code"]]))
    return(invisible())
  }
  issue <- result$issues[[1L]]
  bytes <- function(text) if (is.null(text)) NULL else utf8_bytes(text)
  offset <- expected[["offset"]]
  expect_same(
    list(count = length(result$issues), code = issue[["code"]],
         message = bytes(issue[["message"]]), offset = issue[["offset"]],
         pointer = bytes(issue[["pointer"]])),
    list(count = 1L, code = expected[["code"]], message = bytes(expected[["message"]]),
         offset = if (!is.null(offset)) as.integer(offset), pointer = bytes(expected[["pointer"]])),
    label = label
  )
}

# Compares the canonical bytes of a value read, their hash and, for a
# number, its bits with the expected ones in one expectation.
expect_canonical <- function(result, expected, profile, label) {
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected canonical bytes, got %s.", label, result$issues[[1L]][["code"]]))
    return(invisible())
  }
  bytes <- canonical_bytes(result$value, profile)
  bits <- if (!is.null(expected[["bits"]])) mixedcheck:::double_bits(result$value)
  expect_same(list(bytes = bytes, sha256 = hash_bytes(bytes), bits = bits),
              list(bytes = utf8_bytes(expected[["canonical"]]), sha256 = expected[["sha256"]],
                   bits = expected[["bits"]]),
              label = label)
}

profiles <- c("plain", "data", "hashable")

run_reader_case <- function(case) {
  source <- reader_input(case)
  for (profile in intersect(profiles, names(case[["expected"]]))) {
    expected <- case[["expected"]][[profile]]
    label <- paste(case$id, profile)
    result <- capture_issues(function() read_json_strict(source, profile))
    if (!is.null(expected[["issue"]])) {
      expect_issue(result, expected[["issue"]], label)
    } else {
      expect_canonical(result, expected, profile, label)
    }
  }
}

# Replaces the value at the tokens of a pointer.
set_at_pointer <- function(x, tokens, value) {
  if (length(tokens) == 0L) {
    return(value)
  }
  token <- tokens[1L]
  index <- if (is.null(names(x))) as.integer(token) + 1L else token
  x[[index]] <- set_at_pointer(x[[index]], tokens[-1L], value)
  x
}

pointer_tokens <- function(pointer) {
  if (identical(pointer, "")) {
    return(character(0))
  }
  tokens <- strsplit(substring(pointer, 2L), "/", fixed = TRUE)[[1L]]
  gsub("~0", "~", gsub("~1", "/", tokens, fixed = TRUE), fixed = TRUE)
}

substitute_value <- function(x, substitution) {
  replacement <- if (!is.null(substitution[["double"]])) {
    mixedcheck:::bits_double(substitution[["double"]])
  } else if (!is.null(substitution[["wrap"]])) {
    value <- json_pointer_value(x, substitution[["pointer"]])
    for (i in seq_len(substitution[["wrap"]])) {
      value <- list(value)
    }
    value
  } else if (!is.null(substitution[["r_string"]])) {
    text <- rawToChar(hex_raw(substitution[["r_string"]][["hex"]]))
    Encoding(text) <- substitution[["r_string"]][["encoding"]]
    text
  } else {
    stop("Substitution not available in R.")
  }
  set_at_pointer(x, pointer_tokens(substitution[["pointer"]]), replacement)
}

json_pointer_value <- function(x, pointer) {
  mixedcheck:::json_pointer_get(x, pointer)
}

writer_value <- function(case) {
  value <- if (!is.null(case[["double"]])) {
    mixedcheck:::bits_double(case[["double"]])
  } else {
    read_json_strict(utf8_bytes(case[["json"]]), "plain")
  }
  for (substitution in case[["substitutions"]]) {
    value <- substitute_value(value, substitution)
  }
  value
}

run_writer_case <- function(case) {
  value <- writer_value(case)
  for (profile in intersect(profiles, names(case[["expected"]]))) {
    expected <- case[["expected"]][[profile]]
    label <- paste(case$id, profile)
    result <- capture_issues(function() canonical_bytes(value, profile))
    if (!is.null(expected[["issue"]])) {
      expect_issue(result, expected[["issue"]], label)
    } else if (!is.null(result$issues)) {
      fail(sprintf("%s: expected canonical bytes, got %s.", label, result$issues[[1L]][["code"]]))
    } else {
      expect_same(list(bytes = result$value, sha256 = hash_bytes(result$value)),
                  list(bytes = utf8_bytes(expected[["canonical"]]), sha256 = expected[["sha256"]]),
                  label = label)
    }
  }
}

# Runs a corpus file whose cases are reader or writer cases.
run_json_cases <- function(cases) {
  for (case in cases) {
    if (!is.null(case[["json"]]) || !is.null(case[["double"]])) {
      run_writer_case(case)
    } else {
      run_reader_case(case)
    }
  }
}

# The path of an input file of a corpus, relative to its directory.
corpus_file <- function(directory, path) {
  file.path(corpus_directory(directory), path)
}

# Compares a list of issues with the expected list exactly: the codes, the
# messages and the locations, in order.
expect_issues <- function(result, expected, label) {
  if (is.null(result$issues)) {
    fail(sprintf("%s: expected %s, got no issue.", label, expected[[1L]][["code"]]))
    return(invisible())
  }
  expect_length(result$issues, length(expected))
  for (i in seq_len(min(length(expected), length(result$issues)))) {
    expect_issue(list(issues = result$issues[i]), expected[[i]], paste(label, i))
  }
}

# Runs the cases of a file of the declaration or YAML corpus: a valid case
# gives the canonical bytes and the hash of the declaration as read, and an
# invalid case gives its list of issues (fixtures/conformance/declarations/
# README.md).
run_declaration_cases <- function(directory, file) {
  cases <- corpus_cases(directory, file)
  expect_gt(length(cases), 0L)
  for (case in cases) {
    path <- corpus_file(directory, case[["path"]])
    minimal <- isTRUE(case[["minimal"]])
    result <- capture_issues(function() validate_declaration(path, minimal = minimal))
    expected <- case[["expected"]]
    if (!is.null(expected[["issues"]])) {
      expect_issues(result, expected[["issues"]], case$id)
    } else {
      expect_canonical(result, expected, "hashable", case$id)
    }
  }
}

# The data frame of a case of the formula corpus: one column for each member of its data, numeric,
# character or logical, with NA for null. Strings come from the strict reader
# and are marked UTF-8.
corpus_data_frame <- function(data) {
  special <- c("NaN" = NaN, "Infinity" = Inf, "-Infinity" = -Inf)
  columns <- lapply(data, function(values) {
    present <- Filter(Negate(is.null), values)
    # A column with a number is numeric, and its strings are special values.
    if (any(vapply(present, is.numeric, NA))) {
      return(vapply(values, function(v) {
        if (is.null(v)) NA_real_ else if (is.character(v)) special[[v]] else v
      }, 0))
    }
    if (is.character(present[[1L]])) {
      return(vapply(values, function(v) if (is.null(v)) NA_character_ else v, ""))
    }
    vapply(values, function(v) if (is.null(v)) NA else v, NA)
  })
  frame <- list2DF(unname(columns))
  names(frame) <- names(data)
  frame
}

# Whether two real values match within the tolerance of conventions.md
# (Comparison across languages), with its exceptions for design.collinearity,
# design.scale_disparity, identifiability.gram_rank and outcome.separation,
# whose tolerance is the parameter bound_tolerance of its entry. 'NaN',
# 'Infinity' and '-Infinity' match only themselves.
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
  if (check == "identifiability.gram_rank" && name == "smallest_eigenvalue") {
    return(abs(x - y) <= 1e-12 + 1e-9 * max(1, m))
  }
  if (check == "outcome.separation") {
    tolerance <- json_number_values(
      registry_entry(check)[["parameters"]][["bound_tolerance"]][["value"]])
    return(abs(x - y) <= if (name == "bounds") tolerance else tolerance * max(1, m))
  }
  abs(x - y) <= 1e-12 + 1e-9 * m
}
