# Z12 Distinguishable dyads with negative dependence, and its matched negative
# Z12N. Parents and children have outcome variances 1 and 4 and a within-dyad
# correlation of -0.4 in Z12 and +0.4 in Z12N. A random dyad intercept
# assumes a non-negative within-dyad covariance, and the dyad block that would
# declare distinguishable members and their roles is deferred, so registry
# 0.1.0 gives both the same findings, and the planned check waits for that
# block.

# The data: dyads D01 onwards, each with a parent and then a child, persons
# Q001 onwards in row order, with columns dyad, person, role and y. Draws: for
# each dyad in label order, z1 and z2 from N(0, 1). The parent's y is
# sd_parent z1 and the child's y is child_shift + sd_child (rho z1 +
# sqrt(1 - rho^2) z2), each rounded to the stored grid. Drawn property,
# checked on the stored values: the two values of every dyad differ, else the
# dyad's z1 and z2 are drawn again.
zoo_Z12 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    D <- p$dyads
    rho <- as.numeric(p$correlation)
    pair <- function(z) {
      c(zoo_round(as.numeric(p$sd_parent) * z[1L], p$digits),
        zoo_round(as.numeric(p$child_shift) +
                    as.numeric(p$sd_child) * (rho * z[1L] + sqrt(1 - rho^2) * z[2L]),
                  p$digits))
    }
    y <- as.vector(vapply(seq_len(D), function(d) pair(stats::rnorm(2L)), numeric(2)))
    data <- data.frame(
      dyad = zoo_label("D", rep(seq_len(D), each = 2L), D),
      person = zoo_label("Q", seq_len(2L * D)),
      role = rep(c("parent", "child"), times = D),
      y = y
    )
    zoo_check(
      data,
      list(differ = function(d) which(d$y[c(TRUE, FALSE)] == d$y[c(FALSE, TRUE)])),
      function(d, unit) {
        d$y[2L * unit - c(1L, 0L)] <- pair(stats::rnorm(2L))
        d
      },
      checks
    )
  })
}

zoo_Z12_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "dyad", type = "string"),
      list(name = "person", type = "string"),
      list(name = "role", type = "string", categories = zn("parent", "child")),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "dyad", columns = zn("dyad"), role = "dyad"),
      list(name = "person", columns = zn("person"), nested_in = "dyad", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "person", key = zn("person")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# role[child] and the random intercept of dyad.
zoo_Z12_gram <- function(p) {
  D <- p$dyads
  ones <- matrix(1, 2L * D, 1L)
  list(X = cbind(ones, rep(c(0, 1), times = D)),
       terms = list(list(factor = rep(seq_len(D), each = 2L), columns = ones)))
}

# The expected findings, from the parameters alone. Each person is one member
# of the disclosure unit, so the levels of person resolve as person counts,
# and the dyads, which hold two persons each, and the roles, which hold D
# each, as non-person counts. The drawn property makes the two outcomes of
# every dyad differ, so no dyad is constant.
zoo_Z12_expected <- function(p, data) {
  D <- p$dyads
  stopifnot(D >= 3, all(data$y[c(TRUE, FALSE)] != data$y[c(FALSE, TRUE)]))
  N <- 2L * D
  P <- "person"
  dyad_class <- zoo_count_class(2)
  role_class <- zoo_count_class(D)
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and role[child] are linearly independent."),
      zoo_db("dyad", dyad_class, D, D - 1, "(Intercept)",
             paste0("J - k + r = ", D, " - 2 + 1, since role varies within every dyad.")),
      zoo_gr(zoo_Z12_gram(p), paste0(
        "1 - 1/sqrt(2) for ", D, " pairs whose two rows differ in role, the contrast that ",
        "the fixed part removes, as zoo_gram() computes it."
      )),
      zoo_ld1("dyad", dyad_class, D),
      zoo_rc1("dyad", dyad_class, D, "Every dyad holds two rows."),
      zoo_kd("person", N, paste0("The ", N, " person labels are distinct.")),
      zoo_lu("dyad", dyad_class),
      zoo_lu("person", P),
      zoo_lu("role", role_class),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "dyad"), "consistent", "none_constant",
        list(multi_row_levels = zv(D, dyad_class), constant_levels = zv(0, dyad_class),
             constant_share = zr(0, D, dyad_class)),
        why = "The drawn property makes the two outcomes of every dyad differ."
      ),
      zoo_sr(N),
      zoo_cs("dyad", dyad_class, rep(2, D), why = paste0(D, " dyads of two persons.")),
      zoo_finding(
        "structure.within_between", list(factor = "dyad", term = "role"), "consistent",
        "status",
        list(multi_row_levels = zv(D, dyad_class), varying_levels = zv(D, dyad_class),
             informative_levels = zv(D, dyad_class), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every dyad holds a parent and a child, and role is categorical."
      )
    )
  )
  list(samples = list(table = zoo_sample(N), design = zoo_sample(N), analysis = zoo_sample(N)),
       findings = findings)
}

zoo_Z12_parameters <- function(correlation) {
  list(dyads = 60, sd_parent = "1", sd_child = "2", correlation = correlation,
       child_shift = "0.5", digits = 2)
}

zoo_Z12_planned <- list(zoo_planned(
  "outcome.dyad_dependence", "T1", "L7-08", NULL, "after 1.0", "The dyad block.",
  paste("Negative within-dyad dependence and the distinguishability of the members of a",
        "dyad, which a random dyad intercept cannot represent.")
))

zoo_Z12_deferred <- list(
  block = "dyad",
  reason = paste("Vocabulary 0.1 cannot state distinguishable members, their roles or the",
                 "within-dyad dependence, so the dyad is declared as a unit of role 'dyad'",
                 "with role as a predictor.")
)

zoo_define(
  id = "Z12", name = "dyads-negative-dependence",
  title = "Distinguishable dyads with negative dependence",
  role = "fixture", matched = "Z12N", negative_of = character(0), domain = "dyads",
  catalogue = "L7-08",
  planted = paste("Parents and children have outcome variances 1 and 4 and a within-dyad",
                  "correlation of -0.4, which a random dyad intercept cannot represent."),
  seed = 202611120, parameters = zoo_Z12_parameters("-0.4"), generate = zoo_Z12,
  declaration = function(p) {
    zoo_Z12_declaration(p, "Z12 Distinguishable dyads with negative dependence")
  },
  formula = function(p) "y ~ role + (1 | dyad)",
  run = zoo_access("Z12", "T1"), expected = zoo_Z12_expected,
  signal = list(), planned = zoo_Z12_planned, deferred = zoo_Z12_deferred
)

zoo_define(
  id = "Z12N", name = "dyads-positive-dependence",
  title = "Distinguishable dyads with positive dependence",
  role = "negative", matched = "Z12", negative_of = "Z12", domain = "dyads",
  catalogue = "L7-08",
  planted = paste("The within-dyad correlation is +0.4, a non-negative covariance that a",
                  "random dyad intercept can represent."),
  seed = 202611120, parameters = zoo_Z12_parameters("0.4"), generate = zoo_Z12,
  declaration = function(p) {
    zoo_Z12_declaration(p, "Z12N Distinguishable dyads with positive dependence")
  },
  formula = function(p) "y ~ role + (1 | dyad)",
  run = zoo_access("Z12N", "T1"), expected = zoo_Z12_expected,
  signal = list(), deferred = zoo_Z12_deferred
)
