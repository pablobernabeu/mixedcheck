# The hash and HMAC corpora: SHA-256 of bytes, files and sections of
# documents, HMAC-SHA-256 with the test cases of RFC 4231, key identifiers and
# keyed commitments (fixtures/conformance/hash/ and hmac/).

message_bytes <- function(case) {
  if (!is.null(case[["message_hex"]])) hex_raw(case[["message_hex"]]) else utf8_bytes(case[["message"]])
}

test_that("every case of hash sha256.json passes in memory and as a file", {
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  for (case in corpus_cases("hash", "sha256.json")) {
    bytes <- if (!is.null(case[["input_hex"]])) hex_raw(case[["input_hex"]]) else utf8_bytes(case[["input"]])
    if (!is.null(case[["repeat"]])) {
      bytes <- rep(bytes, times = case[["repeat"]])
    }
    expect_same(hash_bytes(bytes), case[["expected"]][["sha256"]], label = case$id)
    writeBin(bytes, path)
    expect_same(hash_file(path), case[["expected"]][["sha256"]], label = case$id)
  }
})

test_that("every case of hash sections.json passes", {
  for (case in corpus_cases("hash", "sections.json")) {
    document <- read_json_strict(utf8_bytes(case[["input"]]), "hashable")
    section <- mixedcheck:::json_pointer_get(document, case[["pointer"]])
    bytes <- canonical_bytes(section, "hashable")
    expect_same(bytes, utf8_bytes(case[["expected"]][["canonical"]]), label = case$id)
    expect_same(canonical_hash(section, "hashable"), case[["expected"]][["sha256"]], label = case$id)
  }
})

test_that("every case of hmac rfc4231.json passes", {
  for (case in corpus_cases("hmac", "rfc4231.json")) {
    digest <- mixedcheck:::hmac_sha256(hex_raw(case[["key_hex"]]), message_bytes(case))
    if (!is.null(case[["truncate"]])) {
      digest <- substr(digest, 1L, 2L * case[["truncate"]])
    }
    expect_same(digest, case[["expected"]][["digest"]], label = case$id)
  }
})

test_that("every case of hmac commitments.json passes", {
  for (case in corpus_cases("hmac", "commitments.json")) {
    expected <- case[["expected"]]
    if (!is.null(case[["covers"]])) {
      commitment <- keyed_commitment(message_bytes(case), case[["key"]], case[["covers"]])
      expect_same(commitment, expected[["commitment"]], label = case$id)
    } else if (!is.null(expected[["issue"]])) {
      result <- capture_issues(function() commitment_key_id(case[["key"]]))
      expect_issue(result, expected[["issue"]], case$id)
    } else {
      expect_same(commitment_key_id(case[["key"]]), expected[["key_id"]], label = case$id)
    }
  }
})
