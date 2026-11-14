"""The machinery of the checks of the registry (docs/spec/registry.md and
documents.md, Findings), which :func:`audit` runs in steps 10 and 11
(03-execution-plan.md, M2). The compiled registry drives it: the order of the
checks, the family filter, availability, the scope elements, the kinds and
count classes of the statistics, ratios, quantiles, the decision with its
thresholds, threshold proximity, validation, assessability, the rendering of
messages, the support, the resolution of by_unit counts and the order of the
findings.

A check is one function, named ``check_`` followed by its identifier with '.'
written as '_', such as ``check_keys_duplicates()``, in the module of its
prefix, ``mixedcheck._checks_<prefix>`` (_checks_keys.py), which
:func:`check_implementation` finds from the identifier. It is called as
``f(run, entry, elements)``:

- ``run`` is the :class:`Run` of the audit, with the declaration, the table,
  the IR, the samples, X and Z, the response at T1 and T2 and the findings of
  the checks that the entry requires in ``run.results``. The functions of this
  module, such as :func:`sample_rows`, :func:`value_codes`,
  :func:`factor_keys`, :func:`factor_levels`, :func:`random_term_values` and
  :func:`unit_label_columns`, read it.
- ``entry`` is the registry entry of the check, a dict as the compiled registry
  holds it.
- ``elements`` are the elements of the entry's scope (:func:`scope_elements`),
  each a dict of its parts.

It returns :func:`check_unavailable` when an availability rule of the entry
other than package_missing holds, the first in the entry's order, since the
machinery checks the package_missing rules, which come first in every entry,
before calling it. Otherwise, it returns a list with one item for each element:
None when applies_when does not hold for the element, and otherwise
:func:`check_element` with the statistics of the element and the conditions
of the decision and assessability rules. The machinery computes the ratios
from their counts and does everything else.

Rows of the table are counted from 0 here, where the R package counts them
from 1. Codes of values and levels are int64 arrays counted from 0, with -1
where R has NA.
"""

from __future__ import annotations

import importlib
import importlib.util
import math
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, TypeAlias

from mixedcheck._declaration import path_pointer
from mixedcheck._design import DesignBuilt, DesignModel, sequential_rule
from mixedcheck._errors import display_text, internal_error
from mixedcheck._formula_ir import ModelTable, exact_sum
from mixedcheck._messages import render_message
from mixedcheck._registry import registry_document, registry_entries_by_id
from mixedcheck._times import run_time, utc_timestamp
from mixedcheck._unicode import comparison_form, sort_identifiers

if TYPE_CHECKING:
    import numpy

    Array: TypeAlias = numpy.ndarray[Any, Any]

# The tiers in order.
TIERS = ("T0", "T1", "T2")

# The kinds of statistics whose values are lists.
LIST_KINDS = ("names", "labels", "reals")


# --- What a check returns ------------------------------------------------------------


@dataclass
class CheckElement:
    """The result of a check for one scope element.

    - ``statistics``: the internal values of the statistics, by name, leaving
      out those that the definition leaves absent and every ratio, which the
      machinery computes from its numerator and denominator. A count is an int
      (or an integral float or numpy integer), a real a float (NaN and the
      infinities included), reals a sequence of floats, a category a str, a
      boolean a bool, names and labels sequences of str.
    - ``rules``: whether the condition of each rule of the decision holds, in
      the entry's order. :func:`threshold_holds` compares a statistic with a
      threshold.
    - ``assessability``: whether the condition of each assessability rule
      holds, in the entry's order.
    - ``items``: for a by_unit statistic resolved by a statistic of kind names,
      the item that the statistic holds, by the statistic's name: the column
      keys whose combined values form its levels, as a list of str, or the
      level of each row of the table as an int64 array of codes with -1 for a
      row without a level. Without it, the one name that the statistic holds
      is taken as a grouping factor, a column or a unit, in that order.
    - ``proximity``: for each parameter with a proximity_factor, by name, the
      computed values that the entry compares with it, as a sequence of floats
      or as :func:`compared_values` with a bound on the rounding error of each
      when the definition gives one.
    - ``near_threshold``: True when the definition makes the finding
      near_threshold for another reason.
    - ``rows``: the rows of the table, from 0, that the statistics count, over
      which by_unit counts are resolved, by default the rows of the entry's
      sample. The privacy filter treats other rows, such as the rows of an
      assignment, as a sample of their own.
    - ``label_factors``: for a statistic of kind labels, the grouping factor or
      column whose labels it holds, by the statistic's name, which the privacy
      filter pairs with each label to give it a pseudonym.
    """

    statistics: dict[str, Any]
    rules: list[bool] = field(default_factory=list)
    assessability: list[bool] = field(default_factory=list)
    items: dict[str, Any] = field(default_factory=dict)
    proximity: dict[str, Any] = field(default_factory=dict)
    near_threshold: bool = False
    rows: Array | None = None
    label_factors: dict[str, str] = field(default_factory=dict)


def check_element(
    statistics: Mapping[str, Any],
    rules: Sequence[bool] = (),
    assessability: Sequence[bool] = (),
    items: Mapping[str, Any] | None = None,
    proximity: Mapping[str, Any] | None = None,
    near_threshold: bool = False,
    rows: Array | None = None,
    label_factors: Mapping[str, str] | None = None,
) -> CheckElement:
    """The result of a check for one scope element (:class:`CheckElement`)."""
    return CheckElement(
        dict(statistics),
        [bool(rule) for rule in rules],
        [bool(rule) for rule in assessability],
        dict(items or {}),
        dict(proximity or {}),
        bool(near_threshold),
        rows,
        dict(label_factors or {}),
    )


@dataclass
class Unavailable:
    """A check that is not available as a whole: the reason of its availability
    rule and, for too_large, declaration_missing and capability_missing, the
    detail that picks the rule or that the rule lacks."""

    reason: str
    detail: str | None = None


def check_unavailable(reason: str, detail: str | None = None) -> Unavailable:
    """A check that is not available, for the first availability rule of the
    entry with this reason or, for too_large and declaration_missing, for the
    rule whose parameter or pointer is ``detail`` when it is given. ``detail``
    is needed otherwise only for capability_missing, whose rule names no
    capability."""
    return Unavailable(reason, detail)


@dataclass
class ComparedValues:
    """Values that a check compares with a parameter that has a proximity
    factor, each with a bound on its rounding error (registry.md, Parameters)."""

    values: Any
    bound: Any


def compared_values(values: Any, bounds: Any) -> ComparedValues:
    """Values compared with a parameter that has a proximity factor, with a
    bound on the rounding error of each, so that a value within its bound of
    the parameter's value makes the finding near_threshold."""
    return ComparedValues(values, bounds)


# --- Findings -------------------------------------------------------------------------


@dataclass
class Support:
    """The support of the findings of a sample (documents.md, Support): its
    rows, the basis of its contributors, the number of distinct contributors,
    whether the dominance rule fails and, for the privacy filter, the summed
    rows of the largest contributors, by grouping factor for the basis
    grouping_factors."""

    rows: int
    basis: str
    distinct: int
    dominated: bool
    largest: int | dict[str, int]


@dataclass
class Finding:
    """A finding inside a run, before it is written (:func:`document_finding`).

    A finding that is not available as a whole has ``available`` False and its
    ``availability``. An available finding has its status fields, message,
    statistics (by name, each with its kind, count class and the quantile of
    its entry), values, support, the items of its by_unit statistics, the rows
    over which they resolve, its entry, the position of the decision rule that
    decided it (None for 'otherwise') and the factors of its labels. The
    privacy filter marks suppressed values in ``suppressed`` and
    ``support_suppressed``, by name with the detail of the rule, and a finding
    suppressed as a whole with ``whole``, marks with ``guarded`` a finding of
    a T1 or T2 check on an item of crossed columns that step 9 suppresses as a
    whole and with ``bounded`` one below the minimum count whose contributors
    the findings on the analysis sample bound from below by k - 1, records in
    ``with_rows`` events and non_events when step 7 suppresses them with the
    rows of the analysis sample alone, which step 9 reads as written, and
    records in ``left_written`` the statistics that its steps 1 to 5 left
    written.
    """

    check: str
    check_version: int
    tier: str
    scope: dict[str, str]
    available: bool
    availability: dict[str, Any] | None = None
    status: dict[str, Any] = field(default_factory=dict)
    message: dict[str, str] | None = None
    statistics: dict[str, dict[str, Any]] = field(default_factory=dict)
    values: dict[str, Any] = field(default_factory=dict)
    support: Support | None = None
    items: dict[str, list[Array | None]] = field(default_factory=dict)
    rows: Array | None = None
    entry: dict[str, Any] | None = None
    rule: int | None = None
    label_factors: dict[str, str] = field(default_factory=dict)
    suppressed: dict[str, str] = field(default_factory=dict)
    whole: bool = False
    guarded: bool = False
    bounded: bool = False
    with_rows: list[str] = field(default_factory=list)
    support_suppressed: dict[str, str] = field(default_factory=dict)
    left_written: list[str] = field(default_factory=list)


# --- The run ---------------------------------------------------------------------------


@dataclass
class Disclosure:
    """The disclosure unit (conventions.md, Declaration fields): its name, its
    source, its label columns as keys and the code of the member of each row
    of the table, -1 when a label column is missing."""

    name: str
    source: str
    columns: list[str]
    codes: Array


@dataclass
class OutcomeReads:
    """The columns of the outcome that a check read at its tier."""

    tier: str
    columns: list[str]


@dataclass
class Run:
    """A run after step 8 of :func:`audit`, which the checks read.

    - ``declaration``: the declaration as validate_declaration() returned it,
      or None.
    - ``table``: the table (``ModelTable``), with the names, keys (comparison
      forms), values, types and missing values of its columns.
    - ``ir``: the IR, a dict as formula_ir() returns it.
    - ``family_class`` and ``tier``: the family class and the highest tier.
    - ``design``: the rows of the design sample, from 0.
    - ``analysis``, ``response`` and ``trials``: the rows of the analysis
      sample and the response and trials vectors over them, set in step 9 at
      T1 and T2, and None at T0. Checks read them through
      :func:`outcome_values`.
    - ``x``, ``x_columns`` and ``x_kept``: X over the design sample, the names
      of its columns and whether the sequential rule keeps each.
    - ``z`` and ``z_columns``: Z over the design sample, a
      ``scipy.sparse.csc_array``, and the description of its columns.
    - ``offset`` and ``weights``: the vectors over the design sample, or None.
    - ``factors``: the column keys of each grouping factor, by name, in the
      order in which the factors first arise in the IR.
    - ``grouping_columns``: the grouping columns, in order of first use.
    - ``results``: the findings of each check that has run, by identifier.
    - ``outcome_reads``: the reads of the outcome that the access log must
      record.
    - ``packages``: the packages whose results the findings use, by name with
      their versions, which ``software.packages`` records.
    - ``cache``: values computed once for the run, by key.
    - ``disclosure``: the disclosure unit, or None.
    - ``analysis_kept``: whether the sequential rule keeps each column of X on
      the analysis sample, which outcome.separation sets and the privacy
      filter reads, or None.
    """

    declaration: Any
    table: ModelTable
    ir: dict[str, Any]
    family_class: str
    tier: str
    design: Array
    x: Array
    x_columns: list[str]
    x_kept: list[bool]
    z: Any
    z_columns: Any
    offset: Array | None
    weights: Array | None
    factors: dict[str, list[str]]
    grouping_columns: list[str]
    analysis: Array | None = None
    response: Array | None = None
    trials: Array | None = None
    results: dict[str, list[Finding]] = field(default_factory=dict)
    outcome_reads: list[OutcomeReads] = field(default_factory=list)
    packages: dict[str, str] = field(default_factory=dict)
    cache: dict[str, Any] = field(default_factory=dict)
    disclosure: Disclosure | None = None
    analysis_kept: list[bool] | None = None


def new_run(
    declaration: Any,
    table: ModelTable,
    ir: dict[str, Any],
    family_class: str,
    tier: str,
    model: DesignModel,
    built: DesignBuilt,
) -> Run:
    """The run after step 8, which the checks read."""
    factors: dict[str, list[str]] = {}
    for term in ir["random"]:
        if term["factor"] not in factors:
            factors[term["factor"]] = list(term["grouping"])
    grouping_columns = list(dict.fromkeys(key for term in ir["random"] for key in term["grouping"]))
    run = Run(
        declaration=declaration,
        table=table,
        ir=ir,
        family_class=family_class,
        tier=tier,
        design=model.design,
        x=built.x,
        x_columns=built.x_columns,
        x_kept=built.kept,
        z=built.z,
        z_columns=built.z_columns,
        offset=built.offset,
        weights=built.weights,
        factors=factors,
        grouping_columns=grouping_columns,
    )
    run.disclosure = disclosure_unit(run)
    return run


def sample_rows(run: Run, sample: str) -> Array:
    """The rows of the table, counted from 0, in a sample: 'table', 'design' or
    'analysis'."""
    import numpy as np

    if sample == "table":
        return np.arange(run.table.rows, dtype=np.int64)
    if sample == "design":
        return run.design
    if sample == "analysis":
        if run.analysis is None:
            internal_error("the analysis sample was not read.")
        return run.analysis
    internal_error(f"the sample '{sample}' is not known.")


def column_index(run: Run, key: str) -> int:
    """The position of a column in the table, by its comparison form."""
    j = run.table.index(key)
    if j is None:
        internal_error(f"the table has no column '{display_text(key)}'.")
    return j


def first_codes(values: Any) -> Array:
    """Codes of the values of a one-dimensional array, from 0 in order of first
    appearance, so that two values have the same code exactly when they are
    equal. Numbers are compared by value, with NaN equal to NaN and negative
    zero equal to zero, as R's match() compares them, strings as they are,
    without NFC, and None is a value like any other. R's
    match(x, unique(x)) gives these codes plus 1."""
    import numpy as np
    import pandas as pd

    codes, _ = pd.factorize(values, use_na_sentinel=False)
    return np.asarray(codes, dtype=np.int64)


def column_codes(run: Run, key: str) -> Array:
    """The codes of the values of one column in every row of the table,
    compared by value as the table reader compares keys (registry.md, Terms):
    strings after NFC, numbers by value with NaN equal to NaN and negative zero
    equal to zero, and booleans by value. The codes count from 0 in order of
    first appearance, and a missing value has the code -1. The result is
    cached and must not be changed."""
    import numpy as np

    j = column_index(run, key)
    cache_key = f"codes:{j}"
    cached = run.cache.get(cache_key)
    if cached is not None:
        return cached  # type: ignore[no-any-return]
    table = run.table
    values = table.values[j]
    missing = table.missing[j]
    present = ~missing
    codes = np.full(table.rows, -1, dtype=np.int64)
    kept = values[present]
    if table.types[j] == "string":
        forms = {value: comparison_form(value) for value in set(kept.tolist())}
        kept = np.array([forms[value] for value in kept.tolist()], dtype=object)
    elif table.types[j] == "number":
        # Adding 0 turns negative zero into zero.
        kept = kept + 0.0
    codes[present] = first_codes(kept)
    codes.setflags(write=False)
    run.cache[cache_key] = codes
    return codes


def value_codes(
    run: Run, keys: Sequence[str], rows: Array | None = None, missing_level: bool = False
) -> Array:
    """The codes of the combined values of several columns in the rows given,
    by default every row of the table, so that two rows have the same code when
    every value is equal. A row with a missing value has the code -1, or, with
    ``missing_level`` True, a missing value counts as a value equal only to a
    missing value. The codes count from 0 in order of first appearance in the
    table."""
    import numpy as np

    n = run.table.rows
    combined = np.zeros(n, dtype=np.int64)
    absent = np.zeros(n, dtype=bool)
    for key in keys:
        codes = column_codes(run, key)
        if missing_level:
            codes = codes + 1
        else:
            absent |= codes < 0
        width = int(codes.max(initial=0)) + 2
        combined = combined * width + codes
        combined[absent] = -1
        found = np.full(n, -1, dtype=np.int64)
        found[~absent] = first_codes(combined[~absent])
        combined = found
    return combined if rows is None else combined[rows]


def tabulate(codes: Array, count: int | None = None) -> Array:
    """The number of times each code from 0 occurs among codes, ignoring codes
    below 0, with ``count`` bins or as many as the largest code needs."""
    import numpy as np

    present = codes[codes >= 0]
    return np.bincount(present, minlength=count or 0).astype(np.int64)


def pair_codes(first: Array, second: Array) -> Array:
    """One code for each pair of codes, from 0 in order of first appearance,
    and -1 for a pair with a missing code."""
    import numpy as np

    width = int(second.max(initial=0)) + 1
    absent = (first < 0) | (second < 0)
    combined = first.astype(np.int64) * width + second
    found = np.full(len(combined), -1, dtype=np.int64)
    found[~absent] = first_codes(combined[~absent])
    return found


def factor_keys(run: Run, factor: str) -> list[str]:
    """The column keys of one grouping factor of the IR."""
    keys = run.factors.get(factor)
    if keys is None:
        internal_error(f"the IR has no grouping factor '{display_text(factor)}'.")
    return keys


# --- The declaration -------------------------------------------------------------------


def declaration_inferred(declaration: Any, pointer: str) -> bool:
    """Whether the entry at a pointer of the declaration counts as absent
    because /provenance/inferred lists the pointer or one above it
    (declarations.md, provenance)."""
    if not isinstance(declaration, dict):
        return False
    inferred = declaration.get("provenance", {}).get("inferred", [])
    return any(p == pointer or pointer.startswith(p + "/") for p in inferred)


def declared_units(declaration: Any) -> dict[str, dict[str, Any]]:
    """The declared units that do not count as absent, by name, each a copy of
    its entry with ``index``, its position in the units block from 0. A unit
    counts as absent when it, its name, its columns or one of its columns is
    inferred (registry.md, Terms), and a unit nested with id_scope
    'within_parent' in a unit that counts as absent counts as absent too,
    since its levels cannot be formed without the label columns of its parent,
    recursively."""
    units = declaration.get("units", []) if isinstance(declaration, dict) else []
    found: dict[str, dict[str, Any]] = {}
    for i, unit in enumerate(units):
        pointers = [
            path_pointer("units", i),
            path_pointer("units", i, "name"),
            path_pointer("units", i, "columns"),
        ] + [path_pointer("units", i, "columns", j) for j in range(len(unit["columns"]))]
        if not any(declaration_inferred(declaration, pointer) for pointer in pointers):
            found[unit["name"]] = {**unit, "index": i}
    while True:
        orphans = [
            name
            for name, unit in found.items()
            if unit.get("id_scope") == "within_parent"
            and unit_nesting_declared(declaration, unit)
            and unit["nested_in"] not in found
        ]
        if not orphans:
            return found
        for name in orphans:
            del found[name]


def unit_nesting_declared(declaration: Any, unit: Mapping[str, Any]) -> bool:
    """Whether a declared unit names a parent in nested_in and neither
    nested_in, id_scope nor membership is inferred, so that it counts as
    nested."""
    return "nested_in" in unit and not any(
        declaration_inferred(declaration, path_pointer("units", unit["index"], member))
        for member in ("nested_in", "id_scope", "membership")
    )


def unit_parent(declaration: Any, unit: Mapping[str, Any]) -> dict[str, Any] | None:
    """The parent of a declared unit, or None when the unit is not nested, its
    nesting counts as absent or its parent counts as absent (registry.md,
    Terms)."""
    if not unit_nesting_declared(declaration, unit):
        return None
    return declared_units(declaration).get(unit["nested_in"])


def unit_label_columns(declaration: Any, name: str) -> list[str]:
    """The label columns of a declared unit, as keys: its columns, preceded,
    while it is nested in its parent with id_scope 'within_parent', by the
    label columns of the parent, recursively (registry.md, Terms)."""
    unit = declared_units(declaration).get(name)
    if unit is None:
        internal_error(f"no declared unit is named '{display_text(name)}'.")
    columns = [comparison_form(column) for column in unit["columns"]]
    parent = unit_parent(declaration, unit)
    if parent is not None and unit.get("id_scope") == "within_parent":
        columns = list(dict.fromkeys(unit_label_columns(declaration, parent["name"]) + columns))
    return columns


def disclosure_unit(run: Run) -> Disclosure | None:
    """The disclosure unit (conventions.md, Declaration fields): the unit that
    disclosure_unit names, with the source 'declared', or the one declared
    unit with the role 'participant', with the source 'participant', with the
    code of the member of each row of the table, -1 when a label column is
    missing."""
    declaration = run.declaration
    units = declared_units(declaration)
    name = declaration.get("disclosure_unit") if isinstance(declaration, dict) else None
    source = "declared"
    if name is None or declaration_inferred(declaration, "/disclosure_unit") or name not in units:
        participants = [
            unit_name
            for unit_name, unit in units.items()
            if unit.get("role") == "participant"
            and not declaration_inferred(declaration, path_pointer("units", unit["index"], "role"))
        ]
        if len(participants) != 1:
            return None
        name = participants[0]
        source = "participant"
    columns = unit_label_columns(declaration, name)
    return Disclosure(name, source, columns, value_codes(run, columns))


def declared_role_columns(declaration: Any, roles: Sequence[str]) -> list[str]:
    """The comparison forms of the columns that the declaration gives one of the
    roles, whether or not /provenance/inferred lists the role, since a column
    that may hold the outcome is kept from the outcome-blind checks either
    way."""
    variables = declaration.get("variables", {}) if isinstance(declaration, dict) else {}
    return [
        comparison_form(name) for name, entry in variables.items() if entry.get("role") in roles
    ]


def role_columns(declaration: Any, roles: Sequence[str] | None = None) -> list[str]:
    """The columns, as the declaration names them, to which it gives a role
    that /provenance/inferred does not list, or one of the roles given."""
    variables = declaration.get("variables", {}) if isinstance(declaration, dict) else {}
    return [
        name
        for name, entry in variables.items()
        if "role" in entry
        and (roles is None or entry["role"] in roles)
        and not declaration_inferred(declaration, path_pointer("variables", name, "role"))
    ]


def assignment_elements(declaration: Any) -> list[dict[str, str]]:
    """The entries of the assignment block that do not count as absent: an
    entry counts as absent when it, its column or its unit is inferred, or when
    its unit counts as absent."""
    assignment = declaration.get("assignment", []) if isinstance(declaration, dict) else []
    units = declared_units(declaration)
    found = []
    for i, entry in enumerate(assignment):
        pointer = path_pointer("assignment", i)
        pointers = [pointer, pointer + "/column", pointer + "/unit"]
        if (
            not any(declaration_inferred(declaration, p) for p in pointers)
            and entry["unit"] in units
        ):
            found.append({"column": entry["column"], "unit": entry["unit"]})
    return found


def compared_key_columns(run: Run) -> list[str]:
    """The columns that keys.duplicates compares, and among which
    structure.id_scope_evidence looks for attributes: those that the IR reads and
    those that the declaration gives a role, other than the response, its
    trials column and the columns that the declaration gives the role outcome
    or outcome_derived, as keys in code-point order."""
    ir = run.ir
    declaration = run.declaration
    read = (
        list(ir["predictors"])
        + run.grouping_columns
        + [o["variable"] for o in ir["offsets"]]
        + ([ir["weights"]["variable"]] if "weights" in ir else [])
        + [comparison_form(name) for name in role_columns(declaration)]
    )
    excluded = set(declared_role_columns(declaration, ("outcome", "outcome_derived")))
    response = ir.get("response")
    if response is not None:
        excluded.add(response["variable"])
        if "trials" in response:
            excluded.add(response["trials"])
    return sort_identifiers(key for key in dict.fromkeys(read) if key not in excluded)


def factor_has_intercept(run: Run, factor: str) -> bool:
    """Whether a random term of a grouping factor has an intercept."""
    return any(
        term["factor"] == factor and random_term_has_intercept(term) for term in run.ir["random"]
    )


def random_term_has_intercept(term: Mapping[str, Any]) -> bool:
    """Whether a random term has an intercept, a term without variables."""
    return any(not part["variables"] for part in term["terms"])


# --- Scope elements ---------------------------------------------------------------------


def scope_elements(run: Run, scope: str) -> list[dict[str, str]]:
    """The elements of a scope (registry.md, Scopes), each a dict of its parts,
    before applies_when. The scope of the model is the empty dict."""
    factors = list(run.factors)
    terms = [term["name"] for term in run.ir["fixed"]["terms"] if term["variables"]]
    if scope == "model":
        return [{}]
    if scope == "grouping_factor":
        return [{"factor": factor} for factor in factors]
    if scope == "grouping_factor_or_model":
        return [{"factor": factor} for factor in factors] if factors else [{}]
    if scope == "grouping_factor_pair":
        return _pairs_of(factors)
    if scope == "grouping_column_pair":
        return grouping_column_pairs(run)
    if scope == "fixed_term":
        return [{"term": term} for term in terms]
    if scope == "fixed_term_by_factor":
        return [{"term": term, "factor": factor} for term in terms for factor in factors]
    if scope == "random_term":
        return [{"term": term["name"], "factor": term["factor"]} for term in run.ir["random"]]
    if scope == "assignment":
        return assignment_elements(run.declaration)
    if scope == "column":
        return [{"column": key} for key in sort_identifiers(run.table.keys)]
    internal_error(f"the scope '{scope}' is not known.")


def _pair(a: str, b: str) -> dict[str, str]:
    first, second = sorted((a, b))
    return {"first": first, "second": second}


def _pairs_of(names: list[str]) -> list[dict[str, str]]:
    return [_pair(names[i], names[j]) for i in range(len(names)) for j in range(i + 1, len(names))]


def grouping_column_pairs(run: Run) -> list[dict[str, str]]:
    """The pairs of grouping columns, and the pair of a grouping column with the
    column of the direct parent of its unit when that column is not a grouping
    column, where the unit of a column and its parent list that column
    alone."""
    columns = run.grouping_columns
    found = _pairs_of(columns)
    units = declared_units(run.declaration)

    def single(unit: Mapping[str, Any]) -> str | None:
        listed = unit["columns"]
        return comparison_form(listed[0]) if len(listed) == 1 else None

    for column in columns:
        for unit in units.values():
            if single(unit) != column:
                continue
            parent = unit_parent(run.declaration, unit)
            parent_column = single(parent) if parent is not None else None
            if parent_column is not None and parent_column not in columns:
                found.append(_pair(column, parent_column))
    unique: dict[tuple[str, str], dict[str, str]] = {}
    for pair in found:
        unique.setdefault((pair["first"], pair["second"]), pair)
    return list(unique.values())


# --- What several checks compute ----------------------------------------------------------


def decimal_fraction(text: str) -> tuple[int, int]:
    """A non-negative decimal string as m / 10^d, returned as (m, d)."""
    whole, _, fraction = text.partition(".")
    return int(whole + fraction), len(fraction)


def agreement_fraction(entry: Mapping[str, Any]) -> tuple[int, int]:
    """The parameter agreement of an entry, m / 10^d, as (m, d)."""
    return decimal_fraction(entry["parameters"]["agreement"]["value"])


def parameter_value(entry: Mapping[str, Any], name: str) -> float:
    """The double nearest to the value of a parameter of an entry."""
    return float(entry["parameters"][name]["value"])


def scope_finding(findings: Sequence[Finding], element: Mapping[str, str]) -> Finding | None:
    """The finding of a required check for the same pair, by the parts first
    and second of the scope element, or None when that check yields none for
    it."""
    for finding in findings:
        if finding.scope.get("first") == element.get("first") and finding.scope.get(
            "second"
        ) == element.get("second"):
            return finding
    return None


@dataclass
class TermValues:
    """The columns of a random term over the rows of the design sample:
    ``values``, a matrix with one column for each column of the term,
    ``level``, the level of each row as its position from 0 in the level order
    of ir.md (Z), and ``count``, the number of levels."""

    values: Array
    level: Array
    count: int


def random_term_values(run: Run, t: int) -> TermValues:
    """The columns of the random term at position t of the IR, from 0, over the
    rows of the design sample, read from the stored entries of Z."""
    import numpy as np

    cache_key = f"random:{t}"
    cached = run.cache.get(cache_key)
    if cached is not None:
        return cached  # type: ignore[no-any-return]
    z = run.z
    columns = np.flatnonzero(run.z_columns["term"].to_numpy() == t)
    q = len(run.ir["random"][t]["columns"])
    n = z.shape[0]
    start = int(columns[0])
    end = int(columns[-1]) + 1
    indptr = z.indptr
    stored = np.diff(indptr[start : end + 1])
    entries = np.arange(indptr[start], indptr[end])
    position = np.repeat(np.arange(end - start), stored)
    column = position % q
    row = z.indices[entries]
    values = np.zeros((n, q), dtype=np.float64)
    values[row, column] = z.data[entries]
    level = np.zeros(n, dtype=np.int64)
    first = column == 0
    level[row[first]] = position[first] // q
    found = TermValues(values, level, (end - start) // q)
    run.cache[cache_key] = found
    return found


@dataclass
class FactorLevels:
    """The level of each row of the design sample in a grouping factor, from 0
    in the level order of ir.md (Z), and the number of levels."""

    code: Array
    count: int


def factor_levels(run: Run, factor: str) -> FactorLevels:
    """The level of each row of the design sample in a grouping factor, from the
    first random term of the factor."""
    for t, term in enumerate(run.ir["random"]):
        if term["factor"] == factor:
            found = random_term_values(run, t)
            return FactorLevels(found.level, found.count)
    internal_error(f"the IR has no grouping factor '{display_text(factor)}'.")


def row_patterns(values: Array) -> Array:
    """The rows of a matrix of doubles as codes from 0, compared by value, so
    that two rows have the same code when every value is equal (registry.md,
    Terms)."""
    import numpy as np

    combined = np.zeros(values.shape[0], dtype=np.int64)
    for j in range(values.shape[1]):
        combined = pair_codes(combined, first_codes(values[:, j] + 0.0))
    return combined


@dataclass
class Constancy:
    """Whether groups are constant with the parameter agreement, and whether
    every group has exactly one pattern."""

    constant: bool
    exact: bool


def pooled_constancy(groups: Array, patterns: Array, agreement: tuple[int, int]) -> Constancy:
    """Whether groups are constant in a pattern with the parameter agreement,
    pooled over the groups with at least two rows (registry.md, Terms): the
    rows whose pattern is the most frequent of their group number c, out of n
    rows in these groups, and c x 10^d >= m x n in integer arithmetic. exact is
    whether every group has one pattern. groups and patterns are codes from 0,
    one for each row."""
    import numpy as np

    m, d = agreement
    sizes = np.bincount(groups)
    several = sizes[groups] >= 2
    groups = groups[several]
    patterns = patterns[several]
    cell = pair_codes(groups, patterns)
    counts = np.bincount(cell)
    first = np.full(len(counts), -1, dtype=np.int64)
    unique, index = np.unique(cell, return_index=True)
    first[unique] = index
    owner = groups[first]
    largest = np.zeros(int(groups.max(initial=-1)) + 1, dtype=np.int64)
    np.maximum.at(largest, owner, counts)
    group_count = len(np.unique(groups))
    n = len(groups)
    c = int(largest.sum())
    return Constancy(c * 10**d >= m * n, len(counts) == group_count)


def levels_of_full_rank(
    values: Array,
    level: Array,
    count: int,
    among: Array | None = None,
    difference: bool = False,
) -> Array:
    """For each level of a grouping factor among those given, whether the rank
    by the sequential rule of some columns restricted to the level's rows,
    after the level's first row is subtracted from every row when
    ``difference`` is True, equals the number of columns. The sequential rule
    keeps a single column exactly when it is not 0 in every row, and q columns
    need at least q rows, so the rule itself is applied only to levels with two
    or more columns and at least as many rows. ``level`` holds codes from 0."""
    import numpy as np

    q = values.shape[1]
    chosen = np.ones(count, dtype=bool) if among is None else np.asarray(among, dtype=bool)
    if difference:
        values = values - values[_first_rows(level, count)[level], :]
    if q == 1:
        return chosen & (np.bincount(level[values[:, 0] != 0], minlength=count) > 0)
    sizes = np.bincount(level, minlength=count)
    full = np.zeros(count, dtype=bool)
    candidates = np.flatnonzero(chosen & (sizes >= q))
    if len(candidates):
        order = np.argsort(level, kind="stable")
        bounds = np.concatenate(([0], np.cumsum(sizes)))
        for lev in candidates.tolist():
            rows = order[bounds[lev] : bounds[lev + 1]]
            full[lev] = sum(sequential_rule(np.asfortranarray(values[rows, :]))) == q
    return full


def _first_rows(level: Array, count: int) -> Array:
    """The first row of each level, from 0, or -1 for a level without rows."""
    import numpy as np

    first = np.full(count, -1, dtype=np.int64)
    unique, index = np.unique(level, return_index=True)
    first[unique] = index
    return first


def within_level_rank(x: Array, level: Array, count: int) -> list[bool]:
    """The within-level rank of assignment.design_df and identifiability.df_budget
    for the columns x that the sequential rule keeps: Q, the columns of x, each
    divided by its largest absolute value, made orthonormal in column order by
    two passes of classical Gram-Schmidt over the rows, and Q_d, Q with the
    first row of each level, in table order, subtracted from every row of the
    level. Returns whether the sequential rule keeps each column of Q_d when it
    compares the norm of the column's residual with the tolerance times the
    norm of the same column of Q, which is 1, instead of the norm of the
    column of Q_d. ``level`` holds codes from 0."""
    import numpy as np

    n, p = x.shape
    q = np.array(x, dtype=np.float64, order="F", copy=True)
    for j in range(p if n else 0):
        r = x[:, j] / np.max(np.abs(x[:, j]))
        if j > 0:
            basis = q[:, :j]
            for _ in range(2):
                r = r - basis @ (basis.T @ r)
        norm = math.sqrt(float(np.dot(r, r)))
        if not norm > 0:
            internal_error("a column that the sequential rule keeps has no residual.")
        q[:, j] = r / norm
    first = _first_rows(level, count)
    differences = np.asfortranarray(q - q[first[level], :])
    return sequential_rule(differences, norms=np.ones(p))


def exact_group_sums(x: Array, groups: Array, count: int) -> Array:
    """The exact sum of the finite doubles of each group, rounded once to the
    nearest double, ties to even, as exact_sum() rounds the sum of one list.
    groups gives the group of each value, from 0 to count - 1, and a group
    without values sums to 0. A sum of 0 is +0, as in the R package."""
    import numpy as np

    result = np.zeros(count, dtype=np.float64)
    if len(x) == 0:
        return result
    order = np.argsort(groups, kind="stable")
    sizes = np.bincount(groups, minlength=count)
    bounds = np.concatenate(([0], np.cumsum(sizes)))
    ordered = x[order].tolist()
    for g in np.flatnonzero(sizes).tolist():
        part = ordered[bounds[g] : bounds[g + 1]]
        result[g] = part[0] if len(part) == 1 else exact_sum(part)
    return result + 0.0


@dataclass
class OutcomeValues:
    """The outcome over the rows of the analysis sample: the response and
    trials vectors of step 9, the values of the response column as the table
    holds them, with their type, and the rows."""

    response: Array | None
    trials: Array | None
    values: Array
    type: str
    rows: Array


def outcome_values(run: Run, entry: Mapping[str, Any]) -> OutcomeValues:
    """The outcome over the rows of the analysis sample, for a check of tier T1
    or T2 that the run reached. Every check reads the outcome through this
    function, which records the columns it reads with the check's tier, and
    step 13 refuses to write an access log that lacks an entry for a recorded
    read (:func:`outcome_reads_logged`)."""
    tier = entry["tier"]
    if tier == "T0" or run.analysis is None or TIERS.index(tier) > TIERS.index(run.tier):
        internal_error(f"{entry['id']} read the outcome at a tier that the run did not reach.")
    response = run.ir["response"]
    columns = [response["variable"]] + ([response["trials"]] if "trials" in response else [])
    run.outcome_reads.append(OutcomeReads(tier, columns))
    j = column_index(run, comparison_form(response["variable"]))
    return OutcomeValues(
        run.response,
        run.trials,
        run.table.values[j][run.analysis],
        run.table.types[j],
        run.analysis,
    )


def outcome_reads_logged(run: Run, entries: Sequence[Mapping[str, Any]]) -> None:
    """Refuses an access log that lacks an entry for a column that a check read
    through :func:`outcome_values` at its tier."""
    logged = {(e["tier"], e.get("outcome", {}).get("column", "")) for e in entries}
    for read in run.outcome_reads:
        if not all((read.tier, column) in logged for column in read.columns):
            internal_error("a check read an outcome column that the access log does not record.")


# --- Running the checks ----------------------------------------------------------------------


CheckFunction: TypeAlias = Callable[[Run, dict[str, Any], list[dict[str, str]]], Any]


def check_function_name(id: str) -> tuple[str, str]:
    """The module and the name of the function of a check: the module
    ``mixedcheck._checks_<prefix>`` and ``check_`` followed by the identifier
    with '.' written as '_'."""
    prefix = id.split(".", 1)[0]
    return f"mixedcheck._checks_{prefix}", "check_" + id.replace(".", "_")


def check_implementation(id: str) -> CheckFunction | None:
    """The function of a check, or None for an identifier without one."""
    module_name, function_name = check_function_name(id)
    if importlib.util.find_spec(module_name) is None:
        return None
    module = importlib.import_module(module_name)
    function = getattr(module, function_name, None)
    return function if callable(function) else None


def check_order(entries: Mapping[str, Mapping[str, Any]], tier: str) -> list[str]:
    """The checks that a run of a tier runs, in ascending order of identifier
    after the checks they require (03-execution-plan.md, M2, step 10)."""
    reached = TIERS.index(tier)
    ids = sorted(id for id, entry in entries.items() if TIERS.index(entry["tier"]) <= reached)
    ordered: list[str] = []
    done: set[str] = set()
    pending = set(ids)
    while ids:
        ready = next(
            (
                id
                for id in ids
                if all(r in done or r not in pending for r in entries[id]["links"]["requires"])
            ),
            None,
        )
        if ready is None:
            internal_error("the links of the registry form a cycle.")
        ordered.append(ready)
        done.add(ready)
        ids.remove(ready)
    return ordered


@dataclass
class Checked:
    """The findings of the checks of a run and the time at which the checks of
    each tier started, as UTC timestamps."""

    findings: list[Finding]
    times: dict[str, str]


def run_checks(run: Run) -> Checked:
    """Step 10: each check whose tier the run reached, with the time at which
    the checks of each tier started."""
    entries = registry_entries_by_id()
    started: dict[str, int] = {}
    findings: list[Finding] = []
    for id in check_order(entries, run.tier):
        entry = entries[id]
        if entry["tier"] not in started:
            started[entry["tier"]] = run_time()
        found = run_check(run, entry)
        run.results[id] = found
        findings.extend(found)
    # The time of a tier none of whose checks ran is the time at which the
    # checks ended, and no tier starts before the tier below it.
    times: dict[str, str] = {}
    previous: int | None = None
    for tier in TIERS[: TIERS.index(run.tier) + 1]:
        time = started[tier] if tier in started else run_time()
        if previous is not None:
            time = max(time, previous)
        times[tier] = utc_timestamp(time)
        previous = time
    return Checked(findings, times)


def package_installed(package: str) -> bool:
    """Whether a package can be imported, a function of its own so that the
    tests can take the branch of a package that is not installed."""
    try:
        return importlib.util.find_spec(package) is not None
    except (ImportError, ValueError):
        return False


def run_check(run: Run, entry: dict[str, Any]) -> list[Finding]:
    """One check: the family filter, the availability rules package_missing,
    the function of the check and the findings of the elements for which
    applies_when holds. Every entry of the registry has a function, so an
    entry without one is an internal error."""
    families = entry.get("families")
    if families and run.family_class not in families:
        return []
    implementation = check_implementation(entry["id"])
    if implementation is None:
        internal_error(f"the check {entry['id']} has no function.")
    for rule in entry["availability"]:
        if rule["reason"] != "package_missing":
            break
        for package in rule["packages"].get("Python", []):
            if not package_installed(package):
                return [unavailable_finding(run, entry, "package_missing", package)]
    elements = scope_elements(run, entry["scope"])
    result = implementation(run, entry, elements)
    if isinstance(result, Unavailable):
        return [unavailable_finding(run, entry, result.reason, result.detail)]
    if not isinstance(result, list) or len(result) != len(elements):
        internal_error(f"{entry['id']} returned no result for some scope element.")
    return [
        assemble_finding(run, entry, element, item)
        for element, item in zip(elements, result, strict=True)
        if item is not None
    ]


def unavailable_finding(
    run: Run, entry: Mapping[str, Any], reason: str, detail: str | None = None
) -> Finding:
    """The finding of a check that is not available as a whole, with the detail
    of its availability rule (registry.md, Availability): the declaration
    field, with {outcome} standing for the escaped name of the response, the
    package or the parameter that holds the limit."""
    rules = [
        rule
        for rule in entry["availability"]
        if rule["reason"] == reason
        and (reason != "too_large" or detail is None or rule.get("parameter") == detail)
        and (reason != "declaration_missing" or detail is None or rule.get("pointer") == detail)
    ]
    if not rules:
        internal_error(f"{entry['id']} has no availability rule '{reason}'.")
    rule = rules[0]
    if reason == "declaration_missing":
        response = run.ir.get("response", {}).get("variable", "")
        outcome = response.replace("~", "~0").replace("/", "~1")
        detail = rule["pointer"].replace("{outcome}", outcome)
    elif reason == "too_large":
        detail = rule["parameter"]
    availability: dict[str, Any] = {"value": "not_available", "reason": reason}
    if detail is not None:
        availability["detail"] = detail
    return Finding(
        check=entry["id"],
        check_version=entry["version"],
        tier=entry["tier"],
        scope={},
        available=False,
        availability=availability,
    )


# --- Assembling a finding ---------------------------------------------------------------------


def statistic_value(value: Any, kind: str) -> Any:
    """A value of a statistic in the form that the machinery keeps, or None
    when it does not have the form of its kind: a count as an int, a real as a
    float, reals as a list of floats, a category as a str, a boolean as a bool
    and names and labels as lists of str."""
    import numpy as np

    if kind == "count":
        if isinstance(value, bool | np.bool_):
            return None
        if isinstance(value, int | np.integer):
            return int(value) if value >= 0 else None
        if isinstance(value, float | np.floating):
            number = float(value)
            if math.isfinite(number) and number >= 0 and number.is_integer():
                return int(number)
        return None
    if kind == "real":
        if isinstance(value, float | np.floating):
            return float(value)
        return None
    if kind == "reals":
        if isinstance(value, np.ndarray) and value.dtype.kind == "f" and value.ndim == 1:
            return [float(v) for v in value.tolist()]
        if isinstance(value, list | tuple) and all(
            isinstance(v, float | np.floating) for v in value
        ):
            return [float(v) for v in value]
        return None
    if kind == "category":
        return value if isinstance(value, str) else None
    if kind == "boolean":
        return bool(value) if isinstance(value, bool | np.bool_) else None
    if kind in ("names", "labels"):
        if isinstance(value, str):
            return None
        items = value.tolist() if isinstance(value, np.ndarray) else value
        if isinstance(items, list | tuple) and all(isinstance(v, str) for v in items):
            return list(items)
        return None
    return None


def assemble_finding(
    run: Run, entry: dict[str, Any], scope: dict[str, str], element: Any
) -> Finding:
    """The finding of one scope element from what the check returned: its
    statistics, with the ratios computed from their counts, its status fields,
    its message and its support. The count classes of by_unit statistics are
    resolved in step 11 from the items kept with the finding."""
    if not isinstance(element, CheckElement):
        internal_error(f"{entry['id']} returned a result that is not check_element().")
    defined: dict[str, Any] = entry["statistics"]
    given = element.statistics
    unknown = [name for name in given if name not in defined]
    if unknown:
        internal_error(f"{entry['id']} has no statistic '{unknown[0]}'.")
    values: dict[str, Any] = {}
    for name, value in given.items():
        kind = defined[name]["kind"]
        checked = None if kind == "ratio" else statistic_value(value, kind)
        if checked is None:
            internal_error(f"the statistic '{name}' of {entry['id']} is not a valid {kind}.")
        values[name] = checked
    for name, statistic in defined.items():
        if statistic["kind"] == "ratio":
            a = values.get(statistic["numerator"])
            b = values.get(statistic["denominator"])
            if a is not None and b is not None and b > 0:
                values[name] = a / b
    values = {name: values[name] for name in defined if name in values}
    rules = entry["decision"]["rules"]
    if len(element.rules) != len(rules):
        internal_error(f"{entry['id']} gave no condition for some rule of its decision.")
    chosen = next((i for i, holds in enumerate(element.rules) if holds), None)
    decided = entry["decision"]["otherwise"] if chosen is None else rules[chosen]
    near = finding_near_threshold(entry, values, element)
    status = {
        "assessability": finding_assessability(entry, element),
        "finding": {"value": decided["finding"]},
        "threshold_proximity": {"value": "near_threshold" if near else "clear"},
        "validation": {"value": finding_validation(entry)},
    }
    if entry.get("fitted_model"):
        internal_error("checks of fitted models arrive with Stream A.")
    message_id = decided["message"]
    statistics: dict[str, dict[str, Any]] = {}
    for name in values:
        statistic = defined[name]
        found: dict[str, Any] = {"kind": statistic["kind"]}
        if statistic["kind"] in ("count", "ratio"):
            found["count_class"] = statistic["count_class"]
        if "quantile" in statistic:
            found["quantile"] = statistic["quantile"]
        statistics[name] = found
    for name in values:
        if defined[name]["kind"] == "labels" and not isinstance(
            element.label_factors.get(name), str
        ):
            internal_error(f"{entry['id']} gave no factor for the labels of '{name}'.")
    rows = element.rows if element.rows is not None else sample_rows(run, entry["sample"])
    return Finding(
        check=entry["id"],
        check_version=entry["version"],
        tier=entry["tier"],
        scope=dict(scope),
        available=True,
        status=status,
        message={"id": message_id, "text": render_message(entry, message_id, scope, values)},
        statistics=statistics,
        values=values,
        support=sample_support(run, entry["sample"]),
        items=finding_items(run, entry, scope, element, values),
        rows=rows,
        entry=entry,
        rule=chosen,
        label_factors=dict(element.label_factors),
    )


def finding_assessability(entry: Mapping[str, Any], element: CheckElement) -> dict[str, Any]:
    """The assessability status: the first rule whose condition holds, or
    adequate."""
    rules = entry["assessability"]
    if len(element.assessability) != len(rules):
        internal_error(f"{entry['id']} gave no condition for some assessability rule.")
    chosen = next((i for i, holds in enumerate(element.assessability) if holds), None)
    if chosen is None:
        return {"value": "adequate"}
    rule = rules[chosen]
    status: dict[str, Any] = {"value": rule["value"]}
    if "reason" in rule:
        status["reason"] = rule["reason"]
    if rule.get("reason") == "prerequisite_unmet":
        status["detail"] = rule["prerequisite"]
    return status


def decision_thresholds(entry: Mapping[str, Any]) -> list[str]:
    """The thresholds that the rules of a decision name."""
    names = [name for rule in entry["decision"]["rules"] for name in rule["thresholds"]]
    return list(dict.fromkeys(names))


def finding_validation(entry: Mapping[str, Any]) -> str:
    """The validation status: descriptive when the decision names no threshold
    or a descriptive one (registry.md, Thresholds). Validated thresholds need
    the validation studies that later registries add."""
    values = [
        entry["thresholds"][name]["validation"]["value"] for name in decision_thresholds(entry)
    ]
    if not values or "descriptive" in values:
        return "descriptive"
    internal_error("validated thresholds arrive with the validation studies.")


def finding_near_threshold(
    entry: Mapping[str, Any], values: Mapping[str, Any], element: CheckElement
) -> bool:
    """Whether the finding is near_threshold: a real statistic within the
    proximity band of a threshold that a rule of the decision names, a value
    compared with a parameter that has a proximity factor within its band or
    within its bound of the parameter's value, or the check's own flag
    (registry.md, Thresholds and Parameters)."""
    import numpy as np

    if element.near_threshold:
        return True
    for name in decision_thresholds(entry):
        threshold = entry["thresholds"][name]
        s = values.get(threshold["statistic"])
        band = threshold.get("proximity")
        if band is None or s is None:
            continue
        t = float(threshold["value"])
        width = float(band["absolute"]) + float(band["relative"]) * abs(t)
        if abs(s - t) <= width:
            return True
    for name, compared in element.proximity.items():
        parameter = entry["parameters"].get(name, {})
        factor = parameter.get("proximity_factor")
        if factor is None:
            internal_error(f"the parameter '{name}' of {entry['id']} has no proximity factor.")
        t = float(parameter["value"])
        f = float(factor)
        if isinstance(compared, ComparedValues):
            raw, bound = compared.values, compared.bound
        else:
            raw, bound = compared, 0.0
        s = np.abs(np.asarray(raw, dtype=np.float64).reshape(-1))
        b = np.asarray(0.0 if bound is None else bound, dtype=np.float64)
        with np.errstate(invalid="ignore"):
            near = ((s >= t / f) & (s <= t * f)) | (np.abs(s - t) <= b)
        if bool(near.any()):
            return True
    return False


def threshold_holds(entry: Mapping[str, Any], name: str, values: Mapping[str, Any]) -> bool:
    """Whether a threshold's comparison holds for the statistic it applies to:
    a count in integer arithmetic, a ratio a/b with the value m/10^d by
    comparing a x 10^d with m x b in integer arithmetic, and a real with the
    double nearest to the value (registry.md, Thresholds). An absent statistic
    does not satisfy it."""
    threshold = entry["thresholds"].get(name)
    if threshold is None:
        internal_error(f"{entry['id']} has no threshold '{name}'.")
    statistic = entry["statistics"][threshold["statistic"]]
    value = values.get(threshold["statistic"])
    if value is None:
        return False
    left: Any
    right: Any
    if statistic["kind"] == "ratio":
        m, d = decimal_fraction(threshold["value"])
        left = int(values[statistic["numerator"]]) * 10**d
        right = m * int(values[statistic["denominator"]])
    elif statistic["kind"] == "count":
        left = int(value)
        m, d = decimal_fraction(threshold["value"])
        if d:
            internal_error(f"the threshold '{name}' of {entry['id']} is not an integer.")
        right = m
    else:
        left = float(value)
        right = float(threshold["value"])
    comparator = threshold["comparator"]
    if comparator == "<":
        return bool(left < right)
    if comparator == "<=":
        return bool(left <= right)
    if comparator == ">":
        return bool(left > right)
    if comparator == ">=":
        return bool(left >= right)
    internal_error(f"the comparator '{comparator}' is not known.")


# --- Support ---------------------------------------------------------------------------------


def sample_support(run: Run, sample: str) -> Support:
    """The support of the findings of a sample (documents.md, Support), computed
    once for each sample."""
    cache_key = f"support:{sample}"
    cached = run.cache.get(cache_key)
    if cached is not None:
        return cached  # type: ignore[no-any-return]
    support = rows_support(run, sample_rows(run, sample))
    run.cache[cache_key] = support
    return support


def rows_support(run: Run, rows: Array) -> Support:
    """The support of some rows of the table, as :func:`sample_support` gives it
    for the rows of a sample: the rows, the basis of the contributors, the
    number of distinct contributors, whether the dominance rule fails and the
    summed rows of the largest contributors."""
    import numpy as np

    n = len(rows)
    dominance = registry_document()["privacy"]["dominance"]
    m, d = decimal_fraction(dominance["share"])
    k = int(dominance["contributors"])

    def contributors(codes: Array) -> tuple[int, int, bool]:
        counts = np.bincount(codes[codes >= 0])
        counts = counts[counts > 0]
        largest = sum(largest_counts(counts.tolist(), k))
        return len(counts), largest, n > 0 and largest * 10**d >= m * n

    if run.disclosure is not None:
        distinct, largest, dominated = contributors(run.disclosure.codes[rows])
        return Support(n, "disclosure_unit", distinct, dominated, largest)
    if run.factors:
        found = {
            name: contributors(value_codes(run, keys, rows)) for name, keys in run.factors.items()
        }
        return Support(
            n,
            "grouping_factors",
            min(f[0] for f in found.values()),
            any(f[2] for f in found.values()),
            {name: f[1] for name, f in found.items()},
        )
    _, largest, dominated = contributors(np.arange(n, dtype=np.int64))
    return Support(n, "rows", n, dominated, largest)


def largest_counts(counts: Sequence[int], k: int) -> list[int]:
    """The k largest of some counts."""
    return sorted(counts, reverse=True)[:k]


# --- Count classes ----------------------------------------------------------------------------


def finding_items(
    run: Run,
    entry: Mapping[str, Any],
    scope: Mapping[str, str],
    element: CheckElement,
    values: Mapping[str, Any],
) -> dict[str, list[Array | None]]:
    """The items of the by_unit statistics of a finding, by statistic, as the
    level codes of each row of the table: one item, or two for combinations, or
    None for an item that the finding lacks, such as the factor of a finding
    for the model as a whole."""
    items: dict[str, list[Array | None]] = {}
    for name in values:
        statistic = entry["statistics"][name]
        if statistic.get("count_class") != "by_unit" or "resolved_by" not in statistic:
            continue
        items[name] = [
            item_codes(run, reference, entry["scope"], scope, element, values)
            for reference in statistic["resolved_by"]
        ]
    return items


def item_codes(
    run: Run,
    reference: Mapping[str, str],
    kind: str,
    scope: Mapping[str, str],
    element: CheckElement,
    values: Mapping[str, Any],
) -> Array | None:
    """The level codes of one item of resolved_by. The parts first and second
    name grouping factors in the scope grouping_factor_pair and columns in the
    scope grouping_column_pair."""
    import numpy as np

    name = reference["name"]
    if reference["source"] == "scope":
        value = scope.get(name)
        if value is None:
            return None
        if name == "column":
            keys = [comparison_form(value)]
        elif name in ("first", "second"):
            keys = (
                factor_keys(run, value)
                if kind == "grouping_factor_pair"
                else [comparison_form(value)]
            )
        elif name == "factor":
            keys = factor_keys(run, value)
        elif name == "unit":
            keys = unit_label_columns(run.declaration, value)
        else:
            internal_error(f"the scope part '{name}' is not an item.")
        return value_codes(run, keys)
    given = element.items.get(name)
    if isinstance(given, np.ndarray) and given.dtype.kind in "iu":
        return given.astype(np.int64)
    if given is not None:
        return value_codes(run, list(given))
    held = values.get(name)
    if not isinstance(held, list) or len(held) != 1:
        internal_error(f"the item of '{name}' must be given with the statistic.")
    one = held[0]
    if one in run.factors:
        return value_codes(run, factor_keys(run, one))
    if comparison_form(one) in run.table.keys:
        return value_codes(run, [comparison_form(one)])
    if one in declared_units(run.declaration):
        return value_codes(run, unit_label_columns(run.declaration, one))
    internal_error(f"'{display_text(one)}' is neither a grouping factor, a column nor a unit.")


def resolve_count_class(run: Run, items: Sequence[Array | None], rows: Array) -> str:
    """The class to which a by_unit count resolves over the rows of its finding
    (registry.md, Statistics and counts): person without a disclosure unit or
    when some level of its item, or some combination of the levels of its two
    items that occurs in a row, has at most one member of the disclosure unit,
    and non_person otherwise, also when the item has no level in the rows."""
    import numpy as np

    if run.disclosure is None or not items or any(item is None for item in items):
        return "person"
    first = items[0]
    assert first is not None
    level = first[rows]
    if len(items) == 2:
        second = items[1]
        assert second is not None
        level = pair_codes(level, second[rows])
    member = run.disclosure.codes[rows]
    present = level >= 0
    level = first_codes(level[present])
    member = member[present]
    known = member >= 0
    level_known = level[known]
    pairs = pair_codes(level_known, member[known])
    _, first_index = np.unique(pairs, return_index=True)
    count = int(level.max(initial=-1)) + 1
    members = np.bincount(level_known[first_index], minlength=count)
    return "person" if bool((members <= 1).any()) else "non_person"


def resolve_finding_classes(run: Run, finding: Finding) -> Finding:
    """Step 11: the count class of each by_unit statistic of a finding, resolved
    for the finding. A ratio takes the class of its numerator, which counts the
    levels of the same item as its denominator."""
    if not finding.available:
        return finding
    assert finding.entry is not None and finding.rows is not None
    for name, statistic in finding.statistics.items():
        if statistic.get("count_class") != "by_unit":
            continue
        source = name
        if statistic["kind"] == "ratio":
            source = finding.entry["statistics"][name]["numerator"]
        statistic["count_class"] = resolve_count_class(
            run, finding.items.get(source, []), finding.rows
        )
    return finding


# --- Order and document form -------------------------------------------------------------------


def finding_order_key(check: str, scope: Mapping[str, str]) -> list[str]:
    """The list by which findings are ordered and compared: the check, then the
    name and the NFC form of the value of each part of the scope, in ascending
    order of part name (documents.md, Findings). Python compares lists of str
    element by element, code point by code point, with a prefix first."""
    key = [check]
    for part in sorted(scope):
        key += [part, comparison_form(scope[part])]
    return key


def order_findings(findings: list[Finding]) -> list[Finding]:
    """Step 11: the findings in the order of documents.md (Findings)."""
    return sorted(findings, key=lambda finding: finding_order_key(finding.check, finding.scope))


def suppressed_availability(detail: str) -> dict[str, str]:
    """The availability of a value or a finding that the privacy filter
    suppressed, with the detail of the rule that suppressed it."""
    return {"value": "not_available", "reason": "privacy_suppressed", "detail": detail}


def document_value(value: Any, kind: str) -> Any:
    """A value of a statistic as a document writes it: lists of names, labels
    and reals as lists. The writer writes non-finite reals as the strings of
    the data profile."""
    if kind in LIST_KINDS:
        return list(value)
    return value


def document_finding(finding: Finding) -> dict[str, Any]:
    """A finding in the form that a results document writes it (documents.md,
    Findings and Statistics). An internal document writes every value. A
    shareable document writes the marks of the privacy filter: a suppressed
    value as null with its availability, a finding suppressed as a whole as
    not available, and the n of a quantile only when the count that gives n
    is written."""
    found: dict[str, Any] = {
        "check": finding.check,
        "check_version": finding.check_version,
        "tier": finding.tier,
        "scope": dict(finding.scope),
    }
    if not finding.available:
        found["status"] = {"availability": finding.availability}
        return found
    if finding.whole:
        found["status"] = {"availability": suppressed_availability("decision")}
        return found
    found["status"] = {"availability": {"value": "available"}, **finding.status}
    found["message"] = finding.message
    suppressed = finding.suppressed
    statistics: dict[str, Any] = {}
    for name, statistic in finding.statistics.items():
        written: dict[str, Any]
        if name in suppressed:
            written = {
                "kind": statistic["kind"],
                "value": None,
                "availability": suppressed_availability(suppressed[name]),
            }
        else:
            written = {
                "kind": statistic["kind"],
                "value": document_value(finding.values[name], statistic["kind"]),
            }
        if "count_class" in statistic:
            written["count_class"] = statistic["count_class"]
        if "quantile" in statistic:
            quantile: dict[str, Any] = {"p": float(statistic["quantile"]["p"])}
            n = statistic["quantile"]["n"]
            if finding.values.get(n) is not None and n not in suppressed:
                quantile["n"] = finding.values[n]
            written["quantile"] = quantile
        statistics[name] = written
    found["statistics"] = statistics
    support = finding.support
    assert support is not None
    hidden = finding.support_suppressed

    def reported(member: str, value: int) -> dict[str, Any]:
        if member in hidden:
            return {"value": None, "availability": suppressed_availability(hidden[member])}
        return {"value": value}

    found["support"] = {
        "rows": reported("rows", support.rows),
        "contributors": {
            "basis": support.basis,
            "distinct": reported("distinct", support.distinct),
            "dominated": support.dominated,
        },
    }
    return found
