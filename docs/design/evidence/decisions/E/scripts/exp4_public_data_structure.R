# Experiment E4: outcome-free structural audit of candidate public datasets,
# to see which real pathologies they carry (useful for the test corpus).
# For each ordered pair (outer A, inner B): share of B labels found under
# more than one A level, incidence fill rate, and bipartite components.
# Usage: Rscript exp4_public_data_structure.R <out_dir>
suppressPackageStartupMessages({library(lme4); library(mlmRev); library(nlme)})
args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "."

n_components <- function(a, b) {
  # connected components of the bipartite graph of observed (a, b) pairs,
  # by label propagation on integer codes (min label over edges until stable)
  ai <- as.integer(factor(a)); bi <- as.integer(factor(b)) + max(ai)
  e <- unique(cbind(ai, bi))
  lab <- seq_len(max(bi))
  repeat {
    m <- pmin(lab[e[, 1]], lab[e[, 2]])
    new <- lab
    new[e[, 1]] <- pmin(new[e[, 1]], ave(m, e[, 1], FUN = min))
    new[e[, 2]] <- pmin(new[e[, 2]], ave(m, e[, 2], FUN = min))
    new <- new[new]  # pointer jumping
    if (identical(new, lab)) break
    lab <- new
  }
  length(unique(lab[unique(c(e[, 1], e[, 2]))]))
}
pair_audit <- function(d, outer, inner, ds) {
  d <- d[!is.na(d[[outer]]) & !is.na(d[[inner]]), ]
  tab <- table(droplevels(as.factor(d[[inner]])), droplevels(as.factor(d[[outer]]))) > 0
  m <- rowSums(tab)
  data.frame(dataset = ds, outer = outer, inner = inner,
             n_outer = ncol(tab), n_inner = nrow(tab),
             share_inner_in_multiple_outer = round(mean(m > 1), 4),
             max_outer_per_inner = max(m),
             fill_rate = round(mean(tab), 4),
             components = n_components(d[[outer]], d[[inner]]),
             label = if (all(m == 1)) "nested" else if (all(tab)) "fully crossed" else "partially crossed")
}
size_summary <- function(d, g, ds) {
  n <- table(droplevels(as.factor(d[[g]])))
  data.frame(dataset = ds, factor = g, J = length(n), N = sum(n),
             singletons = sum(n == 1), pairs = sum(n == 2),
             median = median(n), max = max(n))
}
data(Exam); data(ScotsSec); data(star); data(guImmun); data(Hsb82)
data(sleepstudy, package = "lme4"); data(InstEval, package = "lme4")
star$tch_year <- interaction(star$tch, star$gr, drop = TRUE)
res <- rbind(
  pair_audit(Exam, "school", "student", "mlmRev::Exam"),
  pair_audit(ScotsSec, "primary", "second", "mlmRev::ScotsSec"),
  pair_audit(ScotsSec, "second", "primary", "mlmRev::ScotsSec"),
  pair_audit(star, "sch", "tch", "mlmRev::star"),
  pair_audit(star, "sch", "id", "mlmRev::star"),
  pair_audit(star, "tch", "id", "mlmRev::star"),
  pair_audit(guImmun, "comm", "mom", "mlmRev::guImmun"),
  pair_audit(InstEval, "s", "d", "lme4::InstEval"),
  pair_audit(InstEval, "dept", "d", "lme4::InstEval")
)
sizes <- rbind(size_summary(guImmun, "mom", "mlmRev::guImmun"),
               size_summary(Exam, "school", "mlmRev::Exam"),
               size_summary(ScotsSec, "primary", "mlmRev::ScotsSec"),
               size_summary(star, "tch_year", "mlmRev::star (teacher x grade)"))
# treatment constancy in STAR: is class type constant within teacher x grade?
ct <- tapply(star$cltype, star$tch_year, function(x) length(unique(x[!is.na(x)])))
star_check <- data.frame(teacher_grade_cells = length(ct),
                         cells_with_mixed_cltype = sum(ct > 1, na.rm = TRUE))
write.csv(res, file.path(out_dir, "exp4_pair_audit.csv"), row.names = FALSE)
write.csv(sizes, file.path(out_dir, "exp4_cluster_sizes.csv"), row.names = FALSE)
print(res, row.names = FALSE); print(sizes, row.names = FALSE); print(star_check)
