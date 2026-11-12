"""The outcome checks, in the parts that the audit corpus cannot reach: how
they read the outcome, counts of binomial outcomes over many levels, decimal
bounds, and the solver of outcome.separation: its failure, which gives the
message no_solution, the verification of its solutions against the box, the
floor and the upper bound of their multipliers, the dual that solves every
program of the audit corpus, the program solved itself when its dual fails,
rounding residues, bounds whose face its floor moves fast, the 2,000 rows of
the review of registry 0.1.0, the outlier that compresses a margin below the
tolerances, the limits on the size of the programs and on the programs of
bounds, its time on 20,000 observations and tables of the structures of the
benchmark that chose the formulation."""

from __future__ import annotations

import time
from types import SimpleNamespace
from typing import Any

import numpy as np
import pandas as pd
import pytest
import scipy
from audit_helpers import AUDIT_KEY, run_audit
from corpus_helpers import corpus_cases

from mixedcheck import _checks_outcome, audit
from mixedcheck._checks import outcome_reads_logged, outcome_values, parameter_value
from mixedcheck._registry import registry_entry


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def outcome_results(data: pd.DataFrame, formula: str, tier: str = "T1", **arguments: Any) -> Any:
    """The results of an audit in internal mode at a tier."""
    return audit(
        data,
        formula,
        outcome_access=tier,
        reason="Test.",
        exploratory=tier == "T2",
        privacy="internal",
        key=AUDIT_KEY,
        **arguments,
    )


def outcome_findings(
    data: pd.DataFrame, formula: str, check: str, tier: str = "T1", **arguments: Any
) -> list[dict[str, Any]]:
    """The findings of one check for an audit in internal mode at a tier."""
    results = outcome_results(data, formula, tier, **arguments)
    return [f for f in results.document["findings"] if f["check"] == check]


def outcome_statistics(finding: dict[str, Any]) -> dict[str, Any]:
    return {name: statistic["value"] for name, statistic in finding["statistics"].items()}


def separation_finding(data: pd.DataFrame, formula: str = "y ~ x") -> dict[str, Any]:
    """The finding of outcome.separation for a formula with the family
    binomial."""
    return outcome_findings(data, formula, "outcome.separation", tier="T2", family="binomial")[0]


def alternating() -> pd.DataFrame:
    return pd.DataFrame({"y": [0.0, 1, 0, 1, 0, 1], "x": [-2.0, -1, 0, 1, 2, 3]})


def separated() -> pd.DataFrame:
    return pd.DataFrame({"y": [0.0, 0, 0, 1, 1, 1], "x": [-3.0, -2, -1, 1, 2, 3]})


def replace_solver(monkeypatch: pytest.MonkeyPatch, solver: Any) -> None:
    """Replace the solver of outcome.separation for the rest of a test."""
    monkeypatch.setattr(_checks_outcome, "separation_solver", solver)


def first_unit(formulation: str, a: Any, objective: Any, *rest: Any) -> Any:
    """A solver that returns b = (1e-6, 0, ...) and multipliers 0 for every
    program."""
    b = np.zeros(len(objective))
    b[0] = 1e-6
    return _checks_outcome.SolvedProgram(b, np.zeros(a.shape[0]), 0.0)


def with_b(found: Any, b: Any) -> Any:
    """A solution of the solver with another b and the same multipliers."""
    return _checks_outcome.SolvedProgram(
        np.asarray(b, dtype=np.float64), found.multipliers, found.floor_multiplier
    )


def test_a_check_reads_the_outcome_only_at_a_tier_that_its_entry_states_and_the_run_reached() -> (
    None
):
    run: Any = SimpleNamespace(tier="T1", analysis=np.arange(3), outcome_reads=[])
    with pytest.raises(RuntimeError, match="Internal error"):
        outcome_values(run, {"id": "a.t0", "tier": "T0"})
    with pytest.raises(RuntimeError, match="Internal error"):
        outcome_values(run, {"id": "a.t2", "tier": "T2"})
    run.analysis = None
    with pytest.raises(RuntimeError, match="Internal error"):
        outcome_values(run, {"id": "a.t1", "tier": "T1"})
    # Step 13 refuses an access log without an entry for a column read.
    run.outcome_reads = [SimpleNamespace(tier="T2", columns=["k", "n"])]
    logged: list[dict[str, Any]] = [
        {"tier": "T0"},
        {"tier": "T2", "outcome": {"column": "k"}},
    ]
    with pytest.raises(RuntimeError, match="access log does not record"):
        outcome_reads_logged(run, logged)
    logged.append({"tier": "T2", "outcome": {"column": "n"}})
    outcome_reads_logged(run, logged)


def test_the_minority_events_and_constant_levels_of_a_binomial_outcome_are_counted_by_level() -> (
    None
):
    rng = np.random.default_rng(7)
    subjects = [f"s{i:02d}" for i in range(1, 31)]
    subject = np.repeat(subjects, 3)
    n = rng.integers(1, 5, len(subject))
    p = np.repeat(np.tile([0, 0.5, 1, 0.3, 0.7], 6), 3)
    k = rng.binomial(n, p)
    data = pd.DataFrame({"k": k, "n": n, "x": np.arange(1, len(k) + 1), "subject": subject})
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
    }
    formula = "k ~ x + (1 | subject)"
    minority = outcome_findings(data, formula, "outcome.minority_events", declaration=declaration)[
        0
    ]
    values = outcome_statistics(minority)
    events = data.groupby("subject")["k"].sum()
    non_events = (data["n"] - data["k"]).groupby(data["subject"]).sum()
    level_minority = np.minimum(events, non_events)
    assert values["events"] == k.sum()
    assert values["non_events"] == (n - k).sum()
    assert values["levels"] == 30
    assert values["levels_without_minority"] == (level_minority == 0).sum()
    assert values["median_minority"] == np.sort(level_minority.to_numpy())[14]
    assert minority["statistics"]["median_minority"]["quantile"] == {"p": 0.5, "n": 30}
    assert values["events_per_column"] == pytest.approx(min(k.sum(), (n - k).sum()) / 2)
    constant = outcome_findings(
        data, formula, "outcome.constant_clusters", declaration=declaration
    )[0]
    none = data["k"].eq(0).groupby(data["subject"]).all()
    every = data["k"].eq(data["n"]).groupby(data["subject"]).all()
    assert outcome_statistics(constant)["constant_levels"] == (none | every).sum()
    assert outcome_statistics(constant)["multi_row_levels"] == 30


def test_boundary_shares_compares_with_the_doubles_nearest_to_decimal_bounds() -> None:
    data = pd.DataFrame({"score": [0.5, 0.5, 9.5, 3, 4.25, 9.5, 9.5, 2], "x": np.arange(1.0, 9.0)})
    declaration: dict[str, Any] = {
        "vocabulary": "0.1.0",
        "variables": {
            "score": {"role": "outcome", "measurement": "bounded_score", "bounds": [0.5, 9.5]}
        },
    }
    found = outcome_findings(data, "score ~ x", "outcome.boundary_shares", declaration=declaration)[
        0
    ]
    values = outcome_statistics(found)
    assert (values["at_floor"], values["at_ceiling"]) == (2, 3)
    assert found["message"]["id"] == "at_bounds"
    # A measurement that /provenance/inferred lists counts as absent.
    declaration["provenance"] = {"inferred": ["/variables/score/measurement"]}
    found = outcome_findings(data, "score ~ x", "outcome.boundary_shares", declaration=declaration)[
        0
    ]
    assert found["status"]["availability"]["reason"] == "declaration_missing"


def test_separation_reports_no_solution_when_the_solver_gives_no_optimum(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    replace_solver(monkeypatch, lambda *args: None)
    found = separation_finding(separated())
    assert found["message"] == {
        "id": "no_solution",
        "text": "The solver gave no verified optimum of the linear programs, so separation could "
        "not be assessed.",
    }
    assert found["status"]["finding"]["value"] == "consistent"
    assert found["status"]["assessability"] == {
        "value": "not_assessable",
        "reason": "prerequisite_unmet",
        "detail": "verified_solution",
    }
    values = outcome_statistics(found)
    for name in ("verdict", "optimum", "margin"):
        assert name not in values
    assert values["columns"] == 2


def test_separation_verifies_each_solution_in_double_arithmetic(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A returned b that violates a constraint by more than
    # feasibility_tolerance is not verified, from the dual or the program.
    replace_solver(monkeypatch, first_unit)
    assert separation_finding(alternating())["message"]["id"] == "no_solution"


def test_a_program_whose_dual_has_no_verified_solution_is_solved_itself(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    solver = _checks_outcome.separation_solver
    unverified = _checks_outcome.SolvedProgram(np.array([1e-6, 0.0]), np.zeros(6), 0.0)
    for failure in (None, unverified):
        formulations: list[str] = []

        def failing(
            formulation: str, *args: Any, failure: Any = failure, called: list[str] = formulations
        ) -> Any:
            called.append(formulation)
            return failure if formulation == "dual" else solver(formulation, *args)

        replace_solver(monkeypatch, failing)
        values = outcome_statistics(separation_finding(separated()))
        assert values["verdict"] == "complete"
        assert formulations == ["dual", "primal"] * 6
        # Complete separation by 'x', scaled to -1 to 1: b = (0, 1) gives the
        # margin 1/3, and every b_1 from -1/3 to 1/3 with b_2 = 1 the optimum
        # 4.
        assert values["margin"] == pytest.approx(1 / 3, abs=1e-12)
        assert values["optimum"] == pytest.approx(4, abs=1e-12)
        assert values["bounds"] == pytest.approx([-1 / 3, 1 / 3, 1 - 1e-6 / 4, 1], abs=1e-9)
    # The dual and the program itself give the same values.
    monkeypatch.setattr(_checks_outcome, "separation_solver", solver)
    values = outcome_statistics(separation_finding(separated()))
    assert (values["verdict"], values["columns"]) == ("complete", 2)
    assert values["margin"] == pytest.approx(1 / 3, abs=1e-12)
    assert values["bounds"] == pytest.approx([-1 / 3, 1 / 3, 1 - 1e-6 / 4, 1], abs=1e-9)


def test_the_dual_gives_the_verified_solution_of_every_separation_program_of_the_audit_corpus(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The b of the dual is the first p elements of res.eqlin.marginals with
    # no change of sign. With a wrong sign, every dual would fail verification
    # and the programs themselves would give the same findings.
    solver = _checks_outcome.separation_solver
    formulations: list[str] = []

    def recording(formulation: str, *args: Any) -> Any:
        formulations.append(formulation)
        return solver(formulation, *args)

    replace_solver(monkeypatch, recording)
    cases = [
        case
        for name in ("outcome.json", "privacy.json")
        for case in corpus_cases("audits", name)
        if "outcome.separation" in case["checks"] and "issue" not in case["expected"]
    ]
    assert cases
    for case in cases:
        result = run_audit(case, "internal")
        assert "value" in result, case["id"]
    assert formulations
    assert set(formulations) == {"dual"}


def test_rounding_residues_leave_a_finding_clear_and_larger_violations_make_it_near_threshold(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # For the alternating data, b = (e, 0) gives u = -e for each non-event.
    def with_offset(e: float) -> dict[str, Any]:
        def offset(formulation: str, a: Any, objective: Any, *rest: Any) -> Any:
            b = np.zeros(len(objective))
            b[0] = e
            return _checks_outcome.SolvedProgram(b, np.zeros(a.shape[0]), 0.0)

        replace_solver(monkeypatch, offset)
        return separation_finding(alternating())

    for e in (0.0, 2e-13, 9e-12):
        found = with_offset(e)
        assert found["status"]["threshold_proximity"]["value"] == "clear", e
        assert outcome_statistics(found)["verdict"] == "none"
    for e in (1.1e-11, 1e-9, 9e-8):
        found = with_offset(e)
        assert found["status"]["threshold_proximity"]["value"] == "near_threshold", e


def test_a_bound_program_without_a_verified_solution_leaves_the_bounds_absent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    solver = _checks_outcome.separation_solver
    calls = 0

    # The dual of the first and of the second program succeed, then neither
    # the dual nor the program of the first bound gives a solution.
    def failing(*args: Any) -> Any:
        nonlocal calls
        calls += 1
        return None if calls > 2 else solver(*args)

    replace_solver(monkeypatch, failing)
    found = separation_finding(separated())
    values = outcome_statistics(found)
    assert calls == 4
    assert values["verdict"] == "complete"
    assert "bounds" not in values
    assert "columns_involved" not in values
    # The solver of the other package can solve the program.
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert found["message"]["text"] == (
        "The fixed effects separate the events from the non-events completely, so the estimates "
        "of some coefficients diverge and their Wald statistics are unreliable."
    )


def test_the_bound_programs_stop_at_the_first_without_a_verified_solution(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    solver = _checks_outcome.separation_solver

    # The bound programs of separated() minimise and maximise b_1 and then
    # b_2. The program numbered 'failing' has no solution, and
    # b = (1/3 + 1e-9, 1), which leaves u near -1e-9 for the non-event at
    # x = -1, scaled to -1/3, and reaches the largest b_2, answers the last.
    def with_failure(failing: int) -> tuple[dict[str, Any], list[str]]:
        programs = 0
        calls: list[str] = []

        def solving(
            formulation: str,
            a: Any,
            objective: Any,
            margin: bool,
            sums: Any,
            floor: float | None,
        ) -> Any:
            nonlocal programs
            if floor is None:
                return solver(formulation, a, objective, margin, sums, floor)
            if formulation == "dual":
                programs += 1
            calls.append(f"{programs} {formulation}")
            if programs == failing:
                return None
            found = solver(formulation, a, objective, margin, sums, floor)
            if programs == 4:
                return with_b(found, [1 / 3 + 1e-9, 1.0])
            return found

        replace_solver(monkeypatch, solving)
        return separation_finding(separated()), calls

    for failing in (1, 3):
        found, calls = with_failure(failing)
        values = outcome_statistics(found)
        solved = [f"{i} dual" for i in range(1, failing)]
        assert calls == solved + [f"{failing} dual", f"{failing} primal"], failing
        assert values["verdict"] == "complete"
        assert "bounds" not in values
        assert "columns_involved" not in values
        assert found["status"]["threshold_proximity"]["value"] == "near_threshold", failing
    # Solved, the last program makes the finding near_threshold through its
    # residue, and every program is solved by its dual.
    found, calls = with_failure(5)
    assert calls == [f"{i} dual" for i in range(1, 5)]
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert len(outcome_statistics(found)["bounds"]) == 4


def test_a_solution_outside_the_box_or_below_the_floor_is_not_verified(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    solver = _checks_outcome.separation_solver

    # Every |b_j| may exceed 1 by feasibility_tolerance, 1e-7, and no more.
    def outside(excess: float) -> dict[str, Any]:
        def solving(formulation: str, a: Any, objective: Any, *rest: Any) -> Any:
            found = solver(formulation, a, objective, *rest)
            return with_b(found, found.b * (1 + excess))

        replace_solver(monkeypatch, solving)
        return separation_finding(separated())

    assert outcome_statistics(outside(5e-8))["verdict"] == "complete"
    assert outside(2e-7)["message"]["id"] == "no_solution"

    # Half of the b of each program of bounds meets every other condition,
    # with an upper bound that never rejects it, but leaves the sum of the u
    # at 2, below the floor 4 - 1e-6.
    def halved(
        formulation: str, a: Any, objective: Any, margin: bool, sums: Any, floor: Any
    ) -> Any:
        found = solver(formulation, a, objective, margin, sums, floor)
        return found if floor is None else with_b(found, found.b / 2)

    replace_solver(monkeypatch, halved)
    monkeypatch.setattr(_checks_outcome, "separation_upper_bound", lambda *args: -np.inf)
    found = separation_finding(separated())
    assert "bounds" not in outcome_statistics(found)
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"


# Five rows whose columns x and x2 coincide to about 1e-10 after scaling, from
# a differential review of M2b-3. Over the optimal face, the smallest b_1 and
# the largest b_4 change by about 3.6e5 for each unit of the floor, so that
# optima 1e-12 apart move them by 3.6e-7, and lpSolve's duals gave bounds
# 1.6e-6 from the exact ones.
FLAT_FACE = pd.DataFrame(
    {
        "y": [1.0, 0, 1, 1, 1],
        "cond": ["lo", "hi", "lo", "lo", "lo"],
        "grp": ["ctl", "trt", "trt", "trt", "trt"],
        "x": [
            1000000.4954159142,
            1000000.7907073069,
            999998.8069716928,
            1000000.718385498,
            1000000.3630027653,
        ],
        "z": [
            1.1869343867185078,
            -0.3503705437936126,
            -1.9883279286402349,
            0.1613879293542133,
            -0.8714736062078614,
        ],
        "x2": [
            1000000.4955102435,
            1000000.7906631059,
            999998.8069359513,
            1000000.7182989309,
            1000000.3630308936,
        ],
        "dup": [
            2.3738687734370156,
            -0.7007410875872252,
            -3.9766558572804698,
            0.3227758587084266,
            -1.7429472124157228,
        ],
    }
)

# The bounds over the face of the exact optimum of FLAT_FACE, computed in
# rational arithmetic on the scaled columns by scratch code.
FLAT_FACE_BOUNDS = [
    0.640142041007987,
    1.0,
    0.9999997499999999,
    1.0,
    -1.0,
    -0.9999989999972206,
    -0.1762146611131083,
    0.18364429788168413,
    -1.0,
    -0.9999819239657262,
]


def test_bounds_whose_face_the_floor_moves_fast_make_the_finding_near_threshold() -> None:
    # Every program of FLAT_FACE has a verified solution with every u at
    # least minus residue_tolerance, so that only the multiplier r of the
    # floor makes the finding near_threshold. Each verified bound lies within
    # optimality_tolerance of the bound over the face of its own floor, which
    # the exact optimum of 5.055321869019773 gives here.
    found = separation_finding(FLAT_FACE, "y ~ cond * grp + x2 + x:z + dup")
    values = outcome_statistics(found)
    assert values["verdict"] == "complete"
    assert values["optimum"] == 5.055321869019773
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"
    assert len(values["bounds"]) == len(FLAT_FACE_BOUNDS)
    for bound, exact in zip(values["bounds"], FLAT_FACE_BOUNDS, strict=True):
        assert abs(bound - exact) <= 1e-8


def test_a_bound_below_the_upper_bound_of_its_multipliers_makes_the_finding_near_threshold(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The largest b_2 of separated() is 1, which the multipliers of its
    # solution certify. A b_2 that lies more than optimality_tolerance, 1e-9,
    # below it meets every constraint but leaves the finding near_threshold.
    solver = _checks_outcome.separation_solver

    def short_of(shortfall: float) -> dict[str, Any]:
        programs = 0

        def solving(
            formulation: str, a: Any, objective: Any, margin: bool, sums: Any, floor: Any
        ) -> Any:
            nonlocal programs
            found = solver(formulation, a, objective, margin, sums, floor)
            if floor is not None:
                programs += 1
                if programs == 4:
                    return with_b(found, [0.0, 1 - shortfall])
            return found

        replace_solver(monkeypatch, solving)
        return separation_finding(separated())

    for shortfall, proximity in ((5e-10, "clear"), (5e-9, "near_threshold")):
        found = short_of(shortfall)
        assert found["status"]["threshold_proximity"]["value"] == proximity, shortfall
        assert outcome_statistics(found)["bounds"][3] == 1 - shortfall


def test_marginals_far_below_their_upper_bound_make_the_finding_near_threshold() -> None:
    # Eight rows from the differential review of M2b-3, on which the
    # marginals of HiGHS for the smallest b_1 lie 2.2e-4 below the upper
    # bound of their multipliers and give 0.19318, where the exact bound over
    # the face of HiGHS's floor is 0.19299. The finding is near_threshold, as
    # it also is through the multiplier of the floor, near 3e5.
    data = pd.DataFrame(
        {
            "x0": [
                999999999.8005153,
                1000000000.3799306,
                999999998.93274,
                1000000001.0096029,
                1000000000.4365969,
                999999999.439252,
                1000000000.0784128,
                999999999.2560368,
            ],
            "x1": [
                1.1357764298101365,
                1.080586500871513,
                1.0608553761474853,
                0.09303841656973061,
                -0.027718407047332614,
                -0.950745323156156,
                0.40682788056219954,
                -1.792300863208763,
            ],
            "x2": [
                0.0005647508654815184,
                -0.0005514930500565029,
                -0.001832797229172364,
                0.00041848823393125675,
                0.0001358266117778995,
                0.0004962967851529367,
                -0.00021997975131418218,
                0.00030675730962633423,
            ],
            "x3": [
                485.67874034307584,
                460.20369426462184,
                1033.2329392319568,
                -1139.2170764981781,
                1141.4873024189453,
                275.55789987566766,
                -321.35191176656366,
                -875.6127376387095,
            ],
            "x4": [
                1000001.403305679,
                1000001.0005482967,
                1000000.4491212625,
                1000000.3270283963,
                1000000.9715402777,
                1000000.3755385365,
                1000000.6673432314,
                999999.0177721872,
            ],
            "f": ["b", "a", "b", "c", "a", "c", "b", "b"],
            "h": ["v", "v", "u", "v", "u", "v", "v", "v"],
            "y": [0.0, 0, 1, 1, 0, 0, 1, 1],
        }
    )
    found = separation_finding(data, "y ~ x0 + x1 + x2 + x3 + x4 + f + h:x0 + f:h")
    values = outcome_statistics(found)
    assert values["verdict"] == "complete"
    assert found["status"]["threshold_proximity"]["value"] == "near_threshold"


def separation_parameter(name: str) -> float:
    """A parameter of outcome.separation."""
    return parameter_value(registry_entry("outcome.separation"), name)


def replace_size(monkeypatch: pytest.MonkeyPatch, size: float) -> None:
    """Replace the size of the programs of outcome.separation for the rest of
    a test."""
    monkeypatch.setattr(_checks_outcome, "separation_size", lambda run: size)


def test_the_size_of_the_programs_counts_the_values_other_than_0_of_the_design_sample(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    size = _checks_outcome.separation_size
    sizes: list[float] = []

    def recorded(run: Any) -> float:
        sizes.append(size(run))
        return sizes[-1]

    monkeypatch.setattr(_checks_outcome, "separation_size", recorded)
    # The intercept and x, with two zeros, hold 7 + 5 values other than 0 in
    # the 7 rows of the design sample, the last of which has no outcome, and
    # the sequential rule drops w = 2x: (7 + 5) (2 + 10).
    x = [-2.0, 0, 1, 0, 3, 4, 5]
    y = pd.Series([0.0, 0, 1, 1, 0, 1, None], dtype=object)
    data = pd.DataFrame({"y": y, "x": x, "n": 2.0, "w": [2 * v for v in x]})
    separation_finding(data, "y ~ x + w")
    # Each row counts twice for the class binomial.
    benchmark_finding(data, "y ~ x + w", binomial=True)
    assert sizes == [144, 288]


def test_separation_is_not_available_beyond_max_size_and_then_names_no_solver(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    limit = separation_parameter("max_size")
    replace_size(monkeypatch, limit)
    found = separation_finding(separated())
    assert found["statistics"]["verdict"]["value"] == "complete"
    replace_size(monkeypatch, limit + 1)
    results = outcome_results(separated(), "y ~ x", tier="T2", family="binomial")
    found = next(f for f in results.document["findings"] if f["check"] == "outcome.separation")
    assert found["status"]["availability"] == {
        "value": "not_available",
        "reason": "too_large",
        "detail": "max_size",
    }
    assert "statistics" not in found
    assert "packages" not in results.document["software"]


def test_separation_leaves_the_bounds_absent_beyond_max_bound_size(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The 2 kept columns of 'separated()' give 4 programs of bounds.
    limit = separation_parameter("max_bound_size") / 4
    replace_size(monkeypatch, limit)
    assert len(outcome_statistics(separation_finding(separated()))["bounds"]) == 4
    replace_size(monkeypatch, limit + 1)
    found = separation_finding(separated())
    values = outcome_statistics(found)
    assert values["verdict"] == "complete"
    assert values["optimum"] == pytest.approx(4, abs=1e-12)
    assert "bounds" not in values
    assert "columns_involved" not in values
    assert found["message"]["text"] == (
        "The fixed effects separate the events from the non-events completely, so the "
        "estimates of some coefficients diverge and their Wald statistics are unreliable."
    )
    # The limit, unlike a program without a verified solution, leaves the
    # finding clear, since both packages apply it alike.
    assert found["status"]["threshold_proximity"]["value"] == "clear"


def test_separation_solves_up_to_max_bound_programs_programs_of_bounds() -> None:
    # A factor of 50 levels with an intercept keeps 50 columns, and one of 51
    # levels 51, two rows in each level, an event and a non-event apart from
    # the last level, which holds two events.
    def quasi(levels: int) -> pd.DataFrame:
        f = [f"l{level:02d}" for level in range(1, levels + 1) for _ in range(2)]
        y = [0.0, 1.0] * levels
        y[-2] = 1.0
        return pd.DataFrame({"y": y, "f": f})

    assert separation_parameter("max_bound_programs") == 100
    values = outcome_statistics(separation_finding(quasi(50), "y ~ f"))
    assert (values["columns"], values["verdict"]) == (50, "quasi")
    assert len(values["bounds"]) == 100
    assert values["columns_involved"] == ["f[l50]"]
    found = separation_finding(quasi(51), "y ~ f")
    values = outcome_statistics(found)
    assert (values["columns"], values["verdict"]) == (51, "quasi")
    assert "bounds" not in values
    assert "columns_involved" not in values
    assert found["status"]["threshold_proximity"]["value"] == "clear"


def test_a_program_whose_dual_has_no_verified_solution_is_solved_itself_up_to_max_primal_size(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    solver = _checks_outcome.separation_solver
    formulations: list[str] = []

    def failing(formulation: str, *args: Any) -> Any:
        formulations.append(formulation)
        return None if formulation == "dual" else solver(formulation, *args)

    replace_solver(monkeypatch, failing)
    limit = separation_parameter("max_primal_size")
    replace_size(monkeypatch, limit)
    assert outcome_statistics(separation_finding(separated()))["verdict"] == "complete"
    assert formulations == ["dual", "primal"] * 6
    # Beyond the limit, neither program of the verdict has a verified solution.
    formulations.clear()
    replace_size(monkeypatch, limit + 1)
    found = separation_finding(separated())
    assert formulations == ["dual", "dual"]
    assert found["message"]["id"] == "no_solution"
    assert "verdict" not in outcome_statistics(found)


def test_separation_names_scipy_whenever_it_runs_and_solves_nothing_without_kept_columns() -> None:
    packages = {"scipy": scipy.__version__}
    for y in ([0.0, 0, 0, 1, 1, 1], [0.0] * 6):
        data = pd.DataFrame({"y": y, "x": [-3.0, -2, -1, 1, 2, 3]})
        results = outcome_results(data, "y ~ x", tier="T2", family="binomial")
        assert results.document["software"]["packages"] == packages
    # Without the check, no package is named.
    results = outcome_results(separated(), "y ~ x", tier="T1", family="binomial")
    assert "packages" not in results.document["software"]
    # Without kept columns, the only solution is b = () and the verdict none.
    data = pd.DataFrame({"y": [1.0, 0, 1, 0, 1, 1], "g": ["a", "a", "b", "b", "c", "c"]})
    values = outcome_statistics(separation_finding(data, "y ~ 0 + (1 | g)"))
    assert {name: values[name] for name in ("columns", "verdict", "optimum", "margin")} == {
        "columns": 0,
        "verdict": "none",
        "optimum": 0,
        "margin": 0,
    }


def test_on_2000_rows_that_only_b_0_separates_a_violating_solution_is_near_threshold() -> None:
    # One event and one non-event a gap g apart around 0.5, first in the
    # table, and the other events above and non-events below 0.5. HiGHS at the
    # tolerances 1e-9 returns b = 0, where lpSolve reaches an optimum near 500
    # through violations of g.
    for g in (1e-8, 1e-9):
        data = pd.DataFrame(
            {
                "y": np.concatenate(([1.0, 0.0], np.zeros(999), np.ones(999))),
                "x": np.concatenate(
                    (
                        [0.5 - g, 0.5 + g],
                        np.linspace(0.0005, 0.4995, 999),
                        np.linspace(0.5005, 0.9995, 999),
                    )
                ),
            }
        )
        found = separation_finding(data)
        values = outcome_statistics(found)
        near = found["status"]["threshold_proximity"]["value"] == "near_threshold"
        assert values.get("verdict") == "none" or near, g


def test_separated_data_whose_margin_an_outlier_compresses_below_the_tolerances_are_clear() -> None:
    # 5,000 rows with y = 1 exactly when x1 > 0.5 x2, and x1 = 1e7 in the
    # first row, which divides the other values of x1 by 1e7 or more. The
    # verdict is quasi in exact arithmetic, and HiGHS through
    # scipy.optimize.linprog() with method 'highs-ds' and tolerances 1e-9
    # returns b = 0 and the verdict none, clear, where lpSolve reaches quasi
    # through a solution that is near_threshold (conventions.md, Comparison
    # across languages).
    i = np.arange(1, 5001)
    x1 = (i * 7919) % 10007 / 10007 - 0.5
    x2 = (i * 31337) % 10009 / 10009 - 0.5
    y = (x1 > 0.5 * x2).astype(float)
    x1[0] = 1e7
    found = outcome_findings(
        pd.DataFrame({"y": y, "x1": x1, "x2": x2}),
        "y ~ x1 + x2",
        "outcome.separation",
        tier="T2",
        family="binomial",
    )[0]
    assert found["statistics"]["verdict"]["value"] == "none"
    assert found["status"]["threshold_proximity"]["value"] == "clear"


def test_separation_is_fast_on_20000_observations() -> None:
    # The floor of scipy is 1.15.3, since linprog() takes time quadratic in
    # the number of variables of a program before it, which for the dual is
    # the number of observations, so that each of the 12 programs of this
    # table took about two minutes with SciPy 1.15.0.
    n = 20000
    rows = np.arange(n)
    x = np.sin(rows)
    f = np.resize(["a", "b", "c", "d"], n)
    y = np.where(f == "d", 1.0, (np.cos(rows * 1.3) > 0).astype(float))
    data = pd.DataFrame({"y": y, "x": x, "f": pd.Series(f, dtype=object)})
    start = time.perf_counter()
    values = outcome_statistics(separation_finding(data, "y ~ x + f"))
    elapsed = time.perf_counter() - start
    assert values["verdict"] == "quasi"
    assert values["columns_involved"] == ["f[d]"]
    assert elapsed < 60


def benchmark_table(
    seed: int, structure: str, kind: str, binomial: bool = False, n: int = 200
) -> pd.DataFrame:
    """A table of a structure of the benchmark that chose the formulation of
    outcome.separation (03-execution-plan.md, M2, M2b-2), generated as there
    with numpy's generator: x1 to x11 standard normal rounded to 6 decimals,
    the factors f, with 3 levels for S7 and 4 otherwise, and h, with 5 levels,
    a grouping column and, for the class binomial, trials from 1 to 6."""
    rng = np.random.default_rng(seed)
    d: dict[str, Any] = {"row": np.arange(1, n + 1)}
    for j in range(1, 12):
        d[f"x{j}"] = np.round(rng.normal(size=n), 6)
    d["f"] = rng.choice(list("abc" if structure == "S7" else "abcd"), n)
    d["h"] = rng.choice(["p", "q", "r", "s", "t"], n)
    d["g"] = [f"g{v:03d}" for v in rng.integers(1, max(5, n // 20) + 1, n)]
    m = rng.integers(1, 7, n) if binomial else np.ones(n, dtype=np.int64)
    mild = 0.6 * d["x1"] - 0.4 * d["x2"] + 0.3 * (d["f"] == "b") - 0.2 * (d["h"] == "q")
    if kind == "none":
        k = rng.binomial(m, 1 / (1 + np.exp(-mild)))
    elif kind == "complete":
        # S7: x1 x2 + 0.2 x1 above its median.
        z = d["x1"] * d["x2"] + 0.2 * d["x1"]
        k = np.where(z - np.median(z) > 0, m, 0)
    elif structure == "S4":
        # Only events at the level 'r' of h.
        k = rng.binomial(m, 1 / (1 + np.exp(-mild)))
        k[d["h"] == "r"] = m[d["h"] == "r"]
    else:
        # S8: events above the median of x1 on a grid of integers,
        # non-events below it, both at the median.
        d["x1"] = np.round(d["x1"] * 2)
        t = d["x1"] - np.median(d["x1"])
        k = np.where(t > 0, m, np.where(t < 0, 0, rng.binomial(m, 0.5)))
    d["y"] = k if binomial else (k > 0).astype(np.int64)
    d["n"] = m
    return pd.DataFrame(d)


# The cases of the benchmark: the seed, the structure, the kind of
# separation, whether the class is binomial, the formula, and the verdict,
# optimum, margin and columns_involved that the R package gives with lpSolve
# on the same tables, written by DataFrame.to_csv() and read by read.csv().
BENCHMARK_X11 = "y ~ " + " + ".join(f"x{j}" for j in range(1, 12))
BENCHMARK_CASES: list[tuple[Any, ...]] = [
    (1028, "S4", "none", True, "y ~ x1 + x2 + x3 + f + h", "none", 0, 0, None),
    (1031, "S4", "quasi", False, "y ~ x1 + x2 + x3 + f + h", "quasi", 44, 0, ["h[r]"]),
    (
        1061,
        "S7",
        "complete",
        False,
        "y ~ x1 * x2 + f",
        "complete",
        30.007920108550319,
        0.00054096974594815966,
        ["(Intercept)", "x1", "x2", "f[b]", "f[c]", "x1:x2"],
    ),
    (1067, "S8", "quasi", False, BENCHMARK_X11, "quasi", 49.833333333333329, 0, ["x1"]),
]


def benchmark_finding(data: pd.DataFrame, formula: str, binomial: bool) -> dict[str, Any]:
    declaration = None
    if binomial:
        declaration = {
            "vocabulary": "0.1.0",
            "variables": {"y": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
        }
    return outcome_findings(
        data,
        formula,
        "outcome.separation",
        tier="T2",
        family="binomial",
        declaration=declaration,
    )[0]


@pytest.mark.parametrize("case", BENCHMARK_CASES, ids=[str(case[0]) for case in BENCHMARK_CASES])
def test_separation_agrees_with_lpsolve_on_tables_of_its_benchmark(case: tuple[Any, ...]) -> None:
    seed, structure, kind, binomial, formula, verdict, optimum, margin, involved = case
    found = benchmark_finding(benchmark_table(seed, structure, kind, binomial), formula, binomial)
    values = outcome_statistics(found)
    assert values["verdict"] == verdict
    assert found["status"]["threshold_proximity"]["value"] == "clear"
    assert abs(values["optimum"] - optimum) <= 1e-6 * max(1, optimum)
    assert abs(values["margin"] - margin) <= 1e-6
    assert values.get("columns_involved") == involved
