"""The audit corpus: every case runs through audit() in internal mode with the
commitment key 00 01 02 ... 1F and MIXEDCHECK_TIME set to 0, and its findings,
or the issue that refuses the run, are compared with the expected ones as
fixtures/conformance/audits/README.md describes. A case that states shareable
findings also runs in shareable mode, and its findings are compared with
those. Every document that audit() returns is validated with
validate_results() and its commitments verified against the data and
declaration of the case.
"""

from __future__ import annotations

from typing import Any

import pytest
from audit_helpers import (
    expect_audit_findings,
    message_texts_match,
    run_audit,
)
from corpus_helpers import corpus_cases, expect_issue

from mixedcheck._messages import render_message
from mixedcheck._registry import registry_entry

AUDIT_FILES = (
    "assignment.json",
    "design.json",
    "identifiability.json",
    "keys.json",
    "labels.json",
    "outcome.json",
    "privacy.json",
    "sample.json",
    "structure.json",
)

CASES = [case for name in AUDIT_FILES for case in corpus_cases("audits", name)]
SHAREABLE = [case for case in CASES if "shareable" in case["expected"]]


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every case runs at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_audit_corpus(case: dict[str, Any]) -> None:
    expected = case["expected"]
    if "issue" in expected:
        result = run_audit(case, case.get("privacy", "internal"))
        expect_issue(result, expected["issue"], case["id"])
        return
    expect_audit_findings(run_audit(case, "internal"), expected["findings"], case, case["id"])


@pytest.mark.parametrize("case", SHAREABLE, ids=[case["id"] for case in SHAREABLE])
def test_audit_corpus_shareable(case: dict[str, Any]) -> None:
    expect_audit_findings(
        run_audit(case, "shareable"), case["expected"]["shareable"], case, f"{case['id']} shareable"
    )


def test_the_audit_corpus_holds_307_cases_in_nine_files() -> None:
    assert len(CASES) == 307
    assert len({case["id"] for case in CASES}) == 307


def message_finding(
    check: str,
    id: str,
    values: dict[str, Any],
    scope: dict[str, str] | None = None,
    text: str | None = None,
    written: list[str] | None = None,
) -> dict[str, Any]:
    """A finding of a check with the given statistics and message, whose text is
    rendered from them unless 'text' gives it."""
    entry = registry_entry(check)
    shown = list(values) if written is None else written
    statistics = {
        name: {
            "kind": entry["statistics"][name]["kind"],
            "value": values[name] if name in shown else None,
        }
        for name in values
    }
    rendered = text if text is not None else render_message(entry, id, scope or {}, values, shown)
    return {
        "check": check,
        "scope": scope or {},
        "statistics": statistics,
        "message": {"id": id, "text": rendered},
    }


def test_messages_match_by_their_values_whatever_the_renderings_of_their_reals() -> None:
    def gvif(value: float, term: str = "x", id: str = "high") -> dict[str, Any]:
        return message_finding(
            "design.collinearity",
            id,
            {"df": 1, "gvif": value, "gvif_per_df": value},
            scope={"term": term},
        )

    def ratio(value: float) -> dict[str, Any]:
        return message_finding(
            "design.scale_disparity",
            "disparate",
            {"scaled_columns": ["x1", "x2"], "sd_ratio": value},
        )

    def events(
        per_column: float,
        count: int = 1,
        text: str | None = None,
        written: list[str] | None = None,
    ) -> dict[str, Any]:
        return message_finding(
            "outcome.minority_events",
            "events_model",
            {"events": count, "non_events": 20, "events_per_column": per_column},
            text=text,
            written=written,
        )

    # Values within the tolerance whose renderings differ by several units of
    # the last place, in notation, as under 0.1 and 0.1 or as neighbouring
    # roundings.
    pairs = [
        (gvif(4e5), gvif(400000.015)),
        (ratio(2e9), ratio(2000000001.5)),
        (ratio(1e15 - 0.125), ratio(1e15)),
        (events(0.05 - 2.0**-57), events(0.05)),
        (gvif(1.255), gvif(1.255 + 1e-12)),
    ]
    for first, second in pairs:
        assert first["message"]["text"] != second["message"]["text"]
        assert message_texts_match(first, second)
        assert message_texts_match(second, first)
    assert message_texts_match(events(1 / 21), events(1 / 21))
    fallback = events(1 / 21, written=["events", "non_events"])
    assert message_texts_match(fallback, fallback)
    # An argument other than a real that differs, values outside the
    # tolerance, a text that does not render its own value, a template against
    # its fallback and two messages.
    assert not message_texts_match(gvif(2, term="x"), gvif(2, term="z"))
    assert not message_texts_match(events(1 / 21, count=1), events(1 / 21, count=2))
    assert not message_texts_match(events(1 / 21), events(0.1))
    assert not message_texts_match(gvif(4e5), gvif(400000.02))
    wrong = (
        "The outcome has 1 event and 20 non-events, or 0.0 minority events per fixed-effects "
        "column."
    )
    assert not message_texts_match(events(1 / 21), events(1 / 21, text=wrong))
    assert not message_texts_match(events(1 / 21, text=wrong), events(1 / 21, text=wrong))
    assert not message_texts_match(events(1 / 21), fallback)
    assert not message_texts_match(gvif(7, id="moderate"), gvif(7, id="high"))
