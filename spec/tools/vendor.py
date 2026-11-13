#!/usr/bin/env python3
"""Copy the shared artefacts into both packages and check the copies.

Usage, from the repository root:

    python3 spec/tools/vendor.py sync
    python3 spec/tools/vendor.py check

spec/vendoring.json lists every artefact to vendor, as a path relative to the
repository root under spec/ or fixtures/. An entry that ends in '/' names a
directory under fixtures/, outside fixtures/conformance/, every file of which
is vendored, such as fixtures/zoo/. `sync` copies each one byte for byte
into the package directories that TARGETS names for the most specific source
directory that holds it, and writes a MANIFEST.json of SHA-256 digests into
each of them. `check` changes nothing and exits with status 1, naming each
problem, when a copy is missing or differs from its
source, a listed source is missing, a vendored directory holds a file that is
not listed, an old copy of an artefact now vendored elsewhere or a symbolic
link, a MANIFEST.json is missing or stale, or a
file under spec/ contains a carriage return (CR) or starts with a UTF-8
byte-order mark. Both modes also reject a list entry whose name the R package
could not carry, and take --root to work on another tree.

The script uses the Python standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath

LIST = "spec/vendoring.json"
MANIFEST = "MANIFEST.json"
# Each source directory and the package directories it is vendored into
# (02-decisions.md, Q7). An artefact belongs to the most specific source
# directory that holds it. The conformance corpora are test material, so they
# go into the packages' test directories and are not installed. Other fixtures,
# such as the zoo, are installed with the packages.
TARGETS = {
    "spec": ("r/inst/spec", "python/src/mixedcheck/_spec"),
    "fixtures": ("r/inst/fixtures", "python/src/mixedcheck/_fixtures"),
    "fixtures/conformance": ("r/tests/conformance", "python/tests/conformance"),
}
# Caches that tools may write under spec/. They are not sources.
SKIP_DIRS = {"__pycache__", ".pytest_cache", ".ruff_cache"}
# Files that operating systems write and .gitignore excludes. They are not
# sources.
SKIP_FILES = {".DS_Store", "Thumbs.db"}
BOM = b"\xef\xbb\xbf"
# R CMD build leaves some names out of the R package's tarball, and R CMD
# check rejects names that are not portable (Writing R Extensions, 1.1.1). The
# list rejects such names, so that the cause shows here rather than as a
# missing file in the R package's checks.
R_PACKAGE = "mixedcheck"
R_PATH_LIMIT = 100
PORTABLE_NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]*")
WINDOWS_DEVICE = re.compile(r"(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?", re.IGNORECASE)
R_DROPPED_NAME = re.compile(r"Read-and-delete-me|(?i:autom4te\.cache|.*\.(bak|swp))")
R_DROPPED_DIR = re.compile(r"check|chm|CVS|_darcs|.*([Oo]ld|\.Rcheck)")


def _reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    keys = [key for key, _ in pairs]
    duplicated = sorted({key for key in keys if keys.count(key) > 1})
    if duplicated:
        raise ValueError(f"duplicate key {duplicated[0]!r}")
    return dict(pairs)


def source_dir_of(entry: str) -> str | None:
    """Return the most specific source directory of TARGETS that holds `entry`."""
    matches = [source for source in TARGETS if entry.startswith(source + "/")]
    return max(matches, key=len) if matches else None


def _r_name_problem(parts: tuple[str, ...], source_dir: str) -> str | None:
    for index, part in enumerate(parts):
        if not PORTABLE_NAME.fullmatch(part):
            return f"has the component {part!r}, which is not a portable file name"
        if WINDOWS_DEVICE.fullmatch(part):
            return f"has the component {part!r}, which names a device on Windows"
        is_dir = index < len(parts) - 1
        if R_DROPPED_NAME.fullmatch(part) or (is_dir and R_DROPPED_DIR.fullmatch(part)):
            return f"has the component {part!r}, which R CMD build leaves out"
    rest = "/".join(parts[len(source_dir.split("/")) :])
    r_path = f"{R_PACKAGE}/{TARGETS[source_dir][0].removeprefix('r/')}/{rest}"
    if len(r_path.encode("utf-8")) > R_PATH_LIMIT:
        return f"is longer than {R_PATH_LIMIT} bytes as a path in the R package's tarball"
    return None


def _entry_problem(entry: object) -> str | None:
    if not isinstance(entry, str):
        return f"entry {entry!r} is not a string"
    path = PurePosixPath(entry)
    if "\\" in entry or path.is_absolute() or str(path) != entry:
        return f"entry {entry!r} is not a normalised relative POSIX path"
    if any(part in {".", ".."} for part in path.parts):
        return f"entry {entry!r} contains '.' or '..'"
    source_dir = source_dir_of(entry)
    if source_dir is None:
        roots = " or ".join(f"{root}/" for root in TARGETS if "/" not in root)
        return f"entry {entry!r} is not a file under {roots}"
    if entry == LIST:
        return f"entry {entry!r} is the list of artefacts itself"
    if entry[len(source_dir) + 1 :].lower() == MANIFEST.lower():
        return f"entry {entry!r} would overwrite the vendored {MANIFEST}"
    problem = _r_name_problem(path.parts, source_dir)
    return None if problem is None else f"entry {entry!r} {problem}"


def _case_problems(artefacts: list[str]) -> list[str]:
    """Name paths that differ only in case.

    R CMD check rejects them, and a case-insensitive file system cannot hold
    both.
    """
    seen: dict[str, str] = {}
    clashes: set[tuple[str, str]] = set()
    for entry in artefacts:
        parts = PurePosixPath(entry).parts
        for end in range(2, len(parts) + 1):
            path = "/".join(parts[:end])
            first = seen.setdefault(path.lower(), path)
            if first != path:
                clashes.add((first, path))
    return [f"{LIST}: {a!r} and {b!r} differ only in case" for a, b in sorted(clashes)]


def _directory_problem(entry: str) -> str | None:
    """A problem with an entry that names a directory, or None."""
    name = entry[:-1]
    path = PurePosixPath(name)
    if not name or "\\" in entry or path.is_absolute() or str(path) != name:
        return f"entry {entry!r} is not a normalised relative POSIX path"
    if any(part in {".", ".."} for part in path.parts):
        return f"entry {entry!r} contains '.' or '..'"
    conformance = name == "fixtures/conformance" or name.startswith("fixtures/conformance/")
    if not name.startswith("fixtures/") or conformance:
        return f"entry {entry!r} is not a directory under fixtures/ outside fixtures/conformance/"
    return None


def expand_directory(root: Path, entry: str) -> tuple[list[str], str | None]:
    """The files of a directory entry, in code-point order of their paths,
    without the files that SKIP_FILES and SKIP_DIRS leave out, or a problem."""
    directory = root / entry
    if not directory.is_dir():
        return [], f"entry {entry!r} names a directory that does not exist"
    names = sorted(
        path.relative_to(root).as_posix()
        for path in directory.rglob("*")
        if (path.is_file() or path.is_symlink())
        and path.name not in SKIP_FILES
        and not SKIP_DIRS.intersection(path.relative_to(directory).parts)
    )
    if not names:
        return [], f"entry {entry!r} names a directory that holds no file"
    return names, None


def read_list(root: Path) -> tuple[list[str], list[str]]:
    """Return the listed artefacts and the problems found in the list. An
    entry that names a directory is expanded into the files it holds, which
    are then treated as listed ones."""
    try:
        text = (root / LIST).read_text(encoding="utf-8")
    except FileNotFoundError:
        return [], [f"{LIST}: missing"]
    try:
        data = json.loads(text, object_pairs_hook=_reject_duplicates)
    except (ValueError, UnicodeDecodeError) as err:
        return [], [f"{LIST}: not valid JSON ({err})"]
    if (
        not isinstance(data, dict)
        or set(data) != {"artefacts"}
        or not isinstance(data["artefacts"], list)
    ):
        return [], [f"{LIST}: must be an object whose only key, 'artefacts', holds a list"]
    artefacts: list[str] = []
    problems: list[str] = []
    seen: set[str] = set()
    for entry in data["artefacts"]:
        if isinstance(entry, str) and entry.endswith("/"):
            problem = _directory_problem(entry)
            if problem is None and entry in seen:
                problem = f"entry {entry!r} is listed twice"
            files: list[str] = []
            if problem is None:
                files, problem = expand_directory(root, entry)
            seen.add(entry)
            if problem is not None:
                problems.append(f"{LIST}: {problem}")
            for name in files:
                file_problem = _entry_problem(name)
                if file_problem is None and name in artefacts:
                    file_problem = f"entry {name!r} is listed twice"
                if file_problem is None:
                    artefacts.append(name)
                else:
                    problems.append(f"{LIST}: {file_problem} (through the entry {entry!r})")
            continue
        problem = _entry_problem(entry)
        if problem is None and entry in artefacts:
            problem = f"entry {entry!r} is listed twice"
        if problem is None:
            artefacts.append(entry)
        else:
            problems.append(f"{LIST}: {problem}")
    return artefacts, problems + _case_problems(artefacts)


def _files_under(directory: Path) -> set[str]:
    if not directory.is_dir():
        return set()
    return {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() or path.is_symlink()
    }


def _listed_in(source_dir: str, artefacts: list[str]) -> list[str]:
    prefix = source_dir + "/"
    return sorted(entry[len(prefix) :] for entry in artefacts if source_dir_of(entry) == source_dir)


def manifest_text(source_root: Path, listed: list[str], source_dir: str) -> str:
    """The MANIFEST.json that `sync` writes for the files in `listed`."""
    digests = {
        name: hashlib.sha256((source_root / name).read_bytes()).hexdigest()
        for name in sorted(listed)
    }
    document = {"source": source_dir, "algorithm": "sha256", "files": digests}
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def text_problems(root: Path) -> list[str]:
    """Name every file under spec/ that contains a CR byte or starts with a BOM."""
    problems = []
    spec = root / "spec"
    for path in sorted(spec.rglob("*")):
        if (
            not path.is_file()
            or path.name in SKIP_FILES
            or SKIP_DIRS.intersection(path.relative_to(spec).parts)
        ):
            continue
        content = path.read_bytes()
        name = path.relative_to(root).as_posix()
        count = content.count(b"\r")
        if count:
            line = content[: content.index(b"\r")].count(b"\n") + 1
            problems.append(
                f"{name}: {count} carriage return(s), the first on line {line}. "
                "Sources in spec/ must use LF line endings"
            )
        if content.startswith(BOM):
            problems.append(
                f"{name}: starts with a byte-order mark. Sources in spec/ must be UTF-8 without one"
            )
    return problems


def _source_problems(root: Path, artefacts: list[str]) -> list[str]:
    return [
        f"{entry}: listed in {LIST} but missing"
        for entry in artefacts
        if not (root / entry).is_file()
    ]


def check(root: Path) -> list[str]:
    """Return every problem with the vendored copies, without changing anything."""
    artefacts, problems = read_list(root)
    problems += _source_problems(root, artefacts)
    problems += text_problems(root)
    for source_dir, targets in TARGETS.items():
        listed = _listed_in(source_dir, artefacts)
        source_root = root / source_dir
        sources_present = all((source_root / name).is_file() for name in listed)
        for target in targets:
            target_root = root / target
            present = _files_under(target_root)
            # A link passes a comparison of contents, but a checkout without
            # symbolic links writes it as a file that holds the link's target.
            for name in sorted(present):
                if (target_root / name).is_symlink():
                    problems.append(f"{target}/{name}: a symbolic link, not a copy")
            for name in listed:
                copy, source = target_root / name, source_root / name
                if not copy.is_file():
                    problems.append(f"{target}/{name}: missing copy of {source_dir}/{name}")
                elif source.is_file() and copy.read_bytes() != source.read_bytes():
                    problems.append(f"{target}/{name}: differs from {source_dir}/{name}")
            expected = (set(listed) | {MANIFEST}) if listed else set()
            for name in sorted(present - expected):
                entry = f"{source_dir}/{name}"
                owner = source_dir_of(entry) if entry in artefacts else None
                if owner is not None and owner != source_dir:
                    # A copy left where an earlier layout vendored the artefact.
                    problems.append(
                        f"{target}/{name}: an old copy of {entry}, which is now "
                        f"vendored into {' and '.join(TARGETS[owner])}"
                    )
                else:
                    problems.append(f"{target}/{name}: not listed in {LIST}")
            if listed and sources_present:
                manifest = target_root / MANIFEST
                expected_manifest = manifest_text(source_root, listed, source_dir)
                if not manifest.is_file():
                    problems.append(f"{target}/{MANIFEST}: missing")
                elif manifest.read_bytes() != expected_manifest.encode("utf-8"):
                    problems.append(f"{target}/{MANIFEST}: stale")
    return problems


def _write_if_changed(path: Path, content: bytes, root: Path, log: list[str]) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.is_file() and path.read_bytes() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    log.append(f"wrote {path.relative_to(root).as_posix()}")


def _remove_empty_dirs(directory: Path, root: Path, log: list[str], *, keep_root: bool) -> None:
    if not directory.is_dir():
        return
    for path in sorted(directory.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    if not keep_root and not any(directory.iterdir()):
        directory.rmdir()
        log.append(f"removed {directory.relative_to(root).as_posix()}/")


def sync(root: Path) -> tuple[list[str], list[str]]:
    """Write the copies and manifests. Return (problems, log of changes).

    Nothing is written when a listed source is missing, the list is invalid or
    a spec/ source contains a CR byte or starts with a byte-order mark.
    """
    artefacts, problems = read_list(root)
    problems += _source_problems(root, artefacts)
    problems += text_problems(root)
    log: list[str] = []
    if problems:
        return problems, log
    for source_dir, targets in TARGETS.items():
        listed = _listed_in(source_dir, artefacts)
        source_root = root / source_dir
        for target in targets:
            target_root = root / target
            for name in listed:
                content = (source_root / name).read_bytes()
                _write_if_changed(target_root / name, content, root, log)
            if listed:
                manifest = manifest_text(source_root, listed, source_dir)
                _write_if_changed(target_root / MANIFEST, manifest.encode("utf-8"), root, log)
            keep = (set(listed) | {MANIFEST}) if listed else set()
            for name in sorted(_files_under(target_root) - keep):
                (target_root / name).unlink()
                log.append(f"removed {target}/{name}")
            _remove_empty_dirs(target_root, root, log, keep_root=bool(listed))
    return problems, log


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Vendor the shared artefacts into the R and Python packages."
    )
    parser.add_argument("mode", choices=["sync", "check"])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: the root this script sits in)",
    )
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.mode == "sync":
        problems, log = sync(root)
        for line in log:
            print(line)
        if not problems:
            print("vendored copies are up to date" if not log else "sync finished")
    else:
        problems = check(root)
        if not problems:
            artefacts, _ = read_list(root)
            print(f"vendoring check passed for {len(artefacts)} artefact(s)")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"{len(problems)} problem(s). Edit the sources in spec/ or fixtures/, never "
            "the copies, then run 'python3 spec/tools/vendor.py sync'.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
