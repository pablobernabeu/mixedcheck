# The strict JSON reader (docs/spec/conventions.md, Strict reader). It works in
# four stages, input, UTF-8, syntax and values, and reports the first issue
# that they find. The bytes are classified with vectorised operations, and a
# loop over the tokens, not the bytes, checks the grammar, so that a document
# of a few megabytes is read in seconds.

#' Read JSON text with the strict reader
#'
#' Reads a JSON document under one of the two profiles of mixedcheck, or in
#' the plain mode without a profile, and reports the first problem it finds
#' as an error with a stable code. The reader refuses a byte-order mark,
#' invalid UTF-8, duplicate keys, empty keys, unpaired surrogate escapes,
#' U+0000, NaN and the infinities, numbers that a double cannot hold and
#' containers nested more than 64 levels deep. The hashable profile also
#' refuses null, keys outside the Basic Multilingual Plane, integers beyond
#' 9007199254740991 in magnitude, non-integers with more than 15 significant
#' digits or below 1e-307 in magnitude, and strings that are not in Unicode
#' normalisation form C or hold a code point that Unicode 14.0 does not
#' assign. The data profile also refuses keys outside the Basic Multilingual
#' Plane.
#'
#' Numbers are converted to the nearest double with correct rounding, through
#' jsonlite's parser, never with `as.numeric()`.
#'
#' @param source A file path, as a character string, or the bytes of the input,
#'   as a raw vector.
#' @param profile The profile: `"data"`, `"hashable"` or `"plain"`.
#' @return The value read: objects as named lists, with members in the order of
#'   the input, arrays as unnamed lists, strings as character strings marked
#'   UTF-8, numbers as doubles, booleans as logical values and null as `NULL`.
#'   An empty object is `setNames(list(), character(0))`.
#' @section Errors: A problem is signalled as an error of class
#'   `mixedcheck_error`, whose element `issues` holds one issue: a list with
#'   the `code` of the shared error catalogue, the rendered `message` and the
#'   byte `offset` at which the problem lies, counted from 0, when the code
#'   has a location.
#' @export
#' @examples
#' read_json_strict(charToRaw('{"b": [1.50, true], "a": "x"}'), "hashable")
#'
#' path <- tempfile(fileext = ".json")
#' writeBin(charToRaw('{"a": 1, "a": 2}'), path)
#' problem <- tryCatch(read_json_strict(path), mixedcheck_error = function(e) e)
#' problem$issues[[1]]$code
#' unlink(path)
read_json_strict <- function(source, profile = c("data", "hashable", "plain")) {
  profile <- profile_argument(profile)
  parse_json_bytes(read_input_bytes(source), profile)
}

# The value of an argument with a fixed set of choices, the first by default.
# Only the exact names are accepted, without the abbreviations that
# match.arg() allows, as in the Python package.
exact_choice <- function(value, choices, message) {
  if (identical(value, choices)) {
    return(choices[[1L]])
  }
  if (!is.character(value) || length(value) != 1L || is.na(value) || !value %in% choices) {
    stop(message, call. = FALSE)
  }
  value
}

profile_argument <- function(profile) {
  exact_choice(profile, c("data", "hashable", "plain"),
               "'profile' must be 'data', 'hashable' or 'plain'.")
}

# Stage 1 for a file: the bytes of the file, or E1001 and E1002.
read_input_bytes <- function(source) {
  if (is.raw(source)) {
    return(source)
  }
  if (!is.character(source) || length(source) != 1L || is.na(source)) {
    stop("'source' must be a file path or a raw vector.", call. = FALSE)
  }
  if (!file.exists(source)) {
    raise_issue("E1001")
  }
  if (dir.exists(source) || file.access(source, 4L) != 0L) {
    raise_issue("E1002")
  }
  size <- file.size(source)
  bytes <- tryCatch(
    readBin(source, "raw", n = size),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(bytes) || length(bytes) != size) {
    raise_issue("E1002")
  }
  bytes
}

parse_json_bytes <- function(bytes, profile) {
  n <- length(bytes)
  if (n >= 3L && bytes[1L] == as.raw(0xEF) && bytes[2L] == as.raw(0xBB) &&
      bytes[3L] == as.raw(0xBF)) {
    raise_issue("E1003")
  }
  invalid <- utf8_invalid_offset(bytes)
  if (!is.na(invalid)) {
    raise_issue("E1201", offset = invalid)
  }
  lexed <- json_lex(bytes)
  structure <- json_syntax(lexed)
  scalars <- json_values(lexed, structure, profile)
  json_build(lexed, structure, scalars)
}

# Token kinds.
token_open_object <- 1L
token_close_object <- 2L
token_open_array <- 3L
token_close_array <- 4L
token_colon <- 5L
token_comma <- 6L
token_string <- 7L
token_word <- 8L

# The class of each byte outside strings: 1 for white space, 2 for a
# structural character, 3 for '"', 4 for '\\' and 0 for any other byte.
json_byte_class <- local({
  classes <- integer(256L)
  classes[c(32L, 9L, 10L, 13L) + 1L] <- 1L
  classes[c(123L, 125L, 91L, 93L, 58L, 44L) + 1L] <- 2L
  classes[34L + 1L] <- 3L
  classes[92L + 1L] <- 4L
  classes
})

# Classifies every byte and returns the tokens of the input: the structural
# characters, the strings, from an opening quote to the next quote that no
# backslash escapes, and the words, the runs of other bytes outside strings.
# Up to the first syntax error, these tokens are those of the grammar, since
# a backslash or a quote can escape or end a string wrongly only after it.
json_lex <- function(bytes) {
  b <- as.integer(bytes)
  n <- length(b)
  position <- seq_len(n)
  byte_class <- json_byte_class[b + 1L]
  backslash <- byte_class == 4L
  escaped <- logical(n)
  if (any(backslash)) {
    last_other <- cummax(position * !backslash)
    run <- position - last_other
    escaped <- c(FALSE, (run %% 2L == 1L)[-n])
  }
  quote <- byte_class == 3L & !escaped
  quotes <- cumsum(quote)
  inside <- (quotes %% 2L == 1L) & !quote
  outside <- !inside & !quote
  space <- outside & byte_class == 1L
  structural <- outside & byte_class == 2L
  other <- outside & byte_class != 1L & byte_class != 2L
  word_start <- other & !c(FALSE, other[-n])
  word_end <- other & !c(other[-1L], FALSE)

  quote_at <- which(quote)
  odd <- seq_along(quote_at) %% 2L == 1L
  opens <- quote_at[odd]
  closes <- quote_at[!odd]
  closes <- c(closes, rep(NA_integer_, length(opens) - length(closes)))

  at <- which(structural)
  kinds <- c(`123` = token_open_object, `125` = token_close_object,
             `91` = token_open_array, `93` = token_close_array,
             `58` = token_colon, `44` = token_comma)
  words <- which(word_start)
  token_pos <- c(at, opens, words)
  token_kind <- c(unname(kinds[as.character(b[at])]), rep(token_string, length(opens)),
                  rep(token_word, length(words)))
  token_end <- c(at, closes, which(word_end))
  token_string_index <- c(integer(length(at)), seq_along(opens), integer(length(words)))
  token_word_index <- c(integer(length(at)), integer(length(opens)), seq_along(words))
  ordering <- order(token_pos)

  # The first problem inside each string: a raw control character (E1024), an
  # escape that is not valid (E1025) or the end of the input inside an escape
  # (E1021), in the order of the input.
  problem_pos <- integer(0)
  problem_code <- character(0)
  control <- which(inside & b < 32L & !escaped)
  if (length(control)) {
    problem_pos <- control
    problem_code <- rep("E1024", length(control))
  }
  starts <- which(backslash & inside & !escaped)
  if (length(starts)) {
    byte_at <- function(i) ifelse(i <= n, b[pmin(i, n)], -1L)
    letter <- byte_at(starts + 1L)
    simple <- letter %in% c(34L, 92L, 47L, 98L, 102L, 110L, 114L, 116L)
    code <- ifelse(letter == -1L, "E1021", ifelse(simple, NA_character_, "E1025"))
    unicode <- letter == 117L
    if (any(unicode)) {
      hex <- function(v) (v >= 48L & v <= 57L) | (v >= 65L & v <= 70L) | (v >= 97L & v <= 102L)
      found <- rep(NA_character_, length(starts))
      for (k in 5:2) {
        v <- byte_at(starts + k)
        found <- ifelse(v == -1L, "E1021", ifelse(hex(v), found, "E1025"))
      }
      code[unicode] <- found[unicode]
    }
    bad <- !is.na(code)
    problem_pos <- c(problem_pos, starts[bad])
    problem_code <- c(problem_code, code[bad])
  }
  problem_order <- order(problem_pos)
  problem_pos <- problem_pos[problem_order]
  problem_code <- problem_code[problem_order]
  string_problem_code <- rep(NA_character_, length(opens))
  string_problem_offset <- rep(NA_integer_, length(opens))
  if (length(opens)) {
    following <- findInterval(opens, problem_pos) + 1L
    limit <- ifelse(is.na(closes), n + 1L, closes)
    has <- following <= length(problem_pos)
    has[has] <- problem_pos[following[has]] < limit[has]
    string_problem_code[has] <- problem_code[following[has]]
    string_problem_offset[has] <- ifelse(problem_code[following[has]] == "E1021", n,
                                         problem_pos[following[has]] - 1L)
    unterminated <- !has & is.na(closes)
    string_problem_code[unterminated] <- "E1021"
    string_problem_offset[unterminated] <- n
  }

  # Words are classified on an ASCII copy of the input, in which every other
  # byte is '?', so that no word with such a byte is valid.
  ascii <- bytes
  ascii[b >= 128L | b == 0L] <- as.raw(63L)
  ascii_text <- rawToChar(ascii)
  word_text <- if (length(words)) substring(ascii_text, words, which(word_end)) else character(0)
  word_class <- match(word_text, c("true", "false", "null"))
  number <- is.na(word_class) &
    grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", word_text, perl = TRUE)
  word_class[number] <- 4L
  word_class[is.na(word_class)] <- 0L

  list(
    bytes = bytes,
    b = b,
    n = n,
    pos = token_pos[ordering],
    end = token_end[ordering],
    kind = token_kind[ordering],
    string_index = token_string_index[ordering],
    word_index = token_word_index[ordering],
    string_open = opens,
    string_close = closes,
    string_problem_code = string_problem_code,
    string_problem_offset = string_problem_offset,
    word_text = word_text,
    word_class = word_class
  )
}

# Grammar states.
state_value <- 1L
state_value_or_close <- 2L
state_key_or_close <- 3L
state_key <- 4L
state_colon <- 5L
state_after_value <- 6L
state_end <- 7L

# Stage 3: checks the tokens against the grammar of RFC 8259 and the limit on
# nesting, and returns for each token its role (1 for a key, 2 for a value),
# its parent container and, for a member's value, the token of its key.
json_syntax <- function(lexed) {
  kind <- lexed$kind
  pos <- lexed$pos
  count <- length(kind)
  # The strings with a problem inside and the words that are neither a
  # literal nor a number, whose problem is reported if the grammar reaches it.
  faulty <- logical(count)
  strings <- kind == token_string
  faulty[strings] <- !is.na(lexed$string_problem_code[lexed$string_index[strings]])
  words <- kind == token_word
  faulty[words] <- lexed$word_class[lexed$word_index[words]] == 0L
  parent <- integer(count)
  role <- integer(count)
  key_token <- integer(count)
  level <- integer(count)
  stack <- integer(65L)
  object <- logical(65L)
  depth <- 0L
  state <- state_value
  last_key <- 0L
  i <- 0L
  repeat {
    i <- i + 1L
    if (i > count) {
      if (state == state_end) {
        break
      }
      raise_issue("E1021", offset = lexed$n)
    }
    t <- kind[i]
    if (state <= state_value_or_close) {
      if (t == token_close_array && state == state_value_or_close) {
        depth <- depth - 1L
        state <- if (depth == 0L) state_end else state_after_value
        next
      }
      if (t == token_open_object || t == token_open_array) {
        if (depth == 64L) {
          raise_issue("E1030", list(limit = 64L), offset = pos[i] - 1L)
        }
        if (depth > 0L) {
          parent[i] <- stack[depth]
          if (object[depth]) {
            key_token[i] <- last_key
          }
        }
        role[i] <- 2L
        depth <- depth + 1L
        stack[depth] <- i
        object[depth] <- t == token_open_object
        level[i] <- depth
        state <- if (t == token_open_object) state_key_or_close else state_value_or_close
        next
      }
      if (t < token_string) {
        syntax_unexpected(lexed, pos[i])
      }
      if (faulty[i]) {
        if (t == token_string) string_problem(lexed, i) else word_problem(lexed, i, depth)
      }
      role[i] <- 2L
      if (depth > 0L) {
        parent[i] <- stack[depth]
        if (object[depth]) {
          key_token[i] <- last_key
        }
        state <- state_after_value
      } else {
        state <- state_end
      }
    } else if (state <= state_key) {
      if (t == token_close_object && state == state_key_or_close) {
        depth <- depth - 1L
        state <- if (depth == 0L) state_end else state_after_value
        next
      }
      if (t != token_string) {
        syntax_unexpected(lexed, pos[i])
      }
      if (faulty[i]) {
        string_problem(lexed, i)
      }
      parent[i] <- stack[depth]
      role[i] <- 1L
      last_key <- i
      state <- state_colon
    } else if (state == state_colon) {
      if (t != token_colon) {
        syntax_unexpected(lexed, pos[i])
      }
      state <- state_value
    } else if (state == state_after_value) {
      if (t == token_comma) {
        state <- if (object[depth]) state_key else state_value
      } else if ((t == token_close_object && object[depth]) ||
                 (t == token_close_array && !object[depth])) {
        depth <- depth - 1L
        state <- if (depth == 0L) state_end else state_after_value
      } else {
        syntax_unexpected(lexed, pos[i])
      }
    } else {
      raise_issue("E1023", offset = pos[i] - 1L)
    }
  }
  list(parent = parent, role = role, key_token = key_token, level = level)
}

# E1022 naming the character that starts at a 1-based position.
syntax_unexpected <- function(lexed, at) {
  raise_issue("E1022", list(character = character_at(lexed$b, at)), offset = at - 1L)
}

# The code point of the character that starts at a 1-based position of valid
# UTF-8 bytes.
character_at <- function(b, at) {
  utf8_codepoints_at(b, at)
}

# Reports the first problem inside a string token, if it has one.
string_problem <- function(lexed, i) {
  index <- lexed$string_index[i]
  code <- lexed$string_problem_code[index]
  if (is.na(code)) {
    return(invisible())
  }
  offset <- lexed$string_problem_offset[index]
  if (code == "E1024") {
    raise_issue("E1024", list(codepoint = lexed$b[offset + 1L]), offset = offset)
  }
  raise_issue(code, offset = offset)
}

# Reports the problem of a word at a value position that is neither a literal
# nor a number, by the rules for a value position in conventions.md (Syntax).
word_problem <- function(lexed, i, depth) {
  b <- lexed$b
  n <- lexed$n
  at <- lexed$pos[i]
  starts_with <- function(text) {
    pattern <- utf8ToInt(text)
    last <- at + length(pattern) - 1L
    last <= n && all(b[at:last] == pattern)
  }
  for (literal in c("NaN", "Infinity", "-Infinity")) {
    if (starts_with(literal)) {
      raise_issue("E1027", list(literal = literal), offset = at - 1L)
    }
  }
  first <- b[at]
  # A number run starts at '-', '+', '.' or a digit and also takes in 'e' and
  # 'E', so that a word that starts with 'e' is an unexpected character.
  number_start <- function(v) (v >= 48L & v <= 57L) | v == 43L | v == 45L | v == 46L
  number_byte <- function(v) number_start(v) | v == 101L | v == 69L
  if (number_start(first)) {
    last <- at
    while (last < n && number_byte(b[last + 1L])) {
      last <- last + 1L
    }
    run <- rawToChar(lexed$bytes[at:last])
    if (!grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", run, perl = TRUE)) {
      raise_issue("E1028", list(token = run), offset = at - 1L)
    }
    after_value_problem(lexed, last + 1L, depth)
  }
  literal <- c("true", "false", "null")[match(first, c(116L, 102L, 110L))]
  if (!is.na(literal)) {
    pattern <- utf8ToInt(literal)
    for (j in seq_along(pattern)) {
      here <- at + j - 1L
      if (here > n) {
        raise_issue("E1021", offset = n)
      }
      if (b[here] != pattern[j]) {
        syntax_unexpected(lexed, here)
      }
    }
    after_value_problem(lexed, at + length(pattern), depth)
  }
  syntax_unexpected(lexed, at)
}

# A byte of a word follows a complete value: E1023 after the top-level value
# and E1022 inside a container.
after_value_problem <- function(lexed, at, depth) {
  if (depth == 0L) {
    raise_issue("E1023", offset = at - 1L)
  }
  syntax_unexpected(lexed, at)
}

# Stage 4: decodes the strings and converts the numbers, and checks every key,
# string, number and null against the rules of the mode or profile. The issue
# of the token that starts first is reported, and within a token the first
# rule that fails.
json_values <- function(lexed, structure, profile) {
  b <- lexed$b
  n <- lexed$n
  kind <- lexed$kind
  pos <- lexed$pos
  role <- structure$role
  count <- length(kind)
  token_code <- rep(NA_character_, count)
  token_args <- vector("list", count)

  # Strings, keys included.
  strings <- which(kind == token_string)
  index <- lexed$string_index[strings]
  open <- lexed$string_open[index]
  close <- lexed$string_close[index]
  string_count <- length(strings)
  text <- character(string_count)
  wide_key <- logical(string_count)
  unassigned <- logical(string_count)
  non_ascii <- logical(string_count)
  string_code <- rep(NA_character_, string_count)
  if (string_count) {
    count_in <- function(mask) {
      total <- c(0L, cumsum(mask))
      total[close] - total[open + 1L]
    }
    has_escape <- count_in(b == 92L) > 0L
    non_ascii <- count_in(b >= 128L) > 0L
    wide_key <- count_in(b >= 240L) > 0L
    lead <- which(b >= 192L)
    if (length(lead)) {
      bad_lead <- logical(n)
      bad_lead[lead] <- !codepoints_assigned(utf8_codepoints_at(b, lead))
      unassigned <- count_in(bad_lead) > 0L
    }
    latin1_text <- rawToChar(lexed$bytes)
    Encoding(latin1_text) <- "latin1"
    text <- substring(latin1_text, open + 1L, close - 1L)
    Encoding(text) <- "UTF-8"
    escaped_strings <- which(has_escape)
    if (length(escaped_strings)) {
      decoded <- decode_json_strings(text[escaped_strings])
      string_code[escaped_strings] <- decoded$code
      text[escaped_strings] <- decoded$text
      non_ascii[escaped_strings] <- decoded$non_ascii
      wide_key[escaped_strings] <- decoded$wide
      unassigned[escaped_strings] <- decoded$unassigned
    }
    is_key <- role[strings] == 1L
    fine <- is.na(string_code)
    string_code[fine & is_key & text == ""] <- "E1109"
    if (profile != "plain") {
      string_code[is.na(string_code) & is_key & wide_key] <- "E1108"
    }
    if (profile == "hashable") {
      string_code[is.na(string_code) & unassigned] <- "E1208"
      check <- which(is.na(string_code) & non_ascii)
      if (length(check)) {
        not_nfc <- utf8::utf8_normalize(text[check]) != text[check]
        string_code[check[not_nfc]] <- "E1203"
      }
    }
    keys <- which(is_key)
    if (length(keys)) {
      duplicate <- duplicated(paste0(structure$parent[strings[keys]], ":", text[keys]))
      string_code[keys[duplicate & is.na(string_code[keys])]] <- "E1029"
    }
    token_code[strings] <- string_code
    for (j in which(string_code == "E1029")) {
      token_args[[strings[j]]] <- list(key = text[j])
    }
  }

  # Numbers and literals.
  words <- which(kind == token_word)
  word_class <- lexed$word_class[lexed$word_index[words]]
  numbers <- words[word_class == 4L]
  number_text <- lexed$word_text[lexed$word_index[numbers]]
  number_value <- numeric(0)
  if (length(numbers)) {
    number_value <- as.double(jsonlite::parse_json(
      paste0("[", paste(number_text, collapse = ","), "]"),
      simplifyVector = TRUE
    ))
    if (profile == "hashable") {
      number_code <- hashable_token_codes(number_text)
    } else {
      zero <- !grepl("[1-9]", sub("[eE].*$", "", number_text))
      number_code <- ifelse(is.infinite(number_value), "E1105",
                            ifelse(number_value == 0 & !zero, "E1106", NA_character_))
    }
    token_code[numbers] <- number_code
    for (j in which(!is.na(number_code))) {
      token_args[[numbers[j]]] <- list(number = number_text[j])
    }
  }
  if (profile == "hashable") {
    token_code[words[word_class == 3L]] <- "E1101"
  }

  failing <- which(!is.na(token_code))
  if (length(failing)) {
    first <- failing[1L]
    raise_issue(token_code[first], token_args[[first]] %||% list(), offset = pos[first] - 1L)
  }
  list(
    strings = strings,
    string_text = text,
    numbers = numbers,
    number_value = number_value,
    words = words,
    word_class = word_class
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# Decodes the escapes of strings' contents, all at once. Returns for each
# string its text, the code E1026 for an unpaired surrogate escape or E1202 for
# U+0000, checked in that order, or NA, and whether it holds a character
# outside ASCII, outside the BMP or not assigned in Unicode 14.0.
decode_json_strings <- function(texts) {
  strings <- length(texts)
  pieces <- lapply(texts, utf8ToInt)
  owner <- rep.int(seq_len(strings), lengths(pieces))
  codepoints <- unlist(pieces, use.names = FALSE)
  count <- length(codepoints)
  position <- seq_len(count)
  first_of_string <- c(TRUE, owner[-1L] != owner[-count])
  backslash <- codepoints == 92L
  # The run of backslashes that ends at each character, counted from the
  # start of its string, decides which backslashes start an escape.
  last_other <- cummax(ifelse(backslash, ifelse(first_of_string, position - 1L, 0L), position))
  run <- position - last_other
  run_before <- c(0L, run[-count])
  run_before[first_of_string] <- 0L
  start <- which(backslash & run_before %% 2L == 0L)
  letter <- codepoints[start + 1L]
  value <- integer(length(start))
  simple <- c(`34` = 34L, `92` = 92L, `47` = 47L, `98` = 8L, `102` = 12L, `110` = 10L,
              `114` = 13L, `116` = 9L)
  unicode <- letter == 117L
  value[!unicode] <- simple[as.character(letter[!unicode])]
  if (any(unicode)) {
    hex <- function(v) ifelse(v <= 57L, v - 48L, ifelse(v <= 70L, v - 55L, v - 87L))
    u <- start[unicode]
    value[unicode] <- hex(codepoints[u + 2L]) * 4096L + hex(codepoints[u + 3L]) * 256L +
      hex(codepoints[u + 4L]) * 16L + hex(codepoints[u + 5L])
  }
  size <- ifelse(unicode, 6L, 2L)
  # A high surrogate escape must be followed at once, in the same string, by
  # a low surrogate escape.
  high <- unicode & value >= 0xD800L & value <= 0xDBFFL
  low <- unicode & value >= 0xDC00L & value <= 0xDFFFL
  escapes <- length(start)
  following <- c(start[-1L], NA_integer_)
  following_low <- c(low[-1L], FALSE)
  same_string <- c(owner[start[-1L]] == owner[start[-escapes]], FALSE)
  paired_high <- high & !is.na(following) & following == start + 6L & following_low & same_string
  paired_low <- low & c(FALSE, paired_high[-escapes])
  code <- rep(NA_character_, strings)
  unpaired <- (high & !paired_high) | (low & !paired_low)
  code[unique(owner[start[unpaired]])] <- "E1026"
  pairs <- which(paired_high)
  value[pairs] <- 0x10000L + (value[pairs] - 0xD800L) * 1024L + (value[pairs + 1L] - 0xDC00L)
  # Drop the characters of each escape after its backslash, and every
  # character of the low half of a pair.
  from <- ifelse(paired_low, start, start + 1L)
  change <- tabulate(from, nbins = count + 1L) - tabulate(start + size, nbins = count + 1L)
  keep <- cumsum(change)[seq_len(count)] == 0L
  codepoints[start] <- value
  result <- codepoints[keep]
  result_owner <- owner[keep]
  nul <- unique(result_owner[result == 0L])
  code[nul[is.na(code[nul])]] <- "E1202"
  tally <- function(mask) tabulate(result_owner[mask], nbins = strings) > 0L
  text <- character(strings)
  ok <- which(is.na(code))
  if (length(ok)) {
    grouped <- split(result, factor(result_owner, levels = seq_len(strings)))
    text[ok] <- vapply(grouped[ok], function(v) if (length(v)) intToUtf8(v) else "", "")
  }
  list(
    text = text,
    code = code,
    non_ascii = tally(result >= 128L),
    wide = tally(result > 0xFFFFL),
    unassigned = tally(result >= 128L & !codepoints_assigned(result))
  )
}

# Builds the R value from the tokens, bottom-up by nesting level.
json_build <- function(lexed, structure, scalars) {
  kind <- lexed$kind
  count <- length(kind)
  values <- vector("list", count)
  role <- structure$role
  value_strings <- scalars$strings[role[scalars$strings] == 2L]
  if (length(value_strings)) {
    values[value_strings] <- as.list(scalars$string_text[role[scalars$strings] == 2L])
  }
  if (length(scalars$numbers)) {
    values[scalars$numbers] <- as.list(scalars$number_value)
  }
  values[scalars$words[scalars$word_class == 1L]] <- list(TRUE)
  values[scalars$words[scalars$word_class == 2L]] <- list(FALSE)
  key_text <- character(count)
  key_text[scalars$strings] <- scalars$string_text

  containers <- which(kind == token_open_object | kind == token_open_array)
  members <- which(role == 2L & structure$parent > 0L)
  parent_level <- structure$level[structure$parent[members]]
  container_level <- structure$level[containers]
  for (level in rev(seq_len(max(c(0L, container_level))))) {
    here <- containers[container_level == level]
    children <- members[parent_level == level]
    groups <- split(values[children], factor(structure$parent[children], levels = here))
    objects <- kind[here] == token_open_object
    if (any(objects)) {
      in_object <- children[kind[structure$parent[children]] == token_open_object]
      names_of <- split(key_text[structure$key_token[in_object]],
                        factor(structure$parent[in_object], levels = here[objects]))
      groups[objects] <- mapply(function(group, keys) {
        names(group) <- keys
        group
      }, groups[objects], names_of, SIMPLIFY = FALSE, USE.NAMES = FALSE)
    }
    values[here] <- unname(groups)
  }
  values[[1L]]
}
