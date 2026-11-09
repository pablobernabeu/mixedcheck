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
  expect_true(is.data.frame(table), label = label)
  expect_identical(length(table), length(expected), label = label)
  types <- attr(table, "types")
  expect_identical(lapply(names(table), utf8_bytes),
                   lapply(expected, function(column) utf8_bytes(column[["name"]])),
                   label = label)
  expect_identical(lapply(names(types), utf8_bytes), lapply(names(table), utf8_bytes),
                   label = label)
  for (j in seq_along(expected)) {
    column <- expected[[j]]
    type <- column[["type"]]
    where <- paste(label, "column", j)
    expect_identical(unname(types[j]), type, label = where)
    want <- expected_column_values(column[["values"]], type)
    got <- table[[j]]
    expect_identical(length(got), length(want), label = where)
    if (type %in% c("integer", "number")) {
      expect_true(is.double(got), label = where)
      expect_identical(is.na(got) & !is.nan(got), is.na(want) & !is.nan(want), label = where)
      expect_identical(is.nan(got), is.nan(want), label = where)
      known <- !is.na(want)
      expect_true(all(got[known] == want[known]), label = where)
    } else if (type == "boolean") {
      expect_identical(got, want, label = where)
    } else {
      expect_true(is.character(got), label = where)
      expect_identical(is.na(got), is.na(want), label = where)
      known <- !is.na(want)
      expect_identical(lapply(got[known], utf8_bytes), lapply(want[known], utf8_bytes),
                       label = where)
      expect_true(all(Encoding(got[known & has_non_ascii_bytes(got)]) == "UTF-8"),
                  label = where)
    }
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
  expect_identical(samples$design_sample - 1L, as.integer(unlist(expected[["design_sample"]])),
                   label = paste(label, "design sample"))
  expect_identical(samples$analysis_sample - 1L,
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
  expect_identical(sum(vapply(files, function(file) length(corpus_cases("tables", file)), 0L)),
                   194L)
  with_formula <- vapply(files, function(file) {
    sum(vapply(corpus_cases("tables", file), function(case) !is.null(case[["formula"]]), NA))
  }, 0L)
  expect_identical(sum(with_formula), 10L)
})
