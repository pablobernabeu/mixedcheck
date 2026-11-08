# Targeted tests of the strict reader and the serialiser, beyond the cases of
# the JSON corpus. Non-ASCII strings are built with intToUtf8(), never from
# literals, which a C locale would leave unmarked.

issue_of <- function(expr) {
  tryCatch({
    force(expr)
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

text_bytes <- function(text) charToRaw(text)

test_that("the reader returns lists, doubles, logicals, NULL and strings marked UTF-8", {
  e_acute <- intToUtf8(0xE9)
  input <- c(text_bytes('{"a":[1,2.5,true,null,{}],"b":"caf'), charToRaw(e_acute),
             text_bytes('","c":[],"d":{"x":-0}}'))
  value <- read_json_strict(input, "data")
  expect_named(value, c("a", "b", "c", "d"))
  expect_identical(value$a[1:2], list(1, 2.5))
  expect_type(value$a[[1L]], "double")
  expect_true(value$a[[3L]])
  expect_null(value$a[[4L]])
  expect_length(value$a, 5L)
  expect_identical(value$a[[5L]], setNames(list(), character(0)))
  expect_identical(Encoding(value$b), "UTF-8")
  expect_identical(utf8ToInt(value$b), c(99L, 97L, 102L, 0xE9L))
  expect_identical(value$c, list())
  expect_null(names(value$c))
  expect_identical(value$d$x, 0)
})

test_that("the reader keeps the order of members and reads a top-level scalar", {
  value <- read_json_strict(text_bytes('{"z":1,"a":2}'), "hashable")
  expect_named(value, c("z", "a"))
  expect_identical(read_json_strict(text_bytes(" \"x\" "), "plain"), "x")
  expect_identical(read_json_strict(text_bytes("12"), "hashable"), 12)
  expect_null(read_json_strict(text_bytes("null"), "data"))
})

test_that("the reader reads files and reports missing and unreadable ones", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(text_bytes('{"a": "b"}'), path)
  expect_identical(read_json_strict(path, "hashable"), list(a = "b"))
  expect_identical(issue_of(read_json_strict(paste0(path, "-missing")))$code, "E1001")
  expect_identical(issue_of(read_json_strict(tempdir()))$code, "E1002")
  expect_error(read_json_strict(1), "file path or a raw vector")
  expect_error(read_json_strict(c("a", "b")), "file path or a raw vector")
  expect_error(read_json_strict(raw(0), "strict"))
  # Only the exact names of the profiles are accepted, as in Python.
  message <- "'profile' must be 'data', 'hashable' or 'plain'."
  expect_error(read_json_strict(charToRaw("[1]"), "pl"), message, fixed = TRUE)
  expect_error(canonical_bytes(list(a = 1), "hash"), message, fixed = TRUE)
  expect_error(canonical_hash(list(a = 1), "d"), message, fixed = TRUE)
  expect_error(canonical_bytes(list(a = 1), c("data", "plain")), message, fixed = TRUE)
  expect_error(canonical_bytes(list(a = 1), NA_character_), message, fixed = TRUE)
  expect_error(read_json_strict(charToRaw("[1]"), NULL), message, fixed = TRUE)
  expect_identical(read_json_strict(charToRaw("[1]")), list(1))
})

test_that("an error carries its issue as a condition of class mixedcheck_error", {
  condition <- tryCatch(read_json_strict(text_bytes('{"a":1,"a":2}')),
                        error = function(e) e)
  expect_s3_class(condition, c("mixedcheck_error", "error", "condition"))
  expect_identical(conditionMessage(condition), "Duplicate key 'a' at byte 7.")
  expect_identical(condition$issues,
                   list(list(code = "E1029", message = "Duplicate key 'a' at byte 7.",
                             offset = 7L)))
})

test_that("the reader handles escapes across many strings at once", {
  input <- text_bytes(paste0(
    '["\\\\", "\\\\\\"", "a\\u00e9\\ud83d\\ude00", "\\\\u0041", "\\n\\t\\/", "\\\\\\\\",',
    ' "\\ud800\\udc00\\u0041"]'
  ))
  value <- read_json_strict(input, "plain")
  expect_identical(lapply(value, utf8ToInt), list(
    92L, c(92L, 34L), c(97L, 0xE9L, 0x1F600L), c(92L, 117L, 48L, 48L, 52L, 49L),
    c(10L, 9L, 47L), c(92L, 92L), c(0x10000L, 65L)
  ))
  # A high surrogate at the end of one string is not paired with a low one at
  # the start of the next.
  expect_identical(issue_of(read_json_strict(text_bytes('["\\ud800","\\udc00"]'), "plain")),
                   list(code = "E1026", message = "Unpaired surrogate escape in a string at byte 1.",
                        offset = 1L))
})

test_that("the reader reads a large document", {
  item <- '{"check":"structure.cluster_sizes","value":0.30000000000000004,"labels":["a","b\\"c"]}'
  input <- text_bytes(paste0("[", paste(rep(item, 20000L), collapse = ","), "]"))
  value <- read_json_strict(input, "data")
  expect_length(value, 20000L)
  expect_identical(value[[20000L]]$labels[[2L]], "b\"c")
  expect_identical(canonical_bytes(value, "data"),
                   text_bytes(paste0("[", paste(rep(
                     '{"check":"structure.cluster_sizes","labels":["a","b\\"c"],"value":0.30000000000000004}',
                     20000L), collapse = ","), "]")))
})

test_that("the writer refuses values that have no JSON form", {
  code_of <- function(x, profile = "data") issue_of(canonical_bytes(x, profile))
  expect_identical(code_of(list(a = factor("x"))),
                   list(code = "E1301", message = "The value at /a has the type 'factor', which has no JSON form.",
                        pointer = "/a"))
  expect_identical(code_of(list(Sys.Date()))$code, "E1301")
  expect_identical(code_of(data.frame(a = 1))$code, "E1301")
  expect_identical(code_of(list(matrix(1)))$code, "E1301")
  expect_identical(code_of(list(sum))$message,
                   "The value at /0 has the type 'builtin', which has no JSON form.")
  expect_identical(code_of(list(1i))$code, "E1301")
  expect_identical(code_of(list(as.raw(1)))$code, "E1301")
  expect_identical(code_of(list(1:2)),
                   list(code = "E1302",
                        message = "The vector at /0 has length 2. Wrap the values in a list to write a JSON array.",
                        pointer = "/0"))
  expect_identical(code_of(list(a = character(0)))$code, "E1302")
  expect_identical(code_of(setNames(list(1, 2), c("a", NA)))$code, "E1303")
  expect_identical(code_of(setNames(list(1, 2), c("a", "")))$code, "E1303")
  expect_identical(code_of(setNames(list(1, 2), c("a", "a")))$message,
                   "The list at (root) has missing, empty or duplicated names.")
})

test_that("the writer reports the first problem in canonical order", {
  value <- list(b = list(NaN), a = list(x = NULL, w = 1:2))
  expect_identical(issue_of(canonical_bytes(value, "hashable"))$pointer, "/a/w")
  expect_identical(issue_of(canonical_bytes(value, "data"))$pointer, "/a/w")
  value$a$w <- 1L
  expect_identical(issue_of(canonical_bytes(value, "hashable"))$pointer, "/a/x")
  expect_identical(rawToChar(canonical_bytes(value, "data")), '{"a":{"w":1,"x":null},"b":["NaN"]}')
  # A string refused after the walk still loses to an earlier problem.
  bytes_marked <- rawToChar(as.raw(c(0xC3, 0xA9)))
  Encoding(bytes_marked) <- "bytes"
  value <- list(a = list(b = bytes_marked), c = list(1, 2))
  expect_identical(issue_of(canonical_bytes(value, "data"))$code, "E1205")
  value$c <- factor("x")
  expect_identical(issue_of(canonical_bytes(value, "data"))$pointer, "/a/b")
})

test_that("the writer writes missing values and non-finite numbers by profile", {
  value <- list(NA, NA_integer_, NA_real_, NA_character_, NULL, NaN, Inf, -Inf, 3L, FALSE)
  expect_identical(rawToChar(canonical_bytes(value, "data")),
                   '[null,null,null,null,null,"NaN","Infinity","-Infinity",3,false]')
  expect_identical(rawToChar(canonical_bytes(value, "plain")),
                   '[null,null,null,null,null,"NaN","Infinity","-Infinity",3,false]')
  expect_identical(issue_of(canonical_bytes(list(Inf), "hashable"))$code, "E1107")
  expect_identical(issue_of(canonical_bytes(list(NA_character_), "hashable"))$code, "E1101")
  expect_identical(rawToChar(canonical_bytes(c(a = "x"), "hashable")), '"x"')
})

test_that("the writer converts latin1 names and sorts keys by UTF-16 code units", {
  latin1_key <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xE9)))
  Encoding(latin1_key) <- "latin1"
  value <- setNames(list(1, 2), c(latin1_key, "b"))
  expected <- c(text_bytes('{"b":2,"caf'), as.raw(c(0xC3, 0xA9)), text_bytes('":1}'))
  expect_identical(canonical_bytes(value, "hashable"), expected)
  keys <- c(intToUtf8(0xFF08), intToUtf8(0x1F600), "a")
  bytes <- canonical_bytes(setNames(list(1, 2, 3), keys), "plain")
  expect_identical(utf8ToInt(rawToChar(bytes))[c(3L, 9L, 15L)], c(97L, 0x1F600L, 0xFF08L))
  expect_identical(issue_of(canonical_bytes(setNames(list(1), keys[2L]), "data"))$code, "E1108")
})

test_that("unmarked non-ASCII names are refused at the pointer of their object", {
  unmarked <- rawToChar(as.raw(c(0x61, 0xE9)))
  value <- list(x = setNames(list(1), unmarked))
  expect_identical(issue_of(canonical_bytes(value, "plain")),
                   list(code = "E1204",
                        message = paste("The string at /x contains non-ASCII bytes but no declared",
                                        "encoding. Mark it as UTF-8 with Encoding() or read the",
                                        "data with encoding = 'UTF-8'."),
                        pointer = "/x"))
})

test_that("canonical bytes do not depend on the order of members or the profile", {
  a <- list(b = list(1, "x"), a = TRUE)
  b <- list(a = TRUE, b = list(1, "x"))
  expect_identical(canonical_bytes(a, "hashable"), canonical_bytes(b, "plain"))
  expect_identical(canonical_hash(a, "hashable"),
                   hash_bytes(charToRaw('{"a":true,"b":[1,"x"]}')))
  expect_identical(canonical_bytes(read_json_strict(canonical_bytes(a)), "data"),
                   canonical_bytes(a))
})

test_that("objects whose keys take more than 10,000 bytes together are written", {
  keys <- sprintf("k%09d", 1:1000)
  value <- setNames(as.list(rep(1, 1000)), rev(keys))
  bytes <- canonical_bytes(value, "hashable")
  expected <- paste0("{", paste0("\"", keys, "\":1", collapse = ","), "}")
  expect_identical(rawToChar(bytes), expected)
  # Repeated sets of keys, short and long, give the same bytes each time.
  rows <- list(value, value, list(a = 1, b = 2), list(b = 2, a = 1))
  text <- rawToChar(canonical_bytes(rows, "plain"))
  expect_identical(text, paste0("[", expected, ",", expected, ",{\"a\":1,\"b\":2},{\"a\":1,\"b\":2}]"))
})

test_that("a value that starts with 'e' is an unexpected character, not a number", {
  expect_identical(issue_of(read_json_strict(charToRaw("[e]"), "plain"))$code, "E1022")
  expect_identical(issue_of(read_json_strict(charToRaw("E5"), "data"))$message,
                   "Unexpected character 'E' at byte 0.")
  expect_identical(issue_of(read_json_strict(charToRaw("[1e]"), "data"))$code, "E1028")
})
