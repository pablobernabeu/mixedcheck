# The table corpus: CSV inputs read with the strict table reader, with or
# without the table block of a declaration (fixtures/conformance/tables/
# README.md). Cases with a formula also give the design and analysis samples
# of the IR that formula_ir() builds from the formula, the declaration and
# the table read, numbered from 0 in the corpus.

# The input of a table case: the path of its CSV file, or a path that does
# not exist or is a directory.
table_case_path <- function(case) {
  if (!is.null(case[["path"]])) {
    return(corpus_file("tables", case[["path"]]))
  }
  switch(case[["file"]],
    missing = file.path(tempdir(), "mixedcheck-no-such-file.csv"),
    directory = tempdir(),
    stop("Unknown file case.")
  )
}

# The value that the reader returns for one expected value of a column, as
# the corpus README describes: null is NA of the column's type, and 'NaN',
# 'Infinity' and '-Infinity' of a number column are the special values.
expected_column_values <- function(values, type) {
  if (type %in% c("integer", "number")) {
    return(vapply(values, function(value) {
      if (is.null(value)) {
        return(NA_real_)
      }
      if (is.character(value)) {
        return(switch(value, "NaN" = NaN, "Infinity" = Inf, "-Infinity" = -Inf))
      }
      value
    }, 0))
  }
  if (type == "boolean") {
    return(vapply(values, function(value) if (is.null(value)) NA else value, NA))
  }
  vapply(values, function(value) if (is.null(value)) NA_character_ else value, "")
}

# Compares the columns that the reader returned with the expected columns:
# names and strings byte for byte, without normalisation, numbers by value,
# so that negative zero equals zero, and NaN, the infinities and NA apart.
expect_table_columns <- function(result, expected, label) {
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected columns, got %s.", label, result$issues[[1L]][["code"]]))
    return(invisible())
  }
  table <- result$value
  types <- attr(table, "types")
  expect_same(
    list(data_frame = is.data.frame(table), columns = length(table),
         names = lapply(names(table), utf8_bytes), type_names = lapply(names(types), utf8_bytes)),
    list(data_frame = TRUE, columns = length(expected),
         names = lapply(expected, function(column) utf8_bytes(column[["name"]])),
         type_names = lapply(names(table), utf8_bytes)),
    label = label
  )
  # The facts of each column, compared in one expectation.
  for (j in seq_along(expected)) {
    column <- expected[[j]]
    type <- column[["type"]]
    want <- expected_column_values(column[["values"]], type)
    got <- table[[j]]
    known <- !is.na(want)
    facts <- list(type = unname(types[j]), length = length(got))
    expected_facts <- list(type = type, length = length(want))
    if (type %in% c("integer", "number")) {
      facts <- c(facts, list(double = is.double(got), na = is.na(got) & !is.nan(got),
                             nan = is.nan(got), equal = all(got[known] == want[known])))
      expected_facts <- c(expected_facts, list(double = TRUE, na = is.na(want) & !is.nan(want),
                                               nan = is.nan(want), equal = TRUE))
    } else if (type == "boolean") {
      facts$values <- got
      expected_facts$values <- want
    } else {
      facts <- c(facts, list(character = is.character(got), na = is.na(got),
                             bytes = lapply(got[known], utf8_bytes),
                             utf8 = all(Encoding(got[known & has_non_ascii_bytes(got)]) == "UTF-8")))
      expected_facts <- c(expected_facts, list(character = TRUE, na = is.na(want),
                                               bytes = lapply(want[known], utf8_bytes), utf8 = TRUE))
    }
    expect_same(facts, expected_facts, label = paste(label, "column", j))
  }
}

has_non_ascii_bytes <- function(x) {
  grepl("[^\\x01-\\x7F]", x, useBytes = TRUE, perl = TRUE)
}

# Compares the design and analysis samples of the IR of a case's formula
# with those the case gives, which count rows from 0.
expect_table_samples <- function(table, case, label) {
  ir <- capture_issues(function() formula_ir(case[["formula"]], case[["declaration"]], table))
  if (!is.null(ir$issues)) {
    fail(sprintf("%s: expected an IR, got %s.", label, ir$issues[[1L]][["code"]]))
    return(invisible())
  }
  samples <- design_samples(ir$value, table)
  expected <- case[["expected"]]
  expect_same(samples$design_sample - 1L, as.integer(unlist(expected[["design_sample"]])),
              label = paste(label, "design sample"))
  expect_same(samples$analysis_sample - 1L,
              as.integer(unlist(expected[["analysis_sample"]])),
              label = paste(label, "analysis sample"))
}

run_table_cases <- function(file) {
  cases <- corpus_cases("tables", file)
  expect_gt(length(cases), 0L)
  for (case in cases) {
    result <- capture_issues(function() read_table(table_case_path(case), case[["declaration"]]))
    expected <- case[["expected"]]
    if (!is.null(expected[["issue"]])) {
      expect_issue(result, expected[["issue"]], case$id)
    } else {
      expect_table_columns(result, expected[["columns"]], case$id)
      if (!is.null(case[["formula"]]) && is.null(result$issues)) {
        expect_table_samples(result$value, case, case$id)
      }
    }
  }
}

for (file in c("edgezoo.json", "edge.json", "input.json", "records.json", "header.json",
               "values.json", "inference.json", "keys.json", "precedence.json",
               "samples.json")) {
  test_that(paste("every case of tables", file, "passes"), {
    run_table_cases(file)
  })
}

test_that("the table corpus holds 194 cases, 10 of them with a formula", {
  files <- c("edgezoo.json", "edge.json", "input.json", "records.json", "header.json",
             "values.json", "inference.json", "keys.json", "precedence.json", "samples.json")
  expect_same(sum(vapply(files, function(file) length(corpus_cases("tables", file)), 0L)),
              194L)
  with_formula <- vapply(files, function(file) {
    sum(vapply(corpus_cases("tables", file), function(case) !is.null(case[["formula"]]), NA))
  }, 0L)
  expect_same(sum(with_formula), 10L)
})
