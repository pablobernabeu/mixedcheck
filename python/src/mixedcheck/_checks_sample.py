"""The check of the prefix sample (spec/registry/checks/sample.raw_vs_analysis.yaml)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    check_element,
    column_codes,
    column_index,
    tabulate,
    value_codes,
)
from mixedcheck._unicode import comparison_form, sort_identifiers

if TYPE_CHECKING:
    import numpy


def check_sample_raw_vs_analysis(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """sample.raw_vs_analysis: the rows of the table that leave the design
    sample, the columns whose missing values remove them, and the factors and
    grouping factors whose levels the design sample loses or leaves with one
    row."""
    import numpy as np

    ir = run.ir
    design = run.design
    table_rows = run.table.rows
    in_design = np.zeros(table_rows, dtype=bool)
    in_design[design] = True
    # The columns that the IR reads, other than the response and its trials
    # column, and its sample columns, as the design sample reads them.
    read = list(
        dict.fromkeys(
            list(ir["predictors"])
            + run.grouping_columns
            + [o["variable"] for o in ir["offsets"]]
            + ([ir["weights"]["variable"]] if "weights" in ir else [])
            + list(ir.get("sample_columns", []))
        )
    )
    incomplete = [key for key in read if bool((column_codes(run, key) < 0).any())]
    categorical = {
        key: predictor
        for key, predictor in ir["predictors"].items()
        if predictor["kind"] == "categorical"
    }
    keys = sort_identifiers(categorical)

    def loses_levels(codes: numpy.ndarray[Any, Any]) -> bool:
        present = np.unique(codes[codes >= 0])
        return len(np.setdiff1d(present, codes[in_design])) > 0

    emptied = [key for key in keys if loses_levels(column_codes(run, key))]
    contrasts = {
        variable["variable"]
        for part in [ir["fixed"]] + ir["random"]
        for term in part["terms"]
        for variable in term["variables"]
        if variable.get("coding") == "contrast"
    }
    reference_emptied = [
        key
        for key in keys
        if key in contrasts
        and not bool(reference_rows(run, key, categorical[key]["reference"])[design].any())
    ]
    factor_codes = {name: value_codes(run, columns) for name, columns in run.factors.items()}
    losing = [name for name, codes in factor_codes.items() if loses_levels(codes)]

    def has_new_singletons(codes: numpy.ndarray[Any, Any]) -> bool:
        in_table = tabulate(codes)
        in_sample = tabulate(codes[in_design], len(in_table))
        return bool(((in_sample == 1) & (in_table > 1)).any())

    singletons = [name for name, codes in factor_codes.items() if has_new_singletons(codes)]
    rows_kept = len(design)
    statistics = {
        "rows_raw": table_rows,
        "rows_kept": rows_kept,
        "rows_dropped": table_rows - rows_kept,
        "incomplete_columns": sort_identifiers(incomplete),
        "emptied_factors": emptied,
        "reference_emptied": reference_emptied,
        "factors_losing_levels": losing,
        "new_singletons": singletons,
    }
    return [
        check_element(statistics, rules=[len(reference_emptied) > 0, table_rows - rows_kept > 0])
    ]


def reference_rows(run: Run, key: str, reference: Any) -> numpy.ndarray[Any, Any]:
    """Whether each row of the table holds the reference level of a categorical
    predictor, compared by value: a string after NFC, a number by value and a
    boolean by value."""
    import numpy as np

    j = column_index(run, key)
    values = run.table.values[j]
    kind = run.table.types[j]
    missing = run.table.missing[j]
    n = run.table.rows
    if kind == "string" and isinstance(reference, str):
        hit = np.fromiter(
            (
                not m and comparison_form(value) == reference
                for value, m in zip(values.tolist(), missing.tolist(), strict=True)
            ),
            dtype=bool,
            count=n,
        )
    elif kind == "boolean" and isinstance(reference, bool):
        hit = values == reference
    elif (
        kind == "number" and isinstance(reference, int | float) and not isinstance(reference, bool)
    ):
        hit = values == float(reference)
    else:
        hit = np.zeros(n, dtype=bool)
    found: numpy.ndarray[Any, Any] = ~missing & hit
    return found
