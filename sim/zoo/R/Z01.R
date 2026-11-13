# Z01 Reused class labels, and its matched negative Z01N. Class labels '1' to
# 'K' recur in every school, are declared unique only within their school, and
# the formula uses class without school, so that the model merges the classes
# that share a label. In Z01N the labels are unique
# across the data. The file is the worked example that the other generator
# files follow: one generator shared by the fixture and its negative, the
# declaration, the formula and the expected findings as functions of the
# parameters, and the two definitions.

# The data: schools S01 to SJ, K classes in each and n pupils in each class,
# ordered by school, class and pupil. Draws, in this order: J school effects,
# J K class effects in school order and J K n residuals. y is their sum,
# rounded to the stored grid. No property is drawn, so checks has nothing to
# redraw.
zoo_Z01 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    K <- p$classes
    n <- p$pupils
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    class_effect <- stats::rnorm(J * K, 0, as.numeric(p$sd_class))
    residual <- stats::rnorm(J * K * n, 0, as.numeric(p$sd_residual))
    school <- rep(seq_len(J), each = K * n)
    class <- rep(seq_len(J * K), each = n)
    data <- data.frame(
      school = zoo_label("S", school, J),
      class = if (p$reuse) zoo_label("", (class - 1) %% K + 1, K) else zoo_label("C", class, J * K),
      pupil = zoo_label("P", seq_len(J * K * n)),
      y = zoo_round(school_effect[school] + class_effect[class] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z01_declaration <- function(p, title) {
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
      list(name = "class", columns = zn("class"), nested_in = "school",
           id_scope = if (p$reuse) "within_parent" else "global", role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "class", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the intercept and random
# intercepts of school and of the class labels, in the order of the formula.
zoo_Z01_gram <- function(p) {
  J <- p$schools
  K <- p$classes
  N <- J * K * p$pupils
  class <- rep(seq_len(J * K), each = p$pupils)
  ones <- matrix(1, N, 1L)
  list(X = ones, terms = list(
    list(factor = rep(seq_len(J), each = K * p$pupils), columns = ones),
    list(factor = if (p$reuse) (class - 1) %% K + 1 else class, columns = ones)
  ))
}

# The expected findings, from the parameters alone. Every pupil is one member
# of the disclosure unit, so a count of the levels of an item resolves by the
# number of pupils in its smallest level.
zoo_Z01_expected <- function(p, data) {
  J <- p$schools
  K <- p$classes
  n <- p$pupils
  stopifnot(J >= 2, K >= 2, n >= 1)
  N <- J * K * n
  labels <- if (p$reuse) K else J * K
  school_class <- zoo_count_class(K * n)
  class_class <- zoo_count_class(N / labels)
  pair_class <- zoo_count_class(n)
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("class", class_class, labels, labels - 1, "(Intercept)",
             paste0("J - k + r = ", labels, " - 1 + 0 for the ", labels, " labels of class.")),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 1 + 0.")),
      zoo_gr(zoo_Z01_gram(p), paste0(
        "The school, class and residual variances of a balanced layout with ", n,
        " rows in each of ", J * K, " cells, as zoo_gram() computes them."
      )),
      zoo_ld1("class", class_class, labels),
      zoo_ld1("school", school_class, J),
      zoo_rc1("class", class_class, labels, paste0(N / labels, " rows in each level.")),
      zoo_rc1("school", school_class, J, paste0(K * n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("class", class_class),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_sr(N),
      zoo_cs("class", class_class, rep(N / labels, labels)),
      zoo_cs("school", school_class, rep(K * n, J))
    )
  )
  pair <- list(first = "class", second = "school")
  if (p$reuse) {
    findings <- c(findings, list(
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Each label occurs in all ", J, " schools and each school holds ", K,
                     " labels, and both terms have the intercept.")
      ),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, pair_class), between_component_terms = zv(zn()),
             exact = zv(TRUE)),
        why = "Every label occurs in every school, and the intercept is the only fixed term."
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consequential", "merged_units",
        list(levels_first = zv(K, class_class), levels_second = zv(J, school_class),
             combinations = zv(J * K, pair_class), first_in_several = zv(K, class_class),
             second_in_several = zv(J, school_class), relation = zv("crossed"),
             declared = zv("nested_within_parent"), inner = zv(zn("class")),
             outer = zv(zn("school")), inner_in_several = zv(K, class_class),
             composite = zv(FALSE), inner_alone = zv(TRUE)),
        why = paste0("Labels 1 to ", K, " recur in all ", J,
                     " schools, are declared within_parent, and (1 | class) uses class ",
                     "without school.")
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "nested",
        list(partition = zv("first_finer"), shared_columns = zv(TRUE),
             finer = zv(zn("class")), coarser = zv(zn("school")),
             coarser_levels = zv(J, school_class), informative_levels = zv(J, school_class),
             rows = zv(N), informative_rows = zv(N)),
        why = paste0("Each class lies in one school, and each school holds ", K,
                     " classes, so every school and row informs the nesting.")
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(J * K, class_class), levels_second = zv(J, school_class),
             combinations = zv(J * K, pair_class), first_in_several = zv(0, class_class),
             second_in_several = zv(J, school_class),
             relation = zv("first_nested_in_second"), declared = zv("nested_global"),
             inner = zv(zn("class")), outer = zv(zn("school")),
             inner_in_several = zv(0, class_class), composite = zv(FALSE),
             inner_alone = zv(TRUE)),
        why = "The class labels are unique across schools, as the declaration states."
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z01_parameters <- function(reuse) {
  list(schools = 10, classes = 3, pupils = 8, reuse = reuse, sd_school = "0.5",
       sd_class = "0.4", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z01", name = "reused-class-labels", title = "Reused class labels across schools",
  role = "fixture", matched = "Z01N", negative_of = character(0), domain = "education",
  catalogue = c("L1-01", "L7-01", "L2-22"),
  planted = paste("Class labels 1 to 3 recur in every school, are declared unique only within",
                  "their school, and the formula uses class without school."),
  seed = 202611010, parameters = zoo_Z01_parameters(TRUE), generate = zoo_Z01,
  declaration = function(p) zoo_Z01_declaration(p, "Z01 Reused class labels across schools"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | class)",
  run = zoo_access("Z01", "T0"), expected = zoo_Z01_expected,
  signal = list(zoo_signal("structure.label_incidence", list(first = "class", second = "school"),
                           "merged_units"))
)

zoo_define(
  id = "Z01N", name = "unique-class-labels", title = "Class labels unique across schools",
  role = "negative", matched = "Z01", negative_of = "Z01", domain = "education",
  catalogue = c("L1-01", "L7-01", "L2-22"),
  planted = paste("The class labels C01 to C30 are unique across schools and declared so, so",
                  "(1 | class) merges no classes."),
  seed = 202611010, parameters = zoo_Z01_parameters(FALSE), generate = zoo_Z01,
  declaration = function(p) zoo_Z01_declaration(p, "Z01N Class labels unique across schools"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | class)",
  run = zoo_access("Z01N", "T0"), expected = zoo_Z01_expected,
  signal = list()
)
