# Experiment E3: can the observation key be inferred from the data?
# Enumerate minimal column sets (size <= 3) that identify rows uniquely, on
# real datasets shipped with installed packages, and flag those that rely on
# measured (outcome or continuous) columns rather than design columns.
# Usage: Rscript exp3_key_inference.R <out_dir>
suppressPackageStartupMessages({library(lme4); library(afex); library(mlmRev)})
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "."

minimal_keys <- function(d, max_size = 3) {
  cols <- names(d); found <- list()
  for (k in seq_len(max_size)) {
    for (cmb in combn(cols, k, simplify = FALSE)) {
      if (any(vapply(found, function(f) all(f %in% cmb), logical(1)))) next
      if (!anyDuplicated(d[, cmb, drop = FALSE])) found[[length(found) + 1]] <- cmb
    }
  }
  vapply(found, paste, character(1), collapse = "+")
}

data("sleepstudy", package = "lme4")
data("fhch2010", package = "afex")
data("Exam", package = "mlmRev")
sets <- list(
  sleepstudy = list(d = sleepstudy, design = c("Subject", "Days"),
                    measured = "Reaction"),
  fhch2010 = list(d = fhch2010, design = c("id", "task", "stimulus", "density",
                                            "frequency", "length", "item"),
                  measured = c("rt", "log_rt", "correct")),
  Exam = list(d = Exam, design = c("school", "student", "schgend", "type", "sex"),
              measured = c("normexam", "standLRT", "vr", "intake", "schavg"))
)
rows <- list()
for (nm in names(sets)) {
  s <- sets[[nm]]
  keys <- minimal_keys(s$d)
  uses_measured <- vapply(strsplit(keys, "+", fixed = TRUE),
                          function(k) any(k %in% s$measured), logical(1))
  n_dup_rows <- sum(duplicated(s$d))
  rows[[nm]] <- data.frame(dataset = nm, n_rows = nrow(s$d),
                           exact_duplicate_rows = n_dup_rows,
                           minimal_key = if (length(keys)) keys else "(none up to size 3)",
                           uses_measured_column = if (length(keys)) uses_measured else NA)
}
out <- do.call(rbind, rows)
write.csv(out, file.path(out_dir, "exp3_key_inference.csv"), row.names = FALSE)
print(out, row.names = FALSE)
