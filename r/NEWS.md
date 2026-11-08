# mixedcheck 0.0.0.9000 (development version)

## Added

* The package skeleton, with `spec_versions()`, which returns the versions of
  the registry, the schemas and the canonicaliser in the shared specification
  vendored into the package.

* The package ships the shared specification: the compiled registry of
  checks, the error catalogue, the schema bundle, the list of code points that
  Unicode 14.0 assigns and the conformance corpora, including the table and
  formula corpora for M2. `spec_versions()` reports registry, schema bundle
  and canonicaliser version 0.1.0.

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
