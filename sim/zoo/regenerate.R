# Writes or checks the stored instances of the pathology zoo (sim/zoo/README.md).
#
#   Rscript sim/zoo/regenerate.R                   # write every directory and index.json
#   Rscript sim/zoo/regenerate.R --only Z01,Z01N   # write these directories and index.json
#   Rscript sim/zoo/regenerate.R --check           # change nothing, compare, exit 1 on a difference
#
# The script sources sim/zoo/R/zoo.R and then sim/zoo/R/Z*.R in code-point
# order, each of which registers its definitions with zoo_define(). For each
# definition it calls the generator with the stored parameters, checks
# 'redraw' and the seed, prints the number of redraws and writes data.csv,
# declaration.json, formula.txt and expected.json into
# fixtures/zoo/<id>-<name>/, and it writes fixtures/zoo/index.json from every
# definition. --check writes everything into a temporary directory and
# compares it with fixtures/zoo/: every file byte for byte, apart from the
# reals of expected.json, which it compares within a relative tolerance of
# 1e-10 (zoo_same_expected()), since their last bits depend on the long
# double and the BLAS of the R that computes them. With --only, --check
# compares the directories named and index.json. Both modes check the limits
# on sizes, the reference values of zoo_gram() and the known answers of the
# helpers, and exit with status 1 when any problem is printed. Write mode
# writes nothing when a generator stops, so that index.json never loses the
# entry of a fixture. Any argument other than --check and --only VALUE stops
# the script. Base R only, and the bytes written do not depend on the locale.

args <- commandArgs(trailingOnly = TRUE)
check_mode <- FALSE
only <- NULL
i <- 1L
while (i <= length(args)) {
  if (identical(args[i], "--check")) {
    check_mode <- TRUE
  } else if (identical(args[i], "--only") && i < length(args) &&
             !startsWith(args[i + 1L], "--")) {
    only <- strsplit(args[i + 1L], ",", fixed = TRUE)[[1L]]
    i <- i + 1L
  } else {
    stop(paste0("regenerate.R takes --check and --only ID,..., not '", args[i], "'."),
         call. = FALSE)
  }
  i <- i + 1L
}

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
here <- normalizePath(dirname(script))
root <- normalizePath(file.path(here, "..", ".."))
zoo_root <- file.path(root, "fixtures", "zoo")

source(file.path(here, "R", "zoo.R"))
generator_files <- sort(list.files(file.path(here, "R"), pattern = "^Z[0-9]{2}[.]R$"),
                        method = "radix")
for (file in generator_files) {
  zoo_state$file <- file
  source(file.path(here, "R", file))
}
zoo_state$file <- NA_character_

definitions <- zoo_state$definitions
ids <- sort(names(definitions), method = "radix")
unknown <- setdiff(only, ids)
if (length(unknown)) {
  stop(paste0("--only names no definition: ", paste(unknown, collapse = ", "), "."), call. = FALSE)
}
problems <- character(0)
problem <- function(text) {
  problems <<- c(problems, text)
  cat(text, "\n", sep = "")
}

# The expected.json of a definition, from its data and the result of its
# expected function, with the members in the order of fixtures/zoo/README.md.
zoo_document <- function(definition, data, result) {
  document <- list(
    zoo = "0.1.0", id = definition$id, name = definition$name, title = definition$title,
    role = definition$role, matched = definition$matched,
    negative_of = zn(sort(definition$negative_of, method = "radix")),
    domain = definition$domain, catalogue = zn(definition$catalogue),
    planted = definition$planted, registry = "0.1.0", vocabulary = "0.1.0",
    generator = list(file = definition$file, "function" = definition[["function"]],
                     seed = definition$seed, rng = zn(zoo_rng),
                     parameters = definition$parameters),
    run = definition$run, rows = nrow(data)
  )
  if (!is.null(result$issue)) {
    document$issue <- result$issue
  } else {
    document$samples <- result$samples
    document$findings <- zoo_order(result$findings)
  }
  document$signal <- definition$signal
  document$planned <- definition$planned
  if (!is.null(definition$deferred)) {
    document$deferred <- definition$deferred
  }
  document
}

# Builds one directory: the generated data and the four files' contents.
zoo_build <- function(definition) {
  p <- definition$parameters
  data <- definition$generate(p, "redraw", definition$seed)
  redraws <- attr(data, "zoo_redraws")
  attr(data, "zoo_redraws") <- NULL
  declaration <- definition$declaration(p)
  result <- definition$expected(p, data)
  list(data = data, redraws = if (is.null(redraws)) 0L else redraws,
       declaration = declaration, formula = definition$formula(p),
       document = zoo_document(definition, data, result))
}

zoo_write_directory <- function(definition, built, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  csv <- definition$csv
  zoo_write_csv(built$data, built$declaration$table$fields, file.path(directory, "data.csv"),
                csv$eol, csv$digits, csv$missing)
  zoo_write_json(built$declaration, file.path(directory, "declaration.json"), "declaration")
  zoo_write_text(paste0(built$formula, "\n"), file.path(directory, "formula.txt"))
  zoo_write_json(built$document, file.path(directory, "expected.json"), "expected")
}

# The smallest eigenvalue that a document's gram_rank finding writes.
zoo_written_eigenvalue <- function(document) {
  for (finding in document$findings) {
    if (identical(finding$check, "identifiability.gram_rank")) {
      return(finding$statistics$smallest_eigenvalue$value)
    }
  }
  NULL
}

directories <- function(x) paste0(length(x), if (length(x) == 1L) " directory" else " directories")

built <- list()
for (id in ids) {
  outcome <- tryCatch(zoo_build(definitions[[id]]), error = function(e) e)
  if (inherits(outcome, "error")) {
    problem(paste0(id, ": the generator or its expected function stops: ",
                   conditionMessage(outcome)))
    next
  }
  built[[id]] <- outcome
  if (is.null(only) || id %in% only) {
    cat(id, ": ", outcome$redraws, " redraws\n", sep = "")
  }
  reference <- zoo_gram_reference[id]
  value <- zoo_written_eigenvalue(outcome$document)
  if (!is.na(reference) && !is.null(value) && abs(value - reference) > 5e-8) {
    problem(paste0(id, ": zoo_gram() gives ", zoo_json_number(value),
                   ", which differs from the reference value ", zoo_json_number(reference),
                   " of the design by more than 5e-8"))
  }
}
for (text in zoo_self_test()) {
  problem(text)
}

index <- list(zoo = "0.1.0", registry = "0.1.0", fixtures = lapply(names(built), function(id) {
  definition <- definitions[[id]]
  list(id = id, name = definition$name, title = definition$title, role = definition$role,
       matched = definition$matched, tier = definition$run$outcome_access,
       rows = nrow(built[[id]]$data), domain = definition$domain,
       deferred = !is.null(definition$deferred))
}))
selected <- if (is.null(only)) names(built) else intersect(only, names(built))
failed <- setdiff(ids, names(built))
if (!check_mode && length(failed)) {
  cat("Wrote nothing, since ", directories(failed), " could not be built.\n", sep = "")
  cat(length(problems), " problem(s).\n", sep = "")
  quit(status = 1L)
}
target <- if (check_mode) file.path(tempfile("zoo-"), "zoo") else zoo_root
dir.create(target, recursive = TRUE, showWarnings = FALSE)
for (id in selected) {
  definition <- definitions[[id]]
  zoo_write_directory(definition, built[[id]], file.path(target, zoo_directory(definition)))
}
zoo_write_json(index, file.path(target, "index.json"), "expected")

# The limits on sizes of sim/zoo/README.md, measured on the files written:
# each file rounded up to a multiple of 4096 bytes plus 4096 bytes for each
# directory, as du measures them.
written <- list.files(target, recursive = TRUE)
sizes <- file.size(file.path(target, written))
block <- function(bytes) 4096 * ceiling(bytes / 4096)
for (i in seq_along(written)) {
  limit <- c(data.csv = 16384, expected.json = 24576)[basename(written[i])]
  if (!is.na(limit) && sizes[i] > limit) {
    problem(paste0(written[i], ": ", sizes[i], " bytes, above the limit of ", limit))
  }
}
if (is.null(only)) {
  csv_total <- sum(sizes[basename(written) == "data.csv"])
  if (csv_total > 250 * 1024) {
    problem(paste0("the data.csv files hold ", csv_total, " bytes, above the limit of 256000"))
  }
  readme <- file.path(zoo_root, "README.md")
  disk <- sum(block(sizes)) + 4096 * (length(selected) + 1L) +
    if (file.exists(readme)) block(file.size(readme)) else 0
  if (disk > 2.2 * 1024 * 1024) {
    problem(paste0("fixtures/zoo/ takes ", disk, " bytes on disk, above the limit of 2.2 MB"))
  }
}

if (check_mode) {
  # Compares the files written with the stored ones byte for byte.
  for (name in written) {
    stored <- file.path(zoo_root, name)
    shown <- paste0("fixtures/zoo/", name)
    if (!file.exists(stored)) {
      problem(paste0(shown, ": missing, the generator writes it"))
      next
    }
    a <- readBin(file.path(target, name), "raw", file.size(file.path(target, name)))
    b <- readBin(stored, "raw", file.size(stored))
    if (identical(a, b)) {
      next
    }
    if (basename(name) == "expected.json") {
      difference <- zoo_same_expected(rawToChar(a), rawToChar(b))
      if (!is.null(difference)) {
        problem(paste0(shown, ": differs from what its generator writes, ", difference))
      }
      next
    }
    n <- min(length(a), length(b))
    at <- which(a[seq_len(n)] != b[seq_len(n)])
    at <- if (length(at)) at[1L] - 1L else n
    problem(paste0(shown, ": differs from what its generator writes, first at byte ", at))
  }
  if (is.null(only)) {
    stored <- list.files(zoo_root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE,
                         no.. = TRUE)
    written_directories <- unique(dirname(written))
    for (name in sort(stored, method = "radix")) {
      if (name == "README.md" || name %in% written || name %in% written_directories) {
        next
      }
      problem(paste0("fixtures/zoo/", name, ": no generator writes it"))
    }
  }
  unlink(dirname(target), recursive = TRUE)
  if (!length(problems)) {
    cat("Every stored file of the zoo is what its generator writes (", directories(selected),
        ").\n", sep = "")
  }
} else {
  cat("Wrote ", directories(selected), " and index.json under fixtures/zoo/.\n", sep = "")
}
if (length(problems)) {
  cat(length(problems), " problem(s).\n", sep = "")
  quit(status = 1L)
}
