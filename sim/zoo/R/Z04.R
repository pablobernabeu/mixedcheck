# Z04 One class per school, and its matched negative Z04N. Every school holds
# one class, so the partitions of school and class coincide and only the sum
# of their variances is identified. In Z04N the first schools hold two
# classes each, which separates the two variances.

# The layout of the rows, from the parameters alone: school j holds
# classes_per_school[j] classes, numbered across the data in school order,
# and its pupils_per_school pupils are split evenly between them, in order.
zoo_Z04_layout <- function(p) {
  J <- p$schools
  n <- p$pupils_per_school
  per <- as.numeric(unclass(p$classes_per_school))
  stopifnot(length(per) == J, all(n %% per == 0))
  school <- rep(seq_len(J), each = n)
  first <- cumsum(c(0, per))[seq_len(J)]
  class <- unlist(lapply(seq_len(J), function(j) {
    first[j] + rep(seq_len(per[j]), each = n / per[j])
  }))
  list(school = school, class = class, classes = sum(per), per = per)
}

# The data: school S01 to SJ, class C01 onwards in school order, pupil P001
# onwards and y, ordered by school, class and pupil. Draws, in this order: J
# school effects, the class effects in label order and the residuals in row
# order. y is their sum, rounded to the stored grid. No property is drawn.
zoo_Z04 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    L <- zoo_Z04_layout(p)
    J <- p$schools
    N <- length(L$school)
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    class_effect <- stats::rnorm(L$classes, 0, as.numeric(p$sd_class))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    data <- data.frame(
      school = zoo_label("S", L$school, J),
      class = zoo_label("C", L$class, L$classes),
      pupil = zoo_label("P", seq_len(N), max(N, 100)),
      y = zoo_round(school_effect[L$school] + class_effect[L$class] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z04_declaration <- function(p, title) {
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

# The design of identifiability.gram_rank: the intercept and random
# intercepts of school and class, in the order of the formula.
zoo_Z04_gram <- function(p) {
  L <- zoo_Z04_layout(p)
  ones <- matrix(1, length(L$school), 1L)
  list(X = ones, terms = list(
    list(factor = L$school, columns = ones),
    list(factor = L$class, columns = ones)
  ))
}

# The expected findings, from the parameters alone. Every pupil is one member
# of the disclosure unit, and every school and class holds several pupils,
# so the counts of their levels resolve as non-person counts.
zoo_Z04_expected <- function(p, data) {
  L <- zoo_Z04_layout(p)
  J <- p$schools
  n <- p$pupils_per_school
  N <- length(L$school)
  C <- L$classes
  stopifnot(J >= 2, n >= 2)
  class_sizes <- unlist(lapply(L$per, function(k) rep(n / k, k)))
  school_class <- zoo_count_class(n)
  class_class <- zoo_count_class(class_sizes)
  pair_class <- class_class
  split <- sum(L$per >= 2)
  pair <- list(first = "class", second = "school")
  gram <- if (split == 0) {
    # Identical indicator columns give identical bases, so the Gram matrix
    # has a null vector on the two variances, on which the residual has no
    # loading. zoo_gram() confirms it to rounding level, and the expectation
    # writes the interval that rounding allows.
    value <- zoo_gram(zoo_Z04_gram(p)$X, zoo_Z04_gram(p)$terms)$smallest_eigenvalue
    stopifnot(abs(value) <= 1e-12)
    zoo_finding(
      "identifiability.gram_rank", finding = "consequential", message = "not_identified",
      statistics = list(
        parameters = zv(3), rank = zv(2), verdict = zv("not_identified"),
        vanishing_parameters = zv(zn()),
        confounded_parameters = zv(zn("1 | school: var((Intercept))",
                                      "1 | class: var((Intercept))")),
        smallest_eigenvalue = zi("-1e-12", "1e-12")
      ),
      why = paste0("The school and class indicators are identical, so the Gram matrix has a ",
                   "null vector on the two variances, on which the residual has no loading.")
    )
  } else {
    zoo_gr(zoo_Z04_gram(p), paste0(
      "The ", split, " schools with two classes separate the class variance from the school ",
      "variance, as zoo_gram() computes."
    ))
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("class", class_class, C, C - 1, "(Intercept)",
             paste0("J - k + r = ", C, " - 1 + 0.")),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 1 + 0.")),
      gram,
      zoo_ld1("class", class_class, C),
      zoo_ld1("school", school_class, J),
      zoo_rc1("class", class_class, C,
              paste0("Every class holds ", min(class_sizes), " rows or more.")),
      zoo_rc1("school", school_class, J, paste0(n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("class", class_class),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_sr(N),
      if (split == 0) {
        zoo_finding(
          "structure.aliased_factors", pair, "consequential", "aliased",
          list(partition = zv("identical"), shared_columns = zv(TRUE), finer = zv(zn()),
               coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
               rows = zv(N), informative_rows = za()),
          why = "Each school holds one class, so the two factors divide the rows alike."
        )
      } else {
        zoo_finding(
          "structure.aliased_factors", pair, "consistent", "nested",
          list(partition = zv("first_finer"), shared_columns = zv(TRUE),
               finer = zv(zn("class")), coarser = zv(zn("school")),
               coarser_levels = zv(J, school_class), informative_levels = zv(split, school_class),
               rows = zv(N), informative_rows = zv(split * n)),
          why = paste0("Each class lies in one school, and ", split, " schools of ", n,
                       " rows hold two classes.")
        )
      },
      zoo_cs("class", class_class, class_sizes),
      zoo_cs("school", school_class, rep(n, J)),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(C, class_class), levels_second = zv(J, school_class),
             combinations = zv(C, pair_class), first_in_several = zv(0, class_class),
             second_in_several = zv(split, school_class),
             relation = zv(if (split == 0) "identical" else "first_nested_in_second"),
             declared = zv("nested_global"), inner = zv(zn("class")), outer = zv(zn("school")),
             inner_in_several = zv(0, class_class), composite = zv(FALSE),
             inner_alone = zv(TRUE)),
        why = paste0("Each class label occurs in one school, as the declaration states, and ",
                     split, " schools hold more than one class.")
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z04_parameters <- function(classes_per_school) {
  list(schools = 12, classes_per_school = zoo_array(classes_per_school), pupils_per_school = 10,
       sd_school = "0.5", sd_class = "0.4", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z04", name = "aliased-grouping", title = "One class per school",
  role = "fixture", matched = "Z04N", negative_of = character(0), domain = "education",
  catalogue = "L1-02",
  planted = paste("Every school holds one class, so the school and class partitions coincide",
                  "and only the sum of their variances is identified."),
  seed = 202611040, parameters = zoo_Z04_parameters(rep(1, 12)), generate = zoo_Z04,
  declaration = function(p) zoo_Z04_declaration(p, "Z04 One class per school"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | class)",
  run = zoo_access("Z04", "T0"), expected = zoo_Z04_expected,
  signal = list(
    zoo_signal("identifiability.gram_rank", zoo_object(), "not_identified"),
    zoo_signal("structure.aliased_factors", list(first = "class", second = "school"), "aliased")
  )
)

zoo_define(
  id = "Z04N", name = "nested-classes", title = "Classes nested in schools",
  role = "negative", matched = "Z04", negative_of = "Z04", domain = "education",
  catalogue = "L1-02",
  planted = paste("Schools S01 to S04 hold two classes of 5 pupils, which separates the class",
                  "variance from the school variance."),
  seed = 202611040, parameters = zoo_Z04_parameters(c(2, 2, 2, 2, rep(1, 8))),
  generate = zoo_Z04,
  declaration = function(p) zoo_Z04_declaration(p, "Z04N Classes nested in schools"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | class)",
  run = zoo_access("Z04N", "T0"), expected = zoo_Z04_expected,
  signal = list()
)
