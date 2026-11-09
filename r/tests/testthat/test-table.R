# Targeted tests of the table reader (docs/spec/tables.md) for cases that the
# table corpus does not cover. Inputs are built from bytes, never from
# non-ASCII string literals, which a C locale would leave unmarked.

write_table_file <- function(bytes) {
  path <- tempfile(fileext = ".csv")
  writeBin(bytes, path)
  path
}

read_text <- function(text, declaration = NULL) {
  path <- write_table_file(charToRaw(text))
  on.exit(unlink(path))
  read_table(path, declaration)
}

issue_of <- function(f) {
  tryCatch({
    f()
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

string_fields <- function(...) {
  lapply(c(...), function(name) list(name = name, type = "string", missingValues = list()))
}

# A reading of the CSV text of tables.md that scans the characters one at a
# time, written for these tests only. It returns the records read before the
# first quoting problem, the offset of each record and the offset and record
# of that problem, if there is one.
reference_scan <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  records <- list()
  starts <- integer(0)
  record <- character(0)
  record_start <- 0L
  i <- 1L
  problem <- function(at) {
    list(records = records, starts = starts, problem = at, problem_record = length(records) + 1L)
  }
  if (n == 0L) {
    return(list(records = records, starts = starts, problem = NA))
  }
  repeat {
    if (i <= n && chars[i] == "\"") {
      opening <- i
      j <- i + 1L
      value <- character(0)
      repeat {
        if (j > n) {
          return(problem(opening - 1L))
        }
        if (chars[j] == "\"") {
          if (j < n && chars[j + 1L] == "\"") {
            value <- c(value, "\"")
            j <- j + 2L
            next
          }
          j <- j + 1L
          break
        }
        value <- c(value, chars[j])
        j <- j + 1L
      }
      if (j <= n && !chars[j] %in% c(",", "\n", "\r")) {
        return(problem(j - 1L))
      }
    } else {
      j <- i
      value <- character(0)
      while (j <= n && !chars[j] %in% c(",", "\n", "\r")) {
        if (chars[j] == "\"") {
          return(problem(j - 1L))
        }
        value <- c(value, chars[j])
        j <- j + 1L
      }
    }
    record <- c(record, paste(value, collapse = ""))
    i <- j
    if (i > n) {
      records <- c(records, list(record))
      starts <- c(starts, record_start)
      break
    }
    if (chars[i] == ",") {
      i <- i + 1L
      next
    }
    i <- i + if (chars[i] == "\r" && i < n && chars[i + 1L] == "\n") 2L else 1L
    records <- c(records, list(record))
    starts <- c(starts, record_start)
    record <- character(0)
    record_start <- i - 1L
    if (i > n) {
      break
    }
  }
  list(records = records, starts = starts, problem = NA)
}

# The outcome that tables.md gives a text of ASCII characters under a table
# block whose fields are the given names, of type string without missing
# values: the first problem of the header or of a record, in the order of
# the records, or the records.
reference_outcome <- function(text, field_names) {
  scan <- reference_scan(text)
  if (length(scan$records) == 0L && is.na(scan$problem)) {
    return(list(code = "E5001"))
  }
  if (!is.na(scan$problem) && scan$problem_record == 1L) {
    return(list(code = "E5004", offset = scan$problem))
  }
  header <- scan$records[[1L]]
  if (!identical(header, field_names)) {
    return(list(code = "other"))
  }
  records <- scan$records[-1L]
  for (k in seq_along(records)) {
    if (length(records[[k]]) != length(header)) {
      return(list(code = "E5005", offset = scan$starts[k + 1L]))
    }
  }
  if (!is.na(scan$problem)) {
    return(list(code = "E5004", offset = scan$problem))
  }
  list(records = records)
}

table_outcome <- function(text, field_names) {
  table <- list(fields = string_fields(field_names))
  result <- tryCatch(
    mixedcheck:::parse_table_bytes(charToRaw(text), table),
    mixedcheck_error = function(e) e$issues[[1L]]
  )
  if (!is.data.frame(result)) {
    if (result$code %in% c("E5002", "E5003")) {
      return(list(code = "other"))
    }
    return(result[intersect(c("code", "offset"), names(result))])
  }
  rows <- nrow(result)
  list(records = lapply(seq_len(rows), function(i) unname(unlist(result[i, ]))))
}

# Every text of up to five characters from ',', '"', LF, CR and 'a', after a
# header 'a,b' and alone.
all_texts <- function(alphabet, size) {
  texts <- ""
  current <- ""
  for (length in seq_len(size)) {
    current <- as.vector(outer(current, alphabet, paste0))
    texts <- c(texts, current)
  }
  texts
}

# The texts whose outcomes differ.
differing_texts <- function(texts, field_names) {
  same <- vapply(texts, function(text) {
    identical(table_outcome(text, field_names), reference_outcome(text, field_names))
  }, NA, USE.NAMES = FALSE)
  encodeString(texts[!same])
}

test_that("the division into records and fields agrees with a scan of each character", {
  texts <- all_texts(c(",", "\"", "\n", "\r", "a"), 5L)
  expect_identical(differing_texts(paste0("a,b\n", texts), c("a", "b")), character(0))
  short <- texts[nchar(texts) <= 4L]
  expect_identical(differing_texts(paste0("a,b\r\n", short), c("a", "b")), character(0))
  # The header itself, under a table block of one column 'a'.
  expect_identical(differing_texts(texts, "a"), character(0))
})

test_that("the reader returns a data frame with the names and types of the header", {
  table <- read_text("a b,1x,c\n1,true,x\n,false,\n2.5,1,y\n")
  expect_s3_class(table, "data.frame")
  expect_identical(names(table), c("a b", "1x", "c"))
  expect_identical(attr(table, "types"), c(`a b` = "number", `1x` = "string", c = "string"))
  expect_identical(table[["a b"]], c(1, NA, 2.5))
  expect_identical(table[["1x"]], c("true", "false", "1"))
  expect_identical(table[["c"]], c("x", NA, "y"))
  expect_identical(nrow(table), 3L)
  expect_identical(row.names(table), c("1", "2", "3"))
})

test_that("column names that data.frame() treats specially are kept", {
  table <- read_text("row.names,check.names,..adfl.x,stringsAsFactors,\" \"\n1,2,3,4,5\n")
  expect_identical(names(table), c("row.names", "check.names", "..adfl.x", "stringsAsFactors", " "))
  expect_identical(unname(unlist(table[1L, ])), c(1, 2, 3, 4, 5))
})

test_that("NaN and the infinities stay distinct from missing values", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"),
    list(name = "k", type = "integer"),
    list(name = "b", type = "boolean")
  )))
  table <- read_text("y,k,b\nNaN,1,1\n,,\nInf,-0,FALSE\n-INF,+7,\n", declaration)
  expect_identical(is.na(table$y), c(TRUE, TRUE, FALSE, FALSE))
  expect_identical(is.nan(table$y), c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(table$y[3:4], c(Inf, -Inf))
  expect_identical(table$k, c(1, NA, 0, 7))
  expect_identical(1 / table$k[3], Inf)
  expect_identical(table$b, c(TRUE, NA, FALSE, NA))
  expect_identical(attr(table, "types"), c(y = "number", k = "integer", b = "boolean"))
})

test_that("a number column keeps negative zero and converts with correct rounding", {
  table <- read_text("y\n-0\n-0.0e5\n0\n.5\n5.\n+1e-3\n0.1\n")
  expect_identical(1 / table$y[1:3], c(-Inf, -Inf, Inf))
  expect_identical(table$y[4:7], c(0.5, 5, 0.001, 0.1))
})

test_that("columns of every type hold the vectors that the documentation states", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "s", type = "string"),
    list(name = "d", type = "date"),
    list(name = "t", type = "datetime"),
    list(name = "a"),
    list(name = "k", type = "integer"),
    list(name = "y", type = "number"),
    list(name = "b", type = "boolean")
  )))
  table <- read_text("s,d,t,a,k,y,b\nx,2026-11-08,2026-11-08T12:00:00Z,1,2,3,true\n", declaration)
  expect_identical(vapply(table, typeof, ""),
                   c(s = "character", d = "character", t = "character", a = "character",
                     k = "double", y = "double", b = "logical"))
  expect_identical(table$a, "1")
  expect_identical(attr(table, "types")[["a"]], "string")
})

test_that("a header without records gives columns of length zero", {
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = list(list(name = "id", type = "integer"), list(name = "b", type = "boolean")),
    primaryKey = list("id")
  ))
  table <- read_text("id,b\r\n", declaration)
  expect_identical(nrow(table), 0L)
  expect_identical(table$id, numeric(0))
  expect_identical(table$b, logical(0))
})

test_that("strings outside ASCII are marked UTF-8 and returned as written", {
  e_acute <- as.raw(c(0xC3, 0xA9))
  nfd <- as.raw(c(0x65, 0xCC, 0x81))
  bytes <- c(charToRaw("caf"), nfd, charToRaw(",s\n1,"), e_acute, charToRaw("\n2,\"x"), nfd,
             charToRaw("\"\"\"\n"))
  path <- write_table_file(bytes)
  on.exit(unlink(path))
  table <- read_table(path)
  expect_identical(Encoding(names(table))[1L], "UTF-8")
  expect_identical(charToRaw(names(table)[1L]), c(charToRaw("caf"), nfd))
  expect_identical(Encoding(table$s), c("UTF-8", "UTF-8"))
  expect_identical(charToRaw(table$s[1L]), e_acute)
  expect_identical(charToRaw(table$s[2L]), c(charToRaw("x"), nfd, charToRaw("\"")))
  expect_identical(table[[1L]], c(1, 2))
})

test_that("a quoted field keeps its line breaks as written", {
  table <- read_text("id,s\n1,\"a\r\nb\rc\nd\"\r2,\"\"\n", list(
    vocabulary = "0.1.0", table = list(fields = string_fields("id", "s"))
  ))
  expect_identical(table$s, c("a\r\nb\rc\nd", ""))
  expect_identical(table$id, c("1", "2"))
})

test_that("missing values of the table block apply to fields without their own", {
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = list(
      list(name = "k", type = "integer"),
      list(name = "s", type = "string", missingValues = list()),
      list(name = "y", type = "number", missingValues = list(list(value = "-1", label = "none")))
    ),
    missingValues = list(list(value = "-99", label = "refused"), list(value = "")),
    uniqueKeys = list(list("k", "y"))
  ))
  table <- read_text("k,s,y\n-99,,-1\n,-99,2\n3,x,-1\n3,x,-99\n", declaration)
  expect_identical(table$k, c(NA, NA, 3, 3))
  expect_identical(table$s, c("", "-99", "x", "x"))
  # '-99' is not a missing value of 'y', whose own list replaces the table's.
  expect_identical(table$y, c(NA, 2, NA, -99))
})

test_that("a unique key compares integers by value and skips incomplete records", {
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = list(list(name = "k", type = "integer"), list(name = "g", type = "string")),
    uniqueKeys = list(list("g"), list("k", "g"))
  ))
  issue <- issue_of(function() read_text("k,g\n1,a\n,a\n007,b\n7,b\n", declaration))
  # The first unique key ('g') already repeats 'a' in the second record.
  expect_identical(issue$code, "E5010")
  expect_identical(issue$offset, 8L)
  expect_match(issue$message, "unique key 1 ", fixed = TRUE)
  declaration$table$uniqueKeys <- list(list("k", "g"))
  issue <- issue_of(function() read_text("k,g\n1,a\n,a\n,a\n007,b\n7,b\n", declaration))
  expect_identical(issue$code, "E5010")
  expect_identical(issue$offset, 20L)
  expect_identical(issue$message,
                   "The record at byte 20 has the same values in unique key 1 of the table block as the record at byte 14.")
})

test_that("a composite primary key reports the first missing value in key order", {
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = string_fields("a", "b", "c"),
    missingValues = list(""),
    primaryKey = list("c", "a")
  ))
  declaration$table$fields <- lapply(declaration$table$fields, function(field) {
    field$missingValues <- NULL
    field
  })
  issue <- issue_of(function() read_text("a,b,c\n1,2,3\n,2,\n", declaration))
  expect_identical(issue$code, "E5008")
  expect_identical(issue$offset, 15L)
  expect_match(issue$message, "column 'c'", fixed = TRUE)
})

test_that("the primary key is checked record by record", {
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = string_fields("id", "y"),
    missingValues = list(""),
    primaryKey = list("id")
  ))
  declaration$table$fields <- lapply(declaration$table$fields, function(field) {
    field$missingValues <- NULL
    field
  })
  # A repeated key in the third record comes before a missing key in the
  # fourth.
  issue <- issue_of(function() read_text("id,y\n1,a\n2,b\n1,c\n,d\n", declaration))
  expect_identical(issue$code, "E5009")
  expect_identical(issue$offset, 13L)
  expect_identical(issue$message,
                   "The record at byte 13 has the same values in the primary key as the record at byte 5.")
  # A missing key in the third record comes before a repetition in the fourth.
  issue <- issue_of(function() read_text("id,y\n1,a\n2,b\n,c\n1,d\n", declaration))
  expect_identical(issue$code, "E5008")
  expect_identical(issue$offset, 13L)
  # Two incomplete records with the same values are reported as incomplete.
  issue <- issue_of(function() read_text("id,y\n,a\n,a\n", declaration))
  expect_identical(issue$code, "E5008")
  expect_identical(issue$offset, 5L)
})

test_that("an invalid declaration gives the validator's error before the file is read", {
  issue <- issue_of(function() {
    read_table(file.path(tempdir(), "mixedcheck-no-such-file.csv"),
               list(vocabulary = "0.1.0", table = list(fields = list())))
  })
  expect_identical(issue$code, "E1413")
  expect_identical(issue$pointer, "/table/fields")
})

test_that("a declaration can be given as a JSON file", {
  declaration <- tempfile(fileext = ".json")
  writeBin(charToRaw(paste0(
    '{"vocabulary": "0.1.0", "table": {"fields": [{"name": "id", "type": "integer"}, ',
    '{"name": "y", "type": "number"}], "primaryKey": ["id"]}}'
  )), declaration)
  on.exit(unlink(declaration))
  table <- read_text("id,y\n1,2\n2,3\n", declaration)
  expect_identical(attr(table, "types"), c(id = "integer", y = "number"))
  issue <- issue_of(function() read_text("id,y\n1,2\n1,3\n", declaration))
  expect_identical(issue$code, "E5009")
  expect_identical(issue$offset, 9L)
})

test_that("a declaration can be given as a YAML file", {
  skip_if_not_installed("yaml")
  declaration <- tempfile(fileext = ".yaml")
  writeBin(charToRaw(paste(
    "vocabulary: 0.1.0",
    "table:",
    "  fields:",
    "    - {name: id, type: integer}",
    "    - {name: cond, type: string, categories: [A, B]}",
    "",
    sep = "\n"
  )), declaration)
  on.exit(unlink(declaration))
  issue <- issue_of(function() read_text("id,cond\n1,A\n2,C\n", declaration))
  expect_identical(issue$code, "E5007")
  expect_identical(issue$message,
                   "The value 'C' of the column 'cond' at byte 14 is not one of its categories.")
})

test_that("the file argument must be one path", {
  expect_error(read_table(1), "'file' must be a file path.", fixed = TRUE)
  expect_error(read_table(c("a", "b")), "'file' must be a file path.", fixed = TRUE)
  expect_error(read_table(NA_character_), "'file' must be a file path.", fixed = TRUE)
})

test_that("an unreadable file gives E1002", {
  skip_on_os("windows")
  path <- write_table_file(charToRaw("a\n1\n"))
  on.exit(unlink(path))
  Sys.chmod(path, "000")
  skip_if(file.access(path, 4L) == 0L, "the file stays readable, as for the superuser")
  issue <- issue_of(function() read_table(path))
  expect_identical(issue$code, "E1002")
})

test_that("a value that ends in a line feed or uses other digits has no typed form", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "d", type = "date")
  )))
  issue <- issue_of(function() read_text("d\n\"2026-11-08\n\"\n", declaration))
  expect_identical(issue$code, "E5006")
  expect_identical(issue$message,
                   "The value '2026-11-08\\u000A' of the column 'd' at byte 2 cannot be read as a date.")
  declaration$table$fields[[1L]]$type <- "boolean"
  issue <- issue_of(function() read_text("d\nTrue\nyes\n", declaration))
  expect_identical(issue$offset, 7L)
})

test_that("a date and time names a real offset", {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "t", type = "datetime")
  )))
  table <- read_text("t\n2024-02-29T23:59:59.999-23:59\n", declaration)
  expect_identical(table$t, "2024-02-29T23:59:59.999-23:59")
  issue <- issue_of(function() read_text("t\n2026-11-08T00:00:00+05:60\n", declaration))
  expect_identical(issue$code, "E5006")
  issue <- issue_of(function() read_text("t\n2026-11-08T00:60:00\n", declaration))
  expect_identical(issue$code, "E5006")
})

test_that("the reader gives the same results under the C locale", {
  skip_on_os("windows")
  bytes <- c(charToRaw("g"), as.raw(c(0xC3, 0xA9)), charToRaw(",y\n"), as.raw(c(0xC3, 0xA9)),
             charToRaw(",1\nb,2\n"))
  path <- write_table_file(bytes)
  on.exit(unlink(path))
  expected <- read_table(path)
  # The marks of strings and their translation depend on LC_CTYPE.
  old <- c(LC_CTYPE = Sys.getlocale("LC_CTYPE"), LC_COLLATE = Sys.getlocale("LC_COLLATE"))
  on.exit(for (category in names(old)) Sys.setlocale(category, old[[category]]), add = TRUE)
  set <- vapply(names(old), function(category) {
    nzchar(suppressWarnings(Sys.setlocale(category, "C")))
  }, NA)
  skip_if_not(all(set), "The C locale cannot be set.")
  expect_false(isTRUE(l10n_info()[["UTF-8"]]))
  table <- read_table(path)
  expect_identical(table, expected)
  expect_identical(charToRaw(names(table)[1L]), as.raw(c(0x67, 0xC3, 0xA9)))
  expect_identical(Encoding(names(table)[1L]), "UTF-8")
  expect_identical(charToRaw(table[[1L]][1L]), as.raw(c(0xC3, 0xA9)))
  expect_identical(Encoding(table[[1L]][1L]), "UTF-8")
})

test_that("a table of 10,000 rows and 12 columns is read in seconds", {
  skip_on_cran()
  rows <- 10000L
  index <- seq_len(rows)
  lines <- paste(index, sprintf("s%03d", index %% 97L), sprintf("i%03d", index %% 89L),
                 c("A", "B", "C")[index %% 3L + 1L], sprintf("%.6f", index / 7),
                 c("true", "false")[index %% 2L + 1L], "2026-11-08", "2026-11-08T12:00:00Z",
                 sprintf("%.15g", index / 3), ifelse(index %% 50L == 0L, "", "1.5e-7"),
                 index %% 1000L, "\"a, \"\"b\"\"\"", sep = ",")
  path <- write_table_file(charToRaw(paste0(
    "id,subject,item,cond,rt,acc,date,time,x1,x2,count,note\n",
    paste(lines, collapse = "\n"), "\n"
  )))
  on.exit(unlink(path))
  types <- c("integer", "string", "string", "string", "number", "boolean", "date",
             "datetime", "number", "number", "integer", "string")
  columns <- c("id", "subject", "item", "cond", "rt", "acc", "date", "time", "x1", "x2",
               "count", "note")
  fields <- Map(function(name, type) list(name = name, type = type), columns, types)
  fields[[4L]]$categories <- list("A", "B", "C")
  declaration <- list(vocabulary = "0.1.0", table = list(
    fields = unname(fields), primaryKey = list("id"),
    uniqueKeys = list(list("subject", "item", "rt"))
  ))
  time <- system.time(table <- read_table(path, declaration))[["elapsed"]]
  expect_lt(time, 10)
  expect_identical(nrow(table), rows)
  expect_identical(table$note[1L], "a, \"b\"")
  expect_identical(sum(is.na(table$x2)), 200L)
})
