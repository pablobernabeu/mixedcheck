"""Helpers for the tests of the pathology zoo: the directories to test, the run
of a fixture and the comparison of its findings with its expected findings by
the rules of fixtures/zoo/README.md (Comparison), which parity/parity.py
applies too."""

from __future__ import annotations

import os
import re
import warnings
from importlib.resources import files
from importlib.resources.abc import Traversable
from pathlib import Path
from typing import Any

from audit_helpers import AUDIT_KEY, reals_match

import mixedcheck
from mixedcheck import canonical_bytes
from mixedcheck._registry import registry_entries_by_id

# The defaults of the status fields that an expectation leaves out.
STATUS_DEFAULTS = {
    "availability": "available",
    "assessability": "adequate",
    "threshold_proximity": "clear",
    "validation": "descriptive",
}


def zoo_test_directories() -> dict[str, Traversable]:
    """The directories to test, by identifier: those under the directory that
    MIXEDCHECK_ZOO_DIR names when it is set, such as fixtures/zoo/ of the
    source tree, and otherwise those that the installed index.json lists."""
    root = os.environ.get("MIXEDCHECK_ZOO_DIR", "")
    if root:
        path = Path(root)
        names = sorted(
            entry.name
            for entry in path.iterdir()
            if entry.is_dir() and re.match(r"Z[0-9]{2}N?-", entry.name)
        )
        return {name.split("-", 1)[0]: path / name for name in names}
    installed = files("mixedcheck") / "_fixtures" / "zoo"
    index = mixedcheck.read_json_strict((installed / "index.json").read_bytes(), "data")
    return {
        entry["id"]: installed / f"{entry['id']}-{entry['name']}" for entry in index["fixtures"]
    }


def zoo_run(fixture: dict[str, Any], privacy: str) -> dict[str, Any]:
    """Run audit() on a fixture with the commitment key 00 01 02 ... 1F, with
    MIXEDCHECK_TIME set to 0 by the caller. Returns {'value': results} or
    {'issues': ...} for a MixedcheckError."""
    try:
        results = mixedcheck.audit(
            fixture["data"],
            fixture["formula"],
            fixture["declaration"],
            **fixture["arguments"],
            privacy=privacy,
            key=AUDIT_KEY,
        )
    except mixedcheck.MixedcheckError as err:
        return {"issues": err.issues}
    return {"value": results}


def show(value: Any) -> str:
    """A value as canonical JSON text, or 'nothing' for None."""
    if value is None:
        return "nothing"
    try:
        return canonical_bytes(value).decode("utf-8")
    except mixedcheck.MixedcheckError:
        return repr(value)


def same(x: Any, y: Any) -> bool:
    """Whether two values have the same canonical bytes."""
    return bool(canonical_bytes([x]) == canonical_bytes([y]))


def expected_status(status: dict[str, Any]) -> dict[str, Any]:
    """The status of an expected finding with the defaults of the zoo:
    available, adequate, clear and descriptive, unless the finding is not
    available."""
    expanded = {
        name: {"value": field} if isinstance(field, str) else field
        for name, field in status.items()
    }
    if expanded.get("availability", {}).get("value") == "not_available":
        return expanded
    for name, value in STATUS_DEFAULTS.items():
        expanded.setdefault(name, {"value": value})
    return expanded


def scope_key(finding: dict[str, Any]) -> str:
    return canonical_bytes([finding["check"], finding["scope"]]).decode("utf-8")


def statistic_differences(
    actual: dict[str, Any], wanted: dict[str, Any], check: str, name: str, here: str
) -> list[str]:
    """How one written statistic differs from its expectation."""
    found = []
    if "count_class" in wanted and actual.get("count_class") != wanted["count_class"]:
        found.append(
            f"{here}: count class {show(actual.get('count_class'))} and "
            f"{show(wanted['count_class'])}"
        )
    value = actual.get("value")
    if wanted.get("absent"):
        found.append(f"{here}: {show(value)} and absent")
    elif "ratio" in wanted:
        numerator, denominator = wanted["ratio"]
        if not (isinstance(value, float | int) and value == numerator / denominator):
            found.append(f"{here}: {show(value)} and the ratio {show(wanted['ratio'])}")
    elif "interval" in wanted:
        low, high = wanted["interval"]
        values = value if isinstance(value, list) else [value]
        numeric = all(isinstance(v, float | int) and not isinstance(v, bool) for v in values)
        if not values or not numeric or any(v < low or v > high for v in values):
            found.append(f"{here}: {show(value)} and the interval {show(wanted['interval'])}")
    elif actual.get("kind") in ("real", "reals"):
        xs = value if isinstance(value, list) else [value]
        ys = wanted["value"] if isinstance(wanted["value"], list) else [wanted["value"]]
        if len(xs) != len(ys) or not all(
            reals_match(x, y, check, name) for x, y in zip(xs, ys, strict=False)
        ):
            found.append(f"{here}: {show(value)} and {show(wanted['value'])}")
    elif not same(value, wanted["value"]):
        found.append(f"{here}: {show(value)} and {show(wanted['value'])}")
    return found


def finding_differences(
    actual: dict[str, Any],
    wanted: dict[str, Any],
    samples: dict[str, Any],
    privacy: str,
    here: str,
) -> list[str]:
    """How one finding of a run differs from its expectation in a privacy
    mode."""
    check = wanted["check"]
    shareable = privacy == "shareable"
    status = actual["status"]
    availability = status.get("availability", {})
    if (
        shareable
        and actual.get("tier") != "T0"
        and availability.get("reason") == "privacy_suppressed"
        and availability.get("detail") == "decision"
    ):
        return []
    expanded = expected_status(wanted["status"])
    if not same(status, expanded):
        return [f"{here}/status: {show(status)} and {show(expanded)}"]
    if availability.get("value") != "available":
        return []
    found = []
    message = actual.get("message", {}).get("id")
    if message != wanted.get("message"):
        found.append(f"{here}/message: {show(message)} and {show(wanted.get('message'))}")
    statistics = actual.get("statistics", {})
    expected = wanted.get("statistics", {})
    for name, statistic_wanted in expected.items():
        where = f"{here}/statistics/{name}"
        statistic = statistics.get(name)
        if statistic is None:
            if not statistic_wanted.get("absent"):
                found.append(f"{where}: nothing and {show(statistic_wanted)}")
            continue
        if shareable and statistic.get("value") is None:
            if (
                "count_class" in statistic_wanted
                and statistic.get("count_class") != statistic_wanted["count_class"]
            ):
                found.append(
                    f"{where}: count class {show(statistic.get('count_class'))} and "
                    f"{show(statistic_wanted['count_class'])}"
                )
            continue
        found += statistic_differences(statistic, statistic_wanted, check, name, where)
    for name, statistic in statistics.items():
        if name not in expected and statistic["kind"] not in ("real", "reals"):
            found.append(f"{here}/statistics/{name}: {show(statistic.get('value'))} and nothing")
    sample = samples[registry_entries_by_id()[check]["sample"]]
    support = actual["support"]

    def written(value: Any) -> bool:
        return not shareable or value is not None

    rows = support["rows"].get("value")
    if written(rows) and rows != sample["rows"]:
        found.append(f"{here}/support/rows: {show(support['rows'])} and {sample['rows']}")
    contributors = support["contributors"]
    distinct = contributors["distinct"].get("value")
    if (
        contributors["basis"] != sample["basis"]
        or contributors["dominated"] != sample["dominated"]
        or (written(distinct) and distinct != sample["distinct"])
    ):
        found.append(f"{here}/support/contributors: {show(contributors)} and {show(sample)}")
    return found


def zoo_differences(result: dict[str, Any], expected: dict[str, Any], privacy: str) -> list[str]:
    """How the result of a run differs from the expected findings of its
    fixture, as lines that name the JSON Pointer of the member and both
    values. The result is {'value': results} or {'issues': ...}."""
    issue = expected.get("issue")
    if issue is not None:
        issues = result.get("issues")
        if issues is None:
            return ["/issue: a document and the issue"]
        names = ("code", "message", "pointer")
        got = {name: issues[0][name] for name in names if issues[0].get(name) is not None}
        want = {name: issue[name] for name in names if issue.get(name) is not None}
        if len(issues) != 1 or not same(got, want):
            return [f"/issue: {show(issues)} and {show(issue)}"]
        return []
    if "issues" in result:
        return [f"/findings: the issue {show(result['issues'])} and findings"]
    found = []
    results = result["value"]
    if privacy == "shareable":
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error")
                mixedcheck.validate_results(results)
        except (mixedcheck.MixedcheckError, Warning) as err:
            found.append(f"validate_results(): {err}")
    findings = results.document["findings"]
    wanted = expected["findings"]
    keys = [scope_key(finding) for finding in findings]
    wanted_keys = [scope_key(finding) for finding in wanted]
    if keys != wanted_keys:
        beyond = [key for key in keys if key not in wanted_keys]
        lacks = [key for key in wanted_keys if key not in keys]
        order = ", in another order" if sorted(keys) == sorted(wanted_keys) else ""
        found.append(
            f"/findings: the run has {beyond} beyond the expectation and lacks {lacks}{order}"
        )
        return found
    for i, (actual, finding) in enumerate(zip(findings, wanted, strict=True)):
        found += finding_differences(
            actual, finding, expected["samples"], privacy, f"/findings/{i}"
        )
    return found
