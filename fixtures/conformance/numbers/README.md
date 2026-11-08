# Number corpus

These cases test how both packages write doubles in ECMAScript's form, read number tokens with correct rounding, apply the number rules of the hashable profile and round decimal constants ([conventions.md](../../../docs/spec/conventions.md), Numbers, Profiles, Serialisation and Decimal strings and centring constants).

| File | Cases | Covers |
|---|---|---|
| format.json | 125 | writer cases with one double: the layouts of Number::toString on both sides of n = 21, n = 0 and n = -6, shortest round trips, negative zero, subnormal doubles, integers near 2^53 and beyond, the 46 powers of two for which formatting with increasing precision is not shortest, the largest doubles and NaN and the infinities, with the issues E1102, E1103, E1104 and E1107 of the hashable profile |
| read.json | 142 | reader cases with one number token: zero in every form, exponents with leading zeros or of 401 digits, the integer range and the limits of 15 significant digits and 1e-307 in the hashable profile, overflow and underflow at their exact boundaries, ties rounded to even, exact midpoints between neighbouring doubles, a token of 805 characters and 45 decimals that R 4.3.3's as.numeric() converts to a neighbour of the nearest double |
| decimal_constants.json | 41 | doubles rounded to k significant digits, half to even on their exact binary values: the table of conventions.md, ties, carries into a new digit, zero, negative values and values whose plain notation needs many digits |

## Format

format.json holds writer cases and read.json reader cases, in the format of [json/README.md](../json/README.md). A reader case of read.json that reads a non-zero number also has `bits` in each successful result, the double read as 16 hexadecimal digits in the form of `double`, so that a test can compare the double itself. Zero has no `bits`, because conventions.md leaves the sign of a zero read from a token open, and both zeros are written as 0.

A case of decimal_constants.json gives the bits of a double as `double` and a number k of significant digits from 1 to 15 as `digits`. `expected` holds `decimal`, the decimal string of the constant (`decimal_string` in defs.schema.json). A test computes the constant from the double and compares the string exactly.

The R package's tests should also run the cases of this directory with `options(OutDec = ",")`, which must change nothing, since canonical numbers are never formatted with format() or formatC().

## Provenance

The cases were written for this project from conventions.md and are MIT-licensed. [tools/make_canonicaliser_corpora.py](../tools/make_canonicaliser_corpora.py) writes the files and checks every expected output against independent oracles. The ECMAScript strings come from the rfc8785 package 0.1.4, which lays out the digits of CPython's repr(), and Node.js 22 gives the same string for every double of format.json and json/rfc8785.json. The doubles read come from CPython's float(), which rounds correctly, and exact rational arithmetic confirms that each is the nearest double, with ties to even. The decimal constants come from the decimal module, rounding the exact value of the double half to even, and format() with the 'e' presentation gives the same digits. The values of the table in conventions.md are reproduced exactly.

The first three decimals of read.json that as.numeric() misconverts are the examples of conventions.md. The other 42 were found by comparing R 4.3.3's as.numeric() on Linux with Python's float() on about 450,000 generated strings, decimals of at most 15 significant digits and the shortest and 17-digit forms of random doubles. Their expected values come from float() and exact fractions, not from R. The 46 powers of two were found by comparing the loop over '%.{p}e' that conventions.md describes with repr().
