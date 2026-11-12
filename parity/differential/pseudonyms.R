# Runs the pseudonym cases of the differential test with the installed R
# package (parity/README.md, Differential test).
#
#   Rscript parity/differential/pseudonyms.R CASES OUTPUT
#
# Registry 0.1.0 has no statistic of kind labels, so no audit writes a
# pseudonym. Each case of CASES, which differential.py writes, holds findings
# of a check whose findings write labels, as test-privacy.R defines it, each
# with its factor, its labels and the distinct contributors of its support,
# and the commitment key and k of the case. The runner applies step 2 of the
# filter to each finding, then steps 10 and 11, and writes to OUTPUT one line
# for each case with the hexadecimal digits of the canonical bytes, in the
# data profile, of the case's identifier, the written findings and the
# pseudonyms in the form of the internal sidecar.

suppressPackageStartupMessages(library(mixedcheck))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript pseudonyms.R CASES OUTPUT", call. = FALSE)
}
ns <- asNamespace("mixedcheck")

# A check whose findings write labels, a copy of the one that
# r/tests/testthat/test-privacy.R defines, which the tests and this runner
# keep apart because the tests do not ship with the parity harness.
labels_entry <- list(
  id = "structure.flagged_levels", version = 1, tier = "T0", sample = "design",
  scope = "grouping_factor",
  statistics = list(
    flagged = list(kind = "labels"),
    flagged_levels = list(kind = "count", count_class = "person")
  ),
  decision = list(
    rules = list(list(finding = "detectable_inconsequential", statistics = list("flagged"),
                      message = "listed")),
    otherwise = list(finding = "consistent", message = "listed")
  ),
  messages = list(listed = list(
    template = "Flagged levels of '{factor}': {flagged}.",
    fallback = "Some levels of '{factor}' are flagged.",
    args = list(factor = list(source = "scope", name = "factor"),
                flagged = list(source = "statistic", name = "flagged"))
  ))
)

labels_finding <- function(factor, labels, distinct, dominated, k) {
  finding <- list(
    check = "structure.flagged_levels", check_version = 1, tier = "T0",
    scope = list(factor = factor), available = TRUE,
    status = list(assessability = list(value = "adequate"),
                  finding = list(value = "detectable_inconsequential"),
                  threshold_proximity = list(value = "clear"),
                  validation = list(value = "descriptive")),
    message = list(id = "listed", text = ""),
    statistics = list(flagged = list(kind = "labels"),
                      flagged_levels = list(kind = "count", count_class = "person")),
    values = list(flagged = labels, flagged_levels = 12),
    support = list(rows = 200, basis = "grouping_factors", distinct = distinct,
                   dominated = dominated),
    items = list(), rows = seq_len(200), entry = labels_entry, rule = 1L,
    label_factors = list(flagged = factor),
    suppressed = structure(character(0), names = character(0)),
    support_suppressed = structure(character(0), names = character(0)),
    whole = FALSE
  )
  ns$privacy_minimum_rules(finding, k)
}

hex <- function(bytes) paste(as.character(bytes), collapse = "")

cases <- read_json_strict(args[1L], "data")$cases
lines <- vapply(cases, function(case) {
  findings <- lapply(case$findings, function(f) {
    labels_finding(f$factor, as.character(unlist(f$labels)), f$distinct, f$dominated, case$k)
  })
  pseudonyms <- ns$privacy_pseudonyms(findings, case$key)
  rendered <- lapply(findings, ns$privacy_render, pseudonyms = pseudonyms)
  hex(canonical_bytes(list(id = case$id, findings = lapply(rendered, ns$document_finding),
                           pseudonyms = ns$privacy_sidecar_pseudonyms(pseudonyms)), "data"))
}, "")
writeLines(lines, args[2L], useBytes = TRUE)
