# JSON corpus

These cases test the strict JSON reader and the RFC 8785 serialiser of both packages ([conventions.md](../../../docs/spec/conventions.md), Strict reader, Profiles and Serialisation). A reader case gives input bytes and, for the plain mode and each of the data and hashable profiles, either the canonical bytes of the value read with their hash or the one issue that the reader reports. A writer case gives a value in memory and, for each mode, either its canonical bytes with their hash or the first issue that the writer reports.

| File | Cases | Covers |
|---|---|---|
| rfc8785.json | 28 | the examples of RFC 8785: the canonical form of section 3.2.2, whose bytes section 3.2.4 lists, the sorting example of section 3.2.3 and the 26 numbers of appendix B |
| syntax.json | 138 | stages 1 to 3 of the reader: missing and unreadable files, byte-order marks, the end of the input, unexpected characters, among them words that start with 'e' or 'E', trailing content, control characters and escapes in strings, NaN and the infinities, invalid numbers and nesting deeper than 64 |
| values.json | 57 | stage 4 of the reader: duplicate keys, U+0000, empty keys, keys outside the BMP, unpaired surrogates, unassigned code points and NFC and null in each mode, with the order in which issues take precedence |
| canonical.json | 42 | inputs that the reader accepts, with their canonical bytes: white space, scalars, empty containers, the order of members, escapes, numbers, the worked example of conventions.md, the edge files of the evidence for the decisions and an object whose keys together take more than 10,000 bytes |
| writer.json | 28 | values in memory: the order of the writer's checks, pointers, NaN and the infinities, negative zero, the number rules of the hashable profile, Python ints and nesting |

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile. The files are ASCII, with every other character written as an escape, so that no editor or file system can normalise them, and their strings need not be in NFC. Each case has an `id`, unique across the corpora, and a `description`. The corpora in numbers/ and unicode/ use the same two kinds of case, which their members tell apart.

A reader case has one of these members, which give the input:

- `input`: a string whose UTF-8 encoding is the input.
- `input_hex`: the bytes of the input in lower-case hexadecimal, for input that is not valid UTF-8 or that holds U+0000.
- `file`: 'missing' to read a path that does not exist, or 'directory' to read a path to a directory.

A writer case has one of these members, which give the value:

- `json`: JSON text that the reader accepts in the plain mode. The value it reads is the value to write: in R a named or unnamed list, a character string marked UTF-8, a double, a logical or NULL, and in Python a dict, a list, a str, an int, a float, a bool or None.
- `double`: the 64 bits of an IEEE 754 double as 16 hexadecimal digits, most significant first, as `readBin(..., "double", size = 8, endian = "big")` in R and `struct.unpack(">d", ...)` in Python read them. The value is that double.

A writer case may also have `substitutions`, applied in order, each with a `pointer`, a JSON Pointer into the value that is '' for the whole value, and one of these members:

- `double`: replaces the value at the pointer with the double of these bits, such as NaN or an infinity.
- `wrap`: an integer n. Replaces the value at the pointer with itself inside n nested arrays of one element.
- `r_string`: an object with `hex` and `encoding`. Replaces the value at the pointer with an R character string of these bytes, as `rawToChar()` gives it, and the encoding mark 'UTF-8', 'latin1', 'unknown' or 'bytes', set with `Encoding<-`.
- `python_string`: a list of code points. Replaces the value at the pointer with a Python str of these code points, which may include surrogates.
- `python_int`: decimal digits. Replaces the value at the pointer with a Python int.

A case with `languages` runs only in the languages it lists, because only they can hold its value. The parity harness compares the cases that both languages run.

`expected` has a member for each mode in which the case runs, `plain`, `data` and `hashable`. Writer cases with a non-finite double or a Python int have no `plain` member, since conventions.md defines no result for them in the plain mode. Each member holds one of these:

- `canonical` and `sha256`: the canonical bytes, as the string whose UTF-8 encoding they are, and their hash as documents write it. For a reader case, they are the bytes of the value read, written in the same mode.
- `issue`: the one issue reported, with its `code`, its rendered `message` and its `offset` or `pointer`, or neither for a code that has no location (`issue` in [defs.schema.json](../../../spec/schemas/defs.schema.json)). A reader locates issues by byte offset and a writer by JSON Pointer, in which a key is written as it is, with '~' as '~0' and '/' as '~1'. The message displays the pointer escaped, as [errors.md](../../../docs/spec/errors.md) describes.

A test compares the canonical bytes and the hash, or the code, the message and the location, exactly.

## Provenance

The cases were written for this project from conventions.md and errors.md and are MIT-licensed. They reproduce, with attribution, the examples of RFC 8785 (Rundgren, Jordan and Erdtman, 2020), typed from the RFC: short test values published so that implementations can be checked against one another, which the test suite of the rfc8785 Python package reproduces in the same way. The project treats them as facts and claims no rights in them ([test-vectors.md](../../../docs/design/evidence/reading/licences/test-vectors.md)). The values of the RFC's appendix B match the list in the test suite of the rfc8785 Python package 0.1.4. The 12 edge files of docs/design/evidence/decisions/E/schema/edge and E-verify/edge are earlier MIT-licensed work of this project and are used as stored.

[tools/make_canonicaliser_corpora.py](../tools/make_canonicaliser_corpora.py) writes the files. Each case states its expected codes by hand, and the script checks the rest of each expected output against independent oracles, as [tools/README.md](../tools/README.md) describes: the rfc8785 package for every canonical form and Node.js 22 for every number of appendix B, Python's json module and float() for the values read, unicodedata of Python 3.11 for NFC and jsonschema 4.26.0 for the form of every issue. Offsets, pointers and message arguments come from a scratch reading of the rules that is part of neither package and agree with the offsets and pointers stated by hand. The canonical bytes of the RFC 8785 example and of the worked example of conventions.md, with its hash, equal the published ones.
