"""Loading of the vendored compiled registry (docs/spec/registry.md, The
compiled registry) and the rules enforced in code on it, which the package
tests apply (registry.md, Rules enforced in code)."""

from __future__ import annotations

import copy
import hashlib
import os
import re
from importlib.resources import files
from importlib.resources.abc import Traversable
from typing import Any, cast

from mixedcheck._declaration import version_supported
from mixedcheck._errors import Issue, MixedcheckError, finish_issues, raise_issue, raw_issue
from mixedcheck._json_read import parse_json_bytes, read_input_bytes
from mixedcheck._schema import child_pointer, schema_issues

# The supported line of registry versions.
REGISTRY_VERSION_PATTERN = re.compile(r"0\.1\.(0|[1-9][0-9]*)")

_PLACEHOLDER = re.compile(r"\{([a-z][a-z0-9_]{0,47})\}")

# The names of the parts of each scope, which message arguments of source
# 'scope' may name (registry.md, Scopes).
REGISTRY_SCOPE_PARTS: dict[str, tuple[str, ...]] = {
    "assignment": ("column", "unit"),
    "column": ("column",),
    "fixed_term": ("term",),
    "fixed_term_by_factor": ("factor", "term"),
    "grouping_column_pair": ("first", "second"),
    "grouping_factor": ("factor",),
    "grouping_factor_or_model": ("factor",),
    "grouping_factor_pair": ("first", "second"),
    "model": (),
    "random_term": ("factor", "term"),
}

# The registry, read once per session.
_registry: list[dict[str, Any]] = []


def read_registry() -> dict[str, Any]:
    """The registry of checks.

    Returns the compiled registry of checks installed with the package: every
    check that the package runs, with what it reads, its statistics,
    thresholds, decision rules, messages, remedies and sources, together with
    the parameters of the privacy filter. The R package's ``read_registry()``
    returns the same document from its own copy.

    The registry is read once per session. Its SHA-256 digest is compared with
    the manifest of the vendored files, it is read with the strict reader in
    the hashable profile and its version must lie in the line that this
    release supports, 0.1.

    Returns:
        A dict with the members ``entries``, the entries in ascending order of
        identifier, ``privacy`` and ``registry_version``, as
        :func:`read_json_strict` returns them. Each call returns a new copy.

    Raises:
        MixedcheckError: A registry that cannot be loaded, with the code
            E1321 when the file differs from its manifest, a code of the strict
            reader when it cannot be read and E1441 when its version is not
            supported.

    Examples:
        >>> registry = read_registry()
        >>> registry["registry_version"]
        '0.1.0'
        >>> [entry["id"] for entry in registry["entries"]][:2]
        ['assignment.constant_within_unit', 'assignment.design_df']
    """
    if not _registry:
        _registry.append(load_registry(files("mixedcheck") / "_spec"))
    return copy.deepcopy(_registry[0])


def _read_entry_bytes(entry: Traversable | str | os.PathLike[str]) -> bytes:
    """The bytes of a vendored file, or E1001 and E1002."""
    if isinstance(entry, str | os.PathLike):
        return read_input_bytes(entry)
    if not entry.is_file():
        raise_issue("E1002" if entry.is_dir() else "E1001")
    try:
        return entry.read_bytes()
    except OSError:
        raise_issue("E1002")


def load_registry(directory: Traversable | str | os.PathLike[str]) -> dict[str, Any]:
    """Load compiled/registry.json from a directory of vendored files with its
    MANIFEST.json, as registry.md (The compiled registry) describes."""
    if isinstance(directory, str | os.PathLike):
        base = os.fspath(directory)
        data = _read_entry_bytes(os.path.join(base, "compiled", "registry.json"))
        manifest_bytes = _read_entry_bytes(os.path.join(base, "MANIFEST.json"))
    else:
        data = _read_entry_bytes(directory / "compiled" / "registry.json")
        manifest_bytes = _read_entry_bytes(directory / "MANIFEST.json")
    manifest = parse_json_bytes(manifest_bytes, "data")
    listed = manifest.get("files") if isinstance(manifest, dict) else None
    recorded = listed.get("compiled/registry.json") if isinstance(listed, dict) else None
    if hashlib.sha256(data).hexdigest() != recorded:
        raise_issue("E1321", pointer="/files/compiled~1registry.json")
    document = parse_json_bytes(data, "hashable")
    version = document.get("registry_version") if isinstance(document, dict) else None
    if not isinstance(version, str):
        # Without a version to check, the structure is checked instead.
        issues = finish_issues(schema_issues(document, "urn:mixedcheck:schema:registry"))
        if issues:
            raise MixedcheckError(issues)
    if not version_supported(version, REGISTRY_VERSION_PATTERN):
        raise_issue(
            "E1441", {"version": version, "supported": "0.1.x"}, pointer="/registry_version"
        )
    return cast(dict[str, Any], document)


def registry_entry(id: str, registry: dict[str, Any] | None = None) -> dict[str, Any]:
    """The entry of a check, or E4001 when no entry has the identifier."""
    document = registry if registry is not None else read_registry()
    for entry in document["entries"]:
        if entry["id"] == id:
            return cast(dict[str, Any], entry)
    raise_issue("E4001", {"id": id})


def registry_issues(document: dict[str, Any]) -> list[Issue]:
    """The rules enforced in code on a structurally valid compiled registry:
    the order of the entries, the rules on each entry and the rules across
    entries. Returns the issues sorted and capped."""
    issues: list[dict[str, Any]] = []
    entries = document["entries"]
    ids = [entry["id"] for entry in entries]
    for i, entry in enumerate(entries):
        prefix = f"/entries/{i}"
        # Identifiers are compared code point by code point, never by the
        # collation of the locale.
        if i > 0 and not ids[i - 1] < ids[i]:
            issues.append(raw_issue("E4017", prefix))
        issues += registry_entry_issues(entry, prefix)
    issues += registry_graph_issues(entries)
    return finish_issues(issues)


def registry_entry_issues(entry: dict[str, Any], prefix: str) -> list[dict[str, Any]]:
    """The rules enforced in code on one structurally valid entry, with
    pointers under the prefix that locates the entry in its document."""
    issues: list[dict[str, Any]] = []

    def add(code: str, pointer: str, args: dict[str, Any] | None = None) -> None:
        issues.append(raw_issue(code, prefix + pointer, args))

    reads = entry["reads"]
    tier = entry["tier"]
    if (
        (tier == "T0" and "outcome" in reads)
        or (tier != "T0" and "outcome" not in reads)
        or (tier == "T1" and "predictors" in reads)
    ):
        add("E4016", "/reads", {"tier": tier})
    if (tier == "T0") == (entry["sample"] == "analysis"):
        add("E4016", "/sample", {"tier": tier})
    statistics = entry["statistics"]
    thresholds = entry["thresholds"]
    parameters = entry["parameters"]
    messages = entry["messages"]
    for name, threshold in thresholds.items():
        here = child_pointer("/thresholds", name)
        statistic = statistics.get(threshold["statistic"])
        if statistic is None:
            add(
                "E4004",
                here + "/statistic",
                {"kind": "statistic", "name": threshold["statistic"]},
            )
        elif statistic["kind"] not in ("count", "ratio", "real"):
            add("E4011", here, {"name": threshold["statistic"]})
        else:
            kind = statistic["kind"]
            value = threshold["value"]
            if kind == "count" and "." in value:
                add("E4012", here + "/value", {"form": "an integer", "kind": kind})
            places = len(value.partition(".")[2])
            if kind == "ratio" and (
                value.startswith("-") or (value != "1" and not value.startswith("0")) or places > 4
            ):
                add(
                    "E4012",
                    here + "/value",
                    {"form": "between 0 and 1 with at most four decimal places", "kind": kind},
                )
            if ("proximity" in threshold) != (kind == "real"):
                add("E4013", here)
        unread = any(
            source["kind"] in ("literature", "software")
            and source.get("full_text_read") is not True
            for source in threshold["sources"]
        )
        if threshold["validation"]["value"] == "validated" and unread:
            add("E4010", here + "/validation")
    for name, statistic in statistics.items():
        if statistic.get("kind") != "ratio":
            continue
        here = child_pointer("/statistics", name)
        parts = []
        for part in ("numerator", "denominator"):
            target = statistics.get(statistic[part])
            if target is None:
                add("E4004", f"{here}/{part}", {"kind": "statistic", "name": statistic[part]})
            parts.append(target)
        if all(target is not None for target in parts) and any(
            target.get("kind") != "count"
            or target.get("count_class") != statistic.get("count_class")
            for target in parts
        ):
            add("E4021", here)
    for i, condition in enumerate(entry["availability"]):
        parameter = condition.get("parameter")
        if parameter is not None and parameter not in parameters:
            add(
                "E4004",
                f"/availability/{i}/parameter",
                {"kind": "parameter", "name": parameter},
            )
    decision = entry["decision"]
    for i, rule in enumerate(decision["rules"]):
        here = f"/decision/rules/{i}"
        named = rule["thresholds"]
        for j, threshold_name in enumerate(named):
            if threshold_name not in thresholds:
                add(
                    "E4004",
                    f"{here}/thresholds/{j}",
                    {"kind": "threshold", "name": threshold_name},
                )
        if rule["message"] not in messages:
            add("E4004", here + "/message", {"kind": "message", "name": rule["message"]})
        descriptive = any(
            thresholds[threshold_name]["validation"]["value"] == "descriptive"
            for threshold_name in named
            if threshold_name in thresholds
        )
        if rule["finding"] == "consequential" and descriptive:
            add("E4020", here + "/finding")
    otherwise = decision["otherwise"]["message"]
    if otherwise not in messages:
        add("E4004", "/decision/otherwise/message", {"kind": "message", "name": otherwise})
    parts_of_scope = REGISTRY_SCOPE_PARTS.get(entry["scope"], ())
    for name, message in messages.items():
        here = child_pointer("/messages", name)
        template = message["template"]
        used = list(dict.fromkeys(_PLACEHOLDER.findall(template)))
        stray = _PLACEHOLDER.sub("", template)
        if "{" in stray or "}" in stray:
            add("E4009", here + "/template")
        args = message["args"]
        for placeholder in used:
            if placeholder not in args:
                add("E4007", here + "/template", {"name": placeholder})
        for arg_name, arg in args.items():
            arg_here = child_pointer(here + "/args", arg_name)
            if arg_name not in used:
                add("E4008", arg_here, {"name": arg_name})
            source = arg["source"]
            target = arg["name"]
            known: Any = {
                "statistic": statistics,
                "threshold": thresholds,
                "parameter": parameters,
                "scope": parts_of_scope,
            }.get(source, ())
            if target not in known:
                kind = "scope element" if source == "scope" else source
                add("E4004", arg_here + "/name", {"kind": kind, "name": target})
                continue
            statistic_kind = statistics[target]["kind"] if source == "statistic" else ""
            if statistic_kind in ("boolean", "reals"):
                add("E4015", arg_here + "/name", {"name": target})
            elif ("digits" in arg) != (statistic_kind in ("ratio", "real")):
                add("E4014", arg_here)
    remedies = [remedy["id"] for remedy in entry["remedies"]]
    seen: set[str] = set()
    for i, remedy in enumerate(remedies):
        if remedy in seen:
            add("E4006", f"/remedies/{i}/id", {"name": remedy})
        seen.add(remedy)
    return issues


def registry_graph_issues(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The rules across entries: unique identifiers (E4003), links that name an
    entry (E4004) and no cycle of links (E4005). A link closes a cycle when the
    check it names reaches the linking entry through links, so every link on a
    cycle is reported."""
    issues: list[dict[str, Any]] = []
    ids = [entry["id"] for entry in entries]
    seen: set[str] = set()
    for i, identifier in enumerate(ids):
        if identifier in seen:
            issues.append(raw_issue("E4003", f"/entries/{i}/id", {"id": identifier}))
        seen.add(identifier)
    # The links of each entry, in pointer order, with their pointers.
    links: list[list[tuple[str, str]]] = []
    for entry in entries:
        found = []
        for kind in ("explained_by", "requires"):
            for j, target in enumerate(entry["links"].get(kind) or []):
                found.append((f"/links/{kind}/{j}", target))
        links.append(found)
    known = set(ids)
    edges: dict[str, list[str]] = {}
    for identifier, found in zip(ids, links, strict=True):
        edges.setdefault(identifier, []).extend(target for _, target in found if target in known)

    def reaches(start: str, goal: str) -> bool:
        visited: set[str] = set()
        stack = [start]
        while stack:
            current = stack.pop()
            if current == goal:
                return True
            if current not in visited:
                visited.add(current)
                stack.extend(edges.get(current, []))
        return False

    for i, found in enumerate(links):
        for pointer, target in found:
            here = f"/entries/{i}{pointer}"
            if target not in known:
                issues.append(raw_issue("E4004", here, {"kind": "check", "name": target}))
            elif reaches(target, ids[i]):
                issues.append(raw_issue("E4005", here, {"check": target}))
    return issues
