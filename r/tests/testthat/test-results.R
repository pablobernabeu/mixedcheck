# The results object, write_results(), the parts of validate_results() that
# the results corpus cannot reach and the commitments that audit() and
# validation share.

example_key <- paste(sprintf("%02x", 0:31), collapse = "")

results_document <- function(name) {
  read_json_strict(corpus_file("results", name), "data")
}

example_sidecar <- function() {
  list(
    sidecar_version = "0.1.0",
    keys = list(list(created = "2026-11-08T09:05:30Z", key = example_key,
                     key_id = commitment_key_id(example_key))),
    pseudonyms = list()
  )
}

example_results <- function(name = "valid/001.json") {
  new_results(results_document(name), example_sidecar())
}

issue_codes <- function(issues) {
  vapply(issues, function(issue) paste(issue$code, issue$pointer %||% ""), "")
}

errors_of <- function(f) {
  tryCatch({
    f()
    list()
  }, mixedcheck_error = function(e) e$issues)
}

test_that("printing shows the banner of the mode and one line for each finding", {
  shareable <- example_results()
  lines <- capture.output(result <- withVisible(print(shareable)))
  expect_false(result$visible)
  expect_identical(result$value, shareable)
  expect_identical(lines, c(
    paste("Shareable output: the privacy filter has reduced the risk of disclosure,",
          "but this report is not anonymous data."),
    paste("keys.duplicates: consistent. Every row has its own value of the observation key",
          "'school', 'class', 'pupil' and 'wave'."),
    paste("outcome.constant_clusters (factor 'school'): consistent. The outcome varies within",
          "every level of 'school' that has two or more rows."),
    paste("structure.label_incidence (first 'class', second 'school'): consistent. In the design",
          "sample, 'class' has 4 labels and 'school' has 6, which occur in 24 combinations.",
          "Relation from the labels: crossed.")
  ))

  internal <- example_results("valid/005.json")
  lines <- capture.output(print(internal))
  expect_identical(lines[1:2], c(
    paste("INTERNAL: this report holds values that the privacy filter has not checked,",
          "such as small counts and labels. Do not share it."),
    "keys.duplicates: not available (declaration_missing: /observation/key)."
  ))
  expect_length(lines, 4L)

  internal$document$findings <- list()
  expect_identical(capture.output(print(internal))[2L], "No findings.")
  # A scope value is shown after display escaping.
  finding <- list(check = "structure.cluster_sizes", scope = list(factor = "a\tb"),
                  status = list(availability = list(value = "not_available",
                                                    reason = "planned", version = "1.1")))
  expect_identical(finding_line(finding),
                   "structure.cluster_sizes (factor 'a\\u0009b'): not available (planned: 1.1).")
})

test_that("write_results() writes the canonical bytes and the sidecar with the results hash", {
  directory <- tempfile("results-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  results <- example_results()
  path <- file.path(directory, "audit.json")
  sidecar <- file.path(directory, "audit.internal.json")
  hash <- withVisible(write_results(results, path, sidecar))
  expect_false(hash$visible)
  bytes <- readBin(path, "raw", file.size(path))
  expect_identical(bytes, canonical_bytes(results$document, "data"))
  expect_identical(hash$value, hash_file(path))
  # With the registry hash of documents.md, the example there has 5,715
  # canonical bytes and the results file hash that its sidecar records.
  example <- results$document
  example$inputs$registry_hash <-
    "sha256:872491a30d60d598962de6e7b834ab76b2aa65fbab102c6ebaaae6acdc238822"
  example_bytes <- canonical_bytes(example, "data")
  expect_length(example_bytes, 5715L)
  expect_identical(hash_bytes(example_bytes),
                   "sha256:18dbc4b03b51662e1d3111d53fc2b79b0ade3ab52820cd20bd4ae12b7e123d92")
  written <- read_json_strict(sidecar, "data")
  expect_identical(written$results_hash, hash$value)
  expect_identical(written[names(results$sidecar)], results$sidecar)
  expect_identical(readBin(sidecar, "raw", file.size(sidecar)), canonical_bytes(written, "data"))
  expect_silent(validate_results(path, sidecar))

  internal <- example_results("valid/002.json")
  path <- file.path(directory, "audit.internal.json")
  sidecar <- file.path(directory, "keys.internal.json")
  expect_identical(write_results(internal, path, sidecar), hash_file(path))
  expect_silent(validate_results(path, sidecar))
})

test_that("write_results() refuses file names that do not match the document (E7010)", {
  directory <- tempfile("results-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  at <- function(name) file.path(directory, name)
  shareable <- example_results()
  internal <- example_results("valid/002.json")
  message <- function(file, rule) {
    sprintf("The %s must be written to a file whose name %s '.internal.json'.", file, rule)
  }
  expect_identical(errors_of(function() {
    write_results(shareable, at("audit.internal.json"), at("keys.internal.json"))
  }), list(list(code = "E7010",
                 message = message("shareable results document", "does not end in"))))
  expect_identical(errors_of(function() {
    write_results(internal, at("audit.json"), at("keys.internal.json"))
  }), list(list(code = "E7010", message = message("internal results document", "ends in"))))
  for (results in list(shareable, internal)) {
    expect_identical(errors_of(function() {
      path <- at(if (identical(results, shareable)) "audit.json" else "audit.internal.json")
      write_results(results, path, at("keys.json"))
    }), list(list(code = "E7010", message = message("internal sidecar", "ends in"))))
  }
  # Only the name counts, and the suffix is compared exactly.
  expect_identical(errors_of(function() {
    write_results(internal, at("audit.INTERNAL.JSON"), at("keys.internal.json"))
  })[[1L]]$code, "E7010")
  dir.create(at("x.internal.json"))
  expect_identical(errors_of(function() {
    write_results(shareable, file.path(directory, "x.internal.json", "audit.json"),
                  at("keys.internal.json"))
  }), list())
  expect_length(list.files(directory), 2L)
})

test_that("write_results() refuses a commitment key in a shareable document (E1315)", {
  directory <- tempfile("results-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  results <- example_results()
  results$document$inputs$data$analysis_table <- example_sidecar()$keys[[1L]]
  expect_identical(errors_of(function() {
    write_results(results, file.path(directory, "a.json"), file.path(directory, "a.internal.json"))
  }), list(list(
    code = "E1315",
    message = paste("The commitment key at /inputs/data/analysis_table cannot be written to a",
                    "shareable file."),
    pointer = "/inputs/data/analysis_table"
  )))
  expect_length(list.files(directory), 0L)
  nested <- list(list(1), list(b = list(created = 1, key = 2, key_id = 3)))
  expect_identical(commitment_key_pointer(nested), "/1/b")
  expect_null(commitment_key_pointer(list(created = 1, key = 2)))
})

test_that("write_results() gives ordinary errors for arguments of the wrong type", {
  directory <- tempfile("results-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  results <- example_results()
  path <- file.path(directory, "audit.json")
  sidecar <- file.path(directory, "audit.internal.json")
  ordinary <- function(f) {
    problem <- tryCatch(f(), error = function(e) e)
    expect_s3_class(problem, "error")
    expect_false(inherits(problem, "mixedcheck_error"))
  }
  ordinary(function() write_results(results$document, path, sidecar))
  ordinary(function() write_results(results, NA_character_, sidecar))
  ordinary(function() write_results(results, path, c(sidecar, sidecar)))
  ordinary(function() write_results(results, path, 1))
  ordinary(function() {
    write_results(example_results("valid/002.json"), sidecar,
                  file.path(directory, ".", basename(sidecar)))
  })
  # A sidecar in a missing directory: nothing is written, since the document
  # would commit to a key that no file holds.
  ordinary(function() {
    write_results(results, path, file.path(directory, "missing", "audit.internal.json"))
  })
  expect_length(list.files(directory), 0L)
  # A sidecar that cannot be written, here because a directory has its name,
  # takes the document with it.
  dir.create(sidecar)
  ordinary(function() suppressWarnings(write_results(results, path, sidecar)))
  expect_false(file.exists(path))
})

test_that("validate_results() reads a document in memory and a results object", {
  path <- corpus_file("results", "valid/004.json")
  value <- results_document("valid/004.json")
  # The document is indented, so the hash of its canonical bytes differs from
  # that of the file.
  canonical <- hash_bytes(canonical_bytes(value, "data"))
  expect_false(identical(canonical, hash_file(path)))
  sidecar <- c(example_sidecar(), list(results_hash = canonical))
  returned <- withVisible(validate_results(value, sidecar))
  expect_false(returned$visible)
  expect_identical(returned$value, value)
  expect_identical(issue_codes(errors_of(function() validate_results(path, sidecar))),
                   "E1321 /results_hash")

  # A results object is verified against its own sidecar, which holds no
  # results hash, unless a sidecar is given.
  results <- new_results(value, example_sidecar())
  expect_identical(validate_results(results), value)
  expect_silent(validate_results(results, sidecar))
  results$sidecar$keys <- list()
  expect_identical(issue_codes(errors_of(function() validate_results(results))), "E1313 ")
  results$sidecar$keys <- list(example_sidecar()$keys[[1L]], example_sidecar()$keys[[1L]])
  expect_identical(issue_codes(errors_of(function() validate_results(results))),
                   "E7061 /keys/1/key_id")

  # A document in memory that cannot be written in the data profile.
  broken <- value
  formula <- rawToChar(as.raw(c(0x79, 0xE9, 0x20, 0x7E, 0x20, 0x78)))
  Encoding(formula) <- "bytes"
  broken$inputs$model$formula <- formula
  expect_identical(issue_codes(errors_of(function() validate_results(broken))),
                   "E1205 /inputs/model/formula")
})

test_that("validate_results() signals W7090 as a warning and goes on to the sidecar", {
  value <- results_document("valid/001.json")
  value$inputs$registry_hash <- paste0("sha256:", strrep("0", 64))
  warning <- tryCatch(validate_results(value), mixedcheck_warning = function(w) w)
  expect_s3_class(warning, c("mixedcheck_warning", "warning", "condition"), exact = TRUE)
  expect_identical(issue_codes(warning$issues), "W7090 /inputs/registry_hash")
  expect_identical(suppressWarnings(validate_results(value)), value)
})

test_that("validate_results() recomputes commitments from a data frame", {
  document <- corpus_file("results", "sidecar/frame.json")
  sidecar <- corpus_file("results", "sidecar/frame_sidecar.json")
  declaration <- corpus_file("results", "sidecar/declaration.json")
  frame <- read_table(corpus_file("results", "sidecar/reordered.csv"))
  expect_silent(validate_results(document, sidecar, frame, declaration))
  frame$arm[1L] <- if (frame$arm[1L] == "A") "B" else "A"
  expect_identical(issue_codes(errors_of(function() {
    validate_results(document, sidecar, frame, declaration)
  })), "E1314 /inputs/data/analysis_table")
  # A factor is read by its labels and an integer column as numbers.
  frame <- read_table(corpus_file("results", "sidecar/data.csv"))
  frame$arm <- factor(frame$arm, levels = c("B", "A"))
  frame$wave <- as.integer(frame$wave)
  expect_silent(validate_results(document, sidecar, frame, declaration))

  # A document that commits to a data file needs its path.
  file_document <- corpus_file("results", "sidecar/file.json")
  file_sidecar <- corpus_file("results", "sidecar/file_sidecar.json")
  problem <- tryCatch(validate_results(file_document, file_sidecar, frame, declaration),
                      error = function(e) e)
  expect_false(inherits(problem, "mixedcheck_error"))
  expect_match(conditionMessage(problem), "data file")
})

test_that("validate_results() gives ordinary errors for its arguments", {
  document <- corpus_file("results", "sidecar/nokey.json")
  data <- corpus_file("results", "sidecar/data.csv")
  ordinary <- function(f) {
    problem <- tryCatch(f(), error = function(e) e)
    expect_s3_class(problem, "error")
    expect_false(inherits(problem, "mixedcheck_error"))
  }
  ordinary(function() validate_results(1))
  ordinary(function() validate_results(c(document, document)))
  ordinary(function() validate_results(document, sidecar = 1))
  sidecar <- corpus_file("results", "sidecar/nokey_sidecar.json")
  ordinary(function() validate_results(document, sidecar, data = 1))
  ordinary(function() validate_results(document, data = data))
  ordinary(function() validate_results(document, declaration = list(vocabulary = "0.1.0")))
})

test_that("the registry hash is the hash of the vendored compiled registry", {
  path <- system.file("spec", "compiled", "registry.json", package = "mixedcheck")
  expect_identical(registry_hash(), hash_file(path))
  expect_identical(names(registry_entries_by_id()),
                   vapply(read_registry()$entries, function(entry) entry$id, ""))
})

test_that("the quantile rule is exact in integer arithmetic", {
  expect_true(quantile_shown(100, 0.9, 10))
  expect_false(quantile_shown(99, 0.9, 10))
  expect_true(quantile_shown(40, 0.25, 10))
  expect_false(quantile_shown(19, 0.5, 10))
  expect_true(quantile_shown(20, 0.5, 10))
  for (p in list(0, 1, "0", "1")) {
    expect_false(quantile_shown(1e15, p, 1))
  }
  expect_true(quantile_shown(200, "0.05", 10))
  expect_false(quantile_shown(199, "0.05", 10))
  expect_true(quantile_shown(200, "0.95", 10))
  expect_false(quantile_shown(199, 0.95, 10))
  # p = 1e-7: 10^8 values give 10, the minimum count.
  expect_true(quantile_shown(1e8, 1e-7, 10))
  expect_false(quantile_shown(1e8 - 1, 1e-7, 10))
  expect_true(quantile_shown(1e8, "0.0000001", 10))
  # The shortest decimal of the double nearest to 1/3 has 16 digits, so 30
  # values fall short of k = 10, although 30 / 3 is 10 in doubles.
  third <- 1 / 3
  expect_identical(30 * third, 10)
  expect_false(quantile_shown(30, third, 10))
  expect_true(quantile_shown(31, third, 10))
  expect_identical(bn_compare(bn_mul(bn_from_digits("123456789012345678"), bn_normalise(2^52)),
                              bn_from_digits("555999948992357940337780130316288")), 0L)
  expect_identical(bn_compare(bn_from_digits("10000000"), bn_from_digits("9999999")), 1L)
  expect_identical(bn_compare(bn_from_digits("12"), bn_from_digits("13")), -1L)
})

test_that("the analysis table and outcome column commitments match documents.md", {
  declaration <- list(observation = list(key = list("pupil", "wave")),
                      variables = list(post = list(role = "outcome")))
  frame <- data.frame(pupil = c("p2", "p1", "p2", "p1"), wave = c(1, 0, 0, 1),
                      arm = c("B", "A", "B", "A"), post = c(9, 12, NA, 15))
  table <- model_table(frame, NULL)
  outcome <- outcome_column_message(table, declaration, "post")
  expect_identical(rawToChar(outcome), paste0(
    '{"column":"post","key":["pupil","wave"],"rows":',
    '[["p1",0,12],["p1",1,15],["p2",0,null],["p2",1,9]]}'
  ))
  expect_identical(keyed_commitment(outcome, example_key, "outcome_column")$digest,
                   "75cc1f029d23f7ee37f8b3e0f1dc93e2d78b113b88d69f62a617346a6edafe7f")
  analysis <- analysis_table_message(table, declaration, "post")
  expect_length(analysis, 118L)
  expect_identical(keyed_commitment(analysis, example_key, "analysis_table")$digest,
                   "72de9a1b287c8601cdbab959ce1192af4fe02a10030e6bc721928ba52d8b0391")
  # A key that /provenance/inferred points to counts as absent, so the rows
  # keep the order of the table.
  for (pointer in c("/observation", "/observation/key", "/observation/key/1")) {
    inferred <- c(declaration, list(provenance = list(inferred = list(pointer))))
    expect_identical(observation_key_columns(inferred), character(0))
    expect_match(rawToChar(analysis_table_message(table, inferred, "post")),
                 '"key":[],"rows":[["p2",1,"B"],', fixed = TRUE)
  }
  expect_identical(observation_key_columns(c(declaration, list(provenance = list(
    inferred = list("/observation/time")
  )))), c("pupil", "wave"))
  # A column that the table lacks gives no message.
  expect_null(outcome_column_message(table, declaration, "score"))
  expect_null(analysis_table_message(table, list(observation = list(key = list("id"))), NULL))
})

test_that("the analysis table leaves out the response, its trials and declared outcomes", {
  declaration <- list(variables = list(
    hits = list(role = "outcome", measurement = "binomial", trials = "n"),
    rt = list(role = "outcome_derived"),
    age = list(role = "covariate")
  ))
  expect_setequal(outcome_column_keys(declaration, "hits"), c("hits", "rt", "n"))
  expect_setequal(outcome_column_keys(declaration, NULL), c("hits", "rt"))
  expect_setequal(outcome_column_keys(NULL, "y"), "y")
  frame <- data.frame(id = 1:2, hits = c(3, 4), n = c(5, 5), rt = c(1.5, 2), age = c(30, 40),
                      y = c(TRUE, FALSE))
  text <- rawToChar(analysis_table_message(model_table(frame, NULL), declaration, "hits"))
  expect_identical(text, paste0('{"columns":["id","age","y"],"key":[],',
                                '"rows":[[1,30,true],[2,40,false]]}'))
  # The response is compared with the columns after NFC.
  composed <- read_json_strict(charToRaw('"caf\\u00e9"'))
  decomposed <- read_json_strict(charToRaw('"cafe\\u0301"'))
  frame <- data.frame(x = 1, y = 2)
  names(frame) <- c(decomposed, "x")
  text <- rawToChar(analysis_table_message(model_table(frame, NULL), NULL, composed))
  expect_identical(text, '{"columns":["x"],"key":[],"rows":[[2]]}')
})

test_that("commitment messages write values as the data profile and order rows by key bytes", {
  e_acute <- read_json_strict(charToRaw('"\\u00e9"'))
  frame <- data.frame(
    g = c("z", e_acute, "a", "z", NA),
    k = c(2, 1, NaN, -0, Inf),
    v = c(-Inf, 1e21, 0.1, NA, 1.5),
    b = c(TRUE, NA, FALSE, TRUE, FALSE),
    s = c("q\"uote", "tab\t", NA, "back\\slash", "")
  )
  table <- model_table(frame, NULL)
  declaration <- list(observation = list(key = list("g", "k")))
  message <- analysis_table_message(table, declaration, NULL)
  # The rows ordered by the canonical bytes of their key values, which put
  # '"a"', then '"z"', then the two bytes of e acute and then null, and ties
  # broken by the whole row.
  rows <- lapply(seq_len(nrow(frame)), function(i) {
    lapply(frame[i, ], function(value) if (is.na(value) && !is.nan(value)) NULL else value)
  })
  key_bytes <- vapply(rows, function(row) {
    paste(as.character(canonical_bytes(unname(row[c("g", "k")]), "data")), collapse = "")
  }, "")
  row_bytes <- vapply(rows, function(row) {
    paste(as.character(canonical_bytes(unname(row), "data")), collapse = "")
  }, "")
  ordered <- rows[order(key_bytes, row_bytes, method = "radix")]
  expected <- canonical_bytes(list(
    columns = as.list(names(frame)),
    key = list("g", "k"),
    rows = lapply(ordered, unname)
  ), "data")
  expect_identical(message, expected)
  expect_identical(vapply(ordered, function(row) row$g %||% "NULL", ""),
                   c("a", "z", "z", e_acute, "NULL"))
  # Rows without a key keep the order of the table, and a table without
  # rows has none.
  expect_match(rawToChar(analysis_table_message(table, NULL, NULL)),
               '"rows":[["z",2,"-Infinity",true,', fixed = TRUE)
  empty <- model_table(frame[0, ], NULL)
  expect_identical(rawToChar(outcome_column_message(empty, declaration, "v")),
                   '{"column":"v","key":["g","k"],"rows":[]}')
})

test_that("the declared missing values apply to a data frame as the reader applies them", {
  table_block <- list(
    fields = list(
      list(name = "pupil", type = "string", missingValues = list("NA", "")),
      list(name = "score", type = "number", missingValues = list(list(value = "-99"), "nan", "0")),
      list(name = "flag", type = "boolean")
    ),
    missingValues = list("1.0", "x")
  )
  decomposed <- read_json_strict(charToRaw('"na\\u0301"'))
  frame <- data.frame(
    pupil = c("p1", "NA", "", "x"),
    score = c(-99, NaN, -0, 99),
    flag = c(TRUE, FALSE, NA, TRUE),
    other = c(1, 2, 1.0, 3),
    note = factor(c("x", "y", "x", "z"))
  )
  applied <- apply_missing_values(frame, table_block)
  expect_identical(applied$pupil, c("p1", NA, NA, "x"))
  expect_identical(applied$score, c(NA, NA, NA, 99))
  expect_identical(applied$flag, frame$flag)
  expect_identical(applied$other, c(NA, 2, NA, 3))
  expect_identical(applied$note, c(NA, "y", NA, "z"))
  # Strings are compared after NFC, and an empty list declares that no value
  # is missing.
  composed_block <- list(fields = list(list(name = "pupil", missingValues = list(
    read_json_strict(charToRaw('"n\\u00e1"'))
  ))))
  applied <- apply_missing_values(data.frame(pupil = c(decomposed, "b")), composed_block)
  expect_identical(applied$pupil, c(NA, "b"))
  none <- list(fields = list(list(name = "pupil", missingValues = list())))
  expect_identical(apply_missing_values(data.frame(pupil = c("", "b")), none)$pupil, c("", "b"))
  # Without a table block nothing is applied, and the default '' applies to a
  # column without a field.
  expect_identical(run_data(data.frame(a = c("", "b")), NULL)$table$values[[1L]], c("", "b"))
  block <- list(table = list(fields = list()))
  expect_identical(run_data(data.frame(a = c("", "b")), block)$table$values[[1L]], c(NA, "b"))

  # A data frame and the file it was read from give the same table.
  path <- corpus_file("results", "sidecar/sentinel.csv")
  declaration <- validate_declaration(corpus_file("results", "sidecar/declaration_table.json"))
  frame <- read_table(path)
  expect_identical(frame$post[3L], -99)
  from_file <- run_data(path, declaration)
  from_frame <- run_data(frame, declaration)
  expect_identical(from_frame$table, from_file$table)
  expect_identical(from_file$file, readBin(path, "raw", file.size(path)))
  expect_null(from_frame$file)
})

test_that("the commitments of a run verify against its document", {
  document <- read_json_strict(corpus_file("results", "sidecar/file.json"), "data")
  declaration <- validate_declaration(corpus_file("results", "sidecar/declaration.json"))
  run <- run_data(corpus_file("results", "sidecar/data.csv"), declaration)
  members <- c("analysis_table", "data_file")
  expect_identical(data_commitments(run, declaration, "post", example_key)[members],
                   document$inputs$data[members])
  expect_identical(outcome_commitment(run, declaration, "post", example_key),
                   document$access_log$entries[[2L]]$outcome$commitment)
  frame <- run_data(read_table(corpus_file("results", "sidecar/data.csv")), declaration)
  expect_named(data_commitments(frame, declaration, "post", example_key), "analysis_table")
})
