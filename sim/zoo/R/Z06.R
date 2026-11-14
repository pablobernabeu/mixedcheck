# Z06 Fewer levels than the dimension of a random term, and its matched
# negative Z06N. In Z06, 3 schools carry a random term with an intercept and
# two slopes, so the number of levels equals the dimension of the term, and
# a covariance matrix estimated from 3 levels whose columns are also fixed
# effects has rank 2 at most. Z06N has 30 schools.

# The data: schools S01 to SJ with n pupils each, numbered P001 onwards in
# school order. Within a school, x1 is -1 for the first half of the pupils
# and 1 for the second, and x2 alternates -1 and 1, so that each of the four
# combinations of x1 and x2 holds n/4 pupils of every school. Draws, in this
# order: J school intercepts, J slopes of x1, J slopes of x2 and J n
# residuals. y is the school intercept plus the school's slopes times x1 and
# x2 plus the residual, rounded to the stored grid. No property is drawn.
zoo_Z06 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    n <- p$pupils
    intercept <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    slope1 <- stats::rnorm(J, 0, as.numeric(p$sd_slopes))
    slope2 <- stats::rnorm(J, 0, as.numeric(p$sd_slopes))
    residual <- stats::rnorm(J * n, 0, as.numeric(p$sd_residual))
    design <- zoo_Z06_design(p)
    school <- design$school
    data <- data.frame(
      school = zoo_label("S", school, J),
      pupil = zoo_label("P", seq_len(J * n)),
      x1 = design$x1,
      x2 = design$x2,
      y = zoo_round(intercept[school] + slope1[school] * design$x1 +
                      slope2[school] * design$x2 + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The school and the covariates of each row.
zoo_Z06_design <- function(p) {
  n <- p$pupils
  within <- seq_len(n)
  list(school = rep(seq_len(p$schools), each = n),
       x1 = rep(ifelse(within <= n / 2, -1, 1), p$schools),
       x2 = rep(ifelse(within %% 2 == 1, -1, 1), p$schools))
}

zoo_Z06_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "school", type = "string"),
      list(name = "pupil", type = "string"),
      list(name = "x1", type = "integer"),
      list(name = "x2", type = "integer"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "school", columns = zn("school"), role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      x1 = list(role = "baseline_covariate"),
      x2 = list(role = "baseline_covariate")
    )
  )
}

# The fixed-effects columns (Intercept), x1 and x2.
zoo_Z06_X <- function(p) {
  design <- zoo_Z06_design(p)
  X <- cbind(1, design$x1, design$x2)
  colnames(X) <- c("(Intercept)", "x1", "x2")
  X
}

# The design of identifiability.gram_rank: the term 1 + x1 + x2 | school has
# the three fixed-effects columns.
zoo_Z06_gram <- function(p) {
  X <- zoo_Z06_X(p)
  list(X = X, terms = list(list(factor = zoo_Z06_design(p)$school, columns = X)))
}

# The expected findings, from the parameters alone. Every pupil is one member
# of the disclosure unit, and each school holds n of them.
zoo_Z06_expected <- function(p, data) {
  J <- p$schools
  n <- p$pupils
  stopifnot(J >= 2, n >= 4, n %% 4 == 0)
  N <- J * n
  school_class <- zoo_count_class(n)
  design <- zoo_Z06_design(p)
  X <- zoo_Z06_X(p)
  term <- "1 + x1 + x2 | school"
  # x1 and x2 are centred and orthogonal, so their correlation is 0 and each
  # GVIF is 1. Both take only -1 and 1, so their standard deviations are
  # sqrt(N/(N - 1)), and the three columns of unit length are orthogonal, so
  # the condition number is 1.
  sd <- zoo_sd(design$x1)
  stopifnot(sum(design$x1) == 0, sum(design$x2) == 0, sum(design$x1 * design$x2) == 0,
            sd == zoo_sd(design$x2))
  gvif1 <- zoo_gvif(X[, -1L], "x1")
  gvif2 <- zoo_gvif(X[, -1L], "x2")
  # Each school holds n/2 values of -1 and of 1 in each column, so the school
  # means are 0, SSB is 0 and icc is -1/(n0 - 1) with n0 = n.
  anova1 <- zoo_anova(design$x1, design$school)
  anova2 <- zoo_anova(design$x2, design$school)
  within <- function(column, anova) {
    zoo_finding(
      "structure.within_between", list(factor = "school", term = column), "consistent",
      "status",
      list(multi_row_levels = zv(J, school_class), varying_levels = zv(J, school_class),
           informative_levels = zv(J, school_class), status = zv("within"),
           slope_requested = zv(TRUE), icc = zv(anova$icc),
           within_share = zv(anova$within_share)),
      why = paste0("Every school has the same mean of ", column, ", 0, so SSB is 0, icc is ",
                   "-1/(", n, " - 1) and within_share is 1.")
    )
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_finding(
        "design.collinearity", list(term = "x1"), "consistent", "low",
        list(df = zv(1), gvif = zv(gvif1$gvif), gvif_per_df = zv(gvif1$gvif_per_df)),
        why = "x1 and x2 are centred and orthogonal, so their correlation is 0 and the GVIF is 1."
      ),
      zoo_finding(
        "design.collinearity", list(term = "x2"), "consistent", "low",
        list(df = zv(1), gvif = zv(gvif2$gvif), gvif_per_df = zv(gvif2$gvif_per_df)),
        why = "x1 and x2 are centred and orthogonal, so their correlation is 0 and the GVIF is 1."
      ),
      zoo_rd(3, "The columns (Intercept), x1 and x2 are orthogonal."),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(scaled_columns = zv(zn("x1", "x2")), sd_largest = zv(sd),
                          sd_smallest = zv(sd), sd_ratio = zv(1),
                          condition_number = zv(zoo_condition(X))),
        why = paste0("x1 and x2 take -1 and 1 equally often, so both standard deviations are ",
                     "sqrt(", N, "/", N - 1, "), and the three scaled columns are orthogonal.")
      ),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 3 + 2, since x1 and x2 vary within every school.")),
      zoo_gr(zoo_Z06_gram(p), paste0(
        "Six covariance parameters and the residual, separated by the ", n,
        " rows of each school, as zoo_gram() computes them."
      )),
      if (J - 1 < 3) {
        zoo_finding(
          "identifiability.levels_vs_dimension", list(factor = "school", term = term),
          "consequential", "guaranteed",
          list(dimension = zv(3), levels = zv(J, school_class),
               informative_levels = zv(J, school_class), counterparts = zv(TRUE),
               bound = zv(J - 1, school_class)),
          why = paste0("The term's columns are fixed effects too, so the bound is J - 1 = ",
                       J - 1, ", below the dimension 3.")
        )
      } else {
        zoo_finding(
          "identifiability.levels_vs_dimension", list(factor = "school", term = term),
          "consistent", "adequate",
          list(dimension = zv(3), levels = zv(J, school_class),
               informative_levels = zv(J, school_class), counterparts = zv(TRUE),
               bound = zv(J - 1, school_class)),
          why = paste0("The bound J - 1 = ", J - 1, " reaches the dimension 3, and every ",
                       "school has rank 3 in [1, x1, x2].")
        )
      },
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_sr(N),
      zoo_cs("school", school_class, rep(n, J)),
      within("x1", anova1),
      within("x2", anova2)
    )
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z06_parameters <- function(schools, pupils) {
  list(schools = schools, pupils = pupils, sd_school = "0.5", sd_slopes = "0.2",
       sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z06", name = "levels-below-dimension",
  title = "Fewer levels than the dimension of a random term",
  role = "fixture", matched = "Z06N", negative_of = character(0), domain = "education",
  catalogue = "L1-07",
  planted = paste("Three schools carry a random term with an intercept and two slopes, so the",
                  "levels do not exceed the dimension of the term."),
  seed = 202611060, parameters = zoo_Z06_parameters(3, 20), generate = zoo_Z06,
  declaration = function(p) {
    zoo_Z06_declaration(p, "Z06 Fewer levels than the dimension of a random term")
  },
  formula = function(p) "y ~ x1 + x2 + (1 + x1 + x2 | school)",
  run = zoo_access("Z06", "T0"), expected = zoo_Z06_expected,
  signal = list(
    zoo_signal("identifiability.levels_vs_dimension",
               list(factor = "school", term = "1 + x1 + x2 | school"), "guaranteed")
  )
)

zoo_define(
  id = "Z06N", name = "levels-above-dimension",
  title = "More levels than the dimension of a random term",
  role = "negative", matched = "Z06", negative_of = "Z06", domain = "education",
  catalogue = "L1-07",
  planted = paste("Thirty schools carry the random term with an intercept and two slopes, well",
                  "above its dimension."),
  seed = 202611060, parameters = zoo_Z06_parameters(30, 4), generate = zoo_Z06,
  declaration = function(p) {
    zoo_Z06_declaration(p, "Z06N More levels than the dimension of a random term")
  },
  formula = function(p) "y ~ x1 + x2 + (1 + x1 + x2 | school)",
  run = zoo_access("Z06N", "T0"), expected = zoo_Z06_expected,
  signal = list()
)
