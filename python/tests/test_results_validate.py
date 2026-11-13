"""validate_results() in the parts that the results corpus cannot reach,
documents in memory, results objects, warnings, data frames and arguments,
the quantile rule, and the commitments that audit() and validation share
(documents.md, Validation, Internal sidecar, Outcome column commitment and
Analysis table commitment)."""

from __future__ import annotations

import copy
import math
import warnings
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY
from corpus_helpers import corpus_directory

from mixedcheck import (
    MixedcheckError,
    MixedcheckWarning,
    Results,
    audit,
    canonical_bytes,
    commitment_key_id,
    hash_bytes,
    hash_file,
    keyed_commitment,
    read_json_strict,
    read_table,
    validate_declaration,
    validate_results,
)
from mixedcheck._commitments import (
    analysis_table_message,
    apply_missing_values,
    data_commitments,
    observation_key_columns,
    outcome_column_keys,
    outcome_column_message,
    outcome_commitment,
    run_data,
)
from mixedcheck._errors import finish_issues
from mixedcheck._formula_ir import ModelTable, model_table
from mixedcheck._results_validate import quantile_shown
from mixedcheck._schema import Node, schema_bundle, schema_issues, simple_schema_valid


def corpus_file(name: str) -> str:
    return str(corpus_directory("results") / name)


def results_document(name: str) -> dict[str, Any]:
    document = read_json_strict(corpus_file(name), "data")
    assert isinstance(document, dict)
    return document


def example_sidecar() -> dict[str, Any]:
    return {
        "sidecar_version": "0.1.0",
        "keys": [
            {
                "created": "2026-11-08T09:05:30Z",
                "key": AUDIT_KEY,
                "key_id": commitment_key_id(AUDIT_KEY),
            }
        ],
        "pseudonyms": [],
    }


def issue_codes(f: Any) -> list[str]:
    """The code and pointer of each issue of the error that f raises."""
    try:
        f()
    except MixedcheckError as err:
        return [f"{issue['code']} {issue.get('pointer', '')}" for issue in err.issues]
    return []


def silent(f: Any) -> Any:
    """Call f and check that it neither raises nor warns."""
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return f()


# --- validate_results() ------------------------------------------------------------


def test_validate_results_reads_a_document_in_memory_and_a_results_object() -> None:
    path = corpus_file("valid/004.json")
    value = results_document("valid/004.json")
    # The document is indented, so the hash of its canonical bytes differs from
    # that of the file.
    canonical = hash_bytes(canonical_bytes(value, "data"))
    assert canonical != hash_file(path)
    sidecar = {**example_sidecar(), "results_hash": canonical}
    assert silent(lambda: validate_results(value, sidecar)) is value
    assert issue_codes(lambda: validate_results(path, sidecar)) == ["E1321 /results_hash"]
    # A file gives the value read from it, through a str or a path-like object.
    assert validate_results(Path(path)) == value

    # A results object is verified against its own sidecar, which holds no
    # results hash, unless a sidecar is given.
    results = Results(value, example_sidecar())
    assert silent(lambda: validate_results(results)) is value
    silent(lambda: validate_results(results, sidecar))
    assert "results_hash" not in results.sidecar
    results.sidecar["keys"] = []
    assert issue_codes(lambda: validate_results(results)) == ["E1313 "]
    key = example_sidecar()["keys"][0]
    results.sidecar["keys"] = [key, copy.deepcopy(key)]
    assert issue_codes(lambda: validate_results(results)) == ["E7061 /keys/1/key_id"]

    # A document in memory that cannot be written in the data profile, and a
    # sidecar in memory, whose issue comes from the writer too.
    broken = copy.deepcopy(value)
    broken["inputs"]["model"]["formula"] = "y\ud800 ~ x"
    assert issue_codes(lambda: validate_results(broken)) == ["E1206 /inputs/model/formula"]
    odd = {**sidecar, "keys": [{**example_sidecar()["keys"][0], "created": "\udc00"}]}
    assert issue_codes(lambda: validate_results(value, odd)) == ["E1206 /keys/0/created"]


def test_validate_results_accepts_a_suppressed_count_of_class_non_person() -> None:
    # The privacy filter suppresses a count of class non_person with the
    # detail 'secondary' when it measures a hidden quantity, as rule 6 of
    # privacy.md (Across findings) does for the counts of columns, and the
    # invariants of a shareable document never ask for such a count. They ask
    # only that a ratio of which it is the numerator or the denominator is
    # suppressed too (E7024).
    value = results_document("valid/001.json")
    assert value["privacy"]["mode"] == "shareable"
    finding = next(f for f in value["findings"] if f["check"] == "outcome.constant_clusters")
    statistic = finding["statistics"]["multi_row_levels"]
    assert statistic["count_class"] == "non_person"
    for name, detail in (("multi_row_levels", "secondary"), ("constant_share", "ratio")):
        finding["statistics"][name]["value"] = None
        finding["statistics"][name]["availability"] = {
            "value": "not_available",
            "reason": "privacy_suppressed",
            "detail": detail,
        }
    assert silent(lambda: validate_results(value)) is value
    finding["statistics"]["constant_share"]["value"] = 0.5
    del finding["statistics"]["constant_share"]["availability"]
    at = "/findings/" + str(value["findings"].index(finding)) + "/statistics/constant_share/value"
    assert issue_codes(lambda: validate_results(value)) == ["E7024 " + at]


def test_validate_results_warns_with_w7090_and_goes_on_to_the_sidecar() -> None:
    value = results_document("valid/001.json")
    value["inputs"]["registry_hash"] = "sha256:" + "0" * 64
    with pytest.warns(MixedcheckWarning) as caught:
        returned = validate_results(value)
    assert returned is value
    assert len(caught) == 1
    warning = caught[0].message
    assert isinstance(warning, MixedcheckWarning)
    assert [(i["code"], i["pointer"]) for i in warning.issues] == [
        ("W7090", "/inputs/registry_hash")
    ]
    assert str(warning) == warning.issues[0]["message"]
    # The sidecar is verified after the warning.
    results = Results(value, {**example_sidecar(), "keys": []})
    with pytest.warns(MixedcheckWarning):
        assert issue_codes(lambda: validate_results(results)) == ["E1313 "]


def test_validate_results_recomputes_commitments_from_a_data_frame() -> None:
    document = corpus_file("sidecar/frame.json")
    sidecar = corpus_file("sidecar/frame_sidecar.json")
    declaration = corpus_file("sidecar/declaration.json")
    frame = read_table(corpus_file("sidecar/reordered.csv"))
    silent(lambda: validate_results(document, sidecar, frame, declaration))
    frame.loc[0, "arm"] = "B" if frame.loc[0, "arm"] == "A" else "A"
    assert issue_codes(lambda: validate_results(document, sidecar, frame, declaration)) == [
        "E1314 /inputs/data/analysis_table"
    ]
    # A categorical column is read by its labels and an integer column as
    # numbers.
    frame = read_table(corpus_file("sidecar/data.csv"))
    frame["arm"] = pd.Categorical(frame["arm"], categories=["B", "A"])
    frame["wave"] = frame["wave"].astype("int64")
    silent(lambda: validate_results(document, sidecar, frame, declaration))
    # The declaration may be given as a value in memory.
    value = read_json_strict(declaration, "hashable")
    silent(lambda: validate_results(document, sidecar, frame, value))

    # A document that commits to a data file needs its path.
    file_document = corpus_file("sidecar/file.json")
    file_sidecar = corpus_file("sidecar/file_sidecar.json")
    with pytest.raises(ValueError, match="data file") as raised:
        validate_results(file_document, file_sidecar, frame, declaration)
    assert not isinstance(raised.value, MixedcheckError)
    silent(
        lambda: validate_results(
            file_document, file_sidecar, Path(corpus_file("sidecar/data.csv")), declaration
        )
    )


def test_validate_results_reports_the_errors_of_the_declaration_and_the_data() -> None:
    document = corpus_file("sidecar/frame.json")
    sidecar = corpus_file("sidecar/frame_sidecar.json")
    frame = read_table(corpus_file("sidecar/data.csv"))
    assert issue_codes(
        lambda: validate_results(document, sidecar, frame, {"vocabulary": "9.0.0"})
    ) == ["E1441 /vocabulary"]
    assert issue_codes(
        lambda: validate_results(document, sidecar, corpus_file("sidecar/missing.csv"))
    ) == ["E1001 "]


def test_validate_results_gives_ordinary_errors_for_its_arguments() -> None:
    document = corpus_file("sidecar/nokey.json")
    sidecar = corpus_file("sidecar/nokey_sidecar.json")
    data = corpus_file("sidecar/data.csv")
    # A list is a JSON array in memory, which is not a results document, where
    # R refuses a character vector of two paths as an argument.
    for f, error in (
        (lambda: validate_results(1), TypeError),
        (lambda: validate_results(None), TypeError),
        (lambda: validate_results(b"{}"), TypeError),
        (lambda: validate_results([document, document]), MixedcheckError),
        (lambda: validate_results(document, sidecar=1), TypeError),
        (lambda: validate_results(document, sidecar, data=1), TypeError),
        (lambda: validate_results(document, sidecar, data={"a": [1]}), TypeError),
        (lambda: validate_results(document, data=data), ValueError),
        (lambda: validate_results(document, declaration={"vocabulary": "0.1.0"}), ValueError),
    ):
        with pytest.raises(error) as raised:
            f()
        if error is not MixedcheckError:
            assert not isinstance(raised.value, MixedcheckError)


def test_documents_that_audit_returns_verify_against_their_data(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")
    data = pd.DataFrame(
        {
            "k": [1.0, 2, 0, 1, 3, 2],
            "n": [3.0, 3, 2, 4, 4, 5],
            "x": [1.0, 2, 3, 4, 5, 6],
            "s": ["a", "a", "b", "b", "c", "c"],
        }
    )
    results = audit(data, "x ~ 1 + (1 | s)", privacy="internal", key=AUDIT_KEY)
    silent(lambda: validate_results(results, data=data))
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
        "provenance": {"outcome_seen": True},
    }
    results = audit(
        data,
        "k ~ x + (1 | s)",
        declaration=declaration,
        outcome_access="T2",
        reason="Look.",
        exploratory=True,
        privacy="internal",
        key=AUDIT_KEY,
    )
    silent(lambda: validate_results(results, data=data, declaration=declaration))
    changed = data.copy()
    changed.loc[0, "n"] = 9.0
    assert issue_codes(
        lambda: validate_results(results, data=changed, declaration=declaration)
    ) == [
        "E1314 /access_log/entries/2/outcome/commitment",
        "E1314 /access_log/entries/4/outcome/commitment",
    ]
    # A run from a CSV file, and the document and sidecar it writes.
    path = tmp_path / "data.csv"
    path.write_bytes(b"y,x,g\n1.5,1,a\n2,2,a\n2.5,3,b\n,4,b\n")
    results = audit(str(path), "y ~ x + (1 | g)", privacy="internal", key=AUDIT_KEY)
    silent(lambda: validate_results(results, data=str(path)))
    with pytest.raises(ValueError, match="path of that file"):
        validate_results(results, data=read_table(path))
    from mixedcheck import write_results

    document = tmp_path / "audit.internal.json"
    sidecar = tmp_path / "audit.sidecar.internal.json"
    write_results(results, document, sidecar)
    value = silent(lambda: validate_results(document, sidecar, path))
    assert value == results.document


def test_the_structural_validator_decides_conditions_as_full_validation_does() -> None:
    # The validator keeps whether a value meets a condition by the identity of
    # the value, so that the quantile 1 + 2^-52, which serialises as 1 does,
    # is still above its maximum of 1 after a quantile of 1 was found valid.
    bundle = schema_bundle()
    node = Node({"$ref": "#/$defs/statistic"}, "urn:mixedcheck:schema:results")

    def statistic(p: float) -> dict[str, Any]:
        return {"kind": "real", "value": 0.5, "quantile": {"p": p}}

    pair = [statistic(1.0), statistic(1 + 2**-52)]
    issues = finish_issues(schema_issues(pair, Node({"items": node.schema}, node.base), bundle))
    assert [(issue["code"], issue["pointer"]) for issue in issues] == [("E1410", "/1/quantile/p")]
    # The conditions of the definition, decided without collecting issues,
    # agree with full validation.
    definition = bundle.resolve("#/$defs/statistic", "urn:mixedcheck:schema:results").schema
    conditions = [sub["if"] for sub in definition["allOf"] if "if" in sub]
    assert len(conditions) > 5
    values: list[Any] = [statistic(1.0), {"kind": "count", "value": 2}, {"value": 1}, "count"]
    values += [{"kind": 3}, {"kind": "labels", "value": None}, [], None]
    for value in values:
        for condition in conditions:
            simple = simple_schema_valid(value, condition)
            assert simple is not None
            full = not schema_issues(value, Node(condition, node.base), bundle)
            assert simple == full, (value, condition)
    assert simple_schema_valid(1, {"minimum": 0}) is None
    assert simple_schema_valid(1, {"not": {"$ref": "#/$defs/text"}}) is None


# --- The quantile rule -------------------------------------------------------------


def test_the_quantile_rule_is_exact_in_integer_arithmetic() -> None:
    assert quantile_shown(100, 0.9, 10)
    assert not quantile_shown(99, 0.9, 10)
    assert quantile_shown(40, 0.25, 10)
    assert not quantile_shown(19, 0.5, 10)
    assert quantile_shown(20, 0.5, 10)
    for p in (0, 1, 0.0, 1.0, "0", "1"):
        assert not quantile_shown(10**15, p, 1)
    assert quantile_shown(200, "0.05", 10)
    assert not quantile_shown(199, "0.05", 10)
    assert quantile_shown(200, "0.95", 10)
    assert not quantile_shown(199, 0.95, 10)
    # p = 1e-7: 10^8 values give 10, the minimum count.
    assert quantile_shown(10**8, 1e-7, 10)
    assert not quantile_shown(10**8 - 1, 1e-7, 10)
    assert quantile_shown(1e8, "0.0000001", 10)
    # The shortest decimal of the double nearest to 1/3 has 16 digits, so 30
    # values fall short of k = 10, although 30 / 3 is 10 in doubles.
    third = 1 / 3
    assert 30 * third == 10
    assert not quantile_shown(30, third, 10)
    assert quantile_shown(31, third, 10)
    # Counts beyond the doubles stay exact.
    assert quantile_shown(2 * 10**30 + 1, "0.5", 10**30)
    assert not quantile_shown(2 * 10**30 - 1, "0.5", 10**30)


# --- Commitments -------------------------------------------------------------------


def frame_of(columns: dict[str, list[Any]]) -> pd.DataFrame:
    """A DataFrame whose columns have dtype object, so that None stays a
    missing value."""
    return pd.DataFrame({name: pd.Series(values, dtype=object) for name, values in columns.items()})


def test_the_analysis_table_and_outcome_column_commitments_match_documents_md() -> None:
    declaration: dict[str, Any] = {
        "observation": {"key": ["pupil", "wave"]},
        "variables": {"post": {"role": "outcome"}},
    }
    table = model_table(
        frame_of(
            {
                "pupil": ["p2", "p1", "p2", "p1"],
                "wave": [1.0, 0.0, 0.0, 1.0],
                "arm": ["B", "A", "B", "A"],
                "post": [9.0, 12.0, None, 15.0],
            }
        ),
        [],
    )
    outcome = outcome_column_message(table, declaration, "post")
    assert outcome == (
        b'{"column":"post","key":["pupil","wave"],"rows":'
        b'[["p1",0,12],["p1",1,15],["p2",0,null],["p2",1,9]]}'
    )
    assert keyed_commitment(outcome, AUDIT_KEY, "outcome_column")["digest"] == (
        "75cc1f029d23f7ee37f8b3e0f1dc93e2d78b113b88d69f62a617346a6edafe7f"
    )
    analysis = analysis_table_message(table, declaration, "post")
    assert analysis is not None and len(analysis) == 118
    assert keyed_commitment(analysis, AUDIT_KEY, "analysis_table")["digest"] == (
        "72de9a1b287c8601cdbab959ce1192af4fe02a10030e6bc721928ba52d8b0391"
    )
    # A key that /provenance/inferred points to counts as absent, so the rows
    # keep the order of the table.
    for pointer in ("/observation", "/observation/key", "/observation/key/1"):
        inferred = {**declaration, "provenance": {"inferred": [pointer]}}
        assert observation_key_columns(inferred) == []
        message = analysis_table_message(table, inferred, "post")
        assert message is not None and b'"key":[],"rows":[["p2",1,"B"],' in message
    other = {**declaration, "provenance": {"inferred": ["/observation/time"]}}
    assert observation_key_columns(other) == ["pupil", "wave"]
    # A column that the table lacks gives no message.
    assert outcome_column_message(table, declaration, "score") is None
    assert analysis_table_message(table, {"observation": {"key": ["id"]}}, None) is None


def test_the_analysis_table_leaves_out_the_response_its_trials_and_declared_outcomes() -> None:
    declaration = {
        "variables": {
            "hits": {"role": "outcome", "measurement": "binomial", "trials": "n"},
            "rt": {"role": "outcome_derived"},
            "age": {"role": "covariate"},
        }
    }
    assert set(outcome_column_keys(declaration, "hits")) == {"hits", "rt", "n"}
    assert set(outcome_column_keys(declaration, None)) == {"hits", "rt"}
    assert set(outcome_column_keys(None, "y")) == {"y"}
    frame = pd.DataFrame(
        {
            "id": [1, 2],
            "hits": [3.0, 4.0],
            "n": [5.0, 5.0],
            "rt": [1.5, 2.0],
            "age": [30.0, 40.0],
            "y": [True, False],
        }
    )
    message = analysis_table_message(model_table(frame, []), declaration, "hits")
    assert message == b'{"columns":["id","age","y"],"key":[],"rows":[[1,30,true],[2,40,false]]}'
    # The response is compared with the columns after NFC.
    frame = pd.DataFrame({"cafe\u0301": [1.0], "x": [2.0]})
    message = analysis_table_message(model_table(frame, []), None, "caf\u00e9")
    assert message == b'{"columns":["x"],"key":[],"rows":[[2]]}'


def test_commitment_messages_write_values_as_the_data_profile_and_order_rows_by_key_bytes() -> None:
    e_acute = "\u00e9"
    columns: dict[str, list[Any]] = {
        "g": ["z", e_acute, "a", "z", None],
        "k": [2.0, 1.0, math.nan, -0.0, math.inf],
        "v": [-math.inf, 1e21, 0.1, None, 1.5],
        "b": [True, None, False, True, False],
        "s": ['q"uote', "tab\t", None, "back\\slash", ""],
    }
    table = model_table(frame_of(columns), [])
    declaration = {"observation": {"key": ["g", "k"]}}
    message = analysis_table_message(table, declaration, None)
    # The rows ordered by the canonical bytes of their key values, which put
    # '"a"', then '"z"', then the two bytes of e acute and then null, and ties
    # broken by the whole row.
    rows = [[columns[name][i] for name in columns] for i in range(5)]
    ordered = sorted(rows, key=lambda row: (canonical_bytes(row[:2]), canonical_bytes(row)))
    expected = canonical_bytes({"columns": list(columns), "key": ["g", "k"], "rows": ordered})
    assert message == expected
    assert [row[0] or "NULL" for row in ordered] == ["a", "z", "z", e_acute, "NULL"]
    # Rows without a key keep the order of the table, and a table without rows
    # has none.
    message = analysis_table_message(table, None, None)
    assert message is not None and b'"rows":[["z",2,"-Infinity",true,' in message
    empty = model_table(frame_of(columns).iloc[0:0], [])
    assert (
        outcome_column_message(empty, declaration, "v")
        == b'{"column":"v","key":["g","k"],"rows":[]}'
    )


def table_column(table: ModelTable, name: str) -> list[Any]:
    """The values of a column of a table, with None for a missing value."""
    j = table.names.index(name)
    return [
        None if missing else value
        for value, missing in zip(table.values[j].tolist(), table.missing[j].tolist(), strict=True)
    ]


def test_the_declared_missing_values_apply_to_a_data_frame_as_the_reader_applies_them() -> None:
    table_block: dict[str, Any] = {
        "fields": [
            {"name": "pupil", "type": "string", "missingValues": ["NA", ""]},
            {"name": "score", "type": "number", "missingValues": [{"value": "-99"}, "nan", "0"]},
            {"name": "flag", "type": "boolean"},
        ],
        "missingValues": ["1.0", "x"],
    }
    frame = pd.DataFrame(
        {
            "pupil": ["p1", "NA", "", "x"],
            "score": [-99.0, math.nan, -0.0, 99.0],
            "flag": pd.Series([True, False, None, True], dtype=object),
            "other": [1.0, 2.0, 1.0, 3.0],
            "note": pd.Categorical(["x", "y", "x", "z"]),
        }
    )
    table = model_table(frame, [])
    apply_missing_values(table, table_block)
    assert table_column(table, "pupil") == ["p1", None, None, "x"]
    assert table_column(table, "score") == [None, None, None, 99.0]
    assert table_column(table, "flag") == [True, False, None, True]
    assert table_column(table, "other") == [None, 2.0, None, 3.0]
    assert table_column(table, "note") == [None, "y", None, "z"]
    # Strings are compared after NFC, and an empty list declares that no value
    # is missing.
    composed = {"fields": [{"name": "pupil", "missingValues": ["n\u00e1"]}]}
    table = model_table(pd.DataFrame({"pupil": ["na\u0301", "b"]}), [])
    apply_missing_values(table, composed)
    assert table_column(table, "pupil") == [None, "b"]
    none: dict[str, Any] = {"fields": [{"name": "pupil", "missingValues": []}]}
    table = model_table(pd.DataFrame({"pupil": ["", "b"]}), [])
    apply_missing_values(table, none)
    assert table_column(table, "pupil") == ["", "b"]
    # Without a table block nothing is applied, and the default '' applies to
    # a column without a field.
    run = run_data(pd.DataFrame({"a": ["", "b"]}), None)
    assert table_column(run.table, "a") == ["", "b"]
    run = run_data(pd.DataFrame({"a": ["", "b"]}), {"table": {"fields": []}})
    assert table_column(run.table, "a") == [None, "b"]

    # A data frame and the file it was read from give the same table.
    path = corpus_file("sidecar/sentinel.csv")
    declaration = validate_declaration(corpus_file("sidecar/declaration_table.json"))
    frame = read_table(path)
    assert frame["post"][2] == -99
    from_file = run_data(path, declaration)
    from_frame = run_data(frame, declaration)
    assert from_frame.table.names == from_file.table.names
    assert from_frame.table.types == from_file.table.types
    for j in range(len(from_file.table.names)):
        assert np.array_equal(from_frame.table.missing[j], from_file.table.missing[j])
        name = from_file.table.names[j]
        assert table_column(from_frame.table, name) == table_column(from_file.table, name)
    assert from_file.file == Path(path).read_bytes()
    assert from_frame.file is None


def test_the_commitments_of_a_run_verify_against_its_document() -> None:
    document = results_document("sidecar/file.json")
    declaration = validate_declaration(corpus_file("sidecar/declaration.json"))
    run = run_data(corpus_file("sidecar/data.csv"), declaration)
    members = ("analysis_table", "data_file")
    commitments = data_commitments(run, declaration, "post", AUDIT_KEY)
    assert {name: commitments[name] for name in members} == {
        name: document["inputs"]["data"][name] for name in members
    }
    assert (
        outcome_commitment(run, declaration, "post", AUDIT_KEY)
        == document["access_log"]["entries"][1]["outcome"]["commitment"]
    )
    frame = run_data(read_table(corpus_file("sidecar/data.csv")), declaration)
    assert list(data_commitments(frame, declaration, "post", AUDIT_KEY)) == ["analysis_table"]
