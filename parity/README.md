# Parity

This directory holds the cross-language harness, which compares the outputs of the R and Python packages (02-decisions.md, Q7). It runs both packages over every case of the conformance corpora in [fixtures/conformance/](../fixtures/README.md) and compares each outcome with the outcome of the other language and with the expected outcome that the case states. It compares outputs by the rules of [docs/spec/conventions.md](../docs/spec/conventions.md) (Comparison across languages): error codes, issues with their messages and locations, canonical bytes, hashes and every count, category, name and label exactly, and real statistics and the messages that render them within the tolerance stated there. Every output of M1 and M2a is compared exactly, except the response, trials, offset and weight vectors of the design matrices, which ir.md compares within a tolerance because they can hold logarithms.

| File | Contents |
|---|---|
| `parity.py` | the driver: it writes the plan of a run, runs both packages, compares their outcomes, prints every mismatch and a summary and sets the exit status. It needs only the standard library of Python 3.11 or later. |
| `run_r.R` | runs the cases with the installed R package and writes its outcomes |
| `run_python.py` | runs the cases with the installed Python package and writes its outcomes |
| `corpora.json` | every JSON corpus file of fixtures/conformance/ with the kind of its cases. A file marked `pending` is counted but not run until the milestone it names implements what it tests. `pending_parts` maps a part of the cases of a file to the milestone that implements it: the runners skip that part, and the harness counts it and runs the other parts. The shareable part of audits/privacy.json waits in this way for the privacy filter of M2b-3. |

## Running the harness

Install both packages, the R package with the suggested packages yaml and lpSolve, without which outcome.separation is not available, and the Python package with its extra 'yaml', then run the harness from the repository root:

```bash
mkdir -p /tmp/parity/rlib
R CMD INSTALL --library=/tmp/parity/rlib r
python3 -m venv /tmp/parity/venv
/tmp/parity/venv/bin/pip install './python[yaml]'
python3 parity/parity.py --python /tmp/parity/venv/bin/python --r-lib /tmp/parity/rlib
```

`--python` names the interpreter that runs the Python package, by default the one that runs parity.py, and `--r-lib` a library that R searches before its own. `--rscript` names another Rscript. R runs once with LC_ALL set to each locale given with `--r-locale`, by default C.UTF-8 and C, so that the cases whose output a locale could change are run in both (fixtures/conformance/unicode/README.md). The harness stops if R does not get the locale it asked for. `--keep DIR` keeps the plan and the outputs of the runs in DIR, and `--compare-only` with `--keep` compares the outputs already there without running the packages again. A run takes about a minute and a half, most of it in the audits that R runs in each locale.

The exit status is 0 when every case gives its expected outcome in every run and the runs agree, 1 when a case does not and 2 when the harness cannot run, for example when a corpus file is missing from corpora.json or a package cannot be loaded.

The workflow [parity.yaml](../.github/workflows/parity.yaml) runs the harness on every push to main and every pull request that touches either package, spec/, fixtures/ or this directory, with R release and Python 3.11.

## What is compared

Each case gives one outcome for each of its parts: each mode of a reader or writer case (plain, data and hashable), the hash in memory and of a file for the cases of hash/sha256.json, the parts of table, formula, audit and results cases listed below, and one outcome for every other case. An outcome is the canonical bytes with their hash, and for some reader cases the bits of the double read, or the list of issues reported, or another value such as a decimal string, an NFC form, an order, a digest, a key identifier or a commitment. Any issue raised as a warning is part of the outcome, and an error that is not one of the package's own errors is recorded with its message, so that a crash appears as a mismatch rather than stopping the run.

Table cases have a part for the table read and, with a formula, one for its samples. Formula cases have a part for the IR and, when the case gives the design matrices, one for them and one for the vectors, or, when it gives the issue that the design matrices report, one for the matrices that holds that issue. Audit cases have a part for the run in internal mode and, in privacy.json, one for the run in shareable mode. Results cases have a part for the document validated alone and, when the case gives a sidecar, one for the document validated with its sidecar, data and declaration.

- A table read is the list of columns, each with its name, its type and its values as the table corpus writes them, by the type of each value that the package returns: null for a missing value, strings and booleans as themselves, the integers of an integer column as integers and every other number as the bits of the double, with negative zero as zero, or as 'NaN', 'Infinity' or '-Infinity'. So a value of the wrong type in R or Python is a mismatch, and R's strings that are not ASCII must be marked UTF-8.
- The samples of a table case are the design and analysis samples of the IR of its formula, as row positions counted from 0, which both runners compute with `design_samples()`.
- The IR is its canonical bytes in the hashable profile with its hash. The harness computes the expected bytes from the IR of the case and stops unless they have the IR hash that the case states.
- The design matrices are the rows of the design sample, X with the names of its columns and those that the sequential rule drops, Z with the description of its columns and the number of entries it stores, which is one for each row and each column of a random term. Their values are compared bit for bit.
- The vectors are the response, trials, offset and weight vectors of the design matrices, which the corpus does not give. They are compared across the languages alone, each value within the tolerance of conventions.md, since ir.md compares them within a tolerance.
- An audit part runs `audit()` with the data frame of the case, built as for a formula case, its other inputs, the commitment key 00 01 02 … 1F and MIXEDCHECK_TIME set to 0 (fixtures/conformance/audits/README.md). Its outcome is the issues of the error that refuses the run, compared exactly, or the canonical bytes in the data profile of the document and of the sidecar. The findings of the checks of the case are compared with the expected findings by the rules of that README, and the documents and sidecars of the runs with each other by the rules of conventions.md: every member exactly apart from `created`, `software` and the package version in `versions`, which are not compared, and each finding exactly apart from its real statistics, which match within the tolerance of their check or bit for bit for those that the case lists in `exact`, and its message, which matches by its values. A finding that is near_threshold in either outcome may differ in what conventions.md allows. A mismatch lists the members that differ by their JSON Pointers. Until the privacy filter is ported to Python, the shareable part is pending.
- The outcome of a results part is 'valid' when `validate_results()` returns, with the warning W7090 for a document of another registry, or the issues of its error, compared exactly with the issues and sidecar issues of the case (fixtures/conformance/results/README.md). An error in the document stops validation before the sidecar, so that the second part then repeats the first.

A case with `languages` runs only in the languages it lists, and its outcomes are compared with the expected outcome alone. A run that reports a code which spec/errors.json reserves for the other language is a mismatch (docs/spec/errors.md).

The harness also reads, through each package, every JSON file of spec/ that spec/vendoring.json vendors, in the data profile, and compares the canonical bytes and hashes across the languages. The registry that `read_registry()` returns must give the bytes of spec/compiled/registry.json, and `spec_versions()` the content of spec/versions.json.

## Reports

Every mismatch is printed with the case, the part, the expected outcome and the outcome of each run, runs with the same outcome together. Strings are shown with characters that a terminal may not show escaped, and where canonical bytes differ, the first differing byte is shown in context. A summary follows, with the number of cases in each corpus file, the number run in each run and in both languages and the result. The outputs are JSON Lines: a header that names the run, the package, the interpreter, the version of the YAML package and, for R, the locale, then one record for each part of each case with every string written as the hexadecimal digits of its bytes, so that the two runners write identical records for identical outcomes.

## Adding a corpus

A new JSON corpus file must be listed in corpora.json, or the harness stops. A file of an existing kind needs nothing else. A new kind needs a function in run_r.R and in run_python.py that computes the outcome of each part, and the expected outcomes in `expected_parts()` of parity.py, written from the README of the corpus. A kind whose outcomes match by rules other than equality and the tolerance of real values also needs functions that compare and show them, which `compare_runs()` passes to `Report.compare()`, as `audit_differences()` and `show_audit()` do for the audit corpus.

## Result

At the end of M1, on R 4.3.3 and Python 3.13 under Linux, the harness ran 1,183 cases: 1,169 in both languages and 14 that only one language can hold, with 2,586 outcomes compared, and read the vendored files of spec/, with 14 outcomes. Every case gave its expected outcome in Python and in R under C.UTF-8 and C, and the runs agreed. The 403 cases of the table and formula corpora waited for M2.

At the end of M2a, on R 4.3.3 and on Python 3.13 and 3.11 under Linux, the harness ran 1,588 cases, among them the 194 table cases and the 211 formula cases: 1,574 in both languages and 14 that only one language can hold, with 3,055 outcomes compared, and read the vendored files of spec/, with 14 outcomes. Every case gave its expected outcome in Python and in R under C.UTF-8 and C, and the runs agreed. After the review of M2a, which added 35 formula cases, the harness ran 1,623 cases on R 4.3.3 and on Python 3.13 and 3.11: 1,609 in both languages, with 3,109 outcomes compared, and every case again gave its expected outcome in every run. With the four formula cases added after M2a, it ran 1,627 cases, 1,613 in both languages, and compared 3,115 outcomes with the same result.

In M2b-3, before the port of the privacy filter, on R 4.3.3 and on Python 3.13 and 3.11 under Linux, the harness ran 2,066 cases, among them the 287 audit cases in internal mode and the 152 results cases: 2,052 in both languages and 14 that only one language can hold, with 3,577 outcomes compared, and read the vendored files of spec/, with 14 outcomes. Every case gave its expected outcome in Python and in R under C.UTF-8 and C, and the runs agreed. The 69 shareable parts of audits/privacy.json wait for the filter.
