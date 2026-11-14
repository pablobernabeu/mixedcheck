"""Targeted tests of UTF-8 validation, NFC and the order of identifiers, beyond
the cases of the Unicode corpus."""

from __future__ import annotations

import random

from mixedcheck._unicode import (
    codepoint_assigned,
    compare_identifiers,
    comparison_form,
    has_non_bmp,
    has_surrogate,
    is_normalisable,
    nfc,
    sort_identifiers,
    utf8_invalid_offset,
)


def test_the_first_ill_formed_sequence_is_found_by_decoding_from_the_start():
    def offset(*values):
        return utf8_invalid_offset(bytes(values))

    assert offset(0x61, 0x62) is None
    assert offset() is None
    assert offset(0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80) is None
    assert offset(0x80) == 0
    assert offset(0x61, 0xC3) == 1
    assert offset(0xE2, 0x82, 0x41) == 0
    assert offset(0xF0, 0x9F, 0x98, 0x80, 0x80) == 4
    assert offset(0xED, 0x9F, 0xBF, 0xED, 0xA0, 0x80) == 3
    assert offset(0xF4, 0x8F, 0xBF, 0xBF, 0xF4, 0x90, 0x80, 0x80) == 4
    assert offset(0xC0, 0x80) == 0
    assert offset(0xEF, 0xBF, 0xBE) is None


def _well_formed(data: bytes) -> bool:
    """Table 3-7 of the Unicode Standard, written out for the test."""
    i = 0
    while i < len(data):
        lead = data[i]
        if lead < 0x80:
            i += 1
            continue
        if 0xC2 <= lead <= 0xDF:
            ranges = [(0x80, 0xBF)]
        elif lead == 0xE0:
            ranges = [(0xA0, 0xBF), (0x80, 0xBF)]
        elif 0xE1 <= lead <= 0xEC or 0xEE <= lead <= 0xEF:
            ranges = [(0x80, 0xBF), (0x80, 0xBF)]
        elif lead == 0xED:
            ranges = [(0x80, 0x9F), (0x80, 0xBF)]
        elif lead == 0xF0:
            ranges = [(0x90, 0xBF), (0x80, 0xBF), (0x80, 0xBF)]
        elif 0xF1 <= lead <= 0xF3:
            ranges = [(0x80, 0xBF)] * 3
        elif lead == 0xF4:
            ranges = [(0x80, 0x8F), (0x80, 0xBF), (0x80, 0xBF)]
        else:
            return False
        for k, (low, high) in enumerate(ranges, start=1):
            if i + k >= len(data) or not low <= data[i + k] <= high:
                return False
        i += len(ranges) + 1
    return True


def test_the_validator_agrees_with_table_3_7_on_random_bytes():
    generator = random.Random(20261108)
    candidates = [
        *range(0x01, 0x80), *range(0x80, 0xC0), *range(0xC0, 0xC4), *range(0xDF, 0xE2),
        *range(0xEC, 0xEF), *range(0xEF, 0xF2), *range(0xF3, 0xF6), 0xFE, 0xFF,
    ]  # fmt: skip
    for _ in range(5000):
        data = bytes(generator.choice(candidates) for _ in range(generator.randint(1, 6)))
        assert (utf8_invalid_offset(data) is None) == _well_formed(data), data.hex()


def test_identifiers_are_compared_and_sorted_by_the_code_points_of_their_nfc_forms():
    assert compare_identifiers("é", "\xe9") == 0
    assert comparison_form("é") == "\xe9"
    assert sort_identifiers(["\xe9", "Z", "a", "_", "\U0001f600"]) == [
        "Z",
        "_",
        "a",
        "\xe9",
        "\U0001f600",
    ]
    # U+1E4EC is assigned only from Unicode 15.0, so the string is compared as
    # it is, whatever Unicode version this Python implements.
    later = "x\U0001e4ec̖"
    assert not is_normalisable(later)
    assert comparison_form(later) == later
    assert nfc("é") == "\xe9"


def test_assigned_code_points_follow_unicode_14():
    assert codepoint_assigned(0x41)
    assert not codepoint_assigned(0x378)
    assert codepoint_assigned(0x1E2AE)
    assert not codepoint_assigned(0x1E4EC)
    assert codepoint_assigned(0xFFFD)
    assert not codepoint_assigned(0x10FFFF)


def test_surrogates_and_characters_outside_the_bmp_are_found():
    assert has_surrogate("a\ud800")
    assert not has_surrogate("a\U0001f600")
    assert has_non_bmp("a\U0001f600")
    assert not has_non_bmp("a￿")
