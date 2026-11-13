# Z30 Multisite trial with single-arm sites, and its matched negative Z30N.
# In Z30, participants were randomised within 12 sites, but two sites
# enrolled the treatment arm only, so a site-varying treatment effect rests
# on the other 10 sites. Registry 0.1.0 reports the partial variation through
# structure.within_between, and a check of single-arm blocks is planned. In
# Z30N, every site has both arms.

# The data: sites S01 onwards with 2 n participants each, numbered P001
# onwards in site order. In each site, the first n participants are control
# and the last n treatment, except in the sites of single_arm_sites, where
# all 2 n are treatment. Draws, in this order: J site intercepts, J site
# slopes of treatment and the 2 J n residuals. y is the site intercept, plus
# effect and the site slope in rows of treatment, plus the residual, rounded
# to the stored grid. No property is drawn.
zoo_Z30 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    J <- p$sites
    design <- zoo_Z30_design(p)
    intercept <- stats::rnorm(J, 0, as.numeric(p$sd_site))
    slope <- stats::rnorm(J, 0, as.numeric(p$sd_site_slope))
    residual <- stats::rnorm(length(design$site), 0, as.numeric(p$sd_residual))
    site <- design$site
    data <- data.frame(
      site = zoo_label("S", site, J),
      participant = zoo_label("P", seq_along(site)),
      arm = ifelse(design$treatment, "treatment", "control"),
      y = zoo_round(intercept[site] + design$treatment * (as.numeric(p$effect) + slope[site]) +
                      residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: site and whether the participant is in the treatment arm.
zoo_Z30_design <- function(p) {
  n <- p$per_arm
  site <- rep(seq_len(p$sites), each = 2L * n)
  position <- rep(seq_len(2L * n), times = p$sites)
  list(site = site, treatment = position > n | site %in% unlist(p$single_arm_sites))
}

zoo_Z30_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("multisite"),
    table = list(fields = list(
      list(name = "site", type = "string"),
      list(name = "participant", type = "string"),
      list(name = "arm", type = "string", categories = zn("control", "treatment")),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "site", columns = zn("site"), role = "site"),
      list(name = "participant", columns = zn("participant"), nested_in = "site",
           id_scope = "global", role = "participant")
    ),
    observation = list(unit = "participant", key = zn("participant")),
    assignment = list(list(column = "arm", unit = "participant", randomised = TRUE,
                           level = "between_unit", blocks = zn("site"))),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      arm = list(role = "assigned")
    ),
    estimands = list(list(id = "ATE", term = "arm", kind = "total_effect"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# arm[treatment], and the term 1 + arm | site with the same columns.
zoo_Z30_gram <- function(p) {
  design <- zoo_Z30_design(p)
  X <- cbind(1, as.numeric(design$treatment))
  list(X = X, terms = list(list(factor = design$site, columns = X)))
}

# The expected findings, from the parameters alone. Every participant is one
# member of the disclosure unit and has one row, so the assignment checks,
# which need a level of the unit with two rows, yield no finding. Each site,
# each arm and each cell of site and pattern holds n participants or more.
zoo_Z30_expected <- function(p, data) {
  J <- p$sites
  n <- p$per_arm
  single <- length(unlist(p$single_arm_sites))
  stopifnot(J >= 3, n >= 2, single <= J - 2)
  N <- 2L * J * n
  NP <- zoo_count_class(n)
  both <- J - single
  term <- "1 + arm | site"
  findings <- list(
    zoo_rd(2, "The columns (Intercept) and arm[treatment] are linearly independent."),
    zoo_db("site", NP, J, J - 1, "(Intercept)",
           paste0("J - k + r = ", J, " - 2 + 1, since arm varies within ", both, " sites.")),
    zoo_gr(zoo_Z30_gram(p), paste0(
      "The ", both, " sites with both arms separate the four parameters, as zoo_gram() ",
      "computes them."
    )),
    zoo_finding(
      "identifiability.levels_vs_dimension", list(factor = "site", term = term),
      "consistent", "adequate",
      list(dimension = zv(2), levels = zv(J, NP), informative_levels = zv(both, NP),
           counterparts = zv(TRUE), bound = zv(J - 1, NP)),
      why = paste0("[1, arm[treatment]] has rank 2 in the ", both, " sites with both arms, ",
                   "and the bound ", J - 1, " is at least 2.")
    ),
    zoo_finding(
      "identifiability.residual_confounding", list(factor = "site", term = term),
      "consistent", "replicated",
      list(columns = zv(2), correlated = zv(TRUE), pattern_terms = zv(zn(term)),
           cells = zv(2 * both + single, NP), replicated_cells = zv(2 * both + single, NP),
           intercept_alone = zv(FALSE)),
      why = paste0("Two patterns of ", n, " rows in ", both, " sites",
                   if (single > 0) paste0(" and one of ", 2 * n, " rows in ", single), ".")
    ),
    zoo_kd("participant", N, paste0("The ", N, " participant labels are distinct.")),
    zoo_lu("arm", NP),
    zoo_lu("participant", "person"),
    zoo_lu("site", NP),
    zoo_sr(N),
    zoo_cs("site", NP, rep(2L * n, J)),
    if (single > 0) {
      zoo_finding(
        "structure.within_between", list(factor = "site", term = "arm"),
        "detectable_inconsequential", "partial_slope",
        list(multi_row_levels = zv(J, NP), varying_levels = zv(both, NP),
             informative_levels = zv(both, NP), status = zv("partially_within"),
             slope_requested = zv(TRUE), icc = za(), within_share = za()),
        why = paste0("arm varies within ", both, " sites and not in ", single,
                     ", so the pooled agreement is ", both * n + single * 2 * n, "/", N,
                     ", and 1 + arm | site requests the slope.")
      )
    } else {
      zoo_finding(
        "structure.within_between", list(factor = "site", term = "arm"), "consistent",
        "status",
        list(multi_row_levels = zv(J, NP), varying_levels = zv(J, NP),
             informative_levels = zv(J, NP), status = zv("within"),
             slope_requested = zv(TRUE), icc = za(), within_share = za()),
        why = "Every site has both arms."
      )
    }
  )
  list(
    samples = list(table = zoo_sample(N), design = zoo_sample(N)),
    findings = findings
  )
}

zoo_Z30_parameters <- function(single_arm_sites) {
  list(sites = 12, per_arm = 5, single_arm_sites = zoo_array(single_arm_sites),
       sd_site = "0.4", sd_site_slope = "0.3", effect = "0.3", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z30", name = "single-arm-sites", title = "Multisite trial with single-arm sites",
  role = "fixture", matched = "Z30N", negative_of = character(0), domain = "education",
  catalogue = "L7-04",
  planted = paste("Sites S11 and S12 enrolled the treatment arm only, so a site-varying",
                  "treatment effect rests on the other 10 sites."),
  seed = 202611300, parameters = zoo_Z30_parameters(c(11, 12)), generate = zoo_Z30,
  declaration = function(p) zoo_Z30_declaration(p, "Z30 Multisite trial with single-arm sites"),
  formula = function(p) "y ~ arm + (1 + arm | site)",
  run = zoo_access("Z30", "T0"), expected = zoo_Z30_expected,
  signal = list(zoo_signal("structure.within_between", list(factor = "site", term = "arm"),
                           "partial_slope")),
  planned = list(zoo_planned(
    "assignment.single_arm_blocks", "T0", "L7-04", "0.2", "M4", "Nothing beyond vocabulary 0.1.",
    "Blocks of a declared assignment that hold one arm only."
  ))
)

zoo_define(
  id = "Z30N", name = "both-arms-at-every-site",
  title = "Multisite trial with both arms at every site",
  role = "negative", matched = "Z30", negative_of = "Z30", domain = "education",
  catalogue = "L7-04",
  planted = "Every site enrolled 5 participants in each arm.",
  seed = 202611300, parameters = zoo_Z30_parameters(numeric(0)), generate = zoo_Z30,
  declaration = function(p) {
    zoo_Z30_declaration(p, "Z30N Multisite trial with both arms at every site")
  },
  formula = function(p) "y ~ arm + (1 + arm | site)",
  run = zoo_access("Z30N", "T0"), expected = zoo_Z30_expected,
  signal = list()
)
