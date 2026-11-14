# Z21 Few clusters, and its matched negative Z21N. A trial randomised 4
# schools, 2 to each arm, and the formula also adjusts for two school-level
# covariates, the area of the school and its share of pupils eligible for
# free school meals. With the intercept and the arm, these use up the 4
# schools, so no degree of freedom between schools remains, either for the
# variance of the school intercept or for the effect of the arm. Registry
# 0.1.0 flags both through identifiability.df_budget, assignment.design_df
# and identifiability.gram_rank, whose school variance vanishes. A check of
# few clusters that would also flag 4 schools without the covariates is
# planned. Z21N has 40 schools of 6 pupils and the same formula.

# The layout of the schools, from the parameters alone: school j takes
# control when j is odd and tutoring when it is even, lies in an urban area
# in the first half of the schools and a rural one in the second, and has
# fsm 0.40 when j mod 4 is 0 or 1 and 0.20 otherwise. With J a multiple of
# 4, each arm and each area holds as many schools at 0.40 as at 0.20, and
# each combination of arm and area as many schools as the others, so that
# the columns of arm, area and fsm are uncorrelated over the rows.
zoo_Z21_layout <- function(p) {
  J <- p$schools
  stopifnot(J %% 4 == 0)
  j <- seq_len(J)
  list(tutoring = j %% 2 == 0, rural = j > J / 2, fsm = ifelse(j %% 4 <= 1, 0.4, 0.2))
}

# The data: school S01 onwards, pupil P001 onwards, arm, area, fsm and y,
# ordered by school and pupil, with area and fsm left out when covariates is
# false. Draws, in this order: J school effects and the residuals in row
# order. y is the school effect, effect for tutoring and the residual,
# rounded to the stored grid. No property is drawn.
zoo_Z21 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    L <- zoo_Z21_layout(p)
    J <- p$schools
    n <- p$pupils
    N <- J * n
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    school <- rep(seq_len(J), each = n)
    data <- data.frame(
      school = zoo_label("S", school, max(J, 10)),
      pupil = zoo_label("P", seq_len(N), max(N, 100)),
      arm = ifelse(L$tutoring[school], "tutoring", "control")
    )
    if (p$covariates) {
      data$area <- ifelse(L$rural[school], "rural", "urban")
      data$fsm <- L$fsm[school]
    }
    data$y <- zoo_round(school_effect[school] + as.numeric(p$effect) * L$tutoring[school] +
                          residual, p$digits)
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z21_declaration <- function(p, title) {
  fields <- list(
    list(name = "school", type = "string"),
    list(name = "pupil", type = "string"),
    list(name = "arm", type = "string", categories = zn("control", "tutoring"))
  )
  variables <- list(y = list(role = "outcome", measurement = "continuous"),
                    arm = list(role = "assigned"))
  if (p$covariates) {
    fields <- c(fields, list(
      list(name = "area", type = "string", categories = zn("urban", "rural")),
      list(name = "fsm", type = "number")
    ))
    variables <- c(variables, list(area = list(role = "baseline_covariate"),
                                   fsm = list(role = "baseline_covariate")))
  }
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("cluster_randomised"),
    table = list(fields = c(fields, list(list(name = "y", type = "number")))),
    units = list(
      list(name = "school", columns = zn("school"), role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    assignment = list(list(column = "arm", unit = "school", randomised = TRUE,
                           level = "between_unit")),
    variables = variables,
    estimands = list(list(id = "ITT", term = "arm", kind = "total_effect"))
  )
}

zoo_Z21_formula <- function(p) {
  if (p$covariates) "y ~ arm + area + fsm + (1 | school)" else "y ~ arm + (1 | school)"
}

# The fixed-effects columns over the rows: the intercept, arm[tutoring],
# area[rural] and fsm, the reference levels being control and urban.
zoo_Z21_X <- function(p) {
  L <- zoo_Z21_layout(p)
  school <- rep(seq_len(p$schools), each = p$pupils)
  cbind(1, as.numeric(L$tutoring[school]), as.numeric(L$rural[school]), L$fsm[school])
}

# The expected findings with covariates, from the parameters alone. Every
# pupil is one member of the disclosure unit, and every school, arm and area
# holds several pupils, so the counts of their levels resolve as non-person
# counts. The four fixed columns are constant within schools.
zoo_Z21_expected <- function(p, data) {
  stopifnot(p$covariates)
  L <- zoo_Z21_layout(p)
  J <- p$schools
  n <- p$pupils
  N <- J * n
  stopifnot(J >= 4, n >= 2)
  school_class <- zoo_count_class(n)
  half_class <- zoo_count_class(N / 2)
  X <- zoo_Z21_X(p)
  school <- rep(seq_len(J), each = n)
  ones <- matrix(1, N, 1L)
  gram <- zoo_gram(X, list(list(factor = school, columns = ones)))
  # The budget and design_df are J - k + r with k = 4 kept columns and r = 0,
  # since all four are constant within schools.
  budget <- J - 4
  assignment <- list(column = "arm", unit = "school")
  status_between <- function(term, real, why) {
    statistics <- list(multi_row_levels = zv(J, school_class), varying_levels = zv(0, school_class),
                       informative_levels = zv(0, school_class), status = zv("between"),
                       slope_requested = zv(FALSE))
    if (real) {
      # fsm is constant within schools: SSW = 0, so MSW = 0, icc = MSB / MSB
      # = 1 and within_share = 0.
      statistics <- c(statistics, list(icc = zv(1), within_share = zv(0)))
    } else {
      statistics <- c(statistics, list(icc = za(), within_share = za()))
    }
    zoo_finding("structure.within_between", list(factor = "school", term = term),
                "consistent", "status", statistics, why = why)
  }
  findings <- list(
    zoo_finding(
      "assignment.constant_within_unit", assignment, "consistent", "constant",
      list(units = zv(J, school_class), mixed_units = zv(0, school_class),
           level_source = zv("declared")),
      why = paste0("Every one of the ", J, " schools takes one arm for all its pupils.")
    ),
    if (budget == 0) {
      zoo_finding(
        "assignment.design_df", assignment, "consequential", "no_df",
        list(units = zv(J, school_class), design_df = zv(0, school_class),
             missing_blocks = zv(zn()), level_source = zv("declared")),
        why = paste0("J + r - k = ", J, " + 0 - 4: the 4 kept columns are constant within ",
                     "schools and use up the ", J, " schools.")
      )
    } else {
      zoo_finding(
        "assignment.design_df", assignment, "consistent", "design_df",
        list(units = zv(J, school_class), design_df = zv(budget, school_class),
             missing_blocks = zv(zn()), level_source = zv("declared")),
        why = paste0("J + r - k = ", J, " + 0 - 4, the 4 kept columns being constant within ",
                     "schools.")
      )
    },
    zoo_finding(
      "assignment.unit_in_random_part", assignment, "consistent", "unit_present",
      list(units = zv(J, school_class), coverage = zv("present"), coarser_factors = zv(zn()),
           level_source = zv("declared")),
      why = "The school intercept divides the rows into the schools."
    ),
    zoo_finding(
      "design.collinearity", list(term = "area"), "consistent", "low",
      list(df = zv(1), gvif = zv(1), gvif_per_df = zv(1)),
      why = paste0("The centred columns of arm, area and fsm are orthogonal, since each ",
                   "combination of two of them holds as many schools as the others.")
    ),
    zoo_finding(
      "design.collinearity", list(term = "arm"), "consistent", "low",
      list(df = zv(1), gvif = zv(1), gvif_per_df = zv(1)),
      why = "The centred columns of arm, area and fsm are orthogonal."
    ),
    zoo_finding(
      "design.collinearity", list(term = "fsm"), "consistent", "low",
      list(df = zv(1), gvif = zv(1), gvif_per_df = zv(1)),
      why = "The centred columns of arm, area and fsm are orthogonal."
    ),
    zoo_rd(4, "The intercept, arm[tutoring], area[rural] and fsm are linearly independent."),
    zoo_finding(
      "design.scale_disparity", finding = "consistent", message = "similar",
      statistics = list(
        scaled_columns = zv(zn("fsm")), sd_largest = zv(zoo_sd(X[, 4])),
        sd_smallest = zv(zoo_sd(X[, 4])), sd_ratio = zv(1),
        condition_number = zv(zoo_condition(X))
      ),
      why = paste0("fsm is the only numeric column, with ", N / 2, " rows at 0.40 and ", N / 2,
                   " at 0.20, and zoo_condition() gives the condition number.")
    ),
    if (budget == 0) {
      zoo_finding(
        "identifiability.df_budget", list(factor = "school"), "consequential", "no_budget",
        list(levels = zv(J, school_class), budget = zv(0, school_class),
             consuming_terms = zv(zn("(Intercept)", "arm", "area", "fsm"))),
        why = paste0("J - k + r = ", J, " - 4 + 0, and each of the four terms, constant ",
                     "within schools, lowers the budget by 1.")
      )
    } else {
      zoo_db("school", school_class, J, budget, c("(Intercept)", "arm", "area", "fsm"),
             paste0("J - k + r = ", J, " - 4 + 0, each term lowering the budget by 1."))
    },
    if (budget == 0) {
      # P takes the indicators of the schools to 0, so every level ratio of the
      # school variance is 0 up to rounding, and C holds the residual alone.
      stopifnot(identical(gram$vanishing, 1L), gram$parameters == 2)
      zoo_finding(
        "identifiability.gram_rank", finding = "consequential", message = "not_identified",
        statistics = list(
          parameters = zv(2), rank = zv(1), verdict = zv("not_identified"),
          vanishing_parameters = zv(zn("1 | school: var((Intercept))")),
          confounded_parameters = zv(zn()), smallest_eigenvalue = zv(gram$smallest_eigenvalue)
        ),
        why = paste0("The fixed columns span the school indicators, so the school variance ",
                     "vanishes and C holds the residual alone, whose eigenvalue is 1.")
      )
    } else {
      zoo_gr(list(X = X, terms = list(list(factor = school, columns = ones))),
             "The school and residual variances, as zoo_gram() computes them.")
    },
    zoo_ld1("school", school_class, J),
    zoo_rc1("school", school_class, J, paste0(n, " rows in each level.")),
    zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
    zoo_lu("area", half_class),
    zoo_lu("arm", half_class),
    zoo_lu("pupil", "person"),
    zoo_lu("school", school_class),
    zoo_sr(N),
    zoo_cs("school", school_class, rep(n, J)),
    status_between("area", FALSE, "area is constant within every school, and it is categorical."),
    status_between("arm", FALSE, "arm is constant within every school, and it is categorical."),
    status_between("fsm", TRUE, paste0("fsm is constant within every school, so SSW = 0, ",
                                       "icc = MSB / MSB = 1 and within_share = 0."))
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z21_parameters <- function(schools, pupils) {
  list(schools = schools, pupils = pupils, covariates = TRUE, sd_school = "0.4",
       sd_residual = "1", effect = "0.3", digits = 2)
}

zoo_Z21_planned <- list(zoo_planned(
  "identifiability.few_levels", "T0", c("L7-02", "L1-08"), "0.2", "M4",
  "Nothing beyond vocabulary 0.1.",
  paste("Few levels of a grouping factor or few assigned units for the inference planned,",
        "with the design degrees of freedom that M5 reports in Stream A.")
))

zoo_define(
  id = "Z21", name = "few-clusters", title = "Few clusters",
  role = "fixture", matched = "Z21N", negative_of = character(0), domain = "education",
  catalogue = c("L7-02", "L1-08", "L1-10"),
  planted = paste("4 schools were randomised, 2 to each arm, and the formula adjusts for two",
                  "school-level covariates, which with the intercept and the arm use up the 4",
                  "schools."),
  seed = 202611210, parameters = zoo_Z21_parameters(4, 15), generate = zoo_Z21,
  declaration = function(p) zoo_Z21_declaration(p, "Z21 Few clusters"),
  formula = zoo_Z21_formula,
  run = zoo_access("Z21", "T0"), expected = zoo_Z21_expected,
  signal = list(
    zoo_signal("assignment.design_df", list(column = "arm", unit = "school"), "no_df"),
    zoo_signal("identifiability.df_budget", list(factor = "school"), "no_budget"),
    zoo_signal("identifiability.gram_rank", zoo_object(), "not_identified")
  ),
  planned = zoo_Z21_planned
)

zoo_define(
  id = "Z21N", name = "many-clusters", title = "Many clusters",
  role = "negative", matched = "Z21", negative_of = "Z21", domain = "education",
  catalogue = c("L7-02", "L1-08", "L1-10"),
  planted = paste("40 schools of 6 pupils with the same formula, which leaves 36 degrees of",
                  "freedom between schools."),
  seed = 202611210, parameters = zoo_Z21_parameters(40, 6), generate = zoo_Z21,
  declaration = function(p) zoo_Z21_declaration(p, "Z21N Many clusters"),
  formula = zoo_Z21_formula,
  run = zoo_access("Z21N", "T0"), expected = zoo_Z21_expected,
  signal = list()
)
