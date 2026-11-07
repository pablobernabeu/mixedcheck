# Q7 Names and monorepo (checked 2026-11-07)

## A. Availability

Methods (script: scripts/name_check.py; raw TSV: out/name_availability.tsv; controls: out/name_controls.tsv):
- CRAN, current or archived: `git ls-remote https://github.com/cran/<name>`. The cran mirror keeps archived packages (controls rgdal and maptools resolve) and GitHub resolves names case-insensitively (cran/LME4 resolves), matching CRAN's rule that names must not clash "irrespective of case" with current or past packages.
- Bioconductor: `git ls-remote https://github.com/bioc/<name>` (control: limma resolves).
- PyPI: the exact PEP 503-normalised name in the full simple index (933,753 projects, downloaded 2026-11-07), plus PyPI's 'too similar' rule as implemented in Warehouse. That rule strips `.`, `_` and `-`, maps l/L/i/I to 1 and o/O to 0, and lowercases (pypi/warehouse migration d18d443f89f0, used in packaging/services.py, whose error reads "The name ... is too similar to an existing project"). Control: `lmm` is flagged as too similar to the existing `imm`.
- conda-forge: package names in channeldata.json (34,956 names) and the feedstock repositories `<name>-feedstock` and `r-<name>-feedstock`.
- Not checkable here: R-universe (r-universe.dev is blocked) and PyPI's admin 'prohibited names' list. Web searches for the main candidates found no package with these names.

| Name | CRAN (current or archived) | Bioc | PyPI exact | PyPI 'too similar' | conda-forge | Notes |
|---|---|---|---|---|---|---|
| lmecheck | free | free | free | free | free | Same as the repo name. 'lme' evokes `nlme::lme` and suggests linear models only. Searches return unrelated 'lmcheck' and 'lacheck' |
| lmmcheck | free | free | free | free | free | LMM is the standard acronym, but the name excludes GLMMs. Close to CRAN `lmm` (Schafer) |
| mixedcheck | free | free | free | free | free | Covers LMMs and GLMMs and avoids the 'mix' (mixture or MCMC) connotation. Searches drift to audio tools 'MixChecker' and 'Mix Check Studio' |
| mmcheck | free | free | **taken** | - | free | Unavailable on PyPI |
| lmmdiag | free | free | free | free | free | 'diag' collides with lme4 2.x `diag()` covariance terms |
| mixeddiag | free | free | free | free | free | Same `diag()` ambiguity |
| lmmaudit | free | free | free | free | free | 'audit' fits Stream B better than Stream A. Linear only |
| mixedaudit | free | free | free | free | free | Broad, but 'audit' undersells diagnostics and reporting |
| glmmcheck | free | free | free | free | free | Could be mistaken for a companion to the unrelated CRAN `glmm` or the PyPI `glmm` engine |
| mlmcheck | free | free | free | free | free | `mlm` is R's class for multivariate linear models |
| mixdiag / mixDiagnostics | free | free | free | free | free | Suggest mixture models or MCMC mixing (earlier finding) |
| others checked: glmmaudit, lmeaudit, lmediag, mixedlint, lmmlint, mixedspec, lmmspec, remcheck, ranefcheck, mmaudit, mixedreport, lmmreport, mixedmodelcheck, mixedmodels, mixeddx, lmmdx, multilevelcheck, merdiag | all free | all free | all free | all free | all free | |

## B. Naming guidance (primary sources)
- CRAN Repository Policy (CRAN_policies.texi, revision 6985, eddelbuettel/crp mirror): names must not conflict, irrespective of case, with any current or past CRAN package or any current Bioconductor package. "Package names on CRAN are persistent and in general it is not permitted to change a package's name."
- Writing R Extensions: only ASCII letters, numbers and dot, at least two characters, starting with a letter and not ending in a dot.
- rOpenSci Dev Guide (ropensci/dev_guide pkg_building.Rmd, commit of 2026-09-28): "short, descriptive names in lower case". Check names with `pak::pkg_name_check()` and a search engine, never reuse a CRAN or Bioconductor name, and weigh uniqueness against discoverability.
- PEP 8: packages should have "short, all-lowercase names, although the use of underscores is discouraged".
- PyPA 'Names and normalization' (PEP 503/508): the regex `^([A-Z0-9]|[A-Z0-9][A-Z0-9._-]*[A-Z0-9])\Z`; lowercase, with runs of `.`, `-` and `_` collapsed to `-`.

## C. Dual-language precedents
Same name in both registries, separate repositories: marginaleffects (vincentarelbundock/marginaleffects and pymarginaleffects), pins (rstudio/pins-r and pins-python), vetiver (rstudio/vetiver-r and vetiver-python), pointblank (rstudio/pointblank and posit-dev/pointblank), duckdb (duckdb/duckdb-r, which vendors the C++ core by automated commits, and duckdb/duckdb-python). Each name is on both CRAN (cran mirror) and PyPI (JSON API 200).

Monorepos that publish to CRAN and PyPI from subdirectories:
- apache/arrow: `r/` (DESCRIPTION Depends R (>= 4.2)) and `python/` (pyarrow, requires-python >= 3.11). `r/Makefile` target `sync-cpp` rsyncs `../cpp`, NOTICE and LICENSE into `r/tools/` before `R CMD build`, and `r/bootstrap.R` exists for R-universe. The R-universe registry for the apache universe lists arrow with `subdir = r`.
- dmlc/xgboost: `R-package/` and `python-package/` (requires-python >= 3.12). `R-package/bootstrap.R` ("Script used to bootstrap R-universe build") copies sources from `..` into `src/`. The dmlc.r-universe.dev `packages.json` has `"subdir": "R-package"`.
- LightGBM (README links now point to lightgbm-org/LightGBM): `R-package/` and `python-package/` (requires-python >= 3.11). `build-cran-package.sh` assembles a temporary `lightgbm_r/` from `R-package/*`, `include/`, `src/` and `external_libs/`, then runs `R CMD build`. The R README documents CRAN or `build_r.R` installs, not `install_github`.

What these show: CRAN and PyPI do not care about repository layout, because each receives a built tarball, sdist or wheel. The extra work in these monorepos comes from compiled code shared across the tree. A pure R and pure Python project avoids it if the shared registry and fixtures are committed as vendored copies inside `r/inst/` and `python/src/<pkg>/`, rather than copied at build time.

Tooling support for subdirectories (primary sources):
- R-universe docs (r-universe-org/docs publish/set-up.qmd): "If the R package does not live in the root of the Git repository, you also need to set the `subdir` field". troubleshoot-build.qmd says a `bootstrap.R` or `.prepare` script at the package root "will be executed before R CMD build".
- remotes::install_github: `username/repo[/subdir][@ref|#pull|@*release]` or `subdir =` (r-lib/remotes R/install-github.R). pak/pkgdepends parses GitHub refs with a `/subdir` component (R/parse-remotes.R, `github_subdir_rx`).
- pip: `pip install "pkg @ vcs+protocol://repo_url/#subdirectory=pkg_dir"` (pypa/pip docs/html/topics/vcs-support.md).
- PyPI upload from CI: pypa/gh-action-pypi-publish supports Trusted Publishing (`id-token: write`) and a `packages-dir:` input for a non-default dist directory.
- JOSS (openjournals/joss docs/submitting.md, fetched 2026-11-07): the paper must be "hosted in a Git-based repository together with your software". The repository must have been public for more than six months, with iterative development, evidence of research use and, for single-author projects, several open-practice signals (tagged releases or changelog, tests and CI, documentation, CONTRIBUTING, governance). Generative-AI use must be disclosed.
