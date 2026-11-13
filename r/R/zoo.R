# The accessor of the pathology zoo (fixtures/zoo/README.md), the simulated
# fixtures that spec/tools/vendor.py installs under inst/fixtures/zoo/ with
# their SHA-256 digests in inst/fixtures/MANIFEST.json.

#' The pathology zoo
#'
#' The pathology zoo is a set of small simulated data sets, each with a
#' declaration, a preliminary formula and the findings that [audit()] is
#' expected to give for it. Each fixture plants one problem of a study design,
#' such as class labels that recur across schools or a randomisation level
#' left out of the formula, and has a matched negative, a similar design
#' without the problem. The expected findings are derived from the design
#' that generated the data, never from either package. The R and Python
#' packages install the same files, and fixtures/zoo/README.md in the
#' repository describes each fixture and the formats.
#'
#' Called without an argument, `pathology_zoo()` lists the fixtures. Called
#' with an identifier, it returns one fixture, ready to be audited.
#'
#' Before a file is read, its SHA-256 digest is compared with the
#' MANIFEST.json installed with the package, as for the registry.
#'
#' @param fixture `NULL`, to list the fixtures, or the identifier of one
#'   fixture or matched negative, such as 'Z01' or 'Z01N'.
#' @return Without an argument, a data frame with one row for each fixture
#'   and matched negative, in the order of their identifiers, and the columns
#'   `id`, `name`, `title`, `role` ('fixture' or 'negative'), `matched` (the
#'   identifier of the matched negative of a fixture, or of the fixture of a
#'   negative), `tier` (the outcome access of its run, 'T0', 'T1' or 'T2'),
#'   `rows` (the number of rows of its data), `domain` and `deferred` (whether
#'   it records a declaration block of a later vocabulary for which its
#'   planned check waits, or for a negative that of its fixture). `rows` is
#'   integer, `deferred` logical and the others character.
#'
#'   With an identifier, a named list with the elements `id`, `name`,
#'   `title`, `role`, `matched` and `tier` as in the listing, `data`, the
#'   data read by [read_table()] with the declaration, a data frame with the
#'   attribute `types`, `data_file`, the path of the installed data file that
#'   `data` was read from, `declaration`, the declaration as
#'   [validate_declaration()] returns it, `formula`, the formula as a
#'   character string, `arguments`, the further arguments of [audit()] that
#'   the run of the fixture sets, as a named list with `outcome_access` and,
#'   at the tiers T1 and T2, `reason` and `exploratory`, and `expected`, the
#'   expected findings of the fixture as [read_json_strict()] returns them in
#'   the data profile.
#' @section Errors: An argument that is neither `NULL` nor one string, an
#'   identifier that names no fixture and an installed file that is missing
#'   or differs from MANIFEST.json give ordinary errors. A table or
#'   declaration that does not read gives the error of class
#'   `mixedcheck_error` of [read_table()] or [validate_declaration()], which
#'   only a damaged installation can cause.
#' @seealso [audit()], which a fixture is made for.
#' @export
#' @examples
#' zoo <- pathology_zoo()
#' zoo[, c("id", "title", "tier")]
#'
#' # Audit one fixture in internal mode with a fixed commitment key.
#' fixture <- pathology_zoo("Z08")
#' key <- paste(sprintf("%02x", 0:31), collapse = "")
#' results <- do.call(audit, c(list(fixture$data, fixture$formula, fixture$declaration),
#'                             fixture$arguments, list(privacy = "internal", key = key)))
#' results
pathology_zoo <- function(fixture = NULL) {
  zoo_fixture(fixture, installed_path("fixtures"))
}

# The accessor on a directory of installed fixtures, which holds zoo/ and
# MANIFEST.json, so that the tests can give it a modified copy.
zoo_fixture <- function(fixture, root) {
  if (!is.null(fixture) && !(is.character(fixture) && length(fixture) == 1L && !is.na(fixture))) {
    stop("'fixture' must be NULL or one identifier, such as 'Z01'.", call. = FALSE)
  }
  digests <- zoo_manifest(root)
  index <- read_json_strict(zoo_checked_bytes(root, "zoo/index.json", digests), "data")
  fixtures <- index[["fixtures"]]
  if (is.null(fixture)) {
    return(zoo_listing(fixtures))
  }
  ids <- vapply(fixtures, function(entry) entry[["id"]], "")
  position <- match(enc2utf8(fixture), ids)
  if (is.na(position)) {
    stop(paste0("'", fixture, "' is not an identifier of the pathology zoo. ",
                "pathology_zoo() lists them."), call. = FALSE)
  }
  directory <- paste0("zoo/", fixture, "-", fixtures[[position]][["name"]])
  for (name in c("data.csv", "declaration.json", "formula.txt", "expected.json")) {
    zoo_checked_bytes(root, paste0(directory, "/", name), digests)
  }
  zoo_read(file.path(root, directory))
}

# The digests of the MANIFEST.json of the installed fixtures.
zoo_manifest <- function(root) {
  path <- file.path(root, "MANIFEST.json")
  if (!file.exists(path)) {
    stop("'fixtures/MANIFEST.json' is missing from the installed package.", call. = FALSE)
  }
  read_json_strict(path, "data")[["files"]]
}

# The bytes of an installed file after its digest is compared with the
# manifest.
zoo_checked_bytes <- function(root, name, digests) {
  path <- file.path(root, name)
  shown <- paste0("fixtures/", name)
  if (!file.exists(path)) {
    stop(paste0("'", shown, "' is missing from the installed package."), call. = FALSE)
  }
  bytes <- readBin(path, "raw", n = file.size(path))
  if (!identical(cli::hash_raw_sha256(bytes), digests[[name]])) {
    stop(paste0("'", shown, "' differs from the MANIFEST.json installed with the package."),
         call. = FALSE)
  }
  bytes
}

zoo_listing <- function(fixtures) {
  column <- function(name) vapply(fixtures, function(entry) entry[[name]], "")
  data.frame(
    id = column("id"), name = column("name"), title = column("title"), role = column("role"),
    matched = column("matched"), tier = column("tier"),
    rows = vapply(fixtures, function(entry) as.integer(entry[["rows"]]), 0L),
    domain = column("domain"),
    deferred = vapply(fixtures, function(entry) isTRUE(entry[["deferred"]]), NA),
    stringsAsFactors = FALSE
  )
}

# Reads the four files of a directory of the zoo, installed or in the source
# tree, without comparing digests, and returns the elements of one fixture.
zoo_read <- function(directory) {
  expected <- read_json_strict(file.path(directory, "expected.json"), "data")
  declaration <- validate_declaration(file.path(directory, "declaration.json"))
  data <- read_table(file.path(directory, "data.csv"), declaration)
  path <- file.path(directory, "formula.txt")
  bytes <- readBin(path, "raw", n = file.size(path))
  if (length(bytes) && bytes[length(bytes)] == as.raw(10L)) {
    bytes <- bytes[-length(bytes)]
  }
  formula <- rawToChar(bytes)
  Encoding(formula) <- "UTF-8"
  run <- expected[["run"]]
  arguments <- Filter(Negate(is.null), list(
    outcome_access = run[["outcome_access"]], reason = run[["reason"]],
    exploratory = run[["exploratory"]]
  ))
  list(id = expected[["id"]], name = expected[["name"]], title = expected[["title"]],
       role = expected[["role"]], matched = expected[["matched"]],
       tier = run[["outcome_access"]], data = data,
       data_file = file.path(directory, "data.csv"), declaration = declaration,
       formula = formula, arguments = arguments, expected = expected)
}
