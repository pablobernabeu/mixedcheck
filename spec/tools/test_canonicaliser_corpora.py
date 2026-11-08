"""Tests of the canonicaliser corpora in fixtures/conformance/, run from the
repository root with

    python3 -m unittest discover -s spec/tools -v

The corpora in json/, numbers/, unicode/, hash/ and hmac/ hold the cases of the
strict reader, the serialiser, number formatting, decimal constants, NFC,
hashing and keyed commitments of docs/spec/conventions.md. These tests check
the corpora themselves, not a reader or writer, which both packages implement:
the format of every case, the tables of the READMEs, every hash against its
bytes, every expected issue against spec/errors.json, and every digest, NFC
form, order, decimal string and number against the standard library and the
serialiser of compile_registry.py. Under Python 3.11 with the oracles of
fixtures/conformance/tools/requirements.txt installed, they also check that the
corpora equal what fixtures/conformance/tools/make_canonicaliser_corpora.py writes.
"""

from __future__ import annotations

import contextlib
import hashlib
import hmac
import importlib.util
import io
import json
import re
import struct
import sys
import unicodedata
import unittest
from decimal import ROUND_HALF_EVEN, Decimal, localcontext
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_registry as cr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CORPORA = ROOT / "fixtures" / "conformance"
TOOLS = CORPORA / "tools"
FILES = {
    "json": ["rfc8785", "syntax", "values", "canonical", "writer"],
    "numbers": ["format", "read", "decimal_constants"],
    "unicode": ["utf8", "normalisation", "hashable", "order", "c_locale"],
    "hash": ["sha256", "sections"],
    "hmac": ["rfc4231", "commitments"],
}
CODEC_FILES = {
    "json/rfc8785",
    "json/syntax",
    "json/values",
    "json/canonical",
    "json/writer",
    "numbers/format",
    "numbers/read",
    "unicode/utf8",
    "unicode/hashable",
    "unicode/c_locale",
}
MODES = ("plain", "data", "hashable")
READER_INPUTS = {"input", "input_hex", "file"}
WRITER_VALUES = {"json", "double"}
SUBSTITUTIONS = {"double", "wrap", "r_string", "python_string", "python_int"}
# Every code that the strict reader can report, and those of the writer that the
# corpora cover.
READER_CODES = {
    "E1001", "E1002", "E1003", "E1021", "E1022", "E1023", "E1024", "E1025", "E1026",
    "E1027", "E1028", "E1029", "E1030", "E1101", "E1102", "E1103", "E1104", "E1105",
    "E1106", "E1108", "E1109", "E1201", "E1202", "E1203", "E1208",
}  # fmt: skip
WRITER_CODES = {
    "E1030", "E1101", "E1102", "E1103", "E1104", "E1107", "E1108", "E1201", "E1203",
    "E1204", "E1205", "E1206", "E1208",
}  # fmt: skip
HEX64 = re.compile(r"[0-9a-f]{64}")
SHA256 = re.compile(r"sha256:[0-9a-f]{64}")


def load(path: Path) -> dict:
    data = path.read_bytes()
    if not data.isascii() or b"\r" in data:
        raise ValueError(f"{path} is not ASCII text with LF line endings")
    return json.loads(
        data.decode("ascii"),
        object_pairs_hook=cr._reject_duplicates,
        parse_constant=cr._reject_constant,
    )


def double(bits: str) -> float:
    return struct.unpack(">d", bytes.fromhex(bits))[0]


def input_bytes(case: dict) -> bytes:
    if "input_hex" in case:
        return bytes.fromhex(case["input_hex"])
    return case["input"].encode("utf-8")


def message_bytes(case: dict) -> bytes:
    if "message_hex" in case:
        return bytes.fromhex(case["message_hex"])
    return case["message"].encode("utf-8")


def resolve(value: Any, pointer: str) -> Any:
    for token in pointer.split("/")[1:]:
        token = token.replace("~1", "/").replace("~0", "~")
        value = value[int(token)] if isinstance(value, list) else value[token]
    return value


def form(text: str) -> str:
    return unicodedata.normalize("NFC", text) if cr.normalisable(text) else text


def decimal_constant(x: float, digits: int) -> str:
    if x == 0:
        return "0"
    with localcontext() as context:
        context.prec = 2000
        exact = Decimal(x)
        quantum = Decimal(1).scaleb(exact.adjusted() - digits + 1)
        text = format(exact.quantize(quantum, rounding=ROUND_HALF_EVEN), "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


class CanonicaliserCorporaTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = {
            f"{directory}/{stem}": load(CORPORA / directory / f"{stem}.json")
            for directory, stems in FILES.items()
            for stem in stems
        }
        cls.codes = {
            entry["code"]: entry for entry in cr.load_json(ROOT / "spec" / "errors.json")["codes"]
        }

    def cases(self, *names: str) -> list[tuple[str, dict]]:
        chosen = names or tuple(self.files)
        return [(name, case) for name in chosen for case in self.files[name]["cases"]]

    def codec_cases(self) -> list[tuple[str, dict]]:
        return self.cases(*sorted(CODEC_FILES))

    def test_files_and_readmes(self) -> None:
        for directory, stems in FILES.items():
            with self.subTest(directory=directory):
                on_disk = sorted(path.name for path in (CORPORA / directory).iterdir())
                self.assertEqual(
                    on_disk, sorted([f"{stem}.json" for stem in stems] + ["README.md"])
                )
                readme = (CORPORA / directory / "README.md").read_text(encoding="utf-8")
                for stem in stems:
                    document = self.files[f"{directory}/{stem}"]
                    self.assertEqual(set(document), {"description", "cases"})
                    self.assertIn(f"| {stem}.json | {len(document['cases'])} |", readme)

    def test_ids(self) -> None:
        seen: set[str] = set()
        for name, document in self.files.items():
            prefix = name.replace("/", "-").replace("_", "-")
            for number, case in enumerate(document["cases"], 1):
                with self.subTest(case=case.get("id")):
                    self.assertEqual(case["id"], f"{prefix}-{number:03d}")
                    self.assertNotIn(case["id"], seen)
                    seen.add(case["id"])
                    self.assertTrue(case["description"].endswith("."))

    def check_result(self, result: dict, *, reader: bool, data: bytes | None) -> None:
        if "issue" in result:
            self.assertEqual(set(result), {"issue"})
            self.check_issue(result["issue"], reader=reader, data=data)
            return
        self.assertLessEqual({"canonical", "sha256"}, set(result))
        self.assertLessEqual(set(result), {"canonical", "sha256", "bits"})
        canonical = result["canonical"].encode("utf-8")
        self.assertEqual(result["sha256"], "sha256:" + hashlib.sha256(canonical).hexdigest())
        value = json.loads(result["canonical"], parse_int=float)
        self.assertEqual(cr.canonical_bytes(value), canonical)

    def check_issue(self, issue: dict, *, reader: bool, data: bytes | None) -> None:
        entry = self.codes[issue["code"]]
        location = entry["location"]
        self.assertLessEqual(set(issue), {"code", "message", "offset", "pointer"})
        if location == "none":
            self.assertEqual(set(issue), {"code", "message"})
            rendered = None
        elif reader:
            self.assertIn(location, ("offset", "offset_or_pointer"))
            self.assertEqual(set(issue), {"code", "message", "offset"})
            if data is not None:
                self.assertLessEqual(issue["offset"], len(data))
            rendered = f"byte {issue['offset']}"
        else:
            self.assertIn(location, ("pointer", "offset_or_pointer"))
            self.assertEqual(set(issue), {"code", "message", "pointer"})
            pointer = issue["pointer"]
            rendered = cr.display_escape(pointer) if pointer else "(root)"
        pattern = ""
        for part in re.split(r"(\{[a-z_]+\})", entry["template"]):
            if part == "{location}":
                pattern += re.escape(rendered or "")
            elif re.fullmatch(r"\{[a-z_]+\}", part):
                pattern += ".+"
            else:
                pattern += re.escape(part)
        self.assertRegex(issue["message"], "^" + pattern + "$")

    def test_codec_cases(self) -> None:
        for name, case in self.codec_cases():
            with self.subTest(case=case["id"]):
                members = set(case) - {"id", "description", "expected", "languages"}
                expected = case["expected"]
                if members & READER_INPUTS:
                    self.assertEqual(len(members & READER_INPUTS), 1)
                    self.assertLessEqual(members, READER_INPUTS)
                    self.assertNotIn("languages", case)
                    self.assertEqual(set(expected), set(MODES))
                    data = None if "file" in case else input_bytes(case)
                    if "input" in case:
                        self.assertNotIn("\0", case["input"])
                    for result in expected.values():
                        self.check_result(result, reader=True, data=data)
                        if name != "numbers/read":
                            self.assertNotIn("bits", result)
                else:
                    self.assertEqual(len(members & WRITER_VALUES), 1)
                    self.assertLessEqual(members, WRITER_VALUES | {"substitutions"})
                    for substitution in case.get("substitutions", []):
                        kinds = set(substitution) - {"pointer"}
                        self.assertEqual(len(kinds), 1)
                        self.assertLessEqual(kinds, SUBSTITUTIONS)
                    self.assertIn(set(expected), ({"data", "hashable"}, set(MODES)))
                    for result in expected.values():
                        self.check_result(result, reader=False, data=None)
                        self.assertNotIn("bits", result)

    def test_languages(self) -> None:
        for _, case in self.codec_cases():
            with self.subTest(case=case["id"]):
                kinds = {
                    kind
                    for substitution in case.get("substitutions", [])
                    for kind in substitution
                    if kind != "pointer"
                }
                if "r_string" in kinds:
                    self.assertEqual(case.get("languages"), ["R"])
                elif kinds & {"python_string", "python_int"}:
                    self.assertEqual(case.get("languages"), ["Python"])
                else:
                    self.assertNotIn("languages", case)

    def test_every_code_is_covered(self) -> None:
        reader, writer = set(), set()
        for _, case in self.codec_cases():
            target = writer if not set(case) & READER_INPUTS else reader
            for result in case["expected"].values():
                if "issue" in result:
                    target.add(result["issue"]["code"])
        self.assertLessEqual(READER_CODES, reader)
        self.assertLessEqual(WRITER_CODES, writer)
        self.assertLessEqual(reader, READER_CODES)

    def test_number_formats(self) -> None:
        for _, case in self.cases("json/rfc8785", "numbers/format"):
            if "double" not in case:
                continue
            with self.subTest(case=case["id"]):
                x = double(case["double"])
                if x != x or x in (float("inf"), float("-inf")):
                    word = "NaN" if x != x else "Infinity" if x > 0 else "-Infinity"
                    self.assertEqual(case["expected"]["data"]["canonical"], f'"{word}"')
                    self.assertEqual(case["expected"]["hashable"]["issue"]["code"], "E1107")
                    continue
                self.assertEqual(case["expected"]["plain"]["canonical"], cr.format_number(x))

    def test_numbers_read(self) -> None:
        for _, case in self.cases("numbers/read"):
            with self.subTest(case=case["id"]):
                x = float(case["input"])
                for result in case["expected"].values():
                    if "issue" in result:
                        continue
                    if x == 0:
                        self.assertNotIn("bits", result)
                    else:
                        self.assertEqual(result["bits"], struct.pack(">d", x).hex())
                        self.assertEqual(result["canonical"], cr.format_number(x))

    def test_decimal_constants(self) -> None:
        for _, case in self.cases("numbers/decimal_constants"):
            with self.subTest(case=case["id"]):
                self.assertEqual(set(case), {"id", "description", "double", "digits", "expected"})
                self.assertTrue(1 <= case["digits"] <= 15)
                text = decimal_constant(double(case["double"]), case["digits"])
                self.assertEqual(case["expected"], {"decimal": text})
                self.assertRegex(text, r"^(0|-?[1-9][0-9]*(\.[0-9]*[1-9])?|-?0\.[0-9]*[1-9])$")

    def test_normalisation(self) -> None:
        for _, case in self.cases("unicode/normalisation"):
            with self.subTest(case=case["id"]):
                text = case["string"]
                normalisable = cr.normalisable(text)
                self.assertEqual(
                    case["expected"], {"normalisable": normalisable, "form": form(text)}
                )

    def test_order(self) -> None:
        for _, case in self.cases("unicode/order"):
            with self.subTest(case=case["id"]):
                if "strings" in case:
                    keys = [[ord(char) for char in form(text)] for text in case["strings"]]
                    self.assertEqual(len({tuple(key) for key in keys}), len(keys))
                    ordered = sorted(case["strings"], key=lambda text: [ord(c) for c in form(text)])
                    self.assertEqual(case["expected"], {"sorted": ordered})
                    continue
                left = [ord(char) for char in form(case["first"])]
                right = [ord(char) for char in form(case["second"])]
                self.assertEqual(case["expected"], {"order": (left > right) - (left < right)})

    def test_sha256(self) -> None:
        for _, case in self.cases("hash/sha256"):
            with self.subTest(case=case["id"]):
                data = input_bytes(case) * case.get("repeat", 1)
                self.assertRegex(case["expected"]["sha256"], SHA256)
                digest = "sha256:" + hashlib.sha256(data).hexdigest()
                self.assertEqual(case["expected"], {"sha256": digest})

    def test_sections(self) -> None:
        for _, case in self.cases("hash/sections"):
            with self.subTest(case=case["id"]):
                document = json.loads(case["input"], parse_int=float)
                serialised = cr.canonical_bytes(resolve(document, case["pointer"]))
                self.assertEqual(case["expected"]["canonical"].encode("utf-8"), serialised)
                digest = "sha256:" + hashlib.sha256(serialised).hexdigest()
                self.assertEqual(case["expected"]["sha256"], digest)

    def test_rfc4231(self) -> None:
        for _, case in self.cases("hmac/rfc4231"):
            with self.subTest(case=case["id"]):
                key = bytes.fromhex(case["key_hex"])
                digest = hmac.new(key, message_bytes(case), hashlib.sha256).hexdigest()
                length = 2 * case.get("truncate", 32)
                self.assertEqual(case["expected"], {"digest": digest[:length]})

    def test_commitments(self) -> None:
        for _, case in self.cases("hmac/commitments"):
            with self.subTest(case=case["id"]):
                key = case["key"]
                expected = case["expected"]
                if not HEX64.fullmatch(key):
                    self.assertEqual(set(expected), {"issue"})
                    self.assertEqual(expected["issue"]["code"], "E1311")
                    self.check_issue(expected["issue"], reader=False, data=None)
                    continue
                key_id = hashlib.sha256(bytes.fromhex(key)).hexdigest()[:16]
                if "covers" not in case:
                    self.assertEqual(expected, {"key_id": key_id})
                    continue
                message = message_bytes(case)
                digest = hmac.new(bytes.fromhex(key), message, hashlib.sha256).hexdigest()
                commitment = {
                    "algorithm": "hmac-sha256",
                    "covers": case["covers"],
                    "digest": digest,
                    "key_id": key_id,
                }
                self.assertEqual(expected, {"commitment": commitment})

    @unittest.skipUnless(
        unicodedata.unidata_version == "14.0.0"
        and importlib.util.find_spec("rfc8785") is not None
        and importlib.util.find_spec("jsonschema") is not None,
        "needs Python 3.11 with the oracles of fixtures/conformance/tools/requirements.txt",
    )
    def test_corpora_are_up_to_date(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "make_canonicaliser_corpora", TOOLS / "make_canonicaliser_corpora.py"
        )
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        # dataclasses look the module up in sys.modules while it is executed.
        sys.modules[spec.name] = module
        write_bytecode = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec.loader.exec_module(module)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(["--check"]), 0)
        finally:
            del sys.modules[spec.name]
            sys.dont_write_bytecode = write_bytecode


if __name__ == "__main__":
    unittest.main()
