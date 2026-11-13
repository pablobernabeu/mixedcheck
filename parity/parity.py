"""The parity harness: runs the conformance corpora with the R and Python
packages and compares their outcomes with each other and with the expected
outcomes of the corpora (parity/README.md).

Usage, from the repository root:

    python3 parity/parity.py [--python PYTHON] [--rscript RSCRIPT]
                             [--r-lib DIR] [--r-locale LOCALE ...]
                             [--corpus DIR] [--keep DIR] [--compare-only]

The script needs only the standard library of Python 3.11 or later. PYTHON
must be an interpreter with the package mixedcheck and PyYAML installed, and
R must find an installed mixedcheck and the package yaml, in DIR when it is
given. The exit status is 0 when every case gives the expected outcome in
every run, 1 when a case does not, and 2 when the harness cannot run.
"""

from __future__ import annotations

import argparse
import functools
import hashlib
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MODES = ("plain", "data", "hashable")
LANGUAGES = ("R", "Python")
DEFAULT_R_LOCALES = ("C.UTF-8", "C")
# The line of the summary for the vendored files of spec/.
FILES = "spec/ (vendored files)"
# The longest text shown for a value in a report.
SHOWN = 160


class HarnessError(Exception):
    """The harness cannot run."""


# Expected outcomes, encoded as the runners encode outcomes: every string as
# the lower-case hexadecimal digits of its UTF-8 bytes.


def encode(x: Any) -> Any:
    if isinstance(x, bytes):
        return x.hex()
    if isinstance(x, str):
        return x.encode("utf-8", "surrogatepass").hex()
    if isinstance(x, dict):
        return {key: encode(value) for key, value in x.items()}
    if isinstance(x, list):
        return [encode(value) for value in x]
    return x


def canonical_outcome(expected: dict[str, Any]) -> dict[str, Any]:
    outcome = {"canonical": expected["canonical"], "sha256": expected["sha256"]}
    if "bits" in expected:
        outcome["bits"] = expected["bits"]
    return outcome


def expected_parts(kind: str, case: dict[str, Any]) -> dict[str, dict[str, Any] | None]:
    """The expected outcome of each part of a case, by the format of its
    corpus (fixtures/conformance/*/README.md)."""
    expected = case["expected"]
    if kind == "json":
        parts = {}
        for mode in MODES:
            if mode in expected:
                result = expected[mode]
                if "issue" in result:
                    parts[mode] = {"issues": [result["issue"]]}
                else:
                    parts[mode] = canonical_outcome(result)
        return parts
    if kind == "decimal":
        return {"value": {"decimal": expected["decimal"]}}
    if kind in ("normalisation", "order", "hmac"):
        return {"value": dict(expected)}
    if kind == "sha256":
        return {"memory": dict(expected), "file": dict(expected)}
    if kind == "section":
        return {"value": canonical_outcome(expected)}
    if kind == "commitment":
        if "issue" in expected:
            return {"value": {"issues": [expected["issue"]]}}
        return {"value": dict(expected)}
    if kind == "declaration":
        if "issues" in expected:
            return {"value": {"issues": expected["issues"]}}
        return {"value": canonical_outcome(expected)}
    if kind == "table":
        return expected_table(case)
    if kind == "formula":
        return expected_formula(case)
    if kind == "audit":
        return expected_audit(case)
    if kind == "results":
        return expected_results(case)
    raise HarnessError(f"Unknown kind of corpus '{kind}'.")


def double_bits(value: float) -> str:
    """The 16 hexadecimal digits of the bits of a double, with negative zero
    as zero."""
    return struct.pack(">d", value + 0.0).hex()


def real_value(value: Any) -> str:
    """A number of a corpus as the runners write a double: the bits of the
    nearest double, or 'NaN', 'Infinity' or '-Infinity' as the data profile
    writes them."""
    if isinstance(value, str):
        return value
    return double_bits(float(value))


def expected_table(case: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """The read table and, for a case with a formula, the samples
    (fixtures/conformance/tables/README.md). A value of a number column is
    compared by its bits, with negative zero as zero."""
    expected = case["expected"]
    if "issue" in expected:
        return {"value": {"issues": [expected["issue"]]}}
    columns = []
    for column in expected["columns"]:
        number = column["type"] == "number"
        values = [
            real_value(value) if number and value is not None else value
            for value in column["values"]
        ]
        columns.append({"name": column["name"], "type": column["type"], "values": values})
    parts: dict[str, dict[str, Any]] = {"value": {"columns": columns}}
    if "formula" in case:
        parts["samples"] = {
            "design_sample": expected["design_sample"],
            "analysis_sample": expected["analysis_sample"],
        }
    return parts


def expected_formula(case: dict[str, Any]) -> dict[str, dict[str, Any] | None]:
    """The IR with its hash and, for a case with matrices, the design
    matrices, compared bit for bit, and the response, trials, offset and
    weight vectors, which the corpus does not give and which are compared
    across languages within the tolerance of real values, or, for a case with
    an issue beside its IR, the issue that the design matrices report
    (fixtures/conformance/formulas/README.md)."""
    expected = case["expected"]
    if "ir" not in expected:
        return {"ir": {"issues": [expected["issue"]]}}
    ir = canonical_json(expected["ir"])
    digest = "sha256:" + hashlib.sha256(ir).hexdigest()
    if digest != expected["ir_hash"]:
        raise HarnessError(f"The IR of {case['id']} does not have its stated hash.")
    parts: dict[str, dict[str, Any] | None] = {"ir": {"canonical": ir, "sha256": digest}}
    if "issue" in expected:
        # The issue that the design matrices report for the IR.
        parts["matrices"] = {"issues": [expected["issue"]]}
        return parts
    matrices = expected.get("matrices")
    if matrices is None:
        return parts
    rows = matrices["rows"]
    widths = sum(len(term["columns"]) for term in expected["ir"]["random"])
    parts["matrices"] = {
        "rows": rows,
        "x": [[real_value(value) for value in row] for row in matrices["x"]],
        "x_columns": [column["name"] for column in expected["ir"]["fixed"]["columns"]],
        "x_dropped": matrices["x_dropped"],
        "z": [[real_value(value) for value in row] for row in matrices.get("z", [[]] * len(rows))],
        "z_columns": matrices.get("z_columns", []),
        "z_stored": len(rows) * widths,
    }
    parts["vectors"] = None
    return parts


def expected_audit(case: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """The issue that refuses the run of a case, or the findings of the checks
    of the case in internal mode and, for a case of privacy.json, in shareable
    mode (fixtures/conformance/audits/README.md). The findings are held as JSON
    text with the checks and the exact statistics of the case, so that
    audit_differences() compares them with a document by the rules of that
    README."""
    expected = case["expected"]
    if "issue" in expected:
        return {"internal": {"issues": [expected["issue"]]}}

    def findings(listed: list[dict[str, Any]]) -> dict[str, Any]:
        value = {"findings": listed, "checks": case["checks"], "exact": case.get("exact", [])}
        return {"findings": json.dumps(value, ensure_ascii=False)}

    parts = {"internal": findings(expected["findings"])}
    if "shareable" in expected:
        parts["shareable"] = findings(expected["shareable"])
    return parts


def expected_results(case: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """The outcome of validate_results() on the document alone and, for a case
    with a sidecar, on the document with its sidecar, data and declaration
    (fixtures/conformance/results/README.md): 'valid' when the call returns,
    with W7090 as a warning, or the issues of its error. An error in the
    document stops validation before the sidecar."""
    expected = case["expected"]
    issues = expected["issues"]
    warned = len(issues) == 1 and issues[0]["code"] == "W7090"
    document: dict[str, Any] = {"issues": issues}
    if not issues or warned:
        document = {"valid": True}
        if warned:
            document["warnings"] = issues
    parts = {"document": document}
    if "sidecar" in case:
        if issues and not warned:
            parts["sidecar"] = document
        else:
            sidecar_issues = expected["sidecar_issues"]
            sidecar = {"issues": sidecar_issues} if sidecar_issues else {"valid": True}
            if warned:
                sidecar["warnings"] = issues
            parts["sidecar"] = sidecar
    return parts


def canonical_json(value: Any) -> bytes:
    """The canonical bytes of RFC 8785 for a value without numbers other than
    integers, such as an IR: members sorted by the UTF-16 code units of their
    keys and strings escaped as RFC 8785 requires."""
    if value is None or isinstance(value, bool):
        return json.dumps(value).encode("ascii")
    if isinstance(value, int):
        if abs(value) > 2**53 - 1:
            raise HarnessError(f"The integer {value} is outside the range of the profiles.")
        return str(value).encode("ascii")
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).encode("utf-8", "surrogatepass")
    if isinstance(value, list):
        return b"[" + b",".join(canonical_json(item) for item in value) + b"]"
    if isinstance(value, dict):
        keys = sorted(value, key=lambda key: key.encode("utf-16-be", "surrogatepass"))
        members = [canonical_json(key) + b":" + canonical_json(value[key]) for key in keys]
        return b"{" + b",".join(members) + b"}"
    raise HarnessError(f"The canonical form of {value!r} is not computed by the harness.")


def expected_artefacts(artefacts: list[str]) -> dict[tuple[str, str], dict[str, Any] | None]:
    """The expected outcome of each artefact record, or None for the files of
    spec/ whose canonical form only the two packages compute, which are
    compared across languages alone. The compiled registry is stored in
    canonical form, and spec_versions() returns spec/versions.json."""
    registry = (ROOT / "spec" / "compiled" / "registry.json").read_bytes()
    as_stored = encode(
        {"canonical": registry, "sha256": "sha256:" + hashlib.sha256(registry).hexdigest()}
    )
    versions = json.loads((ROOT / "spec" / "versions.json").read_text(encoding="utf-8"))
    parts: dict[tuple[str, str], dict[str, Any] | None] = {
        (name, "data"): as_stored if name == "compiled/registry.json" else None
        for name in artefacts
    }
    parts[("read_registry()", "hashable")] = as_stored
    parts[("spec_versions()", "value")] = encode({"value": versions})
    return parts


# Showing outcomes.


def text(value: str) -> str:
    """The text of hexadecimal digits, with characters that a terminal may
    not show escaped, shortened to SHOWN characters."""
    shown = bytes.fromhex(value).decode("utf-8", "backslashreplace")
    shown = shown.encode("ascii", "backslashreplace").decode("ascii")
    shown = "".join(c if c.isprintable() else repr(c)[1:-1] for c in shown)
    if len(shown) > SHOWN:
        shown = shown[: SHOWN - 3] + "..."
    return "'" + shown + "'"


def show_issue(issue: dict[str, Any]) -> str:
    where = ""
    if "offset" in issue:
        where = f" at byte {issue['offset']}"
    elif "pointer" in issue:
        where = f" at {text(issue['pointer'])}"
    extra = sorted(set(issue) - {"code", "message", "offset", "pointer"})
    rest = f" with further members {', '.join(extra)}" if extra else ""
    return f"{text(issue.get('code', ''))}{where}: {text(issue.get('message', ''))}{rest}"


def show_value(value: Any) -> str:
    if isinstance(value, str):
        return text(value)
    if isinstance(value, list):
        return "[" + ", ".join(show_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(f"{key}: {show_value(item)}" for key, item in value.items()) + "}"
    return json.dumps(value)


def show(outcome: dict[str, Any] | None) -> list[str]:
    """Lines that describe an outcome."""
    if outcome is None:
        return ["no outcome"]
    lines = []
    for key, value in outcome.items():
        if key in ("issues", "warnings") and isinstance(value, list):
            label = "issue" if key == "issues" else "warning"
            lines += [f"{label} {show_issue(issue)}" for issue in value] or [f"no {label}s"]
        elif key == "canonical":
            size = len(value) // 2
            lines.append(f"canonical bytes ({size}) {text(value)}")
        elif key == "error":
            lines.append(f"error {text(value)}")
        else:
            lines.append(f"{key} {show_value(value)}")
    return lines


def first_difference(a: str, b: str) -> str:
    """Where two canonical byte strings, as hexadecimal digits, first differ."""
    x, y = bytes.fromhex(a), bytes.fromhex(b)
    index = next((i for i in range(min(len(x), len(y))) if x[i] != y[i]), min(len(x), len(y)))
    start = max(0, index - 20)
    return (
        f"first difference at byte {index}: "
        f"{text(x[start : index + 20].hex())} and {text(y[start : index + 20].hex())}"
    )


# Running the packages.


def run(command: list[str], env: dict[str, str], label: str) -> float:
    started = time.monotonic()
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, errors="replace")
    except OSError as err:
        raise HarnessError(f"{label} cannot start: {err}") from err
    elapsed = time.monotonic() - started
    if result.returncode != 0:
        raise HarnessError(
            f"{label} failed with status {result.returncode}:\n{result.stdout}{result.stderr}"
        )
    for line in (result.stdout + result.stderr).splitlines():
        print(f"  {label}: {line}")
    return elapsed


def read_output(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not path.exists():
        raise HarnessError(f"{path} was not written.")
    lines = path.read_text(encoding="ascii").splitlines()
    if not lines:
        raise HarnessError(f"{path} is empty.")
    return json.loads(lines[0]), [json.loads(line) for line in lines[1:]]


def corpus_list(corpus: Path) -> list[dict[str, Any]]:
    """The corpus files in parity/corpora.json, which must list every corpus
    file of the corpus directory."""
    listed = json.loads((HERE / "corpora.json").read_text(encoding="utf-8"))["corpora"]
    names = [entry["file"] for entry in listed]
    present = sorted(p.relative_to(corpus).as_posix() for p in corpus.glob("*/*.json"))
    present = [name for name in present if not name.startswith("tools/")]
    problems = [
        f"{name} is not listed in parity/corpora.json" for name in present if name not in names
    ]
    problems += [
        f"{name} is listed in parity/corpora.json but missing"
        for name in names
        if name not in present
    ]
    if len(set(names)) != len(names):
        problems.append("parity/corpora.json lists a file twice")
    if problems:
        raise HarnessError("\n".join(problems))
    return listed


def vendored_artefacts() -> list[str]:
    """The JSON files of spec/ that spec/vendoring.json vendors into both packages."""
    vendoring = json.loads((ROOT / "spec" / "vendoring.json").read_text(encoding="utf-8"))
    return [
        name.removeprefix("spec/")
        for name in vendoring["artefacts"]
        if name.startswith("spec/") and name.endswith(".json")
    ]


def code_languages() -> dict[str, list[str]]:
    """The codes of spec/errors.json that only some languages can raise."""
    catalogue = json.loads((ROOT / "spec" / "errors.json").read_text(encoding="utf-8"))
    return {
        entry["code"]: entry["languages"] for entry in catalogue["codes"] if "languages" in entry
    }


# Comparing outcomes.


def words(items: list[str]) -> str:
    """Items joined by ', ', with ' and ' before the last."""
    if len(items) < 2:
        return "".join(items)
    return ", ".join(items[:-1]) + " and " + items[-1]


# Real values, the members under the key 'reals' of an outcome, are compared
# within the tolerance of conventions.md (Comparison across languages).
ABSOLUTE = 1e-12
RELATIVE = 1e-9


def real(value: str) -> float | str:
    """A real value as a runner encodes it: the hexadecimal digits of the
    bits of a double, or of 'NaN', 'Infinity' or '-Infinity'."""
    shown = bytes.fromhex(value).decode("ascii")
    if shown in ("NaN", "Infinity", "-Infinity"):
        return shown
    return float(struct.unpack(">d", bytes.fromhex(shown))[0])


def reals_agree(x: str, y: str) -> bool:
    a, b = real(x), real(y)
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    return math.fabs(a - b) <= ABSOLUTE + RELATIVE * max(math.fabs(a), math.fabs(b))


def agree(a: Any, b: Any, reals: bool = False) -> bool:
    """Whether two outcomes are the same: equal, except that real values
    match within the tolerance."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(
            agree(a[key], b[key], reals or key == "reals") for key in a
        )
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(agree(x, y, reals) for x, y in zip(a, b, strict=True))
    if reals and isinstance(a, str) and isinstance(b, str):
        return reals_agree(a, b)
    return type(a) is type(b) and a == b


def plain_differences(a: Any, b: Any) -> list[str]:
    """No difference when two outcomes agree, and otherwise one that the
    report does not describe further."""
    return [] if agree(a, b) else [""]


# Audit outcomes, compared by the rules of conventions.md (Comparison across
# languages) and fixtures/conformance/audits/README.md (Comparison).

SPECIAL_REALS = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}
# The statistics of a near_threshold finding that its solver, or its
# comparisons with rank_tolerance, decide, which may then differ.
SOLVED = {
    "outcome.separation": ("verdict", "optimum", "margin", "bounds", "columns_involved"),
    "identifiability.gram_rank": (
        "rank",
        "verdict",
        "vanishing_parameters",
        "confounded_parameters",
        "smallest_eigenvalue",
    ),
}
# The members of a results document that record what wrote it, which are not
# compared, besides the package version in 'versions'.
WRITER_MEMBERS = ("created", "software")
# The most differences shown for one outcome.
DIFFERENCES_SHOWN = 12
PLACEHOLDER = re.compile(r"(\{[a-z][a-z0-9_]*\})")


@functools.cache
def registry_entries() -> dict[str, dict[str, Any]]:
    """The entries of spec/compiled/registry.json by identifier."""
    registry = json.loads((ROOT / "spec" / "compiled" / "registry.json").read_bytes())
    return {entry["id"]: entry for entry in registry["entries"]}


def json_text(value: str) -> Any:
    """The value of JSON text that an outcome holds as hexadecimal digits."""
    return json.loads(bytes.fromhex(value).decode("utf-8"))


def brief(value: Any) -> str:
    shown = json.dumps(value, ensure_ascii=True, sort_keys=True)
    return shown if len(shown) <= SHOWN else shown[: SHOWN - 3] + "..."


def same_scalar(a: Any, b: Any) -> bool:
    """Whether two JSON scalars are equal: numbers by value, whether written as
    integers or not, and every other value with its type."""
    numbers = (int, float)
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, numbers) and isinstance(b, numbers):
        return bool(a == b)
    return type(a) is type(b) and a == b


def json_differences(a: Any, b: Any, path: str) -> list[str]:
    """Where two JSON values differ, as JSON Pointers with the two values."""
    if isinstance(a, dict) and isinstance(b, dict):
        found = []
        for key in sorted(set(a) | set(b)):
            here = f"{path}/{key}"
            if key not in a or key not in b:
                found.append(f"{here} is present in only one of them")
            else:
                found += json_differences(a[key], b[key], here)
        return found
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path} has {len(a)} and {len(b)} elements"]
        return [
            line
            for i, (x, y) in enumerate(zip(a, b, strict=True))
            for line in json_differences(x, y, f"{path}/{i}")
        ]
    if (isinstance(a, dict | list) or isinstance(b, dict | list)) or not same_scalar(a, b):
        return [f"{path}: {brief(a)} and {brief(b)}"]
    return []


def reals_match(x: Any, y: Any, check: str, name: str) -> bool:
    """Whether two values of a real statistic match within the tolerance of
    conventions.md, with its exceptions for design.collinearity,
    design.scale_disparity, identifiability.gram_rank and outcome.separation,
    whose tolerance is the parameter bound_tolerance of its entry. 'NaN',
    'Infinity' and '-Infinity' match only themselves."""
    if isinstance(x, str) or isinstance(y, str):
        return bool(x == y)
    m = max(math.fabs(x), math.fabs(y))
    if check == "design.collinearity" and name in ("gvif", "gvif_per_df"):
        return math.fabs(x - y) <= ABSOLUTE + max(RELATIVE, 1e-13 * m) * m
    if check == "design.scale_disparity" and name == "condition_number":
        return math.fabs(x - y) <= ABSOLUTE + max(RELATIVE, 1e-14 * m) * m
    if check == "identifiability.gram_rank" and name == "smallest_eigenvalue":
        return math.fabs(x - y) <= ABSOLUTE + RELATIVE * max(1.0, m)
    if check == "outcome.separation":
        parameter = registry_entries()[check]["parameters"]["bound_tolerance"]
        tolerance = float(parameter["value"])
        return math.fabs(x - y) <= (tolerance if name == "bounds" else tolerance * max(1, m))
    return math.fabs(x - y) <= ABSOLUTE + RELATIVE * m


def point_digits(digits: str, places: int) -> str:
    if places == 0:
        return digits
    digits = "0" * max(0, places + 1 - len(digits)) + digits
    return digits[: len(digits) - places] + "." + digits[len(digits) - places :]


def real_text(x: float, places: int) -> str:
    """A real as a message renders it (registry.md, Messages): in scientific
    notation from 1e15, otherwise with 'places' decimal places and no sign on
    a rounded zero, as 'under' and the smallest positive value at that number
    of places for a positive double that rounds to zero, and NaN and the
    infinities by name."""
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Infinity" if x > 0 else "-Infinity"
    if math.fabs(x) >= 1e15:
        return format(x, f".{places}e")
    shown = format(x, f"z.{places}f")
    if x > 0 and not any("1" <= char <= "9" for char in shown):
        return "under " + point_digits("1", places)
    return shown


def written_real(finding: dict[str, Any], name: str) -> float | None:
    value = finding.get("statistics", {}).get(name, {}).get("value")
    if value is None:
        return None
    return SPECIAL_REALS[value] if isinstance(value, str) else float(value)


def message_form(finding: dict[str, Any]) -> tuple[str, list[str]] | None:
    """The form of its message that the text of a finding renders, the
    template or the fallback, with the renderings of its arguments other than
    real statistics. A real statistic must render the value that the finding
    writes. None when the text renders neither form."""
    entry = registry_entries().get(finding["check"])
    message = entry["messages"].get(finding["message"]["id"]) if entry else None
    if entry is None or message is None:
        return None
    for form in ("template", "fallback"):
        template = message.get(form)
        if template is None:
            continue
        pattern = []
        for i, piece in enumerate(PLACEHOLDER.split(template)):
            if i % 2 == 0:
                pattern.append(re.escape(piece))
                continue
            arg = message["args"][piece[1:-1]]
            kind = None
            if arg["source"] == "statistic":
                kind = entry["statistics"][arg["name"]]["kind"]
            if kind != "real":
                pattern.append("(.*?)")
                continue
            value = written_real(finding, arg["name"])
            if value is None:
                break
            pattern.append(re.escape(real_text(value, int(arg["digits"]))))
        else:
            found = re.fullmatch("".join(pattern), finding["message"]["text"], re.DOTALL)
            if found is not None:
                return form, list(found.groups())
    return None


def messages_match(actual: dict[str, Any], expected: dict[str, Any]) -> bool:
    """Whether the messages of two findings match: the same identifier, both
    texts rendering its template or both its fallback, every argument other
    than a real statistic rendered identically, the two values of every real
    statistic that the form renders matching within the tolerance, and each
    text rendering the values of its own finding."""
    if actual["message"]["id"] != expected["message"]["id"]:
        return False
    form = message_form(actual)
    if form is None or form != message_form(expected):
        return False
    check = expected["check"]
    entry = registry_entries()[check]
    message = entry["messages"][expected["message"]["id"]]
    for placeholder, arg in message["args"].items():
        name = arg["name"]
        if (
            arg["source"] != "statistic"
            or entry["statistics"][name]["kind"] != "real"
            or "{" + placeholder + "}" not in message[form[0]]
        ):
            continue
        x, y = written_real(actual, name), written_real(expected, name)
        if x is None or y is None:
            return False
        if math.isfinite(x) and math.isfinite(y):
            if not reals_match(x, y, check, name):
                return False
        elif not (x == y or (math.isnan(x) and math.isnan(y))):
            return False
    return True


def near_threshold(finding: dict[str, Any]) -> bool:
    proximity = finding.get("status", {}).get("threshold_proximity", {})
    return bool(proximity.get("value") == "near_threshold")


def finding_differences(
    actual: dict[str, Any], expected: dict[str, Any], exact: list[str], label: str
) -> list[str]:
    """How a finding differs from another: exactly, apart from the values of
    real statistics, which match within the tolerance or bit for bit for
    those that 'exact' lists, and the message, which matches by its values.
    A finding that is near_threshold in either may differ in its finding
    status, its message and its threshold_proximity, and a finding of
    outcome.separation or identifiability.gram_rank also in the statistics
    that its solver or rank_tolerance decides."""
    check = expected.get("check")
    if actual.get("check") != check:
        return [f"{label}: a finding of {actual.get('check')} and one of {check}"]
    near = near_threshold(actual) or near_threshold(expected)
    solved = SOLVED.get(check, ()) if near else ()
    reals = [
        name
        for name, statistic in expected.get("statistics", {}).items()
        if statistic.get("kind") in ("real", "reals") and name not in solved
    ]

    def strip(finding: dict[str, Any]) -> dict[str, Any]:
        finding = json.loads(json.dumps(finding))
        statistics = finding.get("statistics", {})
        for name in reals:
            if statistics.get(name, {}).get("value") is not None:
                statistics[name]["value"] = "real"
        if "message" in finding:
            finding["message"]["text"] = "text"
        if near:
            for name in ("finding", "threshold_proximity"):
                finding.get("status", {}).pop(name, None)
            finding.pop("message", None)
            for name in solved:
                statistics.pop(name, None)
        return finding

    found = json_differences(strip(actual), strip(expected), label)
    for name in reals:
        x = actual.get("statistics", {}).get(name, {}).get("value")
        y = expected["statistics"][name].get("value")
        if x is None or y is None:
            continue
        xs = x if isinstance(x, list) else [x]
        ys = y if isinstance(y, list) else [y]
        if f"{check}:{name}" in exact:
            same = [bits_of(v) for v in xs] == [bits_of(v) for v in ys]
        else:
            same = len(xs) == len(ys) and all(
                reals_match(a, b, check, name) for a, b in zip(xs, ys, strict=True)
            )
        if not same:
            found.append(f"{label}/statistics/{name}: {brief(x)} and {brief(y)}")
    if not near and "message" in expected and "message" in actual:
        if not messages_match(actual, expected):
            found.append(
                f"{label}/message: {brief(actual['message'])} and {brief(expected['message'])}"
            )
    return found


def bits_of(value: Any) -> str:
    return value if isinstance(value, str) else struct.pack(">d", float(value)).hex()


def document_differences(a: dict[str, Any], b: dict[str, Any], exact: list[str]) -> list[str]:
    """How two results documents differ: every member exactly apart from
    created, software and the package version, which are not compared, and
    the findings by finding_differences()."""

    def compared(document: dict[str, Any]) -> dict[str, Any]:
        document = {key: value for key, value in document.items() if key not in WRITER_MEMBERS}
        if isinstance(document.get("versions"), dict):
            document["versions"] = {
                key: value for key, value in document["versions"].items() if key != "package"
            }
        document.pop("findings", None)
        return document

    found = json_differences(compared(a), compared(b), "")
    x, y = a.get("findings", []), b.get("findings", [])
    if len(x) != len(y):
        return [*found, f"/findings has {len(x)} and {len(y)} elements"]
    for i, (first, second) in enumerate(zip(x, y, strict=True)):
        found += finding_differences(first, second, exact, f"/findings/{i}")
    return found


def audit_differences(a: Any, b: Any, exact: list[str]) -> list[str]:
    """How the outcome a of an audit part differs from b, another run's
    outcome or the expected one. The expected findings are compared with the
    findings of the checks of the case in the run's document, and the runs'
    documents and sidecars with each other. Issues, errors and warnings must
    agree exactly."""
    if a is None or b is None:
        return [] if a is b else [""]
    if "findings" in a and "findings" not in b:
        a, b = b, a
    if "findings" in b:
        if set(a) != {"document", "sidecar"}:
            return [""]
        expected = json_text(b["findings"])
        checks = set(expected["checks"])
        document = json_text(a["document"])
        findings = [f for f in document.get("findings", []) if f.get("check") in checks]
        wanted = expected["findings"]
        if len(findings) != len(wanted):
            return [f"{len(findings)} findings of the checks of the case, {len(wanted)} expected"]
        return [
            line
            for i, (actual, finding) in enumerate(zip(findings, wanted, strict=True))
            for line in finding_differences(
                actual, finding, expected["exact"], f"finding {i + 1} ({finding.get('check')})"
            )
        ]
    if "document" in a and "document" in b:
        found = []
        if not agree(a.get("warnings"), b.get("warnings")):
            found.append("the warnings differ")
        if set(a) != set(b):
            found.append("the members of the outcomes differ")
        found += document_differences(json_text(a["document"]), json_text(b["document"]), exact)
        found += json_differences(json_text(a["sidecar"]), json_text(b["sidecar"]), "sidecar")
        return found
    return plain_differences(a, b)


def show_audit(outcome: dict[str, Any] | None) -> list[str]:
    """Lines that describe an audit outcome."""
    if outcome is not None and "findings" in outcome:
        expected = json_text(outcome["findings"])
        count = len(expected["findings"])
        return [f"{count} findings of {', '.join(expected['checks'])}"]
    if outcome is not None and "document" in outcome:
        count = len(json_text(outcome["document"]).get("findings", []))
        rest = {key: value for key, value in outcome.items() if key == "warnings"}
        return [f"a document with {count} findings, and its sidecar", *show(rest)]
    return show(outcome)


# Outcomes of the pathology zoo, compared with each other by
# audit_differences() and with expected.json of each directory by the rules
# of fixtures/zoo/README.md (Comparison).

# The line of the summary and the file of the records of the zoo.
ZOO = "zoo"
ZOO_PARTS = ("internal", "shareable")
# The defaults of the status fields that an expected finding leaves out.
STATUS_DEFAULTS = {
    "availability": "available",
    "assessability": "adequate",
    "threshold_proximity": "clear",
    "validation": "descriptive",
}


def zoo_list() -> dict[str, Path]:
    """The directories of the pathology zoo that parity/corpora.json names, by
    identifier in the order of its index.json, which must list every
    directory of the zoo and no other."""
    entry = json.loads((HERE / "corpora.json").read_text(encoding="utf-8")).get("zoo")
    if not isinstance(entry, dict) or entry.get("kind") != "zoo":
        raise HarnessError("parity/corpora.json has no member 'zoo' of the kind 'zoo'.")
    index = ROOT / entry["index"]
    if not index.is_file():
        raise HarnessError(f"{entry['index']} is missing.")
    listed = {
        fixture["id"]: f"{fixture['id']}-{fixture['name']}"
        for fixture in json.loads(index.read_text(encoding="utf-8"))["fixtures"]
    }
    present = sorted(path.name for path in index.parent.iterdir() if path.is_dir())
    problems = [
        f"{index.parent.relative_to(ROOT).as_posix()}/{name} is not listed in {entry['index']}"
        for name in present
        if name not in listed.values()
    ]
    problems += [
        f"{name} is listed in {entry['index']} but missing"
        for name in listed.values()
        if name not in present
    ]
    if problems:
        raise HarnessError("\n".join(problems))
    return {fixture_id: index.parent / name for fixture_id, name in listed.items()}


def expected_status(status: dict[str, Any]) -> dict[str, Any]:
    """The status of an expected finding of the zoo with the defaults filled
    in, unless the finding is not available."""
    expanded = {
        name: {"value": field} if isinstance(field, str) else field
        for name, field in status.items()
    }
    if expanded.get("availability", {}).get("value") == "not_available":
        return expanded
    for name, value in STATUS_DEFAULTS.items():
        expanded.setdefault(name, {"value": value})
    return expanded


def zoo_statistic_differences(
    actual: dict[str, Any], wanted: dict[str, Any], check: str, name: str, here: str
) -> list[str]:
    """How a written statistic differs from its expectation."""
    found = []
    if "count_class" in wanted and actual.get("count_class") != wanted["count_class"]:
        found.append(
            f"{here}: count class {brief(actual.get('count_class'))} and "
            f"{brief(wanted['count_class'])}"
        )
    value = actual.get("value")
    if wanted.get("absent"):
        found.append(f"{here}: {brief(value)} and absent")
    elif "ratio" in wanted:
        numerator, denominator = wanted["ratio"]
        if not (isinstance(value, int | float) and value == numerator / denominator):
            found.append(f"{here}: {brief(value)} and the ratio {brief(wanted['ratio'])}")
    elif "interval" in wanted:
        low, high = wanted["interval"]
        values = value if isinstance(value, list) else [value]
        numeric = all(isinstance(v, int | float) and not isinstance(v, bool) for v in values)
        if not values or not numeric or any(v < low or v > high for v in values):
            found.append(f"{here}: {brief(value)} and the interval {brief(wanted['interval'])}")
    elif actual.get("kind") in ("real", "reals"):
        xs = value if isinstance(value, list) else [value]
        ys = wanted["value"] if isinstance(wanted["value"], list) else [wanted["value"]]
        if len(xs) != len(ys) or not all(
            reals_match(x, y, check, name) for x, y in zip(xs, ys, strict=False)
        ):
            found.append(f"{here}: {brief(value)} and {brief(wanted['value'])}")
    elif json_differences(value, wanted["value"], ""):
        found.append(f"{here}: {brief(value)} and {brief(wanted['value'])}")
    return found


def zoo_finding_differences(
    actual: dict[str, Any],
    wanted: dict[str, Any],
    samples: dict[str, Any],
    privacy: str,
    here: str,
) -> list[str]:
    """How a finding of a run differs from its expectation in a mode."""
    check = wanted["check"]
    shareable = privacy == "shareable"
    status = actual.get("status", {})
    availability = status.get("availability", {})
    if (
        shareable
        and actual.get("tier") != "T0"
        and availability.get("reason") == "privacy_suppressed"
        and availability.get("detail") == "decision"
    ):
        return []
    expanded = expected_status(wanted["status"])
    if json_differences(status, expanded, ""):
        return [f"{here}/status: {brief(status)} and {brief(expanded)}"]
    if availability.get("value") != "available":
        return []
    found = []
    message = actual.get("message", {}).get("id")
    if message != wanted.get("message"):
        found.append(f"{here}/message: {brief(message)} and {brief(wanted.get('message'))}")
    statistics = actual.get("statistics", {})
    expected = wanted.get("statistics", {})
    for name, statistic_wanted in expected.items():
        where = f"{here}/statistics/{name}"
        statistic = statistics.get(name)
        if statistic is None:
            if not statistic_wanted.get("absent"):
                found.append(f"{where}: nothing and {brief(statistic_wanted)}")
            continue
        if shareable and statistic.get("value") is None:
            if (
                "count_class" in statistic_wanted
                and statistic.get("count_class") != statistic_wanted["count_class"]
            ):
                found.append(
                    f"{where}: count class {brief(statistic.get('count_class'))} and "
                    f"{brief(statistic_wanted['count_class'])}"
                )
            continue
        found += zoo_statistic_differences(statistic, statistic_wanted, check, name, where)
    for name, statistic in statistics.items():
        if name not in expected and statistic.get("kind") not in ("real", "reals"):
            found.append(f"{here}/statistics/{name}: {brief(statistic.get('value'))} and nothing")
    sample = samples[registry_entries()[check]["sample"]]
    support = actual.get("support", {})
    rows = support.get("rows", {}).get("value")
    if (not shareable or rows is not None) and rows != sample["rows"]:
        found.append(f"{here}/support/rows: {brief(rows)} and {sample['rows']}")
    contributors = support.get("contributors", {})
    distinct = contributors.get("distinct", {}).get("value")
    if (
        contributors.get("basis") != sample["basis"]
        or contributors.get("dominated") != sample["dominated"]
        or ((not shareable or distinct is not None) and distinct != sample["distinct"])
    ):
        found.append(f"{here}/support/contributors: {brief(contributors)} and {brief(sample)}")
    return found


def zoo_differences(outcome: Any, expected: dict[str, Any], privacy: str) -> list[str]:
    """How the outcome of a run of a directory of the zoo differs from its
    expected.json, as lines that name the JSON Pointer of the member and both
    values. validate_results() on the shareable document runs in the tests of
    the packages."""
    if outcome is None:
        return ["no outcome"]
    issue = expected.get("issue")
    if issue is not None:
        wanted = encode({"issues": [issue]})
        return [] if agree(outcome, wanted) else [f"/issue: {brief(issue)}"]
    if "document" not in outcome:
        return ["/findings: " + "; ".join(show(outcome))]
    found = []
    if outcome.get("warnings"):
        found.append("the run warns: " + "; ".join(show({"warnings": outcome["warnings"]})))
    findings = json_text(outcome["document"]).get("findings", [])
    wanted = expected["findings"]

    def key(finding: dict[str, Any]) -> str:
        return json.dumps([finding.get("check"), finding.get("scope")], sort_keys=True)

    keys = [key(finding) for finding in findings]
    wanted_keys = [key(finding) for finding in wanted]
    if keys != wanted_keys:
        beyond = [k for k in keys if k not in wanted_keys]
        lacks = [k for k in wanted_keys if k not in keys]
        order = ", in another order" if sorted(keys) == sorted(wanted_keys) else ""
        return [
            *found,
            f"/findings: the run has {beyond} beyond the expectation and lacks {lacks}{order}",
        ]
    for i, (actual, finding) in enumerate(zip(findings, wanted, strict=True)):
        found += zoo_finding_differences(
            actual, finding, expected["samples"], privacy, f"/findings/{i}"
        )
    return found


def zoo_part_differences(a: Any, b: Any) -> list[str]:
    """How the outcome a of a part of the zoo differs from b, the outcome of
    another run, compared by audit_differences(), or the expected one, held
    as {'zoo': expected.json, 'privacy': mode}."""
    if isinstance(a, dict) and "zoo" in a:
        a, b = b, a
    if isinstance(b, dict) and "zoo" in b:
        return zoo_differences(a, b["zoo"], b["privacy"])
    return audit_differences(a, b, [])


def show_zoo(outcome: dict[str, Any] | None) -> list[str]:
    """Lines that describe an outcome of the zoo or its expectation."""
    if outcome is not None and "zoo" in outcome:
        expected = outcome["zoo"]
        if "issue" in expected:
            return [f"the issue {expected['issue']['code']}"]
        return [f"{len(expected['findings'])} findings in {outcome['privacy']} mode"]
    return show_audit(outcome)


class Report:
    def __init__(self, runs: list[tuple[dict[str, Any], dict[tuple[Any, Any, Any], Any]]]) -> None:
        self.runs = runs
        self.names = [header["run"] for header, _ in runs]
        self.mismatches = 0
        self.only_codes = code_languages()

    def mismatch(self, title: str, lines: list[str]) -> None:
        self.mismatches += 1
        print(f"\nMISMATCH {title}")
        for line in lines:
            print(f"  {line}")

    def wrong_language_codes(self, language: str, outcome: dict[str, Any]) -> list[str]:
        codes = [
            bytes.fromhex(issue.get("code", "")).decode("utf-8", "replace")
            for key in ("issues", "warnings")
            for issue in outcome.get(key, []) or []
            if isinstance(issue, dict)
        ]
        return [
            code
            for code in codes
            if code in self.only_codes and language not in self.only_codes[code]
        ]

    def compare(
        self,
        title: str,
        expected: dict[str, Any] | None,
        outcomes: dict[str, dict[str, Any] | None],
        differences: Callable[[Any, Any], list[str]] = plain_differences,
        describe: Callable[[dict[str, Any] | None], list[str]] = show,
    ) -> bool:
        """Compare the outcomes of the runs with each other and with the
        expected outcome, and report a mismatch. 'differences' lists how one
        outcome differs from another, or from the expected one, and nothing
        when they agree, and 'describe' gives the lines that show an outcome.
        Returns whether they agree."""
        groups: list[tuple[dict[str, Any] | None, list[str]]] = []
        for name, outcome in outcomes.items():
            for found, names in groups:
                if not differences(outcome, found):
                    names.append(name)
                    break
            else:
                groups.append((outcome, [name]))
        problems = []
        if expected is not None:
            wrong = [name for name, outcome in outcomes.items() if differences(outcome, expected)]
            if wrong:
                verb = "differs" if len(wrong) == 1 else "differ"
                problems.append(f"{words(wrong)} {verb} from the expected outcome")
        if len(groups) > 1:
            problems.append(f"the runs give {len(groups)} different outcomes")
        for name, outcome in outcomes.items():
            language = self.language(name)
            for code in self.wrong_language_codes(language, outcome or {}):
                only = words(self.only_codes[code])
                problems.append(f"{name} reports {code}, which only {only} can raise")
        if not problems:
            return True

        def details(found: list[str], indent: str) -> list[str]:
            found = [line for line in found if line]
            shown = [f"{indent}{line}" for line in found[:DIFFERENCES_SHOWN]]
            if len(found) > DIFFERENCES_SHOWN:
                shown.append(f"{indent}and {len(found) - DIFFERENCES_SHOWN} more differences")
            return shown

        lines = list(problems)
        if expected is not None:
            lines += ["expected:"] + [f"  {line}" for line in describe(expected)]
        reference = expected if expected is not None else groups[0][0]
        for i, (outcome, names) in enumerate(groups):
            if expected is not None and not differences(outcome, expected):
                lines.append(f"{words(names)}: as expected")
            else:
                lines += [f"{words(names)}:"] + [f"  {line}" for line in describe(outcome)]
                lines += details(differences(outcome, reference), "  ")
            if i > 0 and expected is not None:
                found = details(differences(outcome, groups[0][0]), "    ")
                if found:
                    lines += [f"  against {words(groups[0][1])}:", *found]
            if (
                outcome
                and reference
                and outcome is not reference
                and "canonical" in outcome
                and "canonical" in reference
                and outcome["canonical"] != reference["canonical"]
            ):
                lines.append(f"  {first_difference(reference['canonical'], outcome['canonical'])}")
        self.mismatch(title, lines)
        return False

    def language(self, name: str) -> str:
        for header, _ in self.runs:
            if header["run"] == name:
                return str(header["language"])
        raise KeyError(name)


def index(records: list[dict[str, Any]]) -> dict[tuple[Any, Any, Any], Any]:
    return {(record["file"], record["id"], record["part"]): record["outcome"] for record in records}


def compare_runs(
    corpus: Path,
    listed: list[dict[str, Any]],
    artefacts: list[str],
    runs: list[tuple[dict[str, Any], list[dict[str, Any]]]],
    zoo: dict[str, Path] | None = None,
) -> int:
    """Compare the outcomes of every run, print every mismatch and a summary,
    and return the number of mismatches."""
    indexed = [(header, index(records)) for header, records in runs]
    report = Report(indexed)
    seen: set[tuple[Any, Any, Any]] = set()
    rows: list[Row] = []
    for entry in listed:
        name = entry["file"]
        cases = json.loads((corpus / name).read_text(encoding="utf-8"))["cases"]
        row = Row(name, len(cases), report.names)
        rows.append(row)
        if "pending" in entry:
            row.pending = entry["pending"]
            continue
        pending = entry.get("pending_parts", {})
        row.pending_parts = sorted(set(pending.values()))
        for header, outcomes in indexed:
            failure = outcomes.get((name, None, None))
            if failure is not None:
                report.mismatch(f"{name} in {header['run']}", show(failure))
        for case in cases:
            languages = case.get("languages", list(LANGUAGES))
            running = [header["run"] for header, _ in indexed if header["language"] in languages]
            for run_name in running:
                row.ran[run_name] += 1
            row.shared += all(language in languages for language in LANGUAGES)
            expected = {
                part: encode(outcome)
                for part, outcome in expected_parts(entry["kind"], case).items()
            }
            rule: dict[str, Any] = {}
            if entry["kind"] == "audit":
                exact = case.get("exact", [])
                rule = {
                    "differences": lambda a, b, exact=exact: audit_differences(a, b, exact),
                    "describe": show_audit,
                }
            parts = set(expected)
            for header, outcomes in indexed:
                if header["run"] in running:
                    parts |= {key[2] for key in outcomes if key[:2] == (name, case["id"])}
            agreed = True
            for part in sorted(parts):
                key = (name, case["id"], part)
                seen.add(key)
                found = {
                    header["run"]: outcomes.get(key)
                    for header, outcomes in indexed
                    if header["run"] in running
                }
                title = f"{name} {case['id']} [{part}]"
                if part in pending:
                    row.waiting += 1
                    names = [run_name for run_name, outcome in found.items() if outcome is not None]
                    if names:
                        report.mismatch(title, [f"{words(names)}: an outcome for a pending part"])
                        agreed = False
                    continue
                row.parts += 1
                if part not in expected:
                    names = [run_name for run_name, outcome in found.items() if outcome is not None]
                    report.mismatch(
                        title, [f"{words(names)}: an outcome for a part the case lacks"]
                    )
                    agreed = False
                    continue
                agreed = report.compare(title, expected[part], found, **rule) and agreed
            row.mismatched += not agreed
    if zoo is not None:
        row = Row(ZOO, len(zoo), report.names)
        rows.append(row)
        for fixture_id, directory in zoo.items():
            for run_name in report.names:
                row.ran[run_name] += 1
            row.shared += 1
            expected_json = json.loads((directory / "expected.json").read_text(encoding="utf-8"))
            agreed = True
            for part in ZOO_PARTS:
                key = (ZOO, fixture_id, part)
                seen.add(key)
                found = {header["run"]: outcomes.get(key) for header, outcomes in indexed}
                row.parts += 1
                agreed = (
                    report.compare(
                        f"{ZOO} {fixture_id} [{part}]",
                        {"zoo": expected_json, "privacy": part},
                        found,
                        differences=zoo_part_differences,
                        describe=show_zoo,
                    )
                    and agreed
                )
            row.mismatched += not agreed
    expected_artefact = expected_artefacts(artefacts)
    row = Row(FILES, len(expected_artefact), report.names)
    rows.append(row)
    for (artefact, part), expected in expected_artefact.items():
        key = ("artefacts", artefact, part)
        seen.add(key)
        found = {header["run"]: outcomes.get(key) for header, outcomes in indexed}
        for run_name in found:
            row.ran[run_name] += 1
        row.shared += 1
        row.parts += 1
        row.mismatched += not report.compare(f"spec/{artefact} [{part}]", expected, found)
    for header, outcomes in indexed:
        for key in outcomes:
            if key not in seen and key[1] is not None:
                title = f"{key[0]} {key[1]} [{key[2]}]"
                report.mismatch(title, [f"{header['run']}: an outcome for a case the corpus lacks"])
    print_summary(rows, report.names)
    return report.mismatches


class Row:
    """A line of the summary: one corpus file, or the vendored files of spec/."""

    def __init__(self, name: str, cases: int, runs: list[str]) -> None:
        self.name = name
        self.cases = cases
        self.ran = dict.fromkeys(runs, 0)
        self.shared = 0
        self.parts = 0
        self.mismatched = 0
        self.pending: str | None = None
        # The parts that wait for a milestone, and the milestones.
        self.waiting = 0
        self.pending_parts: list[str] = []

    def cells(self, runs: list[str]) -> list[str]:
        if self.pending:
            return [
                self.name,
                str(self.cases),
                *["-" for _ in runs],
                "-",
                f"pending {self.pending}",
            ]
        result = f"{self.mismatched} mismatched" if self.mismatched else "identical"
        if self.waiting:
            result += f", {self.waiting} parts pending {' and '.join(self.pending_parts)}"
        ran = [str(self.ran[name]) for name in runs]
        return [self.name, str(self.cases), *ran, str(self.shared), result]


def print_summary(rows: list[Row], runs: list[str]) -> None:
    """Print a table with a line for each corpus file and a line of totals."""
    header = ["Corpus", "Cases", *runs, "Both languages", "Result"]
    active = [row for row in rows if not row.pending]
    total = Row("Total", sum(row.cases for row in rows), runs)
    for row in active:
        for name in runs:
            total.ran[name] += row.ran[name]
        total.shared += row.shared
        total.parts += row.parts
        total.mismatched += row.mismatched
        total.waiting += row.waiting
        total.pending_parts = sorted(set(total.pending_parts) | set(row.pending_parts))
    table = [header] + [row.cells(runs) for row in rows] + [total.cells(runs)]
    widths = [max(len(line[i]) for line in table) for i in range(len(header))]
    print()
    for line in table:
        cells = [line[0].ljust(widths[0])]
        cells += [cell.rjust(width) for cell, width in zip(line[1:-1], widths[1:-1], strict=True)]
        print("  ".join([*cells, line[-1]]))
    pending = sum(row.cases for row in rows if row.pending)
    corpora = [row for row in active if row.name != FILES]
    files = [row for row in active if row.name == FILES]
    waiting = (
        f" {pending} cases wait for the milestone that implements what they test."
        if pending
        else ""
    )
    parts = sum(row.waiting for row in corpora)
    if parts:
        waiting += f" {parts} parts of cases that ran wait for the milestone that implements them."
    print(
        f"\n{sum(row.cases for row in corpora)} cases were run, "
        f"{sum(row.shared for row in corpora)} of them in both languages, "
        f"with {sum(row.parts for row in corpora)} outcomes compared. "
        f"The vendored files of spec/ gave {sum(row.parts for row in files)} outcomes."
        f"{waiting}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--python", default=sys.executable, help="interpreter with mixedcheck and PyYAML"
    )
    parser.add_argument("--rscript", default="Rscript", help="the Rscript of the R to run")
    parser.add_argument("--r-lib", help="a library that holds the installed R package")
    parser.add_argument(
        "--r-locale",
        action="append",
        help="a locale for LC_ALL in which to run R, repeated for several runs "
        f"(default: {' and '.join(DEFAULT_R_LOCALES)})",
    )
    parser.add_argument("--corpus", default=str(ROOT / "fixtures" / "conformance"))
    parser.add_argument(
        "--keep", help="a directory for the plan and the outputs of the runs, which are kept"
    )
    parser.add_argument(
        "--compare-only",
        action="store_true",
        help="compare the outputs already in the --keep directory",
    )
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    if args.compare_only and not args.keep:
        parser.error("--compare-only needs --keep")
    try:
        return harness(args)
    except HarnessError as err:
        print(f"The parity harness cannot run.\n{err}", file=sys.stderr)
        return 2


def harness(args: argparse.Namespace) -> int:
    corpus = Path(args.corpus).resolve()
    listed = corpus_list(corpus)
    zoo = zoo_list()
    artefacts = vendored_artefacts()
    locales = args.r_locale or list(DEFAULT_R_LOCALES)
    with tempfile.TemporaryDirectory(prefix="mixedcheck-parity-") as scratch:
        work = Path(args.keep).resolve() if args.keep else Path(scratch)
        work.mkdir(parents=True, exist_ok=True)
        outputs = [("Python", work / "python.jsonl")] + [
            (f"R (LC_ALL={locale})", work / f"r-{locale}.jsonl") for locale in locales
        ]
        if not args.compare_only:
            plan = {
                "corpus": str(corpus),
                "corpora": [entry for entry in listed if "pending" not in entry],
                "zoo": list(zoo),
                "artefacts": artefacts,
            }
            (work / "plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
            env = dict(os.environ)
            elapsed = run(
                [
                    args.python,
                    str(HERE / "run_python.py"),
                    str(work / "plan.json"),
                    str(outputs[0][1]),
                ],
                env,
                "Python",
            )
            print(f"Python ran in {elapsed:.1f} s.")
            for locale, (name, path) in zip(locales, outputs[1:], strict=True):
                env = dict(os.environ, LC_ALL=locale)
                if args.r_lib:
                    libraries = [str(Path(args.r_lib).resolve()), os.environ.get("R_LIBS", "")]
                    env["R_LIBS"] = os.pathsep.join(item for item in libraries if item)
                command = [
                    args.rscript,
                    str(HERE / "run_r.R"),
                    str(work / "plan.json"),
                    str(path),
                    name,
                ]
                elapsed = run(command, env, name)
                print(f"{name} ran in {elapsed:.1f} s.")
        runs = [read_output(path) for _, path in outputs]
        for (name, _), (header, _) in zip(outputs, runs, strict=True):
            if header["run"] != name:
                raise HarnessError(f"The output for {name} was written by the run {header['run']}.")
        check_locales(locales, [header for header, _ in runs[1:]])
        print()
        for header, _ in runs:
            details = ", ".join(
                f"{key} {value}" for key, value in header.items() if key not in ("run", "language")
            )
            print(f"{header['run']}: {details}")
            if header.get("yaml") is None:
                print(
                    f"  {header['run']} cannot read YAML, so the cases of yaml/ give E3001 there."
                )
        mismatches = compare_runs(corpus, listed, artefacts, runs, zoo)
    if mismatches:
        print(f"\n{mismatches} {'mismatch' if mismatches == 1 else 'mismatches'}.")
        return 1
    print("\nEvery case gave the expected outcome in every run, and the runs agree.")
    return 0


def check_locales(locales: list[str], headers: list[dict[str, Any]]) -> None:
    """Stop when R did not run in the locale requested, since a run that
    falls back to another locale would test nothing new."""
    for locale, header in zip(locales, headers, strict=True):
        wants_utf8 = locale.lower().replace("-", "").endswith("utf8")
        if bool(header.get("utf8")) != wants_utf8:
            raise HarnessError(
                f"R ran with LC_CTYPE '{header.get('locale')}' instead of '{locale}'. "
                "Choose a locale that the system provides with --r-locale."
            )


if __name__ == "__main__":
    sys.exit(main())
