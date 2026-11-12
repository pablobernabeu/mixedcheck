"""The differential test of the two packages: runs the R and Python packages
on every table of the families and of the regression attacks of the
disclosure-attack harness, on generated realistic designs and on edge cases,
in internal and in shareable mode, and compares their documents after the canonical serialisation
(parity/README.md, Differential test).

Usage, from the repository root:

    python3 parity/differential/differential.py [--inputs DIR] [--generate]
        [--seeds N] [--edge-seeds N] [--widen N] [--families NAME,...]
        [--designs NAME,...] [--edges NAME,...] [--regressions NAME,...]
        [--pseudonym-cases N]
        [--python PYTHON] [--rscript RSCRIPT] [--r-lib DIR] [--r-locale LOCALE]
        [--cores N] [--shards N] [--only ID ...] [--keep DIR] [--compare-only]
        [--report FILE] [--shown N]

The script needs only the standard library of Python 3.11 or later and
parity.py beside it. PYTHON must be an interpreter with the package mixedcheck
installed, and R must find an installed mixedcheck, in DIR when it is given.
The exit status is 0 when the two packages give the same outcome for every
input and mode, 1 when an outcome differs or a run fails, and 2 when the test
cannot run.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import parity  # noqa: E402

MODES = ("internal", "shareable")
LANGUAGES = ("R", "Python")
# The classes of a comparison, in the order of the summary.
CLASSES = ("identical", "tolerance", "different")
# The most kinds of difference that the report prints.
KINDS_SHOWN = 40
# The times of a run in the report, in seconds, and their labels.
TIMES = {
    "inputs": "writing the inputs",
    "r_shards": "R in all shards",
    "python_shards": "Python in all shards",
    "comparison": "comparing",
    "total": "in all",
}
HEADINGS = {
    "identical": "Identical",
    "tolerance": "Within tolerance",
    "different": "Different",
}


class HarnessError(Exception):
    """The test cannot run."""


# Pseudonym cases.

# Labels of grouping levels for the pseudonym cases: labels whose order
# differs between locales and code-point order, labels that NFC merges,
# labels in other scripts, outside the Basic Multilingual Plane, with
# quotation marks, control characters, a noncharacter, white space, the
# empty string and labels that look like pseudonyms.
PSEUDONYM_LABELS = (
    "a", "B", "b", "A", "Z", "z", "_x", "10", "9", "-1", "\u00c1", "\u00e1", "\u00e4",
    "a\u0308", "\u00df", "ss", "\u0130", "\u0131", "\u01c5", "\ufb01", "\u212b", "\u00c5",
    "A\u030a", "\u00e9", "e\u0301", "x y", "\U0001f600", "\U0001d538", "\u2126", "\u03a9",
    "\u4e1c\u4eac", "a'b", 'a"b', "\t", "a\u0001b", "\ufffe", "", " ", "#1", "#2", "NA", "null",
)  # fmt: skip
# Grouping factors as the IR names them.
PSEUDONYM_FACTORS = (
    "school", "class", "`\u00e9l\u00e8ve`", "g", "school:class", "`\u5b66\u6821`", "subject",
)  # fmt: skip
# Ranges of code points from which random labels are drawn.
PSEUDONYM_RANGES = (
    (0x20, 0x7E), (0xA0, 0x17F), (0x300, 0x36F), (0x370, 0x3FF), (0x400, 0x4FF),
    (0x4E00, 0x4E3F), (0xFFF0, 0xFFFF), (0x1D400, 0x1D4FF), (0x1F600, 0x1F64F),
)  # fmt: skip


def pseudonym_label(rng: random.Random) -> str:
    """A label for a pseudonym case: one of PSEUDONYM_LABELS, or a string of
    one to six characters drawn from PSEUDONYM_RANGES."""
    if rng.random() < 0.6:
        return rng.choice(PSEUDONYM_LABELS)
    ranges = [rng.choice(PSEUDONYM_RANGES) for _ in range(rng.randint(1, 6))]
    return "".join(chr(rng.randint(low, high)) for low, high in ranges)


def write_pseudonym_cases(path: Path, count: int) -> None:
    """Write the pseudonym cases: each with its k, a commitment key and one
    to six findings of a check that writes labels, each with its factor, its
    labels, the distinct contributors of its support, from 1 to 50 and around
    k, and whether its largest contributors dominate. The cases depend on
    count alone."""
    rng = random.Random(1)
    cases = []
    for i in range(count):
        k = rng.randint(2, 20)
        findings = [
            {
                "factor": rng.choice(PSEUDONYM_FACTORS),
                "labels": [pseudonym_label(rng) for _ in range(rng.choice((0, 1, 1, 2, 3, 5, 9)))],
                "distinct": rng.choice((1, k - 1, k, k + 1, 50)),
                "dominated": rng.random() < 0.15,
            }
            for _ in range(rng.randint(1, 6))
        ]
        key = f"{rng.getrandbits(256):064x}"
        cases.append({"id": f"pseudonyms/{i + 1}", "k": k, "key": key, "findings": findings})
    text = json.dumps({"cases": cases}, ensure_ascii=False, indent=0)
    path.write_text(text + "\n", encoding="utf-8")


# Running the packages.


def generate(args: argparse.Namespace, inputs: Path, env: dict[str, str]) -> float:
    """Write the inputs with inputs.R and return the time it took."""
    command = [args.rscript, str(HERE / "inputs.R"), str(inputs), "--seeds", str(args.seeds)]
    command += ["--edge-seeds", str(args.edge_seeds), "--widen", str(args.widen)]
    for name in ("families", "designs", "edges", "regressions"):
        value = getattr(args, name)
        if value is not None:
            command += [f"--{name}", value]
    started = time.monotonic()
    result = subprocess.run(
        command, env=dict(env, LC_ALL="C.UTF-8"), capture_output=True, text=True, errors="replace"
    )
    if result.returncode != 0:
        raise HarnessError(f"inputs.R failed:\n{result.stdout}{result.stderr}")
    print(result.stdout.strip())
    return time.monotonic() - started


def run_task(command: list[str], env: dict[str, str], label: str) -> float:
    """Run one command and return its time in seconds, raising HarnessError
    when it fails."""
    started = time.monotonic()
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, errors="replace")
    except OSError as err:
        raise HarnessError(f"{label} cannot start: {err}") from err
    if result.returncode != 0:
        raise HarnessError(
            f"{label} failed with status {result.returncode}:\n{result.stdout}{result.stderr}"
        )
    return time.monotonic() - started


def run_packages(
    args: argparse.Namespace,
    inputs: Path,
    work: Path,
    shards: int,
    only: Path | None,
    env: dict[str, str],
) -> dict[str, float]:
    """Run every shard in both languages, at most args.cores at a time, and
    return the time that the shards of each language took in all."""
    tasks = []
    for language in LANGUAGES:
        for shard in range(shards):
            output = work / f"{language.lower()}-{shard}.jsonl.gz"
            if language == "R":
                command = [args.rscript, str(HERE / "run_r.R")]
                task_env = dict(env, LC_ALL=args.r_locale)
            else:
                command = [args.python, str(HERE / "run_python.py")]
                task_env = dict(env)
            command += [str(inputs), str(output), str(shard), str(shards)]
            if only is not None:
                command.append(str(only))
            tasks.append((language, shard, command, task_env))
    cases = work / "pseudonyms.json"
    if cases.exists():
        for language in LANGUAGES:
            output = work / f"{language.lower()}-pseudonyms.txt"
            if language == "R":
                command = [args.rscript, str(HERE / "pseudonyms.R")]
                task_env = dict(env, LC_ALL=args.r_locale)
            else:
                command = [args.python, str(HERE / "pseudonyms.py")]
                task_env = dict(env)
            tasks.append((language, -1, [*command, str(cases), str(output)], task_env))
    spent: dict[str, float] = defaultdict(float)

    def one(task: tuple[str, int, list[str], dict[str, str]]) -> tuple[str, int, float]:
        language, shard, command, task_env = task
        if shard < 0:
            elapsed = run_task(command, task_env, f"{language} pseudonym cases")
            print(f"  {language} pseudonym cases ran in {elapsed:.0f} s", flush=True)
            return language, shard, elapsed
        elapsed = run_task(command, task_env, f"{language} shard {shard}")
        print(f"  {language} shard {shard + 1} of {shards} ran in {elapsed:.0f} s", flush=True)
        return language, shard, elapsed

    with ThreadPoolExecutor(max_workers=args.cores) as pool:
        for language, _, elapsed in pool.map(one, tasks):
            spent[language] += elapsed
    return dict(spent)


# Reading outcomes.


def read_shard(path: Path) -> tuple[dict[str, Any], dict[tuple[str, str], dict[str, Any]]]:
    if not path.exists():
        raise HarnessError(f"{path} was not written.")
    with gzip.open(path, "rt", encoding="ascii") as handle:
        lines = handle.read().splitlines()
    if not lines:
        raise HarnessError(f"{path} is empty.")
    records = {}
    for line in lines[1:]:
        record = json.loads(line)
        records[(record["id"], record["mode"])] = record
    return json.loads(lines[0]), records


def unhex(value: str) -> str:
    return bytes.fromhex(value).decode("utf-8")


def decoded(x: Any) -> Any:
    """An outcome with every string decoded from its hexadecimal digits."""
    if isinstance(x, str):
        return unhex(x)
    if isinstance(x, dict):
        return {key: decoded(value) for key, value in x.items()}
    if isinstance(x, list):
        return [decoded(value) for value in x]
    return x


def describe(outcome: dict[str, Any] | None) -> str:
    """A line that describes an outcome."""
    if outcome is None:
        return "no outcome"
    if "document" in outcome:
        count = len(json.loads(bytes.fromhex(outcome["document"])).get("findings", []))
        text = f"a document with {count} findings"
    elif "issues" in outcome:
        text = " | ".join(parity.show_issue(issue) for issue in outcome["issues"])
    elif "error" in outcome:
        text = f"error {parity.text(outcome['error'])}"
    else:
        text = json.dumps(sorted(outcome))
    if outcome.get("warnings"):
        text += ", with the warnings " + " | ".join(
            parity.show_issue(w) for w in outcome["warnings"]
        )
    return text


# Comparing outcomes.


def compare(
    r: dict[str, Any] | None, python: dict[str, Any] | None
) -> tuple[str, list[str], dict[str, Any] | None]:
    """The class of a comparison, the differences, each a JSON Pointer with
    the value of R and then that of Python, and the R document, which names
    the checks of the findings in the differences."""
    if r is None or python is None:
        return "different", [f"R: {describe(r)}", f"Python: {describe(python)}"], None
    if r == python:
        return "identical", [], None
    if "document" in r and "document" in python:
        a = json.loads(bytes.fromhex(r["document"]))
        b = json.loads(bytes.fromhex(python["document"]))
        found = parity.document_differences(a, b, [])
        found += parity.json_differences(
            json.loads(bytes.fromhex(r["sidecar"])),
            json.loads(bytes.fromhex(python["sidecar"])),
            "sidecar",
        )
        if decoded(r.get("warnings")) != decoded(python.get("warnings")):
            found.append(f"warnings: {describe_warnings(r)} and {describe_warnings(python)}")
        return ("different" if found else "tolerance"), found, a
    return "different", [f"R: {describe(r)}", f"Python: {describe(python)}"], None


def describe_warnings(outcome: dict[str, Any]) -> str:
    warnings = outcome.get("warnings") or []
    return " | ".join(parity.show_issue(w) for w in warnings) or "none"


FINDING = re.compile(r"^/findings/(\d+)(.*)$")


def signature(line: str, document: dict[str, Any] | None) -> str:
    """The kind of a difference: its JSON Pointer with the index of a finding
    replaced by its check, or the outcomes that differ."""
    if line.startswith(("R: ", "Python: ")):
        return "outcomes of different kinds"
    pointer = re.split(r":? ", line, maxsplit=1)[0]
    found = FINDING.match(pointer)
    if found and document is not None:
        findings = document.get("findings", [])
        index = int(found.group(1))
        check = findings[index].get("check", "?") if index < len(findings) else "?"
        return f"{check} {found.group(2) or '(the finding)'}"
    return pointer


class Inputs:
    """The inputs that inputs.R wrote, read on demand to describe them."""

    def __init__(self, directory: Path) -> None:
        self.directory = directory
        index_path = directory / "index.json"
        if not index_path.exists():
            raise HarnessError(f"{index_path} does not exist. Run with --generate.")
        self.index = json.loads(index_path.read_text(encoding="utf-8"))
        self.files: dict[str, str] = {}
        for chunk in self.index["chunks"]:
            for identifier in chunk["ids"]:
                self.files[identifier] = chunk["file"]
        self.cache: dict[str, dict[str, Any]] = {}

    def ids_of_shard(self, shard: int, shards: int) -> list[str]:
        return [
            identifier
            for position, chunk in enumerate(self.index["chunks"])
            if position % shards == shard
            for identifier in chunk["ids"]
        ]

    def source(self, identifier: str) -> str:
        """What rebuilds an input, in words."""
        if identifier.startswith("pseudonyms/"):
            return (
                f"case {identifier.split('/')[1]} of pseudonyms.json in the work directory, "
                "which pseudonyms.R and pseudonyms.py run"
            )
        file = self.files[identifier]
        if file not in self.cache:
            listed = json.loads((self.directory / file).read_text(encoding="utf-8"))["inputs"]
            self.cache[file] = {item["id"]: item for item in listed}
        item = self.cache[file][identifier]
        source = item["source"]
        if source["kind"] == "family":
            parameters = ", ".join(
                f"{key} = {value}" for key, value in source["parameters"].items()
            )
            text = f"table {source['table']} of the family {source['family']}, {parameters}"
        elif source["kind"] == "edge":
            text = (
                f"the edge {source['edge']} with seed {source['seed']}, {source['rows']} rows, "
                f"at {source['tier']}"
            )
        elif source["kind"] == "regression":
            text = (
                f"run {source['run']} of the regression attack {source['attack']}, "
                f"{source['rows']} rows"
            )
        else:
            text = (
                f"the design {source['design']} with a {source['outcome']} outcome at "
                f"{source['tier']}, {source['missing']} of {source['rows']} rows without an "
                f"outcome and seed {source['seed']}"
            )
        return f"{text}, at k = {item['k']}, in {self.directory / file}"


class Results:
    """The comparisons of a run: counts by inputs and mode, the comparisons
    that differ, the runs that failed and the kinds of difference."""

    def __init__(self) -> None:
        self.counts: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
        self.differences: list[dict[str, Any]] = []
        self.failures: list[dict[str, Any]] = []
        self.kinds: dict[tuple[str, str], list[str]] = defaultdict(list)
        # The time of each input in each language, both modes together.
        self.times: dict[str, Counter[str]] = {language: Counter() for language in LANGUAGES}

    def add(self, identifier: str, mode: str, records: dict[str, dict[str, Any] | None]) -> None:
        group = " ".join(identifier.split("/")[:2])
        outcomes = {
            language: None if record is None else record["outcome"]
            for language, record in records.items()
        }
        for language, record in records.items():
            if record is not None:
                self.times[language][identifier] += record["milliseconds"]
            if record is not None and "error" in record["outcome"]:
                self.failures.append(
                    {
                        "id": identifier,
                        "mode": mode,
                        "language": language,
                        "error": unhex(record["outcome"]["error"]),
                    }
                )
        kind, lines, document = compare(outcomes["R"], outcomes["Python"])
        self.counts[(group, mode)][kind] += 1
        if kind == "different":
            self.differences.append({"id": identifier, "mode": mode, "differences": lines})
            for line in lines:
                key = (mode, signature(line, document))
                if identifier not in self.kinds[key]:
                    self.kinds[key].append(identifier)


def compare_pseudonyms(results: Results, work: Path) -> None:
    """Compare the outcomes of the pseudonym cases, when they were run: the
    written findings and the pseudonyms of the sidecar, byte for byte."""
    paths = {language: work / f"{language.lower()}-pseudonyms.txt" for language in LANGUAGES}
    if not (work / "pseudonyms.json").exists():
        return
    lines = {}
    for language, path in paths.items():
        if not path.exists():
            raise HarnessError(f"{path} was not written.")
        lines[language] = path.read_text(encoding="ascii").splitlines()
    if len(lines["R"]) != len(lines["Python"]):
        raise HarnessError("The two runs of the pseudonym cases wrote different numbers of cases.")
    for r, python in zip(lines["R"], lines["Python"], strict=True):
        a = json.loads(bytes.fromhex(r))
        identifier = a["id"]
        if r == python:
            results.counts[("pseudonyms", "shareable")]["identical"] += 1
            continue
        b = json.loads(bytes.fromhex(python))
        found = parity.json_differences(a, b, "") or ["the canonical bytes"]
        results.counts[("pseudonyms", "shareable")]["different"] += 1
        results.differences.append({"id": identifier, "mode": "shareable", "differences": found})
        for line in found:
            key = ("shareable", "pseudonyms " + re.split(r":? ", line, maxsplit=1)[0])
            results.kinds[key].append(identifier)


def check_registries(work: Path, shards: int) -> None:
    """Stop when the shards were run with packages that read different
    compiled registries, whose documents would differ everywhere at
    /inputs/registry_hash."""
    found: dict[str, set[str]] = defaultdict(set)
    for shard in range(shards):
        for language in LANGUAGES:
            path = work / f"{language.lower()}-{shard}.jsonl.gz"
            with gzip.open(path, "rt", encoding="ascii") as handle:
                header = json.loads(handle.readline())
            found[header.get("registry_hash", "unknown")].add(language)
    if len(found) > 1:
        listed = " | ".join(
            f"{parity.words(sorted(languages))}: {digest}" for digest, languages in found.items()
        )
        raise HarnessError(
            f"The packages read different compiled registries ({listed}). Install both "
            "from the same tree."
        )


def compare_outputs(
    inputs: Inputs, work: Path, shards: int, only: set[str] | None
) -> tuple[Results, list[dict[str, Any]]]:
    results = Results()
    headers = []
    for shard in range(shards):
        expected = inputs.ids_of_shard(shard, shards)
        if only is not None:
            expected = [identifier for identifier in expected if identifier in only]
        read = {}
        for language in LANGUAGES:
            header, records = read_shard(work / f"{language.lower()}-{shard}.jsonl.gz")
            if shard == 0:
                headers.append(header)
            read[language] = records
        for identifier in expected:
            for mode in MODES:
                key = (identifier, mode)
                results.add(
                    identifier, mode, {language: read[language].get(key) for language in LANGUAGES}
                )
    return results, headers


# Reporting.


def plural(count: int, noun: str) -> str:
    return f"{count} {noun}" if count == 1 else f"{count} {noun}s"


def print_summary(results: Results) -> None:
    groups = sorted({group for group, _ in results.counts})
    header = ["Inputs", "Mode", *[HEADINGS[name] for name in CLASSES]]
    table = [header]
    totals: dict[str, Counter[str]] = {mode: Counter() for mode in MODES}
    for group in groups:
        for mode in MODES:
            counts = results.counts.get((group, mode), Counter())
            if not counts:
                continue
            totals[mode].update(counts)
            table.append([group, mode, *[str(counts[name]) for name in CLASSES]])
    for mode in MODES:
        table.append(["Total", mode, *[str(totals[mode][name]) for name in CLASSES]])
    widths = [max(len(line[i]) for line in table) for i in range(len(header))]
    print()
    for line in table:
        cells = [line[0].ljust(widths[0]), line[1].ljust(widths[1])]
        cells += [cell.rjust(width) for cell, width in zip(line[2:], widths[2:], strict=True)]
        print("  ".join(cells))


def print_report(results: Results, inputs: Inputs, args: argparse.Namespace, rerun: str) -> None:
    print_summary(results)
    unbuilt = inputs.index.get("unbuilt", [])
    if unbuilt:
        print(
            f"\n{plural(len(unbuilt), 'table')} that the families cannot build, such as "
            f"{unbuilt[0]['id']}, are left out of the inputs, as the harness leaves them out."
        )
    if results.failures:
        print(
            f"\n{plural(len(results.failures), 'run')} failed with an error that is not "
            "the package's own:"
        )
        for failure in results.failures[: args.shown]:
            print(
                f"  {failure['id']} [{failure['mode']}] in {failure['language']}: "
                f"{failure['error'][: parity.SHOWN]}"
            )
    if results.kinds:
        print(
            "\nDifferences by kind, as JSON Pointers into the document with the check of "
            "their finding, with the inputs that give them:"
        )
        kinds = sorted(results.kinds.items(), key=lambda item: (-len(item[1]), item[0]))
        for (mode, kind), identifiers in kinds[:KINDS_SHOWN]:
            shown = ", ".join(identifiers[:3])
            more = f" and {len(identifiers) - 3} more" if len(identifiers) > 3 else ""
            count = plural(len(identifiers), "input")
            print(f"  [{mode}] {kind}: {count}, such as {shown}{more}")
        if len(kinds) > KINDS_SHOWN:
            print(
                f"  and {plural(len(kinds) - KINDS_SHOWN, 'further kind')}, which --report writes"
            )
    for difference in results.differences[: args.shown]:
        identifier = difference["id"]
        print(f"\nDIFFERENT {identifier} [{difference['mode']}]")
        print(f"  input: {inputs.source(identifier)}")
        print(f"  rerun: {rerun} --only {identifier}")
        print("  each difference gives the value of R, then that of Python:")
        lines = difference["differences"]
        for line in lines[: parity.DIFFERENCES_SHOWN]:
            print(f"    {line}")
        if len(lines) > parity.DIFFERENCES_SHOWN:
            print(f"    and {len(lines) - parity.DIFFERENCES_SHOWN} more differences")
    if len(results.differences) > args.shown:
        print(
            f"\n{len(results.differences) - args.shown} further comparisons differ, which "
            "--report writes."
        )
    for language in LANGUAGES:
        slowest = results.times[language].most_common(3)
        if slowest:
            shown = ", ".join(f"{identifier} ({ms / 1000:.1f} s)" for identifier, ms in slowest)
            print(f"\nThe slowest inputs in {language}, both modes together: {shown}.")


def write_report(
    path: Path,
    results: Results,
    inputs: Inputs,
    headers: list[dict[str, Any]],
    timing: dict[str, Any],
) -> None:
    report = {
        "runs": headers,
        "timing": timing,
        "counts": [
            {"inputs": group, "mode": mode, **dict(counts)}
            for (group, mode), counts in sorted(results.counts.items())
        ],
        "differences": [
            {**difference, "input": inputs.source(difference["id"])}
            for difference in results.differences
        ],
        "kinds": [
            {"mode": mode, "kind": kind, "inputs": identifiers}
            for (mode, kind), identifiers in sorted(results.kinds.items())
        ],
        "failures": results.failures,
        "unbuilt": inputs.index.get("unbuilt", []),
    }
    path.write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


# Main.


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--inputs", help="the directory of the inputs (default: in the work directory)"
    )
    parser.add_argument(
        "--generate",
        action="store_true",
        help="write the inputs again even when the directory holds them",
    )
    parser.add_argument("--seeds", type=int, default=3, help="seeds of each design (default 3)")
    parser.add_argument(
        "--edge-seeds", type=int, default=25, help="seeds of each edge (default 25)"
    )
    parser.add_argument(
        "--widen",
        type=int,
        default=0,
        help="values added beyond each end of the families' ranges (default 0)",
    )
    parser.add_argument("--families", help="the families to write, or 'none' (default: all)")
    parser.add_argument("--designs", help="the designs to write, or 'none' (default: all)")
    parser.add_argument("--edges", help="the edges to write, or 'none' (default: all)")
    parser.add_argument(
        "--regressions",
        help="the regression attacks whose tables to write, or 'none' (default: all)",
    )
    parser.add_argument(
        "--pseudonym-cases",
        type=int,
        default=2000,
        help="cases of findings that write labels, run beside the inputs (default 2000)",
    )
    parser.add_argument("--python", default=sys.executable, help="interpreter with mixedcheck")
    parser.add_argument("--rscript", default="Rscript", help="the Rscript of the R to run")
    parser.add_argument("--r-lib", help="a library that holds the installed R package")
    parser.add_argument("--r-locale", default="C.UTF-8", help="LC_ALL of R (default C.UTF-8)")
    parser.add_argument(
        "--cores",
        type=int,
        default=os.cpu_count() or 1,
        help="runs at the same time (default: the number of cores)",
    )
    parser.add_argument(
        "--shards",
        type=int,
        help="parts of the inputs for each language (default: 3 times --cores)",
    )
    parser.add_argument("--only", nargs="+", help="the identifiers of the inputs to run")
    parser.add_argument("--keep", help="a directory for the inputs and outputs, which are kept")
    parser.add_argument(
        "--compare-only",
        action="store_true",
        help="compare the outputs already in the --keep directory",
    )
    parser.add_argument("--report", help="a JSON file for every difference and count")
    parser.add_argument(
        "--shown",
        type=int,
        default=20,
        help="the most comparisons that differ shown in full (default 20)",
    )
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    if args.compare_only and not args.keep:
        parser.error("--compare-only needs --keep")
    try:
        return differential(args)
    except HarnessError as err:
        print(f"The differential test cannot run.\n{err}", file=sys.stderr)
        return 2


def differential(args: argparse.Namespace) -> int:
    started = time.monotonic()
    env = dict(os.environ)
    if args.r_lib:
        libraries = [str(Path(args.r_lib).resolve()), os.environ.get("R_LIBS", "")]
        env["R_LIBS"] = os.pathsep.join(item for item in libraries if item)
    timing: dict[str, Any] = {}
    with tempfile.TemporaryDirectory(prefix="mixedcheck-differential-") as scratch:
        work = Path(args.keep).resolve() if args.keep else Path(scratch)
        work.mkdir(parents=True, exist_ok=True)
        inputs_dir = Path(args.inputs).resolve() if args.inputs else work / "inputs"
        if not args.compare_only and (args.generate or not (inputs_dir / "index.json").exists()):
            timing["inputs"] = round(generate(args, inputs_dir, env), 1)
        inputs = Inputs(inputs_dir)
        settings = work / "settings.json"
        if args.compare_only:
            if not settings.exists():
                raise HarnessError(f"{settings} does not exist.")
            shards = json.loads(settings.read_text(encoding="utf-8"))["shards"]
        else:
            shards = args.shards or 3 * args.cores
            shards = max(1, min(shards, len(inputs.index["chunks"])))
            settings.write_text(json.dumps({"shards": shards}) + "\n", encoding="utf-8")
        only = set(args.only) if args.only else None
        cases = work / "pseudonyms.json"
        if not args.compare_only:
            cases.unlink(missing_ok=True)
            if only is None and args.pseudonym_cases > 0:
                write_pseudonym_cases(cases, args.pseudonym_cases)
        only_file = None
        if only is not None:
            unknown = sorted(only - set(inputs.files))
            if unknown:
                raise HarnessError(f"No input has the identifier {', '.join(unknown)}.")
            only_file = work / "only.txt"
            only_file.write_text("\n".join(sorted(only)) + "\n", encoding="utf-8")
        total = len(only) if only is not None else inputs.index["inputs"]
        if not args.compare_only:
            print(
                f"Running {total} inputs in both modes and languages, in {shards} shards "
                f"for each language, {args.cores} at a time.",
                flush=True,
            )
            spent = run_packages(args, inputs_dir, work, shards, only_file, env)
            for language in LANGUAGES:
                timing[f"{language.lower()}_shards"] = round(spent.get(language, 0.0), 1)
        compared = time.monotonic()
        check_registries(work, shards)
        results, headers = compare_outputs(inputs, work, shards, only)
        if only is None:
            compare_pseudonyms(results, work)
        timing["comparison"] = round(time.monotonic() - compared, 1)
        timing["total"] = round(time.monotonic() - started, 1)
        print()
        for header in headers:
            details = ", ".join(
                f"{key} {value}" for key, value in header.items() if key not in ("run", "language")
            )
            print(f"{header['run']}: {details}")
        rerun = "python3 parity/differential/differential.py --inputs " + str(inputs_dir)
        if args.python != sys.executable:
            rerun += f" --python {args.python}"
        if args.r_lib:
            rerun += f" --r-lib {args.r_lib}"
        print_report(results, inputs, args, rerun)
        if args.report:
            write_report(Path(args.report), results, inputs, headers, timing)
        shown = ", ".join(f"{TIMES[key]} {value}" for key, value in timing.items())
        print(f"\nSeconds: {shown}.")
    if results.differences or results.failures:
        count = len(results.differences)
        verb = "differs" if count == 1 else "differ"
        failed = len(results.failures)
        print(f"\n{plural(count, 'comparison')} {verb}, and {plural(failed, 'run')} failed.")
        return 1
    print("\nThe two packages agree on every comparison.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
