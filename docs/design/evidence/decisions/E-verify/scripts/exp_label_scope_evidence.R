# Outcome-free (T0) evidence on ID scope that report E's experiment E1 does not use.
# For an inner label B that appears under several outer levels A, two kinds of
# evidence are available without the outcome:
#  (1) label pattern: inside each A level, B labels form the sequence 1..k_A
#      (restart numbering), which suggests local labels;
#  (2) attribute consistency: a covariate that should be constant for one real
#      unit (sex for a pupil, word frequency for an item) varies across the A
#      levels that share the label, which shows the label is NOT one unit.
# Neither is proof. Applied to mlmRev::Exam (student within school) and
# afex::fhch2010 (item crossed with participant).
# Usage: Rscript exp_label_scope_evidence.R <out_dir>
suppressPackageStartupMessages({library(mlmRev); library(afex)})
out_dir <- commandArgs(trailingOnly = TRUE)[1]
data("Exam", package = "mlmRev"); data("fhch2010", package = "afex")

restart_share <- function(outer, inner) {
  lab <- suppressWarnings(as.integer(as.character(inner)))
  if (anyNA(lab)) return(NA_real_)
  s <- tapply(lab, outer, function(x) { u <- sort(unique(x)); identical(u, seq_len(max(u))) })
  mean(s)
}
consistency <- function(outer, inner, attr) {
  # among inner labels seen under >1 outer level: share whose attribute varies
  multi <- names(which(tapply(outer, inner, function(x) length(unique(x))) > 1))
  if (!length(multi)) return(c(n_multi = 0, share_attr_varies = NA))
  keep <- inner %in% multi
  v <- tapply(as.character(attr[keep]), droplevels(factor(inner[keep])), function(x) length(unique(x)) > 1)
  c(n_multi = length(multi), share_attr_varies = round(mean(v), 4))
}
res <- rbind(
  data.frame(dataset = "mlmRev::Exam", outer = "school", inner = "student", attribute = "sex",
             restart_share = round(restart_share(Exam$school, Exam$student), 4),
             t(consistency(Exam$school, Exam$student, Exam$sex))),
  data.frame(dataset = "mlmRev::Exam", outer = "school", inner = "student", attribute = "vr (school-level band)",
             restart_share = NA, t(consistency(Exam$school, Exam$student, Exam$vr))),
  data.frame(dataset = "afex::fhch2010", outer = "id", inner = "item", attribute = "frequency",
             restart_share = NA, t(consistency(fhch2010$id, fhch2010$item, fhch2010$frequency))),
  data.frame(dataset = "afex::fhch2010", outer = "id", inner = "item", attribute = "length",
             restart_share = NA, t(consistency(fhch2010$id, fhch2010$item, fhch2010$length)))
)
# Exam student labels: are they numbered 1..k within each school?
st <- suppressWarnings(as.integer(as.character(Exam$student)))
ranges <- tapply(st, Exam$school, function(x) c(min = min(x), max = max(x), n = length(unique(x))))
rng <- do.call(rbind, ranges)
res$note <- ""
res$note[1] <- sprintf("student labels: min label per school ranges %d-%d; schools whose labels are exactly 1..k: %d of %d",
                       min(rng[, "min"]), max(rng[, "min"]), sum(rng[, "min"] == 1 & rng[, "max"] == rng[, "n"]), nrow(rng))
write.csv(res, file.path(out_dir, "label_scope_evidence.csv"), row.names = FALSE)
print(res, row.names = FALSE)
cat("\nExam student label summary by school (first 8):\n"); print(head(rng, 8))
cat("\nfhch2010 columns:", paste(names(fhch2010), collapse = ", "), "\n")
