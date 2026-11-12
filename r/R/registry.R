# Loading of the vendored compiled registry (docs/spec/registry.md, The
# compiled registry) and the rules enforced in code on it, which the package
# tests apply (registry.md, Rules enforced in code).

#' The registry of checks
#'
#' Returns the compiled registry of checks installed with the package: every
#' check that the package runs, with what it reads, its statistics,
#' thresholds, decision rules, messages, remedies and sources, together with
#' the parameters of the privacy filter. The Python package's
#' `mixedcheck.read_registry()` returns the same document from its own copy.
#'
#' The registry is read once per session. Its SHA-256 digest is compared with
#' the manifest of the vendored files, it is read with the strict reader in
#' the hashable profile and its version must lie in the line that this
#' release supports, 0.1.
#'
#' @return A named list with the members `registry_version`, `entries`, the
#'   entries in ascending order of identifier, and `privacy`, as
#'   [read_json_strict()] returns them.
#' @section Errors: A registry that cannot be loaded gives an error of class
#'   `mixedcheck_error`, with the code E1321 when the file differs from its
#'   manifest, a code of the strict reader when it cannot be read and E1441
#'   when its version is not supported.
#' @export
#' @examples
#' registry <- read_registry()
#' registry$registry_version
#' vapply(registry$entries, function(entry) entry$id, "")[1:3]
read_registry <- function() {
  registry <- mixedcheck_cache$registry
  if (is.null(registry)) {
    registry <- load_registry(installed_path("spec"))
    mixedcheck_cache$registry <- registry
  }
  registry
}

# The registry hash of the vendored compiled registry: the SHA-256 of its
# bytes, which every results document records (registry.md, The compiled
# registry).
registry_hash <- function() {
  hash <- mixedcheck_cache$registry_hash
  if (is.null(hash)) {
    read_registry()
    hash <- hash_file(installed_path("spec", "compiled", "registry.json"))
    mixedcheck_cache$registry_hash <- hash
  }
  hash
}

# The entries of the registry, named by identifier.
registry_entries_by_id <- function(registry = read_registry()) {
  entries <- registry[["entries"]]
  names(entries) <- vapply(entries, function(entry) entry[["id"]], "")
  entries
}

# The supported line of registry versions.
registry_version_pattern <- "^0\\.1\\.(0|[1-9][0-9]*)\\z"

# Loads compiled/registry.json from a directory of vendored files with its
# MANIFEST.json, as registry.md (The compiled registry) describes.
load_registry <- function(directory) {
  bytes <- read_input_bytes(file.path(directory, "compiled", "registry.json"))
  manifest <- read_json_strict(file.path(directory, "MANIFEST.json"), "data")
  recorded <- if (is_json_object(manifest[["files"]])) manifest[["files"]][["compiled/registry.json"]]
  if (!identical(cli::hash_raw_sha256(bytes), recorded)) {
    raise_issue("E1321", pointer = "/files/compiled~1registry.json")
  }
  document <- parse_json_bytes(bytes, "hashable")
  version <- if (is_json_object(document)) document[["registry_version"]]
  if (!is.character(version)) {
    # Without a version to check, the structure is checked instead.
    signal_issues(finish_issues(schema_issues(document, "urn:mixedcheck:schema:registry")))
  }
  if (!version_supported(version, registry_version_pattern)) {
    raise_issue("E1441", list(version = version, supported = "0.1.x"),
                pointer = "/registry_version")
  }
  document
}

# The entry of a check, or E4001 when no entry has the identifier.
registry_entry <- function(id, registry = read_registry()) {
  for (entry in registry[["entries"]]) {
    if (identical(entry[["id"]], id)) {
      return(entry)
    }
  }
  raise_issue("E4001", list(id = id))
}

# The names of the parts of each scope, which message arguments of source
# 'scope' may name (registry.md, Scopes).
registry_scope_parts <- list(
  assignment = c("column", "unit"),
  column = "column",
  fixed_term = "term",
  fixed_term_by_factor = c("factor", "term"),
  grouping_column_pair = c("first", "second"),
  grouping_factor = "factor",
  grouping_factor_or_model = "factor",
  grouping_factor_pair = c("first", "second"),
  model = character(0),
  random_term = c("factor", "term")
)

# The rules enforced in code on a structurally valid compiled registry: the
# order of the entries, the rules on each entry and the rules across entries.
# Returns the issues sorted and capped.
registry_issues <- function(document) {
  issues <- list()
  entries <- document[["entries"]]
  ids <- vapply(entries, function(entry) entry[["id"]], "")
  for (i in seq_along(entries)) {
    prefix <- paste0("/entries/", i - 1L)
    # Identifiers are compared code point by code point, which the radix
    # method gives, never by the collation of the locale.
    if (i > 1L && (ids[i] == ids[i - 1L] ||
                   !identical(order(ids[c(i - 1L, i)], method = "radix"), 1:2))) {
      issues <- c(issues, list(raw_issue("E4017", prefix)))
    }
    issues <- c(issues, registry_entry_issues(entries[[i]], prefix))
  }
  issues <- c(issues, registry_graph_issues(entries))
  finish_issues(issues)
}

# The rules enforced in code on one structurally valid entry, with pointers
# under the prefix that locates the entry in its document.
registry_entry_issues <- function(entry, prefix) {
  issues <- list()
  add <- function(code, pointer, args = list()) {
    issues[[length(issues) + 1L]] <<- raw_issue(code, paste0(prefix, pointer), args)
  }
  reads <- unlist(entry[["reads"]])
  tier <- entry[["tier"]]
  if ((tier == "T0" && "outcome" %in% reads) || (tier != "T0" && !"outcome" %in% reads) ||
      (tier == "T1" && "predictors" %in% reads)) {
    add("E4016", "/reads", list(tier = tier))
  }
  if ((tier == "T0") == (entry[["sample"]] == "analysis")) {
    add("E4016", "/sample", list(tier = tier))
  }
  statistics <- entry[["statistics"]]
  thresholds <- entry[["thresholds"]]
  parameters <- entry[["parameters"]]
  messages <- entry[["messages"]]
  for (name in names(thresholds)) {
    threshold <- thresholds[[name]]
    here <- child_pointer("/thresholds", name)
    statistic <- statistics[[threshold[["statistic"]]]]
    if (is.null(statistic)) {
      add("E4004", paste0(here, "/statistic"), list(kind = "statistic", name = threshold[["statistic"]]))
    } else if (!statistic[["kind"]] %in% c("count", "ratio", "real")) {
      add("E4011", here, list(name = threshold[["statistic"]]))
    } else {
      kind <- statistic[["kind"]]
      value <- threshold[["value"]]
      if (kind == "count" && grepl(".", value, fixed = TRUE)) {
        add("E4012", paste0(here, "/value"), list(form = "an integer", kind = kind))
      }
      places <- if (grepl(".", value, fixed = TRUE)) nchar(sub("^[^.]*\\.", "", value)) else 0L
      if (kind == "ratio" && (startsWith(value, "-") || (value != "1" && !startsWith(value, "0")) ||
                              places > 4L)) {
        add("E4012", paste0(here, "/value"),
            list(form = "between 0 and 1 with at most four decimal places", kind = kind))
      }
      if (!is.null(threshold[["proximity"]]) != (kind == "real")) {
        add("E4013", here)
      }
    }
    unread <- any(vapply(threshold[["sources"]], function(source) {
      source[["kind"]] %in% c("literature", "software") && !isTRUE(source[["full_text_read"]])
    }, NA))
    if (identical(threshold[["validation"]][["value"]], "validated") && unread) {
      add("E4010", paste0(here, "/validation"))
    }
  }
  for (name in names(statistics)) {
    statistic <- statistics[[name]]
    if (!identical(statistic[["kind"]], "ratio")) {
      next
    }
    here <- child_pointer("/statistics", name)
    parts <- list()
    for (part in c("numerator", "denominator")) {
      target <- statistics[[statistic[[part]]]]
      if (is.null(target)) {
        add("E4004", paste0(here, "/", part), list(kind = "statistic", name = statistic[[part]]))
      }
      parts <- c(parts, list(target))
    }
    if (!any(vapply(parts, is.null, NA)) &&
        any(vapply(parts, function(target) {
          !identical(target[["kind"]], "count") ||
            !identical(target[["count_class"]], statistic[["count_class"]])
        }, NA))) {
      add("E4021", here)
    }
  }
  parts <- registry_scope_parts[[entry[["scope"]]]]
  for (name in names(statistics)) {
    statistic <- statistics[[name]]
    here <- child_pointer("/statistics", name)
    resolved_by <- statistic[["resolved_by"]]
    for (i in seq_along(resolved_by)) {
      target <- resolved_by[[i]][["name"]]
      at <- paste0(here, "/resolved_by/", i - 1L, "/name")
      if (identical(resolved_by[[i]][["source"]], "scope")) {
        if (!target %in% parts) {
          add("E4004", at, list(kind = "scope element", name = target))
        }
      } else if (is.null(statistics[[target]])) {
        add("E4004", at, list(kind = "statistic", name = target))
      } else if (!identical(statistics[[target]][["kind"]], "names")) {
        add("E4024", at, list(name = target, expected = "of kind names"))
      }
    }
    if (!is.null(statistic[["quantile"]])) {
      target <- statistic[["quantile"]][["n"]]
      if (is.null(statistics[[target]])) {
        add("E4004", paste0(here, "/quantile/n"), list(kind = "statistic", name = target))
      } else if (!identical(statistics[[target]][["kind"]], "count")) {
        add("E4024", paste0(here, "/quantile/n"), list(name = target, expected = "a count"))
      }
    }
    suppress_with <- unlist(statistic[["suppress_with"]])
    for (i in seq_along(suppress_with)) {
      if (is.null(statistics[[suppress_with[i]]])) {
        add("E4004", paste0(here, "/suppress_with/", i - 1L),
            list(kind = "statistic", name = suppress_with[i]))
      }
    }
    if (!is.null(statistic[["part_of"]])) {
      target <- statistic[["part_of"]]
      total <- statistics[[target]]
      if (is.null(total)) {
        add("E4004", paste0(here, "/part_of"), list(kind = "statistic", name = target))
      } else if (!identical(total[["kind"]], "count") ||
                 !identical(total[["count_class"]], statistic[["count_class"]])) {
        add("E4024", paste0(here, "/part_of"),
            list(name = target, expected = "a count of the same count class"))
      }
    }
  }
  availability <- entry[["availability"]]
  for (i in seq_along(availability)) {
    parameter <- availability[[i]][["parameter"]]
    if (!is.null(parameter) && !parameter %in% names(parameters)) {
      add("E4004", paste0("/availability/", i - 1L, "/parameter"),
          list(kind = "parameter", name = parameter))
    }
  }
  decision <- entry[["decision"]]
  rules <- decision[["rules"]]
  for (i in seq_along(rules)) {
    rule <- rules[[i]]
    here <- paste0("/decision/rules/", i - 1L)
    read <- unlist(rule[["statistics"]])
    for (j in seq_along(read)) {
      if (is.null(statistics[[read[j]]])) {
        add("E4004", paste0(here, "/statistics/", j - 1L), list(kind = "statistic", name = read[j]))
      }
    }
    named <- unlist(rule[["thresholds"]])
    for (j in seq_along(named)) {
      if (!named[j] %in% names(thresholds)) {
        add("E4004", paste0(here, "/thresholds/", j - 1L), list(kind = "threshold", name = named[j]))
      }
    }
    if (!rule[["message"]] %in% names(messages)) {
      add("E4004", paste0(here, "/message"), list(kind = "message", name = rule[["message"]]))
    }
    descriptive <- vapply(named[named %in% names(thresholds)], function(name) {
      identical(thresholds[[name]][["validation"]][["value"]], "descriptive")
    }, NA)
    if (identical(rule[["finding"]], "consequential") && any(descriptive)) {
      add("E4020", paste0(here, "/finding"))
    }
  }
  otherwise <- decision[["otherwise"]][["message"]]
  if (!otherwise %in% names(messages)) {
    add("E4004", "/decision/otherwise/message", list(kind = "message", name = otherwise))
  }
  for (name in names(messages)) {
    message <- messages[[name]]
    here <- child_pointer("/messages", name)
    args <- message[["args"]]
    used <- registry_template_issues(message[["template"]], names(args),
                                     paste0(here, "/template"), add)
    for (arg_name in names(args)) {
      arg <- args[[arg_name]]
      arg_here <- child_pointer(paste0(here, "/args"), arg_name)
      if (!arg_name %in% used) {
        add("E4008", arg_here, list(name = arg_name))
      }
      source <- arg[["source"]]
      target <- arg[["name"]]
      known <- switch(source,
        statistic = names(statistics),
        threshold = names(thresholds),
        parameter = names(parameters),
        scope = parts
      )
      if (!target %in% known) {
        kind <- if (source == "scope") "scope element" else source
        add("E4004", paste0(arg_here, "/name"), list(kind = kind, name = target))
        next
      }
      statistic_kind <- if (source == "statistic") statistics[[target]][["kind"]] else ""
      if (statistic_kind %in% c("boolean", "reals")) {
        add("E4015", paste0(arg_here, "/name"), list(name = target))
      } else if (!is.null(arg[["digits"]]) != (statistic_kind %in% c("ratio", "real"))) {
        add("E4014", arg_here)
      }
      if (!is.null(arg[["noun"]]) && statistic_kind != "count") {
        add("E4024", paste0(arg_here, "/noun"), list(name = target, expected = "a count"))
      }
    }
    # The arguments that render a statistic that can be left unwritten, which
    # only the template may render, and only with a fallback (E4023).
    unwritten <- names(args)[vapply(args, function(arg) {
      identical(arg[["source"]], "statistic") && !is.null(statistics[[arg[["name"]]]]) &&
        statistic_can_be_unwritten(statistics[[arg[["name"]]]])
    }, NA)]
    fallback <- message[["fallback"]]
    if (!is.null(fallback)) {
      fallback_used <- registry_template_issues(fallback, names(args),
                                                paste0(here, "/fallback"), add)
      if (any(unwritten %in% fallback_used)) {
        add("E4023", here)
      }
    } else if (length(unwritten)) {
      add("E4023", here)
    }
  }
  remedies <- vapply(entry[["remedies"]], function(remedy) remedy[["id"]], "")
  for (i in which(duplicated(remedies))) {
    add("E4006", paste0("/remedies/", i - 1L, "/id"), list(name = remedies[i]))
  }
  issues
}

# The placeholders of a template or fallback, each once, after reporting a
# brace outside a placeholder (E4009) and a placeholder that no argument
# defines (E4007) at the pointer given.
registry_template_issues <- function(template, argument_names, pointer, add) {
  placeholder <- "\\{([a-z][a-z0-9_]{0,47})\\}"
  used <- regmatches(template, gregexpr(placeholder, template, perl = TRUE))[[1L]]
  used <- unique(substr(used, 2L, nchar(used) - 1L))
  if (grepl("[{}]", gsub(placeholder, "", template, perl = TRUE))) {
    add("E4009", pointer)
  }
  for (name in used) {
    if (!name %in% argument_names) {
      add("E4007", pointer, list(name = name))
    }
  }
  used
}

# Whether a message may find a statistic unwritten, because its definition
# can leave it absent or the privacy filter can suppress it (registry.md,
# Messages): ratios, reals and labels, person and by_unit counts, counts that
# measure a quantity, which the filter suppresses with it whatever their
# class, and every statistic that is internal_only or suppressed with another.
statistic_can_be_unwritten <- function(statistic) {
  kind <- statistic[["kind"]]
  kind %in% c("ratio", "real", "labels") ||
    (identical(kind, "count") && !identical(statistic[["count_class"]], "non_person")) ||
    !is.null(statistic[["measures"]]) ||
    isTRUE(statistic[["internal_only"]]) || !is.null(statistic[["suppress_with"]])
}

# Parameters whose value must be the same in every entry that has one (E4022).
registry_shared_parameters <- "agreement"

# The rules across entries: unique identifiers (E4003), the same value of a
# shared parameter in every entry that has it (E4022), links that name an
# entry (E4004) and no cycle of links (E4005). A link closes a cycle when the
# check it names reaches the linking entry through links, so every link on a
# cycle is reported.
registry_graph_issues <- function(entries) {
  issues <- list()
  ids <- vapply(entries, function(entry) entry[["id"]], "")
  for (i in which(duplicated(ids))) {
    issues <- c(issues, list(raw_issue("E4003", paste0("/entries/", i - 1L, "/id"),
                                       list(id = ids[i]))))
  }
  for (name in registry_shared_parameters) {
    first <- NULL
    for (i in seq_along(entries)) {
      value <- entries[[i]][["parameters"]][[name]][["value"]]
      if (is.null(value)) {
        next
      }
      if (is.null(first)) {
        first <- value
      } else if (!identical(value, first)) {
        pointer <- paste0(child_pointer(paste0("/entries/", i - 1L, "/parameters"), name), "/value")
        issues <- c(issues, list(raw_issue("E4022", pointer, list(expected = first))))
      }
    }
  }
  # The links of each entry, in pointer order, with their pointers.
  links <- lapply(entries, function(entry) {
    pointer <- character(0)
    target <- character(0)
    for (kind in c("explained_by", "requires")) {
      found <- unlist(entry[["links"]][[kind]])
      if (length(found)) {
        pointer <- c(pointer, paste0("/links/", kind, "/", seq_along(found) - 1L))
        target <- c(target, found)
      }
    }
    list(pointer = pointer, target = target)
  })
  edges <- list()
  for (i in seq_along(entries)) {
    known <- links[[i]]$target[links[[i]]$target %in% ids]
    edges[[ids[i]]] <- c(edges[[ids[i]]], known)
  }
  reaches <- function(start, goal) {
    seen <- character(0)
    stack <- start
    while (length(stack)) {
      current <- stack[length(stack)]
      stack <- stack[-length(stack)]
      if (current == goal) {
        return(TRUE)
      }
      if (!current %in% seen) {
        seen <- c(seen, current)
        stack <- c(stack, edges[[current]])
      }
    }
    FALSE
  }
  for (i in seq_along(entries)) {
    prefix <- paste0("/entries/", i - 1L)
    for (j in seq_along(links[[i]]$target)) {
      target <- links[[i]]$target[j]
      pointer <- paste0(prefix, links[[i]]$pointer[j])
      if (!target %in% ids) {
        issues <- c(issues, list(raw_issue("E4004", pointer, list(kind = "check", name = target))))
      } else if (reaches(target, ids[i])) {
        issues <- c(issues, list(raw_issue("E4005", pointer, list(check = target))))
      }
    }
  }
  issues
}
