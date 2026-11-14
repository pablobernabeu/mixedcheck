"""Runs the pseudonym cases of the differential test with the installed Python
package (parity/README.md, Differential test).

Usage: python pseudonyms.py CASES OUTPUT

Registry 0.1.0 has no statistic of kind labels, so no audit writes a
pseudonym. Each case of CASES, which differential.py writes, holds findings of
a check whose findings write labels, as test_privacy.py defines it, each with
its factor, its labels and the distinct contributors of its support, and the
commitment key and k of the case. The runner applies step 2 of the filter to
each finding, then steps 10 and 11, and writes to OUTPUT one line for each
case with the hexadecimal digits of the canonical bytes, in the data profile,
of the case's identifier, the written findings and the pseudonyms in the form
of the internal sidecar, as pseudonyms.R does.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import numpy as np

from mixedcheck import canonical_bytes, read_json_strict
from mixedcheck._checks import Finding, Support, document_finding
from mixedcheck._privacy import privacy_minimum_rules, privacy_pseudonyms, privacy_render

# A check whose findings write labels, a copy of the one that
# python/tests/test_privacy.py defines, which the tests and this runner keep
# apart because the tests do not ship with the parity harness.
LABELS_ENTRY: dict[str, Any] = {
    "id": "structure.flagged_levels",
    "version": 1,
    "tier": "T0",
    "sample": "design",
    "scope": "grouping_factor",
    "statistics": {
        "flagged": {"kind": "labels"},
        "flagged_levels": {"kind": "count", "count_class": "person"},
    },
    "decision": {
        "rules": [
            {
                "finding": "detectable_inconsequential",
                "statistics": ["flagged"],
                "thresholds": [],
                "message": "listed",
            }
        ],
        "otherwise": {"finding": "consistent", "message": "listed"},
    },
    "assessability": [],
    "messages": {
        "listed": {
            "template": "Flagged levels of '{factor}': {flagged}.",
            "fallback": "Some levels of '{factor}' are flagged.",
            "args": {
                "factor": {"source": "scope", "name": "factor"},
                "flagged": {"source": "statistic", "name": "flagged"},
            },
        }
    },
}


def labels_finding(
    factor: str, labels: list[str], distinct: int, dominated: bool, k: int
) -> Finding:
    """A finding of the check of LABELS_ENTRY on a grouping factor, with its
    labels and distinct contributors, after step 2 of the privacy filter at
    k, as the labels_finding() of test_privacy.py builds it."""
    finding = Finding(
        check="structure.flagged_levels",
        check_version=1,
        tier="T0",
        scope={"factor": factor},
        available=True,
        status={
            "assessability": {"value": "adequate"},
            "finding": {"value": "detectable_inconsequential"},
            "threshold_proximity": {"value": "clear"},
            "validation": {"value": "descriptive"},
        },
        message={"id": "listed", "text": ""},
        statistics={
            "flagged": {"kind": "labels"},
            "flagged_levels": {"kind": "count", "count_class": "person"},
        },
        values={"flagged": list(labels), "flagged_levels": 12},
        support=Support(200, "grouping_factors", distinct, dominated, {}),
        items={},
        rows=np.arange(200),
        entry=LABELS_ENTRY,
        rule=0,
        label_factors={"flagged": factor},
    )
    return privacy_minimum_rules(finding, k)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: python pseudonyms.py CASES OUTPUT", file=sys.stderr)
        return 2
    cases = read_json_strict(argv[1], "data")["cases"]
    lines = []
    for case in cases:
        findings = [
            labels_finding(f["factor"], f["labels"], f["distinct"], f["dominated"], case["k"])
            for f in case["findings"]
        ]
        pseudonyms = privacy_pseudonyms(findings, case["key"])
        rendered = [privacy_render(finding, pseudonyms) for finding in findings]
        written = {
            "id": case["id"],
            "findings": [document_finding(finding) for finding in rendered],
            "pseudonyms": pseudonyms,
        }
        lines.append(canonical_bytes(written, "data").hex())
    Path(argv[2]).write_text("".join(line + "\n" for line in lines), encoding="ascii")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
