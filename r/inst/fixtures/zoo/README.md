# The pathology zoo

The pathology zoo is a set of small simulated data sets, each with a declaration, a preliminary formula and the findings that `audit()` is expected to give for it under registry 0.1.0 (02-decisions.md, Q8, layer 1 of the test corpus). Each fixture plants one problem of a study design, such as class labels that recur across schools or a randomisation level left out of the formula, and has a matched negative, a similar design without the problem. The expected findings are derived from the generating design, by hand from the parameters of the generator or by base-R computations of the definitions in the registry that call neither package, and never from either package.

Every file here is written by the seeded generators of [sim/zoo/](../../sim/zoo/README.md), which regenerate it byte for byte, apart from the last digits of some reals of expected.json, which depend on the long double and the BLAS of the R that computes them and which the check of sim/zoo/ compares within a tolerance (sim/zoo/README.md, Regeneration). The data are simulated and hold no personal data. The files are MIT-licensed, as the repository is. spec/tools/vendor.py vendors this directory, through its entry `fixtures/zoo/` in spec/vendoring.json, into r/inst/fixtures/zoo/ and python/src/mixedcheck/_fixtures/zoo/, so that both packages install it, and `pathology_zoo()` reads the installed copy in both languages.

## Layout

| Path | Content |
|---|---|
| index.json | the list of the directories, in code-point order of their identifiers, which `pathology_zoo()` returns without an argument |
| Zn-name/ | one directory for each fixture, such as Z01-reused-class-labels/, and for each matched negative, such as Z01N-unique-class-labels/ |
| Zn-name/data.csv | the stored instance |
| Zn-name/declaration.json | a declaration of vocabulary 0.1 whose table block types every column of data.csv |
| Zn-name/formula.txt | the preliminary formula, one line followed by LF |
| Zn-name/expected.json | the run and the expected findings |

A fixture has an identifier 'Z01' to 'Z31', and its matched negative the identifier of the fixture followed by 'N'. Z03N is the matched negative of Z03 and of Z31, and Z08 that of Z09, so neither Z09 nor Z31 has a negative of its own. The zoo holds 60 directories: 31 fixtures and 29 matched negatives.

| Id | Name | Rows | Tier | Formula |
|---|---|---|---|---|
| Z01 | reused-class-labels | 240 | T0 | y ~ 1 + (1 \| school) + (1 \| class) |
| Z01N | unique-class-labels | 240 | T0 | as Z01 |
| Z02 | pupil-mobility | 120 | T0 | y ~ wave + (1 \| school/pupil) |
| Z02N | no-mobility | 120 | T0 | as Z02 |
| Z03 | crossed-teachers | 240 | T0 | y ~ 1 + (1 \| school) + (1 \| teacher) |
| Z03N | crossed-teachers-with-attributes | 240 | T0 | as Z03 |
| Z04 | aliased-grouping | 120 | T0 | y ~ 1 + (1 \| school) + (1 \| class) |
| Z04N | nested-classes | 120 | T0 | as Z04 |
| Z05 | between-subject-slope | 192 | T0 | y ~ cond + (1 + cond \| subject) + (1 \| item) |
| Z05N | within-subject-slope | 192 | T0 | as Z05 |
| Z06 | levels-below-dimension | 60 | T0 | y ~ x1 + x2 + (1 + x1 + x2 \| school) |
| Z06N | levels-above-dimension | 120 | T0 | as Z06 |
| Z07 | latin-square-one-row | 144 | T0 | y ~ cond + (1 + cond \| subject) + (1 + cond \| item) + (1 \| subject:item) |
| Z07N | latin-square-two-rows | 144 | T0 | as Z07 |
| Z08 | randomisation-level-omitted | 240 | T0 | y ~ arm + (1 \| school) |
| Z08N | randomisation-level-modelled | 240 | T0 | y ~ arm + school + (1 \| class) |
| Z09 | mixed-assignment | 240 | T0 | y ~ arm + (1 \| school) |
| Z10 | partially-nested | 64 | T0 | y ~ arm + (1 \| group) |
| Z10N | fully-nested | 64 | T0 | as Z10 |
| Z11 | singleton-families | 124 | T0 | y ~ x + (1 + x \| family) |
| Z11N | families-of-two-to-four | 115 | T0 | as Z11 |
| Z12 | dyads-negative-dependence | 120 | T1 | y ~ role + (1 \| dyad) |
| Z12N | dyads-positive-dependence | 120 | T1 | as Z12 |
| Z13 | disconnected-crossed | 160 | T0 | y ~ group + (1 \| subject) + (1 \| item) |
| Z13N | connected-crossed | 160 | T0 | as Z13 |
| Z14 | empty-cell | 72 | T0 | y ~ A * B + (1 \| subject) |
| Z14N | full-cells | 72 | T0 | as Z14 |
| Z15 | reference-level-emptied | 72 | T0 | y ~ dose + adherence + (1 \| clinic) |
| Z15N | missing-elsewhere | 72 | T0 | as Z15 |
| Z16 | eeg-average-reference | 256 | T1 | amp ~ cond + (1 \| subject) + (1 \| channel) |
| Z16N | eeg-linked-mastoids | 256 | T1 | as Z16 |
| Z17 | duplicate-keys | 205 | T0 | acc ~ cond + (1 + cond \| subject) |
| Z17N | identical-rows-without-key | 200 | T0 | as Z17 |
| Z18 | composite-id-collision | 80 | T0 | y ~ 1 + (1 \| school/class) |
| Z18N | safe-composite-ids | 80 | T0 | as Z18 |
| Z19 | sentinel-codes | 60 | T0 | y ~ group + pre + (1 \| school) |
| Z19N | true-missing-values | 60 | T0 | as Z19 |
| Z20 | unicode-id-variants | 72 | T0 | y ~ cond + (1 \| Subject) + (1 \| item) |
| Z20N | clean-ids | 72 | T0 | as Z20 |
| Z21 | few-clusters | 60 | T0 | y ~ arm + area + fsm + (1 \| school) |
| Z21N | many-clusters | 240 | T0 | as Z21 |
| Z22 | omitted-intermediate-level | 144 | T0 | y ~ 1 + (1 \| school) |
| Z22N | intermediate-level-modelled | 144 | T0 | y ~ 1 + (1 \| school) + (1 \| class) |
| Z23 | post-assignment-covariate | 72 | T0 | y ~ arm + pre + attendance + (1 \| school) |
| Z23N | baseline-covariate-only | 72 | T0 | y ~ arm + pre + (1 \| school) |
| Z24 | separation | 180 | T2 | acc ~ cond + (1 \| subject) + (1 \| item) |
| Z24N | no-separation | 180 | T2 | as Z24 |
| Z25 | timestamps-across-dst | 72 | T0 | y ~ 1 + (1 \| person) |
| Z25N | timestamps-in-utc | 72 | T0 | as Z25 |
| Z26 | lagged-outcome-short-series | 200 | T2 | y ~ y_lag_pc + (1 \| person) |
| Z26N | lagged-outcome-long-series | 200 | T2 | as Z26 |
| Z27 | informative-cluster-size | 130 | T1 | y ~ 1 + (1 \| person) |
| Z27N | uninformative-cluster-size | 130 | T1 | as Z27 |
| Z28 | ceiling-effects | 80 | T1 | score ~ wave + (1 \| child) |
| Z28N | no-ceiling | 80 | T1 | as Z28 |
| Z29 | slope-scale-mm | 120 | T0 | rt ~ dist + (1 + dist \| subject) |
| Z29N | slope-scale-m | 120 | T0 | as Z29 |
| Z30 | single-arm-sites | 120 | T0 | y ~ arm + (1 + arm \| site) |
| Z30N | both-arms-at-every-site | 120 | T0 | as Z30 |
| Z31 | reused-teacher-labels | 240 | T0 | as Z03 |

The 60 data.csv files hold 167 KB, and the whole directory 0.75 MB, which occupies 1.6 MB on a file system with blocks of 4 KB, as du measures it. regenerate.R and spec/tools/test_zoo.py hold the zoo within the limits that sim/zoo/README.md states, so that the installed R package stays well below the size at which R CMD check reports it.

## data.csv, declaration.json and formula.txt

data.csv is UTF-8 without a byte-order mark, with LF line endings except Z19, whose CR LF endings are part of its planted problem. The header names the fields of the table block in order. A field that holds ',', '"', CR or LF is quoted as RFC 4180 writes it, with each '"' doubled, and no other field is quoted. Labels are zero-padded so that code-point order is numeric order, such as 'S01' and 'P001', except where a fixture's labels are its subject (Z18 and Z20). A number is written with the digits of its column, 2 unless the fixture states otherwise, and a missing value is the empty field, except the sentinel '-99' of Z19.

declaration.json holds a declaration of vocabulary '0.1.0' in the hashable profile, written with two spaces of indentation and a final LF. Its table block types every column of data.csv, every categorical predictor declares its categories, so that its reference level is the intended one, and one unit has the role 'participant', which makes it the disclosure unit. formula.txt holds the formula and one LF.

## expected.json

expected.json is a JSON document in the data profile, read with the strict reader, whose structure spec/schemas/zoo.schema.json states. Its members are, in order:

| Member | Content |
|---|---|
| zoo | the version of the formats of the zoo, '0.1.0' |
| id, name, title | the identifier, the name and a title of at most 100 characters |
| role | 'fixture' or 'negative' |
| matched | the identifier of the matched negative of a fixture, or of the fixture of a negative. Z09 names Z08, Z31 names Z03N and Z03N names Z03 |
| negative_of | the identifiers of the fixtures whose matched negative this directory is, in code-point order, such as ['Z01'] for Z01N, ['Z03', 'Z31'] for Z03N, ['Z09'] for Z08 and [] for every other fixture |
| domain | 'education', 'crossed', 'families', 'dyads', 'eeg', 'trial-level', 'ild' or 'any', as in Q8 |
| catalogue | the review-catalogue items of Q8 |
| planted | the planted problem, or for a negative what it lacks |
| registry, vocabulary | '0.1.0' and '0.1.0' |
| generator | file, function, seed, rng (the three kinds of R's random number generator) and parameters, with numbers as JSON numbers and decimal constants as strings |
| run | outcome_access, and reason and exploratory when the tier needs them |
| rows | the number of records of data.csv |
| samples | for the table, the design sample and, at T1 and T2, the analysis sample: rows, basis, distinct and dominated, the support that the findings on that sample must have |
| findings | the expected findings in the order of documents.md (Findings), absent with issue |
| issue | code, message and, for a located code, pointer, when the run is refused, absent with findings |
| signal | the findings through which the planted problem shows under registry 0.1.0, each with check, scope, message and, where the problem shows only in counts, statistics. Empty for a negative, and for a fixture whose problem no check of registry 0.1.0 shows: Z12, Z16, Z19, Z22 and Z27, whose planned names the check that will show it, and Z18, whose findings differ from those of its negative only in the counts of structure.label_incidence that its own labels set, since joined labels must not merge |
| planned | the checks beyond registry 0.1.0 that the fixture is for, with their tier, catalogue items, the registry version or milestone that adds them and what they need |
| deferred | block and reason, for a fixture whose planned check waits for a declaration block of a later vocabulary, and for its negative, which shares its fixture's block |

The findings list every finding that the run yields, so that a finding the run adds or loses is a difference. Each finding has check, scope (an object of its parts, {} for the model), status, message (the identifier), statistics and why, a derivation of one or two sentences. A finding that is not available has no message and no statistics. In status, each field is its value as a string, or an object with value, reason and detail as the results document writes it, and the fields left out take the defaults: availability available, assessability adequate, threshold_proximity clear and validation descriptive. A finding that is not available lists availability alone.

Each statistic is an object with exactly one of these members, and count_class for a statistic whose registry entry gives the class by_unit:

| Member | Meaning |
|---|---|
| value | the exact value of a count, category, boolean or names, or of a real whose value the design fixes or a helper of sim/zoo/R/zoo.R computes from the stored values |
| ratio | two counts, numerator and denominator, whose quotient the run must write as the nearest double |
| interval | two decimal numbers, the bounds that the design guarantees for a real or for every element of reals |
| absent | true, for a statistic that the definition leaves out |

A real that the design does not fix is left out, with the reason in the derivation.

## index.json

index.json has the members zoo, registry and fixtures. fixtures lists the directories in code-point order of their identifiers, each with id, name, title, role, matched, tier, rows, domain and deferred, as `pathology_zoo()` returns them without an argument. regenerate.R writes it from the definitions of every generator file present.

## Comparison

The test suites of both packages (r/tests/testthat/test-zoo.R and python/tests/test_zoo.py) and the parity harness, kind 'zoo', run every directory through `audit()` in internal and in shareable mode, with the commitment key 00 01 02 … 1F of conventions.md and MIXEDCHECK_TIME set to 0, and compare the document with expected.json by these rules. The tests read the installed copy, or the directory that the environment variable MIXEDCHECK_ZOO_DIR names, such as fixtures/zoo/ of the source tree.

Internal mode:

1. With issue, the run must raise the package's error with that code, message and pointer. Otherwise it must return a document.
2. The findings of the run and of the expectation are matched by check and scope, and the two lists must hold the same pairs in the same order.
3. The status of each finding, with the defaults filled in, must equal the run's status exactly, every field and every reason and detail. A run that reports near_threshold is a difference, since every real of the zoo lies far from its thresholds by design.
4. The message identifier must be equal. The text is compared by the parity harness, between the two languages.
5. Every statistic of the expectation must hold in the run: a value equal exactly for counts, categories, booleans and names, and for reals within the tolerance of conventions.md (Comparison across languages) with its exceptions, a ratio as the double nearest to the quotient of its counts, an interval with the value, or every element of a reals value, between its ends inclusive, and absent with no such statistic in the run. count_class, where given, must be equal.
6. Every statistic of the run of a kind other than real and reals must be in the expectation. A real or reals statistic that the expectation leaves out is not compared.
7. The support of each available finding must equal the sample of the expectation that the check's entry names: rows, basis, distinct and dominated.

Shareable mode:

1. `validate_results()` must accept the document without an error or a warning.
2. The pairs of check and scope must be those of the expectation, since the filter suppresses findings and never removes them.
3. A finding of a check of tier T1 or T2 may be not available with the reason privacy_suppressed and the detail 'decision', and is then not compared further. A finding of a T0 check never may.
4. Every other finding has the status and the message identifier of the expectation.
5. Every statistic and support count that the document writes must meet its expectation as in internal mode. A value that the filter suppressed is not compared, and an expectation marked absent also accepts a statistic written as suppressed. count_class must be equal where given.

The R tests take outcome.separation as not available with the reason package_missing and the detail 'lpSolve' when lpSolve is not installed, as in the job of R CMD check without Suggests. The R tests run shareable mode only where CRAN does not run them, and the parity harness and CI run both modes.

When a package disagrees with an expectation, the derivation is checked again. A wrong expectation is corrected in the expected function of its generator, with its derivation, and regenerated, and a defect of a package is fixed in the specification and both packages. No expectation is changed to follow the code.
