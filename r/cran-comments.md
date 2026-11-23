## Submission

This is a new submission, the first release of mixedcheck. A Python package
of the same name, released on PyPI at the same time, shares its registry of
checks, its schemas and its test fixtures, which the R package installs
under inst/ and reads in its tests.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  New submission
  Possibly misspelled words in DESCRIPTION: schemas (10:5)

'schemas' is the plural of 'schema' and is spelled as intended.

## Test environments

GitHub Actions, for commit 1a7b03c on the release branch. In the package
directory, only this file, which `.Rbuildignore` keeps out of the tarball,
has changed since.

The cran-tarball workflow (run 45114883852) built the tarball and ran
`R CMD check --as-cran` on it with CRAN's remote incoming checks and with
NOT_CRAN unset, as on CRAN:

* ubuntu-24.04 (Ubuntu 24.04.5 LTS), R 4.6.2: 1 NOTE, the one above

The R-CMD-check workflow (run 45114880264) ran `R CMD check --as-cran
--no-manual` in each of these configurations, without the remote incoming
checks:

* ubuntu-latest (Ubuntu 26.04.1 LTS), R 4.6.2: OK
* ubuntu-latest, R-devel (2026-11-21 r90959): OK
* ubuntu-latest, R 4.5.3: OK
* ubuntu-latest, R 4.6.2 with LC_ALL=C: OK
* ubuntu-latest, R 4.6.2 without the packages in Suggests: OK
* ubuntu-latest, R 4.6.2 with lme4 1.1-35.1: OK
* ubuntu-latest, R 4.2.3 with Matrix 1.4-1, the oldest versions that
  DESCRIPTION accepts: 1 NOTE, that the suggested packages lme4, lpSolve and
  openssl, which this configuration leaves out, are not available
* windows-latest (Windows Server 2022 x64, build 26100), R 4.6.2: OK
* macos-latest (macOS Tahoe 26.7.2), R 4.6.2: OK

## Tests

On CRAN, the tests run the first case of each file of the audit corpus and
every fifth case after it, which reaches every file, while CI runs every
case. Under CRAN's settings they took 90 s on the Ubuntu runner above. The
tests that compare the package with lme4 skip when lme4 is absent, and the
examples and tests write files only to tempdir().
