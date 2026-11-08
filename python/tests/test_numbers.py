"""Targeted tests of number formatting, decimal constants and the number rules
of the hashable profile, beyond the cases of the number corpus.

The formatting is checked against the definition of Number::toString in
ECMA-262 with exact decimal arithmetic: each string converts back to its
double, no decimal with fewer digits does, and no other decimal with as many
digits that converts back lies closer to the double.
"""

from __future__ import annotations

import math
import random
import struct
from decimal import Decimal

import pytest

from mixedcheck._numbers import decimal_string, format_number, hashable_token_code


def _check_shortest_and_closest(x: float) -> None:
    text = format_number(x)
    assert float(text) == x, text
    exact = Decimal(x)
    value = Decimal(text)
    _, digits, last = value.normalize().as_tuple()
    unit = Decimal(1).scaleb(last)
    # No decimal with fewer digits converts back: if one did, one of the two
    # multiples of ten units nearest to the double, below and above it, would.
    if len(digits) > 1:
        coarse = unit * 10
        below = (exact / coarse).to_integral_value(rounding="ROUND_FLOOR") * coarse
        for candidate in (below, below + coarse):
            assert float(candidate) != x, (text, candidate)
    # Of the neighbours with as many digits, none that converts back is closer.
    for candidate in (value - unit, value + unit):
        if float(candidate) == x:
            assert abs(candidate - exact) >= abs(value - exact), (text, candidate)


def _doubles() -> list[float]:
    values = [2.0**e for e in range(-1074, 1024)]
    for e in range(-323, 309):
        power = float(f"1e{e}")
        values += [power, math.nextafter(power, 0), math.nextafter(power, math.inf)]
    generator = random.Random(20261108)
    for _ in range(1500):
        bits = generator.getrandbits(64) & 0x7FFFFFFFFFFFFFFF
        value = struct.unpack(">d", bits.to_bytes(8, "big"))[0]
        if math.isfinite(value) and value != 0:
            values.append(value)
    values += [generator.random() for _ in range(500)]
    values += [5e-324 * m for m in range(1, 301)]
    return [value for value in values if math.isfinite(value) and value > 0]


def test_doubles_are_written_in_the_shortest_and_closest_form():
    for x in _doubles():
        _check_shortest_and_closest(x)
        assert format_number(-x) == "-" + format_number(x)


def test_values_that_defeat_simpler_methods_are_written_in_shortest_form():
    # Formatting with increasing precision returns 7.1202363472230444e-307
    # for 2^-1017, although 16 digits convert back (conventions.md, Numbers).
    assert format_number(2.0**-1017) == "7.120236347223045e-307"
    assert format_number(5e-324) == "5e-324"
    assert format_number(1.7976931348623157e308) == "1.7976931348623157e+308"
    assert format_number(2.0**53) == "9007199254740992"
    assert format_number(2.0**68) == "295147905179352830000"
    assert format_number(1e21) == "1e+21"
    assert format_number(1e23) == "1e+23"
    assert format_number(0.1 + 0.2) == "0.30000000000000004"
    assert format_number(1 / 3) == "0.3333333333333333"
    assert format_number(2 / 3) == "0.6666666666666666"
    assert format_number(1e-6) == "0.000001"
    assert format_number(1e-7) == "1e-7"
    assert format_number(123e-20) == "1.23e-18"
    assert format_number(100.0) == "100"
    assert format_number(100) == "100"
    assert format_number(-0.0) == "0"
    # A Python int beyond 2^53 is formatted as the double it converts to.
    assert format_number(2**60) == "1152921504606847000"
    with pytest.raises(ValueError):
        format_number(math.nan)


def test_decimal_constants_round_the_exact_binary_value_half_to_even():
    # Expected strings from Python's decimal module, quantising the exact
    # value of each double with ROUND_HALF_EVEN.
    assert decimal_string(9.995, 3) == "9.99"
    assert decimal_string(0.5, 1) == "0.5"
    assert decimal_string(1e300, 1) == "1" + "0" * 300
    assert decimal_string(1e-300, 2) == "0." + "0" * 299 + "1"
    assert decimal_string(5e-324, 1) == "0." + "0" * 323 + "5"
    assert decimal_string(1.7976931348623157e308, 15) == "179769313486232" + "0" * 294
    assert decimal_string(123456789, 15) == "123456789"
    assert decimal_string(0.1, 15) == "0.1"
    assert decimal_string(2.5e-5, 1) == "0.00003"
    assert decimal_string(99.5, 2) == "100"
    assert decimal_string(-1.5, 1) == "-2"
    assert decimal_string(2.0**53, 3) == "9010000000000000"
    assert decimal_string(1234.5, 4) == "1234"
    assert decimal_string(0, 3) == "0"
    assert decimal_string(-0.0, 3) == "0"
    with pytest.raises(ValueError, match="one finite number"):
        decimal_string(math.nan, 3)
    with pytest.raises(ValueError, match="one finite number"):
        decimal_string(True, 3)
    with pytest.raises(ValueError, match="integer from 1 to 15"):
        decimal_string(1.0, 16)
    with pytest.raises(ValueError, match="integer from 1 to 15"):
        decimal_string(1.0, 2.5)


def test_decimal_constants_agree_with_the_decimal_module():
    generator = random.Random(7)
    for _ in range(3000):
        x = generator.uniform(-1e6, 1e6) * 10.0 ** generator.randint(-30, 30)
        digits = generator.randint(1, 15)
        exact = Decimal(x)
        quantum = Decimal(1).scaleb(exact.adjusted() - digits + 1)
        rounded = exact.quantize(quantum, rounding="ROUND_HALF_EVEN")
        expected = format(rounded.normalize(), "f")
        assert decimal_string(x, digits) == expected, (x, digits)


def test_the_hashable_profile_classifies_tokens_by_their_exact_decimal_value():
    tokens = [
        "0",
        "-0.000e99999999999",
        "9007199254740991",
        "9007199254740992",
        "90071992547409910e-1",
        "1e15",
        "1e16",
        "0.000000000000001e30",
        "123456789012345.0",
        "1.234567890123456",
        "1e-307",
        "0.99e-307",
        "1e00000000000000000000001",
        "1e-99999999999",
        "1.0000000000000001e-99999999999",
    ]
    expected = [
        None, None, None, "E1102", None,
        None, "E1102", None, None, "E1103",
        None, "E1104", None, "E1104", "E1103",
    ]  # fmt: skip
    assert [hashable_token_code(token) for token in tokens] == expected
