# SHA-256 hashes, HMAC-SHA-256 and keyed commitments (docs/spec/conventions.md,
# Hashes and Keyed commitments). SHA-256 comes from cli, since base R gains it
# only in 4.5.0, and HMAC is built on it by RFC 2104.

#' SHA-256 hashes of bytes and files
#'
#' `hash_bytes()` hashes bytes held in memory and `hash_file()` the bytes of a
#' file as stored. Both write the hash as documents write it: 'sha256:'
#' followed by the 64 lower-case hexadecimal digits of the SHA-256 digest.
#' A character string is never hashed directly, because its bytes depend on
#' its encoding. Use [canonical_hash()] for the hash of a value.
#'
#' @param x A raw vector.
#' @param path The path of a file.
#' @return A character string.
#' @section Errors: `hash_file()` signals an error of class `mixedcheck_error`
#'   with the code E1001 when the file does not exist and E1002 when it cannot
#'   be read.
#' @export
#' @examples
#' hash_bytes(charToRaw("abc"))
#'
#' path <- tempfile()
#' writeBin(charToRaw("abc"), path)
#' hash_file(path)
#' unlink(path)
hash_bytes <- function(x) {
  if (!is.raw(x)) {
    stop("'x' must be a raw vector.", call. = FALSE)
  }
  paste0("sha256:", cli::hash_raw_sha256(x))
}

#' @rdname hash_bytes
#' @export
hash_file <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("'path' must be a file path.", call. = FALSE)
  }
  if (!file.exists(path)) {
    raise_issue("E1001")
  }
  if (dir.exists(path) || file.access(path, 4L) != 0L) {
    raise_issue("E1002")
  }
  paste0("sha256:", cli::hash_file_sha256(path))
}

# The bytes written as lower-case hexadecimal digits, two to a byte.
hex_to_raw <- function(hex) {
  count <- nchar(hex)
  if (count == 0L) {
    return(raw(0))
  }
  starts <- seq.int(1L, count, by = 2L)
  as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
}

# HMAC-SHA-256 of a message under a key, both raw vectors, by RFC 2104 with
# a block size of 64 bytes. Returns the digest as 64 lower-case hexadecimal
# digits.
hmac_sha256 <- function(key, message) {
  if (length(key) > 64L) {
    key <- hex_to_raw(cli::hash_raw_sha256(key))
  }
  padded <- c(key, raw(64L - length(key)))
  inner <- hex_to_raw(cli::hash_raw_sha256(c(xor(padded, as.raw(rep(0x36L, 64L))), message)))
  cli::hash_raw_sha256(c(xor(padded, as.raw(rep(0x5CL, 64L))), inner))
}

# The 32 bytes of a commitment key supplied as 64 lower-case hexadecimal
# digits, or E1311.
commitment_key_bytes <- function(key) {
  if (!is.character(key) || length(key) != 1L || is.na(key) ||
      !grepl("^[0-9a-f]{64}$", key, useBytes = TRUE)) {
    raise_issue("E1311")
  }
  hex_to_raw(key)
}

#' Commitment keys
#'
#' A commitment key is 32 bytes, written as 64 lower-case hexadecimal digits.
#' `new_commitment_key()` creates one from a cryptographically secure source
#' of random bytes, never from R's random number generator, whose state it
#' leaves unchanged: the operating system's generator through /dev/urandom on
#' Unix-alikes and, where /dev/urandom does not exist, as on Windows, or
#' cannot be read, `openssl::rand_bytes()` when the package openssl is
#' installed.
#' `commitment_key_id()` returns the identifier of a key, the first 16
#' hexadecimal digits of the SHA-256 digest of its 32 bytes, by which a
#' verifier finds the key. Keys belong in the internal sidecar of a results
#' document and never in a shareable file.
#'
#' @param key A commitment key, as 64 lower-case hexadecimal digits.
#' @return `new_commitment_key()` returns a list with the members `created`,
#'   the UTC time of creation, `key` and `key_id`, the form in which the
#'   internal sidecar stores a key. The time is that of the environment
#'   variable MIXEDCHECK_TIME when it is set, as for [audit()].
#'   `commitment_key_id()` returns a character string.
#' @section Errors: A key of another form gives an error of class
#'   `mixedcheck_error` with the code E1311. When /dev/urandom cannot be read
#'   and the package openssl is not installed, no secure source is available, so
#'   `new_commitment_key()` gives the code E1312, and a key must be supplied.
#'   A value of MIXEDCHECK_TIME other than a whole number of seconds gives an
#'   ordinary error.
#' @export
#' @examples
#' commitment_key_id(paste(rep("0f", 32), collapse = ""))
#' key <- tryCatch(new_commitment_key(), mixedcheck_error = function(e) NULL)
#' if (!is.null(key)) key$key_id
new_commitment_key <- function() {
  created <- utc_timestamp(run_time())
  key <- paste(as.character(random_key_bytes()), collapse = "")
  list(created = created, key = key, key_id = commitment_key_id(key))
}

# The type of the operating system, a function of its own so that the tests
# can take the branch of another system.
platform_type <- function() {
  .Platform$OS.type
}

# Whether a package can be loaded, a function of its own so that the tests
# can take the branch of a package that is not installed.
package_installed <- function(package) {
  requireNamespace(package, quietly = TRUE)
}

# 32 bytes from a cryptographically secure source (conventions.md, Keys):
# /dev/urandom on Unix-alikes and openssl::rand_bytes() where /dev/urandom
# does not exist or cannot be read, or E1312 when neither is available.
random_key_bytes <- function() {
  bytes <- NULL
  if (platform_type() == "unix" && file.exists("/dev/urandom")) {
    bytes <- urandom_bytes()
  }
  if ((!is.raw(bytes) || length(bytes) != 32L) && package_installed("openssl")) {
    bytes <- openssl::rand_bytes(32L)
  }
  if (!is.raw(bytes) || length(bytes) != 32L) {
    raise_issue("E1312")
  }
  as.raw(bytes)
}

# 32 bytes read from /dev/urandom, or NULL when it cannot be read. The
# connection is opened with raw = TRUE, since /dev/urandom is not a regular
# file.
urandom_bytes <- function() {
  connection <- tryCatch(file("/dev/urandom", "rb", raw = TRUE), error = function(e) NULL)
  if (is.null(connection)) {
    return(NULL)
  }
  on.exit(close(connection))
  tryCatch(readBin(connection, "raw", n = 32L), error = function(e) NULL)
}

#' @rdname new_commitment_key
#' @export
commitment_key_id <- function(key) {
  substr(cli::hash_raw_sha256(commitment_key_bytes(key)), 1L, 16L)
}

#' Keyed commitments
#'
#' A keyed commitment is the HMAC-SHA-256 of a message under a commitment key.
#' Shareable files carry commitments in place of hashes of person-level data,
#' because an unkeyed hash of a small data set can be reversed by trying every
#' possible value. The message for 'data_file' is the bytes of a raw data file
#' as stored, which `readBin(path, "raw", file.size(path))` reads.
#'
#' @param message The bytes committed to, as a raw vector.
#' @param key A commitment key, as 64 lower-case hexadecimal digits.
#' @param covers What the message is: 'data_file', 'analysis_table' or
#'   'outcome_column'.
#' @return A list with the members `algorithm`, `covers`, `digest` and
#'   `key_id`, the form of a keyed commitment in a results document.
#' @section Errors: A key of another form gives an error of class
#'   `mixedcheck_error` with the code E1311.
#' @export
#' @examples
#' key <- paste(rep("0f", 32), collapse = "")
#' keyed_commitment(charToRaw("pupil,score\n1,12\n"), key)
keyed_commitment <- function(message, key,
                             covers = c("data_file", "analysis_table", "outcome_column")) {
  if (!is.raw(message)) {
    stop("'message' must be a raw vector.", call. = FALSE)
  }
  covers <- exact_choice(covers, c("data_file", "analysis_table", "outcome_column"),
                         "'covers' must be 'data_file', 'analysis_table' or 'outcome_column'.")
  bytes <- commitment_key_bytes(key)
  list(
    algorithm = "hmac-sha256",
    covers = covers,
    digest = hmac_sha256(bytes, message),
    key_id = substr(cli::hash_raw_sha256(bytes), 1L, 16L)
  )
}

# Verifies a keyed commitment against the message it covers, with the keys of
# an internal sidecar as commitment_key objects. Reports E1313 when no key has
# the commitment's identifier and E1314, at the pointer of the commitment,
# when the digest differs. Returns TRUE invisibly otherwise.
verify_commitment <- function(commitment, message, keys, pointer = "") {
  key_ids <- vapply(keys, function(entry) entry[["key_id"]], "")
  found <- which(key_ids == commitment[["key_id"]])
  if (length(found) == 0L) {
    raise_issue("E1313", list(key_id = commitment[["key_id"]]))
  }
  digest <- hmac_sha256(commitment_key_bytes(keys[[found[1L]]][["key"]]), message)
  if (!identical(digest, commitment[["digest"]])) {
    raise_issue("E1314", pointer = pointer)
  }
  invisible(TRUE)
}

# The value at a JSON Pointer (RFC 6901) in a value read by the strict reader,
# such as the section of a document whose hash the document records.
json_pointer_get <- function(x, pointer) {
  if (identical(pointer, "")) {
    return(x)
  }
  if (!startsWith(pointer, "/")) {
    stop("A JSON Pointer must be empty or start with '/'.", call. = FALSE)
  }
  tokens <- strsplit(substring(pointer, 2L), "/", fixed = TRUE)[[1L]]
  if (endsWith(pointer, "/")) {
    tokens <- c(tokens, "")
  }
  for (token in tokens) {
    token <- gsub("~0", "~", gsub("~1", "/", token, fixed = TRUE), fixed = TRUE)
    if (!is.list(x)) {
      stop(sprintf("The pointer '%s' does not lead to a value.", pointer), call. = FALSE)
    }
    if (is.null(names(x))) {
      if (!grepl("^(0|[1-9][0-9]*)$", token) || as.numeric(token) >= length(x)) {
        stop(sprintf("The pointer '%s' does not lead to a value.", pointer), call. = FALSE)
      }
      x <- x[[as.integer(token) + 1L]]
    } else {
      found <- which(names(x) == token)
      if (length(found) == 0L) {
        stop(sprintf("The pointer '%s' does not lead to a value.", pointer), call. = FALSE)
      }
      x <- x[[found[1L]]]
    }
  }
  x
}
