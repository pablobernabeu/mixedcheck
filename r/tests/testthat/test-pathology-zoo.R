# The accessor of the pathology zoo, pathology_zoo(), on the installed copy:
# the listing and its column types, each error, the elements of a fixture and
# the types of its data, the comparison with MANIFEST.json and the parsing and
# locale hazards that Z18, Z19 and Z20 plant.

test_that("the listing has the columns and types of every package", {
  zoo <- pathology_zoo()
  expect_named(zoo, c("id", "name", "title", "role", "matched", "tier", "rows", "domain",
                      "deferred"))
  expect_identical(vapply(zoo, function(column) class(column)[1L], ""),
                   c(id = "character", name = "character", title = "character",
                     role = "character", matched = "character", tier = "character",
                     rows = "integer", domain = "character", deferred = "logical"))
  expect_identical(nrow(zoo), 60L)
  expect_identical(zoo$id, sort(zoo$id, method = "radix"))
  expect_identical(row.names(zoo), as.character(seq_len(nrow(zoo))))
  first <- zoo[zoo$id == "Z01", ]
  expect_identical(
    as.list(first),
    list(id = "Z01", name = "reused-class-labels", title = "Reused class labels across schools",
         role = "fixture", matched = "Z01N", tier = "T0", rows = 240L, domain = "education",
         deferred = FALSE)
  )
  expect_true(all(zoo$matched %in% zoo$id))
})

test_that("a fixture has its elements in order, read with its declaration", {
  fixture <- pathology_zoo("Z01")
  expect_named(fixture, c("id", "name", "title", "role", "matched", "tier", "data",
                          "declaration", "formula", "arguments", "expected"))
  expect_identical(fixture[c("id", "name", "role", "matched", "tier")],
                   list(id = "Z01", name = "reused-class-labels", role = "fixture",
                        matched = "Z01N", tier = "T0"))
  expect_identical(fixture$formula, "y ~ 1 + (1 | school) + (1 | class)")
  expect_identical(fixture$arguments, list(outcome_access = "T0"))
  expect_identical(fixture$expected$id, "Z01")
  expect_identical(nrow(fixture$data), 240L)
  directory <- system.file("fixtures", "zoo", "Z01-reused-class-labels", package = "mixedcheck")
  expect_identical(fixture$declaration,
                   validate_declaration(file.path(directory, "declaration.json")))
})

test_that("the data of every fixture have the types of its declared fields", {
  zoo <- pathology_zoo()
  tests <- list(string = is.character, date = is.character, datetime = is.character,
                integer = is.double, number = is.double, boolean = is.logical)
  arguments <- list(T0 = "outcome_access", T1 = c("outcome_access", "reason"),
                    T2 = c("outcome_access", "reason", "exploratory"))
  for (id in zoo$id) {
    fixture <- pathology_zoo(id)
    fields <- fixture$declaration$table$fields
    declared <- vapply(fields, function(field) {
      if (is.null(field$type)) "string" else field$type
    }, "")
    names(declared) <- vapply(fields, function(field) field$name, "")
    expect_identical(attr(fixture$data, "types"), declared, label = id)
    expect_identical(names(fixture$data), names(declared), label = id)
    for (name in names(declared)) {
      expect_true(tests[[declared[[name]]]](fixture$data[[name]]), label = paste(id, name))
    }
    expect_identical(nrow(fixture$data), zoo$rows[zoo$id == id], label = id)
    expect_named(fixture$arguments, arguments[[fixture$tier]], label = id)
  }
})

test_that("an argument that is not one identifier is an error", {
  message <- "'fixture' must be NULL or one identifier, such as 'Z01'."
  for (fixture in list(1, c("Z01", "Z01N"), NA_character_, character(0), list("Z01"))) {
    expect_error(pathology_zoo(fixture), message, fixed = TRUE)
  }
  expect_error(pathology_zoo("Z99"),
               "'Z99' is not an identifier of the pathology zoo. pathology_zoo() lists them.",
               fixed = TRUE)
  expect_error(pathology_zoo("z01"), "'z01' is not an identifier", fixed = TRUE)
})

test_that("an installed file that is missing or differs from MANIFEST.json is an error", {
  copy <- tempfile("zoo-copy-")
  on.exit(unlink(copy, recursive = TRUE), add = TRUE)
  dir.create(copy)
  file.copy(system.file("fixtures", package = "mixedcheck"), copy, recursive = TRUE)
  root <- file.path(copy, "fixtures")
  expect_identical(zoo_fixture("Z01", root)$id, "Z01")
  data <- file.path(root, "zoo", "Z01-reused-class-labels", "data.csv")
  cat("S01,1,P241,0.00\n", file = data, append = TRUE)
  expect_error(zoo_fixture("Z01", root),
               paste("'fixtures/zoo/Z01-reused-class-labels/data.csv' differs from the",
                     "MANIFEST.json installed with the package."),
               fixed = TRUE)
  expect_identical(zoo_fixture("Z01N", root)$id, "Z01N")
  unlink(file.path(root, "zoo", "Z01N-unique-class-labels", "formula.txt"))
  expect_error(zoo_fixture("Z01N", root),
               paste("'fixtures/zoo/Z01N-unique-class-labels/formula.txt' is missing from the",
                     "installed package."),
               fixed = TRUE)
  index <- file.path(root, "zoo", "index.json")
  writeBin(c(readBin(index, "raw", file.size(index)), as.raw(10L)), index)
  expect_error(zoo_fixture(NULL, root),
               paste("'fixtures/zoo/index.json' differs from the MANIFEST.json installed with",
                     "the package."),
               fixed = TRUE)
  unlink(file.path(root, "MANIFEST.json"))
  expect_error(zoo_fixture(NULL, root),
               "'fixtures/MANIFEST.json' is missing from the installed package.", fixed = TRUE)
})

test_that("Z18 keeps the labels that the CSV quotes", {
  fixture <- pathology_zoo("Z18")
  expect_true(all(c("1,2", "\"3\"", "1:2", "A:1") %in%
                    c(fixture$data$class, fixture$data$school)))
  bytes <- readBin(system.file("fixtures", "zoo", "Z18-composite-id-collision", "data.csv",
                               package = "mixedcheck"), "raw", 1e5)
  text <- rawToChar(bytes)
  expect_true(grepl("\"1,2\"", text, fixed = TRUE))
  expect_true(grepl("\"\"\"3\"\"\"", text, fixed = TRUE))
})

test_that("Z19 reads its CR LF records and its labelled sentinels as missing values", {
  fixture <- pathology_zoo("Z19")
  path <- system.file("fixtures", "zoo", "Z19-sentinel-codes", "data.csv", package = "mixedcheck")
  bytes <- readBin(path, "raw", file.size(path))
  lf <- which(bytes == as.raw(10L))
  expect_length(lf, 61L)
  expect_true(all(bytes[lf - 1L] == as.raw(13L)))
  expect_identical(fixture$data$pupil[is.na(fixture$data$pre)],
                   c("P02", "P09", "P13", "P18", "P24", "P37", "P46"))
  expect_false(any(fixture$data$pre %in% -99, na.rm = TRUE))
  expect_identical(sort(unique(fixture$data$group)), c(1, 2))
})

test_that("Z20 keeps its decomposed labels under the C locale", {
  old <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  Sys.setlocale("LC_CTYPE", "C")
  fixture <- pathology_zoo("Z20")
  subjects <- unique(fixture$data$Subject)
  jose <- intToUtf8(c(74L, 111L, 115L, 101L, 769L))
  zoe <- intToUtf8(c(90L, 111L, 101L, 776L))
  expect_true(all(c(jose, zoe, intToUtf8(c(74L, 111L, 115L, 233L)), " s1") %in% subjects))
  expect_true(all(Encoding(subjects[!grepl("^[ -~]*$", subjects, useBytes = TRUE)]) == "UTF-8"))
})

test_that("Z20 gives the same findings whatever the collation", {
  old <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", old), add = TRUE)
  fixture <- pathology_zoo("Z20")
  run <- function() {
    results <- zoo_run(fixture, "internal")
    canonical_bytes(results$value$document$findings, "data")
  }
  Sys.setlocale("LC_COLLATE", "C")
  in_c <- run()
  skip_if(!nzchar(suppressWarnings(Sys.setlocale("LC_COLLATE", "en_US.UTF-8"))),
          "the system has no locale en_US.UTF-8")
  expect_identical(run(), in_c)
})
