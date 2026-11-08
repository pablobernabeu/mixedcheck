# UTF-8 validation, encoding marks, NFC and the comparison and order of
# identifiers and labels (docs/spec/conventions.md, Text and Unicode).

# Returns the 0-based offset of the first ill-formed sequence in a raw vector,
# found by decoding from the start by Table 3-7 of the Unicode Standard, or NA
# when the bytes are valid UTF-8. A truncated sequence is reported at its lead
# byte and a stray continuation byte at its own offset.
utf8_invalid_offset <- function(bytes) {
  bad <- utf8_invalid_positions(bytes)
  if (length(bad)) bad[1L] - 1L else NA_integer_
}

# The 1-based positions at which a decoder that restarts after each ill-formed
# sequence finds one. The first is the offset that utf8_invalid_offset()
# reports, and a part of the input between ASCII bytes holds one exactly when
# it is not valid UTF-8.
utf8_invalid_positions <- function(bytes) {
  b <- as.integer(bytes)
  n <- length(b)
  # ASCII bytes are well-formed sequences of one byte, so only the other
  # bytes need checking.
  at <- which(b >= 0x80L)
  if (length(at) == 0L) {
    return(integer(0))
  }
  byte_at <- function(i) {
    v <- rep(-1L, length(i))
    inside <- i <= n
    v[inside] <- b[i[inside]]
    v
  }
  lead <- b[at]
  b1 <- byte_at(at + 1L)
  b2 <- byte_at(at + 2L)
  b3 <- byte_at(at + 3L)
  in_range <- function(v, low, high) v >= low & v <= high
  tail <- function(v) in_range(v, 0x80L, 0xBFL)
  # Whether a well-formed sequence starts at each byte, and its length.
  valid <- logical(length(at))
  size <- integer(length(at))
  two <- in_range(lead, 0xC2L, 0xDFL)
  valid[two] <- tail(b1[two])
  size[two] <- 2L
  three <- in_range(lead, 0xE0L, 0xEFL)
  second <- tail(b1)
  second[lead == 0xE0L] <- in_range(b1[lead == 0xE0L], 0xA0L, 0xBFL)
  second[lead == 0xEDL] <- in_range(b1[lead == 0xEDL], 0x80L, 0x9FL)
  valid[three] <- second[three] & tail(b2[three])
  size[three] <- 3L
  four <- in_range(lead, 0xF0L, 0xF4L)
  second <- tail(b1)
  second[lead == 0xF0L] <- in_range(b1[lead == 0xF0L], 0x90L, 0xBFL)
  second[lead == 0xF4L] <- in_range(b1[lead == 0xF4L], 0x80L, 0x8FL)
  valid[four] <- second[four] & tail(b2[four]) & tail(b3[four])
  size[four] <- 4L
  # A continuation byte is covered when a well-formed sequence that starts
  # one to three bytes earlier extends over it.
  starts <- at[valid]
  lengths_of <- size[valid]
  covered_at <- c(starts + 1L, starts[lengths_of >= 3L] + 2L, starts[lengths_of >= 4L] + 3L)
  continuation <- tail(lead)
  at[(!continuation & !valid) | (continuation & !(at %in% covered_at))]
}

# The code points of the UTF-8 sequences that start at the given 1-based
# positions of a valid UTF-8 byte vector.
utf8_codepoints_at <- function(b, at) {
  n <- length(b)
  lead <- b[at]
  next_byte <- function(k) {
    i <- at + k
    ifelse(i <= n, b[pmin(i, n)], 0L)
  }
  c1 <- next_byte(1L) %% 64L
  c2 <- next_byte(2L) %% 64L
  c3 <- next_byte(3L) %% 64L
  ifelse(lead < 0x80L, lead,
    ifelse(lead < 0xE0L, (lead %% 32L) * 64L + c1,
      ifelse(lead < 0xF0L, (lead %% 16L) * 4096L + c1 * 64L + c2,
        (lead %% 8L) * 262144L + c1 * 4096L + c2 * 64L + c3)))
}

# The ranges of code points that Unicode 14.0 assigns, from the vendored
# spec/unicode/assigned-14.0.json.
assigned_ranges <- function() {
  ranges <- mixedcheck_cache$assigned
  if (is.null(ranges)) {
    document <- read_json_strict(installed_path("spec", "unicode", "assigned-14.0.json"),
                                 "data")
    pairs <- document[["ranges"]]
    ranges <- list(
      first = vapply(pairs, function(pair) pair[[1L]], 0),
      last = vapply(pairs, function(pair) pair[[2L]], 0)
    )
    mixedcheck_cache$assigned <- ranges
  }
  ranges
}

# Whether each code point is assigned in Unicode 14.0.
codepoints_assigned <- function(codepoints) {
  ranges <- assigned_ranges()
  i <- findInterval(codepoints, ranges$first)
  i > 0L & codepoints <= ranges$last[pmax(i, 1L)]
}

# Whether each string holds only code points that Unicode 14.0 assigns, so
# that both packages normalise it in the same way. x is ASCII or marked UTF-8.
is_normalisable <- function(x) {
  result <- rep(TRUE, length(x))
  wide <- which(has_non_ascii(x))
  if (length(wide)) {
    codepoints <- lapply(x[wide], utf8ToInt)
    owner <- rep(seq_along(wide), lengths(codepoints))
    unassigned <- !codepoints_assigned(unlist(codepoints, use.names = FALSE))
    result[wide] <- tabulate(owner[unassigned], nbins = length(wide)) == 0L
  }
  result
}

# NFC of strings that are ASCII or marked UTF-8.
nfc <- function(x) {
  result <- x
  wide <- has_non_ascii(x)
  if (any(wide)) {
    result[wide] <- utf8::utf8_normalize(x[wide])
  }
  result
}

# The form in which identifiers and labels are compared: the NFC form of a
# normalisable string and the string itself otherwise.
comparison_form <- function(x) {
  result <- x
  normalise <- is_normalisable(x) & has_non_ascii(x)
  if (any(normalise)) {
    result[normalise] <- utf8::utf8_normalize(x[normalise])
  }
  result
}

# Compares two identifiers or labels by the code points of their comparison
# forms, with a prefix first. Returns -1, 0 or 1.
compare_identifiers <- function(first, second) {
  a <- utf8ToInt(comparison_form(first))
  b <- utf8ToInt(comparison_form(second))
  common <- min(length(a), length(b))
  differ <- which(a[seq_len(common)] != b[seq_len(common)])
  if (length(differ)) {
    return(if (a[differ[1L]] < b[differ[1L]]) -1L else 1L)
  }
  as.integer(sign(length(a) - length(b)))
}

# Sorts identifiers or labels by the code points of their comparison forms.
# For strings that are ASCII or marked UTF-8, the radix method compares bytes,
# which orders UTF-8 by code point in every locale.
sort_identifiers <- function(x) {
  x[order(comparison_form(x), method = "radix")]
}

# Whether each string holds a byte of 80 or above.
has_non_ascii <- function(x) {
  grepl("[^\\x01-\\x7F]", x, useBytes = TRUE, perl = TRUE)
}

# Whether the session's native encoding is UTF-8. A function of its own, so
# that the tests can replace it.
native_utf8 <- function() {
  isTRUE(l10n_info()[["UTF-8"]])
}

# The input boundary of conventions.md (Strings in R) for a value in memory
# that the caller passes in: in a session whose native encoding is UTF-8, the
# strings and names with non-ASCII bytes and no declared encoding are marked
# UTF-8, and the writer then refuses those that are not valid UTF-8 (E1201).
# In any other session they stay unmarked, and the writer refuses them
# (E1204).
mark_input_strings <- function(x) {
  if (!native_utf8()) {
    return(x)
  }
  mark <- function(strings) {
    unmarked <- which(Encoding(strings) == "unknown" & has_non_ascii(strings))
    if (length(unmarked)) {
      Encoding(strings)[unmarked] <- "UTF-8"
    }
    strings
  }
  walk <- function(value) {
    if (is.character(value) && is.null(attr(value, "class"))) {
      return(mark(value))
    }
    if (is.list(value) && is.null(attr(value, "class"))) {
      keys <- names(value)
      for (i in seq_along(value)) {
        if (!is.null(value[[i]])) {
          value[[i]] <- walk(value[[i]])
        }
      }
      if (!is.null(keys)) {
        names(value) <- mark(keys)
      }
    }
    value
  }
  walk(x)
}
