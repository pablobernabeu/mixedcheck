#!/bin/bash
# Build lme4 2.1-0 (and the newer deps it needs) from the CRAN GitHub mirror into a private library.
set -u
B=/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/A-verify
cd $B/rsrc
export MAKEFLAGS="-j4"
for p in rbibutils Rdpack reformulas Rcpp lme4; do
  echo "=== $p $(date +%T)"
  [ -d $p ] || timeout 300 git clone -q --depth 1 https://github.com/cran/$p $p
  grep -E "^Version" $p/DESCRIPTION
  R_LIBS=$B/rlib R CMD INSTALL --no-test-load --no-docs --no-html --library=$B/rlib $p > $B/out/build_$p.log 2>&1
  echo "exit $? $(date +%T)"; tail -2 $B/out/build_$p.log
done
R_LIBS=$B/rlib Rscript -e 'library(lme4, lib.loc=Sys.getenv("R_LIBS")); cat("loaded lme4", as.character(packageVersion("lme4", lib.loc=Sys.getenv("R_LIBS"))), "\n")'
