# declaration(), the declare_*() builders and draft_design()
# (02-decisions.md, Q4, and docs/spec/declarations.md).

test_that("the builders write the JSON of a hand-written declaration", {
  built <- declaration(
    units = list(declare_unit("school", "school", role = "cluster"),
                 declare_unit("pupil", "pupil", nested_in = "school", id_scope = "global",
                              role = "participant")),
    observation = declare_observation(key = "pupil", unit = "pupil", time_column = "wave",
                                      time_kind = "occasion", time_within = "pupil"),
    assignment = list(declare_assignment("arm", "school", randomised = TRUE,
                                         level = "between_unit")),
    variables = list(score = declare_variable("outcome", measurement = "bounded_score",
                                              bounds = c(0, 40)),
                     arm = declare_variable("assigned")),
    estimands = list(declare_estimand("itt", "arm", kind = "total_effect", focal = TRUE)),
    features = c("cluster_randomised", "longitudinal"),
    title = "Tutoring trial"
  )
  text <- paste0(
    '{"assignment":[{"column":"arm","level":"between_unit","randomised":true,"unit":"school"}],',
    '"estimands":[{"focal":true,"id":"itt","kind":"total_effect","term":"arm"}],',
    '"features":["cluster_randomised","longitudinal"],',
    '"observation":{"key":["pupil"],"time":{"column":"wave","kind":"occasion","within":"pupil"},',
    '"unit":"pupil"},"title":"Tutoring trial",',
    '"units":[{"columns":["school"],"name":"school","role":"cluster"},',
    '{"columns":["pupil"],"id_scope":"global","name":"pupil","nested_in":"school",',
    '"role":"participant"}],',
    '"variables":{"arm":{"role":"assigned"},"score":{"bounds":[0,40],',
    '"measurement":"bounded_score","role":"outcome"}},"vocabulary":"0.1.0"}'
  )
  expect_identical(rawToChar(canonical_bytes(built, "hashable")), text)
  expect_identical(canonical_hash(built, "hashable"),
                   "sha256:51dad8b2dd49cbc777ebc73b908a60d87d8b6e60f12f64053c6eca5c5a694ef9")
})

test_that("the builders check their arguments and the declaration", {
  expect_error(declare_unit("school", 1), "'columns'")
  expect_error(declare_assignment("arm", "school", randomised = "yes"), "'randomised'")
  expect_error(declare_variable("outcome", bounds = 1), "'bounds'")
  problem <- tryCatch(declaration(units = list(declare_unit("pupil", "pupil",
                                                            nested_in = "class",
                                                            id_scope = "global"))),
                      mixedcheck_error = function(e) e)
  expect_identical(problem$issues[[1L]]$code, "E2006")
  minimal <- tryCatch(declaration(units = list(declare_unit("pupil", "pupil")), minimal = TRUE),
                      mixedcheck_error = function(e) e)
  expect_identical(minimal$issues[[1L]]$code, "E2028")
})

test_that("a draft marks every entry it infers and reads no outcome", {
  data <- data.frame(
    school = rep(c("A", "B"), each = 6),
    class = rep(c("1", "2", "3"), times = 4),
    pupil = sprintf("p%02d", 1:12),
    x = seq_len(12),
    y = NA_real_,
    stringsAsFactors = FALSE
  )
  draft <- with_audit_time(draft_design(data, "y ~ x + (1 | school/class) + (1 | pupil)"), "0")
  expect_identical(vapply(draft$units, function(u) u$name, ""), c("school", "class", "pupil"))
  # Class labels reused in every school look crossed with the schools, and
  # the draft does not take '/' to settle id_scope.
  expect_null(draft$units[[2L]]$nested_in)
  expect_identical(draft$crossings, list(list(units = list("school", "class"))))
  # Each pupil meets one class and one school, and the class has more labels.
  expect_identical(draft$units[[3L]]$nested_in, "class")
  expect_identical(draft$units[[3L]]$id_scope, "global")
  expect_identical(unlist(draft$observation$key), "pupil")
  expect_identical(draft$variables$y, list(role = "outcome"))
  expect_identical(unlist(draft$provenance$inferred),
                   c("/units/0", "/units/1", "/units/2", "/crossings/0", "/observation/key",
                     "/variables/y"))
  expect_identical(draft$provenance$created, "1970-01-01T00:00:00Z")
  # A draft is not a minimal declaration.
  problem <- tryCatch(validate_declaration(draft, minimal = TRUE),
                      mixedcheck_error = function(e) e)
  expect_true("E2032" %in% vapply(problem$issues, function(i) i$code, ""))
})

test_that("a draft makes no unit of a predictor in a grouping", {
  data <- expand.grid(f = c("a", "b", "c"), g = sprintf("g%d", 1:4), stringsAsFactors = FALSE)
  data$y <- NA_real_
  draft <- draft_design(data, "y ~ f + (1 | g) + (1 | g:f)")
  expect_identical(vapply(draft$units, function(u) u$name, ""), "g")
})

test_that("a draft finds crossed units", {
  data <- expand.grid(subject = c("s1", "s2", "s3"), item = c("i1", "i2"),
                      stringsAsFactors = FALSE)
  data$y <- NA_real_
  draft <- draft_design(data, "y ~ 1 + (1 | subject) + (1 | item)")
  expect_identical(draft$crossings, list(list(units = list("subject", "item"))))
  expect_identical(unlist(draft$observation$key), c("subject", "item"))
})
