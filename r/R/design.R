# The design and analysis samples, the design matrices X and Z, the response,
# offset and weight vectors and the sequential rule for aliased columns
# (docs/spec/ir.md, Samples, Design matrices and Sequential rule) and the
# exact summation behind mean centring constants (ir.md, Centring).

#' Build the design matrices of an IR
#'
#' Builds, for the data, the design and analysis samples of an IR that
#' [formula_ir()] returned and the matrices and vectors of the model: the
#' fixed-effects matrix X, with the columns that the sequential rule drops
#' named separately, the random-effects matrix Z and the response, trials,
#' offset and weight vectors.
#'
#' The design sample holds the rows in which no column that the IR reads is
#' missing, other than the response and the trials column, and no sample
#' column of the IR is missing. The analysis sample holds the rows of the
#' design sample in which the response is present and, with a trials column,
#' the trials are present and either above 0 or not finite.
#' [design_samples()] gives the two samples alone. X and Z have one row for
#' each row of the design sample, in the order of the data. X has the
#' fixed-part columns of the IR, computed in double arithmetic in the order
#' the IR specification fixes, and the sequential rule drops each column
#' whose values are all 0 or whose residual after projection onto the columns
#' kept before it is at most 1e-7 times its norm, once the column is divided
#' by its largest absolute value. Z has, for each random term in IR order, one
#' column for each level of its grouping factor in the design sample and
#' each column of the term, the columns of one level together, with one
#' stored entry for each row and column of the term, zero or not.
#'
#' @param ir An IR, as [formula_ir()] returns it with the data. Its version
#'   and structure are checked, and a mean centring rule must hold its
#'   constant.
#' @param data A data frame with the columns that the IR reads, under the
#'   rules of [formula_ir()].
#' @return A list with these elements:
#'   * `design_sample` and `analysis_sample`: the rows of `data` in each
#'     sample, as integer row numbers counted from 1. The Python package
#'     counts them from 0.
#'   * `x`: a double matrix with one row for each row of the design sample
#'     and one column for each column of the fixed part, named as in the IR.
#'   * `x_columns`: the names of the columns of `x`, in order.
#'   * `x_dropped`: the names of the columns of `x` that the sequential rule
#'     drops, in column order.
#'   * `z`: a sparse [Matrix::dgCMatrix-class] with one row for each row of
#'     the design sample and the columns described by `z_columns`.
#'   * `z_columns`: a data frame with one row for each column of `z` and the
#'     columns `term`, the position of its random term in `ir$random`,
#'     counted from 1 (from 0 in Python), `level`, the label of its level,
#'     which for several grouping variables joins their labels by ':', with
#'     each '\\' and ':' in a label preceded by '\\', and `column`, the
#'     name of the column of the random term.
#'   * `response` and `trials`: double vectors with one value for each row
#'     of the analysis sample, or `NULL`. The response is the response
#'     itself, its natural logarithm for the transform 'log', 1 and 0 for
#'     `TRUE` and `FALSE`, or, with a declared event level, 1 where the value
#'     equals the event level and 0 otherwise. A response of strings without
#'     an event level has no response vector.
#'   * `offset` and `weights`: double vectors with one value for each row of
#'     the design sample, or `NULL` when the IR has no offsets or weights.
#'     The offset is the sum of the offsets in IR order, with the natural
#'     logarithm for the transform 'log'.
#' @section Errors: A problem is signalled as an error of class
#'   `mixedcheck_error` with one issue: E6073 for NaN or an infinity in a
#'   numeric column that the IR reads in a row of the design sample, other
#'   than the response and the trials column, checked by column in
#'   code-point order, then E6077 for the first column of X and then of Z
#'   with a value that is not finite, such as a product beyond the largest
#'   double, E6071 for the logarithm of a value that is not
#'   positive in an offset, in IR order, E6072 for a weight that is not
#'   positive, E6073 for NaN or an infinity in the response and then the
#'   trials column in a row of the analysis sample, E6078 for events or
#'   trials of a response with a trials column that are not integers with
#'   0 <= events <= trials and E6071 for a response written with log(). An
#'   IR that is not valid gives the codes of the schema area. Data that do
#'   not hold the columns or levels of the IR, and
#'   an IR whose columns or reference levels name a level that is not among
#'   the levels of their predictor, give an ordinary error.
#' @seealso [formula_ir()], [design_samples()].
#' @export
#' @examples
#' # Fixture Z19N of the pathology zoo (pathology_zoo()), in which 7 of the 60
#' # pupils have no baseline score and so lie outside the design sample.
#' fixture <- pathology_zoo("Z19N")
#' ir <- formula_ir(fixture$formula, fixture$declaration, fixture$data)
#' matrices <- design_matrices(ir, fixture$data)
#' head(matrices$x)
#' matrices$z_columns
#' dim(matrices$z)
design_matrices <- function(ir, data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  ir <- ir_input(ir)
  table <- model_table(data, NULL)
  model <- design_model(ir, table)
  built <- design_build(ir, model, table)
  vectors <- design_response(ir, model, table, model$analysis)
  list(
    design_sample = model$design,
    analysis_sample = model$analysis,
    x = built$x,
    x_columns = built$x_columns,
    x_dropped = built$x_columns[!built$kept],
    z = built$z,
    z_columns = built$z_columns,
    response = vectors$response,
    trials = vectors$trials,
    offset = built$offset,
    weights = built$weights
  )
}

# X, Z, the offset and the weights of the design sample of a model, with the
# columns that the sequential rule keeps, reporting E6073 for a column of the
# design sample, E6077, E6071 for an offset and E6072 in the order of ir.md
# (Errors). The response is not read, so that audit() can build them at T0.
design_build <- function(ir, model, table) {
  design <- model$design
  # E6073 in the design sample, by column in code-point order.
  checked <- unique(c(
    names(Filter(function(p) p$kind == "numeric", model$predictors)),
    unlist(lapply(model$random, function(term) {
      Filter(function(key) table$types[model$column(key)] == "number", term$grouping)
    })),
    vapply(model$offsets, function(o) o$variable, ""),
    model$weights
  ))
  for (key in sort_identifiers(checked)) {
    if (any(!is.finite(table$values[[model$column(key)]][design]))) {
      raise_issue("E6073", list(column = key))
    }
  }
  values <- design_variable_values(model, table, design)
  fixed_names <- vapply(ir$fixed$columns, function(column) column$name, "")
  # E6077 for the first column of X, then of Z, with a value that is not
  # finite. Each column is checked before it is written into X.
  x <- vapply(seq_along(ir$fixed$columns), function(k) {
    column <- design_column_values(ir$fixed$terms, ir$fixed$columns[[k]], values, length(design))
    if (any(!is.finite(column))) {
      raise_issue("E6077", list(column = fixed_names[k]))
    }
    column
  }, numeric(length(design)))
  dim(x) <- c(length(design), length(fixed_names))
  colnames(x) <- fixed_names
  z <- design_z(ir, model, table, design, values)
  kept <- sequential_rule(x)
  offset <- NULL
  for (o in model$offsets) {
    v <- table$values[[model$column(o$variable)]][design]
    if (o$transform == "log") {
      if (any(v <= 0)) {
        raise_issue("E6071", list(column = o$variable))
      }
      v <- log(v)
    }
    offset <- if (is.null(offset)) v else offset + v
  }
  weights <- NULL
  if (!is.null(model$weights)) {
    weights <- table$values[[model$column(model$weights)]][design]
    if (any(weights <= 0)) {
      raise_issue("E6072", list(column = model$weights))
    }
  }
  list(x = x, x_columns = fixed_names, kept = kept, z = z$matrix, z_columns = z$columns,
       offset = offset, weights = weights)
}

#' The design and analysis samples of an IR
#'
#' Determines, for the data, the design and analysis samples of an IR that
#' [formula_ir()] returned, without building the design matrices. The samples
#' are determined before X, Z and the vectors, so this function reports them
#' even when [design_matrices()] would signal E6071, E6072, E6073 or E6077
#' for the values of the rows.
#'
#' The design sample holds the rows in which no column that the IR reads is
#' missing, other than the response and the trials column, and no sample
#' column of the IR is missing. The analysis sample holds the rows of the
#' design sample in which the response is present and, with a trials column,
#' the trials are present and either above 0 or not finite.
#'
#' @inheritParams design_matrices
#' @return A list with the elements `design_sample` and `analysis_sample`:
#'   the rows of `data` in each sample, as integer row numbers counted from
#'   1. The Python package counts them from 0.
#' @section Errors: An IR that is not valid gives the codes of the schema
#'   area. Data that do not hold the columns or levels of the IR give an
#'   ordinary error.
#' @seealso [design_matrices()], which also builds the matrices.
#' @export
#' @examples
#' # Fixture Z19N of the pathology zoo (pathology_zoo()), in which 7 of the 60
#' # pupils have no baseline score.
#' fixture <- pathology_zoo("Z19N")
#' ir <- formula_ir(fixture$formula, fixture$declaration, fixture$data)
#' samples <- design_samples(ir, fixture$data)
#' lengths(samples)
#' fixture$data$pupil[-samples$design_sample]
#'
#' # A pupil without an outcome stays in the design sample and leaves the
#' # analysis sample.
#' data <- fixture$data
#' data$y[1] <- NA
#' lengths(design_samples(ir, data))
design_samples <- function(ir, data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  ir <- ir_input(ir)
  model <- design_model(ir, model_table(data, NULL))
  list(design_sample = model$design, analysis_sample = model$analysis)
}

# An IR passed in: written and read again in the hashable profile, so that it
# holds the values that the strict reader returns, then checked for its
# version (E1441) and against ir.schema.json. A mean centring rule without
# its constant cannot be applied.
ir_input <- function(ir) {
  value <- parse_json_bytes(canonical_bytes(mark_input_strings(ir), "hashable"), "hashable")
  version <- if (is_json_object(value)) value[["ir_version"]]
  if (is.character(version) && !version_supported(version, "^0\\.1\\.(0|[1-9][0-9]*)\\z")) {
    raise_issue("E1441", list(version = version, supported = "0.1.x"), pointer = "/ir_version")
  }
  raw <- schema_issues(value, "urn:mixedcheck:schema:ir")
  if (length(raw)) {
    signal_issues(finish_issues(raw))
  }
  for (i in seq_along(value$predictors)) {
    name <- names(value$predictors)[i]
    centring <- value$predictors[[i]]$centring
    if (identical(centring$rule, "mean") && is.null(centring$constant)) {
      stop(sprintf(paste0("The centring of '%s' has no constant. Build the IR with ",
                          "formula_ir() and the data first."), display_text(name)),
           call. = FALSE)
    }
  }
  value
}

# What the matrices need from an IR and the data: the column of each key,
# the predictors, the random terms, the offsets, the weights and the samples.
# The analysis sample, which reads the response, is left out when analysis is
# FALSE, as audit() leaves it out at T0.
design_model <- function(ir, table, analysis = TRUE) {
  column <- function(key) {
    j <- match(key, table$keys)
    if (is.na(j)) {
      stop(sprintf("The column '%s' that the IR reads is not in 'data'.", display_text(key)),
           call. = FALSE)
    }
    j
  }
  predictors <- ir$predictors
  for (i in seq_along(predictors)) {
    key <- names(predictors)[i]
    p <- predictors[[i]]
    j <- column(key)
    wanted <- if (p$kind == "numeric") "number" else if (is.character(p$levels[[1L]])) "string" else
      if (is.logical(p$levels[[1L]])) "boolean" else "number"
    if (table$types[j] != wanted && !all(table$missing[[j]])) {
      stop(sprintf("The column '%s' of 'data' does not hold the %s values that the IR reads.",
                   display_text(key), wanted), call. = FALSE)
    }
  }
  random <- lapply(ir$random, function(term) {
    term$grouping <- unlist(term$grouping)
    term
  })
  offsets <- ir$offsets
  weights <- ir$weights$variable
  sample_columns <- unlist(ir$sample_columns)
  read <- unique(c(names(predictors), unlist(lapply(random, function(term) term$grouping)),
                   vapply(offsets, function(o) o$variable, ""), weights, sample_columns))
  for (key in c(read, ir$response$variable, ir$response$trials)) {
    column(key)
  }
  for (key in c(vapply(offsets, function(o) o$variable, ""), weights, ir$response$trials)) {
    if (table$types[column(key)] != "number") {
      stop(sprintf("The column '%s' of 'data' does not hold numbers.", display_text(key)),
           call. = FALSE)
    }
  }
  design <- design_rows(table, read)
  list(column = column, predictors = predictors, random = random, offsets = offsets,
       weights = weights, design = design,
       analysis = if (analysis) analysis_rows(ir, table, design, column))
}

# The analysis sample (ir.md, Samples): the rows of the design sample whose
# response, and trials column if any, are present, with trials above 0 or not
# finite.
analysis_rows <- function(ir, table, design, column) {
  analysis <- design
  if (!is.null(ir$response)) {
    j <- column(ir$response$variable)
    analysis <- analysis[!table$missing[[j]][analysis]]
    if (!is.null(ir$response$trials)) {
      t <- column(ir$response$trials)
      trials <- table$values[[t]][analysis]
      analysis <- analysis[!table$missing[[t]][analysis] & !(is.finite(trials) & trials <= 0)]
    }
  }
  analysis
}

# The rows of the table, counted from 1, in which no column of the given keys
# is missing.
design_rows <- function(table, keys) {
  present <- rep(TRUE, table$rows)
  for (key in keys) {
    present <- present & !table$missing[[match(key, table$keys)]]
  }
  which(present)
}

# The values of each predictor in the rows of a sample: a numeric predictor
# centred by its rule and, for a categorical predictor, the position of each
# row's level among its levels. A value outside the levels is refused.
design_variable_values <- function(model, table, rows) {
  keys <- names(model$predictors)
  values <- lapply(seq_along(keys), function(i) {
    key <- keys[i]
    p <- model$predictors[[i]]
    v <- table$values[[model$column(key)]][rows]
    if (p$kind == "numeric") {
      rule <- p$centring$rule
      if (rule != "none") {
        v <- v - json_number_values(p$centring$constant$value)
      }
      return(v)
    }
    levels <- unlist(p$levels)
    position <- if (is.character(levels)) match(comparison_form(v), levels) else match(v, levels)
    if (anyNA(position)) {
      stop(sprintf("The column '%s' of 'data' holds a value that is not one of its levels in the IR.",
                   display_text(key)), call. = FALSE)
    }
    position
  })
  names(values) <- keys
  attr(values, "predictors") <- model$predictors
  values
}

# The values of one column of a part (ir.md, X): 1 for '(Intercept)', and
# otherwise the product of the values of the term's variables, multiplied
# from the left in double arithmetic.
design_column_values <- function(terms, column, values, rows) {
  term <- terms[[column$term + 1L]]
  if (!length(term$variables)) {
    return(rep(1, rows))
  }
  result <- NULL
  for (variable in term$variables) {
    key <- variable$variable
    v <- named_member(values, key)
    if (!is.null(variable$coding)) {
      level <- named_member(column$levels, key)
      if (is.null(level)) {
        stop(sprintf("The column '%s' of the IR gives no level of '%s'.",
                     display_text(column$name), display_text(key)), call. = FALSE)
      }
      v <- level_values(v, variable$coding, level, named_member(attr(values, "predictors"), key))
    }
    result <- if (is.null(result)) v else result * v
  }
  result
}

# The position of a level of the IR among the levels of its predictor. The
# schema of the IR does not tie a column's level or a reference to the
# levels, so a level outside them is refused here.
level_index <- function(level, levels) {
  l <- if (is.character(levels) == is.character(level) &&
             is.logical(levels) == is.logical(level)) match(level, levels) else NA_integer_
  if (is.na(l)) {
    stop(sprintf("The level '%s' is not one of the levels in the IR.",
                 display_text(level_label(level))), call. = FALSE)
  }
  l
}

# The values that a categorical variable takes in the column of one level,
# for rows whose levels are at the positions given: its contrast (ir.md,
# Contrasts) or its indicator.
level_values <- function(position, coding, level, predictor) {
  levels <- unlist(predictor$levels)
  l <- level_index(level, levels)
  if (coding == "indicator") {
    return(as.double(position == l))
  }
  k <- length(levels)
  switch(predictor$contrast,
    treatment = as.double(position == l),
    sum = {
      r <- level_index(predictor$reference, levels)
      ifelse(position == l, 1, ifelse(position == r, -1, 0))
    },
    simple = {
      inverse <- 1 / k
      ifelse(position == l, (k - 1) / k, -inverse)
    }
  )
}

# Z (ir.md, Z): for each random term in IR order, J x q columns, ordered by
# level and, within a level, by the term's columns. Returns the matrix and
# the description of its columns.
design_z <- function(ir, model, table, rows, values) {
  n <- length(rows)
  i_all <- list()
  j_all <- list()
  x_all <- list()
  described <- list()
  start <- 0L
  for (t in seq_along(model$random)) {
    term <- model$random[[t]]
    grouping <- grouping_levels(table, term$grouping, rows, model$column)
    q <- length(term$columns)
    for (c in seq_len(q)) {
      v <- design_column_values(term$terms, term$columns[[c]], values, n)
      if (any(!is.finite(v))) {
        raise_issue("E6077", list(column = term$columns[[c]]$name))
      }
      i_all[[length(i_all) + 1L]] <- seq_len(n)
      j_all[[length(j_all) + 1L]] <- start + (grouping$code - 1L) * q + c
      x_all[[length(x_all) + 1L]] <- v
    }
    labels <- grouping$labels
    described[[t]] <- data.frame(
      term = rep(t, length(labels) * q),
      level = rep(labels, each = q),
      column = rep(vapply(term$columns, function(column) column$name, ""), length(labels)),
      stringsAsFactors = FALSE
    )
    start <- start + length(labels) * q
  }
  columns <- if (length(described)) do.call(rbind, described) else
    data.frame(term = integer(0), level = character(0), column = character(0),
               stringsAsFactors = FALSE)
  columns$term <- as.integer(columns$term)
  rownames(columns) <- NULL
  # The dgCMatrix is built from its slots, so that every entry is stored,
  # zero or not, whatever Matrix version is installed: the entries sorted by
  # column, with the rows of each column in increasing order, which a stable
  # sort by column keeps, since each column takes its entries from one
  # column of a term in row order.
  i <- unlist(i_all, use.names = FALSE) %||% integer(0)
  j <- unlist(j_all, use.names = FALSE) %||% integer(0)
  order_by_column <- order(j, method = "radix")
  matrix <- methods::new(
    "dgCMatrix",
    i = i[order_by_column] - 1L,
    p = c(0L, cumsum(tabulate(j, nbins = start))),
    x = (unlist(x_all, use.names = FALSE) %||% numeric(0))[order_by_column],
    Dim = c(n, start),
    Dimnames = list(NULL, NULL)
  )
  list(matrix = matrix, columns = columns)
}

# The levels of a grouping factor in the rows of a sample (ir.md, Z): the
# distinct combinations of the values of its variables, ordered by the first
# variable, then the second, numbers by value, strings by code point after
# NFC and false before true. Returns the position of each row's level among
# the levels and the label of each level: the label of its one variable, or
# the labels of its variables joined by ':', each with a backslash and ':'
# escaped by a backslash.
grouping_levels <- function(table, keys, rows, column) {
  ranks <- list()
  labels <- list()
  for (key in keys) {
    j <- column(key)
    v <- table$values[[j]][rows]
    if (table$types[j] == "string") {
      v <- comparison_form(v)
      distinct <- sort_identifiers(unique(v))
      text <- distinct
    } else if (table$types[j] == "boolean") {
      distinct <- c(FALSE, TRUE)[c(FALSE, TRUE) %in% v]
      text <- ifelse(distinct, "true", "false")
    } else {
      distinct <- sort(unique(v + 0))
      text <- if (length(distinct)) format_number(distinct) else character(0)
    }
    if (length(keys) > 1L) {
      text <- gsub(":", "\\:", gsub("\\", "\\\\", text, fixed = TRUE), fixed = TRUE)
    }
    ranks[[length(ranks) + 1L]] <- match(if (is.numeric(v)) v + 0 else v, distinct)
    labels[[length(labels) + 1L]] <- text
  }
  combined <- rep(1, length(rows))
  for (r in ranks) {
    combined <- match(combined * (length(rows) + 1) + r, unique(combined * (length(rows) + 1) + r))
  }
  first <- match(seq_len(max(c(combined, 0L))), combined)
  level_ranks <- lapply(ranks, function(r) r[first])
  ordering <- if (length(first)) do.call(order, c(level_ranks, list(method = "radix"))) else integer(0)
  code <- match(combined, ordering)
  level_text <- vapply(ordering, function(level) {
    paste(vapply(seq_along(ranks), function(v) labels[[v]][level_ranks[[v]][level]], ""),
          collapse = ":")
  }, "")
  list(code = code, labels = level_text)
}

# The response and trials vectors of the analysis sample (ir.md, Response,
# offsets and weights).
design_response <- function(ir, model, table, analysis) {
  response <- ir$response
  if (is.null(response)) {
    return(list(response = NULL, trials = NULL))
  }
  j <- model$column(response$variable)
  v <- table$values[[j]][analysis]
  trials <- NULL
  if (table$types[j] == "number" && any(!is.finite(v))) {
    raise_issue("E6073", list(column = response$variable))
  }
  if (!is.null(response$trials)) {
    trials <- table$values[[model$column(response$trials)]][analysis]
    if (any(!is.finite(trials))) {
      raise_issue("E6073", list(column = response$trials))
    }
    # E6078: the events and trials of every row must be integers with
    # 0 <= events <= trials. Events that are not numbers fail in the first row.
    counts <- !length(v) || (table$types[j] == "number" &&
                               all(v == floor(v) & trials == floor(trials) & v >= 0 & v <= trials))
    if (!counts) {
      raise_issue("E6078", list(column = response$variable))
    }
  }
  if (!is.null(response$event_level)) {
    event <- response$event_level
    hit <- if (is.character(event)) {
      table$types[j] == "string" & comparison_form(v) == comparison_form(event)
    } else {
      table$types[j] == "number" & v == event
    }
    return(list(response = as.double(hit), trials = trials))
  }
  if (table$types[j] == "boolean") {
    return(list(response = as.double(v), trials = trials))
  }
  if (table$types[j] == "string") {
    return(list(response = NULL, trials = trials))
  }
  if (response$transform == "log") {
    if (any(v <= 0)) {
      raise_issue("E6071", list(column = response$variable))
    }
    v <- log(v)
  }
  list(response = v, trials = trials)
}

# --- The sequential rule ----------------------------------------------------------

# The tolerance tau of the sequential rule (ir.md, Sequential rule).
sequential_tolerance <- 1e-7

# The sequential rule for aliased columns (ir.md, Sequential rule): each
# column in turn is dropped when its values are all 0. Otherwise it is divided
# by its largest absolute value, so that its squares neither overflow nor
# underflow, and dropped when the norm of its residual after orthogonal
# projection onto the columns kept so far is at most tolerance times its
# norm. The steps, which sequential_rule() in the Python package follows one
# by one:
#
# 1. One pass over the columns finds the largest absolute value of each and
#    divides the column by it, which gives the scaled columns V of the
#    columns that are not all 0.
# 2. When there are more than twice as many rows as columns in V, V is
#    replaced by Q'V, its coordinates in the orthonormal factor Q of the
#    Householder QR with column pivoting of LAPACK's DGEQP3, which
#    qr(LAPACK = TRUE) calls: the triangular factor R, with its columns put
#    back in the order of V. Q'V keeps every norm and inner product up to an
#    error near the rounding error of the column, and the next step then
#    works on as many rows as there are columns.
# 3. Each column of V in turn is projected out of an orthonormal basis of
#    the columns kept so far with two passes of Gram-Schmidt, and when its
#    residual is kept, the residual divided by its norm joins the basis.
#    Norms and inner products are computed with crossprod() and %*%, which
#    call BLAS, as numpy.dot() and @ do in Python.
#
# The two packages call the same LAPACK routine and BLAS operations on the
# same values, so that they differ only in the rounding of their BLAS and
# LAPACK. Returns whether each column is kept.
sequential_rule <- function(x, tolerance = sequential_tolerance, norms = NULL) {
  sequential_residuals(x, tolerance, norms)$kept
}

# The sequential rule with the norms it computes: kept, whether each column
# is kept, and residual, the norm of the residual of each scaled column after
# projection onto the columns kept before it, 0 for a column whose values are
# all 0. design.collinearity takes the residuals of its columns from here, so
# that they are computed as the rule computes them. With norms, a column is
# kept when the norm of its residual, in the units of x, exceeds tolerance
# times its element of norms instead of tolerance times the norm of the
# column (within_level_rank()).
sequential_residuals <- function(x, tolerance = sequential_tolerance, norms = NULL) {
  n <- nrow(x)
  p <- ncol(x)
  kept <- logical(p)
  residual <- numeric(p)
  if (!n || !p) {
    return(list(kept = kept, residual = residual))
  }
  largest <- numeric(p)
  v <- vapply(seq_len(p), function(j) {
    column <- x[, j]
    largest[j] <<- max(abs(column))
    if (largest[j] > 0) column / largest[j] else column
  }, numeric(n))
  dim(v) <- c(n, p)
  candidates <- which(largest > 0)
  if (!length(candidates)) {
    return(list(kept = kept, residual = residual))
  }
  if (length(candidates) < p) {
    v <- v[, candidates, drop = FALSE]
  }
  if (n > 2L * length(candidates)) {
    decomposition <- qr(v, LAPACK = TRUE)
    v <- qr.R(decomposition)[, order(decomposition$pivot), drop = FALSE]
    rm(decomposition)
  }
  basis <- matrix(0, nrow(v), 0L)
  for (k in seq_along(candidates)) {
    r <- v[, k]
    norm_v <- sqrt(drop(crossprod(r)))
    if (ncol(basis)) {
      for (pass in 1:2) {
        r <- r - drop(basis %*% crossprod(basis, r))
      }
    }
    norm_r <- sqrt(drop(crossprod(r)))
    residual[candidates[k]] <- norm_r
    if (!is.null(norms)) {
      norm_v <- norms[candidates[k]] / largest[candidates[k]]
    }
    if (norm_r > tolerance * norm_v) {
      kept[candidates[k]] <- TRUE
      basis <- cbind(basis, r / norm_r)
    }
  }
  list(kept = kept, residual = residual)
}

# --- Exact summation --------------------------------------------------------------

# The sum of finite doubles, computed exactly and rounded once to the nearest
# double, ties to even, as Python's math.fsum() returns it (ir.md,
# Centring). Each double is m * 2^e with an integer m below 2^53, and its
# exact value is split into three limbs of 32 bits at the position of e,
# counted from 2^-1074. The limbs of all values are summed exactly in double
# arithmetic in chunks small enough that no sum reaches 2^53 and carried, and the
# difference of the positive and negative sums is rounded to 53 bits.
exact_sum <- function(x) {
  x <- x[x != 0]
  if (!length(x)) {
    return(0)
  }
  parts <- double_parts(x)
  limb_count <- 72L
  total <- list(positive = numeric(limb_count), negative = numeric(limb_count))
  # A limb receives at most three amounts below 2^32 from each value, so a
  # chunk of 2^19 values keeps its sums below 2^53.
  chunk <- 2^19
  for (sign in c("positive", "negative")) {
    chosen <- if (sign == "positive") !parts$negative else parts$negative
    m <- parts$m[chosen]
    e <- parts$e[chosen]
    if (!length(m)) {
      next
    }
    for (first in seq.int(1, length(m), by = chunk)) {
      at <- first:min(length(m), first + chunk - 1)
      total[[sign]] <- limbs_normalise(total[[sign]] + exact_limbs(m[at], e[at], limb_count))
    }
  }
  positive <- total$positive
  negative <- total$negative
  top <- which(positive != negative)
  if (!length(top)) {
    return(0)
  }
  top <- max(top)
  negative_result <- negative[top] > positive[top]
  difference <- if (negative_result) limbs_subtract(negative, positive) else
    limbs_subtract(positive, negative)
  value <- limbs_round(difference)
  if (negative_result) -value else value
}

# The exact sum of the finite doubles of each group, rounded once to the
# nearest double, ties to even, as exact_sum() rounds the sum of one vector.
# groups gives the group of each value, from 1 to count, and a group without
# values sums to 0. The limbs of every group are summed and carried together,
# so that the time grows with the values and not with the groups times the
# values.
exact_group_sums <- function(x, groups, count) {
  nonzero <- x != 0
  x <- x[nonzero]
  groups <- groups[nonzero]
  result <- numeric(count)
  # The sum of a single value is the value, so only the groups with two or
  # more values take limbs, and a factor with one level per row costs no
  # more than the values.
  sizes <- tabulate(groups, nbins = count)
  single <- sizes[groups] == 1L
  result[groups[single]] <- x[single]
  several <- which(sizes >= 2L)
  if (length(several)) {
    result[several] <- exact_sums_of_groups(x[!single], match(groups[!single], several),
                                            length(several))
  }
  result
}

# exact_group_sums() for groups that each hold at least one value. Each value
# m * 2^e adds amounts below 2^33 to the limbs l, l + 1 and l + 2 of base
# 2^32 at its position l, counted from 2^-1074, and a group keeps only the
# cells from l - 1 to l + 3 of each l among its values, so that memory grows
# with the values. Without the cells l + 3 a carry would have no cell to go
# to, and without the cells l - 1 the highest limb that is not 0 after a
# borrow could fall between cells. Between two cells, a carry or a borrow
# passes on unchanged.
exact_sums_of_groups <- function(x, groups, count) {
  base <- 2^32
  # The cells of a group lie at positions 0 to 66 and take the keys from
  # (group - 1) * 72 on.
  stride <- 72
  parts <- double_parts(x)
  position <- parts$e + 1074
  limb <- position %/% 32
  shift <- 2^(position %% 32)
  high <- floor(parts$m / base)
  low <- parts$m - high * base
  low_shifted <- low * shift
  low_carry <- floor(low_shifted / base)
  high_shifted <- high * shift
  high_carry <- floor(high_shifted / base)
  amounts <- list(low_shifted - low_carry * base, low_carry + high_shifted - high_carry * base,
                  high_carry)
  first <- (groups - 1) * stride + limb
  rm(position, limb, shift, high, low, low_shifted, low_carry, high_shifted, high_carry)
  # The cells, in ascending order of key, from the sorted keys of the l of
  # each group: each start s adds the keys from s - 1, or from the key after
  # the cells of the start below it, up to s + 3.
  starts <- sort(unique(first))
  from <- pmax(starts - (starts %% stride > 0), c(-1, starts[-length(starts)] + 4))
  size <- as.integer(starts + 4 - from)
  cells <- rep(from, size) + sequence(size) - 1
  cell_count <- length(cells)
  cell_group <- as.integer(cells %/% stride) + 1L
  cell_position <- as.integer(cells - (cell_group - 1L) * stride)
  previous <- c(FALSE, cell_group[-1L] == cell_group[-cell_count])
  by_position <- split(seq_len(cell_count), cell_position)
  start_cell <- cumsum(size) - size + as.integer(starts - from) + 1L
  rm(from, size)
  # The amounts of each cell, positive and negative apart, summed in parts
  # of 17 and 16 bits, whose running sums over all values stay below 2^53.
  slot <- start_cell[match(first, starts)] + parts$negative * cell_count
  rm(first, starts, start_cell, parts)
  order_of <- order(slot)
  slot <- slot[order_of]
  last <- c(slot[-1L] != slot[-length(slot)], TRUE)
  slot <- slot[last]
  sum_upper <- numeric(2 * cell_count)
  sum_lower <- numeric(2 * cell_count)
  for (k in 0:2) {
    amount <- amounts[[k + 1L]][order_of]
    upper <- floor(amount / 2^16)
    lower <- cumsum(amount - upper * 2^16)[last]
    upper <- cumsum(upper)[last]
    at <- slot + k
    sum_upper[at] <- sum_upper[at] + upper - c(0, upper[-length(upper)])
    sum_lower[at] <- sum_lower[at] + lower - c(0, lower[-length(lower)])
  }
  rm(amounts, amount, upper, lower, at, order_of, slot, last)
  totals <- lapply(0:1, function(negative) {
    at <- negative * cell_count + seq_len(cell_count)
    # sum_upper * 2^16 + sum_lower as a limb below 2^32 and a carry.
    carried <- floor(sum_upper[at] / 2^16)
    rest <- (sum_upper[at] - carried * 2^16) * 2^16 + sum_lower[at]
    over <- floor(rest / base)
    limbs_carry_cells(rest - over * base, carried + over, by_position, previous)$limb
  })
  rm(sum_upper, sum_lower)
  difference <- totals[[1L]] - totals[[2L]]
  rm(totals)
  result <- numeric(count)
  nonzero <- which(difference != 0)
  if (!length(nonzero)) {
    return(result)
  }
  # The sign of each sum is the sign of its highest limb that differs. The
  # cells are in ascending order of group and position.
  ends <- function(cell) {
    group <- cell_group[cell]
    change <- group[-1L] != group[-length(group)]
    list(first = cell[c(TRUE, change)], last = cell[c(change, TRUE)])
  }
  bounds <- ends(nonzero)
  highest <- bounds$last
  lowest <- bounds$first
  sign <- numeric(count)
  sign[cell_group[highest]] <- sign(difference[highest])
  borrowed <- limbs_carry_cells(difference * sign[cell_group], numeric(cell_count),
                                by_position, previous)
  limbs <- borrowed$limb
  carry <- borrowed$carry
  rm(difference, borrowed)
  # The highest limb that is not 0 lies in a cell, and the limb below a cell
  # that is not one lies in a gap, all 1s after a borrow and 0 otherwise.
  top <- ends(which(limbs > 0))$last
  group <- cell_group[top]
  t <- cell_position[top]
  limb_below <- function(down) {
    out <- numeric(length(top))
    at <- t >= down
    key_below <- cells[top[at]] - down
    j <- findInterval(key_below, cells)
    same <- j > 0L
    same[same] <- cell_group[j[same]] == group[at][same]
    exact <- same & cells[pmax(j, 1L)] == key_below
    value <- numeric(length(j))
    value[exact] <- limbs[j[exact]]
    gap <- same & !exact
    value[gap] <- ifelse(carry[j[gap]] < 0, base - 1, 0)
    out[at] <- value
    out
  }
  high <- limbs[top]
  middle <- limb_below(1L)
  low <- limb_below(2L)
  # Whether a limb below the three highest is not 0, which holds exactly when
  # a difference below them is not 0.
  below <- cell_position[lowest] < t - 2
  # Sums below 2^64 times 2^-1074, which no data reach in practice, are
  # rounded one by one, since they can be subnormal.
  small <- which(t < 2)
  for (i in small) {
    result[group[i]] <- sign[group[i]] *
      limbs_round(if (t[i] == 1) c(middle[i], high[i]) else high[i])
  }
  wide <- which(t >= 2)
  if (length(wide)) {
    high <- high[wide]
    middle <- middle[wide]
    low <- low[wide]
    sticky <- below[wide]
    # The bit length b of the highest limb, and the s = 53 - b bits taken
    # from the limbs below it.
    b <- floor(log2(high)) + 1
    b[2^(b - 1) > high] <- b[2^(b - 1) > high] - 1
    b[2^b <= high] <- b[2^b <= high] + 1
    s <- 53 - b
    mantissa <- numeric(length(wide))
    round_bit <- logical(length(wide))
    one <- s < 32
    if (any(one)) {
      unit <- 2^(32 - s[one])
      taken <- floor(middle[one] / unit)
      rest <- middle[one] - taken * unit
      half <- unit / 2
      mantissa[one] <- high[one] * 2^s[one] + taken
      round_bit[one] <- rest >= half
      sticky[one] <- sticky[one] | rest - round_bit[one] * half > 0 | low[one] > 0
    }
    two <- s == 32
    if (any(two)) {
      mantissa[two] <- high[two] * 2^32 + middle[two]
      round_bit[two] <- low[two] >= 2^31
      sticky[two] <- sticky[two] | low[two] - round_bit[two] * 2^31 > 0
    }
    three <- s > 32
    if (any(three)) {
      unit <- 2^(64 - s[three])
      taken <- floor(low[three] / unit)
      rest <- low[three] - taken * unit
      half <- unit / 2
      mantissa[three] <- high[three] * 2^s[three] + middle[three] * 2^(s[three] - 32) + taken
      round_bit[three] <- rest >= half
      sticky[three] <- sticky[three] | rest - round_bit[three] * half > 0
    }
    up <- round_bit & (sticky | mantissa %% 2 == 1)
    mantissa[up] <- mantissa[up] + 1
    g <- group[wide]
    result[g] <- sign[g] * mantissa * 2^(32 * t[wide] + b - 53 - 1074)
  }
  result
}

# Carries the cells of exact_sums_of_groups() from the lowest position up:
# value + carry is split into a limb in [0, 2^32) and a carry into the next
# cell of its group, which adds to carry_out. A carry passes unchanged over
# the positions between two cells. Returns the limbs and the carry out of
# each cell.
limbs_carry_cells <- function(value, carry_out, by_position, previous) {
  base <- 2^32
  limb <- value
  carry <- numeric(length(value))
  for (at in by_position) {
    incoming <- numeric(length(at))
    from <- previous[at]
    incoming[from] <- carry[at[from] - 1L]
    total <- value[at] + incoming
    over <- floor(total / base)
    limb[at] <- total - over * base
    carry[at] <- carry_out[at] + over
  }
  list(limb = limb, carry = carry)
}

# The limbs of base 2^32 of the sum of m * 2^e, before carrying.
exact_limbs <- function(m, e, limb_count) {
  base <- 2^32
  position <- e + 1074
  limb <- position %/% 32
  shift <- 2^(position %% 32)
  high <- floor(m / base)
  low <- m - high * base
  low_shifted <- low * shift
  low_carry <- floor(low_shifted / base)
  high_shifted <- high * shift
  high_carry <- floor(high_shifted / base)
  index <- c(limb, limb + 1, limb + 1, limb + 2) + 1
  amount <- c(low_shifted - low_carry * base, low_carry, high_shifted - high_carry * base,
              high_carry)
  sums <- rowsum(amount, index, reorder = TRUE)
  out <- numeric(limb_count)
  out[as.integer(rownames(sums))] <- sums[, 1L]
  out
}

# Carries limbs of base 2^32 so that each lies in [0, 2^32).
limbs_normalise <- function(limbs) {
  base <- 2^32
  carry <- 0
  for (k in seq_along(limbs)) {
    value <- limbs[k] + carry
    carry <- floor(value / base)
    limbs[k] <- value - carry * base
  }
  limbs
}

# a - b for normalised limbs with a > b.
limbs_subtract <- function(a, b) {
  base <- 2^32
  borrow <- 0
  for (k in seq_along(a)) {
    value <- a[k] - b[k] - borrow
    borrow <- if (value < 0) 1 else 0
    a[k] <- value + borrow * base
  }
  a
}

# The double nearest to the positive integer in normalised limbs times
# 2^-1074, ties to even.
limbs_round <- function(limbs) {
  bits <- unlist(lapply(limbs, function(limb) {
    high <- floor(limb / 65536)
    c(as.integer(intToBits(as.integer(limb - high * 65536)))[1:16],
      as.integer(intToBits(as.integer(high)))[1:16])
  }), use.names = FALSE)
  top <- max(which(bits == 1L))
  if (top <= 53L) {
    return(sum(bits[seq_len(top)] * 2^(seq_len(top) - 1L)) * 2^-1074)
  }
  low <- top - 52L
  mantissa <- sum(bits[low:top] * 2^(0:52))
  round_bit <- bits[low - 1L]
  sticky <- low > 2L && any(bits[seq_len(low - 2L)] == 1L)
  if (round_bit == 1L && (sticky || mantissa %% 2 == 1)) {
    mantissa <- mantissa + 1
  }
  mantissa * 2^(low - 1L - 1074)
}
