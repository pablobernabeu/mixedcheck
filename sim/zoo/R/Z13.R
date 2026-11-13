# Z13 Disconnected crossed design, and its matched negative Z13N. In Z13, the
# subjects of group g1 see the items of the first half and those of g2 the
# items of the second half, so subjects and items form two crossed blocks
# that no row links, and group is constant within each, so its effect rests
# on the difference between the two blocks. In Z13N, the last subject of g1
# sees the first item of the second half in place of its last item, and the
# first subject of g2 the reverse, which links the two blocks.

# The data: G groups of m subjects each, s01 onwards in group order, and G
# blocks of c items each, i01 onwards in block order. Each subject sees the
# c items of its group's block, except, with bridge true, the subjects m and
# m + 1, which exchange the last item of block 1 and the first item of block
# 2. group is the group of the subject. The rows are ordered by subject and
# item. Draws, in this order: G m subject effects, G c item effects and the
# residuals in row order. y is the subject effect, plus effect for each group
# after the first times the group's position, plus the item effect and the
# residual, rounded to the stored grid. No property is drawn.
zoo_Z13 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z13_design(p)
    subject_effect <- stats::rnorm(design$subjects, 0, as.numeric(p$sd_subject))
    item_effect <- stats::rnorm(design$items, 0, as.numeric(p$sd_item))
    residual <- stats::rnorm(length(design$subject), 0, as.numeric(p$sd_residual))
    data <- data.frame(
      subject = zoo_label("s", design$subject, design$subjects),
      item = zoo_label("i", design$item, design$items),
      group = zoo_label("g", design$group, p$groups),
      y = zoo_round(subject_effect[design$subject] + as.numeric(p$effect) * (design$group - 1) +
                      item_effect[design$item] + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

# The rows: subject, item and the subject's group, ordered by subject and
# item.
zoo_Z13_design <- function(p) {
  G <- p$groups
  m <- p$subjects_per_group
  c <- p$items_per_group
  subject <- rep(seq_len(G * m), each = c)
  group <- (subject - 1L) %/% m + 1L
  item <- (group - 1L) * c + rep(seq_len(c), times = G * m)
  if (p$bridge) {
    item[subject == m & item == c] <- c + 1L
    item[subject == m + 1L & item == c + 1L] <- c
  }
  order <- order(subject, item, method = "radix")
  list(subjects = G * m, items = G * c, subject = subject[order], item = item[order],
       group = group[order])
}

zoo_Z13_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("crossed_experiment"),
    table = list(fields = list(
      list(name = "subject", type = "string"),
      list(name = "item", type = "string"),
      list(name = "group", type = "string",
           categories = zn(zoo_label("g", seq_len(p$groups), p$groups))),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "subject", columns = zn("subject"), role = "participant"),
      list(name = "item", columns = zn("item"), role = "item")
    ),
    crossings = list(list(units = zn("subject", "item"))),
    observation = list(key = zn("subject", "item")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The design of identifiability.gram_rank: the columns (Intercept) and
# group[g2] and the random intercepts of subject and item.
zoo_Z13_gram <- function(p) {
  design <- zoo_Z13_design(p)
  ones <- matrix(1, length(design$subject), 1L)
  list(X = cbind(ones, as.numeric(design$group == 2L)), terms = list(
    list(factor = design$subject, columns = ones),
    list(factor = design$item, columns = ones)
  ))
}

# The expected findings, from the parameters alone. Every subject is one
# member of the disclosure unit, so the levels of subject and the
# combinations of item and subject resolve as person counts, and the levels
# of item and of group, which hold m subjects each, as non-person counts.
zoo_Z13_expected <- function(p, data) {
  G <- p$groups
  m <- p$subjects_per_group
  c <- p$items_per_group
  stopifnot(G == 2, m >= 2, c >= 2)
  S <- G * m
  I <- G * c
  N <- S * c
  P <- "person"
  item_class <- zoo_count_class(m)
  pair <- list(first = "item", second = "subject")
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and group[g2] are linearly independent."),
      zoo_db("subject", P, S, S - 2, c("(Intercept)", "group"),
             paste0("J - k + r = ", S, " - 2 + 0, since group is constant within every ",
                    "subject, so both terms lower the budget.")),
      zoo_gr(zoo_Z13_gram(p), paste0(
        "Each block is a full crossing of ", m, " subjects and ", c,
        " items, which separates the three variances, as zoo_gram() computes them."
      )),
      zoo_ld1("item", item_class, I),
      zoo_ld1("subject", P, S),
      zoo_rc1("item", item_class, I, paste0(m, " rows in each level.")),
      zoo_rc1("subject", P, S, paste0(c, " rows in each level.")),
      zoo_kd(c("subject", "item"), N,
             paste0("Each of the ", N, " pairs of subject and item has one row.")),
      zoo_lu("group", item_class),
      zoo_lu("item", item_class),
      zoo_lu("subject", P),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste0("Each item occurs with ", m, " subjects and each subject with ", c,
                     " items, so neither partition is finer.")
      ),
      zoo_cs("item", item_class, rep(m, I)),
      zoo_cs("subject", P, rep(c, S)),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(I, item_class), levels_second = zv(S, P),
             combinations = zv(N, P), first_in_several = zv(I, item_class),
             second_in_several = zv(S, P), relation = zv("partially_crossed"),
             declared = zv("crossed"), inner = zv(zn()), outer = zv(zn()),
             inner_in_several = za(), composite = zv(FALSE), inner_alone = zv(FALSE)),
        why = paste0(N, " of the ", S * I, " combinations occur, and the pair is declared ",
                     "crossed.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "subject", term = "group"), "consistent",
        "status",
        list(multi_row_levels = zv(S, P), varying_levels = zv(0, P),
             informative_levels = zv(0, P), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "group is the subject's group, so it is constant within every subject."
      )
    )
  )
  if (!p$bridge) {
    findings <- c(findings, list(
      zoo_db("item", item_class, I, I - 2, c("(Intercept)", "group"),
             paste0("J - k + r = ", I, " - 2 + 0, since every item is seen by subjects of ",
                    "one group.")),
      zoo_finding(
        "structure.connectivity", pair, "consequential", "confounded",
        list(components = zv(2, P), between_component_terms = zv(zn("group")),
             exact = zv(TRUE)),
        why = paste0("Two components of ", c, " items and ", m,
                     " subjects, and group is exactly constant within each.")
      ),
      zoo_finding(
        "structure.within_between", list(factor = "item", term = "group"), "consistent",
        "status",
        list(multi_row_levels = zv(I, item_class), varying_levels = zv(0, item_class),
             informative_levels = zv(0, item_class), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every item is seen by the subjects of one group only."
      )
    ))
  } else {
    findings <- c(findings, list(
      zoo_db("item", item_class, I, I - 1, "(Intercept)",
             paste0("J - k + r = ", I, " - 2 + 1, since group varies within the two items ",
                    "that the exchange links.")),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, P), between_component_terms = zv(zn()), exact = zv(TRUE)),
        why = "The exchange of two items between two subjects links the two blocks."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "item", term = "group"), "consistent",
        "status",
        list(multi_row_levels = zv(I, item_class), varying_levels = zv(2, item_class),
             informative_levels = zv(2, item_class), status = zv("partially_within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = paste0("The two exchanged items each hold ", m - 1, " rows of one group and 1 of ",
                     "the other, so the pooled agreement ", N - 2, "/", N, " is below 0.99.")
      )
    ))
  }
  list(
    samples = list(table = zoo_sample(N, S), design = zoo_sample(N, S)),
    findings = findings
  )
}

zoo_Z13_parameters <- function(bridge) {
  list(groups = 2, subjects_per_group = 10, items_per_group = 8, bridge = bridge,
       sd_subject = "0.5", sd_item = "0.5", sd_residual = "1", effect = "0.3", digits = 2)
}

zoo_define(
  id = "Z13", name = "disconnected-crossed", title = "Disconnected crossed design",
  role = "fixture", matched = "Z13N", negative_of = character(0), domain = "crossed",
  catalogue = c("L1-14", "L7-18"),
  planted = paste("The subjects of each group see their own items only, so subjects and items",
                  "form two components, and group is constant within each."),
  seed = 202611130, parameters = zoo_Z13_parameters(FALSE), generate = zoo_Z13,
  declaration = function(p) zoo_Z13_declaration(p, "Z13 Disconnected crossed design"),
  formula = function(p) "y ~ group + (1 | subject) + (1 | item)",
  run = zoo_access("Z13", "T0"), expected = zoo_Z13_expected,
  signal = list(zoo_signal("structure.connectivity", list(first = "item", second = "subject"),
                           "confounded"))
)

zoo_define(
  id = "Z13N", name = "connected-crossed", title = "Crossed design linked by two subjects",
  role = "negative", matched = "Z13", negative_of = "Z13", domain = "crossed",
  catalogue = c("L1-14", "L7-18"),
  planted = paste("Subjects s10 and s11 exchange the items i08 and i09, which links the two",
                  "blocks into one component."),
  seed = 202611130, parameters = zoo_Z13_parameters(TRUE), generate = zoo_Z13,
  declaration = function(p) zoo_Z13_declaration(p, "Z13N Crossed design linked by two subjects"),
  formula = function(p) "y ~ group + (1 | subject) + (1 | item)",
  run = zoo_access("Z13N", "T0"), expected = zoo_Z13_expected,
  signal = list()
)
