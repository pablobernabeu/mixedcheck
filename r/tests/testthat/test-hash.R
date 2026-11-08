# Targeted tests of hashing, HMAC, commitment keys and keyed commitments,
# beyond the cases of the hash and HMAC corpora.

issue_code <- function(expr) {
  tryCatch({
    force(expr)
    NA_character_
  }, mixedcheck_error = function(e) e$issues[[1L]]$code)
}

test_that("hash_file() reports missing and unreadable files", {
  expect_identical(issue_code(hash_file(file.path(tempdir(), "mixedcheck-no-file"))), "E1001")
  expect_identical(issue_code(hash_file(tempdir())), "E1002")
  expect_error(hash_file(1), "file path")
  expect_error(hash_bytes("abc"), "raw vector")
})

test_that("the hash of a value covers its canonical bytes", {
  value <- list(title = "study", n = list(1, 2.5))
  expect_identical(canonical_hash(value, "hashable"),
                   hash_bytes(canonical_bytes(value, "hashable")))
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  writeBin(canonical_bytes(value, "hashable"), path)
  expect_identical(hash_file(path), canonical_hash(value, "hashable"))
})

test_that("HMAC-SHA-256 handles keys around the block size", {
  hmac <- mixedcheck:::hmac_sha256
  message <- charToRaw("message")
  # A key longer than 64 bytes is replaced by its SHA-256 digest first.
  long_key <- as.raw(rep(0xAA, 131L))
  digest_key <- mixedcheck:::hex_to_raw(cli::hash_raw_sha256(long_key))
  expect_identical(hmac(long_key, message), hmac(digest_key, message))
  # A key of up to 64 bytes is padded with zeros.
  expect_identical(hmac(as.raw(1:10), message), hmac(c(as.raw(1:10), raw(54L)), message))
  expect_false(identical(hmac(as.raw(rep(1, 64L)), message), hmac(as.raw(rep(1, 65L)), message)))
})

test_that("new_commitment_key() creates a key from the system and leaves R's generator alone", {
  skip_on_os("windows")
  set.seed(1)
  before <- .Random.seed
  key <- new_commitment_key()
  expect_identical(.Random.seed, before)
  expect_named(key, c("created", "key", "key_id"))
  expect_match(key$created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  expect_match(key$key, "^[0-9a-f]{64}$")
  expect_identical(key$key_id, commitment_key_id(key$key))
  expect_false(identical(new_commitment_key()$key, key$key))
})

test_that("commitments refuse keys of the wrong form", {
  expect_identical(issue_code(commitment_key_id(NA_character_)), "E1311")
  expect_identical(issue_code(commitment_key_id(c("a", "b"))), "E1311")
  expect_identical(issue_code(commitment_key_id(paste(rep("0g", 32), collapse = ""))), "E1311")
  key <- paste(rep("0f", 32), collapse = "")
  expect_identical(issue_code(keyed_commitment(raw(1), toupper(key))), "E1311")
  expect_error(keyed_commitment("text", key), "raw vector")
  expect_error(keyed_commitment(raw(1), key, "table"))
  expect_error(keyed_commitment(raw(1), key, "out"),
               "'covers' must be 'data_file', 'analysis_table' or 'outcome_column'.", fixed = TRUE)
  commitment <- keyed_commitment(charToRaw("abc"), key)
  expect_identical(commitment$covers, "data_file")
  expect_identical(commitment$key_id, commitment_key_id(key))
  expect_identical(commitment$digest, mixedcheck:::hmac_sha256(mixedcheck:::hex_to_raw(key),
                                                               charToRaw("abc")))
})

test_that("verification finds the key and compares the digest", {
  verify <- mixedcheck:::verify_commitment
  key <- paste(rep("0f", 32), collapse = "")
  other <- paste(rep("1e", 32), collapse = "")
  keys <- list(
    list(created = "2026-11-08T12:00:00Z", key = other, key_id = commitment_key_id(other)),
    list(created = "2026-11-08T12:00:00Z", key = key, key_id = commitment_key_id(key))
  )
  commitment <- keyed_commitment(charToRaw("abc"), key, "outcome_column")
  expect_true(verify(commitment, charToRaw("abc"), keys))
  condition <- tryCatch(verify(commitment, charToRaw("abd"), keys, "/access/0/commitment"),
                        mixedcheck_error = function(e) e$issues[[1L]])
  expect_identical(condition, list(code = "E1314",
                                   message = "The data do not match the commitment at /access/0/commitment.",
                                   pointer = "/access/0/commitment"))
  condition <- tryCatch(verify(commitment, charToRaw("abc"), keys[1L]),
                        mixedcheck_error = function(e) e$issues[[1L]])
  expect_identical(condition$code, "E1313")
  expect_identical(condition$message,
                   sprintf("No commitment key with the identifier '%s' was found.",
                           commitment_key_id(key)))
})

test_that("JSON Pointers lead to sections of a document", {
  get <- mixedcheck:::json_pointer_get
  document <- read_json_strict(charToRaw('{"a/b":{"m~n":[1,{"k":2}]},"c":[]}'), "plain")
  expect_identical(get(document, ""), document)
  expect_identical(get(document, "/a~1b/m~0n/0"), 1)
  expect_identical(get(document, "/c"), list())
  expect_error(get(document, "/a~1b/m~0n/2"), "does not lead to a value")
  expect_error(get(document, "/a~1b/m~0n/01"), "does not lead to a value")
  expect_error(get(document, "/x"), "does not lead to a value")
  expect_error(get(document, "a"), "start with '/'")
})
