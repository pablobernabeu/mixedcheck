# The rendering of real statistics in messages (registry.md, Messages),
# compared with the vectors of the number corpus.
#
# numbers/message_reals.txt.xz holds doubles, as the 16 hexadecimal digits of
# their bits, each with its renderings with 0 to 6 digits, which
# fixtures/conformance/tools/make_message_reals.py writes with Python's format()
# and checks against exact rounding. They are random bit patterns, values from
# 1e-7 to 1e22, the neighbours of 1e15, every power of ten from 1e-323 to
# 1e308 with both neighbours, decimals that lie halfway between two roundings
# of the mantissa or to d decimal places and the doubles nearest to such
# decimals that a double does not hold, the doubles nearest to the decimals at
# which the rounding carries into a new digit or into the exponent, the
# largest doubles, the smallest subnormal doubles and the doubles near 2^53,
# most of them with both signs (fixtures/conformance/numbers/README.md).

message_real_vectors <- function() {
  path <- corpus_directory("numbers", "message_reals.txt.xz")
  if (!file.exists(path)) {
    stop("The corpus file numbers/message_reals.txt.xz is missing.")
  }
  connection <- xzfile(path)
  on.exit(close(connection))
  parts <- strsplit(readLines(connection), "\t", fixed = TRUE)
  list(
    x = vapply(parts, function(p) mixedcheck:::bits_double(p[1L]), 0),
    text = t(vapply(parts, function(p) p[-1L], character(7L)))
  )
}

test_that("reals are rendered as the vectors of the number corpus give them", {
  vectors <- message_real_vectors()
  expect_gt(length(vectors$x), 20000L)
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

test_that("a positive real whose rounding has only zeros renders as under the smallest value", {
  # The double nearest to 0.05 lies above it, and the double before it below.
  below <- 0.05 - 2^-57
  expect_identical(below, 0.049999999999999996)
  expect_identical(real_text(0.05, 1L), "0.1")
  expect_identical(real_text(below, 1L), "under 0.1")
  expect_identical(real_text(below, 0:2), c("under 1", "under 0.1", "0.05"))
  expect_identical(real_text(1 / 21, 1L), "under 0.1")
  # 0.5 is a tie, which rounds half to even to 0, and the double after it
  # rounds up.
  expect_identical(real_text(0.5, 0L), "under 1")
  expect_identical(real_text(0.5 + 2^-53, 0L), "1")
  expect_identical(real_text(1.5, 0L), "2")
  expect_identical(real_text(0.0625, 3L), "0.062")
  # Subnormal doubles, the smallest of them included.
  expect_identical(real_text(2^-1074, 0:6), c("under 1", paste0("under 0.", strrep("0", 0:5), "1")))
  expect_identical(real_text(2^-1022 - 2^-1074, 6L), "under 0.000001")
  # Zero and negative values keep their fixed rendering.
  expect_identical(real_text(0, 1L), "0.0")
  expect_identical(real_text(-2^-1074, 0:1), c("0", "0.0"))
  expect_identical(real_text(-below, 1L), "0.0")
  expect_identical(real_text(-0.5, 0L), "0")
  entry <- registry_entry("outcome.minority_events")
  expect_identical(
    render_message(entry, "events_model", list(),
                   list(events = 1, non_events = 20, events_per_column = 1 / 21)),
    "The outcome has 1 event and 20 non-events, or under 0.1 minority events per fixed-effects column."
  )
})
