# mixedcheck (R)

The R package of mixedcheck, which audits study designs before mixed-effects
models are fitted and diagnoses and reports fitted models. It shares the
registry of checks, the schemas and the test fixtures with the Python package
of the same name. Each component is built in R first.

The package is in development and has not been released. So far it provides
`spec_versions()`, which returns the versions of the shared specification
installed with the package, and the layer that every reader and writer of the
package builds on:

- `read_json_strict()` reads JSON in the hashable or data profile and reports
  the first problem with a stable code.
- `canonical_bytes()` writes a value by RFC 8785, with numbers in ECMAScript's
  shortest form, and `canonical_hash()` returns the SHA-256 hash of those
  bytes. `hash_bytes()` and `hash_file()` hash bytes and files.
- `new_commitment_key()`, `commitment_key_id()` and `keyed_commitment()`
  create commitment keys and HMAC-SHA-256 keyed commitments.
- `validate_declaration()` checks a design declaration written in JSON, in
  YAML (with the suggested package yaml) or in memory, and returns it, so
  that `canonical_hash()` gives its declaration hash.
- `read_registry()` returns the registry of checks installed with the
  package.

The functions have the same names and arguments as in the Python package.
The tests run every case of the JSON, number, Unicode, hash, HMAC, declaration
and YAML corpora installed with the package, and the table and formula
corpora wait for the table reader and formula parser of M2. The
[parity harness](https://github.com/pablobernabeu/lmecheck/tree/main/parity)
of the repository checks that both packages give the same codes, canonical
bytes and hashes for every case of these corpora.

``` r
library(mixedcheck)
spec_versions()
value <- read_json_strict(charToRaw('{"b": [1.50, true], "a": "x"}'), "hashable")
rawToChar(canonical_bytes(value, "hashable"))
canonical_hash(value, "hashable")
declaration <- validate_declaration(list(vocabulary = "0.1.0", goal = "exploratory"))
canonical_hash(declaration, "hashable")
```

It needs R 4.2.0 or later. To install it from a clone of the repository:

``` sh
R CMD INSTALL r
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design
documents and both packages. Changes are listed in
[NEWS.md](https://github.com/pablobernabeu/lmecheck/blob/main/r/NEWS.md). The
package is MIT-licensed.
