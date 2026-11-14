# The pathology zoo: every fixture and matched negative runs through audit()
# in internal and in shareable mode with the commitment key 00 01 02 ... 1F
# and MIXEDCHECK_TIME set to 0, and its findings are compared with its
# expected findings by the rules of fixtures/zoo/README.md (Comparison). The
# fixtures are read from the installed copy, or from the directory that
# MIXEDCHECK_ZOO_DIR names. CRAN runs internal mode only, and CI and the
# parity harness run both modes.

zoo_directories <- zoo_test_directories()

test_that("the zoo has directories to test", {
  expect_gt(length(zoo_directories), 0L)
})

for (zoo_id in names(zoo_directories)) {
  local({
    id <- zoo_id
    directory <- zoo_directories[[id]]
    test_that(paste(id, "gives its expected findings in internal mode"), {
      fixture <- zoo_read(directory)
      expect_identical(fixture$id, id)
      expect_zoo_findings(zoo_run(fixture, "internal"), fixture$expected, "internal", id)
    })
    test_that(paste(id, "gives its expected findings in shareable mode"), {
      skip_on_cran()
      fixture <- zoo_read(directory)
      expect_zoo_findings(zoo_run(fixture, "shareable"), fixture$expected, "shareable", id)
    })
  })
}

test_that("the comparison reports each kind of difference", {
  expect_true("Z01" %in% names(zoo_directories))
  fixture <- zoo_read(zoo_directories[["Z01"]])
  result <- zoo_run(fixture, "internal")
  expected <- fixture$expected
  expect_identical(zoo_differences(result, expected, "internal"), character(0))
  at <- function(check) which(vapply(expected$findings, function(f) f$check, "") == check)[1L]
  incidence <- at("structure.label_incidence")
  where <- paste0("/findings/", incidence - 1L)

  changed <- expected
  changed$findings[[incidence]]$statistics$levels_first$value <- 4
  expect_match(zoo_differences(result, changed, "internal"),
               paste0(where, "/statistics/levels_first: 3 and 4"), fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]]$statistics$levels_first$count_class <- "person"
  expect_match(zoo_differences(result, changed, "internal"), "count class", fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]]$statistics$composite <- NULL
  expect_match(zoo_differences(result, changed, "internal"),
               paste0(where, "/statistics/composite: false and nothing"), fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]]$statistics$composite <- list(absent = TRUE)
  expect_match(zoo_differences(result, changed, "internal"), "false and absent", fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]]$status <- list(finding = "consistent")
  expect_match(zoo_differences(result, changed, "internal"), paste0(where, "/status"),
               fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]]$message <- "relation"
  expect_match(zoo_differences(result, changed, "internal"), paste0(where, "/message"),
               fixed = TRUE)
  changed <- expected
  changed$findings[[incidence]] <- NULL
  expect_match(zoo_differences(result, changed, "internal"), "beyond the expectation",
               fixed = TRUE)
  changed <- expected
  changed$samples$design$distinct <- 239
  expect_match(zoo_differences(result, changed, "internal"), "/support/contributors",
               fixed = TRUE)

  gram <- at("identifiability.gram_rank")
  value <- expected$findings[[gram]]$statistics$smallest_eigenvalue$value
  changed <- expected
  changed$findings[[gram]]$statistics$smallest_eigenvalue <- list(value = value * (1 + 1e-6))
  expect_match(zoo_differences(result, changed, "internal"), "smallest_eigenvalue",
               fixed = TRUE)
  changed$findings[[gram]]$statistics$smallest_eigenvalue <- list(interval = list(0.78, 0.79))
  expect_identical(zoo_differences(result, changed, "internal"), character(0))
  changed$findings[[gram]]$statistics$smallest_eigenvalue <- list(interval = list(0.8, 0.9))
  expect_match(zoo_differences(result, changed, "internal"), "the interval", fixed = TRUE)
  changed <- expected
  changed$findings[[gram]]$statistics$smallest_eigenvalue <- NULL
  expect_identical(zoo_differences(result, changed, "internal"), character(0))

  changed <- expected
  changed$findings <- NULL
  changed$issue <- list(code = "E6069", message = "A message.")
  expect_match(zoo_differences(result, changed, "internal"), "/issue", fixed = TRUE)
})
