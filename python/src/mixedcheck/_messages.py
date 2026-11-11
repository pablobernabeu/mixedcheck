"""The rendering of the messages of findings (docs/spec/registry.md, Messages):
the template, or the fallback when a statistic that the template renders is
not written, with each placeholder replaced by its argument."""

from __future__ import annotations

import math
import re
from collections.abc import Iterable, Mapping
from typing import Any

from mixedcheck._errors import display_text, format_integer, internal_error

_PLACEHOLDER = re.compile(r"\{([a-z][a-z0-9_]*)\}")

# The double 10^15, from which a real renders in scientific notation.
SCIENTIFIC_FROM = 1e15


def render_message(
    entry: Mapping[str, Any],
    id: str,
    scope: Mapping[str, str],
    values: Mapping[str, Any],
    written: Iterable[str] | None = None,
) -> str:
    """The text of a message of an entry for a finding.

    ``values`` holds the values of the statistics by name, with the
    pseudonyms of labels in a shareable document, and ``written`` the names of
    those that the document writes, by default every statistic in ``values``,
    as in internal mode. The template renders when every statistic that it
    renders is written, and the fallback otherwise.
    """
    message = entry["messages"].get(id)
    if message is None:
        internal_error(f"{entry['id']} has no message '{id}'.")
    shown = set(values if written is None else written)
    args = message["args"]
    complete = all(arg["name"] in shown for arg in args.values() if arg["source"] == "statistic")
    template = message["template"] if complete else message.get("fallback")
    if template is None:
        internal_error(
            f"the message '{id}' of {entry['id']} renders a statistic that is not written."
        )
    # Templates are ASCII, so that nothing depends on how a placeholder is found.
    return _PLACEHOLDER.sub(
        lambda match: render_message_argument(args[match.group(1)], entry, scope, values),
        template,
    )


def render_message_argument(
    arg: Mapping[str, Any],
    entry: Mapping[str, Any],
    scope: Mapping[str, str],
    values: Mapping[str, Any],
) -> str:
    """One argument of a message: a scope part after display escaping, a
    threshold or parameter as written, a ratio threshold as a percentage, or a
    statistic rendered by its kind."""
    name = arg["name"]
    source = arg["source"]
    if source == "scope":
        return display_text(scope[name], limit=None)
    if source == "parameter":
        return str(entry["parameters"][name]["value"])
    if source == "threshold":
        threshold = entry["thresholds"][name]
        kind = entry["statistics"][threshold["statistic"]]["kind"]
        value = str(threshold["value"])
        return percent_text(value) if kind == "ratio" else value
    statistic = entry["statistics"][name]
    kind = statistic["kind"]
    value = values[name]
    if kind == "count":
        text = format_integer(value)
        noun = arg.get("noun")
        if noun:
            return text + " " + str(noun[0] if text == "1" else noun[1])
        return text
    if kind == "ratio":
        return ratio_text(
            values[statistic["numerator"]], values[statistic["denominator"]], arg["digits"]
        )
    if kind == "real":
        return real_text(value, arg["digits"])
    if kind == "category":
        return str(value).replace("_", " ")
    if kind in ("names", "labels"):
        return names_text(value)
    internal_error(f"a statistic of kind {kind} cannot be rendered.")


def names_text(x: Iterable[str]) -> str:
    """Names or labels, each in single quotation marks after display escaping,
    joined by ', ' except the last two, which are joined by ' and ', or
    'none'."""
    quoted = ["'" + display_text(value, limit=None) + "'" for value in x]
    if not quoted:
        return "none"
    if len(quoted) == 1:
        return quoted[0]
    return ", ".join(quoted[:-1]) + " and " + quoted[-1]


def percent_text(value: str) -> str:
    """A decimal string with its decimal point moved two places to the right and
    followed by '%', so that '0.15' gives '15%', '0.125' '12.5%' and '1'
    '100%'."""
    whole, _, fraction = value.partition(".")
    fraction = fraction + "0" * max(0, 2 - len(fraction))
    digits = (whole + fraction[:2]).lstrip("0") or "0"
    rest = fraction[2:].rstrip("0")
    return digits + ("." + rest if rest else "") + "%"


def ratio_text(a: Any, b: Any, digits: int) -> str:
    """The integer q nearest to a x 100 x 10^digits / b, a tie going to the
    even integer, computed in integer arithmetic and written with 'digits'
    decimal places and followed by '%'."""
    q, r = divmod(int(a) * 100 * 10 ** int(digits), int(b))
    if 2 * r > int(b) or (2 * r == int(b) and q % 2 == 1):
        q += 1
    return point_digits(str(q), int(digits)) + "%"


def point_digits(text: str, digits: int) -> str:
    """Decimal digits of a non-negative integer with a decimal point placed
    'digits' places from the right."""
    if digits == 0:
        return text
    text = "0" * max(0, digits + 1 - len(text)) + text
    return text[: len(text) - digits] + "." + text[len(text) - digits :]


def real_text(x: float, digits: int) -> str:
    """A real statistic as a message renders it (registry.md, Messages).

    A finite double whose absolute value is at least 1e15, a bound that the
    double 10^15 holds exactly, is written as ``f"{x:.{digits}e}"`` writes it,
    and any other finite double as ``f"{x:z.{digits}f}"`` does, whose option
    'z' drops the sign of a rounded zero. Python's format() rounds the exact
    binary value half to even. A double above 0 whose fixed rendering has no
    digit other than 0 is written as 'under' and the smallest positive value
    at that number of places, which the rendering itself decides. NaN and the
    infinities are written as 'NaN', 'Infinity' and '-Infinity'.
    """
    value = float(x)
    places = int(digits)
    if math.isnan(value):
        return "NaN"
    if math.isinf(value):
        return "Infinity" if value > 0 else "-Infinity"
    if abs(value) >= SCIENTIFIC_FROM:
        return format(value, f".{places}e")
    text = format(value, f"z.{places}f")
    if value > 0 and not any("1" <= char <= "9" for char in text):
        return "under " + point_digits("1", places)
    return text
