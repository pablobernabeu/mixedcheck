# Conventions

This document states the conventions that every reader, writer and validator in both packages follows. It turns the cross-cutting conventions of [02-decisions.md](../design/02-decisions.md) into rules precise enough for two independent implementations to produce the same bytes, hashes and error codes. The shared definitions are in [spec/schemas/defs.schema.json](../../spec/schemas/defs.schema.json), and the error codes are in [spec/errors.json](../../spec/errors.json), described in [errors.md](errors.md). Where this document and a schema disagree, this document prevails and the schema is corrected.

The rules on reading, profiles, serialisation and hashing make up canonicaliser version 0.1.0, which spec/versions.json records. 'Must' marks a requirement. Bytes are written in hexadecimal (EF BB BF), code points as U+ followed by at least four hexadecimal digits, and byte offsets count from 0 at the first byte of the input.

## Scope and terms

- A document is a JSON value that a schema of the bundle describes, such as a declaration, a plan, the compiled registry or a results document. A section is a JSON value inside a document at a JSON Pointer that its schema names.
- A profile is a set of rules on JSON values beyond RFC 8259. There are two, 'hashable' and 'data'. The strict reader also has a 'plain' mode with no profile.
- A reader turns bytes into a value. A writer turns a value held in memory into canonical bytes. A validator checks a value against a document schema and the rules enforced in code.
- The canonical bytes of a value are its RFC 8785 serialisation encoded in UTF-8.
- A hash is a public SHA-256 digest of canonical bytes or of a file. A keyed commitment is an HMAC-SHA-256 digest under a key held in an internal sidecar.
- A shareable file may leave the analyst's machine. An internal sidecar holds what must not, such as observation keys and commitment keys (02-decisions.md, cross-cutting conventions).
- An identifier is a name used to refer to something, such as a column name, a unit name or a check ID. A label is a value of a categorical variable or grouping factor in the data.

## Text and Unicode

### UTF-8

All text is UTF-8. A byte sequence is valid UTF-8 when it is well formed according to Table 3-7 of the Unicode Standard (section 3.9). This excludes overlong forms, the encoded surrogates ED A0 80 to ED BF BF and anything above U+10FFFF, and includes the noncharacters such as U+FFFE. A string is a sequence of Unicode scalar values, so it never contains a surrogate code point. U+0000 is not allowed in any string or key, in every profile and mode, because R cannot hold it in a character string (E1202). For the same reason, no key may be empty (E1109), because R cannot tell an empty name from a missing one.

A reader validates the whole input before parsing it. If the input is invalid, the reader reports E1201 at the offset of the first byte of the first ill-formed sequence, found by decoding from the start: at each position, the bytes from there on either start a well-formed sequence or the position is reported. A truncated sequence is therefore reported at its lead byte and a stray continuation byte at its own offset, as Python's UnicodeDecodeError.start reports them.

### Strings in R

R marks each string with an encoding. A string is acceptable to a writer or a hasher when it is ASCII, when it is marked 'UTF-8' and valid (E1201 otherwise) or when it is marked 'latin1', which enc2utf8() converts exactly. A string marked 'bytes' is refused (E1205). A string marked 'unknown' that contains a byte of 80 or above is refused (E1204), because its encoding cannot be known.

Readers read files as raw bytes with readBin(), validate them and mark the strings with `Encoding(x) <- "UTF-8"`, without re-encoding. They never read text through a connection with an `encoding` or `fileEncoding` argument and never call enc2utf8(), enc2native() or iconv() with `from = ""` on unmarked strings.

Strings that the caller passes to a reader or a validator, such as a declaration in memory given to validate_declaration() or, from M2, a data frame, cross an input boundary. There, an unmarked non-ASCII string is marked as UTF-8 if the session's native encoding is UTF-8 (`l10n_info()[["UTF-8"]]` is TRUE) and it is valid UTF-8 (E1201 otherwise). In any other session, it is refused with E1204, whose message tells the user to mark the string as UTF-8 or to read the data with `encoding = 'UTF-8'`. Strings marked 'latin1' are converted with enc2utf8(). After the boundary, every string the package holds is ASCII or marked UTF-8, and the value that a validator returns holds its strings in that form. Writers and hashers, among them canonical_bytes() and canonical_hash(), refuse an unmarked non-ASCII string in every session (E1204), so that whether a value can be written or hashed never depends on the locale. The value that validate_declaration() returns can therefore be hashed in any session, and the value passed to it only when its strings are ASCII or marked.

These behaviours of R 4.3.3 make the rules necessary. They were observed in this project:

- In a C locale, the literal `"\u00e9"` in R code yields the bytes C3 A9 marked 'unknown'. Code and tests build non-ASCII strings with intToUtf8() or from raw bytes with `Encoding<-`.
- In a C locale, enc2utf8() and jsonlite::toJSON() turn an unmarked 'é' read without an encoding into the text '<c3><a9>', and read.csv() with `fileEncoding = 'UTF-8'` fails (evidence/decisions/G-critic/out/c_locale_encoding.txt).
- sort() and order() collate by locale unless `method = "radix"` is given. With it, they compare bytes, which orders UTF-8 strings by code point but misorders a 'latin1'-marked string among UTF-8 ones.
- as.character() and format() of a double give 15 significant digits, and format() follows `options(OutDec)`. Canonical numbers are never formatted with them.

### Strings in Python

A str is a sequence of code points. A writer or hasher refuses a str that contains a surrogate code point (U+D800 to U+DFFF), as decoding with 'surrogateescape' produces (E1206). A bytes value is never treated as a string. Files are opened in binary mode, or in text mode with `encoding="utf-8"` and `newline=""` where text mode is needed.

### NFC

Normalisation form C (NFC) is defined in Unicode Standard Annex #15. In R, it is computed with `utf8::utf8_normalize(x)` with its default arguments, on strings marked UTF-8. In Python, it is computed with `unicodedata.normalize("NFC", s)` and tested with `unicodedata.is_normalized("NFC", s)`.

The two packages can use different versions of the Unicode Character Database. utf8 1.2.4 implements Unicode 14.0, and the R package requires utf8 1.2.4 or later, the version against which the corpora were checked. Releases up to 1.2.2 predate Unicode 14.0. utf8 1.2.4 reorders U+1E2AE, a combining mark added in 14.0, but leaves U+1E4EC, added in 15.0, in place. Python 3.11 uses Unicode 14.0.0, 3.12 uses 15.0.0, 3.13 uses 15.1.0 and 3.14 uses 16.0.0. By the Unicode normalisation stability policy, NFC gives the same result in every version from 14.0 on for any string whose code points were all assigned in Unicode 14.0. For a string with a code point assigned later, the result can differ: for 'x' followed by U+1E4EC and U+0316, Python 3.13 puts U+0316 first and utf8 1.2.4 leaves the string unchanged.

[spec/unicode/assigned-14.0.json](../../spec/unicode/assigned-14.0.json) lists, as ranges, the code points that Unicode 14.0 assigns, those whose general category is not Cn, and both packages read it. A string is normalisable when every code point it holds is listed there. Only normalisable strings are normalised or tested for NFC, so that both packages always agree. Results documents record the Unicode version each package used (utf8's package version in R, `unicodedata.unidata_version` in Python).

NFC applies in three ways:

1. Every string and key of a document in the hashable profile must be normalisable (E1208) and already in NFC (E1203). Readers and writers never normalise a document. They refuse it, so that a hash always covers the bytes the user wrote and never depends on the Unicode version of either package.
2. Two identifiers or two labels are equal when their NFC forms are the same sequence of code points. A string that is not normalisable stands for itself in such a comparison, compared code point by code point. There is no case folding, no compatibility mapping (NFKC) and no trimming of white space. This is how declared column names are matched with the columns of the data, and declared category values and event levels with values in the data.
3. Distinct strings of one set that are equal after NFC, such as two spellings of one label in a column, are treated as one and the merge is reported, never split silently. W1251 reports it unless the component's own specification defines a code or names a check of the registry that reports it, as ir.md does for the levels of a column.

### Order

Strings are ordered by the code points of their NFC forms, compared one by one, with a prefix before any longer string. For valid UTF-8 this is the order of the bytes, and for strings without characters outside the Basic Multilingual Plane (BMP) it is also the order of their UTF-16 code units. In R, `order(x, method = "radix")` gives this order for strings that are all ASCII or marked UTF-8. In Python, sorted() gives it for str values.

### Locale

Every function gives the same result under any locale, including LC_ALL=C, and on Windows. Canonical paths use no locale-dependent function: no default collation, no case mapping, no locale-aware number formatting (R's format() and formatC() with `OutDec`, Python's locale module) and no conversion through the native encoding. R's sprintf() and Python's `%` and format() are locale-independent for numbers and may be used.

## Strict reader

The strict reader turns bytes into a value under a profile, 'hashable' or 'data', or in the 'plain' mode, which applies RFC 8259 and, of the I-JSON rules of RFC 7493, those on unique member names (E1029), on unpaired surrogates (E1026) and on numbers that a double can hold (E1105 and E1106), together with the rules on U+0000 and empty keys that hold in every mode, but no profile. Noncharacters such as U+FFFE and U+FFFF, which RFC 7493 also excludes, are accepted, raw or escaped, in the plain mode and the data profile. The hashable profile refuses them with E1208, as it refuses every code point that Unicode 14.0 does not assign. The plain mode serves test vectors and files that are not documents. Every document is read in its profile.

### Stages

The reader works in four stages and stops at the first error, so it reports exactly one issue.

1. Input. A file that does not exist gives E1001, and one that cannot be read gives E1002. If the input starts with EF BB BF, the reader reports E1003.
2. UTF-8. The whole input is validated (E1201), as described under UTF-8.
3. Syntax. The input is scanned from left to right against the grammar of RFC 8259, and the first syntax error is reported.
4. Values. The parsed value is checked, token by token in the order of the input, against the rules below for the mode or profile. The first token that breaks a rule is reported.

A syntax error anywhere therefore takes precedence over a value error earlier in the input, and within stage 4 the token that starts first is reported.

### Syntax

White space is the bytes 20, 09, 0A and 0D, and may appear before and after every value and structural character. The scan expects a value at the start, after ':' in an object, after '[' or ',' in an array and nowhere else. At a value position, the scan proceeds as follows.

- If the input has ended, it reports E1021 at the offset equal to the length of the input. An empty input or one of white space only gives E1021.
- If the bytes there begin with `NaN`, `Infinity` or `-Infinity`, it reports E1027, naming the literal.
- If the byte is '-', '+', '.' or a digit, it reads the longest run of bytes from the set '0' to '9', '+', '-', '.', 'e' and 'E'. If the run does not match the RFC 8259 number grammar `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?` in full, it reports E1028 at the start of the run, naming the run. A valid run is a number token, and the scan continues after it, so that `[0x1F]` gives E1022 at 'x' and `0x1F` alone gives E1023 there.
- If the byte is 't', 'f' or 'n', it compares the input with `true`, `false` or `null`. At the first byte that differs it reports E1022, and if the input ends first it reports E1021.
- If the byte is '"', it reads a string token. If the byte is '{' or '[', it reads an object or an array.
- Any other byte gives E1022, naming the character that starts there.

A string token runs from '"' to the next unescaped '"'. A raw byte from 00 to 1F inside it gives E1024 at its offset, with its code point. A backslash must be followed by '"', '\', '/', 'b', 'f', 'n', 'r', 't' or 'u' and four hexadecimal digits in either case, and otherwise E1025 is reported at the offset of the backslash. If the input ends inside a string, including inside an escape, E1021 is reported, so that `"\u12` gives E1021 and `"\u12"` gives E1025.

In an object, '{' is followed by '}' or by a string token as the first key. After a key comes ':', then a value, then ',' and the next key, or '}'. In an array, '[' is followed by ']' or by a value, and after each value comes ',' and the next value, or ']'. A missing structural character gives E1022 at the byte found instead, or E1021 at the end of the input. A trailing comma, as in `[1,]`, therefore gives E1022 at ']'.

Containers nest to a depth of at most 64, counting the outermost '[' or '{' as depth 1. The '[' or '{' that would open depth 65 gives E1030 at its offset.

After the top-level value and any white space, the input must end. The first other byte gives E1023 at its offset.

### Values

Stage 4 attributes each check to a token and reports the token whose first byte comes first. A token's location is the offset of its first byte: the opening '"' of a string or key, the first byte of a number and the 'n' of null. Within one token, the checks run in the order below, and the first that fails is reported.

For a key:

1. Escapes are decoded. An escape `\uD800` to `\uDBFF` must be followed at once by an escape `\uDC00` to `\uDFFF`, and the pair encodes one code point. Any other surrogate escape is unpaired and gives E1026.
2. The key must not contain U+0000 (E1202).
3. The key must not be empty (E1109).
4. In both profiles, the key must not contain a code point above U+FFFF (E1108).
5. In the hashable profile, the key must be normalisable (E1208).
6. In the hashable profile, the key must be in NFC (E1203).
7. The key must differ from every earlier key of the same object, compared as sequences of code points (E1029).

For a string value, checks 1, 2, 5 and 6 apply in that order. For null, the hashable profile reports E1101. For a number token, the profile rules below apply.

### Numbers

A number token is read as an exact decimal value. Its sign, the digits of its integer and fraction parts and its exponent give the value D × 10^e, where D is the digit string with leading zeros removed and with trailing zeros removed, each removed trailing zero adding 1 to e. If no digit remains, the value is zero. Otherwise, n is the number of digits of D, the value is an integer when e ≥ 0 and p = n + e − 1 is the power of ten of its leading digit. For example, `4.50` gives D = 45, e = −1, n = 2 and p = 0, and `25e-1` gives the same value as `2.5`.

The hashable profile accepts a number token when its value is zero, when it is an integer with p ≤ 14, when it is an integer with p = 15 and a value of at most 9007199254740991 in magnitude, or when it is not an integer, n ≤ 15 and p ≥ −307. Otherwise, it reports E1102 for an integer, E1103 for a non-integer with n > 15 and E1104 for a non-integer with p < −307, checked in that order. Exponents are computed exactly. An exponent beyond ±10^9 with a non-zero D can be classified as out of range at once, since no input below 1 GB brings such a value back into range.

The data profile and the plain mode convert the value to the nearest IEEE 754 double, rounding ties to even. A result of ±infinity gives E1105, and a result of zero from a non-zero value gives E1106. For example, `1.7976931348623158e308` gives the largest double, `1.7976931348623159e308` gives E1105, `2.4703282292062328e-324` gives 5e-324 and `2.4703282292062327e-324` gives E1106. The hashable profile also converts accepted tokens to the nearest double, which for these tokens has the same decimal value.

Conversion must be correctly rounded. R's as.numeric() is not. In R 4.3.3 on Linux, `as.numeric("-76944133.284736")` returns -0x1.2584c152391d6p+26, where the correctly rounded value is -0x1.2584c152391d5p+26. In this project's tests, as.numeric() misconverted 43 of 399,827 strings written at shortest or 17-digit precision and 171 of 295,773 decimals of at most 15 significant digits, such as `7.32e-97` and `-6.1892785e-12`. `jsonlite::parse_json()` converted all of them correctly on Linux. The R reader therefore converts number tokens with a routine that rounds correctly, such as jsonlite's parser, and the corpora include these cases, so that a platform on which that routine rounds incorrectly fails the tests.

### Values in memory

Readers return objects as named lists in R and dicts in Python, with members in the order of the input, and arrays as unnamed lists in R, never simplified to atomic vectors, and lists in Python. An empty object is `setNames(list(), character(0))` in R. Strings are character strings marked UTF-8 in R and str in Python. Booleans are logical in R and bool in Python. null is NULL in R and None in Python. Numbers are doubles in R, never integers. In Python, a number token without a fraction or an exponent whose value lies within ±9007199254740991 becomes an int, and every other number a float. Validators compare numbers by value, so that 1, 1.0 and 1e0 are the same integer, as JSON Schema requires.

A reader must read a results document of a few megabytes in seconds. In R, handling the input one byte at a time in R code is too slow for this, so the reader works on the raw vector with vectorised operations.

## Profiles

### Hashable profile

The hashable profile serves documents whose hash must be identical in both languages: declarations, plans and their sections, the IR, the compiled registry and every JSON file under spec/. It allows objects, arrays, strings, booleans and numbers, under these rules:

- no null (E1101) and no non-finite number (E1027 when read, E1107 when written)
- integers within ±9007199254740991, that is ±(2^53 − 1), the range of RFC 7493 (E1102). This reads 'integers within ±2^53' in 02-decisions.md as the integers that a double holds exactly together with their neighbours.
- non-integers with at most 15 significant digits as written (E1103) and a magnitude of at least 1e-307 (E1104), so that every accepted decimal maps to one double and back to the same decimal
- strings and keys normalisable (E1208) and in NFC (E1203), without U+0000 (E1202)
- keys not empty (E1109) and without characters outside the BMP (E1108), so that ordering keys by code point, by UTF-8 bytes and by UTF-16 code units agree

A writer applies the same rules to values in memory, reporting a JSON Pointer as the location. A missing value, which is R's NULL or NA of any type or Python's None, gives E1101, and NaN or an infinity gives E1107. For a finite double x, let s be its serialisation as described under Numbers in Serialisation. If x is an integer, its magnitude must be at most 9007199254740991 (E1102). Otherwise, s must have at most 15 significant digits (E1103) and a decimal value of at least 1e-307 in magnitude (E1104). The writer's rule on s and the reader's rule on tokens accept the same doubles, so that what one package writes the other reads. A value such as 1/3, whose shortest form has 16 digits, cannot be written in this profile and is stored as a decimal string instead.

### Data profile

The data profile serves results documents, their access log section, internal sidecars and bring-your-own estimates. It allows every JSON value, under these rules:

- numbers are finite doubles after correctly rounded conversion (E1105, E1106)
- strings and keys contain no U+0000 (E1202), and keys are not empty (E1109) and have no characters outside the BMP (E1108). Strings need not be in NFC, because they can hold labels exactly as the data give them.
- null stands for a missing value. It is allowed only where the document schema pairs it with an availability status, as `reported_number` in defs.schema.json does.
- a computed non-finite double is written as the string 'NaN', 'Infinity' or '-Infinity' in a position that the schema types as `data_number`. A missing value is never written as 'NaN', and a computed NaN is never written as null.

A writer in the data profile writes R's NA of any type, R's NULL and Python's None as null, R's NaN (tested with is.nan(), since is.na() is also TRUE for NaN) and Python's float('nan') as 'NaN' and infinities as 'Infinity' and '-Infinity'. A reader leaves these strings as strings, and the code that interprets a `data_number` position converts them. Negative zero is written as 0.

In both profiles, Python ints must lie within ±9007199254740991 (E1102), the range in which the reader returns integers as int and in which every integer and its neighbours are exact doubles. Larger integers are passed as floats.

### Documents and profiles

| Document | Profile |
|---|---|
| Declaration, in JSON or converted from YAML | hashable |
| IR | hashable |
| Plan, including its design part and execution binding | hashable |
| Registry entry and compiled registry | hashable |
| Error catalogue and schemas under spec/ | hashable |
| Results document, including the access log | data |
| Internal sidecar | data |
| Bring-your-own estimates | data |

Object keys in every document are names that the schema defines or identifiers declared in a hashable document. Strings that come from the data, such as labels, appear as values, never as keys, so that the key rules never reject data.

## Serialisation

The serialiser writes a value as its canonical bytes by RFC 8785. The output is UTF-8 with no byte-order mark, no white space between tokens and no final line feed. A document written to a file consists of exactly its canonical bytes, so that the hash of the file equals the hash of the document. Human-maintained JSON files under spec/ are an exception: they are indented with two spaces, end with a line feed and are read through the strict reader like any other input.

### Literals and strings

true, false and null are written as `true`, `false` and `null`.

A string is written as '"', then each code point in turn, then '"'. U+0022 is written as `\"`, U+005C as `\\`, U+0008 as `\b`, U+0009 as `\t`, U+000A as `\n`, U+000C as `\f` and U+000D as `\r`. Every other code point from U+0000 to U+001F is written as `\u00` followed by two lower-case hexadecimal digits. Every other code point, including '/', U+007F, U+2028, U+2029 and characters outside the BMP, is written as its UTF-8 bytes.

### Numbers

A finite double x is written by the ECMAScript algorithm Number::toString (ECMA-262), as RFC 8785 requires:

1. If x is +0 or −0, the result is `0`.
2. If x < 0, the result is '-' followed by the result for −x.
3. Otherwise, let k, s and n be integers with k ≥ 1, 10^(k−1) ≤ s < 10^k and k as small as possible, such that the decimal s × 10^(n−k) converts to x under round-to-nearest, ties to even. If several values of s qualify, s is the one for which s × 10^(n−k) is closest to x, and of two equally close, the even one. The digits of s are its k decimal digits, and s does not end in 0.
4. If k ≤ n ≤ 21, the result is the digits of s followed by n − k zeros.
5. If 0 < n ≤ 21, the result is the first n digits of s, '.', and the remaining k − n digits.
6. If −6 < n ≤ 0, the result is '0.', −n zeros and the digits of s.
7. Otherwise, the result is the first digit of s, then, if k > 1, '.' and the remaining k − 1 digits, then 'e', '+' if n − 1 ≥ 0 or '-' otherwise, and the decimal digits of |n − 1|.

NaN and the infinities have no JSON form. The data profile writes them as strings before serialisation, and the hashable profile refuses them.

The following examples come from RFC 8785, appendix B, and from Node.js 22, which implements ECMAScript.

| Double (IEEE 754 bits) | Value | Written |
|---|---|---|
| 0000000000000000 | 0 | `0` |
| 8000000000000000 | −0 | `0` |
| 0000000000000001 | smallest subnormal | `5e-324` |
| 7FEFFFFFFFFFFFFF | largest double | `1.7976931348623157e+308` |
| 4340000000000000 | 2^53 | `9007199254740992` |
| 4430000000000000 | 2^68 | `295147905179352830000` |
| 444B1AE4D6E2EF50 | 10^21 | `1e+21` |
| 444B1AE4D6E2EF4F | below 10^21 | `999999999999999900000` |
| 44B52D02C7E14AF6 | 10^23 | `1e+23` |
| 44B52D02C7E14AF5 | below 10^23 | `9.999999999999997e+22` |
| 3EB0C6F7A0B5ED8D | 10^−6 | `0.000001` |
| 3EB0C6F7A0B5ED8C | below 10^−6 | `9.999999999999997e-7` |
| 41B3DE4355555555 | 1e9/3 | `333333333.3333333` |
| BECBF647612F3696 | −1e−5/3 | `-0.0000033333333333333333` |
| 43143FF3C1CB0959 | an example of RFC 8785 | `1424953923781206.2` |
| 3E7AD7F29ABCAF48 | 10^−7 | `1e-7` |
| 3FD3333333333334 | 0.1 + 0.2 | `0.30000000000000004` |
| 0060000000000000 | 2^−1017 | `7.120236347223045e-307` |

The last row shows why a simpler method fails. Formatting with `%.{p}e` for p = 1, 2, … and stopping at the first result that converts back to x gives the closest p-digit decimal at each step. At a power of two, the gap to the next lower double is half the gap to the next higher one, and the closest 16-digit decimal to 2^−1017 converts back to a different double. The loop therefore returns the 17-digit 7.1202363472230444e-307, although the 16-digit 7.120236347223045e-307 converts to x. Of the 2,098 finite powers of two, 46 behave this way. An implementation must search the shortest digit strings on both sides of x, as Ryu, Grisu with fallback and David Gay's dtoa in mode 0 do.

Python's repr() of a float gives the right digits but the wrong layout for RFC 8785: `1e+16` where ECMAScript writes `10000000000000000`, `1e-06` for `0.000001`, `1e-07` for `1e-7`, `100.0` for `100` and `-0.0` for `0`. The Python serialiser takes the digits and exponent from repr() and lays them out by steps 4 to 7. json.dumps() is never used for canonical bytes, since it escapes non-ASCII characters by default and formats floats with repr(). R has no shortest formatting, so the R serialiser finds the shortest digits itself and checks each candidate with a correctly rounding conversion, never with as.numeric().

### Arrays and objects

An array is written as '[', its elements separated by ',', and ']'. An object is written as '{', its members separated by ',', and '}', each member written as its key as a string, ':' and its value.

Members are sorted by their keys, compared as sequences of UTF-16 code units, each an unsigned 16-bit number, with a key that is a prefix of another first. The serialiser implements this order in full, so that it passes the sorting test of RFC 8785, section 3.2.3, in the plain mode. In both profiles, keys contain no characters outside the BMP, and the order equals code-point order and UTF-8 byte order, which `order(keys, method = "radix")` gives in R. The keys U+FF08 and U+1F600 show the difference: by UTF-16 code units, U+1F600 (D83D DE00) comes first, whereas by code points U+FF08 does.

### Values in memory

A writer accepts the following values and refuses anything else with E1301, naming the type.

| JSON | R | Python |
|---|---|---|
| object | a list whose names attribute is set, with every name a non-empty, non-NA and unique string (E1303 otherwise), and `setNames(list(), character(0))` when empty | dict with str keys |
| array | a list without a names attribute, `list()` when empty | list |
| string | a character vector of length 1 | str |
| number | a double or integer vector of length 1 | int (not bool), float, or a numpy integer or floating scalar, converted with int() or float() |
| true, false | a logical vector of length 1 | bool, or numpy.bool_, converted with bool() |
| null (data profile and plain mode) | NULL, or NA of type logical, integer, double or character | None |

In R, an atomic vector of any other length gives E1302, because a vector of length 1 cannot be told apart from an array of one element. An object with a class attribute, such as a factor, a Date or a data frame, gives E1301. In Python, tuples, sets, bytes, non-str keys and numpy arrays give E1301. The Python package recognises numpy scalars by their types numpy.integer, numpy.floating and numpy.bool_ without importing numpy when the caller has not, since subclasses of int such as numpy.int64 are not, and numpy.float64 is the only numpy type that subclasses float. A writer refuses a value nested more than 64 containers deep with E1030, as a reader does. Writers check values in the order of their canonical serialisation, keys before values, and report the first violation, with the checks of each value in the order given for readers.

### Worked example

The input below, read in the hashable profile,

```json
{
  "title": "caf\u00e9 \"study\"",
  "n": [1.0, 1e2, 0.000001, 1E-7, 4.50, -0, 25e-1],
  "a": {"z": true, "b": false, "é": "\u00e9"},
  "tab": "a\tb\u001f"
}
```

has these 117 canonical bytes, shown as text with 'é' standing for C3 A9:

```text
{"a":{"b":false,"z":true,"é":"é"},"n":[1,100,0.000001,1e-7,4.5,0,2.5],"tab":"a\tb\u001f","title":"café \"study\""}
```

Their SHA-256 is `288afb1eec38acd97fc29eb68a97d9200dd6e77da5ee06d7586945b51372b80d`. The rfc8785 Python package, used as an oracle, gives the same bytes.

## Hashes

A hash is the SHA-256 digest (FIPS 180-4) of canonical bytes, or of the bytes of a file, written in documents as 'sha256:' followed by 64 lower-case hexadecimal digits (`sha256_hash` in defs.schema.json). In R, it is computed with `cli::hash_raw_sha256()` (cli 3.2.0 or later) on the raw vector of the bytes, or with `cli::hash_file_sha256()` on a file. A character string is never hashed directly, because its bytes depend on its encoding mark. In Python, it is computed with `hashlib.sha256(data).hexdigest()`. Both return lower-case hexadecimal, and both give `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` for no bytes.

A hash of a document covers its canonical bytes. When a document records the hash of a part of itself, the part is a section at a JSON Pointer that the document's schema names, the hash covers the canonical bytes of that section and the section never contains the hash.

### Taxonomy

Public hashes may appear in shareable files. Each covers one thing.

| Hash | Covers | Bytes hashed |
|---|---|---|
| registry hash | the compiled registry | the bytes of spec/compiled/registry.json, which are its canonical bytes |
| declaration hash | a declaration | the canonical bytes of the declaration as read, after conversion from YAML when it was authored in YAML |
| IR hash | the canonical IR of one model | the canonical bytes of the IR (ir.md) |
| design-plan hash | the language-neutral part of a plan: the IR of every rung, the protected set, the stopping rule with its version, the terminal state and the declaration hash | the canonical bytes of that section of the plan |
| execution binding hash | the engine, its version, the optimiser settings, the encoding of each rung for that engine with its expressibility, and the design-plan hash that the binding refers to | the canonical bytes of the binding |
| results file hash | a written results file | the bytes of the file |

The design-plan hash depends only on values that both languages compute identically, and must match across languages (03-execution-plan.md, M3). The execution binding records how one engine in one language runs the plan. It is compared only within a language and engine, and a rung that the engine cannot express appears in it as not_available with the reason not_expressible. The plan schema names the two sections.

Anything computed from person-level data appears in shareable files only as a keyed commitment. An unkeyed hash of person-level data works as an oracle: a brute-force search over all 2^20 binary outcome columns of a class of 20 pupils recovered the column from its hash in 1.6 s (02-decisions.md). Unkeyed hashes of person-level data are therefore allowed only in internal sidecars and in parity tests.

## Keyed commitments

### Algorithm

A commitment is HMAC-SHA-256 (RFC 2104 with SHA-256) of a message under a key. With block size B = 64 bytes, a key longer than 64 bytes is first replaced by its SHA-256 digest, and the key is then padded with zero bytes to 64 bytes, giving K0. The commitment is SHA-256((K0 XOR opad) followed by SHA-256((K0 XOR ipad) followed by the message)), where ipad is the byte 36 and opad the byte 5C, each repeated 64 times. It is written as 64 lower-case hexadecimal digits.

Python uses `hmac.new(key, message, hashlib.sha256).hexdigest()` and compares digests with `hmac.compare_digest()`. R implements the construction with `cli::hash_raw_sha256()` and `xor()` on raw vectors, converting the inner digest from hexadecimal to raw before the outer hash. Both implementations accept keys of any length, so that they pass test cases 1 to 7 of RFC 4231. Test case 5 checks only the first 128 bits. For example, test case 1 (key 0B repeated 20 times, message 'Hi There') gives `b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7`, and test case 2 (key 'Jefe', message 'what do ya want for nothing?') gives `5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843`.

### Keys

A commitment key is 32 bytes. The package creates it from a cryptographically secure generator: `secrets.token_bytes(32)` in Python and, in R on Unix-alikes, `readBin("/dev/urandom", "raw", 32L)`, which reads the operating system's generator. Base R on Windows offers no access to the system generator, and the R package has no compiled code that could call BCryptGenRandom, so where /dev/urandom does not exist, as on Windows, or cannot be read, it takes the bytes from `openssl::rand_bytes(32)`, a generator over OpenSSL's RAND_bytes, when the package openssl, which it suggests, is installed. Without openssl there, creating a key without one supplied, as `audit()` does when the caller gives no key, gives E1312 (03-execution-plan.md, M2). A user can create a key with any secure generator outside R, for example `openssl rand -hex 32` or `python3 -c "print(__import__('secrets').token_hex(32))"`, and should keep it with the internal sidecar, not with the shareable files. Keys never come from R's or numpy's random number generators, which a seed set by the user determines and whose state the package must not change.

The user may supply a key as 64 lower-case hexadecimal digits (E1311 otherwise), for example to show that two results documents commit to the same outcome column. The key identifier is the first 16 hexadecimal digits of the SHA-256 digest of the 32 key bytes (`key_id` in defs.schema.json). It lets a verifier find the key, and reveals nothing of a random key.

The internal sidecar stores each key as a `commitment_key` object with its identifier, its 64 hexadecimal digits and the UTC time of its creation. A writer of a shareable file checks that no value in it is an object with exactly the members created, key and key_id, and refuses the file otherwise (E1315).

### What is committed

A commitment is written as a `keyed_commitment` object (defs.schema.json) with the algorithm 'hmac-sha256', the key identifier, the digest and what it covers:

| covers | Message |
|---|---|
| data_file | the bytes of a raw data file as stored, before any decoding |
| analysis_table | the canonical bytes of the analysis table with its observation keys, as [documents.md](documents.md) (Analysis table commitment) defines them |
| outcome_column | the canonical bytes of the outcome column with its observation keys, as [documents.md](documents.md) (Outcome column commitment) defines them |

Verification finds the key by its identifier in the sidecar (E1313 if it is absent), recomputes the digest and compares it with the recorded one (E1314 if they differ). keyed_commitment() computes a commitment of any of the three kinds to the bytes that the caller supplies. `audit()` builds the messages of all three kinds from the data it reads, and a caller who commits to an analysis table or an outcome column outside `audit()` supplies the message that documents.md defines.

### Example

With the key 00 01 02 … 1F (the 32 bytes from 00 to 1F), the key identifier is `630dcd2966c43366`, and the commitment to the 117 canonical bytes of the worked example under Serialisation is `dd8943be1fcb832169c6f874652f017415a37dddc77d6e9407ac0d910f67227a`.

## Status fields

Every finding carries status fields with the values below (02-decisions.md, cross-cutting conventions). Each field is an object with a member 'value', so that reasons and details can be added as further members, and defs.schema.json defines each as a definition of the same name.

| Field | Value | Meaning |
|---|---|---|
| availability | available | the check ran or the quantity was computed |
| | not_available | it was not, for the reason given |
| assessability | adequate | the check can detect what it looks for in this design, by its registry entry's assessability rule |
| | weak | it can, with reduced power (detection between .50 and .80 at the smallest harmful magnitude, for validated checks) |
| | not_assessable | it cannot, for the reason prerequisite_unmet or low_detection (detection below .50) |
| finding | consistent | no departure from the model was found |
| | detectable_inconsequential | a departure was found below the registry's threshold of consequence |
| | consequential | a departure was found at or above that threshold |
| optimisation | at_optimum | the objective matches and the gap to the best objective found is within the registry tolerance |
| | near_optimum | the gap exceeds the tolerance but lies within the registry's near-optimum bound, and counts as converged |
| | not_converged | the gap exceeds the near-optimum bound |
| | not_certified | the optimum could not be certified, and counts as converged only if a second optimiser reaches the same objective within tolerance |
| | objective_unavailable | no objective could be evaluated |
| | objective_offset_registered | the reported objective differs from the suite's by an offset registered for the engine and version |
| | contract_mismatch | the reported objective differs from the suite's evaluation at the reported estimates beyond tolerance, with no registered offset |
| threshold_proximity | clear | the statistic is not near a threshold |
| | near_threshold | a real statistic lies within the registry's proximity band of a threshold that a rule of the decision names (registry.md, Thresholds) |
| validation | validated | the threshold or rule was validated, by the study, language, engine and version range given |
| | descriptive | it was not validated, as for thresholds taken from the literature or set by convention |
| | outside_validated_range | it was validated, but the present language, engine, version or design lies outside the validated range |

The reasons for not_available are the same in both languages:

| Reason | Meaning | detail |
|---|---|---|
| engine_missing | the engine that fitted the model is not installed | the engine's package name |
| package_missing | another package that the check needs is not installed | the package name |
| capability_missing | the engine or adapter lacks a capability the check needs, such as X, Z, an objective function, refit, simulate or df | the capability |
| declaration_missing | the check needs a declaration field that is absent | the JSON Pointer of the field in the declaration |
| not_expressible | the engine cannot express the model or rung | the engine's package name |
| too_large | the problem exceeds a size limit in the registry | the limit, if the registry entry names one |
| privacy_suppressed | the privacy filter suppressed the output | the step of the filter that suppressed it ([privacy.md](privacy.md), Steps) |
| planned | the feature arrives in a later release | none, and 'version' holds the release, such as '1.1' |

The call `not_available('planned 1.1')` in 03-execution-plan.md therefore produces `{"reason": "planned", "value": "not_available", "version": "1.1"}`.

When availability is not_available, a finding carries no other status field, since nothing was computed. When it is available, the finding carries assessability, finding, threshold_proximity and validation, and also optimisation exactly when the check evaluates a fitted model, as its registry entry states. The value not_assessable has one meaning only, and suppression for privacy is reported as not_available with the reason privacy_suppressed.

A missing value in a data-profile document is null, and the schema places an availability status beside it, as `reported_number` does: its value is null exactly when its availability is not_available.

## Decimal strings and centring constants

A decimal string writes a number in canonical plain notation (`decimal_string` in defs.schema.json): no exponent, no '+', no leading zeros in the integer part, no trailing zeros in the fraction, no trailing '.', '0' for zero and '-' only before a non-zero value. Each number has exactly one decimal string. Its significant digits are its digits from the first non-zero digit to the last non-zero digit, so '100' has 1, '1230000' has 3, '0.0012' has 2 and '0' has none.

A centring constant, and any other constant stored at a declared precision, is a `decimal_constant`: a decimal string and the number of significant digits k, from 1 to 15, to which it was rounded. The constant is computed as a double x and rounded as follows.

1. If x is zero, the decimal string is '0'.
2. Otherwise, the exact binary value of x is rounded to k significant digits, a tie going to the even digit. Ties occur only when the exact value ends in 5 at the rounding position, as 0.125 does.
3. The rounded value is written as a decimal string.

The digits are those of the exact binary value rounded half to even, on every platform. Python obtains them with `format(x, f".{k - 1}e")`, which CPython rounds correctly on every platform with its own conversion routine. R's sprintf() passes the conversion to the C library, whose handling of ties differs between builds: Microsoft documents that the Windows C runtime rounded exactly representable ties up before Windows 10 version 2004. The R package therefore obtains the digits with an in-house routine that expands the double exactly from its significand and exponent in integer arithmetic and rounds half to even, on every platform, never with sprintf(). The digits are then laid out in plain notation. The corpora hold the ties of the table below, so that the Windows CI job tests them. Computations use the double nearest to the decimal string, converted with correct rounding.

| x | k | Exact value of the double begins | Decimal string |
|---|---|---|---|
| 3.215 | 3 | 3.21499999999999985789 | `3.21` |
| 0.125 | 2 | 0.125 | `0.12` |
| 0.375 | 2 | 0.375 | `0.38` |
| 2.5 | 1 | 2.5 | `2` |
| 34.56789 | 6 | 34.56788999999999845158 | `34.5679` |
| 52345.678 | 6 | 52345.67799999999988358 | `52345.7` |
| 1234567 | 3 | 1234567 | `1230000` |
| −0.000123456 | 2 | −0.00012345600000000000518 | `-0.00012` |
| 1/3 | 10 | 0.33333333333333331483 | `0.3333333333` |

The IR specification defines which constants are stored this way, the default number of significant digits and the sample each constant comes from. A prospective plan, written before the data are seen, stores the centring rule rather than a constant, and the constant is computed and recorded with its sample when the plan is executed.

## Declaration fields used across components

Four declaration fields are read by components other than the declaration validator. The declaration schema places them, and defs.schema.json defines their types.

- disclosure_unit names the declared unit whose distinct members the privacy rules count (02-decisions.md, Q5). Without it, the default is the one declared unit whose role is 'participant'. A disclosure_unit that is inferred, or that names a unit that counts as absent (registry.md, Terms), counts as absent, so that the default applies, and a unit whose role is inferred has no role for the default. With no such unit, or more than one, there is no disclosure unit, and every displayed cell, bin or band must contain at least k distinct levels of every grouping factor.
- event_level gives, for a binary outcome, the category value that counts as the event and is coded 1, compared with the data after NFC normalisation. Without it, an outcome coded other than 0 and 1 (numbers or logical values) is not modelled, and checks that need the coding report not_available with the reason declaration_missing. Reports state the modelled event, for example 'modelled event: P(acc == 'correct')'.
- trials names, for a binomial outcome with trials, the column holding the number of trials n of each row. The outcome column then holds the number of events k, with k and n integers and 0 ≤ k ≤ n. Rows with n = 0 leave the analysis sample and are reported.
- exposure gives, for a count outcome, the column holding the exposure of each row and its scale. With 'raw', the column holds the exposure, which must be positive, and the model uses its logarithm as an offset. With 'log', the column holds the logarithm and is used as the offset unchanged.

## Versions

The registry, the schemas, the canonicaliser, the declaration vocabulary and each kind of document carry versions of the form MAJOR.MINOR.PATCH (`semver` in defs.schema.json). A reader supports one or more MAJOR.MINOR lines and accepts every PATCH within them, as 'any 0.1.x version is accepted' in 02-decisions.md (Q4) requires. A document whose version lies outside the supported lines gives E1441, checked before any other validation.

A change that can alter canonical bytes, a hash or whether an input is accepted raises the MINOR version before 1.0 and the MAJOR version from 1.0 on. A change that alters none of them, such as a clearer description or a new error message template, raises the PATCH version. Adding a code to spec/errors.json changes no version, since codes are never renumbered or reused.

Versions of other software are recorded as the software reports them (`software_version`). A version range (`version_range`) is one or more comparisons such as `>=2.1-0, <3`. Versions are compared component by component as integers after splitting on '.' and '-', with missing trailing components counted as 0, so that 2.1-0 equals 2.1. A version that contains any other character, such as 0.15.0rc1, lies outside every range.

## Shared definitions

[spec/schemas/defs.schema.json](../../spec/schemas/defs.schema.json) holds the definitions that the other schemas share. Its identifier is `urn:mixedcheck:schema:defs`.

| Definition | Content |
|---|---|
| name | a declared name, such as a unit name or estimand ID: an ASCII letter and up to 63 ASCII letters, digits, '_' or '.' |
| column_name | a column name of 1 to 128 characters, without control characters or characters outside the BMP (E1207 in code) |
| category_value | a string or an integer |
| check_id | a registry entry's identifier, one to four lower-case segments separated by '.' |
| error_code | a code of spec/errors.json |
| json_pointer | a JSON Pointer (RFC 6901) |
| tier, language, count_class | the enumerations T0, T1 and T2, R and Python, and person and non_person |
| utc_timestamp, date | YYYY-MM-DDTHH:MM:SSZ and YYYY-MM-DD, with a year from 0001 to 9999 and the day checked against its month in code (E1406). February has 29 days when the year is divisible by 4 and not by 100, or by 400. Validators compute this in integer arithmetic, without date libraries, whose ranges of years differ. |
| semver, release, software_version, version_range | versions, as described under Versions |
| versions | the package, registry, schema and canonicaliser versions that a results document or a plan records |
| sha256_hash, key_id, keyed_commitment, commitment_key | hashes and commitments, as described under Hashes and Keyed commitments |
| decimal_string, decimal_constant | decimal strings and constants at a declared precision |
| profile_key, profile_string, hashable_value, data_value, data_number, reported_number | the profiles, as far as JSON Schema expresses them |
| availability, assessability, finding, optimisation, threshold_proximity, validation, status | the status fields and the set of them that a finding carries |
| issue | one reported problem, with its code, message and location |
| disclosure_unit, event_level, trials_column, exposure | the declaration fields used across components |

## Schemas

Every schema in spec/schemas/ follows these rules, so that the hand-written validators and the jsonschema oracle read it the same way.

- It uses JSON Schema draft 2020-12 and declares `"$schema": "https://json-schema.org/draft/2020-12/schema"`. Its file is spec/schemas/<kind>.schema.json, its identifier is `urn:mixedcheck:schema:<kind>` and it refers to a shared definition as `urn:mixedcheck:schema:defs#/$defs/<name>`.
- It uses only these keywords: $schema, $id, $ref, $defs, $comment, title, description, default, examples, deprecated, type, enum, const, properties, patternProperties, additionalProperties, propertyNames, required, dependentRequired, minProperties, maxProperties, items, prefixItems, minItems, maxItems, uniqueItems, contains, minLength, maxLength, pattern, minimum, maximum, exclusiveMinimum, exclusiveMaximum, allOf, anyOf, oneOf, not, if, then and else, together with the boolean schemas true and false. It does not use format, which draft 2020-12 treats as an annotation, and expresses each format with a pattern instead.
- Every object schema states which members are allowed, with additionalProperties set to false or to a schema, because unknown keys are errors.
- A regular expression, in the keyword pattern or as a key of patternProperties, uses only character classes, `\u` escapes, quantifiers, non-capturing and capturing groups, alternation and the anchors '^' and '$'. A pattern keyword starts with '^', ends with '$' and must match the whole string. A key of patternProperties starts with '^' and may leave out the final '$' to match a prefix, as in `^x-`. In the JSON file, backslashes are escaped, as in `"^[\\u0020-\\uFFFF]+$"`, so that no control character or U+0000 appears in a schema string.
- Patterns are matched over code points, and a final '$' matches only at the end of the string. ECMA-262 without the flag 'u' matches over UTF-16 code units instead, so validators do not follow it: under code points, a character outside the BMP does not match `[\\u00A0-\\uFFFF]`. Python validators call re.search with a final '$' replaced by '\Z', since Python's '$' also matches before a final line feed, and the jsonschema oracle is extended with a pattern keyword that does the same. R validators call grepl() with `perl = TRUE` on strings that are ASCII or marked UTF-8, after rewriting the pattern: each `\uXXXX` becomes `\x{XXXX}`, a final '$' becomes '\z' and '(*UTF)' is put before it, so that PCRE matches over code points even when every string is ASCII. R's default engine, TRE, reads neither `\u` escapes nor characters outside the BMP the same way on every platform, and PCRE without '(*UTF)' refuses `\x{FFFF}` when no input is marked UTF-8.
- A schema object with a pattern has a title, which E1406 names as the form required. E1418 names the title of the propertyNames schema or, when it has none, the title of the first schema that its $ref chain reaches, such as 'column name' for `{"$ref": "urn:mixedcheck:schema:defs#/$defs/column_name"}`.
- oneOf and anyOf are used only when the alternatives differ in type. A type list with if and then, as in `data_number`, is preferred.
- The root of a hashable document's schema includes `{"$ref": "urn:mixedcheck:schema:defs#/$defs/hashable_value"}` in an allOf, and that of a data document `data_value`. Readers and writers enforce the profiles, so validators do not check them again.
- A rule that JSON Schema cannot express is stated in a description, with the code that the validators report for it.
- The file is UTF-8 without a byte-order mark, with LF line endings, two-space indentation and a final line feed, and passes the strict reader in the hashable profile. It therefore contains no null literal.

The jsonschema oracle validates with Draft202012Validator, a referencing.Registry that holds every schema of the bundle under its identifier, and the pattern keyword above.

## YAML authoring

Declarations and registry sources may be written in YAML, which serves for authoring only and is converted to JSON (02-decisions.md, Q4). Both packages parse it with libyaml, which the yaml package bundles in R and PyYAML wraps in yaml.CBaseLoader. yaml 2.3.8 and PyYAML 6.0 both bundle libyaml 0.2.5. The Python reader uses a loader derived from yaml.CBaseLoader and never PyYAML's pure-Python parser, which refuses tabs that libyaml accepts, as after 'a: b' or in `[b,` followed by a tab. The reader reports E3001 when R lacks the yaml package, or when Python lacks PyYAML or has one built without libyaml (`yaml.__with_libyaml__` false), naming as the package 'yaml', 'PyYAML' or 'PyYAML built with libyaml'. It does so after step 1 below and before the pre-scan, so that bytes that step 1 refuses give the same code whether the package is installed or not.

The R package yaml cannot report anchors, aliases, explicit tags, merge keys or a second document: it resolves aliases and merge keys, drops tags and reads the first document only. Both packages therefore scan the text themselves before they parse it. A YAML text is read in five steps, and the first issue found is reported.

1. Bytes. The input is checked as for JSON (E1001 to E1003 and E1201).
2. Pre-scan. The decoded text is scanned as described below, and the first problem in the order of the text is reported.
3. Parsing. The text is parsed with libyaml. In R, yaml.load() is called with `as.named.list = FALSE`, with a handler for each implicit type of the package (str, int, int#hex, int#oct, int#base60, float, float#fix, float#exp, float#base60, float#nan, float#inf, float#neginf, bool#yes, bool#no, null, timestamp#ymd, timestamp#iso8601, timestamp#spaced, binary, bool#na, int#na, float#na and str#na) that returns the scalar's text, and with a handler 'seq' that returns a list, so that no scalar is converted and a sequence of one item stays a sequence. yaml 2.3.8 gives the type float#exp to exponents written with a '.' and a signed exponent, such as '1.0e+3' and '-1.5E-7', and the four types ending in '#na' to '.na', '.na.integer', '.na.real' and '.na.character'. Without a handler, it converts these scalars. It reads some plain scalars that start with '<<' as the merge key of YAML 1.1 and accepts no handler for them: '<<' itself and '<<' followed at once by a character outside ASCII, such as '<<é'. As a key, such a scalar merges its value into the mapping that holds it, and elsewhere it becomes a value of class '_yaml.merge_' that has lost the rest of the text. The pre-scan therefore refuses every plain scalar that starts with '<<'. Python processes the parser's events in order. Whichever comes first in the order of events is reported: a failure of the parser (E3002) or a mapping that holds two equal keys when it ends (E3007), which is when R's yaml checks its keys. Two keys are equal when they are scalars with the same text, or sequences or mappings with equal items in the same order. The reader attaches the parser's own message outside the rendered template, as errors.md (Issues and conditions) describes, since the line and column of a syntax error are known only to the parser.
4. Keys. The parsed value is walked depth first in the order of the text, each key before its value, and the first key that is a sequence or a mapping (E3006, at the JSON Pointer of the mapping that holds it) or that is empty (E1109, at the JSON Pointer of its member) is reported.
5. Conversion. Mappings become objects, sequences become arrays and scalars become strings, and each string is coerced to the type that the document's schema requires at its position (E3008, below). The converted value is then checked against the hashable profile as a writer checks a value in memory: in the order of its canonical serialisation, keys before values, each issue located by JSON Pointer, with the rules on numbers (E1102 to E1104) applied to the scalar's text as to a JSON token, the rules on strings and keys (E1108, E1203 and E1208) applied as to a written value and E1030 for a value nested more than 64 containers deep. At each position, E3008 comes before these rules, and the first issue in this order is reported.

The pre-scan reads the text by lines, which end at LF, CR LF, CR, U+0085, U+2028 or U+2029, as libyaml ends them. It skips comments, quoted scalars and block scalars and keeps track of the brackets '[' and '{' that are open. It reports:

- E1202 at the offset of U+0000 anywhere in the text, or of the backslash of the escape `\0`, `\x00`, `\u0000` or `\U00000000` in a double-quoted scalar, which R cannot hold
- E3005 at the offset of a line that starts with '%', which is a directive
- E3003 at the offset of a document marker '---' after the first content of the text and of the first content after a document marker '...'
- E3004 at the offset of '&' or '*' at the start of a node, which is an anchor or an alias
- E3005 at the offset of '!' at the start of a node, which is a tag
- E3009 at the offset of a node that starts with '<<', a plain scalar that R's yaml package can read as a merge key, whatever follows the '<<'
- E3010 when the text has no content, once the whole text has been scanned

Offsets count bytes from the start of the text, as for JSON. The pre-scan finds every anchor, alias, tag, directive, merge key and second document that libyaml would read. If libyaml nonetheless reports one of them in Python, or R's yaml package returns a merge key, the reader reports E9001, because the pre-scan has failed.

These terms are defined on the text alone:

- A document marker is '---' or '...' at the start of a line, followed by a space, a tab, a line break or the end of the text. Content is any character other than a space, a tab or a line break, outside comments and document markers.
- A comment starts at a '#' that begins a line or follows a space or a tab, outside a quoted or block scalar, and runs to the end of the line.
- A node starts at the first character of a line that is not a space or a tab, after a '-', '?' or ':' that is followed by a space, a tab or a line break, after a '?' or ':' outside a scalar while a bracket is open, which libyaml reads as an indicator whatever follows it, after a ':' that follows a quoted scalar with only spaces or tabs between them, after '[', '{' or ',' while a bracket is open and after the document marker '---'. Spaces and tabs before it are skipped.
- At the start of a node, "'" opens a single-quoted scalar, which ends at the next "'" that is not doubled, and '"' opens a double-quoted scalar, which ends at the next '"' that does not follow an escaping backslash. Either may span lines. While no bracket is open, '|' or '>' at the start of a node opens a block scalar, which holds the rest of its line and every following line that is empty, holds only spaces and tabs or starts with more spaces than the line of the '|' or '>'. '[' and '{' open a bracket and ']' and '}' close one.
- Any other character at the start of a node begins a plain scalar, which ends at a ':' followed by a space, a tab or a line break, at a comment, at the end of the line and, while a bracket is open, at ',', '[', ']', '{' or '}'.

The pre-scan can refuse a text that YAML would read, such as a plain scalar that starts with '<<' or one continued on a line that starts with '&'. Quoting the scalar avoids it.

Each string from step 5 is coerced as follows:

- boolean: exactly 'true' or 'false'
- integer: text matching `^-?(0|[1-9][0-9]*)$`
- number: text matching the number grammar of RFC 8259
- string: any text

Where the schema allows several types, the string becomes the first of boolean, integer, number and string that the schema allows and whose form it matches. Where the schema allows any value, it stays a string. A string that matches no allowed form gives E3008, naming the type required as 'a boolean', 'an integer' or 'a number'. A plain empty scalar is the empty string, and `~`, `null`, `yes` and `NO` are strings like any other. Quoting a scalar does not change its coercion, so `'1'` and `1` both become the integer 1 where the schema requires an integer. The converted value is then validated like a JSON document, and the hash of a document authored in YAML is the hash of its JSON form.

## Comparison across languages

Both packages must give the same output for the same input (02-decisions.md, Q2 and Q5). The package tests and the parity harness ([parity/README.md](../../parity/README.md)) compare outputs as follows.

- Error codes, issues with their messages and locations, canonical bytes and hashes match exactly, and so do IRs, plans and every member of a results document other than those below.
- The members of a results document that record what wrote it, `created`, `software` and the package version in `versions`, are not compared.
- The values of statistics of kind real or reals match when |x − y| ≤ 1e-12 + 1e-9 × max(|x|, |y|) for each pair x and y, and 'NaN', 'Infinity' and '-Infinity' match only themselves. Such statistics come from sums, determinants, eigenvalues and singular values that the two languages compute with different orders of summation and different linear-algebra libraries, so that their last digits can differ (02-decisions.md, Q5). Five exceptions follow from how the values are computed. gvif and gvif_per_df of design.collinearity match when |x − y| ≤ 1e-12 + max(1e-9, 1e-13 × M) × M with M = max(|x|, |y|), since the relative error of a variance inflation factor grows with its value whatever the method, by about 1e-15 times the value in a review of registry 0.1.0. condition_number of design.scale_disparity matches when |x − y| ≤ 1e-12 + max(1e-9, 1e-14 × M) × M, since the relative error of a smallest singular value is of the order of the unit roundoff times the condition number for any backward-stable singular value decomposition of the matrix itself, which its definition requires, and different orders of the same rows and columns gave relative differences of up to 1.6e-17 times the value in a review of M2b-2. smallest_eigenvalue of identifiability.gram_rank matches when |x − y| ≤ 1e-12 + 1e-9 × max(1, |x|, |y|), since C has a diagonal of 1, so that the rounding errors of its eigenvalues, which grow with the rows of the design sample through the sums of W, are relative to its norm, at least 1, rather than to the eigenvalue, and an eigenvalue near 4e-5 from 1e5 rows lay about 6e-10 from its exact value in both packages, which differed by 3.7e-12, in a review of M2b-3. The coefficient bounds of outcome.separation match within the parameter bound_tolerance of its registry entry, which the comparison of their objectives with the upper bounds of their multipliers ensures for findings that are clear in both languages (outcome.separation.yaml, optimality_tolerance), and its optimum and margin when |x − y| ≤ bound_tolerance × max(1, |x|, |y|), since they come from different solvers and the optimum grows with the number of rows (02-decisions.md, Q2).
- The messages of two findings match when both texts render the template of the same message, or both its fallback, every argument other than a real statistic renders identically in both, the two values of every real statistic that they render match by the rule above, and each text renders the values of its own finding as registry.md (Messages) prescribes. The renderings of a real are not compared with each other, since values that match can render differently: as the neighbouring roundings on either side of a rounding boundary, by several units of the last place where the tolerance exceeds one unit of it, as for gvif and gvif_per_df from about 3.2e5 and for sd_ratio with 0 digits from about 1e9, in fixed and in scientific notation on either side of 1e15, and as under 0.1 and 0.1 on either side of 0.05 with 1 digit. The parity harness and the corpus tests of both packages compare messages by this rule.
- A finding that is near_threshold in either language may differ in its finding status, its message and its threshold_proximity, because its decision compares a real statistic with a threshold within the statistic's tolerance (registry.md, Thresholds). A finding of outcome.separation that is near_threshold in either language may also differ in its verdict, optimum, margin, bounds and columns_involved, since a solution that meets the constraints only within the feasibility tolerance, which makes it near_threshold, can reach an optimum that the other solver does not reach, as on separated data whose margin on the scaled columns lies below the solvers' tolerances (outcome.separation.yaml, verdict), and since a program of bounds that one solver cannot solve, whose objective lies further below the upper bound of its multipliers than optimality_tolerance or whose bound the floor of the face moves fast, each of which makes the finding near_threshold, leaves bounds that are absent in one language or further apart than bound_tolerance (outcome.separation.yaml, bounds and optimality_tolerance). A finding of identifiability.gram_rank that is near_threshold in either language may also differ in its rank, verdict, vanishing_parameters, confounded_parameters and smallest_eigenvalue, since a value within its bound of rank_tolerance, which makes it near_threshold, can fall on either side of the tolerance with another orthonormal basis of X or another order of summation, as an eigenvalue of 0 does for one level of N − 1 rows and one of one row beside a slope at 7e5 rows (identifiability.gram_rank.yaml, rank_tolerance).
- Counts, ratios, booleans, categories, names and labels match exactly. A ratio is the double nearest to the quotient of two exact counts, which both languages compute alike.
- A count or name that the sequential rule decides, such as the columns it drops from X, design_df of assignment.design_df and budget of identifiability.df_budget, can differ between the languages for a column whose residual lies within the rounding error of its computation of the rule's tolerance, since the packages compute residuals with different orders of operations and linear-algebra libraries (ir.md, Sequential rule for aliased columns). Such an input lies outside the parity of the packages. Every residual that the rule compares in the corpora lies at least a factor of 10 from the tolerance, and a difference in such a count is a mismatch like any other.

## Error reporting

Every failure of a reader, writer or validator maps to exactly one code of spec/errors.json, whose message template is rendered as [errors.md](errors.md) describes. A reader reports one issue, the first by the stages above. A validator reports every structural problem it finds, then, if there are none, every problem found by the rules enforced in code, sorted by location and code and capped at 100. errors.md also sets out how JSON Schema keywords map to codes and which problems are reported together, so that both packages report the same list.

## References

Ben-Kiki, O., Evans, C., & Ingerson, B. (2005). YAML Ain't Markup Language (YAML) version 1.1. https://yaml.org/spec/1.1/

Bray, T. (Ed.). (2015). The I-JSON message format (RFC 7493). Internet Engineering Task Force. https://doi.org/10.17487/RFC7493

Bray, T. (Ed.). (2017). The JavaScript Object Notation (JSON) data interchange format (RFC 8259). Internet Engineering Task Force. https://doi.org/10.17487/RFC8259

Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation (JSON) Pointer (RFC 6901). Internet Engineering Task Force. https://doi.org/10.17487/RFC6901

Ecma International. (2024). ECMA-262: ECMAScript 2024 language specification (15th ed.). https://ecma-international.org/publications-and-standards/standards/ecma-262/

Krawczyk, H., Bellare, M., & Canetti, R. (1997). HMAC: Keyed-hashing for message authentication (RFC 2104). Internet Engineering Task Force. https://doi.org/10.17487/RFC2104

National Institute of Standards and Technology. (2015). Secure hash standard (SHS) (FIPS PUB 180-4). https://doi.org/10.6028/NIST.FIPS.180-4

Nystrom, M. (2005). Identifiers and test vectors for HMAC-SHA-224, HMAC-SHA-256, HMAC-SHA-384, and HMAC-SHA-512 (RFC 4231). Internet Engineering Task Force. https://doi.org/10.17487/RFC4231

Rundgren, A., Jordan, B., & Erdtman, S. (2020). JSON Canonicalization Scheme (JCS) (RFC 8785). Internet Engineering Task Force. https://doi.org/10.17487/RFC8785

The Unicode Consortium. (2021). The Unicode Standard, version 14.0.0. https://www.unicode.org/versions/Unicode14.0.0/

Whistler, K. (Ed.). (2021). Unicode normalization forms (Unicode Standard Annex #15, revision 51, for Unicode 14.0.0). The Unicode Consortium. https://www.unicode.org/reports/tr15/tr15-51.html

Wright, A., Andrews, H., & Hutton, B. (2022). JSON Schema Validation: A vocabulary for structural validation of JSON (draft 2020-12). https://json-schema.org/draft/2020-12/json-schema-validation

Wright, A., Andrews, H., Hutton, B., & Dennis, G. (2022). JSON Schema: A media type for describing JSON documents (draft 2020-12). https://json-schema.org/draft/2020-12/json-schema-core

Yergeau, F. (2003). UTF-8, a transformation format of ISO 10646 (RFC 3629). Internet Engineering Task Force. https://doi.org/10.17487/RFC3629
