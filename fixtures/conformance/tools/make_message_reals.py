#!/usr/bin/env python3
"""Write the vectors of the rendering of real statistics in messages.

docs/spec/registry.md (Messages) renders a real statistic with 'digits' decimal
places: a finite double below 1e15 in absolute value in fixed notation, as
Python's f"{x:.{digits}f}" writes it, with a minus sign only before a rounded
value that is not zero, unless the double is above 0 and that rendering has no
digit other than 0, when it renders as 'under' and the smallest positive value
with 'digits' places, such as 'under 0.1', a double whose absolute value is at
least 1e15 in scientific notation, as f"{x:.{digits}e}" writes it, and NaN and
the infinities as 'NaN', 'Infinity' and '-Infinity'. The double itself, before
any rounding, decides the notation. This script writes the renderings of a set
of doubles with 0 to 6 digits to
fixtures/conformance/numbers/message_reals.txt.xz, whose format
fixtures/conformance/numbers/README.md describes.

Every finite rendering comes from format() with the option 'z', which drops the
sign of a value that rounds to zero, with 'under' decided from the digits it
writes, and the script stops unless it equals the exact binary value of the
double rounded half to even with exact fractions, with 'under' decided from the
rounded integer. The doubles are built from their bits, from integers and from
decimal strings, which CPython converts with correct rounding, never with the
mathematical functions of the C library, and the random ones come from the
SplitMix64 generator below with a fixed seed, so that the content does not
depend on the platform or on the version of Python's random module.

Run it from the repository root with Python 3.11 or later, using the standard
library only:

    python3 fixtures/conformance/tools/make_message_reals.py
    python3 fixtures/conformance/tools/make_message_reals.py --check

The first writes the file when its content differs and the second compares
the content with the file and writes nothing. Both compare the decompressed
text, since the bytes that xz writes for the same text can differ between
versions of liblzma.
"""

from __future__ import annotations

import argparse
import lzma
import math
import struct
import sys
from collections.abc import Callable, Iterator
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "fixtures" / "conformance" / "numbers" / "message_reals.txt.xz"
DIGITS = range(7)
SEED = 20261109
MASK = (1 << 64) - 1
# The double 10^15, from which a real takes scientific notation.
BOUND = 1e15


class SplitMix64:
    """Steele, Lea and Flood's SplitMix64, which fixes every value drawn."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def below(self, n: int) -> int:
        """An integer from 0 to n - 1, from as many words of 64 bits as n
        needs, by rejection."""
        words = (n.bit_length() + 63) // 64
        span = 1 << (64 * words)
        limit = span - span % n
        while True:
            value = 0
            for _ in range(words):
                value = (value << 64) | self.next()
            if value < limit:
                return value % n

    def between(self, low: int, high: int) -> int:
        return low + self.below(high - low + 1)


def from_bits(bits: int) -> float:
    return struct.unpack(">d", bits.to_bytes(8, "big"))[0]


def to_bits(x: float) -> int:
    return int.from_bytes(struct.pack(">d", x), "big")


def around(x: float, count: int) -> list[float]:
    """A positive double with the `count` doubles on each side of it."""
    bits = to_bits(x)
    return [from_bits(bits + step) for step in range(-count, count + 1)]


def under(digits: int) -> str:
    """'under' and the smallest positive value with `digits` decimal places."""
    return "under " + ("1" if digits == 0 else "0." + "0" * (digits - 1) + "1")


def render(x: float, digits: int) -> str:
    """The rendering of registry.md, from format()."""
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Infinity" if x > 0 else "-Infinity"
    if abs(x) < BOUND:
        text = format(x, f"z.{digits}f")
        # A double above 0 whose rendering has no digit other than 0.
        return under(digits) if x > 0 and not text.strip("0.") else text
    return format(x, f".{digits}e")


def exact_render(x: float, digits: int) -> str:
    """The same rendering from the exact value of the double, with fractions."""
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Infinity" if x > 0 else "-Infinity"
    value = abs(Fraction(x))
    sign = "-" if x < 0 else ""
    if abs(x) < BOUND:
        # round() of a fraction rounds half to even.
        scaled = round(value * 10**digits)
        if x > 0 and scaled == 0:
            return under(digits)
        text = str(scaled).rjust(digits + 1, "0")
        if digits:
            text = f"{text[:-digits]}.{text[-digits:]}"
        return (sign if scaled else "") + text
    exponent = len(str(math.floor(value))) - 1
    mantissa = round(value / Fraction(10) ** (exponent - digits))
    if mantissa == 10 ** (digits + 1):
        mantissa //= 10
        exponent += 1
    text = str(mantissa)
    if digits:
        text = f"{text[0]}.{text[1:]}"
    return f"{sign}{text}e{'+' if exponent >= 0 else '-'}{exponent:02d}"


def both_signs(values: list[float]) -> list[float]:
    return [y for x in values for y in (x, -x)]


def special(_: SplitMix64) -> list[float]:
    return [0.0, -0.0, from_bits(0x7FF8000000000000), math.inf, -math.inf]


def examples(_: SplitMix64) -> list[float]:
    # The examples of registry.md, Messages, and of the R package's tests,
    # among them 1/21 and the doubles on either side of 0.05.
    return both_signs(
        [
            2.5e20,
            3.5e20,
            9.5e15,
            2.0**60,
            1e100,
            0.04,
            999999999999999.875,
            1 / 21,
            0.05,
            math.nextafter(0.05, 0),
            0.5,
            0.4,
        ]
    )


def random_bits(rng: SplitMix64) -> list[float]:
    values: list[float] = []
    while len(values) < 1000:
        x = from_bits(rng.next())
        if math.isfinite(x):
            values.append(x)
    return values


def log_uniform(rng: SplitMix64) -> list[float]:
    # A binary exponent drawn uniformly and 52 random bits of the significand,
    # kept from 1e-7 to 1e22.
    values: list[float] = []
    while len(values) < 1000:
        exponent = rng.between(-24, 73)
        x = from_bits(((exponent + 1023) << 52) | rng.below(1 << 52))
        if 1e-7 <= x <= 1e22:
            values.append(x)
    return both_signs(values)


def near_bound(_: SplitMix64) -> list[float]:
    return both_signs(around(BOUND, 200))


def powers_of_ten(_: SplitMix64) -> list[float]:
    values = [x for k in range(-323, 309) for x in around(float(f"1e{k}"), 1)]
    return both_signs(values)


def ties_scientific(rng: SplitMix64) -> list[float]:
    # Decimals (n + 1/2) 10^(e - d) from 1e15 on, with n of d + 1 digits, which
    # lie halfway between two mantissas with d decimal places. They equal
    # (2n + 1) 5^(e - d) 2^(e - d - 1), which a double holds exactly while
    # (2n + 1) 5^(e - d) is below 2^53.
    # Each number of digits contributes 150 of them, or all when there are
    # fewer.
    values: list[float] = []
    for d in DIGITS:
        ranges = []
        e = 15
        while (2 * 10**d + 1) * 5 ** (e - d) < 2**53:
            ranges.append((e, min(10 ** (d + 1) - 1, ((2**53 - 1) // 5 ** (e - d) - 1) // 2)))
            e += 1
        available = sum(n_max - 10**d + 1 for _, n_max in ranges)
        chosen: set[int] = set()
        if available <= 150:
            chosen = {
                (2 * n + 1) * 5 * 10 ** (e - d - 1)
                for e, n_max in ranges
                for n in range(10**d, n_max + 1)
            }
        while len(chosen) < min(150, available):
            e, n_max = ranges[rng.below(len(ranges))]
            n = rng.between(10**d, n_max)
            chosen.add((2 * n + 1) * 5 * 10 ** (e - d - 1))
        for value in sorted(chosen):
            x = float(value)
            assert x == value and abs(x) >= BOUND
            values.append(x)
    return both_signs(values)


def ties_fixed(rng: SplitMix64) -> list[float]:
    # Odd multiples of 2^-(d + 1) below 1e15, which lie halfway between two
    # roundings to d decimal places.
    values: list[float] = []
    for d in DIGITS:
        count = 0
        while count < 100:
            length = rng.between(1, 53)
            odd = (1 << (length - 1)) | rng.below(1 << (length - 1)) | 1
            x = odd / 2 ** (d + 1)
            if x < BOUND:
                assert Fraction(x) * 10**d * 2 % 2 == 1
                values.append(x)
                count += 1
    return both_signs(values)


def near_ties(rng: SplitMix64) -> list[float]:
    # The doubles nearest to decimals whose last digit is a 5 just beyond d
    # decimal places of fixed notation or of the mantissa, which lie above or
    # below the halfway point unless a double holds them exactly.
    values: list[float] = []
    for d in DIGITS:
        for _ in range(100):
            m = rng.below(10 ** rng.between(1, d + 15))
            values.append(float(f"{10 * m + 5}e-{d + 1}"))
        for _ in range(100):
            n = rng.between(10**d, 10 ** (d + 1) - 1)
            x = float(f"{10 * n + 5}e{rng.between(15, 308) - d - 1}")
            if math.isfinite(x):
                values.append(x)
    return both_signs(values)


def carries_fixed(_: SplitMix64) -> list[float]:
    # The doubles nearest to 10^k - 5 10^-(d + 1), at which the rounding to d
    # decimal places carries into a new digit, with their neighbours.
    values = [
        x
        for d in DIGITS
        for k in range(-d, 16)
        for x in around(float(Fraction(10 ** (k + d + 1) - 5, 10 ** (d + 1))), 1)
    ]
    return both_signs(values)


def carries_scientific(rng: SplitMix64) -> list[float]:
    # The doubles nearest to (10 - 5 10^-(d + 1)) 10^e for every exponent from
    # 15 to 307, at which the rounding of the mantissa to d decimal places
    # carries into the exponent, with their neighbours, each with a random sign.
    values = [
        x
        for d in DIGITS
        for e in range(15, 308)
        for x in around(float((10 ** (d + 2) - 5) * 10 ** (e - d - 1)), 1)
    ]
    return [x if rng.below(2) else -x for x in values]


def extremes(_: SplitMix64) -> list[float]:
    largest = [from_bits(0x7FEFFFFFFFFFFFFF - step) for step in range(20)]
    subnormal = [from_bits(step) for step in range(1, 21)]
    return both_signs(largest + subnormal + around(2.0**53, 20))


CLASSES: list[Callable[[SplitMix64], list[float]]] = [
    special,
    examples,
    random_bits,
    log_uniform,
    near_bound,
    powers_of_ten,
    ties_scientific,
    ties_fixed,
    near_ties,
    carries_fixed,
    carries_scientific,
    extremes,
]


def doubles() -> Iterator[float]:
    """Every double of the classes once, in the order of the classes."""
    rng = SplitMix64(SEED)
    seen: set[int] = set()
    for make in CLASSES:
        for x in make(rng):
            bits = to_bits(x)
            if bits not in seen:
                seen.add(bits)
                yield x


def content() -> str:
    lines = []
    for x in doubles():
        texts = [render(x, d) for d in DIGITS]
        for d, text in zip(DIGITS, texts, strict=True):
            if text != exact_render(x, d):
                raise SystemExit(f"format() and exact rounding differ for {x!r} with {d} digits")
        lines.append("\t".join([f"{to_bits(x):016x}", *texts]))
    return "\n".join(lines) + "\n"


def read(path: Path) -> str | None:
    try:
        return lzma.decompress(path.read_bytes()).decode("ascii")
    except (FileNotFoundError, lzma.LZMAError, UnicodeDecodeError):
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="compare, write nothing")
    options = parser.parse_args(argv)
    text = content()
    count = text.count("\n")
    if read(TARGET) == text:
        print(f"{TARGET.relative_to(ROOT).as_posix()} is up to date with {count} doubles")
        return 0
    if options.check:
        print(f"differs: {TARGET.relative_to(ROOT).as_posix()}", file=sys.stderr)
        return 1
    data = lzma.compress(text.encode("ascii"), preset=9 | lzma.PRESET_EXTREME)
    TARGET.write_bytes(data)
    print(f"wrote {TARGET.relative_to(ROOT).as_posix()} with {count} doubles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
