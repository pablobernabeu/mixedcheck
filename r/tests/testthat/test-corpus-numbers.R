# The number corpus: ECMAScript formatting, correctly rounded reading, the
# number rules of the hashable profile and decimal constants
# (fixtures/conformance/numbers/README.md).

run_decimal_constants <- function(cases) {
  for (case in cases) {
    x <- mixedcheck:::bits_double(case[["double"]])
    expect_identical(mixedcheck:::decimal_string(x, case[["digits"]]), case[["expected"]][["decimal"]],
                     label = case$id)
  }
}

test_that("every case of numbers format.json and read.json passes", {
  run_json_cases(corpus_cases("numbers", "format.json"))
  run_json_cases(corpus_cases("numbers", "read.json"))
})

test_that("every case of numbers decimal_constants.json passes", {
  run_decimal_constants(corpus_cases("numbers", "decimal_constants.json"))
})

test_that("a decimal comma in OutDec changes no number", {
  format_cases <- corpus_cases("numbers", "format.json")
  read_cases <- corpus_cases("numbers", "read.json")
  constant_cases <- corpus_cases("numbers", "decimal_constants.json")
  old <- options(OutDec = ",")
  on.exit(options(old), add = TRUE)
  run_json_cases(format_cases)
  run_json_cases(read_cases)
  run_decimal_constants(constant_cases)
})
