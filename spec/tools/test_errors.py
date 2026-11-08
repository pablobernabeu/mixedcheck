"""Tests of the error catalogue spec/errors.json, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

They check the rules that docs/spec/errors.md sets for the catalogue, so that
codes added for any component stay consistent. They use the standard library
only.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "spec" / "errors.json"
PROSE = ROOT / "docs" / "spec" / "errors.md"
CODE = re.compile(r"[EW][1-9][0-9]{3}")
NAME = re.compile(r"[a-z][a-z0-9]*(_[a-z0-9]+)+")
PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")
LOCATIONS = {"offset", "pointer", "offset_or_pointer", "none"}
KINDS = {"text", "integer", "number", "codepoint", "values", "words"}
LANGUAGES = {"R", "Python"}
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def _reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def _reject_constant(name: str) -> object:
    raise ValueError(f"non-finite number {name}")


def load() -> dict:
    data = CATALOGUE.read_bytes()
    if data.startswith(b"\xef\xbb\xbf") or b"\r" in data:
        raise ValueError("spec/errors.json has a byte-order mark or a carriage return")
    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=_reject_duplicates,
        parse_constant=_reject_constant,
    )


class CatalogueTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalogue = load()
        cls.areas = {area["area"]: area for area in cls.catalogue["areas"]}

    def test_top_level_members(self) -> None:
        self.assertEqual(set(self.catalogue), {"description", "areas", "codes"})

    def test_areas_do_not_overlap(self) -> None:
        areas = self.catalogue["areas"]
        self.assertEqual(len(self.areas), len(areas), "area identifiers repeat")
        previous_last = 999
        for area in areas:
            with self.subTest(area=area.get("area")):
                self.assertEqual(set(area), {"area", "first", "last", "title", "description"})
                self.assertRegex(area["area"], r"^[a-z]+$")
                self.assertLessEqual(area["first"], area["last"])
                self.assertGreater(area["first"], previous_last, "ranges overlap or are unsorted")
                self.assertLessEqual(area["last"], 9999)
                previous_last = area["last"]

    def test_codes(self) -> None:
        numbers: set[int] = set()
        names: set[str] = set()
        previous = 0
        for entry in self.catalogue["codes"]:
            code = entry.get("code", "?")
            with self.subTest(code=code):
                required = {"code", "name", "area", "location", "template", "args"}
                self.assertTrue(required <= set(entry), "a required member is missing")
                self.assertTrue(set(entry) <= required | {"languages", "retired"}, "unknown member")
                self.assertRegex(code, CODE)
                self.assertEqual(len(code), 5)
                number = int(code[1:])
                self.assertNotIn(number, numbers, "number used twice")
                self.assertGreater(number, previous, "codes are not in ascending order")
                numbers.add(number)
                previous = number

                area = self.areas.get(entry["area"])
                self.assertIsNotNone(area, "unknown area")
                self.assertTrue(area["first"] <= number <= area["last"], "outside its area")

                name = entry["name"]
                self.assertTrue(NAME.fullmatch(name), "name is not snake_case")
                self.assertTrue(name.startswith(entry["area"] + "_"), "name lacks area prefix")
                self.assertNotIn(name, names, "name used twice")
                names.add(name)

                self.assertIn(entry["location"], LOCATIONS)
                template = entry["template"]
                self.assertTrue(template.isascii(), "template is not ASCII")
                placeholders = PLACEHOLDER.findall(template)
                self.assertEqual(
                    len(placeholders), len(set(placeholders)), "placeholder used twice"
                )
                stripped = PLACEHOLDER.sub("", template)
                self.assertNotIn("{", stripped, "stray brace")
                self.assertNotIn("}", stripped, "stray brace")
                has_location = "location" in placeholders
                self.assertEqual(has_location, entry["location"] != "none")
                args = entry["args"]
                self.assertIsInstance(args, dict)
                self.assertNotIn("location", args)
                self.assertEqual(set(placeholders) - {"location"}, set(args))
                for kind in args.values():
                    self.assertIn(kind, KINDS)
                if "languages" in entry:
                    languages = entry["languages"]
                    self.assertTrue(languages and set(languages) <= LANGUAGES)
                    self.assertEqual(len(languages), len(set(languages)))
                if "retired" in entry:
                    self.assertTrue(SEMVER.fullmatch(entry["retired"]))

    def test_every_code_is_described(self) -> None:
        prose = PROSE.read_text(encoding="utf-8")
        for entry in self.catalogue["codes"]:
            with self.subTest(code=entry["code"]):
                row = f"| {entry['code']} | {entry['name']} |"
                self.assertIn(row, prose, "no row in docs/spec/errors.md")


if __name__ == "__main__":
    unittest.main()
