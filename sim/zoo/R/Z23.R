# Z23 Post-assignment covariate adjusted for, and its matched negative Z23N.
# Pupils were randomised to tutoring within schools, attendance was measured
# after randomisation and the tutoring arm raised it by 18 points. In Z23,
# the formula adjusts the effect of the arm, a total effect, for attendance,
# and registry 0.1.0 shows the symptom through design.collinearity:
# attendance carries most of the arm, so both have a variance inflation
# factor near 8. In Z23N, the formula adjusts for the baseline score only.
# Both read the same data, and the check of adjusted roles is planned.

# The data: schools S1 onwards with n pupils each, P01 onwards in row order,
# the first n/2 pupils of each school in the arm control and the others in
# tutoring, pre with the digits pre_digits, attendance and y. attendance is
# attendance_control + attendance_step (m - 1) for the m-th control pupil of
# a school and the same plus attendance_shift for the m-th tutoring pupil, so
# every school holds the same values. Draws, in this order: pre from
# N(pre_mean, pre_sd) in row order, on its stored grid, the school effects
# and the residuals in row order. y is the school effect plus the residual,
# rounded to the stored grid. Drawn properties, checked on the stored pre:
# its standard deviation lies in [5, 20], it takes at least two values
# within every school, and R^2, the squared multiple correlation of pre on
# the arm and attendance over all rows, is at most 0.09, else every pre is
# drawn again.
zoo_Z23 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z23_design(p)
    N <- length(design$school)
    draw_pre <- function() {
      zoo_round(stats::rnorm(N, as.numeric(p$pre_mean), as.numeric(p$pre_sd)), p$pre_digits)
    }
    pre <- draw_pre()
    school_effect <- stats::rnorm(p$schools, 0, as.numeric(p$sd_school))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    data <- data.frame(
      school = zoo_label("S", design$school, p$schools),
      pupil = zoo_label("P", seq_len(N)),
      arm = ifelse(design$tutoring, "tutoring", "control"),
      pre = pre,
      attendance = design$attendance,
      y = zoo_round(school_effect[design$school] + residual, p$digits)
    )
    zoo_check(
      data,
      list(
        spread = function(d) {
          s <- zoo_sd(d$pre)
          if (s < 5 || s > 20) "all" else character(0)
        },
        varies = function(d) {
          constant <- tapply(d$pre, design$school, function(v) all(v == v[1L]))
          if (any(constant)) "all" else character(0)
        },
        independent = function(d) {
          if (zoo_Z23_r2(d$pre, design) > 0.09) "all" else character(0)
        }
      ),
      function(d, unit) {
        d$pre <- draw_pre()
        d
      },
      checks
    )
  })
}

# The rows: school, whether the pupil is in tutoring and attendance, from the
# parameters alone. attendance is computed in integer hundredths, so that it
# lies on the stored grid.
zoo_Z23_design <- function(p) {
  n <- p$pupils
  stopifnot(n %% 2L == 0L)
  half <- n / 2
  m <- rep(seq_len(n), times = p$schools)
  tutoring <- m > half
  position <- ifelse(tutoring, m - half, m)
  hundredths <- round(100 * as.numeric(p$attendance_control)) +
    round(100 * as.numeric(p$attendance_step)) * (position - 1) +
    ifelse(tutoring, round(100 * as.numeric(p$attendance_shift)), 0)
  list(school = rep(seq_len(p$schools), each = n), tutoring = tutoring,
       attendance = hundredths / 100)
}

# The squared multiple correlation of pre on the arm and attendance.
zoo_Z23_r2 <- function(pre, design) {
  X <- cbind(1, as.numeric(design$tutoring), design$attendance)
  residual <- qr.resid(qr(X), pre)
  1 - sum(residual^2) / sum((pre - sum(pre) / length(pre))^2)
}

zoo_Z23_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("multisite"),
    table = list(fields = list(
      list(name = "school", type = "string"),
      list(name = "pupil", type = "string"),
      list(name = "arm", type = "string", categories = zn("control", "tutoring")),
      list(name = "pre", type = "number"),
      list(name = "attendance", type = "number"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "school", columns = zn("school"), role = "site"),
      list(name = "pupil", columns = zn("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = zn("pupil")),
    assignment = list(list(column = "arm", unit = "pupil", randomised = TRUE,
                           level = "between_unit", blocks = zn("school"))),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      arm = list(role = "assigned"),
      pre = list(role = "baseline_covariate"),
      attendance = list(role = "post_assignment_covariate")
    ),
    estimands = list(list(id = "ITT", term = "arm", kind = "total_effect"))
  )
}

# The expected findings. The counts follow from the parameters, and each
# pupil is one member of the disclosure unit with one row, so the assignment
# checks, which need a level of the assigned unit with two rows, yield no
# finding. The reals of attendance follow from the design, and those of pre
# are computed from the stored pre with the helpers of zoo.R, within the
# bounds that the drawn properties guarantee.
zoo_Z23_expected <- function(p, data) {
  design <- zoo_Z23_design(p)
  J <- p$schools
  n <- p$pupils
  N <- J * n
  stopifnot(J >= 3, n >= 4)
  adjusted <- p$adjust_attendance
  pre <- data$pre
  tutoring <- as.numeric(design$tutoring)
  attendance <- design$attendance
  r2 <- zoo_Z23_r2(pre, design)
  stopifnot(r2 <= 0.09, all(data$attendance == attendance))
  NP <- zoo_count_class(n)
  P <- "person"
  terms <- if (adjusted) c("arm", "pre", "attendance") else c("arm", "pre")
  main <- cbind(arm = tutoring, pre = pre, attendance = attendance)[, terms, drop = FALSE]
  X <- cbind(1, main)
  gvif <- lapply(stats::setNames(terms, terms), function(term) zoo_gvif(main, term))
  # Over the rows, attendance has within-arm variance s^2 = step^2 (h^2 - 1)/12
  # with h = n/2 values per arm and a difference shift between the arms, so
  # the GVIF of arm given attendance alone is 1 + shift^2/(4 s^2), 278/35
  # for the stored parameters. pre lowers the shares that each leaves
  # unexplained by at most the checked R^2, so both GVIFs lie in [278/35,
  # (278/35)/0.91]. The GVIF of pre is 1/(1 - R^2), in [1, 1/0.91].
  h <- n / 2
  step <- as.numeric(p$attendance_step)
  shift <- as.numeric(p$attendance_shift)
  floor_gvif <- 1 + shift^2 / (4 * step^2 * (h^2 - 1) / 12)
  collinearity <- function(term) {
    value <- gvif[[term]]
    if (term == "pre") {
      stopifnot(value$gvif >= 1 - 1e-12, value$gvif <= 1 / 0.91 + 1e-12)
      return(zoo_finding(
        "design.collinearity", list(term = term), "consistent", "low",
        list(df = zv(1), gvif = zv(value$gvif), gvif_per_df = zv(value$gvif_per_df)),
        why = paste("The GVIF of pre is 1/(1 - R^2) for its squared multiple correlation with",
                    "the other terms, which the checked R^2 of at most 0.09 keeps in [1, 1.099].")
      ))
    }
    if (!adjusted) {
      return(zoo_finding(
        "design.collinearity", list(term = term), "consistent", "low",
        list(df = zv(1), gvif = zv(value$gvif), gvif_per_df = zv(value$gvif_per_df)),
        why = paste("With arm and pre alone, the GVIF is 1/(1 - r^2), which the checked R^2 of",
                    "at most 0.09 keeps in [1, 1.099].")
      ))
    }
    stopifnot(value$gvif >= floor_gvif - 1e-9, value$gvif <= floor_gvif / 0.91 + 1e-9)
    zoo_finding(
      "design.collinearity", list(term = term), "detectable_inconsequential", "moderate",
      list(df = zv(1), gvif = zv(value$gvif), gvif_per_df = zv(value$gvif_per_df)),
      why = paste("attendance carries the arm, which sets the GVIF of arm and of attendance to",
                  "278/35 without pre, and pre multiplies it by at most 1/0.91, so it lies in",
                  "[7.94, 8.73].")
    )
  }
  sd_pre <- zoo_sd(pre)
  stopifnot(sd_pre >= 5, sd_pre <= 20)
  scaled <- if (adjusted) zn("pre", "attendance") else zn("pre")
  sd_smallest <- if (adjusted) zoo_sd(attendance) else sd_pre
  gram <- zoo_gram(X, list(list(factor = design$school, columns = matrix(1, N, 1L))))
  stopifnot(length(gram$vanishing) == 0L)
  anova_pre <- zoo_anova(pre, design$school)
  within <- function(term, why, icc = za(), within_share = za()) {
    zoo_finding(
      "structure.within_between", list(factor = "school", term = term), "consistent", "status",
      list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
           informative_levels = zv(J, NP), status = zv("within"),
           slope_requested = zv(FALSE), icc = icc, within_share = within_share),
      why = why
    )
  }
  findings <- c(
    lapply(terms, collinearity),
    list(
      zoo_rd(length(terms) + 1L, paste0("The columns (Intercept), ",
                                        paste(c("arm[tutoring]", terms[-1L]), collapse = ", "),
                                        " are linearly independent.")),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(scaled_columns = zv(scaled), sd_largest = zv(sd_pre),
                          sd_smallest = zv(sd_smallest), sd_ratio = zv(sd_pre / sd_smallest),
                          condition_number = zv(zoo_condition(X))),
        why = if (adjusted) {
          paste("attendance has the sd sqrt(0.6672/71), about 0.0969, and pre one in [5, 20],",
                "so sd_ratio lies in [51.5, 206.4], below 1000.")
        } else {
          "pre is the only scaled column, so sd_ratio is 1."
        }
      ),
      zoo_db("school", NP, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - ", length(terms) + 1L, " + ", length(terms),
                    ", since every term varies within every school.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "identified",
        statistics = list(parameters = zv(2), rank = zv(2), verdict = zv("identified"),
                          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
                          smallest_eigenvalue = zv(gram$smallest_eigenvalue)),
        why = paste("The school and residual variances, with the drawn pre in X, as zoo_gram()",
                    "computes them.")
      ),
      zoo_ld1("school", NP, J),
      zoo_rc1("school", NP, J, paste0(n, " rows in each level.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("arm", NP),
      zoo_lu("pupil", P),
      zoo_lu("school", NP),
      zoo_sr(N),
      zoo_cs("school", NP, rep(n, J)),
      within("arm", "Every school holds pupils of both arms, and arm is categorical."),
      within("pre", paste("pre takes two values or more in every school by the drawn property,",
                          "and zoo_anova() computes icc and within_share."),
             zv(anova_pre$icc), zv(anova_pre$within_share))
    )
  )
  if (adjusted) {
    # Every school holds the same n values of attendance, so SSB = 0, and with
    # n0 = n, icc = -MSW/((n - 1) MSW) = -1/(n - 1) and within_share = 1.
    findings <- c(findings, list(within(
      "attendance",
      paste0("Every school holds the same ", n, " values, so SSB = 0 and icc = -1/", n - 1,
             " with n0 = ", n, ", and within_share = 1."),
      zv(-1 / (n - 1)), zv(1)
    )))
  }
  list(samples = list(table = zoo_sample(N), design = zoo_sample(N)), findings = findings)
}

zoo_Z23_parameters <- function(adjust_attendance) {
  list(schools = 6, pupils = 12, attendance_control = "0.60", attendance_step = "0.02",
       attendance_shift = "0.18", pre_mean = "50", pre_sd = "10", sd_school = "0.4",
       sd_residual = "1", digits = 2, pre_digits = 1, adjust_attendance = adjust_attendance)
}

zoo_Z23_csv <- list(digits = list(pre = 1L))

zoo_define(
  id = "Z23", name = "post-assignment-covariate", title = "Post-assignment covariate adjusted for",
  role = "fixture", matched = "Z23N", negative_of = character(0), domain = "education",
  catalogue = c("critic: declared roles", "L2-19"),
  planted = paste("The formula adjusts the total effect of the randomised arm for attendance, a",
                  "covariate measured after randomisation that the arm raised by 18 points."),
  seed = 202611230, parameters = zoo_Z23_parameters(TRUE), generate = zoo_Z23,
  declaration = function(p) zoo_Z23_declaration(p, "Z23 Post-assignment covariate adjusted for"),
  formula = function(p) "y ~ arm + pre + attendance + (1 | school)",
  run = zoo_access("Z23", "T0"), expected = zoo_Z23_expected,
  signal = list(
    zoo_signal("design.collinearity", list(term = "arm"), "moderate"),
    zoo_signal("design.collinearity", list(term = "attendance"), "moderate")
  ),
  planned = list(zoo_planned(
    "design.adjusted_roles", "T0", c("critic: declared roles", "L2-19"), "0.2", "M4",
    "Nothing beyond vocabulary 0.1.",
    paste("A post-assignment covariate or a mediator in the fixed part of a model for an",
          "estimand of kind total_effect.")
  )),
  csv = zoo_Z23_csv
)

zoo_define(
  id = "Z23N", name = "baseline-covariate-only", title = "Baseline covariate only",
  role = "negative", matched = "Z23", negative_of = "Z23", domain = "education",
  catalogue = c("critic: declared roles", "L2-19"),
  planted = paste("The formula adjusts the effect of the arm for the baseline score only and",
                  "leaves out attendance."),
  seed = 202611230, parameters = zoo_Z23_parameters(FALSE), generate = zoo_Z23,
  declaration = function(p) zoo_Z23_declaration(p, "Z23N Baseline covariate only"),
  formula = function(p) "y ~ arm + pre + (1 | school)",
  run = zoo_access("Z23N", "T0"), expected = zoo_Z23_expected,
  signal = list(),
  csv = zoo_Z23_csv
)
