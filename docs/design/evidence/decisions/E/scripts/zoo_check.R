# Independent R re-computation of selected by-construction findings of the
# pathology-zoo prototype, reading each CSV with the column types and missing
# tokens declared in design.json (Frictionless Table Schema subset), never with
# R's type guessing.
# Usage: Rscript zoo_check.R <zoo_dir>
suppressPackageStartupMessages(library(jsonlite))
zoo <- commandArgs(trailingOnly = TRUE)[1]

read_fixture <- function(dir) {
  des <- parse_json(readLines(file.path(dir, "design.json"), encoding = "UTF-8", warn = FALSE) |> paste(collapse = "\n"),
                    simplifyVector = FALSE)
  f <- des$table$fields
  map <- c(string = "character", integer = "integer", number = "numeric", boolean = "logical")
  cls <- setNames(map[vapply(f, function(x) if (is.null(x$type)) "string" else x$type, "")],
                  vapply(f, `[[`, "", "name"))
  d <- read.csv(file.path(dir, "data.csv"), colClasses = cls, na.strings = unlist(des$table$missingValues),
                encoding = "UTF-8", check.names = FALSE)
  # declared categories fix the level order; never the locale's sort order
  for (x in f) if (!is.null(x$categories)) d[[x$name]] <- factor(d[[x$name]], levels = unlist(x$categories))
  list(d = d, des = des, exp = fromJSON(file.path(dir, "expected.json"), simplifyVector = FALSE))
}
share_multi <- function(d, outer, inner) mean(tapply(d[[outer]], d[[inner]], function(x) length(unique(x))) > 1)
same_partition <- function(a, b) {
  length(unique(a)) == length(unique(paste(a, b, sep = "\r"))) &&
    length(unique(b)) == length(unique(paste(a, b, sep = "\r")))
}
components <- function(a, b) {
  ai <- as.integer(factor(a)); bi <- as.integer(factor(b)) + max(ai)
  e <- unique(cbind(ai, bi)); lab <- seq_len(max(bi))
  repeat {
    m <- pmin(lab[e[, 1]], lab[e[, 2]]); new <- lab
    new[e[, 1]] <- pmin(new[e[, 1]], ave(m, e[, 1], FUN = min))
    new[e[, 2]] <- pmin(new[e[, 2]], ave(m, e[, 2], FUN = min))
    new <- new[new]; if (identical(new, lab)) break; lab <- new
  }
  length(unique(lab[unique(c(e[, 1], e[, 2]))]))
}
res <- list()
add <- function(fx, what, got, want) res[[length(res) + 1]] <<- data.frame(fixture = fx, quantity = what, R = format(got), expected = format(want), match = isTRUE(all.equal(got, want)))

x <- read_fixture(file.path(zoo, "Z01_reused_class_labels"))
add("Z01", "share inner labels in >1 school", share_multi(x$d, "school", "class"), x$exp$findings[[1]]$share_inner_labels_in_multiple_outer)
add("Z01", "groups of school:class (tuple-coded)", nrow(unique(x$d[c("school", "class")])), x$exp$findings[[3]]$n_groups)
x <- read_fixture(file.path(zoo, "Z01_neg_unique_class_labels"))
add("Z01_neg", "share inner labels in >1 school", share_multi(x$d, "school", "class"), x$exp$findings[[1]]$share_inner_labels_in_multiple_outer)
x <- read_fixture(file.path(zoo, "Z02_mobility"))
mv <- names(which(tapply(x$d$school, x$d$pupil, function(s) length(unique(s))) > 1))
add("Z02", "pupils changing school", paste(sort(mv), collapse = ","), paste(unlist(x$exp$findings[[1]]$units_changing_outer), collapse = ","))
x <- read_fixture(file.path(zoo, "Z04_aliased_grouping"))
add("Z04", "school and class partitions identical", same_partition(x$d$school, x$d$class), TRUE)
x <- read_fixture(file.path(zoo, "Z07_latin_square_one_obs_per_cell"))
add("Z07", "max obs per subject:item", max(table(paste(x$d$subject, x$d$item))), x$exp$findings[[1]]$max_obs_per_level)
add("Z07", "level order of cond from categories", paste(levels(x$d$cond), collapse = ","), "A,B,C")
x <- read_fixture(file.path(zoo, "Z09_crt_treatment_mixed_within_unit"))
mixed <- names(which(tapply(x$d$arm, x$d$class, function(a) length(unique(a))) > 1))
add("Z09", "classes with mixed arm", paste(sort(mixed), collapse = ","), paste(unlist(x$exp$findings[[3]]$units_with_mixed_assignment), collapse = ","))
x <- read_fixture(file.path(zoo, "Z11_families_singletons"))
add("Z11", "singleton families", sum(table(x$d$family) == 1), x$exp$findings[[1]]$singletons)
x <- read_fixture(file.path(zoo, "Z13_disconnected_crossed"))
add("Z13", "subject-item components", components(x$d$subject, x$d$item), x$exp$findings[[1]]$components)
x <- read_fixture(file.path(zoo, "Z17_duplicate_keys"))
add("Z17", "duplicated (subject, trial) keys", sum(duplicated(x$d[c("subject", "trial")])), x$exp$findings[[1]]$duplicated_keys)
out <- do.call(rbind, res)
print(out, row.names = FALSE)
cat("all match:", all(out$match), "\n")
