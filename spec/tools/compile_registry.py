#!/usr/bin/env python3
"""Compile the registry sources into the canonical compiled registry.

Usage, from the repository root:

    python3 spec/tools/compile_registry.py           # write spec/compiled/registry.json
    python3 spec/tools/compile_registry.py --check   # report whether it is up to date

The sources are spec/registry/registry.yaml, which holds the members of the
compiled registry other than the entries and the version, and one YAML file per
check in spec/registry/checks/, named after the check's identifier. The script
reads each source with every scalar as a string, coerces the scalars to the
types that the schema requires at their positions, checks the hashable profile,
validates each source against spec/schemas/registry-entry.schema.json and
applies the rules enforced in code. It then assembles the entries in ascending
order of identifier with the registry version from spec/versions.json,
validates the result against spec/schemas/registry.schema.json and writes its
RFC 8785 canonical bytes. docs/spec/registry.md describes each step, and every
problem is reported with a code of spec/errors.json, rendered as
docs/spec/errors.md describes.

The script uses the Python standard library and PyYAML built with libyaml. It
runs from the repository and is never shipped with either package, which read only the
compiled JSON.
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
import sys
import unicodedata
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover - reported as E3001 when a source is read
    yaml = None

CHECKS_DIR = "spec/registry/checks"
TOP_SOURCE = "spec/registry/registry.yaml"
OUTPUT = "spec/compiled/registry.json"
SCHEMAS_DIR = "spec/schemas"
ERRORS = "spec/errors.json"
VERSIONS = "spec/versions.json"
ENTRY_SCHEMA = "urn:mixedcheck:schema:registry-entry"
REGISTRY_SCHEMA = "urn:mixedcheck:schema:registry"
MAX_INTEGER = 9007199254740991
MAX_DEPTH = 64
MAX_ISSUES = 100
BOM = b"\xef\xbb\xbf"
INTEGER_TEXT = re.compile(r"-?(0|[1-9][0-9]*)")
NUMBER_TEXT = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")
PLACEHOLDER = re.compile(r"\{([a-z][a-z0-9_]{0,47})\}")
# The names of the elements of each scope, which message arguments of source
# 'scope' may name (docs/spec/registry.md, Scopes).
SCOPE_ELEMENTS = {
    "assignment": {"column", "unit"},
    "column": {"column"},
    "fixed_term": {"term"},
    "fixed_term_by_factor": {"factor", "term"},
    "grouping_column_pair": {"first", "second"},
    "grouping_factor": {"factor"},
    "grouping_factor_or_model": {"factor"},
    "grouping_factor_pair": {"first", "second"},
    "model": set(),
    "random_term": {"factor", "term"},
}
THRESHOLD_KINDS = {"count", "ratio", "real"}
UNRENDERABLE_KINDS = {"boolean", "reals"}
DIGIT_KINDS = {"ratio", "real"}
# Parameters whose value must be the same in every entry that has one (E4022).
SHARED_PARAMETERS = ("agreement",)


def can_be_unwritten(statistic: dict) -> bool:
    """Whether the privacy filter can suppress a statistic, or its definition
    leave it absent in a way that a message must allow for (registry.md,
    Messages): ratios, reals and labels, person and by_unit counts, and any
    statistic that is internal_only or suppressed with another."""
    kind = statistic["kind"]
    return (
        kind in ("ratio", "real", "labels")
        or (kind == "count" and statistic["count_class"] != "non_person")
        or bool(statistic.get("internal_only"))
        or "suppress_with" in statistic
    )


# Issues and the error catalogue -------------------------------------------------


@dataclass(frozen=True)
class Issue:
    """One problem, with its code, rendered message and location."""

    code: str
    message: str
    pointer: str | None = None
    offset: int | None = None

    def sort_key(self) -> tuple[str, str, str]:
        return (self.pointer or "", self.code, self.message)


def display_escape(text: str) -> str:
    """Escape control characters and line separators as errors.md requires."""
    out = []
    for char in text:
        point = ord(char)
        if point <= 0x1F or 0x7F <= point <= 0x9F or point in (0x2028, 0x2029):
            out.append(f"\\u{point:04X}")
        else:
            out.append(char)
    return "".join(out)


def _truncate(text: str) -> str:
    return text if len(text) <= 60 else text[:57] + "..."


def _join(items: list[str]) -> str:
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + " or " + items[-1]


def _render_value(value: Any) -> str:
    if isinstance(value, str):
        return "'" + _truncate(display_escape(value)) + "'"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    return format_number(value)


class Catalogue:
    """The codes of spec/errors.json, rendered as docs/spec/errors.md describes."""

    def __init__(self, path: Path) -> None:
        data = load_json(path)
        self.by_name = {entry["name"]: entry for entry in data["codes"]}

    def issue(
        self,
        code_name: str,
        /,
        *,
        pointer: str | None = None,
        offset: int | None = None,
        **args: Any,
    ) -> Issue:
        entry = self.by_name[code_name]
        rendered = {}
        if entry["location"] != "none":
            if offset is not None:
                rendered["location"] = f"byte {offset}"
            else:
                rendered["location"] = display_escape(pointer) if pointer else "(root)"
        for key, kind in entry["args"].items():
            value = args[key]
            if kind == "text":
                rendered[key] = _truncate(display_escape(str(value)))
            elif kind == "integer":
                rendered[key] = str(int(value))
            elif kind == "number":
                rendered[key] = format_number(value)
            elif kind == "codepoint":
                rendered[key] = f"{value:04X}"
            elif kind == "values":
                rendered[key] = _join([_render_value(item) for item in value])
            else:  # words
                rendered[key] = _join([str(item) for item in value])
        message = PLACEHOLDER.sub(lambda match: rendered[match.group(1)], entry["template"])
        if entry["location"] == "none":
            pointer = offset = None
        return Issue(entry["code"], message, pointer, offset)


def finish(issues: list[Issue], catalogue: Catalogue) -> list[Issue]:
    """Sort the issues of a phase, report each once and cap them at 100, as errors.md requires."""
    ordered = sorted(set(issues), key=Issue.sort_key)
    if len(ordered) > MAX_ISSUES:
        rest = len(ordered) - MAX_ISSUES
        ordered = ordered[:MAX_ISSUES] + [catalogue.issue("schema_issues_truncated", count=rest)]
    return ordered


# JSON files of the repository ---------------------------------------------------


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key {key!r}")
        result[key] = value
    return result


def _reject_constant(name: str) -> Any:
    raise ValueError(f"non-finite number {name}")


def load_json(path: Path) -> Any:
    """Read a human-maintained JSON file of the repository, such as a schema."""
    data = path.read_bytes()
    if data.startswith(BOM) or b"\r" in data:
        raise ValueError(f"{path} has a byte-order mark or a carriage return")
    return json.loads(
        data.decode("utf-8"),
        object_pairs_hook=_reject_duplicates,
        parse_constant=_reject_constant,
    )


# RFC 8785 serialisation ---------------------------------------------------------


def format_number(value: int | float) -> str:
    """Write a finite number as ECMAScript's Number::toString does (RFC 8785)."""
    if isinstance(value, bool):
        raise TypeError("a boolean is not a number")
    if isinstance(value, int):
        if abs(value) > MAX_INTEGER:
            raise ValueError("integer outside the range of the profiles")
        value = float(value)
    if value != value or value in (float("inf"), float("-inf")):
        raise ValueError("non-finite number")
    if value == 0:
        return "0"
    if value < 0:
        return "-" + format_number(-value)
    # repr() gives the shortest digits that round-trip, laid out differently.
    mantissa, _, exponent_text = repr(value).partition("e")
    exponent = int(exponent_text) if exponent_text else 0
    whole, _, fraction = mantissa.partition(".")
    if whole.strip("0") == "":
        n = exponent - (len(fraction) - len(fraction.lstrip("0")))
    else:
        n = len(whole.lstrip("0")) + exponent
    digits = (whole + fraction).strip("0")
    k = len(digits)
    if k <= n <= 21:
        return digits + "0" * (n - k)
    if 0 < n <= 21:
        return digits[:n] + "." + digits[n:]
    if -6 < n <= 0:
        return "0." + "0" * (-n) + digits
    tail = "." + digits[1:] if k > 1 else ""
    sign = "+" if n - 1 >= 0 else "-"
    return digits[0] + tail + "e" + sign + str(abs(n - 1))


_ESCAPES = {
    0x22: '\\"',
    0x5C: "\\\\",
    0x08: "\\b",
    0x09: "\\t",
    0x0A: "\\n",
    0x0C: "\\f",
    0x0D: "\\r",
}


def _write_string(text: str, out: list[str]) -> None:
    out.append('"')
    for char in text:
        point = ord(char)
        if point in _ESCAPES:
            out.append(_ESCAPES[point])
        elif point < 0x20:
            out.append(f"\\u{point:04x}")
        else:
            out.append(char)
    out.append('"')


def _utf16_key(key: str) -> bytes:
    return key.encode("utf-16-be", "surrogatepass")


def _write(value: Any, out: list[str]) -> None:
    if value is None:
        out.append("null")
    elif value is True:
        out.append("true")
    elif value is False:
        out.append("false")
    elif isinstance(value, int | float):
        out.append(format_number(value))
    elif isinstance(value, str):
        _write_string(value, out)
    elif isinstance(value, list):
        out.append("[")
        for index, item in enumerate(value):
            if index:
                out.append(",")
            _write(item, out)
        out.append("]")
    elif isinstance(value, dict):
        out.append("{")
        for index, key in enumerate(sorted(value, key=_utf16_key)):
            if index:
                out.append(",")
            _write_string(key, out)
            out.append(":")
            _write(value[key], out)
        out.append("}")
    else:
        raise TypeError(f"no JSON form for {type(value).__name__}")


def canonical_bytes(value: Any) -> bytes:
    """The RFC 8785 serialisation of a value, encoded in UTF-8."""
    out: list[str] = []
    _write(value, out)
    return "".join(out).encode("utf-8")


# Reading YAML sources ----------------------------------------------------------


class _Refused(Exception):
    def __init__(self, issue: Issue) -> None:
        super().__init__(issue.message)
        self.issue = issue


def read_bytes(path: Path, catalogue: Catalogue) -> tuple[str | None, Issue | None]:
    """Read a file and validate it as UTF-8 text without a byte-order mark."""
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return None, catalogue.issue("input_file_missing")
    except OSError:
        return None, catalogue.issue("input_file_unreadable")
    if data.startswith(BOM):
        return None, catalogue.issue("input_byte_order_mark")
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError as err:
        return None, catalogue.issue("unicode_invalid_utf8", offset=err.start)


# libyaml ends lines at LF, CR LF, CR, U+0085, U+2028 and U+2029.
_BREAKS = "\r\n\x85\u2028\u2029"
_BLANKS = " \t"
_ENDS = " \t" + _BREAKS


def _byte_offset(text: str, index: int) -> int:
    return len(text[:index].encode("utf-8"))


def yaml_prescan(text: str) -> tuple[str, int | None] | None:
    """The first problem that the pre-scan of conventions.md (YAML authoring) finds.

    Returns the name of the code with the byte offset of the problem, or with
    None for a text without content (E3010), or None when there is none.
    """
    n = len(text)
    nul = text.find("\x00")

    def found(name: str, index: int) -> tuple[str, int | None]:
        if 0 <= nul < index:
            return "unicode_nul", _byte_offset(text, nul)
        return name, _byte_offset(text, index)

    def follows_end(j: int) -> bool:
        return j >= n or text[j] in _ENDS

    i = 0
    content = False
    ended = False
    depth = 0
    node_start = False
    after_quote = False
    line_begin = 0
    indent = 0
    at_line_start = True
    while i < n:
        if at_line_start:
            at_line_start = False
            line_begin = i
            if text[i] == "%":
                return found("yaml_tag", i)
            if text.startswith(("---", "..."), i) and follows_end(i + 3):
                if text[i] == "-":
                    if content:
                        return found("yaml_document_count", i)
                    node_start = True
                else:
                    ended = True
                    node_start = False
                i += 3
                continue
            j = i
            while j < n and text[j] == " ":
                j += 1
            indent = j - i
            node_start = True
            after_quote = False
        c = text[i]
        if c in _BREAKS:
            i += 2 if text.startswith("\r\n", i) else 1
            at_line_start = True
            continue
        if c in _BLANKS:
            i += 1
            continue
        if c == "#" and (i == line_begin or text[i - 1] in _BLANKS):
            while i < n and text[i] not in _BREAKS:
                i += 1
            continue
        if c == "\x00":
            return found("unicode_nul", i)
        if ended:
            return found("yaml_document_count", i)
        content = True
        if not node_start:
            # libyaml reads '?' and ':' outside a scalar as indicators
            # whatever follows them while a bracket is open.
            if c in "-?:" and (
                follows_end(i + 1) or (c == ":" and after_quote) or (c != "-" and depth)
            ):
                node_start = True
            elif c == "," and depth:
                node_start = True
            elif c in "[{":
                depth += 1
                node_start = True
            elif c in "]}":
                depth = max(0, depth - 1)
            after_quote = False
            i += 1
            continue
        node_start = False
        after_quote = False
        if c in "&*":
            return found("yaml_anchor_alias", i)
        if c == "!":
            return found("yaml_tag", i)
        if c in "-?:" and (follows_end(i + 1) or (c != "-" and depth)):
            node_start = True
            i += 1
            continue
        if c in "[{":
            depth += 1
            node_start = True
            i += 1
            continue
        if c in "]}":
            depth = max(0, depth - 1)
            i += 1
            continue
        if c == "'":
            i += 1
            while i < n:
                if text[i] == "'":
                    if text.startswith("''", i):
                        i += 2
                        continue
                    break
                i += 1
            i += 1
            after_quote = True
            continue
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    for escape in ("\\0", "\\x00", "\\u0000", "\\U00000000"):
                        if text.startswith(escape, i):
                            return found("unicode_nul", i)
                    i += 2
                    continue
                i += 1
            i += 1
            after_quote = True
            continue
        if c in "|>" and not depth:
            while i < n and text[i] not in _BREAKS:
                i += 1
            while i < n:
                i += 2 if text.startswith("\r\n", i) else 1
                j = i
                while j < n and text[j] == " ":
                    j += 1
                k = j
                while k < n and text[k] in _BLANKS:
                    k += 1
                if k < n and text[k] not in _BREAKS and j - i <= indent:
                    break
                while i < n and text[i] not in _BREAKS:
                    if text[i] == "\x00":
                        return found("unicode_nul", i)
                    i += 1
            at_line_start = True
            continue
        if text.startswith("<<", i):
            # A plain scalar that starts with '<<', which R's yaml package can
            # read as a merge key whatever follows.
            return found("yaml_merge_key", i)
        while i < n:
            ch = text[i]
            if ch in _BREAKS:
                break
            if ch == ":" and follows_end(i + 1):
                break
            if ch in _BLANKS and i + 1 < n and text[i + 1] == "#":
                break
            if depth and ch in ",[]{}":
                break
            if ch == "\x00":
                return found("unicode_nul", i)
            i += 1
    if 0 <= nul:
        return "unicode_nul", _byte_offset(text, nul)
    if not content:
        return "yaml_no_document", None
    return None


def parse_yaml(text: str, catalogue: Catalogue) -> tuple[Any, Issue | None]:
    """Read YAML text with every scalar as a string (conventions.md, YAML authoring).

    The pre-scan runs first, then libyaml through yaml.CBaseLoader, whose events
    are processed in order: a parser failure (E3002) or a mapping that ends with
    two equal keys (E3007) is reported, whichever comes first. The keys are then
    checked for sequences or mappings (E3006) and empty strings (E1109).
    """
    if yaml is None:
        return None, catalogue.issue("yaml_package_missing", package="PyYAML")
    if not getattr(yaml, "__with_libyaml__", False):
        return None, catalogue.issue("yaml_package_missing", package="PyYAML built with libyaml")
    problem = yaml_prescan(text)
    if problem is not None:
        name, offset = problem
        if offset is not None:
            return None, catalogue.issue(name, offset=offset)
        return None, catalogue.issue(name)
    events = yaml.parse(text, Loader=yaml.CBaseLoader)

    def next_event() -> Any:
        try:
            return next(events)
        except yaml.YAMLError:
            raise _Refused(catalogue.issue("yaml_syntax")) from None
        except StopIteration:
            # A stream without a document, which the pre-scan refuses unless
            # it misses one.
            raise _Refused(catalogue.issue("yaml_no_document")) from None

    def node(event: Any) -> Any:
        if isinstance(event, yaml.ScalarEvent):
            return event.value
        if isinstance(event, yaml.SequenceStartEvent):
            items = []
            while not isinstance(event := next_event(), yaml.SequenceEndEvent):
                items.append(node(event))
            return items
        pairs: list[tuple[Any, Any]] = []
        while not isinstance(event := next_event(), yaml.MappingEndEvent):
            key = node(event)
            pairs.append((key, node(next_event())))
        keys = [key for key, _ in pairs]
        if any(key in keys[:index] for index, key in enumerate(keys)):
            raise _Refused(catalogue.issue("yaml_duplicate_key"))
        return _Mapping(pairs)

    try:
        while not isinstance(next_event(), yaml.DocumentStartEvent):
            pass
        value = node(next_event())
        while not isinstance(event := next_event(), yaml.StreamEndEvent):
            if isinstance(event, yaml.DocumentStartEvent):
                # A second document, which the pre-scan always finds first.
                raise _Refused(
                    catalogue.issue(
                        "internal_error", detail="the pre-scan missed a second YAML document"
                    )
                )
    except _Refused as refused:
        return None, refused.issue

    def keys(item: Any, pointer: str) -> Issue | None:
        if isinstance(item, _Mapping):
            for key, sub in item:
                if not isinstance(key, str):
                    return catalogue.issue("yaml_complex_key", pointer=pointer)
                if key == "":
                    return catalogue.issue("profile_empty_key", pointer=child_pointer(pointer, key))
                if (issue := keys(sub, child_pointer(pointer, key))) is not None:
                    return issue
        elif isinstance(item, list):
            for index, sub in enumerate(item):
                if (issue := keys(sub, child_pointer(pointer, index))) is not None:
                    return issue
        return None

    def plain(item: Any) -> Any:
        if isinstance(item, _Mapping):
            return {key: plain(sub) for key, sub in item}
        if isinstance(item, list):
            return [plain(sub) for sub in item]
        return item

    issue = keys(value, "")
    if issue is not None:
        return None, issue
    return plain(value), None


class _Mapping(list):
    """The (key, value) pairs of a YAML mapping, in the order of the text."""


# Schemas -------------------------------------------------------------------------

Node = tuple[Any, str]
Flagged = tuple[Node, bool]


def _escape_token(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


def child_pointer(pointer: str, token: str | int) -> str:
    return pointer + "/" + _escape_token(str(token))


def _as_list(types: Any) -> list[str]:
    return [types] if isinstance(types, str) else list(types)


def json_type(value: Any) -> str:
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
    return "object"


def _has_type(value: Any, name: str) -> bool:
    actual = json_type(value)
    if name == "integer":
        return actual == "number" and float(value).is_integer()
    return actual == name


def json_equal(left: Any, right: Any) -> bool:
    """Equality of JSON values as JSON Schema defines it."""
    if json_type(left) != json_type(right):
        return False
    if isinstance(left, list):
        return len(left) == len(right) and all(map(json_equal, left, right))
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(json_equal(left[k], right[k]) for k in left)
    return bool(left == right)


def _search(pattern: str, text: str) -> bool:
    # Python's '$' also matches before a final line feed (conventions.md, Schemas).
    if pattern.endswith("$") and not pattern.endswith("\\$"):
        pattern = pattern[:-1] + r"\Z"
    return re.search(pattern, text) is not None


class Bundle:
    """The schemas of spec/schemas/, by identifier."""

    def __init__(self, directory: Path) -> None:
        self.schemas: dict[str, Any] = {}
        for path in sorted(directory.glob("*.schema.json")):
            schema = load_json(path)
            self.schemas[schema["$id"]] = schema

    def resolve(self, ref: str, base: str) -> Node:
        document, _, fragment = ref.partition("#")
        document = document or base
        schema = self.schemas[document]
        if fragment:
            for token in fragment.lstrip("/").split("/"):
                schema = schema[token.replace("~1", "/").replace("~0", "~")]
        return schema, document

    def node(self, ref: str) -> Node:
        return self.resolve(ref, ref.partition("#")[0])

    # Types for coercion -----------------------------------------------------------
    #
    # A position is described by the schemas that may apply there, each with a
    # flag that is True when it is reached through then, else, anyOf or oneOf.
    # Only the unconditional schemas restrict the types, unless none of them
    # says anything, because which conditional branch applies depends on the
    # value that is being coerced.

    def _closure(self, nodes: list[Flagged]) -> list[Flagged]:
        out: list[Flagged] = []
        queue = list(nodes)
        while queue:
            (schema, base), conditional = queue.pop(0)
            out.append(((schema, base), conditional))
            if not isinstance(schema, dict):
                continue
            if "$ref" in schema:
                queue.append((self.resolve(schema["$ref"], base), conditional))
            queue.extend(((sub, base), conditional) for sub in schema.get("allOf", []))
            queue.extend(((schema[key], base), True) for key in ("then", "else") if key in schema)
            for key in ("anyOf", "oneOf"):
                queue.extend(((sub, base), True) for sub in schema.get(key, []))
        return out

    def _own_types(self, schema: dict, base: str) -> list[set[str]]:
        sets: list[set[str]] = []
        if "type" in schema:
            sets.append(set(_as_list(schema["type"])))
        if "enum" in schema:
            sets.append({_kind(value) for value in schema["enum"]})
        if "const" in schema:
            sets.append({_kind(schema["const"])})
        for key in ("anyOf", "oneOf"):
            if key in schema:
                union: set[str] | None = set()
                for sub in schema[key]:
                    allowed = self.allowed_types([((sub, base), False)])
                    if allowed is None:
                        union = None
                        break
                    union |= allowed
                if union is not None:
                    sets.append(union)
        return [allowed | {"integer"} if "number" in allowed else allowed for allowed in sets]

    def allowed_types(self, nodes: list[Flagged]) -> set[str] | None:
        """The JSON types allowed at a position, or None when any type is."""
        closure = self._closure(nodes)
        result: set[str] | None = None
        for (schema, base), conditional in closure:
            if conditional:
                continue
            if schema is False:
                return set()
            if isinstance(schema, dict):
                for allowed in self._own_types(schema, base):
                    result = allowed if result is None else result & allowed
        if result is None:
            for (schema, base), conditional in closure:
                if conditional and isinstance(schema, dict):
                    for allowed in self._own_types(schema, base):
                        result = allowed if result is None else result | allowed
        return result

    def children(self, nodes: list[Flagged], token: str | int) -> list[Flagged]:
        """The schemas that may apply to a member or item of a value."""
        out: list[Flagged] = []
        for (schema, base), conditional in self._closure(nodes):
            if not isinstance(schema, dict):
                continue
            if isinstance(token, int):
                prefix = schema.get("prefixItems", [])
                if token < len(prefix):
                    out.append(((prefix[token], base), conditional))
                elif "items" in schema:
                    out.append(((schema["items"], base), conditional))
                continue
            covered = False
            if token in schema.get("properties", {}):
                out.append(((schema["properties"][token], base), conditional))
                covered = True
            for pattern, sub in schema.get("patternProperties", {}).items():
                if _search(pattern, token):
                    out.append(((sub, base), conditional))
                    covered = True
            if not covered and "additionalProperties" in schema:
                out.append(((schema["additionalProperties"], base), conditional))
        return out


def _kind(value: Any) -> str:
    kind = json_type(value)
    return "integer" if kind == "number" and float(value).is_integer() else kind


# Coercion and the hashable profile --------------------------------------------------


def _decimal_parts(text: str) -> tuple[int, int, bool]:
    """Return (n, p, is_integer) of a number token, or n = 0 for zero."""
    body = text.lstrip("-")
    mantissa, _, exponent_text = body.lower().partition("e")
    exponent = int(exponent_text) if exponent_text else 0
    whole, _, fraction = mantissa.partition(".")
    digits = (whole + fraction).lstrip("0")
    exponent -= len(fraction)
    stripped = digits.rstrip("0")
    exponent += len(digits) - len(stripped)
    if not stripped:
        return 0, 0, True
    n = len(stripped)
    return n, n + exponent - 1, exponent >= 0


class Coercer:
    """Convert the strings read from YAML to the types the schema requires."""

    def __init__(self, bundle: Bundle, catalogue: Catalogue) -> None:
        self.bundle = bundle
        self.catalogue = catalogue

    def coerce(self, value: Any, nodes: list[Flagged], pointer: str = "") -> Any:
        if isinstance(value, dict):
            return {
                key: self.coerce(
                    item, self.bundle.children(nodes, key), child_pointer(pointer, key)
                )
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [
                self.coerce(item, self.bundle.children(nodes, index), child_pointer(pointer, index))
                for index, item in enumerate(value)
            ]
        allowed = self.bundle.allowed_types(nodes)
        if allowed is None:
            return value
        if "boolean" in allowed and value in ("true", "false"):
            return value == "true"
        if "integer" in allowed and INTEGER_TEXT.fullmatch(value):
            number = int(value)
            if abs(number) > MAX_INTEGER:
                self._refuse("profile_integer_range", pointer, number=value)
            return number
        if "number" in allowed and NUMBER_TEXT.fullmatch(value):
            return self._number(value, pointer)
        if "string" in allowed or not allowed & {"boolean", "integer", "number"}:
            return value
        required = (
            "a number"
            if "number" in allowed
            else "an integer"
            if "integer" in allowed
            else "a boolean"
        )
        self._refuse("yaml_coercion", pointer, value=value, type=required)
        return value

    def _number(self, text: str, pointer: str) -> int | float:
        n, p, is_integer = _decimal_parts(text)
        if n == 0:
            return 0
        if is_integer:
            if p > 15 or (p == 15 and abs(int(Decimal(text))) > MAX_INTEGER):
                self._refuse("profile_integer_range", pointer, number=text)
        elif n > 15:
            self._refuse("profile_too_many_digits", pointer, number=text)
        elif p < -307:
            self._refuse("profile_number_too_small", pointer, number=text)
        if INTEGER_TEXT.fullmatch(text):
            return int(text)
        return float(text)

    def _refuse(self, code_name: str, pointer: str, /, **args: Any) -> None:
        raise _Refused(self.catalogue.issue(code_name, pointer=pointer, **args))


def profile_issue(
    value: Any, catalogue: Catalogue, pointer: str = "", depth: int = 0
) -> Issue | None:
    """The first violation of the hashable profile in canonical order, if any."""
    if isinstance(value, dict | list):
        if depth >= MAX_DEPTH:
            return catalogue.issue("json_too_deep", pointer=pointer, limit=MAX_DEPTH)
    if isinstance(value, dict):
        for key in sorted(value, key=_utf16_key):
            member = child_pointer(pointer, key)
            problem = _text_issue(key, member, catalogue, is_key=True)
            if problem is None:
                problem = profile_issue(value[key], catalogue, member, depth + 1)
            if problem is not None:
                return problem
        return None
    if isinstance(value, list):
        for index, item in enumerate(value):
            problem = profile_issue(item, catalogue, child_pointer(pointer, index), depth + 1)
            if problem is not None:
                return problem
        return None
    if isinstance(value, str):
        return _text_issue(value, pointer, catalogue, is_key=False)
    if value is None:
        return catalogue.issue("profile_null", pointer=pointer)
    return None


_ASSIGNED: list[tuple[int, int]] = []


def normalisable(text: str) -> bool:
    """Whether Unicode 14.0 assigns every code point of the text (conventions.md, NFC)."""
    if not _ASSIGNED:
        path = Path(__file__).resolve().parents[1] / "unicode" / "assigned-14.0.json"
        _ASSIGNED.extend((first, last) for first, last in load_json(path)["ranges"])
    starts = [first for first, _ in _ASSIGNED]
    for char in set(text):
        code = ord(char)
        index = bisect.bisect_right(starts, code) - 1
        if index < 0 or code > _ASSIGNED[index][1]:
            return False
    return True


def _text_issue(text: str, pointer: str, catalogue: Catalogue, *, is_key: bool) -> Issue | None:
    if any(0xD800 <= ord(char) <= 0xDFFF for char in text):
        return catalogue.issue("unicode_surrogate", pointer=pointer)
    if "\x00" in text:
        return catalogue.issue("unicode_nul", pointer=pointer)
    if is_key and text == "":
        return catalogue.issue("profile_empty_key", pointer=pointer)
    if is_key and any(ord(char) > 0xFFFF for char in text):
        return catalogue.issue("profile_key_outside_bmp", pointer=pointer)
    if not text.isascii() and not normalisable(text):
        return catalogue.issue("unicode_unassigned_character", pointer=pointer)
    if not unicodedata.is_normalized("NFC", text):
        return catalogue.issue("unicode_not_nfc", pointer=pointer)
    return None


# Structural validation (errors.md, Structural validation) ------------------------------


class Validator:
    """A validator for the keywords that conventions.md allows in the bundle."""

    def __init__(self, bundle: Bundle, catalogue: Catalogue) -> None:
        self.bundle = bundle
        self.catalogue = catalogue

    def validate(self, value: Any, node: Node) -> list[Issue]:
        return finish(self._validate(value, node, ""), self.catalogue)

    def is_valid(self, value: Any, node: Node) -> bool:
        return not self._validate(value, node, "")

    def _issue(self, code_name: str, pointer: str, /, **args: Any) -> Issue:
        return self.catalogue.issue(code_name, pointer=pointer, **args)

    def _unconditional_types(self, value: Any, node: Node) -> Iterator[list[str]]:
        schema, base = node
        if not isinstance(schema, dict):
            return
        if "type" in schema:
            yield _as_list(schema["type"])
        if "$ref" in schema:
            yield from self._unconditional_types(value, self.bundle.resolve(schema["$ref"], base))
        for sub in schema.get("allOf", []):
            yield from self._unconditional_types(value, (sub, base))
        if "if" in schema:
            branch = "then" if self.is_valid(value, (schema["if"], base)) else "else"
            if branch in schema:
                yield from self._unconditional_types(value, (schema[branch], base))

    def _validate(self, value: Any, node: Node, pointer: str) -> list[Issue]:
        schema, base = node
        if schema is True:
            return []
        if schema is False:
            return [self._issue("schema_not", pointer)]
        for types in self._unconditional_types(value, node):
            if not any(_has_type(value, name) for name in types):
                return [self._issue("schema_type", pointer, expected=types, found=json_type(value))]
        issues: list[Issue] = []
        self._apply(value, node, pointer, issues)
        return issues

    def _title(self, node: Node) -> str:
        schema, base = node
        while isinstance(schema, dict) and "title" not in schema and "$ref" in schema:
            schema, base = self.bundle.resolve(schema["$ref"], base)
        if isinstance(schema, dict) and "title" in schema:
            return str(schema["title"])
        return "value of the required form"

    def _apply(self, value: Any, node: Node, pointer: str, issues: list[Issue]) -> None:
        schema, base = node
        if "$ref" in schema:
            issues += self._validate(value, self.bundle.resolve(schema["$ref"], base), pointer)
        for sub in schema.get("allOf", []):
            issues += self._validate(value, (sub, base), pointer)
        if "if" in schema:
            branch = "then" if self.is_valid(value, (schema["if"], base)) else "else"
            if branch in schema:
                issues += self._validate(value, (schema[branch], base), pointer)
        if "enum" in schema and not any(json_equal(value, item) for item in schema["enum"]):
            issues.append(self._issue("schema_enum", pointer, allowed=schema["enum"]))
        if "const" in schema and not json_equal(value, schema["const"]):
            issues.append(self._issue("schema_enum", pointer, allowed=[schema["const"]]))
        if isinstance(value, str):
            self._string(value, schema, node, pointer, issues)
        elif json_type(value) == "number":
            self._number(value, schema, pointer, issues)
        elif isinstance(value, list):
            self._array(value, schema, base, pointer, issues)
        elif isinstance(value, dict):
            self._object(value, schema, base, pointer, issues)
        for key in ("anyOf", "oneOf"):
            if key in schema:
                self._alternatives(value, key, schema[key], base, pointer, issues)
        if "not" in schema and self.is_valid(value, (schema["not"], base)):
            issues.append(self._issue("schema_not", pointer))

    def _string(self, value: str, schema: dict, node: Node, pointer: str, issues: list) -> None:
        if "minLength" in schema and len(value) < schema["minLength"]:
            issues.append(self._issue("schema_too_short", pointer, limit=schema["minLength"]))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            issues.append(self._issue("schema_too_long", pointer, limit=schema["maxLength"]))
        if "pattern" in schema and not _search(schema["pattern"], value):
            issues.append(self._issue("schema_pattern", pointer, form=self._title(node)))

    def _number(self, value: Any, schema: dict, pointer: str, issues: list) -> None:
        checks: list[tuple[str, str, Callable[[Any, Any], bool]]] = [
            ("minimum", "schema_minimum", lambda v, limit: v < limit),
            ("maximum", "schema_maximum", lambda v, limit: v > limit),
            ("exclusiveMinimum", "schema_exclusive_minimum", lambda v, limit: v <= limit),
            ("exclusiveMaximum", "schema_exclusive_maximum", lambda v, limit: v >= limit),
        ]
        for keyword, name, fails in checks:
            if keyword in schema and fails(value, schema[keyword]):
                issues.append(self._issue(name, pointer, limit=schema[keyword]))

    def _array(self, value: list, schema: dict, base: str, pointer: str, issues: list) -> None:
        prefix = schema.get("prefixItems", [])
        for index, item in enumerate(value):
            if index < len(prefix):
                sub = prefix[index]
            elif "items" in schema:
                sub = schema["items"]
            else:
                continue
            issues += self._validate(item, (sub, base), child_pointer(pointer, index))
        if "minItems" in schema and len(value) < schema["minItems"]:
            issues.append(self._issue("schema_too_few_items", pointer, limit=schema["minItems"]))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            issues.append(self._issue("schema_too_many_items", pointer, limit=schema["maxItems"]))
        if schema.get("uniqueItems"):
            for index, item in enumerate(value):
                if any(json_equal(item, earlier) for earlier in value[:index]):
                    issues.append(
                        self._issue("schema_duplicate_item", child_pointer(pointer, index))
                    )
        if "contains" in schema and not any(
            self.is_valid(item, (schema["contains"], base)) for item in value
        ):
            issues.append(self._issue("schema_contains", pointer))

    def _object(self, value: dict, schema: dict, base: str, pointer: str, issues: list) -> None:
        for key in schema.get("required", []):
            if key not in value:
                issues.append(self._issue("schema_required", pointer, key=key))
        for key, required in schema.get("dependentRequired", {}).items():
            if key in value:
                for other in required:
                    if other not in value:
                        issues.append(
                            self._issue(
                                "schema_dependent_required", pointer, key=key, required=other
                            )
                        )
        if "propertyNames" in schema:
            names = (schema["propertyNames"], base)
            for key in value:
                if not self.is_valid(key, names):
                    issues.append(
                        self._issue(
                            "schema_property_name", pointer, key=key, form=self._title(names)
                        )
                    )
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            issues.append(
                self._issue("schema_too_few_members", pointer, limit=schema["minProperties"])
            )
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            issues.append(
                self._issue("schema_too_many_members", pointer, limit=schema["maxProperties"])
            )
        properties = schema.get("properties", {})
        patterns = schema.get("patternProperties", {})
        for key, item in value.items():
            subs = []
            if key in properties:
                subs.append(properties[key])
            subs += [sub for pattern, sub in patterns.items() if _search(pattern, key)]
            if not subs and "additionalProperties" in schema:
                if schema["additionalProperties"] is False:
                    issues.append(self._issue("schema_unknown_key", pointer, key=key))
                    continue
                subs.append(schema["additionalProperties"])
            if any(sub is False for sub in subs):
                issues.append(self._issue("schema_member_not_allowed", pointer, key=key))
                continue
            for sub in subs:
                issues += self._validate(item, (sub, base), child_pointer(pointer, key))

    def _alternatives(
        self, value: Any, key: str, alternatives: list, base: str, pointer: str, issues: list
    ) -> None:
        results = [self._validate(value, (sub, base), pointer) for sub in alternatives]
        matches = sum(not result for result in results)
        if key == "oneOf" and matches > 1:
            issues.append(self._issue("schema_several_alternatives", pointer))
            return
        if matches:
            return
        qualifying = [
            index
            for index, sub in enumerate(alternatives)
            if not isinstance(sub, dict)
            or "type" not in sub
            or any(_has_type(value, name) for name in _as_list(sub["type"]))
        ]
        if len(qualifying) == 1:
            issues += results[qualifying[0]]
        else:
            issues.append(self._issue("schema_no_alternative", pointer))


# Rules enforced in code (docs/spec/registry.md, Rules enforced in code) ----------------


def _placeholders(template: str) -> tuple[list[str], bool]:
    names = PLACEHOLDER.findall(template)
    stray = "{" in PLACEHOLDER.sub("", template) or "}" in PLACEHOLDER.sub("", template)
    return names, stray


def _decimal_places(text: str) -> int:
    return len(text.partition(".")[2])


def entry_issues(
    entry: dict, catalogue: Catalogue, prefix: str = "", file_id: str | None = None
) -> list[Issue]:
    """The rules enforced in code on one structurally valid entry.

    Pointers are written under `prefix`, the location of the entry in its
    document, and `file_id` is the identifier that the source file's name gives.
    """
    issues: list[Issue] = []

    def add(code_name: str, pointer: str, /, **args: Any) -> None:
        issues.append(catalogue.issue(code_name, pointer=prefix + pointer, **args))

    if file_id is not None and entry["id"] != file_id:
        add("registry_file_name", "/id", expected=file_id)
    reads, tier = set(entry["reads"]), entry["tier"]
    if (
        (tier == "T0" and "outcome" in reads)
        or (tier != "T0" and "outcome" not in reads)
        or (tier == "T1" and "predictors" in reads)
    ):
        add("registry_tier_reads", "/reads", tier=tier)
    if (tier == "T0") == (entry["sample"] == "analysis"):
        add("registry_tier_reads", "/sample", tier=tier)
    statistics = entry["statistics"]
    thresholds = entry["thresholds"]
    parameters = entry["parameters"]
    messages = entry["messages"]
    for name, threshold in thresholds.items():
        here = child_pointer("/thresholds", name)
        statistic = statistics.get(threshold["statistic"])
        if statistic is None:
            add(
                "registry_unknown_reference",
                here + "/statistic",
                kind="statistic",
                name=threshold["statistic"],
            )
        elif statistic["kind"] not in THRESHOLD_KINDS:
            add("registry_threshold_statistic", here, name=threshold["statistic"])
        else:
            kind, value = statistic["kind"], threshold["value"]
            if kind == "count" and "." in value:
                add("registry_threshold_value", here + "/value", form="an integer", kind=kind)
            if kind == "ratio" and (
                value.startswith("-")
                or (value != "1" and not value.startswith("0"))
                or _decimal_places(value) > 4
            ):
                add(
                    "registry_threshold_value",
                    here + "/value",
                    form="between 0 and 1 with at most four decimal places",
                    kind=kind,
                )
            if ("proximity" in threshold) != (kind == "real"):
                add("registry_proximity", here)
        unread = any(
            source["kind"] in ("literature", "software") and not source["full_text_read"]
            for source in threshold["sources"]
        )
        if threshold["validation"]["value"] == "validated" and unread:
            add("registry_unread_source", here + "/validation")
    for name, statistic in statistics.items():
        if statistic["kind"] != "ratio":
            continue
        here = child_pointer("/statistics", name)
        parts = [statistics.get(statistic[part]) for part in ("numerator", "denominator")]
        for part, target in zip(("numerator", "denominator"), parts, strict=True):
            if target is None:
                add(
                    "registry_unknown_reference",
                    f"{here}/{part}",
                    kind="statistic",
                    name=statistic[part],
                )
        if all(target is not None for target in parts) and any(
            target["kind"] != "count" or target["count_class"] != statistic["count_class"]
            for target in parts
        ):
            add("registry_ratio_counts", here)
    elements_of_scope = SCOPE_ELEMENTS[entry["scope"]]
    for name, statistic in statistics.items():
        here = child_pointer("/statistics", name)
        for position, ref in enumerate(statistic.get("resolved_by", [])):
            ref_here = f"{here}/resolved_by/{position}/name"
            if ref["source"] == "scope":
                if ref["name"] not in elements_of_scope:
                    add(
                        "registry_unknown_reference",
                        ref_here,
                        kind="scope element",
                        name=ref["name"],
                    )
            elif ref["name"] not in statistics:
                add("registry_unknown_reference", ref_here, kind="statistic", name=ref["name"])
            elif statistics[ref["name"]]["kind"] != "names":
                add("registry_reference_kind", ref_here, name=ref["name"], expected="of kind names")
        if "quantile" in statistic:
            target = statistic["quantile"]["n"]
            if target not in statistics:
                add(
                    "registry_unknown_reference",
                    here + "/quantile/n",
                    kind="statistic",
                    name=target,
                )
            elif statistics[target]["kind"] != "count":
                add(
                    "registry_reference_kind", here + "/quantile/n", name=target, expected="a count"
                )
        for position, target in enumerate(statistic.get("suppress_with", [])):
            if target not in statistics:
                add(
                    "registry_unknown_reference",
                    f"{here}/suppress_with/{position}",
                    kind="statistic",
                    name=target,
                )
        if "part_of" in statistic:
            target = statistic["part_of"]
            if target not in statistics:
                add("registry_unknown_reference", here + "/part_of", kind="statistic", name=target)
            elif statistics[target]["kind"] != "count" or statistics[target].get(
                "count_class"
            ) != statistic.get("count_class"):
                add(
                    "registry_reference_kind",
                    here + "/part_of",
                    name=target,
                    expected="a count of the same count class",
                )
    for index, rule in enumerate(entry["availability"]):
        if "parameter" in rule and rule["parameter"] not in parameters:
            add(
                "registry_unknown_reference",
                f"/availability/{index}/parameter",
                kind="parameter",
                name=rule["parameter"],
            )
    decision = entry["decision"]
    for index, rule in enumerate(decision["rules"]):
        here = f"/decision/rules/{index}"
        for position, name in enumerate(rule["statistics"]):
            if name not in statistics:
                add(
                    "registry_unknown_reference",
                    f"{here}/statistics/{position}",
                    kind="statistic",
                    name=name,
                )
        for position, name in enumerate(rule["thresholds"]):
            if name not in thresholds:
                add(
                    "registry_unknown_reference",
                    f"{here}/thresholds/{position}",
                    kind="threshold",
                    name=name,
                )
        if rule["message"] not in messages:
            add(
                "registry_unknown_reference",
                here + "/message",
                kind="message",
                name=rule["message"],
            )
        if rule["finding"] == "consequential" and any(
            thresholds[name]["validation"]["value"] == "descriptive"
            for name in rule["thresholds"]
            if name in thresholds
        ):
            add("registry_consequential_descriptive", here + "/finding")
    if decision["otherwise"]["message"] not in messages:
        add(
            "registry_unknown_reference",
            "/decision/otherwise/message",
            kind="message",
            name=decision["otherwise"]["message"],
        )
    elements = SCOPE_ELEMENTS[entry["scope"]]
    for name, message in messages.items():
        here = child_pointer("/messages", name)
        used, stray = _placeholders(message["template"])
        if stray:
            add("registry_template_brace", here + "/template")
        for placeholder in dict.fromkeys(used):
            if placeholder not in message["args"]:
                add("registry_template_placeholder", here + "/template", name=placeholder)
        for arg_name, arg in message["args"].items():
            arg_here = child_pointer(here + "/args", arg_name)
            if arg_name not in used:
                add("registry_unused_argument", arg_here, name=arg_name)
            source, target = arg["source"], arg["name"]
            known = {
                "statistic": statistics,
                "threshold": thresholds,
                "parameter": parameters,
                "scope": elements,
            }[source]
            if target not in known:
                kind = "scope element" if source == "scope" else source
                add("registry_unknown_reference", arg_here + "/name", kind=kind, name=target)
                continue
            statistic_kind = statistics[target]["kind"] if source == "statistic" else None
            if statistic_kind in UNRENDERABLE_KINDS:
                add("registry_message_kind", arg_here + "/name", name=target)
            elif ("digits" in arg) != (statistic_kind in DIGIT_KINDS):
                add("registry_message_digits", arg_here)
            if "noun" in arg and statistic_kind != "count":
                add("registry_reference_kind", arg_here + "/noun", name=target, expected="a count")
        unwritten = {
            arg_name
            for arg_name, arg in message["args"].items()
            if arg["source"] == "statistic"
            and arg["name"] in statistics
            and can_be_unwritten(statistics[arg["name"]])
        }
        if "fallback" in message:
            fallback_used, fallback_stray = _placeholders(message["fallback"])
            if fallback_stray:
                add("registry_template_brace", here + "/fallback")
            for placeholder in dict.fromkeys(fallback_used):
                if placeholder not in message["args"]:
                    add("registry_template_placeholder", here + "/fallback", name=placeholder)
            if unwritten & set(fallback_used):
                add("registry_message_fallback", here)
        elif unwritten:
            add("registry_message_fallback", here)
    seen: set[str] = set()
    for index, remedy in enumerate(entry["remedies"]):
        if remedy["id"] in seen:
            add("registry_duplicate_name", f"/remedies/{index}/id", name=remedy["id"])
        seen.add(remedy["id"])
    return issues


def _links(entry: dict) -> list[tuple[str, str]]:
    """(pointer, check) for every link of an entry, in pointer order."""
    return [
        (f"/links/{kind}/{index}", target)
        for kind in ("explained_by", "requires")
        for index, target in enumerate(entry["links"][kind])
    ]


def graph_issues(entries: list[tuple[str, dict]], catalogue: Catalogue) -> list[list[Issue]]:
    """The rules across entries: unique identifiers, existing links and no cycles.

    `entries` holds (prefix, entry) pairs, where the prefix locates the entry in
    its document. The issues are returned in a list parallel to `entries`. A
    link closes a cycle when the check it names reaches the linking entry
    through links, so every link on a cycle is reported.
    """
    issues: list[list[Issue]] = [[] for _ in entries]
    known: set[str] = set()
    for position, (prefix, entry) in enumerate(entries):
        if entry["id"] in known:
            issues[position].append(
                catalogue.issue("registry_duplicate_id", pointer=prefix + "/id", id=entry["id"])
            )
        known.add(entry["id"])
    edges: dict[str, list[str]] = {}
    for _, entry in entries:
        edges.setdefault(entry["id"], []).extend(
            target for _, target in _links(entry) if target in known
        )

    def reaches(start: str, goal: str) -> bool:
        seen: set[str] = set()
        stack = [start]
        while stack:
            current = stack.pop()
            if current == goal:
                return True
            if current not in seen:
                seen.add(current)
                stack.extend(edges.get(current, []))
        return False

    for name in SHARED_PARAMETERS:
        values = [
            entry["parameters"][name]["value"]
            for _, entry in entries
            if name in entry["parameters"]
        ]
        for position, (prefix, entry) in enumerate(entries):
            parameter = entry["parameters"].get(name)
            if parameter is not None and parameter["value"] != values[0]:
                issues[position].append(
                    catalogue.issue(
                        "registry_parameter_differs",
                        pointer=prefix + child_pointer("/parameters", name) + "/value",
                        expected=values[0],
                    )
                )
    for position, (prefix, entry) in enumerate(entries):
        for pointer, target in _links(entry):
            if target not in known:
                issues[position].append(
                    catalogue.issue(
                        "registry_unknown_reference",
                        pointer=prefix + pointer,
                        kind="check",
                        name=target,
                    )
                )
            elif reaches(target, entry["id"]):
                issues[position].append(
                    catalogue.issue(
                        "registry_dependency_cycle", pointer=prefix + pointer, check=target
                    )
                )
    return issues


def registry_issues(document: dict, catalogue: Catalogue) -> list[Issue]:
    """The rules enforced in code on a structurally valid compiled registry."""
    issues: list[Issue] = []
    entries = document["entries"]
    pairs = [(f"/entries/{index}", entry) for index, entry in enumerate(entries)]
    for index, (prefix, entry) in enumerate(pairs):
        if index and entry["id"] <= entries[index - 1]["id"]:
            issues.append(catalogue.issue("registry_entry_order", pointer=prefix))
        issues += entry_issues(entry, catalogue, prefix)
    for found in graph_issues(pairs, catalogue):
        issues += found
    return finish(issues, catalogue)


def compiled_registry_issues(data: bytes, catalogue: Catalogue) -> list[Issue]:
    """Check that bytes read as a compiled registry are its canonical bytes (E4018).

    The packages apply this rule when they load the vendored registry, after
    reading it with the strict reader. Here the bytes are read with json.
    """
    document = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    if canonical_bytes(document) != data:
        return [catalogue.issue("registry_not_canonical")]
    return []


# Compilation -----------------------------------------------------------------------


@dataclass
class Result:
    """The compiled bytes, or the problems found, by source file."""

    output: bytes | None
    problems: dict[str, list[Issue]]


class Compiler:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.catalogue = Catalogue(root / ERRORS)
        self.bundle = Bundle(root / SCHEMAS_DIR)
        self.validator = Validator(self.bundle, self.catalogue)
        self.coercer = Coercer(self.bundle, self.catalogue)

    def read_source(self, path: Path, node: Node) -> tuple[Any, list[Issue]]:
        """Read one YAML source and validate it structurally against a schema."""
        text, problem = read_bytes(path, self.catalogue)
        if problem is None:
            value, problem = parse_yaml(text or "", self.catalogue)
        if problem is None:
            try:
                value = self.coercer.coerce(value, [(node, False)])
            except _Refused as refused:
                problem = refused.issue
        if problem is None:
            problem = profile_issue(value, self.catalogue)
        if problem is not None:
            return None, [problem]
        return value, self.validator.validate(value, node)

    def compile(self) -> Result:
        problems: dict[str, list[Issue]] = {}
        entry_node = self.bundle.node(ENTRY_SCHEMA)
        top_node: Node = (
            {
                "type": "object",
                "additionalProperties": False,
                "required": ["privacy"],
                "properties": {"privacy": {"$ref": REGISTRY_SCHEMA + "#/$defs/privacy"}},
            },
            REGISTRY_SCHEMA,
        )
        top, found = self.read_source(self.root / TOP_SOURCE, top_node)
        if found:
            problems[TOP_SOURCE] = found
        checks = self.root / CHECKS_DIR
        paths = sorted(checks.iterdir()) if checks.is_dir() else []
        sources: list[tuple[str, dict]] = []
        for path in paths:
            relative = f"{CHECKS_DIR}/{path.name}"
            if not path.name.endswith(".yaml") or not path.is_file():
                problems[relative] = [
                    self.catalogue.issue("registry_unexpected_file", name=path.name)
                ]
                continue
            entry, found = self.read_source(path, entry_node)
            if not found:
                found = finish(
                    entry_issues(entry, self.catalogue, file_id=path.name[: -len(".yaml")]),
                    self.catalogue,
                )
            if found:
                problems[relative] = found
            else:
                sources.append((relative, entry))
        if not paths:
            problems[CHECKS_DIR] = [self.catalogue.issue("input_file_missing")]
        if problems:
            return Result(None, problems)
        # Rules across entries, reported in the source of the entry concerned.
        found_by_entry = graph_issues([("", entry) for _, entry in sources], self.catalogue)
        for (relative, _), found in zip(sources, found_by_entry, strict=True):
            if found:
                problems[relative] = finish(found, self.catalogue)
        if problems:
            return Result(None, problems)
        versions = load_json(self.root / VERSIONS)
        document = {
            "entries": sorted((entry for _, entry in sources), key=lambda entry: entry["id"]),
            "privacy": top["privacy"],
            "registry_version": versions["registry"],
        }
        problem = profile_issue(document, self.catalogue)
        found = [problem] if problem else []
        if not found:
            found = self.validator.validate(document, self.bundle.node(REGISTRY_SCHEMA))
        if not found:
            found = registry_issues(document, self.catalogue)
        if found:
            return Result(None, {OUTPUT: found})
        return Result(canonical_bytes(document), {})


def _report(problems: dict[str, list[Issue]]) -> None:
    for name in sorted(problems):
        for issue in problems[name]:
            print(f"{name}: {issue.code} {issue.message}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compile spec/registry/ into spec/compiled/registry.json."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="change nothing, and exit with status 1 if the compiled registry is not up to date",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: the root this script sits in)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()
    result = Compiler(root).compile()
    if result.output is None:
        _report(result.problems)
        count = sum(len(found) for found in result.problems.values())
        print(f"{count} problem(s). The compiled registry was not written.", file=sys.stderr)
        return 1
    target = root / OUTPUT
    current = target.read_bytes() if target.is_file() else None
    if args.check:
        if current != result.output:
            print(
                f"{OUTPUT}: does not match the sources in spec/registry/. "
                "Run 'python3 spec/tools/compile_registry.py'.",
                file=sys.stderr,
            )
            return 1
        print(f"{OUTPUT} is up to date")
        return 0
    if current == result.output:
        print(f"{OUTPUT} is up to date")
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(result.output)
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
