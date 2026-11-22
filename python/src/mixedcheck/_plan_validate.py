"""The validator of plans (docs/spec/documents.md, Plan, Validation) and the
rule of ir.md (The IR document, Validation) that it applies to every IR."""

from __future__ import annotations

import os
import re
from collections.abc import Mapping
from typing import Any

from mixedcheck._checks import random_term_has_intercept
from mixedcheck._declaration import path_pointer, version_supported
from mixedcheck._errors import MixedcheckError, finish_issues, new_issue, raw_issue
from mixedcheck._formula_ir import (
    ColumnInfo,
    PartColumns,
    _part_document,
    level_position,
    part_columns,
    random_term_name,
)
from mixedcheck._formula_parse import variable_text
from mixedcheck._json_read import parse_json_bytes, read_input_bytes
from mixedcheck._json_write import canonical_bytes, canonical_hash
from mixedcheck._schema import json_equal, schema_issues
from mixedcheck._unicode import comparison_form

PLAN_VERSION_PATTERN = re.compile(r"0\.1\.(0|[1-9][0-9]*)")


def validate_plan(plan: Any) -> Any:
    """Validate a plan.

    Validates a plan in the four stages of the plan specification and stops
    after the first stage that finds a problem: reading in the hashable
    profile, the version at ``/plan_version``, the structure against the plan
    schema, with the IR schema for every IR, and the rules in code: the
    recorded hashes, the rungs and verdicts of the design and its bindings,
    the protected set in every rung, a terminal state that this package can
    run and that suits the design, the unique grouping factors of the ceiling
    and the rule of ir.md for every IR.

    Args:
        plan: A plan: the path of a file or the value that
            :func:`read_json_strict` returns, as :func:`design_plan` returns
            it.

    Returns:
        The plan: the value read from a file, or the plan given in memory.

    Raises:
        MixedcheckError: A plan that is not valid, with the issues of the first
            stage that finds any, as :func:`validate_results` reports them:
            one from reading, E1441 for the version, the structural issues, or
            the issues of the rules in code, E1321, E6101 and E7301 to E7309,
            among them E7307 for the terminal state cluster_robust_cr2, which
            this package cannot run, sorted by pointer, code and message and
            capped at 100.
        TypeError: A plan that is neither a path nor a dict.

    Examples:
        >>> fixture = pathology_zoo("Z05N")
        >>> plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
        >>> validate_plan(plan) is plan
        True
    """
    path = isinstance(plan, str | os.PathLike)
    if not path and not isinstance(plan, dict):
        raise TypeError("'plan' must be a file path or a value that read_json_strict() returns.")
    data = read_input_bytes(plan) if path else canonical_bytes(plan, "hashable")
    value = parse_json_bytes(data, "hashable")
    issues = plan_issues(value)
    if issues:
        raise MixedcheckError(issues)
    return value if path else plan


def plan_issues(value: Any) -> list[dict[str, Any]]:
    """Stages 2 to 4 on a plan read in stage 1."""
    version = value.get("plan_version") if isinstance(value, dict) else None
    if isinstance(version, str) and not version_supported(version, PLAN_VERSION_PATTERN):
        return [
            new_issue("E1441", {"version": version, "supported": "0.1.x"}, pointer="/plan_version")
        ]
    for stage in (lambda p: schema_issues(p, "urn:mixedcheck:schema:plan"), plan_rule_issues):
        raw = stage(value)
        if raw:
            return finish_issues(raw)
    return []


def plan_rule_issues(p: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Stage 4: the rules in code on a plan whose structure is valid."""
    issues: list[dict[str, Any]] = []

    def add(code: str, pointer: str, args: Mapping[str, Any] | None = None) -> None:
        issues.append(raw_issue(code, pointer, args))

    design = p["design"]
    rungs = design["rungs"]
    if canonical_hash(design, "hashable") != p["design_plan_hash"]:
        add("E1321", "/design_plan_hash")
    for i, entry in enumerate(p["bindings"]):
        here = path_pointer("bindings", i)
        binding = entry["binding"]
        if canonical_hash(binding, "hashable") != entry["hash"]:
            add("E1321", here + "/hash")
        if len(binding["rungs"]) != len(rungs):
            add(
                "E7301",
                here + "/binding/rungs",
                {"found": len(binding["rungs"]), "expected": len(rungs)},
            )
        if binding["design_plan_hash"] != p["design_plan_hash"]:
            add("E7302", here + "/binding/design_plan_hash")
    if len(p["verdicts"]) != len(rungs):
        add("E7303", "/verdicts", {"found": len(p["verdicts"]), "expected": len(rungs)})
    for i, verdict in enumerate(p["verdicts"]):
        if verdict["value"] == "not_identified":
            add("E7304", path_pointer("verdicts", i))
    protected = design.get("protected", [])
    for i, component in enumerate(protected):
        here = path_pointer("design", "protected", i)
        variables = {comparison_form(v) for v in component["variables"]}
        for earlier in protected[:i]:
            if (
                comparison_form(earlier["factor"]) == comparison_form(component["factor"])
                and {comparison_form(v) for v in earlier["variables"]} == variables
            ):
                add("E7305", here)
                break
        for r, rung in enumerate(rungs):
            # Complex random intercepts stand for the component only from a
            # step complex_intercepts on its grouping factor (documents.md,
            # E7306).
            complex_step = any(
                earlier.get("step", {}).get("kind") == "complex_intercepts"
                and comparison_form(earlier["step"]["factor"])
                == comparison_form(component["factor"])
                for earlier in rungs[: r + 1]
            )
            if not component_in_rung(component, rung["ir"], complex_step):
                add("E7306", here, {"rung": r})
    terminal = design.get("terminal", {}).get("state")
    if terminal == "cluster_robust_cr2":
        # Only the R package can run CR2 inference, through clubSandwich.
        add("E7307", "/design/terminal/state", {"state": terminal})
        if not factors_nested(rungs[0]["ir"]):
            add("E7309", "/design/terminal/state")
    factors = [comparison_form(f["factor"]) for f in p["ceiling"]["factors"]]
    for i, name in enumerate(factors):
        if name in factors[:i]:
            add(
                "E7308",
                path_pointer("ceiling", "factors", i, "factor"),
                {"name": p["ceiling"]["factors"][i]["factor"]},
            )
    irs = [(p["ceiling"]["ir"], "/ceiling/ir")] + [
        (rung["ir"], path_pointer("design", "rungs", r, "ir")) for r, rung in enumerate(rungs)
    ]
    for ir, pointer in irs:
        found = ir_rule_pointer(ir)
        if found is not None:
            add("E6101", pointer + found)
    return issues


def component_in_rung(
    component: Mapping[str, Any], ir: Mapping[str, Any], complex_step: bool = True
) -> bool:
    """Whether a rung holds a protected component (documents.md, E7306): a
    random term of its grouping factor with a term whose set of variables is
    the component's, or the intercept for an empty list, or, for one
    categorical variable f, the random intercept of the factor joined with f,
    which complex random intercepts give."""
    factor = comparison_form(component["factor"])
    variables = [comparison_form(v) for v in component["variables"]]
    for term in ir["random"]:
        grouping = [comparison_form(g) for g in term["grouping"]]
        if comparison_form(term["factor"]) == factor:
            for t in term["terms"]:
                found = [comparison_form(v["variable"]) for v in t["variables"]]
                if set(found) == set(variables) and len(found) == len(variables):
                    return True
        predictor = ir["predictors"].get(variables[0]) if len(variables) == 1 else None
        if (
            complex_step
            and predictor is not None
            and predictor["kind"] == "categorical"
            and random_term_has_intercept(term)
            and len(grouping) >= 2
            and grouping[-1] == variables[0]
            and ":".join(variable_text(g) for g in grouping[:-1]) == factor
        ):
            return True
    return False


def factors_nested(ir: Mapping[str, Any]) -> bool:
    """Whether one grouping factor of an IR has columns that every other
    grouping factor includes (documents.md, E7309)."""
    groupings = [{comparison_form(g) for g in term["grouping"]} for term in ir["random"]]
    return any(all(outer <= g for g in groupings) for outer in groupings)


# --- The rule of ir.md for an IR document -------------------------------------------


def ir_rule_pointer(ir: Mapping[str, Any]) -> str | None:
    """The JSON Pointer, within the IR, of the first member in the order of the
    canonical serialisation that differs from what the rules of ir.md give, or
    None for an IR that follows them (ir.md, The IR document, Validation)."""
    found: list[str] = []
    predictors: dict[str, ColumnInfo] = {}
    for name, entry in ir["predictors"].items():
        info = ColumnInfo(key=name, j=None, kind=entry["kind"], frozen=entry.get("frozen") is True)
        if entry["kind"] == "categorical":
            info.levels = list(entry["levels"])
            position = level_position(entry["reference"], entry["levels"])
            if position is None:
                found.append(path_pointer("predictors", name, "reference"))
                position = 0
            info.reference = position
        predictors[name] = info
    expected: dict[str, Any] = dict(ir)

    def part_terms(terms: list[Any], pointer: str) -> tuple[bool, list[list[str]]]:
        intercept = len(terms) > 0 and not terms[0]["variables"]
        variable_sets: list[list[str]] = []
        for i, term in enumerate(terms):
            variables = [v["variable"] for v in term["variables"]]
            for j, variable in enumerate(variables):
                if variable not in predictors:
                    found.append(pointer + path_pointer(i, "variables", j, "variable"))
            if i > 0 or not intercept:
                variable_sets.append(variables)
        keys = [tuple(sorted(v)) for v in variable_sets]
        for k, key in enumerate(keys):
            if key in keys[:k]:
                found.append(pointer + path_pointer(k + int(intercept)))
        return intercept, variable_sets

    if found:
        return earliest_pointer(found)
    intercept, terms = part_terms(ir["fixed"]["terms"], "/fixed/terms")
    if found:
        return earliest_pointer(found)
    expected["fixed"] = _part_document(part_columns(intercept, terms, predictors))
    random = list(ir["random"])
    identities: list[tuple[Any, ...]] = []
    columns_of: dict[str, list[str]] = {}
    for r, term in enumerate(ir["random"]):
        here = path_pointer("random", r)
        intercept, terms = part_terms(term["terms"], here + "/terms")
        if found:
            break
        part = part_columns(intercept, terms, predictors)
        carried = [[v.get("level") for v in t["variables"]] for t in term["terms"]]
        if any(level is not None for levels in carried for level in levels):
            # Levels are carried only in a random term with one term and no
            # intercept, only by frozen predictors and only for a level of a
            # column of that term.
            last = term["terms"][-1]
            levels = {v["variable"]: v["level"] for v in last["variables"] if "level" in v}
            chosen = [
                c
                for c in part.columns
                if len(c.levels) == len(levels)
                and all(
                    name in c.levels and json_equal(c.levels[name], value)
                    for name, value in levels.items()
                )
            ]
            valid = (
                not intercept
                and len(terms) == 1
                and len(chosen) == 1
                and all(predictors[name].frozen for name in levels)
            )
            if not valid:
                first = next(j for j, level in enumerate(carried[-1]) if level is not None)
                found.append(
                    here
                    + path_pointer("terms", len(term["terms"]) - 1, "variables", first, "level")
                )
                break
            column = chosen[0]
            part = PartColumns(
                part.intercept, part.terms, part.coding, [column], column.labels, column.levels
            )
        document = _part_document(part)
        grouping = list(term["grouping"])
        factor = ":".join(variable_text(g) for g in grouping)
        names = [t["name"] for t in document["terms"]]
        if intercept:
            names = names[1:]
        random[r] = {
            "name": random_term_name(intercept, names, factor),
            "factor": factor,
            "grouping": term["grouping"],
            "covariance": "unstructured",
            **document,
        }
        identity = (factor, intercept, tuple(sorted(names)))
        if identity in identities:
            found.append(here)
        identities.append(identity)
        column_names = [c["name"] for c in document["columns"]]
        shared = [name for name in column_names if name in columns_of.get(factor, [])]
        if shared:
            found.append(here + path_pointer("columns", column_names.index(shared[0]), "name"))
        columns_of.setdefault(factor, []).extend(column_names)
    expected["random"] = random
    offsets = ir["offsets"]
    if offsets:
        expected["offsets"] = sorted(
            offsets, key=lambda o: (comparison_form(o["variable"]), o["transform"])
        )
    sample = list(ir.get("sample_columns", []))
    if sample:
        read = {
            comparison_form(name)
            for name in (
                list(ir["predictors"])
                + [g for term in ir["random"] for g in term["grouping"]]
                + [o["variable"] for o in offsets]
                + ([ir["weights"]["variable"]] if "weights" in ir else [])
                + ([ir["response"]["variable"]] if "response" in ir else [])
                + ([ir["response"]["trials"]] if "trials" in ir.get("response", {}) else [])
            )
        }
        kept = [name for name in sample if comparison_form(name) not in read]
        expected["sample_columns"] = sorted(kept, key=comparison_form)
    difference = json_first_difference(ir, expected, "")
    return earliest_pointer(found + ([difference] if difference is not None else []))


def json_first_difference(a: Any, b: Any, pointer: str) -> str | None:
    """The pointer of the first member, in the order of the canonical
    serialisation, at which two JSON values differ, or None."""
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b)):
            here = pointer + path_pointer(key)
            if key not in a or key not in b:
                return here
            found = json_first_difference(a[key], b[key], here)
            if found is not None:
                return found
        return None
    if isinstance(a, list) and isinstance(b, list):
        for i in range(max(len(a), len(b))):
            here = pointer + "/" + str(i)
            if i >= len(a) or i >= len(b):
                return here
            found = json_first_difference(a[i], b[i], here)
            if found is not None:
                return found
        return None
    return None if json_equal(a, b) else pointer


def earliest_pointer(pointers: list[str]) -> str | None:
    """The earliest of some JSON Pointers in the order of the canonical
    serialisation: token by token, array indices by value and keys by code
    point, with a pointer before every pointer that extends it."""
    if not pointers:
        return None
    return min(pointers, key=_pointer_key)


def _pointer_key(pointer: str) -> list[tuple[int, Any]]:
    tokens = pointer[1:].split("/") if pointer else []
    key: list[tuple[int, Any]] = []
    for token in tokens:
        if token.isdigit() and token.isascii():
            key.append((0, int(token)))
        else:
            key.append((1, token.replace("~1", "/").replace("~0", "~")))
    return key
