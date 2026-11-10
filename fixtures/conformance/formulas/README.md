# Formula corpus

These cases test the formula parser and the builder of the canonical IR that M2 implements in both packages ([docs/spec/ir.md](../../../docs/spec/ir.md)). Each case gives a formula with the context it needs and the expected IR with its hash, or the one issue that the builder must report. Some cases also give the design matrices of the design sample, which M2's builder of X and Z must reproduce, or the one issue that it must report for the IR.

| File | Cases | Covers |
|---|---|---|
| ordinary.json | 46 | intercepts, numeric and categorical predictors, level order, the empty string as a level, categories given as objects, contrasts with explicit reference levels, centring, the response with its declared event level or trials, weights, sample columns, the rows of the design sample whose response is missing or whose trials are 0, quoted names, NFC and white space |
| interactions.json | 26 | ':', '*', '/', '^' and '-', the order of terms and variables, contrasts or indicators in each term, and the sequential rule on empty cells, exact dependencies in either order and relative residuals on both sides of its tolerance |
| nested.json | 13 | nested grouping factors written with '/' or ':', their names and order, and fixed effects of nested factors |
| crossed.json | 12 | crossed grouping factors, factor slopes, implicit intercepts, the order of random terms and the levels of grouping factors, with labels that are booleans, numbers or strings that contain ':' |
| double_bar.json | 22 | '\|\|' on numeric terms and on factors whose coding is frozen as numeric contrast columns, and its rejection on other categorical columns |
| offsets.json | 24 | offsets, declared exposures, weights, the rows that a missing weight or exposure removes, white space before '(', misplaced offset() or log() and the logarithms and weights that the design matrices refuse, also in rows whose response is missing |
| malformed.json | 61 | lexical, syntactic, structural and expansion errors, with byte offsets, including the length in code points and the limit on terms |
| context.json | 46 | errors that need the data, the declaration or the coding argument, including predictors that identify persons, levels and names that the IR cannot hold, parts with more than 10,000 columns, values that are not finite and their order |

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile, since missing values in the data are null (conventions.md, Profiles). Formulas may hold strings that are not in NFC on purpose. Each case has these members:

- `id` and `description`.
- `formula`: the formula string.
- `declaration`: a valid declaration of vocabulary 0.1, when the case needs one.
- `data`: the table as the table reader would return it, when the case has data. Each member is a column, keyed by its name as the data give it, which need not be in NFC, and its array holds one value per row: a number, a string, a boolean or null for a missing value. In a column with a number, the strings 'NaN', 'Infinity' and '-Infinity' stand for the special values that the table reader returns as values. A test builds a data frame from it, with numeric, character and logical columns and NA for null. Every column has at least one value that is not null.
- `coding`: the coding argument (ir.md, Coding argument), when the case sets one.
- `weights`: the name of the weights column, when the case sets one.
- `sample_columns`: further columns whose missing values remove rows from the design sample (ir.md, Samples), when the case sets them.
- `expected`: either `ir` and `ir_hash`, with `matrices` or `issue` in some cases, or `issue` alone.

`ir` is the expected IR, with its members in a readable order rather than in canonical order. A test serialises the builder's IR in the hashable profile, compares its canonical bytes with those of `ir` and checks that their SHA-256 is `ir_hash`. Cases whose descriptions say they give the same IR as another case have the same `ir_hash`.

`issue` holds the `code`, the rendered `message` and, for a code located by offset, the byte `offset` into the UTF-8 encoding of the formula. A test compares all three. Alone, it is the issue of the builder of the IR. Beside `ir`, it is the issue that the builder of the design matrices reports for that IR and the data (ir.md, Errors): E6071, E6072, E6073 or E6077.

`matrices`, present beside `ir` in some cases, holds the design matrices of the design sample (ir.md, Samples and Design matrices):

- `rows`: the rows of `data` in the design sample, numbered from 0 in the order of the arrays, as in Python. `design_matrices()` returns row positions counted from 1 in R and from 0 in Python.
- `x`: one array per row of the design sample, with the values of the fixed-part columns in IR order.
- `x_dropped`: the columns of X that the sequential rule drops, in column order. Every residual that the rule compares lies at least a factor of 10 from its tolerance, so that both languages drop the same columns (conventions.md, Comparison across languages).
- `z_columns` and `z`, when the model has random terms: for each column of Z in order, the index of its random term, the label of its level and the name of its column, then one array per row of the design sample with the values of Z. The tests and the parity harness also check that Z stores as many entries as ir.md (Z) requires, one for each row and each column of a random term, zero or not.

The values are doubles, compared exactly, since contrasts, products and centred values are computed in double arithmetic as ir.md specifies. The response, trials, offset and weight vectors are not included: the corpus gives only X, Z and the design sample, and the response and offset vectors can hold logarithms, which can differ in the last bit between platforms. The parity harness compares the vectors across the languages.

## Provenance

The cases and their expected outputs were written for this project from ir.md and are MIT-licensed. The expected outputs were derived from the specification with a scratch derivation that is not part of either package, and checked against independent oracles: R 4.3.3's terms() and model.matrix() for the order of fixed terms and the names and order of their columns, lme4 1.1-35.1's lFormula() for the columns of random terms, both run as black boxes, and the rfc8785 and jsonschema Python packages for the canonical bytes, the hashes and validity against spec/schemas/ir.schema.json. They agree on every valid case with treatment coding that R and lme4 accept, apart from the differences that ir.md lists. The cases with frozen coding, sample columns or columns that identify persons have no counterpart in R or lme4 and rest on ir.md alone, and the cases of the sequential rule were checked against its tolerance by computing the relative residuals of their columns. lme4 rejects the one-sided formula and double-bar-10, `y ~ (1 || g)`, R cannot parse the formula with a carriage return, and neither applies NFC. The zoo cases (nested-07, nested-09, nested-10, crossed-02, crossed-08 and crossed-09) take their formulas and columns from the prototyped fixtures Z01, Z02, Z04, Z07, Z08, Z13 and Z17 in docs/design/evidence/decisions/E/zoo, with a few rows of data written for each case. spec/tools/test_formula_corpus.py checks the format of every case, the hashes, the schema and the error codes against spec/errors.json.

The corpus has no generator. Its files are written in the layout that the scratch derivation of M1 gave them, which keeps an object or array on one line when it fits in 100 characters, and cases are added by hand in that layout. A new case states its code, and its offset for a located code, by hand from ir.md. Its IR, matrices and messages are checked against what ir.md specifies, then by spec/tools/test_formula_corpus.py, by the tests of both packages and by the parity harness, which compare them with both packages, and, for a valid case with treatment coding that R and lme4 accept, by the oracle test of the R package against model.matrix() and lme4. The 35 cases added after the review of M2a, ordinary-40 to ordinary-46, crossed-11 and crossed-12, double-bar-22, malformed-55 to malformed-61, context-31 to context-44 and offsets-19 to offsets-22, were added this way. After M2a, a second derivation of these 35 cases from the specifications alone, written without the packages, gave the same outcomes and found four points that ir.md had left open, which ir.md now settles (03-execution-plan.md, M2). No case separated the readings of two of them, the rows to which E6071 for an offset and E6072 apply and the order of the codes of centring, and none gave E6075 for a random term, so offsets-23, offsets-24, context-45 and context-46 were then added by hand in the same way.
