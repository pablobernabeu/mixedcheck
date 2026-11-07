"""Reference Python reader for design declarations (prototype).

Strict reading rules shared with the R reader (decl_read.R):
  * bytes must be UTF-8 without BOM; strings are checked for NFC form
  * duplicate object keys are an error (json.loads would keep the last one)
  * null, NaN and Infinity are errors
  * the document is validated against design.schema.json (JSON Schema 2020-12)
  * the hash is SHA-256 of the RFC 8785 (JCS) canonical form

Usage: python -I decl_read.py <schema.json> <file.json> [<file.json> ...]
Prints one tab-separated line per file: file, status, sha256, message.
"""
import hashlib
import json
import sys
import unicodedata

import jsonschema
import rfc8785


class DeclError(Exception):
    pass


def _pairs(pairs):
    keys = [k for k, _ in pairs]
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup:
        raise DeclError("duplicate key(s): " + ", ".join(dup))
    return dict(pairs)


def _no_constants(name):
    raise DeclError("non-finite number: " + name)


def _walk(x, path="$"):
    if x is None:
        raise DeclError(f"null at {path}")
    if isinstance(x, str):
        if unicodedata.normalize("NFC", x) != x:
            raise DeclError(f"string not in NFC at {path}")
    elif isinstance(x, dict):
        for k, v in x.items():
            if unicodedata.normalize("NFC", k) != k:
                raise DeclError(f"key not in NFC at {path}")
            _walk(v, f"{path}.{k}")
    elif isinstance(x, list):
        for i, v in enumerate(x):
            _walk(v, f"{path}[{i}]")


def read_declaration(path, schema):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise DeclError("byte-order mark")
    text = raw.decode("utf-8")  # strict
    doc = json.loads(text, object_pairs_hook=_pairs, parse_constant=_no_constants)
    _walk(doc)
    errors = sorted(jsonschema.Draft202012Validator(schema).iter_errors(doc),
                    key=lambda e: list(e.absolute_path))
    if errors:
        e = errors[0]
        loc = "/".join(str(p) for p in e.absolute_path) or "(root)"
        raise DeclError(f"schema: {loc}: {e.message[:160]}")
    canon = rfc8785.dumps(doc)
    return doc, canon, hashlib.sha256(canon).hexdigest()


def main():
    schema = json.load(open(sys.argv[1], encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    for f in sys.argv[2:]:
        try:
            _, canon, h = read_declaration(f, schema)
            print(f"{f.split('/')[-1]}\tok\t{h}\t{len(canon)} bytes")
        except (DeclError, UnicodeDecodeError, json.JSONDecodeError) as e:
            print(f"{f.split('/')[-1]}\terror\t-\t{e}")


if __name__ == "__main__":
    main()
