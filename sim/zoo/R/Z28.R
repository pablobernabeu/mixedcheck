# Z28 Ceiling effects in child scores, and its matched negative Z28N. In Z28,
# a score bounded by 0 and 40 reaches 40 for 2 children in wave 1 and for 12
# in wave 2, 14 of 80 rows, above the share of 0.15 of
# outcome.boundary_shares, and the 2 children at 40 in both waves are
# constant. In Z28N, no score reaches 40.

# The data: children C01 onwards with waves 1 and 2, ordered by child and
# wave, with columns child, wave and score. Draws, in this order: the
# abilities a of the children in label order from N(ability_mean,
# ability_sd), then their growths g by sample.int() from growth_low to
# growth_high. Let r be the rank of a child's ability from the highest, ties
# in label order, and v = min(cap, max(lower + 1, floor(a + 0.5))). By
# construction, the children with r at most ceiling_wave1 score the upper
# bound in both waves, those with r above ceiling_wave1 and at most
# ceiling_wave2 score min(upper - 1, max(lower + 1, floor(a + 0.5))) in wave 1
# and the upper bound in wave 2, and every other child scores v in wave 1 and
# v + g in wave 2, which lies above v and below the upper bound when cap +
# growth_high is below it. No property is drawn: every count that the
# expectations read is structural.
zoo_Z28 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    scores <- zoo_Z28_scores(p)
    data <- data.frame(
      child = zoo_label("C", rep(seq_len(p$children), each = 2L), p$children),
      wave = rep(1:2, times = p$children),
      score = as.vector(rbind(scores$wave1, scores$wave2))
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The scores of both waves, from the draws in the order the generator states.
zoo_Z28_scores <- function(p) {
  K <- p$children
  bounds <- as.numeric(unlist(p$bounds))
  lower <- bounds[1L]
  upper <- bounds[2L]
  stopifnot(p$ceiling_wave1 <= p$ceiling_wave2, p$ceiling_wave2 <= K,
            p$cap + p$growth_high < upper)
  a <- stats::rnorm(K, as.numeric(p$ability_mean), as.numeric(p$ability_sd))
  g <- p$growth_low - 1L + sample.int(p$growth_high - p$growth_low + 1L, K, replace = TRUE)
  r <- integer(K)
  r[order(-a, seq_len(K), method = "radix")] <- seq_len(K)
  rounded <- pmax(lower + 1, floor(a + 0.5))
  v <- pmin(p$cap, rounded)
  wave1 <- ifelse(r <= p$ceiling_wave1, upper,
                  ifelse(r <= p$ceiling_wave2, pmin(upper - 1, rounded), v))
  wave2 <- ifelse(r <= p$ceiling_wave2, upper, v + g)
  list(wave1 = wave1, wave2 = wave2)
}

zoo_Z28_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("longitudinal"),
    table = list(fields = list(
      list(name = "child", type = "string"),
      list(name = "wave", type = "integer"),
      list(name = "score", type = "integer")
    )),
    units = list(list(name = "child", columns = zn("child"), role = "participant")),
    observation = list(key = zn("child", "wave"),
                       time = list(column = "wave", kind = "occasion", within = "child")),
    variables = list(
      score = list(role = "outcome", measurement = "bounded_score",
                   bounds = zoo_array(as.numeric(unlist(p$bounds)))),
      wave = list(role = "time")
    )
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and wave
# and the random intercept of child.
zoo_Z28_gram <- function(p) {
  K <- p$children
  ones <- matrix(1, 2L * K, 1L)
  list(X = cbind(ones, rep(1:2, times = K)),
       terms = list(list(factor = rep(seq_len(K), each = 2L), columns = ones)))
}

# The expected findings, from the parameters alone. The rows at the upper
# bound are ceiling_wave1 in wave 1 and ceiling_wave2 in wave 2, no score
# reaches the lower bound, and the ceiling_wave1 children at the upper bound
# in both waves are the only constant ones. Each child is one member of the
# disclosure unit, so the levels of child resolve as person counts, and the
# waves, which hold every child, as non-person counts.
zoo_Z28_expected <- function(p, data) {
  K <- p$children
  N <- 2L * K
  stopifnot(K >= 3)
  at_ceiling <- p$ceiling_wave1 + p$ceiling_wave2
  constant <- p$ceiling_wave1
  upper <- as.numeric(unlist(p$bounds))[2L]
  stopifnot(sum(data$score == upper) == at_ceiling,
            sum(data$score == as.numeric(unlist(p$bounds))[1L]) == 0)
  P <- "person"
  NP <- zoo_count_class(K)
  # wave takes 1 and 2 on K rows each, so its sd is sqrt((N/4)/(N - 1)), and
  # the scaled columns (1, 1)/sqrt(K) and (1/2, 1)/sqrt(5K/4) have the
  # singular values whose ratio is 3 + sqrt(10).
  sd <- sqrt((N / 4) / (N - 1))
  bounds_finding <- if (at_ceiling / N > 0.15) {
    zoo_finding(
      "outcome.boundary_shares", finding = "detectable_inconsequential", message = "at_bounds",
      statistics = list(rows = zv(N), at_floor = zv(0), at_ceiling = zv(at_ceiling),
                        floor_share = zr(0, N), ceiling_share = zr(at_ceiling, N)),
      why = paste0(p$ceiling_wave1, " children score 40 in wave 1 and ", p$ceiling_wave2,
                   " in wave 2, and ", at_ceiling, "/", N, " exceeds 0.15.")
    )
  } else {
    zoo_finding(
      "outcome.boundary_shares", finding = "consistent", message = "within_bounds",
      statistics = list(rows = zv(N), at_floor = zv(0), at_ceiling = zv(at_ceiling),
                        floor_share = zr(0, N), ceiling_share = zr(at_ceiling, N)),
      why = "No score reaches 0 or 40."
    )
  }
  constant_finding <- if (constant > 0) {
    zoo_finding(
      "outcome.constant_clusters", list(factor = "child"), "detectable_inconsequential", "some",
      list(multi_row_levels = zv(K, P), constant_levels = zv(constant, P),
           constant_share = zr(constant, K, P)),
      why = paste0("The ", constant, " children at 40 in both waves are constant, and every ",
                   "other child scores higher in wave 2.")
    )
  } else {
    zoo_finding(
      "outcome.constant_clusters", list(factor = "child"), "consistent", "none_constant",
      list(multi_row_levels = zv(K, P), constant_levels = zv(0, P),
           constant_share = zr(0, K, P)),
      why = "Every child scores higher in wave 2 than in wave 1."
    )
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and wave are linearly independent."),
      zoo_finding(
        "design.scale_disparity", finding = "consistent", message = "similar",
        statistics = list(scaled_columns = zv(zn("wave")), sd_largest = zv(sd),
                          sd_smallest = zv(sd), sd_ratio = zv(1),
                          condition_number = zv(3 + sqrt(10))),
        why = paste0("wave takes 1 and 2 on ", K, " rows each, so its sd is sqrt(", N / 4, "/",
                     N - 1, ") and the condition number 3 + sqrt(10).")
      ),
      zoo_db("child", P, K, K - 1, "(Intercept)",
             paste0("J - k + r = ", K, " - 2 + 1, since wave varies within every child.")),
      zoo_gr(zoo_Z28_gram(p), paste0(
        "1 - 1/sqrt(2) for ", K, " children whose two rows differ in wave, as zoo_gram() ",
        "computes it."
      )),
      zoo_ld1("child", P, K),
      zoo_rc1("child", P, K, "Every child has two rows."),
      zoo_kd(c("child", "wave"), N, paste0("Each child and wave has one of the ", N, " rows.")),
      zoo_lu("child", P),
      zoo_lu("wave", NP, "wave holds integers, so it has no spellings."),
      bounds_finding,
      constant_finding,
      zoo_sr(N),
      zoo_cs("child", P, rep(2, K), why = paste0(K, " children with two waves each.")),
      zoo_finding(
        "structure.within_between", list(factor = "child", term = "wave"), "consistent",
        "status",
        list(multi_row_levels = zv(K, P), varying_levels = zv(K, P),
             informative_levels = zv(K, P), status = zv("within"),
             slope_requested = zv(FALSE), icc = zv(-1), within_share = zv(1)),
        why = paste("Every child has waves 1 and 2, so the level means are equal, SSB = 0 and",
                    "with n0 = 2, icc = -1 and within_share = 1.")
      )
    )
  )
  list(samples = list(table = zoo_sample(N, K), design = zoo_sample(N, K),
                      analysis = zoo_sample(N, K)),
       findings = findings)
}

zoo_Z28_parameters <- function(ceiling_wave1, ceiling_wave2, cap) {
  list(children = 40, bounds = zoo_array(c(0, 40)), ceiling_wave1 = ceiling_wave1,
       ceiling_wave2 = ceiling_wave2, cap = cap, ability_mean = "28", ability_sd = "5",
       growth_low = 1, growth_high = 6)
}

zoo_define(
  id = "Z28", name = "ceiling-effects", title = "Ceiling effects in child scores",
  role = "fixture", matched = "Z28N", negative_of = character(0), domain = "education",
  catalogue = c("L3-12", "L7-20"),
  planted = paste("A score bounded by 0 and 40 reaches 40 for 2 children in wave 1 and for 12",
                  "in wave 2, 14 of 80 rows, above the share of 0.15."),
  seed = 202611280, parameters = zoo_Z28_parameters(2, 12, 33), generate = zoo_Z28,
  declaration = function(p) zoo_Z28_declaration(p, "Z28 Ceiling effects in child scores"),
  formula = function(p) "score ~ wave + (1 | child)",
  run = zoo_access("Z28", "T1"), expected = zoo_Z28_expected,
  signal = list(
    zoo_signal("outcome.boundary_shares", list(), "at_bounds"),
    zoo_signal("outcome.constant_clusters", list(factor = "child"), "some")
  )
)

zoo_define(
  id = "Z28N", name = "no-ceiling", title = "Child scores below the ceiling",
  role = "negative", matched = "Z28", negative_of = "Z28", domain = "education",
  catalogue = c("L3-12", "L7-20"),
  planted = paste("No score reaches 40: wave 1 is at most 32 and wave 2 at most 38, and every",
                  "child scores higher in wave 2."),
  seed = 202611280, parameters = zoo_Z28_parameters(0, 0, 32), generate = zoo_Z28,
  declaration = function(p) zoo_Z28_declaration(p, "Z28N Child scores below the ceiling"),
  formula = function(p) "score ~ wave + (1 | child)",
  run = zoo_access("Z28N", "T1"), expected = zoo_Z28_expected,
  signal = list()
)
