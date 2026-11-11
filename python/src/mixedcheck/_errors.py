"""The error catalogue, the rendering of its message templates and the errors
that carry issues (docs/spec/errors.md).

An issue is a dict with the members ``code``, ``message`` and, when the code
has a location, ``offset`` or ``pointer``, which is the JSON form ``issue`` of
defs.schema.json.
"""

from __future__ import annotations

import re
import threading
from collections.abc import Iterable, Mapping, Sequence
from importlib.resources import files
from typing import Any, NoReturn

Issue = dict[str, Any]

MAX_ISSUES = 100

_PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")

# The catalogue, read once per session, whether it is being read and the lock
# that lets one thread read it while the others wait.
_catalogue: dict[str, dict[str, Any]] | None = None
_loading: list[bool] = [False]
_lock = threading.RLock()


class MixedcheckError(ValueError):
    """An error that carries the issues of the shared error catalogue.

    Its message is the message of the first issue, followed by one line for
    each further issue, and ``issues`` holds the list of issues, each with the
    ``code`` of the shared error catalogue, the rendered ``message`` and the
    byte ``offset`` or the JSON ``pointer`` at which the problem lies, when the
    code has a location.
    """

    def __init__(self, issues: list[Issue]) -> None:
        self.issues = issues
        super().__init__("\n".join(issue["message"] for issue in issues))

    def __reduce__(self) -> tuple[Any, ...]:
        # Rebuilt from the issues, so that the error can be pickled, as a
        # process pool does, and copied.
        return (type(self), (self.issues,))


class MixedcheckWarning(UserWarning):
    """A warning that carries the issues of the shared error catalogue.

    Its message and ``issues`` are those of :class:`MixedcheckError`.
    """

    def __init__(self, issues: list[Issue]) -> None:
        self.issues = issues
        super().__init__("\n".join(issue["message"] for issue in issues))

    def __reduce__(self) -> tuple[Any, ...]:
        return (type(self), (self.issues,))


def internal_error(text: str) -> NoReturn:
    """An internal error, which indicates a bug in the package: a RuntimeError
    whose message starts with 'Internal error:'."""
    raise RuntimeError("Internal error: " + text)


def error_catalogue() -> dict[str, dict[str, Any]]:
    """Return the codes of the vendored spec/errors.json, by code."""
    global _catalogue
    catalogue = _catalogue
    if catalogue is not None:
        return catalogue
    with _lock:
        if _catalogue is not None:
            return _catalogue
        if _loading[0]:
            # Reading the catalogue itself failed in this thread, so no issue
            # can be rendered.
            raise RuntimeError("The error catalogue spec/errors.json cannot be read.")
        # Imported here, since the reader renders its own issues with the
        # catalogue.
        from mixedcheck._json_read import parse_json_bytes

        _loading[0] = True
        try:
            data = (files("mixedcheck") / "_spec" / "errors.json").read_bytes()
            document = parse_json_bytes(data, "hashable")
        except (OSError, MixedcheckError) as err:
            raise RuntimeError("The error catalogue spec/errors.json cannot be read.") from err
        finally:
            _loading[0] = False
        # Assigned whole, so that no thread sees part of the catalogue.
        _catalogue = {entry["code"]: entry for entry in document["codes"]}
        return _catalogue


def new_issue(
    code: str,
    args: Mapping[str, Any] | None = None,
    offset: int | None = None,
    pointer: str | None = None,
) -> Issue:
    """Build one issue: the code, its rendered message and its location.

    The location is a 0-based byte offset or a JSON Pointer, as the code's
    location member allows.
    """
    entry = error_catalogue().get(code)
    if entry is None:
        internal_error(f"unknown error code '{code}'.")
    allowed = {
        "none": (),
        "offset": ("offset",),
        "pointer": ("pointer",),
        "offset_or_pointer": ("offset", "pointer"),
    }[entry["location"]]
    given = [
        name for name, value in (("offset", offset), ("pointer", pointer)) if value is not None
    ]
    if len(given) > 1 or not all(name in allowed for name in given) or (allowed and not given):
        internal_error(f"wrong location for {code}.")
    location: int | str | None = offset if offset is not None else pointer
    issue: Issue = {"code": code, "message": render_template(entry, args or {}, location)}
    if offset is not None:
        issue["offset"] = int(offset)
    if pointer is not None:
        issue["pointer"] = pointer
    return issue


def render_template(entry: Mapping[str, Any], args: Mapping[str, Any], location: Any) -> str:
    """Render a template, replacing each placeholder by its argument rendered
    according to the kind that the catalogue gives it."""
    kinds = entry["args"]

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name == "location":
            return render_location(location)
        if name not in kinds or name not in args:
            internal_error(f"no argument '{name}' for {entry['code']}.")
        return render_argument(args[name], kinds[name])

    return _PLACEHOLDER.sub(replace, entry["template"])


def render_location(location: Any) -> str:
    """Render an offset as 'byte n' and a pointer after display escaping, or
    as '(root)' for the empty pointer."""
    if isinstance(location, int):
        return f"byte {location}"
    if location == "":
        return "(root)"
    return display_text(location, limit=None)


def render_argument(value: Any, kind: str) -> str:
    """Render an argument according to its kind (errors.md, Rendering messages)."""
    if kind == "text":
        return display_text(value)
    if kind == "integer":
        return format_integer(value)
    if kind == "number":
        from mixedcheck._numbers import format_number

        return format_number(value)
    if kind == "codepoint":
        return f"{int(value):04X}"
    if kind == "values":
        return join_alternatives([render_json_value(item) for item in value])
    if kind == "words":
        words = [value] if isinstance(value, str) else [str(item) for item in value]
        return join_alternatives(words)
    internal_error(f"unknown argument kind '{kind}'.")


def render_json_value(value: Any) -> str:
    """Render one JSON value for the kind 'values'."""
    if value is None:
        return "null"
    if isinstance(value, str):
        return "'" + display_text(value) + "'"
    if isinstance(value, bool):
        return "true" if value else "false"
    from mixedcheck._numbers import format_number

    return format_number(value)


def join_alternatives(items: Sequence[str]) -> str:
    """Join items with ', ', except the last two, which are joined with ' or '."""
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + " or " + items[-1]


def format_integer(value: Any) -> str:
    """Write an integer as decimal digits, with '-' before a negative value."""
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    number = float(value)
    if abs(number) < 2**53 and number.is_integer():
        return str(int(number))
    from mixedcheck._numbers import format_number

    return format_number(number)


def display_text(text: Any, limit: int | None = 60) -> str:
    """Display escaping and truncation of errors.md.

    Each code point from U+0000 to U+001F, from U+007F to U+009F and U+2028
    and U+2029 is written as '\\u' and four upper-case hexadecimal digits, and
    a text of more than ``limit`` code points after escaping keeps its first
    ``limit - 3`` code points followed by '...'.
    """
    text = str(text)
    out = []
    for char in text:
        point = ord(char)
        if point <= 0x1F or 0x7F <= point <= 0x9F or point in (0x2028, 0x2029):
            out.append(f"\\u{point:04X}")
        else:
            out.append(char)
    escaped = "".join(out)
    if limit is not None and len(escaped) > limit:
        escaped = escaped[: limit - 3] + "..."
    return escaped


def raise_issue(
    code: str,
    args: Mapping[str, Any] | None = None,
    offset: int | None = None,
    pointer: str | None = None,
) -> NoReturn:
    """Raise a MixedcheckError with one issue."""
    raise MixedcheckError([new_issue(code, args, offset=offset, pointer=pointer)])


def raw_issue(
    code: str, pointer: str | None = None, args: Mapping[str, Any] | None = None
) -> dict[str, Any]:
    """A raw issue for finish_issues(): the code, its arguments and its pointer."""
    return {"code": code, "args": dict(args or {}), "pointer": pointer}


def finish_issues(raw: Iterable[Mapping[str, Any]], limit: int = MAX_ISSUES) -> list[Issue]:
    """The issues of one phase of a validator, sorted and capped as errors.md
    (Reporting rules) requires.

    The issues are rendered, sorted by pointer, code and message, compared
    code point by code point with a prefix first, reported once each and capped
    at ``limit``, with W1490 giving the number left out.
    """
    issues = [new_issue(item["code"], item["args"], pointer=item["pointer"]) for item in raw]
    issues.sort(key=lambda issue: (issue.get("pointer", ""), issue["code"], issue["message"]))
    unique: list[Issue] = []
    for issue in issues:
        if unique and _issue_key(unique[-1]) == _issue_key(issue):
            continue
        unique.append(issue)
    if len(unique) > limit:
        rest = len(unique) - limit
        unique = unique[:limit] + [new_issue("W1490", {"count": rest})]
    return unique


def _issue_key(issue: Issue) -> tuple[str, str, str]:
    return (issue.get("pointer", ""), issue["code"], issue["message"])
