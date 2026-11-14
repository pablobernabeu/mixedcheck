"""Numbers: ECMAScript's Number::toString, decimal constants and the number
rules of the hashable profile (docs/spec/conventions.md, Numbers,
Serialisation and Decimal strings and centring constants)."""

from __future__ import annotations

import math
import re

MAX_INTEGER = 9007199254740991

_TOKEN = re.compile(r"-?([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?)([0-9]+))?")


def shortest_parts(a: float) -> tuple[str, int]:
    """The digits s and exponent n, with value 0.s * 10^n, of the shortest
    decimal that converts back to a positive finite double.

    repr() gives these digits: the shortest that round-trip and, of several,
    the closest to the double, as ECMA-262 (Number::toString, step 5)
    requires. Only their layout differs from ECMAScript's.
    """
    mantissa, _, exponent_text = repr(a).partition("e")
    exponent = int(exponent_text) if exponent_text else 0
    whole, _, fraction = mantissa.partition(".")
    if whole.strip("0") == "":
        n = exponent - (len(fraction) - len(fraction.lstrip("0")))
    else:
        n = len(whole.lstrip("0")) + exponent
    return (whole + fraction).strip("0"), n


def ecmascript_layout(s: str, n: int) -> str:
    """Lay out digits s and exponent n by steps 4 to 7 of Number::toString."""
    k = len(s)
    if k <= n <= 21:
        return s + "0" * (n - k)
    if 0 < n <= 21:
        return s[:n] + "." + s[n:]
    if -6 < n <= 0:
        return "0." + "0" * (-n) + s
    tail = "." + s[1:] if k > 1 else ""
    sign = "+" if n - 1 >= 0 else "-"
    return s[0] + tail + "e" + sign + str(abs(n - 1))


def format_number(x: int | float) -> str:
    """Write a finite number as ECMAScript's Number::toString does, which
    RFC 8785 requires: the shortest decimal that converts back to the double,
    the closest of several, laid out in plain or exponential notation."""
    if isinstance(x, int) and not isinstance(x, bool) and abs(x) <= MAX_INTEGER:
        return str(x)
    value = float(x)
    if not math.isfinite(value):
        raise ValueError("Only finite numbers have a JSON form.")
    if value == 0:
        return "0"
    s, n = shortest_parts(abs(value))
    text = ecmascript_layout(s, n)
    return "-" + text if value < 0 else text


def hashable_token_code(token: str) -> str | None:
    """Classify a number token, which matches the number grammar of RFC 8259,
    by the rules of the hashable profile.

    Returns None for an accepted token, or E1102 for an integer outside the
    range, E1103 for a non-integer with more than 15 significant digits or
    E1104 for one below 1e-307 in magnitude. Exponents are exact: one of more
    than ten digits lies beyond any input below 1 GB.
    """
    match = _TOKEN.fullmatch(token)
    if match is None:
        raise ValueError(f"'{token}' is not a number token.")
    integer_part, fraction, exponent_sign, exponent_digits = match.groups()
    fraction = fraction or ""
    exponent_digits = (exponent_digits or "").lstrip("0")
    significand = (integer_part + fraction).lstrip("0")
    if significand == "":
        return None
    stripped = significand.rstrip("0")
    trailing = len(significand) - len(stripped)
    digits = len(stripped)
    if len(exponent_digits) > 10:
        exponent = 10**15
    else:
        exponent = int(exponent_digits) if exponent_digits else 0
    if exponent_sign == "-":
        exponent = -exponent
    # The value is stripped * 10^e, with p the power of ten of its leading digit.
    e = exponent - len(fraction) + trailing
    p = digits + e - 1
    if e >= 0:
        if p > 15 or (p == 15 and int(stripped) * 10**e > MAX_INTEGER):
            return "E1102"
        return None
    if digits > 15:
        return "E1103"
    if p < -307:
        return "E1104"
    return None


def decimal_string(x: int | float, digits: int) -> str:
    """Round a finite number to significant digits and write it as a decimal string.

    The exact binary value of the double is rounded half to even, and the
    result is written with no exponent, no '+', no leading zeros in the integer
    part and no trailing zeros in the fraction (conventions.md, Decimal
    strings and centring constants). CPython's format() rounds the exact value
    correctly on every platform.
    """
    if isinstance(x, bool) or not isinstance(x, int | float) or not math.isfinite(x):
        raise ValueError("'x' must be one finite number.")
    if (
        isinstance(digits, bool)
        or not isinstance(digits, int | float)
        or not float(digits).is_integer()
        or not 1 <= digits <= 15
    ):
        raise ValueError("'digits' must be an integer from 1 to 15.")
    value = float(x)
    if value == 0:
        return "0"
    mantissa, _, exponent_text = format(abs(value), f".{int(digits) - 1}e").partition("e")
    s = mantissa.replace(".", "").rstrip("0")
    n = int(exponent_text) + 1
    k = len(s)
    if n >= k:
        text = s + "0" * (n - k)
    elif n > 0:
        text = s[:n] + "." + s[n:]
    else:
        text = "0." + "0" * (-n) + s
    return "-" + text if value < 0 else text
