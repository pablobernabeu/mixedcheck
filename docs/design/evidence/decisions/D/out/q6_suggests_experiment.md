# Q6 experiment: engines in Suggests vs Imports (R 4.3.3, lme4 1.1-35.1, glmmTMB 1.1.8, lmerTest 3.1-3, afex 1.3-1)

Packages: /tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/D/exp_suggests/A (lme4, lmerTest, glmmTMB, afex in Suggests)
and .../exp_suggests/B (identical code, lme4 in Imports with importFrom(lme4, getME, isSingular)).

Design: a package-owned S3 generic `diagnose()` with methods registered in NAMESPACE as
`S3method(diagnose, merMod)`, `S3method(diagnose, glmmTMB)`, `S3method(diagnose, mixed)`;
engine calls written as `lme4::getME()` inside `requireNamespace()` guards; an engine-free
`audit()` that needs only Matrix (recommended package).

| Check | Result |
|---|---|
| `R CMD check` (A, all Suggests installed) | exit 0. Status 2 WARNINGs, 1 NOTE, all unrelated to Suggests: a container locale warning (en_US.UTF-8 missing), missing Rd files (no docs in the demo), and "Namespaces in Imports field not imported from: jsonlite, stats" (demo artefact). No undeclared-dependency or S3-consistency problems. |
| `_R_CHECK_DEPENDS_ONLY_=true R CMD check` (A) | exit 0, same three demo-only issues. Tests printed "lme4 not available: Stream A tests skipped" and "glmmTMB not available: tests skipped". |
| S3 dispatch on S4 fits without importing lme4 | `lmerMod`, `glmerMod` and `lmerModLmerTest` (lmerTest) all dispatched to `diagnose.merMod`; afex `mixed` objects to `diagnose.mixed`, which forwards `$full_model`; glmmTMB to `diagnose.glmmTMB`. |
| lme4 loaded by `library()` of the package? | A: no (`"lme4" %in% loadedNamespaces()` was FALSE after the audit ran). |
| Namespaces attached by `library(pkg)` in a fresh `Rscript --vanilla`, 5 runs each | A: 4 (Matrix, grid, lattice, pkg). B: 12 (adds lme4, MASS, Rcpp, boot, minqa, nlme, nloptr, splines). |
| Elapsed `library()` time, median of 5 | A 0.475 s, B 0.644 s (the difference is small. The main costs of Imports are at install time and in exposure to breakage in the dependency closure, not at load time). |

Raw outputs: exp_suggests/check_A.log, exp_suggests/check_A_depends_only.log, exp_suggests/auditdemoA.Rcheck/, exp_suggests/depsonly/auditdemoA.Rcheck/tests/dispatch.Rout, exp_suggests/load_cost.tsv.

I did not measure compile time for lme4 and glmmTMB from source, because the background compile job was not permitted in this session. That measurement is listed as an item for the local or ARC session.
