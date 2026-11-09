"""Targeted tests of the design and analysis samples, the design matrices, the
response, offset and weight vectors and the sequential rule (docs/spec/ir.md),
and a loose check of their speed."""

from __future__ import annotations

import math
import re
import time
import warnings
from typing import Any

import numpy as np
import pandas as pd
import pytest
from scipy import sparse

from mixedcheck import MixedcheckError, design_matrices, design_samples, formula_ir
from mixedcheck._design import sequential_rule


def issue_code(f, *args: Any) -> str:
    with pytest.raises(MixedcheckError) as caught:
        f(*args)
    assert len(caught.value.issues) == 1
    return caught.value.issues[0]["code"]


def test_the_sequential_rule_drops_zero_columns_and_later_members_of_dependencies():
    x = np.column_stack([np.ones(4), [1.0, 2, 3, 4], np.zeros(4), [2.0, 4, 6, 8], [1.0, 0, 0, 1]])
    assert sequential_rule(x) == [True, True, False, False, True]
    assert sequential_rule(x[:, [3, 1]]) == [True, False]
    base = np.array([1.0, 2, 3, 4])
    near = base + np.array([1.0, -1, -1, 1]) * 1e-6
    far = base + np.array([1.0, -1, -1, 1]) * 1e-8
    assert sequential_rule(np.column_stack([np.ones(4), base, near])) == [True, True, True]
    assert sequential_rule(np.column_stack([np.ones(4), base, far])) == [True, True, False]
    assert sequential_rule(np.zeros((3, 0))) == []


def test_the_response_trials_offset_and_weight_vectors_follow_the_samples():
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
    }
    data = pd.DataFrame(
        {
            "k": pd.Series([1.0, 2.0, None, 0.0, 3.0], dtype=object),
            "n": [4.0, 0.0, 2.0, 3.0, 5.0],
            "x": pd.Series([1.0, 2.0, 3.0, None, 5.0], dtype=object),
            "e": [1.0, 2.0, 4.0, 8.0, 16.0],
            "z": [0.5, 0.25, 0.0, 1.0, 2.0],
            "w": [1.0, 2.0, 3.0, 4.0, 0.5],
        }
    )
    ir = formula_ir("k ~ x + offset(log(e)) + offset(z)", declaration, data, weights="w")
    m = design_matrices(ir, data)
    assert m["design_sample"].dtype == np.int64
    assert m["design_sample"].tolist() == [0, 1, 2, 4]
    assert m["analysis_sample"].tolist() == [0, 4]
    assert m["response"].tolist() == [1.0, 3.0]
    assert m["trials"].tolist() == [4.0, 5.0]
    expected = np.log(np.array([1.0, 2.0, 4.0, 16.0])) + np.array([0.5, 0.25, 0.0, 2.0])
    assert m["offset"].tolist() == expected.tolist()
    assert m["weights"].tolist() == [1.0, 2.0, 3.0, 0.5]


def test_an_event_level_a_log_response_and_a_boolean_response_give_their_vectors():
    data = pd.DataFrame(
        {
            "acc": ["correct", "error", "corre\u0301ct"],
            "rt": [350.0, 420.0, 515.5],
            "ok": [True, False, True],
            "x": [1.0, 2.0, 3.0],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {
            "acc": {"role": "outcome", "measurement": "binary", "event_level": "correct"}
        },
    }
    m = design_matrices(formula_ir("acc ~ x", declaration, data), data)
    assert m["response"].tolist() == [1.0, 0.0, 0.0]
    assert design_matrices(formula_ir("acc ~ x", data=data), data)["response"] is None
    m = design_matrices(formula_ir("log(rt) ~ x", data=data), data)
    assert m["response"].tolist() == np.log(np.array([350.0, 420.0, 515.5])).tolist()
    m = design_matrices(formula_ir("ok ~ x", data=data), data)
    assert m["response"].tolist() == [1.0, 0.0, 1.0]
    assert m["offset"] is None
    assert m["weights"] is None
    assert m["trials"] is None
    assert design_matrices(formula_ir("~ x", data=data), data)["response"] is None
    declaration["variables"] = {"w": {"role": "outcome", "measurement": "binary", "event_level": 2}}
    data["w"] = [2.0, 1.0, 2.0]
    m = design_matrices(formula_ir("w ~ x", declaration, data), data)
    assert m["response"].tolist() == [1.0, 0.0, 1.0]


def test_the_matrices_report_their_problems_in_the_order_of_ir_md():
    data = pd.DataFrame(
        {"y": [1.0, 2.0, 3.0], "x": [1.0, 2.0, 3.0], "e": [1.0, 0.0, 2.0], "w": [1.0, -1.0, 1.0]}
    )
    ir = formula_ir("y ~ x + offset(log(e))", data=data, weights="w")
    assert issue_code(design_matrices, ir, data) == "E6071"
    ir = formula_ir("y ~ x", data=data, weights="w")
    assert issue_code(design_matrices, ir, data) == "E6072"
    data.loc[1, "x"] = math.inf
    assert issue_code(design_matrices, ir, data) == "E6073"
    data = pd.DataFrame({"y": [1.0, math.nan, 3.0], "x": [1.0, 2.0, 3.0]})
    assert issue_code(design_matrices, formula_ir("y ~ x", data=data), data) == "E6073"
    data = pd.DataFrame({"y": [1.0, 0.0, 3.0], "x": [1.0, 2.0, 3.0]})
    assert issue_code(design_matrices, formula_ir("log(y) ~ x", data=data), data) == "E6071"
    data["y"] = pd.Series([1.0, None, 3.0], dtype=object)
    m = design_matrices(formula_ir("log(y) ~ x", data=data), data)
    assert m["response"].tolist() == [0.0, math.log(3.0)]
    data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "x": [1.0, 2.0, 3.0], "g": [1.0, math.nan, 2.0]})
    assert issue_code(design_matrices, formula_ir("y ~ x + (1 | g)", data=data), data) == "E6073"


def test_e6071_for_an_offset_and_e6072_apply_to_rows_whose_response_is_missing():
    data = pd.DataFrame(
        {
            "y": pd.Series([1.0, None, 3.0], dtype=object),
            "x": [1.0, 2.0, 3.0],
            "e": [1.0, 0.0, 2.0],
            "w": [1.0, 0.0, 1.0],
        }
    )
    ir = formula_ir("y ~ x + offset(log(e))", data=data)
    assert design_samples(ir, data)["analysis_sample"].tolist() == [0, 2]
    assert issue_code(design_matrices, ir, data) == "E6071"
    ir = formula_ir("y ~ x", data=data, weights="w")
    assert issue_code(design_matrices, ir, data) == "E6072"


def test_z_stores_one_entry_for_each_row_and_column_of_a_term_zero_or_not():
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6],
            "x": [0.0, 1, 2, 0, 1, 2],
            "g": [2.0, 10, 1.5, 2, 10, 1.5],
            "h": [True, False, True, False, True, False],
        }
    )
    m = design_matrices(formula_ir("y ~ x + (1 + x | g) + (1 | g:h)", data=data), data)
    assert isinstance(m["z"], sparse.csc_array)
    assert m["z"].nnz == 6 * 3
    assert m["z_columns"]["level"].tolist()[0:6:2] == ["1.5", "2", "10"]
    assert m["z_columns"]["level"].tolist()[6:12] == [
        "1.5:false",
        "1.5:true",
        "2:false",
        "2:true",
        "10:false",
        "10:true",
    ]
    assert m["z_columns"]["term"].tolist() == [0] * 6 + [1] * 6
    assert m["z"].toarray()[0].tolist() == [0.0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0]


def test_a_random_slope_of_0_keeps_its_stored_entry_in_z():
    # The slope of level 'a' is 0 in both of its rows and that of level 'b' in
    # its first row. scipy keeps explicit zeros, from scipy 1.15 on.
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4],
            "x": [0.0, 0, 0, 3],
            "g": pd.Series(["a", "a", "b", "b"], dtype=object),
        }
    )
    z = design_matrices(formula_ir("y ~ x + (1 + x | g)", data=data), data)["z"]
    assert isinstance(z, sparse.csc_array)
    assert z.nnz == z.shape[0] * 2
    assert z.indptr.tolist() == [0, 2, 4, 6, 8]
    assert z.indices.tolist() == [0, 1, 0, 1, 2, 3, 2, 3]
    assert z.data.tolist() == [1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 3.0]
    assert z.count_nonzero() == 5


def test_grouping_labels_compare_strings_after_nfc_in_code_point_order():
    data = pd.DataFrame(
        {"y": [1.0, 2, 3, 4], "g": ["i10", "i2", "\u00e9", "e\u0301"], "s": ["B", "a", "B", "a"]}
    )
    m = design_matrices(formula_ir("y ~ (1 | g) + (1 | s:g)", data=data), data)
    assert m["z_columns"]["level"].tolist() == [
        "i10",
        "i2",
        "\u00e9",
        "B:i10",
        "B:\u00e9",
        "a:i2",
        "a:\u00e9",
    ]
    assert m["z"].toarray()[3].tolist() == [0.0, 0, 1, 0, 0, 0, 1]


def test_a_level_outside_the_levels_of_the_ir_and_a_missing_column_are_refused():
    data = pd.DataFrame({"y": [1.0, 2, 3], "a": ["A", "B", "A"]})
    ir = formula_ir("y ~ a", data=data)
    data.loc[2, "a"] = "C"
    with pytest.raises(ValueError, match="not one of its levels") as caught:
        design_matrices(ir, data)
    assert not isinstance(caught.value, MixedcheckError)
    with pytest.raises(ValueError, match="is not in 'data'"):
        design_matrices(ir, pd.DataFrame({"y": [1.0, 2.0]}))
    with pytest.raises(TypeError, match="'data' must be"):
        design_matrices(ir, {"y": [1.0]})  # type: ignore[arg-type]


def test_a_level_of_the_ir_outside_its_predictor_levels_is_refused():
    data = pd.DataFrame({"y": [1.5, 2.25, 3.0, 2.5], "cond": ["A", "B", "A", "B"]})
    ir = formula_ir("y ~ cond", data=data)
    for level, shown in (("C", "C"), ("C\t", "C\\u0009"), (True, "true")):
        ir["fixed"]["columns"][1]["levels"]["cond"] = level
        with pytest.raises(ValueError, match=re.escape(f"The level '{shown}' is not one")):
            design_matrices(ir, data)


def test_the_ir_is_checked_before_it_is_used():
    data = pd.DataFrame({"y": [1.0, 2, 3], "x": [1.0, 2, 3]})
    ir = formula_ir("y ~ x", data=data)
    ir["ir_version"] = "0.2.0"
    assert issue_code(design_matrices, ir, data) == "E1441"
    ir["ir_version"] = "0.1.0"
    ir["fixed"]["columns"][0]["term"] = "0"
    assert issue_code(design_matrices, ir, data) == "E1401"
    declaration = {
        "vocabulary": "0.1.0",
        "table": {"fields": [{"name": "y", "type": "number"}, {"name": "x", "type": "number"}]},
    }
    prospective = formula_ir("y ~ x", declaration, coding={"x": {"centring": "mean"}})
    with pytest.raises(ValueError, match="has no constant"):
        design_matrices(prospective, data)
    trials = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
    }
    data = pd.DataFrame({"k": [1.0, 2.0], "n": [3.0, 4.0], "x": [1.0, 2.0]})
    ir = formula_ir("k ~ x", trials, data)
    data["n"] = ["3", "4"]
    with pytest.raises(ValueError, match="does not hold numbers"):
        design_matrices(ir, data)


def test_x_multiplies_centred_values_and_contrasts_from_the_left():
    data = pd.DataFrame(
        {
            "y": [1.0, 2, 3, 4, 5, 6],
            "x": [0.1, 0.2, 0.3, 0.4, 0.5, 0.7],
            "a": ["A1", "A2", "A3", "A1", "A2", "A3"],
        }
    )
    coding = {"x": {"centring": "value", "value": "0.3"}, "a": {"contrast": "simple"}}
    m = design_matrices(formula_ir("y ~ x:a", data=data, coding=coding), data)
    centred = [value - 0.3 for value in data["x"]]
    assert m["x"].flags.f_contiguous
    assert m["x_columns"] == ["(Intercept)", "x:a[A1]", "x:a[A2]", "x:a[A3]"]
    # 'a' is coded by indicators in x:a, since no earlier term holds 'x'.
    indicator = [1.0 if a == "A1" else 0.0 for a in data["a"]]
    assert m["x"][:, 1].tolist() == [c * i for c, i in zip(centred, indicator, strict=True)]
    coding["a"]["frozen"] = True
    m = design_matrices(formula_ir("y ~ x:a", data=data, coding=coding), data)
    simple = [2 / 3 if a == "A2" else -(1 / 3) for a in data["a"]]
    assert m["x_columns"] == ["(Intercept)", "x:a[A2]", "x:a[A3]"]
    assert m["x"][:, 1].tolist() == [c * v for c, v in zip(centred, simple, strict=True)]
    ir = formula_ir("y ~ a:x", data=data, coding={"a": {"contrast": "simple"}})
    assert design_matrices(ir, data)["x_columns"][1] == "a[A1]:x"


def test_formula_ir_and_design_matrices_are_fast_on_10000_rows():
    n = 10000
    rows = np.arange(1, n + 1)
    data = pd.DataFrame(
        {
            "rt": rows / 7,
            "x": np.sin(rows),
            "cond": pd.Series(np.resize(["A", "B", "C"], n), dtype=object),
            "subject": pd.Series([f"s{i % 100 + 1:03d}" for i in range(n)], dtype=object),
            "item": pd.Series([f"i{i // (n // 80) + 1:03d}" for i in range(n)], dtype=object),
        }
    )
    start = time.perf_counter()
    ir = formula_ir(
        "rt ~ cond * x + (1 + cond + x | subject) + (1 + x | item)",
        data=data,
        coding={"x": {"centring": "mean"}},
    )
    m = design_matrices(ir, data)
    elapsed = time.perf_counter() - start
    assert m["z"].shape == (n, 100 * 4 + 80 * 2)
    assert elapsed < 10


def test_the_sequential_rule_is_fast_for_a_factor_of_300_levels():
    # About 0.6 s, and 1 to 2 s on 100,000 rows, where projecting every
    # column onto a basis of n rows took 3 s. The threads of OpenBLAS in the
    # QR compete with other processes, so the test takes about 5 s with a
    # CPU-bound process on every core and 13 s with four other jobs, each
    # running BLAS on four threads, on four cores. The bound is nine times
    # the latter, so that a loaded machine does not fail the test.
    n = 30000
    rows = np.arange(n)
    data = pd.DataFrame(
        {
            "y": np.cos(rows),
            "x": np.sin(rows),
            "f": pd.Series([f"L{i % 300:03d}" for i in range(n)], dtype=object),
        }
    )
    start = time.perf_counter()
    m = design_matrices(formula_ir("y ~ x + f", data=data), data)
    elapsed = time.perf_counter() - start
    assert m["x"].shape == (n, 301)
    assert m["x_dropped"] == []
    assert elapsed < 120


def test_the_sequential_rule_gives_the_same_columns_after_the_reduction_by_qr():
    # The same columns as in the R package's test. Of the 13 columns, 12 are
    # not all 0, so that the columns are reduced by QR on more than 24 rows
    # and used as they are on 24 rows or fewer.
    index = np.arange(1, 201, dtype=np.float64)
    a = np.sin(index)
    b = np.cos(3 * index)
    f = np.array(["A", "B", "C"])[index.astype(np.int64) % 3]
    sign = np.resize([1.0, -1.0], 200)
    x = np.column_stack(
        [
            np.ones(200),
            a,
            np.zeros(200),
            b,
            a + 2 * b,
            f == "A",
            f == "B",
            f == "C",
            (f == "C") * 1e-12,
            a * (f == "A"),
            3 * a - 1,
            b + sign * 1e-6,
            b + sign * 1e-9,
        ]
    ).astype(np.float64)
    expected = [True, True, False, True, False, True, True, False, False, True, False, True, False]
    assert sequential_rule(x) == expected
    assert sequential_rule(x[:25]) == expected
    assert sequential_rule(x[:24]) == expected
    assert sequential_rule(x[:, [0, 1, 4, 3]]) == [True, True, True, False]
    # Relative residuals of 2e-7 and 5e-8 against the columns 1 and a, on 200
    # rows, which are reduced.
    base = np.column_stack([np.ones(200), a])
    e = sign - base @ np.linalg.lstsq(base, sign, rcond=None)[0]
    e = e / math.sqrt(float(e @ e))
    w = a / math.sqrt(float(a @ a))
    assert sequential_rule(np.column_stack([base, w + 2e-7 * e])) == [True, True, True]
    assert sequential_rule(np.column_stack([base, w + 5e-8 * e])) == [True, True, False]


def test_the_sequential_rule_scales_each_column_by_its_largest_value():
    # The sums of squares of these columns overflow or underflow unscaled.
    for x in ([1e160, 2e160, 3.5e160], [1e-170, 2e-170, 3.5e-170]):
        data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "x": x})
        assert design_matrices(formula_ir("y ~ x", data=data), data)["x_dropped"] == []
    data = pd.DataFrame({"y": [1.0, 2.0, 3.0, 4.0], "x": [-1e308] * 4})
    assert design_matrices(formula_ir("y ~ x", data=data), data)["x_dropped"] == ["x"]
    assert sequential_rule(np.array([[1e200], [1.0], [2.0]])) == [True]
    x = np.column_stack([np.ones(3), [1e-200, 1e-170, 2e-200]])
    assert sequential_rule(x) == [True, True]
    # Relative to their size, these two columns differ by about 1e-308.
    x = np.column_stack([[1e308, 1e308, 1.0], [1e308, 1e308, 3.0]])
    assert sequential_rule(x) == [True, False]
    x = np.column_stack([[1e308, 1e308, 1.0], [1e308, -1e308, 3.0]])
    assert sequential_rule(x) == [True, True]
    x = np.column_stack([[1e308, 5e307, 0.0], [2e307, 1e307, 0.0]])
    assert sequential_rule(x) == [True, False]


def test_values_of_x_and_z_that_are_not_finite_are_refused_without_warnings():
    data = pd.DataFrame(
        {
            "y": [1.0, 2.0, 3.0],
            "x": [1e200, 1.0, 2.0],
            "z": [1e200, 3.0, 1.0],
            "g": ["a", "b", "a"],
        },
        dtype=object,
    )
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        ir = formula_ir("y ~ x:z", data=data)
        with pytest.raises(MixedcheckError) as caught:
            design_matrices(ir, data)
        assert caught.value.issues[0]["message"] == "A value computed for 'x:z' is not finite."
        ir = formula_ir("y ~ 1 + (0 + x:z | g)", data=data)
        assert issue_code(design_matrices, ir, data) == "E6077"
        data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "x": [1e308, -1e308, 3.0]}, dtype=object)
        coding = {"x": {"centring": "value", "value": "1" + "0" * 308}}
        ir = formula_ir("y ~ x", data=data, coding=coding)
        assert issue_code(design_matrices, ir, data) == "E6077"


def test_trials_that_are_not_finite_reach_e6073_and_negative_trials_leave():
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
    }
    for bad in (math.nan, math.inf, -math.inf):
        data = pd.DataFrame(
            {
                "k": [1.0, 0.0, 2.0, 1.0, 1.0, 0.0],
                "x": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
                "n": [3.0, 0.0, 4.0, None, bad, -1.0],
            },
            dtype=object,
        )
        ir = formula_ir("k ~ x", declaration, data)
        samples = design_samples(ir, data)
        assert samples["design_sample"].tolist() == [0, 1, 2, 3, 4, 5]
        assert samples["analysis_sample"].tolist() == [0, 2, 4]
        with pytest.raises(MixedcheckError) as caught:
            design_matrices(ir, data)
        assert caught.value.issues[0]["message"] == (
            "The column 'n' holds NaN or an infinity in a row that the model uses."
        )


def test_the_levels_of_a_factor_of_several_variables_escape_their_labels():
    data = pd.DataFrame(
        {"y": [1.0, 2.0, 3.0, 4.0], "g": ["a:b", "a", "a:b", "a\\"], "h": ["c", "b:c", "c", "d"]},
        dtype=object,
    )
    m = design_matrices(formula_ir("y ~ (1 | g:h) + (1 | g)", data=data), data)
    assert m["z_columns"]["level"].tolist() == [
        "a:b\\:c",
        "a\\:b:c",
        "a\\\\:d",
        "a",
        "a:b",
        "a\\",
    ]


def test_design_samples_reports_the_samples_that_the_matrices_refuse():
    data = pd.DataFrame({"y": [1.0, None, 3.0], "x": [1.0, 2.0, math.inf]}, dtype=object)
    ir = formula_ir("y ~ x", data=data)
    assert issue_code(design_matrices, ir, data) == "E6073"
    samples = design_samples(ir, data)
    assert samples["design_sample"].tolist() == [0, 1, 2]
    assert samples["analysis_sample"].tolist() == [0, 2]
    with pytest.raises(TypeError):
        design_samples(ir, data.to_dict())
