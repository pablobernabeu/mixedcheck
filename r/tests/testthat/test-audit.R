# audit() and the machinery of the checks, in the parts that the audit
# corpus cannot reach: the arguments, columns of other types, times, keys,
# the access log and inputs, printing, and the machinery's rules for
# messages, thresholds, availability, scopes, count classes and order.

audit_key <- paste(sprintf("%02x", 0:31), collapse = "")

audit_data <- function() {
  data.frame(
    y = c(2.1, 3.4, 1.8, 2.9, 3.3, 4.1, 2.6, 3.7),
    x = c(1, 2, 3, 4, 5, 6, 7, 8),
    subject = c("s1", "s1", "s2", "s2", "s3", "s3", "s4", "s4"),
    trial = c(1, 2, 1, 2, 1, 2, 1, 2)
  )
}

# Runs audit() at the time 0 in internal mode with the example key.
audit_at_zero <- function(data = audit_data(), formula = "y ~ x + (1 | subject)", ...,
                          privacy = "internal", key = audit_key, time = "0") {
  with_audit_time(do.call(audit, c(list(data, formula), list(...),
                                   list(privacy = privacy, key = key))), time)
}

audit_issue <- function(...) {
  tryCatch({
    audit_at_zero(...)
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

audit_error <- function(...) {
  tryCatch({
    audit_at_zero(...)
    NULL
  }, mixedcheck_error = function(e) NULL, error = function(e) conditionMessage(e))
}

test_that("a run returns a valid results object with every member of the document", {
  results <- audit_at_zero()
  expect_s3_class(results, "mixedcheck_results")
  document <- results$document
  expect_identical(document$results_version, "0.1.0")
  expect_identical(document$created, "1970-01-01T00:00:00Z")
  expect_identical(document$stream, "B")
  expect_identical(document$software$language, "R")
  expect_identical(document$software$unicode$library, "utf8")
  expect_identical(document$privacy$mode, "internal")
  expect_identical(document$privacy$min_count, 10)
  expect_null(document$privacy$disclosure_unit)
  expect_identical(document$inputs$registry_hash, registry_hash())
  expect_null(document$inputs$declaration)
  expect_identical(document$inputs$model$formula, "y ~ x + (1 | subject)")
  expect_identical(document$inputs$model$family_class, "gaussian")
  expect_identical(names(document$inputs$data), "analysis_table")
  expect_identical(document$access_log,
                   list(entries = list(list(mode = "outcome_blind", tier = "T0",
                                            time = "1970-01-01T00:00:00Z"))))
  expect_identical(results$sidecar, list(
    sidecar_version = "0.1.0",
    keys = list(list(created = "1970-01-01T00:00:00Z", key = audit_key,
                     key_id = "630dcd2966c43366")),
    pseudonyms = list()
  ))
  # The document holds the values that the strict reader returns.
  expect_identical(read_json_strict(canonical_bytes(document, "data"), "data"), document)
  expect_silent(validate_results(results, data = audit_data()))
})

test_that("the arguments are checked in step 1 with their codes", {
  expect_identical(audit_issue(family = "Gaussian")$message, paste(
    "The family 'Gaussian' is not one of 'gaussian', 'binomial', 'poisson',",
    "'negative_binomial', 'beta', 'gamma', 'inverse_gaussian' or 'cumulative'."
  ))
  requirement <- function(...) audit_issue(...)$message
  expect_identical(requirement(outcome_access = "T1"), paste(
    "Outcome access at T1 needs a reason of 1 to 4000 characters without control characters."
  ))
  for (reason in c("", "a\tb", strrep("x", 4001L), "a\u007fb")) {
    expect_identical(audit_issue(outcome_access = "T1", reason = reason)$code, "E7009")
  }
  expect_null(audit_issue(outcome_access = "T1", reason = strrep("x", 4000L)))
  expect_identical(requirement(outcome_access = "T2", reason = "Look."),
                   "Outcome access at T2 needs the exploratory mode.")
  # The reason comes before the exploratory mode.
  expect_match(requirement(outcome_access = "T2"), "a reason of 1 to 4000")
  expect_identical(audit_issue(formula = "~ x + (1 | subject)", outcome_access = "T1",
                               reason = "Look.")$message,
                   "Outcome access at T1 needs a formula with a response.")
  expect_identical(audit_issue(key = "00")$code, "E1311")
  expect_identical(audit_issue(key = toupper(audit_key))$code, "E1311")
  # E7008 comes before E7009 and the key.
  expect_identical(audit_issue(family = "x", outcome_access = "T1", key = "00")$code, "E7008")
})

test_that("arguments of the wrong type give ordinary errors", {
  expect_match(audit_error(data = list(y = 1)), "'data' must be a data frame")
  expect_match(audit_error(formula = 1), "'formula' must be")
  expect_match(audit_error(family = 1), "'family' must be")
  expect_match(audit_error(coding = list(1)), "'coding' must be")
  expect_match(audit_error(weights = c("a", "b")), "'weights' must be")
  expect_match(audit_error(sample_columns = 1), "'sample_columns' must be")
  expect_match(audit_error(outcome_access = "t1"), "'outcome_access' must be")
  expect_match(audit_error(reason = 1, outcome_access = "T1"), "'reason' must be")
  expect_match(audit_error(reason = "Look."), "'reason' is given only for outcome access")
  expect_match(audit_error(exploratory = NA), "'exploratory' must be")
  expect_match(audit_error(outcome_seen = "yes"), "'outcome_seen' must be")
  expect_match(audit_error(privacy = "Internal"), "'privacy' must be")
  expect_match(audit_error(key = 1), "'key' must be")
})

test_that("columns of other types give an ordinary error", {
  data <- audit_data()
  columns <- list(
    date = as.Date("2026-01-01") + 0:7,
    time = as.POSIXct("2026-01-01", tz = "UTC") + 0:7,
    duration = as.difftime(1:8, units = "secs"),
    list = I(as.list(1:8)),
    complex = complex(real = 1:8, imaginary = 1)
  )
  for (name in names(columns)) {
    data[[name]] <- columns[[name]]
    expect_match(audit_error(data = data), sprintf("The column '%s' of 'data' is not a vector", name),
                 label = name)
    data[[name]] <- NULL
  }
  # Integer, factor and logical columns are read as numbers, labels and
  # booleans.
  data$trial <- as.integer(data$trial)
  data$subject <- factor(data$subject)
  data$flag <- rep(c(TRUE, FALSE), 4L)
  expect_s3_class(audit_at_zero(data = data), "mixedcheck_results")
})

test_that("the declaration's missing values apply to a data frame", {
  data <- audit_data()
  data$x[3L] <- -99
  declaration <- list(vocabulary = "0.1.0", table = list(
    missingValues = list("", "-99"),
    fields = list(list(name = "y", type = "number"), list(name = "x", type = "number"),
                  list(name = "subject", type = "string"), list(name = "trial", type = "integer"))
  ))
  results <- audit_at_zero(data = data, declaration = declaration)
  sample <- Filter(function(f) f$check == "sample.raw_vs_analysis", results$document$findings)[[1L]]
  expect_identical(sample$statistics$rows_kept$value, 7)
  expect_identical(sample$statistics$incomplete_columns$value, list("x"))
})

test_that("a data frame must keep every declared column within its categories", {
  # The rule on observation keys of the privacy filter counts a column with
  # declared categories among those whose levels the declaration gives, so
  # trial and cond, which the formula does not read, are refused outside
  # them too, as the table reader refuses them in a file.
  data <- audit_data()
  data$cond <- rep(c("A", "E\u0301"), 4L)
  data$flag <- rep(c(TRUE, FALSE), 4L)
  declaration <- list(vocabulary = "0.1.0", observation = list(key = list("subject", "trial")),
                      table = list(missingValues = list("", "-99"), fields = list(
    list(name = "y", type = "number"), list(name = "x", type = "number"),
    list(name = "subject", type = "string"),
    list(name = "trial", type = "integer", categories = list(1, 2)),
    list(name = "cond", type = "string",
         categories = list(list(value = "A"), list(value = "\u00c9", label = "E acute"))),
    list(name = "flag", type = "boolean")
  )))
  # NFC compares strings, and a category given as an object matches
  # through its value.
  expect_s3_class(audit_at_zero(data = data, declaration = declaration), "mixedcheck_results")
  data$cond[2L] <- "E"
  issue <- audit_issue(data = data, declaration = declaration)
  expect_identical(issue$code, "E5012")
  expect_identical(issue$pointer, "/data/cond/1")
  expect_identical(issue$message,
                   "The value of the column 'cond' at /data/cond/1 is not one of its declared categories.")
  # Missing values are not compared.
  data$cond[c(2L, 4L)] <- c("-99", NA)
  expect_s3_class(audit_at_zero(data = data, declaration = declaration), "mixedcheck_results")
  # Integers compare by value, the earliest row comes first and, within a
  # row, the first column of the data frame.
  data$trial[7L] <- 3
  data$cond[7L] <- "C"
  expect_identical(audit_issue(data = data, declaration = declaration)$pointer, "/data/trial/6")
  data$trial[7L] <- 1.5
  data$cond[5L] <- "C"
  expect_identical(audit_issue(data = data, declaration = declaration)$pointer, "/data/cond/4")
  data$cond[5L] <- "A"
  expect_identical(audit_issue(data = data, declaration = declaration)$pointer, "/data/trial/6")
  data$trial[7L] <- NaN
  expect_identical(audit_issue(data = data, declaration = declaration)$pointer, "/data/trial/6")
  data$trial[7L] <- 1L
  data$cond[7L] <- "A"
  expect_s3_class(audit_at_zero(data = data, declaration = declaration), "mixedcheck_results")
  # The pointer names the column as the data frame does.
  names(data)[5L] <- "co/nd~"
  declaration$table$fields[[5L]]$name <- "co/nd~"
  data[[5L]][2L] <- "C"
  expect_identical(audit_issue(data = data, declaration = declaration)$pointer,
                   "/data/co~1nd~0/1")
})

test_that("MIXEDCHECK_TIME sets every time of a run, and other values are refused", {
  results <- audit_at_zero(time = "1767225600", outcome_access = "T1", reason = "Look.")
  document <- results$document
  expect_identical(document$created, "2026-01-01T00:00:00Z")
  expect_identical(vapply(document$access_log$entries, function(e) e$time, ""),
                   rep("2026-01-01T00:00:00Z", 2L))
  expect_identical(results$sidecar$keys[[1L]]$created, "2026-01-01T00:00:00Z")
  # Only the ASCII digits 0 to 9 are digits, whatever Python's int() reads.
  for (value in c("-1", "1.5", "1e9", " 1", "1 ", "+1", "1_0", "253402300800", "abc")) {
    expect_match(audit_error(time = value), "MIXEDCHECK_TIME must be a whole number", label = value)
  }
  if (l10n_info()[["UTF-8"]]) {
    for (value in c("\u0663", "1\u0663", "\u00b2", "\uff11")) {
      expect_match(audit_error(time = value), "MIXEDCHECK_TIME must be a whole number",
                   label = value)
    }
  }
  expect_identical(audit_at_zero(time = "0000253402300799")$document$created,
                   "9999-12-31T23:59:59Z")
  # An empty value counts as unset, as on Windows.
  created <- audit_at_zero(time = "")$document$created
  expect_match(created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  expect_false(identical(created, "1970-01-01T00:00:00Z"))
  expect_identical(utc_timestamp(c(951782400, 951868800, 4107542400, 86399)),
                   c("2000-02-29T00:00:00Z", "2000-03-01T00:00:00Z",
                     "2100-03-01T00:00:00Z", "1970-01-01T23:59:59Z"))
})

test_that("a run without a key creates one from a secure source", {
  skip_without_key_source()
  results <- audit_at_zero(key = NULL)
  key <- results$sidecar$keys[[1L]]
  expect_match(key$key, "^[0-9a-f]{64}$")
  expect_identical(key$key_id, commitment_key_id(key$key))
  expect_identical(results$document$inputs$data$analysis_table$key_id, key$key_id)
})

test_that("without /dev/urandom, keys come from openssl, or E1312 without it", {
  local_mocked_bindings(platform_type = function() "windows")
  local_mocked_bindings(package_installed = function(package) FALSE)
  expect_identical(audit_issue(key = NULL)$code, "E1312")
  expect_identical(tryCatch(new_commitment_key(), mixedcheck_error = function(e) e$issues[[1L]]$code),
                   "E1312")
  # A supplied key needs no source.
  expect_s3_class(audit_at_zero(), "mixedcheck_results")
  skip_if_not_installed("openssl")
  local_mocked_bindings(package_installed = function(package) TRUE)
  first <- new_commitment_key()
  second <- new_commitment_key()
  expect_match(first$key, "^[0-9a-f]{64}$")
  expect_false(identical(first$key, second$key))
  expect_identical(first$key_id, commitment_key_id(first$key))
  expect_match(audit_at_zero(key = NULL)$sidecar$keys[[1L]]$key, "^[0-9a-f]{64}$")
})

test_that("a /dev/urandom that cannot be read falls back to openssl", {
  local_mocked_bindings(platform_type = function() "unix", urandom_bytes = function() NULL)
  local_mocked_bindings(package_installed = function(package) FALSE)
  expect_identical(tryCatch(new_commitment_key(), mixedcheck_error = function(e) e$issues[[1L]]$code),
                   "E1312")
  skip_if_not_installed("openssl")
  local_mocked_bindings(package_installed = function(package) TRUE)
  expect_match(new_commitment_key()$key, "^[0-9a-f]{64}$")
})

test_that("the access log records each outcome column read at each tier", {
  data <- data.frame(k = c(1, 2, 0, 1, 3, 2), n = c(3, 3, 2, 4, 4, 5), x = 1:6,
                     s = c("a", "a", "b", "b", "c", "c"))
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ), provenance = list(outcome_seen = TRUE))
  results <- audit_at_zero(data = data, formula = "k ~ x + (1 | s)", declaration = declaration,
                           outcome_access = "T2", reason = "Look.", exploratory = TRUE)
  log <- results$document$access_log
  expect_true(log$outcome_seen)
  entries <- log$entries
  expect_identical(vapply(entries, function(e) paste(e$tier, e$outcome$column %||% ""), ""),
                   c("T0 ", "T1 k", "T1 n", "T2 k", "T2 n"))
  expect_identical(unique(vapply(entries[-1L], function(e) e$mode, "")), "exploratory")
  expect_identical(unique(vapply(entries[-1L], function(e) e$reason, "")), "Look.")
  expect_identical(entries[[2L]]$outcome$commitment,
                   outcome_commitment(run_data(data, validate_declaration(declaration)),
                                      validate_declaration(declaration), "k", audit_key))
  expect_identical(results$document$inputs$model$family_class, "binomial")
  expect_identical(results$document$inputs$declaration$minimal, FALSE)
  expect_identical(results$document$inputs$declaration$draft, FALSE)
  expect_silent(validate_results(results, data = data, declaration = declaration))
  # The attestation agrees with the declaration or is refused.
  expect_match(audit_error(data = data, formula = "k ~ x", declaration = declaration,
                           outcome_seen = FALSE), "'outcome_seen' differs")
  expect_false(audit_at_zero(outcome_seen = FALSE)$document$access_log$outcome_seen)
})

test_that("a run from a CSV file commits to the file's bytes", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw("y,x,g\n1.5,1,a\n2,2,a\n2.5,3,b\n,4,b\n"), path)
  results <- audit_at_zero(data = path, formula = "y ~ x + (1 | g)")
  data <- results$document$inputs$data
  expect_identical(data$data_file,
                   keyed_commitment(readBin(path, "raw", file.size(path)), audit_key, "data_file"))
  expect_silent(validate_results(results, data = path))
  # A data frame cannot stand for the file.
  expect_error(validate_results(results, data = read_table(path)), "path of that file")
})

test_that("E5011 takes the places of E2007 in order, and E6069 the columns that read the outcome", {
  declaration <- list(vocabulary = "0.1.0",
                      units = list(list(name = "subject", columns = list("subject"))),
                      observation = list(key = list("subject", "wave")),
                      variables = list(zzz = list(role = "auxiliary"), aaa = list(role = "time")))
  issue <- audit_issue(declaration = declaration)
  expect_identical(issue$pointer, "/observation/key/1")
  declaration$observation <- NULL
  expect_identical(audit_issue(declaration = declaration)$pointer, "/variables/aaa")
  declaration <- list(vocabulary = "0.1.0", variables = list(
    x = list(role = "outcome_derived"), y = list(role = "outcome")
  ))
  expect_identical(audit_issue(declaration = declaration)$message, paste(
    "The column 'x' is an outcome, is derived from one or holds the trials of the response,",
    "so the outcome-blind checks cannot read it."
  ))
  declaration$variables$x <- NULL
  data <- audit_data()
  data$w <- 1
  declaration$variables$w <- list(role = "outcome_derived")
  expect_match(audit_issue(data = data, declaration = declaration, weights = "w")$message,
               "'w'")
  expect_match(audit_issue(data = data, formula = "y ~ x + offset(w)",
                           declaration = declaration)$message, "'w'")
  # The response is an outcome whatever the declaration says: as the weights
  # column, a key column or a unit column, and an outcome-derived sample
  # column, are refused, whereas the response as a sample column is left
  # out of the IR's sample columns (ir.md, Samples).
  data <- audit_data()
  data$z <- data$y
  expect_match(audit_issue(data = data, weights = "y")$message, "'y'")
  key_declaration <- list(vocabulary = "0.1.0", observation = list(key = list("trial", "y")))
  expect_match(audit_issue(data = data, declaration = key_declaration)$message, "'y'")
  unit_declaration <- list(vocabulary = "0.1.0",
                           units = list(list(name = "p", columns = list("y"), role = "participant")))
  expect_match(audit_issue(data = data, formula = "y ~ x",
                           declaration = unit_declaration)$message, "'y'")
  derived <- list(vocabulary = "0.1.0", variables = list(
    y = list(role = "outcome"), z = list(role = "outcome_derived", derived_from = list("y"))
  ))
  expect_match(audit_issue(data = data, declaration = derived, sample_columns = "z")$message,
               "'z'")
  expect_null(audit_issue(data = data, sample_columns = "y"))
  assigned <- list(vocabulary = "0.1.0",
                   units = list(list(name = "subject", columns = list("subject"))),
                   assignment = list(list(column = "y", unit = "subject", randomised = TRUE)))
  expect_match(audit_issue(data = data, declaration = assigned)$message, "'y'")
})

test_that("documents depend on no option, and a run leaves options and the generator alone", {
  data <- data.frame(k = c(1, 2, 0, 1, 3, 2, 0, 2), n = c(3, 3, 2, 4, 4, 5, 2, 3),
                     x = c(0.5, 1.25, 2, 3.5, 4, 5.75, 6, 7.5), s = rep(c("a", "b", "c", "d"), 2))
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")
  ))
  run <- function(tier) {
    arguments <- list(data = data, formula = "k ~ x + (1 | s)", declaration = declaration)
    if (tier != "T0") {
      arguments <- c(arguments, list(outcome_access = tier, reason = "Look.",
                                     exploratory = tier == "T2"))
    }
    canonical_bytes(do.call(audit_at_zero, arguments)$document, "data")
  }
  tiers <- if (requireNamespace("lpSolve", quietly = TRUE)) c("T1", "T2") else "T1"
  expected <- lapply(tiers, run)
  old <- options(OutDec = ",", digits = 3, scipen = 100, warn = 2)
  on.exit(options(old), add = TRUE)
  local_seed(3)
  seed <- .Random.seed
  before <- options()
  expect_identical(lapply(tiers, run), expected)
  expect_identical(.Random.seed, seed)
  expect_identical(options(), before)
})

test_that("names outside ASCII give the same document in a C locale", {
  # 'g' with U+00FC, and the ASCII text that a C locale writes for it, which
  # names that are translated to the native encoding would merge.
  accented <- intToUtf8(c(103L, 252L))
  escaped <- "g<U+00FC>"
  size <- intToUtf8(c(71L, 114L, 246L, 223L, 101L))
  data <- data.frame(y = seq(1, 6, length.out = 60), x = rep(1:6, 10),
                     a = sprintf("l%02d", rep(1:20, 3)), b = rep(c("p", "q", "r"), 20))
  data$x[c(5L, 17L)] <- 3.5
  names(data) <- c("y", size, accented, escaped)
  formula <- paste0("y ~ `", size, "` + (1 | `", accented, "`) + (1 | `", escaped, "`)")
  expected <- canonical_bytes(audit_at_zero(data, formula)$document, "data")
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  Sys.setlocale("LC_CTYPE", "C")
  expect_no_warning(results <- audit_at_zero(data, formula))
  expect_identical(canonical_bytes(results$document, "data"), expected)
  checks <- vapply(results$document$findings, function(finding) finding$check, "")
  expect_identical(sum(checks == "structure.cluster_sizes"), 2L)
  expect_true("structure.label_incidence" %in% checks)
})

test_that("the family class follows the family or the declared measurement", {
  data <- data.frame(k = c(1, 0, 1, 1), n = c(2, 2, 2, 2), x = 1:4)
  class_of <- function(...) audit_at_zero(data = data, ...)$document$inputs$model$family_class
  expect_identical(class_of(formula = "k ~ x"), "gaussian")
  expect_identical(class_of(formula = "k ~ x", family = "binomial"), "bernoulli")
  expect_identical(class_of(formula = "k ~ x", family = "negative_binomial"), "poisson")
  expect_identical(class_of(formula = "k ~ x", family = "cumulative"), "other")
  measured <- function(measurement) {
    declaration <- list(vocabulary = "0.1.0", variables = list(k = list(
      role = "outcome", measurement = measurement
    )))
    if (measurement == "binomial") {
      declaration$variables$k$trials <- "n"
    }
    class_of(formula = "k ~ x", declaration = declaration)
  }
  expect_identical(vapply(c("binary", "binomial", "count", "ordinal", "continuous",
                            "positive_duration"), measured, ""),
                   c(binary = "bernoulli", binomial = "binomial", count = "poisson",
                     ordinal = "other", continuous = "gaussian", positive_duration = "gaussian"))
  declaration <- list(vocabulary = "0.1.0",
                      variables = list(k = list(role = "outcome", measurement = "count")),
                      provenance = list(inferred = list("/variables/k/measurement")))
  expect_identical(class_of(formula = "k ~ x", declaration = declaration), "gaussian")
})

test_that("printing an audit shows its banner and findings", {
  lines <- capture.output(print(audit_at_zero()))
  expect_identical(lines[1L], paste(
    "INTERNAL: this report holds values that the privacy filter has not checked,",
    "such as small counts and labels. Do not share it."
  ))
  expect_true("keys.duplicates: not available (declaration_missing: /observation/key)." %in% lines)
})

test_that("messages render every kind of argument as registry.md describes", {
  expect_identical(real_text(0.125, 2L), "0.12")
  expect_identical(real_text(0.375, 2L), "0.38")
  expect_identical(real_text(2.5, 0L), "2")
  expect_identical(real_text(3.5, 0L), "4")
  expect_identical(real_text(-0.04, 1L), "0.0")
  expect_identical(real_text(-0.06, 1L), "-0.1")
  expect_identical(real_text(0, 2L), "0.00")
  expect_identical(real_text(1234.5678, 2L), "1234.57")
  expect_identical(real_text(1e-30, 3L), "under 0.001")
  expect_identical(real_text(1e21, 1L), "1.0e+21")
  expect_identical(real_text(0.005, 2L), "0.01")
  expect_identical(real_text(NaN, 2L), "NaN")
  expect_identical(real_text(-Inf, 2L), "-Infinity")
  expect_identical(ratio_text(23, 40, 0L), "58%")
  expect_identical(ratio_text(23, 80, 1L), "28.8%")
  expect_identical(ratio_text(1, 8, 0L), "12%")
  expect_identical(ratio_text(3, 8, 0L), "38%")
  expect_identical(ratio_text(0, 7, 1L), "0.0%")
  expect_identical(ratio_text(7, 7, 0L), "100%")
  expect_identical(percent_text("0.15"), "15%")
  expect_identical(percent_text("0.125"), "12.5%")
  expect_identical(percent_text("1"), "100%")
  expect_identical(percent_text("0"), "0%")
  expect_identical(percent_text("0.0005"), "0.05%")
  expect_identical(names_text(character(0)), "none")
  expect_identical(names_text("a"), "'a'")
  expect_identical(names_text(c("a", "b\tc", "d")), "'a', 'b\\u0009c' and 'd'")
  entry <- registry_entry("keys.duplicates")
  values <- list(key_columns = "id", identical_keys = 1, duplicate_rows = 1)
  expect_identical(render_message(entry, "double_import", list(), values), paste(
    "Values of the observation key 'id' shared by identical rows: 1, with 1 row in all,",
    "which suggests rows imported twice. Remove the copies at the source."
  ))
  # A statistic that is not written gives the fallback.
  expect_identical(render_message(entry, "double_import", list(), values, written = "key_columns"),
                   paste("Some values of the observation key 'id' are shared by identical rows,",
                         "which suggests rows imported twice. Remove the copies at the source."))
  entry <- registry_entry("outcome.boundary_shares")
  values <- list(rows = 40, at_floor = 1, at_ceiling = 23, floor_share = 1 / 40,
                 ceiling_share = 23 / 40)
  expect_match(render_message(entry, "at_bounds", list(), values), "57.5%")
  expect_match(render_message(entry, "at_bounds", list(), values), "15%")
  entry <- registry_entry("identifiability.gram_rank")
  expect_error(render_message(entry, "no_such_message", list(), list()), "Internal error")
})

test_that("thresholds compare counts, ratios and reals exactly, with proximity bands", {
  entry <- registry_entry("outcome.boundary_shares")
  shares <- function(at, rows) list(at_ceiling = at, rows = rows, ceiling_share = at / rows)
  # 0.15 of 20 is 3: the comparison is exact, so 3 of 20 is not above it.
  expect_false(threshold_holds(entry, "ceiling", shares(3, 20)))
  expect_true(threshold_holds(entry, "ceiling", shares(31, 200)))
  expect_false(threshold_holds(entry, "ceiling", list(rows = 20)))
  entry <- registry_entry("design.collinearity")
  expect_true(threshold_holds(entry, "high", list(gvif_per_df = 10)))
  expect_false(threshold_holds(entry, "high", list(gvif_per_df = 9.999)))
  expect_false(threshold_holds(entry, "high", list(gvif_per_df = NaN)))
  element <- check_element(list(), proximity = list())
  expect_true(finding_near_threshold(entry, list(gvif_per_df = 10 + 5e-9), element))
  expect_false(finding_near_threshold(entry, list(gvif_per_df = 10 + 2e-8), element))
  expect_false(finding_near_threshold(entry, list(gvif_per_df = NaN), element))
  expect_false(finding_near_threshold(entry, list(), element))
  entry <- registry_entry("identifiability.gram_rank")
  near <- function(values) {
    finding_near_threshold(entry, list(), check_element(list(), proximity = list(rank_tolerance = values)))
  }
  expect_true(near(c(1, 5e-10)))
  expect_true(near(-2e-11))
  expect_false(near(c(1, 2e-9, 9e-12)))
  expect_true(finding_near_threshold(entry, list(), check_element(list(), near_threshold = TRUE)))
  expect_identical(finding_validation(registry_entry("design.collinearity")), "descriptive")
  expect_identical(finding_validation(registry_entry("keys.duplicates")), "descriptive")
})

test_that("package_missing makes a check not available before it runs", {
  run <- new.env()
  run$ir <- list()
  run$family_class <- "gaussian"
  entry <- registry_entry("keys.duplicates")
  entry$availability <- c(list(list(reason = "package_missing", condition = "No package.",
                                    packages = list(R = list("mixedcheck.no.such.package")))),
                          entry$availability)
  expect_identical(run_check(run, entry), list(list(
    check = "keys.duplicates", check_version = 1, tier = "T0", scope = empty_object(),
    available = FALSE,
    availability = list(value = "not_available", reason = "package_missing",
                        detail = "mixedcheck.no.such.package")
  )))
  # A family filter that excludes the class yields no finding at all.
  entry$families <- list("poisson")
  expect_identical(run_check(run, entry), list())
})

test_that("every entry checks its package_missing rules first", {
  for (entry in read_registry()$entries) {
    reasons <- vapply(entry$availability, function(rule) rule$reason, "")
    packages <- reasons == "package_missing"
    expect_false(any(packages[cumsum(!packages) > 0L]), label = entry$id)
  }
})

test_that("checks run in order of identifier after the checks they require", {
  entries <- registry_entries_by_id()
  order <- check_order(entries, "T2")
  expect_length(order, length(entries))
  for (id in order) {
    for (required in unlist(entries[[id]]$links$requires)) {
      expect_lt(match(required, order), match(id, order))
    }
  }
  expect_true(all(vapply(entries[check_order(entries, "T0")], function(e) e$tier, "") == "T0"))
  expect_identical(check_order(entries, "T0")[1:2],
                   c("assignment.constant_within_unit", "assignment.design_df"))
})

# A run of audit() as the checks see it, for the tests of the machinery.
machinery_run <- function(data, formula, declaration = NULL) {
  declaration <- if (!is.null(declaration)) validate_declaration(declaration)
  table <- run_data(data, declaration)$table
  ir <- build_formula_ir(formula, declaration, table, coding_input(NULL), NULL, character(0))
  model <- design_model(ir, table, analysis = FALSE)
  new_run(declaration, table, ir, "gaussian", "T0", model, design_build(ir, model, table))
}

test_that("scope elements follow registry.md", {
  data <- data.frame(y = 1:8, a = rep(c("p", "q"), 4L), x = 1:8, z = c(1, 2, 1, 2, 3, 3, 4, 4),
                     school = rep(c("S1", "S2"), each = 4L), class = rep(c("c1", "c2"), 4L),
                     district = rep("D1", 8L))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "district", columns = list("district")),
    list(name = "school", columns = list("school"), nested_in = "district", id_scope = "global"),
    list(name = "class", columns = list("class"), nested_in = "school", id_scope = "within_parent")
  ), assignment = list(list(column = "a", unit = "class", randomised = TRUE)))
  run <- machinery_run(data, "y ~ a * x + (1 | class) + (0 + z | class)", declaration)
  expect_identical(scope_elements(run, "model"), list(empty_object()))
  expect_identical(scope_elements(run, "grouping_factor"), list(list(factor = "class")))
  expect_identical(scope_elements(run, "grouping_factor_pair"), list())
  # school, the column of the parent of the unit of class, is not a grouping
  # column, so it is paired with class.
  expect_identical(scope_elements(run, "grouping_column_pair"),
                   list(list(first = "class", second = "school")))
  expect_identical(vapply(scope_elements(run, "fixed_term"), function(e) e$term, ""),
                   c("a", "x", "a:x"))
  expect_length(scope_elements(run, "fixed_term_by_factor"), 3L)
  expect_identical(scope_elements(run, "assignment"), list(list(column = "a", unit = "class")))
  expect_identical(vapply(scope_elements(run, "column"), function(e) e$column, ""),
                   c("a", "class", "district", "school", "x", "y", "z"))
  expect_identical(unit_label_columns(run$declaration, "class"), c("school", "class"))
  expect_identical(unit_label_columns(run$declaration, "school"), "school")
  run <- machinery_run(data, "y ~ x + (1 | class) + (1 + x | school:class)", declaration)
  expect_identical(scope_elements(run, "grouping_factor_pair"),
                   list(list(first = "class", second = "school:class")))
  # school is now a grouping column, and the column of its parent is not.
  expect_identical(scope_elements(run, "grouping_column_pair"),
                   list(list(first = "class", second = "school"),
                        list(first = "district", second = "school")))
  expect_identical(scope_elements(run, "random_term")[[2L]],
                   list(term = "1 + x | school:class", factor = "school:class"))
  expect_length(scope_elements(run, "fixed_term_by_factor"), 2L)
  # A nesting that counts as absent gives no parent.
  declaration$provenance <- list(inferred = list("/units/2/nested_in"))
  run <- machinery_run(data, "y ~ x + (1 | class)", declaration)
  expect_identical(scope_elements(run, "grouping_column_pair"), list())
  expect_identical(unit_label_columns(run$declaration, "class"), "class")
  run <- machinery_run(data, "y ~ x")
  expect_identical(scope_elements(run, "grouping_factor_or_model"), list(empty_object()))
  expect_identical(scope_elements(run, "assignment"), list())
})

test_that("by_unit counts resolve by the members of the disclosure unit", {
  data <- data.frame(y = 1:8, pupil = c("p1", "p2", "p3", "p4", "p5", "p6", "p7", "p7"),
                     school = c("A", "A", "B", "B", "C", "C", "D", "D"),
                     session = c("s1", "s1", "s2", "s2", "s3", "s4", "s5", "s5"))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "pupil", columns = list("pupil"), role = "participant")
  ))
  run <- machinery_run(data, "y ~ 1 + (1 | school) + (1 | session)", declaration)
  expect_identical(run$disclosure$name, "pupil")
  expect_identical(run$disclosure$source, "participant")
  rows <- seq_len(8L)
  item <- function(key) value_codes(run, key)
  # Every school holds two pupils, but D holds one pupil twice.
  expect_identical(resolve_count_class(run, list(item("school")), 1:6), "non_person")
  expect_identical(resolve_count_class(run, list(item("school")), rows), "person")
  # Sessions s3 and s4 hold one pupil each.
  expect_identical(resolve_count_class(run, list(item("session")), 1:4), "non_person")
  expect_identical(resolve_count_class(run, list(item("session")), 1:6), "person")
  # Combinations of two items.
  expect_identical(resolve_count_class(run, list(item("school"), item("session")), 1:4),
                   "non_person")
  expect_identical(resolve_count_class(run, list(item("school"), item("session")), 1:6),
                   "person")
  expect_identical(resolve_count_class(run, list(NULL), rows), "person")
  # A level whose rows all lack a member has none.
  data$pupil[1:2] <- NA
  run <- machinery_run(data, "y ~ 1 + (1 | school)", declaration)
  expect_identical(resolve_count_class(run, list(value_codes(run, "school")), 1:6), "person")
  # Without a disclosure unit, every by_unit count counts persons.
  run <- machinery_run(data, "y ~ 1 + (1 | school)")
  expect_null(run$disclosure)
  expect_identical(resolve_count_class(run, list(value_codes(run, "school")), 3:6), "person")
})

test_that("the support counts the contributors of each basis", {
  data <- data.frame(y = 1:6, g = c("a", "a", "a", "a", "a", "b"), h = c(1, 2, 3, 4, 5, NA),
                     x = c(1, 2, 3, 4, 5, 6))
  run <- machinery_run(data, "y ~ x + (1 | g) + (1 | h)")
  support <- sample_support(run, "table")
  expect_identical(support[c("rows", "basis", "distinct", "dominated")],
                   list(rows = 6L, basis = "grouping_factors", distinct = 2, dominated = TRUE))
  expect_identical(support$largest, c(g = 6, h = 2))
  expect_identical(sample_support(run, "design")$rows, 5L)
  run <- machinery_run(data, "y ~ x")
  support <- sample_support(run, "design")
  expect_identical(support[c("rows", "basis", "distinct", "dominated", "largest")],
                   list(rows = 6L, basis = "rows", distinct = 6L, dominated = FALSE, largest = 2L))
  run <- machinery_run(data[1L, ], "y ~ x")
  expect_true(sample_support(run, "design")$dominated)
})

test_that("findings are ordered by check and then by their scopes", {
  findings <- list(
    list(check = "b.check", scope = list(column = "a")),
    list(check = "a.check", scope = list(second = "x", first = "z")),
    list(check = "a.check", scope = list(first = "y", second = "x")),
    list(check = "a.check", scope = list(first = "y")),
    list(check = "b.check", scope = list(column = "B"))
  )
  ordered <- order_findings(findings)
  expect_identical(vapply(ordered, function(f) paste(c(f$check, unlist(f$scope)), collapse = " "), ""),
                   c("a.check y", "a.check y x", "a.check x z", "b.check B", "b.check a"))
})

test_that("check functions that break the machinery's contract are internal errors", {
  run <- machinery_run(audit_data(), "y ~ x + (1 | subject)")
  entry <- registry_entry("keys.duplicates")
  scope <- empty_object()
  bad <- function(element) {
    tryCatch(assemble_finding(run, entry, scope, element), error = conditionMessage)
  }
  expect_match(bad(list()), "not check_element")
  expect_match(bad(check_element(list(no_such = 1))), "no statistic 'no_such'")
  expect_match(bad(check_element(list(rows = -1))), "not a valid count")
  expect_match(bad(check_element(list(rows = 1), rules = TRUE)), "some rule of its decision")
  entry <- registry_entry("outcome.boundary_shares")
  expect_match(tryCatch(assemble_finding(run, entry, scope, check_element(
    list(floor_share = 0.5))), error = conditionMessage), "not a valid ratio")
})
