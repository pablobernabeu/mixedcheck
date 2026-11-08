canon <- '{"a":"é"}'
cat("locale:", Sys.getlocale("LC_CTYPE"), "| Encoding:", Encoding(canon), "| nchar bytes:", nchar(canon, "bytes"), "\n")
cat("charToRaw(canon):", paste(charToRaw(canon), collapse=" "), "\n")
e <- enc2utf8(canon)
cat("Encoding(enc2utf8):", Encoding(e), "| charToRaw(enc2utf8(canon)):", paste(charToRaw(e), collapse=" "), "\n")
cat("cli::hash_sha256(canon):", cli::hash_sha256(canon), "\n")
cat("cli::hash_raw_sha256(charToRaw(canon)):", cli::hash_raw_sha256(charToRaw(canon)), "\n")
cat("digest(charToRaw(canon)):", digest::digest(charToRaw(canon), algo = "sha256", serialize = FALSE), "\n")
cat("jsonlite::toJSON round trip:", as.character(jsonlite::toJSON(jsonlite::fromJSON(canon), auto_unbox = TRUE)), "\n")
