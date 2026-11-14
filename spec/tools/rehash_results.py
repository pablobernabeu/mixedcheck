#!/usr/bin/env python3
"""Bring the results corpus up to date after a change to the compiled registry.

Usage, from the repository root:

    python3 spec/tools/rehash_results.py           # rewrite, then vendor.py sync
    python3 spec/tools/rehash_results.py --check   # exit 1 when anything is out of date

The documents of fixtures/conformance/results/ record the registry hash of the
compiled registry that the tests use, which stage 5 of validation compares with
the SHA-256 of spec/compiled/registry.json, and the sidecars record the results
file hash, the SHA-256 of the bytes of a document (docs/spec/documents.md,
Validation and Internal sidecar). Every change to the registry therefore
changes the bytes of the documents and the hashes that the sidecars record.

The script takes the old registry hash from the documents of the cases that
expect no issue, which only the registry that the tests use passes. It
replaces that hash with the SHA-256 of spec/compiled/registry.json wherever a
document, a sidecar or a case file records it, so that the documents of the
cases of W7090, which record another hash on purpose, keep theirs. It then
replaces the old results file hash of every document whose bytes changed with
the new one wherever a file records it, so that a sidecar that records the hash
of another file on purpose keeps it. Only the bytes of the hashes change, so a
document with a fault of reading keeps the fault. Last, it checks that every
sidecar whose case expects verification to report nothing but E1313 and E1314
records the hash of the case's document, which it reports and does not change.

After rewriting, the script runs `vendor.py sync`. --check changes nothing and
exits with status 1, naming each file, when a file is out of date or a sidecar
does not match. Both modes take --root to work on another tree. The script uses
the Python standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import vendor  # noqa: E402

CORPUS = "fixtures/conformance/results"
REGISTRY = "spec/compiled/registry.json"
REGISTRY_HASH = re.compile(rb'"registry_hash"\s*:\s*"(sha256:[0-9a-f]{64})"')
RESULTS_HASH = re.compile(rb'"results_hash"\s*:\s*"(sha256:[0-9a-f]{64})"')
# A chain of documents that record each other's hashes would need several
# rounds. The corpus has none, so a few rounds suffice.
ROUNDS = 10


def digest(data: bytes) -> bytes:
    return b"sha256:" + hashlib.sha256(data).hexdigest().encode("ascii")


def corpus_files(root: Path) -> dict[str, bytes]:
    """The case files and inputs of the corpus, by path relative to it."""
    corpus = root / CORPUS
    return {
        path.relative_to(corpus).as_posix(): path.read_bytes()
        for path in sorted(corpus.rglob("*"))
        if path.is_file() and path.name != "README.md"
    }


def corpus_cases(files: dict[str, bytes]) -> list[dict]:
    return [
        case
        for name, data in files.items()
        if "/" not in name and name.endswith(".json")
        for case in json.loads(data.decode("utf-8"))["cases"]
    ]


def plan(root: Path) -> tuple[dict[str, bytes], list[str]]:
    """The files to rewrite, with their new bytes, and the problems found."""
    files = corpus_files(root)
    cases = corpus_cases(files)
    problems: list[str] = []
    new_hash = digest((root / REGISTRY).read_bytes())
    recorded = set()
    for case in cases:
        if case["expected"]["issues"] == []:
            recorded.update(REGISTRY_HASH.findall(files[case["document"]]))
    old_hashes = sorted(recorded - {new_hash})
    if len(old_hashes) > 1:
        problems.append(
            "the documents of the cases without issues record several registry hashes: "
            + ", ".join(h.decode("ascii") for h in old_hashes)
        )
        return {}, problems
    updated = dict(files)
    if old_hashes:
        updated = {name: data.replace(old_hashes[0], new_hash) for name, data in updated.items()}
    documents = sorted({case["document"] for case in cases})
    current = {name: digest(files[name]) for name in documents}
    for _ in range(ROUNDS):
        mapping = {}
        for name in documents:
            found = digest(updated[name])
            if found != current[name]:
                mapping[current[name]] = found
                current[name] = found
        if not mapping:
            break
        for name, data in updated.items():
            for old, new in mapping.items():
                data = data.replace(old, new)
            updated[name] = data
    else:
        problems.append("the results file hashes did not settle")
    for case in cases:
        if "sidecar" not in case:
            continue
        errors = [i for i in case["expected"]["issues"] if i["code"].startswith("E")]
        # Verification runs after the sidecar's own stages, whose issues are
        # every other code, and E1321 at /results_hash expects a mismatch.
        stops = [
            issue
            for issue in case["expected"]["sidecar_issues"]
            if issue["code"] not in ("E1313", "E1314")
        ]
        if errors or stops:
            continue
        found = RESULTS_HASH.findall(updated[case["sidecar"]])
        if found and found[0] != digest(updated[case["document"]]):
            problems.append(
                f"{CORPUS}/{case['sidecar']}: the results_hash is not that of "
                f"{case['document']}, which {case['id']} verifies"
            )
    changed = {name: data for name, data in updated.items() if data != files[name]}
    return changed, problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Update the registry and results hashes of the results corpus."
    )
    parser.add_argument("--check", action="store_true", help="change nothing, report")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: the root this script sits in)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()
    changed, problems = plan(root)
    if args.check:
        for name in changed:
            problems.append(f"{CORPUS}/{name}: out of date")
        if not problems:
            print("the results corpus records the hashes of spec/compiled/registry.json")
    else:
        for name, data in changed.items():
            (root / CORPUS / name).write_bytes(data)
            print(f"wrote {CORPUS}/{name}")
        if changed:
            sync_problems, log = vendor.sync(root)
            for line in log:
                print(line)
            problems += sync_problems
        elif not problems:
            print("the results corpus is up to date")
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
