"""The checks of the prefix outcome (spec/registry/checks/outcome.*.yaml).

outcome.separation solves the linear programs of its entry with HiGHS through
``scipy.optimize.linprog()`` with method 'highs-ds' and the feasibility
tolerances 1e-9, through the dual of each program, and solves the program
itself only when the dual has no verified solution. Each solution is verified
in double arithmetic on the observations before the verdict is decided, and
the objectives of the programs that give the bounds against the upper bounds
that their multipliers give (outcome.separation.yaml, verdict and
optimality_tolerance).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    CheckElement,
    OutcomeValues,
    Run,
    Unavailable,
    check_element,
    check_unavailable,
    declaration_inferred,
    exact_group_sums,
    factor_levels,
    first_codes,
    outcome_values,
    pair_codes,
    parameter_value,
    tabulate,
    threshold_holds,
)
from mixedcheck._declaration import path_pointer
from mixedcheck._design import sequential_rule
from mixedcheck._formula_ir import exact_sum
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    import numpy

    Array = numpy.ndarray[Any, Any]

# The primal and dual feasibility tolerances of HiGHS with which
# outcome.separation solves its programs (outcome.separation.yaml, verdict).
SEPARATION_SOLVER_TOLERANCE = 1e-9


@dataclass
class AnalysisLevels:
    """The level of each row of the analysis sample in a grouping factor, from
    0 in the order of first appearance, and the number of levels, counting
    only those that occur in the sample."""

    code: Array
    count: int


def analysis_levels(run: Run, factor: str) -> AnalysisLevels:
    """The levels of a grouping factor over the rows of the analysis sample."""
    import numpy as np

    assert run.analysis is not None
    positions = np.searchsorted(run.design, run.analysis)
    code = first_codes(factor_levels(run, factor).code[positions])
    return AnalysisLevels(code, int(code.max(initial=-1)) + 1)


def response_declared(run: Run, member: str) -> Any:
    """A member of the declaration's entry for the response, or None when it is
    absent or counts as absent (registry.md, Terms)."""
    declaration = run.declaration
    variables = declaration.get("variables", {}) if isinstance(declaration, dict) else {}
    response = run.ir.get("response")
    if response is None:
        return None
    name = next((name for name in variables if comparison_form(name) == response["variable"]), None)
    if name is None or declaration_inferred(declaration, path_pointer("variables", name, member)):
        return None
    return variables[name].get(member)


def event_level_missing(run: Run, outcome: OutcomeValues) -> bool:
    """The availability rule declaration_missing of outcome.minority_events and
    outcome.separation: the class is bernoulli, the outcome takes values other
    than 0 and 1, as numbers or logical values, in the analysis sample, and the
    response of the IR has no event level."""
    if run.family_class != "bernoulli" or "event_level" in run.ir["response"]:
        return False
    if outcome.type == "boolean":
        return False
    if outcome.type == "number":
        return not bool(((outcome.values == 0) | (outcome.values == 1)).all())
    return True


@dataclass
class OutcomeEvents:
    """The events and trials of each row of the analysis sample."""

    events: Array
    trials: Array


def outcome_events(run: Run, outcome: OutcomeValues) -> OutcomeEvents:
    """The events and trials of each row of the analysis sample: the response
    vector and 1 for the class bernoulli, and the events and trials of a
    binomial response."""
    import numpy as np

    assert outcome.response is not None
    if run.family_class == "binomial" and outcome.trials is not None:
        return OutcomeEvents(outcome.response, outcome.trials)
    return OutcomeEvents(outcome.response, np.ones(len(outcome.response), dtype=np.float64))


def check_outcome_boundary_shares(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """outcome.boundary_shares: the rows of the analysis sample at the lower and
    at the upper declared bound of a bounded score."""
    measurement = response_declared(run, "measurement")
    if measurement is None:
        return check_unavailable("declaration_missing")
    if measurement != "bounded_score":
        return [None]
    bounds = response_declared(run, "bounds")
    if bounds is None:
        return check_unavailable("declaration_missing", "/variables/{outcome}/bounds")
    outcome = outcome_values(run, entry)
    if outcome.type != "number":
        return [None]
    values = outcome.values
    statistics: dict[str, Any] = {
        "rows": len(values),
        "at_floor": int((values == float(bounds[0])).sum()),
        "at_ceiling": int((values == float(bounds[1])).sum()),
    }
    compared = {
        **statistics,
        "floor_share": statistics["at_floor"] / statistics["rows"],
        "ceiling_share": statistics["at_ceiling"] / statistics["rows"],
    }
    holds = threshold_holds(entry, "floor", compared) or threshold_holds(entry, "ceiling", compared)
    return [check_element(statistics, rules=[holds])]


def check_outcome_constant_clusters(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """outcome.constant_clusters: the levels of a grouping factor with two or
    more rows of the analysis sample within which the outcome takes one
    value."""
    import numpy as np

    if not elements:
        return []
    outcome = outcome_values(run, entry)
    # For the class binomial, a row is coded 0 without events, 1 with as many
    # events as trials and 2 otherwise, and a level is constant when its rows
    # share the code 0 or the code 1.
    binomial = run.family_class == "binomial" and outcome.trials is not None
    if binomial:
        assert outcome.response is not None and outcome.trials is not None
        observed = np.where(
            outcome.response == 0, 0, np.where(outcome.response == outcome.trials, 1, 2)
        )
        codes = first_codes(observed)
    elif outcome.response is not None:
        # Adding 0 turns negative zero into zero.
        codes = first_codes(outcome.response + 0.0)
    else:
        codes = first_codes(
            np.array([comparison_form(value) for value in outcome.values.tolist()], dtype=object)
        )
    found: list[CheckElement | None] = []
    for element in elements:
        levels = analysis_levels(run, element["factor"])
        several = tabulate(levels.code, levels.count) >= 2
        _, cells = np.unique(pair_codes(levels.code, codes), return_index=True)
        constant = several & (tabulate(levels.code[cells], levels.count) == 1)
        if binomial:
            constant &= tabulate(levels.code[observed == 2], levels.count) == 0
        statistics: dict[str, Any] = {
            "multi_row_levels": int(several.sum()),
            "constant_levels": int(constant.sum()),
        }
        compared = dict(statistics)
        if statistics["multi_row_levels"] > 0:
            compared["constant_share"] = (
                statistics["constant_levels"] / statistics["multi_row_levels"]
            )
        none = statistics["multi_row_levels"] == 0
        rules = [
            none,
            threshold_holds(entry, "many", compared),
            threshold_holds(entry, "any", compared),
        ]
        found.append(check_element(statistics, rules=rules, assessability=[none]))
    return found


def check_outcome_minority_events(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """outcome.minority_events: the events and non-events of the analysis
    sample, the levels of a grouping factor without one of the two classes,
    the median level minority count and the minority events per kept
    fixed-effects column."""
    import numpy as np

    outcome = outcome_values(run, entry)
    if event_level_missing(run, outcome):
        return check_unavailable("declaration_missing")
    counts = outcome_events(run, outcome)
    events = exact_sum(counts.events.tolist())
    non_events = exact_sum(counts.trials.tolist()) - events
    # kept of design.rank_deficiency, which yields no finding without columns.
    required = run.results.get("design.rank_deficiency", [])
    kept = int(required[0].values["kept"]) if required else 0
    found: list[CheckElement | None] = []
    for element in elements:
        statistics: dict[str, Any] = {"events": events, "non_events": non_events}
        if kept > 0:
            statistics["events_per_column"] = min(events, non_events) / kept
        model = "factor" not in element
        if not model:
            levels = analysis_levels(run, element["factor"])
            level_events = exact_group_sums(counts.events, levels.code, levels.count)
            level_trials = exact_group_sums(counts.trials, levels.code, levels.count)
            minority = np.minimum(level_events, level_trials - level_events)
            statistics["levels"] = levels.count
            statistics["levels_without_minority"] = int((minority == 0).sum())
            statistics["median_minority"] = float(np.sort(minority)[(levels.count + 1) // 2 - 1])
        found.append(check_element(statistics, rules=[model]))
    return found


def check_outcome_zero_shares(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """outcome.zero_shares: the rows of the analysis sample whose count is 0 and
    the levels of a grouping factor in which every count is 0."""
    import numpy as np

    outcome = outcome_values(run, entry)
    if outcome.type == "number":
        zero = outcome.values == 0
    else:
        zero = np.zeros(len(outcome.rows), dtype=bool)
    found: list[CheckElement | None] = []
    for element in elements:
        statistics: dict[str, Any] = {"rows": len(zero), "zeros": int(zero.sum())}
        model = "factor" not in element
        if not model:
            levels = analysis_levels(run, element["factor"])
            statistics["levels"] = levels.count
            statistics["all_zero_levels"] = int(
                (tabulate(levels.code[~zero], levels.count) == 0).sum()
            )
        found.append(check_element(statistics, rules=[model]))
    return found


# --- outcome.separation ----------------------------------------------------------------


@dataclass
class SeparationTolerances:
    """The parameters of outcome.separation that its programs and their
    verification read."""

    separation: float
    feasibility: float
    residue: float
    involvement: float
    optimality: float
    bound: float


def check_outcome_separation(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """outcome.separation: whether the kept fixed-effects columns of the
    analysis sample separate the events from the non-events, by the two linear
    programs of the entry, solved by HiGHS and verified in double arithmetic,
    with the range of each coefficient over the optimal face of the first."""
    import numpy as np
    import scipy

    outcome = outcome_values(run, entry)
    if event_level_missing(run, outcome):
        return check_unavailable("declaration_missing")
    # The solver is named whenever the check passes its family filter and
    # availability rules, also when it solves nothing and when the privacy
    # filter suppresses its finding, so that the list of packages shows
    # nothing about the outcome (documents.md, Results document).
    run.packages["scipy"] = scipy.__version__
    tolerances = SeparationTolerances(
        separation=parameter_value(entry, "separation_tolerance"),
        feasibility=parameter_value(entry, "feasibility_tolerance"),
        residue=parameter_value(entry, "residue_tolerance"),
        involvement=parameter_value(entry, "involvement_tolerance"),
        optimality=parameter_value(entry, "optimality_tolerance"),
        bound=parameter_value(entry, "bound_tolerance"),
    )
    assert run.analysis is not None
    x = np.asfortranarray(run.x[np.searchsorted(run.design, run.analysis), :])
    kept = sequential_rule(x)
    # The privacy filter reads the kept columns of the analysis sample.
    run.analysis_kept = kept
    x = x[:, np.asarray(kept, dtype=bool)]
    x = x / np.max(np.abs(x), axis=0)
    # One observation with s = 1 for each row with an event and one with
    # s = -1 for each row with a non-event, in the order of the rows.
    counts = outcome_events(run, outcome)
    with_events = np.flatnonzero(counts.events > 0)
    with_non_events = np.flatnonzero(counts.events < counts.trials)
    rows = np.concatenate((with_events, with_non_events))
    signs = np.concatenate((np.ones(len(with_events)), -np.ones(len(with_non_events))))
    ordered = np.lexsort((-signs, rows))
    a = signs[ordered][:, np.newaxis] * x[rows[ordered], :]
    events = len(with_events)
    non_events = len(with_non_events)
    statistics: dict[str, Any] = {
        "columns": x.shape[1],
        "events": events,
        "non_events": non_events,
        "both_classes": events > 0 and non_events > 0,
    }
    near = False
    proximity: dict[str, Any] = {}
    if statistics["both_classes"]:
        found, near = separation_programs(a, tolerances)
        statistics.update(found)
        bounds = statistics.get("bounds")
        if bounds is not None:
            names = [name for name, keep in zip(run.x_columns, kept, strict=True) if keep]
            statistics["columns_involved"] = [
                name
                for name, smallest, largest in zip(names, bounds[0::2], bounds[1::2], strict=True)
                if largest > tolerances.involvement or smallest < -tolerances.involvement
            ]
        proximity = {
            "separation_tolerance": [
                statistics[name] for name in ("optimum", "margin") if name in statistics
            ],
            "involvement_tolerance": list(bounds or []),
        }
    verdict = statistics.get("verdict")
    one_class = not statistics["both_classes"]
    return [
        check_element(
            statistics,
            rules=[one_class, verdict is None, verdict == "complete", verdict == "quasi"],
            assessability=[one_class, not one_class and verdict is None],
            proximity=proximity,
            near_threshold=near,
        )
    ]


@dataclass
class SeparationSolution:
    """A verified solution of a program of outcome.separation: b, u = A b,
    whether its objective lies within the optimality tolerance of the upper
    bound of its multipliers, and r, the multiplier of the floor of a program
    of bounds. The second program has no upper bound, and counts as certified
    with r = 0, as the first does with r = 0."""

    b: Array
    u: Array
    certified: bool
    floor_multiplier: float


@dataclass
class SolvedProgram:
    """What the solver returns for a program of outcome.separation: b and the
    multipliers that bound its objective, y for the observations and r for
    the floor (outcome.separation.yaml, optimality_tolerance)."""

    b: Array
    multipliers: Array
    floor_multiplier: float


def separation_programs(a: Array, tolerances: SeparationTolerances) -> tuple[dict[str, Any], bool]:
    """The programs of outcome.separation on the rows a of s x' for every
    observation: the first, which maximises the sum of s x'b subject to
    s x'b >= 0, the second, which maximises t subject to s x'b >= t, both with
    -1 <= b_j <= 1 and t <= 1, and, for a verdict of quasi or complete, the
    smallest and largest b_j over the optimal face of the first. Returns the
    statistics optimum, margin, verdict and bounds, each when the definition
    gives it, and whether the solutions make the finding near_threshold."""
    import numpy as np

    n, p = a.shape
    sums = np.array([exact_sum(a[:, j].tolist()) for j in range(p)], dtype=np.float64)
    near = False

    def solve(
        objective: Array, margin: bool = False, floor: float | None = None
    ) -> SeparationSolution | None:
        """The verified solution of the program that maximises objective'b, or
        t with margin True, subject to s x'b >= 0, or >= t, sums'b >= floor
        when floor is given and the bounds: the b of its dual, or of the
        program itself when the dual has no verified solution. A solution is
        verified when every |b_j| is at most 1 and every u = s x'b at least 0,
        each within the feasibility tolerance, and, with floor, the sum of
        the u is at least floor within it. One with some u below minus the
        residue tolerance makes the finding near_threshold. Without kept
        columns, b = () is the one solution and needs no solver."""
        nonlocal near
        if p == 0:
            return SeparationSolution(np.zeros(0), np.zeros(n), True, 0.0)
        for formulation in ("dual", "primal"):
            found = separation_solver(formulation, a, objective, margin, sums, floor)
            if found is None:
                continue
            b = found.b
            if not bool((np.abs(b) <= 1 + tolerances.feasibility).all()):
                continue
            u = a @ b
            if not bool((u >= -tolerances.feasibility).all()):
                continue
            if floor is not None and exact_sum(u.tolist()) < floor - tolerances.feasibility:
                continue
            if bool((u < -tolerances.residue).any()):
                near = True
            if margin:
                return SeparationSolution(b, u, True, 0.0)
            value = exact_sum(u.tolist()) if floor is None else float(objective @ b)
            upper = separation_upper_bound(
                a, objective, sums, floor, found.multipliers, found.floor_multiplier
            )
            certified = upper - value <= tolerances.optimality * max(1.0, abs(value))
            floor_multiplier = max(found.floor_multiplier, 0.0) if floor is not None else 0.0
            return SeparationSolution(b, u, certified, floor_multiplier)
        return None

    statistics: dict[str, Any] = {}
    first = solve(sums)
    if first is not None:
        statistics["optimum"] = exact_sum(first.u.tolist())
    second = solve(np.zeros(p), margin=True)
    if second is not None:
        statistics["margin"] = min(1.0, float(second.u.min()))
    if first is None or second is None:
        return statistics, near
    if statistics["margin"] > tolerances.separation:
        statistics["verdict"] = "complete"
    elif statistics["optimum"] > tolerances.separation:
        statistics["verdict"] = "quasi"
    else:
        statistics["verdict"] = "none"
    if statistics["verdict"] != "none":
        # The optimal face: the constraints of the first program with a sum of
        # s x'b of at least the optimum minus the separation tolerance. The
        # smallest b_j maximises -b_j. The bounds of the two packages can
        # differ by more than the bound tolerance, which makes the finding
        # near_threshold, when the optimum or a bound is not certified, when a
        # program of bounds has no verified solution, or when the floors of
        # the two packages can move a bound that far (outcome.separation.yaml,
        # optimality_tolerance).
        near = near or not first.certified
        floor = statistics["optimum"] - tolerances.separation
        scale = max(1.0, abs(statistics["optimum"]))
        bounds: list[float] = []
        for j in range(p):
            for sign in (-1.0, 1.0):
                unit = np.zeros(p)
                unit[j] = sign
                found = solve(unit, floor=floor)
                if found is None:
                    return statistics, True
                shift = 2 * tolerances.optimality * (1 + found.floor_multiplier * scale)
                if not found.certified or shift > tolerances.bound:
                    near = True
                bounds.append(float(found.b[j]))
        statistics["bounds"] = bounds
    return statistics, near


def separation_upper_bound(
    a: Array,
    objective: Array,
    sums: Array,
    floor: float | None,
    multipliers: Array,
    floor_multiplier: float,
) -> float:
    """The upper bound on the objective of the first program of
    outcome.separation, or of a program of bounds with floor, that the
    multipliers y, for the observations, and r, for the floor, give by weak
    duality, in double arithmetic: with v = A'y, the sum of
    |objective_j + v_j + r sums_j| minus floor r, with r = 0 for the first.
    Multipliers below 0 count as 0 (outcome.separation.yaml,
    optimality_tolerance)."""
    import numpy as np

    v = a.T @ np.maximum(multipliers, 0.0)
    if floor is None:
        return float(np.abs(objective + v).sum())
    r = max(floor_multiplier, 0.0)
    return float(np.abs(objective + v + r * sums).sum()) - r * floor


def separation_solver(
    formulation: str,
    a: Array,
    objective: Array,
    margin: bool,
    sums: Array,
    floor: float | None,
) -> SolvedProgram | None:
    """One program of outcome.separation solved by HiGHS through
    ``scipy.optimize.linprog()`` with method 'highs-ds' and the primal and
    dual feasibility tolerances SEPARATION_SOLVER_TOLERANCE: b and the
    multipliers y and r for an optimum, None otherwise. The program maximises
    objective'b, or t with margin True, subject to A b >= 0, or A b - t >= 0,
    sums'b >= floor when floor is given, -1 <= b_j <= 1 and t <= 1, where A
    is a.

    - 'dual': its dual, which minimises 1'(w+ + w-) - floor r + z over
      y, r, w+, w-, z >= 0 subject to w+ - w- - A'y - sums r = objective and,
      with margin True, 1'y + z = 1, with r only when floor is given and z
      only with margin True. b is the first p elements of
      ``res.eqlin.marginals``, the derivatives of the dual's minimum with
      respect to the right-hand sides of its p equality constraints, with no
      change of sign, and y and r are the solver's values of those variables.
      The program has one constraint for each coefficient, and one more with
      margin True, whatever the number of observations. Its constraints are
      passed as a sparse matrix in compressed columns, the form in which
      linprog() hands them to HiGHS.
    - 'primal': the program itself in b = b+ - b- with 0 <= b+_j, b-_j <= 1,
      the upper bounds written as constraints. y and r are minus the elements
      of ``res.ineqlin.marginals`` of the constraints A b >= 0, or
      A b - t >= 0, and sums'b >= floor, which linprog() takes negated.
    """
    import numpy as np
    from scipy import sparse
    from scipy.optimize import linprog

    n, p = a.shape
    ident = np.eye(p)
    zeros = np.zeros((p, p))
    options = {
        "primal_feasibility_tolerance": SEPARATION_SOLVER_TOLERANCE,
        "dual_feasibility_tolerance": SEPARATION_SOLVER_TOLERANCE,
    }
    if formulation == "dual":
        # The constraints in rows and the variables y, r, w+, w- and z in
        # columns.
        blocks: list[Array] = [-a.T]
        costs: list[Array] = [np.zeros(n)]
        if floor is not None:
            blocks.append(-sums[:, np.newaxis])
            costs.append(np.array([-floor]))
        blocks += [ident, -ident]
        costs.append(np.ones(2 * p))
        rhs = np.asarray(objective, dtype=np.float64)
        if margin:
            width = n + (floor is not None) + 2 * p
            blocks.append(np.zeros((p, 1)))
            total = np.zeros((1, width + 1))
            total[0, :n] = 1.0
            total[0, width] = 1.0
            costs.append(np.ones(1))
            rhs = np.concatenate((rhs, [1.0]))
        # The stubs of scipy 1.15 type the constraints of linprog() as dense
        # arrays, which it does not require.
        equality: Any = sparse.hstack([sparse.csc_array(block) for block in blocks], format="csc")
        if margin:
            equality = sparse.vstack((equality, sparse.csc_array(total)), format="csc")
        found = linprog(
            np.concatenate(costs),
            A_eq=equality,
            b_eq=rhs,
            bounds=(0, None),
            method="highs-ds",
            options=options,
        )
        if found.status != 0:
            return None
        # The stubs of scipy 1.15 do not type the members of eqlin.
        equalities: Any = found.eqlin
        marginals: Array = np.asarray(equalities.marginals, dtype=np.float64)
        values: Array = np.asarray(found.x, dtype=np.float64)
        return SolvedProgram(
            marginals[:p].copy(), values[:n].copy(), float(values[n]) if floor is not None else 0.0
        )
    # The rows that are at least their right-hand sides are negated, since
    # linprog() takes constraints of the form A_ub v <= b_ub.
    rows: list[Array] = [np.hstack((-a, a))]
    rhs_parts: list[Array] = [np.zeros(n)]
    if floor is not None:
        rows.append(np.concatenate((-sums, sums))[np.newaxis, :])
        rhs_parts.append(np.array([-floor]))
    rows += [np.hstack((ident, zeros)), np.hstack((zeros, ident))]
    rhs_parts.append(np.ones(2 * p))
    upper = np.vstack(rows)
    gain = np.concatenate((objective, -np.asarray(objective, dtype=np.float64)))
    if margin:
        column = np.zeros((upper.shape[0], 1))
        column[:n] = 1.0
        last = np.zeros(2 * p + 1)
        last[2 * p] = 1.0
        upper = np.vstack((np.hstack((upper, column)), last))
        rhs_parts.append(np.ones(1))
        gain = np.concatenate((gain, [1.0]))
    inequality: Any = sparse.csc_array(upper)
    found = linprog(
        -gain,
        A_ub=inequality,
        b_ub=np.concatenate(rhs_parts),
        bounds=(0, None),
        method="highs-ds",
        options=options,
    )
    if found.status != 0:
        return None
    solution: Array = np.asarray(found.x, dtype=np.float64)
    inequalities: Any = found.ineqlin
    duals: Array = -np.asarray(inequalities.marginals, dtype=np.float64)
    return SolvedProgram(
        solution[:p] - solution[p : 2 * p],
        duals[:n].copy(),
        float(duals[n]) if floor is not None else 0.0,
    )
