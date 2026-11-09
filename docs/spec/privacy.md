# Privacy filter

The privacy filter turns the findings of a run into the findings of a shareable results document (02-decisions.md, Q5). Every file that leaves the package passes through it unless the caller asks for internal mode explicitly, and a shareable document meets the invariants of [documents.md](documents.md) (Shareable documents, E7020 to E7024). This document specifies its input, the order of its steps, how each rule of Q5 applies to a finding, how messages render, how labels become pseudonyms and which channels of disclosure by differencing it closes. It is normative together with documents.md and [registry.md](registry.md) (Statistics and counts, Messages), which also states how by_unit counts resolve. M2 applies it to the findings of the results document. M4 adds figures, their aggregated tables, rounding to `rounding_base` and the secondary suppression of tables, and extends this document.

## Parameters

The filter reads its parameters from the compiled registry (registry.md, The compiled registry) and the results document records them in `/privacy`. Below, k is `min_count`, the dominance rule has `dominance.contributors` contributors and the share m / 10^d written as `dominance.share`, and `zeros_disclosive` true means that a count of 0 is suppressed like any other count below k. The settings of registry 0.1.0 are k = 10, two contributors, the share 0.9 and zeros treated as disclosive, and every rule below that says '0 included' assumes zeros_disclosive true.

## Input

The filter receives the internal findings of the run in the order of documents.md (Findings), each with:

- the registry entry of its check
- its statistics with their internal values, every by_unit count already resolved to person or non_person (registry.md, Statistics and counts) and every quantile with its p and n
- its support, with the numbers behind the dominance rule: the rows of the sample and the summed rows c of the largest contributors
- the internal message, its identifier and the values of its arguments

and, for the document as a whole, the disclosure unit, the commitment key of the run and the counts of the samples that the rules across findings compare (Across findings). A finding that is not available passes through unchanged. The run resolves every by_unit count before the filter, in internal mode as well, so that every results document records the resolved class.

## Steps

The filter applies these steps in order. A value that a step suppresses becomes null with `availability` not_available, the reason privacy_suppressed and the detail given, and keeps its kind, count class and quantile. A value that an earlier step suppressed keeps its detail.

1. Internal statistics. Every statistic that its entry marks internal_only is suppressed, with the detail 'internal_only'.
2. Minimum count and dominance. A finding fails the minimum-count rule when its support has fewer than k distinct contributors, and the dominance rule when c × 10^d ≥ m × rows in integer arithmetic, with c the summed rows of its largest contributors (documents.md, Support). In a finding that fails either, every statistic of kind real, reals or labels and every count and ratio of class person is suppressed, with the detail 'min_count_rule' when the finding fails the minimum-count rule and 'dominance' otherwise (E7021). Counts and ratios of class non_person, booleans, categories and names stay. This step leaves the support to step 3.
3. Person counts below k. Every person count still written that is below k, 0 included, is suppressed with the detail 'min_count' (E7020): statistics of kind count with the class person, `support.rows` and `support.contributors.distinct`. So the detail 'min_count' marks exactly the values below k.
4. Quantiles. A statistic with quantile p of n values, n being the internal value of the count that the entry names, is suppressed with the detail 'quantile' unless n × min(m, 10^d − m) ≥ k × 10^d in integer arithmetic, where m / 10^d is p (E7022). A minimum or a maximum, the quantile 0 or 1, is therefore never written.
5. Ratios. A ratio whose numerator or denominator is a person count that is suppressed or below k is suppressed with the detail 'ratio' (E7024).
6. Relations within a finding. The rules of Within a finding below are applied, and step 5 with them, until no value changes.
7. Across findings. The rules of Across findings below are applied to the whole document, and step 6 is applied again to every finding that they change.
8. Absent statistics. A ratio that its definition leaves absent is written as suppressed, with the detail 'ratio', when its numerator or denominator is suppressed, and a quantile that its definition leaves absent is written as suppressed, with the detail 'quantile', when the count that gives its n is suppressed. A by_unit statistic written so takes the class to which that suppressed count resolves. Its absence would otherwise show that value, as the absence of constant_share of outcome.constant_clusters shows that multi_row_levels is 0. Entries define their other statistics so that their absence depends on no person count, as effective_size of structure.cluster_sizes, which is 'NaN' for a factor with one level.
9. Decisions. The rules of Decisions below may suppress a finding as a whole.
10. Pseudonyms. Every label still written is replaced by its pseudonym (Pseudonyms).
11. Writing. The quantile of a statistic keeps p and keeps n only when the count that gives n is written in the finding, so that n never shows a suppressed count. Every message is rendered again from the written values (Messages).

The filter never writes a value that the internal document does not hold, and it never changes a status other than availability.

## Within a finding

Three relations that an entry states let a written value give back a suppressed one within the finding (registry.md, Statistics and counts).

- suppress_with. A statistic whose suppress_with names a suppressed statistic is suppressed with the detail 'secondary'. It covers sums, differences and products, such as rows_kept and rows_dropped of sample.raw_vs_analysis, which add up to the written rows_raw.
- part_of. A count whose part_of names a total counts a part of it, and the total minus its parts counts the rest, such as the counts other than 0 beside zeros of outcome.zero_shares. When the total is a person count, every count that names it in part_of is suppressed with the detail 'secondary' if the total minus one of them that steps 1 to 5 left written, or minus the sum of all of them that steps 1 to 5 left written, is below k, 0 included. The rule reads these internal values whether or not a later rule suppresses the total or a part, so that its result does not depend on the order of the rules, as for the nested totals multi_row_levels, varying_levels and informative_levels of structure.within_between. Such a remainder has the class of the total, so a non-person total is shown with its parts exactly.
- Quantiles. A statistic with quantile whose n is given by a suppressed count is suppressed with the detail 'quantile', since the quantile rule cannot then be checked from the document (E7022).

## Across findings

A document can give back a suppressed count through values that different findings write, since several checks count the same rows, members or levels in different samples. These rules read the counts of the samples, not the values that other findings write, so that the shareable form of a finding depends only on its own internal values and on the samples.

The samples are the table, the design sample, the analysis sample when the run read the outcome, the rows of each assignment (registry.md, Terms) and the rows of each pair of columns that structure.label_incidence and structure.id_scope_evidence read, those of the design sample in which both columns are present. The rows of an assignment or of a pair lie in the design sample and count as the design sample when they hold all its rows. The quantities of a sample are its rows, its contributors as documents.md (Support) counts them and, for each item whose counts of levels resolve as person counts in the sample, the number of its levels, of its levels with at least two rows and of its levels with one row. The items are the grouping factors of the IR, the declared units that do not count as absent and the items by which the by_unit counts of the run's findings resolve (registry.md, Statistics and counts), so that other columns and combinations, such as the observation key and the outcome, are not items. Two items are one item when they divide the rows of the table into the same levels, as the factor school:class, the unit class declared within_parent in school and the pair of the grouping columns school and class do.

A count measures a quantity when its entry says so in measures (registry.md, Statistics and counts), `support.rows` measures the rows of the check's sample and `support.contributors.distinct` its contributors. The filter applies these rules in order, each with the detail 'secondary', to every written count that measures the quantity concerned.

1. Samples in turn. When a quantity of the table other than the levels with one row exceeds the same quantity of the design sample, or one of the design sample exceeds that of the analysis sample, by fewer than k, 0 included, the value of the larger sample is suppressed. The levels of an item in the other sample are counted whatever their class there. The levels with one row are left out because a level with two rows in the larger sample can have one row in the smaller, so that the smaller sample can have more of them. The difference counts the rows, members or levels that a missing predictor or a missing outcome removes, which sample.raw_vs_analysis suppresses when it counts rows below k, and the larger sample loses its value because the smaller one is the base of more statistics, such as the shares of the T1 checks. The rows of an assignment or of a pair that are not the design sample are compared with the design sample in the same way, and there they lose their value, since only the checks that read them count them. With the three samples nested, comparing each sample with the next smaller one also compares the table with the analysis sample.
2. Levels with one row. For each item and sample, the levels are the sum of the levels with at least two rows and the levels with one row, and each level with one row is one row, so that the levels with one row are a person count. When the levels with one row number fewer than k, 0 included, or when rule 1 suppresses the levels, every count of the levels with at least two rows in that sample is suppressed, and when rule 1 suppresses the levels with at least two rows, every count of the levels with one row is suppressed, so that no two of the three give back the third. The rule applies to items whose levels resolve as person counts only: every level of a non-person item holds at least two members and so at least two rows, as its class already shows.
3. Equal values. When rule 1 or 2 suppresses a quantity of a sample, every written count of a finding on that sample that has the same value and measures no quantity is suppressed too, unless its class, as resolved for the finding, is non_person, because it may count the same rows, members or levels. The findings of the assignment checks are on the rows of their assignment, and those of structure.label_incidence and structure.id_scope_evidence on the rows of their pair. For example, cells of identifiability.residual_confounding counts the levels of the factor of a term with an intercept alone and replicated_cells its levels with at least two rows. varying_levels of structure.within_between equals multi_row_levels when the status is within. A count that measures a quantity that stays written keeps its value, since it counts that quantity whatever value another quantity shares with it.

Rules 1 and 2 compare quantities that the run computes from the data, whether or not a finding writes the smaller one.

## Decisions

The finding status, the message identifier and the statistics of kind category and boolean are written as decided, because they state the finding itself and a report must state every finding (02-decisions.md, Q5). They can show that a suppressed count is 0 or lies in a range, such as at least 1 when keys.duplicates finds duplicates.

- For the T0 checks, which read no outcome, this is accepted. Their statuses and categories describe the structure of the design and the quality of the data, such as which grouping column is nested in which, whether a level is empty or whether a key repeats, and reports need them to interpret the model. Their names, such as the factors that lose a level in sample.raw_vs_analysis and the columns that design.rank_deficiency drops, which can locate an empty cell of predictors, are accepted on the same ground, since vocabulary 0.1 cannot mark a predictor as a person attribute.
- For the T1 and T2 checks, the counts are tabulations of the outcome, so a decision that rests on a suppressed person count is a cross-tabulation of a person attribute, which Q5 treats as disclosive even at 0. A finding of a check of tier T1 or T2 is suppressed as a whole when a statistic that a rule of its decision reads (registry.md, Decision), in the rule that held or in any rule before it, or in any rule when none held, is a count or a ratio of class person and is suppressed. Such a finding becomes not_available with the reason privacy_suppressed and the detail 'decision', keeps its scope and loses its message, statistics and support (documents.md, Findings).
- The verdict of outcome.separation states whether a linear combination of the fixed effects has events on one side only. Its columns, bounds and optimum are internal_only, so the shareable finding locates no cell. Its first rule reads the numbers of events and non-events, so a finding with fewer than k of either, 0 included, is suppressed as a whole by the rule above, and its message one_class never shows that a class is empty. When the kept columns number at most two, the intercept and one other, a verdict of quasi or complete would name a cell of one predictor in which the outcome takes one value, so the filter suppresses the finding as a whole with the detail 'decision' whatever its verdict, and the suppression shows nothing about the verdict.

## Messages

A message in a shareable document is rendered from the written values (registry.md, Messages): the template when every statistic that it renders is written, and the fallback otherwise. A fallback renders no statistic that can be suppressed, so no message holds a suppressed value, '<10' never appears in a message and a message cannot disclose a value by contrast with another part of its text. Reports, which M4 builds, show a suppressed count as '<' followed by k when its detail is 'min_count', which marks exactly the values below k, and as not shown otherwise. Labels in a message are rendered as their pseudonyms. Scope parts are names of columns, grouping factors, terms and units, which the filter keeps.

## Pseudonyms

A pseudonym replaces a label of a grouping factor or column in a shareable document (02-decisions.md, Q5), so that flagged clusters get labels that exist only in the report. Registry 0.1.0 has no statistic of kind labels, so its documents hold no pseudonyms, and these rules apply when an entry adds one.

- One pseudonym stands for one label of one grouping factor or column across the whole document, so that the same level gets the same pseudonym in every finding, and the same label of two factors gets two pseudonyms.
- The pseudonyms are '#1', '#2' and so on, numbered over the distinct pairs of a factor and a label that the document writes, in increasing order of the HMAC-SHA-256, under the commitment key of the run, of the canonical bytes of the array of the factor's name and the label (conventions.md, Keyed commitments), the digests compared as lower-case hexadecimal strings. The numbers therefore follow neither the order of the labels nor the order of the findings, and they are the same in both packages for the same key.
- The internal sidecar records each pseudonym with the factor, as the IR names it, and the label, as the data give it, in the order of the pseudonyms (documents.md, Internal sidecar).

For example, with the key 00 01 02 … 1F, the labels 'A', 'B' and 'C' of the factor 'school' have the messages `["school","A"]`, `["school","B"]` and `["school","C"]` and the digests below, so that 'C' becomes '#1', 'A' '#2' and 'B' '#3'.

| Label | HMAC-SHA-256 | Pseudonym |
|---|---|---|
| A | 40ad110dcd8fe9389548ba9f7881f4f4865ceb7d1fa9dc216b4b5dfae0a2d0bb | #2 |
| B | 6498f7515d6cdb9bb8d63611caa5b18b19f1141b4e5bcdaf96c24d1a072a101d | #3 |
| C | 0fbd7e082afe70c6380f73284aa8427b10e03607d95525f89d4f08c61ebac253 | #1 |

## Guarantees

After the steps above, a shareable document meets the invariants of documents.md: step 3 gives E7020, step 2 E7021, steps 4, 6 and 11 E7022, step 10 E7023 and step 5 E7024. The further suppressions of steps 1 and 6 to 9 close channels that the invariants alone leave open:

| Channel | Example in registry 0.1.0 | Closed by |
|---|---|---|
| a written total minus a written part that is itself a statistic | the parts `rows_kept` and `rows_dropped` of `rows_raw` in sample.raw_vs_analysis, or `events` and `non_events` of outcome.minority_events | suppress_with between the parts |
| a written total minus written parts that leave a remainder no statistic counts | the parts `at_floor` and `at_ceiling` of `rows` in outcome.boundary_shares, or `varying_levels` of `multi_row_levels` in structure.within_between | part_of |
| a product of written counts | `combinations` of structure.label_incidence beside `levels_first` and `levels_second` when the relation is crossed | suppress_with on `combinations` |
| a ratio or a real with a written denominator | `events_per_column` with `kept` of design.rank_deficiency or `effective_size` with N and J of structure.cluster_sizes | suppress_with on the real and E7024 for ratios |
| a count derived from a suppressed count of levels | `budget`, `bound`, `design_df` and `components` | the class by_unit of the levels they derive from, and suppress_with where a secondary suppression of the levels is possible |
| the n of a quantile | `quantile.n` of the level sizes of structure.cluster_sizes when the levels are suppressed | step 11 |
| a quantile next to a count | `smallest`, `largest` and `singletons` of structure.cluster_sizes | the quantile rule, and the class person of `singletons` |
| the sizes of two samples, or the levels of one item in two samples | `support.rows` of a table-sample finding beside a design-sample finding, `levels` of a factor in T0 and T1 findings and `multi_row_levels` in both | Across findings, rule 1 |
| levels against levels with two rows | `levels` of structure.cluster_sizes beside `multi_row_levels` of structure.within_between | Across findings, rule 2 |
| counts that equal a suppressed quantity | `cells` of identifiability.residual_confounding, `levels_first` of structure.label_incidence and `units` of the assignment checks | measures, and Across findings, rule 3 |
| the absence of a statistic | `constant_share` of outcome.constant_clusters, which is absent exactly when `multi_row_levels` is 0 | step 8, and definitions whose absence depends on no person count |
| the share supplied by the largest contributors | the summed rows c of the two largest contributors, which a written share and written rows would give back | `support.contributors.dominated`, a boolean in place of the share (documents.md, Support) |
| a status or message that rests on a suppressed outcome count | the message none_constant of outcome.constant_clusters, which shows that no level is constant, and one_class of outcome.separation, which shows that a class is empty | Decisions |
| values that locate a cell | the columns, bounds and optimum of outcome.separation, the last of which can equal the count of a cell, and its verdict with two kept columns | internal_only and Decisions |
| the order of pseudonyms | pseudonyms numbered by the order of labels | Pseudonyms |

A written count can still imply a suppressed quantile. When at least a quarter of the J levels of a factor have one row, `singletons` implies that `lower_quartile` of structure.cluster_sizes is 1, and `levels_without_minority` can imply that `median_minority` of outcome.minority_events is 0. The implied value is then shared by the levels that the written count counts, so it discloses nothing that the count does not, and the filter does not suppress the count. The quantile rule prevents a quantile from locating a value that fewer than k values lie on either side of.

Disclosure-attack tests in CI, which M2c writes, check these channels on the pathology zoo (03-execution-plan.md, M2).

## References

Krawczyk, H., Bellare, M., & Canetti, R. (1997). HMAC: Keyed-hashing for message authentication (RFC 2104). Internet Engineering Task Force. https://doi.org/10.17487/RFC2104
