# Q10 Minimum R and Python versions: facts gathered 2026-11-07

## R
| Fact | Value | Source |
|---|---|---|
| R release dates (tag commits in wch/r-source) | 4.1.0 2021-05-18; 4.2.0 2022-04-22; 4.3.0 2023-04-21; 4.4.0 2024-04-24; 4.5.0 2025-04-11; 4.6.0 2026-04-24; 4.6.2 2026-10-29 (current release; oldrel is 4.5.x) | git refs `tags/R-x-y-z` in github.com/wch/r-source |
| tidyverse/r-lib policy | "support the current version, the devel version, and four previous versions of R". The table gives R 4.6 (2026 Spring), minimum 4.2. The next step (R 4.7, Spring 2027, minimum 4.3) is my extrapolation from the stated rule | tidyverse/tidyverse.org content/blog/2019/r-version-support/index.md (edited 2024-07-03) |
| CRAN check flavours | release, devel, oldrel only. Writing R Extensions advises against R dependencies with a non-zero patch level | CRAN policy; R-exts.texi |
| R 4.2.0 (Windows) | "R uses UTF-8 as the native encoding on recent Windows systems ... R uses UCRT as the C runtime" | doc/NEWS.Rd, Changes in R 4.2.0, Windows |
| lme4 2.1-0 (2026-10-23) | Depends R (>= 3.6), LinkingTo Matrix (>= 1.5-0). Matrix 1.7-0 and later Depend R (>= 4.4), while Matrix 1.6-5 (2024-01-11) and earlier need R (>= 3.5.0). On R < 4.4 the bundled Matrix must therefore already be >= 1.5-0 (Ubuntu 24.04: R 4.3.3 with Matrix 1.6-5 qualifies; Ubuntu 22.04: R 4.1.2 with Matrix 1.4-0 does not). Otherwise an archived Matrix must be installed by hand | cran/lme4 and cran/Matrix DESCRIPTION files at tags; Ubuntu Packages indices |
| glmmTMB 1.1.15.2 (2026-09-29) | Depends R (>= 3.6.0), but Imports pbkrtest (Depends R (>= 4.2.0)), which imports doBy 4.7.2 (R (>= 4.2.0)), which imports Deriv 4.3.6 (Depends R (>= 4.5) since Deriv 4.3.5 of 2026-09-03). A source install of the current CRAN closure therefore needs R >= 4.5 unless older versions are pinned | cran mirror DESCRIPTION files |
| Other floors | performance R (>= 4.0); insight R (>= 3.6); DHARMa R (>= 3.5.0) but stringr and dplyr in its closure need R >= 4.1.0; HLMdiag R (>= 3.5.0); lmerTest R (>= 3.2.5); quarto R (>= 4.1.0); ggplot2 closure R >= 4.1 | q6_package_table.md |
| Precedent | apache/arrow r/DESCRIPTION: Depends R (>= 4.2) | git show HEAD:r/DESCRIPTION |
| Ubuntu LTS system R | 22.04 jammy: r-base-core 4.1.2, r-cran-matrix 1.4-0, r-cran-lme4 1.1-28, r-cran-glmmtmb 1.1.2.3. 24.04 noble: 4.3.3, 1.6-5, 1.1-35.1, 1.1.8 | archive.ubuntu.com dists/{jammy,noble}/universe/binary-amd64/Packages.gz |
| Oxford ARC | Not checkable here. A search snippet of the ARC software guide mentions `module load R/4.1.2-foss-2021b-ARC` as the latest at the time it was written | to verify with `module spider R` on ARC |

## Python
| Fact | Value | Source |
|---|---|---|
| CPython lifecycles | 3.10 reached end of life on 2026-10-01 (3.10.22 was the final release). 3.11 has security fixes until about October 2027, 3.12 until about October 2028, 3.13 until about October 2029 and 3.14 until about October 2030. 3.15.0 was released 2026-10-09 | PEP 619, 664, 693, 719, 745, 790 (python/peps main) |
| SPEC 0 rule | Drop Python versions 3 years after release and core packages 2 years after release. Schedule (updated 2026-10-12): 2026 Q4 drop Python 3.12 and numpy 2.2.0. 2027 Q1 drop scipy 1.15.0. 2027 Q2 drop numpy 2.3.0, pandas 2.3.0 and scipy 1.16.0. 2027 Q4 drop Python 3.13 and numpy 2.4.0. Endorsed by ipython, matplotlib, networkx, numpy, scikit-image, scipy, xarray and zarr, but not by pandas or statsmodels | scientific-python/specs spec-0000/{index.md,schedule.md,chart.md} |
| Current requires_python | statsmodels 0.15.0 (2026-08-27) >=3.10. numpy 2.5.4 (2026-10-10) >=3.12. pandas 3.1.1 (2026-11-04) >=3.11. scipy 1.18.1 (2026-08-21) >=3.12. matplotlib 3.11.2 >=3.11. formulaic 1.2.2 >=3.9. patsy 1.0.3 >=3.6 | pypi.org/pypi/<name>/json |
| Newest release installable per Python | Python 3.10: numpy 2.2.6, scipy 1.15.3, pandas 2.3.3, statsmodels 0.15.0. Python 3.11: numpy 2.4.6, scipy 1.17.1, pandas 3.1.1, statsmodels 0.15.0. Python 3.12+: numpy 2.5.4, scipy 1.18.1, pandas 3.1.1 | computed from release-file requires_python (scripts/last_supporting.py) |
| Release floors | numpy 2.3.0 and 2.4.0 need >=3.11, 2.5.0 needs >=3.12. scipy 1.16 and 1.17 need >=3.11, 1.18 needs >=3.12. pandas 3.0.0 needs >=3.11 | PyPI JSON |
| pandas 3.0 behaviour change | "a dedicated string data type is enabled by default ... The missing value sentinel is always NaN", plus Copy-on-Write | pandas-dev/pandas doc/source/whatsnew/v3.0.0.rst |
| Precedents | pyarrow >=3.11; lightgbm >=3.11; xgboost >=3.12 | pyproject.toml at HEAD |
| Ubuntu LTS system Python | 22.04: python3 3.10.4, numpy 1.21.5, statsmodels 0.13.2. 24.04: python3 3.12.3, numpy 1.26.4, statsmodels 0.14.1 | archive.ubuntu.com Packages indices |
