# Targeted tests of the YAML authoring reader, beyond the cases of the YAML
# corpus: the pre-scan, which needs no package, the reader without the yaml
# package and the conversion of positions that the corpus does not reach.

prescan <- function(text) {
  problem <- yaml_prescan(as.integer(charToRaw(text)))
  if (is.null(problem)) "" else paste(problem$code, problem$offset %||% "")
}

yaml_file <- function(text, fileext = ".yaml") {
  path <- tempfile(fileext = fileext)
  writeBin(charToRaw(text), path)
  path
}

issue_codes <- function(path) {
  tryCatch({
    validate_declaration(path)
    character(0)
  }, mixedcheck_error = function(e) {
    vapply(e$issues, function(issue) paste(issue$code, issue$pointer %||% issue$offset %||% ""), "")
  })
}

test_that("the pre-scan skips comments, quoted scalars and block scalars", {
  expect_identical(prescan("a: b # &anchor *alias !tag\n"), "")
  expect_identical(prescan("a: 'x &y ''*z'' !t'\n"), "")
  expect_identical(prescan("a: \"x &y \\\" *z\"\n"), "")
  expect_identical(prescan("a: |\n  &x\n\n  *y\nb: c\n"), "")
  expect_identical(prescan("a: >\n  &x\n&b: c\n"), "E3004 10")
  expect_identical(prescan("a: b&c *d\n"), "")
  expect_identical(prescan("a: b<<\nb: '<<c'\n"), "")
  expect_identical(prescan("? [a]\n: b\n"), "")
  expect_identical(prescan("a: b#c\n"), "")
  expect_identical(prescan("#c\n---\na: b\n...\n# end\n"), "")
})

test_that("the pre-scan finds anchors, aliases, tags, directives and merge keys at the start of a node", {
  expect_identical(prescan("a: &x b\n"), "E3004 3")
  expect_identical(prescan("a: [b, *x]\n"), "E3004 7")
  expect_identical(prescan("a:\n- &x b\n"), "E3004 5")
  expect_identical(prescan("a: {b: c,  &x d: e}\n"), "E3004 11")
  expect_identical(prescan("a: b\r&c: d\r"), "E3004 5")
  expect_identical(prescan("'a': &x b\n"), "E3004 5")
  expect_identical(prescan("a: !!str b\n"), "E3005 3")
  expect_identical(prescan("%YAML 1.1\n---\na: b\n"), "E3005 0")
  expect_identical(prescan("<< : {a: b}\n"), "E3009 0")
  expect_identical(prescan("a: {<<: {b: c}}\n"), "E3009 4")
})

test_that("the pre-scan refuses every plain scalar that starts with '<<'", {
  e_acute <- rawToChar(as.raw(c(0xC3, 0xA9)))
  expect_identical(prescan("a: <<\n"), "E3009 3")
  expect_identical(prescan("a: <<c\n"), "E3009 3")
  expect_identical(prescan(paste0("a: <<", e_acute, "\n")), "E3009 3")
  expect_identical(prescan("? <<\n"), "E3009 2")
  expect_identical(prescan("?\n    <<\r\n: b"), "E3009 6")
  expect_identical(prescan("a: [b, <<]\n"), "E3009 7")
  # libyaml reads '?' and ':' as indicators inside brackets whatever follows.
  expect_identical(prescan("a: {?<<: {b: c}}\n"), "E3009 5")
  expect_identical(prescan("a: {?&x b: c}\n"), "E3004 5")
  expect_identical(prescan("a: {\"b\":!x c}\n"), "E3005 8")
  expect_identical(prescan("a: [b?<<]\n"), "")
})

test_that("the pre-scan ends lines at U+0085, U+2028 and U+2029 as libyaml does", {
  nel <- rawToChar(as.raw(c(0xC2, 0x85)))
  line_sep <- rawToChar(as.raw(c(0xE2, 0x80, 0xA8)))
  para_sep <- rawToChar(as.raw(c(0xE2, 0x80, 0xA9)))
  expect_identical(prescan(paste0("a:", nel, "  &x b\n")), "E3004 6")
  expect_identical(prescan(paste0("a: b", nel, "!x c: d\n")), "E3005 6")
  expect_identical(prescan(paste0("a:", nel, "  <<: {b: c}\n")), "E3009 6")
  expect_identical(prescan(paste0("a: b # c", para_sep, "&x d: e\n")), "E3004 11")
  expect_identical(prescan(paste0("a: x", line_sep, "---\nb: 1\n")), "E3003 7")
  expect_identical(prescan(nel), "E3010 ")
  expect_identical(prescan(paste0("a: |", line_sep, "  &x", para_sep, "b: c\n")), "")
  # Other characters outside ASCII are content.
  expect_identical(prescan(rawToChar(as.raw(c(0xE2, 0x80, 0xAA)))), "")
})

test_that("the pre-scan counts documents and finds U+0000", {
  expect_identical(prescan("---\na: b\n---\nc: d\n"), "E3003 9")
  expect_identical(prescan("a: b\n...\nc: d\n"), "E3003 9")
  expect_identical(prescan("# only a comment\n"), "E3010 ")
  expect_identical(prescan(""), "E3010 ")
  expect_identical(prescan("---\n"), "E3010 ")
  expect_identical(prescan("a: \"x\\x00\"\n"), "E1202 5")
  expect_identical(prescan("a: \"x\\U00000000\"\n"), "E1202 5")
  expect_identical(prescan("a: \"x\\\\0\"\n"), "")
  expect_identical(yaml_prescan(c(as.integer(charToRaw("a: b\n# x")), 0L, 10L)),
                   list(code = "E1202", offset = 8L))
  expect_identical(yaml_prescan(c(as.integer(charToRaw("a: '")), 0L, as.integer(charToRaw("'\n&x: b\n")))),
                   list(code = "E1202", offset = 4L))
})

test_that("reading YAML without the yaml package gives E3001", {
  local_mocked_bindings(yaml_available = function() FALSE)
  path <- yaml_file("vocabulary: 0.1.0\n")
  on.exit(unlink(path), add = TRUE)
  problem <- tryCatch(validate_declaration(path), mixedcheck_error = function(e) e)
  expect_identical(problem$issues, list(list(code = "E3001", message = "Reading YAML needs the package 'yaml'.")))
  bom <- yaml_file("\xef\xbb\xbfvocabulary: 0.1.0\n")
  on.exit(unlink(bom), add = TRUE)
  expect_identical(issue_codes(bom), "E1003 ")
})

test_that("the check of keys walks any depth and keeps the order of the text", {
  deep <- list("x")
  for (i in seq_len(5000L)) {
    deep <- list(deep)
  }
  expect_null(yaml_check_keys(deep, character(0)))
  mapping <- function(keys, values) structure(values, keys = keys)
  late <- mapping(list("a", "b"), list(list(mapping(list(""), list("x"))), "y"))
  problem <- tryCatch(yaml_check_keys(late, character(0)), mixedcheck_error = function(e) e$issues)
  expect_identical(problem[[1L]]$pointer, "/a/0/")
  complex <- mapping(list("a", list("k")), list(mapping(list(""), list("x")), "y"))
  problem <- tryCatch(yaml_check_keys(complex, character(0)), mixedcheck_error = function(e) e$issues)
  expect_identical(problem[[1L]]$pointer, "/a/")
  complex <- mapping(list("a", list("k")), list("x", mapping(list(""), list("y"))))
  problem <- tryCatch(yaml_check_keys(complex, character(0)), mixedcheck_error = function(e) e$issues)
  expect_identical(problem[[1L]]$code, "E3006")
})

test_that("a value that yaml read as a merge key is an internal error, never turned into '<<'", {
  merge <- structure("_yaml.merge_", class = "_yaml.merge_")
  problem <- tryCatch(yaml_scalar_text(merge), mixedcheck_error = function(e) e$issues)
  expect_identical(problem, list(list(
    code = "E9001",
    message = "Internal error: the YAML pre-scan missed a merge key. Please report it."
  )))
})

test_that("a syntax error or a duplicate key keeps the message of the yaml package", {
  skip_if_not_installed("yaml", "2.3.8")
  problem <- tryCatch(yaml_parse("a: {b: 1\n"), mixedcheck_error = function(e) e)
  expect_identical(problem$issues, list(list(code = "E3002", message = "The YAML text cannot be parsed.")))
  lines <- strsplit(conditionMessage(problem), "\n", fixed = TRUE)[[1L]]
  expect_length(lines, 2L)
  expect_identical(lines[1L], "The YAML text cannot be parsed.")
  expect_match(lines[2L], "at line 2, column 1", fixed = TRUE)
  problem <- tryCatch(yaml_parse("a: 1\na: 2\n"), mixedcheck_error = function(e) e)
  expect_identical(problem$issues, list(list(code = "E3007", message = "A YAML mapping holds a key twice.")))
  expect_identical(conditionMessage(problem), "A YAML mapping holds a key twice.\nDuplicate map key: 'a'")
})

test_that("keys that are mappings or empty are refused before conversion", {
  skip_if_not_installed("yaml", "2.3.8")
  paths <- c(yaml_file("? {a: b}\n: c\n"), yaml_file("vocabulary: 0.1.0\n'': x\n"),
             yaml_file("a: [{b: {'': c}}]\n"), yaml_file("a:\n  - ? [x]\n    : 1\n"))
  on.exit(unlink(paths), add = TRUE)
  expect_identical(issue_codes(paths[1L]), "E3006 ")
  expect_identical(issue_codes(paths[4L]), "E3006 /a/0")
  expect_identical(issue_codes(paths[2L]), "E1109 /")
  expect_identical(issue_codes(paths[3L]), "E1109 /a/0/b/")
})

test_that("scalars stay strings except where the schema requires another type", {
  skip_if_not_installed("yaml", "2.3.8")
  convert <- function(text) yaml_convert_declaration(yaml_parse(text))
  value <- convert(paste0(
    "vocabulary: 0.1.0\nextra: true\nunits: {focal: 'true'}\nfeatures: [1, yes]\n",
    "estimands: [{focal: 'false'}]\nprovenance: {outcome_seen: {a: b}}\n",
    "table: {fields: {categories: [1]}}\nvariables: {y: {bounds: ['0', 2.5e1], event_level: '7'}}\n",
    "empty: {}\nnothing: []\n"
  ))
  expect_identical(value$extra, "true")
  expect_identical(value$units, list(focal = "true"))
  expect_identical(value$features, list("1", "yes"))
  expect_identical(value$estimands, list(list(focal = FALSE)))
  expect_identical(value$provenance$outcome_seen, list(a = "b"))
  expect_identical(value$table$fields$categories, list("1"))
  expect_identical(value$variables$y$bounds, list(0, 25))
  expect_identical(value$variables$y$event_level, 7)
  expect_identical(value$empty, setNames(list(), character(0)))
  expect_identical(value$nothing, list())
})

test_that("a category or an event level takes the type of its field", {
  skip_if_not_installed("yaml", "2.3.8")
  convert <- function(text) yaml_convert_declaration(yaml_parse(text))
  value <- convert(paste0(
    "table:\n  fields:\n",
    "    - {name: y, type: string, categories: ['1', 2]}\n",
    "    - {name: y, type: integer, categories: ['3']}\n",
    "    - {name: z, type: [integer], categories: [4, a]}\n",
    "    - 5\n",
    "variables:\n  y: {event_level: '1'}\n  z: {event_level: '6'}\n  w: {event_level: x}\n"
  ))
  expect_identical(value$table$fields[[1L]]$categories, list("1", "2"))
  expect_identical(value$table$fields[[2L]]$categories, list(3))
  expect_identical(value$table$fields[[3L]]$categories, list(4, "a"))
  expect_identical(value$table$fields[[4L]], "5")
  expect_identical(value$variables$y$event_level, "1")
  expect_identical(value$variables$z$event_level, 6)
  expect_identical(value$variables$w$event_level, "x")
  problem <- tryCatch(convert("table:\n  fields:\n    - {name: y, type: integer}\nvariables:\n  y: {event_level: '-0.0'}\n"),
                      mixedcheck_error = function(e) e$issues)
  expect_identical(problem, list(list(
    code = "E3008", message = "The value '-0.0' at /variables/y/event_level cannot be read as an integer.",
    pointer = "/variables/y/event_level"
  )))
})

test_that("a declaration in YAML has the hash of its JSON form", {
  skip_if_not_installed("yaml", "2.3.8")
  text <- paste0(
    "vocabulary: 0.1.0 # a comment\n",
    "title: \"Caf\\u00e9 study\"\n",
    "units:\n  - name: subject\n    columns: [Subject]\n    role: participant\n"
  )
  yaml_path <- yaml_file(text, ".yml")
  json_path <- tempfile(fileext = ".json")
  on.exit(unlink(c(yaml_path, json_path)), add = TRUE)
  value <- validate_declaration(yaml_path)
  writeBin(canonical_bytes(value, "hashable"), json_path)
  expect_identical(canonical_hash(validate_declaration(json_path), "hashable"),
                   canonical_hash(value, "hashable"))
  expect_identical(utf8ToInt(value$title), c(utf8ToInt("Caf"), 0xE9L, utf8ToInt(" study")))
  expect_identical(Encoding(value$title), "UTF-8")
})
