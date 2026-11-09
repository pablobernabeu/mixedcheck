"""Tests of the results corpus in fixtures/conformance/results/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpus itself, not `validate_results()`, which M2 implements in
both packages: the files that exist and their place in the README,
spec/vendoring.json and parity/corpora.json, the members of every case, that its
inputs exist in the directory of its file and are vendored, that every expected
issue has a known code with the location its code requires, and that a case
without issues holds a document that is valid under results.schema.json. A
corpus with no case file passes. They use the standard library and the
structural validator of compile_registry.py.
"""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path, PurePosixPath
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "fixtures" / "conformance" / "results"
SCHEMAS = ROOT / "spec" / "schemas"
RESULTS_SCHEMA = "urn:mixedcheck:schema:results"
CASE_MEMBERS = {"id", "description", "document", "sidecar", "data", "declaration", "expected"}
REQUIRED = {"id", "description", "document", "expected"}
INPUTS = ("document", "sidecar", "data", "declaration")
ISSUE_MEMBERS = {"code", "message", "offset", "pointer"}


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def _reject_constant(name: str) -> Any:
    raise ValueError(f"non-finite number {name}")


def load(path: Path) -> Any:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf") or b"\r" in data:
        raise ValueError(f"{path.name} has a byte-order mark or a carriage return")
    if not data.isascii():
        raise ValueError(f"{path.name} is not ASCII")
    return json.loads(
        data.decode("utf-8"), object_pairs_hook=_reject_duplicates, parse_constant=_reject_constant
    )


def present_files() -> list[str]:
    return sorted(path.name for path in CORPUS.glob("*.json"))


def readme_table() -> dict[str, int]:
    text = (CORPUS / "README.md").read_text(encoding="utf-8")
    rows = re.findall(r"^\| ([a-z_]+\.json) \| ([0-9]+) \|", text, flags=re.MULTILINE)
    return {name: int(count) for name, count in rows}


class ResultsCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {name: load(CORPUS / name) for name in present_files()}
        cls.cases = [(name, case) for name, doc in cls.files.items() for case in doc["cases"]]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.validator = cr.Validator(cls.bundle, cr.Catalogue(ROOT / "spec" / "errors.json"))
        errors = json.loads((ROOT / "spec" / "errors.json").read_bytes())
        cls.codes = {code["code"]: code for code in errors["codes"]}
        cls.vendored = set(json.loads((ROOT / "spec" / "vendoring.json").read_bytes())["artefacts"])

    def test_readme_exists(self) -> None:
        self.assertTrue((CORPUS / "README.md").is_file())

    def test_files_are_registered(self) -> None:
        table = readme_table()
        self.assertEqual(sorted(table), present_files(), "the README's table of files")
        parity = json.loads((ROOT / "parity" / "corpora.json").read_bytes())["corpora"]
        listed = {entry["file"] for entry in parity}
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(table[name], len(doc["cases"]), "count in the README")
                self.assertIn(f"fixtures/conformance/results/{name}", self.vendored)
                self.assertIn(f"results/{name}", listed)

    def test_only_case_files_and_their_directories(self) -> None:
        stems = {name[: -len(".json")] for name in present_files()}
        for path in CORPUS.iterdir():
            with self.subTest(path=path.name):
                if path.is_dir():
                    self.assertIn(path.name, stems, "a directory of inputs belongs to a file")
                else:
                    self.assertTrue(path.name == "README.md" or path.suffix == ".json")

    def test_every_input_is_used_and_vendored(self) -> None:
        used = {
            case[member]
            for name, case in self.cases
            for member in INPUTS
            if isinstance(case.get(member), str)
        }
        for directory in (path for path in CORPUS.iterdir() if path.is_dir()):
            for path in directory.rglob("*"):
                if path.is_file():
                    relative = path.relative_to(CORPUS).as_posix()
                    with self.subTest(input=relative):
                        self.assertIn(relative, used, "an input that no case uses")
                        self.assertIn(f"fixtures/conformance/results/{relative}", self.vendored)

    def test_file_members(self) -> None:
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(set(doc), {"description", "cases"})
                self.assertIsInstance(doc["description"], str)
                self.assertIsInstance(doc["cases"], list)

    def test_cases(self) -> None:
        seen: set[str] = set()
        for name, case in self.cases:
            stem = name[: -len(".json")]
            with self.subTest(case=case.get("id")):
                self.assertLessEqual(set(case), CASE_MEMBERS)
                self.assertLessEqual(REQUIRED, set(case))
                self.assertRegex(case["id"], rf"^results-{stem}-[0-9]{{3}}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                self.assertIsInstance(case["description"], str)
                self.assertTrue(case["description"])
                for member in INPUTS:
                    if member not in case:
                        continue
                    path = PurePosixPath(case[member])
                    self.assertEqual(path.parts[0], stem, f"{member} lies in {stem}/")
                    self.assertNotIn("..", path.parts)
                    self.assertTrue((CORPUS / path).is_file(), f"{member} exists")
                if "declaration" in case:
                    self.assertIn("data", case)
                expected = case["expected"]
                self.assertIsInstance(expected, dict)
                wanted = {"issues", "sidecar_issues"} if "sidecar" in case else {"issues"}
                self.assertEqual(set(expected), wanted)
                for key in sorted(expected):
                    self.assertIsInstance(expected[key], list)
                    for issue in expected[key]:
                        self.check_issue(issue)
                errors = [issue for issue in expected["issues"] if issue["code"].startswith("E")]
                if "sidecar" in case and errors:
                    self.assertEqual(expected["sidecar_issues"], [], "no verification after errors")

    def check_issue(self, issue: Any) -> None:
        self.assertIsInstance(issue, dict)
        self.assertLessEqual(set(issue), ISSUE_MEMBERS)
        self.assertIn(issue["code"], self.codes)
        self.assertIsInstance(issue["message"], str)
        self.assertTrue(issue["message"])
        location = self.codes[issue["code"]]["location"]
        if location == "offset":
            self.assertEqual(set(issue) - {"code", "message"}, {"offset"})
            self.assertIsInstance(issue["offset"], int)
        elif location == "pointer":
            self.assertEqual(set(issue) - {"code", "message"}, {"pointer"})
            self.assertIsInstance(issue["pointer"], str)
        elif location == "offset_or_pointer":
            self.assertEqual(len(set(issue) - {"code", "message"}), 1)
        else:
            self.assertEqual(set(issue), {"code", "message"})

    def test_valid_documents_meet_the_schema(self) -> None:
        node = self.bundle.node(RESULTS_SCHEMA)
        for _, case in self.cases:
            codes = [issue["code"] for issue in case["expected"]["issues"]]
            if codes not in ([], ["W7090"]):
                continue
            with self.subTest(case=case["id"]):
                text = (CORPUS / case["document"]).read_bytes().decode("utf-8")
                document = json.loads(text, object_pairs_hook=_reject_duplicates)
                issues = self.validator.validate(document, node)
                self.assertEqual([issue.message for issue in issues], [])


if __name__ == "__main__":
    unittest.main()
