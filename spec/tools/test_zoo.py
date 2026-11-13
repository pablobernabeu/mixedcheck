"""Tests of the files of the pathology zoo in fixtures/zoo/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

They check the stored files, not the packages, which run the fixtures in their
own tests: the directories and index.json, the schema of expected.json and
index.json, the matched fixtures and negatives, the declarations, formulas and
row counts, every expectation against the compiled registry, the order of the
findings, the signals of the fixtures against their negatives, the coverage of
the rules of registry 0.1.0 by the zoo and the audit corpus, and the limits on
sizes. They use the standard library, jsonschema and the structural validator
of compile_registry.py.
"""

from __future__ import annotations

import csv
import importlib.util
import io
import json
import math
import sys
import unicodedata
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ZOO = ROOT / "fixtures" / "zoo"
AUDITS = ROOT / "fixtures" / "conformance" / "audits"
SCHEMAS = ROOT / "spec" / "schemas"
FILES = ["data.csv", "declaration.json", "expected.json", "formula.txt"]
HAVE_JSONSCHEMA = importlib.util.find_spec("jsonschema") is not None

# The 60 directories of the zoo (fixtures/zoo/README.md), in code-point order of
# their identifiers, every one of which must be present.
ZOO_IDS = [
    *(f"Z{n:02d}{suffix}" for n in range(1, 31) for suffix in ("", "N") if (n, suffix) != (9, "N")),
    "Z31",
]
# Fixtures whose signal is empty without a planned check, with the reason.
SIGNAL_EXCEPTIONS = {
    "Z18": "its findings differ from those of its negative only in the counts of "
    "structure.label_incidence that its own labels set, since joined labels must not merge",
}
# Checks with a rule other than consistent that the zoo cannot reach, with the reason.
COVERAGE_EXCEPTIONS: dict[str, str] = {}
# The messages that the zoo leaves to the audit corpus, since no planted problem
# makes them natural, by check: the message, or '!' and the reason of a
# finding that is not available, with the finding status where the message has
# rules at two statuses, and the cases, named without their prefix 'audits-'.
CORPUS_ONLY: list[tuple[str, str, str | None, list[str]]] = [
    (
        "assignment.unit_in_random_part",
        "unit_missing_alone",
        None,
        ["assignment-012", "privacy-056"],
    ),
    ("design.collinearity", "high", None, ["design-013", "privacy-027"]),
    ("design.rank_deficiency", "nonfocal", None, ["design-003", "design-004", "design-006"]),
    ("identifiability.gram_rank", "!too_large", None, ["identifiability-012"]),
    ("identifiability.residual_confounding", "bernoulli", None, ["identifiability-028"]),
    ("identifiability.residual_confounding", "coding_dependent", None, ["identifiability-027"]),
    ("identifiability.residual_confounding", "overdispersion", None, ["identifiability-029"]),
    ("keys.duplicates", "missing_key", None, ["keys-004", "privacy-035"]),
    ("outcome.boundary_shares", "at_bounds", None, ["outcome-019", "outcome-024"]),
    ("outcome.boundary_shares", "!declaration_missing", None, ["outcome-020"]),
    ("outcome.constant_clusters", "no_levels", None, ["outcome-004", "privacy-022"]),
    ("outcome.minority_events", "events_model", None, ["outcome-010"]),
    ("outcome.minority_events", "!declaration_missing", None, ["outcome-011"]),
    ("outcome.separation", "complete", None, ["outcome-029"]),
    ("outcome.separation", "one_class", None, ["outcome-032"]),
    ("outcome.separation", "!declaration_missing", None, ["outcome-011"]),
    ("outcome.zero_shares", "zeros_model", None, ["outcome-026"]),
    ("structure.aliased_factors", "same_groups", None, ["structure-027"]),
    ("structure.cluster_sizes", "one_row_bernoulli", None, ["structure-035"]),
    ("structure.cluster_sizes", "observation_level", None, ["structure-036"]),
    ("structure.connectivity", "disconnected", None, ["structure-051", "privacy-047"]),
    ("structure.id_scope_evidence", "tied", None, ["structure-021"]),
    ("structure.id_scope_evidence", "some_change", None, ["structure-019"]),
    ("structure.label_incidence", "labels_change_parent", None, ["structure-007"]),
    ("structure.label_incidence", "crossed_split", None, ["structure-012", "structure-056"]),
]
# Rules that neither the zoo nor the audit corpus reaches, by check, message and
# finding status, with the reason and the files of the packages' unit tests
# that reach them, which must assert the status beside the message. The
# tolerance of the parameter agreement needs at least 100 rows, since
# c x 100 >= 99 x n holds below 100 rows only when c equals n, so a case of the
# audit corpus, which has at most 40 rows, cannot hold the two rules of the
# tolerance. A fixture of the zoo could, and the zoo chose not to add one, since
# the unit tests of both packages reach both rules and the planted problems of
# the zoo do not call for them (03-execution-plan.md, M2).
UNIT_TESTS_ONLY = {
    ("outcome.separation", "no_solution", None): (
        "the solver reaches an optimum of every feasible and bounded program",
        "test-checks-outcome.R",
        "test_checks_outcome.py",
    ),
    ("outcome.separation", "!too_large", None): (
        "the limit on the size of the programs needs more than 40 rows",
        "test-checks-outcome.R",
        "test_checks_outcome.py",
    ),
    ("structure.within_between", "between_slope", "detectable_inconsequential"): (
        "a term constant within its levels only with the tolerance of agreement",
        "test-checks-structure.R",
        "test_checks_structure.py",
    ),
    ("structure.connectivity", "confounded", "detectable_inconsequential"): (
        "a between-component term constant only with the tolerance of agreement",
        "test-checks-structure.R",
        "test_checks_structure.py",
    ),
}
# The scope parts of each kind of scope (registry.md, Scopes).
SCOPE_PARTS = {
    "model": [set()],
    "grouping_factor": [{"factor"}],
    "grouping_factor_or_model": [{"factor"}, set()],
    "grouping_factor_pair": [{"first", "second"}],
    "grouping_column_pair": [{"first", "second"}],
    "fixed_term": [{"term"}],
    "fixed_term_by_factor": [{"term", "factor"}],
    "random_term": [{"term", "factor"}],
    "assignment": [{"column", "unit"}],
    "column": [{"column"}],
}
# Limits on sizes (sim/zoo/README.md), measured as du measures them.
BLOCK = 4096
LIMIT_CSV = 16 * 1024
LIMIT_CSV_TOTAL = 250 * 1024
LIMIT_EXPECTED = 24 * 1024
LIMIT_DISK = int(2.2 * 1024 * 1024)
# The members of each entry of index.json, in order.
METADATA = ["id", "name", "title", "role", "matched", "tier", "rows", "domain", "deferred"]


def directories() -> dict[str, Path]:
    """The directories under fixtures/zoo/, by identifier."""
    if not ZOO.is_dir():
        return {}
    return {path.name.split("-", 1)[0]: path for path in sorted(ZOO.iterdir()) if path.is_dir()}


def text_key(text: str) -> list[int]:
    return [ord(c) for c in unicodedata.normalize("NFC", text)]


def finding_key(finding: dict[str, Any]) -> tuple[list[int], list[tuple[list[int], list[int]]]]:
    """The order of findings of documents.md (Findings)."""
    scope = finding["scope"]
    parts = [(text_key(name), text_key(scope[name])) for name in sorted(scope)]
    return text_key(finding["check"]), parts


def rounded(size: int) -> int:
    return BLOCK * math.ceil(size / BLOCK)


def status_beside(text: str, message: str, status: str) -> bool:
    """Whether a test asserts the finding status, quoted, within three lines of
    the message, quoted, as the unit tests of UNIT_TESTS_ONLY do."""
    lines = text.splitlines()
    at = [i for i, line in enumerate(lines) if f'"{message}"' in line]
    return any(
        f'"{status}"' in lines[j] for i in at for j in range(max(0, i - 3), min(len(lines), i + 4))
    )


class ZooTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.dirs = directories()
        cls.expected = {
            fixture_id: cr.load_json(path / "expected.json")
            for fixture_id, path in cls.dirs.items()
            if (path / "expected.json").is_file()
        }
        index = ZOO / "index.json"
        cls.index = cr.load_json(index) if index.is_file() else None
        registry = cr.load_json(ROOT / "spec" / "compiled" / "registry.json")
        cls.entries = {entry["id"]: entry for entry in registry["entries"]}

    # Files -------------------------------------------------------------------

    def test_the_layout_of_fixtures_zoo(self) -> None:
        self.assertEqual(sorted(self.dirs), ZOO_IDS)
        self.assertTrue((ZOO / "README.md").is_file())
        self.assertIsNotNone(self.index)
        others = [
            path.name
            for path in ZOO.iterdir()
            if path.is_file() and path.name not in {"README.md", "index.json"}
        ]
        self.assertEqual(others, [])
        for fixture_id, path in self.dirs.items():
            with self.subTest(directory=path.name):
                self.assertIn(fixture_id, ZOO_IDS)
                self.assertEqual(sorted(p.name for p in path.iterdir()), FILES)
                self.assertEqual(path.name, f"{fixture_id}-{self.expected[fixture_id]['name']}")

    def test_the_index_lists_every_directory_with_its_metadata(self) -> None:
        assert self.index is not None
        listed = [entry["id"] for entry in self.index["fixtures"]]
        self.assertEqual(listed, sorted(self.dirs, key=text_key))
        for entry in self.index["fixtures"]:
            expected = self.expected[entry["id"]]
            with self.subTest(fixture=entry["id"]):
                self.assertEqual(list(entry), METADATA)
                from_expected = {
                    **{name: expected[name] for name in ("id", "name", "title", "role")},
                    "matched": expected["matched"],
                    "tier": expected["run"]["outcome_access"],
                    "rows": expected["rows"],
                    "domain": expected["domain"],
                    "deferred": "deferred" in expected,
                }
                self.assertEqual(entry, from_expected)

    @unittest.skipUnless(HAVE_JSONSCHEMA, "jsonschema is not installed")
    def test_index_and_expected_findings_validate_against_the_schema(self) -> None:
        import jsonschema
        from referencing import Registry, Resource
        from referencing.jsonschema import DRAFT202012

        schemas = [cr.load_json(path) for path in sorted(SCHEMAS.glob("*.schema.json"))]
        for schema in schemas:
            jsonschema.Draft202012Validator.check_schema(schema)
        registry = Registry().with_resources(
            (schema["$id"], Resource.from_contents(schema, default_specification=DRAFT202012))
            for schema in schemas
        )

        # The pattern keyword of conventions.md (Schemas), over code points.
        def pattern(validator: Any, value: str, instance: Any, schema: Any) -> Any:
            if validator.is_type(instance, "string") and not cr._search(value, instance):
                yield jsonschema.ValidationError(f"{instance!r} does not match {value!r}")

        oracle = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, {"pattern": pattern}
        )({"$ref": "urn:mixedcheck:schema:zoo"}, registry=registry)
        documents = {"index.json": self.index, **self.expected}
        for name, document in documents.items():
            with self.subTest(file=name):
                self.assertEqual([error.message for error in oracle.iter_errors(document)], [])
        broken = json.loads(json.dumps(self.expected["Z01"])) if "Z01" in self.expected else None
        if broken is not None:
            broken["findings"][0]["statistics"] = {"x": {"value": 1, "absent": True}}
            del broken["samples"]
            self.assertFalse(oracle.is_valid(broken))

    def test_matched_fixtures_and_negatives(self) -> None:
        for fixture_id, expected in self.expected.items():
            with self.subTest(fixture=fixture_id):
                self.assertEqual(expected["id"], fixture_id)
                self.assertEqual(expected["role"] == "negative", fixture_id.endswith("N"))
                matched = expected["matched"]
                self.assertIn(matched, self.expected, "matched names a directory")
                negative_of = expected["negative_of"]
                self.assertEqual(negative_of, sorted(negative_of, key=text_key))
                if expected["role"] == "fixture":
                    self.assertIn(fixture_id, self.expected[matched]["negative_of"])
                else:
                    self.assertIn(matched, negative_of)
                    self.assertEqual(expected["signal"], [])
                for other in negative_of:
                    self.assertIn(other, self.expected)
                    self.assertEqual(self.expected[other]["matched"], fixture_id)

    def test_declarations_formulas_and_rows(self) -> None:
        bundle = cr.Bundle(SCHEMAS)
        validator = cr.Validator(bundle, cr.Catalogue(ROOT / "spec" / "errors.json"))
        node = bundle.node("urn:mixedcheck:schema:declaration")
        for fixture_id, path in self.dirs.items():
            with self.subTest(fixture=fixture_id):
                declaration = cr.load_json(path / "declaration.json")
                self.assertEqual(validator.validate(declaration, node), [])
                formula = (path / "formula.txt").read_bytes()
                self.assertTrue(formula.endswith(b"\n"))
                self.assertNotIn(b"\n", formula[:-1])
                self.assertNotIn(b"\r", formula)
                text = (path / "data.csv").read_bytes().decode("utf-8")
                records = list(csv.reader(io.StringIO(text, newline="")))
                fields = [field["name"] for field in declaration["table"]["fields"]]
                self.assertEqual(records[0], fields)
                self.assertEqual(len(records) - 1, self.expected[fixture_id]["rows"])

    # Expectations against the registry -----------------------------------------

    def statistic_problems(self, entry: dict[str, Any], name: str, statistic: Any) -> list[str]:
        definition = entry["statistics"].get(name)
        if definition is None:
            return [f"{name}: not a statistic of {entry['id']}"]
        kind = definition["kind"]
        by_unit = definition.get("count_class") == "by_unit"
        problems = []
        if "count_class" in statistic and not by_unit:
            problems.append(f"{name}: a count class for a class that the entry fixes")
        if by_unit and "absent" not in statistic and "count_class" not in statistic:
            problems.append(f"{name}: no count class for the class by_unit")
        if "ratio" in statistic and kind != "ratio":
            problems.append(f"{name}: a ratio for the kind {kind}")
        if kind == "ratio" and "value" in statistic:
            problems.append(f"{name}: a value for a ratio, which its counts give")
        if "interval" in statistic and kind not in ("real", "reals"):
            problems.append(f"{name}: an interval for the kind {kind}")
        if "interval" in statistic and statistic["interval"][0] > statistic["interval"][1]:
            problems.append(f"{name}: an empty interval")
        if "value" in statistic:
            value = statistic["value"]
            fits = {
                "count": isinstance(value, int) and not isinstance(value, bool) and value >= 0,
                "boolean": isinstance(value, bool),
                "category": isinstance(value, str) and value in definition.get("values", [value]),
                "names": isinstance(value, list) and all(isinstance(v, str) for v in value),
                "labels": isinstance(value, list) and all(isinstance(v, str) for v in value),
                "real": (isinstance(value, int | float) and not isinstance(value, bool))
                or value in ("NaN", "Infinity", "-Infinity"),
                "reals": isinstance(value, list)
                and all(isinstance(v, int | float) and not isinstance(v, bool) for v in value),
            }.get(kind, False)
            if not fits:
                problems.append(f"{name}: {value!r} is not a value of the kind {kind}")
        return problems

    def finding_problems(self, finding: dict[str, Any]) -> list[str]:
        entry = self.entries.get(finding["check"])
        if entry is None:
            return [f"{finding['check']}: not a check of the registry"]
        problems = []
        status = finding["status"]
        available = not (
            isinstance(status.get("availability"), dict)
            and status["availability"].get("value") == "not_available"
        )
        if not available:
            if set(finding) != {"check", "scope", "status", "why"} or set(status) != {
                "availability"
            }:
                problems.append("a finding that is not available lists more than availability")
            if finding["scope"]:
                problems.append("a finding that is not available has a scope")
            reasons = [condition["reason"] for condition in entry["availability"]]
            if status["availability"].get("reason") not in reasons:
                problems.append("availability has a reason that the entry does not give")
            return problems
        if set(finding["scope"]) not in SCOPE_PARTS[entry["scope"]]:
            problems.append(f"the scope {sorted(finding['scope'])} is not of {entry['scope']}")
        if "finding" not in status:
            problems.append("an available finding without its finding status")
        message = finding.get("message")
        if message not in entry["messages"]:
            problems.append(f"the message {message!r} is not a message of the entry")
        for name, statistic in finding.get("statistics", {}).items():
            problems += self.statistic_problems(entry, name, statistic)
        return problems

    def test_expectations_against_the_registry(self) -> None:
        for fixture_id, expected in self.expected.items():
            for i, finding in enumerate(expected.get("findings", [])):
                with self.subTest(fixture=fixture_id, finding=i):
                    self.assertEqual(self.finding_problems(finding), [])

    def test_findings_are_in_document_order_without_duplicates(self) -> None:
        for fixture_id, expected in self.expected.items():
            with self.subTest(fixture=fixture_id):
                keys = [finding_key(finding) for finding in expected.get("findings", [])]
                for a, b in zip(keys, keys[1:], strict=False):
                    self.assertLess(a, b)

    def test_samples_name_the_samples_that_the_checks_read(self) -> None:
        for fixture_id, expected in self.expected.items():
            if "issue" in expected:
                continue
            samples = expected["samples"]
            with self.subTest(fixture=fixture_id):
                self.assertEqual("analysis" in samples, expected["run"]["outcome_access"] != "T0")
                for finding in expected["findings"]:
                    if "finding" in finding["status"]:
                        sample = self.entries[finding["check"]]["sample"]
                        self.assertIn(sample, samples, finding["check"])

    # Signals ---------------------------------------------------------------------

    def matches(self, finding: dict[str, Any], signal: dict[str, Any]) -> bool:
        if (finding["check"], finding["scope"], finding.get("message")) != (
            signal["check"],
            signal["scope"],
            signal["message"],
        ):
            return False
        statistics = finding.get("statistics", {})
        return all(
            statistics.get(name, {}).get("value") == value
            for name, value in signal.get("statistics", {}).items()
        )

    def test_each_fixture_has_its_signal_and_its_negatives_lack_it(self) -> None:
        for fixture_id, expected in self.expected.items():
            if expected["role"] != "fixture":
                continue
            with self.subTest(fixture=fixture_id):
                signal = expected["signal"]
                if not signal:
                    self.assertTrue(
                        expected["planned"] or fixture_id in SIGNAL_EXCEPTIONS,
                        "an empty signal needs a planned check or an exception",
                    )
                negatives = [
                    other
                    for other, document in self.expected.items()
                    if fixture_id in document["negative_of"]
                ]
                self.assertTrue(negatives, "the fixture has a negative")
                for element in signal:
                    findings = expected.get("findings", [])
                    self.assertTrue(any(self.matches(f, element) for f in findings), element)
                    for negative in negatives:
                        found = self.expected[negative].get("findings", [])
                        self.assertFalse(any(self.matches(f, element) for f in found), negative)

    # Coverage --------------------------------------------------------------------

    def test_every_flagging_rule_is_reached_by_the_zoo(self) -> None:
        statuses: dict[str, set[str]] = {}
        for expected in self.expected.values():
            for finding in expected.get("findings", []):
                status = finding["status"].get("finding")
                if isinstance(status, dict):
                    status = status["value"]
                if status is not None:
                    statuses.setdefault(finding["check"], set()).add(status)
        for check, entry in self.entries.items():
            flagging = {rule["finding"] for rule in entry["decision"]["rules"]} - {"consistent"}
            if not flagging or check in COVERAGE_EXCEPTIONS:
                continue
            with self.subTest(check=check):
                reached = statuses.get(check, set())
                self.assertIn("consistent", reached)
                self.assertTrue(reached - {"consistent"}, "a flagged finding")

    def test_the_audit_corpus_reaches_the_messages_that_the_zoo_leaves_to_it(self) -> None:
        cases = {}
        for path in sorted(AUDITS.glob("*.json")):
            for case in cr.load_json(path)["cases"]:
                cases[case["id"].removeprefix("audits-")] = case
        for check, message, status, ids in CORPUS_ONLY:
            for case_id in ids:
                with self.subTest(check=check, message=message, case=case_id):
                    self.assertTrue(case_id in cases, f"the corpus has no case audits-{case_id}")
                    expected = cases[case_id]["expected"]
                    findings = [
                        finding
                        for key in ("findings", "shareable")
                        for finding in expected.get(key, [])
                        if finding["check"] == check
                    ]
                    self.assertTrue(any(self.reaches(f, message, status) for f in findings))
        for (check, message, status), (_, r_tests, python_tests) in UNIT_TESTS_ONLY.items():
            with self.subTest(check=check, message=message, status=status):
                self.assertIn(message.lstrip("!"), self.messages_and_reasons(check))
                if status is not None:
                    rules = self.entries[check]["decision"]["rules"]
                    self.assertIn((status, message), [(r["finding"], r["message"]) for r in rules])
                for path in (
                    ROOT / "r" / "tests" / "testthat" / r_tests,
                    ROOT / "python" / "tests" / python_tests,
                ):
                    text = path.read_text(encoding="utf-8")
                    self.assertIn(message.lstrip("!"), text, path.name)
                    if status is not None:
                        self.assertTrue(
                            status_beside(text, message, status),
                            f"{path.name} asserts no status {status} beside {message}",
                        )

    def reaches(self, finding: dict[str, Any], message: str, status: str | None) -> bool:
        availability = finding["status"]["availability"]
        if message.startswith("!"):
            return bool(
                availability["value"] == "not_available"
                and availability.get("reason") == message[1:]
            )
        return bool(
            finding.get("message", {}).get("id") == message
            and (status is None or finding["status"]["finding"]["value"] == status)
        )

    def messages_and_reasons(self, check: str) -> set[str]:
        entry = self.entries[check]
        return set(entry["messages"]) | {condition["reason"] for condition in entry["availability"]}

    # Sizes and vendoring -----------------------------------------------------------

    def test_the_limits_on_sizes(self) -> None:
        disk = BLOCK * (len(self.dirs) + 1)
        csv_total = 0
        for path in sorted(ZOO.rglob("*")):
            if not path.is_file():
                continue
            size = path.stat().st_size
            disk += rounded(size)
            with self.subTest(file=str(path.relative_to(ZOO))):
                if path.name == "data.csv":
                    csv_total += size
                    self.assertLessEqual(size, LIMIT_CSV)
                if path.name == "expected.json":
                    self.assertLessEqual(size, LIMIT_EXPECTED)
        self.assertLessEqual(csv_total, LIMIT_CSV_TOTAL)
        self.assertLessEqual(disk, LIMIT_DISK)

    def test_spec_vendoring_lists_the_zoo(self) -> None:
        listed = json.loads((ROOT / "spec" / "vendoring.json").read_bytes())["artefacts"]
        self.assertIn("fixtures/zoo/", listed)


if __name__ == "__main__":
    unittest.main()
