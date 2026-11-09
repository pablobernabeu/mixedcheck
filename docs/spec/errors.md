# Error codes

[spec/errors.json](../../spec/errors.json) is the one catalogue of error and warning codes that both packages use. Every failure of a reader, writer or validator maps to exactly one code, and both packages render the same message for it. This document describes the catalogue, the rendering of its message templates and the rules that decide which issues a validator reports and in which order. The conventions behind the codes of areas input to schema and yaml are in [conventions.md](conventions.md), and those of the table area in [tables.md](tables.md).

## The catalogue

spec/errors.json is an object with three members.

- description: what the file is.
- areas: one object per area, with the area's identifier, the first and last numbers of its range, a title and a description. Ranges do not overlap.
- codes: one object per code, in ascending order of number.

Each code has these members:

- code: 'E' for an error or 'W' for a warning, followed by four digits. No number is used twice, whether with 'E' or with 'W', and the number lies in the range of the code's area.
- name: a unique identifier in snake_case that starts with the area's identifier and '_', such as json_duplicate_key. Code in both packages refers to codes by these names.
- area: the area's identifier.
- location: 'offset' for a byte offset into the input, 'pointer' for a JSON Pointer into a value, 'offset_or_pointer' for a code that readers report with an offset and writers with a pointer, or 'none'.
- template: the message, with placeholders. It contains '{location}' exactly when the location is not 'none'.
- args: an object that maps the name of each other placeholder to the kind of its value (below).
- languages: present only for a code that one language alone can raise, such as E1204 for unmarked strings in R. The parity harness does not expect such a code from the other language.
- retired: present only for a code that is no longer raised, giving the version of the schemas from which it is not.

Codes are added in the area that owns them, at the next free number, and are never renumbered, reused or deleted. A template is ASCII text in British English, written as one or more complete sentences that state what is wrong and where, with quoted values in single quotation marks. It contains no braces other than its placeholders. spec/tools/test_errors.py checks these rules and that every code appears in the tables below.

## Areas

| Area | Codes | Covers |
|---|---|---|
| input | 1000 to 1019 | files that cannot be opened and inputs that start with a byte-order mark, for every reader |
| json | 1020 to 1099 | the syntax of JSON text and the rules of the strict reader on keys, surrogates, literals, numbers and nesting |
| profile | 1100 to 1199 | the rules of the hashable and data profiles, applied by readers and writers |
| unicode | 1200 to 1299 | UTF-8 validity, NFC, encoding marks in R and surrogates in Python |
| canonical | 1300 to 1309 | in-memory values that have no JSON form |
| hash | 1310 to 1399 | commitment keys, commitments and recorded hashes |
| schema | 1400 to 1499 | violations of JSON Schema keywords and unsupported versions, for every document validator |
| declaration | 2000 to 2999 | rules of declaration vocabulary 0.1 enforced in code, including the table block |
| yaml | 3000 to 3999 | reading YAML sources and converting them to JSON |
| registry | 4000 to 4999 | registry sources, the compiler and loading of the compiled registry |
| table | 5000 to 5999 | reading data tables against the declared table block ([tables.md](tables.md)) |
| formula | 6000 to 6999 | the formula grammar, term expansion and the canonical IR |
| results | 7000 to 7299 | results documents, their access log section and the internal sidecar |
| plan | 7300 to 7599 | plans |
| estimates | 7600 to 7899 | bring-your-own estimates |
| internal | 9000 to 9999 | failed internal checks, which indicate a bug |

Numbers 1500 to 1999, 7900 to 7999 and 8000 to 8999 are not assigned. The areas declaration to estimates belong to the specifications of those components, which add their codes. A failure of a structural JSON Schema keyword in any document is reported with the codes of the schema area, and the component areas hold the rules that JSON Schema cannot express.

## Rendering messages

A message is the template with each placeholder replaced by its argument, rendered according to its kind:

| Kind | Rendering |
|---|---|
| location | an offset n as 'byte n', and a pointer as itself after display escaping, or as '(root)' for the empty pointer |
| text | the string after display escaping, truncated to 60 code points |
| integer | decimal digits, with '-' before a negative value and no grouping |
| number | the double as conventions.md (Serialisation) writes it, such as '1e-307' or '0.5' |
| codepoint | upper-case hexadecimal digits, padded with zeros to at least four |
| values | each JSON value in turn: a string in single quotation marks after display escaping and truncation, a number as the kind number writes it and true, false or null as written. The items are joined by ', ', except the last two, which are joined by ' or '. |
| words | each word as it is, joined as for values |

Some arguments have a stated source, so that both packages render the same text:

- {number} of E1102 to E1106 is the token as written for a reader, the scalar's text for a value converted from YAML, the serialisation of the double (conventions.md, Serialisation) for a double that a writer refuses and the decimal digits, with '-' for a negative value, for a Python int.
- {form} of E1406 is the title of the schema object that holds the pattern, and {form} of E1418 the title of the propertyNames schema or, when it has none, of the first schema that its $ref chain reaches (conventions.md, Schemas).
- The arguments of the table area are defined in [tables.md](tables.md) (Errors) and those of the formula area in [ir.md](ir.md) (Errors).

Display escaping replaces each code point from U+0000 to U+001F, from U+007F to U+009F and U+2028 and U+2029 by '\u' and four upper-case hexadecimal digits, and leaves every other character unchanged. Truncation counts code points after escaping and, if there are more than 60, keeps the first 57 and appends '...'. For example, E1029 for the key 'go' followed by a tab and 'al', at offset 45, renders as `Duplicate key 'go\u0009al' at byte 45.`, and E1405 at /observation/time/kind with the values of the enum ['occasion', 'timestamp', 'trial_index', 'duration_since_start'] renders as `The value at /observation/time/kind must be 'occasion', 'timestamp', 'trial_index' or 'duration_since_start'.`

When the input came from a file, a package may put the file's name and ': ' before the message it shows. The rendered message without that prefix is what the packages compare.

## Issues and conditions

An issue is one reported problem: a code, its rendered message and its location, which is a byte offset, a JSON Pointer or nothing, as the code's location member allows. Its JSON form is `issue` in [defs.schema.json](../../spec/schemas/defs.schema.json), with the member offset or pointer.

In R, an error is signalled as a condition of class `c("mixedcheck_error", "error", "condition")` and a warning as one of class `c("mixedcheck_warning", "warning", "condition")`. In Python, an error is raised as `MixedcheckError`, a subclass of ValueError, and a warning is issued as `MixedcheckWarning`, a subclass of UserWarning. In both, the condition carries the list of issues as `issues`, each with `code`, `message` and `offset` or `pointer`, and its own message is the message of the first issue, followed by one line for each further issue. Where the YAML parser reports the problem, the YAML reader also attaches the parser's own message (conventions.md, YAML authoring): to E3002 in both languages and to E3007 in R, whose yaml package detects duplicate keys. R adds it as a last line of the condition's message, and Python makes PyYAML's exception the cause (`__cause__`) of the error. The parity harness compares lists of issues, not the messages of conditions.

## Reporting rules

A reader reports one issue, the first that its stages find (conventions.md, Strict reader). A writer reports one issue, the first violation in the order of the canonical serialisation.

A validator first checks the document's version, if its schema has a version member, and reports only E1441 when the version lies outside the lines the release supports. It then works in two phases. The first checks the value against the document's schema and reports every structural issue under the rules below. The second runs only when the first found none, and applies the rules enforced in code, reporting every issue it finds with the codes of the document's area. This keeps a rule such as referential integrity from running on a document whose structure is already wrong. A document's specification may divide the second phase into steps, each run only when the steps before it found no issue and each sorted and capped on its own, as [declarations.md](declarations.md) does.

The issues of a phase are sorted by their JSON Pointer, then by code and then by rendered message, each compared code point by code point without normalisation, with a prefix first. In R, this is `order(..., method = "radix")` on strings that are ASCII or marked UTF-8, never the default collation of the locale. The pointer '/a/10' therefore comes before '/a/9'. Issues with the same pointer, code and message, such as those that a schema and the schema it refers to both give, are reported once. If there are more than 100 issues, the first 100 in this order are reported, followed by W1490 giving the number left out.

## Structural validation

A validator checks every keyword of the schema that applies at each position and reports issues as follows.

| Keyword | Code | Location | Arguments |
|---|---|---|---|
| type | E1401 | the value | expected: the types the keyword allows, in the schema's order. found: the value's type, one of object, array, string, number, boolean and null |
| required | E1402 | the object | key: one issue for each missing member |
| additionalProperties false | E1403 | the object | key: one issue for each member not allowed |
| a member whose schema is false | E1404 | the object | key |
| enum, const | E1405 | the value | allowed: the values of enum in the schema's order, or the value of const |
| pattern | E1406 | the value | form: the title of the schema object that holds the pattern |
| minLength, maxLength | E1407, E1408 | the value | limit |
| minimum, maximum | E1409, E1410 | the value | limit |
| exclusiveMinimum, exclusiveMaximum | E1411, E1412 | the value | limit |
| minItems, maxItems | E1413, E1414 | the array | limit |
| uniqueItems | E1415 | each item equal to an earlier item | none |
| minProperties, maxProperties | E1416, E1417 | the object | limit |
| propertyNames | E1418 | the object | key and form, the title of the propertyNames schema or of the first schema its $ref chain reaches, for each key that fails |
| dependentRequired | E1419 | the object | key and required, for each missing member |
| contains | E1420 | the array | none |
| anyOf or oneOf matched by no alternative | E1421 | the value | none |
| oneOf matched by more than one alternative | E1422 | the value | none |
| not, or a false schema other than a member's | E1423 | the value | none |

Lengths count code points. A number is an integer when its value is, so 1.0 satisfies `"type": "integer"`. Two values are equal, for enum, const and uniqueItems, when they have the same type and, for numbers, the same value, for strings the same code points, for arrays equal items in the same order and for objects the same keys with equal values. Strings are compared without NFC normalisation, because documents in the hashable profile hold NFC strings only.

The keywords combine as follows.

1. $ref applies the referenced schema at the same position. allOf applies each subschema. properties, patternProperties and additionalProperties with a schema apply to the members' values, and items and prefixItems to the items.
2. if is evaluated without reporting anything, and then the issues of then or else are reported.
3. When a value fails a type keyword that applies to it unconditionally, only one E1401 is reported for it, listing the types of the first such keyword that fails, and nothing else is reported at that value or below it. A type keyword applies unconditionally when it belongs to the schema object itself or is reached from it through $ref, allOf or the branch of if that applies, taken in that order and recursively, each subschema in turn. Type keywords under anyOf, oneOf, not, contains and propertyNames do not count here.
4. The value of a member reported by E1403 or E1404 is not checked.
5. When no alternative of anyOf or oneOf matches, the validator looks for the alternatives whose type keyword, at the alternative's top level, allows the value's type, counting an alternative without a type keyword as allowing every type. If exactly one alternative qualifies, its issues are reported as if it were the only schema. Otherwise, E1421 is reported and nothing below it.
6. not, contains and propertyNames report only their own codes, never the issues of their subschemas.

The rules that defs.schema.json states in descriptions are checked with these codes: the day of a utc_timestamp or date (E1406, with the form named by the definition's title), the significant digits of a decimal_constant (E1406 at its member value, with the form 'decimal constant') and characters outside the BMP in a column_name (E1207). They belong to the first phase, since they complete the structural check of a definition. The jsonschema oracle used in the tests confirms whether a document is valid under its schema. It does not check these rules, and it does not supply codes, which come from this document.

## Codes

### input

| Code | Name | Raised when |
|---|---|---|
| E1001 | input_file_missing | the file to read does not exist |
| E1002 | input_file_unreadable | the file exists but cannot be read, for example a directory or a file without read permission |
| E1003 | input_byte_order_mark | the input starts with the bytes EF BB BF |

### json

| Code | Name | Raised when |
|---|---|---|
| E1021 | json_unexpected_end | the input ends where the grammar needs more, including an empty input |
| E1022 | json_unexpected_character | a byte cannot continue the JSON text and no more specific code applies |
| E1023 | json_trailing_content | a byte other than white space follows the top-level value |
| E1024 | json_control_character | a string contains a raw byte from 00 to 1F |
| E1025 | json_invalid_escape | a backslash in a string starts no valid escape |
| E1026 | json_lone_surrogate | a string or key contains an unpaired surrogate escape |
| E1027 | json_nonfinite_literal | NaN, Infinity or -Infinity appears where a value is expected |
| E1028 | json_invalid_number | a run of number characters does not match the number grammar |
| E1029 | json_duplicate_key | a key equals an earlier key of the same object |
| E1030 | json_too_deep | containers nest more than 64 levels deep, in the input or in a value to be written |

### profile

| Code | Name | Raised when |
|---|---|---|
| E1101 | profile_null | a null, or a missing value in memory, appears in the hashable profile |
| E1102 | profile_integer_range | an integer lies outside ±9007199254740991, in the hashable profile, or a Python int does in either profile |
| E1103 | profile_too_many_digits | a non-integer has more than 15 significant digits in the hashable profile |
| E1104 | profile_number_too_small | a non-zero non-integer is smaller in magnitude than 1e-307 in the hashable profile |
| E1105 | profile_number_overflow | a number converts to an infinite double |
| E1106 | profile_number_underflow | a non-zero number converts to zero |
| E1107 | profile_nonfinite | a writer meets NaN or an infinity in the hashable profile |
| E1108 | profile_key_outside_bmp | a key contains a character outside the BMP |
| E1109 | profile_empty_key | a key is the empty string |

### unicode

| Code | Name | Raised when |
|---|---|---|
| E1201 | unicode_invalid_utf8 | the input, or a string marked UTF-8 in R, is not valid UTF-8 |
| E1202 | unicode_nul | a string or key contains U+0000 |
| E1203 | unicode_not_nfc | a string or key of a hashable document is not in NFC |
| E1204 | unicode_unmarked | an R string with non-ASCII bytes has no declared encoding, in a session whose native encoding is not UTF-8, or reaches a writer or hasher |
| E1205 | unicode_bytes_encoding | an R string is marked 'bytes' |
| E1206 | unicode_surrogate | a Python str contains a surrogate code point |
| E1207 | unicode_identifier_outside_bmp | an identifier that a schema restricts to the BMP, such as a column name, contains a character outside it |
| E1208 | unicode_unassigned_character | a string or key of a hashable document contains a code point that Unicode 14.0 does not assign, so that NFC could differ between the packages |
| W1251 | unicode_form_collision | distinct strings of one set are equal after NFC and are treated as one |

### canonical

| Code | Name | Raised when |
|---|---|---|
| E1301 | canonical_unsupported_type | a value in memory has a type with no JSON form, such as an R factor or a Python tuple |
| E1302 | canonical_vector_length | an R atomic vector has a length other than 1 |
| E1303 | canonical_invalid_names | an R list has names that are NA, empty or duplicated |

### hash

| Code | Name | Raised when |
|---|---|---|
| E1311 | hash_key_invalid | a supplied commitment key is not 64 lower-case hexadecimal digits |
| E1312 | hash_key_unavailable | a key must be created and no secure source of random bytes is available, which only R on Windows can raise |
| E1313 | hash_key_not_found | verification needs a key that the sidecar does not hold |
| E1314 | hash_commitment_mismatch | the data do not match a recorded commitment |
| E1315 | hash_key_in_shareable | a writer of a shareable file finds a commitment key in it |
| E1321 | hash_mismatch | a recorded hash does not match the content it covers |

### schema

| Code | Name | Raised when |
|---|---|---|
| E1401 | schema_type | a value has a type the schema does not allow |
| E1402 | schema_required | a required member is missing |
| E1403 | schema_unknown_key | an object has a member the schema does not define |
| E1404 | schema_member_not_allowed | a member is present where the schema forbids it, such as a reason beside 'available' |
| E1405 | schema_enum | a value is not among the allowed values |
| E1406 | schema_pattern | a string does not have the required form |
| E1407 | schema_too_short | a string is shorter than minLength |
| E1408 | schema_too_long | a string is longer than maxLength |
| E1409 | schema_minimum | a number is below minimum |
| E1410 | schema_maximum | a number is above maximum |
| E1411 | schema_exclusive_minimum | a number is not above exclusiveMinimum |
| E1412 | schema_exclusive_maximum | a number is not below exclusiveMaximum |
| E1413 | schema_too_few_items | an array has fewer items than minItems |
| E1414 | schema_too_many_items | an array has more items than maxItems |
| E1415 | schema_duplicate_item | an array item equals an earlier item where items must be unique |
| E1416 | schema_too_few_members | an object has fewer members than minProperties |
| E1417 | schema_too_many_members | an object has more members than maxProperties |
| E1418 | schema_property_name | a key does not have the form propertyNames requires |
| E1419 | schema_dependent_required | a member is present without a member it requires |
| E1420 | schema_contains | no item of an array has the form contains requires |
| E1421 | schema_no_alternative | a value matches no alternative of anyOf or oneOf |
| E1422 | schema_several_alternatives | a value matches more than one alternative of oneOf |
| E1423 | schema_not | a value matches a schema under not, or meets a false schema |
| E1441 | schema_version_unsupported | a document's version lies outside the lines the release supports |
| W1490 | schema_issues_truncated | more than 100 issues were found, and the rest are not listed |

### declaration

The rules behind these codes, the order in which they are checked and their locations are in [declarations.md](declarations.md).

| Code | Name | Raised when |
|---|---|---|
| E2001 | declaration_duplicate_unit | a unit name repeats an earlier unit's name |
| E2002 | declaration_duplicate_field | a field name of the table block repeats an earlier field's name |
| E2003 | declaration_duplicate_estimand | an estimand ID repeats an earlier estimand's ID |
| E2004 | declaration_duplicate_assignment | a column is assigned by more than one entry of the assignment block |
| E2005 | declaration_duplicate_crossing | a crossing repeats an earlier crossing of the same two units |
| E2006 | declaration_unknown_unit | a member names a unit that is not declared |
| E2007 | declaration_unknown_column | a member names a column that is not a field of the table block |
| E2008 | declaration_term_repeated_variable | an estimand term names a variable more than once |
| E2009 | declaration_inferred_pointer | a pointer of provenance.inferred points to nothing, to the whole declaration, to /vocabulary, or to /provenance or anything under it |
| E2010 | declaration_nesting_cycle | a unit is nested in itself, directly or through other units |
| E2011 | declaration_crossing_nested | a crossing pairs a unit with a unit it is nested in |
| E2012 | declaration_derivation_cycle | a column is derived from itself, directly or through other columns |
| E2013 | declaration_category_type | a category does not have the type of its field |
| E2014 | declaration_mixed_list | a list of categories or missing values mixes plain values and objects |
| E2015 | declaration_duplicate_value | a list of categories or missing values repeats a value |
| E2016 | declaration_identifier_categories | an identifier column lists categories |
| E2017 | declaration_bounds_order | the first bound is not less than the second |
| E2018 | declaration_assigned_role | an assigned column has a role other than 'assigned' |
| E2019 | declaration_outcome_misused | an outcome column is used where the design is described, such as in a key or an estimand term |
| E2020 | declaration_outcome_derivation | a column derived from an outcome has a role other than 'outcome' or 'outcome_derived' |
| E2021 | declaration_not_outcome | the outcome of an estimand does not have the role 'outcome' |
| E2022 | declaration_estimand_outcome_missing | an estimand names no outcome when several are declared |
| E2023 | declaration_event_level_type | an event level cannot match the type of its field |
| E2024 | declaration_event_level_category | an event level is not one of the categories of its field |
| E2025 | declaration_feature_requirement | a feature lacks the block or member it requires |
| E2026 | declaration_membership_time | a unit's membership may change over time but no observation time is declared |
| E2027 | declaration_observational_conflict | an entry contradicts the feature 'observational' |
| E2028 | declaration_minimal_member | a minimal declaration lacks a block or the observation key |
| E2029 | declaration_minimal_outcome | a minimal declaration declares no outcome |
| E2030 | declaration_minimal_assigned | a minimal declaration names no assigned variable and is not observational |
| E2031 | declaration_minimal_focal | a minimal declaration has no focal estimand |
| E2032 | declaration_minimal_draft | a minimal declaration is a draft with inferred entries |

### yaml

| Code | Name | Raised when |
|---|---|---|
| E3001 | yaml_package_missing | the yaml package (R) or PyYAML built with libyaml (Python) is not installed |
| E3002 | yaml_syntax | the YAML parser fails |
| E3003 | yaml_document_count | the text holds more than one document |
| E3004 | yaml_anchor_alias | the text uses an anchor or an alias |
| E3005 | yaml_tag | the text uses an explicit tag or a directive |
| E3006 | yaml_complex_key | a mapping key is a sequence or a mapping |
| E3007 | yaml_duplicate_key | a mapping holds a key twice |
| E3008 | yaml_coercion | a scalar cannot be read as the boolean, integer or number the schema requires |
| E3009 | yaml_merge_key | a plain scalar starts with '<<', which R's yaml package can read as a merge key |
| E3010 | yaml_no_document | the text holds no document |

### registry

The compiler reports these codes for the YAML sources, with pointers into the entry or into registry.yaml, and the package tests apply them to the vendored compiled registry, with pointers into it ([registry.md](registry.md), The compiled registry). A package raises E4001 when a lookup such as `explain()` names no entry.

| Code | Name | Raised when |
|---|---|---|
| E4001 | registry_unknown_check | a check identifier, such as one given to `explain()`, names no entry |
| E4002 | registry_file_name | an entry's identifier differs from the name of its source file |
| E4003 | registry_duplicate_id | two entries have the same identifier |
| E4004 | registry_unknown_reference | an entry names a check, statistic, threshold, parameter, message or scope element that does not exist |
| E4005 | registry_dependency_cycle | a link between checks closes a cycle |
| E4006 | registry_duplicate_name | two remedies of an entry have the same identifier |
| E4007 | registry_template_placeholder | a message template uses a placeholder that its arguments do not define |
| E4008 | registry_unused_argument | a message argument does not appear in its template |
| E4009 | registry_template_brace | a message template has a brace outside a placeholder |
| E4010 | registry_unread_source | a threshold is marked validated while one of its literature or software sources has not been read in full |
| E4011 | registry_threshold_statistic | a threshold applies to a statistic that is not a count, ratio or real |
| E4012 | registry_threshold_value | a threshold on a count is not an integer, or one on a ratio lies outside 0 to 1 or has more than four decimal places |
| E4013 | registry_proximity | a threshold on a real statistic has no proximity band, or one on another statistic has one |
| E4014 | registry_message_digits | a message argument gives digits for anything but a real or ratio statistic, or omits them for one |
| E4015 | registry_message_kind | a message argument names a boolean or reals statistic |
| E4016 | registry_tier_reads | an entry's inputs do not match its tier |
| E4017 | registry_entry_order | the entries of the compiled registry are not in ascending order of identifier |
| E4018 | registry_not_canonical | the bytes of the compiled registry are not its canonical bytes |
| E4019 | registry_unexpected_file | spec/registry/checks/ holds a file that is not a YAML source |
| E4020 | registry_consequential_descriptive | a decision rule grades a finding as consequential with a threshold whose validation is descriptive |
| E4021 | registry_ratio_counts | a ratio does not name two count statistics of its own count class as its numerator and denominator |

### table

The table reader reports one issue, the first that its stages find (tables.md, Stages), with a byte offset into the file when the issue has a place there. The rules behind these codes are in [tables.md](tables.md).

| Code | Name | Raised when |
|---|---|---|
| E5001 | table_no_header | the table has no header row |
| E5002 | table_column_name | a column name is empty, is not a valid column name or equals an earlier one after NFC |
| E5003 | table_fields_mismatch | the column names do not match the fields of the table block in number and order |
| E5004 | table_csv_quote | a quotation mark does not open or close a quoted field |
| E5005 | table_record_length | a record has a different number of values from the header |
| E5006 | table_value_type | a value does not have the lexical form of its field's type |
| E5007 | table_value_category | a value is not one of the declared categories of its field |
| E5008 | table_key_missing | a column of the primary key has a missing value |
| E5009 | table_primary_key_duplicate | a record has the same values in the primary key as an earlier record |
| E5010 | table_unique_key_duplicate | a record has the same values in a unique key as an earlier record |

### formula

The builder of the IR reports one issue, the first that its stages find, with a byte offset into the UTF-8 encoding of the formula when the issue has a place in it. The grammar, the stages and the rules behind these codes are in [ir.md](ir.md).

| Code | Name | Raised when |
|---|---|---|
| E6001 | formula_too_long | the formula has more than 10,000 characters |
| E6002 | formula_unexpected_character | a character can start no token |
| E6003 | formula_unclosed_quote | a quoted name has no closing backquote |
| E6004 | formula_invalid_quoted_name | a quoted name is empty or contains a backslash or a control character |
| E6005 | formula_reserved_word | a bare name is a reserved word of R |
| E6006 | formula_invalid_number | a number is not allowed where it stands, or an exponent is not an integer from 2 to 1000 |
| E6007 | formula_unsupported_operator | the formula uses '.' or an operator between '%' signs |
| E6008 | formula_no_tilde | the formula has no '~' |
| E6010 | formula_unexpected_end | the formula ends where the grammar needs more |
| E6011 | formula_unexpected_token | a token cannot continue the formula |
| E6012 | formula_response | the response is not one column or log() of one column |
| E6013 | formula_bar_position | '\|' or '\|\|' appears outside the parentheses of a random term |
| E6014 | formula_random_term_position | a random term is not a summand of the formula |
| E6015 | formula_intercept_position | 0 or 1 appears where an intercept cannot, or '- 0' is written |
| E6016 | formula_grouping | the grouping of a random term is not columns joined by ':' and '/' |
| E6017 | formula_function | the formula calls a function other than offset() and log() |
| E6018 | formula_structured_covariance | the formula uses a covariance structure planned for version 1.3 |
| E6019 | formula_offset | offset() is misplaced, subtracted or holds something other than a column or log() of a column |
| E6020 | formula_log_position | log() appears other than around the response or the column of an offset |
| E6021 | formula_too_deep | parentheses nest more than 64 levels deep |
| E6031 | formula_remove_absent | '-' removes a term that is not present at that point |
| E6032 | formula_response_on_right | the response appears after '~' |
| E6033 | formula_grouping_repeated | a grouping names a column twice |
| E6034 | formula_random_term_empty | a random term has no columns |
| E6035 | formula_random_term_duplicate | a random term repeats an earlier one |
| E6036 | formula_offset_duplicate | an offset repeats an earlier one |
| E6037 | formula_empty_expression | an expression in parentheses leaves no term |
| E6038 | formula_too_many_terms | an operator or a sum would give more than 10,000 terms |
| E6051 | formula_unknown_column | a name is not a column of the data, or of the declared table without data |
| E6052 | formula_column_type | a column has a kind that its use does not allow |
| E6053 | formula_double_bar_categorical | a random term with '\|\|' contains a categorical column |
| E6054 | formula_log_response_declared | a response with a declared event level, trials or exposure is written with log() |
| E6055 | formula_levels_unknown | the levels of a categorical predictor are neither declared nor found in the data |
| E6056 | formula_too_few_levels | a categorical predictor has fewer than two levels |
| E6057 | formula_exposure_offset | an offset of the declared exposure uses a transform other than its declared scale |
| E6058 | formula_random_column_shared | two random terms of one grouping factor share a column |
| E6059 | formula_column_name_duplicate | two columns of one part of the model have the same name |
| E6061 | formula_coding_unknown_column | the coding names a column that is not a predictor |
| E6062 | formula_coding_kind | the coding sets a member that does not apply to the column's kind |
| E6063 | formula_coding_value | the coding has an unknown member, an invalid value or a missing value |
| E6064 | formula_reference_not_level | a reference level is not one of the levels |
| E6065 | formula_declared_column | the declared trials or exposure column of the response is not a numeric column |
| E6066 | formula_weights_column | the weights column is not a numeric column |
| E6067 | formula_empty_sample | a mean centring constant is needed and the design sample has no rows |
| E6068 | formula_identifier_predictor | a column that identifies persons is used as a predictor |
| E6069 | formula_outcome_in_design | a Stream B run would read an outcome, an outcome-derived column or the trials column in its outcome-blind checks |
| E6070 | formula_sample_column | a sample column is not a column of the data, or of the declared table without data |
| E6071 | formula_log_not_positive | log() meets a value that is not positive |
| E6072 | formula_weights_not_positive | a weight is not positive |
| E6073 | formula_nonfinite_value | a numeric column that a sample reads holds NaN or an infinity |
| E6074 | formula_level_label | a level of a categorical predictor contains a control character or a character that Unicode 14.0 does not assign |
| E6075 | formula_too_many_columns | the fixed part or a random term would have more than 10,000 columns |
| E6076 | formula_name_too_long | a name of the IR would have more than 10,000 characters |
| E6077 | formula_nonfinite_result | a centring constant, a centred value or a product in the design matrices is not finite |
| E6101 | formula_ir_inconsistent | an IR document differs from what its own predictors and terms define |

### results

The rules behind these codes, the stages in which they are checked and their locations are in [documents.md](documents.md) (Results document and Internal sidecar).

| Code | Name | Raised when |
|---|---|---|
| E7001 | results_duplicate_finding | a finding has the same check and scope as an earlier finding |
| E7002 | results_finding_order | a finding comes before the finding immediately before it in the order of check and scope |
| E7003 | results_tier_not_logged | an available finding has a tier that no entry of the access log records |
| E7004 | results_plan_missing | an entry in the mode 'planned', or an execution binding hash, appears without the plan in the access log |
| E7005 | results_access_order | an entry of the access log is dated before the entry before it |
| E7006 | results_support_basis | the basis of a finding's support does not agree with the disclosure unit |
| E7020 | results_person_count_shown | a shareable document writes a person count below the minimum count |
| E7021 | results_statistic_shown | a shareable document writes a statistic of a finding that fails the minimum-count or dominance rule |
| E7022 | results_quantile_shown | a shareable document writes a quantile that the quantile rule suppresses |
| E7023 | results_label_not_pseudonym | a shareable document writes a label that is not a pseudonym |
| E7024 | results_ratio_shown | a shareable document writes a ratio whose numerator or denominator is a person count that is suppressed or below the minimum count |
| E7040 | results_unknown_check | a finding names a check that the registry does not have |
| E7041 | results_registry_value | a finding's check version, tier, statistic kind or count class differs from its registry entry |
| E7042 | results_unknown_name | a finding has a statistic, message or scope part that its registry entry does not define |
| E7043 | results_scope_part_missing | a finding's scope lacks a part of its registry entry's scope |
| E7044 | results_optimisation_status | a finding's status has optimisation although its check evaluates no fitted model, or lacks it although the check does |
| E7060 | results_duplicate_pseudonym | a pseudonym of the sidecar repeats an earlier one |
| E7061 | results_duplicate_key | a key identifier of the sidecar repeats an earlier one |
| W7090 | results_registry_differs | a results document was produced with a registry other than the one vendored with the package, so its findings are not checked against registry entries |

### plan

The rules behind these codes are in [documents.md](documents.md) (Plan, version 0.1, and Access log for E7310). E7307 is raised by the Python package only, because only the R package can run the terminal state cluster_robust_cr2.

| Code | Name | Raised when |
|---|---|---|
| E7301 | plan_binding_rungs | an execution binding has a different number of rungs from the design |
| E7302 | plan_binding_design | an execution binding refers to another design-plan hash |
| E7303 | plan_verdict_count | the plan has a different number of verdicts from rungs |
| E7304 | plan_rung_not_identified | a rung on the ladder is not identified |
| E7305 | plan_duplicate_protected | a protected component repeats an earlier one |
| E7306 | plan_protected_missing | a protected component is missing from a rung |
| E7307 | plan_terminal_unsupported | the package cannot run the plan's terminal state |
| E7308 | plan_duplicate_factor | a grouping factor of the ceiling repeats an earlier one |
| E7309 | plan_terminal_design | the terminal state cluster_robust_cr2 is declared for grouping factors that are not nested |
| E7310 | plan_run_mismatch | a run bound to a plan has a declaration or IR that the plan does not record |

### estimates

The rules behind these codes are in [documents.md](documents.md) (Bring-your-own estimates, contract version 0.1).

| Code | Name | Raised when |
|---|---|---|
| E7601 | estimates_duplicate_column | two coefficients map the same IR column |
| E7602 | estimates_duplicate_engine_name | two coefficients have the same engine name |
| E7603 | estimates_packed_length | a packed matrix has the wrong number of values for its columns and packing order |
| E7604 | estimates_not_symmetric | a matrix packed in full is not symmetric |
| E7605 | estimates_covariance_columns | the columns of the fixed-effects covariance are not those of the coefficients that are not aliased, in order |
| E7606 | estimates_key_length | a key of the analysis sample has the wrong number of values |
| E7607 | estimates_block_column | a column belongs to two blocks of the same grouping factor |

### internal

| Code | Name | Raised when |
|---|---|---|
| E9001 | internal_error | an internal check fails, which indicates a bug in the package |
