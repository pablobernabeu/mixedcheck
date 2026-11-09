# The formula corpus: formulas with their declaration, data, coding, weights
# and sample columns, and the expected IR with its hash, with the design
# matrices of the design sample or the issue that they report for some cases,
# or the one issue that the builder reports
# (fixtures/conformance/formulas/README.md).

formula_files <- c("ordinary.json", "interactions.json", "nested.json", "crossed.json",
                   "double_bar.json", "offsets.json", "malformed.json", "context.json")

# The design matrices of a case, which give the rows of the design sample
# from 0, X, the columns that the sequential rule drops and Z with its
# columns, whose terms count from 0.
expect_corpus_matrices <- function(ir, data, expected, label) {
  result <- capture_issues(function() design_matrices(ir, data))
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected matrices, got %s.", label, result$issues[[1L]][["code"]]))
    return(invisible())
  }
  m <- result$value
  rows <- as.integer(unlist(expected[["rows"]]))
  expect_identical(m$design_sample - 1L, rows, label = paste(label, "rows"))
  width <- length(ir$fixed$columns)
  x <- matrix(as.double(unlist(expected[["x"]])), ncol = width, byrow = TRUE)
  expect_identical(unname(m$x), x, label = paste(label, "X"))
  expect_identical(m$x_columns, vapply(ir$fixed$columns, function(column) column$name, ""),
                   label = paste(label, "names of X"))
  expect_identical(as.character(colnames(m$x)), m$x_columns, label = paste(label, "names of X"))
  expect_identical(m$x_dropped, as.character(unlist(expected[["x_dropped"]])),
                   label = paste(label, "dropped columns"))
  if (is.null(expected[["z"]])) {
    expect_identical(dim(m$z), c(length(rows), 0L), label = paste(label, "Z"))
    return(invisible())
  }
  expect_s4_class(m$z, "dgCMatrix")
  columns <- expected[["z_columns"]]
  z <- matrix(unlist(expected[["z"]]), ncol = length(columns), byrow = TRUE)
  expect_identical(unname(as.matrix(m$z)), z, label = paste(label, "Z"))
  expect_identical(m$z_columns, data.frame(
    term = vapply(columns, function(column) as.integer(column$term) + 1L, 0L),
    level = vapply(columns, function(column) column$level, ""),
    column = vapply(columns, function(column) column$column, ""),
    stringsAsFactors = FALSE
  ), label = paste(label, "columns of Z"))
}

run_formula_case <- function(case) {
  data <- if (!is.null(case[["data"]])) corpus_data_frame(case[["data"]])
  result <- capture_issues(function() {
    formula_ir(case[["formula"]], case[["declaration"]], data, case[["coding"]],
               case[["weights"]], as.character(unlist(case[["sample_columns"]])))
  })
  expected <- case[["expected"]]
  if (is.null(expected[["ir"]])) {
    expect_issue(result, expected[["issue"]], case$id)
    return(invisible())
  }
  if (!is.null(result$issues)) {
    fail(sprintf("%s: expected an IR, got %s: %s", case$id, result$issues[[1L]][["code"]],
                 result$issues[[1L]][["message"]]))
    return(invisible())
  }
  bytes <- canonical_bytes(result$value, "hashable")
  expect_identical(bytes, canonical_bytes(expected[["ir"]], "hashable"), label = case$id)
  expect_identical(hash_bytes(bytes), expected[["ir_hash"]], label = case$id)
  if (!is.null(expected[["matrices"]])) {
    expect_corpus_matrices(result$value, data, expected[["matrices"]], case$id)
  }
  if (!is.null(expected[["issue"]])) {
    expect_issue(capture_issues(function() design_matrices(result$value, data)),
                 expected[["issue"]], paste(case$id, "design matrices"))
  }
}

for (file in formula_files) {
  test_that(paste("every case of formulas", file, "passes"), {
    cases <- corpus_cases("formulas", file)
    expect_gt(length(cases), 0L)
    for (case in cases) {
      run_formula_case(case)
    }
  })
}

test_that("the formula corpus holds 246 cases, 33 with matrices and 7 with their issue", {
  cases <- unlist(lapply(formula_files, function(file) corpus_cases("formulas", file)),
                  recursive = FALSE)
  expect_length(cases, 246L)
  expect_identical(sum(vapply(cases, function(case) {
    !is.null(case[["expected"]][["matrices"]])
  }, NA)), 33L)
  expect_identical(sum(vapply(cases, function(case) {
    !is.null(case[["expected"]][["ir"]]) && !is.null(case[["expected"]][["issue"]])
  }, NA)), 7L)
})
