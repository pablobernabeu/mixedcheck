"""Helpers for the tests that run audit(): the commitment key and time of the
audit corpus, the data of a case, the validation of the documents that
audit() returns and the comparison of findings by the rules of conventions.md
(Comparison across languages) and fixtures/conformance/audits/README.md.
"""

from __future__ import annotations

import math
import re
import struct
import warnings
from typing import Any

import pandas as pd

import mixedcheck
from mixedcheck import canonical_bytes
from mixedcheck._messages import real_text
from mixedcheck._registry import registry_entries_by_id

# The commitment key 00 01 02 ... 1F of conventions.md (Keyed commitments,
# Example) and its identifier.
AUDIT_KEY = bytes(range(32)).hex()
AUDIT_KEY_ID = "630dcd2966c43366"

SPECIAL_VALUES = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}


def corpus_data_frame(data: dict[str, list[Any]]) -> pd.DataFrame:
    """The DataFrame of the data of a case, with columns of dtype object and
    None for null, as read_table() returns them. In a column with a number, the
    strings 'NaN', 'Infinity' and '-Infinity' stand for the special values."""
    columns = {}
    for name, values in data.items():
        present = [value for value in values if value is not None]
        if any(isinstance(v, int | float) and not isinstance(v, bool) for v in present):
            values = [SPECIAL_VALUES[v] if isinstance(v, str) else v for v in values]
        columns[name] = pd.Series(values, dtype=object)
    return pd.DataFrame(columns)


def audit_case_arguments(case: dict[str, Any], privacy: str) -> dict[str, Any]:
    """The arguments of audit() for a case of the audit corpus."""
    args: dict[str, Any] = {
        "data": corpus_data_frame(case["data"]),
        "formula": case["formula"],
    }
    for member in (
        "declaration",
        "family",
        "coding",
        "weights",
        "sample_columns",
        "outcome_access",
        "reason",
        "exploratory",
    ):
        if member in case:
            args[member] = case[member]
    args["privacy"] = privacy
    args["key"] = AUDIT_KEY
    return args


def run_audit(case: dict[str, Any], privacy: str) -> dict[str, Any]:
    """Run a case with MIXEDCHECK_TIME set to 0, by the caller, and return
    {'value': results} or {'issues': ...} for a MixedcheckError."""
    try:
        return {"value": mixedcheck.audit(**audit_case_arguments(case, privacy))}
    except mixedcheck.MixedcheckError as err:
        return {"issues": err.issues}


# --- Comparison of findings ------------------------------------------------------


def reals_match(x: Any, y: Any, check: str, name: str) -> bool:
    """Whether two real values match within the tolerance of conventions.md
    (Comparison across languages), with its exceptions for design.collinearity,
    design.scale_disparity, identifiability.gram_rank and outcome.separation,
    whose tolerance is the parameter bound_tolerance of its entry. 'NaN',
    'Infinity' and '-Infinity' match only themselves."""
    if isinstance(x, str) or isinstance(y, str):
        return bool(x == y)
    m = max(abs(x), abs(y))
    if check == "design.collinearity" and name in ("gvif", "gvif_per_df"):
        return bool(abs(x - y) <= 1e-12 + max(1e-9, 1e-13 * m) * m)
    if check == "design.scale_disparity" and name == "condition_number":
        return bool(abs(x - y) <= 1e-12 + max(1e-9, 1e-14 * m) * m)
    if check == "identifiability.gram_rank" and name == "smallest_eigenvalue":
        return bool(abs(x - y) <= 1e-12 + 1e-9 * max(1, m))
    if check == "outcome.separation":
        parameter = registry_entries_by_id()[check]["parameters"]["bound_tolerance"]
        tolerance = float(parameter["value"])
        return bool(abs(x - y) <= (tolerance if name == "bounds" else tolerance * max(1, m)))
    return bool(abs(x - y) <= 1e-12 + 1e-9 * m)


def written_real(finding: dict[str, Any], name: str) -> float | None:
    """The value of a real statistic that a finding writes, as a float, with
    'NaN', 'Infinity' and '-Infinity' read as those values, or None when the
    finding does not write it."""
    statistic = finding.get("statistics", {}).get(name)
    value = statistic.get("value") if statistic is not None else None
    if value is None:
        return None
    if isinstance(value, str):
        return SPECIAL_VALUES[value]
    return float(value)


def message_form(finding: dict[str, Any]) -> tuple[str, list[str]] | None:
    """The form of a message that the text of a finding renders, the template
    or the fallback, with the renderings of its arguments other than real
    statistics, in the order of the form. A real statistic must render as
    registry.md (Messages) renders the value that the finding writes, so that
    the form can render only when the finding writes it. None when the text
    renders neither form."""
    entry = registry_entries_by_id()[finding["check"]]
    message = entry["messages"][finding["message"]["id"]]
    text = finding["message"]["text"]
    for form in ("template", "fallback"):
        template = message.get(form)
        if template is None:
            continue
        pieces = re.split(r"(\{[a-z][a-z0-9_]*\})", template)
        pattern = []
        renders = True
        for i, piece in enumerate(pieces):
            if i % 2 == 0:
                pattern.append(re.escape(piece))
                continue
            arg = message["args"][piece[1:-1]]
            kind = None
            if arg["source"] == "statistic":
                kind = entry["statistics"][arg["name"]]["kind"]
            if kind != "real":
                pattern.append("(.*?)")
                continue
            value = written_real(finding, arg["name"])
            if value is None:
                renders = False
                break
            pattern.append(re.escape(real_text(value, arg["digits"])))
        if not renders:
            continue
        found = re.fullmatch("".join(pattern), text, re.DOTALL)
        if found is not None:
            return form, list(found.groups())
    return None


def message_texts_match(actual: dict[str, Any], expected: dict[str, Any]) -> bool:
    """Whether the messages of two findings of a check match (conventions.md,
    Comparison across languages): they have the same identifier, both texts
    render its template, or both its fallback, every argument other than a
    real statistic renders identically, the two values of every real
    statistic that the form renders match within the tolerance, and each text
    renders the values of its own finding."""
    if actual["message"]["id"] != expected["message"]["id"]:
        return False
    a = message_form(actual)
    b = message_form(expected)
    if a is None or a != b:
        return False
    check = expected["check"]
    entry = registry_entries_by_id()[check]
    message = entry["messages"][expected["message"]["id"]]
    template = message[a[0]]
    for placeholder, arg in message["args"].items():
        name = arg["name"]
        if (
            arg["source"] != "statistic"
            or entry["statistics"][name]["kind"] != "real"
            or "{" + placeholder + "}" not in template
        ):
            continue
        x = written_real(actual, name)
        y = written_real(expected, name)
        assert x is not None and y is not None
        if math.isfinite(x) and math.isfinite(y):
            same = reals_match(x, y, check, name)
        else:
            same = x == y or (math.isnan(x) and math.isnan(y))
        if not same:
            return False
    return True


def double_bits(value: float) -> str:
    """The 16 hexadecimal digits of the bits of a double."""
    return struct.pack(">d", float(value)).hex()


def expect_audit_finding(
    actual: dict[str, Any], expected: dict[str, Any], exact: list[str], label: str
) -> None:
    """Compare one finding with its expected form: exactly, apart from the
    values of real statistics, compared within the tolerance or bit for bit for
    those that 'exact' lists, the message text, and, for a finding that is
    near_threshold in the expected findings or in the run, the finding status,
    the message and threshold_proximity, and for outcome.separation and
    identifiability.gram_rank also the values that their solver or their
    comparisons with rank_tolerance decide (conventions.md, Comparison across
    languages)."""
    check = expected["check"]

    def is_near(finding: dict[str, Any]) -> bool:
        proximity = finding.get("status", {}).get("threshold_proximity", {})
        return bool(proximity.get("value") == "near_threshold")

    near = is_near(expected) or is_near(actual)
    solved: list[str] = []
    if near and check == "outcome.separation":
        solved = ["verdict", "optimum", "margin", "bounds", "columns_involved"]
    elif near and check == "identifiability.gram_rank":
        solved = ["rank", "verdict", "vanishing_parameters", "confounded_parameters"]
        solved.append("smallest_eigenvalue")
    reals = [
        name
        for name, statistic in expected.get("statistics", {}).items()
        if statistic["kind"] in ("real", "reals") and name not in solved
    ]

    def strip(finding: dict[str, Any]) -> dict[str, Any]:
        finding = dict(finding)
        statistics = {
            name: dict(statistic) for name, statistic in finding.get("statistics", {}).items()
        }
        for name in reals:
            if name in statistics:
                statistics[name]["value"] = "real"
        if "message" in finding:
            finding["message"] = {**finding["message"], "text": "text"}
        if near:
            finding["status"] = {
                name: value
                for name, value in finding["status"].items()
                if name not in ("finding", "threshold_proximity")
            }
            finding.pop("message", None)
            for name in solved:
                statistics.pop(name, None)
        if "statistics" in finding:
            finding["statistics"] = statistics
        return finding

    stripped_actual = canonical_bytes(strip(actual)).decode("utf-8")
    stripped_expected = canonical_bytes(strip(expected)).decode("utf-8")
    assert stripped_actual == stripped_expected, label
    for name in reals:
        x = actual["statistics"].get(name, {}).get("value")
        y = expected["statistics"][name].get("value")
        if x is None or y is None:
            continue
        here = f"{label} {name}"
        xs = x if isinstance(x, list) else [x]
        ys = y if isinstance(y, list) else [y]
        if f"{check}:{name}" in exact:
            assert [double_bits(v) for v in xs] == [double_bits(v) for v in ys], here
        else:
            assert len(xs) == len(ys), here
            assert all(reals_match(a, b, check, name) for a, b in zip(xs, ys, strict=True)), here
    if not near and "message" in expected:
        assert message_texts_match(actual, expected), (
            f"{label} message: '{actual['message']['text']}' does not match the expected "
            f"'{expected['message']['text']}'."
        )


def expect_valid_results(results: Any, case: dict[str, Any] | None = None) -> None:
    """Every document that audit() returns is valid: validate_results() passes
    it without an error or a warning, and verifies its own sidecar and, for a
    case of the audit corpus, its commitments against the data and the
    declaration of the case."""
    data = corpus_data_frame(case["data"]) if case is not None else None
    declaration = case.get("declaration") if case is not None else None
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        mixedcheck.validate_results(results, data=data, declaration=declaration)


def expect_audit_findings(
    result: dict[str, Any], expected: list[dict[str, Any]], case: dict[str, Any], label: str
) -> None:
    """Compare the findings of the checks of a case with the expected list."""
    assert "value" in result, (
        f"{label}: expected findings, got {result['issues'][0]['code']}: "
        f"{result['issues'][0]['message']}"
    )
    results = result["value"]
    expect_valid_results(results, case)
    checks = case["checks"]
    findings = [f for f in results.document["findings"] if f["check"] in checks]
    assert len(findings) == len(expected), label
    exact = case.get("exact", [])
    for i, (actual, wanted) in enumerate(zip(findings, expected, strict=True)):
        expect_audit_finding(actual, wanted, exact, f"{label} finding {i + 1}")
