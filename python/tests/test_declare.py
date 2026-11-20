"""declaration(), the declare_*() builders and draft_design() (02-decisions.md,
Q4, and docs/spec/declarations.md)."""

from __future__ import annotations

import itertools

import pandas as pd
import pytest

from mixedcheck import (
    MixedcheckError,
    canonical_bytes,
    canonical_hash,
    declaration,
    declare_assignment,
    declare_estimand,
    declare_observation,
    declare_unit,
    declare_variable,
    draft_design,
    validate_declaration,
)


def test_builders_write_the_json_of_a_declaration() -> None:
    built = declaration(
        units=[
            declare_unit("school", ["school"], role="cluster"),
            declare_unit(
                "pupil", ["pupil"], nested_in="school", id_scope="global", role="participant"
            ),
        ],
        observation=declare_observation(
            key=["pupil"],
            unit="pupil",
            time_column="wave",
            time_kind="occasion",
            time_within="pupil",
        ),
        assignment=[declare_assignment("arm", "school", randomised=True, level="between_unit")],
        variables={
            "score": declare_variable("outcome", measurement="bounded_score", bounds=[0, 40]),
            "arm": declare_variable("assigned"),
        },
        estimands=[declare_estimand("itt", "arm", kind="total_effect", focal=True)],
        features=["cluster_randomised", "longitudinal"],
        title="Tutoring trial",
    )
    text = (
        '{"assignment":[{"column":"arm","level":"between_unit","randomised":true,"unit":"school"}],'
        '"estimands":[{"focal":true,"id":"itt","kind":"total_effect","term":"arm"}],'
        '"features":["cluster_randomised","longitudinal"],'
        '"observation":{"key":["pupil"],"time":{"column":"wave","kind":"occasion","within":"pupil"},'
        '"unit":"pupil"},"title":"Tutoring trial",'
        '"units":[{"columns":["school"],"name":"school","role":"cluster"},'
        '{"columns":["pupil"],"id_scope":"global","name":"pupil","nested_in":"school",'
        '"role":"participant"}],'
        '"variables":{"arm":{"role":"assigned"},"score":{"bounds":[0,40],'
        '"measurement":"bounded_score","role":"outcome"}},"vocabulary":"0.1.0"}'
    )
    assert canonical_bytes(built, "hashable").decode("utf-8") == text
    # The hash that the R package's tests record for the same declaration.
    assert canonical_hash(built, "hashable") == (
        "sha256:51dad8b2dd49cbc777ebc73b908a60d87d8b6e60f12f64053c6eca5c5a694ef9"
    )


def test_builders_check_arguments_and_declaration() -> None:
    with pytest.raises(TypeError, match="'columns'"):
        declare_unit("school", "school")
    with pytest.raises(TypeError, match="'randomised'"):
        declare_assignment("arm", "school", randomised="yes")  # type: ignore[arg-type]
    with pytest.raises(TypeError, match="'bounds'"):
        declare_variable("outcome", bounds=[1])
    with pytest.raises(MixedcheckError) as raised:
        declaration(units=[declare_unit("pupil", ["pupil"], nested_in="class", id_scope="global")])
    assert raised.value.issues[0]["code"] == "E2006"
    with pytest.raises(MixedcheckError) as raised:
        declaration(units=[declare_unit("pupil", ["pupil"])], minimal=True)
    assert raised.value.issues[0]["code"] == "E2028"


def test_draft_marks_every_inferred_entry(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")
    data = pd.DataFrame(
        {
            "school": ["A"] * 6 + ["B"] * 6,
            "class": ["1", "2", "3"] * 4,
            "pupil": [f"p{k:02d}" for k in range(1, 13)],
            "x": [float(k) for k in range(1, 13)],
            "y": [float("nan")] * 12,
        }
    )
    draft = draft_design(data, "y ~ x + (1 | school/class) + (1 | pupil)")
    assert [u["name"] for u in draft["units"]] == ["school", "class", "pupil"]
    assert "nested_in" not in draft["units"][1]
    assert draft["crossings"] == [{"units": ["school", "class"]}]
    assert draft["units"][2]["nested_in"] == "class"
    assert draft["units"][2]["id_scope"] == "global"
    assert draft["observation"]["key"] == ["pupil"]
    assert draft["variables"]["y"] == {"role": "outcome"}
    assert draft["provenance"]["inferred"] == [
        "/units/0",
        "/units/1",
        "/units/2",
        "/crossings/0",
        "/observation/key",
        "/variables/y",
    ]
    assert draft["provenance"]["created"] == "1970-01-01T00:00:00Z"
    with pytest.raises(MixedcheckError) as raised:
        validate_declaration(draft, minimal=True)
    assert "E2032" in [i["code"] for i in raised.value.issues]


def test_draft_makes_no_unit_of_a_predictor() -> None:
    data = pd.DataFrame([{"f": f, "g": f"g{k}"} for k in range(1, 5) for f in "abc"])
    data["y"] = float("nan")
    draft = draft_design(data, "y ~ f + (1 | g) + (1 | g:f)")
    assert [u["name"] for u in draft["units"]] == ["g"]


def test_draft_finds_crossed_units() -> None:
    data = pd.DataFrame(
        [{"subject": s, "item": i} for i, s in itertools.product(["i1", "i2"], ["s1", "s2", "s3"])]
    )
    data["y"] = float("nan")
    draft = draft_design(data, "y ~ 1 + (1 | subject) + (1 | item)")
    assert draft["crossings"] == [{"units": ["subject", "item"]}]
    assert draft["observation"]["key"] == ["subject", "item"]
