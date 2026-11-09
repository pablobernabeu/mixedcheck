# Helpers that run the cases of the conformance corpora installed with the
# package (fixtures/conformance/, described in each directory's README.md).
# Inputs are built from bytes and strings read by the strict reader, never
# from non-ASCII string literals, which a C locale would leave unmarked.

corpus_cases <- function(directory, file) {
  path <- system.file("fixtures", "conformance", directory, file, package = "mixedcheck")
  if (!nzchar(path)) {
    stop(sprintf("The corpus file %s/%s is not installed.", directory, file))
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

expect_issue <- function(result, expected, label) {
  if (is.null(result$issues)) {
    fail(sprintf("%s: expected %s, got no issue.", label, expected[["code"]]))
    return(invisible())
  }
  expect_length(result$issues, 1L)
  issue <- result$issues[[1L]]
  expect_identical(issue[["code"]], expected[["code"]], label = label)
  expect_identical(utf8_bytes(issue[["message"]]), utf8_bytes(expected[["message"]]), label = label)
  if (!is.null(expected[["offset"]])) {
    expect_identical(issue[["offset"]], as.integer(expected[["offset"]]), label = label)
  } else {
    expect_null(issue[["offset"]], label = label)
  }
  if (!is.null(expected[["pointer"]])) {
    expect_identical(utf8_bytes(issue[["pointer"]]), utf8_bytes(expected[["pointer"]]), label = label)
  } else {
    expect_null(issue[["pointer"]], label = label)
  }
}

expect_canonical <- function(result, expected, profile, label) {
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected canonical bytes, got %s.", label, result$issues[[1L]][["code"]]))
    return(invisible())
  }
  bytes <- canonical_bytes(result$value, profile)
  expect_identical(bytes, utf8_bytes(expected[["canonical"]]), label = label)
  expect_identical(hash_bytes(bytes), expected[["sha256"]], label = label)
  if (!is.null(expected[["bits"]])) {
    expect_identical(mixedcheck:::double_bits(result$value), expected[["bits"]], label = label)
  }
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
      expect_identical(result$value, utf8_bytes(expected[["canonical"]]), label = label)
      expect_identical(hash_bytes(result$value), expected[["sha256"]], label = label)
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
  file.path(system.file("fixtures", "conformance", directory, package = "mixedcheck"), path)
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
