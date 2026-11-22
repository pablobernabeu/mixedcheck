# lme4: the check.scaleX setting

**Source as checked.** The function `checkScaleX()` in `R/utilities.R` of lme4, which `lmerControl(check.scaleX = ...)` controls. Read in two versions on 21 November 2026: the CRAN release 2.1-0 (published 23 October 2026), through the GitHub mirror cran/lme4, and the development version 2.1-1, through the lme4/lme4 repository on GitHub. Version 2.1-1 is not on CRAN; CRAN's current release is 2.1-0, which is also the version in the H0 library.

**Match.** The function is identical in the two versions, apart from its line position. The registry cites 'lme4 2.1-1', a development version; the CRAN release 2.1-0 behaves the same.

## Claims checked

1. spec/registry/checks/design.scale_disparity.yaml (summary and thresholds ratio, high and low): lme4 warns, with the default settings of lmerControl(), when the standard deviations of the fixed-effects columns that are not all 0 or 1 differ by a factor above 1000, or when one of them lies above 1000 or below 0.001.
   **Confirmed.** `checkScaleX(X, kind = "warning", tol = 1e3)` keeps the columns of the fixed-effects matrix whose values are not all 0 or 1, so the intercept and indicator columns are left out; it computes their standard deviations and warns when the absolute log of any pairwise ratio of those standard deviations, or of any standard deviation itself, exceeds log(1000). That is a ratio above 1000 or a standard deviation above 1000 or below 0.001, as the registry states, with strict inequalities as in the registry's comparators. The default `kind` is 'warning'; 'stop' stops, and 'warn+rescale' and 'silent.rescale' rescale those columns instead. The tolerance of 1000 is the function's default and is not exposed through lmerControl(), which sets only the kind.
2. review-catalogue.md (L2-13): check.scaleX = 'warning' by default. **Confirmed.** The warning text in both versions also suggests `(g)lmerControl(autoscale = TRUE)`.

## Fields that differ from the repository's records

- The registry cites lme4 '2.1-1', which is not a released version; the behaviour it describes is that of the CRAN release 2.1-0, whose CRAN record is https://CRAN.R-project.org/package=lme4 (DOI 10.32614/CRAN.package.lme4), with the author list that CRAN gives for that version.
