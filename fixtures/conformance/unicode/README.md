# Unicode corpus

These cases test the Unicode policy of both packages ([conventions.md](../../../docs/spec/conventions.md), Text and Unicode): the validation of UTF-8, which strings are normalisable, NFC, the comparison and order of identifiers and labels, the NFC rule of the hashable profile and the cases whose output a locale or an encoding mark could change.

| File | Cases | Covers |
|---|---|---|
| utf8.json | 38 | reader cases: ill-formed UTF-8 by Table 3-7 of the Unicode Standard (overlong forms, encoded surrogates, code points above U+10FFFF, bytes that never occur, truncated sequences and stray continuation bytes) with the offset of the first ill-formed sequence and its precedence over syntax errors, together with well-formed sequences at the limits, some of them unassigned |
| normalisation.json | 47 | text cases: whether a string is normalisable and the form in which it is compared, for NFC and NFD pairs, singletons, canonical reordering, Hangul, composition exclusions, compatibility characters that NFC keeps, U+1E2AE of Unicode 14.0, U+1E4EC of Unicode 15.0, unassigned code points and noncharacters |
| hashable.json | 77 | reader cases: the strings of normalisation.json as strings and as keys in each mode, which only the hashable profile refuses when they are not in NFC (E1203) or not normalisable (E1208) |
| order.json | 59 | comparison cases: pairs of strings in both orders and lists to sort |
| c_locale.json | 22 | reader cases whose output a locale could change, with non-ASCII strings, keys and messages, the order of keys and numbers, together with writer cases of R strings with encoding marks and of Python strs with surrogates |

## Format

utf8.json and hashable.json hold reader cases, and c_locale.json reader and writer cases, in the format of [json/README.md](../json/README.md).

A case of normalisation.json has a `string` and `expected` with two members. `normalisable` tells whether every code point of the string is listed in [spec/unicode/assigned-14.0.json](../../../spec/unicode/assigned-14.0.json). `form` is the form in which identifiers and labels are compared: the NFC form of the string when it is normalisable, and the string itself otherwise. A test checks both with the package's own functions.

A case of order.json has either `first` and `second`, with `expected` holding `order`, or `strings`, with `expected` holding `sorted`. `order` is -1 when the first string comes first, 0 when the two are equal as identifiers and 1 when the second comes first, comparing the code points of their comparison forms one by one with a prefix first. `sorted` is the list in that order, and no two of its strings are equal.

The R package runs its tests under the session's locale and, in the CI job that sets LC_ALL=C, in a C locale. c_locale.json gathers the cases that a locale is most likely to change, and every case of the corpora must give the same result in both. In R, the inputs of the corpora are built from their bytes and marked UTF-8, never from string literals, which a C locale would leave unmarked.

## Provenance

The cases were written for this project from conventions.md and are MIT-licensed. Some strings are examples of Unicode Standard Annex #15, such as U+1E0B U+0323 and U+1E9B U+0323. Others come from conventions.md, such as 'x' followed by U+1E4EC and U+0316. [tools/make_canonicaliser_corpora.py](../tools/make_canonicaliser_corpora.py) writes the files and checks every expected output against independent oracles. NFC comes from unicodedata of Python 3.11, which implements Unicode 14.0.0. Which code points are assigned comes from spec/unicode/assigned-14.0.json, confirmed with the general categories of the same unicodedata. The offsets of ill-formed UTF-8 agree with Python's UnicodeDecodeError.start. The hash of the canonical bytes of ["école"] and the SHA-256 of 'école' in hash/sha256.json match the values that docs/design/evidence/decisions/G-critic/out/c_locale_encoding.txt records.
