# The RFC 8785 serialiser (docs/spec/conventions.md, Serialisation and
# Profiles). It checks a value in the order of its canonical serialisation,
# keys before values, reports the first violation by JSON Pointer and writes
# the canonical bytes.

#' Canonical bytes of a value
#'
#' Serialises an R value as JSON by RFC 8785, the JSON Canonicalization Scheme,
#' and returns its UTF-8 bytes: members sorted by their keys, no white space,
#' strings with the minimal escapes and numbers written as ECMAScript writes
#' them, the shortest decimal that converts back to the same double. The value
#' is checked against the rules of the profile first.
#'
#' A named list is an object and an unnamed list an array, a character string
#' a string, a double or integer a number and a logical value a boolean.
#' Vectors must have length 1. `NULL` and `NA` of any type are null, which
#' only the data profile and the plain mode accept. In the data profile and
#' the plain mode, `NaN`, `Inf` and `-Inf` are written as the strings 'NaN',
#' 'Infinity' and '-Infinity'. Strings must be ASCII or marked UTF-8 or
#' latin1, in every locale, since the encoding of an unmarked string with other
#' bytes cannot be known. The value that [validate_declaration()] returns
#' holds marked strings.
#'
#' @param x The value to write.
#' @param profile The profile: `"data"`, `"hashable"` or `"plain"`.
#' @return A raw vector with the canonical bytes.
#' @section Errors: A value that cannot be written is signalled as an error of
#'   class `mixedcheck_error`, whose element `issues` holds one issue with the
#'   `code` of the shared error catalogue, the rendered `message` and the JSON
#'   Pointer of the value as `pointer`.
#' @export
#' @examples
#' bytes <- canonical_bytes(list(b = list(1.5, TRUE), a = "x"), "hashable")
#' rawToChar(bytes)
#' rawToChar(canonical_bytes(list(1e21, 0.1 + 0.2, 1e-7)))
canonical_bytes <- function(x, profile = c("data", "hashable", "plain")) {
  profile <- profile_argument(profile)
  charToRaw(write_canonical(x, profile))
}

#' Hash of the canonical bytes of a value
#'
#' The SHA-256 hash of the canonical bytes of a value, written as documents
#' write hashes: 'sha256:' followed by 64 lower-case hexadecimal digits.
#'
#' @inheritParams canonical_bytes
#' @return A character string.
#' @inheritSection canonical_bytes Errors
#' @export
#' @examples
#' canonical_hash(list(title = "study", n = list(1, 2.5)), "hashable")
canonical_hash <- function(x, profile = c("data", "hashable", "plain")) {
  hash_bytes(canonical_bytes(x, profile))
}

# The JSON Pointer of a path, with '~' written '~0' and '/' written '~1'.
json_pointer <- function(path) {
  if (length(path) == 0L) {
    return("")
  }
  escaped <- gsub("/", "~1", gsub("~", "~0", path, fixed = TRUE), fixed = TRUE)
  paste0("/", escaped, collapse = "")
}

# Writes a value as canonical JSON text. The value is walked once in the
# order of its canonical serialisation, keys before values. Structural
# problems stop the walk where they occur. Strings and finite doubles are then
# checked and formatted together, and the problem that comes first in the
# canonical order, from the walk or from those checks, is reported.
write_canonical <- function(x, profile) {
  hashable <- profile == "hashable"
  # Containers, numbered as they open, with the parent and token of each, from
  # which pointers are built.
  parents <- integer(64L)
  tokens <- character(64L)
  containers <- 0L
  # Strings and finite doubles, with their position in the canonical order,
  # their container and their token in it.
  leaf_values <- vector("list", 256L)
  leaf_position <- integer(256L)
  leaf_container <- integer(256L)
  leaf_token <- character(256L)
  leaves <- 0L
  position <- 0L
  failure <- NULL
  # The ordering and quoted form of each set of plain ASCII keys met, since
  # many objects of a document share their keys.
  key_cache <- new.env(hash = TRUE, parent = emptyenv())

  fail <- function(code, container, token = NA_character_, args = list()) {
    failure <<- list(code = code, position = position, container = container,
                     token = token, args = args)
    NULL
  }

  add_leaf <- function(value, container, token) {
    leaves <<- leaves + 1L
    if (leaves > length(leaf_position)) {
      size <- 2L * leaves
      length(leaf_values) <<- size
      length(leaf_position) <<- size
      length(leaf_container) <<- size
      length(leaf_token) <<- size
    }
    leaf_values[[leaves]] <<- value
    leaf_position[leaves] <<- position
    leaf_container[leaves] <<- container
    leaf_token[leaves] <<- token
    NA_character_
  }

  visit_scalar <- function(v, container, token) {
    position <<- position + 1L
    if (is.null(v)) {
      if (hashable) {
        return(fail("E1101", container, token))
      }
      return("null")
    }
    if (!is.null(attr(v, "class")) || !is.null(attr(v, "dim"))) {
      return(fail("E1301", container, token, list(type = class(v)[1L])))
    }
    type <- typeof(v)
    if (!type %in% c("logical", "integer", "double", "character")) {
      return(fail("E1301", container, token, list(type = type)))
    }
    if (length(v) != 1L) {
      return(fail("E1302", container, token, list(length = length(v))))
    }
    if (is.na(v) && !(type == "double" && is.nan(v))) {
      if (hashable) {
        return(fail("E1101", container, token))
      }
      return("null")
    }
    if (type == "logical") {
      return(if (v) "true" else "false")
    }
    if (type == "integer") {
      return(as.character(v))
    }
    if (type == "double" && !is.finite(v)) {
      if (hashable) {
        return(fail("E1107", container, token))
      }
      return(if (is.nan(v)) "\"NaN\"" else if (v > 0) "\"Infinity\"" else "\"-Infinity\"")
    }
    add_leaf(v, container, token)
  }

  visit_list <- function(x, parent, token, depth) {
    position <<- position + 1L
    containers <<- containers + 1L
    id <- containers
    if (id > length(parents)) {
      length(parents) <<- 2L * id
      length(tokens) <<- 2L * id
    }
    parents[id] <<- parent
    tokens[id] <<- token
    if (depth == 64L) {
      return(fail("E1030", id, args = list(limit = 64L)))
    }
    count <- length(x)
    keys <- attr(x, "names")
    object <- !is.null(keys)
    if (count == 0L) {
      return(if (object) "{}" else "[]")
    }
    plain_keys <- NULL
    if (object) {
      if (anyNA(keys) || any(keys == "")) {
        return(fail("E1303", id))
      }
      # Keys of printable ASCII characters other than '"' and '\\' need no
      # check and no escape, so only their order and duplicates matter.
      if (!any(grepl("[^\\x20-\\x7E]|[\"\\\\]", keys, useBytes = TRUE, perl = TRUE))) {
        # The keys joined serve as the name of a variable in the cache, which
        # R limits to 10,000 bytes, so longer sets of keys are not cached.
        cache_key <- paste(keys, collapse = "\001")
        cacheable <- nchar(cache_key, type = "bytes") <= 10000L
        plain_keys <- if (cacheable) key_cache[[cache_key]]
        if (is.null(plain_keys)) {
          plain_keys <- list(
            duplicated = anyDuplicated(keys) > 0L,
            ordering = order(keys, method = "radix"),
            quoted = paste0("\"", keys, "\":")
          )
          if (cacheable) {
            assign(cache_key, plain_keys, envir = key_cache)
          }
        }
        if (plain_keys$duplicated) {
          return(fail("E1303", id))
        }
      }
    }
    if (!is.null(plain_keys)) {
      member_tokens <- keys
      ordering <- plain_keys$ordering
      key_codes <- rep(NA_character_, count)
      quoted <- plain_keys$quoted
    } else if (object) {
      # A name that cannot be read as text cannot appear in a pointer, so its
      # problem is reported at the pointer of the object.
      checked <- writer_strings(keys)
      bad <- which(!is.na(checked$code))
      if (length(bad)) {
        return(fail(checked$code[bad[1L]], id))
      }
      member_tokens <- checked$value
      if (anyDuplicated(member_tokens)) {
        return(fail("E1303", id))
      }
      ordering <- utf16_order(member_tokens)
      key_codes <- key_profile_codes(member_tokens, profile)
      quoted <- paste0(quote_json_strings(member_tokens), ":")
    } else {
      member_tokens <- as.character(seq_len(count) - 1L)
      ordering <- seq_len(count)
    }
    pieces <- vector("list", 2L * count + 1L)
    pieces[[1L]] <- if (object) "{" else "["
    for (j in seq_len(count)) {
      i <- ordering[j]
      if (object) {
        position <<- position + 1L
        if (!is.na(key_codes[i])) {
          return(fail(key_codes[i], id, member_tokens[i]))
        }
      }
      v <- x[[i]]
      piece <- if (is.list(v) && is.null(attr(v, "class")) && is.null(attr(v, "dim"))) {
        visit_list(v, id, member_tokens[i], depth + 1L)
      } else {
        visit_scalar(v, id, member_tokens[i])
      }
      if (!is.null(failure)) {
        return(NULL)
      }
      pieces[[2L * j]] <- if (object) c(quoted[i], piece) else piece
      pieces[[2L * j + 1L]] <- ","
    }
    pieces[[2L * count + 1L]] <- if (object) "}" else "]"
    unlist(pieces, use.names = FALSE)
  }

  pointer_of <- function(container, token) {
    path <- if (is.na(token)) character(0) else token
    while (container > 1L) {
      path <- c(tokens[container], path)
      container <- parents[container]
    }
    json_pointer(path)
  }

  if (is.list(x) && is.null(attr(x, "class")) && is.null(attr(x, "dim"))) {
    pieces <- visit_list(x, 0L, NA_character_, 0L)
  } else {
    pieces <- visit_scalar(x, 0L, NA_character_)
  }

  # Strings and doubles, in canonical order, each with the code that refuses
  # it or NA, and its text.
  count <- leaves
  values <- leaf_values[seq_len(count)]
  is_string <- vapply(values, is.character, NA)
  code <- rep(NA_character_, count)
  text <- character(count)
  args <- vector("list", count)
  if (any(is_string)) {
    strings <- writer_strings(unlist(values[is_string], use.names = FALSE))
    string_code <- strings$code
    if (hashable) {
      fine <- which(is.na(string_code))
      string_code[fine] <- hashable_string_codes(strings$value[fine])
    }
    code[is_string] <- string_code
    text[is_string] <- quote_json_strings(ifelse(is.na(string_code), strings$value, ""))
  }
  if (any(!is_string)) {
    numbers <- unlist(values[!is_string], use.names = FALSE)
    formatted <- format_numbers(numbers, hashable)
    code[!is_string] <- formatted$code
    text[!is_string] <- formatted$text
    args[!is_string] <- lapply(formatted$text, function(t) list(number = t))
  }
  refused <- which(!is.na(code))
  if (length(refused)) {
    first <- refused[1L]
    if (is.null(failure) || leaf_position[first] < failure$position) {
      failure <- list(code = code[first], position = leaf_position[first],
                      container = leaf_container[first], token = leaf_token[first],
                      args = if (is_string[first]) list() else args[[first]])
    }
  }
  if (!is.null(failure)) {
    raise_issue(failure$code, failure$args,
                pointer = pointer_of(failure$container, failure$token))
  }
  pieces[is.na(pieces)] <- text
  paste(pieces, collapse = "")
}

# Checks strings that a writer or hasher receives and returns them as ASCII or
# marked UTF-8 in value, with the code that refuses each string or NA in code:
# E1205 for a string marked 'bytes', E1204 for an unmarked string with a byte
# of 80 or above and E1201 for a string marked UTF-8 that is not valid UTF-8.
# Strings marked 'latin1' are converted with enc2utf8().
writer_strings <- function(x) {
  code <- rep(NA_character_, length(x))
  encoding <- Encoding(x)
  wide <- has_non_ascii(x)
  code[encoding == "bytes"] <- "E1205"
  code[encoding == "unknown" & wide] <- "E1204"
  latin1 <- encoding == "latin1"
  if (any(latin1)) {
    x[latin1] <- enc2utf8(x[latin1])
  }
  marked <- which(encoding == "UTF-8" & wide)
  if (length(marked)) {
    code[marked[!utf8_valid_strings(x[marked])]] <- "E1201"
  }
  x[!is.na(code)] <- ""
  list(value = x, code = code)
}

# Whether each string marked UTF-8 holds valid UTF-8. The strings are joined
# with line feeds, which cannot be part of an ill-formed sequence, and
# validated together.
utf8_valid_strings <- function(x) {
  sizes <- nchar(x, type = "bytes")
  joined <- unlist(lapply(x, function(s) c(charToRaw(s), as.raw(10L))), use.names = FALSE)
  bad <- utf8_invalid_positions(joined)
  owner <- findInterval(bad, cumsum(sizes + 1L) + 1L) + 1L
  !(seq_along(x) %in% owner)
}

# The codes with which the hashable profile refuses strings: E1208 for a code
# point that Unicode 14.0 does not assign and E1203 for a string not in NFC.
hashable_string_codes <- function(x) {
  code <- rep(NA_character_, length(x))
  wide <- which(has_non_ascii(x))
  if (length(wide)) {
    normalisable <- is_normalisable(x[wide])
    code[wide[!normalisable]] <- "E1208"
    check <- wide[normalisable]
    if (length(check)) {
      code[check[utf8::utf8_normalize(x[check]) != x[check]]] <- "E1203"
    }
  }
  code
}

# The codes with which a profile refuses keys: E1108 for a character outside
# the BMP in either profile, then E1208 and E1203 in the hashable profile.
key_profile_codes <- function(keys, profile) {
  code <- rep(NA_character_, length(keys))
  if (profile == "plain") {
    return(code)
  }
  code[has_non_bmp(keys)] <- "E1108"
  if (profile == "hashable") {
    fine <- which(is.na(code))
    code[fine] <- hashable_string_codes(keys[fine])
  }
  code
}

# Formats finite doubles as Number::toString does and, in the hashable
# profile, returns the code that refuses each one or NA: E1102 for an integer
# outside +-9007199254740991, E1103 for a non-integer whose shortest form has
# more than 15 significant digits and E1104 for one whose shortest form is
# below 1e-307 in magnitude.
format_numbers <- function(x, hashable) {
  count <- length(x)
  text <- rep("0", count)
  code <- rep(NA_character_, count)
  nonzero <- which(x != 0)
  if (length(nonzero)) {
    a <- abs(x[nonzero])
    parts <- number_parts(a)
    laid_out <- ecmascript_layout(parts$digits, parts$n)
    text[nonzero] <- ifelse(x[nonzero] < 0, paste0("-", laid_out), laid_out)
    if (hashable) {
      integer <- a == floor(a)
      code[nonzero[integer & a > 9007199254740991]] <- "E1102"
      code[nonzero[!integer & nchar(parts$digits) > 15L]] <- "E1103"
      code[nonzero[!integer & nchar(parts$digits) <= 15L & parts$n - 1L < -307L]] <- "E1104"
    }
  }
  list(text = text, code = code)
}

# Whether each string holds a character outside the Basic Multilingual Plane,
# whose UTF-8 form starts with a byte from F0 to F4.
has_non_bmp <- function(x) {
  grepl("[\\xF0-\\xF4]", x, useBytes = TRUE, perl = TRUE)
}

# The order of keys by their UTF-16 code units, with a prefix first (RFC 8785,
# section 3.2.3). Without characters outside the BMP, this is the order of the
# UTF-8 bytes, which the radix method gives.
utf16_order <- function(keys) {
  if (!any(has_non_bmp(keys))) {
    return(order(keys, method = "radix"))
  }
  units <- vapply(keys, function(key) {
    codepoints <- utf8ToInt(key)
    wide <- codepoints > 0xFFFFL
    pieces <- as.list(codepoints)
    pieces[wide] <- lapply(codepoints[wide] - 0x10000L, function(v) {
      c(0xD800L + v %/% 1024L, 0xDC00L + v %% 1024L)
    })
    paste(sprintf("%04x", unlist(pieces, use.names = FALSE)), collapse = "")
  }, "", USE.NAMES = FALSE)
  order(units, method = "radix")
}

# Writes strings with the escapes of RFC 8785: '"' and '\' escaped, U+0008,
# U+0009, U+000A, U+000C and U+000D as two-character escapes, other control
# characters as \u00xx and everything else as its UTF-8 bytes. The strings
# are ASCII or marked UTF-8.
quote_json_strings <- function(x) {
  result <- paste0("\"", x, "\"")
  special <- which(grepl("[\\x01-\\x1F\"\\\\]", x, useBytes = TRUE, perl = TRUE))
  short <- c(`8` = "\\b", `9` = "\\t", `10` = "\\n", `12` = "\\f", `13` = "\\r",
             `34` = "\\\"", `92` = "\\\\")
  for (i in special) {
    bytes <- charToRaw(x[i])
    code <- as.integer(bytes)
    escape <- code < 32L | code == 34L | code == 92L
    pieces <- as.list(bytes)
    replacement <- short[as.character(code[escape])]
    long <- is.na(replacement)
    replacement[long] <- sprintf("\\u%04x", code[escape][long])
    pieces[escape] <- lapply(unname(replacement), charToRaw)
    text <- rawToChar(c(as.raw(34L), unlist(pieces, use.names = FALSE), as.raw(34L)))
    Encoding(text) <- "UTF-8"
    result[i] <- text
  }
  result
}
