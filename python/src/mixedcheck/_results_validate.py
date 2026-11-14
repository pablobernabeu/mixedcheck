"""The validator of results documents and the reading and verification of
internal sidecars (docs/spec/documents.md, Validation and Internal sidecar)."""

from __future__ import annotations

import os
import re
import warnings
from collections.abc import Callable
from typing import Any

from mixedcheck._checks import finding_order_key
from mixedcheck._commitments import analysis_table_message, outcome_column_message, run_data
from mixedcheck._declaration import validate_declaration, version_supported
from mixedcheck._errors import (
    MAX_ISSUES,
    Issue,
    MixedcheckError,
    MixedcheckWarning,
    finish_issues,
    new_issue,
    raw_issue,
)
from mixedcheck._formula_ir import formula_response_key
from mixedcheck._hash import commitment_key_id, hash_bytes, hmac_sha256
from mixedcheck._json_read import parse_json_bytes, read_input_bytes
from mixedcheck._json_write import canonical_bytes
from mixedcheck._numbers import shortest_parts
from mixedcheck._registry import (
    REGISTRY_SCOPE_PARTS,
    registry_document,
    registry_entries_by_id,
    registry_hash,
)
from mixedcheck._results import Results
from mixedcheck._schema import child_pointer, json_equal, schema_bundle, schema_issues

# The supported line of results documents and sidecars.
RESULTS_VERSION_PATTERN = re.compile(r"0\.1\.(0|[1-9][0-9]*)")

# The members of /privacy that equal those of the privacy block of the
# registry (E7046), as paths of member names.
FILTER_PARAMETERS = (
    ("min_count",),
    ("dominance", "contributors"),
    ("dominance", "share"),
    ("rounding_base",),
    ("zeros_disclosive",),
)

_DIGITS = re.compile(r"[0-9]+")


def validate_results(
    document: Any, sidecar: Any = None, data: Any = None, declaration: Any = None
) -> Any:
    """Validate a results document and verify its sidecar.

    Validates a results document in the five stages of the results
    specification and stops after the first stage that finds a problem:
    reading in the data profile, the version at ``/results_version``, the
    structure against the results schema, the rules on findings and the
    access log, with the invariants of a shareable document, and the rules
    that compare each finding with the registry entry of its check. A document
    produced with another registry is reported with the warning W7090, and its
    findings are not compared with registry entries.

    With a sidecar, the sidecar is then read in the data profile and its
    version, structure and rules are checked, and it is verified against the
    document: the hash of the results file, the keys that the commitments of
    the document name and, with ``data``, every commitment to the data file,
    the analysis table and an outcome column, recomputed from the data with
    the keys of the sidecar. A results object without ``sidecar`` is verified
    against the sidecar it holds, without the check of the results file hash,
    which it does not hold.

    Args:
        document: A results document: the path of a file, as a str or a
            path-like object, the value that :func:`read_json_strict` returns
            or a results object, as :func:`audit` returns it. A document in
            memory is first written in the data profile, and the hash of its
            canonical bytes stands for the hash of the file.
        sidecar: None, or the internal sidecar of the document: the path of a
            file or the value that :func:`read_json_strict` returns.
        data: None, or the data of the run that produced the document: the
            path of its CSV file, or a pandas DataFrame, as :func:`audit`
            accepts them. A document that commits to a data file needs its
            path. The commitments are recomputed from the data, so ``data``
            needs the keys of a sidecar.
        declaration: None, or the declaration of the run, as
            :func:`validate_declaration` accepts it, when the run had one. It
            is used with ``data`` alone.

    Returns:
        The document: the value read from a file, in the form that
        :func:`read_json_strict` returns, or the document given in memory.

    Raises:
        MixedcheckError: A document that is not valid, whose ``issues`` list
            the problems of the first stage that finds any, each with the
            ``code`` of the shared error catalogue, the rendered ``message``
            and its location. Reading reports one problem, located by the byte
            ``offset`` in the file or, for a document in memory, by the JSON
            Pointer of the value that cannot be written. The later stages
            report every problem they find, located by JSON Pointer as
            ``pointer``, sorted by pointer, code and message and capped at
            100. A sidecar that is not valid, or that does not agree with the
            document, gives an error with its issues: one from reading, E1441
            for its version, the structural issues or the issues of its rules
            (E1321, E7060 and E7061), or the issues of verification in this
            order: E1321 at ``/results_hash``, E1313 for each key that the
            sidecar lacks and E1314 at each commitment that the data do not
            match. A declaration that is not valid, or data that cannot be
            read, give the error of :func:`validate_declaration` or
            :func:`read_table`, and a DataFrame with a value outside the
            declared categories of its field gives E5012, as in
            :func:`audit`.
        TypeError: An argument of the wrong type.
        ValueError: ``data`` without a sidecar, ``declaration`` without
            ``data``, or a document that commits to a data file verified with
            data that are not the path of a file.

    Warns:
        MixedcheckWarning: A document whose registry hash differs from that of
            the registry of this release, with the code W7090 alone. The
            sidecar is then verified as for any other document.

    Examples:
        >>> # The shareable document of an audit of fixture Z01 of the
        >>> # pathology zoo, validated with its sidecar, data and declaration.
        >>> import os, tempfile
        >>> fixture = pathology_zoo("Z01")
        >>> key = bytes(range(32)).hex()
        >>> results = audit(fixture["data"], fixture["formula"], fixture["declaration"], key=key)
        >>> directory = tempfile.TemporaryDirectory()
        >>> path = os.path.join(directory.name, "audit.json")
        >>> sidecar = os.path.join(directory.name, "audit.sidecar.internal.json")
        >>> _ = write_results(results, path, sidecar)
        >>> value = validate_results(
        ...     path, sidecar, data=fixture["data"], declaration=fixture["declaration"]
        ... )
        >>> value["privacy"]["mode"]
        'shareable'
        >>> # A document of another registry: its findings are not compared
        >>> # with registry entries, and a warning says so.
        >>> import warnings
        >>> document = read_json_strict(path, "data")
        >>> other = {**document, "inputs": {"registry_hash": "sha256:" + "0" * 64}}
        >>> with warnings.catch_warnings(record=True) as caught:
        ...     warnings.simplefilter("always")
        ...     _ = validate_results(other)
        >>> caught[0].message.issues[0]["code"]
        'W7090'
        >>> # A finding of a check that the registry does not have.
        >>> document["findings"][-1]["check"] = "structure.no_such_check"
        >>> try:
        ...     validate_results(document)
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["code"])
        E7040
        >>> directory.cleanup()
    """
    is_object = isinstance(document, Results)
    if not is_object and not _is_path(document) and not _is_container(document):
        raise TypeError(
            "'document' must be a file path, a value that read_json_strict() returns "
            "or a results object."
        )
    if sidecar is not None and not _is_path(sidecar) and not _is_container(sidecar):
        raise TypeError(
            "'sidecar' must be None, a file path or a value that read_json_strict() returns."
        )
    if data is not None and not _is_path(data) and not _is_data_frame(data):
        raise TypeError("'data' must be None, a pandas DataFrame or the path of a CSV file.")
    if data is not None and sidecar is None and not is_object:
        raise ValueError("'data' needs a sidecar, whose keys the commitments are recomputed with.")
    if declaration is not None and data is None:
        raise ValueError("'declaration' is used only with 'data'.")
    given = document.document if is_object else document
    value, digest = read_results_input(given)
    issues = results_document_issues(value)
    if issues:
        if issues[0]["code"] == "W7090":
            warnings.warn(MixedcheckWarning(issues), stacklevel=2)
        else:
            raise MixedcheckError(issues)
    if sidecar is None and is_object:
        # The hash of the document stands in for the results hash, which the
        # sidecar of a results object does not hold, so that it is not
        # checked.
        sidecar = {**document.sidecar, "results_hash": digest}
    if sidecar is not None:
        sidecar_issues = results_sidecar_issues(sidecar, value, digest, data, declaration)
        if sidecar_issues:
            raise MixedcheckError(sidecar_issues)
    return value if _is_path(given) else given


def _is_path(x: Any) -> bool:
    return isinstance(x, str | os.PathLike)


def _is_container(x: Any) -> bool:
    """Whether a value is an object or an array, as the strict reader returns
    them."""
    return isinstance(x, dict | list)


def _is_data_frame(x: Any) -> bool:
    import pandas as pd

    return isinstance(x, pd.DataFrame)


def read_results_input(given: Any) -> tuple[Any, str]:
    """Stage 1: the document read from a file in the data profile, or a value
    in memory written in the data profile and read again, with the hash of the
    bytes read or written."""
    data = read_input_bytes(given) if _is_path(given) else canonical_bytes(given, "data")
    return parse_json_bytes(data, "data"), hash_bytes(data)


def results_document_issues(value: Any) -> list[Issue]:
    """Stages 2 to 5 on a document read in stage 1. Returns the issues of the
    first stage that finds any, rendered, sorted and capped, or W7090 alone."""
    version = value.get("results_version") if isinstance(value, dict) else None
    if isinstance(version, str) and not version_supported(version, RESULTS_VERSION_PATTERN):
        return [
            new_issue(
                "E1441", {"version": version, "supported": "0.1.x"}, pointer="/results_version"
            )
        ]
    stages: list[Callable[[Any], list[dict[str, Any]]]] = [
        lambda d: schema_issues(d, "urn:mixedcheck:schema:results"),
        results_rule_issues,
        results_registry_issues,
    ]
    for stage in stages:
        raw = stage(value)
        if raw:
            return finish_issues(raw)
    return []


def results_rule_issues(d: dict[str, Any]) -> list[dict[str, Any]]:
    """Stage 4: the rules on findings and the access log (E7001 to E7006) and,
    in a shareable document, the invariants E7020 to E7023, on a document
    whose structure is valid."""
    issues: list[dict[str, Any]] = []
    log = d["access_log"]
    entries = log["entries"]
    has_plan = log.get("plan") is not None
    for i, entry in enumerate(entries):
        here = f"/access_log/entries/{i}"
        if entry["mode"] == "planned" and not has_plan:
            issues.append(raw_issue("E7004", here + "/mode"))
        # Times have one width, so they compare as strings, code point by
        # code point.
        if i > 0 and entry["time"] < entries[i - 1]["time"]:
            issues.append(raw_issue("E7005", here + "/time"))
    if d["inputs"].get("execution_binding_hash") is not None and not has_plan:
        issues.append(raw_issue("E7004", "/inputs/execution_binding_hash"))
    tiers = {entry["tier"] for entry in entries}
    privacy = d["privacy"]
    has_unit = privacy.get("disclosure_unit") is not None
    allowed = ["disclosure_unit"] if has_unit else ["grouping_factors", "rows"]
    shareable = privacy["mode"] == "shareable"
    seen: set[tuple[str, ...]] = set()
    previous: list[str] | None = None
    for i, finding in enumerate(d["findings"]):
        here = f"/findings/{i}"
        key = finding_order_key(finding["check"], finding.get("scope", {}))
        if tuple(key) in seen:
            issues.append(raw_issue("E7001", here))
        seen.add(tuple(key))
        if previous is not None and key < previous:
            issues.append(raw_issue("E7002", here))
        previous = key
        if finding["status"]["availability"]["value"] != "available":
            continue
        if finding["tier"] not in tiers:
            issues.append(raw_issue("E7003", here + "/tier", {"tier": finding["tier"]}))
        basis = finding["support"]["contributors"]["basis"]
        if basis not in allowed:
            issues.append(
                raw_issue("E7006", here + "/support/contributors/basis", {"expected": allowed})
            )
        if shareable:
            issues += shareable_finding_issues(finding, here, privacy["min_count"])
    return issues


def shareable_finding_issues(
    finding: dict[str, Any], here: str, k: int | float
) -> list[dict[str, Any]]:
    """The invariants E7020 to E7023 for one available finding of a shareable
    document, with k the minimum count (documents.md, Shareable documents).
    Each written value gets the first issue that applies, in the order E7020,
    E7021, E7022 and E7023."""
    issues: list[dict[str, Any]] = []
    support = finding["support"]
    contributors = support["contributors"]
    distinct = contributors["distinct"]
    if distinct.get("value") is None:
        detail = distinct.get("availability", {}).get("detail")
        fails_minimum = detail != "secondary"
    else:
        fails_minimum = distinct["value"] < k
    fails = fails_minimum or contributors.get("dominated") is True
    rule = "minimum-count" if fails_minimum else "dominance"
    for member, at in (
        (support["rows"], "/support/rows/value"),
        (distinct, "/support/contributors/distinct/value"),
    ):
        value = member.get("value")
        if value is not None and value < k:
            issues.append(raw_issue("E7020", here + at, {"limit": k}))
    bundle = schema_bundle()
    pattern = bundle.resolve(
        "urn:mixedcheck:schema:results#/$defs/pseudonym", "urn:mixedcheck:schema:results"
    ).schema["pattern"]
    for name, statistic in finding.get("statistics", {}).items():
        value = statistic.get("value")
        if value is None:
            continue
        at = child_pointer(here + "/statistics", name) + "/value"
        kind = statistic["kind"]
        person = statistic.get("count_class") == "person"
        quantile = statistic.get("quantile")
        if kind == "count" and person and value < k:
            issues.append(raw_issue("E7020", at, {"limit": k}))
        elif fails and (
            kind in ("real", "reals", "labels") or (kind in ("count", "ratio") and person)
        ):
            issues.append(raw_issue("E7021", at, {"rule": rule}))
        elif quantile is not None and (
            quantile.get("n") is None or not quantile_shown(quantile["n"], quantile["p"], k)
        ):
            issues.append(raw_issue("E7022", at, {"limit": k}))
        elif kind == "labels":
            for j, label in enumerate(value):
                if not bundle.matches(pattern, label):
                    issues.append(raw_issue("E7023", f"{at}/{j}"))
    return issues


def quantile_shown(n: int | float, p: str | int | float, k: int | float) -> bool:
    """The quantile rule of privacy.md (Steps, 4): a p-quantile of n values is
    written only when n x min(m, 10^d - m) >= k x 10^d in integer arithmetic,
    where m / 10^d is the shortest decimal that represents p, so that p = 0
    and p = 1 never are. p is a number from 0 to 1 or a decimal string."""
    if isinstance(p, str):
        whole, _, fraction = p.partition(".")
        if whole != "0" or _DIGITS.fullmatch(fraction) is None:
            return False
        m = int(fraction)
        d = len(fraction)
    else:
        value = float(p)
        if not value > 0:
            return False
        # p = 0.s x 10^e, so m = s and d = len(s) - e.
        s, e = shortest_parts(value)
        if e >= 1:
            return False
        m = int(s)
        d = len(s) - e
    if m == 0:
        return False
    power: int = 10**d
    return int(n) * min(m, power - m) >= int(k) * power


def results_registry_issues(d: dict[str, Any]) -> list[dict[str, Any]]:
    """Stage 5: W7090 for a document of another registry, and otherwise the
    rule that compares the parameters of the filter with the registry (E7046)
    and the rules that compare each finding with the registry entry of its
    check (E7040 to E7045 and E7025) and, in a shareable document, E7024."""
    if d["inputs"]["registry_hash"] != registry_hash():
        return [raw_issue("W7090", "/inputs/registry_hash")]
    issues: list[dict[str, Any]] = []
    entries = registry_entries_by_id()
    privacy = d["privacy"]
    shareable = privacy["mode"] == "shareable"
    k = privacy["min_count"]
    # The parameters of the filter equal those of the registry, so that a
    # document cannot lower the k that stage 4 reads from it.
    parameters = registry_document()["privacy"]
    for path in FILTER_PARAMETERS:
        expected = _member(parameters, path)
        given = _member(privacy, path)
        if not json_equal(given, expected):
            issues.append(
                raw_issue("E7046", "/privacy/" + "/".join(path), {"expected": [expected]})
            )
    # Without a disclosure unit, every by_unit count is a person count
    # (registry.md, Statistics and counts).
    by_unit_class = None if privacy.get("disclosure_unit") is not None else "person"
    for i, finding in enumerate(d["findings"]):
        here = f"/findings/{i}"
        entry = entries.get(finding["check"])
        if entry is None:
            issues.append(raw_issue("E7040", here + "/check", {"id": finding["check"]}))
            continue
        if finding["check_version"] != entry["version"]:
            issues.append(
                raw_issue("E7041", here + "/check_version", {"expected": [entry["version"]]})
            )
        if finding["tier"] != entry["tier"]:
            issues.append(raw_issue("E7041", here + "/tier", {"expected": [entry["tier"]]}))
        allowed = REGISTRY_SCOPE_PARTS[entry["scope"]]
        scope = list(finding["scope"])
        for part in scope:
            if part not in allowed:
                issues.append(
                    raw_issue(
                        "E7042",
                        child_pointer(here + "/scope", part),
                        {"kind": "scope part", "name": part},
                    )
                )
        available = finding["status"]["availability"]["value"] == "available"
        if available or scope:
            required = [
                part
                for part in allowed
                if not (entry["scope"] == "grouping_factor_or_model" and part == "factor")
            ]
            for part in required:
                if part not in scope:
                    issues.append(raw_issue("E7043", here + "/scope", {"name": part}))
        if not available:
            continue
        if (finding["status"].get("optimisation") is None) == (entry["fitted_model"] is True):
            issues.append(raw_issue("E7044", here + "/status"))
        message_id = finding["message"]["id"]
        if message_id not in entry["messages"]:
            issues.append(
                raw_issue("E7042", here + "/message/id", {"kind": "message", "name": message_id})
            )
        statistics = finding.get("statistics", {})
        for name, statistic in statistics.items():
            issues += _statistic_issues(
                statistics, name, statistic, entry, here, by_unit_class, shareable, k
            )
    return issues


def _statistic_issues(
    statistics: dict[str, Any],
    name: str,
    statistic: dict[str, Any],
    entry: dict[str, Any],
    here: str,
    by_unit_class: str | None,
    shareable: bool,
    k: int | float,
) -> list[dict[str, Any]]:
    """The issues of stage 5 for one statistic of an available finding."""
    issues: list[dict[str, Any]] = []
    at = child_pointer(here + "/statistics", name)
    defined = entry["statistics"].get(name)
    if defined is None:
        return [raw_issue("E7042", at, {"kind": "statistic", "name": name})]
    if statistic["kind"] != defined["kind"]:
        issues.append(raw_issue("E7041", at + "/kind", {"expected": [defined["kind"]]}))
    count_class = statistic.get("count_class")
    expected = defined.get("count_class")
    if expected == "by_unit":
        expected = by_unit_class
    if count_class is not None and expected is not None and count_class != expected:
        issues.append(raw_issue("E7041", at + "/count_class", {"expected": [expected]}))
    # A statistic has a quantile exactly when its entry gives it one, with the
    # entry's p, so that the quantile rule of stage 4 reaches every quantile
    # of a shareable document.
    quantile = statistic.get("quantile")
    if (quantile is None) != (defined.get("quantile") is None):
        issues.append(raw_issue("E7045", at))
    elif quantile is not None:
        p = float(defined["quantile"]["p"])
        if quantile["p"] != p:
            issues.append(raw_issue("E7041", at + "/quantile/p", {"expected": [p]}))
    if (
        shareable
        and defined["kind"] == "ratio"
        and statistic.get("value") is not None
        and ratio_hides_count(statistics, entry, defined, count_class, k)
    ):
        issues.append(raw_issue("E7024", at + "/value"))
    # The n of a quantile is written only beside the count that the entry
    # names as n, with its value, in every document.
    n = quantile.get("n") if quantile is not None else None
    count = (defined.get("quantile") or {}).get("n")
    if n is not None and count is not None:
        given = statistics.get(count, {}).get("value")
        if not _is_number(given) or given != n:
            issues.append(raw_issue("E7025", at + "/quantile/n", {"count": count}))
    return issues


def _is_number(x: Any) -> bool:
    return isinstance(x, int | float) and not isinstance(x, bool)


def _member(x: Any, path: tuple[str, ...]) -> Any:
    """The value at a path of member names, or None when a member is missing."""
    for name in path:
        if not isinstance(x, dict):
            return None
        x = x.get(name)
    return x


def ratio_hides_count(
    statistics: dict[str, Any],
    entry: dict[str, Any],
    defined: dict[str, Any],
    ratio_class: str | None,
    k: int | float,
) -> bool:
    """Whether the numerator or the denominator of a ratio, as the entry names
    them, is suppressed, whatever its class, or is a person count of the
    finding that is not written or is below k. A part that the finding leaves
    out is a person count when the entry gives it the class person, or the
    class by_unit and the ratio, whose class is that of its parts, is written
    with the class person."""
    for part in (defined.get("numerator"), defined.get("denominator")):
        if part is None:
            continue
        statistic = statistics.get(part)
        if statistic is not None and statistic.get("value") is None:
            return True
        if statistic is None:
            count_class = entry["statistics"].get(part, {}).get("count_class")
            person = count_class == "person" or (
                count_class == "by_unit" and ratio_class == "person"
            )
            value = None
        else:
            person = statistic["kind"] == "count" and statistic.get("count_class") == "person"
            value = statistic.get("value")
        if person and (value is None or value < k):
            return True
    return False


def results_sidecar_issues(
    sidecar: Any, document: dict[str, Any], results_hash: str, data: Any, declaration: Any
) -> list[Issue]:
    """The issues of a sidecar and of its verification against a document read
    in stage 1 whose results file hash is results_hash. Reading, version,
    structure and rules each stop at their first stage with issues, and the
    issues of verification come in the order of documents.md (Internal
    sidecar)."""
    try:
        value, _ = read_results_input(sidecar)
    except MixedcheckError as err:
        return err.issues
    version = value.get("sidecar_version") if isinstance(value, dict) else None
    if isinstance(version, str) and not version_supported(version, RESULTS_VERSION_PATTERN):
        return [
            new_issue(
                "E1441", {"version": version, "supported": "0.1.x"}, pointer="/sidecar_version"
            )
        ]
    stages: list[Callable[[Any], list[dict[str, Any]]]] = [
        lambda s: schema_issues(s, "urn:mixedcheck:schema:results#/$defs/sidecar"),
        sidecar_rule_issues,
    ]
    for stage in stages:
        raw = stage(value)
        if raw:
            return finish_issues(raw)
    return sidecar_verification_issues(value, document, results_hash, data, declaration)


def sidecar_rule_issues(s: dict[str, Any]) -> list[dict[str, Any]]:
    """The rules in code of a structurally valid sidecar: key identifiers that
    match their keys (E1321) and that differ from every earlier one (E7061),
    and pseudonyms that differ from every earlier one (E7060)."""
    issues: list[dict[str, Any]] = []
    key_ids: set[str] = set()
    for i, entry in enumerate(s["keys"]):
        at = f"/keys/{i}/key_id"
        if commitment_key_id(entry["key"]) != entry["key_id"]:
            issues.append(raw_issue("E1321", at))
        if entry["key_id"] in key_ids:
            issues.append(raw_issue("E7061", at, {"name": entry["key_id"]}))
        key_ids.add(entry["key_id"])
    pseudonyms: set[str] = set()
    for i, item in enumerate(s["pseudonyms"]):
        pseudonym = item["pseudonym"]
        if pseudonym in pseudonyms:
            issues.append(raw_issue("E7060", f"/pseudonyms/{i}/pseudonym", {"name": pseudonym}))
        pseudonyms.add(pseudonym)
    return issues


def results_commitments(document: dict[str, Any]) -> list[dict[str, Any]]:
    """The keyed commitments of a valid results document, each with its
    pointer, its commitment and, for an outcome column, the column, in the
    order in which errors.md (Reporting rules) sorts locations."""
    found: list[dict[str, Any]] = []
    for name, commitment in document["inputs"].get("data", {}).items():
        found.append({"pointer": child_pointer("/inputs/data", name), "commitment": commitment})
    for i, entry in enumerate(document["access_log"]["entries"]):
        outcome = entry.get("outcome")
        if outcome is not None:
            found.append(
                {
                    "pointer": f"/access_log/entries/{i}/outcome/commitment",
                    "commitment": outcome["commitment"],
                    "column": outcome["column"],
                }
            )
    return sorted(found, key=lambda item: item["pointer"])


def sidecar_verification_issues(
    sidecar: dict[str, Any],
    document: dict[str, Any],
    results_hash: str,
    data: Any,
    declaration: Any,
) -> list[Issue]:
    """Verification of a valid sidecar against a valid document: E1321 at
    /results_hash, E1313 once for each key identifier that the commitments
    name and the sidecar lacks, in the order in which they first name it, and,
    with data, E1314 at each commitment whose key the sidecar holds and that
    the data do not match, in the order of the commitments."""
    issues: list[Issue] = []
    if sidecar["results_hash"] != results_hash:
        issues.append(new_issue("E1321", pointer="/results_hash"))
    commitments = results_commitments(document)
    keys = sidecar["keys"]
    key_ids = [entry["key_id"] for entry in keys]
    named: list[str] = []
    for item in commitments:
        key_id = item["commitment"]["key_id"]
        if key_id not in named:
            named.append(key_id)
    for key_id in named:
        if key_id not in key_ids:
            issues.append(new_issue("E1313", {"key_id": key_id}))
    if data is not None:
        issues += _commitment_issues(commitments, keys, key_ids, document, data, declaration)
    if len(issues) > MAX_ISSUES:
        rest = len(issues) - MAX_ISSUES
        issues = issues[:MAX_ISSUES] + [new_issue("W1490", {"count": rest})]
    return issues


def _commitment_issues(
    commitments: list[dict[str, Any]],
    keys: list[dict[str, Any]],
    key_ids: list[str],
    document: dict[str, Any],
    data: Any,
    declaration: Any,
) -> list[Issue]:
    """E1314 at each commitment whose key the sidecar holds and that the data
    do not match, in the order of the commitments."""
    issues: list[Issue] = []
    if declaration is not None:
        declaration = validate_declaration(declaration)
    run = run_data(data, declaration)
    response: str | None = None
    response_known = True
    formula = document["inputs"].get("model", {}).get("formula")
    if formula is not None:
        try:
            response = formula_response_key(formula)
        except MixedcheckError:
            response_known = False
    # The digest of a message under a key, computed once for each pair of a
    # message and a key, since every tier of the access log commits to the
    # same columns.
    computed: dict[tuple[str, int, str], str | None] = {}
    for item in commitments:
        commitment = item["commitment"]
        if commitment["key_id"] not in key_ids:
            continue
        found = key_ids.index(commitment["key_id"])
        column = item.get("column")
        memo = (commitment["covers"], found, column or "")
        if memo not in computed:
            message: bytes | None = None
            if commitment["covers"] == "data_file":
                if run.file is None:
                    raise ValueError(
                        "The document commits to a data file, so 'data' must be the path of "
                        "that file."
                    )
                message = run.file
            elif commitment["covers"] == "analysis_table":
                if response_known:
                    message = analysis_table_message(run.table, declaration, response)
            else:
                message = outcome_column_message(run.table, declaration, column or "")
            computed[memo] = (
                hmac_sha256(bytes.fromhex(keys[found]["key"]), message)
                if message is not None
                else None
            )
        if computed[memo] != commitment["digest"]:
            issues.append(new_issue("E1314", pointer=item["pointer"]))
    return issues
