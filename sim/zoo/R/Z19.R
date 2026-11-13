# Z19 Sentinel codes and labelled values, and its matched negative Z19N. In
# Z19, a score exported from SPSS holds the sentinel -99 for pupils who were
# not tested, which the declaration lists as a labelled missing value, the
# group column holds labelled integer codes and the file has CR LF line
# endings. Read with the declaration, the sentinels are missing values, so 7
# rows leave the design sample. In Z19N, the same values are true missing
# values, written as empty fields, with no sentinel declared and LF line
# endings. Both give the same findings by design: the fixture tests that a
# declared sentinel is read as missing, and the check of undeclared sentinels
# is planned.

# The data: schools S1 onwards with n pupils each, P01 onwards in row order,
# group 1 for the first control pupils of each school and 2 for the others,
# pre with the digits pre_digits, missing in the rows sentinel_rows, and y.
# Draws, in this order: the school effects, pre from N(pre_mean, pre_sd) in
# row order, on its stored grid, and the residuals in row order. y is the
# school effect plus the residual, rounded to the stored grid, and does not
# depend on pre. Drawn properties, checked on the rows of the design sample,
# those where pre is not missing: the standard deviation of pre lies in [5,
# 20], the absolute correlation of group and pre is at most 0.5 and pre takes
# at least two values within every school, else every pre is drawn again.
zoo_Z19 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$schools
    n <- p$pupils
    N <- J * n
    school <- rep(seq_len(J), each = n)
    missing <- seq_len(N) %in% unlist(p$sentinel_rows)
    draw_pre <- function() {
      pre <- zoo_round(stats::rnorm(N, as.numeric(p$pre_mean), as.numeric(p$pre_sd)),
                       p$pre_digits)
      ifelse(missing, NA, pre)
    }
    school_effect <- stats::rnorm(J, 0, as.numeric(p$sd_school))
    pre <- draw_pre()
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    data <- data.frame(
      school = zoo_label("S", school, J),
      pupil = zoo_label("P", seq_len(N)),
      group = ifelse(rep(seq_len(n), times = J) <= p$control, 1L, 2L),
      pre = pre,
      y = zoo_round(school_effect[school] + residual, p$digits)
    )
    kept <- !missing
    zoo_check(
      data,
      list(
        spread = function(d) {
          s <- zoo_sd(d$pre[kept])
          if (s < 5 || s > 20) "all" else character(0)
        },
        correlation = function(d) {
          if (abs(stats::cor(d$group[kept], d$pre[kept])) > 0.5) "all" else character(0)
        },
        varies = function(d) {
          constant <- tapply(d$pre[kept], school[kept], function(v) all(v == v[1L]))
          if (any(constant)) "all" else character(0)
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

zoo_Z19_declaration <- function(p, title) {
  pre <- list(name = "pre", type = "number")
  if (nzchar(p$sentinel)) {
    pre$missingValues <- list(list(value = ""), list(value = p$sentinel, label = "not tested"))
  }
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "school", type = "string"),
      list(name = "pupil", type = "string"),
      list(name = "group", type = "integer",
           categories = list(list(value = 1, label = "control"),
                             list(value = 2, label = "tutoring"))),
      pre,
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
      pre = list(role = "baseline_covariate")
    )
  )
}

# The expected findings. The counts follow from the parameters: the rows of
# sentinel_rows leave the design sample, and the parameters keep both groups
# in every school. Each pupil is one member of the disclosure unit. The reals
# that pre fixes are computed from the stored pre of the design sample with
# the helpers of zoo.R, and the drawn properties bound them.
zoo_Z19_expected <- function(p, data) {
  J <- p$schools
  n <- p$pupils
  N <- J * n
  school <- rep(seq_len(J), each = n)
  group <- ifelse(rep(seq_len(n), times = J) <= p$control, 1L, 2L)
  kept <- !(seq_len(N) %in% unlist(p$sentinel_rows))
  M <- sum(kept)
  sizes <- as.vector(table(school[kept]))
  stopifnot(J >= 3, all(sizes >= 2), M < N,
            all(tapply(group[kept], school[kept], function(g) length(unique(g)) == 2L)))
  pre <- data$pre[kept]
  stopifnot(identical(is.na(data$pre), !kept))
  tutoring <- as.numeric(group[kept] == 2L)
  X <- cbind(1, tutoring, pre)
  gvif_group <- zoo_gvif(X[, -1L], 1L)
  gvif_pre <- zoo_gvif(X[, -1L], 2L)
  r2 <- stats::cor(tutoring, pre)^2
  stopifnot(r2 <= 0.25, abs(gvif_group$gvif - 1 / (1 - r2)) < 1e-9)
  sd <- zoo_sd(pre)
  stopifnot(sd >= 5, sd <= 20)
  anova <- zoo_anova(pre, school[kept])
  P <- "person"
  NP <- zoo_count_class(min(sizes))
  group_class <- zoo_count_class(min(table(group)))
  gram <- zoo_gram(X, list(list(factor = school[kept], columns = matrix(1, M, 1L))))
  stopifnot(length(gram$vanishing) == 0L)
  collinearity <- function(term, gvif) {
    zoo_finding(
      "design.collinearity", list(term = term), "consistent", "low",
      list(df = zv(1), gvif = zv(gvif$gvif), gvif_per_df = zv(gvif$gvif_per_df)),
      why = paste("With two terms of one column each, the GVIF is 1/(1 - r^2), and the checked",
                  "r^2 of at most 0.25 keeps it in [1, 4/3].")
    )
  }
  findings <- c(
    zoo_na3(),
    list(
      collinearity("group", gvif_group),
      collinearity("pre", gvif_pre),
      zoo_rd(3, "The columns (Intercept), group[2] and pre are linearly independent."),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(scaled_columns = zv(zn("pre")), sd_largest = zv(sd),
                          sd_smallest = zv(sd), sd_ratio = zv(1),
                          condition_number = zv(zoo_condition(X))),
        why = paste("pre is the only scaled column, and the sentinels are missing values, so no",
                    "-99 enters its standard deviation, which the check keeps in [5, 20].")
      ),
      zoo_db("school", NP, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 3 + 2, since group and pre vary within every ",
                    "school.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "identified",
        statistics = list(parameters = zv(2), rank = zv(2), verdict = zv("identified"),
                          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
                          smallest_eigenvalue = zv(gram$smallest_eigenvalue)),
        why = paste("The school and residual variances, with the drawn pre in X, as zoo_gram()",
                    "computes them from the design sample.")
      ),
      zoo_ld1("school", NP, J),
      zoo_rc1("school", NP, J, paste0("Every school keeps at least ", min(sizes),
                                      " rows in the design sample.")),
      zoo_kd("pupil", N, paste0("The ", N, " pupil labels are distinct.")),
      zoo_lu("group", group_class, "group holds integers, so it has no spellings."),
      zoo_lu("pupil", P),
      zoo_lu("school", NP),
      zoo_finding(
        "sample.raw_vs_analysis", finding = "detectable_inconsequential",
        message = "rows_dropped",
        statistics = list(rows_raw = zv(N), rows_kept = zv(M), rows_dropped = zv(N - M),
                          incomplete_columns = zv(zn("pre")), emptied_factors = zv(zn()),
                          reference_emptied = zv(zn()), factors_losing_levels = zv(zn()),
                          new_singletons = zv(zn())),
        why = paste0("The ", N - M, " values of pre that are missing leave the design sample, ",
                     "and every school keeps both groups.")
      ),
      zoo_cs("school", NP, sizes,
             why = paste0("The schools keep ", paste(sort(sizes, method = "radix"),
                                                     collapse = ", "), " rows.")),
      zoo_finding(
        "structure.within_between", list(factor = "school", term = "group"), "consistent",
        "status",
        list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
             informative_levels = zv(J, NP), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every school keeps pupils of both groups, and group is categorical."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "school", term = "pre"), "consistent",
        "status",
        list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
             informative_levels = zv(J, NP), status = zv("within"),
             slope_requested = zv(FALSE), icc = zv(anova$icc),
             within_share = zv(anova$within_share)),
        why = paste("pre takes two values or more in every school by the drawn property, and",
                    "zoo_anova() computes icc and within_share.")
      )
    )
  )
  list(samples = list(table = zoo_sample(N), design = zoo_sample(M)), findings = findings)
}

zoo_Z19_parameters <- function(eol, sentinel) {
  list(schools = 6, pupils = 10, control = 5, sentinel_rows = c(2, 9, 13, 18, 24, 37, 46),
       pre_mean = "50", pre_sd = "10", sd_school = "0.4", sd_residual = "1", digits = 2,
       pre_digits = 1, eol = eol, sentinel = sentinel)
}

zoo_Z19_csv <- function(p) {
  list(eol = if (p$eol == "CR LF") "\r\n" else "\n", digits = list(pre = p$pre_digits),
       missing = list(pre = p$sentinel))
}

zoo_Z19_planned <- list(zoo_planned(
  "labels.sentinel_codes", "T0", "critic: import artefacts", "0.2", "M4",
  paste("A declaration of the same data.csv that does not list -99 in the missingValues",
        "of pre, which a later milestone adds beside the stored one, since the stored",
        "declaration lists it and Z19N holds no sentinel, so that the check cannot fire on",
        "either directory as stored. Vocabulary 0.1 suffices."),
  paste("Numeric values such as -9, -99 or 999 that lie far from the others in a column",
        "without declared missing values.")
))

zoo_define(
  id = "Z19", name = "sentinel-codes", title = "Sentinel codes and labelled values",
  role = "fixture", matched = "Z19N", negative_of = character(0), domain = "any",
  catalogue = "critic: import artefacts",
  planted = paste("pre holds the sentinel -99, declared as a labelled missing value, for 7",
                  "pupils who were not tested, group holds labelled integer codes and the file",
                  "has CR LF line endings."),
  seed = 202611190, parameters = zoo_Z19_parameters("CR LF", "-99"), generate = zoo_Z19,
  declaration = function(p) zoo_Z19_declaration(p, "Z19 Sentinel codes and labelled values"),
  formula = function(p) "y ~ group + pre + (1 | school)",
  run = zoo_access("Z19", "T0"), expected = zoo_Z19_expected,
  signal = list(), planned = zoo_Z19_planned,
  csv = zoo_Z19_csv(zoo_Z19_parameters("CR LF", "-99"))
)

zoo_define(
  id = "Z19N", name = "true-missing-values", title = "True missing values without sentinels",
  role = "negative", matched = "Z19", negative_of = "Z19", domain = "any",
  catalogue = "critic: import artefacts",
  planted = paste("The 7 untested pupils have empty fields for pre, no sentinel is declared and",
                  "the file has LF line endings."),
  seed = 202611190, parameters = zoo_Z19_parameters("LF", ""), generate = zoo_Z19,
  declaration = function(p) {
    zoo_Z19_declaration(p, "Z19N True missing values without sentinels")
  },
  formula = function(p) "y ~ group + pre + (1 | school)",
  run = zoo_access("Z19N", "T0"), expected = zoo_Z19_expected,
  signal = list(),
  csv = zoo_Z19_csv(zoo_Z19_parameters("LF", ""))
)
