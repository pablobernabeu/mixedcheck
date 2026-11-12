# Attack (d), mutation testing of the filter (sim/disclosure/README.md). Each
# mutant disables one rule of the privacy filter (r/R/privacy.R,
# r/R/privacy-across.R and the writer of findings in r/R/checks.R), of the
# shareable IR hash or of the validator (r/R/results-validate.R) by
# replacing a function of the loaded namespace in the harness alone, either
# by a function that skips the rule or by a copy of the function whose text
# has one condition changed. The package's files are never changed. A mutant
# whose text pattern no longer occurs in its function fails to install, so
# that a change to the filter that moves a rule shows in the mutation run.

# A copy of a function of the namespace with each fixed string 'from'
# replaced by 'to' in its deparsed text.
dm_patch <- function(ns, name, from, to) {
  f <- get(name, envir = ns)
  text <- paste(deparse(f, width.cutoff = 500L), collapse = "\n")
  for (i in seq_along(from)) {
    if (!grepl(from[i], text, fixed = TRUE)) {
      stop(sprintf("mutant pattern not found in %s: %s", name, from[i]), call. = FALSE)
    }
    text <- gsub(from[i], to[i], text, fixed = TRUE)
  }
  g <- eval(parse(text = text))
  environment(g) <- ns
  g
}

dm_identity <- function(argument) {
  force(argument)
  function(...) list(...)[[1L]]
}

# The mutants: an identifier, the rule of privacy.md or documents.md that it
# disables, a function that returns the replacements, by name, and the tier
# of the values that the rule protects (privacy.md, Tiers): 'A' when it
# protects outcome-derived values, alone or with design-structure values,
# and 'B' when it protects design-structure values alone. mutate.R requires
# an attack to detect every mutant of tier A that the registry can reach:
# reachable is FALSE for a rule that no document of registry 0.1.0 can
# exercise.
dm_mutants <- function() {
  m <- function(id, rule, replace, tier = "A", reachable = TRUE) {
    list(id = id, rule = rule, replace = replace, tier = tier, reachable = reachable)
  }
  list(
    m("step-1", "Steps 1: internal_only", function(ns) list(
      privacy_internal_only = function(finding) finding)),
    m("step-2", "Steps 2: minimum count and dominance", function(ns) list(
      privacy_minimum_rules = function(finding, k) finding)),
    m("step-2-minimum", "Steps 2: the minimum-count rule alone", function(ns) {
      original <- get("privacy_minimum_rules", envir = ns)
      list(privacy_minimum_rules = function(finding, k) {
        support <- finding$support
        finding$support$distinct <- max(support$distinct, k)
        out <- original(finding, k)
        out$support <- support
        out
      })
    }),
    m("step-2-dominance", "Steps 2: the dominance rule alone", function(ns) {
      original <- get("privacy_minimum_rules", envir = ns)
      list(privacy_minimum_rules = function(finding, k) {
        support <- finding$support
        finding$support$dominated <- FALSE
        out <- original(finding, k)
        out$support <- support
        out
      })
    }),
    m("step-3", "Steps 3: person counts below k", function(ns) list(
      privacy_small_counts = function(finding, k) finding)),
    m("step-3-support", "Steps 3: support.rows and support.contributors.distinct below k",
      function(ns) list(privacy_small_counts = dm_patch(ns, "privacy_small_counts",
        "if (finding$support[[member]] < k)", "if (FALSE)"))),
    m("step-3-quantile-exception", "Steps 3: quantiles left to step 4", function(ns) list(
      privacy_small_counts = dm_patch(ns, "privacy_small_counts",
        "!privacy_quantile_hidden(finding, name, k)", "TRUE"))),
    m("step-4", "Steps 4: the quantile rule", function(ns) list(
      privacy_quantiles = function(finding, k) finding)),
    m("step-5", "Steps 5: ratios", function(ns) list(
      privacy_ratios = function(finding, k) finding)),
    m("within-suppress-with", "Within a finding: suppress_with", function(ns) list(
      privacy_within = dm_patch(ns, "privacy_within", "if (length(with)) {", "if (FALSE) {"))),
    m("within-suppress-with-detail", "Within a finding: 'secondary' in place of 'min_count'",
      function(ns) list(privacy_within = dm_patch(ns, "privacy_within",
        "if (identical(finding$suppressed[[name]], \"min_count\") && any(back | finding$suppressed[with] != \"min_count\")) {",
        "if (FALSE) {"))),
    m("within-parts-detail", "Within a finding: 'secondary' on both parts of a total",
      function(ns) list(privacy_within = dm_patch(ns, "privacy_within",
        "any(back | finding$suppressed[with] != \"min_count\")",
        "any(!back & finding$suppressed[with] != \"min_count\")"))),
    m("within-part-of", "Within a finding: part_of", function(ns) list(
      privacy_within = dm_patch(ns, "privacy_within",
        "if (length(left) && (any(value - counts < k) || value - sum(counts) < k)) {",
        "if (FALSE) {"))),
    m("within-part-detail", "Within a finding: 'secondary' on a part of a person total below k",
      function(ns) list(privacy_within = dm_patch(ns, "privacy_within",
        "finding <- privacy_suppress(finding, small, \"secondary\", replace = TRUE)", "NULL"))),
    m("within-quantile-n", "Within a finding: the n of quantiles", function(ns) list(
      privacy_within = dm_patch(ns, "privacy_within",
        "if (!is.null(n) && n %in% names(finding$suppressed)) {", "if (FALSE) {"))),
    m("within-quantile-detail", "Within a finding: 'quantile' in place of 'min_count'",
      function(ns) list(privacy_within = dm_patch(ns, "privacy_within",
        "finding$suppressed[name] <- \"quantile\"", "NULL"))),
    m("across", "Across findings: every rule", function(ns) list(
      privacy_across = function(run, findings, k) findings)),
    m("across-1", "Across findings: rule 1", function(ns) list(
      privacy_comparisons = function(samples, main) list())),
    m("across-1-analysis", "Across findings: rule 1 beside the analysis sample", function(ns) list(
      privacy_lost = dm_patch(ns, "privacy_lost", "if (!shown) {", "if (TRUE) {"))),
    m("across-1-analysis-rows", "Across findings: rule 1 on rows beside the analysis sample",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if (privacy_close(larger[[member]], smaller[[member]], k)) {",
        "if (member != \"rows\" && privacy_close(larger[[member]], smaller[[member]], k)) {"))),
    # The contributors are the rows, the levels of a grouping factor or the
    # levels of the disclosure unit, which rule 1 compares beside the
    # analysis sample in their own right, so that in registry 0.1.0 no
    # document tells this comparison from those.
    m("across-1-analysis-contributors",
      "Across findings: rule 1 on contributors beside the analysis sample",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if (privacy_close(larger[[member]], smaller[[member]], k)) {",
        "if (member != \"contributors\" && privacy_close(larger[[member]], smaller[[member]], k)) {")),
      reachable = FALSE),
    m("across-1-analysis-levels", "Across findings: rule 1 on levels beside the analysis sample",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if (privacy_close(larger$items[[i]][[measure]], smaller$items[[i]][[measure]], k)) {",
        "if (FALSE) {"))),
    m("across-1-non-person", "Across findings: rule 1 on non-person items beside the analysis sample",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if (lost[[loser]]$rows || lost[[loser]]$contributors) {", "if (FALSE) {"))),
    m("across-1-sizes", "Across findings: rule 1, the sizes of the levels beside the analysed rows",
      function(ns) list(privacy_sizes_close = function(codes, larger_rows, analysis_rows, person,
                                                       k) FALSE)),
    m("across-1-sizes-one-row",
      "Across findings: rule 1, the sizes of the levels beside the analysed levels with one row",
      function(ns) list(privacy_sizes_close = dm_patch(ns, "privacy_sizes_close",
        "fewest == most", "FALSE"))),
    m("across-1-chain", "Across findings: rule 1, a quantity lost beside the analysis sample",
      function(ns) list(
        privacy_lost = dm_patch(ns, "privacy_lost", "for (comparison in comparisons[!beside]) {",
                                "for (comparison in list()) {"),
        privacy_rule_1 = dm_patch(ns, "privacy_rule_1",
          c("!lost[[larger]][[member]] && !lost[[smaller]][[member]] && ",
            "!lost[[larger]]$items[[i]][[measure]] && !lost[[smaller]]$items[[i]][[measure]] && "),
          c("", "")))),
    m("across-1-chain-rows", "Across findings: rule 1, rows or contributors lost beside the analysis sample",
      function(ns) list(privacy_rule_1 = dm_patch(ns, "privacy_rule_1",
        "!lost[[larger]][[member]] && !lost[[smaller]][[member]] && ", ""))),
    m("across-1-chain-items", "Across findings: rule 1, levels lost beside the analysis sample",
      function(ns) list(privacy_rule_1 = dm_patch(ns, "privacy_rule_1",
        "!lost[[larger]]$items[[i]][[measure]] && !lost[[smaller]]$items[[i]][[measure]] && ",
        ""))),
    m("across-1-crossed", "Across findings: rule 1, the combinations of crossed columns",
      function(ns) list(privacy_written_items = dm_patch(ns, "privacy_written_items",
        "if (finding$check != \"structure.label_incidence\" ||", "if (TRUE ||"))),
    m("across-1-variable", "Across findings: rule 1, a categorical variable that divides the rows as an item",
      function(ns) list(privacy_written_items = dm_patch(ns, "privacy_written_items",
        "for (i in privacy_variable_items(run, items)) {", "for (i in integer(0)) {"))),
    m("across-1-variable-class",
      "Across findings: rule 1, a categorical variable that divides the rows as a non-person item",
      function(ns) list(privacy_analysis_marks = dm_patch(ns, "privacy_analysis_marks",
        "if (privacy_close(larger$items[[i]]$levels, smaller$items[[i]]$levels, k)) {",
        "if (larger$items[[i]]$person && privacy_close(larger$items[[i]]$levels, smaller$items[[i]]$levels, k)) {"))),
    m("across-1-variable-random",
      "Across findings: rule 1, a categorical variable of a random term that divides the rows as an item",
      function(ns) list(privacy_variable_items = dm_patch(ns, "privacy_variable_items",
        "unlist(lapply(run$ir$random, function(random) random$terms), recursive = FALSE)",
        "list()"))),
    m("across-1-variable-combination",
      "Across findings: rule 1, the combination of the categorical variables of a term",
      function(ns) list(privacy_variable_items = dm_patch(ns, "privacy_variable_items",
        "if (length(categorical) > 1L) {", "if (FALSE) {"))),
    m("across-1-propagate", "Across findings: rule 1, the quantities that the analysis sample loses",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if (hidden$items[[i]][[measure]] && larger$items[[i]][[measure]] > 0) {", "if (FALSE) {"))),
    m("across-1-written-rows",
      "Across findings: rule 1, the rows that the written levels of an item bound",
      function(ns) list(privacy_analysis_marks = dm_patch(ns, "privacy_analysis_marks",
        "if (privacy_close(larger$rows, analysis$rows, k) && least > analysis$rows) {",
        "if (FALSE) {"))),
    m("across-1-between", "Across findings: rule 1 between samples other than the analysis sample",
      function(ns) list(privacy_rule_1 = function(quantities, comparisons, lost, marks, k) marks),
      tier = "B"),
    m("across-1-class", "Across findings: rule 1 on the class of the larger sample",
      function(ns) list(privacy_rule_1 = dm_patch(ns, "privacy_rule_1",
        "if (!quantities[[larger]]$items[[i]]$person) {",
        "if (!quantities[[smaller]]$items[[i]]$person) {")), tier = "B"),
    m("across-2", "Across findings: rule 2", function(ns) list(
      privacy_rule_2 = function(quantity, marks, k) marks)),
    m("across-2-two-rows-below-k", "Across findings: rule 2 when the levels with two rows are below k",
      function(ns) list(privacy_rule_2 = dm_patch(ns, "privacy_rule_2",
        "small <- item$levels_with_one_row < k || item$levels_with_two_rows < k",
        "small <- item$levels_with_one_row < k"))),
    m("across-2-non-person", "Across findings: rule 2 for a non-person item",
      function(ns) list(privacy_rule_2 = dm_patch(ns, "privacy_rule_2",
        "else if (any(hidden[1:2])) {", "else if (FALSE) {"))),
    # In registry 0.1.0 a sample other than the analysis sample loses its
    # levels or its levels with two rows only beside the analysis sample,
    # where rule 5 hides every count of the item, and the analysis sample
    # loses its levels under rule 3 only when the first clause of rule 2
    # hides both parts. Beside levels that the columns of a term write, the
    # written levels with two rows bound the hidden analysed levels only from
    # below, by k or more less than the written ones. No document tells these
    # two clauses from those rules.
    m("across-2-levels", "Across findings: rule 2, the levels with two rows when the levels are hidden",
      function(ns) list(privacy_rule_2 = dm_patch(ns, "privacy_rule_2",
        "if (small || hidden[[\"levels\"]]) {", "if (small) {")), reachable = FALSE),
    m("across-2-two-rows",
      "Across findings: rule 2, the levels with one row when the levels with two rows are hidden",
      function(ns) list(privacy_rule_2 = dm_patch(ns, "privacy_rule_2",
        "if (small || hidden[[\"levels_with_two_rows\"]]) {", "if (small) {")),
      reachable = FALSE),
    m("across-3", "Across findings: rule 3", function(ns) list(
      privacy_rule_3 = function(quantity, design, marks, quartiles, k) marks)),
    m("across-3-rows", "Across findings: rule 3, the analysed rows fewer than 2k",
      function(ns) list(privacy_rule_3 = dm_patch(ns, "privacy_rule_3",
        "if (quantity$rows < 2 * k && quantity$contributors >= k) {", "if (FALSE) {"))),
    m("across-parts", "Across findings: the parts of a count that the rules hide in the analysis sample",
      function(ns) list(privacy_across_finding = dm_patch(ns, "privacy_across_finding",
        "if (sample == \"analysis\") {", "if (FALSE) {"))),
    m("across-detail", "Across findings: 'secondary' in place of 'min_count'",
      function(ns) list(privacy_across_finding = dm_patch(ns, "privacy_across_finding",
        "finding <- privacy_suppress(finding, name, \"secondary\", replace = TRUE)",
        "finding <- privacy_suppress(finding, name, \"secondary\")"))),
    m("across-measures", "Across findings: counts that measure a suppressed quantity",
      function(ns) list(privacy_across_finding = dm_patch(ns, "privacy_across_finding",
        "if (suppressed) {", "if (FALSE) {"))),
    m("across-support", "Across findings: the support of a sample that loses its value",
      function(ns) list(privacy_across_finding = dm_patch(ns, "privacy_across_finding",
        "if (marks[[own]][[quantity]] && (is.na(detail) || (member == \"rows\" && detail == \"min_count\"))) {",
        "if (FALSE) {"))),
    m("across-basis", "Across findings: the contributors of the basis grouping_factors",
      function(ns) list(privacy_across_finding = dm_patch(ns, "privacy_across_finding",
        "quantities[[own]]$items[[i]]$levels == finding$support$distinct", "FALSE"))),
    m("across-basis-unit", "Across findings: the contributors of the basis disclosure_unit",
      function(ns) list(
        privacy_across_finding = dm_patch(ns, "privacy_across_finding",
          "disclosure_unit = unit_item[!is.na(unit_item)]", "disclosure_unit = integer(0)"),
        privacy_lost = dm_patch(ns, "privacy_lost", " || identical(i, unit_item)", ""))),
    m("across-4", "Across findings: rule 4", function(ns) list(
      privacy_missing_key_close = function(run, samples, k) FALSE)),
    m("across-4-chain", "Across findings: rule 4 for a sample that loses its rows",
      function(ns) list(privacy_across = dm_patch(ns, "privacy_across",
        "s != \"table\" && (s != \"analysis\" || shown) && !lost[[s]]$rows",
        "s != \"table\" && (s != \"analysis\" || shown)"))),
    m("across-5-reals", "Across findings: rule 5, the reals of a sample that loses its rows",
      function(ns) list(privacy_rule_5 = dm_patch(ns, "privacy_rule_5",
        "if (lost$rows) {", "if (FALSE) {"))),
    m("across-5-reals-items", "Across findings: rule 5, the reals that read a lost item",
      function(ns) list(privacy_rule_5 = dm_patch(ns, "privacy_rule_5",
        "names <- c(counted, combined, if (reads_item) reals)",
        "names <- c(counted, combined)"))),
    m("across-5-counts", "Across findings: rule 5, every count of the levels of a lost item",
      function(ns) list(
        privacy_lost = dm_patch(ns, "privacy_lost", "lost[[s]]$items[[i]][] <- TRUE", "NULL"),
        privacy_rule_5 = dm_patch(ns, "privacy_rule_5",
          "isTRUE(defined[[name]][[\"measures\"]] %in% privacy_measures) &&", "FALSE &&"))),
    m("across-5-parts", "Across findings: rule 5, the parts of a count of the levels of a lost item",
      function(ns) list(privacy_rule_5 = dm_patch(ns, "privacy_rule_5",
        "if (!length(parts)) {", "if (TRUE) {"))),
    m("across-5-combined", "Across findings: rule 5, the counts of an item that combines a lost item",
      function(ns) list(privacy_rule_5 = dm_patch(ns, "privacy_rule_5",
        "names <- c(counted, combined, if (reads_item) reals)",
        "names <- c(counted, if (reads_item) reals)"))),
    m("across-5-contributors", "Across findings: rule 5, the contributors that count a lost item",
      function(ns) list(privacy_lost = dm_patch(ns, "privacy_lost",
        "if ((identical(basis, \"grouping_factors\") && i %in% factor_items) || identical(i, unit_item)) {",
        "if (FALSE) {"))),
    m("step-8", "Steps 8: absent statistics", function(ns) list(
      privacy_absent = function(finding) finding)),
    m("step-8-internal-only", "Steps 8: absent internal_only statistics",
      function(ns) list(privacy_absent = dm_patch(ns, "privacy_absent",
        "if (isTRUE(statistic[[\"internal_only\"]])) {", "if (FALSE) {"))),
    m("decision", "Decisions: every rule", function(ns) list(
      privacy_decision = function(finding, run, k) finding)),
    m("decision-t1", "Decisions: a T1 or T2 finding that rests on a suppressed count",
      function(ns) list(privacy_decision = dm_patch(ns, "privacy_decision",
        "if (any(hidden) ||", "if (FALSE ||"))),
    m("separation", "Decisions: outcome.separation", function(ns) list(
      privacy_separation = function(finding, run, k) FALSE)),
    m("separation-kept", "Decisions: outcome.separation with at most two kept columns",
      function(ns) list(privacy_separation = dm_patch(ns, "privacy_separation",
        c("if (kept <= 2 || sum(run$analysis_kept) <= 2 ||"), c("if (FALSE ||")))),
    m("separation-one-variable", "Decisions: outcome.separation on one variable",
      function(ns) list(separation_one_variable = function(run, kept) FALSE)),
    m("separation-shared-values", "Decisions: outcome.separation with rows of equal values",
      function(ns) list(separation_shared_values = function(x) FALSE)),
    m("separation-analysis", "Decisions: outcome.separation on the analysis sample",
      function(ns) list(privacy_separation = dm_patch(ns, "privacy_separation",
        c("sum(run$analysis_kept) <= 2 ||",
          "separation_one_variable(run, run$analysis_kept) ||",
          "separation_shared_values(run$x[analysis, run$analysis_kept, drop = FALSE])"),
        c("FALSE ||", "FALSE ||", "FALSE")))),
    m("separation-binomial", "Decisions: binomial rows without events, non-events or with both",
      function(ns) list(privacy_separation = dm_patch(ns, "privacy_separation",
        "any(c(rows - events, rows - non_events, events + non_events - rows) < k)", "FALSE"))),
    m("step-11-messages", "Steps 11: messages rendered from the written values",
      function(ns) list(privacy_render = dm_patch(ns, "privacy_render",
        "written <- Filter(function(name) privacy_written(finding, name), names(finding$values))",
        "written <- names(finding$values)"))),
    m("step-11-quantile-n", "Steps 11: the n of a quantile only beside its count",
      function(ns) list(document_finding = dm_patch(ns, "document_finding",
        "if (!is.null(finding$values[[n]]) && !n %in% names(suppressed)) {",
        "if (!is.null(finding$values[[n]])) {"))),
    m("ir-hash", "documents.md (inputs): the IR hash without centring constants",
      function(ns) list(ir_without_means = function(ir) ir)),
    m("validator-E7020", "Validation: E7020", function(ns) list(
      shareable_finding_issues = dm_patch(ns, "shareable_finding_issues",
        "add(\"E7020\"", "c(\"E7020\""))),
    m("validator-E7021", "Validation: E7021", function(ns) list(
      shareable_finding_issues = dm_patch(ns, "shareable_finding_issues",
        "add(\"E7021\"", "c(\"E7021\""))),
    m("validator-E7022", "Validation: E7022", function(ns) list(
      shareable_finding_issues = dm_patch(ns, "shareable_finding_issues",
        "add(\"E7022\"", "c(\"E7022\""))),
    # Registry 0.1.0 has no statistic of kind labels, so a forged label fails
    # E7042 first.
    m("validator-E7023", "Validation: E7023", function(ns) list(
      shareable_finding_issues = dm_patch(ns, "shareable_finding_issues",
        "add(\"E7023\"", "c(\"E7023\"")), reachable = FALSE),
    m("validator-E7024", "Validation: E7024", function(ns) list(
      results_registry_issues = dm_patch(ns, "results_registry_issues",
        "add(\"E7024\"", "c(\"E7024\""))),
    m("validator-E7025", "Validation: E7025", function(ns) list(
      results_registry_issues = dm_patch(ns, "results_registry_issues",
        "add(\"E7025\"", "c(\"E7025\""))),
    m("validator-E7045", "Validation: E7045", function(ns) list(
      results_registry_issues = dm_patch(ns, "results_registry_issues",
        "add(\"E7045\"", "c(\"E7045\""))),
    m("validator-E7046", "Validation: E7046", function(ns) list(
      results_registry_issues = dm_patch(ns, "results_registry_issues",
        "add(\"E7046\"", "c(\"E7046\"")))
  )
}

# Installs a mutant and returns a function that restores the namespace.
dm_install <- function(ns, mutant) {
  replacements <- mutant$replace(ns)
  old <- lapply(names(replacements), function(name) get(name, envir = ns))
  names(old) <- names(replacements)
  for (name in names(replacements)) {
    dh_assign(ns, name, replacements[[name]])
  }
  function() {
    for (name in names(old)) {
      dh_assign(ns, name, old[[name]])
    }
  }
}
