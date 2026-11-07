cat("locale:", Sys.getlocale("LC_CTYPE"), " l10n_info UTF-8:", l10n_info()$`UTF-8`, "\n")
canon <- '{"a":"é","schema_version":"0.1.0","units":[{"name":"pupil"}]}'
b <- charToRaw(enc2utf8(canon)); cat("bytes:", length(b), "first non-ASCII:", paste(b[b > as.raw(127)], collapse = " "), "\n")
cat("digest(raw, serialize=FALSE):", digest::digest(b, algo = "sha256", serialize = FALSE), "\n")
tf <- tempfile(); writeBin(b, tf); cat("digest(file):", digest::digest(tf, algo = "sha256", file = TRUE), "\n")
cat("cli::hash_raw_sha256(raw):", cli::hash_raw_sha256(b), "\n")
nfd <- "é"
cat("nfd bytes:", paste(charToRaw(nfd), collapse = " "), "\n")
u <- utf8::utf8_normalize(nfd); s <- stringi::stri_trans_nfc(nfd)
cat("utf8 NFC bytes:", paste(charToRaw(enc2utf8(u)), collapse = " "), " stringi NFC bytes:", paste(charToRaw(enc2utf8(s)), collapse = " "), "\n")
cat("bytes equal to c3 a9:", identical(charToRaw(enc2utf8(u)), as.raw(c(0xc3, 0xa9))), identical(charToRaw(enc2utf8(s)), as.raw(c(0xc3, 0xa9))), "\n")
