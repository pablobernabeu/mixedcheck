# Z10 Partially nested trial, and its matched negative Z10N. Participants
# were randomised individually, those in the therapy arm were treated in
# groups, and the controls are coded as groups of one, so that a random
# intercept for group spans both arms of a partially nested design. Registry
# 0.1.0 reports the sizes but has no check of the partial nesting, which is
# planned. In Z10N the controls are also in groups of the same size.

# The layout, from the parameters alone: participants 1 to therapy take
# therapy in groups G1 onwards of group_size, and the other participants are
# controls, each a group of one labelled C01 onwards with control_singletons
# true, or in further groups G of group_size otherwise.
zoo_Z10_layout <- function(p) {
  P <- p$participants
  treated <- p$therapy
  size <- p$group_size
  stopifnot(treated %% size == 0, p$control_singletons || (P - treated) %% size == 0)
  therapy <- seq_len(P) <= treated
  groups <- treated / size
  index <- ifelse(therapy, ceiling(seq_len(P) / size),
                  if (p$control_singletons) seq_len(P) - treated
                  else groups + ceiling((seq_len(P) - treated) / size))
  singleton <- !therapy & p$control_singletons
  list(therapy = therapy, index = index, singleton = singleton,
       groups = if (p$control_singletons) groups else P / size)
}

# The data: participant P01 onwards, arm, group and y, one row for each
# participant. Draws, in this order: the effects of the groups of more than
# one participant in label order, and the residuals in row order. A control
# coded as a group of one has no group effect. y is the group effect, effect
# for therapy and the residual, rounded to the stored grid. No property is
# drawn.
zoo_Z10 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    L <- zoo_Z10_layout(p)
    P <- p$participants
    group_effect <- stats::rnorm(L$groups, 0, as.numeric(p$sd_group))
    residual <- stats::rnorm(P, 0, as.numeric(p$sd_residual))
    effect <- ifelse(L$singleton, 0, group_effect[pmin(L$index, L$groups)])
    group <- character(P)
    group[L$singleton] <- zoo_label("C", L$index[L$singleton], P - p$therapy)
    group[!L$singleton] <- zoo_label("G", L$index[!L$singleton], L$groups)
    data <- data.frame(
      participant = zoo_label("P", seq_len(P)),
      arm = ifelse(L$therapy, "therapy", "control"),
      group = group,
      y = zoo_round(effect + as.numeric(p$effect) * L$therapy + residual, p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z10_declaration <- function(p, title) {
  declaration <- list(vocabulary = "0.1.0", title = title)
  if (p$control_singletons) {
    declaration$features <- zn("partially_nested")
  }
  c(declaration, list(
    table = list(fields = list(
      list(name = "participant", type = "string"),
      list(name = "arm", type = "string", categories = zn("control", "therapy")),
      list(name = "group", type = "string"),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "group", columns = zn("group"), role = "cluster"),
      list(name = "participant", columns = zn("participant"), nested_in = "group",
           id_scope = "global", role = "participant")
    ),
    observation = list(unit = "participant", key = zn("participant")),
    assignment = list(list(column = "arm", unit = "participant", randomised = TRUE,
                           level = "between_unit")),
    variables = list(y = list(role = "outcome", measurement = "continuous"),
                     arm = list(role = "assigned")),
    estimands = list(list(id = "effect", term = "arm", kind = "total_effect"))
  ))
}

# The expected findings, from the parameters alone. The three assignment
# checks yield no finding: the assignment is available, but every level of
# its unit, the participant, has one row, so their applies_when fails. A
# group of one holds one participant, so the counts of the levels of group
# resolve as person counts in Z10 and as non-person counts in Z10N.
zoo_Z10_expected <- function(p, data) {
  L <- zoo_Z10_layout(p)
  P <- p$participants
  size <- p$group_size
  stopifnot(size >= 2, p$therapy >= size, P - p$therapy >= 2)
  sizes <- as.vector(vapply(split(L$index * 2 + L$singleton, L$index * 2 + L$singleton),
                            length, 0))
  J <- length(sizes)
  multi <- sum(sizes >= 2)
  group_class <- zoo_count_class(sizes)
  arm_class <- zoo_count_class(c(sum(L$therapy), sum(!L$therapy)))
  ones <- matrix(1, P, 1L)
  gram <- list(X = cbind(ones, as.numeric(L$therapy)),
               terms = list(list(factor = L$index * 2 + L$singleton, columns = ones)))
  # The budget of group is J - k + r with k = 2 kept columns, the intercept
  # and arm, and r = 0, since arm is constant within every group. The groups
  # of one row are the cells that residual_confounding finds unreplicated,
  # and the groups of several rows are the levels that within_between reads.
  findings <- list(
    zoo_rd(2, "The intercept and arm are linearly independent."),
    zoo_db("group", group_class, J, J - 2, c("(Intercept)", "arm"),
           paste0("J - k + r = ", J, " - 2 + 0, since arm is constant within every group.")),
    zoo_gr(gram, paste0("The ", multi, " groups of ", size, " separate the group variance from ",
                        "the residual, as zoo_gram() computes.")),
    zoo_ld1("group", group_class, J,
            if (multi < J) "A group of one also informs the intercept, so every level counts."),
    zoo_finding(
      "identifiability.residual_confounding",
      scope = list(factor = "group", term = "1 | group"),
      finding = "consistent", message = "replicated",
      statistics = list(columns = zv(1), correlated = zv(FALSE),
                        pattern_terms = zv(zn("1 | group")), cells = zv(J, group_class),
                        replicated_cells = zv(multi, group_class), intercept_alone = zv(TRUE)),
      why = paste0(multi, " of the ", J, " groups hold two rows or more.")
    ),
    zoo_kd("participant", P, paste0("The ", P, " participant labels are distinct.")),
    zoo_lu("arm", arm_class),
    zoo_lu("group", group_class),
    zoo_lu("participant", "person"),
    zoo_sr(P),
    zoo_cs("group", group_class, sizes,
           why = paste0(sum(sizes == 1), " groups of one and ", multi, " of ", size, ".")),
    zoo_finding(
      "structure.within_between", list(factor = "group", term = "arm"),
      "consistent", "status",
      list(multi_row_levels = zv(multi, group_class), varying_levels = zv(0, group_class),
           informative_levels = zv(0, group_class), status = zv("between"),
           slope_requested = zv(FALSE), icc = za(), within_share = za()),
      why = paste0("arm is constant within each of the ", multi, " groups of several rows, ",
                   "and it is categorical, so icc is absent.")
    )
  )
  list(
    samples = list(table = zoo_sample(P), design = zoo_sample(P)),
    findings = findings
  )
}

zoo_Z10_parameters <- function(control_singletons) {
  list(participants = 64, therapy = 32, group_size = 8, control_singletons = control_singletons,
       sd_group = "0.5", sd_residual = "1", effect = "0.4", digits = 2)
}

zoo_define(
  id = "Z10", name = "partially-nested", title = "Partially nested trial",
  role = "fixture", matched = "Z10N", negative_of = character(0), domain = "education",
  catalogue = "L7-05",
  planted = paste("The 32 participants of the therapy arm were treated in 4 groups of 8, and",
                  "the 32 controls are coded as groups of one, so the group intercept spans",
                  "both arms of a partially nested design."),
  seed = 202611100, parameters = zoo_Z10_parameters(TRUE), generate = zoo_Z10,
  declaration = function(p) zoo_Z10_declaration(p, "Z10 Partially nested trial"),
  formula = function(p) "y ~ arm + (1 | group)",
  run = zoo_access("Z10", "T0"), expected = zoo_Z10_expected,
  signal = list(zoo_signal("structure.cluster_sizes", list(factor = "group"), "sizes",
                           list(singletons = 32))),
  planned = list(zoo_planned(
    "assignment.partial_nesting", "T0", "L7-05", "0.2", "M4", "Nothing beyond vocabulary 0.1.",
    paste("Level sizes by arm, and a random intercept that spans both arms of a design",
          "declared partially_nested.")
  ))
)

zoo_define(
  id = "Z10N", name = "fully-nested", title = "Fully nested trial",
  role = "negative", matched = "Z10", negative_of = "Z10", domain = "education",
  catalogue = "L7-05",
  planted = "The controls are also treated in 4 groups of 8, so every group holds 8 participants.",
  seed = 202611100, parameters = zoo_Z10_parameters(FALSE), generate = zoo_Z10,
  declaration = function(p) zoo_Z10_declaration(p, "Z10N Fully nested trial"),
  formula = function(p) "y ~ arm + (1 | group)",
  run = zoo_access("Z10N", "T0"), expected = zoo_Z10_expected,
  signal = list()
)
