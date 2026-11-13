# Z20 Unicode and white-space variants of identifiers, and its matched
# negative Z20N. In Z20, the subjects Jose and Zoe with their accents are
# spelled with composed characters for items i1 to i3 and decomposed ones for
# items i4 to i6, which the packages merge after NFC and labels.unicode_forms
# reports, and subject S1 is spelled ' s1' for items i4 to i6, a white-space
# and case variant that no check of registry 0.1.0 compares, so that it
# becomes a level of its own. The grouping columns are named Subject and item,
# which sort in one order by code point and in the other by the collation of
# most locales, and the expectations follow code-point order. In Z20N, every
# label is in NFC and S1 is spelled alike throughout. The R source holds no
# character outside ASCII: every label is built from its code points.

# The labels of the persons in row order, in NFC.
zoo_Z20_persons <- function() {
  points <- list(
    c(65L, 110L, 97L), c(66L, 101L, 110L), c(67L, 104L, 108L, 111L, 233L),
    c(74L, 111L, 115L, 233L), c(321L, 117L, 107L, 97L, 115L, 122L),
    c(201L, 109L, 105L, 108L, 101L), c(90L, 111L, 235L), c(122L, 97L, 114L, 97L),
    c(90L, 101L, 116L, 97L), c(214L, 108L, 109L, 101L, 122L), c(83L, 49L),
    c(84L, 111L, 109L, 225L, 115L)
  )
  vapply(points, function(x) enc2utf8(intToUtf8(x)), "")
}

# The variant spellings and the persons that take them: the decomposed forms
# of Jose and Zoe with their accents, which NFC merges with the composed
# ones, and ' s1' for S1, which differs from it in its code points.
zoo_Z20_variants <- function() {
  list(
    person = c(4L, 7L, 11L),
    spelling = vapply(list(c(74L, 111L, 115L, 101L, 769L), c(90L, 111L, 101L, 776L),
                           c(32L, 115L, 49L)),
                      function(x) enc2utf8(intToUtf8(x)), ""),
    merges = c(TRUE, TRUE, FALSE)
  )
}

# The rows: the person of each row, as an index into the labels, the item, as
# a number, and whether the row holds the variant spelling, which the
# variant persons take for the second half of the items.
zoo_Z20_design <- function(p) {
  P <- length(zoo_Z20_persons())
  I <- p$items
  person <- rep(seq_len(P), each = I)
  item <- rep(seq_len(I), times = P)
  variant <- p$variants & person %in% zoo_Z20_variants()$person & item > I / 2
  list(person = person, item = item, variant = variant)
}

# The data: Subject, item i1 onwards, cond 'a' for the odd items and 'b' for
# the even ones, and y, ordered by person, in the order of the parameter
# persons, which must be the labels of zoo_Z20_persons(), since the variant
# spellings belong to them, and item. Draws, in this order: the person effects in the order of
# persons, the item effects in item order and the residuals in row order. y
# is their sum, rounded to the stored grid, and the variant ' s1' shares the
# effect of S1. No property is drawn.
zoo_Z20 <- function(p, checks = "redraw", seed) {
  zoo_with_rng(seed, {
    design <- zoo_Z20_design(p)
    persons <- enc2utf8(as.character(unclass(p$persons)))
    stopifnot(identical(persons, zoo_Z20_persons()))
    variants <- zoo_Z20_variants()
    I <- p$items
    person_effect <- stats::rnorm(length(persons), 0, as.numeric(p$sd_subject))
    item_effect <- stats::rnorm(I, 0, as.numeric(p$sd_item))
    residual <- stats::rnorm(length(design$person), 0, as.numeric(p$sd_residual))
    alternative <- persons
    alternative[variants$person] <- variants$spelling
    data <- data.frame(
      Subject = ifelse(design$variant, alternative[design$person], persons[design$person]),
      item = zoo_label("i", design$item, I),
      cond = ifelse(design$item %% 2L == 1L, "a", "b"),
      y = zoo_round(person_effect[design$person] + item_effect[design$item] + residual,
                    p$digits)
    )
    zoo_check(data, list(), NULL, checks)
  })
}

zoo_Z20_declaration <- function(p, title) {
  list(
    vocabulary = "0.1.0",
    title = title,
    features = zn("crossed_experiment"),
    table = list(fields = list(
      list(name = "Subject", type = "string"),
      list(name = "item", type = "string"),
      list(name = "cond", type = "string", categories = zn("a", "b")),
      list(name = "y", type = "number")
    )),
    units = list(
      list(name = "Subject", columns = zn("Subject"), role = "participant"),
      list(name = "item", columns = zn("item"), role = "item")
    ),
    crossings = list(list(units = zn("Subject", "item"))),
    observation = list(key = zn("Subject", "item")),
    variables = list(y = list(role = "outcome", measurement = "continuous"))
  )
}

# The levels of Subject after NFC, as numbers: the persons, and one level
# more for the variant ' s1', which differs from S1 in its code points.
zoo_Z20_levels <- function(p) {
  design <- zoo_Z20_design(p)
  variants <- zoo_Z20_variants()
  apart <- design$variant & design$person %in% variants$person[!variants$merges]
  ifelse(apart, length(zoo_Z20_persons()) + match(design$person, variants$person), design$person)
}

# The design of identifiability.gram_rank: the columns (Intercept) and cond[b]
# and the random intercepts of Subject, by its levels after NFC, and item.
zoo_Z20_gram <- function(p) {
  design <- zoo_Z20_design(p)
  ones <- matrix(1, length(design$person), 1L)
  list(X = cbind(ones, as.numeric(design$item %% 2L == 0L)),
       terms = list(list(factor = zoo_Z20_levels(p), columns = ones),
                    list(factor = design$item, columns = ones)))
}

# The expected findings, from the parameters alone. The contributors are the
# levels of Subject after NFC, each one member of the disclosure unit, so the
# levels of Subject and the combinations of Subject and item resolve as
# person counts, and the levels of item and cond, which hold every person, as
# non-person counts. Every level of Subject, the variant ' s1' and S1 with
# three items each included, holds both conditions.
zoo_Z20_expected <- function(p, data) {
  I <- p$items
  stopifnot(I >= 4, I %% 2L == 0L, (I / 2) %% 2L == 1L)
  design <- zoo_Z20_design(p)
  levels <- zoo_Z20_levels(p)
  N <- length(levels)
  sizes <- as.vector(table(levels))
  J <- length(sizes)
  P <- "person"
  NP <- zoo_count_class(length(zoo_Z20_persons()))
  variants <- zoo_Z20_variants()
  merged <- if (p$variants) sum(variants$merges) else 0
  pair <- list(first = "Subject", second = "item")
  unicode <- if (merged > 0) {
    zoo_finding(
      "labels.unicode_forms", list(column = "Subject"), "detectable_inconsequential", "merged",
      list(spellings = zv(2 * merged, P), labels = zv(merged, P)),
      why = paste("Jose and Zoe with their accents are each spelled in a composed and a",
                  "decomposed form, which NFC merges.")
    )
  } else {
    zoo_finding(
      "labels.unicode_forms", list(column = "Subject"), "consistent", "distinct",
      list(spellings = zv(0, P), labels = zv(0, P)),
      why = "Every label of Subject is in NFC, so no two spellings merge."
    )
  }
  crossed <- J * I == N
  findings <- c(
    zoo_na3(),
    list(
      zoo_rd(2, "The columns (Intercept) and cond[b] are linearly independent."),
      zoo_db("Subject", P, J, J - 1, "(Intercept)",
             paste0("J - k + r = ", J, " - 2 + 1, since cond varies within every level of ",
                    "Subject, the variant ' s1' included.")),
      zoo_db("item", NP, I, I - 2, c("(Intercept)", "cond"),
             paste0("J - k + r = ", I, " - 2 + 0, since cond is constant within every item.")),
      zoo_gr(zoo_Z20_gram(p), paste0(
        "The Subject, item and residual variances of ", J, " levels of Subject crossed with ",
        I, " items, as zoo_gram() computes them."
      )),
      zoo_ld1("Subject", P, J),
      zoo_ld1("item", NP, I),
      zoo_rc1("Subject", P, J, paste0("Every level of Subject holds ", min(sizes),
                                      " rows or more.")),
      zoo_rc1("item", NP, I, paste0(N / I, " rows in each level.")),
      zoo_kd(c("Subject", "item"), N,
             paste("After NFC, the two spellings of a person hold different items, and S1 and",
                   "' s1' are different values, so no key repeats.")),
      unicode,
      zoo_lu("cond", NP),
      zoo_lu("item", NP),
      zoo_sr(N),
      zoo_finding(
        "structure.aliased_factors", pair, "consistent", "distinct",
        list(partition = zv("other"), shared_columns = zv(TRUE), finer = zv(zn()),
             coarser = zv(zn()), coarser_levels = za(), informative_levels = za(),
             rows = zv(N), informative_rows = za()),
        why = paste("Every level of Subject meets several items and every item several levels",
                    "of Subject, and both terms have the intercept.")
      ),
      zoo_cs("Subject", P, sizes,
             why = paste0(sum(sizes == I), " levels of Subject with ", I, " rows and ",
                          sum(sizes < I), " with ", I / 2, ".")),
      zoo_cs("item", NP, rep(N / I, I)),
      zoo_finding(
        "structure.connectivity", pair, "consistent", "connected",
        list(components = zv(1, P), between_component_terms = zv(zn()), exact = zv(TRUE)),
        why = paste("Every level of Subject meets three items or more, so the crossing forms",
                    "one component.")
      ),
      zoo_finding(
        "structure.label_incidence", pair, "consistent", "relation",
        list(levels_first = zv(J, P), levels_second = zv(I, NP), combinations = zv(N, P),
             first_in_several = zv(J, P), second_in_several = zv(I, NP),
             relation = zv(if (crossed) "crossed" else "partially_crossed"),
             declared = zv("crossed"), inner = zv(zn()), outer = zv(zn()),
             inner_in_several = za(), composite = zv(FALSE), inner_alone = zv(FALSE)),
        why = if (crossed) {
          paste0("All ", N, " combinations of ", J, " persons and ", I, " items occur.")
        } else {
          paste0(N, " of the ", J * I, " combinations occur, since S1 and ' s1' hold ", I / 2,
                 " items each.")
        }
      ),
      zoo_finding(
        "structure.within_between", list(factor = "Subject", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(J, P), varying_levels = zv(J, P),
             informative_levels = zv(J, P), status = zv("within"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Every level of Subject holds items of both conditions, and cond is categorical."
      ),
      zoo_finding(
        "structure.within_between", list(factor = "item", term = "cond"), "consistent",
        "status",
        list(multi_row_levels = zv(I, NP), varying_levels = zv(0, NP),
             informative_levels = zv(0, NP), status = zv("between"),
             slope_requested = zv(FALSE), icc = za(), within_share = za()),
        why = "Each item belongs to one condition, and cond is categorical."
      )
    )
  )
  list(samples = list(table = zoo_sample(N, J), design = zoo_sample(N, J)),
       findings = findings)
}

zoo_Z20_parameters <- function(variants) {
  list(persons = zn(zoo_Z20_persons()), items = 6, variants = variants, sd_subject = "0.5",
       sd_item = "0.3", sd_residual = "1", digits = 2)
}

zoo_Z20_planned <- list(zoo_planned(
  "labels.near_duplicates", "T0", c("L1-20", "L6-08"), "0.2", "M4",
  "Nothing beyond vocabulary 0.1.",
  "Labels of a column that differ only in case or white space."
))

zoo_define(
  id = "Z20", name = "unicode-id-variants",
  title = "Unicode and white-space variants of identifiers",
  role = "fixture", matched = "Z20N", negative_of = character(0), domain = "any",
  catalogue = c("L1-20", "L6-08"),
  planted = paste("Two subjects are spelled in composed and decomposed Unicode forms, which NFC",
                  "merges, and S1 is spelled ' s1' for three items, a level of its own."),
  seed = 202611200, parameters = zoo_Z20_parameters(TRUE), generate = zoo_Z20,
  declaration = function(p) {
    zoo_Z20_declaration(p, "Z20 Unicode and white-space variants of identifiers")
  },
  formula = function(p) "y ~ cond + (1 | Subject) + (1 | item)",
  run = zoo_access("Z20", "T0"), expected = zoo_Z20_expected,
  signal = list(zoo_signal("labels.unicode_forms", list(column = "Subject"), "merged")),
  planned = zoo_Z20_planned
)

zoo_define(
  id = "Z20N", name = "clean-ids", title = "Identifiers in one Unicode form",
  role = "negative", matched = "Z20", negative_of = "Z20", domain = "any",
  catalogue = c("L1-20", "L6-08"),
  planted = "Every label is in NFC, and S1 is spelled alike for all six items.",
  seed = 202611200, parameters = zoo_Z20_parameters(FALSE), generate = zoo_Z20,
  declaration = function(p) zoo_Z20_declaration(p, "Z20N Identifiers in one Unicode form"),
  formula = function(p) "y ~ cond + (1 | Subject) + (1 | item)",
  run = zoo_access("Z20N", "T0"), expected = zoo_Z20_expected,
  signal = list()
)
