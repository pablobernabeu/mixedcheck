# mixedcheck 0.1.0

## Added

* `design_plan()` builds the Stream B plan of a design without reading the
  outcome: the design-implied ceiling of each grouping factor with its counts
  and identifiability verdict, rung 0 restricted to identifiable terms, the
  outcome-free ladder with its protected set, the stopping rule, the terminal
  state, the design-plan hash and, when lme4 is installed, an lme4 execution
  binding. `validate_plan()` validates a plan, and `preregistration_text()`
  states it in words that both packages write identically. `audit()` takes a
  plan in its new argument `plan`, refuses a run that does not belong to it
  (E7310) and records accesses to the outcome at T1 and T2 as planned.

* `declaration()` and the helpers `declare_unit()`, `declare_crossing()`,
  `declare_observation()`, `declare_assignment()`, `declare_variable()` and
  `declare_estimand()` build a declaration in code, and `draft_design()`
  writes a draft declaration from the grouping columns of the data, with
  every entry marked as inferred.

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
  [table specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/tables.md),
  under the table block of a declaration or with the types inferred from the
  values, and returns a data frame whose attribute `types` holds the column
  types, or reports the first problem with a code of the table area. The
  tests run every case of the table corpus.

* `formula_ir()` parses an lme4-style formula with the in-house parser and
  builds the canonical IR of the
  [IR specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/ir.md)
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
  [results specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/documents.md)
  and, with its internal sidecar, checks the sidecar and verifies the results
  file hash, the commitment keys and, from the data of the run, the
  commitments to the data file, the analysis table and the outcome columns.
  `write_results()` writes a results document as its canonical bytes and its
  internal sidecar, whose file names must show the privacy mode (E7010). The
  tests run every case of the results corpus.

* The tests of the vendored registry apply the rules on registry entries that
  M2 added, among them E4022 to E4024.

* `audit()` runs the 24 checks of the
  [registry](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/registry.md)
  on the design of a model and returns a results object, in the steps of the
  [execution plan](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/design/03-execution-plan.md)
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
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  writes as null the values that could disclose a person's data, suppresses
  a finding of an outcome check that rests on such a value, renders messages
  from the written values and replaces labels with pseudonyms, which the
  sidecar maps back to them. The tests run every case of the audit corpus,
  those of the privacy filter in both modes, and validate every document.
  On CRAN they run the first case of each file of the corpus and every
  fifth after it.

* The privacy filter keeps k values between two quantiles of one count that
  a shareable document writes, the spacing condition of the quantile rule,
  and `validate_results()` reports E7022 for two written quantiles without
  it. No finding of registry 0.1.0 changes, since a quartile that the
  quantile rule writes already lies k values from the median.

* The privacy filter hides the analysed levels of an item wherever the
  firing of rule 3, beside the class non_person of the item in a sample
  whose rows or contributors rule 1 hides, would give the rows or members
  without an outcome, and the table's rows beside the analysis sample when
  the names of sample.raw_vs_analysis show k - 1 rows that leave the design
  sample. The first acts at k = 3 for rows and at any k for contributors,
  the second at k of 4 or less.

* `design_matrices()` refuses events or trials of a response with a trials
  column that are not integers with 0 <= events <= trials (E6078).

* Where /dev/urandom does not exist, as on Windows, or cannot be read,
  `new_commitment_key()` creates a key with `openssl::rand_bytes()` when
  openssl is installed, so that E1312 arises only without it. openssl joins
  the Suggests.

* The messages of findings write a real statistic of at least 1e15 in
  absolute value in scientific notation, such as 2e+20, as the
  [registry specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/registry.md)
  (Messages) states, and a positive one whose rounding shows only zeros as
  under the smallest positive value, such as under 0.1, so that 1 minority
  event for 21 fixed-effects columns no longer reads as none.

* `validate_results()` reports E7025 when the quantile of a statistic writes
  an n although the count that gives n is not written in its finding, or an
  n other than that count, in every document.

* `validate_results()` reports E7045 when a statistic lacks the quantile that
  its registry entry gives it, or has one that its entry does not give, and
  E7041 when the p of a quantile differs from the entry's, in every
  document, so that a shareable document cannot leave a minimum out of the
  quantile rule.

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
  predictor removes and suppresses outcome.separation for a fixed
  part that codes one variable, such as one factor, or whose values two rows
  share, in the design or the analysis sample, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  states.

* The privacy filter of `audit()` writes the detail 'secondary' or
  'quantile' in place of 'min_count' where that detail would bound a
  suppressed count and, in a run that reads the outcome, suppresses the reals
  of the outcome-blind checks on the design sample where they would give
  back the rows or levels without an outcome. A shareable document records
  the IR hash of the IR without the constants of its mean centrings.

* `validate_results()` reports E7046 when a parameter of the privacy filter
  that a document records differs from the registry, and E7041 when a count
  that resolves by unit is not a person count in a document without a
  disclosure unit.

* In a draft declaration, a unit whose name or columns are inferred counts
  as absent, as does a unit declared within_parent in it, together with the
  assignments to them and a disclosure unit that names one, and
  outcome.boundary_shares is not available when the bounds of a bounded
  score are inferred.

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

* identifiability.gram_rank compares the basis of each covariance parameter
  with its unprojected basis level by level, so that a factor with one level
  of one row and another of hundreds of thousands no longer has its
  variance reported as absorbed by the fixed effects, and a covariance whose
  basis cancels across the levels vanishes, as the
  [registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/identifiability.gram_rank.yaml)
  states.

* identifiability.gram_rank is near_threshold when rounding error, whose
  bound grows with the condition of the fixed-effects columns, could move a
  value that it compares with its rank tolerance across that tolerance, as
  with one level of a single row beside a few hundred rows or more and a
  slope, while exactly confounded parameters stay clear up to about 1e5
  rows. It no longer reports the residual as absorbed by the fixed effects
  when the weights differ by many orders of magnitude, as the
  [registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/identifiability.gram_rank.yaml)
  states.

* `validate_results()` validates a results document in about half the time,
  and in less for documents whose statistics repeat those of documents
  validated earlier in the session.

* The privacy filter of `audit()` gives the detail 'secondary', in place of
  'min_count', to every count below the minimum count that a rule after the
  minimum-count step suppresses, and to both parts of a total, hides the
  levels of a factor whose analysed rows are too few for levels without one
  row and no longer suppresses a count because it equals a suppressed one, as
  the [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  states.

* outcome.separation compares the objectives of the programs that give the
  coefficient bounds with the upper bounds of their multipliers, checks that
  every solution lies within the bounds of the coefficients and on the
  optimal face, and makes the finding near_threshold when a bound may lie
  further from the exact one than the parameter bound_tolerance allows,
  including when lpSolve cannot solve a program of bounds, so that two clear
  findings of the R and Python packages give the same bounds within it
  ([registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/outcome.separation.yaml)).

* design.scale_disparity sums the squared differences of each column from
  its mean exactly, so that sd_largest and sd_smallest no longer depend on
  the precision of long double on the platform and are the doubles that the
  [registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/design.scale_disparity.yaml)
  defines.

* outcome.separation limits the size of its linear programs, the values
  other than 0 in the kept columns of the design sample times 10 more than
  their number, so that a categorical predictor with many levels no longer
  makes it take minutes. Above the parameter max_size, the check is not
  available with the reason too_large. Above max_bound_programs programs of
  bounds, or when their number times the size exceeds max_bound_size, the
  finding leaves out bounds and columns_involved and keeps its verdict, and
  a program whose dual has no verified solution is solved itself only up to
  the size max_primal_size
  ([registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/outcome.separation.yaml)).

* The privacy filter of `audit()` protects two tiers of values, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  (Tiers) states. Shareable documents write effective_size of
  structure.cluster_sizes, icc of structure.within_between and
  smallest_eigenvalue of identifiability.gram_rank, and combinations of
  structure.label_incidence beside suppressed levels of its columns, and a
  T1 or T2 run that writes no value of the analysis sample, such as a
  gaussian run whose outcome.constant_clusters is suppressed, writes every
  value of the outcome-blind checks that the minimum-count, dominance,
  threshold and quantile rules allow. Beside an analysis sample that the
  document writes, they suppress more counts of the design sample, the rows
  and contributors of the table, the levels of items that count non-persons
  where the design sample loses its rows or members, the rows of a design
  sample whose level sizes would show how many analysed rows its levels
  lost, the rows and levels of the design sample whose analysed counterparts
  are hidden, the levels of a factor, or of a combination of factors, that
  is also a predictor, the parts of the analysis sample's hidden counts and
  missing_key_rows, where these would give back the rows or levels without
  an outcome. A missing_key_rows below the minimum count that the rule on
  rows without a key value does not suppress keeps the detail 'min_count',
  and with a disclosure unit, the contributors of an outcome check have the
  detail 'secondary' where the analysed rows show that a member has one
  analysed row, unless each member has one row in the design sample. The
  documentation of `audit()` states what shareable mode hides. The guarantee
  for values derived from the outcome accepts, as the privacy specification
  (Guarantees) states, that a document may show, by any of its values, that
  no level of a grouping factor and no member of the disclosure unit lost
  every outcome, or that none of two rows or more kept fewer than two
  analysed rows, but not such a count above 0, the rows or a count of levels
  that are the rows themselves.

* The privacy filter of `audit()` suppresses, with the detail 'secondary',
  the counts of columns that would give back the levels of an item that it
  hides: df of design.collinearity with gvif_per_df, kept, columns and
  empty_cells of design.rank_deficiency, dimension of
  identifiability.levels_vs_dimension, columns of
  identifiability.residual_confounding, budget of identifiability.df_budget
  and design_df of assignment.design_df, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  (Across findings, rule 6) states. The messages that render them fall back
  to texts without these values.

* The privacy filter of `audit()` matches the variables of a term to the
  items whose levels its counts of columns give back on the rows that those
  counts read, so that a grouping column that lacks a label in one row no
  longer lets the columns of a fixed term give back the levels that the
  filter hides. It hides the counts of columns of the IR when the levels of
  the table are hidden, and keeps those of a random term that '||' splits
  from a frozen factor, which has one column. The fallbacks of the messages
  budget of identifiability.df_budget and design_df of assignment.design_df
  no longer say that the levels are hidden.

* The privacy filter of `audit()` hides the analysed levels of a fixed factor
  beside design_df on rows of an assignment that hold the analysed rows or
  lie in them, suppresses a ratio whose numerator or denominator it
  suppresses whatever their class, hides the analysed levels of the
  disclosure unit with the analysed contributors and hides the analysed
  levels of an item of two members or more per level when the written rows
  or contributors would show how many lose every outcome, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  (step 5 of Steps and rule 1 of Across findings) states. `validate_results()`
  reports E7024 for a written ratio beside a suppressed count of any class.

* `pathology_zoo()` lists the fixtures of the pathology zoo, small simulated
  data sets installed with the package, or returns one of them with its data,
  the path of its installed data file, declaration, formula, the arguments of
  `audit()` for its run and its expected findings, after comparing each
  installed file with the MANIFEST.json of the package. The examples of
  `audit()`, `write_results()` and `validate_results()` audit fixtures of the
  zoo, and those of `validate_declaration()`, `read_table()`, `formula_ir()`,
  `design_samples()`, `design_matrices()` and `keyed_commitment()` read its
  fixture Z19N in place of data of their own.

* The privacy filter hides the analysed rows together with the analysed
  levels of an item none of whose levels holds two rows of the design
  sample, and with the analysed contributors when the disclosure unit is such
  an item, since each gives back the other, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  (rule 3 of Across findings) states. rank of identifiability.gram_rank is
  suppressed with smallest_eigenvalue, and the message not_identified falls
  back to a text without it.

* The statistic composite of structure.label_incidence is true only when the
  IR splits the units of one column of the pair: when the inner column of a
  pair declared nested, or either column of another pair, appears in no
  grouping factor without the other, as the
  [registry entry](https://github.com/pablobernabeu/mixedcheck/blob/main/spec/registry/checks/structure.label_incidence.yaml)
  states. crossed_split and movers_split no longer fire for a model such as
  `(1 | subject) + (1 | item) + (1 | subject:item)`, in which each column
  keeps a random effect of its own.

* The privacy filter of `audit()` suppresses as a whole a finding of an
  outcome check that fails the minimum-count rule when its rows are fewer
  than min_count or when the written values of the findings on the same rows
  would leave its contributors a single value, and a finding on a grouping
  column whose labels are crossed with another column when one of its levels
  could be left with a single member by losing fewer than min_count rows. In
  the analysis sample, it suppresses a count other than 0 that is part of the
  hidden analysed levels of an item, such as constant_levels,
  levels_without_minority or all_zero_levels, when it would show that no
  level lacks every outcome, and events and non_events of a binary outcome
  beside hidden analysed rows, beside which the verdict of the separation
  check stays written, as the
  [privacy specification](https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md)
  (Decisions, Across findings) states. It also hides the analysed rows when
  they come within min_count of the bound that a declared observation key
  places on the design sample, the product of the levels of the key's
  columns plus the rows that repeat a key value or lack one, where each
  column is a predictor, a grouping column, a column of a declared unit, a
  column with declared categories or a column declared boolean, and none
  other than a predictor or a column whose levels the declaration gives has
  a level of fewer than min_count rows, since beside levels that the
  document shows to have kept an outcome the analysed rows would show that
  no outcome is missing.

* `audit()` refuses a data frame whose column holds a value outside the
  declared categories of its field with E5012, whether or not the formula
  reads the column, as `read_table()` refuses such a value in a file with
  E5007, since the privacy filter relies on the declared categories of a
  column of the observation key to bound its levels. A predictor outside its
  categories gave an ordinary error before, and other columns were not
  checked. `validate_results()` reads the data of sidecar verification as
  `audit()` does, so such a data frame gives E5012 there too, where it gave
  E1314 before.

* URL and BugReports in DESCRIPTION give the repository under its new name,
  https://github.com/pablobernabeu/mixedcheck.
