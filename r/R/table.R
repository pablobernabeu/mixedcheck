# The strict table reader (docs/spec/tables.md). It works in four stages,
# input, text, records and keys, and reports the first issue that they find.
# The bytes are classified with vectorised operations. The parity of the
# quotation marks before each separator decides whether it lies inside a
# quoted field, so that the records and fields are found without a loop over
# the bytes, and the values of each column are checked and converted together.

#' Read a data table with the strict reader
#'
#' Reads a CSV file by the rules of the table specification of mixedcheck and
#' returns its columns. The text must be UTF-8 without a byte-order mark, with
#' fields separated by ',' and records by LF, CR LF or CR alone, and quoted
#' fields as RFC 4180 writes them. Nothing is trimmed. The first record is the
#' header, whose column names must be valid and distinct after NFC
#' normalisation, and every later record must have as many fields.
#'
#' With a declaration that has a table block, the header must name the fields
#' of the block in number and order, compared after NFC normalisation. A value
#' is missing when it equals, after NFC normalisation, one of the field's
#' `missingValues`, otherwise one of the table block's, otherwise the empty
#' string. Every other value must have the lexical form of its field's type
#' and be one of its categories, and after the last record the primary key
#' and each unique key of the block are checked. A field without a type is
#' read as text. Without a table block, every column has the missing value ''
#' and the type number, boolean or string, inferred from its values in that
#' order.
#'
#' @param file The path of the CSV file, as a character string.
#' @param declaration `NULL`, the path of a declaration file in JSON or YAML,
#'   or a declaration in memory as a named list, as [validate_declaration()]
#'   accepts it. The declaration is validated first, and an invalid one gives
#'   the validator's error. Its table block, if it has one, applies to the
#'   table.
#' @return A data frame with one column for each column of the file, in the
#'   order of the header and under the names that the header writes, without
#'   normalisation and unchanged, as `check.names = FALSE` leaves them, and one
#'   row for each record after the header, in the order of the file. Columns
#'   of type string, date and datetime and fields without a type are
#'   character vectors, with strings marked UTF-8 and returned as written.
#'   Columns of type integer and number are double vectors and columns of
#'   type boolean are logical vectors. A missing value is `NA` of the column's
#'   type, where the Python package returns `None`, and the values 'NaN',
#'   'INF' and '-INF' of a number column, in any mix of upper and lower case,
#'   are `NaN`, `Inf` and `-Inf`, which stay distinct from `NA`. The attribute
#'   `types` is a character vector of the column types, named by column: the
#'   declared type, 'string' for a field without a type or the type inferred.
#' @section Errors: A problem is signalled as an error of class
#'   `mixedcheck_error`, whose element `issues` holds one issue: a list with
#'   the `code` of the shared error catalogue, the rendered `message` and,
#'   when the code has a location, the byte `offset` into the file at which
#'   the problem lies. Offsets count from 0 in both packages, whereas R
#'   numbers rows and columns from 1. A declaration that is not valid gives
#'   the error of [validate_declaration()] instead, with every problem found.
#'   A `file` argument that is not one path gives an ordinary error.
#' @export
#' @examples
#' path <- tempfile(fileext = ".csv")
#' writeBin(charToRaw("id,cond,rt\n1,A,512.5\n2,B,\n3,A,NaN\n"), path)
#' table <- read_table(path)
#' table
#' attr(table, "types")
#'
#' declaration <- list(
#'   vocabulary = "0.1.0",
#'   table = list(
#'     fields = list(
#'       list(name = "id", type = "integer"),
#'       list(name = "cond", type = "string", categories = list("A", "B")),
#'       list(name = "rt", type = "number")
#'     ),
#'     primaryKey = list("id")
#'   )
#' )
#' attr(read_table(path, declaration), "types")
#'
#' # A value outside the categories.
#' writeBin(charToRaw("id,cond,rt\n1,A,512.5\n2,C,498\n"), path)
#' problem <- tryCatch(read_table(path, declaration), mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
#' unlink(path)
read_table <- function(file, declaration = NULL) {
  if (!is.character(file) || length(file) != 1L || is.na(file)) {
    stop("'file' must be a file path.", call. = FALSE)
  }
  table <- NULL
  if (!is.null(declaration)) {
    table <- validate_declaration(declaration)[["table"]]
  }
  parse_table_bytes(read_input_bytes(file), table)
}

# The names that E5006 gives the field types.
table_type_names <- c(
  integer = "an integer", number = "a number", boolean = "a boolean",
  date = "a date", datetime = "a date and time"
)

# The lexical forms of tables.md (Field types), matched over the bytes of
# values that are valid UTF-8. '[0-9]' stands for the ASCII digits, and '\z'
# matches only at the end of the value, so that a value that ends in a line
# feed has none of these forms.
table_integer_pattern <- "^[+-]?[0-9]+\\z"
table_number_pattern <- "^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?\\z"
table_special_pattern <- "^(?:[Nn][Aa][Nn]|-?[Ii][Nn][Ff])\\z"
table_date_pattern <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\z"
table_datetime_pattern <- paste0(
  "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?",
  "(Z|[+-][0-9]{2}:[0-9]{2})?\\z"
)
table_true <- c("true", "True", "TRUE", "1")
table_false <- c("false", "False", "FALSE", "0")

table_matches <- function(pattern, x) {
  grepl(pattern, x, perl = TRUE, useBytes = TRUE)
}

# Reads a table from the bytes of a file, under the table block of a
# declaration or, when table is NULL, by the rules for columns without a
# table block.
parse_table_bytes <- function(bytes, table = NULL) {
  n <- length(bytes)
  # Stage 1: input.
  if (n >= 3L && bytes[1L] == as.raw(0xEF) && bytes[2L] == as.raw(0xBB) &&
      bytes[3L] == as.raw(0xBF)) {
    raise_issue("E1003")
  }
  # Stage 2: text. Invalid UTF-8 anywhere comes before an earlier U+0000.
  invalid <- utf8_invalid_offset(bytes)
  if (!is.na(invalid)) {
    raise_issue("E1201", offset = invalid)
  }
  nul <- grepRaw(as.raw(0L), bytes, fixed = TRUE)
  if (length(nul)) {
    raise_issue("E1202", offset = nul[1L] - 1L)
  }
  if (n == 0L) {
    raise_issue("E5001")
  }
  # Stage 3: records.
  csv <- csv_scan(bytes)
  text <- rawToChar(bytes)
  Encoding(text) <- "latin1"
  header <- table_header(csv, text, table)
  width <- length(header$names)
  records <- csv$record_count
  # The first record that breaks the rules of quoting or length. Records
  # after the first quoting problem were not divided reliably, so their
  # lengths are not compared.
  quote_record <- csv$quote_record
  counts <- tabulate(csv$field_record, nbins = records)
  long <- which(counts != width)
  long <- long[long > 1L & long < quote_record]
  length_record <- if (length(long)) long[1L] else Inf
  broken <- min(quote_record, length_record)
  last_good <- as.integer(min(broken - 1, records))
  raw <- table_raw_values(csv, text, last_good, width)
  if (is.null(table)) {
    if (is.finite(broken)) {
      table_structure_issue(csv, broken, length_record, counts, width)
    }
    columns <- lapply(seq_len(width), function(j) infer_column(raw[[j]]))
  } else {
    fields <- table[["fields"]]
    columns <- lapply(seq_len(width), function(j) {
      read_column(raw[[j]], fields[[j]], table[["missingValues"]])
    })
  }
  # The first value that breaks a rule, by record and then from left to
  # right. With a table block, it comes before a later record of the wrong
  # length or with a quoting problem.
  failing <- vapply(columns, function(column) column$error %||% NA_integer_, 0L)
  if (any(!is.na(failing))) {
    j <- which(failing == min(failing, na.rm = TRUE))[1L]
    column <- columns[[j]]
    i <- column$error
    offset <- csv$field_start[csv$record_first[i + 1L] + j - 1L] - 1L
    args <- list(value = raw[[j]][i], column = header$names[j])
    if (column$code == "E5006") {
      args$type <- table_type_names[[column$type]]
    }
    raise_issue(column$code, args, offset = offset)
  }
  if (is.finite(broken)) {
    table_structure_issue(csv, broken, length_record, counts, width)
  }
  # Stage 4: keys.
  if (!is.null(table)) {
    check_table_keys(table, columns, csv, header$names)
  }
  values <- lapply(columns, function(column) column$values)
  types <- vapply(columns, function(column) column$type, "")
  names(values) <- header$names
  names(types) <- header$names
  # list2DF() neither checks nor changes the names, as check.names = FALSE
  # requires.
  result <- list2DF(values, nrow = max(last_good - 1L, 0L))
  attr(result, "types") <- types
  result
}

# Divides the bytes into records and fields (tables.md, CSV text). A
# separator ',', LF or CR lies inside a quoted field exactly when an odd
# number of quotation marks precede it, which holds for every byte before
# the first quoting problem, since a doubled quotation mark closes the field
# and opens it again. Returns the 1-based first byte and the end, the byte
# after the field's last byte, of each field, the record of each field, the
# first field of each record and the record of the first quoting problem, or
# Inf when there is none.
csv_scan <- function(bytes) {
  n <- length(bytes)
  quote_at <- grepRaw("\"", bytes, all = TRUE, fixed = TRUE)
  candidates <- sort(c(grepRaw(",", bytes, all = TRUE, fixed = TRUE),
                       grepRaw("\n", bytes, all = TRUE, fixed = TRUE),
                       grepRaw("\r", bytes, all = TRUE, fixed = TRUE)))
  if (length(quote_at) && length(candidates)) {
    candidates <- candidates[findInterval(candidates, quote_at) %% 2L == 0L]
  }
  kind <- as.integer(bytes[candidates])
  count <- length(candidates)
  # The LF of a CR LF belongs to the line break that the CR starts.
  after_cr <- kind == 10L & c(FALSE, kind[-count] == 13L) &
    c(FALSE, candidates[-count] == candidates[-1L] - 1L)
  cr_lf <- c(after_cr[-1L], FALSE)
  keep <- !after_cr
  terminator <- candidates[keep]
  is_break <- kind[keep] != 44L
  terminator_end <- terminator + cr_lf[keep]
  terminators <- length(terminator)
  # A line break at the end of the text ends the last record and starts no
  # new one.
  closed <- terminators > 0L && is_break[terminators] && terminator_end[terminators] == n
  fields <- if (closed) terminators else terminators + 1L
  field_start <- c(1L, terminator_end + 1L)[seq_len(fields)]
  field_end <- c(terminator, n + 1L)[seq_len(fields)]
  field_record <- c(1L, 1L + cumsum(is_break))[seq_len(fields)]
  field_quoted <- field_start < field_end
  field_quoted[field_quoted] <- bytes[field_start[field_quoted]] == as.raw(34L)
  record_count <- field_record[fields]
  record_first <- c(which(!duplicated(field_record)), fields + 1L)
  quote_error <- csv_quote_error(bytes, quote_at)
  quote_record <- Inf
  if (!is.na(quote_error)) {
    quote_record <- findInterval(quote_error, field_start[record_first[seq_len(record_count)]])
  }
  list(
    field_start = field_start,
    field_end = field_end,
    field_record = field_record,
    field_quoted = field_quoted,
    record_count = record_count,
    record_first = record_first,
    quote_error = quote_error,
    quote_record = quote_record
  )
}

# The 1-based position of the first quoting problem (E5004), or NA. Counting
# the quotation marks from the start, an odd one opens a quoted field and
# must start a field or follow at once the even one before it, which makes
# the pair a doubled quotation mark. An even one closes the field and must
# be followed by ',', a line break, the end of the text or the odd one of a
# doubled quotation mark. Before the first problem, the scan of RFC 4180
# gives every quotation mark this role, so the first position that breaks
# these rules is where the scan finds its first problem. When there is none
# and the count is odd, the text ends inside the quoted field that the last
# odd quotation mark at the start of a field opens.
csv_quote_error <- function(bytes, quote_at) {
  count <- length(quote_at)
  if (count == 0L) {
    return(NA_integer_)
  }
  n <- length(bytes)
  b <- as.integer(bytes)
  allowed <- c(-1L, 44L, 10L, 13L, 34L)
  before <- rep(-1L, count)
  inside <- quote_at > 1L
  before[inside] <- b[quote_at[inside] - 1L]
  after <- rep(-1L, count)
  inside <- quote_at < n
  after[inside] <- b[quote_at[inside] + 1L]
  odd <- seq_len(count) %% 2L == 1L
  problems <- c(quote_at[odd & !before %in% allowed],
                quote_at[!odd & !after %in% allowed] + 1L)
  if (length(problems)) {
    return(min(problems))
  }
  if (count %% 2L == 1L) {
    openers <- quote_at[odd & before != 34L]
    return(openers[length(openers)])
  }
  NA_integer_
}

# The raw values of the given fields: the text of each field, without the
# quotation marks of a quoted field and with each doubled quotation mark
# made single, marked UTF-8. text holds the bytes of the input marked
# latin1, so that character positions are byte positions.
csv_field_values <- function(csv, text, fields) {
  if (!length(fields)) {
    return(character(0))
  }
  start <- csv$field_start[fields]
  end <- csv$field_end[fields]
  quoted <- csv$field_quoted[fields]
  first <- start + quoted
  last <- end - 1L - quoted
  values <- substring(text, first, last)
  Encoding(values) <- "UTF-8"
  doubled <- which(quoted)
  doubled <- doubled[grepl("\"\"", values[doubled], fixed = TRUE, useBytes = TRUE)]
  if (length(doubled)) {
    values[doubled] <- gsub("\"\"", "\"", values[doubled], fixed = TRUE, useBytes = TRUE)
    Encoding(values) <- "UTF-8"
  }
  values
}

# The header (tables.md, Header): its quoting (E5004), its column names
# (E5002) and their match with the fields of the table block (E5003).
table_header <- function(csv, text, table) {
  if (csv$quote_record == 1L) {
    raise_issue("E5004", offset = csv$quote_error - 1L)
  }
  fields <- seq_len(csv$record_first[2L] - 1L)
  names <- csv_field_values(csv, text, fields)
  offsets <- csv$field_start[fields] - 1L
  forms <- comparison_form(names)
  bad <- which(!valid_column_name(names) | duplicated(forms))
  if (length(bad)) {
    raise_issue("E5002", offset = offsets[bad[1L]])
  }
  if (!is.null(table)) {
    field_names <- vapply(table[["fields"]], function(field) field[["name"]], "")
    common <- min(length(names), length(field_names))
    differ <- which(forms[seq_len(common)] != comparison_form(field_names[seq_len(common)]))
    if (length(differ)) {
      raise_issue("E5003", offset = offsets[differ[1L]])
    }
    if (length(names) < length(field_names)) {
      # The line break that ends the header, or the end of the text.
      raise_issue("E5003", offset = csv$field_end[length(names)] - 1L)
    }
    if (length(names) > length(field_names)) {
      raise_issue("E5003", offset = offsets[length(field_names) + 1L])
    }
  }
  list(names = names)
}

# The raw values of the records from the second to the last good one, as
# one character vector for each column.
table_raw_values <- function(csv, text, last_good, width) {
  rows <- max(last_good - 1L, 0L)
  if (rows == 0L) {
    return(rep(list(character(0)), width))
  }
  fields <- seq.int(csv$record_first[2L], csv$record_first[last_good + 1L] - 1L)
  values <- csv_field_values(csv, text, fields)
  lapply(seq_len(width), function(j) values[seq.int(j, by = width, length.out = rows)])
}

# Reports a record that breaks the rules of quoting (E5004) or length
# (E5005). A quoting problem comes before the length of its record.
table_structure_issue <- function(csv, broken, length_record, counts, width) {
  if (broken == csv$quote_record) {
    raise_issue("E5004", offset = csv$quote_error - 1L)
  }
  offset <- csv$field_start[csv$record_first[length_record]] - 1L
  raise_issue("E5005", list(found = counts[length_record], expected = width), offset = offset)
}

# Whether each raw value is missing: whether it equals, after NFC, one of the
# missing values of the field, otherwise of the table block, otherwise the
# default '' (tables.md, Missing values).
table_missing <- function(raw, field_missing, table_missing) {
  items <- field_missing %||% table_missing %||% list("")
  missing_values <- vapply(items, list_item_value, "")
  if (!length(missing_values)) {
    return(logical(length(raw)))
  }
  if (identical(missing_values, "")) {
    return(raw == "")
  }
  comparison_form(raw) %in% missing_values
}

# Converts values that have the lexical form of a number or an integer, other
# than the special values, to the nearest doubles. Each is first written in
# the number grammar of RFC 8259, without '+', leading zeros, a '.' without
# digits after it or a fraction without digits before it, and converted with
# correct rounding.
table_number_values <- function(tokens) {
  json_form <- table_matches("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?\\z", tokens)
  rewrite <- which(!json_form)
  if (length(rewrite)) {
    token <- tokens[rewrite]
    sign <- ifelse(startsWith(token, "-"), "-", "")
    token <- sub("^[+-]", "", token, perl = TRUE, useBytes = TRUE)
    exponent <- sub("^[^eE]*", "", token, perl = TRUE, useBytes = TRUE)
    mantissa <- substr(token, 1L, nchar(token, "bytes") - nchar(exponent, "bytes"))
    whole <- sub("^0+", "", sub("\\..*$", "", mantissa, perl = TRUE, useBytes = TRUE),
                 perl = TRUE, useBytes = TRUE)
    whole[whole == ""] <- "0"
    fraction <- sub("^[^.]*\\.?", "", mantissa, perl = TRUE, useBytes = TRUE)
    tokens[rewrite] <- paste0(sign, whole, ifelse(fraction == "", "", paste0(".", fraction)),
                              exponent)
  }
  json_number_values(tokens)
}

# Checks and converts the values of one column of a table block. Returns the
# values, the column's type and, for the first value that does not have the
# lexical form of the type (E5006) or is not one of the categories (E5007),
# its index and code.
read_column <- function(raw, field, table_missing_values) {
  type <- field[["type"]] %||% "string"
  missing <- table_missing(raw, field[["missingValues"]], table_missing_values)
  present <- which(!missing)
  text <- raw[present]
  valid <- rep(TRUE, length(present))
  converted <- NULL
  if (type == "integer") {
    valid <- table_matches(table_integer_pattern, text)
    converted <- rep(NA_real_, length(present))
    converted[valid] <- table_number_values(text[valid])
    valid[valid] <- abs(converted[valid]) <= 9007199254740991
  } else if (type == "number") {
    special <- table_matches(table_special_pattern, text)
    valid <- special | table_matches(table_number_pattern, text)
    converted <- rep(NA_real_, length(present))
    converted[special] <- ifelse(grepl("^[Nn]", text[special], useBytes = TRUE), NaN,
                                 ifelse(startsWith(text[special], "-"), -Inf, Inf))
    plain <- which(valid & !special)
    if (length(plain)) {
      value <- table_number_values(text[plain])
      # A number that converts to an infinity, or to zero from a non-zero
      # value, is refused, as in the data profile.
      nonzero <- grepl("[1-9]", sub("[eE].*$", "", text[plain], perl = TRUE, useBytes = TRUE),
                       useBytes = TRUE)
      valid[plain] <- !is.infinite(value) & !(value == 0 & nonzero)
      # Negative zero is computed, since the byte compiler folds the
      # constant -0 into 0.
      negative_zero <- value == 0 & startsWith(text[plain], "-")
      value[negative_zero] <- -abs(value[negative_zero])
      converted[plain] <- value
    }
  } else if (type == "boolean") {
    converted <- text %in% table_true
    valid <- converted | text %in% table_false
  } else if (type == "date") {
    valid <- table_matches(table_date_pattern, text)
    valid[valid] <- table_date_exists(text[valid])
  } else if (type == "datetime") {
    valid <- table_matches(table_datetime_pattern, text)
    valid[valid] <- table_date_exists(text[valid]) & table_time_exists(text[valid])
  }
  code <- rep(NA_character_, length(present))
  code[!valid] <- "E5006"
  categories <- field[["categories"]]
  if (!is.null(categories) && any(valid)) {
    allowed <- lapply(categories, list_item_value)
    inside <- if (type == "integer") {
      converted[valid] %in% vapply(allowed, as.double, 0)
    } else {
      comparison_form(text[valid]) %in% vapply(allowed, as.character, "")
    }
    code[which(valid)[!inside]] <- "E5007"
  }
  values <- switch(type,
    integer = ,
    number = rep(NA_real_, length(raw)),
    boolean = rep(NA, length(raw)),
    rep(NA_character_, length(raw))
  )
  values[present] <- if (is.null(converted)) text else converted
  failing <- which(!is.na(code))
  if (length(failing)) {
    return(list(values = values, type = type, missing = missing,
                error = present[failing[1L]], code = code[failing[1L]]))
  }
  list(values = values, type = type, missing = missing)
}

# Whether each date in the form YYYY-MM-DD at the start of a value names a
# real day: a year from 0001 to 9999, a month from 01 to 12 and a day that
# exists in its month.
table_date_exists <- function(text) {
  year <- as.integer(substr(text, 1L, 4L))
  month <- as.integer(substr(text, 6L, 7L))
  day <- as.integer(substr(text, 9L, 10L))
  result <- year >= 1L & month >= 1L & month <= 12L & day >= 1L
  result[result] <- calendar_day_exists(text[result])
  result
}

# Whether each date and time in the form of a datetime names a real time:
# hours from 00 to 23, minutes and seconds from 00 to 59 and, for an offset,
# hours from 00 to 23 and minutes from 00 to 59.
table_time_exists <- function(text) {
  hour <- as.integer(substr(text, 12L, 13L))
  minute <- as.integer(substr(text, 15L, 16L))
  second <- as.integer(substr(text, 18L, 19L))
  result <- hour <= 23L & minute <= 59L & second <= 59L
  offset <- table_matches("[+-][0-9]{2}:[0-9]{2}\\z", text)
  if (any(offset)) {
    size <- nchar(text[offset], "bytes")
    offset_hour <- as.integer(substr(text[offset], size - 4L, size - 3L))
    offset_minute <- as.integer(substr(text[offset], size - 1L, size))
    result[offset] <- result[offset] & offset_hour <= 23L & offset_minute <= 59L
  }
  result
}

# Infers the type of a column without a table block (tables.md, Columns
# without a table block) and converts its values. Only a number column can
# hold a value that breaks a rule: a number that converts to an infinity or
# to zero from a non-zero value (E5006).
infer_column <- function(raw) {
  missing <- raw == ""
  text <- raw[!missing]
  type <- "string"
  if (length(text)) {
    if (all(table_matches(table_number_pattern, text) | table_matches(table_special_pattern, text))) {
      type <- "number"
    } else if (all(text %in% c("true", "True", "TRUE", "false", "False", "FALSE"))) {
      type <- "boolean"
    }
  }
  read_column(raw, list(type = type), NULL)
}

# The values by which the keys compare records: strings, dates and dates and
# times after NFC, and numbers and booleans by value, with NaN equal to NaN
# and negative zero equal to zero, as match() compares doubles.
key_codes <- function(column) {
  values <- column$values
  if (is.character(values)) {
    values <- comparison_form(values)
  }
  match(values, unique(values))
}

# Combines the codes of the columns of a key into one code for each record.
combine_key_codes <- function(columns, rows) {
  combined <- rep(1, rows)
  for (column in columns) {
    codes <- key_codes(column)
    combined <- combined * (max(codes, 0L) + 1) + codes
    combined <- match(combined, unique(combined))
  }
  combined
}

# Stage 4: the primary key (E5008 and E5009) and then each unique key
# (E5010), over the records in the order of the file (tables.md, Keys).
check_table_keys <- function(table, columns, csv, column_names) {
  field_names <- vapply(table[["fields"]], function(field) field[["name"]], "")
  rows <- length(columns[[1L]]$values)
  if (rows == 0L) {
    return(invisible())
  }
  record_offset <- function(i) csv$field_start[csv$record_first[i + 1L]] - 1L
  primary <- match(unlist(table[["primaryKey"]]), field_names)
  if (length(primary)) {
    # The records are taken in order, and in each a missing value comes
    # before a repetition of an earlier record's values. Every record before
    # the first problem is complete, so a repetition found among all the
    # records before the first incomplete one repeats a complete record.
    missing <- vapply(columns[primary], function(column) column$missing, logical(rows))
    missing <- matrix(missing, nrow = rows)
    incomplete <- which(rowSums(missing) > 0L)
    first_incomplete <- if (length(incomplete)) incomplete[1L] else Inf
    codes <- combine_key_codes(columns[primary], rows)
    repeated <- which(duplicated(codes))
    first_repeated <- if (length(repeated)) repeated[1L] else Inf
    if (first_incomplete <= first_repeated && is.finite(first_incomplete)) {
      i <- first_incomplete
      j <- primary[which(missing[i, ])[1L]]
      raise_issue("E5008", list(column = column_names[j]),
                  offset = csv$field_start[csv$record_first[i + 1L] + j - 1L] - 1L)
    }
    if (is.finite(first_repeated)) {
      i <- first_repeated
      raise_issue("E5009", list(earlier = record_offset(match(codes[i], codes))),
                  offset = record_offset(i))
    }
  }
  unique_keys <- table[["uniqueKeys"]]
  for (index in seq_along(unique_keys)) {
    key <- match(unlist(unique_keys[[index]]), field_names)
    complete <- rep(TRUE, rows)
    for (j in key) {
      complete <- complete & !columns[[j]]$missing
    }
    considered <- which(complete)
    if (length(considered) < 2L) {
      next
    }
    subset <- lapply(columns[key], function(column) {
      list(values = column$values[considered])
    })
    codes <- combine_key_codes(subset, length(considered))
    repeated <- which(duplicated(codes))
    if (length(repeated)) {
      i <- repeated[1L]
      earlier <- considered[match(codes[i], codes)]
      raise_issue("E5010", list(index = index, earlier = record_offset(earlier)),
                  offset = record_offset(considered[i]))
    }
  }
  invisible()
}
