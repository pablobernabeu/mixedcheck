"""The RFC 8785 serialiser (docs/spec/conventions.md, Serialisation and
Profiles).

It checks a value in the order of its canonical serialisation, keys before
values, reports the first violation by JSON Pointer and writes the canonical
bytes.
"""

from __future__ import annotations

import math
import re
import sys
import unicodedata
from typing import Any, NoReturn

from mixedcheck._errors import raise_issue
from mixedcheck._hash import hash_bytes
from mixedcheck._json_read import MAX_DEPTH, check_profile
from mixedcheck._numbers import MAX_INTEGER, ecmascript_layout, shortest_parts
from mixedcheck._unicode import has_non_bmp, has_surrogate, is_normalisable

_SPECIAL = re.compile(r'[\x00-\x1f"\\]')
_SHORT_ESCAPES = {
    0x08: "\\b",
    0x09: "\\t",
    0x0A: "\\n",
    0x0C: "\\f",
    0x0D: "\\r",
    0x22: '\\"',
    0x5C: "\\\\",
}


def canonical_bytes(x: Any, profile: str = "data") -> bytes:
    """Canonical bytes of a value.

    Serialises a Python value as JSON by RFC 8785, the JSON Canonicalization
    Scheme, and returns its UTF-8 bytes: members sorted by their keys, no white
    space, strings with the minimal escapes and numbers written as ECMAScript
    writes them, the shortest decimal that converts back to the same double.
    The value is checked against the rules of the profile first.

    A dict with str keys is an object and a list an array, a str a string, an
    int or a float a number and a bool a boolean, and numpy's integer,
    floating and bool scalars are converted with int(), float() and bool().
    ``None`` is null, which only the data profile and the plain mode accept.
    In the data profile and the plain mode, NaN and the infinities are written
    as the strings 'NaN', 'Infinity' and '-Infinity'. An int must lie within
    +-9007199254740991, the range in which the reader returns integers as int
    and in which every integer and its neighbours are exact doubles, so larger
    integers are passed as floats. A str must not hold a surrogate code point.

    Args:
        x: The value to write.
        profile: The profile: ``"data"``, ``"hashable"`` or ``"plain"``.

    Returns:
        The canonical bytes.

    Raises:
        MixedcheckError: A value that cannot be written, whose ``issues`` hold
            one issue with the ``code`` of the shared error catalogue, the
            rendered ``message`` and the JSON Pointer of the value as
            ``pointer``.

    Examples:
        >>> canonical_bytes({"b": [1.5, True], "a": "x"}, "hashable")
        b'{"a":"x","b":[1.5,true]}'
        >>> canonical_bytes([1e21, 0.1 + 0.2, 1e-7])
        b'[1e+21,0.30000000000000004,1e-7]'
    """
    check_profile(profile)
    out: list[str] = []
    _Writer(profile, out).value(x, [], 0)
    return "".join(out).encode("utf-8")


def canonical_hash(x: Any, profile: str = "data") -> str:
    """Hash of the canonical bytes of a value.

    The SHA-256 hash of the canonical bytes of a value, written as documents
    write hashes: 'sha256:' followed by 64 lower-case hexadecimal digits.

    Args:
        x: The value to write.
        profile: The profile: ``"data"``, ``"hashable"`` or ``"plain"``.

    Returns:
        The hash, as a str.

    Raises:
        MixedcheckError: A value that cannot be written, as for
            :func:`canonical_bytes`.

    Examples:
        >>> canonical_hash({"title": "study", "n": [1, 2.5]}, "hashable")
        'sha256:a5af24013cc40a028e709a636ce1f1ef9bf66262ca8310f2f5266c6ed3603e1b'
    """
    return hash_bytes(canonical_bytes(x, profile))


def json_pointer(path: list[str]) -> str:
    """The JSON Pointer of a path, with '~' written '~0' and '/' written '~1'."""
    return "".join("/" + token.replace("~", "~0").replace("/", "~1") for token in path)


def quote_json_string(text: str) -> str:
    """Write a string with the escapes of RFC 8785: '"' and '\\' escaped,
    U+0008, U+0009, U+000A, U+000C and U+000D as two-character escapes, other
    control characters as \\u00xx and everything else as itself."""
    return '"' + _SPECIAL.sub(_escape, text) + '"'


def _escape(match: re.Match[str]) -> str:
    point = ord(match.group())
    return _SHORT_ESCAPES.get(point) or f"\\u{point:04x}"


def utf16_key(key: str) -> bytes:
    """The UTF-16 code units of a key, which order keys as RFC 8785 requires."""
    return key.encode("utf-16-be", "surrogatepass")


def key_profile_code(key: str, profile: str) -> str | None:
    """The code with which a profile refuses a key: E1108 for a character
    outside the BMP in either profile, then E1208 and E1203 in the hashable
    profile."""
    if profile == "plain" or key.isascii():
        return None
    if has_non_bmp(key):
        return "E1108"
    if profile == "hashable":
        return hashable_string_code(key)
    return None


def hashable_string_code(text: str) -> str | None:
    """The code with which the hashable profile refuses a string: E1208 for a
    code point that Unicode 14.0 does not assign and E1203 for a string not in
    NFC."""
    if text.isascii():
        return None
    if not is_normalisable(text):
        return "E1208"
    if not unicodedata.is_normalized("NFC", text):
        return "E1203"
    return None


def _numpy_scalar(value: Any) -> Any:
    """A numpy integer, floating or bool scalar converted to int, float or
    bool, or the value itself. numpy is not imported when the caller has not
    imported it."""
    numpy = sys.modules.get("numpy")
    if numpy is None:
        return value
    if isinstance(value, numpy.bool_):
        return bool(value)
    if isinstance(value, numpy.integer):
        return int(value)
    if isinstance(value, numpy.floating):
        return float(value)
    return value


class _Writer:
    """One walk of a value in the order of its canonical serialisation."""

    def __init__(self, profile: str, out: list[str]) -> None:
        self.profile = profile
        self.hashable = profile == "hashable"
        self.out = out

    def fail(self, code: str, path: list[str], args: dict[str, Any] | None = None) -> NoReturn:
        raise_issue(code, args, pointer=json_pointer(path))

    def value(self, x: Any, path: list[str], depth: int) -> None:
        out = self.out
        if x is None:
            if self.hashable:
                self.fail("E1101", path)
            out.append("null")
            return
        if isinstance(x, str):
            self.string(x, path)
            out.append(quote_json_string(x))
            return
        if isinstance(x, dict):
            self.object(x, path, depth)
            return
        if isinstance(x, list):
            self.array(x, path, depth)
            return
        x = _numpy_scalar(x)
        if isinstance(x, bool):
            out.append("true" if x else "false")
        elif isinstance(x, int):
            if abs(x) > MAX_INTEGER:
                self.fail("E1102", path, {"number": str(int(x))})
            out.append(str(int(x)))
        elif isinstance(x, float):
            out.append(self.number(x, path))
        else:
            self.fail("E1301", path, {"type": type(x).__name__})

    def string(self, text: str, path: list[str]) -> None:
        if text.isascii():
            if "\x00" in text:
                self.fail("E1202", path)
            return
        if has_surrogate(text):
            self.fail("E1206", path)
        if "\x00" in text:
            self.fail("E1202", path)
        if self.hashable:
            code = hashable_string_code(text)
            if code is not None:
                self.fail(code, path)

    def number(self, x: float, path: list[str]) -> str:
        if not math.isfinite(x):
            if self.hashable:
                self.fail("E1107", path)
            if math.isnan(x):
                return '"NaN"'
            return '"Infinity"' if x > 0 else '"-Infinity"'
        if x == 0:
            return "0"
        a = abs(x)
        if a.is_integer() and a < 2**53:
            text = str(int(a))
        else:
            s, n = shortest_parts(a)
            text = ecmascript_layout(s, n)
            if self.hashable:
                code = None
                if a.is_integer():
                    code = "E1102"
                elif len(s) > 15:
                    code = "E1103"
                elif n - 1 < -307:
                    code = "E1104"
                if code is not None:
                    self.fail(code, path, {"number": text if x > 0 else "-" + text})
        return text if x > 0 else "-" + text

    def object(self, x: dict[str, Any], path: list[str], depth: int) -> None:
        if depth == MAX_DEPTH:
            self.fail("E1030", path, {"limit": MAX_DEPTH})
        # A key that is not a str, or that holds a surrogate code point,
        # cannot appear in a pointer, so its problem is reported at the
        # pointer of the object.
        for key in x:
            if not isinstance(key, str):
                self.fail("E1301", path, {"type": type(key).__name__})
            if has_surrogate(key):
                self.fail("E1206", path)
        keys = list(x)
        if all(key.isascii() for key in keys):
            keys.sort()
        else:
            keys.sort(key=utf16_key)
        out = self.out
        out.append("{")
        for index, key in enumerate(keys):
            if index:
                out.append(",")
            member = path + [key]
            if "\x00" in key:
                self.fail("E1202", member)
            if key == "":
                self.fail("E1109", member)
            code = key_profile_code(key, self.profile)
            if code is not None:
                self.fail(code, member)
            out.append(quote_json_string(key))
            out.append(":")
            self.value(x[key], member, depth + 1)
        out.append("}")

    def array(self, x: list[Any], path: list[str], depth: int) -> None:
        if depth == MAX_DEPTH:
            self.fail("E1030", path, {"limit": MAX_DEPTH})
        out = self.out
        out.append("[")
        for index, item in enumerate(x):
            if index:
                out.append(",")
            self.value(item, path + [str(index)], depth + 1)
        out.append("]")
