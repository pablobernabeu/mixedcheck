# Runs the inputs of the differential test with the installed R package
# (parity/README.md, Differential test).
#
#   Rscript parity/differential/run_r.R INPUTS OUTPUT SHARD SHARDS [ONLY]
#
# INPUTS is the directory that inputs.R wrote. The runner takes the files of
# inputs whose position in index.json, counted from 0, leaves the remainder
# SHARD when divided by SHARDS, and with ONLY, a file with one identifier on
# each line, only the inputs it names. It runs audit() on each input in
# internal and in shareable mode, at the input's k, with the commitment key
# 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0, and writes to OUTPUT, compressed
# with gzip, a header and one JSON object per line for each input and mode.
# The outcome of a run is the canonical bytes in the data profile of the
# document without the members that record what wrote it (created, software
# and the package version in versions), which conventions.md does not compare
# across languages, and of the sidecar, or the issues of the error that
# refuses the run, or the text of any other error, with the issues of any
# warning. Every string of an outcome is written as the hexadecimal digits of
# its UTF-8 bytes, as parity/run_r.R writes them.

suppressPackageStartupMessages(library(mixedcheck))

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(4L, 5L)) {
  stop("Usage: Rscript run_r.R INPUTS OUTPUT SHARD SHARDS [ONLY]", call. = FALSE)
}
inputs_dir <- args[1L]
output <- args[2L]
shard <- as.integer(args[3L])
shards <- as.integer(args[4L])
only <- if (length(args) == 5L) readLines(args[5L], warn = FALSE) else NULL
modes <- c("internal", "shareable")
key <- paste(sprintf("%02x", 0:31), collapse = "")
ns <- asNamespace("mixedcheck")

# --- Records -----------------------------------------------------------------------

hex <- function(bytes) paste(as.character(bytes), collapse = "")

encode <- function(x) {
  if (is.raw(x)) {
    return(hex(x))
  }
  if (is.character(x)) {
    encoded <- lapply(x, function(s) hex(charToRaw(enc2utf8(s))))
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

# JSON text of a record whose strings are printable ASCII and whose numbers
# are integers.
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

# --- Inputs ------------------------------------------------------------------------

special <- c("NaN" = NaN, "Infinity" = Inf, "-Infinity" = -Inf, "-0" = -0)

# The data frame of an input, each column of the R type that it states.
input_frame <- function(columns) {
  values <- lapply(columns, function(column) {
    v <- column$values
    switch(column$type,
      double = vapply(v, function(x) {
        if (is.null(x)) NA_real_ else if (is.character(x)) special[[x]] else as.double(x)
      }, 0),
      integer = vapply(v, function(x) if (is.null(x)) NA_integer_ else as.integer(x), 0L),
      logical = vapply(v, function(x) if (is.null(x)) NA else x, NA),
      string = vapply(v, function(x) if (is.null(x)) NA_character_ else x, ""),
      factor = factor(vapply(v, function(x) if (is.null(x)) NA_character_ else x, ""),
                      levels = unlist(column$levels)),
      stop(sprintf("Unknown column type '%s'.", column$type), call. = FALSE))
  })
  frame <- list2DF(values)
  names(frame) <- vapply(columns, function(column) column$name, "")
  frame
}

# Sets the minimum count of the registry that the session read, which the
# filter, the document's /privacy and the validator read, as the
# disclosure-attack harness does.
set_k <- function(k) {
  registry <- ns$read_registry()
  registry$privacy$min_count <- k
  assign("registry", registry, envir = ns$mixedcheck_cache)
}

run_input <- function(input) {
  set_k(input$k)
  data <- input_frame(input$data)
  arguments <- input$arguments
  for (name in c("weights", "sample_columns")) {
    if (!is.null(arguments[[name]])) {
      arguments[[name]] <- as.character(unlist(arguments[[name]]))
    }
  }
  records <- list()
  for (mode in modes) {
    started <- proc.time()[["elapsed"]]
    outcome <- outcome_of(function() {
      results <- do.call(audit, c(list(data, input$formula), arguments,
                                  list(privacy = mode, key = key)))
      document <- results$document
      document$created <- NULL
      document$software <- NULL
      document$versions$package <- NULL
      list(document = canonical_bytes(document, "data"),
           sidecar = canonical_bytes(results$sidecar, "data"))
    })
    milliseconds <- round(1000 * (proc.time()[["elapsed"]] - started))
    records[[mode]] <- to_json(list(id = input$id, mode = mode, milliseconds = milliseconds,
                                    outcome = outcome))
  }
  records
}

# --- Main --------------------------------------------------------------------------

Sys.setenv(MIXEDCHECK_TIME = "0")
index <- read_json_strict(file.path(inputs_dir, "index.json"), "data")
chunks <- index$chunks
mine <- which((seq_along(chunks) - 1L) %% shards == shard)
header <- list(
  run = "R", language = "R",
  package = as.character(utils::packageVersion("mixedcheck")),
  registry_hash = ns$registry_hash(),
  interpreter = R.version.string,
  locale = Sys.getlocale("LC_CTYPE"),
  utf8 = isTRUE(l10n_info()[["UTF-8"]])
)
con <- gzfile(output, "wb")
writeLines(to_json(header), con, sep = "\n", useBytes = TRUE)
for (j in mine) {
  chunk <- chunks[[j]]
  if (!is.null(only) && !any(unlist(chunk$ids) %in% only)) {
    next
  }
  inputs <- read_json_strict(file.path(inputs_dir, chunk$file), "data")$inputs
  for (input in inputs) {
    if (!is.null(only) && !input$id %in% only) {
      next
    }
    writeLines(unlist(run_input(input)), con, sep = "\n", useBytes = TRUE)
  }
}
close(con)
