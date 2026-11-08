# The error catalogue of spec/errors.json, the rendering of its message
# templates and the conditions that carry issues (docs/spec/errors.md).

# Values that the package computes once per session: the error catalogue, the
# list of assigned code points and powers of 2 and 5 as big integers.
mixedcheck_cache <- new.env(parent = emptyenv())

# Returns the codes of the vendored spec/errors.json as a list named by code.
error_catalogue <- function() {
  catalogue <- mixedcheck_cache$errors
  if (!is.null(catalogue)) {
    return(catalogue)
  }
  if (isTRUE(mixedcheck_cache$loading_errors)) {
    # Reading the catalogue itself failed, so no issue can be rendered.
    stop("The error catalogue spec/errors.json cannot be read.", call. = FALSE)
  }
  mixedcheck_cache$loading_errors <- TRUE
  on.exit(mixedcheck_cache$loading_errors <- FALSE, add = TRUE)
  document <- read_json_strict(installed_path("spec", "errors.json"), "hashable")
  codes <- document[["codes"]]
  names(codes) <- vapply(codes, function(entry) entry[["code"]], "")
  mixedcheck_cache$errors <- codes
  codes
}

# Builds one issue: the code, its rendered message and its location, a 0-based
# byte offset or a JSON Pointer, as the code's location member allows.
new_issue <- function(code, args = list(), offset = NULL, pointer = NULL) {
  entry <- error_catalogue()[[code]]
  if (is.null(entry)) {
    stop(sprintf("Internal error: unknown error code '%s'.", code), call. = FALSE)
  }
  allowed <- switch(entry[["location"]],
    none = character(0),
    offset = "offset",
    pointer = "pointer",
    offset_or_pointer = c("offset", "pointer")
  )
  given <- c(if (!is.null(offset)) "offset", if (!is.null(pointer)) "pointer")
  if (length(given) > 1L || !all(given %in% allowed) ||
      (length(allowed) > 0L && length(given) == 0L)) {
    stop(sprintf("Internal error: wrong location for %s.", code), call. = FALSE)
  }
  location <- NULL
  if (!is.null(offset)) {
    location <- as.integer(offset)
  } else if (!is.null(pointer)) {
    location <- pointer
  }
  issue <- list(code = code, message = render_template(entry, args, location))
  if (!is.null(offset)) {
    issue$offset <- as.integer(offset)
  }
  if (!is.null(pointer)) {
    issue$pointer <- pointer
  }
  issue
}

# Renders a template, replacing each placeholder by its argument rendered
# according to the kind that the catalogue gives it.
render_template <- function(entry, args, location) {
  template <- entry[["template"]]
  kinds <- entry[["args"]]
  # Templates are ASCII, so character positions are byte positions.
  found <- gregexpr("\\{[a-z_]+\\}", template)[[1L]]
  if (found[1L] == -1L) {
    return(template)
  }
  starts <- as.integer(found)
  ends <- starts + attr(found, "match.length") - 1L
  pieces <- character(0)
  previous <- 1L
  for (i in seq_along(starts)) {
    name <- substr(template, starts[i] + 1L, ends[i] - 1L)
    if (identical(name, "location")) {
      value <- render_location(location)
    } else {
      kind <- kinds[[name]]
      if (is.null(kind) || !name %in% names(args)) {
        stop(sprintf("Internal error: no argument '%s' for %s.", name, entry[["code"]]),
             call. = FALSE)
      }
      value <- render_argument(args[[name]], kind)
    }
    pieces <- c(pieces, substr(template, previous, starts[i] - 1L), value)
    previous <- ends[i] + 1L
  }
  pieces <- c(pieces, substr(template, previous, nchar(template)))
  paste(pieces, collapse = "")
}

render_location <- function(location) {
  if (is.numeric(location)) {
    return(paste0("byte ", format_integer(location)))
  }
  if (identical(location, "")) {
    return("(root)")
  }
  display_text(location, limit = NA)
}

render_argument <- function(value, kind) {
  switch(kind,
    text = display_text(value),
    integer = format_integer(value),
    number = format_number(value),
    codepoint = sprintf("%04X", as.integer(value)),
    values = join_alternatives(vapply(value, render_json_value, "")),
    words = join_alternatives(as.character(value)),
    stop(sprintf("Internal error: unknown argument kind '%s'.", kind), call. = FALSE)
  )
}

# Renders one JSON value for the kind 'values'.
render_json_value <- function(value) {
  if (is.null(value)) {
    return("null")
  }
  if (is.character(value)) {
    return(paste0("'", display_text(value), "'"))
  }
  if (is.logical(value)) {
    return(if (value) "true" else "false")
  }
  format_number(as.double(value))
}

# Joins items with ', ', except the last two, which are joined with ' or '.
join_alternatives <- function(items) {
  count <- length(items)
  if (count <= 1L) {
    return(paste(items, collapse = ""))
  }
  paste0(paste(items[-count], collapse = ", "), " or ", items[count])
}

# Writes an integer as decimal digits, with '-' before a negative value.
format_integer <- function(value) {
  if (is.integer(value)) {
    return(as.character(value))
  }
  if (abs(value) < 2^53 && value == floor(value)) {
    digits <- integer_digits(abs(value))
    return(if (value < 0) paste0("-", digits) else digits)
  }
  format_number(value)
}

# Display escaping and truncation of errors.md. x is a string that is ASCII or
# marked UTF-8, or a vector of code points, which can hold U+0000.
display_text <- function(x, limit = 60L) {
  codepoints <- if (is.character(x)) utf8ToInt(enc2utf8(x)) else as.integer(x)
  escape <- codepoints <= 0x1FL | (codepoints >= 0x7FL & codepoints <= 0x9FL) |
    codepoints == 0x2028L | codepoints == 0x2029L
  if (any(escape)) {
    pieces <- as.list(codepoints)
    pieces[escape] <- lapply(sprintf("\\u%04X", codepoints[escape]), utf8ToInt)
    codepoints <- unlist(pieces, use.names = FALSE)
  }
  if (!is.na(limit) && length(codepoints) > limit) {
    codepoints <- c(codepoints[seq_len(limit - 3L)], 46L, 46L, 46L)
  }
  if (length(codepoints) == 0L) {
    return("")
  }
  intToUtf8(codepoints)
}

# The condition that carries issues. Its message is the message of the first
# issue, followed by one line for each further issue.
issue_condition <- function(issues, class) {
  messages <- vapply(issues, function(issue) issue[["message"]], "")
  structure(
    class = c(class, if (class == "mixedcheck_error") "error" else "warning", "condition"),
    list(message = paste(messages, collapse = "\n"), call = NULL, issues = issues)
  )
}

# Signals an error of class mixedcheck_error that carries the issues.
signal_issues <- function(issues) {
  stop(issue_condition(issues, "mixedcheck_error"))
}

# Signals an error with one issue.
raise_issue <- function(code, args = list(), offset = NULL, pointer = NULL) {
  signal_issues(list(new_issue(code, args, offset = offset, pointer = pointer)))
}

# The issues of one phase of a validator, sorted and capped as errors.md
# (Reporting rules) requires. Each raw issue is a list with the code, its
# arguments and its JSON Pointer, or no pointer for a code without a location.
# The issues are rendered, sorted by pointer, code and message, compared code
# point by code point with a prefix first, reported once each and capped at
# 100, with W1490 giving the number left out.
finish_issues <- function(raw, limit = 100L) {
  if (length(raw) == 0L) {
    return(list())
  }
  issues <- lapply(raw, function(issue) {
    new_issue(issue[["code"]], issue[["args"]] %||% list(), pointer = issue[["pointer"]])
  })
  pointers <- vapply(issues, function(issue) issue[["pointer"]] %||% "", "")
  codes <- vapply(issues, function(issue) issue[["code"]], "")
  messages <- vapply(issues, function(issue) issue[["message"]], "")
  ordering <- order(pointers, codes, messages, method = "radix")
  issues <- issues[ordering]
  pointers <- pointers[ordering]
  codes <- codes[ordering]
  messages <- messages[ordering]
  count <- length(issues)
  repeated <- c(FALSE, pointers[-1L] == pointers[-count] & codes[-1L] == codes[-count] &
                  messages[-1L] == messages[-count])
  issues <- issues[!repeated]
  if (length(issues) > limit) {
    rest <- length(issues) - limit
    issues <- c(issues[seq_len(limit)], list(new_issue("W1490", list(count = rest))))
  }
  issues
}

# A raw issue for finish_issues().
raw_issue <- function(code, pointer = NULL, args = list()) {
  list(code = code, args = args, pointer = pointer)
}
