"""Tests of the audit corpus in fixtures/conformance/audits/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the corpus itself, not `audit()`, which M2 implements in both
packages: the files that exist and their place in the README, spec/vendoring.json
and parity/corpora.json, the members and inputs of every case, its declaration
against the declaration schema, its checks against the compiled registry, every
expected finding against the schema of a finding and the registry entry of its
check, the order of the findings, the invariants of a shareable document on the
shareable findings and every issue against spec/errors.json. A corpus with no
case file passes. They use the standard library and the structural validator of
compile_registry.py.
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
import unittest
from decimal import Decimal
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "fixtures" / "conformance" / "audits"
SCHEMAS = ROOT / "spec" / "schemas"
FINDING_SCHEMA = "urn:mixedcheck:schema:results#/$defs/finding"
DECLARATION_SCHEMA = "urn:mixedcheck:schema:declaration"
# One file for each prefix of the check identifiers, and one for the filter.
PREFIXES = [
    "structure",
    "identifiability",
    "design",
    "sample",
    "labels",
    "keys",
    "assignment",
    "outcome",
]
FILES = [*PREFIXES, "privacy"]
CASE_MEMBERS = {
    "id",
    "description",
    "checks",
    "data",
    "formula",
    "declaration",
    "family",
    "coding",
    "weights",
    "sample_columns",
    "outcome_access",
    "reason",
    "exploratory",
    "privacy",
    "exact",
    "expected",
}
REQUIRED = {"id", "description", "checks", "data", "formula", "expected"}
# Messages and fallbacks that no case can expect, with the reason. The
# solver of outcome.separation always reaches an optimum of its feasible and
# bounded programs, so no_solution needs a failing solver, which unit tests
# of the packages simulate. The fallbacks of the T1 checks below render only
# statistics that a rule of the decision reads, so a suppression that would
# call for the fallback suppresses the finding as a whole (privacy.md,
# Decisions).
UNREACHABLE_MESSAGES = {("outcome.separation", "no_solution")}
UNREACHABLE_FALLBACKS = {
    ("outcome.boundary_shares", "at_bounds"),
    ("outcome.boundary_shares", "within_bounds"),
    ("outcome.constant_clusters", "many"),
    ("outcome.constant_clusters", "some"),
}
TIERS = ["T0", "T1", "T2"]
MAX_ROWS = 40
SPECIAL_VALUES = {"NaN", "Infinity", "-Infinity"}
PSEUDONYM = re.compile(r"^#[1-9][0-9]*$")
PART_ORDER = ("column", "factor", "first", "second", "term", "unit")


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
    """The rows of the table of files in the README, file name to count."""
    text = (CORPUS / "README.md").read_text(encoding="utf-8")
    rows = re.findall(r"^\| ([a-z_]+\.json) \| ([0-9]+) \|", text, flags=re.MULTILINE)
    return {name: int(count) for name, count in rows}


def scope_key(finding: dict) -> tuple:
    """The order of findings of documents.md (Findings): the check, then the
    list of scope parts in order of part name, as pairs of the name and the NFC
    form of the value, a prefix first."""
    parts = sorted(finding["scope"].items())
    return (
        finding["check"],
        [(name, unicodedata.normalize("NFC", value)) for name, value in parts],
    )


def fallback_matches(template: str, text: str) -> bool:
    """Whether a text can be the rendering of a fallback template: its literal
    parts in order, each placeholder matching any text."""
    parts = re.split(r"\{[a-z][a-z0-9_]*\}", template)
    pattern = ".+?".join(re.escape(part) for part in parts)
    return re.fullmatch(pattern, text, flags=re.DOTALL) is not None


def quantile_written(p: float, n: int, k: int) -> bool:
    """The quantile rule of documents.md, in integer arithmetic on the shortest
    decimal that represents p."""
    text = cr.format_number(p)
    decimal = Decimal(text)
    places = max(0, -decimal.as_tuple().exponent)  # type: ignore[operator]
    scale = 10**places
    m = int(decimal * scale)
    return n * min(m, scale - m) >= k * scale


class AuditCorpusTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {name: load(CORPUS / name) for name in present_files()}
        cls.cases = [(name, case) for name, doc in cls.files.items() for case in doc["cases"]]
        cls.bundle = cr.Bundle(SCHEMAS)
        cls.validator = cr.Validator(cls.bundle, cr.Catalogue(ROOT / "spec" / "errors.json"))
        registry = json.loads((ROOT / "spec" / "compiled" / "registry.json").read_bytes())
        cls.entries = {entry["id"]: entry for entry in registry["entries"]}
        cls.k = registry["privacy"]["min_count"]
        cls.share = float(registry["privacy"]["dominance"]["share"])
        errors = json.loads((ROOT / "spec" / "errors.json").read_bytes())
        cls.codes = {code["code"]: code for code in errors["codes"]}

    def test_readme_exists(self) -> None:
        self.assertTrue((CORPUS / "README.md").is_file())

    def test_only_the_files_of_the_layout(self) -> None:
        for name in present_files():
            with self.subTest(file=name):
                self.assertIn(name[: -len(".json")], FILES)
        others = [
            path.name
            for path in CORPUS.iterdir()
            if path.name != "README.md" and path.suffix != ".json"
        ]
        self.assertEqual(others, [], "the corpus holds only README.md and the case files")

    def test_files_are_registered(self) -> None:
        table = readme_table()
        self.assertEqual(sorted(table), present_files(), "the README's table of files")
        vendored = set(json.loads((ROOT / "spec" / "vendoring.json").read_bytes())["artefacts"])
        parity = json.loads((ROOT / "parity" / "corpora.json").read_bytes())["corpora"]
        listed = {entry["file"] for entry in parity}
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(table[name], len(doc["cases"]), "count in the README")
                self.assertIn(f"fixtures/conformance/audits/{name}", vendored)
                self.assertIn(f"audits/{name}", listed)

    def test_file_members(self) -> None:
        for name, doc in self.files.items():
            with self.subTest(file=name):
                self.assertEqual(set(doc), {"description", "cases"})
                self.assertIsInstance(doc["description"], str)
                self.assertIsInstance(doc["cases"], list)

    def test_case_members_and_ids(self) -> None:
        seen: set[str] = set()
        for name, case in self.cases:
            stem = name[: -len(".json")]
            with self.subTest(case=case.get("id")):
                self.assertLessEqual(set(case), CASE_MEMBERS)
                self.assertLessEqual(REQUIRED, set(case))
                self.assertRegex(case["id"], rf"^audits-{stem}-[0-9]{{3}}$")
                self.assertNotIn(case["id"], seen)
                seen.add(case["id"])
                self.assertIsInstance(case["description"], str)
                self.assertTrue(case["description"])

    def test_checks(self) -> None:
        for name, case in self.cases:
            stem = name[: -len(".json")]
            with self.subTest(case=case["id"]):
                checks = case["checks"]
                self.assertIsInstance(checks, list)
                self.assertTrue(checks)
                self.assertEqual(len(set(checks)), len(checks))
                for check in checks:
                    self.assertIn(check, self.entries)
                    if stem != "privacy":
                        self.assertTrue(check.startswith(stem + "."), check)

    def test_data(self) -> None:
        for _, case in self.cases:
            with self.subTest(case=case["id"]):
                data = case["data"]
                self.assertIsInstance(data, dict)
                self.assertTrue(data)
                lengths = {len(column) for column in data.values()}
                self.assertEqual(len(lengths), 1, "columns of equal length")
                rows = lengths.pop()
                self.assertGreaterEqual(rows, 1)
                self.assertLessEqual(rows, MAX_ROWS)
                for column_name, column in data.items():
                    self.assertTrue(column_name)
                    kinds = set()
                    for value in column:
                        if value is None:
                            continue
                        if isinstance(value, bool):
                            kinds.add("boolean")
                        elif isinstance(value, int | float):
                            kinds.add("number")
                        else:
                            self.assertIsInstance(value, str)
                            kinds.add("string")
                    self.assertTrue(kinds, f"column {column_name!r} has a value")
                    if "number" in kinds and "string" in kinds:
                        strings = {value for value in column if isinstance(value, str)}
                        self.assertLessEqual(strings, SPECIAL_VALUES)
                        kinds.discard("string")
                    self.assertEqual(len(kinds), 1, f"column {column_name!r} has one kind")

    def test_inputs(self) -> None:
        node = self.bundle.node(DECLARATION_SCHEMA)
        for _, case in self.cases:
            with self.subTest(case=case["id"]):
                self.assertIsInstance(case["formula"], str)
                self.assertTrue(case["formula"])
                if "declaration" in case:
                    issues = self.validator.validate(case["declaration"], node)
                    self.assertEqual([issue.message for issue in issues], [])
                if "family" in case:
                    self.assertIsInstance(case["family"], str)
                if "coding" in case:
                    self.assertIsInstance(case["coding"], dict)
                if "weights" in case:
                    self.assertIn(case["weights"], case["data"])
                if "sample_columns" in case:
                    self.assertIsInstance(case["sample_columns"], list)
                    for column in case["sample_columns"]:
                        self.assertIsInstance(column, str)
                tier = case.get("outcome_access", "T0")
                self.assertIn(tier, TIERS)
                self.assertEqual("reason" in case, tier != "T0")
                if "reason" in case:
                    self.assertIsInstance(case["reason"], str)
                    self.assertTrue(case["reason"])
                if "exploratory" in case:
                    self.assertIsInstance(case["exploratory"], bool)
                self.assertEqual(case.get("exploratory", False), tier == "T2")
                self.assertIn(case.get("privacy", "internal"), ("internal", "shareable"))
                for item in case.get("exact", []):
                    check, _, statistic = item.partition(":")
                    self.assertIn(check, case["checks"])
                    self.assertEqual(self.entries[check]["statistics"][statistic]["kind"], "real")

    def test_expected(self) -> None:
        for name, case in self.cases:
            with self.subTest(case=case["id"]):
                expected = case["expected"]
                self.assertIsInstance(expected, dict)
                if "issue" in expected:
                    self.assertEqual(set(expected), {"issue"})
                    self.check_issue(expected["issue"])
                    continue
                if name == "privacy.json":
                    self.assertEqual(set(expected), {"findings", "shareable"})
                else:
                    self.assertEqual(set(expected), {"findings"})
                    self.assertNotEqual(case.get("privacy"), "shareable")
                tier = TIERS.index(case.get("outcome_access", "T0"))
                for key in sorted(expected):
                    findings = expected[key]
                    self.assertIsInstance(findings, list)
                    for finding in findings:
                        self.check_finding(finding, case)
                        self.assertLessEqual(TIERS.index(finding["tier"]), tier)
                    keys = [scope_key(finding) for finding in findings]
                    self.assertEqual(keys, sorted(keys), f"order of {key}")
                    self.assertEqual(len(keys), len({repr(item) for item in keys}))
                if name == "privacy.json":
                    self.assertEqual(
                        [scope_key(f) for f in expected["findings"]],
                        [scope_key(f) for f in expected["shareable"]],
                        "the same findings in both modes",
                    )
                    for finding in expected["findings"]:
                        self.check_internal(finding)
                    for finding in expected["shareable"]:
                        self.check_shareable(finding)
                else:
                    for finding in expected["findings"]:
                        self.check_internal(finding)

    def check_issue(self, issue: Any) -> None:
        self.assertIsInstance(issue, dict)
        self.assertLessEqual(set(issue), {"code", "message", "pointer"})
        self.assertIn(issue["code"], self.codes)
        self.assertIsInstance(issue["message"], str)
        self.assertTrue(issue["message"])
        location = self.codes[issue["code"]]["location"]
        self.assertEqual("pointer" in issue, location in ("pointer", "offset_or_pointer"))

    def check_finding(self, finding: Any, case: dict) -> None:
        issues = self.validator.validate(finding, self.bundle.node(FINDING_SCHEMA))
        self.assertEqual([issue.message for issue in issues], [])
        self.assertIn(finding["check"], case["checks"])
        entry = self.entries[finding["check"]]
        self.assertEqual(finding["check_version"], entry["version"])
        self.assertEqual(finding["tier"], entry["tier"])
        status = finding["status"]
        available = status["availability"]["value"] == "available"
        parts = cr.SCOPE_ELEMENTS[entry["scope"]]
        self.assertLessEqual(set(finding["scope"]), parts)
        if (available or finding["scope"]) and entry["scope"] != "grouping_factor_or_model":
            self.assertEqual(set(finding["scope"]), parts)
        self.assertEqual("optimisation" in status, available and entry["fitted_model"])
        if not available:
            return
        self.assertIn("support", finding)
        self.assertIn(finding["message"]["id"], entry["messages"])
        for name, statistic in finding["statistics"].items():
            self.assertIn(name, entry["statistics"])
            defined = entry["statistics"][name]
            self.assertEqual(statistic["kind"], defined["kind"])
            if defined.get("count_class") in ("person", "non_person"):
                self.assertEqual(statistic["count_class"], defined["count_class"])
            if "quantile" in defined:
                self.assertIn("quantile", statistic)
                self.assertEqual(
                    Decimal(cr.format_number(statistic["quantile"]["p"])),
                    Decimal(defined["quantile"]["p"]),
                )
                # n is written exactly when the count that gives it is.
                count = finding["statistics"].get(defined["quantile"]["n"])
                if count is not None and count["value"] is not None:
                    self.assertEqual(statistic["quantile"].get("n"), count["value"])
                else:
                    self.assertNotIn("n", statistic["quantile"])
            else:
                self.assertNotIn("quantile", statistic)
            if statistic["kind"] == "category" and statistic["value"] is not None:
                self.assertIn(statistic["value"], defined["values"])

    def check_internal(self, finding: dict) -> None:
        for name, statistic in finding.get("statistics", {}).items():
            self.assertIsNotNone(statistic["value"], f"{name} is written in internal mode")
        support = finding.get("support")
        if support is not None:
            self.assertIsNotNone(support["rows"]["value"])
            self.assertIsNotNone(support["contributors"]["distinct"]["value"])

    def check_shareable(self, finding: dict) -> None:
        """The invariants E7020 to E7024 of documents.md (Shareable documents)."""
        if finding["status"]["availability"]["value"] != "available":
            return
        k = self.k
        entry = self.entries[finding["check"]]
        support = finding["support"]
        distinct = support["contributors"]["distinct"]
        fails = (
            distinct["value"] is None and distinct["availability"].get("detail") != "secondary"
        ) or (distinct["value"] is not None and distinct["value"] < k)
        fails = fails or support["contributors"]["dominated"]
        for value in (support["rows"]["value"], distinct["value"]):
            if value is not None:
                self.assertGreaterEqual(value, k, "E7020")
        statistics = finding["statistics"]
        for name, statistic in statistics.items():
            value = statistic["value"]
            if value is None:
                continue
            kind = statistic["kind"]
            person = statistic.get("count_class") == "person"
            if kind == "count" and person:
                self.assertGreaterEqual(value, k, f"E7020 at {name}")
            if fails:
                self.assertFalse(
                    kind in ("real", "reals", "labels") or (kind in ("count", "ratio") and person),
                    f"E7021 at {name}",
                )
            if "quantile" in statistic:
                quantile = statistic["quantile"]
                self.assertIn("n", quantile, f"E7022 at {name}")
                self.assertTrue(
                    quantile_written(quantile["p"], quantile["n"], k), f"E7022 at {name}"
                )
            if kind == "labels":
                for item in value:
                    self.assertRegex(item, PSEUDONYM, f"E7023 at {name}")
            if kind == "ratio":
                defined = entry["statistics"][name]
                for part in (defined["numerator"], defined["denominator"]):
                    other = statistics.get(part)
                    if other is not None:
                        self.assertIsNotNone(other["value"], f"E7024 at {name}")
                    if other is not None and other.get("count_class") == "person":
                        self.assertGreaterEqual(other["value"], k, f"E7024 at {name}")

    def test_checks_of_findings_work(self) -> None:
        # The checks above on a finding written by hand, so that they are tested
        # before the corpus has cases: a valid shareable finding of
        # keys.duplicates, then one that writes a person count below k.
        case = {"checks": ["keys.duplicates"]}
        suppressed = {
            "value": None,
            "availability": {
                "value": "not_available",
                "reason": "privacy_suppressed",
                "detail": "min_count",
            },
        }
        statistics: dict[str, Any] = {
            "key_columns": {"kind": "names", "value": ["id"]},
            "rows": {"kind": "count", "value": 20, "count_class": "person"},
        }
        for name in (
            "missing_key_rows",
            "duplicated_keys",
            "conflicting_keys",
            "identical_keys",
            "duplicate_rows",
        ):
            statistics[name] = {"kind": "count", "count_class": "person", **suppressed}
        finding = {
            "check": "keys.duplicates",
            "check_version": self.entries["keys.duplicates"]["version"],
            "tier": "T0",
            "scope": {},
            "status": {
                "availability": {"value": "available"},
                "assessability": {"value": "adequate"},
                "finding": {"value": "consistent"},
                "threshold_proximity": {"value": "clear"},
                "validation": {"value": "descriptive"},
            },
            "message": {
                "id": "unique",
                "text": "Every row has its own value of the observation key 'id'.",
            },
            "statistics": statistics,
            "support": {
                "rows": {"value": 20},
                "contributors": {"basis": "rows", "distinct": {"value": 20}, "dominated": False},
            },
        }
        self.check_finding(finding, case)
        self.check_shareable(finding)
        statistics["duplicate_rows"] = {"kind": "count", "value": 2, "count_class": "person"}
        with self.assertRaises(AssertionError):
            self.check_shareable(finding)
        finding["message"]["id"] = "absent"
        with self.assertRaises(AssertionError):
            self.check_finding(finding, case)

    def test_coverage_of_a_complete_corpus(self) -> None:
        # Once every file of the layout exists, every check of the registry is
        # the subject of a case, every message of every entry is expected and
        # every fallback is the expected text of some shareable finding, apart
        # from those that no case can reach.
        if sorted(present_files()) != sorted(f"{name}.json" for name in FILES):
            self.skipTest("the corpus is not complete")
        checks = {check for _, case in self.cases for check in case["checks"]}
        self.assertEqual(checks, set(self.entries))
        messages = {
            (finding["check"], finding["message"]["id"])
            for _, case in self.cases
            for finding in case["expected"].get("findings", [])
            if "message" in finding
        }
        texts = {
            (finding["check"], finding["message"]["id"], finding["message"]["text"])
            for _, case in self.cases
            for finding in case["expected"].get("shareable", [])
            if "message" in finding
        }
        for check, entry in self.entries.items():
            for message, defined in entry["messages"].items():
                with self.subTest(check=check, message=message):
                    if (check, message) not in UNREACHABLE_MESSAGES:
                        self.assertIn((check, message), messages)
                    if "fallback" in defined and (check, message) not in UNREACHABLE_FALLBACKS:
                        self.assertTrue(
                            any(
                                (c, m) == (check, message)
                                and fallback_matches(defined["fallback"], text)
                                for c, m, text in texts
                            ),
                            "fallback expected",
                        )


if __name__ == "__main__":
    unittest.main()
