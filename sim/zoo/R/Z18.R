# Z18 Composite identifiers that collide when joined, and its matched
# negative Z18N. The school and class labels collide when they are joined
# without escaping: school '1' with class '12' and school '11' with class '2'
# both give '112' joined without a separator, and school 'A:1' with class '2'
# and school 'A' with class '1:2' both give 'A:1:2' joined with ':'. The IR
# escapes ':' in the levels of school:class (ir.md), so the factor keeps its
# 8 levels. Two class labels, '1,2' and '"3"', the second with its quotation
# marks as part of the label, must be quoted in the CSV, so that the
# writer's quoting, the doubling of a quotation mark and both table readers
# meet them from the generator to audit(). In Z18N the labels cannot collide
# and need no quoting. Z18 tests that joined labels do not merge, so its
# findings differ from those of Z18N only in the counts of
# structure.label_incidence that its own labels set, and its signal is
# empty.

# The data: school, class, pupil P01 onwards and y, ordered by school and
# class in the order of the parameters and then by pupil. schools lists the
# school labels and classes the class labels of each school. Draws, in this
# order: the school effects, the class effects in the order of the
# parameters and the residuals in row order. y is their sum, rounded to the
# stored grid. No property is drawn.
zoo_Z18 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    schools <- as.character(unclass(p$schools))
    classes <- lapply(p$classes, function(x) as.character(unclass(x)))
    n <- p$pupils_per_class
    per <- lengths(classes)
    school_effect <- stats::rnorm(length(schools), 0, as.numeric(p$sd_school))
    class_effect <- stats::rnorm(sum(per), 0, as.numeric(p$sd_class))
    school <- rep(rep(seq_along(schools), per), each = n)
    class <- rep(seq_len(sum(per)), each = n)
    N <- length(class)
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    data <- data.frame(
      school = enc2utf8(schools[school]),
      class = enc2utf8(unlist(classes)[class]),
      pupil = zoo_label("P", seq_len(N)),
      y = zoo_round(school_effect[school] + class_effect[class] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z18_declaration <- function(p, title) {
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
      list(name = "class", columns = zn("class"), nested_in = "school", id_scope = "within_parent",
           role = "cluster"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "class", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the intercept and random
# intercepts of school and of school:class, whose levels are the pairs of
# the parameters, so that no two pairs merge.
zoo_Z18_gram <- function(p) {
  per <- lengths(p$classes)
  n <- p$pupils_per_class
  ones <- matrix(1, sum(per) * n, 1L)
  list(X = ones, terms = list(
    list(factor = rep(rep(seq_along(per), per), each = n), columns = ones),
    list(factor = rep(seq_len(sum(per)), each = n), columns = ones)
  ))
}

# The expected findings, from the parameters alone. The levels of
# school:class are the pairs of a school and one of its classes, which the
# IR keeps apart however their labels join. The class labels, compared by
# value, give the counts of structure.label_incidence: a label occurs in
# several schools when two schools list it. Every pupil is one member of
# the disclosure unit, and every level of every item holds several pupils.
zoo_Z18_expected <- function(p, data) {
  schools <- as.character(unclass(p$schools))
  classes <- lapply(p$classes, function(x) as.character(unclass(x)))
  n <- p$pupils_per_class
  per <- lengths(classes)
  J <- length(schools)
  K <- sum(per)
  N <- K * n
  stopifnot(J >= 2, n >= 2, all(per >= 2), !anyDuplicated(schools),
            !any(vapply(classes, anyDuplicated, 0L) > 0))
  labels <- unique(unlist(classes))
  schools_of <- vapply(labels, function(l) sum(vapply(classes, function(x) l %in% x, NA)), 0)
  shared <- sum(schools_of >= 2)
  label_members <- schools_of * n
  school_class <- zoo_count_class(per * n)
  cell_class <- zoo_count_class(n)
  class_class <- zoo_count_class(label_members)
  # The relation is crossed when every label occurs in every school, and
  # partially_crossed otherwise, since some label occurs in several schools
  # and every school holds several labels. school:class holds class and no
  # factor holds class alone, so composite is true and inner_alone false,
  # which keeps merged_units from firing for the labels shared by schools.
  crossed <- K == length(labels) * J
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 1 + 0.")),
      zoo_db("school:class", cell_class, K, K - 1, "(Intercept)",
             paste0("J - k + r = ", K, " - 1 + 0 for the ", K, " pairs, none merged.")),
      zoo_gr(zoo_Z18_gram(p), paste0(
        "The school, class and residual variances of ", J, " schools of ", per[1], " classes ",
        "of ", n, " pupils, as zoo_gram() computes them."
      )),
      zoo_ld1("school", school_class, J),
      zoo_ld1("school:class", cell_class, K),
      zoo_rc1("school", school_class, J, paste0(per[1] * n, " rows in each level.")),
      zoo_rc1("school:class", cell_class, K, paste0(n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("class", class_class, paste0("The labels are ASCII, so no two differ only in ",
                                          "their Unicode form, quoted or not.")),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", list(first = "school", second = "school:class"),
        "consistent", "nested",
        list(partition = zv("second_finer"), shared_columns = zv(TRUE),
             finer = zv(zn("school:class")), coarser = zv(zn("school")),
             coarser_levels = zv(J, school_class), informative_levels = zv(J, school_class),
             rows = zv(N), informative_rows = zv(N)),
        why = paste0("Each of the ", K, " levels of school:class lies in one school, and every ",
                     "school holds two.")
      ),
      zoo_cs("school", school_class, per * n),
      zoo_cs("school:class", cell_class, rep(n, K),
             why = paste0(K, " levels of ", n, " rows, none merged by the joined labels.")),
      zoo_finding(
        "structure.label_incidence", list(first = "class", second = "school"),
        "consistent", "relation",
        list(levels_first = zv(length(labels), class_class),
             levels_second = zv(J, school_class), combinations = zv(K, cell_class),
             first_in_several = zv(shared, class_class),
             second_in_several = zv(sum(per >= 2), school_class),
             relation = zv(if (crossed) "crossed" else "partially_crossed"),
             declared = zv("nested_within_parent"), inner = zv(zn("class")),
             outer = zv(zn("school")), inner_in_several = zv(shared, class_class),
             composite = zv(TRUE), inner_alone = zv(FALSE)),
        why = paste0(shared, " of the ", length(labels), " class labels occur in ",
                     zoo_range(schools_of[schools_of >= 2]), " schools each, and class ",
                     "appears only in school:class, which (1 | school/class) builds.")
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z18_parameters <- function(schools, classes) {
  list(schools = zoo_array(schools), classes = lapply(classes, zoo_array),
       pupils_per_class = 10, sd_school = "0.5", sd_class = "0.4", sd_residual = "1",
       digits = 2)
}

zoo_define(
  id = "Z18", name = "composite-id-collision",
  title = "Composite identifiers that collide when joined",
  role = "fixture", matched = "Z18N", negative_of = character(0), domain = "education",
  catalogue = "L2-22",
  planted = paste("School and class labels that collide when joined without escaping, such as",
                  "1 with 12 and 11 with 2, or A:1 with 2 and A with 1:2, and class labels that",
                  "the CSV must quote."),
  seed = 202611180,
  parameters = zoo_Z18_parameters(
    c("1", "11", "A", "A:1"),
    list(c("1", "12"), c("1", "2"), c("1:2", "1,2"), c("2", "\"3\""))
  ),
  generate = zoo_Z18,
  declaration = function(p) {
    zoo_Z18_declaration(p, "Z18 Composite identifiers that collide when joined")
  },
  formula = function(p) "y ~ 1 + (1 | school/class)",
  run = zoo_access("Z18", "T0"), expected = zoo_Z18_expected,
  signal = list()
)

zoo_define(
  id = "Z18N", name = "safe-composite-ids", title = "Composite identifiers that cannot collide",
  role = "negative", matched = "Z18", negative_of = "Z18", domain = "education",
  catalogue = "L2-22",
  planted = paste("Schools S1 to S4 each hold classes C1 and C2, labels that cannot collide",
                  "when joined and need no quoting."),
  seed = 202611180,
  parameters = zoo_Z18_parameters(paste0("S", 1:4), rep(list(c("C1", "C2")), 4)),
  generate = zoo_Z18,
  declaration = function(p) {
    zoo_Z18_declaration(p, "Z18N Composite identifiers that cannot collide")
  },
  formula = function(p) "y ~ 1 + (1 | school/class)",
  run = zoo_access("Z18N", "T0"), expected = zoo_Z18_expected,
  signal = list()
)
