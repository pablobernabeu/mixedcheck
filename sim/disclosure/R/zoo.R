# The pathology zoo in the disclosure-attack tests (sim/disclosure/README.md,
# The zoo): the stored instances, whose shareable documents attack (b) and
# the validator read at the registry's k, and eleven families that build
# small tables from the seeded generators of sim/zoo/R/ with varied
# parameters, with the tables outside them that trace their determinations
# (dh_alternatives()). The generators are sourced into an environment of
# their own, so that their helpers do not mask those of the harness.

# The directory of this file, from the frame of source(), or NULL when it is
# read otherwise.
dz_source_dir <- function() {
  for (frame in rev(sys.frames())) {
    if (!is.null(frame$ofile)) {
      return(dirname(normalizePath(frame$ofile)))
    }
  }
  NULL
}

dz_state <- new.env(parent = emptyenv())
dz_state$here <- dz_source_dir()

# The definitions of the zoo, read once from sim/zoo/R/ as regenerate.R reads
# them. The directory is found beside this file, or under the global root
# that run.R, mutate.R and parity/differential/inputs.R set.
dz_definitions <- function() {
  if (is.null(dz_state$definitions)) {
    zoo_dir <- if (!is.null(dz_state$here)) {
      file.path(dz_state$here, "..", "..", "zoo", "R")
    } else {
      file.path(get("root", envir = globalenv()), "sim", "zoo", "R")
    }
    zoo_dir <- normalizePath(zoo_dir, mustWork = TRUE)
    env <- new.env(parent = globalenv())
    sys.source(file.path(zoo_dir, "zoo.R"), envir = env, keep.source = FALSE)
    files <- sort(list.files(zoo_dir, pattern = "^Z[0-9]{2}[.]R$"), method = "radix")
    for (file in files) {
      env$zoo_state$file <- file
      sys.source(file.path(zoo_dir, file), envir = env, keep.source = FALSE)
    }
    dz_state$definitions <- env$zoo_state$definitions
  }
  dz_state$definitions
}

# A value of a generator file as audit() reads it: an array of the zoo, which
# the writers of sim/zoo/ mark, becomes a list, so that an array of one
# element stays an array.
dz_plain <- function(x) {
  if (inherits(x, "zoo_array")) {
    return(as.list(unclass(x)))
  }
  if (is.list(x)) {
    labels <- names(x)
    x <- lapply(x, dz_plain)
    names(x) <- labels
  }
  x
}

# A table of a zoo family: the data that the generator of fixture id draws
# with the fixture's seed, the checks 'redraw' and the fixture's stored
# parameters with those named in changes replaced, and the fixture's
# declaration and formula for those parameters. The outcome is then removed
# in the rows that missing selects, the one change that a family makes to the
# generated data, and the run is that of the family (args).
dz_case <- function(id, changes, args, missing = integer(0)) {
  definition <- dz_definitions()[[id]]
  p <- utils::modifyList(definition$parameters, changes)
  data <- definition$generate(p, "redraw", definition$seed)
  attr(data, "zoo_redraws") <- NULL
  declaration <- dz_plain(definition$declaration(p))
  formula <- definition$formula(p)
  outcome <- all.vars(stats::as.formula(formula)[[2L]])
  if (length(missing)) {
    data[[outcome]][missing] <- NA
  }
  list(data = data, formula = formula, args = c(list(declaration = declaration), args))
}

# The rows of the units listed in units, one for each unit: its last row
# (last TRUE) or its first, in the order of the table.
dz_rows_of <- function(unit, units, last = TRUE) {
  rows <- seq_along(unit)
  vapply(units, function(u) {
    found <- rows[unit == u]
    if (last) found[length(found)] else found[1L]
  }, 0L)
}

# --- The stored instances ---------------------------------------------------------

# The stored instances as a family whose one parameter is the position of a
# fixture in the listing of pathology_zoo() among those whose run returns a
# document, 58 of the 60, audited at the registry's k. Its tables are
# fixtures of different designs, so attack (a), which compares tables of
# one family, does not run on it: a family of one table for each design
# would report every value that varies between fixtures as determined.
dz_instances <- function(ns) {
  listing <- ns$pathology_zoo()
  documents <- Filter(function(id) is.null(ns$pathology_zoo(id)$expected$issue), listing$id)
  dh_family(
    name = "zoo-instances",
    description = "the stored instances of the pathology zoo, at the registry's k",
    params = list(fixture = dh_param(seq_along(documents), natural = c(TRUE, TRUE))),
    k = dh_k(ns),
    build = function(p) {
      fixture <- ns$pathology_zoo(documents[[p$fixture]])
      list(data = fixture$data, formula = fixture$formula,
           args = c(list(declaration = fixture$declaration), fixture$arguments),
           id = fixture$id)
    }
  )
}

# --- The families -----------------------------------------------------------------

# The eleven zoo families, in the order in which they run after the families
# of R/families.R. Their ranges reach one value beyond the ranges of the
# design of the zoo at an end that is a limit of the family rather than a
# natural bound, so that every family has tables strictly inside its limits
# (dh_interior()). A member count of 1 is a natural bound. The generators
# draw a continuous outcome, which never repeats within a level, and each
# family removes the outcome in rows that its parameters choose, so that
# the status of outcome.constant_clusters and the quantities of the
# analysis sample follow the grid. The families therefore give attack (a)
# the tables outside them that read alike (dz_alternatives_*()), or witness
# parameters whose value 1 lies at a limit of the family and joins the
# groups of the interior tables (reduced, extra and tied). Attack (b) gates
# every family, and attack (a) every family but zoo-reuse and
# zoo-separation (README, The zoo, Gates).
dz_families <- function() {
  list(
    dz_family_reuse(),
    dz_family_mobility(),
    dz_family_latin(),
    dz_family_families(),
    dz_family_crt(),
    dz_family_disconnected(),
    dz_family_empty_cell(),
    dz_family_reference(),
    dz_family_separation(),
    dz_family_ceiling(),
    dz_family_multisite()
  )
}

# Classes whose labels recur in every school and are declared within_parent,
# with a formula that uses class without school (Z01), and pupils without an
# outcome, in a T1 run. Attack (a) does not gate it: beside the firing of
# rule 1, levels of k rows or more of crossed columns are shown not to have
# lost every outcome, the class of determinations that privacy.md
# (Guarantees) names as an exception until the coordinator settles it
# (03-execution-plan.md, M2, Open items) and that dh_known_channels() lists
# (README, The zoo, Gates).
dz_family_reuse <- function() {
  dh_family(
    name = "zoo-reuse",
    gate = FALSE,
    probe = "^(structure|identifiability|sample|outcome)\\.",
    description = "Z01: class labels reused across schools, declared within_parent, T1",
    alternatives = dz_alternatives_reuse,
    params = list(
      schools = dh_param(2:4),
      classes = dh_param(2:4),
      pupils = dh_param(1:3, person = TRUE, natural = c(TRUE, FALSE)),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$schools * p$classes,
    build = function(p) {
      # The last pupil of each of the first y_missing classes.
      missing <- seq_len(p$y_missing) * p$pupils
      dz_case("Z01", list(schools = p$schools, classes = p$classes, pupils = p$pupils,
                          reuse = TRUE), dh_t1(), missing)
    }
  )
}

# Pupils observed in two waves, the first pupils of schools 1 and 2 moving to
# another school in wave 2, declared nested_mobile and modelled as
# (1 | school/pupil) (Z02), and second waves without an outcome, in a T1 run.
dz_family_mobility <- function() {
  dh_family(
    name = "zoo-mobility",
    probe = "^(structure|identifiability|sample|outcome)\\.",
    description = "Z02: pupils who change school between two waves, nested_mobile, T1",
    alternatives = dz_alternatives_mobility,
    params = list(
      pupils_per_school = dh_param(2:4, person = TRUE),
      movers = dh_param(0:2, person = TRUE, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= 3L * p$pupils_per_school - p$movers,
    build = function(p) {
      n <- p$pupils_per_school
      movers <- c(1L, n + 1L)[seq_len(p$movers)]
      # Wave 2 of the first y_missing pupils who do not move.
      staying <- setdiff(seq_len(3L * n), movers)[seq_len(p$y_missing)]
      dz_case("Z02", list(schools = 3, pupils_per_school = n, waves = 2,
                          movers = structure(as.numeric(movers), class = "zoo_array")),
              dh_t1(), (staying - 1L) * 2L + 2L)
    }
  )
}

# A Latin square of three lists, in which each subject sees each item once,
# with by-subject and by-item slopes of the condition and a subject-by-item
# intercept (Z07), three grouping factors, and rows without an outcome in
# the first subject or, when spread is 1, the first item, so that the rows
# without an outcome can leave a subject or an item one row, in a T1 run.
dz_family_latin <- function() {
  dh_family(
    name = "zoo-latin",
    probe = "^(structure|identifiability)\\.|^outcome\\.constant_clusters",
    description = "Z07: Latin square, random slopes and three grouping factors, T1",
    params = list(
      subjects_per_list = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      items_per_condition = dh_param(1:2, natural = c(TRUE, FALSE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      spread = dh_param(0:1, natural = c(TRUE, TRUE), tier = "A")
    ),
    build = function(p) {
      case <- dz_case("Z07", list(lists = 3, subjects_per_list = p$subjects_per_list,
                                  items_per_condition = p$items_per_condition, reps = 1),
                      dh_t1())
      # The first y_missing rows of the first subject, or of the first item
      # when spread is 1.
      within <- if (p$spread == 1L) case$data$item else case$data$subject
      rows <- which(within == within[1L])[seq_len(p$y_missing)]
      case$data$y[rows] <- NA
      case
    }
  )
}

# Classes randomised within schools, one of two classes in each school
# tutored, with a declared cluster-randomised assignment and estimand and a
# formula that omits the class (Z08), the first pupil of class 1 in the other
# arm when mixed is 1 (Z09), and pupils without an outcome, in a T1 run.
dz_family_crt <- function() {
  dh_family(
    name = "zoo-crt",
    probe = "^(structure|identifiability|assignment|outcome)\\.",
    description = "Z08 and Z09: classes randomised within schools, declared estimand, T1",
    alternatives = dz_alternatives_crt,
    params = list(
      schools = dh_param(2:4),
      pupils_per_class = dh_param(1:4, person = TRUE, natural = c(TRUE, FALSE)),
      mixed = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= 2L * p$schools,
    build = function(p) {
      contaminated <- structure(if (p$mixed == 1L) 1 else numeric(0), class = "zoo_array")
      # The last pupil of the first y_missing classes.
      missing <- seq_len(p$y_missing) * p$pupils_per_class
      dz_case("Z08", list(schools = p$schools, classes_per_school = 2,
                          tutoring_per_school = 1, pupils_per_class = p$pupils_per_class,
                          contaminated = contaminated), dh_t1(), missing)
    }
  )
}

# Families of one, two and three children with a by-family slope of a
# covariate that varies within every family (Z11), and second children
# without an outcome, in a T1 run.
dz_family_families <- function() {
  dh_family(
    name = "zoo-families",
    probe = "^(structure|identifiability|outcome)\\.",
    description = "Z11: singleton families beside pairs and triples, random slope, T1",
    alternatives = function(p, case) dz_common_alternatives(case, "y", "family"),
    params = list(
      singles = dh_param(2:4, person = TRUE),
      pairs = dh_param(2:4, person = TRUE),
      triples = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$pairs,
    build = function(p) {
      case <- dz_case("Z11", list(singles = p$singles, pairs = p$pairs, triples = p$triples,
                                  quadruples = 0), dh_t1())
      # The second child of the first y_missing families of two, in label
      # order, whatever their order in the table.
      family <- case$data$family
      sizes <- table(family)
      pairs <- sort(names(sizes)[sizes == 2L], method = "radix")[seq_len(p$y_missing)]
      case$data$y[dz_rows_of(family, pairs, last = TRUE)] <- NA
      case
    }
  )
}

# Subjects and items crossed within two groups, disconnected unless one
# subject of each group swaps an item with the other group (Z13), and rows of
# the second group without an outcome, in a T1 run.
dz_family_disconnected <- function() {
  dh_family(
    name = "zoo-disconnected",
    probe = "^structure\\.connectivity|^(identifiability|outcome)\\.",
    description = "Z13: crossed subjects and items in two groups, with or without a bridge, T1",
    alternatives = dz_alternatives_disconnected,
    params = list(
      subjects_per_group = dh_param(1:3, person = TRUE, natural = c(TRUE, FALSE)),
      items_per_group = dh_param(1:3, natural = c(TRUE, FALSE)),
      bridge = dh_param(0:1, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$subjects_per_group * p$items_per_group,
    build = function(p) {
      case <- dz_case("Z13", list(groups = 2, subjects_per_group = p$subjects_per_group,
                                  items_per_group = p$items_per_group,
                                  bridge = p$bridge == 1L), dh_t1())
      # The first y_missing rows of group g2.
      rows <- which(case$data$group == "g2")[seq_len(p$y_missing)]
      case$data$y[rows] <- NA
      case
    }
  )
}

# A fixed interaction of A and B with B constant at its first level for the
# last level of A when empty_cell is 1 (Z14), in a gaussian T1 run, fourth
# trials without an outcome and, when reduced is 1, trials 2 to 4 of the
# last subject without an outcome, so that a subject keeps one row.
dz_family_empty_cell <- function() {
  dh_family(
    name = "zoo-empty-cell",
    probe = "^(design|identifiability|outcome)\\.",
    description = "Z14: fixed interaction with an empty cell, gaussian, T1",
    alternatives = function(p, case) dz_common_alternatives(case, "y", "subject"),
    params = list(
      subjects_per_level = dh_param(1:3, person = TRUE, natural = c(TRUE, FALSE)),
      empty = dh_param(0:1, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      reduced = dh_param(0:1, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= 3L * p$subjects_per_level - p$reduced,
    build = function(p) {
      S <- 3L * p$subjects_per_level
      # Trial 4 of the first y_missing subjects, and trials 2 to 4 of the
      # last subject when reduced is 1.
      missing <- (seq_len(p$y_missing) - 1L) * 4L + 4L
      if (p$reduced == 1L) {
        missing <- c(missing, (S - 1L) * 4L + 2:4)
      }
      dz_case("Z14", list(levels_A = 3, subjects_per_level = p$subjects_per_level, trials = 4,
                          empty_cell = p$empty == 1L),
              dh_t1(), sort(missing))
    }
  )
}

# Three doses in each clinic with the adherence of the placebo patients
# missing when placebo_missing is 1, so that listwise deletion empties the
# reference level (Z15), and patients at the low dose without an outcome, in
# a T1 run. y_missing counts every row without an outcome: the first
# y_missing - extra patients at the low dose and, when extra is 1, a further
# patient at the low dose of the first clinic, or the placebo patient of the
# last clinic given the low dose when placebo_missing is 1. tied makes the
# outcomes of the last clinic with two analysed rows equal.
dz_family_reference <- function() {
  dh_family(
    name = "zoo-reference",
    probe = "^(sample|design|identifiability|outcome)\\.",
    description = "Z15: reference level emptied by listwise deletion, T1",
    alternatives = dz_alternatives_reference,
    params = list(
      clinics = dh_param(2:4),
      patients_per_dose = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      placebo_missing = dh_param(0:1, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      extra = dh_param(0:1, person = TRUE),
      tied = dh_param(0:1, tier = "A")
    ),
    valid = function(p) {
      p$extra <= p$y_missing && p$y_missing - p$extra <= p$clinics * p$patients_per_dose
    },
    build = function(p) {
      case <- dz_case("Z15", list(clinics = p$clinics, patients_per_dose = p$patients_per_dose,
                                  placebo_missing = p$placebo_missing == 1L,
                                  top_missing = FALSE), dh_t1())
      data <- case$data
      rows <- which(data$dose == "low")[seq_len(p$y_missing - p$extra)]
      data$y[rows] <- NA
      if (p$extra == 1L) {
        if (p$placebo_missing == 1L) {
          # The placebo patient of the last clinic, who leaves the design
          # sample, receives the low dose and lacks the outcome.
          last <- data$clinic[nrow(data)]
          i <- which(data$clinic == last & data$dose == "placebo")[1L]
          data$dose[i] <- "low"
          data$adherence[i] <- data$adherence[which(data$dose == "low")[1L]]
          data$y[i] <- NA
        } else {
          # One more patient at the low dose of the first clinic, without the
          # outcome.
          first <- which(data$dose == "low")[1L]
          row <- data[first, , drop = FALSE]
          row$patient <- sprintf("P%d", nrow(data) + 1L)
          row$y <- NA
          data <- rbind(data[seq_len(first), , drop = FALSE], row,
                        data[-seq_len(first), , drop = FALSE])
          rownames(data) <- NULL
        }
      }
      case$data <- data
      dz_tie(case, "clinic", p$tied)
    }
  )
}

# Binary accuracy whose wrong answers rotate over the items of conditions A
# and B, and of C when ceiling is 0, so that C is answered without error
# when ceiling is 1 (Z24), and rows of condition A without an outcome, in a
# T2 run. The rotation fixes every answer once the parameters are given, so
# the outcome values follow the rows of the template, and its remaining
# determinations are of the class that dh_known_channels() lists, so the
# family does not gate attack (a) (README, The zoo, Gates).
dz_family_separation <- function() {
  dh_family(
    name = "zoo-separation",
    probe = "^outcome\\.",
    description = "Z24: binary accuracy separated by condition, T2",
    gate = FALSE,
    params = list(
      subjects = dh_param(2:4, person = TRUE),
      items_per_condition = dh_param(1:2, natural = c(TRUE, FALSE)),
      ceiling = dh_param(0:1, natural = c(TRUE, TRUE), tier = "A"),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$subjects * p$items_per_condition,
    build = function(p) {
      wrong <- if (p$ceiling == 1L) c("A", "B") else c("A", "B", "C")
      case <- dz_case("Z24", list(subjects = p$subjects,
                                  items_per_condition = p$items_per_condition,
                                  pattern = "rotation",
                                  wrong = structure(wrong, class = "zoo_array")), dh_t2())
      # The first y_missing rows of condition A.
      rows <- which(case$data$cond == "A")[seq_len(p$y_missing)]
      case$data$acc[rows] <- NA
      case
    }
  )
}

# Scores of children in two waves on a scale of 0 to 40, the most able at
# the ceiling in wave 1 or wave 2 and the others below it with scores that
# differ between the waves (Z28), and first waves without an outcome, in a
# T1 run of a bounded score.
dz_family_ceiling <- function() {
  dh_family(
    name = "zoo-ceiling",
    probe = "^outcome\\.(boundary_shares|constant_clusters)",
    description = "Z28: bounded child scores at the ceiling in one or both waves, T1",
    params = list(
      children = dh_param(6:8, person = TRUE),
      ceiling_wave1 = dh_param(0:2, person = TRUE, tier = "A"),
      ceiling_wave2 = dh_param(0:3, person = TRUE, tier = "A"),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$ceiling_wave1 <= p$ceiling_wave2,
    build = function(p) {
      # Wave 1 of the last y_missing children.
      last <- p$children - seq_len(p$y_missing) + 1L
      dz_case("Z28", list(children = p$children, ceiling_wave1 = p$ceiling_wave1,
                          ceiling_wave2 = p$ceiling_wave2),
              dh_t1(), sort((last - 1L) * 2L + 1L))
    }
  )
}

# A multisite trial with a by-site slope of the arm, the last sites holding
# the treatment arm alone (Z30), and participants without an outcome, in a
# T1 run. y_missing counts every row without an outcome: the last
# participant of each of the first y_missing - extra sites and, when extra
# is 1, a further site of one treatment participant without the outcome.
# tied makes the outcomes of the last site with two analysed rows equal.
dz_family_multisite <- function() {
  dh_family(
    name = "zoo-multisite",
    probe = "^(structure|identifiability|outcome)\\.",
    description = "Z30: multisite trial with single-arm sites and a random slope, T1",
    alternatives = dz_alternatives_multisite,
    params = list(
      sites = dh_param(2:4),
      per_arm = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      single_arm_sites = dh_param(0:3),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      extra = dh_param(0:1, person = TRUE),
      tied = dh_param(0:1, tier = "A")
    ),
    valid = function(p) {
      p$single_arm_sites < p$sites && p$extra <= p$y_missing && p$y_missing - p$extra <= p$sites
    },
    build = function(p) {
      single <- seq_len(p$single_arm_sites) + p$sites - p$single_arm_sites
      missing <- seq_len(p$y_missing - p$extra) * 2L * p$per_arm
      case <- dz_case("Z30", list(sites = p$sites, per_arm = p$per_arm,
                                  single_arm_sites = structure(as.numeric(single),
                                                               class = "zoo_array")),
                      dh_t1(), missing)
      if (p$extra == 1L) {
        case$data <- rbind(case$data, data.frame(
          site = sprintf("S%d", p$sites + 1L), participant = sprintf("P%d", nrow(case$data) + 1L),
          arm = "treatment", y = NA_real_, stringsAsFactors = FALSE))
      }
      dz_tie(case, "site", p$tied)
    }
  )
}

# The outcome of every analysed row of a level made equal to the level's
# first analysed outcome, for the first n levels of factor, from the last in
# label order, that hold two analysed rows or more.
dz_tie <- function(case, factor, n) {
  if (n < 1L) {
    return(case)
  }
  outcome <- all.vars(stats::as.formula(case$formula)[[2L]])
  y <- case$data[[outcome]]
  levels <- sort(unique(case$data[[factor]]), method = "radix", decreasing = TRUE)
  done <- 0L
  for (level in levels) {
    rows <- which(case$data[[factor]] == level & !is.na(y))
    if (length(rows) >= 2L) {
      y[rows] <- y[rows[1L]]
      done <- done + 1L
      if (done == n) {
        break
      }
    }
  }
  case$data[[outcome]] <- y
  case
}

# --- The alternatives of the zoo families ------------------------------------------

# Rows added to the data of a case, each a named list of column values, the
# others missing, so that each lacks an outcome unless it gives one.
dz_add_rows <- function(case, ...) {
  for (row in list(...)) {
    new <- case$data[nrow(case$data), , drop = FALSE]
    for (n in names(new)) {
      new[[n]] <- if (is.null(row[[n]])) NA else row[[n]]
    }
    case$data <- rbind(case$data, new)
  }
  rownames(case$data) <- NULL
  case
}

# A case with the value of the family's parameter y_missing that describes
# it, which dh_alternatives() compares with the table's.
dz_alt <- function(case, y_missing) {
  attr(case, "params") <- list(y_missing = y_missing)
  case
}

# The alternatives that every zoo family shares: the table without its rows
# that lack an outcome, without one of them, with one or two more rows
# without an outcome, with a row without an outcome moved to another row,
# with every row of the level of a row without an outcome, and one row of
# another level, without one, with every row of the level of the first row
# without one, and with the outcome made constant within the analysed rows
# of the first and of the last level of each column given.
dz_common_alternatives <- function(case, outcome, columns) {
  d <- case$data
  y <- d[[outcome]]
  miss <- which(is.na(y))
  keep <- which(!is.na(y))
  m <- length(miss)
  out <- list()
  if (m) {
    c1 <- case
    c1$data <- d[-miss, , drop = FALSE]
    rownames(c1$data) <- NULL
    out$without_missing <- dz_alt(c1, 0L)
  }
  if (m > 1L) {
    c1 <- case
    c1$data <- d[-miss[1L], , drop = FALSE]
    rownames(c1$data) <- NULL
    out$without_one_missing <- dz_alt(c1, m - 1L)
  }
  if (length(keep) > 1L) {
    c1 <- case
    c1$data[[outcome]][keep[length(keep)]] <- NA
    out$one_more_missing <- dz_alt(c1, m + 1L)
    c1 <- case
    c1$data[[outcome]][keep[1L]] <- NA
    out$one_more_missing_first <- dz_alt(c1, m + 1L)
    if (length(keep) > 2L) {
      c1$data[[outcome]][keep[length(keep)]] <- NA
      out$two_more_missing <- dz_alt(c1, m + 2L)
    }
    if (m) {
      c1 <- case
      c1$data[[outcome]][keep[1L]] <- NA
      c1$data[[outcome]][miss[1L]] <- y[keep[1L]]
      out$missing_moved <- dz_alt(c1, m)
    }
  }
  if (m) {
    for (column in columns) {
      level <- d[[column]][miss[1L]]
      rows <- which(d[[column]] == level)
      others <- setdiff(keep, rows)
      if (length(others) > 1L) {
        c1 <- case
        c1$data[[outcome]][c(rows, others[length(others)])] <- NA
        out[[paste("level_lost", column, sep = "_")]] <-
          dz_alt(c1, sum(is.na(c1$data[[outcome]])))
      }
    }
  }
  for (column in columns) {
    c1 <- case
    c1$data[[outcome]][d[[column]] == d[[column]][1L]] <- NA
    out[[paste("level_whole", column, sep = "_")]] <- dz_alt(c1, sum(is.na(c1$data[[outcome]])))
  }
  for (column in columns) {
    for (end in c("first", "last")) {
      level <- if (end == "first") d[[column]][1L] else d[[column]][nrow(d)]
      rows <- which(d[[column]] == level & !is.na(y))
      if (length(rows) > 1L) {
        c1 <- case
        c1$data[[outcome]][rows] <- y[rows[1L]]
        out[[paste("constant", column, end, sep = "_")]] <- dz_alt(c1, m)
      }
    }
  }
  out
}

# zoo-reuse: a further pupil without an outcome in the first or the last
# combination, a further label or school whose pupils lack the outcome, a
# label or a school that loses every outcome in a crossing with one school,
# or one label, fewer, and two schools, or two labels, holding the analysed
# rows beside a further label, or school, whose pupils lack the outcome.
dz_alternatives_reuse <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  J <- p$schools
  K <- p$classes
  out <- dz_common_alternatives(case, "y", c("school", "class"))
  out$pupil_first <- dz_alt(dz_add_rows(case, list(school = d$school[1L], class = d$class[1L],
                                                   pupil = "P90")), m + 1L)
  out$pupil_last <- dz_alt(dz_add_rows(case, list(school = d$school[nrow(d)],
                                                  class = d$class[nrow(d)], pupil = "P90")), m + 1L)
  out$new_label <- dz_alt(dz_add_rows(case, list(school = d$school[1L],
                                                 class = as.character(K + 1L), pupil = "P90")),
                          m + 1L)
  out$new_label_two <- dz_alt(dz_add_rows(case,
    list(school = d$school[1L], class = as.character(K + 1L), pupil = "P90"),
    list(school = d$school[nrow(d)], class = as.character(K + 1L), pupil = "P91")), m + 2L)
  out$new_school <- dz_alt(dz_add_rows(case, list(school = paste0("S", J + 1L),
                                                  class = d$class[1L], pupil = "P90")), m + 1L)
  out$new_school_two <- dz_alt(dz_add_rows(case,
    list(school = paste0("S", J + 1L), class = d$class[1L], pupil = "P90"),
    list(school = paste0("S", J + 1L), class = d$class[nrow(d)], pupil = "P91")), m + 2L)
  if (J > 2L) {
    lost <- dz_case("Z01", list(schools = J - 1L, classes = K + 1L, pupils = p$pupils,
                                reuse = TRUE), dh_t1())
    rows <- which(lost$data$class == as.character(K + 1L))
    lost$data$y[rows] <- NA
    out$label_lost <- dz_alt(lost, length(rows))
  }
  if (K > 2L) {
    lost <- dz_case("Z01", list(schools = J + 1L, classes = K - 1L, pupils = p$pupils,
                                reuse = TRUE), dh_t1())
    rows <- which(lost$data$school == lost$data$school[nrow(lost$data)])
    lost$data$y[rows] <- NA
    out$school_lost <- dz_alt(lost, length(rows))
  }
  analysed <- sum(!is.na(d$y))
  crossing <- function(schools, labels, per, lost_school, lost_label) {
    rows <- expand.grid(pupil = seq_len(per), class = seq_len(labels), school = seq_len(schools))
    frame <- data.frame(school = paste0("S", rows$school), class = as.character(rows$class),
                        stringsAsFactors = FALSE)
    if (lost_label) {
      frame <- rbind(frame, data.frame(school = paste0("S", seq_len(schools)),
                                       class = as.character(labels + 1L)))
    }
    if (lost_school) {
      frame <- rbind(frame, data.frame(school = paste0("S", schools + 1L),
                                       class = as.character(seq_len(labels))))
    }
    frame <- frame[order(frame$school, frame$class, method = "radix"), ]
    frame$pupil <- sprintf("P%03d", seq_len(nrow(frame)))
    lacking <- frame$class == as.character(labels + 1L) |
      frame$school == paste0("S", schools + 1L)
    frame$y <- ifelse(lacking, NA, round(sin(seq_len(nrow(frame))), 2))
    rownames(frame) <- NULL
    c1 <- case
    c1$data <- frame[c("school", "class", "pupil", "y")]
    dz_alt(c1, sum(lacking))
  }
  if (m == 0L && analysed %% (2L * K) == 0L) {
    out$label_lost_two_schools <- crossing(2L, K, analysed %/% (2L * K), FALSE, TRUE)
  }
  if (m == 0L && analysed %% (2L * J) == 0L) {
    out$school_lost_two_labels <- crossing(J, 2L, analysed %/% (2L * J), TRUE, FALSE)
  }
  out
}

# zoo-mobility: a further pupil without an outcome at wave 1 of S1, at wave 2
# of S3 or at both waves of S3, and, without movers, as many rows and second
# waves without an outcome held by more pupils, most of them of one wave:
# 6n - 2 - m pupils in the three schools in turn, the first 2 + m with both
# waves and the first m of these without their second outcome.
dz_alternatives_mobility <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  out <- dz_common_alternatives(case, "y", c("school", "pupil"))
  out$pupil_one_wave <- dz_alt(dz_add_rows(case, list(pupil = "P90", school = "S1", wave = 1L)),
                               m + 1L)
  out$pupil_one_wave_last <- dz_alt(dz_add_rows(case, list(pupil = "P90", school = "S3",
                                                           wave = 2L)), m + 1L)
  out$pupil_two_waves <- dz_alt(dz_add_rows(case, list(pupil = "P90", school = "S3", wave = 1L),
                                            list(pupil = "P90", school = "S3", wave = 2L)), m + 2L)
  n <- p$pupils_per_school
  if (p$movers == 0L) {
    two <- 2L + m
    pupils <- 6L * n - 2L - m
    rows <- list()
    for (i in seq_len(pupils)) {
      s <- paste0("S", (i - 1L) %% 3L + 1L)
      rows[[length(rows) + 1L]] <- data.frame(pupil = sprintf("Q%02d", i), school = s, wave = 1L,
                                              y = round(sin(i) * 2, 2), stringsAsFactors = FALSE)
      if (i <= two) {
        rows[[length(rows) + 1L]] <- data.frame(pupil = sprintf("Q%02d", i), school = s,
                                                wave = 2L, y = if (i <= m) NA else round(cos(i), 2),
                                                stringsAsFactors = FALSE)
      }
    }
    c1 <- case
    c1$data <- do.call(rbind, rows)
    out$single_waves <- dz_alt(c1, m)
  }
  out
}

# zoo-crt: a further pupil without an outcome in the class of the second or
# of the last row, a further class or school whose pupils lack the outcome,
# and the rows without an outcome moved to a school of their own.
dz_alternatives_crt <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  miss <- which(is.na(d$y))
  out <- dz_common_alternatives(case, "y", c("school", "class"))
  in_class <- function(i, pupil) {
    list(school = d$school[i], class = d$class[i], arm = d$arm[i], pupil = pupil)
  }
  out$pupil_first <- dz_alt(dz_add_rows(case, in_class(min(2L, nrow(d)), "P090")), m + 1L)
  out$pupil_last <- dz_alt(dz_add_rows(case, in_class(nrow(d), "P090")), m + 1L)
  out$new_class <- dz_alt(dz_add_rows(case, list(school = d$school[1L], class = "C90",
                                                 arm = "tutoring", pupil = "P090")), m + 1L)
  out$new_school <- dz_alt(dz_add_rows(case, list(school = "S9", class = "C90", arm = "control",
                                                  pupil = "P090")), m + 1L)
  out$new_school_two <- dz_alt(dz_add_rows(case,
    list(school = "S9", class = "C90", arm = "control", pupil = "P090"),
    list(school = "S9", class = "C91", arm = "tutoring", pupil = "P091")), m + 2L)
  if (m) {
    c1 <- case
    c1$data <- d[-miss, , drop = FALSE]
    rownames(c1$data) <- NULL
    rows <- lapply(seq_len(m), function(j) {
      list(school = "S9", class = if (j %% 2L) "C90" else "C91",
           arm = if (j %% 2L) "control" else "tutoring", pupil = sprintf("P09%d", j))
    })
    out$missing_school <- dz_alt(do.call(dz_add_rows, c(list(c1), rows)), m)
    if (m == 1L) {
      # A school of two pupils without an outcome in place of the one row,
      # so that a school of two rows loses every outcome.
      out$missing_school_two <- dz_alt(dz_add_rows(c1,
        list(school = "S9", class = "C90", arm = "control", pupil = "P091"),
        list(school = "S9", class = "C91", arm = "tutoring", pupil = "P092")), 2L)
    }
  }
  out
}

# zoo-reference: a further clinic of two patients, at the low and the high
# dose, without an outcome, and a row without a patient label or an outcome
# beside the first row, so that the table holds more rows than patients.
dz_alternatives_reference <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  out <- dz_common_alternatives(case, "y", "clinic")
  adherence <- d$adherence[which(d$dose == "low")[1L]]
  clinic <- sprintf("K%d", p$clinics + 1L)
  out$new_clinic_two <- dz_alt(dz_add_rows(case,
    list(clinic = clinic, patient = "P90", dose = "low", adherence = adherence),
    list(clinic = clinic, patient = "P91", dose = "high", adherence = adherence)), m + 2L)
  out$keyless_row <- dz_alt(dz_add_rows(case, list(clinic = d$clinic[1L], dose = d$dose[1L],
                                                   adherence = d$adherence[1L])), m + 1L)
  if (m == 1L) {
    # A clinic of two patients without an outcome in place of the one row.
    c1 <- case
    c1$data <- d[!is.na(d$y), , drop = FALSE]
    rownames(c1$data) <- NULL
    out$missing_clinic_two <- dz_alt(dz_add_rows(c1,
      list(clinic = clinic, patient = "P90", dose = "low", adherence = adherence),
      list(clinic = clinic, patient = "P91", dose = "high", adherence = adherence)), 2L)
  }
  # When the placebo patients leave the design sample, the last two of them
  # moved to a further clinic at the low and the high dose without an
  # outcome, so that the table keeps its patients while a clinic of two rows
  # of the design sample loses every outcome.
  placebo <- which(d$dose == "placebo" & is.na(d$adherence))
  if (length(placebo) >= 2L) {
    c1 <- case
    i <- placebo[length(placebo) - 1:0]
    c1$data$clinic[i] <- clinic
    c1$data$dose[i] <- c("low", "high")
    c1$data$adherence[i] <- adherence
    c1$data$y[i] <- NA
    c1$data <- c1$data[order(c1$data$clinic, method = "radix"), ]
    rownames(c1$data) <- NULL
    out$placebo_clinic_two <- dz_alt(c1, m + 2L)
  }
  out
}

# zoo-multisite: a further site of one treatment participant, or of one
# participant in each arm, without an outcome.
dz_alternatives_multisite <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  out <- dz_common_alternatives(case, "y", "site")
  site <- sprintf("S%d", length(unique(d$site)) + 1L)
  out$new_site <- dz_alt(dz_add_rows(case, list(site = site, participant = "P90",
                                                arm = "treatment")), m + 1L)
  out$new_site_two <- dz_alt(dz_add_rows(case,
    list(site = site, participant = "P90", arm = "control"),
    list(site = site, participant = "P91", arm = "treatment")), m + 2L)
  out
}

# zoo-disconnected: a further subject or item without an outcome beside the
# first or the last row, a further item held by two subjects, a further
# subject of two items, the last row moved to an item of its own or to the
# first subject, every row on the first item and, with one item in each
# group and every outcome present, every row on the first item in the first
# group beside a second item in the second group whose two subjects lack the
# outcome, so that one item loses every outcome while each group keeps one.
dz_alternatives_disconnected <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$y))
  n <- nrow(d)
  out <- dz_common_alternatives(case, "y", c("subject", "item"))
  out$subject_first_item <- dz_alt(dz_add_rows(case, list(subject = "s90", item = d$item[1L],
                                                          group = d$group[1L])), m + 1L)
  out$subject_last_item <- dz_alt(dz_add_rows(case, list(subject = "s90", item = d$item[n],
                                                         group = d$group[n])), m + 1L)
  out$item_first_subject <- dz_alt(dz_add_rows(case, list(subject = d$subject[1L], item = "i90",
                                                          group = d$group[1L])), m + 1L)
  out$item_last_subject <- dz_alt(dz_add_rows(case, list(subject = d$subject[n], item = "i90",
                                                         group = d$group[n])), m + 1L)
  out$new_item_two <- dz_alt(dz_add_rows(case,
    list(subject = d$subject[1L], item = "i90", group = d$group[1L]),
    list(subject = d$subject[n], item = "i90", group = d$group[n])), m + 2L)
  out$new_item_new_subjects <- dz_alt(dz_add_rows(case,
    list(subject = "s90", item = "i90", group = d$group[n]),
    list(subject = "s91", item = "i90", group = d$group[n])), m + 2L)
  out$new_subject_two <- dz_alt(dz_add_rows(case,
    list(subject = "s90", item = d$item[1L], group = d$group[1L]),
    list(subject = "s90", item = d$item[n], group = d$group[1L])), m + 2L)
  c1 <- case
  c1$data$item[n] <- "i91"
  out$last_row_own_item <- dz_alt(c1, m)
  if (!any(d$subject == d$subject[1L] & d$item == d$item[n])) {
    c1 <- case
    c1$data$subject[n] <- d$subject[1L]
    c1$data$group[n] <- d$group[1L]
    c1$data <- c1$data[order(c1$data$subject, c1$data$item, method = "radix"), ]
    rownames(c1$data) <- NULL
    out$last_row_first_subject <- dz_alt(c1, m)
  }
  c1 <- case
  c1$data$item <- d$item[1L]
  if (!anyDuplicated(paste(c1$data$subject, c1$data$item))) {
    out$one_item <- dz_alt(c1, m)
  }
  if (p$items_per_group == 1L && p$bridge == 0L && m == 0L) {
    c1 <- case
    c1$data$item <- d$item[1L]
    c1$data$group <- d$group[1L]
    c1 <- dz_add_rows(c1, list(subject = "s90", item = "i90", group = d$group[n]),
                      list(subject = "s91", item = "i90", group = d$group[n]))
    out$item_lost <- dz_alt(c1, 2L)
  }
  out
}
