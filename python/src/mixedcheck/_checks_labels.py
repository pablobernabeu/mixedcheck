"""The check of the prefix labels (spec/registry/checks/labels.unicode_forms.yaml)."""

from __future__ import annotations

from collections import Counter
from typing import Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    assignment_elements,
    check_element,
    column_index,
    declared_role_columns,
    role_columns,
)
from mixedcheck._commitments import observation_key_columns
from mixedcheck._unicode import comparison_form


def check_labels_unicode_forms(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """labels.unicode_forms: for each column that holds labels, the distinct
    strings of the table that share their NFC form with another distinct
    string, and the NFC forms they share. A string that is not normalisable
    stands for itself."""
    labelled = set(label_columns(run))
    found: list[CheckElement | None] = []
    for element in elements:
        key = element["column"]
        if key not in labelled:
            found.append(None)
            continue
        j = column_index(run, key)
        spellings = 0
        labels = 0
        if run.table.types[j] == "string":
            present = run.table.values[j][~run.table.missing[j]].tolist()
            forms = [comparison_form(value) for value in dict.fromkeys(present)]
            counts = Counter(forms)
            shared = [form for form in forms if counts[form] > 1]
            spellings = len(shared)
            labels = len(set(shared))
        found.append(
            check_element({"spellings": spellings, "labels": labels}, rules=[spellings > 0])
        )
    return found


def label_columns(run: Run) -> list[str]:
    """The keys of the columns that hold labels (applies_when of
    labels.unicode_forms): the grouping columns, the categorical predictors of
    the IR, the columns of the observation key, the columns of the entries of
    the assignment block and the columns that the declaration gives the role
    assigned, without the outcome columns, which the check does not read."""
    declaration = run.declaration
    ir = run.ir
    categorical = [key for key, p in ir["predictors"].items() if p["kind"] == "categorical"]
    assigned = [element["column"] for element in assignment_elements(declaration)]
    roles = role_columns(declaration, ["assigned"])
    declared = observation_key_columns(declaration) + assigned + roles
    found = run.grouping_columns + categorical + [comparison_form(name) for name in declared]
    outcome = set(declared_role_columns(declaration, ("outcome", "outcome_derived")))
    response = ir.get("response")
    if response is not None:
        outcome.add(response["variable"])
        if "trials" in response:
            outcome.add(response["trials"])
    return [key for key in dict.fromkeys(found) if key not in outcome]
