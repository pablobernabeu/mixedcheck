# The check of the prefix sample (spec/registry/checks/sample.raw_vs_analysis.yaml).

# sample.raw_vs_analysis: the rows of the table that leave the design sample,
# the columns whose missing values remove them, and the factors and grouping
# factors whose levels the design sample loses or leaves with one row.
audit_check_sample_raw_vs_analysis <- function(run, entry, elements) {
  ir <- run$ir
  design <- run$design
  table_rows <- seq_len(run$table$rows)
  in_design <- table_rows %in% design
  # The columns that the IR reads, other than the response and its trials
  # column, and its sample columns, as the design sample reads them.
  read <- unique(c(
    names(ir$predictors),
    run$grouping_columns,
    vapply(ir$offsets, function(o) o$variable, ""),
    ir$weights$variable,
    unlist(ir$sample_columns)
  ))
  incomplete <- read[vapply(read, function(key) anyNA(column_codes(run, key)), NA)]
  categorical <- Filter(function(p) p$kind == "categorical", ir$predictors)
  keys <- sort_identifiers(names(categorical))
  emptied <- keys[vapply(keys, function(key) {
    codes <- column_codes(run, key)
    !all(unique(codes[!is.na(codes)]) %in% codes[in_design])
  }, NA)]
  contrasts <- unique(unlist(lapply(c(list(ir$fixed), ir$random), function(part) {
    lapply(part$terms, function(term) {
      vapply(Filter(function(v) identical(v$coding, "contrast"), term$variables),
             function(v) v$variable, "")
    })
  })))
  reference_emptied <- keys[vapply(keys, function(key) {
    key %in% contrasts && !any(reference_rows(run, key, categorical[[key]]$reference)[design])
  }, NA)]
  factors <- names(run$factors)
  losing <- factors[vapply(factors, function(factor) {
    codes <- value_codes(run, run$factors[[factor]])
    !all(unique(codes[!is.na(codes)]) %in% codes[in_design])
  }, NA)]
  singletons <- factors[vapply(factors, function(factor) {
    codes <- value_codes(run, run$factors[[factor]])
    in_table <- tabulate(codes)
    in_sample <- tabulate(codes[in_design], nbins = length(in_table))
    any(in_sample == 1L & in_table > 1L)
  }, NA)]
  rows_raw <- run$table$rows
  rows_kept <- length(design)
  statistics <- list(
    rows_raw = rows_raw,
    rows_kept = rows_kept,
    rows_dropped = rows_raw - rows_kept,
    incomplete_columns = sort_identifiers(incomplete),
    emptied_factors = emptied,
    reference_emptied = reference_emptied,
    factors_losing_levels = losing,
    new_singletons = singletons
  )
  list(check_element(statistics, rules = c(
    length(reference_emptied) > 0L,
    rows_raw - rows_kept > 0L
  )))
}

# Whether each row of the table holds the reference level of a categorical
# predictor, compared by value: a string after NFC, a number by value and a
# boolean by value.
reference_rows <- function(run, key, reference) {
  j <- column_index(run, key)
  values <- run$table$values[[j]]
  if (is.character(values)) {
    values <- comparison_form(values)
  }
  hit <- if (is.character(values) == is.character(reference) &&
               is.logical(values) == is.logical(reference)) values == reference else FALSE
  !run$table$missing[[j]] & hit %in% TRUE
}
