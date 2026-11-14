"""Tests of the formula corpus in fixtures/conformance/formulas/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpus itself, not a formula parser, which M2 implements in both
packages: the format of every case, the declarations against their schema, every
expected IR against spec/schemas/ir.schema.json, every recorded IR hash against
the canonical bytes of its IR, every expected issue against spec/errors.json and
the shapes of the design matrices. They use the standard library and the
structural validator of compile_registry.py, and, where the jsonschema package is
installed, use it as an oracle for the schema.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
import unicodedata
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

try:
    import jsonschema
    from referencing import Registry, Resource
except ImportError:  # pragma: no cover
    HAVE_ORACLE = False
else:
    HAVE_ORACLE = True

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "fixtures" / "conformance" / "formulas"
SCHEMAS = ROOT / "spec" / "schemas"
IR_SCHEMA = "urn:mixedcheck:schema:ir"
DECLARATION_SCHEMA = "urn:mixedcheck:schema:declaration"
FILES = [
    "ordinary",
    "interactions",
    "nested",
    "crossed",
    "double_bar",
    "offsets",
    "malformed",
    "context",
]
CASE_MEMBERS = {
    "id",
    "description",
    "formula",
    "declaration",
    "data",
    "coding",
    "weights",
    "sample_columns",
    "expected",
}
SAME_IR = re.compile(r"same IR as ([a-z_-]+-[0-9]{2})")
SPECIAL_VALUES = {"NaN", "Infinity", "-Infinity"}
# The codes that the builder of the design matrices reports for an IR.
MATRIX_CODES = {"E6071", "E6072", "E6073", "E6077"}
PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def _reject_constant(name: str) -> Any:
    raise ValueError(f"non-finite number {name}")


def load(name: str) -> dict:
    data = (CORPUS / f"{name}.json").read_bytes()
    if data.startswith(b"\xef\xbb\xbf") or b"\r" in data:
        raise ValueError(f"{name}.json has a byte-order mark or a carriage return")
    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=_reject_duplicates,
        parse_constant=_reject_constant,
    )


def _strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [s for key, item in value.items() for s in [key, *_strings(item)]]
    if isinstance(value, list):
        return [s for item in value for s in _strings(item)]
    return []


def _numbers(value: Any) -> list[Any]:
    if isinstance(value, bool):
        return []
    if isinstance(value, int | float):
        return [value]
    if isinstance(value, dict):
        return [n for item in value.values() for n in _numbers(item)]
    if isinstance(value, list):
        return [n for item in value for n in _numbers(item)]
    return []


def _kind(value: Any) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int | float):
        return "number"
    return type(value).__name__


def _column_kinds(column: list[Any]) -> set[str]:
    """The kinds of the values of a data column. In a column with a number,
    the strings 'NaN', 'Infinity' and '-Infinity' are the special values."""
    kinds = {_kind(value) for value in column if value is not None}
    if "number" in kinds:
        specials = {value for value in column if isinstance(value, str)}
        if specials <= SPECIAL_VALUES:
            kinds.discard("str")
    return kinds


class FormulaCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {name: load(name) for name in FILES}
        cls.cases = [(name, case) for name, doc in cls.files.items() for case in doc["cases"]]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.catalogue = cr.Catalogue(ROOT / "spec" / "errors.json")
        cls.validator = cr.Validator(cls.bundle, cls.catalogue)
        cls.codes = {
            entry["code"]: entry for entry in cr.load_json(ROOT / "spec" / "errors.json")["codes"]
        }

    def test_files(self) -> None:
        on_disk = sorted(path.stem for path in CORPUS.glob("*.json"))
        self.assertEqual(on_disk, sorted(FILES))
        readme = (CORPUS / "README.md").read_text(encoding="utf-8")
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(set(doc), {"description", "cases"})
                self.assertIn(f"| {name}.json | {len(doc['cases'])} |", readme)

    def test_case_members(self) -> None:
        seen: set[str] = set()
        for name, case in self.cases:
            with self.subTest(case=case.get("id")):
                self.assertTrue({"id", "description", "formula", "expected"} <= set(case))
                self.assertTrue(set(case) <= CASE_MEMBERS)
                prefix = name.replace("_", "-") + "-"
                self.assertRegex(case["id"], "^" + re.escape(prefix) + "[0-9]{2}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                expected = case["expected"]
                self.assertIn(
                    set(expected),
                    (
                        {"ir", "ir_hash"},
                        {"ir", "ir_hash", "matrices"},
                        {"ir", "ir_hash", "issue"},
                        {"issue"},
                    ),
                )
                if "ir" in expected and "issue" in expected:
                    self.assertIn("data", case)
                    self.assertIn(expected["issue"]["code"], MATRIX_CODES)
                if "data" in case:
                    lengths = {len(column) for column in case["data"].values()}
                    self.assertEqual(len(lengths), 1, "columns differ in length")
                    for column in case["data"].values():
                        kinds = _column_kinds(column)
                        self.assertEqual(len(kinds), 1, "a column mixes kinds or is all null")

    def test_declarations(self) -> None:
        node = self.bundle.node(DECLARATION_SCHEMA)
        for _, case in self.cases:
            if "declaration" in case:
                with self.subTest(case=case["id"]):
                    self.assertEqual(self.validator.validate(case["declaration"], node), [])

    def test_ir_hashable_and_valid(self) -> None:
        node = self.bundle.node(IR_SCHEMA)
        for _, case in self.cases:
            if "ir" not in case["expected"]:
                continue
            ir = case["expected"]["ir"]
            with self.subTest(case=case["id"]):
                for text in _strings(ir):
                    self.assertTrue(unicodedata.is_normalized("NFC", text), text)
                    self.assertNotIn("\x00", text)
                for number in _numbers(ir):
                    self.assertIsInstance(number, int)
                self.assertEqual(self.validator.validate(ir, node), [])
                digest = hashlib.sha256(cr.canonical_bytes(ir)).hexdigest()
                self.assertEqual(case["expected"]["ir_hash"], "sha256:" + digest)

    @unittest.skipUnless(HAVE_ORACLE, "jsonschema is not installed")
    def test_ir_oracle(self) -> None:
        schemas = [cr.load_json(path) for path in sorted(SCHEMAS.glob("*.schema.json"))]
        registry = Registry().with_resources(
            [(schema["$id"], Resource.from_contents(schema)) for schema in schemas]
        )

        def pattern(validator: Any, value: str, instance: Any, schema: Any) -> Any:
            if validator.is_type(instance, "string"):
                regex = value[:-1] + r"\Z" if value.endswith("$") else value
                if not re.search(regex, instance):
                    yield jsonschema.ValidationError(f"{instance!r} does not match {value!r}")

        oracle_class = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, {"pattern": pattern}
        )
        ir_schema = next(schema for schema in schemas if schema["$id"] == IR_SCHEMA)
        jsonschema.Draft202012Validator.check_schema(ir_schema)
        oracle = oracle_class({"$ref": IR_SCHEMA}, registry=registry)
        for _, case in self.cases:
            if "ir" in case["expected"]:
                with self.subTest(case=case["id"]):
                    self.assertEqual(list(oracle.iter_errors(case["expected"]["ir"])), [])

    def test_same_ir(self) -> None:
        hashes = {case["id"]: case["expected"].get("ir_hash") for _, case in self.cases}
        for _, case in self.cases:
            match = SAME_IR.search(case["description"])
            if match:
                with self.subTest(case=case["id"]):
                    self.assertIsNotNone(hashes[case["id"]])
                    self.assertEqual(hashes[case["id"]], hashes[match.group(1)])

    def test_issues(self) -> None:
        for _, case in self.cases:
            if "issue" not in case["expected"]:
                continue
            issue = case["expected"]["issue"]
            with self.subTest(case=case["id"]):
                entry = self.codes[issue["code"]]
                self.assertEqual(entry["area"], "formula")
                self.assertNotEqual(entry["location"], "pointer")
                if entry["location"] == "offset":
                    self.assertEqual(set(issue), {"code", "message", "offset"})
                    size = len(case["formula"].encode("utf-8"))
                    self.assertTrue(0 <= issue["offset"] <= size)
                else:
                    self.assertEqual(set(issue), {"code", "message"})
                parts = PLACEHOLDER.split(entry["template"])
                regex = ""
                for index, part in enumerate(parts):
                    if index % 2 == 0:
                        regex += re.escape(part)
                    elif part == "location":
                        regex += re.escape(f"byte {issue['offset']}")
                    else:
                        regex += ".+"
                self.assertRegex(issue["message"], "^" + regex + r"\Z")

    def test_matrices(self) -> None:
        for _, case in self.cases:
            matrices = case["expected"].get("matrices")
            if matrices is None:
                continue
            ir = case["expected"]["ir"]
            with self.subTest(case=case["id"]):
                rows = len(next(iter(case["data"].values())))
                self.assertEqual(matrices["rows"], sorted(set(matrices["rows"])))
                self.assertTrue(all(0 <= row < rows for row in matrices["rows"]))
                names = [column["name"] for column in ir["fixed"]["columns"]]
                self.assertEqual(len(matrices["x"]), len(matrices["rows"]))
                for row in matrices["x"]:
                    self.assertEqual(len(row), len(names))
                self.assertTrue(set(matrices["x_dropped"]) <= set(names))
                if ir["random"]:
                    columns = matrices["z_columns"]
                    for column in columns:
                        term = ir["random"][column["term"]]
                        self.assertIn(column["column"], [c["name"] for c in term["columns"]])
                    self.assertEqual(len(matrices["z"]), len(matrices["rows"]))
                    for row in matrices["z"]:
                        self.assertEqual(len(row), len(columns))
                else:
                    self.assertNotIn("z", matrices)


if __name__ == "__main__":
    unittest.main()
