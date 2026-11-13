# Z26 Lagged outcome with person-mean centring and short series, and its
# matched negative Z26N. The formula regresses the outcome on its own lag,
# centred at the person mean, whose coefficient is biased in short series. In
# Z26, 20 persons have 10 occasions each, and in Z26N, 2 persons have 100
# each. The declaration marks both lag columns as derived from the outcome,
# so registry 0.1.0 refuses the predictor in every Stream B run, since the
# outcome-blind checks must read no outcome, and the check of the bias in
# short series waits for the intensive-longitudinal block and Stream A.

# The data: persons P01 onwards with the occasions 1 to n each, ordered by
# person and occasion, with columns person, t, y, y_lag and y_lag_pc. Draws,
# in this order: the person means and the innovations in row order. The
# first occasion of a person is its mean plus the innovation scaled to the
# stationary standard deviation, and each later one is the mean plus
# autoregression times the deviation of the previous one from the mean plus
# the innovation. y is rounded to the stored grid, y_lag is the stored y of
# the previous occasion, missing at the first, and y_lag_pc is y_lag minus
# the person's mean of y_lag over the occasions from the second, rounded to
# the stored grid. No property is drawn: the expectation is the refusal,
# which reads no value.
zoo_Z26 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    K <- p$persons
    n <- p$occasions
    phi <- as.numeric(p$autoregression)
    mu <- stats::rnorm(K, 0, as.numeric(p$sd_person))
    innovation <- stats::rnorm(K * n, 0, as.numeric(p$sd_residual))
    person <- rep(seq_len(K), each = n)
    t <- rep(seq_len(n), times = K)
    latent <- numeric(K * n)
    for (i in seq_along(latent)) {
      latent[i] <- if (t[i] == 1L) {
        mu[person[i]] + innovation[i] / sqrt(1 - phi^2)
      } else {
        mu[person[i]] + phi * (latent[i - 1L] - mu[person[i]]) + innovation[i]
      }
    }
    y <- zoo_round(latent, p$digits)
    y_lag <- ifelse(t == 1L, NA, c(NA, y[-length(y)]))
    centre <- stats::ave(ifelse(is.na(y_lag), 0, y_lag), person) * n / (n - 1)
    data <- data.frame(
      person = zoo_label("P", person, max(K, 10)),
      t = t,
      y = y,
      y_lag = y_lag,
      y_lag_pc = zoo_round(y_lag - centre, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z26_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("intensive_longitudinal"),
    table = list(fields = list(
      list(name = "person", type = "string"),
      list(name = "t", type = "integer"),
      list(name = "y", type = "number"),
      list(name = "y_lag", type = "number"),
      list(name = "y_lag_pc", type = "number")
    )),
    units = list(list(name = "person", columns = zn("person"), role = "participant")),
    observation = list(key = zn("person", "t"),
                       time = list(column = "t", kind = "occasion", within = "person")),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      y_lag = list(role = "outcome_derived", derived_from = zn("y")),
      y_lag_pc = list(role = "outcome_derived", derived_from = zn("y_lag"))
    )
  )
}

# The expected result: audit() refuses the run at step 6 with E6069, since
# the formula's predictor y_lag_pc is declared outcome_derived, whatever the
# values. E6069 has no location, so the issue has no pointer.
zoo_Z26_expected <- function(p, data) {
  list(issue = list(
    code = "E6069",
    message = paste("The column 'y_lag_pc' is an outcome, is derived from one or holds the",
                    "trials of the response, so the outcome-blind checks cannot read it.")
  ))
}

zoo_Z26_parameters <- function(persons, occasions) {
  list(persons = persons, occasions = occasions, autoregression = "0.3", sd_person = "0.5",
       sd_residual = "1", digits = 2)
}

zoo_Z26_deferred <- list(
  block = "intensive_longitudinal",
  reason = paste("Vocabulary 0.1 cannot state how a lag is built within persons, days and",
                 "sessions, so the lag columns are declared outcome_derived, which Stream B",
                 "refuses with E6069.")
)

zoo_define(
  id = "Z26", name = "lagged-outcome-short-series",
  title = "Lagged outcome with person-mean centring and short series",
  role = "fixture", matched = "Z26N", negative_of = character(0), domain = "ild",
  catalogue = "L7-12",
  planted = paste("The formula regresses the outcome on its own lag centred at the person mean",
                  "over 10 occasions, a lag whose coefficient is biased in short series."),
  seed = 202611260, parameters = zoo_Z26_parameters(20, 10), generate = zoo_Z26,
  declaration = function(p) {
    zoo_Z26_declaration(p, "Z26 Lagged outcome with person-mean centring and short series")
  },
  formula = function(p) "y ~ y_lag_pc + (1 | person)",
  run = zoo_access("Z26", "T2"), expected = zoo_Z26_expected,
  signal = list(),
  planned = list(zoo_planned(
    "design.lagged_outcome", "T2", "L7-12", NULL, "after 1.0",
    "The intensive-longitudinal block and Stream A.",
    paste("The bias of the coefficient of a lagged outcome, centred at the person mean, in",
          "series as short as those of the data.")
  )),
  deferred = zoo_Z26_deferred
)

zoo_define(
  id = "Z26N", name = "lagged-outcome-long-series",
  title = "Lagged outcome with person-mean centring and long series",
  role = "negative", matched = "Z26", negative_of = "Z26", domain = "ild",
  catalogue = "L7-12",
  planted = paste("Two persons have 100 occasions each, so the bias of the centred lag is",
                  "small, and the run is refused alike."),
  seed = 202611260, parameters = zoo_Z26_parameters(2, 100), generate = zoo_Z26,
  declaration = function(p) {
    zoo_Z26_declaration(p, "Z26N Lagged outcome with person-mean centring and long series")
  },
  formula = function(p) "y ~ y_lag_pc + (1 | person)",
  run = zoo_access("Z26N", "T2"), expected = zoo_Z26_expected,
  signal = list(), deferred = zoo_Z26_deferred
)
