"""Tests of compile_registry.py, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

They need PyYAML, as the compiler does, and are skipped without it. Where the
jsonschema package is installed, it serves as an oracle for the structural
validator, and those tests are skipped without it. Expected bytes, hashes and
numbers come from RFC 8785, docs/spec/conventions.md and docs/spec/errors.md,
never from the compiler itself.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

try:
    import yaml  # noqa: F401
except ImportError:  # pragma: no cover
    HAVE_YAML = False
else:
    HAVE_YAML = True

try:
    import jsonschema
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012
except ImportError:  # pragma: no cover
    HAVE_ORACLE = False
else:
    HAVE_ORACLE = True

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve().with_name("compile_registry.py")
REGISTRY_DOC = ROOT / "docs" / "spec" / "registry.md"
ENTRY = "spec/registry/checks/structure.id_scope_evidence.yaml"
needs_yaml = unittest.skipUnless(HAVE_YAML, "PyYAML is not installed")


def _double(bits: str) -> float:
    return struct.unpack(">d", bytes.fromhex(bits))[0]


class NumberTestCase(unittest.TestCase):
    """ECMAScript number formatting, from the table in conventions.md."""

    CASES = [
        ("0000000000000000", "0"),
        ("8000000000000000", "0"),
        ("0000000000000001", "5e-324"),
        ("7FEFFFFFFFFFFFFF", "1.7976931348623157e+308"),
        ("4340000000000000", "9007199254740992"),
        ("4430000000000000", "295147905179352830000"),
        ("444B1AE4D6E2EF50", "1e+21"),
        ("444B1AE4D6E2EF4F", "999999999999999900000"),
        ("44B52D02C7E14AF6", "1e+23"),
        ("44B52D02C7E14AF5", "9.999999999999997e+22"),
        ("3EB0C6F7A0B5ED8D", "0.000001"),
        ("3EB0C6F7A0B5ED8C", "9.999999999999997e-7"),
        ("41B3DE4355555555", "333333333.3333333"),
        ("BECBF647612F3696", "-0.0000033333333333333333"),
        ("43143FF3C1CB0959", "1424953923781206.2"),
        ("3E7AD7F29ABCAF48", "1e-7"),
        ("3FD3333333333334", "0.30000000000000004"),
        ("0060000000000000", "7.120236347223045e-307"),
    ]

    def test_conventions_table(self) -> None:
        for bits, expected in self.CASES:
            with self.subTest(bits=bits):
                self.assertEqual(cr.format_number(_double(bits)), expected)

    def test_layout_of_short_values(self) -> None:
        for value, expected in [(100.0, "100"), (1e16, "10000000000000000"), (-1.5, "-1.5")]:
            with self.subTest(value=value):
                self.assertEqual(cr.format_number(value), expected)
        self.assertEqual(cr.format_number(-9007199254740991), "-9007199254740991")

    def test_refuses_non_finite_values_and_booleans(self) -> None:
        for value in (float("nan"), float("inf"), True):
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                cr.format_number(value)


class CanonicalTestCase(unittest.TestCase):
    def test_worked_example_of_conventions(self) -> None:
        text = (
            '{"title": "caf\\u00e9 \\"study\\"", '
            '"n": [1.0, 1e2, 0.000001, 1E-7, 4.50, -0, 25e-1], '
            '"a": {"z": true, "b": false, "é": "\\u00e9"}, '
            '"tab": "a\\tb\\u001f"}'
        )
        data = cr.canonical_bytes(json.loads(text))
        expected = (
            '{"a":{"b":false,"z":true,"é":"é"},"n":[1,100,0.000001,1e-7,4.5,0,2.5],'
            '"tab":"a\\tb\\u001f","title":"café \\"study\\""}'
        ).encode()
        self.assertEqual(data, expected)
        self.assertEqual(len(data), 117)
        self.assertEqual(
            hashlib.sha256(data).hexdigest(),
            "288afb1eec38acd97fc29eb68a97d9200dd6e77da5ee06d7586945b51372b80d",
        )

    def test_rfc8785_key_sorting(self) -> None:
        # RFC 8785, section 3.2.3.
        value = {
            "€": "Euro Sign",
            "\r": "Carriage Return",
            "דּ": "Hebrew Letter Dalet With Dagesh",
            "1": "One",
            "\U0001f600": "Emoji: Grinning Face",
            "\u0080": "Control",
            "ö": "Latin Small Letter O With Diaeresis",
        }
        order = [item for item in json.loads(cr.canonical_bytes(value)).values()]
        self.assertEqual(
            order,
            [
                "Carriage Return",
                "One",
                "Control",
                "Latin Small Letter O With Diaeresis",
                "Euro Sign",
                "Emoji: Grinning Face",
                "Hebrew Letter Dalet With Dagesh",
            ],
        )

    def test_string_escapes(self) -> None:
        value = '"\\/\b\f\n\r\t\x00\x1f\x7f \U0001f600'
        self.assertEqual(
            cr.canonical_bytes(value),
            '"\\"\\\\/\\b\\f\\n\\r\\t\\u0000\\u001f\x7f \U0001f600"'.encode(),
        )


class CatalogueTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.catalogue = cr.Catalogue(ROOT / "spec" / "errors.json")

    def test_rendering_follows_errors_md(self) -> None:
        issue = self.catalogue.issue("json_duplicate_key", offset=45, key="go\tal")
        self.assertEqual(issue.message, "Duplicate key 'go\\u0009al' at byte 45.")
        issue = self.catalogue.issue(
            "schema_enum", pointer="/goal", allowed=["confirmatory", "exploratory", "prediction"]
        )
        self.assertEqual(
            issue.message,
            "The value at /goal must be 'confirmatory', 'exploratory' or 'prediction'.",
        )
        issue = self.catalogue.issue("schema_type", pointer="", expected=["object"], found="array")
        self.assertEqual(issue.message, "Expected object at (root), found array.")

    def test_text_is_truncated_after_escaping(self) -> None:
        issue = self.catalogue.issue("registry_unknown_check", id="a" * 70)
        self.assertEqual(
            issue.message, "No registry entry has the identifier '" + "a" * 57 + "...'."
        )


@needs_yaml
class YamlTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.catalogue = cr.Catalogue(ROOT / "spec" / "errors.json")
        self.directory = Path(tempfile.mkdtemp(prefix="registry-yaml-"))
        self.addCleanup(shutil.rmtree, self.directory)

    def read(self, content: bytes) -> tuple[Any, cr.Issue | None]:
        path = self.directory / "source.yaml"
        path.write_bytes(content)
        text, problem = cr.read_bytes(path, self.catalogue)
        if problem is not None:
            return None, problem
        return cr.parse_yaml(text or "", self.catalogue)

    def code(self, content: bytes) -> str | None:
        _, problem = self.read(content)
        return None if problem is None else problem.code

    def test_every_scalar_is_a_string(self) -> None:
        value, problem = self.read(
            b"a: yes\nb: NO\nc: ~\nd:\ne: 0x1F\nf: 08\ng: 2026.10\nh: '1'\ni: 1e3\nj: [1, true]\n"
        )
        self.assertIsNone(problem)
        self.assertEqual(
            value,
            {
                "a": "yes",
                "b": "NO",
                "c": "~",
                "d": "",
                "e": "0x1F",
                "f": "08",
                "g": "2026.10",
                "h": "1",
                "i": "1e3",
                "j": ["1", "true"],
            },
        )

    def test_rejections(self) -> None:
        # Each text with its code and the location of the issue: a byte
        # offset, a JSON Pointer or None.
        cases: dict[bytes, tuple[str, int | str | None]] = {
            b"\xef\xbb\xbfa: 1\n": ("E1003", None),
            b"a: \xff\n": ("E1201", 3),
            b"a: [1\n": ("E3002", None),
            b"": ("E3010", None),
            b"a: 1\n---\nb: 2\n": ("E3003", 5),
            b"a: &x 1\nb: 2\n": ("E3004", 3),
            b"a: *x\n": ("E3004", 3),
            b"\xc3\xa9: &x 1\n": ("E3004", 4),
            b"a: !!str 1\n": ("E3005", 3),
            b"? [a, b]\n: 1\n": ("E3006", ""),
            b"a:\n  ? [x]\n  : 1\n": ("E3006", "/a"),
            b"a: 1\nb: 2\na: 3\n": ("E3007", None),
            b"%YAML 1.1\n---\na: 1\n": ("E3005", 0),
            b"a: 1\n...\nb: 2\n": ("E3003", 9),
            b"# only a comment\n": ("E3010", None),
            b"d:\n  <<: {x: 1}\n": ("E3009", 5),
            b"a: {b: &x 1}\n": ("E3004", 7),
            b'a: {"b":&x 1}\n': ("E3004", 8),
            b'a: "x\\0y"\n': ("E1202", 5),
            b'"": 1\n': ("E1109", "/"),
            b"a: 1\n? [x]\n: 2\n? [x]\n: 3\n": ("E3007", None),
        }
        for content, (code, location) in cases.items():
            with self.subTest(content=content):
                _, problem = self.read(content)
                assert problem is not None
                found = problem.offset if problem.offset is not None else problem.pointer
                self.assertEqual((problem.code, found), (code, location))

    def test_prescan_skips_scalars_and_comments(self) -> None:
        cases = {
            b"a: |\n  &x *y !z\nb: 1\n": {"a": "&x *y !z\n", "b": "1"},
            b"a: Tom & Jerry # &x\n": {"a": "Tom & Jerry"},
            b"a: 'it''s &x'\n": {"a": "it's &x"},
            b"a: b\t\n": {"a": "b"},
            b"a: [b,\tc]\n": {"a": ["b", "c"]},
            b"---\na: 1\n...\n": {"a": "1"},
        }
        for content, expected in cases.items():
            with self.subTest(content=content):
                self.assertEqual(self.read(content), (expected, None))

    def test_duplicates_are_found_when_a_mapping_ends(self) -> None:
        # libyaml stops at the unclosed bracket before the mapping that holds
        # 'x' twice ends, so the syntax error is reported, as R's yaml does.
        self.assertEqual(self.code(b"x: 1\nx: 2\ny: [a\n"), "E3002")
        self.assertEqual(self.code(b"- a\n- b: 1\n  b: 2\n- c: [\n"), "E3007")

    def test_nul_offset(self) -> None:
        _, problem = self.read(b'k: 1\na: "x\\x00"\n')
        assert problem is not None
        self.assertEqual((problem.code, problem.offset), ("E1202", 10))

    def test_invalid_utf8_offset(self) -> None:
        _, problem = self.read(b"ab: \xe2\x82\n")
        assert problem is not None
        self.assertEqual((problem.code, problem.offset), ("E1201", 4))
        self.assertEqual(problem.message, "Invalid UTF-8 at byte 4.")

    def test_missing_file(self) -> None:
        _, problem = cr.read_bytes(self.directory / "absent.yaml", self.catalogue)
        assert problem is not None
        self.assertEqual(problem.code, "E1001")


@needs_yaml
class CoercionTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.compiler = cr.Compiler(ROOT)
        self.node = self.compiler.bundle.node(cr.ENTRY_SCHEMA)
        text = (ROOT / ENTRY).read_text(encoding="utf-8")
        self.raw, problem = cr.parse_yaml(text, self.compiler.catalogue)
        self.assertIsNone(problem)

    def coerce(self, value: Any) -> Any:
        return self.compiler.coercer.coerce(value, [(self.node, False)])

    def refusal(self, value: Any) -> cr.Issue:
        with self.assertRaises(cr._Refused) as caught:
            self.coerce(value)
        return caught.exception.issue

    def test_types_come_from_the_schema(self) -> None:
        entry = self.coerce(self.raw)
        self.assertEqual(entry["version"], 1)
        self.assertIs(entry["fitted_model"], False)
        # A decimal string stays a string, and a threshold value is one.
        self.assertEqual(entry["thresholds"]["any_change"]["value"], "1")
        self.assertEqual(entry["thresholds"]["most_change"]["value"], "0.5")
        self.assertEqual(entry["statistics"]["changing_share"]["kind"], "ratio")

    def test_coercion_failures(self) -> None:
        raw = copy.deepcopy(self.raw)
        raw["fitted_model"] = "no"
        issue = self.refusal(raw)
        self.assertEqual(issue.code, "E3008")
        self.assertEqual(
            issue.message, "The value 'no' at /fitted_model cannot be read as a boolean."
        )
        raw = copy.deepcopy(self.raw)
        raw["version"] = "1.0"
        issue = self.refusal(raw)
        self.assertEqual(issue.message, "The value '1.0' at /version cannot be read as an integer.")
        raw["version"] = "9007199254740992"
        self.assertEqual(self.refusal(raw).code, "E1102")

    def test_profile(self) -> None:
        entry = self.coerce(self.raw)
        self.assertIsNone(cr.profile_issue(entry, self.compiler.catalogue))
        entry["title"] = "café"
        issue = cr.profile_issue(entry, self.compiler.catalogue)
        assert issue is not None
        self.assertEqual((issue.code, issue.pointer), ("E1203", "/title"))
        entry["title"] = "x"
        entry["statistics"]["\U0001f600"] = {}
        issue = cr.profile_issue(entry, self.compiler.catalogue)
        assert issue is not None
        self.assertEqual(issue.code, "E1108")


@needs_yaml
class ValidatorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.compiler = cr.Compiler(ROOT)
        self.node = self.compiler.bundle.node(cr.ENTRY_SCHEMA)
        text = (ROOT / ENTRY).read_text(encoding="utf-8")
        raw, _ = cr.parse_yaml(text, self.compiler.catalogue)
        self.entry = self.compiler.coercer.coerce(raw, [(self.node, False)])

    def issues(self, entry: dict) -> list[tuple[str, str | None, str]]:
        found = self.compiler.validator.validate(entry, self.node)
        return [(issue.code, issue.pointer, issue.message) for issue in found]

    def test_valid_entry(self) -> None:
        self.assertEqual(self.issues(self.entry), [])

    def test_structural_issues_and_order(self) -> None:
        entry = copy.deepcopy(self.entry)
        entry["version"] = "1"
        entry["tier"] = "T9"
        entry["extra"] = True
        del entry["title"]
        entry["availability"] = [{"reason": "too_large", "condition": "x", "pointer": "/a"}]
        entry["statistics"]["changing_share"].pop("count_class")
        self.assertEqual(
            self.issues(entry),
            [
                ("E1402", "", "The object at (root) lacks the required member 'title'."),
                ("E1403", "", "Unknown key 'extra' in the object at (root)."),
                (
                    "E1402",
                    "/availability/0",
                    "The object at /availability/0 lacks the required member 'parameter'.",
                ),
                (
                    "E1404",
                    "/availability/0",
                    "The member 'pointer' is not allowed in the object at /availability/0.",
                ),
                (
                    "E1402",
                    "/statistics/changing_share",
                    "The object at /statistics/changing_share lacks the required member "
                    "'count_class'.",
                ),
                ("E1405", "/tier", "The value at /tier must be 'T0', 'T1' or 'T2'."),
                ("E1401", "/version", "Expected integer at /version, found string."),
            ],
        )

    def test_a_type_failure_hides_everything_below(self) -> None:
        entry = copy.deepcopy(self.entry)
        entry["statistics"] = ["not", "an", "object"]
        self.assertEqual(
            self.issues(entry),
            [("E1401", "/statistics", "Expected object at /statistics, found array.")],
        )

    def test_pattern_names_the_form(self) -> None:
        entry = copy.deepcopy(self.entry)
        entry["catalogue"] = ["L9-01"]
        entry["statistics"]["Bad"] = entry["statistics"].pop("attributes")
        self.assertEqual(
            self.issues(entry),
            [
                (
                    "E1406",
                    "/catalogue/0",
                    "The string at /catalogue/0 is not a valid catalogue item.",
                ),
                (
                    "E1418",
                    "/statistics",
                    "The key 'Bad' in the object at /statistics is not a valid local name.",
                ),
            ],
        )

    @unittest.skipUnless(HAVE_ORACLE, "jsonschema is not installed")
    def test_agrees_with_the_jsonschema_oracle(self) -> None:
        schemas = [
            cr.load_json(path) for path in sorted((ROOT / "spec" / "schemas").glob("*.schema.json"))
        ]
        registry = Registry().with_resources(
            (schema["$id"], Resource.from_contents(schema, default_specification=DRAFT202012))
            for schema in schemas
        )

        def pattern(validator: Any, value: str, instance: Any, schema: Any) -> Any:
            if validator.is_type(instance, "string"):
                if not cr._search(value, instance):
                    yield jsonschema.ValidationError(f"{instance!r} does not match {value!r}")

        oracle_class = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, {"pattern": pattern}
        )
        oracle = oracle_class({"$ref": cr.ENTRY_SCHEMA}, registry=registry)
        variants = [self.entry]
        mutations = [
            ("tier", "T3"),
            ("version", 0),
            ("reads", []),
            ("scope", "row"),
            ("statistics", {}),
            ("links", {"requires": []}),
            ("catalogue", ["L1-1"]),
        ]
        for key, value in mutations:
            variant = copy.deepcopy(self.entry)
            variant[key] = value
            variants.append(variant)
        for variant in variants:
            with self.subTest(variant=variant.get("tier"), scope=variant.get("scope")):
                self.assertEqual(
                    oracle.is_valid(variant),
                    not self.compiler.validator.validate(variant, self.node),
                )


@needs_yaml
class RulesTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.compiler = cr.Compiler(ROOT)
        node = self.compiler.bundle.node(cr.ENTRY_SCHEMA)
        text = (ROOT / ENTRY).read_text(encoding="utf-8")
        raw, _ = cr.parse_yaml(text, self.compiler.catalogue)
        self.entry = self.compiler.coercer.coerce(raw, [(node, False)])

    def codes(self, entry: dict, file_id: str | None = None) -> list[tuple[str, str | None]]:
        found = cr.finish(
            cr.entry_issues(entry, self.compiler.catalogue, file_id=file_id),
            self.compiler.catalogue,
        )
        return [(issue.code, issue.pointer) for issue in found]

    def test_valid_entry(self) -> None:
        self.assertEqual(self.codes(self.entry, self.entry["id"]), [])

    def test_each_rule(self) -> None:
        entry = copy.deepcopy(self.entry)
        message = entry["messages"]["some_change"]
        message["template"] += " {nope} }"
        message["args"]["changing"]["digits"] = 1
        message["args"]["extra"] = {"source": "scope", "name": "factor"}
        entry["messages"]["no_change"]["args"]["shared"]["name"] = "bounds"
        entry["statistics"]["bounds"] = {"kind": "reals", "definition": "x"}
        entry["decision"]["rules"][1]["thresholds"] = ["absent"]
        entry["decision"]["otherwise"]["message"] = "absent"
        entry["reads"].append("outcome")
        entry["remedies"].append(copy.deepcopy(entry["remedies"][0]))
        thresholds = entry["thresholds"]
        thresholds["any_change"]["value"] = "1.5"
        thresholds["any_change"]["proximity"] = {"relative": "0", "absolute": "0"}
        thresholds["most_change"]["value"] = "0.12345"
        thresholds["most_change"]["validation"] = {
            "value": "validated",
            "study": "V1",
            "language": "R",
            "engine": "lme4",
            "version_range": ">=2.1-0",
        }
        thresholds["most_change"]["sources"].append(
            {"kind": "literature", "citation": "A paper.", "full_text_read": False}
        )
        thresholds["other"] = copy.deepcopy(thresholds["any_change"])
        thresholds["other"]["statistic"] = "attributes"
        thresholds["unknown"] = copy.deepcopy(thresholds["any_change"])
        thresholds["unknown"]["statistic"] = "absent"
        self.assertEqual(
            self.codes(entry, "other.name"),
            [
                ("E4004", "/decision/otherwise/message"),
                ("E4004", "/decision/rules/1/thresholds/0"),
                ("E4002", "/id"),
                ("E4015", "/messages/no_change/args/shared/name"),
                ("E4024", "/messages/no_change/args/shared/noun"),
                ("E4014", "/messages/some_change/args/changing"),
                ("E4008", "/messages/some_change/args/extra"),
                ("E4004", "/messages/some_change/args/extra/name"),
                ("E4007", "/messages/some_change/template"),
                ("E4009", "/messages/some_change/template"),
                ("E4016", "/reads"),
                ("E4006", "/remedies/2/id"),
                ("E4013", "/thresholds/any_change"),
                ("E4012", "/thresholds/any_change/value"),
                ("E4010", "/thresholds/most_change/validation"),
                ("E4012", "/thresholds/most_change/value"),
                ("E4011", "/thresholds/other"),
                ("E4004", "/thresholds/unknown/statistic"),
            ],
        )

    def test_references_of_m2(self) -> None:
        # The members that M2 added: the statistics that a rule reads, the
        # resolution of by_unit counts, quantiles, suppression with other
        # statistics and parts of a total (E4004 and E4024).
        entry = copy.deepcopy(self.entry)
        statistics = entry["statistics"]
        entry["decision"]["rules"][0]["statistics"] = ["attributes", "absent"]
        statistics["shared_labels"]["resolved_by"] = [
            {"source": "scope", "name": "factor"},
            {"source": "statistic", "name": "changing_labels"},
        ]
        statistics["changing_labels"]["resolved_by"] = [{"source": "statistic", "name": "absent"}]
        statistics["changing_labels"]["quantile"] = {"p": "0.5", "n": "changing_attribute"}
        statistics["shared_labels"]["quantile"] = {"p": "0.5", "n": "absent"}
        statistics["changing_share"]["suppress_with"] = ["absent"]
        statistics["changing_labels"]["part_of"] = "absent"
        statistics["shared_labels"]["part_of"] = "changing_attribute"
        self.assertEqual(
            self.codes(entry),
            [
                ("E4004", "/decision/rules/0/statistics/1"),
                ("E4004", "/statistics/changing_labels/part_of"),
                ("E4024", "/statistics/changing_labels/quantile/n"),
                ("E4004", "/statistics/changing_labels/resolved_by/0/name"),
                ("E4004", "/statistics/changing_share/suppress_with/0"),
                ("E4024", "/statistics/shared_labels/part_of"),
                ("E4004", "/statistics/shared_labels/quantile/n"),
                ("E4004", "/statistics/shared_labels/resolved_by/0/name"),
                ("E4024", "/statistics/shared_labels/resolved_by/1/name"),
            ],
        )

    def test_fallback_templates(self) -> None:
        # A message that renders a statistic that can be suppressed needs a
        # fallback, which renders none of them (E4023), and a fallback names
        # only arguments of its message (E4007, E4009).
        entry = copy.deepcopy(self.entry)
        messages = entry["messages"]
        del messages["some_change"]["fallback"]
        messages["no_change"]["fallback"] = "None of the {shared} labels changes. {nope} }"
        messages["no_attribute"]["fallback"] = "No column of {labels_column} is constant."
        self.assertEqual(
            self.codes(entry),
            [
                ("E4023", "/messages/no_change"),
                ("E4007", "/messages/no_change/fallback"),
                ("E4009", "/messages/no_change/fallback"),
                ("E4023", "/messages/some_change"),
            ],
        )

    def test_agreement_is_shared(self) -> None:
        first = copy.deepcopy(self.entry)
        second = copy.deepcopy(self.entry)
        second["id"] = "structure.other"
        second["parameters"]["agreement"]["value"] = "0.95"
        for entry in (first, second):
            entry["links"] = {"requires": [], "explained_by": []}
        found = cr.graph_issues([("/a", first), ("/b", second)], self.compiler.catalogue)
        self.assertEqual(
            [[(issue.code, issue.pointer, issue.message) for issue in issues] for issues in found],
            [
                [],
                [
                    (
                        "E4022",
                        "/b/parameters/agreement/value",
                        "The parameter at /b/parameters/agreement/value must have the value "
                        "'0.99' that other entries give the parameter of the same name.",
                    )
                ],
            ],
        )

    def test_tier_and_reads(self) -> None:
        cases = [
            ("T0", ["formula"], True),
            ("T0", ["formula", "outcome"], False),
            ("T1", ["grouping_factors", "outcome"], True),
            ("T1", ["outcome", "predictors"], False),
            ("T1", ["grouping_factors"], False),
            ("T2", ["outcome", "predictors"], True),
            ("T2", ["predictors"], False),
        ]
        for tier, reads, valid in cases:
            with self.subTest(tier=tier, reads=reads):
                entry = copy.deepcopy(self.entry)
                entry["tier"], entry["reads"] = tier, reads
                entry["sample"] = "design" if tier == "T0" else "analysis"
                codes = [code for code, _ in self.codes(entry)]
                self.assertEqual("E4016" not in codes, valid)

    def test_tier_and_sample(self) -> None:
        cases = [
            ("T0", "table", True),
            ("T0", "design", True),
            ("T0", "analysis", False),
            ("T1", "analysis", True),
            ("T1", "design", False),
            ("T2", "table", False),
        ]
        for tier, sample, valid in cases:
            with self.subTest(tier=tier, sample=sample):
                entry = copy.deepcopy(self.entry)
                entry["tier"], entry["sample"] = tier, sample
                entry["reads"] = ["formula"] if tier == "T0" else ["outcome", "predictors"]
                if tier == "T1":
                    entry["reads"] = ["grouping_factors", "outcome"]
                found = [pointer for code, pointer in self.codes(entry) if code == "E4016"]
                self.assertEqual("/sample" not in found, valid)

    def test_consequential_needs_a_validated_threshold(self) -> None:
        entry = copy.deepcopy(self.entry)
        rule = next(rule for rule in entry["decision"]["rules"] if rule["thresholds"])
        rule["finding"] = "consequential"
        index = entry["decision"]["rules"].index(rule)
        self.assertEqual(self.codes(entry), [("E4020", f"/decision/rules/{index}/finding")])

    def test_ratio_counts(self) -> None:
        entry = copy.deepcopy(self.entry)
        ratio = entry["statistics"]["changing_share"]
        ratio["numerator"] = "absent"
        self.assertEqual(self.codes(entry), [("E4004", "/statistics/changing_share/numerator")])
        ratio["numerator"] = "changing_attribute"
        self.assertEqual(self.codes(entry), [("E4021", "/statistics/changing_share")])
        ratio["numerator"] = "changing_labels"
        ratio["count_class"] = "person"
        self.assertEqual(self.codes(entry), [("E4021", "/statistics/changing_share")])

    def test_graph_rules(self) -> None:
        first = copy.deepcopy(self.entry)
        second = copy.deepcopy(self.entry)
        second["id"] = "structure.other"
        first["links"] = {"requires": ["structure.other", "structure.absent"], "explained_by": []}
        second["links"] = {"requires": [], "explained_by": [first["id"]]}
        duplicate = copy.deepcopy(second)
        duplicate["links"] = {"requires": [], "explained_by": []}
        found = cr.graph_issues(
            [("/a", first), ("/b", second), ("/c", duplicate)], self.compiler.catalogue
        )
        self.assertEqual(
            [[(issue.code, issue.pointer) for issue in issues] for issues in found],
            [
                [("E4005", "/a/links/requires/0"), ("E4004", "/a/links/requires/1")],
                [("E4005", "/b/links/explained_by/0")],
                [("E4003", "/c/id")],
            ],
        )
        self.assertEqual(
            found[1][0].message,
            "The link to 'structure.id_scope_evidence' at /b/links/explained_by/0 closes a "
            "cycle of links between checks.",
        )

    def test_self_link_is_a_cycle(self) -> None:
        entry = copy.deepcopy(self.entry)
        entry["links"]["requires"] = [entry["id"]]
        found = cr.graph_issues([("", entry)], self.compiler.catalogue)
        self.assertEqual([issue.code for issue in found[0]], ["E4005"])


@needs_yaml
class CompiledRegistryTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiler = cr.Compiler(ROOT)
        cls.result = cls.compiler.compile()
        cls.data = (ROOT / cr.OUTPUT).read_bytes()
        cls.document = json.loads(cls.data)

    def test_sources_compile(self) -> None:
        self.assertEqual(self.result.problems, {})

    def test_compiled_registry_is_up_to_date(self) -> None:
        self.assertEqual(
            self.result.output,
            self.data,
            "spec/compiled/registry.json is stale. Run python3 spec/tools/compile_registry.py.",
        )

    def test_compiled_registry_is_canonical_and_valid(self) -> None:
        catalogue = self.compiler.catalogue
        self.assertEqual(cr.compiled_registry_issues(self.data, catalogue), [])
        self.assertFalse(self.data.endswith(b"\n"))
        self.assertIsNone(cr.profile_issue(self.document, catalogue))
        node = self.compiler.bundle.node(cr.REGISTRY_SCHEMA)
        self.assertEqual(self.compiler.validator.validate(self.document, node), [])
        self.assertEqual(cr.registry_issues(self.document, catalogue), [])
        indented = (json.dumps(self.document, indent=2) + "\n").encode()
        self.assertEqual(
            [issue.code for issue in cr.compiled_registry_issues(indented, catalogue)], ["E4018"]
        )

    def test_entry_order(self) -> None:
        document = copy.deepcopy(self.document)
        entries = document["entries"]
        entries[0], entries[1] = entries[1], entries[0]
        found = cr.registry_issues(document, self.compiler.catalogue)
        self.assertEqual(
            [(issue.code, issue.pointer) for issue in found], [("E4017", "/entries/1")]
        )

    def test_version_and_privacy(self) -> None:
        versions = json.loads((ROOT / "spec" / "versions.json").read_bytes())
        self.assertEqual(self.document["registry_version"], versions["registry"])
        privacy = self.document["privacy"]
        self.assertEqual(privacy["min_count"], 10)
        self.assertEqual(privacy["dominance"], {"contributors": 2, "share": "0.9"})
        self.assertEqual(privacy["rounding_base"], 5)

    def test_tiers_and_counts(self) -> None:
        tiers = {entry["id"]: entry["tier"] for entry in self.document["entries"]}
        self.assertEqual(tiers["outcome.separation"], "T2")
        self.assertEqual(
            sorted(key for key, tier in tiers.items() if tier == "T1"),
            [
                "outcome.boundary_shares",
                "outcome.constant_clusters",
                "outcome.minority_events",
                "outcome.zero_shares",
            ],
        )
        for entry in self.document["entries"]:
            for name, statistic in entry["statistics"].items():
                with self.subTest(check=entry["id"], statistic=name):
                    if statistic["kind"] in ("count", "ratio"):
                        self.assertIn(statistic["count_class"], ("person", "non_person", "by_unit"))

    def test_literature_thresholds_are_descriptive(self) -> None:
        # Until the local session reads the sources in full (03-execution-plan.md).
        for entry in self.document["entries"]:
            for name, threshold in entry["thresholds"].items():
                with self.subTest(check=entry["id"], threshold=name):
                    self.assertEqual(threshold["validation"], {"value": "descriptive"})

    def test_every_entry_is_documented(self) -> None:
        text = REGISTRY_DOC.read_text(encoding="utf-8")
        rows = set(re.findall(r"^\| `([a-z0-9_.]+)` \| (T[012]) \|", text, flags=re.MULTILINE))
        expected = {(entry["id"], entry["tier"]) for entry in self.document["entries"]}
        self.assertEqual(rows, expected)

    def test_declaration_pointers_exist(self) -> None:
        # Each pointer of an availability rule names a member that the
        # declaration schema itself defines, {outcome} standing for a member of
        # an object keyed by column name. Members that only the profile
        # definitions of defs.schema.json admit do not count.
        declaration = "urn:mixedcheck:schema:declaration"
        bundle = self.compiler.bundle
        if declaration not in bundle.schemas:
            self.skipTest("spec/schemas/declaration.schema.json is not present")

        def step(nodes: list, token: str) -> list:
            found = []
            for (schema, base), _ in bundle._closure(nodes):
                if not isinstance(schema, dict) or base != declaration:
                    continue
                if token == "{outcome}":
                    sub = schema.get("additionalProperties")
                else:
                    sub = schema.get("properties", {}).get(token)
                if isinstance(sub, dict):
                    found.append(((sub, base), False))
            return found

        for entry in self.document["entries"]:
            for rule in entry["availability"]:
                if "pointer" not in rule:
                    continue
                with self.subTest(check=entry["id"], pointer=rule["pointer"]):
                    nodes = [(bundle.node(declaration), False)]
                    for token in rule["pointer"].split("/")[1:]:
                        nodes = step(nodes, token)
                        self.assertTrue(nodes, f"no member {token!r} in the declaration schema")

    @unittest.skipUnless(HAVE_ORACLE, "jsonschema is not installed")
    def test_oracle_accepts_the_compiled_registry(self) -> None:
        schemas = [
            cr.load_json(path) for path in sorted((ROOT / "spec" / "schemas").glob("*.schema.json"))
        ]
        for schema in schemas:
            jsonschema.Draft202012Validator.check_schema(schema)
        registry = Registry().with_resources(
            (schema["$id"], Resource.from_contents(schema, default_specification=DRAFT202012))
            for schema in schemas
        )
        oracle = jsonschema.Draft202012Validator({"$ref": cr.REGISTRY_SCHEMA}, registry=registry)
        self.assertEqual([error.message for error in oracle.iter_errors(self.document)], [])


@needs_yaml
class CommandLineTestCase(unittest.TestCase):
    """Runs the script on a copy of the sources, as CI does."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="registry-cli-"))
        self.addCleanup(shutil.rmtree, self.root)
        for name in ("errors.json", "versions.json", "schemas", "registry"):
            source = ROOT / "spec" / name
            target = self.root / "spec" / name
            if source.is_dir():
                shutil.copytree(source, target)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)

    def run_script(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_write_then_check(self) -> None:
        self.assertEqual(self.run_script("--check").returncode, 1)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("wrote spec/compiled/registry.json", result.stdout)
        self.assertEqual((self.root / cr.OUTPUT).read_bytes(), (ROOT / cr.OUTPUT).read_bytes())
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_problems_are_reported_by_file(self) -> None:
        source = self.root / "spec" / "registry" / "checks" / "outcome.zero_shares.yaml"
        source.write_text(
            source.read_text(encoding="utf-8").replace("version: 1", "version: one"),
            encoding="utf-8",
        )
        (self.root / "spec" / "registry" / "checks" / "notes.txt").write_text("x\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "spec/registry/checks/outcome.zero_shares.yaml: E3008 The value 'one' at /version "
            "cannot be read as an integer.",
            result.stderr,
        )
        self.assertIn(
            "spec/registry/checks/notes.txt: E4019 The registry sources hold the file "
            "'notes.txt', which is not a YAML source.",
            result.stderr,
        )
        self.assertFalse((self.root / cr.OUTPUT).exists())

    def test_file_name_must_match_identifier(self) -> None:
        checks = self.root / "spec" / "registry" / "checks"
        (checks / "outcome.zero_shares.yaml").rename(checks / "outcome.zeros.yaml")
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "spec/registry/checks/outcome.zeros.yaml: E4002 The identifier at /id must equal "
            "the name of its source file, 'outcome.zeros'.",
            result.stderr,
        )


if __name__ == "__main__":
    unittest.main()
