"""The checks of the prefix assignment (spec/registry/checks/assignment.*.yaml)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    Unavailable,
    agreement_fraction,
    assignment_elements,
    check_element,
    check_unavailable,
    declaration_inferred,
    declared_units,
    factor_has_intercept,
    factor_levels,
    first_codes,
    pair_codes,
    pooled_constancy,
    tabulate,
    unit_label_columns,
    value_codes,
    within_level_rank,
)
from mixedcheck._declaration import path_pointer
from mixedcheck._design import sequential_rule
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    import numpy

    Array = numpy.ndarray[Any, Any]


@dataclass
class Assignment:
    """The assignment of a scope element (registry.md, Terms): ``rows``, the
    rows of the design sample, from 0, in which every label column of its unit
    and the assigned column are present, ``unit``, the level of the unit in
    each of these rows, from 0 in the order of first appearance, ``count``,
    the number of levels, ``assigned``, the codes of the assigned column in
    these rows, ``level``, the level of the assignment, declared or inferred
    with the parameter agreement, and its ``source``, whether the assignment
    is ``randomised`` and its declared ``blocks``. A member that
    /provenance/inferred lists counts as absent."""

    rows: Array
    unit: Array
    count: int
    assigned: Array
    level: str
    source: str
    randomised: bool
    blocks: list[str]


def assignment_rows(run: Run, entry: dict[str, Any], element: dict[str, str]) -> Assignment:
    """The assignment of a scope element, whose column the assignment block
    lists once (declarations.md, E2004)."""
    declaration = run.declaration
    assignment = declaration["assignment"]
    i = next(i for i, a in enumerate(assignment) if a["column"] == element["column"])

    def present(member: str) -> Any:
        if declaration_inferred(declaration, path_pointer("assignment", i, member)):
            return None
        return assignment[i].get(member)

    labels = unit_label_columns(declaration, element["unit"])
    column = comparison_form(element["column"])
    rows = run.design[value_codes(run, labels + [column], run.design) >= 0]
    unit = first_codes(value_codes(run, labels, rows))
    assigned = value_codes(run, [column], rows)
    level = present("level")
    source = "declared"
    if level is None:
        source = "inferred_from_the_data"
        constant = pooled_constancy(unit, assigned, agreement_fraction(entry)).constant
        level = "between_unit" if constant else "within_unit"
    blocks = present("blocks")
    return Assignment(
        rows=rows,
        unit=unit,
        count=int(unit.max(initial=-1)) + 1,
        assigned=assigned,
        level=level,
        source=source,
        randomised=present("randomised") is True,
        blocks=[str(block) for block in blocks] if blocks is not None else [],
    )


def assignment_applies(found: Assignment) -> bool:
    """Whether the assignment checks apply to an assignment: its level is
    between_unit and some level of the unit has at least two rows of the
    assignment."""
    return found.level == "between_unit" and bool((tabulate(found.unit) >= 2).any())


def assignment_block_missing(run: Run) -> bool:
    """Whether the declaration has no assignment block, or every entry of the
    block counts as absent, which makes the checks of the prefix assignment not
    available (declarations.md, assignment)."""
    return not assignment_elements(run.declaration)


def check_assignment_constant_within_unit(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """assignment.constant_within_unit: the levels of the unit within which
    the assigned column takes more than one value."""
    import numpy as np

    if assignment_block_missing(run):
        return check_unavailable("declaration_missing")
    found_elements: list[CheckElement | None] = []
    for element in elements:
        found = assignment_rows(run, entry, element)
        if not assignment_applies(found):
            found_elements.append(None)
            continue
        _, cells = np.unique(pair_codes(found.unit, found.assigned), return_index=True)
        mixed = int((tabulate(found.unit[cells], found.count) > 1).sum())
        statistics = {"units": found.count, "mixed_units": mixed, "level_source": found.source}
        found_elements.append(check_element(statistics, rules=[mixed > 0], rows=found.rows))
    return found_elements


def check_assignment_unit_in_random_part(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """assignment.unit_in_random_part: whether a grouping factor with a random
    intercept divides the rows of the assignment into the levels of the unit,
    and the grouping factors each of whose levels contains whole levels of the
    unit."""
    import numpy as np

    if assignment_block_missing(run):
        return check_unavailable("declaration_missing")
    found_elements: list[CheckElement | None] = []
    for element in elements:
        found = assignment_rows(run, entry, element)
        if not assignment_applies(found) or not found.randomised:
            found_elements.append(None)
            continue
        positions = np.searchsorted(run.design, found.rows)
        coverage = "absent"
        coarser: list[str] = []
        for factor in run.factors:
            code = factor_levels(run, factor).code[positions]
            pairs = len(np.unique(pair_codes(found.unit, code)))
            if pairs == found.count and pairs == len(np.unique(code)):
                if factor_has_intercept(run, factor):
                    coverage = "present"
            elif pairs == found.count:
                coarser.append(factor)
        statistics = {
            "units": found.count,
            "coverage": coverage,
            "coarser_factors": coarser,
            "level_source": found.source,
        }
        absent = coverage == "absent"
        found_elements.append(
            check_element(statistics, rules=[absent and len(coarser) > 0, absent], rows=found.rows)
        )
    return found_elements


def check_assignment_design_df(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """assignment.design_df: the degrees of freedom between the levels of the
    unit after the fixed effects, J + r - k on the rows of the assignment,
    where k is the number of columns of X that the sequential rule keeps on
    these rows and r the within-level rank of those columns
    (:func:`within_level_rank`), and the declared blocks that the fixed part
    leaves out."""
    import numpy as np

    if assignment_block_missing(run):
        return check_unavailable("declaration_missing")
    fixed = {
        comparison_form(variable["variable"])
        for term in run.ir["fixed"]["terms"]
        for variable in term["variables"]
    }
    units = declared_units(run.declaration)
    found_elements: list[CheckElement | None] = []
    for element in elements:
        found = assignment_rows(run, entry, element)
        if not assignment_applies(found):
            found_elements.append(None)
            continue
        x = np.asfortranarray(run.x[np.searchsorted(run.design, found.rows), :])
        kept = sequential_rule(x)
        within = within_level_rank(np.asfortranarray(x[:, kept]), found.unit, found.count)
        design_df = found.count + sum(within) - sum(kept)
        blocks = [
            block
            for block in found.blocks
            if block in units
            and not all(column in fixed for column in unit_label_columns(run.declaration, block))
        ]
        statistics = {
            "units": found.count,
            "design_df": design_df,
            "missing_blocks": blocks,
            "level_source": found.source,
        }
        found_elements.append(
            check_element(statistics, rules=[design_df == 0, len(blocks) > 0], rows=found.rows)
        )
    return found_elements
