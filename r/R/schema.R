# The structural validator (docs/spec/errors.md, Structural validation). It
# checks a value read by the strict reader against a schema of the vendored
# bundle, with the JSON Schema keywords that conventions.md (Schemas) allows,
# and returns every issue it finds as a raw issue for finish_issues(). The
# rules that defs.schema.json states in descriptions are checked with it, as
# part of the same phase.

# The schemas of the vendored bundle, by identifier, read once per session.
schema_bundle <- function() {
  bundle <- mixedcheck_cache$schemas
  if (is.null(bundle)) {
    directory <- installed_path("spec", "schemas")
    files <- sort(list.files(directory, pattern = "\\.schema\\.json$", full.names = TRUE),
                  method = "radix")
    schemas <- lapply(files, read_json_strict, profile = "hashable")
    bundle <- new_schema_bundle(lapply(schemas, with_compiled_conditions))
    mixedcheck_cache$schemas <- bundle
  }
  bundle
}

# A bundle of schemas: the schemas by identifier and a cache of the schemas
# that references resolve to.
new_schema_bundle <- function(schemas) {
  bundle <- new.env(parent = emptyenv())
  names(schemas) <- vapply(schemas, function(s) s[["$id"]], "")
  bundle$schemas <- schemas
  bundle$resolved <- new.env(hash = TRUE, parent = emptyenv())
  bundle$by_base <- new.env(hash = TRUE, parent = emptyenv())
  bundle$valid <- new.env(hash = TRUE, parent = emptyenv())
  bundle$valid_count <- 0L
  bundle$patterns <- new.env(hash = TRUE, parent = emptyenv())
  bundle
}

# The definitions whose references the validator does not follow, because
# readers and writers enforce the profiles (conventions.md, Schemas).
profile_definitions <- c(
  "urn:mixedcheck:schema:defs#/$defs/hashable_value",
  "urn:mixedcheck:schema:defs#/$defs/data_value"
)

# A node is a schema with the identifier of the document that holds it, which
# relative references resolve against, and the absolute reference by which it
# was reached, or NA.
schema_node <- function(schema, base, ref = NA_character_) {
  list(schema = schema, base = base, ref = ref)
}

# Resolves a reference such as 'urn:mixedcheck:schema:defs#/$defs/name' or
# '#/$defs/line' against the identifier of the document that holds it. The
# nodes are kept by base and reference as written, so that a reference met
# again is a lookup.
resolve_reference <- function(bundle, ref, base) {
  known <- bundle$by_base[[base]]
  if (is.null(known)) {
    known <- new.env(hash = TRUE, parent = emptyenv())
    assign(base, known, envir = bundle$by_base)
  }
  node <- known[[ref]]
  if (is.null(node)) {
    node <- resolve_absolute_reference(bundle, ref, base)
    assign(ref, node, envir = known)
  }
  node
}

resolve_absolute_reference <- function(bundle, ref, base) {
  hash <- regexpr("#", ref, fixed = TRUE)
  document <- if (hash > 0L) substr(ref, 1L, hash - 1L) else ref
  fragment <- if (hash > 0L) substring(ref, hash + 1L) else ""
  if (!nzchar(document)) {
    document <- base
  }
  absolute <- paste0(document, "#", fragment)
  cached <- bundle$resolved[[absolute]]
  if (!is.null(cached)) {
    return(cached)
  }
  schema <- bundle$schemas[[document]]
  if (is.null(schema)) {
    stop(sprintf("Internal error: unknown schema '%s'.", document), call. = FALSE)
  }
  tokens <- strsplit(sub("^/+", "", fragment), "/", fixed = TRUE)[[1L]]
  for (token in tokens) {
    token <- gsub("~0", "~", gsub("~1", "/", token, fixed = TRUE), fixed = TRUE)
    schema <- schema[[token]]
    if (is.null(schema)) {
      stop(sprintf("Internal error: the reference '%s' resolves to nothing.", ref), call. = FALSE)
    }
  }
  node <- schema_node(schema, document, absolute)
  assign(absolute, node, envir = bundle$resolved)
  node
}

# The JSON type of a value read by the strict reader.
json_kind <- function(value) {
  if (is.null(value)) {
    return("null")
  }
  if (is.logical(value)) {
    return("boolean")
  }
  if (is.numeric(value)) {
    return("number")
  }
  if (is.character(value)) {
    return("string")
  }
  if (is.list(value)) {
    return(if (is.null(names(value))) "array" else "object")
  }
  "unknown"
}

is_json_object <- function(value) is.list(value) && !is.null(names(value))
is_json_array <- function(value) is.list(value) && is.null(names(value))
is_json_integer <- function(value) {
  is.numeric(value) && length(value) == 1L && is.finite(value) && value == floor(value)
}

# Whether a value has a type of JSON Schema. An integer is a number whose
# value is integral, so 1.0 is an integer.
has_json_type <- function(value, type) {
  if (identical(type, "integer")) {
    return(is_json_integer(value))
  }
  identical(json_kind(value), type)
}

# Whether a value of the given JSON kind has one of the types, as
# has_json_type() decides for each.
has_any_json_type <- function(value, kind, types) {
  any(types == kind) || (any(types == "integer") && is_json_integer(value))
}

# Whether a value equals an item of an enum, as json_equal() decides.
in_enum <- function(value, items) {
  for (item in items) {
    if (json_equal(value, item)) {
      return(TRUE)
    }
  }
  FALSE
}

# Equality of JSON values as JSON Schema defines it: the same type, numbers by
# value, strings by code points, arrays item by item and objects member by
# member, whatever the order of their members.
json_equal <- function(left, right) {
  if (is.character(left) && is.character(right)) {
    return(identical(charToRaw(left), charToRaw(right)))
  }
  kind <- json_kind(left)
  if (!identical(kind, json_kind(right))) {
    return(FALSE)
  }
  switch(kind,
    null = TRUE,
    array = length(left) == length(right) &&
      all(vapply(seq_along(left), function(i) json_equal(left[[i]], right[[i]]), NA)),
    object = {
      keys <- names(left)
      length(keys) == length(right) && all(keys %in% names(right)) &&
        all(vapply(keys, function(key) json_equal(left[[key]], right[[key]]), NA))
    },
    string = identical(charToRaw(left), charToRaw(right)),
    left == right
  )
}

# The number of code points of a string that is ASCII or marked UTF-8.
codepoint_length <- function(x) length(utf8ToInt(x))

# Whether a schema pattern matches a string, over code points and with a
# final '$' matching only at the end (conventions.md, Schemas). Each '\uXXXX'
# becomes '\x{XXXX}', a final '$' becomes '\z' and '(*UTF)' comes first, so
# that PCRE matches over code points even when the string is ASCII.
schema_pattern_matches <- function(bundle, pattern, text) {
  converted <- bundle$patterns[[pattern]]
  if (is.null(converted)) {
    converted <- gsub("\\\\u([0-9A-Fa-f]{4})", "\\\\x{\\1}", pattern, perl = TRUE)
    if (endsWith(converted, "$") && !endsWith(converted, "\\$")) {
      converted <- paste0(substr(converted, 1L, nchar(converted) - 1L), "\\z")
    }
    converted <- paste0("(*UTF)", converted)
    assign(pattern, converted, envir = bundle$patterns)
  }
  grepl(converted, text, perl = TRUE)
}

# Whether each string matches the pattern of a definition of defs.schema.json
# in the vendored bundle, such as 'decimal_string'.
matches_definition <- function(text, name, bundle = schema_bundle()) {
  ref <- paste0("urn:mixedcheck:schema:defs#/$defs/", name)
  schema_pattern_matches(bundle, resolve_reference(bundle, ref, ref)$schema[["pattern"]], text)
}

# Validates a value against the schema with the given identifier, or against a
# node, and returns the raw issues, unsorted.
schema_issues <- function(value, schema, bundle = schema_bundle()) {
  node <- if (is.character(schema)) resolve_reference(bundle, schema, schema) else schema
  validate_schema_node(bundle, value, node, "")
}

schema_valid <- function(bundle, value, node) {
  simple <- simple_schema_valid(value, node$schema)
  if (!is.na(simple)) {
    return(simple)
  }
  length(validate_schema_node(bundle, value, node, "")) == 0L
}

# Whether a value meets the condition of if: by the closure that
# with_compiled_conditions() attached to it, which decides as
# simple_schema_valid() does, or by the validator when that is NA.
condition_valid <- function(bundle, value, condition, base) {
  compiled <- attr(condition, "mixedcheck_condition", exact = TRUE)
  if (!is.null(compiled)) {
    valid <- compiled(value)
    if (!is.na(valid)) {
      return(valid)
    }
  }
  schema_valid(bundle, value, schema_node(condition, base))
}

# A schema with each condition of if that is an object given the attribute
# 'mixedcheck_condition', a closure from compile_condition(), so that the
# validator evaluates the many conditions of the results schema without
# reading their keywords again for each value. The values of enum, const
# and default are data and are left as they are.
with_compiled_conditions <- function(schema) {
  if (!is.list(schema)) {
    return(schema)
  }
  keys <- names(schema)
  for (i in seq_along(schema)) {
    if (!is.null(keys) && keys[i] %in% c("enum", "const", "default")) {
      next
    }
    member <- with_compiled_conditions(schema[[i]])
    if (identical(keys[i], "if") && is.list(member)) {
      attr(member, "mixedcheck_condition") <- compile_condition(member)
    }
    member_keys <- names(member)
    if (is.list(member) && "if" %in% member_keys &&
        all(member_keys == "if" | member_keys == "then" | member_keys == "else")) {
      attr(member, "mixedcheck_conditional") <- TRUE
    }
    if (!is.null(member)) {
      schema[[i]] <- member
    }
  }
  schema
}

# A closure that gives, for a value, what simple_schema_valid() gives for the
# schema: TRUE, FALSE or NA.
compile_condition <- function(schema) {
  if (isTRUE(schema)) {
    return(function(value) TRUE)
  }
  if (isFALSE(schema)) {
    return(function(value) FALSE)
  }
  if (!is.list(schema) || !all(names(schema) %in% simple_keywords)) {
    return(function(value) NA)
  }
  types <- unlist(schema[["type"]])
  enum <- schema[["enum"]]
  strings <- unlist(Filter(is.character, enum))
  has_const <- "const" %in% names(schema)
  const <- schema[["const"]]
  required <- unlist(schema[["required"]])
  properties <- lapply(schema[["properties"]], compile_condition)
  property_names <- names(properties)
  not <- if (!is.null(schema[["not"]])) compile_condition(schema[["not"]])
  function(value) {
    kind <- json_kind(value)
    if (!is.null(types) && !has_any_json_type(value, kind, types)) {
      return(FALSE)
    }
    if (!is.null(enum)) {
      found <- if (kind == "string") {
        # Strings equal as R compares them, confirmed byte for byte.
        bytes <- charToRaw(value)
        any(vapply(strings[strings == value], function(item) identical(charToRaw(item), bytes), NA))
      } else {
        in_enum(value, enum)
      }
      if (!found) {
        return(FALSE)
      }
    }
    if (has_const && !json_equal(value, const)) {
      return(FALSE)
    }
    known <- TRUE
    if (kind == "object") {
      keys <- names(value)
      for (key in required) {
        if (!any(keys == key)) {
          return(FALSE)
        }
      }
      # The result does not depend on the order of the members.
      at <- match(property_names, keys)
      for (j in which(!is.na(at))) {
        valid <- properties[[j]](value[[at[j]]])
        if (isFALSE(valid)) {
          return(FALSE)
        }
        known <- known && !is.na(valid)
      }
    }
    if (!is.null(not)) {
      valid <- not(value)
      if (isTRUE(valid)) {
        return(FALSE)
      }
      known <- known && !is.na(valid)
    }
    if (known) TRUE else NA
  }
}

# The keywords of the schemas that simple_schema_valid() decides.
simple_keywords <- c("type", "enum", "const", "not", "required", "properties", "title",
                     "description")

# Whether a value is valid against a schema built only of the keywords type,
# enum, const, not, required and properties, decided as the validator decides
# it but without collecting issues, or NA for a schema with other keywords.
# The conditions of if in the results schema have this form, and the
# validator evaluates many of them.
simple_schema_valid <- function(value, schema) {
  if (isTRUE(schema)) {
    return(TRUE)
  }
  if (isFALSE(schema)) {
    return(FALSE)
  }
  if (!is.list(schema) || !all(names(schema) %in% simple_keywords)) {
    return(NA)
  }
  types <- schema[["type"]]
  if (!is.null(types) && !has_any_json_type(value, json_kind(value), unlist(types))) {
    return(FALSE)
  }
  if (!is.null(schema[["enum"]]) && !in_enum(value, schema[["enum"]])) {
    return(FALSE)
  }
  if (any(names(schema) == "const") && !json_equal(value, schema[["const"]])) {
    return(FALSE)
  }
  known <- TRUE
  if (json_kind(value) == "object") {
    keys <- names(value)
    if (!all(unlist(schema[["required"]]) %in% keys)) {
      return(FALSE)
    }
    properties <- schema[["properties"]]
    for (i in which(keys %in% names(properties))) {
      valid <- simple_schema_valid(value[[i]], properties[[keys[i]]])
      if (isFALSE(valid)) {
        return(FALSE)
      }
      known <- known && !is.na(valid)
    }
  }
  if (!is.null(schema[["not"]])) {
    valid <- simple_schema_valid(value, schema[["not"]])
    if (isTRUE(valid)) {
      return(FALSE)
    }
    known <- known && !is.na(valid)
  }
  if (known) TRUE else NA
}

# The pointer of a member or item: its token escaped and appended.
child_pointer <- function(pointer, token) {
  if (is.character(token) && (grepl("~", token, fixed = TRUE) || grepl("/", token, fixed = TRUE))) {
    token <- gsub("/", "~1", gsub("~", "~0", token, fixed = TRUE), fixed = TRUE)
  }
  paste0(pointer, "/", token)
}

# The type keywords that apply to a value unconditionally, in the order of
# errors.md (Structural validation, rule 3): the schema's own, then those
# reached through $ref, allOf and the branch of if that applies, recursively.
# The branch of each if is recorded in branches, in the order in which
# apply_schema() meets the same ifs, so that each condition is evaluated
# once for a value.
unconditional_types <- function(bundle, value, node, branches) {
  schema <- node$schema
  if (!is.list(schema)) {
    return(list())
  }
  found <- list()
  if (!is.null(schema[["type"]])) {
    found <- c(found, list(unlist(schema[["type"]])))
  }
  ref <- schema[["$ref"]]
  if (!is.null(ref)) {
    target <- resolve_reference(bundle, ref, node$base)
    if (!any(profile_definitions == target$ref)) {
      found <- c(found, unconditional_types(bundle, value, target, branches))
    }
  }
  for (sub in schema[["allOf"]]) {
    if (conditional_only(sub)) {
      # The step below for a subschema of if, then and else alone.
      branch <- if (condition_valid(bundle, value, sub[["if"]], node$base)) "then" else "else"
      branches$found <- c(branches$found, branch)
      if (!is.null(sub[[branch]])) {
        found <- c(found, unconditional_types(bundle, value, schema_node(sub[[branch]], node$base),
                                              branches))
      }
      next
    }
    found <- c(found, unconditional_types(bundle, value, schema_node(sub, node$base), branches))
  }
  if (!is.null(schema[["if"]])) {
    branch <- if (condition_valid(bundle, value, schema[["if"]], node$base)) "then" else "else"
    branches$found <- c(branches$found, branch)
    if (!is.null(schema[[branch]])) {
      found <- c(found, unconditional_types(bundle, value, schema_node(schema[[branch]], node$base),
                                            branches))
    }
  }
  found
}

# typed is TRUE for a node that apply_schema() reaches through $ref, allOf or
# the branch of if: its unconditional types are among those of the node that
# reached it, which the value already has, so they are not checked again,
# and its ifs take the branches that unconditional_types() recorded.
validate_schema_node <- function(bundle, value, node, pointer, typed = FALSE, branches = NULL) {
  schema <- node$schema
  if (isTRUE(schema)) {
    return(list())
  }
  if (isFALSE(schema)) {
    return(list(raw_issue("E1423", pointer)))
  }
  if (!typed) {
    known <- known_valid_key(bundle, value, schema, node$base)
    if (!is.null(known) && known_valid(bundle, known, value)) {
      return(list())
    }
    branches <- new.env(parent = emptyenv())
    branches$found <- character(0)
    branches$used <- 0L
    kind <- json_kind(value)
    for (types in unconditional_types(bundle, value, node, branches)) {
      if (!has_any_json_type(value, kind, types)) {
        return(list(raw_issue("E1401", pointer, list(expected = types, found = kind))))
      }
    }
    issues <- apply_schema(bundle, value, node, pointer, branches)
    if (!is.null(known) && !length(issues)) {
      remember_valid(bundle, known, value)
    }
    return(issues)
  }
  apply_schema(bundle, value, node, pointer, branches)
}

# The values found valid against a schema of $ref alone, the subschema of
# a member or an item that names a definition, kept for the session: a
# value that is identical, bit for bit, to one of them is valid without a
# second validation, since its issues depend on the definition and the
# value alone. Results documents repeat many statistics, statuses and
# findings. Values are grouped by the definition and the text of their
# serialisation, and compared with identical(), so that the doubles that
# the text rounds alike stay apart. A value whose key exceeds 2,000 bytes is
# not kept, and the store is emptied when it holds 10,000 values.
known_valid_key <- function(bundle, value, schema, base) {
  if (!is.list(schema) || length(schema) != 1L || !identical(names(schema), "$ref")) {
    return(NULL)
  }
  key <- paste0(resolve_reference(bundle, schema[["$ref"]], base)$ref, "\n",
                rawToChar(serialize(value, NULL, ascii = TRUE)))
  if (nchar(key, type = "bytes") > 2000L) NULL else key
}

known_valid <- function(bundle, key, value) {
  for (known in bundle$valid[[key]]) {
    if (identical(known, value, num.eq = FALSE, single.NA = FALSE)) {
      return(TRUE)
    }
  }
  FALSE
}

remember_valid <- function(bundle, key, value) {
  if (bundle$valid_count >= 10000L) {
    bundle$valid <- new.env(hash = TRUE, parent = emptyenv())
    bundle$valid_count <- 0L
  }
  assign(key, c(bundle$valid[[key]], list(value)), envir = bundle$valid)
  bundle$valid_count <- bundle$valid_count + 1L
}

# The title that E1406 and E1418 name: the node's own, or that of the first
# schema its $ref chain reaches that has one.
schema_title <- function(bundle, node) {
  schema <- node$schema
  base <- node$base
  while (is.list(schema) && is.null(schema[["title"]]) && !is.null(schema[["$ref"]])) {
    target <- resolve_reference(bundle, schema[["$ref"]], base)
    schema <- target$schema
    base <- target$base
  }
  if (is.list(schema) && !is.null(schema[["title"]])) schema[["title"]] else "value of the required form"
}

alternative_keywords <- c("anyOf", "oneOf")

# Whether a schema holds if, with then or else, and no other keyword, as
# with_compiled_conditions() marks it.
conditional_only <- function(schema) {
  isTRUE(attr(schema, "mixedcheck_conditional", exact = TRUE))
}

apply_schema <- function(bundle, value, node, pointer, branches) {
  schema <- node$schema
  base <- node$base
  issues <- list()
  ref <- schema[["$ref"]]
  if (!is.null(ref)) {
    target <- resolve_reference(bundle, ref, base)
    if (!any(profile_definitions == target$ref)) {
      issues <- c(issues, validate_schema_node(bundle, value, target, pointer, typed = TRUE,
                                               branches = branches))
      issues <- c(issues, definition_issues(bundle, value, target, pointer))
    }
    if (length(schema) == 1L) {
      # A schema of $ref alone has no other keyword to apply.
      return(issues)
    }
  }
  for (sub in schema[["allOf"]]) {
    if (conditional_only(sub)) {
      # A subschema of if, then and else alone applies the branch that
      # unconditional_types() recorded, as apply_schema() would.
      branches$used <- branches$used + 1L
      branch <- sub[[branches$found[branches$used]]]
      if (!is.null(branch)) {
        issues <- c(issues, validate_schema_node(bundle, value, schema_node(branch, base), pointer,
                                                 typed = TRUE, branches = branches))
      }
      next
    }
    issues <- c(issues, validate_schema_node(bundle, value, schema_node(sub, base), pointer,
                                             typed = TRUE, branches = branches))
  }
  if (!is.null(schema[["if"]])) {
    branches$used <- branches$used + 1L
    branch <- branches$found[branches$used]
    if (!is.null(schema[[branch]])) {
      issues <- c(issues, validate_schema_node(bundle, value, schema_node(schema[[branch]], base),
                                               pointer, typed = TRUE, branches = branches))
    }
  }
  if (!is.null(schema[["enum"]]) && !in_enum(value, schema[["enum"]])) {
    issues <- c(issues, list(raw_issue("E1405", pointer, list(allowed = schema[["enum"]]))))
  }
  if (any(names(schema) == "const") && !json_equal(value, schema[["const"]])) {
    issues <- c(issues, list(raw_issue("E1405", pointer, list(allowed = list(schema[["const"]])))))
  }
  kind <- json_kind(value)
  if (kind == "string") {
    issues <- c(issues, string_issues(bundle, value, node, pointer))
  } else if (kind == "number") {
    issues <- c(issues, number_issues(value, schema, pointer))
  } else if (kind == "array") {
    issues <- c(issues, array_issues(bundle, value, schema, base, pointer))
  } else if (kind == "object") {
    issues <- c(issues, object_issues(bundle, value, schema, base, pointer))
  }
  for (keyword in alternative_keywords) {
    if (!is.null(schema[[keyword]])) {
      issues <- c(issues, alternative_issues(bundle, value, keyword, schema[[keyword]], base, pointer))
    }
  }
  if (!is.null(schema[["not"]]) && schema_valid(bundle, value, schema_node(schema[["not"]], base))) {
    issues <- c(issues, list(raw_issue("E1423", pointer)))
  }
  issues
}

string_issues <- function(bundle, value, node, pointer) {
  schema <- node$schema
  issues <- list()
  length_needed <- !is.null(schema[["minLength"]]) || !is.null(schema[["maxLength"]])
  size <- if (length_needed) codepoint_length(value) else 0L
  if (!is.null(schema[["minLength"]]) && size < schema[["minLength"]]) {
    issues <- c(issues, list(raw_issue("E1407", pointer, list(limit = schema[["minLength"]]))))
  }
  if (!is.null(schema[["maxLength"]]) && size > schema[["maxLength"]]) {
    issues <- c(issues, list(raw_issue("E1408", pointer, list(limit = schema[["maxLength"]]))))
  }
  if (!is.null(schema[["pattern"]]) &&
      !schema_pattern_matches(bundle, schema[["pattern"]], value)) {
    issues <- c(issues, list(raw_issue("E1406", pointer, list(form = schema_title(bundle, node)))))
  }
  issues
}

number_issues <- function(value, schema, pointer) {
  issues <- list()
  checks <- list(
    list("minimum", "E1409", function(v, limit) v < limit),
    list("maximum", "E1410", function(v, limit) v > limit),
    list("exclusiveMinimum", "E1411", function(v, limit) v <= limit),
    list("exclusiveMaximum", "E1412", function(v, limit) v >= limit)
  )
  for (check in checks) {
    limit <- schema[[check[[1L]]]]
    if (!is.null(limit) && check[[3L]](value, limit)) {
      issues <- c(issues, list(raw_issue(check[[2L]], pointer, list(limit = limit))))
    }
  }
  issues
}

array_issues <- function(bundle, value, schema, base, pointer) {
  issues <- list()
  prefix <- schema[["prefixItems"]]
  items <- schema[["items"]]
  for (i in seq_len(if (is.null(items)) min(length(prefix), length(value)) else length(value))) {
    sub <- if (i <= length(prefix)) prefix[[i]] else items
    if (!is.null(sub)) {
      issues <- c(issues, validate_schema_node(bundle, value[[i]], schema_node(sub, base),
                                               child_pointer(pointer, i - 1L)))
    }
  }
  if (!is.null(schema[["minItems"]]) && length(value) < schema[["minItems"]]) {
    issues <- c(issues, list(raw_issue("E1413", pointer, list(limit = schema[["minItems"]]))))
  }
  if (!is.null(schema[["maxItems"]]) && length(value) > schema[["maxItems"]]) {
    issues <- c(issues, list(raw_issue("E1414", pointer, list(limit = schema[["maxItems"]]))))
  }
  if (isTRUE(schema[["uniqueItems"]]) && length(value) > 1L) {
    # Two values that the reader returns are equal as JSON Schema defines it
    # exactly when their canonical forms are, since numbers are written by
    # value and members in the order of their keys. Comparing the forms takes
    # time in proportion to the number of items, not to its square.
    forms <- vapply(value, function(item) write_canonical(item, "plain"), "")
    for (i in which(duplicated(forms))) {
      issues <- c(issues, list(raw_issue("E1415", child_pointer(pointer, i - 1L))))
    }
  }
  if (!is.null(schema[["contains"]])) {
    contains <- schema_node(schema[["contains"]], base)
    if (!any(vapply(value, function(item) schema_valid(bundle, item, contains), NA))) {
      issues <- c(issues, list(raw_issue("E1420", pointer)))
    }
  }
  issues
}

object_issues <- function(bundle, value, schema, base, pointer) {
  issues <- list()
  keys <- names(value)
  for (key in unlist(schema[["required"]])) {
    if (!any(keys == key)) {
      issues <- c(issues, list(raw_issue("E1402", pointer, list(key = key))))
    }
  }
  dependent <- schema[["dependentRequired"]]
  for (key in names(dependent)) {
    if (key %in% keys) {
      for (other in unlist(dependent[[key]])) {
        if (!other %in% keys) {
          issues <- c(issues, list(raw_issue("E1419", pointer, list(key = key, required = other))))
        }
      }
    }
  }
  if (!is.null(schema[["propertyNames"]])) {
    names_node <- schema_node(schema[["propertyNames"]], base)
    for (key in keys) {
      if (!schema_valid(bundle, key, names_node)) {
        issues <- c(issues, list(raw_issue("E1418", pointer,
                                           list(key = key, form = schema_title(bundle, names_node)))))
      }
    }
  }
  if (!is.null(schema[["minProperties"]]) && length(keys) < schema[["minProperties"]]) {
    issues <- c(issues, list(raw_issue("E1416", pointer, list(limit = schema[["minProperties"]]))))
  }
  if (!is.null(schema[["maxProperties"]]) && length(keys) > schema[["maxProperties"]]) {
    issues <- c(issues, list(raw_issue("E1417", pointer, list(limit = schema[["maxProperties"]]))))
  }
  properties <- schema[["properties"]]
  patterns <- schema[["patternProperties"]]
  additional <- schema[["additionalProperties"]]
  if (is.null(properties) && is.null(patterns) && is.null(additional)) {
    # No member has a schema to meet, as for most subschemas of allOf.
    return(issues)
  }
  listed <- match(keys, names(properties))
  for (i in seq_along(keys)) {
    key <- keys[i]
    subs <- if (is.na(listed[i])) list() else list(properties[[listed[i]]])
    for (pattern in names(patterns)) {
      if (schema_pattern_matches(bundle, pattern, key)) {
        subs <- c(subs, list(patterns[[pattern]]))
      }
    }
    if (length(subs) == 0L && !is.null(additional)) {
      if (isFALSE(additional)) {
        issues <- c(issues, list(raw_issue("E1403", pointer, list(key = key))))
        next
      }
      subs <- list(additional)
    }
    refused <- FALSE
    for (sub in subs) {
      refused <- refused || isFALSE(sub)
    }
    if (refused) {
      issues <- c(issues, list(raw_issue("E1404", pointer, list(key = key))))
      next
    }
    for (sub in subs) {
      issues <- c(issues, validate_schema_node(bundle, value[[i]], schema_node(sub, base),
                                               child_pointer(pointer, key)))
    }
  }
  issues
}

# anyOf and oneOf (errors.md, Structural validation, rule 5).
alternative_issues <- function(bundle, value, keyword, alternatives, base, pointer) {
  results <- lapply(alternatives, function(sub) {
    validate_schema_node(bundle, value, schema_node(sub, base), pointer)
  })
  matches <- sum(lengths(results) == 0L)
  if (keyword == "oneOf" && matches > 1L) {
    return(list(raw_issue("E1422", pointer)))
  }
  if (matches > 0L) {
    return(list())
  }
  qualifying <- which(vapply(alternatives, function(sub) {
    !is.list(sub) || is.null(sub[["type"]]) ||
      any(vapply(unlist(sub[["type"]]), function(type) has_json_type(value, type), NA))
  }, NA))
  if (length(qualifying) == 1L) {
    return(results[[qualifying]])
  }
  list(raw_issue("E1421", pointer))
}

# The rules that the schemas state in descriptions and the validators check in
# code (errors.md, Structural validation): the day of a UTC timestamp or a
# date, the significant digits of a decimal constant, characters outside the
# BMP in a column name and in the variables of an estimand term
# (declarations.md, Order of checks). They run where a reference reaches the
# definition and the value has passed its type keyword.
definition_issues <- function(bundle, value, node, pointer) {
  switch(node$ref,
    "urn:mixedcheck:schema:defs#/$defs/column_name" = {
      if (is.character(value) && has_non_bmp(value)) list(raw_issue("E1207", pointer)) else list()
    },
    "urn:mixedcheck:schema:defs#/$defs/utc_timestamp" = ,
    "urn:mixedcheck:schema:defs#/$defs/date" = {
      if (is.character(value) && schema_pattern_matches(bundle, node$schema[["pattern"]], value) &&
          !calendar_day_exists(value)) {
        list(raw_issue("E1406", pointer, list(form = node$schema[["title"]])))
      } else {
        list()
      }
    },
    "urn:mixedcheck:schema:defs#/$defs/decimal_constant" = {
      digits <- if (is_json_object(value)) value[["significant_digits"]]
      text <- if (is_json_object(value)) value[["value"]]
      form <- resolve_reference(bundle, "#/$defs/decimal_string", node$base)$schema[["pattern"]]
      if (is_json_integer(digits) && is.character(text) &&
          schema_pattern_matches(bundle, form, text) && significant_digit_count(text) > digits) {
        list(raw_issue("E1406", child_pointer(pointer, "value"),
                       list(form = node$schema[["title"]])))
      } else {
        list()
      }
    },
    "urn:mixedcheck:schema:declaration#/$defs/term" = {
      if (is.character(value) && schema_pattern_matches(bundle, node$schema[["pattern"]], value) &&
          any(has_non_bmp(term_variables(value)))) {
        list(raw_issue("E1207", pointer))
      } else {
        list()
      }
    },
    list()
  )
}

# Whether the day of each string that matches the pattern of a date or a UTC
# timestamp, YYYY-MM-DD..., with a month from 01 to 12, exists in its month,
# in integer arithmetic.
calendar_day_exists <- function(text) {
  year <- as.integer(substr(text, 1L, 4L))
  month <- as.integer(substr(text, 6L, 7L))
  day <- as.integer(substr(text, 9L, 10L))
  days <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)[month]
  leap <- (year %% 4L == 0L & year %% 100L != 0L) | year %% 400L == 0L
  days[month == 2L & leap] <- 29L
  day <= days
}

# The number of significant digits of a decimal string: its digits without
# leading or trailing zeros.
significant_digit_count <- function(text) {
  digits <- gsub("[^0-9]", "", text)
  nchar(sub("0+$", "", sub("^0+", "", digits)))
}

# The variables of an estimand term that matches the pattern of a term: its
# bare names and its quoted names without the backquotes, in the order
# written (declarations.md, Terms used by the rules).
term_variables <- function(term) {
  codepoints <- utf8ToInt(term)
  count <- length(codepoints)
  variables <- character(0)
  i <- 1L
  while (i <= count) {
    if (codepoints[i] == 96L) {
      j <- i + 1L
      while (codepoints[j] != 96L) {
        j <- j + 1L
      }
      variables <- c(variables, intToUtf8(codepoints[(i + 1L):(j - 1L)]))
      i <- j + 2L
    } else {
      j <- i
      while (j <= count && codepoints[j] != 58L) {
        j <- j + 1L
      }
      variables <- c(variables, intToUtf8(codepoints[i:(j - 1L)]))
      i <- j + 1L
    }
  }
  variables
}
