# Print how R yaml::yaml.load types each scalar in a YAML file.
args <- commandArgs(trailingOnly = TRUE)
d <- yaml::yaml.load_file(args[1])
cat("yaml", as.character(packageVersion("yaml")), "\n")
for (k in names(d)) { v <- d[[k]]; cat(k, "\t", if (is.null(v)) "NULL" else class(v)[1], "\t", if (is.null(v)) "NULL" else deparse(v), "\n", sep = "") }
