# Expectations for the loops over corpus cases, which register thousands of
# them. In a package's tests, expect_identical() and expect_true() compare
# through waldo inside the reporter's reproducible output, which costs a few
# milliseconds each. These compare with identical() and register a success
# directly, and hand a value that differs to the testthat expectation, which
# fails with its usual description of the difference.

expect_same <- function(object, expected, label = NULL) {
  if (identical(object, expected)) {
    return(invisible(succeed()))
  }
  label <- label %||% paste(deparse(substitute(object)), collapse = " ")
  expect_identical(object, expected, label = label)
}

expect_holds <- function(object, label = NULL) {
  if (isTRUE(object)) {
    return(invisible(succeed()))
  }
  label <- label %||% paste(deparse(substitute(object)), collapse = " ")
  expect_true(object, label = label)
}
