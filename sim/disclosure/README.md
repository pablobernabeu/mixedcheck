# Disclosure-attack tests

These tests attack the privacy filter of shareable mode ([privacy.md](../../docs/spec/privacy.md)) as an adversary would, on documents that the R package writes, and fail when a document gives back a value that privacy.md undertakes to hide. They run in CI on every pull request that touches the R package, which holds the filter, the writer of findings, the IR hash and the validator, the specification, the privacy cases of the audit corpus that the regression attacks read or these tests (`.github/workflows/disclosure.yaml`), and never inside `R CMD check`. Nothing here ships with either package.

## Threat model

The adversary of privacy.md holds one shareable results document. They know the package, the registry and the specifications, so they know every definition, rule and detail of suppression, and they can test candidate values against an unkeyed hash, such as the IR hash. They cannot invert a keyed commitment. They do not hold the declaration, the data or a second document of the same data, against which privacy.md (Guarantees) makes no promise. A value is disclosed when the document determines it: when every table that would give the same document gives the value, or when the relations that the specification fixes leave it one value.

privacy.md accepts some channels. The harness separates them from leaks rather than ignoring them:

- the statuses, messages, categories, booleans and names of the T0 checks, the availability of a finding that is not available, the verdict of outcome.separation and its suppression as a whole (Decisions)
- the class person of a by_unit count and the boolean `dominated` (Guarantees)
- a quantile implied by a written count of the levels that hold its value, and a quantile shared by k or more of its n values (Guarantees)
- a count derived through suppress_with from written statistics, a hidden count that measures a quantity that another count writes, and a count of k or more that the written values give back without the details or any other hidden count, such as rows_dropped as rows_raw minus the written rows of the design sample, which give back nothing that the written values do not

The channels that privacy.md (Guarantees) records as not closed are listed in `dh_known_channels()` (`R/attacks.R`). Their leaks are reported apart and do not fail the run, and a listed channel that the attacks no longer find is an error of the harness, so that the list shrinks as the filter closes them.

## The attacks

(a) Inference by consistency search (`R/consistency.R`, `R/families.R`). A family is a template of small tables whose free parameters are counts: cell sizes, events and missing values. The search audits every table of the family in shareable mode, reduces each document to what the adversary can use (`dh_reduce()`: the time of creation and the digests of keyed commitments are dropped, unkeyed hashes kept) and groups the tables whose reduced documents are identical. For each value that the internal findings hold and the shareable document hides, and for each parameter that counts persons and is below k, it reports a determination when the value is the same across a group while the family lets it vary among the tables that hide it with the same detail.

A strict reduction also removes the channels that privacy.md accepts (`dh_strict_finding()`), and the by_unit counts written below k because they resolve as non_person, which would show the class. A determination that the strict reduction keeps is a leak, and one that only the full reduction makes is reported as accepted.

The 25 families hold one grouping factor with levels of one to four rows, crossed and nested factors, classes declared within_parent, a disclosure unit and none, assignments with and without blocks, a predictor of two values and binary factors, bernoulli, binomial, Poisson, gaussian and bounded outcomes, missing outcomes, predictors, keys and assigned columns, up to k + 1 missing values where one sample must exceed another by k or more in one quantity and by fewer in another, a level of one row that loses its only row, duplicated keys, labels with two Unicode spellings, T0, T1 and T2 runs and exploratory mode. The runs use k = 3, which makes tables of 6 to 40 rows meaningful, and four-sizes k = 4: the rules of privacy.md are written for any k, so the harness sets min_count in the cached registry, which the filter, the document's `/privacy` and the validator all read, and the package needs no argument for it. The registry's k of 10 is used by attacks (c) and (v).

Coverage, from 25 sampled tables of each family whose (a) determinations gate the run (gate TRUE in `R/families.R`), with the checks that only families of gate FALSE probe:

| Check | Gated families that probe it | Hidden members exercised |
|---|---|---|
| assignment.constant_within_unit, assignment.design_df, assignment.unit_in_random_part | assign, blocks | units, mixed_units, design_df and the support |
| design.collinearity | none | none, since the families that keep reals read no factor with a GVIF |
| design.rank_deficiency | sizes, sizes-unit | the support |
| design.scale_disparity | sizes, sizes-unit | the reals and the support |
| identifiability.df_budget, identifiability.levels_vs_dimension, identifiability.residual_confounding | sizes, sizes-unit, crossed, crossed-unit, nested | levels, budget, bound, informative_levels, cells, replicated_cells and the support |
| identifiability.gram_rank | sizes, sizes-unit, eigen | smallest_eigenvalue and the support |
| keys.duplicates | keys | every count and the support |
| labels.unicode_forms | sizes, sizes-unit | labels and spellings of 0 and the support, with merged spellings only in unicode |
| outcome.boundary_shares | bounds | the finding suppressed as a whole only |
| outcome.constant_clusters | constant, crossed, crossed-unit, nested | the finding suppressed as a whole only |
| outcome.minority_events | none | probed by minority only |
| outcome.separation | none | probed by binomial, factor-separation, two-factor-separation and separation-missing only |
| outcome.zero_shares | crossed, crossed-unit | zeros, all_zero_levels, levels, rows, zero_share and the support |
| sample.raw_vs_analysis | sizes, sizes-unit, keys | rows_raw, rows_kept, rows_dropped and the support |
| structure.aliased_factors | crossed, crossed-unit, nested | every count and the support |
| structure.cluster_sizes | sizes, sizes-unit, crossed, crossed-unit, nested, eigen | every statistic and the support, with sizes of three or more values only in four-sizes |
| structure.connectivity | crossed, crossed-unit | components and the support |
| structure.id_scope_evidence | labels | shared_labels, changing_labels and changing_share |
| structure.label_incidence | crossed, crossed-unit, labels, nested | every count and the support |
| structure.within_between | sizes, sizes-unit, crossed, crossed-unit, nested | every count, within_share, icc and the support |

No gated family holds weights, offsets or exposure, random slopes, interactions, an emptied reference level, three grouping factors, dominance, declared estimands or inferred provenance.

A determination within a family is meaningful only when the family lets the value vary for reasons that the document does not show. Four things ensure this:

- Each family varies independently the counts on which the values that it probes depend (`probe`), including levels of one, two and three rows, rows outside the design sample and outcomes missing in part of a level and in whole levels, since a family in which every level has two rows tells the adversary what no document shows. A family probes only the checks whose counts it varies. Reals that depend on predictor values are masked unless every predictor of the family takes two values whose counts are parameters, since the adversary does not know the values of a covariate.
- Only tables strictly inside every range that is a limit of the family, rather than a natural bound such as 0, are reported.
- A family whose determinations have not all been traced to a leak or to its fixed structure, such as every subject having two rows, has gate FALSE: its determinations of attack (a) are reported as candidates and do not fail the run. The gate applies to attack (a) only, and a leak of attack (b), which reads one document and no family, fails the run in every family.
- When the search finds a leak, it runs the family again widened by one value beyond every such limit (`dh_search()`, `--widen`). The widened tables can join a group and remove a determination that only the limits of the family made. A determination that survives is reported with its reproducer.

The search cannot find a leak in a structure that no family holds, and a narrow family can still report a determination that a richer one would remove: each reported leak should be confirmed by the interval audit or by hand, as the leaks listed below were.

(b) Interval audit of linear relations (`R/intervals.R`). From one shareable document alone, the adversary collects the linear relations that the specification fixes: parts of a total, sums and differences that definitions state, the quantities that several counts measure in one sample, the nesting of the table, the design sample, the analysis sample and the rows of assignments and pairs, the levels with one and with two or more rows, the contributors of the basis grouping_factors as the fewest levels, the quantiles of level sizes with their position, the levels of combinations against those of each item, the finer levels of structure.aliased_factors against its coarser and informative levels, the contributors of the basis rows as the rows, the labels in several combinations of structure.label_incidence, the numerators and denominators of written ratios and the bounds that a detail implies: 'min_count' a value below k, and 'secondary' on `support.contributors.distinct` a value of k or more, as validation reads it. 'secondary' on any other count shows nothing about the side of k, since the rules after step 3 give it in place of 'min_count'. In the full model it adds the conditions of the decision rule that a status shows, for the conditions of the form 'X is above 0.' and 'X is 0.', and the labels in several combinations, which bound a part to 0 only where the relation shows nesting. Linear programs solved with lpSolve, with binary variables where a relation chooses between alternatives, then give the smallest and largest value of every hidden count, rounded inwards to integers, which keeps every integer solution. A count with one value is a leak unless an accepted channel explains it, and a count shown below k is reported as a bound, since it gives back no more than the detail 'min_count'. The audit checks itself: an interval that excludes the internal value is an error of the harness. It runs on every distinct document of the families. It leaves out reals, relations that are not linear, such as a product of two hidden counts, the conditions of decision rules of other forms, the bounds that a rule's firing implies, such as a hidden quantity of a losing sample within k of the written one, and the link between the contributors of the basis disclosure_unit and the levels of the unit.

(c) Regression attacks (`R/regressions.R`). One attack for each value that the four adversarial reviews of M2b-2 found a shareable document to give back, on the reproducer of the review at k = 10. Most attacks make the computation that the adversary would make on the document. Those of written values that alone give back a count, such as the icc, the reals over the design sample, a minimum or a maximum and the verdicts of outcome.separation, test that the value is not written, so that they would not detect a fix that hid it while leaving the count recoverable in another way. R4-events-per-column guards a channel that privacy.md has closed since the first build, the minority events as events_per_column times the kept columns.

(v) Validation attacks (`R/validator.R`). Shareable documents changed to give back a hidden value, as an implementation that broke a rule would write them, which stages 4 and 5 of `validate_results()` must refuse with E7020, E7021, E7022, E7024, E7025, E7045 or E7046. E7023 cannot be attacked with registry 0.1.0, which has no statistic of kind labels, so that a forged label fails E7042 first. Every shareable document of the families must also pass stages 4 and 5.

(d) Mutation testing (`mutate.R`, `R/mutants.R`). Each mutant disables one rule of the filter, of the shareable IR hash or of the validator by replacing a function of the loaded namespace in the harness, never in the package, and the attacks run again. An attack detects a mutant when it reports a leak that it does not report without it.

(e) Historical check (`historical.sh`). The attacks run against the package as it was at an earlier commit, read with `git archive` into a scratch directory, to measure which leaks of the reviews the harness finds.

## The Python package

M2b-3 carries these attacks over to the filter of the Python package by parity rather than by porting the harness, since attacks (a) and (c) read the internal findings through the R namespace and every attack sets k in the cached registry of the R package. The harness writes every distinct table of its families, with its formula, its arguments and its k, and the documents of attack (v) as a parity corpus that it generates rather than commits. The parity harness runs the tables in both languages and requires their shareable documents to agree by the rules of conventions.md (Comparison across languages), and requires both validators to refuse each document of attack (v) with the same codes. A Python document that agrees with the R document gives back no more than the R document, so the determinations that the attacks make on the R documents cover it, and a leak of the Python filter shows as a mismatch. The Python package gives its tests a way to set min_count in its cached registry, as the harness does in R.

## Running

R with mixedcheck and its Imports installed, lpSolve, jsonlite and parallel:

```sh
R CMD INSTALL r
Rscript sim/disclosure/run.R --cores 4
Rscript sim/disclosure/run.R --attacks c,v                  # regressions and validation only
Rscript sim/disclosure/run.R --families sizes,keys --widen 0
Rscript sim/disclosure/mutate.R --cores 4 --mutants step-3,across-1 --baseline base.rds --out mutants.rds
sh sim/disclosure/historical.sh f704af7 /dev/shm/history-f704af7 --cores 4
```

`run.R` prints one line for each leak with a reproducer, the family and its parameters or the attack, and exits with status 1 when there is a leak or an error of the harness. Every run is deterministic: the tables are fixed by their parameters, the reproducers that draw random numbers set their seeds, the commitment key is fixed and MIXEDCHECK_TIME is 0.

## Results

The CI run audits 5,814 tables of the 25 families and runs the regression and validation attacks in a few seconds. On the machine of M2b-2 it took 559 s on three cores, with 26 minutes of processor time, so that about 14 minutes are to be expected on the two cores of GitHub's runners for private repositories, within the job's limit of 45 minutes. On the package of M2b-2, the regression attacks recover nothing and the validation attacks are all refused, and the consistency search and the interval audit report no leak but those of the channel quantile-pinned-by-rows, which privacy.md records as not closed, in some 15 tables of four-sizes, a number that depends on which table of a document a worker audits. The families of gate FALSE report 671 candidates.

The first version of these tests found three channels, each confirmed by hand at k = 10, and the fourth review of the filter found three more:

- With `rows` N and `levels` J of structure.cluster_sizes written and N below 2J, at least 2J − N levels have one row, so the document showed that `smallest` is 1, `lower_quartile` too when 2J − N reaches ceil(J/4), and `singletons` when 2J − N reaches k − 1. Twelve subjects, three with one row and nine with two, give N = 21 and J = 12. Rule 3 of Across findings now suppresses the levels.
- Two counts that suppress each other and are both below k, beside a written count that is their sum, were each at least the sum minus k − 1, and were given back when the sum is 2k − 2: `identical_keys` and `conflicting_keys` of keys.duplicates beside `duplicated_keys`, or `events` and `non_events` of outcome.minority_events beside `support.rows`, with 9 and 9 of 18. Both parts now have the detail 'secondary'.
- A person count that a rule after step 3 suppresses kept the detail 'min_count' when it was below k, so the detail 'secondary' showed that it is at least k: ten subjects of two rows gave `levels` 10 written and `multi_row_levels`, `varying_levels` and `informative_levels` with the detail 'secondary', so all were 10 and `singletons` 0. Such a count now has the detail 'secondary', and the levels with one row and with two or more are suppressed together, which also closes the levels with two rows below k that the levels minus written singletons gave back.
- `effective_size` with N and J gave back the sum of the squared level sizes, so 39 subjects of 10 rows and one of 9 gave the smallest size 9, held by one level. It is internal_only.
- The rule on equal values suppressed a count only because it equalled a suppressed quantity, so its suppression showed that value: a median of item sizes suppressed between written quartiles one apart gave back the subjects with two rows or more, and the budget of identifiability.df_budget, which the levels and the consuming terms give, the levels with one row. The rule is withdrawn.

The first mutation run of M2b-2 used the families sizes, assign, crossed-unit, labels, keys, two-valued, binomial and two-factor-separation, and the run for the rules of the fourth review and the mutants it changed used sizes, sizes-wide, four-sizes, keys, labels, aliased and blocks. Each ran the families of a mutant only until attack (a) or (b) detected it, so a missing (a) or (b) below can mean that another attack stopped the search first. Of the 55 mutants, 47 are detected:

| Rule disabled | Detected by |
|---|---|
| Steps 1, internal_only | b, c |
| Steps 2, both rules and the minimum-count rule alone | v (E7021 on documents of the families) |
| Steps 3, person counts below k | a, v |
| Steps 3, the support below k | v (E7020) |
| Steps 3, quantiles left to step 4 | b, c |
| Steps 4 | a, c |
| Steps 5 | b, v (E7024) |
| Within a finding: suppress_with and its detail 'secondary' | a, c |
| Within a finding: part_of | c |
| Within a finding: 'secondary' on both parts of a total | b, c |
| Within a finding: 'secondary' on a part of a person total below k | a |
| Within a finding: the n of quantiles and its detail 'quantile' | c (R3-quantile-detail) |
| Across findings: every rule, rule 1 and its levels | a, b, c |
| Rule 1 on rows, the counts that measure a quantity, the support | a, b |
| Rule 1 on contributors | a |
| Rule 1 on the class of the larger sample, on crossed combinations, the basis grouping_factors, rules 4 and 5 | c |
| Rule 2 | b, c |
| Rule 2 when the levels with two rows are below k | b |
| Rule 3 | b, c |
| Across findings: 'secondary' in place of 'min_count' | a, b, c |
| Decisions, every rule and those on T1 and T2 counts | b, c |
| outcome.separation, every rule, rows of equal values, the analysis sample, binomial classes | c |
| Steps 11, messages from written values | a |
| Steps 11, the n of a quantile beside its count | a, v (E7025) |
| The IR hash without centring constants | c |
| Validation rules E7020, E7021, E7022, E7024, E7025, E7045 and E7046 | v |

Eight mutants are not detected:

- The dominance rule alone is untested: no family has a level that holds most rows, and r/tests/testthat/test-privacy.R covers it with two levels that hold 100 of 110 rows. A family with dominant levels would test it.
- Step 8, absent statistics, is untested: the families of the mutation run never make a ratio absent beside a suppressed part of value 0, as outcome.constant_clusters does with no level of two rows.
- The rule on at most two kept columns of outcome.separation overlaps the rule on one variable, which applies to every model of one predictor term, but not for a single column that reads two variables, such as y ~ x:z, which no family or reproducer has, so it is untested rather than redundant.
- The rule on one variable overlaps the rule on rows of equal values for a factor, whose levels repeat their values, which is why R2-separation-one-factor does not detect it, but not for a polynomial of one covariate with distinct values, such as y ~ x + I(x^2), so it is untested rather than redundant.
- E7023 cannot be tested with registry 0.1.0, which has no statistic of kind labels, and is redundant there.
- Rule 1 on a quantity of the losing sample below k and rule 4 on missing_key_rows below k change only the detail of a count below k, which an adversary could read only through the bounds that the firing of a rule implies, and attack (b) leaves those out. r/tests/testthat/test-privacy.R covers the first with the units of an assignment, and audits-privacy-003 and 004 the second.
- Rule 3 with the written quartiles needs 4k levels for a written lower quartile, more than the families hold. test-privacy.R covers it with 40 levels.

The historical check at f704af7, dfe40a6 and 35dc778, the commits before the fixes of the three reviews, finds every channel of the reviews with the regression attacks, as it must. Attacks (a) and (b) alone, which were written without the reviews in view, find at the commit before its fix the nested assignments, the contributors of the basis grouping_factors, minima and maxima, the detail of a quartile of three levels, the eigenvalue, the derived detail 'min_count', the school of one pupil without the arm, the binomial classes of rows and the reals over the design sample, the last three as candidates of families that do not gate the run, and miss the crossed combinations, the icc, the labels that occur once, the software of a document, the kept columns of outcome.separation, the rows without a key value, the verdicts of outcome.separation and the IR hash, whose structures or values no family holds or which are reals or hashes that the search does not take as targets. At 05bf32f, the commit before the fixes of the fourth review, the attacks R4 recover the values of that review, apart from R4-events-per-column, which guards a channel closed since the first build.
