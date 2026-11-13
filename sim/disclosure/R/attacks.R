# The attacks together (sim/disclosure/README.md): the consistency search (a)
# and the interval audit (b) on every family, the interval audit and the
# validation of the documents of the stored instances of the pathology zoo
# when instances is TRUE (R/zoo.R), the regression attacks (c) and the
# validation attacks (v), with a report of the leaks, the candidates of the
# families that do not gate the run, the determinations that privacy.md
# accepts, those that an alternative of the family traces, those of
# design-structure values that it leaves as residual risk and the errors of
# the harness.

dh_run_attacks <- function(ns, root, attacks = c("a", "b", "c", "v"), families = NULL,
                           cores = 1L, widen = 1L, log = FALSE, instances = FALSE) {
  say <- function(...) if (log) cat(sprintf(...), "\n", sep = "")
  leaks <- list()
  candidates <- list()
  residual <- list()
  accepted <- list()
  traced <- list()
  errors <- character(0)
  timing <- list()
  add_leak <- function(attack, where, target, value, reproducer) {
    leaks[[length(leaks) + 1L]] <<- data.frame(attack = attack, where = where, target = target,
                                               value = value, reproducer = reproducer, key = "",
                                               stringsAsFactors = FALSE)
  }
  if (any(c("a", "b") %in% attacks)) {
    for (family in dh_families()) {
      if (!is.null(families) && !family$name %in% families) {
        next
      }
      started <- proc.time()[["elapsed"]]
      result <- dh_family_attacks(ns, family, attacks, cores, widen)
      leaks <- c(leaks, list(result$leaks))
      candidates <- c(candidates, list(result$candidates))
      residual <- c(residual, list(result$residual))
      accepted <- c(accepted, list(result$accepted))
      traced <- c(traced, list(result$traced))
      errors <- c(errors, result$errors)
      timing[[family$name]] <- proc.time()[["elapsed"]] - started
      say("%-24s %5d tables %4.0f s", family$name, result$tables, timing[[family$name]])
    }
  }
  if ("b" %in% attacks && instances) {
    # Attack (b) and the validation of stages 4 and 5 on the documents of the
    # stored instances, at the registry's k, without attack (a).
    started <- proc.time()[["elapsed"]]
    result <- dh_family_attacks(ns, dz_instances(ns), "b", cores, widen = 0L)
    leaks <- c(leaks, list(result$leaks))
    residual <- c(residual, list(result$residual))
    errors <- c(errors, result$errors)
    timing[["zoo-instances"]] <- proc.time()[["elapsed"]] - started
    say("%-24s %5d tables %4.0f s", "zoo-instances", result$tables, timing[["zoo-instances"]])
  }
  if ("c" %in% attacks) {
    started <- proc.time()[["elapsed"]]
    regressions <- rg_run(ns, root)
    tiers <- vapply(rg_attacks(), function(a) a$tier %||% "A", "")
    names(tiers) <- vapply(rg_attacks(), function(a) a$id, "")
    for (j in which(regressions$leak)) {
      if (identical(tiers[[regressions$attack[j]]], "B")) {
        # A design-structure value that an inference other than a linear
        # relation gives back is residual risk (privacy.md, Guarantees).
        residual <- c(residual, list(data.frame(
          attack = "c", where = regressions$attack[j], target = regressions$channel[j],
          value = regressions$found[j], reproducer = "R/regressions.R", key = "",
          stringsAsFactors = FALSE)))
        next
      }
      add_leak("c", regressions$attack[j], regressions$channel[j], regressions$found[j],
               "R/regressions.R")
    }
    timing$regressions <- proc.time()[["elapsed"]] - started
    say("%-24s %5d attacks %4.0f s", "regressions", nrow(regressions), timing$regressions)
  }
  if ("v" %in% attacks) {
    started <- proc.time()[["elapsed"]]
    validation <- va_run(ns)
    for (j in which(validation$leak)) {
      add_leak("v", validation$attack[j],
               paste("the validator accepts a document that", validation$rule[j], "refuses"),
               validation$codes[j], "R/validator.R")
    }
    timing$validation <- proc.time()[["elapsed"]] - started
    say("%-24s %5d attacks %4.0f s", "validation", nrow(validation), timing$validation)
  }
  empty <- data.frame(attack = character(0), where = character(0), target = character(0),
                      value = character(0), reproducer = character(0), key = character(0),
                      stringsAsFactors = FALSE)
  leaks <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, leaks)
  leaks <- if (length(leaks)) do.call(rbind, leaks) else empty
  # The leaks of the channels that privacy.md records as not closed are
  # reported apart, and a listed channel that no attack finds is an error of
  # the harness until it leaves the list.
  known <- dh_known_match(leaks)
  ran <- unique(c(if (any(c("a", "b") %in% attacks)) {
    vapply(Filter(function(f) is.null(families) || f$name %in% families, dh_families()),
           function(f) f$name, "")
  }))
  candidates <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, candidates)
  candidates <- if (length(candidates)) do.call(rbind, candidates) else empty
  # The candidates of a family of gate FALSE that a known channel explains
  # are reported with its leaks.
  known_candidates <- dh_known_match(candidates)
  for (channel in dh_known_channels()) {
    if (any(channel$family %in% ran) && channel$attack %in% attacks &&
        !any(c(known, known_candidates) == channel$id, na.rm = TRUE)) {
      errors <- c(errors, sprintf(
        "the known channel %s is not found: remove it from dh_known_channels()", channel$id))
    }
  }
  residual <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, residual)
  accepted <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, accepted)
  traced <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, traced)
  list(leaks = leaks[is.na(known), , drop = FALSE],
       known = rbind(
         cbind(leaks[!is.na(known), , drop = FALSE], channel = known[!is.na(known)]),
         cbind(candidates[!is.na(known_candidates), , drop = FALSE],
               channel = known_candidates[!is.na(known_candidates)])),
       candidates = candidates[is.na(known_candidates), , drop = FALSE],
       residual = if (length(residual)) do.call(rbind, residual) else empty,
       accepted = if (length(accepted)) do.call(rbind, accepted) else empty[, 1:3],
       traced = if (length(traced)) do.call(rbind, traced) else
         data.frame(where = character(0), target = character(0), alternative = character(0),
                    stringsAsFactors = FALSE),
       errors = errors, timing = timing,
       regressions = if ("c" %in% attacks) regressions,
       validation = if ("v" %in% attacks) validation)
}

# Attacks (a) and (b) on one family: the leaks, the candidates, the
# determinations that privacy.md accepts, those that an alternative of the
# family traces (dh_alternatives()), those that it leaves as residual risk
# and the errors of the harness, with the number of tables. A
# determination of an outcome-derived value is a leak of attack (a) in a
# family that gates the run and a candidate in another, and a leak of attack
# (b) when it is determined, or bound below k by the written values without
# the bounds of details. A design-structure value is a leak of attack (b)
# when the linear relations alone determine it, and residual risk when only
# other inferences do.
# Each leak has a key that identifies where it was found whatever the order
# in which the workers ran: the table of the family for (a) and the reduced
# document for (b), which the interval audit audits once.
dh_family_attacks <- function(ns, family, attacks = c("a", "b"), cores = 1L, widen = 1L) {
  leaks <- list()
  errors <- character(0)
  add_leak <- function(attack, target, value, reproducer, key) {
    leaks[[length(leaks) + 1L]] <<- data.frame(attack = attack, where = family$name,
                                               target = target, value = value,
                                               reproducer = reproducer, key = key,
                                               stringsAsFactors = FALSE)
  }
  # Only a family that gates the run is widened, since the determinations of
  # the others are candidates that do not fail it.
  search <- dh_search(ns, family, cores = cores,
                      widen = if ("a" %in% attacks && isTRUE(family$gate)) widen else 0L,
                      intervals = "b" %in% attacks)
  grid <- search$ran$grid
  runs <- search$ran$runs
  failed <- vapply(runs, function(r) !is.list(r) || !is.null(r$error), NA)
  no_rows <- vapply(runs, function(r) is.list(r) && isTRUE(r$empty), NA)
  for (i in which(failed & !no_rows)) {
    errors <- c(errors, sprintf("%s, table %s: %s", family$name, dh_params(grid, i),
                                if (is.list(runs[[i]])) runs[[i]]$error else runs[[i]]))
  }
  # Every parameter has the tier that the definition gives it on the tables
  # of the family (privacy.md, Tiers).
  keys <- t(vapply(runs, function(r) {
    if (is.list(r) && length(r$design) == 2L) r$design else c(design = NA_character_, table = NA)
  }, c(design = "", table = "")))
  errors <- c(errors, dh_parameter_tier_issues(family, grid, keys))
  issues <- unique(unlist(lapply(runs[!failed], function(r) r$issues)))
  for (issue in issues) {
    errors <- c(errors, sprintf("%s: a shareable document fails validation: %s",
                                family$name, issue))
  }
  found <- search$found
  accepted <- found[found$verdict == "accepted", , drop = FALSE]
  traced <- found[found$verdict == "traced", , drop = FALSE]
  candidates <- list()
  residual <- list()
  add_residual <- function(attack, target, value, reproducer) {
    residual[[length(residual) + 1L]] <<- data.frame(
      attack = attack, where = family$name, target = target, value = value,
      reproducer = reproducer, key = reproducer, stringsAsFactors = FALSE)
  }
  if ("a" %in% attacks) {
    for (j in which(found$verdict == "residual")) {
      add_residual("a", found$target[j], found$value[j], dh_params(grid, found$table[j]))
    }
    for (j in which(found$verdict == "leak")) {
      params <- dh_params(grid, found$table[j])
      if (isTRUE(family$gate)) {
        add_leak("a", found$target[j], found$value[j], params, params)
      } else {
        candidates[[length(candidates) + 1L]] <- data.frame(
          attack = "a", where = family$name, target = found$target[j], value = found$value[j],
          reproducer = params, key = params, stringsAsFactors = FALSE)
      }
    }
  }
  if ("b" %in% attacks) {
    for (i in which(!failed)) {
      lp <- runs[[i]]$lp
      if (is.null(lp) || !nrow(lp)) next
      for (j in seq_len(nrow(lp))) {
        interval <- sprintf("[%g, %g] (%s)", lp$lower[j], lp$upper[j], lp$detail[j])
        if (lp$verdict[j] == "determined" || (lp$verdict[j] == "bound" && lp$tier[j] == "A")) {
          add_leak("b", paste(lp$target[j], lp$verdict[j]), interval, dh_params(grid, i),
                   runs[[i]]$full)
        } else if (lp$verdict[j] == "residual") {
          add_residual("b", paste(lp$target[j], "determined with inequalities"), interval,
                       dh_params(grid, i))
        } else if (lp$verdict[j] == "no tier") {
          errors <- c(errors, sprintf("%s, table %s: the hidden value %s has no tier",
                                      family$name, dh_params(grid, i), lp$target[j]))
        } else if (lp$verdict[j] == "model error") {
          errors <- c(errors, sprintf("%s, table %s: the interval audit excludes the value %g of %s",
                                      family$name, dh_params(grid, i), lp$truth[j], lp$target[j]))
        }
      }
    }
  }
  empty <- data.frame(attack = character(0), where = character(0), target = character(0),
                      value = character(0), reproducer = character(0), key = character(0),
                      stringsAsFactors = FALSE)
  list(leaks = if (length(leaks)) do.call(rbind, leaks) else empty,
       candidates = if (length(candidates)) do.call(rbind, candidates) else empty,
       residual = if (length(residual)) do.call(rbind, residual) else empty,
       accepted = data.frame(attack = rep("a", nrow(accepted)), where = rep(family$name, nrow(accepted)),
                             target = accepted$target, stringsAsFactors = FALSE),
       traced = data.frame(where = rep(family$name, nrow(traced)), target = traced$target,
                           alternative = traced$traced, stringsAsFactors = FALSE),
       errors = errors, tables = nrow(grid))
}

# The channels of outcome-derived values, or linear relations of
# design-structure values, that docs/spec/privacy.md (Guarantees) records as
# not closed, each with the attack and the families, or for attack (c) the
# regression attack, that find it, and a pattern of its targets. privacy.md
# records one, which 03-execution-plan.md (M2, Open items) leaves to the
# coordinator: beside the firing of rule 1 of Across findings, a level known
# to hold k rows or more is shown not to have lost every outcome, as in
# zoo-reuse and zoo-separation, whose determinations of it are candidates.
dh_known_channels <- function() {
  list(
    list(id = "kept-levels", attack = "a", family = c("zoo-reuse", "zoo-separation"),
         target = paste0("^(D design minus analysis \\| levels(_with_two_rows)? (class|school|item)",
                         "|outcome[.]constant_clusters factor=subject \\| multi_row_levels",
                         "|outcome[.]minority_events factor=subject \\| (levels|support[.]distinct)) \\| [a-z_]+$"))
  )
}

# The identifier of the known channel of each leak, or NA.
dh_known_match <- function(leaks) {
  out <- rep(NA_character_, nrow(leaks))
  for (channel in dh_known_channels()) {
    hit <- is.na(out) & leaks$attack == channel$attack & leaks$where %in% channel$family &
      grepl(channel$target, leaks$target)
    out[hit] <- channel$id
  }
  out
}

dh_params <- function(grid, i) {
  paste(names(grid), unlist(grid[i, , drop = FALSE]), sep = "=", collapse = ", ")
}

dh_print_report <- function(report) {
  leaks <- report$leaks
  residual <- report$residual
  traced <- report$traced
  cat(sprintf(paste("%d leaks, %d candidates, %d accepted determinations,",
                    "%d traced determinations, %d determinations of residual risk,",
                    "%d errors of the harness\n"),
              nrow(leaks), nrow(report$candidates), nrow(report$accepted),
              nrow(traced %||% data.frame()), nrow(residual %||% leaks[0, ]),
              length(report$errors)))
  known <- report$known
  if (!is.null(known) && nrow(known)) {
    for (j in which(!duplicated(known$channel))) {
      cat(sprintf("KNOWN %s: %s, in %d places, e.g. family %s, %s\n", known$channel[j],
                  known$target[j], sum(known$channel == known$channel[j]), known$where[j],
                  known$reproducer[j]))
    }
  }
  if (nrow(leaks)) {
    # One line for each target and place, with the first reproducer.
    key <- paste(leaks$attack, leaks$where, leaks$target)
    first <- !duplicated(key)
    counts <- table(key)[key[first]]
    for (j in which(first)) {
      if (leaks$attack[j] %in% c("a", "b")) {
        cat(sprintf("LEAK (%s) family %s: %s = %s, in %d tables, e.g. %s\n", leaks$attack[j],
                    leaks$where[j], leaks$target[j], leaks$value[j], counts[[key[j]]],
                    leaks$reproducer[j]))
      } else {
        cat(sprintf("LEAK (%s) %s: %s: %s\n", leaks$attack[j], leaks$where[j],
                    leaks$target[j], leaks$value[j]))
      }
    }
  }
  for (error in utils::head(report$errors, 20L)) {
    cat("ERROR", error, "\n")
  }
  candidates <- report$candidates
  key <- paste(candidates$where, candidates$target)
  for (j in which(!duplicated(key))) {
    cat(sprintf("CANDIDATE (a) family %s: %s = %s, e.g. %s\n", candidates$where[j],
                candidates$target[j], candidates$value[j], candidates$reproducer[j]))
  }
  if (!is.null(traced) && nrow(traced)) {
    # The determinations that an alternative of the family traces, by family
    # and alternative, so that a reader sees which alternatives carry the
    # gate of attack (a).
    key <- paste(traced$where, traced$alternative)
    for (j in which(!duplicated(key))) {
      cat(sprintf("TRACED (a) family %s: %d determinations by the alternative %s\n",
                  traced$where[j], sum(key == key[j]), traced$alternative[j]))
    }
  }
  if (!is.null(residual) && nrow(residual)) {
    # Determinations of design-structure values that the linear relations
    # alone do not make, which privacy.md (Guarantees, Residual risk) leaves
    # open: one line for each attack, place and target, with the number of
    # tables and the first reproducer. They never fail the run.
    cat("\nResidual risk (privacy.md, Guarantees, Residual risk): determinations of",
        "design-structure values\n")
    key <- paste(residual$attack, residual$where, residual$target)
    for (j in which(!duplicated(key))) {
      if (residual$attack[j] == "c") {
        cat(sprintf("RESIDUAL (c) %s: %s: %s\n", residual$where[j], residual$target[j],
                    residual$value[j]))
      } else {
        cat(sprintf("RESIDUAL (%s) family %s: %s = %s, in %d tables, e.g. %s\n",
                    residual$attack[j], residual$where[j], residual$target[j], residual$value[j],
                    sum(key == key[j]), residual$reproducer[j]))
      }
    }
  }
}
