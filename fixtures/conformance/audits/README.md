# Audit corpus

These cases test `audit()`, the entry point of Stream B that M2 implements in both packages (03-execution-plan.md, M2): the 24 checks of registry 0.1.0 ([docs/spec/registry.md](../../../docs/spec/registry.md) and the sources in [spec/registry/checks/](../../../spec/registry/checks/)), the refusals of a run and the privacy filter ([docs/spec/privacy.md](../../../docs/spec/privacy.md)). Each case gives a small table with a formula and its other inputs, and expects either the findings of the checks the case is about or the one issue that refuses the run.

| File | Cases | Covers |
|---|---|---|
| assignment.json | 22 | the three assignment checks: declared and inferred levels, mixed units, coverage by a random intercept, coarser grouping factors, design degrees of freedom with and without blocks, units nested within their parents, the rows of an assignment and a missing declaration or assignment block |
| design.json | 27 | design.rank_deficiency, design.collinearity and design.scale_disparity: dropped columns, empty cells, estimands, GVIF against its thresholds and the scales of the fixed-effects columns |
| identifiability.json | 33 | the four identifiability checks: the Gram matrix of the covariance parameters, degrees of freedom between levels, levels against the dimension of a random term and random effects confounded with the residual |
| keys.json | 12 | keys.duplicates: duplicates and missing values of the key, the columns compared, availability and the refusals of a key that the run cannot read |
| labels.json | 7 | labels.unicode_forms: the columns that hold labels and the spellings that NFC merges |
| outcome.json | 36 | the T1 checks and outcome.separation: decisions, messages, family filters, availability, findings for the model as a whole and the refusals E6069, E6078, E7007, E7008 and E7009 |
| privacy.json | 58 | the privacy filter in both modes: each step, counts of levels resolved both ways, parts of a total, the rules across findings and on decisions, the fallback of every message that a case can reach and the channels of differencing that the filter closes |
| sample.json | 11 | sample.raw_vs_analysis: complete tables, rows dropped through predictors, weights and sample columns, factors that lose levels, new singletons and emptied reference levels |
| structure.json | 55 | the six structure checks: label incidence, evidence on the scope of repeated labels, aliased factors, level sizes, within and between status and connectivity |

The corpus has one file for each prefix of the check identifiers, structure.json, identifiability.json, design.json, sample.json, labels.json, keys.json, assignment.json and outcome.json, each holding the cases of the checks with that prefix, and privacy.json for the privacy filter. Every file is listed in spec/vendoring.json, so that the packages' tests read it from their copies of the corpora, and in parity/corpora.json with the kind 'audit'.

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile, since missing values in the data are null (conventions.md, Profiles). The files are ASCII, with every other character written as an escape. Each case has these members:

- `id` and `description`. The ID is 'audits-', the name of the file without '.json', '-' and three digits, such as audits-structure-001, unique across the corpora. The description says which rule, message, condition or degenerate case the case is about.
- `checks`: the identifiers of the checks the case is about, each an entry of the registry. In a file other than privacy.json, each starts with the file's prefix. The test compares the findings of these checks only, and ignores those of the other checks that the run yields.
- `data`: the table, as in the formula corpus ([formulas/](../formulas/README.md)): each member is a column, keyed by its name, and its array holds one value per row, a number, a string, a boolean or null for a missing value. In a column with a number, the strings 'NaN', 'Infinity' and '-Infinity' stand for the special values. Every column has as many values as the others, at most 40, so that a reader can check the case by hand, and at least one value that is not null. A test builds a data frame from it, with numeric, character and logical columns and NA or None for null, and passes it to `audit()`.
- `formula`: the formula string.
- `declaration`: a valid declaration of vocabulary 0.1, when the case has one.
- `family`: the family name given to `audit()`, when the case names one, which is one that it accepts unless the case expects E7008.
- `coding`, `weights` and `sample_columns`: the arguments of `formula_ir()`, when the case sets them.
- `outcome_access`: 'T0', 'T1' or 'T2', 'T0' when absent. `reason`, a text, is present exactly when it is 'T1' or 'T2', and `exploratory` is true when it is 'T2'.
- `privacy`: 'internal' or 'shareable', 'internal' when absent. A case of privacy.json gives both outcomes, as `expected` describes.
- `exact`: the statistics of kind real, as 'check:statistic', that the test compares bit for bit because their definitions fix every operation, when there are any.
- `expected`: either `findings`, with `shareable` in privacy.json, or `issue`.

Every test calls `audit()` with the commitment key 00 01 02 … 1F of conventions.md (Keyed commitments, Example) and with the environment variable MIXEDCHECK_TIME set to 0, so that every value of a document is reproducible (03-execution-plan.md, M2).

`findings` lists the findings of the checks of `checks` in the order of documents.md (Findings), each written as a results document writes a finding: `check`, `check_version`, `tier`, `scope`, `status` with every status field that the finding has, `message` with its `id` and its `text`, `statistics` with every statistic that the finding writes, each with its `kind`, `value`, `count_class` for counts and ratios, `quantile` for order statistics, with n only when the count that gives it is written, and `availability` for a value that is not written, and `support`. In the findings of a run in internal mode, every value is written and every by_unit count shows the class it resolves to. A finding that is not available has only `check`, `check_version`, `tier`, `scope` and `status`. A check that yields no finding for the case, because of its families, its tier or applies_when, contributes nothing to the list, so an empty list says that no check of `checks` yields a finding.

`shareable`, in privacy.json, lists the same findings after the privacy filter, for the same inputs with `privacy` 'shareable': suppressed values as null with `availability` and the detail of the step that suppressed them, findings suppressed as a whole, supports and the messages rendered from the written values, templates or fallbacks. The test runs the case twice, once in each mode, and compares `findings` with the internal run and `shareable` with the shareable run. Some cases of privacy.json repeat the inputs and internal findings of a case of another file, which their description names, to show the fallbacks of its messages.

Two parts of the filter cannot be reached within 40 rows: the dominance rule, which with 10 contributors needs about 80 rows, and a written quantile, which needs at least 20 levels and level sizes of at least min_count. results/shareable.json covers both through E7021 and E7022. The message no_solution of outcome.separation needs a solver that fails, which the unit tests of the packages simulate, and the fallbacks of outcome.boundary_shares and outcome.constant_clusters render only statistics that their decision reads, so that a suppression suppresses the finding as a whole. These are the only messages and fallbacks that no case expects. The tolerance of the parameter agreement cannot be tested either, since c × 100 ≥ 99 × n holds below 100 rows only when c equals n. `write_results()` and its code E7010 are covered by the unit tests of the packages.

`issue` holds the `code` and the rendered `message` of the error that refuses the run, such as E5011, E6069, E6078, E7007, E7008 or E7009, with `pointer` for a code located by JSON Pointer.

## Comparison

The test compares the findings with the expected list member by member.

- Identifiers, versions, tiers, scopes, statuses, message identifiers, availability, count classes, quantiles and the values of statistics of kind count, ratio, boolean, category, names and labels match exactly. A ratio is the double nearest to the quotient of its two counts, which both languages compute alike.
- The values of statistics of kind real and reals match within the tolerance of conventions.md (Comparison across languages), with its exceptions for design.collinearity and outcome.separation, and bit for bit for the statistics that `exact` lists. The expected value is the double that the definition gives, written as the canonical serialiser writes it.
- A message text matches when it is identical, or when it differs only in the renderings of real statistics whose values match by the rule above and whose two renderings are the neighbouring roundings at the statistic's digits on either side of one rounding boundary.
- A finding whose expected threshold_proximity is near_threshold may differ in its finding status, its message and the statistics its decision chose between, as conventions.md allows. Cases keep real statistics away from thresholds unless they test the proximity band.
- The `dominated` member of a support matches exactly.

## Provenance

The cases are written for this project from the specifications and are MIT-licensed. Each expected value is derived from registry.md, the registry sources, ir.md, conventions.md, documents.md and privacy.md by hand or by scratch code written from the specifications alone, kept outside the repository and deleted, never from either package. [spec/tools/test_audit_corpus.py](../../../spec/tools/test_audit_corpus.py) checks the format of every case that exists: its members and inputs, its declaration against the declaration schema, its checks against the compiled registry, each expected finding against the schema of a finding and the registry entry of its check, the order of the findings, the invariants of a shareable document on `shareable`, every issue against spec/errors.json, that every file is in this table and in spec/vendoring.json and parity/corpora.json, and, once every file exists, that every check, every message and every fallback apart from the exceptions above is expected. The tests of both packages and the parity harness then run every case.
