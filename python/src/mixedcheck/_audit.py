"""The entry point of Stream B: :func:`audit` runs the checks of the registry on
the design of a model and returns a results object (03-execution-plan.md, M2,
and docs/spec/documents.md, Results document)."""

from __future__ import annotations

import os
import platform
import unicodedata
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    TIERS,
    Run,
    assignment_elements,
    declaration_inferred,
    declared_role_columns,
    declared_units,
    document_finding,
    new_run,
    order_findings,
    outcome_reads_logged,
    resolve_finding_classes,
    run_checks,
)
from mixedcheck._commitments import (
    RunData,
    data_commitments,
    observation_key_columns,
    outcome_commitment,
    run_data,
)
from mixedcheck._declaration import path_pointer, validate_declaration
from mixedcheck._design import analysis_rows, design_build, design_model, design_response
from mixedcheck._errors import MixedcheckError, raise_issue
from mixedcheck._formula_ir import (
    _check_coding_argument,
    build_formula_ir,
    coding_input,
    input_string,
)
from mixedcheck._hash import commitment_key_bytes, commitment_key_id, random_key_bytes
from mixedcheck._json_read import parse_json_bytes
from mixedcheck._json_write import canonical_bytes, canonical_hash
from mixedcheck._privacy import privacy_filter
from mixedcheck._registry import registry_document, registry_hash
from mixedcheck._results import Results
from mixedcheck._schema import term_variables
from mixedcheck._times import run_time, utc_timestamp
from mixedcheck._unicode import comparison_form, sort_identifiers
from mixedcheck._vendored import spec_versions
from mixedcheck._version import __version__

if TYPE_CHECKING:
    import pandas

# The family names that audit() accepts, in the order that E7008 lists them.
FAMILY_NAMES = (
    "gaussian",
    "binomial",
    "poisson",
    "negative_binomial",
    "beta",
    "gamma",
    "inverse_gaussian",
    "cumulative",
)


def audit(
    data: pandas.DataFrame | str | os.PathLike[str],
    formula: str,
    declaration: Any = None,
    family: str | None = None,
    coding: Mapping[str, Mapping[str, Any]] | None = None,
    weights: str | None = None,
    sample_columns: Sequence[str] | None = None,
    outcome_access: str = "T0",
    reason: str | None = None,
    exploratory: bool = False,
    outcome_seen: bool | None = None,
    privacy: str = "shareable",
    key: str | None = None,
) -> Results:
    """Audit the design of a mixed-effects model.

    Runs the checks of the registry on the design of a model before it is
    fitted and returns a results object. The checks of tier T0 read the table
    and the design sample and never the outcome. The checks of tier T1 read
    the outcome marginally or by grouping factor and run only when
    ``outcome_access`` asks for them with a reason, and the exploratory check
    of tier T2 relates the outcome to the predictors by linear programs, which
    scipy's HiGHS solves. The access log of the results document records every
    access to the outcome with a keyed commitment to the column read.

    The check of tier T2, outcome.separation, solves two linear programs over
    every observation and, when it finds separation, two more for each kept
    fixed-effects column. Limits on the size of these programs, which grows
    with the observations and the kept columns, bound its time: beyond the
    parameter max_size of its registry entry, the check is not available,
    and beyond max_bound_programs or max_bound_size, its finding leaves out
    the bounds of the coefficients and the columns involved.

    A run takes the steps of the execution plan in order and stops at the
    first that fails: the arguments, the declaration, the data, the columns
    that the declaration names, the IR, the columns that the outcome-blind
    checks may read, the family class, the design sample with X and Z, at T1
    and T2 the analysis sample with the response, the checks, the order of the
    findings, the privacy filter, the access log and the inputs of the
    document. The data are converted as :func:`formula_ir` converts them,
    after the missing values that the declaration's table block lists are
    applied to a DataFrame. Every column of the data must hold numbers,
    strings or booleans, since the commitment to the analysis table covers
    every column.

    The family class decides which checks apply. 'gaussian' gives the class
    gaussian, 'binomial' the class binomial when the response has a trials
    column and bernoulli otherwise, 'poisson' and 'negative_binomial' the
    class poisson, and 'beta', 'gamma', 'inverse_gaussian' and 'cumulative'
    the class other. Without a family, the class follows the measurement level
    that the declaration gives the response: binary gives bernoulli, binomial
    gives binomial, count gives poisson, ordinal gives other, and any other
    level, or none, gives gaussian.

    The times of the run are UTC times truncated to whole seconds. When the
    environment variable MIXEDCHECK_TIME is set to a whole number of seconds
    since 1970-01-01T00:00:00Z, written as one or more of the ASCII digits 0 to
    9 and nothing else, every time of the run is that time instead, so that a
    run can be repeated byte for byte.

    Shareable mode, the default, passes the findings through the privacy
    filter of the `privacy specification
    <https://github.com/pablobernabeu/mixedcheck/blob/main/docs/spec/privacy.md>`_.
    It writes as null, with the reason privacy_suppressed and the rule that
    applied, the values that could disclose a person's data: counts of
    persons below the minimum count of the registry, values of findings with
    too few contributors or dominated by their largest contributors, values
    that would give back a suppressed one by a sum, difference or ratio,
    minima and maxima, quantiles of too few values and any value from which a
    reader could infer a suppressed value that depends on the outcome. A
    finding of an outcome check whose decision rests on a suppressed count is
    suppressed as a whole, messages are rendered from the written values and
    labels are replaced by pseudonyms, which the sidecar maps back to them.
    Internal mode writes every value, and its documents must stay on the
    analyst's machine.

    Args:
        data: A pandas DataFrame, whose columns hold numbers, strings or
            booleans as :func:`formula_ir` reads them, or the path of a CSV
            file, which :func:`read_table` reads with the declaration.
        formula: The formula, as a str, such as
            ``"rt ~ cond + (1 + cond | subject)"``.
        declaration: ``None``, or a declaration as :func:`validate_declaration`
            accepts it: the path of a JSON or YAML file or a dict.
        family: ``None``, or the name of the family of the model that will be
            fitted: 'gaussian', 'binomial', 'poisson', 'negative_binomial',
            'beta', 'gamma', 'inverse_gaussian' or 'cumulative'.
        coding: The coding argument of :func:`formula_ir`.
        weights: The weights column of :func:`formula_ir`.
        sample_columns: The sample columns of :func:`formula_ir`.
        outcome_access: The highest tier of checks to run: 'T0', 'T1' or 'T2'.
        reason: The reason for reading the outcome, a text of 1 to 4000
            characters without control characters, which the access log
            records as given. It is required at T1 and T2 and refused at T0.
        exploratory: Whether the run is exploratory, which T2 requires.
        outcome_seen: ``None``, True or False: whether the outcome had been
            seen before the run, as for secondary data. ``None`` takes
            ``/provenance/outcome_seen`` of the declaration, when it has one,
            and a value that differs from it is refused.
        privacy: 'shareable' or 'internal'. Only an explicit 'internal' skips
            the privacy filter.
        key: ``None``, or the commitment key of the run as 64 lower-case
            hexadecimal digits. Without it, the run creates a key as
            :func:`new_commitment_key` does.

    Returns:
        A :class:`Results` object with the attributes ``document``, the
        results document in the form that :func:`read_json_strict` returns in
        the data profile, and ``sidecar``, the internal sidecar without
        ``results_hash``: its version, the commitment key of the run and the
        pseudonyms. Printing it shows the banner of its privacy mode and one
        line for each finding. :func:`write_results` writes it.

    Raises:
        MixedcheckError: A run that cannot proceed, whose ``issues`` hold one
            issue: E7008 for a family that is not accepted, E7009 for an
            access at T1 or T2 without a valid reason, at T2 without the
            exploratory mode or with a formula without a response, E1311 for a
            key of the wrong form, E1312 when no secure source of random bytes
            is available to create one, the error of
            :func:`validate_declaration` or :func:`read_table`, E5012 for a
            value of a DataFrame that is not one of the declared categories
            of its field, whether or not the formula reads its column, E5011
            for a column that the declaration names and the data lack, the
            error of :func:`formula_ir`, E6069 for a predictor, grouping
            variable, offset, weights column, sample column, column of the
            observation key, column of a declared unit or assigned column that
            is the response, holds its trials or is declared an outcome or
            derived from one, E7007 for a design sample, or at T1 and T2 an
            analysis sample, without rows, and the errors of
            :func:`design_matrices` for the values that the samples read.
        TypeError: An argument of the wrong type.
        ValueError: An argument with a value that is not accepted, such as a
            reason at T0 or an ``outcome_seen`` that differs from the
            declaration, data whose columns cannot be read, such as datetime
            columns, and an invalid MIXEDCHECK_TIME.

    Examples:
        >>> # Fixture Z08 of the pathology zoo: classes randomised within
        >>> # schools, with a formula that leaves out the class.
        >>> fixture = pathology_zoo("Z08")
        >>> key = bytes(range(32)).hex()
        >>> results = audit(fixture["data"], fixture["formula"], fixture["declaration"], key=key)
        >>> results.document["privacy"]["mode"]
        'shareable'
        >>> [f["message"]["id"] for f in results.document["findings"]
        ...  if f["check"] == "assignment.unit_in_random_part"]
        ['unit_missing']
        >>> # The quantile rule hides the size of the smallest school.
        >>> [f["statistics"]["smallest"]["availability"]["detail"]
        ...  for f in results.document["findings"] if f["check"] == "structure.cluster_sizes"]
        ['quantile']
        >>> # Internal mode writes every value.
        >>> results = audit(
        ...     fixture["data"], fixture["formula"], fixture["declaration"], privacy="internal",
        ...     key=key,
        ... )
        >>> [f["statistics"]["smallest"]["value"] for f in results.document["findings"]
        ...  if f["check"] == "structure.cluster_sizes"]
        [60]
        >>> # A family that audit() does not accept.
        >>> try:
        ...     audit(fixture["data"], "y ~ arm", family="logit", privacy="internal")
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["code"])
        E7008
    """
    # Step 1: the arguments.
    arguments = audit_arguments(
        data,
        formula,
        family,
        coding,
        weights,
        sample_columns,
        outcome_access,
        reason,
        exploratory,
        outcome_seen,
        privacy,
        key,
    )
    tier = arguments.tier
    # Step 2: the declaration, validated again as a minimal declaration.
    minimal: bool | None = None
    if declaration is not None:
        declaration = validate_declaration(declaration)
        try:
            validate_declaration(declaration, minimal=True)
            minimal = True
        except MixedcheckError:
            minimal = False
    seen = audit_outcome_seen(arguments.outcome_seen, declaration)
    # Step 3: the data.
    data_read = run_data(data, declaration)
    table = data_read.table
    # Step 4: the columns that the declaration names.
    declared_columns_present(declaration, table.keys)
    # Step 5: the IR, and a response for an access to the outcome.
    ir = build_formula_ir(
        arguments.formula,
        declaration,
        table,
        arguments.coding,
        arguments.weights,
        arguments.sample_columns,
    )
    if tier != "T0" and "response" not in ir:
        raise_issue("E7009", {"tier": tier, "requirement": "a formula with a response"})
    # Step 6: the columns that the outcome-blind checks may read.
    outcome_blind_columns(ir, declaration)
    # Step 7: the family class.
    family_class = audit_family_class(arguments.family, ir, declaration)
    # Step 8: the design sample, X and Z, without the response.
    model = design_model(ir, table, analysis=False)
    if len(model.design) == 0:
        raise_issue("E7007", {"sample": "design"})
    built = design_build(ir, model, table)
    run = new_run(declaration, table, ir, family_class, tier, model, built)
    # Step 9: at T1 and T2, the analysis sample and the response.
    if tier != "T0":
        analysis = analysis_rows(ir, table, model.design, model.column)
        if len(analysis) == 0:
            raise_issue("E7007", {"sample": "analysis"})
        response, trials = design_response(ir, model, table, analysis)
        run.analysis = analysis
        run.response = response
        run.trials = trials
    # Steps 10 and 11: the checks, the resolution of by_unit counts and the
    # order of the findings.
    checked = run_checks(run)
    findings = order_findings([resolve_finding_classes(run, f) for f in checked.findings])
    # Step 12: the privacy filter.
    pseudonyms: list[dict[str, Any]] = []
    if arguments.privacy == "shareable":
        findings, pseudonyms = privacy_filter(run, findings, arguments.key)
    # Step 13: the access log.
    access_log: dict[str, Any] = {
        "entries": access_log_entries(run, arguments, checked.times, data_read, declaration)
    }
    if seen is not None:
        access_log["outcome_seen"] = seen
    # Step 14: the inputs and the time of creation.
    response_column = ir["response"]["variable"] if "response" in ir else None
    inputs: dict[str, Any] = {"registry_hash": registry_hash()}
    if declaration is not None:
        inputs["declaration"] = {
            "hash": canonical_hash(declaration, "hashable"),
            "vocabulary": declaration["vocabulary"],
            "draft": "inferred" in declaration.get("provenance", {}),
            "minimal": minimal,
        }
    # A shareable document hashes the IR without the constants of its 'mean'
    # centrings, which are means over the design sample (documents.md, inputs).
    hashed = ir_without_means(ir) if arguments.privacy == "shareable" else ir
    inputs["model"] = {
        "formula": arguments.formula,
        "family_class": family_class,
        "ir_hash": canonical_hash(hashed, "hashable"),
    }
    inputs["data"] = data_commitments(data_read, declaration, response_column, arguments.key)

    document = {
        "results_version": "0.1.0",
        "created": utc_timestamp(run_time()),
        "stream": "B",
        "versions": {"package": __version__, **spec_versions()},
        "software": audit_software(run),
        "privacy": audit_privacy(run, arguments.privacy),
        "inputs": inputs,
        "access_log": access_log,
        "findings": [document_finding(finding) for finding in findings],
    }
    document = parse_json_bytes(canonical_bytes(document, "data"), "data")
    sidecar = {
        "sidecar_version": "0.1.0",
        "keys": [
            {
                "created": arguments.key_created,
                "key": arguments.key,
                "key_id": commitment_key_id(arguments.key),
            }
        ],
        "pseudonyms": pseudonyms,
    }
    return Results(document, sidecar)


# --- Arguments ------------------------------------------------------------------


@dataclass
class AuditArguments:
    """The arguments of a run that later steps use, after step 1, with the key
    and the time of its creation."""

    formula: str
    family: str | None
    coding: Any
    weights: str | None
    sample_columns: list[str]
    tier: str
    reason: str | None
    outcome_seen: bool | None
    privacy: str
    key: str
    key_created: str


def audit_arguments(
    data: Any,
    formula: Any,
    family: Any,
    coding: Any,
    weights: Any,
    sample_columns: Any,
    outcome_access: Any,
    reason: Any,
    exploratory: Any,
    outcome_seen: Any,
    privacy: Any,
    key: Any,
) -> AuditArguments:
    """Step 1: the arguments, checked for their types with ordinary errors,
    then E7008, E7009 for the reason and for T2 without the exploratory mode,
    and E1311 or E1312 for the key. Strings cross the input boundary."""
    import pandas as pd

    if not isinstance(data, pd.DataFrame | str | os.PathLike):
        raise TypeError("'data' must be a pandas DataFrame or the path of a CSV file.")
    if not isinstance(formula, str):
        raise TypeError("'formula' must be a str.")
    if family is not None and not isinstance(family, str):
        raise TypeError("'family' must be None or a str.")
    _check_coding_argument(coding)
    if weights is not None and not isinstance(weights, str):
        raise TypeError("'weights' must be None or a column name.")
    if sample_columns is not None and (
        isinstance(sample_columns, str)
        or not isinstance(sample_columns, Sequence)
        or not all(isinstance(name, str) for name in sample_columns)
    ):
        raise TypeError("'sample_columns' must be None or a list of column names.")
    if not isinstance(outcome_access, str):
        raise TypeError("'outcome_access' must be 'T0', 'T1' or 'T2'.")
    if outcome_access not in TIERS:
        raise ValueError("'outcome_access' must be 'T0', 'T1' or 'T2'.")
    if reason is not None and not isinstance(reason, str):
        raise TypeError("'reason' must be None or a str.")
    if outcome_access == "T0" and reason is not None:
        raise ValueError("'reason' is given only for outcome access at T1 or T2.")
    if not isinstance(exploratory, bool):
        raise TypeError("'exploratory' must be True or False.")
    if outcome_seen is not None and not isinstance(outcome_seen, bool):
        raise TypeError("'outcome_seen' must be None, True or False.")
    if not isinstance(privacy, str):
        raise TypeError("'privacy' must be 'shareable' or 'internal'.")
    if privacy not in ("shareable", "internal"):
        raise ValueError("'privacy' must be 'shareable' or 'internal'.")
    if key is not None and not isinstance(key, str):
        raise TypeError("'key' must be None or a str.")
    input_string(formula, ["formula"])
    if weights is not None:
        input_string(weights, ["weights"])
    names = list(sample_columns or [])
    for i, name in enumerate(names):
        input_string(name, ["sample_columns", str(i)])
    coding_value = coding_input(coding)
    if family is not None and family not in FAMILY_NAMES:
        raise_issue(
            "E7008",
            {"name": input_string(family, ["family"]), "expected": list(FAMILY_NAMES)},
        )
    if outcome_access != "T0":
        valid = False
        if reason is not None:
            input_string(reason, ["reason"])
            valid = 1 <= len(reason) <= 4000 and not any(
                ord(char) <= 0x1F or ord(char) == 0x7F for char in reason
            )
        if not valid:
            raise_issue(
                "E7009",
                {
                    "tier": outcome_access,
                    "requirement": "a reason of 1 to 4000 characters without control characters",
                },
            )
        if outcome_access == "T2" and not exploratory:
            raise_issue("E7009", {"tier": outcome_access, "requirement": "the exploratory mode"})
    key_created = utc_timestamp(run_time())
    if key is None:
        key = random_key_bytes().hex()
    else:
        commitment_key_bytes(key)
    return AuditArguments(
        formula=formula,
        family=family,
        coding=coding_value,
        weights=weights,
        sample_columns=names,
        tier=outcome_access,
        reason=reason,
        outcome_seen=outcome_seen,
        privacy=privacy,
        key=key,
        key_created=key_created,
    )


def audit_outcome_seen(argument: bool | None, declaration: Any) -> bool | None:
    """The attestation of the access log: the argument, or
    /provenance/outcome_seen of the declaration when the argument is None. The
    two must agree when both are given."""
    declared = None
    if isinstance(declaration, dict):
        declared = declaration.get("provenance", {}).get("outcome_seen")
    if argument is not None and declared is not None and argument != declared:
        raise ValueError("'outcome_seen' differs from /provenance/outcome_seen of the declaration.")
    return argument if argument is not None else declared


# --- Declaration and data ---------------------------------------------------------


def declared_column_places(declaration: Any) -> list[tuple[str, str]]:
    """The columns that a declaration names, with their pointers, in the order
    of the places that E2007 lists (declarations.md, Stage 4): unit columns,
    crossing lists, the observation key, the time column, assigned columns,
    the keys of variables, derived_from, trials, exposure columns, the
    outcomes of estimands, the primary key, the unique keys and the variables
    of estimand terms, each place in the order of its entries and the keys of
    variables in code-point order."""
    if not isinstance(declaration, dict):
        return []
    places: list[tuple[str, str]] = []

    def add(name: Any, *tokens: Any) -> None:
        if name is not None:
            places.append((name, path_pointer(*tokens)))

    for i, unit in enumerate(declaration.get("units", [])):
        for j, column in enumerate(unit.get("columns", [])):
            add(column, "units", i, "columns", j)
    for i, crossing in enumerate(declaration.get("crossings", [])):
        add(crossing.get("list"), "crossings", i, "list")
    observation = declaration.get("observation", {})
    for j, column in enumerate(observation.get("key", [])):
        add(column, "observation", "key", j)
    add(observation.get("time", {}).get("column"), "observation", "time", "column")
    for i, entry in enumerate(declaration.get("assignment", [])):
        add(entry.get("column"), "assignment", i, "column")
    variables = declaration.get("variables", {})
    ordered = sorted(variables)
    for name in ordered:
        add(name, "variables", name)
    for name in ordered:
        for j, column in enumerate(variables[name].get("derived_from", [])):
            add(column, "variables", name, "derived_from", j)
    for name in ordered:
        add(variables[name].get("trials"), "variables", name, "trials")
    for name in ordered:
        add(
            variables[name].get("exposure", {}).get("column"),
            "variables",
            name,
            "exposure",
            "column",
        )
    estimands = declaration.get("estimands", [])
    for i, estimand in enumerate(estimands):
        add(estimand.get("outcome"), "estimands", i, "outcome")
    table = declaration.get("table", {})
    for j, column in enumerate(table.get("primaryKey", [])):
        add(column, "table", "primaryKey", j)
    for i, unique in enumerate(table.get("uniqueKeys", [])):
        for j, column in enumerate(unique):
            add(column, "table", "uniqueKeys", i, j)
    for i, estimand in enumerate(estimands):
        if "term" in estimand:
            for name in dict.fromkeys(term_variables(estimand["term"])):
                add(name, "estimands", i, "term")
    return places


def declared_columns_present(declaration: Any, keys: Sequence[str]) -> None:
    """Step 4: E5011 for the first column that the declaration names and the
    data lack, compared after NFC, whatever the table block."""
    present = set(keys)
    for name, pointer in declared_column_places(declaration):
        if comparison_form(name) not in present:
            raise_issue("E5011", {"column": name}, pointer=pointer)


def outcome_blind_columns(ir: dict[str, Any], declaration: Any) -> None:
    """Step 6: E6069 for the first column that the outcome-blind checks would
    read and that is the response, its trials column or a column that the
    declaration gives the role outcome or outcome_derived (registry.md, Tier
    and inputs). The columns come in this order: the predictors in code-point
    order, the grouping variables in the order of the IR, the offsets, the
    weights, the sample columns of the IR, the key in its declared order, the
    columns of the declared units and the assigned columns, each block in its
    declared order and leaving out what counts as absent."""
    refused = set(declared_role_columns(declaration, ("outcome", "outcome_derived")))
    response = ir.get("response")
    if response is not None:
        refused.add(response["variable"])
        if "trials" in response:
            refused.add(response["trials"])
    if not refused:
        return
    given = (
        sort_identifiers(ir["predictors"])
        + [key for term in ir["random"] for key in term["grouping"]]
        + [o["variable"] for o in ir["offsets"]]
        + ([ir["weights"]["variable"]] if "weights" in ir else [])
        + list(ir.get("sample_columns", []))
        + observation_key_columns(declaration)
        + [column for unit in declared_units(declaration).values() for column in unit["columns"]]
        + [entry["column"] for entry in assignment_elements(declaration)]
    )
    for column in given:
        if comparison_form(column) in refused:
            raise_issue("E6069", {"column": column})


def audit_family_class(family: str | None, ir: dict[str, Any], declaration: Any) -> str:
    """Step 7: the family class (registry.md, Family classes)."""
    if family is not None:
        if family == "gaussian":
            return "gaussian"
        if family == "binomial":
            return "binomial" if "trials" in ir.get("response", {}) else "bernoulli"
        if family in ("poisson", "negative_binomial"):
            return "poisson"
        return "other"
    measurement = None
    response = ir.get("response")
    if response is not None and isinstance(declaration, dict):
        variables = declaration.get("variables", {})
        for name, entry in variables.items():
            if comparison_form(name) == response["variable"]:
                pointer = path_pointer("variables", name, "measurement")
                if not declaration_inferred(declaration, pointer):
                    measurement = entry.get("measurement")
                break
    return {
        "binary": "bernoulli",
        "binomial": "binomial",
        "count": "poisson",
        "ordinal": "other",
    }.get(measurement or "", "gaussian")


# --- The document -----------------------------------------------------------------


def access_log_entries(
    run: Run,
    arguments: AuditArguments,
    times: Mapping[str, str],
    data: RunData,
    declaration: Any,
) -> list[dict[str, Any]]:
    """Step 13: one entry at T0 and, for each further tier that the run
    reached, one entry for the response and then one for its trials column
    when the IR's response has one, whether or not a check of the tier read
    them, each with its outcome commitment, computed once for each column, and
    the reason. The time of each tier is the time at which its checks
    started."""
    entries: list[dict[str, Any]] = [{"tier": "T0", "time": times["T0"], "mode": "outcome_blind"}]
    reached = TIERS[1 : TIERS.index(run.tier) + 1]
    response = run.ir.get("response")
    columns: list[str] = []
    if response is not None:
        columns = [response["variable"]] + ([response["trials"]] if "trials" in response else [])
    commitments = []
    if reached:
        commitments = [
            outcome_commitment(data, declaration, column, arguments.key) for column in columns
        ]
    for tier in reached:
        for column, commitment in zip(columns, commitments, strict=True):
            entries.append(
                {
                    "tier": tier,
                    "time": times[tier],
                    "mode": "exploratory",
                    "outcome": {"column": column, "commitment": commitment},
                    "reason": arguments.reason,
                }
            )
    outcome_reads_logged(run, entries)
    return entries


def audit_software(run: Run) -> dict[str, Any]:
    """software: the language, the version of Python, the NFC library and the
    packages that the checks record in run.packages, such as the solver of
    outcome.separation, which that check records whenever it is available."""
    software: dict[str, Any] = {
        "language": "Python",
        "runtime": platform.python_version(),
        "unicode": {"library": "unicodedata", "version": unicodedata.unidata_version},
    }
    if run.packages:
        software["packages"] = dict(run.packages)
    return software


def audit_privacy(run: Run, mode: str) -> dict[str, Any]:
    """privacy: the mode, the parameters of the filter, copied from the compiled
    registry, and the disclosure unit."""
    parameters = registry_document()["privacy"]
    privacy: dict[str, Any] = {
        "mode": mode,
        "min_count": parameters["min_count"],
        "dominance": parameters["dominance"],
        "rounding_base": parameters["rounding_base"],
        "zeros_disclosive": parameters["zeros_disclosive"],
    }
    if run.disclosure is not None:
        privacy["disclosure_unit"] = {
            "name": run.disclosure.name,
            "source": run.disclosure.source,
        }
    return privacy


def ir_without_means(ir: dict[str, Any]) -> dict[str, Any]:
    """The IR that the IR hash of a shareable document covers: each 'mean'
    centring holds the significant digits of its constant in place of the
    constant, as before the data are seen (ir.md, The IR document), since the
    constant is a mean over the design sample, which an unkeyed hash would
    let a reader confirm by search."""
    predictors = {}
    for name, predictor in ir["predictors"].items():
        centring = predictor.get("centring", {})
        if centring.get("rule") == "mean" and "constant" in centring:
            predictor = {
                **predictor,
                "centring": {
                    "rule": "mean",
                    "sample": centring["sample"],
                    "significant_digits": centring["constant"]["significant_digits"],
                },
            }
        predictors[name] = predictor
    return {**ir, "predictors": predictors}
