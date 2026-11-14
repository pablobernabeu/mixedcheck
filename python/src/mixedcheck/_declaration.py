"""The declaration validator (docs/spec/declarations.md, Validation).

It works in five stages, reading, version, structure, names and references,
and meaning, and stops after the first stage that reports an issue.
"""

from __future__ import annotations

import os
import re
from collections.abc import Callable
from typing import Any

from mixedcheck._errors import Issue, MixedcheckError, finish_issues, new_issue, raw_issue
from mixedcheck._json_read import parse_json_bytes, read_json_strict
from mixedcheck._json_write import canonical_bytes, json_pointer
from mixedcheck._schema import is_json_integer, json_equal, schema_issues, term_variables

# The supported line of the vocabulary and the form of its versions.
VOCABULARY_PATTERN = re.compile(r"0\.1\.(0|[1-9][0-9]*)")

_ASCII_LOWER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
_YAML_NAME = re.compile(r"\.ya?ml\Z")
_INDEX = re.compile(r"0|[1-9][0-9]*")


def validate_declaration(declaration: Any, minimal: bool = False) -> Any:
    """Validate a design declaration.

    Reads a declaration of declaration vocabulary 0.1 and checks it in five
    stages, stopping after the first stage that finds a problem: reading, the
    vocabulary version, the structure against the declaration schema, names
    and references, and the rules on meaning, including those of the minimal
    declaration. A file whose name ends in '.yaml' or '.yml' is read as YAML,
    with every scalar read as a string and converted to the type that the
    schema requires at its position, which needs PyYAML, installed with the
    extra 'yaml'. Any other file is read as JSON with the strict reader in the
    hashable profile, and a value in memory, such as a dict written by hand,
    must pass the writer's checks of the hashable profile.

    The declaration hash is the hash of the canonical bytes of the value
    returned, so a YAML file and the JSON file it converts to have the same
    hash.

    Args:
        declaration: The path of a file, as a str or a path-like object, or
            the declaration as a dict.
        minimal: Whether the declaration must be a minimal declaration, as the
            outcome-blind and preregistration exports require. A confirmatory
            goal and the features cluster_randomised, stepped_wedge and
            partially_nested require one whatever this argument says.

    Returns:
        The declaration: objects as dicts, arrays as lists, strings as str,
        numbers as int or float and booleans as bool, as
        :func:`read_json_strict` returns them.

    Raises:
        MixedcheckError: A declaration that is not valid, whose ``issues``
            list the problems found, each with the ``code`` of the shared
            error catalogue and the rendered ``message``. Reading reports one
            problem, located by the byte ``offset`` in the file or by the JSON
            Pointer of the converted YAML value as ``pointer``. The later
            stages report every problem they find, located by JSON Pointer as
            ``pointer``, sorted by pointer, code and message and capped at 100.

    Examples:
        >>> # The declaration of fixture Z19N of the pathology zoo: pupils in
        >>> # schools, with a baseline score as a covariate.
        >>> declaration = pathology_zoo("Z19N")["declaration"]
        >>> value = validate_declaration(declaration)
        >>> canonical_hash(value, "hashable")
        'sha256:3636a6607c536ec9935a580c1730601915e6c40ea7627b9ea11b67ae2e0f5ec2'
        >>> # A minimal declaration also states the estimands and an assigned
        >>> # variable.
        >>> try:
        ...     validate_declaration(declaration, minimal=True)
        ... except MixedcheckError as err:
        ...     print([issue["code"] for issue in err.issues])
        ['E2028', 'E2030']
        >>> # A unit nested in a unit that is not declared.
        >>> declaration["units"][1]["nested_in"] = "class"
        >>> try:
        ...     validate_declaration(declaration)
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["message"])
        The unit 'class' at /units/1/nested_in is not declared in the units block.
    """
    if not isinstance(minimal, bool):
        raise TypeError("'minimal' must be True or False.")
    value = read_declaration_input(declaration)
    issues = declaration_issues(value, minimal)
    if issues:
        raise MixedcheckError(issues)
    return value


def read_declaration_input(declaration: Any) -> Any:
    """Stage 1: the declaration as read from a YAML or JSON file, or a value in
    memory after the writer's checks of the hashable profile, as the strict
    reader returns it."""
    if isinstance(declaration, os.PathLike):
        declaration = os.fspath(declaration)
    if isinstance(declaration, str):
        if is_yaml_path(declaration):
            from mixedcheck._yaml import read_yaml_declaration

            return read_yaml_declaration(declaration)
        return read_json_strict(declaration, "hashable")
    return parse_json_bytes(canonical_bytes(declaration, "hashable"), "hashable")


def is_yaml_path(path: str) -> bool:
    """Whether a file name ends in '.yaml' or '.yml', compared in ASCII lower case."""
    return _YAML_NAME.search(path.translate(_ASCII_LOWER)) is not None


def version_supported(version: Any, pattern: re.Pattern[str]) -> bool:
    """Whether a version string lies in a supported line: it matches the
    pattern of the line and has at most 32 characters."""
    return (
        isinstance(version, str) and len(version) <= 32 and pattern.fullmatch(version) is not None
    )


def declaration_issues(value: Any, minimal: bool = False) -> list[Issue]:
    """Stages 2 to 5 on a value read in stage 1. Returns the issues of the
    first stage that finds any, rendered, sorted and capped."""
    version = value.get("vocabulary") if isinstance(value, dict) else None
    if isinstance(version, str) and not version_supported(version, VOCABULARY_PATTERN):
        return [
            new_issue("E1441", {"version": version, "supported": "0.1.x"}, pointer="/vocabulary")
        ]
    stages: list[Callable[[Any], list[dict[str, Any]]]] = [
        lambda d: schema_issues(d, "urn:mixedcheck:schema:declaration"),
        declaration_reference_issues,
        lambda d: declaration_meaning_issues(d, minimal),
    ]
    for stage in stages:
        raw = stage(value)
        if raw:
            return finish_issues(raw)
    return []


def path_pointer(*tokens: Any) -> str:
    """The pointer of a path of tokens, numbers being array indices from 0."""
    return json_pointer([str(token) for token in tokens])


def _strings(entries: list[Any] | None, member: str) -> list[Any]:
    return [entry.get(member) for entry in entries or []]


def _duplicates(values: list[Any]) -> list[int]:
    """The indices of the values that repeat an earlier value."""
    seen: set[Any] = set()
    found = []
    for index, item in enumerate(values):
        if item in seen:
            found.append(index)
        seen.add(item)
    return found


def declaration_reference_issues(d: dict[str, Any]) -> list[dict[str, Any]]:
    """Stage 4: names and references (E2001 to E2009)."""
    issues: list[dict[str, Any]] = []

    def add(code: str, pointer: str, args: dict[str, Any] | None = None) -> None:
        issues.append(raw_issue(code, pointer, args))

    units = d.get("units") or []
    unit_names = _strings(units, "name")
    table = d.get("table")
    has_table = table is not None
    fields = (table or {}).get("fields") or []
    field_names = _strings(fields, "name")
    estimands = d.get("estimands") or []
    assignment = d.get("assignment") or []
    crossings = d.get("crossings") or []
    variables = d.get("variables") or {}

    def repeated(values: list[Any], code: str, *prefix: str, member: str) -> None:
        for i in _duplicates(values):
            add(code, path_pointer(*prefix, i, member), {"name": values[i]})

    repeated(unit_names, "E2001", "units", member="name")
    repeated(field_names, "E2002", "table", "fields", member="name")
    repeated(_strings(estimands, "id"), "E2003", "estimands", member="id")
    repeated(_strings(assignment, "column"), "E2004", "assignment", member="column")

    pairs = [tuple(sorted(crossing.get("units") or [])) for crossing in crossings]
    for i in _duplicates(pairs):
        add("E2005", path_pointer("crossings", i, "units"))

    def unit_reference(name: Any, *tokens: Any) -> None:
        if name is not None and name not in unit_names:
            add("E2006", path_pointer(*tokens), {"name": name})

    def column_reference(name: Any, *tokens: Any) -> None:
        if has_table and name is not None and name not in field_names:
            add("E2007", path_pointer(*tokens), {"name": name})

    for i, unit in enumerate(units):
        unit_reference(unit.get("nested_in"), "units", i, "nested_in")
        for j, column in enumerate(unit.get("columns") or []):
            column_reference(column, "units", i, "columns", j)
    for i, crossing in enumerate(crossings):
        for j, unit in enumerate(crossing.get("units") or []):
            unit_reference(unit, "crossings", i, "units", j)
        column_reference(crossing.get("list"), "crossings", i, "list")
    observation = d.get("observation") or {}
    time = observation.get("time") or {}
    unit_reference(observation.get("unit"), "observation", "unit")
    unit_reference(time.get("within"), "observation", "time", "within")
    for j, column in enumerate(observation.get("key") or []):
        column_reference(column, "observation", "key", j)
    column_reference(time.get("column"), "observation", "time", "column")
    for i, entry in enumerate(assignment):
        unit_reference(entry.get("unit"), "assignment", i, "unit")
        for j, block in enumerate(entry.get("blocks") or []):
            unit_reference(block, "assignment", i, "blocks", j)
        column_reference(entry.get("column"), "assignment", i, "column")
    unit_reference(d.get("disclosure_unit"), "disclosure_unit")
    for column, entry in variables.items():
        column_reference(column, "variables", column)
        for j, source in enumerate(entry.get("derived_from") or []):
            column_reference(source, "variables", column, "derived_from", j)
        column_reference(entry.get("trials"), "variables", column, "trials")
        exposure = entry.get("exposure") or {}
        column_reference(exposure.get("column"), "variables", column, "exposure", "column")
    for i, estimand in enumerate(estimands):
        column_reference(estimand.get("outcome"), "estimands", i, "outcome")
        names = term_variables(estimand["term"]) if "term" in estimand else []
        for name in dict.fromkeys(names):
            column_reference(name, "estimands", i, "term")
        for name in dict.fromkeys(names[j] for j in _duplicates(names)):
            add("E2008", path_pointer("estimands", i, "term"), {"name": name})
    for j, column in enumerate((table or {}).get("primaryKey") or []):
        column_reference(column, "table", "primaryKey", j)
    for i, key in enumerate((table or {}).get("uniqueKeys") or []):
        for j, column in enumerate(key):
            column_reference(column, "table", "uniqueKeys", i, j)

    inferred = (d.get("provenance") or {}).get("inferred") or []
    for j, pointer in enumerate(inferred):
        excluded = pointer in ("", "/vocabulary", "/provenance") or pointer.startswith(
            "/provenance/"
        )
        if excluded or not pointer_resolves(d, pointer):
            add("E2009", path_pointer("provenance", "inferred", j), {"pointer": pointer})
    return issues


def pointer_resolves(x: Any, pointer: str) -> bool:
    """Whether RFC 6901 evaluation of a pointer finds a value, an array index
    token being '0' or a decimal number without leading zeros below the
    array's length."""
    if pointer == "":
        return True
    for token in pointer[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if isinstance(x, dict):
            if token not in x:
                return False
            x = x[token]
        elif isinstance(x, list):
            if _INDEX.fullmatch(token) is None or len(token) > 18 or int(token) >= len(x):
                return False
            x = x[int(token)]
        else:
            return False
    return True


def list_item_value(item: Any) -> Any:
    """The value of a plain item of a list of categories or missing values, or
    the member ``value`` of an object item."""
    return item.get("value") if isinstance(item, dict) else item


def declaration_meaning_issues(d: dict[str, Any], minimal: bool = False) -> list[dict[str, Any]]:
    """Stage 5: meaning (E2010 to E2032), on a declaration whose names are
    unique and whose references resolve."""
    issues: list[dict[str, Any]] = []

    def add(code: str, pointer: str, args: dict[str, Any] | None = None) -> None:
        issues.append(raw_issue(code, pointer, args))

    units = d.get("units") or []
    unit_names = _strings(units, "name")
    parents = dict(zip(unit_names, _strings(units, "nested_in"), strict=True))
    table = d.get("table") or {}
    fields = table.get("fields") or []
    field_names = _strings(fields, "name")
    variables = d.get("variables") or {}
    columns = list(variables)
    roles = {column: entry.get("role") for column, entry in variables.items()}
    outcomes = [column for column in columns if roles[column] == "outcome"]
    outcome_derived = [column for column in columns if roles[column] == "outcome_derived"]
    estimands = d.get("estimands") or []
    assignment = d.get("assignment")
    features = d.get("features") or []
    observation = d.get("observation")
    has_time = observation is not None and observation.get("time") is not None

    def ancestors(unit: str) -> list[str]:
        """The units reached by following nested_in from a unit, stopping when
        a unit repeats."""
        found: list[str] = []
        current = parents.get(unit)
        while current is not None and current not in found:
            found.append(current)
            current = parents.get(current)
        return found

    for i, name in enumerate(unit_names):
        if name in ancestors(name):
            add("E2010", path_pointer("units", i, "nested_in"), {"name": name})
    for i, crossing in enumerate(d.get("crossings") or []):
        first, second = crossing["units"]
        if second in ancestors(first) or first in ancestors(second):
            add("E2011", path_pointer("crossings", i, "units"))

    derived = {column: list(entry.get("derived_from") or []) for column, entry in variables.items()}
    for column in columns:
        pending = list(derived[column])
        seen: list[str] = []
        while pending:
            current = pending.pop(0)
            if current == column:
                add("E2012", path_pointer("variables", column, "derived_from"), {"name": column})
                break
            if current not in seen:
                seen.append(current)
                if current in derived:
                    pending.extend(derived[current])

    identifiers = {column for unit in units for column in unit.get("columns") or []}
    identifiers.update(column for column in columns if roles[column] == "id")
    value_lists: list[tuple[list[Any], tuple[Any, ...]]] = []
    if "missingValues" in table:
        value_lists.append((table["missingValues"], ("table", "missingValues")))
    for i, field in enumerate(fields):
        path = ("table", "fields", i)
        categories = field.get("categories")
        if categories is not None:
            type_name = field.get("type")
            for j, item in enumerate(categories):
                is_object = isinstance(item, dict)
                category = list_item_value(item)
                wrong = (type_name == "string" and not isinstance(category, str)) or (
                    type_name == "integer" and not is_json_integer(category)
                )
                if wrong:
                    tokens = (*path, "categories", j, *(("value",) if is_object else ()))
                    add(
                        "E2013",
                        path_pointer(*tokens),
                        {"type": "a string" if type_name == "string" else "an integer"},
                    )
            value_lists.append((categories, (*path, "categories")))
            if field_names[i] in identifiers:
                add("E2016", path_pointer(*path, "categories"), {"name": field_names[i]})
        if "missingValues" in field:
            value_lists.append((field["missingValues"], (*path, "missingValues")))
    for items, path in value_lists:
        objects = [isinstance(item, dict) for item in items]
        if any(objects) and not all(objects):
            add("E2014", path_pointer(*path))
        values = [list_item_value(item) for item in items]
        for j in range(1, len(values)):
            if any(json_equal(values[j], earlier) for earlier in values[:j]):
                add("E2015", path_pointer(*path, j), {"value": [values[j]]})

    for column, entry in variables.items():
        bounds = entry.get("bounds")
        if bounds is not None and not bounds[0] < bounds[1]:
            add("E2017", path_pointer("variables", column, "bounds"))
    for entry in assignment or []:
        column = entry.get("column")
        if column in roles and roles[column] != "assigned":
            add("E2018", path_pointer("variables", column, "role"), {"name": column})

    def misused(name: Any, *tokens: Any) -> None:
        if name is not None and name in outcomes:
            add("E2019", path_pointer(*tokens), {"name": name})

    for i, unit in enumerate(units):
        for j, column in enumerate(unit.get("columns") or []):
            misused(column, "units", i, "columns", j)
    for i, crossing in enumerate(d.get("crossings") or []):
        misused(crossing.get("list"), "crossings", i, "list")
    observation_block = observation or {}
    for j, column in enumerate(observation_block.get("key") or []):
        misused(column, "observation", "key", j)
    misused((observation_block.get("time") or {}).get("column"), "observation", "time", "column")
    for column, entry in variables.items():
        misused(entry.get("trials"), "variables", column, "trials")
        misused(
            (entry.get("exposure") or {}).get("column"), "variables", column, "exposure", "column"
        )
    for j, column in enumerate(table.get("primaryKey") or []):
        misused(column, "table", "primaryKey", j)
    for i, key in enumerate(table.get("uniqueKeys") or []):
        for j, column in enumerate(key):
            misused(column, "table", "uniqueKeys", i, j)
    for i, estimand in enumerate(estimands):
        for name in dict.fromkeys(term_variables(estimand["term"]) if "term" in estimand else []):
            misused(name, "estimands", i, "term")

    for column in columns:
        if any(source in outcomes or source in outcome_derived for source in derived[column]) and (
            roles[column] not in ("outcome", "outcome_derived")
        ):
            add("E2020", path_pointer("variables", column, "role"), {"name": column})
    for i, estimand in enumerate(estimands):
        outcome = estimand.get("outcome")
        if outcome is not None and outcome not in outcomes:
            add("E2021", path_pointer("estimands", i, "outcome"), {"name": outcome})
        if len(outcomes) > 1 and outcome is None:
            add("E2022", path_pointer("estimands", i))

    for column, entry in variables.items():
        level = entry.get("event_level")
        field = fields[field_names.index(column)] if column in field_names else {}
        type_name = field.get("type")
        if level is None or type_name is None:
            continue
        matches = (type_name == "string" and isinstance(level, str)) or (
            type_name in ("integer", "number") and is_json_integer(level)
        )
        if not matches:
            add("E2023", path_pointer("variables", column, "event_level"), {"type": type_name})
        elif field.get("categories") is not None and not any(
            json_equal(list_item_value(item), level) for item in field["categories"]
        ):
            add("E2024", path_pointer("variables", column, "event_level"), {"value": [level]})

    trial_features = ("cluster_randomised", "stepped_wedge", "partially_nested")
    requirements = {
        "cluster_randomised": ("/assignment",),
        "stepped_wedge": ("/assignment", "/observation/time"),
        "partially_nested": ("/assignment",),
        "longitudinal": ("/observation/time",),
        "intensive_longitudinal": ("/observation/time",),
    }
    present = {"/assignment": assignment is not None, "/observation/time": has_time}
    for j, feature in enumerate(features):
        for required in requirements.get(feature, ()):
            if not present[required]:
                add(
                    "E2025",
                    path_pointer("features", j),
                    {"feature": feature, "required": required},
                )
    for i, unit in enumerate(units):
        if unit.get("membership") == "may_change_over_time" and not has_time:
            add("E2026", path_pointer("units", i, "membership"))
    observational = "observational" in features
    if observational:
        if assignment is not None:
            add("E2027", "/assignment")
        for column in columns:
            if roles[column] == "assigned":
                add("E2027", path_pointer("variables", column, "role"))
        for j, feature in enumerate(features):
            if feature in trial_features:
                add("E2027", path_pointer("features", j))

    if (
        minimal
        or d.get("goal") == "confirmatory"
        or any(feature in trial_features for feature in features)
    ):
        for block in ("units", "observation", "variables", "estimands"):
            if block not in d:
                add("E2028", "", {"key": block})
        if observation is not None and "key" not in observation:
            add("E2028", "/observation", {"key": "key"})
        if "variables" in d and not outcomes:
            add("E2029", "/variables")
        if assignment is None and "assigned" not in roles.values() and not observational:
            add("E2030", "")
        if "estimands" in d and not any(
            estimand.get("focal") is not False for estimand in estimands
        ):
            add("E2031", "/estimands")
        if (d.get("provenance") or {}).get("inferred") is not None:
            add("E2032", "/provenance/inferred")
    return issues
