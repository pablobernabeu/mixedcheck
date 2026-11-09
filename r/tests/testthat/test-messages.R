# The rendering of real statistics in messages (registry.md, Messages),
# compared with Python's f-strings.
#
# message-reals.txt.xz holds 20,966 doubles, as the 16 hexadecimal digits of
# their bits, each with the strings that Python 3.13 writes for it with 0 to 6
# digits: f"{x:z.{d}f}" below 1e15 in absolute value and f"{x:.{d}e}" from 1e15
# on. They are random bit patterns, log-uniform values from 1e-7 to 1e22, the
# 400 neighbours of 1e15 on each side, every power of ten from 1e-323 to 1e308
# with both neighbours, 2,500 decimals at or above 1e15 that a double holds
# exactly and that lie halfway between two roundings of the mantissa, odd
# multiples of 2^-(d + 1) below 1e15, which lie halfway between two roundings
# to d decimal places, the doubles nearest to the decimals at which the
# rounding of the mantissa carries into the exponent with their neighbours,
# the 20 largest doubles, the smallest subnormal doubles and integers near
# 2^53, most of them with both signs, from a fixed seed. A Python script that
# is part of neither package wrote them.

message_real_vectors <- function() {
  connection <- xzfile(test_path("message-reals.txt.xz"))
  on.exit(close(connection))
  parts <- strsplit(readLines(connection), "\t", fixed = TRUE)
  list(
    x = vapply(parts, function(p) mixedcheck:::bits_double(p[1L]), 0),
    text = t(vapply(parts, function(p) p[-1L], character(7L)))
  )
}

test_that("reals are rendered as Python's f-strings write them", {
  vectors <- message_real_vectors()
  expect_identical(length(vectors$x), 20966L)
  rendered <- t(vapply(vectors$x, real_text, character(7L), digits = 0:6))
  wrong <- which(rendered != vectors$text, arr.ind = TRUE)
  expect_identical(nrow(wrong), 0L, label = paste(head(rendered[wrong]), collapse = " "))
  # One number of places at a time gives the same strings.
  rows <- seq(1L, length(vectors$x), by = 97L)
  for (d in 0:6) {
    expect_identical(vapply(vectors$x[rows], real_text, "", digits = d), vectors$text[rows, d + 1L])
  }
})

test_that("the notation changes at 1e15, by the double before rounding", {
  # The double before 1e15.
  below <- 999999999999999.875
  expect_identical(real_text(below, 0L), "1000000000000000")
  expect_identical(real_text(below, 2L), "999999999999999.88")
  expect_identical(real_text(1e15, 0L), "1e+15")
  expect_identical(real_text(1e15, 2L), "1.00e+15")
  expect_identical(real_text(-1e15, 1L), "-1.0e+15")
  expect_identical(real_text(2.5e20, 0L), "2e+20")
  expect_identical(real_text(3.5e20, 0L), "4e+20")
  expect_identical(real_text(9.5e15, 0L), "1e+16")
  expect_identical(real_text(2^60, 2L), "1.15e+18")
  expect_identical(real_text(1e100, 3L), "1.000e+100")
  expect_identical(real_text(.Machine$double.xmax, 6L), "1.797693e+308")
  expect_identical(real_text(-0.04, 1L), "0.0")
  expect_identical(real_text(Inf, 2L), "Infinity")
  expect_identical(real_text(-Inf, 0L), "-Infinity")
  expect_identical(real_text(NaN, 1L), "NaN")
})

test_that("the message of design.scale_disparity renders a large ratio in scientific notation", {
  entry <- registry_entry("design.scale_disparity")
  values <- list(scaled_columns = c("x1", "x2"), sd_largest = 1e299, sd_smallest = 1,
                 sd_ratio = 1e299, condition_number = 1)
  expect_match(render_message(entry, "disparate", list(), values),
               "differ by a factor of 1e+299, or one", fixed = TRUE)
})
