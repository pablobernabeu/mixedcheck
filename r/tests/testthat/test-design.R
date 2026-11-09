# Targeted tests of the design and analysis samples, the design matrices, the
# response, offset and weight vectors, the sequential rule and the exact
# summation behind mean centring constants (docs/spec/ir.md).

issue_code <- function(expr) {
  tryCatch({
    expr
    NA_character_
  }, mixedcheck_error = function(e) e$issues[[1L]]$code)
}

# The double that a hexadecimal significand and a power of two give exactly.
from_hex <- function(significand, power) significand * 2^power

test_that("the exact sum rounds once, as math.fsum() does", {
  exact_sum <- mixedcheck:::exact_sum
  expect_identical(exact_sum(c(1e100, 1, -1e100)), 1)
  expect_identical(exact_sum(rep(0.1, 10L)), 1)
  expect_identical(exact_sum(c(0.1, 0.2, 0.3)), from_hex(0x13333333333333, -53))
  expect_identical(exact_sum(c(1, 2^-53)), 1)
  expect_identical(exact_sum(c(1, 2^-53, 2^-105)), 1 + 2^-52)
  expect_identical(exact_sum(c(1 + 2^-52, 2^-53)), 1 + 2^-51)
  expect_identical(exact_sum(c(5e-324, 5e-324)), 1e-323)
  expect_identical(exact_sum(c(-0.5, -0.25)), -0.75)
  expect_identical(exact_sum(c(3, -3)), 0)
  expect_identical(exact_sum(numeric(0)), 0)
  # 1,200,000 values span three chunks of the summation (math.fsum() gives
  # 0x1.d4cp+16).
  expect_identical(exact_sum(rep(0.1, 1200000L)), from_hex(0x1d4c, 4))
  # The largest double is taken from .Machine, since R parses a decimal
  # literal in long double, which on some platforms is a double, so that
  # 1.7976931348623157e308 can parse as Inf.
  expect_identical(exact_sum(rep(.Machine$double.xmax / 2^11, 1500L)),
                   from_hex(0x176fffffffffff, 1023 - 52))
})

test_that("the sequential rule drops zero columns and later members of dependencies", {
  rule <- mixedcheck:::sequential_rule
  x <- cbind(1, c(1, 2, 3, 4), 0, c(2, 4, 6, 8), c(1, 0, 0, 1))
  expect_identical(rule(x), c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(rule(x[, c(4, 2)]), c(TRUE, FALSE))
  # Relative residuals on either side of 1e-7.
  base <- c(1, 2, 3, 4)
  near <- base + c(1, -1, -1, 1) * 1e-6
  far <- base + c(1, -1, -1, 1) * 1e-8
  expect_identical(rule(cbind(1, base, near)), c(TRUE, TRUE, TRUE))
  expect_identical(rule(cbind(1, base, far)), c(TRUE, TRUE, FALSE))
  expect_identical(rule(matrix(0, 3, 0)), logical(0))
})

test_that("the response, trials, offset and weight vectors follow the samples", {
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ))
  data <- data.frame(k = c(1, 2, NA, 0, 3), n = c(4, 0, 2, 3, 5), x = c(1, 2, 3, NA, 5),
                     e = c(1, 2, 4, 8, 16), z = c(0.5, 0.25, 0, 1, 2), w = c(1, 2, 3, 4, 0.5))
  ir <- formula_ir("k ~ x + offset(log(e)) + offset(z)", declaration, data, weights = "w")
  m <- design_matrices(ir, data)
  expect_identical(m$design_sample, c(1L, 2L, 3L, 5L))
  expect_identical(m$analysis_sample, c(1L, 5L))
  expect_identical(m$response, c(1, 3))
  expect_identical(m$trials, c(4, 5))
  expect_identical(m$offset, log(c(1, 2, 4, 16)) + c(0.5, 0.25, 0, 2))
  expect_identical(m$weights, c(1, 2, 3, 0.5))
})

test_that("a declared event level, a log response and a boolean response give their vectors", {
  data <- data.frame(acc = c("correct", "error", "correct"), rt = c(350, 420, 515.5),
                     ok = c(TRUE, FALSE, TRUE), x = c(1, 2, 3), stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", variables = list(
    acc = list(role = "outcome", measurement = "binary", event_level = "correct")
  ))
  m <- design_matrices(formula_ir("acc ~ x", declaration, data), data)
  expect_identical(m$response, c(1, 0, 1))
  m <- design_matrices(formula_ir("acc ~ x", data = data), data)
  expect_null(m$response)
  m <- design_matrices(formula_ir("log(rt) ~ x", data = data), data)
  expect_identical(m$response, log(c(350, 420, 515.5)))
  m <- design_matrices(formula_ir("ok ~ x", data = data), data)
  expect_identical(m$response, c(1, 0, 1))
  expect_null(m$offset)
  expect_null(m$weights)
  expect_null(design_matrices(formula_ir("~ x", data = data), data)$response)
})

test_that("the matrices report their problems in the order of ir.md", {
  data <- data.frame(y = c(1, 2, 3), x = c(1, 2, 3), e = c(1, 0, 2), w = c(1, -1, 1))
  ir <- formula_ir("y ~ x + offset(log(e))", data = data, weights = "w")
  expect_identical(issue_code(design_matrices(ir, data)), "E6071")
  ir <- formula_ir("y ~ x", data = data, weights = "w")
  expect_identical(issue_code(design_matrices(ir, data)), "E6072")
  data$x[2L] <- Inf
  expect_identical(issue_code(design_matrices(ir, data)), "E6073")
  data <- data.frame(y = c(1, NaN, 3), x = c(1, 2, 3))
  expect_identical(issue_code(design_matrices(formula_ir("y ~ x", data = data), data)), "E6073")
  data <- data.frame(y = c(1, 0, 3), x = c(1, 2, 3))
  expect_identical(issue_code(design_matrices(formula_ir("log(y) ~ x", data = data), data)), "E6071")
  data$y[2L] <- NA
  expect_identical(design_matrices(formula_ir("log(y) ~ x", data = data), data)$response,
                   log(c(1, 3)))
})

test_that("E6071 for an offset and E6072 apply to rows whose response is missing", {
  data <- data.frame(y = c(1, NA, 3), x = c(1, 2, 3), e = c(1, 0, 2), w = c(1, 0, 1))
  ir <- formula_ir("y ~ x + offset(log(e))", data = data)
  expect_identical(design_samples(ir, data)$analysis_sample, c(1L, 3L))
  expect_identical(issue_code(design_matrices(ir, data)), "E6071")
  ir <- formula_ir("y ~ x", data = data, weights = "w")
  expect_identical(issue_code(design_matrices(ir, data)), "E6072")
})

test_that("Z stores one entry for each row and column of a term, zero or not", {
  data <- data.frame(y = 1:6, x = c(0, 1, 2, 0, 1, 2), g = c(2, 10, 1.5, 2, 10, 1.5),
                     h = c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE))
  ir <- formula_ir("y ~ x + (1 + x | g) + (1 | g:h)", data = data)
  m <- design_matrices(ir, data)
  expect_s4_class(m$z, "dgCMatrix")
  expect_identical(length(m$z@x), 6L * 3L)
  expect_identical(m$z_columns$level[c(1, 3, 5)], c("1.5", "2", "10"))
  expect_identical(m$z_columns$level[7:12],
                   c("1.5:false", "1.5:true", "2:false", "2:true", "10:false", "10:true"))
  expect_identical(m$z_columns$term, c(rep(1L, 6L), rep(2L, 6L)))
  expect_identical(as.matrix(m$z)[1L, ], c(0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0))
})

test_that("a random slope of 0 keeps its stored entry in Z", {
  # The slope of level 'a' is 0 in both of its rows and that of level 'b' in
  # its first row. Z is built from its slots, so that this holds whatever
  # Matrix version is installed.
  data <- data.frame(y = c(1, 2, 3, 4), x = c(0, 0, 0, 3), g = c("a", "a", "b", "b"))
  z <- design_matrices(formula_ir("y ~ x + (1 + x | g)", data = data), data)$z
  expect_s4_class(z, "dgCMatrix")
  expect_no_error(methods::validObject(z))
  expect_identical(length(z@x), nrow(z) * 2L)
  expect_identical(z@p, c(0L, 2L, 4L, 6L, 8L))
  expect_identical(z@i, c(0L, 1L, 0L, 1L, 2L, 3L, 2L, 3L))
  expect_identical(z@x, c(1, 1, 0, 0, 1, 1, 0, 3))
  expect_identical(z@Dimnames, list(NULL, NULL))
})

test_that("a level outside the IR's levels and a missing column are refused", {
  data <- data.frame(y = c(1, 2, 3), a = c("A", "B", "A"))
  ir <- formula_ir("y ~ a", data = data)
  data$a[3L] <- "C"
  expect_error(design_matrices(ir, data), "not one of its levels")
  expect_error(design_matrices(ir, data.frame(y = c(1, 2))), "is not in 'data'")
})

test_that("the IR is checked before it is used", {
  data <- data.frame(y = c(1, 2, 3), x = c(1, 2, 3))
  ir <- formula_ir("y ~ x", data = data)
  ir$ir_version <- "0.2.0"
  expect_identical(issue_code(design_matrices(ir, data)), "E1441")
  ir$ir_version <- "0.1.0"
  ir$fixed$columns[[1L]]$term <- "0"
  expect_identical(issue_code(design_matrices(ir, data)), "E1401")
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"), list(name = "x", type = "number")
  )))
  prospective <- formula_ir("y ~ x", declaration, coding = list(x = list(centring = "mean")))
  expect_error(design_matrices(prospective, data), "has no constant")
  trials <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ))
  data <- data.frame(k = c(1, 2), n = c(3, 4), x = c(1, 2))
  ir <- formula_ir("k ~ x", trials, data)
  data$n <- c("3", "4")
  expect_error(design_matrices(ir, data), "does not hold numbers", class = "simpleError")
  expect_error(design_samples(ir, data), "does not hold numbers")
})

test_that("X multiplies centred values and contrasts from the left", {
  data <- data.frame(y = 1:6, x = c(0.1, 0.2, 0.3, 0.4, 0.5, 0.7),
                     a = c("A1", "A2", "A3", "A1", "A2", "A3"))
  ir <- formula_ir("y ~ x:a", data = data,
                   coding = list(x = list(centring = "value", value = "0.3"),
                                 a = list(contrast = "simple")))
  m <- design_matrices(ir, data)
  centred <- data$x - 0.3
  expect_identical(colnames(m$x), c("(Intercept)", "x:a[A1]", "x:a[A2]", "x:a[A3]"))
  expect_identical(m$x[, 2L], centred * (data$a == "A1"))
  ir <- formula_ir("y ~ a:x", data = data, coding = list(a = list(contrast = "simple")))
  m <- design_matrices(ir, data)
  expect_identical(colnames(m$x)[2L], "a[A1]:x")
})

test_that("formula_ir() and design_matrices() are fast on 10,000 rows", {
  skip_on_cran()
  n <- 10000L
  data <- data.frame(
    rt = seq_len(n) / 7, x = sin(seq_len(n)), cond = rep(c("A", "B", "C"), length.out = n),
    subject = sprintf("s%03d", rep(seq_len(100L), length.out = n)),
    item = sprintf("i%03d", rep(seq_len(80L), each = n / 80L)),
    stringsAsFactors = FALSE
  )
  elapsed <- system.time({
    ir <- formula_ir("rt ~ cond * x + (1 + cond + x | subject) + (1 + x | item)", data = data,
                     coding = list(x = list(centring = "mean")))
    m <- design_matrices(ir, data)
  })[["elapsed"]]
  expect_identical(dim(m$z), c(n, 100L * 4L + 80L * 2L))
  expect_lt(elapsed, 10)
})

test_that("the sequential rule scales each column by its largest value", {
  rule <- mixedcheck:::sequential_rule
  expect_identical(rule(matrix(c(1e200, 1, 2), ncol = 1L)), TRUE)
  expect_identical(rule(cbind(1, c(1e-200, 1e-170, 2e-200))), c(TRUE, TRUE))
  # Relative to their size, these two columns differ by about 1e-308.
  expect_identical(rule(cbind(c(1e308, 1e308, 1), c(1e308, 1e308, 3))), c(TRUE, FALSE))
  expect_identical(rule(cbind(c(1e308, 1e308, 1), c(1e308, -1e308, 3))), c(TRUE, TRUE))
  expect_identical(rule(cbind(c(1e308, 5e307, 0), c(2e307, 1e307, 0))), c(TRUE, FALSE))
})

test_that("values of X and Z that are not finite are refused", {
  data <- data.frame(y = c(1, 2, 3), x = c(1e200, 1, 2), z = c(1e200, 3, 1), g = c("a", "b", "a"))
  ir <- formula_ir("y ~ x:z", data = data)
  issue <- tryCatch(design_matrices(ir, data), mixedcheck_error = function(e) e$issues[[1L]])
  expect_identical(issue$message, "A value computed for 'x:z' is not finite.")
  ir <- formula_ir("y ~ 1 + (0 + x:z | g)", data = data)
  expect_identical(issue_code(design_matrices(ir, data)), "E6077")
  data <- data.frame(y = c(1, 2, 3), x = c(1e308, -1e308, 3))
  coding <- list(x = list(centring = "value", value = paste0("1", strrep("0", 308L))))
  ir <- formula_ir("y ~ x", data = data, coding = coding)
  expect_identical(issue_code(design_matrices(ir, data)), "E6077")
})

test_that("trials that are not finite reach E6073 and negative trials leave", {
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ))
  for (bad in c(NaN, Inf, -Inf)) {
    data <- data.frame(k = c(1, 0, 2, 1, 1, 0), x = 1:6, n = c(3, 0, 4, NA, bad, -1))
    ir <- formula_ir("k ~ x", declaration, data)
    samples <- design_samples(ir, data)
    expect_identical(samples$design_sample, 1:6)
    expect_identical(samples$analysis_sample, c(1L, 3L, 5L))
    issue <- tryCatch(design_matrices(ir, data), mixedcheck_error = function(e) e$issues[[1L]])
    expect_identical(issue$message,
                     "The column 'n' holds NaN or an infinity in a row that the model uses.")
  }
})

test_that("the levels of a factor of several variables escape their labels", {
  data <- data.frame(y = c(1, 2, 3, 4), g = c("a:b", "a", "a:b", "a\\"),
                     h = c("c", "b:c", "c", "d"))
  m <- design_matrices(formula_ir("y ~ (1 | g:h) + (1 | g)", data = data), data)
  expect_identical(m$z_columns$level, c("a:b\\:c", "a\\:b:c", "a\\\\:d", "a", "a:b", "a\\"))
})

test_that("design_samples() reports the samples that the matrices refuse", {
  data <- data.frame(y = c(1, NA, 3), x = c(1, 2, Inf))
  ir <- formula_ir("y ~ x", data = data)
  expect_identical(issue_code(design_matrices(ir, data)), "E6073")
  samples <- design_samples(ir, data)
  expect_identical(samples, list(design_sample = 1:3, analysis_sample = c(1L, 3L)))
  expect_error(design_samples(ir, as.list(data)), "data frame")
})

test_that("columns far from 1 in size are kept or dropped by their direction alone", {
  # In exact arithmetic, x has a relative residual of about 0.4 against the
  # intercept at every scale.
  for (scale in c(1e160, 1e-170)) {
    data <- data.frame(y = c(1, 2, 3), x = c(1, 2, 3.5) * scale)
    m <- design_matrices(formula_ir("y ~ x", data = data), data)
    expect_identical(m$x_dropped, character(0))
  }
  data <- data.frame(y = c(1, 2, 3, 4), x = rep(-1e308, 4L))
  m <- design_matrices(formula_ir("y ~ x", data = data), data)
  expect_identical(m$x_dropped, "x")
})

test_that("the sequential rule gives the same columns after the reduction by QR", {
  # The same columns as in the Python package's test. Of the 13 columns, 12
  # are not all 0, so that the columns are reduced by QR on more than 24 rows
  # and used as they are on 24 rows or fewer.
  rule <- mixedcheck:::sequential_rule
  index <- seq_len(200L)
  a <- sin(index)
  b <- cos(3 * index)
  f <- c("A", "B", "C")[index %% 3L + 1L]
  sign <- c(1, -1)
  x <- cbind(1, a, 0, b, a + 2 * b, f == "A", f == "B", f == "C", (f == "C") * 1e-12,
             a * (f == "A"), 3 * a - 1, b + sign * 1e-6, b + sign * 1e-9)
  expected <- c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE,
                FALSE)
  expect_identical(rule(x), expected)
  expect_identical(rule(x[1:25, ]), expected)
  expect_identical(rule(x[1:24, ]), expected)
  expect_identical(rule(x[, c(1, 2, 5, 4)]), c(TRUE, TRUE, TRUE, FALSE))
  # Relative residuals of 2e-7 and 5e-8 against the columns 1 and a, on 200
  # rows, which are reduced.
  e <- rep(sign, 100L)
  e <- e - drop(cbind(1, a) %*% qr.solve(cbind(1, a), e))
  e <- e / sqrt(sum(e * e))
  w <- a / sqrt(sum(a * a))
  expect_identical(rule(cbind(1, a, w + 2e-7 * e)), c(TRUE, TRUE, TRUE))
  expect_identical(rule(cbind(1, a, w + 5e-8 * e)), c(TRUE, TRUE, FALSE))
})

test_that("a level of the IR outside its predictor's levels is refused", {
  data <- data.frame(y = c(1.5, 2.25, 3, 2.5), cond = c("A", "B", "A", "B"))
  ir <- formula_ir("y ~ cond", data = data)
  bad <- ir
  bad$fixed$columns[[2L]]$levels$cond <- "C"
  bad$fixed$columns[[2L]]$name <- "cond[C]"
  expect_error(design_matrices(bad, data), "The level 'C' is not one of the levels in the IR.",
               fixed = TRUE)
  bad$fixed$columns[[2L]]$levels$cond <- "C\t"
  expect_error(design_matrices(bad, data), "The level 'C\\u0009' is not one", fixed = TRUE)
  bad$fixed$columns[[2L]]$levels$cond <- TRUE
  expect_error(design_matrices(bad, data), "The level 'true' is not one", fixed = TRUE)
  bad <- formula_ir("y ~ cond", data = data, coding = list(cond = list(contrast = "sum")))
  bad$predictors$cond$reference <- "Z"
  expect_error(design_matrices(bad, data), "The level 'Z' is not one", fixed = TRUE)
  bad <- ir
  bad$fixed$columns[[2L]]$levels <- structure(list(), names = character(0))
  expect_error(design_matrices(bad, data), "The column 'cond[B]' of the IR gives no level",
               fixed = TRUE)
})

test_that("a factor of 300 levels on 30,000 rows gives its matrices in seconds", {
  # About 3 s, and 12 s on 100,000 rows, almost all of it in the QR of the
  # sequential rule, where projecting every column onto a basis of n rows
  # took 70 s. The reference BLAS of R shares the cores with every thread of
  # other jobs, so the test takes about 4 s with a CPU-bound process on every
  # core and 17 s with four other jobs, each running BLAS on four threads, on
  # four cores. The bound is seven times the latter, so that a loaded machine
  # does not fail the test.
  skip_on_cran()
  n <- 30000L
  index <- seq_len(n)
  data <- data.frame(y = sin(index), x = cos(index), f = sprintf("L%03d", index %% 300L))
  elapsed <- system.time({
    m <- design_matrices(formula_ir("y ~ x + f", data = data), data)
  })[["elapsed"]]
  expect_identical(dim(m$x), c(n, 301L))
  expect_identical(m$x_dropped, character(0))
  expect_lt(elapsed, 120)
})
