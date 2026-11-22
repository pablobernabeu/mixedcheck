# Runs the conformance corpora with the installed R package for the parity
# harness (parity/README.md).
#
# Usage: Rscript run_r.R PLAN OUTPUT RUN
#
# PLAN is the JSON file that parity.py writes, with the corpus directory, the
# corpus files to run with the kind of their cases, the identifiers of the
# directories of the pathology zoo and the vendored files of spec/ to read.
# OUTPUT receives one JSON object per line: first a header that
# describes the run, named RUN, then one record for each case and part of a
# case, with the outcome that the package gave. Every string of an outcome is
# written as the lower-case hexadecimal digits of its bytes, so that
# run_python.py and this script write identical records for identical
# outcomes. The harness reads the corpora with the package's own strict
# reader, as the package tests do, and builds every input from bytes, never
# from string literals, which a C locale would leave unmarked.

suppressPackageStartupMessages(library(mixedcheck))

language <- "R"
modes <- c("plain", "data", "hashable")

# Writing records ----------------------------------------------------------

hex <- function(bytes) paste(as.character(bytes), collapse = "")

# The outcome with every string and raw vector as hexadecimal digits. A
# character vector of another length than 1 becomes a list.
encode <- function(x) {
  if (is.raw(x)) {
    return(hex(x))
  }
  if (is.character(x)) {
    encoded <- lapply(x, function(s) hex(charToRaw(s)))
    return(if (length(x) == 1L) encoded[[1L]] else encoded)
  }
  if (is.list(x)) {
    encoded <- lapply(x, encode)
    names(encoded) <- names(x)
    return(encoded)
  }
  x
}

json_string <- function(s) {
  if (grepl("[^\\x20-\\x7E]", s, useBytes = TRUE, perl = TRUE)) {
    stop("A record holds a string that is not printable ASCII.", call. = FALSE)
  }
  paste0("\"", gsub("([\"\\\\])", "\\\\\\1", s, useBytes = TRUE), "\"")
}

# JSON text of a record whose strings are printable ASCII.
to_json <- function(x) {
  if (is.null(x)) {
    return("null")
  }
  if (is.list(x)) {
    values <- vapply(x, to_json, "")
    if (is.null(names(x))) {
      return(paste0("[", paste(values, collapse = ","), "]"))
    }
    return(paste0("{", paste0(vapply(names(x), json_string, ""), ":", values, collapse = ","), "}"))
  }
  if (length(x) != 1L) {
    stop("A record holds a vector of length ", length(x), ".", call. = FALSE)
  }
  if (is.logical(x)) {
    return(if (is.na(x)) "null" else if (x) "true" else "false")
  }
  if (is.numeric(x)) {
    if (!is.finite(x) || x != round(x) || abs(x) > 2^53) {
      stop("A record holds a number that is not an integer.", call. = FALSE)
    }
    return(sprintf("%.0f", x))
  }
  json_string(x)
}

# Outcomes -----------------------------------------------------------------

# Calls compute and returns its outcome, the issues of a mixedcheck_error or
# the text of any other error, with the issues of any mixedcheck_warning.
outcome_of <- function(compute) {
  raised <- list()
  outcome <- withCallingHandlers(
    tryCatch(
      compute(),
      mixedcheck_error = function(e) list(issues = e$issues),
      error = function(e) list(error = paste0(class(e)[1L], ": ", conditionMessage(e)))
    ),
    mixedcheck_warning = function(w) {
      raised <<- c(raised, w$issues)
      invokeRestart("muffleWarning")
    }
  )
  if (length(raised)) {
    outcome$warnings <- raised
  }
  encode(outcome)
}

unexpected <- function(message) {
  stop(structure(class = c("unexpected_outcome", "error", "condition"),
                 list(message = message, call = NULL)))
}

utf8_bytes <- function(text) charToRaw(enc2utf8(text))
hex_raw <- function(hex) mixedcheck:::hex_to_raw(hex)
bits_double <- function(bits) mixedcheck:::bits_double(bits)

# The canonical bytes of a value in a profile and its hash.
canonical <- function(value, profile) {
  list(canonical = canonical_bytes(value, profile), sha256 = canonical_hash(value, profile))
}

# The canonical bytes and hash of a value that a reader returned, which must
# be writable in the profile in which it was read.
canonical_of_value_read <- function(value, profile) {
  tryCatch(canonical(value, profile), mixedcheck_error = function(e) {
    codes <- vapply(e$issues, function(issue) issue[["code"]], "")
    unexpected(paste("writing the value read gave", paste(codes, collapse = ", ")))
  })
}

# Cases of json/, numbers/format.json and read.json and unicode/ -----------

reader_source <- function(case, scratch) {
  if (!is.null(case[["input"]])) {
    return(utf8_bytes(case[["input"]]))
  }
  if (!is.null(case[["input_hex"]])) {
    return(hex_raw(case[["input_hex"]]))
  }
  switch(case[["file"]],
    missing = file.path(scratch, "mixedcheck-no-such-file.json"),
    directory = scratch,
    stop("Unknown file case '", case[["file"]], "'.", call. = FALSE)
  )
}

pointer_tokens <- function(pointer) {
  if (identical(pointer, "")) {
    return(character(0))
  }
  tokens <- strsplit(substring(pointer, 2L), "/", fixed = TRUE)[[1L]]
  if (endsWith(pointer, "/")) {
    tokens <- c(tokens, "")
  }
  gsub("~0", "~", gsub("~1", "/", tokens, fixed = TRUE), fixed = TRUE)
}

set_at_pointer <- function(x, tokens, value) {
  if (length(tokens) == 0L) {
    return(value)
  }
  index <- if (is.null(names(x))) as.integer(tokens[1L]) + 1L else tokens[1L]
  x[[index]] <- set_at_pointer(x[[index]], tokens[-1L], value)
  x
}

substitute_value <- function(x, substitution) {
  pointer <- substitution[["pointer"]]
  replacement <- if (!is.null(substitution[["double"]])) {
    bits_double(substitution[["double"]])
  } else if (!is.null(substitution[["wrap"]])) {
    value <- mixedcheck:::json_pointer_get(x, pointer)
    for (i in seq_len(substitution[["wrap"]])) {
      value <- list(value)
    }
    value
  } else if (!is.null(substitution[["r_string"]])) {
    text <- rawToChar(hex_raw(substitution[["r_string"]][["hex"]]))
    Encoding(text) <- substitution[["r_string"]][["encoding"]]
    text
  } else {
    stop("Substitution not available in R.", call. = FALSE)
  }
  set_at_pointer(x, pointer_tokens(pointer), replacement)
}

writer_value <- function(case) {
  value <- if (!is.null(case[["double"]])) {
    bits_double(case[["double"]])
  } else {
    read_json_strict(utf8_bytes(case[["json"]]), "plain")
  }
  for (substitution in case[["substitutions"]]) {
    value <- substitute_value(value, substitution)
  }
  value
}

run_json <- function(case, context) {
  case_modes <- intersect(modes, names(case[["expected"]]))
  outcomes <- list()
  if (!is.null(case[["json"]]) || !is.null(case[["double"]])) {
    for (mode in case_modes) {
      outcomes[[mode]] <- outcome_of(function() canonical(writer_value(case), mode))
    }
    return(outcomes)
  }
  source <- reader_source(case, context$scratch)
  for (mode in case_modes) {
    outcomes[[mode]] <- outcome_of(function() {
      value <- read_json_strict(source, mode)
      outcome <- canonical_of_value_read(value, mode)
      if (!is.null(case[["expected"]][[mode]][["bits"]])) {
        outcome$bits <- mixedcheck:::double_bits(value)
      }
      outcome
    })
  }
  outcomes
}

run_decimal <- function(case, context) {
  list(value = outcome_of(function() {
    list(decimal = mixedcheck:::decimal_string(bits_double(case[["double"]]), case[["digits"]]))
  }))
}

run_normalisation <- function(case, context) {
  list(value = outcome_of(function() {
    list(normalisable = mixedcheck:::is_normalisable(case[["string"]]),
         form = mixedcheck:::comparison_form(case[["string"]]))
  }))
}

run_order <- function(case, context) {
  list(value = outcome_of(function() {
    if (!is.null(case[["first"]])) {
      list(order = mixedcheck:::compare_identifiers(case[["first"]], case[["second"]]))
    } else {
      sorted <- mixedcheck:::sort_identifiers(unlist(case[["strings"]]))
      list(sorted = as.list(sorted))
    }
  }))
}

# Cases of hash/ and hmac/ -------------------------------------------------

message_bytes <- function(case) {
  if (!is.null(case[["message_hex"]])) hex_raw(case[["message_hex"]]) else utf8_bytes(case[["message"]])
}

run_sha256 <- function(case, context) {
  bytes <- if (!is.null(case[["input_hex"]])) hex_raw(case[["input_hex"]]) else utf8_bytes(case[["input"]])
  if (!is.null(case[["repeat"]])) {
    bytes <- rep(bytes, times = case[["repeat"]])
  }
  path <- file.path(context$scratch, "sha256-input")
  list(
    memory = outcome_of(function() list(sha256 = hash_bytes(bytes))),
    file = outcome_of(function() {
      writeBin(bytes, path)
      list(sha256 = hash_file(path))
    })
  )
}

run_section <- function(case, context) {
  list(value = outcome_of(function() {
    document <- read_json_strict(utf8_bytes(case[["input"]]), "hashable")
    canonical(mixedcheck:::json_pointer_get(document, case[["pointer"]]), "hashable")
  }))
}

run_hmac <- function(case, context) {
  list(value = outcome_of(function() {
    digest <- mixedcheck:::hmac_sha256(hex_raw(case[["key_hex"]]), message_bytes(case))
    if (!is.null(case[["truncate"]])) {
      digest <- substr(digest, 1L, 2L * case[["truncate"]])
    }
    list(digest = digest)
  }))
}

run_commitment <- function(case, context) {
  list(value = outcome_of(function() {
    if (!is.null(case[["covers"]])) {
      list(commitment = keyed_commitment(message_bytes(case), case[["key"]], case[["covers"]]))
    } else {
      list(key_id = commitment_key_id(case[["key"]]))
    }
  }))
}

# Cases of declarations/ and yaml/ -----------------------------------------

run_declaration <- function(case, context) {
  path <- file.path(context$directory, case[["path"]])
  list(value = outcome_of(function() {
    value <- validate_declaration(path, minimal = isTRUE(case[["minimal"]]))
    canonical_of_value_read(value, "hashable")
  }))
}

# Cases of tables/ ---------------------------------------------------------

table_path <- function(case, context) {
  if (!is.null(case[["path"]])) {
    return(file.path(context$directory, case[["path"]]))
  }
  switch(case[["file"]],
    missing = file.path(context$scratch, "mixedcheck-no-such-file.csv"),
    directory = context$scratch,
    stop("Unknown file case '", case[["file"]], "'.", call. = FALSE)
  )
}

# Strings that a package function returned, which must be marked UTF-8 when
# they are not ASCII.
marked_strings <- function(x, what) {
  unmarked <- !is.na(x) & Encoding(x) != "UTF-8" &
    grepl("[^\\x01-\\x7F]", x, useBytes = TRUE, perl = TRUE)
  if (any(unmarked)) {
    unexpected(paste(what, "holds a string that is not marked UTF-8"))
  }
  x
}

# A double as the 16 hexadecimal digits of its bits, with negative zero as
# zero, or as 'NaN', 'Infinity' or '-Infinity', and NA as null.
real_value <- function(v) {
  if (is.nan(v)) {
    return("NaN")
  }
  if (is.na(v)) {
    return(NULL)
  }
  if (is.infinite(v)) {
    return(if (v > 0) "Infinity" else "-Infinity")
  }
  mixedcheck:::double_bits(v + 0)
}

real_values <- function(v) lapply(as.double(v), real_value)

# The values of a column as the table corpus writes them, by the class of the
# column: NA as null, strings and booleans as themselves, the doubles of an
# integer column that are integers as integers and every other double as its
# bits (real_value()).
column_values <- function(values, type, name) {
  if (is.character(values)) {
    values <- marked_strings(values, paste0("the column '", name, "'"))
    return(lapply(values, function(v) if (is.na(v)) NULL else v))
  }
  if (is.logical(values)) {
    return(lapply(values, function(v) if (is.na(v)) NULL else v))
  }
  if (is.double(values)) {
    return(lapply(values, function(v) {
      if (identical(type, "integer") && is.finite(v) && v == round(v)) v + 0 else real_value(v)
    }))
  }
  unexpected(paste0("the column '", name, "' is of class ", class(values)[1L]))
}

# The columns of a table that read_table() returned, in order, each with its
# name, its type and its values. The names of the attribute 'types' must be
# the column names.
table_columns <- function(table) {
  if (!is.data.frame(table)) {
    unexpected("read_table() did not return a data frame")
  }
  names <- marked_strings(names(table), "the column names")
  types <- attr(table, "types")
  if (!is.character(types) || !identical(names(types), names)) {
    unexpected("the attribute 'types' does not name the columns in order")
  }
  lapply(seq_along(table), function(j) {
    list(name = names[j], type = unname(types[j]),
         values = column_values(table[[j]], types[[j]], names[j]))
  })
}

# Rows of the data as row positions counted from 0, as the corpora count them.
rows_from_0 <- function(rows) as.list(as.integer(rows) - 1L)

run_table <- function(case, context) {
  path <- table_path(case, context)
  table <- NULL
  outcomes <- list(value = outcome_of(function() {
    table <<- read_table(path, case[["declaration"]])
    list(columns = table_columns(table))
  }))
  if (!is.null(case[["formula"]])) {
    outcomes$samples <- outcome_of(function() {
      if (is.null(table)) {
        unexpected("the table was not read")
      }
      ir <- formula_ir(case[["formula"]], case[["declaration"]], table)
      samples <- design_samples(ir, table)
      list(design_sample = rows_from_0(samples$design_sample),
           analysis_sample = rows_from_0(samples$analysis_sample))
    })
  }
  outcomes
}

# Cases of formulas/ -------------------------------------------------------

# The data frame of a formula case, as the package tests build it: one column
# for each member of its data, numeric, character or logical, with NA for
# null and the strings 'NaN', 'Infinity' and '-Infinity' of a numeric column
# as the special values.
formula_data_frame <- function(data) {
  special <- c("NaN" = NaN, "Infinity" = Inf, "-Infinity" = -Inf)
  columns <- lapply(data, function(values) {
    present <- Filter(Negate(is.null), values)
    # A column with a number is numeric, and its strings are special values.
    if (any(vapply(present, is.numeric, NA))) {
      return(vapply(values, function(v) {
        if (is.null(v)) NA_real_ else if (is.character(v)) special[[v]] else v
      }, 0))
    }
    if (is.character(present[[1L]])) {
      return(vapply(values, function(v) if (is.null(v)) NA_character_ else v, ""))
    }
    vapply(values, function(v) if (is.null(v)) NA else v, NA)
  })
  frame <- list2DF(unname(columns))
  names(frame) <- names(data)
  frame
}

matrix_rows <- function(m) {
  lapply(seq_len(nrow(m)), function(i) real_values(m[i, , drop = TRUE]))
}

# The design matrices as the formula corpus writes them, with the number of
# entries that Z stores.
matrices_outcome <- function(m) {
  if (!methods::is(m$z, "dgCMatrix")) {
    unexpected("Z is not a dgCMatrix")
  }
  if (!identical(as.character(colnames(m$x)), m$x_columns)) {
    unexpected("the column names of X are not x_columns")
  }
  described <- m$z_columns
  list(
    rows = rows_from_0(m$design_sample),
    x = matrix_rows(m$x),
    x_columns = as.list(marked_strings(m$x_columns, "x_columns")),
    x_dropped = as.list(marked_strings(m$x_dropped, "x_dropped")),
    z = matrix_rows(as.matrix(m$z)),
    z_columns = lapply(seq_len(nrow(described)), function(i) {
      list(term = described$term[i] - 1L,
           level = marked_strings(described$level[i], "z_columns"),
           column = marked_strings(described$column[i], "z_columns"))
    }),
    z_stored = length(m$z@x)
  )
}

run_formula <- function(case, context) {
  data <- if (!is.null(case[["data"]])) formula_data_frame(case[["data"]])
  ir <- NULL
  outcomes <- list(ir = outcome_of(function() {
    ir <<- formula_ir(case[["formula"]], case[["declaration"]], data, case[["coding"]],
                      case[["weights"]], as.character(unlist(case[["sample_columns"]])))
    canonical(ir, "hashable")
  }))
  expected <- case[["expected"]]
  # The design matrices, or the issue that they report beside the IR.
  if (is.null(expected[["matrices"]]) && (is.null(expected[["ir"]]) || is.null(expected[["issue"]]))) {
    return(outcomes)
  }
  matrices <- NULL
  outcomes$matrices <- outcome_of(function() {
    if (is.null(ir)) {
      unexpected("formula_ir() gave no IR")
    }
    matrices <<- design_matrices(ir, data)
    matrices_outcome(matrices)
  })
  if (is.null(expected[["matrices"]])) {
    return(outcomes)
  }
  outcomes$vectors <- outcome_of(function() {
    if (is.null(matrices)) {
      unexpected("design_matrices() gave no matrices")
    }
    vectors <- lapply(matrices[c("response", "trials", "offset", "weights")],
                      function(v) if (!is.null(v)) real_values(v))
    list(reals = vectors)
  })
  outcomes
}

# Cases of audits/ --------------------------------------------------------

# The commitment key 00 01 02 ... 1F of conventions.md (Keyed commitments,
# Example), with which every case of the audit corpus runs.
audit_key <- paste(sprintf("%02x", 0:31), collapse = "")
audit_arguments <- c("declaration", "family", "coding", "weights", "outcome_access", "reason",
                     "exploratory")

# The run of a case in internal mode and, for a case that expects shareable
# findings, in shareable mode, each with the commitment key 00 01 02 ... 1F
# and MIXEDCHECK_TIME set to 0: the canonical bytes in the data profile of
# the document and of the sidecar, or the issues of the error that refuses
# the run (fixtures/conformance/audits/README.md). A part that corpora.json
# marks as pending is not run.
run_audit <- function(case, context) {
  audit_in <- function(privacy) {
    function() {
      args <- list(data = formula_data_frame(case[["data"]]), formula = case[["formula"]])
      for (member in audit_arguments) {
        if (!is.null(case[[member]])) {
          args[[member]] <- case[[member]]
        }
      }
      if (!is.null(case[["sample_columns"]])) {
        args$sample_columns <- as.character(unlist(case[["sample_columns"]]))
      }
      args$privacy <- privacy
      args$key <- audit_key
      previous <- Sys.getenv("MIXEDCHECK_TIME", NA_character_)
      Sys.setenv(MIXEDCHECK_TIME = "0")
      on.exit(if (is.na(previous)) {
        Sys.unsetenv("MIXEDCHECK_TIME")
      } else {
        Sys.setenv(MIXEDCHECK_TIME = previous)
      })
      results <- do.call(audit, args)
      list(document = canonical_bytes(results$document, "data"),
           sidecar = canonical_bytes(results$sidecar, "data"))
    }
  }
  outcomes <- list(internal = outcome_of(audit_in("internal")))
  if (!is.null(case[["expected"]][["shareable"]]) &&
      is.null(context$pending_parts[["shareable"]])) {
    outcomes$shareable <- outcome_of(audit_in("shareable"))
  }
  outcomes
}

# Directories of the pathology zoo ----------------------------------------

# The run of a directory of the pathology zoo, read with pathology_zoo() from
# the installed package, in internal and in shareable mode, each with the
# commitment key 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0: the canonical
# bytes in the data profile of the document and of the sidecar, or the issues
# of the error that refuses the run (fixtures/zoo/README.md).
run_zoo <- function(id) {
  audit_in <- function(privacy) {
    function() {
      fixture <- pathology_zoo(id)
      args <- c(list(fixture$data, fixture$formula, fixture$declaration), fixture$arguments,
                list(privacy = privacy, key = audit_key))
      previous <- Sys.getenv("MIXEDCHECK_TIME", NA_character_)
      Sys.setenv(MIXEDCHECK_TIME = "0")
      on.exit(if (is.na(previous)) {
        Sys.unsetenv("MIXEDCHECK_TIME")
      } else {
        Sys.setenv(MIXEDCHECK_TIME = previous)
      })
      results <- do.call(audit, args)
      list(document = canonical_bytes(results$document, "data"),
           sidecar = canonical_bytes(results$sidecar, "data"))
    }
  }
  # The plan and the draft of the directory, at the time 0. The plan is
  # compared without its language, its package version and its bindings,
  # which belong to the language, and so is its preregistration text.
  at_zero <- function(compute) {
    function() {
      previous <- Sys.getenv("MIXEDCHECK_TIME", NA_character_)
      Sys.setenv(MIXEDCHECK_TIME = "0")
      on.exit(if (is.na(previous)) {
        Sys.unsetenv("MIXEDCHECK_TIME")
      } else {
        Sys.setenv(MIXEDCHECK_TIME = previous)
      })
      compute(pathology_zoo(id))
    }
  }
  plan <- at_zero(function(fixture) {
    args <- fixture$arguments[intersect(names(fixture$arguments),
                                        c("family", "coding", "weights", "sample_columns"))]
    found <- do.call(design_plan, c(list(fixture$data, fixture$formula, fixture$declaration),
                                    args))
    found$language <- "R"
    found$versions$package <- "0"
    found$bindings <- list()
    list(plan = canonical_bytes(found, "hashable"), text = utf8_bytes(preregistration_text(found)))
  })
  draft <- at_zero(function(fixture) {
    list(draft = canonical_bytes(draft_design(fixture$data, fixture$formula), "hashable"))
  })
  list(internal = outcome_of(audit_in("internal")),
       shareable = outcome_of(audit_in("shareable")),
       plan = outcome_of(plan),
       draft = outcome_of(draft))
}

# Cases of results/ -------------------------------------------------------

# The document alone and, for a case with a sidecar, the document with its
# sidecar, data and declaration. A call that returns gives the outcome
# 'valid', with the warning W7090 if the document records another registry.
run_results <- function(case, context) {
  path <- function(member) {
    if (!is.null(case[[member]])) file.path(context$directory, case[[member]])
  }
  outcomes <- list(document = outcome_of(function() {
    validate_results(path("document"))
    list(valid = TRUE)
  }))
  if (!is.null(case[["sidecar"]])) {
    outcomes$sidecar <- outcome_of(function() {
      validate_results(path("document"), path("sidecar"), path("data"), path("declaration"))
      list(valid = TRUE)
    })
  }
  outcomes
}

# Cases of plans/ ---------------------------------------------------------

# The plan validated by validate_plan(): 'valid' when the call returns.
run_plan <- function(case, context) {
  list(plan = outcome_of(function() {
    validate_plan(file.path(context$directory, case[["plan"]]))
    list(valid = TRUE)
  }))
}

runners <- list(
  json = run_json,
  decimal = run_decimal,
  normalisation = run_normalisation,
  order = run_order,
  sha256 = run_sha256,
  section = run_section,
  hmac = run_hmac,
  commitment = run_commitment,
  declaration = run_declaration,
  table = run_table,
  formula = run_formula,
  audit = run_audit,
  results = run_results,
  plan = run_plan
)

# Reads each vendored file of spec/ installed with the package in the data
# profile, and the registry and the versions as the package loads them.
run_artefacts <- function(artefacts) {
  records <- lapply(artefacts, function(name) {
    outcome <- outcome_of(function() {
      path <- system.file("spec", name, package = "mixedcheck")
      if (!nzchar(path)) {
        unexpected(paste0("spec/", name, " is not installed"))
      }
      canonical_of_value_read(read_json_strict(path, "data"), "data")
    })
    list(file = "artefacts", id = name, part = "data", outcome = outcome)
  })
  c(records, list(
    list(file = "artefacts", id = "read_registry()", part = "hashable",
         outcome = outcome_of(function() canonical(read_registry(), "hashable"))),
    list(file = "artefacts", id = "spec_versions()", part = "value",
         outcome = outcome_of(function() list(value = spec_versions())))
  ))
}

main <- function(args) {
  if (length(args) != 3L) {
    stop("Usage: Rscript run_r.R PLAN OUTPUT RUN", call. = FALSE)
  }
  plan <- jsonlite::fromJSON(args[1L], simplifyVector = FALSE)
  corpus <- plan$corpus
  scratch <- tempfile("mixedcheck-parity-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  header <- list(
    run = args[3L],
    language = language,
    package = as.character(utils::packageVersion("mixedcheck")),
    interpreter = R.version.string,
    yaml = if (requireNamespace("yaml", quietly = TRUE)) as.character(utils::packageVersion("yaml")),
    locale = Sys.getlocale("LC_CTYPE"),
    utf8 = isTRUE(l10n_info()[["UTF-8"]])
  )
  lines <- to_json(header)
  for (corpus_file in plan$corpora) {
    name <- corpus_file$file
    context <- list(scratch = scratch, directory = file.path(corpus, dirname(name)),
                    pending_parts = corpus_file$pending_parts)
    cases <- tryCatch(read_json_strict(file.path(corpus, name), "data")[["cases"]],
                      error = function(e) e)
    if (inherits(cases, "error")) {
      error <- paste("The corpus file cannot be read:", conditionMessage(cases))
      lines <- c(lines, to_json(list(file = name, id = NULL, part = NULL,
                                     outcome = list(error = hex(charToRaw(error))))))
      next
    }
    runner <- runners[[corpus_file$kind]]
    for (case in cases) {
      if (!is.null(case[["languages"]]) && !(language %in% unlist(case[["languages"]]))) {
        next
      }
      outcomes <- runner(case, context)
      for (part in names(outcomes)) {
        lines <- c(lines, to_json(list(file = name, id = case[["id"]],
                                       part = part, outcome = outcomes[[part]])))
      }
    }
  }
  for (id in unlist(plan$zoo)) {
    outcomes <- run_zoo(id)
    for (part in names(outcomes)) {
      lines <- c(lines, to_json(list(file = "zoo", id = id, part = part,
                                     outcome = outcomes[[part]])))
    }
  }
  for (record in run_artefacts(unlist(plan$artefacts))) {
    lines <- c(lines, to_json(record))
  }
  con <- file(args[2L], "wb")
  on.exit(close(con), add = TRUE)
  writeLines(lines, con, sep = "\n", useBytes = TRUE)
}

main(commandArgs(trailingOnly = TRUE))
