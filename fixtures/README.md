# Fixtures

This directory holds the test fixtures that the R and Python packages share: the conformance corpora, and later the simulated pathology zoo and the golden files, each with its provenance (02-decisions.md, Q7 and Q8). A directory whose contents are not MIT-licensed is marked with REUSE-style licence files (03-execution-plan.md, M0). Whether the published test vectors of RFC 4231, RFC 8785 and NIST in conformance/hash/, hmac/ and json/ need such files is an open licence check of the execution plan.

| Directory | Contents |
|---|---|
| [conformance/formulas/](conformance/formulas/README.md) | formulas with their declaration, data and coding, and the expected canonical IR, its hash and some design matrices or the issue that they report, or the expected error code (docs/spec/ir.md) |
| [conformance/json/](conformance/json/README.md) | the strict JSON reader in each mode and the RFC 8785 serialiser: the vectors of RFC 8785, every rejection of the reader, profile violations and canonical bytes with their hashes (docs/spec/conventions.md) |
| [conformance/numbers/](conformance/numbers/README.md) | ECMAScript number formatting, the reading of number tokens with correct rounding, the number rules of the hashable profile, decimal constants and vectors of the rendering of real statistics in messages (docs/spec/registry.md) |
| [conformance/unicode/](conformance/unicode/README.md) | UTF-8 validation, normalisable strings, NFC and NFD pairs, the order of identifiers, NFC in the hashable profile and cases a C locale or an encoding mark could change |
| [conformance/hash/](conformance/hash/README.md) | SHA-256 of bytes, files and sections of documents |
| [conformance/hmac/](conformance/hmac/README.md) | the HMAC-SHA-256 vectors of RFC 4231, commitment keys and their identifiers, and keyed commitments |
| [conformance/declarations/](conformance/declarations/README.md) | declarations in JSON: valid ones covering vocabulary 0.1 with their canonical bytes and hashes, ones that each break one rule of each stage of validation and ones that break several, with the issues the validator reports (docs/spec/declarations.md) |
| [conformance/yaml/](conformance/yaml/README.md) | declarations written in YAML: their conversion to JSON with the canonical bytes and hashes of the result, and the issues of reading, pre-scan, parsing, coercion, the hashable profile and validation |
| [conformance/audits/](conformance/audits/README.md) | small tables with a formula, a declaration and a tier of access, and the findings that `audit()` gives for the checks of registry 0.1.0, in internal and shareable mode, or the issue that refuses the run (docs/spec/registry.md and docs/spec/privacy.md) |
| [conformance/results/](conformance/results/README.md) | results documents and sidecars with the issues that `validate_results()` reports and the outcome of the verification of the sidecar (docs/spec/documents.md) |
| [conformance/tables/](conformance/tables/README.md) | CSV inputs with their declarations and the columns that the table reader returns, with the design and analysis samples of a formula, or the issue that it reports (docs/spec/tables.md) |
| [conformance/tools/](conformance/tools/README.md) | the scripts that write corpora, which are not vendored |

The files that the packages read are listed in spec/vendoring.json and reach them only through spec/tools/vendor.py. The tests of each package run every case of the corpora from the copies in its test directory (spec/README.md), and the parity harness ([parity/README.md](../parity/README.md)) runs every case in both packages and compares their outcomes with each other and with the expected outcomes. Every corpus file of cases must be listed in parity/corpora.json with the kind of its cases, and the harness stops when one is missing.
