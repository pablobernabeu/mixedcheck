"""The design checks, in the parts that the audit corpus cannot reach: the
generalised variance inflation factor against its definition as a ratio of
determinants on designs of more terms and levels, the condition number and
standard deviations against numpy, these values at extreme magnitudes, empty
cells of three factors, the estimands that /provenance/inferred marks and the
residuals of the sequential rule."""

from __future__ import annotations

import math
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

from mixedcheck import audit
from mixedcheck._checks_design import column_sd
from mixedcheck._design import sequential_residuals, sequential_rule


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def design_findings(
    data: pd.DataFrame, formula: str, checks: tuple[str, ...], **arguments: Any
) -> list[dict[str, Any]]:
    """The findings of some checks for an audit in internal mode."""
    results = audit(data, formula, privacy="internal", key=AUDIT_KEY, **arguments)
    return [f for f in results.document["findings"] if f["check"] in checks]


def design_values(finding: dict[str, Any]) -> dict[str, Any]:
    return {name: statistic.get("value") for name, statistic in finding["statistics"].items()}


def collinear_data(seed: int) -> pd.DataFrame:
    """A design of 60 rows with two correlated numeric predictors, a factor of
    four levels and a factor of three levels."""
    rng = np.random.default_rng(seed)
    n = 60
    a = rng.choice(["A1", "A2", "A3", "A4"], n)
    b = rng.choice(["B1", "B2", "B3"], n)
    x1 = rng.normal(size=n) + (a == "A2") * 1.5
    x2 = 0.7 * x1 + rng.normal(scale=0.6, size=n) + (b == "B3")
    return pd.DataFrame({"y": rng.normal(size=n), "x1": x1, "x2": x2, "a": a, "b": b})


def indicators(values: Any, reference: str) -> tuple[np.ndarray[Any, Any], list[str]]:
    """The treatment-coded columns of a factor, without its reference level."""
    levels = sorted(set(values) - {reference})
    columns = np.column_stack([np.asarray(values) == level for level in levels]).astype(float)
    return columns, levels


def test_collinearity_gives_the_ratio_of_determinants_for_each_main_effect_term() -> None:
    for seed in (1, 2, 3):
        data = collinear_data(seed)
        findings = design_findings(data, "y ~ x1 + a + x2 + b + x1:b", ("design.collinearity",))
        assert [f["scope"]["term"] for f in findings] == ["a", "b", "x1", "x2"]
        # The definition with the columns of the main-effect terms coded by
        # treatment contrasts and numpy's correlations and determinants.
        a, a_levels = indicators(data["a"], "A1")
        b, b_levels = indicators(data["b"], "B1")
        columns = np.column_stack((data["x1"], a, data["x2"], b))
        owner = np.array(["x1"] + ["a"] * len(a_levels) + ["x2"] + ["b"] * len(b_levels))
        r = np.corrcoef(columns, rowvar=False)
        for finding in findings:
            own = owner == finding["scope"]["term"]
            expected = (
                np.linalg.det(r[np.ix_(own, own)])
                * np.linalg.det(r[np.ix_(~own, ~own)])
                / np.linalg.det(r)
            )
            values = design_values(finding)
            assert values["gvif"] == pytest.approx(expected, rel=1e-10)
            assert values["df"] == int(own.sum())
            assert values["gvif_per_df"] == pytest.approx(expected ** (1 / own.sum()), rel=1e-10)


def test_collinearity_does_not_change_with_the_contrasts_or_the_order_of_the_terms() -> None:
    data = collinear_data(11)

    def value(formula: str, term: str, **arguments: Any) -> float:
        findings = design_findings(data, formula, ("design.collinearity",), **arguments)
        found = next(f for f in findings if f["scope"]["term"] == term)
        return float(design_values(found)["gvif"])

    reference = value("y ~ x1 + a + x2", "a")
    coding = {"a": {"contrast": "sum"}}
    assert value("y ~ x1 + a + x2", "a", coding=coding) == pytest.approx(reference, rel=1e-12)
    assert value("y ~ a + x2 + x1", "a") == pytest.approx(reference, rel=1e-12)
    assert value("y ~ 0 + x1 + a + x2", "a") == pytest.approx(reference, rel=1e-12)


def test_scale_disparity_agrees_with_numpys_standard_deviations_and_condition_number() -> None:
    rng = np.random.default_rng(3)
    data = pd.DataFrame(
        {
            "y": rng.normal(size=50),
            "x1": rng.normal(scale=20, size=50),
            "x2": rng.uniform(size=50) / 50,
            "d": rng.integers(0, 2, 50).astype(float),
            "a": np.tile(["A", "B"], 25),
        }
    )
    found = design_findings(data, "y ~ x1 * x2 + d + a", ("design.scale_disparity",))[0]
    values = design_values(found)
    assert values["scaled_columns"] == ["x1", "x2", "x1:x2"]
    deviations = [
        float(np.std(data["x1"], ddof=1)),
        float(np.std(data["x2"], ddof=1)),
        float(np.std(data["x1"] * data["x2"], ddof=1)),
    ]
    assert values["sd_largest"] == pytest.approx(max(deviations), rel=1e-12)
    assert values["sd_smallest"] == pytest.approx(min(deviations), rel=1e-12)
    assert values["sd_ratio"] == pytest.approx(max(deviations) / min(deviations), rel=1e-12)
    x = np.column_stack(
        (
            np.ones(50),
            data["x1"],
            data["x2"],
            data["d"],
            data["a"] == "B",
            data["x1"] * data["x2"],
        )
    ).astype(float)
    x = x / np.sqrt(np.sum(x**2, axis=0))
    assert values["condition_number"] == pytest.approx(np.linalg.cond(x), rel=1e-10)
    assert found["message"]["id"] == "disparate"


def test_collinearity_and_scale_disparity_hold_at_extreme_magnitudes() -> None:
    # Each column is divided by its largest absolute value before any sum or
    # product, so that columns near 1e300 or 1e-300 give the values of the
    # same data at unit scale, multiplied by the scale for the standard
    # deviations.
    rng = np.random.default_rng(21)
    z = rng.normal(size=40)
    base = pd.DataFrame(
        {
            "y": rng.normal(size=40),
            "x": z + rng.normal(size=40),
            "z": z,
            "g": np.tile([f"g{i}" for i in range(1, 9)], 5),
        }
    )
    checks = ("design.collinearity", "design.scale_disparity")

    def findings(data: pd.DataFrame) -> list[dict[str, Any]]:
        return [design_values(f) for f in design_findings(data, "y ~ x + z + (1 | g)", checks)]

    reference = findings(base)
    for scale in (1e-300, 1e-100, 1e100, 1e300):
        data = base.copy()
        data["x"] = base["x"] * scale
        found = findings(data)
        for i in range(2):
            assert found[i]["gvif"] == pytest.approx(reference[i]["gvif"], rel=1e-12), (scale, i)
        assert found[2]["condition_number"] == pytest.approx(
            reference[2]["condition_number"], rel=1e-12
        )
        deviation = found[2]["sd_largest"] if scale > 1 else found[2]["sd_smallest"]
        assert deviation / scale == pytest.approx(column_sd(base["x"].to_numpy()), rel=1e-12)


def test_column_sd_is_exactly_0_for_equal_values_and_scales_before_squaring() -> None:
    assert column_sd(np.array([5.0, 5.0, 5.0])) == 0.0
    assert column_sd(np.array([-1000.0, 0.0, 1000.0])) == 1000.0
    assert column_sd(np.array([1e308, -1e308])) == pytest.approx(math.sqrt(2) * 1e308)
    assert column_sd(np.array([3e-320, -3e-320])) > 0


def test_column_sd_sums_the_squared_differences_exactly() -> None:
    # The squares 2^-64 of the last 2^16 values are each below half a unit of
    # the last place of 2 in a long double, so that R's sum() would lose them
    # and give 2, whereas their exact sum adds 2^-48 and moves the result by 6
    # units of the last place.
    t = 2.0**-32
    x = np.array([1.0, -1.0] + [t, -t] * 2**15)
    n = len(x)
    assert column_sd(x) == math.sqrt((2 + 2.0**-48) / (n - 1))
    assert column_sd(x) != math.sqrt(2 / (n - 1))


def test_rank_deficiency_counts_empty_cells_of_factors_only() -> None:
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 13),
            "a": np.repeat(["A1", "A2"], 6),
            "b": np.tile(["B1", "B2", "B3"], 4),
            "c": np.tile(["C1", "C1", "C2"], 4),
            "x": [1.0, 4, 2, 5, 3, 6, 2, 7, 1, 8, 9, 3],
        }
    )
    found = design_findings(data, "y ~ a * b * c + b:x", ("design.rank_deficiency",))[0]
    values = design_values(found)

    # a:b has every cell. a:c and b:c lack A?:C2 with B1 or B2 and B3 with
    # C1, and a:b:c sums those of all three factors. b:x is left out.
    def levels(*columns: str) -> int:
        return len(set(zip(*(data[c] for c in columns), strict=True)))

    expected = (
        (2 * 3 - levels("a", "b"))
        + (2 * 2 - levels("a", "c"))
        + (3 * 2 - levels("b", "c"))
        + (2 * 3 * 2 - levels("a", "b", "c"))
    )
    assert values["empty_cells"] == expected
    assert expected > 0


def test_an_estimand_that_provenance_inferred_lists_counts_as_absent() -> None:
    data = pd.DataFrame(
        {
            "y": [1.2, 2.9, 3.1, 4.8, 4.4, 6.5],
            "x1": [1.0, 2, 3, 4, 5, 6],
            "x2": [2.0, 0, 1, 3, 1, 2],
            "x3": [3.0, 2, 4, 7, 6, 8],
        }
    )
    checks = ("design.rank_deficiency",)
    declaration: dict[str, Any] = {
        "vocabulary": "0.1.0",
        "estimands": [{"id": "slope", "term": "x1", "kind": "association"}],
    }
    formula = "y ~ x1 + x2 + x3"
    found = design_findings(data, formula, checks, declaration=declaration)[0]
    assert found["message"]["id"] == "nonfocal"
    # Without the estimand, every term is focal and x3 makes it consequential.
    declaration["provenance"] = {"inferred": ["/estimands/0"]}
    found = design_findings(data, formula, checks, declaration=declaration)[0]
    assert found["message"]["id"] == "focal"
    assert design_values(found)["focal_dropped"] is True
    # An inferred focal member counts as absent, so the estimand is focal.
    declaration["estimands"][0]["term"] = "x3"
    declaration["estimands"][0]["focal"] = False
    declaration["provenance"] = {"inferred": ["/estimands/0/focal"]}
    found = design_findings(data, formula, checks, declaration=declaration)[0]
    assert found["message"]["id"] == "focal"


def test_the_residuals_of_the_sequential_rule_are_the_norms_it_compares() -> None:
    rng = np.random.default_rng(5)
    x = np.column_stack(
        (rng.normal(size=30), rng.normal(size=30), np.zeros(30), rng.normal(size=30))
    )
    x = np.asfortranarray(np.column_stack((x, x[:, 0] + 2 * x[:, 1])))
    kept, residual = sequential_residuals(x)
    assert kept == sequential_rule(x)
    assert kept == [True, True, False, True, False]
    assert residual[2] == 0
    scaled = x[:, 1] / np.max(np.abs(x[:, 1]))
    first = x[:, 0] / math.sqrt(float(np.sum(x[:, 0] ** 2)))
    expected = math.sqrt(float(np.sum((scaled - np.sum(scaled * first) * first) ** 2)))
    assert residual[1] == pytest.approx(expected, rel=1e-12)
    assert residual[4] < 1e-12
