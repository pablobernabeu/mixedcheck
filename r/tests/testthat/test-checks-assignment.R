# The assignment checks, in the parts that the audit corpus cannot reach:
# the tolerance of the parameter agreement, which tables of 40 rows cannot
# test, design_df against the literal sequential rule on the indicator
# columns, and the members of the assignment block that /provenance/inferred
# marks.

assignment_key <- paste(sprintf("%02x", 0:31), collapse = "")

# The findings of the assignment checks for an audit in internal mode.
assignment_findings <- function(data, formula, declaration, check) {
  results <- audit(data, formula, declaration, privacy = "internal", key = assignment_key)
  Filter(function(finding) finding$check == check, results$document$findings)
}

assignment_values <- function(finding) {
  lapply(finding$statistics, function(statistic) statistic$value)
}

class_declaration <- function(...) {
  list(vocabulary = "0.1.0",
       units = list(list(name = "class", columns = list("class"), role = "cluster")),
       assignment = list(c(list(column = "arm", unit = "class", randomised = TRUE), list(...))))
}

test_that("an assignment without a declared level is inferred with the tolerance of agreement", {
  # Ten classes of 20 rows, arm constant within each class but one row: 199
  # of the 200 rows have the most frequent value of their class, and
  # 199 x 100 >= 99 x 200, so the level is between_unit and the mixed class
  # is reported.
  class <- rep(sprintf("c%02d", 1:10), each = 20)
  arm <- rep(rep(c("T", "C"), 5), each = 20)
  arm[7L] <- "C"
  data <- data.frame(y = seq_along(arm), arm = arm, class = class)
  found <- assignment_findings(data, "y ~ arm + (1 | class)", class_declaration(),
                               "assignment.constant_within_unit")[[1L]]
  values <- assignment_values(found)
  expect_identical(values$level_source, "inferred_from_the_data")
  expect_identical(values$units, 10)
  expect_identical(values$mixed_units, 1)
  expect_identical(found$status$finding$value, "consequential")
  expect_match(found$message$text, "1 of the 10 levels of 'class'.*inferred from the data")
  # Three miscoded rows leave 197 of 200, below the agreement, so the level
  # is within_unit and no check applies.
  data$arm[c(27L, 47L)] <- c("T", "C")
  expect_length(assignment_findings(data, "y ~ arm + (1 | class)", class_declaration(),
                                    "assignment.constant_within_unit"), 0L)
})

test_that("assignment.design_df equals the indicator columns that the sequential rule keeps", {
  for (seed in 1:4) {
    set.seed(seed)
    classes <- 12
    size <- sample(3:5, classes, replace = TRUE)
    class <- rep(sprintf("c%02d", seq_len(classes)), size)
    school <- rep(rep(c("S1", "S2", "S3"), each = 4), size)
    arm <- rep(rep(c("T", "C"), 6), size)
    # A class-level covariate with values that level means do not give back
    # exactly, and a pupil-level covariate.
    z <- rep(round(runif(classes), 1) + 0.1, size)
    data <- data.frame(y = seq_along(class), arm = arm, school = school, class = class, z = z,
                       x = rnorm(length(class)))
    for (formula in c("y ~ arm + (1 | class)", "y ~ arm + school + z + (1 | class)",
                      "y ~ arm * z + x + (1 | class)")) {
      found <- assignment_findings(data, formula, class_declaration(level = "between_unit"),
                                   "assignment.design_df")[[1L]]
      matrices <- design_matrices(formula_ir(formula, data = data), data)
      indicators <- outer(data$class, sprintf("c%02d", seq_len(classes)), "==") * 1
      kept <- sequential_rule(cbind(matrices$x, indicators))
      expect_identical(assignment_values(found)$design_df,
                       as.double(sum(kept[-seq_len(ncol(matrices$x))])), label = formula)
    }
  }
})

test_that("members of the assignment block that /provenance/inferred lists count as absent", {
  data <- data.frame(
    y = 1:12,
    arm = rep(c("T", "C", "T", "C"), each = 3),
    school = rep(c("S1", "S2"), each = 6),
    class = rep(c("c1", "c2", "c3", "c4"), each = 3)
  )
  declaration <- class_declaration(level = "between_unit", blocks = list("school"))
  declaration$units <- c(list(list(name = "school", columns = list("school"), role = "cluster")),
                         declaration$units)
  findings <- function(check, inferred) {
    if (length(inferred)) {
      declaration$provenance <- list(inferred = as.list(inferred))
    }
    assignment_findings(data, "y ~ arm + (1 | school)", declaration, check)
  }
  # The block as a whole: no check is available.
  found <- findings("assignment.design_df", "/assignment")[[1L]]
  expect_identical(found$status$availability[c("value", "reason", "detail")],
                   list(value = "not_available", reason = "declaration_missing",
                        detail = "/assignment"))
  # The level is inferred from the data.
  found <- findings("assignment.constant_within_unit", "/assignment/0/level")[[1L]]
  expect_identical(assignment_values(found)$level_source, "inferred_from_the_data")
  # Without randomised, assignment.unit_in_random_part does not apply.
  expect_length(findings("assignment.unit_in_random_part", character(0)), 1L)
  expect_length(findings("assignment.unit_in_random_part", "/assignment/0/randomised"), 0L)
  # Without blocks, no block is missing.
  found <- findings("assignment.design_df", character(0))[[1L]]
  expect_identical(assignment_values(found)$missing_blocks, list("school"))
  found <- findings("assignment.design_df", "/assignment/0/blocks")[[1L]]
  expect_identical(assignment_values(found)$missing_blocks, list())
  # An assignment to a unit that counts as absent yields no finding.
  expect_length(findings("assignment.constant_within_unit", "/units/1"), 0L)
})

test_that("assignment.unit_in_random_part compares partitions over the rows of the assignment", {
  # The random intercept is on 'room', which divides the rows like the
  # classes except in a row whose arm is missing, which is not a row of the
  # assignment.
  data <- data.frame(
    y = 1:9,
    arm = c("T", "T", NA, "C", "C", "C", "T", "T", "T"),
    class = rep(c("c1", "c2", "c3"), each = 3),
    room = c("r1", "r1", "r9", "r2", "r2", "r2", "r3", "r3", "r3")
  )
  found <- assignment_findings(data, "y ~ (1 | room)", class_declaration(level = "between_unit"),
                               "assignment.unit_in_random_part")[[1L]]
  expect_identical(assignment_values(found)$coverage, "present")
  expect_identical(found$support$rows$value, 9)
})

test_that("every assignment check has its function", {
  ids <- grep("^assignment[.]", names(registry_entries_by_id()), value = TRUE)
  expect_length(ids, 3L)
  expect_true(all(ids %in% implemented_checks()))
})
