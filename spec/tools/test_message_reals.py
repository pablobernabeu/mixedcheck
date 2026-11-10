"""Tests of the vectors of the rendering of real statistics in messages,
fixtures/conformance/numbers/message_reals.txt.xz, run from the repository root
with

    python3 -m unittest discover -s spec/tools -v

They check the vectors themselves, not a rendering, which both packages
implement: the form of every line, the notation that the double gives each
rendering, the count in the README of numbers/, the listing in
spec/vendoring.json and that the decompressed text equals what
fixtures/conformance/tools/make_message_reals.py writes. Python 3.11, 3.12,
3.13 and 3.14 write the same text, so the comparison runs under every Python
from 3.11 on. They use the standard library only.
"""

from __future__ import annotations

import importlib.util
import json
import lzma
import math
import re
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NUMBERS = ROOT / "fixtures" / "conformance" / "numbers"
NAME = "message_reals.txt.xz"
TOOLS = ROOT / "fixtures" / "conformance" / "tools"
HEX16 = re.compile(r"[0-9a-f]{16}")
WORDS = {"NaN", "Infinity", "-Infinity"}


def fixed(digits: int) -> re.Pattern[str]:
    point = rf"\.[0-9]{{{digits}}}" if digits else ""
    return re.compile(rf"-?(0|[1-9][0-9]*){point}")


def scientific(digits: int) -> re.Pattern[str]:
    point = rf"\.[0-9]{{{digits}}}" if digits else ""
    return re.compile(rf"-?[1-9]{point}e[+-]([0-9]{{2}}|[1-9][0-9]{{2}})")


def under(digits: int) -> str:
    return "under " + ("1" if digits == 0 else "0." + "0" * (digits - 1) + "1")


class MessageRealsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = lzma.decompress((NUMBERS / NAME).read_bytes()).decode("ascii")
        cls.lines = cls.text.split("\n")[:-1]

    def test_form(self) -> None:
        self.assertTrue(self.text.endswith("\n"))
        self.assertNotIn("\r", self.text)
        seen: set[str] = set()
        for line in self.lines:
            with self.subTest(line=line[:16]):
                fields = line.split("\t")
                self.assertEqual(len(fields), 8)
                bits, texts = fields[0], fields[1:]
                self.assertRegex(bits, HEX16)
                self.assertNotIn(bits, seen)
                seen.add(bits)
                x = struct.unpack(">d", bytes.fromhex(bits))[0]
                if not math.isfinite(x):
                    word = "NaN" if math.isnan(x) else "Infinity" if x > 0 else "-Infinity"
                    self.assertEqual(texts, [word] * 7)
                    continue
                for digits, text in enumerate(texts):
                    if abs(x) >= 1e15:
                        self.assertRegex(text, scientific(digits))
                        self.assertEqual(text.startswith("-"), x < 0)
                    elif text.startswith("under "):
                        self.assertGreater(x, 0)
                        self.assertEqual(text, under(digits))
                    else:
                        self.assertRegex(text, fixed(digits))
                        self.assertTrue(x < 0 or not text.startswith("-"))

    def test_readme_and_vendoring(self) -> None:
        readme = (NUMBERS / "README.md").read_text(encoding="utf-8")
        self.assertIn(f"| {NAME} | {len(self.lines):,} |", readme)
        with open(ROOT / "spec" / "vendoring.json", encoding="utf-8") as handle:
            listed = json.load(handle)["artefacts"]
        self.assertIn(f"fixtures/conformance/numbers/{NAME}", listed)

    @unittest.skipUnless(sys.version_info >= (3, 11), "needs Python 3.11 or later")
    def test_generator(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "make_message_reals", TOOLS / "make_message_reals.py"
        )
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        write_bytecode = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec.loader.exec_module(module)
        finally:
            sys.dont_write_bytecode = write_bytecode
        self.assertEqual(module.content(), self.text)


if __name__ == "__main__":
    unittest.main()
