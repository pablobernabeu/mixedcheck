# R's model.matrix() and lme4's lFormula() as black-box oracles for the
# columns of X and Z, on the cases where docs/spec/ir.md (Differences from R
# and lme4) says that the suite agrees with them: valid formulas with
# treatment coding whose levels all occur in the sample, once the names of
# columns are translated. The formulas and data are generated without R's
# random number generator, which the tests leave alone.

`%||%` <- function(x, y) if (is.null(x)) y else x

# A linear congruential generator, so that the cases do not depend on R's
# random number generator.
oracle_stream <- function(seed) {
  state <- seed
  function(n) {
    state <<- (state * 1103515245 + 12345) %% 2147483648
    floor(state / 2147483648 * n) + 1
  }
}

oracle_data <- function(draw, n = 60L) {
  pick <- function(values) values[vapply(seq_len(n), function(i) draw(length(values)), 0)]
  data.frame(
    y = vapply(seq_len(n), function(i) draw(1000) / 100, 0),
    x = vapply(seq_len(n), function(i) draw(200) / 50 - 2, 0),
    z = vapply(seq_len(n), function(i) draw(100) / 100, 0),
    a = pick(c("A1", "A2", "A3")),
    b = pick(c("B1", "B2")),
    c = pick(c("C1", "C2", "C3", "C4")),
    g = pick(sprintf("g%d", 1:6)),
    h = pick(sprintf("h%d", 1:4)),
    stringsAsFactors = FALSE
  )
}

oracle_formula <- function(draw) {
  variables <- c("x", "z", "a", "b", "c")
  expression <- function(depth) {
    if (depth > 1L || draw(6) <= 3) {
      return(variables[draw(5)])
    }
    left <- expression(depth + 1L)
    right <- expression(depth + 1L)
    switch(draw(5),
      paste0(left, " : ", right),
      paste0(left, " * ", right),
      paste0(left, " / ", right),
      paste0("(", left, " + ", right, ")"),
      paste0("(", left, " + ", right, ")^2")
    )
  }
  fixed <- paste(vapply(seq_len(draw(3)), function(i) expression(0L), ""), collapse = " + ")
  if (draw(4) == 1) {
    fixed <- paste("0 +", fixed)
  }
  random <- vapply(seq_len(draw(3) - 1L), function(i) {
    slopes <- vapply(seq_len(draw(3) - 1L), function(j) expression(2L), "")
    lhs <- paste(c(c("1", "0", "1")[draw(3)], slopes), collapse = " + ")
    if (lhs == "0") {
      lhs <- "1"
    }
    bar <- if (draw(4) == 1 && length(slopes)) "||" else "|"
    paste0("(", lhs, " ", bar, " ", c("g", "h", "g/h", "g:h")[draw(4)], ")")
  }, "")
  paste("y ~", paste(c(fixed, random), collapse = " + "))
}

# Compares X with model.matrix() and each block of Z with the block of its
# random term in lFormula(), by the column names and by Z Z', which does not
# depend on the order in which lme4 lists the levels.
oracle_agrees <- function(formula, data) {
  ir <- tryCatch(formula_ir(formula, data = data), mixedcheck_error = function(e) NULL)
  if (is.null(ir)) {
    return(NA)
  }
  m <- design_matrices(ir, data)
  frame <- data[m$design_sample, , drop = FALSE]
  for (name in names(ir$predictors)) {
    p <- ir$predictors[[name]]
    if (p$kind == "categorical") {
      frame[[name]] <- factor(frame[[name]], levels = unlist(p$levels))
      if (any(table(frame[[name]]) == 0L)) {
        return(NA)
      }
    }
  }
  translate <- function(names) {
    names <- gsub("[true]", "TRUE", gsub("[false]", "FALSE", names, fixed = TRUE), fixed = TRUE)
    gsub("\\[([^]]*)\\]", "\\1", names)
  }
  same_x <- function(x) {
    identical(translate(colnames(m$x)) %||% character(0), colnames(x) %||% character(0)) &&
      identical(unname(m$x), matrix(as.double(x), nrow = nrow(x)))
  }
  if (!length(ir$random)) {
    return(same_x(stats::model.matrix(stats::as.formula(formula), frame)))
  }
  control <- lme4::lmerControl(
    check.nobs.vs.rankZ = "ignore", check.nobs.vs.nlev = "ignore",
    check.nlev.gtreq.5 = "ignore", check.nlev.gtr.1 = "ignore", check.nobs.vs.nRE = "ignore",
    check.rankX = "ignore", check.scaleX = "ignore", check.formula.LHS = "ignore"
  )
  structure <- tryCatch(suppressMessages(suppressWarnings(
    lme4::lFormula(stats::as.formula(formula), data = frame, control = control)
  )), error = function(e) NULL)
  if (is.null(structure)) {
    return(NA)
  }
  if (!same_x(structure$X)) {
    return(FALSE)
  }
  terms <- structure$reTrms
  if (length(terms$Ztlist) != length(ir$random)) {
    return(FALSE)
  }
  for (k in seq_along(ir$random)) {
    term <- ir$random[[k]]
    ours <- as.matrix(m$z[, m$z_columns$term == k, drop = FALSE])
    columns <- translate(vapply(term$columns, function(column) column$name, ""))
    matched <- FALSE
    for (j in seq_along(terms$Ztlist)) {
      # lme4 writes a nested factor inner first, as 'pupil:(class:school)'.
      factor <- gsub("[()]", "", names(terms$cnms)[j])
      if (!setequal(strsplit(factor, ":", fixed = TRUE)[[1L]],
                    unlist(term$grouping)) || !identical(terms$cnms[[j]], columns)) {
        next
      }
      theirs <- t(as.matrix(terms$Ztlist[[j]]))
      matched <- matched || (ncol(theirs) == ncol(ours) &&
                               identical(unname(ours %*% t(ours)), unname(theirs %*% t(theirs))))
    }
    if (!matched) {
      return(FALSE)
    }
  }
  TRUE
}

test_that("X and Z agree with model.matrix() and lme4 on generated formulas", {
  skip_on_cran()
  skip_if_not_installed("lme4")
  draw <- oracle_stream(20261108)
  data <- oracle_data(draw)
  outcomes <- vapply(seq_len(300L), function(i) {
    formula <- oracle_formula(draw)
    agrees <- oracle_agrees(formula, data)
    if (identical(agrees, FALSE)) {
      fail(paste("X or Z differs from R and lme4 for", formula))
    }
    agrees
  }, NA)
  expect_false(any(outcomes %in% FALSE))
  expect_gt(sum(outcomes, na.rm = TRUE), 120L)
})

test_that("X and Z agree with model.matrix() and lme4 on the corpus cases they accept", {
  skip_on_cran()
  skip_if_not_installed("lme4")
  compared <- 0L
  for (file in c("ordinary.json", "interactions.json", "nested.json", "crossed.json",
                 "double_bar.json", "offsets.json")) {
    for (case in corpus_cases("formulas", file)) {
      plain <- !is.null(case[["data"]]) && is.null(case[["declaration"]]) &&
        is.null(case[["coding"]]) && is.null(case[["weights"]]) &&
        is.null(case[["sample_columns"]]) && !is.null(case[["expected"]][["ir"]]) &&
        !grepl("^\\s*~|offset|log\\(|[`\r]", case[["formula"]])
      if (!plain) {
        next
      }
      data <- corpus_data_frame(case[["data"]])
      # R and lme4 do not apply NFC, so only ASCII labels are compared, and
      # they paste the labels of an interaction with ':', which merges levels
      # whose labels contain ':' (ir.md, Differences from R and lme4).
      if (any(vapply(data, function(column) {
        is.character(column) && any(grepl("[^ -~]|:", column[!is.na(column)]))
      }, NA))) {
        next
      }
      agrees <- oracle_agrees(case[["formula"]], data)
      if (identical(agrees, FALSE)) {
        fail(paste("X or Z differs from R and lme4 for", case$id))
      }
      compared <- compared + isTRUE(agrees)
    }
  }
  expect_gt(compared, 40L)
})
