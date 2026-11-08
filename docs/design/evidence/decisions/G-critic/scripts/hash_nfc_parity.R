# Runtime routes to SHA-256 and NFC in R without digest/stringi (used by key E's prototype),
# compared at the byte level with Python (hashlib, unicodedata). Run under C and C.UTF-8 locales.
cat("R:", R.version.string, "| LC_CTYPE:", Sys.getlocale("LC_CTYPE"), "\n")
cat("tools::sha256sum available (added in R 4.5.0):", exists("sha256sum", envir = asNamespace("tools")), "\n")
canon <- '{"a":"é"}'; Encoding(canon) <- "UTF-8"   # as a strict reader would mark it
cat("cli", as.character(packageVersion("cli")), "hash_sha256(marked string):", cli::hash_sha256(canon), "\n")
nfd <- "é"; Encoding(nfd) <- "UTF-8"
cat("utf8", as.character(packageVersion("utf8")), "utf8_normalize(e+U+0301) bytes:", paste(charToRaw(utf8::utf8_normalize(nfd)), collapse = " "), "(NFC e-acute = c3 a9)\n")
