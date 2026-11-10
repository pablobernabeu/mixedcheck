# Attack (d), mutation testing of the filter (sim/disclosure/README.md). Each
# mutant disables one rule of the privacy filter (r/R/privacy.R and the
# writer of findings in r/R/checks.R), of the shareable IR hash or of the
# validator (r/R/results-validate.R) by replacing a function of the loaded
# namespace in the harness alone, either by a function that skips the rule
# or by a copy of the function whose text has one condition changed. The
# package's files are never changed. A mutant whose text pattern no longer
# occurs in its function fails to install, so that a change to the filter
# that moves a rule shows in the mutation run.

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
# disables and a function that returns the replacements, by name.
dm_mutants <- function() {
  m <- function(id, rule, replace) list(id = id, rule = rule, replace = replace)
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
    m("across-1-rows", "Across findings: rule 1 on rows", function(ns) list(
      privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "for (member in c(\"rows\", \"contributors\"))", "for (member in c(\"contributors\"))"))),
    m("across-1-contributors", "Across findings: rule 1 on contributors", function(ns) list(
      privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "for (member in c(\"rows\", \"contributors\"))", "for (member in c(\"rows\"))"))),
    m("across-1-levels", "Across findings: rule 1 on levels", function(ns) list(
      privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "for (measure in measures[1:2])", "for (measure in character(0))"))),
    m("across-1-class", "Across findings: rule 1 on the class of the larger sample",
      function(ns) list(privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "if (!larger$items[[i]]$person) {", "if (!smaller$items[[i]]$person) {"))),
    m("across-1-losing-below-k", "Across findings: rule 1 on a quantity of the losing sample below k",
      function(ns) list(privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "close <- function(a, b, lose) (a - b >= 0 && a - b < k) || lose < k",
        "close <- function(a, b, lose) a - b >= 0 && a - b < k"))),
    m("across-1-crossed", "Across findings: rule 1 on the combinations of a crossed pair",
      function(ns) list(privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "for (pair in crossed)", "for (pair in list())"))),
    m("across-2", "Across findings: rule 2", function(ns) list(
      privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        c("if (small || first[[\"levels\"]]) {",
          "if (small || first[[\"levels_with_two_rows\"]]) {"),
        c("if (FALSE) {", "if (FALSE) {")))),
    m("across-2-two-rows-below-k", "Across findings: rule 2 when the levels with two rows are below k",
      function(ns) list(privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "small <- item$levels_with_one_row < k || item$levels_with_two_rows < k",
        "small <- item$levels_with_one_row < k"))),
    m("across-3", "Across findings: rule 3", function(ns) list(
      privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "if (quantities[[sample]]$rows < privacy_rows_without_singletons(item$levels, written)) {",
        "if (FALSE) {"))),
    m("across-3-quartiles", "Across findings: rule 3 with the written quartiles",
      function(ns) list(privacy_quantity_marks = dm_patch(ns, "privacy_quantity_marks",
        "written <- q$quantiles", "written <- list()"))),
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
        "if (identical(finding$support$basis, \"grouping_factors\") &&",
        "if (FALSE &&"))),
    m("across-4", "Across findings: rule 4", function(ns) list(
      privacy_missing_key_close = function(run, samples, k) FALSE)),
    m("across-4-below-k", "Across findings: rule 4 on missing_key_rows below k",
      function(ns) list(privacy_across = dm_patch(ns, "privacy_across",
        "isTRUE(findings[[i]]$values[[\"missing_key_rows\"]] < k) ||", "FALSE ||"))),
    m("across-5", "Across findings: rule 5", function(ns) list(
      privacy_design_reals = function(run, finding, items, marks) finding)),
    m("step-8", "Steps 8: absent statistics", function(ns) list(
      privacy_absent = function(finding) finding)),
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
    m("validator-E7023", "Validation: E7023", function(ns) list(
      shareable_finding_issues = dm_patch(ns, "shareable_finding_issues",
        "add(\"E7023\"", "c(\"E7023\""))),
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
