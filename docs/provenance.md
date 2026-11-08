# Provenance log

This log records where the code of mixedcheck comes from. It is required by the clean-room rule in 02-decisions.md (Q10) and by the mitigation of the risk of AI-assisted code in 03-execution-plan.md, and it supplies the disclosure of AI assistance that JOSS asks of its authors.

## Clean-room rule

Code is never copied or translated from GPL or AGPL packages, such as lme4, glmmTMB, performance, insight, DHARMa and reformulas. These packages may be called as Q6 in 02-decisions.md describes. lme4 and glmmTMB are engines in Suggests whose fits the package diagnoses. performance, insight and DHARMa are called in opt-in cross-checks, and reformulas serves only as a test oracle. Algorithms are implemented from papers, standards and documentation, and any third-party source code read while writing an implementation is recorded in its entry. Third-party data enter shipped fixtures only under CC0 or CC BY, with attribution.

The rule applies equally to code written with AI assistance, and each entry records that assistance.

## Format

Each entry has a heading with the date and the component, followed by these fields:

- Files: the files or directories the entry covers.
- Algorithm: the method implemented, or 'None' when the code implements no algorithm.
- Sources: the papers, standards or documentation the implementation follows, with full references.
- Code consulted: any third-party source code read while writing it, with its licence, or 'None'.
- AI assistance: the tool used and the part it played, or 'None'.
- Verification: how the implementation was checked, such as the tests or reference values.

An algorithm that is later reimplemented or corrected gets a new entry, and earlier entries are not edited.

## Entries

### 2026-11-08: repository skeleton (M0)

- Files: r/, python/, spec/ (including spec/tools/vendor.py), .github/ and the root configuration files.
- Algorithm: None. The skeleton reads the vendored versions.json and compares files with their SHA-256 digests, using hashlib in Python and cli in R.
- Sources: R Core Team, 'Writing R Extensions' and 'R Internals', R 4.3.3, https://cran.r-project.org/manuals.html. Python Software Foundation, 'The Python Standard Library' (hashlib, importlib.resources and json), Python 3.11, https://docs.python.org/3.11/library/. PEP 621, 'Storing project metadata in pyproject.toml', https://peps.python.org/pep-0621/. PEP 639, 'Improving License Clarity with Better Package Metadata', https://peps.python.org/pep-0639/. PEP 735, 'Dependency Groups in pyproject.toml', https://peps.python.org/pep-0735/.
- Code consulted: the R CMD build and R CMD check code in R's tools package (R 4.3.3, GPL-2 | GPL-3), read to find the environment variables that the R workflow sets and the file names that R CMD build leaves out or R CMD check rejects. No code was copied, and no other code outside the maintainer's own repositories was read.
- AI assistance: written with Claude Code (Anthropic) under the maintainer's direction.
- Verification: the R package passes R CMD check with --as-cran, the Python package's tests pass under the lowest direct and the latest resolutions of its dependencies, and the tests of the vendoring script cover each kind of mismatch.
