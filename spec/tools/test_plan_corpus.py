"""Tests of the plan corpus in fixtures/conformance/plans/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpus itself, not `validate_plan()`, which M3 implements in
both packages: the files that exist and their place in the README,
spec/vendoring.json and parity/corpora.json, the members of every case, that
its plan exists in the directory of its file and is vendored, that every
expected issue has a known code with the location its code requires, that the
recorded hashes of a plan without E1321 match its sections, and that a plan
without issues in some language is valid under plan.schema.json. They use the
standard library and the structural validator of compile_registry.py.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
import unittest
from pathlib import Path, PurePosixPath
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "fixtures" / "conformance" / "plans"
PLAN_SCHEMA = "urn:mixedcheck:schema:plan"
CASE_MEMBERS = {"id", "description", "plan", "languages", "expected"}
REQUIRED = {"id", "description", "plan", "expected"}


def load(path: Path) -> Any:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf") or b"\r" in data or not data.isascii():
        raise ValueError(f"{path.name} is not ASCII text with line feeds")
    return json.loads(data.decode("utf-8"))


def canonical_hash(value: Any) -> str:
    """The hash of a value of the hashable profile written by RFC 8785, which
    for strings within the Basic Multilingual Plane, integers, booleans,
    arrays and objects is JSON with sorted keys and no white space."""
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


class PlanCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {path.name: load(path) for path in sorted(CORPUS.glob("*.json"))}
        cls.cases = [(name, case) for name, doc in cls.files.items() for case in doc["cases"]]
        cls.bundle = cr.Bundle(ROOT / "spec" / "schemas")
        cls.validator = cr.Validator(cls.bundle, cr.Catalogue(ROOT / "spec" / "errors.json"))
        errors = json.loads((ROOT / "spec" / "errors.json").read_bytes())
        cls.codes = {code["code"]: code for code in errors["codes"]}
        cls.vendored = set(json.loads((ROOT / "spec" / "vendoring.json").read_bytes())["artefacts"])

    def test_files_are_registered(self) -> None:
        text = (CORPUS / "README.md").read_text(encoding="utf-8")
        table = {
            name: int(count)
            for name, count in re.findall(r"^\| ([a-z_]+\.json) \| ([0-9]+) \|", text, re.MULTILINE)
        }
        self.assertEqual(sorted(table), sorted(self.files))
        listed = {
            e["file"]
            for e in json.loads((ROOT / "parity" / "corpora.json").read_bytes())["corpora"]
        }
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(set(doc), {"description", "cases"})
                self.assertEqual(table[name], len(doc["cases"]))
                self.assertIn(f"fixtures/conformance/plans/{name}", self.vendored)
                self.assertIn(f"plans/{name}", listed)

    def test_every_input_is_used_and_vendored(self) -> None:
        used = {case["plan"] for _, case in self.cases}
        for path in CORPUS.rglob("*"):
            if path.is_file() and path.parent != CORPUS:
                relative = path.relative_to(CORPUS).as_posix()
                with self.subTest(input=relative):
                    self.assertIn(relative, used)
                    self.assertIn(f"fixtures/conformance/plans/{relative}", self.vendored)

    def test_cases(self) -> None:
        seen: set[str] = set()
        for name, case in self.cases:
            stem = name[: -len(".json")]
            with self.subTest(case=case.get("id")):
                self.assertLessEqual(set(case), CASE_MEMBERS)
                self.assertLessEqual(REQUIRED, set(case))
                self.assertRegex(case["id"], rf"^plans-{stem}-[0-9]{{3}}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                self.assertTrue(case["description"])
                path = PurePosixPath(case["plan"])
                self.assertEqual(path.parts[0], stem)
                self.assertTrue((CORPUS / path).is_file())
                for language in case.get("languages", []):
                    self.assertIn(language, ("R", "Python"))
                self.assertEqual(set(case["expected"]), {"issues"})
                for issue in case["expected"]["issues"]:
                    self.assertIn(issue["code"], self.codes)
                    location = self.codes[issue["code"]]["location"]
                    if location == "pointer":
                        self.assertEqual(set(issue), {"code", "message", "pointer"})
                    else:
                        self.assertEqual(set(issue), {"code", "message"})

    def test_hashes_match_unless_reported(self) -> None:
        for _, case in self.cases:
            codes = [(i["code"], i.get("pointer")) for i in case["expected"]["issues"]]
            plan = load(CORPUS / case["plan"])
            if not isinstance(plan, dict) or "design" not in plan:
                continue
            with self.subTest(case=case["id"]):
                if ("E1321", "/design_plan_hash") not in codes:
                    self.assertEqual(canonical_hash(plan["design"]), plan["design_plan_hash"])
                for i, entry in enumerate(plan.get("bindings", [])):
                    if ("E1321", f"/bindings/{i}/hash") not in codes:
                        self.assertEqual(canonical_hash(entry["binding"]), entry["hash"])

    def test_plans_meet_the_schema(self) -> None:
        node = self.bundle.node(PLAN_SCHEMA)
        for _, case in self.cases:
            codes = {i["code"] for i in case["expected"]["issues"]}
            if "E1441" in codes:
                continue
            with self.subTest(case=case["id"]):
                issues = self.validator.validate(load(CORPUS / case["plan"]), node)
                self.assertEqual([issue.message for issue in issues], [])


if __name__ == "__main__":
    unittest.main()
