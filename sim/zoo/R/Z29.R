# Z29 Slope whose size depends on the units of its covariate, and its matched
# negative Z29N. In Z29, dist is recorded in millimetres, so its standard
# deviation is about 2,301, above the value at which lme4 warns about the
# scales of the fixed-effects columns, and a by-subject slope with a small
# variance then looks near-singular by criteria that depend on the units.
# identifiability.gram_rank is scale-free and gives the same smallest
# eigenvalue in both units. In Z29N, dist is recorded in metres. A
# scale-free criterion for near-singular fits is a planned check of Stream A.

# The data: subjects s01 onwards with T trials each, ordered by subject and
# trial. The distance of subject s in trial t is ((t + s) mod T) + 1 metres,
# so that every subject has each of the distances 1 to T once, written in
# millimetres with unit 'mm' and in metres with unit 'm'. Draws, in this
# order: S subject intercepts, S subject slopes per metre and S T residuals.
# rt is mean_rt plus the subject intercept, plus slope and the subject slope
# times the distance in metres, plus the residual, rounded to the stored grid
# of one decimal, so that it does not depend on the unit. No property is
# drawn.
zoo_Z29 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    S <- p$subjects
    T <- p$trials
    design <- zoo_Z29_design(p)
    intercept <- stats::rnorm(S, 0, as.numeric(p$sd_subject))
    slope <- stats::rnorm(S, 0, as.numeric(p$sd_slope))
    residual <- stats::rnorm(S * T, 0, as.numeric(p$sd_residual))
    subject <- design$subject
    data <- data.frame(
      subject = zoo_label("s", subject, S),
      trial = design$trial,
      dist = design$metres * if (p$unit == "mm") 1000 else 1,
      rt = zoo_round(as.numeric(p$mean_rt) + intercept[subject] +
                       (as.numeric(p$slope) + slope[subject]) * design$metres + residual,
                     p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: subject, trial and the distance in metres.
zoo_Z29_design <- function(p) {
  stopifnot(p$unit %in% c("mm", "m"))
  S <- p$subjects
  T <- p$trials
  subject <- rep(seq_len(S), each = T)
  trial <- rep(seq_len(T), times = S)
  list(subject = subject, trial = trial, metres = (trial + subject) %% T + 1)
}

zoo_Z29_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "trial", type = "integer"),
      list(name = "dist", type = "integer"),
      list(name = "rt", type = "number")
    )),
    units = list(list(name = "subject", columns = zn("subject"), role = "participant")),
    observation = list(key = zn("subject", "trial")),
    variables = list(
      rt = list(role = "outcome", measurement = "positive_duration"),
      dist = list(role = "auxiliary")
    )
  )
}

# The fixed-effects columns (Intercept) and dist in the stored unit.
zoo_Z29_X <- function(p) {
  design <- zoo_Z29_design(p)
  cbind(1, design$metres * if (p$unit == "mm") 1000 else 1)
}

# The design of identifiability.gram_rank: the term 1 + dist | subject has
# the two fixed-effects columns.
zoo_Z29_gram <- function(p) {
  X <- zoo_Z29_X(p)
  list(X = X, terms = list(list(factor = zoo_Z29_design(p)$subject, columns = X)))
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit, and every trial holds every subject.
zoo_Z29_expected <- function(p, data) {
  S <- p$subjects
  T <- p$trials
  stopifnot(S >= 3, T >= 3)
  N <- S * T
  P <- "person"
  X <- zoo_Z29_X(p)
  design <- zoo_Z29_design(p)
  # S copies of the distances 1 to T, whose squared deviations sum to
  # S T (T^2 - 1)/12, 630 for 15 subjects and 8 trials, so the standard
  # deviation is sqrt(630/119) metres, about 2.3009, or 1000 times that in
  # millimetres, above the threshold high of 1000. The cosine between the
  # two scaled columns is sum(dist)/sqrt(N sum(dist^2)), 540/sqrt(120 * 3060),
  # whatever the unit, and the condition number is sqrt((1 + c)/(1 - c)).
  sd <- zoo_sd(X[, 2L])
  stopifnot(abs(sd - (if (p$unit == "mm") 1000 else 1) * sqrt(S * T * (T^2 - 1) / 12 / (N - 1))) <
              1e-9 * sd)
  cosine <- sum(design$metres) / sqrt(N * sum(design$metres^2))
  condition <- zoo_condition(X)
  stopifnot(abs(condition - sqrt((1 + cosine) / (1 - cosine))) < 1e-12)
  anova <- zoo_anova(X[, 2L], design$subject)
  disparate <- sd > 1000
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and dist are linearly independent."),
      zoo_finding(
        "design.scale_disparity",
        finding = if (disparate) "detectable_inconsequential" else "consistent",
        message = if (disparate) "disparate" else "similar",
        statistics = list(scaled_columns = zv(zn("dist")), sd_largest = zv(sd),
                          sd_smallest = zv(sd), sd_ratio = zv(1),
                          condition_number = zv(condition)),
        why = if (disparate) {
          paste0("dist in millimetres has the standard deviation 1000 sqrt(630/119), about ",
                 "2300.9, above the threshold high of 1000.")
        } else {
          "dist in metres has the standard deviation sqrt(630/119), about 2.3009."
        }
      ),
      zoo_db("subject", P, S, S - 1, "(Intercept)",
             paste0("J - k + r = ", S, " - 2 + 1, since dist varies within every subject.")),
      zoo_gr(zoo_Z29_gram(p), paste0(
        "The four parameters are separated, and zoo_gram() gives the same eigenvalue in both ",
        "units, since the bases do not depend on the units of the columns."
      )),
      zoo_finding(
        "identifiability.levels_vs_dimension",
        list(factor = "subject", term = "1 + dist | subject"), "consistent", "adequate",
        list(dimension = zv(2), levels = zv(S, P), informative_levels = zv(S, P),
             counterparts = zv(TRUE), bound = zv(S - 1, P)),
        why = paste0("[1, dist] has rank 2 within every subject, and the bound ", S - 1,
                     " is at least 2.")
      ),
      zoo_kd(c("subject", "trial"), N,
             paste0("Each of the ", N, " pairs of subject and trial has one row.")),
      zoo_lu("subject", P),
      zoo_lu("trial", zoo_count_class(S), "The trials are integers."),
      zoo_sr(N),
      zoo_cs("subject", P, rep(T, S)),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "dist"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(S, P),
             informative_levels = zv(S, P), status = zv("within"),
             slope_requested = zv(TRUE), icc = zv(anova$icc),
             within_share = zv(anova$within_share)),
        why = paste0("Every subject has the same distances, so SSB is 0, icc is -1/(", T,
                     " - 1) and within_share is 1.")
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z29_parameters <- function(unit) {
  list(subjects = 15, trials = 8, unit = unit, mean_rt = "600", sd_subject = "50",
       sd_slope = "3", slope = "10", sd_residual = "40", digits = 1)
}

zoo_Z29_planned <- list(zoo_planned(
  "convergence.scale_free_rank", "Stream A", c("L4-03", "L4-04"), NULL, "M3b in R and M5",
  "A fitted model.",
  paste("A criterion for near-singular fits that does not depend on the units of the",
        "covariates, which the convergence triage of M3b adds in R and Stream A in both",
        "languages.")
))

zoo_define(
  id = "Z29", name = "slope-scale-mm", title = "Slope of a covariate in millimetres",
  role = "fixture", matched = "Z29N", negative_of = character(0), domain = "any",
  catalogue = c("L4-03", "L4-04"),
  planted = paste("dist is recorded in millimetres, so its standard deviation is about 2,301",
                  "and a by-subject slope with a small variance looks near-singular by criteria",
                  "that depend on units."),
  seed = 202611290, parameters = zoo_Z29_parameters("mm"), generate = zoo_Z29,
  declaration = function(p) zoo_Z29_declaration(p, "Z29 Slope of a covariate in millimetres"),
  formula = function(p) "rt ~ dist + (1 + dist | subject)",
  run = zoo_access("Z29", "T0"), expected = zoo_Z29_expected,
  signal = list(zoo_signal("design.scale_disparity", list(), "disparate")),
  planned = zoo_Z29_planned,
  csv = list(digits = list(rt = 1L))
)

zoo_define(
  id = "Z29N", name = "slope-scale-m", title = "Slope of a covariate in metres",
  role = "negative", matched = "Z29", negative_of = "Z29", domain = "any",
  catalogue = c("L4-03", "L4-04"),
  planted = paste("dist is recorded in metres, so its standard deviation is about 2.3 and the",
                  "scales of the fixed-effects columns are similar."),
  seed = 202611290, parameters = zoo_Z29_parameters("m"), generate = zoo_Z29,
  declaration = function(p) zoo_Z29_declaration(p, "Z29N Slope of a covariate in metres"),
  formula = function(p) "rt ~ dist + (1 + dist | subject)",
  run = zoo_access("Z29N", "T0"), expected = zoo_Z29_expected,
  signal = list(),
  csv = list(digits = list(rt = 1L))
)
