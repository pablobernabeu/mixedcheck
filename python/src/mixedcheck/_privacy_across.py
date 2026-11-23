"""Step 7 of the privacy filter, the rules across findings (docs/spec/privacy.md,
Across findings). They compare the quantities of the samples that the findings
of a document read: the table, the design sample, the analysis sample when the
run read the outcome and the rows that an available finding reads when they
are not its entry's sample, the rows of an assignment or of a pair of columns,
which are the design sample, or else the analysis sample, when they hold its
rows, and one sample when two findings read the same rows. The quantities of a
sample are its rows, its contributors and, for each item, its levels, its
levels with at least two rows and its levels with one row. The marks of a
sample record which of them the document hides. Each rule suppresses the
counts that measure a hidden quantity with the detail 'secondary', which
replaces the detail 'min_count' of a count below k.

The rules run in this order. The clauses at the end of rule 1, under which the
analysis sample loses a value, and rules 2 and 3 apply to the analysis sample
first, and steps 6, 8 and 9 to the findings on it, which decides whether the
analysis sample is shown. Before that, privacy_crossed_guarded() names the
items of crossed columns whose findings of the T1 and T2 checks step 9
suppresses as a whole. Rule 1 then compares the other samples with the
analysis sample when it is shown, the sizes of the levels that keep an
analysed row included, and they lose what the analysis sample loses. Rule 5
extends what they lose there, the chain clause of rule 1 compares with the
analysis sample the samples that a losing sample would have been compared
with, rule 1 compares the other samples with one another, rule 2 applies to
every sample and each finding takes the marks of its samples, rule 4, rule 5
and rule 6.

The functions have the names of their counterparts in the R package's
privacy-across.R. Items are numbered from 0, and an item that the rules do not
compare is None where R has NA.
"""

from __future__ import annotations

import copy
import dataclasses
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Literal

from mixedcheck._checks import (
    Finding,
    Run,
    declared_units,
    factor_keys,
    first_codes,
    pair_codes,
    resolve_count_class,
    rows_support,
    sample_rows,
    tabulate,
    unit_label_columns,
    value_codes,
)
from mixedcheck._commitments import observation_key_columns
from mixedcheck._privacy import (
    entry_statistics,
    privacy_absent,
    privacy_decision,
    privacy_person,
    privacy_suppress,
    privacy_within,
    privacy_written,
)
from mixedcheck._registry import registry_document
from mixedcheck._unicode import comparison_form

if TYPE_CHECKING:
    from mixedcheck._checks import Array

# The quantities of a sample: its rows, its contributors and, for each item,
# the quantities that measures names.
Quantity = Literal["rows", "contributors", "levels", "levels_with_two_rows", "levels_with_one_row"]

# The quantities of a sample other than those of its items.
SAMPLE_MEMBERS: tuple[Quantity, ...] = ("rows", "contributors")

# The quantities of an item that measures names.
PRIVACY_MEASURES: tuple[Quantity, ...] = ("levels", "levels_with_two_rows", "levels_with_one_row")

# The values of measures that mark a count of columns, which gives back the
# levels of the items of its terms with an offset and which rule 6 alone
# suppresses.
PRIVACY_TERM_MEASURES = ("term_levels", "table_term_levels")

# The samples whose rows the values of measures for rows count.
ROWS_MEASURES = {"table_rows": "table", "design_rows": "design", "analysis_rows": "analysis"}


@dataclass
class ItemQuantities:
    """The quantities of an item in some rows: whether its counts of levels
    resolve as person counts there, its levels, those with at least two rows
    and those with one row."""

    person: bool
    levels: int
    levels_with_two_rows: int
    levels_with_one_row: int


@dataclass
class SampleQuantities:
    """The quantities of a sample: its rows, its contributors and those of each
    item, by the item's position."""

    rows: int
    contributors: int
    items: list[ItemQuantities]


@dataclass
class SampleMarks:
    """The quantities of a sample that the document hides: its rows, its
    contributors and, for each item by its position, each measure of
    PRIVACY_MEASURES."""

    rows: bool = False
    contributors: bool = False
    items: list[dict[str, bool]] = field(default_factory=list)


@dataclass
class Comparison:
    """A comparison of rule 1: the larger and the smaller sample, by name, and
    the one that loses its value."""

    larger: str
    smaller: str
    loser: str


@dataclass
class WrittenItem:
    """An item whose levels a sample writes whatever rule 1 hides: its
    position and the two samples compared, the larger and the smaller."""

    item: int
    larger: str
    smaller: str


def privacy_across(run: Run, findings: list[Finding], k: int) -> list[Finding]:
    """Step 7: the rules across findings, applied to the available findings of
    a run."""
    import numpy as np

    if not any(finding.available for finding in findings):
        return findings
    samples: dict[str, Array] = {"table": sample_rows(run, "table"), "design": run.design}
    if run.analysis is not None:
        samples["analysis"] = run.analysis
    main = list(samples)
    finding_samples = [""] * len(findings)
    for i, finding in enumerate(findings):
        if not finding.available:
            continue
        assert finding.entry is not None and finding.rows is not None
        sample: str = finding.entry["sample"]
        if not same_rows(finding.rows, samples[sample]):
            same = [name for name, rows in samples.items() if same_rows(rows, finding.rows)]
            sample = same[0] if same else f"rows {len(samples)}"
            samples[sample] = finding.rows
        finding_samples[i] = sample
    available = [finding for finding in findings if finding.available]
    available_samples = [s for f, s in zip(findings, finding_samples, strict=True) if f.available]
    items = privacy_items(run, available)
    quantities = {
        name: SampleQuantities(
            rows=len(rows),
            contributors=rows_support(run, rows).distinct,
            items=[privacy_item_quantities(run, codes, rows) for codes in items],
        )
        for name, rows in samples.items()
    }
    # The items that the contributors count: the grouping factors with the
    # basis grouping_factors and the disclosure unit with the basis
    # disclosure_unit.
    basis = rows_support(run, samples["table"]).basis
    factor_items = [
        privacy_item_index(items, [value_codes(run, keys)]) for keys in run.factors.values()
    ]
    unit_item = (
        None if run.disclosure is None else privacy_item_index(items, [run.disclosure.codes])
    )
    comparisons = privacy_comparisons(samples, main)
    written = privacy_written_items(run, available, available_samples, items, comparisons, samples)
    marks = privacy_blank_marks(quantities)
    shown = False
    if "analysis" in samples:
        holders = [
            s
            for s in samples
            if s != "analysis" and bool(np.isin(samples["analysis"], samples[s]).all())
        ]
        marks["analysis"] = privacy_analysis_marks(
            available,
            available_samples,
            run,
            items,
            quantities,
            written,
            holders,
            basis,
            unit_item,
            k,
        )
        guarded = privacy_crossed_guarded(
            run, available, available_samples, items, samples, quantities, k
        )
        for finding in available:
            finding.guarded = (
                finding.tier in ("T1", "T2")
                and "factor" in finding.scope
                and privacy_item_index(items, privacy_scope_item(run, finding)) in guarded
            )
        on_analysis = [
            finding
            for finding, s in zip(available, available_samples, strict=True)
            if s == "analysis"
        ]
        probes = []
        for finding in on_analysis:
            probe = finding_copy(finding)
            privacy_across_finding(
                run, probe, "analysis", items, factor_items, unit_item, quantities, marks, k
            )
            probes.append(privacy_absent(privacy_within(probe, k)))
        # The findings on the analysis sample share its rows and contributors,
        # so the bound that their written values place on the contributors
        # decides for all of them (privacy.md, Decisions).
        bounded = privacy_contributors_bound(run, probes) >= k - 1
        for finding in on_analysis:
            finding.bounded = bounded
        for probe in probes:
            probe.bounded = bounded
            privacy_decision(probe, run, k)
            shown = shown or not probe.whole
    beside = ["analysis" in (comparison.larger, comparison.smaller) for comparison in comparisons]
    others = [c for c, near in zip(comparisons, beside, strict=True) if not near]
    # Rule 1 between the samples other than the analysis sample, as in a
    # document that does not show it, and the items whose levels a count
    # measures in each sample, which rule 6 reads.
    structural = privacy_rule_1(
        quantities, others, privacy_blank_marks(quantities), privacy_blank_marks(quantities), k
    )
    measured = privacy_measured_items(run, available, available_samples, items, k)
    lost = privacy_lost(
        samples,
        quantities,
        comparisons,
        beside,
        shown,
        items,
        written,
        marks.get("analysis"),
        factor_items,
        unit_item,
        basis,
        privacy_names_bound(run, available),
        k,
    )
    marks = privacy_rule_1(quantities, others, lost, marks, k)
    for s in marks:
        marks[s] = privacy_or_marks(marks[s], lost[s])
        if s != "analysis":
            marks[s] = privacy_rule_2(quantities[s], marks[s], k)
    # Rule 6 reads the marks of rule 1 between the samples other than the
    # analysis sample alone for those samples, and the final marks for the
    # analysis sample.
    ruled = dict(structural)
    if "analysis" in samples:
        ruled["analysis"] = marks["analysis"]
    # Rule 4 compares the analysis sample only when it is shown, and no sample
    # that loses its rows beside it.
    keyed = [
        samples[s]
        for s in samples
        if s != "table" and (s != "analysis" or shown) and not lost[s].rows
    ]
    for i, finding in enumerate(findings):
        if not finding.available:
            continue
        s = finding_samples[i]
        privacy_across_finding(
            run, finding, s, items, factor_items, unit_item, quantities, marks, k
        )
        if finding.check == "keys.duplicates" and privacy_missing_key_close(run, keyed, k):
            privacy_suppress(finding, ["missing_key_rows"], "secondary", replace=True)
        if s != "analysis":
            privacy_rule_5(run, finding, items, lost[s])
        privacy_rule_6(
            run,
            finding,
            s,
            samples,
            items,
            quantities,
            measured,
            ruled,
            k,
        )
    return findings


def same_rows(a: Array, b: Array) -> bool:
    """Whether two vectors of rows hold the same rows in the same order."""
    import numpy as np

    return len(a) == len(b) and bool(np.array_equal(a, b))


def finding_copy(finding: Finding) -> Finding:
    """A copy of a finding whose marks and statistics can change without
    changing the finding."""
    return dataclasses.replace(
        finding,
        statistics=dict(finding.statistics),
        suppressed=dict(finding.suppressed),
        support_suppressed=dict(finding.support_suppressed),
    )


# --- Marks ------------------------------------------------------------------------------


def privacy_blank_marks(quantities: dict[str, SampleQuantities]) -> dict[str, SampleMarks]:
    """The marks of every sample with no quantity hidden."""
    return {name: blank_sample_marks(sample) for name, sample in quantities.items()}


def blank_sample_marks(sample: SampleQuantities) -> SampleMarks:
    """The marks of one sample with no quantity hidden."""
    return SampleMarks(
        items=[dict.fromkeys(PRIVACY_MEASURES, False) for _ in sample.items],
    )


def privacy_or_marks(a: SampleMarks, b: SampleMarks) -> SampleMarks:
    """The marks of one sample that hide what either of two marks hides."""
    return SampleMarks(
        rows=a.rows or b.rows,
        contributors=a.contributors or b.contributors,
        items=[
            {measure: x[measure] or y[measure] for measure in PRIVACY_MEASURES}
            for x, y in zip(a.items, b.items, strict=True)
        ],
    )


def privacy_close(a: int, b: int, k: int) -> bool:
    """Whether a quantity a of the larger of two samples exceeds the quantity b
    of the smaller by fewer than k, 0 included. A quantity that is 0 in the
    larger sample is not compared, since the difference is then 0 whatever
    the data."""
    return a > 0 and a - b >= 0 and a - b < k


def privacy_quantity(quantity: SampleQuantities, member: Quantity, item: int | None = None) -> int:
    """The value of a quantity of a sample, the rows or the contributors when
    item is None, and otherwise the measure of the item at that position."""
    if item is not None:
        return item_quantity(quantity.items[item], member)
    if member == "rows":
        return quantity.rows
    if member == "contributors":
        return quantity.contributors
    raise ValueError(member)


def item_quantity(item: ItemQuantities, measure: Quantity) -> int:
    """The value of a measure of the quantities of an item."""
    if measure == "levels":
        return item.levels
    if measure == "levels_with_two_rows":
        return item.levels_with_two_rows
    if measure == "levels_with_one_row":
        return item.levels_with_one_row
    raise ValueError(measure)


def marked(marks: SampleMarks, member: Quantity, item: int | None = None) -> bool:
    """Whether marks hide a quantity, the rows or the contributors when item
    is None, and otherwise the measure of the item at that position."""
    if item is not None:
        return marks.items[item][member]
    if member == "rows":
        return marks.rows
    if member == "contributors":
        return marks.contributors
    raise ValueError(member)


def mark(marks: SampleMarks, member: Quantity, item: int | None = None) -> None:
    """Hide a quantity in marks, as marked() names it."""
    if item is not None:
        marks.items[item][member] = True
    elif member == "rows":
        marks.rows = True
    elif member == "contributors":
        marks.contributors = True
    else:
        raise ValueError(member)


# --- The analysis sample ----------------------------------------------------------------


def privacy_analysis_marks(
    findings: list[Finding],
    finding_samples: list[str],
    run: Run,
    items: list[Array],
    quantities: dict[str, SampleQuantities],
    written: list[WrittenItem],
    holders: list[str],
    basis: str,
    unit_item: int | None,
    k: int,
) -> SampleMarks:
    """The marks of the analysis sample: the clauses at the end of rule 1,
    under which it loses a value, then rules 2 and 3. They compare quantities
    that the run computes whether or not the analysis sample is shown, so that
    the findings on it are final before step 7 decides whether it is shown.

    ``written`` lists the items whose levels a sample beside the analysis
    sample writes whatever rule 1 hides, by privacy_written_items(). Since
    rule 1 cannot hide those levels, the analysis sample loses its levels of
    such an item when the other sample's exceed them by fewer than k. The
    written levels also bound the rows of the other sample from below, by
    twice the levels of an item that resolves as non-person there and by the
    levels otherwise, and with the basis disclosure_unit its contributors by
    twice the levels of a non-person item, so the analysis sample loses its
    rows, or its contributors, when the other sample's exceed them by fewer
    than k and that bound exceeds them. The levels with two rows that the
    written levels and rows of the other sample bound from above are protected
    by the sizes of the levels in privacy_lost(). With the basis
    disclosure_unit, the contributors are the levels of the disclosure unit, at
    ``unit_item``, which the analysis sample loses with them.

    Each level of an item whose counts resolve as non-person in a sample holds
    two members or more, so that the rows of the sample, and with the basis
    disclosure_unit its contributors, are at least twice its levels, which the
    analysed levels bound from below. ``holders`` names the samples that hold
    the analysis sample's rows. Of their rows and contributors, those that
    exceed the analysis sample's by k or more, which rule 1 does not hide
    beside it, bound the levels that lose every outcome, and the analysis
    sample loses its levels of such an item when the fewer of them exceeds
    twice those levels by fewer than k, since they would then confine the
    levels that lose every outcome to fewer than k / 2 values, a single one
    when every level holds two members."""
    analysis = quantities["analysis"]
    marks = blank_sample_marks(analysis)
    for w in written:
        if w.smaller != "analysis" and w.larger != "analysis":
            continue
        i = w.item
        larger = quantities[w.larger]
        smaller = quantities[w.smaller]
        if privacy_close(larger.items[i].levels, smaller.items[i].levels, k):
            marks.items[i]["levels"] = True
        if w.smaller != "analysis":
            continue
        item = larger.items[i]
        least = item.levels * (1 if item.person else 2)
        if privacy_close(larger.rows, analysis.rows, k) and least > analysis.rows:
            marks.rows = True
        if (
            basis == "disclosure_unit"
            and not item.person
            and privacy_close(larger.contributors, analysis.contributors, k)
            and least > analysis.contributors
        ):
            marks.contributors = True
    for s in holders:
        other = quantities[s]
        members = [other.rows] if other.rows - analysis.rows >= k else []
        if basis == "disclosure_unit" and other.contributors - analysis.contributors >= k:
            members.append(other.contributors)
        if not members:
            continue
        for i, item in enumerate(other.items):
            if not item.person and min(members) - 2 * analysis.items[i].levels < k:
                marks.items[i]["levels"] = True
    if privacy_close(privacy_key_bound(run, findings, k), analysis.rows, k):
        marks.rows = True
    if marks.contributors and basis == "disclosure_unit" and unit_item is not None:
        marks.items[unit_item]["levels"] = True
    quartiles: list[tuple[int | None, list[tuple[str, int]]]] = []
    for finding, sample in zip(findings, finding_samples, strict=True):
        if finding.check == "structure.cluster_sizes" and sample == "analysis":
            quartiles.append(
                (
                    privacy_item_index(items, privacy_scope_item(run, finding)),
                    privacy_written_quantiles(finding),
                )
            )
    design = quantities["design"]
    marks = privacy_single_row_items(design, marks, basis, unit_item)
    marks = privacy_rule_3(analysis, design, privacy_rule_2(analysis, marks, k), quartiles, k)
    marks = privacy_rule_3_bound(analysis, quantities, holders, marks, quartiles, basis, k)
    return privacy_rule_2(analysis, privacy_single_row_items(design, marks, basis, unit_item), k)


def privacy_rule_3_bound(
    analysis: SampleQuantities,
    quantities: dict[str, SampleQuantities],
    holders: list[str],
    marks: SampleMarks,
    quartiles: list[tuple[int | None, list[tuple[str, int]]]],
    basis: str,
    k: int,
) -> SampleMarks:
    """The end of rule 3: its firing on an item shows that the analysed rows
    fall short of the fewest rows that the item's analysed levels can hold
    without a level of one row, so that those levels number at least the
    fewest J for which that floor exceeds the analysed rows. In a sample that
    holds the analysis sample's rows and in which the item resolves as
    non-person, each of those levels holds two rows or more, so that its rows
    are at least 2J, and with the basis disclosure_unit its contributors too.
    Rule 1 hiding that sample's rows beside the analysis sample shows them
    below the analysed rows plus k, so when 2J equals the analysed rows plus
    k - 1, or rule 1 hides its contributors and 2J equals the analysed
    contributors plus k - 1, the firing of rule 3 would leave the rows or
    members without an outcome a single value. A bound above that would
    contradict the firing of rule 1, so that the item cannot be non-person
    there, as its class shows anyway. The analysis sample then loses its levels
    of the item whether or not rule 3 fires, and whatever the item's class in
    the other sample, so that the loss shows neither, since J depends only on
    the analysed rows and the written quantiles. For the rows, 2J exceeds the
    analysed rows by at most 2, so only at k = 3: 5 schools of two pupils, 2 of
    whom lack the outcome, give 8 analysed rows, whose 5 analysed schools rule
    3 hides, which beside the class non_person of the schools of the design
    sample would show 10 rows there. The contributors can meet the bound at any
    k when members hold several rows: 50 schools of 99 analysed rows and 91
    analysed pupils, at k = 10, would show 100 pupils in the design sample.
    ``marks`` holds the levels with one row that rule 2 hides, which rule 3
    reads."""
    design = quantities["design"]
    for i, item in enumerate(analysis.items):
        if (
            not item.person
            or not marks.items[i]["levels_with_one_row"]
            or design.items[i].levels_with_two_rows == 0
        ):
            continue
        written: list[tuple[str, int]] = []
        for position, quantiles in quartiles:
            if position == i:
                written = quantiles
        least = 1
        while privacy_rows_without_singletons(least, written) <= analysis.rows:
            least += 1
        bound = 2 * least
        for s in holders:
            other = quantities[s]
            if (privacy_close(other.rows, analysis.rows, k) and bound == analysis.rows + k - 1) or (
                basis == "disclosure_unit"
                and privacy_close(other.contributors, analysis.contributors, k)
                and bound == analysis.contributors + k - 1
            ):
                marks.items[i]["levels"] = True
    return marks


def privacy_key_bound(run: Run, findings: list[Finding], k: int) -> int:
    """The bound that a declared observation key places on the rows of the
    design sample, or 0 when keys.duplicates does not run, or when a column of
    the key is none whose levels the document or the declaration can give
    (privacy_bounded_columns()). The design sample holds at most as many
    distinct key values as the product of the levels of the key's columns
    there, and its rows exceed its distinct key values by its rows with a key
    value that repeat one, which duplicate_rows less duplicated_keys of
    keys.duplicates bound in the table, and by its rows without a key value,
    which missing_key_rows bounds. Beside the firing of rule 1, which shows
    fewer than k rows without an outcome, the levels of crossed columns that
    it shows to have kept an outcome, a column's declared categories, the two
    values of a column declared boolean or the columns of a fixed factor can
    give that product, which beside the analysed rows would give back the rows
    without an outcome (privacy.md, Across findings, the end of rule 1). The
    bound counts the repeated rows and the rows without a key value of the
    design sample, no more than those that the written counts of the table
    bound, so that it comes within k of the analysed rows wherever theirs
    does. A column other than a predictor or a column whose levels the
    declaration gives (privacy_declared_level_columns()) that has a level of
    fewer than k rows of the design sample, as the label of a pupil of two
    rows does, also gives 0: beside the firing of rule 1 such a level may have
    lost every outcome, so its analysed levels do not give its levels there,
    which rule 1 hides as the levels of an item, or no count writes, wherever
    the bound would come within k of the analysed rows."""
    import numpy as np

    if not any(finding.check == "keys.duplicates" and finding.available for finding in findings):
        return 0
    key = [comparison_form(column) for column in observation_key_columns(run.declaration)]
    if not set(key) <= privacy_bounded_columns(run):
        return 0
    given = set(run.ir["predictors"]) | privacy_declared_level_columns(run.declaration)
    bound = 1
    for column in key:
        codes = value_codes(run, [column], run.design)
        sizes = np.unique(codes[codes >= 0], return_counts=True)[1]
        if column not in given and (sizes.size == 0 or int(np.min(sizes)) < k):
            return 0
        bound *= int(sizes.size)
    codes = value_codes(run, key, run.design)
    keyed = codes[codes >= 0]
    return bound + int(keyed.size) - int(np.unique(keyed).size) + int((codes < 0).sum())


def privacy_bounded_columns(run: Run) -> set[str]:
    """The columns whose levels in the design sample the document or the
    declaration can give: the predictors and grouping columns of the IR, the
    label columns of the declared units and the columns whose levels the
    declaration gives (privacy_declared_level_columns()), as keys."""
    declaration = run.declaration
    columns = set(run.ir["predictors"]) | set(run.grouping_columns)
    for name in declared_units(declaration):
        columns.update(unit_label_columns(declaration, name))
    return columns | privacy_declared_level_columns(declaration)


def privacy_declared_level_columns(declaration: dict[str, Any] | None) -> set[str]:
    """The columns of the table block whose levels the declaration gives,
    those with declared categories, which the table reader and audit() keep
    within them whether or not the formula reads the column, and those of type
    'boolean', which hold the values false and true alone (tables.md), as
    keys."""
    table = (declaration or {}).get("table") or {}
    return {
        comparison_form(entry["name"])
        for entry in table.get("fields") or []
        if entry.get("categories") is not None or entry.get("type") == "boolean"
    }


def privacy_crossed_guarded(
    run: Run,
    findings: list[Finding],
    finding_samples: list[str],
    items: list[Array],
    samples: dict[str, Array],
    quantities: dict[str, SampleQuantities],
    k: int,
) -> list[int]:
    """The items of two crossed columns whose findings of the T1 and T2 checks
    step 9 suppresses as a whole (privacy.md, Decisions). When
    structure.label_incidence finds two columns crossed in the rows that it
    reads, those of the design sample in which both columns are present, each
    level of one column's item holds every level of the other's there. When
    the item's counts resolve as non-person there and some level of it would
    keep at most one member after losing fewer than k of its rows, the class
    person of its counts in the analysis sample, which a finding suppressed as
    a whole by Decisions shows, would bound from below the rows without an
    outcome in that level, which rule 1 can show to be fewer than k. The
    conditions read no outcome."""
    guarded: list[int] = []
    if "analysis" not in samples or run.disclosure is None:
        return guarded
    for finding, sample in zip(findings, finding_samples, strict=True):
        if (
            finding.check != "structure.label_incidence"
            or finding.values.get("relation") != "crossed"
        ):
            continue
        for codes in finding.items.get("combinations", []):
            a = privacy_item_index(items, [codes])
            if (
                a is not None
                and a not in guarded
                and not quantities[sample].items[a].person
                and privacy_reducible(items[a], run.disclosure.codes, samples[sample], k)
            ):
                guarded.append(a)
    return guarded


def privacy_reducible(codes: Array, members: Array, rows: Array, k: int) -> bool:
    """Whether some level of an item, in the rows given, would hold at most one
    member of the disclosure unit after losing fewer than k of its rows: its
    rows less those of its member with the most rows there and less those
    without a member number fewer than k. ``codes`` are the level codes of the
    item and ``members`` the codes of the members, -1 for none, in every row
    of the table."""
    import numpy as np

    level = codes[rows]
    member = members[rows]
    keep = level >= 0
    level = level[keep]
    member = member[keep]
    if not len(level):
        return False
    bins = int(level.max()) + 1
    sizes = np.bincount(level, minlength=bins)
    labelled = member >= 0
    most = np.zeros(bins, dtype=np.int64)
    if labelled.any():
        # The rows of each pair of a level and a member, and the largest of
        # them in each level.
        pairs, counts = np.unique(
            np.stack([level[labelled], member[labelled]]), axis=1, return_counts=True
        )
        np.maximum.at(most, pairs[0], counts)
    unlabelled = np.bincount(level[~labelled], minlength=bins)
    removal = sizes - most - unlabelled
    return bool(((sizes > 0) & (removal < k)).any())


def privacy_contributors_bound(run: Run, findings: list[Finding]) -> int:
    """The lower bound that the findings on the analysis sample place on its
    contributors (privacy.md, Decisions): 2 when a by_unit count or ratio
    resolves as non-person over rows that hold a level of its item, since each
    level then holds two members or more, twice the largest written by_unit
    count of class non_person whose item holds each member of the disclosure
    unit in one level of the design sample, and dominance.contributors + 1
    when ``dominated`` of a finding whose support counts the analysis sample
    is false, 0 without any of these."""
    bound = 0
    dominance = int(registry_document()["privacy"]["dominance"]["contributors"])
    for finding in findings:
        assert finding.entry is not None and finding.support is not None
        if finding.entry["sample"] == "analysis" and not finding.support.dominated:
            bound = max(bound, dominance + 1)
        defined = entry_statistics(finding)
        for name in finding.values:
            statistic = finding.statistics[name]
            if (
                defined[name].get("count_class") != "by_unit"
                or statistic.get("count_class") != "non_person"
            ):
                continue
            item = finding.items.get(name)
            if item is None and "factor" in finding.scope:
                item = privacy_scope_item(run, finding)
            if item is None or any(codes is None for codes in item):
                continue
            assert finding.rows is not None
            codes = privacy_item_codes(item)
            if not (codes[finding.rows] >= 0).any():
                continue
            bound = max(bound, 2)
            if (
                statistic["kind"] == "count"
                and privacy_written(finding, name)
                and run.disclosure is not None
                and privacy_members_nested(codes, run.disclosure.codes, run.design)
            ):
                bound = max(bound, 2 * int(finding.values[name]))
    return bound


def privacy_members_nested(codes: Array, members: Array, rows: Array) -> bool:
    """Whether each member of the disclosure unit lies in one level of an item
    in the rows given, among the rows that hold both. ``codes`` and
    ``members`` are the codes of every row of the table, -1 for none."""
    import numpy as np

    level = codes[rows]
    member = members[rows]
    keep = (level >= 0) & (member >= 0)
    if not keep.any():
        return True
    pairs = np.unique(np.stack([member[keep], level[keep]]), axis=1)
    return bool(len(np.unique(pairs[0])) == pairs.shape[1])


def privacy_single_row_items(
    design: SampleQuantities, marks: SampleMarks, basis: str, unit_item: int | None
) -> SampleMarks:
    """The levels of an item none of whose levels holds two rows of the design
    sample are the analysis sample's rows whatever the outcome (rule 3 of
    Across findings), and with the basis disclosure_unit, when the item is the
    disclosure unit, its contributors too. So the analysis sample loses its
    rows when it loses its levels of such an item, or the contributors that
    count them, and it loses its levels of every such item, and the
    contributors that count them, when it loses its rows."""
    single = [
        i
        for i, item in enumerate(design.items)
        if item.levels > 0 and item.levels_with_two_rows == 0
    ]
    if not single:
        return marks
    unit = basis == "disclosure_unit" and unit_item is not None and unit_item in single
    if any(marks.items[i]["levels"] for i in single) or (unit and marks.contributors):
        marks.rows = True
    if marks.rows:
        for i in single:
            marks.items[i]["levels"] = True
        marks.contributors = marks.contributors or unit
    return marks


def privacy_written_items(
    run: Run,
    findings: list[Finding],
    finding_samples: list[str],
    items: list[Array],
    comparisons: list[Comparison],
    samples: dict[str, Array],
) -> list[WrittenItem]:
    """The items whose levels a sample writes whatever rule 1 hides, each with
    the two samples compared, the larger and the smaller, one of which is the
    analysis sample. A categorical variable of a term of the IR, or the
    combination of the categorical variables of a term, that divides the rows
    of the design sample, or of the table, into the levels of an item gives
    the term columns that count the item's levels there: in the design
    sample, which kept and empty_cells of design.rank_deficiency and df of
    design.collinearity count, and in the table, which columns of
    design.rank_deficiency and dimension of
    identifiability.levels_vs_dimension count, all of them non-person counts
    that no comparison with the analysis sample suppresses (rule 6 of Across
    findings). So does a fixed term on the rows of an assignment that hold the
    analysis sample's rows or lie in them, whose columns design_df of
    assignment.design_df counts there, and more generally a term of a count of
    columns, marked term_levels, of a finding on a sample other than these
    three. When structure.label_incidence finds two columns crossed in a
    sample, of which one holds the analysis sample's rows, the levels of their
    combinations there are the product of the levels of the two columns, which
    that sample writes or the analysis sample's bound from below."""
    written: list[WrittenItem] = []
    if not any("analysis" in (c.larger, c.smaller) for c in comparisons):
        return written

    def beside_analysis(sample: str) -> list[Comparison]:
        """Every pair of compared samples of which one is the analysis sample
        and the other the sample given."""
        return [c for c in comparisons if {c.larger, c.smaller} == {sample, "analysis"}]

    for larger in ("design", "table"):
        for i in privacy_variable_items(run, items, samples[larger]):
            written.append(WrittenItem(i, larger, "analysis"))
    for finding, sample in zip(findings, finding_samples, strict=True):
        if sample in ("table", "design", "analysis"):
            continue
        defined = entry_statistics(finding)
        if not any(defined[name].get("measures") == "term_levels" for name in finding.values):
            continue
        terms = privacy_finding_terms(run, finding)
        for i in privacy_term_items(run, items, terms, samples[sample]):
            for comparison in beside_analysis(sample):
                written.append(WrittenItem(i, comparison.larger, comparison.smaller))
    for finding, sample in zip(findings, finding_samples, strict=True):
        if (
            finding.check != "structure.label_incidence"
            or sample == "analysis"
            or finding.values.get("relation") != "crossed"
        ):
            continue
        crossed = privacy_item_index(items, finding.items.get("combinations"))
        if crossed is None:
            continue
        for comparison in beside_analysis(sample):
            written.append(WrittenItem(crossed, comparison.larger, comparison.smaller))
    return written


def privacy_variable_items(run: Run, items: list[Array], rows: Array) -> list[int]:
    """The items into whose levels a categorical variable of a term of the IR,
    in the fixed part or in a random term, or the combination of the
    categorical variables of a term, divides the rows given."""
    terms = list(run.ir["fixed"]["terms"])
    for random in run.ir["random"]:
        terms += random["terms"]
    return privacy_term_items(run, items, terms, rows)


def privacy_term_items(
    run: Run, items: list[Array], terms: Sequence[Mapping[str, Any]], rows: Array
) -> list[int]:
    """The positions of the items into whose levels a categorical variable of
    one of the terms given, or the combination of the categorical variables of
    one of them, divides the rows given, the rows without a level included.
    The variables and the items are compared on those rows alone, since a row
    that the rows leave out, such as a row whose grouping column alone is
    missing, changes no count of columns over them. A variable that carries a
    level, in a term that '||' has split, gives the term one column whatever
    its levels, so it divides the rows into no levels here."""
    found: list[int] = []
    for term in terms:
        categorical = [
            variable["variable"]
            for variable in term["variables"]
            if variable.get("coding") in ("contrast", "indicator") and "level" not in variable
        ]
        sets = [[variable] for variable in categorical]
        if len(categorical) > 1:
            sets.append(categorical)
        for variables in sets:
            keys = [comparison_form(variable) for variable in variables]
            found += privacy_items_in(items, value_codes(run, keys), rows)
    return list(dict.fromkeys(found))


def privacy_items_in(items: list[Array], codes: Array, rows: Array) -> list[int]:
    """The positions of the items that divide the rows given into the same
    levels as the codes, every such item when two items divide them alike
    although they divide the table differently."""
    import numpy as np

    target = privacy_item_codes([codes[rows]])
    return [
        i
        for i, item in enumerate(items)
        if np.array_equal(privacy_item_codes([item[rows]]), target)
    ]


# --- Rules 1 and 5 ----------------------------------------------------------------------


def privacy_lost(
    samples: dict[str, Array],
    quantities: dict[str, SampleQuantities],
    comparisons: list[Comparison],
    beside: list[bool],
    shown: bool,
    items: list[Array],
    written: list[WrittenItem],
    hidden: SampleMarks | None,
    factor_items: list[int | None],
    unit_item: int | None,
    basis: str,
    leaving: int,
    k: int,
) -> dict[str, SampleMarks]:
    """The quantities that the samples lose beside the analysis sample, as
    marks. Rule 1 compares each sample with the analysis sample when it is
    shown: the rows, the contributors and the levels of every item whose
    counts of levels resolve as person counts there. A sample whose written
    levels and counts can give back the sizes of its levels of an item,
    because it keeps those levels or writes them through the columns of a
    term, loses its rows when those sizes, beside the analysis sample's rows,
    would give back an outcome-derived value (privacy_sizes_close). The levels
    of an item whose counts resolve as non-person are compared when the
    sample loses its rows or its contributors, since each such level holds two
    members or more, so that its written levels would bound the members and
    rows that the sample loses. A sample that holds the analysis sample's rows
    loses the rows, contributors, levels and levels with two rows of an item
    that the analysis sample loses, since its written quantity would show that
    rule 1 did not fire against the hidden one. Rule 5 then extends a loss of
    the levels, or of the levels with two rows, of an item to every count of
    its levels and, when the contributors count the item's levels, to the
    contributors. A quantity that a sample loses is compared with no other
    sample (privacy_rule_1), since whether that comparison fires would bound
    it, and a sample that it would have been compared with, which lies in it
    and does not hold the analysis sample's rows, loses the quantity unless
    the analysis sample's exceeds it by k or more. The two steps repeat until
    nothing changes."""
    import numpy as np

    lost = privacy_blank_marks(quantities)
    if not shown:
        return lost
    assert hidden is not None
    two = PRIVACY_MEASURES[:2]
    for comparison, near in zip(comparisons, beside, strict=True):
        if not near:
            continue
        larger = quantities[comparison.larger]
        smaller = quantities[comparison.smaller]
        loser = lost[comparison.loser]
        for member in SAMPLE_MEMBERS:
            if privacy_close(
                privacy_quantity(larger, member), privacy_quantity(smaller, member), k
            ):
                mark(loser, member)
        # When the names of sample.raw_vs_analysis show k - 1 or more rows of
        # the table that leave the design sample (privacy_names_bound()) and
        # rule 1 hides the design sample's rows beside the analysis sample, the
        # table loses its rows beside it whatever they exceed the analysed rows
        # by, since the firing of rule 1 would otherwise show the table's rows
        # within k - 1 of the analysed rows, and so no outcome missing.
        if (
            comparison.larger == "table"
            and comparison.smaller == "analysis"
            and leaving >= k - 1
            and "design" in quantities
            and privacy_close(quantities["design"].rows, smaller.rows, k)
        ):
            lost["table"].rows = True
        inside = comparison.smaller == "analysis" and comparison.loser == comparison.larger
        # A quantity that the analysis sample loses is lost by every sample
        # that holds its rows, whose written quantity would show that rule 1
        # did not fire and so bound the hidden one from above, unless it is 0
        # there, which rule 1 does not compare.
        if inside:
            loser.rows = loser.rows or hidden.rows
            loser.contributors = loser.contributors or hidden.contributors
            for i, item in enumerate(larger.items):
                for measure in two:
                    if hidden.items[i][measure] and item_quantity(item, measure) > 0:
                        loser.items[i][measure] = True

        def compare_items(
            person: bool,
            larger: SampleQuantities = larger,
            smaller: SampleQuantities = smaller,
            loser: SampleMarks = loser,
        ) -> None:
            for i, item in enumerate(larger.items):
                if item.person != person:
                    continue
                for measure in two:
                    if privacy_close(
                        item_quantity(item, measure), item_quantity(smaller.items[i], measure), k
                    ):
                        loser.items[i][measure] = True

        compare_items(True)
        if inside:
            for i in range(len(larger.items)):
                through_columns = any(
                    w.item == i and w.larger == comparison.larger and w.smaller == "analysis"
                    for w in written
                )
                if (
                    through_columns or not any(loser.items[i][measure] for measure in two)
                ) and privacy_sizes_close(
                    items[i],
                    samples[comparison.larger],
                    samples["analysis"],
                    quantities["analysis"].items[i].person,
                    k,
                ):
                    loser.rows = True
        if loser.rows or loser.contributors:
            compare_items(False)

    def holds_analysis(s: str) -> bool:
        return bool(np.isin(samples["analysis"], samples[s]).all())

    while True:
        before = copy.deepcopy(lost)
        for s, marks in lost.items():
            if s == "analysis":
                continue
            for i, hidden_item in enumerate(marks.items):
                if hidden_item["levels"] or hidden_item["levels_with_two_rows"]:
                    for measure in PRIVACY_MEASURES:
                        hidden_item[measure] = True
                    if (basis == "grouping_factors" and i in factor_items) or i == unit_item:
                        marks.contributors = True
        for comparison, near in zip(comparisons, beside, strict=True):
            if near:
                continue
            larger_name = comparison.larger
            smaller_name = comparison.smaller
            if holds_analysis(smaller_name):
                continue

            def chain(
                member: Quantity,
                item: int | None = None,
                larger_name: str = larger_name,
                smaller_name: str = smaller_name,
            ) -> None:
                if (
                    marked(lost[larger_name], member, item)
                    and not marked(lost[smaller_name], member, item)
                    and privacy_quantity(quantities["analysis"], member, item)
                    - privacy_quantity(quantities[smaller_name], member, item)
                    < k
                ):
                    mark(lost[smaller_name], member, item)

            for member in SAMPLE_MEMBERS:
                chain(member)
            for i, item_quantities in enumerate(quantities[larger_name].items):
                if item_quantities.person:
                    for measure in two:
                        chain(measure, i)
        if lost == before:
            return lost


def privacy_names_bound(run: Run, findings: list[Finding]) -> int:
    """The rows of the table that leave the design sample which the names of
    sample.raw_vs_analysis show to be distinct rows. For one variable, a row in
    which its column, or a column of its grouping factor, is missing
    (incomplete_columns), a row at a level of it that leaves the design sample
    (emptied_factors or factors_losing_levels) and a row of a level that keeps
    one row there (new_singletons) are three different rows, while rows that
    the names of different variables show can be one row. The bound is the
    most rows that the names show for one variable, 0 to 3, or 0 when the
    check is not available."""
    for finding in findings:
        if finding.check != "sample.raw_vs_analysis" or not finding.available:
            continue
        values = finding.values
        incomplete = list(values["incomplete_columns"])
        losing = list(values["emptied_factors"]) + list(values["factors_losing_levels"])
        singletons = list(values["new_singletons"])
        best = 0
        for name in dict.fromkeys(losing + singletons + incomplete):
            columns = list(run.factors[name]) if name in run.factors else [name]
            count = (
                int(any(column in incomplete for column in columns))
                + int(name in losing)
                + int(name in singletons)
            )
            best = max(best, count)
        return best
    return 0


def privacy_sizes_close(
    codes: Array, larger_rows: Array, analysis_rows: Array, person: bool, k: int
) -> bool:
    """Whether the sizes in a larger sample of the levels of an item that hold
    an analysed row would, beside the rows of the analysis sample, give back
    an outcome-derived value: the rows that the larger sample holds in those
    of them that have two rows or more there exceed the analysed rows in them
    by fewer than k, 0 included, or, for an item whose counts of levels
    resolve as person counts in the analysis sample, they leave its levels
    with one row a single possible value. Besides the levels of one row in the
    larger sample, the fewest that can have one analysed row are as many as
    the rows lost beyond those that leave each level two rows, and the most as
    many as the rows lost reduce to one row, from the smallest. When fewer
    than k levels can have one analysed row, rule 2 hides the analysed levels
    with two rows, and the larger sample loses them. ``codes`` are the level
    codes of the item in every row of the table."""
    import numpy as np

    bins = int(codes.max(initial=-1)) + 1
    analysed = tabulate(codes[analysis_rows], bins)
    sizes = tabulate(codes[larger_rows], bins)
    several = (analysed > 0) & (sizes >= 2)
    if not several.any():
        return False
    lost_rows = int(sizes[several].sum()) - int(analysed[several].sum())
    if lost_rows < k:
        return True
    if not person:
        return False
    most = int((np.cumsum(np.sort(sizes[several] - 1)) <= lost_rows).sum())
    fewest = max(0, lost_rows - int((sizes[several] - 2).sum()))
    return fewest == most


def privacy_rule_1(
    quantities: dict[str, SampleQuantities],
    comparisons: list[Comparison],
    lost: dict[str, SampleMarks],
    marks: dict[str, SampleMarks],
    k: int,
) -> dict[str, SampleMarks]:
    """Rule 1 between the samples other than the analysis sample: the rows and
    contributors, and the levels and levels with two rows of each item whose
    counts of levels resolve as person counts in the larger sample, which
    holds the levels that the difference counts. A quantity that either
    sample loses beside the analysis sample is not compared."""
    for comparison in comparisons:
        larger = comparison.larger
        smaller = comparison.smaller
        for member in SAMPLE_MEMBERS:
            if (
                not marked(lost[larger], member)
                and not marked(lost[smaller], member)
                and privacy_close(
                    privacy_quantity(quantities[larger], member),
                    privacy_quantity(quantities[smaller], member),
                    k,
                )
            ):
                mark(marks[comparison.loser], member)
        for i, item in enumerate(quantities[larger].items):
            if not item.person:
                continue
            for measure in PRIVACY_MEASURES[:2]:
                if (
                    not lost[larger].items[i][measure]
                    and not lost[smaller].items[i][measure]
                    and privacy_close(
                        item_quantity(item, measure),
                        item_quantity(quantities[smaller].items[i], measure),
                        k,
                    )
                ):
                    marks[comparison.loser].items[i][measure] = True
    return marks


def privacy_rule_5(run: Run, finding: Finding, items: list[Array], lost: SampleMarks) -> Finding:
    """Rule 5 for one finding on a sample other than the analysis sample, given
    what the sample loses beside the analysis sample: every real when it loses
    its rows, and for each item whose levels or levels with two rows it loses,
    the counts that name a count of the item's levels in part_of, directly or
    through another such count, the counts of an item that combines it with
    another, and the reals of a finding whose scope names it as its factor, or
    names no factor while its entry reads grouping_factors. The counts that
    measure the item's levels take the marks of the sample."""
    defined = entry_statistics(finding)
    reals = [
        name for name in finding.values if finding.statistics[name]["kind"] in ("real", "reals")
    ]
    if lost.rows:
        privacy_suppress(finding, reals, "secondary")
    hit = [i for i, item in enumerate(lost.items) if item["levels"] or item["levels_with_two_rows"]]
    if not hit:
        return finding
    factor = privacy_scope_item(run, finding) if "factor" in finding.scope else None
    counted = [
        name
        for name in finding.values
        if defined[name].get("measures") in PRIVACY_MEASURES
        and privacy_item_index(items, finding_item(finding, name, factor)) in hit
    ]
    counted += privacy_parts(finding, counted, person=False)
    combined = []
    for name in finding.values:
        item = finding.items.get(name)
        if (
            item is not None
            and len(item) == 2
            and all(codes is not None for codes in item)
            and any(privacy_item_index(items, [codes]) in hit for codes in item)
        ):
            combined.append(name)
    assert finding.entry is not None
    if factor is None:
        reads_item = "grouping_factors" in finding.entry.get("reads", [])
    else:
        reads_item = privacy_item_index(items, factor) in hit
    names = counted + combined + (reals if reads_item else [])
    return privacy_suppress(finding, dict.fromkeys(names), "secondary", replace=True)


def finding_item(
    finding: Finding, name: str, factor: list[Array | None] | None
) -> list[Array | None] | None:
    """The item of a count of a finding: that of resolved_by, or the grouping
    factor of the finding's scope, given as ``factor``, for a count without
    resolved_by."""
    item = finding.items.get(name)
    return factor if item is None else item


# --- Rule 6 -----------------------------------------------------------------------------


def privacy_rule_6(
    run: Run,
    finding: Finding,
    sample: str,
    samples: dict[str, Array],
    items: list[Array],
    quantities: dict[str, SampleQuantities],
    measured: dict[str, dict[int, bool]],
    marks: dict[str, SampleMarks],
    k: int,
) -> Finding:
    """Rule 6 for one finding on a sample: a count of columns that measures the
    levels of the items of its terms with an offset, marked term_levels for
    the columns kept over the rows of the finding and table_term_levels for
    the columns of the IR, which count the levels of the table and so give
    back those of these rows too, is suppressed when the document hides the
    levels of one of these items in those rows, or in the table for
    table_term_levels. The items of the terms in some rows are those into
    whose levels a variable of the terms divides those rows. The document
    hides them there when a finding there has a count that measures them, and
    that count resolves as a person count below k or every such finding fails
    the minimum-count or the dominance rule (steps 2 and 3), or rule 1
    between samples other than the analysis sample, compared as in a document
    that does not show it, hides them, or, in the analysis sample, any rule
    does. In the table, where no finding of registry 0.1.0 has such a count,
    it hides them when rule 1 does and a finding on a sample other than the
    analysis sample has a count that measures them. ``marks`` are those of
    rule 1 alone for a sample other than the analysis sample and the final
    marks for the analysis sample, so that whether the rule suppresses a
    count of a design-structure sample depends on no outcome-derived value.
    ``measured`` holds, for each sample, whether every finding that measures
    the levels of an item there fails the minimum-count or the dominance
    rule, by the item's position."""
    defined = entry_statistics(finding)
    names = [
        name for name in finding.values if defined[name].get("measures") in PRIVACY_TERM_MEASURES
    ]
    if not names:
        return finding
    terms = privacy_finding_terms(run, finding)

    def counted_elsewhere(i: int) -> bool:
        """Whether a finding on a sample other than the analysis sample has a
        count that measures the levels of the item at position i."""
        return any(i in by_item for s, by_item in measured.items() if s != "analysis")

    def hidden(s: str) -> bool:
        for i in privacy_term_items(run, items, terms, samples[s]):
            fails = measured.get(s, {}).get(i)
            item = quantities[s].items[i]
            ruled = s in marks and marks[s].items[i]["levels"]
            if fails is None:
                if s == "table" and ruled and counted_elsewhere(i):
                    return True
            elif (item.person and (item.levels < k or fails)) or ruled:
                return True
        return False

    here = hidden(sample)
    table = (
        sample != "table"
        and not here
        and any(defined[name]["measures"] == "table_term_levels" for name in names)
        and hidden("table")
    )
    suppressed = [
        name
        for name in names
        if here or (table and defined[name]["measures"] == "table_term_levels")
    ]
    return privacy_suppress(finding, suppressed, "secondary", replace=True)


def privacy_measured_items(
    run: Run,
    findings: list[Finding],
    finding_samples: list[str],
    items: list[Array],
    k: int,
) -> dict[str, dict[int, bool]]:
    """The items whose levels a count of an available finding measures, for
    each sample, by the position of the item, each recording whether every
    finding on the sample with such a count fails the minimum-count or the
    dominance rule (step 2), which then suppresses every such count of a
    person item."""
    measured: dict[str, dict[int, bool]] = {}
    for finding, s in zip(findings, finding_samples, strict=True):
        defined = entry_statistics(finding)
        support = finding.support
        assert support is not None
        fails = support.distinct < k or support.dominated
        factor: list[Array | None] | None = None
        for name in finding.values:
            if defined[name].get("measures") != "levels":
                continue
            if factor is None and finding.items.get(name) is None:
                factor = privacy_scope_item(run, finding)
            i = privacy_item_index(items, finding_item(finding, name, factor))
            if i is None:
                continue
            before = measured.setdefault(s, {}).get(i)
            measured[s][i] = fails and (before is None or before)
    return measured


def privacy_finding_terms(run: Run, finding: Finding) -> list[Mapping[str, Any]]:
    """The terms whose columns the counts of a finding count: the term of its
    scope element, fixed or random, or every fixed term when the element names
    no term."""
    term = finding.scope.get("term")
    if term is None:
        return list(run.ir["fixed"]["terms"])
    assert finding.entry is not None
    if finding.entry["scope"] == "random_term":
        for random in run.ir["random"]:
            if random["name"] == term and random["factor"] == finding.scope.get("factor"):
                return list(random["terms"])
        return []
    return [fixed for fixed in run.ir["fixed"]["terms"] if fixed["name"] == term]


# --- Rules 2 and 3 ----------------------------------------------------------------------


def privacy_rule_2(quantity: SampleQuantities, marks: SampleMarks, k: int) -> SampleMarks:
    """Rule 2 in one sample: for an item whose counts of levels resolve as
    person counts there, the levels with one and with at least two rows when
    either numbers fewer than k, the levels with at least two rows when the
    levels are hidden, and the levels with one row when the levels with at
    least two rows are hidden. For a non-person item, the levels with at least
    two rows are the levels, so that either hides the other."""
    for item, hidden in zip(quantity.items, marks.items, strict=True):
        if item.person:
            small = item.levels_with_one_row < k or item.levels_with_two_rows < k
            if small or hidden["levels"]:
                hidden["levels_with_two_rows"] = True
            if small or hidden["levels_with_two_rows"]:
                hidden["levels_with_one_row"] = True
        elif hidden["levels"] or hidden["levels_with_two_rows"]:
            hidden["levels"] = True
            hidden["levels_with_two_rows"] = True
    return marks


def privacy_rule_3(
    quantity: SampleQuantities,
    design: SampleQuantities,
    marks: SampleMarks,
    quartiles: list[tuple[int | None, list[tuple[str, int]]]],
    k: int,
) -> SampleMarks:
    """Rule 3 in the analysis sample: the rows hold one row of each level with
    one row and at least two of each other level, and at least each written
    quantile of the level sizes from its position on, so that rows below that
    sum without a level of one row, beside the levels, show that some level
    has one row and so that the smallest level size is 1. When rule 2 hides
    the levels with one row of a person item, the levels are hidden in that
    case, and the rows too when they are fewer than 2k beside k contributors
    or more, since a finding that passes the minimum-count rule shows that
    each grouping factor has k levels or more. An item none of whose levels
    holds two rows of the design sample is left out, since its levels in the
    analysis sample are its rows whatever the outcome. ``quartiles`` lists,
    for each finding of structure.cluster_sizes on the sample, the position of
    its item and the quantiles that it writes."""
    for i, item in enumerate(quantity.items):
        if (
            not item.person
            or not marks.items[i]["levels_with_one_row"]
            or design.items[i].levels_with_two_rows == 0
        ):
            continue
        written: list[tuple[str, int]] = []
        for position, quantiles in quartiles:
            if position == i:
                written = quantiles
        if quantity.rows < privacy_rows_without_singletons(item.levels, written):
            marks.items[i]["levels"] = True
            if quantity.rows < 2 * k and quantity.contributors >= k:
                marks.rows = True
    return marks


def privacy_written_quantiles(finding: Finding) -> list[tuple[str, int]]:
    """The quantiles of the level sizes that a finding of
    structure.cluster_sizes writes after steps 1 to 6, as a list of their p
    and values."""
    found = []
    for name in finding.values:
        quantile = finding.statistics[name].get("quantile")
        if quantile is not None and quantile["n"] == "levels" and privacy_written(finding, name):
            found.append((str(quantile["p"]), int(finding.values[name])))
    return found


def privacy_rows_without_singletons(levels: int, quantiles: list[tuple[str, int]]) -> int:
    """The fewest rows that J levels can hold when none has one row and each
    written quantile of their sizes, at position ceil(J p) of the sizes in
    increasing order, bounds the sizes from it on: the sum over the positions
    of the larger of 2 and the largest quantile at or before the position."""
    floor = [2] * levels
    for p, value in quantiles:
        position = quantile_position(levels, p)
        if 1 <= position <= levels:
            for j in range(position - 1, levels):
                floor[j] = max(floor[j], value)
    return sum(floor)


def quantile_position(n: int, p: str) -> int:
    """The position ceil(n p), counted from 1, of the p-quantile of n values, p
    a decimal string m / 10^d, in integer arithmetic, and 1 for the
    minimum."""
    if p in ("0", "1"):
        return 1 if p == "0" else n
    digits = p.removeprefix("0.")
    scale: int = 10 ** len(digits)
    return max(1, (n * int(digits) + scale - 1) // scale)


# --- Rule 4 -----------------------------------------------------------------------------


def privacy_missing_key_close(run: Run, samples: list[Array], k: int) -> bool:
    """Rule 4: whether the rows of the table with a missing value in a column
    of the observation key and the rows of the table that one of the samples
    given leaves out, one of which holds the other, differ by fewer than k
    rows, 0 included, so that missing_key_rows of keys.duplicates beside the
    rows of the table and of that sample would give back the rows by which
    they differ, such as the rows with a key value but no value of a
    predictor."""
    import numpy as np

    key = [comparison_form(column) for column in observation_key_columns(run.declaration)]
    missing = np.flatnonzero(value_codes(run, key) < 0)
    every = np.arange(run.table.rows, dtype=np.int64)
    for rows in samples:
        left_out = np.setdiff1d(every, rows)
        nested = bool(np.isin(missing, left_out).all()) or bool(np.isin(left_out, missing).all())
        if nested and abs(len(left_out) - len(missing)) < k:
            return True
    return False


# --- Samples, items and findings --------------------------------------------------------


def privacy_comparisons(samples: dict[str, Array], main: list[str]) -> list[Comparison]:
    """The comparisons of rule 1: every two samples one of which holds the
    other's rows, as the larger and the smaller, the table before the design
    sample and the design sample before the analysis sample when they hold the
    same rows, with the sample that loses its value. The rows of an assignment
    or of a pair lose against the table, the design sample and the analysis
    sample, and otherwise the larger sample loses."""
    import numpy as np

    names = list(samples)
    comparisons: list[Comparison] = []
    for a, larger_name in enumerate(names):
        for b, smaller_name in enumerate(names):
            larger = samples[larger_name]
            smaller = samples[smaller_name]
            if (
                a == b
                or len(smaller) > len(larger)
                or (len(smaller) == len(larger) and b < a)
                or not bool(np.isin(smaller, larger).all())
            ):
                continue
            loser = (
                smaller_name if larger_name in main and smaller_name not in main else larger_name
            )
            comparisons.append(Comparison(larger_name, smaller_name, loser))
    return comparisons


def privacy_items(run: Run, findings: list[Finding]) -> list[Array]:
    """The items whose quantities the rules across findings compare: the
    grouping factors of the IR, the declared units that do not count as absent
    and the items by which the by_unit counts of the findings resolve, each as
    the level codes of every row of the table. Items that divide the rows into
    the same levels are one item."""
    import numpy as np

    candidates: list[list[Array | None]] = [
        [value_codes(run, keys)] for keys in run.factors.values()
    ]
    for unit in declared_units(run.declaration):
        candidates.append([value_codes(run, unit_label_columns(run.declaration, unit))])
    for finding in findings:
        for item in finding.items.values():
            if all(codes is not None for codes in item):
                candidates.append(list(item))
    items: list[Array] = []
    for candidate in candidates:
        codes = privacy_item_codes(candidate)
        if not any(np.array_equal(codes, other) for other in items):
            items.append(codes)
    return items


def privacy_item_codes(item: list[Array | None]) -> Array:
    """The level codes of an item given as the codes of one item, or of two
    whose combinations form its levels, numbered from 0 in the order of first
    appearance, with -1 for a row without a level."""
    import numpy as np

    first = item[0]
    assert first is not None
    level = first
    if len(item) == 2:
        second = item[1]
        assert second is not None
        level = pair_codes(first, second)
    present = level >= 0
    codes = np.full(len(level), -1, dtype=np.int64)
    codes[present] = first_codes(level[present])
    return codes


def privacy_item_index(items: list[Array], item: list[Array | None] | None) -> int | None:
    """The position of an item among the items of the rules, or None for an
    item that the finding lacks."""
    import numpy as np

    if item is None or any(codes is None for codes in item):
        return None
    codes = privacy_item_codes(item)
    for i, other in enumerate(items):
        if np.array_equal(codes, other):
            return i
    return None


def privacy_item_quantities(run: Run, codes: Array, rows: Array) -> ItemQuantities:
    """The quantities of an item in some rows: whether its counts of levels
    resolve as person counts there, its levels, those with at least two rows
    and those with one row."""
    sizes = tabulate(codes[rows])
    return ItemQuantities(
        person=resolve_count_class(run, [codes], rows) == "person",
        levels=int((sizes > 0).sum()),
        levels_with_two_rows=int((sizes >= 2).sum()),
        levels_with_one_row=int((sizes == 1).sum()),
    )


def privacy_across_finding(
    run: Run,
    finding: Finding,
    sample: str,
    items: list[Array],
    factor_items: list[int | None],
    unit_item: int | None,
    quantities: dict[str, SampleQuantities],
    marks: dict[str, SampleMarks],
    k: int,
) -> Finding:
    """One finding on a sample with the marks of the samples: its support and
    the counts that measure a hidden quantity, with the detail 'secondary' in
    place of 'min_count', apart from support.contributors.distinct, whose
    detail 'min_count' shows that the finding fails the minimum-count rule, as
    the details of its statistics show too. The support counts the sample that
    the entry names, and the counts of levels the sample of the finding. On
    the analysis sample, the counts that name such a person count in part_of,
    directly or through another such count, are suppressed too, since a
    written part shows that the count exceeds it by k or more (Within a
    finding, part_of). So are those other than 0 that name a non-person count
    of levels that the sample loses when the design sample's levels of the
    item exceed them by fewer than k, since they would bound the hidden levels
    from below, which the design sample's bound from above. events and
    non_events of a bernoulli outcome, which add up to the rows, are
    suppressed when the analysis sample loses its rows."""
    assert finding.entry is not None and finding.support is not None
    own: str = finding.entry["sample"]
    support_members: tuple[tuple[str, Quantity], ...] = (
        ("rows", "rows"),
        ("distinct", "contributors"),
    )
    for member, quantity in support_members:
        detail = finding.support_suppressed.get(member)
        if marked(marks[own], quantity) and (
            detail is None or (member == "rows" and detail == "min_count")
        ):
            finding.support_suppressed[member] = "secondary"
    # With the basis grouping_factors, the distinct contributors are the
    # levels of the factors with the fewest levels, and with the basis
    # disclosure_unit, the levels of the disclosure unit, and they measure
    # them.
    support = finding.support
    if "distinct" not in finding.support_suppressed:
        counted: list[int] = []
        if support.basis == "grouping_factors":
            counted = [
                i
                for i in factor_items
                if i is not None and quantities[own].items[i].levels == support.distinct
            ]
        elif support.basis == "disclosure_unit" and unit_item is not None:
            counted = [unit_item]
        if any(marks[own].items[i]["levels"] for i in counted):
            finding.support_suppressed["distinct"] = "secondary"
    defined = entry_statistics(finding)
    hidden: list[str] = []
    # The hidden counts of levels, with their items.
    levels: dict[str, int] = {}
    factor: list[Array | None] | None = None
    for name in finding.values:
        measure = defined[name].get("measures")
        if measure is None or measure in PRIVACY_TERM_MEASURES:
            continue
        i: int | None = None
        if measure in ROWS_MEASURES:
            suppressed = marks[ROWS_MEASURES[measure]].rows
        else:
            if factor is None and finding.items.get(name) is None:
                factor = privacy_scope_item(run, finding)
            i = privacy_item_index(items, finding_item(finding, name, factor))
            suppressed = i is not None and marks[sample].items[i][measure]
        if suppressed:
            privacy_suppress(finding, [name], "secondary", replace=True)
            hidden.append(name)
            if i is not None:
                levels[name] = i
    if sample == "analysis":
        person = privacy_parts(finding, hidden, person=True)
        privacy_suppress(finding, person, "secondary", replace=True)
        # constant_levels 10 beside the 10 levels of an item that the columns
        # of a factor give the design sample would show that no level lacks
        # every outcome, and none_constant shows constant_levels 0 anyway.
        design = quantities["design"]
        for total, i in levels.items():
            parts = [p for p in privacy_parts(finding, [total], person=False) if p not in person]
            close = [
                p
                for p in parts
                if finding.values[p] > 0 and design.items[i].levels - finding.values[p] < k
            ]
            privacy_suppress(finding, close, "secondary", replace=True)
        # Those that this rule alone suppresses are k or more, and step 9
        # reads them as written.
        pair = ["events", "non_events"]
        if (
            marks["analysis"].rows
            and run.family_class == "bernoulli"
            and all(name in finding.values for name in pair)
        ):
            finding.with_rows = [name for name in pair if privacy_written(finding, name)]
            privacy_suppress(finding, pair, "secondary", replace=True)
    return finding


def privacy_scope_item(run: Run, finding: Finding) -> list[Array | None]:
    """The item of the factor of a finding's scope, which the counts of the
    finding without resolved_by count, as privacy_item_index() takes it."""
    return [value_codes(run, factor_keys(run, finding.scope["factor"]))]


def privacy_parts(finding: Finding, names: list[str], person: bool) -> list[str]:
    """The counts of a finding that name one of the counts given in part_of,
    directly or through another such count, only through totals of class
    person when person is True."""
    defined = entry_statistics(finding)
    found: list[str] = []
    while True:
        parts = [
            name
            for name in finding.values
            if name not in names
            and name not in found
            and defined[name].get("part_of") in [*names, *found]
            and (not person or privacy_person(finding, defined[name]["part_of"]))
        ]
        if not parts:
            return found
        found += parts
