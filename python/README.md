# mixedcheck (Python)

The Python package of mixedcheck, which audits study designs before mixed-effects models are fitted and diagnoses and reports fitted models. It shares the registry of checks, the schemas and the test fixtures with the R package of the same name, and each component is ported from the R implementation against shared JSON fixtures.

The package is in development and has not been released. So far it provides `mixedcheck.spec_versions()`, which returns the versions of the shared specification installed with the package, and the layer that every reader and writer of the package builds on:

- `read_json_strict()` reads JSON in the hashable or data profile and reports the first problem with a stable code.
- `canonical_bytes()` writes a value by RFC 8785, with numbers in ECMAScript's shortest form, and `canonical_hash()` returns the SHA-256 hash of those bytes. `hash_bytes()` and `hash_file()` hash bytes and files.
- `new_commitment_key()`, `commitment_key_id()` and `keyed_commitment()` create commitment keys and HMAC-SHA-256 keyed commitments.
- `validate_declaration()` checks a design declaration written in JSON, in YAML (with the extra 'yaml') or in memory, and returns it, so that `canonical_hash()` gives its declaration hash.
- `read_registry()` returns the registry of checks installed with the package.

A problem is raised as `mixedcheck.MixedcheckError`, a subclass of ValueError, whose `issues` hold the codes of the shared error catalogue with their messages and locations. The functions have the same names and arguments as in the R package and give the same codes, bytes and hashes. The tests run every case of the JSON, number, Unicode, hash, HMAC, declaration and YAML corpora installed with the package, and the table and formula corpora wait for the table reader and formula parser of M2. The [parity harness](https://github.com/pablobernabeu/lmecheck/tree/main/parity) of the repository checks that both packages agree on every case of these corpora.

```python
import mixedcheck

mixedcheck.spec_versions()
value = mixedcheck.read_json_strict(b'{"b": [1.50, true], "a": "x"}', "hashable")
mixedcheck.canonical_bytes(value, "hashable")
mixedcheck.canonical_hash(value, "hashable")
declaration = mixedcheck.validate_declaration({"vocabulary": "0.1.0", "goal": "exploratory"})
mixedcheck.canonical_hash(declaration, "hashable")
```

It needs Python 3.11 or later, with numpy, pandas and scipy. To install it from a clone of the repository, with PyYAML for declarations written in YAML:

```bash
python -m pip install "./python[yaml]"
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design documents and both packages. Changes are listed in [CHANGELOG.md](https://github.com/pablobernabeu/lmecheck/blob/main/python/CHANGELOG.md). The package is MIT-licensed.
