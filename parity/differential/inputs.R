# Writes the inputs of the differential test of the two packages
# (parity/README.md, Differential test): every table of every family of the
# disclosure-attack harness (sim/disclosure/R/families.R and the zoo families
# of sim/disclosure/R/zoo.R) at the family's k, the realistic designs of
# designs.R at the registry's k, the edge cases of edges.R, each at its own
# k, the tables of the regression attacks of the harness
# (sim/disclosure/R/regressions.R), at the k that each attack sets, each with
# every argument that audit() receives, and every fixture and matched
# negative of the pathology zoo at the registry's k and at k = 3.
#
#   Rscript parity/differential/inputs.R OUT [--seeds N] [--edge-seeds N]
#     [--widen N] [--families NAME,...] [--designs NAME,...]
#     [--edges NAME,...] [--regressions NAME,...] [--zoo ID,...] [--chunk N]
#
# OUT receives index.json, which lists the files of inputs and the tables
# that their families cannot build, and the files. --seeds sets the number of
# seeds of each design (3 by default), --edge-seeds that of each edge (25 by
# default), --widen widens the grid of every family as the harness does (0 by
# default), --families, --designs, --edges and --regressions, the
# identifiers of attacks, and --zoo, the identifiers of the pathology zoo,
# restrict the sources, with 'none' for none, and --chunk sets the most
# inputs in one file (40 by default), which also holds at most 4000 rows past
# its first input. The script needs a UTF-8 locale, in which the labels of
# the families are read, and the installed mixedcheck, whose canonical writer
# writes the files and whose pathology_zoo() lists the zoo.
#
# Each file is a JSON object with the member 'inputs', a list of inputs, each
# with these members:
# - id: 'family/NAME/I', the table I of the family's grid in the order of
#   dh_grid(), 'design/NAME/OUTCOME/TIER/missing-COUNT/seed-S',
#   'edge/NAME/seed-S', 'regression/ATTACK/I', the run I of the attack, or
#   'zoo/ID/kK', the fixture ID of the pathology zoo at k = K
# - source: what rebuilds the input, the family with its parameters, the
#   design with its outcome, tier, rows without an outcome and seed, the
#   edge with its seed, the attack with the position of its run or the
#   fixture with its rows
# - k: the minimum count of the run
# - formula and arguments: the formula and the other arguments of audit(),
#   declaration, family, coding, weights, sample_columns, outcome_access,
#   reason, exploratory and outcome_seen, those that the input sets
# - data: the columns in order, each with its name, its type, 'double',
#   'integer', 'logical', 'string' or 'factor', its levels in order for a
#   factor and its values, with null for NA and, in a double column, the
#   strings 'NaN', 'Infinity', '-Infinity' and '-0' for the special values
# An input of the zoo holds id, source, k and fixture, the identifier, in
# place of formula, arguments and data: the runners read the fixture with
# pathology_zoo() of the installed package, which gives its data, formula,
# declaration and run.

options(warn = 1)
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[i + 1L]
}
listed <- function(name) {
  value <- option(name)
  if (is.null(value)) NULL else strsplit(value, ",")[[1L]]
}

if (!isTRUE(l10n_info()[["UTF-8"]])) {
  stop("inputs.R needs a UTF-8 locale, such as LC_ALL=C.UTF-8.", call. = FALSE)
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
here <- normalizePath(dirname(script))
root <- normalizePath(file.path(here, "..", ".."))
source(file.path(root, "sim", "disclosure", "R", "families.R"), encoding = "UTF-8")
source(file.path(root, "sim", "disclosure", "R", "zoo.R"), encoding = "UTF-8")
source(file.path(here, "designs.R"), encoding = "UTF-8")
source(file.path(here, "edges.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(mixedcheck))

out <- args[1L]
if (is.na(out) || startsWith(out, "--")) {
  stop("Usage: Rscript parity/differential/inputs.R OUT [options]", call. = FALSE)
}
seeds <- as.integer(option("seeds", "3"))
edge_seeds <- as.integer(option("edge-seeds", "25"))
widen <- as.integer(option("widen", "0"))
chunk <- as.integer(option("chunk", "40"))
only_families <- listed("families")
only_designs <- listed("designs")
only_edges <- listed("edges")
only_regressions <- listed("regressions")
only_zoo <- listed("zoo")

# The arguments of audit() that an input may set, besides data, formula,
# privacy and key, which the runners set.
arguments <- c("declaration", "family", "coding", "weights", "sample_columns", "outcome_access",
               "reason", "exploratory", "outcome_seen")
registry_k <- read_registry()[["privacy"]][["min_count"]]
reason <- "Differential test of the two packages."

# --- Writing values ----------------------------------------------------------------

# A value of R as a value that the canonical writer accepts: a list for every
# array, so that a vector of one element stays an array.
json_value <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.list(x)) {
    value <- lapply(x, json_value)
    if (!is.null(names(x))) {
      names(value) <- names(x)
    }
    return(value)
  }
  if (is.character(x)) {
    x <- enc2utf8(x)
  }
  if (length(x) == 1L) x else as.list(x)
}

double_value <- function(v) {
  if (is.nan(v)) {
    return("NaN")
  }
  if (is.na(v)) {
    return(NULL)
  }
  if (is.infinite(v)) {
    return(if (v > 0) "Infinity" else "-Infinity")
  }
  if (v == 0 && 1 / v < 0) {
    return("-0")
  }
  v
}

column_json <- function(name, x) {
  column <- list(name = enc2utf8(name))
  if (is.factor(x)) {
    labels <- enc2utf8(levels(x))
    column$type <- "factor"
    column$levels <- as.list(labels)
    values <- labels[as.integer(x)]
  } else if (is.logical(x)) {
    column$type <- "logical"
    values <- x
  } else if (is.integer(x)) {
    column$type <- "integer"
    values <- x
  } else if (is.double(x)) {
    column$type <- "double"
    column$values <- lapply(as.double(x), double_value)
    return(column)
  } else if (is.character(x)) {
    column$type <- "string"
    values <- enc2utf8(x)
  } else {
    stop(sprintf("The column '%s' has the type %s.", name, typeof(x)), call. = FALSE)
  }
  if (is.character(values) && !all(validUTF8(values[!is.na(values)]))) {
    stop(sprintf("The column '%s' holds a string that is not valid UTF-8.", name), call. = FALSE)
  }
  column$values <- lapply(values, function(v) if (is.na(v)) NULL else v)
  column
}

input_json <- function(id, source, k, formula, args, data) {
  unknown <- setdiff(names(args), arguments)
  if (length(unknown)) {
    stop(sprintf("%s passes audit() the argument %s, which the runners do not know.", id,
                 paste(unknown, collapse = ", ")), call. = FALSE)
  }
  args <- args[!vapply(args, is.null, NA)]
  set <- json_value(args[intersect(arguments, names(args))])
  list(
    id = id,
    source = source,
    k = k,
    formula = formula,
    arguments = set %||% setNames(list(), character(0)),
    data = lapply(names(data), function(name) column_json(name, data[[name]]))
  )
}

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

# --- Families ----------------------------------------------------------------------

# The inputs of a family. A table that the family cannot build, as some
# tables of a widened grid, is left out and listed in index.json with its
# error, as the harness leaves it out of its search.
unbuilt <- list()
family_inputs <- function(family) {
  grid <- dh_grid(family, widen = widen)
  inputs <- lapply(seq_len(nrow(grid)), function(i) {
    parameters <- as.list(grid[i, , drop = FALSE])
    id <- sprintf("family/%s/%d", family$name, i)
    case <- tryCatch(family$build(parameters), error = function(e) e)
    if (inherits(case, "error")) {
      unbuilt[[length(unbuilt) + 1L]] <<- list(id = id, error = conditionMessage(case))
      return(NULL)
    }
    source <- list(kind = "family", family = family$name, table = i,
                   parameters = lapply(parameters, as.integer), widen = widen)
    input_json(id, source, family$k, case$formula, case$args, case$data)
  })
  Filter(Negate(is.null), inputs)
}

# --- Designs -----------------------------------------------------------------------

outcomes <- c("gaussian", "poisson", "binomial")
tiers <- c("T0", "T1", "T2")

# The numbers of rows without an outcome: none, one, a few, k - 1 and many,
# a third of the rows.
missing_counts <- function(n, k) {
  counts <- c(none = 0L, one = 1L, few = 3L, `k-1` = as.integer(k) - 1L,
              many = as.integer(ceiling(n / 3)))
  counts[counts < n & !duplicated(counts)]
}

design_inputs <- function(design, index) {
  inputs <- list()
  for (seed in seq_len(seeds)) {
    base <- 1000L * index + seed
    set.seed(base, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
    built <- design$build(seed)
    n <- nrow(built$data)
    order <- sample.int(n)
    for (outcome in outcomes) {
      set.seed(base + 100L * match(outcome, outcomes))
      eta <- built$eta
      data <- built$data
      declaration <- built$declaration
      family <- outcome
      if (outcome == "gaussian") {
        y <- round(1 + eta + stats::rnorm(n), 3)
        # Odd seeds leave the family to its default, the class gaussian.
        if (seed %% 2L == 1L) {
          family <- NULL
        }
      } else if (outcome == "poisson") {
        y <- stats::rpois(n, exp(0.8 + 0.5 * eta))
      } else {
        trials <- sample(4:12, n, replace = TRUE)
        y <- stats::rbinom(n, trials, stats::plogis(eta - 0.5))
        data$trials <- trials
        declaration <- declaration %||% list(vocabulary = "0.1.0")
        declaration$variables <- list(y = list(role = "outcome", measurement = "binomial",
                                               trials = "trials"))
      }
      counts <- missing_counts(n, registry_k)
      for (tier in tiers) {
        for (label in names(counts)) {
          missing <- counts[[label]]
          y_missing <- y
          y_missing[order[seq_len(missing)]] <- NA
          rows <- cbind(data, y = y_missing)
          args <- list(declaration = declaration, family = family, coding = built$coding,
                       weights = built$weights, sample_columns = built$sample_columns)
          if (tier != "T0") {
            args <- c(args, list(outcome_access = tier, reason = reason))
            # The first seed of every three attests that the outcome was seen.
            if (seed %% 3L == 1L) {
              args$outcome_seen <- TRUE
            }
          }
          if (tier == "T2") {
            args$exploratory <- TRUE
          }
          id <- sprintf("design/%s/%s/%s/missing-%d/seed-%d", design$name, outcome, tier,
                        missing, seed)
          source <- list(kind = "design", design = design$name, outcome = outcome, tier = tier,
                         missing = missing, missing_label = label, seed = seed, rows = n)
          inputs[[length(inputs) + 1L]] <- input_json(
            id, source, registry_k, paste("y ~", built$rhs), args, rows)
        }
      }
    }
  }
  inputs
}

# --- Edges -------------------------------------------------------------------------

# The inputs of an edge: one for each seed, each at the k and tier that the
# edge draws.
edge_inputs <- function(edge, index) {
  lapply(seq_len(edge_seeds), function(seed) {
    set.seed(100000L + 1000L * index + seed, kind = "Mersenne-Twister",
             normal.kind = "Inversion", sample.kind = "Rejection")
    built <- edge$build(seed)
    id <- sprintf("edge/%s/seed-%d", edge$name, seed)
    source <- list(kind = "edge", edge = edge$name, seed = seed, tier = built$tier,
                   rows = nrow(built$data))
    input_json(id, source, built$k, built$formula, built$args, built$data)
  })
}

# --- Regressions -------------------------------------------------------------------

# The tables of the regression attacks: every run of audit() that an attack
# makes on the installed package, at the k that it sets, recorded by a
# dh_run() that runs the case as the harness does. An attack that cannot run
# leaves the runs it made before.
regression_inputs <- function() {
  harness <- new.env()
  for (file in c("harness.R", "regressions.R")) {
    sys.source(file.path(root, "sim", "disclosure", "R", file), envir = harness,
               keep.source = FALSE)
  }
  ns <- asNamespace("mixedcheck")
  found <- list()
  for (attack in harness$rg_attacks()) {
    if (!is.null(only_regressions) && !attack$id %in% only_regressions) {
      next
    }
    runs <- list()
    harness$dh_run <- function(ns, case) {
      runs[[length(runs) + 1L]] <<- list(case = case, k = harness$dh_k(ns))
      args <- c(list(case$data, case$formula), case$args, list(key = harness$dh_key))
      results <- tryCatch(do.call(ns$audit, args), error = function(e) e)
      if (inherits(results, "error")) list(error = conditionMessage(results)) else
        list(document = results$document)
    }
    tryCatch(attack$attack(ns, root), error = function(e) NULL)
    for (j in seq_along(runs)) {
      run <- runs[[j]]
      id <- sprintf("regression/%s/%d", attack$id, j)
      source <- list(kind = "regression", attack = attack$id, run = j,
                     rows = nrow(run$case$data))
      found[[length(found) + 1L]] <- input_json(id, source, run$k, run$case$formula,
                                               run$case$args, run$case$data)
    }
  }
  found
}

# --- The pathology zoo -------------------------------------------------------------

# Two inputs for each fixture and matched negative of the installed zoo, at
# the registry's k and at k = 3, which the runners build with pathology_zoo().
zoo_inputs <- function() {
  listing <- pathology_zoo()
  unknown <- setdiff(only_zoo, c(listing$id, "none"))
  if (length(unknown)) {
    stop(sprintf("--zoo names no fixture of the pathology zoo: %s.",
                 paste(unknown, collapse = ", ")), call. = FALSE)
  }
  inputs <- list()
  for (i in seq_len(nrow(listing))) {
    id <- listing$id[i]
    if (!is.null(only_zoo) && !id %in% only_zoo) {
      next
    }
    for (k in c(registry_k, 3L)) {
      inputs[[length(inputs) + 1L]] <- list(
        id = sprintf("zoo/%s/k%d", id, k),
        source = list(kind = "zoo", fixture = id, rows = listing$rows[i]),
        k = k,
        fixture = id
      )
    }
  }
  inputs
}

# --- Writing the files -------------------------------------------------------------

dir.create(out, recursive = TRUE, showWarnings = FALSE)
chunks <- list()
write_source <- function(kind, name, description, inputs) {
  if (!length(inputs)) {
    return(invisible())
  }
  dir.create(file.path(out, kind), showWarnings = FALSE)
  # A file holds at most chunk inputs and, past its first input, at most
  # 4000 rows, so that the files take similar times to run.
  rows <- vapply(inputs, function(input) {
    if (is.null(input$fixture)) length(input$data[[1L]]$values) else as.integer(input$source$rows)
  }, 0L)
  group <- integer(length(inputs))
  current <- 1L
  count <- 0L
  total <- 0L
  for (i in seq_along(inputs)) {
    if (count > 0L && (count >= chunk || total + rows[i] > 4000L)) {
      current <- current + 1L
      count <- 0L
      total <- 0L
    }
    group[i] <- current
    count <- count + 1L
    total <- total + rows[i]
  }
  for (j in seq_len(current)) {
    part <- inputs[group == j]
    file <- sprintf("%s/%s-%03d.json", kind, name, j)
    writeBin(canonical_bytes(list(inputs = part), "data"), file.path(out, file))
    chunks[[length(chunks) + 1L]] <<- list(
      file = file, source = paste(sub("s$", "", kind), name), description = description,
      inputs = length(part), ids = lapply(part, function(input) input$id))
  }
}

started <- proc.time()[["elapsed"]]
for (family in dh_families()) {
  if (!is.null(only_families) && !family$name %in% only_families) {
    next
  }
  write_source("families", family$name, family$description, family_inputs(family))
}
designs <- dd_designs()
for (index in seq_along(designs)) {
  design <- designs[[index]]
  if (!is.null(only_designs) && !design$name %in% only_designs) {
    next
  }
  write_source("designs", design$name, design$description, design_inputs(design, index))
}
edges <- de_edges()
for (index in seq_along(edges)) {
  edge <- edges[[index]]
  if (!is.null(only_edges) && !edge$name %in% only_edges) {
    next
  }
  write_source("edges", edge$name, edge$description, edge_inputs(edge, index))
}
if (!identical(only_regressions, "none")) {
  write_source("regressions", "attacks",
               "the tables of the regression attacks of the disclosure-attack harness",
               regression_inputs())
}
if (!identical(only_zoo, "none")) {
  write_source("zoo", "fixtures",
               "the fixtures and matched negatives of the pathology zoo at the registry's k and 3",
               zoo_inputs())
}
total <- sum(vapply(chunks, function(chunk) chunk$inputs, 0L))
index <- list(
  description = "The inputs of the differential test of the two packages (parity/README.md).",
  generator = list(r = R.version.string, mixedcheck = as.character(packageVersion("mixedcheck")),
                   seeds = seeds, edge_seeds = edge_seeds, widen = widen, chunk = chunk,
                   key = paste(sprintf("%02x", 0:31), collapse = ""), registry_k = registry_k),
  inputs = total,
  chunks = chunks,
  unbuilt = unbuilt
)
writeBin(canonical_bytes(json_value(index), "data"), file.path(out, "index.json"))
cat(sprintf("%d inputs in %d files written to %s in %.0f s\n", total, length(chunks), out,
            proc.time()[["elapsed"]] - started))
if (length(unbuilt)) {
  cat(sprintf("%d tables that their families cannot build are left out, such as %s: %s\n",
              length(unbuilt), unbuilt[[1L]]$id, unbuilt[[1L]]$error))
}
