# Names outside ASCII under LC_CTYPE=C. `[[`, assign() and get() translate a
# name to the native encoding, which in a C locale writes 'g' with U+00FC as
# the ASCII text 'g<U+00FC>', so a lookup by such a name would find a column
# of that literal name. The declaration validator, the table reader and
# audit() must give the same results as under a UTF-8 locale.

# Runs code with LC_CTYPE set to the first of the locales that can be set,
# and restores it afterwards. Skips the test when none can be set.
in_ctype <- function(locales, code) {
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  set <- FALSE
  for (locale in locales) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", locale)))) {
      set <- TRUE
      break
    }
  }
  skip_if_not(set, paste("None of the locales", paste(locales, collapse = ", "), "can be set."))
  force(code)
}

utf8_locales <- c("C.UTF-8", "en_US.UTF-8", "en_GB.UTF-8", "English_United States.utf8")

# Runs code under a UTF-8 locale and under the C locale and returns both
# results, checking that the C run is in a locale that is not UTF-8.
in_both_locales <- function(code) {
  code <- substitute(code)
  frame <- parent.frame()
  list(
    utf8 = in_ctype(utf8_locales, {
      expect_true(isTRUE(l10n_info()[["UTF-8"]]))
      eval(code, frame)
    }),
    c = in_ctype("C", {
      expect_false(isTRUE(l10n_info()[["UTF-8"]]))
      eval(code, frame)
    })
  )
}

# 'g' with U+00FC, and the ASCII text that the C locale writes for it.
accented <- intToUtf8(c(103L, 252L))
escaped <- "g<U+00FC>"

named <- function(values, names) {
  names(values) <- names
  values
}

# The code and pointer of each issue of a declaration, or NULL when it is
# valid.
declaration_problems <- function(declaration) {
  tryCatch({
    validate_declaration(declaration)
    NULL
  }, mixedcheck_error = function(e) {
    vapply(e$issues, function(issue) paste(issue$code, issue$pointer), "")
  })
}

test_that("the declaration validator tells apart names that a C locale merges", {
  base <- list(vocabulary = "0.1.0", variables = named(list(
    list(role = "outcome", measurement = "continuous"),
    list(role = "baseline_covariate", measurement = "bounded_score", bounds = list(0, 10)),
    list(role = "auxiliary", measurement = "bounded_score", bounds = list(0, 100),
         derived_from = list("x"))
  ), c("y", accented, escaped)))
  valid <- base
  valid$provenance <- list(inferred = list(paste0("/variables/", escaped, "/derived_from")))
  # The pointer names a member of the other column (E2009), bounds that are
  # not increasing (E2017) and a column derived from the outcome without an
  # outcome role (E2020).
  dangling <- base
  dangling$provenance <- list(inferred = list(paste0("/variables/", accented, "/derived_from")))
  meaning <- base
  meaning$variables[[2L]]$bounds <- list(5, 1)
  meaning$variables[[2L]]$derived_from <- list("y")
  results <- in_both_locales(list(
    valid = canonical_bytes(validate_declaration(valid), "hashable"),
    dangling = declaration_problems(dangling),
    meaning = declaration_problems(meaning)
  ))
  expect_identical(results$c, results$utf8)
  pointer <- paste0("/variables/", accented)
  expect_identical(results$utf8$dangling, "E2009 /provenance/inferred/0")
  expect_identical(results$utf8$meaning,
                   c(paste0("E2017 ", pointer, "/bounds"), paste0("E2020 ", pointer, "/role")))
})

test_that("read_table() and audit() tell apart names that a C locale merges", {
  rows <- 24L
  lines <- sprintf("%s,s%d,%s,%s", format(seq_len(rows) / 4), (seq_len(rows) - 1L) %/% 4L,
                   c("a", "b", "c")[seq_len(rows) %% 3L + 1L], format((seq_len(rows) * 7L) %% 11L))
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeBin(c(charToRaw("y,s,"), charToRaw(enc2utf8(accented)), charToRaw(","),
             charToRaw(escaped), charToRaw("\n"),
             charToRaw(paste0(paste(gsub(" ", "", lines), collapse = "\n"), "\n"))), path)
  declaration <- list(
    vocabulary = "0.1.0",
    units = list(list(name = "subject", columns = list("s"), role = "participant")),
    variables = named(list(
      list(role = "outcome", measurement = "continuous"),
      list(role = "baseline_covariate"),
      list(role = "baseline_covariate", measurement = "bounded_score", bounds = list(0, 10))
    ), c("y", accented, escaped))
  )
  formula <- paste0("y ~ `", accented, "` + `", escaped, "` + (1 | s)")
  coding <- named(list(list(contrast = "sum"), list(centring = "mean")), c(accented, escaped))
  key <- paste(sprintf("%02x", 0:31), collapse = "")
  results <- in_both_locales(list(
    table = read_table(path),
    ir = formula_ir(formula, declaration, read_table(path), coding),
    document = with_audit_time(canonical_bytes(
      audit(path, formula, declaration = declaration, coding = coding, key = key)$document,
      "data"
    ))
  ))
  expect_identical(results$c, results$utf8)
  expect_identical(names(results$utf8$table), c("y", "s", accented, escaped))
  predictors <- results$utf8$ir$predictors
  expect_identical(names(predictors), c(escaped, accented))
  expect_identical(predictors[[1L]]$centring$rule, "mean")
  expect_identical(predictors[[2L]]$kind, "categorical")
  expect_identical(predictors[[2L]]$contrast, "sum")
})
