# Z25 Irregular timestamps across midnight and a clock change, and its matched
# negative Z25N. Experience-sampling beeps are stored as local wall-clock
# times in Europe/London over the night of 24 to 25 October 2026, when clocks
# go back from 02:00 BST to 01:00 GMT. In Z25, two beeps of P2 and two of P5
# fall one hour apart in UTC but at the same local time in the repeated hour,
# so the declared key (person, ts) repeats with different beeps. In Z25N, the
# same instants are written in UTC with 'Z'. Vocabulary 0.1 has no time zone,
# and the check of local timestamps waits for the intensive-longitudinal
# block.

# Minutes since 1970-01-01T00:00Z of a time 'YYYY-MM-DDTHH:MM:SSZ', and the
# text of such minutes, by integer arithmetic on the civil calendar, so that
# neither the time-zone database nor the locale of the system enters.
zoo_Z25_days <- function(y, m, d) {
  y <- y - (m <= 2)
  era <- y %/% 400
  yoe <- y - era * 400
  doy <- (153 * (m + ifelse(m > 2, -3, 9)) + 2) %/% 5 + d - 1
  doe <- yoe * 365 + yoe %/% 4 - yoe %/% 100 + doy
  era * 146097 + doe - 719468
}

zoo_Z25_minutes <- function(text) {
  part <- function(from, to) as.numeric(substr(text, from, to))
  zoo_Z25_days(part(1, 4), part(6, 7), part(9, 10)) * 1440 + part(12, 13) * 60 + part(15, 16)
}

zoo_Z25_civil <- function(days) {
  z <- days + 719468
  era <- z %/% 146097
  doe <- z - era * 146097
  yoe <- (doe - doe %/% 1460 + doe %/% 36524 - doe %/% 146096) %/% 365
  doy <- doe - (365 * yoe + yoe %/% 4 - yoe %/% 100)
  mp <- (5 * doy + 2) %/% 153
  d <- doy - (153 * mp + 2) %/% 5 + 1
  m <- mp + ifelse(mp < 10, 3, -9)
  list(y = yoe + era * 400 + (m <= 2), m = m, d = d)
}

zoo_Z25_two <- function(x) ifelse(x < 10, paste0("0", zoo_digits(x)), zoo_digits(x))

zoo_Z25_date <- function(minutes) {
  civil <- zoo_Z25_civil(minutes %/% 1440)
  paste0(zoo_digits(civil$y), "-", zoo_Z25_two(civil$m), "-", zoo_Z25_two(civil$d))
}

zoo_Z25_datetime <- function(minutes) {
  within <- minutes %% 1440
  paste0(zoo_Z25_date(minutes), "T", zoo_Z25_two(within %/% 60), ":", zoo_Z25_two(within %% 60),
         ":00")
}

# The instants of the beeps in minutes since 1970 in UTC, person by person
# and beep by beep: start + offset k + gap (b - 1) for beep b of the k-th
# person, with the overrides of the parameter overrides in place of the
# regular instants.
zoo_Z25_instants <- function(p) {
  K <- p$persons
  B <- p$beeps
  person <- rep(seq_len(K), each = B)
  beep <- rep(seq_len(B), times = K)
  instant <- zoo_Z25_minutes(p$start) + p$person_offset * person + p$gap * (beep - 1)
  for (override in p$overrides) {
    row <- (override$person - 1) * B + as.numeric(unclass(override$beeps))
    instant[row] <- zoo_Z25_minutes(as.character(unclass(override$at)))
  }
  list(person = person, beep = beep, instant = instant)
}

# Local time in minutes: UTC plus local_offset before the instant
# clock_change and UTC from then on.
zoo_Z25_local <- function(p, instant) {
  instant + ifelse(instant < zoo_Z25_minutes(p$clock_change), p$local_offset, 0)
}

# The data: persons P1 onwards with the beeps 1 to B each, ordered by person
# and beep, with columns person, beep, ts, day and y. In Z25, ts is the local
# wall-clock time without an offset and day the local date, and in Z25N, ts
# is the instant in UTC with 'Z' and day the date in UTC. Draws, in this
# order: the person effects and the residuals in row order. y is their sum,
# rounded to the stored grid. No property is drawn: the instants and the
# local times are structural.
zoo_Z25 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    stopifnot(p$clock %in% c("local", "utc"))
    beeps <- zoo_Z25_instants(p)
    shown <- if (p$clock == "local") zoo_Z25_local(p, beeps$instant) else beeps$instant
    person_effect <- stats::rnorm(p$persons, 0, as.numeric(p$sd_person))
    residual <- stats::rnorm(length(beeps$person), 0, as.numeric(p$sd_residual))
    data <- data.frame(
      person = zoo_label("P", beeps$person, p$persons),
      beep = beeps$beep,
      ts = paste0(zoo_Z25_datetime(shown), if (p$clock == "utc") "Z" else ""),
      day = zoo_Z25_date(shown),
      y = zoo_round(person_effect[beeps$person] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z25_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("intensive_longitudinal"),
    table = list(fields = list(
      list(name = "person", type = "string"),
      list(name = "beep", type = "integer"),
      list(name = "ts", type = "datetime"),
      list(name = "day", type = "date"),
      list(name = "y", type = "number")
    )),
    units = list(list(name = "person", columns = zn("person"), role = "participant")),
    observation = list(key = zn("person", "ts"),
                       time = list(column = "ts", kind = "timestamp", within = "person")),
    variables = list(
      y = list(role = "outcome", measurement = "continuous"),
      beep = list(role = "auxiliary"),
      day = list(role = "auxiliary")
    )
  )
}

# The design of identifiability.gram_rank: the intercept and the random
# intercept of person.
zoo_Z25_gram <- function(p) {
  N <- p$persons * p$beeps
  ones <- matrix(1, N, 1L)
  list(X = ones, terms = list(list(factor = rep(seq_len(p$persons), each = p$beeps),
                                   columns = ones)))
}

# The expected findings, from the parameters alone. The keys follow from the
# instants: in local time, the two beeps of each override fall at the same
# wall-clock time, and every other pair of beeps of a person differs, which
# the function checks on the times it computes from the parameters. Each
# person is one member of the disclosure unit, so the levels of person and
# of ts resolve as person counts.
zoo_Z25_expected <- function(p, data) {
  K <- p$persons
  B <- p$beeps
  N <- K * B
  stopifnot(K >= 3, B >= 2)
  beeps <- zoo_Z25_instants(p)
  shown <- if (p$clock == "local") zoo_Z25_local(p, beeps$instant) else beeps$instant
  ts <- paste0(zoo_Z25_datetime(shown), if (p$clock == "utc") "Z" else "")
  stopifnot(identical(data$ts, ts))
  # Keys are compared as written, so a key repeats when a person has two
  # beeps with the same text of ts.
  counts <- table(paste(beeps$person, ts))
  duplicated_keys <- sum(counts > 1)
  duplicate_rows <- sum(counts[counts > 1])
  stopifnot(all(counts <= 2))
  P <- "person"
  keys <- if (duplicated_keys > 0) {
    # The rows of each repeated key differ in beep, a column with a declared
    # role, so every repeated key conflicts and none is identical.
    zoo_finding(
      "keys.duplicates", finding = "consequential", message = "conflicting",
      statistics = list(rows = zv(N), key_columns = zv(zn("person", "ts")),
                        missing_key_rows = zv(0), duplicated_keys = zv(duplicated_keys),
                        conflicting_keys = zv(duplicated_keys), identical_keys = zv(0),
                        duplicate_rows = zv(duplicate_rows)),
      why = paste("In the repeated hour, P2 has 01:30 twice and P5 01:45 twice in local time,",
                  "and the rows of each pair differ in beep.")
    )
  } else {
    zoo_kd(c("person", "ts"), N, "In UTC, every beep of a person has its own instant.")
  }
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(1, "The fixed part is the intercept alone."),
      zoo_db("person", P, K, K - 1, "(Intercept)", paste0("J - k + r = ", K, " - 1 + 0.")),
      zoo_gr(zoo_Z25_gram(p), paste0(
        "The person and residual variances of ", K, " persons with ", B,
        " rows each, as zoo_gram() computes them."
      )),
      zoo_ld1("person", P, K),
      zoo_rc1("person", P, K, paste0(B, " rows in each level.")),
      keys,
      zoo_lu("person", P),
      zoo_lu("ts", P, "ts holds dates and times in ASCII, so no two differ in Unicode form."),
      zoo_sr(N),
      zoo_cs("person", P, rep(B, K))
    )
  )
  list(samples = list(table = zoo_sample(N, K), design = zoo_sample(N, K)),
       findings = findings)
}

zoo_Z25_parameters <- function(clock) {
  list(persons = 6, beeps = 12, start = "2026-10-24T16:00:00Z", gap = 110, person_offset = 7,
       overrides = list(
         list(person = 2, beeps = zoo_array(c(5, 6)),
              at = zn("2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z")),
         list(person = 5, beeps = zoo_array(c(5, 6)),
              at = zn("2026-10-25T00:45:00Z", "2026-10-25T01:45:00Z"))
       ),
       clock_change = "2026-10-25T01:00:00Z", local_offset = 60, clock = clock,
       sd_person = "0.5", sd_residual = "1", digits = 2)
}

zoo_Z25_deferred <- list(
  block = "intensive_longitudinal",
  reason = paste("Vocabulary 0.1 cannot state the time zone or the clock resolution of",
                 "observation.time, so ts is a timestamp compared as written.")
)

zoo_define(
  id = "Z25", name = "timestamps-across-dst",
  title = "Irregular timestamps across midnight and a clock change",
  role = "fixture", matched = "Z25N", negative_of = character(0), domain = "ild",
  catalogue = c("L7-11", "L7-12"),
  planted = paste("Beeps are stored as local wall-clock times over the night the clocks go back,",
                  "so two beeps of P2 and two of P5 an hour apart share a local time and the",
                  "key (person, ts) repeats."),
  seed = 202611250, parameters = zoo_Z25_parameters("local"), generate = zoo_Z25,
  declaration = function(p) {
    zoo_Z25_declaration(p, "Z25 Irregular timestamps across midnight and a clock change")
  },
  formula = function(p) "y ~ 1 + (1 | person)",
  run = zoo_access("Z25", "T0"), expected = zoo_Z25_expected,
  signal = list(zoo_signal("keys.duplicates", list(), "conflicting")),
  planned = list(zoo_planned(
    "structure.local_time", "T0", c("L7-11", "L7-12"), NULL, "after 1.0",
    "The intensive-longitudinal block.",
    paste("The ordering and spacing of local timestamps across clock changes, which needs the",
          "time zone of observation.time.")
  )),
  deferred = zoo_Z25_deferred
)

zoo_define(
  id = "Z25N", name = "timestamps-in-utc", title = "Timestamps in UTC across a clock change",
  role = "negative", matched = "Z25", negative_of = "Z25", domain = "ild",
  catalogue = c("L7-11", "L7-12"),
  planted = paste("The same instants are written in UTC with 'Z', so every beep of a person has",
                  "its own timestamp."),
  seed = 202611250, parameters = zoo_Z25_parameters("utc"), generate = zoo_Z25,
  declaration = function(p) zoo_Z25_declaration(p, "Z25N Timestamps in UTC across a clock change"),
  formula = function(p) "y ~ 1 + (1 | person)",
  run = zoo_access("Z25N", "T0"), expected = zoo_Z25_expected,
  signal = list(), deferred = zoo_Z25_deferred
)
