#!/usr/bin/env python3
"""Write the conformance corpus of the table reader.

The corpus tests the strict data reader that M2 implements in both packages,
as docs/spec/tables.md specifies it: the CSV text, the header and its match
with the table block of a declaration, missing values, the lexical forms of the
field types, categories, the types inferred without a table block, the primary
and unique keys, and the rows that missing values remove from the design and
analysis samples of docs/spec/ir.md. This script writes it under
fixtures/conformance/tables/: one JSON file for each group of cases and a
directory of the same name with the CSV inputs, byte for byte.

Each case states by hand the code it expects, or 'ok', and some cases also
state by hand an offset, values or sample rows. The script derives the rest of
each expected output with a scratch reading of tables.md, written for this
script and part of neither package, stops unless it agrees with what a case
states by hand, and checks the derivation against independent oracles:

- the records and fields of every table that the reader accepts, against
  Python's csv module in strict mode, reading an empty line as one empty field
- every number converted, against exact fractions, so that each double is the
  one nearest to its decimal, with ties to even
- every date and date and time checked, against the datetime module, whose
  years run from 1 to 9999 as the lexical forms require
- NFC, against unicodedata, for code points that Unicode 14.0 assigns

The edgezoo cases read their inputs from
docs/design/evidence/decisions/E-verify/edgezoo/ as stored. The declarations
pass the structural validator of spec/tools/compile_registry.py and the rules
of the hashable profile, and messages are rendered from spec/errors.json as
docs/spec/errors.md describes.

Run it from the repository root with Python 3.11 or later:

    python3 fixtures/conformance/tools/make_table_corpus.py
    python3 fixtures/conformance/tools/make_table_corpus.py --check

The first writes the corpus and the second compares it with the files and
writes nothing.
"""

from __future__ import annotations

import argparse
import csv
import datetime
import io
import json
import math
import re
import struct
import sys
import unicodedata
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "spec" / "tools"))

import compile_registry as cr  # noqa: E402

CORPUS = ROOT / "fixtures" / "conformance" / "tables"
EDGEZOO = ROOT / "docs" / "design" / "evidence" / "decisions" / "E-verify" / "edgezoo"
DECLARATION_SCHEMA = "urn:mixedcheck:schema:declaration"
GROUPS = {
    "edgezoo": (
        "The ten edge tables of docs/design/evidence/decisions/E-verify/edgezoo, read as "
        "stored, with their table descriptors updated to vocabulary 0.1."
    ),
    "edge": (
        "Tables that carry the strings, numbers, byte-order marks, escapes and empty "
        "containers of the JSON edge files in docs/design/evidence/decisions/E/schema/edge "
        "and E-verify/edge into CSV text."
    ),
    "input": (
        "Stages 1 and 2: files that do not exist or cannot be read, the byte-order mark, "
        "invalid UTF-8 and U+0000."
    ),
    "records": (
        "The CSV text: line breaks, quoted and unquoted fields, white space, quoting "
        "problems (E5004) and records of the wrong length (E5005)."
    ),
    "header": (
        "The header: an empty table, invalid and repeated column names (E5002) and the "
        "match of the column names with the table block (E5003)."
    ),
    "values": (
        "Declared columns: missing values, the lexical form of each field type (E5006) "
        "and categories (E5007)."
    ),
    "inference": "Columns without a table block, whose types are inferred from their values.",
    "keys": "The primary key (E5008 and E5009) and the unique keys (E5010) of the table block.",
    "precedence": "Tables with several problems, of which the reader reports the first.",
    "samples": (
        "The rows that missing values, sentinel codes and trials of 0 remove from the "
        "design and analysis samples of a formula."
    ),
}
BOM = b"\xef\xbb\xbf"
MAX_INTEGER = 9007199254740991
INTEGER = re.compile(r"[+-]?[0-9]+")
NUMBER = re.compile(r"[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?")
SPECIAL = {"nan": math.nan, "inf": math.inf, "-inf": -math.inf}
TRUE = {"true", "True", "TRUE", "1"}
FALSE = {"false", "False", "FALSE", "0"}
WORDS = {"true": True, "True": True, "TRUE": True, "false": False, "False": False, "FALSE": False}
DATE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})")
DATETIME = re.compile(
    r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?"
    r"(Z|[+-]([0-9]{2}):([0-9]{2}))?"
)
TYPE_WORDS = {
    "integer": "an integer",
    "number": "a number",
    "boolean": "a boolean",
    "date": "a date",
    "datetime": "a date and time",
}
CATALOGUE = cr.Catalogue(ROOT / "spec" / "errors.json")
NAMES = {entry["code"]: name for name, entry in CATALOGUE.by_name.items()}


# --- Scratch reading of docs/spec/tables.md -------------------------------------


class Refusal(Exception):
    """The one issue that the reader reports."""

    def __init__(self, code: str, offset: int | None = None, **args: Any) -> None:
        super().__init__(code)
        self.code = code
        self.offset = offset
        self.args_ = args

    def issue(self) -> dict:
        found = CATALOGUE.issue(NAMES[self.code], offset=self.offset, **self.args_)
        out = {"code": found.code, "message": found.message}
        if found.offset is not None:
            out["offset"] = found.offset
        return out


@dataclass
class Field:
    offset: int
    raw: str


@dataclass
class Record:
    start: int
    fields: list[Field]
    end: int


@dataclass
class Table:
    names: list[str]
    types: list[str]
    records: list[Record]
    rows: list[list[Any]]


def nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text) if cr.normalisable(text) else text


class Scanner:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def more(self) -> bool:
        return self.pos < len(self.data)

    def record(self) -> Record:
        data, size = self.data, len(self.data)
        start = self.pos
        fields = []
        while True:
            begin = self.pos
            if begin < size and data[begin] == 0x22:
                j = begin + 1
                buffer = bytearray()
                while True:
                    if j >= size:
                        raise Refusal("E5004", begin)
                    if data[j] == 0x22:
                        if j + 1 < size and data[j + 1] == 0x22:
                            buffer.append(0x22)
                            j += 2
                            continue
                        j += 1
                        break
                    buffer.append(data[j])
                    j += 1
                if j < size and data[j] not in (0x2C, 0x0A, 0x0D):
                    raise Refusal("E5004", j)
                raw = bytes(buffer)
            else:
                j = begin
                while j < size and data[j] not in (0x2C, 0x0A, 0x0D):
                    if data[j] == 0x22:
                        raise Refusal("E5004", j)
                    j += 1
                raw = data[begin:j]
            fields.append(Field(begin, raw.decode("utf-8")))
            if j < size and data[j] == 0x2C:
                self.pos = j + 1
                continue
            if j < size:
                crlf = data[j] == 0x0D and j + 1 < size and data[j + 1] == 0x0A
                self.pos = j + (2 if crlf else 1)
            else:
                self.pos = j
            return Record(start, fields, j)


def _column_name_valid(name: str) -> bool:
    if not 1 <= len(name) <= 128:
        return False
    return all(0x20 <= ord(c) <= 0x7E or 0xA0 <= ord(c) <= 0xFFFF for c in name)


def _missing(table: dict | None, spec: dict | None) -> set[str]:
    if spec is not None and "missingValues" in spec:
        values = spec["missingValues"]
    elif table is not None and "missingValues" in table:
        values = table["missingValues"]
    else:
        values = [""]
    return {nfc(item["value"] if isinstance(item, dict) else item) for item in values}


def _days(year: int, month: int) -> int:
    if month == 2:
        leap = year % 4 == 0 and year % 100 != 0 or year % 400 == 0
        return 29 if leap else 28
    return 30 if month in (4, 6, 9, 11) else 31


def _date_ok(year: str, month: str, day: str) -> bool:
    y, m, d = int(year), int(month), int(day)
    return 1 <= y <= 9999 and 1 <= m <= 12 and 1 <= d <= _days(y, m)


def number_value(raw: str) -> float | None:
    """The double of a number, or None when the raw value is not a number."""
    if raw.isascii() and raw.lower() in SPECIAL:
        return SPECIAL[raw.lower()]
    if not NUMBER.fullmatch(raw):
        return None
    value = float(raw)
    mantissa = re.split("[eE]", raw)[0]
    if math.isinf(value) or (value == 0 and re.search("[1-9]", mantissa)):
        return None
    ORACLE.nearest(raw, value)
    return value


def convert(raw: str, kind: str | None) -> tuple[bool, Any]:
    """Whether the raw value has the lexical form of the type, and its value."""
    if kind is None or kind == "string":
        return True, raw
    if kind == "integer":
        if not INTEGER.fullmatch(raw) or abs(int(raw)) > MAX_INTEGER:
            return False, None
        return True, int(raw)
    if kind == "number":
        value = number_value(raw)
        return value is not None, value
    if kind == "boolean":
        if raw in TRUE or raw in FALSE:
            return True, raw in TRUE
        return False, None
    if kind == "date":
        match = DATE.fullmatch(raw)
        ok = bool(match) and _date_ok(*match.groups())
        ORACLE.calendar(raw, kind, ok)
        return ok, raw if ok else None
    match = DATETIME.fullmatch(raw)
    ok = False
    if match:
        year, month, day, hour, minute, second, _, zone, zone_hour, zone_minute = match.groups()
        ok = (
            _date_ok(year, month, day)
            and int(hour) <= 23
            and int(minute) <= 59
            and int(second) <= 59
            and (zone_hour is None or (int(zone_hour) <= 23 and int(zone_minute) <= 59))
        )
    ORACLE.calendar(raw, kind, ok)
    return ok, raw if ok else None


def _key_value(value: Any, kind: str | None) -> Any:
    if kind in (None, "string", "date", "datetime"):
        return ("s", nfc(value))
    if kind == "number":
        if math.isnan(value):
            return ("nan",)
        return ("n", value + 0.0)
    return (kind, value)


def read_table(data: bytes, table: dict | None) -> Table:
    if data.startswith(BOM):
        raise Refusal("E1003")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise Refusal("E1201", error.start) from None
    if b"\x00" in data:
        raise Refusal("E1202", data.index(b"\x00"))
    if not data:
        raise Refusal("E5001")
    scanner = Scanner(data)
    header = scanner.record()
    names = [f.raw for f in header.fields]
    seen: list[str] = []
    for f in header.fields:
        if not _column_name_valid(f.raw) or nfc(f.raw) in seen:
            raise Refusal("E5002", f.offset)
        seen.append(nfc(f.raw))
    specs: list[dict | None] = [None] * len(names)
    if table is not None:
        declared = table["fields"]
        for i, f in enumerate(header.fields):
            if i >= len(declared) or nfc(f.raw) != nfc(declared[i]["name"]):
                raise Refusal("E5003", f.offset)
        if len(names) < len(declared):
            raise Refusal("E5003", header.end)
        specs = list(declared)
    records: list[Record] = []
    rows: list[list[Any]] = []

    def value_of(record: Record, i: int, kind: str | None) -> Any:
        f = record.fields[i]
        if nfc(f.raw) in _missing(table, specs[i]):
            return None
        ok, value = convert(f.raw, kind)
        if not ok:
            raise Refusal("E5006", f.offset, value=f.raw, column=names[i], type=TYPE_WORDS[kind])
        spec = specs[i]
        if spec is not None and "categories" in spec:
            allowed = [c["value"] if isinstance(c, dict) else c for c in spec["categories"]]
            hit = value in allowed if kind == "integer" else nfc(value) in {nfc(c) for c in allowed}
            if not hit:
                raise Refusal("E5007", f.offset, value=f.raw, column=names[i])
        return value

    def check_length(record: Record) -> None:
        if len(record.fields) != len(names):
            raise Refusal("E5005", record.start, found=len(record.fields), expected=len(names))

    if table is not None:
        types = [spec.get("type", "string") for spec in specs if spec is not None]
        while scanner.more():
            record = scanner.record()
            check_length(record)
            rows.append([value_of(record, i, spec.get("type")) for i, spec in enumerate(specs)])
            records.append(record)
    else:
        while scanner.more():
            record = scanner.record()
            check_length(record)
            records.append(record)
        types = []
        for i in range(len(names)):
            present = [r.fields[i].raw for r in records if r.fields[i].raw != ""]
            if present and all(
                (v.isascii() and v.lower() in SPECIAL) or NUMBER.fullmatch(v) for v in present
            ):
                types.append("number")
            elif present and all(v in WORDS for v in present):
                types.append("boolean")
            else:
                types.append("string")
        for record in records:
            row = []
            for i, kind in enumerate(types):
                raw = record.fields[i].raw
                if raw == "":
                    row.append(None)
                elif kind == "boolean":
                    row.append(WORDS[raw])
                else:
                    row.append(value_of(record, i, kind))
            rows.append(row)
    if table is not None:
        position = {spec["name"]: i for i, spec in enumerate(specs) if spec is not None}
        kinds = [spec.get("type") for spec in specs if spec is not None]
        if "primaryKey" in table:
            columns = [position[name] for name in table["primaryKey"]]
            first: dict[tuple, int] = {}
            for record, row in zip(records, rows, strict=True):
                for i in columns:
                    if row[i] is None:
                        raise Refusal("E5008", record.fields[i].offset, column=names[i])
                key = tuple(_key_value(row[i], kinds[i]) for i in columns)
                if key in first:
                    raise Refusal("E5009", record.start, earlier=first[key])
                first[key] = record.start
        for index, unique in enumerate(table.get("uniqueKeys", []), start=1):
            columns = [position[name] for name in unique]
            first = {}
            for record, row in zip(records, rows, strict=True):
                if any(row[i] is None for i in columns):
                    continue
                key = tuple(_key_value(row[i], kinds[i]) for i in columns)
                if key in first:
                    raise Refusal("E5010", record.start, index=index, earlier=first[key])
                first[key] = record.start
    return Table(names, types, records, rows)


# --- Oracles -------------------------------------------------------------------


class Oracle:
    def nearest(self, raw: str, value: float) -> None:
        exact = Fraction(raw)
        if value == 0:
            return
        below = math.nextafter(value, -math.inf)
        above = math.nextafter(value, math.inf)
        gap = abs(exact - Fraction(value))
        for other in (below, above):
            if math.isinf(other):
                continue
            distance = abs(exact - Fraction(other))
            if distance < gap or (distance == gap and int.from_bytes(_bits(other)) % 2 == 0):
                raise AssertionError(f"{raw!r} does not convert to its nearest double")

    def calendar(self, raw: str, kind: str, ok: bool) -> None:
        if kind == "date":
            match = DATE.fullmatch(raw)
            valid = False
            if match:
                try:
                    datetime.date(*map(int, match.groups()))
                    valid = True
                except ValueError:
                    pass
        else:
            match = DATETIME.fullmatch(raw)
            valid = False
            if match:
                year, month, day, hour, minute, second, _, _, zone_hour, zone_minute = (
                    match.groups()
                )
                try:
                    datetime.datetime(*map(int, (year, month, day, hour, minute, second)))
                    if zone_hour is not None:
                        datetime.time(int(zone_hour), int(zone_minute))
                    valid = True
                except ValueError:
                    pass
        if valid != ok:
            raise AssertionError(f"the datetime module disagrees on {raw!r}")

    def records(self, data: bytes, table: Table) -> None:
        text = data.decode("utf-8")
        found = [row or [""] for row in csv.reader(io.StringIO(text, newline=""), strict=True)]
        mine = [table.names] + [[f.raw for f in r.fields] for r in table.records]
        if found != mine:
            raise AssertionError(f"the csv module reads other records: {found!r}")


def _bits(value: float) -> bytes:
    return struct.pack(">d", value)


ORACLE = Oracle()


# --- Cases ---------------------------------------------------------------------


@dataclass
class Case:
    group: str
    name: str
    description: str
    code: str
    data: bytes | None = None
    declaration: dict | None = None
    file: str | None = None
    offset: int | None = None
    values: dict[str, list] | None = None
    formula: str | None = None
    reads: tuple[str, list[str]] | None = None
    design: list[int] | None = None
    analysis: list[int] | None = None
    extra: dict = field(default_factory=dict)


def fld(name: str, kind: str | None = None, **members: Any) -> dict:
    out: dict[str, Any] = {"name": name}
    if kind is not None:
        out["type"] = kind
    out.update(members)
    return out


def block(*fields: dict, **members: Any) -> dict:
    return {"vocabulary": "0.1.0", "table": {"fields": list(fields), **members}}


def strings(*names: str) -> dict:
    return block(*(fld(name, "string") for name in names))


def one(name: str, kind: str, **members: Any) -> dict:
    return block(fld("id", "string"), fld(name, kind, **members))


NAN = "NaN"
INF = "Infinity"
NINF = "-Infinity"
CASES: list[Case] = []


def case(group: str, name: str, description: str, code: str, data: bytes | str | None, **kw: Any):
    if isinstance(data, str):
        data = data.encode("utf-8")
    CASES.append(Case(group, name, description, code, data, **kw))


def edgezoo() -> None:
    def source(name: str) -> tuple[bytes, dict]:
        directory = EDGEZOO / name
        data = (directory / "data.csv").read_bytes()
        design = json.loads((directory / "design.json").read_text(encoding="utf-8"))
        if set(design) != {"schema_version", "table"} or design["schema_version"] != "0.1.0":
            raise AssertionError(f"{name}: unexpected design.json")
        return data, {"vocabulary": "0.1.0", "table": design["table"]}

    rows = [
        (
            "T1_missing_default",
            "T1: without missingValues, the Frictionless default [''] applies, so the empty "
            "values of a string and a number column are missing. The row with a missing "
            "predictor leaves the design sample and the row with a missing response the "
            "analysis sample.",
            "ok",
            {
                "values": {"id": ["1", "2", "3"], "g": ["a", None, "b"], "y": [1.5, 2.5, None]},
                "formula": "y ~ g",
                "reads": ("y", ["g"]),
                "design": [0, 2],
                "analysis": [0],
            },
        ),
        (
            "T2_integer_forms",
            "T2: '007' and '+5' are integers, but ' 12' is not, since nothing is trimmed, so "
            "the reader stops at it before reaching '1_000'.",
            "E5006",
            {"offset": 18},
        ),
        ("T3_hex_integer", "T3: '0x1A' is not an integer.", "E5006", {"offset": 7}),
        (
            "T4_number_tokens",
            "T4: NaN, INF and -INF are numbers, not missing values, so no row leaves either "
            "sample. Building the response vector later gives E6073 (ir.md).",
            "ok",
            {
                "values": {"id": ["1", "2", "3"], "y": [NAN, INF, NINF]},
                "formula": "y ~ 1",
                "reads": ("y", []),
                "design": [0, 1, 2],
                "analysis": [0, 1, 2],
            },
        ),
        (
            "T5_strings",
            "T5: 'NA' is a string value, not a missing value, and white space and a quoted "
            "comma are kept, so every row stays in the analysis sample of a formula whose "
            "response is the string column.",
            "ok",
            {
                "values": {"id": ["1", "2", "3", "4"], "s": ["NA", "caf\u00e9", " padded ", "a,b"]},
                "formula": "s ~ 1",
                "reads": ("s", []),
                "design": [0, 1, 2, 3],
                "analysis": [0, 1, 2, 3],
            },
        ),
        (
            "T6_crlf",
            "T6: CR LF line endings end records like LF.",
            "ok",
            {"values": {"id": ["1", "2"], "s": ["x", "y"]}},
        ),
        ("T7_bom", "T7: a CSV file that starts with a byte-order mark is refused.", "E1003", {}),
        (
            "T8_volts",
            "T8: small numbers in exponent notation, as EEG amplitudes in volts are written.",
            "ok",
            {"values": {"id": ["1", "2"], "amp": [3.2e-06, -1.25e-07]}},
        ),
        (
            "T9_embedded_newline",
            "T9: a quoted field holds a line feed, which is kept.",
            "ok",
            {"values": {"id": ["1", "2"], "s": ["two\nlines", "z"]}},
        ),
        (
            "T10_clean_control",
            "T10: a clean ASCII table, the control case of the edge tables.",
            "ok",
            {
                "values": {"id": ["1", "2"], "s": ["x", "y"], "y": [0.5, 1.25]},
                "formula": "y ~ s",
                "reads": ("y", ["s"]),
                "design": [0, 1],
                "analysis": [0, 1],
            },
        ),
    ]
    for name, description, code, kw in rows:
        data, declaration = source(name)
        case("edgezoo", name, description, code, data, declaration=declaration, **kw)


def edge() -> None:
    g = "edge"
    # edge1_canonical.json: strings, numbers, escapes and characters outside the BMP.
    numbers = [
        "1",
        "1.0",
        "3000000000",
        "-0",
        "1e2",
        "0.5",
        "7.5",
        "1e-3",
        "123.456",
        "0.1",
        "2026.10",
    ]
    rows = []
    for i, token in enumerate(numbers):
        if i == 0:
            rows.append(
                f'{i + 1},caf\u00e9,{token},"tab\there ""q"" back\\slash \x01 ctrl",'
                "\U0001f600 \U0001f600"
            )
        else:
            rows.append(f"{i + 1},,{token},,")
    text = "id,Z\u00fcrich,b,esc,emoji\n" + "\n".join(rows) + "\n"
    expected_b = [1.0, 1.0, 3000000000.0, 0.0, 100.0, 0.5, 7.5, 0.001, 123.456, 0.1, 2026.1]
    case(
        g,
        "edge1_mixed",
        "From edge1: a non-ASCII column name, strings with a tab, quotation "
        "marks, a backslash, U+0001 and characters outside the BMP, which are values as "
        "written, and the numbers of edge1, among them '-0' and '2026.10'.",
        "ok",
        text,
        declaration=block(
            fld("id", "string"),
            fld("Z\u00fcrich", "string"),
            fld("b", "number"),
            fld("esc", "string"),
            fld("emoji", "string"),
        ),
        values={"b": expected_b, "esc": ['tab\there "q" back\\slash \x01 ctrl'] + [None] * 10},
    )
    case(
        g,
        "edge1_inferred",
        "From edge1: the same table without a table block. The column "
        "'id' of '1' to '11' is a number column, and the columns with empty values are string "
        "columns with missing values.",
        "ok",
        text,
        values={"id": [float(i) for i in range(1, 12)], "b": expected_b},
    )
    # edge2_nfd.json: 'cafe' with an acute accent, written in NFD.
    nfd = "cafe\u0301"
    case(
        g,
        "edge2_value",
        "From edge2: a value in NFD is returned as written, apart from the same value in NFC.",
        "ok",
        f"id,s\n1,{nfd}\n2,caf\u00e9\n",
        declaration=strings("id", "s"),
        values={"s": [nfd, "caf\u00e9"]},
    )
    case(
        g,
        "edge2_header",
        "From edge2: a column name in NFD matches the field name in NFC, "
        "and the column keeps the name as the header writes it.",
        "ok",
        f"id,{nfd}\n1,x\n",
        declaration=strings("id", "caf\u00e9"),
        values={nfd: ["x"]},
    )
    case(
        g,
        "edge2_category",
        "From edge2: values in NFD match categories in NFC and are returned as written.",
        "ok",
        f"id,s\n1,{nfd}\n2,the\u0301\n3,caf\u00e9\n",
        declaration=one("s", "string", categories=["caf\u00e9", "th\u00e9"]),
        values={"s": [nfd, "the\u0301", "caf\u00e9"]},
    )
    case(
        g,
        "edge2_missing",
        "From edge2: a value in NFD matches a labelled missing value in NFC and is missing.",
        "ok",
        "id,s\n1,refuse\u0301\n2,x\n",
        declaration=one(
            "s", "string", missingValues=[{"value": "refus\u00e9", "label": "refused"}]
        ),
        values={"s": [None, "x"]},
    )
    case(
        g,
        "edge2_duplicate_header",
        "From edge2: two column names equal after NFC.",
        "E5002",
        f"caf\u00e9,{nfd}\n1,2\n",
        offset=6,
    )
    # edge3_bom.json: the byte-order mark.
    case(
        g,
        "edge3_bom",
        "From edge3: a byte-order mark before a table without a table block.",
        "E1003",
        BOM + b"id,s\n1,x\n",
    )
    case(
        g,
        "edge3_bom_inside",
        "From edge3: U+FEFF after the start of the input is a character of its value.",
        "ok",
        "id,s\n1,\ufeffx\n",
        declaration=strings("id", "s"),
        values={"s": ["\ufeffx"]},
    )
    case(
        g,
        "edge3_bom_number",
        "From edge3: U+FEFF before a number makes it no number.",
        "E5006",
        "id,y\n1,\ufeff1\n",
        declaration=one("y", "number"),
        offset=7,
    )
    # edge4_nan.json: NaN and the infinities.
    case(
        g,
        "edge4_special_numbers",
        "From edge4: NaN, INF and -INF in any mix of upper and lower case are numbers.",
        "ok",
        "id,y\n1,NaN\n2,nan\n3,NAN\n4,iNf\n5,-inf\n6,INF\n7,-Inf\n",
        declaration=one("y", "number"),
        values={"y": [NAN, NAN, NAN, INF, NINF, INF, NINF]},
    )
    for name, token, what in [
        ("edge4_plus_inf", "+INF", "'+INF' has a sign that only '-INF' allows"),
        ("edge4_infinity", "Infinity", "'Infinity' is not one of the special values"),
        ("edge4_negative_nan", "-NaN", "'-NaN' is not one of the special values"),
    ]:
        case(
            g,
            name,
            f"From edge4: {what}.",
            "E5006",
            f"id,y\n1,{token}\n",
            declaration=one("y", "number"),
            offset=7,
        )
    case(
        g,
        "edge4_nan_integer",
        "From edge4: 'NaN' is no integer.",
        "E5006",
        "id,k\n1,NaN\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "edge4_inferred",
        "From edge4: without a table block, a column of 'NaN' and '1' is "
        "a number column and a column of 'NA' and '1' a string column.",
        "ok",
        "y,z\nNaN,NA\n1,1\n",
        values={"y": [NAN, 1.0], "z": ["NA", "1"]},
    )
    # e5_small_numbers.json.
    case(
        g,
        "e5_small",
        "From e5: small numbers, the smallest subnormal, the largest decimal "
        "that rounds to it, a zero with a large negative exponent and negative zero.",
        "ok",
        "id,y\n1,1e-7\n2,1.5e-7\n3,5e-324\n4,2.4703282292062328e-324\n5,0e-400\n6,-0.0\n",
        declaration=one("y", "number"),
        values={"y": [1e-07, 1.5e-07, 5e-324, 5e-324, 0.0, 0.0]},
    )
    case(
        g,
        "e5_underflow",
        "From e5: the largest decimal that rounds to zero.",
        "E5006",
        "id,y\n1,2.4703282292062327e-324\n",
        declaration=one("y", "number"),
        offset=7,
    )
    case(
        g,
        "e5_underflow_exponent",
        "From e5: '1e-400' rounds to zero.",
        "E5006",
        "id,y\n1,1e-400\n",
        declaration=one("y", "number"),
        offset=7,
    )
    # e6_large_numbers.json.
    case(
        g,
        "e6_large",
        "From e6: large numbers, the largest double and the largest decimal that rounds to it.",
        "ok",
        "id,y\n1,1e21\n2,1.7976931348623157e308\n3,123456789012345680000\n4,1e20\n"
        "5,1.7976931348623158e308\n",
        declaration=one("y", "number"),
        values={
            "y": [1e21, 1.7976931348623157e308, 1.2345678901234568e20, 1e20, 1.7976931348623157e308]
        },
    )
    case(
        g,
        "e6_overflow",
        "From e6: the smallest decimal that rounds to infinity.",
        "E5006",
        "id,y\n1,1.7976931348623159e308\n",
        declaration=one("y", "number"),
        offset=7,
    )
    case(
        g,
        "e6_negative_overflow",
        "From e6: '-1e400' rounds to minus infinity.",
        "E5006",
        "id,y\n1,-1e400\n",
        declaration=one("y", "number"),
        offset=7,
    )
    case(
        g,
        "e6_integer_range",
        "From e6: an integer beyond 9007199254740991.",
        "E5006",
        "id,k\n1,123456789012345680000\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "e6_integer_exponent",
        "From e6: '1e21' is not in the lexical form of an integer.",
        "E5006",
        "id,k\n1,1e21\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    # e7_big_int.json.
    case(
        g,
        "e7_integer_limits",
        "From e7: the largest and smallest integers, leading zeros and signed zeros.",
        "ok",
        "id,k\n1,9007199254740991\n2,-9007199254740991\n3,0009007199254740991\n4,-0\n5,+0\n",
        declaration=one("k", "integer"),
        values={"k": [MAX_INTEGER, -MAX_INTEGER, MAX_INTEGER, 0, 0]},
    )
    case(
        g,
        "e7_integer_2_53",
        "From e7: 2^53 is outside the integer range.",
        "E5006",
        "id,k\n1,9007199254740992\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "e7_integer_beyond",
        "From e7: 9007199254740993, the value of e7.",
        "E5006",
        "id,k\n1,9007199254740993\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "e7_number",
        "From e7: as numbers, 9007199254740993 rounds to the even neighbour "
        "9007199254740992, and 9007199254740995 to 9007199254740996.",
        "ok",
        "id,y\n1,9007199254740993\n2,9007199254740995\n",
        declaration=one("y", "number"),
        values={"y": [9007199254740992.0, 9007199254740996.0]},
    )
    # e8_supplementary_key_order.json: U+FF08 and U+1F600 as keys.
    case(
        g,
        "e8_header_outside_bmp",
        "From e8: a column name outside the BMP.",
        "E5002",
        "id,\uff08,\U0001f600\n1,2,3\n",
        offset=7,
    )
    case(
        g,
        "e8_column_order",
        "From e8: columns keep the order of the header, which is not "
        "sorted, a column name may hold U+FF08 and a value may hold U+1F600.",
        "ok",
        "b,\uff08,a\n\U0001f600,x,y\n",
        values={"b": ["\U0001f600"], "\uff08": ["x"], "a": ["y"]},
    )
    # e9_lone_surrogate.json.
    case(
        g,
        "e9_encoded_surrogate",
        "From e9: the bytes ED A0 80 encode the surrogate U+D800, which is not UTF-8.",
        "E1201",
        b"id,s\n1,\xed\xa0\x80\n",
        offset=7,
    )
    case(
        g,
        "e9_cesu",
        "From e9: U+1F600 encoded as two surrogates (CESU-8) is not UTF-8.",
        "E1201",
        b"id,s\n1,\xed\xa0\xbd\xed\xb8\x80\n",
        offset=7,
    )
    case(
        g,
        "e9_escape_text",
        "From e9: CSV has no escapes, so the text '\\ud800' is six characters of a value.",
        "ok",
        "id,s\n1,\\ud800\n",
        declaration=strings("id", "s"),
        values={"s": ["\\ud800"]},
    )
    # e10_number_layout.json.
    case(
        g,
        "e10_layout",
        "From e10: the number layouts of e10, with forms that only the "
        "table's lexical form allows: '.5', '5.', '+5' and '-.5e+1'.",
        "ok",
        "id,y\n1,0.000001\n2,4.35\n3,0.3\n4,1.0000000000000002\n5,1e-6\n6,0.1\n7,100\n8,1E2\n"
        "9,2.5e1\n10,.5\n11,5.\n12,+5\n13,-.5e+1\n",
        declaration=one("y", "number"),
        values={
            "y": [
                1e-06,
                4.35,
                0.3,
                1.0000000000000002,
                1e-06,
                0.1,
                100.0,
                100.0,
                25.0,
                0.5,
                5.0,
                5.0,
                -5.0,
            ]
        },
    )
    case(
        g,
        "e10_rounding",
        "From e10: decimals that R's as.numeric() misconverts, which the "
        "reader must round correctly (conventions.md, Numbers).",
        "ok",
        "id,y\n1,-76944133.284736\n2,7.32e-97\n3,-6.1892785e-12\n",
        declaration=one("y", "number"),
        values={"y": [-76944133.284736, 7.32e-97, -6.1892785e-12]},
    )
    for name, token, what, offset in [
        ("e10_dot", ".", "a lone '.' has no digit", 7),
        ("e10_exponent_without_digits", "1e", "an exponent needs digits", 7),
        ("e10_decimal_comma", '"1,5"', "the decimal character is '.'", 7),
        ("e10_arabic_indic", "\u0661", "only ASCII digits are digits", 7),
        ("e10_trailing_line_feed", '"1\n"', "a quoted number that ends in a line feed", 7),
        ("e10_hexadecimal", "0x10", "hexadecimal is not a number form", 7),
    ]:
        case(
            g,
            name,
            f"From e10: {what}.",
            "E5006",
            f"id,y\n1,{token}\n",
            declaration=one("y", "number"),
            offset=offset,
        )
    case(
        g,
        "e10_integer_decimal",
        "From e10: '1.0' is a number but not an integer.",
        "E5006",
        "id,k\n1,1.0\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    # e11_empty_containers.json.
    case(
        g,
        "e11_header_only",
        "From e11: a header without records is a table of no rows.",
        "ok",
        "id,y\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        values={"id": [], "y": []},
    )
    case(
        g,
        "e11_header_without_line_break",
        "From e11: a header that ends the text, without "
        "a table block. Columns without values are string columns.",
        "ok",
        "id,y",
        values={"id": [], "y": []},
    )
    case(
        g,
        "e11_empty_line",
        "From e11: in a table of one column, an empty line is a record "
        "with one empty field, which is missing.",
        "ok",
        "id\n\n",
        declaration=strings("id"),
        values={"id": [None]},
    )
    case(
        g,
        "e11_empty_line_no_missing",
        "From e11: with an empty list of missing values, the "
        "empty field of an empty line is the empty string.",
        "ok",
        "id\n\n",
        declaration=block(fld("id", "string", missingValues=[])),
        values={"id": [""]},
    )
    case(
        g,
        "e11_empty_line_two_columns",
        "From e11: an empty line in a table of two columns is "
        "a record of one field, located at its line break.",
        "E5005",
        "id,y\n1,2\n\n",
        offset=9,
    )
    case(
        g,
        "e11_empty_integer",
        "From e11: with an empty list of missing values, an empty "
        "integer is no integer. The empty field is located at the line break that ends it.",
        "E5006",
        "id,k\n1,\n",
        declaration=one("k", "integer", missingValues=[]),
        offset=7,
    )
    case(g, "e11_empty_input", "From e11: an empty input has no record.", "E5001", b"")
    case(
        g,
        "e11_line_break_only",
        "From e11: a text of one line break has one empty record, whose column name is empty.",
        "E5002",
        "\n",
        offset=0,
    )
    # e12_escapes.json: U+2028, U+001F and e acute.
    case(
        g,
        "e12_raw_characters",
        "From e12: U+2028, U+001F and U+00E9 are characters of their values, not escapes.",
        "ok",
        "id,s\n1,line\u2028sep and \u00e9 and \x1f\n",
        declaration=strings("id", "s"),
        values={"s": ["line\u2028sep and \u00e9 and \x1f"]},
    )
    case(
        g,
        "e12_control_message",
        "From e12: the message shows U+001F of a value escaped.",
        "E5006",
        "id,y\n1,1\x1f\n",
        declaration=one("y", "number"),
        offset=7,
    )
    case(
        g,
        "e12_separator_message",
        "From e12: the message shows U+2028 of a value escaped.",
        "E5006",
        "id,k\n1,1\u20282\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "e12_long_value",
        "From e12: the message truncates a value of more than 60 code points to 57 and '...'.",
        "E5006",
        "id,y\n1," + "1234567890" * 7 + "x\n",
        declaration=one("y", "number"),
        offset=7,
    )


def input_stage() -> None:
    g = "input"
    case(g, "missing_file", "A file that does not exist.", "E1001", None, file="missing")
    case(g, "directory", "A directory in place of a file.", "E1002", None, file="directory")
    case(
        g,
        "continuation_byte",
        "A continuation byte without a lead byte.",
        "E1201",
        b"id,s\n1,\x80\n",
        offset=7,
    )
    case(
        g,
        "truncated_sequence",
        "A sequence that the input ends inside is located at its lead byte.",
        "E1201",
        b"id,s\n1,\xe2\x82",
        offset=7,
    )
    case(g, "overlong", "An overlong encoding of '/'.", "E1201", b"id,s\n1,\xc0\xaf\n", offset=7)
    case(
        g,
        "above_10ffff",
        "A sequence above U+10FFFF.",
        "E1201",
        b"id,s\n1,\xf4\x90\x80\x80\n",
        offset=7,
    )
    case(g, "nul_value", "U+0000 in a value.", "E1202", b"id,s\n1,a\x00b\n", offset=8)
    case(g, "nul_in_header", "U+0000 in the header.", "E1202", b"i\x00d\n1\n", offset=1)
    case(
        g,
        "bom_before_invalid",
        "A byte-order mark is reported before invalid UTF-8.",
        "E1003",
        BOM + b"id\n\xff\n",
    )
    case(
        g,
        "noncharacter",
        "The noncharacter U+FFFE and the unassigned U+0378 are characters "
        "of values and column names.",
        "ok",
        "id,\u0378\n1,\ufffe\n",
        values={"\u0378": ["\ufffe"]},
    )


def records() -> None:
    g = "records"
    s2 = strings("id", "s")
    case(
        g,
        "lf",
        "Records ended by LF.",
        "ok",
        "id,s\n1,x\n2,y\n",
        declaration=s2,
        values={"s": ["x", "y"]},
    )
    case(
        g,
        "cr",
        "Records ended by CR alone.",
        "ok",
        "id,s\r1,x\r2,y\r",
        declaration=s2,
        values={"s": ["x", "y"]},
    )
    case(
        g,
        "mixed_line_breaks",
        "LF, CR LF and CR alone in one text, and a last record without a line break.",
        "ok",
        "id,s\n1,x\r\n2,y\r3,z",
        declaration=s2,
        values={"s": ["x", "y", "z"]},
    )
    case(
        g,
        "quoted_crlf",
        "A quoted CR LF is kept as CR LF.",
        "ok",
        'id,s\r\n1,"a\r\nb"\r\n',
        declaration=s2,
        values={"s": ["a\r\nb"]},
    )
    case(
        g,
        "quoted_cr",
        "A quoted CR alone is kept.",
        "ok",
        'id,s\n1,"a\rb"\n',
        declaration=s2,
        values={"s": ["a\rb"]},
    )
    case(
        g,
        "doubled_quotes",
        "A doubled quotation mark in a quoted field stands for one.",
        "ok",
        'id,s\n1,"say ""hi"""\n2,""""\n',
        declaration=s2,
        values={"s": ['say "hi"', '"']},
    )
    case(
        g,
        "quoted_empty",
        "A quoted empty field and an empty field are both the empty "
        "string, so both are missing by default.",
        "ok",
        'id,s\n1,""\n2,\n',
        declaration=s2,
        values={"s": [None, None]},
    )
    case(
        g,
        "quoted_empty_no_missing",
        "With an empty list of missing values, a quoted empty "
        "field and an empty field are both the empty string.",
        "ok",
        'id,s\n1,""\n2,\n',
        declaration=block(fld("id", "string"), fld("s", "string", missingValues=[])),
        values={"s": ["", ""]},
    )
    case(
        g,
        "white_space",
        "Spaces and tabs belong to the field, inside or outside quotation marks.",
        "ok",
        'id,s\n1, x \n2,\tx\n3," x "\n',
        declaration=s2,
        values={"s": [" x ", "\tx", " x "]},
    )
    case(
        g,
        "quoted_header",
        "Quoted column names may hold ',' and '\"'.",
        "ok",
        'id,"a,b","c""d"\n1,2,3\n',
        values={"a,b": [2.0], 'c"d': [3.0]},
    )
    case(
        g,
        "trailing_comma",
        "A ',' before the line break ends the record with an empty field.",
        "ok",
        "id,s\n1,\n",
        declaration=s2,
        values={"s": [None]},
    )
    case(
        g,
        "text_after_quote",
        "Text after the closing quotation mark.",
        "E5004",
        'id,s\n1,"x"y\n',
        offset=10,
    )
    case(
        g,
        "quote_in_unquoted",
        "A quotation mark inside an unquoted field.",
        "E5004",
        'id,s\n1,x"y\n',
        offset=8,
    )
    case(
        g,
        "space_before_quote",
        "A field that starts with a space is unquoted, so its quotation mark is misplaced.",
        "E5004",
        'id,s\n1, "x"\n',
        offset=8,
    )
    case(
        g,
        "space_after_quote",
        "A space after the closing quotation mark.",
        "E5004",
        'id,s\n1,"x" \n',
        offset=10,
    )
    case(
        g,
        "unclosed_quote",
        "A quoted field that the text ends inside is located at its opening quotation mark.",
        "E5004",
        'id,s\n1,"x\n2,y\n',
        offset=7,
    )
    case(g, "header_quote", "A quoting problem in the header.", "E5004", 'id,"s"x\n1,2\n', offset=6)
    case(
        g,
        "too_few",
        "A record with fewer fields than the header.",
        "E5005",
        "id,s,y\n1,x,2\n2,y\n",
        offset=13,
    )
    case(
        g,
        "too_many",
        "A record with more fields than the header, through a trailing ','.",
        "E5005",
        "id,s\n1,x,\n",
        offset=5,
    )
    case(
        g,
        "two_final_line_breaks",
        "Two line breaks at the end make an empty last record.",
        "E5005",
        "id,s\n1,x\r\n\r\n",
        offset=10,
    )


def header() -> None:
    g = "header"
    case(g, "empty_first_name", "An empty first column name.", "E5002", ",a\n1,2\n", offset=0)
    case(
        g,
        "empty_last_name",
        "An empty last column name, located at the line break.",
        "E5002",
        "a,\n1,2\n",
        offset=2,
    )
    case(g, "tab_in_name", "A tab in a quoted column name.", "E5002", '"a\tb",c\n1,2\n', offset=0)
    case(
        g,
        "c1_control_in_name",
        "The C1 control character U+0085 in a column name.",
        "E5002",
        "a,b\u0085\n1,2\n",
        offset=2,
    )
    case(g, "delete_in_name", "U+007F in a column name.", "E5002", "a,b\x7f\n1,2\n", offset=2)
    case(
        g,
        "name_too_long",
        "A column name of 129 characters.",
        "E5002",
        "id," + "n" * 129 + "\n1,2\n",
        offset=3,
    )
    case(
        g,
        "name_128",
        "A column name of 128 characters, the most allowed.",
        "ok",
        "id," + "\u00e9" * 128 + "\n1,2\n",
        values={"\u00e9" * 128: [2.0]},
    )
    case(
        g,
        "repeated_name",
        "A column name that repeats an earlier one.",
        "E5002",
        "a,b,a\n1,2,3\n",
        offset=4,
    )
    case(
        g,
        "name_differs",
        "A column name that differs from the field at its position.",
        "E5003",
        "id,x\n1,2\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=3,
    )
    case(
        g,
        "name_case",
        "Column names are compared without case folding.",
        "E5003",
        "id,Y\n1,2\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=3,
    )
    case(
        g,
        "names_reordered",
        "The fields must follow the order of the columns.",
        "E5003",
        "y,id\n1,2\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=0,
    )
    case(
        g,
        "fewer_columns",
        "A header with fewer columns than the block has fields gives "
        "E5003 at the line break that ends it.",
        "E5003",
        "id\r\n1\r\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=2,
    )
    case(
        g,
        "fewer_columns_end",
        "A header that ends the text and has fewer columns gives E5003 at the end of the text.",
        "E5003",
        "id",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=2,
    )
    case(
        g,
        "more_columns",
        "A header with more columns than the block has fields gives E5003 "
        "at the first column without a field.",
        "E5003",
        "id,y,z\n1,2,3\n",
        declaration=block(fld("id", "string"), fld("y", "number")),
        offset=5,
    )
    case(
        g,
        "names_before_match",
        "An invalid column name gives E5002, although an earlier "
        "column already differs from the block.",
        "E5002",
        "x,a,a\n1,2,3\n",
        declaration=block(fld("y", "string"), fld("a", "string"), fld("b", "string")),
        offset=4,
    )


def values() -> None:
    g = "values"
    case(
        g,
        "field_missing_values",
        "A field's missingValues replace the table's, which "
        "replace the default, so '' and 'NA' are values of 's' and only '-99' is missing.",
        "ok",
        "id,s,t\n1,NA,NA\n2,-99,-99\n3,,\n",
        declaration=block(
            fld("id", "string"),
            fld("s", "string", missingValues=["-99"]),
            fld("t", "string"),
            missingValues=["NA", ""],
        ),
        values={"s": ["NA", None, ""], "t": [None, "-99", None]},
    )
    case(
        g,
        "labelled_sentinel",
        "A labelled sentinel code of an integer field is missing, "
        "and another negative code is a value.",
        "ok",
        "id,k\n1,-99\n2,-98\n3,4\n",
        declaration=one("k", "integer", missingValues=[{"value": "-99", "label": "refused"}]),
        values={"k": [None, -98, 4]},
    )
    case(
        g,
        "missing_before_type",
        "Missing values are matched before the type is checked.",
        "ok",
        "id,k\n1,n/a\n2,5\n",
        declaration=one("k", "integer", missingValues=["n/a"]),
        values={"k": [None, 5]},
    )
    case(
        g,
        "missing_not_trimmed",
        "A space is not the empty string, so it is a value.",
        "ok",
        "id,s\n1, \n2,\n",
        declaration=strings("id", "s"),
        values={"s": [" ", None]},
    )
    case(
        g,
        "missing_category",
        "A missing value is never checked against the categories.",
        "ok",
        "id,s\n1,a\n2,\n3,b\n",
        declaration=one("s", "string", categories=["a", "b"]),
        values={"s": ["a", None, "b"]},
    )
    case(
        g,
        "missing_case",
        "Missing values are compared without case folding.",
        "ok",
        "id,s\n1,na\n2,NA\n",
        declaration=one("s", "string", missingValues=["NA"]),
        values={"s": ["na", None]},
    )
    case(
        g,
        "integer_forms",
        "Leading zeros, signs and signed zeros of integers.",
        "ok",
        "id,k\n1,007\n2,+5\n3,-0\n4,+0\n5,0\n6,-12\n",
        declaration=one("k", "integer"),
        values={"k": [7, 5, 0, 0, 0, -12]},
    )
    case(
        g,
        "integer_underscore",
        "'1_000' is not an integer.",
        "E5006",
        "id,k\n1,1_000\n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "integer_space",
        "A space after an integer.",
        "E5006",
        "id,k\n1,12 \n",
        declaration=one("k", "integer"),
        offset=7,
    )
    case(
        g,
        "boolean_forms",
        "The eight boolean forms.",
        "ok",
        "id,b\n1,true\n2,True\n3,TRUE\n4,1\n5,false\n6,False\n7,FALSE\n8,0\n",
        declaration=one("b", "boolean"),
        values={"b": [True, True, True, True, False, False, False, False]},
    )
    case(
        g,
        "boolean_yes",
        "'yes' is not a boolean.",
        "E5006",
        "id,b\n1,yes\n",
        declaration=one("b", "boolean"),
        offset=7,
    )
    case(
        g,
        "boolean_mixed_case",
        "'tRUE' is not a boolean.",
        "E5006",
        "id,b\n1,tRUE\n",
        declaration=one("b", "boolean"),
        offset=7,
    )
    case(
        g,
        "date_forms",
        "Dates, including 29 February of leap years and the first and last "
        "days of the years allowed, are returned as written.",
        "ok",
        "id,d\n1,2024-02-29\n2,2000-02-29\n3,0001-01-01\n4,9999-12-31\n5,2026-11-08\n",
        declaration=one("d", "date"),
        values={"d": ["2024-02-29", "2000-02-29", "0001-01-01", "9999-12-31", "2026-11-08"]},
    )
    for name, token, what in [
        ("date_not_leap", "2023-02-29", "29 February of a year that is not a leap year"),
        ("date_century", "1900-02-29", "29 February of 1900, which is not a leap year"),
        ("date_year_zero", "0000-01-01", "the year 0000"),
        ("date_month_13", "2026-13-01", "the month 13"),
        ("date_april_31", "2026-04-31", "31 April"),
        ("date_short_month", "2026-1-01", "a month of one digit"),
        ("date_with_time", "2026-11-08T00:00:00", "a date and time"),
    ]:
        case(
            g,
            name,
            f"Not a date: {what}.",
            "E5006",
            f"id,d\n1,{token}\n",
            declaration=one("d", "date"),
            offset=7,
        )
    case(
        g,
        "datetime_forms",
        "Dates and times with and without fractions of a second and "
        "offsets are returned as written.",
        "ok",
        "id,t\n1,2026-11-08T12:00:00\n2,2026-11-08T23:59:59Z\n3,2026-11-08T00:00:00.5+01:00\n"
        "4,2026-11-08T00:00:00.000001-23:59\n5,2024-02-29T12:00:00+00:00\n",
        declaration=one("t", "datetime"),
        values={
            "t": [
                "2026-11-08T12:00:00",
                "2026-11-08T23:59:59Z",
                "2026-11-08T00:00:00.5+01:00",
                "2026-11-08T00:00:00.000001-23:59",
                "2024-02-29T12:00:00+00:00",
            ]
        },
    )
    for name, token, what in [
        ("datetime_hour_24", "2026-11-08T24:00:00", "the hour 24"),
        ("datetime_leap_second", "2026-12-31T23:59:60Z", "the second 60"),
        ("datetime_space", "2026-11-08 12:00:00", "a space in place of 'T'"),
        ("datetime_lower_z", "2026-11-08T12:00:00z", "a lower-case 'z'"),
        ("datetime_offset_24", "2026-11-08T12:00:00+24:00", "an offset of 24 hours"),
        ("datetime_no_seconds", "2026-11-08T12:00", "no seconds"),
        ("datetime_empty_fraction", "2026-11-08T12:00:00.", "a '.' without digits"),
        ("datetime_bad_date", "2023-02-29T00:00:00Z", "a day that does not exist"),
    ]:
        case(
            g,
            name,
            f"Not a date and time: {what}.",
            "E5006",
            f"id,t\n1,{token}\n",
            declaration=one("t", "datetime"),
            offset=7,
        )
    case(
        g,
        "without_type",
        "A field without a type is read as text, so '1' stays a string.",
        "ok",
        "id,a\n1,1\n2,x\n",
        declaration=block(fld("id", "string"), fld("a")),
        values={"a": ["1", "x"]},
    )
    case(
        g,
        "categories",
        "Plain categories and categories with labels; the values are returned as written.",
        "ok",
        "id,s,k\n1,low,1\n2,high,2\n",
        declaration=block(
            fld("id", "string"),
            fld("s", "string", categories=[{"value": "low", "label": "Low"}, {"value": "high"}]),
            fld("k", "integer", categories=[1, 2]),
        ),
        values={"s": ["low", "high"], "k": [1, 2]},
    )
    case(
        g,
        "category_outside",
        "A string value outside the categories.",
        "E5007",
        "id,s\n1,a\n2,c\n",
        declaration=one("s", "string", categories=["a", "b"]),
        offset=11,
    )
    case(
        g,
        "category_case",
        "Categories are compared without case folding.",
        "E5007",
        "id,s\n1,A\n",
        declaration=one("s", "string", categories=["a", "b"]),
        offset=7,
    )
    case(
        g,
        "category_integer_value",
        "Integer categories are compared by value, so '007' and '+2' are the categories 7 and 2.",
        "ok",
        "id,k\n1,007\n2,+2\n",
        declaration=one("k", "integer", categories=[2, 7]),
        values={"k": [7, 2]},
    )
    case(
        g,
        "category_integer_outside",
        "An integer outside the categories.",
        "E5007",
        "id,k\n1,3\n",
        declaration=one("k", "integer", categories=[1, 2]),
        offset=7,
    )
    case(
        g,
        "category_type_first",
        "A value that is no integer gives E5006, not E5007.",
        "E5006",
        "id,k\n1,x\n",
        declaration=one("k", "integer", categories=[1, 2]),
        offset=7,
    )
    case(
        g,
        "value_message_column",
        "The message names the column as the header writes it, here in NFD.",
        "E5006",
        "id,cafe\u0301\n1,x\n",
        declaration=block(fld("id", "string"), fld("caf\u00e9", "number")),
        offset=12,
    )


def inference() -> None:
    g = "inference"
    case(
        g,
        "zero_one",
        "A column of '1' and '0' is a number column.",
        "ok",
        "b\n1\n0\n",
        values={"b": [1.0, 0.0]},
    )
    case(
        g,
        "boolean_words",
        "A column of the six boolean words is a boolean column, and an empty value is missing.",
        "ok",
        "b\nTRUE\nfalse\n\nTrue\n",
        values={"b": [True, False, None, True]},
    )
    case(
        g,
        "boolean_and_one",
        "A column of 'true' and '1' is neither a number nor a boolean column.",
        "ok",
        "b\ntrue\n1\n",
        values={"b": ["true", "1"]},
    )
    case(
        g,
        "all_missing",
        "A column without a value that is not missing is a string column.",
        "ok",
        "a,b\n1,\n2,\n",
        values={"a": [1.0, 2.0], "b": [None, None]},
    )
    case(
        g,
        "number_with_missing",
        "Missing values do not change the type.",
        "ok",
        "y\n1.5\n\n-2\n",
        values={"y": [1.5, None, -2.0]},
    )
    case(
        g,
        "only_nan",
        "A column of 'NaN' and 'inf' is a number column.",
        "ok",
        "y\nNaN\ninf\n",
        values={"y": [NAN, INF]},
    )
    case(
        g,
        "space_before_number",
        "' 1' has no number form, so its column is a string column.",
        "ok",
        "y\n 1\n2\n",
        values={"y": [" 1", "2"]},
    )
    case(
        g,
        "dates",
        "Dates are strings without a table block.",
        "ok",
        "d\n2026-11-08\n",
        values={"d": ["2026-11-08"]},
    )
    case(
        g,
        "overflow",
        "'1e400' has the lexical form of a number, so its column is a number "
        "column, and the value gives E5006.",
        "E5006",
        "y\n1\n1e400\n",
        offset=4,
    )
    case(
        g,
        "structure_first",
        "Without a table block, the record of the wrong length later "
        "in the file is reported before the value that gives E5006.",
        "E5005",
        "y\n1e400\n1,2\n",
        offset=8,
    )
    case(
        g,
        "structure_first_declared",
        "With a table block, the same text gives E5006 at the earlier record.",
        "E5006",
        "y\n1e400\n1,2\n",
        declaration=block(fld("y", "number")),
        offset=2,
    )
    case(
        g,
        "quote_after_value",
        "Without a table block, a quoting problem later in the file is "
        "reported before the value that gives E5006.",
        "E5004",
        'y\n1e400\n"x\n',
        offset=8,
    )
    case(
        g,
        "nfd_labels",
        "Labels that differ only in their Unicode form are returned as "
        "written. The IR merges them (ir.md).",
        "ok",
        "g\ncaf\u00e9\ncafe\u0301\n",
        values={"g": ["caf\u00e9", "cafe\u0301"]},
    )


def keys() -> None:
    g = "keys"
    two = [fld("id", "string"), fld("y", "number")]
    case(
        g,
        "primary",
        "A primary key without missing or repeated values.",
        "ok",
        "id,y\n1,2\n2,2\n",
        declaration=block(*two, primaryKey=["id"]),
        values={"id": ["1", "2"]},
    )
    case(
        g,
        "primary_missing",
        "A missing value in the primary key.",
        "E5008",
        "id,y\n1,2\n,3\n",
        declaration=block(*two, primaryKey=["id"]),
        offset=9,
    )
    case(
        g,
        "primary_duplicate",
        "A record repeats the primary key of the first record.",
        "E5009",
        "id,y\n1,2\n2,3\n1,4\n",
        declaration=block(*two, primaryKey=["id"]),
        offset=13,
    )
    composite = [fld("school", "string"), fld("pupil", "string"), fld("y", "number")]
    case(
        g,
        "composite",
        "A composite primary key whose columns repeat on their own.",
        "ok",
        "school,pupil,y\nA,1,1\nA,2,2\nB,1,3\n",
        declaration=block(*composite, primaryKey=["school", "pupil"]),
        values={"pupil": ["1", "2", "1"]},
    )
    case(
        g,
        "composite_duplicate",
        "A composite primary key repeated.",
        "E5009",
        "school,pupil,y\nA,1,1\nB,1,2\nA,1,3\n",
        declaration=block(*composite, primaryKey=["school", "pupil"]),
        offset=27,
    )
    case(
        g,
        "missing_in_key_order",
        "With both columns missing, E5008 names the first column of primaryKey.",
        "E5008",
        "a,b\n1,2\n,\n",
        declaration=block(fld("a", "string"), fld("b", "string"), primaryKey=["b", "a"]),
        offset=9,
    )
    case(
        g,
        "integer_by_value",
        "Integers are compared by value, so '7' repeats '007'.",
        "E5009",
        "k,y\n007,1\n7,2\n",
        declaration=block(fld("k", "integer"), fld("y", "number"), primaryKey=["k"]),
        offset=10,
    )
    case(
        g,
        "string_by_text",
        "Strings are compared as text, so '7' and '007' differ.",
        "ok",
        "k,y\n007,1\n7,2\n",
        declaration=block(fld("k", "string"), fld("y", "number"), primaryKey=["k"]),
        values={"k": ["007", "7"]},
    )
    case(
        g,
        "string_nfc",
        "Strings are compared after NFC.",
        "E5009",
        "k,y\ncaf\u00e9,1\ncafe\u0301,2\n",
        declaration=block(fld("k", "string"), fld("y", "number"), primaryKey=["k"]),
        offset=12,
    )
    case(
        g,
        "number_nan",
        "NaN equals NaN in a key.",
        "E5009",
        "k,y\nNaN,1\nnan,2\n",
        declaration=block(fld("k", "number"), fld("y", "number"), primaryKey=["k"]),
        offset=10,
    )
    case(
        g,
        "number_zero",
        "Negative zero equals zero, and 1 equals 1.0.",
        "E5009",
        "k,y\n0,1\n-0,2\n",
        declaration=block(fld("k", "number"), fld("y", "number"), primaryKey=["k"]),
        offset=8,
    )
    case(
        g,
        "boolean_by_value",
        "'1' and 'true' are one boolean value.",
        "E5009",
        "k,y\ntrue,1\n1,2\n",
        declaration=block(fld("k", "boolean"), fld("y", "number"), primaryKey=["k"]),
        offset=11,
    )
    three = [fld("id", "string"), fld("email", "string"), fld("code", "string")]
    case(
        g,
        "unique",
        "Unique keys without repeated values.",
        "ok",
        "id,email,code\n1,a,x\n2,b,y\n",
        declaration=block(*three, primaryKey=["id"], uniqueKeys=[["email"], ["code"]]),
        values={"code": ["x", "y"]},
    )
    case(
        g,
        "unique_duplicate",
        "A repeated value of the first unique key.",
        "E5010",
        "id,email,code\n1,a,x\n2,a,y\n",
        declaration=block(*three, uniqueKeys=[["email"], ["code"]]),
        offset=20,
    )
    case(
        g,
        "unique_second",
        "A repeated value of the second unique key.",
        "E5010",
        "id,email,code\n1,a,x\n2,b,x\n",
        declaration=block(*three, uniqueKeys=[["email"], ["code"]]),
        offset=20,
    )
    case(
        g,
        "unique_missing",
        "Records with a missing value in a unique key are not compared on it.",
        "ok",
        "id,email,code\n1,,x\n2,,x\n3,a,\n",
        declaration=block(*three, uniqueKeys=[["email", "code"]]),
        values={"email": [None, None, "a"]},
    )
    case(
        g,
        "primary_before_unique",
        "The primary key is checked over every record before the unique keys.",
        "E5009",
        "id,email,code\n1,a,x\n2,a,y\n1,c,z\n",
        declaration=block(*three, primaryKey=["id"], uniqueKeys=[["email"]]),
        offset=26,
    )
    case(
        g,
        "values_before_keys",
        "Keys are checked after every value, so a value error later in the file is reported first.",
        "E5006",
        "id,y\n1,2\n1,3\n2,x\n",
        declaration=block(*two, primaryKey=["id"]),
        offset=15,
    )


def precedence() -> None:
    g = "precedence"
    num = block(fld("id", "string"), fld("y", "number"))
    case(
        g,
        "earlier_record_first",
        "A value error in an earlier record before a record of the wrong length.",
        "E5006",
        "id,y\n1,x\n2\n",
        declaration=num,
        offset=7,
    )
    case(
        g,
        "quote_before_value",
        "Within a record, a quoting problem comes before a value error earlier in the record.",
        "E5004",
        'id,y,z\n1,x,"a"b\n',
        declaration=block(fld("id", "string"), fld("y", "number"), fld("z", "string")),
        offset=14,
    )
    case(
        g,
        "length_before_value",
        "Within a record, its length comes before its values.",
        "E5005",
        "id,y\n1,x,3\n",
        declaration=num,
        offset=5,
    )
    case(
        g,
        "first_column_first",
        "Values are checked from left to right.",
        "E5006",
        "id,y,z\n1,x,y\n",
        declaration=block(fld("id", "string"), fld("y", "number"), fld("z", "number")),
        offset=9,
    )
    case(
        g,
        "header_quote_before_name",
        "In the header, a quoting problem comes before an "
        "invalid column name earlier in the header.",
        "E5004",
        ',a"b\n1,2\n',
        offset=2,
    )
    case(
        g,
        "header_before_records",
        "The header is checked before any record.",
        "E5003",
        "id,z\n1,x,3\n",
        declaration=num,
        offset=3,
    )
    case(
        g,
        "value_before_unclosed_quote",
        "A value error in an earlier record before a quoted field that the text ends inside.",
        "E5006",
        'id,y\n1,x\n2,"3\n',
        declaration=num,
        offset=7,
    )
    case(
        g,
        "utf8_before_nul",
        "Invalid UTF-8 later in the input is reported before an earlier U+0000.",
        "E1201",
        b"id,s\n1,\x00\n2,\xff\n",
        offset=11,
    )
    case(
        g,
        "utf8_before_header",
        "Invalid UTF-8 in a record is reported before an empty column name.",
        "E1201",
        b",a\n1,\xff\n",
        offset=5,
    )


def samples() -> None:
    g = "samples"
    declaration = block(
        fld("id", "string"),
        fld("g", "string"),
        fld("x", "number"),
        fld("y", "number"),
        fld("note", "string"),
    )
    case(
        g,
        "missing_columns",
        "A missing predictor removes its row from the design sample, a "
        "missing response only from the analysis sample, and a missing value of a column that "
        "the formula does not read from neither.",
        "ok",
        "id,g,x,y,note\n1,a,1,2,\n2,b,,3,n\n3,,2,4,n\n4,a,3,,n\n5,b,4,5,n\n",
        declaration=declaration,
        formula="y ~ x + g",
        reads=("y", ["x", "g"]),
        design=[0, 3, 4],
        analysis=[0, 4],
    )
    case(
        g,
        "grouping_factor",
        "A missing grouping factor removes its row from the design sample.",
        "ok",
        "id,g,x,y,note\n1,a,1,2,n\n2,,2,3,n\n3,b,3,4,n\n4,a,4,5,n\n",
        declaration=declaration,
        formula="y ~ x + (1 | g)",
        reads=("y", ["x", "g"]),
        design=[0, 2, 3],
        analysis=[0, 2, 3],
    )
    case(
        g,
        "sentinel",
        "A labelled sentinel code removes its row like any missing value, "
        "whereas 'NA' in a string column is a level.",
        "ok",
        "id,g,x\n1,NA,1\n2,a,-99\n3,a,2\n4,NA,-98\n",
        declaration=block(
            fld("id", "string"),
            fld("g", "string"),
            fld("x", "integer", missingValues=[{"value": "-99", "label": "refused"}]),
        ),
        formula="x ~ g",
        reads=("x", ["g"]),
        design=[0, 1, 2, 3],
        analysis=[0, 2, 3],
    )
    case(
        g,
        "empty_level",
        "With an empty list of missing values, the empty string is a level, "
        "so its row stays in both samples.",
        "ok",
        "id,g,y\n1,,1\n2,a,2\n3,b,\n",
        declaration=block(
            fld("id", "string"), fld("g", "string", missingValues=[]), fld("y", "number")
        ),
        formula="y ~ g",
        reads=("y", ["g"]),
        values={"g": ["", "a", "b"]},
        design=[0, 1, 2],
        analysis=[0, 1],
    )
    case(
        g,
        "trials",
        "A binomial response with trials: a row with 0 trials or missing trials "
        "leaves the analysis sample but stays in the design sample.",
        "ok",
        "id,x,k,n\n1,1,2,5\n2,2,0,0\n3,3,1,\n4,4,,4\n5,5,3,3\n",
        declaration={
            "vocabulary": "0.1.0",
            "table": {
                "fields": [
                    fld("id", "string"),
                    fld("x", "number"),
                    fld("k", "integer"),
                    fld("n", "integer"),
                ]
            },
            "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
        },
        formula="k ~ x",
        reads=("k", ["x"]),
        design=[0, 1, 2, 3, 4],
        analysis=[0, 4],
    )
    case(
        g,
        "nan_value",
        "NaN is a value of a number column, so its row stays in both samples. "
        "Computing a mean centring constant or building X later gives E6073 (ir.md).",
        "ok",
        "id,x,y\n1,NaN,1\n2,2,\n3,3,3\n",
        declaration=block(fld("id", "string"), fld("x", "number"), fld("y", "number")),
        formula="y ~ x",
        reads=("y", ["x"]),
        design=[0, 1, 2],
        analysis=[0, 2],
    )


def build_cases() -> list[Case]:
    CASES.clear()
    for make in (
        edgezoo,
        edge,
        input_stage,
        records,
        header,
        values,
        inference,
        keys,
        precedence,
        samples,
    ):
        make()
    return CASES


# --- Expected outputs ----------------------------------------------------------


def _json_value(value: Any, kind: str) -> Any:
    if value is None:
        return None
    if kind == "number":
        if math.isnan(value):
            return NAN
        if math.isinf(value):
            return INF if value > 0 else NINF
        return value + 0.0
    return value


def _same(left: Any, right: Any) -> bool:
    if isinstance(left, float) and isinstance(right, float):
        return left == right
    return type(left) is type(right) and left == right


def _check_declaration(name: str, declaration: dict) -> None:
    bundle = cr.Bundle(ROOT / "spec" / "schemas")
    validator = cr.Validator(bundle, CATALOGUE)
    issues = validator.validate(declaration, bundle.node(DECLARATION_SCHEMA))
    if issues or cr.profile_issue(declaration, CATALOGUE) is not None:
        raise AssertionError(f"{name}: the declaration is not valid: {issues}")
    table = declaration.get("table")
    if table is None:
        return
    names = [f["name"] for f in table["fields"]]
    if len(names) != len(set(names)):
        raise AssertionError(f"{name}: repeated field")
    referenced = list(table.get("primaryKey", []))
    for unique in table.get("uniqueKeys", []):
        referenced += unique
    for column, entry in declaration.get("variables", {}).items():
        referenced.append(column)
        if "trials" in entry:
            referenced.append(entry["trials"])
    if not set(referenced) <= set(names):
        raise AssertionError(f"{name}: a reference does not resolve")
    for f in table["fields"]:
        for category in f.get("categories", []):
            value = category["value"] if isinstance(category, dict) else category
            kind = int if f["type"] == "integer" else str
            if not isinstance(value, kind) or isinstance(value, bool):
                raise AssertionError(f"{name}: a category has the wrong type")


def expected_output(c: Case) -> dict:
    name = f"{c.group}/{c.name}"
    if c.declaration is not None:
        _check_declaration(name, c.declaration)
    if c.file is not None:
        code = "E1001" if c.file == "missing" else "E1002"
        found = Refusal(code).issue()
        if found["code"] != c.code:
            raise AssertionError(f"{name}: expected {c.code}")
        return {"issue": found}
    assert c.data is not None
    table = c.declaration["table"] if c.declaration else None
    try:
        result = read_table(c.data, table)
    except Refusal as refusal:
        found = refusal.issue()
        if found["code"] != c.code:
            raise AssertionError(f"{name}: expected {c.code}, derived {found}") from None
        if c.offset is not None and found.get("offset") != c.offset:
            raise AssertionError(f"{name}: expected offset {c.offset}, derived {found}") from None
        if c.formula is not None:
            raise AssertionError(f"{name}: a refused table has no samples") from None
        return {"issue": found}
    if c.code != "ok":
        raise AssertionError(f"{name}: expected {c.code}, derived a table")
    ORACLE.records(c.data, result)
    columns = []
    for i, column in enumerate(result.names):
        kind = result.types[i]
        values_ = [_json_value(row[i], kind) for row in result.rows]
        columns.append({"name": column, "type": kind, "values": values_})
    by_name = {column["name"]: column["values"] for column in columns}
    for column, stated in (c.values or {}).items():
        derived = by_name[column]
        if len(derived) != len(stated) or not all(map(_same, derived, stated)):
            raise AssertionError(f"{name}: column {column!r} derived {derived}, stated {stated}")
    out: dict[str, Any] = {"columns": columns}
    if c.formula is not None:
        assert c.reads is not None
        response, others = c.reads
        for column in [response, *others]:
            if not re.search(
                r"(?<![A-Za-z0-9_.])" + re.escape(column) + r"(?![A-Za-z0-9_.])", c.formula
            ):
                raise AssertionError(f"{name}: {column} is not in the formula")
        trials = None
        if c.declaration is not None:
            trials = c.declaration.get("variables", {}).get(response, {}).get("trials")
        index = {column: i for i, column in enumerate(result.names)}
        design = [
            r
            for r, row in enumerate(result.rows)
            if all(row[index[column]] is not None for column in others)
        ]
        analysis = [
            r
            for r in design
            if result.rows[r][index[response]] is not None
            and (trials is None or (result.rows[r][index[trials]] or 0) > 0)
        ]
        if c.design is not None and c.design != design:
            raise AssertionError(f"{name}: design sample {design}, stated {c.design}")
        if c.analysis is not None and c.analysis != analysis:
            raise AssertionError(f"{name}: analysis sample {analysis}, stated {c.analysis}")
        out["design_sample"] = design
        out["analysis_sample"] = analysis
    return out


def corpus() -> tuple[dict[str, str], dict[str, bytes]]:
    """The text of every JSON file and the bytes of every input, by path."""
    texts: dict[str, str] = {}
    inputs: dict[str, bytes] = {}
    documents: dict[str, list] = {group: [] for group in GROUPS}
    counters: dict[str, int] = {group: 0 for group in GROUPS}
    for c in build_cases():
        counters[c.group] += 1
        entry: dict[str, Any] = {
            "id": f"tables-{c.group}-{counters[c.group]:03d}",
            "description": c.description,
        }
        if c.file is not None:
            entry["file"] = c.file
        else:
            path = f"{c.group}/{c.name}.csv"
            if path in inputs:
                raise AssertionError(f"{path} serves two cases")
            entry["path"] = path
            assert c.data is not None
            inputs[path] = c.data
        if c.declaration is not None:
            entry["declaration"] = c.declaration
        if c.formula is not None:
            entry["formula"] = c.formula
        entry["expected"] = expected_output(c)
        documents[c.group].append(entry)
    for group, description in GROUPS.items():
        document = {"description": description, "cases": documents[group]}
        texts[f"{group}.json"] = json.dumps(document, indent=2, ensure_ascii=True) + "\n"
    return texts, inputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="compare, write nothing")
    options = parser.parse_args()
    texts, inputs = corpus()
    wanted = {name: text.encode("ascii") for name, text in texts.items()} | inputs
    on_disk = {
        str(path.relative_to(CORPUS)).replace("\\", "/")
        for path in CORPUS.rglob("*")
        if path.is_file() and path.name != "README.md"
    }
    if options.check:
        problems = sorted(set(wanted) ^ on_disk)
        problems += [
            name
            for name in sorted(set(wanted) & on_disk)
            if (CORPUS / name).read_bytes() != wanted[name]
        ]
        for problem in problems:
            print(f"differs: fixtures/conformance/tables/{problem}", file=sys.stderr)
        return 1 if problems else 0
    for name in sorted(on_disk - set(wanted)):
        (CORPUS / name).unlink()
    for name, data in wanted.items():
        path = CORPUS / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(f"wrote {len(texts)} files with {len(CASES)} cases and {len(inputs)} inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
