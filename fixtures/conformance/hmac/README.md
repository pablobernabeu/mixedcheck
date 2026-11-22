# HMAC corpus

These cases test HMAC-SHA-256 and the keyed commitments of both packages ([conventions.md](../../../docs/spec/conventions.md), Keyed commitments): the construction of RFC 2104 with keys of any length, the key identifier, the refusal of supplied keys of the wrong form and the commitment object.

| File | Cases | Covers |
|---|---|---|
| rfc4231.json | 12 | test cases 1 to 7 of RFC 4231, keys of 64 and 65 bytes on both sides of the block size, an empty key, an empty message and every byte value as a message |
| commitments.json | 21 | the identifiers of four keys, 12 supplied keys that E1311 refuses and keyed commitments to five messages, among them the examples of conventions.md and documents.md |

## Format

Each file is a JSON object with a `description` and a list of `cases`, as in [json/README.md](../json/README.md). A message is given as `message`, a string whose UTF-8 encoding it is, or as `message_hex`.

A case of rfc4231.json has `key_hex`, the key in hexadecimal, of any length, and a message. `expected` holds `digest`, the HMAC-SHA-256 in lower-case hexadecimal. When the case has `truncate`, the digest holds only that many leading bytes, as RFC 4231 gives for test case 5, and a test compares only those.

A case of commitments.json has `key`, a string supplied as the user would supply a commitment key, and is one of two kinds:

- Without a message, `expected` holds either `key_id`, the identifier of the key, or `issue`, the issue E1311 that refuses it.
- With a message and `covers`, `expected` holds `commitment`, the `keyed_commitment` object (defs.schema.json) that commits to the message under the key.

## Provenance

The cases were written for this project from conventions.md and documents.md and are MIT-licensed. They reproduce, with attribution, the keys and messages of RFC 4231 (Nystrom, 2005), short test values published so that implementations can be checked against one another, which the test suites of CPython and Go reproduce in the same way. The project treats them as facts and claims no rights in them ([test-vectors.md](../../../docs/design/evidence/reading/licences/test-vectors.md)). [tools/make_canonicaliser_corpora.py](../tools/make_canonicaliser_corpora.py) writes the files. Every digest comes from Python's hmac and hashlib, which agree with the digests that RFC 4231 publishes, with the key identifier and commitment of the example in conventions.md and with the outcome column commitment of documents.md. jsonschema 4.26.0 confirms the form of every key identifier and commitment.
