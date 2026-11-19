"""The code-first builders of declarations and :func:`draft_design`, which
writes a draft declaration from the data (02-decisions.md, Q4, and
docs/spec/declarations.md). Both give the JSON that a hand-written declaration
gives, and :func:`validate_declaration` checks it."""

from __future__ import annotations

import itertools
import os
import re
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import TYPE_CHECKING, Any

import numpy as np

from mixedcheck._audit import audit_arguments
from mixedcheck._checks import Run, column_codes, column_index, value_codes
from mixedcheck._commitments import run_data
from mixedcheck._declaration import path_pointer, validate_declaration
from mixedcheck._formula_ir import build_formula_ir
from mixedcheck._times import run_time, utc_timestamp

if TYPE_CHECKING:
    import pandas

_PLAN_KEY = "00" * 32
_UNIT_NAME = re.compile(r"[A-Za-z][A-Za-z0-9_.]{0,63}")


def declaration(
    units: Sequence[Mapping[str, Any]] | None = None,
    crossings: Sequence[Mapping[str, Any]] | None = None,
    observation: Mapping[str, Any] | None = None,
    assignment: Sequence[Mapping[str, Any]] | None = None,
    variables: Mapping[str, Mapping[str, Any]] | None = None,
    estimands: Sequence[Mapping[str, Any]] | None = None,
    table: Mapping[str, Any] | None = None,
    title: str | None = None,
    goal: str | None = None,
    features: Sequence[str] | None = None,
    disclosure_unit: str | None = None,
    provenance: Mapping[str, Any] | None = None,
    vocabulary: str = "0.1.0",
    minimal: bool = False,
) -> Any:
    """Build a design declaration in code.

    Assembles a declaration of vocabulary 0.1 from its blocks and validates it
    with :func:`validate_declaration`. The entries of the blocks come from
    :func:`declare_unit`, :func:`declare_crossing`, :func:`declare_observation`,
    :func:`declare_assignment`, :func:`declare_variable` and
    :func:`declare_estimand`, or are written as dicts. A block left None is
    absent. The result is the declaration that the same JSON file gives, with
    the same hash.

    Args:
        units, crossings, assignment, estimands: None or a list of entries.
        observation, table, provenance: None or the block as a dict.
        variables: None or a dict of variables by column.
        title, goal, disclosure_unit: None or a str.
        features: None or a list of features.
        vocabulary: The vocabulary version.
        minimal: Whether the declaration must be a minimal declaration.

    Returns:
        The declaration, as :func:`validate_declaration` returns it.

    Raises:
        TypeError: An argument of the wrong type.
        MixedcheckError: The error of :func:`validate_declaration`.

    Examples:
        >>> d = declaration(
        ...     units=[declare_unit("school", ["school"], role="cluster"),
        ...            declare_unit("pupil", ["pupil"], nested_in="school",
        ...                         id_scope="global", role="participant")],
        ...     observation=declare_observation(key=["pupil"], unit="pupil"),
        ...     assignment=[declare_assignment("arm", "school", randomised=True,
        ...                                    level="between_unit")],
        ...     variables={"score": declare_variable("outcome", measurement="continuous"),
        ...                "arm": declare_variable("assigned")},
        ...     estimands=[declare_estimand("itt", "arm", kind="total_effect")],
        ...     features=["cluster_randomised"],
        ... )
        >>> d["units"][1]["nested_in"]
        'school'
    """
    value: dict[str, Any] = {"vocabulary": _string(vocabulary, "vocabulary")}
    members: dict[str, Any] = {
        "title": _string(title, "title"),
        "goal": _string(goal, "goal"),
        "features": _strings(features, "features"),
        "disclosure_unit": _string(disclosure_unit, "disclosure_unit"),
        "table": _object(table, "table"),
        "units": _entries(units, "units"),
        "crossings": _entries(crossings, "crossings"),
        "observation": _object(observation, "observation"),
        "assignment": _entries(assignment, "assignment"),
        "variables": _object(variables, "variables"),
        "estimands": _entries(estimands, "estimands"),
        "provenance": _object(provenance, "provenance"),
    }
    value.update({k: v for k, v in members.items() if v is not None})
    if not isinstance(minimal, bool):
        raise TypeError("'minimal' must be True or False.")
    return validate_declaration(value, minimal=minimal)


def declare_unit(
    name: str,
    columns: Sequence[str],
    nested_in: str | None = None,
    id_scope: str | None = None,
    membership: str | None = None,
    role: str | None = None,
) -> dict[str, Any]:
    """A unit of the units block (declarations.md, units).

    Examples:
        >>> declare_unit("pupil", ["pupil"], nested_in="school", id_scope="global")
        {'name': 'pupil', 'columns': ['pupil'], 'nested_in': 'school', 'id_scope': 'global'}
    """
    return _entry(
        name=_string(name, "name"),
        columns=_strings(columns, "columns"),
        nested_in=_string(nested_in, "nested_in"),
        id_scope=_string(id_scope, "id_scope"),
        membership=_string(membership, "membership"),
        role=_string(role, "role"),
    )


def declare_crossing(units: Sequence[str], list_column: str | None = None) -> dict[str, Any]:
    """A crossing of two units, with the column of its counterbalancing list
    as ``list_column``, the member ``list``.

    Examples:
        >>> declare_crossing(["subject", "item"])
        {'units': ['subject', 'item']}
    """
    return _entry(units=_strings(units, "units"), list=_string(list_column, "list_column"))


def declare_observation(
    key: Sequence[str] | None = None,
    unit: str | None = None,
    time_column: str | None = None,
    time_kind: str | None = None,
    time_within: str | None = None,
) -> dict[str, Any]:
    """The observation block, with the members of ``time`` as ``time_column``,
    ``time_kind`` and ``time_within``.

    Examples:
        >>> declare_observation(key=["pupil", "wave"], time_column="wave", time_kind="occasion")
        {'key': ['pupil', 'wave'], 'time': {'column': 'wave', 'kind': 'occasion'}}
    """
    time = _entry(
        column=_string(time_column, "time_column"),
        kind=_string(time_kind, "time_kind"),
        within=_string(time_within, "time_within"),
    )
    return _entry(unit=_string(unit, "unit"), key=_strings(key, "key"), time=time or None)


def declare_assignment(
    column: str,
    unit: str,
    randomised: bool,
    level: str | None = None,
    blocks: Sequence[str] | None = None,
) -> dict[str, Any]:
    """An assignment of the assignment block.

    Examples:
        >>> declare_assignment("arm", "school", randomised=True, level="between_unit")
        {'column': 'arm', 'unit': 'school', 'randomised': True, 'level': 'between_unit'}
    """
    if not isinstance(randomised, bool):
        raise TypeError("'randomised' must be True or False.")
    return _entry(
        column=_string(column, "column"),
        unit=_string(unit, "unit"),
        randomised=randomised,
        level=_string(level, "level"),
        blocks=_strings(blocks, "blocks"),
    )


def declare_variable(
    role: str,
    measurement: str | None = None,
    derived_from: Sequence[str] | None = None,
    bounds: Sequence[float] | None = None,
    event_level: str | int | float | None = None,
    trials: str | None = None,
    exposure_column: str | None = None,
    exposure_scale: str | None = None,
) -> dict[str, Any]:
    """An entry of the variables block, with the members of ``exposure`` as
    ``exposure_column`` and ``exposure_scale``.

    Examples:
        >>> declare_variable("outcome", measurement="count", exposure_column="days",
        ...                  exposure_scale="raw")
        {'role': 'outcome', 'measurement': 'count', 'exposure': {'column': 'days', 'scale': 'raw'}}
    """
    if bounds is not None and (
        isinstance(bounds, str)
        or len(bounds) != 2
        or not all(isinstance(b, int | float) and not isinstance(b, bool) for b in bounds)
    ):
        raise TypeError("'bounds' must be None or two numbers.")
    if event_level is not None and (
        isinstance(event_level, bool) or not isinstance(event_level, str | int | float)
    ):
        raise TypeError("'event_level' must be None, a str or a number.")
    exposure = _entry(
        column=_string(exposure_column, "exposure_column"),
        scale=_string(exposure_scale, "exposure_scale"),
    )
    return _entry(
        role=_string(role, "role"),
        measurement=_string(measurement, "measurement"),
        derived_from=_strings(derived_from, "derived_from"),
        bounds=list(bounds) if bounds is not None else None,
        event_level=event_level,
        trials=_string(trials, "trials"),
        exposure=exposure or None,
    )


def declare_estimand(
    id: str,
    term: str,
    kind: str | None = None,
    focal: bool | None = None,
    outcome: str | None = None,
) -> dict[str, Any]:
    """An estimand of the estimands block. Absent, ``focal`` is true.

    Examples:
        >>> declare_estimand("itt", "arm", kind="total_effect")
        {'id': 'itt', 'term': 'arm', 'kind': 'total_effect'}
    """
    if focal is not None and not isinstance(focal, bool):
        raise TypeError("'focal' must be None, True or False.")
    return _entry(
        id=_string(id, "id"),
        term=_string(term, "term"),
        kind=_string(kind, "kind"),
        focal=focal,
        outcome=_string(outcome, "outcome"),
    )


def _entry(**members: Any) -> dict[str, Any]:
    """The members that are not None."""
    return {k: v for k, v in members.items() if v is not None}


def _string(x: Any, name: str) -> str | None:
    if x is not None and not isinstance(x, str):
        raise TypeError(f"'{name}' must be None or a str.")
    return x


def _strings(x: Any, name: str) -> list[str] | None:
    if x is None:
        return None
    if isinstance(x, str) or not isinstance(x, Sequence) or not all(isinstance(v, str) for v in x):
        raise TypeError(f"'{name}' must be None or a list of str.")
    return list(x)


def _object(x: Any, name: str) -> dict[str, Any] | None:
    if x is not None and not isinstance(x, Mapping):
        raise TypeError(f"'{name}' must be None or a dict.")
    return None if x is None else dict(x)


def _entries(x: Any, name: str) -> list[Any] | None:
    if x is None:
        return None
    if isinstance(x, str | Mapping) or not isinstance(x, Sequence):
        raise TypeError(f"'{name}' must be None or a list of entries.")
    return list(x)


def draft_design(
    data: pandas.DataFrame | str | os.PathLike[str],
    formula: str,
    coding: Mapping[str, Mapping[str, Any]] | None = None,
) -> Any:
    """Draft a design declaration from the data.

    Writes a declaration pre-filled from what the data and the formula show,
    with every entry listed in ``/provenance/inferred``, so that it is a draft:
    each entry counts as absent for every check until the user accepts it by
    removing its pointer (declarations.md, provenance). The draft reads only
    the grouping columns of the formula and never the outcome, whose column it
    names from the formula alone.

    The draft holds a unit for each grouping column that is not a predictor,
    in the order of the formula. A unit is nested, with id_scope 'global', in
    the unit with the most labels among those of which each of its labels
    meets exactly one label in the rows where both are present, when the
    reverse does not hold. Labels reused within parents, as class labels 1, 2
    and 3 in every school, look like crossed units in the data (02-decisions.md,
    Q4), so the draft never infers id_scope 'within_parent', and a grouping
    such as ``(1 | school/class)`` does not decide it either, since the
    formula writes crossed factors in the same way. Two units neither of which is nested in
    the other, directly or through other units, are crossed when a label of
    each meets two or more labels of the other. The observation key is the
    first set of grouping columns, by size and then in the order of the units,
    whose values identify every row and are never missing. The response is
    declared with the role outcome. Roles of units, assignments, measurement
    levels and estimands cannot be read from the data and are left to the
    user.

    Args:
        data, formula, coding: As :func:`audit` takes them.

    Returns:
        The draft declaration, as :func:`validate_declaration` returns it.

    Raises:
        MixedcheckError, TypeError, ValueError: The errors of :func:`audit`
            for the data, the formula and the coding.

    Examples:
        >>> fixture = pathology_zoo("Z01")
        >>> draft = draft_design(fixture["data"], fixture["formula"])
        >>> draft["provenance"]["inferred"][0]
        '/units/0'
    """
    arguments = audit_arguments(
        data, formula, None, coding, None, None, "T0", None, False, None, "shareable", _PLAN_KEY
    )
    table = run_data(data, None).table
    ir = build_formula_ir(arguments.formula, None, table, arguments.coding, None, [])
    run = Run.__new__(Run)
    run.table = table
    run.cache = {}
    # The grouping columns in order, other than predictors, such as the
    # factor f of (1 | g:f).
    columns: list[str] = []
    for term in ir["random"]:
        for column in term["grouping"]:
            if column not in columns and column not in ir["predictors"]:
                columns.append(column)
    names = _unit_names(columns)

    def rows_of(a: str, b: str) -> Any:
        missing = table.missing[column_index(run, a)] | table.missing[column_index(run, b)]
        return np.flatnonzero(~missing)

    def within(a: str, b: str) -> bool:
        """Whether each label of a meets exactly one label of b where both are
        present."""
        rows = rows_of(a, b)
        if len(rows) == 0:
            return False
        codes_a = column_codes(run, a)[rows]
        pairs = set(zip(codes_a.tolist(), column_codes(run, b)[rows].tolist(), strict=True))
        return len(pairs) == len(set(codes_a.tolist()))

    def label_count(a: str) -> int:
        codes = column_codes(run, a)
        return len(set(codes[codes >= 0].tolist()))

    units: list[dict[str, Any]] = []
    parent_of: list[int | None] = [None] * len(columns)
    for i, column in enumerate(columns):
        unit: dict[str, Any] = {"name": names[i], "columns": [column]}
        candidates = [
            j
            for j in range(len(columns))
            if j != i and within(column, columns[j]) and not within(columns[j], column)
        ]
        if candidates:
            counts = [label_count(columns[j]) for j in candidates]
            parent_of[i] = candidates[counts.index(max(counts))]
            unit["nested_in"] = names[candidates[counts.index(max(counts))]]
            unit["id_scope"] = "global"
        units.append(unit)

    def ancestors(i: int) -> list[int]:
        found: list[int] = []
        parent = parent_of[i]
        while parent is not None and parent not in found:
            found.append(parent)
            parent = parent_of[parent]
        return found

    crossings = []
    for i in range(len(columns)):
        for j in range(i + 1, len(columns)):
            if j in ancestors(i) or i in ancestors(j):
                continue
            if _crossed(run, rows_of(columns[i], columns[j]), columns[i], columns[j]):
                crossings.append({"units": [names[i], names[j]]})
    key = _draft_key(run, columns)
    draft: dict[str, Any] = {"vocabulary": "0.1.0"}
    inferred: list[str] = []
    if units:
        draft["units"] = units
        inferred += [path_pointer("units", i) for i in range(len(units))]
    if crossings:
        draft["crossings"] = crossings
        inferred += [path_pointer("crossings", i) for i in range(len(crossings))]
    if key:
        draft["observation"] = {"key": key}
        inferred.append("/observation/key")
    response = ir.get("response")
    if response is not None:
        draft["variables"] = {response["variable"]: {"role": "outcome"}}
        inferred.append(path_pointer("variables", response["variable"]))
    draft["provenance"] = {"created": utc_timestamp(run_time())}
    if inferred:
        draft["provenance"]["inferred"] = inferred
    return validate_declaration(draft)


def _unit_names(columns: list[str]) -> list[str]:
    """Unit names for grouping columns: the column name when it is a valid name
    of a unit (defs.schema.json, name), and otherwise 'unit' followed by the
    position of the column, counted from 1, with '_' and a number added until
    the name differs from those before it."""
    found: list[str] = []
    for i, column in enumerate(columns):
        name = column if _UNIT_NAME.fullmatch(column) else "unit" + str(i + 1)
        base = name
        k = 1
        while name in found:
            k += 1
            name = base[:60] + "_" + str(k)
        found.append(name)
    return found


def _crossed(run: Run, rows: Any, a: str, b: str) -> bool:
    """Whether a label of each of two columns meets two or more labels of the
    other in the rows given."""
    if len(rows) == 0:
        return False
    pairs = set(
        zip(column_codes(run, a)[rows].tolist(), column_codes(run, b)[rows].tolist(), strict=True)
    )
    first = Counter(p[0] for p in pairs)
    second = Counter(p[1] for p in pairs)
    return max(first.values()) >= 2 and max(second.values()) >= 2


def _draft_key(run: Run, columns: list[str]) -> list[str]:
    """The first set of columns, by size and then in the order given, whose
    values are present in every row and identify the rows of the table."""
    present = [c for c in columns if not run.table.missing[column_index(run, c)].any()]
    for size in range(1, len(present) + 1):
        for chosen in itertools.combinations(present, size):
            codes = value_codes(run, list(chosen))
            if len(np.unique(codes)) == len(codes):
                return list(chosen)
    return []
