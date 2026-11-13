# Z07 Latin square with one observation per subject and item, and its
# matched negative Z07N. In Z07, each subject sees each item once, and the
# formula has a subject-by-item intercept, whose levels hold one row each, so
# its variance is confounded with the residual. In Z07N, each subject sees
# each of 6 items twice. The counterbalancing of the lists is a planned check.

# The data: L lists, m subjects in each list and c items for each of the 3
# conditions, so S = L m subjects and I = 3 c items. Subject s is in list
# ((s - 1) mod L) + 1, and the row of item it in list l has the condition at
# position ((it - 1) + (l - 1)) mod 3 of A, B and C. Each subject sees every
# item reps times, and the rows are ordered by subject, item and repetition.
# Draws, in this order: S subject intercepts, then the subject slopes of B
# and of C for each subject in label order, I item intercepts, the item
# slopes of B and of C for each item in label order, and the residuals in row
# order. y is the sum of the intercepts, the slopes of the row's condition
# and the residual, rounded to the stored grid. No property is drawn.
zoo_Z07 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z07_design(p)
    S <- design$subjects
    I <- design$items
    subject_intercept <- stats::rnorm(S, 0, as.numeric(p$sd_subject))
    subject_slope <- matrix(stats::rnorm(2 * S, 0, as.numeric(p$sd_slopes)), S, 2L,
                            byrow = TRUE)
    item_intercept <- stats::rnorm(I, 0, as.numeric(p$sd_item))
    item_slope <- matrix(stats::rnorm(2 * I, 0, as.numeric(p$sd_slopes)), I, 2L, byrow = TRUE)
    residual <- stats::rnorm(length(design$subject), 0, as.numeric(p$sd_residual))
    subject <- design$subject
    item <- design$item
    condition <- design$condition
    slope <- function(effects) {
      ifelse(condition == 1L, 0, effects[cbind(seq_along(condition), pmax(condition - 1L, 1L))])
    }
    data <- data.frame(
      subject = zoo_label("s", subject, S),
      item = zoo_label("i", item, I),
      list = zoo_label("L", design$list, p$lists),
      cond = c("A", "B", "C")[condition]
    )
    if (p$reps > 1) {
      data$rep <- design$rep
    }
    data$y <- zoo_round(subject_intercept[subject] + slope(subject_slope[subject, , drop = FALSE]) +
                          item_intercept[item] + slope(item_slope[item, , drop = FALSE]) +
                          residual, p$digits)
    zoo_check(data, list(), NULL, checks)
  })
}

# The structure of the rows: subject, item, repetition, list and condition,
# the condition as 1, 2 or 3 for A, B and C.
zoo_Z07_design <- function(p) {
  S <- p$lists * p$subjects_per_list
  I <- 3 * p$items_per_condition
  R <- p$reps
  subject <- rep(seq_len(S), each = I * R)
  item <- rep(rep(seq_len(I), each = R), times = S)
  list <- (subject - 1L) %% p$lists + 1L
  list(subjects = S, items = I, subject = subject, item = item,
       rep = rep(seq_len(R), times = S * I), list = list,
       condition = ((item - 1L) + (list - 1L)) %% 3L + 1L)
}

zoo_Z07_declaration <- function(p, title) {
  fields <- list(
    list(name = "subject", type = "string"),
    list(name = "item", type = "string"),
    list(name = "list", type = "string"),
    list(name = "cond", type = "string", categories = zn("A", "B", "C"))
  )
  if (p$reps > 1) {
    fields <- c(fields, list(list(name = "rep", type = "integer")))
  }
  fields <- c(fields, list(list(name = "y", type = "number")))
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("crossed_experiment", "counterbalanced"),
    table = list(fields = fields),
    units = list(
      list(name = "subject", columns = zn("subject"), role = "participant"),
      list(name = "item", columns = zn("item"), role = "item")
    ),
    crossings = list(list(units = zn("subject", "item"), list = "list")),
    observation = list(key = zn(c("subject", "item", if (p$reps > 1) "rep"))),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept), cond[B]
# and cond[C], the terms 1 + cond | subject and 1 + cond | item with the same
# three columns and the term 1 | subject:item, in the order of the formula.
zoo_Z07_gram <- function(p) {
  design <- zoo_Z07_design(p)
  X <- cbind(1, as.numeric(design$condition == 2L), as.numeric(design$condition == 3L))
  list(X = X, terms = list(
    list(factor = design$subject, columns = X),
    list(factor = design$item, columns = X),
    list(factor = (design$subject - 1L) * design$items + design$item,
         columns = X[, 1L, drop = FALSE])
  ))
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit, so the levels of subject and of subject:item,
# the combinations of item and subject and the cells of subject and pattern
# resolve as person counts. Each item is seen by S subjects, each condition
# and each repetition by S subjects, and each cell of item and condition by m
# subjects, so their counts resolve as non-person counts.
zoo_Z07_expected <- function(p, data) {
  design <- zoo_Z07_design(p)
  S <- design$subjects
  I <- design$items
  R <- p$reps
  m <- p$subjects_per_list
  stopifnot(p$lists == 3, m >= 2, p$items_per_condition >= 1, R %in% c(1, 2))
  N <- S * I * R
  P <- "person"
  item_class <- zoo_count_class(S)
  cell_class <- zoo_count_class(m)
  key <- if (R > 1) c("subject", "item", "rep") else c("subject", "item")
  pair <- list(first = "item", second = "subject")
  cells <- S * I
  gram <- zoo_gram(zoo_Z07_gram(p)$X, zoo_Z07_gram(p)$terms)
  random <- function(factor, class, levels) {
    term <- paste0("1 + cond | ", factor)
    list(
      zoo_finding(
        "identifiability.levels_vs_dimension", list(factor = factor, term = term),
        "consistent", "adequate",
        list(dimension = zv(3), levels = zv(levels, class),
             informative_levels = zv(levels, class), counterparts = zv(TRUE),
             bound = zv(levels - 1, class)),
        why = paste0("Every ", factor, " occurs in all three conditions across the lists, so ",
                     "[1, cond[B], cond[C]] has rank 3 in each of the ", levels, " levels.")
      ),
      zoo_finding(
        "identifiability.residual_confounding", list(factor = factor, term = term),
        "consistent", "replicated",
        list(columns = zv(3), correlated = zv(TRUE), pattern_terms = zv(zn(term)),
             cells = zv(3 * levels, if (factor == "item") cell_class else P),
             replicated_cells = zv(3 * levels, if (factor == "item") cell_class else P),
             intercept_alone = zv(FALSE)),
        why = paste0("Each ", factor, " has the 3 conditions, each in ", N / (3 * levels),
                     " rows.")
      )
    )
  }
  within <- function(factor, class, levels) {
    zoo_finding(
      "structure.within_between", list(factor = factor, term = "cond"), "consistent", "status",
      list(multi_row_levels = zv(levels, class), varying_levels = zv(levels, class),
           informative_levels = zv(levels, class), status = zv("within"),
           slope_requested = zv(TRUE), icc = za(), within_share = za()),
      why = paste0("Every ", factor, " has rows of all three conditions, and 1 + cond | ",
                   factor, " requests the slope.")
    )
  }
  nested <- function(factor, class, levels) {
    zoo_finding(
      "structure.aliased_factors", list(first = factor, second = "subject:item"), "consistent",
      "nested",
      list(partition = zv("second_finer"), shared_columns = zv(TRUE),
           finer = zv(zn("subject:item")), coarser = zv(zn(factor)),
           coarser_levels = zv(levels, class), informative_levels = zv(levels, class),
           rows = zv(N), informative_rows = zv(N)),
      why = paste0("Each level of subject:item lies in one ", factor, ", and every ", factor,
                   " holds several of them.")
    )
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(3, "The columns (Intercept), cond[B] and cond[C] are linearly independent."),
      zoo_db("item", item_class, I, I - 1, "(Intercept)",
             paste0("J - k + r = ", I, " - 3 + 2, since cond varies within every item.")),
      zoo_db("subject", P, S, S - 1, "(Intercept)",
             paste0("J - k + r = ", S, " - 3 + 2, since cond varies within every subject.")),
      zoo_db("subject:item", P, cells, cells - 3, c("(Intercept)", "cond"),
             paste0("J - k + r = ", cells, " - 3 + 0, since cond is constant within every ",
                    "level of subject:item, so both terms lower the budget.")),
      zoo_ld1("subject:item", P, cells, paste0(
        "Every one of the ", cells, " levels informs the intercept, and the bound is ",
        cells - 1, "."
      )),
      zoo_kd(key, N, paste0("Each of the ", N, " rows has its own value of the key.")),
      zoo_lu("cond", item_class),
      zoo_lu("item", item_class),
      zoo_lu("subject", P),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Every item occurs with every subject, so neither partition is finer, and ",
                     "both terms have the intercept.")
      ),
      nested("item", item_class, I),
      nested("subject", P, S),
      zoo_cs("item", item_class, rep(S * R, I)),
      zoo_cs("subject", P, rep(I * R, S)),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, P), between_component_terms = zv(zn()), exact = zv(TRUE)),
        why = "Every subject sees every item, so subjects and items form one component."
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(I, item_class), levels_second = zv(S, P),
             combinations = zv(cells, P), first_in_several = zv(I, item_class),
             second_in_several = zv(S, P), relation = zv("crossed"),
             declared = zv("crossed"), inner = zv(zn()), outer = zv(zn()),
             inner_in_several = za(), composite = zv(FALSE), inner_alone = zv(FALSE)),
        why = paste0("All ", cells, " combinations occur, and composite is false, since subject ",
                     "and item each keep a grouping factor of their own beside subject:item.")
      ),
      within("item", item_class, I),
      within("subject", P, S)
    ),
    random("item", item_class, I),
    random("subject", P, S)
  )
  if (R == 1) {
    # Z of subject:item is a permutation of the identity, so the basis of its
    # variance equals the residual basis, and C has one null vector on the
    # two parameters, which the other twelve do not load.
    stopifnot(length(gram$vanishing) == 0L, abs(gram$smallest_eigenvalue) < 1e-12)
    findings <- c(findings, list(
      zoo_finding(
        "identifiability.gram_rank", finding = "consequential", message = "not_identified",
        statistics = list(
          parameters = zv(14), rank = zv(13), verdict = zv("not_identified"),
          vanishing_parameters = zv(zn()),
          confounded_parameters = zv(zn("1 | subject:item: var((Intercept))", "residual")),
          smallest_eigenvalue = zi("-1e-12", "1e-12")
        ),
        why = paste0("Each level of subject:item holds one row, so its random-effects matrix is ",
                     "a permutation of the identity and its basis equals the residual basis.")
      ),
      zoo_finding(
        "identifiability.residual_confounding",
        list(factor = "subject:item", term = "1 | subject:item"), "consequential", "confounded",
        list(columns = zv(1), correlated = zv(FALSE), pattern_terms = zv(zn("1 | subject:item")),
             cells = zv(cells, P), replicated_cells = zv(0, P), intercept_alone = zv(TRUE)),
        why = "Every level of subject:item holds one row, and the family class is gaussian."
      ),
      zoo_finding(
        "structure.cluster_sizes", list(factor = "subject:item"), "consequential",
        "one_row_per_level",
        list(levels = zv(cells, P), rows = zv(N), smallest = zv(1), lower_quartile = zv(1),
             median = zv(1), upper_quartile = zv(1), largest = zv(1), singletons = zv(cells),
             effective_size = zv((N - cells / N) / (cells - 1)), intercept = zv(TRUE)),
        why = paste0("The ", cells, " levels equal the rows, (1 | subject:item) has an ",
                     "intercept, and the family class is gaussian.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject:item", term = "cond"), "consistent",
        "no_levels",
        status = list(assessability = list(value = "not_assessable",
                                           reason = "prerequisite_unmet",
                                           detail = "level_with_two_rows")),
        statistics = list(multi_row_levels = zv(0, P), varying_levels = zv(0, P),
                          informative_levels = zv(0, P), status = za(),
                          slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "No level of subject:item has two rows."
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_gr(zoo_Z07_gram(p), paste0(
        "The two repetitions of each subject and item separate the subject:item variance ",
        "from the residual, as zoo_gram() computes them."
      )),
      zoo_rc1("subject:item", P, cells, paste0("Each of the ", cells,
                                                " levels holds its two repetitions.")),
      zoo_cs("subject:item", P, rep(R, cells)),
      zoo_finding(
        "structure.within_between", list(factor = "subject:item", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(cells, P), varying_levels = zv(0, P),
             informative_levels = zv(0, P), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "The two repetitions of a subject and item have the same condition."
      ),
      zoo_lu("rep", item_class, "The repetitions are the integers 1 and 2.")
    ))
  }
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z07_parameters <- function(items_per_condition, reps) {
  list(lists = 3, subjects_per_list = 4, items_per_condition = items_per_condition,
       reps = reps, sd_subject = "0.5", sd_item = "0.3", sd_slopes = "0.2",
       sd_residual = "1", digits = 2)
}

zoo_Z07_planned <- list(zoo_planned(
  "design.counterbalancing", "T0", "L7-14", registry = "0.2", milestone = "M4",
  needs = "the list column of a declared crossing, which vocabulary 0.1 has",
  description = paste("The items of each condition in each list of a declared crossing with a",
                      "list, so that every list holds every condition equally often.")
))

zoo_define(
  id = "Z07", name = "latin-square-one-row",
  title = "Latin square with one observation per cell",
  role = "fixture", matched = "Z07N", negative_of = character(0), domain = "crossed",
  catalogue = c("L1-05", "L7-14"),
  planted = paste("Each subject sees each item once, and the formula has a subject-by-item",
                  "intercept whose levels hold one row each, so its variance is confounded with",
                  "the residual."),
  seed = 202611070, parameters = zoo_Z07_parameters(4, 1), generate = zoo_Z07,
  declaration = function(p) {
    zoo_Z07_declaration(p, "Z07 Latin square with one observation per cell")
  },
  formula = function(p) {
    "y ~ cond + (1 + cond | subject) + (1 + cond | item) + (1 | subject:item)"
  },
  run = zoo_access("Z07", "T0"), expected = zoo_Z07_expected,
  signal = list(
    zoo_signal("identifiability.gram_rank", list(), "not_identified"),
    zoo_signal("identifiability.residual_confounding",
               list(factor = "subject:item", term = "1 | subject:item"), "confounded"),
    zoo_signal("structure.cluster_sizes", list(factor = "subject:item"), "one_row_per_level")
  ),
  planned = zoo_Z07_planned
)

zoo_define(
  id = "Z07N", name = "latin-square-two-rows",
  title = "Latin square with two observations per cell",
  role = "negative", matched = "Z07", negative_of = "Z07", domain = "crossed",
  catalogue = c("L1-05", "L7-14"),
  planted = paste("Each subject sees each of 6 items twice, so the subject-by-item intercept",
                  "is separated from the residual."),
  seed = 202611070, parameters = zoo_Z07_parameters(2, 2), generate = zoo_Z07,
  declaration = function(p) {
    zoo_Z07_declaration(p, "Z07N Latin square with two observations per cell")
  },
  formula = function(p) {
    "y ~ cond + (1 + cond | subject) + (1 + cond | item) + (1 | subject:item)"
  },
  run = zoo_access("Z07N", "T0"), expected = zoo_Z07_expected,
  signal = list()
)
