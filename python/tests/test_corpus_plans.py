"""The plan corpus: plans checked in the four stages of validate_plan()
(fixtures/conformance/plans/README.md)."""

from __future__ import annotations

from typing import Any

import pytest
from corpus_helpers import corpus_cases, corpus_directory

from mixedcheck import MixedcheckError, validate_plan

CASES = corpus_cases("plans", "validate.json")


@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_plan_corpus(case: dict[str, Any]) -> None:
    try:
        validate_plan(str(corpus_directory("plans") / case["plan"]))
    except MixedcheckError as err:
        found = err.issues
    else:
        found = []
    assert found == case["expected"]["issues"]
