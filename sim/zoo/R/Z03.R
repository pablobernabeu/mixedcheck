# Z03 Teachers crossed with schools, and its matched negative Z03N, which is
# also the matched negative of Z31 (Z31.R). The labels T1 to TK denote the
# same K peripatetic teachers in every school, with the incidence of Z01. The
# declaration leaves the relation of school and teacher undeclared, and the
# table of Z03 holds no attribute of a school or a teacher, so that label
# incidence alone cannot tell this crossing from reuse and
# structure.id_scope_evidence reports that the data give no evidence. Z03N
# adds the school attribute sector and the teacher attribute teacher_years,
# each constant within its unit, so that the check finds evidence consistent
# with one teacher for each label.

# The data: schools S01 to SJ, teachers T1 to TK in each and n pupils with
# each teacher, ordered by school, teacher and pupil. With attributes
# 'constant' or 'reused', sector ('state' in the first half of the schools,
# 'independent' in the others) and teacher_years follow pupil. teacher_years
# is years[k] for teacher k with 'constant', and 2 + ((7 j + 3 k) mod 29) for
# teacher k of school j with 'reused', which differs between the schools for
# each label, since 7 j mod 29 takes distinct values for j = 1 to 29, and
# between the teachers of each school. Draws, in this order: J school
# effects, the teacher effects in label order (K, or J K in school order with
# 'reused', where each school has its own K teachers) and J K n residuals. y
# is their sum, rounded to the stored grid. No property is drawn.
zoo_Z03 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    K <- p$teachers
    n <- p$pupils
    N <- J * K * n
    reused <- identical(p$attributes, "reused")
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    teacher_effect <- stats::rnorm(if (reused) J * K else K, 0, as.numeric(p$sd_teacher))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    school <- rep(seq_len(J), each = K * n)
    teacher <- rep(rep(seq_len(K), each = n), times = J)
    unit <- if (reused) (school - 1) * K + teacher else teacher
    data <- data.frame(
      school = zoo_label("S", school, J),
      teacher = zoo_label("T", teacher, K),
      pupil = zoo_label("P", seq_len(N))
    )
    if (!identical(p$attributes, "none")) {
      data$sector <- ifelse(school <= J / 2, "state", "independent")
      data$teacher_years <- if (reused) {
        2 + (7 * school + 3 * teacher) %% 29
      } else {
        as.numeric(unclass(p$years))[teacher]
      }
    }
    data$y <- zoo_round(school_effect[school] + teacher_effect[unit] + residual, p$digits)
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z03_declaration <- function(p, title) {
  fields <- list(
    list(name = "school", type = "string"),
    list(name = "teacher", type = "string"),
    list(name = "pupil", type = "string")
  )
  variables <- list(y = list(role = "outcome", measurement = "continuous"))
  if (!identical(p$attributes, "none")) {
    fields <- c(fields, list(list(name = "sector", type = "string"),
                             list(name = "teacher_years", type = "integer")))
    variables <- c(variables, list(sector = list(role = "auxiliary"),
                                   teacher_years = list(role = "auxiliary")))
  }
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = c(fields, list(list(name = "y", type = "number")))),
    units = list(
      list(name = "school", columns = zn("school"), role = "cluster"),
      list(name = "teacher", columns = zn("teacher"), role = "other"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    variables = variables
  )
}

# The design of identifiability.gram_rank: the intercept and random
# intercepts of school and of the teacher labels, in the order of the formula.
zoo_Z03_gram <- function(p) {
  J <- p$schools
  K <- p$teachers
  n <- p$pupils
  ones <- matrix(1, J * K * n, 1L)
  list(X = ones, terms = list(
    list(factor = rep(seq_len(J), each = K * n), columns = ones),
    list(factor = rep(rep(seq_len(K), each = n), times = J), columns = ones)
  ))
}

# structure.id_scope_evidence for the pair of school and teacher, from the
# attributes of the parameters. The candidate attributes of a direction are
# the columns other than the response and the pair that are constant within
# the combinations of school and teacher but not within every label of the
# context column. pupil differs within every combination, so it is never a
# candidate. sector is constant within each school and differs between the
# halves of the schools, so it is a candidate with school as the labels
# column alone. teacher_years is constant within each combination, differs
# between the teachers of a school, so that it is a candidate with teacher
# as the labels column, and is a candidate with school as the labels column
# only when it differs between the schools for some label, as with 'reused'.
zoo_Z03_evidence <- function(p) {
  J <- p$schools
  K <- p$teachers
  school_class <- zoo_count_class(K * p$pupils)
  teacher_class <- zoo_count_class(J * p$pupils)
  pair <- list(first = "school", second = "teacher")
  if (identical(p$attributes, "none")) {
    # Neither direction has a candidate, so the first column, school, is the
    # labels column and the statistics of the attributes are absent.
    return(zoo_finding(
      "structure.id_scope_evidence", pair, "consistent", "no_attribute",
      list(labels_column = zv(zn("school")), context_column = zv(zn("teacher")),
           levels = zv(J, school_class), shared_labels = zv(J, school_class),
           attributes = zv(zn()), changing_labels = za(), changing_share = za(),
           changing_attribute = za(), tied = zv(FALSE)),
      status = list(assessability = list(value = "not_assessable", reason = "prerequisite_unmet",
                                         detail = "unit_attribute")),
      why = paste0("pupil differs within every combination and y is the response, so no ",
                   "column is a candidate in either direction, and school, the first column, ",
                   "is the labels column.")
    ))
  }
  if (identical(p$attributes, "constant")) {
    # With school as the labels column, sector is the only candidate and
    # changes within no school. With teacher as the labels column,
    # teacher_years is the only candidate and changes for no teacher label.
    # Both counts are 0, so the first column, school, is reported.
    return(zoo_finding(
      "structure.id_scope_evidence", pair, "consistent", "no_change",
      list(labels_column = zv(zn("school")), context_column = zv(zn("teacher")),
           levels = zv(J, school_class), shared_labels = zv(J, school_class),
           attributes = zv(zn("sector")), changing_labels = zv(0, school_class),
           changing_share = zr(0, J, school_class), changing_attribute = zv(zn("sector")),
           tied = zv(FALSE)),
      why = paste0("sector, the candidate with school as the labels column, changes for no ",
                   "school, and teacher_years, the candidate with teacher as the labels ",
                   "column, for no teacher, so school, the first column, is reported.")
    ))
  }
  # 'reused': with school as the labels column, sector and teacher_years are
  # candidates and the smallest count of changing labels, that of sector, is
  # 0. With teacher as the labels column, teacher_years is the only candidate
  # and changes for all K labels. The teacher direction is reported, since
  # its count is above 0 where the other is 0, and K/K reaches 0.5.
  zoo_finding(
    "structure.id_scope_evidence", pair, "detectable_inconsequential", "reuse_likely",
    list(labels_column = zv(zn("teacher")), context_column = zv(zn("school")),
         levels = zv(K, teacher_class), shared_labels = zv(K, teacher_class),
         attributes = zv(zn("teacher_years")), changing_labels = zv(K, teacher_class),
         changing_share = zr(K, K, teacher_class), changing_attribute = zv(zn("teacher_years")),
         tied = zv(FALSE)),
    why = paste0("teacher_years changes across the schools for all ", K, " teacher labels, ",
                 "while sector, a candidate with school as the labels column, changes for no ",
                 "school, so the teacher direction is reported.")
  )
}

# The expected findings, from the parameters alone. Every pupil is one member
# of the disclosure unit, so a count of the levels of an item resolves by the
# number of pupils in its smallest level.
zoo_Z03_expected <- function(p, data) {
  J <- p$schools
  K <- p$teachers
  n <- p$pupils
  stopifnot(J >= 2, K >= 2, n >= 2, J <= 29)
  N <- J * K * n
  school_class <- zoo_count_class(K * n)
  teacher_class <- zoo_count_class(J * n)
  pair_class <- zoo_count_class(n)
  pair <- list(first = "school", second = "teacher")
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("school", school_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 1 + 0.")),
      zoo_db("teacher", teacher_class, K, K - 1, "(Intercept)",
             paste0("J - k + r = ", K, " - 1 + 0 for the ", K, " teacher labels.")),
      zoo_gr(zoo_Z03_gram(p), paste0(
        "The school, teacher and residual variances of a balanced crossed layout with ", n,
        " rows in each of ", J * K, " cells, as zoo_gram() computes them."
      )),
      zoo_ld1("school", school_class, J),
      zoo_ld1("teacher", teacher_class, K),
      zoo_rc1("school", school_class, J, paste0(K * n, " rows in each level.")),
      zoo_rc1("teacher", teacher_class, K, paste0(J * n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("pupil", "person"),
      zoo_lu("school", school_class),
      zoo_lu("teacher", teacher_class),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Each school holds all ", K, " teacher labels and each label occurs in all ",
                     J, " schools, and both terms have the intercept.")
      ),
      zoo_cs("school", school_class, rep(K * n, J)),
      zoo_cs("teacher", teacher_class, rep(J * n, K)),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, pair_class), between_component_terms = zv(zn()),
             exact = zv(TRUE)),
        why = paste("Every teacher label occurs in every school, and the intercept is the only",
                    "fixed term.")
      ),
      zoo_Z03_evidence(p),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(J, school_class), levels_second = zv(K, teacher_class),
             combinations = zv(J * K, pair_class), first_in_several = zv(J, school_class),
             second_in_several = zv(K, teacher_class), relation = zv("crossed"),
             declared = zv("none"), inner = zv(zn()), outer = zv(zn()),
             inner_in_several = za(), composite = zv(FALSE), inner_alone = zv(FALSE)),
        why = paste0("All ", J * K, " combinations occur, no unit names the other in nested_in ",
                     "and no crossing is declared.")
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z03_parameters <- function(attributes) {
  p <- list(schools = 10, teachers = 3, pupils = 8, attributes = attributes)
  if (identical(attributes, "constant")) {
    p$years <- zoo_array(c(4, 11, 23))
  }
  c(p, list(sd_school = "0.5", sd_teacher = "0.4", sd_residual = "1", digits = 2))
}

zoo_define(
  id = "Z03", name = "crossed-teachers", title = "Teachers crossed with schools",
  role = "fixture", matched = "Z03N", negative_of = character(0), domain = "education",
  catalogue = c("L1-01", "L7-01"),
  planted = paste("The labels T1 to T3 denote the same three teachers in every school, the",
                  "relation of school and teacher is undeclared, and no attribute of a school or",
                  "a teacher can tell this crossing from reuse."),
  seed = 202611030, parameters = zoo_Z03_parameters("none"), generate = zoo_Z03,
  declaration = function(p) zoo_Z03_declaration(p, "Z03 Teachers crossed with schools"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | teacher)",
  run = zoo_access("Z03", "T0"), expected = zoo_Z03_expected,
  signal = list(zoo_signal("structure.id_scope_evidence",
                           list(first = "school", second = "teacher"), "no_attribute"))
)

zoo_define(
  id = "Z03N", name = "crossed-teachers-with-attributes",
  title = "Teachers crossed with schools, with constant attributes",
  role = "negative", matched = "Z03", negative_of = c("Z03", "Z31"), domain = "education",
  catalogue = c("L1-01", "L7-01"),
  planted = paste("The crossing of Z03 with the school attribute sector and the teacher",
                  "attribute teacher_years, each constant within its unit, which give evidence",
                  "consistent with one teacher for each label."),
  seed = 202611030, parameters = zoo_Z03_parameters("constant"), generate = zoo_Z03,
  declaration = function(p) {
    zoo_Z03_declaration(p, "Z03N Teachers crossed with schools, with constant attributes")
  },
  formula = function(p) "y ~ 1 + (1 | school) + (1 | teacher)",
  run = zoo_access("Z03N", "T0"), expected = zoo_Z03_expected,
  signal = list()
)
