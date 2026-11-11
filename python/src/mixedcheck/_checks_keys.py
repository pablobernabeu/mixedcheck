"""The check of the prefix keys (spec/registry/checks/keys.duplicates.yaml)."""

from __future__ import annotations

from typing import Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    Unavailable,
    check_element,
    check_unavailable,
    compared_key_columns,
    pair_codes,
    tabulate,
    value_codes,
)
from mixedcheck._commitments import observation_key_columns
from mixedcheck._unicode import comparison_form


def check_keys_duplicates(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """keys.duplicates: the rows of the table that share a value of the declared
    observation key, whether they differ in a compared column, and the rows
    with a missing key value. Key values and compared columns are compared by
    value, and missing values of a compared column equal each other."""
    import numpy as np

    key = observation_key_columns(run.declaration)
    if not key:
        return check_unavailable("declaration_missing")
    rows = run.table.rows
    codes = value_codes(run, [comparison_form(column) for column in key])
    complete = codes >= 0
    counts = tabulate(codes)
    duplicated_codes = np.flatnonzero(counts >= 2)
    shared = complete & np.isin(codes, duplicated_codes)
    conflicting = 0
    if len(duplicated_codes):
        patterns = value_codes(run, compared_key_columns(run), missing_level=True)
        shared_codes = codes[shared]
        _, first = np.unique(pair_codes(shared_codes, patterns[shared]), return_index=True)
        distinct = tabulate(shared_codes[first], len(counts))
        conflicting = int((distinct[duplicated_codes] > 1).sum())
    missing = rows - int(complete.sum())
    identical_keys = len(duplicated_codes) - conflicting
    statistics = {
        "key_columns": list(key),
        "rows": rows,
        "missing_key_rows": missing,
        "duplicated_keys": len(duplicated_codes),
        "conflicting_keys": conflicting,
        "identical_keys": identical_keys,
        "duplicate_rows": int(shared.sum()),
    }
    return [check_element(statistics, rules=[conflicting > 0, identical_keys > 0, missing > 0])]
