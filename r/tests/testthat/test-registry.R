# The vendored compiled registry: loading, the checks that registry.md (The
# compiled registry) gives the package tests, and the rules enforced in code
# on altered copies.

entry_index <- function(document, id) {
  which(vapply(document$entries, function(entry) entry$id, "") == id)
}

codes_and_pointers <- function(issues) {
  vapply(issues, function(issue) paste(issue$code, issue$pointer %||% ""), "")
}

test_that("read_registry() returns the vendored registry, once read per session", {
  registry <- read_registry()
  expect_named(registry, c("entries", "privacy", "registry_version"))
  expect_identical(registry$registry_version, spec_versions()$registry)
  ids <- vapply(registry$entries, function(entry) entry$id, "")
  expect_gt(length(ids), 0L)
  expect_identical(ids, sort(ids, method = "radix"))
  expect_identical(registry$privacy$min_count, 10)
  expect_identical(read_registry(), registry)
})

test_that("the vendored registry holds its canonical bytes and passes its schema and rules", {
  path <- system.file("spec", "compiled", "registry.json", package = "mixedcheck")
  registry <- read_registry()
  expect_identical(canonical_bytes(registry, "hashable"), readBin(path, "raw", n = file.size(path)))
  expect_identical(finish_issues(schema_issues(registry, "urn:mixedcheck:schema:registry")), list())
  expect_identical(registry_issues(registry), list())
})

test_that("registry_entry() finds an entry by identifier and reports E4001 otherwise", {
  expect_identical(registry_entry("structure.cluster_sizes")$id, "structure.cluster_sizes")
  problem <- tryCatch(registry_entry("structure.no_such_check"), mixedcheck_error = function(e) e)
  expect_identical(problem$issues, list(list(
    code = "E4001", message = "No registry entry has the identifier 'structure.no_such_check'."
  )))
})

test_that("load_registry() checks the manifest, the reader and the version", {
  root <- tempfile("registry-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.copy(system.file("spec", package = "mixedcheck"), root, recursive = TRUE)
  directory <- file.path(root, "spec")
  expect_identical(load_registry(directory), read_registry())

  path <- file.path(directory, "compiled", "registry.json")
  manifest_path <- file.path(directory, "MANIFEST.json")
  manifest <- read_json_strict(manifest_path, "data")
  rewrite <- function(document) {
    bytes <- canonical_bytes(document, "hashable")
    writeBin(bytes, path)
    manifest$files[["compiled/registry.json"]] <- substring(hash_bytes(bytes), 8L)
    writeBin(canonical_bytes(manifest, "data"), manifest_path)
  }
  issue_of_load <- function() {
    tryCatch(load_registry(directory), mixedcheck_error = function(e) e$issues)
  }

  document <- read_registry()
  document$privacy$min_count <- 5
  writeBin(canonical_bytes(document, "hashable"), path)
  expect_identical(issue_of_load(), list(list(
    code = "E1321", message = "The hash at /files/compiled~1registry.json does not match the content it covers.",
    pointer = "/files/compiled~1registry.json"
  )))

  document <- read_registry()
  document$registry_version <- "0.2.0"
  rewrite(document)
  expect_identical(issue_of_load(), list(list(
    code = "E1441",
    message = "Version '0.2.0' at /registry_version is not supported. This release reads version 0.1.x.",
    pointer = "/registry_version"
  )))

  document$registry_version <- 1
  rewrite(document)
  expect_identical(codes_and_pointers(issue_of_load()), "E1401 /registry_version")

  writeBin(charToRaw('{"registry_version": "0.1.0", "x": null}'), path)
  manifest$files[["compiled/registry.json"]] <- substring(hash_file(path), 8L)
  writeBin(canonical_bytes(manifest, "data"), manifest_path)
  expect_identical(codes_and_pointers(issue_of_load()), "E1101 ")
})

test_that("the rules across entries find disorder, duplicates, unknown links and cycles", {
  registry <- read_registry()

  document <- registry
  document$entries[c(1L, 2L)] <- document$entries[c(2L, 1L)]
  expect_identical(codes_and_pointers(registry_issues(document)), "E4017 /entries/1")

  document <- registry
  document$entries[[2L]]$id <- document$entries[[1L]]$id
  found <- codes_and_pointers(registry_issues(document))
  expect_true(all(c("E4003 /entries/1/id", "E4017 /entries/1") %in% found))

  document <- registry
  document$entries[[1L]]$links$requires <- list("structure.no_such_check")
  expect_identical(codes_and_pointers(registry_issues(document)),
                   "E4004 /entries/0/links/requires/0")

  document <- registry
  first <- entry_index(document, "assignment.constant_within_unit")
  second <- entry_index(document, "labels.unicode_forms")
  document$entries[[second]]$links$requires <- list("assignment.constant_within_unit")
  expect_identical(
    codes_and_pointers(registry_issues(document)),
    c(sprintf("E4005 /entries/%d/links/explained_by/0", first - 1L),
      sprintf("E4005 /entries/%d/links/requires/0", second - 1L))
  )
})

test_that("the rules on one entry find each kind of problem", {
  registry <- read_registry()
  at <- function(id) entry_index(registry, id)
  check <- function(document, expected) {
    expect_identical(codes_and_pointers(registry_issues(document)), expected)
  }

  document <- registry
  i <- at("assignment.constant_within_unit")
  prefix <- sprintf("/entries/%d", i - 1L)
  document$entries[[i]]$reads <- c(document$entries[[i]]$reads, list("outcome"))
  document$entries[[i]]$sample <- "analysis"
  document$entries[[i]]$remedies <- c(document$entries[[i]]$remedies, document$entries[[i]]$remedies)
  document$entries[[i]]$availability[[1L]]$parameter <- "no_such_parameter"
  document$entries[[i]]$messages$constant$template <- "{column} {unknown} {unit} {units} {"
  document$entries[[i]]$messages$constant$args$units$digits <- 2
  document$entries[[i]]$messages$constant$args$unit$name <- "no_such_part"
  check(document, paste0("E", c(
    paste0("4004 ", prefix, "/availability/0/parameter"),
    paste0("4008 ", prefix, "/messages/constant/args/level"),
    paste0("4004 ", prefix, "/messages/constant/args/unit/name"),
    paste0("4014 ", prefix, "/messages/constant/args/units"),
    paste0("4007 ", prefix, "/messages/constant/template"),
    paste0("4009 ", prefix, "/messages/constant/template"),
    paste0("4016 ", prefix, "/reads"),
    paste0("4006 ", prefix, "/remedies/1/id"),
    paste0("4016 ", prefix, "/sample")
  )))

  document <- registry
  i <- at("outcome.constant_clusters")
  prefix <- sprintf("/entries/%d", i - 1L)
  document$entries[[i]]$thresholds$any$value <- "1.5"
  document$entries[[i]]$thresholds$many$value <- "0.12345"
  document$entries[[i]]$thresholds$many$proximity <- "0.01"
  document$entries[[i]]$statistics$constant_share$count_class <- "person"
  check(document, c(
    paste0("E4021 ", prefix, "/statistics/constant_share"),
    paste0("E4012 ", prefix, "/thresholds/any/value"),
    paste0("E4013 ", prefix, "/thresholds/many"),
    paste0("E4012 ", prefix, "/thresholds/many/value")
  ))

  document <- registry
  i <- at("design.collinearity")
  prefix <- sprintf("/entries/%d", i - 1L)
  document$entries[[i]]$thresholds$high$validation$value <- "validated"
  # E4010 needs a literature source that has not been read in full; the
  # registry's own source of this threshold has been, so the test marks it unread.
  document$entries[[i]]$thresholds$high$sources[[1L]]$full_text_read <- FALSE
  document$entries[[i]]$decision$rules[[1L]]$finding <- "consequential"
  document$entries[[i]]$decision$rules[[2L]]$thresholds <- list("no_such_threshold")
  document$entries[[i]]$decision$rules[[2L]]$message <- "no_such_message"
  document$entries[[i]]$statistics$flag <- list(definition = "A flag.", kind = "boolean")
  document$entries[[i]]$thresholds$moderate$statistic <- "flag"
  document$entries[[i]]$messages$low$args$gvif$name <- "flag"
  check(document, c(
    paste0("E4004 ", prefix, "/decision/rules/1/message"),
    paste0("E4004 ", prefix, "/decision/rules/1/thresholds/0"),
    paste0("E4015 ", prefix, "/messages/low/args/gvif/name"),
    paste0("E4010 ", prefix, "/thresholds/high/validation"),
    paste0("E4011 ", prefix, "/thresholds/moderate")
  ))
  document$entries[[i]]$thresholds$high$validation$value <- "descriptive"
  check(document, c(
    paste0("E4020 ", prefix, "/decision/rules/0/finding"),
    paste0("E4004 ", prefix, "/decision/rules/1/message"),
    paste0("E4004 ", prefix, "/decision/rules/1/thresholds/0"),
    paste0("E4015 ", prefix, "/messages/low/args/gvif/name"),
    paste0("E4011 ", prefix, "/thresholds/moderate")
  ))
})

test_that("the members that M2 added name what exists, of the kind required", {
  registry <- read_registry()
  i <- entry_index(registry, "structure.id_scope_evidence")
  prefix <- sprintf("/entries/%d", i - 1L)
  check <- function(document, expected) {
    expect_identical(codes_and_pointers(registry_issues(document)), paste0("E", expected))
  }
  # The statistics that a rule reads, the resolution of by_unit counts,
  # quantiles, suppression with other statistics and parts of a total
  # (E4004 and E4024).
  document <- registry
  statistics <- document$entries[[i]]$statistics
  document$entries[[i]]$decision$rules[[1L]]$statistics <- list("attributes", "absent")
  statistics$shared_labels$resolved_by <- list(
    list(name = "factor", source = "scope"),
    list(name = "changing_labels", source = "statistic")
  )
  statistics$changing_labels$resolved_by <- list(list(name = "absent", source = "statistic"))
  statistics$changing_labels$quantile <- list(n = "changing_attribute", p = "0.5")
  statistics$shared_labels$quantile <- list(n = "absent", p = "0.5")
  statistics$changing_share$suppress_with <- list("absent")
  statistics$changing_labels$part_of <- "absent"
  statistics$shared_labels$part_of <- "changing_attribute"
  document$entries[[i]]$statistics <- statistics
  check(document, paste0(c("4004 ", "4004 ", "4024 ", "4004 ", "4004 ", "4024 ", "4004 ",
                           "4004 ", "4024 "), prefix, c(
    "/decision/rules/0/statistics/1",
    "/statistics/changing_labels/part_of",
    "/statistics/changing_labels/quantile/n",
    "/statistics/changing_labels/resolved_by/0/name",
    "/statistics/changing_share/suppress_with/0",
    "/statistics/shared_labels/part_of",
    "/statistics/shared_labels/quantile/n",
    "/statistics/shared_labels/resolved_by/0/name",
    "/statistics/shared_labels/resolved_by/1/name"
  )))

  # Parts and totals of another count class (E4024), beside the ratio of
  # two counts of different classes (E4021), and a noun for an argument that
  # does not show a count (E4024).
  document <- registry
  document$entries[[i]]$statistics$shared_labels$count_class <- "person"
  document$entries[[i]]$messages$no_change$args$attributes$noun <- list("attribute", "attributes")
  check(document, paste0(c("4024 ", "4024 ", "4021 ", "4024 "), prefix, c(
    "/messages/no_change/args/attributes/noun",
    "/statistics/changing_labels/part_of",
    "/statistics/changing_share",
    "/statistics/shared_labels/part_of"
  )))
})

test_that("a message that renders an unwritten statistic has a fallback (E4023)", {
  registry <- read_registry()
  i <- entry_index(registry, "structure.id_scope_evidence")
  prefix <- sprintf("/entries/%d", i - 1L)
  document <- registry
  messages <- document$entries[[i]]$messages
  messages$some_change$fallback <- NULL
  messages$no_change$fallback <- "None of the {shared} labels changes. {nope} }"
  messages$no_attribute$fallback <- "No column of {labels_column} is constant."
  document$entries[[i]]$messages <- messages
  expect_identical(codes_and_pointers(registry_issues(document)), paste0(
    c("E4023 ", "E4007 ", "E4009 ", "E4023 "), prefix,
    c("/messages/no_change", "/messages/no_change/fallback", "/messages/no_change/fallback",
      "/messages/some_change")
  ))

  # A count of class non_person can be rendered without a fallback, whereas
  # one that measures a quantity, is internal_only or is suppressed with
  # another cannot.
  j <- entry_index(registry, "outcome.constant_clusters")
  document <- registry
  multi <- document$entries[[j]]$statistics$multi_row_levels
  expect_false(statistic_can_be_unwritten(list(kind = "count", count_class = "non_person")))
  expect_true(statistic_can_be_unwritten(list(kind = "count", count_class = "non_person",
                                              measures = "term_levels")))
  expect_true(statistic_can_be_unwritten(list(kind = "count", count_class = "non_person",
                                              measures = "table_term_levels")))
  expect_true(statistic_can_be_unwritten(list(kind = "count", count_class = "by_unit")))
  expect_true(statistic_can_be_unwritten(list(kind = "names", internal_only = TRUE)))
  expect_true(statistic_can_be_unwritten(list(kind = "names", suppress_with = list("x"))))
  expect_false(statistic_can_be_unwritten(list(kind = "category", values = list("a", "b"))))
  expect_identical(multi$count_class, "by_unit")
})

test_that("the parameter agreement has one value in every entry that has it (E4022)", {
  registry <- read_registry()
  holders <- which(vapply(registry$entries, function(entry) {
    !is.null(entry$parameters$agreement)
  }, NA))
  expect_gt(length(holders), 1L)
  document <- registry
  document$entries[[holders[2L]]]$parameters$agreement$value <- "0.95"
  first <- registry$entries[[holders[1L]]]$parameters$agreement$value
  pointer <- sprintf("/entries/%d/parameters/agreement/value", holders[2L] - 1L)
  expect_identical(registry_issues(document), list(list(
    code = "E4022",
    message = sprintf(paste("The parameter at %s must have the value '%s' that other entries",
                            "give the parameter of the same name."), pointer, first),
    pointer = pointer
  )))
})

test_that("the schema checks the members that no rule in code covers", {
  registry <- read_registry()
  schema_codes <- function(document) {
    codes_and_pointers(finish_issues(schema_issues(document, "urn:mixedcheck:schema:registry")))
  }
  i <- entry_index(registry, "outcome.separation")
  j <- entry_index(registry, "structure.cluster_sizes")
  k <- entry_index(registry, "outcome.minority_events")
  document <- registry
  # proximity_factor is a decimal above 1, internal_only a boolean, measures
  # one of its values and only for counts, and the scope one of the scopes.
  document$entries[[i]]$parameters$separation_tolerance$proximity_factor <- "1"
  document$entries[[i]]$statistics$margin$internal_only <- "yes"
  document$entries[[j]]$statistics$rows$measures <- "rows"
  document$entries[[j]]$statistics$effective_size$measures <- "design_rows"
  document$entries[[k]]$scope <- "grouping_factor_or_models"
  found <- schema_codes(document)
  prefix <- function(index) sprintf("/entries/%d", index - 1L)
  expect_true(all(c(
    paste0("E1406 ", prefix(i), "/parameters/separation_tolerance/proximity_factor"),
    paste0("E1401 ", prefix(i), "/statistics/margin/internal_only"),
    paste0("E1405 ", prefix(j), "/statistics/rows/measures"),
    paste0("E1404 ", prefix(j), "/statistics/effective_size"),
    paste0("E1405 ", prefix(k), "/scope")
  ) %in% found))
})

test_that("internal_only and suppress_with make a statistic unwritten", {
  registry <- read_registry()
  i <- entry_index(registry, "outcome.separation")
  prefix <- sprintf("/entries/%d", i - 1L)
  # A list of names can be rendered without a fallback unless it is
  # internal_only or suppressed with another statistic (E4023).
  document <- registry
  document$entries[[i]]$messages$none <- list(
    args = list(columns = list(name = "columns_involved", source = "statistic")),
    template = "The fixed effects do not separate the events, through {columns}."
  )
  expect_identical(codes_and_pointers(registry_issues(document)),
                   paste0("E4023 ", prefix, "/messages/none"))
  document$entries[[i]]$statistics$columns_involved$internal_only <- NULL
  expect_identical(registry_issues(document), list())
  document$entries[[i]]$statistics$columns_involved$suppress_with <- list("events")
  expect_identical(codes_and_pointers(registry_issues(document)),
                   paste0("E4023 ", prefix, "/messages/none"))
})

test_that("the scope grouping_factor_or_model has the part factor and no other", {
  registry <- read_registry()
  j <- entry_index(registry, "outcome.zero_shares")
  document <- registry
  expect_identical(document$entries[[j]]$scope, "grouping_factor_or_model")
  document$entries[[j]]$messages$zeros$args$factor$name <- "term"
  document$entries[[j]]$statistics$levels$resolved_by[[1L]] <- list(name = "unit", source = "scope")
  expect_identical(codes_and_pointers(registry_issues(document)), paste0("E4004 ", sprintf(
    "/entries/%d", j - 1L
  ), c("/messages/zeros/args/factor/name", "/statistics/levels/resolved_by/0/name")))
})
