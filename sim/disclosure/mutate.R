# Mutation testing of the privacy filter (sim/disclosure/README.md, attack d).
# Runs the attacks with the filter as it is, then with each mutant of
# R/mutants.R in turn, and reports which attacks detect each mutant: an
# attack detects a mutant when it reports a leak that it does not report
# without the mutant.
#
#   Rscript sim/disclosure/mutate.R [--lib DIR] [--cores N] [--mutants ID,...]
#     [--families NAME,...] [--baseline FILE] [--out FILE] [--first]
#
# The consistency search runs on each family without widening here. The
# regression and validation attacks run for every mutant, and the families
# run only until attack (a) or (b) detects it, or until validation refuses
# a document of a family, so that the run records the attacks that detect
# it first. With --first, the families do not run for a mutant that the
# regression or validation attacks detect. Split a long run with --mutants.
# The run ends with the mutants of rules that protect outcome-derived values
# (tier A in R/mutants.R) that no attack detects, leaving out those that
# registry 0.1.0 cannot reach, and exits with status 1 when there is one.

options(warn = 1)
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[i + 1L]
}
first_only <- "--first" %in% args
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
here <- normalizePath(dirname(script))
root <- normalizePath(file.path(here, "..", ".."))
for (file in list.files(file.path(here, "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(file)
}
cores <- as.integer(option("cores", max(1L, parallel::detectCores() - 1L)))
families <- option("families")
families <- if (is.null(families)) NULL else strsplit(families, ",")[[1L]]
chosen <- option("mutants")
mutants <- dm_mutants()
if (!is.null(chosen)) {
  mutants <- Filter(function(m) m$id %in% strsplit(chosen, ",")[[1L]], mutants)
}

ns <- dh_load(option("lib"))
dh_capture_on(ns)

# The leaks of attacks (a) and (b) on a family, and of (c) and (v), as
# signatures by attack: the place, the key of the table or document where an
# attack found the leak and the target, so that a mutant that adds a leak in
# a new table or document on a target that the baseline reports elsewhere
# counts as detected.
signatures <- function(leaks) split(paste(leaks$where, leaks$key, leaks$target), leaks$attack)
selected <- Filter(function(f) is.null(families) || f$name %in% families, dh_families())
if (!is.null(families)) {
  selected <- selected[order(match(vapply(selected, function(f) f$name, ""), families))]
}
# The leaks of attacks (a) and (b) on a family, with the documents of the
# family that validation refuses as leaks of attack (v), since every
# shareable document must meet the invariants of documents.md.
family_leaks <- function(family) {
  result <- dh_family_attacks(ns, family, c("a", "b"), cores = cores, widen = 0L)
  refused <- grep("fails validation", result$errors, value = TRUE)
  rbind(result$leaks, data.frame(attack = rep("v", length(refused)),
                                 where = rep(family$name, length(refused)),
                                 target = sub(".*validation: ", "", refused),
                                 value = rep("", length(refused)),
                                 reproducer = rep("", length(refused)),
                                 key = rep("", length(refused)),
                                 stringsAsFactors = FALSE))
}
other_leaks <- function() {
  dh_run_attacks(ns, root, attacks = c("c", "v"))$leaks
}

# The leaks without a mutant, read from --baseline when that file exists and
# written to it otherwise, so that runs split by --mutants compute them once.
saved <- option("baseline")
if (!is.null(saved) && file.exists(saved)) {
  baseline <- readRDS(saved)
} else {
  baseline <- list(other = signatures(other_leaks()))
  for (family in selected) {
    baseline[[family$name]] <- signatures(family_leaks(family))
  }
  if (!is.null(saved)) {
    saveRDS(baseline, saved)
  }
}

rows <- list()
for (mutant in mutants) {
  started <- proc.time()[["elapsed"]]
  restore <- dm_install(ns, mutant)
  detected <- c(a = FALSE, b = FALSE, c = FALSE, v = FALSE)
  first <- character(0)
  note <- function(found, base, attack, where) {
    new <- setdiff(found[[attack]], base[[attack]])
    if (length(new)) {
      detected[[attack]] <<- TRUE
      first <<- c(first, paste0(attack, ": ", new[1L]))
    }
  }
  outcome <- tryCatch({
    found <- signatures(other_leaks())
    for (attack in c("c", "v")) note(found, baseline$other, attack)
    # The families run until an attack on them detects the mutant. A mutant
    # of the validator leaves every document as it was, so the families do
    # not run for it.
    skip <- startsWith(mutant$id, "validator-") || (first_only && any(detected))
    for (family in if (skip) list() else selected) {
      found <- signatures(family_leaks(family))
      before <- detected
      for (attack in c("a", "b", "v")) {
        if (!detected[[attack]]) note(found, baseline[[family$name]], attack)
      }
      if (any(detected[c("a", "b")]) || (detected[["v"]] && !before[["v"]])) break
    }
    ""
  }, error = function(e) conditionMessage(e))
  restore()
  rows[[length(rows) + 1L]] <- data.frame(
    mutant = mutant$id, rule = mutant$rule, tier = mutant$tier, reachable = mutant$reachable,
    a = detected[["a"]], b = detected[["b"]],
    c = detected[["c"]], v = detected[["v"]],
    note = if (nzchar(outcome)) paste("error:", outcome) else paste(first, collapse = "; "),
    stringsAsFactors = FALSE)
  cat(sprintf("%-28s a %-5s b %-5s c %-5s v %-5s %4.0f s  %s\n", mutant$id, detected[["a"]],
              detected[["b"]], detected[["c"]], detected[["v"]],
              proc.time()[["elapsed"]] - started, substr(rows[[length(rows)]]$note, 1, 120)))
  out <- option("out")
  if (!is.null(out)) {
    saveRDS(list(baseline = baseline, mutants = do.call(rbind, rows)), out)
  }
}

missed <- Filter(function(row) {
  row$tier == "A" && row$reachable && !any(unlist(row[c("a", "b", "c", "v")]))
}, rows)
for (row in missed) {
  cat(sprintf("NOT DETECTED %s: %s\n", row$mutant, row$rule))
}
if (length(missed)) {
  quit(status = 1L)
}
