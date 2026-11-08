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
