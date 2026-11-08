"""The structural validator (docs/spec/errors.md, Structural validation).

It checks a value read by the strict reader against a schema of the vendored
bundle, with the JSON Schema keywords that conventions.md (Schemas) allows,
and returns every issue it finds as a raw issue for finish_issues(). The rules
that defs.schema.json states in descriptions are checked with it, as part of
the same phase.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterator
from importlib.resources import files
from typing import Any, NamedTuple

from mixedcheck._errors import raw_issue
from mixedcheck._json_write import canonical_bytes
from mixedcheck._unicode import has_non_bmp

# The definitions whose references the validator does not follow, because
# readers and writers enforce the profiles (conventions.md, Schemas).
PROFILE_DEFINITIONS = (
    "urn:mixedcheck:schema:defs#/$defs/hashable_value",
    "urn:mixedcheck:schema:defs#/$defs/data_value",
)

RawIssue = dict[str, Any]


class Node(NamedTuple):
    """A schema with the identifier of the document that holds it, which
    relative references resolve against, and the absolute reference by which
    it was reached, or None."""

    schema: Any
    base: str
    ref: str | None = None


class Bundle:
    """A bundle of schemas: the schemas by identifier and caches of the nodes
    that references resolve to and of compiled patterns."""

    def __init__(self, schemas: list[Any]) -> None:
        self.schemas = {schema["$id"]: schema for schema in schemas}
        self.resolved: dict[str, Node] = {}
        self.patterns: dict[str, re.Pattern[str]] = {}

    def resolve(self, ref: str, base: str) -> Node:
        """Resolve a reference such as 'urn:mixedcheck:schema:defs#/$defs/name'
        or '#/$defs/line' against the identifier of the document that holds it."""
        document, _, fragment = ref.partition("#")
        document = document or base
        absolute = document + "#" + fragment
        cached = self.resolved.get(absolute)
        if cached is not None:
            return cached
        if document not in self.schemas:
            raise RuntimeError(f"Internal error: unknown schema '{document}'.")
        schema = self.schemas[document]
        for token in fragment.lstrip("/").split("/") if fragment.lstrip("/") else []:
            token = token.replace("~1", "/").replace("~0", "~")
            if not isinstance(schema, dict) or token not in schema:
                raise RuntimeError(f"Internal error: the reference '{ref}' resolves to nothing.")
            schema = schema[token]
        node = Node(schema, document, absolute)
        self.resolved[absolute] = node
        return node

    def matches(self, pattern: str, text: str) -> bool:
        """Whether a schema pattern matches a string, over code points and with
        a final '$' matching only at the end (conventions.md, Schemas)."""
        compiled = self.patterns.get(pattern)
        if compiled is None:
            converted = pattern
            if converted.endswith("$") and not converted.endswith("\\$"):
                converted = converted[:-1] + r"\Z"
            compiled = re.compile(converted)
            self.patterns[pattern] = compiled
        return compiled.search(text) is not None


_bundle: list[Bundle] = []


def schema_bundle() -> Bundle:
    """The schemas of the vendored bundle, read once per session."""
    if not _bundle:
        from mixedcheck._json_read import parse_json_bytes

        directory = files("mixedcheck") / "_spec" / "schemas"
        entries = sorted(
            (entry for entry in directory.iterdir() if entry.name.endswith(".schema.json")),
            key=lambda entry: entry.name,
        )
        _bundle.append(
            Bundle([parse_json_bytes(entry.read_bytes(), "hashable") for entry in entries])
        )
    return _bundle[0]


def json_kind(value: Any) -> str:
    """The JSON type of a value read by the strict reader."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int | float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def is_json_integer(value: Any) -> bool:
    """Whether a value is a number whose value is integral, so that 1.0 is an
    integer."""
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and value.is_integer()


def has_json_type(value: Any, type_name: str) -> bool:
    """Whether a value has a type of JSON Schema."""
    if type_name == "integer":
        return is_json_integer(value)
    return json_kind(value) == type_name


def json_equal(left: Any, right: Any) -> bool:
    """Equality of JSON values as JSON Schema defines it: the same type,
    numbers by value, strings by code points, arrays item by item and objects
    member by member, whatever the order of their members."""
    kind = json_kind(left)
    if kind != json_kind(right):
        return False
    if kind == "array":
        return len(left) == len(right) and all(map(json_equal, left, right))
    if kind == "object":
        return left.keys() == right.keys() and all(json_equal(left[k], right[k]) for k in left)
    return bool(left == right)


def child_pointer(pointer: str, token: str | int) -> str:
    """The pointer of a member or item: its token escaped and appended."""
    return pointer + "/" + str(token).replace("~", "~0").replace("/", "~1")


def _types(schema: dict[str, Any]) -> list[str]:
    types = schema["type"]
    return [types] if isinstance(types, str) else list(types)


def schema_issues(value: Any, schema: str | Node, bundle: Bundle | None = None) -> list[RawIssue]:
    """Validate a value against the schema with the given identifier, or
    against a node, and return the raw issues, unsorted."""
    bundle = bundle or schema_bundle()
    node = bundle.resolve(schema, schema) if isinstance(schema, str) else schema
    return _Validator(bundle).validate(value, node, "")


class _Validator:
    def __init__(self, bundle: Bundle) -> None:
        self.bundle = bundle

    def valid(self, value: Any, node: Node) -> bool:
        return not self.validate(value, node, "")

    def unconditional_types(self, value: Any, node: Node) -> Iterator[list[str]]:
        """The type keywords that apply to a value unconditionally, in the
        order of errors.md (Structural validation, rule 3): the schema's own,
        then those reached through $ref, allOf and the branch of if that
        applies, recursively."""
        schema = node.schema
        if not isinstance(schema, dict):
            return
        if "type" in schema:
            yield _types(schema)
        if "$ref" in schema:
            target = self.bundle.resolve(schema["$ref"], node.base)
            if target.ref not in PROFILE_DEFINITIONS:
                yield from self.unconditional_types(value, target)
        for sub in schema.get("allOf", []):
            yield from self.unconditional_types(value, Node(sub, node.base))
        if "if" in schema:
            branch = "then" if self.valid(value, Node(schema["if"], node.base)) else "else"
            if branch in schema:
                yield from self.unconditional_types(value, Node(schema[branch], node.base))

    def validate(self, value: Any, node: Node, pointer: str) -> list[RawIssue]:
        schema = node.schema
        if schema is True:
            return []
        if schema is False:
            return [raw_issue("E1423", pointer)]
        for types in self.unconditional_types(value, node):
            if not any(has_json_type(value, name) for name in types):
                return [raw_issue("E1401", pointer, {"expected": types, "found": json_kind(value)})]
        return self.apply(value, node, pointer)

    def title(self, node: Node) -> str:
        """The title that E1406 and E1418 name: the node's own, or that of the
        first schema its $ref chain reaches that has one."""
        schema, base = node.schema, node.base
        while isinstance(schema, dict) and "title" not in schema and "$ref" in schema:
            target = self.bundle.resolve(schema["$ref"], base)
            schema, base = target.schema, target.base
        if isinstance(schema, dict) and "title" in schema:
            return str(schema["title"])
        return "value of the required form"

    def apply(self, value: Any, node: Node, pointer: str) -> list[RawIssue]:
        schema, base = node.schema, node.base
        issues: list[RawIssue] = []
        if "$ref" in schema:
            target = self.bundle.resolve(schema["$ref"], base)
            if target.ref not in PROFILE_DEFINITIONS:
                issues += self.validate(value, target, pointer)
                issues += self.definition_issues(value, target, pointer)
        for sub in schema.get("allOf", []):
            issues += self.validate(value, Node(sub, base), pointer)
        if "if" in schema:
            branch = "then" if self.valid(value, Node(schema["if"], base)) else "else"
            if branch in schema:
                issues += self.validate(value, Node(schema[branch], base), pointer)
        if "enum" in schema and not any(json_equal(value, item) for item in schema["enum"]):
            issues.append(raw_issue("E1405", pointer, {"allowed": schema["enum"]}))
        if "const" in schema and not json_equal(value, schema["const"]):
            issues.append(raw_issue("E1405", pointer, {"allowed": [schema["const"]]}))
        kind = json_kind(value)
        if kind == "string":
            issues += self.string_issues(value, node, pointer)
        elif kind == "number":
            issues += self.number_issues(value, schema, pointer)
        elif kind == "array":
            issues += self.array_issues(value, schema, base, pointer)
        elif kind == "object":
            issues += self.object_issues(value, schema, base, pointer)
        for keyword in ("anyOf", "oneOf"):
            if keyword in schema:
                issues += self.alternative_issues(value, keyword, schema[keyword], base, pointer)
        if "not" in schema and self.valid(value, Node(schema["not"], base)):
            issues.append(raw_issue("E1423", pointer))
        return issues

    def string_issues(self, value: str, node: Node, pointer: str) -> list[RawIssue]:
        schema = node.schema
        issues = []
        if "minLength" in schema and len(value) < schema["minLength"]:
            issues.append(raw_issue("E1407", pointer, {"limit": schema["minLength"]}))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            issues.append(raw_issue("E1408", pointer, {"limit": schema["maxLength"]}))
        if "pattern" in schema and not self.bundle.matches(schema["pattern"], value):
            issues.append(raw_issue("E1406", pointer, {"form": self.title(node)}))
        return issues

    @staticmethod
    def number_issues(value: Any, schema: dict[str, Any], pointer: str) -> list[RawIssue]:
        checks: list[tuple[str, str, Callable[[Any, Any], bool]]] = [
            ("minimum", "E1409", lambda v, limit: v < limit),
            ("maximum", "E1410", lambda v, limit: v > limit),
            ("exclusiveMinimum", "E1411", lambda v, limit: v <= limit),
            ("exclusiveMaximum", "E1412", lambda v, limit: v >= limit),
        ]
        issues = []
        for keyword, code, fails in checks:
            if keyword in schema and fails(value, schema[keyword]):
                issues.append(raw_issue(code, pointer, {"limit": schema[keyword]}))
        return issues

    def array_issues(
        self, value: list[Any], schema: dict[str, Any], base: str, pointer: str
    ) -> list[RawIssue]:
        issues: list[RawIssue] = []
        prefix = schema.get("prefixItems", [])
        for index, item in enumerate(value):
            if index < len(prefix):
                sub = prefix[index]
            elif "items" in schema:
                sub = schema["items"]
            else:
                continue
            issues += self.validate(item, Node(sub, base), child_pointer(pointer, index))
        if "minItems" in schema and len(value) < schema["minItems"]:
            issues.append(raw_issue("E1413", pointer, {"limit": schema["minItems"]}))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            issues.append(raw_issue("E1414", pointer, {"limit": schema["maxItems"]}))
        if schema.get("uniqueItems") is True and len(value) > 1:
            # Two values that the reader returns are equal as JSON Schema
            # defines it exactly when their canonical forms are, since numbers
            # are written by value and members in the order of their keys.
            # Comparing the forms takes time in proportion to the number of
            # items, not to its square.
            seen: set[bytes] = set()
            for index, item in enumerate(value):
                form = canonical_bytes(item, "plain")
                if form in seen:
                    issues.append(raw_issue("E1415", child_pointer(pointer, index)))
                seen.add(form)
        if "contains" in schema:
            contains = Node(schema["contains"], base)
            if not any(self.valid(item, contains) for item in value):
                issues.append(raw_issue("E1420", pointer))
        return issues

    def object_issues(
        self, value: dict[str, Any], schema: dict[str, Any], base: str, pointer: str
    ) -> list[RawIssue]:
        issues: list[RawIssue] = []
        for key in schema.get("required", []):
            if key not in value:
                issues.append(raw_issue("E1402", pointer, {"key": key}))
        for key, required in schema.get("dependentRequired", {}).items():
            if key in value:
                for other in required:
                    if other not in value:
                        issues.append(raw_issue("E1419", pointer, {"key": key, "required": other}))
        if "propertyNames" in schema:
            names = Node(schema["propertyNames"], base)
            for key in value:
                if not self.valid(key, names):
                    issues.append(
                        raw_issue("E1418", pointer, {"key": key, "form": self.title(names)})
                    )
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            issues.append(raw_issue("E1416", pointer, {"limit": schema["minProperties"]}))
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            issues.append(raw_issue("E1417", pointer, {"limit": schema["maxProperties"]}))
        properties = schema.get("properties", {})
        patterns = schema.get("patternProperties", {})
        for key, item in value.items():
            subs = []
            if key in properties:
                subs.append(properties[key])
            subs += [sub for pattern, sub in patterns.items() if self.bundle.matches(pattern, key)]
            if not subs and "additionalProperties" in schema:
                if schema["additionalProperties"] is False:
                    issues.append(raw_issue("E1403", pointer, {"key": key}))
                    continue
                subs.append(schema["additionalProperties"])
            if any(sub is False for sub in subs):
                issues.append(raw_issue("E1404", pointer, {"key": key}))
                continue
            for sub in subs:
                issues += self.validate(item, Node(sub, base), child_pointer(pointer, key))
        return issues

    def alternative_issues(
        self, value: Any, keyword: str, alternatives: list[Any], base: str, pointer: str
    ) -> list[RawIssue]:
        """anyOf and oneOf (errors.md, Structural validation, rule 5)."""
        results = [self.validate(value, Node(sub, base), pointer) for sub in alternatives]
        matches = sum(not result for result in results)
        if keyword == "oneOf" and matches > 1:
            return [raw_issue("E1422", pointer)]
        if matches:
            return []
        qualifying = [
            index
            for index, sub in enumerate(alternatives)
            if not isinstance(sub, dict)
            or "type" not in sub
            or any(has_json_type(value, name) for name in _types(sub))
        ]
        if len(qualifying) == 1:
            return results[qualifying[0]]
        return [raw_issue("E1421", pointer)]

    def definition_issues(self, value: Any, node: Node, pointer: str) -> list[RawIssue]:
        """The rules that the schemas state in descriptions and the validators
        check in code (errors.md, Structural validation).

        The day of a UTC timestamp or a date, the significant digits of a
        decimal constant, characters outside the BMP in a column name and in
        the variables of an estimand term (declarations.md, Order of checks).
        They run where a reference reaches the definition and the value has
        passed its type keyword.
        """
        ref = node.ref
        schema = node.schema
        if ref == "urn:mixedcheck:schema:defs#/$defs/column_name":
            if isinstance(value, str) and has_non_bmp(value):
                return [raw_issue("E1207", pointer)]
        elif ref in (
            "urn:mixedcheck:schema:defs#/$defs/utc_timestamp",
            "urn:mixedcheck:schema:defs#/$defs/date",
        ):
            if (
                isinstance(value, str)
                and self.bundle.matches(schema["pattern"], value)
                and not calendar_day_exists(value)
            ):
                return [raw_issue("E1406", pointer, {"form": schema["title"]})]
        elif ref == "urn:mixedcheck:schema:defs#/$defs/decimal_constant":
            if isinstance(value, dict):
                digits = value.get("significant_digits")
                text = value.get("value")
                form = self.bundle.resolve("#/$defs/decimal_string", node.base).schema["pattern"]
                if (
                    isinstance(digits, int | float)
                    and is_json_integer(digits)
                    and isinstance(text, str)
                    and self.bundle.matches(form, text)
                    and significant_digit_count(text) > digits
                ):
                    return [
                        raw_issue(
                            "E1406", child_pointer(pointer, "value"), {"form": schema["title"]}
                        )
                    ]
        elif ref == "urn:mixedcheck:schema:declaration#/$defs/term":
            if (
                isinstance(value, str)
                and self.bundle.matches(schema["pattern"], value)
                and any(has_non_bmp(name) for name in term_variables(value))
            ):
                return [raw_issue("E1207", pointer)]
        return []


def calendar_day_exists(text: str) -> bool:
    """Whether the day of a string that matches the pattern of a date or a UTC
    timestamp, YYYY-MM-DD..., exists in its month, in integer arithmetic."""
    year = int(text[0:4])
    month = int(text[5:7])
    day = int(text[8:10])
    days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
    if month == 2 and leap:
        days = 29
    return day <= days


def significant_digit_count(text: str) -> int:
    """The number of significant digits of a decimal string: its digits
    without leading or trailing zeros."""
    digits = "".join(char for char in text if "0" <= char <= "9")
    return len(digits.lstrip("0").rstrip("0"))


def term_variables(term: str) -> list[str]:
    """The variables of an estimand term that matches the pattern of a term:
    its bare names and its quoted names without the backquotes, in the order
    written (declarations.md, Terms used by the rules)."""
    variables = []
    i = 0
    count = len(term)
    while i < count:
        if term[i] == "`":
            j = term.index("`", i + 1)
            variables.append(term[i + 1 : j])
            i = j + 2
        else:
            j = term.find(":", i)
            if j < 0:
                j = count
            variables.append(term[i:j])
            i = j + 1
    return variables
