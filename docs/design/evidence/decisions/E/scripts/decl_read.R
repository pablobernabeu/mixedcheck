# Reference R reader for design declarations (prototype), mirroring decl_read.py.
# Strict reading: UTF-8 without BOM, NFC strings, no duplicate keys, no null,
# then RFC 8785 (JCS) canonical serialisation and SHA-256.
# Schema validation is NOT done here (no JSON Schema validator without V8);
# the packages would generate their structural checks from the schema instead.
# Usage: Rscript decl_read.R <file.json> [<file.json> ...]
suppressPackageStartupMessages({library(jsonlite); library(digest); library(stringi)})
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))  # avoid <U+xxxx> escapes in paste()

decl_error <- function(msg) stop(structure(class = c("decl_error", "error", "condition"),
                                           list(message = msg, call = NULL)))

walk <- function(x, path = "$") {
  if (is.null(x)) decl_error(paste("null at", path))
  if (is.list(x)) {
    nm <- names(x)
    if (!is.null(nm)) {
      if (anyDuplicated(nm)) decl_error(paste("duplicate key(s):", paste(unique(nm[duplicated(nm)]), collapse = ", ")))
      if (any(stri_trans_nfc(nm) != nm)) decl_error(paste("key not in NFC at", path))
    }
    for (i in seq_along(x)) {
      if (is.null(x[[i]])) decl_error(paste("null at", paste0(path, if (is.null(nm)) paste0("[", i - 1, "]") else paste0(".", nm[i]))))
      walk(x[[i]], if (is.null(nm)) paste0(path, "[", i - 1, "]") else paste0(path, ".", nm[i]))
    }
  } else if (is.character(x)) {
    if (any(stri_trans_nfc(x) != x)) decl_error(paste("string not in NFC at", path))
  }
  invisible(TRUE)
}

jcs_string <- function(s) {
  cp <- utf8ToInt(enc2utf8(s))
  out <- vapply(cp, function(c) {
    if (c == 0x22) "\\\"" else if (c == 0x5C) "\\\\" else if (c == 0x08) "\\b" else
    if (c == 0x0C) "\\f" else if (c == 0x0A) "\\n" else if (c == 0x0D) "\\r" else
    if (c == 0x09) "\\t" else if (c < 0x20) sprintf("\\u%04x", c) else intToUtf8(c)
  }, character(1))
  paste0("\"", paste(out, collapse = ""), "\"")
}

jcs_number <- function(x) {
  if (!is.finite(x)) decl_error("non-finite number")
  if (x == 0) return("0")
  if (x == trunc(x) && abs(x) < 1e21) return(format(x, scientific = FALSE, trim = TRUE))
  # shortest round-trip digits, then ECMAScript layout for 1e-7 < |x| < 1e21
  for (p in 1:17) { s <- formatC(x, digits = p, format = "g"); if (as.numeric(s) == x) break }
  if (abs(x) >= 1e-6) return(format(x, digits = p, scientific = FALSE, trim = TRUE))
  decl_error("number outside the range this prototype serialises")
}

jcs <- function(x) {
  if (is.list(x)) {
    nm <- names(x)
    if (!is.null(nm)) {                         # object (named list, possibly empty)
      if (!length(x)) return("{}")
      # JCS sorts keys by UTF-16 code units; for keys without supplementary-plane
      # characters this equals code-point order, which C-locale radix sort gives.
      o <- order(nm, method = "radix")
      return(paste0("{", paste(vapply(o, function(i) paste0(jcs_string(nm[i]), ":", jcs(x[[i]])), character(1)), collapse = ","), "}"))
    }
    return(paste0("[", paste(vapply(x, jcs, character(1)), collapse = ","), "]"))
  }
  if (length(x) != 1) decl_error("unexpected vector")
  if (is.logical(x)) return(if (x) "true" else "false")
  if (is.numeric(x)) return(jcs_number(x))
  if (is.character(x)) return(jcs_string(x))
  decl_error(paste("unsupported type", class(x)[1]))
}

read_declaration <- function(path) {
  raw <- readBin(path, "raw", file.info(path)$size)
  if (length(raw) >= 3 && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) decl_error("byte-order mark")
  txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) decl_error("invalid UTF-8")
  doc <- parse_json(txt, simplifyVector = FALSE)
  walk(doc)
  canon <- jcs(doc)
  list(doc = doc, canon = canon,
       sha256 = digest(charToRaw(enc2utf8(canon)), algo = "sha256", serialize = FALSE))
}

for (f in commandArgs(trailingOnly = TRUE)) {
  r <- tryCatch(read_declaration(f), decl_error = function(e) e,
                error = function(e) structure(list(message = conditionMessage(e)), class = "decl_error"))
  if (inherits(r, "decl_error")) cat(basename(f), "\terror\t-\t", r$message, "\n", sep = "")
  else cat(basename(f), "\tok\t", r$sha256, "\t", nchar(r$canon, type = "bytes"), " bytes\n", sep = "")
}
