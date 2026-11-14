# The validator of results documents and the reading and verification of
# internal sidecars (docs/spec/documents.md, Validation and Internal
# sidecar).

#' Validate a results document and verify its sidecar
#'
#' Validates a results document in the five stages of the results
#' specification and stops after the first stage that finds a problem:
#' reading in the data profile, the version at `/results_version`, the
#' structure against the results schema, the rules on findings and the access
#' log, with the invariants of a shareable document, and the rules that
#' compare each finding with the registry entry of its check. A document
#' produced with another registry is reported with the warning W7090, and its
#' findings are not compared with registry entries.
#'
#' With a sidecar, the sidecar is then read in the data profile and its
#' version, structure and rules are checked, and it is verified against the
#' document: the hash of the results file, the keys that the commitments of
#' the document name and, with `data`, every commitment to the data file, the
#' analysis table and an outcome column, recomputed from the data with the
#' keys of the sidecar. A results object without `sidecar` is verified against
#' the sidecar it holds, without the check of the results file hash, which it
#' does not hold.
#'
#' @param document A results document: the path of a file, the value that
#'   [read_json_strict()] returns or a results object, as [audit()] returns
#'   it. A document in memory is first written in the data profile, and the
#'   hash of its canonical bytes stands for the hash of the file.
#' @param sidecar `NULL`, or the internal sidecar of the document: the path
#'   of a file or the value that [read_json_strict()] returns.
#' @param data `NULL`, or the data of the run that produced the document: the
#'   path of its CSV file, or a data frame, as [audit()] accepts them. A
#'   document that commits to a data file needs its path. The commitments are
#'   recomputed from the data, so `data` needs the keys of a sidecar.
#' @param declaration `NULL`, or the declaration of the run, as
#'   [validate_declaration()] accepts it, when the run had one. It is used
#'   with `data` alone.
#' @return The document, invisibly: the value read from a file, in the form
#'   that [read_json_strict()] returns, or the document given in memory.
#' @section Errors: A document that is not valid gives an error of class
#'   `mixedcheck_error`, whose element `issues` lists the problems of the
#'   first stage that finds any, each with the `code` of the shared error
#'   catalogue, the rendered `message` and its location. Reading reports one
#'   problem, located by the byte `offset` in the file or, for a document in
#'   memory, by the JSON Pointer of the value that cannot be written. The
#'   later stages report every problem they find, located by JSON Pointer as
#'   `pointer`, sorted by pointer, code and message and capped at 100. A
#'   document whose registry hash differs from that of the registry of this
#'   release gives a warning of class `mixedcheck_warning` with the code W7090
#'   alone. A sidecar that is not valid, or that does not agree with the
#'   document, gives an error with its issues: one from reading, E1441 for its
#'   version, the structural issues or the issues of its rules (E1321, E7060
#'   and E7061), or the issues of verification in this order: E1321 at
#'   `/results_hash`, E1313 for each key that the sidecar lacks and E1314 at
#'   each commitment that the data do not match. A declaration that is not
#'   valid, or data that cannot be read, give the error of
#'   [validate_declaration()] or [read_table()], and a data frame with a
#'   value outside the declared categories of its field gives E5012, as in
#'   [audit()]. Arguments of the wrong type,
#'   `data` without a sidecar and `declaration` without `data` give an
#'   ordinary error.
#' @family results documents
#' @export
#' @examples
#' # The shareable document of an audit of fixture Z01 of the pathology zoo
#' # (pathology_zoo()), validated with its sidecar, data and declaration.
#' fixture <- pathology_zoo("Z01")
#' key <- paste(sprintf("%02x", 0:31), collapse = "")
#' results <- audit(fixture$data, fixture$formula, fixture$declaration, key = key)
#' path <- file.path(tempdir(), "audit.json")
#' sidecar <- file.path(tempdir(), "audit.sidecar.internal.json")
#' write_results(results, path, sidecar)
#' value <- validate_results(path, sidecar, data = fixture$data,
#'                           declaration = fixture$declaration)
#' value$privacy$mode
#'
#' # A document of another registry: its findings are not compared with
#' # registry entries, and a warning says so.
#' document <- read_json_strict(path, "data")
#' other <- document
#' other$inputs$registry_hash <- paste0("sha256:", strrep("0", 64))
#' found <- tryCatch(validate_results(other), mixedcheck_warning = function(w) w)
#' found$issues[[1]]$code
#'
#' # A finding of a check that the registry does not have.
#' document$findings[[length(document$findings)]]$check <- "structure.no_such_check"
#' problem <- tryCatch(validate_results(document), mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
#' unlink(c(path, sidecar))
validate_results <- function(document, sidecar = NULL, data = NULL, declaration = NULL) {
  is_object <- inherits(document, "mixedcheck_results")
  if (!is_object && !is_string(document) && !is_plain_list(document)) {
    stop(paste("'document' must be a file path, a value that read_json_strict() returns",
               "or a results object."), call. = FALSE)
  }
  if (!is.null(sidecar) && !is_string(sidecar) && !is_plain_list(sidecar)) {
    stop("'sidecar' must be NULL, a file path or a value that read_json_strict() returns.",
         call. = FALSE)
  }
  if (!is.null(data) && !is_string(data) && !is.data.frame(data)) {
    stop("'data' must be NULL, a data frame or the path of a CSV file.", call. = FALSE)
  }
  if (!is.null(data) && is.null(sidecar) && !is_object) {
    stop("'data' needs a sidecar, whose keys the commitments are recomputed with.", call. = FALSE)
  }
  if (!is.null(declaration) && is.null(data)) {
    stop("'declaration' is used only with 'data'.", call. = FALSE)
  }
  input <- if (is_object) document[["document"]] else document
  read <- read_results_input(input)
  issues <- results_document_issues(read$value)
  if (length(issues)) {
    if (identical(issues[[1L]][["code"]], "W7090")) {
      warning(issue_condition(issues, "mixedcheck_warning"))
    } else {
      signal_issues(issues)
    }
  }
  if (is.null(sidecar) && is_object) {
    # The hash of the document stands in for the results hash, which the
    # sidecar of a results object does not hold, so that it is not checked.
    sidecar <- document[["sidecar"]]
    sidecar[["results_hash"]] <- read$hash
  }
  if (!is.null(sidecar)) {
    sidecar_issues <- results_sidecar_issues(sidecar, read$value, read$hash, data, declaration)
    if (length(sidecar_issues)) {
      signal_issues(sidecar_issues)
    }
  }
  invisible(if (is.character(input)) read$value else input)
}

is_plain_list <- function(x) {
  is.list(x) && is.null(attr(x, "class"))
}

# Stage 1: the document read from a file in the data profile, or a value in
# memory written in the data profile and read again, with the hash of the
# bytes read or written.
read_results_input <- function(input) {
  bytes <- if (is.character(input)) {
    read_input_bytes(input)
  } else {
    canonical_bytes(mark_input_strings(input), "data")
  }
  list(value = parse_json_bytes(bytes, "data"), hash = hash_bytes(bytes))
}

# The supported line of results documents and sidecars.
results_version_pattern <- "^0\\.1\\.(0|[1-9][0-9]*)\\z"

# Stages 2 to 5 on a document read in stage 1. Returns the issues of the
# first stage that finds any, rendered, sorted and capped, or W7090 alone.
results_document_issues <- function(value) {
  version <- if (is_json_object(value)) value[["results_version"]]
  if (is.character(version) && !version_supported(version, results_version_pattern)) {
    return(list(new_issue("E1441", list(version = version, supported = "0.1.x"),
                          pointer = "/results_version")))
  }
  for (stage in list(
    function(d) schema_issues(d, "urn:mixedcheck:schema:results"),
    results_rule_issues,
    results_registry_issues
  )) {
    raw <- stage(value)
    if (length(raw)) {
      return(finish_issues(raw))
    }
  }
  list()
}

# The list by which findings are ordered and compared: the check, then the
# name and the NFC form of the value of each part of the scope, in ascending
# order of part name (documents.md, Findings).
finding_order_key <- function(finding) {
  scope <- finding[["scope"]]
  parts <- sort(as.character(names(scope)), method = "radix")
  values <- comparison_form(vapply(parts, function(part) scope[[part]], "", USE.NAMES = FALSE))
  c(finding[["check"]], as.vector(rbind(parts, values)))
}

# Whether the list a comes before the list b: their strings compared in turn
# by their bytes, which for UTF-8 is the order of code points, and a list
# that is a prefix of the other first.
key_before <- function(a, b) {
  common <- min(length(a), length(b))
  for (j in seq_len(common)) {
    if (a[j] != b[j]) {
      return(identical(order(c(a[j], b[j]), method = "radix"), 1:2))
    }
  }
  length(a) < length(b)
}

# Stage 4: the rules on findings and the access log (E7001 to E7006) and, in
# a shareable document, the invariants E7020 to E7023, on a document whose
# structure is valid.
results_rule_issues <- function(d) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  log <- d[["access_log"]]
  entries <- log[["entries"]]
  has_plan <- !is.null(log[["plan"]])
  for (i in seq_along(entries)) {
    here <- paste0("/access_log/entries/", i - 1L)
    if (identical(entries[[i]][["mode"]], "planned") && !has_plan) {
      add("E7004", paste0(here, "/mode"))
    }
    # Times have one width, so they compare as strings, byte by byte.
    if (i > 1L && key_before(entries[[i]][["time"]], entries[[i - 1L]][["time"]])) {
      add("E7005", paste0(here, "/time"))
    }
  }
  if (!is.null(d[["inputs"]][["execution_binding_hash"]]) && !has_plan) {
    add("E7004", "/inputs/execution_binding_hash")
  }
  tiers <- vapply(entries, function(entry) entry[["tier"]], "")
  privacy <- d[["privacy"]]
  has_unit <- !is.null(privacy[["disclosure_unit"]])
  shareable <- identical(privacy[["mode"]], "shareable")
  findings <- d[["findings"]]
  keys <- lapply(findings, finding_order_key)
  # Scope values hold no control characters, so U+0001 separates them.
  repeated <- duplicated(vapply(keys, paste, "", collapse = "\001"))
  for (i in seq_along(findings)) {
    finding <- findings[[i]]
    here <- paste0("/findings/", i - 1L)
    if (repeated[i]) {
      add("E7001", here)
    }
    if (i > 1L && key_before(keys[[i]], keys[[i - 1L]])) {
      add("E7002", here)
    }
    if (!identical(finding[["status"]][["availability"]][["value"]], "available")) {
      next
    }
    if (!finding[["tier"]] %in% tiers) {
      add("E7003", paste0(here, "/tier"), list(tier = finding[["tier"]]))
    }
    basis <- finding[["support"]][["contributors"]][["basis"]]
    allowed <- if (has_unit) "disclosure_unit" else c("grouping_factors", "rows")
    if (!basis %in% allowed) {
      add("E7006", paste0(here, "/support/contributors/basis"), list(expected = as.list(allowed)))
    }
    if (shareable) {
      for (issue in shareable_finding_issues(finding, here, privacy[["min_count"]])) {
        issues[[length(issues) + 1L]] <- issue
      }
    }
  }
  issues
}

# The invariants E7020 to E7023 for one available finding of a shareable
# document, with k the minimum count (documents.md, Shareable documents).
# Each written value gets the first issue that applies, in the order E7020,
# E7021, E7022 and E7023.
shareable_finding_issues <- function(finding, here, k) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  support <- finding[["support"]]
  contributors <- support[["contributors"]]
  distinct <- contributors[["distinct"]]
  fails_minimum <- if (is.null(distinct[["value"]])) {
    !identical(distinct[["availability"]][["detail"]], "secondary")
  } else {
    distinct[["value"]] < k
  }
  fails <- fails_minimum || isTRUE(contributors[["dominated"]])
  rule <- if (fails_minimum) "minimum-count" else "dominance"
  for (member in list(list(support[["rows"]], "/support/rows/value"),
                      list(distinct, "/support/contributors/distinct/value"))) {
    value <- member[[1L]][["value"]]
    if (!is.null(value) && value < k) {
      add("E7020", paste0(here, member[[2L]]), list(limit = k))
    }
  }
  statistics <- finding[["statistics"]]
  for (name in names(statistics)) {
    statistic <- statistics[[name]]
    value <- statistic[["value"]]
    if (is.null(value)) {
      next
    }
    at <- paste0(child_pointer(paste0(here, "/statistics"), name), "/value")
    kind <- statistic[["kind"]]
    person <- identical(statistic[["count_class"]], "person")
    quantile <- statistic[["quantile"]]
    if (kind == "count" && person && value < k) {
      add("E7020", at, list(limit = k))
    } else if (fails && (kind %in% c("real", "reals", "labels") ||
                           (kind %in% c("count", "ratio") && person))) {
      add("E7021", at, list(rule = rule))
    } else if (!is.null(quantile) &&
               (is.null(quantile[["n"]]) || !quantile_shown(quantile[["n"]], quantile[["p"]], k))) {
      add("E7022", at, list(limit = k))
    } else if (kind == "labels") {
      bundle <- schema_bundle()
      pattern <- resolve_reference(bundle, "urn:mixedcheck:schema:results#/$defs/pseudonym",
                                   "urn:mixedcheck:schema:results")$schema[["pattern"]]
      for (j in seq_along(value)) {
        if (!schema_pattern_matches(bundle, pattern, value[[j]])) {
          add("E7023", paste0(at, "/", j - 1L))
        }
      }
    }
  }
  issues
}

# The quantile rule of privacy.md (Steps, 4): a p-quantile of n values is
# written only when n x min(m, 10^d - m) >= k x 10^d in integer arithmetic,
# where m / 10^d is the shortest decimal that represents p, so that p = 0
# and p = 1 never are. p is a double from 0 to 1 or a decimal string.
quantile_shown <- function(n, p, k) {
  if (is.character(p)) {
    digits <- sub("^0\\.?", "", p)
    exponent <- if (startsWith(p, "0.")) {
      -(nchar(digits) - nchar(sub("^0+", "", digits)))
    } else {
      nchar(p)
    }
    digits <- sub("^0+", "", digits)
  } else {
    if (p == 0) {
      return(FALSE)
    }
    parts <- number_parts(p)
    digits <- parts$digits
    exponent <- parts$n
  }
  # p = 0.digits x 10^exponent, so m = digits and d = nchar(digits) - exponent.
  if (!nzchar(digits) || exponent >= 1L) {
    return(FALSE)
  }
  d <- nchar(digits) - exponent
  m <- bn_from_digits(digits)
  power <- c(numeric(d %/% 7L), 10^(d %% 7L))
  smaller <- if (bn_compare(bn_add(m, m), power) <= 0L) m else bn_sub(power, m)
  bn_compare(bn_mul(bn_normalise(n), smaller), bn_mul(bn_normalise(k), power)) >= 0L
}

# A big integer from a string of decimal digits.
bn_from_digits <- function(digits) {
  count <- nchar(digits)
  ends <- rev(seq.int(count, 1L, by = -7L))
  limbs <- as.numeric(substring(digits, pmax(ends - 6L, 1L), ends))
  bn_normalise(rev(limbs))
}

# The product of two big integers. Each limb product is below 10^14, and the
# few limbs of the factors here keep each sum of products below 2^53.
bn_mul <- function(a, b) {
  result <- numeric(length(a) + length(b))
  for (i in seq_along(b)) {
    span <- i - 1L + seq_along(a)
    result[span] <- result[span] + a * b[i]
  }
  bn_normalise(result)
}

# Compares two big integers: -1, 0 or 1.
bn_compare <- function(a, b) {
  if (length(a) != length(b)) {
    return(if (length(a) < length(b)) -1L else 1L)
  }
  differ <- which(a != b)
  if (!length(differ)) {
    return(0L)
  }
  top <- max(differ)
  if (a[top] < b[top]) -1L else 1L
}

# Stage 5: W7090 for a document of another registry, and otherwise the rule
# that compares the parameters of the filter with the registry (E7046) and
# the rules that compare each finding with the registry entry of its check
# (E7040 to E7045 and E7025) and, in a shareable document, E7024.
results_registry_issues <- function(d) {
  if (!identical(d[["inputs"]][["registry_hash"]], registry_hash())) {
    return(list(raw_issue("W7090", "/inputs/registry_hash")))
  }
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, pointer, args)
  }
  entries <- registry_entries_by_id()
  privacy <- d[["privacy"]]
  shareable <- identical(privacy[["mode"]], "shareable")
  k <- privacy[["min_count"]]
  # The parameters of the filter equal those of the registry, so that a
  # document cannot lower the k that stage 4 reads from it.
  parameters <- read_registry()[["privacy"]]
  for (member in list("min_count", c("dominance", "contributors"), c("dominance", "share"),
                      "rounding_base", "zeros_disclosive")) {
    expected <- parameters[[member]]
    given <- privacy[[member]]
    same <- if (is.numeric(expected)) {
      is.numeric(given) && given == expected
    } else {
      identical(given, expected)
    }
    if (!same) {
      add("E7046", paste0("/privacy/", paste(member, collapse = "/")),
          list(expected = list(expected)))
    }
  }
  # Without a disclosure unit, every by_unit count is a person count
  # (registry.md, Statistics and counts).
  by_unit_class <- if (is.null(privacy[["disclosure_unit"]])) "person"
  findings <- d[["findings"]]
  for (i in seq_along(findings)) {
    finding <- findings[[i]]
    here <- paste0("/findings/", i - 1L)
    entry <- entries[[finding[["check"]]]]
    if (is.null(entry)) {
      add("E7040", paste0(here, "/check"), list(id = finding[["check"]]))
      next
    }
    if (finding[["check_version"]] != entry[["version"]]) {
      add("E7041", paste0(here, "/check_version"), list(expected = list(entry[["version"]])))
    }
    if (finding[["tier"]] != entry[["tier"]]) {
      add("E7041", paste0(here, "/tier"), list(expected = list(entry[["tier"]])))
    }
    allowed <- registry_scope_parts[[entry[["scope"]]]]
    scope <- names(finding[["scope"]])
    for (part in setdiff(scope, allowed)) {
      add("E7042", child_pointer(paste0(here, "/scope"), part),
          list(kind = "scope part", name = part))
    }
    available <- identical(finding[["status"]][["availability"]][["value"]], "available")
    if (available || length(scope)) {
      required <- allowed
      if (entry[["scope"]] == "grouping_factor_or_model") {
        required <- setdiff(required, "factor")
      }
      for (part in setdiff(required, scope)) {
        add("E7043", paste0(here, "/scope"), list(name = part))
      }
    }
    if (!available) {
      next
    }
    if (is.null(finding[["status"]][["optimisation"]]) == isTRUE(entry[["fitted_model"]])) {
      add("E7044", paste0(here, "/status"))
    }
    message_id <- finding[["message"]][["id"]]
    if (!message_id %in% names(entry[["messages"]])) {
      add("E7042", paste0(here, "/message/id"), list(kind = "message", name = message_id))
    }
    statistics <- finding[["statistics"]]
    for (name in names(statistics)) {
      statistic <- statistics[[name]]
      at <- child_pointer(paste0(here, "/statistics"), name)
      defined <- entry[["statistics"]][[name]]
      if (is.null(defined)) {
        add("E7042", at, list(kind = "statistic", name = name))
        next
      }
      if (statistic[["kind"]] != defined[["kind"]]) {
        add("E7041", paste0(at, "/kind"), list(expected = list(defined[["kind"]])))
      }
      class <- statistic[["count_class"]]
      expected <- defined[["count_class"]]
      if (identical(expected, "by_unit")) {
        expected <- by_unit_class
      }
      if (!is.null(class) && !is.null(expected) && class != expected) {
        add("E7041", paste0(at, "/count_class"), list(expected = list(expected)))
      }
      # A statistic has a quantile exactly when its entry gives it one, with
      # the entry's p, so that the quantile rule of stage 4 reaches every
      # quantile of a shareable document.
      quantile <- statistic[["quantile"]]
      if (is.null(quantile) != is.null(defined[["quantile"]])) {
        add("E7045", at)
      } else if (!is.null(quantile)) {
        p <- json_number_values(defined[["quantile"]][["p"]])
        if (quantile[["p"]] != p) {
          add("E7041", paste0(at, "/quantile/p"), list(expected = list(p)))
        }
      }
      if (shareable && identical(defined[["kind"]], "ratio") && !is.null(statistic[["value"]]) &&
          ratio_hides_count(statistics, entry, defined, statistic[["count_class"]], k)) {
        add("E7024", paste0(at, "/value"))
      }
      # The n of a quantile is written only beside the count that the entry
      # names as n, with its value, in every document.
      n <- statistic[["quantile"]][["n"]]
      count <- defined[["quantile"]][["n"]]
      if (!is.null(n) && !is.null(count)) {
        given <- statistics[[count]][["value"]]
        if (!is.numeric(given) || length(given) != 1L || given != n) {
          add("E7025", paste0(at, "/quantile/n"), list(count = count))
        }
      }
    }
  }
  issues
}

# Whether the numerator or the denominator of a ratio, as the entry names
# them, is suppressed, whatever its class, or is a person count of the
# finding that is not written or is below k. A part that the finding leaves
# out is a person count when the entry gives it the class person, or the
# class by_unit and the ratio, whose class is that of its parts, is written
# with the class person.
ratio_hides_count <- function(statistics, entry, defined, ratio_class, k) {
  for (part in c(defined[["numerator"]], defined[["denominator"]])) {
    statistic <- statistics[[part]]
    if (!is.null(statistic) && is.null(statistic[["value"]])) {
      return(TRUE)
    }
    person <- if (is.null(statistic)) {
      class <- entry[["statistics"]][[part]][["count_class"]]
      identical(class, "person") ||
        (identical(class, "by_unit") && identical(ratio_class, "person"))
    } else {
      identical(statistic[["kind"]], "count") && identical(statistic[["count_class"]], "person")
    }
    value <- statistic[["value"]]
    if (person && (is.null(value) || value < k)) {
      return(TRUE)
    }
  }
  FALSE
}

# The issues of a sidecar and of its verification against a document read in
# stage 1 whose results file hash is results_hash. Reading, version,
# structure and rules each stop at their first stage with issues, and the
# issues of verification come in the order of documents.md (Internal
# sidecar).
results_sidecar_issues <- function(sidecar, document, results_hash, data, declaration) {
  value <- tryCatch(
    read_results_input(sidecar)$value,
    mixedcheck_error = function(e) e
  )
  if (inherits(value, "mixedcheck_error")) {
    return(value$issues)
  }
  version <- if (is_json_object(value)) value[["sidecar_version"]]
  if (is.character(version) && !version_supported(version, results_version_pattern)) {
    return(list(new_issue("E1441", list(version = version, supported = "0.1.x"),
                          pointer = "/sidecar_version")))
  }
  for (stage in list(
    function(s) schema_issues(s, "urn:mixedcheck:schema:results#/$defs/sidecar"),
    sidecar_rule_issues
  )) {
    raw <- stage(value)
    if (length(raw)) {
      return(finish_issues(raw))
    }
  }
  sidecar_verification_issues(value, document, results_hash, data, declaration)
}

# The rules in code of a structurally valid sidecar: key identifiers that
# match their keys (E1321) and that differ from every earlier one (E7061), and
# pseudonyms that differ from every earlier one (E7060).
sidecar_rule_issues <- function(s) {
  issues <- list()
  key_ids <- character(0)
  for (i in seq_along(s[["keys"]])) {
    entry <- s[["keys"]][[i]]
    at <- paste0("/keys/", i - 1L, "/key_id")
    if (!identical(commitment_key_id(entry[["key"]]), entry[["key_id"]])) {
      issues <- c(issues, list(raw_issue("E1321", at)))
    }
    if (entry[["key_id"]] %in% key_ids) {
      issues <- c(issues, list(raw_issue("E7061", at, list(name = entry[["key_id"]]))))
    }
    key_ids <- c(key_ids, entry[["key_id"]])
  }
  pseudonyms <- character(0)
  for (i in seq_along(s[["pseudonyms"]])) {
    pseudonym <- s[["pseudonyms"]][[i]][["pseudonym"]]
    if (pseudonym %in% pseudonyms) {
      issues <- c(issues, list(raw_issue("E7060", paste0("/pseudonyms/", i - 1L, "/pseudonym"),
                                         list(name = pseudonym))))
    }
    pseudonyms <- c(pseudonyms, pseudonym)
  }
  issues
}

# The keyed commitments of a valid results document, with their pointers,
# in the order in which errors.md (Reporting rules) sorts locations.
results_commitments <- function(document) {
  found <- list()
  data <- document[["inputs"]][["data"]]
  for (name in names(data)) {
    found[[length(found) + 1L]] <- list(pointer = child_pointer("/inputs/data", name),
                                        commitment = data[[name]])
  }
  entries <- document[["access_log"]][["entries"]]
  for (i in seq_along(entries)) {
    outcome <- entries[[i]][["outcome"]]
    if (!is.null(outcome)) {
      found[[length(found) + 1L]] <- list(
        pointer = paste0("/access_log/entries/", i - 1L, "/outcome/commitment"),
        commitment = outcome[["commitment"]], column = outcome[["column"]]
      )
    }
  }
  pointers <- vapply(found, function(item) item$pointer, "")
  found[order(pointers, method = "radix")]
}

# Verification of a valid sidecar against a valid document: E1321 at
# /results_hash, E1313 once for each key identifier that the commitments name
# and the sidecar lacks, in the order in which they first name it, and, with
# data, E1314 at each commitment whose key the sidecar holds and that the
# data do not match, in the order of the commitments.
sidecar_verification_issues <- function(sidecar, document, results_hash, data, declaration) {
  issues <- list()
  if (!identical(sidecar[["results_hash"]], results_hash)) {
    issues <- c(issues, list(new_issue("E1321", pointer = "/results_hash")))
  }
  commitments <- results_commitments(document)
  keys <- sidecar[["keys"]]
  key_ids <- vapply(keys, function(entry) entry[["key_id"]], "")
  named <- unique(vapply(commitments, function(item) item$commitment[["key_id"]], ""))
  for (key_id in setdiff(named, key_ids)) {
    issues <- c(issues, list(new_issue("E1313", list(key_id = key_id))))
  }
  if (!is.null(data)) {
    declaration <- if (!is.null(declaration)) validate_declaration(declaration)
    run <- run_data(data, declaration)
    response <- NULL
    response_known <- TRUE
    formula <- document[["inputs"]][["model"]][["formula"]]
    if (!is.null(formula)) {
      response <- tryCatch(formula_response_key(formula), mixedcheck_error = function(e) NA)
      response_known <- !identical(response, NA)
    }
    # The digest of a message under a key, computed once for each pair of a
    # message and a key, since every tier of the access log commits to the
    # same columns.
    computed <- list()
    for (item in commitments) {
      commitment <- item$commitment
      found <- match(commitment[["key_id"]], key_ids)
      if (is.na(found)) {
        next
      }
      memo <- paste(commitment[["covers"]], found, item$column %||% "", sep = "\001")
      at <- match(memo, names(computed))
      if (!is.na(at)) {
        if (!identical(computed[[at]], commitment[["digest"]])) {
          issues <- c(issues, list(new_issue("E1314", pointer = item$pointer)))
        }
        next
      }
      message <- switch(commitment[["covers"]],
        data_file = {
          if (is.null(run$file)) {
            stop("The document commits to a data file, so 'data' must be the path of that file.",
                 call. = FALSE)
          }
          run$file
        },
        analysis_table = if (response_known) {
          analysis_table_message(run$table, declaration, response)
        },
        outcome_column = outcome_column_message(run$table, declaration, item$column)
      )
      digest <- if (!is.null(message)) hmac_sha256(hex_to_raw(keys[[found]][["key"]]), message)
      computed[[length(computed) + 1L]] <- digest %||% NA_character_
      names(computed)[length(computed)] <- memo
      if (!identical(digest, commitment[["digest"]])) {
        issues <- c(issues, list(new_issue("E1314", pointer = item$pointer)))
      }
    }
  }
  if (length(issues) > 100L) {
    issues <- c(issues[seq_len(100L)],
                list(new_issue("W1490", list(count = length(issues) - 100L))))
  }
  issues
}
