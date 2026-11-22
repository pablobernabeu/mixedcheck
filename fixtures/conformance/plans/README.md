# Plan corpus

These cases test `validate_plan()`, the validator of plans that M3 implements in both packages ([docs/spec/documents.md](../../../docs/spec/documents.md), Plan, version 0.1, Validation). Each case gives a plan as a file and expects the issues that validation reports, an empty list for a valid plan.

| File | Cases | Covers |
|---|---|---|
| validate.json | 25 | valid protected and exploratory plans, complex random intercepts in place of a protected slope after a step complex_intercepts and without one (E7306), E1441, E1321 at the design-plan hash and at a binding hash, E7301 to E7306, E7307 in Python, E7308, E7309 in both languages and E6101 for a column name, a reference level, a repeated random term, sample columns and offsets out of order, a carried level and a repeated fixed term |

Every case file and every input file is listed in spec/vendoring.json, so that the packages' tests read them from their copies of the corpora, and every case file in parity/corpora.json with the kind 'plan'.

## Format

Each file is a JSON object with a `description` and a list of `cases`. The files are ASCII. The plans of a file lie in a directory named after the file without '.json'. Each case has these members:

- `id` and `description`. The ID is 'plans-', the name of the file without '.json', '-' and three digits.
- `plan`: the plan, as a path relative to this directory.
- `languages`: present only for a case that one language alone runs, since only the R package can run the terminal state cluster_robust_cr2, so that the Python package reports E7307 for it (errors.md, plan).
- `expected`: `issues`, the issues that `validate_plan()` reports, in the order reported, each with its `code`, its rendered `message` and its `pointer` for a code located by pointer. The rules in code report every issue they find, sorted by pointer, code and message (errors.md, Reporting rules). E6101 is reported at the first member, in the order of the canonical serialisation, that differs from what the rules of ir.md give, which is the deepest member that differs.

## Provenance

The cases are written for this project from documents.md, ir.md, plan.schema.json and errors.md, and are MIT-licensed. The plans and their expected issues were written by scratch code from the specifications alone, kept outside the repository, never from either package. The IRs derive from the IR of case ordinary-33 of the formula corpus, the example of ir.md, with 'cond' frozen. [spec/tools/test_plan_corpus.py](../../../spec/tools/test_plan_corpus.py) checks the format of every case, its listing in the README, spec/vendoring.json and parity/corpora.json, the recorded hashes of every plan whose case does not expect E1321 and the validity of every plan under plan.schema.json. The tests of both packages and the parity harness then run every case.
