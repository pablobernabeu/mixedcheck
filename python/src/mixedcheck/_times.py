"""The times of a run (03-execution-plan.md, M2): UTC times truncated to whole
seconds, or the time that the environment variable MIXEDCHECK_TIME fixes, and
their form as UTC timestamps."""

from __future__ import annotations

import math
import os
import re
import time

# The last second of the year 9999, the last that a UTC timestamp can write.
LAST_SECOND = 253402300799

# Only the ASCII digits count, whatever Python's int() would read.
_DIGITS = re.compile(r"[0123456789]+")


def run_time() -> int:
    """The time of the run, in whole seconds since 1970-01-01T00:00:00Z.

    The value of MIXEDCHECK_TIME when it is set and not empty, and otherwise
    the current time truncated to whole seconds. Windows cannot hold an empty
    variable, so an empty value counts as unset in every system. Any other
    value than one or more of the ASCII digits 0 to 9, up to the end of the
    year 9999, is refused with an ordinary error.
    """
    value = os.environ.get("MIXEDCHECK_TIME", "")
    if value == "":
        return math.floor(time.time())
    digits = ""
    if _DIGITS.fullmatch(value) is not None:
        digits = value.lstrip("0") or "0"
    if digits == "" or len(digits) > 12 or int(digits) > LAST_SECOND:
        raise ValueError(
            "The environment variable MIXEDCHECK_TIME must be a whole number of seconds since "
            "1970-01-01T00:00:00Z, written in the digits 0 to 9, up to the end of the year 9999."
        )
    return int(digits)


def utc_timestamp(seconds: int) -> str:
    """A whole number of seconds since 1970-01-01T00:00:00Z as a UTC timestamp,
    YYYY-MM-DDTHH:MM:SSZ, with the days converted to a date of the proleptic
    Gregorian calendar in integer arithmetic, so that no time zone or platform
    routine is involved."""
    days, rest = divmod(int(seconds), 86400)
    z = days + 719468
    era, day_of_era = divmod(z, 146097)
    year_of_era = (
        day_of_era - day_of_era // 1460 + day_of_era // 36524 - day_of_era // 146096
    ) // 365
    day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
    month_index = (5 * day_of_year + 2) // 153
    day = day_of_year - (153 * month_index + 2) // 5 + 1
    month = month_index + (3 if month_index < 10 else -9)
    year = year_of_era + era * 400 + (1 if month <= 2 else 0)
    hours, rest = divmod(rest, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{year:04d}-{month:02d}-{day:02d}T{hours:02d}:{minutes:02d}:{secs:02d}Z"
