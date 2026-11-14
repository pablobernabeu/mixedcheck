# Z24 Separation in binary accuracy, and its matched negative Z24N. In Z24,
# every answer in condition C is correct, so the column cond[C] separates the
# events quasi-completely and its coefficient diverges. In Z24N, each subject
# answers one item wrongly in every condition. The run is at T2, which also
# runs outcome.constant_clusters and outcome.minority_events on the binary
# outcome.

# The data: subjects s01 onwards crossed with c items in each of the
# conditions A, B and C, i01 onwards in condition order, one row for each
# subject and item, ordered by subject and item. With the pattern 'rotation',
# which the stored instances use and which draws nothing, subject s answers
# wrongly item ((s - 1) mod c) + 1 of each condition listed in wrong, counted
# within the condition, and every other item correctly. With the pattern
# 'random', for the studies of M6, acc is 1 when a uniform draw, one for
# each row in order, is below the accuracy of the row's condition.
zoo_Z24 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z24_design(p)
    acc <- if (p$pattern == "rotation") {
      as.integer(!design$wrong)
    } else {
      accuracy <- as.numeric(unlist(p$accuracy))
      as.integer(stats::runif(length(design$subject)) < accuracy[design$condition])
    }
    data <- data.frame(
      subject = zoo_label("s", design$subject, p$subjects),
      item = zoo_label("i", design$item, 3 * p$items_per_condition),
      cond = c("A", "B", "C")[design$condition],
      acc = acc
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: subject, item, condition as 1, 2 or 3 and whether the rotation
# makes the answer wrong.
zoo_Z24_design <- function(p) {
  stopifnot(p$pattern %in% c("rotation", "random"))
  S <- p$subjects
  c <- p$items_per_condition
  subject <- rep(seq_len(S), each = 3 * c)
  item <- rep(seq_len(3 * c), times = S)
  condition <- (item - 1L) %/% c + 1L
  position <- (item - 1L) %% c + 1L
  wrong <- c("A", "B", "C")[condition] %in% unlist(p$wrong) & position == (subject - 1L) %% c + 1L
  list(subject = subject, item = item, condition = condition, wrong = wrong)
}

zoo_Z24_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("crossed_experiment", "trial_level"),
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "item", type = "string"),
      list(name = "cond", type = "string", categories = zn("A", "B", "C")),
      list(name = "acc", type = "integer")
    )),
    units = list(
      list(name = "subject", columns = zn("subject"), role = "participant"),
      list(name = "item", columns = zn("item"), role = "item")
    ),
    crossings = list(list(units = zn("subject", "item"))),
    observation = list(key = zn("subject", "item")),
    variables = list(acc = list(role = "outcome", measurement = "binary"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept), cond[B]
# and cond[C] and the random intercepts of subject and item. The family class
# is bernoulli, so the Gram matrix has no residual.
zoo_Z24_gram <- function(p) {
  design <- zoo_Z24_design(p)
  ones <- matrix(1, length(design$subject), 1L)
  X <- cbind(ones, as.numeric(design$condition == 2L), as.numeric(design$condition == 3L))
  list(X = X, terms = list(list(factor = design$subject, columns = ones),
                           list(factor = design$item, columns = ones)),
       gaussian = FALSE)
}

# The expected findings of the rotation, from the parameters alone. Every
# subject is one member of the disclosure unit, so the levels of subject and
# the combinations of item and subject resolve as person counts, and the
# levels of item and cond, which hold every subject, as non-person counts.
zoo_Z24_expected <- function(p, data) {
  stopifnot(p$pattern == "rotation")
  S <- p$subjects
  c <- p$items_per_condition
  stopifnot(S >= 2 * c, c >= 2, all(c("A", "B") %in% unlist(p$wrong)))
  I <- 3 * c
  N <- S * I
  P <- "person"
  NP <- zoo_count_class(S)
  design <- zoo_Z24_design(p)
  # Every subject answers one item wrongly in each condition of wrong, and
  # item k of a condition of wrong is answered wrongly by the subjects s with
  # (s - 1) mod c = k - 1.
  w <- length(unlist(p$wrong))
  non_events <- S * w
  events <- N - non_events
  item_minority <- as.vector(tapply(design$wrong, design$item, sum))
  stopifnot(isTRUE(all.equal(as.numeric(item_minority),
                             as.vector(outer(seq_len(c), c("A", "B", "C"), function(k, condition) {
                               ifelse(condition %in% unlist(p$wrong), (S - k) %/% c + 1, 0)
                             })))))
  sorted <- sort(item_minority, method = "radix")
  constant_items <- sum(item_minority == 0)
  separated <- !("C" %in% unlist(p$wrong))
  gram <- zoo_gram(zoo_Z24_gram(p)$X, zoo_Z24_gram(p)$terms, gaussian = FALSE)
  stopifnot(length(gram$vanishing) == 0L)
  pair <- list(first = "item", second = "subject")
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(3, "The columns (Intercept), cond[B] and cond[C] are linearly independent."),
      zoo_db("item", NP, I, I - 3, c("(Intercept)", "cond"),
             paste0("J - k + r = ", I, " - 3 + 0, since cond is constant within every item, so ",
                    "both terms lower the budget.")),
      zoo_db("subject", P, S, S - 1, "(Intercept)",
             paste0("J - k + r = ", S, " - 3 + 2, since every subject sees all three ",
                    "conditions.")),
      zoo_finding(
        "identifiability.gram_rank", finding = "consistent", message = "necessary_only",
        statistics = list(parameters = zv(2), rank = zv(2),
                          verdict = zv("necessary_condition_met"),
                          vanishing_parameters = zv(zn()), confounded_parameters = zv(zn()),
                          smallest_eigenvalue = zv(gram$smallest_eigenvalue)),
        why = paste0("The subject and item variances on the latent scale, without a residual, ",
                     "as zoo_gram() computes them.")
      ),
      zoo_ld1("item", NP, I),
      zoo_ld1("subject", P, S),
      zoo_rc1("item", NP, I, paste0(S, " rows in each level.")),
      zoo_rc1("subject", P, S, paste0(I, " rows in each level.")),
      zoo_kd(c("subject", "item"), N,
             paste0("Each of the ", N, " pairs of subject and item has one row.")),
      zoo_lu("cond", NP),
      zoo_lu("item", NP),
      zoo_lu("subject", P),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "item"),
        if (constant_items > 0) "detectable_inconsequential" else "consistent",
        if (constant_items > 0) "many" else "none_constant",
        list(multi_row_levels = zv(I, NP), constant_levels = zv(constant_items, NP),
             constant_share = zr(constant_items, I, NP)),
        why = if (constant_items > 0) {
          paste0("The ", constant_items, " items of C are always answered correctly, and ",
                 constant_items, "/", I, " reaches 0.25.")
        } else {
          "Every item is answered wrongly by at least one subject."
        }
      ),
      zoo_finding(
        "outcome.constant_clusters", list(factor = "subject"), "consistent", "none_constant",
        list(multi_row_levels = zv(S, P), constant_levels = zv(0, P),
             constant_share = zr(0, S, P)),
        why = paste0("Every subject answers ", w, " items wrongly and the others correctly.")
      ),
      zoo_finding(
        "outcome.minority_events", list(factor = "item"), "consistent", "events",
        list(events = zv(events), non_events = zv(non_events), levels = zv(I, NP),
             levels_without_minority = zv(constant_items, NP),
             median_minority = zv(sorted[ceiling(I / 2)]),
             events_per_column = zv(min(events, non_events) / 3)),
        why = paste0("The item minority counts sorted put ", sorted[ceiling(I / 2)],
                     " at position ", ceiling(I / 2), ", and min(", events, ", ", non_events,
                     ")/3 events per kept column.")
      ),
      zoo_finding(
        "outcome.minority_events", list(factor = "subject"), "consistent", "events",
        list(events = zv(events), non_events = zv(non_events), levels = zv(S, P),
             levels_without_minority = zv(0, P), median_minority = zv(w),
             events_per_column = zv(min(events, non_events) / 3)),
        why = paste0("Every subject has ", w, " wrong answers, so every level minority is ", w,
                     ".")
      ),
      if (separated) {
        # Both classes occur in A and in B, which forces b of (Intercept) and
        # of cond[B] to 0, so the first program reaches 60 with b of cond[C]
        # at 1 on the S c rows of C, the second cannot exceed 0, and on the
        # optimal face S c b >= S c - 1e-6 fixes b of cond[C] to
        # [1 - 1e-6/(S c), 1].
        zoo_finding(
          "outcome.separation", finding = "consequential", message = "quasi",
          statistics = list(
            columns = zv(3), events = zv(events), non_events = zv(non_events),
            both_classes = zv(TRUE), verdict = zv("quasi"), optimum = zv(S * c), margin = zv(0),
            bounds = zv(list(0, 0, 0, 0, 1 - 1e-6 / (S * c), 1)),
            columns_involved = zv(zn("cond[C]"))
          ),
          why = paste0("Both classes in A and B fix the other coefficients to 0, and cond[C] ",
                       "reaches ", S * c, " on the rows of C, which are all events.")
        )
      } else {
        zoo_finding(
          "outcome.separation", finding = "consistent", message = "none",
          statistics = list(
            columns = zv(3), events = zv(events), non_events = zv(non_events),
            both_classes = zv(TRUE), verdict = zv("none"), optimum = zv(0), margin = zv(0),
            bounds = za(), columns_involved = za()
          ),
          why = paste("Both classes occur in every condition, so every coefficient of the first",
                      "program is 0.")
        )
      },
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Every item occurs with every subject, so neither partition is finer, and ",
                     "both terms have the intercept.")
      ),
      zoo_cs("item", NP, rep(S, I)),
      zoo_cs("subject", P, rep(I, S)),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, P), between_component_terms = zv(zn()), exact = zv(TRUE)),
        why = "The full crossing links every subject with every item in one component."
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(I, NP), levels_second = zv(S, P), combinations = zv(N, P),
             first_in_several = zv(I, NP), second_in_several = zv(S, P),
             relation = zv("crossed"), declared = zv("crossed"), inner = zv(zn()),
             outer = zv(zn()), inner_in_several = za(), composite = zv(FALSE),
             inner_alone = zv(FALSE)),
        why = paste0("All ", N, " combinations occur, and the pair is declared crossed.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "item", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(I, NP), varying_levels = zv(0, NP),
             informative_levels = zv(0, NP), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Each item belongs to one condition."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(S, P),
             informative_levels = zv(S, P), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every subject sees the items of all three conditions."
      )
    )
  )
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S),
                   analysis = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z24_parameters <- function(wrong, accuracy) {
  list(subjects = 12, items_per_condition = 5, pattern = "rotation", wrong = zn(wrong),
       accuracy = zoo_array(accuracy))
}

zoo_define(
  id = "Z24", name = "separation", title = "Separation in binary accuracy",
  role = "fixture", matched = "Z24N", negative_of = character(0), domain = "crossed",
  catalogue = c("L3-03", "L3-04"),
  planted = paste("Every answer in condition C is correct, so cond[C] separates the events",
                  "quasi-completely and its coefficient diverges."),
  seed = 202611240, parameters = zoo_Z24_parameters(c("A", "B"), c("0.8", "0.8", "1")),
  generate = zoo_Z24,
  declaration = function(p) zoo_Z24_declaration(p, "Z24 Separation in binary accuracy"),
  formula = function(p) "acc ~ cond + (1 | subject) + (1 | item)",
  run = zoo_access("Z24", "T2"), expected = zoo_Z24_expected,
  signal = list(
    zoo_signal("outcome.constant_clusters", list(factor = "item"), "many"),
    zoo_signal("outcome.separation", list(), "quasi")
  )
)

zoo_define(
  id = "Z24N", name = "no-separation", title = "Binary accuracy below 1 in every condition",
  role = "negative", matched = "Z24", negative_of = "Z24", domain = "crossed",
  catalogue = c("L3-03", "L3-04"),
  planted = paste("Each subject answers one item wrongly in every condition, so both classes",
                  "occur in every condition and no column separates the events."),
  seed = 202611240, parameters = zoo_Z24_parameters(c("A", "B", "C"), c("0.8", "0.8", "0.8")),
  generate = zoo_Z24,
  declaration = function(p) {
    zoo_Z24_declaration(p, "Z24N Binary accuracy below 1 in every condition")
  },
  formula = function(p) "acc ~ cond + (1 | subject) + (1 | item)",
  run = zoo_access("Z24N", "T2"), expected = zoo_Z24_expected,
  signal = list()
)
