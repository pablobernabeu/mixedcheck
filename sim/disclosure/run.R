# Runs the disclosure-attack tests of the privacy filter (sim/disclosure/README.md)
# and exits with status 1 when an attack recovers a value that
# docs/spec/privacy.md undertakes to hide, or when the harness fails.
#
#   Rscript sim/disclosure/run.R [--lib DIR] [--cores N] [--widen N]
#     [--attacks a,b,c,v] [--families NAME,...] [--out FILE] [--no-fail]
#
# --lib loads mixedcheck from a library other than the default ones, such as
# a copy installed from an earlier commit. --attacks chooses among the
# consistency search (a), the interval audit (b), the regression attacks (c)
# and the validation attacks (v), all by default. --families restricts the
# families of a and b. --out writes the results as an RDS file. --no-fail
# exits with status 0 whatever the results, as the historical check does.

options(warn = 1)
args <- commandArgs(trailingOnly = TRUE)
option <- function(name, default = NULL) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[i + 1L]
}
flag <- function(name) paste0("--", name) %in% args

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
here <- normalizePath(dirname(script))
root <- normalizePath(file.path(here, "..", ".."))
for (file in list.files(file.path(here, "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(file)
}

lib <- option("lib")
cores <- as.integer(option("cores", max(1L, parallel::detectCores() - 1L)))
widen <- as.integer(option("widen", "1"))
attacks <- strsplit(option("attacks", "a,b,c,v"), ",")[[1L]]
only <- option("families")
only <- if (is.null(only)) NULL else strsplit(only, ",")[[1L]]

ns <- dh_load(lib)
dh_capture_on(ns)
started <- proc.time()[["elapsed"]]
report <- dh_run_attacks(ns, root, attacks = attacks, families = only, cores = cores,
                         widen = widen, log = TRUE)
cat(sprintf("\nmixedcheck %s from %s, %.0f s\n", getNamespaceVersion(ns),
            dirname(getNamespaceInfo(ns, "path")), proc.time()[["elapsed"]] - started))
dh_print_report(report)
out <- option("out")
if (!is.null(out)) {
  saveRDS(report, out)
}
if (!flag("no-fail") && (nrow(report$leaks) > 0L || length(report$errors) > 0L)) {
  quit(status = 1L)
}
