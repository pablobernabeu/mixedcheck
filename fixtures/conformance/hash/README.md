# Hash corpus

These cases test SHA-256 hashing in both packages ([conventions.md](../../../docs/spec/conventions.md), Hashes): the hashes of bytes, of files and of sections of documents, each written as 'sha256:' followed by 64 lower-case hexadecimal digits.

| File | Cases | Covers |
|---|---|---|
| sha256.json | 20 | byte strings: the SHA-256 examples of NIST, lengths at the boundaries of SHA-256 padding, every byte value, bytes that are not UTF-8, a byte-order mark, LF and CRLF line endings, 'école' in UTF-8 and in Latin-1 and the 117 canonical bytes of the worked example of conventions.md |
| sections.json | 10 | sections of one document in the hashable profile, located by JSON Pointer, with their canonical bytes and hashes |

## Format

Each file is a JSON object with a `description` and a list of `cases`, as in [json/README.md](../json/README.md). A case of sha256.json gives its bytes as `input`, a string whose UTF-8 encoding they are, or as `input_hex`. With `repeat`, the bytes are repeated that many times. `expected` holds `sha256`. A test hashes the bytes in memory, with `cli::hash_raw_sha256()` in R and hashlib in Python, and, written to a temporary file, as a file, with `cli::hash_file_sha256()` in R.

A case of sections.json has `input`, JSON text that the reader accepts in the hashable profile, and a `pointer`. `expected` holds the `canonical` bytes of the section at the pointer and their `sha256`, as a reader case does. The same document serves every case.

## Provenance

The cases were written for this project from conventions.md and are MIT-licensed. They reproduce, with attribution, the messages of the NIST examples, from FIPS 180-2 (appendix B) and the examples of SHA-256 that NIST publishes, works of the United States government that are not subject to copyright there and that CPython's test suite reproduces in the same way. The project treats them as facts and claims no rights in them ([test-vectors.md](../../../docs/design/evidence/reading/licences/test-vectors.md)). [tools/make_canonicaliser_corpora.py](../tools/make_canonicaliser_corpora.py) writes the files. Every digest comes from Python's hashlib, which agrees with the published digests of the NIST examples and with the hash of the worked example in conventions.md, and the canonical bytes of the sections come from the rfc8785 package.
