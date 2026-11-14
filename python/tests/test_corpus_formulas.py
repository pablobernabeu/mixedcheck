"""The formula corpus: formulas with their declaration, data, coding, weights
and sample columns, and the expected IR with its hash, with the design
matrices of the design sample or the issue that they report for some cases,
or the one issue that the builder reports
(fixtures/conformance/formulas/README.md).

Each case with data runs twice: with columns of dtype object, as read_table()
returns them, and with pandas' nullable dtypes, which formula_ir() reads the
same way.
"""

from __future__ import annotations

import math
from typing import Any

import numpy as np
import pandas as pd
import pytest
from corpus_helpers import capture, corpus_cases, expect_issue
from scipy import sparse

from mixedcheck import canonical_bytes, design_matrices, formula_ir, hash_bytes

FORMULA_FILES = (
    "ordinary.json",
    "interactions.json",
    "nested.json",
    "crossed.json",
    "double_bar.json",
    "offsets.json",
    "malformed.json",
    "context.json",
)

CASES = [case for name in FORMULA_FILES for case in corpus_cases("formulas", name)]


SPECIAL_VALUES = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}


def corpus_frame(data: dict[str, list[Any]], representation: str) -> pd.DataFrame:
    """The DataFrame of the data of a case: one column for each member, with
    None for null and the strings 'NaN', 'Infinity' and '-Infinity' of a column
    of numbers as the special values. 'object' gives columns of dtype object,
    and 'nullable' gives the nullable dtypes Float64, boolean and string, whose
    missing values are pandas.NA and in which NaN stays a value."""
    columns = {}
    for name, values in data.items():
        present = [value for value in values if value is not None]
        numbers = any(isinstance(v, int | float) and not isinstance(v, bool) for v in present)
        if numbers:
            values = [SPECIAL_VALUES[v] if isinstance(v, str) else v for v in values]
        if representation == "object":
            columns[name] = pd.Series(values, dtype=object)
        elif numbers:
            mask = np.array([value is None for value in values])
            floats = np.array([0.0 if value is None else value for value in values], dtype=float)
            columns[name] = pd.Series(pd.arrays.FloatingArray(floats, mask))
        elif all(isinstance(value, bool) for value in present):
            columns[name] = pd.Series(values, dtype="boolean")
        else:
            columns[name] = pd.Series(values, dtype="string")
    return pd.DataFrame(columns)


def expect_exact(got: np.ndarray, want: list[list[Any]], rows: int, label: str) -> None:
    """Compare a matrix with the expected rows value by value, exactly."""
    expected = np.array(want, dtype=np.float64).reshape(rows, -1)
    assert got.dtype == np.float64, label
    assert got.shape == expected.shape, label
    assert not np.isnan(got).any(), label
    assert (got == expected).all(), f"{label}: {got.tolist()} against {want}"


def expect_matrices(ir: dict[str, Any], data: pd.DataFrame, expected: dict[str, Any], label: str):
    """The design matrices of a case: the rows of the design sample, X, the
    columns that the sequential rule drops and Z with its columns, whose terms
    and rows count from 0 in the corpus and in Python."""
    result = capture(lambda: design_matrices(ir, data))
    assert "value" in result, f"{label}: expected matrices, got {result.get('issues')}."
    m = result["value"]
    rows = expected["rows"]
    assert m["design_sample"].dtype == np.int64, label
    assert m["design_sample"].tolist() == rows, label
    expect_exact(m["x"], expected["x"], len(rows), f"{label} X")
    assert m["x_columns"] == [column["name"] for column in ir["fixed"]["columns"]], label
    assert m["x_dropped"] == expected["x_dropped"], label
    z = m["z"]
    assert isinstance(z, sparse.csc_array), label
    if "z" not in expected:
        assert z.shape == (len(rows), 0), label
        assert len(m["z_columns"]) == 0, label
        return
    expect_exact(z.toarray(), expected["z"], len(rows), f"{label} Z")
    described = m["z_columns"]
    assert list(described.columns) == ["term", "level", "column"], label
    assert described["term"].dtype == np.int64, label
    got = list(
        zip(
            described["term"].tolist(),
            described["level"].tolist(),
            described["column"].tolist(),
            strict=True,
        )
    )
    assert got == [(c["term"], c["level"], c["column"]) for c in expected["z_columns"]], label
    # One stored entry for each row and each column of a random term, zero or
    # not (ir.md, Z).
    widths = [len(term["columns"]) for term in ir["random"]]
    assert z.nnz == len(rows) * sum(widths), label


def run_case(case: dict[str, Any], representation: str) -> None:
    data = corpus_frame(case["data"], representation) if "data" in case else None
    result = capture(
        lambda: formula_ir(
            case["formula"],
            case.get("declaration"),
            data,
            case.get("coding"),
            case.get("weights"),
            case.get("sample_columns"),
        )
    )
    expected = case["expected"]
    label = f"{case['id']} {representation}"
    if "ir" not in expected:
        expect_issue(result, expected["issue"], label)
        return
    assert "value" in result, f"{label}: expected an IR, got {result.get('issues')}."
    data_bytes = canonical_bytes(result["value"], "hashable")
    assert data_bytes == canonical_bytes(expected["ir"], "hashable"), label
    assert hash_bytes(data_bytes) == expected["ir_hash"], label
    if "matrices" in expected:
        assert data is not None
        expect_matrices(result["value"], data, expected["matrices"], label)
    if "issue" in expected:
        assert data is not None
        expect_issue(
            capture(lambda: design_matrices(result["value"], data)), expected["issue"], label
        )


@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_formula_corpus(case):
    run_case(case, "object")


@pytest.mark.parametrize(
    "case", [case for case in CASES if "data" in case], ids=lambda case: case["id"]
)
def test_formula_corpus_with_nullable_dtypes(case):
    run_case(case, "nullable")


def test_the_formula_corpus_holds_250_cases_33_with_matrices_9_with_their_issue():
    for name in FORMULA_FILES:
        assert corpus_cases("formulas", name), name
    assert len(CASES) == 250
    assert sum("matrices" in case["expected"] for case in CASES) == 33
    assert sum({"ir", "issue"} <= set(case["expected"]) for case in CASES) == 9
