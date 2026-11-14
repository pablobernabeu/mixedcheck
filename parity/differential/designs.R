# Realistic designs for the differential test of the two packages
# (parity/README.md, Differential test). Each design builds the structure of
# a study from a seed: its rows, grouping columns, predictors, declaration,
# coding and weights, with a linear predictor for the outcome. inputs.R adds
# the outcome as a gaussian, Poisson or binomial outcome with trials and
# removes it from 0, 1, a few, k - 1 or many rows. The structure depends on
# the seed alone, so that the variants of one seed differ only in the
# outcome, the tier and the rows without an outcome.
#
# The labels hold characters outside ASCII, written here as escapes so that
# the file stays ASCII and reads alike in every locale. Factors have levels in
# an order other than code-point order, which neither package may use, since
# the levels of a categorical predictor come from the declaration or from the
# distinct values of the table in code-point order (ir.md, Kinds of columns).

dd_ids <- function(prefix, n, width = 3L) {
  sprintf(paste0("%s%0", width, "d"), prefix, seq_len(n))
}

dd_design <- function(name, description, build) {
  list(name = name, description = description, build = build)
}

# Words with accents, other scripts, a ligature and a character outside the
# Basic Multilingual Plane, as labels of items and schools.
dd_words <- c(
  "árbol", "cañón", "pingüino", "Straße", "Ärger",
  "œuvre", "naïve", "façade", "smörgås", "jalapeño",
  "crème", "Zürich", "København", "Ελλάδα",
  "мир", "東京", "café", "piñata", "über",
  "élan", "\U0001D538lpha", "table", "house", "river", "stone"
)

# Every design, in the order in which inputs.R writes them.
dd_designs <- function() {
  list(
    dd_repeated(),
    dd_crossed(),
    dd_schools(),
    dd_within_three(),
    dd_singletons(),
    dd_pairs()
  )
}

# Repeated measures with random slopes: subjects measured on up to six
# occasions, some of whom drop out, with time as an integer column, age as a
# subject covariate and, for one seed in three, precision weights.
dd_repeated <- function() {
  dd_design(
    name = "repeated",
    description = "repeated measures with random slopes of time, dropout and weights",
    build = function(seed) {
      subjects <- sample(24:36, 1L)
      dropout <- sample(0:3, subjects, replace = TRUE, prob = c(0.6, 0.2, 0.1, 0.1))
      sizes <- 6L - dropout
      ids <- dd_ids("p", subjects)
      subject <- rep(ids, sizes)
      time <- sequence(sizes) - 1L
      age <- round(stats::runif(subjects, 18, 70), 1)[match(subject, ids)]
      intercepts <- stats::rnorm(subjects, 0, 0.5)[match(subject, ids)]
      slopes <- stats::rnorm(subjects, 0, 0.1)[match(subject, ids)]
      eta <- 0.3 * time + 0.01 * (age - 40) + intercepts + slopes * time
      data <- data.frame(subject = subject, time = time, age = age, stringsAsFactors = FALSE)
      weights <- NULL
      if (seed %% 3L == 2L) {
        data$precision <- round(stats::runif(nrow(data), 0.5, 2), 3)
        weights <- "precision"
      }
      declaration <- list(
        vocabulary = "0.1.0",
        units = list(list(name = "subject", columns = list("subject"), role = "participant")),
        observation = list(key = list("subject", "time"))
      )
      list(data = data, eta = eta, rhs = "time + age + (1 + time | subject)",
           declaration = declaration, weights = weights)
    }
  )
}

# Subjects crossed with items: each subject sees most items, in a condition
# that varies between items and within subjects, a factor whose levels are
# not in code-point order. Item labels are words with accents and other
# scripts, and for one seed in three one item is spelt in two Unicode forms.
dd_crossed <- function() {
  dd_design(
    name = "crossed",
    description = "subjects crossed with items, an incomplete design, labels outside ASCII",
    build = function(seed) {
      subjects <- sample(18:26, 1L)
      items <- sample(12:20, 1L)
      words <- sample(setdiff(dd_words, "café"), items)
      if (seed %% 3L == 0L) {
        words[1L] <- "café"
      }
      grid <- expand.grid(item = seq_len(items), subject = seq_len(subjects))
      grid <- grid[stats::runif(nrow(grid)) < 0.85, , drop = FALSE]
      condition <- rep(c("congruent", "incongruent"), length.out = items)
      subject <- dd_ids("s", subjects)[grid$subject]
      item <- words[grid$item]
      if (seed %% 3L == 0L) {
        # The second half of the subjects read the first item decomposed.
        item[grid$item == 1L & grid$subject > subjects %/% 2L] <- "café"
      }
      data <- data.frame(subject = subject, item = item,
                         condition = factor(condition[grid$item],
                                            levels = c("incongruent", "congruent")),
                         stringsAsFactors = FALSE)
      effect <- stats::rnorm(items, 0, 0.3)[grid$item] +
        stats::rnorm(subjects, 0, 0.4)[grid$subject]
      eta <- 0.5 + 0.4 * (data$condition == "incongruent") + effect
      declaration <- list(
        vocabulary = "0.1.0",
        units = list(list(name = "subject", columns = list("subject"), role = "participant"),
                     list(name = "item", columns = list("item"), role = "item"))
      )
      coding <- if (seed %% 3L == 2L) {
        list(condition = list(contrast = "simple", reference = "congruent"))
      }
      list(data = data, eta = eta, rhs = "condition + (1 + condition | subject) + (1 | item)",
           declaration = declaration, coding = coding)
    }
  )
}

# Pupils nested in classes in schools, with an arm assigned by school, class
# labels repeated in every school and declared within_parent, school names
# outside ASCII and, for one seed in three, a baseline score as a sample
# column with a few values missing.
dd_schools <- function() {
  dd_design(
    name = "schools",
    description = "pupils in classes in schools, an arm assigned by school, sample columns",
    build = function(seed) {
      schools <- sample(8:12, 1L)
      school_names <- paste("Escuela", sample(dd_words, schools))
      classes <- sample(2:4, schools, replace = TRUE)
      class_school <- rep(seq_len(schools), classes)
      class_label <- LETTERS[sequence(classes)]
      pupils <- sample(6:14, length(class_school), replace = TRUE)
      row_class <- rep(seq_along(class_school), pupils)
      school <- school_names[class_school[row_class]]
      arm <- sample(rep(c("control", "treatment"), length.out = schools))[class_school[row_class]]
      n <- length(row_class)
      ses <- round(stats::rnorm(n), 2)
      data <- data.frame(school = school, class = class_label[row_class],
                         pupil = dd_ids("u", n, 4L), arm = arm, ses = ses,
                         stringsAsFactors = FALSE)
      sample_columns <- NULL
      if (seed %% 3L == 0L) {
        data$baseline <- round(stats::rnorm(n, 50, 10), 1)
        data$baseline[sample(n, 4L)] <- NA
        sample_columns <- list("baseline")
      }
      eta <- 0.2 * (arm == "treatment") + 0.3 * ses +
        stats::rnorm(schools, 0, 0.3)[class_school[row_class]] +
        stats::rnorm(length(class_school), 0, 0.2)[row_class]
      declaration <- list(
        vocabulary = "0.1.0",
        units = list(
          list(name = "school", columns = list("school"), role = "cluster"),
          list(name = "class", columns = list("class"), role = "cluster", nested_in = "school",
               id_scope = "within_parent"),
          list(name = "pupil", columns = list("pupil"), role = "participant", nested_in = "class",
               id_scope = "global")
        ),
        assignment = list(list(column = "arm", unit = "school", randomised = TRUE,
                               level = "between_unit"))
      )
      list(data = data, eta = eta, rhs = "arm + ses + (1 | school) + (1 | school:class)",
           declaration = declaration, sample_columns = sample_columns)
    }
  )
}

# A within-subject factor of three levels, low, mid and high, in that order of
# levels, with two or three trials of each level by subject and age as an
# integer covariate. The seeds vary the random part and the coding.
dd_within_three <- function() {
  dd_design(
    name = "within-three",
    description = "a within-subject factor of three levels, a covariate, contrasts and centring",
    build = function(seed) {
      subjects <- sample(30:44, 1L)
      reps <- sample(2:3, subjects, replace = TRUE)
      ids <- dd_ids("s", subjects)
      subject <- rep(ids, 3L * reps)
      level <- unlist(lapply(reps, function(r) rep(c("low", "mid", "high"), each = r)))
      age <- sample(19:68, subjects, replace = TRUE)[match(subject, ids)]
      data <- data.frame(subject = subject, cond = factor(level, levels = c("low", "mid", "high")),
                         age = age, stringsAsFactors = FALSE)
      eta <- c(low = 0, mid = 0.3, high = 0.6)[level] + 0.01 * (age - 40) +
        stats::rnorm(subjects, 0, 0.4)[match(subject, ids)]
      random <- switch(seed %% 3L + 1L, "(1 | subject) + (1 | subject:cond)", "(1 | subject)",
                       "(1 + cond | subject)")
      coding <- switch(seed %% 3L + 1L,
        list(cond = list(contrast = "simple", reference = "low"), age = list(centring = "mean")),
        NULL,
        list(cond = list(contrast = "sum", reference = "mid")))
      declaration <- list(
        vocabulary = "0.1.0",
        units = list(list(name = "subject", columns = list("subject"), role = "participant"))
      )
      list(data = data, eta = unname(eta), rhs = paste("cond + age +", random),
           declaration = declaration, coding = coding)
    }
  )
}

# Unbalanced subjects, many of them with one row, a covariate that varies
# within subjects and a logical treatment that does not, missing for a few
# subjects for one seed in three. Odd seeds have no disclosure unit, so that
# the contributors are the levels of the grouping factor.
dd_singletons <- function() {
  dd_design(
    name = "singletons",
    description = "unbalanced subjects with singletons, a logical predictor, no disclosure unit",
    build = function(seed) {
      subjects <- sample(50:70, 1L)
      sizes <- sample(c(1L, 1L, 1L, 1L, 2L, 2L, 3L, 4L, 6L, 9L), subjects, replace = TRUE)
      ids <- dd_ids("r", subjects)
      subject <- rep(ids, sizes)
      treated <- (stats::runif(subjects) < 0.5)[match(subject, ids)]
      if (seed %% 3L == 0L) {
        treated[subject %in% sample(ids, 3L)] <- NA
      }
      n <- length(subject)
      x <- round(stats::rnorm(n, 0, 1), 3)
      data <- data.frame(subject = subject, x = x, treated = treated, stringsAsFactors = FALSE)
      eta <- 0.4 * x + 0.3 * ifelse(is.na(treated), 0, treated) +
        stats::rnorm(subjects, 0, 0.5)[match(subject, ids)]
      declaration <- if (seed %% 2L == 0L) {
        list(vocabulary = "0.1.0",
             units = list(list(name = "subject", columns = list("subject"), role = "participant")))
      }
      list(data = data, eta = eta, rhs = "x + treated + (1 | subject)", declaration = declaration)
    }
  )
}

# Pairs of two persons in the roles A and B, some pairs with one person,
# each person measured twice alone and twice together, with the interaction
# of role and condition. The persons are the disclosure unit, nested in the
# pairs.
dd_pairs <- function() {
  dd_design(
    name = "pairs",
    description = "pairs with an interaction of role and condition, incomplete pairs",
    build = function(seed) {
      pairs <- sample(20:32, 1L)
      single <- stats::runif(pairs) < 0.1
      pair_ids <- dd_ids("d", pairs, 2L)
      person_pair <- unlist(lapply(seq_len(pairs), function(i) rep(i, if (single[i]) 1L else 2L)))
      role <- unlist(lapply(seq_len(pairs), function(i) {
        if (single[i]) sample(c("A", "B"), 1L) else c("A", "B")
      }))
      person <- paste0(pair_ids[person_pair], "-", role)
      rows <- rep(seq_along(person), each = 4L)
      condition <- factor(rep(c("solo", "joint", "solo", "joint"), length(person)),
                          levels = c("solo", "joint"))
      data <- data.frame(pair = pair_ids[person_pair][rows], person = person[rows],
                         role = role[rows], condition = condition, stringsAsFactors = FALSE)
      eta <- 0.3 * (data$role == "B") + 0.2 * (data$condition == "joint") +
        0.25 * (data$role == "B" & data$condition == "joint") +
        stats::rnorm(pairs, 0, 0.4)[person_pair][rows] +
        stats::rnorm(length(person), 0, 0.3)[rows]
      coding <- if (seed %% 3L == 0L) {
        list(role = list(contrast = "sum"), condition = list(contrast = "sum"))
      }
      declaration <- list(
        vocabulary = "0.1.0",
        units = list(list(name = "pair", columns = list("pair"), role = "dyad"),
                     list(name = "person", columns = list("person"), role = "participant",
                          nested_in = "pair", id_scope = "global"))
      )
      list(data = data, eta = eta, rhs = "role * condition + (1 | pair) + (1 | person)",
           declaration = declaration, coding = coding)
    }
  )
}
