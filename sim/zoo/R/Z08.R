# Z08 Classes randomised within schools with the randomisation level omitted,
# and its matched negative Z08N. Classes were randomised to tutoring or
# control within schools, and the formula of Z08 has a school intercept only,
# which ignores the dependence within classes. Z08N has the same data and the
# formula of the design analysis, y ~ arm + school + (1 | class), which models
# the classes and the blocking schools. Z09 (Z09.R) calls the generator with
# the arm of the first pupil of some classes switched, and Z08 is its matched
# negative.

# The data: school S1 to SJ, class C01 onwards in school order, pupil P001
# onwards, arm and y, ordered by school, class and pupil. Each school has C
# classes, tutoring_per_school of which take tutoring, chosen by a random permutation of its
# classes, and n pupils in each class. The first pupil, in table order, of
# each class listed in contaminated takes the other arm. Draws, in this
# order: J permutations, one for each school, which choose its tutoring
# classes and change no count or value of the expectations, since arm stays
# balanced within every school, then J school effects, J C class effects and
# the residuals in row order. y is the sum of the school effect, the class
# effect, effect times the indicator of tutoring and the residual, rounded to
# the stored grid. No property is drawn.
zoo_Z08 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    C <- p$classes_per_school
    tutored <- p$tutoring_per_school
    n <- p$pupils_per_class
    stopifnot(tutored >= 1, tutored < C)
    tutoring <- unlist(lapply(seq_len(J), function(j) {
      chosen <- sample.int(C)[seq_len(tutored)]
      seq_len(C) %in% chosen
    }))
    school_effect <- stats::rnorm(J, 0, sqrt(as.numeric(p$var_school)))
    class_effect <- stats::rnorm(J * C, 0, sqrt(as.numeric(p$var_class)))
    N <- J * C * n
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    school <- rep(seq_len(J), each = C * n)
    class <- rep(seq_len(J * C), each = n)
    treated <- tutoring[class]
    first <- (as.numeric(unclass(p$contaminated)) - 1) * n + 1
    treated[first] <- !treated[first]
    data <- data.frame(
      school = zoo_label("S", school, J),
      class = zoo_label("C", class, J * C),
      pupil = zoo_label("P", seq_len(N), max(N, 100)),
      arm = ifelse(treated, "tutoring", "control"),
      y = zoo_round(school_effect[school] + class_effect[class] +
                      as.numeric(p$effect) * treated + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z08_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("cluster_randomised"),
    table = list(fields = list(
      list(name = "school", type = "string"),
      list(name = "class", type = "string"),
      list(name = "pupil", type = "string"),
      list(name = "arm", type = "string", categories = zn("control", "tutoring")),
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
    assignment = list(list(column = "arm", unit = "class", randomised = TRUE,
                           level = "between_unit", blocks = zn("school"))),
    variables = list(y = list(role = "outcome", measurement = "continuous"),
                     arm = list(role = "assigned")),
    estimands = list(list(id = "ITT", term = "arm", kind = "total_effect"))
  )
}

# The design of identifiability.gram_rank. The arrangement of the arms is a
# draw, so the indicator of tutoring comes from the stored arm column. With
# the formula of Z08, X holds the intercept and arm and the random term is
# the school intercept. With that of Z08N, X adds the indicators of schools 2
# to J and the random term is the class intercept.
zoo_Z08_gram <- function(p, data, modelled) {
  J <- p$schools
  C <- p$classes_per_school
  n <- p$pupils_per_class
  N <- J * C * n
  school <- rep(seq_len(J), each = C * n)
  ones <- matrix(1, N, 1L)
  X <- cbind(ones, as.numeric(data$arm == "tutoring"))
  if (modelled) {
    X <- cbind(X, vapply(seq_len(J)[-1L], function(j) as.numeric(school == j), numeric(N)))
    return(list(X = X, terms = list(list(factor = rep(seq_len(J * C), each = n),
                                         columns = ones))))
  }
  list(X = X, terms = list(list(factor = school, columns = ones)))
}

# The expected findings, from the parameters, with the formula of Z08 or,
# with modelled true, of Z08N. Every pupil is one member of the disclosure
# unit, and every school and class holds several pupils, so the counts of
# their levels resolve as non-person counts. The data are read only for the
# arrangement of the arms, which zoo_gram() needs.
zoo_Z08_expected <- function(p, data, modelled = FALSE) {
  J <- p$schools
  C <- p$classes_per_school
  n <- p$pupils_per_class
  stopifnot(J >= 2, C >= 2, n >= 2)
  N <- J * C * n
  K <- J * C
  mixed <- length(unique(as.numeric(unclass(p$contaminated))))
  stopifnot(!modelled || mixed == 0)
  school_class <- zoo_count_class(C * n)
  class_class <- zoo_count_class(n)
  arm_class <- zoo_count_class(c(K * n / 2, K * n / 2))
  # design_df = J + r - k over the rows of the assignment, all N rows: the k
  # kept columns are the intercept and arm, with the indicators of schools 2
  # to J under the formula of Z08N, and r, their rank within the classes, is
  # 1 when arm varies within some class and 0 otherwise.
  k <- if (modelled) 2 + (J - 1) else 2
  r <- if (mixed > 0) 1 else 0
  assignment <- list(column = "arm", unit = "class")
  findings <- list(
    if (mixed > 0) {
      zoo_finding(
        "assignment.constant_within_unit", assignment, "consequential", "mixed",
        list(units = zv(K, class_class), mixed_units = zv(mixed, class_class),
             level_source = zv("declared")),
        why = paste0("The first pupil of ", mixed, " classes takes the other arm, so arm ",
                     "takes two values within those classes.")
      )
    } else {
      zoo_finding(
        "assignment.constant_within_unit", assignment, "consistent", "constant",
        list(units = zv(K, class_class), mixed_units = zv(0, class_class),
             level_source = zv("declared")),
        why = paste0("Every one of the ", K, " classes takes one arm for all its pupils.")
      )
    },
    if (modelled) {
      zoo_finding(
        "assignment.design_df", assignment, "consistent", "design_df",
        list(units = zv(K, class_class), design_df = zv(K + r - k, class_class),
             missing_blocks = zv(zn()), level_source = zv("declared")),
        why = paste0("J + r - k = ", K, " + ", r, " - ", k, ", with the intercept, arm and ",
                     J - 1, " school columns constant within classes.")
      )
    } else {
      zoo_finding(
        "assignment.design_df", assignment, "detectable_inconsequential", "blocks_missing",
        list(units = zv(K, class_class), design_df = zv(K + r - k, class_class),
             missing_blocks = zv(zn("school")), level_source = zv("declared")),
        why = paste0("J + r - k = ", K, " + ", r, " - ", k, ", and the declared block school ",
                     "is not a variable of the fixed part.")
      )
    },
    if (modelled) {
      zoo_finding(
        "assignment.unit_in_random_part", assignment, "consistent", "unit_present",
        list(units = zv(K, class_class), coverage = zv("present"), coarser_factors = zv(zn()),
             level_source = zv("declared")),
        why = "The class intercept divides the rows into the classes."
      )
    } else {
      zoo_finding(
        "assignment.unit_in_random_part", assignment, "consequential", "unit_missing",
        list(units = zv(K, class_class), coverage = zv("absent"),
             coarser_factors = zv(zn("school")), level_source = zv("declared")),
        why = "The only grouping factor, school, holds whole classes, and no factor matches them."
      )
    },
    zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
    zoo_lu("arm", arm_class),
    zoo_lu("pupil", "person"),
    zoo_lu("school", school_class),
    zoo_sr(N)
  )
  if (modelled) {
    gram <- zoo_Z08_gram(p, data, TRUE)
    findings <- c(findings, list(
      zoo_finding(
        "design.collinearity", list(term = "arm"), "consistent", "low",
        list(df = zv(1), gvif = zv(1), gvif_per_df = zv(1)),
        why = paste0("arm is balanced within every school, so it is uncorrelated with the ",
                     "school columns.")
      ),
      zoo_finding(
        "design.collinearity", list(term = "school"), "consistent", "low",
        list(df = zv(J - 1), gvif = zv(1), gvif_per_df = zv(1)),
        why = "The school columns are uncorrelated with arm, which is balanced within schools."
      ),
      zoo_rd(k, paste0("The intercept, arm and ", J - 1, " school columns.")),
      zoo_db("class", class_class, K, K - k, c("(Intercept)", "arm", "school"),
             paste0("J - k + r = ", K, " - ", k, " + 0, each term constant within classes.")),
      zoo_gr(gram, "The class and residual variances, as zoo_gram() computes them."),
      zoo_ld1("class", class_class, K),
      zoo_rc1("class", class_class, K, paste0(n, " rows in each level.")),
      zoo_lu("class", class_class),
      zoo_cs("class", class_class, rep(n, K)),
      zoo_finding(
        "structure.label_incidence", list(first = "class", second = "school"),
        "consistent", "relation",
        list(levels_first = zv(K, class_class), levels_second = zv(J, school_class),
             combinations = zv(K, class_class), first_in_several = zv(0, class_class),
             second_in_several = zv(J, school_class),
             relation = zv("first_nested_in_second"), declared = zv("nested_global"),
             inner = zv(zn("class")), outer = zv(zn("school")),
             inner_in_several = zv(0, class_class), composite = zv(FALSE),
             inner_alone = zv(TRUE)),
        why = paste0("school is the column of the declared parent of class, and each class ",
                     "lies in one school.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "class", term = "arm"),
        "consistent", "status",
        list(multi_row_levels = zv(K, class_class), varying_levels = zv(0, class_class),
             informative_levels = zv(0, class_class), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "arm is constant within every class, and it is categorical, so icc is absent."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "class", term = "school"),
        "consistent", "status",
        list(multi_row_levels = zv(K, class_class), varying_levels = zv(0, class_class),
             informative_levels = zv(0, class_class), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Each class lies in one school, and school is categorical, so icc is absent."
      )
    ))
  } else {
    gram <- zoo_Z08_gram(p, data, FALSE)
    findings <- c(findings, list(
      zoo_rd(2, "The intercept and arm are linearly independent."),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 2 + 1, since arm varies within every school.")),
      zoo_gr(gram, "The school and residual variances, as zoo_gram() computes them."),
      zoo_ld1("school", school_class, J),
      zoo_rc1("school", school_class, J, paste0(C * n, " rows in each level.")),
      zoo_cs("school", school_class, rep(C * n, J)),
      zoo_finding(
        "structure.within_between", list(factor = "school", term = "arm"),
        "consistent", "status",
        list(multi_row_levels = zv(J, school_class), varying_levels = zv(J, school_class),
             informative_levels = zv(J, school_class), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("Every school holds classes of both arms, and arm is categorical, so icc ",
                     "is absent.")
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z08_parameters <- function(contaminated) {
  list(schools = 4, classes_per_school = 6, tutoring_per_school = 3, pupils_per_class = 10,
       contaminated = zoo_array(contaminated), var_school = "0.2", var_class = "0.15",
       sd_residual = "1", effect = "0.3", digits = 2)
}

zoo_define(
  id = "Z08", name = "randomisation-level-omitted", title = "Classes randomised within schools",
  role = "fixture", matched = "Z08N", negative_of = "Z09", domain = "education",
  catalogue = "L7-03",
  planted = paste("Classes were randomised within schools, and the formula has a school",
                  "intercept only, which ignores the dependence within classes."),
  seed = 202611080, parameters = zoo_Z08_parameters(numeric(0)), generate = zoo_Z08,
  declaration = function(p) zoo_Z08_declaration(p, "Z08 Classes randomised within schools"),
  formula = function(p) "y ~ arm + (1 | school)",
  run = zoo_access("Z08", "T0"), expected = function(p, data) zoo_Z08_expected(p, data),
  signal = list(
    zoo_signal("assignment.design_df", list(column = "arm", unit = "class"), "blocks_missing"),
    zoo_signal("assignment.unit_in_random_part", list(column = "arm", unit = "class"),
               "unit_missing")
  )
)

zoo_define(
  id = "Z08N", name = "randomisation-level-modelled", title = "Randomisation level modelled",
  role = "negative", matched = "Z08", negative_of = "Z08", domain = "education",
  catalogue = "L7-03",
  planted = paste("The data of Z08 with the formula of the design analysis, which models the",
                  "randomised classes and the blocking schools."),
  seed = 202611080, parameters = zoo_Z08_parameters(numeric(0)), generate = zoo_Z08,
  declaration = function(p) zoo_Z08_declaration(p, "Z08N Randomisation level modelled"),
  formula = function(p) "y ~ arm + school + (1 | class)",
  run = zoo_access("Z08N", "T0"),
  expected = function(p, data) zoo_Z08_expected(p, data, modelled = TRUE),
  signal = list()
)
