# Data-derived strings: read a UTF-8 CSV with a non-ASCII ID in the session's locale, then hash as the E prototype does.
tf <- tempfile(fileext = ".csv"); writeBin(charToRaw('id,y\nécole,1\n'), tf)
d1 <- read.csv(tf); d2 <- read.csv(tf, encoding = "UTF-8")
h <- function(s) cli::hash_raw_sha256(charToRaw(enc2utf8(s)))
cat(Sys.getlocale("LC_CTYPE"), "| default read: Encoding", Encoding(d1$id), "bytes after enc2utf8:", paste(charToRaw(enc2utf8(d1$id)), collapse = " "), "| sha:", substr(h(d1$id), 1, 12), "\n")
cat(Sys.getlocale("LC_CTYPE"), "| encoding='UTF-8': Encoding", Encoding(d2$id), "bytes after enc2utf8:", paste(charToRaw(enc2utf8(d2$id)), collapse = " "), "| sha:", substr(h(d2$id), 1, 12), "\n")
cat("jsonlite default-read:", as.character(jsonlite::toJSON(d1$id)), " marked:", as.character(jsonlite::toJSON(d2$id)), "\n")
