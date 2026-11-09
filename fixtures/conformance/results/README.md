# Results corpus

These cases test `validate_results()`, the validator of results documents and of their internal sidecars that M2 implements in both packages ([docs/spec/documents.md](../../../docs/spec/documents.md), Results document, Validation and Internal sidecar). Each case gives a results document as a file, with a sidecar and the data behind its commitments in some cases, and expects the issues that validation reports, an empty list for a valid document, and the outcome of the verification of the sidecar.

| File | Cases | Covers |
|---|---|---|
| reading.json | 19 | stage 1: every code of the strict reader in the data profile, with its offset, and the precedence of its stages |
| version.json | 10 | stage 2: E1441 at `/results_version` before every other check, and versions left to the structural check |
| structure.json | 29 | stage 3: every structural keyword that the schema uses, days in a month, E1207 with E1406, sorting and the cap at 100 with W1490 |
| rules.json | 15 | stage 4: E7001 to E7006, the comparison of scopes after NFC, the order of prefixes and sorting |
| shareable.json | 18 | the invariants E7020 to E7023 of stage 4 and E7024 of stage 5, with by_unit ratios, the order in which a value gets its one issue, the exception for 'secondary', quantiles without n and internal documents |
| registry.json | 13 | stage 5: W7090, E7040 to E7044, with the exception of the scope grouping_factor_or_model, and E7025, with n beside a count that differs, beside a suppressed count and beside its count |
| stages.json | 7 | the order of the five stages |
| sidecar.json | 23 | reading, version, structure and rules of the sidecar, the results file hash, missing keys, the order of the issues of verification and E1314 for the data file, the analysis table and the outcome column |
| valid.json | 11 | valid internal and shareable documents, among them the example of documents.md, with and without a disclosure unit, at T0, T1 and T2 |

The cases cover every rule of documents.md on results documents and sidecars, the five stages of validation and their order, W7090, the n of a quantile (E7025) and the invariants of a shareable document (E7020 to E7024). Every case file and every input file is listed in spec/vendoring.json, so that the packages' tests read them from their copies of the corpora, and every case file in parity/corpora.json with the kind 'results'.

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile. The files are ASCII, with every other character written as an escape. The inputs of the cases of a file lie in a directory named after the file without '.json', such as reading/ for reading.json. Each case has these members:

- `id` and `description`. The ID is 'results-', the name of the file without '.json', '-' and three digits, such as results-reading-001, unique across the corpora. The description says which rule, stage or order the case is about.
- `document`: the results document, as a path relative to this directory, read as bytes. Inputs may hold a byte-order mark, invalid UTF-8, duplicate keys or other faults of reading on purpose, and .gitattributes keeps their bytes as stored.
- `sidecar`: the internal sidecar, as a path, when the case verifies one.
- `data`: the data behind the commitments of the document, as the path of a CSV file, when the case recomputes them, and `declaration`, the path of the declaration of the run, when the run had one.
- `expected`: `issues` and, when the case has a sidecar, `sidecar_issues`.

`issues` lists the issues that `validate_results()` reports for the document, in the order reported, each with its `code`, its rendered `message` and its `offset` or `pointer`, or neither for a code without a location (`issue` in [defs.schema.json](../../../spec/schemas/defs.schema.json)). Reading reports one issue, located by byte offset, the version check one, and the later stages report every issue of the first stage that finds any, sorted by pointer, code and message and capped at 100 with W1490 (errors.md, Reporting rules). An empty list says that the document is valid, and a list holding W7090 alone that it is valid but was produced with another registry. The tests use the compiled registry vendored with the package, so a case of stage 5 records the hash of that registry, and a case of W7090 another hash. After a change to the registry, [spec/tools/rehash_results.py](../../../spec/tools/rehash_results.py) replaces the old registry hash wherever the corpus records it and then the results file hash of each rewritten document wherever a sidecar records it, leaving the other hashes that cases record on purpose, and its option --check reports whether the corpus is up to date.

`sidecar_issues` lists, in the same form, the issues of the sidecar and of its verification against the document, which run only when `issues` holds no error: reading the sidecar in the data profile, its version, its structure and its rules (E1441, E1321, E7060 and E7061), then, in the order of documents.md (Internal sidecar), E1321 at `/results_hash` when the hash differs from that of the document's file, E1313 without a location once for each key identifier that the commitments name and the sidecar lacks and, when the case gives `data`, E1314 for each commitment that the data do not match. An empty list says that the sidecar is valid and agrees with the document.

## Comparison

The test calls `validate_results()` on the document, with the sidecar, the data and the declaration when the case gives them, and compares the issues with `issues` and `sidecar_issues` exactly: the codes, the messages and the locations, in order. Every expected issue is derived from documents.md, conventions.md and errors.md, and its message is rendered from the template of its code as errors.md (Rendering messages) describes.

## Provenance

The cases are written for this project from the specifications and are MIT-licensed. Each document and its expected issues are derived from documents.md, results.schema.json, privacy.md, conventions.md and errors.md by hand or by scratch code written from the specifications alone, kept outside the repository and deleted, never from either package. Valid documents are checked against results.schema.json with the jsonschema package as an oracle. [spec/tools/test_results_corpus.py](../../../spec/tools/test_results_corpus.py) checks the format of every case that exists: its members, that its inputs exist under this directory and are listed in spec/vendoring.json, that every issue has a known code with the location its code requires, that a case without issues holds a document that is valid under the schema, and that every file is in this table and in parity/corpora.json. The tests of both packages and the parity harness then run every case.
