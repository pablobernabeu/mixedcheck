# mixedcheck (R)

The R package of mixedcheck, which audits study designs before mixed-effects
models are fitted and diagnoses and reports fitted models. It shares the
registry of checks, the schemas and the test fixtures with the Python package
of the same name. Each component is built in R first.

The package is in development and has not been released. So far it provides
`spec_versions()`, which returns the versions of the shared specification
installed with the package, and the functions below. They read and write the
shared formats, read tables, build the canonical model and its design
matrices, run the audits and write and validate their results:

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
- `read_table()` reads a CSV file with the strict table reader, under the
  table block of a declaration or with the types inferred from the values,
  and returns a data frame or the first problem with a stable code.
- `formula_ir()` parses an lme4-style formula and builds the canonical IR of
  the model, whose `canonical_hash()` is its IR hash, and
  `design_matrices()` builds its design and analysis samples, X, the sparse
  Z and the response, trials, offset and weight vectors. `design_samples()`
  returns the two samples alone.
- `audit()` runs the checks of the registry on the design of a model and
  returns a results object with an access log of every access to the
  outcome. In shareable mode, the default, the privacy filter suppresses
  the values that could disclose a person's data.
- `validate_results()` validates a results document and verifies its internal
  sidecar against it, and `write_results()` writes a results document and its
  sidecar.

The functions that both packages provide have the same names and arguments.
`design_matrices()` and `design_samples()` number rows, and
`design_matrices()` random terms, from 1 in R and from 0 in Python, whereas
indices inside the IR count from 0 in both, and a missing value is `NA` in R
and `None` in Python. The tests run every case of the JSON, number, Unicode,
hash, HMAC, declaration, YAML, table, formula, results and audit corpora,
with the cases of the privacy filter in both modes. The
[parity harness](https://github.com/pablobernabeu/lmecheck/tree/main/parity)
of the repository checks that both packages agree on every case of the
corpora, and its differential test that they agree on the tables of the
disclosure-attack harness and on generated designs in both modes.

``` r
library(mixedcheck)
spec_versions()
value <- read_json_strict(charToRaw('{"b": [1.50, true], "a": "x"}'), "hashable")
rawToChar(canonical_bytes(value, "hashable"))
canonical_hash(value, "hashable")
declaration <- validate_declaration(list(vocabulary = "0.1.0", goal = "exploratory"))
canonical_hash(declaration, "hashable")
path <- tempfile(fileext = ".csv")
writeBin(charToRaw("id,cond,rt\n1,A,512.5\n2,B,\n3,A,498\n4,B,530\n"), path)
data <- read_table(path)
ir <- formula_ir("rt ~ cond", data = data)
canonical_hash(ir, "hashable")
design_matrices(ir, data)$x
audit(data, "rt ~ cond")
```

It needs R 4.2.0 or later. To install it from a clone of the repository:

``` sh
R CMD INSTALL r
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design
documents and both packages. Changes are listed in
[NEWS.md](https://github.com/pablobernabeu/lmecheck/blob/main/r/NEWS.md). The
package is MIT-licensed.
