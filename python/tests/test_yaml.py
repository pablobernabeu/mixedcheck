"""Targeted tests of the YAML authoring reader, beyond the cases of the YAML
corpus: the pre-scan, which needs no package, the reader without PyYAML and
the conversion of positions that the corpus does not reach."""

from __future__ import annotations

from pathlib import Path

import pytest

import mixedcheck._yaml as reader
from mixedcheck import MixedcheckError, canonical_bytes, canonical_hash, validate_declaration


def prescan(text: str) -> str:
    problem = reader.yaml_prescan(text)
    if problem is None:
        return ""
    code, offset = problem
    return f"{code} {'' if offset is None else offset}"


def yaml_file(tmp_path: Path, text: str | bytes, name: str = "declaration.yaml") -> Path:
    path = tmp_path / name
    path.write_bytes(text.encode("utf-8") if isinstance(text, str) else text)
    return path


def issue_codes(path) -> list[str]:
    try:
        validate_declaration(path)
    except MixedcheckError as err:
        return [
            f"{issue['code']} {issue.get('pointer', issue.get('offset', ''))}"
            for issue in err.issues
        ]
    return []


def convert(text: str):
    yaml = pytest.importorskip("yaml")
    if not getattr(yaml, "__with_libyaml__", False):
        pytest.skip("PyYAML is built without libyaml")
    parsed = reader.yaml_parse(text, yaml)
    reader.yaml_check_keys(parsed, [])
    return reader.yaml_convert_declaration(parsed)


def test_the_prescan_skips_comments_quoted_scalars_and_block_scalars():
    assert prescan("a: b # &anchor *alias !tag\n") == ""
    assert prescan("a: 'x &y ''*z'' !t'\n") == ""
    assert prescan('a: "x &y \\" *z"\n') == ""
    assert prescan("a: |\n  &x\n\n  *y\nb: c\n") == ""
    assert prescan("a: >\n  &x\n&b: c\n") == "E3004 10"
    assert prescan("a: b&c *d\n") == ""
    assert prescan("a: b<<\nb: '<<c'\n") == ""
    assert prescan("? [a]\n: b\n") == ""
    assert prescan("a: b#c\n") == ""
    assert prescan("#c\n---\na: b\n...\n# end\n") == ""


def test_the_prescan_finds_anchors_aliases_tags_directives_and_merge_keys():
    assert prescan("a: &x b\n") == "E3004 3"
    assert prescan("a: [b, *x]\n") == "E3004 7"
    assert prescan("a:\n- &x b\n") == "E3004 5"
    assert prescan("a: {b: c,  &x d: e}\n") == "E3004 11"
    assert prescan("a: b\r&c: d\r") == "E3004 5"
    assert prescan("'a': &x b\n") == "E3004 5"
    assert prescan("a: !!str b\n") == "E3005 3"
    assert prescan("%YAML 1.1\n---\na: b\n") == "E3005 0"
    assert prescan("<< : {a: b}\n") == "E3009 0"
    assert prescan("a: {<<: {b: c}}\n") == "E3009 4"


def test_the_prescan_refuses_every_plain_scalar_that_starts_with_merge():
    assert prescan("a: <<\n") == "E3009 3"
    assert prescan("a: <<c\n") == "E3009 3"
    assert prescan("a: <<\u00e9\n") == "E3009 3"
    assert prescan("? <<\n") == "E3009 2"
    assert prescan("?\n    <<\r\n: b") == "E3009 6"
    assert prescan("a: [b, <<]\n") == "E3009 7"
    # libyaml reads '?' and ':' as indicators inside brackets whatever follows.
    assert prescan("a: {?<<: {b: c}}\n") == "E3009 5"
    assert prescan("a: {?&x b: c}\n") == "E3004 5"
    assert prescan('a: {"b":!x c}\n') == "E3005 8"
    assert prescan("a: [b?<<]\n") == ""


def test_the_prescan_ends_lines_at_nel_and_the_separators_as_libyaml_does():
    assert prescan("a:\x85  &x b\n") == "E3004 6"
    assert prescan("a: b\x85!x c: d\n") == "E3005 6"
    assert prescan("a:\x85  <<: {b: c}\n") == "E3009 6"
    assert prescan("a: b # c\u2029&x d: e\n") == "E3004 11"
    assert prescan("a: x\u2028---\nb: 1\n") == "E3003 7"
    assert prescan("\x85") == "E3010 "
    assert prescan("a: |\u2028  &x\u2029b: c\n") == ""
    # Other characters outside ASCII are content.
    assert prescan("\u202a") == ""


def test_the_parser_reports_a_missing_document_or_a_construct_that_the_prescan_misses():
    yaml = pytest.importorskip("yaml")
    if not getattr(yaml, "__with_libyaml__", False):
        pytest.skip("PyYAML is built without libyaml")
    with pytest.raises(MixedcheckError) as caught:
        reader.yaml_parse("\x85", yaml)
    assert caught.value.issues == [{"code": "E3010", "message": "The YAML text holds no document."}]
    for text, what in [
        ("a: b\n---\nc: d\n", "a second document"),
        ("a: &x b\n", "an anchor or an alias"),
        ("a: !t b\n", "a tag"),
    ]:
        with pytest.raises(MixedcheckError) as caught:
            reader.yaml_parse(text, yaml)
        assert caught.value.issues == [
            {
                "code": "E9001",
                "message": f"Internal error: the YAML pre-scan missed {what}. Please report it.",
            }
        ]


def test_a_syntax_error_has_pyyaml_s_exception_as_its_cause():
    yaml = pytest.importorskip("yaml")
    if not getattr(yaml, "__with_libyaml__", False):
        pytest.skip("PyYAML is built without libyaml")
    with pytest.raises(MixedcheckError) as caught:
        reader.yaml_parse("a: {b: 1\n", yaml)
    assert caught.value.issues == [{"code": "E3002", "message": "The YAML text cannot be parsed."}]
    assert str(caught.value) == "The YAML text cannot be parsed."
    cause = caught.value.__cause__
    assert isinstance(cause, yaml.YAMLError)
    assert (cause.problem_mark.line, cause.problem_mark.column) == (1, 0)


def test_the_check_of_keys_walks_any_depth_and_keeps_the_order_of_the_text():
    deep: list = ["x"]
    for _ in range(5000):
        deep = [deep]
    reader.yaml_check_keys(deep, [])
    late = reader._Mapping([("a", [reader._Mapping([("", "x")])]), ("b", "y")])
    with pytest.raises(MixedcheckError) as caught:
        reader.yaml_check_keys(late, [])
    assert caught.value.issues[0]["pointer"] == "/a/0/"


def test_the_prescan_counts_documents_and_finds_u_0000():
    assert prescan("---\na: b\n---\nc: d\n") == "E3003 9"
    assert prescan("a: b\n...\nc: d\n") == "E3003 9"
    assert prescan("# only a comment\n") == "E3010 "
    assert prescan("") == "E3010 "
    assert prescan("---\n") == "E3010 "
    assert prescan('a: "x\\x00"\n') == "E1202 5"
    assert prescan('a: "x\\U00000000"\n') == "E1202 5"
    assert prescan('a: "x\\\\0"\n') == ""
    assert reader.yaml_prescan("a: b\n# x\x00\n") == ("E1202", 8)
    assert reader.yaml_prescan("a: '\x00'\n&x: b\n") == ("E1202", 4)
    # Offsets count bytes.
    assert reader.yaml_prescan('\xe9: "\\0"\n') == ("E1202", 5)


def test_reading_yaml_without_pyyaml_gives_e3001(tmp_path, monkeypatch):
    monkeypatch.setattr(reader, "_import_yaml", lambda: None)
    path = yaml_file(tmp_path, "vocabulary: 0.1.0\n")
    with pytest.raises(MixedcheckError) as caught:
        validate_declaration(path)
    assert caught.value.issues == [
        {"code": "E3001", "message": "Reading YAML needs the package 'PyYAML'."}
    ]
    bom = yaml_file(tmp_path, b"\xef\xbb\xbfvocabulary: 0.1.0\n", "bom.yaml")
    assert issue_codes(bom) == ["E1003 "]
    invalid = yaml_file(tmp_path, b"vocabulary: 0.1.0\xff\n", "invalid.yml")
    assert issue_codes(invalid) == ["E1201 17"]


def test_pyyaml_without_libyaml_counts_as_missing(tmp_path, monkeypatch):
    yaml = pytest.importorskip("yaml")
    monkeypatch.setattr(yaml, "__with_libyaml__", False)
    assert reader.yaml_module() is None
    with pytest.raises(MixedcheckError) as caught:
        validate_declaration(yaml_file(tmp_path, "vocabulary: 0.1.0\n"))
    assert caught.value.issues == [
        {
            "code": "E3001",
            "message": "Reading YAML needs the package 'PyYAML built with libyaml'.",
        }
    ]


def test_keys_that_are_mappings_or_empty_are_refused_before_conversion(tmp_path):
    pytest.importorskip("yaml")
    assert issue_codes(yaml_file(tmp_path, "? {a: b}\n: c\n", "a.yaml")) == ["E3006 "]
    assert issue_codes(yaml_file(tmp_path, "a:\n  - ? [x]\n    : 1\n", "f.yaml")) == ["E3006 /a/0"]
    assert issue_codes(yaml_file(tmp_path, "vocabulary: 0.1.0\n'': x\n", "b.yaml")) == ["E1109 /"]
    assert issue_codes(yaml_file(tmp_path, "a: [{b: {'': c}}]\n", "c.yaml")) == ["E1109 /a/0/b/"]
    # A key is checked after the values of the members before it.
    text = "a: {'': x}\n? [b]\n: c\n"
    assert issue_codes(yaml_file(tmp_path, text, "d.yaml")) == ["E1109 /a/"]
    text = "a: {b: x}\n? [b]\n: {'': c}\n"
    assert issue_codes(yaml_file(tmp_path, text, "e.yaml")) == ["E3006 "]


def test_complex_keys_are_equal_only_when_they_have_the_same_kind_and_items(tmp_path):
    pytest.importorskip("yaml")
    # Two equal keys are reported when their mapping ends, before step 4
    # refuses complex keys.
    assert issue_codes(yaml_file(tmp_path, "? [a, b]\n: 1\n? [a, b]\n: 2\n", "a.yaml")) == [
        "E3007 "
    ]
    assert issue_codes(yaml_file(tmp_path, "? {a: b}\n: 1\n? {a: b}\n: 2\n", "b.yaml")) == [
        "E3007 "
    ]
    # A scalar that spells a sequence differs from the sequence.
    text = "'[''a'']': 1\n? [a]\n: 2\n"
    assert issue_codes(yaml_file(tmp_path, text, "e.yaml")) == ["E3006 "]
    # An empty sequence and an empty mapping are different keys.
    assert issue_codes(yaml_file(tmp_path, "? {}\n: 1\n? []\n: 2\n", "c.yaml")) == ["E3006 "]
    assert issue_codes(yaml_file(tmp_path, "? [a]\n: 1\n? {a: b}\n: 2\n", "d.yaml")) == ["E3006 "]


def test_deep_nesting_is_parsed_without_recursion_and_refused_in_conversion(tmp_path):
    pytest.importorskip("yaml")
    text = "a: " + "[" * 3000 + "]" * 3000 + "\n"
    issues = issue_codes(yaml_file(tmp_path, text))
    assert len(issues) == 1
    assert issues[0].startswith("E1030 /a/0/0/0/")


def test_scalars_stay_strings_except_where_the_schema_requires_another_type():
    value = convert(
        "vocabulary: 0.1.0\nextra: true\nunits: {focal: 'true'}\nfeatures: [1, yes]\n"
        "estimands: [{focal: 'false'}]\nprovenance: {outcome_seen: {a: b}}\n"
        "table: {fields: {categories: [1]}}\nvariables: {y: {bounds: ['0', 2.5e1], "
        "event_level: '7'}}\nempty: {}\nnothing: []\n"
    )
    assert value["extra"] == "true"
    assert value["units"] == {"focal": "true"}
    assert value["features"] == ["1", "yes"]
    assert value["estimands"] == [{"focal": False}]
    assert value["provenance"]["outcome_seen"] == {"a": "b"}
    assert value["table"]["fields"]["categories"] == ["1"]
    assert value["variables"]["y"]["bounds"] == [0, 25.0]
    assert [type(bound) for bound in value["variables"]["y"]["bounds"]] == [int, float]
    assert value["variables"]["y"]["event_level"] == 7
    assert value["empty"] == {}
    assert value["nothing"] == []


def test_a_category_or_an_event_level_takes_the_type_of_its_field():
    value = convert(
        "table:\n  fields:\n"
        "    - {name: y, type: string, categories: ['1', 2]}\n"
        "    - {name: y, type: integer, categories: ['3']}\n"
        "    - {name: z, type: [integer], categories: [4, a]}\n"
        "    - 5\n"
        "variables:\n  y: {event_level: '1'}\n  z: {event_level: '6'}\n  w: {event_level: x}\n"
    )
    assert value["table"]["fields"][0]["categories"] == ["1", "2"]
    assert value["table"]["fields"][1]["categories"] == [3]
    assert value["table"]["fields"][2]["categories"] == [4, "a"]
    assert value["table"]["fields"][3] == "5"
    assert value["variables"]["y"]["event_level"] == "1"
    assert value["variables"]["z"]["event_level"] == 6
    assert value["variables"]["w"]["event_level"] == "x"
    with pytest.raises(MixedcheckError) as caught:
        convert(
            "table:\n  fields:\n    - {name: y, type: integer}\n"
            "variables:\n  y: {event_level: '-0.0'}\n"
        )
    assert caught.value.issues == [
        {
            "code": "E3008",
            "message": "The value '-0.0' at /variables/y/event_level cannot be read as an integer.",
            "pointer": "/variables/y/event_level",
        }
    ]


def test_a_declaration_in_yaml_has_the_hash_of_its_json_form(tmp_path):
    pytest.importorskip("yaml")
    text = (
        "vocabulary: 0.1.0 # a comment\n"
        'title: "Caf\\u00e9 study"\n'
        "units:\n  - name: subject\n    columns: [Subject]\n    role: participant\n"
    )
    yaml_path = yaml_file(tmp_path, text, "declaration.yml")
    value = validate_declaration(yaml_path)
    json_path = tmp_path / "declaration.json"
    json_path.write_bytes(canonical_bytes(value, "hashable"))
    assert canonical_hash(validate_declaration(json_path), "hashable") == canonical_hash(
        value, "hashable"
    )
    assert value["title"] == "Caf\xe9 study"
