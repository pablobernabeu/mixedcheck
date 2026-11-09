# Changelog

Notable changes to the Python package mixedcheck are recorded here, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The package skeleton, with `spec_versions()`, which returns the versions of the registry, the schemas and the canonicaliser in the shared specification vendored into the package.
- The package ships the shared specification: the compiled registry of checks, the error catalogue, the schema bundle and the list of code points that Unicode 14.0 assigns. `spec_versions()` reports registry, schema bundle and canonicaliser version 0.1.0.
- `read_json_strict()` reads JSON in the hashable or data profile or in the plain mode and raises `MixedcheckError`, a subclass of ValueError that carries the issues, with a code of the shared error catalogue for the first problem. `canonical_bytes()` writes a value by RFC 8785 with ECMAScript number formatting, and `canonical_hash()` hashes those bytes. `hash_bytes()` and `hash_file()` return SHA-256 hashes, and `new_commitment_key()`, `commitment_key_id()` and `keyed_commitment()` create HMAC-SHA-256 keyed commitments. The functions have the names and arguments of the R package's.
- `validate_declaration()` checks a declaration of vocabulary 0.1, read from a JSON or YAML file or given in memory, in the five stages of the specification and reports every problem of the first stage that finds any. YAML is read with every scalar as a string and needs the extra 'yaml' (PyYAML).
- `read_registry()` returns the vendored compiled registry after checking its digest and version.
- The package ships the marker `py.typed`, and its type hints pass mypy in strict mode.
- The tests run every case of the JSON, number, Unicode, hash, HMAC, declaration and YAML corpora.
- `read_table()` reads a CSV file with the strict table reader of the [table specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/tables.md), applying the table block of a declaration or inferring the column types without one, and raises `MixedcheckError` with one issue of the table area, located by byte offset. It returns a pandas DataFrame whose columns have dtype object, with the column types in `attrs["types"]`, and the tests run every case of the table corpus.
- `formula_ir()` parses an lme4-style formula with the in-house parser and builds the canonical IR of the [IR specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/ir.md) from the formula, a declaration, the data, the coding argument, the weights and the sample columns, or raises `MixedcheckError` with one issue of the formula area. It reads a pandas DataFrame in which None, pandas.NA and the NaN of pandas' string dtype are missing, so that NaN in a float column is a value, and a categorical whose categories are strings by its labels, as R reads a factor. `canonical_hash()` of the IR gives its IR hash.
- `design_matrices()` builds the design and analysis samples of an IR as row positions counted from 0, X as a numpy array with the columns that the sequential rule drops, the sparse Z as a `scipy.sparse.csc_array` with its columns described in a DataFrame and the response, trials, offset and weight vectors, with the members and shapes of the R function. `design_samples()` returns the two samples alone, even when `design_matrices()` refuses the values of the rows.
- The tests run every case of the formula corpus, with the design matrices of the cases that give them, and the design and analysis samples of the table cases with a formula.
