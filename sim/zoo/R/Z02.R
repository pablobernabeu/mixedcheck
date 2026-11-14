# Z02 Pupil mobility between waves, and its matched negative Z02N. Pupils are
# observed in two waves, some of them change school in the second wave, the
# declaration says that their membership may change over time, and the
# formula nests pupil in school, so that the model splits each mover into two
# pupils. Z02N has no movers and the same declaration.

# The layout of the rows, from the parameters alone: pupil i of 1 to J n
# belongs to school ceil(i / n), the rows are ordered by pupil and wave, and
# a mover whose school is s attends school (s mod J) + 1 from wave 2 on.
zoo_Z02_layout <- function(p) {
  J <- p$schools
  n <- p$pupils_per_school
  W <- p$waves
  movers <- as.numeric(unclass(p$movers))
  pupil <- rep(seq_len(J * n), each = W)
  wave <- rep(seq_len(W), times = J * n)
  home <- ceiling(pupil / n)
  school <- ifelse(pupil %in% movers & wave >= 2, home %% J + 1, home)
  list(pupil = pupil, wave = wave, school = school)
}

# The data: pupil P01 to P(J n), school S1 to SJ, wave and y, one row for
# each pupil and wave. Draws, in this order: J school effects, J n pupil
# effects and the residuals in row order. y is the sum of the effect of the
# school of the row, the pupil effect and the residual, rounded to the stored
# grid. No property is drawn.
zoo_Z02 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    L <- zoo_Z02_layout(p)
    J <- p$schools
    P <- J * p$pupils_per_school
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    pupil_effect <- stats::rnorm(P, 0, as.numeric(p$sd_pupil))
    residual <- stats::rnorm(length(L$pupil), 0, as.numeric(p$sd_residual))
    data <- data.frame(
      pupil = zoo_label("P", L$pupil, P),
      school = zoo_label("S", L$school, J),
      wave = L$wave,
      y = zoo_round(school_effect[L$school] + pupil_effect[L$pupil] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z02_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("longitudinal"),
    table = list(fields = list(
      list(name = "pupil", type = "string"),
      list(name = "school", type = "string"),
      list(name = "wave", type = "integer"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "school", columns = zn("school"), role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "school", id_scope = "global",
           membership = "may_change_over_time", role = "participant")
    ),
    observation = list(key = zn("pupil", "wave"),
                       time = list(column = "wave", kind = "occasion", within = "pupil")),
    variables = list(y = list(role = "outcome", measurement = "continuous"),
                     wave = list(role = "time"))
  )
}

# The design of identifiability.gram_rank: the intercept and wave, and the
# random intercepts of school and of school:pupil, in IR order.
zoo_Z02_gram <- function(p) {
  L <- zoo_Z02_layout(p)
  ones <- matrix(1, length(L$pupil), 1L)
  list(X = cbind(ones, L$wave), terms = list(
    list(factor = L$school, columns = ones),
    list(factor = L$school * 1e6 + L$pupil, columns = ones)
  ))
}

# The number of distinct members of the disclosure unit, the pupils, in each
# level of an item given for every row.
zoo_Z02_members <- function(level, pupil) {
  vapply(split(pupil, level), function(x) length(unique(x)), 0)
}

# The expected findings, from the parameters. Every pupil is one member of
# the disclosure unit, so a count of the levels of pupil, of school:pupil or
# of the combinations of pupil and school resolves as a person count, and a
# count of the schools, each holding several pupils, as a non-person count.
zoo_Z02_expected <- function(p, data) {
  L <- zoo_Z02_layout(p)
  J <- p$schools
  n <- p$pupils_per_school
  m <- length(unique(as.numeric(unclass(p$movers))))
  stopifnot(J >= 2, n >= 2, p$waves == 2)
  N <- length(L$pupil)
  P <- J * n
  cell <- L$school * 1e6 + L$pupil
  school_sizes <- as.vector(tabulate(L$school, J))
  cell_sizes <- as.vector(vapply(split(cell, cell), length, 0))
  cells <- length(cell_sizes)
  replicated <- sum(cell_sizes >= 2)
  school_class <- zoo_count_class(zoo_Z02_members(L$school, L$pupil))
  cell_class <- zoo_count_class(zoo_Z02_members(cell, L$pupil))
  wave_class <- zoo_count_class(zoo_Z02_members(L$wave, L$pupil))
  pupil_class <- "person"
  # icc and within_share of wave within each factor, from the layout: the
  # schools differ only in how many rows of wave 2 the movers move, and a
  # level of school:pupil of two rows holds waves 1 and 2.
  by_school <- zoo_anova(L$wave, L$school)
  by_cell <- zoo_anova(L$wave, cell)
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The intercept and wave are linearly independent."),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(
          scaled_columns = zv(zn("wave")), sd_largest = zv(zoo_sd(L$wave)),
          sd_smallest = zv(zoo_sd(L$wave)), sd_ratio = zv(1),
          condition_number = zv(zoo_condition(cbind(1, L$wave)))
        ),
        why = paste0("wave is the only scaled column, with ", N / 2, " rows at 1 and ", N / 2,
                     " at 2, so its sd is sqrt(", N / 4, "/", N - 1,
                     ") and the condition number 3 + sqrt(10).")
      ),
      # budget = J - k + r with k = 2 kept columns, the intercept and wave, and
      # r = 1, since wave varies within the levels of both factors.
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 2 + 1, since wave varies within every school.")),
      zoo_db("school:pupil", cell_class, cells, cells - 1, "(Intercept)",
             paste0("J - k + r = ", cells, " - 2 + 1, since wave varies within the levels of ",
                    "two rows.")),
      zoo_gr(zoo_Z02_gram(p), paste0(
        "The ", replicated, " levels of school:pupil with two rows separate the pupil variance ",
        "from the residual, as zoo_gram() computes."
      )),
      zoo_ld1("school", school_class, J),
      zoo_ld1("school:pupil", cell_class, cells,
              if (replicated < cells) {
                "A level of one row also informs the intercept, so every level counts."
              }),
      zoo_rc1("school", school_class, J,
              paste0("Every school holds ", min(school_sizes), " rows or more.")),
      zoo_finding(
        "identifiability.residual_confounding",
        scope = list(factor = "school:pupil", term = "1 | school:pupil"),
        finding = "consistent", message = "replicated",
        statistics = list(columns = zv(1), correlated = zv(FALSE),
                          pattern_terms = zv(zn("1 | school:pupil")),
                          cells = zv(cells, cell_class),
                          replicated_cells = zv(replicated, cell_class),
                          intercept_alone = zv(TRUE)),
        why = if (m > 0) {
          paste0(cells - replicated, " levels of the movers hold one row, and the other ",
                 replicated, " hold two.")
        } else {
          paste0("Each of the ", cells, " levels holds two rows.")
        }
      ),
      zoo_kd(c("pupil", "wave"), N, "Each pupil has one row in each wave."),
      zoo_lu("pupil", pupil_class),
      zoo_lu("school", school_class),
      zoo_lu("wave", wave_class, "wave is a key column of integers, which hold no strings."),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", list(first = "school", second = "school:pupil"),
        "consistent", "nested",
        list(partition = zv("second_finer"), shared_columns = zv(TRUE),
             finer = zv(zn("school:pupil")), coarser = zv(zn("school")),
             coarser_levels = zv(J, school_class), informative_levels = zv(J, school_class),
             rows = zv(N), informative_rows = zv(N)),
        why = "Each level of school:pupil lies in one school, and every school holds several."
      ),
      zoo_cs("school", school_class, school_sizes,
             why = paste0("A mover leaves its school after wave 1 and joins the next, so the ",
                          "schools hold ", min(school_sizes), " to ", max(school_sizes),
                          " rows.")),
      zoo_cs("school:pupil", cell_class, cell_sizes,
             why = paste0(cells - replicated, " levels of one row from the ", m,
                          " movers, and ", replicated, " of two rows.")),
      # Each mover adds one combination of pupil and school and is the only
      # kind of pupil label in several schools, and every school holds
      # several pupils. pupil appears only in school:pupil, so composite is
      # true and inner_alone false, and declared nested_mobile with movers
      # gives movers_split.
      zoo_finding(
        "structure.label_incidence", list(first = "pupil", second = "school"),
        if (m > 0) "consequential" else "consistent",
        if (m > 0) "movers_split" else "relation",
        list(levels_first = zv(P, pupil_class), levels_second = zv(J, school_class),
             combinations = zv(P + m, pupil_class), first_in_several = zv(m, pupil_class),
             second_in_several = zv(J, school_class),
             relation = zv(if (m > 0) "partially_crossed" else "first_nested_in_second"),
             declared = zv("nested_mobile"), inner = zv(zn("pupil")),
             outer = zv(zn("school")), inner_in_several = zv(m, pupil_class),
             composite = zv(TRUE), inner_alone = zv(FALSE)),
        why = paste0(m, " pupils change school, which declared nested_mobile allows, and ",
                     "school:pupil holds pupil while no grouping factor holds it alone.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "school", term = "wave"),
        "consistent", "status",
        list(multi_row_levels = zv(J, school_class), varying_levels = zv(J, school_class),
             informative_levels = zv(J, school_class), status = zv("within"),
             slope_requested = zv(FALSE), icc = zv(by_school$icc),
             within_share = zv(by_school$within_share)),
        why = paste0("Every school holds rows of both waves, and zoo_anova() gives icc and ",
                     "within_share from the rows of each wave in each school.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "school:pupil", term = "wave"),
        "consistent", "status",
        list(multi_row_levels = zv(replicated, cell_class),
             varying_levels = zv(replicated, cell_class),
             informative_levels = zv(replicated, cell_class), status = zv("within"),
             slope_requested = zv(FALSE), icc = zv(by_cell$icc),
             within_share = zv(by_cell$within_share)),
        why = paste0("Each of the ", replicated, " levels of two rows holds both waves, and ",
                     "zoo_anova() gives icc and within_share over all ", cells, " levels.")
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N, P), design = zoo_sample(N, P)),
    findings = findings
  )
}

zoo_Z02_parameters <- function(movers) {
  list(schools = 6, pupils_per_school = 10, waves = 2, movers = zoo_array(movers),
       sd_school = "0.4", sd_pupil = "0.8", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z02", name = "pupil-mobility", title = "Pupil mobility between waves",
  role = "fixture", matched = "Z02N", negative_of = character(0), domain = "education",
  catalogue = "L7-01",
  planted = paste("4 of 60 pupils change school in wave 2, the declaration says that their",
                  "membership may change, and the formula nests pupil in school, which splits",
                  "each mover into two pupils."),
  seed = 202611020, parameters = zoo_Z02_parameters(c(3, 17, 31, 48)), generate = zoo_Z02,
  declaration = function(p) zoo_Z02_declaration(p, "Z02 Pupil mobility between waves"),
  formula = function(p) "y ~ wave + (1 | school/pupil)",
  run = zoo_access("Z02", "T0"), expected = zoo_Z02_expected,
  signal = list(zoo_signal("structure.label_incidence", list(first = "pupil", second = "school"),
                           "movers_split"))
)

zoo_define(
  id = "Z02N", name = "no-mobility", title = "No pupil mobility between waves",
  role = "negative", matched = "Z02", negative_of = "Z02", domain = "education",
  catalogue = "L7-01",
  planted = paste("No pupil changes school, so nesting pupil in school splits no pupil,",
                  "with the same declaration and formula."),
  seed = 202611020, parameters = zoo_Z02_parameters(numeric(0)), generate = zoo_Z02,
  declaration = function(p) zoo_Z02_declaration(p, "Z02N No pupil mobility between waves"),
  formula = function(p) "y ~ wave + (1 | school/pupil)",
  run = zoo_access("Z02N", "T0"), expected = zoo_Z02_expected,
  signal = list()
)
