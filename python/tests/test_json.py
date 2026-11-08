"""Targeted tests of the strict reader and the serialiser, beyond the cases of
the JSON corpus."""

from __future__ import annotations

import math
import sys
import types
from pathlib import Path

import pytest

from mixedcheck import (
    MixedcheckError,
    canonical_bytes,
    canonical_hash,
    hash_bytes,
    read_json_strict,
)


def issue_of(f, *args):
    try:
        f(*args)
    except MixedcheckError as err:
        assert len(err.issues) == 1
        return err.issues[0]
    return None


def test_the_reader_returns_dicts_lists_numbers_booleans_none_and_str():
    value = read_json_strict(
        '{"a":[1,2.5,true,null,{}],"b":"caf\xe9","c":[],"d":{"x":-0}}'.encode()
    )
    assert list(value) == ["a", "b", "c", "d"]
    assert value["a"] == [1, 2.5, True, None, {}]
    assert type(value["a"][0]) is int
    assert type(value["a"][1]) is float
    assert value["b"] == "caf\xe9"
    assert value["c"] == []
    assert value["d"]["x"] == 0


def test_numbers_become_int_or_float_as_conventions_md_requires():
    value = read_json_strict(b"[1, -0, 1.0, 1e2, 9007199254740991, 9007199254740993, -12]")
    assert [type(item) for item in value] == [int, int, float, float, int, float, int]
    assert value[5] == 9007199254740992.0


def test_long_number_tokens_are_classified_without_converting_them_to_int():
    # Python refuses to convert a str of more than 4,300 digits to an int.
    assert issue_of(read_json_strict, b"9" * 5000, "data")["code"] == "E1105"
    assert issue_of(read_json_strict, b"9" * 5000, "hashable")["code"] == "E1102"
    assert issue_of(read_json_strict, b"1e" + b"9" * 5000, "hashable")["code"] == "E1102"
    assert issue_of(read_json_strict, b"1e-" + b"9" * 5000, "data")["code"] == "E1106"
    value = read_json_strict(b"1" + b"0" * 300, "data")
    assert type(value) is float and value == 1e300


def test_the_reader_keeps_the_order_of_members_and_reads_a_top_level_scalar():
    assert list(read_json_strict(b'{"z":1,"a":2}', "hashable")) == ["z", "a"]
    assert read_json_strict(b' "x" ', "plain") == "x"
    assert read_json_strict(b"12", "hashable") == 12
    assert read_json_strict(b"null", "data") is None


def test_the_reader_reads_files_and_reports_missing_and_unreadable_ones(tmp_path):
    path = tmp_path / "a.json"
    path.write_bytes(b'{"a": "b"}')
    assert read_json_strict(path, "hashable") == {"a": "b"}
    assert read_json_strict(str(path), "hashable") == {"a": "b"}
    assert issue_of(read_json_strict, str(path) + "-missing")["code"] == "E1001"
    assert issue_of(read_json_strict, tmp_path)["code"] == "E1002"
    assert read_json_strict(bytearray(b"[1]")) == [1]
    with pytest.raises(TypeError, match="file path or a bytes object"):
        read_json_strict(1)
    with pytest.raises(ValueError, match="'profile' must be"):
        read_json_strict(b"1", "strict")


def test_an_error_carries_its_issue():
    with pytest.raises(MixedcheckError) as caught:
        read_json_strict(b'{"a":1,"a":2}')
    assert isinstance(caught.value, ValueError)
    assert str(caught.value) == "Duplicate key 'a' at byte 7."
    assert caught.value.issues == [
        {"code": "E1029", "message": "Duplicate key 'a' at byte 7.", "offset": 7}
    ]


def test_offsets_count_bytes_after_non_ascii_characters():
    assert issue_of(read_json_strict, '["\xe9", x]'.encode())["offset"] == 7
    assert issue_of(read_json_strict, '["\U0001f600"'.encode())["offset"] == 7
    assert issue_of(read_json_strict, '{"\xe9":1,"\xe9":2}'.encode())["offset"] == 8


def test_the_reader_handles_escapes():
    text = r'["\\", "\\\"", "aé😀", "\\u0041", "\n\t\/", "\\\\", "𐀀A"]'
    value = read_json_strict(text.encode(), "plain")
    assert value == ["\\", '\\"', "a\xe9\U0001f600", "\\u0041", "\n\t/", "\\\\", "\U00010000A"]
    # A high surrogate at the end of one string is not paired with a low one
    # at the start of the next.
    assert issue_of(read_json_strict, rb'["\ud800","\udc00"]', "plain") == {
        "code": "E1026",
        "message": "Unpaired surrogate escape in a string at byte 1.",
        "offset": 1,
    }
    # A high surrogate escape followed by a malformed escape is a syntax error.
    assert issue_of(read_json_strict, rb'["\ud800\u12x4"]', "plain")["code"] == "E1025"


def test_a_syntax_error_takes_precedence_over_an_earlier_value_error():
    assert issue_of(read_json_strict, b'[null, "a", ]', "hashable")["code"] == "E1022"
    assert issue_of(read_json_strict, b'[null, "a"] x', "hashable")["code"] == "E1023"
    assert issue_of(read_json_strict, b'[null, "\\u0000"]', "hashable")["code"] == "E1101"


def test_the_reader_reads_a_large_document():
    item = '{"check":"structure.cluster_sizes","value":0.30000000000000004,"labels":["a","b\\"c"]}'
    data = ("[" + ",".join([item] * 20000) + "]").encode()
    value = read_json_strict(data, "data")
    assert len(value) == 20000
    assert value[19999]["labels"][1] == 'b"c'
    written = (
        '{"check":"structure.cluster_sizes","labels":["a","b\\"c"],"value":0.30000000000000004}'
    )
    assert canonical_bytes(value, "data") == ("[" + ",".join([written] * 20000) + "]").encode()


def test_the_writer_refuses_values_that_have_no_json_form():
    def code_of(x, profile="data"):
        return issue_of(canonical_bytes, x, profile)

    assert code_of({"a": (1, 2)}) == {
        "code": "E1301",
        "message": "The value at /a has the type 'tuple', which has no JSON form.",
        "pointer": "/a",
    }
    assert (
        code_of([{1}])["message"] == "The value at /0 has the type 'set', which has no JSON form."
    )
    assert code_of([b"x"])["code"] == "E1301"
    assert code_of([1j])["code"] == "E1301"
    assert code_of({"a": {1: 2}}) == {
        "code": "E1301",
        "message": "The value at /a has the type 'int', which has no JSON form.",
        "pointer": "/a",
    }
    with pytest.raises(ValueError, match="'profile' must be"):
        canonical_bytes([], "strict")


def test_the_writer_reports_the_first_problem_in_canonical_order():
    value = {"b": [math.nan], "a": {"x": None, "w": (1, 2)}}
    assert issue_of(canonical_bytes, value, "hashable")["pointer"] == "/a/w"
    assert issue_of(canonical_bytes, value, "data")["pointer"] == "/a/w"
    value["a"]["w"] = 1
    assert issue_of(canonical_bytes, value, "hashable")["pointer"] == "/a/x"
    assert canonical_bytes(value, "data") == b'{"a":{"w":1,"x":null},"b":["NaN"]}'


def test_the_writer_writes_missing_values_and_non_finite_numbers_by_profile():
    value = [None, math.nan, math.inf, -math.inf, 3, False, -0.0]
    assert canonical_bytes(value, "data") == b'[null,"NaN","Infinity","-Infinity",3,false,0]'
    assert canonical_bytes(value, "plain") == b'[null,"NaN","Infinity","-Infinity",3,false,0]'
    assert issue_of(canonical_bytes, [math.inf], "hashable")["code"] == "E1107"
    assert issue_of(canonical_bytes, [None], "hashable")["code"] == "E1101"


def test_the_writer_checks_python_ints_and_strs():
    assert canonical_bytes([2**53 - 1, -(2**53 - 1)]) == b"[9007199254740991,-9007199254740991]"
    assert issue_of(canonical_bytes, [2**53], "plain")["code"] == "E1102"
    assert issue_of(canonical_bytes, ["a\ud800"], "plain") == {
        "code": "E1206",
        "message": "The string at /0 contains a surrogate code point.",
        "pointer": "/0",
    }
    # A key that holds a surrogate cannot appear in a pointer, so it is
    # reported at the pointer of its object.
    assert issue_of(canonical_bytes, {"a": {"\udc00": 1}}, "plain")["pointer"] == "/a"
    assert issue_of(canonical_bytes, {"a": {"": 1}}, "plain") == {
        "code": "E1109",
        "message": "Empty key at /a/.",
        "pointer": "/a/",
    }
    assert issue_of(canonical_bytes, {"a\x00": 1}, "plain")["code"] == "E1202"
    assert issue_of(canonical_bytes, ["a\x00"], "plain")["code"] == "E1202"


def test_the_writer_sorts_keys_by_utf16_code_units():
    data = canonical_bytes({"（": 1, "\U0001f600": 2, "a": 3}, "plain")
    assert data == '{"a":3,"\U0001f600":2,"（":1}'.encode()
    assert issue_of(canonical_bytes, {"\U0001f600": 1}, "data")["code"] == "E1108"
    assert canonical_bytes({"\U0001f600": 1}, "plain") == '{"\U0001f600":1}'.encode()


def test_numpy_scalars_are_converted_without_importing_numpy(monkeypatch):
    class Integer(int):
        pass

    class Floating(float):
        pass

    class Bool:
        def __init__(self, value):
            self.value = value

        def __bool__(self):
            return self.value

    fake = types.ModuleType("numpy")
    fake.integer = Integer
    fake.floating = Floating
    fake.bool_ = Bool
    monkeypatch.setitem(sys.modules, "numpy", fake)
    value = [Integer(3), Floating(0.5), Bool(True), Bool(False)]
    assert canonical_bytes(value) == b"[3,0.5,true,false]"
    monkeypatch.delitem(sys.modules, "numpy")
    assert issue_of(canonical_bytes, [Bool(True)])["code"] == "E1301"


def test_numpy_scalars_and_arrays_when_numpy_is_installed():
    numpy = pytest.importorskip("numpy")
    value = [numpy.int64(3), numpy.float32(0.5), numpy.bool_(True), numpy.float64(0.1)]
    assert canonical_bytes(value, "hashable") == b"[3,0.5,true,0.1]"
    assert issue_of(canonical_bytes, [numpy.int64(2**62)])["code"] == "E1102"
    assert issue_of(canonical_bytes, [numpy.array([1, 2])])["code"] == "E1301"


def test_canonical_bytes_do_not_depend_on_the_order_of_members_or_the_profile():
    a = {"b": [1, "x"], "a": True}
    b = {"a": True, "b": [1.0, "x"]}
    assert canonical_bytes(a, "hashable") == canonical_bytes(b, "plain")
    assert canonical_hash(a, "hashable") == hash_bytes(b'{"a":true,"b":[1,"x"]}')
    assert canonical_bytes(read_json_strict(canonical_bytes(a)), "data") == canonical_bytes(a)


def test_canonical_hash_of_a_file_equals_the_hash_of_the_value(tmp_path: Path):
    from mixedcheck import hash_file

    value = {"title": "study", "n": [1, 2.5]}
    path = tmp_path / "value.json"
    path.write_bytes(canonical_bytes(value, "hashable"))
    assert hash_file(path) == canonical_hash(value, "hashable")
