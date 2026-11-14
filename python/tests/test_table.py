"""Edge cases of the strict table reader that the table corpus does not cover
(docs/spec/tables.md), and a loose check of its speed."""

from __future__ import annotations

import json
import math
import pathlib
import time
from typing import Any

import pytest

from mixedcheck import MixedcheckError, read_table


def write(tmp_path: pathlib.Path, data: bytes, name: str = "data.csv") -> str:
    path = tmp_path / name
    path.write_bytes(data)
    return str(path)


def table_block(*fields: dict[str, Any], **members: Any) -> dict[str, Any]:
    return {"vocabulary": "0.1.0", "table": {"fields": list(fields), **members}}


def issue_of(path: str, declaration: Any = None) -> dict[str, Any]:
    with pytest.raises(MixedcheckError) as caught:
        read_table(path, declaration)
    assert len(caught.value.issues) == 1
    return caught.value.issues[0]


def test_columns_have_dtype_object_and_python_values(tmp_path):
    path = write(tmp_path, b"s,k,y,b,d\nx,9007199254740991,1.5,1,2026-01-31\n,,,,\n")
    declaration = table_block(
        {"name": "s", "type": "string"},
        {"name": "k", "type": "integer"},
        {"name": "y", "type": "number"},
        {"name": "b", "type": "boolean"},
        {"name": "d", "type": "date"},
    )
    frame = read_table(path, declaration)
    assert list(frame.columns) == ["s", "k", "y", "b", "d"]
    assert all(dtype.kind == "O" for dtype in frame.dtypes)
    assert list(frame.attrs["types"].items()) == [
        ("s", "string"),
        ("k", "integer"),
        ("y", "number"),
        ("b", "boolean"),
        ("d", "date"),
    ]
    first = frame.iloc[0].tolist()
    assert first == ["x", 9007199254740991, 1.5, True, "2026-01-31"]
    assert [type(value) for value in first] == [str, int, float, bool, str]
    assert frame.iloc[1].tolist() == [None] * 5


def test_negative_zero_stays_negative(tmp_path):
    path = write(tmp_path, b"y\n-0\n0\n-0.0e5\n")
    for declaration in (None, table_block({"name": "y", "type": "number"})):
        values = read_table(path, declaration)["y"].tolist()
        assert [math.copysign(1.0, value) for value in values] == [-1.0, 1.0, -1.0]


def test_zero_from_zero_digits_is_a_number(tmp_path):
    path = write(tmp_path, b"y\n0e-500\n0.000e999\n")
    assert read_table(path)["y"].tolist() == [0.0, 0.0]
    path = write(tmp_path, b"y\n0.0001e-400\n")
    assert issue_of(path)["code"] == "E5006"


def test_integers_of_many_digits(tmp_path):
    # int() refuses strings of more than 4,300 digits, so the range is
    # checked on the digits first.
    long = b"1" * 5000
    path = write(tmp_path, b"k\n" + long + b"\n")
    issue = issue_of(path, table_block({"name": "k", "type": "integer"}))
    assert issue["code"] == "E5006"
    assert issue["offset"] == 2
    assert issue["message"] == (
        "The value '" + "1" * 57 + "...' of the column 'k' at byte 2 cannot be read as an integer."
    )
    path = write(tmp_path, b"k\n" + b"0" * 5000 + b"7\n")
    assert read_table(path, table_block({"name": "k", "type": "integer"}))["k"].tolist() == [7]
    path = write(tmp_path, b"y\n" + long + b"\n")
    assert issue_of(path)["code"] == "E5006"


def test_special_numbers_and_their_signs(tmp_path):
    path = write(tmp_path, b"y\nnan\nInf\n-inF\nNAN\n")
    values = read_table(path)["y"].tolist()
    assert math.isnan(values[0]) and math.isnan(values[3])
    assert values[1:3] == [math.inf, -math.inf]
    declaration = table_block({"name": "y", "type": "number"})
    for text in (b"+nan", b"+Inf", b"-Infinity", b"inf "):
        issue = issue_of(write(tmp_path, b"y\n" + text + b"\n"), declaration)
        assert (issue["code"], issue["offset"]) == ("E5006", 2)


def test_a_quoted_field_that_the_text_ends_inside(tmp_path):
    # After 'ab', the doubled '"' stands for one, so the field runs to the end
    # of the text and is located at its opening '"'.
    issue = issue_of(write(tmp_path, b'id,s\n1,"ab""'))
    assert (issue["code"], issue["offset"]) == ("E5004", 7)
    frame = read_table(write(tmp_path, b'id,s\n1,"a""b\n2,x"\n'))
    assert frame["s"].tolist() == ['a"b\n2,x']
    assert frame["id"].tolist() == [1.0]


def test_a_line_break_in_a_column_name(tmp_path):
    issue = issue_of(write(tmp_path, b'"a\nb",c\n1,2\n'))
    assert (issue["code"], issue["offset"]) == ("E5002", 0)


def test_fewer_columns_than_fields_at_a_cr_lf(tmp_path):
    path = write(tmp_path, b"id\r\n1\r\n")
    declaration = table_block({"name": "id", "type": "string"}, {"name": "y", "type": "number"})
    issue = issue_of(path, declaration)
    assert (issue["code"], issue["offset"]) == ("E5003", 2)


def test_offsets_count_bytes(tmp_path):
    declaration = table_block({"name": "é", "type": "string"}, {"name": "y", "type": "number"})
    issue = issue_of(write(tmp_path, "é,y\n1,x\n".encode()), declaration)
    assert (issue["code"], issue["offset"]) == ("E5006", 7)
    issue = issue_of(write(tmp_path, "é,é\n".encode()))
    assert (issue["code"], issue["offset"]) == ("E5002", 3)
    # A problem far into a text that is not ASCII.
    text = "s,y\n" + "é,1\n" * 1000 + "é,x\n"
    declaration = table_block({"name": "s", "type": "string"}, {"name": "y", "type": "number"})
    issue = issue_of(write(tmp_path, text.encode()), declaration)
    assert issue == {
        "code": "E5006",
        "message": "The value 'x' of the column 'y' at byte 5007 cannot be read as a number.",
        "offset": 5007,
    }


def test_an_earlier_record_comes_before_an_earlier_column(tmp_path):
    path = write(tmp_path, b"id,y,z\n1,1,x\n2,x,1\n")
    declaration = table_block(
        {"name": "id", "type": "string"},
        {"name": "y", "type": "number"},
        {"name": "z", "type": "number"},
    )
    issue = issue_of(path, declaration)
    assert issue == {
        "code": "E5006",
        "message": "The value 'x' of the column 'z' at byte 11 cannot be read as a number.",
        "offset": 11,
    }


def test_missing_values_and_categories_compared_after_nfc(tmp_path):
    # U+212A KELVIN SIGN has the NFC form 'K', and U+212B ANGSTROM SIGN the
    # NFC form U+00C5.
    path = write(tmp_path, "id,s,t\n1,K,Å\n2,K,Å\n".encode())
    declaration = table_block(
        {"name": "id", "type": "string"},
        {"name": "s", "type": "string", "missingValues": ["K"]},
        {"name": "t", "type": "string", "categories": ["Å"]},
    )
    frame = read_table(path, declaration)
    assert frame["s"].tolist() == [None, None]
    assert frame["t"].tolist() == ["Å", "Å"]


def test_integer_categories_given_as_objects(tmp_path):
    declaration = table_block(
        {"name": "k", "type": "integer", "categories": [{"value": 2}, {"value": 7, "label": "x"}]}
    )
    assert read_table(write(tmp_path, b"k\n007\n+2\n"), declaration)["k"].tolist() == [7, 2]
    issue = issue_of(write(tmp_path, b"k\n7\n3\n"), declaration)
    assert (issue["code"], issue["offset"]) == ("E5007", 4)


def test_dates_and_times_that_do_not_exist(tmp_path):
    declaration = table_block({"name": "t", "type": "datetime"})
    for text in (
        b"2026-11-08T12:00:00+01:60",
        b"2026-11-08T12:60:00",
        b"2026-02-29T00:00:00",
        b"0000-01-01T00:00:00",
        b"2026-00-01T00:00:00Z",
        b"2026-13-01T00:00:00Z",
    ):
        issue = issue_of(write(tmp_path, b"t\n" + text + b"\n"), declaration)
        assert (issue["code"], issue["offset"]) == ("E5006", 2)
    declaration = table_block({"name": "d", "type": "date"})
    for text in (b"2026-00-10", b"2026-06-00", b"2400-02-30"):
        issue = issue_of(write(tmp_path, b"d\n" + text + b"\n"), declaration)
        assert (issue["code"], issue["offset"]) == ("E5006", 2)
    assert read_table(write(tmp_path, b"d\n2400-02-29\n"), declaration)["d"].tolist() == [
        "2400-02-29"
    ]


def test_a_duplicate_primary_key_before_a_missing_one(tmp_path):
    # The records are taken in order, so the duplicate in the second record
    # is reported before the missing value in the third.
    declaration = table_block(
        {"name": "id", "type": "string"}, {"name": "y", "type": "number"}, primaryKey=["id"]
    )
    issue = issue_of(write(tmp_path, b"id,y\na,1\na,2\n,3\n"), declaration)
    assert issue == {
        "code": "E5009",
        "message": (
            "The record at byte 9 has the same values in the primary key as the record at byte 5."
        ),
        "offset": 9,
    }
    issue = issue_of(write(tmp_path, b"id,y\n,1\na,2\na,3\n"), declaration)
    assert issue == {
        "code": "E5008",
        "message": (
            "The value of the column 'id' at byte 5 is missing, but the column belongs to the "
            "primary key."
        ),
        "offset": 5,
    }


def test_unique_keys_are_checked_one_after_the_other(tmp_path):
    declaration = table_block(
        {"name": "id", "type": "string"},
        {"name": "a", "type": "string"},
        {"name": "b", "type": "string"},
        uniqueKeys=[["a"], ["b"]],
    )
    issue = issue_of(write(tmp_path, b"id,a,b\n1,1,x\n2,2,x\n3,1,y\n"), declaration)
    assert (issue["code"], issue["offset"]) == ("E5010", 19)
    assert issue["message"] == (
        "The record at byte 19 has the same values in unique key 1 of the table block as the "
        "record at byte 7."
    )


def test_columns_without_a_table_block(tmp_path):
    frame = read_table(write(tmp_path, b"b,n,s\nTRUE,1,\n,,x\nfalse,2,\n"))
    assert frame.attrs["types"] == {"b": "boolean", "n": "number", "s": "string"}
    assert frame["b"].tolist() == [True, None, False]
    assert frame["n"].tolist() == [1.0, None, 2.0]
    assert frame["s"].tolist() == [None, "x", None]
    # A declaration without a table block reads the table by the same rules.
    frame = read_table(write(tmp_path, b"id\n1\n\n2\n"), {"vocabulary": "0.1.0"})
    assert frame["id"].tolist() == [1.0, None, 2.0]


def test_paths(tmp_path):
    path = pathlib.Path(write(tmp_path, b"a\nx\n"))
    assert read_table(path)["a"].tolist() == ["x"]
    with pytest.raises(TypeError):
        read_table(b"a\nx\n")  # type: ignore[arg-type]


def test_declarations_from_files_and_their_validation(tmp_path):
    path = write(tmp_path, b"k\n1\n")
    declaration = table_block({"name": "k", "type": "integer"})
    json_path = tmp_path / "design.json"
    json_path.write_text(json.dumps(declaration), encoding="utf-8")
    assert read_table(path, str(json_path)).attrs["types"] == {"k": "integer"}
    # The declaration is validated first, so its issue comes before that of
    # a file that does not exist.
    with pytest.raises(MixedcheckError) as caught:
        read_table(str(tmp_path / "missing.csv"), {"vocabulary": "0.2.0"})
    assert [issue["code"] for issue in caught.value.issues] == ["E1441"]
    with pytest.raises(MixedcheckError) as caught:
        read_table(path, {"vocabulary": "0.1.0", "table": {"fields": []}})
    assert caught.value.issues[0]["code"] == "E1413"


def test_declaration_in_yaml(tmp_path):
    pytest.importorskip("yaml")
    path = write(tmp_path, b"k,s\n007,a\n")
    yaml_path = tmp_path / "design.yaml"
    yaml_path.write_text(
        "vocabulary: 0.1.0\ntable:\n  fields:\n"
        "    - {name: k, type: integer, categories: [7]}\n    - {name: s, type: string}\n",
        encoding="utf-8",
    )
    frame = read_table(path, str(yaml_path))
    assert frame["k"].tolist() == [7]
    assert frame.attrs["types"] == {"k": "integer", "s": "string"}


def test_reading_is_fast(tmp_path):
    # About 1.3 MB with 10,000 records of 12 columns, read in about 0.15 s.
    # The bound is loose, so that a slow machine does not fail the test, and
    # the 10 MB table of the performance target reads in about 1.3 s.
    lines = ["id,s,c,k,y,b,d,t,u,v,w,z"]
    for i in range(10_000):
        lines.append(
            f"o{i},S{i % 50},{'abc'[i % 3]},{i},{i / 7:.6f},{'true' if i % 2 else 'false'},"
            f"2026-01-{1 + i % 28:02d},2026-01-01T00:00:{i % 60:02d}Z,{i * 0.5},"
            f'"x, {i}",{-i},'
        )
    path = write(tmp_path, ("\n".join(lines) + "\n").encode())
    declaration = table_block(
        {"name": "id", "type": "string"},
        {"name": "s", "type": "string"},
        {"name": "c", "type": "string", "categories": ["a", "b", "c"]},
        {"name": "k", "type": "integer"},
        {"name": "y", "type": "number"},
        {"name": "b", "type": "boolean"},
        {"name": "d", "type": "date"},
        {"name": "t", "type": "datetime"},
        {"name": "u", "type": "number"},
        {"name": "v", "type": "string"},
        {"name": "w", "type": "integer"},
        {"name": "z"},
        primaryKey=["id"],
    )
    start = time.perf_counter()
    frame = read_table(path, declaration)
    elapsed = time.perf_counter() - start
    assert frame.shape == (10_000, 12)
    assert frame["v"].iloc[9] == "x, 9"
    assert elapsed < 10
