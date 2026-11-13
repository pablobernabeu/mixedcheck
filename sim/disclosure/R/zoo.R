# The pathology zoo in the disclosure-attack tests (sim/disclosure/README.md,
# The zoo): the stored instances, whose shareable documents attack (b) and
# the validator read at the registry's k, and eleven families that build
# small tables from the seeded generators of sim/zoo/R/ with varied
# parameters. The generators are sourced into an environment of their own,
# so that their helpers do not mask those of the harness.

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
# (dh_interior()). A member count of 1 is a natural bound, apart from the
# pupils per class of zoo-crt, which start at 2 (README, The zoo). Attack (b)
# gates every family. Attack (a) gates zoo-ceiling and zoo-latin, in which it
# determines no outcome-derived value. The other nine families keep gate
# FALSE, since some of their determinations are not traced to their fixed
# structure: the generators draw a continuous outcome, which never repeats
# within a level, so that the status of outcome.constant_clusters follows
# the generator, and the families remove the outcome in rows that y_missing
# alone chooses, so that the analysed rows and levels follow it. README (The
# zoo) lists the determinations traced to that structure and those open.
dz_families <- function() {
  list(
    dz_family_reuse(),
    dz_family_mobility(),
    dz_family_latin(),
    dz_family_crt(),
    dz_family_families(),
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
# outcome, in a T1 run.
dz_family_reuse <- function() {
  dh_family(
    name = "zoo-reuse",
    gate = FALSE,
    probe = "^(structure|identifiability|sample|outcome)\\.",
    description = "Z01: class labels reused across schools, declared within_parent, T1",
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
    gate = FALSE,
    probe = "^(structure|identifiability|sample|outcome)\\.",
    description = "Z02: pupils who change school between two waves, nested_mobile, T1",
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
# intercept (Z07), three grouping factors, and rows without an outcome, in a
# T1 run.
dz_family_latin <- function() {
  dh_family(
    name = "zoo-latin",
    probe = "^(structure|identifiability)\\.|^outcome\\.constant_clusters",
    description = "Z07: Latin square, random slopes and three grouping factors, T1",
    params = list(
      subjects_per_list = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      items_per_condition = dh_param(1:2, natural = c(TRUE, FALSE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    build = function(p) {
      dz_case("Z07", list(lists = 3, subjects_per_list = p$subjects_per_list,
                          items_per_condition = p$items_per_condition, reps = 1),
              dh_t1(), seq_len(p$y_missing))
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
    gate = FALSE,
    probe = "^(structure|identifiability|assignment|outcome)\\.",
    description = "Z08 and Z09: classes randomised within schools, declared estimand, T1",
    params = list(
      schools = dh_param(2:4),
      pupils_per_class = dh_param(2:4, person = TRUE),
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
    gate = FALSE,
    probe = "^(structure|identifiability|outcome)\\.",
    description = "Z11: singleton families beside pairs and triples, random slope, T1",
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
    gate = FALSE,
    probe = "^structure\\.connectivity|^(identifiability|outcome)\\.",
    description = "Z13: crossed subjects and items in two groups, with or without a bridge, T1",
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
# last level of A when empty_cell is 1 (Z14), in a gaussian T1 run, and
# fourth trials without an outcome.
dz_family_empty_cell <- function() {
  dh_family(
    name = "zoo-empty-cell",
    gate = FALSE,
    probe = "^(design|identifiability|outcome)\\.",
    description = "Z14: fixed interaction with an empty cell, gaussian, T1",
    params = list(
      subjects_per_level = dh_param(1:3, person = TRUE, natural = c(TRUE, FALSE)),
      empty = dh_param(0:1, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= 3L * p$subjects_per_level,
    build = function(p) {
      # Trial 4 of the first y_missing subjects.
      dz_case("Z14", list(levels_A = 3, subjects_per_level = p$subjects_per_level, trials = 4,
                          empty_cell = p$empty == 1L),
              dh_t1(), (seq_len(p$y_missing) - 1L) * 4L + 4L)
    }
  )
}

# Three doses in each clinic with the adherence of the placebo patients
# missing when placebo_missing is 1, so that listwise deletion empties the
# reference level (Z15), and patients at the low dose without an outcome, in
# a T1 run.
dz_family_reference <- function() {
  dh_family(
    name = "zoo-reference",
    gate = FALSE,
    probe = "^(sample|design|identifiability|outcome)\\.",
    description = "Z15: reference level emptied by listwise deletion, T1",
    params = list(
      clinics = dh_param(2:4),
      patients_per_dose = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      placebo_missing = dh_param(0:1, natural = c(TRUE, TRUE)),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$clinics * p$patients_per_dose,
    build = function(p) {
      case <- dz_case("Z15", list(clinics = p$clinics, patients_per_dose = p$patients_per_dose,
                                  placebo_missing = p$placebo_missing == 1L,
                                  top_missing = FALSE), dh_t1())
      # The first y_missing patients at the low dose.
      rows <- which(case$data$dose == "low")[seq_len(p$y_missing)]
      case$data$y[rows] <- NA
      case
    }
  )
}

# Binary accuracy whose wrong answers rotate over the items of conditions A
# and B, and of C when ceiling is 0, so that C is answered without error
# when ceiling is 1 (Z24), and rows of condition A without an outcome, in a
# T2 run. The rotation fixes every answer once the parameters are given, so
# the outcome values follow the rows of the template and the family does not
# gate the run, as binomial and factor-separation do not.
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
# T1 run.
dz_family_multisite <- function() {
  dh_family(
    name = "zoo-multisite",
    gate = FALSE,
    probe = "^(structure|identifiability|outcome)\\.",
    description = "Z30: multisite trial with single-arm sites and a random slope, T1",
    params = list(
      sites = dh_param(2:4),
      per_arm = dh_param(1:2, person = TRUE, natural = c(TRUE, FALSE)),
      single_arm_sites = dh_param(0:3),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$single_arm_sites < p$sites && p$y_missing <= p$sites,
    build = function(p) {
      single <- seq_len(p$single_arm_sites) + p$sites - p$single_arm_sites
      # The last participant of each of the first y_missing sites.
      missing <- seq_len(p$y_missing) * 2L * p$per_arm
      dz_case("Z30", list(sites = p$sites, per_arm = p$per_arm,
                          single_arm_sites = structure(as.numeric(single), class = "zoo_array")),
              dh_t1(), missing)
    }
  )
}
