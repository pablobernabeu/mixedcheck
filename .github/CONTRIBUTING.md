# Contributing to mixedcheck

Thank you for considering a contribution. Issues and pull requests are both
welcome. Decisions about the project are taken as described in
[GOVERNANCE.md](GOVERNANCE.md).

## How the repository is organised

mixedcheck is a pair of packages, one for R and one for Python, developed in one
repository with the design that governs them.

| Directory | Contents |
|---|---|
| `r/` | the R package |
| `python/` | the Python package, with a src layout |
| `spec/` | the shared specification and the vendoring script in `spec/tools/` |
| `fixtures/` | the shared test fixtures |
| `parity/` | the cross-language harness |
| `sim/` | the disclosure-attack tests of the privacy filter and the validation studies to run on the HPC, never shipped |
| `paper/` | the JOSS paper |
| `docs/` | the design documents in `docs/design/`, the specifications in `docs/spec/` and the provenance log |

The decision record (`docs/design/02-decisions.md`) settles what the packages
do, and the execution plan (`docs/design/03-execution-plan.md`) sets the order
in which they are built. Each component is built in R first. Rscript then writes
JSON fixtures, and the Python port is developed against those fixtures, so a
change to behaviour usually needs a change in both packages.

## Shared artefacts and vendoring

Files that both packages read, such as `spec/versions.json`, are edited only in
`spec/` or `fixtures/` and listed in `spec/vendoring.json`. The vendoring script
copies them byte for byte into the packages, with a manifest of SHA-256
digests: `spec/` into `r/inst/spec/` and `python/src/mixedcheck/_spec/`, the
conformance corpora into `r/tests/conformance/` and `python/tests/conformance/`,
and other fixtures into `r/inst/fixtures/` and `python/src/mixedcheck/_fixtures/`. After editing a source, run from the repository
root:

```bash
python3 spec/tools/vendor.py sync    # write the copies and the manifests
python3 spec/tools/vendor.py check   # report any copy that does not match its source
```

The registry of checks is written in YAML, one file per check in
`spec/registry/checks/`, and compiled into `spec/compiled/registry.json`, the
only form that the packages read. After editing a source, compile the registry
before running the vendoring script. The compiler needs PyYAML built with
libyaml, which the wheels on PyPI include:

```bash
python3 spec/tools/compile_registry.py           # write spec/compiled/registry.json
python3 spec/tools/compile_registry.py --check   # report whether it matches its sources
```

A change to the registry changes its hash, which the documents of the results
corpus record, and with them the results file hashes that their sidecars
record. `python3 spec/tools/rehash_results.py` replaces both wherever the corpus
records them and runs the vendoring script, and `--check` reports whether the
corpus is up to date.

The files in `spec/` must have LF line endings and no byte-order mark, and
`check` fails on any carriage return or byte-order mark there. It also rejects
an artefact whose name R CMD build would leave out of the R package or R CMD
check would reject. Fixtures may hold CRLF and byte-order-mark cases on
purpose, and `.gitattributes` stops Git from converting either.

## Clean-room rule and provenance

Code is never copied or translated from GPL or AGPL packages, such as lme4,
glmmTMB, performance, insight or DHARMa. Algorithms are implemented from papers,
standards and documentation. Every algorithm gets an entry in
[docs/provenance.md](../docs/provenance.md) that records its sources, any
third-party code read while writing it and any AI assistance, in the format that
file describes.

## Running the checks

The R package needs R 4.2.0 or later. roxygen2 writes `NAMESPACE` and `man/`,
and DESCRIPTION records the version used. The check runs on the built tarball:

```bash
Rscript -e 'roxygen2::roxygenise("r")'
R CMD build r
_R_CHECK_CRAN_INCOMING_REMOTE_=false _R_CHECK_CRAN_INCOMING_SKIP_LARGE_VERSION_=true \
  R CMD check --as-cran --no-manual mixedcheck_*.tar.gz
```

The quick CI job sets the same two variables. They stop CRAN's incoming checks
from reporting a new submission, the repository's URLs while it is private and
the large component of the development version number. Without access to a time
server, also set `_R_CHECK_SYSTEM_CLOCK_=false`.

The Python package needs Python 3.11 or later. Install it with its test and
typing groups, the second of which holds mypy and the stubs of pandas and scipy,
then run the tests and ruff from the repository root, and mypy, which reads its
settings from python/pyproject.toml, from python/:

```bash
python -m pip install ./python --group python/pyproject.toml:test --group python/pyproject.toml:typing
python -m pytest python
ruff check python spec/tools parity fixtures/conformance/tools .github/scripts
(cd python && mypy)
```

The `--group` option needs pip 25.1 or later. With uv, `uv pip install ./python
--group python/pyproject.toml:test` does the same, and `--resolution
lowest-direct` installs the lowest versions that the package declares.

The tests of the scripts in spec/tools/ use the standard library, PyYAML for
the registry compiler and, where it is installed, jsonschema as an oracle. The
tests that need PyYAML are skipped without it:

```bash
python3 -m unittest discover -s spec/tools -v
```

The parity harness runs both packages over every case of the conformance
corpora and reports every case in which they differ from each other or from
the expected outcome. It needs the R package installed with yaml and the
Python package installed with its extra 'yaml', as
[parity/README.md](../parity/README.md) describes:

```bash
python3 parity/parity.py --python /path/to/venv/bin/python --r-lib /path/to/rlib
```

The disclosure-attack tests attack the shareable documents of the R package
and fail when one gives back a value that the privacy filter undertakes to
hide. They need the R package installed with lpSolve, as
[sim/disclosure/README.md](../sim/disclosure/README.md) describes:

```bash
Rscript sim/disclosure/run.R --cores 4
```

Continuous integration runs these checks on every push to main and every pull
request that touches the files concerned. The full matrix of R and Python versions and
platforms runs when started by hand from the Actions tab and, once the
repository is public, every night. The references in docs/ that carry a DOI
are checked against their Crossref records by `.github/scripts/check_references.py`
in the workflow references.yaml, which runs when started by hand or when the
label 'references' is added to a pull request, since the cloud sessions cannot
reach Crossref. Its tests need no network:

```bash
python3 -m unittest discover -s .github/scripts -v
```

## Changelogs

`CHANGELOG.md` at the root records changes to the design and the shared
specification, `r/NEWS.md` changes to the R package and `python/CHANGELOG.md`
changes to the Python package. Add an entry to each one that a change affects.

## Licence and conduct

By contributing, you agree that your contribution is licensed under the MIT
licence of the project, and that you will follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
