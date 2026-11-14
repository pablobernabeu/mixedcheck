# Z05 Between-subject predictor with a by-subject slope, and its matched
# negative Z05N. In Z05, cond is constant within each subject, and the formula
# asks for a by-subject slope of cond, which can only describe how the
# variance between subjects differs between the conditions. In Z05N, cond
# varies within subjects.

# The data: subjects s01 to sS crossed with items i01 to iI, one row for each
# subject and item, ordered by subject and item. In Z05 (between true), the
# first half of the subjects take 'a' and the second half 'b'. In Z05N, the
# row of subject s and item i takes 'b' when s + i is odd, which gives each
# subject I/2 rows of each condition and each item S/2 subjects of each for
# even S and I. Draws, in this order: S subject intercepts, S subject slopes,
# I item effects and S I residuals. y is the subject intercept, plus the
# effect of 'b' and the subject's slope in rows of 'b', plus the item effect
# and the residual, rounded to the stored grid. No property is drawn.
zoo_Z05 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    S <- p$subjects
    I <- p$items
    intercept <- stats::rnorm(S, 0, as.numeric(p$sd_subject))
    slope <- stats::rnorm(S, 0, as.numeric(p$sd_slope))
    item_effect <- stats::rnorm(I, 0, as.numeric(p$sd_item))
    residual <- stats::rnorm(S * I, 0, as.numeric(p$sd_residual))
    subject <- rep(seq_len(S), each = I)
    item <- rep(seq_len(I), times = S)
    b <- zoo_Z05_b(p, subject, item)
    data <- data.frame(
      subject = zoo_label("s", subject, S),
      item = zoo_label("i", item, I),
      cond = ifelse(b, "b", "a"),
      y = zoo_round(intercept[subject] + b * (as.numeric(p$effect) + slope[subject]) +
                      item_effect[item] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# Whether each row has condition 'b'.
zoo_Z05_b <- function(p, subject, item) {
  if (p$between) subject > p$subjects / 2 else (subject + item) %% 2 == 1
}

zoo_Z05_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("crossed_experiment"),
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "item", type = "string"),
      list(name = "cond", type = "string", categories = zn("a", "b")),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "subject", columns = zn("subject"), role = "participant"),
      list(name = "item", columns = zn("item"), role = "item")
    ),
    crossings = list(list(units = zn("subject", "item"))),
    observation = list(key = zn("subject", "item")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# cond[b], the term 1 + cond | subject with the same two columns and the term
# 1 | item, in the order of the formula.
zoo_Z05_gram <- function(p) {
  S <- p$subjects
  I <- p$items
  subject <- rep(seq_len(S), each = I)
  item <- rep(seq_len(I), times = S)
  X <- cbind(1, as.numeric(zoo_Z05_b(p, subject, item)))
  list(X = X, terms = list(
    list(factor = subject, columns = X),
    list(factor = item, columns = X[, 1L, drop = FALSE])
  ))
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit, so the levels of subject, the combinations
# of subject and item and the cells of subject and pattern resolve as person
# counts, and the levels of item and cond, which hold S and S/2 subjects, as
# non-person counts.
zoo_Z05_expected <- function(p, data) {
  S <- p$subjects
  I <- p$items
  stopifnot(S >= 4, I >= 2, S %% 2 == 0, I %% 2 == 0)
  N <- S * I
  subject_class <- zoo_count_class(1)
  item_class <- zoo_count_class(S)
  pair_class <- zoo_count_class(1)
  term <- "1 + cond | subject"
  # Within a subject of Z05, cond[b] is constant, so the within-level rank r
  # of the kept columns (Intercept) and cond[b] is 0 for subject. It varies
  # within every item, so r is 1 for item, and in Z05N within every subject.
  r_subject <- if (p$between) 0 else 1
  # zoo_gram() of the design, whose parameters are those of
  # 1 + cond | subject in IR order, then that of 1 | item and the residual.
  gram <- zoo_gram(zoo_Z05_gram(p)$X, zoo_Z05_gram(p)$terms)
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and cond[b] are linearly independent."),
      zoo_db("item", item_class, I, I - 1, "(Intercept)",
             paste0("J - k + r = ", I, " - 2 + 1, since cond varies within every item, so ",
                    "cond lowers no budget.")),
      if (p$between) {
        zoo_db("subject", subject_class, S, S - 2, zn("(Intercept)", "cond"),
               paste0("J - k + r = ", S, " - 2 + 0, since cond is constant within every ",
                      "subject, so both terms lower the budget."))
      } else {
        zoo_db("subject", subject_class, S, S - 1, "(Intercept)",
               paste0("J - k + r = ", S, " - 2 + 1, since cond varies within every subject."))
      },
      zoo_ld1("item", item_class, I),
      zoo_rc1("item", item_class, I, paste0(S, " rows in each level.")),
      zoo_kd(c("subject", "item"), N,
             paste0("Each of the ", N, " pairs of subject and item has one row.")),
      zoo_lu("cond", zoo_count_class(S / 2)),
      zoo_lu("item", item_class),
      zoo_lu("subject", subject_class),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", list(first = "item", second = "subject"), "consistent",
        "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Every item occurs with every subject, so neither partition is finer, and ",
                     "both terms have the intercept.")
      ),
      zoo_cs("item", item_class, rep(S, I)),
      zoo_cs("subject", subject_class, rep(I, S)),
      zoo_finding(
        "structure.connectivity", list(first = "item", second = "subject"), "consistent",
        "connected",
        list(components = zv(1, pair_class), between_component_terms = zv(zn()),
             exact = zv(TRUE)),
        why = "The full crossing links every subject with every item in one component."
      ),
      zoo_finding(
        "structure.label_incidence", list(first = "item", second = "subject"), "consistent",
        "relation",
        list(levels_first = zv(I, item_class), levels_second = zv(S, subject_class),
             combinations = zv(N, pair_class), first_in_several = zv(I, item_class),
             second_in_several = zv(S, subject_class), relation = zv("crossed"),
             declared = zv("crossed"), inner = zv(zn()), outer = zv(zn()),
             inner_in_several = za(), composite = zv(FALSE), inner_alone = zv(FALSE)),
        why = paste0("All ", N, " combinations occur, the pair is declared crossed, and no ",
                     "grouping factor joins the two columns.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "item", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(I, item_class), varying_levels = zv(I, item_class),
             informative_levels = zv(I, item_class), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("Every item has ", S / 2, " subjects of each condition, and icc and ",
                     "within_share are absent for a categorical term.")
      )
    )
  )
  if (p$between) {
    # The column cond[b] equals the intercept in every level of a subject of
    # 'b' and is 0 in every level of a subject of 'a', so the basis of the
    # covariance is twice that of the variance of cond[b] in every level, and
    # C has one null vector on those two parameters, which the intercept
    # variances, the item variance and the residual do not load.
    stopifnot(length(gram$vanishing) == 0L, abs(gram$smallest_eigenvalue) < 1e-12)
    findings <- c(findings, list(
      zoo_finding(
        "identifiability.gram_rank", finding = "consequential", message = "not_identified",
        statistics = list(
          parameters = zv(5), rank = zv(4), verdict = zv("not_identified"),
          vanishing_parameters = zv(zn()),
          confounded_parameters = zv(zn(paste0(term, ": cov((Intercept), cond[b])"),
                                        paste0(term, ": var(cond[b])"))),
          smallest_eigenvalue = zi("-1e-12", "1e-12")
        ),
        why = paste0("cond[b] equals the intercept within a subject of b and is 0 within one ",
                     "of a, so the covariance basis is twice the slope basis in every level.")
      ),
      zoo_finding(
        "identifiability.levels_vs_dimension", list(factor = "subject", term = term),
        "detectable_inconsequential", "likely",
        list(dimension = zv(2), levels = zv(S, subject_class),
             informative_levels = zv(0, subject_class), counterparts = zv(TRUE),
             bound = zv(S - 1, subject_class)),
        why = paste0("[1, cond[b]] has rank 1 within every subject, so no level informs the ",
                     "term, and 0 is at most the dimension 2.")
      ),
      zoo_finding(
        "identifiability.residual_confounding", list(factor = "subject", term = term),
        "consistent", "replicated",
        list(columns = zv(2), correlated = zv(TRUE), pattern_terms = zv(zn(term)),
             cells = zv(S, subject_class), replicated_cells = zv(S, subject_class),
             intercept_alone = zv(FALSE)),
        why = paste0("Each subject has one pattern of [1, cond[b]], held by its ", I, " rows.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "cond"),
        "consequential", "between_slope",
        list(multi_row_levels = zv(S, subject_class), varying_levels = zv(0, subject_class),
             informative_levels = zv(0, subject_class), status = zv("between"),
             slope_requested = zv(TRUE), icc = za(), within_share = za()),
        why = paste0("cond is exactly constant within every subject, and 1 + cond | subject ",
                     "requests its slope.")
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_gr(zoo_Z05_gram(p), paste0(
        "Each subject has both conditions, so the 5 parameters are separated, as zoo_gram() ",
        "computes them."
      )),
      zoo_finding(
        "identifiability.levels_vs_dimension", list(factor = "subject", term = term),
        "consistent", "adequate",
        list(dimension = zv(2), levels = zv(S, subject_class),
             informative_levels = zv(S, subject_class), counterparts = zv(TRUE),
             bound = zv(S - 1, subject_class)),
        why = paste0("[1, cond[b]] has rank 2 within every subject, and the bound ", S - 1,
                     " is at least 2.")
      ),
      zoo_finding(
        "identifiability.residual_confounding", list(factor = "subject", term = term),
        "consistent", "replicated",
        list(columns = zv(2), correlated = zv(TRUE), pattern_terms = zv(zn(term)),
             cells = zv(2 * S, subject_class), replicated_cells = zv(2 * S, subject_class),
             intercept_alone = zv(FALSE)),
        why = paste0("Each subject has two patterns of [1, cond[b]], each held by ", I / 2,
                     " rows.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(S, subject_class), varying_levels = zv(S, subject_class),
             informative_levels = zv(S, subject_class), status = zv("within"),
             slope_requested = zv(TRUE), icc = za(), within_share = za()),
        why = paste0("Every subject has ", I / 2, " rows of each condition.")
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z05_parameters <- function(between) {
  list(subjects = 16, items = 12, between = between, sd_subject = "0.5", sd_slope = "0.3",
       sd_item = "0.3", sd_residual = "1", effect = "0.4", digits = 2)
}

zoo_define(
  id = "Z05", name = "between-subject-slope",
  title = "Between-subject predictor with a by-subject slope",
  role = "fixture", matched = "Z05N", negative_of = character(0), domain = "crossed",
  catalogue = c("L1-03", "L1-04"),
  planted = paste("cond is constant within each subject, and the formula asks for a by-subject",
                  "slope of cond, which the data cannot separate from the subject variances."),
  seed = 202611050, parameters = zoo_Z05_parameters(TRUE), generate = zoo_Z05,
  declaration = function(p) {
    zoo_Z05_declaration(p, "Z05 Between-subject predictor with a by-subject slope")
  },
  formula = function(p) "y ~ cond + (1 + cond | subject) + (1 | item)",
  run = zoo_access("Z05", "T0"), expected = zoo_Z05_expected,
  signal = list(
    zoo_signal("identifiability.gram_rank", list(), "not_identified"),
    zoo_signal("identifiability.levels_vs_dimension",
               list(factor = "subject", term = "1 + cond | subject"), "likely"),
    zoo_signal("structure.within_between", list(factor = "subject", term = "cond"),
               "between_slope")
  )
)

zoo_define(
  id = "Z05N", name = "within-subject-slope",
  title = "Within-subject predictor with a by-subject slope",
  role = "negative", matched = "Z05", negative_of = "Z05", domain = "crossed",
  catalogue = c("L1-03", "L1-04"),
  planted = paste("cond varies within every subject, with 6 rows of each condition, so the",
                  "by-subject slope of cond is identified."),
  seed = 202611050, parameters = zoo_Z05_parameters(FALSE), generate = zoo_Z05,
  declaration = function(p) {
    zoo_Z05_declaration(p, "Z05N Within-subject predictor with a by-subject slope")
  },
  formula = function(p) "y ~ cond + (1 + cond | subject) + (1 | item)",
  run = zoo_access("Z05N", "T0"), expected = zoo_Z05_expected,
  signal = list()
)
