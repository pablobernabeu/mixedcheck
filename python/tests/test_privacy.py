"""The privacy filter of shareable mode (docs/spec/privacy.md): each channel of
disclosure by differencing that the filter closes, tried on inputs of these
tests, the pseudonyms of labels, which registry 0.1.0 does not write, and the
steps that the audit corpus cannot reach. Each test mirrors the test of the R
package's test-privacy.R whose name it takes, with the same data where R's
random number generator does not build them. Every shareable document that a
test produces must pass validate_results()."""

from __future__ import annotations

import re
import statistics
import warnings
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

from mixedcheck import (
    audit,
    canonical_bytes,
    canonical_hash,
    formula_ir,
    validate_results,
    write_results,
)
from mixedcheck._checks import Finding, Support, assemble_finding, check_element, document_finding
from mixedcheck._hash import commitment_key_bytes, hmac_sha256
from mixedcheck._privacy import (
    privacy_absent,
    privacy_minimum_rules,
    privacy_pseudonyms,
    privacy_render,
    separation_shared_values,
)
from mixedcheck._privacy_across import (
    ItemQuantities,
    SampleMarks,
    SampleQuantities,
    privacy_blank_marks,
    privacy_rows_without_singletons,
    privacy_rule_3,
    quantile_position,
)
from mixedcheck._results_validate import shareable_finding_issues

PRIVACY_KEY = AUDIT_KEY


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


# --- Helpers ----------------------------------------------------------------------------


def rep(values: Any, times: int | list[int] = 1, each: int = 1) -> list[Any]:
    """R's rep(): the values, each repeated 'each' times, then the whole
    repeated 'times' times, or each value repeated as often as the matching
    element of a list 'times' says."""
    base = [values] if values is None or isinstance(values, str | int | float) else list(values)
    expanded = [value for value in base for _ in range(each)]
    if isinstance(times, int):
        return expanded * times
    return [value for value, n in zip(expanded, times, strict=True) for _ in range(n)]


def rep_len(values: list[Any], length: int) -> list[Any]:
    """R's rep(values, length.out = length)."""
    return [values[i % len(values)] for i in range(length)]


def labels(template: str, numbers: Any) -> list[str]:
    """R's sprintf() of one template over numbers."""
    return [template % number for number in numbers]


def seq_len(n: int) -> list[int]:
    """R's seq_len(): 1 to n."""
    return list(range(1, n + 1))


def frame(**columns: list[Any]) -> pd.DataFrame:
    """A data frame as R's data.frame() builds it: a column with None, R's NA,
    holds objects, so that None is a missing value."""
    return pd.DataFrame(
        {
            name: pd.Series(values, dtype=object)
            if any(value is None for value in values)
            else pd.Series(values)
            for name, values in columns.items()
        }
    )


def audit_both(data: pd.DataFrame, formula: str, **arguments: Any) -> dict[str, Any]:
    """Run audit() at the time 0 in both modes with the example key, and check
    that the shareable document is valid."""

    def run(privacy: str) -> Any:
        return audit(data, formula, privacy=privacy, key=PRIVACY_KEY, **arguments)

    shareable = run("shareable")
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        validate_results(shareable)
    return {"internal": run("internal").document, "shareable": shareable.document}


def finding_of(document: dict[str, Any], check: str, **scope: str) -> dict[str, Any]:
    """The finding of a check whose scope has the given parts."""
    for finding in document["findings"]:
        if finding["check"] == check and all(
            finding["scope"].get(part) == value for part, value in scope.items()
        ):
            return finding  # type: ignore[no-any-return]
    raise AssertionError(f"no finding of {check}")


def written(finding: dict[str, Any], name: str) -> Any:
    """The written value of a statistic, or of support.rows or
    support.contributors.distinct, and None when it is not written."""
    if name == "support_rows":
        return finding["support"]["rows"]["value"]
    if name == "contributors":
        return finding["support"]["contributors"]["distinct"]["value"]
    statistic = finding.get("statistics", {}).get(name)
    return None if statistic is None else statistic.get("value")


def detail(finding: dict[str, Any], name: str) -> Any:
    """The detail of a suppressed statistic, or None."""
    statistic = finding.get("statistics", {}).get(name)
    return None if statistic is None else statistic.get("availability", {}).get("detail")


def support_detail(finding: dict[str, Any], member: str) -> Any:
    """The detail of support.rows, or of support.contributors.distinct for
    'distinct', when suppressed."""
    support = finding["support"]
    value = support["rows"] if member == "rows" else support["contributors"]["distinct"]
    return value.get("availability", {}).get("detail")


def recover_difference(a: Any, b: Any) -> Any:
    """The difference a - b of two written counts, as an attempt to recover a
    suppressed one, or None when either is not written."""
    return None if a is None or b is None else a - b


def expect_message_falls_back(finding: dict[str, Any], id: str) -> None:
    """The message of a shareable finding is its fallback, which holds no
    number."""
    assert finding["message"]["id"] == id
    assert re.search("[0-9]", finding["message"]["text"]) is None


def units(*declared: dict[str, Any], **members: Any) -> dict[str, Any]:
    """A declaration of vocabulary 0.1.0 with the units given and other
    members."""
    declaration: dict[str, Any] = {"vocabulary": "0.1.0"}
    if declared:
        declaration["units"] = list(declared)
    declaration.update(members)
    return declaration


def unit(name: str, role: str, **members: Any) -> dict[str, Any]:
    """A declared unit whose one label column has its name."""
    return {"name": name, "columns": [name], "role": role, **members}


def school_pupil() -> dict[str, Any]:
    """Schools, a cluster, and pupils, the participants, with labels unique
    across schools."""
    return units(
        unit("school", "cluster"),
        unit("pupil", "participant", nested_in="school", id_scope="global"),
    )


def subject_declaration(**members: Any) -> dict[str, Any]:
    """Subjects as the participants."""
    return units(unit("subject", "participant"), **members)


def assignment(column: str, unit_name: str, level: str = "between_unit") -> dict[str, Any]:
    """A randomised assignment of a column to a unit."""
    return {"column": column, "unit": unit_name, "randomised": True, "level": level}


T1_ZEROS = {"family": "poisson", "outcome_access": "T1", "reason": "Zeros."}


def test_shareable_mode_is_the_default_and_writes_no_commitment_key(tmp_path: Path) -> None:
    data = frame(
        y=[i + 0.5 for i in seq_len(24)],
        x=rep(range(1, 13), 2),
        subject=rep(labels("s%02d", range(1, 13)), 2),
    )
    results = audit(data, "y ~ x + (1 | subject)", key=PRIVACY_KEY)
    assert results.document["privacy"]["mode"] == "shareable"
    assert str(results).split("\n")[0] == (
        "Shareable output: the privacy filter has reduced the risk of disclosure, "
        "but this report is not anonymous data."
    )
    assert results.sidecar["pseudonyms"] == []
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        validate_results(results)
    path = tmp_path / "audit.json"
    sidecar = tmp_path / "audit.internal.json"
    write_results(results, path, sidecar)
    assert PRIVACY_KEY.encode("ascii") not in path.read_bytes()
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        validate_results(path, sidecar, data=data)


def test_a_part_of_a_total_cannot_be_recovered_from_the_total_and_the_other_part() -> None:
    # 40 subjects of two rows, 3 of which lack 'x', so that 3 rows leave the
    # design sample: rows_raw - rows_kept would give rows_dropped. The two
    # parts name each other and both have the detail 'secondary', so that
    # neither shows which part is below k.
    data = frame(
        y=[i / 4 for i in seq_len(80)],
        x=[None] * 3 + [i % 7 for i in seq_len(77)],
        subject=rep(labels("s%02d", range(1, 41)), each=2),
    )
    found = audit_both(data, "y ~ x + (1 | subject)")
    internal = finding_of(found["internal"], "sample.raw_vs_analysis")
    assert written(internal, "rows_dropped") == 3
    shared = finding_of(found["shareable"], "sample.raw_vs_analysis")
    assert detail(shared, "rows_dropped") == "secondary"
    assert recover_difference(written(shared, "rows_raw"), written(shared, "rows_kept")) is None
    assert detail(shared, "rows_kept") == "secondary"
    # Nor from the sizes of the table and the design sample, which other
    # findings write in their supports and statistics.
    design = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(design, "support_rows") == 77
    assert written(shared, "support_rows") is None
    assert written(shared, "rows_raw") is None
    expect_message_falls_back(shared, "rows_dropped")


def test_parts_of_a_total_whose_remainder_is_below_min_count_are_suppressed() -> None:
    # 40 rows, 12 under 6 repeated key values, 22 without a key and 6 with a
    # key of their own: the rows minus both parts would give back the 6,
    # which no statistic counts. 'x' is missing in 10 rows, so that the table
    # keeps its size and its contributors, the rows.
    data = frame(
        y=[i / 2 for i in seq_len(40)],
        x=seq_len(30) + [None] * 10,
        id=rep(range(1, 7), each=2) + [None] * 22 + list(range(7, 13)),
    )
    declaration = units(observation={"key": ["id"]})
    found = audit_both(data, "y ~ x", declaration=declaration)
    internal = finding_of(found["internal"], "keys.duplicates")
    assert [
        written(internal, "rows"),
        written(internal, "duplicate_rows"),
        written(internal, "missing_key_rows"),
    ] == [40, 12, 22]
    shared = finding_of(found["shareable"], "keys.duplicates")
    assert written(shared, "rows") == 40
    assert written(shared, "support_rows") == 40
    assert detail(shared, "duplicate_rows") == "secondary"
    assert detail(shared, "missing_key_rows") == "secondary"
    # In a T1 finding, the suppressed parts are shares that the decision
    # reads, so the finding is suppressed as a whole: 14 and 20 of 40 rows at
    # the bounds leave 6 between them.
    score = [0] * 14 + [10] * 20 + [3, 4, 5, 6, 7, 8]
    data = frame(score=score, pupil=rep(labels("p%02d", range(1, 21)), each=2))
    declaration = units(
        variables={"score": {"role": "outcome", "measurement": "bounded_score", "bounds": [0, 10]}}
    )
    found = audit_both(
        data,
        "score ~ 1 + (1 | pupil)",
        declaration=declaration,
        outcome_access="T1",
        reason="Bounds.",
    )
    internal = finding_of(found["internal"], "outcome.boundary_shares")
    assert [
        written(internal, "at_floor"),
        written(internal, "at_ceiling"),
        written(internal, "rows"),
    ] == [14, 20, 40]
    shared = finding_of(found["shareable"], "outcome.boundary_shares")
    assert shared["status"]["availability"]["detail"] == "decision"


def test_a_product_of_written_counts_is_hidden_only_beside_the_analysis_sample() -> None:
    # 15 subjects, the disclosure unit, meet both items once in one of five
    # sessions, the first of which holds one subject, so that the 5 levels of
    # 'session' are a person count below min_count, while the 10 combinations
    # divided by the 2 written levels of 'item' give them back. At T0 this
    # product is residual risk on design-structure values (privacy.md,
    # Guarantees), so the combinations are written.
    subject = rep(labels("s%02d", range(1, 16)), each=2)
    session = rep(["k1"] + ["k2"] * 3 + ["k3"] * 3 + ["k4"] * 4 + ["k5"] * 4, each=2)
    data = frame(
        y=[i % 4 for i in seq_len(30)],
        subject=subject,
        item=rep(["i1", "i2"], 15),
        session=session,
    )
    declaration = subject_declaration()
    formula = "y ~ 1 + (1 | item) + (1 | session)"
    found = audit_both(data, formula, declaration=declaration)
    pair = {"first": "item", "second": "session"}
    internal = finding_of(found["internal"], "structure.label_incidence", **pair)
    assert [
        written(internal, "combinations"),
        written(internal, "levels_first"),
        written(internal, "levels_second"),
    ] == [10, 2, 5]
    shared = finding_of(found["shareable"], "structure.label_incidence", **pair)
    assert [written(shared, "levels_first"), written(shared, "combinations")] == [2, 10]
    assert detail(shared, "levels_second") == "min_count"
    # At T1, outcome.zero_shares shows the analysis sample, which holds every
    # row, so the design sample loses its levels beside it and rule 5 every
    # count of them, the combinations among them.
    found = audit_both(data, formula, declaration=declaration, **T1_ZEROS)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="item")
    assert written(zeros, "levels") == 2
    shared = finding_of(found["shareable"], "structure.label_incidence", **pair)
    for name in ("levels_first", "levels_second", "combinations"):
        assert detail(shared, name) == "secondary"


def test_a_ratio_or_a_real_with_a_written_denominator_does_not_give_back_its_numerator() -> None:
    # 6 zeros among 40 counts: zero_share times the written rows would give
    # back zeros.
    counts = [0] * 6 + rep_len([1, 2, 3, 4], 34)
    data = frame(count=counts, x=[i * 0.1 for i in range(40)])
    found = audit_both(data, "count ~ x", **T1_ZEROS)
    shared = finding_of(found["shareable"], "outcome.zero_shares")
    assert written(shared, "rows") == 40
    # A part of a person total below k has the detail 'secondary'.
    assert detail(shared, "zeros") == "secondary"
    assert detail(shared, "zero_share") == "ratio"
    # 7 events among 40 rows: events_per_column times the written number of
    # kept columns would give back the minority events.
    data = frame(y=[1.0] * 7 + [0.0] * 33, x=[i / 8 for i in seq_len(40)])
    found = audit_both(data, "y ~ x", family="binomial", outcome_access="T1", reason="Events.")
    kept = written(finding_of(found["shareable"], "design.rank_deficiency"), "kept")
    assert kept == 2
    shared = finding_of(found["shareable"], "outcome.minority_events")
    assert detail(shared, "events") == "secondary"
    assert detail(shared, "non_events") == "secondary"
    assert detail(shared, "events_per_column") == "secondary"


def same_samples() -> dict[str, Any]:
    """A T1 run on 11 subjects of two rows with a binary outcome, none
    missing, so that the design and analysis samples hold the same rows and
    levels."""
    data = frame(
        y=rep_len([0.0, 1.0, 1.0, 0.0], 22),
        x=[i / 2 for i in seq_len(22)],
        subject=rep(labels("s%02d", range(1, 12)), each=2),
    )
    return audit_both(
        data, "y ~ x + (1 | subject)", family="binomial", outcome_access="T1", reason="Events."
    )


def test_counts_derived_from_a_suppressed_count_of_levels_and_the_n_of_quantiles_are_hidden() -> (
    None
):
    found = same_samples()
    internal = finding_of(found["internal"], "identifiability.df_budget", factor="subject")
    assert [written(internal, "levels"), written(internal, "budget")] == [11, 10]
    # The 11 levels of the design sample equal those of the analysis sample,
    # so the design sample loses them, and the budget, a person count of at
    # least min_count, would give them back with the rank of X.
    shared = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert detail(shared, "levels") == "secondary"
    assert detail(shared, "budget") == "secondary"
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(sizes, "levels") is None
    quantiles = {"smallest": 0, "lower_quartile": 0.25, "median": 0.5, "upper_quartile": 0.75}
    for name, p in (quantiles | {"largest": 1}).items():
        assert sizes["statistics"][name]["quantile"] == {"p": p}
    # The analysis sample keeps its levels in the T1 findings.
    minority = finding_of(found["shareable"], "outcome.minority_events", factor="subject")
    assert written(minority, "levels") == 11


def test_quartiles_of_many_levels_are_written_and_minima_and_maxima_never() -> None:
    # 40 levels of 10 to 13 rows: a quartile of 40 values passes the quantile
    # rule, the quantiles 0 and 1 never do.
    sizes = rep([10, 11, 12, 13], 10)
    data = frame(
        y=[i / 7 for i in seq_len(sum(sizes))],
        subject=rep(labels("s%02d", range(1, 41)), sizes),
    )
    found = audit_both(data, "y ~ 1 + (1 | subject)")
    shared = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(shared, "levels") == 40
    assert [
        written(shared, "lower_quartile"),
        written(shared, "median"),
        written(shared, "upper_quartile"),
    ] == [10, 11, 12]
    assert shared["statistics"]["median"]["quantile"] == {"n": 40, "p": 0.5}
    assert detail(shared, "smallest") == "quantile"
    assert detail(shared, "largest") == "quantile"
    assert detail(shared, "singletons") == "secondary"


def test_the_sizes_of_two_samples_do_not_give_back_the_rows_that_a_missing_outcome_removes() -> (
    None
):
    # 3 of 40 rows lack the outcome: the rows of the design sample minus those
    # of the analysis sample would give 3.
    counts = [None] * 3 + rep_len([0, 1, 2, 3, 4, 5], 37)
    data = frame(
        count=counts,
        x=[i / 4 for i in seq_len(40)],
        subject=rep(labels("s%02d", range(1, 21)), each=2),
    )
    found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
    analysis = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    design = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(analysis, "rows") == 37
    assert recover_difference(written(design, "rows"), written(analysis, "rows")) is None
    assert (
        recover_difference(written(design, "support_rows"), written(analysis, "support_rows"))
        is None
    )
    # The levels of 'subject' with two rows in the design sample, 20, minus
    # those in the analysis sample, 17, would give back the 3 subjects
    # concerned.
    between = finding_of(found["shareable"], "structure.within_between", factor="subject", term="x")
    assert written(between, "multi_row_levels") is None


def test_levels_and_levels_with_two_rows_do_not_give_back_the_levels_with_one_row() -> None:
    # 20 subjects, 3 of them with one row and 17 with three. The levels with
    # one row and with two or more are parts of the levels, and both have the
    # detail 'secondary', which does not show which part is below k.
    subject = rep(labels("s%02d", range(1, 18)), each=3) + labels("s%02d", range(18, 21))
    n = len(subject)
    data = frame(y=[i / 3 for i in seq_len(n)], x=[i % 5 for i in seq_len(n)], subject=subject)
    found = audit_both(data, "y ~ x + (1 | subject)")
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    between = finding_of(found["shareable"], "structure.within_between", factor="subject", term="x")
    assert written(sizes, "levels") == 20
    assert detail(sizes, "singletons") == "secondary"
    assert (
        recover_difference(written(sizes, "levels"), written(between, "multi_row_levels")) is None
    )
    assert detail(between, "multi_row_levels") == "secondary"
    # 15 subjects of one row and 5 of six: the 5 levels with two or more rows
    # are below k, and the 15 levels with one row would give them back beside
    # the 20 levels.
    subject = rep(labels("s%02d", range(1, 6)), each=6) + labels("s%02d", range(6, 21))
    n = len(subject)
    data = frame(y=[i / 3 for i in seq_len(n)], x=[i % 5 for i in seq_len(n)], subject=subject)
    found = audit_both(data, "y ~ x + (1 | subject)")
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    between = finding_of(found["shareable"], "structure.within_between", factor="subject", term="x")
    assert written(sizes, "levels") == 20
    assert detail(sizes, "singletons") == "secondary"
    assert detail(between, "multi_row_levels") == "secondary"


def test_two_parts_of_a_written_total_do_not_show_which_is_below_k() -> None:
    # 20 subjects of three trials, the first 9 keys repeated identically and
    # the next 9 with another x: 18 duplicated keys, 9 identical and 9
    # conflicting. Details that showed both below k would bound each by
    # 18 - 9 from below and give back 9 and 9.
    subject = rep(labels("s%02d", range(1, 21)), each=3)
    trial = rep([1, 2, 3], 20)
    x = [i % 7 + 0.5 for i in seq_len(60)]
    rows = list(range(60)) + list(range(9)) + list(range(9, 18))
    data = frame(
        subject=[subject[i] for i in rows],
        trial=[trial[i] for i in rows],
        x=[x[i] + (1 if j >= 69 else 0) for j, i in enumerate(rows)],
        y=[i % 11 + 0.5 for i in seq_len(78)],
    )
    declaration = subject_declaration(observation={"key": ["subject", "trial"]})
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration)
    shared = finding_of(found["shareable"], "keys.duplicates")
    assert written(shared, "duplicated_keys") == 18
    assert [detail(shared, "identical_keys"), detail(shared, "conflicting_keys")] == [
        "secondary",
        "secondary",
    ]


def test_a_count_below_k_that_no_rule_across_findings_suppresses_keeps_min_count() -> None:
    # 20 subjects of two rows, 4 of them with the assigned column z: the 4
    # units of the assignment's rows keep the detail 'min_count', which beside
    # the 20 written levels of the design sample shows that these exceed them
    # by k or more. The difference counts subjects without the assigned
    # column, a design-structure value that rule 1 compares with no losing
    # quantity below k (privacy.md, Guarantees).
    subject = rep(labels("s%02d", range(1, 21)), each=2)
    z = [
        ["a", "b"][(i // 2) % 2] if subject[i - 1] <= "s04" else None for i in seq_len(len(subject))
    ]
    data = frame(y=[i / 3 for i in seq_len(40)], subject=subject, z=z)
    declaration = subject_declaration(assignment=[assignment("z", "subject")])
    found = audit_both(data, "y ~ 1 + (1 | subject)", declaration=declaration)
    shared = finding_of(found["shareable"], "assignment.constant_within_unit", column="z")
    assert detail(shared, "units") == "min_count"
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(sizes, "levels") == 20


def test_a_count_that_measures_no_quantity_is_written_whatever_a_suppressed_quantity_holds() -> (
    None
):
    # 20 subjects, 2 of one row and 18 of three, with x constant within each:
    # the budget of 20 - 2 = 18 equals the 18 levels with two or more rows,
    # which rule 2 suppresses, and is written, since writing it shows nothing
    # that the levels and the consuming terms do not.
    sizes = [1, 1] + [3] * 18
    subject = rep(labels("s%02d", seq_len(len(sizes))), sizes)
    data = frame(
        y=[(i * 5) % 13 + 0.25 for i in seq_len(len(subject))],
        x=rep([i % 3 + 0.5 for i in seq_len(len(sizes))], sizes),
        subject=subject,
    )
    found = audit_both(data, "y ~ x + (1 | subject)")
    budget = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert [written(budget, "levels"), written(budget, "budget")] == [20, 18]
    between = finding_of(found["shareable"], "structure.within_between", factor="subject", term="x")
    assert detail(between, "multi_row_levels") == "secondary"


def test_the_rows_and_levels_of_the_analysis_sample_do_not_show_that_a_level_has_one_row() -> None:
    # 12 subjects in the analysis sample, 9 of two rows and 3 of one, and 10
    # subjects of four rows without an outcome: 21 analysed rows are fewer
    # than twice the 12 levels, so at least 3 subjects have one analysed row
    # and the smallest analysed size is 1, an outcome-derived value.
    subject = (
        rep(labels("s%02d", range(1, 10)), each=2)
        + labels("t%02d", range(1, 4))
        + rep(labels("u%02d", range(1, 11)), each=4)
    )
    n = len(subject)
    data = frame(
        count=[i % 4 for i in seq_len(21)] + [None] * 40,
        x=[i % 7 + 0.5 for i in seq_len(n)],
        subject=subject,
    )
    # With the basis grouping_factors and with the basis disclosure_unit, the
    # contributors measure the levels of subject and are suppressed with them.
    for declared in (None, subject_declaration()):
        found = audit_both(data, "count ~ x + (1 | subject)", declaration=declared, **T1_ZEROS)
        shares = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
        assert written(shares, "rows") == 21
        assert detail(shares, "levels") == "secondary"
        assert support_detail(shares, "distinct") == "secondary"
    # In the design sample the same bound concerns design-structure values,
    # which the filter leaves as residual risk (privacy.md, Guarantees): the
    # 21 rows of a T0 run are written beside its 12 levels.
    found = audit_both(data.iloc[:21].reset_index(drop=True), "count ~ x + (1 | subject)")
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert [written(sizes, "rows"), written(sizes, "levels")] == [21, 12]


def test_the_rows_and_levels_of_the_design_sample_do_not_bound_what_it_loses() -> None:
    # 20 subjects of two rows, 10 of them with a constant outcome, 10
    # subjects of one row with an outcome and 10 of one row without one. The
    # 20 levels with two rows of the analysis sample, which
    # outcome.constant_clusters writes, equal the design sample's, which
    # beside its 60 rows and 40 levels would show that no subject lost its
    # second outcome, so rule 5 hides every count of the levels of subject in
    # the design sample.
    y = [3, 3] * 10 + [1, 2] * 10 + [i / 7 for i in range(1, 11)] + [None] * 10
    data = frame(
        y=y,
        x=[i % 7 + 0.5 for i in seq_len(len(y))],
        subject=rep(labels("s%02d", range(1, 21)), each=2) + labels("t%02d", range(1, 21)),
    )
    found = audit_both(data, "y ~ x + (1 | subject)", outcome_access="T1", reason="Sizes.")
    constant = finding_of(found["shareable"], "outcome.constant_clusters", factor="subject")
    assert written(constant, "multi_row_levels") == 20
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(sizes, "rows") == 60
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "singletons") == "secondary"


def test_the_rows_of_a_pair_of_columns_are_a_sample_of_their_own() -> None:
    # 14 classes of two rows, declared within schools, of which 2 have no
    # school: structure.label_incidence counts the 12 classes with a school,
    # and the 14 classes of the design sample minus them would give 2.
    data = frame(
        y=[i / 3 for i in seq_len(28)],
        **{"class": rep(labels("c%02d", range(1, 15)), each=2)},
        school=rep(["S1", "S2", "S3", "S4", "S5", "S6", None], each=4),
    )
    declaration = units(
        unit("school", "cluster"),
        unit("class", "cluster", nested_in="school", id_scope="global"),
    )
    found = audit_both(data, "y ~ 1 + (1 | class)", declaration=declaration)
    pair = {"first": "class", "second": "school"}
    internal = finding_of(found["internal"], "structure.label_incidence", **pair)
    assert written(internal, "levels_first") == 12
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="class")
    shared = finding_of(found["shareable"], "structure.label_incidence", **pair)
    assert written(sizes, "levels") == 14
    assert recover_difference(written(sizes, "levels"), written(shared, "levels_first")) is None
    assert detail(shared, "levels_first") == "secondary"


def test_nested_samples_other_than_the_design_sample_are_compared_with_each_other() -> None:
    # 60 subjects of three rows, two of them assigned. z1 is missing for
    # subjects 1 to 20 and z2 for subjects 1 to 15, so the units of z2, 45,
    # minus those of z1, 40, would give back 5 subjects.
    subject = rep(labels("s%02d", range(1, 61)), each=3)
    n = len(subject)

    def assigned(values: list[str], missing: str) -> list[str | None]:
        return [None if s <= missing else v for s, v in zip(subject, values, strict=True)]

    z1 = assigned(rep(rep(["a", "b"], 30), each=3), "s20")
    z2 = assigned(rep(rep(["c", "c", "d", "d"], 15), each=3), "s15")
    y: list[Any] = [i % 7 for i in seq_len(n)]
    x = [i % 5 for i in seq_len(n)]
    data = frame(y=y, x=x, subject=subject, z1=z1, z2=z2)
    declaration = subject_declaration(
        assignment=[assignment("z1", "subject"), assignment("z2", "subject")]
    )
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration)
    first = finding_of(found["shareable"], "assignment.design_df", column="z1")
    second = finding_of(found["shareable"], "assignment.design_df", column="z2")
    assert written(first, "units") == 40
    assert detail(second, "units") == "secondary"
    # The analysis sample within the rows of an assignment: the outcome is
    # missing for subjects 1 to 20, so the 45 units of z2 minus the 40 levels
    # of the analysis sample would give back 5 randomised subjects without an
    # outcome.
    declaration["assignment"] = declaration["assignment"][1:]
    lost = [None if s <= "s20" else v for s, v in zip(subject, y, strict=True)]
    data = frame(y=lost, x=x, subject=subject, z1=z1, z2=z2)
    arguments = {"family": "poisson", "outcome_access": "T1", "reason": "Loss."}
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration, **arguments)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assigned_finding = finding_of(found["shareable"], "assignment.design_df", column="z2")
    assert written(zeros, "levels") == 40
    assert detail(assigned_finding, "units") == "secondary"
    # Rows of an assignment equal to the analysis sample count as the
    # analysis sample, against which the design sample loses its value: z2
    # and the outcome are missing for subjects 1 to 5.
    lost = [None if s <= "s05" else v for s, v in zip(subject, y, strict=True)]
    z2 = assigned(rep(rep(["c", "c", "d", "d"], 15), each=3), "s05")
    data = frame(y=lost, x=x, subject=subject, z1=z1, z2=z2)
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration, **arguments)
    assigned_finding = finding_of(found["shareable"], "assignment.design_df", column="z2")
    budget = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert written(assigned_finding, "units") == 55
    assert detail(budget, "levels") == "secondary"


def test_the_contributors_of_the_basis_grouping_factors_measure_the_levels_of_a_factor() -> None:
    # Without a disclosure unit, the contributors are the levels of the
    # factor with the fewest levels: 'g', with 20 levels in the design sample,
    # where 'h' has 40. 'g' keeps 15 levels in the analysis sample, so its 20
    # levels in the design sample, which the contributors would give back,
    # are suppressed. The 10 analysed levels of 'h', three of one row among 17
    # rows, are hidden by rule 3, and with them its 40 levels in the design
    # sample.
    n = 80
    kept = set(range(1, 16)) | {21, 23}
    counts = rep([0, 1, 3, 2], 20)
    data = frame(
        count=[c if i in kept else None for i, c in enumerate(counts, start=1)],
        x=[i % 9 for i in seq_len(n)],
        g=labels("g%02d", [(i - 1) % 20 + 1 for i in seq_len(n)]),
        h=labels("h%02d", [(i + 1) // 2 for i in seq_len(n)]),
    )
    found = audit_both(data, "count ~ x + (1 | g) + (1 | h)", **T1_ZEROS)
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="g")
    other = finding_of(found["shareable"], "structure.cluster_sizes", factor="h")
    assert detail(sizes, "levels") == "secondary"
    assert detail(other, "levels") == "secondary"
    assert support_detail(sizes, "distinct") == "secondary"


def test_crossed_columns_do_not_give_back_the_combinations_that_lack_an_outcome() -> None:
    # 12 levels of g crossed with 12 of h, two pupils in each combination but
    # one, so that g and h count non-persons and their combinations persons.
    # The outcome is missing in the 10 rows of 5 combinations. The design
    # sample's levels of g and h, compared beside the analysis sample
    # whatever their class, lose their value, and its combinations, the
    # product of the two, too. The analysis sample's levels of g and h, which
    # outcome.zero_shares writes, bound the design sample's from below, and
    # the firing of rule 1 bounds their product from above, so the analysis
    # sample loses its count of combinations too: 12 x 12 is the only
    # product within k of its 139.
    cells = [(g, h) for h in labels("h%02d", range(1, 13)) for g in labels("g%02d", range(1, 13))]
    lost = {cells[i - 1] for i in (10, 30, 50, 70, 90)}

    def crossed(rows: list[int]) -> dict[str, Any]:
        chosen = [cells[i] for i in rows]
        m = len(chosen)
        data = frame(
            g=[cell[0] for cell in chosen],
            h=[cell[1] for cell in chosen],
            pupil=labels("p%03d", seq_len(m)),
            count=[None if cell in lost else i % 4 for i, cell in enumerate(chosen, start=1)],
            x=[i % 7 for i in seq_len(m)],
        )
        declaration = units(unit("pupil", "participant"))
        formula = "count ~ x + (1 | g) + (1 | h) + (1 | g:h)"
        return audit_both(data, formula, declaration=declaration, **T1_ZEROS)["shareable"]  # type: ignore[no-any-return]

    # With every combination of two rows, the 278 analysed rows are twice the
    # 139 analysed combinations, so rule 3 leaves them, and the clause on
    # crossed columns alone hides them.
    pairs = rep(range(len(cells)), each=2)
    for rows in (pairs[1:], pairs):
        shareable = crossed(rows)
        incidence = finding_of(shareable, "structure.label_incidence", first="g", second="h")
        assert written(incidence, "relation") == "crossed"
        for name in ("levels_first", "levels_second", "combinations"):
            assert detail(incidence, name) == "secondary"
        assert written(finding_of(shareable, "outcome.zero_shares", factor="g"), "levels") == 12
        combined = finding_of(shareable, "outcome.zero_shares", factor="g:h")
        assert detail(combined, "levels") == "secondary"


def test_the_labels_that_repeat_do_not_give_back_the_labels_that_occur_once() -> None:
    # 25 class labels, 20 of which occur in two of 12 schools. The labels in
    # several schools, 20, written beside the 25 labels of 'class', would give
    # back the 5 that occur in one school, which part_of suppresses in both
    # checks that count them.
    combinations = (
        [(f"c{i + 1:02d}", f"S{i % 12 + 1:02d}") for i in range(20)]
        + [(f"c{i + 1:02d}", f"S{(i + 5) % 12 + 1:02d}") for i in range(20)]
        + [(f"c{i:02d}", f"S{i - 20:02d}") for i in range(21, 26)]
    )
    rows = rep(combinations, each=2)
    n = len(rows)
    data = frame(
        **{"class": [row[0] for row in rows]},
        school=[row[1] for row in rows],
        # The first row of each combination, counted from 1, modulo 3.
        tx=[(2 * (i // 2) + 1) % 3 for i in range(n)],
        stype=[int(row[1][1:3]) % 2 for row in rows],
        y=[i % 7 for i in seq_len(n)],
        x=[i % 5 for i in seq_len(n)],
    )
    found = audit_both(data, "y ~ x + tx + stype + (1 | school) + (1 | class)")
    pair = {"first": "class", "second": "school"}
    evidence = finding_of(found["shareable"], "structure.id_scope_evidence", **pair)
    incidence = finding_of(found["shareable"], "structure.label_incidence", **pair)
    assert written(evidence, "levels") == 25
    assert written(incidence, "levels_first") == 25
    assert detail(incidence, "first_in_several") == "secondary"
    assert detail(evidence, "shared_labels") == "secondary"


def test_counts_that_equal_a_suppressed_quantity_are_suppressed() -> None:
    # 15 subjects of two rows, the second outcome of two missing: the 15
    # levels of the design sample exceed the 15 of the analysis sample by 0,
    # and cells of identifiability.residual_confounding counts the same
    # levels. outcome.zero_shares of the Poisson outcome shows the analysis
    # sample.
    y: list[Any] = [i % 4 for i in seq_len(30)]
    y[1] = None
    y[3] = None
    data = frame(
        y=y, x=[i % 4 for i in seq_len(30)], subject=rep(labels("s%02d", range(1, 16)), each=2)
    )
    found = audit_both(
        data, "y ~ x + (1 | subject)", family="poisson", outcome_access="T1", reason="Sizes."
    )
    scope = {"factor": "subject", "term": "1 | subject"}
    internal = finding_of(found["internal"], "identifiability.residual_confounding", **scope)
    assert written(internal, "cells") == 15
    shared = finding_of(found["shareable"], "identifiability.residual_confounding", **scope)
    assert detail(shared, "cells") == "secondary"
    assert detail(shared, "replicated_cells") == "secondary"


def test_a_count_that_resolves_as_non_person_is_not_suppressed_for_an_equal_value() -> None:
    # Ten pupils, the disclosure unit, in five schools of two, one pupil with
    # two rows and the outcome constant within school S1. The analysis sample
    # has 1 level of 'pupil' with two rows, which rule 2 suppresses, and the 1
    # constant school is a non-person count, which stays written with its
    # share, as its message shows.
    data = frame(
        y=[5.0, 5, 5, 1, 2, 3, 4, 6, 7, 8, 9],
        school=["S1", "S1", "S1", "S2", "S2", "S3", "S3", "S4", "S4", "S5", "S5"],
        pupil=["p01", "p01"] + labels("p%02d", range(2, 11)),
    )
    found = audit_both(
        data,
        "y ~ 1 + (1 | school) + (1 | pupil)",
        declaration=school_pupil(),
        outcome_access="T1",
        reason="Constant levels.",
    )
    shared = finding_of(found["shareable"], "outcome.constant_clusters", factor="school")
    assert shared["statistics"]["constant_levels"] == {
        "count_class": "non_person",
        "kind": "count",
        "value": 1,
    }
    assert written(shared, "multi_row_levels") == 5
    assert "within 1 of the 5 levels" in shared["message"]["text"]


def test_nested_parts_of_totals_are_suppressed_whatever_the_order_of_the_rules() -> None:
    # 12 levels of 3 rows, a varying in 11 and taking all three of its levels
    # in 10: multi_row_levels 12, varying_levels 11 and informative_levels 10.
    a = rep(["a1", "a2", "a3"], 10) + ["a1", "a1", "a2", "a1", "a1", "a1"]
    data = frame(
        y=[i / 3 for i in seq_len(len(a))], a=a, g=rep(labels("g%02d", range(1, 13)), each=3)
    )
    found = audit_both(data, "y ~ a + (1 | g)")
    scope = {"factor": "g", "term": "a"}
    internal = finding_of(found["internal"], "structure.within_between", **scope)
    assert [
        written(internal, "multi_row_levels"),
        written(internal, "varying_levels"),
        written(internal, "informative_levels"),
    ] == [12, 11, 10]
    shared = finding_of(found["shareable"], "structure.within_between", **scope)
    assert detail(shared, "varying_levels") == "secondary"
    assert detail(shared, "informative_levels") == "secondary"


def test_an_absent_ratio_whose_denominator_is_suppressed_is_written_as_suppressed() -> None:
    # Three subjects crossed with four items, with no candidate attribute, so
    # that changing_share is absent: its absence would show nothing more than
    # the suppressed shared_labels.
    data = frame(
        y=[i + 0.5 for i in seq_len(12)],
        subject=rep(["s1", "s2", "s3"], each=4),
        item=rep(["i1", "i2", "i3", "i4"], 3),
    )
    found = audit_both(data, "y ~ 1 + (1 | subject) + (1 | item)")
    pair = {"first": "item", "second": "subject"}
    internal = finding_of(found["internal"], "structure.id_scope_evidence", **pair)
    assert "changing_share" not in internal["statistics"]
    shared = finding_of(found["shareable"], "structure.id_scope_evidence", **pair)
    assert shared["statistics"]["changing_share"]["count_class"] == "person"
    assert detail(shared, "changing_share") == "ratio"
    assert "changing_labels" not in shared["statistics"]


def test_the_dominance_rule_is_written_as_a_boolean_without_the_share() -> None:
    # 12 subjects, two of which hold 100 of the 110 rows.
    sizes = [50, 50] + [1] * 10
    data = frame(y=[i / 9 for i in seq_len(110)], subject=rep(labels("s%02d", range(1, 13)), sizes))
    found = audit_both(data, "y ~ 1 + (1 | subject)")
    shared = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    contributors = shared["support"]["contributors"]
    assert sorted(contributors) == ["basis", "distinct", "dominated"]
    assert contributors["dominated"] is True
    assert contributors["distinct"]["value"] == 12
    assert detail(shared, "levels") == "dominance"
    assert detail(shared, "effective_size") == "dominance"


def test_a_t1_finding_that_rests_on_a_suppressed_outcome_count_is_suppressed_as_a_whole() -> None:
    found = same_samples()
    shared = finding_of(found["shareable"], "outcome.constant_clusters", factor="subject")
    assert shared["status"] == {
        "availability": {
            "detail": "decision",
            "reason": "privacy_suppressed",
            "value": "not_available",
        }
    }
    assert "message" not in shared
    assert "statistics" not in shared
    assert "support" not in shared


def separation(data: pd.DataFrame, formula: str, **arguments: Any) -> dict[str, Any]:
    """The findings of outcome.separation of a T2 run in both modes."""
    found = audit_both(
        data,
        formula,
        outcome_access="T2",
        reason="Separation.",
        exploratory=True,
        **({"family": "binomial"} | arguments),
    )
    return {mode: finding_of(found[mode], "outcome.separation") for mode in found}


def test_the_values_of_outcome_separation_that_locate_a_cell_are_never_written() -> None:
    # Complete separation by 'x' with 'z', three kept columns whose values no
    # two rows share.
    y: list[Any] = [0.0] * 12 + [1.0] * 12
    data = frame(y=y, x=seq_len(24), z=rep([-3, 3, -1, 1], 6))
    found = separation(data, "y ~ x + z")
    assert written(found["internal"], "verdict") == "complete"
    assert written(found["shareable"], "verdict") == "complete"
    for name in ("bounds", "columns_involved", "margin", "optimum"):
        assert detail(found["shareable"], name) == "internal_only"
    # With two kept columns, the verdict would name a cell of one predictor.
    shared = separation(data, "y ~ x")["shareable"]
    assert shared["status"]["availability"]["detail"] == "decision"
    # With two factors of two levels, complete shows that each combination
    # holds one class, so the finding is suppressed whatever its verdict.
    data = frame(y=y, x=rep([-2, 2], each=12), z=rep([-3, 3, -1, 1], 6))
    found = separation(data, "y ~ x + z")
    assert written(found["internal"], "verdict") == "complete"
    assert found["shareable"]["status"]["availability"]["detail"] == "decision"
    # A column that varies only in rows without an outcome leaves the
    # analysis sample two kept columns, on which the verdict would name a cell
    # of 'x'.
    data = frame(y=y + [None, None], x=seq_len(24) + [7.5, 18.5], z=[0] * 24 + [1, 1])
    found = separation(data, "y ~ x + z")
    assert written(found["internal"], "verdict") == "complete"
    assert found["shareable"]["status"]["availability"]["detail"] == "decision"


def test_two_rows_share_the_values_of_the_kept_columns_of_outcome_separation() -> None:
    def matrix(*columns: Any) -> Any:
        return np.column_stack([np.broadcast_to(np.asarray(c, dtype=float), (3,)) for c in columns])

    assert not separation_shared_values(matrix(1, [1, 2, 3]))
    assert separation_shared_values(matrix(1, [1, 2, 1]))
    # -0 and 0 are the same value.
    assert separation_shared_values(matrix(1, [0, 2, -0.0], [5, 6, 5]))
    assert not separation_shared_values(matrix(1, [0, 2, 0], [5, 6, 4]))
    assert not separation_shared_values(np.array([[1.0, 3.0]]))


def test_the_software_of_a_document_does_not_show_that_an_outcome_class_is_empty() -> None:
    # With 0 or 3 events in 200 rows, the finding of outcome.separation is
    # suppressed as a whole, and the solver is named in both documents.
    documents = []
    for events in (0, 3):
        data = frame(
            y=[1.0] * events + [0.0] * (200 - events),
            x=[i % 7 for i in seq_len(200)],
            g=rep(labels("g%02d", range(1, 21)), each=10),
        )
        found = audit_both(
            data,
            "y ~ x + (1 | g)",
            family="binomial",
            outcome_access="T2",
            reason="Separation.",
            exploratory=True,
        )
        documents.append(found["shareable"])
    for document in documents:
        finding = finding_of(document, "outcome.separation")
        assert finding["status"]["availability"]["detail"] == "decision"
    assert documents[0]["software"] == documents[1]["software"]
    assert list(documents[0]["software"]["packages"]) == ["scipy"]


def test_binomial_events_and_non_events_beside_the_rows_do_not_give_back_small_classes_of_rows() -> (  # noqa: E501
    None
):
    # The rows with k = 0, with k = n and with both classes are the rows minus
    # events, the rows minus non_events and their overlap.
    declaration = units(
        variables={"k": {"role": "outcome", "measurement": "binomial", "trials": "n"}}
    )

    def run(k: list[int]) -> dict[str, Any]:
        rng = np.random.default_rng(3)
        data = frame(
            k=k,
            n=[5] * 40,
            x=np.round(rng.normal(size=40), 3).tolist(),
            z=np.round(rng.normal(size=40), 3).tolist(),
        )
        return separation(data, "k ~ x + z", declaration=declaration, family=None)

    for k in (
        [0] * 3 + [5] * 12 + [2] * 25,
        [0] * 12 + [5] * 3 + [2] * 25,
        [0] * 15 + [5] * 25,
    ):
        found = run(k)
        assert [written(found["internal"], "events"), written(found["internal"], "non_events")] == [
            sum(v > 0 for v in k),
            sum(v < 5 for v in k),
        ]
        assert found["shareable"]["status"]["availability"]["detail"] == "decision"
    found = run([0] * 12 + [5] * 12 + [2] * 16)
    assert found["shareable"]["status"]["availability"]["value"] == "available"
    assert written(found["shareable"], "verdict") == written(found["internal"], "verdict")
    assert [written(found["shareable"], "events"), written(found["shareable"], "non_events")] == [
        28,
        28,
    ]


def test_outcome_separation_does_not_show_that_missing_outcomes_emptied_a_cell() -> None:
    # The outcome is missing in the 3 rows with smoker 's2', which leaves 3
    # kept columns in the analysis sample against 4 in the design sample, or
    # in 3 rows with smoker 's1', which leaves 4 in both. The seed gives three
    # rows with smoker 's2' that do not share their outcome, so that neither
    # analysis sample is separated.
    rng = np.random.default_rng(1)
    y = rng.binomial(1, 0.5, size=40).astype(float).tolist()
    x1 = np.round(rng.normal(size=40), 3).tolist()
    x2 = np.round(rng.normal(size=40), 3).tolist()
    smoker = ["s2"] * 3 + ["s1"] * 37
    shared = []
    for missing in ([1, 2, 3], [4, 25, 30]):
        lost = [None if i in missing else v for i, v in enumerate(y, start=1)]
        data = frame(y=lost, x1=x1, x2=x2, smoker=smoker)
        found = audit_both(
            data,
            "y ~ x1 + x2 + smoker",
            family="binomial",
            outcome_access="T2",
            reason="Separation.",
            exploratory=True,
        )
        rank = finding_of(found["shareable"], "design.rank_deficiency")
        assert written(rank, "kept") == 4
        internal = finding_of(found["internal"], "outcome.separation")
        assert written(internal, "columns") == (3 if missing[0] == 1 else 4)
        shared.append(finding_of(found["shareable"], "outcome.separation"))
    for finding in shared:
        assert detail(finding, "columns") == "internal_only"
        assert finding["status"]["availability"]["value"] == "available"
    assert shared[0]["status"] == shared[1]["status"]


def test_outcome_separation_with_the_levels_of_one_factor_is_suppressed_whatever_its_verdict() -> (
    None
):
    # Three arms of 40 rows, with events exactly in arm 'b': complete would
    # show that each arm holds one class, and events which.
    arm = rep(["a", "b", "c"], each=40)
    g = rep(labels("g%02d", range(1, 21)), 6)
    data = frame(arm=arm, g=g, y=[float(a == "b") for a in arm])
    arguments = {
        "family": "binomial",
        "outcome_access": "T2",
        "reason": "Separation.",
        "exploratory": True,
    }
    found = audit_both(data, "y ~ arm + (1 | g)", **arguments)
    assert written(finding_of(found["shareable"], "design.rank_deficiency"), "kept") == 3
    assert written(finding_of(found["internal"], "outcome.separation"), "verdict") == "complete"
    shared = finding_of(found["shareable"], "outcome.separation")
    assert shared["status"]["availability"]["detail"] == "decision"
    # Without separation, the finding is suppressed alike.
    data = frame(arm=arm, g=g, y=rep([0.0, 1.0], 60))
    found = audit_both(data, "y ~ arm + (1 | g)", **arguments)
    assert written(finding_of(found["internal"], "outcome.separation"), "verdict") == "none"
    shared = finding_of(found["shareable"], "outcome.separation")
    assert shared["status"]["availability"]["detail"] == "decision"


def test_the_smallest_eigenvalue_does_not_give_back_the_rows_without_an_outcome() -> None:
    # 20 subjects of 4 rows with a condition balanced within subjects: the
    # eigenvalue is 1 - sqrt((J - 1) / (N - 2)), which gives back N. At T0
    # this is residual risk on the rows of the design sample, so it is
    # written. At T1, outcome.zero_shares writes the 80 rows of the analysis
    # sample, beside which rule 1 hides the design sample's and rule 5 the
    # eigenvalue, which would show that no outcome is missing.
    data = frame(
        y=[i % 9 for i in seq_len(80)],
        condition=rep(["a", "b"], 40),
        subject=rep(labels("s%02d", range(1, 21)), each=4),
    )
    found = audit_both(data, "y ~ condition + (1 | subject)")
    expected = 1 - (19 / 78) ** 0.5
    internal = finding_of(found["internal"], "identifiability.gram_rank")
    assert written(internal, "smallest_eigenvalue") == pytest.approx(expected, rel=1e-12)
    shared = finding_of(found["shareable"], "identifiability.gram_rank")
    assert written(shared, "smallest_eigenvalue") == pytest.approx(expected, rel=1e-12)
    found = audit_both(data, "y ~ condition + (1 | subject)", **T1_ZEROS)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert written(zeros, "rows") == 80
    shared = finding_of(found["shareable"], "identifiability.gram_rank")
    assert detail(shared, "smallest_eigenvalue") == "secondary"


def test_a_quartile_that_is_the_minimum_is_suppressed_by_the_quantile_rule_whatever_its_value() -> (
    None
):
    # Three schools of pupils, the disclosure unit: the lower quartile of 3
    # sizes is the smallest, and its detail must not show whether it is
    # below min_count.
    details = []
    for sizes in ([6, 40, 54], [12, 40, 48]):
        school = rep(["A", "B", "C"], sizes)
        n = len(school)
        data = frame(
            y=[i % 5 for i in seq_len(n)], school=school, pupil=labels("p%03d", seq_len(n))
        )
        found = audit_both(data, "y ~ 1 + (1 | school)", declaration=school_pupil())
        finding = finding_of(found["shareable"], "structure.cluster_sizes", factor="school")
        details += [
            detail(finding, name) for name in ("lower_quartile", "median", "upper_quartile")
        ]
    assert details == ["quantile"] * 6


def test_levels_that_an_assignment_removes_from_a_person_sample_are_compared() -> None:
    # 29 schools of 4 pupils and S30 of 1 pupil, whose rows alone lack 'arm':
    # the schools are person counts in the design sample and not in the rows
    # of the assignment, and 30 levels minus 29 units would count S30.
    school = rep(labels("S%02d", range(1, 30)), each=8) + ["S30"] * 2
    pupil = rep(labels("P%03d", range(1, 117)), each=2) + ["P117"] * 2
    n = len(school)
    arm = [
        None if s == "S30" else ("a" if i % 16 < 8 else "b") for i, s in enumerate(school, start=1)
    ]
    data = frame(y=[i % 7 for i in seq_len(n)], school=school, pupil=pupil, arm=arm)
    declaration = school_pupil()
    declaration["assignment"] = [assignment("arm", "school")]
    found = audit_both(data, "y ~ 1 + (1 | school)", declaration=declaration)
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="school")
    assigned = finding_of(found["shareable"], "assignment.constant_within_unit", column="arm")
    assert written(sizes, "levels") == 30
    internal = finding_of(found["internal"], "assignment.constant_within_unit", column="arm")
    assert internal["statistics"]["units"]["count_class"] == "non_person"
    assert recover_difference(written(sizes, "levels"), written(assigned, "units")) is None
    assert detail(assigned, "units") == "secondary"


def test_rows_without_a_key_value_do_not_give_back_the_rows_that_a_predictor_removes() -> None:
    # 30 subjects of 10 trials, with 'subject' missing in rows 1 to 15 and
    # 'x' in rows 100 and 200: 17 rows leave the design sample, 15 of them
    # without a key value.
    subject: list[Any] = rep(labels("s%02d", range(1, 31)), each=10)
    subject[:15] = [None] * 15
    x: list[Any] = [i % 13 for i in seq_len(300)]
    x[99] = None
    x[199] = None
    y = [i % 11 for i in seq_len(300)]
    trial = rep(range(1, 11), 30)
    declaration = subject_declaration(observation={"key": ["subject", "trial"]})
    data = frame(y=y, x=x, subject=subject, trial=trial)
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration)
    assert written(finding_of(found["internal"], "keys.duplicates"), "missing_key_rows") == 15
    keys = finding_of(found["shareable"], "keys.duplicates")
    dropped = finding_of(found["shareable"], "sample.raw_vs_analysis")
    assert written(dropped, "rows_dropped") == 17
    assert (
        recover_difference(written(dropped, "rows_dropped"), written(keys, "missing_key_rows"))
        is None
    )
    assert detail(keys, "missing_key_rows") == "secondary"
    # With 12 rows that only 'x' removes, the count stays.
    x[99] = 1
    x[199] = 1
    for i in range(20, 241, 20):
        x[i - 1] = None
    data = frame(y=y, x=x, subject=subject, trial=trial)
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration)
    assert written(finding_of(found["shareable"], "keys.duplicates"), "missing_key_rows") == 15


# --- The analysis sample, shown or not, and the samples beside it -----------------------


def strict_values(document: dict[str, Any]) -> list[Any]:
    """The values of a shareable document that a reader may not use against
    an outcome-derived value, with the T0 statuses, messages, categories,
    booleans and names that privacy.md (Guarantees) accepts to show left out:
    for each finding, its availability, its counts, ratios and reals with
    their details and its support, and the whole of a finding of a T1 or T2
    check."""
    values: list[Any] = []
    for finding in document["findings"]:
        if finding["tier"] != "T0":
            values.append(finding)
            continue
        values.append(
            {
                "check": finding["check"],
                "scope": finding["scope"],
                "availability": finding["status"]["availability"],
                "statistics": {
                    name: [
                        statistic.get("value"),
                        statistic.get("availability", {}).get("detail"),
                    ]
                    for name, statistic in finding.get("statistics", {}).items()
                    if statistic["kind"] in ("count", "ratio", "real", "reals")
                },
                "support": finding.get("support"),
            }
        )
    return values


def expect_same_reading(first: dict[str, Any], second: dict[str, Any]) -> None:
    """Two shareable documents of tables that differ only in a hidden
    outcome-derived value must read alike."""
    assert canonical_bytes(strict_values(first)) == canonical_bytes(strict_values(second))


def test_a_gaussian_t1_run_that_shows_no_value_of_the_analysis_sample_writes_the_t0_values() -> (
    None
):
    # 10 subjects of one row and 30 of two, the trial of subjects s01 to s10
    # missing and both outcomes of s01 to s06 missing. Without a constant
    # subject, outcome.constant_clusters rests on a suppressed count and is
    # suppressed as a whole, so the document shows no value of the analysis
    # sample and writes the reals and counts of the design sample as a T0
    # document does. missing_key_rows, 20, is written: the 12 rows that the
    # analysis sample leaves out, 8 fewer, are not compared with it.
    subject = rep(labels("s%02d", range(1, 31)), each=2) + labels("t%02d", range(1, 11))
    n = len(subject)
    trial: list[Any] = rep([1, 2], 30) + [1] * 10
    trial = [None if s <= "s10" else t for s, t in zip(subject, trial, strict=True)]
    offsets = rep([0, 0.5], 35)
    y: list[Any] = [i / 3 + offsets[i - 1] for i in seq_len(n)]
    y = [None if s <= "s06" else v for s, v in zip(subject, y, strict=True)]
    x = [i % 4 + 0.5 for i in seq_len(n)]
    declaration = units(observation={"key": ["subject", "trial"]})

    def run(y: list[Any]) -> dict[str, Any]:
        data = frame(y=y, x=x, subject=subject, trial=trial)
        found = audit_both(
            data,
            "y ~ x + (1 | subject)",
            declaration=declaration,
            outcome_access="T1",
            reason="Constant levels.",
        )
        return found["shareable"]  # type: ignore[no-any-return]

    shareable = run(y)
    constant = finding_of(shareable, "outcome.constant_clusters", factor="subject")
    assert constant["status"]["availability"]["detail"] == "decision"
    sizes = finding_of(shareable, "structure.cluster_sizes", factor="subject")
    assert [written(sizes, "rows"), written(sizes, "levels")] == [70, 40]
    assert written(sizes, "effective_size") is not None
    within = finding_of(shareable, "structure.within_between", factor="subject", term="x")
    assert written(within, "within_share") is not None
    gram = finding_of(shareable, "identifiability.gram_rank")
    assert written(gram, "smallest_eigenvalue") is not None
    assert written(finding_of(shareable, "keys.duplicates"), "missing_key_rows") == 20
    # With 10 constant subjects outcome.constant_clusters is written, the
    # analysis sample is shown and its 34 levels beside the design sample's
    # 40 hide these, the reals that read them and missing_key_rows.
    constant_values = {s: float(j) for j, s in enumerate(labels("s%02d", range(11, 21)), 11)}
    y = [constant_values.get(s, v) for s, v in zip(subject, y, strict=True)]
    shareable = run(y)
    constant = finding_of(shareable, "outcome.constant_clusters", factor="subject")
    assert written(constant, "constant_levels") == 10
    sizes = finding_of(shareable, "structure.cluster_sizes", factor="subject")
    assert written(sizes, "rows") == 70
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "effective_size") == "secondary"
    within = finding_of(shareable, "structure.within_between", factor="subject", term="x")
    assert detail(within, "within_share") == "secondary"
    gram = finding_of(shareable, "identifiability.gram_rank")
    assert detail(gram, "smallest_eigenvalue") == "secondary"
    assert detail(finding_of(shareable, "keys.duplicates"), "missing_key_rows") == "secondary"


def test_a_sample_that_loses_a_quantity_beside_the_analysis_sample_is_compared_with_no_other() -> (
    None
):
    # 50 subjects of four rows and 10 of one row: the 10 rows lack the
    # covariate, or 9 lack it and 1 lacks the outcome. The design sample
    # loses its rows beside the 200 analysed rows in both tables, and were
    # the table compared with it, its 210 rows would be written beside a
    # design sample of 200 rows and hidden beside one of 201.
    def chain(y_missing: bool) -> dict[str, Any]:
        count: list[Any] = rep([0, 1, 2, 3], 50) + [1] * 10
        x: list[Any] = [i % 7 + 0.5 for i in seq_len(200)] + [None] * 10
        if y_missing:
            x[200] = 0.5
            count[200] = None
        data = frame(
            count=count,
            x=x,
            g=rep(labels("g%02d", range(1, 51)), each=4) + labels("h%02d", range(1, 11)),
        )
        return audit_both(data, "count ~ x + (1 | g)", **T1_ZEROS)["shareable"]  # type: ignore[no-any-return]

    pair = [chain(False), chain(True)]
    expect_same_reading(pair[0], pair[1])
    assert written(finding_of(pair[0], "sample.raw_vs_analysis"), "rows_raw") == 210
    sizes = finding_of(pair[0], "structure.cluster_sizes", factor="g")
    assert detail(sizes, "rows") == "secondary"

    # Rule 4 likewise leaves out the design sample, which loses its rows: 10
    # rows without a subject and 10 without the covariate, or 9 and one
    # without an outcome. missing_key_rows, 10, would be written beside a
    # design sample of 200 rows and hidden beside one of 201.
    def keyed(y_missing: bool) -> dict[str, Any]:
        subject = (
            rep(labels("s%02d", range(1, 51)), each=4) + [None] * 10 + labels("u%02d", range(1, 11))
        )
        x: list[Any] = [i % 7 + 0.5 for i in seq_len(210)] + [None] * 10
        count: list[Any] = rep([0, 1, 2, 3], 50) + [1] * 20
        if y_missing:
            x[210] = 0.5
            count[210] = None
        data = frame(
            count=count,
            x=x,
            subject=subject,
            trial=rep([1, 2, 3, 4], 50) + seq_len(10) + [1] * 10,
        )
        declaration = units(observation={"key": ["subject", "trial"]})
        found = audit_both(data, "count ~ x + (1 | subject)", declaration=declaration, **T1_ZEROS)
        return found["shareable"]  # type: ignore[no-any-return]

    pair = [keyed(False), keyed(True)]
    expect_same_reading(pair[0], pair[1])
    assert written(finding_of(pair[0], "keys.duplicates"), "missing_key_rows") == 10


def test_contributors_parts_and_combined_items_do_not_bound_the_levels_that_a_sample_loses() -> (
    None
):
    # 40 levels of f crossed with 42 of g over 168 rows with an outcome, and
    # 20 rows without one in 10 new levels of f, in 9 new levels of g of two
    # rows and 2 rows of existing levels, or in 8 new levels and 4 rows. The
    # contributors, the 50 levels of f, would be written beside 51 levels of
    # g and hidden beside 50, so rule 5 hides them with the levels of g.
    r = seq_len(168)

    def contributors(new_g: int) -> dict[str, Any]:
        extra = rep(labels("G%02d", [42 + i for i in seq_len(new_g)]), each=2) + labels(
            "G%02d", seq_len(20 - 2 * new_g)
        )
        data = frame(
            count=[i % 4 for i in r] + [None] * 20,
            x=[i % 7 + 0.5 for i in r] + [i / 3 for i in seq_len(20)],
            f=labels("F%02d", [(i - 1) % 40 + 1 for i in r])
            + rep(labels("F%02d", range(41, 51)), each=2),
            g=labels("G%02d", [(i - 1) % 42 + 1 for i in r]) + extra,
        )
        found = audit_both(data, "count ~ x + (1 | f) + (1 | g)", **T1_ZEROS)
        return found["shareable"]  # type: ignore[no-any-return]

    pair = [contributors(9), contributors(8)]
    expect_same_reading(pair[0], pair[1])
    sizes = finding_of(pair[0], "structure.cluster_sizes", factor="f")
    assert support_detail(sizes, "distinct") == "secondary"
    # 49 subjects of two rows: 30 keep both outcomes, 10 one and 9 none. A
    # part of the hidden levels written beside the 40 analysed subjects, such
    # as informative_levels 39, would show 49 or more of them.
    subject = rep(labels("s%02d", range(1, 50)), each=2)
    later = set(labels("s%02d", range(40, 50)))
    x = [0.5 if s in later else v for s, v in zip(subject, rep([0.5, 1.5], 49), strict=True)]
    count = [2, 2] * 15 + [1, 3] * 15 + [4, None] * 10 + [None] * 18
    data = frame(count=count, x=x, subject=subject)
    found = audit_both(data, "count ~ x + (1 + x | subject)", **T1_ZEROS)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert written(zeros, "levels") == 40
    dimension = finding_of(
        found["shareable"], "identifiability.levels_vs_dimension", factor="subject"
    )
    assert detail(dimension, "informative_levels") == "secondary"
    within = finding_of(found["shareable"], "structure.within_between", factor="subject", term="x")
    for name in ("multi_row_levels", "varying_levels", "informative_levels"):
        assert detail(within, name) == "secondary"
    # 25 crossed components of two levels of f and two of g, the outcome of 9
    # levels of g missing: twice the components would bound the hidden levels
    # of g by 50 beside the 41 analysed.
    grid = [
        (c, a, b) for c in range(1, 26) for a in range(1, 3) for b in range(1, 3) for _ in range(2)
    ]
    g = [f"G{c:02d}_{b}" for c, _, b in grid]
    hidden = set(labels("G%02d_2", range(1, 10)))
    m = len(grid)
    data = frame(
        f=[f"F{c:02d}_{a}" for c, a, _ in grid],
        g=g,
        count=[None if level in hidden else i % 4 for i, level in enumerate(g, start=1)],
        x=[i % 7 + 0.5 for i in seq_len(m)],
    )
    found = audit_both(data, "count ~ x + (1 | f) + (1 | g)", **T1_ZEROS)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="g")
    assert written(zeros, "levels") == 41
    assert detail(finding_of(found["shareable"], "structure.connectivity"), "components") == (
        "secondary"
    )


def test_the_counts_of_the_design_sample_do_not_bound_the_levels_that_it_loses() -> None:
    # 50 levels of f in the design sample, 10 of one row without an outcome,
    # so that the rows and the levels lost are equal: the 10 singletons of f
    # beside them would show that no analysed level of f has one row.
    r = seq_len(168)
    data = frame(
        count=[i % 4 for i in r] + [None] * 10,
        x=[i % 7 + 0.5 for i in r] + [i / 3 for i in seq_len(10)],
        f=labels("F%02d", [(i - 1) % 40 + 1 for i in r]) + labels("F%02d", range(41, 51)),
        g=labels("G%02d", [(i - 1) % 42 + 1 for i in r]) + labels("G%02d", range(43, 52)) + ["G01"],
    )
    found = audit_both(data, "count ~ x + (1 | f) + (1 | g)", **T1_ZEROS)
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="f")
    assert written(sizes, "rows") == 178
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "singletons") == "secondary"
    # 20 subjects of one row and 30 of two, the second outcome of 10 missing:
    # 80 rows and 20 singletons would bound the levels by 50, the 50 analysed
    # subjects, and show that no subject lost every outcome.
    subject = labels("o%02d", range(1, 21)) + rep(labels("s%02d", range(1, 31)), each=2)
    n = len(subject)
    count: list[Any] = [i % 4 for i in seq_len(n)]
    for j in range(10):
        count[21 + 2 * j] = None
    data = frame(count=count, x=[i % 7 + 0.5 for i in seq_len(n)], subject=subject)
    found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert written(zeros, "levels") == 50
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(sizes, "rows") == 80
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "singletons") == "secondary"


def schools_of_two_pupils() -> pd.DataFrame:
    """50 schools of two pupils of one row each, 9 pupils without an outcome
    in 9 schools."""
    count: list[Any] = [i % 4 for i in seq_len(100)]
    for i in range(1, 18, 2):
        count[i - 1] = None
    return frame(
        count=count,
        x=[i % 7 + 0.5 for i in seq_len(100)],
        school=rep(labels("s%02d", range(1, 51)), each=2),
        pupil=labels("p%03d", seq_len(100)),
    )


def test_the_levels_of_a_non_person_item_are_compared_beside_the_analysis_sample() -> None:
    # 50 schools of two pupils of one row each, 9 pupils without an outcome
    # in 9 schools: the 50 schools, a non-person count, would show 100 rows or
    # more in the design sample beside the 91 analysed.
    found = audit_both(
        schools_of_two_pupils(),
        "count ~ x + (1 | school)",
        declaration=school_pupil(),
        **T1_ZEROS,
    )
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert written(zeros, "rows") == 91
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="school")
    internal = finding_of(found["internal"], "structure.cluster_sizes", factor="school")
    assert internal["statistics"]["levels"]["count_class"] == "non_person"
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "rows") == "secondary"


def test_the_columns_of_a_factor_that_is_also_a_predictor_do_not_give_back_its_lost_levels() -> (
    None
):
    # 50 schools of four rows, 9 without an outcome: df 49 of
    # design.collinearity gives the 50 schools of the design sample, so the
    # analysis sample loses its 41, whether the schools count persons or,
    # with two pupils or more each, not.
    school = rep(labels("s%02d", range(1, 51)), each=4)
    late = set(labels("s%02d", range(42, 51)))
    count = [None if s in late else i % 5 for i, s in enumerate(school, start=1)]
    data = frame(
        count=count,
        x=[i % 7 + 0.5 for i in seq_len(200)],
        school=school,
        pupil=labels("p%03d", seq_len(200)),
    )
    declaration = school_pupil()
    for declared in (None, declaration):
        found = audit_both(
            data, "count ~ x + school + (1 | school)", declaration=declared, **T1_ZEROS
        )
        collinearity = finding_of(found["shareable"], "design.collinearity", term="school")
        assert written(collinearity, "df") == 49
        shares = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
        assert detail(shares, "levels") == "secondary"
    internal = finding_of(found["internal"], "outcome.zero_shares", factor="school")
    assert internal["statistics"]["levels"]["count_class"] == "non_person"
    constant = finding_of(found["shareable"], "outcome.constant_clusters", factor="school")
    assert detail(constant, "multi_row_levels") == "secondary"
    # The dimension of a random term over the indicators of school counts the
    # 50 schools of the table in the same way.
    data["district"] = labels("d%02d", rep(range(1, 11), 20))
    found = audit_both(
        data,
        "count ~ x + (1 | school) + (0 + school | district)",
        declaration=declaration,
        **T1_ZEROS,
    )
    dimension = finding_of(
        found["shareable"], "identifiability.levels_vs_dimension", factor="district"
    )
    assert written(dimension, "dimension") == 50
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert detail(shares, "levels") == "secondary"


def test_the_columns_of_a_factor_do_not_give_back_the_levels_that_the_filter_hides() -> None:
    # 20 subjects of two rows nested in 2 sites, site a fixed term and a
    # declared unit: structure.label_incidence counts the 2 sites as a person
    # count below k, which df 1 of design.collinearity, kept 3 and columns 3
    # of design.rank_deficiency and budget 18 beside 20 subjects would give
    # back (privacy.md, Across findings, rule 6).
    data = frame(
        y=[i % 7 + 0.25 for i in seq_len(40)],
        treatment=rep([-0.5, 0.5], 20),
        site=rep(["S1", "S2"], each=20),
        subject=rep(labels("s%02d", range(1, 21)), each=2),
    )
    site = unit("site", "cluster")
    formula = "y ~ treatment + site + (1 | subject)"
    declaration = units(site, unit("subject", "cluster", nested_in="site", id_scope="global"))
    found = audit_both(data, formula, declaration=declaration)
    incidence = finding_of(found["shareable"], "structure.label_incidence", first="site")
    assert detail(incidence, "levels_first") == "min_count"
    collinearity = finding_of(found["shareable"], "design.collinearity", term="site")
    assert detail(collinearity, "df") == "secondary"
    assert detail(collinearity, "gvif_per_df") == "secondary"
    assert collinearity["message"]["text"] == (
        "'site' has a generalised variance inflation factor per degree of freedom below 5."
    )
    treatment = finding_of(found["shareable"], "design.collinearity", term="treatment")
    assert written(treatment, "df") == 1
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    for name in ("kept", "columns", "empty_cells"):
        assert detail(rank, name) == "secondary"
    expect_message_falls_back(rank, "full_rank")
    budget = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert detail(budget, "budget") == "secondary"
    assert written(budget, "levels") == 20
    # With the subjects as the disclosure unit, each site holds 10 members,
    # so its levels are a non-person count that the document writes, and so
    # are the counts of its columns.
    declaration = units(site, unit("subject", "participant", nested_in="site", id_scope="global"))
    found = audit_both(data, formula, declaration=declaration)
    incidence = finding_of(found["shareable"], "structure.label_incidence", first="site")
    assert written(incidence, "levels_first") == 2
    collinearity = finding_of(found["shareable"], "design.collinearity", term="site")
    assert written(collinearity, "df") == 1
    assert written(finding_of(found["shareable"], "design.rank_deficiency"), "kept") == 3
    # A factor whose levels no count measures, such as an arm that only
    # labels.unicode_forms reads, keeps the counts of its columns.
    data["arm"] = rep(["a", "b", "c", "c"], 10)
    found = audit_both(data, "y ~ treatment + arm + (1 | subject)")
    assert written(finding_of(found["shareable"], "design.collinearity", term="arm"), "df") == 2
    assert written(finding_of(found["shareable"], "design.rank_deficiency"), "columns") == 4


def test_the_absence_of_an_internal_only_statistic_does_not_show_the_kept_columns() -> None:
    # 90 rows of 49 covariates and three indicators that are 1 in one row
    # each: the analysis sample keeps 53 columns, more than
    # max_bound_programs allows, so bounds is absent, whereas it would be
    # present had the outcomes of the three rows been missing. It is written
    # as suppressed.
    rng = np.random.default_rng(7)
    covariates = rng.normal(size=(90, 49))
    columns: dict[str, list[Any]] = {f"x{j + 1:02d}": covariates[:, j].tolist() for j in range(49)}
    columns["y"] = rng.binomial(1, 0.5, size=90).astype(float).tolist()
    for j in range(1, 4):
        columns[f"d{j}"] = [float(i == j) for i in seq_len(90)]
    formula = "y ~ " + " + ".join([*labels("x%02d", range(1, 50)), "d1", "d2", "d3"])
    found = separation(frame(**columns), formula)
    assert "bounds" not in found["internal"]["statistics"]
    assert "columns_involved" not in found["internal"]["statistics"]
    for name in ("columns", "optimum", "margin", "bounds", "columns_involved"):
        assert detail(found["shareable"], name) == "internal_only"


def test_the_columns_of_the_combination_of_a_term_s_factors_do_not_give_back_its_lost_levels() -> (
    None
):
    # 19 cells of A and B of three rows, the cell (a4, b5) empty, with
    # count ~ x + A * B + (1 | A:B): df 3 and 4 of A and B and empty_cells 1
    # give the 19 combinations of the design sample, which beside the
    # analysed combinations would show how many lack an outcome.
    # structure.label_incidence counts the 4 levels of A and the 5 of B,
    # person counts below k, so rule 6 suppresses these counts of columns
    # too, and the analysis sample loses its combinations all the same.
    cells = [
        (a, b)
        for b in labels("b%d", range(1, 6))
        for a in labels("a%d", range(1, 5))
        if (a, b) != ("a4", "b5")
    ]
    rows = rep(cells, each=3)
    n = len(rows)
    data = frame(
        A=[row[0] for row in rows],
        B=[row[1] for row in rows],
        x=[i % 7 + 0.5 for i in seq_len(n)],
        count=[None if row == ("a1", "b1") else i % 4 for i, row in enumerate(rows, start=1)],
    )
    found = audit_both(data, "count ~ x + A * B + (1 | A:B)", **T1_ZEROS)
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    internal = finding_of(found["internal"], "design.rank_deficiency")
    assert written(internal, "empty_cells") == 1
    for name in ("empty_cells", "kept", "columns"):
        assert detail(rank, name) == "secondary"
    collinearity = finding_of(found["shareable"], "design.collinearity", term="A")
    assert detail(collinearity, "df") == "secondary"
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="A:B")
    assert written(shares, "rows") == 54
    assert detail(shares, "levels") == "secondary"


def test_the_sizes_of_the_levels_of_the_design_sample_do_not_give_back_what_the_analysed_ones_lost() -> (  # noqa: E501
    None
):
    # 20 subjects of one row and 40 of two, 10 of these without an outcome:
    # the 100 rows, 20 subjects of one row and 40 of two of the design sample
    # show that no subject has three rows, which beside 50 analysed subjects
    # of 80 rows would show that no analysed subject of two rows lost an
    # outcome, so the design sample and the table lose their rows.
    def run(subject: list[str], lost: Any) -> dict[str, Any]:
        n = len(subject)
        count = [
            None if lost(j, s) else i % 4
            for j, (i, s) in enumerate(zip(seq_len(n), subject, strict=True))
        ]
        data = frame(count=count, x=[i % 7 + 0.5 for i in seq_len(n)], subject=subject)
        found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
        return found["shareable"]  # type: ignore[no-any-return]

    subject = labels("o%02d", range(1, 21)) + rep(labels("t%02d", range(1, 41)), each=2)
    shareable = run(subject, lambda j, s: s >= "t31")
    shares = finding_of(shareable, "outcome.zero_shares", factor="subject")
    assert [written(shares, "rows"), written(shares, "levels")] == [80, 50]
    sizes = finding_of(shareable, "structure.cluster_sizes", factor="subject")
    assert [written(sizes, "levels"), written(sizes, "singletons")] == [60, 20]
    assert detail(sizes, "rows") == "secondary"
    assert detail(sizes, "effective_size") == "secondary"
    assert detail(finding_of(shareable, "sample.raw_vs_analysis"), "rows_raw") == "secondary"
    # With 10 more subjects of two rows that lose their second outcome, 30
    # analysed subjects of one row out of 60 and 90 rows are the only value
    # that the sizes leave, so the design sample loses its rows again.
    subject = labels("o%02d", range(1, 21)) + rep(labels("t%02d", range(1, 51)), each=2)
    second = set(labels("t%02d", range(31, 41)))
    shareable = run(
        subject,
        lambda j, s: s >= "t41" or (s in second and subject.index(s) < j),
    )
    sizes = finding_of(shareable, "structure.cluster_sizes", factor="subject")
    assert written(sizes, "levels") == 70
    assert detail(sizes, "rows") == "secondary"
    # 40 subjects of two rows, 10 without an outcome: no analysed subject has
    # one row, so rule 2 hides the analysed subjects with two rows, and the
    # design sample loses its own, with every count of its subjects and the
    # reals that read them, while it writes its rows. 80 rows, 40 levels and
    # effective_size 2 would otherwise show the analysed sizes.
    subject = rep(labels("s%02d", range(1, 41)), each=2)
    shareable = run(subject, lambda j, s: s >= "s31")
    sizes = finding_of(shareable, "structure.cluster_sizes", factor="subject")
    assert written(sizes, "rows") == 80
    assert detail(sizes, "levels") == "secondary"
    assert detail(sizes, "effective_size") == "secondary"


def test_a_written_part_does_not_bound_a_hidden_count_of_the_analysis_sample() -> None:
    # 50 schools of four rows, 40 with zero counts, the outcome of one school
    # missing or not: the levels hidden beside df 49, all_zero_levels 40
    # would show 50 analysed schools, so that none lacks an outcome.
    school = rep(labels("s%02d", range(1, 51)), each=4)
    data = frame(
        count=[0 if s <= "s40" else i % 3 + 1 for i, s in enumerate(school, start=1)],
        x=[i % 7 + 0.5 for i in seq_len(200)],
        school=school,
    )
    found = audit_both(data, "count ~ x + school + (1 | school)", **T1_ZEROS)
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert detail(shares, "levels") == "secondary"
    assert detail(shares, "all_zero_levels") == "secondary"
    # 50 subjects of two rows, 30 with zero counts, 10 without an outcome and
    # one without its second: rule 3 hides the 40 analysed subjects beside 79
    # rows, which all_zero_levels 30 would bound from below by 40.
    subject = rep(labels("s%02d", range(1, 51)), each=2)
    count: list[Any] = [
        None if s >= "s41" else (0 if s <= "s30" else i % 3 + 1)
        for i, s in enumerate(subject, start=1)
    ]
    count[79] = None
    data = frame(count=count, time=rep([0, 1], 50), subject=subject)
    found = audit_both(data, "count ~ time + (1 | subject)", **T1_ZEROS)
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert written(shares, "rows") == 79
    assert detail(shares, "levels") == "secondary"
    assert detail(shares, "all_zero_levels") == "secondary"


def test_the_rows_and_the_columns_of_a_factor_that_is_also_a_predictor_do_not_bound_its_lost_levels() -> (  # noqa: E501
    None
):
    # 30 schools of two rows and 20 of one, the 10 schools s41 to s50 of one
    # row without an outcome: df 49 and 80 rows would bound the design
    # sample's schools with two rows by 30, which outcome.constant_clusters
    # writes for the analysis sample, showing that none lost an outcome. The
    # analysed schools with two rows hold all their rows, so the design
    # sample loses its rows.
    school = rep(labels("s%02d", range(1, 31)), each=2) + labels("s%02d", range(31, 51))
    n = len(school)
    offsets = rep_len([0, 0.5], n)
    constant = rep([float(j) for j in range(1, 11)], each=2)
    y: list[Any] = []
    for i, s in enumerate(school, start=1):
        if s <= "s10":
            y.append(constant[i - 1])
        elif s >= "s41":
            y.append(None)
        else:
            y.append(i / 7 + offsets[i - 1])
    data = frame(y=y, x=[i % 5 + 0.5 for i in seq_len(n)], school=school)
    found = audit_both(
        data,
        "y ~ x + school + (1 | school)",
        outcome_access="T1",
        reason="Constant levels.",
    )
    constant_finding = finding_of(found["shareable"], "outcome.constant_clusters", factor="school")
    assert written(constant_finding, "multi_row_levels") == 30
    collinearity = finding_of(found["shareable"], "design.collinearity", term="school")
    assert written(collinearity, "df") == 49
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="school")
    assert detail(sizes, "rows") == "secondary"
    # 50 schools of two pupils, the disclosure unit, 9 of them without an
    # outcome: df 49 and two pupils or more in each school bound the rows of
    # the design sample, hidden beside the 91 analysed, by 100, so the
    # analysis sample loses its rows.
    found = audit_both(
        schools_of_two_pupils(),
        "count ~ x + school + (1 | school)",
        declaration=school_pupil(),
        **T1_ZEROS,
    )
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert detail(shares, "rows") == "secondary"
    assert support_detail(shares, "rows") == "secondary"
    assert support_detail(shares, "distinct") == "secondary"


def test_the_levels_that_the_analysis_sample_hides_are_hidden_in_the_design_sample_too() -> None:
    # 20 subjects of two rows, 10 without an outcome and one without its
    # second: rule 3 hides the 10 analysed subjects beside 19 rows, which the
    # minimum-count rule bounds by 10 from below, and 20 written levels of the
    # design sample, k or more above them, would leave 10.
    subject = rep(labels("s%02d", range(1, 21)), each=2)
    count: list[Any] = [None if s >= "s11" else i % 4 for i, s in enumerate(subject, start=1)]
    count[1] = None
    data = frame(count=count, x=[i % 7 + 0.5 for i in seq_len(40)], subject=subject)
    found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert detail(shares, "levels") == "secondary"
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert detail(sizes, "levels") == "secondary"
    # 20 subjects of four rows, 15 of which lose two outcomes each: the
    # design sample keeps its rows and loses its levels, and the reals that
    # read the subjects would give the levels of the balanced design from the
    # rows.
    subject = rep(labels("s%02d", range(1, 21)), each=4)
    trial = rep([1, 2, 3, 4], 20)
    count = [
        None if s <= "s15" and t <= 2 else i % 4
        for i, (s, t) in enumerate(zip(subject, trial, strict=True), start=1)
    ]
    data = frame(count=count, x=[i % 7 + 0.5 for i in seq_len(80)], subject=subject)
    found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
    assert written(sizes, "rows") == 80
    assert detail(sizes, "effective_size") == "secondary"
    gram = finding_of(found["shareable"], "identifiability.gram_rank")
    assert detail(gram, "smallest_eigenvalue") == "secondary"


def test_the_analysed_rows_are_hidden_beside_k_contributors_or_more_when_fewer_than_2k() -> None:
    # 9 subjects of one row and one of two, every outcome present: the
    # minimum-count rule holds for 10 subjects, which beside 11 written rows
    # would show that 9 have one analysed row.
    data = frame(
        count=[0, 1, 2, 3, 0, 1, 2, 3, 1, 2, 0],
        x=[i / 3 for i in seq_len(11)],
        subject=labels("s%02d", range(1, 10)) + ["s10", "s10"],
    )
    found = audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="subject")
    assert detail(shares, "rows") == "secondary"
    assert support_detail(shares, "rows") == "secondary"


def test_step_7_applies_steps_6_and_9_to_the_findings_on_the_analysis_sample_before_it_is_shown() -> (  # noqa: E501
    None
):
    # 50 schools of two pupils, a fixed term and a declared cluster, and a
    # bounded score without its value for 9 pupils: df 49 and the two pupils
    # or more of each school bound the 100 rows of the design sample, so the
    # analysis sample loses its 91 rows. Step 5 then suppresses the shares of
    # outcome.boundary_shares, whose decision reads them, so that the
    # finding, the only one on the analysis sample, is suppressed as a whole
    # and the document does not show the analysis sample: the design sample
    # writes its rows.
    score: list[Any] = rep([0.5, 9.5, 3, 4, 5], 20)
    for i in range(1, 18, 2):
        score[i - 1] = None
    data = frame(
        score=score,
        x=[i % 7 + 0.5 for i in seq_len(100)],
        school=rep(labels("s%02d", range(1, 51)), each=2),
        pupil=labels("p%03d", seq_len(100)),
    )
    declaration = school_pupil()
    declaration["variables"] = {
        "score": {"role": "outcome", "measurement": "bounded_score", "bounds": [0.5, 9.5]}
    }
    found = audit_both(
        data, "score ~ x + school", declaration=declaration, outcome_access="T1", reason="Bounds."
    )
    bounds = finding_of(found["shareable"], "outcome.boundary_shares")
    assert bounds["status"]["availability"]["detail"] == "decision"
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    assert written(rank, "support_rows") == 100


def test_a_count_of_levels_lost_beside_the_analysis_sample_is_compared_with_no_other_sample() -> (
    None
):
    # 20 subjects of one row and 30 of four rows: 10 of these lack the
    # covariate, or 9 lack it and one lacks every outcome. The design sample
    # loses the levels of subject beside the 40 analysed in both tables, and
    # the table's 50 contributors would be written beside 40 subjects of the
    # design sample and hidden beside 41. The analysed subjects of one row
    # and of four rows both number k or more, so rule 2 hides neither.
    def make(y_missing: bool) -> dict[str, Any]:
        g = labels("o%02d", range(1, 21)) + rep(labels("s%02d", range(1, 31)), each=4)
        without = set(labels("s%02d", range(21, 30) if y_missing else range(21, 31)))
        data = frame(
            count=[None if y_missing and s == "s30" else i % 4 for i, s in enumerate(g, start=1)],
            x=[None if s in without else i % 7 + 0.5 for i, s in enumerate(g, start=1)],
            g=g,
        )
        return audit_both(data, "count ~ x + (1 | g)", **T1_ZEROS)["shareable"]  # type: ignore[no-any-return]

    pair = [make(False), make(True)]
    expect_same_reading(pair[0], pair[1])
    assert written(finding_of(pair[0], "sample.raw_vs_analysis"), "contributors") == 50


def test_a_disclosure_unit_whose_members_each_have_one_row_keeps_its_counts() -> None:
    # 200 pupils of one row each in 20 schools, 30 of them without an
    # outcome: the analysed pupils are the analysed rows whatever the
    # outcome, so rule 3 leaves the pupils out, and the pupils' levels with
    # two rows, 0 in every sample, are not compared, so the design sample
    # keeps its 200 contributors. The schools, which count non-persons, keep
    # their counts and reals, since the design sample loses neither its rows
    # nor its pupils beside the analysis sample.
    lost = set(range(3, 201, 20)) | set(range(5, 201, 20)) | set(range(8, 201, 20))
    data = frame(
        count=[None if i in lost else (i * 5) % 4 for i in seq_len(200)],
        x=[(i * 7) % 11 + 0.5 for i in seq_len(200)],
        school=labels("S%02d", rep(range(1, 21), each=10)),
        pupil=labels("p%03d", seq_len(200)),
    )
    found = audit_both(data, "count ~ x + (1 | school)", declaration=school_pupil(), **T1_ZEROS)
    shares = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert [written(shares, "support_rows"), written(shares, "contributors")] == [170, 170]
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="school")
    assert [
        written(sizes, "rows"),
        written(sizes, "contributors"),
        written(sizes, "levels"),
    ] == [200, 200, 20]
    assert written(sizes, "effective_size") is not None
    within = finding_of(found["shareable"], "structure.within_between", factor="school", term="x")
    assert written(within, "within_share") is not None


def test_outcome_separation_with_one_kept_column_of_two_variables_or_one_factor_is_suppressed() -> (
    None
):
    # One kept column besides the intercept, which reads x and z: a verdict
    # of quasi or complete would name a cell of x:z.
    x = seq_len(40)
    z = [100 + i % 7 for i in seq_len(40)]
    products = [a * b for a, b in zip(x, z, strict=True)]
    middle = statistics.median(products)
    data = frame(y=[float(p > middle) for p in products], x=x, z=z)
    found = separation(data, "y ~ x:z")
    assert written(found["internal"], "verdict") == "complete"
    assert found["shareable"]["status"]["availability"]["detail"] == "decision"
    # A factor of 24 levels of one row each: no two rows share the values of
    # the kept columns, and the verdict would show the class of each level.
    data = frame(y=rep([1.0, 0.0], 12), g=labels("g%02d", range(1, 25)))
    found = separation(data, "y ~ g")
    assert written(found["internal"], "verdict") == "complete"
    assert found["shareable"]["status"]["availability"]["detail"] == "decision"


def test_only_the_rows_of_assignments_that_yield_findings_are_samples() -> None:
    # 30 classes of 2 rows without a disclosure unit. 'arm' is missing in
    # classes 1 to 10 and 'dose' in classes 1 to 11, so the rows of 'dose'
    # lie in those of 'arm' and differ by one class.
    classes = rep(labels("c%02d", range(1, 31)), each=2)
    position = [int(c[1:]) - 1 for c in classes]
    arm = [
        None if c <= "c10" else ["a", "b"][p % 2] for c, p in zip(classes, position, strict=True)
    ]
    dose = [
        None if c <= "c11" else ["d1", "d2", "d3"][p % 3]
        for c, p in zip(classes, position, strict=True)
    ]
    n = len(classes)
    data = frame(
        y=[i % 7 for i in seq_len(n)],
        x=[i % 5 for i in seq_len(n)],
        **{"class": classes},
        arm=arm,
        dose=dose,
    )

    def design_df(level: str) -> dict[str, Any]:
        declaration = units(
            unit("class", "cluster"),
            assignment=[assignment("arm", "class"), assignment("dose", "class", level)],
        )
        found = audit_both(data, "y ~ x + (1 | class)", declaration=declaration)
        return finding_of(found["shareable"], "assignment.design_df", column="arm")

    # 'dose' within units yields no finding, so its rows are not a sample.
    assert written(design_df("within_unit"), "units") == 20
    assert detail(design_df("between_unit"), "units") == "secondary"


def test_the_rows_of_two_pairs_of_columns_that_hold_the_same_rows_are_one_sample() -> None:
    # 24 classes and 24 teachers in 12 schools, which are not in the formula
    # and are missing in schools 7 to 12: the pairs (class, school) and
    # (school, teacher) read the same 24 rows.
    index = rep(range(1, 25), each=2)
    n = len(index)
    data = frame(
        y=[i % 7 for i in seq_len(n)],
        x=[i % 5 for i in seq_len(n)],
        **{"class": labels("c%02d", index)},
        teacher=labels("t%02d", index),
        school=[f"S{(i + 1) // 2:02d}" if i <= 12 else None for i in index],
    )
    declaration = units(
        unit("school", "cluster"),
        unit("class", "cluster", nested_in="school", id_scope="global"),
        unit("teacher", "cluster", nested_in="school", id_scope="global"),
    )
    found = audit_both(data, "y ~ x + (1 | class) + (1 | teacher)", declaration=declaration)
    classes = finding_of(
        found["shareable"], "structure.label_incidence", first="class", second="school"
    )
    teachers = finding_of(
        found["shareable"], "structure.label_incidence", first="school", second="teacher"
    )
    assert written(classes, "levels_first") == 12
    assert written(teachers, "levels_second") == 12


def test_a_draft_declaration_has_the_disclosure_unit_of_the_units_that_do_not_count_as_absent() -> (
    None
):
    data = frame(
        y=[i % 5 for i in seq_len(24)],
        x=[i % 7 for i in seq_len(24)],
        **{"class": rep(labels("c%d", range(1, 7)), each=4)},
        pupil=rep(labels("p%02d", range(1, 13)), each=2),
    )

    def draft(inferred: list[str], disclosure_unit: str | None = None) -> dict[str, Any]:
        declaration = units(
            unit("class", "cluster"),
            unit("pupil", "participant"),
            provenance={"inferred": inferred},
        )
        if disclosure_unit is not None:
            declaration["disclosure_unit"] = disclosure_unit
        results = audit(data, "y ~ x + (1 | class)", declaration=declaration, key=PRIVACY_KEY)
        return results.document

    # A disclosure_unit that names a unit that counts as absent counts as
    # absent itself, so that the one participant unit is the default.
    document = draft(["/units/0"], "class")
    assert document["privacy"]["disclosure_unit"] == {"name": "pupil", "source": "participant"}
    # A unit one of whose columns is inferred counts as absent, so that no
    # unit is the disclosure unit.
    for inferred in ("/units/1/columns", "/units/1/columns/0", "/units/1/name"):
        document = draft([inferred])
        assert "disclosure_unit" not in document["privacy"]
        sizes = finding_of(document, "structure.cluster_sizes", factor="class")
        assert sizes["support"]["contributors"]["basis"] == "grouping_factors"


# --- Counts of columns, chains and the clauses of steps 6 and 7 -----------------------


def test_a_term_s_variables_are_matched_to_an_item_on_the_rows_that_its_counts_read() -> None:
    # 99 cells of A and B with three rows each, the outcome missing in one,
    # and cell, which labels them, missing in one row, which leaves the
    # design sample: A:B divides the design sample, though not the table,
    # into the levels of cell, so kept 100 and empty_cells 1 give its 99
    # levels there, and the 98 analysed levels must be hidden.
    cells = [
        (a, b)
        for a in labels("a%02d", range(1, 11))
        for b in labels("b%02d", range(1, 11))
        if (a, b) != ("a10", "b10")
    ]
    cells.append(cells.pop(cells.index(("a09", "b10"))))
    rows = [cell for cell in cells for _ in range(3)]
    n = len(rows)
    count: list[Any] = [i % 4 for i in seq_len(n)]
    for j, cell in enumerate(rows):
        if cell == ("a01", "b01"):
            count[j] = None
    cell_labels: list[Any] = [f"{a}-{b}" for a, b in rows]
    cell_labels[n - 1] = None
    data = frame(
        A=[a for a, _ in rows],
        B=[b for _, b in rows],
        x=[i % 7 + 0.5 for i in seq_len(n)],
        count=count,
        cell=cell_labels,
    )
    found = audit_both(data, "count ~ x + A * B + (1 | cell)", **T1_ZEROS)
    internal = finding_of(found["internal"], "outcome.zero_shares", factor="cell")
    assert written(internal, "levels") == 98
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    assert written(rank, "kept") == 100
    assert written(rank, "empty_cells") == 1
    shared = finding_of(found["shareable"], "outcome.zero_shares", factor="cell")
    assert detail(shared, "levels") == "secondary"
    # school2 copies the grouping factor school but lacks a label in one row:
    # df 49 gives the 50 schools of the design sample beside 41 analysed ones.
    school = rep(labels("s%02d", range(1, 51)), each=4)
    lacking = set(labels("s%02d", range(42, 51)))
    data = frame(
        count=[None if s in lacking else i % 5 for i, s in zip(seq_len(200), school, strict=True)],
        x=[i % 7 + 0.5 for i in seq_len(200)],
        school=school,
        school2=[None, *school[1:]],
    )
    found = audit_both(data, "count ~ x + school2 + (1 | school)", **T1_ZEROS)
    collinearity = finding_of(found["shareable"], "design.collinearity", term="school2")
    assert written(collinearity, "df") == 49
    shared = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert detail(shared, "levels") == "secondary"
    # site2 copies the declared unit site, whose 4 levels step 3 hides, but
    # lacks its label in one row: its columns count the sites of the design
    # sample.
    subject = rep(labels("s%02d", range(1, 41)), each=5)
    site = [f"S{(int(s[1:]) - 1) // 10 + 1}" for s in subject]
    data = frame(
        y=[(i * 5) % 13 + 0.25 for i in seq_len(200)],
        treatment=rep([0.5, -0.5], 100),
        site=site,
        subject=subject,
        site2=[None, *site[1:]],
    )
    declaration = units(
        unit("site", "cluster"), unit("subject", "cluster", nested_in="site", id_scope="global")
    )
    found = audit_both(data, "y ~ treatment + site2 + (1 | subject)", declaration=declaration)
    incidence = finding_of(found["shareable"], "structure.label_incidence", first="site")
    assert detail(incidence, "levels_first") == "min_count"
    collinearity = finding_of(found["shareable"], "design.collinearity", term="site2")
    assert detail(collinearity, "df") == "secondary"
    assert detail(collinearity, "gvif_per_df") == "secondary"
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    for name in ("kept", "columns", "empty_cells"):
        assert detail(rank, name) == "secondary"
    budget = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert detail(budget, "budget") == "secondary"


def test_the_columns_of_the_ir_do_not_give_back_the_levels_that_rule_1_hides_in_the_table() -> None:
    # 12 sites crossed with 20 districts, two rows each, and x missing in
    # every row of S12: dimension 12 of (0 + site | district), and columns 12
    # of identifiability.residual_confounding, count the sites of the table,
    # which rule 1 hides beside the 11 that structure.cluster_sizes counts in
    # the design sample.
    rows = [
        (site, district)
        for district in labels("d%02d", range(1, 21))
        for site in labels("S%02d", range(1, 13))
        for _ in range(2)
    ]
    n = len(rows)
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(n)],
        x=[
            None if site == "S12" else i % 5 + 0.25
            for i, (site, _) in zip(seq_len(n), rows, strict=True)
        ],
        site=[site for site, _ in rows],
        district=[district for _, district in rows],
    )
    found = audit_both(data, "y ~ x + (0 + site | district) + (1 | site)")
    internal = finding_of(
        found["internal"], "identifiability.levels_vs_dimension", factor="district"
    )
    assert written(internal, "dimension") == 12
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="site")
    assert written(sizes, "levels") == 11
    shared = finding_of(
        found["shareable"], "identifiability.levels_vs_dimension", factor="district"
    )
    assert detail(shared, "dimension") == "secondary"
    confounding = finding_of(
        found["shareable"], "identifiability.residual_confounding", factor="district"
    )
    assert detail(confounding, "columns") == "secondary"
    own = finding_of(found["shareable"], "identifiability.levels_vs_dimension", factor="site")
    assert written(own, "dimension") == 1
    # Without the grouping factor site, no count measures the levels of
    # site, a predictor that only labels.unicode_forms reads, and dimension
    # stays.
    found = audit_both(data, "y ~ x + (0 + site | district)")
    shared = finding_of(
        found["shareable"], "identifiability.levels_vs_dimension", factor="district"
    )
    assert written(shared, "dimension") == 12


def test_the_random_terms_that_split_from_a_frozen_factor_keep_their_dimension() -> None:
    # 3 sites, whose levels step 3 hides, split by '||' into random terms of
    # one column each, whose dimension is 1 whatever the levels.
    subject = rep(labels("s%02d", range(1, 41)), each=6)
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(240)],
        site=[f"S{(int(s[1:]) - 1) % 3 + 1}" for s in subject],
        subject=subject,
    )
    declaration = units(
        unit("site", "cluster"), unit("subject", "cluster", nested_in="site", id_scope="global")
    )
    found = audit_both(
        data,
        "y ~ 1 + (1 + site || subject)",
        declaration=declaration,
        coding={"site": {"frozen": True}},
    )
    incidence = finding_of(found["shareable"], "structure.label_incidence", first="site")
    assert detail(incidence, "levels_first") == "min_count"
    for term in ("0 + site[S2] | subject", "0 + site[S3] | subject"):
        levels = finding_of(found["shareable"], "identifiability.levels_vs_dimension", term=term)
        assert written(levels, "dimension") == 1
        confounding = finding_of(
            found["shareable"], "identifiability.residual_confounding", term=term
        )
        assert written(confounding, "columns") == 1


def test_the_columns_of_a_term_on_analysed_rows_are_suppressed_with_the_levels_hidden_there() -> (
    None
):
    # 50 schools of 4 pupils with two rows each, and 9 schools without the
    # outcome or treat, which is assigned to the pupils, so that the rows of
    # the assignment are the analysis sample: units 164 less design_df would
    # give the 41 analysed schools, which beside the 50 of kept show that 9
    # lack an outcome.
    school = rep(labels("s%02d", range(1, 51)), each=8)
    pupil = rep(labels("p%03d", range(1, 201)), each=2)
    lacking = set(labels("s%02d", range(42, 51)))
    data = frame(
        count=[None if s in lacking else i % 4 for i, s in zip(seq_len(400), school, strict=True)],
        school=school,
        pupil=pupil,
        treat=[
            None if s in lacking else ("a" if int(p[1:]) % 2 == 0 else "b")
            for s, p in zip(school, pupil, strict=True)
        ],
    )
    declaration = units(
        unit("school", "cluster"),
        unit("pupil", "cluster", nested_in="school", id_scope="global"),
        assignment=[assignment("treat", "pupil")],
    )
    found = audit_both(data, "count ~ school + (1 | school)", declaration=declaration, **T1_ZEROS)
    internal = finding_of(found["internal"], "assignment.design_df", column="treat")
    assert written(internal, "design_df") == 123
    shared = finding_of(found["shareable"], "assignment.design_df", column="treat")
    assert written(shared, "units") == 164
    assert detail(shared, "design_df") == "secondary"
    assert written(finding_of(found["shareable"], "design.rank_deficiency"), "kept") == 50
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="school")
    assert detail(zeros, "levels") == "secondary"


def test_the_columns_of_a_factor_are_hidden_when_every_finding_that_counts_its_levels_fails() -> (
    None
):
    # 12 sites of two rows beside a grouping factor of 3 levels, so that
    # every finding fails the minimum-count rule, which hides the 12 sites
    # although they are k or more.
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(24)],
        x=[i % 5 + 0.25 for i in seq_len(24)],
        site=rep(labels("S%02d", range(1, 13)), each=2),
        g2=rep(["g1", "g2", "g3"], 8),
    )
    found = audit_both(data, "y ~ x + site + (1 | g2) + (1 | site)")
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="site")
    assert detail(sizes, "levels") == "min_count_rule"
    site = finding_of(found["shareable"], "design.collinearity", term="site")
    assert detail(site, "df") == "secondary"
    assert written(finding_of(found["shareable"], "design.collinearity", term="x"), "df") == 1
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    for name in ("kept", "columns", "empty_cells"):
        assert detail(rank, name) == "secondary"
    # A grouping factor of 10 levels, two of which hold 180 of the 196 rows,
    # makes every finding fail the dominance rule instead.
    n = 196
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(n)],
        x=[i % 5 + 0.25 for i in seq_len(n)],
        site=[f"S{(i - 1) % 12 + 1:02d}" for i in seq_len(n)],
        g2=rep("g01", 95) + rep("g02", 85) + rep(labels("g%02d", range(3, 11)), each=2),
    )
    found = audit_both(data, "y ~ x + site + (1 | g2) + (1 | site)")
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="site")
    assert detail(sizes, "levels") == "dominance"
    site = finding_of(found["shareable"], "design.collinearity", term="site")
    assert detail(site, "df") == "secondary"
    assert detail(finding_of(found["shareable"], "design.rank_deficiency"), "kept") == "secondary"


def test_the_columns_of_a_term_on_the_rows_of_an_assignment_are_hidden_with_their_levels_there() -> (  # noqa: E501
    None
):
    # 12 sites of 10 subjects with two rows each. dose, assigned to the
    # subjects, and arm, assigned to the sites, are both missing for the
    # first subject of every site, so that their rows are one sample, which
    # keeps the 12 sites. Rule 1 hides its sites beside the 12 of the design
    # sample, and design_df of dose, 96 beside 108 units, would give them
    # back.
    site = rep(labels("S%02d", range(1, 13)), each=20)
    subject = rep(labels("u%03d", range(1, 121)), each=2)
    first = {f"u{i:03d}" for i in range(1, 121, 10)}
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(240)],
        site=site,
        subject=subject,
        dose=[None if u in first else ("lo" if int(u[1:]) % 2 == 0 else "hi") for u in subject],
        arm=[
            None if u in first else ("a" if int(s[1:]) % 2 == 0 else "b")
            for s, u in zip(site, subject, strict=True)
        ],
    )
    declaration = units(
        unit("site", "cluster"),
        unit("subject", "cluster", nested_in="site", id_scope="global"),
        assignment=[assignment("dose", "subject"), assignment("arm", "site")],
    )
    found = audit_both(data, "y ~ site + (1 | subject)", declaration=declaration)
    internal = finding_of(found["internal"], "assignment.design_df", column="dose")
    assert written(internal, "design_df") == 96
    dose = finding_of(found["shareable"], "assignment.design_df", column="dose")
    assert written(dose, "units") == 108
    assert detail(dose, "design_df") == "secondary"
    arm = finding_of(found["shareable"], "assignment.design_df", column="arm")
    assert detail(arm, "units") == "secondary"
    incidence = finding_of(found["shareable"], "structure.label_incidence", first="site")
    assert written(incidence, "levels_first") == 12


def test_the_columns_of_the_combination_of_a_term_s_factors_are_hidden_with_its_levels() -> None:
    # 13 subjects, the disclosure unit, each with a row in each combination
    # of A and B apart from (a2, b3), which one subject holds: step 3 hides
    # the 6 levels of the grouping factor A:B, which kept, columns and
    # empty_cells would give back beside the levels of A and B.
    rows = [
        (f"s{s:02d}", a, b)
        for s in range(1, 14)
        for a in ("a1", "a2")
        for b in ("b1", "b2", "b3")
        if s == 13 or (a, b) != ("a2", "b3")
    ]
    n = len(rows)
    data = frame(
        subject=[s for s, _, _ in rows],
        A=[a for _, a, _ in rows],
        B=[b for _, _, b in rows],
        x=[i % 5 + 0.5 for i in seq_len(n)],
        y=[(i * 7) % 11 + 0.5 for i in seq_len(n)],
    )
    found = audit_both(
        data,
        "y ~ x + A * B + (1 | subject) + (1 | A:B)",
        declaration=subject_declaration(),
    )
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="A:B")
    assert detail(sizes, "levels") == "min_count"
    assert written(finding_of(found["shareable"], "design.collinearity", term="A"), "df") == 1
    assert written(finding_of(found["shareable"], "design.collinearity", term="B"), "df") == 2
    rank = finding_of(found["shareable"], "design.rank_deficiency")
    for name in ("kept", "columns", "empty_cells"):
        assert detail(rank, name) == "secondary"


def test_a_count_of_columns_below_k_that_rule_6_suppresses_has_the_detail_secondary() -> None:
    # 18 subjects of two rows nested in 9 sites: step 3 hides the 9 sites,
    # and budget 18 - 9 = 9 with the detail 'min_count' would bound them by
    # 18 - 9, so that they would be 9.
    data = frame(
        y=[(i * 7) % 11 + 0.5 for i in seq_len(36)],
        treatment=rep([-0.5, 0.5], 18),
        site=rep(labels("S%d", range(1, 10)), each=4),
        subject=rep(labels("s%02d", range(1, 19)), each=2),
    )
    declaration = units(
        unit("site", "cluster"), unit("subject", "cluster", nested_in="site", id_scope="global")
    )
    found = audit_both(data, "y ~ treatment + site + (1 | subject)", declaration=declaration)
    internal = finding_of(found["internal"], "identifiability.df_budget", factor="subject")
    assert written(internal, "budget") == 9
    budget = finding_of(found["shareable"], "identifiability.df_budget", factor="subject")
    assert detail(budget, "budget") == "secondary"
    assert budget["statistics"]["budget"]["count_class"] == "person"
    assert written(budget, "levels") == 18


def test_a_sample_inside_one_that_loses_its_levels_beside_the_analysis_sample_is_compared() -> None:
    # 50 subjects of four rows, the unit to which z is assigned, z missing
    # for s50, and s01 without the covariate or without the outcome. The
    # design sample loses its subjects beside the 49 analysed ones either
    # way, and the rows of the assignment, which lie in it but leave out s50,
    # lose theirs beside the analysis sample, whose 49 exceed their 48 or 49
    # by fewer than k, so that the two tables read alike.
    def make(y_missing: bool) -> dict[str, Any]:
        subject = rep(labels("s%02d", range(1, 51)), each=4)
        data = frame(
            count=[
                None if y_missing and s == "s01" else v
                for s, v in zip(subject, rep([0, 1, 2, 3], 50), strict=True)
            ],  # noqa: E501
            x=[
                None if not y_missing and s == "s01" else i % 7 + 0.5
                for i, s in zip(seq_len(200), subject, strict=True)
            ],  # noqa: E501
            subject=subject,
            z=[None if s == "s50" else ("a" if int(s[1:]) % 2 == 0 else "b") for s in subject],
        )
        declaration = subject_declaration(assignment=[assignment("z", "subject")])
        return audit_both(data, "count ~ x + (1 | subject)", declaration=declaration, **T1_ZEROS)

    first = make(False)
    second = make(True)
    internal = finding_of(second["internal"], "assignment.design_df", column="z")
    assert written(internal, "units") == 49
    for found in (first, second):
        for check in ("assignment.design_df", "assignment.constant_within_unit"):
            assert detail(finding_of(found["shareable"], check, column="z"), "units") == "secondary"
    expect_same_reading(first["shareable"], second["shareable"])


def test_the_rows_that_the_analysis_sample_hides_are_hidden_in_the_samples_that_hold_its_rows() -> (  # noqa: E501
    None
):
    # 12 subjects of two rows, each with one outcome or two: 13 or 15
    # analysed rows, which rule 3 hides beside 12 contributors. Beside 15,
    # rule 1 hides the 24 rows of the design sample, and beside 13 the
    # design sample loses them because the analysis sample hides its own, so
    # that the two tables read alike.
    def make(second: int) -> dict[str, Any]:
        count: list[Any] = rep([1, 2], 12)
        for position in list(range(1, 24, 2))[second:]:
            count[position] = None
        data = frame(
            count=count,
            x=[i % 5 + 0.5 for i in seq_len(24)],
            subject=rep(labels("s%02d", range(1, 13)), each=2),
        )
        return audit_both(data, "count ~ x + (1 | subject)", **T1_ZEROS)

    first = make(1)
    second = make(3)
    for found in (first, second):
        sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="subject")
        assert detail(sizes, "rows") == "secondary"
        assert written(sizes, "support_rows") is None
    expect_same_reading(first["shareable"], second["shareable"])


def test_the_contributors_of_a_factor_that_the_design_sample_loses_are_hidden_with_its_levels() -> (  # noqa: E501
    None
):
    # Crossed factors f and g: 40 analysed rows in 20 levels of f and 22 of
    # g, and 20 rows without an outcome in 10 more levels of f and 9 more of
    # g. The design sample loses the levels of g, 31 beside 22 analysed, and
    # keeps those of f, 30 beside 20, so that written contributors of 30, the
    # levels of f, would show that g has more than 30 levels.
    f = [
        *labels("f%02d", range(1, 11)),
        *rep(labels("f%02d", range(11, 21)), each=3),
        *rep(labels("f%02d", range(21, 31)), each=2),
    ]
    g = [
        *labels("g%02d", range(1, 13)),
        *rep(labels("g%02d", range(13, 21)), each=3),
        *rep(labels("g%02d", range(21, 23)), each=2),
        *[f"g{23 + i % 9:02d}" for i in range(20)],
    ]
    data = frame(
        count=[i % 4 for i in seq_len(40)] + [None] * 20,
        x=[i % 7 + 0.5 for i in seq_len(60)],
        f=f,
        g=g,
    )
    found = audit_both(data, "count ~ x + (1 | f) + (1 | g)", **T1_ZEROS)
    internal = finding_of(found["internal"], "structure.cluster_sizes", factor="g")
    assert written(internal, "contributors") == 30
    sizes = finding_of(found["shareable"], "structure.cluster_sizes", factor="g")
    assert detail(sizes, "levels") == "secondary"
    assert support_detail(sizes, "distinct") == "secondary"
    zeros = finding_of(found["shareable"], "outcome.zero_shares", factor="g")
    assert written(zeros, "levels") == 22


def test_part_of_reads_the_parts_that_steps_1_to_5_leave_written() -> None:
    # 30 rows of 22 subjects: 8 subjects have two rows of the same trial, 9
    # one row and 5 one row without a trial. The total of 30 rows less the
    # 16 duplicate rows, the only part that step 3 leaves written, is 14, so
    # duplicate_rows stays, although 30 - 5 - 16 is below k.
    data = frame(
        y=[i % 7 + 0.5 for i in seq_len(30)],
        subject=rep(labels("s%02d", range(1, 9)), each=2) + labels("s%02d", range(9, 23)),
        trial=[1] * 25 + [None] * 5,
    )
    declaration = subject_declaration(observation={"key": ["subject", "trial"]})
    found = audit_both(data, "y ~ 1 + (1 | subject)", declaration=declaration)
    internal = finding_of(found["internal"], "keys.duplicates")
    assert written(internal, "rows") == 30
    assert written(internal, "missing_key_rows") == 5
    assert written(internal, "duplicate_rows") == 16
    keys = finding_of(found["shareable"], "keys.duplicates")
    assert written(keys, "duplicate_rows") == 16
    assert detail(keys, "missing_key_rows") is not None


def test_rule_4_compares_the_rows_without_a_key_value_only_with_rows_nested_with_them() -> None:
    # 20 subjects of three trials: 12 rows lack their trial and 12 other rows
    # lack x, so that neither set of rows holds the other, and the 12 rows
    # without a key value give back nothing about the 12 that x removes.
    data = frame(
        y=[i % 7 + 0.5 for i in seq_len(60)],
        x=[None if 25 <= i <= 36 else i % 5 + 0.25 for i in seq_len(60)],
        subject=rep(labels("s%02d", range(1, 21)), each=3),
        trial=[None] * 12 + rep([1, 2, 3], 20)[12:],
    )
    declaration = subject_declaration(observation={"key": ["subject", "trial"]})
    found = audit_both(data, "y ~ x + (1 | subject)", declaration=declaration)
    keys = finding_of(found["shareable"], "keys.duplicates")
    assert written(keys, "missing_key_rows") == 12
    dropped = finding_of(found["shareable"], "sample.raw_vs_analysis")
    assert written(dropped, "rows_dropped") == 12


def test_the_written_quantiles_of_the_level_sizes_raise_the_rows_that_rule_3_requires() -> None:
    # Registry 0.1.0 writes no quantile of level sizes on the analysis
    # sample, so these helpers of rule 3 are called directly.
    assert quantile_position(12, "0") == 1
    assert quantile_position(12, "1") == 12
    assert quantile_position(12, "0.25") == 3
    assert quantile_position(12, "0.5") == 6
    assert quantile_position(12, "0.333") == 4
    assert quantile_position(3, "0.25") == 1
    assert privacy_rows_without_singletons(12, []) == 24
    # A written median of 3 raises the sizes from position 6 on to 3, and an
    # upper quartile of 4 those from position 9 on to 4.
    assert privacy_rows_without_singletons(12, [("0.5", 3)]) == 31
    assert privacy_rows_without_singletons(12, [("0.5", 3), ("0.75", 4)]) == 35
    analysis = SampleQuantities(30, 12, [ItemQuantities(True, 12, 9, 3)])
    design = SampleQuantities(40, 12, [ItemQuantities(True, 12, 12, 0)])

    def marks() -> SampleMarks:
        blank = privacy_blank_marks({"analysis": analysis})["analysis"]
        blank.items[0]["levels_with_one_row"] = True
        return blank

    # 30 rows of 12 levels can have no level of one row, but not with a
    # written median of 3, which needs 31.
    assert not privacy_rule_3(analysis, design, marks(), [], 10).items[0]["levels"]
    quartiles: list[tuple[int | None, list[tuple[str, int]]]] = [(0, [("0.5", 3)])]
    assert privacy_rule_3(analysis, design, marks(), quartiles, 10).items[0]["levels"]


def test_an_absent_internal_only_by_unit_count_is_written_as_a_suppressed_person_count() -> None:
    # No internal_only statistic of registry 0.1.0 is a by_unit count, so
    # privacy_absent() is called on an entry that has one.
    entry = {
        "statistics": {
            "hidden": {"kind": "count", "count_class": "by_unit", "internal_only": True},
            "shown": {"kind": "count", "count_class": "non_person"},
        }
    }
    finding = Finding(
        check="test.check",
        check_version=1,
        tier="T0",
        scope={},
        available=True,
        entry=entry,
        values={"shown": 3},
        statistics={"shown": {"kind": "count", "count_class": "non_person"}},
    )
    out = privacy_absent(finding)
    assert out.statistics["hidden"] == {"kind": "count", "count_class": "person"}
    assert out.suppressed["hidden"] == "internal_only"


# --- Pseudonyms -------------------------------------------------------------------------


def labels_entry() -> dict[str, Any]:
    """A check whose findings write labels, which registry 0.1.0 does not
    have."""
    return {
        "id": "structure.flagged_levels",
        "version": 1,
        "tier": "T0",
        "sample": "design",
        "scope": "grouping_factor",
        "statistics": {
            "flagged": {"kind": "labels"},
            "flagged_levels": {"kind": "count", "count_class": "person"},
        },
        "decision": {
            "rules": [
                {
                    "finding": "detectable_inconsequential",
                    "statistics": ["flagged"],
                    "thresholds": [],
                    "message": "listed",
                }
            ],
            "otherwise": {"finding": "consistent", "message": "listed"},
        },
        "assessability": [],
        "messages": {
            "listed": {
                "template": "Flagged levels of '{factor}': {flagged}.",
                "fallback": "Some levels of '{factor}' are flagged.",
                "args": {
                    "factor": {"source": "scope", "name": "factor"},
                    "flagged": {"source": "statistic", "name": "flagged"},
                },
            }
        },
    }


def labels_finding(factor: str, values: list[str], distinct: int = 50) -> Finding:
    """An internal finding of that check, as the filter receives it after
    step 9."""
    finding = Finding(
        check="structure.flagged_levels",
        check_version=1,
        tier="T0",
        scope={"factor": factor},
        available=True,
        status={
            "assessability": {"value": "adequate"},
            "finding": {"value": "detectable_inconsequential"},
            "threshold_proximity": {"value": "clear"},
            "validation": {"value": "descriptive"},
        },
        message={"id": "listed", "text": ""},
        statistics={
            "flagged": {"kind": "labels"},
            "flagged_levels": {"kind": "count", "count_class": "person"},
        },
        values={"flagged": list(values), "flagged_levels": 12},
        support=Support(200, "grouping_factors", distinct, False, {}),
        items={},
        rows=np.arange(200),
        entry=labels_entry(),
        rule=0,
        label_factors={"flagged": factor},
    )
    return privacy_minimum_rules(finding, 10)


def test_pseudonyms_follow_the_hmac_of_the_factor_and_the_label_as_privacy_md_shows() -> None:
    digest = hmac_sha256(
        commitment_key_bytes(PRIVACY_KEY), canonical_bytes(["school", "A"], "data")
    )
    assert digest == "40ad110dcd8fe9389548ba9f7881f4f4865ceb7d1fa9dc216b4b5dfae0a2d0bb"
    findings = [labels_finding("school", ["B", "A"]), labels_finding("school", ["C", "A"])]
    pseudonyms = privacy_pseudonyms(findings, PRIVACY_KEY)
    assert [p["label"] for p in pseudonyms] == ["C", "A", "B"]
    assert [p["pseudonym"] for p in pseudonyms] == ["#1", "#2", "#3"]
    rendered = [privacy_render(finding, pseudonyms) for finding in findings]
    # The same label gets the same pseudonym in every finding, and the
    # numbers follow neither the labels nor the findings.
    assert rendered[0].values["flagged"] == ["#3", "#2"]
    assert rendered[1].values["flagged"] == ["#1", "#2"]
    assert rendered[0].message is not None
    assert rendered[0].message["text"] == "Flagged levels of 'school': '#3' and '#2'."
    document = document_finding(rendered[0])
    assert document["statistics"]["flagged"]["value"] == ["#3", "#2"]
    assert shareable_finding_issues(document, "/findings/0", 10) == []
    # The same label of two factors gets two pseudonyms.
    findings = [labels_finding("school", ["A"]), labels_finding("class", ["A"])]
    pseudonyms = privacy_pseudonyms(findings, PRIVACY_KEY)
    assert len(pseudonyms) == 2
    assert {p["factor"] for p in pseudonyms} == {"school", "class"}


def test_labels_of_a_finding_that_fails_the_minimum_count_rule_get_no_pseudonym() -> None:
    finding = labels_finding("school", ["A", "B"], distinct=4)
    assert finding.suppressed["flagged"] == "min_count_rule"
    pseudonyms = privacy_pseudonyms([finding], PRIVACY_KEY)
    assert pseudonyms == []
    rendered = privacy_render(finding, pseudonyms)
    assert rendered.message is not None
    assert rendered.message["text"] == "Some levels of 'school' are flagged."
    document = document_finding(rendered)
    assert document["statistics"]["flagged"]["value"] is None
    assert document["statistics"]["flagged"]["availability"]["detail"] == "min_count_rule"


def test_a_check_that_writes_labels_must_name_their_factor() -> None:
    element = check_element({"flagged": ["A", "B"], "flagged_levels": 12}, rules=[True])
    with pytest.raises(RuntimeError, match="gave no factor for the labels"):
        assemble_finding(None, labels_entry(), {"factor": "school"}, element)  # type: ignore[arg-type]


def test_the_ir_hash_of_a_shareable_document_leaves_out_the_constants_of_mean_centrings() -> None:
    declaration = units(
        table={"fields": [{"name": "y", "type": "number"}, {"name": "x", "type": "number"}]}
    )
    data = frame(y=[1.0, 2, 3, 4], x=[1.0, 2, 4, 8])
    coding = {"x": {"centring": "mean", "significant_digits": 4}}
    found = audit_both(data, "y ~ x", declaration=declaration, coding=coding)
    # The shareable document hashes the IR as it is before the data are seen.
    before = formula_ir("y ~ x", declaration, coding=coding)
    assert "constant" not in before["predictors"]["x"]["centring"]
    assert found["shareable"]["inputs"]["model"]["ir_hash"] == canonical_hash(before, "hashable")
    after = formula_ir("y ~ x", declaration, data, coding=coding)
    assert after["predictors"]["x"]["centring"]["constant"]["value"] == "3.75"
    assert found["internal"]["inputs"]["model"]["ir_hash"] == canonical_hash(after, "hashable")
