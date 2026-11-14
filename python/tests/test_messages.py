"""The rendering of messages (registry.md, Messages): every kind of argument,
templates and fallbacks, and the rendering of reals, compared with the vectors
of the number corpus.

numbers/message_reals.txt.xz holds doubles, as the 16 hexadecimal digits of
their bits, each with its renderings with 0 to 6 digits, which
fixtures/conformance/tools/make_message_reals.py writes with Python's format()
and checks against exact rounding (fixtures/conformance/numbers/README.md).
The tests of the R package read the same vectors.
"""

from __future__ import annotations

import lzma
import math
import sys
from typing import Any

import pytest
from corpus_helpers import bits_double, corpus_directory

from mixedcheck._messages import (
    names_text,
    percent_text,
    ratio_text,
    real_text,
    render_message,
)
from mixedcheck._registry import registry_entry


def message_real_vectors() -> list[tuple[float, list[str]]]:
    path = corpus_directory("numbers") / "message_reals.txt.xz"
    with lzma.open(path, "rt", encoding="utf-8") as handle:
        rows = [line.rstrip("\n").split("\t") for line in handle]
    return [(bits_double(row[0]), row[1:]) for row in rows]


def test_reals_are_rendered_as_the_vectors_of_the_number_corpus_give_them() -> None:
    vectors = message_real_vectors()
    assert len(vectors) > 20000
    wrong = [
        (x, d, real_text(x, d), texts[d])
        for x, texts in vectors
        for d in range(7)
        if real_text(x, d) != texts[d]
    ]
    assert wrong == []


def test_the_notation_changes_at_1e15_by_the_double_before_rounding() -> None:
    below = 1e15 - 0.125
    assert real_text(below, 0) == "1000000000000000"
    assert real_text(below, 2) == "999999999999999.88"
    assert real_text(1e15, 0) == "1e+15"
    assert real_text(1e15, 2) == "1.00e+15"
    assert real_text(-1e15, 1) == "-1.0e+15"
    assert real_text(2.5e20, 0) == "2e+20"
    assert real_text(3.5e20, 0) == "4e+20"
    assert real_text(9.5e15, 0) == "1e+16"
    assert real_text(2.0**60, 2) == "1.15e+18"
    assert real_text(1e100, 3) == "1.000e+100"
    assert real_text(sys.float_info.max, 6) == "1.797693e+308"
    assert real_text(-0.04, 1) == "0.0"
    assert real_text(math.inf, 2) == "Infinity"
    assert real_text(-math.inf, 0) == "-Infinity"
    assert real_text(math.nan, 1) == "NaN"


def test_a_positive_real_whose_rounding_has_only_zeros_renders_as_under() -> None:
    # The double nearest to 0.05 lies above it, and the double before it below.
    below = 0.05 - 2.0**-57
    assert below < 0.05 and below + 2.0**-57 == 0.05
    assert real_text(0.05, 1) == "0.1"
    assert real_text(below, 1) == "under 0.1"
    assert [real_text(below, d) for d in range(3)] == ["under 1", "under 0.1", "0.05"]
    assert real_text(1 / 21, 1) == "under 0.1"
    # 0.5 is a tie, which rounds half to even to 0, and the double after it
    # rounds up.
    assert real_text(0.5, 0) == "under 1"
    assert real_text(0.5 + 2.0**-53, 0) == "1"
    assert real_text(1.5, 0) == "2"
    assert real_text(0.0625, 3) == "0.062"
    # Subnormal doubles, the smallest of them included.
    assert [real_text(2.0**-1074, d) for d in range(7)] == ["under 1"] + [
        "under 0." + "0" * k + "1" for k in range(6)
    ]
    assert real_text(2.0**-1022 - 2.0**-1074, 6) == "under 0.000001"
    # Zero and negative values keep their fixed rendering.
    assert real_text(0.0, 1) == "0.0"
    assert real_text(-0.0, 2) == "0.00"
    assert [real_text(-(2.0**-1074), d) for d in range(2)] == ["0", "0.0"]
    assert real_text(-below, 1) == "0.0"
    assert real_text(-0.5, 0) == "0"
    entry = registry_entry("outcome.minority_events")
    values = {"events": 1, "non_events": 20, "events_per_column": 1 / 21}
    assert render_message(entry, "events_model", {}, values) == (
        "The outcome has 1 event and 20 non-events, or under 0.1 minority events per "
        "fixed-effects column."
    )


def test_messages_render_every_kind_of_argument_as_registry_md_describes() -> None:
    assert real_text(0.125, 2) == "0.12"
    assert real_text(0.375, 2) == "0.38"
    assert real_text(2.5, 0) == "2"
    assert real_text(3.5, 0) == "4"
    assert real_text(-0.06, 1) == "-0.1"
    assert real_text(1234.5678, 2) == "1234.57"
    assert real_text(1e-30, 3) == "under 0.001"
    assert real_text(1e21, 1) == "1.0e+21"
    assert real_text(0.005, 2) == "0.01"
    assert ratio_text(23, 40, 0) == "58%"
    assert ratio_text(23, 80, 1) == "28.8%"
    assert ratio_text(1, 8, 0) == "12%"
    assert ratio_text(3, 8, 0) == "38%"
    assert ratio_text(0, 7, 1) == "0.0%"
    assert ratio_text(7, 7, 0) == "100%"
    assert ratio_text(2**60 + 1, 2**61, 2) == "50.00%"
    assert percent_text("0.15") == "15%"
    assert percent_text("0.125") == "12.5%"
    assert percent_text("1") == "100%"
    assert percent_text("0") == "0%"
    assert percent_text("0.0005") == "0.05%"
    assert names_text([]) == "none"
    assert names_text(["a"]) == "'a'"
    assert names_text(["a", "b\tc", "d"]) == "'a', 'b\\u0009c' and 'd'"
    entry = registry_entry("keys.duplicates")
    values: dict[str, Any] = {"key_columns": ["id"], "identical_keys": 1, "duplicate_rows": 1}
    assert render_message(entry, "double_import", {}, values) == (
        "Values of the observation key 'id' shared by identical rows: 1, with 1 row in all, "
        "which suggests rows imported twice. Remove the copies at the source."
    )
    values["duplicate_rows"] = 2
    assert "with 2 rows in all" in render_message(entry, "double_import", {}, values)
    # A statistic that is not written gives the fallback.
    assert render_message(entry, "double_import", {}, values, written=["key_columns"]) == (
        "Some values of the observation key 'id' are shared by identical rows, which suggests "
        "rows imported twice. Remove the copies at the source."
    )
    entry = registry_entry("outcome.boundary_shares")
    values = {
        "rows": 40,
        "at_floor": 1,
        "at_ceiling": 23,
        "floor_share": 1 / 40,
        "ceiling_share": 23 / 40,
    }
    text = render_message(entry, "at_bounds", {}, values)
    assert "57.5%" in text and "15%" in text
    # A scope part after display escaping, a threshold as written and reals.
    entry = registry_entry("design.collinearity")
    values = {"df": 1, "gvif": 2.5, "gvif_per_df": 2.5}
    assert render_message(entry, "low", {"term": "a\tb"}, values) == (
        "'a\\u0009b' has a generalised variance inflation factor of 2.50, or 2.50 per degree "
        "of freedom, below 5."
    )
    entry = registry_entry("identifiability.gram_rank")
    with pytest.raises(RuntimeError, match="Internal error"):
        render_message(entry, "no_such_message", {}, {})


def test_the_message_of_design_scale_disparity_renders_a_large_ratio_in_scientific_notation() -> (
    None
):
    entry = registry_entry("design.scale_disparity")
    values = {
        "scaled_columns": ["x1", "x2"],
        "sd_largest": 1e299,
        "sd_smallest": 1.0,
        "sd_ratio": 1e299,
        "condition_number": 1.0,
    }
    assert "differ by a factor of 1e+299, or one" in render_message(entry, "disparate", {}, values)


def test_a_scope_part_and_a_category_render_as_registry_md_describes() -> None:
    entry = registry_entry("structure.id_scope_evidence")
    message = entry["messages"]["some_change"]
    values = {
        "changing_labels": 3,
        "shared_labels": 40,
        "labels_column": ["class"],
        "context_column": ["school"],
        "changing_attribute": ["teacher_sex"],
    }
    text = render_message(entry, "some_change", {"first": "class", "second": "school"}, values)
    assert text == (
        "'class' has 40 labels occurring with several levels of 'school', and the attribute "
        "'teacher_sex' changes between those levels for 3 of them. Check these units and "
        "declare the scope of the labels."
    ), message
