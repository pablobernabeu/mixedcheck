# Targeted tests of the declaration validator, beyond the cases of the
# declaration corpus: values in memory, arguments, the order of issues under
# any locale and the helpers of the rules in code. Non-ASCII strings are built
# with intToUtf8(), never from literals.

issues_of <- function(expr) {
  tryCatch({
    force(expr)
    list()
  }, mixedcheck_error = function(e) e$issues)
}

codes_of <- function(issues) vapply(issues, function(issue) issue[["code"]], "")
pointers_of <- function(issues) vapply(issues, function(issue) issue[["pointer"]] %||% "", "")

minimal_declaration <- function() {
  list(
    vocabulary = "0.1.0",
    goal = "confirmatory",
    units = list(
      list(name = "school", columns = list("school"), role = "cluster"),
      list(name = "pupil", columns = list("pupil"), nested_in = "school", id_scope = "global",
           role = "participant")
    ),
    observation = list(unit = "pupil", key = list("pupil")),
    assignment = list(list(column = "arm", unit = "school", randomised = TRUE)),
    variables = list(
      score = list(role = "outcome", measurement = "continuous"),
      arm = list(role = "assigned")
    ),
    estimands = list(list(id = "ITT", term = "arm", kind = "total_effect"))
  )
}

test_that("a declaration in memory is checked and returned as the reader returns it", {
  declaration <- minimal_declaration()
  value <- validate_declaration(declaration)
  expect_identical(canonical_bytes(value, "hashable"), canonical_bytes(declaration, "hashable"))
  expect_named(value, sort(names(declaration), method = "radix"))
  expect_invisible(validate_declaration(declaration))
  expect_identical(validate_declaration(declaration, minimal = TRUE), value)
})

test_that("a value in memory passes the writer's checks of the hashable profile first", {
  declaration <- minimal_declaration()
  declaration$title <- NA_character_
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), "E1101")
  expect_identical(pointers_of(issues), "/title")

  declaration <- minimal_declaration()
  declaration$units[[1L]]$columns <- c("school", "class")
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), "E1302")
  expect_identical(pointers_of(issues), "/units/0/columns")

  declaration <- minimal_declaration()
  declaration$title <- intToUtf8(c(0x65, 0x301))
  expect_identical(codes_of(issues_of(validate_declaration(declaration))), "E1203")

  expect_identical(codes_of(issues_of(validate_declaration(list("0.1.0")))), "E1401")
  expect_identical(codes_of(issues_of(validate_declaration(factor("a")))), "E1301")
})

test_that("the arguments are checked", {
  expect_error(validate_declaration(minimal_declaration(), minimal = NA), "'minimal' must be")
  expect_error(validate_declaration(minimal_declaration(), minimal = "yes"), "'minimal' must be")
  expect_error(validate_declaration(c("a.json", "b.json")), "must be a file path")
  expect_error(validate_declaration(NA_character_), "must be a file path")
})

test_that("a file is read as YAML only when its name ends in .yaml or .yml", {
  expect_true(is_yaml_path("design.yaml"))
  expect_true(is_yaml_path("design.YML"))
  expect_true(is_yaml_path("dir/design.Yaml"))
  expect_false(is_yaml_path("design.json"))
  expect_false(is_yaml_path("design.yaml.json"))
  expect_false(is_yaml_path("design.yamlx"))
  expect_false(is_yaml_path("yaml"))

  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(canonical_bytes(minimal_declaration(), "hashable"), path)
  expect_identical(canonical_bytes(validate_declaration(path), "hashable"),
                   canonical_bytes(minimal_declaration(), "hashable"))
  missing <- issues_of(validate_declaration(file.path(tempdir(), "no-such-declaration.json")))
  expect_identical(codes_of(missing), "E1001")
})

test_that("the minimal declaration applies to a confirmatory goal, trial features and the argument", {
  declaration <- list(vocabulary = "0.1.0")
  expect_identical(issues_of(validate_declaration(declaration)), list())
  expect_identical(codes_of(issues_of(validate_declaration(declaration, minimal = TRUE))),
                   c("E2028", "E2028", "E2028", "E2028", "E2030"))
  declaration$goal <- "exploratory"
  expect_identical(issues_of(validate_declaration(declaration)), list())
  declaration$features <- list("observational")
  expect_identical(codes_of(issues_of(validate_declaration(declaration, minimal = TRUE))),
                   rep("E2028", 4L))

  declaration <- minimal_declaration()
  declaration$estimands[[1L]]$focal <- FALSE
  declaration$provenance <- list(inferred = list("/units/0/role"))
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), c("E2031", "E2032"))
  declaration$goal <- NULL
  expect_identical(issues_of(validate_declaration(declaration)), list())
})

test_that("the version is checked first, and a missing or non-string version is structural", {
  declaration <- minimal_declaration()
  declaration$vocabulary <- "0.1.01"
  declaration$units <- "none"
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), "E1441")
  expect_identical(issues[[1L]]$message,
                   "Version '0.1.01' at /vocabulary is not supported. This release reads version 0.1.x.")
  long <- paste0("0.1.", strrep("1", 29L))
  declaration$vocabulary <- long
  expect_identical(codes_of(issues_of(validate_declaration(declaration))), "E1441")
  declaration$vocabulary <- substr(long, 1L, 32L)
  expect_identical(codes_of(issues_of(validate_declaration(declaration))), "E1401")
  declaration$vocabulary <- NULL
  expect_identical(codes_of(issues_of(validate_declaration(declaration))), c("E1402", "E1401"))
})

test_that("issues are sorted by code point, not by the collation of the locale", {
  e_acute <- intToUtf8(0xE9)
  declaration <- list(
    vocabulary = "0.1.0",
    table = list(fields = list(list(name = "Z"), list(name = "a"))),
    variables = list(list(role = "auxiliary"), list(role = "auxiliary"), list(role = "auxiliary"),
                     list(role = "auxiliary"))
  )
  names(declaration$variables) <- c(e_acute, "b", "B", "a")
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), rep("E2007", 3L))
  expected <- paste0("/variables/", c("B", "b", e_acute))
  expect_identical(lapply(pointers_of(issues), utf8ToInt), lapply(expected, utf8ToInt))
  old <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", old), add = TRUE)
  for (locale in c("C", "en_US.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_COLLATE", locale)))) {
      expect_identical(lapply(pointers_of(issues_of(validate_declaration(declaration))), utf8ToInt),
                       lapply(expected, utf8ToInt), label = locale)
    }
  }
})

test_that("finish_issues() reports each issue once and caps the list at 100", {
  raw <- c(
    lapply(0:104, function(i) raw_issue("E1403", paste0("/units/", i), list(key = "x"))),
    list(raw_issue("E1403", "/units/3", list(key = "x")))
  )
  issues <- finish_issues(raw)
  expect_length(issues, 101L)
  expect_identical(issues[[1L]]$pointer, "/units/0")
  expect_identical(issues[[3L]]$pointer, "/units/10")
  expect_identical(issues[[101L]], list(code = "W1490", message = "5 further problems were found but not listed."))
  expect_identical(finish_issues(list()), list())
  expect_identical(finish_issues(list(raw_issue("E2030", ""), raw_issue("E2028", "", list(key = "units")))),
                   list(new_issue("E2028", list(key = "units"), pointer = ""), new_issue("E2030", pointer = "")))
})

test_that("term_variables() splits a term into its variables", {
  expect_identical(term_variables("arm"), "arm")
  expect_identical(term_variables("arm:pre.test_1"), c("arm", "pre.test_1"))
  expect_identical(term_variables("`a:b`:c:`d e`"), c("a:b", "c", "d e"))
  expect_identical(term_variables("`x`:x"), c("x", "x"))
  wide <- intToUtf8(c(0x60, 0x1F600, 0x60, 0x3A, 0x61))
  expect_identical(lapply(term_variables(wide), utf8ToInt), list(0x1F600L, 0x61L))
})

test_that("pointer_resolves() follows RFC 6901", {
  document <- list(a = list(1, list(`b/c` = TRUE, `d~e` = "x")))
  expect_true(pointer_resolves(document, ""))
  expect_true(pointer_resolves(document, "/a"))
  expect_true(pointer_resolves(document, "/a/1/b~1c"))
  expect_true(pointer_resolves(document, "/a/1/d~0e"))
  expect_false(pointer_resolves(document, "/a/2"))
  expect_false(pointer_resolves(document, "/a/01"))
  expect_false(pointer_resolves(document, "/a/-"))
  expect_false(pointer_resolves(document, "/a/0/x"))
  expect_false(pointer_resolves(document, "/a/1/b/c"))
  expect_false(pointer_resolves(document, "/b"))
  expect_false(pointer_resolves(document, "/a/"))
})

test_that("the rules in code compare numbers by value and strings by code point", {
  declaration <- list(
    vocabulary = "0.1.0",
    table = list(fields = list(
      list(name = "hit", type = "integer", categories = list(0, 1)),
      list(name = "acc", type = "string", categories = list("a", intToUtf8(0xE9))),
      list(name = "x", type = "number")
    )),
    variables = list(
      hit = list(role = "outcome", measurement = "binary", event_level = 1),
      acc = list(role = "outcome", measurement = "binary", event_level = intToUtf8(0xE9))
    ),
    estimands = list(list(id = "e", term = "x", outcome = "hit"))
  )
  expect_identical(issues_of(validate_declaration(declaration)), list())
  declaration$variables$hit$event_level <- 1L
  expect_identical(issues_of(validate_declaration(declaration)), list())
  declaration$table$fields[[2L]]$categories[[2L]] <- intToUtf8(0xE8)
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), "E2024")
  expect_identical(issues[[1L]]$message, paste0("The event level '", intToUtf8(0xE9),
                                                "' at /variables/acc/event_level is not one of the categories of its field."))
})

test_that("the rules on units follow nesting to its end", {
  units <- list(
    list(name = "a", columns = list("a"), nested_in = "b", id_scope = "global"),
    list(name = "b", columns = list("b"), nested_in = "c", id_scope = "global"),
    list(name = "c", columns = list("c"), nested_in = "b", id_scope = "global"),
    list(name = "d", columns = list("d"))
  )
  declaration <- list(vocabulary = "0.1.0", units = units,
                      crossings = list(list(units = list("a", "c")), list(units = list("d", "a"))))
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), c("E2011", "E2010", "E2010"))
  expect_identical(pointers_of(issues), c("/crossings/0/units", "/units/1/nested_in", "/units/2/nested_in"))
})

test_that("unmarked strings in memory are marked UTF-8 only in a UTF-8 session", {
  e_acute <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xC3, 0xA9)))
  expect_identical(Encoding(e_acute), "unknown")
  declaration <- list(vocabulary = "0.1.0", title = e_acute,
                      variables = list(list(role = "auxiliary")))
  names(declaration$variables) <- e_acute

  local_mocked_bindings(native_utf8 = function() TRUE)
  value <- validate_declaration(declaration)
  expect_identical(Encoding(value$title), "UTF-8")
  expect_identical(utf8ToInt(value$title), c(99L, 97L, 102L, 0xE9L))
  expect_identical(utf8ToInt(names(value$variables)), c(99L, 97L, 102L, 0xE9L))
  # Writers refuse unmarked strings in every session, so the value returned,
  # whose strings are marked, is hashed rather than the value passed in.
  issues <- issues_of(canonical_hash(declaration, "hashable"))
  expect_identical(codes_of(issues), "E1204")
  expect_identical(pointers_of(issues), "/title")
  expect_identical(
    issues[[1L]]$message,
    paste("The string at /title contains non-ASCII bytes but no declared encoding.",
          "Mark it as UTF-8 with Encoding() or read the data with encoding = 'UTF-8'.")
  )
  expect_match(canonical_hash(value, "hashable"), "^sha256:[0-9a-f]{64}$")
  invalid <- declaration
  invalid$title <- rawToChar(as.raw(c(0x63, 0xE9)))
  issues <- issues_of(validate_declaration(invalid))
  expect_identical(codes_of(issues), "E1201")
  expect_identical(pointers_of(issues), "/title")

  local_mocked_bindings(native_utf8 = function() FALSE)
  issues <- issues_of(validate_declaration(declaration))
  expect_identical(codes_of(issues), "E1204")
  expect_identical(pointers_of(issues), "/title")
})

test_that("a declaration with more than a thousand variables is validated and hashed", {
  declaration <- list(
    vocabulary = "0.1.0",
    variables = setNames(rep(list(list(role = "auxiliary")), 1100L), sprintf("item_%04d", 1:1100))
  )
  value <- validate_declaration(declaration)
  # The hash that the Python package gives for the same declaration.
  expect_identical(canonical_hash(value, "hashable"),
                   "sha256:3246014fc47f05426b0ad3fbf74cff05aace9da9201887492bacede70ea9524e")
})
