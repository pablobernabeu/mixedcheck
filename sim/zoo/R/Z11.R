# Z11 Families with singletons, and its matched negative Z11N. In Z11, 44 of
# 80 families have one child. Singletons are legitimate and kept, but only the
# 36 families with two children or more separate the family variance from the
# residual and inform the by-family slope of x. In Z11N, 40 families have two
# to four children each.

# The sizes of the families before their order is drawn: singles families of
# one child, then pairs of two, triples of three and quadruples of four.
zoo_Z11_sizes <- function(p) {
  rep(1:4, c(p$singles, p$pairs, p$triples, p$quadruples))
}

# The data: families F01 onwards and children K001 onwards, ordered by family
# and child, with columns family, child, x and y. Draws, in this order: the
# order of the families by sample.int(), which assigns the sizes to the labels
# and changes no count, then x from N(0, sd_x) in row order, on the stored
# grid. The drawn properties of x are then checked: the children of every
# family of two or more do not all share one value of x, else the last
# child's x is drawn again, and the standard deviation of x lies in [0.5, 2],
# else every x is drawn again. Then the family intercepts and the family
# slopes, each in label order, and the residuals in row order. y is the
# family intercept plus the family slope times x plus the residual, rounded
# to the stored grid.
zoo_Z11 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    sizes <- zoo_Z11_sizes(p)
    J <- length(sizes)
    sizes <- sizes[sample.int(J)]
    N <- sum(sizes)
    family <- rep(seq_len(J), sizes)
    last <- cumsum(sizes)
    draw_x <- function(n) zoo_round(stats::rnorm(n, 0, as.numeric(p$sd_x)), p$digits)
    covariate <- data.frame(family = family, x = draw_x(N))
    covariate <- zoo_check(
      covariate,
      list(
        varies = function(d) {
          constant <- tapply(d$x, d$family, function(v) length(v) >= 2L && all(v == v[1L]))
          which(as.vector(constant))
        },
        spread = function(d) {
          s <- zoo_sd(d$x)
          if (s < 0.5 || s > 2) "all" else integer(0)
        }
      ),
      function(d, unit) {
        if (identical(unit, "all")) {
          d$x <- draw_x(N)
        } else {
          d$x[last[unit]] <- draw_x(1L)
        }
        d
      },
      checks
    )
    x <- covariate$x
    intercept <- stats::rnorm(J, 0, as.numeric(p$sd_family))
    slope <- stats::rnorm(J, 0, as.numeric(p$sd_slope))
    residual <- stats::rnorm(N, 0, as.numeric(p$sd_residual))
    data <- data.frame(
      family = zoo_label("F", family, J),
      child = zoo_label("K", seq_len(N)),
      x = x,
      y = zoo_round(intercept[family] + slope[family] * x + residual, p$digits)
    )
    for (name in c("zoo_redraws", "zoo_failed")) {
      attr(data, name) <- attr(covariate, name)
    }
    data
  })
}

zoo_Z11_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("family"),
    table = list(fields = list(
      list(name = "family", type = "string"),
      list(name = "child", type = "string"),
      list(name = "x", type = "number"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "family", columns = zn("family"), role = "family"),
      list(name = "child", columns = zn("child"), nested_in = "family", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "child", key = zn("child")),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      x = list(role = "baseline_covariate")
    )
  )
}

# The expected findings. Every count follows from the sizes: each child is one
# member of the disclosure unit, so the levels of family resolve as person
# counts when some family has one child. The drawn property makes every
# family of two or more children vary in x, so those families inform the
# slope. The reals that x fixes are computed from the stored x with the
# helpers of zoo.R.
zoo_Z11_expected <- function(p, data) {
  sizes <- zoo_Z11_sizes(p)
  J <- length(sizes)
  N <- sum(sizes)
  multi <- sum(sizes >= 2)
  stopifnot(J >= 3, multi >= 3, nrow(data) == N)
  x <- data$x
  family <- data$family
  stopifnot(all(tapply(x, family, function(v) length(v) == 1L || any(v != v[1L]))))
  P <- "person"
  family_class <- zoo_count_class(sizes)
  sd <- zoo_sd(x)
  stopifnot(sd >= 0.5, sd <= 2)
  anova <- zoo_anova(x, family)
  X <- cbind(1, x)
  term <- "1 + x | family"
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and x are linearly independent."),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(scaled_columns = zv(zn("x")), sd_largest = zv(sd),
                          sd_smallest = zv(sd), sd_ratio = zv(1),
                          condition_number = zv(zoo_condition(X))),
        why = paste("x is the only scaled column, so sd_ratio is 1, and zoo_sd() and",
                    "zoo_condition() compute the reals from the stored x.")
      ),
      zoo_db("family", family_class, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 2 + 1, since x varies within the families of two ",
                    "children or more.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "identified",
        statistics = list(
          parameters = zv(4), rank = zv(4), verdict = zv("identified"),
          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
          smallest_eigenvalue = zv(zoo_gram(X, list(list(factor = family, columns = X)))$
                                     smallest_eigenvalue)
        ),
        why = paste0("The intercept and slope variances, their covariance and the residual, ",
                     "separated by the ", multi, " families in which x varies, as zoo_gram() ",
                     "computes them.")
      ),
      zoo_finding(
        "identifiability.levels_vs_dimension", list(factor = "family", term = term),
        "consistent", "adequate",
        list(dimension = zv(2), levels = zv(J, family_class),
             informative_levels = zv(multi, family_class), counterparts = zv(TRUE),
             bound = zv(J - 1, family_class)),
        why = paste0("Rank 2 needs two children with different x, which the ", multi,
                     " families of two or more have, and x is also fixed, so the bound is ",
                     J - 1, ".")
      ),
      zoo_kd("child", N, paste0("The ", N, " child labels are distinct.")),
      zoo_lu("child", P),
      zoo_lu("family", family_class),
      zoo_sr(N),
      zoo_cs("family", family_class, sizes, why = zoo_Z11_listing(p)),
      zoo_finding(
        "structure.within_between", list(factor = "family", term = "x"), "consistent", "status",
        list(multi_row_levels = zv(multi, family_class),
             varying_levels = zv(multi, family_class),
             informative_levels = zv(multi, family_class), status = zv("within"),
             slope_requested = zv(TRUE), icc = zv(anova$icc),
             within_share = zv(anova$within_share)),
        why = paste0("x varies within each of the ", multi, " families of two or more by the ",
                     "drawn property, and zoo_anova() computes icc and within_share.")
      )
    )
  )
  list(samples = list(table = zoo_sample(N), design = zoo_sample(N)), findings = findings)
}

# The sizes in words, such as '44 families of one child, 28 of two and 8 of
# three.'
zoo_Z11_listing <- function(p) {
  counts <- c(p$singles, p$pairs, p$triples, p$quadruples)
  words <- c("one child", "two", "three", "four")[counts > 0]
  counts <- counts[counts > 0]
  parts <- paste0(zoo_digits(counts), c(" families of ", rep(" of ", length(counts) - 1L)), words)
  if (length(parts) > 1L) {
    parts <- c(paste(parts[-length(parts)], collapse = ", "), parts[length(parts)])
  }
  paste0(paste(parts, collapse = " and "), ".")
}

zoo_Z11_parameters <- function(singles, pairs, triples, quadruples) {
  list(singles = singles, pairs = pairs, triples = triples, quadruples = quadruples,
       sd_x = "1", sd_family = "0.7", sd_slope = "0.2", sd_residual = "1", digits = 2)
}

zoo_define(
  id = "Z11", name = "singleton-families", title = "Families with singletons",
  role = "fixture", matched = "Z11N", negative_of = character(0), domain = "families",
  catalogue = c("L1-09", "L7-06"),
  planted = paste("44 of 80 families have one child, so only the 36 families with two children",
                  "or more separate the family variance from the residual and inform the slope."),
  seed = 202611110, parameters = zoo_Z11_parameters(44, 28, 8, 0), generate = zoo_Z11,
  declaration = function(p) zoo_Z11_declaration(p, "Z11 Families with singletons"),
  formula = function(p) "y ~ x + (1 + x | family)",
  run = zoo_access("Z11", "T0"), expected = zoo_Z11_expected,
  signal = list(zoo_signal("structure.cluster_sizes", list(factor = "family"), "sizes",
                           list(singletons = 44)))
)

zoo_define(
  id = "Z11N", name = "families-of-two-to-four", title = "Families of two to four children",
  role = "negative", matched = "Z11", negative_of = "Z11", domain = "families",
  catalogue = c("L1-09", "L7-06"),
  planted = paste("Every one of the 40 families has two to four children, so every family",
                  "informs the family variance and the slope."),
  seed = 202611110, parameters = zoo_Z11_parameters(0, 15, 15, 10), generate = zoo_Z11,
  declaration = function(p) zoo_Z11_declaration(p, "Z11N Families of two to four children"),
  formula = function(p) "y ~ x + (1 + x | family)",
  run = zoo_access("Z11N", "T0"), expected = zoo_Z11_expected,
  signal = list()
)
