"""The data of a run and the keyed commitments to them that :func:`audit` writes
and the validator verifies (docs/spec/documents.md, Outcome column commitment
and Analysis table commitment, and conventions.md, Keyed commitments). The
table of a run is the form that model_table() returns: the names of the
columns as given, their comparison forms, their values, their types and their
missing values."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from mixedcheck._declaration import list_item_value
from mixedcheck._errors import internal_error, raise_issue
from mixedcheck._formula_ir import ModelTable, _declared_column, input_string, model_table
from mixedcheck._hash import keyed_commitment
from mixedcheck._json_read import read_input_bytes
from mixedcheck._json_write import json_pointer, quote_json_string
from mixedcheck._numbers import format_number
from mixedcheck._table import _BAD_TYPE, _number, read_table_bytes, table_frame
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    import pandas


@dataclass
class RunData:
    """The data of a run: the table and, for data read from a file, the bytes
    that the commitment to the data file covers."""

    table: ModelTable
    file: bytes | None


def run_data(data: Any, declaration: Any) -> RunData:
    """The data of a run (03-execution-plan.md, M2, step 3): a CSV file read by
    the table reader with the declaration's table block, or a DataFrame
    converted as formula_ir() converts it, after the declaration's missing
    values are applied when it has a table block and with E5012 for a value
    outside the declared categories of its field (tables.md, Missing values).
    The declaration is None or a value that validate_declaration() returned."""
    import pandas as pd

    table_block = declaration.get("table") if isinstance(declaration, dict) else None
    fields: list[dict[str, Any]] = list(table_block.get("fields", [])) if table_block else []
    if isinstance(data, str | os.PathLike):
        data_bytes = read_input_bytes(data)
        names, columns, types = read_table_bytes(data_bytes, table_block)
        return RunData(model_table(table_frame(names, columns, types), fields), data_bytes)
    if not isinstance(data, pd.DataFrame):
        raise TypeError("'data' must be a pandas DataFrame or the path of a CSV file.")
    if table_block is None:
        return RunData(model_table(data, fields), None)
    _check_missing_value_strings(data, table_block)
    table = model_table(data, [])
    apply_missing_values(table, table_block)
    declared_categories_held(table, fields)
    return RunData(table, None)


def declared_categories_held(table: ModelTable, fields: list[dict[str, Any]]) -> None:
    """E5012 for the first value of a DataFrame, in row order and then in the
    order of its columns, that is not missing and is not one of the declared
    categories of its field, compared after NFC for a field of type 'string'
    and by value for one of type 'integer', as the table reader checks a file
    (tables.md, Missing values). The rule on observation keys of the privacy
    filter counts a column with declared categories among those whose levels
    the declaration gives, whether or not the formula reads it."""
    import numpy as np

    field_keys = [comparison_form(field["name"]) for field in fields]
    first: tuple[int, str] | None = None
    for j, key in enumerate(table.keys):
        if key not in field_keys:
            continue
        categories = fields[field_keys.index(key)].get("categories")
        if categories is None:
            continue
        allowed = [list_item_value(item) for item in categories]
        values = table.values[j]
        if table.types[j] == "string":
            forms = {comparison_form(value) for value in allowed}
            inside = np.fromiter(
                (
                    m or comparison_form(value) in forms
                    for value, m in zip(values.tolist(), table.missing[j].tolist(), strict=True)
                ),
                dtype=bool,
                count=len(values),
            )
        else:
            inside = np.isin(values, np.array(allowed, dtype=np.float64)) | table.missing[j]
        outside = np.flatnonzero(~inside)
        if outside.size and (first is None or int(outside[0]) < first[0]):
            first = (int(outside[0]), table.names[j])
    if first is not None:
        row, name = first
        raise_issue("E5012", {"column": name}, pointer=json_pointer(["data", name, str(row)]))


def _missing_values(table_block: dict[str, Any], key: str) -> list[str]:
    """The missing values that apply to the column of a key: those of its
    field, otherwise those of the table block, otherwise the empty string."""
    for field in table_block.get("fields", []):
        if comparison_form(field["name"]) == key:
            if "missingValues" in field:
                return [list_item_value(item) for item in field["missingValues"]]
            break
    items = table_block.get("missingValues", [""])
    return [list_item_value(item) for item in items]


def _check_missing_value_strings(data: pandas.DataFrame, table_block: dict[str, Any]) -> None:
    """The input boundary in the order in which the R package crosses it when
    it applies missing values: for each column, its name and then its strings,
    when missing values apply to it, so that a surrogate code point gives
    E1206 at the same pointer in both packages."""
    import pandas as pd

    for j, name in enumerate(data.columns):
        if not isinstance(name, str):
            continue
        key = comparison_form(input_string(name, ["data", name]))
        if not _missing_values(table_block, key):
            continue
        column = data.iloc[:, j]
        if isinstance(column.dtype, pd.CategoricalDtype):
            categories = column.cat.categories.tolist()
            values: list[Any] = [
                categories[code] if code >= 0 else None for code in column.cat.codes.tolist()
            ]
        elif column.dtype == object or isinstance(column.dtype, pd.StringDtype):
            values = column.tolist()
        else:
            continue
        strings = [value for value in values if isinstance(value, str)]
        if len(strings) != sum(1 for value in values if not _is_missing(value)):
            continue
        for i, value in enumerate(values):
            if isinstance(value, str):
                input_string(value, ["data", name, str(i)])


def _is_missing(value: Any) -> bool:
    import pandas as pd

    return value is None or value is pd.NA or (isinstance(value, float) and value != value)


def apply_missing_values(table: ModelTable, table_block: dict[str, Any]) -> None:
    """Applies the missing values of a table block to the table of a DataFrame,
    in place: in each column, a string that equals one of the missing values
    that apply to the column, compared after NFC, and a number that equals the
    double to which such a value with the lexical form of a number converts,
    compared as keys compare numbers, become missing. Booleans are never
    missing. A column that the table block declares then takes the type of its
    field when every value is missing and must otherwise hold values of that
    type, as in model_table()."""
    import numpy as np

    fields = table_block.get("fields", [])
    field_keys = [comparison_form(field["name"]) for field in fields]
    for j, key in enumerate(table.keys):
        missing_values = _missing_values(table_block, key)
        values = table.values[j]
        kind = table.types[j]
        missing = table.missing[j]
        if missing_values and kind == "string":
            forms = {comparison_form(value) for value in missing_values}
            hit = np.fromiter(
                (
                    not m and comparison_form(value) in forms
                    for value, m in zip(values.tolist(), missing.tolist(), strict=True)
                ),
                dtype=bool,
                count=len(values),
            )
            if bool(hit.any()):
                values = values.copy()
                values[hit] = None
                missing = missing | hit
        elif missing_values and kind == "number":
            numbers = missing_number_values(missing_values)
            if numbers:
                finite = np.array([n for n in numbers if n == n], dtype=np.float64)
                hit = np.isin(values, finite)
                if any(n != n for n in numbers):
                    hit |= np.isnan(values)
                missing = missing | hit
        declared = fields[field_keys.index(key)] if key in field_keys else None
        values, kind, missing = _declared_column(values, kind, missing, table.names[j], declared)
        table.values[j] = values
        table.types[j] = kind
        table.missing[j] = missing


def missing_number_values(text: list[str]) -> list[float]:
    """The doubles to which missing values with the lexical form of a number
    convert, as the table reader converts the values of a number column
    (tables.md, Field types). A value that converts to an infinity, or to zero
    from a non-zero value, has no such double."""
    found = []
    for value in text:
        number = _number(value)
        if number is not _BAD_TYPE:
            found.append(float(number))
    return found


def observation_key_columns(declaration: Any) -> list[str]:
    """The columns of the declared observation key, in declared order, or none
    when no key is declared or the key counts as absent, because
    /provenance/inferred points to the key, to one of its columns or to the
    observation block (registry.md, Terms)."""
    if not isinstance(declaration, dict):
        return []
    key = list(declaration.get("observation", {}).get("key", []))
    if not key:
        return []
    inferred = [str(p) for p in declaration.get("provenance", {}).get("inferred", [])]
    if any(
        p in ("/observation", "/observation/key") or p.startswith("/observation/key/")
        for p in inferred
    ):
        return []
    return key


def outcome_column_keys(declaration: Any, response: str | None = None) -> list[str]:
    """The comparison forms of the outcome columns that the analysis table
    leaves out: the columns that the declaration gives the role outcome or
    outcome_derived, the response and its declared trials column. response is
    the name of the response column, or None for a one-sided formula."""
    variables = declaration.get("variables", {}) if isinstance(declaration, dict) else {}
    keys = [
        comparison_form(name)
        for name, entry in variables.items()
        if entry.get("role") in ("outcome", "outcome_derived")
    ]
    if response is not None:
        response_key = comparison_form(response)
        keys.append(response_key)
        for name, entry in variables.items():
            if comparison_form(name) == response_key:
                if "trials" in entry:
                    keys.append(comparison_form(entry["trials"]))
                break
    return list(dict.fromkeys(keys))


def json_cells(values: Any, kind: str, missing: Any) -> list[str]:
    """The JSON text of each value of a column of a run's table, as a writer in
    the data profile writes it: a missing value as null, a finite double as
    RFC 8785 writes it, NaN and the infinities as 'NaN', 'Infinity' and
    '-Infinity', a string with its escapes and a boolean as true or false."""
    import numpy as np

    n = len(values)
    if kind == "number":
        unique, inverse = np.unique(values, return_inverse=True)
        texts = []
        for value in unique.tolist():
            if value != value:
                texts.append('"NaN"')
            elif value == float("inf"):
                texts.append('"Infinity"')
            elif value == float("-inf"):
                texts.append('"-Infinity"')
            else:
                texts.append(format_number(value))
        cells = [texts[i] for i in inverse.reshape(-1).tolist()]
    elif kind == "string":
        cells = [
            "null" if m else quote_json_string(value)
            for value, m in zip(values.tolist(), missing.tolist(), strict=True)
        ]
        return cells
    else:
        cells = ["true" if value else "false" for value in values.tolist()]
    for i in np.flatnonzero(missing).tolist():
        cells[i] = "null"
    assert len(cells) == n
    return cells


def commitment_rows(table: ModelTable, positions: list[int], key: list[int]) -> str:
    """The canonical bytes, as text, of the rows of a commitment message: one
    array for each row of the table with the values of the columns at the
    positions given, ordered by the canonical bytes of the array of their key
    values, compared byte by byte with a prefix first, and then by the bytes of
    the whole row, when key holds the positions of the key columns, and in the
    order of the table otherwise. UTF-8 orders strings as their code points
    do, so that the strs are compared directly."""
    if table.rows == 0:
        return "[]"

    def json_rows(columns: list[int]) -> list[str]:
        if not columns:
            return ["[]"] * table.rows
        cells = [json_cells(table.values[j], table.types[j], table.missing[j]) for j in columns]
        return ["[" + ",".join(row) + "]" for row in zip(*cells, strict=True)]

    rows = json_rows(positions)
    if key:
        key_rows = json_rows(key)
        order = sorted(range(table.rows), key=lambda i: (key_rows[i], rows[i]))
        rows = [rows[i] for i in order]
    return "[" + ",".join(rows) + "]"


def table_positions(table: ModelTable, columns: list[str]) -> list[int] | None:
    """The positions of the named columns in a run's table, compared after NFC,
    or None when one of them is not a column of the table."""
    positions = []
    for column in columns:
        j = table.index(comparison_form(column))
        if j is None:
            return None
        positions.append(j)
    return positions


def json_string_array(x: list[str]) -> str:
    """The canonical bytes of an array of strings, as text."""
    return "[" + ",".join(quote_json_string(value) for value in x) + "]"


def analysis_table_message(
    table: ModelTable, declaration: Any, response: str | None = None
) -> bytes | None:
    """The message of the commitment to the analysis table (documents.md,
    Analysis table commitment): the canonical bytes of the columns of the table
    other than the outcome columns, the observation key and the rows. None when
    a column of the key is not a column of the table."""
    key_columns = observation_key_columns(declaration)
    key = table_positions(table, key_columns)
    if key is None:
        return None
    outcomes = set(outcome_column_keys(declaration, response))
    kept = [j for j, k in enumerate(table.keys) if k not in outcomes]
    text = (
        '{"columns":'
        + json_string_array([table.names[j] for j in kept])
        + ',"key":'
        + json_string_array(key_columns)
        + ',"rows":'
        + commitment_rows(table, kept, key)
        + "}"
    )
    return text.encode("utf-8")


def outcome_column_message(table: ModelTable, declaration: Any, column: str) -> bytes | None:
    """The message of the commitment to an outcome column (documents.md, Outcome
    column commitment): the canonical bytes of the column's name, the
    observation key and, for each row of the table, the key values followed by
    the value of the column. column is the name that the access log records.
    None when the column or a column of the key is not a column of the table."""
    key_columns = observation_key_columns(declaration)
    key = table_positions(table, key_columns)
    outcome = table_positions(table, [column])
    if key is None or outcome is None:
        return None
    text = (
        '{"column":'
        + quote_json_string(column)
        + ',"key":'
        + json_string_array(key_columns)
        + ',"rows":'
        + commitment_rows(table, key + outcome, key)
        + "}"
    )
    return text.encode("utf-8")


def data_commitments(
    data: RunData, declaration: Any, response: str | None, key: str
) -> dict[str, dict[str, str]]:
    """The commitments of /inputs/data for the data of a run under a key: the
    analysis table always, and the data file when the run read one. response
    is the response column of the IR, or None."""
    message = analysis_table_message(data.table, declaration, response)
    if message is None:
        internal_error("the analysis table has no message.")
    commitments = {"analysis_table": keyed_commitment(message, key, "analysis_table")}
    if data.file is not None:
        commitments["data_file"] = keyed_commitment(data.file, key, "data_file")
    return commitments


def outcome_commitment(data: RunData, declaration: Any, column: str, key: str) -> dict[str, str]:
    """The commitment of an access log entry to an outcome column of the data of
    a run, the response or its trials column, under a key."""
    message = outcome_column_message(data.table, declaration, column)
    if message is None:
        internal_error("the outcome column has no message.")
    return keyed_commitment(message, key, "outcome_column")
