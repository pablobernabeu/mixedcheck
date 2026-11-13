"""The accessor of the pathology zoo (fixtures/zoo/README.md in the repository),
the simulated fixtures that spec/tools/vendor.py installs under
_fixtures/zoo/ with their SHA-256 digests in _fixtures/MANIFEST.json."""

from __future__ import annotations

import hashlib
import os
from importlib.resources import as_file, files
from importlib.resources.abc import Traversable
from pathlib import Path
from typing import Any, overload

import pandas

from mixedcheck._declaration import validate_declaration
from mixedcheck._json_read import read_json_strict
from mixedcheck._table import read_table

# The files of each directory of the zoo, in the order the accessor compares
# them with MANIFEST.json.
FILES = ("data.csv", "declaration.json", "formula.txt", "expected.json")
LISTING_COLUMNS = ("id", "name", "title", "role", "matched", "tier", "rows", "domain", "deferred")


@overload
def pathology_zoo(fixture: None = None) -> pandas.DataFrame: ...


@overload
def pathology_zoo(fixture: str) -> dict[str, Any]: ...


def pathology_zoo(fixture: str | None = None) -> pandas.DataFrame | dict[str, Any]:
    """List the fixtures of the pathology zoo, or return one of them.

    The pathology zoo is a set of small simulated data sets, each with a
    declaration, a preliminary formula and the findings that :func:`audit` is
    expected to give for it. Each fixture plants one problem of a study
    design, such as class labels that recur across schools or a randomisation
    level left out of the formula, and has a matched negative, a similar
    design without the problem. The expected findings are derived from the
    design that generated the data, never from either package. The R and
    Python packages install the same files, and fixtures/zoo/README.md in the
    repository describes each fixture and the formats.

    Called without an argument, the function lists the fixtures. Called with
    an identifier, it returns one fixture, ready to be audited. Before a file
    is read, its SHA-256 digest is compared with the MANIFEST.json installed
    with the package, as for the registry.

    Args:
        fixture: ``None``, to list the fixtures, or the identifier of one
            fixture or matched negative, such as ``"Z01"`` or ``"Z01N"``.

    Returns:
        Without an argument, a pandas DataFrame with a RangeIndex and one row
        for each fixture and matched negative, in the order of their
        identifiers, with the columns ``id``, ``name``, ``title``, ``role``
        ('fixture' or 'negative'), ``matched`` (the identifier of the matched
        negative of a fixture, or of the fixture of a negative), ``tier`` (the
        outcome access of its run, 'T0', 'T1' or 'T2'), ``rows`` (the number of
        rows of its data), ``domain`` and ``deferred`` (whether it records a
        declaration block of a later vocabulary for which its planned check
        waits, or for a negative that of its fixture). ``rows`` has the dtype
        int64, ``deferred`` bool and the others object, holding str.

        With an identifier, a dict with the keys ``id``, ``name``, ``title``,
        ``role``, ``matched`` and ``tier`` as in the listing, ``data``, the data
        read by :func:`read_table` with the declaration, a DataFrame of dtype
        object, ``declaration``, the declaration as
        :func:`validate_declaration` returns it, ``formula``, the formula as a
        str, ``arguments``, the further arguments of :func:`audit` that the
        run of the fixture sets, as a dict with ``outcome_access`` and, at the
        tiers T1 and T2, ``reason`` and ``exploratory``, and ``expected``, the
        expected findings of the fixture as :func:`read_json_strict` returns
        them in the data profile.

    Raises:
        TypeError: ``fixture`` is neither None nor one string.
        ValueError: ``fixture`` names no fixture of the zoo.
        RuntimeError: an installed file is missing or differs from
            MANIFEST.json.
        MixedcheckError: the table or the declaration does not read, which
            only a damaged installation can cause.

    Examples:
        >>> zoo = pathology_zoo()
        >>> list(zoo.columns)
        ['id', 'name', 'title', 'role', 'matched', 'tier', 'rows', 'domain', 'deferred']
        >>> zoo.loc[zoo["id"] == "Z01", "title"].item()
        'Reused class labels across schools'
        >>> # Audit one fixture in internal mode with a fixed commitment key.
        >>> fixture = pathology_zoo("Z08")
        >>> fixture["formula"]
        'y ~ arm + (1 | school)'
        >>> key = bytes(range(32)).hex()
        >>> results = audit(
        ...     fixture["data"],
        ...     fixture["formula"],
        ...     fixture["declaration"],
        ...     **fixture["arguments"],
        ...     privacy="internal",
        ...     key=key,
        ... )
        >>> [f["message"]["id"] for f in results.document["findings"]
        ...  if f["check"] == "assignment.unit_in_random_part"]
        ['unit_missing']
    """
    return zoo_fixture(fixture, files("mixedcheck") / "_fixtures")


@overload
def zoo_fixture(fixture: None, root: Traversable) -> pandas.DataFrame: ...


@overload
def zoo_fixture(fixture: str, root: Traversable) -> dict[str, Any]: ...


def zoo_fixture(fixture: str | None, root: Traversable) -> pandas.DataFrame | dict[str, Any]:
    """The accessor on a directory of installed fixtures, which holds zoo/ and
    MANIFEST.json, so that the tests can give it a modified copy."""
    if fixture is not None and not isinstance(fixture, str):
        raise TypeError("'fixture' must be None or one identifier, such as 'Z01'.")
    digests = _manifest(root)
    index = read_json_strict(_checked_bytes(root, "zoo/index.json", digests), "data")
    fixtures = index["fixtures"]
    if fixture is None:
        return _listing(fixtures)
    names = {entry["id"]: entry["name"] for entry in fixtures}
    if fixture not in names:
        raise ValueError(
            f"'{fixture}' is not an identifier of the pathology zoo. pathology_zoo() lists them."
        )
    directory = f"zoo/{fixture}-{names[fixture]}"
    for name in FILES:
        _checked_bytes(root, f"{directory}/{name}", digests)
    return read_fixture(_child(root, directory))


def _child(root: Traversable, relative: str) -> Traversable:
    for part in relative.split("/"):
        root = root / part
    return root


def _manifest(root: Traversable) -> dict[str, str]:
    """The digests of the MANIFEST.json of the installed fixtures."""
    entry = root / "MANIFEST.json"
    if not entry.is_file():
        raise RuntimeError("'_fixtures/MANIFEST.json' is missing from the installed package.")
    listed = read_json_strict(entry.read_bytes(), "data")["files"]
    return dict(listed)


def _checked_bytes(root: Traversable, name: str, digests: dict[str, str]) -> bytes:
    """The bytes of an installed file after its digest is compared with the
    manifest."""
    entry = _child(root, name)
    shown = f"_fixtures/{name}"
    if not entry.is_file():
        raise RuntimeError(f"'{shown}' is missing from the installed package.")
    content = entry.read_bytes()
    if hashlib.sha256(content).hexdigest() != digests.get(name):
        raise RuntimeError(f"'{shown}' differs from the MANIFEST.json installed with the package.")
    return content


def _listing(fixtures: list[dict[str, Any]]) -> pandas.DataFrame:
    columns: dict[str, pandas.Series[Any]] = {}
    for name in LISTING_COLUMNS:
        values = [entry[name] for entry in fixtures]
        if name == "rows":
            columns[name] = pandas.Series(values, dtype="int64")
        elif name == "deferred":
            columns[name] = pandas.Series(values, dtype="bool")
        else:
            columns[name] = pandas.Series(values, dtype=object)
    return pandas.DataFrame(columns)


def read_fixture(directory: Traversable | str | os.PathLike[str]) -> dict[str, Any]:
    """Read the four files of a directory of the zoo, installed or in the
    source tree, without comparing digests, and return the elements of one
    fixture as pathology_zoo() returns them."""
    if isinstance(directory, str | os.PathLike):
        directory = Path(directory)
    expected = read_json_strict((directory / "expected.json").read_bytes(), "data")
    with as_file(directory / "declaration.json") as path:
        declaration = validate_declaration(path)
    with as_file(directory / "data.csv") as path:
        data = read_table(path, declaration)
    formula = (directory / "formula.txt").read_bytes().decode("utf-8")
    formula = formula.removesuffix("\n")
    run = expected["run"]
    arguments = {
        name: run[name] for name in ("outcome_access", "reason", "exploratory") if name in run
    }
    return {
        "id": expected["id"],
        "name": expected["name"],
        "title": expected["title"],
        "role": expected["role"],
        "matched": expected["matched"],
        "tier": run["outcome_access"],
        "data": data,
        "declaration": declaration,
        "formula": formula,
        "arguments": arguments,
        "expected": expected,
    }
