"""Tests of the declaration and YAML corpora in fixtures/conformance/declarations/
and fixtures/conformance/yaml/, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpora themselves, not a validator, which both packages
implement: the format of every case, the input files and their listing in
spec/vendoring.json, every canonical form and hash, the validity of every valid
declaration and of every declaration that reaches stage 4 or 5 under
spec/schemas/declaration.schema.json, the structural issues of stage 3 against
the structural validator of compile_registry.py, the scalars of each converted
YAML declaration against the YAML text, and every expected issue against
spec/errors.json and the reporting rules of docs/spec/errors.md. They use the
standard library, the structural validator and YAML reader of
compile_registry.py and, where they are installed, PyYAML and the jsonschema
package as an oracle.
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
    import yaml
except ImportError:  # pragma: no cover
    HAVE_YAML = False
else:
    HAVE_YAML = bool(getattr(yaml, "__with_libyaml__", False))

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures" / "conformance"
SCHEMAS = ROOT / "spec" / "schemas"
DECLARATION_SCHEMA = "urn:mixedcheck:schema:declaration"
CORPORA = {
    "declarations": [
        "valid",
        "reading",
        "version",
        "structure",
        "references",
        "meaning",
        "precedence",
    ],
    "yaml": ["valid", "reading", "conversion", "validation", "precedence"],
}
CASE_MEMBERS = {"id", "description", "path", "minimal", "expected"}
PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")
SAME = re.compile(r"Same canonical bytes as ((?:declarations|yaml)-[a-z]+-[0-9]{3})\.")
NUMBER = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")
# Codes that the checks in code of stage 3 give and the schema alone does not.
UTC = cr.load_json(SCHEMAS / "defs.schema.json")["$defs"]["utc_timestamp"]["pattern"]
# The areas of the codes that a validator reports in stages 2 to 5, located by
# JSON Pointer, besides E1207 of the unicode area.
VALIDATION_AREAS = {"schema", "declaration"}


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def _reject_constant(name: str) -> Any:
    raise ValueError(f"non-finite number {name}")


def _loads(text: str) -> Any:
    return json.loads(text, object_pairs_hook=_reject_duplicates, parse_constant=_reject_constant)


def _at(value: Any, pointer: str) -> Any:
    for raw in pointer.split("/")[1:]:
        token = raw.replace("~1", "/").replace("~0", "~")
        value = value[int(token)] if isinstance(value, list) else value[token]
    return value


def _is_yaml(path: str) -> bool:
    return path.lower().endswith((".yaml", ".yml"))


class DeclarationCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files: dict[tuple[str, str], dict] = {}
        for corpus, groups in CORPORA.items():
            for group in groups:
                data = (FIXTURES / corpus / f"{group}.json").read_bytes()
                if not data.isascii() or b"\r" in data:
                    raise ValueError(
                        f"{corpus}/{group}.json is not ASCII text with LF line endings"
                    )
                cls.files[(corpus, group)] = _loads(data.decode("ascii"))
        cls.cases = [
            (corpus, group, case)
            for (corpus, group), doc in cls.files.items()
            for case in doc["cases"]
        ]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.catalogue = cr.Catalogue(ROOT / "spec" / "errors.json")
        cls.validator = cr.Validator(cls.bundle, cls.catalogue)
        cls.node = cls.bundle.node(DECLARATION_SCHEMA)
        cls.codes = {
            entry["code"]: entry for entry in cr.load_json(ROOT / "spec" / "errors.json")["codes"]
        }

    def _bytes(self, corpus: str, case: dict) -> bytes:
        return (FIXTURES / corpus / case["path"]).read_bytes()

    def _json_input(self, corpus: str, case: dict) -> Any:
        return _loads(self._bytes(corpus, case).decode("utf-8"))

    def test_files(self) -> None:
        for corpus, groups in CORPORA.items():
            directory = FIXTURES / corpus
            on_disk = sorted(path.stem for path in directory.glob("*.json"))
            self.assertEqual(on_disk, sorted(groups))
            readme = (directory / "README.md").read_text(encoding="utf-8")
            for group in groups:
                with self.subTest(file=f"{corpus}/{group}.json"):
                    doc = self.files[(corpus, group)]
                    self.assertEqual(set(doc), {"description", "cases"})
                    self.assertIn(f"| {group}.json | {len(doc['cases'])} |", readme)

    def test_inputs_and_vendoring(self) -> None:
        listed = set(cr.load_json(ROOT / "spec" / "vendoring.json")["artefacts"])
        for corpus, groups in CORPORA.items():
            directory = FIXTURES / corpus
            paths = [case["path"] for c, _, case in self.cases if c == corpus]
            self.assertEqual(len(paths), len(set(paths)), f"{corpus}: an input serves two cases")
            on_disk = sorted(
                str(path.relative_to(directory)).replace("\\", "/")
                for group in groups
                for path in (directory / group).glob("*")
            )
            self.assertEqual(on_disk, sorted(paths), f"{corpus}: input files without a case")
            expected = {f"fixtures/conformance/{corpus}/{group}.json" for group in groups}
            expected |= {f"fixtures/conformance/{corpus}/{path}" for path in paths}
            self.assertEqual(expected - listed, set(), "not listed in spec/vendoring.json")

    def test_case_members(self) -> None:
        seen: set[str] = set()
        for corpus, group, case in self.cases:
            with self.subTest(case=case.get("id")):
                self.assertTrue({"id", "description", "path", "expected"} <= set(case))
                self.assertTrue(set(case) <= CASE_MEMBERS)
                self.assertRegex(case["id"], f"^{corpus}-{group}-[0-9]{{3}}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                self.assertTrue(case["path"].startswith(f"{group}/"))
                self.assertIs(case.get("minimal", True), True)
                expected = case["expected"]
                if group == "valid":
                    self.assertEqual(set(expected), {"canonical", "sha256"})
                else:
                    self.assertEqual(set(expected), {"issues"})
                    self.assertTrue(expected["issues"])

    def test_canonical_and_hashes(self) -> None:
        for corpus, group, case in self.cases:
            if group != "valid":
                continue
            with self.subTest(case=case["id"]):
                canonical = case["expected"]["canonical"]
                value = _loads(canonical)
                self.assertEqual(cr.canonical_bytes(value), canonical.encode("utf-8"))
                self.assertEqual(cr.profile_issue(value, self.catalogue), None)
                digest = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
                self.assertEqual(case["expected"]["sha256"], digest)
                self.assertEqual(self.validator.validate(value, self.node), [])
                if not _is_yaml(case["path"]):
                    self.assertEqual(self._json_input(corpus, case), value)

    def test_same_canonical(self) -> None:
        hashes = {
            case["id"]: case["expected"].get("sha256")
            for _, group, case in self.cases
            if group == "valid"
        }
        for _, _, case in self.cases:
            match = SAME.search(case["description"])
            if match:
                with self.subTest(case=case["id"]):
                    self.assertEqual(hashes[case["id"]], hashes[match.group(1)])

    def test_example_hash(self) -> None:
        text = (ROOT / "docs" / "spec" / "declarations.md").read_text(encoding="utf-8")
        published = re.search(r"The declaration hash is `(sha256:[0-9a-f]{64})`", text).group(1)
        example = [
            case
            for corpus, group, case in self.cases
            if case["path"] in ("valid/crt_example.json", "valid/example.yaml")
        ]
        self.assertEqual(len(example), 2)
        for case in example:
            self.assertEqual(case["expected"]["sha256"], published)

    @unittest.skipUnless(HAVE_YAML, "PyYAML with libyaml is not installed")
    def test_yaml_scalars(self) -> None:
        # Each scalar of a converted declaration is the text of the YAML scalar
        # at the same place, as a string, a boolean or a number.
        def same(raw: Any, value: Any) -> bool:
            if isinstance(raw, dict):
                return (
                    isinstance(value, dict)
                    and sorted(raw) == sorted(value)
                    and all(same(raw[key], value[key]) for key in raw)
                )
            if isinstance(raw, list):
                return (
                    isinstance(value, list)
                    and len(raw) == len(value)
                    and all(map(same, raw, value))
                )
            if isinstance(value, bool):
                return raw == ("true" if value else "false")
            if isinstance(value, int | float):
                return bool(NUMBER.fullmatch(raw)) and float(raw) == value
            return raw == value

        for corpus, group, case in self.cases:
            if group != "valid" or not _is_yaml(case["path"]):
                continue
            with self.subTest(case=case["id"]):
                raw, problem = cr.parse_yaml(
                    self._bytes(corpus, case).decode("utf-8"), self.catalogue
                )
                self.assertIsNone(problem)
                value = _loads(case["expected"]["canonical"])
                self.assertTrue(same(raw, value))

    def test_issues(self) -> None:
        for corpus, group, case in self.cases:
            if group == "valid":
                continue
            issues = case["expected"]["issues"]
            with self.subTest(case=case["id"]):
                located = [issue for issue in issues if issue["code"] != "W1490"]
                for issue in issues:
                    entry = self.codes[issue["code"]]
                    self.assertNotIn("languages", entry)
                    if "offset" in issue:
                        self.assertEqual(set(issue), {"code", "message", "offset"})
                        self.assertIn(entry["location"], ("offset", "offset_or_pointer"))
                        size = len(self._bytes(corpus, case))
                        self.assertTrue(0 <= issue["offset"] <= size)
                        where = f"byte {issue['offset']}"
                    elif "pointer" in issue:
                        self.assertEqual(set(issue), {"code", "message", "pointer"})
                        self.assertIn(entry["location"], ("pointer", "offset_or_pointer"))
                        where = cr.display_escape(issue["pointer"]) or "(root)"
                    else:
                        self.assertEqual(set(issue), {"code", "message"})
                        self.assertEqual(entry["location"], "none")
                        where = ""
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
                validation = all(
                    self.codes[issue["code"]]["area"] in VALIDATION_AREAS
                    or issue["code"] == "E1207"
                    for issue in located
                )
                if not validation:
                    # A reader reports one issue.
                    self.assertEqual(len(issues), 1)
                else:
                    # A list from stages 2 to 5: sorted, reported once and capped.
                    for issue in located:
                        self.assertIn("pointer", issue)
                    keys = [(i["pointer"], i["code"], i["message"]) for i in located]
                    self.assertEqual(keys, sorted(set(keys)))
                    self.assertLessEqual(len(located), 100)
                    if len(issues) > len(located):
                        self.assertEqual(issues[-1]["code"], "W1490")
                        self.assertEqual(len(located), 100)

    def test_structure(self) -> None:
        # Stage 3 issues are those of the structural validator, together with
        # those of the checks in code: E1207 and the day of a timestamp.
        for corpus, group, case in self.cases:
            if _is_yaml(case["path"]) or group == "valid":
                continue
            codes = [issue["code"] for issue in case["expected"]["issues"]]
            if not codes or not all(
                code.startswith("E14") and code != "E1441" or code in ("E1207", "W1490")
                for code in codes
            ):
                continue
            with self.subTest(case=case["id"]):
                value = self._json_input(corpus, case)
                found = [
                    {
                        "code": i.code,
                        "message": i.message,
                        **({} if i.pointer is None else {"pointer": i.pointer}),
                    }
                    for i in self.validator.validate(value, self.node)
                ]
                in_code = [
                    issue
                    for issue in case["expected"]["issues"]
                    if issue["code"] == "E1207"
                    or (
                        issue["code"] == "E1406"
                        and issue["message"].endswith("not a valid UTC timestamp.")
                        and cr._search(UTC, _at(value, issue["pointer"]))
                    )
                ]
                rest = [issue for issue in case["expected"]["issues"] if issue not in in_code]
                self.assertEqual(found, rest)

    def test_rules_in_code_on_valid_structure(self) -> None:
        for corpus, group, case in self.cases:
            if _is_yaml(case["path"]) or group == "valid":
                continue
            codes = {issue["code"] for issue in case["expected"]["issues"]}
            if not codes or not all(code.startswith("E20") for code in codes):
                continue
            with self.subTest(case=case["id"]):
                self.assertEqual(
                    self.validator.validate(self._json_input(corpus, case), self.node), []
                )

    @unittest.skipUnless(HAVE_ORACLE, "jsonschema is not installed")
    def test_oracle(self) -> None:
        schemas = [cr.load_json(path) for path in sorted(SCHEMAS.glob("*.schema.json"))]
        # jsonschema takes the validator class from the $schema of a resource
        # whose root a $ref reaches, which would drop the pattern keyword below,
        # so the copies in the registry leave $schema out.
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
            if validator.is_type(instance, "string"):
                regex = value[:-1] + r"\Z" if value.endswith("$") else value
                if not re.search(regex, instance):
                    yield jsonschema.ValidationError(f"{instance!r} does not match {value!r}")

        oracle_class = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, {"pattern": pattern}
        )
        oracle = oracle_class({"$ref": DECLARATION_SCHEMA}, registry=registry)
        self.assertTrue(list(oracle.iter_errors({"vocabulary": "0.1.0\n"})))
        for corpus, group, case in self.cases:
            if group == "valid":
                value = _loads(case["expected"]["canonical"])
            elif _is_yaml(case["path"]):
                continue
            else:
                codes = {issue["code"] for issue in case["expected"]["issues"]}
                if not all(code.startswith("E20") for code in codes):
                    continue
                value = self._json_input(corpus, case)
            with self.subTest(case=case["id"]):
                self.assertEqual([e.message for e in oracle.iter_errors(value)], [])


if __name__ == "__main__":
    unittest.main()
