"""The YAML authoring reader for declarations (docs/spec/conventions.md, YAML
authoring, and docs/spec/declarations.md, YAML authoring).

It reads a text in five steps, bytes, pre-scan, parsing, keys and conversion,
and reports the first issue found. The pre-scan finds what R's yaml package
cannot report, anchors, aliases, explicit tags, merge keys and a second
document, and libyaml, through PyYAML's CBaseLoader, parses the text with every
scalar read as a string. PyYAML is an optional dependency, installed with the
extra 'yaml'.
"""

from __future__ import annotations

import importlib
import re
from types import ModuleType
from typing import Any, NoReturn

from mixedcheck._errors import MixedcheckError, new_issue, raise_issue
from mixedcheck._json_read import MAX_DEPTH, read_input_bytes
from mixedcheck._json_write import hashable_string_code, json_pointer, key_profile_code, utf16_key
from mixedcheck._numbers import MAX_INTEGER, hashable_token_code
from mixedcheck._unicode import utf8_invalid_offset

_BOM = b"\xef\xbb\xbf"
# libyaml ends lines at LF, CR LF, CR, U+0085, U+2028 and U+2029.
_BREAKS = "\r\n\x85\u2028\u2029"
_BLANKS = " \t"
_ENDS = " \t" + _BREAKS
_NUL_ESCAPES = ("\\0", "\\x00", "\\u0000", "\\U00000000")

# The forms of an integer and of a number of RFC 8259.
_INTEGER_TEXT = re.compile(r"-?(0|[1-9][0-9]*)")
_NUMBER_TEXT = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")


class _Mapping(list[Any]):
    """The (key, value) pairs of a YAML mapping, in the order of the text."""


def _import_yaml() -> ModuleType | None:
    """PyYAML, when it is installed, or None."""
    try:
        return importlib.import_module("yaml")
    except ImportError:
        return None


def yaml_module() -> ModuleType | None:
    """PyYAML, when it is installed and built with libyaml, or None."""
    yaml = _import_yaml()
    if yaml is None or not getattr(yaml, "__with_libyaml__", False):
        return None
    return yaml


def yaml_requirement() -> str:
    """What reading YAML needs when yaml_module() gives None: PyYAML, or
    PyYAML built with libyaml when PyYAML is installed without it."""
    return "PyYAML" if _import_yaml() is None else "PyYAML built with libyaml"


def read_yaml_declaration(path: str) -> Any:
    """Read a declaration written in YAML and return its JSON form."""
    data = read_input_bytes(path)
    if data.startswith(_BOM):
        raise_issue("E1003")
    invalid = utf8_invalid_offset(data)
    if invalid is not None:
        raise_issue("E1201", offset=invalid)
    yaml = yaml_module()
    if yaml is None:
        raise_issue("E3001", {"package": yaml_requirement()})
    text = data.decode("utf-8")
    problem = yaml_prescan(text)
    if problem is not None:
        code, offset = problem
        raise_issue(code, offset=offset)
    parsed = yaml_parse(text, yaml)
    yaml_check_keys(parsed, [])
    return yaml_convert_declaration(parsed)


def _byte_offset(text: str, index: int) -> int:
    return len(text[:index].encode("utf-8"))


def yaml_prescan(text: str) -> tuple[str, int | None] | None:
    """Step 2: the pre-scan of conventions.md (YAML authoring).

    Returns the code of the first problem with its byte offset, or with None
    for a text without content (E3010), or None.
    """
    n = len(text)
    nul = text.find("\x00")

    def found(code: str, index: int) -> tuple[str, int | None]:
        # The problem at the index, unless U+0000 comes earlier.
        if 0 <= nul < index:
            return "E1202", _byte_offset(text, nul)
        return code, _byte_offset(text, index)

    def follows_end(j: int) -> bool:
        # Whether position j is past the end or holds a space, a tab or a
        # line break.
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
                return found("E3005", i)
            if text.startswith(("---", "..."), i) and follows_end(i + 3):
                if text[i] == "-":
                    if content:
                        return found("E3003", i)
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
            return found("E1202", i)
        if ended:
            return found("E3003", i)
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
            return found("E3004", i)
        if c == "!":
            return found("E3005", i)
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
            # A single-quoted scalar, which ends at a quotation mark that is
            # not doubled.
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
            # A double-quoted scalar, in which the escapes of U+0000 are refused.
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    if text.startswith(_NUL_ESCAPES, i):
                        return found("E1202", i)
                    i += 2
                    continue
                i += 1
            i += 1
            after_quote = True
            continue
        if c in "|>" and not depth:
            # A block scalar: the rest of its line and every following line
            # that is empty, holds only spaces and tabs or is indented further.
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
                        return found("E1202", i)
                    i += 1
            at_line_start = True
            continue
        if text.startswith("<<", i):
            # A plain scalar that starts with '<<', which R's yaml package can
            # read as a merge key whatever follows.
            return found("E3009", i)
        # A plain scalar.
        while i < n:
            char = text[i]
            if char in _BREAKS:
                break
            if char == ":" and follows_end(i + 1):
                break
            if char in _BLANKS and i + 1 < n and text[i + 1] == "#":
                break
            if depth and char in ",[]{}":
                break
            if char == "\x00":
                return found("E1202", i)
            i += 1
    if nul >= 0:
        return "E1202", _byte_offset(text, nul)
    if not content:
        return "E3010", None
    return None


def yaml_parse(text: str, yaml: ModuleType) -> Any:
    """Step 3: parse the text with libyaml through yaml.CBaseLoader, with every
    scalar read as its text.

    The parser's events are processed in order. A failure of the parser gives
    E3002, whose cause is PyYAML's exception with the line and column of the
    problem, and a mapping that holds two equal keys when it ends gives E3007,
    whichever comes first. A mapping becomes a list of its (key, value) pairs.
    The nodes are built with a stack, so that no depth of nesting exhausts
    Python's recursion limit.
    """
    events = yaml.parse(text, Loader=yaml.CBaseLoader)

    def next_event() -> Any:
        try:
            return next(events)
        except yaml.YAMLError as err:
            raise MixedcheckError([new_issue("E3002")]) from err
        except StopIteration:
            # A stream without a document, which the pre-scan refuses unless
            # it misses one.
            raise_issue("E3010")

    def missed(what: str) -> NoReturn:
        # The pre-scan finds every anchor, alias, tag and second document, so
        # one that reaches here shows that it has failed.
        raise_issue("E9001", {"detail": f"the YAML pre-scan missed {what}"})

    while not isinstance(next_event(), yaml.DocumentStartEvent):
        pass
    # Each open node: the node and, for a mapping, the key read without its
    # value, held in a list of length one.
    stack: list[tuple[Any, list[Any]]] = []
    root: Any = None
    done = False
    while not done:
        event = next_event()
        if isinstance(event, yaml.AliasEvent) or getattr(event, "anchor", None) is not None:
            missed("an anchor or an alias")
        if getattr(event, "tag", None) is not None:
            missed("a tag")
        if isinstance(event, yaml.SequenceStartEvent):
            stack.append(([], []))
            continue
        if isinstance(event, yaml.MappingStartEvent):
            stack.append((_Mapping(), []))
            continue
        if isinstance(event, yaml.ScalarEvent):
            value = event.value
        elif isinstance(event, yaml.SequenceEndEvent | yaml.MappingEndEvent):
            value, _ = stack.pop()
            if isinstance(value, _Mapping) and _has_duplicate_keys(value):
                raise_issue("E3007")
        else:
            continue
        if not stack:
            root = value
            done = True
        elif isinstance(stack[-1][0], _Mapping):
            mapping, pending = stack[-1]
            if pending:
                mapping.append((pending.pop(), value))
            else:
                pending.append(value)
        else:
            stack[-1][0].append(value)
    while not isinstance(event := next_event(), yaml.StreamEndEvent):
        if isinstance(event, yaml.DocumentStartEvent):
            missed("a second document")
    return root


def _has_duplicate_keys(mapping: _Mapping) -> bool:
    """Whether a mapping holds two equal keys: scalars with the same text, or
    sequences or mappings with equal items in the same order."""
    seen: set[str] = set()
    for key, _ in mapping:
        text = _node_text(key)
        if text in seen:
            return True
        seen.add(text)
    return False


_CLOSE_SEQUENCE = object()
_CLOSE_MAPPING = object()
_CLOSE_PAIR = object()


def _node_text(node: Any) -> str:
    """A text that two parsed nodes share exactly when they are equal, built
    with a stack, so that no depth of nesting exhausts Python's recursion
    limit. A scalar is written with repr(), a sequence between brackets, a
    mapping between braces and each pair of a mapping between parentheses, so
    that a sequence never equals a mapping."""
    out: list[str] = []
    stack: list[Any] = [node]
    while stack:
        item = stack.pop()
        if item is _CLOSE_SEQUENCE:
            out.append("]")
        elif item is _CLOSE_MAPPING:
            out.append("}")
        elif item is _CLOSE_PAIR:
            out.append(")")
        elif isinstance(item, str):
            out.append(repr(item))
        elif isinstance(item, tuple):
            out.append("(")
            stack.extend((_CLOSE_PAIR, item[1], item[0]))
        elif isinstance(item, _Mapping):
            out.append("{")
            stack.append(_CLOSE_MAPPING)
            stack.extend(reversed(item))
        else:
            out.append("[")
            stack.append(_CLOSE_SEQUENCE)
            stack.extend(reversed(item))
    return "".join(out)


def yaml_check_keys(item: Any, tokens: list[str]) -> None:
    """Step 4: walk the parsed value depth first in the order of the text,
    each key before its value, and report the first key that is a sequence or
    a mapping (E3006, at the pointer of the mapping) or that is empty (E1109,
    at the pointer of its member)."""
    pending: list[tuple[Any, list[str]]] = [(item, tokens)]
    while pending:
        node, path = pending.pop()
        children: list[tuple[Any, list[str]]] = []
        if isinstance(node, _Mapping):
            for key, sub in node:
                if not isinstance(key, str):
                    # A key is checked before the value of an earlier member
                    # only when that value holds no key that fails.
                    children.append((_KeyProblem("E3006", json_pointer(path)), path))
                    break
                if key == "":
                    children.append((_KeyProblem("E1109", json_pointer([*path, key])), path))
                    break
                children.append((sub, [*path, key]))
        elif isinstance(node, list):
            children = [(sub, [*path, str(index)]) for index, sub in enumerate(node)]
        elif isinstance(node, _KeyProblem):
            raise_issue(node.code, pointer=node.pointer)
        pending.extend(reversed(children))


class _KeyProblem:
    """A key that step 4 refuses, placed in the order of the walk."""

    def __init__(self, code: str, pointer: str | None) -> None:
        self.code = code
        self.pointer = pointer


def _member(item: Any, key: str) -> Any:
    """The value of a member of a mapping of the parsed value, or None."""
    if not isinstance(item, _Mapping):
        return None
    for name, value in item:
        if isinstance(name, str) and name == key:
            return value
    return None


def _field_type(field: Any) -> str | None:
    """The text of the type of a field of the parsed value, or None."""
    type_text = _member(field, "type")
    return type_text if isinstance(type_text, str) else None


def yaml_convert_declaration(root: Any) -> Any:
    """Step 5: convert the parsed value to JSON.

    Mappings become objects, sequences arrays and scalars strings, which are
    coerced to the type that the declaration schema requires at their position
    (declarations.md, YAML authoring). The value is walked in the order of its
    canonical serialisation, keys before values, and the first violation of
    the hashable profile or of coercion is reported.
    """
    fields = _member(_member(root, "table"), "fields")
    if not isinstance(fields, list) or isinstance(fields, _Mapping):
        fields = None

    def position(tokens: list[str], containers: list[str]) -> tuple[str, str | None]:
        """Where the schema requires a type other than string: 'boolean',
        'number' or the type of a field, given as the field's type text, or
        'string'."""
        shape = " ".join(containers)
        count = len(tokens)
        if (
            count == 4
            and shape == "object object array object"
            and (tokens[0], tokens[1], tokens[3]) == ("table", "fields", "categoriesOrdered")
        ):
            return "boolean", None
        if (
            count == 3
            and shape == "object array object"
            and (
                (tokens[0] == "assignment" and tokens[2] == "randomised")
                or (tokens[0] == "estimands" and tokens[2] == "focal")
            )
        ):
            return "boolean", None
        if count == 2 and shape == "object object" and tokens == ["provenance", "outcome_seen"]:
            return "boolean", None
        if (
            count == 4
            and shape == "object object object array"
            and tokens[0] == "variables"
            and tokens[2] == "bounds"
        ):
            return "number", None
        category = (count == 5 and shape == "object object array object array") or (
            count == 6
            and shape == "object object array object array object"
            and tokens[5] == "value"
        )
        if category and (tokens[0], tokens[1], tokens[3]) == ("table", "fields", "categories"):
            field = fields[int(tokens[2])] if fields is not None else None
            return "typed", _field_type(field)
        if (
            count == 3
            and shape == "object object object"
            and tokens[0] == "variables"
            and tokens[2] == "event_level"
        ):
            for field in fields or []:
                name = _member(field, "name")
                if isinstance(name, str) and name == tokens[1]:
                    return "typed", _field_type(field)
            return "typed", None
        return "string", None

    def coerce(text: str, tokens: list[str], containers: list[str]) -> Any:
        pointer = json_pointer(tokens)
        kind, type_text = position(tokens, containers)
        if kind == "typed":
            if type_text == "string":
                kind = "string"
            elif type_text == "integer" or _INTEGER_TEXT.fullmatch(text):
                kind = "integer"
            else:
                kind = "string"
        if kind == "boolean":
            if text not in ("true", "false"):
                raise_issue("E3008", {"value": text, "type": "a boolean"}, pointer=pointer)
            return text == "true"
        if kind in ("integer", "number"):
            form = _INTEGER_TEXT if kind == "integer" else _NUMBER_TEXT
            if form.fullmatch(text) is None:
                required = "an integer" if kind == "integer" else "a number"
                raise_issue("E3008", {"value": text, "type": required}, pointer=pointer)
            code = hashable_token_code(text)
            if code is not None:
                raise_issue(code, {"number": text}, pointer=pointer)
            if _INTEGER_TEXT.fullmatch(text) and abs(int(text)) <= MAX_INTEGER:
                return int(text)
            return float(text)
        code = hashable_string_code(text)
        if code is not None:
            raise_issue(code, pointer=pointer)
        return text

    def convert(item: Any, tokens: list[str], containers: list[str], depth: int) -> Any:
        if isinstance(item, _Mapping):
            if depth == MAX_DEPTH:
                raise_issue("E1030", {"limit": MAX_DEPTH}, pointer=json_pointer(tokens))
            result: dict[str, Any] = {}
            for key, _ in item:
                result[key] = None
            values = dict(item)
            for key in sorted(values, key=utf16_key):
                code = key_profile_code(key, "hashable")
                if code is not None:
                    raise_issue(code, pointer=json_pointer([*tokens, key]))
                result[key] = convert(
                    values[key], [*tokens, key], [*containers, "object"], depth + 1
                )
            return result
        if isinstance(item, list):
            if depth == MAX_DEPTH:
                raise_issue("E1030", {"limit": MAX_DEPTH}, pointer=json_pointer(tokens))
            return [
                convert(sub, [*tokens, str(index)], [*containers, "array"], depth + 1)
                for index, sub in enumerate(item)
            ]
        return coerce(item, tokens, containers)

    return convert(root, [], [], 0)
