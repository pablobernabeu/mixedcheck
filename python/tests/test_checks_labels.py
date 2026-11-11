"""labels.unicode_forms, in the parts that the audit corpus cannot reach: the
strings that are not normalisable and the label columns that an entry of the
assignment block adds while its unit does not count as absent."""

from __future__ import annotations

from typing import Any

import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

from mixedcheck import audit


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def label_findings(data: pd.DataFrame, formula: str, **arguments: Any) -> list[dict[str, Any]]:
    """The findings of labels.unicode_forms for an audit in internal mode."""
    results = audit(data, formula, privacy="internal", key=AUDIT_KEY, **arguments)
    return [f for f in results.document["findings"] if f["check"] == "labels.unicode_forms"]


def test_a_string_that_is_not_normalisable_stands_for_itself() -> None:
    # U+0378 is not assigned in Unicode 14.0, so the two spellings that hold it
    # are compared as they are, whereas the two without it share their NFC
    # form. Missing values are not labels.
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6],
            "g": ["\u00e9\u0378", "e\u0301\u0378", "\u00e9", "e\u0301", None, "b"],
        }
    )
    found = label_findings(data, "y ~ 1 + (1 | g)")
    assert [f["scope"] for f in found] == [{"column": "g"}]
    assert found[0]["statistics"]["spellings"]["value"] == 2
    assert found[0]["statistics"]["labels"]["value"] == 1
    assert found[0]["message"]["id"] == "merged"


def test_the_columns_of_the_assignment_block_hold_labels_while_their_unit_is_declared() -> None:
    # An entry of the assignment block makes its column a label column only
    # while the entry counts as present, which it does not when its unit
    # counts as absent.
    data = pd.DataFrame(
        {
            "y": [float(i) for i in range(1, 13)],
            "arm": [a for a in ("T", "C", "T", "C") for _ in range(3)],
            "school": ["S1"] * 6 + ["S2"] * 6,
            "class": [c for c in ("c1", "c2", "c3", "c4") for _ in range(3)],
        }
    )
    data["arm2"] = data["arm"]
    declaration: dict[str, Any] = {
        "vocabulary": "0.1.0",
        "units": [
            {"name": "school", "columns": ["school"], "role": "cluster"},
            {"name": "class", "columns": ["class"], "role": "cluster"},
        ],
        "assignment": [
            {"column": "arm", "unit": "class", "randomised": True, "level": "between_unit"},
            {"column": "arm2", "unit": "school", "randomised": True, "level": "between_unit"},
        ],
    }
    columns = [
        f["scope"]["column"]
        for f in label_findings(data, "y ~ 1 + (1 | class)", declaration=declaration)
    ]
    assert columns == ["arm", "arm2", "class"]
    declaration["provenance"] = {"inferred": ["/units/0"]}
    columns = [
        f["scope"]["column"]
        for f in label_findings(data, "y ~ 1 + (1 | class)", declaration=declaration)
    ]
    assert columns == ["arm", "class"]


def test_the_outcome_holds_no_labels_whatever_else_names_it() -> None:
    # 'resp' is the response and 'score' has the role outcome, so neither is
    # read, although each holds two spellings of one label.
    data = pd.DataFrame(
        {
            "resp": ["\u00e9", "e\u0301", "a", "b"],
            "score": ["\u00e9", "e\u0301", "a", "b"],
            "site": ["s1", "s1", "s2", "s2"],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"score": {"role": "outcome"}, "site": {"role": "assigned"}},
    }
    columns = [
        f["scope"]["column"]
        for f in label_findings(data, "resp ~ 1 + (1 | site)", declaration=declaration)
    ]
    assert columns == ["site"]
