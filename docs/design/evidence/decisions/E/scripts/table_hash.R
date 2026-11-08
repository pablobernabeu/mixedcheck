# R counterpart of table_hash.py: parse data.csv with declared types, missing
# tokens and category order, then hash the RFC 8785 canonical form.
# Usage: Rscript table_hash.R <zoo_dir>
suppressPackageStartupMessages({library(jsonlite); library(digest)})
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))
src <- readLines(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE))), "decl_read.R"))
eval(parse(text = src[seq_len(grep("^read_declaration <- function", src) - 1)]))  # reuse jcs helpers

jcs_cell <- function(v) if (is.na(v)) "null" else if (is.numeric(v)) jcs_number(v) else jcs_string(v)
jcs_col <- function(x) paste0("[", paste(vapply(x, jcs_cell, character(1)), collapse = ","), "]")
obj <- function(named) {
  if (!length(named)) return("{}")
  o <- order(names(named), method = "radix")
  paste0("{", paste(vapply(o, function(i) paste0(jcs_string(names(named)[i]), ":", named[[i]]), ""), collapse = ","), "}")
}
for (fid in sort(list.files(commandArgs(trailingOnly = TRUE)[1]))) {
  dir <- file.path(commandArgs(trailingOnly = TRUE)[1], fid)
  des <- parse_json(paste(readLines(file.path(dir, "design.json"), encoding = "UTF-8", warn = FALSE), collapse = "\n"),
                    simplifyVector = FALSE)
  na <- vapply(des$table$missingValues, function(m) if (is.list(m)) m$value else m, "")
  d <- read.csv(file.path(dir, "data.csv"), colClasses = "character", na.strings = character(0),
                encoding = "UTF-8", check.names = FALSE)
  cols <- list(); lev <- list()
  for (f in des$table$fields) {
    x <- d[[f$name]]; x[x %in% na] <- NA
    t <- if (is.null(f$type)) "string" else f$type
    if (t == "integer") x <- as.integer(x) else if (t == "number") x <- as.numeric(x)
    cols[[f$name]] <- jcs_col(x)
    if (!is.null(f$categories)) {
      lv <- lapply(f$categories, function(c) if (is.list(c)) c$value else c)
      stopifnot(all(x[!is.na(x)] %in% unlist(lv)))
      lev[[f$name]] <- paste0("[", paste(vapply(lv, jcs_cell, ""), collapse = ","), "]")
    }
  }
  canon <- obj(list(columns = obj(cols), levels = obj(lev), nrow = as.character(nrow(d))))
  cat(fid, "\t", digest(charToRaw(enc2utf8(canon)), algo = "sha256", serialize = FALSE), "\n", sep = "")
}
