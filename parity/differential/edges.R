# Edge cases for the differential test of the two packages (parity/README.md,
# Differential test): inputs where the two privacy filters, and the checks
# whose values they read, are most likely to differ. Each edge builds one
# input from a seed, with its own k from 2 to 20 and its own tier, so that
# many seeds cover the combinations of its features.
#
# - ties: level sizes from a few values, so that the quantiles of the sizes
#   fall on ties and on either side of the quantile rule
# - scripts: labels and levels in several scripts, with characters whose
#   order differs between locales, Unicode forms that NFC merges, an empty
#   label and quotation marks, grouping columns whose names lie outside ASCII
#   or sort differently by locale, factors whose levels are not in code-point
#   order and declared categories without rows
# - sparse: empty and single-row levels, factors with unused levels, levels
#   whose every outcome is missing and runs in which every outcome is missing
# - trials: binomial outcomes with trials of 0, 1 and missing, and bernoulli
#   outcomes with an event level
# - offsets: offsets in the formula and exposures in the declaration, and
#   weights, one of them missing for some seeds and 0, which audit()
#   refuses, for others
# - slopes: random slopes, '||', nesting and crossed factors whose design
#   falls into several connected components
# - assignments: assignments between and within units, randomised or not,
#   with blocks, without a level, with missing values and varying where they
#   are declared constant
# - units: no declaration, declarations without a participant or with two,
#   and so without a disclosure unit, a disclosure_unit that names a site and
#   a participant unit of two columns
#
# The labels are written as escapes, so that the file stays ASCII and reads
# alike in every locale.

de_edge <- function(name, description, build) {
  list(name = name, description = description, build = build)
}

# Labels whose order differs between locales and code-point order, labels
# that NFC merges, labels in other scripts and labels with quotation marks.
de_labels <- c(
  "a", "B", "b", "A", "Z", "z", "_x", "x_", "10", "9", "-1", "01",
  "\u00c1", "\u00e1", "\u00e4", "a\u0308", "\u00c4", "\u00df", "ss", "SS",
  "\u0130", "\u0131", "i", "I", "\u01c5", "\ufb01", "fi",
  "\u212b", "\u00c5", "A\u030a", "\u00e9", "e\u0301", "x y",
  "\U0001F600", "\U0001D538", "\u2126", "\u03a9", "\u00e6", "\u00f8", "\u0152",
  "\u2170", "\u2460", "\uff46", "\u4e1c\u4eac", "\u0645\u0631\u062d\u0628\u0627",
  "\u05e9\u05dc\u05d5\u05dd", "\u0e01", "a'b", "a\"b", "O'Brien"
)

de_tiers <- c("T0", "T1", "T2")

# The arguments of audit() for a tier, with the attestation that the outcome
# was seen for some seeds.
de_tier_args <- function(tier, seed) {
  if (tier == "T0") {
    return(list())
  }
  args <- list(outcome_access = tier, reason = "Differential test of the two packages.")
  if (seed %% 4L == 1L) {
    args$outcome_seen <- TRUE
  }
  if (tier == "T2") {
    args$exploratory <- TRUE
  }
  args
}

de_participant <- function(unit, columns = unit) {
  list(name = unit, columns = as.list(columns), role = "participant")
}

de_input <- function(formula, data, args = list(), k = sample(2:20, 1L), tier = NULL) {
  list(formula = formula, data = data, args = args, k = k, tier = tier)
}

# An outcome of the family given from a linear predictor.
de_outcome <- function(eta, family) {
  switch(family,
    gaussian = round(1 + eta + stats::rnorm(length(eta)), 2),
    poisson = stats::rpois(length(eta), exp(0.5 + 0.4 * eta)),
    bernoulli = stats::rbinom(length(eta), 1L, stats::plogis(eta))
  )
}

# Every edge, in the order in which inputs.R writes them.
de_edges <- function() {
  list(de_ties(), de_scripts(), de_sparse(), de_trials(), de_offsets(), de_slopes(),
       de_assignments(), de_units())
}

# Level sizes drawn from a few values, so that the quantiles of the sizes
# tie, beside a nested factor and a covariate with ties.
de_ties <- function() {
  de_edge(
    name = "ties",
    description = "level sizes from a few values, ties in the quantiles",
    build = function(seed) {
      levels <- sample(c(4:12, 18:22, 38:42), 1L)
      pattern <- switch(sample(5L, 1L),
        rep(sample(1:3, 1L), levels),
        sample(c(1L, 2L), levels, replace = TRUE),
        sample(c(2L, 2L, 2L, 3L), levels, replace = TRUE),
        sample(c(1L, 1L, 1L, 4L), levels, replace = TRUE),
        rep(c(1L, 2L, 3L, 4L), length.out = levels))
      g <- rep(sprintf("g%02d", seq_len(levels)), pattern)
      n <- length(g)
      h <- paste0(g, "-", sample(c("p", "q"), n, replace = TRUE))
      x <- sample(1:3, n, replace = TRUE)
      family <- sample(c("gaussian", "poisson"), 1L)
      y <- de_outcome(0.2 * x + stats::rnorm(levels)[match(g, unique(g))], family)
      tier <- sample(de_tiers, 1L)
      missing <- switch(sample(4L, 1L),
        integer(0),
        sample(n, 1L),
        which(g %in% sample(unique(g), min(levels, sample(1:3, 1L)))),
        sample(n, max(1L, n %/% 3L)))
      y[missing] <- NA
      nested <- seed %% 2L == 0L
      formula <- if (nested) "y ~ x + (1 | g) + (1 | h)" else "y ~ x + (1 | g)"
      declaration <- if (seed %% 3L != 0L) {
        list(vocabulary = "0.1.0", units = list(de_participant("g")))
      }
      args <- c(list(declaration = declaration, family = family), de_tier_args(tier, seed))
      de_input(formula, data.frame(y = y, x = x, g = g, h = h, stringsAsFactors = FALSE), args,
               tier = tier)
    }
  )
}

# Labels in several scripts as grouping levels and as the levels of a fixed
# factor, in a grouping column whose name lies outside ASCII, with a factor
# whose levels are not in code-point order, a drawn contrast and reference
# level, declared categories of which one has no row and, for some seeds,
# the empty string as a label.
de_scripts <- function() {
  de_edge(
    name = "scripts",
    description = "labels in several scripts, locale order, NFC, quotes and empty labels",
    build = function(seed) {
      subjects <- sample(de_labels, sample(8:30, 1L))
      if (seed %% 5L == 0L) {
        subjects[1L] <- ""
      }
      sizes <- sample(1:4, length(subjects), replace = TRUE)
      subject <- rep(subjects, sizes)
      n <- length(subject)
      levels <- unique(sample(setdiff(de_labels, ""), sample(3:5, 1L)))
      condition <- sample(levels, n, replace = TRUE)
      x <- round(stats::rnorm(n), 1)
      family <- sample(c("gaussian", "poisson"), 1L)
      y <- de_outcome(0.3 * match(condition, levels) + x, family)
      tier <- sample(de_tiers, 1L)
      y[sample(n, sample(0:3, 1L))] <- NA
      column <- "\u00e9l\u00e8ve"
      data <- data.frame(y = y, x = x, cond = condition, stringsAsFactors = FALSE)
      data[[column]] <- subject
      declaration <- list(vocabulary = "0.1.0", units = list(de_participant("pupil", column)))
      coding <- NULL
      variant <- seed %% 4L
      if (variant == 1L) {
        data$cond <- factor(condition, levels = rev(c(levels, "\u00ff-unused")))
      } else if (variant == 2L) {
        coding <- list(cond = list(contrast = sample(c("treatment", "sum", "simple"), 1L),
                                   reference = sample(unique(condition), 1L)))
      } else if (variant == 3L) {
        # A table block whose categories of cond name a level without rows,
        # first, so that it is the reference level. A declaration holds its
        # strings in NFC, which the labels of the data need not be.
        categories <- unique(mixedcheck:::nfc(c("\u00fcbrig", sample(unique(condition)))))
        declaration$table <- list(fields = list(
          list(name = "y", type = "number"), list(name = "x", type = "number"),
          list(name = "cond", type = "string", categories = as.list(categories)),
          list(name = column, type = "string"), list(name = "Zone", type = "string"),
          list(name = "\u00e1baco", type = "string")))
      }
      # Two more grouping columns, whose names and labels sort in one order
      # by code point and in another by the collation of most locales.
      data$Zone <- c("\u00c5sa", "Zeta", "alpha", "\u00e5s")[match(subject, subjects) %% 4L + 1L]
      data[["\u00e1baco"]] <- sample(c("Item", "item", "\u00cdtem", "_item"), n, replace = TRUE)
      formula <- sprintf("y ~ x + cond + (1 | `%s`) + (1 | Zone) + (1 | `\u00e1baco`)", column)
      args <- c(list(declaration = declaration, family = family, coding = coding),
                de_tier_args(tier, seed))
      de_input(formula, data, args, tier = tier)
    }
  )
}

# Empty and single-row levels, a factor with unused levels, levels whose
# every outcome is missing and, for some seeds, every outcome missing.
de_sparse <- function() {
  de_edge(
    name = "sparse",
    description = "empty and single-row levels, unused levels, outcomes missing by level",
    build = function(seed) {
      levels <- sample(5:25, 1L)
      sizes <- sample(c(1L, 1L, 2L, 3L, 6L), levels, replace = TRUE)
      g <- rep(sprintf("s%02d", seq_len(levels)), sizes)
      n <- length(g)
      f_levels <- c("lo", "mid", "hi", "none")
      f <- factor(sample(f_levels[1:3], n, replace = TRUE, prob = c(0.6, 0.35, 0.05)),
                  levels = sample(f_levels))
      x <- round(stats::runif(n, 0, 10))
      family <- sample(c("gaussian", "poisson", "bernoulli"), 1L)
      y <- de_outcome(0.1 * x + 0.3 * as.integer(f), family)
      tier <- sample(c("T1", "T1", "T2", "T0"), 1L)
      emptied <- sample(unique(g), min(levels, sample(0:4, 1L)))
      y[g %in% emptied] <- NA
      if (seed %% 7L == 0L) {
        y[] <- NA
      }
      if (seed %% 5L == 0L) {
        x[sample(n, 1L)] <- NA
      }
      args <- c(list(family = if (family == "bernoulli") "binomial" else family,
                     declaration = list(vocabulary = "0.1.0",
                                        units = list(de_participant("g")))),
                de_tier_args(tier, seed))
      data <- data.frame(y = y, f = f, x = x, g = g, stringsAsFactors = FALSE)
      de_input("y ~ f + x + (1 | g)", data, args, tier = tier)
    }
  )
}

# Binomial outcomes with trials of 0, 1 and missing, and bernoulli outcomes
# of strings with a declared event level.
de_trials <- function() {
  de_edge(
    name = "trials",
    description = "binomial trials of 0 and 1, missing trials, bernoulli event levels",
    build = function(seed) {
      levels <- sample(6:30, 1L)
      g <- rep(sprintf("s%02d", seq_len(levels)), sample(1:5, levels, replace = TRUE))
      n <- length(g)
      x <- round(stats::rnorm(n), 2)
      cond <- sample(c("p", "q"), n, replace = TRUE)
      tier <- sample(c("T1", "T2"), 1L)
      eta <- 0.5 * x + 0.4 * (cond == "q")
      if (seed %% 2L == 0L) {
        trials <- sample(c(0L, 1L, 1L, 2L, 5L), n, replace = TRUE)
        k <- stats::rbinom(n, trials, stats::plogis(eta))
        trials[sample(n, sample(0:2, 1L))] <- NA
        k[sample(n, sample(0:2, 1L))] <- NA
        declaration <- list(vocabulary = "0.1.0", units = list(de_participant("g")),
                            variables = list(k = list(role = "outcome", measurement = "binomial",
                                                      trials = "n")))
        data <- data.frame(k = k, n = trials, x = x, cond = cond, g = g,
                           stringsAsFactors = FALSE)
        family <- if (seed %% 4L == 0L) "binomial"
        formula <- "k ~ x + cond + (1 | g)"
      } else {
        y <- ifelse(stats::rbinom(n, 1L, stats::plogis(eta)) == 1L, "yes", "no")
        y[sample(n, sample(0:2, 1L))] <- NA
        declaration <- list(vocabulary = "0.1.0", units = list(de_participant("g")),
                            variables = list(y = list(role = "outcome", measurement = "binary",
                                                      event_level = "yes")))
        data <- data.frame(y = y, x = x, cond = cond, g = g, stringsAsFactors = FALSE)
        family <- if (seed %% 3L == 0L) "binomial"
        formula <- "y ~ x + cond + (1 | g)"
      }
      args <- c(list(declaration = declaration, family = family), de_tier_args(tier, seed))
      de_input(formula, data, args, tier = tier)
    }
  )
}

# Poisson counts with an offset in the formula or an exposure in the
# declaration, and precision weights, one of them missing or 0 for some
# seeds.
de_offsets <- function() {
  de_edge(
    name = "offsets",
    description = "offsets, exposures and weights, some of them missing or 0",
    build = function(seed) {
      levels <- sample(6:30, 1L)
      g <- rep(sprintf("s%02d", seq_len(levels)), sample(1:6, levels, replace = TRUE))
      n <- length(g)
      x <- round(stats::rnorm(n), 2)
      e <- round(stats::runif(n, 0.5, 4), 2)
      count <- stats::rpois(n, e * exp(0.3 * x))
      count[sample(n, sample(0:3, 1L))] <- NA
      tier <- sample(de_tiers, 1L)
      declaration <- list(vocabulary = "0.1.0", units = list(de_participant("g")))
      weights <- NULL
      data <- data.frame(count = count, x = x, e = e, g = g, stringsAsFactors = FALSE)
      variant <- seed %% 4L
      if (variant == 0L) {
        formula <- "count ~ x + offset(log(e)) + (1 | g)"
      } else if (variant == 1L) {
        formula <- "count ~ x + (1 | g)"
        declaration$variables <- list(count = list(role = "outcome", measurement = "count",
                                                   exposure = list(column = "e", scale = "raw")))
      } else {
        formula <- "count ~ x + offset(e) + (1 | g)"
        data$w <- round(stats::runif(n, 0.2, 3), 2)
        if (variant == 3L) {
          data$w[sample(n, 1L)] <- if (seed %% 8L == 3L) 0 else NA
        }
        weights <- "w"
      }
      args <- c(list(declaration = declaration, family = "poisson", weights = weights),
                de_tier_args(tier, seed))
      de_input(formula, data, args, tier = tier)
    }
  )
}

# Random slopes, '||', nesting and crossed factors whose design falls into
# several connected components.
de_slopes <- function() {
  de_edge(
    name = "slopes",
    description = "random slopes, '||', nesting and crossed components",
    build = function(seed) {
      blocks <- sample(1:4, 1L)
      rows <- list()
      for (b in seq_len(blocks)) {
        subjects <- sprintf("s%d%02d", b, seq_len(sample(3:8, 1L)))
        items <- sprintf("i%d%02d", b, seq_len(sample(2:6, 1L)))
        grid <- expand.grid(subject = subjects, item = items, stringsAsFactors = FALSE)
        grid <- grid[stats::runif(nrow(grid)) < 0.8, , drop = FALSE]
        rows[[b]] <- grid
      }
      data <- do.call(rbind, rows)
      n <- nrow(data)
      data$x <- round(stats::rnorm(n), 2)
      data$t <- sample(0:3, n, replace = TRUE)
      data$school <- paste0("k", match(data$subject, unique(data$subject)) %% 3L)
      data$class <- sample(c("A", "B"), n, replace = TRUE)
      family <- sample(c("gaussian", "poisson"), 1L)
      data$y <- de_outcome(0.3 * data$x + 0.1 * data$t, family)
      tier <- sample(de_tiers, 1L)
      data$y[sample(n, sample(0:3, 1L))] <- NA
      random <- switch(seed %% 5L + 1L,
        "(1 + x | subject) + (1 | item)",
        "(1 + x || subject) + (1 + t | item)",
        "(0 + x | subject) + (1 | item)",
        "(1 | school/class) + (1 | item)",
        "(1 | subject) + (1 | item) + (1 | subject:item)")
      declaration <- list(vocabulary = "0.1.0",
                          units = list(de_participant("subject"),
                                       list(name = "item", columns = list("item"), role = "item")),
                          crossings = list(list(units = list("subject", "item"))))
      if (seed %% 3L == 0L) {
        declaration <- NULL
      }
      args <- c(list(declaration = declaration, family = family), de_tier_args(tier, seed))
      de_input(paste("y ~ x + t +", random), data, args, tier = tier)
    }
  )
}

# Assignments of several kinds: between units with blocks, within units,
# randomised or not, without a level, with missing values and varying where
# they are declared constant.
de_assignments <- function() {
  de_edge(
    name = "assignments",
    description = "assignments between and within units, blocks, missing and varying values",
    build = function(seed) {
      schools <- sample(4:10, 1L)
      classes <- sample(2:3, schools, replace = TRUE)
      class_school <- rep(seq_len(schools), classes)
      pupils <- sample(2:6, length(class_school), replace = TRUE)
      row_class <- rep(seq_along(class_school), pupils)
      n <- length(row_class)
      school <- sprintf("S%02d", class_school[row_class])
      class <- LETTERS[sequence(classes)][row_class]
      pupil <- sprintf("p%03d", seq_len(n))
      arm <- sample(rep(c("control", "treat"), length.out = schools))[class_school[row_class]]
      dose <- sample(c("low", "high"), length(class_school), replace = TRUE)[row_class]
      cond <- sample(c("a", "b"), n, replace = TRUE)
      kind <- seed %% 6L
      if (kind == 3L) {
        arm[sample(n, 2L)] <- NA
      }
      if (kind == 4L) {
        arm[1L] <- if (arm[1L] == "control") "treat" else "control"
      }
      family <- sample(c("gaussian", "poisson"), 1L)
      y <- de_outcome(0.4 * (arm %in% "treat") + 0.2 * (cond == "b"), family)
      tier <- sample(de_tiers, 1L)
      y[sample(n, sample(0:4, 1L))] <- NA
      units <- list(
        list(name = "school", columns = list("school"), role = "cluster"),
        list(name = "class", columns = list("class"), role = "cluster", nested_in = "school",
             id_scope = "within_parent"),
        list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "class",
             id_scope = "global"))
      assignment <- switch(kind + 1L,
        list(list(column = "arm", unit = "school", randomised = TRUE, level = "between_unit")),
        list(list(column = "dose", unit = "class", randomised = TRUE, level = "between_unit",
                  blocks = list("school"))),
        list(list(column = "cond", unit = "pupil", randomised = FALSE, level = "within_unit")),
        list(list(column = "arm", unit = "school", randomised = TRUE)),
        list(list(column = "arm", unit = "school", randomised = TRUE, level = "between_unit"),
             list(column = "cond", unit = "class", randomised = TRUE, level = "within_unit")),
        list(list(column = "arm", unit = "school", randomised = FALSE, level = "between_unit"),
             list(column = "dose", unit = "class", randomised = TRUE)))
      declaration <- list(vocabulary = "0.1.0", units = units, assignment = assignment)
      formula <- switch(kind %% 3L + 1L,
        "y ~ arm + cond + (1 | school) + (1 | school:class)",
        "y ~ dose + arm + (1 | school/class)",
        "y ~ arm * cond + (1 | pupil) + (1 | school)")
      data <- data.frame(y = y, arm = arm, dose = dose, cond = cond, school = school,
                         class = class, pupil = pupil, stringsAsFactors = FALSE)
      args <- c(list(declaration = declaration, family = family), de_tier_args(tier, seed))
      de_input(formula, data, args, tier = tier)
    }
  )
}

# Declarations of the disclosure unit: none at all, units of which none is
# a participant or two are, which leave no disclosure unit, a
# disclosure_unit that names a site and a participant unit whose label takes
# two columns.
de_units <- function() {
  de_edge(
    name = "units",
    description = "no disclosure unit, two participants, a cluster as disclosure unit",
    build = function(seed) {
      sites <- sample(2:6, 1L)
      subjects <- sample(8:30, 1L)
      site <- sprintf("site%d", sample(sites, subjects, replace = TRUE))
      local <- sprintf("r%02d", seq_len(subjects))
      sizes <- sample(1:5, subjects, replace = TRUE)
      rows <- rep(seq_len(subjects), sizes)
      n <- length(rows)
      data <- data.frame(site = site[rows], local = local[rows],
                         rater = sample(c("u", "v", "w"), n, replace = TRUE),
                         x = round(stats::rnorm(n), 1), stringsAsFactors = FALSE)
      data$subject <- paste(data$site, data$local, sep = "/")
      family <- sample(c("gaussian", "poisson"), 1L)
      data$y <- de_outcome(0.3 * data$x, family)
      tier <- sample(de_tiers, 1L)
      data$y[sample(n, sample(0:3, 1L))] <- NA
      cluster <- list(name = "site", columns = list("site"), role = "site")
      rater <- list(name = "rater", columns = list("rater"), role = "rater")
      declaration <- switch(seed %% 5L + 1L,
        NULL,
        list(vocabulary = "0.1.0", units = list(cluster, rater)),
        list(vocabulary = "0.1.0", units = list(de_participant("subject"),
                                                list(name = "rater", columns = list("rater"),
                                                     role = "participant"))),
        list(vocabulary = "0.1.0", units = list(cluster, de_participant("subject")),
             disclosure_unit = "site"),
        list(vocabulary = "0.1.0",
             units = list(cluster, list(name = "person", columns = list("site", "local"),
                                        role = "participant", nested_in = "site",
                                        id_scope = "within_parent"))))
      formula <- "y ~ x + (1 | site) + (1 | subject) + (1 | rater)"
      args <- c(list(declaration = declaration, family = family), de_tier_args(tier, seed))
      de_input(formula, data, args, tier = tier)
    }
  )
}
