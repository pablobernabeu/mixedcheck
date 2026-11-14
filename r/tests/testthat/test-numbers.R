# Targeted tests of number formatting, decimal constants and the number rules
# of the hashable profile, beyond the cases of the number corpus.
#
# ecmascript-numbers.txt.gz holds 6,367 positive doubles, as the 16
# hexadecimal digits of their bits, with the string that Node.js 22.22.0's
# String() gives for each, which is ECMAScript's Number::toString. They are
# every finite power of two, the subnormal doubles with significands 1 to 300,
# every power of ten from 1e-323 to 1e308 with both neighbours, the largest
# doubles, the neighbourhood of the smallest normal double, integers near 2^53,
# the neighbours of 1e21, 1e-6 and 1e-7, 1,500 random bit patterns and 500
# random values in [0, 1), from a fixed seed. A Node.js script that is part of
# neither package wrote them.

format_number <- mixedcheck:::format_number
bits_double <- mixedcheck:::bits_double

ecmascript_vectors <- function() {
  lines <- readLines(gzfile(test_path("ecmascript-numbers.txt.gz")))
  parts <- strsplit(lines, "\t", fixed = TRUE)
  list(
    x = vapply(parts, function(p) bits_double(p[1L]), 0),
    text = vapply(parts, function(p) p[2L], "")
  )
}

test_that("doubles are written as Node.js writes them and convert back", {
  vectors <- ecmascript_vectors()
  expect_length(vectors$x, 6367L)
  values <- c(vectors$x, -vectors$x)
  written <- format_number(values)
  expected <- c(vectors$text, paste0("-", vectors$text))
  wrong <- which(written != expected)
  expect_identical(wrong, integer(0), label = paste(head(written[wrong]), collapse = " "))
  back <- jsonlite::parse_json(paste0("[", paste(written, collapse = ","), "]"),
                               simplifyVector = TRUE)
  expect_identical(as.double(back), values)
})

test_that("values that defeat simpler methods are written in shortest form", {
  # Formatting with increasing precision returns 7.1202363472230444e-307 for
  # 2^-1017, although 16 digits convert back (conventions.md, Numbers).
  expect_identical(format_number(2^-1017), "7.120236347223045e-307")
  expect_identical(format_number(5e-324), "5e-324")
  expect_identical(format_number(.Machine$double.xmax), "1.7976931348623157e+308")
  expect_identical(format_number(2^53), "9007199254740992")
  expect_identical(format_number(2^68), "295147905179352830000")
  expect_identical(format_number(1e21), "1e+21")
  expect_identical(format_number(1e23), "1e+23")
  expect_identical(format_number(0.1 + 0.2), "0.30000000000000004")
  expect_identical(format_number(1 / 3), "0.3333333333333333")
  expect_identical(format_number(2 / 3), "0.6666666666666666")
  expect_identical(format_number(1e-6), "0.000001")
  expect_identical(format_number(1e-7), "1e-7")
  expect_identical(format_number(123e-20), "1.23e-18")
  expect_identical(format_number(100), "100")
  expect_identical(format_number(c(-0, 0)), c("0", "0"))
})

test_that("number formatting does not depend on OutDec or the locale's digits", {
  old <- options(OutDec = ",", scipen = 100, digits = 3)
  on.exit(options(old), add = TRUE)
  expect_identical(format_number(c(0.5, 1234.5, 1e21, -1e-6, 1.5e-7)),
                   c("0.5", "1234.5", "1e+21", "-0.000001", "1.5e-7"))
})

test_that("decimal constants round the exact binary value half to even", {
  decimal_string <- mixedcheck:::decimal_string
  # Expected strings from Python's decimal module, quantising the exact value
  # of each double with ROUND_HALF_EVEN.
  expect_identical(decimal_string(9.995, 3), "9.99")
  expect_identical(decimal_string(0.5, 1), "0.5")
  expect_identical(decimal_string(1e300, 1), paste0("1", strrep("0", 300)))
  expect_identical(decimal_string(1e-300, 2), paste0("0.", strrep("0", 299), "1"))
  expect_identical(decimal_string(5e-324, 1), paste0("0.", strrep("0", 323), "5"))
  expect_identical(decimal_string(.Machine$double.xmax, 15),
                   paste0("179769313486232", strrep("0", 294)))
  expect_identical(decimal_string(123456789, 15), "123456789")
  expect_identical(decimal_string(0.1, 15), "0.1")
  expect_identical(decimal_string(2.5e-5, 1), "0.00003")
  expect_identical(decimal_string(99.5, 2), "100")
  expect_identical(decimal_string(-1.5, 1), "-2")
  expect_identical(decimal_string(2^53, 3), "9010000000000000")
  expect_identical(decimal_string(1234.5, 4), "1234")
  expect_identical(decimal_string(0, 3), "0")
  expect_error(decimal_string(NaN, 3), "one finite number")
  expect_error(decimal_string(1, 16), "integer from 1 to 15")
  expect_error(decimal_string(1, 2.5), "integer from 1 to 15")
})

test_that("the hashable profile classifies tokens by their exact decimal value", {
  codes <- mixedcheck:::hashable_token_codes(c(
    "0", "-0.000e99999999999", "9007199254740991", "9007199254740992", "90071992547409910e-1",
    "1e15", "1e16", "0.000000000000001e30", "123456789012345.0", "1.234567890123456",
    "1e-307", "0.99e-307", "1e00000000000000000000001", "1e-99999999999", "1.0000000000000001e-99999999999"
  ))
  expect_identical(codes, c(
    NA, NA, NA, "E1102", NA,
    NA, "E1102", NA, NA, "E1103",
    NA, "E1104", NA, "E1104", "E1103"
  ))
})

test_that("integers are written exactly without C formatting of doubles", {
  integer_digits <- mixedcheck:::integer_digits
  expect_identical(integer_digits(c(0, 1, 99999999, 1e8, 123456789012345, 2^53 - 1)),
                   c("0", "1", "99999999", "100000000", "123456789012345", "9007199254740991"))
  expect_identical(mixedcheck:::format_integer(-12L), "-12")
  expect_identical(mixedcheck:::format_integer(-9007199254740991), "-9007199254740991")
})
