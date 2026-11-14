# The validation attacks (sim/disclosure/README.md): shareable documents that
# give back a hidden value, made by changing a document of the filter as an
# implementation that broke a rule would write it, which stages 4 and 5 of
# validate_results() must refuse (documents.md, Shareable documents). Each
# attack names the rule of validation that should refuse it. A document that
# the validator accepts is a leak of the validator, since a shareable
# document that passes validation is taken to meet the invariants.

va_attacks <- function() {
  list(
    list(id = "V-E7020", rule = "E7020", forge = va_person_count_below_k),
    list(id = "V-E7021", rule = "E7021", forge = va_real_of_small_finding),
    list(id = "V-E7022", rule = "E7022", forge = va_minimum_written),
    list(id = "V-E7024", rule = "E7024", forge = va_ratio_of_hidden_count),
    list(id = "V-E7025", rule = "E7025", forge = va_quantile_n_beside_hidden_count),
    list(id = "V-E7045", rule = "E7045", forge = va_quantile_member_dropped),
    list(id = "V-E7046", rule = "E7046", forge = va_lower_min_count)
  )
}

# Runs every validation attack at the registry's k. Returns a data frame
# with one row for each: the attack, the rule that should refuse its
# document, whether the validator accepted it (a leak) and the codes it
# reported.
va_run <- function(ns) {
  rows <- lapply(va_attacks(), function(a) {
    forged <- tryCatch(a$forge(ns), error = function(e) e)
    if (inherits(forged, "error")) {
      return(data.frame(attack = a$id, rule = a$rule, leak = FALSE,
                        codes = paste("could not run:", conditionMessage(forged)),
                        stringsAsFactors = FALSE))
    }
    codes <- dh_validation_issues(ns, list(document = forged))
    data.frame(attack = a$id, rule = a$rule, leak = !length(codes),
               codes = paste(unique(sub(" .*", "", codes)), collapse = " "),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# A shareable document of a case with its internal findings.
va_case <- function(ns, data, formula, ...) {
  result <- dh_run(ns, list(data = data, formula = formula, args = list(...)))
  if (!is.null(result$error)) {
    stop(result$error, call. = FALSE)
  }
  result
}

va_index <- function(document, check) {
  which(vapply(document$findings, function(f) identical(f$check, check), NA))[1L]
}

# Writes the internal value of a suppressed statistic. An attack whose
# statistic the filter writes does not apply, as under a mutant of the
# filter that writes it.
va_unsuppress <- function(result, check, name) {
  document <- result$document
  i <- va_index(document, check)
  s <- document$findings[[i]]$statistics[[name]]
  if (!is.null(s$value)) {
    stop("not applicable: the filter writes the statistic", call. = FALSE)
  }
  s$value <- result$findings[[i]]$values[[name]]
  s$availability <- NULL
  document$findings[[i]]$statistics[[name]] <- s
  document
}

# 40 subjects of two rows, 3 of which lack x: rows_dropped is 3.
va_dropped <- function(ns) {
  data <- data.frame(y = seq_len(80) / 4, x = c(NA, NA, NA, seq_len(77) %% 7),
                     subject = rep(sprintf("s%02d", 1:40), each = 2))
  va_case(ns, data, "y ~ x + (1 | subject)")
}

va_person_count_below_k <- function(ns) {
  va_unsuppress(va_dropped(ns), "sample.raw_vs_analysis", "rows_dropped")
}

va_real_of_small_finding <- function(ns) {
  # Four subjects: every finding fails the minimum-count rule.
  data <- data.frame(y = seq_len(16) / 3, x = seq_len(16) %% 5,
                     subject = rep(sprintf("s%02d", 1:4), each = 4))
  va_unsuppress(va_case(ns, data, "y ~ x + (1 | subject)"), "structure.cluster_sizes",
                "effective_size")
}

# 40 subjects of 10 to 13 rows.
va_sizes <- function(ns) {
  sizes <- rep(10:13, 10)
  data <- data.frame(y = seq_len(sum(sizes)) / 7, subject = rep(sprintf("s%02d", 1:40), sizes))
  va_case(ns, data, "y ~ 1 + (1 | subject)")
}

va_minimum_written <- function(ns) {
  va_unsuppress(va_sizes(ns), "structure.cluster_sizes", "smallest")
}

va_quantile_member_dropped <- function(ns) {
  document <- va_minimum_written(ns)
  i <- va_index(document, "structure.cluster_sizes")
  document$findings[[i]]$statistics$smallest$quantile <- NULL
  document
}

va_ratio_of_hidden_count <- function(ns) {
  counts <- c(0, 0, 0, 0, 0, 0, rep(1:4, length.out = 34))
  data <- data.frame(count = counts, x = seq(0, 3.9, by = 0.1))
  result <- va_case(ns, data, "count ~ x", family = "poisson", outcome_access = "T1",
                    reason = "Zeros.")
  va_unsuppress(result, "outcome.zero_shares", "zero_share")
}

va_quantile_n_beside_hidden_count <- function(ns) {
  # 11 subjects of two rows with a binary outcome: the levels of the design
  # sample are suppressed beside those of the analysis sample.
  data <- data.frame(y = rep(c(0, 1, 1, 0), length.out = 22), x = seq_len(22) / 2,
                     subject = rep(sprintf("s%02d", 1:11), each = 2))
  result <- va_case(ns, data, "y ~ x + (1 | subject)", family = "binomial",
                    outcome_access = "T1", reason = "Events.")
  document <- result$document
  i <- va_index(document, "structure.cluster_sizes")
  if (!is.null(document$findings[[i]]$statistics$levels$value)) {
    stop("not applicable: the filter writes the levels", call. = FALSE)
  }
  document$findings[[i]]$statistics$median$quantile$n <- result$findings[[i]]$values$levels
  document
}

va_lower_min_count <- function(ns) {
  document <- va_person_count_below_k(ns)
  document$privacy$min_count <- 3
  document
}
