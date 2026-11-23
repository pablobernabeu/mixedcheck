"""The privacy filter of shareable mode (docs/spec/privacy.md), step 12 of
:func:`audit` (03-execution-plan.md, M2). It takes the internal findings of a
run in the order of documents.md (Findings), with their by_unit counts
resolved, and marks the values that a shareable document does not write.
:func:`document_finding` then writes each finding from its marks. Step 7, the
rules across findings, is in _privacy_across.py. The functions have the names
of their counterparts in the R package's privacy.R and privacy-across.R.

The marks of a finding are:

- ``suppressed``: the detail of each statistic that the filter suppressed, by
  name, which includes the absent statistics of step 8
- ``support_suppressed``: the detail of support.rows and of
  support.contributors.distinct, by 'rows' and 'distinct', when suppressed
- ``whole``: True for a finding that step 9 suppresses as a whole
- ``left_written``: the statistics that steps 1 to 5 left written, which the
  rule part_of reads
"""

from __future__ import annotations

from collections.abc import Iterable
from fractions import Fraction
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import Finding, Run
from mixedcheck._hash import commitment_key_bytes, hmac_sha256
from mixedcheck._json_write import canonical_bytes
from mixedcheck._messages import render_message
from mixedcheck._registry import registry_document
from mixedcheck._results_validate import quantile_decimal, quantile_shown, quantiles_spaced

if TYPE_CHECKING:
    from mixedcheck._checks import Array


def privacy_filter(
    run: Run, findings: list[Finding], key: str
) -> tuple[list[Finding], list[dict[str, str]]]:
    """Step 12: the shareable findings of a run and the pseudonyms of their
    labels, in the form that the internal sidecar records them. ``key`` is the
    commitment key of the run, as 64 hexadecimal digits."""
    # The rules across findings call the steps of this module, so the module
    # that holds them is imported here, once this one is loaded.
    from mixedcheck._privacy_across import privacy_across

    k = int(registry_document()["privacy"]["min_count"])
    for finding in findings:
        if not finding.available:
            continue
        finding.suppressed = {}
        finding.support_suppressed = {}
        finding.whole = False
        privacy_internal_only(finding)
        privacy_minimum_rules(finding, k)
        privacy_small_counts(finding, k)
        privacy_quantiles(finding, k)
        privacy_ratios(finding, k)
        finding.left_written = [name for name in finding.values if name not in finding.suppressed]
        privacy_within(finding, k)
    privacy_across(run, findings, k)
    for finding in findings:
        if finding.available:
            privacy_within(finding, k)
            privacy_absent(finding)
            privacy_decision(finding, run, k)
    pseudonyms = privacy_pseudonyms(findings, key)
    for finding in findings:
        privacy_render(finding, pseudonyms)
    return findings, pseudonyms


# --- Marks ------------------------------------------------------------------------------


def privacy_written(finding: Finding, name: str) -> bool:
    """Whether a statistic of a finding is written: present and not
    suppressed."""
    return finding.values.get(name) is not None and name not in finding.suppressed


def privacy_suppress(
    finding: Finding, names: Iterable[str], detail: str, replace: bool = False
) -> Finding:
    """Suppress the statistics of a finding that are still written with a
    detail. A statistic that an earlier step suppressed keeps its detail,
    unless ``replace`` is True and that detail is 'min_count': a rule after
    step 3 that suppresses a count then gives it the detail 'secondary', so
    that the detail does not show on which side of k the count lies
    (privacy.md, Steps)."""
    names = list(names)
    if replace:
        for name in names:
            if finding.suppressed.get(name) == "min_count":
                finding.suppressed[name] = detail
    for name in dict.fromkeys(names):
        if privacy_written(finding, name):
            finding.suppressed[name] = detail
    return finding


def privacy_person(finding: Finding, name: str, ratio: bool = False) -> bool:
    """Whether a statistic of a finding is a count, or with ``ratio`` True a
    count or a ratio, of class person as resolved for the finding."""
    statistic = finding.statistics.get(name)
    kinds = ("count", "ratio") if ratio else ("count",)
    return bool(
        statistic is not None
        and statistic["kind"] in kinds
        and statistic.get("count_class") == "person"
    )


def entry_statistics(finding: Finding) -> dict[str, Any]:
    """The statistics that the entry of a finding defines, by name."""
    assert finding.entry is not None
    defined: dict[str, Any] = finding.entry["statistics"]
    return defined


# --- Steps 1 to 6 -----------------------------------------------------------------------


def privacy_internal_only(finding: Finding) -> Finding:
    """Step 1: the statistics that the entry marks internal_only."""
    defined = entry_statistics(finding)
    internal = [name for name, s in defined.items() if s.get("internal_only") is True]
    return privacy_suppress(finding, internal, "internal_only")


def privacy_minimum_rules(finding: Finding, k: int) -> Finding:
    """Step 2: in a finding that fails the minimum-count or the dominance
    rule, every real, reals and labels value and every person count and
    ratio."""
    support = finding.support
    assert support is not None
    fails_minimum = support.distinct < k
    if not fails_minimum and not support.dominated:
        return finding
    names = [
        name
        for name in finding.values
        if finding.statistics[name]["kind"] in ("real", "reals", "labels")
        or privacy_person(finding, name, ratio=True)
    ]
    return privacy_suppress(finding, names, "min_count_rule" if fails_minimum else "dominance")


def privacy_small_counts(finding: Finding, k: int) -> Finding:
    """Step 3: every person count still written that is below k, 0 included,
    support.rows and support.contributors.distinct among them, other than a
    quantile that step 4 suppresses, a minimum or a maximum among them, which
    step 4 suppresses whatever its value, so that its detail does not show on
    which side of k it lies."""
    names = [
        name
        for name in finding.values
        if privacy_person(finding, name)
        and finding.values[name] < k
        and not privacy_quantile_hidden(finding, name, k)
    ]
    privacy_suppress(finding, names, "min_count")
    support = finding.support
    assert support is not None
    for member, value in (("rows", support.rows), ("distinct", support.distinct)):
        if value < k:
            finding.support_suppressed[member] = "min_count"
    return finding


def privacy_quantiles(finding: Finding, k: int) -> Finding:
    """Step 4: a p-quantile of n values unless n x min(m, 10^d - m) >= k x 10^d,
    with n the internal value of the count that the entry names, and a
    quantile that the spacing condition drops."""
    names = [name for name in finding.values if privacy_quantile_hidden(finding, name, k)]
    return privacy_suppress(finding, names, "quantile")


def privacy_quantile_hidden(finding: Finding, name: str, k: int) -> bool:
    """Whether a statistic is a quantile that step 4 suppresses: its n, the
    internal value of the count that its entry names, is absent or fails the
    quantile rule, as it always does for a minimum or a maximum, or the
    spacing condition drops it."""
    quantile = finding.statistics[name].get("quantile")
    if quantile is None:
        return False
    n = finding.values.get(quantile["n"])
    return (
        n is None
        or not quantile_shown(n, quantile["p"], k)
        or name in privacy_unspaced_quantiles(finding, k)
    )


def privacy_unspaced_quantiles(finding: Finding, k: int) -> list[str]:
    """The quantiles of a finding that the spacing condition of step 4 drops.
    The quantiles that meet the quantile rule are taken by increasing distance
    of p from 0.5 and, at equal distances, by increasing p, and each is kept
    when it is spaced from every quantile with the same n kept before it, and
    dropped otherwise, so that the quantiles nearest the median stay. They
    depend on the entry and the internal values alone, so that steps 3 and 4
    agree on them whatever other rules suppress."""
    shown: list[tuple[str, Any, str]] = []
    for name in finding.values:
        quantile = finding.statistics[name].get("quantile")
        if quantile is None:
            continue
        n = finding.values.get(quantile["n"])
        if n is not None and quantile_shown(n, quantile["p"], k):
            shown.append((name, n, quantile["p"]))
    if len(shown) < 2:
        return []
    shown.sort(key=lambda item: quantile_centre_key(item[2]))
    kept: list[tuple[str, Any, str]] = []
    dropped: list[str] = []
    for name, n, p in shown:
        if all(n != other_n or quantiles_spaced(n, p, other_p, k) for _, other_n, other_p in kept):
            kept.append((name, n, p))
        else:
            dropped.append(name)
    return dropped


def quantile_centre_key(p: str) -> tuple[Fraction, Fraction]:
    """The key that orders quantiles p, decimal strings strictly between 0 and
    1, by increasing distance from 0.5 and, at equal distances, increasing p,
    both exact."""
    decimal = quantile_decimal(p)
    assert decimal is not None
    value = Fraction(decimal[0], 10 ** decimal[1])
    return abs(value - Fraction(1, 2)), value


def privacy_ratios(finding: Finding, k: int) -> Finding:
    """Step 5: a ratio whose numerator or denominator is suppressed, whatever
    its class, or is a person count below k. A non-person count that a rule
    across findings suppresses would otherwise follow from the ratio and the
    other count, as multi_row_levels of outcome.constant_clusters follows from
    constant_levels and constant_share."""
    defined = entry_statistics(finding)
    names = []
    for name in finding.values:
        statistic = defined[name]
        if statistic["kind"] != "ratio":
            continue
        parts = (statistic["numerator"], statistic["denominator"])
        if any(
            part in finding.suppressed
            or (privacy_person(finding, part) and finding.values[part] < k)
            for part in parts
        ):
            names.append(name)
    return privacy_suppress(finding, names, "ratio")


def privacy_within(finding: Finding, k: int) -> Finding:
    """Step 6: the relations within a finding, suppress_with, part_of and the
    n of quantiles, with step 5, until no value or detail changes. part_of
    reads the internal values of a person total and of the parts that steps 1
    to 5 left written, so that its result does not depend on the order of the
    rules. suppress_with, part_of and the n of a quantile also replace the
    detail 'min_count' that step 3 gave, which would show that the value is
    below k and so bound the suppressed statistic, its partner or the n:
    'secondary' when a statistic that suppress_with names is suppressed, and
    that statistic names this one back, as the parts of a total do, or is
    suppressed with another detail, 'secondary' for a part of a person total,
    and 'quantile' when the count that gives n is suppressed."""
    defined = entry_statistics(finding)
    part_of = {name: s["part_of"] for name, s in defined.items() if "part_of" in s}
    while True:
        before = dict(finding.suppressed)
        for name in finding.values:
            named = defined[name].get("suppress_with", [])
            with_ = [s for s in dict.fromkeys(named) if s in finding.suppressed]
            if with_:
                privacy_suppress(finding, [name], "secondary")
                # The parts of a total name each other, and a statistic
                # derived from another names it alone.
                back = [name in defined[s].get("suppress_with", []) for s in with_]
                if finding.suppressed.get(name) == "min_count" and any(
                    named_back or finding.suppressed[s] != "min_count"
                    for s, named_back in zip(with_, back, strict=True)
                ):
                    finding.suppressed[name] = "secondary"
        for total in dict.fromkeys(part_of.values()):
            value = finding.values.get(total)
            if value is None or not privacy_person(finding, total):
                continue
            parts = [name for name, of in part_of.items() if of == total]
            left = [part for part in parts if part in finding.left_written]
            counts = [finding.values[part] for part in left]
            if left and (any(value - c < k for c in counts) or value - sum(counts) < k):
                privacy_suppress(finding, parts, "secondary", replace=True)
            # A part below k has the detail 'secondary', since the rule above
            # suppresses the parts at least k whose remainder is below k.
            small = [
                part
                for part in parts
                if finding.values.get(part) is not None and finding.values[part] < k
            ]
            privacy_suppress(finding, small, "secondary", replace=True)
        for name in finding.values:
            quantile = finding.statistics[name].get("quantile")
            if quantile is not None and quantile["n"] in finding.suppressed:
                privacy_suppress(finding, [name], "quantile")
                if finding.suppressed.get(name) == "min_count":
                    finding.suppressed[name] = "quantile"
        privacy_ratios(finding, k)
        if finding.suppressed == before:
            return finding


# --- Steps 8 and 9 ----------------------------------------------------------------------


def privacy_absent(finding: Finding) -> Finding:
    """Step 8: a statistic that its entry marks internal_only and that its
    definition leaves absent, a ratio that its definition leaves absent, when
    its numerator or denominator is suppressed, and a quantile that its
    definition leaves absent, when the count that gives its n is suppressed,
    are written as suppressed. A by_unit ratio or quantile takes the class of
    the count it derives from, and a by_unit internal_only count, which
    resolves over no levels, the class person."""
    defined = entry_statistics(finding)
    for name, statistic in defined.items():
        if name in finding.values:
            continue
        kind = statistic["kind"]
        written: dict[str, Any] = {"kind": kind}
        if statistic.get("internal_only") is True:
            if kind in ("count", "ratio"):
                written["count_class"] = statistic["count_class"]
                if written["count_class"] == "by_unit":
                    written["count_class"] = "person"
            finding.statistics[name] = written
            finding.suppressed[name] = "internal_only"
            continue
        if kind == "ratio":
            parts = [statistic["numerator"], statistic["denominator"]]
        else:
            parts = [statistic["quantile"]["n"]] if "quantile" in statistic else []
        found = [part for part in dict.fromkeys(parts) if part in finding.suppressed]
        if not found:
            continue
        if kind in ("count", "ratio"):
            written["count_class"] = statistic["count_class"]
            if written["count_class"] == "by_unit":
                written["count_class"] = finding.statistics[found[0]].get("count_class")
        if "quantile" in statistic:
            written["quantile"] = statistic["quantile"]
        finding.statistics[name] = written
        finding.suppressed[name] = "ratio" if kind == "ratio" else "quantile"
    return finding


def privacy_decision(finding: Finding, run: Run, k: int) -> Finding:
    """Step 9: a finding of tier T1 or T2 is suppressed as a whole when a
    person count or ratio that a rule of its decision reads, in the rule that
    held or a rule before it, or in any rule when none held, is suppressed,
    when it fails the minimum-count rule on fewer than k rows or with
    contributors bounded from below by k - 1 (privacy_small_sample()), when it
    is scoped to an item of two crossed columns that privacy_crossed_guarded()
    names, and a finding of outcome.separation by the rules of privacy.md
    (Decisions)."""
    if finding.tier not in ("T1", "T2"):
        return finding
    assert finding.entry is not None
    rules = finding.entry["decision"]["rules"]
    read = rules if finding.rule is None else rules[: finding.rule + 1]
    names = dict.fromkeys(name for rule in read for name in rule.get("statistics", []))
    # events and non_events that Across findings suppresses only with the rows
    # of the analysis sample are k or more, so they count as written here.
    hidden = any(
        privacy_person(finding, name, ratio=True)
        and name in finding.suppressed
        and name not in finding.with_rows
        for name in names
    )
    if (
        hidden
        or finding.guarded
        or privacy_small_sample(finding, k)
        or (finding.check == "outcome.separation" and privacy_separation(finding, run, k))
    ):
        finding.whole = True
    return finding


def privacy_small_sample(finding: Finding, k: int) -> bool:
    """Whether a finding that fails the minimum-count rule has fewer than k
    rows, or contributors that the findings on the analysis sample bound from
    below by k - 1, as privacy_contributors_bound() computes it and step 7
    records in ``bounded`` (privacy.md, Decisions). Its rows would otherwise
    be shown below k, where a written quantity of a larger sample, which shows
    that rule 1 did not fire, bounds them from above by that quantity less k:
    beside 11 written rows of the design sample, a finding whose rows the
    detail 'min_count' shows below k has one analysed row, since a sample with
    an available finding has a row. The detail 'min_count' shows its
    contributors below k, so a bound of k - 1 would leave them one value."""
    support = finding.support
    assert support is not None
    if support.distinct >= k:
        return False
    return support.rows < k or finding.bounded


def privacy_separation(finding: Finding, run: Run, k: int) -> bool:
    """Whether the filter suppresses a finding of outcome.separation as a
    whole beyond the rule on its decision: when the design sample, or the
    analysis sample on which the check ran, has at most two kept columns,
    kept of design.rank_deficiency or 0 without its finding for the design
    sample, when its kept columns other than the intercept belong to terms
    that read one variable alone, or when two of its rows share the values of
    every kept column, and, for the class binomial, when the rows with k = 0,
    with k = n or with both classes, which the rows of the analysis sample,
    events and non_events give back, number fewer than k, 0 included."""
    import numpy as np

    required = run.results.get("design.rank_deficiency", [])
    kept = 0
    if required and required[0].values.get("kept") is not None:
        kept = int(required[0].values["kept"])
    assert run.analysis is not None and run.analysis_kept is not None
    x_kept = np.asarray(run.x_kept, dtype=bool)
    analysis_kept = np.asarray(run.analysis_kept, dtype=bool)
    position = np.full(run.table.rows, -1, dtype=np.int64)
    position[run.design] = np.arange(len(run.design), dtype=np.int64)
    analysis = position[run.analysis]
    # The analysis sample keeps no column that the design sample drops, so
    # the test of its kept columns implies that of the design sample
    # whenever design.rank_deficiency yields a finding. Both are kept as
    # privacy.md (Decisions) states them.
    if (
        kept <= 2
        or int(analysis_kept.sum()) <= 2
        or separation_one_variable(run, x_kept)
        or separation_one_variable(run, analysis_kept)
        or separation_shared_values(run.x[:, x_kept])
        or separation_shared_values(run.x[np.ix_(analysis, analysis_kept)])
    ):
        return True
    if run.family_class != "binomial":
        return False
    support = finding.support
    assert support is not None
    rows = support.rows
    events = int(finding.values["events"])
    non_events = int(finding.values["non_events"])
    return min(rows - events, rows - non_events, events + non_events - rows) < k


def separation_one_variable(run: Run, kept: Array) -> bool:
    """Whether the kept fixed-effects columns other than the intercept, as a
    boolean array over the columns of X, belong to terms that read one
    variable alone, or to none."""
    terms = run.ir["fixed"]["terms"]
    columns = run.ir["fixed"]["columns"]
    variables: set[str] = set()
    for t in dict.fromkeys(columns[j]["term"] for j in range(len(columns)) if kept[j]):
        variables.update(v["variable"] for v in terms[t]["variables"])
    return len(variables) <= 1


def separation_shared_values(x: Array) -> bool:
    """Whether two rows of a matrix of kept columns hold equal values in every
    column, so that the columns divide the rows into combinations of which one
    holds two rows or more."""
    import numpy as np

    n = x.shape[0]
    if n < 2:
        return False
    # numpy.unique() compares the rows as floats, so -0 equals 0. Adding 0
    # mirrors the R package, whose sort needs it.
    rows = np.ascontiguousarray(np.asarray(x, dtype=np.float64) + 0.0)
    return bool(len(np.unique(rows, axis=0)) < n)


# --- Steps 10 and 11 --------------------------------------------------------------------


def privacy_pseudonyms(findings: list[Finding], key: str) -> list[dict[str, str]]:
    """Step 10: the pseudonyms of the labels that the shareable findings write,
    as a list of the pseudonym, the factor and the label: one for each
    distinct pair of a factor and a label, numbered in increasing order of the
    HMAC-SHA-256 of the canonical bytes of the array of the two under the
    commitment key, the digests compared as lower-case hexadecimal strings."""
    pairs: dict[tuple[str, str], None] = {}
    for finding in findings:
        if not finding.available or finding.whole:
            continue
        for name, values in finding.values.items():
            if finding.statistics[name]["kind"] == "labels" and privacy_written(finding, name):
                factor = finding.label_factors[name]
                for label in values:
                    pairs[(factor, label)] = None
    secret = commitment_key_bytes(key)
    digests = {pair: hmac_sha256(secret, canonical_bytes(list(pair), "data")) for pair in pairs}
    ordered = sorted(pairs, key=lambda pair: digests[pair])
    return [
        {"pseudonym": f"#{i}", "factor": factor, "label": label}
        for i, (factor, label) in enumerate(ordered, start=1)
    ]


def privacy_render(finding: Finding, pseudonyms: list[dict[str, str]]) -> Finding:
    """Steps 10 and 11 for one finding: its labels replaced by their
    pseudonyms and its message rendered again from the written values, the
    template when every statistic that it renders is written and the fallback
    otherwise."""
    if not finding.available or finding.whole:
        return finding
    values = dict(finding.values)
    for name in finding.values:
        if finding.statistics[name]["kind"] == "labels" and privacy_written(finding, name):
            factor = finding.label_factors[name]
            mine = {p["label"]: p["pseudonym"] for p in pseudonyms if p["factor"] == factor}
            values[name] = [mine[label] for label in finding.values[name]]
    finding.values = values
    written = [name for name in finding.values if privacy_written(finding, name)]
    assert finding.entry is not None and finding.message is not None
    text = render_message(finding.entry, finding.message["id"], finding.scope, values, written)
    finding.message = {**finding.message, "text": text}
    return finding
