"""The table corpus, run from the installed package: CSV inputs read with the
strict table reader, with and without the table block of a declaration
(fixtures/conformance/tables/README.md).

Each case gives the columns that the reader returns, with their names, types
and values, or the one issue that it reports, with its code, message and byte
offset. The cases with a formula also give the design and analysis samples of
the IR that formula_ir() builds from the formula, the declaration and the table
read, with rows counted from 0. They are computed with the internal
design_samples(), since design_matrices() reports E6073 for two of them.
"""

from __future__ import annotations

import math
from importlib.resources import as_file
from typing import Any

from corpus_helpers import (
    capture,
    corpus_cases,
    corpus_directory,
    expect_issue,
    parametrize_cases,
    special_path,
)

from mixedcheck import design_samples, formula_ir, read_table

TABLE_FILES = (
    "edgezoo.json",
    "edge.json",
    "input.json",
    "records.json",
    "header.json",
    "values.json",
    "inference.json",
    "keys.json",
    "precedence.json",
    "samples.json",
)

# The Python types of the values of each column type.
VALUE_TYPES = {
    "string": str,
    "date": str,
    "datetime": str,
    "integer": int,
    "number": float,
    "boolean": bool,
}
SPECIAL_NUMBERS = {"Infinity": math.inf, "-Infinity": -math.inf}


def test_every_corpus_file_has_cases():
    for name in TABLE_FILES:
        assert corpus_cases("tables", name), name
    assert sum(len(corpus_cases("tables", name)) for name in TABLE_FILES) == 194
    with_formula = [
        case for name in TABLE_FILES for case in corpus_cases("tables", name) if "formula" in case
    ]
    assert len(with_formula) == 10


def read_case(case: dict[str, Any], tmp_path) -> dict[str, Any]:
    """Read the input of a case with its declaration, if it has one."""
    declaration = case.get("declaration")
    if "file" in case:
        path = special_path(case["file"], tmp_path)
        return capture(lambda: read_table(path, declaration))
    with as_file(corpus_directory("tables") / case["path"]) as file:
        return capture(lambda: read_table(str(file), declaration))


def expect_value(got: Any, want: Any, kind: str, label: str) -> None:
    """Compare one value with the value that the corpus writes in the data
    profile: strings code point by code point, numbers by value, with 'NaN',
    'Infinity' and '-Infinity' for the special values, and null for a missing
    value."""
    if want is None:
        assert got is None, label
        return
    assert type(got) is VALUE_TYPES[kind], f"{label}: {got!r} has the type {type(got).__name__}"
    if kind == "number" and want == "NaN":
        assert math.isnan(got), label
    elif kind == "number" and isinstance(want, str):
        assert got == SPECIAL_NUMBERS[want], label
    else:
        assert got == want, f"{label}: {got!r} against {want!r}"


def expect_columns(result: dict[str, Any], expected: list[dict[str, Any]], label: str) -> None:
    """Compare the DataFrame read with the expected columns: their names and
    order, their types and every value."""
    assert "value" in result, f"{label}: expected columns, got {result.get('issues')}."
    frame = result["value"]
    names = [column["name"] for column in expected]
    assert list(frame.columns) == names, label
    assert list(frame.attrs["types"].items()) == [
        (column["name"], column["type"]) for column in expected
    ], label
    for position, column in enumerate(expected):
        series = frame.iloc[:, position]
        assert series.dtype.kind == "O", label
        values = series.tolist()
        assert len(values) == len(column["values"]), label
        for row, (got, want) in enumerate(zip(values, column["values"], strict=True)):
            expect_value(got, want, column["type"], f"{label} {column['name']!r} row {row}")


def expect_samples(frame: Any, case: dict[str, Any], label: str) -> None:
    """Compare the design and analysis samples of the IR of a case's formula
    with those the case gives."""
    ir = capture(lambda: formula_ir(case["formula"], case.get("declaration"), frame))
    assert "value" in ir, f"{label}: expected an IR, got {ir.get('issues')}."
    samples = design_samples(ir["value"], frame)
    expected = case["expected"]
    assert samples["design_sample"].tolist() == expected["design_sample"], f"{label} design"
    assert samples["analysis_sample"].tolist() == expected["analysis_sample"], f"{label} analysis"


@parametrize_cases("tables", *TABLE_FILES)
def test_table_corpus(case, tmp_path):
    result = read_case(case, tmp_path)
    expected = case["expected"]
    if "issue" in expected:
        expect_issue(result, expected["issue"], case["id"])
    else:
        expect_columns(result, expected["columns"], case["id"])
        if "formula" in case:
            expect_samples(result["value"], case, case["id"])
