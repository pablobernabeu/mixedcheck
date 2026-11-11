"""The results object that :func:`audit` returns, its printing and the writer
of the results document and its internal sidecar (docs/spec/documents.md,
Results document, Writing and Internal sidecar, and 03-execution-plan.md,
M2)."""

from __future__ import annotations

import os
import pathlib
from typing import Any

from mixedcheck._errors import display_text, raise_issue
from mixedcheck._hash import hash_bytes
from mixedcheck._json_write import canonical_bytes, json_pointer, utf16_key

# The banners of the two privacy modes, as documents.md (privacy) writes them.
RESULTS_BANNERS = {
    "shareable": (
        "Shareable output: the privacy filter has reduced the risk of disclosure, "
        "but this report is not anonymous data."
    ),
    "internal": (
        "INTERNAL: this report holds values that the privacy filter has not checked, "
        "such as small counts and labels. Do not share it."
    ),
}

# The suffix of the names of internal files (documents.md, Writing).
INTERNAL_SUFFIX = ".internal.json"


class Results:
    """The results of an audit.

    A results object holds the results document of a run as ``document``, in
    the form that :func:`read_json_strict` returns in the data profile, and
    the internal sidecar without ``results_hash``, which only
    :func:`write_results` sets, as ``sidecar``: its version, the commitment
    keys of the run and the pseudonyms. Printing it, or its ``repr()``, shows
    the banner of its privacy mode and one line for each finding with its
    check, its scope, its finding status and its message, or its
    availability. :func:`write_results` writes it and
    :func:`validate_results` validates it.
    """

    __slots__ = ("document", "sidecar")

    def __init__(self, document: dict[str, Any], sidecar: dict[str, Any]) -> None:
        self.document = document
        self.sidecar = sidecar

    def lines(self) -> list[str]:
        """The lines that printing shows: the banner and one line for each
        finding, or 'No findings.'."""
        findings = self.document.get("findings", [])
        lines = [finding_line(finding) for finding in findings] or ["No findings."]
        return [results_banner(self.document)] + lines

    def __str__(self) -> str:
        return "\n".join(self.lines())

    def __repr__(self) -> str:
        return str(self)


def results_banner(document: dict[str, Any]) -> str:
    """The banner of a document: the shareable banner only for a document whose
    mode is 'shareable', and the internal banner otherwise."""
    mode = document.get("privacy", {}).get("mode") if isinstance(document, dict) else None
    return RESULTS_BANNERS["shareable" if mode == "shareable" else "internal"]


def finding_line(finding: dict[str, Any]) -> str:
    """One line for a finding: its check, the parts of its scope in ascending
    order of name, and its finding status and message, or its availability."""
    scope = finding.get("scope", {})
    parts = sorted(scope)
    where = ""
    if parts:
        where = (
            " ("
            + ", ".join(f"{part} '{display_text(scope[part], limit=None)}'" for part in parts)
            + ")"
        )
    status = finding["status"]
    availability = status["availability"]
    if availability.get("value") != "available":
        reason = availability.get("reason")
        detail = availability.get("detail", availability.get("version"))
        if detail is not None:
            reason = f"{reason}: {display_text(detail, limit=None)}"
        return f"{finding['check']}{where}: not available ({reason})."
    value = status["finding"]["value"].replace("_", " ")
    text = display_text(finding["message"]["text"], limit=None)
    return f"{finding['check']}{where}: {value}. {text}"


def write_results(
    results: Results, path: str | os.PathLike[str], sidecar: str | os.PathLike[str]
) -> str:
    """Write a results document and its internal sidecar.

    Writes the results document of a results object to ``path`` as its
    canonical bytes, the JSON text that RFC 8785 defines, and the internal
    sidecar to ``sidecar``. The sidecar holds the commitment keys of the run,
    the pseudonyms of a shareable document and ``results_hash``, the SHA-256
    of the bytes written to ``path``, so it must stay on the analyst's
    machine. Every document of :func:`audit` commits to its analysis table
    with a key, so the sidecar is always written.

    File names show which files may be shared: the name of ``path`` must end
    in '.internal.json' exactly when the document is internal, and the name of
    ``sidecar`` must always end in it. No suffix is added, so the caller sees
    the name of each file written. Existing files are replaced. The document is
    written first, and it is removed when the sidecar cannot be written, since
    the sidecar holds the only copy of the key.

    Args:
        results: A results object, as :func:`audit` returns it.
        path: The path of the results document.
        sidecar: The path of the internal sidecar, which must name a file
            other than ``path``.

    Returns:
        The results file hash: 'sha256:' followed by the 64 lower-case
        hexadecimal digits of the SHA-256 digest of the bytes written to
        ``path``.

    Raises:
        MixedcheckError: A file name whose suffix does not match, with the code
            E7010, a commitment key found in a shareable document, with the
            code E1315, or a document that the writer cannot write in the data
            profile, with the writer's code at its JSON Pointer.
        TypeError: An argument of the wrong type.
        ValueError: A ``sidecar`` that names the file of ``path``, or a
            directory that does not exist.
        OSError: A file that cannot be written.

    Examples:
        >>> import os, tempfile
        >>> import pandas as pd
        >>> data = pd.DataFrame(
        ...     {
        ...         "y": [2.1, 3.4, 1.8, 2.9, 3.3, 4.1],
        ...         "x": [1, 2, 3, 4, 5, 6],
        ...         "subject": ["s1", "s1", "s2", "s2", "s3", "s3"],
        ...     }
        ... )
        >>> key = bytes(range(32)).hex()
        >>> results = audit(data, "y ~ x + (1 | subject)", privacy="internal", key=key)
        >>> directory = tempfile.mkdtemp()
        >>> path = os.path.join(directory, "audit.internal.json")
        >>> sidecar = os.path.join(directory, "audit.sidecar.internal.json")
        >>> write_results(results, path, sidecar) == hash_file(path)
        True
        >>> # An internal document cannot be written to a file named as shareable.
        >>> try:
        ...     write_results(results, os.path.join(directory, "audit.json"), sidecar)
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["message"])
        The internal results document must be written to a file whose name ends in '.internal.json'.
    """
    if not isinstance(results, Results):
        raise TypeError("'results' must be a results object, as audit() returns it.")
    paths = []
    for value, name in ((path, "path"), (sidecar, "sidecar")):
        if isinstance(value, os.PathLike):
            value = os.fspath(value)
        if not isinstance(value, str) or value == "":
            raise TypeError(f"'{name}' must be a file path.")
        paths.append(value)
    path, sidecar = paths
    if _resolved_path(path) == _resolved_path(sidecar):
        raise ValueError("'sidecar' must be a path other than 'path'.")
    document = results.document
    privacy = document.get("privacy") if isinstance(document, dict) else None
    shareable = isinstance(privacy, dict) and privacy.get("mode") == "shareable"
    if shareable == _name(path).endswith(INTERNAL_SUFFIX):
        if shareable:
            raise_issue("E7010", {"file": "shareable results document", "rule": "does not end in"})
        raise_issue("E7010", {"file": "internal results document", "rule": "ends in"})
    if not _name(sidecar).endswith(INTERNAL_SUFFIX):
        raise_issue("E7010", {"file": "internal sidecar", "rule": "ends in"})
    if shareable:
        found = commitment_key_pointer(document)
        if found is not None:
            raise_issue("E1315", pointer=found)
    for file in (path, sidecar):
        if not os.path.isdir(os.path.dirname(file) or "."):
            raise ValueError(f"The directory of '{display_text(file)}' does not exist.")
    data = canonical_bytes(document, "data")
    digest = hash_bytes(data)
    sidecar_value = dict(results.sidecar)
    sidecar_value["results_hash"] = digest
    sidecar_bytes = canonical_bytes(sidecar_value, "data")
    with open(path, "wb") as handle:
        handle.write(data)
    try:
        with open(sidecar, "wb") as handle:
            handle.write(sidecar_bytes)
    except BaseException:
        # The sidecar holds the only copy of the key, so a document whose
        # sidecar cannot be written is removed.
        try:
            os.remove(path)
        except OSError:
            pass
        raise
    return digest


def _name(path: str) -> str:
    """The name of the file of a path, its last component."""
    return pathlib.PurePath(path).name


def _resolved_path(path: str) -> str:
    """A path with its directory resolved, so that two names of one file compare
    equal when the directory exists."""
    return os.path.join(os.path.realpath(os.path.dirname(path) or "."), _name(path))


def commitment_key_pointer(x: Any, path: list[str] | None = None) -> str | None:
    """The JSON Pointer of the first commitment key in a value, in the order of
    its canonical serialisation: an object with exactly the members created,
    key and key_id (conventions.md, Keys). None when there is none."""
    path = path or []
    if isinstance(x, dict):
        if sorted(x) == ["created", "key", "key_id"]:
            return json_pointer(path)
        for key in sorted(x, key=utf16_key):
            found = commitment_key_pointer(x[key], path + [key])
            if found is not None:
                return found
    elif isinstance(x, list):
        for i, value in enumerate(x):
            found = commitment_key_pointer(value, path + [str(i)])
            if found is not None:
                return found
    return None
