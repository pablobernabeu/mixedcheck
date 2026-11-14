#!/usr/bin/env python3
"""Write the conformance corpora of the canonicaliser.

The corpora test the strict JSON reader, the RFC 8785 serialiser with ECMAScript
number formatting, decimal constants, SHA-256 hashing, HMAC-SHA-256 keyed
commitments and the Unicode policy of docs/spec/conventions.md, which make up
canonicaliser version 0.1.0. This script writes them under fixtures/conformance/:

    json/      rfc8785.json syntax.json values.json canonical.json writer.json
    numbers/   format.json read.json decimal_constants.json
    unicode/   utf8.json normalisation.json hashable.json order.json c_locale.json
    hash/      sha256.json sections.json
    hmac/      rfc4231.json commitments.json

Each case states the expected error code by hand, from the specification. The
script derives the remaining parts of each expected output and checks them
against independent oracles:

- canonical bytes from the rfc8785 package, applied to the value that Python's
  json module reads from the input, with every number converted by float(),
  which CPython rounds correctly. Fractions confirm the rounding.
- ECMAScript number strings from the rfc8785 package, confirmed by Node.js
  when `node` is on the PATH
- SHA-256 from hashlib and HMAC-SHA-256 from hmac
- NFC from unicodedata, which implements Unicode 14.0.0 in Python 3.11
- decimal constants from the decimal module, confirmed by format()
- the form of every issue, commitment, hash and decimal string from jsonschema
  with the schemas in spec/schemas/

The offsets, pointers and message arguments of the expected issues come from a
scratch reading of the rules in conventions.md, written for this script and part
of neither package. Where a case states an offset by hand, the script checks
that the two agree. Messages are rendered from the templates of spec/errors.json
as docs/spec/errors.md describes.

Run it from the repository root with Python 3.11, in a virtual environment that
holds the packages of requirements.txt:

    python fixtures/conformance/tools/make_canonicaliser_corpora.py
    python fixtures/conformance/tools/make_canonicaliser_corpora.py --check

The first writes the corpora and the second compares them with the files and
writes nothing.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import hmac
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass, field
from decimal import ROUND_HALF_EVEN, Decimal, localcontext
from fractions import Fraction
from pathlib import Path
from typing import Any

import jsonschema
import rfc8785
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[3]
CORPORA = ROOT / "fixtures" / "conformance"
SPEC = ROOT / "spec"
MODES = ("plain", "data", "hashable")
OK = "ok"
BOM = b"\xef\xbb\xbf"
MAX_INTEGER = 9007199254740991
MAX_DEPTH = 64
UNICODE_VERSION = "14.0.0"


# Oracles ------------------------------------------------------------------------


def sha256_hash(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def bits_of(x: float) -> str:
    return struct.pack(">d", x).hex()


def double(bits: str) -> float:
    return struct.unpack(">d", bytes.fromhex(bits))[0]


def es_number(x: float) -> str:
    """ECMAScript Number::toString of a finite double, from the rfc8785 package."""
    return rfc8785.dumps(float(x)).decode("ascii")


def _floats(value: Any) -> Any:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, list):
        return [_floats(item) for item in value]
    return {key: _floats(item) for key, item in value.items()}


def canonical(value: Any) -> bytes:
    """The RFC 8785 serialisation of a value, with every number as a double."""
    return rfc8785.dumps(_floats(value))


def oracle_read(data: bytes) -> Any:
    """Read JSON text that the strict reader accepts, with Python's json module."""

    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        return dict(items)

    return json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_int=float)


def check_nearest(token: str, x: float) -> None:
    """Confirm with exact arithmetic that x is the double nearest to the decimal token."""
    mantissa, _, exponent = token.lower().partition("e")
    if exponent and abs(int(exponent)) > 4000:
        return
    exact = Fraction(token)
    magnitude = abs(exact)
    if math.isinf(x):
        assert magnitude >= Fraction(2) ** 1024 - Fraction(2) ** 970, token
        return
    if x == 0:
        assert magnitude <= Fraction(2) ** -1075, token
        return
    below = math.nextafter(x, -math.inf)
    above = math.nextafter(x, math.inf)
    above_value = Fraction(2) ** 1024 if math.isinf(above) else Fraction(above)
    gap = abs(exact - Fraction(x))
    assert gap <= abs(exact - Fraction(below)), token
    assert gap <= abs(exact - above_value), token
    if gap in (abs(exact - Fraction(below)), abs(exact - above_value)):
        assert struct.unpack(">Q", struct.pack(">d", x))[0] % 2 == 0, token


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


class Schemas:
    """jsonschema validation against the shared definitions of the schema bundle."""

    def __init__(self) -> None:
        resources = []
        for path in sorted((SPEC / "schemas").glob("*.schema.json")):
            schema = _load(path)
            resources.append((schema["$id"], Resource.from_contents(schema)))
        self.registry = Registry().with_resources(resources)

    def check(self, value: Any, definition: str) -> None:
        schema = {"$ref": f"urn:mixedcheck:schema:defs#/$defs/{definition}"}
        validator = jsonschema.Draft202012Validator(schema, registry=self.registry)
        errors = list(validator.iter_errors(value))
        if errors:
            raise AssertionError(f"{value!r} is not a valid {definition}: {errors[0].message}")


class Unicode:
    """Assigned code points of Unicode 14.0 and NFC from unicodedata."""

    def __init__(self) -> None:
        if unicodedata.unidata_version != UNICODE_VERSION:
            sys.exit(f"needs unicodedata {UNICODE_VERSION}, as in Python 3.11")
        ranges = _load(SPEC / "unicode" / "assigned-14.0.json")["ranges"]
        self.firsts = [first for first, _ in ranges]
        self.lasts = [last for _, last in ranges]

    def assigned(self, point: int) -> bool:
        index = bisect.bisect_right(self.firsts, point) - 1
        result = index >= 0 and point <= self.lasts[index]
        expected = 0xD800 > point or point > 0xDFFF
        expected = expected and unicodedata.category(chr(point)) != "Cn"
        assert result == expected, hex(point)
        return result

    def normalisable(self, text: str) -> bool:
        return all(self.assigned(ord(char)) for char in text)

    def form(self, text: str) -> str:
        """The form compared for identifiers and labels: NFC when normalisable."""
        return unicodedata.normalize("NFC", text) if self.normalisable(text) else text


UNICODE = Unicode()
SCHEMAS = Schemas()


# Messages -----------------------------------------------------------------------


def display_escape(text: str) -> str:
    out = []
    for char in text:
        point = ord(char)
        if point <= 0x1F or 0x7F <= point <= 0x9F or point in (0x2028, 0x2029):
            out.append(f"\\u{point:04X}")
        else:
            out.append(char)
    return "".join(out)


def truncate(text: str) -> str:
    return text if len(text) <= 60 else text[:57] + "..."


class Catalogue:
    """The codes of spec/errors.json, rendered as docs/spec/errors.md describes."""

    def __init__(self) -> None:
        self.codes = {entry["code"]: entry for entry in _load(SPEC / "errors.json")["codes"]}

    def issue(
        self, code: str, offset: int | None = None, pointer: str | None = None, **args: Any
    ) -> dict[str, Any]:
        entry = self.codes[code]
        values: dict[str, str] = {}
        location = entry["location"]
        if location != "none":
            if offset is not None:
                assert location in ("offset", "offset_or_pointer"), code
                values["location"] = f"byte {offset}"
            else:
                assert pointer is not None and location in ("pointer", "offset_or_pointer"), code
                values["location"] = display_escape(pointer) if pointer else "(root)"
        for name, kind in entry["args"].items():
            value = args[name]
            if kind == "text":
                values[name] = truncate(display_escape(str(value)))
            elif kind == "integer":
                values[name] = str(int(value))
            elif kind == "number":
                values[name] = es_number(value)
            elif kind == "codepoint":
                values[name] = f"{value:04X}"
            else:
                raise AssertionError(f"kind {kind} is not used here")
        message = re.sub(r"\{([a-z_]+)\}", lambda match: values[match.group(1)], entry["template"])
        result: dict[str, Any] = {"code": code, "message": message}
        if location != "none":
            if offset is not None:
                result["offset"] = offset
            else:
                result["pointer"] = pointer
        SCHEMAS.check(result, "issue")
        return result


CATALOGUE = Catalogue()


class Refusal(Exception):
    """An issue found by the scratch reading of the rules."""

    def __init__(
        self, code: str, offset: int | None = None, pointer: str | None = None, **args: Any
    ) -> None:
        super().__init__(code)
        self.code = code
        self.offset = offset
        self.pointer = pointer
        self.args_ = args

    def issue(self) -> dict[str, Any]:
        return CATALOGUE.issue(self.code, self.offset, self.pointer, **self.args_)


# Scratch reading of the strict reader (conventions.md, Strict reader) ------------

WHITE = b" \t\n\r"
NUMBER_BYTES = frozenset(b"0123456789+-.eE")
NUMBER_GRAMMAR = re.compile(rb"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
NUMBER_PARTS = re.compile(r"(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?")
HEX = frozenset(b"0123456789abcdefABCDEF")
SIMPLE_ESCAPES = {
    ord('"'): 0x22,
    ord("\\"): 0x5C,
    ord("/"): 0x2F,
    ord("b"): 0x08,
    ord("f"): 0x0C,
    ord("n"): 0x0A,
    ord("r"): 0x0D,
    ord("t"): 0x09,
}
LITERALS = {ord("t"): (b"true", True), ord("f"): (b"false", False), ord("n"): (b"null", None)}


def decimal_parts(token: str) -> tuple[str, int]:
    """D and e of a number token (conventions.md, Numbers). D is '' for zero."""
    match = NUMBER_PARTS.fullmatch(token)
    assert match is not None, token
    fraction = match.group(3) or ""
    digits = (match.group(2) + fraction).lstrip("0")
    exponent = int(match.group(4) or "0") - len(fraction)
    if not digits:
        return "", 0
    stripped = digits.rstrip("0")
    return stripped, exponent + len(digits) - len(stripped)


def token_issue(token: str, mode: str) -> str | None:
    digits, exponent = decimal_parts(token)
    if mode == "hashable":
        if not digits:
            return None
        n = len(digits)
        p = n + exponent - 1
        if exponent >= 0:
            if p <= 14 or (p == 15 and int(digits) * 10**exponent <= MAX_INTEGER):
                return None
            return "E1102"
        if n <= 15 and p >= -307:
            return None
        return "E1103" if n > 15 else "E1104"
    x = float(token)
    if math.isinf(x):
        return "E1105"
    if x == 0 and digits:
        return "E1106"
    return None


def decode_items(items: list[tuple[str, int]]) -> tuple[str, bool]:
    """Join the characters and escapes of a string token. Return it and whether a
    surrogate escape is unpaired."""
    out: list[str] = []
    index = 0
    while index < len(items):
        kind, value = items[index]
        if kind == "u" and 0xD800 <= value <= 0xDBFF:
            if index + 1 < len(items):
                next_kind, low = items[index + 1]
                if next_kind == "u" and 0xDC00 <= low <= 0xDFFF:
                    out.append(chr(0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)))
                    index += 2
                    continue
            return "", True
        if kind == "u" and 0xDC00 <= value <= 0xDFFF:
            return "", True
        out.append(chr(value))
        index += 1
    return "".join(out), False


class ScratchReader:
    def __init__(self, data: bytes, mode: str) -> None:
        self.data = data
        self.n = len(data)
        self.mode = mode
        self.i = 0
        self.first: Refusal | None = None

    def value_issue(self, refusal: Refusal) -> None:
        if self.first is None:
            self.first = refusal

    def character(self, offset: int) -> str:
        lead = self.data[offset]
        length = 1 if lead < 0x80 else 2 if lead < 0xE0 else 3 if lead < 0xF0 else 4
        return self.data[offset : offset + length].decode("utf-8")

    def white(self) -> None:
        while self.i < self.n and self.data[self.i] in WHITE:
            self.i += 1

    def end(self) -> Refusal:
        return Refusal("E1021", offset=self.n)

    def read(self) -> Any:
        value = self.value(0)
        self.white()
        if self.i < self.n:
            raise Refusal("E1023", offset=self.i)
        if self.first is not None:
            raise self.first
        return value

    def value(self, depth: int) -> Any:
        self.white()
        if self.i >= self.n:
            raise self.end()
        start = self.i
        byte = self.data[start]
        for literal in (b"NaN", b"Infinity", b"-Infinity"):
            if self.data.startswith(literal, start):
                raise Refusal("E1027", offset=start, literal=literal.decode())
        if byte in b"-+.0123456789":
            return self.number()
        if byte in LITERALS:
            return self.literal()
        if byte == 0x22:
            text, lone = self.string()
            self.check_text(text, lone, start, key=False)
            return text
        if byte == 0x7B:
            return self.object(depth + 1)
        if byte == 0x5B:
            return self.array(depth + 1)
        raise Refusal("E1022", offset=start, character=self.character(start))

    def number(self) -> Any:
        start = end = self.i
        while end < self.n and self.data[end] in NUMBER_BYTES:
            end += 1
        run = self.data[start:end]
        if not NUMBER_GRAMMAR.fullmatch(run):
            raise Refusal("E1028", offset=start, token=run.decode())
        self.i = end
        token = run.decode()
        code = token_issue(token, self.mode)
        if code is not None:
            self.value_issue(Refusal(code, offset=start, number=token))
        return float(token)

    def literal(self) -> Any:
        start = self.i
        word, value = LITERALS[self.data[start]]
        for k, expected in enumerate(word):
            if start + k >= self.n:
                raise self.end()
            if self.data[start + k] != expected:
                raise Refusal("E1022", offset=start + k, character=self.character(start + k))
        self.i = start + len(word)
        if value is None and self.mode == "hashable":
            self.value_issue(Refusal("E1101", offset=start))
        return value

    def string(self) -> tuple[str, bool]:
        i = self.i + 1
        items: list[tuple[str, int]] = []
        while True:
            if i >= self.n:
                raise self.end()
            byte = self.data[i]
            if byte == 0x22:
                self.i = i + 1
                return decode_items(items)
            if byte < 0x20:
                raise Refusal("E1024", offset=i, codepoint=byte)
            if byte == 0x5C:
                if i + 1 >= self.n:
                    raise self.end()
                escape = self.data[i + 1]
                if escape in SIMPLE_ESCAPES:
                    items.append(("c", SIMPLE_ESCAPES[escape]))
                    i += 2
                    continue
                if escape == ord("u"):
                    for k in range(4):
                        if i + 2 + k >= self.n:
                            raise self.end()
                        if self.data[i + 2 + k] not in HEX:
                            raise Refusal("E1025", offset=i)
                    items.append(("u", int(self.data[i + 2 : i + 6], 16)))
                    i += 6
                    continue
                raise Refusal("E1025", offset=i)
            char = self.character(i)
            items.append(("c", ord(char)))
            i += len(char.encode("utf-8"))

    def check_text(self, text: str, lone: bool, start: int, *, key: bool) -> bool:
        """Apply the checks of a string or key token. Return False after an issue."""
        code = None
        if lone:
            code = "E1026"
        elif "\0" in text:
            code = "E1202"
        elif key and text == "":
            code = "E1109"
        elif key and self.mode != "plain" and any(ord(char) > 0xFFFF for char in text):
            code = "E1108"
        elif self.mode == "hashable" and not UNICODE.normalisable(text):
            code = "E1208"
        elif self.mode == "hashable" and not unicodedata.is_normalized("NFC", text):
            code = "E1203"
        if code is not None:
            self.value_issue(Refusal(code, offset=start))
            return False
        return True

    def expect(self, wanted: bytes) -> None:
        self.white()
        if self.i >= self.n:
            raise self.end()
        if self.data[self.i] not in wanted:
            raise Refusal("E1022", offset=self.i, character=self.character(self.i))

    def object(self, depth: int) -> dict[str, Any]:
        if depth > MAX_DEPTH:
            raise Refusal("E1030", offset=self.i, limit=MAX_DEPTH)
        self.i += 1
        result: dict[str, Any] = {}
        self.expect(b'"}')
        if self.data[self.i] == 0x7D:
            self.i += 1
            return result
        while True:
            self.expect(b'"')
            start = self.i
            key, lone = self.string()
            if self.check_text(key, lone, start, key=True) and key in result:
                self.value_issue(Refusal("E1029", offset=start, key=key))
            self.expect(b":")
            self.i += 1
            result[key] = self.value(depth)
            self.expect(b",}")
            self.i += 1
            if self.data[self.i - 1] == 0x7D:
                return result

    def array(self, depth: int) -> list[Any]:
        if depth > MAX_DEPTH:
            raise Refusal("E1030", offset=self.i, limit=MAX_DEPTH)
        self.i += 1
        result: list[Any] = []
        self.white()
        if self.i < self.n and self.data[self.i] == 0x5D:
            self.i += 1
            return result
        while True:
            result.append(self.value(depth))
            self.expect(b",]")
            self.i += 1
            if self.data[self.i - 1] == 0x5D:
                return result


def scratch_read(data: bytes, mode: str) -> Any:
    if data.startswith(BOM):
        raise Refusal("E1003")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as err:
        raise Refusal("E1201", offset=err.start) from None
    return ScratchReader(data, mode).read()


# Scratch reading of the writer (conventions.md, Profiles and Serialisation) ------


@dataclass(frozen=True)
class RString:
    """An R string with its bytes and encoding mark."""

    hex: str
    encoding: str


@dataclass(frozen=True)
class PyString:
    """A Python str given by its code points, which may include surrogates."""

    points: tuple[int, ...]


@dataclass(frozen=True)
class PyInt:
    """A Python int, which may lie outside the range of a double's exact integers."""

    value: int


def child(pointer: str, token: str | int) -> str:
    text = str(token).replace("~", "~0").replace("/", "~1")
    return f"{pointer}/{text}"


def utf16_key(key: str) -> bytes:
    return key.encode("utf-16-be", "surrogatepass")


def significant_digits(text: str) -> int:
    mantissa = text.lstrip("-").split("e")[0].replace(".", "")
    return len(mantissa.strip("0"))


def text_check(value: Any, mode: str, pointer: str, *, key: bool) -> str:
    """Check a string or key as a writer does and return it as a str."""
    if isinstance(value, RString):
        raw = bytes.fromhex(value.hex)
        if value.encoding == "bytes":
            raise Refusal("E1205", pointer=pointer)
        if value.encoding == "unknown" and any(byte >= 0x80 for byte in raw):
            raise Refusal("E1204", pointer=pointer)
        if value.encoding == "latin1":
            value = raw.decode("latin-1")
        else:
            try:
                value = raw.decode("utf-8")
            except UnicodeDecodeError:
                raise Refusal("E1201", pointer=pointer) from None
    elif isinstance(value, PyString):
        if any(0xD800 <= point <= 0xDFFF for point in value.points):
            raise Refusal("E1206", pointer=pointer)
        value = "".join(chr(point) for point in value.points)
    if "\0" in value:
        raise Refusal("E1202", pointer=pointer)
    if key and value == "":
        raise Refusal("E1109", pointer=pointer)
    if key and mode != "plain" and any(ord(char) > 0xFFFF for char in value):
        raise Refusal("E1108", pointer=pointer)
    if mode == "hashable" and not UNICODE.normalisable(value):
        raise Refusal("E1208", pointer=pointer)
    if mode == "hashable" and not unicodedata.is_normalized("NFC", value):
        raise Refusal("E1203", pointer=pointer)
    return value


def scratch_write(value: Any, mode: str, pointer: str = "", depth: int = 0) -> Any:
    """Check a value in memory and return it as the writer would serialise it."""
    if isinstance(value, dict):
        if depth + 1 > MAX_DEPTH:
            raise Refusal("E1030", pointer=pointer, limit=MAX_DEPTH)
        result = {}
        for key in sorted(value, key=utf16_key):
            member = child(pointer, key)
            text_check(key, mode, member, key=True)
            result[key] = scratch_write(value[key], mode, member, depth + 1)
        return result
    if isinstance(value, list):
        if depth + 1 > MAX_DEPTH:
            raise Refusal("E1030", pointer=pointer, limit=MAX_DEPTH)
        return [
            scratch_write(item, mode, child(pointer, index), depth + 1)
            for index, item in enumerate(value)
        ]
    if value is None:
        if mode == "hashable":
            raise Refusal("E1101", pointer=pointer)
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, PyInt):
        if abs(value.value) > MAX_INTEGER:
            assert mode != "plain", "the plain mode does not define this case"
            raise Refusal("E1102", pointer=pointer, number=str(value.value))
        value = value.value
    if isinstance(value, int | float):
        x = float(value)
        if math.isnan(x) or math.isinf(x):
            assert mode != "plain", "the plain mode does not write non-finite numbers"
            if mode == "hashable":
                raise Refusal("E1107", pointer=pointer)
            return "NaN" if math.isnan(x) else "Infinity" if x > 0 else "-Infinity"
        if mode == "hashable" and x != 0:
            text = es_number(x)
            if x == math.floor(x):
                if abs(x) > MAX_INTEGER:
                    raise Refusal("E1102", pointer=pointer, number=text)
            elif significant_digits(text) > 15:
                raise Refusal("E1103", pointer=pointer, number=text)
            elif abs(Decimal(text)) < Decimal("1e-307"):
                raise Refusal("E1104", pointer=pointer, number=text)
        return x
    return text_check(value, mode, pointer, key=False)


# Case builders ------------------------------------------------------------------


def modes(plain: str = OK, data: str | None = None, hashable: str | None = None) -> dict:
    """Expected codes by mode. data defaults to plain and hashable to data."""
    data = plain if data is None else data
    hashable = data if hashable is None else hashable
    return {"plain": plain, "data": data, "hashable": hashable}


def _expect(expect: str | dict) -> dict:
    return modes(expect) if isinstance(expect, str) else dict(expect)


def _locate(data: bytes, at: int | str | None) -> int | None:
    if at is None or isinstance(at, int):
        return at
    found = data.find(at.encode("utf-8"))
    assert found >= 0, at
    return found


def _success(serialised: bytes, extra: dict | None = None) -> dict[str, Any]:
    result = {"canonical": serialised.decode("utf-8"), "sha256": sha256_hash(serialised)}
    SCHEMAS.check(result["sha256"], "sha256_hash")
    return result | (extra or {})


@dataclass
class Builder:
    """Collects the cases of one corpus file and numbers them."""

    prefix: str
    description: str
    cases: list[dict] = field(default_factory=list)

    def add(self, case: dict) -> dict:
        number = len(self.cases) + 1
        case = {"id": f"{self.prefix}-{number:03d}"} | case
        self.cases.append(case)
        return case

    def reader(
        self,
        description: str,
        text: str | bytes | None = None,
        expect: str | dict = OK,
        *,
        at: int | str | dict | None = None,
        file: str | None = None,
        bits: bool = False,
    ) -> dict:
        """A reader case. text is the input, str for its UTF-8 bytes or bytes."""
        expected_codes = _expect(expect)
        case: dict[str, Any] = {"description": description}
        if file is not None:
            case["file"] = file
            data = b""
        else:
            assert text is not None
            data = text.encode("utf-8") if isinstance(text, str) else text
            try:
                decoded = data.decode("utf-8")
            except UnicodeDecodeError:
                decoded = None
            if decoded is None or "\0" in decoded:
                case["input_hex"] = data.hex()
            else:
                case["input"] = decoded
        results = {}
        for mode in MODES:
            wanted = expected_codes[mode]
            if file is not None:
                refusal = Refusal("E1001" if file == "missing" else "E1002")
                assert wanted == refusal.code, description
                results[mode] = {"issue": refusal.issue()}
                continue
            try:
                value = scratch_read(data, mode)
            except Refusal as refusal:
                assert wanted == refusal.code, (description, mode, refusal.code)
                where = at.get(mode) if isinstance(at, dict) else at
                expected_offset = _locate(data, where)
                if expected_offset is not None:
                    assert refusal.offset == expected_offset, (description, refusal.offset)
                results[mode] = {"issue": refusal.issue()}
                continue
            assert wanted == OK, (description, mode, "accepted")
            serialised = canonical(oracle_read(data))
            assert serialised == canonical(value), description
            extra = None
            if bits:
                x = float(oracle_read(data))
                check_nearest(data.decode("ascii"), x)
                # The sign of a zero read from a token is left open.
                extra = {"bits": bits_of(x)} if x != 0 else None
            results[mode] = _success(serialised, extra)
        case["expected"] = results
        return self.add(case)

    def writer(
        self,
        description: str,
        expect: str | dict = OK,
        *,
        json_text: str | None = None,
        bits: str | None = None,
        substitutions: Iterable[dict] = (),
        languages: list[str] | None = None,
        at: str | None = None,
        skip_plain: bool = False,
    ) -> dict:
        """A writer case: a value in memory and its expected output by mode."""
        expected_codes = _expect(expect)
        case: dict[str, Any] = {"description": description}
        if languages:
            case["languages"] = languages
        if json_text is not None:
            case["json"] = json_text
            value = oracle_read(json_text.encode("utf-8"))
            scratch_read(json_text.encode("utf-8"), "plain")
        else:
            assert bits is not None
            case["double"] = bits
            value = double(bits)
        substitutions = list(substitutions)
        if substitutions:
            case["substitutions"] = [
                {key: item for key, item in sub.items() if key != "value"} for sub in substitutions
            ]
            for sub in substitutions:
                value = substitute(value, sub)
        results = {}
        for mode in MODES:
            if mode == "plain" and skip_plain:
                continue
            wanted = expected_codes[mode]
            try:
                written = scratch_write(value, mode)
            except Refusal as refusal:
                assert wanted == refusal.code, (description, mode, refusal.code)
                if at is not None:
                    assert refusal.pointer == at, (description, refusal.pointer)
                results[mode] = {"issue": refusal.issue()}
                continue
            assert wanted == OK, (description, mode, "accepted")
            results[mode] = _success(canonical(written))
        case["expected"] = results
        return self.add(case)

    def document(self) -> dict:
        return {"description": self.description, "cases": self.cases}


def substitute(value: Any, sub: dict) -> Any:
    """Apply one substitution of a writer case to a value."""
    tokens = [] if sub["pointer"] == "" else sub["pointer"][1:].split("/")
    tokens = [token.replace("~1", "/").replace("~0", "~") for token in tokens]

    def replace(target: Any, depth: int) -> Any:
        if depth == len(tokens):
            if "double" in sub:
                return double(sub["double"])
            if "wrap" in sub:
                for _ in range(sub["wrap"]):
                    target = [target]
                return target
            return sub["value"]
        token = tokens[depth]
        if isinstance(target, list):
            index = int(token)
            return [
                replace(item, depth + 1) if i == index else item for i, item in enumerate(target)
            ]
        return {
            key: replace(item, depth + 1) if key == token else item for key, item in target.items()
        }

    return replace(value, 0)


def r_string(pointer: str, hex_bytes: str, encoding: str) -> dict:
    return {
        "pointer": pointer,
        "r_string": {"hex": hex_bytes, "encoding": encoding},
        "value": RString(hex_bytes, encoding),
    }


def py_string(pointer: str, points: list[int]) -> dict:
    return {"pointer": pointer, "python_string": points, "value": PyString(tuple(points))}


def py_int(pointer: str, digits: str) -> dict:
    return {"pointer": pointer, "python_int": digits, "value": PyInt(int(digits))}


def nan_bits(kind: str) -> str:
    return {
        "NaN": "7ff8000000000000",
        "Infinity": "7ff0000000000000",
        "-Infinity": "fff0000000000000",
    }[kind]


# json/ ----------------------------------------------------------------------------

RFC8785_VALUES_INPUT = (
    "{\n"
    '  "numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],\n'
    '  "string": "\\u20ac$\\u000F\\u000aA\'\\u0042\\u0022\\u005c\\\\\\"\\/",\n'
    '  "literals": [null, true, false]\n'
    "}"
)
RFC8785_VALUES_OUTPUT = (
    '{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],'
    '"string":"\u20ac$\\u000f\\nA\'B\\"\\\\\\\\\\"/"}'
)
RFC8785_SORTING_INPUT = (
    "{\n"
    '  "\\u20ac": "Euro Sign",\n'
    '  "\\r": "Carriage Return",\n'
    '  "\\ufb33": "Hebrew Letter Dalet With Dagesh",\n'
    '  "1": "One",\n'
    '  "\\ud83d\\ude00": "Emoji: Grinning Face",\n'
    '  "\\u0080": "Control",\n'
    '  "\\u00f6": "Latin Small Letter O With Diaeresis"\n'
    "}"
)
RFC8785_SORTED_VALUES = [
    "Carriage Return",
    "One",
    "Control",
    "Latin Small Letter O With Diaeresis",
    "Euro Sign",
    "Emoji: Grinning Face",
    "Hebrew Letter Dalet With Dagesh",
]
# RFC 8785, appendix B: IEEE 754 bits and the expected JSON number.
RFC8785_NUMBERS = [
    ("0000000000000000", "0", "zero"),
    ("8000000000000000", "0", "minus zero"),
    ("0000000000000001", "5e-324", "the smallest positive number"),
    ("8000000000000001", "-5e-324", "the smallest negative number"),
    ("7fefffffffffffff", "1.7976931348623157e+308", "the largest positive number"),
    ("ffefffffffffffff", "-1.7976931348623157e+308", "the largest negative number"),
    ("4340000000000000", "9007199254740992", "the largest positive integer of the RFC"),
    ("c340000000000000", "-9007199254740992", "the largest negative integer of the RFC"),
    ("4430000000000000", "295147905179352830000", "about 2^68"),
    ("7fffffffffffffff", None, "NaN"),
    ("7ff0000000000000", None, "Infinity"),
    ("44b52d02c7e14af5", "9.999999999999997e+22", None),
    ("44b52d02c7e14af6", "1e+23", None),
    ("44b52d02c7e14af7", "1.0000000000000001e+23", None),
    ("444b1ae4d6e2ef4e", "999999999999999700000", None),
    ("444b1ae4d6e2ef4f", "999999999999999900000", None),
    ("444b1ae4d6e2ef50", "1e+21", None),
    ("3eb0c6f7a0b5ed8c", "9.999999999999997e-7", None),
    ("3eb0c6f7a0b5ed8d", "0.000001", None),
    ("41b3de4355555553", "333333333.3333332", None),
    ("41b3de4355555554", "333333333.33333325", None),
    ("41b3de4355555555", "333333333.3333333", None),
    ("41b3de4355555556", "333333333.3333334", None),
    ("41b3de4355555557", "333333333.33333343", None),
    ("becbf647612f3696", "-0.0000033333333333333333", None),
    ("43143ff3c1cb0959", "1424953923781206.2", "rounded to even"),
]


def hashable_number_code(x: float) -> str:
    try:
        scratch_write(x, "hashable")
    except Refusal as refusal:
        return refusal.code
    return OK


def json_rfc8785() -> Builder:
    b = Builder(
        "json-rfc8785",
        "The examples of RFC 8785: the canonicalised example of sections 3.2.2 and 3.2.4, the "
        "sorting example of section 3.2.3 and the number serialisations of appendix B.",
    )
    case = b.reader(
        "RFC 8785, section 3.2.2. In the hashable profile, its first number has 17 significant "
        "digits.",
        RFC8785_VALUES_INPUT,
        modes(OK, OK, "E1103"),
        at="333333333.33333329",
    )
    assert case["expected"]["plain"]["canonical"] == RFC8785_VALUES_OUTPUT
    case = b.reader(
        "RFC 8785, section 3.2.3: members sorted by the UTF-16 code units of their keys, so that "
        "the key U+1F600 comes before U+FB33. The profiles refuse the key outside the BMP and the "
        "hashable profile, first, the key U+FB33, whose NFC form is U+05D3 U+05BC.",
        RFC8785_SORTING_INPUT,
        modes(OK, "E1108", "E1203"),
        at={"data": '"\\ud83d', "hashable": '"\\ufb33'},
    )
    values = list(json.loads(case["expected"]["plain"]["canonical"]).values())
    assert values == RFC8785_SORTED_VALUES
    for bits, text, comment in RFC8785_NUMBERS:
        x = double(bits)
        name = f"RFC 8785, appendix B: {bits}"
        if text is None:
            b.writer(
                f"{name}, {comment}, which has no JSON form. The data profile writes it as a "
                "string and the hashable profile refuses it.",
                modes(OK, OK, "E1107"),
                bits=bits,
                skip_plain=True,
            )
            continue
        assert es_number(x) == text, bits
        description = f"{name}, written {text}" + (f", {comment}" if comment else "") + "."
        b.writer(description, modes(OK, OK, hashable_number_code(x)), bits=bits)
    return b


def json_syntax() -> Builder:
    b = Builder(
        "json-syntax",
        "Inputs that the strict reader refuses in stages 1 and 3, before it checks any value: "
        "files, byte-order marks, unexpected ends, characters and trailing content, control "
        "characters and escapes in strings, non-finite literals, invalid numbers and nesting.",
    )
    r = b.reader
    r("A file that does not exist.", expect="E1001", file="missing")
    r("A directory in place of a file.", expect="E1002", file="directory")
    r("A byte-order mark before an object.", b"\xef\xbb\xbf{}", "E1003")
    r("A byte-order mark before a valid document.", b'\xef\xbb\xbf{"a":1}', "E1003")
    r("A byte-order mark is reported before a syntax error.", b"\xef\xbb\xbf[", "E1003")
    r("A byte-order mark is reported before invalid UTF-8.", b"\xef\xbb\xbf\xff", "E1003")
    r("A byte-order mark alone.", BOM, "E1003")
    r("Two byte-order marks.", BOM + BOM + b"1", "E1003")
    r("The UTF-16 little-endian byte-order mark is invalid UTF-8.", b"\xff\xfe{}", "E1201", at=0)
    r("The UTF-16 big-endian byte-order mark is invalid UTF-8.", b"\xfe\xff{}", "E1201", at=0)
    r("The first two bytes of a byte-order mark.", b"\xef\xbb{}", "E1201", at=0)
    r(
        "A byte-order mark after the first byte is the character U+FEFF where a value is expected.",
        "[\ufeff1]",
        "E1022",
        at=1,
    )
    r("A byte-order mark after white space.", " \ufeff{}", "E1022", at=1)
    r("JSON text encoded in UTF-16LE holds U+0000 after '{'.", b"{\x00}\x00", "E1022", at=1)
    r("An empty input.", "", "E1021", at=0)
    r("White space only.", "  \n\t\r", "E1021", at=5)
    r("An array that is not closed.", "[", "E1021", at=1)
    r("An object that is not closed.", "{", "E1021", at=1)
    r("An array that ends after a value.", "[1", "E1021", at=2)
    r("An array that ends after a comma.", "[1,", "E1021", at=3)
    r("An object that ends after a key.", '{"a"', "E1021", at=4)
    r("An object that ends after a colon.", '{"a":', "E1021", at=5)
    r("An object that ends after a member.", '{"a":1', "E1021", at=6)
    r("An object that ends after a comma.", '{"a":1,', "E1021", at=7)
    r("A string that is not closed.", '"abc', "E1021", at=4)
    r("A string that ends after a backslash.", '"\\', "E1021", at=2)
    r("A string that ends inside a \\u escape.", '"\\u12', "E1021", at=5)
    r("A truncated true.", "tru", "E1021", at=3)
    r("A truncated false inside an array.", "[fals", "E1021", at=5)
    r("A truncated null.", "nul", "E1021", at=3)
    r("A closing bracket where a value is expected.", "]", "E1022", at=0)
    r("A closing brace where a value is expected.", "}", "E1022", at=0)
    r("A comma where a value is expected.", ",", "E1022", at=0)
    r("A colon where a value is expected.", ":", "E1022", at=0)
    r("Two values in an array without a comma.", "[1 2]", "E1022", at="2")
    r("A trailing comma in an array.", "[1,]", "E1022", at="]")
    r("A leading comma in an array.", "[,1]", "E1022", at=",")
    r("Two commas in an array.", "[1,,2]", "E1022", at=3)
    r("A key without a colon.", '{"a" 1}', "E1022", at="1")
    r("A trailing comma in an object.", '{"a":1,}', "E1022", at="}")
    r("An unquoted key.", "{a:1}", "E1022", at="a")
    r("A key in single quotation marks.", "{'a':1}", "E1022", at="'")
    r("Two members without a comma.", '{"a":1 "b":2}', "E1022", at='"b"')
    r("A key without a value.", '{"a"}', "E1022", at="}")
    r("A colon without a value.", '{"a":}', "E1022", at="}")
    r("A colon in an array.", "[1:2]", "E1022", at=":")
    r("A comma after a key.", '{"a",1}', "E1022", at=",")
    r("A number as a key.", "{1:2}", "E1022", at="1")
    r("Two colons after a key.", '{"a"::1}', "E1022", at=5)
    r("A hexadecimal number in an array: the number 0 ends before 'x'.", "[0x1F]", "E1022", at="x")
    r("True with a capital letter.", "True", "E1022", at=0)
    r("A literal that differs at its second byte.", "tRue", "E1022", at=1)
    r("nan is compared with null and differs at its second byte.", "nan", "E1022", at=1)
    r("A literal that differs at its last byte.", "nulL", "E1022", at=3)
    r(
        "A literal that differs at a non-ASCII character, which the message names.",
        "n\u00fcll",
        "E1022",
        at=1,
    )
    r("undefined is not a JSON value.", "undefined", "E1022", at=0)
    r("Inf is not a literal that the reader names.", "Inf", "E1022", at=0)
    r("A comment.", "// comment\n1", "E1022", at=0)
    r("A block comment.", "/* c */ 1", "E1022", at=0)
    r("A string in single quotation marks.", "'a'", "E1022", at=0)
    r("A parenthesis.", "(1)", "E1022", at=0)
    r("A form feed is not white space.", "[1,\f2]", "E1022", at=3)
    r("A vertical tab is not white space.", "[1,\v2]", "E1022", at=3)
    r("A no-break space is not white space.", "[1,\u00a02]", "E1022", at=3)
    r("A line separator is not white space.", "[1,\u20282]", "E1022", at=3)
    r("A non-ASCII letter where a value is expected.", "[\u00e9]", "E1022", at=1)
    r("A raw U+0000 where a value is expected.", b"[1,\x00]", "E1022", at=3)
    r("Two numbers.", "1 2", "E1023", at=2)
    r("An extra closing bracket.", "[1]]", "E1023", at=3)
    r("Two objects.", "{}{}", "E1023", at=2)
    r("Two strings.", '"a""b"', "E1023", at=3)
    r("A hexadecimal number at the top level: the number 0 ends before 'x'.", "0x1F", "E1023", at=1)
    r("A literal followed by a letter.", "truex", "E1023", at=4)
    r("Two literals.", "nullnull", "E1023", at=4)
    r("A letter after white space.", "[1] x", "E1023", at=4)
    r("NaN after the top-level value is trailing content.", "1 NaN", "E1023", at=2)
    r("A raw U+0000 after the top-level value.", b"[1]\x00", "E1023", at=3)
    r("A raw tab in a string.", '"a\tb"', "E1024", at=2)
    r("A raw line feed in a string.", '"a\nb"', "E1024", at=2)
    r("A raw carriage return in a string.", '"a\rb"', "E1024", at=2)
    r("A raw U+001F in a string.", '"\x1f"', "E1024", at=1)
    r("A raw U+0000 in a string.", b'"\x00"', "E1024", at=1)
    r("A raw tab in a key.", '{"a\tb":1}', "E1024", at=3)
    r(
        "A raw U+007F is allowed in a string, and the next problem is the missing end.",
        '"\x7f',
        "E1021",
        at=2,
    )
    r("The escape \\x.", '"\\x41"', "E1025", at=1)
    r("The escape \\a.", '"\\a"', "E1025", at=1)
    r("An escaped single quotation mark.", '"\\\'"', "E1025", at=1)
    r("The escape \\U with a capital letter.", '"\\U0041"', "E1025", at=1)
    r("A \\u escape with a character that is not hexadecimal.", '"\\u12G4"', "E1025", at=1)
    r("A \\u escape with three digits before the end of the string.", '"\\u12"', "E1025", at=1)
    r("The escape \\0.", '"\\0"', "E1025", at=1)
    r("A backslash before a space.", '"\\ "', "E1025", at=1)
    r("A backslash before a raw line feed.", '"\\\n"', "E1025", at=1)
    r("The second escape of a surrogate pair has three digits.", '"\\uD83D\\uDE0"', "E1025", at=7)
    r("An invalid escape in a key.", '{"\\q":1}', "E1025", at=2)
    r("NaN.", "NaN", "E1027", at=0)
    r("Infinity.", "Infinity", "E1027", at=0)
    r("-Infinity.", "-Infinity", "E1027", at=0)
    r("NaN in an array.", "[1,NaN]", "E1027", at=3)
    r("-Infinity as a member's value.", '{"a":-Infinity}', "E1027", at=5)
    r("Input that begins with NaN.", "NaNx", "E1027", at=0)
    r("Input that begins with Infinity.", "Infinityx", "E1027", at=0)
    r("A leading zero.", "01", "E1028", at=0)
    r("A negative number with a leading zero.", "-01", "E1028", at=0)
    r("Two zeros.", "00", "E1028", at=0)
    r("A point without a fraction.", "1.", "E1028", at=0)
    r("A fraction without an integer part.", ".5", "E1028", at=0)
    r("A plus sign.", "+1", "E1028", at=0)
    r("An exponent without digits.", "1e", "E1028", at=0)
    r("An exponent with a sign and no digits.", "1e+", "E1028", at=0)
    r("A capital E with a sign and no digits.", "1E-", "E1028", at=0)
    r("A minus sign alone.", "-", "E1028", at=0)
    r("Two minus signs.", "--1", "E1028", at=0)
    r("Two points.", "1..2", "E1028", at=0)
    r("Two fractions.", "1.2.3", "E1028", at=0)
    r("Two exponents.", "1e5e5", "E1028", at=0)
    r("A point before an exponent.", "2.e3", "E1028", at=0)
    r("A minus sign inside a number.", "1-2", "E1028", at=0)
    r("A plus sign inside a number.", "1+2", "E1028", at=0)
    r("A negative fraction without an integer part.", "-.5", "E1028", at=0)
    r("A fractional exponent.", "1e1.5", "E1028", at=0)
    r("Two signs in an exponent.", "1.0E+-2", "E1028", at=0)
    r("A minus sign alone in an array.", "[1,-]", "E1028", at=3)
    r("-Inf is a minus sign followed by a letter.", "-Inf", "E1028", at=0)
    r("-NaN is a minus sign followed by a letter.", "-NaN", "E1028", at=0)
    r(
        "A run of 70 zeros, named in the message by its first 57 characters.",
        "0" * 70,
        "E1028",
        at=0,
    )
    deep = "[" * 64 + "1" + "]" * 64
    r("Arrays nested 64 deep are accepted.", deep, OK)
    r("Arrays nested 65 deep.", "[" * 65 + "]" * 65, "E1030", at=64)
    objects = '{"a":' * 65 + "1" + "}" * 65
    r("Objects nested 65 deep.", objects, "E1030", at=5 * 64)
    mixed = '[{"a":' * 32 + "[" + "1]" + "}]" * 32
    r("Arrays and objects nested 65 deep.", mixed, "E1030", at=6 * 32)
    r(
        "An unclosed nesting of 65 arrays reports the depth before the end.",
        "[" * 65,
        "E1030",
        at=64,
    )
    r(
        "A syntax error before the 65th level is reported first.",
        "[" * 10 + "," + "[" * 60,
        "E1022",
        at=10,
    )
    r("A value that starts with 'e', which does not start a number.", "[e]", "E1022", at=1)
    r("A word that starts with 'e' at the top level.", "e1", "E1022", at=0)
    r("A word that starts with 'E' at the top level.", "E5", "E1022", at=0)
    r("An exponent without a mantissa in an array.", "[E-1]", "E1022", at=1)
    r("An exponent without a mantissa as a member's value.", '{"a":e2}', "E1022", at=5)
    r(
        "An unquoted word that starts with 'e' as a member's value.",
        '{"goal": exploratory}',
        "E1022",
        at=9,
    )
    return b


def json_values() -> Builder:
    b = Builder(
        "json-values",
        "Inputs that the strict reader refuses in stage 4, when it checks keys, strings and "
        "null in the order of the input, with the precedence of syntax errors over value errors.",
    )
    r = b.reader
    r("A duplicate key.", '{"a":1,"a":2}', "E1029", at=7)
    r("A duplicate key written with an escape.", '{"a":1,"\\u0061":2}', "E1029", at=7)
    r("A duplicate key after another member.", '{"a":1,"b":2,"a":3}', "E1029", at=13)
    r("Equal keys in different objects are allowed.", '{"a":{"a":1},"b":{"a":2}}')
    r("Equal keys in objects of an array are allowed.", '[{"x":1},{"x":1}]')
    r("Keys that differ in case are different.", '{"A":1,"a":2}')
    r(
        "Keys that are equal after NFC are different keys, but the hashable profile refuses the "
        "second, which is not in NFC.",
        '{"\u00e9":1,"e\u0301":2}',
        modes(OK, OK, "E1203"),
        at=8,
    )
    r(
        "A duplicate key that is not in NFC: the hashable profile refuses the first, and the "
        "other modes report the duplicate.",
        '{"e\u0301":1,"e\u0301":2}',
        modes("E1029", "E1029", "E1203"),
        at={"plain": 9, "data": 9, "hashable": 1},
    )
    pad = '{"x":"abcdefghijklmnopqrstuvwxyz",'
    r(
        "The example of errors.md: a duplicate key that holds a tab, at byte 45.",
        pad + '"go\\tal":1,"go\\tal":2}',
        "E1029",
        at=45,
    )
    r(
        "A duplicate key of 70 characters, named in the message by its first 57.",
        '{"' + "k" * 70 + '":1,"' + "k" * 70 + '":2}',
        "E1029",
        at=76,
    )
    r("An escaped U+0000 in a key.", '{"\\u0000":1}', "E1202", at=1)
    r("An empty key.", '{"":1}', "E1109", at=1)
    r("Two empty keys: the first is reported.", '{"":1,"":2}', "E1109", at=1)
    r(
        "A key outside the BMP, written as UTF-8, which only the plain mode accepts.",
        '{"\U0001f600":1}',
        modes(OK, "E1108"),
        at=1,
    )
    r(
        "A key outside the BMP, written as a surrogate pair.",
        '{"\\ud83d\\ude00":1}',
        modes(OK, "E1108"),
        at=1,
    )
    r(
        "A key outside the BMP, written as a surrogate pair in capital letters.",
        '{"\\uD83D\\uDE00":1}',
        modes(OK, "E1108"),
        at=1,
    )
    r("A key with an unpaired high surrogate.", '{"\\ud800":1}', "E1026", at=1)
    r(
        "In a key, an unpaired surrogate is reported before U+0000.",
        '{"\\u0000\\ud800":1}',
        "E1026",
        at=1,
    )
    r(
        "In a key, a character outside the BMP is reported before NFC.",
        '{"\U0001f600e\u0301":1}',
        modes(OK, "E1108", "E1108"),
        at=1,
    )
    r(
        "In a key, an unassigned code point is reported before NFC.",
        '{"\\u0378e\\u0301":1}',
        modes(OK, OK, "E1208"),
        at=1,
    )
    r("A key that is a noncharacter.", '{"\\uffff":1}', modes(OK, OK, "E1208"), at=1)
    r("An unpaired high surrogate.", '"\\ud800"', "E1026", at=0)
    r("An unpaired low surrogate.", '"\\udc00"', "E1026", at=0)
    r(
        "A high surrogate followed by an escape that is not a low surrogate.",
        '"\\ud800\\u0041"',
        "E1026",
        at=0,
    )
    r("A high surrogate followed by a character.", '"\\ud800x"', "E1026", at=0)
    r("Two high surrogates.", '"\\ud800\\ud800"', "E1026", at=0)
    r("A low surrogate before a high surrogate.", '"\\udc00\\ud800"', "E1026", at=0)
    r(
        "A high surrogate at the end of a longer string, located at its quotation mark.",
        '"a\\ud800"',
        "E1026",
        at=0,
    )
    r("An unpaired surrogate in the second item.", '["ok","\\udfff"]', "E1026", at=6)
    r("A high surrogate followed by a non-ASCII character.", '"\\ud800\u00e9"', "E1026", at=0)
    r("A surrogate pair is U+10000, which every mode accepts.", '"\\ud800\\udc00"')
    r("An escaped U+0000 in a string.", '"a\\u0000b"', "E1202", at=0)
    r("An escaped U+0000 alone.", '"\\u0000"', "E1202", at=0)
    r("An escaped U+0000 in the second item.", '["x","\\u0000"]', "E1202", at=5)
    r(
        "In a string, an unpaired surrogate is reported before U+0000.",
        '"\\u0000\\ud800"',
        "E1026",
        at=0,
    )
    r(
        "A string in NFD, which only the hashable profile refuses.",
        '"e\u0301"',
        modes(OK, OK, "E1203"),
        at=0,
    )
    r("A string in NFD written with an escape.", '"e\\u0301"', modes(OK, OK, "E1203"), at=0)
    r("The noncharacter U+FFFF, written as UTF-8.", '"\uffff"', modes(OK, OK, "E1208"), at=0)
    r("The noncharacter U+FDD0, written as an escape.", '"\\ufdd0"', modes(OK, OK, "E1208"), at=0)
    r("U+0378, unassigned in Unicode 14.0.", '"\\u0378"', modes(OK, OK, "E1208"), at=0)
    r("U+E000, a private-use character, which Unicode assigns.", '"\\ue000"')
    r("U+10FFFF, a noncharacter.", '"\\udbff\\udfff"', modes(OK, OK, "E1208"), at=0)
    r(
        "The example of conventions.md: 'x', U+1E4EC and U+0316. U+1E4EC was assigned in "
        "Unicode 15.0.",
        '"x\\ud838\\udcec\\u0316"',
        modes(OK, OK, "E1208"),
        at=0,
    )
    r("null at the top level.", "null", modes(OK, OK, "E1101"), at=0)
    r("null in an array.", "[1,null]", modes(OK, OK, "E1101"), at=3)
    r("null as a member's value.", '{"a":null}', modes(OK, OK, "E1101"), at=5)
    r("null nested in an array of an object.", '{"a":[true,null]}', modes(OK, OK, "E1101"), at=11)
    r("A syntax error after a null is reported first.", "[null,1,]", "E1022", at=8)
    r(
        "The end of the input after an unpaired surrogate is reported first.",
        '["\\ud800",tru',
        "E1021",
        at=13,
    )
    r("An unpaired surrogate before a number that overflows.", '["\\ud800",1e400]', "E1026", at=1)
    r(
        "A number that overflows before an unpaired surrogate. The hashable profile refuses it "
        "as an integer out of range.",
        '[1e400,"\\ud800"]',
        modes("E1105", "E1105", "E1102"),
        at=1,
    )
    r("A null before a string in NFD.", '[null,"e\u0301"]', modes(OK, OK, "E1101"), at=1)
    r("A string in NFD before a null.", '["e\u0301",null]', modes(OK, OK, "E1203"), at=1)
    r(
        "A null before a key outside the BMP.",
        '{"a":null,"\U0001f600":1}',
        modes(OK, "E1108", "E1101"),
        at={"data": 10, "hashable": 5},
    )
    r(
        "A key outside the BMP before its null value.",
        '{"\U0001f600":null}',
        modes(OK, "E1108"),
        at=1,
    )
    r("A duplicate key is reported before its value.", '{"a":1,"a":"\\ud800"}', "E1029", at=7)
    r("A value is reported before a later duplicate key.", '{"a":"\\ud800","a":1}', "E1026", at=5)
    return b


def json_canonical() -> Builder:
    b = Builder(
        "json-canonical",
        "Inputs that the strict reader accepts, with their canonical bytes and hashes: white "
        "space, scalars, empty containers, the order of members, escapes, nesting, the worked "
        "example of conventions.md and the edge files of the evidence for the decisions.",
    )
    r = b.reader
    case = r(
        "The worked example of conventions.md (Serialisation).",
        "{\n"
        '  "title": "caf\\u00e9 \\"study\\"",\n'
        '  "n": [1.0, 1e2, 0.000001, 1E-7, 4.50, -0, 25e-1],\n'
        '  "a": {"z": true, "b": false, "\u00e9": "\\u00e9"},\n'
        '  "tab": "a\\tb\\u001f"\n'
        "}\n",
    )
    worked = case["expected"]["hashable"]
    assert len(worked["canonical"].encode("utf-8")) == 117
    assert worked["sha256"].endswith(
        "288afb1eec38acd97fc29eb68a97d9200dd6e77da5ee06d7586945b51372b80d"
    )
    r("White space of every kind around every token.", '\r\n\t {\t"a" :\n[ 1 ,\r2 ] } \n\r\t')
    r("A string at the top level.", '"x"')
    r("An empty string.", '""')
    r("true at the top level.", "true")
    r("false at the top level.", " false ")
    r("Zero at the top level.", "0")
    r("Negative zero is written as 0.", "-0")
    r("An empty object.", "{}")
    r("An empty array.", "[]")
    r("Empty containers inside containers.", '{"a":{},"b":[],"c":[[],{}]}')
    r(
        "Keys sorted by code unit: digits, upper case, '_' and lower case, with a prefix first.",
        '{"b":1,"a":2,"B":3,"A":4,"_":5,"1":6,"10":7,"9":8,"aa":9,"a1":10}',
    )
    r("Members of nested objects are sorted too.", '{"z":{"y":1,"x":{"b":1,"a":2}},"a":0}')
    r("Arrays keep their order.", '[3,1,2,"b","a",{"b":1,"a":2}]')
    r(
        "Sorting ignores language: 'peach', 'p\u00e9ch\u00e9', 'p\u00eache' and 'sin' in code "
        "point order.",
        '{"sin":4,"p\u00eache":3,"p\u00e9ch\u00e9":2,"peach":1}',
    )
    r(
        "Escapes written as two characters.",
        '"\\u0008\\u0009\\u000a\\u000c\\u000d\\u0022\\u005c"',
    )
    controls = "".join(f"\\u{point:04x}" for point in range(1, 0x20))
    r("Every control character from U+0001 to U+001F.", f'"{controls}"')
    r(
        "U+007F, U+0080, U+009F, U+2028, U+2029 and U+FEFF are written as UTF-8.",
        '"\\u007f\\u0080\\u009f\\u2028\\u2029\\ufeff"',
    )
    r("An escaped solidus is written as '/'.", '"a\\/b"')
    r("An escape in capital letters.", '"\\u00C9"')
    r("An escaped and a raw '\u00e9' give the same bytes.", '["\\u00e9","\u00e9"]')
    r("A character outside the BMP from a surrogate pair is written as UTF-8.", '"\\ud83d\\ude00"')
    r("Quotation marks and backslashes.", '"\\"\\\\\\"\\\\"')
    r(
        "In the plain mode, keys are sorted by UTF-16 code units: U+1F600 (D83D DE00) before "
        "U+FF08.",
        '{"\\uff08":1,"\\ud83d\\ude00":2}',
        modes(OK, "E1108"),
        at={"data": '"\\ud83d'},
    )
    r(
        "In the plain mode, U+1F600 (D83D DE00) comes before U+E000.",
        '{"\\ue000":1,"\\ud83d\\ude00":2}',
        modes(OK, "E1108"),
        at={"data": '"\\ud83d'},
    )
    r("Keys of the BMP above U+00FF.", '{"\\uffee":1,"\\u0100":2,"\\u00ff":3,"\\ue000":4}')
    r("Distinct keys that differ by a space.", '{"a":1,"a ":2," a":3}')
    r(
        "Numbers of several forms.",
        "[1.0,1e2,0.000001,1E-7,4.50,-0,25e-1,100,1e+2,-1.5e-3,0.1,123.456]",
    )
    r("A deeply nested object and array.", '{"a":[{"b":[{"c":[]}]}]}')
    evidence = ROOT / "docs" / "design" / "evidence" / "decisions"
    edge_files = [
        ("E-verify/edge/e5_small_numbers.json", modes(OK, OK, "E1104")),
        ("E-verify/edge/e6_large_numbers.json", modes(OK, OK, "E1102")),
        ("E-verify/edge/e7_big_int.json", modes(OK, OK, "E1102")),
        ("E-verify/edge/e8_supplementary_key_order.json", modes(OK, "E1108")),
        ("E-verify/edge/e9_lone_surrogate.json", "E1026"),
        ("E-verify/edge/e10_number_layout.json", modes(OK, OK, "E1103")),
        ("E-verify/edge/e11_empty_containers.json", OK),
        ("E-verify/edge/e12_escapes.json", OK),
        ("E/schema/edge/edge1_canonical.json", OK),
        ("E/schema/edge/edge2_nfd.json", modes(OK, OK, "E1203")),
        ("E/schema/edge/edge3_bom.json", "E1003"),
        ("E/schema/edge/edge4_nan.json", "E1027"),
    ]
    notes = {
        "e5_small_numbers.json": "5e-324 lies below 1e-307 in the hashable profile",
        "e6_large_numbers.json": "1e21 is an integer outside the range of the hashable profile",
        "e7_big_int.json": "9007199254740993 lies outside the hashable profile",
        "e8_supplementary_key_order.json": "a key outside the BMP",
        "e9_lone_surrogate.json": "an unpaired surrogate",
        "e10_number_layout.json": "1.0000000000000002 has 17 significant digits",
        "e11_empty_containers.json": "empty containers",
        "e12_escapes.json": "a line separator, a non-ASCII letter and an escaped control character",
        "edge1_canonical.json": "a mixture of numbers, keys, escapes and characters",
        "edge2_nfd.json": "a string in NFD",
        "edge3_bom.json": "a byte-order mark",
        "edge4_nan.json": "NaN",
    }
    for relative, expect in edge_files:
        name = relative.rsplit("/", 1)[1]
        data = (evidence / relative).read_bytes()
        r(
            f"The edge file {relative} of the evidence for the decisions, as stored: "
            f"{notes[name]}.",
            data,
            expect,
        )
    members = ",".join(f'"member_{i:04d}":{i}' for i in reversed(range(1000)))
    r(
        "An object of 1,000 members in reverse order, whose keys joined together take more than "
        "the 10,000 bytes that R allows in the name of a variable.",
        "{" + members + "}",
    )
    return b


def json_writer() -> Builder:
    b = Builder(
        "json-writer",
        "Values in memory and their canonical bytes, or the first issue in the order of the "
        "canonical serialisation, with its JSON Pointer.",
    )
    w = b.writer
    w(
        "An object with every kind of value. Only the hashable profile refuses its null.",
        modes(OK, OK, "E1101"),
        json_text='{"b":1,"a":[true,false,null],"c":"x"}',
        at="/a/2",
    )
    w(
        "Checks follow the canonical order of members, so the string in NFD under 'a' is "
        "reported before the null under 'b'.",
        modes(OK, OK, "E1203"),
        json_text='{"b":null,"a":"e\\u0301"}',
        at="/a",
    )
    w(
        "A key is checked before its value, at the pointer of its member.",
        modes(OK, OK, "E1203"),
        json_text='{"e\\u0301":null}',
        at="/e\u0301",
    )
    w(
        "Members are checked in the order of UTF-16 code units, so the key U+1F600 comes before "
        "the null under U+FF08.",
        modes(OK, "E1108", "E1108"),
        json_text='{"\\uff08":null,"\\ud83d\\ude00":1}',
        at="/\U0001f600",
    )
    w(
        "A key outside the BMP in a nested object.",
        modes(OK, "E1108"),
        json_text='{"a":{"\\ud83d\\ude00":1}}',
        at="/a/\U0001f600",
    )
    w(
        "NaN and the infinities: the data profile writes them as strings, and the hashable "
        "profile refuses the first.",
        modes(OK, OK, "E1107"),
        json_text="[1,0,0,0]",
        substitutions=[
            {"pointer": "/1", "double": nan_bits("NaN")},
            {"pointer": "/2", "double": nan_bits("Infinity")},
            {"pointer": "/3", "double": nan_bits("-Infinity")},
        ],
        at="/1",
        skip_plain=True,
    )
    w(
        "NaN as a member's value beside a null.",
        modes(OK, OK, "E1101"),
        json_text='{"y":0,"x":null}',
        substitutions=[{"pointer": "/y", "double": nan_bits("NaN")}],
        at="/x",
        skip_plain=True,
    )
    w(
        "A NaN under the key 'b' and a null under 'a': the null comes first in canonical order.",
        modes(OK, OK, "E1101"),
        json_text='{"b":0,"a":null}',
        substitutions=[{"pointer": "/b", "double": nan_bits("NaN")}],
        at="/a",
        skip_plain=True,
    )
    w("Negative zero is written as 0.", json_text="[-0.0,-0]")
    w("Integral doubles are written without a fraction.", json_text="[1.0,100.0,1e2,-5.0]")
    w(
        "The largest integers of the hashable profile.",
        json_text="[9007199254740991,-9007199254740991]",
    )
    w(
        "2^53 lies outside the range of the hashable profile.",
        modes(OK, OK, "E1102"),
        json_text="[9007199254740992]",
        at="/0",
    )
    w(
        "1e21 is an integer, and the message names it as the serialiser writes it.",
        modes(OK, OK, "E1102"),
        json_text="[1e21]",
        at="/0",
    )
    w(
        "0.1 + 0.2 has 17 significant digits.",
        modes(OK, OK, "E1103"),
        json_text="[0.1,0.30000000000000004]",
        at="/1",
    )
    w("1e-307 is the smallest magnitude allowed.", json_text="[1e-307,-1e-307]")
    w(
        "1e-308 is below 1e-307.",
        modes(OK, OK, "E1104"),
        json_text="[1e-307,1e-308]",
        at="/1",
    )
    w(
        "The largest subnormal double has 16 significant digits, which is reported before its "
        "magnitude.",
        modes(OK, OK, "E1103"),
        json_text="[2.225073858507201e-308]",
        at="/0",
    )
    w(
        "Large doubles in the data profile.",
        modes(OK, OK, "E1102"),
        json_text="[1e300,-1.5e-300]",
        at="/0",
    )
    w(
        "A pointer escapes '/' as '~1' and '~' as '~0'.",
        modes(OK, OK, "E1101"),
        json_text='{"a/b":{"m~n":null}}',
        at="/a~1b/m~0n",
    )
    w(
        "The message escapes a tab in the pointer, which holds the tab itself.",
        modes(OK, OK, "E1101"),
        json_text='{"go\\tal":null}',
        at="/go\tal",
    )
    w(
        "An unassigned code point in the hashable profile.",
        modes(OK, OK, "E1208"),
        json_text='["\\u0378"]',
        at="/0",
    )
    w(
        "Escapes in strings.",
        json_text='["\\u0001\\u001f\\"\\\\/\\u007f\\u2028\\b\\f\\n\\r\\t"]',
    )
    w(
        "A Python int of 2^53 - 1.",
        json_text="[0]",
        substitutions=[py_int("/0", "9007199254740991")],
        languages=["Python"],
        skip_plain=True,
    )
    w(
        "A Python int of 2^53, which no profile accepts, since it would be converted to a double.",
        "E1102",
        json_text="[0]",
        substitutions=[py_int("/0", "9007199254740992")],
        languages=["Python"],
        at="/0",
        skip_plain=True,
    )
    w(
        "A negative Python int of 30 digits.",
        "E1102",
        json_text='{"n":0}',
        substitutions=[py_int("/n", "-" + "9" * 30)],
        languages=["Python"],
        at="/n",
        skip_plain=True,
    )
    deep = "[" * 64 + "1" + "]" * 64
    w("A value nested 64 deep.", json_text=deep)
    w(
        "A value nested 65 deep, after the 64-deep value is placed in an array.",
        "E1030",
        json_text=deep,
        substitutions=[{"pointer": "", "wrap": 1}],
        at="/0" * 64,
    )
    w(
        "An object nested 65 deep.",
        "E1030",
        json_text='{"a":' * 64 + "1" + "}" * 64,
        substitutions=[{"pointer": "", "wrap": 1}],
        at="/0" + "/a" * 63,
    )
    return b


# numbers/ -------------------------------------------------------------------------


def _bits_case(builder: Builder, description: str, x: float) -> None:
    bits = bits_of(x)
    if math.isnan(x) or math.isinf(x):
        builder.writer(description, modes(OK, OK, "E1107"), bits=bits, skip_plain=True)
    else:
        builder.writer(description, modes(OK, OK, hashable_number_code(x)), bits=bits)


def numbers_format() -> Builder:
    b = Builder(
        "numbers-format",
        "Doubles given by their IEEE 754 bits, with the string that ECMAScript's "
        "Number::toString gives for them and, in the hashable profile, the writer's issue for "
        "those it refuses.",
    )
    seen: set[str] = {bits for bits, _, _ in RFC8785_NUMBERS}

    def add(description: str, x: float) -> None:
        bits = bits_of(x)
        if bits in seen:
            return
        seen.add(bits)
        if not (math.isnan(x) or math.isinf(x)):
            description = f"{description} Written {es_number(x)}."
        _bits_case(b, description, x)

    add("One.", 1.0)
    add("Minus one.", -1.0)
    add("One half: n = 0.", 0.5)
    add("n = -1.", 0.05)
    add("Five: k = n.", 5.0)
    add("Fifty: n > k.", 50.0)
    add("A fraction with 0 < n.", 123.456)
    add("100 has no fraction.", 100.0)
    add("10^15.", 1e15)
    add("10^16, which Python writes with an exponent.", 1e16)
    add("10^17.", 1e17)
    add("10^20: n = 21, the last plain integer.", 1e20)
    add("A 21-digit integer.", 123456789012345680000.0)
    add("1.2345678901234568 × 10^21: n = 22.", 1.2345678901234568e21)
    add("1.5 × 10^21.", 1.5e21)
    add("10^22.", 1e22)
    add("10^100.", 1e100)
    add("10^-5.", 1e-5)
    add("1.5 × 10^-6: n = -5, the last plain form.", 1.5e-6)
    add("1.2345 × 10^-6.", 1.2345e-6)
    add("1.5 × 10^-7: n = -6, the first exponent form.", 1.5e-7)
    add("10^-7.", 1e-7)
    add("The double after 10^-7.", math.nextafter(1e-7, 1.0))
    add("0.00001234.", 0.00001234)
    add("10^-100.", 1e-100)
    add("1.5 × 10^-10.", 1.5e-10)
    add("0.1.", 0.1)
    add("0.2.", 0.2)
    add("0.3.", 0.3)
    add("0.1 + 0.2.", 0.1 + 0.2)
    add("1/3.", 1 / 3)
    add("2/3.", 2 / 3)
    add("0.7.", 0.7)
    add("1.1.", 1.1)
    add("2.675.", 2.675)
    add("4.35.", 4.35)
    add("The double after 1.", math.nextafter(1.0, 2.0))
    add("The double before 1.", math.nextafter(1.0, 0.0))
    add("The double after 0.1.", math.nextafter(0.1, 1.0))
    add("The double before 0.1.", math.nextafter(0.1, 0.0))
    add("123456789.123456789 rounded to a double.", 123456789.123456789)
    add("A 15-digit fraction, which the hashable profile accepts.", 0.123456789012345)
    add("A 16-digit fraction.", 0.1234567890123456)
    add("99999999999999.9 has 15 digits.", 99999999999999.9)
    add("123456789012345.6 has 16 digits.", 123456789012345.6)
    add("2^51 + 0.5.", 2251799813685248.5)
    add("2^52 - 0.5.", 4503599627370495.5)
    add("2^53 - 2.", 9007199254740990.0)
    add("2^53 - 1, the largest integer of the hashable profile.", 9007199254740991.0)
    add("-(2^53 - 1).", -9007199254740991.0)
    add("2^53 + 2.", 9007199254740994.0)
    add("2^53 + 4.", 9007199254740996.0)
    add("2^54.", 18014398509481984.0)
    add("2^54 + 4.", 18014398509481988.0)
    add("10^16 + 2.", 10000000000000002.0)
    add("2^60.", float(2**60))
    add("2^63.", float(2**63))
    add("2^64.", float(2**64))
    add("12345678901234567890 rounded to a double.", 12345678901234567890.0)
    add("The smallest positive normal double.", double("0010000000000000"))
    add("The double after the smallest normal double.", double("0010000000000001"))
    add("Twice the smallest subnormal double.", double("0000000000000002"))
    add("Three times the smallest subnormal double.", double("0000000000000003"))
    add("A subnormal double: 2^-1064.", double("0000000000000400"))
    add("A subnormal double: 2^-1023.", double("0008000000000000"))
    add("The largest subnormal double.", double("000fffffffffffff"))
    add("The largest negative subnormal double.", double("800fffffffffffff"))
    add("A subnormal double with many digits.", double("000123456789abcd"))
    add("10^-307.", 1e-307)
    add("The double before 10^-307.", math.nextafter(1e-307, 0.0))
    add("10^-308, a subnormal double.", 1e-308)
    add("-1.5 × 10^-308.", -1.5e-308)
    add("The largest double before the largest.", math.nextafter(double("7fefffffffffffff"), 0.0))
    add("10^308.", 1e308)
    add("1.5 × 10^300.", 1.5e300)
    add("2^1023.", math.ldexp(1.0, 1023))
    add("2^-1022.", math.ldexp(1.0, -1022))
    add("A quiet NaN.", double("7ff8000000000000"))
    add("A quiet NaN with the sign bit set.", double("fff8000000000000"))
    add("Negative infinity.", double("fff0000000000000"))
    for exponent in naive_failures():
        add(
            f"2^{exponent}, where formatting with increasing precision and stopping at the "
            "first round trip gives one digit too many.",
            math.ldexp(1.0, exponent),
        )
    return b


def naive_failures() -> list[int]:
    """The powers of two for which the loop over '%.{p}e' is not shortest."""

    def naive(x: float) -> str:
        for precision in range(1, 18):
            text = f"{x:.{precision - 1}e}"
            if float(text) == x:
                return text
        raise AssertionError(x)

    found = []
    for exponent in range(-1074, 1024):
        x = math.ldexp(1.0, exponent)
        if significant_digits(naive(x)) > significant_digits(repr(x)):
            found.append(exponent)
    assert len(found) == 46 and -1017 in found
    return found


AS_NUMERIC_MISCONVERSIONS = [
    # The examples of conventions.md.
    "-76944133.284736",
    "7.32e-97",
    "-6.1892785e-12",
    # Found by comparing R 4.3.3's as.numeric() on Linux with Python's float().
    "18363346.2855308",
    "2524183.197988",
    "-734498.79320267",
    "-567787.541287",
    "105508.170112410",
    "-9.9538354",
    "-23.0696040",
    "9.04554531e-198",
    "-5.6674e-247",
    "4.82374355e-153",
    "-8.1963553721e-150",
    "-1.489051704e-37",
    "3.38451386850241e-25",
    "-1.4e-260",
    "6.31418e-299",
    "-5.6503630680e-154",
    "-1.7591166e-214",
    "-8.5e-276",
    "-9.7e-200",
    "-5.6e-260",
    "-7e-261",
    "9.433e-178",
    "-4.1604293523e-303",
    "1.644e-117",
    "-2.7976304e-97",
    "-6.84e-86",
    "-5.49056905057172e-244",
    "2.76854318123760e-243",
    "-8e126",
    "7.29375148e291",
    "-3.6498925210481e267",
    "6.214174e173",
    "9.60022e201",
    "3.115712e144",
    "3.704514100740427e-152",
    "-7.049819869642031e+230",
    "-5.86824538131268e+268",
    "2.104380188383035e-306",
    "-3.856096668441545e-241",
    "2.744653427217277e-258",
    "-9.81910588847971e-276",
    "-6.870709112140226e+295",
]


def exact_decimal(x: Fraction, digits: int = 1200) -> str:
    """The exact decimal expansion of a dyadic rational, in plain notation."""
    with localcontext() as context:
        context.prec = digits
        value = Decimal(x.numerator) / Decimal(x.denominator)
        assert Fraction(value) == x
        text = format(value, "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


def numbers_read() -> Builder:
    b = Builder(
        "numbers-read",
        "Number tokens read in each mode: the value as a double, its canonical form and the "
        "rules of the hashable profile and of correctly rounded conversion.",
    )

    def r(description: str, token: str, expect: str | dict = OK) -> None:
        b.reader(description, token, expect, at=0, bits=True)

    for token in [
        "0", "-0", "0.0", "-0.0", "0e0", "0E+5", "-0e-5", "1", "-1", "1.0", "1e0", "1E2",
        "1e+2", "1e-2", "4.50", "25e-1", "0.000001", "1E-7", "100.000", "1e007", "1e-007",
        "123.456e1", "0.5e1",
    ]:  # fmt: skip
        r(f"The token {token}.", token)
    hashable = [
        ("99999999999999", OK, "an integer with p = 13"),
        ("999999999999999", OK, "an integer with p = 14"),
        ("9007199254740991", OK, "2^53 - 1"),
        ("-9007199254740991", OK, "-(2^53 - 1)"),
        ("1e15", OK, "10^15, an integer with p = 15 within the range"),
        ("9.007199254740991e15", OK, "2^53 - 1 with an exponent"),
        ("9007199254740991.0", OK, "2^53 - 1 with a zero fraction"),
        ("0.1e1", OK, "the integer 1 written with a fraction and an exponent"),
        ("10000000000000000000000e-10", OK, "10^12 written with 23 digits"),
        ("100000000000000000000000000000e-14", OK, "10^15 written with 30 digits"),
        ("9007199254740992", "E1102", "2^53"),
        ("-9007199254740992", "E1102", "-2^53"),
        ("9.007199254740992e15", "E1102", "2^53 with an exponent"),
        ("1e16", "E1102", "10^16"),
        ("1e21", "E1102", "10^21, an integer of one significant digit"),
        ("1.5e300", "E1102", "an integer of two significant digits"),
        ("12345678901234567890", "E1102", "a 20-digit integer"),
        ("9007199254740991.5", "E1103", "a non-integer of 17 significant digits"),
        ("1.23456789012345", OK, "15 significant digits"),
        ("1.23456789012345000000", OK, "15 significant digits and trailing zeros"),
        ("1.234567890123456", "E1103", "16 significant digits"),
        ("1.2345678901234560", "E1103", "16 significant digits and a trailing zero"),
        ("123456789012345.6", "E1103", "16 significant digits"),
        ("0.1000000000000000000001", "E1103", "22 significant digits"),
        ("0.30000000000000004", "E1103", "0.1 + 0.2"),
        ("333333333.33333329", "E1103", "the first number of RFC 8785, section 3.2.2"),
        ("0.000000000000000000000000001", OK, "10^-27"),
        ("1e-307", OK, "the smallest magnitude allowed"),
        ("1.0e-307", OK, "10^-307 with a fraction"),
        ("-1e-307", OK, "-10^-307"),
        ("1e-308", "E1104", "10^-308"),
        ("-1e-308", "E1104", "-10^-308"),
        ("1.5e-308", "E1104", "p = -308"),
        ("9.99e-308", "E1104", "just below 10^-307"),
        ("5e-324", "E1104", "the smallest subnormal double"),
        ("2.2250738585072014e-308", "E1103", "the smallest normal double, with 17 digits"),
        ("1.234567890123456e-310", "E1103", "16 digits, which are reported before the magnitude"),
    ]
    for token, code, note in hashable:
        r(f"The token {token}: {note}.", token, modes(OK, OK, code))
    long_token = "0.1" + "0" * 800 + "1"
    r(
        "A token of 805 characters just above 0.1. Its message is truncated.",
        long_token,
        modes(OK, OK, "E1103"),
    )
    r("10^1000000000000 overflows.", "1e1000000000000", modes("E1105", "E1105", "E1102"))
    r("-10^1000000000000 overflows.", "-1e1000000000000", modes("E1105", "E1105", "E1102"))
    r("10^-1000000000000 underflows.", "1e-1000000000000", modes("E1106", "E1106", "E1104"))
    r("Zero with a huge exponent is zero.", "0e1000000000000")
    r("Zero with a huge negative exponent is zero.", "0.0e-1000000000000")
    r("An exponent of 401 digits whose value is 1.", "1e" + "0" * 400 + "1")
    r("1e400 overflows.", "1e400", modes("E1105", "E1105", "E1102"))
    r("1e-400 underflows.", "1e-400", modes("E1106", "E1106", "E1104"))
    r("1e-324 underflows.", "1e-324", modes("E1106", "E1106", "E1104"))
    r("The largest double.", "1.7976931348623157e308", modes(OK, OK, "E1102"))
    r(
        "A decimal that rounds down to the largest double.",
        "1.7976931348623158e308",
        modes(OK, OK, "E1102"),
    )
    r(
        "A decimal that rounds up to infinity.",
        "1.7976931348623159e308",
        modes("E1105", "E1105", "E1102"),
    )
    halfway_max = Fraction(2) ** 1024 - Fraction(2) ** 970
    assert halfway_max.denominator == 1
    halfway_text = str(halfway_max.numerator)
    r(
        "The exact midpoint between the largest double and 2^1024 rounds to even, which is "
        "infinity.",
        halfway_text,
        modes("E1105", "E1105", "E1102"),
    )
    r(
        "One less than that midpoint rounds to the largest double.",
        str(halfway_max.numerator - 1),
        modes(OK, OK, "E1102"),
    )
    r(
        "A decimal that rounds up to the smallest subnormal double.",
        "2.4703282292062328e-324",
        modes(OK, OK, "E1103"),
    )
    r(
        "A decimal that rounds down to zero.",
        "2.4703282292062327e-324",
        modes("E1106", "E1106", "E1103"),
    )
    half_min = exact_decimal(Fraction(2) ** -1075)
    r(
        "The exact value of 2^-1075, the midpoint between zero and the smallest subnormal "
        "double, rounds to even, which is zero.",
        half_min,
        modes("E1106", "E1106", "E1103"),
    )
    r(
        "The exact value of 2^-1075 followed by the digit 1 rounds up.",
        half_min + "1",
        modes(OK, OK, "E1103"),
    )
    r(
        "A decimal that rounds down to the largest subnormal double.",
        "2.2250738585072011e-308",
        modes(OK, OK, "E1103"),
    )
    r(
        "A decimal that rounds up to the smallest normal double.",
        "2.2250738585072012e-308",
        modes(OK, OK, "E1103"),
    )
    r("2^53 + 1 rounds to even, 2^53.", "9007199254740993", modes(OK, OK, "E1102"))
    r("2^53 + 3 rounds to even, 2^53 + 4.", "9007199254740995", modes(OK, OK, "E1102"))
    r("Just above 2^53 + 1 rounds up.", "9007199254740993.0000000001", modes(OK, OK, "E1103"))
    r("Just below 2^53 + 3 rounds down.", "9007199254740994.9999999999", modes(OK, OK, "E1103"))
    for value, name in [
        (1.0, "1"),
        (0.1, "0.1"),
        (123.456, "123.456"),
        (1e23, "10^23"),
        (math.ldexp(1.0, -1000), "2^-1000"),
        (1e300, "10^300"),
    ]:
        above = math.nextafter(value, math.inf)
        midpoint = (Fraction(value) + Fraction(above)) / 2
        text = exact_decimal(midpoint)
        even = value if struct.unpack(">Q", struct.pack(">d", value))[0] % 2 == 0 else above
        assert float(text) == even
        expect = modes(OK, OK, token_issue(text, "hashable") or OK)
        r(f"The exact midpoint above {name} rounds to the even neighbour.", text, expect)
        r(
            f"The exact midpoint above {name} followed by the digit 1 rounds up.",
            text + ("1" if "." in text else ".1"),
            modes(OK, OK, token_issue(text + ("1" if "." in text else ".1"), "hashable") or OK),
        )
    for token in AS_NUMERIC_MISCONVERSIONS:
        code = token_issue(token, "hashable") or OK
        r(
            f"R 4.3.3's as.numeric() converts {token} to a neighbour of the nearest double.",
            token,
            modes(OK, OK, code),
        )
    return b


DECIMAL_CONSTANTS = [
    # The table of conventions.md (Decimal strings and centring constants).
    (3.215, 3, "3.21", "not a tie, since the double lies below 3.215"),
    (0.125, 2, "0.12", "an exact tie, rounded to the even digit"),
    (0.375, 2, "0.38", "an exact tie, rounded to the even digit"),
    (2.5, 1, "2", "an exact tie, rounded to the even digit"),
    (34.56789, 6, "34.5679", None),
    (52345.678, 6, "52345.7", None),
    (1234567.0, 3, "1230000", "an integer"),
    (-0.000123456, 2, "-0.00012", "a negative value"),
    (1 / 3, 10, "0.3333333333", None),
    # Further ties and carries.
    (0.5, 1, "0.5", "no rounding"),
    (1.5, 1, "2", "a tie, rounded up to the even digit"),
    (3.5, 1, "4", "a tie, rounded up to the even digit"),
    (4.5, 1, "4", "a tie, rounded down to the even digit"),
    (-2.5, 1, "-2", "a negative tie"),
    (9.5, 1, "10", "a tie that carries into a new digit"),
    (0.0625, 2, "0.062", "an exact tie"),
    (0.1875, 3, "0.188", "an exact tie"),
    (1.25, 2, "1.2", "an exact tie"),
    (1.35, 2, "1.4", "not a tie, since the double lies above 1.35"),
    (2.675, 3, "2.67", "not a tie, since the double lies below 2.675"),
    (1234.5, 4, "1234", "a tie in the units"),
    (1235.5, 4, "1236", "a tie in the units"),
    (9.9999, 3, "10", "a carry into a new digit"),
    (0.9996, 3, "1", "a carry to 1"),
    (99.95, 3, "100", "not a tie, since the double lies above 99.95"),
    (0.0, 6, "0", "zero"),
    (-0.0, 6, "0", "negative zero"),
    (0.1, 15, "0.1", "15 digits of 0.1"),
    (0.1 + 0.2, 15, "0.3", "15 digits of 0.1 + 0.2"),
    (1 / 3, 15, "0.333333333333333", "15 digits"),
    (2 / 3, 15, "0.666666666666667", "15 digits"),
    (123456789012345680000.0, 15, "123456789012346000000", "a large integer"),
    (9007199254740992.0, 15, "9007199254740990", "2^53"),
    (1e22, 1, "10000000000000000000000", "10^22"),
    (-34.56789, 6, "-34.5679", None),
    (1e-7, 3, "0.0000001", "a small value in plain notation"),
    (1.5e-10, 2, "0.00000000015", None),
    (12345.0, 2, "12000", None),
    (0.00099999, 2, "0.001", "a carry in a small value"),
    (5e-324, 1, None, "the smallest subnormal double"),
    (1.7976931348623157e308, 3, None, "the largest double"),
]


def decimal_constant(x: float, digits: int) -> str:
    if x == 0:
        return "0"
    with localcontext() as context:
        context.prec = 2000
        exact = Decimal(x)
        quantum = Decimal(1).scaleb(exact.adjusted() - digits + 1)
        rounded = exact.quantize(quantum, rounding=ROUND_HALF_EVEN)
        text = format(rounded, "f")
        check = format(Decimal(format(x, f".{digits - 1}e")), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if "." in check:
        check = check.rstrip("0").rstrip(".")
    assert text == check, (x, digits)
    return text


def numbers_decimal_constants() -> list[dict]:
    cases = []
    for number, (x, digits, expected, note) in enumerate(DECIMAL_CONSTANTS, 1):
        text = decimal_constant(x, digits)
        if expected is not None:
            assert text == expected, (x, digits, text)
        SCHEMAS.check(text, "decimal_string")
        SCHEMAS.check({"significant_digits": digits, "value": text}, "decimal_constant")
        exact = format(Decimal(x), "f")
        exact = exact[:40] + "..." if len(exact) > 43 else exact
        description = f"The double {es_number(x)} to {digits} significant digit" + (
            "s" if digits > 1 else ""
        )
        description += f". Its exact value is {exact}"
        description += f", {note}." if note else "."
        cases.append(
            {
                "id": f"numbers-decimal-constants-{number:03d}",
                "description": description,
                "double": bits_of(x),
                "digits": digits,
                "expected": {"decimal": text},
            }
        )
    return cases


# unicode/ -------------------------------------------------------------------------


def unicode_utf8() -> Builder:
    b = Builder(
        "unicode-utf8",
        "Inputs checked against Table 3-7 of the Unicode Standard before they are parsed. "
        "Ill-formed input gives the offset of its first ill-formed sequence, and well-formed "
        "sequences at the limits of the table are accepted.",
    )

    def bad(description: str, data: bytes, offset: int) -> None:
        b.reader(description, data, "E1201", at=offset)

    bad("A stray continuation byte.", b'"\x80"', 1)
    bad("A stray continuation byte BF after a character.", '"\u00e9'.encode() + b'\xbf"', 3)
    bad("C0 80, an overlong U+0000.", b'"\xc0\x80"', 1)
    bad("C1 BF, an overlong U+007F.", b'"\xc1\xbf"', 1)
    bad("E0 80 80, an overlong U+0000 in three bytes.", b'"\xe0\x80\x80"', 1)
    bad("E0 9F BF, an overlong U+07FF.", b'"\xe0\x9f\xbf"', 1)
    bad("F0 80 80 80, an overlong U+0000 in four bytes.", b'"\xf0\x80\x80\x80"', 1)
    bad("F0 8F BF BF, an overlong U+FFFF.", b'"\xf0\x8f\xbf\xbf"', 1)
    bad("ED A0 80, the encoded surrogate U+D800.", b'"\xed\xa0\x80"', 1)
    bad("ED BF BF, the encoded surrogate U+DFFF.", b'"\xed\xbf\xbf"', 1)
    bad("ED A0 BD ED B8 80, an encoded surrogate pair (CESU-8).", b'"\xed\xa0\xbd\xed\xb8\x80"', 1)
    bad("F4 90 80 80, the code point U+110000.", b'"\xf4\x90\x80\x80"', 1)
    bad("F5, a byte that never appears in UTF-8.", b'"\xf5\x80\x80\x80"', 1)
    bad("FE, a byte that never appears in UTF-8.", b'"\xfe"', 1)
    bad("FF, a byte that never appears in UTF-8.", b'"\xff"', 1)
    bad("A two-byte sequence without its continuation byte.", b'"\xc3"', 1)
    bad("A lead byte at the end of the input.", b'"a\xc3', 2)
    bad("A three-byte sequence cut after two bytes.", b'"\xe2\x82"', 1)
    bad("A three-byte sequence cut after two bytes at the end of the input.", b'"\xe2\x82', 1)
    bad("A four-byte sequence cut after three bytes.", b'"\xf0\x9f\x98"', 1)
    bad("A lead byte followed by an ASCII byte.", b'"\xe2\x82A"', 1)
    bad("Invalid UTF-8 in a key.", b'{"\xff":1}', 2)
    bad("Invalid UTF-8 outside a string.", b"[1,\xff]", 3)
    bad("Invalid UTF-8 after a syntax error is reported first.", b"[1,,\xff]", 4)
    bad("Invalid UTF-8 after the top-level value.", b"[1]\xff", 3)
    bad(
        "The offset counts bytes: two characters of two bytes come first.",
        '"\u00e9\u00e9'.encode() + b'\xff"',
        5,
    )
    bad(
        "The offset counts bytes: a character of four bytes comes first.",
        '"\U0001f600'.encode() + b'\xc0"',
        5,
    )
    bad("Latin-1 text: 'caf\u00e9' with E9 for '\u00e9'.", b'"caf\xe9"', 4)
    b.reader("The largest two-byte character, U+07FF.", '"\u07ff"')
    b.reader("The smallest three-byte character, U+0800.", '"\u0800"')
    b.reader(
        "U+D7FF, the last code point before the surrogates, is well-formed but unassigned.",
        '"\ud7ff"',
        modes(OK, OK, "E1208"),
        at=0,
    )
    b.reader(
        "U+D7FB, the last character that Unicode 14.0 assigns before the surrogates.", '"\ud7fb"'
    )
    b.reader("U+E000, the first character after the surrogates.", '"\ue000"')
    b.reader(
        "The noncharacter U+FFFE is well-formed UTF-8 but unassigned.",
        '"\ufffe"',
        modes(OK, OK, "E1208"),
        at=0,
    )
    b.reader("U+10000, the smallest four-byte character.", '"\U00010000"')
    b.reader(
        "U+10FFFF, the largest code point, is well-formed but unassigned.",
        '"\U0010ffff"',
        modes(OK, OK, "E1208"),
        at=0,
    )
    b.reader("U+F0000, a private-use character of plane 15.", '"\U000f0000"')
    b.reader(
        "A mixture of one-, two-, three- and four-byte characters.", '"a\u00e9\u20ac\U0001f600"'
    )
    return b


NORMALISATION_STRINGS = [
    ("ASCII text", "Zurich"),
    ("the empty string", ""),
    ("'caf\u00e9' in NFC", "caf\u00e9"),
    ("'caf\u00e9' in NFD", "cafe\u0301"),
    ("'Z\u00fcrich' in NFC", "Z\u00fcrich"),
    ("'Z\u00fcrich' in NFD", "Zu\u0308rich"),
    ("'\u00c7' in NFC", "\u00c7"),
    ("'\u00c7' in NFD", "C\u0327"),
    ("'\u00c5' in NFC", "\u00c5"),
    ("'\u00c5' in NFD", "A\u030a"),
    ("U+212B ANGSTROM SIGN, a singleton that NFC replaces by U+00C5", "\u212b"),
    ("U+2126 OHM SIGN, a singleton that NFC replaces by U+03A9", "\u2126"),
    ("U+212A KELVIN SIGN, a singleton that NFC replaces by the ASCII 'K'", "\u212a"),
    ("U+2000 EN QUAD, a singleton that NFC replaces by U+2002", "\u2000"),
    ("'\u1ec7' in NFC", "\u1ec7"),
    ("'\u1ec7' in NFD", "e\u0323\u0302"),
    ("'\u1ec7' as 'e', U+0302 and U+0323, which canonical ordering reorders", "e\u0302\u0323"),
    ("'\u00e1' with U+0316, in NFC", "\u00e1\u0316"),
    ("'a' with U+0301 and U+0316, out of canonical order", "a\u0301\u0316"),
    ("'a' with U+0316 and U+0301", "a\u0316\u0301"),
    ("U+1E0B U+0323, which NFC turns into U+1E0D U+0307", "\u1e0b\u0323"),
    ("U+1E9B U+0323, which is in NFC", "\u1e9b\u0323"),
    ("'\u00e9' followed by U+0301, which is in NFC", "\u00e9\u0301"),
    ("the Hangul syllable U+AC00 in NFC", "\uac00"),
    ("the Hangul syllable U+AC00 as two jamo", "\u1100\u1161"),
    ("the Hangul syllable U+AC01 as three jamo", "\u1100\u1161\u11a8"),
    ("the Hangul syllable U+AC00 followed by a final jamo", "\uac00\u11a8"),
    ("U+0958 DEVANAGARI LETTER QA, excluded from composition", "\u0958"),
    ("U+0915 U+093C, the NFC form of U+0958", "\u0915\u093c"),
    ("U+FB33 HEBREW LETTER DALET WITH DAGESH, excluded from composition", "\ufb33"),
    ("U+0344, whose NFC form is U+0308 U+0301", "\u0344"),
    ("U+0F73, whose NFC form is U+0F71 U+0F72", "\u0f73"),
    ("the ligature U+FB01, which NFC keeps", "\ufb01"),
    ("the fullwidth letter U+FF21, which NFC keeps", "\uff21"),
    ("the dotless and dotted letters i of Turkish", "\u0131\u0130"),
    ("Greek alpha with psili and oxia in NFD", "\u03b1\u0313\u0301"),
    ("'x', U+1E2AE and U+0316: U+1E2AE was assigned in Unicode 14.0", "x\U0001e2ae\u0316"),
    ("'x', U+0316 and U+1E2AE", "x\u0316\U0001e2ae"),
    ("'x', U+1E4EC and U+0316: U+1E4EC was assigned in Unicode 15.0", "x\U0001e4ec\u0316"),
    ("'x', U+0316 and U+1E4EC", "x\u0316\U0001e4ec"),
    ("U+0378, unassigned", "\u0378"),
    ("the noncharacter U+FFFE", "\ufffe"),
    ("the noncharacter U+FDD0", "\ufdd0"),
    ("U+E000, a private-use character", "\ue000"),
    ("U+1F600, assigned in Unicode 6.1", "\U0001f600"),
    ("U+1FAE8, assigned in Unicode 15.0", "\U0001fae8"),
    ("'\u00e9' in NFD followed by U+0378", "e\u0301\u0378"),
]


def unicode_normalisation() -> list[dict]:
    cases = []
    for number, (name, text) in enumerate(NORMALISATION_STRINGS, 1):
        normalisable = UNICODE.normalisable(text)
        form = UNICODE.form(text)
        if normalisable:
            note = "It is normalisable" + (
                " and in NFC." if form == text else ", and its NFC form differs."
            )
        else:
            note = (
                "It holds a code point that Unicode 14.0 does not assign, so it stands for itself."
            )
        cases.append(
            {
                "id": f"unicode-normalisation-{number:03d}",
                "description": f"{name[0].upper()}{name[1:]}. {note}",
                "string": text,
                "expected": {"normalisable": normalisable, "form": form},
            }
        )
    return cases


def unicode_hashable() -> Builder:
    b = Builder(
        "unicode-hashable",
        "Strings and keys that are or are not normalisable and in NFC, read in each mode. Only "
        "the hashable profile checks NFC, and no mode normalises what it reads.",
    )
    for name, text in NORMALISATION_STRINGS:
        if text == "":
            continue
        normalisable = UNICODE.normalisable(text)
        nfc = normalisable and unicodedata.is_normalized("NFC", text)
        code = OK if nfc else "E1208" if not normalisable else "E1203"
        b.reader(
            f"{name[0].upper()}{name[1:]}, as a string.",
            json.dumps(text, ensure_ascii=False),
            modes(OK, OK, code),
            at=0,
        )
        if any(ord(char) > 0xFFFF for char in text):
            b.reader(
                f"{name[0].upper()}{name[1:]}, as a key.",
                "{" + json.dumps(text, ensure_ascii=False) + ":1}",
                modes(OK, "E1108", "E1108"),
                at=1,
            )
        elif code != OK:
            b.reader(
                f"{name[0].upper()}{name[1:]}, as a key, written with escapes.",
                "{" + json.dumps(text) + ":1}",
                modes(OK, OK, code),
                at=1,
            )
    return b


ORDER_PAIRS = [
    ("a", "b", "letters"),
    ("B", "a", "upper case before lower case"),
    ("Z", "_", "upper case before '_'"),
    ("_", "a", "'_' before lower case"),
    ("10", "9", "digits as characters"),
    ("ab", "abc", "a prefix first"),
    ("", "a", "the empty string first"),
    ("", "", "two empty strings"),
    ("z", "\u00e9", "'\u00e9' after 'z'"),
    ("e\u0301", "\u00e9", "NFD and NFC forms of '\u00e9'"),
    ("e\u0301", "f", "'\u00e9' in NFD compares as U+00E9, after 'f'"),
    ("\uff08", "\U0001f600", "code points, not UTF-16 code units"),
    ("\u2126", "\u03a9", "OHM SIGN and GREEK CAPITAL LETTER OMEGA"),
    ("\u212a", "K", "KELVIN SIGN and 'K'"),
    ("\ufb01", "fi", "no compatibility mapping"),
    ("\u0131", "i", "no case mapping for dotless i"),
    ("\u0130", "I", "no case mapping for dotted capital I"),
    ("A", "a", "no case folding"),
    (" a", "a", "no trimming before"),
    ("a ", "a", "no trimming after"),
    ("\u00a0", " ", "a no-break space is not a space"),
    ("\u2000", "\u2002", "EN QUAD and EN SPACE are equal after NFC"),
    ("\u1100\u1161", "\uac00", "Hangul jamo and the composed syllable"),
    ("a\u0301\u0316", "a\u0316\u0301", "combining marks in either order"),
    ("x\U0001e2ae\u0316", "x\u0316\U0001e2ae", "normalisable strings with U+1E2AE"),
    (
        "x\U0001e4ec\u0316",
        "x\u0316\U0001e4ec",
        "strings with U+1E4EC, compared code point by code point without NFC",
    ),
    ("\u0378", "\u0379", "unassigned code points stand for themselves"),
    ("\ufb33", "\u05d3\u05bc", "a composition exclusion and its NFC form"),
]


def unicode_order() -> list[dict]:
    cases = []

    def compare(first: str, second: str) -> int:
        left = [ord(char) for char in UNICODE.form(first)]
        right = [ord(char) for char in UNICODE.form(second)]
        return (left > right) - (left < right)

    number = 0
    for first, second, note in ORDER_PAIRS:
        for left, right in (
            [(first, second), (second, first)] if first != second else [(first, second)]
        ):
            number += 1
            order = compare(left, right)
            relation = {
                -1: "the first string comes first",
                0: "the two strings are equal",
                1: "the second string comes first",
            }[order]
            cases.append(
                {
                    "id": f"unicode-order-{number:03d}",
                    "description": f"{note[0].upper()}{note[1:]}: {relation}.",
                    "first": left,
                    "second": right,
                    "expected": {"order": order},
                }
            )
    lists = [
        (
            "Letters, digits, punctuation and non-ASCII letters.",
            ["z", "\u00e9", "e", "f", "E", "Z", "_", "a", "1", "10", "9", " "],
        ),
        (
            "Turkish letters i and words that differ in case.",
            ["\u0131", "i", "I", "\u0130", "Ab", "aB", "ab", "AB"],
        ),
        ("Strings in NFD sort as their NFC forms.", ["f", "e\u0301", "e", "\u00e8", "ea"]),
        (
            "Characters outside the BMP after U+FFxx.",
            ["\U0001f600", "\uff08", "\ue000", "\u00ff", "\U00010000"],
        ),
    ]
    for description, strings in lists:
        number += 1
        ordered = sorted(strings, key=lambda text: [ord(char) for char in UNICODE.form(text)])
        keys = [UNICODE.form(text) for text in ordered]
        assert len(set(keys)) == len(keys), "sort cases must have no ties"
        cases.append(
            {
                "id": f"unicode-order-{number:03d}",
                "description": description,
                "strings": strings,
                "expected": {"sorted": ordered},
            }
        )
    return cases


def unicode_c_locale() -> Builder:
    b = Builder(
        "unicode-c-locale",
        "Cases whose outputs a locale could change: non-ASCII strings, keys and messages, the "
        "order of keys, numbers, and, for one language, strings in memory with their encoding.",
    )
    b.reader("'\u00e9cole' as a string.", '"\u00e9cole"')
    case = b.reader(
        "'\u00e9cole' in an array, whose hash the evidence of G-critic records "
        "(out/c_locale_encoding.txt).",
        '["\u00e9cole"]',
    )
    assert case["expected"]["data"]["sha256"].startswith("sha256:0248553cf09b")
    plain_hash = hashlib.sha256("\u00e9cole".encode()).hexdigest()
    assert plain_hash.startswith("f0f772e182a4")
    b.reader(
        "Keys in code point order, which no locale's collation gives: 'E', 'Z', '_', 'a', 'e', "
        "'f', 'z' and '\u00e9'.",
        '{"z":1,"\u00e9":2,"e":3,"f":4,"E":5,"Z":6,"_":7,"a":8}',
    )
    b.reader(
        "The letters i of Turkish are distinct keys, sorted by code point.",
        '{"I":1,"\u0131":2,"i":3,"\u0130":4}',
    )
    b.reader("Keys that differ in case are distinct.", '{"\u00c9":1,"\u00e9":2}')
    b.reader(
        "A duplicate non-ASCII key, named in the message.",
        '{"\u00e9":1,"\u00e9":2}',
        "E1029",
        at=8,
    )
    b.reader(
        "A duplicate key of 70 non-ASCII characters, truncated in the message.",
        '{"' + "\u00e9" * 70 + '":1,"' + "\u00e9" * 70 + '":2}',
        "E1029",
        at=146,
    )
    b.reader(
        "A non-ASCII character where a value is expected, named in the message.",
        "[\u00e9]",
        "E1022",
        at=1,
    )
    b.reader(
        "A character outside the BMP where a value is expected.", "[\U0001f600]", "E1022", at=1
    )
    b.reader(
        "Numbers whose canonical form no decimal separator of a locale changes.",
        "[0.5,1234.5,1e21,-0.000001,1.5e-7]",
        modes(OK, OK, "E1102"),
        at="1e21",
    )
    b.reader(
        "Keys in NFD and NFC are distinct in the data profile and sorted by code point.",
        '{"\u00e9":1,"e\u0301":2}',
        modes(OK, OK, "E1203"),
        at=8,
    )
    w = b.writer
    w(
        "An R string marked UTF-8 that holds '\u00e9cole'.",
        json_text='["x"]',
        substitutions=[r_string("/0", "c3a9636f6c65", "UTF-8")],
        languages=["R"],
    )
    w(
        "An R string marked latin1 that holds '\u00e9cole' gives the bytes and hash of the "
        "string marked UTF-8.",
        json_text='["x"]',
        substitutions=[r_string("/0", "e9636f6c65", "latin1")],
        languages=["R"],
    )
    w(
        "An R string marked latin1 that holds '\u00c5ngstr\u00f6m'.",
        json_text='{"name":"x"}',
        substitutions=[r_string("/name", "c56e67737472f66d", "latin1")],
        languages=["R"],
    )
    w(
        "An unmarked R string with the bytes of '\u00e9cole' in UTF-8.",
        "E1204",
        json_text='["x"]',
        substitutions=[r_string("/0", "c3a9636f6c65", "unknown")],
        languages=["R"],
        at="/0",
    )
    w(
        "An unmarked R string that is ASCII.",
        json_text='["x"]',
        substitutions=[r_string("/0", "65636f6c65", "unknown")],
        languages=["R"],
    )
    w(
        "An unmarked non-ASCII R string after a valid one.",
        "E1204",
        json_text='{"a":"ok","b":["x"]}',
        substitutions=[r_string("/b/0", "e9", "unknown")],
        languages=["R"],
        at="/b/0",
    )
    w(
        "An R string marked 'bytes' with the bytes of '\u00e9cole' in UTF-8. R cannot mark an "
        "ASCII string as 'bytes', so the string holds a byte of 80 or above.",
        "E1205",
        json_text='["x"]',
        substitutions=[r_string("/0", "c3a9636f6c65", "bytes")],
        languages=["R"],
        at="/0",
    )
    w(
        "An R string marked UTF-8 that holds the invalid byte FF.",
        "E1201",
        json_text='["x"]',
        substitutions=[r_string("/0", "61ff", "UTF-8")],
        languages=["R"],
        at="/0",
    )
    w(
        "An R string marked UTF-8 in NFD, which only the hashable profile refuses.",
        modes(OK, OK, "E1203"),
        json_text='["x"]',
        substitutions=[r_string("/0", "65cc81", "UTF-8")],
        languages=["R"],
        at="/0",
    )
    w(
        "A Python str with a lone surrogate, as the error handler 'surrogateescape' produces "
        "for the byte E9.",
        "E1206",
        json_text='["x"]',
        substitutions=[py_string("/0", [0x63, 0x61, 0x66, 0xDCE9])],
        languages=["Python"],
        at="/0",
    )
    w(
        "A Python str with a high surrogate alone.",
        "E1206",
        json_text='{"a":"x"}',
        substitutions=[py_string("/a", [0xD83D])],
        languages=["Python"],
        at="/a",
    )
    return b


# hash/ ----------------------------------------------------------------------------

NIST_SHA256 = [
    ("", 1, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", 1, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        1,
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    ),
    (
        "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqr"
        "lmnopqrsmnopqrstnopqrstu",
        1,
        "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
    ),
    ("a", 1000000, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"),
]


def hash_sha256() -> list[dict]:
    cases: list[dict] = []

    def add(description: str, data: bytes, *, text: str | None = None, repeat: int = 1) -> dict:
        case: dict[str, Any] = {
            "id": f"hash-sha256-{len(cases) + 1:03d}",
            "description": description,
        }
        if text is not None:
            case["input"] = text
            assert text.encode("utf-8") == data
        else:
            case["input_hex"] = data.hex()
        if repeat != 1:
            case["repeat"] = repeat
        digest = sha256_hash(data * repeat)
        SCHEMAS.check(digest, "sha256_hash")
        case["expected"] = {"sha256": digest}
        cases.append(case)
        return case

    names = [
        "no bytes",
        "'abc'",
        "a message of 448 bits",
        "a message of 896 bits",
        "one million 'a'",
    ]
    for (text, repeat, published), name in zip(NIST_SHA256, names, strict=True):
        case = add(f"The example of NIST with {name}.", text.encode(), text=text, repeat=repeat)
        assert case["expected"]["sha256"] == "sha256:" + published
    for length in (55, 56, 63, 64, 65, 119, 120):
        add(
            f"{length} bytes 'a', at a boundary of SHA-256 padding.",
            b"a" * length,
            text="a" * length,
        )
    add("Every byte from 00 to FF.", bytes(range(256)))
    add("Bytes that are not UTF-8 are hashed as they are.", b"\xff\xfe\x00\x80")
    add("A file that starts with a byte-order mark.", b"\xef\xbb\xbf{}")
    add("JSON text with LF line endings.", b'{\n  "a": 1\n}\n', text='{\n  "a": 1\n}\n')
    add(
        "The same JSON text with CRLF line endings.",
        b'{\r\n  "a": 1\r\n}\r\n',
        text='{\r\n  "a": 1\r\n}\r\n',
    )
    add("'\u00e9cole' in UTF-8.", "\u00e9cole".encode(), text="\u00e9cole")
    add("'\u00e9cole' in Latin-1.", "\u00e9cole".encode("latin-1"))
    worked = (
        '{"a":{"b":false,"z":true,"\u00e9":"\u00e9"},"n":[1,100,0.000001,1e-7,4.5,0,2.5],'
        '"tab":"a\\tb\\u001f","title":"caf\u00e9 \\"study\\""}'
    )
    case = add(
        "The 117 canonical bytes of the worked example of conventions.md.",
        worked.encode(),
        text=worked,
    )
    assert case["expected"]["sha256"].endswith(
        "288afb1eec38acd97fc29eb68a97d9200dd6e77da5ee06d7586945b51372b80d"
    )
    return cases


def hash_sections() -> list[dict]:
    document = (
        '{"version":"0.1.0","design":{"rungs":[{"id":"r0","terms":["x","(1|g)"]},'
        '{"id":"r1","terms":["x"]}],"stop":{"rule":"protected","version":"0.1.0"}},'
        '"a/b":{"m~n":[1.5,true]},"\u00e9":"value","list":[0,1,2,3,4,5,6,7,8,9,10,11]}'
    )
    value = oracle_read(document.encode())
    scratch_read(document.encode(), "hashable")
    pointers = [
        ("", "The root: the whole document."),
        ("/design", "An object section."),
        ("/design/rungs", "An array section."),
        ("/design/rungs/1", "An element of an array."),
        ("/design/stop/rule", "A string."),
        ("/a~1b", "A key with '/', written '~1'."),
        ("/a~1b/m~0n", "A key with '~', written '~0'."),
        ("/a~1b/m~0n/0", "A number."),
        ("/\u00e9", "A non-ASCII key."),
        ("/list/10", "The element with index 10, an index of two digits."),
    ]
    cases = []
    for number, (pointer, description) in enumerate(pointers, 1):
        target = value
        for token in pointer.split("/")[1:]:
            token = token.replace("~1", "/").replace("~0", "~")
            target = target[int(token)] if isinstance(target, list) else target[token]
        serialised = canonical(target)
        cases.append(
            {
                "id": f"hash-sections-{number:03d}",
                "description": description,
                "input": document,
                "pointer": pointer,
                "expected": _success(serialised),
            }
        )
    return cases


# hmac/ ----------------------------------------------------------------------------

RFC4231 = [
    (
        "0b" * 20,
        b"Hi There".hex(),
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
        "Test case 1",
    ),
    (
        b"Jefe".hex(),
        b"what do ya want for nothing?".hex(),
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
        "Test case 2, with a key shorter than the output",
    ),
    (
        "aa" * 20,
        "dd" * 50,
        "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
        "Test case 3, with 50 bytes DD",
    ),
    (
        "0102030405060708090a0b0c0d0e0f10111213141516171819",
        "cd" * 50,
        "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
        "Test case 4, with a 25-byte key and 50 bytes CD",
    ),
    (
        "0c" * 20,
        b"Test With Truncation".hex(),
        "a3b6167473100ee06e0c796c2955552b",
        "Test case 5, whose output the RFC truncates to 128 bits",
    ),
    (
        "aa" * 131,
        b"Test Using Larger Than Block-Size Key - Hash Key First".hex(),
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
        "Test case 6, with a 131-byte key, which is hashed first",
    ),
    (
        "aa" * 131,
        b"This is a test using a larger than block-size key and a larger than block-size data. "
        b"The key needs to be hashed before being used by the HMAC algorithm.".hex(),
        "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
        "Test case 7, with a 131-byte key and a 152-byte message",
    ),
]


def _message_member(data: bytes) -> dict[str, str]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return {"message_hex": data.hex()}
    if "\0" in text or data.startswith(BOM):
        return {"message_hex": data.hex()}
    return {"message": text}


def hmac_rfc4231() -> list[dict]:
    cases = []
    for number, (key, message, published, description) in enumerate(RFC4231, 1):
        digest = hmac.new(bytes.fromhex(key), bytes.fromhex(message), hashlib.sha256).hexdigest()
        assert digest.startswith(published), description
        case = {
            "id": f"hmac-rfc4231-{number:03d}",
            "description": f"RFC 4231, {description[0].lower()}{description[1:]}.",
            "key_hex": key,
        } | _message_member(bytes.fromhex(message))
        expected: dict[str, Any] = {"digest": published}
        if len(published) < 64:
            case["truncate"] = len(published) // 2
        case["expected"] = expected
        cases.append(case)
    extra = [
        ("41" * 64, b"block", "A key of exactly 64 bytes, the block size, which is not hashed."),
        ("41" * 65, b"block", "A key of 65 bytes, which is hashed first."),
        ("", b"message", "An empty key."),
        ("00" * 32, b"", "An empty message."),
        (bytes(range(32)).hex(), bytes(range(256)), "Every byte as the message."),
    ]
    for key, message, description in extra:
        digest = hmac.new(bytes.fromhex(key), message, hashlib.sha256).hexdigest()
        cases.append(
            {
                "id": f"hmac-rfc4231-{len(cases) + 1:03d}",
                "description": description,
                "key_hex": key,
            }
            | _message_member(message)
            | {"expected": {"digest": digest}}
        )
    return cases


def key_id(key: bytes) -> str:
    return hashlib.sha256(key).hexdigest()[:16]


def hmac_commitments() -> list[dict]:
    cases: list[dict] = []

    def add(case: dict) -> None:
        cases.append({"id": f"hmac-commitments-{len(cases) + 1:03d}"} | case)

    example_key = bytes(range(32)).hex()
    assert key_id(bytes.fromhex(example_key)) == "630dcd2966c43366"
    for key, description in [
        (example_key, "The key 00 01 02 \u2026 1F of conventions.md."),
        ("00" * 32, "A key of 32 bytes 00."),
        ("ff" * 32, "A key of 32 bytes FF."),
        (hashlib.sha256(b"mixedcheck").hexdigest(), "The SHA-256 of 'mixedcheck' as a key."),
    ]:
        identifier = key_id(bytes.fromhex(key))
        SCHEMAS.check(identifier, "key_id")
        add({"description": description, "key": key, "expected": {"key_id": identifier}})
    invalid = [
        (example_key.upper(), "Upper-case hexadecimal digits."),
        (example_key[:62], "62 digits."),
        (example_key[:63], "63 digits."),
        (example_key + "2", "65 digits."),
        (example_key + "20", "66 digits."),
        ("g" + example_key[1:], "A character that is not a hexadecimal digit."),
        ("0x" + example_key[2:], "The prefix '0x'."),
        (" " + example_key[1:], "A leading space."),
        (example_key[:-1] + "\n", "A line feed in place of the last digit."),
        (example_key + "\n", "A final line feed."),
        ("", "An empty string."),
        ("\uff10" + example_key[1:], "A fullwidth digit zero."),
    ]
    for key, description in invalid:
        issue = CATALOGUE.issue("E1311")
        add(
            {
                "description": f"{description} The key is refused.",
                "key": key,
                "expected": {"issue": issue},
            }
        )
    worked = (
        '{"a":{"b":false,"z":true,"\u00e9":"\u00e9"},"n":[1,100,0.000001,1e-7,4.5,0,2.5],'
        '"tab":"a\\tb\\u001f","title":"caf\u00e9 \\"study\\""}'
    ).encode()
    outcome = (
        b'{"column":"post","key":["pupil","wave"],"rows":[["p1",0,12],["p1",1,15],'
        b'["p2",0,null],["p2",1,9]]}'
    )
    commitments = [
        (
            example_key,
            worked,
            "data_file",
            "The worked example of conventions.md (Keyed commitments, Example).",
            "dd8943be1fcb832169c6f874652f017415a37dddc77d6e9407ac0d910f67227a",
        ),
        (
            example_key,
            outcome,
            "outcome_column",
            "The outcome column example of documents.md, 98 bytes.",
            "75cc1f029d23f7ee37f8b3e0f1dc93e2d78b113b88d69f62a617346a6edafe7f",
        ),
        (example_key, b"", "data_file", "An empty data file.", None),
        (
            example_key,
            b"\xef\xbb\xbfpupil,score\r\np1,12\r\n",
            "data_file",
            "A data file with a byte-order mark and CRLF line endings, committed as stored.",
            None,
        ),
        (
            "ff" * 32,
            b"pupil,score\np1,12\n",
            "analysis_table",
            "A commitment of the kind analysis_table under another key.",
            None,
        ),
    ]
    for key, message, covers, description, published in commitments:
        digest = hmac.new(bytes.fromhex(key), message, hashlib.sha256).hexdigest()
        if published is not None:
            assert digest == published, description
            if covers == "outcome_column":
                assert len(message) == 98
        commitment = {
            "algorithm": "hmac-sha256",
            "covers": covers,
            "digest": digest,
            "key_id": key_id(bytes.fromhex(key)),
        }
        SCHEMAS.check(commitment, "keyed_commitment")
        add(
            {"description": description, "key": key}
            | _message_member(message)
            | {"covers": covers, "expected": {"commitment": commitment}}
        )
    return cases


# Output -----------------------------------------------------------------------------


def corpora() -> dict[str, dict]:
    def doc(description: str, cases: list[dict]) -> dict:
        return {"description": description, "cases": cases}

    return {
        "json/rfc8785.json": json_rfc8785().document(),
        "json/syntax.json": json_syntax().document(),
        "json/values.json": json_values().document(),
        "json/canonical.json": json_canonical().document(),
        "json/writer.json": json_writer().document(),
        "numbers/format.json": numbers_format().document(),
        "numbers/read.json": numbers_read().document(),
        "numbers/decimal_constants.json": doc(
            "Doubles rounded to a number of significant digits, half to even on their exact "
            "binary value, and written as decimal strings (conventions.md, Decimal strings and "
            "centring constants).",
            numbers_decimal_constants(),
        ),
        "unicode/utf8.json": unicode_utf8().document(),
        "unicode/normalisation.json": doc(
            "Strings with whether every code point is assigned in Unicode 14.0 and the form that "
            "comparisons of identifiers and labels use: NFC when normalisable, the string itself "
            "otherwise.",
            unicode_normalisation(),
        ),
        "unicode/hashable.json": unicode_hashable().document(),
        "unicode/order.json": doc(
            "Comparisons and sorts of strings by the code points of their comparison forms "
            "(conventions.md, Order).",
            unicode_order(),
        ),
        "unicode/c_locale.json": unicode_c_locale().document(),
        "hash/sha256.json": doc(
            "Byte strings with their SHA-256 hashes, written as in documents.",
            hash_sha256(),
        ),
        "hash/sections.json": doc(
            "Sections of a document in the hashable profile, located by JSON Pointer, with "
            "their canonical bytes and hashes.",
            hash_sections(),
        ),
        "hmac/rfc4231.json": doc(
            "HMAC-SHA-256 test cases 1 to 7 of RFC 4231 and further keys and messages of "
            "every length.",
            hmac_rfc4231(),
        ),
        "hmac/commitments.json": doc(
            "Commitment keys, each with its identifier or the issue that refuses it, and keyed "
            "commitments to messages.",
            hmac_commitments(),
        ),
    }


def render(document: dict) -> bytes:
    text = json.dumps(document, indent=2, ensure_ascii=True) + "\n"
    return text.encode("ascii")


def node_check(documents: dict[str, dict]) -> int:
    """Compare every number serialisation with Node.js, when it is installed."""
    node = shutil.which("node")
    if node is None:
        return 0
    pairs = []
    for name in ("json/rfc8785.json", "numbers/format.json"):
        for case in documents[name]["cases"]:
            if "double" in case and "plain" in case["expected"]:
                pairs.append((case["double"], case["expected"]["plain"]["canonical"]))
    script = (
        "const lines=require('fs').readFileSync(0,'utf8').trim().split('\\n');"
        "for(const h of lines){console.log(String(Buffer.from(h,'hex').readDoubleBE(0)));}"
    )
    result = subprocess.run(
        [node, "-e", script],
        input="\n".join(bits for bits, _ in pairs),
        capture_output=True,
        text=True,
        check=True,
    )
    for (bits, expected), actual in zip(pairs, result.stdout.split(), strict=True):
        assert actual == expected, (bits, actual, expected)
    return len(pairs)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--check", action="store_true", help="compare with the files, write nothing"
    )
    args = parser.parse_args(argv)
    documents = corpora()
    checked = node_check(documents)
    stale = []
    for name, document in documents.items():
        path = CORPORA / name
        content = render(document)
        if path.is_file() and path.read_bytes() == content:
            continue
        stale.append(name)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    total = sum(len(document["cases"]) for document in documents.values())
    for name, document in documents.items():
        print(f"{name}: {len(document['cases'])} cases")
    print(f"{total} cases in {len(documents)} files")
    print(f"Node.js confirmed {checked} number serialisations" if checked else "Node.js not found")
    if args.check:
        for name in stale:
            print(f"{name} differs from what this script writes", file=sys.stderr)
        return 1 if stale else 0
    for name in stale:
        print(f"wrote {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
