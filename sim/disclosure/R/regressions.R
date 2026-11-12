# Attack (c), regression attacks (sim/disclosure/README.md): one attack for
# each value that a shareable document gave back in the four adversarial
# reviews of M2b-2 and in the reviews of the two tiers of the filter (rounds
# 5 to 8), although docs/spec/privacy.md undertook to hide it. Each attack
# runs audit() on the reproducer of the review at the registry's k, or at the
# k that it sets, reads the shareable document as the adversary would and
# returns whether it recovers the value, with what it found. An attack of tier B recovers a
# design-structure value that privacy.md now leaves as residual risk, and
# what it recovers is reported without failing the run. The reproducers are
# those of r/tests/testthat/test-privacy.R and
# fixtures/conformance/audits/privacy.json.

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
    list(id = "R1-icc", tier = "B", round = 1L,
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
    list(id = "R2-eigenvalue", tier = "B", round = 2L,
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
    list(id = "R4-rows-levels", tier = "B", round = 4L,
         channel = "rows fewer than twice the levels show levels of one row",
         attack = rg_rows_levels),
    list(id = "R4-parts-details", round = 4L,
         channel = "two parts of a written total, both with min_count, are bounded from below",
         attack = rg_parts_details),
    list(id = "R4-secondary-detail", round = 4L,
         channel = "the detail secondary shows that a count is at least k",
         attack = rg_secondary_detail),
    list(id = "R4-effective-size", tier = "B", round = 4L,
         channel = "effective_size gives back the sum of squared sizes and so an extreme size",
         attack = rg_effective_size),
    list(id = "R4-events-per-column", round = 4L,
         channel = "events_per_column times the kept columns gives back the minority events",
         attack = rg_events_per_column),
    list(id = "R5-supports", round = 5L,
         channel = "the design rows beside the support rows of a T1 finding give the rows without an outcome",
         attack = rg_supports),
    list(id = "R5-analysis-bounds", round = 5L,
         channel = "the design rows beside events and non-events give the rows without an outcome",
         attack = rg_analysis_bounds),
    list(id = "R5-design-reals", round = 5L,
         channel = "a standard deviation over the design sample gives its rows beside events and non-events",
         attack = rg_design_reals_bernoulli),
    list(id = "R5-closure", round = 5L,
         channel = "rows and levels of the design sample bound its levels with two rows beside the analysis sample",
         attack = rg_closure),
    list(id = "R5-analysis-levels", round = 5L,
         channel = "the levels and the levels with two rows of the analysis sample give its levels with one row",
         attack = rg_analysis_levels),
    list(id = "R6-table-chain", round = 6L,
         channel = "the rows of the table, written only k or more above the design sample's, pin the rows without an outcome",
         attack = rg_table_chain),
    list(id = "R6-key-chain", round = 6L,
         channel = "missing_key_rows, written only when rule 4 does not fire for the design sample, pins its rows",
         attack = rg_key_chain),
    list(id = "R6-contributors-bound", round = 6L,
         channel = "written contributors, which no hidden level count equals, bound a factor's hidden levels from below",
         attack = rg_contributors_bound),
    list(id = "R6-parts-bound", round = 6L,
         channel = "a written part of a hidden count of levels bounds it from below by the part plus k",
         attack = rg_parts_bound),
    list(id = "R6-analysis-rows-levels", round = 6L,
         channel = "rows fewer than twice the levels of the analysis sample show a subject of one analysed row",
         attack = rg_analysis_rows_levels),
    list(id = "R6-non-person", round = 6L,
         channel = "the written levels of a non-person item, two members each, bound the members and rows the design sample loses",
         attack = rg_non_person),
    list(id = "R6-crossed-analysis-levels", round = 6L,
         channel = "the analysis sample's levels of two crossed columns bound their product, which rule 1 bounds from above",
         attack = rg_crossed_analysis_levels),
    list(id = "R6-components", round = 6L,
         channel = "twice the crossed components bound a factor's hidden levels from below",
         attack = rg_components),
    list(id = "R6-internal-absent", round = 6L,
         channel = "the absence of bounds of outcome.separation shows the kept columns of the analysis sample",
         attack = rg_internal_absent),
    list(id = "R6-fixed-factor", round = 6L,
         channel = "df of a grouping factor that is also a fixed term counts its levels in the design sample",
         attack = rg_fixed_factor),
    list(id = "R6-rows-levels-lost", round = 6L,
         channel = "rows lost equal to levels lost beside the design sample's singletons give the analysis sample's",
         attack = rg_rows_levels_lost),
    list(id = "R6-singletons-rows", round = 6L,
         channel = "singletons and rows of the design sample bound its levels beside the analysis sample's",
         attack = rg_singletons_rows),
    list(id = "R7-unit-contributors", round = 7L,
         channel = "the contributors of the basis disclosure_unit beside the rows show a member of one analysed row",
         attack = rg_unit_contributors),
    list(id = "R7-fixed-factor-non-person", round = 7L,
         channel = "df of a non-person factor that is also a fixed term counts its levels in the design sample",
         attack = rg_fixed_factor_non_person),
    list(id = "R7-random-variable", round = 7L,
         channel = "the dimension of a random term over a categorical variable counts its levels in the design sample",
         attack = rg_random_variable),
    list(id = "R7-dominance", round = 7L,
         channel = "a finding that fails the dominance rule writes a person count or a real",
         attack = rg_dominance),
    list(id = "R7-separation-interaction", round = 7L,
         channel = "the verdict of outcome.separation with one kept column of two variables names a cell",
         attack = rg_separation_interaction),
    list(id = "R7-separation-one-variable", round = 7L,
         channel = "the verdict of outcome.separation with the columns of one factor shows the class of each level",
         attack = rg_separation_one_variable),
    list(id = "R7-part-detail", round = 7L,
         channel = "the detail min_count of a part below k shows that part_of did not fire and bounds the part by the total minus k",
         attack = rg_part_detail),
    list(id = "R4-equal-values", round = 4L,
         channel = "a count suppressed for an equal value shows the value of a suppressed quantity",
         attack = rg_equal_values),
    list(id = "R8-interaction", round = 8L,
         channel = "df of two factors and empty_cells count the combinations of a fixed interaction that is also a grouping factor",
         attack = rg_interaction),
    list(id = "R8-sizes-two-rows", round = 8L,
         channel = "rows, singletons and levels with two rows of the design sample show every level to hold at most two rows, which beside the analysed rows and levels gives the levels with one analysed row",
         attack = rg_sizes_two_rows),
    list(id = "R8-sizes-firing", round = 8L,
         channel = "effective_size, rows and levels of the design sample give the level sizes, which beside the analysed rows and the firing of rule 1 give the hidden analysed levels",
         attack = rg_sizes_firing),
    list(id = "R8-sizes-one-row", round = 8L,
         channel = "the sizes of the levels of the design sample beside the analysed rows and levels give the analysed levels with one row",
         attack = rg_sizes_one_row),
    list(id = "R8-hidden-levels", round = 8L,
         channel = "the written levels of the design sample show that rule 1 did not fire against the analysed levels that rule 3 hides, which the minimum-count rule bounds from below",
         attack = rg_hidden_levels),
    list(id = "R8-non-person-whole", round = 8L,
         channel = "the written levels of a non-person item that keeps two members in each analysed level bound the rows of the design sample that rule 1 hides, at k = 3",
         attack = rg_non_person_whole),
    list(id = "R8-non-person-members", round = 8L,
         channel = "the written levels of a non-person item bound the members of the design sample that rule 1 hides as within k of the analysed ones",
         attack = rg_non_person_members),
    list(id = "R8-reals-items", round = 8L,
         channel = "the reals that read a grouping factor give back its levels in the design sample, which rule 1 hides beside the analysed ones while the rows are written",
         attack = rg_reals_items),
    list(id = "R8-parts-variable", round = 8L,
         channel = "a written part of the analysed levels that the columns of a factor hide bounds them from below",
         attack = rg_parts_variable),
    list(id = "R8-parts-rule3", round = 8L,
         channel = "a written part of the analysed levels that rule 3 hides bounds them from below",
         attack = rg_parts_rule3),
    list(id = "R8-two-rows-variable", round = 8L,
         channel = "the rows and the columns of a factor bound its levels with two rows in the design sample by the analysed ones",
         attack = rg_two_rows_variable),
    list(id = "R8-non-person-variable", round = 8L,
         channel = "the columns of a non-person factor bound the hidden rows of the design sample by twice its levels",
         attack = rg_non_person_variable),
    list(id = "R8-rule3-rows", round = 8L,
         channel = "analysed rows fewer than 2k beside k contributors or more show a level of one analysed row",
         attack = rg_rule3_rows),
    list(id = "R8-chain-items", round = 8L,
         channel = "the contributors of the table, written or hidden beside the levels that the design sample loses, tell 0 levels without an outcome from 1",
         attack = rg_chain_items),
    list(id = "R8-contributors-levels", round = 8L,
         channel = "the contributors of the basis grouping_factors, written beside the levels of a factor that the design sample loses, bound those levels from below by one more than their value",
         attack = rg_contributors_levels),
    list(id = "R8-column-levels", round = 8L,
         channel = "df, kept, columns and budget give back the levels below k of a fixed factor that is also a declared unit, under treatment and sum contrasts, in an interaction and through a copy of the unit that lacks a label",
         attack = rg_column_levels),
    list(id = "R9-items-rows", round = 9L,
         channel = "the columns of a term whose variables divide the design sample, though not the table, into the levels of a grouping factor give back its levels without an outcome",
         attack = rg_items_rows),
    list(id = "R9-analysis-columns", round = 9L,
         channel = "design_df on rows of an assignment that are the analysis sample gives back the analysed levels of a fixed factor that the end of rule 1 hides",
         attack = rg_analysis_columns),
    list(id = "R9-table-levels", round = 9L,
         channel = "dimension of a term with the indicators of a factor gives back the levels of the table that rule 1 hides beside those of the design sample",
         attack = rg_table_levels),
    list(id = "R9-failing-levels", round = 9L,
         channel = "df and kept give back the levels of a factor that the minimum-count rule hides in every finding that counts them",
         attack = rg_failing_levels),
    list(id = "R9-assignment-levels", round = 9L,
         channel = "design_df on the rows of two assignments gives back the levels of a fixed factor that rule 1 hides there beside the design sample",
         attack = rg_assignment_levels),
    list(id = "R9-combination-levels", round = 9L,
         channel = "kept gives back the combinations of two factors that step 3 hides as a grouping factor",
         attack = rg_combination_levels),
    list(id = "R9-column-detail", round = 9L,
         channel = "the detail 'min_count' on budget bounds the levels of a fixed factor that step 3 hides to a single value",
         attack = rg_column_detail),
    list(id = "R9-chain-assignment", round = 9L,
         channel = "the units of an assignment inside a design sample that loses its levels beside the analysis sample tell 0 levels without an outcome from 1",
         attack = rg_chain_assignment),
    list(id = "R9-propagate-rows", round = 9L,
         channel = "the rows of the design sample, written beside analysed rows that rule 3 hides, tell whether rule 1 fired",
         attack = rg_propagate_rows)
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

# --- Round 5: the rules beside the analysis sample ---------------------------------------

rg_rows_of <- function(document, check) rg_value(rg_finding(document, check), "support.rows")

rg_supports <- function(ns, root) {
  # 30 subjects of 12 rows, 12 with a constant outcome, and 10 subjects of
  # one row, no missing outcome, so that outcome.constant_clusters is written.
  y <- c(unlist(lapply(1:30, function(s) if (s <= 12) rep(s, 12) else (1:12) * s %% 17 + 0.5)), (1:10) / 3)
  data <- data.frame(y = y, x = seq_along(y) %% 11 + 0.5,
                     subject = c(rep(sprintf("s%02d", 1:30), each = 12), sprintf("t%02d", 1:10)))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", outcome_access = "T1", reason = "Rows.")
  k <- document$privacy$min_count
  design <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "rows")
  analysis <- rg_value(rg_finding(document, "outcome.constant_clusters", factor = "subject"), "support.rows")
  leak <- !is.null(design) && !is.null(analysis) && design - analysis < k
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", design - analysis))
}

rg_bernoulli_pairs <- function(cond = FALSE) {
  y <- rep(c(1, 0, 0, 1, 1, 0, 1, 0), 5)
  data <- data.frame(y = y, x = (seq_along(y) * 7) %% 11 + 0.5,
                     subject = rep(sprintf("s%02d", 1:20), each = 2))
  if (cond) {
    data$x <- rep(c(-0.5, 0.5), 20)
    data$x[c(3, 8, 11)] <- -0.5
  }
  data
}

rg_analysis_bounds <- function(ns, root) {
  document <- rg_document(ns, rg_bernoulli_pairs(), "y ~ x + (1 | subject)", family = "binomial",
                          outcome_access = "T1", reason = "Events.")
  k <- document$privacy$min_count
  design <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "rows")
  minority <- rg_finding(document, "outcome.minority_events", factor = "subject")
  events <- rg_value(minority, "events")
  non_events <- rg_value(minority, "non_events")
  leak <- !is.null(design) && !is.null(events) && !is.null(non_events) &&
    design - events - non_events < k
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", design - events - non_events))
}

rg_design_reals_bernoulli <- function(ns, root) {
  document <- rg_document(ns, rg_bernoulli_pairs(TRUE), "y ~ x + (1 | subject)", family = "binomial",
                          outcome_access = "T1", reason = "Events.")
  k <- document$privacy$min_count
  sd <- rg_value(rg_finding(document, "design.scale_disparity"), "sd_largest")
  minority <- rg_finding(document, "outcome.minority_events", factor = "subject")
  events <- rg_value(minority, "events")
  non_events <- rg_value(minority, "non_events")
  if (is.null(sd) || is.null(events) || is.null(non_events)) {
    return(rg_result(FALSE))
  }
  # The rows of the design sample and at -0.5 that give the standard
  # deviation, within k - 1 rows of the analysis sample.
  rows <- events + non_events
  found <- integer(0)
  for (n in rows:(rows + k - 1)) {
    for (low in 1:(n - 1)) {
      if (isTRUE(all.equal(stats::sd(c(rep(-0.5, low), rep(0.5, n - low))), sd, tolerance = 1e-12))) {
        found <- union(found, n)
      }
    }
  }
  leak <- length(found) == 1L
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", found - rows))
}

rg_closure <- function(ns, root) {
  # 20 subjects of two rows, 10 with a constant outcome, 10 subjects of one
  # row with an outcome and 10 of one row without one.
  y <- c(rep(c(3, 3), 10), rep(c(1, 2), 10), (1:10) / 7, rep(NA, 10))
  data <- data.frame(y = y, x = seq_along(y) %% 7 + 0.5,
                     subject = c(rep(sprintf("s%02d", 1:20), each = 2), sprintf("t%02d", 1:20)))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", outcome_access = "T1", reason = "Sizes.")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  rows <- rg_value(sizes, "rows")
  levels <- rg_value(sizes, "levels")
  two <- rg_value(rg_finding(document, "outcome.constant_clusters", factor = "subject"), "multi_row_levels")
  leak <- !is.null(rows) && !is.null(levels) && !is.null(two) && rows - levels <= two
  rg_result(leak, if (leak) "no subject lost its second outcome")
}

rg_analysis_levels <- function(ns, root) {
  # 25 subjects of two rows, 12 with a constant outcome, and 3 of one row.
  y <- c(rep(c(1, 1), 6), rep(c(0, 0), 6), rep(c(1, 0), 13), c(1, 0, 1))
  data <- data.frame(y = y, x = seq_along(y) %% 5 + 0.5,
                     subject = c(rep(sprintf("s%02d", 1:25), each = 2), sprintf("t%02d", 1:3)))
  document <- rg_document(ns, data, "y ~ x + (1 | subject)", family = "binomial",
                          outcome_access = "T1", reason = "Levels.")
  k <- document$privacy$min_count
  levels <- rg_value(rg_finding(document, "outcome.minority_events", factor = "subject"), "levels")
  two <- rg_value(rg_finding(document, "outcome.constant_clusters", factor = "subject"), "multi_row_levels")
  leak <- !is.null(levels) && !is.null(two) && levels - two < k
  rg_result(leak, if (leak) sprintf("%d subjects with one analysed row", levels - two))
}

# --- Round 6: chains of comparisons and bounds on hidden quantities -----------------------

# Two tables that differ only in a hidden outcome-derived difference: a leak
# when their strict reductions differ, since the document then tells the two
# values apart.
rg_pair <- function(ns, cases, what) {
  docs <- lapply(cases, function(case) {
    do.call(rg_document, c(list(ns = ns, data = case$data, formula = case$formula), case$args))
  })
  differ <- dh_reduce(docs[[1L]], strict = TRUE) != dh_reduce(docs[[2L]], strict = TRUE)
  rg_result(differ, if (differ) what)
}

rg_table_chain <- function(ns, root) {
  # 50 subjects of four rows and 10 of one row: the 10 rows lack the
  # covariate, or 9 lack it and 1 lacks the outcome.
  make <- function(y_missing) {
    count <- c(rep(c(0, 1, 2, 3), 50), rep(1, 10))
    x <- c(seq_len(200) %% 7 + 0.5, rep(NA, 10))
    if (y_missing) {
      x[201] <- 0.5
      count[201] <- NA
    }
    list(data = data.frame(count = count, x = x,
                           g = c(rep(sprintf("g%02d", 1:50), each = 4), sprintf("h%02d", 1:10))),
         formula = "count ~ x + (1 | g)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros."))
  }
  rg_pair(ns, list(make(FALSE), make(TRUE)), "the table's rows tell 0 rows without an outcome from 1")
}

rg_key_chain <- function(ns, root) {
  make <- function(y_missing) {
    subject <- c(rep(sprintf("s%02d", 1:50), each = 4), rep(NA, 10), sprintf("u%02d", 1:10))
    trial <- c(rep(1:4, 50), 1:10, rep(1, 10))
    x <- c(seq_len(210) %% 7 + 0.5, rep(NA, 10))
    count <- c(rep(c(0, 1, 2, 3), 50), rep(1, 20))
    if (y_missing) {
      x[211] <- 0.5
      count[211] <- NA
    }
    list(data = data.frame(count = count, x = x, subject = subject, trial = trial),
         formula = "count ~ x + (1 | subject)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros.",
                     declaration = list(vocabulary = "0.1.0",
                                        observation = list(key = list("subject", "trial")))))
  }
  rg_pair(ns, list(make(FALSE), make(TRUE)),
          "missing_key_rows tells 0 rows without an outcome from 1")
}

rg_contributors_bound <- function(ns, root) {
  # 40 levels of f crossed with 42 of g over 168 rows with an outcome, and 20
  # rows without one in 10 new levels of f of two rows each: in 9 new levels
  # of g of two rows and 2 rows of existing levels, or in 8 new levels and 4
  # rows of existing levels. The contributors, 50 levels of f, are written
  # when g has 51 levels and equal the hidden levels of g when it has 50.
  make <- function(new_g) {
    r <- 1:168
    f <- sprintf("F%02d", (r - 1) %% 40 + 1)
    g <- sprintf("G%02d", (r - 1) %% 42 + 1)
    extra <- c(rep(sprintf("G%02d", 42 + seq_len(new_g)), each = 2),
               sprintf("G%02d", seq_len(20 - 2 * new_g)))
    list(data = data.frame(count = c(r %% 4, rep(NA, 20)), x = c(r %% 7 + 0.5, (1:20) / 3),
                           f = c(f, rep(sprintf("F%02d", 41:50), each = 2)), g = c(g, extra)),
         formula = "count ~ x + (1 | f) + (1 | g)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros."))
  }
  rg_pair(ns, list(make(9), make(8)),
          "the contributors tell 9 levels of g without an outcome from 8")
}

rg_parts_bound <- function(ns, root) {
  # 49 subjects of two rows in the design sample. 30 keep both rows, 15 of
  # them with a constant count, 10 keep one row and 9 lose both. The
  # covariate varies within 39 subjects, so that informative_levels, 39, a
  # part of the levels, shows them to be at least 49 when written, and
  # varying_levels, 39, shows that the subjects of two rows are at least 49,
  # so that only the levels can have made the levels hidden beside the 40 of
  # the analysis sample.
  subject <- rep(sprintf("s%02d", 1:49), each = 2)
  count <- c(rep(c(2, 2), 15), rep(c(1, 3), 15), rep(c(4, NA), 10), rep(NA, 18))
  x <- rep(c(0.5, 1.5), 49)
  x[subject %in% sprintf("s%02d", 40:49)] <- 0.5
  data <- data.frame(count = count, x = x, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 + x | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  informative <- rg_value(rg_finding(document, "identifiability.levels_vs_dimension",
                                     factor = "subject"), "informative_levels")
  hidden <- is.null(rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"),
                             "levels"))
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "subject"), "levels")
  leak <- !is.null(informative) && hidden && !is.null(levels) && informative + k >= levels + k - 1
  rg_result(leak, if (leak) sprintf("%d subjects without an outcome", informative + k - levels))
}

rg_components <- function(ns, root) {
  # 25 crossed components of two levels of f and two of g, and 9 levels of g
  # without an outcome: twice the components, 50, bound the levels of g in
  # the design sample from below, and rule 1 bounds them by 41 + 9 above.
  rows <- expand.grid(rep = 1:2, b = 1:2, a = 1:2, c = 1:25)
  data <- data.frame(f = sprintf("F%02d_%d", rows$c, rows$a), g = sprintf("G%02d_%d", rows$c, rows$b))
  data$count <- seq_len(nrow(data)) %% 4
  data$count[data$g %in% sprintf("G%02d_2", 1:9)] <- NA
  data$x <- seq_len(nrow(data)) %% 7 + 0.5
  document <- rg_document(ns, data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  components <- rg_value(rg_finding(document, "structure.connectivity"), "components")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "g"), "levels")
  hidden <- is.null(rg_value(rg_finding(document, "structure.cluster_sizes", factor = "g"), "levels"))
  leak <- !is.null(components) && !is.null(levels) && hidden && 2 * components == levels + k - 1
  rg_result(leak, if (leak) sprintf("%d levels of g without an outcome", k - 1))
}

rg_internal_absent <- function(ns, root) {
  # 90 rows of 49 covariates and three indicators that are 1 in one row
  # each: the analysis sample keeps 53 columns, more than max_bound_programs
  # allows, so bounds is absent, and it would be present had the outcomes of
  # the three rows been missing.
  set.seed(7)
  n <- 90
  data <- as.data.frame(matrix(stats::rnorm(n * 49), n, 49))
  names(data) <- sprintf("x%02d", 1:49)
  data$y <- stats::rbinom(n, 1, 0.5)
  for (j in 1:3) data[[sprintf("d%d", j)]] <- as.numeric(seq_len(n) == j)
  formula <- paste("y ~", paste(c(names(data)[1:49], "d1", "d2", "d3"), collapse = " + "))
  document <- rg_document(ns, data, formula, family = "binomial", outcome_access = "T2",
                          reason = "Separation.", exploratory = TRUE)
  separation <- rg_finding(document, "outcome.separation")
  if (!rg_available(separation)) {
    return(rg_result(FALSE))
  }
  missing <- setdiff(c("bounds", "columns_involved", "optimum", "margin", "columns"),
                     names(separation$statistics))
  rg_result(length(missing) > 0L, if (length(missing)) paste("absent:", paste(missing, collapse = ", ")))
}

rg_fixed_factor <- function(ns, root) {
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- seq_len(200) %% 5
  count[school %in% sprintf("s%02d", 42:50)] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school)
  document <- rg_document(ns, data, "count ~ x + school + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  df <- rg_value(rg_finding(document, "design.collinearity", term = "school"), "df")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"), "levels")
  d <- if (!is.null(df) && !is.null(levels)) rg_small_difference(df + 1, levels, k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d schools without an outcome", d))
}

rg_rows_levels_lost <- function(ns, root) {
  # The contributors case of round 6 with 9 levels of g: the 10 rows
  # without an outcome are the 10 levels of f with one row.
  r <- 1:168
  data <- data.frame(count = c(r %% 4, rep(NA, 10)), x = c(r %% 7 + 0.5, (1:10) / 3),
                     f = c(sprintf("F%02d", (r - 1) %% 40 + 1), sprintf("F%02d", 41:50)),
                     g = c(sprintf("G%02d", (r - 1) %% 42 + 1), sprintf("G%02d", 43:51), "G01"))
  document <- rg_document(ns, data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "f")
  analysis <- rg_finding(document, "outcome.zero_shares", factor = "f")
  vals <- list(nd = rg_value(sizes, "rows"), jd = rg_value(sizes, "levels"),
               s = rg_value(sizes, "singletons"), na = rg_value(analysis, "rows"),
               ja = rg_value(analysis, "levels"))
  if (any(vapply(vals, is.null, NA)) || vals$nd - vals$na != vals$jd - vals$ja) {
    return(rg_result(FALSE))
  }
  one <- vals$s - (vals$jd - vals$ja)
  rg_result(one < k, sprintf("%d levels of f with one analysed row", one))
}

rg_singletons_rows <- function(ns, root) {
  # 20 subjects of one row and 30 of two, the second outcome of 10 missing:
  # rows 80 and singletons 20 bound the levels by 50, the levels of the
  # analysis sample.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("s%02d", 1:30), each = 2))
  count <- seq_along(subject) %% 4
  count[21 + 2 * (0:9) + 1] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  rows <- rg_value(sizes, "rows")
  singletons <- rg_value(sizes, "singletons")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "subject"), "levels")
  leak <- !is.null(rows) && !is.null(singletons) && !is.null(levels) &&
    (rows + singletons) / 2 <= levels
  rg_result(leak, if (leak) "no subject lost every outcome")
}

rg_analysis_rows_levels <- function(ns, root) {
  # 12 subjects in the analysis sample, 9 of two rows and 3 of one, and 10
  # subjects of four rows without an outcome, so that the design sample
  # exceeds it by k or more. The contributors of the basis grouping_factors
  # are the levels of subject.
  subject <- c(rep(sprintf("s%02d", 1:9), each = 2), sprintf("t%02d", 1:3),
               rep(sprintf("u%02d", 1:10), each = 4))
  count <- c(seq_len(21) %% 4, rep(NA, 40))
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  rows <- rg_value(shares, "rows")
  levels <- rg_value(shares, "levels") %||% rg_value(shares, "support.distinct")
  leak <- !is.null(rows) && !is.null(levels) && rows < 2 * levels
  rg_result(leak, if (leak) sprintf("at least %d subjects of one analysed row, the smallest size 1",
                                    2 * levels - rows))
}

rg_non_person <- function(ns, root) {
  # 50 schools of two pupils of one row each, 9 pupils without an outcome in
  # 9 schools: the 50 schools, a non-person count, show 100 rows or more in
  # the design sample, which rule 1 hides as within k of the 91 analysed.
  school <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- seq_len(100) %% 4
  count[seq(1, 17, 2)] <- NA
  data <- data.frame(count = count, x = seq_len(100) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%03d", 1:100))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")))
  document <- rg_document(ns, data, "count ~ x + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.", declaration = declaration)
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "school")
  levels <- rg_value(sizes, "levels")
  rows <- rg_value(sizes, "rows")
  analysed <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"), "support.rows")
  leak <- !is.null(levels) && is.null(rows) && !is.null(analysed) &&
    identical(sizes$statistics$levels$count_class, "non_person") && 2 * levels >= analysed + k - 1
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", 2 * levels - analysed))
}

rg_crossed_analysis_levels <- function(ns, root) {
  # The reproducer of R1-crossed-combinations, with the levels of g and h
  # taken from outcome.zero_shares when the design sample hides them: each
  # is at least the analysis sample's, and the combinations of the design
  # sample, their product, exceed the analysis sample's by fewer than k. In
  # the second table every combination holds two rows, so that the 278
  # analysed rows are twice the 139 analysed combinations, rule 3 leaves
  # them and the clause of rule 1 on crossed columns alone hides them.
  cells <- expand.grid(g = sprintf("g%02d", 1:12), h = sprintf("h%02d", 1:12),
                       stringsAsFactors = FALSE)
  pairs <- rep(seq_len(nrow(cells)), each = 2)
  found <- character(0)
  for (rows in list(pairs[-1L], pairs)) {
    data <- cells[rows, ]
    data$pupil <- sprintf("p%03d", seq_len(nrow(data)))
    data$count <- seq_len(nrow(data)) %% 4
    data$x <- seq_len(nrow(data)) %% 7
    lost <- paste(cells$g, cells$h)[c(10, 30, 50, 70, 90)]
    data$count[paste(data$g, data$h) %in% lost] <- NA
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "pupil", columns = list("pupil"), role = "participant")))
    document <- rg_document(ns, data, "count ~ x + (1 | g) + (1 | h) + (1 | g:h)",
                            declaration = declaration, family = "poisson",
                            outcome_access = "T1", reason = "Zeros.")
    k <- document$privacy$min_count
    incidence <- rg_finding(document, "structure.label_incidence", first = "g", second = "h")
    if (!identical(rg_value(incidence, "relation"), "crossed")) {
      next
    }
    level <- function(side, factor) {
      written <- rg_value(incidence, side)
      if (!is.null(written)) return(written)
      a <- rg_value(rg_finding(document, "outcome.zero_shares", factor = factor), "levels")
      if (is.null(a)) NULL else a + 0:(k - 1)
    }
    first <- level("levels_first", "g")
    second <- level("levels_second", "h")
    analysis <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "g:h"), "levels")
    if (is.null(first) || is.null(second) || is.null(analysis)) {
      next
    }
    products <- unique(as.vector(outer(first, second)))
    products <- products[products >= analysis & products < analysis + k]
    if (length(products) == 1L) {
      found <- c(found, sprintf("%d combinations of %d rows lack an outcome", products - analysis,
                                nrow(data)))
    }
  }
  rg_result(length(found) > 0L, found)
}

# --- Round 7: the implementation of the two tiers ------------------------------------------

rg_unit_contributors <- function(ns, root) {
  # The table of R6-analysis-rows-levels with the subjects as the disclosure
  # unit, so that the contributors of the T1 findings are the analysed
  # subjects: 21 analysed rows beside 12 contributors show a subject of one
  # analysed row.
  subject <- c(rep(sprintf("s%02d", 1:9), each = 2), sprintf("t%02d", 1:3),
               rep(sprintf("u%02d", 1:10), each = 4))
  data <- data.frame(count = c(seq_len(21) %% 4, rep(NA, 40)),
                     x = seq_along(subject) %% 7 + 0.5, subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")))
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", declaration = declaration,
                          family = "poisson", outcome_access = "T1", reason = "Zeros.")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  rows <- rg_value(shares, "support.rows") %||% rg_value(shares, "rows")
  members <- rg_value(shares, "support.distinct") %||% rg_value(shares, "levels")
  leak <- !is.null(rows) && !is.null(members) && rows < 2 * members
  rg_result(leak, if (leak) sprintf("at least %d subjects of one analysed row", 2 * members - rows))
}

# The schools of R6-fixed-factor, of four pupils each, so that their counts
# resolve as non-person: df of design.collinearity, or dimension of
# identifiability.levels_vs_dimension when the schools are a categorical
# variable of a random term, gives the schools of the design sample, and
# the levels of outcome.zero_shares, or the levels with two rows of
# outcome.constant_clusters, which equal them for a non-person item, the
# analysed schools.
rg_school_variable <- function(ns, formula, columns) {
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- seq_len(200) %% 5
  count[school %in% sprintf("s%02d", 42:50)] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school,
                     district = sprintf("d%02d", rep(1:10, 20)), pupil = sprintf("p%03d", 1:200))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")))
  document <- rg_document(ns, data, formula, declaration = declaration, family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  design <- columns(document)
  analysed <- c(
    rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"), "levels"),
    rg_value(rg_finding(document, "outcome.constant_clusters", factor = "school"),
             "multi_row_levels"))
  found <- unlist(lapply(analysed, function(a) rg_small_difference(design, a, k)))
  rg_result(length(found) > 0L,
            if (length(found)) sprintf("%d schools without an outcome", found[1L]))
}

rg_fixed_factor_non_person <- function(ns, root) {
  rg_school_variable(ns, "count ~ x + school + (1 | school)", function(document) {
    df <- rg_value(rg_finding(document, "design.collinearity", term = "school"), "df")
    if (!is.null(df)) df + 1
  })
}

rg_random_variable <- function(ns, root) {
  rg_school_variable(ns, "count ~ x + (1 | school) + (0 + school | district)", function(document) {
    rg_value(rg_finding(document, "identifiability.levels_vs_dimension", factor = "district"),
             "dimension")
  })
}

rg_dominance <- function(ns, root) {
  # Two subjects of 50 rows and 10 of one row: the two largest hold 100 of
  # the 110 rows, so every finding whose support counts the subjects fails
  # the dominance rule and writes no real and no person count.
  subject <- c(rep(c("s01", "s02"), each = 50), sprintf("t%02d", 1:10))
  data <- data.frame(count = seq_along(subject) %% 4, x = seq_along(subject) %% 7 + 0.5,
                     subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  found <- character(0)
  for (finding in document$findings) {
    if (!isTRUE(finding$support$contributors$dominated) || !rg_available(finding)) {
      next
    }
    for (name in names(finding$statistics)) {
      s <- finding$statistics[[name]]
      if (!is.null(s$value) && (s$kind %in% c("real", "reals") ||
                                  (s$kind %in% c("count", "ratio") &&
                                     identical(s$count_class, "person")))) {
        found <- c(found, paste(finding$check, name))
      }
    }
  }
  rg_result(length(found) > 0L, if (length(found)) paste("written:", paste(found, collapse = ", ")))
}

rg_separation_interaction <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  # One kept column besides the intercept, which reads two variables: a
  # verdict of quasi or complete names a cell of x:z.
  x <- 1:40
  z <- 100 + (1:40) %% 7
  data <- data.frame(y = as.numeric(x * z > stats::median(x * z)), x = x, z = z)
  document <- rg_document(ns, data, "y ~ x:z", family = "binomial", outcome_access = "T2",
                          reason = "Separation.", exploratory = TRUE)
  leak <- rg_separating_verdict(document)
  rg_result(leak, if (leak) "complete on x:z: the events lie at one end of its values")
}

rg_separation_one_variable <- function(ns, root) {
  skip <- rg_needs_solver()
  if (!is.null(skip)) {
    return(skip)
  }
  # A factor whose 24 levels hold one row each, so that no two rows share
  # the values of the kept columns: the verdict shows that each level holds
  # one class.
  data <- data.frame(y = rep(c(1, 0), 12), g = sprintf("g%02d", 1:24))
  document <- rg_document(ns, data, "y ~ g", family = "binomial", outcome_access = "T2",
                          reason = "Separation.", exploratory = TRUE)
  leak <- rg_separating_verdict(document)
  rg_result(leak, if (leak) "complete with one factor of levels of one row")
}

rg_part_detail <- function(ns, root) {
  # Ten counts, none of them 0, for the model as a whole: zeros, a part of
  # the 10 written rows below k, keeps 'min_count' only if a part below k
  # had no other detail, and 'min_count' then shows that part_of did not
  # fire, so that the rows exceed the zeros by k or more and the zeros are
  # at most rows - k, here 0.
  data <- data.frame(count = c(1, 2, 3, 1, 2, 3, 1, 2, 3, 4), x = (1:10) / 3)
  document <- rg_document(ns, data, "count ~ x", family = "poisson", outcome_access = "T1",
                          reason = "Zeros.")
  k <- document$privacy$min_count
  shares <- rg_finding(document, "outcome.zero_shares")
  rows <- rg_value(shares, "rows")
  leak <- !is.null(rows) && identical(rg_detail(shares, "zeros"), "min_count") && rows - k < k - 1
  rg_result(leak, if (leak) sprintf("zeros at most %d", rows - k))
}

# --- Round 8 ---------------------------------------------------------------------------

rg_interaction <- function(ns, root) {
  # 99 cells of A and B of three rows, the cell (a10, b10) empty, and one
  # cell without an outcome: df 9 and 9 and empty_cells 1 give the 99 cells
  # of the design sample. A and B have k levels or more, so that rule 6 of
  # Across findings, which suppresses these counts beside levels below k,
  # leaves them written.
  cells <- expand.grid(A = sprintf("a%02d", 1:10), B = sprintf("b%02d", 1:10),
                       stringsAsFactors = FALSE)
  cells <- cells[!(cells$A == "a10" & cells$B == "b10"), ]
  data <- cells[rep(seq_len(nrow(cells)), each = 3), ]
  data$x <- seq_len(nrow(data)) %% 7 + 0.5
  data$count <- seq_len(nrow(data)) %% 4
  data$count[data$A == "a01" & data$B == "b01"] <- NA
  document <- rg_document(ns, data, "count ~ x + A * B + (1 | A:B)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  df <- function(term) rg_value(rg_finding(document, "design.collinearity", term = term), "df")
  empty <- rg_value(rg_finding(document, "design.rank_deficiency"), "empty_cells")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "A:B"), "levels")
  design <- if (!is.null(df("A")) && !is.null(df("B")) && !is.null(empty)) {
    (df("A") + 1) * (df("B") + 1) - empty
  }
  d <- rg_small_difference(design, levels, k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d cells without an outcome", d))
}

rg_sizes_two_rows <- function(ns, root) {
  # 20 subjects of one row and 40 of two, 10 of these without an outcome:
  # the rows minus the singletons, twice the levels with two rows, show that
  # no level holds three rows, so 50 analysed subjects of 80 rows hold 20 of
  # one row, which leaves no subject of two rows with one analysed row.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("t%02d", 1:40), each = 2))
  count <- seq_along(subject) %% 4
  count[subject >= "t31"] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  within <- rg_finding(document, "structure.within_between", factor = "subject", term = "x")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  v <- list(n = rg_value(sizes, "rows"), s = rg_value(sizes, "singletons"),
            two = rg_value(within, "multi_row_levels"), na = rg_value(shares, "rows"),
            ja = rg_value(shares, "levels"))
  if (any(vapply(v, is.null, NA)) || v$n - v$s != 2 * v$two) {
    return(rg_result(FALSE))
  }
  lost <- 2 * v$ja - v$na - v$s
  rg_result(lost >= 0 && lost < k,
            sprintf("%d analysed subjects of two rows lost one outcome", lost))
}

rg_sizes_firing <- function(ns, root) {
  # 40 subjects of two rows, 10 without an outcome and one without its
  # second: effective_size 2 with 80 rows and 40 levels gives every size as
  # 2, the 40 written levels leave at most 30 analysed subjects, and 59
  # analysed rows need 30, one of them with one row.
  subject <- rep(sprintf("s%02d", 1:40), each = 2)
  count <- seq_along(subject) %% 4
  count[subject >= "s31"] <- NA
  count[2] <- NA
  data <- data.frame(count = count, time = rep(0:1, 40), subject = subject)
  document <- rg_document(ns, data, "count ~ time + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  v <- list(n = rg_value(sizes, "rows"), j = rg_value(sizes, "levels"),
            e = rg_value(sizes, "effective_size"), na = rg_value(shares, "rows"))
  if (any(vapply(v, is.null, NA)) || !is.null(rg_value(shares, "levels")) ||
      v$n %% v$j != 0 || abs(v$e - v$n / v$j) > 1e-9) {
    return(rg_result(FALSE))
  }
  size <- v$n / v$j
  fewest <- ceiling(v$na / size)
  leak <- fewest == v$j - k
  rg_result(leak, if (leak) sprintf("%d analysed subjects, %d of one row", fewest,
                                    size * fewest - v$na))
}

rg_parts_variable <- function(ns, root) {
  # 50 schools of four rows, 40 with zero counts, every outcome present:
  # all_zero_levels 40 beside the hidden analysed levels shows 50 or more,
  # which df 49 bounds from above.
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- ifelse(school <= "s40", 0, seq_along(school) %% 3 + 1)
  data <- data.frame(count = count, x = seq_along(school) %% 7 + 0.5, school = school)
  document <- rg_document(ns, data, "count ~ x + school + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  df <- rg_value(rg_finding(document, "design.collinearity", term = "school"), "df")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "school")
  part <- rg_value(shares, "all_zero_levels")
  leak <- !is.null(df) && !is.null(part) && is.null(rg_value(shares, "levels")) &&
    part + k >= df + 1
  rg_result(leak, if (leak) sprintf("%d analysed schools", df + 1))
}

rg_parts_rule3 <- function(ns, root) {
  # 50 subjects of two rows, 30 with zero counts, 10 without an outcome and
  # one without its second: rule 3 hides the 40 analysed subjects beside 79
  # rows, which all_zero_levels 30 bounds from below by 40, and the 50
  # written levels of the design sample from above by 40.
  subject <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- ifelse(subject <= "s30", 0, seq_along(subject) %% 3 + 1)
  count[subject >= "s41"] <- NA
  count[80] <- NA
  data <- data.frame(count = count, time = rep(0:1, 50), subject = subject)
  document <- rg_document(ns, data, "count ~ time + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  design <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "levels")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  part <- rg_value(shares, "all_zero_levels")
  rows <- rg_value(shares, "rows")
  leak <- !is.null(part) && is.null(rg_value(shares, "levels")) && !is.null(rows) &&
    (rows < 2 * (part + k) || (!is.null(design) && part + k >= design - k))
  rg_result(leak, if (leak) sprintf("%d analysed subjects or more beside %d rows", part + k, rows))
}

rg_two_rows_variable <- function(ns, root) {
  # 30 schools of two rows and 20 of one, the 10 schools of one row s41 to
  # s50 without an outcome: 80 rows and df 49 bound the schools with two
  # rows of the design sample by 30, which outcome.constant_clusters writes
  # for the analysis sample.
  school <- c(rep(sprintf("s%02d", 1:30), each = 2), sprintf("s%02d", 31:50))
  y <- seq_along(school) / 7 + rep(c(0, 0.5), length.out = length(school))
  y[school <= "s10"] <- rep(seq(1, 10), each = 2)
  y[school >= "s41"] <- NA
  data <- data.frame(y = y, x = seq_along(school) %% 5 + 0.5, school = school)
  document <- rg_document(ns, data, "y ~ x + school + (1 | school)", outcome_access = "T1",
                          reason = "Constant levels.")
  df <- rg_value(rg_finding(document, "design.collinearity", term = "school"), "df")
  rows <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "school"), "rows")
  two <- rg_value(rg_finding(document, "outcome.constant_clusters", factor = "school"),
                  "multi_row_levels")
  leak <- !is.null(df) && !is.null(rows) && !is.null(two) && rows - (df + 1) == two
  rg_result(leak, if (leak) "no school with two rows lost an outcome")
}

rg_non_person_variable <- function(ns, root) {
  # 50 schools of two pupils, the disclosure unit, 9 pupils without an
  # outcome in 9 schools, school also a fixed term: df 49 and the class
  # non-person bound the hidden rows of the design sample by 100, which the
  # firing of rule 1 bounds by the 91 analysed rows plus k - 1.
  school <- rep(sprintf("s%02d", 1:50), each = 2)
  count <- seq_len(100) %% 4
  count[seq(1, 17, 2)] <- NA
  data <- data.frame(count = count, x = seq_len(100) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%03d", 1:100))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")))
  document <- rg_document(ns, data, "count ~ x + school + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.", declaration = declaration)
  k <- document$privacy$min_count
  df <- rg_value(rg_finding(document, "design.collinearity", term = "school"), "df")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "school")
  analysed <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"),
                       "support.rows")
  leak <- !is.null(df) && !is.null(analysed) && is.null(rg_value(sizes, "rows")) &&
    identical(sizes$statistics$levels$count_class, "non_person") &&
    2 * (df + 1) >= analysed + k - 1
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", 2 * (df + 1) - analysed))
}

rg_rule3_rows <- function(ns, root) {
  # 9 subjects of one row and one of two, every outcome present: a finding
  # that passes the minimum-count rule shows 10 subjects or more, which
  # beside 11 written rows hold 9 or more of one row.
  data <- data.frame(count = c(0, 1, 2, 3, 0, 1, 2, 3, 1, 2, 0), x = (1:11) / 3,
                     subject = c(sprintf("s%02d", 1:9), "s10", "s10"))
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  rows <- rg_value(shares, "support.rows") %||% rg_value(shares, "rows")
  distinct <- shares$support$contributors$distinct
  passes <- isTRUE(distinct$value >= k) || identical(distinct$availability$detail, "secondary")
  leak <- rg_available(shares) && !is.null(rows) && rows < 2 * k && passes
  rg_result(leak, if (leak) sprintf("%d rows of %d subjects or more", rows, k))
}

rg_chain_items <- function(ns, root) {
  # 20 subjects of one row and 30 of four rows: 10 of these lack the
  # covariate, or 9 lack it and one lacks every outcome.
  make <- function(y_missing) {
    g <- c(sprintf("o%02d", 1:20), rep(sprintf("s%02d", 1:30), each = 4))
    data <- data.frame(count = seq_along(g) %% 4, x = seq_along(g) %% 7 + 0.5, g = g)
    data$x[g %in% sprintf("s%02d", if (y_missing) 21:29 else 21:30)] <- NA
    if (y_missing) {
      data$count[g == "s30"] <- NA
    }
    list(data = data, formula = "count ~ x + (1 | g)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros."))
  }
  rg_pair(ns, list(make(FALSE), make(TRUE)),
          "the table's contributors tell 0 levels without an outcome from 1")
}

rg_column_levels <- function(ns, root) {
  # 40 subjects in 4 sites, site a fixed term and a declared cluster: step 3
  # suppresses its 4 levels, which structure.label_incidence counts as a
  # person count below k. The counts of the columns of site would give them
  # back (privacy.md, Across findings, rule 6): df 3 of design.collinearity,
  # kept and columns of design.rank_deficiency beside the intercept and the
  # column of treatment, J + 1 for the main effects and 2J with their
  # interaction, and budget of identifiability.df_budget, the 40 subjects
  # less the J columns of the intercept and site, which are constant within
  # the subjects, whatever the contrasts of site.
  subject <- sprintf("s%02d", rep(1:40, each = 5))
  site <- sprintf("S%d", (match(subject, unique(subject)) - 1L) %/% 10L + 1L)
  n <- length(subject)
  data <- data.frame(y = (seq_len(n) * 5L) %% 13L + 0.25,
                     treatment = ifelse(seq_len(n) %% 2 == 0, -0.5, 0.5), site = site,
                     subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")))
  designs <- list(
    treatment = list(formula = "y ~ treatment + site + (1 | subject)", coding = NULL, columns = 1),
    sum = list(formula = "y ~ treatment + site + (1 | subject)",
               coding = list(site = list(contrast = "sum")), columns = 1),
    interaction = list(formula = "y ~ treatment * site + (1 | subject)", coding = NULL,
                       columns = 2),
    # site2 copies site but lacks its label in one row, which leaves the
    # design sample, where site2 divides the rows as site does.
    copy = list(formula = "y ~ treatment + site2 + (1 | subject)", coding = NULL, columns = 1,
                term = "site2")
  )
  data$site2 <- replace(data$site, 1L, NA)
  found <- character(0)
  for (name in names(designs)) {
    design <- designs[[name]]
    args <- list(ns, data, design$formula, declaration = declaration)
    if (!is.null(design$coding)) {
      args$coding <- design$coding
    }
    document <- do.call(rg_document, args)
    k <- document$privacy$min_count
    incidence <- rg_finding(document, "structure.label_incidence", first = "site",
                            second = "subject")
    if (!is.null(rg_value(incidence, "levels_first"))) {
      next
    }
    # Each count gives J through the columns that the other terms add: the
    # intercept and treatment, which varies within the subjects.
    rank <- rg_finding(document, "design.rank_deficiency")
    budget <- rg_finding(document, "identifiability.df_budget", factor = "subject")
    df <- rg_value(rg_finding(document, "design.collinearity", term = design$term %||% "site"),
                   "df")
    kept <- rg_value(rank, "kept")
    columns <- rg_value(rank, "columns")
    levels <- rg_value(budget, "levels")
    left <- rg_value(budget, "budget")
    # The columns of site2 count the levels of the table, where site2 has
    # the sites of site, so columns gives them back too.
    recovered <- c(
      df = if (!is.null(df)) df + 1,
      kept = if (!is.null(kept)) if (design$columns == 1) kept - 1 else kept / 2,
      columns = if (!is.null(columns)) if (design$columns == 1) columns - 1 else columns / 2,
      budget = if (!is.null(levels) && !is.null(left)) levels - left
    )
    recovered <- recovered[recovered < k]
    if (length(recovered)) {
      found <- c(found, sprintf("%s: %d sites from %s", name, recovered[[1L]],
                                paste(names(recovered), collapse = ", ")))
    }
  }
  rg_result(length(found) > 0L, found)
}

rg_sizes_one_row <- function(ns, root) {
  # 20 subjects of one row and 50 of two, 10 of these without an outcome and
  # 10 without their second: no subject has three rows, as the rows minus the
  # singletons, twice the levels with two rows, show, so 60 analysed
  # subjects of 90 rows hold 30 of one row, a count that the document hides.
  subject <- c(sprintf("o%02d", 1:20), rep(sprintf("t%02d", 1:50), each = 2))
  count <- seq_along(subject) %% 4
  count[subject >= "t41"] <- NA
  count[subject %in% sprintf("t%02d", 31:40) & duplicated(subject)] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  within <- rg_finding(document, "structure.within_between", factor = "subject", term = "x")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  v <- list(n = rg_value(sizes, "rows"), s = rg_value(sizes, "singletons"),
            two = rg_value(within, "multi_row_levels"), na = rg_value(shares, "rows"),
            ja = rg_value(shares, "levels"))
  if (any(vapply(v, is.null, NA)) || v$n - v$s != 2 * v$two) {
    return(rg_result(FALSE))
  }
  rg_result(TRUE, sprintf("%d analysed subjects of one row", 2 * v$ja - v$na))
}

rg_hidden_levels <- function(ns, root) {
  # 20 subjects of two rows, 10 without an outcome and one without its
  # second: rule 3 hides the 10 analysed subjects beside 19 rows, and the
  # minimum-count rule, which the finding passes, shows 10 or more, so the
  # 20 written levels of the design sample, k or more above them, leave 10.
  subject <- rep(sprintf("s%02d", 1:20), each = 2)
  count <- seq_along(subject) %% 4
  count[subject >= "s11"] <- NA
  count[2] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  design <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "subject"), "levels")
  shares <- rg_finding(document, "outcome.zero_shares", factor = "subject")
  passes <- identical(shares$support$contributors$distinct$availability$detail, "secondary")
  leak <- !is.null(design) && rg_available(shares) && is.null(rg_value(shares, "levels")) &&
    passes && design - k <= k
  rg_result(leak, if (leak) sprintf("%d analysed subjects", design - k))
}

rg_reals_items <- function(ns, root) {
  # 20 subjects of four rows, 15 of which lose two outcomes each: the design
  # sample keeps its 80 rows, 30 above the analysed, but loses its 20
  # subjects beside the 20 analysed, and smallest_eigenvalue,
  # effective_size or icc, which with the rows give the levels of a balanced
  # design, would show that no subject lost every outcome. The attack tests
  # that none of them is written.
  subject <- rep(sprintf("s%02d", 1:20), each = 4)
  count <- seq_along(subject) %% 4
  count[subject <= "s15" & rep(1:4, 20) <= 2] <- NA
  data <- data.frame(count = count, x = seq_along(subject) %% 7 + 0.5, subject = subject)
  document <- rg_document(ns, data, "count ~ x + (1 | subject)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "subject")
  within <- rg_finding(document, "structure.within_between", factor = "subject", term = "x")
  written <- c(effective_size = !is.null(rg_value(sizes, "effective_size")),
               icc = !is.null(rg_value(within, "icc")),
               smallest_eigenvalue = !is.null(rg_value(rg_finding(document,
                                                                  "identifiability.gram_rank"),
                                                       "smallest_eigenvalue")))
  leak <- !is.null(rg_value(sizes, "rows")) && is.null(rg_value(sizes, "levels")) && any(written)
  rg_result(leak, if (leak) paste("written beside the hidden levels:",
                                  paste(names(written)[written], collapse = ", ")))
}

rg_non_person_members <- function(ns, root) {
  # 50 schools of two pupils of two rows each, 9 pupils without an outcome
  # in 9 schools: 18 rows lack an outcome, k or more, but 9 pupils, so the
  # design sample loses its pupils beside the 91 analysed, and 50 schools,
  # a non-person count of two pupils or more each, would show 100 pupils.
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  pupil <- rep(sprintf("p%03d", 1:100), each = 2)
  count <- seq_len(200) %% 4
  count[pupil %in% sprintf("p%03d", seq(1, 17, 2))] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school, pupil = pupil)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")))
  document <- rg_document(ns, data, "count ~ x + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.", declaration = declaration)
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "school")
  levels <- rg_value(sizes, "levels")
  analysed <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"),
                       "support.distinct")
  leak <- !is.null(levels) && is.null(rg_value(sizes, "support.distinct")) && !is.null(analysed) &&
    identical(sizes$statistics$levels$count_class, "non_person") && 2 * levels >= analysed + k - 1
  rg_result(leak, if (leak) sprintf("%d pupils without an outcome", 2 * levels - analysed))
}

rg_non_person_whole <- function(ns, root) {
  # At k = 3, 10 schools of two pupils of one row each, one school without an
  # outcome: the design sample loses its 20 rows beside the 18 analysed, k - 1
  # fewer, and every analysed school keeps two pupils, so that its schools
  # count non-persons and rule 2 hides nothing. 10 written schools of two
  # pupils or more would show 20 rows. With k = 10, k - 1 is odd and whole
  # schools of two pupils cannot lose k - 1 rows, so the attack sets k.
  old <- dh_set_k(ns, 3L)
  on.exit(dh_set_k(ns, old), add = TRUE)
  school <- rep(sprintf("s%02d", 1:10), each = 2)
  count <- seq_len(20) %% 4
  count[school == "s10"] <- NA
  data <- data.frame(count = count, x = seq_len(20) %% 7 + 0.5, school = school,
                     pupil = sprintf("p%02d", 1:20))
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
         role = "participant")))
  document <- rg_document(ns, data, "count ~ x + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.", declaration = declaration)
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "school")
  levels <- rg_value(sizes, "levels")
  analysed <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"), "support.rows")
  leak <- !is.null(levels) && is.null(rg_value(sizes, "rows")) && !is.null(analysed) &&
    identical(sizes$statistics$levels$count_class, "non_person") && 2 * levels >= analysed + k - 1
  rg_result(leak, if (leak) sprintf("%d rows without an outcome", 2 * levels - analysed))
}

rg_contributors_levels <- function(ns, root) {
  # Crossed factors f and g: 40 analysed rows in 20 levels of f and 22 of g,
  # each with k or more levels of one row and of two rows or more, and 20
  # rows without an outcome in 10 more levels of f and 9 more of g. The
  # design sample loses the levels of g, 31 beside 22 analysed, and keeps
  # those of f, 30 beside 20. Written contributors of 30, the levels of f,
  # would show that g has more than 30 levels, so 31, and that 9 lack an
  # outcome.
  f <- c(sprintf("f%02d", 1:10), rep(sprintf("f%02d", 11:20), each = 3),
         rep(sprintf("f%02d", 21:30), each = 2))
  g <- c(sprintf("g%02d", 1:12), rep(sprintf("g%02d", 13:20), each = 3),
         rep(sprintf("g%02d", 21:22), each = 2), sprintf("g%02d", 23 + (0:19) %% 9))
  data <- data.frame(count = c(seq_len(40) %% 4, rep(NA, 20)), x = seq_len(60) %% 7 + 0.5,
                     f = f, g = g)
  document <- rg_document(ns, data, "count ~ x + (1 | f) + (1 | g)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "g")
  contributors <- rg_value(sizes, "support.distinct")
  analysed <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "g"), "levels")
  leak <- is.null(rg_value(sizes, "levels")) && !is.null(contributors) && !is.null(analysed) &&
    contributors + 1 >= analysed + k - 1
  rg_result(leak, if (leak) sprintf("%d levels of g without an outcome", contributors + 1 - analysed))
}

# --- Round 9 ---------------------------------------------------------------------------

# The review of the port of the filter to Python found the clauses below
# untested or open.

rg_items_rows <- function(ns, root) {
  # A term's variables are matched to an item on the rows that its counts
  # read. cell labels the 99 combinations of A and B but lacks its label in
  # one row, which leaves the design sample, so A:B divides the design
  # sample, though not the table, into the levels of cell: kept 100 and
  # empty_cells 1 give its 99 combinations, which beside 98 analysed levels
  # show that one lacks an outcome. school2 copies the grouping factor
  # school but lacks a label in one row: df 49 beside 41 analysed schools
  # show that 9 lack an outcome.
  k <- NULL
  found <- character(0)
  cells <- expand.grid(B = sprintf("b%02d", 1:10), A = sprintf("a%02d", 1:10),
                       stringsAsFactors = FALSE)
  cells <- cells[!(cells$A == "a10" & cells$B == "b10"), ]
  last <- which(cells$A == "a09" & cells$B == "b10")
  cells <- rbind(cells[-last, ], cells[last, ])
  data <- cells[rep(seq_len(nrow(cells)), each = 3), c("A", "B")]
  n <- nrow(data)
  data$x <- seq_len(n) %% 7 + 0.5
  data$count <- seq_len(n) %% 4
  data$count[data$A == "a01" & data$B == "b01"] <- NA
  data$cell <- paste(data$A, data$B, sep = "-")
  data$cell[n] <- NA
  rownames(data) <- NULL
  document <- rg_document(ns, data, "count ~ x + A * B + (1 | cell)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  k <- document$privacy$min_count
  kept <- rg_value(rg_finding(document, "design.rank_deficiency"), "kept")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "cell"), "levels")
  d <- if (!is.null(kept) && !is.null(levels)) rg_small_difference(kept - 1, levels, k)
  if (!is.null(d)) {
    found <- c(found, sprintf("%d cells without an outcome", d))
  }
  school <- rep(sprintf("s%02d", 1:50), each = 4)
  count <- seq_len(200) %% 5
  count[school %in% sprintf("s%02d", 42:50)] <- NA
  data <- data.frame(count = count, x = seq_len(200) %% 7 + 0.5, school = school,
                     school2 = replace(school, 1L, NA))
  document <- rg_document(ns, data, "count ~ x + school2 + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.")
  df <- rg_value(rg_finding(document, "design.collinearity", term = "school2"), "df")
  levels <- rg_value(rg_finding(document, "outcome.zero_shares", factor = "school"), "levels")
  d <- if (!is.null(df) && !is.null(levels)) rg_small_difference(df + 1, levels, k)
  if (!is.null(d)) {
    found <- c(found, sprintf("%d schools without an outcome", d))
  }
  rg_result(length(found) > 0L, found)
}

# 50 schools of 4 pupils with 2 rows each, the pupils the unit to which treat
# is assigned, and 9 schools without the outcome or treat, so that the rows
# of the assignment are the analysis sample.
rg_school_assignment <- function() {
  school <- rep(sprintf("s%02d", 1:50), each = 8)
  pupil <- rep(sprintf("p%03d", 1:200), each = 2)
  data <- data.frame(count = seq_along(school) %% 4, school = school, pupil = pupil,
                     treat = ifelse(match(pupil, unique(pupil)) %% 2 == 0, "a", "b"))
  lacking <- school %in% sprintf("s%02d", 42:50)
  data$count[lacking] <- NA
  data$treat[lacking] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "school", columns = list("school"), role = "cluster"),
    list(name = "pupil", columns = list("pupil"), role = "cluster", nested_in = "school",
         id_scope = "global")),
    assignment = list(list(column = "treat", unit = "pupil", randomised = TRUE,
                           level = "between_unit")))
  list(data = data, declaration = declaration)
}

rg_analysis_columns <- function(ns, root) {
  # design_df on the analysed rows is the analysed pupils less the kept
  # columns of the intercept and school, which are constant within the
  # pupils, so units - design_df gives the 41 analysed schools, which beside
  # the 50 that kept of design.rank_deficiency counts in the design sample
  # show that 9 lack an outcome.
  case <- rg_school_assignment()
  document <- rg_document(ns, case$data, "count ~ school + (1 | school)", family = "poisson",
                          outcome_access = "T1", reason = "Zeros.",
                          declaration = case$declaration)
  k <- document$privacy$min_count
  assignment <- rg_finding(document, "assignment.design_df", column = "treat")
  units <- rg_value(assignment, "units")
  df <- rg_value(assignment, "design_df")
  kept <- rg_value(rg_finding(document, "design.rank_deficiency"), "kept")
  d <- if (!is.null(units) && !is.null(df) && !is.null(kept)) {
    rg_small_difference(kept, units - df, k)
  }
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d schools without an outcome", d))
}

rg_table_levels <- function(ns, root) {
  # 12 sites crossed with 20 districts, 2 rows each, and x missing in every
  # row of one site: dimension 12 of (0 + site | district) counts the sites
  # of the table, which rule 1 hides beside the 11 sites that
  # structure.cluster_sizes counts in the design sample.
  rows <- expand.grid(rep = 1:2, site = sprintf("S%02d", 1:12),
                      district = sprintf("d%02d", 1:20), stringsAsFactors = FALSE)
  n <- nrow(rows)
  data <- data.frame(y = (seq_len(n) * 7) %% 11 + 0.5, x = seq_len(n) %% 5 + 0.25,
                     site = rows$site, district = rows$district)
  data$x[data$site == "S12"] <- NA
  document <- rg_document(ns, data, "y ~ x + (0 + site | district) + (1 | site)")
  k <- document$privacy$min_count
  dimension <- rg_value(rg_finding(document, "identifiability.levels_vs_dimension",
                                   factor = "district"), "dimension")
  levels <- rg_value(rg_finding(document, "structure.cluster_sizes", factor = "site"), "levels")
  d <- if (!is.null(dimension) && !is.null(levels)) rg_small_difference(dimension, levels, k)
  rg_result(!is.null(d), if (!is.null(d)) sprintf("%d sites that x removes", d))
}

rg_failing_levels <- function(ns, root) {
  # 12 sites of 2 rows and a grouping factor g2 of 3 levels, so that every
  # finding fails the minimum-count rule, which hides the 12 sites of
  # structure.cluster_sizes, and df + 1 would give them back.
  site <- rep(sprintf("S%02d", 1:12), each = 2)
  data <- data.frame(y = (seq_along(site) * 7) %% 11 + 0.5, x = seq_along(site) %% 5 + 0.25,
                     site = site, g2 = rep(c("g1", "g2", "g3"), 8))
  document <- rg_document(ns, data, "y ~ x + site + (1 | g2) + (1 | site)")
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "site")
  df <- rg_value(rg_finding(document, "design.collinearity", term = "site"), "df")
  kept <- rg_value(rg_finding(document, "design.rank_deficiency"), "kept")
  hidden <- is.null(rg_value(sizes, "levels"))
  recovered <- c(df = if (!is.null(df)) df + 1, kept = if (!is.null(kept)) kept - 1)
  leak <- hidden && length(recovered) > 0L
  rg_result(leak, if (leak) sprintf("%d sites from %s", recovered[[1L]],
                                    paste(names(recovered), collapse = ", ")))
}

rg_assignment_levels <- function(ns, root) {
  # 12 sites of 10 subjects with 2 rows each. dose, assigned to the
  # subjects, and arm, assigned to the sites, are both missing for the first
  # subject of every site, so their rows are one sample, which keeps the 12
  # sites. Rule 1 hides its sites beside the design sample's, and
  # units - design_df of dose would give them back.
  site <- rep(sprintf("S%02d", 1:12), each = 20)
  subject <- rep(sprintf("u%03d", 1:120), each = 2)
  data <- data.frame(y = (seq_along(site) * 7) %% 11 + 0.5, site = site, subject = subject,
                     dose = ifelse(match(subject, unique(subject)) %% 2 == 0, "lo", "hi"),
                     arm = ifelse(match(site, unique(site)) %% 2 == 0, "a", "b"))
  first <- subject %in% sprintf("u%03d", seq(1, 120, by = 10))
  data$dose[first] <- NA
  data$arm[first] <- NA
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")),
    assignment = list(
      list(column = "dose", unit = "subject", randomised = TRUE, level = "between_unit"),
      list(column = "arm", unit = "site", randomised = TRUE, level = "between_unit")))
  document <- rg_document(ns, data, "y ~ site + (1 | subject)", declaration = declaration)
  k <- document$privacy$min_count
  dose <- rg_finding(document, "assignment.design_df", column = "dose")
  units <- rg_value(dose, "units")
  df <- rg_value(dose, "design_df")
  levels <- rg_value(rg_finding(document, "structure.label_incidence", first = "site"),
                     "levels_first")
  d <- if (!is.null(units) && !is.null(df) && !is.null(levels)) {
    rg_small_difference(levels, units - df, k)
  }
  rg_result(!is.null(d), if (!is.null(d)) {
    sprintf("%d sites without the assigned columns", d)
  })
}

rg_combination_levels <- function(ns, root) {
  # 13 subjects, the disclosure unit, each with a row in each combination of
  # A, of 2 levels, and B, of 3, apart from (a2, b3), which one subject
  # holds. The combinations are a grouping factor whose levels step 3 hides
  # as a person count of 6, which the levels of A and B, df + 1 of each,
  # less empty_cells would give back.
  combos <- expand.grid(B = c("b1", "b2", "b3"), A = c("a1", "a2"), stringsAsFactors = FALSE)
  rows <- list()
  for (s in 1:13) {
    for (j in seq_len(nrow(combos))) {
      if (s < 13 && combos$A[j] == "a2" && combos$B[j] == "b3") {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(subject = sprintf("s%02d", s), A = combos$A[j],
                                              B = combos$B[j])
    }
  }
  data <- do.call(rbind, rows)
  data$x <- seq_len(nrow(data)) %% 5 + 0.5
  data$y <- (seq_len(nrow(data)) * 7) %% 11 + 0.5
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")))
  document <- rg_document(ns, data, "y ~ x + A * B + (1 | subject) + (1 | A:B)",
                          declaration = declaration)
  sizes <- rg_finding(document, "structure.cluster_sizes", factor = "A:B")
  empty <- rg_value(rg_finding(document, "design.rank_deficiency"), "empty_cells")
  a <- rg_value(rg_finding(document, "design.collinearity", term = "A"), "df")
  b <- rg_value(rg_finding(document, "design.collinearity", term = "B"), "df")
  leak <- is.null(rg_value(sizes, "levels")) && !is.null(empty) && !is.null(a) && !is.null(b)
  rg_result(leak, if (leak) {
    sprintf("%d combinations from df and empty_cells", (a + 1) * (b + 1) - empty)
  })
}

rg_column_detail <- function(ns, root) {
  # 18 subjects of two rows nested in 9 sites, site a fixed term and a
  # declared unit: step 3 hides the 9 sites of structure.label_incidence,
  # and budget 9 of identifiability.df_budget with the detail 'min_count'
  # would show that 18 - 9 sites are below k, so that the sites are 9.
  subject <- rep(sprintf("s%02d", 1:18), each = 2)
  data <- data.frame(y = (seq_along(subject) * 7) %% 11 + 0.5,
                     treatment = rep(c(-0.5, 0.5), 18),
                     site = rep(sprintf("S%d", 1:9), each = 4), subject = subject)
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "site", columns = list("site"), role = "cluster"),
    list(name = "subject", columns = list("subject"), role = "cluster", nested_in = "site",
         id_scope = "global")))
  document <- rg_document(ns, data, "y ~ treatment + site + (1 | subject)",
                          declaration = declaration)
  k <- document$privacy$min_count
  budget <- rg_finding(document, "identifiability.df_budget", factor = "subject")
  incidence <- rg_finding(document, "structure.label_incidence", first = "site")
  levels <- rg_value(budget, "levels")
  leak <- identical(rg_detail(budget, "budget"), "min_count") &&
    identical(rg_detail(incidence, "levels_first"), "min_count") && !is.null(levels) &&
    levels - (k - 1L) == k - 1L
  rg_result(leak, if (leak) sprintf("%d sites", k - 1L))
}

rg_chain_assignment <- function(ns, root) {
  # 50 subjects of four rows, the unit to which z is assigned, z missing for
  # s50. s01 lacks the covariate, or the outcome: the design sample loses
  # its subjects beside the 49 analysed ones either way, and the rows of the
  # assignment, which lie in it but leave out s50, lose them beside the
  # analysis sample, 48 or 49 subjects that would otherwise tell the two
  # tables apart.
  make <- function(y_missing) {
    subject <- rep(sprintf("s%02d", 1:50), each = 4)
    data <- data.frame(count = rep(c(0, 1, 2, 3), 50), x = seq_len(200) %% 7 + 0.5,
                       subject = subject,
                       z = ifelse(match(subject, unique(subject)) %% 2 == 0, "a", "b"))
    data$z[subject == "s50"] <- NA
    if (y_missing) {
      data$count[subject == "s01"] <- NA
    } else {
      data$x[subject == "s01"] <- NA
    }
    declaration <- list(vocabulary = "0.1.0", units = list(
      list(name = "subject", columns = list("subject"), role = "participant")),
      assignment = list(list(column = "z", unit = "subject", randomised = TRUE,
                             level = "between_unit")))
    list(data = data, formula = "count ~ x + (1 | subject)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros.",
                     declaration = declaration))
  }
  rg_pair(ns, list(make(FALSE), make(TRUE)),
          "the units of the assignment tell 0 subjects without an outcome from 1")
}

rg_propagate_rows <- function(ns, root) {
  # 12 subjects of two rows, each with at least one outcome: 13 or 15
  # analysed rows, which rule 3 hides beside 12 contributors. The design
  # sample's 24 rows are hidden beside 15 by rule 1 and beside 13 because
  # the analysis sample hides its rows, so that they would otherwise tell
  # the two tables apart.
  make <- function(second) {
    subject <- rep(sprintf("s%02d", 1:12), each = 2)
    count <- rep(c(1, 2), 12)
    count[seq(2, 24, by = 2)[-seq_len(second)]] <- NA
    list(data = data.frame(count = count, x = seq_len(24) %% 5 + 0.5, subject = subject),
         formula = "count ~ x + (1 | subject)",
         args = list(family = "poisson", outcome_access = "T1", reason = "Zeros."))
  }
  rg_pair(ns, list(make(1L), make(3L)),
          "the design sample's rows tell 13 analysed rows from 15")
}
