# Changelog

Notable changes to the Python package mixedcheck are recorded here, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The package skeleton, with `spec_versions()`, which returns the versions of the registry, the schemas and the canonicaliser in the shared specification vendored into the package.
- The package ships the shared specification: the compiled registry of checks, the error catalogue, the schema bundle, the list of code points that Unicode 14.0 assigns and the conformance corpora, including the table and formula corpora for M2. `spec_versions()` reports registry, schema bundle and canonicaliser version 0.1.0.
- `read_json_strict()` reads JSON in the hashable or data profile or in the plain mode and raises `MixedcheckError`, a subclass of ValueError that carries the issues, with a code of the shared error catalogue for the first problem. `canonical_bytes()` writes a value by RFC 8785 with ECMAScript number formatting, and `canonical_hash()` hashes those bytes. `hash_bytes()` and `hash_file()` return SHA-256 hashes, and `new_commitment_key()`, `commitment_key_id()` and `keyed_commitment()` create HMAC-SHA-256 keyed commitments. The functions have the names and arguments of the R package's.
- `validate_declaration()` checks a declaration of vocabulary 0.1, read from a JSON or YAML file or given in memory, in the five stages of the specification and reports every problem of the first stage that finds any. YAML is read with every scalar as a string and needs the extra 'yaml' (PyYAML).
- `read_registry()` returns the vendored compiled registry after checking its digest and version.
- The package ships the marker `py.typed`, and its type hints pass mypy in strict mode.
- The tests run every case of the JSON, number, Unicode, hash, HMAC, declaration and YAML corpora from the installed package.
