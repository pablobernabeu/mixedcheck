# Z27 Informative cluster size, and its matched negative Z27N. Persons who
# log more sessions have higher counts, because the person effect rises with
# the number of sessions. In Z27N, the person effects take the same values in
# an order drawn at random, so the sizes carry no information on the counts.
# Registry 0.1.0 reports the sizes and the zeros, and the check of
# informative cluster size is planned. The run is at T1 with a count
# outcome, which also covers outcome.zero_shares.

# The sizes of the persons: each of first to last twice, 2, 2, 3, 3, ...,
# 11, 11 for the stored instances.
zoo_Z27_sizes <- function(p) rep(seq(p$smallest, p$largest), each = 2L)

# The data: persons P01 onwards with sessions 1 to their size, ordered by
# person and session, with columns person, session and y. The person of rank
# r, which rises with the size in label order, has the effect effect_scale
# qnorm(r / (K + 1)). Draws, in this order: with informative false, the
# permutation of the ranks by sample.int(), then the counts in row order from
# rpois() with the log rate log_rate + the person effect. Drawn property,
# checked on the stored counts: no person has all counts equal, else that
# person's counts are drawn again, person by person in label order.
zoo_Z27 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    sizes <- zoo_Z27_sizes(p)
    K <- length(sizes)
    rank <- if (p$informative) seq_len(K) else sample.int(K)
    effect <- as.numeric(p$effect_scale) * stats::qnorm(rank / (K + 1))
    person <- rep(seq_len(K), sizes)
    rate <- exp(as.numeric(p$log_rate) + effect)
    data <- data.frame(
      person = zoo_label("P", person, K),
      session = sequence(sizes),
      y = stats::rpois(length(person), rate[person])
    )
    zoo_check(
      data,
      list(varies = function(d) {
        which(as.vector(tapply(d$y, person, function(v) all(v == v[1L]))))
      }),
      function(d, unit) {
        rows <- person == unit
        d$y[rows] <- stats::rpois(sum(rows), rate[unit])
        d
      },
      checks
    )
  })
}

zoo_Z27_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("intensive_longitudinal"),
    table = list(fields = list(
      list(name = "person", type = "string"),
      list(name = "session", type = "integer"),
      list(name = "y", type = "integer")
    )),
    units = list(list(name = "person", columns = zn("person"), role = "participant")),
    observation = list(key = zn("person", "session"),
                       time = list(column = "session", kind = "occasion", within = "person")),
    variables = list(y = list(role = "outcome", measurement = "count"))
  )
}

# The expected findings. Every count but the zeros follows from the sizes,
# and the drawn property keeps every person from constant counts, so none is
# all zero. The zeros z are counted in the stored outcome, which the draws
# fix. Each person is one member of the disclosure unit, so the levels of
# person resolve as person counts, and the sessions, of which the last holds
# two persons, as non-person counts.
zoo_Z27_expected <- function(p, data) {
  sizes <- zoo_Z27_sizes(p)
  K <- length(sizes)
  N <- sum(sizes)
  stopifnot(K >= 3, min(sizes) >= 2, nrow(data) == N,
            all(tapply(data$y, data$person, function(v) any(v != v[1L]))))
  z <- sum(data$y == 0)
  P <- "person"
  session_class <- zoo_count_class(sum(sizes == max(sizes)))
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("person", P, K, K - 1, "(Intercept)", paste0("J - k + r = ", K, " - 1 + 0.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "necessary_only",
        statistics = list(parameters = zv(1), rank = zv(1),
                          verdict = zv("necessary_condition_met"),
                          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
                          smallest_eigenvalue = zv(1)),
        why = paste("The family class poisson has no residual, so C holds the person variance",
                    "alone, whose eigenvalue is 1, and only the necessary condition applies.")
      ),
      zoo_ld1("person", P, K),
      zoo_rc1("person", P, K, paste("Every person has two sessions or more, and the family",
                                    "class poisson keeps the replicated cells.")),
      zoo_kd(c("person", "session"), N, paste0("Each person and session has one of the ", N,
                                               " rows.")),
      zoo_lu("person", P),
      zoo_lu("session", session_class, "session holds integers, so it has no spellings."),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "person"), "consistent", "none_constant",
        list(multi_row_levels = zv(K, P), constant_levels = zv(0, P),
             constant_share = zr(0, K, P)),
        why = "The drawn property keeps every person from constant counts."
      ),
      zoo_finding(
        "outcome.zero_shares", list(factor = "person"), "consistent", "zeros",
        list(rows = zv(N), zeros = zv(z), zero_share = zr(z, N), levels = zv(K, P),
             all_zero_levels = zv(0, P)),
        why = paste0("The stored counts hold ", z, " zeros, and no person is all zero, since ",
                     "none is constant.")
      ),
      zoo_sr(N),
      zoo_cs("person", P, sizes,
             why = paste0("Sizes ", min(sizes), " to ", max(sizes), " twice each, with ", N,
                          " rows."))
    )
  )
  list(samples = list(table = zoo_sample(N, K), design = zoo_sample(N, K),
                      analysis = zoo_sample(N, K)),
       findings = findings)
}

zoo_Z27_parameters <- function(informative) {
  list(smallest = 2, largest = 11, informative = informative, effect_scale = "0.6",
       log_rate = "0.3")
}

zoo_define(
  id = "Z27", name = "informative-cluster-size", title = "Informative cluster size",
  role = "fixture", matched = "Z27N", negative_of = character(0), domain = "ild",
  catalogue = "L7-13",
  planted = paste("Persons who log more sessions have higher counts, because the person effect",
                  "rises with the number of sessions."),
  seed = 202611270, parameters = zoo_Z27_parameters(TRUE), generate = zoo_Z27,
  declaration = function(p) zoo_Z27_declaration(p, "Z27 Informative cluster size"),
  formula = function(p) "y ~ 1 + (1 | person)",
  run = zoo_access("Z27", "T1"), expected = zoo_Z27_expected,
  signal = list(),
  planned = list(zoo_planned(
    "outcome.informative_size", "T1", "L7-13", "0.2", "M4", "Nothing beyond vocabulary 0.1.",
    "The association of the size of a level with the level mean of the outcome."
  ))
)

zoo_define(
  id = "Z27N", name = "uninformative-cluster-size", title = "Uninformative cluster size",
  role = "negative", matched = "Z27", negative_of = "Z27", domain = "ild",
  catalogue = "L7-13",
  planted = paste("The person effects take the same values in a random order, so the number of",
                  "sessions carries no information on the counts."),
  seed = 202611270, parameters = zoo_Z27_parameters(FALSE), generate = zoo_Z27,
  declaration = function(p) zoo_Z27_declaration(p, "Z27N Uninformative cluster size"),
  formula = function(p) "y ~ 1 + (1 | person)",
  run = zoo_access("Z27N", "T1"), expected = zoo_Z27_expected,
  signal = list()
)
