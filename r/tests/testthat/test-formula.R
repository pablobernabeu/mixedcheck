# Targeted tests of the formula parser and the builder of the IR, for edge
# cases that the formula corpus does not cover (docs/spec/ir.md).

issue_of <- function(expr) {
  tryCatch({
    expr
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

numbers <- data.frame(y = c(1, 2, 3, 4), x = c(0.5, 1, 1.5, 2), z = c(2, 1, 4, 3),
                      e = c(1, 2, 3, 4), a = c("A1", "A2", "A1", "A2"),
                      g = c("g1", "g1", "g2", "g2"), stringsAsFactors = FALSE)

test_that("a subtracted random term is refused", {
  issue <- issue_of(formula_ir("y ~ x - (1 | g)", data = numbers))
  expect_identical(issue$code, "E6014")
  expect_identical(issue$offset, 8L)
})

test_that("an exponent that is not a number is named by its first token", {
  issue <- issue_of(formula_ir("y ~ (x + z)^(2)", data = numbers))
  expect_identical(issue$code, "E6006")
  expect_identical(issue$offset, 12L)
  expect_identical(issue$message, paste0("'(' at byte 12 is not a valid number there. Only 0 and 1 ",
                                         "can stand as terms, and an exponent is an integer from 2 ",
                                         "to 1000."))
  expect_identical(issue_of(formula_ir("y ~ (x + z)^1001", data = numbers))$code, "E6006")
  ir <- formula_ir("y ~ (x + z)^1000", data = numbers)
  expect_identical(vapply(ir$fixed$terms, function(term) term$name, ""),
                   c("(Intercept)", "x", "z", "x:z"))
})

test_that("the end of the input is the number of bytes, after trailing white space", {
  issue <- issue_of(formula_ir("y ~ x + \t", data = numbers))
  expect_identical(issue$code, "E6010")
  expect_identical(issue$offset, 9L)
  cafe <- paste0("y ~ `caf", intToUtf8(0xE9), "` +")
  issue <- issue_of(formula_ir(cafe, data = numbers))
  expect_identical(issue$offset, 13L)
})

test_that("operators between percent signs and lone percent signs are told apart", {
  expect_identical(issue_of(formula_ir("y ~ x %% z", data = numbers))$message,
                   paste0("The operator '%%' at byte 6 is not supported. Name the columns and use ",
                          "'+', '-', '*', '/', ':' or '^'."))
  issue <- issue_of(formula_ir("y ~ x % in % z", data = numbers))
  expect_identical(issue$code, "E6002")
  expect_identical(issue$offset, 6L)
})

test_that("parentheses nest to 64 levels", {
  deep <- function(levels) paste0("y ~ ", strrep("(", levels), "x", strrep(")", levels))
  expect_silent(formula_ir(deep(64L), data = numbers))
  issue <- issue_of(formula_ir(deep(65L), data = numbers))
  expect_identical(issue$code, "E6021")
  expect_identical(issue$offset, 68L)
})

test_that("log() and offset() are allowed only where the grammar places them", {
  expect_identical(issue_of(formula_ir("log(y) ~ log(x)", data = numbers))$offset, 9L)
  expect_identical(issue_of(formula_ir("y ~ offset(log(e + z))", data = numbers))$code, "E6019")
  expect_identical(issue_of(formula_ir("y ~ x + offset(y)", data = numbers))$code, "E6032")
  expect_identical(issue_of(formula_ir("y ~ -offset(e) + x", data = numbers))$code, "E6019")
  ir <- formula_ir("y ~ +offset(e) + x", data = numbers)
  expect_identical(ir$offsets, list(list(variable = "e", transform = "identity")))
})

test_that("an absent term is named with its variables in their order in the part", {
  issue <- issue_of(formula_ir("y ~ z + x - x:z", data = numbers))
  expect_identical(issue$message, "The term 'z:x' removed at byte 10 is not in the formula at that point.")
})

test_that("each part evaluates its operands before the sign that applies to them", {
  issue <- issue_of(formula_ir("y ~ x + (z - z) - a", data = numbers))
  expect_identical(issue$code, "E6037")
  expect_identical(issue$offset, 8L)
  issue <- issue_of(formula_ir("y ~ -x + (z - z)", data = numbers))
  expect_identical(issue$code, "E6031")
  expect_identical(issue$offset, 4L)
})

test_that("integer categories take integer references and refuse strings", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"),
    list(name = "wave", type = "integer", categories = list(1, 2, 10))
  )))
  ir <- formula_ir("y ~ wave", declaration, coding = list(wave = list(reference = 10)))
  expect_identical(ir$predictors$wave$reference, 10)
  expect_identical(vapply(ir$fixed$columns, function(column) column$name, ""),
                   c("(Intercept)", "wave[1]", "wave[2]"))
  issue <- issue_of(formula_ir("y ~ wave", declaration, coding = list(wave = list(reference = "2"))))
  expect_identical(issue$message, "The reference level '2' of the column 'wave' is not one of its levels.")
  issue <- issue_of(formula_ir("y ~ wave", declaration, coding = list(wave = list(reference = 1.5))))
  expect_identical(issue$code, "E6063")
})

test_that("a mean centring constant needs finite values in the design sample", {
  data <- numbers
  data$x[2L] <- NaN
  issue <- issue_of(formula_ir("y ~ x", data = data, coding = list(x = list(centring = "mean"))))
  expect_identical(issue$message,
                   "The column 'x' holds NaN or an infinity in a row that the model uses.")
  ir <- formula_ir("y ~ x + z", data = data, coding = list(z = list(centring = "mean")))
  expect_identical(ir$predictors$z$centring$constant$value, "2.5")
  issue <- issue_of(design_matrices(ir, data))
  expect_identical(issue$code, "E6073")
})

test_that("only NA is missing in a data frame, and NaN is a value", {
  data <- numbers
  data$x[1L] <- NaN
  data$a[2L] <- ""
  data$g[3L] <- NA
  ir <- formula_ir("y ~ a + (1 | g)", data = data)
  expect_identical(unlist(ir$predictors$a$levels), c("", "A1", "A2"))
  samples <- design_samples(formula_ir("y ~ x + a", data = data), data)
  expect_identical(samples$design_sample, 1:4)
  samples <- design_samples(ir, data)
  expect_identical(samples$design_sample, c(1L, 2L, 4L))
})

test_that("factors give their labels, in code-point order whatever their levels", {
  data <- numbers
  data$a <- factor(data$a, levels = c("A2", "A1", "unused"))
  ir <- formula_ir("y ~ a", data = data)
  expect_identical(ir$predictors$a$levels, list("A1", "A2"))
  expect_identical(ir$predictors$a$levels_source, "table")
  data$i <- 1:4
  expect_identical(formula_ir("y ~ i", data = data)$predictors$i$kind, "numeric")
})

test_that("data must agree with the declared types and have distinct names", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"),
    list(name = "x", type = "string")
  )))
  data <- data.frame(y = c(1, 2), x = c(3, 4))
  expect_error(formula_ir("y ~ x", declaration, data), "declares the type 'string'")
  data$x <- c(NA, NA)
  expect_error(formula_ir("y ~ x", declaration, data), class = "mixedcheck_error")
  nfd <- paste0("cafe", intToUtf8(0x301))
  nfc <- paste0("caf", intToUtf8(0xE9))
  data <- list2DF(list(c(1, 2), c(1, 2)))
  names(data) <- c(nfd, nfc)
  expect_error(formula_ir("~ 1", data = data), "after NFC normalisation")
  expect_error(formula_ir("y ~ x", data = data.frame(y = 1, x = as.Date("2026-01-01"))),
               "not a vector of numbers")
  expect_error(formula_ir(y ~ x), "'formula' must be a character string")
  expect_error(formula_ir("y ~ x", data = numbers, coding = list(x = "mean")), "'coding' must be")
})

test_that("a declaration without data supplies the columns and their kinds", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"),
    list(name = "flag", type = "boolean"),
    list(name = "x", type = "number")
  )))
  ir <- formula_ir("y ~ flag + x", declaration, coding = list(x = list(centring = "mean")))
  expect_identical(ir$predictors$flag$levels, list(FALSE, TRUE))
  expect_identical(ir$predictors$x$centring,
                   list(rule = "mean", sample = "design", significant_digits = 6))
  expect_identical(issue_of(formula_ir("y ~ x"))$code, "E6051")
})

test_that("the trials column, the weights and the sample columns are checked in order", {
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ))
  data <- data.frame(k = c(1, 2), n = c("a", "b"), x = c(1, 2), w = c("u", "v"))
  issue <- issue_of(formula_ir("k ~ x", declaration, data, weights = "w", sample_columns = "s"))
  expect_identical(issue$code, "E6065")
  data$n <- c(3, 4)
  issue <- issue_of(formula_ir("k ~ x", declaration, data, weights = "w", sample_columns = "s"))
  expect_identical(issue$code, "E6066")
  data$w <- c(1, 2)
  issue <- issue_of(formula_ir("k ~ x", declaration, data, weights = "w",
                               sample_columns = c("x", "s", "t")))
  expect_identical(issue$message,
                   "The sample column 's' is not in the data, or in the declared table when there are no data.")
})

test_that("sample columns that the IR reads are left out, and the rest sorted", {
  data <- numbers
  data$b <- c("p", "q", "p", "q")
  ir <- formula_ir("y ~ x", data = data, weights = "e", sample_columns = c("z", "b", "e", "y", "x"))
  expect_identical(ir$sample_columns, list("b", "z"))
  expect_identical(ir$weights, list(variable = "e"))
})

test_that("an IR in a C locale holds strings marked UTF-8", {
  word <- paste0("caf", intToUtf8(0xE9))
  data <- data.frame(y = c(1, 2, 3), w = c(word, "ami", word), stringsAsFactors = FALSE)
  ir <- formula_ir("y ~ w", data = data)
  expect_identical(Encoding(ir$predictors$w$levels[[2L]]), "UTF-8")
  expect_identical(Encoding(ir$fixed$columns[[2L]]$name), "UTF-8")
  expect_true(startsWith(canonical_hash(ir, "hashable"), "sha256:"))
})

test_that("unmarked strings outside ASCII are refused outside a UTF-8 session", {
  local_mocked_bindings(native_utf8 = function() FALSE)
  formula <- rawToChar(as.raw(c(0x79, 0x20, 0x7E, 0x20, 0x60, 0xC3, 0xA9, 0x60)))
  issue <- issue_of(formula_ir(formula))
  expect_identical(issue$code, "E1204")
  expect_identical(issue$pointer, "/formula")
})

test_that("frozen factors split only under '||' and keep their contrast", {
  data <- data.frame(y = 1:6, a = rep(c("A1", "A2", "A3"), 2), g = rep(c("g1", "g2"), 3),
                     b = rep(c("B1", "B2"), each = 3))
  coding <- list(a = list(frozen = TRUE, contrast = "sum"), b = list(frozen = TRUE))
  ir <- formula_ir("y ~ a * b + (0 + a:b || g)", data = data, coding = coding)
  expect_identical(vapply(ir$random, function(term) term$name, ""),
                   c("0 + a[A2]:b[B2] | g", "0 + a[A3]:b[B2] | g"))
  expect_identical(ir$random[[1L]]$terms[[1L]]$variables, list(
    list(variable = "a", coding = "contrast", level = "A2"),
    list(variable = "b", coding = "contrast", level = "B2")
  ))
  ir <- formula_ir("y ~ (0 + a | g)", data = data, coding = coding["a"])
  expect_identical(vapply(ir$random[[1L]]$columns, function(column) column$name, ""),
                   c("a[A2]", "a[A3]"))
})

test_that("the IR passes the schema and its hash does not depend on the locale", {
  ir <- formula_ir("y ~ x * a + offset(log(e)) + (1 + x | g)", data = numbers,
                   coding = list(x = list(centring = "value", value = "1.25")))
  expect_identical(mixedcheck:::schema_issues(
    mixedcheck:::parse_json_bytes(canonical_bytes(ir, "hashable"), "hashable"),
    "urn:mixedcheck:schema:ir"), list())
  expect_identical(ir$predictors$x$centring$constant,
                   list(significant_digits = 3, value = "1.25"))
})

test_that("the response as a sample column changes no centring constant", {
  data <- data.frame(y = c(NA, 2, 3), x = c(10, 0.2, 0.3))
  coding <- list(x = list(centring = "mean"))
  ir <- formula_ir("y ~ x", data = data, coding = coding, sample_columns = "y")
  expect_null(ir$sample_columns)
  expect_identical(ir$predictors$x$centring$constant$value, "3.5")
  expect_identical(ir, formula_ir("y ~ x", data = data, coding = coding))
})

numeric_declaration <- function(names) {
  list(vocabulary = "0.1.0", table = list(fields = lapply(c("y", names), function(name) {
    list(name = name, type = "number")
  })))
}

test_that("a list of terms holds at most 10,000 terms", {
  names <- paste0("x", 1:14)
  ir <- formula_ir(paste("y ~", paste(names[1:13], collapse = "*")), numeric_declaration(names[1:13]))
  expect_length(ir$fixed$terms, 8192L)
  formula <- paste("y ~", paste(names, collapse = "*"))
  issue <- issue_of(formula_ir(formula))
  expect_identical(issue$code, "E6038")
  expect_identical(issue$offset, max(gregexpr("*", formula, fixed = TRUE)[[1L]]) - 1L)
  power <- paste0("y ~ (", paste(paste0("x", 1:16), collapse = " + "), ")^4")
  issue <- issue_of(formula_ir(power))
  expect_identical(c(issue$code, issue$offset), c("E6038", regexpr("^", power, fixed = TRUE) - 1L))
  first <- paste0("(", paste(paste0("a", 0:12), collapse = "*"), ")")
  second <- paste0("(", paste(paste0("b", 0:12), collapse = "*"), ")")
  issue <- issue_of(formula_ir(paste("y ~", first, "+", second)))
  expect_identical(issue$code, "E6038")
  expect_identical(issue$offset, nchar(paste("y ~", first, "")))
})

test_that("a part has at most 10,000 columns and a name at most 10,000 characters", {
  labels <- sprintf("l%02d", 0:21)
  data <- data.frame(y = rep(1, 22), a = labels, b = labels, c = labels)
  issue <- issue_of(formula_ir("y ~ a:b:c", data = data))
  expect_identical(issue$code, "E6075")
  expect_identical(issue$message, "The fixed part would have more than 10000 columns.")
  data$g <- labels
  issue <- issue_of(formula_ir("y ~ (0 + a:b:c | g)", data = data))
  expect_identical(issue$code, "E6075")
  expect_identical(issue$message,
                   "The random term '0 + a:b:c | g' would have more than 10000 columns.")
  names <- c("a", "b", "c", "d", "e", "f", "h", "i", "j", "k")
  declaration <- numeric_declaration(names)
  declaration$table$fields <- c(declaration$table$fields, list(list(name = "g", type = "string")))
  issue <- issue_of(formula_ir(paste0("y ~ (", paste(names, collapse = "*"), " | g)"), declaration))
  expect_identical(issue$code, "E6076")
  expect_match(issue$message, "^The name '1 \\+ a \\+ b \\+ c \\+ d")
  data <- data.frame(y = c(1, 2), a = c(strrep("x", 9997L), "short"))
  expect_identical(nchar(formula_ir("y ~ a", data = data)$fixed$columns[[2L]]$name), 10000L)
  data <- data.frame(y = c(1, 2), a = c(strrep("x", 9998L), "short"))
  expect_identical(issue_of(formula_ir("y ~ a", data = data))$code, "E6076")
})

test_that("a level that the IR cannot hold is refused at its first appearance", {
  for (label in c("line\nbreak", paste0("x", intToUtf8(0x1E4EC)), "tab\t", intToUtf8(0x85))) {
    data <- data.frame(y = c(1, 2, 3), x = c(1, 2, 3), c = c("a", label, "a"))
    issue <- issue_of(formula_ir("y ~ x + c", data = data))
    expect_identical(c(issue$code, issue$offset), c("E6074", "8"))
  }
  data <- data.frame(y = c(1, 2), c = c(intToUtf8(0xE9), intToUtf8(c(0x65, 0x301))))
  expect_identical(issue_of(formula_ir("y ~ c", data = data))$code, "E6056")
})

test_that("centring constants that are not finite are refused", {
  data <- data.frame(y = c(1, 2), x = c(1.7e308, 1.7e308))
  issue <- issue_of(formula_ir("y ~ x", data = data, coding = list(x = list(centring = "mean"))))
  expect_identical(issue$code, "E6077")
  expect_identical(issue$message, "A value computed for 'x' is not finite.")
  # The mean 1.79e308 rounds to '2e308' with one significant digit.
  data <- data.frame(y = c(1, 2, 3), x = rep(1.79e308, 3L))
  coding <- list(x = list(centring = "mean", significant_digits = 1))
  expect_identical(issue_of(formula_ir("y ~ x", data = data, coding = coding))$code, "E6077")
  coding <- list(x = list(centring = "value", value = paste0("1", strrep("0", 309L))))
  expect_identical(issue_of(formula_ir("y ~ x", numeric_declaration("x"), coding = coding))$code,
                   "E6077")
})

test_that("centring reports every code of one predictor before those of the next", {
  coding <- list(a = list(centring = "mean"), b = list(centring = "mean"))
  data <- data.frame(y = c(1, 2), a = c(1.7e308, 1.7e308), b = c(1, NaN))
  issue <- issue_of(formula_ir("y ~ b + a", data = data, coding = coding))
  expect_identical(c(issue$code, issue$message),
                   c("E6077", "A value computed for 'a' is not finite."))
  # The design sample is empty, so 'b' alone would give E6067.
  data <- data.frame(y = c(1, 2), a = c(1, 2), b = c(1, NA), s = c(NA, 1))
  coding$a <- list(centring = "value", value = paste0("1", strrep("0", 309L)))
  issue <- issue_of(formula_ir("y ~ a + b", data = data, coding = coding, sample_columns = "s"))
  expect_identical(c(issue$code, issue$message),
                   c("E6077", "A value computed for 'a' is not finite."))
})

test_that("integral numbers count as integers in the coding argument", {
  coding <- list(x = list(centring = "mean", significant_digits = 2))
  ir <- formula_ir("y ~ x", data = numbers, coding = coding)
  expect_identical(ir$predictors$x$centring$constant$significant_digits, 2)
  coding$x$significant_digits <- 2.5
  expect_identical(issue_of(formula_ir("y ~ x", data = numbers, coding = coding))$code, "E6063")
  coding$x$significant_digits <- TRUE
  expect_identical(issue_of(formula_ir("y ~ x", data = numbers, coding = coding))$code, "E6063")
})

test_that("a run of 4,998 operands of ':', '*' or '/' builds the IR", {
  # The parser holds a run as one chain, so that no walk recurses once per
  # operand.
  for (op in c(":", "*", "/")) {
    formula <- paste0("y ~ ", paste(rep("x", 4998L), collapse = op))
    expect_identical(nchar(formula), 9999L)
    ir <- formula_ir(formula, data = numbers)
    expect_identical(vapply(ir$fixed$columns, function(column) column$name, ""),
                     c("(Intercept)", "x"))
  }
  ir <- formula_ir(paste0("y ~ ", paste(rep("(x + z)", 1200L), collapse = ":")), data = numbers)
  expect_identical(vapply(ir$fixed$terms, function(term) term$name, ""),
                   c("(Intercept)", "x", "z", "x:z"))
  formula <- paste0("y ~ ", paste(rep("x", 3000L), collapse = ":"))
  expect_identical(issue_of(formula_ir(formula))$code, "E6051")
  inner <- paste0("(", paste(rep("x", 1000L), collapse = "*"), " | g)")
  ir <- formula_ir(paste0("y ~ ", inner), data = numbers)
  expect_identical(ir$random[[1L]]$name, "1 + x | g")
  nested <- paste0("y ~ ", strrep("x:z*(", 64L), "x", strrep(")", 64L))
  ir <- formula_ir(nested, data = numbers)
  expect_identical(vapply(ir$fixed$terms, function(term) term$name, ""),
                   c("(Intercept)", "x", "x:z"))
})

test_that("a sum of about 10,000 characters is expanded in seconds", {
  # About 1 s, also with a CPU-bound process on every core, and 3.5 s with
  # four other jobs, each running BLAS on four threads, on four cores. The
  # bound is seven times the latter, so that a loaded machine does not fail
  # the test.
  skip_on_cran()
  names <- paste0("x", seq_len(1850L))
  formula <- paste0("y ~ ", paste(names, collapse = "+"))
  expect_lt(nchar(formula), 10000L)
  data <- as.data.frame(setNames(rep(list(c(1, 2, 4, 8)), 1851L), c("y", names)))
  elapsed <- system.time(ir <- formula_ir(formula, data = data))[["elapsed"]]
  expect_length(ir$fixed$columns, 1851L)
  elapsed <- elapsed + system.time({
    issue <- issue_of(formula_ir(paste0("y ~ (", paste(names[1:1500], collapse = "+"), " | g)")))
  })[["elapsed"]]
  expect_identical(issue$code, "E6051")
  expect_lt(elapsed, 25)
})

test_that("a key that the coding argument repeats is shown escaped", {
  coding <- structure(list(list(), list()), names = c("a\tb", "a\tb"))
  expect_error(formula_ir("y ~ x", data = numbers, coding = coding),
               "'coding' names the column 'a\\u0009b' twice.", fixed = TRUE)
})
