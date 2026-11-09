# The results corpus: results documents checked in the five stages of
# validate_results(), and internal sidecars read, checked and verified
# against their documents (fixtures/conformance/results/README.md).

# Calls f and returns the issues of its error and of its warnings, in the
# order signalled, and whether it signalled an error.
capture_results_issues <- function(f) {
  warned <- list()
  result <- withCallingHandlers(
    capture_issues(f),
    mixedcheck_warning = function(w) {
      warned <<- c(warned, w$issues)
      invokeRestart("muffleWarning")
    }
  )
  list(issues = c(warned, result$issues), error = !is.null(result$issues))
}

expect_results_issues <- function(found, expected, label) {
  if (length(expected)) {
    expect_issues(found, expected, label)
  } else {
    expect_identical(found$issues, list(), label = label)
  }
}

run_results_cases <- function(file) {
  cases <- corpus_cases("results", file)
  expect_gt(length(cases), 0L)
  for (case in cases) {
    path <- function(member) {
      if (!is.null(case[[member]])) corpus_file("results", case[[member]])
    }
    document <- path("document")
    expected <- case[["expected"]]
    found <- capture_results_issues(function() validate_results(document))
    expect_results_issues(found, expected[["issues"]], case$id)
    if (is.null(case[["sidecar"]])) {
      next
    }
    verified <- capture_results_issues(function() {
      validate_results(document, path("sidecar"), path("data"), path("declaration"))
    })
    label <- paste(case$id, "sidecar")
    if (found$error) {
      # An error in the document stops validation before the sidecar.
      expect_identical(expected[["sidecar_issues"]], list(), label = label)
      expect_identical(verified, found, label = label)
    } else {
      # The warning W7090, if any, comes before the issues of the sidecar.
      verified$issues <- verified$issues[seq_along(verified$issues) > length(found$issues)]
      expect_results_issues(verified, expected[["sidecar_issues"]], label)
    }
  }
}

for (file in c("reading.json", "version.json", "structure.json", "rules.json",
               "shareable.json", "registry.json", "stages.json", "sidecar.json",
               "valid.json")) {
  test_that(paste("every case of results", file, "passes"), {
    run_results_cases(file)
  })
}
