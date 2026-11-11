"""The checks of the prefix design (spec/registry/checks/design.*.yaml)."""

from __future__ import annotations

import math
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    check_element,
    column_codes,
    declaration_inferred,
    role_columns,
    threshold_holds,
    value_codes,
)
from mixedcheck._declaration import path_pointer
from mixedcheck._design import sequential_residuals, sequential_rule
from mixedcheck._formula_ir import exact_sum
from mixedcheck._schema import term_variables
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    import numpy

    Array = numpy.ndarray[Any, Any]


def check_design_rank_deficiency(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """design.rank_deficiency: the fixed-effects columns that the sequential
    rule drops on the design sample, the terms that own them, whether a focal
    term is among those terms and the empty cells of interactions between
    factors."""
    ir = run.ir
    columns = ir["fixed"]["columns"]
    if not columns:
        return [None]
    column_terms = [column["term"] for column in columns]
    term_names = [term["name"] for term in ir["fixed"]["terms"]]
    dropped = [j for j, kept in enumerate(run.x_kept) if not kept]
    owners = sorted({column_terms[j] for j in dropped})
    focal = focal_terms(run)
    focal_dropped = any(focal[t] for t in owners)
    statistics = {
        "columns": len(columns),
        "kept": sum(run.x_kept),
        "dropped_columns": [run.x_columns[j] for j in dropped],
        "dropped_terms": [term_names[t] for t in owners],
        "empty_cells": empty_cells(run),
        "focal_dropped": focal_dropped,
    }
    return [check_element(statistics, rules=[focal_dropped, len(dropped) > 0])]


def focal_terms(run: Run) -> list[bool]:
    """Whether each fixed term of the IR is focal (registry.md, Terms). An
    estimand counts for the model when its outcome, the one it names or else
    the one declared outcome, is the response, when it names none and no
    outcome is declared, and always for a one-sided formula. A focal estimand
    that counts makes focal the term whose set of variables equals that of its
    term. When no estimand counts, every term with variables is focal. An
    estimand, or a member of one, that /provenance/inferred lists counts as
    absent."""
    declaration = run.declaration
    terms = run.ir["fixed"]["terms"]
    response = run.ir.get("response")
    response_key = None if response is None else response["variable"]
    has_variables = [len(term["variables"]) > 0 for term in terms]
    outcomes = role_columns(declaration, ["outcome"])
    counting = False
    wanted: list[set[str]] = []
    estimands = declaration.get("estimands", []) if isinstance(declaration, dict) else []
    for i, estimand in enumerate(estimands):
        if declaration_inferred(declaration, path_pointer("estimands", i)):
            continue

        def present(member: str, i: int = i, estimand: Any = estimand) -> Any:
            if declaration_inferred(declaration, path_pointer("estimands", i, member)):
                return None
            return estimand.get(member)

        outcome = present("outcome")
        if response_key is None:
            counts = True
        elif outcome is not None:
            counts = comparison_form(outcome) == response_key
        elif len(outcomes) == 1:
            counts = comparison_form(outcomes[0]) == response_key
        else:
            counts = not outcomes
        if not counts:
            continue
        counting = True
        if present("focal") is not False:
            term = present("term")
            if term is not None:
                wanted.append({comparison_form(v) for v in term_variables(term)})
    if not counting:
        return has_variables
    found = []
    for term in terms:
        names = {comparison_form(v["variable"]) for v in term["variables"]}
        found.append(len(names) > 0 and any(w == names for w in wanted))
    return found


def empty_cells(run: Run) -> int:
    """The combinations of levels without a row in the design sample, summed
    over the interaction terms whose variables are all categorical, with the
    levels of each variable that occur in the design sample."""
    import numpy as np

    predictors = run.ir["predictors"]
    total = 0
    for term in run.ir["fixed"]["terms"]:
        names = [v["variable"] for v in term["variables"]]
        categorical = all(predictors.get(name, {}).get("kind") == "categorical" for name in names)
        if len(names) < 2 or not categorical:
            continue
        keys = [comparison_form(name) for name in names]
        levels = [len(np.unique(column_codes(run, key)[run.design])) for key in keys]
        cells = len(np.unique(value_codes(run, keys, run.design)))
        total += math.prod(levels) - cells
    return total


def check_design_collinearity(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """design.collinearity: the generalised variance inflation factor of each
    main-effect term (Fox & Monette, 1992) over the columns of the main-effect
    terms that the sequential rule keeps after a column of ones, computed as a
    product of ratios of residual norms rather than as a ratio of
    determinants."""
    import numpy as np

    ir = run.ir
    term_names = [term["name"] for term in ir["fixed"]["terms"]]
    main = {t for t, term in enumerate(ir["fixed"]["terms"]) if len(term["variables"]) == 1}
    if len(main) < 2:
        return [None] * len(elements)
    column_terms = [column["term"] for column in ir["fixed"]["columns"]]
    columns = [j for j, t in enumerate(column_terms) if t in main]
    n = run.x.shape[0]
    with_ones = np.empty((n, len(columns) + 1), dtype=np.float64, order="F")
    with_ones[:, 0] = 1.0
    with_ones[:, 1:] = run.x[:, columns]
    kept = sequential_rule(with_ones)[1:]
    chosen = [j for j, keep in zip(columns, kept, strict=True) if keep]
    owner = np.array([column_terms[j] for j in chosen], dtype=np.int64)
    pool = unit_centred_columns(run.x[:, chosen])
    found: list[CheckElement | None] = []
    for element in elements:
        own = owner == term_names.index(element["term"])
        df = int(own.sum())
        if not df:
            found.append(None)
            continue
        term = pool[:, own]
        others = pool[:, ~own]
        # b: the residuals after the other columns and the earlier columns of
        # the term, a: after the earlier columns of the term alone.
        both = np.asfortranarray(np.hstack((others, term)))
        b = sequential_residuals(both)[1][others.shape[1] :]
        a = sequential_residuals(np.asfortranarray(term))[1]
        gvif = math.prod((x / y) ** 2 for x, y in zip(a, b, strict=True))
        values = {"df": df, "gvif": gvif, "gvif_per_df": gvif ** (1 / df)}
        found.append(
            check_element(
                values,
                rules=[
                    threshold_holds(entry, "high", values),
                    threshold_holds(entry, "moderate", values),
                ],
            )
        )
    return found


def unit_centred_columns(x: Array) -> Array:
    """The columns divided by their largest absolute values, so that no sum or
    product of their values overflows or underflows, centred by their means,
    each summed exactly and divided once as ir.md (Centring) computes means,
    and scaled to unit Euclidean length."""
    import numpy as np

    n = x.shape[0]
    found = np.empty(x.shape, dtype=np.float64, order="F")
    for j in range(x.shape[1]):
        scaled = x[:, j] / np.max(np.abs(x[:, j]))
        centred = scaled - exact_sum(scaled.tolist()) / n
        found[:, j] = centred / math.sqrt(float(np.dot(centred, centred)))
    return found


def check_design_scale_disparity(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """design.scale_disparity: the standard deviations of the kept
    fixed-effects columns of numeric terms that take a value other than 0 and
    1, and the condition number of the kept columns scaled to unit length."""
    import numpy as np

    ir = run.ir
    n = len(run.design)
    predictors = ir["predictors"]
    numeric_terms = [
        len(term["variables"]) > 0
        and all(
            predictors.get(v["variable"], {}).get("kind") == "numeric" for v in term["variables"]
        )
        for term in ir["fixed"]["terms"]
    ]
    column_terms = [column["term"] for column in ir["fixed"]["columns"]]
    x = run.x
    candidates = [j for j, kept in enumerate(run.x_kept) if kept and numeric_terms[column_terms[j]]]
    scaled = [j for j in candidates if bool(((x[:, j] != 0) & (x[:, j] != 1)).any())]
    if n < 2 or not scaled:
        return [None]
    deviations = [column_sd(x[:, j]) for j in scaled]
    statistics: dict[str, Any] = {
        "scaled_columns": [run.x_columns[j] for j in scaled],
        "sd_largest": max(deviations),
        "sd_smallest": min(deviations),
    }
    if statistics["sd_smallest"] > 0:
        statistics["sd_ratio"] = statistics["sd_largest"] / statistics["sd_smallest"]
    kept = x[:, [j for j, keep in enumerate(run.x_kept) if keep]]
    unit = np.empty(kept.shape, dtype=np.float64, order="F")
    for j in range(kept.shape[1]):
        column = kept[:, j] / np.max(np.abs(kept[:, j]))
        unit[:, j] = column / math.sqrt(float(np.dot(column, column)))
    singular = np.linalg.svd(unit, compute_uv=False)
    with np.errstate(divide="ignore", invalid="ignore"):
        statistics["condition_number"] = float(np.max(singular) / np.min(singular))
    disparate = (
        threshold_holds(entry, "ratio", statistics)
        or threshold_holds(entry, "high", statistics)
        or threshold_holds(entry, "low", statistics)
    )
    return [check_element(statistics, rules=[disparate])]


def column_sd(x: Array) -> float:
    """The standard deviation of a column with denominator n - 1: 0 when its
    values are all equal, and otherwise M times the square root of the sum of
    the squared differences from the mean of the column divided by its largest
    absolute value M, over n - 1, so that no square overflows or underflows.
    The mean and the sum of the squares are summed exactly and rounded once,
    so that every operation is fixed."""
    import numpy as np

    if bool((x == x[0]).all()):
        return 0.0
    n = len(x)
    largest = float(np.max(np.abs(x)))
    scaled = x / largest
    centred = scaled - exact_sum(scaled.tolist()) / n
    return largest * math.sqrt(math.fsum((centred * centred).tolist()) / (n - 1))
