# The structure checks, in the parts that the audit corpus cannot reach: the
# tolerance of the parameter agreement, which tables of 40 rows cannot test,
# the connected components, the intraclass correlation, quantiles of more
# levels and grouping factors of several columns.

structure_key <- paste(sprintf("%02x", 0:31), collapse = "")

# The findings of one check for an audit in internal mode.
structure_findings <- function(data, formula, check, ...) {
  results <- audit(data, formula, ..., privacy = "internal", key = structure_key)
  Filter(function(finding) finding$check == check, results$document$findings)
}

statistic_values <- function(finding) {
  lapply(finding$statistics, function(statistic) statistic$value)
}

test_that("structure.within_between infers a between term with the tolerance of agreement", {
  # Ten schools of 20 rows, with x constant within each school but one row:
  # 199 of the 200 rows have the most frequent pattern of their school, and
  # 199 x 100 >= 99 x 200.
  school <- rep(sprintf("S%02d", 1:10), each = 20)
  x <- rep(1:10, each = 20)
  x[5L] <- 7
  data <- data.frame(y = seq_along(x), x = x, school = school)
  found <- structure_findings(data, "y ~ x + (1 + x | school)", "structure.within_between")[[1L]]
  values <- statistic_values(found)
  expect_identical(values$status, "between")
  expect_identical(values$varying_levels, 1)
  expect_identical(found$status$finding$value, "detectable_inconsequential")
  expect_identical(found$message$id, "between_slope")
  # Three miscoded rows leave 197 of 200, below the agreement.
  x[c(25L, 45L)] <- 9
  data$x <- x
  found <- structure_findings(data, "y ~ x + (1 + x | school)", "structure.within_between")[[1L]]
  expect_identical(statistic_values(found)$status, "partially_within")
  expect_identical(found$message$id, "partial_slope")
})

test_that("structure.connectivity lists a term constant with the tolerance of agreement as inexact", {
  # Two blocks of ten subjects crossed with ten items that no row links, and
  # 'group' constant within each block but one row.
  block <- function(subjects, items) {
    expand.grid(item = items, subject = subjects, stringsAsFactors = FALSE)
  }
  data <- rbind(block(sprintf("s%02d", 1:10), sprintf("i%02d", 1:10)),
                block(sprintf("s%02d", 11:20), sprintf("i%02d", 11:20)))
  data$group <- rep(c("A", "B"), each = 100)
  data$group[3L] <- "B"
  data$x <- seq_len(200) %% 7
  data$y <- seq_len(200)
  found <- structure_findings(data, "y ~ x + group + (1 | subject) + (1 | item)",
                              "structure.connectivity")[[1L]]
  values <- statistic_values(found)
  expect_identical(values$components, 2)
  expect_identical(values$between_component_terms, list("group"))
  expect_false(values$exact)
  expect_identical(found$status$finding$value, "detectable_inconsequential")
  expect_identical(found$message$id, "confounded")
  # Exactly constant within each block, the finding is consequential.
  data$group[3L] <- "A"
  found <- structure_findings(data, "y ~ x + group + (1 | subject) + (1 | item)",
                              "structure.connectivity")[[1L]]
  expect_true(statistic_values(found)$exact)
  expect_identical(found$status$finding$value, "consequential")
})

test_that("structure.id_scope_evidence keeps an attribute constant within 99% of the combinations", {
  # 60 pupils, each once in each of two schools, with one more row in which
  # pupil p01 has the other sex at S1: sex is constant within 119 of the 120
  # combinations. stype is constant within each school, so it is a candidate
  # only when the schools are the labels, where it changes for none.
  pupils <- sprintf("p%02d", 1:60)
  sex <- rep(c("F", "M"), 30)
  data <- data.frame(pupil = rep(pupils, 2), school = rep(c("S1", "S2"), each = 60),
                     sex = rep(sex, 2), stype = rep(c(1, 2), each = 60))
  data <- rbind(data, data.frame(pupil = "p01", school = "S1", sex = "M", stype = 1))
  data$y <- seq_len(nrow(data))
  found <- structure_findings(data, "y ~ sex + stype + (1 | school) + (1 | pupil)",
                              "structure.id_scope_evidence")[[1L]]
  values <- statistic_values(found)
  expect_identical(values$labels_column, list("pupil"))
  expect_identical(values$attributes, list("sex"))
  expect_identical(values$changing_labels, 1)
  expect_identical(values$shared_labels, 60)
  expect_false(values$tied)
  expect_identical(found$message$id, "some_change")
  expect_identical(found$status$finding$value, "detectable_inconsequential")
})

test_that("connected components agree with a breadth-first search", {
  components <- mixedcheck:::bipartite_components
  search <- function(a, b, count_a, count_b) {
    found <- integer(count_a + count_b)
    v <- c(a, count_a + b)
    w <- c(count_a + b, a)
    k <- 0L
    for (start in seq_along(found)) {
      if (found[start]) {
        next
      }
      k <- k + 1L
      found[start] <- k
      frontier <- start
      while (length(frontier)) {
        reached <- unique(w[v %in% frontier])
        frontier <- reached[!found[reached]]
        found[frontier] <- k
      }
    }
    found
  }
  set.seed(9)
  for (trial in 1:50) {
    count_a <- sample(1:15, 1)
    count_b <- sample(1:15, 1)
    m <- sample(1:25, 1)
    a <- c(seq_len(count_a), sample(count_a, count_b + m, TRUE))
    b <- c(sample(count_b, count_a, TRUE), seq_len(count_b), sample(count_b, m, TRUE))
    expect_identical(components(a, b, count_a, count_b), search(a, b, count_a, count_b))
  }
  # A path through 2,000 levels with shuffled numbers is one component.
  first <- sample(1000)
  second <- sample(1000)
  path <- components(c(first, first[-1L]), c(second, second[-1000L]), 1000L, 1000L)
  expect_true(all(path == 1))
})

test_that("structure.connectivity resolves its components by the levels of interaction factors", {
  data <- data.frame(
    y = 1:8,
    subject = c("s1", "s1", "s2", "s2", "s3", "s3", "s4", "s4"),
    item = c("i1", "i2", "i1", "i2", "i1", "i2", "i1", "i2"),
    session = c("a", "a", "a", "a", "b", "b", "b", "b")
  )
  declaration <- list(vocabulary = "0.1.0", units = list(
    list(name = "subject", columns = list("subject"), role = "participant")
  ))
  found <- structure_findings(data, "y ~ 1 + (1 | subject) + (1 | item:session)",
                              "structure.connectivity", declaration = declaration)[[1L]]
  expect_identical(found$scope, list(first = "item:session", second = "subject"))
  expect_identical(found$statistics$components$value, 2)
  expect_identical(found$statistics$components$count_class, "person")
  expect_identical(found$message$id, "disconnected")
})

test_that("structure.cluster_sizes takes the quantiles at positions ceil(J x p)", {
  # Seven levels of 1 to 7 rows: positions ceil(7/4) = 2, ceil(7/2) = 4 and
  # ceil(21/4) = 6.
  g <- rep(sprintf("g%d", 1:7), 1:7)
  data <- data.frame(y = seq_along(g), g = g)
  values <- statistic_values(structure_findings(data, "y ~ 1 + (1 | g)",
                                                "structure.cluster_sizes")[[1L]])
  expect_identical(values[c("smallest", "lower_quartile", "median", "upper_quartile", "largest")],
                   list(smallest = 1, lower_quartile = 2, median = 4, upper_quartile = 6,
                        largest = 7))
  expect_identical(values$effective_size, (28 - 140 / 28) / 6)
})

test_that("the intraclass correlation follows its definition", {
  set.seed(4)
  g <- sample(sprintf("g%d", 1:6), 40L, TRUE)
  x <- round(rnorm(40) + match(g, sort(unique(g))), 2)
  data <- data.frame(y = seq_along(x), x = x, g = g)
  values <- statistic_values(structure_findings(data, "y ~ x + (1 | g)",
                                                "structure.within_between")[[1L]])
  sizes <- as.vector(table(g))
  means <- as.vector(tapply(x, g, mean))
  ssb <- sum(sizes * (means - mean(x))^2)
  ssw <- sum((x - ave(x, g))^2)
  msb <- ssb / 5
  msw <- ssw / 34
  n0 <- (40 - sum(sizes^2) / 40) / 5
  expect_equal(values$icc, (msb - msw) / (msb + (n0 - 1) * msw), tolerance = 1e-12)
  expect_equal(values$within_share, ssw / (ssb + ssw), tolerance = 1e-12)
})

test_that("every structure check has its function", {
  ids <- grep("^structure[.]", names(registry_entries_by_id()), value = TRUE)
  expect_length(ids, 6L)
  expect_true(all(ids %in% implemented_checks()))
})
