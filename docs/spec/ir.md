# Canonical IR and formula grammar

The canonical intermediate representation (IR) describes one model in a form that both packages compute identically: its response, the coding of every predictor, the terms and columns of the fixed part, the random terms with their grouping factors and columns, the offsets and the weights. It is built from an lme4-style formula, an optional declaration, the data when they are available, an optional coding argument and optional sample columns, and it is enough to build the design matrices X and Z deterministically in both languages (02-decisions.md, Q1 and Q3). This document specifies the formula grammar the suite accepts, the expansion of terms, the kinds and levels of columns, contrast coding with explicit reference levels, centring rules and constants, the design and analysis samples, the construction of X and Z, the sequential rule for dropping aliased columns, the IR document and its hash and the error codes of the formula area. It is normative together with [spec/schemas/ir.schema.json](../../spec/schemas/ir.schema.json), and where the two disagree, this document prevails and the schema is corrected. [conventions.md](conventions.md) defines the hashable profile, NFC, code-point order, decimal constants and hashing, [errors.md](errors.md) the rendering of messages and [declarations.md](declarations.md) the declaration. The conformance corpus in [fixtures/conformance/formulas/](../../fixtures/conformance/formulas/README.md) holds formulas with their expected IR or error code.

M1 specifies the IR. The formula parser, the builder of the IR and the design matrices are implemented in M2 (03-execution-plan.md).

## Inputs and outputs

The builder of the IR takes six inputs:

- formula: a string in the grammar below.
- declaration: a valid declaration of vocabulary 0.1, or none. The builder reads the table block, for the types and categories of columns, and the `variables` entry of the response, for its event level, trials and exposure. It also reads the units, the roles of variables and `disclosure_unit`, for the columns that identify persons (Kinds of columns), and nothing else.
- data: the table as the table reader returns it ([tables.md](tables.md)), or none. Each column holds numbers, strings or booleans, with missing values marked as missing, and no two column names are equal after NFC. Before the data are seen, as when a prospective plan is written, there are none.
- coding: an object that sets the contrast and reference level of categorical predictors and the centring of numeric ones (Coding argument), or none.
- weights: the name of a column of precision weights, or none.
- sample_columns: the names of further columns whose missing values remove rows from the design sample, or none (Samples).

The builder returns the IR, or exactly one issue with a code of the formula area (Errors). The IR hash is 'sha256:' followed by the SHA-256 of the IR's canonical bytes (conventions.md, Hashes).

The IR is canonical: two inputs that specify the same model in the senses defined below give byte-identical IRs. For example, each of these pairs of formulas gives one IR:

- `y ~ a*b` and `y ~ a + b + a:b`
- `y ~ x` and `y ~ 1 + x`
- `y ~ (1 | school/class)` and `y ~ (1 | school) + (1 | school:class)`
- `y ~ (1 + x || g)` and `y ~ (1 | g) + (0 + x | g)`
- `y ~ x + offset(log(e))` and `y ~ offset(log(e)) + x`

The IR does not hold the formula string, which a results document records separately.

## Formula grammar

A formula is a string of at most 10,000 characters, each a Unicode code point (E6001). Locations in it are byte offsets into its UTF-8 encoding, counted from 0, as for every reader (conventions.md). In R, the string crosses an input boundary as conventions.md (Strings in R) describes.

### Tokens

The formula is first divided into tokens from left to right. White space is U+0020, U+0009, U+000A and U+000D, and separates tokens. At each other position, the token is the first that applies:

1. '|' followed by '|' is the token '||'. Otherwise each of `~ + - * / : ^ ( ) , |` is a token of its own.
2. '`' starts a quoted name, which runs to the next '`'. If there is none, E6003 is reported at the opening backquote. The name is the text between the backquotes, which must be non-empty and contain no backslash (U+005C) and no control character (U+0000 to U+001F and U+007F to U+009F), or E6004 is reported at the opening backquote.
3. An ASCII digit starts a number, which is the longest run of ASCII letters, digits, '.' and '_'. A number that is not all digits, such as '1.5' or '2L', gives E6006.
4. An ASCII letter starts a bare name, the longest run of ASCII letters, digits, '.' and '_'. A bare name that is a reserved word of R gives E6005: if, else, repeat, while, function, for, next, break, TRUE, FALSE, NULL, Inf, NaN, NA, NA_integer_, NA_real_, NA_character_ and in. Such a column is written between backquotes.
5. '.' gives E6007, since the operator '.' for all other columns is not supported.
6. '%' followed, without white space in between, by a later '%' gives E6007 for the operator from one '%' to the next, such as '%in%'. Any other '%' gives E6002.
7. Any other character gives E6002, naming its code point. A no-break space U+00A0 is such a character.

A bare name whose next token is '(' is the name of a function, whether or not white space separates them, as R reads `log (x)` as a call. The first lexical issue, the one at the lowest offset, is reported. A formula without the token '~' then gives E6008.

### Syntax

The tokens must form a formula of this grammar, in the EBNF of ISO/IEC 14977, where a quoted string stands for the token with that text, number for a number token and name for a bare or quoted name:

```ebnf
formula     = [ sum ], "~", sum ;
sum         = [ "+" | "-" ], product, { ( "+" | "-" ), product } ;
product     = interaction, { ( "*" | "/" ), interaction } ;
interaction = power, { ":", power } ;
power       = primary, [ "^", primary ] ;
primary     = name | number | call | "(", argument, ")" ;
call        = function name, "(", [ argument, { ",", argument } ], ")" ;
argument    = sum, [ ( "|" | "||" ), sum ] ;
```

The tokens are read from left to right, each by the first rule that can continue the formula. At the first token that cannot continue it, the parser reports E6013 if the token is '|' or '||', E6010 at the end of the input and E6011, naming the token, otherwise. So `y ~ x +` gives E6010 at byte 7, `y ~ x)` gives E6011 at ')' and `y ~ x | g` gives E6013 at '|'. A '(' that opens a 65th level of nesting, counting the parentheses of calls, gives E6021 at its offset. The parser reports the first of these issues in the order of the tokens, so a '(' that opens a 65th level before a stray token gives E6021, and a stray token before it gives E6011.

This grammar accepts more than the suite does, so that the rules below can report a precise code. The parenthesised `argument` with a bar is a random term, whose left-hand side is the sum before the bar and whose grouping is the sum after it.

### Structure

The parsed formula must also satisfy the rules below. Every violation is located at the offset of a token: a name, number or function name at its own token, a random term or parenthesised expression at its '(', an operator at its token and a sign at its token. When several rules are violated, the violation at the lowest offset is reported, and among violations at one offset, the one with the lowest code.

- Response (E6012, at the first token of the response). The sum before '~', if there is one, is a single name without a sign, or log() of a single name.
- Random terms (E6014). A random term is a summand of the sum after '~', added with '+' or written first without a sign, and not part of a product, interaction, power, parenthesised expression, call or the left-hand side of another random term. A subtracted random term is refused, since lme4 would add it.
- Grouping (E6016). The grouping of a random term is a single summand without a sign, made of names joined by ':' and '/'. The violation is located at the first sign, operator other than ':' and '/', number, call or parenthesis in it.
- Intercepts. A number that is a summand of the sum after '~', or of the left-hand side of a random term, must be '0' or '1' (E6006), and '- 0' is not allowed (E6015, at the sign). A number anywhere else, other than in the grouping of a random term, where the rule of Grouping alone applies, is either the exponent of '^', which must be an integer from 2 to 1000 written without leading zeros (E6006), or gives E6015 if it is '0' or '1' and E6006 otherwise. The exponent of '^' must be a number (E6006, at its first token, whose text is the argument {number}).
- offset() (E6019, at its name). An offset is a summand of the sum after '~', added with '+' or written first without a sign, with one argument that is a single name or log() of a single name.
- log() (E6020). log() appears only as the response or as the argument of offset(), with one argument that is a single name. When it is in such a place but its argument is not a single name, the rule of the response or of offset() applies instead.
- Other functions. diag, cs, ar1, us, homdiag, homcs, hetcs, ou, toep, rr and propto, the covariance structures of lme4 2.x and glmmTMB, give E6018, because structured covariance terms are planned for version 1.3 (02-decisions.md, Q2). Every other function, such as I(), poly(), scale(), factor() or cbind(), gives E6017. A transformed predictor is added to the data as a column of its own.

## Expansion

Expansion turns the formula into terms. A term is a set of variables, each the name of a column, with the empty set standing for the intercept. Names are compared after NFC normalisation (conventions.md, NFC), so a name written in a decomposed form in the formula refers to the same column as its precomposed form.

### Operators

Each sub-expression of a sum that is not an intercept, random term or offset evaluates to an ordered list of terms without repetitions. When a list is extended, a term already in it is not added again.

- A name evaluates to the one term that holds its variable.
- `A:B` gives, for each term a of A in order and, within it, each term b of B in order, the term a ∪ b. A variable joined with itself is the variable, so `x:x` is `x`.
- `A*B` gives the terms of A, then those of B, then those of `A:B`.
- `A/B` gives the terms of A, then, for each term b of B in order, the union of all the variables of A with b. So `a/b` is `a + a:b`, and `(a + x)/b` is `a + x + a:x:b`.
- `A^n` gives `A:A:…:A` with n copies of A, evaluated from the left. So `(x + z + a:b)^2` gives `x`, `x:z`, `x:a:b`, `z`, `z:a:b` and `a:b` in this order, before sorting.
- A parenthesised sum evaluates as a sum. If it leaves no term, E6037 is reported at its '('.
- A sum is evaluated from left to right. It starts empty, '+' or no sign appends the terms of a summand that it does not yet hold, and '-' removes them. Each term that '-' removes must be present at that point, or E6031 is reported at the '-', naming the first absent term. So `y ~ a + b - a + a` gives `b` then `a`, and `y ~ -x + x` gives E6031.

No list of terms may hold more than 10,000 terms, so that a short formula cannot ask for an expansion that exhausts memory. Before an operator forms its terms, it counts them with repetitions: |A| × |B| for `A:B`, |A| + |B| + |A| × |B| for `A*B` and |A| + |B| for `A/B`, where |A| is the number of terms of A. `A^n` counts each interaction of its evaluation in turn, as for ':', from the second copy of A on. A count above 10,000 gives E6038 at the operator. A sum that would hold more than 10,000 terms once a summand is appended gives E6038 at the sign of that summand. So `y ~ x1*x2*…*x13` is accepted, with 8,191 terms, and `y ~ x1*x2*…*x14` gives E6038 at its last '*'.

The fixed part is the evaluation of the sum after '~' without its intercepts, random terms and offsets. The left-hand side of each random term is evaluated in the same way, on its own. Each part is evaluated from left to right, each operand before the operator that combines it, so that a summand is evaluated before its sign is applied, and the evaluation of a part stops at its first issue, E6031, E6037 or E6038. So `y ~ x - (a - a)` gives E6037 at the inner '(' rather than E6031.

### Intercepts

The fixed part and the left-hand side of each random term have an intercept unless they say otherwise. Their intercept summands are applied from left to right, and the last one decides: '1' or '+ 1' includes the intercept, and '0', '+ 0' and '- 1' exclude it. So `y ~ 0 + x + 1` has an intercept, and `(x - 1 | g)` has none.

### Order of terms and variables

After evaluation, the terms of a part are sorted by the number of their variables, keeping the order of evaluation among terms with the same number (a stable sort). The intercept comes first when there is one. This is the term order, as in R.

The variables of each term follow the order of their first appearance as name tokens in the same part, read from left to right: for the fixed part, all names of the fixed part, including those of summands that '-' removes but not those of random terms, offsets or the response, and for a random term, the names of its left-hand side. So `y ~ b:a + a` has the term `b:a`, because 'b' appears first. This order decides which variable varies fastest among the columns of an interaction (Columns of a term).

### Random terms

Each written random term is expanded in three steps.

1. Its left-hand side is evaluated with its intercept.
2. Its grouping becomes one or more grouping factors. A factor is a set of grouping variables, written with ':', and '/' nests: for `f1/f2/…/fk`, the factors are f1, f1 ∪ f2 and so on to f1 ∪ … ∪ fk, so `(1 | school/class)` has the factors school and school:class. A variable that appears twice in one grouping gives E6033 at its second appearance. The variables of a factor keep the order in which they are written where the factor first arises, and a factor that arises again with the same variables, in any order, is the same factor with its first order.
3. A left-hand side with neither an intercept nor a term gives E6034 at the term's '('. Otherwise, with '|', the term gives one random term for each factor, with the whole left-hand side. With '||', it gives, for each factor, the random term '1' if the left-hand side has an intercept, followed by one random term '0 + t' for each other term t of the left-hand side in term order. '||' applies only to numeric terms, since the indicators of a factor would duplicate the intercept (02-decisions.md, Q3). A categorical column in its left-hand side gives E6053 at its first appearance there, including one in a summand that '-' removes, unless the coding argument freezes it as numeric contrast columns (Coding argument), which is checked with the kinds of columns (Kinds of columns and Errors). The exemption holds when the column's entry of the coding argument has `frozen` exactly true, whatever else the entry holds, so that pass 4 of the context then reports any invalid member of that entry. A term '0 + t' from '||' whose term t has a frozen factor and more than one column is split, once the levels are known and before the columns of random terms are checked, into one random term for each column of t, in column order, each with that column alone.

Each written random term reports at most one issue of these steps, the first in their order, and a written term with an issue gives no random terms. A random term that has the same grouping factor, intercept and set of terms as an earlier one gives E6035 at the '(' of the written term that produces it. This is checked on the random terms of step 3, before any term of a frozen factor is split. The random terms of the IR are grouped by grouping factor, in the order in which each factor first arises, and within a factor in the order in which they arise. So `(1 | subject) + (1 | item) + (0 + x | subject)` gives the subject terms first, `(1 + x || g/h)` gives `1 | g`, `0 + x | g`, `1 | g:h` and `0 + x | g:h`, and, with 'a' frozen and coded by treatment contrasts with the levels A1, A2 and A3, `(1 + a || g)` gives `1 | g`, `0 + a[A2] | g` and `0 + a[A3] | g`.

Two random terms of the same grouping factor cannot share a column, since each block of random effects must have distinct columns (documents.md, E7607). A shared column, such as the intercept in `(1 | g) + (1 + x | g)`, gives E6058 at the '(' of the later term, naming the column.

### Response, offsets and weights

The response is the name before '~', with the transform 'identity', or the argument of log(), with the transform 'log'. A formula without a response, such as `~ x + (1 | g)`, has none. The response cannot appear anywhere after '~' (E6032, at its first appearance there).

An offset is a numeric column added to the linear predictor as it is ('identity') or as its natural logarithm ('log'). The same column with the same transform twice gives E6036 at the later 'offset'. When the declaration gives the response an exposure (conventions.md, Declaration fields), the exposure is an offset: its logarithm for the scale 'raw' and the column itself for the scale 'log'. An offset of the exposure column in the formula must use that transform (E6057, at the 'offset' of the offending offset), and an exposure that the formula does not write is added. The offsets of the IR are listed in code-point order of their columns and then of their transforms ('identity' before 'log').

The weights are precision weights, named by the caller (Inputs and outputs). The declaration's role 'weight' does not make a column the weights.

## Kinds of columns

Every name in the formula must be a column (E6051, at the first offending name). With data, the columns are those of the data, compared after NFC. Without data, they are the fields of the declaration's table block. The kind of a column comes from its declared field, if there is one, and otherwise from its values:

| Declared field | Values in the data | Kind | Levels |
|---|---|---|---|
| with categories | any | categorical | the categories, in declared order |
| type 'date' or 'datetime' | strings | date | none |
| type 'boolean' | booleans | categorical | false, then true |
| type 'number' or 'integer' | numbers | numeric | none |
| type 'string', or no type | strings | categorical | the distinct values of the table |
| none | numbers | numeric | none |
| none | strings | categorical | the distinct values of the table |
| none | booleans | categorical | false, then true |

`categoriesOrdered` does not change the coding, unlike R, which gives ordered factors polynomial contrasts. The distinct values of the table are those of all rows of the table as read, missing values excluded, so that a level that the design sample loses keeps its place and its reference level (Samples). Values are compared after NFC, and two values equal after NFC are one level, written in NFC (conventions.md, NFC). The builder merges them without an issue, and the check labels.unicode_forms of the registry reports the merge. They are ordered by code point, so 'B' comes before 'a'.

Each use of a column allows these kinds (E6052, at the offending name, naming its kind and the use). Every appearance of a name in a product of the fixed part or of a random term's left-hand side is a use as a predictor, including one in a summand that '-' removes. The message names the use exactly as the first column of the table writes it, and the column of an offset written with log() is named as the argument of log().

| Use | Kinds |
|---|---|
| the response | numeric, categorical |
| the argument of log() | numeric |
| a predictor | numeric, categorical |
| a grouping variable | any |
| an offset | numeric |

A column that identifies persons cannot be a predictor (E6068, at its first appearance as a predictor, including one in a summand that '-' removes), so that no IR, and no plan that holds IRs, lists the labels of persons as levels (02-decisions.md, Q4 and Q5). The columns that identify persons are those that the declaration gives the role 'id' and the label columns of the disclosure unit (conventions.md, Declaration fields), of every unit with the role 'participant' and of every unit nested in one of these, directly or through other units. Without a declaration, no column is known to identify persons. Other unit columns, such as those of schools or sites used as blocking factors, may be predictors.

A response written with log() cannot have a declared event level, trials or exposure (E6054, at the first token of the response, naming the first of event_level, trials and exposure that the declaration gives). The predictors of the IR are the columns that appear in a term of the fixed part or of a random term after expansion. A categorical predictor whose levels are unknown, because it has no declared categories and there are no data, gives E6055, and one with fewer than two levels gives E6056, each at its first appearance in a product, including one in a summand that '-' removes. A level that contains a control character (U+0000 to U+001F and U+007F to U+009F) or a code point that Unicode 14.0 does not assign gives E6074 at the same place, since a column name cannot hold the first (ir.schema.json, IR name) and the hashable profile cannot hold the second (conventions.md, NFC). The trials and exposure columns that the declaration gives the response (E6065) and the weights column (E6066) must be numeric columns.

## Coding

### Coding argument

The coding argument is an object keyed by column name, compared after NFC. Each entry sets members for one predictor:

| Member | Kind | Value | Default |
|---|---|---|---|
| contrast | categorical | 'treatment', 'sum' or 'simple' | 'treatment' |
| reference | categorical | a string, an integer or a boolean | the first level |
| centring | numeric | 'none', 'mean' or 'value' | 'none' |
| frozen | categorical | true or false | false |
| significant_digits | numeric, with centring 'mean' | an integer from 1 to 15 | 6 |
| value | numeric, with centring 'value', which requires it | a decimal string of at most 15 significant digits (conventions.md, Decimal strings and centring constants) | none |

A number with an integral value, such as 2.0, counts as an integer for `reference` and `significant_digits`, and a boolean never does. The entries are checked one at a time, in code-point order of their keys, and the first issue found is reported. For each key, these checks run in order:

1. A key that is not a predictor gives E6061.
2. Every member, in code-point order, must be one of the six names above with a valid value. The first that is not gives E6063, naming it.
3. Every member, in code-point order, must apply to the kind of the column. The first that does not gives E6062, naming it.
4. For a numeric column, significant_digits requires the centring 'mean' and value the centring 'value' (E6063, naming the member, significant_digits first), and the centring 'value' requires value (E6063, naming centring).

So `{"x": {"contrast": "sum", "zzz": 1}}` for a numeric column 'x' gives E6063 at 'zzz', and `{"a": {"bad": 1}, "z": {}}` gives E6063 for 'a' before E6061 for 'z'. A reference level that is not one of the levels, compared by type and value and for strings after NFC, gives E6064. So an integer reference is never a level of a column of strings.

With `frozen` true, the coding of a categorical predictor is frozen as numeric contrast columns, as a plan freezes it before it builds its ladder (02-decisions.md, Q3). The predictor is coded by its contrast in every term, whatever the rules of Contrasts or indicators would give, and '||' splits a term that holds it into its columns (Random terms). A frozen predictor with two levels and simple contrasts is the one numeric column of ±0.5 coding.

### Contrasts

A categorical predictor with k levels in level order and a reference level r is coded by one column for each level l other than r, in level order. The value of the column of l in a row whose level is m is:

| Contrast | m = l | m = r | otherwise |
|---|---|---|---|
| treatment | 1 | 0 | 0 |
| sum | 1 | −1 | 0 |
| simple | (k − 1)/k | −1/k | −1/k |

With treatment coding, the coefficient of l is the difference between l and the reference level. With sum coding, the reference level takes −1 in every column, as in R's contr.sum when the reference level is the last. Simple coding keeps the comparisons of treatment coding while centring the columns when the levels are balanced, and for two levels it is the ±0.5 coding of 02-decisions.md (Q3), with −0.5 for the reference level. The values are doubles: (k − 1)/k and 1/k are computed as the quotient of two integers, rounded to the nearest double, and −1/k is the negation of 1/k.

A categorical predictor coded by indicators has one column for each level, in level order, with the value 1 in rows of that level and 0 otherwise.

### Contrasts or indicators

In each term of a part, a frozen predictor is coded by its contrast, and every other categorical variable F is coded either by its contrast or by indicators, as in R:

1. If F is the only variable of the term, F is coded by its contrast.
2. Otherwise, let T be the other variables of the term. F is coded by its contrast if T is a subset of some earlier term of the part, in term order, and by indicators if not.
3. If the part has no intercept, the first categorical variable that is not frozen, met when the terms are read in term order, and the variables of each term in their order, is coded by indicators, whatever rules 1 and 2 gave.

So `y ~ a:b` codes both factors by indicators, `y ~ a + a:b` codes 'a' by indicators and 'b' by its contrast in `a:b`, `y ~ 0 + a + b` codes 'a' by indicators and 'b' by its contrast, and in `y ~ 0 + z:b + z:b:a` the first categorical variable met, 'b' in `z:b`, already uses indicators, so 'a' keeps its contrast in `z:b:a`. The coding of each variable in each term is recorded in the IR.

### Columns of a term

The columns of a term are the products of the columns of its variables. A numeric variable gives one column and a categorical variable the columns of its coding in that term. The columns are listed with the first variable of the term varying fastest, as in R, and the intercept term has the one column '(Intercept)'. So `a:b` with treatment coding, 'a' of levels A1, A2 and A3 and 'b' of levels B1 and B2 has the columns `a[A2]:b[B2]` and `a[A3]:b[B2]`, and with both coded by indicators the six columns from `a[A1]:b[B1]`, `a[A2]:b[B1]`, `a[A3]:b[B1]` to `a[A3]:b[B2]`. A variable that carries a level, in a term that '||' has split, gives only the column of that level.

The columns of a part are the columns of its terms in term order.

### Centring

A numeric predictor is centred by its centring rule, wherever it appears, in the fixed part, in interactions and in random terms:

- none: the column is used as it is.
- value: the column minus a constant that the caller gives as a decimal string. The IR stores it as a decimal constant whose significant digits are those of the string as conventions.md (Decimal strings and centring constants) counts them, at least 1, so that '100' has 1 and '2.5' has 2.
- mean: the column minus its mean over the design sample, rounded to the significant digits of the rule (conventions.md, Decimal strings and centring constants).

The mean is computed so that both packages obtain the same double. The values of the design sample are summed exactly and the exact sum is rounded once to the nearest double, ties to even, as Python's math.fsum() does and as R does with an in-house exact summation (Shewchuk, 1997). That double is divided by the number of rows, rounded to the nearest double, and the result is rounded to k significant digits as conventions.md describes. For example, the values 0, 0.25 and 0.125 have the mean 0.125, which rounds to '0.12' with 2 significant digits. An empty design sample gives E6067. An exact sum that rounds to an infinity, or a constant of a 'mean' or 'value' rule whose nearest double is not finite, gives E6077, naming the column.

The fit uses the double nearest to the decimal constant, and the centred value of a row is its value minus that double, computed in double arithmetic. A centred value that is not finite gives E6077 when the design matrices are built (X). Without data, a 'mean' rule is stored with its significant digits and no constant, as for a plan written before the data are seen (conventions.md). The constant is computed and recorded with its sample when the data are available, which gives a new IR and a new IR hash.

## Samples

The IR reads the columns it names: the response, the trials column, the predictors, the grouping variables, the offset columns and the weights column.

- The design sample is the set of rows of the table in which no column that the IR reads is missing, other than the response and the trials column, and no column of the IR's `sample_columns` is missing. A column that the IR also reads in another role, as a predictor, grouping variable, offset or weights column, counts as read, so that a trials column that is also a predictor removes the rows in which it is missing. T0 checks and centring constants use the design sample, since it reads nothing of the outcome (registry.md, Terms).
- The analysis sample is the set of rows of the design sample in which the response is present and, when there is a trials column, the trials column is present and either above 0 or not finite. Rows with 0 trials, or a negative number of trials, leave the analysis sample and are reported (conventions.md, Declaration fields), whereas NaN and the infinities stay and give E6073 (Response, offsets and weights).

`sample_columns` holds the sample columns that the caller names, other than those that the IR reads already, in code-point order, so that one design sample has one representation. The design sample uses this list and not the caller's, so that naming the response or the trials column as a sample column changes neither the design sample nor the centring constants. A sample column must be a column of the data, or a field of the table block without data (E6070). A plan names the columns that its ceiling reads as the sample columns of every rung, so that a rung that drops every term of a grouping factor keeps the design sample of the ceiling and its centring constants (documents.md, The design section). The samples are determined before X, Z and the vectors, so a package can report them even when E6071 to E6073 or E6077 prevent the design matrices.

Missing values are those of the table reader ([tables.md](tables.md)), with the declared missing values of each field. Levels of categorical predictors come from the table as read, not from a sample, so the coding stays the same in every sample. A level that a sample lacks gives a column that is 0 in every row of that sample, or columns that depend on the intercept when it is the reference level, and the sequential rule drops them (sample.raw_vs_analysis and design.rank_deficiency in the registry).

## Design matrices

### X

X has one row for each row of the design sample, in the order of the table, and one column for each column of the fixed part, in column order. The value of a column in a row is 1 for '(Intercept)', and otherwise the product of the values of the term's variables in the term's order, multiplied from the left in double arithmetic, starting from the first:

- a numeric variable: its value, centred as above
- a categorical variable coded by its contrast: the value of the contrast for the column's level and the row's level
- a categorical variable coded by indicators: 1 if the row's level is the column's level and 0 otherwise

A row's level is its value, after NFC for strings, and integer levels match numbers by value. Every value of X must be finite: the first column of X, in column order, that holds a value that is not finite, such as a product or a centred value beyond the largest double, gives E6077, naming the column.

### Z

Z has one row for each row of the design sample, in the order of the table. For each random term in IR order, it has J × q columns, where q is the number of the term's columns and J the number of levels of its grouping factor in the design sample. The columns are ordered by level and, within a level, by the term's columns, so that the q columns of one level are adjacent. The value in a row is the value of the term's column, built as for X, if the row belongs to the level, and 0 otherwise. Once every column of X is checked, the first column of a random term, in IR order and then column order, that holds a value that is not finite gives E6077, naming the column of the random term.

The levels of a grouping factor are the distinct combinations of the values of its variables in the rows of the design sample, compared after NFC for strings. They are ordered by their first variable, then by the second and so on. Within one variable, numbers are ordered by value, strings by code point and booleans false before true. So the numeric labels 1, 2 and 10 keep that order, and the string labels 'i1', 'i10' and 'i2' keep theirs. Numbers are labelled as conventions.md (Serialisation) writes them and booleans as 'true' and 'false'. A level of a factor with one variable is written as its label. A level of a factor with several variables is written as their labels joined by ':', with each `\` and `:` in a label written as `\\` and `\:`, so that two levels never share a description. So the level of school 'S1' and class '2' is `S1:2`, and the level of the labels 'a:b' and 'c' is `a\:b:c`.

### Response, offsets and weights

The response vector has one value for each row of the analysis sample. For a response with a declared event level, it holds 1 where the value equals the event level, after NFC for strings and by value for numbers, and 0 otherwise. The IR does not record whether a response of integers with a declared event level has declared categories, so the event level decides for every response that has one. Otherwise, the vector holds the response itself for a numeric response with the transform 'identity', its natural logarithm for 'log' (E6071 for a value that is not positive) and 1 and 0 for true and false for a boolean response. Without a declared event level, a categorical response has no response vector, and checks that need it report not_available with the reason declaration_missing (conventions.md, Declaration fields). The offset vector is the sum of the offsets in IR order, each added from the left, with the natural logarithm for the transform 'log' (E6071 for a value that is not positive). Weights must be positive (E6072). Logarithms are computed with the platform's log(), whose last bit can differ between platforms, so these vectors are compared within a tolerance and are not part of any hash.

A number column can hold the non-finite values NaN, +∞ and −∞, which the table reader returns as values, not as missing values ([tables.md](tables.md), Field types). A non-finite value in a row of the design sample, in a numeric column that the IR reads other than the response and the trials column, gives E6073 when the builder computes the mean centring constant of that column or when the design matrices are built, and a non-finite value of the response or the trials column in a row of the analysis sample gives E6073 when the response vector is built.

## Sequential rule for aliased columns

The sequential rule decides which columns of an ordered set depend on earlier ones. lme4 drops the later member of each exact dependency in model-matrix order, whereas a greedy pivoted QR can drop a different column (01-design-review.md), so both packages apply this rule wherever the registry refers to it.

Given columns v1, …, vp of n rows, in order, the rule considers each in turn. A column whose values are all 0 is dropped. Otherwise, the column is divided by its largest absolute value, which changes neither its span nor the test below and keeps the squares in its norm from overflowing or underflowing. Let r be the residual of the scaled column after orthogonal projection onto the span of the columns kept so far. The column is kept if the norm of r exceeds τ times the norm of the scaled column, with τ = 1e-7, and dropped otherwise. The rank of the set by the sequential rule is the number of columns kept.

The residual is computed against an orthonormal basis of the kept columns, built from their residuals, with two passes of Gram–Schmidt orthogonalisation or with Householder reflections. Either keeps the error of the computed residual near the rounding error of the column, so the two packages disagree only for a column whose relative residual lies within that error of τ. Exact dependencies, such as those of indicator columns and of empty cells, give relative residuals near 1e-16, far below τ.

## Covariance parameters

A random term with q columns has an unstructured covariance matrix with q variances and q(q − 1)/2 covariances, which IR 0.1 states as covariance 'unstructured'. Its parameters are listed in the order of the lower triangle by columns, as lme4 lists the elements of θ: for each column j in order, the variance of column j, then its covariance with each later column. The variance of column c of the term named t is named 't: var(c)', and the covariance of columns c and d, c earlier, 't: cov(c, d)'. For example, '1 + x | g' has the parameters '1 + x | g: var((Intercept))', '1 + x | g: cov((Intercept), x)' and '1 + x | g: var(x)'. The parameters of the random terms come in IR order, followed, for a Gaussian model, by the residual variance, named 'residual'.

## Names

Names in the IR are formed as follows. Every column name in the IR is written in NFC, as the hashable profile requires, whatever form the data or the formula use. In the name of a term, a grouping factor or a random term, a variable is written as its column name when the name is a bare name of the grammar that is not a reserved word, and between backquotes otherwise. The name of a predictor or of a column uses the column name as it is.

| Name of | Form | Examples |
|---|---|---|
| a predictor or grouping variable | the column name | `cond`, `reaction time` |
| a term | '(Intercept)', or its variables in their order joined by ':', each written as above and, when it carries a level, followed by the level's label in square brackets | `(Intercept)`, `cond:x`, `` `word frequency` ``, `a[A2]:x` |
| a column | '(Intercept)', or the components for the term's variables joined by ':', each the column name as it is, without backquotes, for a numeric variable and the column name followed by the level's label in square brackets for a categorical one | `cond[B]:x`, `wave[1]`, `flag[true]`, `word frequency` |
| a grouping factor | its variables in order, joined by ':', each written as above | `school:class` |
| a random term | '1' or '0' for its intercept, then ' + ' and each other term of its left-hand side in term order, then ' \| ' and its grouping factor | `1 + cond \| subject`, `0 + x \| g`, `1 \| school:class`, `0 + a[A2] \| g` |

The label of a level is the string itself, an integer in decimal digits and a boolean as 'true' or 'false'. A column of a categorical variable is named after its level whatever the coding, so `cond[B]` holds the treatment, sum or simple contrast for level B, or its indicator. Two columns of the fixed part, or of one random term, with the same name give E6059.

Neither the fixed part nor a random term may have more than 10,000 columns, and no name of the IR may have more than 10,000 characters, as ir.schema.json requires of an IR name. The builder counts the columns of the fixed part and of each random term before it forms them, before any term of a frozen factor is split, and reports E6075 for the first that would have more, the fixed part first and then the random terms in IR order. Once the IR is assembled, the first name, in the order of the canonical serialisation of the IR, that has more than 10,000 characters gives E6076.

## The IR document

The IR is a JSON object in the hashable profile, with the members below, which ir.schema.json describes.

| Member | Content |
|---|---|
| `ir_version` | '0.1.0' for this specification. Every 0.1.x version is read, and other versions give E1441. |
| `response` | the response's `variable` and `transform`, with the declared `event_level` or `trials` when there is one. Absent for a one-sided formula. |
| `predictors` | for each predictor, keyed by column name: `kind` 'numeric' with its `centring`, or `kind` 'categorical' with its `levels`, `levels_source` ('declared', 'table' or 'boolean'), `contrast`, `reference` and, only when its coding is frozen, `frozen` true |
| `fixed` | `terms`, each with its `name` and its `variables` in term order, each categorical one with its `coding` ('contrast' or 'indicator') and, in a term that '||' has split, its `level`, and `columns`, each with its `name`, its `term` as an index from 0 into `terms` and its `levels`, the level of each categorical variable of the term |
| `random` | the random terms in IR order, each with its `name`, its grouping `factor` by name and its `grouping` variables in order, the `covariance` 'unstructured' and the `terms` and `columns` of its left-hand side, as for the fixed part |
| `offsets` | the offsets in order, each with its `variable` and `transform` |
| `weights` | the `variable` of the weights, when the caller names one |
| `sample_columns` | the sample columns that the IR does not otherwise read, in code-point order, when there are any |

`centring` holds the rule. For 'mean', it holds `sample`, 'design', and either `significant_digits`, before the data are seen, or `constant`, a decimal constant with its significant digits, afterwards. For 'value', it holds the `constant`.

The members `predictors`, `fixed`, `random` and `offsets` are always present, so that one model has one representation, even when they are empty. Levels and level labels are in NFC, as the hashable profile requires. The IR holds no labels of grouping factors, no row and no value from the data other than the levels of categorical predictors and the centring constants, so that it can be shared and hashed (02-decisions.md, cross-cutting conventions).

### Validation

A validator of an IR document checks `ir_version` first (E1441), then ir.schema.json (errors.md, Structural validation), then one rule in code. From the predictors and, for each part, its intercept, the variable sets of its terms in their order, their variables' order and the levels that variables of split terms carry, it derives the coding of each variable in each term, the columns and every name as this document specifies, and checks that the document holds exactly those. It also checks that each reference level is one of the levels, that `term` indices are in range, that terms and random terms do not repeat, that no two random terms of a grouping factor share a column, that a variable carries a level only in a random term with one term, only for a frozen predictor and only for a level other than its reference, that the offsets are in order and that `sample_columns` is in code-point order and holds no column that the IR otherwise reads. The first member, in the order of the canonical serialisation, that differs from what the rules give is reported with E6101 at its JSON Pointer. M3's plan validator applies this rule to the IR of each rung.

### Example

The formula `rt ~ cond + (1 + cond | subject)`, with a declaration whose table block declares 'rt' as a number, 'cond' as a string with the categories A and B and 'subject' as a string, no data and the coding `{"cond": {"contrast": "simple"}}`, gives the IR below, whose members are shown in canonical order. It is case ordinary-33 of the corpus.

```json
{
  "fixed": {
    "columns": [
      {"levels": {}, "name": "(Intercept)", "term": 0},
      {"levels": {"cond": "B"}, "name": "cond[B]", "term": 1}
    ],
    "terms": [
      {"name": "(Intercept)", "variables": []},
      {"name": "cond", "variables": [{"coding": "contrast", "variable": "cond"}]}
    ]
  },
  "ir_version": "0.1.0",
  "offsets": [],
  "predictors": {
    "cond": {"contrast": "simple", "kind": "categorical", "levels": ["A", "B"], "levels_source": "declared", "reference": "A"}
  },
  "random": [
    {
      "columns": [
        {"levels": {}, "name": "(Intercept)", "term": 0},
        {"levels": {"cond": "B"}, "name": "cond[B]", "term": 1}
      ],
      "covariance": "unstructured",
      "factor": "subject",
      "grouping": ["subject"],
      "name": "1 + cond | subject",
      "terms": [
        {"name": "(Intercept)", "variables": []},
        {"name": "cond", "variables": [{"coding": "contrast", "variable": "cond"}]}
      ]
    }
  ],
  "response": {"transform": "identity", "variable": "rt"}
}
```

Its canonical bytes, 783 bytes on one line, have the IR hash `sha256:ae50b9fcbcdb4f4e6f1757d4cf3954a56c0864e4483bbddca58ff966c1d0322c`, which the rfc8785 Python package, used as an oracle, confirms. In X and in the random term's columns, `cond[B]` is 0.5 for B and −0.5 for A.

## Errors

The builder reports one issue: the first that its stages find, in this order.

1. Length: E6001.
2. Tokens: the lexical issue at the lowest offset (E6002 to E6007), then E6008 when there is no '~'.
3. Syntax: the first, in the order of the tokens, of a token that cannot continue the formula (E6010, E6011, E6013) and a '(' that opens a 65th level of nesting (E6021).
4. Structure: the violation at the lowest offset, then the lowest code (E6006, E6012 to E6020).
5. Expansion: the issue at the lowest offset, then the lowest code, among those that the rules of Expansion find (E6031 to E6038).
6. Context, in passes. Each pass reports its first issue, by offset and then code for located codes, and by code-point order of the column, then code, for the others. A pass runs only when the passes before it found nothing.
   1. Columns: E6051.
   2. Uses: E6052, E6053, E6054 and E6068.
   3. Declared columns, weights and sample columns: E6065 for the trials column, then for the exposure column, then E6066, then E6070 for the first sample column, in the caller's order, that is not a column.
   4. Coding: E6061, E6063 and E6062, in the order that the coding argument sets out above, which replaces the order by column and then code.
   5. Levels: E6055, E6056 and E6074.
   6. Reference levels: E6064, by predictor in code-point order.
   7. Exposure: E6057.
   8. Size: E6075 for the fixed part and then each random term in IR order, before the terms of frozen factors are split.
   9. Columns of random terms: E6058, then E6059 for the fixed part and then each random term in IR order.
   10. Centring: E6067, E6073 and then E6077, by predictor in code-point order.
   11. Names: E6076, for the first name in the order of the canonical serialisation of the IR.

Terms of frozen factors are split after pass 8. The builder of the design matrices reports E6071 to E6073 and E6077, the first in this order: E6073 for a column of the design sample, by column in code-point order, E6077 for a column of X and then of Z, E6071 for each offset with the transform 'log', in IR order, E6072, E6073 for the response and then for the trials column in the analysis sample, and E6071 for a response written with log(). A Stream B run reports E6069 before its T0 checks (registry.md, Tier and inputs), and a validator of IR documents E6101. Messages are rendered as errors.md describes. The argument {intercept} of E6015 is the number, '0' or '1', or '- 0' however the sign and the number are spaced. The argument {use} of E6052 is one of 'the response', 'the argument of log()', 'a predictor' and 'an offset'. The argument {term} of E6031 and E6035 is the name of the term as Names forms it.

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
| E6055 | formula_levels_unknown | the levels of a categorical predictor are neither declared nor found in data |
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

## Differences from R and lme4

The grammar is that of lme4 formulas. The term expansion, the order of terms and columns and the choice between contrasts and indicators agree with R 4.3.3's terms() and model.matrix() and with the random-effects columns of lme4 1.1-35.1's lFormula() on the valid cases of the corpus with treatment coding that they accept and on about 1,000 generated formulas that the suite accepts, once the names are translated. These functions were run as black-box oracles, and no code of R or lme4 was read. The suite departs from them where they depend on the locale, the data or the engine, or accept a formula that is probably a mistake:

- Levels come from the declaration or from the table as read, and a level is never dropped because a sample lacks it. R drops unused levels in the model frame, which silently changes the reference level when it is the level emptied (01-design-review.md).
- Levels of strings are in code-point order after NFC, whereas R's factor() sorts by the collation of the locale.
- Ordered categories use the contrast of the coding argument, treatment by default, not polynomial contrasts.
- A factor whose coding is frozen keeps its contrast in every term, so that '||' can split it into uncorrelated terms for its contrast columns. R and lme4 would expand it into indicators.
- A column that identifies persons cannot be a predictor, so that the IR never lists the labels of persons.
- Column names put the level in square brackets, `cond[B]`, where R writes `condB`, and sum-coded columns are named after their levels, where R numbers them.
- The levels of a grouping factor of several variables are the distinct combinations of their values. R and lme4 paste the labels with ':', which merges combinations such as ('a', 'b:c') and ('a:b', 'c').
- Random terms keep the order of the formula, grouped by factor. lme4 orders them by the number of levels of their grouping factor, which depends on the data, and writes a nested factor inner first, as `class:school` for `school/class`.
- '||' with a categorical column is an error. lme4 1.1-35.1 expands `(1 + f || g)` to `(1 | g) + (0 + f | g)`, which is not identified (01-design-review.md), and the default of lme4 2.x differs again.
- Removing an absent term, '- 0', a subtracted random term, which lme4 adds, a duplicate random term, a column shared by two random terms of one factor, a repeated grouping variable and a parenthesised expression that removes all its terms are errors. R and lme4 accept them.
- A part with more than 10,000 terms or columns and a name of more than 10,000 characters are errors, where R and lme4 try to build them.
- Functions other than offset() and log() are not evaluated, and one-sided formulas are allowed, since T0 audits need no response.

## References

Bates, D., Mächler, M., Bolker, B., & Walker, S. (2015). Fitting linear mixed-effects models using lme4. *Journal of Statistical Software, 67*(1), 1–48. https://doi.org/10.18637/jss.v067.i01

International Organization for Standardization. (1996). Information technology: Syntactic metalanguage: Extended BNF (ISO/IEC 14977:1996).

R Core Team. (2024). *R: A language and environment for statistical computing* (Version 4.3.3), documentation of formula, terms.object and model.matrix. R Foundation for Statistical Computing. https://www.R-project.org/

Shewchuk, J. R. (1997). Adaptive precision floating-point arithmetic and fast robust geometric predicates. *Discrete & Computational Geometry, 18*(3), 305–363. https://doi.org/10.1007/PL00009321

Wilkinson, G. N., & Rogers, C. E. (1973). Symbolic description of factorial models for analysis of variance. *Journal of the Royal Statistical Society: Series C (Applied Statistics), 22*(3), 392–399. https://doi.org/10.2307/2346786
