# Numbers: the exact decimal value of a double, ECMAScript's Number::toString,
# decimal constants and the number rules of the hashable profile
# (docs/spec/conventions.md, Numbers, Serialisation and Decimal strings and
# centring constants). No C library formatting is relied on for digits.
#
# Big integers are numeric vectors of limbs in base 10^7, least significant
# first. Every limb operation stays below 2^53, so doubles hold it exactly.

bn_base <- 1e7

# 10^0 to 10^22, each an exact double, built by exact multiplications.
powers_of_ten <- cumprod(c(1, rep(10, 22L)))

# Quotient and remainder by bn_base of integer-valued doubles below 2^53 in
# magnitude, with the remainder in [0, bn_base). The quotient computed in
# floating point can be one off, which the corrections remove.
bn_divmod <- function(v) {
  q <- floor(v / bn_base)
  r <- v - q * bn_base
  low <- r < 0
  q[low] <- q[low] - 1
  r[low] <- r[low] + bn_base
  high <- r >= bn_base
  q[high] <- q[high] + 1
  r[high] <- r[high] - bn_base
  list(q = q, r = r)
}

# Propagates carries and borrows until every limb lies in [0, bn_base), and
# removes leading zero limbs. The value must not be negative.
bn_normalise <- function(limbs) {
  repeat {
    parts <- bn_divmod(limbs)
    if (all(parts$q == 0)) {
      break
    }
    count <- length(limbs)
    limbs <- parts$r + c(0, parts$q[-count])
    if (parts$q[count] != 0) {
      limbs <- c(limbs, parts$q[count])
    }
  }
  nonzero <- which(limbs != 0)
  if (length(nonzero) == 0L) 0 else limbs[seq_len(max(nonzero))]
}

# Multiplies by an integer below 2^29.
bn_mul_small <- function(a, factor) {
  bn_normalise(a * factor)
}

bn_pad <- function(a, count) {
  c(a, numeric(count - length(a)))
}

bn_add <- function(a, b) {
  count <- max(length(a), length(b))
  bn_normalise(bn_pad(a, count) + bn_pad(b, count))
}

# Subtracts b from a, where a is at least b.
bn_sub <- function(a, b) {
  count <- max(length(a), length(b))
  bn_normalise(bn_pad(a, count) - bn_pad(b, count))
}

# The decimal digits of a big integer, most significant first, without
# leading zeros. Zero gives one digit 0.
bn_digits <- function(a) {
  limbs <- as.integer(rev(a))
  powers <- c(1000000L, 100000L, 10000L, 1000L, 100L, 10L, 1L)
  digits <- as.vector(t(outer(limbs, powers, function(l, p) (l %/% p) %% 10L)))
  nonzero <- which(digits != 0L)
  if (length(nonzero) == 0L) 0L else digits[nonzero[1L]:length(digits)]
}

# base^exponent for base 2 or 5, cached for the session.
bn_power <- function(base, exponent) {
  if (is.null(mixedcheck_cache$powers)) {
    mixedcheck_cache$powers <- new.env(parent = emptyenv())
  }
  key <- paste0(base, "^", exponent)
  cached <- mixedcheck_cache$powers[[key]]
  if (!is.null(cached)) {
    return(cached)
  }
  step <- if (base == 2) 28L else 12L
  result <- 1
  remaining <- exponent
  while (remaining >= step) {
    result <- bn_mul_small(result, base^step)
    remaining <- remaining - step
  }
  if (remaining > 0) {
    result <- bn_mul_small(result, base^remaining)
  }
  assign(key, result, envir = mixedcheck_cache$powers)
  result
}

# The sign, integer significand m and exponent e of each double, with
# x = m * 2^e exactly, from its IEEE 754 bits. m is below 2^53.
double_parts <- function(x) {
  bytes <- matrix(as.integer(writeBin(as.double(x), raw(), size = 8L, endian = "big")),
                  nrow = 8L)
  field <- (bytes[1L, ] %% 128L) * 16L + bytes[2L, ] %/% 16L
  fraction <- (bytes[2L, ] %% 16L) * 2^48 + bytes[3L, ] * 2^40 + bytes[4L, ] * 2^32 +
    bytes[5L, ] * 2^24 + bytes[6L, ] * 2^16 + bytes[7L, ] * 2^8 + bytes[8L, ]
  normal <- field > 0L
  list(
    negative = bytes[1L, ] >= 128L,
    m = ifelse(normal, fraction + 2^52, fraction),
    e = ifelse(normal, field - 1075L, -1074L)
  )
}

# The 16 hexadecimal digits of the bits of each double, most significant first.
double_bits <- function(x) {
  bytes <- matrix(writeBin(as.double(x), raw(), size = 8L, endian = "big"), nrow = 8L)
  apply(bytes, 2L, function(column) paste(as.character(column), collapse = ""))
}

# The double whose bits are given as 16 hexadecimal digits.
bits_double <- function(bits) {
  readBin(hex_to_raw(bits), "double", n = 1L, size = 8L, endian = "big")
}

# The exact value of c * m * 2^e for a significand m below 2^53 and each
# small multiplier c, as digit vectors that share the exponent q of their last
# digit: each value is (its digits) * 10^q.
scaled_digits <- function(m, e, multipliers, offsets = numeric(length(multipliers))) {
  if (e >= 0) {
    power <- bn_power(2, e)
    q <- 0L
  } else {
    power <- bn_power(5, -e)
    q <- e
  }
  high <- floor(m / 2^26)
  low <- m - high * 2^26
  product <- bn_add(bn_mul_small(power, low), bn_mul_small(bn_mul_small(power, high), 2^26))
  digits <- vector("list", length(multipliers))
  for (i in seq_along(multipliers)) {
    value <- bn_mul_small(product, multipliers[i])
    if (offsets[i] > 0) {
      value <- bn_add(value, bn_mul_small(power, offsets[i]))
    } else if (offsets[i] < 0) {
      value <- bn_sub(value, bn_mul_small(power, -offsets[i]))
    }
    digits[[i]] <- bn_digits(value)
  }
  list(digits = digits, q = q)
}

# Adds a small non-negative integer to a digit vector, most significant first.
digits_add_small <- function(digits, value) {
  i <- length(digits)
  carry <- value
  while (carry > 0) {
    if (i == 0L) {
      digits <- c(carry %% 10L, digits)
      carry <- carry %/% 10L
    } else {
      total <- digits[i] + carry
      digits[i] <- total %% 10L
      carry <- total %/% 10L
      i <- i - 1L
    }
  }
  digits
}

# Big integers held as the rows of a matrix, one limb per column, least
# significant first. The operations are those above, applied to every row.
bm_normalise <- function(limbs) {
  repeat {
    parts <- bn_divmod(limbs)
    q <- matrix(parts$q, nrow = nrow(limbs))
    if (all(q == 0)) {
      return(limbs)
    }
    count <- ncol(limbs)
    limbs <- matrix(parts$r, nrow = nrow(limbs))
    if (count > 1L) {
      limbs[, 2:count] <- limbs[, 2:count, drop = FALSE] + q[, -count, drop = FALSE]
    }
    if (any(q[, count] != 0)) {
      limbs <- cbind(limbs, q[, count])
    }
  }
}

bm_widen <- function(limbs, count) {
  if (ncol(limbs) < count) {
    limbs <- cbind(limbs, matrix(0, nrow(limbs), count - ncol(limbs)))
  }
  limbs
}

bm_add <- function(a, b) {
  count <- max(ncol(a), ncol(b))
  bm_normalise(bm_widen(a, count) + bm_widen(b, count))
}

# The decimal digits of each row, most significant first, as a matrix with
# 7 digits for each limb.
bm_digits <- function(limbs) {
  rows <- nrow(limbs)
  count <- ncol(limbs)
  reversed <- limbs[, count:1L, drop = FALSE]
  storage.mode(reversed) <- "integer"
  powers <- c(1000000L, 100000L, 10000L, 1000L, 100L, 10L, 1L)
  digits <- array(0L, c(rows, 7L, count))
  for (t in seq_along(powers)) {
    digits[, t, ] <- (reversed %/% powers[t]) %% 10L
  }
  matrix(digits, nrow = rows)
}

# The last column of each row of a logical matrix that is TRUE, or 0.
last_true <- function(mask) {
  count <- ncol(mask)
  found <- max.col(mask[, count:1L, drop = FALSE] * 1L, ties.method = "first")
  any_true <- rowSums(mask) > 0L
  ifelse(any_true, count + 1L - found, 0L)
}

# The shortest decimal that converts back to each positive finite double
# m * 2^e, for doubles that share e, and of several the closest, ties to even
# (ECMA-262, Number::toString, step 5). The search uses the exact bounds of
# the interval of decimals that round to each double, so it depends on no
# formatting routine. Returns the digits s, without trailing zeros, as
# strings, and n, with value 0.s * 10^n.
shortest_exact <- function(m, e) {
  rows <- length(m)
  # Scaled by 2^(e - 2), the double is 4m and its rounding interval runs from
  # 4m - 2 to 4m + 2, or from 4m - 1 below a power of two, whose lower
  # neighbour is closer.
  scale <- e - 2
  if (scale >= 0) {
    power <- bn_power(2, scale)
    q <- 0L
  } else {
    power <- bn_power(5, -scale)
    q <- scale
  }
  power_row <- matrix(power, nrow = rows, ncol = length(power), byrow = TRUE)
  high <- floor(m / 2^26)
  low <- m - high * 2^26
  product <- bm_add(bm_normalise(outer(low, power)),
                    bm_normalise(bm_normalise(outer(high, power)) * 2^26))
  middle <- bm_normalise(product * 4)
  count <- ncol(middle) + 1L
  middle <- bm_widen(middle, count)
  power_row <- bm_widen(power_row, count)
  upper <- bm_normalise(middle + 2 * power_row)
  lower_offset <- ifelse(m == 2^52 & e > -1074, 1, 2)
  lower <- bm_normalise(middle - lower_offset * power_row)
  count <- max(ncol(lower), ncol(middle), ncol(upper))
  low_digits <- bm_digits(bm_widen(lower, count))
  mid_digits <- bm_digits(bm_widen(middle, count))
  high_digits <- bm_digits(bm_widen(upper, count))
  columns <- ncol(mid_digits)
  # The bounds belong to the interval when m is even, since a decimal halfway
  # between two doubles converts to the one with the even significand.
  inclusive <- m %% 2 == 0
  first_difference <- max.col((low_digits != high_digits) * 1L, ties.method = "first")
  last_low <- last_true(low_digits != 0L)
  last_high <- last_true(high_digits != 0L)
  last_mid <- last_true(mid_digits != 0L)
  # When the lower bound belongs to the interval and has no digit beyond the
  # first digit in which the bounds differ, it is itself the shortest decimal.
  bound <- inclusive & last_low < first_difference
  cut <- ifelse(bound, last_low, first_difference - 1L)
  chosen <- numeric(rows)
  # At each cut, the candidates are the multiples of the unit of the last
  # digit kept that lie in the interval. span counts the units between the
  # truncated bounds, offset those between the truncated lower bound and the
  # truncated double.
  span <- numeric(rows)
  offset <- numeric(rows)
  first <- numeric(rows)
  last <- numeric(rows)
  active <- which(!bound)
  while (length(active)) {
    cut[active] <- cut[active] + 1L
    at <- cbind(active, cut[active])
    span[active] <- 10 * span[active] + high_digits[at] - low_digits[at]
    offset[active] <- 10 * offset[active] + mid_digits[at] - low_digits[at]
    first[active] <- ifelse(last_low[active] <= cut[active] & inclusive[active], 0, 1)
    last[active] <- span[active] -
      ifelse(last_high[active] <= cut[active] & !inclusive[active], 1, 0)
    active <- active[last[active] < first[active]]
  }
  # Round the double at the cut, half to even, and keep the result within
  # the candidates.
  rounded <- which(!bound)
  if (length(rounded)) {
    c0 <- cut[rounded]
    next_digit <- ifelse(c0 < columns, mid_digits[cbind(rounded, pmin(c0 + 1L, columns))], 0L)
    more <- last_mid[rounded] > c0 + 1L
    odd <- mid_digits[cbind(rounded, c0)] %% 2L == 1L
    up <- next_digit > 5L | (next_digit == 5L & (more | odd))
    chosen[rounded] <- pmin(pmax(offset[rounded] + up, first[rounded]), last[rounded])
  }
  # The result, the lower bound truncated at the cut plus chosen units, has
  # at most 17 significant digits, so the 18 digits up to the cut hold it.
  window <- matrix(0L, rows, 18L)
  for (k in 1:18) {
    column <- cut - 18L + k
    present <- column >= 1L
    window[present, k] <- low_digits[cbind(which(present), column[present])]
  }
  leading <- numeric(rows)
  trailing <- numeric(rows)
  for (k in 1:9) {
    leading <- leading * 10 + window[, k]
    trailing <- trailing * 10 + window[, k + 9L]
  }
  trailing <- trailing + chosen
  carry <- trailing >= 1e9
  leading[carry] <- leading[carry] + 1
  trailing[carry] <- trailing[carry] - 1e9
  text <- ifelse(leading > 0,
                 paste0(sprintf("%d", as.integer(leading)), sprintf("%09d", as.integer(trailing))),
                 sprintf("%d", as.integer(trailing)))
  stripped <- sub("0+$", "", text)
  # The last digit of the result has the exponent q + columns - cut.
  last_exponent <- q + columns - cut + (nchar(text) - nchar(stripped))
  list(digits = stripped, n = as.integer(last_exponent + nchar(stripped)))
}

# Removes leading and trailing zeros from a non-zero digit vector whose last
# digit has the exponent last_exponent, and returns the digits s with n such
# that the value is 0.s * 10^n.
strip_digits <- function(digits, last_exponent) {
  nonzero <- which(digits != 0L)
  first <- nonzero[1L]
  last <- max(nonzero)
  last_exponent <- last_exponent + (length(digits) - last)
  digits <- digits[first:last]
  list(digits = digits, n = last_exponent + length(digits))
}

# Splits integer-valued doubles below 2^53 into the parts above and below
# 10^8, exactly, and writes their decimal digits with sprintf("%d"), which
# formats integers exactly on every platform.
integer_digits <- function(a) {
  high <- floor(a / 1e8)
  low <- a - high * 1e8
  under <- low < 0
  high[under] <- high[under] - 1
  low[under] <- low[under] + 1e8
  over <- low >= 1e8
  high[over] <- high[over] + 1
  low[over] <- low[over] - 1e8
  ifelse(high > 0,
         paste0(sprintf("%d", as.integer(high)), sprintf("%08d", as.integer(low))),
         sprintf("%d", as.integer(low)))
}

# The digits s and exponent n (value 0.s * 10^n) of the shortest decimal that
# converts to each positive finite double, as strings of digits and integers.
number_parts <- function(a) {
  count <- length(a)
  digits <- character(count)
  n <- integer(count)
  done <- logical(count)
  # Integers below 2^53 are written in full.
  whole <- a < 2^53 & a == floor(a)
  if (any(whole)) {
    text <- integer_digits(a[whole])
    stripped <- sub("0+$", "", text)
    digits[whole] <- stripped
    n[whole] <- nchar(text)
    done[whole] <- TRUE
  }
  # A double whose closest 15-digit decimal converts back to it has exactly
  # one decimal of at most 15 digits in its rounding interval, since that
  # interval is narrower than the spacing of 15-digit decimals. The candidate
  # comes from sprintf(), and the check is exact whatever sprintf() returns:
  # with s below 10^15 and |q| at most 22, s * 10^q and s / 10^-q are single
  # correctly rounded operations on exact operands.
  rest <- which(!done)
  if (length(rest)) {
    # A candidate that sprintf() writes in any other layout, as the C library
    # of Windows does for some values, is left to the exact method below.
    text <- sprintf("%.14e", a[rest])
    form <- grepl("^[1-9]\\.[0-9]{14}e[+-][0-9]{2,3}$", text)
    text[!form] <- "1.00000000000000e+00"
    mantissa <- paste0(substr(text, 1L, 1L), substr(text, 3L, 16L))
    exponent <- as.integer(substr(text, 18L, nchar(text)))
    stripped <- sub("0+$", "", mantissa)
    k <- nchar(stripped)
    q <- exponent - k + 1L
    columns <- matrix(utf8ToInt(paste(mantissa, collapse = "")) - 48L, nrow = 15L)
    value <- 0
    for (j in seq_len(15L)) {
      value <- value * 10 + columns[j, ]
    }
    # Dividing by the power of ten that the trailing zeros make is exact.
    value <- value / powers_of_ten[16L - k]
    power <- powers_of_ten[pmin(abs(q), 22L) + 1L]
    candidate <- ifelse(q >= 0, value * power, value / power)
    fast <- form & abs(q) <= 22L & candidate == a[rest]
    digits[rest[fast]] <- stripped[fast]
    n[rest[fast]] <- exponent[fast] + 1L
    done[rest[fast]] <- TRUE
  }
  slow <- which(!done)
  if (length(slow)) {
    parts <- double_parts(a[slow])
    for (group in split(seq_along(slow), parts$e)) {
      result <- shortest_exact(parts$m[group], parts$e[group[1L]])
      digits[slow[group]] <- result$digits
      n[slow[group]] <- result$n
    }
  }
  list(digits = digits, n = n)
}

# Lays out digits s and exponent n by steps 4 to 7 of Number::toString.
ecmascript_layout <- function(s, n) {
  k <- nchar(s)
  result <- character(length(s))
  plain <- k <= n & n <= 21L
  result[plain] <- paste0(s[plain], strrep("0", n[plain] - k[plain]))
  point <- !plain & n > 0L & n <= 21L
  result[point] <- paste0(substr(s[point], 1L, n[point]), ".",
                          substr(s[point], n[point] + 1L, k[point]))
  small <- !plain & !point & n > -6L & n <= 0L
  result[small] <- paste0("0.", strrep("0", -n[small]), s[small])
  scientific <- !plain & !point & !small
  if (any(scientific)) {
    ss <- s[scientific]
    exponent <- n[scientific] - 1L
    result[scientific] <- paste0(
      substr(ss, 1L, 1L),
      ifelse(nchar(ss) > 1L, paste0(".", substr(ss, 2L, nchar(ss))), ""),
      "e", ifelse(exponent >= 0L, "+", "-"), sprintf("%d", abs(exponent))
    )
  }
  result
}

# Writes finite doubles as ECMAScript's Number::toString does, which RFC 8785
# requires: the shortest decimal that converts back to the double, the closest
# of several, laid out in plain or exponential notation.
format_number <- function(x) {
  format_numbers(as.double(x), FALSE)$text
}

# Converts number tokens, which match the number grammar of RFC 8259, to the
# nearest doubles, rounding ties to even (conventions.md, Numbers). jsonlite's
# parser rounds correctly, whereas as.numeric() does not.
json_number_values <- function(tokens) {
  if (!length(tokens)) {
    return(numeric(0))
  }
  as.double(jsonlite::parse_json(paste0("[", paste(tokens, collapse = ","), "]"),
                                 simplifyVector = TRUE))
}

# Classifies number tokens, which match the number grammar of RFC 8259, by the
# rules of the hashable profile. Returns NA for an accepted token, or E1102 for
# an integer outside the range, E1103 for a non-integer with more than 15
# significant digits or E1104 for one below 1e-307 in magnitude. Exponents are
# exact: one of more than ten digits lies beyond any input below 1 GB.
hashable_token_codes <- function(tokens) {
  pattern <- "^-?([0-9]+)(?:\\.([0-9]+))?(?:[eE]([+-]?)([0-9]+))?$"
  integer_part <- sub(pattern, "\\1", tokens, perl = TRUE)
  fraction <- sub(pattern, "\\2", tokens, perl = TRUE)
  exponent_sign <- sub(pattern, "\\3", tokens, perl = TRUE)
  exponent_digits <- sub("^0+", "", sub(pattern, "\\4", tokens, perl = TRUE))
  significand <- sub("^0+", "", paste0(integer_part, fraction))
  zero <- significand == ""
  stripped <- sub("0+$", "", significand)
  trailing <- nchar(significand) - nchar(stripped)
  digits <- nchar(stripped)
  huge <- nchar(exponent_digits) > 10L
  exponent <- ifelse(exponent_digits == "" | huge, 0,
                     suppressWarnings(as.numeric(exponent_digits)))
  exponent[huge] <- 1e15
  exponent <- ifelse(exponent_sign == "-", -exponent, exponent)
  # The value is stripped * 10^e, with p the power of ten of its leading digit.
  e <- exponent - nchar(fraction) + trailing
  p <- digits + e - 1
  code <- rep(NA_character_, length(tokens))
  integer <- !zero & e >= 0
  limit <- integer & p == 15
  if (any(limit)) {
    full <- paste0(stripped[limit], strrep("0", e[limit]))
    head <- as.numeric(substr(full, 1L, 8L))
    tail <- as.numeric(substr(full, 9L, 16L))
    beyond <- head > 90071992 | (head == 90071992 & tail > 54740991)
    code[which(limit)[beyond]] <- "E1102"
  }
  code[integer & p > 15] <- "E1102"
  fractional <- !zero & e < 0
  code[fractional & digits > 15L] <- "E1103"
  code[fractional & digits <= 15L & p < -307] <- "E1104"
  code
}

# Rounds a finite double to the given number of significant digits, half to
# even on its exact binary value, and writes it as a decimal string: no
# exponent, no '+', no leading zeros in the integer part and no trailing zeros
# in the fraction (conventions.md, Decimal strings and centring constants).
decimal_string <- function(x, digits) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) {
    stop("'x' must be one finite number.", call. = FALSE)
  }
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) ||
      digits != floor(digits) || digits < 1 || digits > 15) {
    stop("'digits' must be an integer from 1 to 15.", call. = FALSE)
  }
  if (x == 0) {
    return("0")
  }
  parts <- double_parts(x)
  exact <- scaled_digits(parts$m, parts$e, 1)
  value <- exact$digits[[1L]]
  last_exponent <- exact$q
  k <- as.integer(digits)
  if (length(value) > k) {
    dropped <- length(value) - k
    next_digit <- value[k + 1L]
    more <- k + 1L < length(value) && any(value[(k + 2L):length(value)] != 0L)
    kept <- value[seq_len(k)]
    if (next_digit > 5L || (next_digit == 5L && (more || kept[k] %% 2L == 1L))) {
      kept <- digits_add_small(kept, 1L)
    }
    value <- kept
    last_exponent <- last_exponent + dropped
  }
  parts_out <- strip_digits(value, last_exponent)
  s <- paste(parts_out$digits, collapse = "")
  n <- parts_out$n
  k <- nchar(s)
  text <- if (n >= k) {
    paste0(s, strrep("0", n - k))
  } else if (n > 0L) {
    paste0(substr(s, 1L, n), ".", substr(s, n + 1L, k))
  } else {
    paste0("0.", strrep("0", -n), s)
  }
  if (x < 0) paste0("-", text) else text
}
