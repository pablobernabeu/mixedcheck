# Targeted tests of the structural validator on the keywords and rules that
# the declaration schema does not use, with a schema added to a copy of the
# vendored bundle.

test_bundle <- function() {
  schema <- list(
    `$id` = "urn:test",
    type = "object",
    additionalProperties = FALSE,
    properties = list(
      n = list(type = "number", minimum = 0, maximum = 10, exclusiveMinimum = -1,
               exclusiveMaximum = 11),
      any = list(anyOf = list(list(type = "string"), list(type = "integer", minimum = 5))),
      one = list(oneOf = list(list(type = "number"), list(type = "integer"))),
      has = list(type = "array", contains = list(const = "x")),
      no = list(not = list(type = "string")),
      pair = list(type = "array", prefixItems = list(list(type = "string"), list(type = "boolean")),
                  items = FALSE),
      map = list(type = "object", patternProperties = list(`^x-` = list(type = "integer")),
                 additionalProperties = FALSE, maxProperties = 2),
      date = list(`$ref` = "urn:mixedcheck:schema:defs#/$defs/date"),
      constant = list(`$ref` = "urn:mixedcheck:schema:defs#/$defs/decimal_constant"),
      line = list(type = "string", pattern = "^a$", title = "line")
    )
  )
  new_schema_bundle(c(unname(schema_bundle()$schemas), list(schema)))
}

checked <- function(value, bundle = test_bundle()) {
  issues <- finish_issues(schema_issues(value, "urn:test", bundle))
  vapply(issues, function(issue) paste(issue$code, issue$pointer %||% "", issue$message), "")
}

test_that("numbers are checked against their limits", {
  expect_identical(checked(list(n = 0)), character(0))
  expect_identical(checked(list(n = -2)), c(
    "E1409 /n The number at /n is less than 0.",
    "E1411 /n The number at /n must be greater than -1."
  ))
  expect_identical(checked(list(n = 12)), c(
    "E1410 /n The number at /n is greater than 10.",
    "E1412 /n The number at /n must be less than 11."
  ))
})

test_that("anyOf and oneOf report the one alternative of the value's type, or E1421 or E1422", {
  expect_identical(checked(list(any = "s", one = 1.5)), character(0))
  expect_identical(checked(list(any = TRUE)),
                   "E1421 /any The value at /any matches none of the allowed forms.")
  expect_identical(checked(list(any = 3)), "E1409 /any The number at /any is less than 5.")
  expect_identical(checked(list(one = 1)),
                   "E1422 /one The value at /one matches more than one of the allowed forms.")
  expect_identical(checked(list(one = "a")),
                   "E1421 /one The value at /one matches none of the allowed forms.")
})

test_that("contains, not, prefixItems and a false schema report their own codes", {
  expect_identical(checked(list(has = list("y", "x"), no = 1, pair = list("a", TRUE))), character(0))
  expect_identical(checked(list(has = list("y"))),
                   "E1420 /has The array at /has has no item of the required form.")
  expect_identical(checked(list(no = "s")), "E1423 /no The value at /no is not allowed.")
  expect_identical(checked(list(pair = list(1, TRUE, 3))), c(
    "E1401 /pair/0 Expected string at /pair/0, found number.",
    "E1423 /pair/2 The value at /pair/2 is not allowed."
  ))
})

test_that("patternProperties and maxProperties apply to the members of an object", {
  expect_identical(checked(list(map = list(`x-a` = 1))), character(0))
  expect_identical(checked(list(map = list(`x-a` = "s", b = 1, c = 2))), c(
    "E1403 /map Unknown key 'b' in the object at /map.",
    "E1403 /map Unknown key 'c' in the object at /map.",
    "E1417 /map The object at /map has more than 2 members.",
    "E1401 /map/x-a Expected integer at /map/x-a, found string."
  ))
})

test_that("the day of a date is checked against its month in integer arithmetic", {
  for (date in c("2024-02-29", "2000-02-29", "0004-02-29", "2023-12-31", "9999-04-30")) {
    expect_identical(checked(list(date = date)), character(0), label = date)
  }
  for (date in c("2023-02-29", "1900-02-29", "2023-04-31", "0001-02-29")) {
    expect_identical(checked(list(date = date)), "E1406 /date The string at /date is not a valid date.",
                     label = date)
  }
  expect_identical(checked(list(date = "2023-13-01")),
                   "E1406 /date The string at /date is not a valid date.")
  expect_identical(checked(list(date = 20230101)), "E1401 /date Expected string at /date, found number.")
})

test_that("a decimal constant has at most its significant digits", {
  expect_identical(checked(list(constant = list(significant_digits = 2, value = "1200"))), character(0))
  expect_identical(checked(list(constant = list(significant_digits = 3, value = "-0.00125"))),
                   character(0))
  expect_identical(
    checked(list(constant = list(significant_digits = 2, value = "-0.00125"))),
    "E1406 /constant/value The string at /constant/value is not a valid decimal constant."
  )
  expect_identical(checked(list(constant = "1.5")),
                   "E1401 /constant Expected object at /constant, found string.")
})

test_that("patterns match over code points, and '$' only at the end of the string", {
  bundle <- test_bundle()
  expect_identical(checked(list(line = "a"), bundle), character(0))
  expect_identical(checked(list(line = "a\n"), bundle),
                   "E1406 /line The string at /line is not a valid line.")
  wide <- intToUtf8(0x1F600)
  column_name <- "^[\\u0020-\\u007E\\u00A0-\\uFFFF]*$"
  expect_false(schema_pattern_matches(bundle, column_name, wide))
  expect_true(schema_pattern_matches(bundle, column_name, intToUtf8(0xFFFD)))
  expect_true(schema_pattern_matches(bundle, "^.$", wide))
})

test_that("json_equal() compares numbers by value and objects whatever their order", {
  expect_true(json_equal(1, 1L))
  expect_false(json_equal(1, "1"))
  expect_false(json_equal(TRUE, 1))
  expect_true(json_equal(list(a = 1, b = list("x")), list(b = list("x"), a = 1)))
  expect_false(json_equal(list(a = 1), list(1)))
  expect_false(json_equal(list(1, 2), list(2, 1)))
  expect_true(json_equal(intToUtf8(0xE9), enc2utf8(intToUtf8(0xE9))))
  expect_true(has_json_type(2, "integer"))
  expect_false(has_json_type(2.5, "integer"))
  expect_true(has_json_type(2.5, "number"))
  expect_identical(json_kind(setNames(list(), character(0))), "object")
  expect_identical(json_kind(list()), "array")
})

test_that("uniqueItems compares canonical forms in time proportional to the items", {
  schema <- list(`$id` = "urn:test:unique", type = "array", uniqueItems = TRUE)
  bundle <- new_schema_bundle(c(unname(schema_bundle()$schemas), list(schema)))
  keys <- lapply(seq_len(5000L), function(i) list("school", paste0("pupil", i), i %% 3))
  elapsed <- system.time(issues <- schema_issues(keys, "urn:test:unique", bundle))[["elapsed"]]
  expect_identical(issues, list())
  expect_lt(elapsed, 5)
  repeated <- c(keys[1:3], list(list("school", "pupil1", 1), list(b = list(1), a = 2),
                                list(a = 2, b = list(1))))
  issues <- finish_issues(schema_issues(repeated, "urn:test:unique", bundle))
  expect_identical(vapply(issues, function(issue) issue$pointer, ""), c("/3", "/5"))
  expect_identical(unique(vapply(issues, function(issue) issue$code, "")), "E1415")
  distinct <- list(1, TRUE, "1", NULL, list(1), list(`1` = 1))
  expect_identical(schema_issues(distinct, "urn:test:unique", bundle), list())
})
