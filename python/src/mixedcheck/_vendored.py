"""Access to the shared artefacts vendored into the package.

spec/tools/vendor.py copies them from spec/ and fixtures/ in the repository
into _spec/ and _fixtures/, with a MANIFEST.json of SHA-256 digests in each.
"""

from __future__ import annotations

import hashlib
import json
from importlib.resources import files
from importlib.resources.abc import Traversable


def spec_versions() -> dict[str, str]:
    """Return the versions of the shared specification.

    The versions of the check registry, the schemas and the canonicaliser are
    read from the copy of the shared specification installed with the package.
    The R package's ``spec_versions()`` returns the same names and values from
    its own copy.

    Returns:
        A dictionary with the keys ``registry``, ``schemas`` and
        ``canonicaliser``. Each value is a version number held as a string.
    """
    path = files("mixedcheck") / "_spec" / "versions.json"
    return _read_versions(path.read_text(encoding="utf-8"), "_spec/versions.json")


def _reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    keys = [key for key, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate key")
    return dict(pairs)


def _is_object_of_strings(value: object) -> bool:
    return (
        isinstance(value, dict)
        and len(value) > 0
        and all(key != "" and isinstance(item, str) for key, item in value.items())
    )


def _read_versions(text: str, label: str) -> dict[str, str]:
    try:
        versions = json.loads(text, object_pairs_hook=_reject_duplicates)
    except ValueError:
        versions = None
    if not _is_object_of_strings(versions):
        raise ValueError(f"'{label}' must hold a JSON object whose values are strings.")
    return versions


def _walk(directory: Traversable, prefix: str = "") -> list[str]:
    names = []
    for entry in directory.iterdir():
        if entry.is_dir():
            names += _walk(entry, f"{prefix}{entry.name}/")
        else:
            names.append(f"{prefix}{entry.name}")
    return names


def _vendored_problems(directory: Traversable) -> list[str]:
    """Compare a vendored directory with the digests in its MANIFEST.json.

    Returns one message per problem, or an empty list when the directory
    matches its manifest.
    """
    manifest_file = directory / "MANIFEST.json"
    if not manifest_file.is_file():
        return ["MANIFEST.json: missing"]
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    listed = manifest.get("files")
    if manifest.get("algorithm") != "sha256" or not _is_object_of_strings(listed):
        return ["MANIFEST.json: not a manifest of SHA-256 digests"]
    present = set(_walk(directory)) - {"MANIFEST.json"}
    problems = [f"{name}: missing" for name in sorted(set(listed) - present)]
    problems += [f"{name}: not listed in MANIFEST.json" for name in sorted(present - set(listed))]
    for name in sorted(present & set(listed)):
        entry = directory
        for part in name.split("/"):
            entry = entry / part
        content = entry.read_bytes()
        if hashlib.sha256(content).hexdigest() != listed[name]:
            problems.append(f"{name}: SHA-256 differs from MANIFEST.json")
    return problems
