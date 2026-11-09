"""Targeted tests of the formula parser and the builder of the IR, for edge
cases that the formula corpus does not cover (docs/spec/ir.md), and of the
rules by which formula_ir() reads a DataFrame."""

from __future__ import annotations

import math
from typing import Any

import numpy as np
import pandas as pd
import pytest

from mixedcheck import (
    MixedcheckError,
    canonical_bytes,
    canonical_hash,
    design_matrices,
    design_samples,
    formula_ir,
    read_json_strict,
)
from mixedcheck._formula_ir import exact_sum
from mixedcheck._schema import schema_issues


def numbers() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "y": [1.0, 2.0, 3.0, 4.0],
            "x": [0.5, 1.0, 1.5, 2.0],
            "z": [2.0, 1.0, 4.0, 3.0],
            "e": [1.0, 2.0, 3.0, 4.0],
            "a": pd.Series(["A1", "A2", "A1", "A2"], dtype=object),
            "g": pd.Series(["g1", "g1", "g2", "g2"], dtype=object),
        }
    )


def issue_of(f, *args: Any, **kwargs: Any) -> dict[str, Any]:
    with pytest.raises(MixedcheckError) as caught:
        f(*args, **kwargs)
    assert len(caught.value.issues) == 1
    return caught.value.issues[0]


def test_a_subtracted_random_term_is_refused():
    issue = issue_of(formula_ir, "y ~ x - (1 | g)", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6014", 8)


def test_an_exponent_that_is_not_a_number_is_named_by_its_first_token():
    issue = issue_of(formula_ir, "y ~ (x + z)^(2)", data=numbers())
    assert issue == {
        "code": "E6006",
        "message": "'(' at byte 12 is not a valid number there. Only 0 and 1 can stand as "
        "terms, and an exponent is an integer from 2 to 1000.",
        "offset": 12,
    }
    assert issue_of(formula_ir, "y ~ (x + z)^1001", data=numbers())["code"] == "E6006"
    assert issue_of(formula_ir, "y ~ x^`k`", data=numbers())["message"].startswith("'`k`'")
    ir = formula_ir("y ~ (x + z)^1000", data=numbers())
    assert [term["name"] for term in ir["fixed"]["terms"]] == ["(Intercept)", "x", "z", "x:z"]


def test_the_end_of_the_input_is_the_number_of_bytes_after_trailing_white_space():
    issue = issue_of(formula_ir, "y ~ x + \t", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6010", 9)
    issue = issue_of(formula_ir, "y ~ `café` +", data=numbers())
    assert issue["offset"] == 13
    issue = issue_of(formula_ir, "y ~ `\U0001f600` + $", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6002", 13)


def test_operators_between_percent_signs_and_lone_percent_signs_are_told_apart():
    issue = issue_of(formula_ir, "y ~ x %% z", data=numbers())
    assert issue["message"] == (
        "The operator '%%' at byte 6 is not supported. Name the columns and use "
        "'+', '-', '*', '/', ':' or '^'."
    )
    issue = issue_of(formula_ir, "y ~ x % in % z", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6002", 6)


def test_parentheses_nest_to_64_levels():
    def deep(levels: int) -> str:
        return "y ~ " + "(" * levels + "x" + ")" * levels

    formula_ir(deep(64), data=numbers())
    issue = issue_of(formula_ir, deep(65), data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6021", 68)
    calls = "y ~ " + "f(" * 65 + "x" + ")" * 65
    assert issue_of(formula_ir, calls, data=numbers())["code"] == "E6021"


def test_long_runs_of_one_operator_need_no_recursion():
    for op in (":", "*", "/"):
        formula = "y ~ " + op.join(["x"] * 4998)
        assert len(formula) == 9999
        ir = formula_ir(formula, data=numbers())
        assert [term["name"] for term in ir["fixed"]["terms"]] == ["(Intercept)", "x"]
    formula = "y ~ x" + " - x + x" * 1000
    assert [term["name"] for term in formula_ir(formula, data=numbers())["fixed"]["terms"]] == [
        "(Intercept)",
        "x",
    ]
    assert issue_of(formula_ir, "y ~ " + "x + " * 2500 + "x")["code"] == "E6001"


def test_log_and_offset_are_allowed_only_where_the_grammar_places_them():
    assert issue_of(formula_ir, "log(y) ~ log(x)", data=numbers())["offset"] == 9
    assert issue_of(formula_ir, "y ~ offset(log(e + z))", data=numbers())["code"] == "E6019"
    assert issue_of(formula_ir, "y ~ x + offset(y)", data=numbers())["code"] == "E6032"
    assert issue_of(formula_ir, "y ~ -offset(e) + x", data=numbers())["code"] == "E6019"
    ir = formula_ir("y ~ +offset(e) + x", data=numbers())
    assert ir["offsets"] == [{"variable": "e", "transform": "identity"}]


def test_an_absent_term_is_named_with_its_variables_in_their_order_in_the_part():
    issue = issue_of(formula_ir, "y ~ z + x - x:z", data=numbers())
    assert issue["message"] == (
        "The term 'z:x' removed at byte 10 is not in the formula at that point."
    )


def test_each_part_evaluates_its_operands_before_the_sign_that_applies_to_them():
    issue = issue_of(formula_ir, "y ~ x + (z - z) - a", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6037", 8)
    issue = issue_of(formula_ir, "y ~ -x + (z - z)", data=numbers())
    assert (issue["code"], issue["offset"]) == ("E6031", 4)


def test_integer_categories_take_integer_references_and_refuse_strings():
    declaration = {
        "vocabulary": "0.1.0",
        "table": {
            "fields": [
                {"name": "y", "type": "number"},
                {"name": "wave", "type": "integer", "categories": [1, 2, 10]},
            ]
        },
    }
    ir = formula_ir("y ~ wave", declaration, coding={"wave": {"reference": 10}})
    assert ir["predictors"]["wave"]["reference"] == 10
    assert type(ir["predictors"]["wave"]["reference"]) is int
    assert [column["name"] for column in ir["fixed"]["columns"]] == [
        "(Intercept)",
        "wave[1]",
        "wave[2]",
    ]
    ir = formula_ir("y ~ wave", declaration, coding={"wave": {"reference": 2.0}})
    assert ir["predictors"]["wave"]["reference"] == 2
    issue = issue_of(formula_ir, "y ~ wave", declaration, coding={"wave": {"reference": "2"}})
    assert issue["message"] == (
        "The reference level '2' of the column 'wave' is not one of its levels."
    )
    assert (
        issue_of(formula_ir, "y ~ wave", declaration, coding={"wave": {"reference": True}})["code"]
        == "E6064"
    )
    issue = issue_of(formula_ir, "y ~ wave", declaration, coding={"wave": {"reference": 1.5}})
    assert issue["code"] == "E6063"


def test_booleans_are_not_numbers_in_the_coding_argument():
    data = numbers()
    coding = {"x": {"centring": "mean", "significant_digits": True}}
    issue = issue_of(formula_ir, "y ~ x", data=data, coding=coding)
    assert issue["code"] == "E6063"
    ir = formula_ir(
        "y ~ x",
        data=data,
        coding={"x": {"centring": "mean", "significant_digits": np.int64(2)}},
    )
    constant = ir["predictors"]["x"]["centring"]["constant"]
    assert constant == {"significant_digits": 2, "value": "1.2"}
    assert issue_of(formula_ir, "y ~ a", data=data, coding={"a": {"frozen": 1}})["code"] == "E6063"


def test_a_mean_centring_constant_needs_finite_values_in_the_design_sample():
    data = numbers()
    data.loc[1, "x"] = math.nan
    issue = issue_of(formula_ir, "y ~ x", data=data, coding={"x": {"centring": "mean"}})
    assert issue == {
        "code": "E6073",
        "message": "The column 'x' holds NaN or an infinity in a row that the model uses.",
    }
    ir = formula_ir("y ~ x + z", data=data, coding={"z": {"centring": "mean"}})
    assert ir["predictors"]["z"]["centring"]["constant"]["value"] == "2.5"
    assert issue_of(design_matrices, ir, data)["code"] == "E6073"


def test_the_exact_sum_rounds_once_and_survives_intermediate_overflow():
    assert exact_sum([1e100, 1.0, -1e100]) == 1.0
    assert exact_sum([0.1] * 10) == 1.0
    assert exact_sum([5e-324, 5e-324]) == 1e-323
    assert exact_sum([1.0, 2.0**-53, 2.0**-105]) == 1 + 2.0**-52
    assert exact_sum([]) == 0.0
    big = 1.7e308
    assert exact_sum([big, big, -big]) == big
    assert exact_sum([big, big]) == math.inf
    assert exact_sum([-big, -big]) == -math.inf
    data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "x": [big, big, -big]})
    ir = formula_ir("y ~ x", data=data, coding={"x": {"centring": "mean"}})
    assert ir["predictors"]["x"]["centring"]["constant"]["value"] == "5666670" + "0" * 301
    data = pd.DataFrame({"y": [1.0, 2.0], "x": [big, big]})
    with pytest.raises(MixedcheckError) as caught:
        formula_ir("y ~ x", data=data, coding={"x": {"centring": "mean"}})
    assert caught.value.issues[0]["code"] == "E6077"


def test_only_none_and_pandas_na_are_missing_and_nan_is_a_value():
    data = numbers()
    data.loc[0, "x"] = math.nan
    data.loc[1, "a"] = ""
    data.loc[2, "g"] = None
    ir = formula_ir("y ~ a + (1 | g)", data=data)
    assert ir["predictors"]["a"]["levels"] == ["", "A1", "A2"]
    design = design_samples(formula_ir("y ~ x + a", data=data), data)["design_sample"]
    assert design.tolist() == [0, 1, 2, 3]
    design = design_samples(ir, data)["design_sample"]
    assert design.tolist() == [0, 1, 3]
    data["n"] = pd.array([1.0, None, 3.0, 4.0], dtype="Float64")
    design = design_samples(formula_ir("y ~ n", data=data), data)["design_sample"]
    assert design.tolist() == [0, 2, 3]
    # The string dtype that is the default of pandas 3 marks a missing string
    # with NaN.
    data["s"] = pd.Series(["p", None, "q", math.nan], dtype=pd.StringDtype(na_value=math.nan))
    ir = formula_ir("y ~ s", data=data)
    assert ir["predictors"]["s"]["levels"] == ["p", "q"]
    assert design_samples(ir, data)["design_sample"].tolist() == [0, 2]


def test_categoricals_give_their_labels_whatever_the_order_of_their_categories():
    data = numbers()
    data["a"] = pd.Categorical(data["a"], categories=["A2", "A1", "unused"])
    ir = formula_ir("y ~ a", data=data)
    assert ir["predictors"]["a"]["levels"] == ["A1", "A2"]
    assert ir["predictors"]["a"]["levels_source"] == "table"
    # R reads factor(c(2, 1, 2, NA)) by its labels '1' and '2', so a
    # categorical of numbers is refused and one of their labels is read as R
    # reads the factor.
    data["w"] = pd.Categorical([2, 1, 2, None])
    with pytest.raises(ValueError, match="categories that are not strings"):
        formula_ir("y ~ w", data=data)
    with pytest.raises(ValueError, match="categories that are not strings"):
        design_samples(formula_ir("y ~ x", data=numbers()), data)
    data["w"] = pd.Categorical(["2", "1", "2", None])
    predictor = formula_ir("y ~ w", data=data)["predictors"]["w"]
    assert (predictor["kind"], predictor["levels"]) == ("categorical", ["1", "2"])
    assert predictor["levels_source"] == "table"
    # A categorical whose values are all missing is a string column, as a
    # factor of NA is in R, whatever attrs["types"] says.
    data["m"] = pd.Categorical([None] * 4, categories=["p"])
    data.attrs["types"] = {"m": "number"}
    assert issue_of(formula_ir, "y ~ m", data=data)["code"] == "E6056"
    data["i"] = np.arange(4, dtype=np.int32)
    assert formula_ir("y ~ i", data=data)["predictors"]["i"]["kind"] == "numeric"
    data["b"] = [True, False, True, False]
    assert formula_ir("y ~ b", data=data)["predictors"]["b"]["levels"] == [False, True]


def test_columns_of_only_missing_values_take_a_declared_or_read_type():
    data = pd.DataFrame({"y": [1.0, 2.0], "m": pd.Series([None, None], dtype=object)})
    # Without a declared or read type, a boolean column, as a logical column
    # of NA is in R.
    assert formula_ir("y ~ m", data=data)["predictors"]["m"]["levels"] == [False, True]
    data.attrs["types"] = {"y": "number", "m": "number"}
    ir = formula_ir("y ~ m", data=data)
    assert ir["predictors"]["m"]["kind"] == "numeric"
    data.attrs["types"] = {"y": "number", "m": "string"}
    assert issue_of(formula_ir, "y ~ m", data=data)["code"] == "E6056"
    declaration = {
        "vocabulary": "0.1.0",
        "table": {"fields": [{"name": "y", "type": "number"}, {"name": "m", "type": "integer"}]},
    }
    assert formula_ir("y ~ m", declaration, data)["predictors"]["m"]["kind"] == "numeric"


def test_data_must_agree_with_the_declared_types_and_have_distinct_names():
    declaration = {
        "vocabulary": "0.1.0",
        "table": {"fields": [{"name": "y", "type": "number"}, {"name": "x", "type": "string"}]},
    }
    data = pd.DataFrame({"y": [1.0, 2.0], "x": [3.0, 4.0]})
    with pytest.raises(ValueError, match="declares the type 'string'") as caught:
        formula_ir("y ~ x", declaration, data)
    assert not isinstance(caught.value, MixedcheckError)
    data["x"] = pd.Series([None, None], dtype=object)
    with pytest.raises(MixedcheckError):
        formula_ir("y ~ x", declaration, data)
    data = pd.DataFrame([[1.0, 2.0]], columns=["café", "café"])
    with pytest.raises(ValueError, match="after NFC normalisation"):
        formula_ir("~ 1", data=data)
    data = pd.DataFrame({"y": [1.0], "x": pd.to_datetime(["2026-01-01"])})
    with pytest.raises(ValueError, match="not a column of numbers"):
        formula_ir("y ~ x", data=data)
    data = pd.DataFrame({"y": [1.0, 2.0], "x": pd.Series(["a", 1], dtype=object)})
    with pytest.raises(ValueError, match="not a column of numbers"):
        formula_ir("y ~ x", data=data)
    data = pd.DataFrame({"y": [1.0, 2.0], "x": pd.Series(["a", math.nan], dtype=object)})
    with pytest.raises(ValueError, match="not a column of numbers"):
        formula_ir("y ~ x", data=data)
    with pytest.raises(ValueError, match="valid column name"):
        formula_ir("~ 1", data=pd.DataFrame({"a\tb": [1.0]}))
    with pytest.raises(ValueError, match="names that are str"):
        formula_ir("~ 1", data=pd.DataFrame({0: [1.0]}))
    with pytest.raises(TypeError, match="'formula' must be a str"):
        formula_ir(b"y ~ x")  # type: ignore[arg-type]
    with pytest.raises(TypeError, match="'coding' must be"):
        formula_ir("y ~ x", data=numbers(), coding={"x": "mean"})  # type: ignore[dict-item]
    with pytest.raises(TypeError, match="'sample_columns' must be"):
        formula_ir("y ~ x", data=numbers(), sample_columns="x")
    with pytest.raises(TypeError, match="'data' must be"):
        formula_ir("y ~ x", data={"y": [1.0]})  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="names the column 'caf"):
        formula_ir("y ~ x", data=numbers(), coding={"café": {}, "café": {}})


def test_strings_with_a_surrogate_code_point_are_refused_at_their_pointer():
    assert issue_of(formula_ir, "y ~ \udce9")["pointer"] == "/formula"
    assert issue_of(formula_ir, "y ~ x", weights="w\udce9")["pointer"] == "/weights"
    assert issue_of(formula_ir, "y ~ x", sample_columns=["s", "\udce9"])["pointer"] == (
        "/sample_columns/1"
    )
    issue = issue_of(formula_ir, "y ~ x", coding={"x": {"value": "\udce9"}})
    assert issue == {
        "code": "E1206",
        "message": "The string at /coding/x/value contains a surrogate code point.",
        "pointer": "/coding/x/value",
    }
    data = numbers()
    data["a"] = pd.Series(["A1", "A2", "\udce9", None], dtype=object)
    assert issue_of(formula_ir, "y ~ x", data=data)["pointer"] == "/data/a/2"


def test_a_declaration_without_data_supplies_the_columns_and_their_kinds():
    declaration = {
        "vocabulary": "0.1.0",
        "table": {
            "fields": [
                {"name": "y", "type": "number"},
                {"name": "flag", "type": "boolean"},
                {"name": "x", "type": "number"},
            ]
        },
    }
    ir = formula_ir("y ~ flag + x", declaration, coding={"x": {"centring": "mean"}})
    assert ir["predictors"]["flag"]["levels"] == [False, True]
    assert ir["predictors"]["x"]["centring"] == {
        "rule": "mean",
        "sample": "design",
        "significant_digits": 6,
    }
    assert issue_of(formula_ir, "y ~ x")["code"] == "E6051"


def test_the_trials_column_the_weights_and_the_sample_columns_are_checked_in_order():
    declaration = {
        "vocabulary": "0.1.0",
        "variables": {"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}},
    }
    data = pd.DataFrame({"k": [1.0, 2.0], "n": ["a", "b"], "x": [1.0, 2.0], "w": ["u", "v"]})
    issue = issue_of(formula_ir, "k ~ x", declaration, data, weights="w", sample_columns=["s"])
    assert issue["code"] == "E6065"
    data["n"] = [3.0, 4.0]
    issue = issue_of(formula_ir, "k ~ x", declaration, data, weights="w", sample_columns=["s"])
    assert issue["code"] == "E6066"
    data["w"] = [1.0, 2.0]
    issue = issue_of(
        formula_ir, "k ~ x", declaration, data, weights="w", sample_columns=["x", "s", "t"]
    )
    assert issue["message"] == (
        "The sample column 's' is not in the data, or in the declared table when there are no data."
    )


def test_sample_columns_that_the_ir_reads_are_left_out_and_the_rest_sorted():
    data = numbers()
    data["b"] = ["p", "q", "p", "q"]
    ir = formula_ir("y ~ x", data=data, weights="e", sample_columns=["z", "b", "e", "y", "x"])
    assert ir["sample_columns"] == ["b", "z"]
    assert ir["weights"] == {"variable": "e"}


def test_frozen_factors_split_only_under_double_bars_and_keep_their_contrast():
    data = pd.DataFrame(
        {
            "y": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            "a": ["A1", "A2", "A3"] * 2,
            "g": ["g1", "g2"] * 3,
            "b": ["B1"] * 3 + ["B2"] * 3,
        }
    )
    coding = {"a": {"frozen": True, "contrast": "sum"}, "b": {"frozen": True}}
    ir = formula_ir("y ~ a * b + (0 + a:b || g)", data=data, coding=coding)
    assert [term["name"] for term in ir["random"]] == ["0 + a[A2]:b[B2] | g", "0 + a[A3]:b[B2] | g"]
    assert ir["random"][0]["terms"][0]["variables"] == [
        {"variable": "a", "coding": "contrast", "level": "A2"},
        {"variable": "b", "coding": "contrast", "level": "B2"},
    ]
    ir = formula_ir("y ~ (0 + a | g)", data=data, coding={"a": coding["a"]})
    assert [column["name"] for column in ir["random"][0]["columns"]] == ["a[A2]", "a[A3]"]


def test_the_ir_passes_the_schema_and_holds_python_values():
    ir = formula_ir(
        "y ~ x * a + offset(log(e)) + (1 + x | g)",
        data=numbers(),
        coding={"x": {"centring": "value", "value": "1.25"}},
    )
    assert (
        schema_issues(
            read_json_strict(canonical_bytes(ir, "hashable"), "hashable"),
            "urn:mixedcheck:schema:ir",
        )
        == []
    )
    assert ir["predictors"]["x"]["centring"]["constant"] == {
        "significant_digits": 3,
        "value": "1.25",
    }
    assert all(type(column["term"]) is int for column in ir["fixed"]["columns"])
    # The IR equals the value that the strict reader returns for its bytes.
    assert read_json_strict(canonical_bytes(ir, "hashable"), "hashable") == ir
    assert canonical_hash(ir, "hashable").startswith("sha256:")


def test_names_outside_ascii_are_compared_after_nfc():
    data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "café": ["x́", "ý", "z"]})
    ir = formula_ir("y ~ `café`", data=data)
    assert list(ir["predictors"]) == ["café"]
    assert ir["predictors"]["café"]["levels"] == ["x́", "z", "ý"]
    assert [term["name"] for term in ir["fixed"]["terms"]] == ["(Intercept)", "`café`"]


def test_the_response_as_a_sample_column_changes_no_centring_constant():
    data = pd.DataFrame({"y": [None, 2.0, 3.0], "x": [10.0, 0.2, 0.3]}, dtype=object)
    coding = {"x": {"centring": "mean"}}
    ir = formula_ir("y ~ x", data=data, coding=coding, sample_columns=["y"])
    assert "sample_columns" not in ir
    assert ir["predictors"]["x"]["centring"]["constant"]["value"] == "3.5"
    assert ir == formula_ir("y ~ x", data=data, coding=coding)


def test_a_list_of_terms_holds_at_most_10000_terms():
    names = [f"x{i}" for i in range(1, 15)]
    formula = "y ~ " + "*".join(names[:13])
    assert len(formula_ir(formula, declaration=numeric_declaration(names[:13]))["fixed"]["terms"])
    formula = "y ~ " + "*".join(names)
    issue = issue_of(formula_ir, formula)
    assert (issue["code"], issue["offset"]) == ("E6038", formula.rindex("*"))
    power = "y ~ (" + " + ".join(f"x{i}" for i in range(1, 17)) + ")^4"
    issue = issue_of(formula_ir, power)
    assert (issue["code"], issue["offset"]) == ("E6038", power.index("^"))
    first = "(" + "*".join(f"a{i}" for i in range(13)) + ")"
    second = "(" + "*".join(f"b{i}" for i in range(13)) + ")"
    issue = issue_of(formula_ir, f"y ~ {first} + {second}")
    assert (issue["code"], issue["offset"]) == ("E6038", len(f"y ~ {first} "))


def numeric_declaration(names: list[str]) -> dict[str, Any]:
    fields = [{"name": name, "type": "number"} for name in ["y", *names]]
    return {"vocabulary": "0.1.0", "table": {"fields": fields}}


def test_a_part_has_at_most_10000_columns_and_a_name_at_most_10000_characters():
    labels = [f"l{i:02d}" for i in range(22)]
    data = pd.DataFrame({"y": [1.0] * 22, "a": labels, "b": labels, "c": labels}, dtype=object)
    issue = issue_of(formula_ir, "y ~ a:b:c", data=data)
    assert (issue["code"], issue["message"]) == (
        "E6075",
        "The fixed part would have more than 10000 columns.",
    )
    issue = issue_of(formula_ir, "y ~ (0 + a:b:c | g)", data=data.assign(g=labels))
    assert issue["code"] == "E6075"
    assert issue["message"].startswith("The random term '0 + a:b:c | g' would have")
    names = list("abcdefhijk")
    long = "y ~ (" + "*".join(names) + " | g)"
    declaration = numeric_declaration(names)
    declaration["table"]["fields"].append({"name": "g", "type": "string"})
    issue = issue_of(formula_ir, long, declaration)
    assert issue["code"] == "E6076"
    assert issue["message"].startswith("The name '1 + a + b + c + d")
    data = pd.DataFrame({"y": [1.0, 2.0], "a": ["x" * 9997, "short"]}, dtype=object)
    assert len(formula_ir("y ~ a", data=data)["fixed"]["columns"][1]["name"]) == 10000
    data = pd.DataFrame({"y": [1.0, 2.0], "a": ["x" * 9998, "short"]}, dtype=object)
    assert issue_of(formula_ir, "y ~ a", data=data)["code"] == "E6076"


def test_a_level_that_the_ir_cannot_hold_is_refused_at_its_first_appearance():
    for label in ["line\nbreak", "x\U0001e4ec", "tab\t", "\x85"]:
        data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "c": ["a", label, "a"]}, dtype=object)
        issue = issue_of(formula_ir, "y ~ x + c", data=data.assign(x=[1.0, 2.0, 3.0]))
        assert (issue["code"], issue["offset"]) == ("E6074", 8)
    data = pd.DataFrame({"y": [1.0, 2.0], "c": ["é", "é"]}, dtype=object)
    assert issue_of(formula_ir, "y ~ c", data=data)["code"] == "E6056"


def test_centring_constants_that_are_not_finite_are_refused():
    big = 1.7e308
    data = pd.DataFrame({"y": [1.0, 2.0], "x": [big, big]}, dtype=object)
    issue = issue_of(formula_ir, "y ~ x", data=data, coding={"x": {"centring": "mean"}})
    assert (issue["code"], issue["message"]) == (
        "E6077",
        "A value computed for 'x' is not finite.",
    )
    # The mean 1.79e308 rounds to '2e308' with one significant digit.
    coding = {"x": {"centring": "mean", "significant_digits": 1}}
    data = pd.DataFrame({"y": [1.0, 2.0, 3.0], "x": [1.79e308, 1.79e308, 1.79e308]}, dtype=object)
    assert issue_of(formula_ir, "y ~ x", data=data, coding=coding)["code"] == "E6077"
    huge = "1" + "0" * 309
    coding = {"x": {"centring": "value", "value": huge}}
    assert issue_of(formula_ir, "y ~ x", numeric_declaration(["x"]), coding=coding)["code"] == (
        "E6077"
    )


def test_integral_numbers_count_as_integers_in_the_coding_argument():
    data = numbers()
    ir = formula_ir(
        "y ~ x", data=data, coding={"x": {"centring": "mean", "significant_digits": 2.0}}
    )
    assert ir["predictors"]["x"]["centring"]["constant"]["significant_digits"] == 2
    assert isinstance(ir["predictors"]["x"]["centring"]["constant"]["significant_digits"], int)
    issue = issue_of(
        formula_ir,
        "y ~ x",
        data=data,
        coding={"x": {"centring": "mean", "significant_digits": 2.5}},
    )
    assert issue["code"] == "E6063"
