"""Tests of spec/unicode/assigned-14.0.json, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

They check that the ranges are in ascending order, disjoint and within the
code points that a string can hold, and, under a Python whose unicodedata
implements Unicode 14.0.0, such as Python 3.11, that the file equals what
make_unicode_ranges.py writes. They use the standard library only.
"""

from __future__ import annotations

import sys
import unicodedata
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402
import make_unicode_ranges as mur  # noqa: E402

PATH = Path(__file__).resolve().parents[1] / "unicode" / "assigned-14.0.json"


class AssignedRangesTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.data = cr.load_json(PATH)

    def test_members(self) -> None:
        self.assertEqual(set(self.data), {"description", "ranges", "unicode_version"})
        self.assertEqual(self.data["unicode_version"], "14.0.0")

    def test_ranges(self) -> None:
        previous = -2
        for first, last in self.data["ranges"]:
            with self.subTest(first=first):
                self.assertGreater(first, previous + 1, "ranges overlap or touch")
                self.assertLessEqual(first, last)
                self.assertLessEqual(last, 0x10FFFF)
                self.assertFalse(first <= 0xDFFF and last >= 0xD800, "holds surrogates")
                previous = last

    def test_normalisable(self) -> None:
        self.assertTrue(cr.normalisable("café \U0001e2ae"))
        self.assertFalse(cr.normalisable("x\U0001e4ec̖"))

    @unittest.skipUnless(unicodedata.unidata_version == mur.VERSION, "needs Unicode 14.0.0")
    def test_file_is_up_to_date(self) -> None:
        self.assertEqual(PATH.read_text(encoding="utf-8"), mur.render(mur.ranges()))


if __name__ == "__main__":
    unittest.main()
