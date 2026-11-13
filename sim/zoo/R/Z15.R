# Z15 Reference level emptied by listwise deletion, and its matched negative
# Z15N. In Z15, adherence was measured in the active arms only, so every
# placebo patient lacks it, the design sample loses the reference level of
# dose, and dose[high] then depends on the intercept and dose[low]. In Z15N,
# adherence is missing for one patient of every dose in every clinic.

# The data: clinics K1 to KJ, each with n patients of each dose, placebo, low
# and high, whose adherence takes the first n values of the parameter
# adherence in order. Patients are numbered P01 onwards in row order, and the
# rows are ordered by clinic, dose and adherence. With placebo_missing,
# adherence is missing for every placebo patient, and with top_missing, for
# the patient with the largest adherence at every dose. Draws, in this order:
# J clinic effects and the residuals in row order. y is the clinic effect
# plus the residual, rounded to the stored grid, and is never missing. No
# property is drawn.
zoo_Z15 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z15_design(p)
    J <- p$clinics
    clinic_effect <- stats::rnorm(J, 0, as.numeric(p$sd_clinic))
    residual <- stats::rnorm(length(design$clinic), 0, as.numeric(p$sd_residual))
    data <- data.frame(
      clinic = paste0("K", zoo_digits(design$clinic)),
      patient = zoo_label("P", seq_along(design$clinic)),
      dose = c("placebo", "low", "high")[design$dose],
      adherence = ifelse(design$missing, NA, design$adherence),
      y = zoo_round(clinic_effect[design$clinic] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: clinic, dose as 1, 2 or 3, adherence and whether it is missing.
zoo_Z15_design <- function(p) {
  n <- p$patients_per_dose
  values <- as.numeric(unlist(p$adherence))
  stopifnot(n >= 1, length(values) >= n)
  J <- p$clinics
  clinic <- rep(seq_len(J), each = 3L * n)
  dose <- rep(rep(1:3, each = n), times = J)
  position <- rep(seq_len(n), times = 3L * J)
  missing <- (p$placebo_missing & dose == 1L) | (p$top_missing & position == n)
  list(clinic = clinic, dose = dose, adherence = values[position], missing = missing)
}

zoo_Z15_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "clinic", type = "string"),
      list(name = "patient", type = "string"),
      list(name = "dose", type = "string", categories = zn("placebo", "low", "high")),
      list(name = "adherence", type = "number"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "clinic", columns = zn("clinic"), role = "site"),
      list(name = "patient", columns = zn("patient"), nested_in = "clinic", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "patient", key = zn("patient")),
    assignment = list(list(column = "dose", unit = "patient", randomised = TRUE,
                           level = "between_unit")),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      dose = list(role = "assigned"),
      adherence = list(role = "post_assignment_covariate")
    )
  )
}

# The fixed-effects columns (Intercept), dose[low], dose[high] and adherence
# over the design sample, and its clinics.
zoo_Z15_kept <- function(p) {
  design <- zoo_Z15_design(p)
  keep <- !design$missing
  X <- cbind("(Intercept)" = 1, "dose[low]" = as.numeric(design$dose == 2L),
             "dose[high]" = as.numeric(design$dose == 3L), adherence = design$adherence)
  list(X = X[keep, , drop = FALSE], clinic = design$clinic[keep])
}

zoo_Z15_gram <- function(p) {
  kept <- zoo_Z15_kept(p)
  list(X = kept$X, terms = list(list(factor = kept$clinic,
                                     columns = matrix(1, nrow(kept$X), 1L))))
}

# The expected findings, from the parameters alone. Every patient is one
# member of the disclosure unit and has one row, so the assignment checks,
# which need a level of the unit with two rows, yield no finding. The
# clinics and doses hold several patients each.
zoo_Z15_expected <- function(p, data) {
  J <- p$clinics
  n <- p$patients_per_dose
  stopifnot(J >= 2, n >= 3, xor(p$placebo_missing, p$top_missing))
  N <- 3L * J * n
  kept <- zoo_Z15_kept(p)
  X <- kept$X
  M <- nrow(X)
  per_clinic <- M / J
  NP <- zoo_count_class(n)
  adherence <- X[, "adherence"]
  sd <- zoo_sd(adherence)
  anova <- zoo_anova(adherence, kept$clinic)
  if (p$placebo_missing) {
    # Without placebo, dose[high] = 1 - dose[low], so the sequential rule
    # drops it, and dose keeps one column. low and high have the same values
    # of adherence, so dose[low] and adherence are uncorrelated.
    dose_columns <- "dose[low]"
    kept_columns <- c("(Intercept)", "dose[low]", "adherence")
  } else {
    dose_columns <- c("dose[low]", "dose[high]")
    kept_columns <- colnames(X)
  }
  main <- X[, c(dose_columns, "adherence"), drop = FALSE]
  gvif_dose <- zoo_gvif(main, dose_columns)
  gvif_adherence <- zoo_gvif(main, "adherence")
  stopifnot(abs(gvif_dose$gvif - 1) < 1e-12, abs(gvif_adherence$gvif - 1) < 1e-12)
  findings <- list(
    zoo_finding(
      "design.collinearity", list(term = "adherence"), "consistent", "low",
      list(df = zv(1), gvif = zv(gvif_adherence$gvif),
           gvif_per_df = zv(gvif_adherence$gvif_per_df)),
      why = paste0("Every dose in the design sample has the same values of adherence, so ",
                   "adherence is uncorrelated with the columns of dose and the GVIF is 1.")
    ),
    zoo_finding(
      "design.collinearity", list(term = "dose"), "consistent", "low",
      list(df = zv(length(dose_columns)), gvif = zv(gvif_dose$gvif),
           gvif_per_df = zv(gvif_dose$gvif_per_df)),
      why = paste0("dose keeps ", length(dose_columns),
                   if (length(dose_columns) > 1) " columns" else " column",
                   " in the design sample, uncorrelated with adherence.")
    ),
    zoo_finding(
      "design.scale_disparity", finding = "consistent", message = "similar",
      statistics = list(scaled_columns = zv(zn("adherence")), sd_largest = zv(sd),
                        sd_smallest = zv(sd), sd_ratio = zv(1),
                        condition_number = zv(zoo_condition(X[, kept_columns]))),
      why = paste0("adherence is the one scaled column, with ", M / length(unique(adherence)),
                   " rows of each of its values in the design sample.")
    ),
    zoo_db("clinic", NP, J, J - 1, "(Intercept)",
           paste0("J - k + r = ", J, " - ", length(kept_columns), " + ", length(kept_columns) - 1,
                  ", since dose and adherence vary within every clinic.")),
    zoo_gr(zoo_Z15_gram(p), paste0(
      "The clinic variance and the residual with ", per_clinic,
      " rows in each clinic, as zoo_gram() computes them."
    )),
    zoo_ld1("clinic", NP, J),
    zoo_rc1("clinic", NP, J, paste0(per_clinic, " rows in each level.")),
    zoo_kd("patient", N, paste0("The ", N, " patient labels are distinct.")),
    zoo_lu("clinic", NP),
    zoo_lu("dose", NP),
    zoo_lu("patient", "person"),
    zoo_cs("clinic", NP, rep(per_clinic, J)),
    zoo_finding(
      "structure.within_between", list(factor = "clinic", term = "adherence"), "consistent",
      "status",
      list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
           informative_levels = zv(J, NP), status = zv("within"),
           slope_requested = zv(FALSE), icc = zv(anova$icc),
           within_share = zv(anova$within_share)),
      why = paste0("Each clinic holds the same ", per_clinic, " values, so SSB is 0, icc is -1/(",
                   per_clinic, " - 1) and within_share is 1.")
    ),
    zoo_finding(
      "structure.within_between", list(factor = "clinic", term = "dose"), "consistent",
      "status",
      list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
           informative_levels = zv(J, NP), status = zv("within"),
           slope_requested = zv(FALSE), icc = za(), within_share = za()),
      why = "Every clinic has patients of each dose in the design sample."
    )
  )
  if (p$placebo_missing) {
    findings <- c(findings, list(
      zoo_finding(
        "design.rank_deficiency", finding = "consequential", message = "focal",
        statistics = list(columns = zv(4), kept = zv(3), dropped_columns = zv(zn("dose[high]")),
                          dropped_terms = zv(zn("dose")), empty_cells = zv(0),
                          focal_dropped = zv(TRUE)),
        why = paste0("Without placebo, dose[high] is the intercept minus dose[low], and with no ",
                     "estimand declared dose is focal.")
      ),
      zoo_finding(
        "sample.raw_vs_analysis", finding = "consequential", message = "reference_emptied",
        statistics = list(rows_raw = zv(N), rows_kept = zv(M), rows_dropped = zv(N - M),
                          incomplete_columns = zv(zn("adherence")),
                          emptied_factors = zv(zn("dose")), reference_emptied = zv(zn("dose")),
                          factors_losing_levels = zv(zn()), new_singletons = zv(zn())),
        why = paste0("The ", N - M, " placebo patients lack adherence, so placebo, the reference ",
                     "level of dose, has no row in the design sample.")
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_rd(4, "Every dose has rows in the design sample, so the four columns are independent."),
      zoo_finding(
        "sample.raw_vs_analysis", finding = "detectable_inconsequential",
        message = "rows_dropped",
        statistics = list(rows_raw = zv(N), rows_kept = zv(M), rows_dropped = zv(N - M),
                          incomplete_columns = zv(zn("adherence")), emptied_factors = zv(zn()),
                          reference_emptied = zv(zn()), factors_losing_levels = zv(zn()),
                          new_singletons = zv(zn())),
        why = paste0("One patient of each dose in each clinic lacks adherence, so ", N - M,
                     " rows drop and every level keeps rows.")
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(M)),
    findings = findings
  )
}

zoo_Z15_parameters <- function(placebo_missing) {
  list(clinics = 6, patients_per_dose = 4,
       adherence = zoo_array(c("0.6", "0.7", "0.8", "0.9")),
       placebo_missing = placebo_missing, top_missing = !placebo_missing, sd_clinic = "0.4",
       sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z15", name = "reference-level-emptied",
  title = "Reference level emptied by listwise deletion",
  role = "fixture", matched = "Z15N", negative_of = character(0), domain = "any",
  catalogue = c("L2-04", "L1-09"),
  planted = paste("Every placebo patient lacks adherence, so listwise deletion empties the",
                  "reference level of dose and dose[high] depends on the intercept and",
                  "dose[low]."),
  seed = 202611150, parameters = zoo_Z15_parameters(TRUE), generate = zoo_Z15,
  declaration = function(p) {
    zoo_Z15_declaration(p, "Z15 Reference level emptied by listwise deletion")
  },
  formula = function(p) "y ~ dose + adherence + (1 | clinic)",
  run = zoo_access("Z15", "T0"), expected = zoo_Z15_expected,
  signal = list(
    zoo_signal("design.rank_deficiency", list(), "focal"),
    zoo_signal("sample.raw_vs_analysis", list(), "reference_emptied")
  ),
  csv = list(digits = list(adherence = 1L))
)

zoo_define(
  id = "Z15N", name = "missing-elsewhere", title = "Adherence missing at every dose",
  role = "negative", matched = "Z15", negative_of = "Z15", domain = "any",
  catalogue = c("L2-04", "L1-09"),
  planted = paste("One patient of every dose in every clinic lacks adherence, so listwise",
                  "deletion keeps every level of dose."),
  seed = 202611150, parameters = zoo_Z15_parameters(FALSE), generate = zoo_Z15,
  declaration = function(p) zoo_Z15_declaration(p, "Z15N Adherence missing at every dose"),
  formula = function(p) "y ~ dose + adherence + (1 | clinic)",
  run = zoo_access("Z15N", "T0"), expected = zoo_Z15_expected,
  signal = list(),
  csv = list(digits = list(adherence = 1L))
)
