# The rendering of the messages of findings (docs/spec/registry.md,
# Messages): the template, or the fallback when a statistic that the
# template renders is not written, with each placeholder replaced by its
# argument.

# The text of a message of an entry for a finding. values holds the values
# of the statistics by name, with the pseudonyms of labels in a shareable
# document, and written the names of those that the document writes, every
# present statistic in internal mode.
render_message <- function(entry, id, scope, values, written = names(values)) {
  message <- entry[["messages"]][[id]]
  if (is.null(message)) {
    internal_error(sprintf("%s has no message '%s'.", entry[["id"]], id))
  }
  args <- message[["args"]]
  rendered <- vapply(args, function(arg) {
    identical(arg[["source"]], "statistic")
  }, NA)
  complete <- all(vapply(args[rendered], function(arg) arg[["name"]] %in% written, NA))
  template <- if (complete) message[["template"]] else message[["fallback"]]
  if (is.null(template)) {
    internal_error(sprintf("the message '%s' of %s renders a statistic that is not written.",
                           id, entry[["id"]]))
  }
  # Templates are ASCII, so character positions are byte positions.
  found <- gregexpr("\\{[a-z][a-z0-9_]*\\}", template)[[1L]]
  if (found[1L] == -1L) {
    return(template)
  }
  starts <- as.integer(found)
  ends <- starts + attr(found, "match.length") - 1L
  pieces <- character(0)
  previous <- 1L
  for (i in seq_along(starts)) {
    name <- substr(template, starts[i] + 1L, ends[i] - 1L)
    value <- render_message_argument(args[[name]], entry, scope, values)
    pieces <- c(pieces, substr(template, previous, starts[i] - 1L), value)
    previous <- ends[i] + 1L
  }
  pieces <- c(pieces, substr(template, previous, nchar(template)))
  paste(pieces, collapse = "")
}

# One argument of a message: a scope part after display escaping, a
# threshold or parameter as written, a ratio threshold as a percentage, or a
# statistic rendered by its kind.
render_message_argument <- function(arg, entry, scope, values) {
  name <- arg[["name"]]
  switch(arg[["source"]],
    scope = display_text(scope[[name]], limit = NA),
    parameter = entry[["parameters"]][[name]][["value"]],
    threshold = {
      threshold <- entry[["thresholds"]][[name]]
      kind <- entry[["statistics"]][[threshold[["statistic"]]]][["kind"]]
      if (identical(kind, "ratio")) percent_text(threshold[["value"]]) else threshold[["value"]]
    },
    statistic = {
      statistic <- entry[["statistics"]][[name]]
      value <- values[[name]]
      switch(statistic[["kind"]],
        count = {
          text <- format_integer(value)
          noun <- unlist(arg[["noun"]])
          if (length(noun)) paste(text, if (text == "1") noun[1L] else noun[2L]) else text
        },
        ratio = ratio_text(values[[statistic[["numerator"]]]], values[[statistic[["denominator"]]]],
                           arg[["digits"]]),
        real = real_text(value, arg[["digits"]]),
        category = chartr("_", " ", value),
        names = , labels = names_text(value),
        internal_error(sprintf("a statistic of kind %s cannot be rendered.", statistic[["kind"]]))
      )
    }
  )
}

# Names or labels, each in single quotation marks after display escaping,
# joined by ', ' except the last two, which are joined by ' and ', or 'none'.
names_text <- function(x) {
  count <- length(x)
  if (!count) {
    return("none")
  }
  quoted <- paste0("'", vapply(x, display_text, "", limit = NA, USE.NAMES = FALSE), "'")
  if (count == 1L) {
    return(quoted)
  }
  paste0(paste(quoted[-count], collapse = ", "), " and ", quoted[count])
}

# A decimal string with its decimal point moved two places to the right and
# followed by '%', so that '0.15' gives '15%', '0.125' '12.5%' and '1' '100%'.
percent_text <- function(value) {
  parts <- strsplit(value, ".", fixed = TRUE)[[1L]]
  fraction <- if (length(parts) > 1L) parts[2L] else ""
  fraction <- paste0(fraction, strrep("0", max(0L, 2L - nchar(fraction))))
  whole <- sub("^0+(?=[0-9])", "", paste0(parts[1L], substr(fraction, 1L, 2L)), perl = TRUE)
  rest <- sub("0+$", "", substring(fraction, 3L))
  paste0(whole, if (nzchar(rest)) paste0(".", rest), "%")
}

# The integer q nearest to a x 100 x 10^digits / b, a tie going to the even
# integer, written with 'digits' decimal places and followed by '%'. The
# products are exact in doubles below 2^53.
ratio_text <- function(a, b, digits) {
  numerator <- a * 100 * 10^digits
  q <- floor(numerator / b)
  r <- numerator - q * b
  if (r < 0) {
    q <- q - 1
    r <- r + b
  } else if (r >= b) {
    q <- q + 1
    r <- r - b
  }
  if (2 * r > b || (2 * r == b && q %% 2 == 1)) {
    q <- q + 1
  }
  paste0(point_digits(integer_digits(q), digits), "%")
}

# Decimal digits of a non-negative integer with a decimal point placed
# 'digits' places from the right.
point_digits <- function(text, digits) {
  if (digits == 0L) {
    return(text)
  }
  text <- paste0(strrep("0", max(0L, digits + 1L - nchar(text))), text)
  cut <- nchar(text) - digits
  paste0(substr(text, 1L, cut), ".", substring(text, cut + 1L))
}

# A real statistic as a message renders it (registry.md, Messages): in
# scientific notation when the double is finite and at least 1e15 in absolute
# value, a bound that the double 10^15 holds exactly, in fixed notation when
# it is finite and smaller, and as 'NaN', 'Infinity' or '-Infinity'
# otherwise. A double above 0 whose fixed rendering has no digit other than
# 0 is written as 'under' and the smallest positive value at that number of
# places, which the rendering itself decides. 'digits' may hold several
# numbers of places, for each of which the value is rendered from one
# expansion of the double.
real_text <- function(x, digits) {
  digits <- as.integer(digits)
  if (is.nan(x)) {
    return(rep("NaN", length(digits)))
  }
  if (is.infinite(x)) {
    return(rep(if (x > 0) "Infinity" else "-Infinity", length(digits)))
  }
  if (x == 0) {
    return(vapply(digits, function(d) point_digits("0", d), ""))
  }
  parts <- double_parts(x)
  exact <- scaled_digits(parts$m, parts$e, 1)
  if (abs(x) >= powers_of_ten[16L]) {
    return(vapply(digits, function(d) {
      scientific_decimal(exact$digits[[1L]], exact$q, parts$negative, d)
    }, ""))
  }
  vapply(digits, function(d) {
    text <- fixed_decimal(exact$digits[[1L]], exact$q, parts$negative, d)
    if (parts$negative || grepl("[1-9]", text)) text else paste0("under ", point_digits("1", d))
  }, "")
}

# The exact value of a non-zero double, held as its decimal digits 'value'
# times 10^q, rounded half to even to 'digits' decimal places, as Python's
# f"{x:.{digits}f}" writes it, with a minus sign only before a value that is
# not zero after rounding. The digits come from the in-house expansion of the
# double, never from the C library (registry.md, Messages).
fixed_decimal <- function(value, q, negative, digits) {
  # The digits from the place 10^-digits on are dropped and rounded.
  shift <- q + digits
  if (shift >= 0L) {
    kept <- c(value, integer(shift))
  } else {
    keep <- length(value) + shift
    kept <- if (keep > 0L) value[seq_len(keep)] else 0L
    next_digit <- if (keep >= 0L) value[keep + 1L] else 0L
    rest <- if (keep + 2L <= length(value)) value[max(1L, keep + 2L):length(value)] else integer(0)
    more <- keep < -1L || any(rest != 0L)
    odd <- kept[length(kept)] %% 2L == 1L
    if (next_digit > 5L || (next_digit == 5L && (more || odd))) {
      kept <- digits_add_small(kept, 1L)
    }
  }
  nonzero <- which(kept != 0L)
  zero <- !length(nonzero)
  kept <- if (zero) 0L else kept[nonzero[1L]:length(kept)]
  text <- point_digits(paste(kept, collapse = ""), digits)
  if (negative && !zero) paste0("-", text) else text
}

# The exact value of a non-zero double, held as its decimal digits 'value'
# times 10^q, in scientific notation with its mantissa rounded half to even
# to 'digits' decimal places, as Python's f"{x:.{digits}e}" writes it: the
# mantissa, 'e', the sign of the exponent and at least two digits of the
# exponent.
scientific_decimal <- function(value, q, negative, digits) {
  keep <- digits + 1L
  # The leading digit has the exponent q + length(value) - 1, and the
  # mantissa keeps 'keep' digits.
  exponent <- as.integer(q) + length(value) - 1L
  if (length(value) <= keep) {
    kept <- c(value, integer(keep - length(value)))
  } else {
    kept <- value[seq_len(keep)]
    next_digit <- value[keep + 1L]
    more <- keep + 2L <= length(value) && any(value[(keep + 2L):length(value)] != 0L)
    if (next_digit > 5L || (next_digit == 5L && (more || kept[keep] %% 2L == 1L))) {
      kept <- digits_add_small(kept, 1L)
      # A carry out of the leading digit, as from 9.99 to 10.00, adds a
      # trailing zero, which moves to the exponent.
      if (length(kept) > keep) {
        kept <- kept[seq_len(keep)]
        exponent <- exponent + 1L
      }
    }
  }
  mantissa <- paste(kept, collapse = "")
  if (keep > 1L) {
    mantissa <- paste0(substr(mantissa, 1L, 1L), ".", substring(mantissa, 2L))
  }
  text <- paste0(mantissa, "e", if (exponent < 0L) "-" else "+", sprintf("%02d", abs(exponent)))
  if (negative) paste0("-", text) else text
}
