"""The checks of the prefix structure (spec/registry/checks/structure.*.yaml)."""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, TypeAlias

from mixedcheck._checks import (
    CheckElement,
    Run,
    agreement_fraction,
    check_element,
    column_codes,
    compared_key_columns,
    declaration_inferred,
    declared_units,
    exact_group_sums,
    factor_has_intercept,
    factor_levels,
    first_codes,
    levels_of_full_rank,
    pair_codes,
    pooled_constancy,
    random_term_values,
    row_patterns,
    scope_finding,
    tabulate,
    threshold_holds,
    unit_parent,
    value_codes,
)
from mixedcheck._declaration import path_pointer
from mixedcheck._formula_ir import exact_sum
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    import numpy

    Array: TypeAlias = numpy.ndarray[Any, Any]


def first_occurrences(codes: Array) -> Array:
    """Whether each code is the first of its value, as R's !duplicated() gives
    it."""
    import pandas as pd

    found: Array = ~pd.Series(codes).duplicated().to_numpy()
    return found


def code_count(codes: Array) -> int:
    """The number of bins that codes from 0 need: the largest code plus 1."""
    return int(codes.max(initial=-1)) + 1


# --- structure.label_incidence ---------------------------------------------------------


@dataclass
class PairRows:
    """The rows of the design sample, from 0, in which both columns of a pair
    are present, with the codes of the two columns in those rows."""

    rows: Array
    first: Array
    second: Array


def _alone(factors: list[Any], column: str | None, other: str | None) -> bool:
    """Whether some grouping factor contains a column without the other."""
    return any(column in keys and other not in keys for keys in factors)


def column_pair_rows(run: Run, first: str, second: str) -> PairRows:
    """The rows of the design sample in which both columns of a pair are
    present, with the codes of the two columns in those rows, compared by
    value."""
    a = column_codes(run, first)[run.design]
    b = column_codes(run, second)[run.design]
    both = (a >= 0) & (b >= 0)
    return PairRows(run.design[both], a[both], b[both])


@dataclass
class Incidence:
    """The counts of structure.label_incidence for the codes of two columns."""

    levels_first: int
    levels_second: int
    combinations: int
    first_in_several: int
    second_in_several: int


def label_incidence(a: Array, b: Array) -> Incidence:
    """The counts of structure.label_incidence for the codes of two columns in
    the same rows: the labels of each, their distinct combinations and the
    labels of each that occur with more than one label of the other."""
    import numpy as np

    combined = first_occurrences(pair_codes(a, b))
    return Incidence(
        levels_first=len(np.unique(a)),
        levels_second=len(np.unique(b)),
        combinations=int(combined.sum()),
        first_in_several=int((tabulate(a[combined]) > 1).sum()),
        second_in_several=int((tabulate(b[combined]) > 1).sum()),
    )


@dataclass
class DeclaredRelation:
    """The relation that a declaration states for the units of a pair of
    columns, with the inner and outer column of a pair declared nested."""

    value: str
    inner: str | None = None
    outer: str | None = None


def declared_relation(declaration: Any, first: str, second: str) -> DeclaredRelation:
    """The relation that a declaration states for the units whose columns
    member lists one column of a pair alone (the statistic declared of
    structure.label_incidence), with the inner and outer column of a pair
    declared nested."""
    none = DeclaredRelation("none")
    units = declared_units(declaration)

    def alone(column: str) -> list[dict[str, Any]]:
        return [
            unit
            for unit in units.values()
            if [comparison_form(name) for name in unit["columns"]] == [column]
        ]

    units_first = alone(first)
    units_second = alone(second)
    if len(units_first) != 1 or len(units_second) != 1:
        return none
    unit_first = units_first[0]
    unit_second = units_second[0]

    def nesting(inner: str, outer: str, unit: Mapping[str, Any]) -> DeclaredRelation:
        if unit.get("id_scope") == "within_parent":
            value = "nested_within_parent"
        elif unit.get("membership") in (None, "fixed"):
            value = "nested_global"
        else:
            value = "nested_mobile"
        return DeclaredRelation(value, inner, outer)

    parent = unit_parent(declaration, unit_first)
    if parent is not None and parent["name"] == unit_second["name"]:
        return nesting(first, second, unit_first)
    parent = unit_parent(declaration, unit_second)
    if parent is not None and parent["name"] == unit_first["name"]:
        return nesting(second, first, unit_second)
    crossings = declaration.get("crossings", []) if isinstance(declaration, dict) else []
    for i, crossing in enumerate(crossings):
        pointers = [path_pointer("crossings", i, "units", k) for k in (0, 1)]
        if any(declaration_inferred(declaration, pointer) for pointer in pointers):
            continue
        if set(crossing["units"]) == {unit_first["name"], unit_second["name"]}:
            return DeclaredRelation("crossed")
    return none


def check_structure_label_incidence(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.label_incidence: how the labels of two grouping columns occur
    together in the rows of the design sample in which both are present, and
    the relation that the declaration states for the units they label."""
    found: list[CheckElement | None] = []
    for element in elements:
        first = element["first"]
        second = element["second"]
        pair = column_pair_rows(run, first, second)
        incidence = label_incidence(pair.first, pair.second)
        if not incidence.first_in_several and not incidence.second_in_several:
            relation = "identical"
        elif not incidence.first_in_several:
            relation = "first_nested_in_second"
        elif not incidence.second_in_several:
            relation = "second_nested_in_first"
        elif incidence.combinations == incidence.levels_first * incidence.levels_second:
            relation = "crossed"
        else:
            relation = "partially_crossed"
        declared = declared_relation(run.declaration, first, second)
        nested = declared.value.startswith("nested_")
        factors = list(run.factors.values())
        inner_alone = nested and _alone(factors, declared.inner, declared.outer)
        # The IR splits the units of a column that appears in no grouping
        # factor without the other column of the pair: the inner column of a
        # pair declared nested, and either column of any other pair.
        if nested:
            split = not inner_alone
        else:
            split = not (_alone(factors, first, second) and _alone(factors, second, first))
        composite = split and any(first in keys and second in keys for keys in factors)
        statistics: dict[str, Any] = {
            "levels_first": incidence.levels_first,
            "levels_second": incidence.levels_second,
            "combinations": incidence.combinations,
            "first_in_several": incidence.first_in_several,
            "second_in_several": incidence.second_in_several,
            "relation": relation,
            "declared": declared.value,
            "inner": [declared.inner] if nested else [],
            "outer": [declared.outer] if nested else [],
            "composite": composite,
            "inner_alone": inner_alone,
        }
        several = False
        if nested:
            inner_in_several = (
                incidence.first_in_several
                if declared.inner == first
                else incidence.second_in_several
            )
            statistics["inner_in_several"] = inner_in_several
            several = inner_in_several > 0
        found.append(
            check_element(
                statistics,
                rules=[
                    declared.value == "nested_within_parent" and inner_alone and several,
                    declared.value == "nested_global" and several,
                    declared.value == "nested_mobile" and composite and several,
                    declared.value == "crossed" and composite,
                ],
                rows=pair.rows,
            )
        )
    return found


# --- structure.id_scope_evidence -------------------------------------------------------


@dataclass
class ScopeDirection:
    """One direction of structure.id_scope_evidence: the shared labels, the
    candidate attributes and, when there are some, the smallest number of
    shared labels that change one of them and the first attribute that gives
    it."""

    shared: int
    attributes: list[str] = field(default_factory=list)
    changing: int = 0
    attribute: str = ""


def scope_direction(
    run: Run,
    labels: Array,
    context: Array,
    rows: Array,
    candidates: Sequence[str],
    agreement: tuple[int, int],
) -> ScopeDirection:
    """One direction of structure.id_scope_evidence, with labels and context the
    codes of the two columns in the given rows: the shared labels, the
    candidate attributes in code-point order and the smallest number of shared
    labels that change one of them, with the first attribute that gives it.
    Attribute values are compared by value, with missing values equal to each
    other."""
    m, d = agreement
    combination = pair_codes(labels, context)
    distinct = first_occurrences(combination)
    label_count = code_count(labels)
    shared = tabulate(labels[distinct], label_count) > 1
    n = code_count(combination)
    context_count = code_count(context)
    attributes: list[str] = []
    counts: list[int] = []
    for key in candidates:
        values = value_codes(run, [key], rows, missing_level=True)

        def varies(groups: Array, count: int, values: Array = values) -> Array:
            cells = first_occurrences(pair_codes(groups, values))
            return tabulate(groups[cells], count) > 1

        constant = int((~varies(combination, n)).sum())
        if constant * 10**d >= m * n and bool(varies(context, context_count).any()):
            attributes.append(key)
            counts.append(int((varies(labels, label_count) & shared).sum()))
    found = ScopeDirection(int(shared.sum()), attributes)
    if attributes:
        found.changing = min(counts)
        found.attribute = attributes[counts.index(found.changing)]
    return found


def check_structure_id_scope_evidence(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.id_scope_evidence: for a crossed pair that the declaration does
    not relate and the IR does not combine, the attributes that are constant
    within most combinations of the two columns, in each direction, and how
    many shared labels of the labels column change them."""
    incidence = run.results["structure.label_incidence"]
    agreement = agreement_fraction(entry)
    pool = compared_key_columns(run)
    result: list[CheckElement | None] = []
    for element in elements:
        found = scope_finding(incidence, element)
        if (
            found is None
            or found.values["declared"] != "none"
            or found.values["composite"] is not False
            or found.values["relation"] not in ("crossed", "partially_crossed")
        ):
            result.append(None)
            continue
        first = element["first"]
        second = element["second"]
        pair = column_pair_rows(run, first, second)
        candidates = [key for key in pool if key not in (first, second)]
        forward = scope_direction(run, pair.first, pair.second, pair.rows, candidates, agreement)
        backward = scope_direction(run, pair.second, pair.first, pair.rows, candidates, agreement)
        has_forward = bool(forward.attributes)
        has_backward = bool(backward.attributes)
        if has_forward != has_backward:
            reverse = has_backward
        else:
            reverse = has_forward and backward.changing > 0 and forward.changing == 0
        reported = backward if reverse else forward
        tied = has_forward and has_backward and forward.changing > 0 and backward.changing > 0
        statistics: dict[str, Any] = {
            "labels_column": [second if reverse else first],
            "context_column": [first if reverse else second],
            "levels": found.values["levels_second" if reverse else "levels_first"],
            "shared_labels": reported.shared,
            "attributes": reported.attributes,
            "tied": tied,
        }
        if reported.attributes:
            statistics["changing_labels"] = reported.changing
            statistics["changing_attribute"] = [reported.attribute]
        values = dict(statistics)
        if reported.attributes and reported.shared > 0:
            values["changing_share"] = reported.changing / reported.shared
        empty = not reported.attributes
        result.append(
            check_element(
                statistics,
                rules=[
                    empty,
                    tied,
                    threshold_holds(entry, "most_change", values),
                    threshold_holds(entry, "any_change", values),
                ],
                assessability=[empty],
                rows=pair.rows,
            )
        )
    return result


# --- structure.aliased_factors ---------------------------------------------------------


def check_structure_aliased_factors(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.aliased_factors: whether two grouping factors divide the design
    sample into the same groups, one into finer groups than the other or
    neither, and whether their random terms share a column."""
    found: list[CheckElement | None] = []
    for element in elements:
        first = factor_levels(run, element["first"])
        second = factor_levels(run, element["second"])
        combined = first_occurrences(pair_codes(first.code, second.code))
        first_single = bool((tabulate(first.code[combined], first.count) == 1).all())
        second_single = bool((tabulate(second.code[combined], second.count) == 1).all())
        if first_single and second_single:
            partition = "identical"
        elif first_single:
            partition = "first_finer"
        elif second_single:
            partition = "second_finer"
        else:
            partition = "other"
        shared_columns = factors_share_column(run, element["first"], element["second"])
        statistics: dict[str, Any] = {
            "partition": partition,
            "shared_columns": shared_columns,
            "finer": [],
            "coarser": [],
            "rows": len(run.design),
        }
        if partition in ("first_finer", "second_finer"):
            first_is_finer = partition == "first_finer"
            coarser = second if first_is_finer else first
            statistics["finer"] = [element["first"] if first_is_finer else element["second"]]
            statistics["coarser"] = [element["second"] if first_is_finer else element["first"]]
            contained = tabulate(coarser.code[combined], coarser.count)
            informative = contained >= 2
            statistics["coarser_levels"] = coarser.count
            statistics["informative_levels"] = int(informative.sum())
            statistics["informative_rows"] = int(informative[coarser.code].sum())
        found.append(
            check_element(
                statistics,
                rules=[
                    partition == "identical" and shared_columns,
                    partition == "identical",
                    partition in ("first_finer", "second_finer"),
                ],
            )
        )
    return found


def factors_share_column(run: Run, first: str, second: str) -> bool:
    """Whether a random term of one grouping factor and a random term of another
    have a column in common: two columns with the same name, or two columns
    whose values are equal in every row of the design sample."""
    random = run.ir["random"]

    def of(factor: str) -> list[int]:
        return [t for t, term in enumerate(random) if term["factor"] == factor]

    def column_names(t: int) -> set[str]:
        return {column["name"] for column in random[t]["columns"]}

    for s in of(first):
        for t in of(second):
            if column_names(s) & column_names(t):
                return True
            a = random_term_values(run, s).values
            b = random_term_values(run, t).values
            for i in range(a.shape[1]):
                if bool((a[:, [i]] == b).all(axis=0).any()):
                    return True
    return False


# --- structure.cluster_sizes -----------------------------------------------------------


def check_structure_cluster_sizes(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.cluster_sizes: the distribution of the rows of the design
    sample over the levels of a grouping factor."""
    import numpy as np

    found: list[CheckElement | None] = []
    family = run.family_class
    n = len(run.design)
    for element in elements:
        levels = factor_levels(run, element["factor"])
        sizes = np.sort(tabulate(levels.code, levels.count)).tolist()
        j = levels.count

        # The quantile p of the J sizes is the size at position ceil(J x p),
        # counted from 1.
        def at(numerator: int, denominator: int, sizes: list[int] = sizes, j: int = j) -> int:
            return sizes[(j * numerator + denominator - 1) // denominator - 1]

        squares = sum(size * size for size in sizes)
        # S/N, the difference and the quotient are computed in double
        # arithmetic, and the quotient of one level, 0/0, is NaN.
        spread = n - float(squares) / n
        intercept = factor_has_intercept(run, element["factor"])
        statistics = {
            "levels": j,
            "rows": n,
            "smallest": sizes[0],
            "lower_quartile": at(1, 4),
            "median": at(1, 2),
            "upper_quartile": at(3, 4),
            "largest": sizes[j - 1],
            "singletons": sum(1 for size in sizes if size == 1),
            "effective_size": spread / (j - 1) if j > 1 else math.nan,
            "intercept": intercept,
        }
        one_row = j == n and intercept
        found.append(
            check_element(
                statistics,
                rules=[
                    one_row and family in ("gaussian", "other"),
                    one_row and family == "bernoulli",
                    one_row and family in ("binomial", "poisson"),
                ],
            )
        )
    return found


# --- structure.within_between ----------------------------------------------------------


def check_structure_within_between(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.within_between: for a fixed term and a grouping factor, the
    levels in which the term's kept columns vary, the levels in which they
    vary in every direction, the status inferred with the tolerance of
    agreement and, for one numeric column, its intraclass correlation."""
    import numpy as np

    agreement = agreement_fraction(entry)
    ir = run.ir
    terms = ir["fixed"]["terms"]
    term_names = [term["name"] for term in terms]
    column_terms = np.array([column["term"] for column in ir["fixed"]["columns"]], dtype=np.int64)
    x_kept = np.asarray(run.x_kept, dtype=bool)
    found: list[CheckElement | None] = []
    for element in elements:
        t = term_names.index(element["term"])
        kept = np.flatnonzero(x_kept & (column_terms == t))
        if not len(kept):
            found.append(None)
            continue
        term = terms[t]
        values = run.x[:, kept]
        patterns = row_patterns(values)
        levels = factor_levels(run, element["factor"])
        sizes = tabulate(levels.code, levels.count)
        several = sizes >= 2
        cells = first_occurrences(pair_codes(levels.code, patterns))
        varying = several & (tabulate(levels.code[cells], levels.count) > 1)
        informative = levels_of_full_rank(
            values, levels.code, levels.count, among=varying, difference=True
        )
        slope = slope_requested(run, term, element["factor"])
        statistics: dict[str, Any] = {
            "multi_row_levels": int(several.sum()),
            "varying_levels": int(varying.sum()),
            "informative_levels": int(informative.sum()),
            "slope_requested": slope,
        }
        status = None
        if bool(several.any()):
            if pooled_constancy(levels.code, patterns, agreement).constant:
                status = "between"
            elif bool(varying[several].all()):
                status = "within"
            else:
                status = "partially_within"
            statistics["status"] = status
        numeric = all(
            ir["predictors"].get(v["variable"], {}).get("kind") == "numeric"
            for v in term["variables"]
        )
        if len(kept) == 1 and numeric:
            statistics.update(
                intraclass_correlation(values[:, 0], levels.code, levels.count, sizes)
            )
        none = not bool(several.any())
        between = status == "between"
        found.append(
            check_element(
                statistics,
                rules=[
                    none,
                    between and slope and statistics["varying_levels"] == 0,
                    between and slope,
                    status == "partially_within" and slope,
                ],
                assessability=[none],
            )
        )
    return found


def slope_requested(run: Run, term: Mapping[str, Any], factor: str) -> bool:
    """Whether a random term of a grouping factor has a term whose set of
    variables equals that of a fixed term, as estimands are matched with
    terms."""
    wanted = {v["variable"] for v in term["variables"]}
    return any(
        random["factor"] == factor
        and any(
            bool(part["variables"]) and {v["variable"] for v in part["variables"]} == wanted
            for part in random["terms"]
        )
        for random in run.ir["random"]
    )


def intraclass_correlation(x: Array, level: Array, count: int, sizes: Array) -> dict[str, float]:
    """The ANOVA intraclass correlation of a column over the levels of a factor
    and the share of its variation within levels (structure.within_between).
    The column is divided by its largest absolute value, which changes neither
    statistic, so that the squares neither overflow nor underflow, and the
    overall and level means of the scaled column are summed exactly and
    divided once. SSB and SSW are summed exactly and rounded once, a precision
    that the definition leaves open (03-execution-plan.md, M2b-2). Both
    statistics are absent for a column that is constant, compared by value,
    and the share also when SSB + SSW is 0. The correlation is NaN when J is
    1, when N equals J or when its denominator is 0, so that its absence
    depends on no count of levels or rows. ``level`` holds codes from 0."""
    import numpy as np

    found: dict[str, float] = {}
    n = len(x)
    if bool((x == x[0]).all()):
        return found
    x = x / np.max(np.abs(x))
    mean = exact_sum(x.tolist()) / n
    means = exact_group_sums(x, level, count) / sizes
    ssb = math.fsum((sizes * (means - mean) ** 2).tolist())
    ssw = math.fsum(((x - means[level]) ** 2).tolist())
    if ssb + ssw != 0:
        found["within_share"] = ssw / (ssb + ssw)
    found["icc"] = math.nan
    if count > 1 and n > count:
        msb = ssb / (count - 1)
        msw = ssw / (n - count)
        squares = sum(size * size for size in sizes.tolist())
        n0 = (n - float(squares) / n) / (count - 1)
        denominator = msb + (n0 - 1) * msw
        if denominator != 0:
            found["icc"] = (msb - msw) / denominator
    return found


# --- structure.connectivity ------------------------------------------------------------


def check_structure_connectivity(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """structure.connectivity: the crossed groups of levels of two grouping
    factors that rows link, and the fixed terms that are constant within
    them."""
    import numpy as np

    aliased = run.results["structure.aliased_factors"]
    agreement = agreement_fraction(entry)
    ir = run.ir
    column_terms = np.array([column["term"] for column in ir["fixed"]["columns"]], dtype=np.int64)
    x_kept = np.asarray(run.x_kept, dtype=bool)
    found: list[CheckElement | None] = []
    for element in elements:
        aliased_finding = scope_finding(aliased, element)
        if aliased_finding is None or aliased_finding.values["partition"] != "other":
            found.append(None)
            continue
        first = factor_levels(run, element["first"])
        second = factor_levels(run, element["second"])
        component = bipartite_components(first.code, second.code, first.count, second.count)
        of_first = component[: first.count]
        of_second = component[first.count :]
        components = len(component)
        crossed = (tabulate(of_first, components) >= 2) & (tabulate(of_second, components) >= 2)
        if not bool(crossed.any()):
            found.append(None)
            continue
        row_component = of_first[first.code]
        inside = crossed[row_component]
        groups = row_component[inside]
        terms: list[str] = []
        exact = True
        for t, term in enumerate(ir["fixed"]["terms"]):
            kept = np.flatnonzero(x_kept & (column_terms == t))
            if not term["variables"] or not len(kept):
                continue
            patterns = row_patterns(run.x[np.ix_(inside, kept)])
            constancy = pooled_constancy(groups, patterns, agreement)
            if constancy.constant:
                terms.append(term["name"])
                exact = exact and constancy.exact
        crossed_count = int(crossed.sum())
        several = crossed_count >= 2
        found.append(
            check_element(
                {
                    "components": crossed_count,
                    "between_component_terms": terms,
                    "exact": exact,
                },
                rules=[
                    several and bool(terms) and exact,
                    several and bool(terms),
                    several,
                ],
            )
        )
    return found


def bipartite_components(first: Array, second: Array, first_count: int, second_count: int) -> Array:
    """The connected components of the graph whose vertices are the levels of
    two factors, the first's from 0 and the second's after them, and whose
    edges join two levels that occur together in a row. Each round hooks every
    root that has an edge to a root with a smaller number onto the smallest
    such root and then follows the hooks to their roots, so that each round
    takes time that grows with the rows. Returns the component of each vertex,
    numbered from 0 in the order of their smallest vertices. ``first`` and
    ``second`` hold codes from 0."""
    import numpy as np

    edges = first_occurrences(pair_codes(first, second))
    u = first[edges]
    v = first_count + second[edges]
    parent = np.arange(first_count + second_count, dtype=np.int64)
    while True:
        a = parent[u]
        b = parent[v]
        open_ = a != b
        if not bool(open_.any()):
            break
        low = np.minimum(a[open_], b[open_])
        high = np.maximum(a[open_], b[open_])
        ordered = np.lexsort((low, high))
        high = high[ordered]
        low = low[ordered]
        hooked = np.ones(len(high), dtype=bool)
        hooked[1:] = high[1:] != high[:-1]
        parent[high[hooked]] = low[hooked]
        while True:
            jumped = parent[parent]
            if bool((jumped == parent).all()):
                break
            parent = jumped
    return first_codes(parent)
