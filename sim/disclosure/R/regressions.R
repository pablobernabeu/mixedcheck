# Attack (c), regression attacks (sim/disclosure/README.md): one attack for
# each value that a shareable document gave back in the four adversarial
# reviews of M2b-2, although docs/spec/privacy.md undertook to hide it. Each
# attack runs audit() on the reproducer of the review at the registry's k,
# reads the shareable document as the adversary would and returns whether it
# recovers the value, with what it found. The reproducers are those of
# r/tests/testthat/test-privacy.R and fixtures/conformance/audits/privacy.json.

# A case of the audit corpus by its identifier, as a case of the harness.
rg_corpus_case <- function(root, id) {
  path <- file.path(root, "fixtures", "conformance", "audits", "privacy.json")
  cases <- jsonlite::fromJSON(path, simplifyVector = FALSE)$cases
  case <- Find(function(c) identical(c$id, id), cases)
  if (is.null(case)) {
    stop(sprintf("no case %s in %s", id, path), call. = FALSE)
  }
  data <- as.data.frame(lapply(case$data, function(column) {
    unlist(lapply(column, function(v) if (is.null(v)) NA else v))
  }), stringsAsFactors = FALSE)
  args <- case[intersect(names(case), c("declaration", "family", "coding", "weights",
                                        "sample_columns", "outcome_access", "reason",
                                        "exploratory"))]
  list(data = data, formula = case$formula, args = args)
}

# The finding of a check in a shareable document whose scope has the given
# parts, or NULL.
rg_finding <- function(document, check, ...) {
  scope <- list(...)
  for (finding in document$findings) {
    if (identical(finding$check, check) &&
        all(vapply(names(scope), function(p) identical(finding$scope[[p]], scope[[p]]), NA))) {
      return(finding)
    }
  }
  NULL
}

# A written value: a statistic, or support.rows or support.distinct.
rg_value <- function(finding, name) {
  if (is.null(finding)) {
    return(NULL)
  }
  switch(name,
    support.rows = finding$support$rows$value,
    support.distinct = finding$support$contributors$distinct$value,
    finding$statistics[[name]]$value
  )
}

rg_detail <- function(finding, name) {
  if (is.null(finding)) {
    return(NULL)
  }
  finding$statistics[[name]]$availability$detail
}

rg_available <- function(finding) {
  !is.null(finding) && identical(finding$status$availability$value, "available")
}

# A difference of two written counts that recovers a count below k, 0
# included, or NULL.
rg_small_difference <- function(a, b, k) {
  if (is.null(a) || is.null(b)) {
    return(NULL)
  }
  d <- a - b
  if (d >= 0 && d < k) d else NULL
}

rg_result <- function(leak, found = NULL) {
  list(leak = isTRUE(leak), found = if (length(found)) paste(found, collapse = " ") else "")
}

# The attacks, each with the round of the review that found the leak, the
# channel and a function of the namespace and the repository root.
rg_attacks <- function() {
  list(
    list(id = "R1-nested-samples", round = 1L,
         channel = "the units of two nested assignments give back the subjects that lack one",
         attack = rg_nested_samples),
    list(id = "R1-crossed-combinations", round = 1L,
         channel = "the product of crossed levels beside the levels of g:h without an outcome",
         attack = rg_crossed_combinations),
    list(id = "R1-contributors", round = 1L,
         channel = "the contributors of the basis grouping_factors give back levels",
         attack = rg_contributors),
    list(id = "R1-minimum-maximum", round = 1L,
         channel = "a minimum or a maximum of level sizes is written",
         attack = rg_minimum_maximum),
    list(id = "R1-icc", round = 1L,
         channel = "the icc of structure.within_between, which with within_share gives back J",
         attack = rg_icc),
    list(id = "R1-labels-once", round = 1L,
         channel = "the labels of a pair minus the labels that recur give the labels that occur once",
         attack = rg_labels_once),
    list(id = "R1-binomial-overlap", round = 1L,
         channel = "binomial events and non-events beside the rows give back small classes of rows",
         attack = rg_binomial_overlap),
    list(id = "R1-software-one-class", round = 1L,
         channel = "the software of a document shows that an outcome class is empty",
         attack = rg_software_one_class),
    list(id = "R1-separation-columns", round = 1L,
         channel = "the kept columns of outcome.separation show that missing outcomes emptied a cell",
         attack = rg_separation_columns),
    list(id = "R2-eigenvalue", round = 2L,
         channel = "the smallest eigenvalue of identifiability.gram_rank, a function of N and J",
         attack = rg_eigenvalue),
    list(id = "R2-quartile-detail", round = 2L,
         channel = "the detail of a quartile of three levels shows on which side of k the minimum lies",
         attack = rg_quartile_detail),
    list(id = "R2-assignment-person-levels", round = 2L,
         channel = "levels minus the units of an assignment count a school of one pupil",
         attack = rg_assignment_person_levels),
    list(id = "R2-missing-key-rows", round = 2L,
         channel = "rows_dropped minus missing_key_rows count rows that a predictor removes",
         attack = rg_missing_key_rows),
    list(id = "R2-separation-one-factor", round = 2L,
         channel = "the verdict complete with the levels of one factor shows the class of each level",
         attack = rg_separation_one_factor),
    list(id = "R3-derived-detail", round = 3L,
         channel = "the detail min_count of a count derived from levels shows that they number k",
         attack = rg_derived_detail),
    list(id = "R3-quantile-detail", round = 3L,
         channel = "the detail min_count of a median whose n is hidden shows that the levels pass its rule",
         attack = rg_quantile_detail_n),
    list(id = "R3-design-reals", round = 3L,
         channel = "reals over the design sample beside the analysis sample in a T1 document",
         attack = rg_design_reals),
    list(id = "R3-separation-combinations", round = 3L,
         channel = "the verdict complete when the kept columns take few combinations of values",
         attack = rg_separation_combinations),
    list(id = "R3-separation-analysis-columns", round = 3L,
         channel = "the verdict when the analysis sample keeps the columns of one variable",
         attack = rg_separation_analysis_columns),
    list(id = "R3-ir-hash", round = 3L,
         channel = "the IR hash confirms a searched centring constant",
         attack = rg_ir_hash),
    list(id = "R4-rows-levels", round = 4L,
         channel = "rows fewer than twice the levels show levels of one row",
         attack = rg_rows_levels),
    list(id = "R4-parts-details", round = 4L,
         channel = "two parts of a written total, both with min_count, are bounded from below",
         attack = rg_parts_details),
    list(id = "R4-secondary-detail", round = 4L,
         channel = "the detail secondary shows that a count is at least k",
         attack = rg_secondary_detail),
    list(id = "R4-effective-size", round = 4L,
         channel = "effective_size gives back the sum of squared sizes and so an extreme size",
         attack = rg_effective_size),
    list(id = "R4-events-per-column", round = 4L,
         channel = "events_per_column times the kept columns gives back the minority events",
         attack = rg_events_per_column),
    list(id = "R4-equal-values", round = 4L,
         channel = "a count suppressed for an equal value shows the value of a suppressed quantity",
         attack = rg_equal_values)
  )
}

# Runs every attack at the registry's k and returns a data frame with one
# row for each: its identifier, round, channel, whether it recovered a value
# and what it found. An attack that cannot run, because the package lacks a
# check or a value, recovers nothing and says why.
rg_run <- function(ns, root) {
  rows <- lapply(rg_attacks(), function(a) {
    result <- tryCatch(a$attack(ns, root), error = function(e) {
      rg_result(FALSE, paste("could not run:", conditionMessage(e)))
    })
    data.frame(attack = a$id, round = a$round, channel = a$channel, leak = result$leak,
               found = result$found, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

rg_document <- function(ns, data, formula, ...) {
  result <- dh_run(ns, list(data = data, formula = formula, args = list(...)))
  if (!is.null(result$error)) {
    stop(result$error, call. = FALSE)
  }
  result$document
}

# --- Round 1 ---------------------------------------------------------------------------

rg_nested_samples <- function(ns, root) {
  subject <- rep(sprintf("s%02d", 1:60), each = 3)
  z1 <- rep(rep(c("a", "b"), 30), each = 3)
  z2 <- rep(rep(c("c", "c", "d", "d"), 15), each = 3)
  z1[subject <= "s20"] <- NA
  z2[subject <= "s15"] <- NA
  data <- data.frame(y = seq_along(subject) %% 7, x = seq_along(subject) %% 5,
                     subject = subject, z1 = z1, z2 = z2, stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), assignment = list(
    list(column = "z1", unit = "subject", randomised = TRUE, level = "between_unit"),
    list(column = "z2", unit = "subject", randomised = TRUE, level = "between_unit")
  ))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", declaration = declaration)
  k <- document$privacy$min_count
  d <- rg_small_difference(
    rg_value(rg_finding(document, "assignment.design_df", column = "z2"), "units"),
    rg_value(rg_finding(document, "assignment.design_df", column = "z1"), "units"), k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d subjects have z2 but not z1", d))
}

rg_crossed_combinations <- function(ns, root) {
  cells <- expand.grid(g = sprintf("g%02d", 1:12), h = sprintf("h%02d", 1:12),
                       stringsAsFactors = FALSE)
  data <- cells[rep(seq_len(nrow(cells)), each = 2)[-1L], ]
  data$pupil <- sprintf("p%03d", seq_len(nrow(data)))
  data$count <- seq_len(nrow(data)) %% 4
  data$x <- seq_len(nrow(data)) %% 7
  lost <- paste(cells$g, cells$h)[c(10, 30, 50, 70, 90)]
  data$count[paste(data$g, data$h) %in% lost] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "pupil", columns = list("pupil"), role = "participant")
  ))
  document <- rg_document(ns, data, "count ~ x + (1 | g) + (1 | h) + (1 | g:h)",
                          declaration = declaration, family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  incidence <- rg_finding(document, "structure.label_incidence", first = "g", second = "h")
  if (!identical(rg_value(incidence, "relation"), "crossed")) {
    return(rg_result(FALSE, "relation not written as crossed"))
  }
  first <- rg_value(incidence, "levels_first")
  second <- rg_value(incidence, "levels_second")
  analysis <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "g:h"), "levels")
  d <- if (!is.null(first) && !is.null(second)) rg_small_difference(first * second, analysis, k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d combinations lack an outcome", d))
}

rg_contributors <- function(ns, root) {
  n <- 80
  counts <- rep(c(0, 1, 3, 2), 20)
  counts[-c(1:15, 21, 23)] <- NA
  data <- data.frame(count = counts, x = seq_len(n) %% 9,
                     g = sprintf("g%02d", (seq_len(n) - 1) %% 20 + 1),
                     h = sprintf("h%02d", (seq_len(n) + 1) %/% 2), stringsAsFactors = FALSE)
  document <- rg_document(ns, data, "count ~ x + (1 | g) + (1 | h)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  design <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "g"),
                     "support.distinct")
  analysis <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "g"), "levels")
  d <- rg_small_difference(design, analysis, k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d levels of g lack an outcome", d))
}

rg_minimum_maximum <- function(ns, root) {
  # 40 subjects of 10 to 13 rows and one of 4: the smallest is below k.
  sizes <- c(4, rep(10:13, 10))
  data <- data.frame(y = seq_len(sum(sizes)) / 7, subject = rep(sprintf("s%02d", 1:41), sizes))
  document <- rg_document(ns, data, "y ~ 1 + (1 | subject)")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  written <- Filter(Negate(is.null), list(smallest = rg_value(sizes, "smallest"),
                                          largest = rg_value(sizes, "largest")))
  if (length(written)) {
    return(rg_result(TRUE, paste(names(written), unlist(written), sep = " = ", collapse = ", ")))
  }
  # Its detail would show on which side of k the smallest lies.
  leak <- identical(rg_detail(sizes, "smallest"), "min_count")
  rg_result(leak, if (leak) "the detail of smallest shows that it is below k")
}

rg_icc <- function(ns, root) {
  a <- c(rep(c(-1, 1), 30))
  data <- data.frame(y = seq_along(a) %% 7, x = a + rep(c(0, 0.5, 0.25), 20),
                     g = rep(sprintf("g%02d", 1:20), each = 3))
  document <- rg_document(ns, data, "y ~ x + (1 | g)")
  icc <- rg_value(rg_finding(document, "structure.within_between", factor = "g", term = "x"), "icc")
  rg_result(!is.null(icc), if (!is.null(icc)) sprintf("icc = %s is written", format(icc)))
}

rg_labels_once <- function(ns, root) {
  combinations <- rbind(
    data.frame(class = sprintf("c%02d", 1:20), school = sprintf("S%02d", (0:19 %% 12) + 1)),
    data.frame(class = sprintf("c%02d", 1:20), school = sprintf("S%02d", ((5:24) %% 12) + 1)),
    data.frame(class = sprintf("c%02d", 21:25), school = sprintf("S%02d", 1:5))
  )
  data <- combinations[rep(seq_len(nrow(combinations)), each = 2), ]
  data$tx <- ave(seq_len(nrow(data)), data$class, data$school, FUN = function(i) i[1L] %% 3)
  data$stype <- as.integer(substr(data$school, 2L, 3L)) %% 2
  data$y <- seq_len(nrow(data)) %% 7
  data$x <- seq_len(nrow(data)) %% 5
  document <- rg_document(ns, data, "y ~ x + tx + stype + (1 | school) + (1 | class)")
  k <- document$privacy$min_count
  levels <- rg_value(rg_finding(document, "structure.label_incidence", first = "class",
                                second = "school"), "levels_first")
  shared <- c(
    rg_value(rg_finding(document, "structure.id_scope_evidence", first = "class",
                        second = "school"), "shared_labels"),
    rg_value(rg_finding(document, "structure.label_incidence", first = "class",
                        second = "school"), "first_in_several"))
  d <- if (length(shared)) rg_small_difference(levels, shared[1L], k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d class labels occur in one school", d))
}

# The binomial reproducer of the review: 40 rows of 5 trials with two
# covariates drawn with seed 3, and 3 rows with no event.
rg_binomial_data <- function(k) {
  old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv())
  on.exit(if (!is.null(old)) assign(".Random.seed", old, globalenv()), add = TRUE)
  set.seed(3)
  data.frame(k = k, n = 5, x = round(rnorm(40), 3), z = round(rnorm(40), 3))
}

rg_binomial_overlap <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  declaration <- list(vocabulary = "0.1.0", variables = list(
    k = list(role = "outcome", measurement = "binomial", trials = "n")))
  data <- rg_binomial_data(c(rep(0, 3), rep(5, 12), rep(2, 25)))
  document <- rg_document(ns, data, "k ~ x + z", declaration = declaration,
                          outcome_access = "T2", reason = "Separation.", exploratory = TRUE)
  k <- document$privacy$min_count
  separation <- rg_finding(document, "outcome.separation")
  rows <- rg_value(separation, "support.rows")
  events <- rg_value(separation, "events")
  non_events <- rg_value(separation, "non_events")
  if (is.null(rows) || is.null(events) || is.null(non_events)) {
    return(rg_result(FALSE))
  }
  small <- c(without_events = rows - events, without_non_events = rows - non_events,
             both = events + non_events - rows)
  small <- small[small < k]
  rg_result(length(small) > 0L, paste(names(small), small, sep = " = ", collapse = ", "))
}

rg_needs_solver <- function() {
  if (!requireNamespace("lpSolve", quietly = TRUE)) {
    return(rg_result(FALSE, "could not run: lpSolve is not installed"))
  }
  NULL
}

rg_software_one_class <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  documents <- lapply(c(0, 3), function(events) {
    data <- data.frame(y = c(rep(1, events), rep(0, 200 - events)), x = seq_len(200) %% 7,
                       g = rep(sprintf("g%02d", 1:20), each = 10))
    rg_document(ns, data, "y ~ x + (1 | g)", family = "binomial", outcome_access = "T2",
                reason = "Separation.", exploratory = TRUE)
  })
  # One document is attacked: the solver is named exactly when the check
  # solved a program, which it does not with one class.
  named <- vapply(documents, function(d) "lpSolve" %in% names(d$software$packages), NA)
  leak <- !named[1L] && named[2L]
  rg_result(leak, if (leak) "the document without lpSolve has an empty class")
}

rg_separation_columns <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv())
  on.exit(if (!is.null(old)) assign(".Random.seed", old, globalenv()), add = TRUE)
  set.seed(5)
  data <- data.frame(y = rbinom(40, 1, 0.5), x1 = round(rnorm(40), 3), x2 = round(rnorm(40), 3),
                     smoker = c(rep("s2", 3), rep("s1", 37)), stringsAsFactors = FALSE)
  data$y[1:3] <- NA
  document <- rg_document(ns, data, "y ~ x1 + x2 + smoker", family = "binomial",
                          outcome_access = "T2", reason = "Separation.", exploratory = TRUE)
  kept <- rg_value(rg_finding(document, "design.rank_deficiency"), "kept")
  columns <- rg_value(rg_finding(document, "outcome.separation"), "columns")
  leak <- !is.null(kept) && !is.null(columns) && columns < kept
  rg_result(leak, if (leak) sprintf("%d kept columns of %d: a level lost every outcome",
                                    columns, kept))
}

# --- Round 2 ---------------------------------------------------------------------------

rg_eigenvalue <- function(ns, root) {
  data <- data.frame(y = seq_len(80) %% 9, condition = rep(c("a", "b"), 40),
                     subject = rep(sprintf("s%02d", 1:20), each = 4))
  document <- rg_document(ns, data, "y ~ condition + (1 | subject)")
  value <- rg_value(rg_finding(document, "identifiability.gram_rank"), "smallest_eigenvalue")
  if (is.null(value)) {
    return(rg_result(FALSE))
  }
  # For a balanced random intercept the eigenvalue is 1 - sqrt((J - 1) / (N - 2)).
  j <- 20
  n <- 2 + (j - 1) / (1 - value)^2
  rg_result(TRUE, sprintf("N = %.3f from the eigenvalue and J", n))
}

rg_quartile_detail <- function(ns, root) {
  school <- rep(c("A", "B", "C"), c(6, 40, 54))
  data <- data.frame(y = seq_along(school) %% 5, school = school,
                     pupil = sprintf("p%03d", seq_along(school)), stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ))
  document <- rg_document(ns, data, "y ~ 1 + (1 | school)", declaration = declaration)
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "school")
  details <- vapply(c("lower_quartile", "median"), function(n) rg_detail(sizes, n) %||% "", "")
  leak <- any(details == "min_count")
  rg_result(leak, if (leak) "a quartile of three schools, the smallest, is below k")
}

rg_assignment_person_levels <- function(ns, root) {
  school <- c(rep(sprintf("S%02d", 1:29), each = 8), rep("S30", 2))
  pupil <- c(rep(sprintf("P%03d", 1:116), each = 2), rep("P117", 2))
  arm <- ifelse(seq_along(school) %% 16 < 8, "a", "b")
  arm[school == "S30"] <- NA
  data <- data.frame(y = seq_along(school) %% 7, school = school, pupil = pupil, arm = arm,
                     stringsAsFactors = FALSE)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")
  ), assignment = list(list(column = "arm", unit = "school", randomised = TRUE,
                            level = "between_unit")))
  document <- rg_document(ns, data, "y ~ 1 + (1 | school)", declaration = declaration)
  k <- document$privacy$min_count
  d <- rg_small_difference(
    rg_value(rg_finding(document, "structure.cluster_sizes", factor = "school"), "levels"),
    rg_value(rg_finding(document, "assignment.constant_within_unit", column = "arm"), "units"), k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d school of one pupil lacks the arm", d))
}

rg_missing_key_rows <- function(ns, root) {
  data <- data.frame(y = seq_len(300) %% 11, x = seq_len(300) %% 13,
                     subject = rep(sprintf("s%02d", 1:30), each = 10), trial = rep(1:10, 30),
                     stringsAsFactors = FALSE)
  data$subject[1:15] <- NA
  data$x[c(100, 200)] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", declaration = declaration)
  k <- document$privacy$min_count
  d <- rg_small_difference(
    rg_value(rg_finding(document, "sample.raw_vs_analysis"), "rows_dropped"),
    rg_value(rg_finding(document, "keys.duplicates"), "missing_key_rows"), k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d rows lack x", d))
}

# Whether the shareable finding of outcome.separation writes a verdict that
# separates the classes.
rg_separating_verdict <- function(document) {
  verdict <- rg_value(rg_finding(document, "outcome.separation"), "verdict")
  !is.null(verdict) && verdict %in% c("quasi", "complete")
}

rg_separation_one_factor <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  data <- data.frame(arm = rep(c("a", "b", "c"), each = 40), g = rep(sprintf("g%02d", 1:20), 6),
                     stringsAsFactors = FALSE)
  data$y <- as.numeric(data$arm == "b")
  document <- rg_document(ns, data, "y ~ arm + (1 | g)", family = "binomial",
                          outcome_access = "T2", reason = "Separation.", exploratory = TRUE)
  leak <- rg_separating_verdict(document)
  rg_result(leak, if (leak) "complete with one factor: each arm holds one class")
}

# --- Round 3 ---------------------------------------------------------------------------

rg_derived_detail <- function(ns, root) {
  document <- rg_document_case(ns, root, "audits-privacy-062")
  # levels hidden with a detail other than min_count are at least k, and a
  # count of levels minus 1 with the detail min_count is below k.
  checks <- list(
    list("identifiability.levels_vs_dimension", "bound", "levels"),
    list("identifiability.df_budget", "budget", "levels"),
    list("assignment.design_df", "design_df", "units")
  )
  for (c in checks) {
    finding <- rg_finding(document, c[[1L]])
    if (identical(rg_detail(finding, c[[2L]]), "min_count") &&
        identical(rg_detail(finding, c[[3L]]), "secondary")) {
      return(rg_result(TRUE, sprintf("%s of %s with min_count shows that %s are exactly k",
                                     c[[2L]], c[[1L]], c[[3L]])))
    }
  }
  rg_result(FALSE)
}

rg_quantile_detail_n <- function(ns, root) {
  # 20 subjects of two rows with a binary outcome and none missing: the
  # levels of the design sample are hidden beside those of the analysis
  # sample, and the median of 2 rows is below k.
  data <- data.frame(y = rep(c(0, 1, 1, 0), length.out = 40), x = seq_len(40) / 2,
                     subject = rep(sprintf("s%02d", 1:20), each = 2))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", family = "binomial",
                          outcome_access = "T1", reason = "Events.")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  # Step 3 leaves to step 4 only the quantiles that the quantile rule
  # suppresses, so 'min_count' shows that the hidden levels number 20 or more.
  leak <- is.null(rg_value(sizes, "levels")) && identical(rg_detail(sizes, "median"), "min_count")
  rg_result(leak, if (leak) "the median's detail shows at least 20 hidden levels")
}

rg_document_case <- function(ns, root, id) {
  case <- rg_corpus_case(root, id)
  do.call(rg_document, c(list(ns = ns, data = case$data, formula = case$formula), case$args))
}

rg_design_reals <- function(ns, root) {
  document <- rg_document_case(ns, root, "audits-privacy-068")
  rows <- rg_finding(document, "design.scale_disparity")
  if (!is.null(rg_value(rows, "support.rows"))) {
    return(rg_result(FALSE, "the rows of the design sample are written"))
  }
  written <- Filter(Negate(is.null), lapply(c("sd_largest", "sd_smallest", "condition_number"),
                                            function(n) rg_value(rows, n)))
  rg_result(length(written) > 0L,
            if (length(written)) "reals over the design sample beside its suppressed rows")
}

rg_separation_combinations <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  found <- vapply(c("audits-privacy-069", "audits-privacy-064"), function(id) {
    rg_separating_verdict(rg_document_case(ns, root, id))
  }, NA)
  rg_result(any(found), paste("verdict written in", paste(names(found)[found], collapse = ", ")))
}

rg_separation_analysis_columns <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  leak <- rg_separating_verdict(rg_document_case(ns, root, "audits-privacy-063"))
  rg_result(leak, if (leak) "complete on the intercept and x of the analysis sample")
}

rg_ir_hash <- function(ns, root) {
  declaration <- list(vocabulary = "0.1.0", table = list(fields = list(
    list(name = "y", type = "number"), list(name = "x", type = "number")
  )))
  data <- data.frame(y = c(1, 2, 3, 4), x = c(1, 2, 4, 8))
  coding <- list(x = list(centring = "mean", significant_digits = 4))
  document <- rg_document(ns, data, "y ~ x", declaration = declaration, coding = coding)
  # The adversary builds the IR of candidate data whose mean of x is each
  # candidate value and compares its hash with the document's.
  for (mean in seq(1, 8, by = 0.25)) {
    candidate <- data.frame(y = c(1, 2, 3, 4), x = c(mean, mean, mean, mean))
    ir <- ns$formula_ir("y ~ x", declaration, candidate, coding = coding)
    if (identical(ns$canonical_hash(ir, "hashable"), document$inputs$model$ir_hash)) {
      return(rg_result(TRUE, sprintf("the IR hash confirms the mean %s", format(mean))))
    }
  }
  rg_result(FALSE)
}

# --- Round 4 ---------------------------------------------------------------------------

rg_rows_levels <- function(ns, root) {
  found <- character(0)
  # 12 subjects, 3 of one row and 9 of two, and 15 subjects, 9 of one row and
  # 6 of two: each level of two rows or more holds two rows, so the levels
  # with one row number at least 2J - N.
  for (single in c(3, 9)) {
    double <- if (single == 3) 9 else 6
    subject <- c(sprintf("a%02d", seq_len(single)), rep(sprintf("b%02d", seq_len(double)), each = 2))
    data <- data.frame(y = seq_along(subject) / 3, x = seq_along(subject) %% 5, subject = subject)
    document <- rg_document(ns, data, "y ~ x + (1 | subject)")
    k <- document$privacy$min_count
    sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
    rows <- rg_value(sizes, "rows")
    levels <- rg_value(sizes, "levels")
    if (!is.null(rows) && !is.null(levels) && 2 * levels - rows >= 1) {
      lower <- 2 * levels - rows
      found <- c(found, sprintf("smallest = 1 and singletons >= %d of %d levels", lower, levels))
      if (lower >= k - 1 && identical(rg_detail(sizes, "singletons"), "min_count")) {
        found <- c(found, sprintf("singletons = %d", lower))
      }
    }
  }
  rg_result(length(found) > 0L, found)
}

rg_parts_details <- function(ns, root) {
  found <- character(0)
  keys <- data.frame(subject = rep(sprintf("s%02d", 1:20), each = 3), trial = rep(1:3, 20),
                     x = seq_len(60) %% 7 + 0.5)
  conflicting <- keys[10:18, ]
  conflicting$x <- conflicting$x + 1
  data <- rbind(keys, keys[1:9, ], conflicting)
  data$y <- seq_len(78) %% 11 + 0.5
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ), observation = list(key = list("subject", "trial")))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", declaration = declaration)
  k <- document$privacy$min_count
  duplicates <- rg_finding(document, "keys.duplicates")
  total <- rg_value(duplicates, "duplicated_keys")
  parts <- c(rg_detail(duplicates, "identical_keys"), rg_detail(duplicates, "conflicting_keys"))
  # Both parts below k, each at least the total minus k - 1.
  if (!is.null(total) && identical(parts, c("min_count", "min_count")) && total - (k - 1) == k - 1) {
    found <- c(found, sprintf("identical_keys = conflicting_keys = %d", k - 1))
  }
  data <- data.frame(y = rep(c(1, 0), 9), x = seq_len(18) %% 7 + 0.5)
  document <- rg_document(ns, data, "y ~ x", family = "binomial", outcome_access = "T1",
                          reason = "Events.")
  minority <- rg_finding(document, "outcome.minority_events")
  total <- rg_value(minority, "support.rows")
  parts <- c(rg_detail(minority, "events"), rg_detail(minority, "non_events"))
  if (!is.null(total) && identical(parts, c("min_count", "min_count")) && total - (k - 1) == k - 1) {
    found <- c(found, sprintf("events = non_events = %d", k - 1))
  }
  rg_result(length(found) > 0L, found)
}

rg_secondary_detail <- function(ns, root) {
  # 10 subjects of two rows. If a count below k that a later rule suppresses
  # kept 'min_count', the levels with two rows suppressed with 'secondary'
  # beside singletons with 'min_count' would be at least k, and so all of the
  # k written levels, with no level of one row.
  data <- data.frame(y = seq_len(20) / 3, x = seq_len(20) %% 7 + 0.5,
                     subject = rep(sprintf("s%02d", 1:10), each = 2))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)")
  k <- document$privacy$min_count
  levels <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "levels")
  singletons <- rg_detail(rg_finding(document, "structure.cluster_sizes", factor = "subject"),
                          "singletons")
  multi <- rg_detail(rg_finding(document, "structure.within_between", factor = "subject",
                                term = "x"), "multi_row_levels")
  leak <- identical(levels, k) && identical(singletons, "min_count") && identical(multi, "secondary")
  rg_result(leak, if (leak) sprintf("multi_row_levels = %d, singletons = 0", k))
}

# The extreme sizes that N, J, a written median c and the sum S of the
# squared sizes leave: D = N - cJ and Q = S - 2cN + c^2 J are the sum and the
# sum of squares of the deviations from c, which with Q = |D| are |D| values
# of one sign and size 1.
rg_effective_size <- function(ns, root) {
  old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv())
  on.exit(if (!is.null(old)) assign(".Random.seed", old, globalenv()), add = TRUE)
  set.seed(2)
  sizes <- c(rep(10L, 39), 9L)
  data <- data.frame(y = rnorm(399), x = rnorm(399), subject = rep(sprintf("s%02d", 1:40), sizes))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)")
  k <- document$privacy$min_count
  finding <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  n0 <- rg_value(finding, "effective_size")
  n <- rg_value(finding, "rows")
  j <- rg_value(finding, "levels")
  median <- rg_value(finding, "median")
  if (is.null(n0) || is.null(n) || is.null(j) || is.null(median)) {
    return(rg_result(FALSE))
  }
  s <- round(n * (n - n0 * (j - 1)))
  d <- n - median * j
  q <- s - 2 * median * n + median^2 * j
  leak <- d != 0 && q == abs(d) && abs(d) < k
  rg_result(leak, if (leak) sprintf("%s = %d, held by %d levels",
                                    if (d < 0) "smallest" else "largest", median + sign(d), abs(d)))
}

rg_events_per_column <- function(ns, root) {
  data <- data.frame(y = c(rep(1, 4), rep(0, 14)), x = seq_len(18) %% 7 + 0.5)
  document <- rg_document(ns, data, "y ~ x", family = "binomial", outcome_access = "T1",
                          reason = "Events.")
  k <- document$privacy$min_count
  ratio <- rg_value(rg_finding(document, "outcome.minority_events"), "events_per_column")
  kept <- rg_value(rg_finding(document, "design.rank_deficiency"), "kept")
  if (is.null(ratio) || is.null(kept)) {
    return(rg_result(FALSE))
  }
  minority <- round(ratio * kept)
  rg_result(minority < k, sprintf("%d minority events", minority))
}

rg_equal_values <- function(ns, root) {
  found <- character(0)
  # 20 subjects, 2 of one row and 18 of three, x constant within each: the
  # budget, which the levels and the consuming terms give as 20 - 2, would
  # be suppressed only for equalling the 18 suppressed levels with two rows.
  sizes <- c(1, 1, rep(3, 18))
  subject <- rep(sprintf("s%02d", seq_along(sizes)), sizes)
  data <- data.frame(y = (seq_along(subject) * 5) %% 13 + 0.25,
                     x = rep(seq_along(sizes) %% 3 + 0.5, sizes), subject = subject)
  document <- rg_document(ns, data, "y ~ x + (1 | subject)")
  budget <- rg_finding(document, "identifiability.df_budget", factor = "subject")
  levels <- rg_value(budget, "levels")
  terms <- unlist(rg_value(budget, "consuming_terms"))
  if (!is.null(levels) && identical(rg_detail(budget, "budget"), "secondary")) {
    found <- c(found, sprintf("singletons = %d", length(terms)))
  }
  # Items of 41, 42 and 43 rows crossed with 45 - s subjects of about 40 rows
  # and s subjects of one row: a quartile suppressed alone between written
  # neighbours one apart lies between them and equals the suppressed levels
  # of subject with two rows or more.
  old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv())
  on.exit(if (!is.null(old)) assign(".Random.seed", old, globalenv()), add = TRUE)
  set.seed(3)
  item_sizes <- sample(rep(c(41L, 42L, 43L), c(10L, 10L, 20L)))
  item <- rep(sprintf("i%02d", seq_along(item_sizes)), item_sizes)
  for (s in 2:4) {
    subject <- sprintf("s%02d", (seq_along(item) - 1L) %% (45L - s) + 1L)
    subject[seq_len(s)] <- sprintf("t%02d", seq_len(s))
    data <- data.frame(y = seq_along(item) %% 11 + 0.5, x = seq_along(item) %% 7 + 0.25,
                       subject = subject, item = item, stringsAsFactors = FALSE)
    document <- rg_document(ns, data, "y ~ x + (1 | subject) + (1 | item)")
    items <- rg_finding(document, "structure.cluster_sizes", factor = "item")
    j <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "levels")
    quartiles <- c("lower_quartile", "median", "upper_quartile")
    values <- lapply(quartiles, function(q) rg_value(items, q))
    hidden <- vapply(quartiles, function(q) identical(rg_detail(items, q), "secondary"), NA)
    if (!is.null(j) && sum(hidden) == 1L && which(hidden) == 2L &&
        !is.null(values[[1L]]) && !is.null(values[[3L]]) && values[[3L]] - values[[1L]] == 2) {
      found <- c(found, sprintf("singletons = %d", j - values[[1L]] - 1))
    }
  }
  rg_result(length(found) > 0L, found)
}
