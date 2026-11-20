"""The preregistration text of a plan (02-decisions.md, Q3) and the formula of
an IR, which both packages write identically from the plan alone."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from mixedcheck._errors import format_integer
from mixedcheck._formula_ir import term_name_of
from mixedcheck._formula_parse import variable_text
from mixedcheck._json_read import parse_json_bytes
from mixedcheck._json_write import canonical_bytes
from mixedcheck._plan_validate import validate_plan

_REASONS = {
    "replication_unit": "replication unit",
    "randomisation_unit": "randomisation unit",
    "focal_slope": "focal slope",
    "focal_interaction_slope": "focal interaction slope",
    "cross_level_interaction_slope": "cross-level interaction slope",
}


def preregistration_text(plan: Any) -> str:
    """Write the preregistration text of a plan.

    Writes the text that states a plan in words: its hashes, the outcome
    access when it was frozen, the ceiling with its counts, every rung of the
    ladder with the step that leads to it, the protected set, the stopping
    rule and the terminal state. Both packages write the same text for the
    same plan. Plans written by 0.x releases are not for preregistration, and
    the text says so.

    Args:
        plan: A plan, as :func:`validate_plan` accepts it.

    Returns:
        The text, lines that each end with a line feed.

    Raises:
        MixedcheckError: The errors of :func:`validate_plan`.

    Examples:
        >>> fixture = pathology_zoo("Z05N")
        >>> plan = design_plan(fixture["data"], fixture["formula"], fixture["declaration"])
        >>> preregistration_text(plan).splitlines()[0]
        'Analysis plan'
    """
    plan = validate_plan(plan)
    plan = parse_json_bytes(canonical_bytes(plan, "hashable"), "hashable")
    design = plan["design"]
    rungs = design["rungs"]

    def quote(x: str) -> str:
        return "'" + x + "'"

    def join(items: list[str]) -> str:
        if len(items) <= 1:
            return "".join(items)
        return ", ".join(items[:-1]) + " and " + items[-1]

    def count(value: Any, noun: str) -> str:
        """A count with its noun: the number, 'fewer than k' or, for a count
        that the privacy filter suppressed by another rule, a number it
        withholds."""
        if isinstance(value, dict) and "below" in value:
            return "fewer than " + format_integer(value["below"]) + " " + noun
        if isinstance(value, dict):
            return (
                "a number of "
                + noun
                + " that the privacy filter withholds ("
                + str(value["suppressed"])
                + ")"
            )
        return format_integer(value) + " " + noun

    versions = plan["versions"]
    lines = [
        "Analysis plan",
        "",
        "Design-plan hash: " + plan["design_plan_hash"],
        "Plan version "
        + plan["plan_version"]
        + ", written by mixedcheck "
        + versions["package"]
        + " ("
        + plan["language"]
        + ") with registry "
        + versions["registry"]
        + ", schemas "
        + versions["schemas"]
        + " and canonicaliser "
        + versions["canonicaliser"]
        + ".",
        "This plan is not for preregistration: plans written by 0.x releases are not, until the"
        " plan schema and the canonicaliser carry versions that later releases can verify.",
        "The plan was frozen without reading the outcome (T0)."
        if plan["outcome_access"] == "T0"
        else "The plan was frozen after the outcome had been read at "
        + plan["outcome_access"]
        + ", so it was planned after outcome inspection.",
        "The plan was built without a declaration."
        if "declaration_hash" not in design
        else "Declaration hash: " + design["declaration_hash"],
        "",
        "Ceiling",
        "",
        "The design-implied ceiling is "
        + ir_formula(plan["ceiling"]["ir"])
        + ", and its identifiability verdict is "
        + plan["ceiling"]["verdict"]["value"]
        + ".",
    ]
    for factor in plan["ceiling"]["factors"]:
        groups = [
            count(t["informative_groups"], "informative groups") + " behind " + quote(t["term"])
            for t in factor["terms"]
        ]
        lines.append(
            "Grouping factor "
            + quote(factor["factor"])
            + ": "
            + count(factor["levels"], "levels")
            + ", "
            + count(factor["df_budget"], "degrees of freedom between levels")
            + " and "
            + join(groups)
            + "."
        )
    if plan["ceiling"].get("excluded"):
        lines.append(
            "Left out of rung 0 as not identifiable: "
            + join([quote(e["term"]) for e in plan["ceiling"]["excluded"]])
            + "."
        )
    lines += ["", "Ladder (" + design["ladder"] + ")", ""]
    for r, rung in enumerate(rungs):
        head = "Rung " + str(r)
        step = rung.get("step")
        if step is not None:
            terms = join([quote(t) for t in step["terms"]])
            head += (
                ", "
                + {
                    "decorrelate": "decorrelating " + terms,
                    "complex_intercepts": "replacing "
                    + terms
                    + " by complex random intercepts, which restrict the correlations between"
                    " its levels to be non-negative",
                    "drop_terms": "dropping " + terms,
                }[step["kind"]]
            )
        lines.append(
            head + ": " + ir_formula(rung["ir"]) + " (" + plan["verdicts"][r]["value"] + ")."
        )
    if design["ladder"] == "protected":
        components = []
        for c in design["protected"]:
            if c["variables"]:
                what = "the slope of " + quote(term_name_of(list(c["variables"])))
            else:
                what = "the random intercept"
            components.append(
                what + " by " + quote(c["factor"]) + " (" + _REASONS[c["reason"]] + ")"
            )
        rule = design["rule"]
        parameters = [name + " " + value for name, value in rule["parameters"].items()]
        terminal = {
            "no_confirmatory_model": "no confirmatory model, which reports the failure",
            "cluster_robust_cr2": "CR2 cluster-robust inference, which is engine-specific",
        }[design["terminal"]["state"]]
        lines += [
            "The ladder never removes the protected set: " + join(components) + ".",
            "Rung " + str(len(rungs) - 1) + " is the protected rung.",
            "",
            "Stopping rule and terminal state",
            "",
            "The confirmatory model is the rung that the stopping rule "
            + rule["id"]
            + ", version "
            + format_integer(rule["version"])
            + (" with " + join(parameters) if parameters else "")
            + ", selects from this ladder.",
            "The operating characteristics of the rule are known only for simulated conditions"
            " until study H1 has run.",
            "If the protected rung fails, the analysis ends in the terminal state "
            + terminal
            + ".",
            "The selected rung is reported with the protected rung and the adjacent rung as"
            " pre-declared sensitivity analyses.",
        ]
    else:
        lines += [
            "",
            "Without a focal estimand, the protected set cannot be defined, so the ladder is"
            " exploratory and no stopping rule is executed.",
        ]
    if plan["bindings"]:
        lines += ["", "Execution bindings", ""]
        for entry in plan["bindings"]:
            binding = entry["binding"]
            lines.append(
                binding["engine"]["name"]
                + " "
                + binding["engine"]["version"]
                + " ("
                + binding["language"]
                + "): "
                + entry["hash"]
            )
    return "\n".join(lines) + "\n"


def ir_formula(ir: Mapping[str, Any]) -> str:
    """The formula of an IR in the grammar of ir.md: the response, the fixed
    part by the names of its terms, the offsets and the random terms, where the
    terms that '||' has split from one term of a frozen factor are written as
    that term with '||'."""
    response = ir.get("response")
    lhs = ""
    if response is not None:
        text = variable_text(response["variable"])
        lhs = ("log(" + text + ")" if response["transform"] == "log" else text) + " "
    terms = [t["name"] for t in ir["fixed"]["terms"]]
    fixed = ["1", *terms[1:]] if terms and terms[0] == "(Intercept)" else ["0", *terms]
    offsets = []
    for o in ir["offsets"]:
        text = variable_text(o["variable"])
        offsets.append("offset(" + ("log(" + text + ")" if o["transform"] == "log" else text) + ")")
    random: list[str] = []
    previous: tuple[str, tuple[str, ...]] | None = None
    for term in ir["random"]:
        levels = []
        if len(term["terms"]) == 1:
            levels = [v["level"] for v in term["terms"][0]["variables"] if "level" in v]
        if levels:
            variables = [v["variable"] for v in term["terms"][0]["variables"]]
            key = (term["factor"], tuple(variables))
            if key != previous:
                random.append("(0 + " + term_name_of(variables) + " || " + term["factor"] + ")")
            previous = key
        else:
            random.append("(" + term["name"] + ")")
            previous = None
    return lhs + "~ " + " + ".join(fixed + offsets + random)
