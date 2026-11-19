# Declarations

A declaration describes the design behind a dataset: its grouping units and how they nest or cross, what one row is, what was assigned and how, the roles of the columns, the estimands and where the declaration comes from. It supplies what the data cannot show (02-decisions.md, Q4). This document specifies declaration vocabulary 0.1: its members and their meaning, the rules that the validators enforce in code, the order in which every check runs, the code that each failure reports and how a declaration written in YAML becomes JSON. It is normative together with [spec/schemas/declaration.schema.json](../../spec/schemas/declaration.schema.json), and where the two disagree, this document prevails and the schema is corrected. [conventions.md](conventions.md) defines the reader, the hashable profile, hashing and YAML authoring in general, and [errors.md](errors.md) defines the error codes, the structural checks and the order of reported issues.

## Scope

Declarations are optional by default. Checks whose inputs the data determine run without one, and a check that needs a declared field reports not_available with the reason declaration_missing and the JSON Pointer of the field (conventions.md, Status fields). A minimal declaration, defined below, is required for a confirmatory goal, for the outcome-blind and preregistration exports and for the trial features cluster_randomised, stepped_wedge and partially_nested, which also require the assignment block (02-decisions.md, Q4).

The validator checks a declaration on its own. Whether the data agree with it is checked when the data are read and audited: `audit()` refuses data that lack a column that the declaration names with E5011, which can happen only for a data frame or a file read without a table block, since the table block names every column of a file, and whether a key is unique or an assigned column is constant within the declared unit is reported as findings of the registry (03-execution-plan.md, M2, and [registry.md](registry.md)).

## Documents, versions and hashes

A declaration is a JSON object in the hashable profile. Its member `vocabulary` holds the version of the vocabulary, and this release reads every version 0.1.x (conventions.md, Versions). The declaration hash is 'sha256:' followed by the SHA-256 of its canonical bytes, computed after conversion when the declaration was written in YAML (conventions.md, Hashes). Every member counts towards the hash, `provenance` included, so any edit changes it.

A declaration reaches the validator in one of three ways:

- from a file whose name ends in '.yaml' or '.yml', compared in ASCII lower case, through the YAML reader and the conversion described under YAML authoring
- from any other file, through the strict reader in the hashable profile
- as a value in memory, such as the output of a builder, which first crosses the input boundary of conventions.md (Strings in R) in R and then passes the writer's checks of the hashable profile (conventions.md, Serialisation)

Each of these reports at most one issue, and validation stops at it.

## The vocabulary

A declaration has the members below. Each block is optional, and only `vocabulary` is required. Unknown keys are errors everywhere (E1403), including in table field descriptors and for the dyad, EEG and imputation blocks, which follow in a later vocabulary. An optional list or object that is present must not be empty, except a list of missing values, so that the absence of a block is always written by leaving it out.

| Member | Content | When absent |
|---|---|---|
| `vocabulary` | the vocabulary version, 0.1.x | the declaration is invalid (E1402) |
| `title` | a title of 1 to 200 characters without control characters | no title |
| `goal` | 'confirmatory' or 'exploratory' | 'exploratory' |
| `features` | design features | no feature is declared |
| `disclosure_unit` | the unit whose members the privacy rules count | the one unit with role 'participant', if there is exactly one (conventions.md, Declaration fields) |
| `table` | the types, categories, missing values and keys of the columns | the data are read by the rules for columns without a table block (tables.md) |
| `units` | the grouping units | grouping factors come from the formula, and their relations are inferred from the data with 'inferred' wording |
| `crossings` | pairs of crossed units | crossing is inferred from the incidence of labels |
| `observation` | what one row is | keys.duplicates and the checks that need the time of a row report not_available |
| `assignment` | the assigned variables | randomisation checks report not_available |
| `variables` | the roles and measurement of columns | role checks report not_available, and outcome-blind mode cannot exclude an undeclared outcome |
| `estimands` | the estimands | the protected set cannot be defined, so the ladder is labelled exploratory and no stopping rule runs (02-decisions.md, Q3) |
| `provenance` | the origin of the declaration | the report states that there is no attestation |

The goal 'prediction' and the estimand kind 'prediction' follow after 1.0 (03-execution-plan.md), and vocabulary 0.1 rejects them (E1405).

### Features

Features are tags that select domain checks and the wording of messages. They never change data. Each tag appears at most once.

| Feature | Meaning | Requires |
|---|---|---|
| cluster_randomised | whole clusters, such as classes or schools, were randomised | `/assignment` |
| multisite | the study ran at several sites, with any assignment made within sites | nothing |
| stepped_wedge | clusters cross from control to treatment at randomised times | `/assignment` and `/observation/time` |
| partially_nested | members are clustered in one arm only, such as therapy groups in the treatment arm | `/assignment` |
| longitudinal | units are measured on repeated occasions | `/observation/time` |
| intensive_longitudinal | units are measured many times, as in experience sampling or app logs | `/observation/time` |
| family | members are nested in families | nothing |
| crossed_experiment | participants respond to items, which are crossed with them | nothing |
| counterbalanced | conditions rotate across lists, as in a Latin square | nothing |
| trial_level | each row is one trial | nothing |
| corpus | the data come from a language corpus, with speakers crossed with words | nothing |
| observational | no variable was assigned by the investigators | contradicts `/assignment`, the role 'assigned' and the features cluster_randomised, stepped_wedge and partially_nested |

A missing requirement gives E2025 and a contradiction E2027. The feature observational lets an observational study, such as a secondary analysis, form a minimal declaration without an assigned variable (see The minimal declaration).

### table

The table block is a subset of the Frictionless Table Schema v2. It holds `fields`, `missingValues`, `primaryKey` and `uniqueKeys`, and each field holds `name`, `type`, `categories`, `categoriesOrdered` and `missingValues`. No other Frictionless property is allowed, so a misspelt property in a field descriptor is an error (E1403). Field names must be unique (E2002).

- `type` is one of 'string', 'integer', 'number', 'boolean', 'date' and 'datetime'. The lexical form of each type, and the reading of a value that does not have it, are those of [tables.md](tables.md), which writes out the Frictionless defaults. A column of another Frictionless type is declared without a type.
- `categories` lists the values a column may take, either as plain values or as objects with a `value` and an optional `label`, never both forms in one list (E2014). Categories are allowed only on fields of type 'string' or 'integer' (E1404, or E1419 without a type), their values must have the field's type (E2013) and may not repeat (E2015). Their order gives the order of the levels, which the IR uses before any other order (ir.md). The column must hold no other value that is not missing, whether or not a formula reads it: the table reader refuses any other value with E5007, and `audit()` refuses one in a data frame with E5012, for the reason that [tables.md](tables.md) (Missing values) gives. `categoriesOrdered` is true for ordered categories, such as an ordinal item, and needs `categories` (E1419).
- `missingValues` lists the strings that stand for a missing value, either as plain strings or as objects with a `value` and an optional `label`, which declare labelled sentinel codes such as '-99'. One list holds one form (E2014) and no repeated value (E2015). A field's list replaces the table's list for that field, and an empty list declares that no value is missing.
- `primaryKey` lists the columns whose values identify a row, and `uniqueKeys` lists further sets of columns whose values must be unique. The table reader checks both ([tables.md](tables.md), Keys).

Identifier columns cannot list categories (E2016), so that a declaration never carries the identifiers of persons or other units (02-decisions.md, Q4). An identifier column is a column named in the `columns` of a unit or declared in `variables` with the role 'id'.

Frictionless tools read the table block as a Table Schema, with three caveats (02-decisions.md, Q4):

1. The default `fieldsMatch` of Frictionless is 'exact', so the fields must describe every column of the data, in order. The table block cannot carry `fieldsMatch`, and the table reader applies 'exact' too, so that mixedcheck and a Frictionless tool agree on which data match the block.
2. In Frictionless v2, a field without a type has the type 'any', which declares no type. mixedcheck reads such a column as text, without conversion. The value 'any' is not in the subset, and a field of type 'any' is written without a type.
3. The R package frictionless (2.0.1) does not support categories, which its NEWS for 2.0.0 lists as not yet supported with `fieldsMatch`, so it cannot use the categories or their order. mixedcheck reads them itself in both languages.

Without `missingValues` in the table block, the Frictionless default `[""]` applies, and the table reader applies it explicitly (02-decisions.md, Q4 and tables.md, Missing values).

### units

`units` lists the grouping units of the design. Each unit has these members:

- `name`, unique among units (E2001), which other members use to refer to the unit
- `columns`, the columns whose values together label a member of the unit, usually one
- `nested_in`, the declared unit whose members contain the members of this unit
- `id_scope`, required with `nested_in` and allowed only with it (E1419). With 'global', a label denotes the same member wherever it appears, so a label found under two parent members means mobility, crossing or an error. With 'within_parent', labels are unique only within a parent member, so a member is identified by its parent member and its label.
- `membership`, allowed only with `nested_in` (E1419). With 'fixed', the default, each member stays in one parent member. With 'may_change_over_time', a member may move between parent members, as a pupil may change school, and `/observation/time` is required (E2026). With 'multiple', a member belongs to several parent members at once, which the 1.x releases do not model and report as such.
- `role`, which says what the members are: 'participant', 'item', 'cluster', 'site', 'family', 'dyad', 'rater', 'session', 'trial', 'channel' or 'other'

Every unit name that another member gives must be declared (E2006), and no unit may be nested in itself, directly or through other units (E2010).

`disclosure_unit`, at the top level, names the declared unit whose distinct members the privacy rules count (E2006 if it is not declared). Without it, the default of conventions.md (Declaration fields) applies.

### crossings

Each entry of `crossings` names two distinct declared units in `units` whose members are crossed, such as subjects and items, so that a label of one unit shared across members of the other denotes the same member. `list` names the column that holds the counterbalancing list, if there is one. A pair may appear only once, in either order (E2005), and a unit cannot be crossed with a unit it is nested in (E2011).

### observation

`observation` says what one row of the data is.

- `unit` names the declared unit of which each row is one member, so that no two rows belong to the same member. It is left out when a row is not a member of a declared unit, such as a trial of a subject on an item or a pupil on one occasion.
- `key` lists the columns whose values together identify a row. It identifies rows in the internal sidecar (conventions.md) and is the reference for duplicate checks, and it is usually equal to the table's `primaryKey`.
- `time` places a row in time with its `column` and `kind`, and `within` names the declared unit within whose members time runs, such as the pupil for waves. Without `within`, time is common to all rows. The kind 'occasion' is an ordered measurement occasion such as a wave. 'timestamp' is a date or a date and time, compared as written. 'trial_index' is the position of a trial within a member of the `within` unit. 'duration_since_start' is the time elapsed since a start, as a number. Time zones and clock resolution follow in a later vocabulary.

### assignment

Each entry of `assignment` describes one assigned variable, and a column can be assigned only once (E2004).

- `column` is the assigned column. A `variables` entry for it, if there is one, must have the role 'assigned' (E2018).
- `unit` names the declared unit whose members were assigned. When the assignment was randomised, it is the randomisation unit.
- `randomised` is true when values, or sequences of values, were assigned to the members of the unit at random, and false otherwise.
- `level` is 'between_unit' when the column is constant within each member of the unit, as in a cluster-randomised trial, and 'within_unit' when it varies within each member, as in crossover, stepped-wedge and counterbalanced designs. Without it, the level is inferred from the data and reported with 'inferred' wording.
- `blocks` names the declared units within whose members assignment was made, such as the schools of a trial randomised within schools.

### variables

`variables` maps column names to their roles. With a table block, each key must be a field of it (E2007).

| Role | Meaning |
|---|---|
| outcome | a response the model explains, read only at tiers T1 and T2 |
| assigned | a variable whose values the investigators assigned |
| baseline_covariate | a covariate measured before assignment, or before the outcome period, and unaffected by it |
| time_varying_covariate | a covariate measured on each occasion |
| post_assignment_covariate | a covariate measured after assignment, which assignment may have affected |
| mediator | a variable on a path from an assigned variable to an outcome |
| outcome_derived | a column computed from an outcome, such as a lagged outcome, treated as part of the outcome in outcome-blind mode |
| time | a time variable |
| block | a blocking variable |
| weight | an observation weight |
| offset | a known offset of the linear predictor, other than an exposure |
| exclusion_flag | a column that marks rows to exclude |
| id | an identifier |
| auxiliary | any other declared column |

`measurement` gives the measurement level, using the outcome types of 02-decisions.md (Q2):

| Measurement | Meaning |
|---|---|
| continuous | a continuous measure without declared bounds |
| binary | two values, one of which is the event |
| binomial | the number of events k out of n trials, with n in the trials column |
| count | a count of events, with an optional exposure |
| bounded_score | a score between declared bounds |
| ordinal | ordered categories, such as a single Likert item |
| positive_duration | a positive duration, such as a response time |

The other members of an entry are these. The schema allows each only where stated and reports a misplaced one with E1404 and a missing one with E1402.

- `derived_from` lists the columns this column was computed from. A column derived from an outcome or an outcome-derived column must have the role 'outcome' or 'outcome_derived' (E2020), and no column may be derived from itself, directly or through other columns (E2012).
- `bounds` gives the lowest and highest possible values, in that order (E2017), and is required for a bounded_score and allowed for nothing else.
- `event_level`, allowed for an outcome measured as binary, gives the category value that counts as the event and is coded 1 (conventions.md, Declaration fields). With a typed table field, it must have the field's type, a string for a string field and an integer for an integer or number field, and a field of another type cannot have one (E2023). When the field lists categories, the event level must be one of them (E2024).
- `trials`, required for an outcome measured as binomial and allowed for nothing else, names the column that holds the number of trials.
- `exposure`, allowed for an outcome measured as count, names the column that holds the exposure and its scale, 'raw' or 'log'.

### estimands

Each entry of `estimands` declares an estimand: a fixed-effect term in the model of an outcome. IDs must be unique (E2003).

- `id` is a name, as for units.
- `term` is one variable, or an interaction of variables joined by ':', with this grammar in the EBNF of ISO/IEC 14977:

  ```ebnf
  term     = variable, { ":", variable } ;
  variable = bare | quoted ;
  bare     = letter, { letter | digit | "." | "_" } ;
  quoted   = "`", character, { character }, "`" ;
  letter   = "A" | ... | "Z" | "a" | ... | "z" ;
  digit    = "0" | ... | "9" ;
  ```

  where a character is any character other than the backquote (U+0060), the backslash (U+005C) and the control characters U+0000 to U+001F and U+007F to U+009F. The schema checks this form (E1406, with the form 'estimand term'). A variable names a column. A name of the bare form may be written bare or between backquotes, any other name between backquotes, and the name is the text without the backquotes. A variable may contain no character outside the Basic Multilingual Plane (E1207), may appear only once in a term (E2008) and, with a table block, must be a field of it (E2007). The estimand refers to the fixed-effect term of the IR whose variables are the same set (ir.md), so 'arm:pre' and 'pre:arm' refer to the same term.
- `kind` says what the estimand is. 'total_effect' is the effect through all paths, which adjustment for a post-assignment covariate or a mediator biases. 'direct_effect' is the effect not through the declared mediators. 'association' is a difference or a slope with no causal claim.
- `focal` is true when the estimand is focal, which places its slopes in the protected set (02-decisions.md, Q3). Absent, it is true.
- `outcome` names the outcome column of the estimand, which must have the role 'outcome' (E2021). It is required when more than one outcome is declared (E2022), and otherwise the estimand refers to the one declared outcome, if there is one.

An outcome column cannot appear in the term of an estimand (E2019).

### provenance

`provenance` records where the declaration comes from.

- `created` is the UTC time at which the declaration was written.
- `author` names the person who wrote it, in up to 200 characters.
- `outcome_seen` is true when the outcome had been seen when the declaration was written, as for secondary data. It is an attestation, which the package cannot verify (02-decisions.md, Q3).
- `data_commitment` is a keyed commitment to the data the declaration describes, covering a raw data file or the canonical analysis table (conventions.md, Keyed commitments). The key stays in the internal sidecar, so the declaration can be shared.
- `inferred` lists the JSON Pointers of the entries that `draft_design()` inferred from the data and the user has not yet accepted (M3).

A declaration with `inferred` is a draft. Each pointer must point to an existing value other than the whole declaration, `/vocabulary` and `/provenance` or anything under it (E2009). A draft is valid, but until the user accepts it, the entry that a pointer of `inferred` points to, with everything under it, counts as absent for every check, as a field that was never declared does: a check that needs it reports not_available with the reason declaration_missing and the pointer of the field it needs (02-decisions.md, Q4). Properties that the data can show, such as the level at which an assigned variable varies, are inferred by the checks themselves and reported with 'inferred' wording. Removing a pointer from the list accepts that entry, and removing the list accepts the draft. The validator itself checks a draft as written, inferred entries included, so that accepting them cannot make a valid draft invalid. A draft cannot serve as a minimal declaration (E2032), because a draft counts as a declaration only once the user has accepted it (02-decisions.md, Q4).

`draft_design()` reads only the grouping columns of a formula and lists every entry it writes in `inferred`: a unit for each grouping column that is not a predictor, nesting with id_scope 'global' where each label of a unit meets one label of another unit and not the reverse, crossings where a label of each of two units meets several of the other, an observation key among the grouping columns and the role 'outcome' of the response, named from the formula. It never infers id_scope 'within_parent', since reused labels look like crossed units in the data. The builders `declaration()` and `declare_*()` assemble a declaration in memory, which then crosses the input boundary like any other value.

## Validation

### Order of checks

The validator works in five stages and stops after the first stage that reports an issue.

1. Reading. The declaration is read as described under Documents, versions and hashes, which reports at most one issue.
2. Version. If the value is an object whose member `vocabulary` is a string, the string must match `^0\.1\.(0|[1-9][0-9]*)$` and have at most 32 characters. Otherwise, E1441 is reported at `/vocabulary` alone, with the supported version '0.1.x', and nothing else is checked. A missing or non-string `vocabulary` is left to the next stage.
3. Structure. The value is checked against declaration.schema.json as errors.md (Structural validation) describes, together with three checks that complete the schema: no column name and no variable of an estimand term that matches the pattern of a term contains a character outside the Basic Multilingual Plane (E1207, once for the term), and the day of `/provenance/created` exists in its month (E1406). Patterns are matched over code points (conventions.md, Schemas), so a column name with a character outside the Basic Multilingual Plane also fails the pattern of a column name and gets E1406 beside E1207. The schema's reference to `hashable_value` is not checked again, because the reader or writer has enforced the profile.
4. Names and references, the first step of the rules in code.
5. Meaning, the second step of the rules in code, including the minimal declaration when it applies.

Stages 3 to 5 report every issue they find, sorted by JSON Pointer, compared code point by code point with a prefix first, then by code and then by message, and capped at 100 with W1490, as errors.md (Reporting rules) describes. Stages 4 and 5 make up the second phase of errors.md, divided into two steps so that the rules of stage 5 run only on a declaration whose names are unique and whose references resolve.

Locations are JSON Pointers into the declaration as read (RFC 6901), with '~' written as '~0' and '/' as '~1' in each token, so that the entry of the column 'a/b' in `variables` is `/variables/a~1b`. Values are equal when errors.md (Structural validation) says so, which compares strings by code points and numbers by value. Strings need no normalisation here, because a hashable document holds NFC strings only.

### Terms used by the rules

- A declared unit is an entry of `units`, and a reference to a unit resolves when a unit of that name exists.
- A field is an entry of `/table/fields`, and a column reference resolves when a field of that name exists. Column references are checked only when the table block is present.
- An outcome column is a key of `variables` whose role is 'outcome', and an outcome-derived column one whose role is 'outcome_derived'.
- An identifier column is a column named in the `columns` of a unit or a key of `variables` whose role is 'id'.
- An assigned variable is the `column` of an entry of `assignment` or a key of `variables` whose role is 'assigned'.
- The variables of a term are its bare names and its quoted names without the backquotes, in the order written.
- A focal estimand is an estimand whose `focal` is absent or true.
- A JSON Pointer resolves when RFC 6901 evaluation finds a value in the declaration. An array index token must be '0' or a decimal number without leading zeros below the length of the array.

### Stage 4: names and references

| Code | Rule | Location |
|---|---|---|
| E2001 | A unit name differs from the names of all earlier units. | `/units/i/name` of each later unit |
| E2002 | A field name differs from the names of all earlier fields. | `/table/fields/i/name` of each later field |
| E2003 | An estimand ID differs from the IDs of all earlier estimands. | `/estimands/i/id` of each later estimand |
| E2004 | An assigned column differs from the columns of all earlier entries of `assignment`. | `/assignment/i/column` of each later entry |
| E2005 | A crossing pairs two units that no earlier crossing pairs, in either order. | `/crossings/i/units` of each later crossing |
| E2006 | A unit reference resolves. | each of `/units/i/nested_in`, `/crossings/i/units/j`, `/observation/unit`, `/observation/time/within`, `/assignment/i/unit`, `/assignment/i/blocks/j` and `/disclosure_unit` that does not resolve |
| E2007 | With a table block, a column reference resolves. | each of `/units/i/columns/j`, `/crossings/i/list`, `/observation/key/j`, `/observation/time/column`, `/assignment/i/column`, `/variables/c` (the key c itself), `/variables/c/derived_from/j`, `/variables/c/trials`, `/variables/c/exposure/column`, `/estimands/i/outcome`, `/table/primaryKey/j` and `/table/uniqueKeys/i/j` that does not resolve, and `/estimands/i/term` once for each distinct variable of the term that does not resolve, naming it |
| E2008 | No variable appears twice in a term. | `/estimands/i/term`, once for each repeated variable, naming it |
| E2009 | A pointer in `/provenance/inferred` resolves and is not '', `/vocabulary`, `/provenance` or a pointer that starts with `/provenance/`. | `/provenance/inferred/j` |

### Stage 5: meaning

The rules of this stage run only when stages 3 and 4 found no issue, so every name is unique and every reference resolves. The rules on goals and features run always, and those of the minimal declaration when it applies.

| Code | Rule | Location |
|---|---|---|
| E2010 | No unit is nested in itself. Following `nested_in` from a unit never leads back to it. | `/units/i/nested_in` of each unit on a cycle |
| E2011 | Neither unit of a crossing is an ancestor of the other. The ancestors of a unit are the units reached by following `nested_in` from it, stopping when a unit repeats. | `/crossings/i/units` |
| E2012 | No column is derived from itself. Following `derived_from` from a key of `variables` through columns that have entries in `variables` never leads back to it. | `/variables/c/derived_from` of each such column |
| E2013 | Each category of a field of type 'string' is a string, and each category of a field of type 'integer' is an integer, for plain values and for the `value` of objects. | `/table/fields/i/categories/j`, or `/table/fields/i/categories/j/value` for an object |
| E2014 | A list of categories or missing values holds only plain values or only objects. | the list: `/table/missingValues`, `/table/fields/i/missingValues` or `/table/fields/i/categories` |
| E2015 | No value of such a list repeats an earlier value of the same list, comparing plain values and the `value` of objects. | the later item, `/…/j` |
| E2016 | An identifier column lists no categories. | `/table/fields/i/categories` |
| E2017 | The first bound is less than the second. | `/variables/c/bounds` |
| E2018 | A `variables` entry for an assigned column of `assignment` has the role 'assigned'. | `/variables/c/role` |
| E2019 | No outcome column is used where the design is described. | each of `/units/i/columns/j`, `/crossings/i/list`, `/observation/key/j`, `/observation/time/column`, `/variables/c/trials`, `/variables/c/exposure/column`, `/table/primaryKey/j` and `/table/uniqueKeys/i/j` that names an outcome column, and `/estimands/i/term` once for each distinct outcome column among its variables, naming it |
| E2020 | A column whose `derived_from` names an outcome or outcome-derived column has the role 'outcome' or 'outcome_derived'. | `/variables/c/role` |
| E2021 | The `outcome` of an estimand is an outcome column. | `/estimands/i/outcome` |
| E2022 | When more than one outcome column is declared, every estimand names its outcome. | `/estimands/i` |
| E2023 | When the table declares the field of an event level with a type, the event level matches it: a string for 'string' and an integer for 'integer' or 'number'. No event level matches 'boolean', 'date' or 'datetime'. | `/variables/c/event_level` |
| E2024 | When E2023 is satisfied and the field lists categories, the event level equals one of them. | `/variables/c/event_level` |
| E2025 | Each feature has the members it requires (Features). | `/features/j`, once for each missing requirement, naming it as `/assignment` or `/observation/time` |
| E2026 | A unit whose membership is 'may_change_over_time' has `/observation/time`. | `/units/i/membership` |
| E2027 | With the feature observational, there is no assignment block, no `variables` entry with the role 'assigned' and none of the features cluster_randomised, stepped_wedge and partially_nested. | `/assignment`, `/variables/c/role` and `/features/j` for each contradicting entry |

The outcome may appear in `derived_from` and as the `outcome` of an estimand. An assigned column that is also an outcome is reported by E2018 alone.

### The minimal declaration

A minimal declaration declares what Stream B needs to plan an analysis before the outcome is seen: the units, what a row is and how rows are identified, at least one outcome, at least one focal estimand and an assigned variable unless the study is observational (02-decisions.md, Q4). The validator applies the rules below in stage 5 when the goal is 'confirmatory', when `features` holds cluster_randomised, stepped_wedge or partially_nested, or when the caller passes the argument `minimal` as true, which the outcome-blind and preregistration exports of M3 do. The argument is `minimal = FALSE` in R and `minimal=False` in Python.

| Code | Rule | Location |
|---|---|---|
| E2028 | `units`, `observation`, `variables` and `estimands` are present, and `observation` has `key`. | '' for a missing block, naming it, and `/observation` for a missing key |
| E2029 | `variables` declares at least one outcome column. | `/variables` |
| E2030 | The declaration has an assigned variable or the feature observational. | '' |
| E2031 | `estimands` holds at least one focal estimand. | `/estimands` |
| E2032 | The declaration is not a draft. | `/provenance/inferred` |

An empty block cannot satisfy these rules, because the schema rejects empty blocks (E1413 and E1416). E2029 and E2031 apply only when the block they check is present, since E2028 reports a missing block. The trial features require the assignment block as well (E2025), so an exploratory cluster-randomised trial without estimands gives E2028 for the missing block, among the other rules of the minimal declaration it breaks.

### Reporting

Each issue has its code, its rendered message and its JSON Pointer, and the codes are rendered as errors.md describes. The arguments are these: {name} is the repeated name or column of E2001 to E2004, the undeclared unit of E2006, the unresolved column of E2007, the repeated variable of E2008, the unit of E2010, the key of `variables` of E2012 and E2020, the field of E2016, the assigned column of E2018, the outcome column of E2019 and the named outcome of E2021. {pointer} of E2009 is the pointer as listed. {type} of E2013 is 'a string' or 'an integer', and {type} of E2023 is the type of the field. {value} of E2015 is the repeated value and {value} of E2024 the event level. {feature} and {required} of E2025 are the feature and '/assignment' or '/observation/time', and {key} of E2028 is the missing member. For example, the faulty declaration of the Example section gives these four issues, in this order:

```text
E2031 /estimands           The estimands at /estimands include no focal estimand, which a minimal declaration requires.
E2025 /features/1          The feature 'longitudinal' at /features/1 requires '/observation/time' to be declared.
E2019 /observation/key/4   The outcome column 'post' cannot be used at /observation/key/4.
E2018 /variables/arm/role  The column 'arm' is in the assignment block, so its role at /variables/arm/role must be 'assigned'.
```

## YAML authoring

A declaration may be written in YAML, which is read with every scalar as a string and converted to JSON as conventions.md (YAML authoring) describes, with the codes E3001 to E3010. Mappings become objects, sequences become arrays and every scalar becomes a string, which is then coerced to the type that declaration.schema.json requires at its position. The converted value is then checked against the hashable profile as a writer checks a value in memory and validated as a JSON declaration, from stage 2 on.

In a declaration, the schema requires a type other than string at these positions only:

| Position | Type | Written as |
|---|---|---|
| `/table/fields/i/categoriesOrdered`, `/assignment/i/randomised`, `/estimands/i/focal`, `/provenance/outcome_seen` | boolean | 'true' or 'false' |
| `/variables/c/bounds/j` | number | the number grammar of RFC 8259, so that '0', '40' and '2.5' are accepted and '.5', '+1' and '1_000' are not |
| `/table/fields/i/categories/j`, `/table/fields/i/categories/j/value` and `/variables/c/event_level` | string or integer, by the type of the field | below |

A category value and an event level take the type of their field, so that their YAML text reads the same in both languages whatever it looks like. The field of a category is the field that holds it, and the field of the event level at `/variables/c/event_level` is the first entry of `/table/fields` whose `name` is c. If the `type` of that field in the YAML text is 'string', the scalar stays a string, and if it is 'integer', the scalar becomes an integer, or E3008 is reported with the type 'an integer' when its text does not match `^-?(0|[1-9][0-9]*)$`. Otherwise, as when there is no table block or the field has no type, the general rule of conventions.md applies, and the scalar becomes an integer if its text has that form and a string if not. Hence `categories: [0, 1]` gives the integers 0 and 1 in an integer field and the strings '0' and '1' in a string field, and quoting changes neither.

Every other scalar stays a string, including names, columns, versions, times, missing values, labels and terms. A scalar such as 'yes', 'no', '~' or '007' is therefore the string it spells, and at a boolean position 'yes' gives E3008. A scalar at a position where the schema allows only an object or an array, such as `units: none`, stays a string and is reported in stage 3 with E1401, as the same value in JSON would be. A scalar under an unknown key stays a string, and the key gives E1403.

The hash of a declaration written in YAML is the hash of its JSON form, so a YAML file and the JSON file it converts to have the same declaration hash. The YAML text itself is never hashed.

## Changes from the draft schema

The draft in evidence/decisions/E/schema/design.schema.json is the starting point. Vocabulary 0.1 applies the corrections of 02-decisions.md (Q4) and of the report's verifier, which the decision record adopts:

- `schema_version`, fixed at '0.1.0', is replaced by `vocabulary`, which accepts every 0.1.x version and is checked before anything else.
- The dyad, EEG and imputation blocks are removed, with the features dyadic, eeg and multiple_imputation, and are reported as unknown keys or values. The time zone and clock resolution of `observation.time` follow with them in a later vocabulary. The `x-` extension keys are removed, because unknown keys are errors.
- The goal 'prediction' and the estimand kind 'prediction' are removed until the prediction goal arrives after 1.0.
- Field descriptors accept only the five members of the subset, so a misspelt `categoriesOrdered` is an error. Field types are limited to six. A list of categories or missing values holds one form only, as Frictionless v2 requires. Categories are not allowed on identifier columns.
- `id_scope` and `membership` need `nested_in`, `disclosure_unit` is added and `observation.unit` is the unit of which each row is one member.
- An assignment states `randomised` and may state `level`, which replaces `time_varying`. `scheme` and `control_level` are removed. The scheme follows from the features, the level, randomisation and the blocks, and the reference level of a factor belongs to the IR.
- Measurement levels follow the outcome types of 02-decisions.md (Q2), adding 'binomial' and 'positive_duration' and removing 'proportion' and 'response_time'. Outcomes gain `event_level`, `trials` and `exposure`.
- Estimands gain `outcome` and lose `contrast`, and a term has a grammar.
- `provenance.data_hash`, an unkeyed SHA-256 of the data, is replaced by the keyed `data_commitment`, because an unkeyed hash of person-level data works as an oracle. `inferred` marks the entries of a draft, which the draft schema could not do without breaking its own rule on unknown keys.
- The requirements of goals and features, references, cycles and roles across blocks are checked in code with codes of their own. The feature multisite no longer requires an assignment block, and the feature observational is added so that an observational study can form a minimal declaration.
- Empty lists and objects are rejected where they would mean the same as an absent block.

Examples ex1, ex2, ex3 and ex5 of the draft carry over with these changes, whereas ex4 (dyads) and ex6 (EEG) use blocks that vocabulary 0.1 does not have.

## Example

This declaration of a cluster-randomised trial, written in YAML, is valid and minimal:

```yaml
vocabulary: 0.1.0
title: Reading intervention, classes randomised within schools
goal: confirmatory
features: [cluster_randomised, longitudinal]
table:
  fields:
    - {name: school, type: string}
    - {name: class, type: string}
    - {name: pupil, type: string}
    - {name: wave, type: integer, categories: [0, 1], categoriesOrdered: true}
    - {name: arm, type: string, categories: [control, tutoring]}
    - {name: pre, type: number}
    - name: post
      type: number
      missingValues:
        - value: ''
        - {value: '-99', label: absent on test day}
units:
  - {name: school, columns: [school], role: cluster}
  - {name: class, columns: [class], nested_in: school, id_scope: within_parent, role: cluster}
  - {name: pupil, columns: [pupil], nested_in: class, id_scope: global, role: participant}
observation:
  key: [school, class, pupil, wave]
  time: {column: wave, kind: occasion, within: pupil}
assignment:
  - {column: arm, unit: class, randomised: true, level: between_unit, blocks: [school]}
variables:
  post: {role: outcome, measurement: bounded_score, bounds: [0, 40]}
  pre: {role: baseline_covariate, measurement: bounded_score, bounds: [0, 40]}
estimands:
  - {id: ITT, term: arm, kind: total_effect}
provenance: {created: '2026-11-08T09:00:00Z', outcome_seen: false}
```

The categories of `wave` become integers and those of `arm` strings, the booleans and bounds take their types and everything else stays a string. The canonical bytes of the converted declaration, 1,352 bytes on one line, begin

```text
{"assignment":[{"blocks":["school"],"column":"arm","level":"between_unit","randomised":true,"unit":"class"}],"estimands":[{"id":"ITT","kind":"total_effect","term":"arm"}],...
```

and end with `"vocabulary":"0.1.0"}`. The declaration hash is `sha256:93ed460de965c328571efe40719f1d80debb72ae532653f68fca4c301226b8c0`, as the rfc8785 Python package, used as an oracle, also gives.

The faulty declaration of the Reporting section differs from this one in four places: `arm` is declared in `variables` with the role 'baseline_covariate', `post` is added to the observation key, `observation.time` is removed and the estimand has `focal: false`. Its structure is valid and its names and references resolve, so all four issues come from stage 5. If instead the class were nested in 'schools' and the assignment blocked on 'School', stage 4 would report E2006 at `/assignment/0/blocks/0` and at `/units/1/nested_in`, and stage 5 would not run.

## References

Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation (JSON) Pointer (RFC 6901). Internet Engineering Task Force. https://doi.org/10.17487/RFC6901

Frictionless Data. (2024). Table Schema (version 2.0). https://datapackage.org/standard/table-schema/

International Organization for Standardization. (1996). Information technology: Syntactic metalanguage: Extended BNF (ISO/IEC 14977:1996).

Wright, A., Andrews, H., Hutton, B., & Dennis, G. (2022). JSON Schema: A media type for describing JSON documents (draft 2020-12). https://json-schema.org/draft/2020-12/json-schema-core
