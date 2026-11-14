# The YAML authoring reader for declarations (docs/spec/conventions.md, YAML
# authoring, and docs/spec/declarations.md, YAML authoring). It reads a text
# in five steps, bytes, pre-scan, parsing, keys and conversion, and reports
# the first issue found. The pre-scan finds what R's yaml package cannot
# report, anchors, aliases, explicit tags, merge keys and a second document,
# and libyaml, through yaml, parses the text with every scalar read as a
# string.

# Reads a declaration written in YAML and returns its JSON form.
read_yaml_declaration <- function(path) {
  bytes <- read_input_bytes(path)
  if (length(bytes) >= 3L && bytes[1L] == as.raw(0xEF) && bytes[2L] == as.raw(0xBB) &&
      bytes[3L] == as.raw(0xBF)) {
    raise_issue("E1003")
  }
  invalid <- utf8_invalid_offset(bytes)
  if (!is.na(invalid)) {
    raise_issue("E1201", offset = invalid)
  }
  if (!yaml_available()) {
    raise_issue("E3001", list(package = "yaml"))
  }
  problem <- yaml_prescan(as.integer(bytes))
  if (!is.null(problem)) {
    raise_issue(problem$code, offset = problem$offset)
  }
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  parsed <- yaml_parse(text)
  if (is.null(parsed)) {
    # A text without a document, which the pre-scan refuses unless it misses
    # one.
    raise_issue("E3010")
  }
  yaml_check_keys(parsed, character(0))
  yaml_convert_declaration(parsed)
}

# Whether the yaml package can be loaded. A function of its own, so that the
# tests can replace it.
yaml_available <- function() {
  requireNamespace("yaml", quietly = TRUE)
}

# Step 2: the pre-scan of conventions.md (YAML authoring). It works on the
# bytes of valid UTF-8 text, which gives the same result as working on its
# characters, because every character that it looks for is ASCII and the
# bytes of other characters are 80 or above. Returns the code of the first
# problem with its 0-based byte offset, or with no offset for a text without
# content (E3010), or NULL.
yaml_prescan <- function(b) {
  n <- length(b)
  nul <- which(b == 0L)[1L]
  # The problem at the 1-based position index, unless U+0000 comes earlier.
  found <- function(code, index) {
    if (!is.na(nul) && nul < index) {
      return(list(code = "E1202", offset = nul - 1L))
    }
    list(code = code, offset = index - 1L)
  }
  # The number of bytes of the line break at position i, or 0. libyaml ends
  # lines at LF, CR LF, CR, U+0085 (C2 85), U+2028 (E2 80 A8) and U+2029
  # (E2 80 A9).
  break_width <- function(i) {
    v <- b[i]
    if (v == 10L) {
      return(1L)
    }
    if (v == 13L) {
      return(if (i < n && b[i + 1L] == 10L) 2L else 1L)
    }
    if (v == 0xC2L && i < n && b[i + 1L] == 0x85L) {
      return(2L)
    }
    if (v == 0xE2L && i + 2L <= n && b[i + 1L] == 0x80L &&
        (b[i + 2L] == 0xA8L || b[i + 2L] == 0xA9L)) {
      return(3L)
    }
    0L
  }
  is_break <- function(i) break_width(i) > 0L
  is_blank <- function(i) b[i] == 32L || b[i] == 9L
  # Whether position j is past the end or holds a space, a tab or a line break.
  follows_end <- function(j) j > n || is_blank(j) || is_break(j)
  starts_with <- function(i, text) {
    pattern <- utf8ToInt(text)
    last <- i + length(pattern) - 1L
    last <= n && all(b[i:last] == pattern)
  }
  i <- 1L
  content <- FALSE
  ended <- FALSE
  depth <- 0L
  node_start <- FALSE
  after_quote <- FALSE
  line_begin <- 1L
  indent <- 0L
  at_line_start <- TRUE
  while (i <= n) {
    if (at_line_start) {
      at_line_start <- FALSE
      line_begin <- i
      if (b[i] == 37L) {
        return(found("E3005", i))
      }
      if ((starts_with(i, "---") || starts_with(i, "...")) && follows_end(i + 3L)) {
        if (b[i] == 45L) {
          if (content) {
            return(found("E3003", i))
          }
          node_start <- TRUE
        } else {
          ended <- TRUE
          node_start <- FALSE
        }
        i <- i + 3L
        next
      }
      j <- i
      while (j <= n && b[j] == 32L) {
        j <- j + 1L
      }
      indent <- j - i
      node_start <- TRUE
      after_quote <- FALSE
    }
    c <- b[i]
    width <- break_width(i)
    if (width > 0L) {
      i <- i + width
      at_line_start <- TRUE
      next
    }
    if (c == 32L || c == 9L) {
      i <- i + 1L
      next
    }
    if (c == 35L && (i == line_begin || is_blank(i - 1L))) {
      while (i <= n && !is_break(i)) {
        i <- i + 1L
      }
      next
    }
    if (c == 0L) {
      return(found("E1202", i))
    }
    if (ended) {
      return(found("E3003", i))
    }
    content <- TRUE
    if (!node_start) {
      # libyaml reads '?' and ':' outside a scalar as indicators whatever
      # follows them while a bracket is open.
      if (c %in% c(45L, 63L, 58L) &&
          (follows_end(i + 1L) || (c == 58L && after_quote) || (c != 45L && depth > 0L))) {
        node_start <- TRUE
      } else if (c == 44L && depth > 0L) {
        node_start <- TRUE
      } else if (c == 91L || c == 123L) {
        depth <- depth + 1L
        node_start <- TRUE
      } else if (c == 93L || c == 125L) {
        depth <- max(0L, depth - 1L)
      }
      after_quote <- FALSE
      i <- i + 1L
      next
    }
    node_start <- FALSE
    after_quote <- FALSE
    if (c == 38L || c == 42L) {
      return(found("E3004", i))
    }
    if (c == 33L) {
      return(found("E3005", i))
    }
    if (c %in% c(45L, 63L, 58L) && (follows_end(i + 1L) || (c != 45L && depth > 0L))) {
      node_start <- TRUE
      i <- i + 1L
      next
    }
    if (c == 91L || c == 123L) {
      depth <- depth + 1L
      node_start <- TRUE
      i <- i + 1L
      next
    }
    if (c == 93L || c == 125L) {
      depth <- max(0L, depth - 1L)
      i <- i + 1L
      next
    }
    if (c == 39L) {
      # A single-quoted scalar, which ends at a quotation mark that is not
      # doubled.
      i <- i + 1L
      while (i <= n) {
        if (b[i] == 39L) {
          if (i < n && b[i + 1L] == 39L) {
            i <- i + 2L
            next
          }
          break
        }
        i <- i + 1L
      }
      i <- i + 1L
      after_quote <- TRUE
      next
    }
    if (c == 34L) {
      # A double-quoted scalar, in which the escapes of U+0000 are refused.
      i <- i + 1L
      while (i <= n && b[i] != 34L) {
        if (b[i] == 92L) {
          for (escape in c("\\0", "\\x00", "\\u0000", "\\U00000000")) {
            if (starts_with(i, escape)) {
              return(found("E1202", i))
            }
          }
          i <- i + 2L
          next
        }
        i <- i + 1L
      }
      i <- i + 1L
      after_quote <- TRUE
      next
    }
    if ((c == 124L || c == 62L) && depth == 0L) {
      # A block scalar: the rest of its line and every following line that is
      # empty, holds only spaces and tabs or is indented further.
      while (i <= n && !is_break(i)) {
        i <- i + 1L
      }
      while (i <= n) {
        i <- i + break_width(i)
        j <- i
        while (j <= n && b[j] == 32L) {
          j <- j + 1L
        }
        k <- j
        while (k <= n && is_blank(k)) {
          k <- k + 1L
        }
        if (k <= n && !is_break(k) && j - i <= indent) {
          break
        }
        while (i <= n && !is_break(i)) {
          if (b[i] == 0L) {
            return(found("E1202", i))
          }
          i <- i + 1L
        }
      }
      at_line_start <- TRUE
      next
    }
    if (starts_with(i, "<<")) {
      # A plain scalar that starts with '<<', which yaml can read as a merge
      # key whatever follows.
      return(found("E3009", i))
    }
    # A plain scalar.
    while (i <= n) {
      if (is_break(i)) {
        break
      }
      if (b[i] == 58L && follows_end(i + 1L)) {
        break
      }
      if (is_blank(i) && i < n && b[i + 1L] == 35L) {
        break
      }
      if (depth > 0L && b[i] %in% c(44L, 91L, 93L, 123L, 125L)) {
        break
      }
      if (b[i] == 0L) {
        return(found("E1202", i))
      }
      i <- i + 1L
    }
  }
  if (!is.na(nul)) {
    return(list(code = "E1202", offset = nul - 1L))
  }
  if (!content) {
    return(list(code = "E3010", offset = NULL))
  }
  NULL
}

# The implicit types of the yaml package, each of which gets a handler that
# returns the scalar's text, so that no scalar is converted.
yaml_scalar_types <- c(
  "str", "int", "int#hex", "int#oct", "int#base60", "float", "float#fix", "float#exp",
  "float#base60", "float#nan", "float#inf", "float#neginf", "bool#yes", "bool#no", "null",
  "timestamp#ymd", "timestamp#iso8601", "timestamp#spaced", "binary", "bool#na", "int#na",
  "float#na", "str#na"
)

# Step 3: parses the text with libyaml through the yaml package, with every
# scalar read as its text and every sequence as a list. A mapping becomes a
# list with the attribute 'keys'. A failure of the parser gives E3002, and a
# mapping that holds two equal keys E3007, whichever yaml meets first. The
# message of the yaml package, which gives the line and column of a syntax
# error or the duplicate key, follows the message of the issue as the last
# line of the condition's message (docs/spec/errors.md, Issues and
# conditions).
yaml_parse <- function(text) {
  keep <- function(x) x
  handlers <- rep(list(keep), length(yaml_scalar_types) + 1L)
  names(handlers) <- c(yaml_scalar_types, "seq")
  parsed <- tryCatch(
    yaml::yaml.load(text, as.named.list = FALSE, handlers = handlers),
    error = function(e) e
  )
  if (inherits(parsed, "error")) {
    detail <- trimws(conditionMessage(parsed), "right")
    code <- if (startsWith(detail, "Duplicate map key")) "E3007" else "E3002"
    condition <- issue_condition(list(new_issue(code)), "mixedcheck_error")
    condition$message <- paste0(condition$message, "\n", detail)
    stop(condition)
  }
  parsed
}

# The text of a scalar from yaml. yaml reads a plain scalar that starts with
# '<<' as a merge key, which it returns as a value of class '_yaml.merge_'
# that has lost the rest of the text. The pre-scan refuses such scalars, so
# one that reaches here shows that the pre-scan has failed (E9001).
yaml_scalar_text <- function(x) {
  if (inherits(x, "_yaml.merge_")) {
    raise_issue("E9001", list(detail = "the YAML pre-scan missed a merge key"))
  }
  x
}

# The forms of an integer and of a number of RFC 8259.
integer_text <- "^-?(0|[1-9][0-9]*)$"
number_text <- "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"

yaml_is_mapping <- function(x) is.list(x) && !is.null(attr(x, "keys"))

# Step 4: walks the parsed value depth first in the order of the text, each
# key before its value, and reports the first key that is a sequence or a
# mapping (E3006, at the pointer of the mapping) or that is empty (E1109, at
# the pointer of its member). The walk keeps its own stack, so
# that no depth of nesting exhausts R's C stack before step 5 reports E1030.
yaml_check_keys <- function(node, tokens) {
  # The stack holds nodes with their tokens, and a key that fails as a code
  # with the pointer of its issue, placed in the order of the walk: a key is
  # reported after the values of the earlier members of its mapping.
  nodes <- list(node)
  paths <- list(tokens)
  codes <- NA_character_
  top <- 1L
  while (top > 0L) {
    item <- nodes[[top]]
    path <- paths[[top]]
    code <- codes[top]
    top <- top - 1L
    if (!is.na(code)) {
      raise_issue(code, pointer = path)
    }
    if (!is.list(item) || length(item) == 0L) {
      next
    }
    keys <- attr(item, "keys")
    count <- length(item)
    child_nodes <- vector("list", count + 1L)
    child_paths <- vector("list", count + 1L)
    child_codes <- rep(NA_character_, count + 1L)
    used <- 0L
    for (m in seq_len(count)) {
      used <- used + 1L
      if (is.null(keys)) {
        child_nodes[used] <- list(item[[m]])
        child_paths[[used]] <- c(path, as.character(m - 1L))
        next
      }
      key <- keys[[m]]
      if (is.list(key)) {
        child_codes[used] <- "E3006"
        child_paths[[used]] <- json_pointer(path)
        break
      }
      key <- yaml_scalar_text(key)
      if (!nzchar(key)) {
        child_codes[used] <- "E1109"
        child_paths[[used]] <- json_pointer(c(path, key))
        break
      }
      child_nodes[used] <- list(item[[m]])
      child_paths[[used]] <- c(path, key)
    }
    reversed <- rev(seq_len(used))
    nodes[top + seq_len(used)] <- child_nodes[reversed]
    paths[top + seq_len(used)] <- child_paths[reversed]
    codes[top + seq_len(used)] <- child_codes[reversed]
    top <- top + used
  }
  invisible()
}

# Step 5: converts the parsed value to JSON. Mappings become objects,
# sequences arrays and scalars strings, which are coerced to the type that the
# declaration schema requires at their position (declarations.md, YAML
# authoring). The value is walked in the order of its canonical serialisation,
# keys before values, and the first violation of the hashable profile or
# coercion is reported.
yaml_convert_declaration <- function(root) {
  convert <- function(node, tokens, containers, depth) {
    if (is.list(node)) {
      pointer <- json_pointer(tokens)
      if (depth == 64L) {
        raise_issue("E1030", list(limit = 64L), pointer = pointer)
      }
      keys <- attr(node, "keys")
      if (is.null(keys)) {
        result <- vector("list", length(node))
        for (m in seq_along(node)) {
          result[m] <- list(convert(node[[m]], c(tokens, as.character(m - 1L)),
                                    c(containers, "array"), depth + 1L))
        }
        return(result)
      }
      keys <- vapply(keys, yaml_scalar_text, "")
      result <- vector("list", length(node))
      names(result) <- keys
      codes <- key_profile_codes(keys, "hashable")
      for (m in utf16_order(keys)) {
        if (!is.na(codes[m])) {
          raise_issue(codes[m], pointer = json_pointer(c(tokens, keys[m])))
        }
        result[m] <- list(convert(node[[m]], c(tokens, keys[m]), c(containers, "object"),
                                  depth + 1L))
      }
      return(result)
    }
    yaml_coerce(yaml_scalar_text(node), tokens, containers)
  }

  # The value of a member of a mapping of the parsed value, or NULL.
  member <- function(node, key) {
    if (!yaml_is_mapping(node)) {
      return(NULL)
    }
    keys <- vapply(attr(node, "keys"), function(k) if (is.list(k)) "" else yaml_scalar_text(k), "")
    found <- which(keys == key)
    if (length(found)) node[[found[1L]]] else NULL
  }
  # The text of the type of a field of the parsed value, or NULL.
  field_type <- function(field) {
    type <- member(field, "type")
    if (is.character(type)) yaml_scalar_text(type) else NULL
  }
  fields <- member(member(root, "table"), "fields")
  if (!is.list(fields) || yaml_is_mapping(fields)) {
    fields <- NULL
  }

  # Where the schema requires a type other than string: 'boolean', 'number'
  # or the type of a field, given as the field's type text, or NA.
  position <- function(tokens, containers) {
    shape <- paste(containers, collapse = " ")
    count <- length(tokens)
    if (count == 4L && shape == "object object array object" &&
        identical(tokens[c(1L, 2L, 4L)], c("table", "fields", "categoriesOrdered"))) {
      return(list(kind = "boolean"))
    }
    if (count == 3L && shape == "object array object" &&
        ((tokens[1L] == "assignment" && tokens[3L] == "randomised") ||
         (tokens[1L] == "estimands" && tokens[3L] == "focal"))) {
      return(list(kind = "boolean"))
    }
    if (count == 2L && shape == "object object" &&
        identical(tokens, c("provenance", "outcome_seen"))) {
      return(list(kind = "boolean"))
    }
    if (count == 4L && shape == "object object object array" &&
        tokens[1L] == "variables" && tokens[3L] == "bounds") {
      return(list(kind = "number"))
    }
    category <- (count == 5L && shape == "object object array object array") ||
      (count == 6L && shape == "object object array object array object" && tokens[6L] == "value")
    if (category && identical(tokens[c(1L, 2L, 4L)], c("table", "fields", "categories"))) {
      field <- fields[[as.integer(tokens[3L]) + 1L]]
      return(list(kind = "typed", type = field_type(field)))
    }
    if (count == 3L && shape == "object object object" &&
        tokens[1L] == "variables" && tokens[3L] == "event_level") {
      named <- Filter(function(field) {
        name <- member(field, "name")
        is.character(name) && yaml_scalar_text(name) == tokens[2L]
      }, fields)
      type <- if (length(named)) field_type(named[[1L]])
      return(list(kind = "typed", type = type))
    }
    list(kind = "string")
  }

  yaml_coerce <- function(text, tokens, containers) {
    pointer <- json_pointer(tokens)
    target <- position(tokens, containers)
    kind <- target$kind
    if (kind == "typed") {
      type <- target$type
      kind <- if (identical(type, "string")) {
        "string"
      } else if (identical(type, "integer")) {
        "integer"
      } else if (grepl(integer_text, text, useBytes = TRUE)) {
        "integer"
      } else {
        "string"
      }
    }
    if (kind == "boolean") {
      if (!text %in% c("true", "false")) {
        raise_issue("E3008", list(value = text, type = "a boolean"), pointer = pointer)
      }
      return(text == "true")
    }
    if (kind %in% c("integer", "number")) {
      # TRE's '$' matches only at the end of the text, unlike PCRE's.
      form <- if (kind == "integer") integer_text else number_text
      if (!grepl(form, text, useBytes = TRUE)) {
        required <- if (kind == "integer") "an integer" else "a number"
        raise_issue("E3008", list(value = text, type = required), pointer = pointer)
      }
      code <- hashable_token_codes(text)
      if (!is.na(code)) {
        raise_issue(code, list(number = text), pointer = pointer)
      }
      return(as.double(jsonlite::parse_json(paste0("[", text, "]"), simplifyVector = TRUE)))
    }
    code <- hashable_string_codes(text)
    if (!is.na(code)) {
      raise_issue(code, pointer = pointer)
    }
    text
  }

  convert(root, character(0), character(0), 0L)
}
