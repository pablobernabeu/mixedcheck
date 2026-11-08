# Results, plans and estimates

This document specifies three documents and a companion file: the results document with its access log, the internal sidecar that accompanies a written results document, the Stream B plan and the bring-your-own estimates of the fitted-model contract. It sets out their members and their meaning, the rules that the validators enforce in code, the order in which every check runs and the code that each failure reports. It is normative together with [spec/schemas/results.schema.json](../../spec/schemas/results.schema.json), [spec/schemas/plan.schema.json](../../spec/schemas/plan.schema.json) and [spec/schemas/estimates.schema.json](../../spec/schemas/estimates.schema.json), and where a schema and this document disagree, this document prevails and the schema is corrected. [conventions.md](conventions.md) defines the reader, the two profiles, hashing, keyed commitments and the status fields, [errors.md](errors.md) the error codes, the structural checks and the order of reported issues, and [registry.md](registry.md) the checks whose findings a results document holds.

## Scope

| Document | Schema | Profile | Written in | Validator built in |
|---|---|---|---|---|
| results document, with its access log | results.schema.json | data | M2 (Stream B) and M5 (Stream A) | M2 |
| internal sidecar | results.schema.json, `$defs/sidecar` | data | M2 | M2 |
| plan, version 0.1 | plan.schema.json | hashable | M3 | M3 |
| bring-your-own estimates, contract version 0.1 | estimates.schema.json | data | by the user's own code, read in M5 | M5 |

M1 fixes the formats so that the milestones that write and read them build on one definition. The results document and the sidecar are complete for the Stream B audits of M2. The plan and the estimates are drafts at version 0.1 that M3 and M5 refine, since the ladder generator and the adapters do not yet exist. Any change to them raises their MINOR version (conventions.md, Versions).

## Common rules

### Reading and versions

A document is read with the strict reader in its profile (conventions.md, Strict reader), which reports at most one issue and stops there. Each document has a version member, checked before anything else.

| Document | Version member | Supported line |
|---|---|---|
| results document | `results_version` | 0.1.x |
| internal sidecar | `sidecar_version` | 0.1.x |
| plan | `plan_version` | 0.1.x |
| bring-your-own estimates | `contract_version` | 0.1.x |

If the value is an object whose version member is a string, the string must match `^0\.1\.(0|[1-9][0-9]*)$` and have at most 32 characters. Otherwise, E1441 is reported at the version member alone, with the supported version '0.1.x', and nothing else is checked. A missing or non-string version member is left to the structural check.

Documents also record the versions of the package and the shared specification that wrote them, in the member `versions` (`versions` in defs.schema.json): the package version as the package reports it, and the registry, schema and canonicaliser versions of spec/versions.json (03-execution-plan.md, Versions).

### Validation

After the version, a validator checks the value against the document's schema as errors.md (Structural validation) describes, together with the rules that defs.schema.json states in descriptions, such as the day of every `utc_timestamp` (E1406) and characters outside the Basic Multilingual Plane in a `column_name` (E1207). The schema's reference to `hashable_value` or `data_value` is not checked again, because the reader or writer has enforced the profile. When the structure is valid, the validator applies the rules enforced in code, which the sections below list for each document. The issues of each step are sorted by JSON Pointer, then by code and then by message, and capped at 100 with W1490 (errors.md, Reporting rules).

Locations are JSON Pointers into the document as read (RFC 6901). Names of columns, grouping factors, terms and units are compared after NFC normalisation (conventions.md, NFC), and other strings code point by code point. Numbers are compared by value, and values for equality as errors.md (Structural validation) defines it.

### Sections and their hashes

A hash recorded in a document covers the canonical bytes of a section at a JSON Pointer that the schema names, and the section never contains its own hash (conventions.md, Hashes). The sections are these.

| Section | Hash | Recorded at |
|---|---|---|
| `/design` of a plan | design-plan hash | `/design_plan_hash` of the plan, and `/access_log/plan/design_plan_hash` of a results document bound to it |
| `/bindings/i/binding` of a plan | execution binding hash | `/bindings/i/hash` of the plan, and `/inputs/execution_binding_hash` of a Stream A results document |
| `/access_log` of a results document | none | the access log is a section of the results document without a hash of its own (02-decisions.md, Q3) |

A recorded hash that differs from the SHA-256 of the canonical bytes it covers gives E1321.

## Results document

A results document records one run of checks: the Stream B audits of a design, or the Stream A diagnostics of a fitted model. Both packages always return the results as an object, and write it only to a path the caller gives, or to the temporary directory in examples and tests (02-decisions.md, cross-cutting conventions).

### Members

| Member | Content |
|---|---|
| `results_version` | the version of the document, 0.1.x |
| `created` | the UTC time at which the document was written |
| `stream` | 'B' for design audits and 'A' for the diagnostics of a fitted model |
| `versions` | the package, registry, schema and canonicaliser versions |
| `software` | the language, the version of R or Python, the NFC library and other packages used |
| `privacy` | the privacy mode, the parameters of the privacy filter and the disclosure unit |
| `inputs` | the hashes and keyed commitments of the inputs |
| `access_log` | the section that records access to the outcome |
| `findings` | the findings, each with its six status fields, statistics and support |

Every member is required. The schema allows no other member anywhere.

### versions and software

`versions` holds what `spec_versions()` returns, with the version of the package itself, so that a result can be matched with the specification that produced it (03-execution-plan.md, Versions).

`software.language` is 'R' or 'Python' and `software.runtime` the version of R or of Python. `software.unicode` records the library that computes NFC and its version, because NFC agrees across the packages only for code points assigned in Unicode 14.0 (conventions.md, NFC): in R, `library` is 'utf8' and `version` the version of the utf8 package, and in Python, `library` is 'unicodedata' and `version` is `unicodedata.unidata_version`. `software.packages`, when present, maps the name of each other package whose results the findings use, such as an engine or the solver of the separation check, to its version as that package reports it.

### privacy

`privacy.mode` is 'shareable' or 'internal'. A shareable document passed through the privacy filter of the shared view model, which M2 specifies, and meets the invariants under Shareable documents below. An internal document did not pass through it. It is written only when the caller asks for internal mode explicitly, carries a banner in every report built from it and is written with the file suffix that M2 defines (02-decisions.md, Q5).

`min_count`, `dominance`, `rounding_base` and `zeros_disclosive` are the parameters of the filter, copied from the compiled registry (registry.md, The compiled registry). The dominance share is copied as its decimal string.

`privacy.disclosure_unit` names the unit whose distinct members the filter counts, with `source` 'declared' when the declaration names it in `disclosure_unit` and 'participant' when it is the one declared unit with role 'participant' (conventions.md, Declaration fields). Without it, there is no disclosure unit.

### inputs

`inputs` holds the public hashes and the keyed commitments of 02-decisions.md (cross-cutting conventions).

- `registry_hash` is the registry hash, the SHA-256 of the bytes of the compiled registry the package used.
- `declaration`, present when the run had a declaration, holds the declaration hash, its vocabulary version, whether it is a draft with inferred entries and whether it was validated as a minimal declaration (declarations.md).
- `model`, present when the run had a model, holds the formula as the caller gave it, the family class (registry.md, Family classes) and the IR hash (ir.md).
- `data`, present when the run read data, holds keyed commitments by what they cover: `data_file` to the bytes of the raw data file and `analysis_table` to the canonical analysis table that M2 defines (conventions.md, Keyed commitments).
- `execution_binding_hash`, present when Stream A executed a plan, is the hash of the execution binding it ran. It requires `/access_log/plan` (E7004).

The design-plan hash is recorded in the access log, and the commitment to the outcome column in each access log entry that read it. The results file hash, the SHA-256 of the written file, cannot be part of the file it covers, so it is recorded in the internal sidecar and in exports that include the file (02-decisions.md, Q5).

### Access log

The access log, at `/access_log`, records access to the outcome (02-decisions.md, Q3). It records the accesses of the run that produced the document. Earlier accesses enter it only through the frozen plan's stamp and through the attestation.

- `plan` is present when the run is bound to a frozen plan. It holds the plan's design-plan hash and `outcome_access`, the highest tier at which the outcome had been read when the plan was frozen, copied from the plan. The report header shows that tier. Without a plan, it shows the highest tier among the entries.
- `outcome_seen` is the attestation that the outcome had been seen before the run, as for secondary data, taken from `/provenance/outcome_seen` of the declaration or from the caller. Without it, the report states that there is no attestation. The package cannot verify it.
- `entries` lists one entry for each tier at which checks ran and, at T1 and T2, for each outcome column read, in the order in which the accesses happened.

An entry has the tier, the UTC time and the mode. At T0, the mode is 'outcome_blind', and the entry has no outcome and no reason, because T0 checks read no outcome. At T1 and T2, the mode is 'planned' when the access was bound to the frozen plan and 'exploratory' otherwise, and the entry has the outcome column with a keyed commitment to it and the reason the caller gave, written as given. A T1 access without a plan runs in the mode labelled exploratory, and a plan created afterwards records it in its `outcome_access` (02-decisions.md, Q3). A package records an access as planned only after it has read the plan file that the caller gives, validated it (Plan, Validation, including E1321 on `/design_plan_hash`) and found that the run's declaration hash equals `/design/declaration_hash` and its IR hash equals the IR hash of a rung. Otherwise it refuses the access with E7310, naming the member that differs, so that a hash string alone never makes an access planned.

### Outcome column commitment

The commitment of an access log entry covers 'outcome_column' (conventions.md, Keyed commitments). Its message is the canonical bytes (conventions.md, Serialisation) of an object with three members.

- `column`: the name of the outcome column.
- `key`: the columns of the declared observation key, in declared order, or an empty array when no key is declared.
- `rows`: one array for each row of the table as the table reader returns it ([tables.md](tables.md)), before any row leaves the analysis sample, holding the values of the key columns in order followed by the value of the outcome column. Values are written as a writer in the data profile writes them: a missing value as null, a number as a double, a non-finite double as 'NaN', 'Infinity' or '-Infinity', a string as read and a boolean as true or false. With a key, the rows are ordered by the canonical bytes of the array of their key values, compared byte by byte with a prefix first, and rows with equal key bytes, which keys.duplicates reports, by the canonical bytes of the whole row in the same way, so that the commitment does not depend on the order of the rows in the file. Without a key, they are in the order of the table.

For example, with the key 00 01 02 … 1F of conventions.md (Keyed commitments, Example), whose identifier is `630dcd2966c43366`, an outcome column 'post' with the key columns 'pupil' and 'wave' and four rows gives the 98 bytes

```text
{"column":"post","key":["pupil","wave"],"rows":[["p1",0,12],["p1",1,15],["p2",0,null],["p2",1,9]]}
```

and the commitment `75cc1f029d23f7ee37f8b3e0f1dc93e2d78b113b88d69f62a617346a6edafe7f`.

### Findings

A finding is the result of one check for one element of its scope (registry.md, Scopes). It has these members.

- `check`, `check_version` and `tier`: the identifier, version and tier of the registry entry.
- `scope`: the parts of the scope element, named as registry.md names them ('factor', 'first', 'second', 'term', 'column' and 'unit'), each the name of a column, grouping factor, term or unit as the IR or the declaration gives it. The scope of 'model' is the empty object.
- `status`: the six status fields (conventions.md, Status fields). When availability is not_available, no other field is present. When it is available, assessability, finding, threshold_proximity and validation are present, and optimisation is present exactly when the entry's `fitted_model` is true (E7044).
- `message`: for an available finding, the message that the decision named, by its name in the entry, and its text as rendered (registry.md, Messages), after the privacy filter in a shareable document.
- `statistics`: for an available finding, the statistics by their names in the entry. A statistic that its definition leaves absent, such as a ratio whose denominator is 0, is left out.
- `support`: for an available finding, the counts behind it that the privacy filter needs.

A check that is not available as a whole yields one finding with an empty scope (registry.md, Availability). Checks of a tier at which the run did not read the outcome, such as the T1 checks of an outcome-blind run, yield no finding, and a report lists them as not assessed from the registry and the tiers that the access log records, as every report states what could not be assessed (02-decisions.md, Q5). A finding for one scope element that the privacy filter suppressed as a whole is not_available with the reason privacy_suppressed and keeps its scope. A finding that is not available has no message, statistics or support.

Findings are ordered by `check`, compared code point by code point with a prefix first, and findings of the same check by their scopes. A scope is compared through the list of its parts in ascending order of part name, as pairs of a name and the NFC form of the value: pairs are compared in turn, first by name and then by value, each code point by code point, and a list that is a prefix of the other comes first. Two findings with the same check and equal lists are duplicates.

### Statistics

Each statistic is an object with the kind of its registry entry, its value and, for a count or a ratio, its count class.

| Kind | value |
|---|---|
| count | a non-negative integer |
| ratio | the double a / b of its two counts, which is not negative |
| real | a double, or 'NaN', 'Infinity' or '-Infinity' for a computed non-finite value |
| reals | an array of such doubles |
| category | one of the values that the entry lists |
| boolean | true or false |
| names | an array of names of columns, terms, grouping factors or parameters |
| labels | an array of labels, each as a string as M2's table reader gives the levels of a grouping factor, or pseudonyms in a shareable document |

`count_class` is 'person' or 'non_person'. An entry's class by_unit is resolved for each finding from the disclosure unit as registry.md (Statistics and counts) describes, so that the document records the class that the filter applied.

`value` is null exactly when the value was not written, and `availability` is then present with the value not_available and its reason. A value that the privacy filter suppressed has the reason privacy_suppressed, with the detail 'min_count', 'dominance' or 'quantile' for the rule that suppressed it. An `availability` member beside a value that is not null is an error (E1404).

`quantile` records, for a statistic that is the p-quantile of n values, the probability p, from 0 to 1, and n, which the privacy filter needs (02-decisions.md, Q5). It is allowed for statistics of kind count and real. A minimum is the quantile 0 and a maximum the quantile 1, so that the quantile rule also keeps minima and maxima out of shareable output. Registry 0.1.0 does not state which statistics are quantiles. M2 adds this to the entries whose statistics are order statistics, such as the level sizes of structure.cluster_sizes, before their findings are written.

### Support

`support` holds the counts behind a finding that the privacy rules of 02-decisions.md (Q5) use.

- `rows` is the number of rows of the sample that the check reads, as the `sample` of its registry entry names it: the table, the design sample or the analysis sample (registry.md, Tier and inputs).
- `contributors.basis` says who supplied those rows. It is 'disclosure_unit' when the document has a disclosure unit, and a contributor is then a member of that unit. Without a disclosure unit, it is 'grouping_factors' when the model has grouping factors, and a contributor is then a level of a grouping factor, and 'rows' otherwise, when each row is a contributor (E7006).
- `contributors.distinct` is the number of distinct contributors among the rows. With the basis grouping_factors, it is the smallest number of distinct levels over the grouping factors, as the rule 'at least k distinct levels of every grouping factor' requires.
- `contributors.largest_share` is the double nearest to c / rows, where c is the exact integer sum of the rows of the `dominance.contributors` largest contributors, divided once, and 0 when there are no rows. With the basis grouping_factors, it is the largest such share over the grouping factors.

`rows` and `distinct` are person counts, each written as an object with `value` and, when the value is not written, `availability`, as for statistics.

### Shareable documents

A shareable document meets the invariants below. They are necessary conditions that the filter of M2 guarantees and that a validator can check from the document alone. The filter may suppress further values, for example by secondary suppression, and a validator never reports a value that was suppressed. Let k be `privacy.min_count` and s the double nearest to `privacy.dominance.share`. An available finding fails the minimum-count rule when its `support.contributors.distinct.value` is null or below k, and fails the dominance rule when its `support.contributors.largest_share` is at least s. The filter, which knows the counts, applies the dominance rule exactly: with the share written as m / 10^d, a finding fails when c × 10^d ≥ m × rows in integer arithmetic. The validator's comparison of doubles gives the same result whenever rows × 10^d is below 2^53, since both doubles are correctly rounded quotients, and so for every table of fewer than 900 trillion rows with the share 0.9.

1. Every person count that is written is at least k (E7020). The person counts are the values of statistics of kind count with the class person, `support.rows` and `support.contributors.distinct`. A count of 0 is below k and therefore suppressed, which also treats zeros of person attributes as disclosive.
2. When a finding fails the minimum-count rule or the dominance rule, every statistic of kind real, reals or labels and every statistic of kind count or ratio with the class person has the value null (E7021). The issue names the rule as 'minimum-count' when the finding fails that rule, and as 'dominance' otherwise. Counts and ratios with the class non_person, booleans, categories and names stay, because counts of non-person units, parameters and df are shown exactly (02-decisions.md, Q5).
3. A statistic with `quantile` p of n values is written only when n × min(m, 10^d − m) ≥ k × 10^d in integer arithmetic, where m / 10^d is the shortest decimal that represents p (conventions.md, Serialisation), and otherwise has the value null (E7022). So with k = 10, the quantile 0.9 of 100 values is written, whereas n × (1 − p) computed in doubles would give 9.999999999999998. The filter of M2 applies the same rule.
4. Every item of a labels value is a pseudonym: '#' followed by a positive integer without leading zeros, such as '#1' (E7023). The internal sidecar maps each pseudonym to its label.

Each written value gets at most one of these issues, the first that applies in the order E7020, E7021, E7022 and E7023, and the items of a labels value that E7021 reports are not checked for pseudonyms. A fifth invariant needs the registry entry and is checked in stage 5: a statistic of kind ratio whose numerator or denominator, as the entry names them, is a person count that is not written or is below k, has the value null (E7024), so that a written ratio and a written denominator cannot give back a suppressed count. The document holds no commitment key (E1315), no path, no user name and no host name: the schema has no member for any of them, and the free text it holds, the formula and the reasons in the access log, is written as the caller gave it.

### Writing

A written results document consists of exactly its canonical bytes (conventions.md, Serialisation), so the results file hash is the SHA-256 of the document's canonical bytes. When the document holds a keyed commitment or a pseudonym, the writer also writes an internal sidecar beside it, at a path the caller gives.

### Internal sidecar

The internal sidecar holds what must not leave the analyst's machine (02-decisions.md, cross-cutting conventions). It is a data-profile document that `urn:mixedcheck:schema:results#/$defs/sidecar` describes, with these members.

| Member | Content |
|---|---|
| `sidecar_version` | the version of the sidecar, 0.1.x |
| `results_hash` | the SHA-256 of the bytes of the results file that the sidecar accompanies |
| `keys` | the commitment keys of the results document, as `commitment_key` objects (conventions.md, Keys) |
| `pseudonyms` | for each pseudonym of the results document, the pseudonym, the column or grouping factor whose label it replaces and the label as the data give it |

Observation keys and the labels of predicted random effects, which 02-decisions.md also places in the sidecar, are added with the milestones that write them (M2 and M5), as a MINOR version.

The rules enforced in code are these.

| Code | Rule | Location |
|---|---|---|
| E1321 | A key identifier is the first 16 hexadecimal digits of the SHA-256 of the 32 bytes of its key. | `/keys/i/key_id` |
| E7060 | A pseudonym differs from every earlier pseudonym. | `/pseudonyms/i/pseudonym` |
| E7061 | A key identifier differs from every earlier key identifier. | `/keys/i/key_id` |

Verification reads a results file with its sidecar. It reports E1321 at `/results_hash` when the hash differs from the SHA-256 of the results file, E1313 for a commitment whose key the sidecar does not hold and E1314 for a commitment that the data do not match (conventions.md, Keyed commitments).

### Validation

The validator of a results document works in five stages and stops after the first stage that reports an issue.

1. Reading, in the data profile.
2. Version, at `/results_version`.
3. Structure, against results.schema.json.
4. Document rules, the first step of the rules in code: the rules on findings and the access log, and, in a shareable document, the invariants above.
5. Registry rules, the second step, only when stage 4 found no issue.

Stage 5 compares `/inputs/registry_hash` with the hash of the compiled registry vendored with the package. If they differ, the document was produced with another registry, and the validator reports W7090 at `/inputs/registry_hash` and nothing else. If they are equal, it checks each finding against the registry entry of its check.

Stage 4 applies these rules.

| Code | Rule | Location |
|---|---|---|
| E7001 | No finding has the same check and scope as an earlier finding. | `/findings/i` of each later finding |
| E7002 | No finding comes before the finding immediately before it in the order of findings. | `/findings/i` |
| E7003 | For each available finding, the access log has an entry of the finding's tier. | `/findings/i/tier` |
| E7004 | An entry with the mode 'planned', and `/inputs/execution_binding_hash`, have `/access_log/plan`. | `/access_log/entries/i/mode` and `/inputs/execution_binding_hash` |
| E7005 | The time of each entry is not earlier than that of the entry before it. | `/access_log/entries/i/time` |
| E7006 | The basis of every support is 'disclosure_unit' when `/privacy/disclosure_unit` is present, and 'grouping_factors' or 'rows' otherwise. | `/findings/i/support/contributors/basis`, with the values allowed |
| E7020 | In a shareable document, every person count that is written is at least min_count. | `/findings/i/statistics/s/value`, `/findings/i/support/rows/value` or `/findings/i/support/contributors/distinct/value` |
| E7021 | In a shareable document, a finding that fails the minimum-count or dominance rule writes no value of kind real, reals or labels and no person count or ratio. | `/findings/i/statistics/s/value` |
| E7022 | In a shareable document, a quantile that fails the quantile rule above is not written. | `/findings/i/statistics/s/value` |
| E7023 | In a shareable document, every label is a pseudonym. | `/findings/i/statistics/s/value/j` |

Stage 5 applies these rules to each finding. A finding whose check is not in the registry gets E7040 alone.

| Code | Rule | Location |
|---|---|---|
| E7040 | The check is an entry of the registry. | `/findings/i/check` |
| E7041 | `check_version` and `tier` equal those of the entry. The kind of each statistic equals the entry's, and so does its count class where the entry's class is person or non_person. | `/findings/i/check_version`, `/findings/i/tier`, `/findings/i/statistics/s/kind` or `/findings/i/statistics/s/count_class`, with the value the entry requires |
| E7042 | Each statistic, the message and each scope part are defined by the entry. | `/findings/i/statistics/s`, `/findings/i/message/id` or `/findings/i/scope/p`, naming the kind 'statistic', 'message' or 'scope part' |
| E7043 | The scope of an available finding, or of a finding that is not available and has a non-empty scope, has every part of the entry's scope. | `/findings/i/scope`, once for each missing part |
| E7044 | The status of an available finding includes optimisation exactly when the entry's `fitted_model` is true. | `/findings/i/status` |
| E7024 | In a shareable document, a ratio whose numerator or denominator, as the entry names them, is a person count that is not written or is below min_count, is not written. | `/findings/i/statistics/s/value` |

### Example

This shareable document records a planned Stream B run on the cluster-randomised trial of declarations.md (Example), with 480 pupils measured twice and 10 outcome values missing. The hashes and the data-file digest are placeholders of the right form. The outcome commitment is the example above, and the key identifier that of the key 00 01 02 … 1F.

```json
{
  "results_version": "0.1.0",
  "created": "2026-11-08T09:06:00Z",
  "stream": "B",
  "versions": {
    "package": "0.1.0",
    "registry": "0.1.0",
    "schemas": "0.1.0",
    "canonicaliser": "0.1.0"
  },
  "software": {
    "language": "Python",
    "runtime": "3.13.1",
    "unicode": {"library": "unicodedata", "version": "15.1.0"}
  },
  "privacy": {
    "mode": "shareable",
    "min_count": 10,
    "dominance": {"contributors": 2, "share": "0.9"},
    "rounding_base": 5,
    "zeros_disclosive": true,
    "disclosure_unit": {"name": "pupil", "source": "participant"}
  },
  "inputs": {
    "registry_hash": "sha256:872491a30d60d598962de6e7b834ab76b2aa65fbab102c6ebaaae6acdc238822",
    "declaration": {
      "hash": "sha256:abcd0ee1fc2cdf511d8a85bd020c5f2f18468d6c442f5506fec7d859b8fea335",
      "vocabulary": "0.1.0",
      "draft": false,
      "minimal": true
    },
    "model": {
      "formula": "post ~ arm + pre + (1 | school/class)",
      "family_class": "gaussian",
      "ir_hash": "sha256:08c85bd37cdd0ffce8c39ecd7c7f0ff94e6f45af2aa986673b0c9f1a8a2fffea"
    },
    "data": {
      "data_file": {
        "algorithm": "hmac-sha256",
        "covers": "data_file",
        "digest": "3fd4fa71c858aa2220b2c7417504cdea3242c26ef0feadab0714f3a5d70fad51",
        "key_id": "630dcd2966c43366"
      }
    }
  },
  "access_log": {
    "plan": {
      "design_plan_hash": "sha256:a77de8a6daa1129516b14c8ca1e233a51a8414b202eac7c8acfbb9b485046ad4",
      "outcome_access": "T0"
    },
    "outcome_seen": false,
    "entries": [
      {"tier": "T0", "time": "2026-11-08T09:05:00Z", "mode": "outcome_blind"},
      {
        "tier": "T1",
        "time": "2026-11-08T09:05:30Z",
        "mode": "planned",
        "outcome": {
          "column": "post",
          "commitment": {
            "algorithm": "hmac-sha256",
            "covers": "outcome_column",
            "digest": "75cc1f029d23f7ee37f8b3e0f1dc93e2d78b113b88d69f62a617346a6edafe7f",
            "key_id": "630dcd2966c43366"
          }
        },
        "reason": "The T1 checks of the frozen plan."
      }
    ]
  },
  "findings": [
    {
      "check": "keys.duplicates",
      "check_version": 1,
      "tier": "T0",
      "scope": {},
      "status": {
        "availability": {"value": "available"},
        "assessability": {"value": "adequate"},
        "finding": {"value": "consistent"},
        "threshold_proximity": {"value": "clear"},
        "validation": {"value": "descriptive"}
      },
      "message": {
        "id": "unique",
        "text": "Every row has its own value of the observation key 'school', 'class', 'pupil' and 'wave'."
      },
      "statistics": {
        "rows": {"kind": "count", "value": 960, "count_class": "person"},
        "duplicate_rows": {
          "kind": "count",
          "value": null,
          "count_class": "person",
          "availability": {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": "min_count"
          }
        },
        "duplicated_keys": {
          "kind": "count",
          "value": null,
          "count_class": "person",
          "availability": {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": "min_count"
          }
        },
        "conflicting_keys": {
          "kind": "count",
          "value": null,
          "count_class": "person",
          "availability": {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": "min_count"
          }
        },
        "identical_keys": {
          "kind": "count",
          "value": null,
          "count_class": "person",
          "availability": {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": "min_count"
          }
        },
        "missing_key_rows": {
          "kind": "count",
          "value": null,
          "count_class": "person",
          "availability": {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": "min_count"
          }
        },
        "key_columns": {"kind": "names", "value": ["school", "class", "pupil", "wave"]}
      },
      "support": {
        "rows": {"value": 960},
        "contributors": {
          "basis": "disclosure_unit",
          "distinct": {"value": 480},
          "largest_share": 0.004166666666666667
        }
      }
    },
    {
      "check": "outcome.constant_clusters",
      "check_version": 1,
      "tier": "T1",
      "scope": {"factor": "school"},
      "status": {
        "availability": {"value": "available"},
        "assessability": {"value": "adequate"},
        "finding": {"value": "consistent"},
        "threshold_proximity": {"value": "clear"},
        "validation": {"value": "descriptive"}
      },
      "message": {
        "id": "none_constant",
        "text": "The outcome varies within every level of 'school' that has two or more rows."
      },
      "statistics": {
        "multi_row_levels": {"kind": "count", "value": 6, "count_class": "non_person"},
        "constant_levels": {"kind": "count", "value": 0, "count_class": "non_person"},
        "constant_share": {"kind": "ratio", "value": 0, "count_class": "non_person"}
      },
      "support": {
        "rows": {"value": 950},
        "contributors": {
          "basis": "disclosure_unit",
          "distinct": {"value": 476},
          "largest_share": 0.004210526315789474
        }
      }
    },
    {
      "check": "structure.label_incidence",
      "check_version": 1,
      "tier": "T0",
      "scope": {"first": "class", "second": "school"},
      "status": {
        "availability": {"value": "available"},
        "assessability": {"value": "adequate"},
        "finding": {"value": "consistent"},
        "threshold_proximity": {"value": "clear"},
        "validation": {"value": "descriptive"}
      },
      "message": {
        "id": "relation",
        "text": "In the design sample, 'class' has 4 labels and 'school' has 6, which occur in 24 combinations. Relation from the labels: crossed."
      },
      "statistics": {
        "combinations": {"kind": "count", "value": 24, "count_class": "non_person"},
        "composite": {"kind": "boolean", "value": true},
        "declared": {"kind": "category", "value": "nested_within_parent"},
        "first_in_several": {"kind": "count", "value": 4, "count_class": "non_person"},
        "inner": {"kind": "names", "value": ["class"]},
        "inner_in_several": {"kind": "count", "value": 4, "count_class": "non_person"},
        "levels_first": {"kind": "count", "value": 4, "count_class": "non_person"},
        "levels_second": {"kind": "count", "value": 6, "count_class": "non_person"},
        "outer": {"kind": "names", "value": ["school"]},
        "relation": {"kind": "category", "value": "crossed"},
        "second_in_several": {"kind": "count", "value": 6, "count_class": "non_person"}
      },
      "support": {
        "rows": {"value": 960},
        "contributors": {
          "basis": "disclosure_unit",
          "distinct": {"value": 480},
          "largest_share": 0.004166666666666667
        }
      }
    }
  ]
}
```

The counts of levels of 'class' and 'school' are non-person counts, because both units are coarser than the disclosure unit 'pupil'. The duplicate counts of keys.duplicates are person counts of 0, below k = 10, so they are suppressed, whereas the message that the decision chose quotes none of them. The canonical bytes of the document are 5,178 bytes long, and its results file hash is `sha256:96266d92ba646e346fbf6f19a59bd4f0b8ce63226d3a75a2d53aaa935a653477`, which the sidecar records:

```json
{
  "sidecar_version": "0.1.0",
  "results_hash": "sha256:96266d92ba646e346fbf6f19a59bd4f0b8ce63226d3a75a2d53aaa935a653477",
  "keys": [
    {
      "created": "2026-11-08T09:05:30Z",
      "key": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
      "key_id": "630dcd2966c43366"
    }
  ],
  "pseudonyms": []
}
```

A check that cannot run gives a finding such as this one, for keys.duplicates without a declared observation key:

```json
{
  "check": "keys.duplicates",
  "check_version": 1,
  "tier": "T0",
  "scope": {},
  "status": {
    "availability": {
      "value": "not_available",
      "reason": "declaration_missing",
      "detail": "/observation/key"
    }
  }
}
```

## Plan, version 0.1

A plan is the Stream B output of 02-decisions.md (Q3): the design-implied ceiling, identifiability verdicts, an outcome-free ladder of nested rungs with a protected set, a stopping rule from the menu, a terminal state and two hashes. It is a document in the hashable profile, so that a plan deposited with a third party can be read and hashed by any later release that supports its version. Version 0.1 fixes the parts and the hashes. M3, which builds the ladder generator, refines the members of each part.

### Members

| Member | Content |
|---|---|
| `plan_version` | the version of the plan, 0.1.x |
| `created` | the UTC time at which the plan was frozen |
| `language` | the language of the package that wrote the plan |
| `versions` | the package, registry, schema and canonicaliser versions |
| `outcome_access` | the highest tier at which the outcome had been read when the plan was frozen |
| `for_preregistration` | false in every plan of version 0.1 |
| `rule_evidence` | 'simulated_conditions_only', exactly when the design has a stopping rule |
| `design` | the language-neutral section, which the design-plan hash covers |
| `design_plan_hash` | the design-plan hash |
| `ceiling` | the design-implied ceiling with its counts and verdict |
| `verdicts` | the identifiability verdict of each rung |
| `bindings` | the execution bindings, each with its hash |

`outcome_access` is T0 for a plan made outcome-blind, and T1 or T2 stamps the plan as planned after outcome inspection (02-decisions.md, Q3). Plans written by 0.x releases are not for preregistration until the plan schema and the canonicaliser carry versions that later releases can verify, so `for_preregistration` is false. `rule_evidence` states that the rule's operating characteristics are known only for the simulated conditions until study H1 has run, which the report repeats.

### The design section

`/design` holds exactly what the design-plan hash covers (conventions.md, Hashes): the declaration hash, the IR of every rung, the protected set, the stopping rule with its version and the terminal state. Every value in it must be computed identically in both languages, so that the design-plan hash matches across languages (03-execution-plan.md, M3). The ceiling, the verdicts and the bindings lie outside it, because 02-decisions.md (Q3) names exactly what the hash covers and the bindings depend on the engine.

- `declaration_hash` is the hash of the declaration the plan was built from, absent when there was none.
- `ladder` is 'protected' when the declaration names estimands, so that the protected set is defined. It is 'exploratory' otherwise, and the plan then has no protected set, no rule and no terminal state, so no rule is executed.
- `rungs` lists the rungs in order. Each holds the IR of the rung (ir.md), with the coding of every categorical predictor frozen as numeric contrast columns (ir.md, Coding argument), the centring frozen and the columns that the ceiling reads as its sample columns, so that every rung has the design sample of the ceiling and its centring constants (ir.md, Samples, and 01-design-review.md). A plan written before the data are seen stores the centring rule rather than a constant (conventions.md, Decimal strings and centring constants). Rung 0 is the ceiling restricted to identifiable terms and has no step. Every later rung has a `step`: its kind, the grouping factor and the random terms of the rung before that the step changes or removes.
- `protected` lists the protected components, each with its grouping factor, the variables of the term of the random part that it protects (an empty list for the random intercept) and the reason it is protected: replication_unit and randomisation_unit for random intercepts, focal_slope for the by-unit slope of a focal within-unit effect, focal_interaction_slope for the slope of the highest-order combination of within-unit factors in a focal interaction and cross_level_interaction_slope for the lower-level slope of a focal cross-level interaction.
- `rule` names the stopping rule, its version and the values it uses as decimal strings, such as `"alpha": "0.2"` for protected_lrt. Version 0.1 offers the rules of the first 0.x release: localised_backoff, the default, protected_lrt and no_reduction. Protected AIC and the unprotected back-off are not offered.
- `terminal` is the declared terminal state for when the protected rung fails: no_confirmatory_model in both languages, or cluster_robust_cr2, CR2 inference for nested designs through clubSandwich in R only, labelled engine-specific.

The kinds of step follow the order of reduction of 02-decisions.md (Q3). decorrelate replaces a correlated block of numeric slopes, among them the contrast columns of frozen factors, by separate uncorrelated terms, as '||' writes them (ir.md, Random terms). complex_intercepts replaces the unstructured block of a factor slope with three or more levels by (1 | g) + (1 | g:f), whose restriction to non-negative correlation the report states. drop_terms removes the variances of the terms listed.

### Ceiling, verdicts and counts

`ceiling` holds the IR of the design-implied ceiling, its identifiability verdict, the random terms left out of rung 0 as not identifiable and, for each grouping factor, its number of levels, its level-specific df budget and the number of informative groups behind each of its random terms.

A verdict is 'identified' or 'not_identified' from the exact test for Gaussian LMMs whose covariance parameters enter linearly. For GLMMs, only a necessary condition is tested, giving 'necessary_condition_met' or 'not_identified'. These are the values of the statistic verdict of identifiability.gram_rank. When that check is not available for the ceiling or a rung, as when Z has more columns than its parameter max_z_columns, the package builds no plan and reports the check's availability instead. `verdicts` holds one verdict for each rung, and since a rung that is not identified is removed from the ladder, none of them is 'not_identified'.

The hashable profile has no null, so a count in a plan is a non-negative integer, or `{"below": k}` when the privacy filter suppressed a person count below k. The levels and informative groups of a grouping factor are counts of its levels, classified as registry.md (Statistics and counts) classifies by_unit counts. A df budget is the statistic budget of identifiability.df_budget, a non-person count that is always written and never negative.

### Execution bindings

Each entry of `bindings` holds an execution binding and its hash. A binding records how one engine in one language runs the plan (02-decisions.md, Q3): the design-plan hash it refers to, the language, the engine and its version, the optimisers in order of use, the second serving as the restart for large q, each with its settings by name, and one entry for each rung of the design. A rung's entry is available, with its encoding for the engine, such as an lme4 formula, or not_available with the reason not_expressible and the engine's name as detail. A rung is never skipped. The binding hash covers the binding, and with it the design-plan hash, so that it identifies one plan run by one engine.

### Validation

The validator of a plan works in four stages: reading in the hashable profile, the version at `/plan_version`, the structure against plan.schema.json and the rules in code below. The structure of each IR, of the ceiling and of every rung, is checked against ir.schema.json as part of the plan's, and the rules in code include the rule of ir.md (Validation) for each IR, reported as E6101 at its JSON Pointer in the plan. M3 implements the validator.

| Code | Rule | Location |
|---|---|---|
| E1321 | `/design_plan_hash` is the SHA-256 of the canonical bytes of `/design`, and each `/bindings/i/hash` that of `/bindings/i/binding`. | `/design_plan_hash`, `/bindings/i/hash` |
| E7301 | A binding has as many rungs as the design. | `/bindings/i/binding/rungs` |
| E7302 | A binding's design-plan hash equals `/design_plan_hash`. | `/bindings/i/binding/design_plan_hash` |
| E7303 | There are as many verdicts as rungs. | `/verdicts` |
| E7304 | No verdict of a rung is 'not_identified'. | `/verdicts/i` |
| E7305 | No protected component has the grouping factor and set of variables of an earlier one. | `/design/protected/i` |
| E7306 | Every protected component appears in every rung: a random term of its grouping factor has a term whose set of variables equals the component's, the intercept for an empty list, or, for a component with one categorical variable f after a step complex_intercepts on it, the rung has the random intercept of the grouping factor of the component's factor joined with f, which replaces the component. | `/design/protected/i`, once for each rung that lacks it, numbered from 0 |
| E7307 | The package can run the terminal state. The Python package cannot run cluster_robust_cr2. | `/design/terminal/state` |
| E7309 | The terminal state cluster_robust_cr2 has nested grouping factors, so that CR2 inference can cluster on one of them: one grouping factor of rung 0 whose columns every other grouping factor of rung 0 includes, as `(1 \| school/class)` gives. | `/design/terminal/state` |
| E7308 | No grouping factor of the ceiling repeats an earlier one. | `/ceiling/factors/i/factor` |

### Example

The plan below is abbreviated: each IR is shown as `{…}`, and the hashes as `sha256:…`. It belongs to a crossed design of 48 subjects with a focal within-subject factor 'cond' and a nuisance covariate 'freq_c'.

```text
{
  "plan_version": "0.1.0",
  "created": "2026-11-08T09:00:00Z",
  "language": "R",
  "versions": {"package": "0.1.0", "registry": "0.1.0", "schemas": "0.1.0", "canonicaliser": "0.1.0"},
  "outcome_access": "T0",
  "for_preregistration": false,
  "rule_evidence": "simulated_conditions_only",
  "design": {
    "declaration_hash": "sha256:…",
    "ladder": "protected",
    "rungs": [
      {"ir": {…}},
      {"ir": {…}, "step": {"kind": "decorrelate", "factor": "subject", "terms": ["1 + cond + freq_c | subject"]}},
      {"ir": {…}, "step": {"kind": "drop_terms", "factor": "subject", "terms": ["0 + freq_c | subject"]}}
    ],
    "protected": [
      {"factor": "subject", "variables": [], "reason": "replication_unit"},
      {"factor": "subject", "variables": ["cond"], "reason": "focal_slope"}
    ],
    "rule": {"id": "localised_backoff", "version": 1, "parameters": {}},
    "terminal": {"state": "no_confirmatory_model"}
  },
  "design_plan_hash": "sha256:…",
  "ceiling": {
    "ir": {…},
    "verdict": {"value": "identified"},
    "factors": [
      {
        "factor": "subject",
        "levels": 48,
        "df_budget": 47,
        "terms": [{"term": "1 + cond + freq_c | subject", "informative_groups": 48}]
      }
    ]
  },
  "verdicts": [{"value": "identified"}, {"value": "identified"}, {"value": "identified"}],
  "bindings": [
    {
      "binding": {
        "design_plan_hash": "sha256:…",
        "language": "R",
        "engine": {"name": "lme4", "version": "2.1-0"},
        "optimisers": [{"name": "bobyqa", "settings": {}}, {"name": "Nelder_Mead", "settings": {}}],
        "rungs": [
          {"availability": {"value": "available"}, "encoding": "y ~ cond + freq_c + (1 + cond + freq_c | subject)"},
          {"availability": {"value": "available"}, "encoding": "y ~ cond + freq_c + (1 + cond + freq_c || subject)"},
          {"availability": {"value": "available"}, "encoding": "y ~ cond + freq_c + (1 + cond || subject)"}
        ]
      },
      "hash": "sha256:…"
    }
  ]
}
```

The names of random terms are those of the IR (ir.md, Names). Every IR codes 'cond', a factor with two levels, with simple contrasts and its coding frozen, so that its slope is one numeric column of ±0.5 and the decorrelate step splits it from the intercept as `(1 + cond + freq_c || subject)` does. Rung 1 holds '1 | subject', '0 + cond | subject' and '0 + freq_c | subject', and each rung holds the protected intercept and slope of 'subject' as terms of its random terms.

## Bring-your-own estimates, contract version 0.1

The fitted-model contract is the set of fields that every adapter supplies to Stream A (02-decisions.md, Q1). A bring-your-own estimates file writes the contract as a data-profile document, so that estimates from any engine can be diagnosed. The file holds the observation keys of the analysis sample, which identify rows of person-level data, so it is an internal input: the packages read it and never copy it into shareable output. Version 0.1 holds the required fields of Q1 for Gaussian LMMs, the models that Stream A diagnoses in 1.0. M5, which builds the adapters, refines it.

### Members

| Field of Q1 | Member |
|---|---|
| engine, engine version, adapter version and contract version | `engine` and `adapter`, each with a name and a version, and `contract_version` |
| the IR hash and the analysis-sample observation keys | `ir_hash` and `analysis_sample` |
| the map from engine coefficients to canonical IR columns, with aliasing flags | `coefficients` |
| the criterion and whether the reported likelihood is exact | `criterion` |
| the semantics of the weights | `weights` |
| the fixed effects | `coefficients`, the `estimate` of each column that is not aliased |
| the absolute covariance matrix of each random-effects block, with its packing order | `random_effects` |
| the residual variance or dispersion | `residual` |
| the reported objective, with its constant convention | `objective` |
| the covariance matrix of the fixed effects, with a method label | `fixed_effects_covariance` |
| the raw convergence output | `convergence` |
| the flags of the optional capabilities | `capabilities` |

- `analysis_sample.columns` lists the columns of the declared observation key, in declared order, and each item of `analysis_sample.keys` holds the values of those columns, strings or integers, for one row the engine used. Rows are identified by these values, never by position, because R and Python index rows differently (02-decisions.md, cross-cutting conventions).
- `coefficients` has one entry for each column of the fixed part of the IR, in the IR's column order: the IR column, the engine's name for its coefficient, which is absent when the engine reports none, whether the engine treated the column as aliased and, for a column that is not aliased, the estimate. The map is built by matching design columns numerically, never by parsing names (02-decisions.md, Q1).
- `criterion.name` is reml, ml, laplace, agq with its number of `nodes`, nagq0, variational_bayes or map, and `exact_likelihood` states whether the reported likelihood is exact rather than approximated.
- `weights` is none for a model without weights, or precision, frequency or log_likelihood_multiplier.
- `residual` holds the residual variance of a Gaussian model. The dispersion of other families follows with GLMMs in 1.1 (02-decisions.md, Q2).
- `objective` holds the reported value, its scale, minus_two_log_likelihood or log_likelihood, and whether it includes every normalising constant. A value without some constants, such as lme4's AGQ log-likelihood before 2.1-0, is marked 'omitted' and matched through the offsets that the registry records for the engine and version.
- `fixed_effects_covariance.method` is conditional_on_theta, joint_observed_hessian, finite_difference_hessian, expected_information or posterior, because standard-error conventions differ by up to 2.4% between engines (02-decisions.md, Q1).
- `convergence` holds the optimiser, the engine's messages in order and any other values by name, as the engine gave them. The suite computes its own optimisation status and never takes it from these values.
- `capabilities` flags X, Z, labelled predicted random effects, an objective function, refit, simulate and df. A file cannot carry a function, so objective_function, refit and simulate are false in every version. Contract 0.1 has no members that carry X, Z, predicted random effects or df, so they are false too until a later version adds them. A missing capability makes the checks that need it not_available with the reason capability_missing.

### Packing of covariance matrices

A symmetric matrix of q columns, in the order that `columns` gives, is listed in one of three packing orders. full_row_major lists all q × q values row by row. lower_column_major lists the q(q + 1)/2 values on and below the diagonal column by column, which is the half-vectorisation vech and the order in which R's `x[lower.tri(x, diag = TRUE)]` returns them. lower_row_major lists the same values row by row. Reading glmm's covariance in the wrong order shifted the REML criterion by 2.3 units, yet still gave a positive-definite matrix (02-decisions.md, Q1), so the order is always stated.

### Validation

The validator of an estimates file works in four stages: reading in the data profile, the version at `/contract_version`, the structure against estimates.schema.json and the rules in code below. Checks against the IR whose hash the file records, such as whether every column of the fixed part has an entry, belong to the adapter of M5.

| Code | Rule | Location |
|---|---|---|
| E7601 | No coefficient has the column of an earlier coefficient. | `/coefficients/i/column` |
| E7602 | No coefficient has the engine name of an earlier coefficient. | `/coefficients/i/engine_name` |
| E7603 | A matrix has q × q values packed in full and q(q + 1)/2 values packed as a lower triangle, for its q columns. | `/random_effects/i/covariance`, `/fixed_effects_covariance/values` |
| E7604 | A matrix packed in full, with the right number of values, has equal values at (r, c) and (c, r). | as for E7603 |
| E7605 | The columns of the fixed-effects covariance are the columns of the coefficients that are not aliased, in the same order. | `/fixed_effects_covariance/columns` |
| E7606 | Every key of the analysis sample has as many values as the observation key has columns. | `/analysis_sample/keys/i` |
| E7607 | No column belongs to two blocks of the same grouping factor. | `/random_effects/i/columns/j` of the later block |

### Example

This file reports a Gaussian model with a random intercept and slope by subject, fitted by REML. The values are illustrative, and the analysis sample is shortened to two rows.

```json
{
  "contract_version": "0.1.0",
  "engine": {"name": "glmm", "version": "0.8.0"},
  "adapter": {"name": "my_export", "version": "1.0"},
  "ir_hash": "sha256:08c85bd37cdd0ffce8c39ecd7c7f0ff94e6f45af2aa986673b0c9f1a8a2fffea",
  "analysis_sample": {"columns": ["Subject", "Days"], "keys": [["308", 0], ["308", 1]]},
  "coefficients": [
    {"column": "(Intercept)", "engine_name": "Intercept", "aliased": false, "estimate": 251.4},
    {"column": "Days", "engine_name": "Days", "aliased": false, "estimate": 10.47}
  ],
  "criterion": {"name": "reml", "exact_likelihood": true},
  "weights": "none",
  "random_effects": [
    {
      "factor": "Subject",
      "columns": ["(Intercept)", "Days"],
      "packing": "lower_column_major",
      "covariance": [612.1, 9.6, 35.07]
    }
  ],
  "residual": {"parameterisation": "residual_variance", "value": 654.9},
  "objective": {"value": 1743.6, "scale": "minus_two_log_likelihood", "constants": "included"},
  "fixed_effects_covariance": {
    "method": "conditional_on_theta",
    "columns": ["(Intercept)", "Days"],
    "packing": "lower_column_major",
    "values": [46.57, -1.46, 2.39]
  },
  "convergence": {"optimiser": "lbfgs", "messages": ["converged"], "values": {"iterations": 21}},
  "capabilities": {
    "x": false,
    "z": false,
    "predicted_random_effects": false,
    "objective_function": false,
    "refit": false,
    "simulate": false,
    "df": false
  }
}
```

## Left to later milestones

- M2 specifies the privacy filter that produces a shareable document, including how suppressed values render in message text, the canonical analysis table that the analysis_table commitment covers, the file suffix of internal mode and the quantile probabilities of the registry's order statistics. It adds the observation keys to the sidecar.
- M3 builds the ladder generator, which fixes how each rung's IR follows from the ceiling. It also fixes the menu of stopping rules with their versions and parameters and how a plan written before the data are seen records its centring rules, and it implements the plan validator.
- M4 adds the figures and their aggregated tables to the results document, with the support of each bin.
- M5 adds the Stream A sections of the results document, the labels of predicted random effects in the sidecar, the optional capabilities of the contract and the checks of an estimates file against its IR.

## References

Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation (JSON) Pointer (RFC 6901). Internet Engineering Task Force. https://doi.org/10.17487/RFC6901

Krawczyk, H., Bellare, M., & Canetti, R. (1997). HMAC: Keyed-hashing for message authentication (RFC 2104). Internet Engineering Task Force. https://doi.org/10.17487/RFC2104

Rundgren, A., Jordan, B., & Erdtman, S. (2020). JSON Canonicalization Scheme (JCS) (RFC 8785). Internet Engineering Task Force. https://doi.org/10.17487/RFC8785

Wright, A., Andrews, H., Hutton, B., & Dennis, G. (2022). JSON Schema: A media type for describing JSON documents (draft 2020-12). https://json-schema.org/draft/2020-12/json-schema-core
