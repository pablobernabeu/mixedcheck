| Package | CRAN version (published) | Licence | Depends R | Direct Imports (+LinkingTo) | Compiled | Recursive hard deps: runtime / +LinkingTo (non-recommended) | Compiled in closure (non-rec.) | Highest R floor in closure, excluding recommended pkgs (set by) |
|---|---|---|---|---|---|---|---|---|
| lme4 | 2.1-0 (2026-10-23) | GPL (>= 2) | >= 3.6 | MASS, Rdpack, boot, lattice, minqa, nlme, nloptr, reformulas ; LinkingTo: Matrix, Rcpp, RcppEigen | yes | 11 / 12 (6 / 7) | 9 (5) | 3.6.0 (RcppEigen) |
| glmmTMB | 1.1.15.2 (2026-09-29) | AGPL-3 | >= 3.6.0 | RTMB, TMB, lme4, Matrix, nlme, numDeriv, mgcv, reformulas, pbkrtest, sandwich ; LinkingTo: TMB, RcppEigen | yes | 60 / 63 (53 / 56) | 38 (32) | 4.5 (Deriv) |
| reformulas | 0.4.4 (2026-02-02) | GPL-3 | - | Matrix, Rdpack | no | 4 / 4 (2 / 2) | 3 (1) | 2.15.0 (Rdpack) |
| Matrix | 1.7-6 (2026-07-25) | GPL (>= 2) \| file LICENCE | >= 4.4 | lattice | yes | 1 / 1 (0 / 0) | 1 (0) | - |
| performance | 0.19.0 (2026-10-18) | GPL-3 | >= 4.0 | bayestestR, insight, datawizard | no | 3 / 3 (3 / 3) | 0 (0) | 4.0 (datawizard) |
| insight | 1.7.0 (2026-10-30) | GPL-3 | >= 3.6 | (base only) | no | 0 / 0 (0 / 0) | 0 (0) | 3.6 (insight) |
| datawizard | 1.5.0 (2026-11-04) | MIT + file LICENSE | >= 4.0 | insight | no | 1 / 1 (1 / 1) | 0 (0) | 4.0 (datawizard) |
| bayestestR | 0.20.0 (2026-10-16) | GPL-3 | >= 3.6 | insight, datawizard | no | 2 / 2 (2 / 2) | 0 (0) | 4.0 (datawizard) |
| DHARMa | 0.5.0 (2026-06-01) | GPL (>= 3) | >= 3.5.0 | Matrix, gap, lmtest, ape, qgam, lme4 | no | 91 / 93 (84 / 86) | 54 (49) | 4.1.0 (dplyr) |
| HLMdiag | 0.5.1 (2025-05-12) | GPL-2 | >= 3.5.0 | ggplot2, plyr, reshape2, MASS, Matrix, mgcv, dplyr, magrittr, stringr, purrr, tibble, tidyselect, janitor, Rcpp, rlang, ggrepel, diagonals ; LinkingTo: Rcpp, RcppArmadillo | yes | 43 / 45 (38 / 40) | 27 (22) | 4.1.0 (dplyr) |
| lmerTest | 3.2-1 (2026-03-05) | GPL (>= 2) | >= 3.2.5 | numDeriv, MASS, ggplot2, reformulas | no | 29 / 31 (24 / 26) | 17 (13) | 4.1 (glue) |
| pbkrtest | 0.5.5 (2025-07-18) | GPL (>= 2) | >= 4.2.0 | broom, dplyr, MASS, numDeriv, Matrix, doBy | no | 55 / 58 (49 / 52) | 35 (30) | 4.5 (Deriv) |
| jsonlite | 2.0.0 (2025-03-27) | MIT + file LICENSE | - | (base only) | yes | 0 / 0 (0 / 0) | 0 (0) | - |
| whisker | 0.4.1 (2022-12-05) | GPL-3 | - | (base only) | no | 0 / 0 (0 / 0) | 0 (0) | - |
| quarto | 1.5.1 (2025-09-04) | MIT + file LICENSE | >= 4.1.0 | cli, fs, htmltools, jsonlite, later, lifecycle, processx, rlang, rmarkdown, rstudioapi, xfun, yaml | no | 30 / 30 (30 / 30) | 18 (18) | 4.1.0 (quarto) |

Source: DESCRIPTION files from https://raw.githubusercontent.com/cran/<pkg>/master/DESCRIPTION fetched 2026-11-07; recursion over Depends+Imports (runtime) and +LinkingTo (source build); base packages excluded; 'recommended' = the 15 packages shipped with R.
