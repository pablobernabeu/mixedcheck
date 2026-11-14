"""The assignment checks, in the parts that the audit corpus cannot reach: the
tolerance of the parameter agreement, which tables of 40 rows cannot test,
design_df against the literal sequential rule on the indicator columns, and
the members of the assignment block that /provenance/inferred marks."""

from __future__ import annotations

import copy
import re
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

from mixedcheck import audit, design_matrices, formula_ir
from mixedcheck._design import sequential_rule


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def assignment_findings(
    data: pd.DataFrame, formula: str, declaration: dict[str, Any], check: str
) -> list[dict[str, Any]]:
    """The findings of one check for an audit in internal mode."""
    results = audit(data, formula, declaration, privacy="internal", key=AUDIT_KEY)
    return [f for f in results.document["findings"] if f["check"] == check]


def assignment_values(finding: dict[str, Any]) -> dict[str, Any]:
    return {name: statistic["value"] for name, statistic in finding["statistics"].items()}


def class_declaration(**members: Any) -> dict[str, Any]:
    return {
        "vocabulary": "0.1.0",
        "units": [{"name": "class", "columns": ["class"], "role": "cluster"}],
        "assignment": [{"column": "arm", "unit": "class", "randomised": True, **members}],
    }


def test_an_assignment_without_a_declared_level_is_inferred_with_the_tolerance_of_agreement() -> (
    None
):
    # Ten classes of 20 rows, arm constant within each class but one row: 199
    # of the 200 rows have the most frequent value of their class, and
    # 199 x 100 >= 99 x 200, so the level is between_unit and the mixed class
    # is reported.
    classes = np.repeat([f"c{i:02d}" for i in range(1, 11)], 20)
    arm = np.repeat(["T", "C"] * 5, 20).astype(object)
    arm[6] = "C"
    data = pd.DataFrame({"y": np.arange(1.0, 201.0), "arm": arm, "class": classes})
    check = "assignment.constant_within_unit"
    found = assignment_findings(data, "y ~ arm + (1 | class)", class_declaration(), check)[0]
    values = assignment_values(found)
    assert values["level_source"] == "inferred_from_the_data"
    assert values["units"] == 10
    assert values["mixed_units"] == 1
    assert found["status"]["finding"]["value"] == "consequential"
    assert re.search(
        "1 of the 10 levels of 'class'.*inferred from the data", found["message"]["text"]
    )
    # Three miscoded rows leave 197 of 200, below the agreement, so the level
    # is within_unit and no check applies.
    data.loc[[26, 46], "arm"] = ["T", "C"]
    assert assignment_findings(data, "y ~ arm + (1 | class)", class_declaration(), check) == []


def design_df_expected(data: pd.DataFrame, formula: str, classes: list[str]) -> int:
    """The indicator columns of the classes that the sequential rule keeps after
    the fixed-effects columns."""
    matrices = design_matrices(formula_ir(formula, data=data), data)
    x = matrices["x"]
    indicators = (data["class"].to_numpy()[:, np.newaxis] == np.array(classes)).astype(float)
    kept = sequential_rule(np.asfortranarray(np.hstack((x, indicators))))
    return sum(kept[x.shape[1] :])


def test_design_df_equals_the_indicator_columns_that_the_sequential_rule_keeps() -> None:
    for seed in range(1, 5):
        rng = np.random.default_rng(seed)
        count = 12
        size = rng.integers(3, 6, count)
        names = [f"c{i:02d}" for i in range(1, count + 1)]
        # A class-level covariate with values that level means do not give
        # back exactly, and a pupil-level covariate.
        z = np.round(rng.uniform(size=count), 1) + 0.1
        n = int(size.sum())
        data = pd.DataFrame(
            {
                "y": np.arange(1.0, n + 1.0),
                "arm": np.repeat(["T", "C"] * 6, size),
                "school": np.repeat(np.repeat(["S1", "S2", "S3"], 4), size),
                "class": np.repeat(names, size),
                "z": np.repeat(z, size),
                "x": rng.normal(size=n),
            }
        )
        for formula in (
            "y ~ arm + (1 | class)",
            "y ~ arm + school + z + (1 | class)",
            "y ~ arm * z + x + (1 | class)",
        ):
            found = assignment_findings(
                data, formula, class_declaration(level="between_unit"), "assignment.design_df"
            )[0]
            expected = design_df_expected(data, formula, names)
            assert assignment_values(found)["design_df"] == expected, formula


def test_design_df_does_not_change_when_a_constant_is_added_to_a_column() -> None:
    # Sessions of 30 classes on different days, each up to 60 seconds long,
    # in seconds from 0 and from 1.7e9, near the Unix time of 2023.
    rng = np.random.default_rng(2)
    names = [f"c{i:02d}" for i in range(1, 31)]
    classes = np.repeat(names, 8)
    seconds = np.repeat(rng.permutation(30), 8) * 86400 + rng.uniform(0, 60, 240)
    for origin in (0.0, 1.7e9):
        data = pd.DataFrame(
            {
                "y": np.arange(1.0, 241.0),
                "arm": np.repeat(["T", "C"] * 15, 8),
                "class": classes,
                "time": origin + seconds,
            }
        )
        for formula in ("y ~ arm + time + (1 | class)", "y ~ arm * time + (1 | class)"):
            found = assignment_findings(
                data, formula, class_declaration(level="between_unit"), "assignment.design_df"
            )[0]
            label = f"{origin} {formula}"
            assert assignment_values(found)["design_df"] == design_df_expected(
                data, formula, names
            ), label
            assert assignment_values(found)["design_df"] == 28, label


def test_members_of_the_assignment_block_that_provenance_inferred_lists_count_as_absent() -> None:
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 13.0),
            "arm": np.repeat(["T", "C", "T", "C"], 3),
            "school": np.repeat(["S1", "S2"], 6),
            "class": np.repeat(["c1", "c2", "c3", "c4"], 3),
        }
    )
    declaration = class_declaration(level="between_unit", blocks=["school"])
    declaration["units"].insert(0, {"name": "school", "columns": ["school"], "role": "cluster"})

    def findings(
        check: str, inferred: list[str], data: pd.DataFrame = data, formula: str = ""
    ) -> list[dict[str, Any]]:
        declared = copy.deepcopy(declaration)
        if inferred:
            declared["provenance"] = {"inferred": inferred}
        return assignment_findings(data, formula or "y ~ arm + (1 | school)", declared, check)

    # The block as a whole: no check is available.
    found = findings("assignment.design_df", ["/assignment"])[0]
    assert found["status"]["availability"] == {
        "value": "not_available",
        "reason": "declaration_missing",
        "detail": "/assignment",
    }
    # The level is inferred from the data.
    found = findings("assignment.constant_within_unit", ["/assignment/0/level"])[0]
    assert assignment_values(found)["level_source"] == "inferred_from_the_data"
    # Without randomised, assignment.unit_in_random_part does not apply.
    assert len(findings("assignment.unit_in_random_part", [])) == 1
    assert findings("assignment.unit_in_random_part", ["/assignment/0/randomised"]) == []
    # Without blocks, no block is missing.
    found = findings("assignment.design_df", [])[0]
    assert assignment_values(found)["missing_blocks"] == ["school"]
    found = findings("assignment.design_df", ["/assignment/0/blocks"])[0]
    assert assignment_values(found)["missing_blocks"] == []
    # An entry whose column or unit is inferred, or whose unit counts as
    # absent, counts as absent, and a block whose every entry counts as absent
    # makes the checks not available.
    for inferred in (
        "/assignment/0",
        "/assignment/0/column",
        "/assignment/0/unit",
        "/units/1",
        "/units/1/columns/0",
    ):
        found = findings("assignment.unit_in_random_part", [inferred])[0]
        assert found["status"]["availability"]["detail"] == "/assignment", inferred
    data = data.assign(arm2=data["arm"])
    declaration["assignment"].append(
        {"column": "arm2", "unit": "class", "randomised": True, "level": "between_unit"}
    )
    found = findings("assignment.constant_within_unit", ["/assignment/0/unit"], data)
    assert len(found) == 1
    assert found[0]["scope"]["column"] == "arm2"
    # An entry whose unit counts as absent yields no finding, and its column
    # holds no labels unless something else makes it a label column.
    declaration["assignment"][1]["unit"] = "school"
    found = findings("assignment.constant_within_unit", ["/units/0"], data)
    assert len(found) == 1
    assert found[0]["scope"]["column"] == "arm"
    formula = "y ~ 1 + (1 | class)"
    labels = findings("labels.unicode_forms", [], data, formula)
    assert "arm2" in [f["scope"]["column"] for f in labels]
    labels = findings("labels.unicode_forms", ["/units/0"], data, formula)
    assert "arm2" not in [f["scope"]["column"] for f in labels]


def test_unit_in_random_part_compares_partitions_over_the_rows_of_the_assignment() -> None:
    # The random intercept is on 'room', which divides the rows like the
    # classes except in a row whose arm is missing, which is not a row of the
    # assignment.
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 10.0),
            "arm": pd.Series(["T", "T", None, "C", "C", "C", "T", "T", "T"], dtype=object),
            "class": np.repeat(["c1", "c2", "c3"], 3),
            "room": ["r1", "r1", "r9", "r2", "r2", "r2", "r3", "r3", "r3"],
        }
    )
    found = assignment_findings(
        data,
        "y ~ (1 | room)",
        class_declaration(level="between_unit"),
        "assignment.unit_in_random_part",
    )[0]
    assert assignment_values(found)["coverage"] == "present"
    assert found["support"]["rows"]["value"] == 9
