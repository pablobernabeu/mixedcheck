# Registry

The registry describes every check that the packages run: what it reads, the statistics it computes and how, the thresholds it compares them with and where those come from, how it decides its status fields, the messages it reports, the remedies it can suggest and how it relates to other checks. Both packages read the same compiled registry, so a check computes the same statistics, reaches the same status and renders the same message in R and in Python. This document is normative together with [spec/schemas/registry-entry.schema.json](../../spec/schemas/registry-entry.schema.json) and [spec/schemas/registry.schema.json](../../spec/schemas/registry.schema.json). It relies on the conventions in [conventions.md](conventions.md), on the error codes in [errors.md](errors.md) and on the canonical IR in [ir.md](ir.md).

## Files

| Path | Content |
|---|---|
| spec/registry/checks/&lt;id&gt;.yaml | one source file for each check, named after the check's identifier |
| spec/registry/registry.yaml | the members of the compiled registry other than the entries and the version, at present the privacy parameters |
| spec/compiled/registry.json | the compiled registry, in canonical form, the only form that the packages read |
| spec/schemas/registry-entry.schema.json | the schema of one entry, in a source and in the compiled registry |
| spec/schemas/registry.schema.json | the schema of the compiled registry |
| spec/tools/compile_registry.py | the compiler, with its tests in spec/tools/test_compile_registry.py |

The sources are edited by hand, and the compiled registry is written only by the compiler. spec/vendoring.json lists the compiled registry and the two schemas, so spec/tools/vendor.py copies them byte for byte into r/inst/spec/ and python/src/mixedcheck/_spec/. The YAML sources are not vendored, so neither package needs a YAML parser to read the registry.

## The compiler

spec/tools/compile_registry.py uses the Python standard library and PyYAML built with libyaml. It runs from the repository and is never shipped. From the repository root:

```bash
python3 spec/tools/compile_registry.py           # compile and write spec/compiled/registry.json
python3 spec/tools/compile_registry.py --check   # change nothing, and exit with status 1 if it is stale
```

The compiler works in these steps.

1. It lists spec/registry/checks/. Every file there must be a YAML source whose name ends in '.yaml' (E4019).
2. It reads each source, and registry.yaml, as conventions.md (YAML authoring) describes: the bytes are checked (E1001 to E1003 and E1201), the text is pre-scanned and parsed with libyaml with every scalar read as a string (E1109, E1202 and E3001 to E3010), and each string is coerced to the type that the schema requires at its position (E3008), with the number rules of the hashable profile applied to the scalar's text (E1102 to E1104). At a position reached through then, else, anyOf or oneOf, the types come from the schemas that apply unconditionally, and from the conditional ones only when the unconditional ones state none, because the branch that applies depends on the value being coerced.
3. It checks the strings and keys of the converted value against the hashable profile, in canonical order (E1030, E1108, E1109, E1202, E1203, E1206 and E1208), as a writer would.
4. It validates each source against registry-entry.schema.json, or registry.yaml against the privacy definition of registry.schema.json, and reports every structural issue as errors.md describes.
5. For a source without structural issues, it applies the rules enforced in code on one entry (E4002, E4004, E4006 to E4016, E4020, E4021, E4023 and E4024).
6. When every source has passed, it applies the rules across entries (E4003, E4004 for links, E4005 and E4022) and reports each issue in the source of the entry concerned.
7. It assembles the compiled registry: the entries in ascending order of identifier, compared code point by code point, the privacy parameters of registry.yaml and registry_version, the value of 'registry' in spec/versions.json.
8. It validates the assembled document against registry.schema.json and the rules enforced in code, which a correct compiler always passes.
9. It writes the canonical bytes of the document (conventions.md, Serialisation) to spec/compiled/registry.json, without a final line feed.

A source reports one issue from steps 2 and 3, and otherwise the issues of step 4, or those of step 5 if step 4 found none, sorted and capped as errors.md describes. Each issue is printed on its own line as the source's path, a colon, a space, the code, a space and the rendered message, for example `spec/registry/checks/outcome.zeros.yaml: E4002 The identifier at /id must equal the name of its source file, 'outcome.zeros'.` When any issue is found, the compiler writes nothing and exits with status 1.

## The compiled registry

The compiled registry is a document in the hashable profile with three members.

- registry_version: the registry version, which readers check first (E1441).
- entries: the entries, in ascending order of identifier (E4017).
- privacy: the parameters of the privacy filter (02-decisions.md, Q5). min_count is k, the smallest number of distinct members of the disclosure unit in a displayed cell and the value below which a person count is shown as '<' followed by k. dominance gives the number of largest contributors and the share of a bin's rows that they must stay below. rounding_base is the base to which suppressed tables are rounded, and zeros_disclosive states that zeros in cross-tabulations of person attributes are disclosive. A quantile p is shown only if n times min(p, 1 - p) is at least min_count. [privacy.md](privacy.md) specifies the filter that applies them.

The file holds exactly the canonical bytes of the document, so its SHA-256 is both the hash of the file and the hash of the document. This is the registry hash of conventions.md (Hashes), which every results document records. A package loads its vendored copy as follows: it compares the SHA-256 of the file with its MANIFEST.json, reads it with the strict reader in the hashable profile and checks that registry_version lies in a supported line, which is 0.1 for this release (E1441). The package tests also check that the bytes are canonical (E4018), validate the document against registry.schema.json and apply the rules enforced in code. A function that looks up a check by identifier, such as `explain()`, reports E4001 for an identifier that no entry has.

## Versions

Each entry has an integer check version, which starts at 1 and is raised by 1 whenever the entry's statistics, thresholds, parameters, decision or assessability rules change. Versions count changes between releases: an entry edited before the first release of its registry version keeps its version, so the entries of registry 0.1.0 stay at version 1 until that registry is released. A results document records the check version of each finding, so that a finding can be matched with the rule that produced it.

The registry version follows conventions.md (Versions). Before 1.0, adding or removing a check or raising a check version raises the MINOR version, and any other change, such as clearer wording, a new remedy or a corrected source, raises the PATCH version. From 1.0, removing a check or raising a check version raises the MAJOR version and adding a check the MINOR version. Parity between the packages is defined per registry version (03-execution-plan.md, Versions).

## Entry fields

Every member of an entry is required except families and applies_when. The table summarises them, and the sections below give the rules.

| Member | Content |
|---|---|
| id | the stable identifier, `check_id` in defs.schema.json |
| version | the check version |
| title | a short title on one line |
| tier | T0, T1 or T2 |
| summary | what the check looks for and why |
| reads | the inputs the check reads |
| fitted_model | whether the check evaluates a fitted model, which decides whether its findings carry the optimisation status |
| sample | the rows the check reads: 'table', 'design' or 'analysis' (Terms) |
| families | the family classes the check applies to, every class when absent |
| scope | what one finding covers |
| applies_when | the condition under which an element of the scope yields a finding |
| availability | the conditions under which the check is not available, with their reasons |
| statistics | the quantities the check computes, by name |
| thresholds | the cut-offs that the decision uses, by name |
| parameters | fixed values of the computation, such as tolerances and size limits, by name |
| decision | the rules that decide the finding status and the message |
| assessability | the rules that lower the assessability status |
| messages | the message templates, by name |
| remedies | the remedies a report may list |
| links | the checks whose results this check uses and those that can explain its findings |
| references | the sources of the check as a whole |
| catalogue | the items of the review catalogue behind the check |

Names of statistics, thresholds, parameters, messages, message arguments, remedies and prerequisites are local names: a lower-case letter followed by up to 47 lower-case letters, digits or '_'. Statistics, thresholds, parameters and messages are objects keyed by name, so their names are unique by construction, and remedy identifiers are unique within an entry (E4006).

### Tier and inputs

The tier states how a check reads the outcome (02-decisions.md, Q3). T0 checks read no outcome, T1 checks read the outcome marginally or by grouping factor, and T2 checks relate it to the predictors. In Stream B, T0 checks always run, T1 checks run only with the outcome-access argument, and T2 checks run only in the exploratory mode.

reads lists the inputs: declaration, formula, grouping_factors (the columns of grouping factors), predictors (the other columns of the fixed part), keys (the columns of the declared observation key), other_columns (columns outside the formula that the declaration gives a role other than outcome or outcome_derived) and outcome (the outcome and its trials column). 'outcome' appears exactly when the tier is T1 or T2, and 'predictors' never appears with T1 (E4016). Restricting the rows to the analysis sample uses the missing values of every column and does not count as reading the predictors.

sample names the rows the check reads, which the support of its findings counts (documents.md, Support): 'table' for every row of the table as read, 'design' for the design sample and 'analysis' for the analysis sample. T0 checks read the table or the design sample, and T1 and T2 checks the analysis sample (E4016).

The outcome-blind checks read no outcome only if no column that they read holds it. Before any check of a Stream B run, the run therefore refuses with E6069 an IR whose predictors, grouping variables, offset columns, weights column or sample columns include the response, its trials column or a column that the declaration gives the role outcome or outcome_derived, and a declaration whose observation key, units or assignment block names such a column where it does not count as absent, since keys.duplicates, the structure checks, the assignment checks and the support read them (02-decisions.md, Q3, and declarations.md, variables). The response is an outcome whatever the declaration says. The declaration validator already refuses an outcome column in the key and the columns of a unit (E2019) and as an assigned column (E2018), and the IR leaves the response and its trials column out of its sample columns (ir.md, Samples). The checks that read further columns through declared roles, such as structure.id_scope_evidence and keys.duplicates, leave out the outcome and outcome-derived columns and the trials column themselves.

### Family classes

Several checks depend on the family of the model the user intends to fit. The family class of an audit is one of these.

| Class | Families |
|---|---|
| gaussian | Gaussian |
| bernoulli | binomial with one trial in each row |
| binomial | binomial with a trials column |
| poisson | Poisson and other families for counts |
| other | any other family, such as beta, Gamma or a cumulative-link model |

The class follows the family that the caller names, as 03-execution-plan.md (M2, the API of `audit()`) lists the names and their classes. Without one, it follows the declared measurement level of the outcome: binary gives bernoulli, binomial gives binomial, count gives poisson, ordinal gives other and continuous, bounded_score, positive_duration or no declared level give gaussian. families lists the classes for which a check yields findings, and a check without it applies to every class. The family filter comes before everything else: a check whose families do not include the class of the run yields no finding at all, not even one that is not available.

### Terms

Entries use these terms, which the IR defines in detail (ir.md).

- The design sample and the analysis sample are those of ir.md (Samples): the design sample holds the rows of the table in which neither a column that the IR reads, other than the response and its trials column, nor a sample column of the IR is missing. The analysis sample holds the rows of the design sample whose response, and trials column if any, are present, with trials above 0. T0 checks use the table or the design sample, because they do not read the outcome, and T1 and T2 checks use the analysis sample. A run whose design sample, or at T1 and T2 whose analysis sample, has no rows is refused before any check (E7007), so every check reads at least one row.
- The fixed-effects columns are the columns of the fixed part of the IR on the design or analysis sample, the intercept first, in the IR's column order. A fixed term is a term of the fixed part. Its columns are those that the IR builds for it, and its number of columns does not count those that the sequential rule drops unless an entry says so. The kept columns of a term are those that the sequential rule keeps when it is applied to the fixed-effects columns.
- An estimand counts for the model when its outcome, which it names or which is the one declared outcome when it names none (declarations.md, estimands), is the model's response, when it names no outcome and no outcome is declared, and, for a one-sided formula, always. A focal term is a fixed term that a focal estimand that counts for the model names. When no estimand counts for the model, because the declaration names none or all of them concern another outcome, every fixed term other than the intercept is focal. When estimands count but none of them is focal, no term is focal.
- A random term is a term of the random part of the IR after `/`, `:` and `||` are expanded. Its grouping factor is a column or an interaction of columns, and a grouping column is a column that appears in some grouping factor. The levels of a grouping factor are its distinct labels, or combinations of labels, in the sample, compared after NFC normalisation (conventions.md, NFC).
- Values are compared by value as the table reader compares keys (tables.md, Keys), whatever the column: strings, dates and dates and times after NFC, integers, numbers and booleans by value, with NaN equal to NaN, negative zero equal to zero and a missing value equal only to a missing value. A row pattern, the values of several columns in a row, equals another when every value does.
- The levels of a declared unit are the distinct combinations of the values of its label columns, preceded, while the unit is nested in its parent with id_scope 'within_parent', by the label columns of the parent, recursively, compared by value and ordered as ir.md (Z) orders the levels of a grouping factor. The label columns of a unit, in this sense, are those combined columns.
- The rows of an assignment are the rows of the design sample in which every label column of its unit, as the levels of a unit define them, and the assigned column are present. The three assignment checks count the units, infer the level and compute their statistics over these rows.
- The sequential rule is the rule of ir.md for dropping aliased columns, which keeps a column unless it depends on the columns kept before it. The rank of a set of columns by the sequential rule is the number of columns it keeps.
- Names of columns, terms, grouping factors and covariance parameters are those that the IR gives them, in its order, backquotes included where ir.md (Names) writes them, and messages render them so.
- Lists are ordered as follows unless an entry states another order: fixed-effects columns, terms, random terms and covariance parameters in IR order, grouping factors in the order in which they first arise in the IR, data columns and predictors in code-point order of their NFC names, units in the order of the units block, the entries of a declaration list, such as blocks, in declared order, and labels in the level order of ir.md (Z).
- The level at which a term or an assigned column varies is inferred with tolerance (02-decisions.md, Q4), pooled over the levels of a grouping factor or unit as in the evidence behind that rule (evidence/decisions/E-verify/scripts/exp2_tolerant.py, rule R2). A grouping factor or unit is constant in some columns when, over its levels with at least two rows, the rows whose pattern of those columns equals the most frequent pattern of their level number c, out of n rows in these levels, and c × 10^d ≥ m × n in integer arithmetic, with the entry's parameter agreement written as m / 10^d. A level whose patterns tie for the most frequent counts the rows of one of them. A level is exactly constant when all its rows have one pattern. An assignment without a declared level is inferred to be between_unit when its unit is constant in the assigned column over the rows of the assignment, and within_unit otherwise. The parameter agreement has one value in every entry that has it (E4022), so that the inferred level of a term or an assignment is the same in every finding. Findings that rest on an inferred level or status say so in their message.
- An entry of the declaration that `/provenance/inferred` points to counts as absent (declarations.md, provenance). So a unit whose nested_in, id_scope or membership is inferred counts as not nested in any check, and an observation key whose list or any of whose columns is inferred counts as absent, as keys.duplicates states. A unit counts as absent when it, its name, its columns or one of its columns is inferred, since its levels cannot be formed without them, and an entry of the assignment block counts as absent when it, its column or its unit is inferred or its unit counts as absent. The IR, whose hash the results document records, is built from the declaration as written, inferred entries included (ir.md, Inputs and outputs), so the event level, trials column and exposure of its response decide the response vector, and the conditions of the checks on the event level, whether or not `/provenance/inferred` lists them.

### Scopes

A check yields one finding for each element of its scope, and only for the elements for which applies_when holds. Messages can name the parts of an element. The unit of an element of the scope assignment is the declared unit of the entry of the assignment block. The pair of a grouping column with the label column of its unit's parent lets structure.label_incidence evaluate a declared nesting when the formula uses the inner column without the outer one, as `(1 | class)` does with classes declared within schools.

| Scope | One finding for | Parts |
|---|---|---|
| model | the model | none |
| grouping_factor | each grouping factor | factor |
| grouping_factor_or_model | each grouping factor, or the model as a whole when the IR has no grouping factor | factor, absent for the model |
| grouping_factor_pair | each unordered pair of grouping factors, the first before the second in code-point order of their names | first, second |
| grouping_column_pair | each unordered pair of grouping columns, and each pair of a grouping column with the column of the direct parent of its unit when that column is not a grouping column, ordered likewise, where the unit of a grouping column and its parent are units whose `columns` member lists that column alone, and a unit whose nested_in counts as absent has no parent | first, second |
| fixed_term | each fixed term other than the intercept | term |
| fixed_term_by_factor | each fixed term other than the intercept, with each grouping factor | term, factor |
| random_term | each random term | term, factor |
| assignment | each entry of the declaration's assignment block | column, unit |
| column | each column that the check reads as labels | column |

### Availability

availability lists the conditions under which a check is not available, checked in order before anything is computed. The first that holds gives the availability status, with its reason (conventions.md, Status fields). For declaration_missing, pointer names the declaration field, which becomes the status detail. The token {outcome} in a pointer stands for the name of the outcome column, escaped as RFC 6901 requires. For package_missing, packages names the packages by language, and the first missing package becomes the detail. For too_large, parameter names the parameter that holds the limit, which becomes the detail. A check that is not available yields one finding for the whole check, with no other status field. Availability is checked after the family filter (Family classes).

### Statistics and counts

Each statistic has a kind and a definition, which states exactly how it is computed.

| Kind | Value |
|---|---|
| count | a non-negative integer |
| ratio | a ratio of two counts, written as the double nearest to their quotient, and rendered and compared with thresholds exactly from the counts |
| real | a double computed in floating point |
| category | one of the values that 'values' lists |
| boolean | true or false |
| names | a list of names of columns, terms, grouping factors or parameters |
| labels | a list of labels from the data |
| reals | a list of doubles |

A definition may leave a statistic absent, for example a ratio whose denominator is 0. A finding then leaves it out (documents.md, Findings).

A ratio names the count statistics of its numerator and denominator (E4004 and E4021), so that the privacy filter and the validator can find them (documents.md, Shareable documents). Real and reals statistics are compared across languages within a tolerance, and every other kind exactly (conventions.md, Comparison across languages).

Every count and every ratio carries its count class, which the privacy filter uses (02-decisions.md, Q5, and [privacy.md](privacy.md)). person counts rows, persons or anything a person can be identified from. non_person counts parameters, degrees of freedom, columns and other structural quantities. by_unit counts levels, labels or combinations of a column, grouping factor or declared unit, and is resolved for each finding. A by_unit count names in resolved_by what it counts the levels of, its item: a part of the scope element, or a statistic of kind names that holds one column, grouping factor or unit, or a list of terms whose levels are the patterns of the terms' columns, or two such items for combinations of both. It resolves over the rows that the check reads: the rows of the assignment for the assignment checks, the rows of the design sample in which both columns of the pair are present for structure.label_incidence and structure.id_scope_evidence, and the check's sample for the other checks. A member of the disclosure unit is a level of that unit (Terms), and the members of a level are those in its rows among these in which every label column of the disclosure unit is present. The count resolves as follows:

- It is a person count when there is no disclosure unit.
- With one item, it is a person count when some level of the item in these rows has at most one member. With two items, it counts combinations of their levels, and it is a person count when some combination that occurs in one of these rows has at most one member, as it has when a level of either item has.
- Otherwise, it is a non-person count.

So the levels of a factor of pupils, of a factor of sessions with one pupil each and of a factor of sessions of which a single one holds one pupil are person counts, since a count of such levels can count pupils, and the levels of schools that each hold two or more pupils are not. A level whose rows all lack a label of the disclosure unit has no member and so makes the count a person count. A by_unit statistic that a definition leaves absent is not resolved, unless step 8 of the privacy filter writes it as suppressed, when it takes the class of the count it derives from (privacy.md, Steps). A count of degrees of freedom or of components that can give back a count of levels, such as the budget of identifiability.df_budget, has the class by_unit of those levels, so that it is suppressed when they are. The class of a ratio is that of its numerator and denominator, which have the same class (E4021). A results document records the resolved class of each count.

A statistic that is the p-quantile of n values states it in quantile, with p as a decimal string and the count statistic whose value is n, so that the filter can apply the quantile rule (documents.md, Statistics). A minimum is the quantile 0 and a maximum the quantile 1. The quantile is the value at position ceil(n × p), counted from 1 in increasing order, and the minimum at position 1. Maxima and minima over columns, terms or attributes, such as the largest standard deviation of design.scale_disparity, are not quantiles of values that persons contribute and are not marked.

suppress_with names the statistics whose suppression by the privacy filter suppresses a statistic too, so that a written value cannot give back a suppressed one through a sum, a difference or a product. part_of names the count of which a count counts a part, when the total minus its parts counts a further set that no statistic counts, such as the rows whose count is not 0 beside zeros and rows of outcome.zero_shares. The part has the count class of its total, and the filter suppresses the parts when such a remainder of a person total is below k. internal_only marks a statistic that a shareable document never writes. measures marks a count of the rows of the table, the design sample or the analysis sample, or of the levels of its item, of those with at least two rows or of those with one row, in the check's sample, or in the rows of an assignment or of a pair of columns that the check reads, which the filter compares across the findings of a document. The item of such a count is that of resolved_by, and for a count without resolved_by, such as the person count singletons of structure.cluster_sizes, the grouping factor of the finding's scope. [privacy.md](privacy.md) states how the filter applies these members. The class of a by_unit ratio is the class to which its numerator and denominator, which count the levels of the same item, resolve.

### Thresholds

A threshold compares one count, ratio or real statistic of the entry (E4011) with a value, using the comparator '<', '<=', '>' or '>='. A rule's condition that names a threshold holds when the comparison does. The value is a decimal string (conventions.md, Decimal strings and centring constants), so that every threshold has one exact value.

- A count is compared with an integer value (E4012) in integer arithmetic.
- A ratio a/b is compared exactly with a value m/10^d between 0 and 1 with at most four decimal places (E4012), by comparing a times 10^d with m times b in integer arithmetic. In R, the products are computed in doubles, which is exact while they stay below 2^53, that is, for tables of fewer than 900 billion rows.
- A real statistic s is compared with the double nearest to the value t. Its threshold has a proximity band, and no other threshold has one (E4013). The finding's threshold_proximity status is near_threshold when, for some threshold that a rule of the decision names, |s - t| is at most absolute + relative times |t|, and clear otherwise. The bands of registry 0.1.0 match the tolerance within which the two languages compare real statistics (conventions.md, Comparison across languages), so that a decision that differs between them is near_threshold in at least one. Count and ratio comparisons are exact, so they never make a finding near_threshold, and nor does an absent statistic.

Each threshold states its validation status, its rationale and its sources. A threshold is validated only with the study, language, engine and version range of its validation, and while any of its sources of kind literature or software has not been read in full, it must be descriptive (E4010). Until the local session confirms the sources (03-execution-plan.md, Local session), every threshold of registry 0.1.0 is descriptive, and every source of kind literature or software is marked as not read in full. A finding takes the validation status of its thresholds, and a finding whose decision uses no threshold is descriptive until a validation study covers it.

### Parameters

A parameter is a fixed value of the computation that is not compared with a statistic, such as a rank tolerance or the size limit of a too_large condition. Its value is a decimal string, and it has a definition and sources. Changing a parameter raises the check version.

A tolerance that the entry compares with computed real values, such as eigenvalues or the optimum of a linear program, may give proximity_factor f. The definition states which values are compared with it, and the finding's threshold_proximity is near_threshold when one of them, s, lies in the band t/f ≤ |s| ≤ t × f around the parameter's value t, as it is for a real statistic near a threshold. Such values come from linear algebra or a solver whose last digits differ between the languages, so a status that a value in the band decides may differ between them.

### Decision

The decision holds rules, each with a finding status, a condition, the thresholds the condition uses and the message to report, and 'otherwise', with the finding status and message for when no rule holds. The rules are evaluated in order, and the first whose condition holds decides. Conditions are stated in prose in terms of the statistics, the family class and the thresholds, and both packages implement them in code. Each rule lists in statistics the statistics its condition reads (E4004), which the privacy filter uses (privacy.md, Decisions). Every threshold and message that a rule names exists in the entry (E4004). A rule that names a threshold whose validation is descriptive yields at most detectable_inconsequential (E4020), because a descriptive flag graded consequential needs a predicted false-flag rate of at most .05, which only a validation study supplies (02-decisions.md, Q9). Rules without thresholds, which state exact facts of the design such as a design df of 0, may be consequential. A level or a constancy inferred with the tolerance of Terms is not such a fact, so a rule that rests on one is consequential only when a statistic shows that it also holds exactly.

### Assessability

The assessability rules are evaluated in order, and the first whose condition holds gives the status: weak, or not_assessable with its reason. For prerequisite_unmet, prerequisite names the unmet prerequisite, which becomes the status detail. When no rule holds, the status is adequate. For the deterministic checks of registry 0.1.0, adequate means that the check is exact, since nothing about their detection is left to chance.

### Messages

A message template is ASCII text in British English, written as complete sentences, with placeholders written as a local name in braces, such as {count}. The template uses every argument at least once (E4008), names no placeholder that its arguments do not define (E4007) and contains no other brace (E4009). Each argument states its source and the name it renders.

| Source | Renders |
|---|---|
| scope | a part of the finding's scope element, such as factor, after display escaping (errors.md, Rendering messages) and without quotation marks, which the template supplies |
| statistic | a statistic of the entry, as the table below describes |
| threshold | the threshold's value as written, or for a threshold on a ratio, its decimal string with the decimal point moved two places to the right, followed by '%', so that 0.15 renders as 15%, 0.125 as 12.5% and 1 as 100% |
| parameter | the parameter's value as written |

| Kind | Rendering |
|---|---|
| count | the decimal digits |
| ratio | for numerator a and denominator b, the integer q nearest to a × 100 × 10^digits / b, a tie going to the even integer, computed in integer arithmetic, then q / 10^digits written with 'digits' decimal places and followed by '%', so that 23/40 with 0 digits renders as 58% and 23/80 with 1 digit as 28.8% |
| real | for a finite double below 1e15 in absolute value, its exact binary value rounded half to even to 'digits' decimal places, as `f"{x:.{digits}f}"` writes it in Python, and for one whose absolute value is at least 1e15, its exact binary value in scientific notation, with the mantissa rounded half to even to 'digits' decimal places and followed by 'e', the sign of the exponent and at least two digits of the exponent, as `f"{x:.{digits}e}"` writes it, so that 2.5e20 with 0 digits renders as 2e+20 and 2^60 with 2 digits as 1.15e+18, or 'NaN', 'Infinity' or '-Infinity' for a non-finite value, without digits |
| category | the value with each '_' replaced by a space |
| names | each name in single quotation marks after display escaping, joined by ', ' except the last two, which are joined by ' and ', or 'none' for an empty list |
| labels | as names |

A count argument may give noun, the singular and the plural form of a noun, which the count is followed by, after a space: the singular when the rendered count is 1 and the plural otherwise. So 'levels' with noun [level, levels] renders 1 as '1 level' and 6 as '6 levels'. Templates are written so that they read correctly for every value, a count of 1 and a list of one name or of none included, using noun or a list after a colon where a verb would have to agree with a count or a list.

A message may give a fallback, a second template that renders instead of the template when a statistic that the template renders is not written, because its definition leaves it absent or the privacy filter suppressed it. A fallback states the finding without those values and renders only arguments that are always written: scope parts, thresholds, parameters and statistics of kind names or category, or counts of class non_person, that are neither internal_only nor suppressed with another statistic. A message that renders a statistic that can be unwritten, of kind ratio, real or labels, a count of class person or by_unit, or a statistic that is internal_only or suppressed with another, has a fallback (E4023). An entry ensures that every statistic that a message without a fallback renders is present whenever its decision names that message. 'digits' is given exactly for ratio and real statistics (E4014), and statistics of kind boolean or reals cannot be rendered (E4015). A real is rounded as conventions.md (Decimal strings and centring constants) rounds decimal constants: the exact binary value, half to even, with the R package's in-house routine on every platform, never with the C library. The notation is chosen by comparing the double itself with 1e15, which a double holds exactly, before any rounding, so that 999999999999999.875, the double below 1e15, renders with 0 digits as 1000000000000000. From 1e15 on, fixed notation would write more integer digits than the 15 significant digits that a double keeps, up to 309 for the largest double. A minus sign is written only before a rounded value that is not zero, so that -0.04 with 1 digit renders as 0.0. For a ratio, q is a × 100 × 10^digits integer-divided by b, plus 1 when twice the remainder exceeds b, or equals it and the quotient is odd. In R, the products are computed in doubles, which is exact while they stay below 2^53.

This rendering produces the internal message. In a shareable document, the privacy filter renders the template when every statistic it renders is written, with labels replaced by their pseudonyms, and the fallback otherwise ([privacy.md](privacy.md), Messages), so that no message holds a suppressed value or discloses one by contrast with another part of the text.

For example, the message some_change of structure.id_scope_evidence, with changing_labels 3, shared_labels 40, labels_column ['class'], context_column ['school'] and changing_attribute ['teacher_sex'], renders as: 'class' has 40 labels occurring with several levels of 'school', and the attribute 'teacher_sex' changes between those levels for 3 of them. Check these units and declare the scope of the labels. With shared_labels 1 and changing_labels 1, it renders 'has 1 label occurring' and 'for 1 of them', since no verb agrees with either count.

### Remedies

A remedy has an identifier, a description, whether applying it reads the outcome (uses_outcome), whether it changes what the focal coefficients estimate (changes_estimand) and the packages or engines it needs (software), empty when any engine can apply it. Reports list remedies, and no package applies one automatically.

### Links

links.requires lists the checks whose results the check uses, which run before it. links.explained_by lists the checks whose consequential finding can cause a finding of this check. A report groups a finding under such a root cause when the root cause's finding on the same model is consequential. Every check named exists (E4004), and the links of both kinds together form no cycle (E4005), so the checks can be run in an order that respects requires and the grouping always ends at a root.

### Sources

A source has a kind, a citation and optionally a locator, a DOI and an HTTPS URL. literature is a publication, cited in APA style, and software is the documented behaviour of a package. Both record in full_text_read whether the source has been read in full. decision is a section of the design documents or of these specifications, derivation is an argument given in the citation or in the documents it names, such as an item of the review catalogue with its verifier's correction, and convention is a value set by this project. catalogue lists the items of the review catalogue (docs/design/evidence/review-catalogue.md) behind a check.

## Rules enforced in code

The rules below complete what the two schemas express. The compiler applies them to every source, and the package tests apply them to the compiled registry.

| Code | Rule |
|---|---|
| E4001 | a check identifier looked up in the registry names an entry |
| E4002 | the identifier of a source equals its file name without '.yaml' |
| E4003 | no two entries share an identifier |
| E4004 | every check named in links, and every statistic, threshold, parameter, message and scope part that an entry names, in a rule, a message, a quantile, resolved_by, suppress_with or part_of, exists |
| E4005 | the links form no cycle, and every link on a cycle is reported |
| E4006 | the remedy identifiers of an entry are unique |
| E4007, E4008, E4009 | each message template uses exactly the placeholders that its arguments define and has no stray brace |
| E4010 | a validated threshold has no source of kind literature or software that has not been read in full |
| E4011, E4012, E4013 | a threshold applies to a count, ratio or real statistic, its value suits the statistic, and it has a proximity band exactly when the statistic is real |
| E4014, E4015 | a message argument gives digits exactly for a ratio or real statistic and never names a boolean or reals statistic |
| E4016 | the inputs and the sample of an entry match its tier |
| E4017 | the entries of the compiled registry are in ascending order of identifier |
| E4018 | the compiled registry file holds its canonical bytes |
| E4019 | spec/registry/checks/ holds only YAML sources |
| E4020 | a decision rule that names a threshold whose validation is descriptive does not grade a finding as consequential |
| E4021 | a ratio names as its numerator and denominator two count statistics of its own count class |
| E4022 | every parameter named agreement has the same value in every entry that has it |
| E4023 | a message that renders a statistic that can be absent or suppressed has a fallback, which renders none of them |
| E4024 | the n of a quantile names a count statistic, a statistic in resolved_by is of kind names, part_of names a count statistic of the same count class and noun is given only for a count statistic |

## Checks of registry 0.1.0

Registry 0.1.0 holds the audits that M2 implements (03-execution-plan.md, M2): the T0 audits, the T1 audits that read the outcome marginally or by grouping factor (02-decisions.md, Q2) and the exploratory T2 separation check.

| Check | Tier | Scope | Title |
|---|---|---|---|
| `structure.label_incidence` | T0 | grouping_column_pair | Label incidence between grouping columns |
| `structure.id_scope_evidence` | T0 | grouping_column_pair | Evidence on the scope of repeated labels |
| `structure.aliased_factors` | T0 | grouping_factor_pair | Grouping factors with identical partitions |
| `structure.cluster_sizes` | T0 | grouping_factor | Level sizes of a grouping factor |
| `structure.within_between` | T0 | fixed_term_by_factor | Within and between status of a fixed term |
| `structure.connectivity` | T0 | grouping_factor_pair | Connectivity of two crossed grouping factors |
| `identifiability.gram_rank` | T0 | model | Identifiability of the covariance parameters |
| `identifiability.df_budget` | T0 | grouping_factor | Degrees of freedom between the levels of a grouping factor |
| `identifiability.levels_vs_dimension` | T0 | random_term | Levels against the dimension of a random term |
| `identifiability.residual_confounding` | T0 | random_term | Random effects confounded with the residual |
| `design.rank_deficiency` | T0 | model | Rank deficiency of the fixed effects |
| `design.collinearity` | T0 | fixed_term | Collinearity of a fixed term |
| `design.scale_disparity` | T0 | model | Scales of the fixed-effects columns |
| `sample.raw_vs_analysis` | T0 | model | Differences between the raw data and the analysis sample |
| `labels.unicode_forms` | T0 | column | Labels that differ only in Unicode form |
| `keys.duplicates` | T0 | model | Duplicates of the declared observation key |
| `assignment.constant_within_unit` | T0 | assignment | Assignment constant within its unit |
| `assignment.unit_in_random_part` | T0 | assignment | Randomisation unit in the random part |
| `assignment.design_df` | T0 | assignment | Design degrees of freedom of an assignment |
| `outcome.constant_clusters` | T1 | grouping_factor | Levels without outcome variation |
| `outcome.minority_events` | T1 | grouping_factor_or_model | Minority events of a binary outcome |
| `outcome.boundary_shares` | T1 | model | Outcome values at the declared bounds |
| `outcome.zero_shares` | T1 | grouping_factor_or_model | Zeros of a count outcome |
| `outcome.separation` | T2 | model | Separation of a binary outcome by the fixed effects |

The T0 audits listed in 03-execution-plan.md (M2) map to these entries.

| Audit in the execution plan | Entries |
|---|---|
| label incidence for every pair of grouping factors | structure.label_incidence |
| evidence on ID scope when it is undeclared | structure.id_scope_evidence |
| aliased grouping factors and factors with one row per level | structure.aliased_factors, structure.cluster_sizes |
| within and between status with informative-group counts and predictor ICCs | structure.within_between |
| the identifiability verdict from the projected Gram matrix | identifiability.gram_rank |
| the level-specific df budget, J ≤ q and confounding with the residual | identifiability.df_budget, identifiability.levels_vs_dimension, identifiability.residual_confounding |
| rank deficiency and empty cells under the sequential aliasing rule | design.rank_deficiency |
| term-level GVIF and scale disparity | design.collinearity, design.scale_disparity |
| differences between the raw data and the analysis sample | sample.raw_vs_analysis |
| labels that differ only in Unicode form | labels.unicode_forms |
| duplicates against the declared observation key | keys.duplicates |

The three assignment checks and structure.connectivity are not in that list. They are included because the prototyped zoo fixtures Z08, Z09 and Z13 expect their findings and the M2 gate requires exact parity on the zoo, and because Q4 and Q8 of 02-decisions.md name the randomisation level, the design df and connectivity among the Stream B checks.

## References

Albert, A., & Anderson, J. A. (1984). On the existence of maximum likelihood estimates in logistic regression models. *Biometrika, 71*(1), 1–10. https://doi.org/10.1093/biomet/71.1.1

Ben-Kiki, O., Evans, C., & Ingerson, B. (2005). YAML Ain't Markup Language (YAML) version 1.1. https://yaml.org/spec/1.1/

Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation (JSON) Pointer (RFC 6901). Internet Engineering Task Force. https://doi.org/10.17487/RFC6901

Fox, J., & Monette, G. (1992). Generalized collinearity diagnostics. *Journal of the American Statistical Association, 87*(417), 178–183. https://doi.org/10.1080/01621459.1992.10475190

James, G., Witten, D., Hastie, T., & Tibshirani, R. (2013). *An introduction to statistical learning: With applications in R*. Springer. https://doi.org/10.1007/978-1-4614-7138-7

Konis, K. (2007). *Linear programming algorithms for detecting separated data in binary logistic regression models* [Doctoral thesis, University of Oxford]. Oxford University Research Archive. https://ora.ox.ac.uk/objects/uuid:8f9ee0d0-d78e-4101-9ab4-f9cbceed2a2a

Pustejovsky, J. E., & Tipton, E. (2018). Small-sample methods for cluster-robust variance estimation and hypothesis testing in fixed effects models. *Journal of Business & Economic Statistics, 36*(4), 672–683. https://doi.org/10.1080/07350015.2016.1247004

Rundgren, A., Jordan, B., & Erdtman, S. (2020). JSON Canonicalization Scheme (JCS) (RFC 8785). Internet Engineering Task Force. https://doi.org/10.17487/RFC8785

Terwee, C. B., Bot, S. D. M., de Boer, M. R., van der Windt, D. A. W. M., Knol, D. L., Dekker, J., Bouter, L. M., & de Vet, H. C. W. (2007). Quality criteria were proposed for measurement properties of health status questionnaires. *Journal of Clinical Epidemiology, 60*(1), 34–42. https://doi.org/10.1016/j.jclinepi.2006.03.012

Wright, A., Andrews, H., Hutton, B., & Dennis, G. (2022). JSON Schema: A media type for describing JSON documents (draft 2020-12). https://json-schema.org/draft/2020-12/json-schema-core
