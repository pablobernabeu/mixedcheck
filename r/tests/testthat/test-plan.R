# design_plan(), validate_plan(), preregistration_text() and audit() bound
# to a plan (docs/spec/documents.md, Plan, version 0.1, and Access log).

plan_key_hex <- paste(sprintf("%02x", 0:31), collapse = "")

plan_at_zero <- function(...) {
  with_audit_time(design_plan(...), "0")
}

audit_at_zero <- function(data, formula, ..., privacy = "internal") {
  with_audit_time(audit(data, formula, ..., privacy = privacy, key = plan_key_hex), "0")
}

audit_issue <- function(...) {
  tryCatch({
    audit_at_zero(...)
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

plan_issue <- function(...) {
  tryCatch({
    plan_at_zero(...)
    NULL
  }, mixedcheck_error = function(e) e$issues[[1L]])
}

# Subjects crossed with items, a focal condition of two levels within both,
# a covariate that varies between items, a factor of three levels within
# subjects and a second row of every cell, so that every slope is identified.
crossed_data <- function() {
  grid <- expand.grid(item = sprintf("i%02d", 1:8), subject = sprintf("s%02d", 1:12),
                      rep = 1:2, stringsAsFactors = FALSE)
  grid$cond <- ifelse((match(grid$item, unique(grid$item)) + grid$rep) %% 2 == 0, "a", "b")
  grid$freq <- match(grid$item, unique(grid$item)) / 4
  grid$block <- c("x", "y", "z")[(match(grid$subject, unique(grid$subject)) + grid$rep +
                                    match(grid$item, unique(grid$item))) %% 3 + 1]
  grid$rt <- NA_real_
  grid
}

crossed_declaration <- function(estimands = TRUE) {
  declaration(
    units = list(declare_unit("subject", "subject", role = "participant"),
                 declare_unit("item", "item", role = "item")),
    crossings = list(declare_crossing(c("subject", "item"))),
    observation = declare_observation(key = c("subject", "item", "rep")),
    variables = list(rt = declare_variable("outcome", measurement = "continuous"),
                     cond = declare_variable("assigned")),
    estimands = if (estimands) list(declare_estimand("cond", "cond", kind = "total_effect")),
    features = "crossed_experiment"
  )
}

test_that("a protected plan validates, records its hashes and ends at the protected rung", {
  plan <- plan_at_zero(crossed_data(), "rt ~ cond + freq + (1 | subject) + (1 | item)",
                       crossed_declaration())
  expect_identical(validate_plan(plan), plan)
  expect_identical(plan$created, "1970-01-01T00:00:00Z")
  expect_identical(plan$design$ladder, "protected")
  expect_identical(plan$rule_evidence, "simulated_conditions_only")
  expect_false(plan$for_preregistration)
  expect_identical(plan$design_plan_hash, canonical_hash(plan$design, "hashable"))
  expect_identical(plan$design$declaration_hash,
                   canonical_hash(crossed_declaration(), "hashable"))
  # freq varies between items, so the ceiling gives it a slope by subject only.
  ceiling <- vapply(plan$ceiling$ir$random, function(t) t$name, "")
  expect_identical(ceiling, c("1 + cond + freq | subject", "1 + cond | item"))
  steps <- vapply(plan$design$rungs[-1L], function(r) r$step$kind, "")
  expect_identical(steps, c("decorrelate", "decorrelate", "drop_terms"))
  last <- plan$design$rungs[[length(plan$design$rungs)]]$ir
  expect_identical(vapply(last$random, function(t) t$name, ""),
                   c("1 | subject", "0 + cond | subject", "1 | item", "0 + cond | item"))
  reasons <- vapply(plan$design$protected, function(c) c$reason, "")
  expect_identical(reasons, c("replication_unit", "replication_unit", "focal_slope",
                              "focal_slope"))
  expect_length(plan$verdicts, length(plan$design$rungs))
})

test_that("every rung freezes the factors and reads the columns of the ceiling", {
  plan <- plan_at_zero(crossed_data(), "rt ~ cond + freq + (1 | subject) + (1 | item)",
                       crossed_declaration())
  for (rung in plan$design$rungs) {
    expect_true(rung$ir$predictors$cond$frozen)
    expect_null(rung$ir$sample_columns)
  }
  dropped <- plan_at_zero(crossed_data(), "rt ~ cond + (1 | subject) + (1 | item)",
                          crossed_declaration(estimands = FALSE))
  expect_identical(dropped$design$ladder, "exploratory")
  expect_null(dropped$design$protected)
  expect_null(dropped$rule_evidence)
  # An exploratory ladder keeps every random intercept.
  last <- dropped$design$rungs[[length(dropped$design$rungs)]]$ir
  expect_identical(vapply(last$random, function(t) t$name, ""), c("1 | subject", "1 | item"))
})

test_that("the outcome is never read", {
  data <- crossed_data()
  formula <- "rt ~ cond + freq + (1 | subject) + (1 | item)"
  blind <- plan_at_zero(data, formula, crossed_declaration())
  data$rt <- seq_len(nrow(data)) * 1.5
  seen <- plan_at_zero(data, formula, crossed_declaration())
  expect_identical(seen$design_plan_hash, blind$design_plan_hash)
  expect_identical(seen$ceiling, blind$ceiling)
})

test_that("a factor slope of three levels becomes complex random intercepts", {
  plan <- plan_at_zero(crossed_data(), "rt ~ block + (1 | subject)")
  kinds <- vapply(plan$design$rungs[-1L], function(r) r$step$kind, "")
  expect_identical(kinds[1L], "complex_intercepts")
  second <- vapply(plan$design$rungs[[2L]]$ir$random, function(t) t$name, "")
  expect_identical(second, c("1 | subject", "1 | subject:block"))
})

test_that("rung 0 leaves out what the design does not identify", {
  # One row for each subject and condition: the slope is confounded with the
  # residual.
  data <- expand.grid(cond = c("a", "b"), subject = sprintf("s%02d", 1:20),
                      stringsAsFactors = FALSE)
  data$y <- NA_real_
  plan <- plan_at_zero(data, "y ~ cond + (1 | subject)")
  expect_identical(plan$ceiling$excluded,
                   list(list(factor = "subject", term = "0 + cond | subject")))
  expect_identical(vapply(plan$design$rungs[[1L]]$ir$random, function(t) t$name, ""),
                   "1 | subject")
})

test_that("the counts of the ceiling follow the privacy filter", {
  fixture <- pathology_zoo("Z05N")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration)
  subject <- plan$ceiling$factors[[1L]]
  expect_identical(subject$levels, 16)
  expect_identical(subject$terms[[1L]]$informative_groups, list(suppressed = "secondary"))
})

test_that("design_plan() refuses what it cannot plan", {
  data <- crossed_data()
  expect_identical(plan_issue(data, "rt ~ cond")$code, "E7315")
  bad <- crossed_declaration()
  bad$estimands[[1L]]$term <- "freq"
  expect_identical(plan_issue(data, "rt ~ cond + (1 | subject)", bad)$code, "E7314")
  draft <- crossed_declaration()
  draft$provenance <- list(inferred = list("/units/0"))
  expect_identical(plan_issue(data, "rt ~ cond + (1 | subject)", draft)$code, "E2032")
  expect_identical(plan_issue(data, "rt ~ cond + (1 | subject) + (1 | item)",
                              crossed_declaration(), terminal = "cluster_robust_cr2")$code,
                   "E7309")
  expect_error(design_plan(data, "rt ~ cond + (1 | subject)", rule = "aic"), "'rule'")
  # The randomisation unit of fixture Z08 is not a grouping factor.
  fixture <- pathology_zoo("Z08")
  expect_identical(plan_issue(fixture$data, fixture$formula, fixture$declaration)$code, "E7316")
  # The school of fixture Z21 has no degrees of freedom left.
  fixture <- pathology_zoo("Z21")
  issue <- plan_issue(fixture$data, fixture$formula, fixture$declaration)
  expect_identical(issue$code, "E7311")
  expect_match(issue$message, "'1' of 'school'")
})

test_that("the stopping rules and terminal states are written with their parameters", {
  fixture <- pathology_zoo("Z30N")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration,
                       rule = "protected_lrt", outcome_access = "T1")
  expect_identical(plan$design$rule, list(id = "protected_lrt", parameters = list(alpha = "0.2"),
                                          version = 1))
  expect_identical(plan$outcome_access, "T1")
  nested <- plan_at_zero(pathology_zoo("Z02N")$data, "y ~ wave + (1 | school/pupil)",
                         terminal = "cluster_robust_cr2")
  expect_identical(nested$design$ladder, "exploratory")
})

test_that("the lme4 binding encodes every rung over the columns of X", {
  skip_if_not_installed("lme4")
  fixture <- pathology_zoo("Z30")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration)
  binding <- plan$bindings[[1L]]
  expect_identical(binding$hash, canonical_hash(binding$binding, "hashable"))
  expect_identical(binding$binding$engine$name, "lme4")
  expect_identical(binding$binding$rungs[[2L]]$encoding,
                   "`y` ~ 1 + `arm[treatment]` + (1 | `site`) + (0 + `arm[treatment]` | `site`)")
})

test_that("validate_plan() reports the rules in code", {
  fixture <- pathology_zoo("Z30")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration)
  codes <- function(p) {
    tryCatch({
      validate_plan(p)
      character(0)
    }, mixedcheck_error = function(e) vapply(e$issues, function(i) paste(i$code, i$pointer), ""))
  }
  edited <- plan
  edited$design$rule$parameters <- list(alpha = "0.05")
  expect_identical(codes(edited), "E1321 /design_plan_hash")
  edited <- plan
  edited$verdicts <- edited$verdicts[1L]
  expect_identical(codes(edited), "E7303 /verdicts")
  edited <- plan
  edited$verdicts[[1L]]$value <- "not_identified"
  expect_identical(codes(edited), "E7304 /verdicts/0")
  edited <- plan
  edited$ceiling$factors[[2L]] <- edited$ceiling$factors[[1L]]
  expect_identical(codes(edited), "E7308 /ceiling/factors/1/factor")
  edited <- plan
  edited$ceiling$ir$fixed$terms[[2L]]$name <- "arms"
  expect_identical(codes(edited), "E6101 /ceiling/ir/fixed/terms/1/name")
  # Without lme4, the plan has no binding to edit.
  if (length(plan$bindings)) {
    edited <- plan
    edited$bindings[[1L]]$binding$rungs <- edited$bindings[[1L]]$binding$rungs[1L]
    edited$bindings[[1L]]$hash <- canonical_hash(edited$bindings[[1L]]$binding, "hashable")
    expect_identical(codes(edited), "E7301 /bindings/0/binding/rungs")
  }
  edited <- plan
  edited$plan_version <- "0.2.0"
  expect_identical(codes(edited), "E1441 /plan_version")
})

test_that("the preregistration text states the plan", {
  fixture <- pathology_zoo("Z30")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration)
  text <- preregistration_text(plan)
  expect_match(text, plan$design_plan_hash, fixed = TRUE)
  expect_match(text, "Rung 1, decorrelating '1 + arm | site': y ~ 1 + arm + (1 | site) + (0 + arm | site) (identified).",
               fixed = TRUE)
  expect_match(text, "is not for preregistration", fixed = TRUE)
  expect_true(endsWith(text, "\n"))
})

test_that("an audit bound to a plan is planned only when it belongs to the plan", {
  fixture <- pathology_zoo("Z30")
  plan <- plan_at_zero(fixture$data, fixture$formula, fixture$declaration)
  results <- audit_at_zero(fixture$data, "y ~ arm + (1 + arm || site)", fixture$declaration,
                           plan = plan, outcome_access = "T1", reason = "planned",
                           privacy = "shareable")
  log <- results$document$access_log
  expect_identical(log$plan, list(design_plan_hash = plan$design_plan_hash,
                                  outcome_access = "T0"))
  expect_identical(log$entries[[2L]]$mode, "planned")
  validate_results(results)
  other <- audit_issue(fixture$data, "y ~ arm + (1 | site)", fixture$declaration, plan = plan)
  expect_identical(other$message,
                   "The run does not belong to the plan: its IR hash differs from the one the plan records.")
  undeclared <- audit_issue(fixture$data, fixture$formula, plan = plan)
  expect_identical(undeclared$code, "E7310")
})

# Pupils in classes with labels unique across schools, classes randomised.
school_data <- function() {
  data <- expand.grid(pupil = 1:6, class = 1:4, school = 1:6)
  data$class <- sprintf("c%02d", (data$school - 1) * 4 + data$class)
  data$school <- sprintf("s%d", data$school)
  data$pupil <- sprintf("%s-p%d", data$class, data$pupil)
  data$arm <- ifelse(as.integer(substr(data$class, 2, 3)) %% 2 == 0, "control", "tutoring")
  data$y <- NA_real_
  data
}

school_declaration <- function() {
  declaration(
    units = list(declare_unit("school", "school", role = "cluster"),
                 declare_unit("class", "class", nested_in = "school", id_scope = "global",
                              role = "cluster"),
                 declare_unit("pupil", "pupil", nested_in = "class", id_scope = "global",
                              role = "participant")),
    observation = declare_observation(key = "pupil", unit = "pupil"),
    assignment = list(declare_assignment("arm", "class", randomised = TRUE,
                                         level = "between_unit", blocks = "school")),
    variables = list(y = declare_variable("outcome", measurement = "continuous"),
                     arm = declare_variable("assigned")),
    estimands = list(declare_estimand("itt", "arm", kind = "total_effect")),
    features = "cluster_randomised"
  )
}

test_that("a unit written as school/class is the factor school:class", {
  plan <- plan_at_zero(school_data(), "y ~ arm + (1 | school/class)", school_declaration())
  protected <- vapply(plan$design$protected, function(c) paste(c$factor, c$reason), "")
  # The arm varies within schools, so its slope by school is protected too.
  expect_identical(protected, c("school replication_unit", "school:class randomisation_unit",
                                "school focal_slope"))
  last <- plan$design$rungs[[length(plan$design$rungs)]]$ir
  expect_identical(vapply(last$random, function(t) t$name, ""),
                   c("1 | school", "0 + arm | school", "1 | school:class"))
})

test_that("focal slopes are protected only by declared units", {
  data <- crossed_data()
  plan <- plan_at_zero(data, "rt ~ cond + (1 | subject:item) + (1 | subject)",
                       crossed_declaration())
  factors <- vapply(plan$design$protected, function(c) c$factor, "")
  expect_false("subject:item" %in% factors)
})

test_that("a caller's coding keeps the plan's frozen factors", {
  coding <- list(cond = list(contrast = "simple"))
  plan <- plan_at_zero(crossed_data(), "rt ~ cond + freq + (1 | subject) + (1 | item)",
                       crossed_declaration(), coding = coding)
  formula <- mixedcheck:::ir_formula(plan$design$rungs[[2L]]$ir)
  results <- audit_at_zero(crossed_data(), formula, crossed_declaration(), plan = plan,
                           coding = coding)
  expect_identical(results$document$access_log$plan$design_plan_hash, plan$design_plan_hash)
})

test_that("the lme4 encoding escapes backquotes and backslashes", {
  skip_if_not_installed("lme4")
  data <- crossed_data()
  data$cond <- ifelse(data$cond == "a", "a`x", "b\\y")
  plan <- plan_at_zero(data, "rt ~ cond + (1 | subject)")
  for (rung in plan$bindings[[1L]]$binding$rungs) {
    expect_true(is.call(str2lang(rung$encoding)))
  }
  expect_match(plan$bindings[[1L]]$binding$rungs[[1L]]$encoding, "`cond[b\\\\y]`", fixed = TRUE)
})

test_that("a design that identifies no random intercept gives E7317", {
  data <- expand.grid(subject = sprintf("s%02d", 1:8), item = sprintf("i%d", 1:4),
                      stringsAsFactors = FALSE)
  data$cond <- ifelse(seq_len(nrow(data)) %% 2 == 0, "a", "b")
  data$y <- NA_real_
  expect_identical(plan_issue(data, "y ~ cond + (1 | item:subject)")$code, "E7317")
})

test_that("a caller's centring replaces the plan's with its members", {
  data <- crossed_data()
  plan <- plan_at_zero(data, "rt ~ freq + (1 | subject)",
                       coding = list(freq = list(centring = "mean")))
  issue <- audit_issue(data, "rt ~ freq + (1 | subject)", plan = plan,
                       coding = list(freq = list(centring = "none")))
  expect_identical(issue$code, "E7310")
})
