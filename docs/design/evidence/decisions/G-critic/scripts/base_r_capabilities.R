cat("R:", R.version.string, "\n")
tl <- ls(asNamespace("tools"))
cat("tools sha256-like functions:", paste(grep("sha|md5", tl, value = TRUE, ignore.case = TRUE), collapse = ", "), "\n")
base_fns <- c(ls(baseenv()), tl, ls(asNamespace("utils")))
cat("functions matching normali[sz]e / nfc / nfd:", paste(grep("normali[sz]e|nfc|nfd|unorm", base_fns, value = TRUE, ignore.case = TRUE), collapse = ", "), "\n")
# Does iconv offer a normalisation target on this platform?
cat("iconv targets containing 'NFC' or 'MAC':", paste(grep("NFC|UTF-8-MAC", iconvlist(), value = TRUE), collapse = ", "), "\n")
x <- "é"  # e + combining acute (NFD)
y <- "é"        # precomposed (NFC)
cat("NFD == NFC in base R comparison:", identical(x, y), " nchar:", nchar(x), nchar(y), "\n")
for (p in c("cli", "openssl", "digest", "utf8", "stringi", "yaml", "whisker", "jsonlite")) {
  ok <- requireNamespace(p, quietly = TRUE)
  cat(sprintf("%-9s installed=%s %s\n", p, ok,
              if (ok) paste(utils::packageDescription(p)$Version, utils::packageDescription(p)$License) else ""))
}
