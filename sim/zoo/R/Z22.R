# Z22 Omitted intermediate level, and its matched negative Z22N. Pupils are
# nested in classes nested in schools, the class variance is 0.25, and the
# formula of Z22 omits class. No check of registry 0.1.0 reads a declared
# unit that the formula leaves out, so a check of omitted units is planned.
# Z22N has the same data and a formula with class.

# The data: school S1 to SJ, class C01 onwards in school order, pupil P001
# onwards and y, ordered by school, class and pupil. Draws, in this order: J
# school effects, J K class effects and the residuals in row order. y is
# their sum, rounded to the stored grid. No property is drawn.
zoo_Z22 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    K <- p$classes_per_school
    n <- p$pupils
    N <- J * K * n
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    class_effect <- stats::rnorm(J * K, 0, as.numeric(p$sd_class))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    school <- rep(seq_len(J), each = K * n)
    class <- rep(seq_len(J * K), each = n)
    data <- data.frame(
      school = zoo_label("S", school, J),
      class = zoo_label("C", class, J * K),
      pupil = zoo_label("P", seq_len(N), max(N, 100)),
      y = zoo_round(school_effect[school] + class_effect[class] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z22_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "school", type = "string"),
      list(name = "class", type = "string"),
      list(name = "pupil", type = "string"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "school", columns = zn("school"), role = "cluster"),
      list(name = "class", columns = zn("class"), nested_in = "school", id_scope = "global",
           role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "class", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The expected findings, from the parameters alone, with the formula of
# Z22, or of Z22N with modelled true. Every pupil is one member of the
# disclosure unit, and every school and class holds several pupils. Without
# class in the formula, no pair of grouping columns exists, and class, the
# declared unit between school and pupil, is no grouping column, so no
# structure check reads it.
zoo_Z22_expected <- function(p, data, modelled = FALSE) {
  J <- p$schools
  K <- p$classes_per_school
  n <- p$pupils
  N <- J * K * n
  stopifnot(J >= 2, K >= 2, n >= 2)
  school_class <- zoo_count_class(K * n)
  class_class <- zoo_count_class(n)
  school <- rep(seq_len(J), each = K * n)
  class <- rep(seq_len(J * K), each = n)
  ones <- matrix(1, N, 1L)
  terms <- list(list(factor = school, columns = ones))
  if (modelled) {
    terms <- c(terms, list(list(factor = class, columns = ones)))
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 1 + 0.")),
      zoo_gr(list(X = ones, terms = terms), paste0(
        if (modelled) "The school, class and residual variances" else
          "The school and residual variances",
        " of a balanced layout, as zoo_gram() computes them."
      )),
      zoo_ld1("school", school_class, J),
      zoo_rc1("school", school_class, J, paste0(K * n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_sr(N),
      zoo_cs("school", school_class, rep(K * n, J))
    )
  )
  if (modelled) {
    pair <- list(first = "class", second = "school")
    findings <- c(findings, list(
      zoo_db("class", class_class, J * K, J * K - 1, "(Intercept)",
             paste0("J - k + r = ", J * K, " - 1 + 0.")),
      zoo_ld1("class", class_class, J * K),
      zoo_rc1("class", class_class, J * K, paste0(n, " rows in each level.")),
      zoo_lu("class", class_class),
      zoo_cs("class", class_class, rep(n, J * K)),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "nested",
        list(partition = zv("first_finer"), shared_columns = zv(TRUE),
             finer = zv(zn("class")), coarser = zv(zn("school")),
             coarser_levels = zv(J, school_class), informative_levels = zv(J, school_class),
             rows = zv(N), informative_rows = zv(N)),
        why = paste0("Each class lies in one school, and every school holds ", K, " classes.")
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(J * K, class_class), levels_second = zv(J, school_class),
             combinations = zv(J * K, class_class), first_in_several = zv(0, class_class),
             second_in_several = zv(J, school_class),
             relation = zv("first_nested_in_second"), declared = zv("nested_global"),
             inner = zv(zn("class")), outer = zv(zn("school")),
             inner_in_several = zv(0, class_class), composite = zv(FALSE),
             inner_alone = zv(TRUE)),
        why = "Each class label occurs in one school, as the declaration states."
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z22_parameters <- function() {
  list(schools = 6, classes_per_school = 3, pupils = 8, sd_school = "0.4", sd_class = "0.5",
       sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z22", name = "omitted-intermediate-level", title = "Omitted intermediate level",
  role = "fixture", matched = "Z22N", negative_of = character(0), domain = "education",
  catalogue = "critic: omitted clustering",
  planted = paste("Pupils are nested in classes nested in schools, the class variance is 0.25,",
                  "and the formula omits class."),
  seed = 202611220, parameters = zoo_Z22_parameters(), generate = zoo_Z22,
  declaration = function(p) zoo_Z22_declaration(p, "Z22 Omitted intermediate level"),
  formula = function(p) "y ~ 1 + (1 | school)",
  run = zoo_access("Z22", "T0"), expected = function(p, data) zoo_Z22_expected(p, data),
  signal = list(),
  planned = list(zoo_planned(
    "structure.omitted_units", "T0", "critic: omitted clustering", "0.2", "M4",
    "Nothing beyond vocabulary 0.1.",
    paste("A declared unit between grouping factors of the formula that no random term",
          "uses.")
  ))
)

zoo_define(
  id = "Z22N", name = "intermediate-level-modelled", title = "Intermediate level modelled",
  role = "negative", matched = "Z22", negative_of = "Z22", domain = "education",
  catalogue = "critic: omitted clustering",
  planted = "The data of Z22 with a formula that has a random intercept for class.",
  seed = 202611220, parameters = zoo_Z22_parameters(), generate = zoo_Z22,
  declaration = function(p) zoo_Z22_declaration(p, "Z22N Intermediate level modelled"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | class)",
  run = zoo_access("Z22N", "T0"),
  expected = function(p, data) zoo_Z22_expected(p, data, modelled = TRUE),
  signal = list()
)
