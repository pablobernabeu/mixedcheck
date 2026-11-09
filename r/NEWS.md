# mixedcheck 0.0.0.9000 (development version)

## Added

* The package skeleton, with `spec_versions()`, which returns the versions of
  the registry, the schemas and the canonicaliser in the shared specification
  vendored into the package.

* The package ships the shared specification: the compiled registry of
  checks, the error catalogue, the schema bundle, the list of code points that
  Unicode 14.0 assigns and the conformance corpora, including the table and
  formula corpora. `spec_versions()` reports registry, schema bundle and
  canonicaliser version 0.1.0.

* `read_json_strict()` reads JSON in the hashable or data profile or in the
  plain mode and reports the first problem with a code of the shared error
  catalogue. `canonical_bytes()` writes a value by RFC 8785 with ECMAScript
  number formatting, and `canonical_hash()` hashes those bytes. `hash_bytes()`
  and `hash_file()` return SHA-256 hashes, and `new_commitment_key()`,
  `commitment_key_id()` and `keyed_commitment()` create HMAC-SHA-256 keyed
  commitments. utf8 (>= 1.2.4), which implements Unicode 14.0, joins the
  Imports for NFC.

* `validate_declaration()` checks a declaration of vocabulary 0.1, read from
  a JSON or YAML file or given in memory, in the five stages of the
  specification and reports every problem of the first stage that finds any.
  YAML is read with every scalar as a string, and yaml joins the Suggests.

* `read_registry()` returns the vendored compiled registry after checking its
  digest and version.

* The tests run every case of the JSON, number, Unicode, hash, HMAC,
  declaration and YAML corpora from the installed package, also with
  `options(OutDec = ",")`.

* `read_table()` reads a CSV file with the strict table reader of the
  [table specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/tables.md),
  under the table block of a declaration or with the types inferred from the
  values, and returns a data frame whose attribute `types` holds the column
  types, or reports the first problem with a code of the table area. The
  tests run every case of the table corpus from the installed package.

* `formula_ir()` parses an lme4-style formula with the in-house parser and
  builds the canonical IR of the
  [IR specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/ir.md)
  from the formula, a declaration, the data, the coding argument, the weights
  and the sample columns, or reports the first problem with a code of the
  formula area. It reads a data frame in which only NA is missing, so that
  NaN is a value, and `canonical_hash()` of the IR gives its IR hash.

* `design_matrices()` builds the design and analysis samples of an IR, X
  with the columns that the sequential rule drops, the sparse Z as a
  `Matrix::dgCMatrix` and the response, trials, offset and weight vectors.
  `design_samples()` returns the two samples alone, even when
  `design_matrices()` refuses the values of the rows. Matrix joins the
  Imports, and lme4 joins the Suggests as a test oracle.

* The tests run every case of the formula corpus from the installed package,
  with the design matrices of the cases that give them, and the design and
  analysis samples of the table cases with a formula.
