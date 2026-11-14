"""The strict JSON reader (docs/spec/conventions.md, Strict reader).

It works in four stages, input, UTF-8, syntax and values, and reports the
first issue that they find. One scan from left to right checks the grammar of
RFC 8259, builds the value and records the first token that breaks a rule of
the mode or profile. A syntax error anywhere takes precedence over that token,
so the token is reported only when the scan reaches the end of the input.
"""

from __future__ import annotations

import math
import os
import re
import unicodedata
from typing import Any, NoReturn

from mixedcheck._errors import MixedcheckError, new_issue, raise_issue
from mixedcheck._numbers import MAX_INTEGER, hashable_token_code
from mixedcheck._unicode import has_non_bmp, is_normalisable, utf8_invalid_offset

PROFILES = ("data", "hashable", "plain")
MAX_DEPTH = 64

_BOM = b"\xef\xbb\xbf"
_WHITE_SPACE = re.compile(r"[ \t\n\r]*")
_WHITE = " \t\n\r"
# The characters of a string that need no attention: anything but '"', '\'
# and the control characters.
_STRING_CHUNK = re.compile(r'[^"\\\x00-\x1f]*')
_NUMBER_RUN = re.compile(r"[0-9+\-.eE]+")
_NUMBER = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")
_INTEGER = re.compile(r"-?(0|[1-9][0-9]*)")
# The part of a number token before its exponent, and a digit that makes it
# non-zero.
_MANTISSA = re.compile(r"[^eE]*")
_NON_ZERO_DIGIT = re.compile(r"[1-9]")
_HEX = re.compile(r"[0-9A-Fa-f]{4}")


def _matched(pattern: re.Pattern[str], text: str, start: int) -> re.Match[str]:
    """The match at start of a pattern that always matches there, such as a
    run that may be empty or one whose first character has been checked."""
    match = pattern.match(text, start)
    assert match is not None
    return match


_ESCAPES = {
    '"': '"',
    "\\": "\\",
    "/": "/",
    "b": "\b",
    "f": "\f",
    "n": "\n",
    "r": "\r",
    "t": "\t",
}
_LITERALS = {"t": "true", "f": "false", "n": "null"}
_LITERAL_VALUES = {"true": True, "false": False, "null": None}
_NONFINITE = ("NaN", "Infinity", "-Infinity")

# Grammar states.
_VALUE = 1
_VALUE_OR_CLOSE = 2
_KEY_OR_CLOSE = 3
_KEY = 4
_COLON = 5
_AFTER_VALUE = 6
_END = 7


def read_json_strict(source: str | os.PathLike[str] | bytes, profile: str = "data") -> Any:
    """Read JSON text with the strict reader.

    Reads a JSON document under one of the two profiles of mixedcheck, or in
    the plain mode without a profile, and reports the first problem it finds
    as an error with a stable code. The reader refuses a byte-order mark,
    invalid UTF-8, duplicate keys, empty keys, unpaired surrogate escapes,
    U+0000, NaN and the infinities, numbers that a double cannot hold and
    containers nested more than 64 levels deep. The hashable profile also
    refuses null, keys outside the Basic Multilingual Plane, integers beyond
    9007199254740991 in magnitude, non-integers with more than 15 significant
    digits or below 1e-307 in magnitude, and strings that are not in Unicode
    normalisation form C or hold a code point that Unicode 14.0 does not
    assign. The data profile also refuses keys outside the Basic Multilingual
    Plane.

    Numbers are converted to the nearest double with correct rounding, as
    float() converts them.

    Args:
        source: A file path, as a str or a path-like object, or the bytes of
            the input, as a bytes object.
        profile: The profile: ``"data"``, ``"hashable"`` or ``"plain"``.

    Returns:
        The value read: objects as dicts, with members in the order of the
        input, arrays as lists, strings as str, booleans as bool and null as
        None. A number without a fraction or an exponent whose value lies
        within +-9007199254740991 is an int, and every other number a float.

    Raises:
        MixedcheckError: A problem, whose ``issues`` hold one issue: a dict
            with the ``code`` of the shared error catalogue, the rendered
            ``message`` and the byte ``offset`` at which the problem lies,
            counted from 0, when the code has a location.

    Examples:
        >>> read_json_strict(b'{"b": [1.50, true], "a": "x"}', "hashable")
        {'b': [1.5, True], 'a': 'x'}
        >>> try:
        ...     read_json_strict(b'{"a": 1, "a": 2}')
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["code"])
        E1029
    """
    check_profile(profile)
    return parse_json_bytes(read_input_bytes(source), profile)


def check_profile(profile: Any) -> None:
    """Refuse a profile other than 'data', 'hashable' and 'plain'."""
    if profile not in PROFILES:
        raise ValueError("'profile' must be 'data', 'hashable' or 'plain'.")


def read_input_bytes(source: Any) -> bytes:
    """Stage 1 for a file: the bytes of the file, or E1001 and E1002."""
    if isinstance(source, bytes | bytearray | memoryview):
        return bytes(source)
    if isinstance(source, os.PathLike):
        source = os.fspath(source)
    if not isinstance(source, str):
        raise TypeError("'source' must be a file path or a bytes object.")
    if not os.path.exists(source):
        raise_issue("E1001")
    if os.path.isdir(source) or not os.access(source, os.R_OK):
        raise_issue("E1002")
    try:
        with open(source, "rb") as handle:
            return handle.read()
    except OSError:
        raise_issue("E1002")


def parse_json_bytes(data: bytes, profile: str) -> Any:
    """Stages 1 to 4 for the bytes of an input."""
    if data.startswith(_BOM):
        raise_issue("E1003")
    invalid = utf8_invalid_offset(data)
    if invalid is not None:
        raise_issue("E1201", offset=invalid)
    text = data.decode("utf-8")
    return _Parser(text, len(data), profile).parse()


class _Parser:
    """One scan of a decoded input against the grammar and the value rules."""

    def __init__(self, text: str, size: int, profile: str) -> None:
        self.text = text
        self.n = len(text)
        self.size = size
        self.ascii = len(text) == size
        self.profile = profile
        self.hashable = profile == "hashable"
        # The first value problem: the index of its token, its code and its
        # arguments.
        self.problem: tuple[int, str, dict[str, Any]] | None = None

    # Locations ----------------------------------------------------------------

    def offset(self, index: int) -> int:
        """The byte offset of a character index, or the size of the input at
        its end."""
        if index >= self.n:
            return self.size
        if self.ascii:
            return index
        return len(self.text[:index].encode("utf-8"))

    def fail(self, code: str, index: int, args: dict[str, Any] | None = None) -> NoReturn:
        raise MixedcheckError([new_issue(code, args, offset=self.offset(index))])

    def end_of_input(self) -> NoReturn:
        raise MixedcheckError([new_issue("E1021", offset=self.size)])

    def unexpected(self, index: int) -> NoReturn:
        self.fail("E1022", index, {"character": self.text[index]})

    def note(self, index: int, code: str, args: dict[str, Any] | None = None) -> None:
        if self.problem is None:
            self.problem = (index, code, args or {})

    # The scan -------------------------------------------------------------------

    def parse(self) -> Any:
        text = self.text
        n = self.n
        # Each open container: the container, whether it is an object, the
        # keys met so far and the key of the member whose value comes next.
        stack: list[list[Any]] = []
        state = _VALUE
        root: Any = None
        i = 0
        while True:
            if i < n and text[i] in _WHITE:
                i = _matched(_WHITE_SPACE, text, i).end()
            if i >= n:
                if state == _END:
                    break
                self.end_of_input()
            c = text[i]
            if state <= _VALUE_OR_CLOSE:
                if c == "]" and state == _VALUE_OR_CLOSE:
                    stack.pop()
                    state = _AFTER_VALUE if stack else _END
                    i += 1
                    continue
                if c == "{" or c == "[":
                    if len(stack) == MAX_DEPTH:
                        self.fail("E1030", i, {"limit": MAX_DEPTH})
                    container: Any = {} if c == "{" else []
                    if stack:
                        self._attach(stack[-1], container)
                    else:
                        root = container
                    if c == "{":
                        stack.append([container, True, set(), None])
                        state = _KEY_OR_CLOSE
                    else:
                        stack.append([container, False, None, None])
                        state = _VALUE_OR_CLOSE
                    i += 1
                    continue
                value, i = self._scalar(i)
                if stack:
                    self._attach(stack[-1], value)
                    state = _AFTER_VALUE
                else:
                    root = value
                    state = _END
            elif state <= _KEY:
                if c == "}" and state == _KEY_OR_CLOSE:
                    stack.pop()
                    state = _AFTER_VALUE if stack else _END
                    i += 1
                    continue
                if c != '"':
                    self.unexpected(i)
                frame = stack[-1]
                key, i = self._string(i, frame)
                frame[3] = key
                state = _COLON
            elif state == _COLON:
                if c != ":":
                    self.unexpected(i)
                i += 1
                state = _VALUE
            elif state == _AFTER_VALUE:
                frame = stack[-1]
                if c == ",":
                    state = _KEY if frame[1] else _VALUE
                elif (c == "}" and frame[1]) or (c == "]" and not frame[1]):
                    stack.pop()
                    state = _AFTER_VALUE if stack else _END
                else:
                    self.unexpected(i)
                i += 1
            else:
                self.fail("E1023", i)
        if self.problem is not None:
            index, code, args = self.problem
            raise MixedcheckError([new_issue(code, args, offset=self.offset(index))])
        return root

    @staticmethod
    def _attach(frame: list[Any], value: Any) -> None:
        if frame[1]:
            frame[0][frame[3]] = value
        else:
            frame[0].append(value)

    def _scalar(self, i: int) -> tuple[Any, int]:
        """Read the scalar at a value position, by the rules of conventions.md
        (Syntax), and return its value and the index after it."""
        text = self.text
        c = text[i]
        if c == '"':
            return self._string(i, None)
        for literal in _NONFINITE:
            if text.startswith(literal, i):
                self.fail("E1027", i, {"literal": literal})
        if c in "-+.0123456789":
            run = _matched(_NUMBER_RUN, text, i)
            token = run.group()
            if _NUMBER.fullmatch(token) is None:
                self.fail("E1028", i, {"token": token})
            return self._number(token, i), run.end()
        word = _LITERALS.get(c)
        if word is not None:
            for j, expected in enumerate(word):
                if i + j >= self.n:
                    self.end_of_input()
                if text[i + j] != expected:
                    self.unexpected(i + j)
            if word == "null" and self.hashable:
                self.note(i, "E1101")
            return _LITERAL_VALUES[word], i + len(word)
        self.unexpected(i)

    def _number(self, token: str, i: int) -> int | float:
        """Check a number token by the rules of the profile and convert it."""
        if self.hashable:
            code = hashable_token_code(token)
        else:
            value = float(token)
            code = None
            if math.isinf(value):
                code = "E1105"
            elif value == 0 and _NON_ZERO_DIGIT.search(_matched(_MANTISSA, token, 0).group()):
                code = "E1106"
        if code is not None:
            self.note(i, code, {"number": token})
            return 0
        if len(token) <= 17 and _INTEGER.fullmatch(token) and abs(int(token)) <= MAX_INTEGER:
            return int(token)
        return float(token)

    def _string(self, i: int, frame: list[Any] | None) -> tuple[str, int]:
        """Read the string token that starts at i, a key when frame is its
        object, and return its text and the index after it."""
        text = self.text
        n = self.n
        j = _matched(_STRING_CHUNK, text, i + 1).end()
        if j < n and text[j] == '"':
            value = text[i + 1 : j]
            self._check_string(value, i, frame, unpaired=False)
            return value, j + 1
        pieces = [text[i + 1 : j]]
        unpaired = False
        while True:
            if j >= n:
                self.end_of_input()
            c = text[j]
            if c == '"':
                break
            if c < " ":
                self.fail("E1024", j, {"codepoint": ord(c)})
            # A backslash.
            if j + 1 >= n:
                self.end_of_input()
            letter = text[j + 1]
            if letter in _ESCAPES:
                pieces.append(_ESCAPES[letter])
                j += 2
            elif letter == "u":
                unit = self._hex(j)
                size = 6
                if 0xD800 <= unit <= 0xDBFF:
                    # A high surrogate escape is paired only with a low
                    # surrogate escape that follows at once.
                    low = self._low_surrogate(j + 6)
                    if low is None:
                        unpaired = True
                    else:
                        pieces.append(chr(0x10000 + (unit - 0xD800) * 1024 + (low - 0xDC00)))
                        size = 12
                elif 0xDC00 <= unit <= 0xDFFF:
                    unpaired = True
                else:
                    pieces.append(chr(unit))
                j += size
            else:
                self.fail("E1025", j)
            start = j
            j = _matched(_STRING_CHUNK, text, j).end()
            pieces.append(text[start:j])
        value = "".join(pieces)
        self._check_string(value, i, frame, unpaired=unpaired)
        return value, j + 1

    def _hex(self, j: int) -> int:
        """The value of the four hexadecimal digits of the escape '\\u' at j."""
        text = self.text
        for k in range(2, 6):
            if j + k >= self.n:
                self.end_of_input()
            if text[j + k] not in "0123456789ABCDEFabcdef":
                self.fail("E1025", j)
        return int(text[j + 2 : j + 6], 16)

    def _low_surrogate(self, k: int) -> int | None:
        """The value of a low surrogate escape that starts at k, or None."""
        text = self.text
        if not text.startswith("\\u", k) or _HEX.match(text, k + 2) is None:
            return None
        value = int(text[k + 2 : k + 6], 16)
        return value if 0xDC00 <= value <= 0xDFFF else None

    def _check_string(self, value: str, i: int, frame: list[Any] | None, unpaired: bool) -> None:
        """Stage 4 for a string or key token: the checks of conventions.md
        (Values), in their order."""
        if self.problem is not None:
            return
        code = None
        if unpaired:
            code = "E1026"
        elif "\x00" in value:
            code = "E1202"
        elif frame is not None and value == "":
            code = "E1109"
        elif frame is not None and self.profile != "plain" and has_non_bmp(value):
            code = "E1108"
        elif self.hashable and not value.isascii():
            if not is_normalisable(value):
                code = "E1208"
            elif not unicodedata.is_normalized("NFC", value):
                code = "E1203"
        if code is not None:
            self.note(i, code)
        elif frame is not None:
            if value in frame[2]:
                self.note(i, "E1029", {"key": value})
            else:
                frame[2].add(value)
