# Declaration corpus

These cases test the declaration validator of both packages ([declarations.md](../../../docs/spec/declarations.md)) on declarations written in JSON: reading through the strict reader in the hashable profile, the check of the vocabulary version, structural validation against [declaration.schema.json](../../../spec/schemas/declaration.schema.json) and the rules in code on names and references and on meaning, including the minimal declaration. A valid case gives the canonical bytes of the declaration and its hash, and an invalid case gives the issues that the validator reports, in order. Declarations written in YAML are in [yaml/](../yaml/README.md).

| File | Cases | Covers |
|---|---|---|
| valid.json | 28 | every block, member, feature, role, measurement level, field type, time kind and estimand kind of vocabulary 0.1, the examples of the draft schema updated to vocabulary 0.1, the Example of declarations.md, drafts, terms with quoted names, numbers and escapes in their canonical form, values at the limits of the schema, the argument `minimal` and declarations that differ only in layout or in one member of their provenance |
| reading.json | 17 | stage 1: a byte-order mark, a duplicate key, null, NFD, NaN, numbers outside the hashable profile, an unpaired surrogate, a key outside the BMP, bytes that are not UTF-8, U+0000, an empty key, an unassigned code point and syntax errors, among them an unquoted word |
| version.json | 5 | stage 2: versions outside the 0.1.x line, too long or followed by a line feed |
| structure.json | 59 | stage 3: each keyword of the schema that a declaration can break, the deferred dyad, EEG and imputation blocks, misspelt members, the members that measurement levels allow and the three checks that complete the schema |
| references.json | 12 | stage 4: E2001 to E2009, with every place that names a unit or a column |
| meaning.json | 46 | stage 5: E2010 to E2032, with every place where an outcome column is misused and each rule of the minimal declaration |
| precedence.json | 25 | declarations that break several rules: the order of the stages and of the reader's checks, the order of issues by pointer, code and message, the cap of 100 issues with W1490, type failures that hide the issues below them, issues reported once and the examples of declarations.md |

Each case of reading.json, version.json, structure.json, references.json and meaning.json breaks one rule, which may give more than one issue, such as an undeclared unit named in several places.

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile. The files are ASCII, with every other character written as an escape. Each case has these members:

- `id` and `description`. The ID is unique across the corpora.
- `path`: the input file, relative to this directory. The test reads it as the validator reads a file: a name that ends in '.yaml' or '.yml', compared in ASCII lower case, through the YAML reader, and any other name through the strict reader in the hashable profile (declarations.md, Documents, versions and hashes).
- `minimal`: present and true when the validator is called with the argument `minimal` set to true (`minimal = TRUE` in R, `minimal=True` in Python).
- `expected`: either `canonical` and `sha256`, or `issues`.

`canonical` holds the canonical bytes of the declaration as read, as the string whose UTF-8 encoding they are, and `sha256` the declaration hash, as documents write it. A test checks that the validator reports no issue, writes the value read in the hashable profile and compares the bytes and the hash exactly.

`issues` holds the issues in the order reported, each with its `code`, its rendered `message` and its `offset` or `pointer`, or neither for a code without a location (`issue` in [defs.schema.json](../../../spec/schemas/defs.schema.json)). A reader reports one issue, located by byte offset, and stages 2 to 5 report their issues sorted, capped at 100 and located by JSON Pointer (declarations.md, Validation). A test compares the list exactly: the codes, the messages and the locations, in order.

The input files are written as people write them, indented and with their members in any order. Some have CRLF line endings, escapes, a byte-order mark or bytes that are not UTF-8 on purpose. .gitattributes keeps their bytes as stored.

## Provenance

The cases were written for this project from declarations.md, [conventions.md](../../../docs/spec/conventions.md) and [errors.md](../../../docs/spec/errors.md) and are MIT-licensed. They start from earlier MIT-licensed work of this project in docs/design/evidence/decisions/E/schema and E-verify/edge:

- examples ex1, ex2, ex3 and ex5 of the draft carry over as valid cases, updated to vocabulary 0.1 as declarations.md (Changes from the draft schema) describes. ex4 and ex6 are valid without their dyad and EEG blocks and invalid with them.
- the draft's invalid files bad1 to bad7 appear as single-rule cases, and bad2 and bad4 also as written, since each breaks two rules.
- the edge files edge2 to edge4 and e5 to e11, whose 'x-' keys are unknown keys in vocabulary 0.1, place their strings and numbers in titles, bounds, categories and missing values.

The expected outputs were derived from the specification with a scratch derivation that is part of neither package: a strict reader and the rules of stages 2, 4 and 5 written from the specifications, with the structural validator of spec/tools/compile_registry.py and the three checks in code for stage 3. Each case states its expected codes by hand, and the derivation was required to agree. Independent oracles confirm the rest. The rfc8785 Python package 0.1.4 gives every canonical form and hash. jsonschema 4.26.0, with the pattern keyword of conventions.md (Schemas), finds every valid case and every case of stages 4 and 5 valid under declaration.schema.json. It finds every case of stages 2 and 3 invalid, apart from those that only the checks in code catch. An earlier scratch prototype of the rules of stages 4 and 5, written with declarations.md, gives the same issues for every case, apart from the two cases that compare numbers by value (1.0 is the integer 1), where it compared Python types. The Example of declarations.md has the declaration hash published there, and the faulty declaration of its Reporting section and its variant with undeclared units give the issues that declarations.md lists. [spec/tools/test_declaration_corpus.py](../../../spec/tools/test_declaration_corpus.py) checks the format of the corpus, the hashes, the schema and every issue against spec/errors.json.
