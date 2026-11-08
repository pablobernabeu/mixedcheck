"""Write spec/unicode/assigned-14.0.json, the code points that Unicode 14.0 assigns.

Run from the repository root with a Python whose unicodedata implements Unicode
14.0.0, which Python 3.11 does:

    python3.11 spec/tools/make_unicode_ranges.py

A code point is assigned when its general category is not Cn. The surrogates
D800 to DFFF are left out, since no string holds them. The file lists the
assigned code points as ranges of first and last code point, in ascending
order, and is written in the layout of the other JSON files under spec/.
docs/spec/conventions.md (NFC) states how the packages use it. The script uses
the Python standard library only.
"""

from __future__ import annotations

import sys
import unicodedata
from pathlib import Path

VERSION = "14.0.0"
OUT = Path(__file__).resolve().parents[1] / "unicode" / "assigned-14.0.json"
DESCRIPTION = (
    "The code points that Unicode 14.0.0 assigns, as ranges of first and last code point in "
    "ascending order, without the surrogates D800 to DFFF. A code point is assigned when its "
    "general category is not Cn. Strings that hold only these code points have the same NFC form "
    "in every later version of Unicode, so both packages normalise only such strings "
    "(docs/spec/conventions.md, NFC). Written by spec/tools/make_unicode_ranges.py from the "
    "Unicode Character Database of Python 3.11."
)


def ranges() -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    start: int | None = None
    for cp in range(0x110000):
        assigned = unicodedata.category(chr(cp)) != "Cn" and not 0xD800 <= cp <= 0xDFFF
        if assigned and start is None:
            start = cp
        elif not assigned and start is not None:
            out.append((start, cp - 1))
            start = None
    if start is not None:
        out.append((start, 0x10FFFF))
    return out


def render(items: list[tuple[int, int]]) -> str:
    lines = [
        "{",
        f'  "description": "{DESCRIPTION}",',
        f'  "unicode_version": "{VERSION}",',
        '  "ranges": [',
    ]
    lines += [f"    [{a}, {b}]," for a, b in items]
    lines[-1] = lines[-1].rstrip(",")
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def main() -> int:
    if unicodedata.unidata_version != VERSION:
        print(f"This Python implements Unicode {unicodedata.unidata_version}, not {VERSION}.")
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(render(ranges()).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
