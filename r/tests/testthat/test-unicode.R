# Targeted tests of UTF-8 validation, NFC and the order of identifiers,
# beyond the cases of the Unicode corpus.

test_that("the first ill-formed sequence is found by decoding from the start", {
  offset <- function(...) mixedcheck:::utf8_invalid_offset(as.raw(c(...)))
  expect_identical(offset(0x61, 0x62), NA_integer_)
  expect_identical(offset(), NA_integer_)
  expect_identical(offset(0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80), NA_integer_)
  expect_identical(offset(0x80), 0L)
  expect_identical(offset(0x61, 0xC3), 1L)
  expect_identical(offset(0xE2, 0x82, 0x41), 0L)
  expect_identical(offset(0xF0, 0x9F, 0x98, 0x80, 0x80), 4L)
  expect_identical(offset(0xED, 0x9F, 0xBF, 0xED, 0xA0, 0x80), 3L)
  expect_identical(offset(0xF4, 0x8F, 0xBF, 0xBF, 0xF4, 0x90, 0x80, 0x80), 4L)
})

test_that("the validator agrees with R's validUTF8() on random bytes", {
  set.seed(20261108)
  candidates <- c(0x00:0x7F, 0x80:0xBF, 0xC0:0xC3, 0xDF:0xE1, 0xEC:0xEE, 0xEF:0xF1, 0xF3:0xF5,
                  0xFE, 0xFF)
  samples <- lapply(seq_len(2000L), function(i) {
    as.raw(sample(candidates[candidates > 0], sample(1:6, 1L), replace = TRUE))
  })
  ours <- vapply(samples, function(bytes) is.na(mixedcheck:::utf8_invalid_offset(bytes)), NA)
  theirs <- vapply(samples, function(bytes) validUTF8(rawToChar(bytes)), NA)
  differ <- which(ours != theirs)
  expect_identical(differ, integer(0),
                   label = paste(vapply(samples[differ], paste, "", collapse = " "), collapse = ", "))
})

test_that("strings marked UTF-8 are checked together", {
  valid <- mixedcheck:::utf8_valid_strings
  bad <- rawToChar(as.raw(c(0x61, 0xC3)))
  Encoding(bad) <- "UTF-8"
  good <- intToUtf8(c(0xE9, 0x1F600))
  expect_identical(valid(c(good, bad, good, bad)), c(TRUE, FALSE, TRUE, FALSE))
})

test_that("identifiers are compared and sorted by the code points of their NFC forms", {
  nfd <- intToUtf8(c(0x65, 0x301))
  nfc <- intToUtf8(0xE9)
  expect_identical(mixedcheck:::compare_identifiers(nfd, nfc), 0L)
  expect_identical(mixedcheck:::comparison_form(c(nfd, "a")), c(nfc, "a"))
  sorted <- mixedcheck:::sort_identifiers(c(nfc, "Z", "a", "_", intToUtf8(0x1F600)))
  expect_identical(lapply(sorted, utf8ToInt), list(90L, 95L, 97L, 0xE9L, 0x1F600L))
  # U+1E4EC is assigned only from Unicode 15.0, so the string is compared as
  # it is.
  later <- intToUtf8(c(0x78, 0x1E4EC, 0x316))
  expect_false(mixedcheck:::is_normalisable(later))
  expect_identical(mixedcheck:::comparison_form(later), later)
})
