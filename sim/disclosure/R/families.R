# Families of small tables for the consistency search (attack a). A family
# is a template whose free parameters are counts: cell sizes, events and
# missing values. Each parameter lists its values, whether it counts persons
# and whether each end of its range is a natural bound (0, or a count that
# the structure of the template fixes) rather than a limit of the family.
# The search runs every combination of values that valid() accepts, so the
# families are small enough to be exhaustive.

# tier is 'A' for a parameter that the outcome's values or missingness
# define, such as outcomes missing or events, and 'B' for one that only the
# design structure defines (privacy.md, Tiers).
dh_param <- function(values, person = FALSE, natural = c(min(values) == 0, FALSE), tier = "B") {
  list(values = values, person = person, natural = natural, tier = tier)
}

# alternatives, when given, is a function of the parameters and the case of
# a table that returns named cases outside the family, each with the
# attribute params holding the values of the family's parameters of tier A
# that describe it, which dh_alternatives() audits beside a table at which
# attack (a) finds a determination.
dh_family <- function(name, params, build, valid = function(p) TRUE, k = 3,
                      description = "", reals = FALSE, probe = ".", gate = TRUE,
                      alternatives = NULL) {
  list(name = name, params = params, build = build, valid = valid, k = k,
       description = description, reals = reals, probe = probe, gate = gate,
       alternatives = alternatives)
}

# The combinations of the parameters of a family that valid() accepts, as a
# data frame with one row for each table. widen adds that many values beyond
# each end of every range that is not a natural bound.
dh_grid <- function(family, widen = 0L) {
  values <- lapply(family$params, function(p) {
    v <- p$values
    if (widen > 0L) {
      step <- if (length(v) > 1L) min(diff(v)) else 1L
      if (!p$natural[1L]) v <- c(min(v) - step * rev(seq_len(widen)), v)
      if (!p$natural[2L]) v <- c(v, max(v) + step * seq_len(widen))
    }
    v
  })
  grid <- expand.grid(values, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  keep <- vapply(seq_len(nrow(grid)), function(i) {
    p <- as.list(grid[i, , drop = FALSE])
    all(unlist(p) >= 0) && isTRUE(family$valid(p))
  }, NA)
  grid <- grid[keep, , drop = FALSE]
  rownames(grid) <- NULL
  grid
}

# Whether a table lies inside its family: no parameter at an end of its
# range that is a limit of the family rather than a natural bound.
dh_interior <- function(family, grid) {
  inside <- rep(TRUE, nrow(grid))
  for (name in names(family$params)) {
    p <- family$params[[name]]
    if (!p$natural[1L]) inside <- inside & grid[[name]] > min(p$values)
    if (!p$natural[2L]) inside <- inside & grid[[name]] < max(p$values)
  }
  inside
}

# Labels with two digits, so that their order is that of their numbers.
dh_labels <- function(prefix, n) {
  sprintf("%s%02d", prefix, seq_len(n))
}

dh_t1 <- function(...) {
  list(outcome_access = "T1", reason = "Disclosure-attack tests.", ...)
}

dh_t2 <- function(...) {
  list(outcome_access = "T2", reason = "Disclosure-attack tests.", exploratory = TRUE, ...)
}

dh_participant <- function(unit, columns = unit) {
  list(name = unit, columns = as.list(columns), role = "participant")
}


dh_unit <- function(name, role = "cluster", nested_in = NULL, id_scope = "global",
                    columns = name) {
  unit <- list(name = name, columns = as.list(columns), role = role)
  if (!is.null(nested_in)) {
    unit$nested_in <- nested_in
    unit$id_scope <- id_scope
  }
  unit
}

dh_declaration <- function(...) {
  c(list(vocabulary = "0.1.0"), list(...))
}

# A covariate that differs between neighbouring rows, and an outcome that
# differs from it, so that neither is constant within a level by accident.
dh_covariate <- function(n) (seq_len(n) * 7L) %% 11L + 0.5
dh_outcome <- function(n) (seq_len(n) * 5L) %% 13L + 0.25

# --- The families ---------------------------------------------------------------------

# Every family of the search, in the order in which they run. run.R --shard
# gives position p to shard ((p - 1) mod N) + 1, so the order also spreads
# the run time of the families over the four shards of CI: crossed, eigen
# and zoo-families stand where they balance them, and bounds and
# factor-separation take the places of minority and labels, which moved to
# the shards that crossed does not lengthen.
dh_families <- function() {
  c(
    list(
      dh_family_sizes(unit = FALSE),
      dh_family_sizes(unit = TRUE),
      dh_family_sizes(unit = FALSE, wide = TRUE),
      dh_family_four_sizes(),
      dh_family_bounds(),
      dh_family_constant(),
      dh_family_zeros(),
      dh_family_minority(),
      dh_family_crossed(unit = FALSE),
      dh_family_blocks(),
      dh_family_assign(),
      dh_family_crossed(unit = TRUE),
      dh_family_factor_separation(),
      dh_family_nested(),
      dh_family_aliased(),
      dh_family_keys(),
      dh_family_unicode(),
      dh_family_two_valued(),
      dh_family_cross_tier(),
      dh_family_quartile(),
      dh_family_assign_school(),
      dh_family_binomial(),
      dh_family_labels(),
      dh_family_two_factor_separation(),
      dh_family_separation_missing(),
      dh_family_chain(),
      dh_family_reals(),
      dh_family_constant_written(),
      dh_family_non_person(),
      dh_family_eigen(),
      dh_family_whole_lost(),
      dh_family_fixed_factor(),
      dh_family_interaction(),
      dh_family_trials()
    ),
    # The families made from the generators of the pathology zoo (R/zoo.R).
    dz_families(),
    # After the zoo, so that no family before it changes shard.
    list(dh_family_collinearity())
  )
}

# Two binary factors a and b whose four combinations hold subjects of two
# rows, n11 in a1:b1, off in each of a1:b2 and a2:b1 and n22 in a2:b2, with
# triple subjects of three rows and single subjects of one row in a2:b2, so
# that the rows of each combination, on which the GVIF of a and b depends,
# are parameters and the reals stay unmasked. Second rows of the last
# y_missing subjects of two rows in a2:b2 lack the outcome, in a Poisson T1
# run whose outcome.zero_shares shows the analysis sample. The zeros lie on
# the first rows of the first three subjects. The family probes the design
# checks alone: its subjects hold at most three rows and none loses every
# outcome, which fixes the analysed subjects of outcome.zero_shares.
dh_family_collinearity <- function() {
  dh_family(
    name = "collinearity",
    probe = "^design\\.(collinearity|rank_deficiency|scale_disparity)",
    description = "two binary factors with varied combinations, GVIF, missing outcomes, Poisson T1",
    params = list(
      n11 = dh_param(2:4, person = TRUE),
      off = dh_param(1:3, person = TRUE),
      n22 = dh_param(2:4, person = TRUE),
      single = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:3, person = TRUE, tier = "A"),
      triple = dh_param(0:1, person = TRUE)
    ),
    valid = function(p) p$y_missing <= p$n22,
    build = function(p) {
      cells <- c(rep(1L, p$n11), rep(2L, p$off), rep(3L, p$off), rep(4L, p$n22))
      sizes <- c(rep(2L, length(cells)), rep(3L, p$triple), rep(1L, p$single))
      cell <- c(cells, rep(4L, p$triple), rep(4L, p$single))
      subjects <- dh_labels("s", length(sizes))
      subject <- rep(subjects, sizes)
      row_cell <- rep(cell, sizes)
      position <- sequence(sizes)
      n <- length(subject)
      y <- 1 + seq_len(n) %% 3L
      y[position == 1L & subject %in% subjects[1:3]] <- 0
      doubles22 <- subjects[seq_along(cells)][cells == 4L]
      lost <- rev(doubles22)[seq_len(p$y_missing)]
      y[position == 2L & subject %in% lost] <- NA
      data <- data.frame(y = y, a = c("a1", "a1", "a2", "a2")[row_cell],
                         b = c("b1", "b2", "b1", "b2")[row_cell], subject = subject,
                         stringsAsFactors = FALSE)
      list(data = data, formula = "y ~ a + b + (1 | subject)",
           args = c(list(family = "poisson"), dh_t1()))
    },
    reals = TRUE
  )
}

# The reals that the two tiers restore beside an analysis sample with no,
# one and k - 1 rows without an outcome: subjects of one, two and three rows
# in which a contrast of -0.5 and 0.5 alternates and second rows without an
# outcome, in a T1 run of a gaussian model, which writes no value of the
# analysis sample, a T1 run of a Poisson model, whose outcome.zero_shares
# writes the analysis sample, and a T2 run of a bernoulli model. The counts
# of each value of the contrast are parameters, so the reals stay unmasked:
# effective_size, icc and smallest_eigenvalue, within_share and the standard
# deviation, which give back the rows of the design sample whenever they are
# written. The zeros and the events lie on the first rows of the first three
# subjects and the rows without an outcome in the last subjects of two rows,
# so that the T1 statistics do not follow the rows without an outcome.
dh_family_reals <- function() {
  dh_family(
    name = "reals",
    probe = "^(structure|identifiability|design|sample)\\.",
    description = "contrast within subjects, no, one and k - 1 rows without an outcome, T1 and T2",
    params = list(
      run = dh_param(1:3, natural = c(TRUE, TRUE)),
      single = dh_param(0:2, person = TRUE),
      double = dh_param(6:8, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    build = function(p) {
      sizes <- c(rep(2L, p$double), rep(3L, p$triple), rep(1L, p$single))
      subject <- rep(dh_labels("s", length(sizes)), sizes)
      position <- sequence(sizes)
      n <- length(subject)
      marked <- position == 1L & subject %in% dh_labels("s", 3L)
      y <- switch(p$run, dh_outcome(n), ifelse(marked, 0, 1 + seq_len(n) %% 3L), as.numeric(marked))
      lost <- dh_labels("s", p$double)[p$double - seq_len(p$y_missing) + 1L]
      y[position == 2L & subject %in% lost] <- NA
      data <- data.frame(y = y, x = ifelse(position == 2L, 0.5, -0.5), subject = subject,
                         stringsAsFactors = FALSE)
      args <- switch(p$run, dh_t1(), c(list(family = "poisson"), dh_t1()),
                     c(list(family = "binomial"), dh_t2()))
      list(data = data, formula = "y ~ x + (1 | subject)", args = args)
    },
    reals = TRUE
  )
}

# Subjects of one and two rows, a constant outcome within k subjects of two
# rows or more and second rows without an outcome in others, at k = 3, so
# that outcome.constant_clusters writes the analysis sample's levels with two
# rows beside the design sample's counts and reals, in a T1 run of a gaussian
# model. A contrast of -0.5 and 0.5 alternates within subjects.
dh_family_constant_written <- function() {
  dh_family(
    name = "constant-written",
    probe = "^(structure|identifiability|design|outcome\\.constant_clusters)",
    description = "outcome constant within k subjects or more, missing outcomes, gaussian, T1",
    params = list(
      single = dh_param(2:4, person = TRUE),
      double = dh_param(7:9, person = TRUE),
      constant = dh_param(3:5, person = TRUE, tier = "A"),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$constant + p$y_missing <= p$double,
    build = function(p) {
      sizes <- c(rep(2L, p$double), rep(1L, p$single))
      subjects <- dh_labels("s", length(sizes))
      subject <- rep(subjects, sizes)
      second <- sequence(sizes) == 2L
      n <- length(subject)
      y <- dh_outcome(n)
      constant <- subjects[p$double - seq_len(p$constant) + 1L]
      y[subject %in% constant & second] <- y[which(subject %in% constant & second) - 1L]
      y[subject %in% subjects[seq_len(p$y_missing)] & second] <- NA
      list(data = data.frame(y = y, x = ifelse(second, 0.5, -0.5), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)", args = dh_t1())
    },
    reals = TRUE
  )
}

# Schools of two or three pupils, the disclosure unit, so that the schools
# count non-persons, schools of one pupil, which make them count persons, and
# pupils without an outcome, in a T1 run of a Poisson model: the written
# levels of a non-person item bound the rows that the design sample loses
# beside the analysis sample. The pupils without an outcome are the second
# pupils of the schools of three pupils, then of the schools of two pupils
# after the first three, whose first pupils hold the zeros, so that the T1
# statistics do not follow them.
dh_family_non_person <- function() {
  dh_family(
    name = "non-person",
    probe = "^(structure|identifiability|sample)\\.",
    description = "schools of pupils, the disclosure unit, missing outcomes, Poisson, T1",
    alternatives = dh_alternatives_non_person,
    params = list(
      two = dh_param(4:6, person = TRUE),
      three = dh_param(0:2, person = TRUE),
      one = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing - min(p$y_missing, p$three) <= p$two - 3L,
    build = function(p) {
      pupils <- c(rep(2L, p$two), rep(3L, p$three), rep(1L, p$one))
      schools <- dh_labels("S", length(pupils))
      school <- rep(schools, pupils)
      second <- sequence(pupils) == 2L
      n <- length(school)
      count <- 1 + seq_len(n) %% 3L
      count[sequence(pupils) == 1L & school %in% schools[1:3]] <- 0
      lost <- c(schools[p$two + seq_len(p$three)], schools[3L + seq_len(p$two - 3L)])
      count[second & school %in% lost[seq_len(p$y_missing)]] <- NA
      declaration <- dh_declaration(units = list(
        dh_unit("school"), dh_unit("pupil", role = "participant", nested_in = "school")))
      list(data = data.frame(count = count, x = dh_covariate(n), school = school,
                             pupil = dh_labels("p", n), stringsAsFactors = FALSE),
           formula = "count ~ x + (1 | school)",
           args = c(list(declaration = declaration, family = "poisson"), dh_t1()))
    }
  )
}

# The alternatives of non-person (dh_alternatives()): those that the zoo
# families share, a further school of one or two pupils without an outcome,
# since no table of the family loses a whole school, and a school of two
# pupils without an outcome in place of one row without one.
dh_alternatives_non_person <- function(p, case) {
  d <- case$data
  m <- sum(is.na(d$count))
  x <- dh_covariate(nrow(d) + 2L)[nrow(d) + 1:2]
  school_two <- function(c1) {
    dz_add_rows(c1, list(school = "S90", pupil = "p90", x = x[1L]),
                list(school = "S90", pupil = "p91", x = x[2L]))
  }
  out <- dz_common_alternatives(case, "count", "school")
  out$new_school <- dz_alt(dz_add_rows(case, list(school = "S90", pupil = "p90", x = x[1L])),
                           m + 1L)
  out$new_school_two <- dz_alt(school_two(case), m + 2L)
  if (m == 1L) {
    c1 <- case
    c1$data <- d[!is.na(d$count), , drop = FALSE]
    rownames(c1$data) <- NULL
    out$missing_school_two <- dz_alt(school_two(c1), 2L)
  }
  # In the family, every school that loses an outcome loses one of two
  # pupils, so the schools, which the class non_person shows to hold two
  # pupils or more, would give the rows without an outcome. Two tables
  # outside the family hold the same analysed rows: without the second row
  # that lacks an outcome, whose school's other pupils join the first school
  # with every outcome, and with the last pupil of the second school with
  # every outcome without it and a pupil with an outcome added to the first.
  miss <- which(is.na(d$count))
  whole <- setdiff(unique(d$school), unique(d$school[miss]))
  if (m > 1L && length(whole)) {
    c1 <- case
    second <- d$school == d$school[miss[2L]]
    c1$data$school[second] <- whole[1L]
    c1$data <- c1$data[-miss[2L], , drop = FALSE]
    rownames(c1$data) <- NULL
    out$schools_merged <- dz_alt(c1, m - 1L)
  }
  if (length(whole) >= 2L) {
    c1 <- case
    last <- max(which(d$school == whole[2L]))
    c1$data$count[last] <- NA
    added <- d[last, , drop = FALSE]
    added$school <- whole[1L]
    added$pupil <- "p90"
    c1$data <- rbind(c1$data, added)
    rownames(c1$data) <- NULL
    out$lost_and_added <- dz_alt(c1, m + 1L)
  }
  # Each row without an outcome swapped with the last pupil of each school
  # with every outcome, which keeps the analysed counts and moves the loss
  # to another school.
  for (i in miss) {
    for (school in whole) {
      j <- max(which(d$school == school))
      c1 <- case
      c1$data$count[c(i, j)] <- c(d$count[j], NA)
      out[[sprintf("swapped_%d_%d", i, j)]] <- dz_alt(c1, m)
    }
  }
  out
}

# Subjects of one and two rows, subjects of one row without their outcome,
# subjects of two rows without their second outcome and an outcome constant
# within three subjects of two rows, in a T1 run of a Poisson model, so that
# outcome.zero_shares writes the analysis sample's rows and levels and
# outcome.constant_clusters its levels with two rows beside the design
# sample's counts. The outcome values follow the rows, so the T1 statistics
# that the template fixes make its determinations of attack (a) candidates.
dh_family_cross_tier <- function() {
  dh_family(
    name = "cross-tier",
    gate = FALSE,
    probe = "^(structure|identifiability|sample)\\.",
    description = "subjects of one and two rows losing outcomes, Poisson, T1",
    params = list(
      single = dh_param(3:6, person = TRUE),
      double = dh_param(6:8, person = TRUE),
      single_lost = dh_param(0:4, person = TRUE, tier = "A"),
      double_reduced = dh_param(0:3, person = TRUE, tier = "A")
    ),
    valid = function(p) p$single_lost <= p$single && p$double_reduced <= p$double - 3L,
    build = function(p) {
      sizes <- c(rep(2L, p$double), rep(1L, p$single))
      subjects <- dh_labels("s", length(sizes))
      subject <- rep(subjects, sizes)
      second <- sequence(sizes) == 2L
      n <- length(subject)
      count <- (seq_len(n) * 5L) %% 4L
      constant <- subjects[seq_len(3L)]
      count[subject %in% constant] <- 2
      reduced <- subjects[3L + seq_len(p$double_reduced)]
      count[subject %in% reduced & second] <- NA
      count[subject %in% subjects[p$double + seq_len(p$single_lost)]] <- NA
      list(data = data.frame(count = count, x = dh_covariate(n), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "count ~ x + (1 | subject)",
           args = c(list(family = "poisson"), dh_t1()))
    }
  )
}

# Subjects of one, two and three rows, subjects of one row whose covariate is
# missing, rows whose subject is missing under an observation key and second
# rows without an outcome, in a T1 run of a Poisson model, so that the table,
# the design sample and the analysis sample differ by counts on either side
# of k and the rules that compare the design sample with the table and with
# missing_key_rows fire or not beside a design sample that loses its rows to
# the analysis sample, the chains of comparisons of rules 1 and 4 of Across
# findings.
dh_family_chain <- function() {
  dh_family(
    name = "chain",
    probe = "^(keys\\.duplicates|sample\\.raw_vs_analysis|structure\\.cluster_sizes)",
    description = "table, design sample and analysis sample nested, observation key, Poisson, T1",
    alternatives = function(p, case) dz_common_alternatives(case, "y", "subject"),
    params = list(
      single = dh_param(0:2, person = TRUE),
      double = dh_param(4:6, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      x_lost = dh_param(0:4, person = TRUE),
      missing_key = dh_param(0:3, person = TRUE),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$double,
    build = function(p) {
      subjects <- c(dh_labels("s", p$double), dh_labels("t", p$triple), dh_labels("o", p$single),
                    dh_labels("u", p$x_lost), dh_labels("m", p$missing_key))
      sizes <- c(rep(2L, p$double), rep(3L, p$triple), rep(1L, p$single + p$x_lost + p$missing_key))
      subject <- rep(subjects, sizes)
      trial <- sequence(sizes)
      n <- length(subject)
      x <- dh_covariate(n)
      x[substr(subject, 1L, 1L) == "u"] <- NA
      y <- (seq_len(n) * 5L) %% 4L
      y[subject %in% dh_labels("s", p$double)[seq_len(p$y_missing)] & trial == 2L] <- NA
      subject[substr(subject, 1L, 1L) == "m"] <- NA
      declaration <- dh_declaration(observation = list(key = list("subject", "trial")))
      list(data = data.frame(y = y, x = x, subject = subject, trial = trial, stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)",
           args = c(list(declaration = declaration, family = "poisson"), dh_t1()))
    }
  )
}

# One grouping factor of subjects with one, two or three rows, a covariate
# that varies within subjects and second rows without the covariate or the
# outcome, in a T1 run of a gaussian model. The subjects are the disclosure
# unit, or there is none. The wide variant has up to k + 1 missing values of
# each, so that one sample can exceed another by k or more in one quantity
# and by fewer in another, and a subject of one row without an outcome. Its
# determinations of attack (a) rest in part on the template, in which every
# subject keeps a row with the covariate, and are candidates.
dh_family_sizes <- function(unit, wide = FALSE) {
  missing <- if (wide) 0:4 else 0:2
  dh_family(
    name = paste0("sizes", if (unit) "-unit", if (wide) "-wide"),
    gate = !wide,
    probe = "^(structure|identifiability|sample|design|labels)\\.",
    description = "subjects of one to three rows, missing covariate and outcome, gaussian, T1",
    alternatives = dh_alternatives_sizes,
    params = list(
      single = dh_param(0:3, person = TRUE),
      double = dh_param(2:5, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      x_missing = dh_param(missing, person = TRUE),
      y_missing = dh_param(missing, person = TRUE, tier = "A"),
      single_lost = dh_param(if (wide) 0:1 else 0L, person = TRUE, natural = c(TRUE, TRUE), tier = "A")
    ),
    valid = function(p) p$x_missing + p$y_missing <= p$double && p$single_lost <= p$single,
    build = function(p) {
      sizes <- c(rep(1L, p$single), rep(2L, p$double), rep(3L, p$triple))
      subjects <- dh_labels("s", length(sizes))
      subject <- rep(subjects, sizes)
      second <- sequence(sizes) == 2L
      n <- length(subject)
      x <- dh_covariate(n)
      y <- dh_outcome(n)
      doubles <- subjects[sizes == 2L]
      x[subject %in% doubles[seq_len(p$x_missing)] & second] <- NA
      y[subject %in% doubles[p$x_missing + seq_len(p$y_missing)] & second] <- NA
      y[subject %in% subjects[sizes == 1L][seq_len(p$single_lost)]] <- NA
      declaration <- if (unit) dh_declaration(units = list(dh_participant("subject")))
      list(data = data.frame(y = y, x = x, subject = subject, stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)",
           args = c(list(declaration = declaration), dh_t1()))
    }
  )
}

# The alternatives of the sizes families (dh_alternatives()): those that
# the zoo families share, each described by its own rows of the design
# sample without an outcome in subjects of two such rows or more (y_missing)
# and subjects of one such row without an outcome (single_lost). A subject
# of two rows whose second lacks the covariate has one row in the design
# sample, which can lose its outcome as a subject of one row can.
dh_alternatives_sizes <- function(p, case) {
  lapply(dz_common_alternatives(case, "y", "subject"), function(alternative) {
    d <- alternative$data
    design <- !is.na(d$x) & !is.na(d$subject)
    sizes <- as.vector(table(d$subject[design])[d$subject])
    sizes[is.na(sizes)] <- 0L
    lost <- design & is.na(d$y)
    attr(alternative, "params") <- list(y_missing = sum(lost & sizes >= 2L),
                                        single_lost = sum(lost & sizes == 1L))
    alternative
  })
}

# Subjects of one to four rows, with the counts of each size as parameters,
# in a T0 run, so that the level sizes take up to four values. The family
# runs at k = 4: written singletons fewer than the position of a quantile
# bound it from below by 2, which the bound k - 1 of the detail 'min_count'
# meets at k = 3 only.
dh_family_four_sizes <- function() {
  dh_family(
    name = "four-sizes",
    k = 4,
    gate = FALSE,
    probe = "^structure\\.cluster_sizes",
    description = "subjects of one to four rows, T0",
    params = list(
      one = dh_param(0:5, person = TRUE),
      two = dh_param(0:4, person = TRUE),
      three = dh_param(0:3, person = TRUE),
      four = dh_param(0:3, person = TRUE)
    ),
    valid = function(p) p$one + p$two + p$three + p$four >= 4L,
    build = function(p) {
      sizes <- rep(1:4, c(p$one, p$two, p$three, p$four))
      subject <- rep(dh_labels("s", length(sizes)), sizes)
      n <- length(subject)
      list(data = data.frame(y = dh_outcome(n), x = dh_covariate(n), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)", args = list())
    }
  )
}

# Subjects of two rows with no, one or two events of a bernoulli outcome, and
# second rows without the outcome, in a T1 run.
dh_family_minority <- function() {
  dh_family(
    name = "minority",
    gate = FALSE,
    probe = "^outcome\\.minority_events",
    description = "subjects of two rows with no, one or two events, missing outcomes, T1",
    params = list(
      none = dh_param(0:3, person = TRUE, tier = "A"),
      one = dh_param(1:4, person = TRUE, tier = "A"),
      both = dh_param(0:3, person = TRUE, tier = "A"),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$y_missing <= p$one,
    build = function(p) {
      kinds <- rep(0:2, c(p$none, p$one, p$both))
      subject <- rep(dh_labels("s", length(kinds)), each = 2L)
      y <- as.numeric(rep(kinds, each = 2L) > rep(c(0, 1), length(kinds)))
      ones <- which(kinds == 1L)[seq_len(p$y_missing)]
      y[2L * ones] <- NA
      list(data = data.frame(y = y, x = dh_covariate(length(y)), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)", args = c(list(family = "binomial"), dh_t1()))
    }
  )
}

# Subjects of two rows whose outcome is constant within some of them, and
# second rows without the outcome, in subjects with and without a constant
# outcome.
dh_family_constant <- function() {
  dh_family(
    name = "constant",
    probe = "^outcome\\.constant_clusters",
    description = "outcome constant within some subjects, missing outcomes, gaussian, T1",
    params = list(
      double = dh_param(3:6, person = TRUE),
      constant = dh_param(0:3, person = TRUE, tier = "A"),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      constant_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) {
      p$constant + p$y_missing <= p$double && p$constant_missing <= p$constant
    },
    build = function(p) {
      subjects <- dh_labels("s", p$double)
      subject <- rep(subjects, each = 2L)
      second <- rep(c(FALSE, TRUE), p$double)
      y <- dh_outcome(length(subject))
      constant <- subjects[seq_len(p$constant)]
      y[subject %in% constant & second] <- y[which(subject %in% constant & second) - 1L]
      others <- setdiff(subjects, constant)
      y[subject %in% others[seq_len(p$y_missing)] & second] <- NA
      y[subject %in% constant[seq_len(p$constant_missing)] & second] <- NA
      list(data = data.frame(y = y, subject = subject, stringsAsFactors = FALSE),
           formula = "y ~ 1 + (1 | subject)", args = dh_t1())
    }
  )
}

# Counts of two rows by subject, both 0, one 0 or none, with outcomes
# missing, in a T1 run of a Poisson model.
dh_family_zeros <- function() {
  dh_family(
    name = "zeros",
    gate = FALSE,
    probe = "^outcome\\.(zero_shares|constant_clusters)",
    description = "counts with zeros by subject, missing outcomes, poisson, T1",
    params = list(
      single = dh_param(0:2, person = TRUE),
      double = dh_param(3:6, person = TRUE),
      triple = dh_param(0:1, person = TRUE),
      all_zero = dh_param(0:3, person = TRUE, tier = "A"),
      one_zero = dh_param(0:3, person = TRUE, tier = "A"),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$all_zero + p$one_zero + p$y_missing <= p$double,
    build = function(p) {
      subject <- c(rep(dh_labels("s", p$double), each = 2L),
                   dh_labels("t", p$single), rep(dh_labels("u", p$triple), each = 3L))
      n <- length(subject)
      count <- (seq_len(n) %% 4L) + 1
      first <- seq(1L, n, by = 2L)
      zero <- first[seq_len(p$all_zero)]
      count[c(zero, zero + 1L)] <- 0
      count[first[p$all_zero + seq_len(p$one_zero)]] <- 0
      missing <- first[p$all_zero + p$one_zero + seq_len(p$y_missing)] + 1L
      count[missing] <- NA
      list(data = data.frame(count = count, x = dh_covariate(n), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "count ~ x + (1 | subject)", args = c(list(family = "poisson"), dh_t1()))
    }
  )
}

# A bounded score at its floor, at its ceiling and between them, in a model
# without grouping factors.
dh_family_bounds <- function() {
  dh_family(
    name = "bounds",
    probe = "^outcome\\.boundary_shares",
    description = "bounded score at its floor and ceiling, T1",
    params = list(
      at_floor = dh_param(0:4, person = TRUE, tier = "A"),
      at_ceiling = dh_param(0:4, person = TRUE, tier = "A"),
      between = dh_param(1:12, person = TRUE, tier = "A")
    ),
    build = function(p) {
      score <- c(rep(0, p$at_floor), rep(10, p$at_ceiling), 1 + seq_len(p$between) %% 8)
      declaration <- dh_declaration(variables = list(
        score = list(role = "outcome", measurement = "bounded_score", bounds = list(0, 10))
      ))
      list(data = data.frame(score = score, x = dh_covariate(length(score))),
           formula = "score ~ x", args = c(list(declaration = declaration), dh_t1()))
    }
  )
}

# Two assignments between subjects, the second missing for the subjects
# that lack the first and for some more, an assignment that varies within a
# subject and subjects without an outcome, in a T1 run.
dh_family_assign <- function() {
  dh_family(
    name = "assign",
    probe = "^assignment\\.",
    description = "two nested assignments between subjects, missing outcome, T1",
    alternatives = dh_alternatives_assign,
    params = list(
      subjects = dh_param(4:7, person = TRUE),
      z1_missing = dh_param(0:3, person = TRUE),
      z2_extra = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      mixed = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE))
    ),
    valid = function(p) p$z1_missing + p$z2_extra + p$y_missing + p$mixed <= p$subjects,
    build = function(p) {
      subjects <- dh_labels("s", p$subjects)
      subject <- rep(subjects, each = 2L)
      index <- match(subject, subjects)
      z1 <- c("a", "b")[index %% 2L + 1L]
      z2 <- c("c", "d")[(index %/% 2L) %% 2L + 1L]
      z1[index <= p$z1_missing] <- NA
      z2[index <= p$z1_missing + p$z2_extra] <- NA
      y <- dh_outcome(length(subject))
      y[index > p$subjects - p$y_missing] <- NA
      if (p$mixed > 0L) {
        mixed <- p$subjects - p$y_missing
        z1[which(index == mixed)[2L]] <- if (z1[which(index == mixed)[1L]] == "a") "b" else "a"
      }
      declaration <- dh_declaration(units = list(dh_participant("subject")), assignment = list(
        list(column = "z1", unit = "subject", randomised = TRUE, level = "between_unit"),
        list(column = "z2", unit = "subject", randomised = TRUE, level = "between_unit")
      ))
      list(data = data.frame(y = y, x = dh_covariate(length(subject)), subject = subject, z1 = z1,
                             z2 = z2, stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)", args = c(list(declaration = declaration), dh_t1()))
    }
  )
}

# The alternatives of assign (dh_alternatives()): those that the zoo
# families share. The subject whose z1 varies is the last subject with an
# outcome in the family, so its place, which the findings of the T0 checks
# show, gives y_missing within the family alone, and a table with a row
# without an outcome moved, or with one more, traces it.
dh_alternatives_assign <- function(p, case) {
  dz_common_alternatives(case, "y", "subject")
}

# Classes of pupils within schools, the arm assigned by class in blocks of
# schools, classes of one pupil, classes without an arm and a class whose arm
# varies, in a T0 run.
dh_family_blocks <- function() {
  dh_family(
    name = "blocks",
    probe = "^assignment\\.",
    description = "arm assigned by class within schools, classes of one pupil, T0",
    params = list(
      schools = dh_param(3:4, person = FALSE, natural = c(FALSE, FALSE)),
      single = dh_param(0:3, person = TRUE),
      arm_missing = dh_param(0:2, person = TRUE),
      mixed = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE))
    ),
    valid = function(p) p$arm_missing + p$mixed <= 2L * p$schools,
    build = function(p) {
      classes <- dh_labels("c", 2L * p$schools)
      pupils <- ifelse(seq_along(classes) <= p$single, 1L, 2L)
      class <- rep(classes, pupils)
      school <- dh_labels("S", p$schools)[(match(class, classes) + 1L) %/% 2L]
      pupil <- dh_labels("p", length(class))
      index <- match(class, classes)
      arm <- c("a", "b")[index %% 2L + 1L]
      arm[index > length(classes) - p$arm_missing] <- NA
      if (p$mixed > 0L) {
        mixed <- which(pupils == 2L & seq_along(classes) <= length(classes) - p$arm_missing)
        rows <- which(index == mixed[length(mixed)])
        arm[rows[2L]] <- if (arm[rows[1L]] == "a") "b" else "a"
      }
      declaration <- dh_declaration(units = list(
        dh_unit("school"), dh_unit("class", nested_in = "school"),
        dh_unit("pupil", role = "participant", nested_in = "class")
      ), assignment = list(list(column = "arm", unit = "class", randomised = TRUE,
                                level = "between_unit", blocks = list("school"))))
      list(data = data.frame(y = dh_outcome(length(class)), school = school, class = class,
                             pupil = pupil, arm = arm, stringsAsFactors = FALSE),
           formula = "y ~ 1 + (1 | school) + (1 | class)", args = list(declaration = declaration))
    }
  )
}

# Two crossed grouping factors whose combinations hold two rows each, apart
# from combinations of one row, empty combinations and combinations without
# an outcome, in a T1 run of a Poisson model. Each row is a pupil, the
# disclosure unit, or there is none. crossed takes g and h of 2 to 4, so
# that its tables of 3 levels of each lie inside its limits, and valid()
# leaves every level of h a combination that is not empty. Its alternatives
# trace the determinations of those tables (dh_crossed_alternatives()), and
# the class kept-levels accepts the others (R/kept.R), so both gate attack
# (a).
dh_family_crossed <- function(unit) {
  sizes <- if (unit) 3:4 else 2:4
  dh_family(
    name = paste0("crossed", if (unit) "-unit" else ""),
    probe = "^structure\\.(label_incidence|connectivity)|g:h",
    description = "two crossed factors, cells of one row, empty cells, missing outcomes, T1",
    alternatives = if (!unit) dh_crossed_alternatives,
    params = list(
      g = dh_param(sizes, person = FALSE, natural = c(FALSE, FALSE)),
      h = dh_param(sizes, person = FALSE, natural = c(FALSE, FALSE)),
      single = dh_param(0:2, person = TRUE),
      empty = dh_param(0:2, person = TRUE),
      y_missing = dh_param(0:4, person = TRUE, tier = "A")
    ),
    build = function(p) {
      m <- p$g * p$h
      rows <- rep(2L, m)
      # The cells changed lie apart, one in each row of g where possible.
      order <- order(seq_len(m) %% p$h, seq_len(m))
      rows[order[seq_len(p$empty)]] <- 0L
      rows[order[p$empty + seq_len(p$single)]] <- 1L
      lost <- order[p$empty + p$single + seq_len(p$y_missing)]
      missing <- rep(0L, m)
      missing[lost] <- rows[lost]
      dh_crossed_case(matrix(rows, p$g, p$h, byrow = TRUE),
                      matrix(missing, p$g, p$h, byrow = TRUE), unit)
    },
    valid = function(p) {
      p$single + p$empty + p$y_missing <= p$g * p$h - 1L && p$empty < p$g
    }
  )
}

# A table of the template of crossed from the rows of each combination of g
# and h, sizes, a matrix with one row for each level of g and one column for
# each level of h, and missing, the rows among them without an outcome, which
# are the last rows of their combination. The rows take the outcome and the
# covariate of the template in order.
dh_crossed_case <- function(sizes, missing, unit = FALSE) {
  cells <- expand.grid(h = dh_labels("h", ncol(sizes)), g = dh_labels("g", nrow(sizes)),
                       stringsAsFactors = FALSE)[, c("g", "h")]
  rows <- as.vector(t(sizes))
  lost <- as.vector(t(missing))
  cell <- rep(seq_len(nrow(cells)), rows)
  data <- cells[cell, , drop = FALSE]
  n <- nrow(data)
  data$count <- (seq_len(n) %% 4L) + 1
  position <- ave(seq_len(n), cell, FUN = seq_along)
  data$count[position > (rows - lost)[cell]] <- NA
  data$x <- dh_covariate(n)
  data$pupil <- dh_labels("p", n)
  rownames(data) <- NULL
  declaration <- if (unit) dh_declaration(units = list(dh_participant("pupil")))
  list(data = data, formula = "count ~ x + (1 | g) + (1 | h) + (1 | g:h)",
       args = c(list(declaration = declaration, family = "poisson"), dh_t1()))
}

# The alternatives of crossed, tables outside the family that read alike with
# a table of 3 levels of g and of h and give a determination of it another
# value, found by the analysis of 13 November 2026 (docs/provenance.md) and,
# for the determinations that only the full reduction makes, by the review
# of 14 November 2026: the
# cells rearranged within the 3 by 3 design, a further level of g or of h, or
# of both, with rows without an outcome, the analysed rows gathered in one
# level and cells of one row placed so that rule 3 hides the analysed
# combinations of a design that is no longer crossed. Each is given by the
# rows of its combinations and the rows among them without an outcome, rows
# of g separated by '/', for the values of single, empty and y_missing of
# the table that it serves. Every table with a row without an outcome also
# has the alternative x_missing, in which its first such row has an outcome
# and lacks the covariate, so that it leaves the design sample. The value of
# y_missing that describes an alternative is the number of its combinations
# without any outcome, as in the family.
dh_crossed_alternatives <- function(p, case) {
  describe <- function(alternative) {
    d <- alternative$data
    lost <- tapply(is.na(d$count), paste(d$g, d$h), all)
    attr(alternative, "params") <- list(y_missing = sum(lost))
    alternative
  }
  out <- list()
  if (p$g == 3L && p$h == 3L) {
    table <- matrix(dh_crossed_tables, ncol = 4L, byrow = TRUE)
    matrix_of <- function(text) {
      groups <- strsplit(strsplit(text, "/", fixed = TRUE)[[1L]], ",", fixed = TRUE)
      do.call(rbind, lapply(groups, as.integer))
    }
    mine <- table[table[, 1L] == paste(p$single, p$empty, p$y_missing, sep = ","), , drop = FALSE]
    for (i in seq_len(nrow(mine))) {
      out[[mine[i, 2L]]] <- describe(dh_crossed_case(matrix_of(mine[i, 3L]),
                                                     matrix_of(mine[i, 4L])))
    }
  }
  lacking <- which(is.na(case$data$count))
  if (length(lacking)) {
    first <- lacking[1L]
    case$data$count[first] <- (first %% 4L) + 1
    case$data$x[first] <- NA
    out$x_missing <- describe(case)
  }
  out
}

# The alternatives of dh_crossed_alternatives(): the values of single, empty
# and y_missing of the table, the name, the rows of each combination and the
# rows without an outcome among them.
dh_crossed_tables <- c(
  "0,0,0", "lose_1_2_3", "2,2,2/3,2,2/3,2,2",
    "2,0,0/0,0,0/0,0,0",
  "0,0,1", "H5", "2,2,1,1/2,2,2,0/2,1,2,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/1,0,0,0",
  "0,0,1", "H6", "2,2,1/2,2,2/2,1,2/1,1,0",
    "0,0,0/0,0,0/0,0,0/1,1,0",
  "0,0,1", "H7", "2,2,1,1/2,2,2,1/2,1,2,0",
    "0,0,0,1/0,0,0,1/0,0,0,0",
  "0,0,2", "A1", "2,2,1/2,2,1/2,2,1/1,1,1",
    "0,0,0/0,0,0/0,0,1/1,1,1",
  "0,0,2", "A2", "2,2,2,1/2,2,2,1/1,1,1,1",
    "0,0,0,1/0,0,0,1/0,0,1,1",
  "0,0,2", "split_1_1", "2,2,2/2,2,2/2,2,2",
    "1,0,1/0,0,2/0,0,0",
  "0,0,3", "T7a", "2,2,1,1/2,2,1,1/2,2,1,1",
    "0,0,1,1/0,0,1,1/0,0,1,1",
  "0,0,3", "T7b", "2,2,1/2,2,1/2,2,1/1,1,1",
    "0,0,1/0,0,1/0,0,1/1,1,1",
  "0,0,3", "T7c", "4,1,1/4,1,1/4,1,1",
    "0,1,1/0,1,1/0,1,1",
  "0,0,3", "c1+1+0 c2-1+0", "3,2,2/1,2,2/2,2,2",
    "0,0,2/0,0,2/0,0,2",
  "0,0,3", "c1+1+1 c7-1-1", "3,2,1/2,2,2/2,2,2",
    "1,0,1/0,0,2/0,0,2",
  "0,1,0", "c1+1+0 c2+0+1", "3,2,0/2,2,2/2,2,2",
    "0,0,0/1,0,0/0,0,0",
  "0,1,0", "c1+1+0 c2-1+0", "3,2,0/1,2,2/2,2,2",
    "0,0,0/0,0,0/0,0,0",
  "0,1,0", "extra_missing_1", "3,2,0/2,2,2/2,2,2",
    "1,0,0/0,0,0/0,0,0",
  "0,1,0", "gX@1+hX@1", "2,2,0,1/2,2,2,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/1,0,0,0",
  "0,1,0", "gX@1m c4+1+1", "2,2,0/2,2,2/2,2,2/2,0,0",
    "0,0,0/0,0,0/0,0,0/2,0,0",
  "0,1,0", "gX@1m", "2,2,0/2,2,2/2,2,2/1,0,0",
    "0,0,0/0,0,0/0,0,0/1,0,0",
  "0,1,0", "hX@1m c10+1+1", "2,2,0,2/2,2,2,0/2,2,2,0",
    "0,0,0,2/0,0,0,0/0,0,0,0",
  "0,1,0", "hX@1m", "2,2,0,1/2,2,2,0/2,2,2,0",
    "0,0,0,1/0,0,0,0/0,0,0,0",
  "0,1,1", "T10a", "2,2,0/2,2,0/2,2,2/1,1,0",
    "0,0,0/0,0,0/0,0,0/1,1,0",
  "0,1,1", "T10b", "2,2,0,1/2,2,0,1/2,2,2,0",
    "0,0,0,1/0,0,0,1/0,0,0,0",
  "0,1,1", "c1+1+0 c2-1+0", "3,2,0/1,2,2/2,2,2",
    "0,0,0/0,0,2/0,0,0",
  "0,1,1", "c8-1-1 gX@1m", "2,2,0/2,2,1/2,2,2/1,0,0",
    "0,0,0/0,0,1/0,0,0/1,0,0",
  "0,1,1", "c8-1-1 hX@1m", "2,2,0,1/2,2,1,0/2,2,2,0",
    "0,0,0,1/0,0,1,0/0,0,0,0",
  "0,1,1", "gX@3+hX@1 c10-1-1 c10-1-1", "2,2,0,1/2,2,0,0/2,2,2,0/0,0,1,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/0,0,1,0",
  "0,1,1", "lost_one_8", "2,2,0/2,2,1/2,2,2",
    "0,0,0/0,0,1/0,0,0",
  "0,1,2", "C1", "4,1,0/4,0,1/4,1,1",
    "0,1,0/0,0,1/0,1,1",
  "0,1,2", "C2", "3,2,0/2,2,2/3,1,1",
    "0,0,0/0,0,2/0,1,1",
  "0,1,2", "T4a", "2,1,0/3,3,1/3,2,1",
    "1,1,0/0,0,1/0,0,1",
  "0,1,2", "c1+1+0 c2-1+0", "3,2,0/1,2,2/2,2,2",
    "0,0,0/0,0,2/0,0,2",
  "0,1,2", "c1+1+1 c8-1-1", "3,2,0/2,2,1/2,2,2",
    "1,0,0/0,0,1/0,0,2",
  "0,1,2", "c8-1-1 gX@1m", "2,2,0/2,2,1/2,2,2/1,0,0",
    "0,0,0/0,0,1/0,0,2/1,0,0",
  "0,1,2", "c8-1-1 hX@1m", "2,2,0,1/2,2,1,0/2,2,2,0",
    "0,0,0,1/0,0,1,0/0,0,2,0",
  "0,1,2", "gX@1+hX@1 c10-1-1 c11-1-1", "2,2,0,1/2,2,1,0/2,2,1,0/1,0,0,0",
    "0,0,0,1/0,0,1,0/0,0,1,0/1,0,0,0",
  "0,1,3", "T8a", "4,2,0/3,0,2/3,1,1",
    "0,2,0/0,0,2/0,1,1",
  "0,1,3", "c1-1-1 gX@1m", "1,2,0/2,2,2/2,2,2/1,0,0",
    "1,0,0/0,0,2/0,0,2/1,0,0",
  "0,1,3", "c1-1-1 hX@1m", "1,2,0,1/2,2,2,0/2,2,2,0",
    "1,0,0,1/0,0,2,0/0,0,2,0",
  "0,1,3", "c2+1+0 c4-1+0", "2,1,0/3,2,2/2,2,2",
    "2,0,0/0,0,2/0,0,2",
  "0,1,3", "gX@1+hX@1 c1-1-1 c1-1-1", "0,2,0,1/2,2,2,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/0,0,2,0/0,0,2,0/1,0,0,0",
  "0,1,3", "split_1_2", "2,2,0/2,2,2/2,2,2",
    "1,0,0/1,0,2/0,0,2",
  "1,0,0", "G1", "2,2,1,1/2,2,2,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/1,0,0,0",
  "1,0,0", "G3", "2,2,1/2,2,2/2,2,2/1,1,0",
    "0,0,0/0,0,0/0,0,0/1,1,0",
  "1,0,0", "G4", "2,2,1,1/2,2,2,1/2,2,2,0",
    "0,0,0,1/0,0,0,1/0,0,0,0",
  "1,0,0", "lose_1_2_3", "2,2,1/3,2,2/3,2,2",
    "2,0,0/0,0,0/0,0,0",
  "1,0,0", "single_half_7", "2,2,2/2,2,2/2,2,2",
    "0,0,1/0,0,0/0,0,0",
  "1,0,1", "singles_1_5_9", "1,2,2/2,1,2/2,2,1",
    "0,0,0/0,0,0/0,0,0",
  "1,0,1", "singles_1_5_half_9", "1,2,2/2,1,2/2,2,2",
    "0,0,0/0,0,0/0,0,1",
  "1,0,1", "halves_5_9", "1,2,2/2,2,2/2,2,2",
    "0,0,0/0,1,0/0,0,1",
  "1,0,2", "E1", "2,2,1/2,3,1/4,1,1",
    "0,0,0/0,1,1/0,1,1",
  "1,0,2", "T13a", "1,1,1/3,2,2/2,3,2",
    "0,1,1/0,0,1/0,0,1",
  "1,0,2", "c1+1+0 c2-1+0", "3,2,1/1,2,2/2,2,2",
    "0,0,0/0,0,2/0,0,2",
  "1,0,2", "c1+1+1 c8-1-1", "3,2,1/2,2,1/2,2,2",
    "1,0,0/0,0,1/0,0,2",
  "1,0,3", "T6a", "2,2,1/2,2,1/2,1,1/1,1,1",
    "0,0,0/0,0,1/0,1,1/1,1,1",
  "1,0,3", "T6b", "2,2,1,1/2,2,2,1/1,1,1,1",
    "0,0,0,1/0,0,1,1/0,1,1,1",
  "1,0,3", "T6c", "2,2,1,1/2,2,1,1/2,1,1,1",
    "0,0,0,1/0,0,1,1/0,1,1,1",
  "1,0,3", "split_1_2", "2,2,1/2,2,2/2,2,2",
    "1,0,0/1,0,2/0,0,2",
  "1,1,0", "B2", "4,1,1/1,4,1/1,1,1/1,0,0",
    "0,0,0/0,0,0/0,0,0/1,0,0",
  "1,1,0", "c1+1+0 c2-1+0", "3,2,0/1,2,1/2,2,2",
    "0,0,0/0,0,0/0,0,0",
  "1,1,0", "gX@1+hX@1", "2,2,0,1/2,2,1,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/1,0,0,0",
  "1,1,0", "gX@1m c4+1+1", "2,2,0/2,2,1/2,2,2/2,0,0",
    "0,0,0/0,0,0/0,0,0/2,0,0",
  "1,1,0", "gX@1m", "2,2,0/2,2,1/2,2,2/1,0,0",
    "0,0,0/0,0,0/0,0,0/1,0,0",
  "1,1,0", "hX@1m c10+1+1", "2,2,0,2/2,2,1,0/2,2,2,0",
    "0,0,0,2/0,0,0,0/0,0,0,0",
  "1,1,0", "hX@1m", "2,2,0,1/2,2,1,0/2,2,2,0",
    "0,0,0,1/0,0,0,0/0,0,0,0",
  "1,1,0", "single_half_8", "2,2,0/2,2,2/2,2,2",
    "0,0,0/0,0,1/0,0,0",
  "1,1,0", "extra_missing_1", "3,2,0/2,2,1/2,2,2",
    "1,0,0/0,0,0/0,0,0",
  "1,1,1", "T12b", "4,1,0/1,3,1/1,1,1/1,1,0",
    "0,0,0/0,0,1/0,0,0/0,1,0",
  "1,1,1", "c1+1+0 c2-1+0", "3,2,0/1,2,1/2,2,2",
    "0,0,0/0,0,0/0,0,2",
  "1,1,1", "c8-1+0 c9+0-1", "2,2,0/2,2,0/2,2,2",
    "0,0,0/0,0,0/0,0,1",
  "1,1,1", "c9-1-1 gX@1m", "2,2,0/2,2,1/2,2,1/1,0,0",
    "0,0,0/0,0,0/0,0,1/1,0,0",
  "1,1,1", "c9-1-1 hX@1m", "2,2,0,1/2,2,1,0/2,2,1,0",
    "0,0,0,1/0,0,0,0/0,0,1,0",
  "1,1,1", "gX@1+hX@1 c11-1-1 c11-1-1", "2,2,0,1/2,2,1,0/2,2,0,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,0,0/1,0,0,0",
  "1,1,1", "lost_one_9", "2,2,0/2,2,1/2,2,1",
    "0,0,0/0,0,0/0,0,1",
  "1,1,2", "c1-1-1 gX@1m", "1,2,0/2,2,1/2,2,2/1,0,0",
    "1,0,0/0,0,0/0,0,2/1,0,0",
  "1,1,2", "c1-1-1 hX@1m", "1,2,0,1/2,2,1,0/2,2,2,0",
    "1,0,0,1/0,0,0,0/0,0,2,0",
  "1,1,2", "gX@1+hX@1 c1-1-1 c1-1-1", "0,2,0,1/2,2,1,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/0,0,0,0/0,0,2,0/1,0,0,0",
  "1,1,2", "split_1_2", "2,2,0/2,2,1/2,2,2",
    "1,0,0/1,0,0/0,0,2",
  "1,1,2", "split_2_4", "2,2,0/2,2,1/2,2,2",
    "2,1,0/0,0,0/0,0,1",
  "1,1,3", "T9a", "2,3,0/1,2,2/2,1,2",
    "1,0,0/0,1,2/2,0,0",
  "1,1,3", "c1+1+1 c2-1-1", "3,2,0/1,2,1/2,2,2",
    "3,0,0/1,0,0/0,0,2",
  "1,1,3", "c1-1-1 gX@1m", "1,2,0/2,2,1/2,2,2/1,0,0",
    "1,0,0/2,0,0/0,0,2/1,0,0",
  "1,1,3", "c1-1-1 hX@1m", "1,2,0,1/2,2,1,0/2,2,2,0",
    "1,0,0,1/2,0,0,0/0,0,2,0",
  "1,1,3", "c3+1+0 c4-1+0", "2,1,0/2,2,1/3,2,2",
    "2,0,0/2,0,0/0,0,2",
  "1,1,3", "c3-1+0 c4+1+0", "2,3,0/2,2,1/1,2,2",
    "2,0,0/2,0,0/0,0,2",
  "1,1,3", "gX@1+hX@1 c1-1-1 c1-1-1", "0,2,0,1/2,2,1,0/2,2,2,0/1,0,0,0",
    "0,0,0,1/2,0,0,0/0,0,2,0/1,0,0,0"
)

# Class labels that recur in two schools or occur in one, without a
# declared scope, and combinations without a school, in a T0 run.
dh_family_labels <- function() {
  dh_family(
    name = "labels",
    probe = "^structure\\.(id_scope_evidence|label_incidence)",
    description = "class labels recurring across schools, undeclared scope, T0",
    params = list(
      schools = dh_param(3:5, person = FALSE, natural = c(FALSE, FALSE)),
      shared = dh_param(0:3, person = TRUE),
      once = dh_param(2:4, person = TRUE),
      school_missing = dh_param(0:2, person = TRUE)
    ),
    valid = function(p) p$school_missing <= p$shared + p$once,
    build = function(p) {
      schools <- dh_labels("S", p$schools)
      classes <- dh_labels("c", p$shared + p$once)
      combos <- rbind(
        data.frame(class = classes, school = schools[(seq_along(classes) - 1L) %% p$schools + 1L],
                   stringsAsFactors = FALSE),
        data.frame(class = classes[seq_len(p$shared)],
                   school = schools[seq_len(p$shared) %% p$schools + 1L],
                   stringsAsFactors = FALSE)
      )
      combos$school[seq_len(p$school_missing)] <- NA
      data <- combos[rep(seq_len(nrow(combos)), each = 2L), , drop = FALSE]
      n <- nrow(data)
      data$tx <- rep(seq_len(nrow(combos)) %% 3L, each = 2L)
      data$y <- dh_outcome(n)
      data$x <- dh_covariate(n)
      rownames(data) <- NULL
      list(data = data, formula = "y ~ x + tx + (1 | school) + (1 | class)", args = list())
    }
  )
}

# Classes whose labels repeat in each school, declared within_parent, with
# pupils as the disclosure unit, classes of one pupil and pupils without an
# outcome, in a T1 run.
dh_family_nested <- function() {
  dh_family(
    name = "nested",
    probe = "school:class|^structure\\.label_incidence",
    description = "classes within_parent in schools, classes of one pupil, missing outcomes, T1",
    params = list(
      schools = dh_param(3:4, person = FALSE, natural = c(FALSE, FALSE)),
      single = dh_param(0:3, person = TRUE),
      y_missing = dh_param(0:2, person = TRUE, tier = "A"),
      school_missing = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE))
    ),
    build = function(p) {
      m <- 2L * p$schools
      pupils <- ifelse(seq_len(m) <= p$single, 1L, 2L)
      combo <- rep(seq_len(m), pupils)
      school <- dh_labels("S", p$schools)[(combo + 1L) %/% 2L]
      class <- c("c1", "c2")[(combo - 1L) %% 2L + 1L]
      n <- length(combo)
      y <- dh_outcome(n)
      y[n - seq_len(p$y_missing) + 1L] <- NA
      school[combo == m & p$school_missing > 0L] <- NA
      declaration <- dh_declaration(units = list(
        dh_unit("school"), dh_unit("class", nested_in = "school", id_scope = "within_parent"),
        dh_unit("pupil", role = "participant", nested_in = "class")
      ))
      list(data = data.frame(y = y, x = dh_covariate(n), school = school, class = class,
                             pupil = dh_labels("p", n), stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | school) + (1 | school:class)",
           args = c(list(declaration = declaration), dh_t1()))
    }
  )
}

# Sessions within subjects, subjects of one or two sessions and sessions of
# one row, in a T0 run.
dh_family_aliased <- function() {
  dh_family(
    name = "aliased",
    gate = FALSE,
    probe = "^structure\\.aliased_factors",
    description = "sessions nested in subjects, sessions of one row, T0",
    params = list(
      subjects = dh_param(3:5, person = TRUE),
      two_sessions = dh_param(0:3, person = TRUE),
      three_sessions = dh_param(0:1, person = TRUE),
      one_row = dh_param(0:2, person = TRUE)
    ),
    valid = function(p) p$two_sessions + p$three_sessions <= p$subjects,
    build = function(p) {
      sessions <- ifelse(seq_len(p$subjects) <= p$two_sessions, 2L, 1L)
      sessions[p$subjects - seq_len(p$three_sessions) + 1L] <- 3L
      session_subject <- rep(seq_len(p$subjects), sessions)
      rows <- ifelse(seq_along(session_subject) <= p$one_row, 1L, 2L)
      session <- rep(dh_labels("k", length(session_subject)), rows)
      subject <- dh_labels("s", p$subjects)[rep(session_subject, rows)]
      n <- length(session)
      list(data = data.frame(y = dh_outcome(n), x = dh_covariate(n), subject = subject,
                             session = session, stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject) + (1 | session)", args = list())
    }
  )
}

# An observation key of subject and trial with rows repeated identically or
# with another covariate, rows without a subject and rows without the
# covariate, in a T0 run.
dh_family_keys <- function() {
  dh_family(
    name = "keys",
    probe = "^(keys\\.duplicates|sample\\.raw_vs_analysis)",
    description = "observation key with duplicates and missing values, missing covariate, T0",
    params = list(
      subjects = dh_param(4:5, person = TRUE),
      four = dh_param(0:1, person = TRUE),
      identical = dh_param(0:2, person = TRUE),
      conflicting = dh_param(0:2, person = TRUE),
      missing_key = dh_param(0:2, person = TRUE),
      x_missing = dh_param(0:2, person = TRUE)
    ),
    build = function(p) {
      trials <- c(rep(3L, p$subjects), rep(4L, p$four))
      base <- data.frame(subject = rep(dh_labels("s", length(trials)), trials),
                         trial = sequence(trials), stringsAsFactors = FALSE)
      base$x <- dh_covariate(nrow(base))
      repeated <- base[seq_len(p$identical), , drop = FALSE]
      conflicting <- base[p$identical + seq_len(p$conflicting), , drop = FALSE]
      conflicting$x <- conflicting$x + 1
      data <- rbind(base, repeated, conflicting)
      n <- nrow(data)
      data$subject[nrow(base) - seq_len(p$missing_key) + 1L] <- NA
      data$x[nrow(base) - p$missing_key - seq_len(p$x_missing) + 1L] <- NA
      data$y <- dh_outcome(n)
      declaration <- dh_declaration(units = list(dh_participant("subject")),
                                    observation = list(key = list("subject", "trial")))
      list(data = data, formula = "y ~ x + (1 | subject)", args = list(declaration = declaration))
    }
  )
}

# Subject labels of which some have two Unicode spellings, in a T0 run.
dh_family_unicode <- function() {
  dh_family(
    name = "unicode",
    gate = FALSE,
    probe = "^labels\\.unicode_forms",
    description = "labels with two Unicode spellings, T0",
    params = list(
      plain = dh_param(3:5, person = TRUE),
      merged = dh_param(0:3, person = TRUE)
    ),
    build = function(p) {
      plain <- dh_labels("s", p$plain)
      composed <- paste0("\u00e9", seq_len(p$merged))
      decomposed <- paste0("e\u0301", seq_len(p$merged))
      subject <- c(rep(plain, each = 2L), composed, decomposed)
      n <- length(subject)
      list(data = data.frame(y = dh_outcome(n), subject = enc2utf8(subject),
                             stringsAsFactors = FALSE),
           formula = "y ~ 1 + (1 | subject)", args = list())
    }
  )
}

# A predictor with the two values -2 and 5, constant within most subjects
# and varying within some, and subjects without an outcome, in a T1 run. The
# reals of the document are functions of these counts.
dh_family_two_valued <- function() {
  dh_family(
    name = "two-valued",
    gate = FALSE,
    probe = "^(design|structure\\.within_between|identifiability)\\.",
    description = "predictor of two values, missing outcomes, T1, reals kept",
    params = list(
      low = dh_param(2:4, person = TRUE),
      high = dh_param(2:4, person = TRUE),
      varying = dh_param(0:2, person = TRUE),
      low_missing = dh_param(0:2, person = TRUE, tier = "A"),
      high_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$low_missing <= p$low && p$high_missing <= p$high,
    build = function(p) {
      kinds <- c(rep("low", p$low), rep("high", p$high), rep("varying", p$varying))
      subject <- rep(dh_labels("s", length(kinds)), each = 2L)
      kind <- rep(kinds, each = 2L)
      x <- ifelse(kind == "low", -2, 5)
      x[kind == "varying"] <- rep(c(-2, 5), p$varying)
      y <- dh_outcome(length(x))
      index <- rep(seq_along(kinds), each = 2L)
      y[kind == "low" & index <= p$low_missing] <- NA
      y[kind == "high" & index <= p$low + p$high_missing] <- NA
      list(data = data.frame(y = y, x = x, subject = subject, stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)", args = dh_t1())
    },
    reals = TRUE
  )
}

# A condition balanced within subjects of two or four rows, and subjects
# without an outcome, in a T1 run. The reals are functions of these counts.
dh_family_eigen <- function() {
  dh_family(
    name = "eigen",
    probe = "^(identifiability\\.gram_rank|structure\\.cluster_sizes)",
    description = "condition balanced within subjects, missing outcomes, T1, reals kept",
    params = list(
      two = dh_param(0:4, person = TRUE),
      four = dh_param(0:4, person = TRUE),
      y_missing = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$two + p$four >= 3L && p$y_missing <= p$two + p$four - 1L,
    build = function(p) {
      sizes <- c(rep(2L, p$two), rep(4L, p$four))
      subject <- rep(dh_labels("s", length(sizes)), sizes)
      condition <- rep(c("a", "b"), length.out = length(subject))
      y <- dh_outcome(length(subject))
      y[match(subject, unique(subject)) <= p$y_missing] <- NA
      list(data = data.frame(y = y, condition = condition, subject = subject,
                             stringsAsFactors = FALSE),
           formula = "y ~ condition + (1 | subject)", args = dh_t1())
    },
    reals = TRUE
  )
}

# Three schools of one to five pupils, the disclosure unit, in a T0 run.
dh_family_quartile <- function() {
  dh_family(
    name = "quartile",
    gate = FALSE,
    probe = "^structure\\.cluster_sizes",
    description = "three schools of one to five pupils, T0",
    params = list(
      a = dh_param(1:5, person = TRUE, natural = c(TRUE, FALSE)),
      b = dh_param(1:5, person = TRUE, natural = c(TRUE, FALSE)),
      c = dh_param(1:5, person = TRUE, natural = c(TRUE, FALSE))
    ),
    build = function(p) {
      school <- rep(c("A", "B", "C"), c(p$a, p$b, p$c))
      n <- length(school)
      declaration <- dh_declaration(units = list(
        dh_unit("school"), dh_unit("pupil", role = "participant", nested_in = "school")
      ))
      list(data = data.frame(y = dh_outcome(n), school = school, pupil = dh_labels("p", n),
                             stringsAsFactors = FALSE),
           formula = "y ~ 1 + (1 | school)", args = list(declaration = declaration))
    }
  )
}

# An arm assigned by school, schools of one or two pupils, the disclosure
# unit, and schools without an arm, in a T0 run.
dh_family_assign_school <- function() {
  dh_family(
    name = "assign-school",
    gate = FALSE,
    probe = "^(assignment|structure\\.cluster_sizes)",
    description = "arm assigned by school, schools of one pupil without an arm, T0",
    params = list(
      double = dh_param(3:5, person = TRUE),
      single = dh_param(0:2, person = TRUE),
      single_missing = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE)),
      double_missing = dh_param(0:2, person = TRUE)
    ),
    valid = function(p) p$single_missing <= p$single && p$double_missing <= p$double,
    build = function(p) {
      pupils <- c(rep(2L, p$double), rep(1L, p$single))
      schools <- dh_labels("S", length(pupils))
      school_of_pupil <- rep(seq_along(pupils), pupils)
      pupil <- rep(dh_labels("p", length(school_of_pupil)), each = 2L)
      school <- schools[rep(school_of_pupil, each = 2L)]
      index <- match(school, schools)
      arm <- c("a", "b")[index %% 2L + 1L]
      arm[index <= p$double_missing] <- NA
      arm[index > p$double & index <= p$double + p$single_missing] <- NA
      n <- length(school)
      declaration <- dh_declaration(units = list(
        dh_unit("school"), dh_unit("pupil", role = "participant", nested_in = "school")
      ), assignment = list(list(column = "arm", unit = "school", randomised = TRUE,
                                level = "between_unit")))
      list(data = data.frame(y = dh_outcome(n), school = school, pupil = pupil, arm = arm,
                             stringsAsFactors = FALSE),
           formula = "y ~ 1 + (1 | school)", args = list(declaration = declaration))
    }
  )
}

# A binomial outcome of two trials with rows of 0, 1 and 2 events, two
# covariates that no two rows share and rows without an outcome, in a T2
# run.
dh_family_binomial <- function() {
  dh_family(
    name = "binomial",
    gate = FALSE,
    probe = "^outcome\\.separation",
    description = "binomial rows with no, some and all events, missing outcomes, T2",
    alternatives = dh_alternatives_binomial,
    params = list(
      none = dh_param(0:4, person = TRUE, tier = "A"),
      all = dh_param(0:4, person = TRUE, tier = "A"),
      some = dh_param(2:5, person = TRUE, tier = "A"),
      y_missing = dh_param(0:1, person = TRUE, natural = c(TRUE, TRUE), tier = "A")
    ),
    valid = function(p) p$none + p$all + p$some >= 3L,
    build = function(p) {
      k <- c(rep(0, p$none), rep(2, p$all), rep(1, p$some), rep(NA, p$y_missing))
      n <- length(k)
      declaration <- dh_declaration(variables = list(
        k = list(role = "outcome", measurement = "binomial", trials = "n")))
      list(data = data.frame(k = k, n = 2, x = dh_covariate(n), z = (seq_len(n) * 3L) %% 7L + 0.5),
           formula = "k ~ x + z", args = c(list(declaration = declaration), dh_t2()))
    }
  )
}

# The alternatives of binomial (dh_alternatives()): those that the zoo
# families share, for each row with an outcome the table in which that row
# has each other number of events, and two rows recoded with the same events,
# each described by its own counts of rows with no, some and all events and
# without an outcome. The family
# places the outcomes in a fixed order of the rows, whose covariates follow
# their positions, so the verdict of outcome.separation, which privacy.md
# accepts to show, can give the counts within the family alone.
dh_alternatives_binomial <- function(p, case) {
  describe <- function(alternative) {
    k <- alternative$data$k
    attr(alternative, "params") <- list(none = sum(k == 0, na.rm = TRUE),
                                        all = sum(k == 2, na.rm = TRUE),
                                        some = sum(k == 1, na.rm = TRUE),
                                        y_missing = sum(is.na(k)))
    alternative
  }
  out <- dz_common_alternatives(case, "k", character(0))
  k <- case$data$k
  for (i in which(!is.na(k))) {
    for (events in setdiff(0:2, k[i])) {
      recoded <- case
      recoded$data$k[i] <- events
      out[[sprintf("row_%d_events_%d", i, events)]] <- recoded
    }
  }
  # Two rows of one event each recoded as one row of two and one of none,
  # and the reverse, which keep the events and the trials.
  some <- which(k == 1)
  if (length(some) >= 2L) {
    split <- case
    split$data$k[some[1:2]] <- c(2, 0)
    out$pair_split <- split
  }
  all <- which(k == 2)
  none <- which(k == 0)
  if (length(all) && length(none)) {
    joined <- case
    joined$data$k[c(all[1L], none[1L])] <- 1
    out$pair_joined <- joined
  }
  # Rows without an outcome on the recording grids of x and z, found by a
  # search over the grid points, one or two, beside the design of n rows,
  # that leave the statuses of design.collinearity, and every other value of
  # the document, as they are. The covariates follow the positions of the
  # rows, so the statuses of the GVIF over the design sample, which rows
  # without an outcome change, would otherwise give their number.
  extra <- dh_binomial_grid_rows[[as.character(nrow(case$data))]]
  if (!is.null(extra)) {
    added <- case
    added$data <- rbind(added$data, data.frame(k = NA, n = 2, x = extra$x, z = extra$z))
    out$grid_rows <- added
  }
  lapply(out, describe)
}

# The rows of dh_alternatives_binomial() for a table of n rows, by n: two
# for the four rows of 'none', 'all' and 'some' without a row without an
# outcome, and one for five rows.
dh_binomial_grid_rows <- list(`4` = list(x = c(10.5, 9.5), z = c(2.5, 4.5)),
                              `5` = list(x = 10.5, z = 2.5))

# Three arms of three, four and five rows with any number of events in
# each, a bernoulli outcome, in a T2 run.
dh_family_factor_separation <- function() {
  dh_family(
    name = "factor-separation",
    probe = "^outcome\\.(separation|minority_events)",
    description = "three arms of different sizes, events by arm, T2",
    params = list(
      e1 = dh_param(0:3, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      e2 = dh_param(0:4, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      e3 = dh_param(0:5, person = TRUE, natural = c(TRUE, TRUE), tier = "A")
    ),
    build = function(p) {
      arm <- rep(c("a", "b", "c"), c(3L, 4L, 5L))
      y <- c(rep(1, p$e1), rep(0, 3L - p$e1), rep(1, p$e2), rep(0, 4L - p$e2),
             rep(1, p$e3), rep(0, 5L - p$e3))
      list(data = data.frame(y = y, arm = arm, stringsAsFactors = FALSE), formula = "y ~ arm",
           args = c(list(family = "binomial"), dh_t2()))
    },
    reals = TRUE
  )
}

# Two factors of two levels whose four combinations hold two to five rows,
# with any number of events in each, a bernoulli outcome, in a T2 run.
dh_family_two_factor_separation <- function() {
  dh_family(
    name = "two-factor-separation",
    probe = "^outcome\\.(separation|minority_events)",
    description = "two factors of two levels, events by combination, T2",
    params = list(
      e11 = dh_param(0:2, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      e12 = dh_param(0:3, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      e21 = dh_param(0:4, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      e22 = dh_param(0:5, person = TRUE, natural = c(TRUE, TRUE), tier = "A")
    ),
    build = function(p) {
      sizes <- 2:5
      events <- c(p$e11, p$e12, p$e21, p$e22)
      cell <- rep(1:4, sizes)
      y <- unlist(lapply(1:4, function(j) c(rep(1, events[j]), rep(0, sizes[j] - events[j]))))
      list(data = data.frame(y = y, a = c("a1", "a1", "a2", "a2")[cell],
                             b = c("b1", "b2", "b1", "b2")[cell], stringsAsFactors = FALSE),
           formula = "y ~ a + b", args = c(list(family = "binomial"), dh_t2()))
    },
    reals = TRUE
  )
}

# Two covariates and a factor of two levels, the second of which holds two
# to four rows, some or all of them without an outcome, in a T2 run.
dh_family_separation_missing <- function() {
  dh_family(
    name = "separation-missing",
    probe = "^outcome\\.separation",
    description = "a rare level whose rows lose their outcome, T2",
    params = list(
      rare = dh_param(2:4, person = TRUE, natural = c(FALSE, FALSE)),
      rare_missing = dh_param(0:4, person = TRUE, natural = c(TRUE, TRUE), tier = "A"),
      events = dh_param(8:12, person = TRUE, natural = c(FALSE, FALSE), tier = "A")
    ),
    valid = function(p) p$rare_missing <= p$rare,
    build = function(p) {
      n <- 24L + p$rare
      level <- c(rep("s2", p$rare), rep("s1", 24L))
      y <- c(rep(c(1, 0), length.out = p$rare), rep(0, 24L))
      y[p$rare + seq(1L, 24L, length.out = p$events)] <- 1
      y[seq_len(p$rare_missing)] <- NA
      list(data = data.frame(y = y, x1 = dh_covariate(n), x2 = (seq_len(n) * 3L) %% 17L + 0.5,
                             smoker = level, stringsAsFactors = FALSE),
           formula = "y ~ x1 + x2 + smoker", args = c(list(family = "binomial"), dh_t2()))
    }
  )
}

# Subjects of one, two and three rows, subjects of two rows that lose every
# outcome and others that lose their second, in a T1 run of a Poisson model,
# so that the design sample keeps its levels beside the analysis sample when
# k or more subjects lose every outcome, and the sizes of its levels, beside
# the analysed rows, would give back the second rows that the analysed
# subjects lost. Only subjects of two rows lose outcomes, so that the rows
# without an outcome, which the document writes when they are k or more,
# leave few ways to lose them, and its determinations of attack (a) rest on
# the template and are candidates.
dh_family_whole_lost <- function() {
  dh_family(
    name = "whole-lost",
    gate = FALSE,
    probe = "^(structure|identifiability|sample)\\.",
    description = "subjects losing every outcome beside subjects losing one, Poisson, T1",
    params = list(
      single = dh_param(0:2, person = TRUE),
      double = dh_param(6:8, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      whole = dh_param(0:4, person = TRUE, tier = "A"),
      part = dh_param(0:2, person = TRUE, tier = "A")
    ),
    valid = function(p) p$whole + p$part <= p$double - 3L,
    build = function(p) {
      subjects <- c(dh_labels("s", p$double), dh_labels("t", p$triple), dh_labels("o", p$single))
      sizes <- c(rep(2L, p$double), rep(3L, p$triple), rep(1L, p$single))
      subject <- rep(subjects, sizes)
      time <- sequence(sizes) - 1L
      n <- length(subject)
      # The zeros lie in the first rows of three subjects that keep every
      # outcome, so that the written counts of zeros do not follow the
      # parameters, and the subjects that lose outcomes are the last ones.
      # The covariate does not follow the position of a row in its subject,
      # whose values would show the largest size.
      y <- 1 + time
      doubles <- dh_labels("s", p$double)
      y[subject %in% doubles[1:3] & time == 0L] <- 0
      losing <- rev(doubles)
      y[subject %in% losing[seq_len(p$whole)]] <- NA
      y[subject %in% losing[p$whole + seq_len(p$part)] & time == 1L] <- NA
      list(data = data.frame(y = y, x = dh_covariate(n), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "y ~ x + (1 | subject)",
           args = c(list(family = "poisson"), dh_t1()))
    }
  )
}

# A grouping factor that is also a fixed term, with levels of two and three
# rows, levels whose counts are all 0, levels that lose every outcome and
# levels that lose one, in a T1 run of a Poisson model, so that the columns
# of the term write the design sample's levels and outcome.zero_shares the
# levels whose counts are all 0, a part of the analysed levels.
dh_family_fixed_factor <- function() {
  dh_family(
    name = "fixed-factor",
    probe = "^(structure|identifiability|sample|design)\\.",
    description = "a grouping factor that is a fixed term, levels of zeros, Poisson, T1",
    params = list(
      double = dh_param(5:7, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      zero = dh_param(3:4, person = TRUE, tier = "A"),
      whole = dh_param(0:2, person = TRUE, tier = "A"),
      part = dh_param(0:1, person = TRUE, tier = "A")
    ),
    valid = function(p) p$zero + p$whole + p$part <= p$double,
    build = function(p) {
      levels <- c(dh_labels("g", p$double), dh_labels("h", p$triple))
      sizes <- c(rep(2L, p$double), rep(3L, p$triple))
      g <- rep(levels, sizes)
      second <- sequence(sizes) == 2L
      n <- length(g)
      y <- 1 + (seq_len(n) * 5L) %% 3L
      doubles <- dh_labels("g", p$double)
      y[g %in% doubles[seq_len(p$zero)]] <- 0
      y[g %in% doubles[p$zero + seq_len(p$whole)]] <- NA
      y[g %in% doubles[p$zero + p$whole + seq_len(p$part)] & second] <- NA
      list(data = data.frame(y = y, x = dh_covariate(n), g = g, stringsAsFactors = FALSE),
           formula = "y ~ x + g + (1 | g)",
           args = c(list(family = "poisson"), dh_t1()))
    }
  )
}

# A fixed interaction of two factors, A of three levels and B of two, whose
# combinations are a grouping factor: cells of two and three rows, an empty
# cell or none, cells that lose every outcome and cells that lose one, in a
# T1 run of a Poisson model, so that df of the two factors and empty_cells
# write the design sample's combinations. Its outcome values follow the
# rows, so its determinations of attack (a) are candidates.
dh_family_interaction <- function() {
  dh_family(
    name = "interaction",
    gate = FALSE,
    probe = "^(structure|identifiability|sample|design)\\.",
    description = "a fixed interaction whose combinations are a grouping factor, Poisson, T1",
    params = list(
      triple = dh_param(0:2, person = TRUE),
      empty = dh_param(0:1, person = TRUE),
      whole = dh_param(0:2, person = TRUE, tier = "A"),
      part = dh_param(0:1, person = TRUE, tier = "A")
    ),
    valid = function(p) p$whole + p$part + p$empty <= 6L - 3L,
    build = function(p) {
      cells <- expand.grid(A = dh_labels("a", 3L), B = dh_labels("b", 2L),
                           stringsAsFactors = FALSE)
      cells <- cells[seq_len(6L - p$empty), ]
      sizes <- rep(2L, nrow(cells))
      sizes[seq_len(p$triple)] <- 3L
      data <- cells[rep(seq_len(nrow(cells)), sizes), ]
      second <- sequence(sizes) == 2L
      n <- nrow(data)
      data$x <- dh_covariate(n)
      data$y <- (seq_len(n) * 5L) %% 4L
      cell <- rep(seq_len(nrow(cells)), sizes)
      last <- nrow(cells) + 1L - seq_len(p$whole + p$part)
      data$y[cell %in% last[seq_len(p$whole)]] <- NA
      data$y[cell %in% last[p$whole + seq_len(p$part)] & second] <- NA
      rownames(data) <- NULL
      list(data = data, formula = "y ~ x + A * B + (1 | A:B)",
           args = c(list(family = "poisson"), dh_t1()))
    }
  )
}

# A binomial outcome of two trials whose trials are 0 or missing in some
# rows, which leave the analysis sample as rows without an outcome do,
# subjects of one, two and three rows and rows without an outcome, in a T1
# run. Its outcome values follow the rows, so its determinations of attack
# (a) are candidates.
dh_family_trials <- function() {
  dh_family(
    name = "trials",
    gate = FALSE,
    probe = "^(structure|identifiability|sample|outcome)\\.",
    description = "binomial trials of 0 and missing trials, T1",
    params = list(
      double = dh_param(4:6, person = TRUE),
      triple = dh_param(0:2, person = TRUE),
      zero_trials = dh_param(0:2, person = TRUE, tier = "A"),
      missing_trials = dh_param(0:2, person = TRUE, tier = "A"),
      y_missing = dh_param(0:1, person = TRUE, tier = "A")
    ),
    valid = function(p) p$zero_trials + p$missing_trials + p$y_missing <= p$double,
    build = function(p) {
      subjects <- c(dh_labels("s", p$double), dh_labels("t", p$triple))
      sizes <- c(rep(2L, p$double), rep(3L, p$triple))
      subject <- rep(subjects, sizes)
      second <- sequence(sizes) == 2L
      n <- length(subject)
      k <- (seq_len(n) * 5L) %% 3L
      trials <- rep(2L, n)
      doubles <- dh_labels("s", p$double)
      lose <- function(from, count) doubles[from + seq_len(count)]
      trials[subject %in% lose(0L, p$zero_trials) & second] <- 0L
      k[subject %in% lose(0L, p$zero_trials) & second] <- 0L
      trials[subject %in% lose(p$zero_trials, p$missing_trials) & second] <- NA
      k[subject %in% lose(p$zero_trials + p$missing_trials, p$y_missing) & second] <- NA
      declaration <- dh_declaration(variables = list(
        k = list(role = "outcome", measurement = "binomial", trials = "n")))
      list(data = data.frame(k = k, n = trials, x = dh_covariate(n), subject = subject,
                             stringsAsFactors = FALSE),
           formula = "k ~ x + (1 | subject)",
           args = c(list(declaration = declaration), dh_t1()))
    }
  )
}
