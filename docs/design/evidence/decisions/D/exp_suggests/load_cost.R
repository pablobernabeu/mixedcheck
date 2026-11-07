args <- commandArgs(TRUE); pkg <- args[1]; lib <- args[2]
before <- loadedNamespaces()
t <- system.time(suppressPackageStartupMessages(library(pkg, lib.loc = c(lib, .libPaths()), character.only = TRUE)))[["elapsed"]]
after <- setdiff(loadedNamespaces(), before)
cat(sprintf("%s\t%.3f\t%d\t%s\n", pkg, t, length(after), paste(sort(after), collapse = ",")))
