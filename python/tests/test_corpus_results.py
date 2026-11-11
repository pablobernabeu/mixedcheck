"""The results corpus: results documents checked in the five stages of
validate_results(), and internal sidecars read, checked and verified against
their documents (fixtures/conformance/results/README.md)."""

from __future__ import annotations

import warnings
from collections.abc import Callable
from typing import Any

import pytest
from corpus_helpers import corpus_cases, corpus_directory

from mixedcheck import MixedcheckError, MixedcheckWarning, validate_results

RESULTS_FILES = (
    "reading.json",
    "version.json",
    "structure.json",
    "rules.json",
    "shareable.json",
    "registry.json",
    "stages.json",
    "sidecar.json",
    "valid.json",
)

CASES = [case for name in RESULTS_FILES for case in corpus_cases("results", name)]


def capture_results_issues(f: Callable[[], Any]) -> dict[str, Any]:
    """Call f and return the issues of its warnings and of its error, in the
    order signalled, and whether it raised an error."""
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            f()
        except MixedcheckError as err:
            raised: list[dict[str, Any]] | None = err.issues
        else:
            raised = None
    warned = [
        issue
        for warning in caught
        if isinstance(warning.message, MixedcheckWarning)
        for issue in warning.message.issues
    ]
    assert len(warned) == len(caught), "a warning of another class"
    return {"issues": warned + (raised or []), "error": raised is not None}


def case_path(case: dict[str, Any], member: str) -> str | None:
    """The path of an input of a case, or None when the case has none."""
    if member not in case:
        return None
    return str(corpus_directory("results") / case[member])


@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_results_corpus(case: dict[str, Any]) -> None:
    document = case_path(case, "document")
    expected = case["expected"]
    found = capture_results_issues(lambda: validate_results(document))
    assert found["issues"] == expected["issues"], case["id"]
    if "sidecar" not in case:
        return
    verified = capture_results_issues(
        lambda: validate_results(
            document,
            case_path(case, "sidecar"),
            case_path(case, "data"),
            case_path(case, "declaration"),
        )
    )
    label = f"{case['id']} sidecar"
    if found["error"]:
        # An error in the document stops validation before the sidecar.
        assert expected.get("sidecar_issues", []) == [], label
        assert verified == found, label
    else:
        # The warning W7090, if any, comes before the issues of the sidecar.
        assert verified["issues"][: len(found["issues"])] == found["issues"], label
        assert verified["issues"][len(found["issues"]) :] == expected["sidecar_issues"], label


def test_the_results_corpus_holds_152_cases_in_nine_files() -> None:
    assert len(CASES) == 152
    assert len({case["id"] for case in CASES}) == 152
    assert sum("sidecar" in case for case in CASES) > 0
