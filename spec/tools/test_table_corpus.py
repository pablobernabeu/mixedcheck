"""Tests of the table corpus in fixtures/conformance/tables/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpus itself, not a table reader, which M2 implements in both
packages: the format of every case, the input files and their listing in
spec/vendoring.json, the edgezoo inputs against the evidence they come from,
every declaration against spec/schemas/declaration.schema.json and the hashable
profile, the expected columns and samples, every expected issue against
spec/errors.json and, through fixtures/conformance/tools/make_table_corpus.py,
that the corpus equals what its scratch derivation and oracles give. They use
the standard library and compile_registry.py.
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "fixtures" / "conformance" / "tables"
TOOLS = ROOT / "fixtures" / "conformance" / "tools"
EDGEZOO = ROOT / "docs" / "design" / "evidence" / "decisions" / "E-verify" / "edgezoo"
SCHEMAS = ROOT / "spec" / "schemas"
DECLARATION_SCHEMA = "urn:mixedcheck:schema:declaration"
GROUPS = [
    "edgezoo",
    "edge",
    "input",
    "records",
    "header",
    "values",
    "inference",
    "keys",
    "precedence",
    "samples",
]
CASE_MEMBERS = {"id", "description", "path", "file", "declaration", "formula", "expected"}
TYPES = {"string", "integer", "number", "boolean", "date", "datetime"}
SPECIAL = {"NaN", "Infinity", "-Infinity"}
AREAS = {"input", "unicode", "table"}
PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def _reject_constant(name: str) -> Any:
    raise ValueError(f"non-finite number {name}")


def _nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text) if cr.normalisable(text) else text


def _fits(value: Any, kind: str) -> bool:
    if value is None:
        return True
    if kind == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == "number":
        return value in SPECIAL or (isinstance(value, int | float) and not isinstance(value, bool))
    if kind == "boolean":
        return isinstance(value, bool)
    return isinstance(value, str)


class TableCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {}
        for group in GROUPS:
            data = (CORPUS / f"{group}.json").read_bytes()
            if not data.isascii() or b"\r" in data:
                raise ValueError(f"{group}.json is not ASCII text with LF line endings")
            cls.files[group] = json.loads(
                data.decode("ascii"),
                object_pairs_hook=_reject_duplicates,
                parse_constant=_reject_constant,
            )
        cls.cases = [(group, case) for group, doc in cls.files.items() for case in doc["cases"]]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.catalogue = cr.Catalogue(ROOT / "spec" / "errors.json")
        cls.validator = cr.Validator(cls.bundle, cls.catalogue)
        cls.codes = {
            entry["code"]: entry for entry in cr.load_json(ROOT / "spec" / "errors.json")["codes"]
        }

    def _size(self, case: dict) -> int:
        return len((CORPUS / case["path"]).read_bytes())

    def test_files(self) -> None:
        on_disk = sorted(path.stem for path in CORPUS.glob("*.json"))
        self.assertEqual(on_disk, sorted(GROUPS))
        readme = (CORPUS / "README.md").read_text(encoding="utf-8")
        for group, doc in self.files.items():
            with self.subTest(file=group):
                self.assertEqual(set(doc), {"description", "cases"})
                self.assertIn(f"| {group}.json | {len(doc['cases'])} |", readme)

    def test_inputs_and_vendoring(self) -> None:
        listed = set(cr.load_json(ROOT / "spec" / "vendoring.json")["artefacts"])
        paths = [case["path"] for _, case in self.cases if "path" in case]
        self.assertEqual(len(paths), len(set(paths)), "an input serves two cases")
        on_disk = sorted(
            str(path.relative_to(CORPUS)).replace("\\", "/")
            for group in GROUPS
            for path in (CORPUS / group).glob("*")
        )
        self.assertEqual(on_disk, sorted(paths), "input files without a case")
        expected = {f"fixtures/conformance/tables/{group}.json" for group in GROUPS}
        expected |= {f"fixtures/conformance/tables/{path}" for path in paths}
        self.assertEqual(expected - listed, set(), "not listed in spec/vendoring.json")

    def test_edgezoo_inputs_as_stored(self) -> None:
        sources = sorted(path.name for path in EDGEZOO.iterdir() if path.is_dir())
        cases = [case for group, case in self.cases if group == "edgezoo"]
        self.assertEqual(sorted(Path(case["path"]).stem for case in cases), sources)
        for case in cases:
            with self.subTest(case=case["id"]):
                name = Path(case["path"]).stem
                stored = (EDGEZOO / name / "data.csv").read_bytes()
                self.assertEqual((CORPUS / case["path"]).read_bytes(), stored)
                design = json.loads((EDGEZOO / name / "design.json").read_text("utf-8"))
                self.assertEqual(case["declaration"]["table"], design["table"])

    def test_case_members(self) -> None:
        seen: set[str] = set()
        for group, case in self.cases:
            with self.subTest(case=case.get("id")):
                self.assertTrue({"id", "description", "expected"} <= set(case))
                self.assertTrue(set(case) <= CASE_MEMBERS)
                self.assertRegex(case["id"], f"^tables-{group}-[0-9]{{3}}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                self.assertEqual(("path" in case) + ("file" in case), 1)
                if "path" in case:
                    self.assertRegex(case["path"], f"^{group}/[A-Za-z0-9_]+\\.csv$")
                else:
                    self.assertIn(case["file"], ("missing", "directory"))
                expected = case["expected"]
                if "issue" in expected:
                    self.assertEqual(set(expected), {"issue"})
                    self.assertNotIn("formula", case)
                elif "formula" in case:
                    self.assertEqual(set(expected), {"columns", "design_sample", "analysis_sample"})
                else:
                    self.assertEqual(set(expected), {"columns"})

    def test_declarations(self) -> None:
        node = self.bundle.node(DECLARATION_SCHEMA)
        for _, case in self.cases:
            if "declaration" in case:
                with self.subTest(case=case["id"]):
                    declaration = case["declaration"]
                    self.assertEqual(self.validator.validate(declaration, node), [])
                    self.assertIsNone(cr.profile_issue(declaration, self.catalogue))
                    self.assertIn("table", declaration)

    def test_columns(self) -> None:
        for _, case in self.cases:
            columns = case["expected"].get("columns")
            if columns is None:
                continue
            with self.subTest(case=case["id"]):
                names = [column["name"] for column in columns]
                self.assertEqual(len({_nfc(name) for name in names}), len(names))
                lengths = {len(column["values"]) for column in columns}
                self.assertEqual(len(lengths), 1, "columns differ in length")
                table = case.get("declaration", {}).get("table")
                if table is not None:
                    fields = table["fields"]
                    self.assertEqual([_nfc(name) for name in names], [f["name"] for f in fields])
                    for column, f in zip(columns, fields, strict=True):
                        self.assertEqual(column["type"], f.get("type", "string"))
                for column in columns:
                    self.assertEqual(set(column), {"name", "type", "values"})
                    self.assertIn(column["type"], TYPES)
                    if table is None:
                        self.assertIn(column["type"], ("string", "number", "boolean"))
                    for value in column["values"]:
                        self.assertTrue(_fits(value, column["type"]), value)

    def test_samples(self) -> None:
        for _, case in self.cases:
            if "formula" not in case:
                continue
            with self.subTest(case=case["id"]):
                expected = case["expected"]
                rows = len(expected["columns"][0]["values"])
                design, analysis = expected["design_sample"], expected["analysis_sample"]
                self.assertEqual(design, sorted(set(design)))
                self.assertTrue(all(0 <= row < rows for row in design))
                self.assertEqual(analysis, sorted(set(analysis)))
                self.assertTrue(set(analysis) <= set(design))

    def test_issues(self) -> None:
        for _, case in self.cases:
            issue = case["expected"].get("issue")
            if issue is None:
                continue
            with self.subTest(case=case["id"]):
                entry = self.codes[issue["code"]]
                self.assertIn(entry["area"], AREAS)
                self.assertNotIn("languages", entry)
                if entry["location"] == "none":
                    self.assertEqual(set(issue), {"code", "message"})
                    where = ""
                else:
                    self.assertIn(entry["location"], ("offset", "offset_or_pointer"))
                    self.assertEqual(set(issue), {"code", "message", "offset"})
                    self.assertTrue(0 <= issue["offset"] <= self._size(case))
                    where = f"byte {issue['offset']}"
                parts = PLACEHOLDER.split(entry["template"])
                regex = ""
                for index, part in enumerate(parts):
                    if index % 2 == 0:
                        regex += re.escape(part)
                    elif part == "location":
                        regex += re.escape(where)
                    else:
                        regex += ".*"
                self.assertRegex(issue["message"], "^" + regex + r"\Z")

    def test_generator(self) -> None:
        sys.path.insert(0, str(TOOLS))
        try:
            import make_table_corpus as generator
        finally:
            sys.path.remove(str(TOOLS))
        texts, inputs = generator.corpus()
        for name, text in texts.items():
            with self.subTest(file=name):
                self.assertEqual((CORPUS / name).read_text(encoding="ascii"), text)
        for path, data in inputs.items():
            with self.subTest(input=path):
                self.assertEqual((CORPUS / path).read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
