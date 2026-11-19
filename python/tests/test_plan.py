"""design_plan(), validate_plan(), preregistration_text() and audit() bound to
a plan (docs/spec/documents.md, Plan, version 0.1, and Access log)."""

from __future__ import annotations

import copy
import itertools
from typing import Any

import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

import mixedcheck
from mixedcheck import (
    MixedcheckError,
    _plan,
    audit,
    canonical_hash,
    declaration,
    declare_assignment,
    declare_crossing,
    declare_estimand,
    declare_observation,
    declare_unit,
    declare_variable,
    design_plan,
    pathology_zoo,
    preregistration_text,
    validate_plan,
    validate_results,
)


@pytest.fixture(autouse=True)
def time_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def issue(*args: Any, **kwargs: Any) -> dict[str, Any]:
    with pytest.raises(MixedcheckError) as raised:
        design_plan(*args, **kwargs)
    return raised.value.issues[0]


def crossed_data() -> pd.DataFrame:
    """Subjects crossed with items, a focal condition of two levels within
    both, a covariate that varies between items, a factor of three levels
    within subjects and a second row of every cell."""
    rows = []
    items = [f"i{k:02d}" for k in range(1, 9)]
    subjects = [f"s{k:02d}" for k in range(1, 13)]
    for rep, (s, subject), (i, item) in itertools.product(
        (1, 2), enumerate(subjects, 1), enumerate(items, 1)
    ):
        rows.append(
            {
                "item": item,
                "subject": subject,
                "rep": float(rep),
                "cond": "a" if (i + rep) % 2 == 0 else "b",
                "freq": i / 4,
                "block": ["x", "y", "z"][(s + rep + i) % 3],
                "rt": None,
            }
        )
    frame = pd.DataFrame(rows)
    frame["rt"] = frame["rt"].astype(float)
    return frame


def crossed_declaration(estimands: bool = True) -> Any:
    return declaration(
        units=[
            declare_unit("subject", ["subject"], role="participant"),
            declare_unit("item", ["item"], role="item"),
        ],
        crossings=[declare_crossing(["subject", "item"])],
        observation=declare_observation(key=["subject", "item", "rep"]),
        variables={
            "rt": declare_variable("outcome", measurement="continuous"),
            "cond": declare_variable("assigned"),
        },
        estimands=[declare_estimand("cond", "cond", kind="total_effect")] if estimands else None,
        features=["crossed_experiment"],
    )


FORMULA = "rt ~ cond + freq + (1 | subject) + (1 | item)"


def names(ir: dict[str, Any]) -> list[str]:
    return [t["name"] for t in ir["random"]]


def test_protected_plan() -> None:
    plan = design_plan(crossed_data(), FORMULA, crossed_declaration())
    assert validate_plan(plan) is plan
    assert plan["created"] == "1970-01-01T00:00:00Z"
    assert plan["design"]["ladder"] == "protected"
    assert plan["rule_evidence"] == "simulated_conditions_only"
    assert plan["for_preregistration"] is False
    assert plan["design_plan_hash"] == canonical_hash(plan["design"], "hashable")
    assert plan["design"]["declaration_hash"] == canonical_hash(crossed_declaration(), "hashable")
    assert names(plan["ceiling"]["ir"]) == ["1 + cond + freq | subject", "1 + cond | item"]
    steps = [r["step"]["kind"] for r in plan["design"]["rungs"][1:]]
    assert steps == ["decorrelate", "decorrelate", "drop_terms"]
    assert names(plan["design"]["rungs"][-1]["ir"]) == [
        "1 | subject",
        "0 + cond | subject",
        "1 | item",
        "0 + cond | item",
    ]
    reasons = [c["reason"] for c in plan["design"]["protected"]]
    assert reasons == ["replication_unit", "replication_unit", "focal_slope", "focal_slope"]
    assert len(plan["verdicts"]) == len(plan["design"]["rungs"])


def test_rungs_and_exploratory_ladder() -> None:
    plan = design_plan(crossed_data(), FORMULA, crossed_declaration())
    for rung in plan["design"]["rungs"]:
        assert rung["ir"]["predictors"]["cond"]["frozen"] is True
        assert "sample_columns" not in rung["ir"]
    dropped = design_plan(
        crossed_data(), "rt ~ cond + (1 | subject) + (1 | item)", crossed_declaration(False)
    )
    assert dropped["design"]["ladder"] == "exploratory"
    assert "protected" not in dropped["design"]
    assert "rule_evidence" not in dropped
    assert names(dropped["design"]["rungs"][-1]["ir"]) == ["1 | subject", "1 | item"]


def test_outcome_never_read() -> None:
    data = crossed_data()
    blind = design_plan(data, FORMULA, crossed_declaration())
    data["rt"] = [k * 1.5 for k in range(len(data))]
    seen = design_plan(data, FORMULA, crossed_declaration())
    assert seen["design_plan_hash"] == blind["design_plan_hash"]
    assert seen["ceiling"] == blind["ceiling"]


def test_complex_intercepts() -> None:
    plan = design_plan(crossed_data(), "rt ~ block + (1 | subject)")
    assert plan["design"]["rungs"][1]["step"]["kind"] == "complex_intercepts"
    assert names(plan["design"]["rungs"][1]["ir"]) == ["1 | subject", "1 | subject:block"]


def test_rung_zero_leaves_out_what_is_not_identified() -> None:
    data = pd.DataFrame(
        [{"cond": c, "subject": f"s{k:02d}", "y": None} for k in range(1, 21) for c in "ab"]
    )
    data["y"] = data["y"].astype(float)
    plan = design_plan(data, "y ~ cond + (1 | subject)")
    assert plan["ceiling"]["excluded"] == [{"factor": "subject", "term": "0 + cond | subject"}]
    assert names(plan["design"]["rungs"][0]["ir"]) == ["1 | subject"]


def test_counts_follow_privacy_filter() -> None:
    fixture = pathology_zoo("Z05N")
    plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
    subject = plan["ceiling"]["factors"][0]
    assert subject["levels"] == 16
    assert subject["terms"][0]["informative_groups"] == {"suppressed": "secondary"}


def test_refusals() -> None:
    data = crossed_data()
    assert issue(data, "rt ~ cond")["code"] == "E7315"
    bad = copy.deepcopy(crossed_declaration())
    bad["estimands"][0]["term"] = "freq"
    assert issue(data, "rt ~ cond + (1 | subject)", bad)["code"] == "E7314"
    draft = copy.deepcopy(crossed_declaration())
    draft["provenance"] = {"inferred": ["/units/0"]}
    assert issue(data, "rt ~ cond + (1 | subject)", draft)["code"] == "E2032"
    found = issue(data, FORMULA, crossed_declaration(), terminal="cluster_robust_cr2")
    assert found["code"] == "E7307"
    with pytest.raises(ValueError, match="'rule'"):
        design_plan(data, "rt ~ cond + (1 | subject)", rule="aic")
    fixture = pathology_zoo("Z08")
    assert issue(fixture["data"], fixture["formula"], fixture["declaration"])["code"] == "E7316"
    fixture = pathology_zoo("Z21")
    found = issue(fixture["data"], fixture["formula"], fixture["declaration"])
    assert found["code"] == "E7311"
    assert "'1' of 'school'" in found["message"]


def test_rules_and_outcome_access() -> None:
    fixture = pathology_zoo("Z30N")
    plan = design_plan(
        fixture["data"],
        fixture["formula"],
        fixture["declaration"],
        rule="protected_lrt",
        outcome_access="T1",
    )
    assert plan["design"]["rule"] == {
        "id": "protected_lrt",
        "parameters": {"alpha": "0.2"},
        "version": 1,
    }
    assert plan["outcome_access"] == "T1"


def test_statsmodels_binding(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_plan, "statsmodels_version", lambda: "0.15.0")
    fixture = pathology_zoo("Z30")
    plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
    entry = plan["bindings"][0]
    assert entry["hash"] == canonical_hash(entry["binding"], "hashable")
    assert entry["binding"]["engine"] == {"name": "statsmodels", "version": "0.15.0"}
    first = entry["binding"]["rungs"][0]
    assert first["encoding"] == (
        '{"engine":"statsmodels.MixedLM","fixed":["(Intercept)","arm[treatment]"],'
        '"groups":["site"],"offsets":[],"re":["(Intercept)","arm[treatment]"],'
        '"response":"y","use_sparse":false,"vc":[]}'
    )
    # Crossed correlated slopes cannot be expressed.
    crossed = design_plan(crossed_data(), FORMULA, crossed_declaration())
    rungs = crossed["bindings"][0]["binding"]["rungs"]
    assert rungs[0]["availability"] == {
        "value": "not_available",
        "reason": "not_expressible",
        "detail": "statsmodels",
    }
    assert rungs[-1]["availability"] == {"value": "available"}
    monkeypatch.setattr(_plan, "statsmodels_version", lambda: None)
    assert (
        design_plan(fixture["data"], fixture["formula"], fixture["declaration"])["bindings"] == []
    )


def codes(plan: Any) -> list[str]:
    try:
        validate_plan(plan)
    except MixedcheckError as err:
        return [i["code"] + " " + i.get("pointer", "") for i in err.issues]
    return []


def test_validator_rules() -> None:
    fixture = pathology_zoo("Z30")
    plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
    edited = copy.deepcopy(plan)
    edited["design"]["rule"]["parameters"] = {"alpha": "0.05"}
    assert codes(edited) == ["E1321 /design_plan_hash"]
    edited = copy.deepcopy(plan)
    edited["verdicts"] = edited["verdicts"][:1]
    assert codes(edited) == ["E7303 /verdicts"]
    edited = copy.deepcopy(plan)
    edited["verdicts"][0]["value"] = "not_identified"
    assert codes(edited) == ["E7304 /verdicts/0"]
    edited = copy.deepcopy(plan)
    edited["ceiling"]["factors"].append(edited["ceiling"]["factors"][0])
    assert codes(edited) == ["E7308 /ceiling/factors/1/factor"]
    edited = copy.deepcopy(plan)
    edited["ceiling"]["ir"]["fixed"]["terms"][1]["name"] = "arms"
    assert codes(edited) == ["E6101 /ceiling/ir/fixed/terms/1/name"]
    edited = copy.deepcopy(plan)
    edited["plan_version"] = "0.2.0"
    assert codes(edited) == ["E1441 /plan_version"]


def test_preregistration_text() -> None:
    fixture = pathology_zoo("Z30")
    plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
    text = preregistration_text(plan)
    assert plan["design_plan_hash"] in text
    assert (
        "Rung 1, decorrelating '1 + arm | site': y ~ 1 + arm + (1 | site) + (0 + arm | site)"
        " (identified)." in text
    )
    assert "is not for preregistration" in text
    assert text.endswith("\n")


def test_audit_bound_to_plan() -> None:
    fixture = pathology_zoo("Z30")
    plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
    results = audit(
        fixture["data"],
        "y ~ arm + (1 + arm || site)",
        fixture["declaration"],
        plan=plan,
        outcome_access="T1",
        reason="planned",
        key=AUDIT_KEY,
    )
    log = results.document["access_log"]
    assert log["plan"] == {"design_plan_hash": plan["design_plan_hash"], "outcome_access": "T0"}
    assert log["entries"][1]["mode"] == "planned"
    validate_results(results)
    with pytest.raises(MixedcheckError) as raised:
        audit(
            fixture["data"],
            "y ~ arm + (1 | site)",
            fixture["declaration"],
            plan=plan,
            key=AUDIT_KEY,
        )
    assert raised.value.issues[0]["message"] == (
        "The run does not belong to the plan: its IR hash differs from the one the plan records."
    )
    with pytest.raises(MixedcheckError) as raised:
        audit(fixture["data"], fixture["formula"], plan=plan, key=AUDIT_KEY)
    assert raised.value.issues[0]["code"] == "E7310"


def test_exports() -> None:
    for name in ("design_plan", "validate_plan", "preregistration_text", "draft_design"):
        assert name in mixedcheck.__all__


def school_data() -> pd.DataFrame:
    """Pupils in classes with labels unique across schools, classes
    randomised."""
    rows = []
    for school in range(1, 7):
        for c in range(1, 5):
            label = f"c{(school - 1) * 4 + c:02d}"
            for pupil in range(1, 7):
                rows.append(
                    {
                        "pupil": f"{label}-p{pupil}",
                        "class": label,
                        "school": f"s{school}",
                        "arm": "control" if int(label[1:]) % 2 == 0 else "tutoring",
                        "y": float("nan"),
                    }
                )
    return pd.DataFrame(rows)


def school_declaration() -> Any:
    return declaration(
        units=[
            declare_unit("school", ["school"], role="cluster"),
            declare_unit("class", ["class"], nested_in="school", id_scope="global", role="cluster"),
            declare_unit(
                "pupil", ["pupil"], nested_in="class", id_scope="global", role="participant"
            ),
        ],
        observation=declare_observation(key=["pupil"], unit="pupil"),
        assignment=[
            declare_assignment(
                "arm", "class", randomised=True, level="between_unit", blocks=["school"]
            )
        ],
        variables={
            "y": declare_variable("outcome", measurement="continuous"),
            "arm": declare_variable("assigned"),
        },
        estimands=[declare_estimand("itt", "arm", kind="total_effect")],
        features=["cluster_randomised"],
    )


def test_unit_written_with_slash() -> None:
    plan = design_plan(school_data(), "y ~ arm + (1 | school/class)", school_declaration())
    protected = [c["factor"] + " " + c["reason"] for c in plan["design"]["protected"]]
    # The arm varies within schools, so its slope by school is protected too.
    assert protected == [
        "school replication_unit",
        "school:class randomisation_unit",
        "school focal_slope",
    ]
    assert names(plan["design"]["rungs"][-1]["ir"]) == [
        "1 | school",
        "0 + arm | school",
        "1 | school:class",
    ]


def test_focal_slopes_only_by_declared_units() -> None:
    plan = design_plan(
        crossed_data(), "rt ~ cond + (1 | subject:item) + (1 | subject)", crossed_declaration()
    )
    assert "subject:item" not in [c["factor"] for c in plan["design"]["protected"]]


def test_caller_coding_keeps_frozen_factors() -> None:
    from mixedcheck._plan_text import ir_formula

    coding = {"cond": {"contrast": "simple"}}
    plan = design_plan(crossed_data(), FORMULA, crossed_declaration(), coding=coding)
    formula = ir_formula(plan["design"]["rungs"][1]["ir"])
    results = audit(
        crossed_data(), formula, crossed_declaration(), plan=plan, coding=coding, key=AUDIT_KEY
    )
    assert results.document["access_log"]["plan"]["design_plan_hash"] == plan["design_plan_hash"]
