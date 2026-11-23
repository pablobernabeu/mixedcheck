"""The identifiability checks, in the parts that the audit corpus cannot reach:
the Gram matrix against its definition on dense matrices, at extreme
magnitudes, with weights that differ by many orders of magnitude and in chunks
of levels, the proximity band of rank_tolerance and the bounds on rounding
errors that make a value near it, with fixed-effects columns far from
orthogonal and on confounded designs that stay clear, a level of many rows
beside a level of one row, the limits of max_z_columns and max_parameters, the
budget against the literal sequential rule, the rank of each level and the
smallest eigenvalue of 1e5 rows against the value of the R package.
"""

from __future__ import annotations

import copy
import math
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY, reals_match

from mixedcheck import _checks as machinery
from mixedcheck import audit, design_matrices, formula_ir
from mixedcheck._checks_identifiability import (
    check_identifiability_gram_rank,
    covariance_bases,
    gram_of_bases,
    scaled_random_columns,
)
from mixedcheck._commitments import run_data
from mixedcheck._design import design_build, design_model, sequential_rule
from mixedcheck._formula_ir import build_formula_ir, coding_input
from mixedcheck._registry import registry_entry


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def identifiability_finding(
    data: pd.DataFrame, formula: str, check: str, **arguments: Any
) -> dict[str, Any]:
    """The first finding of a check for an audit in internal mode."""
    results = audit(data, formula, privacy="internal", key=AUDIT_KEY, **arguments)
    return next(f for f in results.document["findings"] if f["check"] == check)


def values_of(finding: dict[str, Any]) -> dict[str, Any]:
    return {name: statistic.get("value") for name, statistic in finding["statistics"].items()}


def gram_rank_run(
    data: pd.DataFrame, formula: str, weights: str | None = None, family_class: str = "gaussian"
) -> machinery.Run:
    """The run of a model at T0 without audit(), for designs larger than a run
    of all the checks would allow in a test."""
    table = run_data(data, None).table
    ir = build_formula_ir(formula, None, table, coding_input(None), weights, [])
    model = design_model(ir, table, analysis=False)
    return machinery.new_run(
        None, table, ir, family_class, "T0", model, design_build(ir, model, table)
    )


def equal(x: float, y: float, tolerance: float) -> bool:
    """Equality within a tolerance as R's all.equal() takes it: relative to y,
    or absolute when y is smaller than the tolerance."""
    if abs(y) > tolerance:
        return abs(x - y) <= tolerance * abs(y)
    return abs(x - y) <= tolerance


def gram_by_definition(
    data: pd.DataFrame, formula: str, weights: str | None = None, gaussian: bool = True
) -> dict[str, Any]:
    """The Gram matrix of identifiability.gram_rank by its definition, with P,
    D, Z, the bases A_k and their parts A_kL in the levels as dense matrices,
    and its rank and smallest eigenvalue as the entry decides them."""
    ir = formula_ir(formula, data=data, weights=weights)
    m = design_matrices(ir, data)
    z = m["z"].toarray()
    x = m["x"][:, [name not in m["x_dropped"] for name in m["x_columns"]]]
    n = z.shape[0]
    p = np.eye(n) - x @ np.linalg.solve(x.T @ x, x.T)
    d = np.eye(n) if weights is None else np.diag(1 / m["weights"])
    w = z.T @ p @ z if gaussian else z.T @ z
    w0 = z.T @ z
    columns_of_z = z.shape[1]
    term_of = m["z_columns"]["term"].to_numpy()
    parts = []
    for t, term in enumerate(ir["random"]):
        q = len(term["columns"])
        positions = np.flatnonzero(term_of == t)
        columns = [positions[c::q] for c in range(q)]
        for j in range(q):
            for k in range(j, q):
                levels = []
                for level in range(len(columns[j])):
                    a = np.zeros((columns_of_z, columns_of_z))
                    a[columns[j][level], columns[k][level]] = 1
                    a[columns[k][level], columns[j][level]] = 1
                    levels.append(a)
                parts.append(levels)
    bases = [sum(levels) for levels in parts]
    size = len(bases)
    gram = np.array(
        [[np.trace(bases[k] @ w @ bases[m_] @ w) for m_ in range(size)] for k in range(size)]
    )
    vanishing = []
    for k, levels in enumerate(parts):
        projected = np.array([np.trace(a @ w @ a @ w) for a in levels])
        unprojected = np.array([np.trace(a @ w0 @ a @ w0) for a in levels])
        held = unprojected > 0
        vanishing.append(
            not held.any()
            or (projected[held] / unprojected[held]).max() <= 1e-10
            or gram[k, k] <= 1e-10 * projected.sum()
        )
    if gaussian:
        cross = np.array([np.trace(a @ z.T @ p @ d @ p @ z) for a in bases])
        own = np.trace(p @ d @ p @ d)
        gram = np.block([[gram, cross[:, None]], [cross[None, :], np.array([[own]])]])
        vanishing.append(x.shape[1] == n)
    gone = np.array(vanishing)
    others = np.flatnonzero(~gone)
    diagonal = np.diag(gram)[others]
    scaled = gram[np.ix_(others, others)] / np.sqrt(np.outer(diagonal, diagonal))
    values = np.linalg.eigvalsh(scaled)
    return {
        "rank": len(gram) - int(gone.sum()) - int((values <= 1e-10).sum()),
        "smallest": float(values.min()),
        "vanishing": int(gone.sum()),
    }


def test_gram_rank_agrees_with_the_gram_matrix_of_its_definition() -> None:
    rng = np.random.default_rng(7)
    formulas = [
        "y ~ x + (1 + x | g)",
        "y ~ x + cond + (1 | g) + (0 + z | h)",
        "y ~ 1 + (1 + x + z | g) + (1 | h)",
        "y ~ x + (1 | g) + (1 | g:h)",
        "y ~ cond + (1 + cond | g)",
        "y ~ g + (1 + x | g)",
    ]
    for formula in formulas:
        n = 24
        data = pd.DataFrame(
            {
                "y": rng.normal(size=n),
                "x": np.round(rng.normal(size=n), 1),
                "z": np.round(rng.uniform(size=n), 1),
                "cond": rng.choice(["A", "B", "C"], n),
                "g": rng.choice([f"g{i}" for i in range(1, 5)], n),
                "h": rng.choice([f"h{i}" for i in range(1, 4)], n),
                "w": rng.choice([0.5, 1, 2, 4], n),
            }
        )
        settings: list[dict[str, Any]] = [{}, {"weights": "w"}, {"family": "poisson"}]
        for setting in settings:
            found = identifiability_finding(data, formula, "identifiability.gram_rank", **setting)
            expected = gram_by_definition(
                data, formula, setting.get("weights"), gaussian="family" not in setting
            )
            label = f"{formula} {list(setting)}"
            values = values_of(found)
            assert values["rank"] == expected["rank"], label
            assert len(values["vanishing_parameters"]) == expected["vanishing"], label
            assert equal(values["smallest_eigenvalue"], expected["smallest"], 1e-9), label


def test_gram_rank_is_near_threshold_for_values_in_the_band_of_rank_tolerance() -> None:
    # Two slopes whose columns differ by eps make the smallest eigenvalue of C
    # of the order of eps^2.
    x = [1.0, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4]
    noise = np.array([1.0, -1, 1, -1, -1, 1, -1, 1, 1, 1, -1, -1])

    def slopes(eps: float) -> dict[str, Any]:
        data = pd.DataFrame(
            {
                "y": np.arange(1.0, 13),
                "x": x,
                "x2": np.array(x) + eps * noise,
                "g": np.repeat(["a", "b", "c"], 4),
            }
        )
        return identifiability_finding(
            data,
            "y ~ 1 + (0 + x | g) + (0 + x2 | g)",
            "identifiability.gram_rank",
            family="poisson",
        )

    found = slopes(3e-5)
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert values_of(found)["verdict"] == "necessary_condition_met"
    found = slopes(1e-5)
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert values_of(found)["verdict"] == "not_identified"
    assert slopes(1e-3)["status"]["threshold_proximity"]["value"] == "clear"
    found = slopes(1e-6)
    assert found["status"]["threshold_proximity"]["value"] == "clear"
    assert values_of(found)["confounded_parameters"] == ["0 + x | g: var(x)", "0 + x2 | g: var(x2)"]


def test_gram_rank_is_near_threshold_for_a_largest_level_ratio_in_the_band() -> None:
    # The fixed part g * x holds x in every level, so that the column of
    # x2 = x + eps * noise in a level keeps eps * noise, orthogonal to X, and
    # its level ratio is (eps^2 * 4 / 30)^2 in each level.
    x = np.tile([1.0, 2, 3, 4], 3)
    noise = np.tile([1.0, -1, -1, 1], 3)

    def slope(eps: float) -> dict[str, Any]:
        data = pd.DataFrame(
            {
                "y": np.arange(1.0, 13),
                "x": x,
                "x2": x + eps * noise,
                "g": np.repeat(["a", "b", "c"], 4),
            }
        )
        return identifiability_finding(
            data, "y ~ g * x + (0 + x2 | g)", "identifiability.gram_rank"
        )

    found = slope(5e-3)
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert values_of(found)["vanishing_parameters"] == ["0 + x2 | g: var(x2)"]
    found = slope(1e-2)
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert values_of(found)["verdict"] == "identified"
    found = slope(2e-2)
    assert found["status"]["threshold_proximity"]["value"] == "clear"
    assert values_of(found)["verdict"] == "identified"
    found = slope(1e-3)
    assert found["status"]["threshold_proximity"]["value"] == "clear"
    assert values_of(found)["verdict"] == "not_identified"


def test_gram_rank_keeps_a_variance_that_a_level_of_many_rows_would_hide() -> None:
    # With one level of n - 1 rows and one of one row beside an intercept,
    # M_kk divided by tr(A_k Z'Z A_k Z'Z) is about 4 / n^2, 4.4e-11 here,
    # whereas the level of one row has a level ratio of about 1.
    n = 300_000
    data = pd.DataFrame({"y": np.zeros(n), "g": ["big"] * (n - 1) + ["small"]})
    run = gram_rank_run(data, "y ~ 1 + (1 | g)")
    found = machinery.run_check(run, registry_entry("identifiability.gram_rank"))[0]
    assert found.values["verdict"] == "identified"
    assert found.status["threshold_proximity"]["value"] == "clear"
    assert found.values["vanishing_parameters"] == []


def compared_with_tolerance(run: machinery.Run) -> tuple[Any, machinery.CheckElement]:
    entry = registry_entry("identifiability.gram_rank")
    result = check_identifiability_gram_rank(run, entry, [{}])
    assert isinstance(result, list)
    element = result[0]
    assert element is not None
    return element.proximity["rank_tolerance"], element


@pytest.mark.parametrize("n", [1000, 100_000, 700_000])
def test_gram_rank_bounds_the_rounding_error_of_every_value_it_compares(n: int) -> None:
    # One level of n - 1 rows and one of one row beside the fixed part 1 + x,
    # with x = 1, -1, 1, ... and n even, give PZ of rank 1 and W = a vv' with
    # a = 1 - 2 / n, so that every largest level ratio is a^2, every
    # cancellation ratio is 2 and C has the eigenvalues 2 + s, 2 - s, 0 and 0
    # for s = sqrt(1 + 3 / (n - 2)). The elements of W cancel to within about
    # 2^-52 n^2 / 5, so that an eigenvalue of 0 is computed with an error of
    # the order of 1e-11, 1e-7 and 1e-5 for n of 1e3, 1e5 and 7e5, depending
    # on the BLAS, where each value lies within its bound and the bounds make
    # the finding near_threshold. The bounds leave the rank undecided at
    # every n, so the verdict, which another orthonormal basis or BLAS can
    # change from 1e5, is tested at 1e3 alone, where the errors lie well below
    # the tolerance.
    entry = registry_entry("identifiability.gram_rank")
    data = pd.DataFrame(
        {
            "y": np.zeros(n),
            "x": np.resize([1.0, -1.0], n),
            "g": ["big"] * (n - 1) + ["small"],
        }
    )
    run = gram_rank_run(data, "y ~ x + (1 + x | g)")
    compared, element = compared_with_tolerance(run)
    a = 1 - 2 / n
    s = math.sqrt(1 + 3 / (n - 2))
    exact = np.array([a**2] * 3 + [2.0] * 3 + [2 + s, 2 - s, 0, 0])
    values = np.asarray(compared.values)
    assert len(values) == len(exact)
    assert bool((np.abs(values - exact) <= np.asarray(compared.bound)).all()), n
    if n == 1000:
        assert element.statistics["verdict"] == "not_identified"
    assert machinery.finding_near_threshold(entry, element.statistics, element), n


def test_the_smallest_eigenvalue_of_1e5_rows_matches_that_of_the_r_package() -> None:
    # x alternates near 1 and -1 and x2 = x + 2e-4 v, from a numerical review
    # of M2b-3. The Gram matrix sums 1e5 rows, so that the smallest
    # eigenvalue of C, about 4.13744e-5, carries a rounding error of about
    # 6.2e-10 in both packages, against the value of its definition in
    # 30-digit arithmetic, and the two values differed by 3.7e-12, beyond the
    # general tolerance of conventions.md and within its tolerance for this
    # statistic, relative to the norm of C. The finding is clear in both.
    n = 100_000
    i = np.arange(1, n + 1)
    u = (i * 7919) % 10007 / 10007 - 0.5
    v = (i * 31337) % 10009 / 10009 - 0.5
    x = np.where(i % 2 == 1, 1.0, -1.0) + 0.02 * u
    data = pd.DataFrame(
        {
            "y": np.zeros(n),
            "x": x,
            "x2": x + 2e-4 * v,
            "g": [f"g{k}" if k <= 5 else "g0" for k in i],
        }
    )
    found = identifiability_finding(
        data, "y ~ x + (1 + x | g) + (0 + x2 | g)", "identifiability.gram_rank"
    )
    value = found["statistics"]["smallest_eigenvalue"]["value"]
    assert found["status"]["threshold_proximity"]["value"] == "clear"
    assert abs(value - 4.1374441250249373e-05) <= 1e-9
    r_value = 4.1373823032930801e-05
    assert reals_match(value, r_value, "identifiability.gram_rank", "smallest_eigenvalue")


def test_gram_rank_bounds_the_error_of_a_basis_of_x_that_is_far_from_orthogonal() -> None:
    # x2 = x1 + 2^-22 w, exact in doubles, which the sequential rule keeps
    # with a residual ratio of about 1.4e-7, has the span of 1, x1 and w, so
    # that y ~ x1 + w gives the same exact values with a well-conditioned
    # basis. The rounding of the basis of x1 and x2 changes the level ratios
    # by 5e-12 to 1e-10, depending on the platform and its BLAS, far
    # more than the sums over the rows explain.
    rng = np.random.default_rng(3)
    n = 100
    w = np.round(rng.uniform(-1, 1, n) * 1024) / 1024
    x1 = np.resize([1.0, -1.0], n)
    data = pd.DataFrame(
        {"y": 0.0, "x1": x1, "x2": x1 + w * 2.0**-22, "w": w, "g": ["big"] * (n - 1) + ["small"]}
    )
    run = gram_rank_run(data, "y ~ x1 + x2 + (1 + w | g)")
    assert all(run.x_kept)
    found, _ = compared_with_tolerance(run)
    reference, _ = compared_with_tolerance(gram_rank_run(data, "y ~ x1 + w + (1 + w | g)"))
    assert len(found.values) == len(reference.values)
    error = np.abs(np.asarray(found.values) - np.asarray(reference.values))
    assert error.max() > 1e-12
    assert bool((error <= np.asarray(found.bound) + np.asarray(reference.bound)).all())


def test_gram_rank_leaves_exactly_confounded_designs_of_1000_rows_clear() -> None:
    # An intercept for each row beside the residual, a factor and a copy of it
    # with other labels, and a slope of two values with two rows in each level
    # confound parameters exactly. Their eigenvalues of 0 are computed within
    # about 1e-15, and their bounds of about 5e-12 decide the rank.
    rng = np.random.default_rng(11)
    entry = registry_entry("identifiability.gram_rank")
    n = 1000
    pairs = np.repeat(np.arange(1, n // 2 + 1), 2)
    data = pd.DataFrame(
        {
            "y": 0.0,
            "x": rng.normal(size=n),
            "slope": np.resize([0.0, 1.0], n),
            "g": [f"g{i:02d}" for i in np.resize(np.arange(1, 11), n)],
            "obs": [f"o{i:04d}" for i in range(1, n + 1)],
            "pair": [f"p{i:03d}" for i in pairs],
            "copy": [f"c{i:03d}" for i in pairs],
        }
    )
    for formula in (
        "y ~ x + (1 | g) + (1 | obs)",
        "y ~ x + (1 | pair) + (1 | copy)",
        "y ~ slope + (1 + slope | pair)",
    ):
        found = machinery.run_check(gram_rank_run(data, formula), entry)[0]
        assert found.values["verdict"] == "not_identified", formula
        assert found.status["threshold_proximity"]["value"] == "clear", formula


def test_a_value_is_near_rank_tolerance_in_its_band_or_within_its_bound_of_the_tolerance() -> None:
    entry = registry_entry("identifiability.gram_rank")

    def near(value: float, bound: float) -> bool:
        element = machinery.check_element(
            {}, proximity={"rank_tolerance": machinery.compared_values([value], [bound])}
        )
        return machinery.finding_near_threshold(entry, {}, element)

    assert not near(1e-7, 0)
    assert near(1e-7, 1e-7)
    assert not near(1e-7, 9e-8)
    assert not near(1e-13, 0)
    assert not near(-1e-13, 1e-11)
    assert near(-1e-13, 1e-10)
    assert not near(1.7e-9, 7e-10)
    assert near(5e-10, 0)
    assert near(2e-11, 0)
    assert near(1, math.inf)


def test_gram_rank_keeps_the_residual_for_weights_that_differ_by_many_orders_of_magnitude() -> None:
    # f isolates the first row, which P takes to 0, and gives it the smallest
    # weight, so that D = diag(m / w) holds 1 for it and the pattern of the
    # other rows divided by the ratio. C does not depend on the ratio, and the
    # residual has n - rank(X) = 4 degrees of freedom. tr(PDPD) / tr(DD) falls
    # below rank_tolerance from a ratio of about 1e6, and tr(PDPD) =
    # sum(d^2) - 2 sum(h d^2) + ||Q'DQ||^2 cancels to rounding error from
    # about 1e8.
    entry = registry_entry("identifiability.gram_rank")
    pattern = np.array([1, 1.5, 2, 1, 3, 1.2, 2.5])
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 8),
            "f": ["iso", "A", "A", "A", "B", "B", "B"],
            "g": ["g1", "g1", "g2", "g3", "g1", "g2", "g3"],
            "w": pattern,
        }
    )
    expected = gram_by_definition(data, "y ~ f + (1 | g)", "w")
    assert expected["rank"] == 2
    for power in range(13):
        ratio = 10.0**power
        data["w"] = np.concatenate(([1.0], np.full(6, ratio))) * pattern
        found = machinery.run_check(gram_rank_run(data, "y ~ f + (1 | g)", "w"), entry)[0]
        label = f"ratio {ratio}"
        assert found.values["verdict"] == "identified", label
        assert found.status["threshold_proximity"]["value"] == "clear", label
        assert equal(found.values["smallest_eigenvalue"], expected["smallest"], 1e-9), label
    # The residual vanishes exactly when X has rank n, here with a level of f
    # for every row.
    data["f"] = list("abcdefg")
    found = machinery.run_check(gram_rank_run(data, "y ~ f + (1 | g)", "w"), entry)[0]
    assert found.values["vanishing_parameters"] == ["1 | g: var((Intercept))", "residual"]
    assert found.status["threshold_proximity"]["value"] == "clear"


def test_gram_rank_runs_up_to_max_z_columns_columns_of_z() -> None:
    data = pd.DataFrame({"y": np.arange(1.0, 7), "g": ["a", "a", "b", "b", "c", "c"]})
    run = gram_rank_run(data, "y ~ 1 + (1 | g)")
    entry = copy.deepcopy(registry_entry("identifiability.gram_rank"))
    entry["parameters"]["max_z_columns"]["value"] = "2"
    assert machinery.run_check(run, entry)[0].availability == {
        "value": "not_available",
        "reason": "too_large",
        "detail": "max_z_columns",
    }
    entry["parameters"]["max_z_columns"]["value"] = "3"
    assert machinery.run_check(run, entry)[0].available
    # A random term whose column is 0 in every row has a basis of 0, which
    # vanishes.
    data["z"] = 0.0
    found = identifiability_finding(
        data, "y ~ 1 + (1 | g) + (0 + z | g)", "identifiability.gram_rank", family="poisson"
    )
    assert values_of(found)["vanishing_parameters"] == ["0 + z | g: var(z)"]


def test_gram_rank_gives_the_same_verdict_at_extreme_magnitudes() -> None:
    # The columns of a random term and the inverse weights are divided by their
    # largest absolute values before any product, so that values near 1e300 or
    # 1e-300 give the findings of the same data at unit scale.
    rng = np.random.default_rng(20)
    base = pd.DataFrame(
        {
            "y": rng.normal(size=40),
            "x": rng.normal(size=40),
            "g": np.tile([f"g{i}" for i in range(1, 9)], 5),
            "w": np.tile([0.5, 1, 2, 4], 10),
        }
    )
    formula = "y ~ x + (1 + x | g)"
    expected = [
        values_of(identifiability_finding(base, formula, "identifiability.gram_rank", weights=w))
        for w in (None, "w")
    ]
    assert expected[0]["verdict"] == "identified"
    for scale in (1e-300, 1e-100, 1e100, 1e300):
        data = base.copy()
        data["x"] = base["x"] * scale
        data["w"] = base["w"] * scale
        for i, weights in enumerate((None, "w")):
            found = values_of(
                identifiability_finding(data, formula, "identifiability.gram_rank", weights=weights)
            )
            label = f"{scale} {weights}"
            assert found["verdict"] == "identified", label
            assert found["rank"] == 4, label
            assert equal(found["smallest_eigenvalue"], expected[i]["smallest_eigenvalue"], 1e-9), (
                label
            )


def test_gram_rank_sums_the_gram_matrix_over_chunks_of_levels() -> None:
    # Chunks of one or a few levels give the Gram matrix of a single chunk.
    rng = np.random.default_rng(5)
    n = 60
    data = pd.DataFrame(
        {
            "y": rng.normal(size=n),
            "x": rng.normal(size=n),
            "z": rng.normal(size=n),
            "g": rng.choice([f"g{i}" for i in range(1, 8)], n),
            "h": rng.choice([f"h{i}" for i in range(1, 6)], n),
        }
    )
    for formula in (
        "y ~ x + (1 + x | g) + (0 + z | h)",
        "y ~ x + (x | g) + (1 + z | h) + (1 | g:h)",
    ):
        for family_class in ("gaussian", "other"):
            run = gram_rank_run(data, formula, family_class=family_class)
            scaled = scaled_random_columns(run)
            zq = None
            if family_class == "gaussian":
                q = np.linalg.qr(run.x[:, np.flatnonzero(run.x_kept)])[0]
                zq = np.asarray(scaled.z.T @ q)
            bases = covariance_bases(run)
            whole = gram_of_bases(scaled, zq, bases)
            for chunk in (1, 7, 40):
                found = gram_of_bases(scaled, zq, bases, chunk=chunk)
                label = f"{formula} {chunk}"
                np.testing.assert_allclose(found.gram, whole.gram, rtol=1e-12, err_msg=label)
                np.testing.assert_allclose(found.largest, whole.largest, rtol=1e-12)
                np.testing.assert_allclose(found.level_sums, whole.level_sums, rtol=1e-12)
                for a, b in zip(found.traces, whole.traces, strict=True):
                    np.testing.assert_allclose(a, b, rtol=1e-12, atol=1e-12)


def test_gram_rank_is_not_available_above_max_parameters() -> None:
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 13),
            "x": [1.0, 4, 2, 5, 3, 6, 2, 1, 4, 3, 6, 5],
            "z": [1.0, 2, 3, 4, 5, 6, 6, 5, 4, 3, 2, 1],
            "g": np.tile(["a", "b", "c"], 4),
        }
    )
    run = gram_rank_run(data, "y ~ x + (1 + x + z | g)")
    entry = copy.deepcopy(registry_entry("identifiability.gram_rank"))
    entry["parameters"]["max_parameters"]["value"] = "5"
    assert machinery.run_check(run, entry)[0].availability == {
        "value": "not_available",
        "reason": "too_large",
        "detail": "max_parameters",
    }
    entry["parameters"]["max_parameters"]["value"] = "6"
    assert machinery.run_check(run, entry)[0].available
    entry["parameters"]["max_z_columns"]["value"] = "8"
    assert machinery.run_check(run, entry)[0].availability == {
        "value": "not_available",
        "reason": "too_large",
        "detail": "max_z_columns",
    }


def budget_by_indicators(data: pd.DataFrame, formula: str) -> dict[str, Any]:
    """The budget of identifiability.df_budget as the number of indicator
    columns of the levels of 'g' that the sequential rule keeps after the kept
    fixed-effects columns of the terms up to each term, which J - k + r, with
    r the rank within the levels (within_level_rank()), equals up to the
    tolerances, and the consuming terms that it gives."""
    ir = formula_ir(formula, data=data)
    m = design_matrices(ir, data)
    levels = sorted(set(data["g"]))
    indicators = (np.array(data["g"])[:, None] == np.array(levels)[None, :]).astype(np.float64)
    columns = np.array([column["term"] for column in ir["fixed"]["columns"]])
    kept = np.array([name not in m["x_dropped"] for name in m["x_columns"]])
    budgets = []
    for t in range(len(ir["fixed"]["terms"])):
        x = m["x"][:, (columns <= t) & kept]
        rule = sequential_rule(np.asfortranarray(np.hstack((x, indicators))))
        budgets.append(sum(rule[x.shape[1] :]))
    terms = [term["name"] for term in ir["fixed"]["terms"]]
    previous = [indicators.shape[1]] + budgets[:-1]
    return {
        "budget": budgets[-1],
        "consuming": [name for name, b, a in zip(terms, budgets, previous, strict=True) if b < a],
    }


def test_df_budget_equals_the_indicator_columns_that_the_sequential_rule_keeps() -> None:
    rng = np.random.default_rng(11)
    formulas = [
        "y ~ x + b + (1 | g)",
        "y ~ x + s + b + (1 | g)",
        "y ~ g + (1 | g)",
        "y ~ 0 + x + (1 | g)",
        "y ~ cond * b + (1 | g)",
        "y ~ s + x + (1 | g)",
    ]
    names = [f"g{i}" for i in range(1, 7)]
    for formula in formulas:
        n = 30
        g = rng.choice(names, n)
        level = dict(zip(names, np.round(rng.normal(size=6), 2), strict=True))
        data = pd.DataFrame(
            {
                "y": rng.normal(size=n),
                "x": np.round(rng.normal(size=n), 1),
                "b": [level[v] for v in g],
                "g": g,
                "cond": rng.choice(["A", "B"], n),
            }
        )
        data["s"] = data["b"] + data["x"]
        found = values_of(identifiability_finding(data, formula, "identifiability.df_budget"))
        expected = budget_by_indicators(data, formula)
        assert found["budget"] == expected["budget"], formula
        assert found["consuming_terms"] == expected["consuming"], formula


def test_df_budget_counts_no_rank_within_levels_for_a_column_constant_up_to_rounding() -> None:
    # wn differs from its level's value by one unit in the last place in some
    # rows, wn2 by about 1e-9 and wn3 by 1e-4 relative to its scale, which the
    # indicator columns do not absorb.
    rng = np.random.default_rng(6)
    n = 96
    data = pd.DataFrame(
        {
            "y": rng.normal(size=n),
            "g": np.repeat([f"g{i:02d}" for i in range(1, 13)], 8),
            "x": rng.normal(size=n),
        }
    )
    base = np.repeat(rng.normal(10, 3, 12), 8)
    f = rng.uniform(1, 3, n)
    data["wn"] = (base * f) / f
    data["wn2"] = base + rng.normal(scale=1e-9, size=n)
    data["wn3"] = base + rng.normal(scale=1e-3, size=n)
    assert bool((data["wn"] != base).any())
    for formula in (
        "y ~ wn + x + (1 | g)",
        "y ~ wn2 + x + (1 | g)",
        "y ~ x + wn3 + (1 | g)",
        "y ~ wn * x + (1 | g)",
    ):
        found = values_of(identifiability_finding(data, formula, "identifiability.df_budget"))
        expected = budget_by_indicators(data, formula)
        assert found["budget"] == expected["budget"], formula
        assert found["consuming_terms"] == expected["consuming"], formula
    budget = "identifiability.df_budget"
    assert values_of(identifiability_finding(data, "y ~ wn + x + (1 | g)", budget))["budget"] == 10
    assert values_of(identifiability_finding(data, "y ~ x + wn3 + (1 | g)", budget))["budget"] == 11


def test_df_budget_does_not_change_when_a_constant_is_added_to_a_column() -> None:
    # Times of 30 sessions on different days, each up to 60 seconds long, in
    # seconds from 0 and from 1.7e9, near the Unix time of 2023. The time
    # varies within every subject, alone and in the interaction, from either
    # origin.
    rng = np.random.default_rng(1)
    subject = np.repeat([f"s{i:02d}" for i in range(1, 31)], 8)
    day = np.repeat(rng.permutation(30), 8)
    seconds = day * 86400 + rng.uniform(0, 60, 240)
    base = pd.DataFrame(
        {"y": rng.normal(size=240), "cond": np.repeat(np.tile(["A", "B"], 15), 8), "g": subject}
    )
    check = "identifiability.df_budget"
    for origin in (0.0, 1.7e9):
        data = base.copy()
        data["time"] = origin + seconds
        for formula in (
            "y ~ cond + time + (1 | g)",
            "y ~ cond * time + (1 | g)",
            "y ~ 0 + time + cond + (1 | g)",
        ):
            found = values_of(identifiability_finding(data, formula, check))
            expected = budget_by_indicators(data, formula)
            label = f"{origin} {formula}"
            assert found["budget"] == expected["budget"], label
            assert found["consuming_terms"] == expected["consuming"], label
        found = values_of(identifiability_finding(data, "y ~ cond * time + (1 | g)", check))
        assert found["budget"] == 28
    # Values near the largest double, whose differences within the levels
    # would overflow before the columns are scaled.
    data = base.copy()
    data["time"] = (2 * seconds / seconds.max() - 1) * 1.7e308
    found = values_of(identifiability_finding(data, "y ~ cond + time + (1 | g)", check))
    assert found["budget"] == 28


def test_the_rank_of_each_level_follows_the_sequential_rule() -> None:
    rng = np.random.default_rng(2)
    level = rng.integers(0, 12, 60)
    values = np.column_stack(
        (np.ones(60), np.round(rng.normal(size=60)), rng.integers(0, 2, 60).astype(np.float64))
    )
    values[level == 2, 1] = 5
    values[level == 3, 2] = 0

    def full(columns: list[int], difference: bool) -> list[bool]:
        found = []
        for lev in range(12):
            rows = values[level == lev][:, columns]
            if difference and len(rows):
                rows = rows - rows[0]
            found.append(sum(sequential_rule(np.asfortranarray(rows))) == len(columns))
        return found

    for columns in ([0], [1], [2], [0, 1], [1, 2], [0, 1, 2]):
        for difference in (False, True):
            found = machinery.levels_of_full_rank(
                values[:, columns], level, 12, difference=difference
            )
            assert found.tolist() == full(columns, difference), (columns, difference)
