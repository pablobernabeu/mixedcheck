"""Targeted tests of the structural validator on the keywords and rules that
the declaration schema does not use, with a schema added to a copy of the
vendored bundle."""

from __future__ import annotations

from mixedcheck._errors import finish_issues
from mixedcheck._schema import (
    Bundle,
    has_json_type,
    json_equal,
    json_kind,
    schema_bundle,
    schema_issues,
)

TEST_SCHEMA = {
    "$id": "urn:test",
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "n": {
            "type": "number",
            "minimum": 0,
            "maximum": 10,
            "exclusiveMinimum": -1,
            "exclusiveMaximum": 11,
        },
        "any": {"anyOf": [{"type": "string"}, {"type": "integer", "minimum": 5}]},
        "one": {"oneOf": [{"type": "number"}, {"type": "integer"}]},
        "has": {"type": "array", "contains": {"const": "x"}},
        "no": {"not": {"type": "string"}},
        "pair": {
            "type": "array",
            "prefixItems": [{"type": "string"}, {"type": "boolean"}],
            "items": False,
        },
        "map": {
            "type": "object",
            "patternProperties": {"^x-": {"type": "integer"}},
            "additionalProperties": False,
            "maxProperties": 2,
        },
        "date": {"$ref": "urn:mixedcheck:schema:defs#/$defs/date"},
        "constant": {"$ref": "urn:mixedcheck:schema:defs#/$defs/decimal_constant"},
        "line": {"type": "string", "pattern": "^a$", "title": "line"},
    },
}


def make_bundle() -> Bundle:
    return Bundle([*schema_bundle().schemas.values(), TEST_SCHEMA])


def checked(value, bundle=None):
    issues = finish_issues(schema_issues(value, "urn:test", bundle or make_bundle()))
    return [f"{issue['code']} {issue.get('pointer', '')} {issue['message']}" for issue in issues]


def test_numbers_are_checked_against_their_limits():
    assert checked({"n": 0}) == []
    assert checked({"n": -2}) == [
        "E1409 /n The number at /n is less than 0.",
        "E1411 /n The number at /n must be greater than -1.",
    ]
    assert checked({"n": 12}) == [
        "E1410 /n The number at /n is greater than 10.",
        "E1412 /n The number at /n must be less than 11.",
    ]


def test_any_of_and_one_of_report_the_alternative_of_the_value_type_or_e1421_or_e1422():
    assert checked({"any": "s", "one": 1.5}) == []
    assert checked({"any": True}) == [
        "E1421 /any The value at /any matches none of the allowed forms."
    ]
    assert checked({"any": 3}) == ["E1409 /any The number at /any is less than 5."]
    assert checked({"one": 1}) == [
        "E1422 /one The value at /one matches more than one of the allowed forms."
    ]
    assert checked({"one": "a"}) == [
        "E1421 /one The value at /one matches none of the allowed forms."
    ]


def test_contains_not_prefix_items_and_a_false_schema_report_their_own_codes():
    assert checked({"has": ["y", "x"], "no": 1, "pair": ["a", True]}) == []
    assert checked({"has": ["y"]}) == [
        "E1420 /has The array at /has has no item of the required form."
    ]
    assert checked({"no": "s"}) == ["E1423 /no The value at /no is not allowed."]
    assert checked({"pair": [1, True, 3]}) == [
        "E1401 /pair/0 Expected string at /pair/0, found number.",
        "E1423 /pair/2 The value at /pair/2 is not allowed.",
    ]


def test_pattern_properties_and_max_properties_apply_to_the_members_of_an_object():
    assert checked({"map": {"x-a": 1}}) == []
    assert checked({"map": {"x-a": "s", "b": 1, "c": 2}}) == [
        "E1403 /map Unknown key 'b' in the object at /map.",
        "E1403 /map Unknown key 'c' in the object at /map.",
        "E1417 /map The object at /map has more than 2 members.",
        "E1401 /map/x-a Expected integer at /map/x-a, found string.",
    ]


def test_the_day_of_a_date_is_checked_against_its_month_in_integer_arithmetic():
    for date in ("2024-02-29", "2000-02-29", "0004-02-29", "2023-12-31", "9999-04-30"):
        assert checked({"date": date}) == [], date
    for date in ("2023-02-29", "1900-02-29", "2023-04-31", "0001-02-29"):
        assert checked({"date": date}) == [
            "E1406 /date The string at /date is not a valid date."
        ], date
    assert checked({"date": "2023-13-01"}) == [
        "E1406 /date The string at /date is not a valid date."
    ]
    assert checked({"date": 20230101}) == ["E1401 /date Expected string at /date, found number."]


def test_a_decimal_constant_has_at_most_its_significant_digits():
    assert checked({"constant": {"significant_digits": 2, "value": "1200"}}) == []
    assert checked({"constant": {"significant_digits": 3, "value": "-0.00125"}}) == []
    assert checked({"constant": {"significant_digits": 2, "value": "-0.00125"}}) == [
        "E1406 /constant/value The string at /constant/value is not a valid decimal constant."
    ]
    assert checked({"constant": "1.5"}) == [
        "E1401 /constant Expected object at /constant, found string."
    ]


def test_patterns_match_over_code_points_and_dollar_only_at_the_end_of_the_string():
    bundle = make_bundle()
    assert checked({"line": "a"}, bundle) == []
    assert checked({"line": "a\n"}, bundle) == [
        "E1406 /line The string at /line is not a valid line."
    ]
    column_name = "^[\\u0020-\\u007E\\u00A0-\\uFFFF]*$"
    assert not bundle.matches(column_name, "\U0001f600")
    assert bundle.matches(column_name, "�")
    assert bundle.matches("^.$", "\U0001f600")


def test_json_equal_compares_numbers_by_value_and_objects_whatever_their_order():
    assert json_equal(1, 1.0)
    assert not json_equal(1, "1")
    assert not json_equal(True, 1)
    assert json_equal({"a": 1, "b": ["x"]}, {"b": ["x"], "a": 1})
    assert not json_equal({"a": 1}, [1])
    assert not json_equal([1, 2], [2, 1])
    assert json_equal("\xe9", "\xe9")
    assert not json_equal("\xe9", "é")
    assert has_json_type(2, "integer")
    assert has_json_type(2.0, "integer")
    assert not has_json_type(2.5, "integer")
    assert not has_json_type(True, "integer")
    assert has_json_type(2.5, "number")
    assert json_kind({}) == "object"
    assert json_kind([]) == "array"
    assert json_kind(None) == "null"


def test_unique_items_compares_canonical_forms_in_time_proportional_to_the_items():
    import time

    schema = {"$id": "urn:test:unique", "type": "array", "uniqueItems": True}
    bundle = Bundle([*schema_bundle().schemas.values(), schema])
    keys = [["school", f"pupil{i}", i % 3] for i in range(10000)]
    start = time.perf_counter()
    assert schema_issues(keys, "urn:test:unique", bundle) == []
    assert time.perf_counter() - start < 1.0
    repeated = [*keys[:3], ["school", "pupil1", 1.0], {"b": [1], "a": 2}, {"a": 2.0, "b": [1.0]}]
    issues = finish_issues(schema_issues(repeated, "urn:test:unique", bundle))
    assert [issue["pointer"] for issue in issues] == ["/3", "/5"]
    assert {issue["code"] for issue in issues} == {"E1415"}
    assert schema_issues([1, True, "1", None, [1], {"1": 1}], "urn:test:unique", bundle) == []
