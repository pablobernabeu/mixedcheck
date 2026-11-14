# The results object that audit() returns, its printing and the writer of the
# results document and its internal sidecar (docs/spec/documents.md, Results
# document, Writing and Internal sidecar, and 03-execution-plan.md, M2).

# The banners of the two privacy modes, as documents.md (privacy) writes them.
results_banners <- c(
  shareable = paste("Shareable output: the privacy filter has reduced the risk of disclosure,",
                    "but this report is not anonymous data."),
  internal = paste("INTERNAL: this report holds values that the privacy filter has not checked,",
                   "such as small counts and labels. Do not share it.")
)

# The suffix of the names of internal files (documents.md, Writing).
internal_suffix <- ".internal.json"

# The results object: the results document, in the form that
# read_json_strict() returns in the data profile, and the internal sidecar
# without results_hash, which only write_results() sets: its version, the
# commitment keys of the run and the pseudonyms.
new_results <- function(document, sidecar) {
  structure(list(document = document, sidecar = sidecar), class = "mixedcheck_results")
}

# The banner of a document: the shareable banner only for a document whose
# mode is 'shareable', and the internal banner otherwise.
results_banner <- function(document) {
  if (identical(document[["privacy"]][["mode"]], "shareable")) {
    results_banners[["shareable"]]
  } else {
    results_banners[["internal"]]
  }
}

# One line for a finding: its check, the parts of its scope in ascending
# order of name, and its finding status and message, or its availability.
finding_line <- function(finding) {
  scope <- finding[["scope"]]
  parts <- sort(as.character(names(scope)), method = "radix")
  where <- if (length(parts)) {
    values <- vapply(parts, function(part) display_text(scope[[part]], limit = NA), "")
    paste0(" (", paste0(parts, " '", values, "'", collapse = ", "), ")")
  } else {
    ""
  }
  status <- finding[["status"]]
  availability <- status[["availability"]]
  if (!identical(availability[["value"]], "available")) {
    reason <- availability[["reason"]]
    detail <- availability[["detail"]] %||% availability[["version"]]
    if (!is.null(detail)) {
      reason <- paste0(reason, ": ", display_text(detail, limit = NA))
    }
    return(paste0(finding[["check"]], where, ": not available (", reason, ")."))
  }
  paste0(finding[["check"]], where, ": ", chartr("_", " ", status[["finding"]][["value"]]), ". ",
         display_text(finding[["message"]][["text"]], limit = NA))
}

#' @export
print.mixedcheck_results <- function(x, ...) {
  document <- x[["document"]]
  findings <- document[["findings"]]
  lines <- if (length(findings)) vapply(findings, finding_line, "") else "No findings."
  cat(results_banner(document), lines, sep = "\n")
  invisible(x)
}

#' Write a results document and its internal sidecar
#'
#' Writes the results document of a results object to `path` as its
#' canonical bytes, the JSON text that RFC 8785 defines, and the internal
#' sidecar to `sidecar`. The sidecar holds the commitment keys of the run, the
#' pseudonyms of a shareable document and `results_hash`, the SHA-256 of the
#' bytes written to `path`, so it must stay on the analyst's machine. Every
#' document of [audit()] commits to its analysis table with a key, so the
#' sidecar is always written.
#'
#' File names show which files may be shared: the name of `path` must end in
#' '.internal.json' exactly when the document is internal, and the name of
#' `sidecar` must always end in it. No suffix is added, so the caller sees the
#' name of each file written. Existing files are replaced.
#'
#' A results object is a list of class 'mixedcheck_results' with the elements
#' `document`, the results document in the form that [read_json_strict()]
#' returns, and `sidecar`, the sidecar without `results_hash`. Printing it
#' shows the banner of its privacy mode and one line for each finding.
#'
#' @param results A results object, as [audit()] returns it.
#' @param path The path of the results document, as a character string.
#' @param sidecar The path of the internal sidecar, as a character string,
#'   which must differ from `path`.
#' @return The results file hash, invisibly: 'sha256:' followed by the 64
#'   lower-case hexadecimal digits of the SHA-256 digest of the bytes written
#'   to `path`.
#' @section Errors: A file name whose suffix does not match gives an error of
#'   class `mixedcheck_error` with the code E7010, and a commitment key found
#'   in a shareable document the code E1315. A document that the writer cannot
#'   write in the data profile gives the writer's code at its JSON Pointer.
#'   Arguments of the wrong type, and a `sidecar` equal to `path`, give an
#'   ordinary error.
#' @family results documents
#' @export
#' @examples
#' # Fixture Z01 of the pathology zoo (pathology_zoo()) in internal mode.
#' fixture <- pathology_zoo("Z01")
#' key <- paste(sprintf("%02x", 0:31), collapse = "")
#' results <- audit(fixture$data, fixture$formula, fixture$declaration, privacy = "internal",
#'                  key = key)
#'
#' # An internal document is written to a file whose name says so.
#' path <- file.path(tempdir(), "audit.internal.json")
#' sidecar <- file.path(tempdir(), "audit.sidecar.internal.json")
#' write_results(results, path, sidecar)
#' validate_results(path, sidecar, data = fixture$data,
#'                  declaration = fixture$declaration)$privacy$mode
#'
#' # An internal document cannot be written to a file named as shareable.
#' problem <- tryCatch(write_results(results, file.path(tempdir(), "audit.json"), sidecar),
#'                     mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
#' unlink(c(path, sidecar))
write_results <- function(results, path, sidecar) {
  if (!inherits(results, "mixedcheck_results")) {
    stop("'results' must be a results object, as audit() returns it.", call. = FALSE)
  }
  for (argument in list(list(path, "path"), list(sidecar, "sidecar"))) {
    value <- argument[[1L]]
    if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
      stop(sprintf("'%s' must be a file path.", argument[[2L]]), call. = FALSE)
    }
  }
  if (identical(resolved_path(path), resolved_path(sidecar))) {
    stop("'sidecar' must be a path other than 'path'.", call. = FALSE)
  }
  document <- results[["document"]]
  shareable <- identical(document[["privacy"]][["mode"]], "shareable")
  if (shareable == endsWith(basename(path), internal_suffix)) {
    raise_issue("E7010", if (shareable) {
      list(file = "shareable results document", rule = "does not end in")
    } else {
      list(file = "internal results document", rule = "ends in")
    })
  }
  if (!endsWith(basename(sidecar), internal_suffix)) {
    raise_issue("E7010", list(file = "internal sidecar", rule = "ends in"))
  }
  if (shareable) {
    found <- commitment_key_pointer(document)
    if (!is.null(found)) {
      raise_issue("E1315", pointer = found)
    }
  }
  for (file in c(path, sidecar)) {
    if (!dir.exists(dirname(file))) {
      stop(sprintf("The directory of '%s' does not exist.", display_text(file)), call. = FALSE)
    }
  }
  bytes <- canonical_bytes(document, "data")
  hash <- hash_bytes(bytes)
  sidecar_value <- results[["sidecar"]]
  sidecar_value[["results_hash"]] <- hash
  sidecar_bytes <- canonical_bytes(sidecar_value, "data")
  # The sidecar holds the only copy of the key, so a document whose sidecar
  # cannot be written is removed.
  writeBin(bytes, path)
  complete <- FALSE
  on.exit(if (!complete) unlink(path), add = TRUE)
  writeBin(sidecar_bytes, sidecar)
  complete <- TRUE
  invisible(hash)
}

# A path with its directory resolved, so that two names of one file compare
# equal when the directory exists.
resolved_path <- function(path) {
  file.path(normalizePath(dirname(path), winslash = "/", mustWork = FALSE), basename(path))
}

# The JSON Pointer of the first commitment key in a value, in the order of
# its canonical serialisation: an object with exactly the members created,
# key and key_id (conventions.md, Keys). NULL when there is none.
commitment_key_pointer <- function(x, path = character(0)) {
  if (!is.list(x) || !is.null(attr(x, "class"))) {
    return(NULL)
  }
  keys <- names(x)
  if (!is.null(keys) && identical(sort(keys, method = "radix"), c("created", "key", "key_id"))) {
    return(json_pointer(path))
  }
  ordering <- if (is.null(keys)) seq_along(x) else utf16_order(keys)
  for (i in ordering) {
    token <- if (is.null(keys)) as.character(i - 1L) else keys[i]
    found <- commitment_key_pointer(x[[i]], c(path, token))
    if (!is.null(found)) {
      return(found)
    }
  }
  NULL
}
