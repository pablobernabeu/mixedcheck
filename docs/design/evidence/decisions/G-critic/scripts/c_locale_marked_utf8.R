# In a C locale, does marking strings as UTF-8 (as a strict reader would) avoid the <xx> corruption?
x <- '{"a":"é"}'; Encoding(x) <- "UTF-8"
cat("locale:", Sys.getlocale("LC_CTYPE"), "| marked:", Encoding(x), "\n")
cat("enc2utf8 bytes:", paste(charToRaw(enc2utf8(x)), collapse = " "), "\n")
cat("toJSON round trip bytes:", paste(charToRaw(enc2utf8(as.character(jsonlite::toJSON(jsonlite::fromJSON(x), auto_unbox = TRUE)))), collapse = " "), "\n")
tf <- tempfile(fileext = ".csv"); writeBin(charToRaw('id,y\nécole,1\n'), tf)
d1 <- read.csv(tf); d2 <- read.csv(tf, encoding = "UTF-8"); d3 <- read.csv(tf, fileEncoding = "UTF-8")
cat("read.csv default Encoding:", Encoding(d1$id), "| encoding='UTF-8':", Encoding(d2$id), "| fileEncoding='UTF-8':", Encoding(d3$id), "\n")
cat("factor level bytes after enc2utf8 (default read):", paste(charToRaw(enc2utf8(d1$id)), collapse = " "), "\n")
