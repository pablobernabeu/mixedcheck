# Corpus tools

The scripts here write conformance corpora, so that they can be regenerated after a change to the specification. They run from the repository only and are not vendored. After running one, vendor the corpora with `python3 spec/tools/vendor.py sync`.

## make_canonicaliser_corpora.py

The script writes the corpora of the canonicaliser in [json/](../json/README.md), [numbers/](../numbers/README.md), [unicode/](../unicode/README.md), [hash/](../hash/README.md) and [hmac/](../hmac/README.md). It needs Python 3.11, whose unicodedata implements Unicode 14.0.0, the version of spec/unicode/assigned-14.0.json, and the oracles pinned in `requirements.txt`. Node.js, where it is on the PATH, confirms every number serialisation. From the repository root:

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r fixtures/conformance/tools/requirements.txt
.venv/bin/python fixtures/conformance/tools/make_canonicaliser_corpora.py           # write the files
.venv/bin/python fixtures/conformance/tools/make_canonicaliser_corpora.py --check   # exit with status 1 if a file differs
```

spec/tools/test_canonicaliser_corpora.py runs the check when it finds Python 3.11 and the oracles.

Each case in the script states its expected error codes by hand, from [conventions.md](../../../docs/spec/conventions.md). The script derives the rest of each expected output and checks it against independent oracles: canonical bytes from the rfc8785 package, number strings from rfc8785 and Node.js, doubles from CPython's float() checked with exact fractions, SHA-256 from hashlib, HMAC-SHA-256 from hmac, NFC from unicodedata, decimal constants from the decimal module and format(), and the form of every issue, hash, commitment and decimal string from jsonschema with the schemas of spec/schemas/. Offsets, pointers and message arguments come from a scratch reading of the rules in conventions.md, written for this script and part of neither package. Where a case also states an offset or a pointer by hand, the script stops unless the two agree. Messages are rendered from spec/errors.json as [errors.md](../../../docs/spec/errors.md) describes. The script stops at the first expected output that an oracle contradicts, and it checks the published values it reproduces: the vectors of RFC 8785 and RFC 4231, the SHA-256 examples of NIST and the worked examples of conventions.md and documents.md.

The cases of numbers/read.json that R's as.numeric() misconverts were found once by comparing R 4.3.3's as.numeric() with Python's float() on about 450,000 generated decimal strings, and the script lists them. Their expected values come from float() and exact fractions, not from R.

## make_table_corpus.py

The script writes the table corpus in [tables/](../tables/README.md): one JSON file for each group of cases and a directory of the same name with the CSV inputs, byte for byte. It reads the edgezoo inputs from docs/design/evidence/decisions/E-verify/edgezoo as stored and needs only the standard library of Python 3.11 or later and spec/tools/compile_registry.py. From the repository root:

```bash
python3 fixtures/conformance/tools/make_table_corpus.py           # write the files
python3 fixtures/conformance/tools/make_table_corpus.py --check   # exit with status 1 if a file differs
```

spec/tools/test_table_corpus.py runs the same comparison.

Each case in the script states its expected code by hand, from [tables.md](../../../docs/spec/tables.md), and some also state an offset, values or the rows of the samples. The script derives the rest of each expected output with a scratch reading of tables.md, written for this script and part of neither package, and stops unless the derivation agrees with what a case states. It checks the derivation against independent oracles: Python's csv module in strict mode for the records and fields of every table read, exact fractions for the rounding of every number converted, the datetime module for every date and time checked and unicodedata for NFC. Its declarations must pass the structural validator of compile_registry.py and the rules of the hashable profile, and messages are rendered from spec/errors.json as [errors.md](../../../docs/spec/errors.md) describes.
