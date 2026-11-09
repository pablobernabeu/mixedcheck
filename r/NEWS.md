# mixedcheck 0.0.0.9000 (development version)

## Added

* The package skeleton, with `spec_versions()`, which returns the versions of
  the registry, the schemas and the canonicaliser in the shared specification
  vendored into the package.

* The package ships the shared specification: the compiled registry of
  checks, the error catalogue, the schema bundle and the list of code points
  that Unicode 14.0 assigns. `spec_versions()` reports registry, schema bundle
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
  declaration and YAML corpora, also with `options(OutDec = ",")`.

* `read_table()` reads a CSV file with the strict table reader of the
  [table specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/tables.md),
  under the table block of a declaration or with the types inferred from the
  values, and returns a data frame whose attribute `types` holds the column
  types, or reports the first problem with a code of the table area. The
  tests run every case of the table corpus.

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
  `design_matrices()` refuses the values of the rows. Matrix and methods join
  the Imports, and lme4 joins the Suggests as a test oracle.

* The tests run every case of the formula corpus, with the design matrices of
  the cases that give them, and the design and analysis samples of the table
  cases with a formula.

* `validate_results()` validates a results document in the five stages of the
  [results specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/documents.md)
  and, with its internal sidecar, checks the sidecar and verifies the results
  file hash, the commitment keys and, from the data of the run, the
  commitments to the data file, the analysis table and the outcome columns.
  `write_results()` writes a results document as its canonical bytes and its
  internal sidecar, whose file names must show the privacy mode (E7010). The
  tests run every case of the results corpus.

* The tests of the vendored registry apply the rules on registry entries that
  M2 added, among them E4022 to E4024.

* `audit()` runs the 24 checks of the
  [registry](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/registry.md)
  on the design of a model and returns a results object, in the steps of the
  [execution plan](https://github.com/pablobernabeu/lmecheck/blob/main/docs/design/03-execution-plan.md)
  (M2), with an access log that commits to every outcome column read. The
  outcome-blind checks never read the response, its trials or a declared
  outcome column, and a run that would gives E6069. The environment variable
  MIXEDCHECK_TIME fixes its times. Among the checks are the identifiability
  of the covariance parameters from the rank of their Gram matrix, the
  connected components of two crossed grouping factors, the generalised
  variance inflation factor of each main-effect term and the design degrees
  of freedom of an assignment. outcome.separation solves its linear programs
  with lpSolve, which joins the Suggests, and is not available without it.

* In shareable mode, the default of `audit()`, the privacy filter of the
  [privacy specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/privacy.md)
  writes as null the values that could disclose a person's data, suppresses
  a finding of an outcome check that rests on such a value, renders messages
  from the written values and replaces labels with pseudonyms, which the
  sidecar maps back to them. The tests run every case of the audit corpus,
  those of the privacy filter in both modes, and validate every document.

* `design_matrices()` refuses events or trials of a response with a trials
  column that are not integers with 0 <= events <= trials (E6078).

* Where /dev/urandom does not exist, as on Windows, or cannot be read,
  `new_commitment_key()` creates a key with `openssl::rand_bytes()` when
  openssl is installed, so that E1312 arises only without it. openssl joins
  the Suggests.

* The messages of findings write a real statistic of at least 1e15 in
  absolute value in scientific notation, such as 2e+20, as the
  [registry specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/registry.md)
  (Messages) states.

* `validate_results()` reports E7025 when the quantile of a statistic writes
  an n although the count that gives n is not written in its finding, or an
  n other than that count, in every document.

* In a C locale, `validate_declaration()`, `formula_ir()` and `audit()` keep
  apart column names outside ASCII and names that hold the text into which
  R translates them, such as `<U+00FC>`, which lookups by name had merged.

* `audit()` sums the values of the levels of a grouping factor exactly with
  memory that grows with the rows, so that a factor with many small levels
  needs less memory and time.

* The privacy filter of `audit()` writes the detail 'quantile' for every
  quantile that the quantile rule suppresses, compares the levels that an
  assignment removes from a sample in which they are person counts, hides
  the rows without a key value when they would give back rows that a
  predictor removes, never writes the smallest eigenvalue of
  identifiability.gram_rank and suppresses outcome.separation for a fixed
  part that codes one variable, such as one factor, as the
  [privacy specification](https://github.com/pablobernabeu/lmecheck/blob/main/docs/spec/privacy.md)
  states.

* In a draft declaration, a unit whose name or columns are inferred counts
  as absent, together with the assignments to it and a disclosure unit that
  names it, and outcome.boundary_shares is not available when the bounds of
  a bounded score are inferred.

* MIXEDCHECK_TIME accepts only the ASCII digits 0 to 9.

* identifiability.df_budget and assignment.design_df take the rank within
  the levels from an orthonormal basis of the kept fixed-effects columns, so
  that adding a constant to a column, as with times in Unix seconds, no
  longer changes the budget, and values near the largest double no longer
  stop the run. structure.within_between divides its column by its largest
  absolute value, so that values beyond about 1e154 no longer give 'NaN'.

* identifiability.gram_rank forms the elements between random terms with
  one sparse product for each term, so that a model with hundreds of random
  terms takes seconds instead of minutes.
