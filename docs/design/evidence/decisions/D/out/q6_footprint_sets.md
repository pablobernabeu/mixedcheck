| Candidate Imports set (roots) | Hard deps incl. roots: runtime / +LinkingTo | of which non-recommended | Compiled (non-recommended) | System requirements in closure | Licences in closure |
|---|---|---|---|---|---|
| S0 audit core: Matrix+jsonlite | 3 / 3 | 1 / 1 | 3 (1) | - | GPL (>= 2) \| file LICENCE: 1; MIT + file LICENSE: 1; GPL (>= 2): 1 |
| S0b audit core: jsonlite only | 1 / 1 | 1 / 1 | 1 (1) | - | MIT + file LICENSE: 1 |
| S1 S0+whisker | 4 / 4 | 2 / 2 | 3 (1) | - | GPL (>= 2) \| file LICENCE: 1; MIT + file LICENSE: 1; GPL (>= 2): 1; GPL-3: 1 |
| S2 S0+lme4 | 13 / 14 | 8 / 9 | 11 (7) | minqa, nloptr | GPL (>= 2): 5; GPL-2: 2; GPL-2 \| GPL-3: 1; GPL (>= 2) \| file LICENCE: 1; GPL (>= 2) \| file LICENSE: 1 |
| S3 S2+insight | 14 / 15 | 9 / 10 | 11 (7) | minqa, nloptr | GPL (>= 2): 5; GPL-3: 2; GPL-2: 2; GPL-2 \| GPL-3: 1; GPL (>= 2) \| file LICENCE: 1 |
| S4 S2+performance | 17 / 18 | 12 / 13 | 11 (7) | minqa, nloptr | GPL (>= 2): 5; GPL-3: 4; GPL-2: 2; MIT + file LICENSE: 2; GPL-2 \| GPL-3: 1 |
| S5 S2+DHARMa | 92 / 94 | 85 / 87 | 54 (49) | curl, fs, httpuv, knitr, minqa, nloptr, openssl, rmarkdown, sass, stringi | MIT + file LICENSE: 53; GPL (>= 2): 12; GPL-2 \| GPL-3: 5; GPL: 4; GPL-2: 3 |
| S6 S2+glmmTMB | 62 / 65 | 55 / 58 | 40 (34) | glmmTMB, minqa, nloptr, stringi | MIT + file LICENSE: 27; GPL (>= 2): 13; GPL-2 \| GPL-3: 6; GPL-2: 5; GPL-3: 3 |
| S7 S2+lmerTest+pbkrtest | 58 / 61 | 52 / 55 | 36 (31) | minqa, nloptr, stringi | MIT + file LICENSE: 27; GPL (>= 2): 12; GPL-2 \| GPL-3: 5; GPL-2: 4; GPL-3: 3 |
| S8 S0+quarto | 33 / 33 | 31 / 31 | 20 (18) | fs, knitr, quarto, rmarkdown, sass | MIT + file LICENSE: 23; GPL (>= 2): 4; GPL: 3; BSD_3_clause + file LICENSE: 1; GPL (>= 2) \| file LICENCE: 1 |
| S9 S0+ggplot2 | 19 / 20 | 17 / 18 | 10 (8) | - | MIT + file LICENSE: 16; GPL (>= 2) \| file LICENCE: 1; MIT + file LICENSE \| Unlimited: 1; Apache License 2.0: 1; GPL (>= 2): 1 |
| S10 everything (S2+perf+DHARMa+glmmTMB+lmerTest+pbkrtest+ggplot2) | 115 / 118 | 107 / 110 | 65 (59) | curl, fs, glmmTMB, httpuv, knitr, minqa, nloptr, openssl, rmarkdown, sass, stringi | MIT + file LICENSE: 55; GPL (>= 2): 20; GPL-2 \| GPL-3: 8; GPL-3: 7; GPL-2: 6 |

Counts include the root packages themselves and recommended packages (Matrix, lattice, MASS, boot, nlme, mgcv, nnet, codetools), which ship with standard R installations. Base packages excluded. Source: cached DESCRIPTION files from the cran GitHub mirror (2026-11-07); script scripts/footprint.py.
