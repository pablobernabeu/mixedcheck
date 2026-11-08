test_that("spec_versions() returns the versions in the vendored versions.json", {
  versions <- spec_versions()
  expect_type(versions, "list")
  expect_named(versions, c("registry", "schemas", "canonicaliser"))
  for (version in versions) {
    expect_type(version, "character")
    expect_length(version, 1L)
  }
  path <- system.file("spec", "versions.json", package = "mixedcheck")
  expect_identical(versions, jsonlite::read_json(path, simplifyVector = FALSE))
})

test_that("read_spec_versions() rejects anything but an object of strings", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  for (text in c('{"registry": 1}', '{"registry": null}', '{"registry": ["0.1.0"]}',
                 '["0.1.0"]', '"0.1.0"', "{}", '{"registry": "0.1.0", "registry": "0.2.0"}',
                 "{")) {
    writeLines(text, path)
    expect_error(read_spec_versions(path), "must hold a JSON object whose values are strings")
  }
})

test_that("the installed vendored files match their MANIFEST.json", {
  spec <- system.file("spec", package = "mixedcheck")
  expect_true(nzchar(spec))
  expect_true(file.exists(file.path(spec, "MANIFEST.json")))
  for (name in c("spec", "fixtures")) {
    directory <- system.file(name, package = "mixedcheck")
    if (nzchar(directory)) {
      expect_identical(vendored_problems(directory), character(0), label = name)
    }
  }
})

test_that("vendored_problems() names a changed, missing or unlisted file", {
  root <- tempfile("vendored-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.copy(system.file("spec", package = "mixedcheck"), root, recursive = TRUE)
  directory <- file.path(root, "spec")
  expect_identical(vendored_problems(directory), character(0))

  writeBin(charToRaw("extra\n"), file.path(directory, "extra.txt"))
  expect_identical(vendored_problems(directory), "extra.txt: not listed in MANIFEST.json")
  unlink(file.path(directory, "extra.txt"))

  versions <- file.path(directory, "versions.json")
  original <- readBin(versions, "raw", n = file.size(versions))
  # The same text with CRLF line endings, as a Git checkout with line-ending
  # conversion would write it.
  crlf <- gsub("\n", "\r\n", rawToChar(original), fixed = TRUE)
  writeBin(charToRaw(crlf), versions)
  expect_identical(
    vendored_problems(directory),
    "versions.json: SHA-256 differs from MANIFEST.json"
  )

  unlink(versions)
  expect_identical(vendored_problems(directory), "versions.json: missing")

  unlink(file.path(directory, "MANIFEST.json"))
  expect_identical(vendored_problems(directory), "MANIFEST.json: missing")
})
