"""UTF-8 validation, NFC and the comparison and order of identifiers and labels
(docs/spec/conventions.md, Text and Unicode)."""

from __future__ import annotations

import bisect
import re
import unicodedata
from collections.abc import Iterable
from importlib.resources import files

_SURROGATE = re.compile("[\ud800-\udfff]")

# The ranges of code points that Unicode 14.0 assigns, as first and last code
# points, read once per session.
_ranges: tuple[list[int], list[int]] | None = None


def utf8_invalid_offset(data: bytes) -> int | None:
    """The 0-based offset of the first ill-formed sequence, or None.

    The bytes are decoded from the start by Table 3-7 of the Unicode Standard,
    so a truncated sequence is reported at its lead byte and a stray
    continuation byte at its own offset, as UnicodeDecodeError.start gives it.
    """
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as err:
        return err.start
    return None


def _assigned_ranges() -> tuple[list[int], list[int]]:
    """The ranges of spec/unicode/assigned-14.0.json, as first and last code points."""
    global _ranges
    ranges = _ranges
    if ranges is None:
        from mixedcheck._json_read import parse_json_bytes

        path = files("mixedcheck") / "_spec" / "unicode" / "assigned-14.0.json"
        document = parse_json_bytes(path.read_bytes(), "data")
        # Built whole and assigned in one statement, so that threads reading
        # the file at once each see complete ranges.
        pairs = document["ranges"]
        ranges = ([first for first, _ in pairs], [last for _, last in pairs])
        _ranges = ranges
    return ranges


def codepoint_assigned(point: int) -> bool:
    """Whether Unicode 14.0 assigns a code point."""
    firsts, lasts = _assigned_ranges()
    index = bisect.bisect_right(firsts, point) - 1
    return index >= 0 and point <= lasts[index]


def is_normalisable(text: str) -> bool:
    """Whether a string holds only code points that Unicode 14.0 assigns, so
    that both packages normalise it in the same way."""
    if text.isascii():
        return True
    return all(codepoint_assigned(ord(char)) for char in set(text))


def has_surrogate(text: str) -> bool:
    """Whether a str holds a surrogate code point, U+D800 to U+DFFF."""
    return not text.isascii() and _SURROGATE.search(text) is not None


def has_non_bmp(text: str) -> bool:
    """Whether a str holds a character outside the Basic Multilingual Plane."""
    return not text.isascii() and any(ord(char) > 0xFFFF for char in text)


def nfc(text: str) -> str:
    """The NFC form of a str."""
    if text.isascii():
        return text
    return unicodedata.normalize("NFC", text)


def comparison_form(text: str) -> str:
    """The form in which identifiers and labels are compared: the NFC form of
    a normalisable string and the string itself otherwise."""
    if text.isascii() or not is_normalisable(text):
        return text
    return unicodedata.normalize("NFC", text)


def compare_identifiers(first: str, second: str) -> int:
    """Compare two identifiers or labels by the code points of their
    comparison forms, with a prefix first. Returns -1, 0 or 1."""
    a = comparison_form(first)
    b = comparison_form(second)
    return (a > b) - (a < b)


def sort_identifiers(strings: Iterable[str]) -> list[str]:
    """Sort identifiers or labels by the code points of their comparison forms.

    Python compares str values code point by code point, with a prefix first,
    in every locale.
    """
    return sorted(strings, key=comparison_form)
