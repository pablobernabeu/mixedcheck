#' Versions of the shared specification
#'
#' Returns the versions of the check registry, the schemas and the
#' canonicaliser recorded in the copy of the shared specification installed
#' with the package. The Python package's `mixedcheck.spec_versions()` returns
#' the same names and values from its own copy.
#'
#' @return A named list with the elements `registry`, `schemas` and
#'   `canonicaliser`. Each element is a version number held as a character
#'   string.
#' @export
#' @examples
#' spec_versions()
spec_versions <- function() {
  read_spec_versions(installed_path("spec", "versions.json"))
}

installed_path <- function(...) {
  path <- system.file(..., package = "mixedcheck")
  if (!nzchar(path)) {
    stop(
      sprintf("'%s' is missing from the installed package.", file.path(...)),
      call. = FALSE
    )
  }
  path
}

read_spec_versions <- function(path) {
  # Invalid JSON gets the same message as in Python, so that both packages
  # fail in the same words.
  versions <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is_object_of_strings(versions)) {
    stop(
      sprintf("'%s' must hold a JSON object whose values are strings.", path),
      call. = FALSE
    )
  }
  versions
}

is_object_of_strings <- function(x) {
  keys <- names(x)
  is.list(x) && length(x) > 0L && !is.null(keys) && all(nzchar(keys)) &&
    !anyDuplicated(keys) &&
    all(vapply(x, function(value) is.character(value) && length(value) == 1L, logical(1)))
}

# Compares the files in a vendored directory with the SHA-256 digests in its
# MANIFEST.json, which spec/tools/vendor.py writes. Returns one message per
# problem, or character(0) when the directory matches its manifest.
vendored_problems <- function(directory) {
  manifest_path <- file.path(directory, "MANIFEST.json")
  if (!file.exists(manifest_path)) {
    return("MANIFEST.json: missing")
  }
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  if (!identical(manifest[["algorithm"]], "sha256") ||
      !is_object_of_strings(manifest[["files"]])) {
    return("MANIFEST.json: not a manifest of SHA-256 digests")
  }
  listed <- manifest[["files"]]
  present <- setdiff(
    list.files(directory, recursive = TRUE, all.files = TRUE, no.. = TRUE),
    "MANIFEST.json"
  )
  problems <- c(
    sprintf("%s: missing", setdiff(names(listed), present)),
    sprintf("%s: not listed in MANIFEST.json", setdiff(present, names(listed)))
  )
  for (name in intersect(names(listed), present)) {
    path <- file.path(directory, name)
    # Read as raw bytes, so that no encoding or line-ending conversion can
    # change the digest.
    digest <- cli::hash_raw_sha256(readBin(path, "raw", n = file.size(path)))
    if (!identical(digest, listed[[name]])) {
      problems <- c(problems, sprintf("%s: SHA-256 differs from MANIFEST.json", name))
    }
  }
  problems
}
