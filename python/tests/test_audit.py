"""audit() and the machinery of the checks, in the parts that the audit corpus
cannot reach: the arguments, columns of other types, times, keys, the access
log and inputs, printing, and the machinery's rules for thresholds,
availability, scopes, count classes, support, order and the helpers that the
checks share."""

from __future__ import annotations

import copy
import math
import random
import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY, AUDIT_KEY_ID

import mixedcheck
from mixedcheck import (
    MixedcheckError,
    Results,
    audit,
    canonical_bytes,
    commitment_key_id,
    keyed_commitment,
    new_commitment_key,
    read_json_strict,
    validate_declaration,
)
from mixedcheck import _checks as machinery
from mixedcheck._commitments import outcome_commitment, run_data
from mixedcheck._design import design_build, design_model, sequential_rule
from mixedcheck._errors import finish_issues
from mixedcheck._formula_ir import build_formula_ir, coding_input
from mixedcheck._registry import registry_entries_by_id, registry_entry, registry_hash
from mixedcheck._schema import schema_issues
from mixedcheck._times import utc_timestamp


def audit_data() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "y": [2.1, 3.4, 1.8, 2.9, 3.3, 4.1, 2.6, 3.7],
            "x": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "subject": ["s1", "s1", "s2", "s2", "s3", "s3", "s4", "s4"],
            "trial": [1.0, 2, 1, 2, 1, 2, 1, 2],
        }
    )


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0 unless a test sets another."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def audit_at_zero(
    data: Any = None,
    formula: str = "y ~ x + (1 | subject)",
    privacy: str = "internal",
    key: str | None = AUDIT_KEY,
    **arguments: Any,
) -> Results:
    """audit() in internal mode with the example key."""
    return audit(
        audit_data() if data is None else data,
        formula,
        privacy=privacy,
        key=key,
        **arguments,
    )


def audit_issue(**arguments: Any) -> dict[str, Any] | None:
    try:
        audit_at_zero(**arguments)
    except MixedcheckError as err:
        return err.issues[0]  # type: ignore[no-any-return]
    return None


def audit_error(**arguments: Any) -> str | None:
    """The message of an ordinary error, or None."""
    try:
        audit_at_zero(**arguments)
    except MixedcheckError:
        return None
    except (TypeError, ValueError) as err:
        return str(err)
    return None


def test_a_run_returns_a_results_object_with_every_member_of_the_document() -> None:
    results = audit_at_zero()
    assert isinstance(results, Results)
    document = results.document
    assert document["results_version"] == "0.1.0"
    assert document["created"] == "1970-01-01T00:00:00Z"
    assert document["stream"] == "B"
    assert document["software"]["language"] == "Python"
    assert document["software"]["unicode"]["library"] == "unicodedata"
    assert document["versions"]["package"] == mixedcheck.__version__
    assert document["privacy"]["mode"] == "internal"
    assert document["privacy"]["min_count"] == 10
    assert "disclosure_unit" not in document["privacy"]
    assert document["inputs"]["registry_hash"] == registry_hash()
    assert "declaration" not in document["inputs"]
    assert document["inputs"]["model"]["formula"] == "y ~ x + (1 | subject)"
    assert document["inputs"]["model"]["family_class"] == "gaussian"
    assert list(document["inputs"]["data"]) == ["analysis_table"]
    assert document["access_log"] == {
        "entries": [{"mode": "outcome_blind", "tier": "T0", "time": "1970-01-01T00:00:00Z"}]
    }
    assert results.sidecar == {
        "sidecar_version": "0.1.0",
        "keys": [{"created": "1970-01-01T00:00:00Z", "key": AUDIT_KEY, "key_id": AUDIT_KEY_ID}],
        "pseudonyms": [],
    }
    # The document holds the values that the strict reader returns, and it
    # meets the results schema.
    assert read_json_strict(canonical_bytes(document, "data"), "data") == document
    assert finish_issues(schema_issues(document, "urn:mixedcheck:schema:results")) == []


def test_shareable_mode_waits_for_the_privacy_filter() -> None:
    with pytest.raises(RuntimeError, match="Internal error: shareable mode arrives with"):
        audit_at_zero(privacy="shareable")
    with pytest.raises(RuntimeError, match="privacy filter"):
        audit(audit_data(), "y ~ x + (1 | subject)", key=AUDIT_KEY)


def test_the_arguments_are_checked_in_step_1_with_their_codes() -> None:
    issue = audit_issue(family="Gaussian")
    assert issue is not None
    assert issue["message"] == (
        "The family 'Gaussian' is not one of 'gaussian', 'binomial', 'poisson', "
        "'negative_binomial', 'beta', 'gamma', 'inverse_gaussian' or 'cumulative'."
    )
    issue = audit_issue(outcome_access="T1")
    assert issue is not None
    assert issue["message"] == (
        "Outcome access at T1 needs a reason of 1 to 4000 characters without control characters."
    )
    for reason in ("", "a\tb", "x" * 4001, "a\x7fb"):
        issue = audit_issue(outcome_access="T1", reason=reason)
        assert issue is not None and issue["code"] == "E7009", reason
    assert audit_issue(outcome_access="T1", reason="x" * 4000) is None
    issue = audit_issue(outcome_access="T2", reason="Look.")
    assert issue is not None
    assert issue["message"] == "Outcome access at T2 needs the exploratory mode."
    # The reason comes before the exploratory mode.
    issue = audit_issue(outcome_access="T2")
    assert issue is not None and "a reason of 1 to 4000" in issue["message"]
    issue = audit_issue(formula="~ x + (1 | subject)", outcome_access="T1", reason="Look.")
    assert issue is not None
    assert issue["message"] == "Outcome access at T1 needs a formula with a response."
    for key in ("00", AUDIT_KEY.upper()):
        issue = audit_issue(key=key)
        assert issue is not None and issue["code"] == "E1311"
    # E7008 comes before E7009 and the key.
    issue = audit_issue(family="x", outcome_access="T1", key="00")
    assert issue is not None and issue["code"] == "E7008"
    # A surrogate code point gives E1206 at the pointer of the argument.
    issue = audit_issue(formula="y ~ x\ud800")
    assert issue == {
        "code": "E1206",
        "message": "The string at /formula contains a surrogate code point.",
        "pointer": "/formula",
    }


def test_arguments_of_the_wrong_type_give_ordinary_errors() -> None:
    cases: list[tuple[dict[str, Any], str]] = [
        ({"data": {"y": [1]}}, "'data' must be"),
        ({"formula": 1}, "'formula' must be"),
        ({"family": 1}, "'family' must be"),
        ({"coding": [1]}, "'coding' must be"),
        ({"weights": ["a", "b"]}, "'weights' must be"),
        ({"sample_columns": "x"}, "'sample_columns' must be"),
        ({"outcome_access": "t1"}, "'outcome_access' must be"),
        ({"reason": 1, "outcome_access": "T1"}, "'reason' must be"),
        ({"reason": "Look."}, "'reason' is given only for outcome access"),
        ({"exploratory": None}, "'exploratory' must be"),
        ({"outcome_seen": "yes"}, "'outcome_seen' must be"),
        ({"privacy": "Internal"}, "'privacy' must be"),
        ({"key": 1}, "'key' must be"),
    ]
    for arguments, message in cases:
        error = audit_error(**arguments)
        assert error is not None and message in error, arguments


def test_columns_of_other_types_give_an_ordinary_error() -> None:
    columns = {
        "date": pd.to_datetime(["2026-01-01"] * 8),
        "duration": pd.to_timedelta([1] * 8, unit="s"),
        "complex": np.array([1 + 1j] * 8),
        "list": pd.Series([[1]] * 8, dtype=object),
    }
    for name, column in columns.items():
        data = audit_data()
        data[name] = column
        error = audit_error(data=data)
        assert error is not None and f"The column '{name}' of 'data'" in error, name
    # Integer, categorical, boolean and nullable columns are read as numbers,
    # labels and booleans.
    data = audit_data()
    data["trial"] = data["trial"].astype("int64")
    data["subject"] = data["subject"].astype("category")
    data["flag"] = [True, False] * 4
    data["y"] = data["y"].astype("Float64")
    assert isinstance(audit_at_zero(data=data), Results)


def sample_finding(results: Results) -> dict[str, Any]:
    found = [f for f in results.document["findings"] if f["check"] == "sample.raw_vs_analysis"]
    assert len(found) == 1
    return found[0]


def test_the_declarations_missing_values_apply_to_a_data_frame() -> None:
    data = audit_data()
    data.loc[2, "x"] = -99
    data.loc[5, "subject"] = "NA"
    declaration = {
        "vocabulary": "0.1.0",
        "table": {
            "missingValues": ["", "-99", "NA"],
            "fields": [
                {"name": "y", "type": "number"},
                {"name": "x", "type": "number"},
                {"name": "subject", "type": "string"},
                {"name": "trial", "type": "integer"},
            ],
        },
    }
    finding = sample_finding(audit_at_zero(data=data, declaration=declaration))
    assert finding["statistics"]["rows_kept"]["value"] == 6
    assert finding["statistics"]["incomplete_columns"]["value"] == ["subject", "x"]
    # A column whose values all become missing takes the type of its field.
    data = audit_data()
    data["code"] = ["NA"] * 8
    declaration["table"]["fields"].append({"name": "code", "type": "number"})
    assert isinstance(audit_at_zero(data=data, declaration=declaration), Results)
    # A field of another type is refused otherwise.
    data["code"] = ["a"] * 8
    error = audit_error(data=data, declaration=declaration)
    assert error is not None and "declares the type 'number'" in error


def test_mixedcheck_time_sets_every_time_of_a_run(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "1767225600")
    results = audit_at_zero(outcome_access="T1", reason="Look.")
    document = results.document
    assert document["created"] == "2026-01-01T00:00:00Z"
    assert [e["time"] for e in document["access_log"]["entries"]] == ["2026-01-01T00:00:00Z"] * 2
    assert results.sidecar["keys"][0]["created"] == "2026-01-01T00:00:00Z"
    assert new_commitment_key()["created"] == "2026-01-01T00:00:00Z"
    # Only the ASCII digits 0 to 9 are digits, whatever int() reads.
    for value in (
        "-1",
        "1.5",
        "1e9",
        " 1",
        "1 ",
        "+1",
        "1_0",
        "1\n",
        "253402300800",
        "abc",
        "٣",
        "1٣",
        "²",
        "１",
    ):
        monkeypatch.setenv("MIXEDCHECK_TIME", value)
        error = audit_error()
        assert error is not None and "MIXEDCHECK_TIME must be a whole number" in error, value
        with pytest.raises(ValueError, match="MIXEDCHECK_TIME"):
            new_commitment_key()
    monkeypatch.setenv("MIXEDCHECK_TIME", "0000253402300799")
    assert audit_at_zero().document["created"] == "9999-12-31T23:59:59Z"
    # An empty value counts as unset, as on Windows.
    monkeypatch.setenv("MIXEDCHECK_TIME", "")
    created = audit_at_zero().document["created"]
    assert re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", created)
    assert created != "1970-01-01T00:00:00Z"
    assert [utc_timestamp(s) for s in (951782400, 951868800, 4107542400, 86399)] == [
        "2000-02-29T00:00:00Z",
        "2000-03-01T00:00:00Z",
        "2100-03-01T00:00:00Z",
        "1970-01-01T23:59:59Z",
    ]


def test_a_run_without_a_key_creates_one_from_a_secure_source() -> None:
    results = audit_at_zero(key=None)
    key = results.sidecar["keys"][0]
    assert re.fullmatch(r"[0-9a-f]{64}", key["key"])
    assert key["key_id"] == commitment_key_id(key["key"])
    assert results.document["inputs"]["data"]["analysis_table"]["key_id"] == key["key_id"]
    assert audit_at_zero(key=None).sidecar["keys"][0]["key"] != key["key"]


def test_without_a_secure_source_a_key_must_be_supplied(monkeypatch: pytest.MonkeyPatch) -> None:
    def unavailable(count: int) -> bytes:
        raise NotImplementedError("no source")

    monkeypatch.setattr("secrets.token_bytes", unavailable)
    issue = audit_issue(key=None)
    assert issue is not None and issue["code"] == "E1312"
    with pytest.raises(MixedcheckError) as caught:
        new_commitment_key()
    assert caught.value.issues[0]["code"] == "E1312"
    # A supplied key needs no source.
    assert isinstance(audit_at_zero(), Results)


def test_a_run_leaves_the_random_generators_alone() -> None:
    random.seed(3)
    state = random.getstate()
    numpy_state = np.random.get_state()
    audit_at_zero(key=None)
    assert random.getstate() == state
    after = np.random.get_state()
    assert after[0] == numpy_state[0] and bool((after[1] == numpy_state[1]).all())


def test_the_access_log_records_each_outcome_column_read_at_each_tier() -> None:
    data = pd.DataFrame(
        {
            "k": [1.0, 2, 0, 1, 3, 2],
            "n": [3.0, 3, 2, 4, 4, 5],
            "x": [1.0, 2, 3, 4, 5, 6],
            "s": ["a", "a", "b", "b", "c", "c"],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
        "provenance": {"outcome_seen": True},
    }
    results = audit_at_zero(
        data=data,
        formula="k ~ x + (1 | s)",
        declaration=declaration,
        outcome_access="T2",
        reason="Look.",
        exploratory=True,
    )
    log = results.document["access_log"]
    assert log["outcome_seen"] is True
    entries = log["entries"]
    assert [(e["tier"], e.get("outcome", {}).get("column", "")) for e in entries] == [
        ("T0", ""),
        ("T1", "k"),
        ("T1", "n"),
        ("T2", "k"),
        ("T2", "n"),
    ]
    assert {e["mode"] for e in entries[1:]} == {"exploratory"}
    assert {e["reason"] for e in entries[1:]} == {"Look."}
    valid = validate_declaration(declaration)
    assert entries[1]["outcome"]["commitment"] == outcome_commitment(
        run_data(data, valid), valid, "k", AUDIT_KEY
    )
    inputs = results.document["inputs"]
    assert inputs["model"]["family_class"] == "binomial"
    assert inputs["declaration"]["minimal"] is False
    assert inputs["declaration"]["draft"] is False
    # The attestation agrees with the declaration or is refused.
    error = audit_error(data=data, formula="k ~ x", declaration=declaration, outcome_seen=False)
    assert error is not None and "'outcome_seen' differs" in error
    assert audit_at_zero(outcome_seen=False).document["access_log"]["outcome_seen"] is False


def test_a_check_that_reads_the_outcome_must_be_logged() -> None:
    data = audit_data()
    model_run = machinery_run(data, "y ~ x + (1 | subject)")
    entry = registry_entry("outcome.boundary_shares")
    # At T0, the run has no analysis sample.
    with pytest.raises(RuntimeError, match="did not reach"):
        machinery.outcome_values(model_run, entry)
    model_run.tier = "T1"
    model_run.analysis = model_run.design
    found = machinery.outcome_values(model_run, entry)
    assert found.type == "number" and len(found.rows) == 8
    with pytest.raises(RuntimeError, match="does not record"):
        machinery.outcome_reads_logged(model_run, [{"tier": "T0"}])
    machinery.outcome_reads_logged(model_run, [{"tier": "T1", "outcome": {"column": "y"}}])


def test_a_run_from_a_csv_file_commits_to_the_files_bytes(tmp_path: Path) -> None:
    path = tmp_path / "data.csv"
    path.write_bytes(b"y,x,g\n1.5,1,a\n2,2,a\n2.5,3,b\n,4,b\n")
    results = audit_at_zero(data=str(path), formula="y ~ x + (1 | g)")
    data = results.document["inputs"]["data"]
    assert data["data_file"] == keyed_commitment(path.read_bytes(), AUDIT_KEY, "data_file")
    assert audit_at_zero(data=path, formula="y ~ x + (1 | g)").document == results.document
    issue = audit_issue(data=str(tmp_path / "missing.csv"), formula="y ~ x")
    assert issue is not None and issue["code"] == "E1001"


def test_e5011_takes_the_places_of_e2007_and_e6069_the_columns_that_read_the_outcome() -> None:
    declaration: dict[str, Any] = {
        "vocabulary": "0.1.0",
        "units": [{"name": "subject", "columns": ["subject"]}],
        "observation": {"key": ["subject", "wave"]},
        "variables": {"zzz": {"role": "auxiliary"}, "aaa": {"role": "time"}},
    }
    issue = audit_issue(declaration=declaration)
    assert issue is not None and issue["pointer"] == "/observation/key/1"
    del declaration["observation"]
    issue = audit_issue(declaration=declaration)
    assert issue is not None and issue["pointer"] == "/variables/aaa"
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"x": {"role": "outcome_derived"}, "y": {"role": "outcome"}},
    }
    issue = audit_issue(declaration=declaration)
    assert issue is not None and issue["message"] == (
        "The column 'x' is an outcome, is derived from one or holds the trials of the response, "
        "so the outcome-blind checks cannot read it."
    )
    del declaration["variables"]["x"]
    data = audit_data()
    data["w"] = 1.0
    declaration["variables"]["w"] = {"role": "outcome_derived"}
    for arguments in ({"weights": "w"}, {"formula": "y ~ x + offset(w)"}):
        issue = audit_issue(data=data, declaration=declaration, **arguments)
        assert issue is not None and "'w'" in issue["message"], arguments
    # The response is an outcome whatever the declaration says.
    data = audit_data()
    data["z"] = data["y"]
    issue = audit_issue(data=data, weights="y")
    assert issue is not None and "'y'" in issue["message"]
    key_declaration = {"vocabulary": "0.1.0", "observation": {"key": ["trial", "y"]}}
    issue = audit_issue(data=data, declaration=key_declaration)
    assert issue is not None and "'y'" in issue["message"]
    unit_declaration = {
        "vocabulary": "0.1.0",
        "units": [{"name": "p", "columns": ["y"], "role": "participant"}],
    }
    issue = audit_issue(data=data, formula="y ~ x", declaration=unit_declaration)
    assert issue is not None and "'y'" in issue["message"]
    derived = {
        "vocabulary": "0.1.0",
        "variables": {
            "y": {"role": "outcome"},
            "z": {"role": "outcome_derived", "derived_from": ["y"]},
        },
    }
    issue = audit_issue(data=data, declaration=derived, sample_columns=["z"])
    assert issue is not None and "'z'" in issue["message"]
    assert audit_issue(data=data, sample_columns=["y"]) is None
    assigned = {
        "vocabulary": "0.1.0",
        "units": [{"name": "subject", "columns": ["subject"]}],
        "assignment": [{"column": "y", "unit": "subject", "randomised": True}],
    }
    issue = audit_issue(data=data, declaration=assigned)
    assert issue is not None and "'y'" in issue["message"]


def test_the_family_class_follows_the_family_or_the_declared_measurement() -> None:
    data = pd.DataFrame({"k": [1.0, 0, 1, 1], "n": [2.0, 2, 2, 2], "x": [1.0, 2, 3, 4]})

    def class_of(**arguments: Any) -> str:
        results = audit_at_zero(data=data, formula="k ~ x", **arguments)
        return results.document["inputs"]["model"]["family_class"]  # type: ignore[no-any-return]

    assert class_of() == "gaussian"
    assert class_of(family="binomial") == "bernoulli"
    assert class_of(family="negative_binomial") == "poisson"
    assert class_of(family="cumulative") == "other"

    def measured(measurement: str) -> str:
        variable: dict[str, Any] = {"role": "outcome", "measurement": measurement}
        if measurement == "binomial":
            variable["trials"] = "n"
        return class_of(declaration={"vocabulary": "0.1.0", "variables": {"k": variable}})

    found = {
        m: measured(m)
        for m in ("binary", "binomial", "count", "ordinal", "continuous", "positive_duration")
    }
    assert found == {
        "binary": "bernoulli",
        "binomial": "binomial",
        "count": "poisson",
        "ordinal": "other",
        "continuous": "gaussian",
        "positive_duration": "gaussian",
    }
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "count"}},
        "provenance": {"inferred": ["/variables/k/measurement"]},
    }
    assert class_of(declaration=declaration) == "gaussian"


def test_printing_an_audit_shows_its_banner_and_findings() -> None:
    lines = str(audit_at_zero()).split("\n")
    assert lines[0] == (
        "INTERNAL: this report holds values that the privacy filter has not checked, "
        "such as small counts and labels. Do not share it."
    )
    assert "keys.duplicates: not available (declaration_missing: /observation/key)." in lines
    assert repr(audit_at_zero()) == "\n".join(lines)


def test_documents_do_not_depend_on_the_representation_of_the_data() -> None:
    data = audit_data()
    expected = canonical_bytes(audit_at_zero(data=data).document)
    variants = [
        data.astype(object),
        data.astype({"subject": "category", "trial": "int64"}),
        data.astype({"subject": "string", "y": "Float64"}),
    ]
    for variant in variants:
        assert canonical_bytes(audit_at_zero(data=variant).document) == expected


# --- The machinery ------------------------------------------------------------------


def test_thresholds_compare_counts_ratios_and_reals_exactly_with_proximity_bands() -> None:
    entry = registry_entry("outcome.boundary_shares")

    def shares(at: int, rows: int) -> dict[str, Any]:
        return {"at_ceiling": at, "rows": rows, "ceiling_share": at / rows}

    # 0.15 of 20 is 3: the comparison is exact, so 3 of 20 is not above it.
    assert not machinery.threshold_holds(entry, "ceiling", shares(3, 20))
    assert machinery.threshold_holds(entry, "ceiling", shares(31, 200))
    assert not machinery.threshold_holds(entry, "ceiling", {"rows": 20})
    entry = registry_entry("design.collinearity")
    assert machinery.threshold_holds(entry, "high", {"gvif_per_df": 10.0})
    assert not machinery.threshold_holds(entry, "high", {"gvif_per_df": 9.999})
    assert not machinery.threshold_holds(entry, "high", {"gvif_per_df": math.nan})
    element = machinery.check_element({})
    near = machinery.finding_near_threshold
    assert near(entry, {"gvif_per_df": 10 + 5e-9}, element)
    assert not near(entry, {"gvif_per_df": 10 + 2e-8}, element)
    assert not near(entry, {"gvif_per_df": math.nan}, element)
    assert not near(entry, {}, element)
    entry = registry_entry("identifiability.gram_rank")

    def compared(values: Any) -> bool:
        return near(entry, {}, machinery.check_element({}, proximity={"rank_tolerance": values}))

    assert compared([1.0, 5e-10])
    assert compared([-2e-11])
    assert not compared([1.0, 2e-9, 9e-12])
    # A value within its bound of the tolerance.
    assert compared(machinery.compared_values([2e-9], [2e-9]))
    assert not compared(machinery.compared_values([2e-9], [1e-9]))
    assert near(entry, {}, machinery.check_element({}, near_threshold=True))
    assert machinery.finding_validation(registry_entry("design.collinearity")) == "descriptive"
    assert machinery.finding_validation(registry_entry("keys.duplicates")) == "descriptive"


def test_package_missing_makes_a_check_not_available_before_it_runs() -> None:
    run = machinery_run(audit_data(), "y ~ x")
    entry = copy.deepcopy(registry_entry("keys.duplicates"))
    entry["availability"].insert(
        0,
        {
            "reason": "package_missing",
            "condition": "No package.",
            "packages": {"Python": ["mixedcheck_no_such_package"]},
        },
    )
    found = machinery.run_check(run, entry)
    assert [machinery.document_finding(f) for f in found] == [
        {
            "check": "keys.duplicates",
            "check_version": 1,
            "tier": "T0",
            "scope": {},
            "status": {
                "availability": {
                    "value": "not_available",
                    "reason": "package_missing",
                    "detail": "mixedcheck_no_such_package",
                }
            },
        }
    ]
    # A family filter that excludes the class yields no finding at all.
    entry["families"] = ["poisson"]
    assert machinery.run_check(run, entry) == []


def test_every_check_of_the_registry_has_its_function() -> None:
    ids = list(registry_entries_by_id())
    assert len(ids) == 24
    assert [id for id in ids if machinery.check_implementation(id) is None] == []


def test_an_entry_without_a_function_is_an_internal_error() -> None:
    run = machinery_run(audit_data(), "y ~ x")
    entry = copy.deepcopy(registry_entry("keys.duplicates"))
    entry["id"] = "keys.no_such_check"
    with pytest.raises(RuntimeError, match="has no function"):
        machinery.run_check(run, entry)
    assert machinery.check_implementation("nosuchprefix.check") is None
    assert machinery.check_function_name("sample.raw_vs_analysis") == (
        "mixedcheck._checks_sample",
        "check_sample_raw_vs_analysis",
    )


def test_every_entry_checks_its_package_missing_rules_first() -> None:
    for entry in registry_entries_by_id().values():
        reasons = [rule["reason"] for rule in entry["availability"]]
        first_other = next(
            (i for i, r in enumerate(reasons) if r != "package_missing"), len(reasons)
        )
        assert "package_missing" not in reasons[first_other:], entry["id"]


def test_checks_run_in_order_of_identifier_after_the_checks_they_require() -> None:
    entries = registry_entries_by_id()
    order = machinery.check_order(entries, "T2")
    assert len(order) == len(entries)
    for id in order:
        for required in entries[id]["links"]["requires"]:
            assert order.index(required) < order.index(id)
    t0 = machinery.check_order(entries, "T0")
    assert {entries[id]["tier"] for id in t0} == {"T0"}
    assert t0[:2] == ["assignment.constant_within_unit", "assignment.design_df"]


def machinery_run(data: pd.DataFrame, formula: str, declaration: Any = None) -> machinery.Run:
    """A run of audit() as the checks see it, for the tests of the machinery."""
    if declaration is not None:
        declaration = validate_declaration(declaration)
    table = run_data(data, declaration).table
    ir = build_formula_ir(formula, declaration, table, coding_input(None), None, [])
    model = design_model(ir, table, analysis=False)
    built = design_build(ir, model, table)
    return machinery.new_run(declaration, table, ir, "gaussian", "T0", model, built)


def test_scope_elements_follow_registry_md() -> None:
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "a": ["p", "q"] * 4,
            "x": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "z": [1.0, 2, 1, 2, 3, 3, 4, 4],
            "school": ["S1"] * 4 + ["S2"] * 4,
            "class": ["c1", "c2"] * 4,
            "district": ["D1"] * 8,
        }
    )
    declaration: dict[str, Any] = {
        "vocabulary": "0.1.0",
        "units": [
            {"name": "district", "columns": ["district"]},
            {
                "name": "school",
                "columns": ["school"],
                "nested_in": "district",
                "id_scope": "global",
            },
            {
                "name": "class",
                "columns": ["class"],
                "nested_in": "school",
                "id_scope": "within_parent",
            },
        ],
        "assignment": [{"column": "a", "unit": "class", "randomised": True}],
    }
    run = machinery_run(data, "y ~ a * x + (1 | class) + (0 + z | class)", declaration)
    elements = machinery.scope_elements
    assert elements(run, "model") == [{}]
    assert elements(run, "grouping_factor") == [{"factor": "class"}]
    assert elements(run, "grouping_factor_pair") == []
    # school, the column of the parent of the unit of class, is not a grouping
    # column, so it is paired with class.
    assert elements(run, "grouping_column_pair") == [{"first": "class", "second": "school"}]
    assert [e["term"] for e in elements(run, "fixed_term")] == ["a", "x", "a:x"]
    assert len(elements(run, "fixed_term_by_factor")) == 3
    assert elements(run, "assignment") == [{"column": "a", "unit": "class"}]
    assert [e["column"] for e in elements(run, "column")] == [
        "a",
        "class",
        "district",
        "school",
        "x",
        "y",
        "z",
    ]
    assert machinery.unit_label_columns(run.declaration, "class") == ["school", "class"]
    assert machinery.unit_label_columns(run.declaration, "school") == ["school"]
    run = machinery_run(data, "y ~ x + (1 | class) + (1 + x | school:class)", declaration)
    assert elements(run, "grouping_factor_pair") == [{"first": "class", "second": "school:class"}]
    # school is now a grouping column, and the column of its parent is not.
    assert elements(run, "grouping_column_pair") == [
        {"first": "class", "second": "school"},
        {"first": "district", "second": "school"},
    ]
    assert elements(run, "random_term")[1] == {
        "term": "1 + x | school:class",
        "factor": "school:class",
    }
    assert len(elements(run, "fixed_term_by_factor")) == 2
    # A nesting that counts as absent gives no parent.
    declaration["provenance"] = {"inferred": ["/units/2/nested_in"]}
    run = machinery_run(data, "y ~ x + (1 | class)", declaration)
    assert elements(run, "grouping_column_pair") == []
    assert machinery.unit_label_columns(run.declaration, "class") == ["class"]
    run = machinery_run(data, "y ~ x")
    assert elements(run, "grouping_factor_or_model") == [{}]
    assert elements(run, "assignment") == []


def test_by_unit_counts_resolve_by_the_members_of_the_disclosure_unit() -> None:
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "pupil": ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p7"],
            "school": ["A", "A", "B", "B", "C", "C", "D", "D"],
            "session": ["s1", "s1", "s2", "s2", "s3", "s4", "s5", "s5"],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "units": [{"name": "pupil", "columns": ["pupil"], "role": "participant"}],
    }
    run = machinery_run(data, "y ~ 1 + (1 | school) + (1 | session)", declaration)
    assert run.disclosure is not None
    assert (run.disclosure.name, run.disclosure.source) == ("pupil", "participant")

    def item(key: str) -> Any:
        return machinery.value_codes(run, [key])

    resolve = machinery.resolve_count_class
    rows = np.arange(8)
    # Every school holds two pupils, but D holds one pupil twice.
    assert resolve(run, [item("school")], rows[:6]) == "non_person"
    assert resolve(run, [item("school")], rows) == "person"
    # Sessions s3 and s4 hold one pupil each.
    assert resolve(run, [item("session")], rows[:4]) == "non_person"
    assert resolve(run, [item("session")], rows[:6]) == "person"
    # Combinations of two items.
    assert resolve(run, [item("school"), item("session")], rows[:4]) == "non_person"
    assert resolve(run, [item("school"), item("session")], rows[:6]) == "person"
    assert resolve(run, [None], rows) == "person"
    # An item without a level in the rows resolves to non_person.
    assert resolve(run, [np.full(8, -1)], rows) == "non_person"
    # A level whose rows all lack a member has none.
    data["pupil"] = pd.Series([None, None, "p3", "p4", "p5", "p6", "p7", "p7"], dtype=object)
    run = machinery_run(data, "y ~ 1 + (1 | school)", declaration)
    assert resolve(run, [machinery.value_codes(run, ["school"])], rows[:6]) == "person"
    # Without a disclosure unit, every by_unit count counts persons.
    run = machinery_run(data, "y ~ 1 + (1 | school)")
    assert run.disclosure is None
    assert resolve(run, [machinery.value_codes(run, ["school"])], rows[2:6]) == "person"


def test_the_support_counts_the_contributors_of_each_basis() -> None:
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6],
            "g": ["a", "a", "a", "a", "a", "b"],
            "h": pd.Series([1, 2, 3, 4, 5, None], dtype=object),
            "x": [1.0, 2, 3, 4, 5, 6],
        }
    )
    run = machinery_run(data, "y ~ x + (1 | g) + (1 | h)")
    support = machinery.sample_support(run, "table")
    assert (support.rows, support.basis, support.distinct, support.dominated) == (
        6,
        "grouping_factors",
        2,
        True,
    )
    assert support.largest == {"g": 6, "h": 2}
    assert machinery.sample_support(run, "design").rows == 5
    run = machinery_run(data, "y ~ x")
    support = machinery.sample_support(run, "design")
    assert (support.rows, support.basis, support.distinct, support.dominated) == (
        6,
        "rows",
        6,
        False,
    )
    assert support.largest == 2
    run = machinery_run(data.iloc[:1], "y ~ x")
    assert machinery.sample_support(run, "design").dominated


def test_findings_are_ordered_by_check_and_then_by_their_scopes() -> None:
    def finding(check: str, scope: dict[str, str]) -> machinery.Finding:
        return machinery.Finding(check, 1, "T0", scope, False)

    findings = [
        finding("b.check", {"column": "a"}),
        finding("a.check", {"second": "x", "first": "z"}),
        finding("a.check", {"first": "y", "second": "x"}),
        finding("a.check", {"first": "y"}),
        finding("b.check", {"column": "B"}),
        finding("a.check", {"first": "é"}),
        finding("a.check", {"first": "éz"}),
    ]
    ordered = machinery.order_findings(findings)
    assert [" ".join([f.check, *f.scope.values()]) for f in ordered] == [
        "a.check y",
        "a.check y x",
        "a.check x z",
        "a.check é",
        "a.check éz",
        "b.check B",
        "b.check a",
    ]


def test_check_functions_that_break_the_machinerys_contract_are_internal_errors() -> None:
    run = machinery_run(audit_data(), "y ~ x + (1 | subject)")
    entry = registry_entry("keys.duplicates")

    def bad(element: Any, entry: dict[str, Any] = entry) -> str:
        with pytest.raises(RuntimeError) as caught:
            machinery.assemble_finding(run, entry, {}, element)
        return str(caught.value)

    assert "not check_element" in bad({})
    assert "no statistic 'no_such'" in bad(machinery.check_element({"no_such": 1}))
    assert "not a valid count" in bad(machinery.check_element({"rows": -1}))
    assert "not a valid count" in bad(machinery.check_element({"rows": True}))
    assert "not a valid count" in bad(machinery.check_element({"rows": 1.5}))
    assert "some rule of its decision" in bad(machinery.check_element({"rows": 1}, rules=[True]))
    assert "not a valid names" in bad(machinery.check_element({"key_columns": "id"}))
    entry = registry_entry("outcome.boundary_shares")
    assert "not a valid ratio" in bad(machinery.check_element({"floor_share": 0.5}), entry)
    # Counts may be numpy integers and integral floats.
    finding = machinery.assemble_finding(
        run,
        registry_entry("keys.duplicates"),
        {},
        machinery.check_element(
            {
                "key_columns": np.array(["id"]),
                "rows": np.int64(8),
                "missing_key_rows": 0.0,
                "duplicated_keys": 0,
                "conflicting_keys": 0,
                "identical_keys": 0,
                "duplicate_rows": 0,
            },
            rules=[False, False, False],
        ),
    )
    assert finding.values["rows"] == 8 and isinstance(finding.values["rows"], int)
    assert finding.values["key_columns"] == ["id"]
    assert finding.message is not None and finding.message["id"] == "unique"


def test_a_ratio_is_the_quotient_of_its_counts_and_absent_without_a_denominator() -> None:
    run = machinery_run(audit_data(), "y ~ x")
    entry = registry_entry("outcome.boundary_shares")
    element = machinery.check_element(
        {"rows": 3, "at_floor": 1, "at_ceiling": 0},
        rules=[False] * len(entry["decision"]["rules"]),
        assessability=[False] * len(entry["assessability"]),
    )
    run.analysis = run.design
    finding = machinery.assemble_finding(run, entry, {}, element)
    assert finding.values["floor_share"] == 1 / 3
    assert finding.values["ceiling_share"] == 0.0
    assert (
        list(finding.values)[:3]
        == [name for name in entry["statistics"] if name in finding.values][:3]
    )
    element.statistics["rows"] = 0
    finding = machinery.assemble_finding(run, entry, {}, element)
    assert "floor_share" not in finding.values


def test_value_codes_compare_values_as_keys_compare_them() -> None:
    data = pd.DataFrame(
        {
            "y": [1.0] * 8,
            "s": pd.Series(["é", "é", "a", None, "a", "b", None, "é"], dtype=object),
            "n": [0.0, -0.0, math.nan, math.nan, 1, 1, 2, 0],
            "m": pd.Series([1, 1, None, None, 2, 2, 3, 3], dtype=object),
            "b": [True, False] * 4,
        }
    )
    run = machinery_run(data, "y ~ 1")
    assert machinery.column_codes(run, "s").tolist() == [0, 0, 1, -1, 1, 2, -1, 0]
    assert machinery.column_codes(run, "n").tolist() == [0, 0, 1, 1, 2, 2, 3, 0]
    assert machinery.column_codes(run, "b").tolist() == [0, 1] * 4
    assert machinery.value_codes(run, ["s", "m"]).tolist() == [0, 0, -1, -1, 1, 2, -1, 3]
    assert machinery.value_codes(run, ["s", "m"], missing_level=True).tolist() == [
        0,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
    ]
    assert machinery.value_codes(run, ["m"], rows=np.array([4, 0])).tolist() == [1, 0]
    assert machinery.value_codes(run, []).tolist() == [0] * 8
    with pytest.raises(ValueError):
        machinery.column_codes(run, "s")[0] = 5
    assert machinery.pair_codes(np.array([0, 0, 1, -1]), np.array([1, 1, 0, 0])).tolist() == [
        0,
        0,
        1,
        -1,
    ]
    assert machinery.tabulate(np.array([2, -1, 0, 2]), 4).tolist() == [1, 0, 2, 0]


def test_random_term_values_and_factor_levels_come_from_z() -> None:
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6],
            "x": [0.5, 0.0, 2, 3, 4, 5],
            "g": ["b", "a", "b", "c", "a", "c"],
        }
    )
    run = machinery_run(data, "y ~ x + (1 + x | g)")
    values = machinery.random_term_values(run, 0)
    assert values.count == 3
    assert values.level.tolist() == [1, 0, 1, 2, 0, 2]
    assert values.values.tolist() == [[1, 0.5], [1, 0], [1, 2], [1, 3], [1, 4], [1, 5]]
    levels = machinery.factor_levels(run, "g")
    assert levels.code.tolist() == [1, 0, 1, 2, 0, 2] and levels.count == 3
    with pytest.raises(RuntimeError, match="no grouping factor"):
        machinery.factor_levels(run, "h")
    run = machinery_run(data, "y ~ x + (0 + x | g) + (1 | x)")
    assert not machinery.factor_has_intercept(run, "g")
    assert machinery.factor_has_intercept(run, "x")
    assert machinery.random_term_has_intercept(run.ir["random"][1])


def test_pooled_constancy_pools_agreement_over_the_groups_with_two_rows() -> None:
    groups = np.array([0, 0, 0, 0, 1, 1, 2])
    patterns = np.array([0, 0, 0, 1, 2, 2, 5])
    # 5 of the 6 rows in groups of two or more rows follow their group's
    # most frequent pattern.
    found = machinery.pooled_constancy(groups, patterns, (9, 1))
    assert (found.constant, found.exact) == (False, False)
    found = machinery.pooled_constancy(groups, patterns, (8, 1))
    assert (found.constant, found.exact) == (True, False)
    found = machinery.pooled_constancy(groups, np.array([0, 0, 0, 0, 2, 2, 5]), (99, 2))
    assert (found.constant, found.exact) == (True, True)
    assert machinery.agreement_fraction(registry_entry("structure.within_between")) == (99, 2)
    assert machinery.decimal_fraction("0.125") == (125, 3)
    assert machinery.decimal_fraction("12") == (12, 0)
    assert machinery.row_patterns(np.array([[1.0, 0.0], [1.0, -0.0], [2.0, 0.0]])).tolist() == [
        0,
        0,
        1,
    ]


def test_levels_of_full_rank_and_the_within_level_rank() -> None:
    level = np.array([0, 0, 0, 1, 1, 2])
    values = np.array([[1.0, 1], [1, 2], [1, 3], [1, 5], [1, 5], [1, 7]])
    assert machinery.levels_of_full_rank(values, level, 3).tolist() == [True, False, False]
    assert machinery.levels_of_full_rank(values[:, 1:], level, 3, difference=True).tolist() == [
        True,
        False,
        False,
    ]
    among = np.array([False, True, True])
    assert machinery.levels_of_full_rank(values[:, :1], level, 3, among).tolist() == [
        False,
        True,
        True,
    ]
    # x varies within the first level only, and its intercept never does.
    x = np.array([[1.0, 1], [1, 2], [1, 7], [1, 7], [1, 9]])
    kept = machinery.within_level_rank(x, np.array([0, 0, 1, 1, 2]), 3)
    assert kept == [False, True]
    assert sequential_rule(np.asfortranarray(x)) == [True, True]


def test_exact_group_sums_round_each_sum_once() -> None:
    x = np.array([1e16, 1.0, -1e16, 0.1, 0.2, 0.3, -0.0, 5.0])
    groups = np.array([0, 0, 0, 1, 1, 1, 2, 3])
    sums = machinery.exact_group_sums(x, groups, 5)
    assert sums.tolist() == [1.0, math.fsum([0.1, 0.2, 0.3]), 0.0, 5.0, 0.0]
    assert math.copysign(1, sums[2]) == 1.0
    big = np.array([1.7e308, 1.7e308, -1.7e308])
    assert machinery.exact_group_sums(big, np.zeros(3, dtype=np.int64), 1).tolist() == [1.7e308]
    assert machinery.exact_group_sums(np.zeros(0), np.zeros(0, dtype=np.int64), 2).tolist() == [
        0.0,
        0.0,
    ]
