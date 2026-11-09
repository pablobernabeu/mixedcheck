# The formula grammar of docs/spec/ir.md (Formula grammar): the division into
# tokens, the parser of the EBNF and the structural rules. Each stage reports
# the first issue that the specification assigns to it. Formulas hold at most
# 10,000 characters, so the stages work one token at a time.

# The reserved words of R, which a bare name cannot be (E6005).
formula_reserved_words <- c(
  "if", "else", "repeat", "while", "function", "for", "next", "break", "TRUE",
  "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_",
  "NA_character_", "in"
)

# The covariance structures of lme4 2.x and glmmTMB (E6018).
formula_covariance_structures <- c(
  "diag", "cs", "ar1", "us", "homdiag", "homcs", "hetcs", "ou", "toep", "rr",
  "propto"
)

# Whether a variable name is written bare in IR names: a bare name of the
# grammar that is not a reserved word.
formula_bare_name <- function(name) {
  grepl("^[A-Za-z][A-Za-z0-9._]*\\z", name, perl = TRUE) &
    !name %in% formula_reserved_words
}

# A variable as IR names write it: bare, or between backquotes.
formula_variable_text <- function(name) {
  ifelse(formula_bare_name(name), name, paste0("`", name, "`"))
}

# The code points of the formula with the 0-based byte offset of each and the
# number of bytes. formula is ASCII or marked UTF-8.
formula_text <- function(formula) {
  codepoints <- utf8ToInt(formula)
  sizes <- ifelse(codepoints < 0x80L, 1L,
    ifelse(codepoints < 0x800L, 2L, ifelse(codepoints < 0x10000L, 3L, 4L)))
  list(
    codepoints = codepoints,
    offsets = cumsum(c(0L, sizes))[seq_along(codepoints)],
    bytes = sum(sizes)
  )
}

# Divides a formula into tokens from left to right (ir.md, Tokens) and returns
# them as a list, closed by a token of type 'end' at the end of the input.
# Each token has its type ('op', 'name', 'number' or 'end'), its text as
# written, its offset and, for a name, its value and whether it was quoted
# and whether it names a function. The first lexical issue stops the scan,
# since it lies at the lowest offset.
formula_tokens <- function(text) {
  cp <- text$codepoints
  at <- text$offsets
  n <- length(cp)
  white <- c(0x20L, 0x09L, 0x0AL, 0x0DL)
  operators <- utf8ToInt("~+-*/:^(),|")
  letter <- function(c) (c >= 65L & c <= 90L) | (c >= 97L & c <= 122L)
  digit <- function(c) c >= 48L & c <= 57L
  word <- function(c) letter(c) | digit(c) | c == 46L | c == 95L
  tokens <- vector("list", n + 1L)
  count <- 0L
  add <- function(type, text_value, offset, value = NULL, quoted = FALSE) {
    count <<- count + 1L
    tokens[[count]] <<- list(type = type, text = text_value, offset = offset,
                             value = value, quoted = quoted, func = FALSE)
  }
  run_end <- function(i) {
    j <- i
    while (j < n && word(cp[j + 1L])) {
      j <- j + 1L
    }
    j
  }
  i <- 1L
  while (i <= n) {
    c <- cp[i]
    offset <- at[i]
    if (c %in% white) {
      i <- i + 1L
    } else if (c == 124L && i < n && cp[i + 1L] == 124L) {
      add("op", "||", offset)
      i <- i + 2L
    } else if (c %in% operators) {
      add("op", intToUtf8(c), offset)
      i <- i + 1L
    } else if (c == 96L) {
      close <- if (i < n) which(cp[(i + 1L):n] == 96L) else integer(0)
      if (!length(close)) {
        raise_issue("E6003", offset = offset)
      }
      j <- i + close[1L]
      inner <- if (j > i + 1L) cp[(i + 1L):(j - 1L)] else integer(0)
      if (!length(inner) || any(inner == 92L) || any(inner <= 0x1FL) ||
          any(inner >= 0x7FL & inner <= 0x9FL)) {
        raise_issue("E6004", offset = offset)
      }
      add("name", intToUtf8(cp[i:j]), offset, value = intToUtf8(inner), quoted = TRUE)
      i <- j + 1L
    } else if (digit(c)) {
      j <- run_end(i)
      value <- intToUtf8(cp[i:j])
      if (!all(digit(cp[i:j]))) {
        raise_issue("E6006", list(number = value), offset = offset)
      }
      add("number", value, offset)
      i <- j + 1L
    } else if (letter(c)) {
      j <- run_end(i)
      value <- intToUtf8(cp[i:j])
      if (value %in% formula_reserved_words) {
        raise_issue("E6005", list(name = value), offset = offset)
      }
      add("name", value, offset, value = value)
      i <- j + 1L
    } else if (c == 46L) {
      raise_issue("E6007", list(operator = "."), offset = offset)
    } else if (c == 37L) {
      close <- if (i < n) which(cp[(i + 1L):n] == 37L) else integer(0)
      if (length(close)) {
        j <- i + close[1L]
        between <- if (j > i + 1L) cp[(i + 1L):(j - 1L)] else integer(0)
        if (!any(between %in% white)) {
          raise_issue("E6007", list(operator = intToUtf8(cp[i:j])), offset = offset)
        }
      }
      raise_issue("E6002", list(codepoint = c), offset = offset)
    } else {
      raise_issue("E6002", list(codepoint = c), offset = offset)
    }
  }
  tokens <- tokens[seq_len(count)]
  # A bare name whose next token is '(' names a function.
  for (k in seq_len(max(count - 1L, 0L))) {
    if (tokens[[k]]$type == "name" && !tokens[[k]]$quoted &&
        tokens[[k + 1L]]$type == "op" && tokens[[k + 1L]]$text == "(") {
      tokens[[k]]$func <- TRUE
    }
  }
  c(tokens, list(list(type = "end", text = "", offset = text$bytes, value = NULL,
                      quoted = FALSE, func = FALSE)))
}

# Parses the tokens by the grammar of ir.md (Syntax), each token by the first
# rule that can continue the formula, and returns the syntax tree. The nodes
# are lists with a kind and the offset of their first token as start:
# 'name' (key, value, quoted), 'number' (text), 'call' (name, args), 'paren'
# (arg), 'chain' (operands, ops, at), 'power' (base, exponent, at), 'sum'
# (summands, each with its sign, the sign's offset and expr) and 'argument'
# (lhs, bar, rhs). A chain holds a run of two or more operands joined by
# ':', or by '*' and '/', read from the left, with the text and offset of
# the operator before each operand after the first, so that the walks of
# the tree loop over a run and recurse only into parentheses, which nest at
# most 64 levels deep. The formula has lhs, which is NULL without a
# response, and rhs.
formula_parse <- function(tokens, bytes) {
  position <- 1L
  depth <- 0L
  peek <- function() tokens[[position]]
  advance <- function() {
    token <- tokens[[position]]
    position <<- position + 1L
    token
  }
  is_op <- function(token, ops) token$type == "op" && token$text %in% ops
  fail <- function(token) {
    if (token$type == "end") {
      raise_issue("E6010", offset = bytes)
    }
    if (is_op(token, c("|", "||"))) {
      raise_issue("E6013", list(bar = token$text), offset = token$offset)
    }
    raise_issue("E6011", list(token = token$text), offset = token$offset)
  }
  open <- function() {
    token <- advance()
    depth <<- depth + 1L
    if (depth > 64L) {
      raise_issue("E6021", offset = token$offset)
    }
    token
  }
  close <- function() {
    if (!is_op(peek(), ")")) {
      fail(peek())
    }
    advance()
    depth <<- depth - 1L
  }
  parse_sum <- function() {
    summands <- list()
    sign <- NULL
    sign_at <- NULL
    start <- peek()$offset
    if (is_op(peek(), c("+", "-"))) {
      token <- advance()
      sign <- token$text
      sign_at <- token$offset
    }
    repeat {
      expr <- parse_product()
      summands[[length(summands) + 1L]] <- list(sign = sign, sign_at = sign_at, expr = expr)
      if (!is_op(peek(), c("+", "-"))) {
        break
      }
      token <- advance()
      sign <- token$text
      sign_at <- token$offset
    }
    list(kind = "sum", start = start, summands = summands)
  }
  parse_chain <- function(operand, ops) {
    first <- operand()
    if (!is_op(peek(), ops)) {
      return(first)
    }
    operands <- list(first)
    op_text <- character(0)
    op_at <- integer(0)
    while (is_op(peek(), ops)) {
      token <- advance()
      op_text[length(op_text) + 1L] <- token$text
      op_at[length(op_at) + 1L] <- token$offset
      operands[[length(operands) + 1L]] <- operand()
    }
    list(kind = "chain", start = first$start, operands = operands, ops = op_text, at = op_at)
  }
  parse_product <- function() parse_chain(parse_interaction, c("*", "/"))
  parse_interaction <- function() parse_chain(parse_power, ":")
  parse_power <- function() {
    base <- parse_primary()
    if (is_op(peek(), "^")) {
      token <- advance()
      exponent <- parse_primary()
      return(list(kind = "power", start = base$start, at = token$offset, base = base,
                  exponent = exponent))
    }
    base
  }
  parse_argument <- function() {
    lhs <- parse_sum()
    if (is_op(peek(), c("|", "||"))) {
      token <- advance()
      rhs <- parse_sum()
      return(list(kind = "argument", start = lhs$start, lhs = lhs, bar = token$text, rhs = rhs))
    }
    list(kind = "argument", start = lhs$start, lhs = lhs, bar = NULL, rhs = NULL)
  }
  parse_primary <- function() {
    token <- peek()
    if (token$type == "name" && token$func) {
      advance()
      open()
      args <- list()
      if (!is_op(peek(), ")")) {
        repeat {
          args[[length(args) + 1L]] <- parse_argument()
          if (!is_op(peek(), ",")) {
            break
          }
          advance()
        }
      }
      close()
      return(list(kind = "call", start = token$offset, name = token$value, args = args))
    }
    if (token$type == "name") {
      advance()
      return(list(kind = "name", start = token$offset, value = token$value,
                  key = comparison_form(token$value), quoted = token$quoted))
    }
    if (token$type == "number") {
      advance()
      return(list(kind = "number", start = token$offset, text = token$text))
    }
    if (is_op(token, "(")) {
      open()
      arg <- parse_argument()
      close()
      return(list(kind = "paren", start = token$offset, arg = arg))
    }
    fail(token)
  }
  lhs <- NULL
  if (!is_op(peek(), "~")) {
    lhs <- parse_sum()
    if (!is_op(peek(), "~")) {
      fail(peek())
    }
  }
  advance()
  rhs <- parse_sum()
  if (peek()$type != "end") {
    fail(peek())
  }
  list(lhs = lhs, rhs = rhs)
}

# Helpers on syntax trees.

# Whether a sum is a single name without a sign.
formula_single_name <- function(sum) {
  length(sum$summands) == 1L && is.null(sum$summands[[1L]]$sign) &&
    sum$summands[[1L]]$expr$kind == "name"
}

# The call that makes up a whole sum, a single summand without a sign, or
# NULL.
formula_sole_call <- function(sum, name) {
  if (length(sum$summands) == 1L && is.null(sum$summands[[1L]]$sign)) {
    expr <- sum$summands[[1L]]$expr
    if (expr$kind == "call" && expr$name == name) {
      return(expr)
    }
  }
  NULL
}

# Whether a call has one argument without a bar that is a single name.
formula_call_of_name <- function(call) {
  length(call$args) == 1L && is.null(call$args[[1L]]$bar) &&
    formula_single_name(call$args[[1L]]$lhs)
}

# Whether an expression is a random term: a parenthesised argument with a bar.
formula_is_random <- function(expr) {
  expr$kind == "paren" && !is.null(expr$arg$bar)
}

# The violations of the structural rules of ir.md (Structure). Returns the
# one at the lowest offset and, among those at one offset, with the lowest
# code, as list(code, offset, args), or NULL.
formula_structure_issue <- function(tree) {
  found <- list()
  add <- function(code, offset, args = list()) {
    found[[length(found) + 1L]] <<- list(code = code, offset = offset, args = args)
  }
  # A number that is no intercept summand and no exponent.
  stray_number <- function(node) {
    if (node$text %in% c("0", "1")) {
      add("E6015", node$start, list(intercept = node$text))
    } else {
      add("E6006", node$start, list(number = node$text))
    }
  }
  # The arguments of a call. An argument of offset() that is log() of
  # anything is in a place where log() is allowed.
  walk_call_args <- function(call, offset_call) {
    for (arg in call$args) {
      log_call <- if (offset_call && is.null(arg$bar)) formula_sole_call(arg$lhs, "log")
      if (!is.null(log_call)) {
        for (inner in log_call$args) walk_argument(inner, "other")
      } else {
        walk_argument(arg, "other")
      }
    }
  }
  walk_argument <- function(arg, context) {
    walk_sum(arg$lhs, context)
    if (!is.null(arg$bar)) {
      walk_sum(arg$rhs, context)
    }
  }
  walk_sum <- function(sum, context) {
    for (summand in sum$summands) walk_expr(summand$expr, context)
  }
  # An expression outside the summands that the rules treat specially. In a
  # grouping, numbers fall under the rule of the grouping alone.
  walk_expr <- function(node, context) {
    switch(node$kind,
      name = NULL,
      number = if (context != "grouping") stray_number(node),
      call = {
        if (node$name == "offset") {
          add("E6019", node$start)
        } else if (node$name == "log") {
          add("E6020", node$start)
        } else if (node$name %in% formula_covariance_structures) {
          add("E6018", node$start, list(`function` = node$name))
        } else {
          add("E6017", node$start, list(`function` = node$name))
        }
        walk_call_args(node, node$name == "offset")
      },
      paren = {
        if (formula_is_random(node)) {
          add("E6014", node$start)
          walk_random(node)
        } else {
          walk_sum(node$arg$lhs, context)
        }
      },
      chain = for (operand in node$operands) walk_expr(operand, context),
      power = {
        walk_expr(node$base, context)
        exponent <- node$exponent
        if (context == "grouping") {
          walk_expr(exponent, context)
        } else if (exponent$kind == "number") {
          text <- exponent$text
          if (startsWith(text, "0") || nchar(text) > 4L || as.integer(text) < 2L ||
              as.integer(text) > 1000L) {
            add("E6006", exponent$start, list(number = text))
          }
        } else {
          add("E6006", exponent$start, list(number = first_token_text(exponent)))
          walk_expr(exponent, context)
        }
      }
    )
    invisible()
  }
  # The text of the first token of an expression that is not a number.
  first_token_text <- function(node) {
    switch(node$kind,
      name = if (node$quoted) paste0("`", node$value, "`") else node$value,
      call = node$name,
      paren = "(",
      chain = first_token_text(node$operands[[1L]]),
      power = first_token_text(node$base),
      number = node$text
    )
  }
  # A summand of the sum after '~' or of the left-hand side of a random term.
  walk_summand <- function(summand, top) {
    expr <- summand$expr
    if (expr$kind == "number") {
      if (!expr$text %in% c("0", "1")) {
        add("E6006", expr$start, list(number = expr$text))
      } else if (identical(summand$sign, "-") && expr$text == "0") {
        add("E6015", summand$sign_at, list(intercept = "- 0"))
      }
    } else if (formula_is_random(expr)) {
      if (!top || identical(summand$sign, "-")) {
        add("E6014", expr$start)
      }
      walk_random(expr)
    } else if (expr$kind == "call" && expr$name == "offset") {
      arg_ok <- length(expr$args) == 1L && is.null(expr$args[[1L]]$bar) &&
        (formula_single_name(expr$args[[1L]]$lhs) || {
          log_call <- formula_sole_call(expr$args[[1L]]$lhs, "log")
          !is.null(log_call) && formula_call_of_name(log_call)
        })
      if (!top || identical(summand$sign, "-") || !arg_ok) {
        add("E6019", expr$start)
      }
      walk_call_args(expr, TRUE)
    } else {
      walk_expr(expr, "other")
    }
  }
  # The left-hand side and grouping of a random term.
  walk_random <- function(node) {
    for (summand in node$arg$lhs$summands) walk_summand(summand, FALSE)
    grouping <- node$arg$rhs
    offsets <- integer(0)
    collect <- function(expr) {
      switch(expr$kind,
        name = NULL,
        number = offsets <<- c(offsets, expr$start),
        call = offsets <<- c(offsets, expr$start),
        paren = offsets <<- c(offsets, expr$start),
        chain = {
          offsets <<- c(offsets, expr$at[!expr$ops %in% c(":", "/")])
          for (operand in expr$operands) collect(operand)
        },
        power = {
          offsets <<- c(offsets, expr$at)
          collect(expr$base)
          collect(expr$exponent)
        }
      )
    }
    for (summand in grouping$summands) {
      if (!is.null(summand$sign)) {
        offsets <- c(offsets, summand$sign_at)
      }
      collect(summand$expr)
    }
    if (length(offsets)) {
      add("E6016", min(offsets))
    }
    walk_sum(grouping, "grouping")
  }
  # The response: a single name without a sign, or log() of a single name.
  if (!is.null(tree$lhs)) {
    log_call <- formula_sole_call(tree$lhs, "log")
    valid <- formula_single_name(tree$lhs) ||
      (!is.null(log_call) && formula_call_of_name(log_call))
    if (!valid) {
      add("E6012", tree$lhs$start)
    }
    if (!is.null(log_call)) {
      for (arg in log_call$args) walk_argument(arg, "other")
    } else {
      walk_sum(tree$lhs, "other")
    }
  }
  for (summand in tree$rhs$summands) walk_summand(summand, TRUE)
  formula_first_issue(found)
}

# The issue at the lowest offset and, at one offset, with the lowest code.
formula_first_issue <- function(found) {
  if (!length(found)) {
    return(NULL)
  }
  offsets <- vapply(found, function(issue) as.numeric(issue$offset %||% Inf), 0)
  codes <- vapply(found, function(issue) issue$code, "")
  found[[order(offsets, codes, method = "radix")[1L]]]
}
