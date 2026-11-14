# The builder of the canonical IR (docs/spec/ir.md): expansion of the parsed
# formula into terms, the kinds and levels of columns, the coding argument,
# contrasts or indicators in each term, the columns and names of each part,
# the centring constants and the IR document. It reports the first issue that
# its stages find, in the order of ir.md (Errors).

#' Build the canonical IR of a model
#'
#' Parses an lme4-style formula with the in-house parser of mixedcheck and
#' builds the canonical intermediate representation (IR) of the model, which
#' both packages compute identically: the response, the coding of every
#' predictor, the terms and columns of the fixed part, the random terms with
#' their grouping factors and columns, the offsets, the weights and the
#' further sample columns. [canonical_hash()] of the IR in the hashable
#' profile gives its IR hash.
#'
#' The formula grammar is that of lme4 with the differences that the IR
#' specification of mixedcheck lists. Terms are expanded and ordered as R
#' orders them. Levels come from the declared categories or from all rows of
#' the data, in code-point order after NFC normalisation, never from a
#' sample, and the first level is the reference unless the coding argument
#' names another. Each categorical variable is coded by its contrast or by
#' indicators in each term, as in R, unless the coding argument freezes it.
#'
#' @param formula The formula, as a character string of at most 10,000
#'   characters, such as `"rt ~ cond + (1 + cond | subject)"`.
#' @param declaration `NULL`, the path of a declaration file in JSON or YAML,
#'   or a declaration in memory as a named list, as [validate_declaration()]
#'   accepts it. The declaration is validated first. The builder reads its
#'   table block, for the types and categories of columns, and the
#'   `variables` entry of the response, for its event level, trials and
#'   exposure. It also reads the units, roles and `disclosure_unit`, for the
#'   columns that identify persons, which cannot be predictors.
#' @param data `NULL`, or a data frame, such as [read_table()] returns. Its
#'   columns are numbers (double or integer), strings (character, or a factor,
#'   whose labels are used and whose level order is ignored) or logical
#'   values. Only `NA` is a missing value, and `NaN`, `Inf` and `-Inf` are
#'   values, so strings such as '' or 'NA' that a declaration lists as missing
#'   values must be `NA`, as [read_table()] returns them. Column names are
#'   compared after NFC normalisation and must differ after it. A column that
#'   the table block declares must hold values of its type, unless all its
#'   values are missing. Without data, the columns are the fields of the
#'   table block.
#' @param coding `NULL`, or a named list with one entry for each predictor
#'   whose coding departs from the defaults, keyed by column name. An entry
#'   is a named list with any of the members `contrast` ('treatment', 'sum'
#'   or 'simple'), `reference` (a level, as a string, a whole number or a
#'   logical value), `frozen` (`TRUE` or `FALSE`) for a categorical
#'   predictor and `centring` ('none', 'mean' or 'value'),
#'   `significant_digits` (1 to 15, with 'mean', by default 6) and `value` (a
#'   decimal string, with 'value') for a numeric one.
#' @param weights `NULL`, or the name of a column of precision weights.
#' @param sample_columns `NULL`, or a character vector of further columns
#'   whose missing values remove rows from the design sample. Columns that the
#'   IR reads already, such as the response, are left out.
#' @return The IR as a named list in the form that [read_json_strict()]
#'   returns: objects as named lists, arrays as unnamed lists, strings marked
#'   UTF-8, numbers as doubles and booleans as logical values. Its members are
#'   `ir_version`, `response` (absent for a one-sided formula), `predictors`,
#'   `fixed`, `random`, `offsets`, `weights` (when named) and
#'   `sample_columns` (when any remain), as the IR specification describes.
#'   Term indices count from 0 in the IR, in both packages.
#' @section Errors: A problem with the formula or its context is signalled as
#'   an error of class `mixedcheck_error`, whose element `issues` holds one
#'   issue of the formula area: a list with the `code` of the shared error
#'   catalogue, the rendered `message` and, when the code has a location, the
#'   byte `offset` into the UTF-8 encoding of the formula, counted from 0. A
#'   declaration that is not valid gives the error of
#'   [validate_declaration()]. A string that cannot be read as UTF-8 gives a
#'   code of the JSON writer at its JSON Pointer, such as `/formula` or
#'   `/data/<column>/<row>`: E1204 for an unmarked string outside ASCII in a
#'   session that is not UTF-8, E1201 for a string marked UTF-8 that is not
#'   valid UTF-8 and E1205 for a string marked 'bytes'. Python reports E1206
#'   for a string with a surrogate code point at the same pointers. Arguments
#'   of the wrong type and data whose columns cannot be read give an ordinary
#'   error.
#' @seealso [design_matrices()], which builds the design matrices of an IR.
#' @export
#' @examples
#' # Fixture Z19N of the pathology zoo (pathology_zoo()): pupils in schools,
#' # with a treatment group and a baseline score that 7 pupils lack.
#' fixture <- pathology_zoo("Z19N")
#' fixture$formula
#'
#' # The IR before the data are seen, from the declaration alone.
#' ir <- formula_ir(fixture$formula, fixture$declaration,
#'                  coding = list(group = list(contrast = "simple")))
#' canonical_hash(ir, "hashable")
#' vapply(ir$fixed$columns, function(column) column$name, "")
#'
#' # A mean centring takes its constant from the data.
#' ir <- formula_ir(fixture$formula, fixture$declaration, fixture$data,
#'                  coding = list(pre = list(centring = "mean")))
#' ir$predictors$pre$centring
#'
#' # log() is allowed only around the response or the column of an offset.
#' problem <- tryCatch(formula_ir("y ~ group + log(pre) + (1 | school)", fixture$declaration),
#'                     mixedcheck_error = function(e) e)
#' problem$issues[[1]]$message
formula_ir <- function(formula, declaration = NULL, data = NULL, coding = NULL,
                       weights = NULL, sample_columns = NULL) {
  if (!is.character(formula) || length(formula) != 1L || is.na(formula)) {
    stop("'formula' must be a character string.", call. = FALSE)
  }
  if (!is.null(data) && !is.data.frame(data)) {
    stop("'data' must be NULL or a data frame.", call. = FALSE)
  }
  if (!is.null(weights) && (!is.character(weights) || length(weights) != 1L || is.na(weights))) {
    stop("'weights' must be NULL or a column name.", call. = FALSE)
  }
  if (!is.null(sample_columns) &&
      (!is.character(sample_columns) || anyNA(sample_columns))) {
    stop("'sample_columns' must be NULL or a character vector of column names.", call. = FALSE)
  }
  check_coding_argument(coding)
  if (!is.null(declaration)) {
    declaration <- validate_declaration(declaration)
  }
  formula <- input_strings(formula, function(i) "/formula")
  if (!is.null(weights)) {
    weights <- input_strings(weights, function(i) "/weights")
  }
  if (length(sample_columns)) {
    sample_columns <- input_strings(sample_columns,
                                    function(i) json_pointer(c("sample_columns", i - 1L)))
  } else {
    sample_columns <- character(0)
  }
  coding <- coding_input(coding)
  fields <- declaration[["table"]][["fields"]]
  table <- if (!is.null(data)) model_table(data, fields)
  build_formula_ir(formula, declaration, table, coding, weights, sample_columns)
}

# --- Inputs ---------------------------------------------------------------------

# The input boundary of conventions.md (Strings in R) for a character vector
# that the caller passes in: unmarked strings outside ASCII are marked UTF-8
# in a UTF-8 session and strings marked latin1 are converted. A string that
# cannot be read as UTF-8 gives the writer's code at the pointer that
# pointer_of() gives its index.
input_strings <- function(x, pointer_of) {
  attributes(x) <- NULL
  checked <- writer_strings(mark_input_strings(x))
  bad <- which(!is.na(checked$code))
  if (length(bad)) {
    raise_issue(checked$code[bad[1L]], pointer = pointer_of(bad[1L]))
  }
  checked$value
}

# The coding argument must be NULL or a named list of entries, each a list
# that is empty or has unique names.
check_coding_argument <- function(coding) {
  if (is.null(coding)) {
    return(invisible())
  }
  entries_ok <- is.list(coding) && is.null(attr(coding, "class")) &&
    (length(coding) == 0L || (!is.null(names(coding)) && !anyNA(names(coding)) &&
                                all(nzchar(names(coding)))))
  if (entries_ok) {
    entries_ok <- all(vapply(coding, function(entry) {
      is.list(entry) && is.null(attr(entry, "class")) &&
        (length(entry) == 0L || (!is.null(names(entry)) && !anyNA(names(entry)) &&
                                   all(nzchar(names(entry))) && !anyDuplicated(names(entry))))
    }, NA))
  }
  if (!entries_ok) {
    stop("'coding' must be NULL or a named list of named lists, one for each column.",
         call. = FALSE)
  }
  invisible()
}

# The coding argument with its keys and member names marked, its string
# values marked and its entries keyed by the comparison forms of the keys.
coding_input <- function(coding) {
  if (!length(coding)) {
    return(list(keys = character(0), names = character(0), entries = list()))
  }
  keys <- input_strings(names(coding), function(i) json_pointer(c("coding", names(coding)[i])))
  entries <- lapply(seq_along(coding), function(k) {
    entry <- coding[[k]]
    if (length(entry)) {
      names(entry) <- input_strings(names(entry), function(i) {
        json_pointer(c("coding", keys[k], names(entry)[i]))
      })
      for (m in seq_along(entry)) {
        value <- entry[[m]]
        if (is.character(value) && length(value) == 1L && !is.na(value)) {
          entry[[m]] <- input_strings(value, function(i) {
            json_pointer(c("coding", keys[k], names(entry)[m]))
          })
        }
      }
    }
    entry
  })
  forms <- comparison_form(keys)
  if (anyDuplicated(forms)) {
    stop(sprintf("'coding' names the column '%s' twice.",
                 display_text(keys[duplicated(forms)][1L])), call. = FALSE)
  }
  list(keys = forms, names = keys, entries = entries)
}

# The data in the form the builder reads: the names, their comparison forms,
# and for each column its values (double, character marked UTF-8 or
# logical), its type ('number', 'string' or 'boolean') and which values are
# missing. Only NA is missing, and NaN, Inf and -Inf are numbers. fields are
# the fields of the declaration's table block, which give the type a column
# must have.
model_table <- function(data, fields) {
  raw_names <- names(data)
  if (is.null(raw_names) || anyNA(raw_names)) {
    stop("The columns of 'data' must have names.", call. = FALSE)
  }
  column_names <- input_strings(raw_names, function(i) json_pointer(c("data", raw_names[i])))
  keys <- comparison_form(column_names)
  valid <- valid_column_name(column_names)
  if (!all(valid)) {
    stop(sprintf("The column name '%s' of 'data' is not a valid column name.",
                 display_text(column_names[!valid][1L])), call. = FALSE)
  }
  if (anyDuplicated(keys)) {
    stop(sprintf("Two columns of 'data' are named '%s' after NFC normalisation.",
                 display_text(keys[duplicated(keys)][1L])), call. = FALSE)
  }
  field_keys <- comparison_form(vapply(fields, function(field) field[["name"]], ""))
  columns <- lapply(seq_along(data), function(j) {
    field <- fields[match(keys[j], field_keys)]
    model_column(data[[j]], column_names[j], if (length(field)) field[[1L]])
  })
  list(
    names = column_names,
    keys = keys,
    values = lapply(columns, function(column) column$values),
    types = vapply(columns, function(column) column$type, ""),
    missing = lapply(columns, function(column) column$missing),
    rows = nrow(data)
  )
}

# The type of values that a declared field requires.
field_value_type <- function(field) {
  type <- field[["type"]] %||% "string"
  switch(type, integer = , number = "number", boolean = "boolean", "string")
}

model_column <- function(x, name, field) {
  if (is.factor(x)) {
    x <- levels(x)[x]
  }
  if (typeof(x) == "logical" && !is.object(x) && is.null(dim(x))) {
    type <- "boolean"
    attributes(x) <- NULL
  } else if (typeof(x) %in% c("double", "integer") && !is.object(x) && is.null(dim(x))) {
    type <- "number"
    x <- as.double(x)
    attributes(x) <- NULL
  } else if (typeof(x) == "character" && !is.object(x) && is.null(dim(x))) {
    type <- "string"
    x <- input_strings(x, function(i) json_pointer(c("data", name, i - 1L)))
  } else {
    stop(sprintf("The column '%s' of 'data' is not a vector of numbers, strings or logical values.",
                 display_text(name)), call. = FALSE)
  }
  missing <- is.na(x) & !(type == "number" & is.nan(x))
  if (!is.null(field)) {
    wanted <- field_value_type(field)
    if (all(missing)) {
      x <- switch(wanted, number = rep(NA_real_, length(x)), boolean = rep(NA, length(x)),
                  rep(NA_character_, length(x)))
      type <- wanted
    } else if (type != wanted) {
      stop(sprintf("The column '%s' of 'data' holds %s values, but the table block declares the type '%s'.",
                   display_text(name), type, field[["type"]] %||% "string"), call. = FALSE)
    }
  }
  list(values = x, type = type, missing = missing)
}

# --- The builder ----------------------------------------------------------------

build_formula_ir <- function(formula, declaration, table, coding, weights, sample_columns) {
  tree <- formula_tree(formula)
  # Stage 5: expansion.
  model <- formula_expand(tree)
  raise_found(model$issue)
  # Stage 6: context, whose last pass checks the names of the assembled IR.
  context <- formula_context(model, declaration, table, coding, weights, sample_columns)
  ir <- ir_document(model, context)
  long <- ir_long_name(ir)
  if (!is.null(long)) {
    raise_issue("E6076", list(name = long))
  }
  ir
}

# The name node of the response of a parsed formula that has passed the
# structural rules, with its transform, or NULL for a one-sided formula.
formula_response_node <- function(tree) {
  if (is.null(tree$lhs)) {
    return(NULL)
  }
  log_call <- formula_sole_call(tree$lhs, "log")
  node <- if (is.null(log_call)) tree$lhs$summands[[1L]]$expr else
    log_call$args[[1L]]$lhs$summands[[1L]]$expr
  list(node = node, transform = if (is.null(log_call)) "identity" else "log")
}

# The parsed formula after the first four stages of the builder, which need
# no data: length, tokens, syntax and structure. The issue of the first stage
# that fails is signalled.
formula_tree <- function(formula) {
  text <- formula_text(formula)
  if (length(text$codepoints) > 10000L) {
    raise_issue("E6001")
  }
  tokens <- formula_tokens(text)
  if (!any(vapply(tokens, function(token) token$type == "op" && token$text == "~", NA))) {
    raise_issue("E6008")
  }
  tree <- formula_parse(tokens, text$bytes)
  raise_found(formula_structure_issue(tree))
  tree
}

# The response of a formula, as the key by which the IR names its column, or
# NULL for a one-sided formula.
formula_response_key <- function(formula) {
  formula_response_node(formula_tree(formula))$node$key
}

# The first name of an IR, in the order of its canonical serialisation, that
# has more than 10,000 characters, or NULL (ir.md, Names).
ir_long_name <- function(ir) {
  part_names <- function(part) {
    c(vapply(part$columns, function(column) column$name, ""),
      vapply(part$terms, function(term) term$name, ""))
  }
  names_in_order <- c(part_names(ir$fixed), unlist(lapply(ir$random, function(term) {
    c(vapply(term$columns, function(column) column$name, ""), term$factor, term$name,
      vapply(term$terms, function(t) t$name, ""))
  })))
  long <- names_in_order[nchar(names_in_order, type = "chars") > formula_limit]
  if (length(long)) long[[1L]]
}

raise_found <- function(found) {
  if (!is.null(found)) {
    raise_issue(found$code, found$args, offset = found$offset)
  }
}

# --- Expansion ------------------------------------------------------------------

# The name nodes of an expression, from left to right. The operands of a
# chain and the summands of a sum are visited in a loop, so that only
# parentheses and calls add to the depth of recursion.
formula_names <- function(node) {
  switch(node$kind,
    name = list(node),
    number = list(),
    call = unlist(lapply(node$args, formula_names), recursive = FALSE),
    paren = formula_names(node$arg),
    argument = c(formula_names(node$lhs), if (!is.null(node$bar)) formula_names(node$rhs)),
    chain = unlist(lapply(node$operands, formula_names), recursive = FALSE),
    power = c(formula_names(node$base), formula_names(node$exponent)),
    sum = unlist(lapply(node$summands, function(summand) formula_names(summand$expr)),
                 recursive = FALSE)
  )
}

# The identity of a term, a set of variable keys.
term_key <- function(term) paste(sort(term, method = "radix"), collapse = "\001")

# A list of terms carries the key of each term beside it, computed once when
# the term is formed, so that unions and removals compare the stored keys.
# Each term holds its variable keys sorted and without repetitions.
term_list <- function(terms) {
  list(terms = terms, keys = vapply(terms, paste, "", collapse = "\001"))
}

# The terms of a list without repetitions, each kept where it first appears.
terms_distinct <- function(list) {
  keep <- !duplicated(list$keys)
  list(terms = list$terms[keep], keys = list$keys[keep])
}

# Appends the terms of b that a does not hold.
terms_union <- function(a, b) {
  keep <- !b$keys %in% a$keys & !duplicated(b$keys)
  list(terms = c(a$terms, b$terms[keep]), keys = c(a$keys, b$keys[keep]))
}

# For each term of a in order and, within it, each term of b in order, the
# union of the two.
terms_interact <- function(a, b) {
  i <- rep(seq_along(a$terms), each = length(b$terms))
  j <- rep(seq_along(b$terms), times = length(a$terms))
  terms_distinct(term_list(Map(function(x, y) {
    sort(unique(c(x, y)), method = "radix")
  }, a$terms[i], b$terms[j])))
}

# The most terms that a list of terms may hold, and the most columns of a
# part and characters of a name (ir.md, Operators and Names).
formula_limit <- 10000

# A signal that stops the evaluation of a part at its first issue.
expansion_stop <- function(code, offset, args = list()) {
  stop(structure(class = c("mixedcheck_expansion", "condition"),
                 list(message = code, call = NULL,
                      issue = list(code = code, offset = offset, args = args))))
}

# Evaluates the summands of a part (ir.md, Operators). Returns its intercept
# and its terms in term order, each with its variables in the order of their
# first appearance in the part, or the first issue as list(issue = ).
# Intercept summands, random terms and offsets are left out of the terms.
evaluate_part <- function(summands, order) {
  term_name <- function(term) {
    paste(formula_variable_text(order[order %in% term]), collapse = ":")
  }
  # Each operand of a chain is evaluated before the operator that joins it
  # to the terms of the operands before it.
  evaluate <- function(node) {
    switch(node$kind,
      name = list(terms = list(node$key), keys = node$key),
      paren = {
        terms <- evaluate_sum(node$arg$lhs$summands)
        if (!length(terms$terms)) {
          expansion_stop("E6037", node$start)
        }
        terms
      },
      chain = {
        a <- evaluate(node$operands[[1L]])
        for (k in seq_along(node$ops)) {
          op <- node$ops[k]
          b <- evaluate(node$operands[[k + 1L]])
          # The terms the operator would form, counted with repetitions.
          count <- switch(op,
            ":" = length(a$terms) * length(b$terms),
            "*" = length(a$terms) + length(b$terms) + length(a$terms) * length(b$terms),
            "/" = length(a$terms) + length(b$terms)
          )
          if (count > formula_limit) {
            expansion_stop("E6038", node$at[k])
          }
          a <- switch(op,
            ":" = terms_interact(a, b),
            "*" = terms_union(terms_union(a, b), terms_interact(a, b)),
            "/" = {
              all_a <- unique(unlist(a$terms))
              terms_union(a, term_list(lapply(b$terms, function(term) {
                sort(unique(c(all_a, term)), method = "radix")
              })))
            }
          )
        }
        a
      },
      power = {
        a <- evaluate(node$base)
        result <- a
        for (k in seq_len(as.integer(node$exponent$text) - 1L)) {
          if (length(result$terms) * length(a$terms) > formula_limit) {
            expansion_stop("E6038", node$at)
          }
          following <- terms_interact(result, a)
          if (identical(following$keys, result$keys)) {
            break
          }
          result <- following
        }
        result
      }
    )
  }
  evaluate_sum <- function(summands) {
    held <- term_list(list())
    for (summand in summands) {
      expr <- summand$expr
      if (expr$kind == "number" || formula_is_random(expr) ||
          (expr$kind == "call" && expr$name == "offset")) {
        next
      }
      terms <- evaluate(expr)
      if (identical(summand$sign, "-")) {
        absent <- which(!terms$keys %in% held$keys)
        if (length(absent)) {
          expansion_stop("E6031", summand$sign_at, list(term = term_name(terms$terms[[absent[1L]]])))
        }
        keep <- !held$keys %in% terms$keys
        held <- list(terms = held$terms[keep], keys = held$keys[keep])
      } else {
        held <- terms_union(held, terms)
        if (length(held$terms) > formula_limit) {
          expansion_stop("E6038", summand$sign_at %||% expr$start)
        }
      }
    }
    held
  }
  intercept <- TRUE
  for (summand in summands) {
    if (summand$expr$kind == "number") {
      intercept <- summand$expr$text == "1" && !identical(summand$sign, "-")
    }
  }
  terms <- tryCatch(evaluate_sum(summands)$terms,
                    mixedcheck_expansion = function(condition) condition)
  if (inherits(terms, "mixedcheck_expansion")) {
    return(list(issue = terms$issue))
  }
  terms <- terms[order(lengths(terms), method = "radix")]
  terms <- lapply(terms, function(term) order[order %in% term])
  list(terms = terms, intercept = intercept)
}

# The name of a term whose variables are in order, each with the level it
# carries, if any.
term_name_of <- function(variables, labels = NULL) {
  if (!length(variables)) {
    return("(Intercept)")
  }
  parts <- formula_variable_text(variables)
  if (!is.null(labels)) {
    carried <- !is.na(labels)
    parts[carried] <- paste0(parts[carried], "[", labels[carried], "]")
  }
  paste(parts, collapse = ":")
}

# The name of a random term.
random_term_name <- function(intercept, term_names, factor_name) {
  paste0(paste(c(if (intercept) "1" else "0", term_names), collapse = " + "), " | ", factor_name)
}

# Expands the parsed formula (ir.md, Expansion) into the response, the fixed
# part, the random terms and the offsets, with every name of the formula and
# its use. The random terms are grouped by factor in the order in which each
# factor first arises. The first issue of expansion, by offset and then code,
# is returned as issue.
formula_expand <- function(tree) {
  found <- list()
  add <- function(issue) found[[length(found) + 1L]] <<- issue
  uses <- list()
  use <- function(nodes, kind, written = NA_integer_, double = FALSE) {
    for (node in nodes) {
      uses[[length(uses) + 1L]] <<- list(key = node$key, value = node$value, offset = node$start,
                                         use = kind, written = written, double = double)
    }
  }
  response <- formula_response_node(tree)
  if (!is.null(response)) {
    use(list(response$node), if (response$transform == "identity") "response" else "log_response")
    response <- list(key = response$node$key, value = response$node$value,
                     transform = response$transform, offset = response$node$start,
                     start = tree$lhs$start)
  }
  summands <- tree$rhs$summands
  kinds <- vapply(summands, function(summand) {
    expr <- summand$expr
    if (formula_is_random(expr)) "random" else if (expr$kind == "call") "offset" else
      if (expr$kind == "number") "number" else "fixed"
  }, "")
  # The fixed part.
  fixed_nodes <- unlist(lapply(summands[kinds == "fixed"], function(summand) {
    formula_names(summand$expr)
  }), recursive = FALSE)
  use(fixed_nodes, "predictor")
  fixed_order <- unique(vapply(fixed_nodes, function(node) node$key, ""))
  fixed <- evaluate_part(summands[kinds != "random" & kinds != "offset"], fixed_order)
  if (!is.null(fixed$issue)) {
    add(fixed$issue)
  }
  # The random terms, in the order in which they are written.
  factors <- list()
  factor_name <- function(key) {
    paste(formula_variable_text(named_member(factors, key)), collapse = ":")
  }
  produced <- list()
  written <- 0L
  for (summand in summands[kinds == "random"]) {
    written <- written + 1L
    node <- summand$expr
    double <- node$arg$bar == "||"
    lhs_nodes <- formula_names(node$arg$lhs)
    use(lhs_nodes, "predictor", written, double)
    grouping_nodes <- formula_names(node$arg$rhs)
    use(grouping_nodes, "grouping", written)
    order <- unique(vapply(lhs_nodes, function(n) n$key, ""))
    part <- evaluate_part(node$arg$lhs$summands, order)
    if (!is.null(part$issue)) {
      add(part$issue)
      next
    }
    grouping_keys <- vapply(grouping_nodes, function(n) n$key, "")
    repeated <- which(duplicated(grouping_keys))
    if (length(repeated)) {
      repeated_node <- grouping_nodes[[repeated[1L]]]
      add(list(code = "E6033", offset = repeated_node$start,
               args = list(column = repeated_node$value)))
      next
    }
    if (!part$intercept && !length(part$terms)) {
      add(list(code = "E6034", offset = node$start, args = list()))
      next
    }
    segments <- slash_segments(node$arg$rhs$summands[[1L]]$expr)
    for (k in seq_along(segments)) {
      keys <- unlist(segments[seq_len(k)])
      key <- term_key(keys)
      if (!key %in% names(factors)) {
        factors[[length(factors) + 1L]] <- keys
        names(factors)[length(factors)] <- key
      }
      pieces <- if (double) {
        c(if (part$intercept) list(list(intercept = TRUE, terms = list())),
          lapply(part$terms, function(term) list(intercept = FALSE, terms = list(term))))
      } else {
        list(list(intercept = part$intercept, terms = part$terms))
      }
      for (piece in pieces) {
        produced[[length(produced) + 1L]] <- list(
          factor = key, intercept = piece$intercept, terms = piece$terms,
          double = double, written = written, open = node$start
        )
      }
    }
  }
  # Duplicate random terms, before any term of a frozen factor is split.
  identities <- vapply(produced, function(term) {
    paste(term$factor, term$intercept,
          paste(sort(vapply(term$terms, term_key, ""), method = "radix"), collapse = "\002"),
          sep = "\003")
  }, "")
  for (k in which(duplicated(identities))) {
    earlier <- produced[[match(identities[k], identities)]]
    add(list(code = "E6035", offset = produced[[k]]$open, args = list(
      term = random_term_name(earlier$intercept,
                              vapply(earlier$terms, term_name_of, ""),
                              factor_name(earlier$factor)))))
  }
  # Offsets.
  offsets <- list()
  for (summand in summands[kinds == "offset"]) {
    argument <- summand$expr$args[[1L]]$lhs
    log_call <- formula_sole_call(argument, "log")
    name_node <- if (is.null(log_call)) argument$summands[[1L]]$expr else
      log_call$args[[1L]]$lhs$summands[[1L]]$expr
    transform <- if (is.null(log_call)) "identity" else "log"
    use(list(name_node), if (is.null(log_call)) "offset" else "log_offset")
    for (earlier in offsets) {
      if (earlier$key == name_node$key && earlier$transform == transform) {
        add(list(code = "E6036", offset = summand$expr$start, args = list()))
        break
      }
    }
    offsets[[length(offsets) + 1L]] <- list(key = name_node$key, value = name_node$value,
                                            transform = transform, at = summand$expr$start)
  }
  # The response after '~'.
  if (!is.null(response)) {
    again <- Filter(function(u) !u$use %in% c("response", "log_response") &&
                      u$key == response$key, uses)
    if (length(again)) {
      first <- again[[which.min(vapply(again, function(u) u$offset, 0))]]
      add(list(code = "E6032", offset = first$offset, args = list(column = response$value)))
    }
  }
  # The random terms of the IR, grouped by factor.
  factor_keys <- names(factors)
  if (length(produced)) {
    produced <- produced[order(match(vapply(produced, function(term) term$factor, ""),
                                     factor_keys), method = "radix")]
  }
  produced <- lapply(produced, function(term) {
    term$grouping <- named_member(factors, term$factor)
    term$factor_name <- factor_name(term$factor)
    term
  })
  list(
    issue = formula_first_issue(found),
    response = response,
    fixed = fixed,
    random = produced,
    offsets = offsets,
    uses = uses
  )
}

# The segments f1, f2, ... of a grouping f1/f2/..., each the keys of its
# names joined by ':' in the order written. The structural rules leave only
# ':' and '/' in a grouping.
slash_segments <- function(node) {
  segments <- if (node$kind == "chain" && all(node$ops == "/")) node$operands else list(node)
  lapply(segments, function(segment) vapply(formula_names(segment), function(n) n$key, ""))
}

# --- Context --------------------------------------------------------------------

# The columns that identify persons (ir.md, Kinds of columns): those with the
# role 'id' and the label columns of the disclosure unit, of every unit with
# the role 'participant' and of every unit nested in one of these.
person_columns <- function(declaration) {
  keys <- character(0)
  variables <- declaration[["variables"]]
  for (i in seq_along(variables)) {
    if (identical(variables[[i]][["role"]], "id")) {
      keys <- c(keys, names(variables)[i])
    }
  }
  units <- declaration[["units"]]
  unit_names <- vapply(units, function(unit) unit[["name"]], "")
  roles <- vapply(units, function(unit) unit[["role"]] %||% NA_character_, "")
  parents <- vapply(units, function(unit) unit[["nested_in"]] %||% NA_character_, "")
  disclosure <- declaration[["disclosure_unit"]]
  if (is.null(disclosure) && sum(roles %in% "participant") == 1L) {
    disclosure <- unit_names[roles %in% "participant"]
  }
  chosen <- unique(c(disclosure, unit_names[roles %in% "participant"]))
  repeat {
    more <- setdiff(unit_names[parents %in% chosen], chosen)
    if (!length(more)) {
      break
    }
    chosen <- c(chosen, more)
  }
  for (unit in units[unit_names %in% chosen]) {
    keys <- c(keys, unlist(unit[["columns"]]))
  }
  comparison_form(unique(keys))
}

# The label of a level in names: the string itself, an integer in decimal
# digits and a boolean as 'true' or 'false'.
level_label <- function(level) {
  if (is.character(level)) {
    return(level)
  }
  if (is.logical(level)) {
    return(if (level) "true" else "false")
  }
  format_integer(level)
}

# Runs the passes of ir.md (Errors, stage 6) and returns what the IR needs:
# the columns and their kinds, the predictors with their coding, the parts
# with their coding and columns, the offsets, the design sample and the
# centring constants.
formula_context <- function(model, declaration, table, coding, weights, sample_columns) {
  fields <- declaration[["table"]][["fields"]]
  field_keys <- comparison_form(vapply(fields, function(field) field[["name"]], ""))
  have_data <- !is.null(table)
  persons <- person_columns(declaration)
  # The kind and levels of a column, or NULL when it is not a column. The
  # cache is looked up with match(), which compares keys in UTF-8, since
  # `[[` translates them to the native encoding.
  column_cache <- list()
  column <- function(key) {
    cached <- named_member(column_cache, key)
    if (!is.null(cached)) {
      return(cached)
    }
    j <- NA_integer_
    if (have_data) {
      j <- match(key, table$keys)
      if (is.na(j)) {
        return(NULL)
      }
    }
    f <- match(key, field_keys)
    if (!have_data && is.na(f)) {
      return(NULL)
    }
    field <- if (!is.na(f)) fields[[f]]
    # The type of the declared field, or of the values without one.
    type <- if (!is.null(field)) field[["type"]] %||% "string" else
      switch(table$types[j], number = "number", boolean = "boolean", "string")
    info <- list(key = key, j = j, levels = NULL, source = NULL)
    if (!is.null(field[["categories"]])) {
      info$kind <- "categorical"
      info$levels <- lapply(field[["categories"]], list_item_value)
      info$source <- "declared"
    } else if (type == "boolean") {
      info$kind <- "categorical"
      info$levels <- list(FALSE, TRUE)
      info$source <- "boolean"
    } else if (type %in% c("date", "datetime")) {
      info$kind <- "date"
    } else if (type %in% c("number", "integer")) {
      info$kind <- "numeric"
    } else {
      info$kind <- "categorical"
      info$source <- "table"
      if (have_data) {
        values <- table$values[[j]][!table$missing[[j]]]
        info$levels <- as.list(sort_identifiers(unique(comparison_form(values))))
      }
    }
    column_cache[[length(column_cache) + 1L]] <<- info
    names(column_cache)[length(column_cache)] <<- key
    info
  }
  kind_of <- function(key) column(key)$kind
  uses <- model$uses
  first <- function(found) {
    issue <- formula_first_issue(found)
    raise_found(issue)
  }
  # Pass 1: columns.
  first(lapply(Filter(function(u) is.null(column(u$key)), uses), function(u) {
    list(code = "E6051", offset = u$offset, args = list(column = u$value))
  }))
  # The coding entry of a column, by the comparison form of its key.
  coding_entry <- function(key) {
    k <- match(key, coding$keys)
    if (is.na(k)) NULL else coding$entries[[k]]
  }
  frozen_by_coding <- function(key) {
    identical(coding_entry(key)[["frozen"]], TRUE)
  }
  # The declared variables entry of the response.
  response <- model$response
  declared <- NULL
  variables <- declaration[["variables"]]
  if (!is.null(response) && length(variables)) {
    k <- match(response$key, comparison_form(names(variables)))
    if (!is.na(k)) {
      declared <- variables[[k]]
    }
  }
  # Pass 2: uses.
  found <- list()
  add <- function(code, offset, args) found[[length(found) + 1L]] <<- list(code = code, offset = offset, args = args)
  allowed <- list(response = c("numeric", "categorical"), log_response = "numeric",
                  predictor = c("numeric", "categorical"), offset = "numeric",
                  log_offset = "numeric")
  use_names <- c(response = "the response", log_response = "the argument of log()",
                 predictor = "a predictor", offset = "an offset",
                 log_offset = "the argument of log()")
  double_seen <- integer(0)
  for (u in uses) {
    kind <- kind_of(u$key)
    if (u$use != "grouping" && !kind %in% allowed[[u$use]]) {
      add("E6052", u$offset, list(column = u$value, kind = kind, use = use_names[[u$use]]))
    }
    if (u$use == "predictor" && u$key %in% persons) {
      add("E6068", u$offset, list(column = u$value))
    }
    if (u$use == "predictor" && u$double && !u$written %in% double_seen &&
        kind == "categorical" && !frozen_by_coding(u$key)) {
      double_seen <- c(double_seen, u$written)
      add("E6053", u$offset, list(column = u$value))
    }
  }
  if (!is.null(response) && response$transform == "log") {
    member <- intersect(c("event_level", "trials", "exposure"), names(declared))
    if (length(member)) {
      add("E6054", response$start, list(member = member[1L]))
    }
  }
  first(found)
  # Pass 3: declared columns, weights and sample columns.
  numeric_column <- function(name) {
    info <- column(comparison_form(name))
    !is.null(info) && info$kind == "numeric"
  }
  trials <- declared[["trials"]]
  exposure <- declared[["exposure"]]
  if (!is.null(trials) && !numeric_column(trials)) {
    raise_issue("E6065", list(column = trials, member = "trials"))
  }
  if (!is.null(exposure) && !numeric_column(exposure[["column"]])) {
    raise_issue("E6065", list(column = exposure[["column"]], member = "exposure"))
  }
  if (!is.null(weights) && !numeric_column(weights)) {
    raise_issue("E6066", list(column = weights))
  }
  for (name in sample_columns) {
    if (is.null(column(comparison_form(name)))) {
      raise_issue("E6070", list(column = name))
    }
  }
  # The predictors of the IR: the columns of the terms after expansion.
  fixed <- model$fixed
  random <- model$random
  predictor_keys <- as.character(unique(c(unlist(fixed$terms), unlist(lapply(random, function(term) {
    unlist(term$terms)
  })))))
  predictor_keys <- predictor_keys[order(predictor_keys, method = "radix")]
  # The first appearance of a predictor in a product of the formula.
  first_use <- function(key) {
    candidates <- Filter(function(u) u$use == "predictor" && u$key == key, uses)
    candidates[[which.min(vapply(candidates, function(u) u$offset, 0))]]
  }
  # Pass 4: the coding argument.
  predictors <- lapply(predictor_keys, function(key) {
    info <- column(key)
    info$value <- key
    info
  })
  names(predictors) <- predictor_keys
  check_coding(coding, predictors)
  # Pass 5: levels.
  found <- list()
  # Predictors are looked up with match(), since `[[` translates their keys
  # to the native encoding (named_member()).
  for (key in predictor_keys) {
    info <- named_member(predictors, key)
    if (info$kind == "categorical") {
      appearance <- first_use(key)
      if (is.null(info$levels)) {
        add("E6055", appearance$offset, list(column = appearance$value))
      } else if (length(info$levels) < 2L) {
        add("E6056", appearance$offset, list(column = appearance$value))
      } else if (!all(levels_writable(info$levels))) {
        add("E6074", appearance$offset, list(column = appearance$value))
      }
    }
  }
  first(found)
  # Pass 6: reference levels and the coding of each predictor.
  for (key in predictor_keys) {
    info <- named_member(predictors, key)
    entry <- coding_entry(key)
    if (info$kind == "categorical") {
      reference <- entry[["reference"]]
      position <- 1L
      if (!is.null(reference)) {
        position <- level_position(reference, info$levels)
        if (is.na(position)) {
          raise_issue("E6064", list(reference = list(reference),
                                    column = coding$names[match(key, coding$keys)]))
        }
      }
      info$reference <- position
      info$contrast <- entry[["contrast"]] %||% "treatment"
      info$frozen <- isTRUE(entry[["frozen"]])
    } else {
      info$centring <- entry[["centring"]] %||% "none"
      info$digits <- entry[["significant_digits"]] %||% 6
      info$value_text <- entry[["value"]]
    }
    named_member(predictors, key) <- info
  }
  # Pass 7: the exposure.
  offsets <- model$offsets
  if (!is.null(exposure)) {
    exposure_key <- comparison_form(exposure[["column"]])
    wanted <- if (exposure[["scale"]] == "raw") "log" else "identity"
    found <- list()
    for (o in offsets) {
      if (o$key == exposure_key && o$transform != wanted) {
        add("E6057", o$at, list(column = o$value))
      }
    }
    first(found)
    if (!any(vapply(offsets, function(o) o$key == exposure_key && o$transform == wanted, NA))) {
      offsets[[length(offsets) + 1L]] <- list(key = exposure_key, value = exposure[["column"]],
                                              transform = wanted, at = NA_integer_)
    }
  }
  # Pass 8: size. The columns of the fixed part and of each random term,
  # counted before they are formed and before any term is split.
  fixed_coding <- part_coding(fixed$intercept, fixed$terms, predictors)
  if (part_size(fixed$intercept, fixed$terms, fixed_coding, predictors) > formula_limit) {
    raise_issue("E6075", list(part = "fixed part"))
  }
  random_coding <- lapply(random, function(term) {
    part_coding(term$intercept, term$terms, predictors)
  })
  for (k in seq_along(random)) {
    term <- random[[k]]
    if (part_size(term$intercept, term$terms, random_coding[[k]], predictors) > formula_limit) {
      name <- random_term_name(term$intercept, vapply(term$terms, term_name_of, ""),
                               term$factor_name)
      raise_issue("E6075", list(part = paste0("random term '", name, "'")))
    }
  }
  # The coding and columns of each part, with the terms of frozen factors
  # that '||' gives split into their columns.
  fixed_part <- part_columns(fixed$intercept, fixed$terms, predictors, fixed_coding)
  random_parts <- list()
  for (k in seq_along(random)) {
    term <- random[[k]]
    part <- part_columns(term$intercept, term$terms, predictors, random_coding[[k]])
    split <- term$double && !term$intercept && length(term$terms) == 1L &&
      length(part$columns) > 1L &&
      any(vapply(term$terms[[1L]], function(key) {
        isTRUE(named_member(predictors, key)$frozen)
      }, NA))
    if (split) {
      for (p in seq_along(part$columns)) {
        piece <- part
        piece$columns <- part$columns[p]
        piece$labels <- list(part$columns[[p]]$level_labels)
        piece$levels <- list(part$columns[[p]]$levels)
        random_parts[[length(random_parts) + 1L]] <- c(term[c("factor", "grouping",
                                                              "factor_name", "open")],
                                                       list(part = piece))
      }
    } else {
      random_parts[[length(random_parts) + 1L]] <- c(term[c("factor", "grouping",
                                                            "factor_name", "open")],
                                                     list(part = part))
    }
  }
  # Pass 9: columns of random terms (E6058), then names (E6059).
  found <- list()
  for (factor_key in unique(vapply(random_parts, function(term) term$factor, ""))) {
    members <- Filter(function(term) term$factor == factor_key, random_parts)
    seen <- character(0)
    for (term in members) {
      names_here <- vapply(term$part$columns, function(c) c$name, "")
      shared <- names_here[names_here %in% seen]
      if (length(shared)) {
        add("E6058", term$open, list(column = shared[1L], factor = term$factor_name))
      }
      seen <- c(seen, names_here)
    }
  }
  first(found)
  for (part in c(list(fixed_part), lapply(random_parts, function(term) term$part))) {
    names_here <- vapply(part$columns, function(c) c$name, "")
    if (anyDuplicated(names_here)) {
      raise_issue("E6059", list(name = names_here[duplicated(names_here)][1L]))
    }
  }
  # Pass 10: centring. The design sample uses the sample columns of the IR,
  # which leave out the columns that the IR reads, the response and the
  # trials column among them.
  read_keys <- unique(c(
    predictor_keys,
    unlist(lapply(random, function(term) term$grouping)),
    vapply(offsets, function(o) o$key, ""),
    if (!is.null(weights)) comparison_form(weights)
  ))
  read_all <- unique(c(read_keys, if (!is.null(response)) response$key,
                       if (!is.null(trials)) comparison_form(trials)))
  sample_keys <- sort_identifiers(setdiff(unique(comparison_form(sample_columns)), read_all))
  design <- NULL
  if (have_data) {
    design <- design_rows(table, unique(c(read_keys, sample_keys)))
  }
  for (key in predictor_keys) {
    info <- named_member(predictors, key)
    if (info$kind != "numeric") {
      next
    }
    if (info$centring == "value" && !is.finite(json_number_values(info$value_text))) {
      raise_issue("E6077", list(column = key))
    }
    if (info$centring != "mean" || !have_data) {
      next
    }
    if (!length(design)) {
      raise_issue("E6067", list(column = key))
    }
    values <- table$values[[info$j]][design]
    if (any(!is.finite(values))) {
      raise_issue("E6073", list(column = key))
    }
    total <- exact_sum(values)
    constant <- if (is.finite(total)) decimal_string(total / length(values), info$digits)
    if (is.null(constant) || !is.finite(json_number_values(constant))) {
      raise_issue("E6077", list(column = key))
    }
    info$constant <- constant
    named_member(predictors, key) <- info
  }
  list(
    response = response,
    declared = declared,
    predictors = predictors,
    fixed = fixed_part,
    random = random_parts,
    offsets = offsets,
    weights = if (!is.null(weights)) comparison_form(weights),
    sample_columns = sample_keys,
    have_data = have_data
  )
}

# The position of a reference level among the levels, compared by type and
# value and, for strings, after NFC, or NA.
level_position <- function(reference, levels) {
  sample_level <- levels[[1L]]
  if (is.character(sample_level)) {
    if (!is.character(reference)) {
      return(NA_integer_)
    }
    return(match(comparison_form(reference), unlist(levels)))
  }
  if (is.logical(sample_level)) {
    if (!is.logical(reference)) {
      return(NA_integer_)
    }
    return(match(reference, unlist(levels)))
  }
  if (!is.numeric(reference)) {
    return(NA_integer_)
  }
  match(as.double(reference), as.double(unlist(levels)))
}

# Pass 4 of the context (ir.md, Coding argument): the entries one at a time in
# code-point order of their keys.
check_coding <- function(coding, predictors) {
  members <- c("centring", "contrast", "frozen", "reference", "significant_digits", "value")
  categorical_members <- c("contrast", "frozen", "reference")
  for (k in order(coding$keys, method = "radix")) {
    key <- coding$keys[k]
    name <- coding$names[k]
    info <- named_member(predictors, key)
    if (is.null(info)) {
      raise_issue("E6061", list(column = name))
    }
    entry <- coding$entries[[k]]
    member_names <- names(entry)
    member_order <- member_names[order(member_names, method = "radix")]
    for (member in member_order) {
      if (!member %in% members || !coding_value_valid(member, entry[[member]])) {
        raise_issue("E6063", list(column = name, member = member))
      }
    }
    for (member in member_order) {
      categorical <- member %in% categorical_members
      if (categorical != (info$kind == "categorical")) {
        raise_issue("E6062", list(column = name, member = member))
      }
    }
    if (info$kind == "numeric") {
      centring <- entry[["centring"]] %||% "none"
      if (!is.null(entry[["significant_digits"]]) && centring != "mean") {
        raise_issue("E6063", list(column = name, member = "significant_digits"))
      }
      if (!is.null(entry[["value"]]) && centring != "value") {
        raise_issue("E6063", list(column = name, member = "value"))
      }
      if (centring == "value" && is.null(entry[["value"]])) {
        raise_issue("E6063", list(column = name, member = "centring"))
      }
    }
  }
  invisible()
}

# Whether a member of the coding argument has a valid value.
coding_value_valid <- function(member, value) {
  is_string <- is.character(value) && length(value) == 1L && !is.na(value) &&
    is.null(attr(value, "class"))
  is_whole <- is.numeric(value) && length(value) == 1L && !is.na(value) && is.finite(value) &&
    value == floor(value) && is.null(attr(value, "class"))
  is_flag <- is.logical(value) && length(value) == 1L && !is.na(value)
  switch(member,
    contrast = is_string && value %in% c("treatment", "sum", "simple"),
    centring = is_string && value %in% c("none", "mean", "value"),
    frozen = is_flag,
    reference = is_string || is_flag || (is_whole && abs(value) <= 9007199254740991),
    significant_digits = is_whole && value >= 1 && value <= 15,
    value = is_string && matches_definition(value, "decimal_string") &&
      significant_digit_count(value) <= 15L,
    FALSE
  )
}

# Whether each level can be written in the IR (ir.md, Kinds of columns): a
# string without control characters whose code points Unicode 14.0 assigns.
# Integers and booleans always can.
levels_writable <- function(levels) {
  vapply(levels, function(level) {
    if (!is.character(level)) {
      return(TRUE)
    }
    codepoints <- utf8ToInt(level)
    !any(codepoints <= 0x1FL | (codepoints >= 0x7FL & codepoints <= 0x9FL)) &&
      is_normalisable(level)
  }, NA)
}

# The number of columns of a part, counted from the coding of its terms
# without forming them: one for the intercept, and for each term the product
# of one for a numeric variable, k for a factor of k levels coded by
# indicators and k - 1 for one coded by its contrast.
part_size <- function(intercept, terms, coding, predictors) {
  size <- as.double(intercept)
  for (i in seq_along(terms)) {
    width <- 1
    for (v in seq_along(coding[[i]])) {
      k <- length(named_member(predictors, names(coding[[i]])[v])$levels)
      width <- width * if (coding[[i]][[v]] == "indicator") k else k - 1
    }
    size <- size + width
  }
  size
}

# The coding of each categorical variable in each term of a part (ir.md,
# Contrasts or indicators). terms holds the terms in term order, each with its
# variables in order.
part_coding <- function(intercept, terms, predictors) {
  coding <- lapply(terms, function(term) {
    out <- character(0)
    for (variable in term) {
      if (named_member(predictors, variable)$kind == "categorical") {
        named_member(out, variable) <- NA_character_
      }
    }
    out
  })
  for (i in seq_along(terms)) {
    term <- terms[[i]]
    for (v in seq_along(coding[[i]])) {
      variable <- names(coding[[i]])[v]
      info <- named_member(predictors, variable)
      others <- setdiff(term, variable)
      contrast <- info$frozen || !length(others) ||
        any(vapply(terms[seq_len(i - 1L)], function(earlier) all(others %in% earlier), NA))
      coding[[i]][[v]] <- if (contrast) "contrast" else "indicator"
    }
  }
  if (!intercept) {
    done <- FALSE
    for (i in seq_along(terms)) {
      for (variable in terms[[i]]) {
        info <- named_member(predictors, variable)
        if (info$kind == "categorical" && !info$frozen) {
          named_member(coding[[i]], variable) <- "indicator"
          done <- TRUE
          break
        }
      }
      if (done) {
        break
      }
    }
  }
  coding
}

# The columns of a part (ir.md, Columns of a term), from the coding of its
# terms.
part_columns <- function(intercept, terms, predictors,
                         coding = part_coding(intercept, terms, predictors)) {
  columns <- list()
  if (intercept) {
    columns[[1L]] <- list(name = "(Intercept)", term = 0L, levels = list(), level_labels = NULL)
  }
  for (i in seq_along(terms)) {
    term <- terms[[i]]
    pieces <- list(list(names = character(0), levels = list()))
    for (variable in term) {
      info <- named_member(predictors, variable)
      if (info$kind == "numeric") {
        options <- list(list(name = variable, level = NULL))
      } else {
        chosen <- seq_along(info$levels)
        if (named_member(coding[[i]], variable) == "contrast") {
          chosen <- chosen[chosen != info$reference]
        }
        options <- lapply(chosen, function(l) {
          list(name = paste0(variable, "[", level_label(info$levels[[l]]), "]"),
               level = info$levels[[l]])
        })
      }
      grown <- list()
      for (option in options) {
        for (piece in pieces) {
          levels <- piece$levels
          if (!is.null(option$level)) {
            named_member(levels, variable) <- option$level
          }
          grown[[length(grown) + 1L]] <- list(names = c(piece$names, option$name),
                                              levels = levels)
        }
      }
      pieces <- grown
    }
    for (piece in pieces) {
      labels <- vapply(term, function(variable) {
        level <- named_member(piece$levels, variable)
        if (is.null(level)) NA_character_ else level_label(level)
      }, "")
      columns[[length(columns) + 1L]] <- list(
        name = paste(piece$names, collapse = ":"),
        term = i - 1L + intercept,
        levels = piece$levels,
        level_labels = labels
      )
    }
  }
  list(intercept = intercept, terms = terms, coding = coding, columns = columns,
       labels = NULL, levels = NULL)
}

# --- The IR document ------------------------------------------------------------

# Assembles the IR document (ir.md, The IR document) as a named list.
ir_document <- function(model, context) {
  empty_object <- structure(list(), names = character(0))
  as_object <- function(x) if (length(x)) x else empty_object
  predictors <- lapply(context$predictors, function(info) {
    if (info$kind == "numeric") {
      centring <- list(rule = info$centring)
      if (info$centring == "mean") {
        centring$sample <- "design"
        if (context$have_data) {
          centring$constant <- list(significant_digits = as.double(info$digits),
                                    value = info$constant)
        } else {
          centring$significant_digits <- as.double(info$digits)
        }
      } else if (info$centring == "value") {
        centring$constant <- list(
          significant_digits = as.double(max(significant_digit_count(info$value_text), 1L)),
          value = info$value_text
        )
      }
      return(list(kind = "numeric", centring = centring))
    }
    entry <- list(kind = "categorical", levels = info$levels, levels_source = info$source,
                  contrast = info$contrast, reference = info$levels[[info$reference]])
    if (info$frozen) {
      entry$frozen <- TRUE
    }
    entry
  })
  part_document <- function(part) {
    term_entries <- list()
    if (part$intercept) {
      term_entries[[1L]] <- list(name = "(Intercept)", variables = list())
    }
    for (i in seq_along(part$terms)) {
      term <- part$terms[[i]]
      labels <- if (!is.null(part$labels)) part$labels[[1L]]
      variables <- lapply(seq_along(term), function(v) {
        variable <- term[[v]]
        entry <- list(variable = variable)
        coding <- part$coding[[i]]
        if (variable %in% names(coding)) {
          entry$coding <- named_member(coding, variable)
          if (!is.null(labels) && !is.na(labels[v])) {
            entry$level <- named_member(part$levels[[1L]], variable)
          }
        }
        entry
      })
      term_entries[[length(term_entries) + 1L]] <- list(
        name = term_name_of(term, labels),
        variables = variables
      )
    }
    column_entries <- lapply(part$columns, function(column) {
      list(name = column$name, term = as.double(column$term), levels = as_object(column$levels))
    })
    list(terms = term_entries, columns = column_entries)
  }
  random <- lapply(context$random, function(term) {
    document <- part_document(term$part)
    term_names <- vapply(document$terms, function(t) t$name, "")
    if (term$part$intercept) {
      term_names <- term_names[-1L]
    }
    c(
      list(name = random_term_name(term$part$intercept, term_names, term$factor_name),
           factor = term$factor_name,
           grouping = as.list(term$grouping),
           covariance = "unstructured"),
      document
    )
  })
  offsets <- context$offsets
  offset_order <- order(vapply(offsets, function(o) o$key, ""),
                        vapply(offsets, function(o) o$transform, ""), method = "radix")
  offsets <- lapply(offsets[offset_order], function(o) {
    list(variable = o$key, transform = o$transform)
  })
  ir <- list(ir_version = "0.1.0")
  response <- context$response
  if (!is.null(response)) {
    ir$response <- list(variable = response$key, transform = response$transform)
    declared <- context$declared
    if (!is.null(declared[["event_level"]])) {
      ir$response$event_level <- declared[["event_level"]]
    }
    if (!is.null(declared[["trials"]])) {
      ir$response$trials <- comparison_form(declared[["trials"]])
    }
  }
  ir$predictors <- as_object(predictors)
  ir$fixed <- part_document(context$fixed)
  ir$random <- random
  ir$offsets <- offsets
  if (!is.null(context$weights)) {
    ir$weights <- list(variable = context$weights)
  }
  if (length(context$sample_columns)) {
    ir$sample_columns <- as.list(context$sample_columns)
  }
  ir
}
