"""Tests of the JSON examples of docs/spec/documents.md, run from the repository
root with

    python3 -m unittest discover -s spec/tools -v

documents.md shows four examples: a shareable results document, its internal
sidecar, a finding that is not available and a file of bring-your-own
estimates. These tests check that each is valid under its schema in
spec/schemas/, by the structural validator of compile_registry.py and, where it
is installed, by the jsonschema package as an oracle, and that the results
document has the length and the results file hash that documents.md states for
its canonical bytes and that the sidecar records. They use the standard
library, compile_registry.py and, where they are installed, the jsonschema and
rfc8785 packages.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

try:
    import jsonschema
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012
except ImportError:  # pragma: no cover
    HAVE_ORACLE = False
else:
    HAVE_ORACLE = True

try:
    import rfc8785
except ImportError:  # pragma: no cover
    HAVE_RFC8785 = False
else:
    HAVE_RFC8785 = True

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "spec" / "schemas"
DOCUMENTS = ROOT / "docs" / "spec" / "documents.md"
JSON_BLOCK = re.compile(r"^```json\n(.*?)^```$", re.MULTILINE | re.DOTALL)
# The schema of each JSON example of documents.md, in the order of the text.
EXAMPLE_SCHEMAS = [
    "urn:mixedcheck:schema:results",
    "urn:mixedcheck:schema:results#/$defs/sidecar",
    "urn:mixedcheck:schema:results#/$defs/finding",
    "urn:mixedcheck:schema:estimates",
]
# What documents.md states about the canonical bytes of the results document.
STATED = re.compile(
    r"The canonical bytes of the document are ([0-9,]+) bytes long, and its results file "
    r"hash is `(sha256:[0-9a-f]{64})`"
)


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [key for key, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate key")
    return dict(pairs)


class DocumentExamplesTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = DOCUMENTS.read_text(encoding="utf-8")
        cls.examples = [
            json.loads(block, object_pairs_hook=_reject_duplicates)
            for block in JSON_BLOCK.findall(cls.text)
        ]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.validator = cr.Validator(cls.bundle, cr.Catalogue(ROOT / "spec" / "errors.json"))

    def test_every_example_has_a_schema(self) -> None:
        self.assertEqual(len(self.examples), len(EXAMPLE_SCHEMAS))

    def test_structural_validator(self) -> None:
        for example, ref in zip(self.examples, EXAMPLE_SCHEMAS, strict=True):
            with self.subTest(schema=ref):
                issues = self.validator.validate(example, self.bundle.node(ref))
                self.assertEqual([issue.message for issue in issues], [])

    @unittest.skipUnless(HAVE_ORACLE, "jsonschema is not installed")
    def test_oracle(self) -> None:
        schemas = [cr.load_json(path) for path in sorted(SCHEMAS.glob("*.schema.json"))]
        # As in test_declaration_corpus.py: the copies in the registry leave
        # $schema out, so that the pattern keyword below applies everywhere.
        registry = Registry().with_resources(
            [
                (
                    schema["$id"],
                    Resource(
                        contents={k: v for k, v in schema.items() if k != "$schema"},
                        specification=DRAFT202012,
                    ),
                )
                for schema in schemas
            ]
        )

        def pattern(validator: Any, value: str, instance: Any, schema: Any) -> Any:
            # '$' matches only at the end of the string, as in ECMA-262.
            if validator.is_type(instance, "string"):
                regex = value[:-1] + r"\Z" if value.endswith("$") else value
                if not re.search(regex, instance):
                    yield jsonschema.ValidationError(f"{instance!r} does not match {value!r}")

        oracle_class = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, {"pattern": pattern}
        )
        for example, ref in zip(self.examples, EXAMPLE_SCHEMAS, strict=True):
            with self.subTest(schema=ref):
                oracle = oracle_class({"$ref": ref}, registry=registry)
                self.assertEqual([error.message for error in oracle.iter_errors(example)], [])

    def test_results_file_hash(self) -> None:
        stated = STATED.search(self.text)
        assert stated is not None
        length = int(stated.group(1).replace(",", ""))
        data = cr.canonical_bytes(self.examples[0])
        if HAVE_RFC8785:
            self.assertEqual(rfc8785.dumps(self.examples[0]), data)
        self.assertEqual(len(data), length)
        digest = "sha256:" + hashlib.sha256(data).hexdigest()
        self.assertEqual(digest, stated.group(2))
        self.assertEqual(self.examples[1]["results_hash"], digest)


if __name__ == "__main__":
    unittest.main()
