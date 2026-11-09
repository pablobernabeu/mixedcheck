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
import hashlib
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import time
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
    ) -> bool:
        """Compare the outcomes of the runs with each other and with the
        expected outcome, and report a mismatch. Returns whether they agree."""
        groups: list[tuple[dict[str, Any] | None, list[str]]] = []
        for name, outcome in outcomes.items():
            for found, names in groups:
                if agree(found, outcome):
                    names.append(name)
                    break
            else:
                groups.append((outcome, [name]))
        problems = []
        if expected is not None:
            wrong = [name for name, outcome in outcomes.items() if not agree(outcome, expected)]
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
        lines = list(problems)
        if expected is not None:
            lines += ["expected:"] + [f"  {line}" for line in show(expected)]
        reference = expected if expected is not None else groups[0][0]
        for outcome, names in groups:
            if expected is not None and agree(outcome, expected):
                lines.append(f"{words(names)}: as expected")
                continue
            lines += [f"{words(names)}:"] + [f"  {line}" for line in show(outcome)]
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
                row.parts += 1
                if part not in expected:
                    names = [run_name for run_name, outcome in found.items() if outcome is not None]
                    report.mismatch(
                        title, [f"{words(names)}: an outcome for a part the case lacks"]
                    )
                    agreed = False
                    continue
                agreed = report.compare(title, expected[part], found) and agreed
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
        mismatches = compare_runs(corpus, listed, artefacts, runs)
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
