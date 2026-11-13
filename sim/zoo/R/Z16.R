# Z16 Average-referenced EEG with channel rows, and its matched negative Z16N.
# In Z16, the amplitudes are average-referenced, so the eight channels of
# every trial sum to exactly 0, which makes the channel rows of a trial
# linearly dependent in the outcome. In Z16N, a linked-mastoid reference
# leaves them without the constraint. The EEG block that would declare the
# reference is deferred, so registry 0.1.0 gives both the same findings, and
# the planned check waits for that block.

# The data: subjects s1 onwards, trials 1 to K within each subject, standard
# in the odd trials and deviant in the even ones, and the channels in the
# order of the parameter channels within each trial, with columns subject,
# trial, channel, cond and amp, ordered by subject, trial and channel. Draws,
# in this order: the subject effects, the channel effects in the order of
# channels, the trial effects in subject and trial order and the residuals in
# row order. The raw amplitude is their sum plus deviant_shift on the
# channels of shifted in deviant trials. Under the reference 'average', the
# mean of its trial is subtracted from each raw amplitude, the values are
# rounded to the stored grid, and the last channel is set to minus the sum of
# the others, computed in integer hundredths, so that every stored trial sums
# to exactly 0. Under 'mastoids', the raw amplitudes are rounded. Drawn
# property, checked on the stored values: no subject or channel has a
# constant amplitude, else the residuals of the first such unit's rows are
# drawn again.
zoo_Z16 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    stopifnot(p$reference %in% c("average", "mastoids"))
    S <- p$subjects
    K <- p$trials
    channels <- as.character(unlist(p$channels))
    C <- length(channels)
    subject <- rep(seq_len(S), each = K * C)
    trial <- rep(rep(seq_len(K), each = C), times = S)
    channel <- rep(seq_len(C), times = S * K)
    deviant <- trial %% 2L == 0L
    subject_effect <- stats::rnorm(S, 0, as.numeric(p$sd_subject))
    channel_effect <- stats::rnorm(C, 0, as.numeric(p$sd_channel))
    trial_effect <- stats::rnorm(S * K, 0, as.numeric(p$sd_trial))
    sd_residual <- as.numeric(p$sd_residual)
    fixed <- subject_effect[subject] + channel_effect[channel] +
      trial_effect[(subject - 1L) * K + trial] +
      ifelse(deviant & channels[channel] %in% unlist(p$shifted),
             as.numeric(p$deviant_shift), 0)
    amplitude <- function(residual) {
      raw <- fixed + residual
      if (p$reference == "mastoids") {
        return(zoo_round(raw, p$digits))
      }
      key <- (subject - 1L) * K + trial
      referenced <- zoo_round(raw - stats::ave(raw, key), p$digits)
      if (is.na(p$digits)) {
        return(referenced)
      }
      # The last channel takes minus the sum of the others, in integer units
      # of the stored grid, so that the stored trial sums to exactly 0.
      scale <- 10^p$digits
      units <- floor(referenced * scale + 0.5)
      last <- channel == C
      units[last] <- -as.vector(tapply(units[!last], key[!last], sum))
      units / scale
    }
    data <- data.frame(
      subject = zoo_label("s", subject, S),
      trial = trial,
      channel = channels[channel],
      cond = ifelse(deviant, "deviant", "standard"),
      amp = 0,
      .residual = stats::rnorm(length(subject), 0, sd_residual)
    )
    data$amp <- amplitude(data$.residual)
    constant <- function(values, groups) {
      which(as.vector(tapply(values, groups, function(v) all(v == v[1L]))))
    }
    data <- zoo_check(
      data,
      list(varies = function(d) {
        units <- character(0)
        for (unit in c("subject", "channel")) {
          failing <- constant(d$amp, if (unit == "subject") subject else channel)
          if (length(failing)) {
            units <- c(units, paste0(unit, " ", failing))
          }
        }
        units
      }),
      function(d, unit) {
        parts <- strsplit(unit, " ", fixed = TRUE)[[1L]]
        rows <- if (parts[1L] == "subject") subject == as.integer(parts[2L]) else
          channel == as.integer(parts[2L])
        d$.residual[rows] <- stats::rnorm(sum(rows), 0, sd_residual)
        d$amp <- amplitude(d$.residual)
        d
      },
      checks
    )
    kept <- data[setdiff(names(data), ".residual")]
    for (name in c("zoo_redraws", "zoo_failed")) {
      attr(kept, name) <- attr(data, name)
    }
    kept
  })
}

zoo_Z16_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "trial", type = "integer"),
      list(name = "channel", type = "string"),
      list(name = "cond", type = "string", categories = zn("standard", "deviant")),
      list(name = "amp", type = "number")
    )),
    units = list(
      list(name = "subject", columns = zn("subject"), role = "participant"),
      list(name = "trial", columns = zn("trial"), nested_in = "subject",
           id_scope = "within_parent", role = "trial"),
      list(name = "channel", columns = zn("channel"), role = "channel")
    ),
    crossings = list(list(units = zn("subject", "channel"))),
    observation = list(key = zn("subject", "trial", "channel"),
                       time = list(column = "trial", kind = "trial_index", within = "subject")),
    variables = list(amp = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# cond[deviant] and the random intercepts of subject and channel.
zoo_Z16_gram <- function(p) {
  S <- p$subjects
  K <- p$trials
  C <- length(unlist(p$channels))
  N <- S * K * C
  trial <- rep(rep(seq_len(K), each = C), times = S)
  ones <- matrix(1, N, 1L)
  list(X = cbind(ones, as.numeric(trial %% 2L == 0L)),
       terms = list(list(factor = rep(seq_len(S), each = K * C), columns = ones),
                    list(factor = rep(seq_len(C), times = S * K), columns = ones)))
}

# The expected findings, from the parameters alone, which do not depend on the
# reference. Each subject is one member of the disclosure unit, so the levels
# of subject and the combinations of channel and subject resolve as person
# counts, and the levels of channel, trial and cond, which hold every
# subject, as non-person counts. The drawn property keeps every subject and
# channel from a constant amplitude.
zoo_Z16_expected <- function(p, data) {
  S <- p$subjects
  K <- p$trials
  C <- length(unlist(p$channels))
  stopifnot(S >= 3, K >= 2, K %% 2L == 0L, C >= 3)
  N <- S * K * C
  P <- "person"
  NP <- zoo_count_class(S)
  pair <- list(first = "channel", second = "subject")
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and cond[deviant] are linearly independent."),
      zoo_db("channel", NP, C, C - 1, "(Intercept)",
             paste0("J - k + r = ", C, " - 2 + 1, since cond varies within every channel.")),
      zoo_db("subject", P, S, S - 1, "(Intercept)",
             paste0("J - k + r = ", S, " - 2 + 1, since cond varies within every subject.")),
      zoo_gr(zoo_Z16_gram(p), paste0(
        "The subject, channel and residual variances of ", S, " subjects fully crossed with ",
        C, " channels, as zoo_gram() computes them."
      )),
      zoo_ld1("channel", NP, C),
      zoo_ld1("subject", P, S),
      zoo_rc1("channel", NP, C, paste0(S * K, " rows in each level.")),
      zoo_rc1("subject", P, S, paste0(K * C, " rows in each level.")),
      zoo_kd(c("subject", "trial", "channel"), N,
             paste0("Each subject, trial and channel has one of the ", N, " rows.")),
      zoo_lu("channel", NP),
      zoo_lu("cond", NP),
      zoo_lu("subject", P),
      zoo_lu("trial", NP, "trial holds integers, so it has no spellings."),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "channel"), "consistent", "none_constant",
        list(multi_row_levels = zv(C, NP), constant_levels = zv(0, NP),
             constant_share = zr(0, C, NP)),
        why = "The drawn property keeps every channel from a constant amplitude."
      ),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "subject"), "consistent", "none_constant",
        list(multi_row_levels = zv(S, P), constant_levels = zv(0, P),
             constant_share = zr(0, S, P)),
        why = "The drawn property keeps every subject from a constant amplitude."
      ),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste("Every channel occurs with every subject, so neither partition is finer,",
                    "and both terms have the intercept.")
      ),
      zoo_cs("channel", NP, rep(S * K, C)),
      zoo_cs("subject", P, rep(K * C, S)),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, P), between_component_terms = zv(zn()), exact = zv(TRUE)),
        why = "The full crossing links every subject with every channel in one component."
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(C, NP), levels_second = zv(S, P), combinations = zv(S * C, P),
             first_in_several = zv(C, NP), second_in_several = zv(S, P),
             relation = zv("crossed"), declared = zv("crossed"), inner = zv(zn()),
             outer = zv(zn()), inner_in_several = za(), composite = zv(FALSE),
             inner_alone = zv(FALSE)),
        why = paste0("All ", S * C, " combinations occur, and the pair is declared crossed.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "channel", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(C, NP), varying_levels = zv(C, NP),
             informative_levels = zv(C, NP), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every channel holds standard and deviant trials, and cond is categorical."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(S, P),
             informative_levels = zv(S, P), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every subject has standard and deviant trials, and cond is categorical."
      )
    )
  )
  list(samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S),
                      analysis = zoo_sample(N, S)),
       findings = findings)
}

zoo_Z16_parameters <- function(reference) {
  list(subjects = 4, trials = 8, channels = zn("Fz", "Cz", "Pz", "Oz", "F3", "F4", "P3", "P4"),
       reference = reference, sd_subject = "2", sd_channel = "3", sd_trial = "2",
       sd_residual = "4", shifted = zn("Pz", "Cz"), deviant_shift = "2.5", digits = 2)
}

zoo_Z16_planned <- list(zoo_planned(
  "outcome.reference_dependence", "T1", "L7-17", NULL, "after 1.0", "The EEG block.",
  paste("The dependence of the channel rows of a trial on the declared reference scheme, such",
        "as the average reference, under which the channels of a trial sum to 0.")
))

zoo_Z16_deferred <- list(
  block = "eeg",
  reason = paste("Vocabulary 0.1 cannot state the reference scheme, so the data are declared",
                 "with units subject, trial and channel and channel crossed with subject.")
)

zoo_define(
  id = "Z16", name = "eeg-average-reference", title = "Average-referenced EEG with channel rows",
  role = "fixture", matched = "Z16N", negative_of = character(0), domain = "eeg",
  catalogue = "L7-17",
  planted = paste("The amplitudes are average-referenced, so the eight channels of every trial",
                  "sum to exactly 0 and the channel rows of a trial are linearly dependent in",
                  "the outcome."),
  seed = 202611160, parameters = zoo_Z16_parameters("average"), generate = zoo_Z16,
  declaration = function(p) zoo_Z16_declaration(p, "Z16 Average-referenced EEG with channel rows"),
  formula = function(p) "amp ~ cond + (1 | subject) + (1 | channel)",
  run = zoo_access("Z16", "T1"), expected = zoo_Z16_expected,
  signal = list(), planned = zoo_Z16_planned, deferred = zoo_Z16_deferred
)

zoo_define(
  id = "Z16N", name = "eeg-linked-mastoids", title = "EEG referenced to linked mastoids",
  role = "negative", matched = "Z16", negative_of = "Z16", domain = "eeg",
  catalogue = "L7-17",
  planted = paste("The amplitudes are referenced to linked mastoids, so the channels of a trial",
                  "do not sum to a constant."),
  seed = 202611160, parameters = zoo_Z16_parameters("mastoids"), generate = zoo_Z16,
  declaration = function(p) zoo_Z16_declaration(p, "Z16N EEG referenced to linked mastoids"),
  formula = function(p) "amp ~ cond + (1 | subject) + (1 | channel)",
  run = zoo_access("Z16N", "T1"), expected = zoo_Z16_expected,
  signal = list(), deferred = zoo_Z16_deferred
)
