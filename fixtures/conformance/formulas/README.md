# Formula corpus

These cases test the formula parser and the builder of the canonical IR that M2 implements in both packages ([docs/spec/ir.md](../../../docs/spec/ir.md)). Each case gives a formula with the context it needs and the expected IR with its hash, or the one issue that the builder must report. Some cases also give the design matrices of the design sample, which M2's builder of X and Z must reproduce.

| File | Cases | Covers |
|---|---|---|
| ordinary.json | 39 | intercepts, numeric and categorical predictors, level order, the empty string as a level, contrasts with explicit reference levels, centring, the response with its declared event level or trials, weights, sample columns, quoted names, NFC and white space |
| interactions.json | 26 | ':', '*', '/', '^' and '-', the order of terms and variables, contrasts or indicators in each term, and the sequential rule on empty cells, exact dependencies in either order and relative residuals on both sides of its tolerance |
| nested.json | 13 | nested grouping factors written with '/' or ':', their names and order, and fixed effects of nested factors |
| crossed.json | 10 | crossed grouping factors, factor slopes, implicit intercepts, the order of random terms and the levels of grouping factors |
| double_bar.json | 21 | '\|\|' on numeric terms and on factors whose coding is frozen as numeric contrast columns, and its rejection on other categorical columns |
| offsets.json | 18 | offsets, declared exposures, weights, the rows that a missing weight or exposure removes, white space before '(' and misplaced offset() or log() |
| malformed.json | 54 | lexical, syntactic, structural and expansion errors, with byte offsets |
| context.json | 30 | errors that need the data, the declaration or the coding argument, including predictors that identify persons, and their order |

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile, since missing values in the data are null (conventions.md, Profiles). Formulas may hold strings that are not in NFC on purpose. Each case has these members:

- `id` and `description`.
- `formula`: the formula string.
- `declaration`: a valid declaration of vocabulary 0.1, when the case needs one.
- `data`: the table as the table reader would return it, when the case has data. Each member is a column, keyed by its name as the data give it, which need not be in NFC, and its array holds one value per row: a number, a string, a boolean or null for a missing value. A test builds a data frame from it, with numeric, character and logical columns and NA for null. Every column has at least one value that is not null.
- `coding`: the coding argument (ir.md, Coding argument), when the case sets one.
- `weights`: the name of the weights column, when the case sets one.
- `sample_columns`: further columns whose missing values remove rows from the design sample (ir.md, Samples), when the case sets them.
- `expected`: either `ir` and `ir_hash`, or `issue`.

`ir` is the expected IR, with its members in a readable order rather than in canonical order. A test serialises the builder's IR in the hashable profile, compares its canonical bytes with those of `ir` and checks that their SHA-256 is `ir_hash`. Cases whose descriptions say they give the same IR as another case have the same `ir_hash`.

`issue` holds the `code`, the rendered `message` and, for a code located by offset, the byte `offset` into the UTF-8 encoding of the formula. A test compares all three.

`matrices`, present beside `ir` in some cases, holds the design matrices of the design sample (ir.md, Samples and Design matrices):

- `rows`: the rows of `data` in the design sample, numbered from 0 in the order of the arrays. Numbering from 0 belongs to this file only. The packages identify rows by their observation keys.
- `x`: one array per row of the design sample, with the values of the fixed-part columns in IR order.
- `x_dropped`: the columns of X that the sequential rule drops, in column order.
- `z_columns` and `z`, when the model has random terms: for each column of Z in order, the index of its random term, the label of its level and the name of its column, then one array per row of the design sample with the values of Z.

The values are doubles, compared exactly, since contrasts, products and centred values are computed in double arithmetic as ir.md specifies. The response, offset and weight vectors are not included, because logarithms can differ in the last bit between platforms.

## Provenance

The cases and their expected outputs were written for this project from ir.md and are MIT-licensed. The expected outputs were derived from the specification with a scratch derivation that is not part of either package, and checked against independent oracles: R 4.3.3's terms() and model.matrix() for the order of fixed terms and the names and order of their columns, lme4 1.1-35.1's lFormula() for the columns of random terms, both run as black boxes, and the rfc8785 and jsonschema Python packages for the canonical bytes, the hashes and validity against spec/schemas/ir.schema.json. They agree on every valid case with treatment coding that R and lme4 accept, apart from the differences that ir.md lists. The cases with frozen coding, sample columns or columns that identify persons have no counterpart in R or lme4 and rest on ir.md alone, and the cases of the sequential rule were checked against its tolerance by computing the relative residuals of their columns. lme4 rejects the one-sided formula, R cannot parse the formula with a carriage return, and neither applies NFC. The zoo cases (nested-07, nested-09, nested-10, crossed-02, crossed-08 and crossed-09) take their formulas and columns from the prototyped fixtures Z01, Z02, Z04, Z07, Z08, Z13 and Z17 in docs/design/evidence/decisions/E/zoo, with a few rows of data written for each case. spec/tools/test_formula_corpus.py checks the format of every case, the hashes, the schema and the error codes against spec/errors.json.
