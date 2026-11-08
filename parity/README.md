# Parity

This directory holds the cross-language harness, which compares the outputs of the R and Python packages (02-decisions.md, Q7). It runs both packages over every case of the conformance corpora in [fixtures/conformance/](../fixtures/README.md) and compares each outcome with the outcome of the other language and with the expected outcome that the case states. It compares outputs by the rules of [docs/spec/conventions.md](../docs/spec/conventions.md) (Comparison across languages): error codes, issues with their messages and locations, canonical bytes, hashes and every count, category, name and label exactly, and real statistics and the messages that render them within the tolerance stated there. Every output of M1 is compared exactly, since M1 computes no real statistics.

| File | Contents |
|---|---|
| `parity.py` | the driver: it writes the plan of a run, runs both packages, compares their outcomes, prints every mismatch and a summary and sets the exit status. It needs only the standard library of Python 3.11 or later. |
| `run_r.R` | runs the cases with the installed R package and writes its outcomes |
| `run_python.py` | runs the cases with the installed Python package and writes its outcomes |
| `corpora.json` | every corpus file of fixtures/conformance/ with the kind of its cases. A file marked `pending` is counted but not run until the milestone it names implements what it tests. |

## Running the harness

Install both packages, the R package with the suggested package yaml and the Python package with its extra 'yaml', then run the harness from the repository root:

```bash
mkdir -p /tmp/parity/rlib
R CMD INSTALL --library=/tmp/parity/rlib r
python3 -m venv /tmp/parity/venv
/tmp/parity/venv/bin/pip install './python[yaml]'
python3 parity/parity.py --python /tmp/parity/venv/bin/python --r-lib /tmp/parity/rlib
```

`--python` names the interpreter that runs the Python package, by default the one that runs parity.py, and `--r-lib` a library that R searches before its own. `--rscript` names another Rscript. R runs once with LC_ALL set to each locale given with `--r-locale`, by default C.UTF-8 and C, so that the cases whose output a locale could change are run in both (fixtures/conformance/unicode/README.md). The harness stops if R does not get the locale it asked for. `--keep DIR` keeps the plan and the outputs of the runs in DIR, and `--compare-only` with `--keep` compares the outputs already there without running the packages again. A run takes about 15 seconds.

The exit status is 0 when every case gives its expected outcome in every run and the runs agree, 1 when a case does not and 2 when the harness cannot run, for example when a corpus file is missing from corpora.json or a package cannot be loaded.

The workflow [parity.yaml](../.github/workflows/parity.yaml) runs the harness on every push to main and every pull request that touches either package, spec/, fixtures/ or this directory, with R release and Python 3.11.

## What is compared

Each case gives one outcome for each of its parts: each mode of a reader or writer case (plain, data and hashable), the hash in memory and of a file for the cases of hash/sha256.json, and one outcome for every other case. An outcome is the canonical bytes with their hash, and for some reader cases the bits of the double read, or the list of issues reported, or another value such as a decimal string, an NFC form, an order, a digest, a key identifier or a commitment. Any issue raised as a warning is part of the outcome, and an error that is not one of the package's own errors is recorded with its message, so that a crash appears as a mismatch rather than stopping the run.

A case with `languages` runs only in the languages it lists, and its outcomes are compared with the expected outcome alone. A run that reports a code which spec/errors.json reserves for the other language is a mismatch (docs/spec/errors.md).

The harness also reads, through each package, every JSON file of spec/ that spec/vendoring.json vendors, in the data profile, and compares the canonical bytes and hashes across the languages. The registry that `read_registry()` returns must give the bytes of spec/compiled/registry.json, and `spec_versions()` the content of spec/versions.json.

## Reports

Every mismatch is printed with the case, the part, the expected outcome and the outcome of each run, runs with the same outcome together. Strings are shown with characters that a terminal may not show escaped, and where canonical bytes differ, the first differing byte is shown in context. A summary follows, with the number of cases in each corpus file, the number run in each run and in both languages and the result. The outputs are JSON Lines: a header that names the run, the package, the interpreter, the version of the YAML package and, for R, the locale, then one record for each part of each case with every string written as the hexadecimal digits of its bytes, so that the two runners write identical records for identical outcomes.

## Adding a corpus

A new corpus file must be listed in corpora.json, or the harness stops. A file of an existing kind needs nothing else. A new kind needs a function in run_r.R and in run_python.py that computes the outcome of each part, and the expected outcomes in `expected_parts()` of parity.py, written from the README of the corpus. The table and formula corpora are pending until M2 implements the table reader and the formula parser.

## Result

At the end of M1, on R 4.3.3 and Python 3.13 under Linux, the harness ran 1,183 cases: 1,169 in both languages and 14 that only one language can hold, with 2,586 outcomes compared, and read the vendored files of spec/, with 14 outcomes. Every case gave its expected outcome in Python and in R under C.UTF-8 and C, and the runs agreed. The 403 cases of the table and formula corpora wait for M2.
