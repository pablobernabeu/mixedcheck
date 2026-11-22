"""The Stream B plan (02-decisions.md, Q3, and docs/spec/documents.md, Plan,
version 0.1): :func:`design_plan` derives the design-implied ceiling, restricts
it to identifiable terms, builds the outcome-free ladder with its protected set
and writes the plan with its design-plan hash and an execution binding."""

from __future__ import annotations

import copy
import os
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field, replace
from typing import TYPE_CHECKING, Any

from mixedcheck._audit import (
    audit,
    audit_arguments,
    audit_family_class,
    declared_columns_present,
    ir_without_means,
    outcome_blind_columns,
)
from mixedcheck._checks import (
    TIERS,
    Run,
    Unavailable,
    agreement_fraction,
    assignment_elements,
    declaration_inferred,
    declared_units,
    factor_keys,
    factor_levels,
    new_run,
    pooled_constancy,
    unit_label_columns,
    unit_parent,
    value_codes,
)
from mixedcheck._checks_identifiability import check_identifiability_gram_rank
from mixedcheck._commitments import run_data
from mixedcheck._declaration import path_pointer, validate_declaration
from mixedcheck._design import design_build, design_model
from mixedcheck._errors import internal_error, raise_issue
from mixedcheck._formula_ir import (
    ModelTable,
    build_formula_ir,
    coding_input,
    formula_tree,
    random_term_name,
    term_name_of,
)
from mixedcheck._formula_parse import is_random, variable_text
from mixedcheck._json_read import parse_json_bytes
from mixedcheck._json_write import canonical_bytes, canonical_hash
from mixedcheck._registry import registry_document, registry_entries_by_id
from mixedcheck._schema import term_variables
from mixedcheck._times import run_time, utc_timestamp
from mixedcheck._unicode import comparison_form
from mixedcheck._vendored import spec_versions
from mixedcheck._version import __version__

if TYPE_CHECKING:
    import pandas

# The stopping rules of the first 0.x release, with their versions and
# parameters as decimal strings (documents.md, The design section).
RULE_MENU: dict[str, dict[str, Any]] = {
    "localised_backoff": {"id": "localised_backoff", "version": 1, "parameters": {}},
    "protected_lrt": {"id": "protected_lrt", "version": 1, "parameters": {"alpha": "0.2"}},
    "no_reduction": {"id": "no_reduction", "version": 1, "parameters": {}},
}

# The terminal states of the plan vocabulary. This package cannot run
# cluster_robust_cr2, which needs clubSandwich in R (E7307).
TERMINAL_STATES = ("no_confirmatory_model", "cluster_robust_cr2")

# The commitment key of the audits that a plan runs internally. Their documents
# are discarded, so no commitment or pseudonym made with it leaves
# design_plan().
PLAN_KEY = "00" * 32


def design_plan(
    data: pandas.DataFrame | str | os.PathLike[str],
    formula: str,
    declaration: Any = None,
    family: str | None = None,
    coding: Mapping[str, Mapping[str, Any]] | None = None,
    weights: str | None = None,
    sample_columns: Sequence[str] | None = None,
    rule: str = "localised_backoff",
    terminal: str = "no_confirmatory_model",
    outcome_access: str = "T0",
) -> dict[str, Any]:
    """Build a Stream B plan.

    Builds the plan of 02-decisions.md (Q3) for a design, without reading the
    outcome: the design-implied ceiling of each grouping factor, its
    identifiability verdict, an outcome-free ladder of nested rungs with its
    protected set, the stopping rule, the terminal state, the design-plan hash
    and, when statsmodels is installed, an execution binding for statsmodels.

    The formula gives the fixed part and the grouping factors. The random
    slopes it writes are ignored, since the ceiling of each grouping factor is
    derived from the design: its random intercept and a correlated slope for
    every fixed term all of whose variables vary within the factor (Barr et
    al., 2013). A variable varies within a factor unless its value is the same
    within the levels of the factor for at least the share of rows that the
    parameter agreement of structure.within_between gives, pooled over the
    levels with two rows or more, or unless an assignment of the declaration
    declares its level for the unit of the factor. Every categorical predictor
    is frozen as numeric contrast columns, with the contrast and reference
    level of ``coding``, and every rung reads the columns of the ceiling as its
    sample columns, so that all rungs share one design sample.

    Rung 0 is the ceiling restricted to identifiable terms: the random
    intercepts and then the slopes are added one at a time, in the order of the
    IR, and each is kept when the model with it is identified by
    identifiability.gram_rank. The ladder then simplifies correlations before
    it removes variances, one grouping factor at a time in the order of the IR:
    a categorical slope of three or more levels becomes the complex random
    intercepts ``(1 | g) + (1 | g:f)``, and the rest of the block becomes
    uncorrelated terms, as ``||`` writes them. It then drops the unprotected
    slopes, higher-order terms before their marginal terms, and last the
    unprotected random intercepts of factors that have no slope left, one step
    for each rung. A rung that is not identified is left out. The last rung is
    the protected rung.

    The protected set comes from the declaration: the random intercept of every
    grouping factor whose columns are the label columns of a declared unit,
    with the reason randomisation_unit for the unit of a randomised assignment
    and replication_unit otherwise, and for each focal estimand and each
    grouping factor, the slope of the variables of its term that vary within
    the factor: focal_slope for a main effect, focal_interaction_slope for an
    interaction all of whose variables vary within the factor and
    cross_level_interaction_slope for the lower-level part of an interaction
    that some variable crosses levels in. Without a focal estimand, the ladder
    is exploratory: it has no protected set, rule or terminal state and drops
    slopes only. A declaration with focal estimands must be a minimal
    declaration (declarations.md).

    The design section of the plan, which the design-plan hash covers, holds
    every IR with each 'mean' centring as its rule and significant digits, as
    before the data are seen, since a plan is a document to share
    (documents.md, inputs). The counts of the ceiling are those that a
    shareable audit of the ceiling writes, a count that the privacy filter
    suppresses written as ``{"below": k}`` or ``{"suppressed": detail}``.

    Args:
        data: A DataFrame or the path of a CSV file. It must hold the columns
            that the formula reads, but the outcome is never read, so a plan
            made before the data are collected can use a column of missing
            values.
        formula, declaration, family, coding, weights, sample_columns: As
            :func:`audit` takes them.
        rule: The stopping rule: 'localised_backoff', the default,
            'protected_lrt', with alpha 0.2, or 'no_reduction'.
        terminal: The terminal state for when the protected rung fails:
            'no_confirmatory_model'. 'cluster_robust_cr2' is run by the R
            package only.
        outcome_access: The highest tier at which the outcome had been read
            when the plan is made: 'T0' for a plan made outcome-blind, and
            'T1' or 'T2' for one made after outcome inspection, which the plan
            records.

    Returns:
        The plan, a dict in the form that :func:`read_json_strict` returns in
        the hashable profile, which :func:`validate_plan` accepts. Write it
        with ``open(path, "wb").write(canonical_bytes(plan, "hashable"))``.

    Raises:
        MixedcheckError: A plan that cannot be built, with one issue: the
            errors of :func:`audit` for its inputs, the issues of a
            declaration with focal estimands that is not a minimal
            declaration, E7315 for a formula without a random term, E7314 for
            a focal estimand whose term is not a fixed term, E7316 for a
            randomisation unit that is not a grouping factor, E7311 for a
            protected term that cannot enter rung 0, E7312 when the
            declaration protects no random term, E7317 when no random intercept is
            identified, E7313 when
            identifiability.gram_rank is not available and E7307 for
            cluster_robust_cr2.
        TypeError, ValueError: Arguments of the wrong type or value.

    Examples:
        >>> fixture = pathology_zoo("Z05N")
        >>> plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
        >>> plan["design"]["ladder"]
        'exploratory'
    """
    if not isinstance(rule, str) or rule not in RULE_MENU:
        raise ValueError("'rule' must be 'localised_backoff', 'protected_lrt' or 'no_reduction'.")
    if not isinstance(terminal, str) or terminal not in TERMINAL_STATES:
        raise ValueError("'terminal' must be 'no_confirmatory_model' or 'cluster_robust_cr2'.")
    if not isinstance(outcome_access, str) or outcome_access not in TIERS:
        raise ValueError("'outcome_access' must be 'T0', 'T1' or 'T2'.")
    arguments = audit_arguments(
        data,
        formula,
        family,
        coding,
        weights,
        sample_columns,
        "T0",
        None,
        False,
        None,
        "shareable",
        PLAN_KEY,
    )
    if declaration is not None:
        declaration = validate_declaration(declaration)
    focal = focal_estimands(declaration)
    if focal:
        validate_declaration(declaration, minimal=True)
    table = run_data(data, declaration).table
    declared_columns_present(declaration, table.keys)
    base = build_formula_ir(
        arguments.formula,
        declaration,
        table,
        arguments.coding,
        arguments.weights,
        arguments.sample_columns,
    )
    outcome_blind_columns(base, declaration)
    if not base["random"]:
        raise_issue("E7315")
    family_class = audit_family_class(arguments.family, base, declaration)
    if focal and terminal == "cluster_robust_cr2":
        raise_issue("E7307", {"state": terminal}, pointer="/design/terminal/state")
    # The coding with every categorical predictor frozen, and the IR of the
    # formula under it, whose fixed part every rung shares.
    frozen = frozen_coding(coding, base)
    base = build_formula_ir(
        arguments.formula,
        declaration,
        table,
        coding_input(frozen),
        arguments.weights,
        arguments.sample_columns,
    )
    setting = Setting(
        declaration=declaration,
        table=table,
        family_class=family_class,
        raw_coding=frozen,
        weights=arguments.weights,
        sample_columns=list(arguments.sample_columns) + ceiling_read_columns(base),
        fixed_text=formula_fixed_text(arguments.formula),
        response_text=formula_response_text(base),
    )
    base_run = plan_run(base, setting)
    within = varying_within(base_run, declaration)
    # The ceiling, its components and the protected set.
    ceiling = ceiling_state(base, within)
    ceiling_ir = rung_ir(ceiling, setting)
    protected = protected_components(base, declaration, focal, within) if focal else None
    # Rung 0 and the terms left out of it.
    restricted = identifiable_state(ceiling, setting)
    check_protected_entered(protected, restricted.state)
    if restricted.verdict is None:
        raise_issue("E7317")
    ladder = ladder_states(restricted.state, protected, setting)
    rung_irs = [rung_ir(state, setting) for state in ladder.states]
    design: dict[str, Any] = {}
    if declaration is not None:
        design["declaration_hash"] = canonical_hash(declaration, "hashable")
    design["ladder"] = "protected" if focal else "exploratory"
    rungs = []
    for i, ir in enumerate(rung_irs):
        rung: dict[str, Any] = {"ir": ir_without_means(ir)}
        if i > 0:
            rung["step"] = ladder.steps[i]
        rungs.append(rung)
    design["rungs"] = rungs
    if protected is not None:
        design["protected"] = [
            {"factor": c.factor, "variables": list(c.variables), "reason": c.reason}
            for c in protected
        ]
        design["rule"] = copy.deepcopy(RULE_MENU[rule])
        design["terminal"] = {"state": terminal}
    design = parse_json_bytes(canonical_bytes(design, "hashable"), "hashable")
    design_hash = canonical_hash(design, "hashable")
    plan: dict[str, Any] = {
        "plan_version": "0.1.0",
        "created": utc_timestamp(run_time()),
        "language": "Python",
        "versions": {"package": __version__, **spec_versions()},
        "outcome_access": outcome_access,
        "for_preregistration": False,
    }
    if protected is not None:
        plan["rule_evidence"] = "simulated_conditions_only"
    plan["design"] = design
    plan["design_plan_hash"] = design_hash
    plan["ceiling"] = ceiling_section(data, ceiling, ceiling_ir, restricted, setting, arguments)
    plan["verdicts"] = [{"value": verdict} for verdict in ladder.verdicts]
    binding = statsmodels_binding(design, design_hash)
    plan["bindings"] = [] if binding is None else [binding]
    plan = parse_json_bytes(canonical_bytes(plan, "hashable"), "hashable")
    from mixedcheck._plan_validate import validate_plan

    return validate_plan(plan)  # type: ignore[no-any-return]


# --- Inputs ---------------------------------------------------------------------


@dataclass
class Setting:
    """What every rung of a plan shares: the declaration, the table, the
    family class, the frozen coding as the caller would write it, the weights,
    the sample columns of the ceiling and the text of the fixed part and of
    the response."""

    declaration: Any
    table: ModelTable
    family_class: str
    raw_coding: dict[str, dict[str, Any]]
    weights: str | None
    sample_columns: list[str]
    fixed_text: str
    response_text: str


@dataclass
class Focal:
    """A focal estimand: its position in /estimands and the comparison forms
    of the variables of its term."""

    index: int
    variables: list[str]


def focal_estimands(declaration: Any) -> list[Focal]:
    """The focal estimands of a declaration that do not count as absent."""
    if not isinstance(declaration, dict):
        return []
    found = []
    for i, estimand in enumerate(declaration.get("estimands", [])):
        entry = path_pointer("estimands", i)
        pointers = [entry, entry + "/term", entry + "/focal"]
        if any(declaration_inferred(declaration, p) for p in pointers):
            continue
        if estimand.get("focal") is False:
            continue
        found.append(Focal(i, [comparison_form(v) for v in term_variables(estimand["term"])]))
    return found


def frozen_coding(
    coding: Mapping[str, Mapping[str, Any]] | None, ir: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    """The coding argument, as the caller gives it, with frozen set to True for
    every categorical predictor of the IR, since a plan freezes the coding of
    factors before it builds its ladder (02-decisions.md, Q3)."""
    result = {name: dict(entry) for name, entry in (coding or {}).items()}
    keys = {comparison_form(name): name for name in result}
    for name, predictor in ir["predictors"].items():
        if predictor["kind"] != "categorical":
            continue
        if name in keys:
            result[keys[name]]["frozen"] = True
        else:
            result[name] = {"frozen": True}
            keys[name] = name
    return result


def ceiling_read_columns(ir: Mapping[str, Any]) -> list[str]:
    """The columns that the ceiling reads other than the response and its
    trials: the predictors, the grouping variables, the offsets and the
    weights. Every rung names them as sample columns (ir.md, Samples)."""
    columns = list(ir["predictors"])
    for term in ir["random"]:
        columns.extend(term["grouping"])
    columns.extend(o["variable"] for o in ir["offsets"])
    if "weights" in ir:
        columns.append(ir["weights"]["variable"])
    return list(dict.fromkeys(columns))


def formula_fixed_text(formula: str) -> str:
    """The text of the fixed part and the offsets of a formula, cut from the
    formula between the summands that are not random terms, with their signs,
    so that every rung writes the fixed part as the caller wrote it and its
    terms keep the order of their variables (ir.md, Order of terms and
    variables)."""
    tree = formula_tree(formula)
    data = formula.encode("utf-8")
    summands = tree.rhs.summands
    starts = [s.sign_at if s.sign_at is not None else s.expr.start for s in summands]
    ends = starts[1:] + [len(data)]
    pieces = [
        data[starts[i] : ends[i]].decode("utf-8").strip(" \t\r\n")
        for i, s in enumerate(summands)
        if not is_random(s.expr)
    ]
    return " ".join(pieces)


def formula_response_text(ir: Mapping[str, Any]) -> str:
    """The response as a formula writes it, or '' for a one-sided formula."""
    response = ir.get("response")
    if response is None:
        return ""
    text = variable_text(response["variable"])
    return "log(" + text + ")" if response["transform"] == "log" else text


# --- Runs and verdicts --------------------------------------------------------------


def plan_run(ir: dict[str, Any], setting: Setting) -> Run:
    """The run of an IR whose checks a plan reads: the design sample, X and Z."""
    model = design_model(ir, setting.table, analysis=False)
    if len(model.design) == 0:
        raise_issue("E7007", {"sample": "design"})
    built = design_build(ir, model, setting.table)
    return new_run(setting.declaration, setting.table, ir, setting.family_class, "T0", model, built)


def identifiability_verdict(ir: dict[str, Any], setting: Setting) -> str:
    """The verdict of identifiability.gram_rank for an IR, or E7313 when the
    check is not available."""
    run = plan_run(ir, setting)
    entry = registry_entries_by_id()["identifiability.gram_rank"]
    result = check_identifiability_gram_rank(run, entry, [{}])
    if isinstance(result, Unavailable):
        raise_issue("E7313", {"parameter": result.detail})
    element = result[0]
    assert element is not None
    return str(element.statistics["verdict"])


def varying_within(run: Run, declaration: Any) -> dict[str, dict[str, bool]]:
    """Whether each predictor varies within each grouping factor of the run, by
    factor and then by predictor. A declared level of an assignment of the
    predictor to the unit of the factor decides, and otherwise the predictor
    varies unless it is constant within the levels with the parameter
    agreement of structure.within_between (registry.md, Terms)."""
    agreement = agreement_fraction(registry_entries_by_id()["structure.within_between"])
    declared = declared_levels(declaration)
    found: dict[str, dict[str, bool]] = {}
    for factor in run.factors:
        levels = factor_levels(run, factor).code
        keys = set(factor_keys(run, factor))
        varying: dict[str, bool] = {}
        for name in run.ir["predictors"]:
            decided = None
            for level in declared:
                if level.column == name and set(level.columns) == keys:
                    decided = level.level == "within_unit"
                    break
            if decided is None:
                values = value_codes(run, [name], rows=run.design)
                decided = not pooled_constancy(levels, values, agreement).constant
            varying[name] = decided
        found[factor] = varying
    return found


@dataclass
class DeclaredLevel:
    column: str
    level: str
    columns: list[str]


def declared_levels(declaration: Any) -> list[DeclaredLevel]:
    """The declared levels of the assignments that do not count as absent, each
    with the comparison form of its column and the label columns of its
    unit."""
    if not isinstance(declaration, dict):
        return []
    assignment = declaration.get("assignment", [])
    found = []
    for element in assignment_elements(declaration):
        i = next(k for k, a in enumerate(assignment) if a["column"] == element["column"])
        level = assignment[i].get("level")
        if level is None or declaration_inferred(
            declaration, path_pointer("assignment", i, "level")
        ):
            continue
        found.append(
            DeclaredLevel(
                comparison_form(element["column"]),
                level,
                unit_label_columns(declaration, element["unit"]),
            )
        )
    return found


# --- The ceiling and the protected set ---------------------------------------------


@dataclass
class FactorState:
    """The state of one grouping factor in a rung: its name, whether it has its
    random intercept, the names of its slope terms in the order of the fixed
    part with their variables, whether they are correlated with each other
    and the intercept, and the names of the categorical variables whose
    slopes are complex random intercepts (1 | g:f)."""

    factor: str
    intercept: bool
    slopes: list[str]
    slope_variables: list[list[str]]
    correlated: bool = True
    complex: list[str] = field(default_factory=list)


State = list[FactorState]


def copy_state(state: State) -> State:
    return [
        replace(
            s,
            slopes=list(s.slopes),
            slope_variables=[list(v) for v in s.slope_variables],
            complex=list(s.complex),
        )
        for s in state
    ]


def ceiling_state(ir: Mapping[str, Any], within: Mapping[str, Mapping[str, bool]]) -> State:
    """The state of the ceiling: for each grouping factor, its random intercept
    and a correlated slope for every fixed term all of whose variables vary
    within it."""
    state: State = []
    seen: set[str] = set()
    for term in ir["random"]:
        if term["factor"] in seen:
            continue
        seen.add(term["factor"])
        varying = within[term["factor"]]
        slopes = []
        variables = []
        for t in ir["fixed"]["terms"]:
            names = [v["variable"] for v in t["variables"]]
            if names and all(varying[name] for name in names):
                slopes.append(t["name"])
                variables.append(names)
        state.append(FactorState(term["factor"], True, slopes, variables))
    return state


@dataclass
class Component:
    factor: str
    variables: list[str]
    reason: str


def protected_components(
    ir: Mapping[str, Any],
    declaration: Any,
    focal: list[Focal],
    within: Mapping[str, Mapping[str, bool]],
) -> list[Component]:
    """The protected components (02-decisions.md, Q3, and documents.md, The
    design section), in the order of the grouping factors of the IR: the random
    intercept of each factor that is a declared unit, then the slopes that
    focal estimands protect, in the order of the estimands."""
    units = declared_units(declaration)
    randomised = randomisation_units(declaration)
    factor_columns: dict[str, list[str]] = {}
    for term in ir["random"]:
        factor_columns.setdefault(term["factor"], list(term["grouping"]))
    for unit in randomised:
        if not any(unit_is_factor(declaration, unit.name, c) for c in factor_columns.values()):
            raise_issue("E7316", pointer=path_pointer("assignment", unit.index, "unit"))
    fixed_terms = [[v["variable"] for v in t["variables"]] for t in ir["fixed"]["terms"]]
    components: list[Component] = []

    def add(factor: str, variables: list[str], reason: str) -> None:
        for c in components:
            if c.factor == factor and set(c.variables) == set(variables):
                return
        components.append(Component(factor, variables, reason))

    randomised_names = [u.name for u in randomised]
    # The grouping factors that are declared units, whose slopes focal
    # estimands protect, since Q3 protects by-unit slopes.
    unit_factors: list[str] = []
    for factor in within:
        matched = next(
            (name for name in units if unit_is_factor(declaration, name, factor_columns[factor])),
            None,
        )
        if matched is not None:
            unit_factors.append(factor)
            reason = "randomisation_unit" if matched in randomised_names else "replication_unit"
            add(factor, [], reason)
    for estimand in focal:
        t = next((i for i, v in enumerate(fixed_terms) if set(v) == set(estimand.variables)), None)
        if t is None:
            raise_issue("E7314", pointer=path_pointer("estimands", estimand.index, "term"))
        variables = fixed_terms[t]
        for factor in unit_factors:
            varying = within[factor]
            inside = [v for v in variables if varying[v]]
            if not inside:
                continue
            if len(inside) < len(variables):
                reason = "cross_level_interaction_slope"
            elif len(variables) == 1:
                reason = "focal_slope"
            else:
                reason = "focal_interaction_slope"
            slope = next((i for i, v in enumerate(fixed_terms) if set(v) == set(inside)), None)
            if slope is None:
                raise_issue(
                    "E7311",
                    {
                        "term": term_name_of(inside),
                        "factor": factor,
                        "reason": "the fixed part has no term of its variables",
                    },
                )
            add(factor, fixed_terms[slope], reason)
    if not components:
        raise_issue("E7312")
    return components


def unit_is_factor(declaration: Any, name: str, columns: Sequence[str]) -> bool:
    """Whether a grouping factor with the given columns is a declared unit: its
    columns are the label columns of the unit, or those together with the
    columns of the units that it is nested in, as (1 | school/class) writes a
    unit class nested in school whatever its id_scope."""
    if set(unit_label_columns(declaration, name)) == set(columns):
        return True
    unit: dict[str, Any] | None = declared_units(declaration).get(name)
    chain: list[str] = []
    while unit is not None:
        chain.extend(comparison_form(c) for c in unit["columns"])
        unit = unit_parent(declaration, unit)
    return set(chain) == set(columns)


@dataclass
class RandomisationUnit:
    name: str
    index: int


def randomisation_units(declaration: Any) -> list[RandomisationUnit]:
    """The units of the randomised assignments that do not count as absent,
    each with the position of its first assignment, other than the declared
    observation unit, of which each row is one member, so that it has no
    random intercept."""
    if not isinstance(declaration, dict):
        return []
    observation = declaration.get("observation", {}).get("unit")
    if observation is not None and any(
        declaration_inferred(declaration, p) for p in ("/observation", "/observation/unit")
    ):
        observation = None
    units = declared_units(declaration)
    found: list[RandomisationUnit] = []
    for i, a in enumerate(declaration.get("assignment", [])):
        entry = path_pointer("assignment", i)
        pointers = [entry, entry + "/unit", entry + "/randomised"]
        if (
            a.get("randomised") is not True
            or any(declaration_inferred(declaration, p) for p in pointers)
            or a["unit"] not in units
            or a["unit"] == observation
            or a["unit"] in [u.name for u in found]
        ):
            continue
        found.append(RandomisationUnit(a["unit"], i))
    return found


# --- Rung 0 ---------------------------------------------------------------------------


@dataclass
class Restricted:
    state: State
    verdict: str | None
    excluded: list[dict[str, str]]


def identifiable_state(state: State, setting: Setting) -> Restricted:
    """Rung 0 (02-decisions.md, Q3): the ceiling restricted to identifiable
    terms. The random intercepts are added one at a time in the order of the
    factors, then the slopes of each factor in turn, and each is kept when the
    model with it is identified. Returns the state, the verdict of rung 0 and
    the random terms left out, each with its factor and its name as a random
    term of its own."""
    current = [FactorState(s.factor, False, [], [], s.correlated, list(s.complex)) for s in state]
    excluded: list[dict[str, str]] = []
    verdict: str | None = None

    def identified(candidate: State) -> str | None:
        found = identifiability_verdict(rung_ir(candidate, setting), setting)
        return None if found == "not_identified" else found

    for f, s in enumerate(state):
        candidate = copy_state(current)
        candidate[f].intercept = True
        found = identified(candidate)
        if found is None:
            excluded.append(
                {"factor": s.factor, "term": random_term_name(True, s.slopes, s.factor)}
            )
        else:
            current = candidate
            verdict = found
    for f, s in enumerate(state):
        if not current[f].intercept:
            continue
        for k, slope in enumerate(s.slopes):
            candidate = copy_state(current)
            candidate[f].slopes.append(slope)
            candidate[f].slope_variables.append(list(s.slope_variables[k]))
            found = identified(candidate)
            if found is None:
                excluded.append(
                    {"factor": s.factor, "term": random_term_name(False, [slope], s.factor)}
                )
            else:
                current = candidate
                verdict = found
    return Restricted(current, verdict, excluded)


def check_protected_entered(protected: list[Component] | None, state: State) -> None:
    """E7311 for the first protected component that rung 0 lacks."""
    for component in protected or []:
        s = next(x for x in state if x.factor == component.factor)
        if not component.variables:
            present = s.intercept
        else:
            present = any(set(v) == set(component.variables) for v in s.slope_variables)
        if not present:
            raise_issue(
                "E7311",
                {
                    "term": term_name_of(component.variables) if component.variables else "1",
                    "factor": component.factor,
                    "reason": "the design does not identify it",
                },
            )


# --- The ladder -------------------------------------------------------------------


@dataclass
class Ladder:
    states: list[State]
    steps: list[dict[str, Any] | None]
    verdicts: list[str]


def ladder_states(state: State, protected: list[Component] | None, setting: Setting) -> Ladder:
    """The ladder from rung 0 (02-decisions.md, Q3, and documents.md, The
    design section): the states of its rungs, the step that leads to each rung
    after the first and the verdict of each. Correlations are simplified first,
    one grouping factor at a time: each categorical slope of three or more
    levels becomes complex random intercepts, then the rest of the block
    becomes uncorrelated. The unprotected slopes are then dropped, higher-order
    terms first and, among terms of one order, by factor and from the last term
    back, and last the unprotected random intercepts of factors without
    slopes. An exploratory ladder protects nothing but keeps every random
    intercept. A candidate rung that is not identified is left out and the
    ladder continues from the rung before it."""
    ladder = Ladder([state], [None], [identifiability_verdict(rung_ir(state, setting), setting)])

    def try_step(candidate: State, step: dict[str, Any]) -> bool:
        verdict = identifiability_verdict(rung_ir(candidate, setting), setting)
        if verdict == "not_identified":
            return False
        ladder.states.append(candidate)
        ladder.steps.append(step)
        ladder.verdicts.append(verdict)
        return True

    predictors = rung_ir(state, setting)["predictors"]

    def levels_of(variables: list[str]) -> int:
        if len(variables) != 1:
            return 0
        info = predictors[variables[0]]
        return len(info["levels"]) if info["kind"] == "categorical" else 0

    for f in range(len(state)):
        for slope in state[f].slopes:
            current = ladder.states[-1]
            if slope not in current[f].slopes:
                continue
            k = current[f].slopes.index(slope)
            if levels_of(current[f].slope_variables[k]) < 3:
                continue
            candidate = copy_state(current)
            del candidate[f].slopes[k]
            del candidate[f].slope_variables[k]
            candidate[f].complex.append(slope)
            try_step(
                candidate,
                {
                    "kind": "complex_intercepts",
                    "factor": current[f].factor,
                    "terms": [block_name(current[f])],
                },
            )
        current = ladder.states[-1]
        s = current[f]
        if s.correlated and block_columns(s, predictors) >= 2:
            candidate = copy_state(current)
            candidate[f].correlated = False
            try_step(
                candidate, {"kind": "decorrelate", "factor": s.factor, "terms": [block_name(s)]}
            )

    def protects(factor: str, variables: Sequence[str]) -> bool:
        return any(
            c.factor == factor and set(c.variables) == set(variables) for c in protected or []
        )

    while True:
        current = ladder.states[-1]
        done = True
        for drop in droppable(current, protects, exploratory=protected is None):
            new_state, step = apply_drop(copy_state(current), drop, rung_ir(current, setting))
            if try_step(new_state, step):
                done = False
                break
        if done:
            break
    return ladder


def block_columns(s: FactorState, predictors: Mapping[str, Any]) -> int:
    """The number of columns of the correlated block of a factor: one for the
    intercept, one for each numeric slope and one for each contrast column."""
    count = int(s.intercept)
    for variables in s.slope_variables:
        width = 1
        for v in variables:
            info = predictors[v]
            if info["kind"] == "categorical":
                width *= len(info["levels"]) - 1
        count += width
    return count


def block_name(s: FactorState) -> str:
    """The name of the block of a factor as one random term, as ir.md names
    it."""
    return random_term_name(s.intercept, s.slopes, s.factor)


@dataclass
class Drop:
    kind: str
    f: int
    k: int
    order: int


def droppable(state: State, protects: Any, exploratory: bool) -> list[Drop]:
    """The drops that a state allows, in the order in which the ladder tries
    them: unprotected slopes and complex random intercepts, by order of term,
    highest first, then by factor and from the last term back, and then the
    unprotected random intercepts of factors with nothing else left, by
    factor. An exploratory ladder keeps every random intercept."""
    candidates: list[Drop] = []
    for f, s in enumerate(state):
        for k in reversed(range(len(s.slopes))):
            if not protects(s.factor, s.slope_variables[k]):
                candidates.append(Drop("slope", f, k, len(s.slope_variables[k])))
        for k in reversed(range(len(s.complex))):
            if not protects(s.factor, term_variables(s.complex[k])):
                candidates.append(Drop("complex", f, k, 1))
    candidates.sort(key=lambda d: -d.order)
    if not exploratory:
        for f, s in enumerate(state):
            if s.intercept and not s.slopes and not s.complex and not protects(s.factor, []):
                candidates.append(Drop("intercept", f, 0, 0))
    return candidates


def apply_drop(state: State, drop: Drop, ir: Mapping[str, Any]) -> tuple[State, dict[str, Any]]:
    """Applies a drop to a state: the new state and the step, which names the
    random terms of the rung before that the drop removes."""
    s = state[drop.f]
    if drop.kind == "slope":
        variables = s.slope_variables[drop.k]
        factor = s.factor
        if s.correlated:
            terms = [block_name(s)]
        else:
            # The uncorrelated terms of the slope: one, or one for each column
            # of a frozen factor that '||' has split.
            terms = [
                t["name"]
                for t in ir["random"]
                if t["factor"] == factor
                and len(t["terms"]) == 1
                and t["terms"][0]["variables"]
                and set(v["variable"] for v in t["terms"][0]["variables"]) == set(variables)
            ]
        del s.slopes[drop.k]
        del s.slope_variables[drop.k]
    elif drop.kind == "complex":
        factor = complex_factor(s, drop.k)
        terms = ["1 | " + factor]
        del s.complex[drop.k]
    else:
        factor = s.factor
        terms = ["1 | " + factor]
        s.intercept = False
    return state, {"kind": "drop_terms", "factor": factor, "terms": terms}


def complex_factor(s: FactorState, k: int) -> str:
    """The name of the grouping factor of the k-th complex random intercept of
    a factor, its variables followed by the categorical variable."""
    return s.factor + ":" + s.complex[k]


# --- IRs of rungs -------------------------------------------------------------------


def rung_formula(state: State, setting: Setting) -> str:
    """The formula of a state: the response, the fixed part as the caller wrote
    it and, for each grouping factor, its block, written with '||' once it is
    uncorrelated, and its complex random intercepts."""
    random = []
    for s in state:
        if s.intercept or s.slopes:
            lhs = " + ".join(["1" if s.intercept else "0", *s.slopes])
            bar = " || " if not s.correlated and s.slopes else " | "
            random.append("(" + lhs + bar + s.factor + ")")
        for k in range(len(s.complex)):
            random.append("(1 | " + complex_factor(s, k) + ")")
    rhs = " + ".join(([setting.fixed_text] if setting.fixed_text else []) + random)
    return setting.response_text + " ~ " + rhs


def rung_ir(state: State, setting: Setting) -> dict[str, Any]:
    """The IR of a state, built from its formula with the frozen coding and the
    sample columns of the ceiling."""
    return build_formula_ir(
        rung_formula(state, setting),
        setting.declaration,
        setting.table,
        coding_input(setting.raw_coding),
        setting.weights,
        setting.sample_columns,
    )


# --- The ceiling section ---------------------------------------------------------------


def ceiling_section(
    data: Any,
    state: State,
    ir: dict[str, Any],
    restricted: Restricted,
    setting: Setting,
    arguments: Any,
) -> dict[str, Any]:
    """The ceiling of the plan (documents.md, Ceiling, verdicts and counts): its
    IR, its verdict, the random terms left out of rung 0 and, for each grouping
    factor, the counts that a shareable audit of the ceiling writes."""
    verdict = identifiability_verdict(ir, setting)
    results = audit(
        data,
        rung_formula(state, setting),
        setting.declaration,
        family=arguments.family,
        coding=setting.raw_coding,
        weights=arguments.weights,
        sample_columns=setting.sample_columns,
        key=PLAN_KEY,
    )
    findings = results.document["findings"]

    def find(check: str, scope: dict[str, str]) -> dict[str, Any]:
        for finding in findings:
            if finding["check"] == check and all(
                finding["scope"].get(k) == v for k, v in scope.items()
            ):
                return finding  # type: ignore[no-any-return]
        internal_error(f"the audit of the ceiling has no finding of {check}.")

    min_count = registry_document()["privacy"]["min_count"]
    factors = []
    for term in ir["random"]:
        budget = find("identifiability.df_budget", {"factor": term["factor"]})
        dimension = find(
            "identifiability.levels_vs_dimension", {"factor": term["factor"], "term": term["name"]}
        )
        factors.append(
            {
                "factor": term["factor"],
                "levels": plan_count(budget, "levels", min_count),
                "df_budget": plan_count(budget, "budget", min_count),
                "terms": [
                    {
                        "term": term["name"],
                        "informative_groups": plan_count(
                            dimension, "informative_levels", min_count
                        ),
                    }
                ],
            }
        )
    section: dict[str, Any] = {
        "ir": ir_without_means(ir),
        "verdict": {"value": verdict},
        "factors": factors,
    }
    if restricted.excluded:
        section["excluded"] = restricted.excluded
    return section


def plan_count(finding: Mapping[str, Any], name: str, min_count: int) -> Any:
    """A count of a shareable finding as a plan writes it: the value,
    {"below": k} for a person count that the filter suppressed below k, and
    {"suppressed": detail} for one that it suppressed by another rule or with
    the whole finding."""
    statistic = finding.get("statistics", {}).get(name)
    if statistic is not None and statistic.get("value") is not None:
        return statistic["value"]
    if statistic is None:
        detail = finding["status"]["availability"].get("detail")
    else:
        detail = statistic["availability"].get("detail")
    if detail is None:
        detail = "secondary"
    if detail == "min_count" and statistic is not None:
        return {"below": min_count}
    if detail == "min_count":
        detail = "min_count_rule"
    if detail not in ("dominance", "min_count_rule", "secondary"):
        detail = "secondary"
    return {"suppressed": detail}


# --- The execution binding ---------------------------------------------------------------


def statsmodels_version() -> str | None:
    """The version of statsmodels as its metadata reports it, or None when it
    is not installed."""
    from importlib import metadata

    try:
        return metadata.version("statsmodels")
    except metadata.PackageNotFoundError:
        return None


def statsmodels_binding(design: Mapping[str, Any], design_hash: str) -> dict[str, Any] | None:
    """The execution binding of the plan for statsmodels' MixedLM
    (documents.md, Execution bindings), when statsmodels is installed: its
    version, the optimisers in order of use, the second serving as the
    restart, and the encoding of each rung that MixedLM can express, or
    not_available with the reason not_expressible otherwise."""
    version = statsmodels_version()
    if version is None:
        return None
    rungs: list[dict[str, Any]] = []
    for rung in design["rungs"]:
        encoding = statsmodels_encoding(rung["ir"])
        if encoding is None:
            rungs.append(
                {
                    "availability": {
                        "value": "not_available",
                        "reason": "not_expressible",
                        "detail": "statsmodels",
                    }
                }
            )
        else:
            rungs.append({"availability": {"value": "available"}, "encoding": encoding})
    binding = {
        "design_plan_hash": design_hash,
        "language": "Python",
        "engine": {"name": "statsmodels", "version": version},
        "optimisers": [{"name": "lbfgs", "settings": {}}, {"name": "nm", "settings": {}}],
        "rungs": rungs,
    }
    binding = parse_json_bytes(canonical_bytes(binding, "hashable"), "hashable")
    return {"binding": binding, "hash": canonical_hash(binding, "hashable")}


def statsmodels_encoding(ir: Mapping[str, Any]) -> str | None:
    """The MixedLM call of an IR as the canonical JSON text of its arguments,
    over columns named as the IR names the columns of X and of the random
    terms, or None when MixedLM cannot express the IR (02-decisions.md, Q1):
    it holds weights, more than one random term of several columns, or a
    random term of several columns beside a random term whose grouping factor
    does not include its grouping variables. ``groups`` is the grouping of the
    term of several columns, or empty for a single group of all rows, ``re``
    its columns, and ``vc`` each other random term, a variance component with
    its grouping variables and its one column."""
    if "weights" in ir:
        return None
    blocks = [t for t in ir["random"] if len(t["columns"]) > 1]
    if len(blocks) > 1:
        return None
    groups: list[str] = list(blocks[0]["grouping"]) if blocks else []
    components = []
    for term in ir["random"]:
        if blocks and term is blocks[0]:
            continue
        if not set(groups) <= set(term["grouping"]):
            return None
        components.append(
            {"grouping": list(term["grouping"]), "column": term["columns"][0]["name"]}
        )
    arguments: dict[str, Any] = {
        "engine": "statsmodels.MixedLM",
        "fixed": [c["name"] for c in ir["fixed"]["columns"]],
        "groups": groups,
        "offsets": [dict(o) for o in ir["offsets"]],
        "re": [c["name"] for c in blocks[0]["columns"]] if blocks else [],
        "use_sparse": not blocks,
        "vc": components,
    }
    if "response" in ir:
        arguments["response"] = ir["response"]["variable"]
    return canonical_bytes(arguments, "hashable").decode("utf-8")
