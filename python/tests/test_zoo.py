"""The pathology zoo: every fixture and matched negative runs through audit()
in internal and in shareable mode with the commitment key 00 01 02 ... 1F and
MIXEDCHECK_TIME set to 0, and its findings are compared with its expected
findings by the rules of fixtures/zoo/README.md (Comparison). The fixtures are
read from the installed copy, or from the directory that MIXEDCHECK_ZOO_DIR
names."""

from __future__ import annotations

import copy
from typing import Any

import pytest
from zoo_helpers import zoo_differences, zoo_run, zoo_test_directories

from mixedcheck._zoo import read_fixture

DIRECTORIES = zoo_test_directories()


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def test_the_zoo_has_directories_to_test() -> None:
    assert DIRECTORIES


@pytest.mark.parametrize("privacy", ["internal", "shareable"])
@pytest.mark.parametrize("fixture_id", list(DIRECTORIES))
def test_the_fixture_gives_its_expected_findings(fixture_id: str, privacy: str) -> None:
    fixture = read_fixture(DIRECTORIES[fixture_id])
    assert fixture["id"] == fixture_id
    found = zoo_differences(zoo_run(fixture, privacy), fixture["expected"], privacy)
    assert not found, "\n".join(f"{fixture_id} {privacy} {line}" for line in found)


def test_the_comparison_reports_each_kind_of_difference() -> None:
    assert "Z01" in DIRECTORIES
    fixture = read_fixture(DIRECTORIES["Z01"])
    result = zoo_run(fixture, "internal")
    expected = fixture["expected"]
    assert zoo_differences(result, expected, "internal") == []
    checks = [finding["check"] for finding in expected["findings"]]
    incidence = checks.index("structure.label_incidence")
    where = f"/findings/{incidence}"

    def differences(change: Any) -> str:
        changed = copy.deepcopy(expected)
        change(changed)
        return "\n".join(zoo_differences(result, changed, "internal"))

    def statistics(changed: dict[str, Any]) -> dict[str, Any]:
        found: dict[str, Any] = changed["findings"][incidence]["statistics"]
        return found

    assert f"{where}/statistics/levels_first: 3 and 4" in differences(
        lambda e: statistics(e)["levels_first"].update(value=4)
    )
    assert "count class" in differences(
        lambda e: statistics(e)["levels_first"].update(count_class="person")
    )
    assert f"{where}/statistics/composite: false and nothing" in differences(
        lambda e: statistics(e).pop("composite")
    )
    assert "false and absent" in differences(
        lambda e: statistics(e).update(composite={"absent": True})
    )
    assert f"{where}/status" in differences(
        lambda e: e["findings"][incidence].update(status={"finding": "consistent"})
    )
    assert f"{where}/message" in differences(
        lambda e: e["findings"][incidence].update(message="relation")
    )
    assert "beyond the expectation" in differences(lambda e: e["findings"].pop(incidence))
    assert "/support/contributors" in differences(
        lambda e: e["samples"]["design"].update(distinct=239)
    )

    gram = checks.index("identifiability.gram_rank")

    def eigenvalue(changed: dict[str, Any]) -> dict[str, Any]:
        found: dict[str, Any] = changed["findings"][gram]["statistics"]
        return found

    value = expected["findings"][gram]["statistics"]["smallest_eigenvalue"]["value"]
    assert "smallest_eigenvalue" in differences(
        lambda e: eigenvalue(e).update(smallest_eigenvalue={"value": value * (1 + 1e-6)})
    )
    assert (
        differences(lambda e: eigenvalue(e).update(smallest_eigenvalue={"interval": [0.78, 0.79]}))
        == ""
    )
    assert "the interval" in differences(
        lambda e: eigenvalue(e).update(smallest_eigenvalue={"interval": [0.8, 0.9]})
    )
    assert differences(lambda e: eigenvalue(e).pop("smallest_eigenvalue")) == ""

    def issue(changed: dict[str, Any]) -> None:
        del changed["findings"]
        changed["issue"] = {"code": "E6069", "message": "A message."}

    assert "/issue" in differences(issue)
