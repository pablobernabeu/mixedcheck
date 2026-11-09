# The data of a run and the keyed commitments to them that audit() writes and
# validate_results() verifies (docs/spec/documents.md, Outcome column
# commitment and Analysis table commitment, and conventions.md, Keyed
# commitments). The table of a run is the form that model_table() returns:
# the names of the columns as given, their comparison forms and their values,
# doubles, strings marked UTF-8 or logical values, with NA for a missing value.

# The data of a run (03-execution-plan.md, M2, step 3): a CSV file read by the
# table reader with the declaration's table block, or a data frame converted
# as formula_ir() converts it, after the declaration's missing values are
# applied when it has a table block (tables.md, Missing values). The
# declaration is NULL or a value that validate_declaration() returned.
# Returns the table and, for a file, the bytes that the commitment to the
# data file covers.
run_data <- function(data, declaration) {
  table_block <- declaration[["table"]]
  fields <- table_block[["fields"]]
  if (is_string(data)) {
    bytes <- read_input_bytes(data)
    return(list(table = model_table(parse_table_bytes(bytes, table_block), fields), file = bytes))
  }
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame or the path of a CSV file.", call. = FALSE)
  }
  if (!is.null(table_block)) {
    data <- apply_missing_values(data, table_block)
  }
  list(table = model_table(data, fields), file = NULL)
}

# Applies the missing values of a table block to a data frame in memory: in
# each column, a string that equals one of the missing values that apply to
# the column, compared after NFC, and a number that equals the double to
# which such a value with the lexical form of a number converts, compared as
# keys compare numbers, become NA. Booleans are never missing. Columns of
# other types are left to model_table(), which refuses them.
apply_missing_values <- function(data, table_block) {
  fields <- table_block[["fields"]]
  field_keys <- comparison_form(vapply(fields, function(field) field[["name"]], ""))
  raw_names <- names(data)
  for (j in seq_along(data)) {
    name <- raw_names[j]
    if (is.null(name) || is.na(name)) {
      next
    }
    key <- comparison_form(input_strings(name, function(i) json_pointer(c("data", name))))
    field <- fields[match(key, field_keys)]
    field <- if (length(field)) field[[1L]]
    items <- field[["missingValues"]] %||% table_block[["missingValues"]] %||% list("")
    missing_values <- vapply(items, list_item_value, "")
    if (!length(missing_values)) {
      next
    }
    x <- data[[j]]
    if (is.factor(x)) {
      x <- levels(x)[x]
    }
    plain <- !is.object(x) && is.null(dim(x))
    if (plain && typeof(x) == "character") {
      x <- input_strings(x, function(i) json_pointer(c("data", name, i - 1L)))
      x[comparison_form(x) %in% missing_values] <- NA_character_
      data[[j]] <- x
    } else if (plain && typeof(x) %in% c("double", "integer")) {
      numbers <- missing_number_values(missing_values)
      if (length(numbers)) {
        # match() keeps NA apart from NaN, and equates negative zero and zero.
        x <- as.double(x)
        x[x %in% numbers] <- NA_real_
        data[[j]] <- x
      }
    }
  }
  data
}

# The doubles to which missing values with the lexical form of a number
# convert, as the table reader converts the values of a number column
# (tables.md, Field types). A value that converts to an infinity, or to zero
# from a non-zero value, has no such double.
missing_number_values <- function(text) {
  special <- table_matches(table_special_pattern, text)
  plain <- !special & table_matches(table_number_pattern, text)
  values <- ifelse(grepl("^[Nn]", text[special], useBytes = TRUE), NaN,
                   ifelse(startsWith(text[special], "-"), -Inf, Inf))
  if (any(plain)) {
    converted <- table_number_values(text[plain])
    nonzero <- grepl("[1-9]", sub("[eE].*$", "", text[plain], perl = TRUE, useBytes = TRUE),
                     useBytes = TRUE)
    values <- c(values, converted[!is.infinite(converted) & !(converted == 0 & nonzero)])
  }
  values
}

# The columns of the declared observation key, in declared order, or none
# when no key is declared or the key counts as absent, because
# /provenance/inferred points to the key, to one of its columns or to the
# observation block (registry.md, Terms).
observation_key_columns <- function(declaration) {
  key <- unlist(declaration[["observation"]][["key"]])
  if (!length(key)) {
    return(character(0))
  }
  inferred <- as.character(unlist(declaration[["provenance"]][["inferred"]]))
  if (any(inferred %in% c("/observation", "/observation/key") |
            startsWith(inferred, "/observation/key/"))) {
    return(character(0))
  }
  key
}

# The comparison forms of the outcome columns that the analysis table leaves
# out: the response, its trials column and the columns that the declaration
# gives the role outcome or outcome_derived. response is the name of the
# response column, or NULL for a one-sided formula.
outcome_column_keys <- function(declaration, response = NULL) {
  variables <- declaration[["variables"]]
  variable_keys <- comparison_form(as.character(names(variables)))
  roles <- vapply(variables, function(entry) entry[["role"]] %||% "", "")
  keys <- variable_keys[roles %in% c("outcome", "outcome_derived")]
  if (!is.null(response)) {
    response <- comparison_form(response)
    trials <- variables[match(response, variable_keys)]
    trials <- if (length(trials)) trials[[1L]][["trials"]]
    keys <- c(keys, response, if (!is.null(trials)) comparison_form(trials))
  }
  unique(keys)
}

# The JSON text of each value of a column of a run's table, as a writer in
# the data profile writes it: NA as null, a finite double as RFC 8785 writes
# it, NaN and the infinities as 'NaN', 'Infinity' and '-Infinity', a string
# with its escapes and a logical value as true or false.
json_cells <- function(values) {
  cells <- rep("null", length(values))
  if (is.double(values)) {
    finite <- is.finite(values)
    cells[finite] <- format_numbers(values[finite], FALSE)$text
    cells[is.nan(values)] <- "\"NaN\""
    cells[values %in% Inf] <- "\"Infinity\""
    cells[values %in% -Inf] <- "\"-Infinity\""
  } else if (is.character(values)) {
    present <- which(!is.na(values))
    if (length(present)) {
      cells[present] <- quote_json_strings(values[present])
    }
  } else if (is.logical(values)) {
    cells[values %in% TRUE] <- "true"
    cells[values %in% FALSE] <- "false"
  }
  cells
}

# The canonical bytes of the rows of a commitment message: one array for each
# row of the table with the values of the columns at the positions given,
# ordered by the canonical bytes of the array of their key values, compared
# byte by byte with a prefix first, and then by the bytes of the whole row,
# when key holds the positions of the key columns, and in the order of the
# table otherwise. The radix method compares strings that are ASCII or marked
# UTF-8 by their bytes.
commitment_rows <- function(table, positions, key) {
  if (table$rows == 0L) {
    return("[]")
  }
  json_rows <- function(columns) {
    if (!length(columns)) {
      return(rep("[]", table$rows))
    }
    cells <- lapply(table$values[columns], json_cells)
    paste0("[", do.call(paste, c(unname(cells), sep = ",")), "]")
  }
  rows <- json_rows(positions)
  if (length(key)) {
    rows <- rows[order(json_rows(key), rows, method = "radix")]
  }
  paste0("[", paste(rows, collapse = ","), "]")
}

# The positions of the named columns in a run's table, compared after NFC, or
# NULL when one of them is not a column of the table.
table_positions <- function(table, columns) {
  positions <- match(comparison_form(columns), table$keys)
  if (anyNA(positions)) NULL else positions
}

# The message of the commitment to the analysis table (documents.md, Analysis
# table commitment): the canonical bytes of the columns of the table other
# than the outcome columns, the observation key and the rows. NULL when a
# column of the key is not a column of the table.
analysis_table_message <- function(table, declaration, response = NULL) {
  key_columns <- observation_key_columns(declaration)
  key <- table_positions(table, key_columns)
  if (is.null(key)) {
    return(NULL)
  }
  kept <- which(!table$keys %in% outcome_column_keys(declaration, response))
  text <- paste0(
    "{\"columns\":", json_string_array(table$names[kept]),
    ",\"key\":", json_string_array(key_columns),
    ",\"rows\":", commitment_rows(table, kept, key), "}"
  )
  charToRaw(text)
}

# The message of the commitment to an outcome column (documents.md, Outcome
# column commitment): the canonical bytes of the column's name, the
# observation key and, for each row of the table, the key values followed by
# the value of the column. column is the name that the access log records.
# NULL when the column or a column of the key is not a column of the table.
outcome_column_message <- function(table, declaration, column) {
  key_columns <- observation_key_columns(declaration)
  key <- table_positions(table, key_columns)
  outcome <- table_positions(table, column)
  if (is.null(key) || is.null(outcome)) {
    return(NULL)
  }
  text <- paste0(
    "{\"column\":", quote_json_strings(column),
    ",\"key\":", json_string_array(key_columns),
    ",\"rows\":", commitment_rows(table, c(key, outcome), key), "}"
  )
  charToRaw(text)
}

# The canonical bytes of an array of strings, as text.
json_string_array <- function(x) {
  if (!length(x)) {
    return("[]")
  }
  paste0("[", paste(quote_json_strings(x), collapse = ","), "]")
}

# The commitments of /inputs/data for the data of a run under a key, as 64
# lower-case hexadecimal digits: the analysis table always, and the data file
# when the run read one. response is the response column of the IR, or NULL.
data_commitments <- function(run, declaration, response, key) {
  commitments <- list(analysis_table = keyed_commitment(
    analysis_table_message(run$table, declaration, response), key, "analysis_table"
  ))
  if (!is.null(run$file)) {
    commitments$data_file <- keyed_commitment(run$file, key, "data_file")
  }
  commitments
}

# The commitment of an access log entry to an outcome column of the data of a
# run, the response or its trials column, under a key.
outcome_commitment <- function(run, declaration, column, key) {
  keyed_commitment(outcome_column_message(run$table, declaration, column), key, "outcome_column")
}
