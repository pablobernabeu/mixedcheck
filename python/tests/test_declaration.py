"""Targeted tests of the declaration validator, beyond the cases of the
declaration corpus: values in memory, arguments, the order of issues and the
helpers of the rules in code."""

from __future__ import annotations

import copy
from pathlib import Path

import pytest

from mixedcheck import MixedcheckError, canonical_bytes, validate_declaration
from mixedcheck._declaration import is_yaml_path, pointer_resolves
from mixedcheck._schema import term_variables


def issues_of(*args, **kwargs):
    try:
        validate_declaration(*args, **kwargs)
    except MixedcheckError as err:
        return err.issues
    return []


def codes_of(issues):
    return [issue["code"] for issue in issues]


def pointers_of(issues):
    return [issue.get("pointer", "") for issue in issues]


def minimal_declaration():
    return {
        "vocabulary": "0.1.0",
        "goal": "confirmatory",
        "units": [
            {"name": "school", "columns": ["school"], "role": "cluster"},
            {
                "name": "pupil",
                "columns": ["pupil"],
                "nested_in": "school",
                "id_scope": "global",
                "role": "participant",
            },
        ],
        "observation": {"unit": "pupil", "key": ["pupil"]},
        "assignment": [{"column": "arm", "unit": "school", "randomised": True}],
        "variables": {
            "score": {"role": "outcome", "measurement": "continuous"},
            "arm": {"role": "assigned"},
        },
        "estimands": [{"id": "ITT", "term": "arm", "kind": "total_effect"}],
    }


def test_a_declaration_in_memory_is_checked_and_returned_as_the_reader_returns_it():
    declaration = minimal_declaration()
    value = validate_declaration(declaration)
    assert canonical_bytes(value, "hashable") == canonical_bytes(declaration, "hashable")
    assert list(value) == sorted(declaration)
    assert validate_declaration(declaration, minimal=True) == value
    declaration["variables"]["score"]["bounds"] = [0.0, 100]
    declaration["variables"]["score"]["measurement"] = "bounded_score"
    value = validate_declaration(declaration)
    assert [type(bound) for bound in value["variables"]["score"]["bounds"]] == [int, int]


def test_a_value_in_memory_passes_the_writer_checks_of_the_hashable_profile_first():
    declaration = minimal_declaration()
    declaration["title"] = None
    issues = issues_of(declaration)
    assert codes_of(issues) == ["E1101"]
    assert pointers_of(issues) == ["/title"]

    declaration = minimal_declaration()
    declaration["units"][0]["columns"] = ("school", "class")
    issues = issues_of(declaration)
    assert codes_of(issues) == ["E1301"]
    assert pointers_of(issues) == ["/units/0/columns"]

    declaration = minimal_declaration()
    declaration["title"] = "é"
    assert codes_of(issues_of(declaration)) == ["E1203"]

    declaration = minimal_declaration()
    declaration["title"] = "caf\udce9"
    assert codes_of(issues_of(declaration)) == ["E1206"]

    assert codes_of(issues_of(["0.1.0"])) == ["E1401"]
    assert codes_of(issues_of(b"0.1.0")) == ["E1301"]


def test_the_arguments_are_checked():
    with pytest.raises(TypeError, match="'minimal' must be"):
        validate_declaration(minimal_declaration(), minimal=None)
    with pytest.raises(TypeError, match="'minimal' must be"):
        validate_declaration(minimal_declaration(), minimal="yes")


def test_a_file_is_read_as_yaml_only_when_its_name_ends_in_yaml_or_yml(tmp_path: Path):
    assert is_yaml_path("design.yaml")
    assert is_yaml_path("design.YML")
    assert is_yaml_path("dir/design.Yaml")
    assert not is_yaml_path("design.json")
    assert not is_yaml_path("design.yaml.json")
    assert not is_yaml_path("design.yamlx")
    assert not is_yaml_path("yaml")
    assert not is_yaml_path("design.yaml\n")

    path = tmp_path / "declaration.json"
    path.write_bytes(canonical_bytes(minimal_declaration(), "hashable"))
    expected = canonical_bytes(minimal_declaration(), "hashable")
    assert canonical_bytes(validate_declaration(path), "hashable") == expected
    assert canonical_bytes(validate_declaration(str(path)), "hashable") == expected
    assert codes_of(issues_of(tmp_path / "no-such-declaration.json")) == ["E1001"]


def test_the_minimal_declaration_applies_to_a_confirmatory_goal_trial_features_and_the_argument():
    declaration: dict = {"vocabulary": "0.1.0"}
    assert issues_of(declaration) == []
    assert codes_of(issues_of(declaration, minimal=True)) == [
        "E2028",
        "E2028",
        "E2028",
        "E2028",
        "E2030",
    ]
    declaration["goal"] = "exploratory"
    assert issues_of(declaration) == []
    declaration["features"] = ["observational"]
    assert codes_of(issues_of(declaration, minimal=True)) == ["E2028"] * 4

    declaration = minimal_declaration()
    declaration["estimands"][0]["focal"] = False
    declaration["provenance"] = {"inferred": ["/units/0/role"]}
    assert codes_of(issues_of(declaration)) == ["E2031", "E2032"]
    del declaration["goal"]
    assert issues_of(declaration) == []


def test_the_version_is_checked_first_and_a_missing_or_non_string_version_is_structural():
    declaration = minimal_declaration()
    declaration["vocabulary"] = "0.1.01"
    declaration["units"] = "none"
    issues = issues_of(declaration)
    assert codes_of(issues) == ["E1441"]
    assert issues[0]["message"] == (
        "Version '0.1.01' at /vocabulary is not supported. This release reads version 0.1.x."
    )
    long = "0.1." + "1" * 29
    declaration["vocabulary"] = long
    assert codes_of(issues_of(declaration)) == ["E1441"]
    declaration["vocabulary"] = long[:32]
    assert codes_of(issues_of(declaration)) == ["E1401"]
    del declaration["vocabulary"]
    assert codes_of(issues_of(declaration)) == ["E1402", "E1401"]


def test_issues_are_sorted_by_code_point():
    declaration = {
        "vocabulary": "0.1.0",
        "table": {"fields": [{"name": "Z"}, {"name": "a"}]},
        "variables": {
            "\xe9": {"role": "auxiliary"},
            "b": {"role": "auxiliary"},
            "B": {"role": "auxiliary"},
            "a": {"role": "auxiliary"},
        },
    }
    issues = issues_of(declaration)
    assert codes_of(issues) == ["E2007"] * 3
    assert pointers_of(issues) == ["/variables/B", "/variables/b", "/variables/\xe9"]


def test_term_variables_splits_a_term_into_its_variables():
    assert term_variables("arm") == ["arm"]
    assert term_variables("arm:pre.test_1") == ["arm", "pre.test_1"]
    assert term_variables("`a:b`:c:`d e`") == ["a:b", "c", "d e"]
    assert term_variables("`x`:x") == ["x", "x"]
    assert term_variables("`\U0001f600`:a") == ["\U0001f600", "a"]


def test_pointer_resolves_follows_rfc_6901():
    document = {"a": [1, {"b/c": True, "d~e": "x"}]}
    assert pointer_resolves(document, "")
    assert pointer_resolves(document, "/a")
    assert pointer_resolves(document, "/a/1/b~1c")
    assert pointer_resolves(document, "/a/1/d~0e")
    assert not pointer_resolves(document, "/a/2")
    assert not pointer_resolves(document, "/a/01")
    assert not pointer_resolves(document, "/a/-")
    assert not pointer_resolves(document, "/a/0/x")
    assert not pointer_resolves(document, "/a/1/b/c")
    assert not pointer_resolves(document, "/b")
    assert not pointer_resolves(document, "/a/")
    assert not pointer_resolves(document, "/a/" + "1" * 5000)


def test_the_rules_in_code_compare_numbers_by_value_and_strings_by_code_point():
    declaration = {
        "vocabulary": "0.1.0",
        "table": {
            "fields": [
                {"name": "hit", "type": "integer", "categories": [0, 1]},
                {"name": "acc", "type": "string", "categories": ["a", "\xe9"]},
                {"name": "x", "type": "number"},
            ]
        },
        "variables": {
            "hit": {"role": "outcome", "measurement": "binary", "event_level": 1.0},
            "acc": {"role": "outcome", "measurement": "binary", "event_level": "\xe9"},
        },
        "estimands": [{"id": "e", "term": "x", "outcome": "hit"}],
    }
    assert issues_of(declaration) == []
    declaration["variables"]["hit"]["event_level"] = 1
    assert issues_of(declaration) == []
    changed = copy.deepcopy(declaration)
    changed["table"]["fields"][1]["categories"][1] = "\xe8"
    issues = issues_of(changed)
    assert codes_of(issues) == ["E2024"]
    assert issues[0]["message"] == (
        "The event level '\xe9' at /variables/acc/event_level is not one of the categories "
        "of its field."
    )


def test_the_rules_on_units_follow_nesting_to_its_end():
    units = [
        {"name": "a", "columns": ["a"], "nested_in": "b", "id_scope": "global"},
        {"name": "b", "columns": ["b"], "nested_in": "c", "id_scope": "global"},
        {"name": "c", "columns": ["c"], "nested_in": "b", "id_scope": "global"},
        {"name": "d", "columns": ["d"]},
    ]
    declaration = {
        "vocabulary": "0.1.0",
        "units": units,
        "crossings": [{"units": ["a", "c"]}, {"units": ["d", "a"]}],
    }
    issues = issues_of(declaration)
    assert codes_of(issues) == ["E2011", "E2010", "E2010"]
    assert pointers_of(issues) == [
        "/crossings/0/units",
        "/units/1/nested_in",
        "/units/2/nested_in",
    ]
