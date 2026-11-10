# The attacks together (sim/disclosure/README.md): the consistency search (a)
# and the interval audit (b) on every family, the regression attacks (c) and
# the validation attacks (v), with a report of the leaks, the
# determinations that privacy.md accepts and the errors of the harness.

dh_run_attacks <- function(ns, root, attacks = c("a", "b", "c", "v"), families = NULL,
                           cores = 1L, widen = 1L, log = FALSE) {
  say <- function(...) if (log) cat(sprintf(...), "\n", sep = "")
  leaks <- list()
  candidates <- list()
  accepted <- list()
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
      accepted <- c(accepted, list(result$accepted))
      errors <- c(errors, result$errors)
      timing[[family$name]] <- proc.time()[["elapsed"]] - started
      say("%-24s %5d tables %4.0f s", family$name, result$tables, timing[[family$name]])
    }
  }
  if ("c" %in% attacks) {
    started <- proc.time()[["elapsed"]]
    regressions <- rg_run(ns, root)
    for (j in which(regressions$leak)) {
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
  for (channel in dh_known_channels()) {
    if (channel$family %in% ran && channel$attack %in% attacks && !any(known == channel$id)) {
      errors <- c(errors, sprintf(
        "the known channel %s is not found: remove it from dh_known_channels()", channel$id))
    }
  }
  candidates <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, candidates)
  accepted <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, accepted)
  list(leaks = leaks[is.na(known), , drop = FALSE],
       known = cbind(leaks[!is.na(known), , drop = FALSE], channel = known[!is.na(known)]),
       candidates = if (length(candidates)) do.call(rbind, candidates) else empty,
       accepted = if (length(accepted)) do.call(rbind, accepted) else empty[, 1:3],
       errors = errors, timing = timing,
       regressions = if ("c" %in% attacks) regressions,
       validation = if ("v" %in% attacks) validation)
}

# Attacks (a) and (b) on one family: the leaks, the determinations that
# privacy.md accepts and the errors of the harness, with the number of tables.
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
  issues <- unique(unlist(lapply(runs[!failed], function(r) r$issues)))
  for (issue in issues) {
    errors <- c(errors, sprintf("%s: a shareable document fails validation: %s",
                                family$name, issue))
  }
  found <- search$found
  accepted <- found[found$verdict == "accepted", , drop = FALSE]
  candidates <- list()
  if ("a" %in% attacks) {
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
        if (lp$verdict[j] == "determined") {
          add_leak("b", paste(lp$target[j], lp$verdict[j]), interval, dh_params(grid, i),
                   runs[[i]]$full)
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
       accepted = data.frame(attack = rep("a", nrow(accepted)), where = rep(family$name, nrow(accepted)),
                             target = accepted$target, stringsAsFactors = FALSE),
       errors = errors, tables = nrow(grid))
}

# The channels that docs/spec/privacy.md (Guarantees) records as not closed,
# each with the attack and family that find it and a pattern of its targets.
dh_known_channels <- function() {
  list(
    list(id = "quantile-pinned-by-rows", attack = "b", family = "four-sizes",
         target = paste0("^structure\\.cluster_sizes .*\\| ",
                         "(lower_quartile|median|upper_quartile) determined$"),
         channel = "a quantile below k that the rows, the levels and the singletons pin")
  )
}

# The identifier of the known channel of each leak, or NA.
dh_known_match <- function(leaks) {
  out <- rep(NA_character_, nrow(leaks))
  for (channel in dh_known_channels()) {
    hit <- is.na(out) & leaks$attack == channel$attack & leaks$where == channel$family &
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
  cat(sprintf(paste("%d leaks, %d of known channels, %d candidates,",
                    "%d accepted determinations, %d errors of the harness\n"),
              nrow(leaks), nrow(report$known %||% leaks[0, ]), nrow(report$candidates),
              nrow(report$accepted), length(report$errors)))
  known <- report$known
  if (!is.null(known) && nrow(known)) {
    for (j in which(!duplicated(known$channel))) {
      cat(sprintf("KNOWN %s: %s, in %d places, e.g. family %s, %s\n", known$channel[j],
                  known$target[j], sum(known$channel == known$channel[j]), known$where[j],
                  known$reproducer[j]))
    }
  }
  candidates <- report$candidates
  key <- paste(candidates$where, candidates$target)
  for (j in which(!duplicated(key))) {
    cat(sprintf("CANDIDATE (a) family %s: %s = %s, e.g. %s\n", candidates$where[j],
                candidates$target[j], candidates$value[j], candidates$reproducer[j]))
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
}
