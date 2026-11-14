"""The structure checks, in the parts that the audit corpus cannot reach: the
tolerance of the parameter agreement, which tables of 40 rows cannot test,
the connected components, the intraclass correlation, quantiles of more
levels and grouping factors of several columns."""

from __future__ import annotations

import itertools
from typing import Any

import numpy as np
import pandas as pd
import pytest
from audit_helpers import AUDIT_KEY

from mixedcheck import audit
from mixedcheck._checks_structure import bipartite_components


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every run is at the time 0."""
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def structure_findings(
    data: pd.DataFrame, formula: str, check: str, **arguments: Any
) -> list[dict[str, Any]]:
    """The findings of one check for an audit in internal mode."""
    results = audit(data, formula, privacy="internal", key=AUDIT_KEY, **arguments)
    return [f for f in results.document["findings"] if f["check"] == check]


def statistic_values(finding: dict[str, Any]) -> dict[str, Any]:
    return {name: statistic["value"] for name, statistic in finding["statistics"].items()}


def test_within_between_infers_a_between_term_with_the_tolerance_of_agreement() -> None:
    # Ten schools of 20 rows, with x constant within each school but one row:
    # 199 of the 200 rows have the most frequent pattern of their school, and
    # 199 x 100 >= 99 x 200.
    school = [f"S{i:02d}" for i in range(1, 11) for _ in range(20)]
    x = [float(i) for i in range(1, 11) for _ in range(20)]
    x[4] = 7.0
    data = pd.DataFrame({"y": np.arange(1.0, 201.0), "x": x, "school": school})
    formula = "y ~ x + (1 + x | school)"
    found = structure_findings(data, formula, "structure.within_between")[0]
    values = statistic_values(found)
    assert values["status"] == "between"
    assert values["varying_levels"] == 1
    assert found["status"]["finding"]["value"] == "detectable_inconsequential"
    assert found["message"]["id"] == "between_slope"
    # Three miscoded rows leave 197 of 200, below the agreement.
    x[24] = 9.0
    x[44] = 9.0
    data["x"] = x
    found = structure_findings(data, formula, "structure.within_between")[0]
    assert statistic_values(found)["status"] == "partially_within"
    assert found["message"]["id"] == "partial_slope"


def test_connectivity_lists_a_term_constant_with_the_tolerance_of_agreement_as_inexact() -> None:
    # Two blocks of ten subjects crossed with ten items that no row links, and
    # 'group' constant within each block but one row.
    def block(subjects: range, items: range) -> list[tuple[str, str]]:
        return [(f"i{i:02d}", f"s{s:02d}") for s in subjects for i in items]

    rows = block(range(1, 11), range(1, 11)) + block(range(11, 21), range(11, 21))
    group = ["A"] * 100 + ["B"] * 100
    group[2] = "B"
    data = pd.DataFrame(
        {
            "item": [row[0] for row in rows],
            "subject": [row[1] for row in rows],
            "group": group,
            "x": [float(i % 7) for i in range(1, 201)],
            "y": np.arange(1.0, 201.0),
        }
    )
    formula = "y ~ x + group + (1 | subject) + (1 | item)"
    found = structure_findings(data, formula, "structure.connectivity")[0]
    values = statistic_values(found)
    assert values["components"] == 2
    assert values["between_component_terms"] == ["group"]
    assert values["exact"] is False
    assert found["status"]["finding"]["value"] == "detectable_inconsequential"
    assert found["message"]["id"] == "confounded"
    # Exactly constant within each block, the finding is consequential.
    group[2] = "A"
    data["group"] = group
    found = structure_findings(data, formula, "structure.connectivity")[0]
    assert statistic_values(found)["exact"] is True
    assert found["status"]["finding"]["value"] == "consequential"


def test_id_scope_evidence_keeps_an_attribute_constant_within_99_percent() -> None:
    # 60 pupils, each once in each of two schools, with one more row in which
    # pupil p01 has the other sex at S1: sex is constant within 119 of the 120
    # combinations. stype is constant within each school, so it is a candidate
    # only when the schools are the labels, where it changes for none.
    pupils = [f"p{i:02d}" for i in range(1, 61)]
    sex = ["F", "M"] * 30
    data = pd.DataFrame(
        {
            "pupil": pupils * 2 + ["p01"],
            "school": ["S1"] * 60 + ["S2"] * 60 + ["S1"],
            "sex": sex * 2 + ["M"],
            "stype": [1.0] * 60 + [2.0] * 60 + [1.0],
        }
    )
    data["y"] = np.arange(1.0, 122.0)
    found = structure_findings(
        data, "y ~ sex + stype + (1 | school) + (1 | pupil)", "structure.id_scope_evidence"
    )[0]
    values = statistic_values(found)
    assert values["labels_column"] == ["pupil"]
    assert values["attributes"] == ["sex"]
    assert values["changing_labels"] == 1
    assert values["shared_labels"] == 60
    assert values["tied"] is False
    assert found["message"]["id"] == "some_change"
    assert found["status"]["finding"]["value"] == "detectable_inconsequential"


def test_the_checks_of_a_pair_of_columns_read_the_rows_in_which_both_are_present() -> None:
    # Four classes crossed with two schools, a class-level attribute a and a
    # 17th row of c1 without a school, in which a is 9. Over the rows of the
    # pair, a is constant within c1 and changes for no shared label.
    classes = [c for c in ("c1", "c2", "c3", "c4") for _ in range(4)]
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 18.0),
            "class": classes + ["c1"],
            "school": ["S1", "S1", "S2", "S2"] * 4 + [None],
            "a": [float(int(c[1])) for c in classes] + [9.0],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "units": [
            {"name": "school", "columns": ["school"], "role": "cluster"},
            {"name": "campus", "columns": ["school"], "role": "cluster"},
            {
                "name": "class",
                "columns": ["class"],
                "nested_in": "school",
                "id_scope": "global",
                "role": "cluster",
            },
        ],
    }
    found = structure_findings(
        data, "y ~ a + (1 | class)", "structure.id_scope_evidence", declaration=declaration
    )[0]
    values = statistic_values(found)
    assert values["attributes"] == ["a"]
    assert values["changing_labels"] == 0
    assert values["tied"] is False
    assert found["message"]["id"] == "no_change"
    # Twenty classes of two pupils with a school missing in the first row: the
    # class c01 has one pupil in the rows of the pair, so the counts of the
    # levels of 'class' there are person counts, whereas over the design
    # sample, which structure.cluster_sizes reads, they are not.
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 41.0),
            "class": [f"c{i:02d}" for i in range(1, 21) for _ in range(2)],
            "school": [None] + (["S1", "S2"] * 20)[1:],
            "pupil": [f"p{i:02d}" for i in range(1, 41)],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "units": [
            {"name": "school", "columns": ["school"], "role": "cluster"},
            {
                "name": "class",
                "columns": ["class"],
                "nested_in": "school",
                "id_scope": "global",
                "role": "cluster",
            },
            {
                "name": "pupil",
                "columns": ["pupil"],
                "nested_in": "class",
                "id_scope": "global",
                "role": "participant",
            },
        ],
    }
    formula = "y ~ 1 + (1 | class)"
    incidence = structure_findings(
        data, formula, "structure.label_incidence", declaration=declaration
    )[0]
    sizes = structure_findings(data, formula, "structure.cluster_sizes", declaration=declaration)[0]
    assert incidence["statistics"]["levels_first"]["value"] == 20
    assert incidence["statistics"]["levels_first"]["count_class"] == "person"
    assert sizes["statistics"]["levels"]["value"] == 20
    assert sizes["statistics"]["levels"]["count_class"] == "non_person"


def breadth_first_components(a: list[int], b: list[int], count_a: int, count_b: int) -> list[int]:
    """The connected components by a breadth-first search, numbered from 0 in
    the order of their smallest vertices."""
    neighbours: list[set[int]] = [set() for _ in range(count_a + count_b)]
    for u, v in zip(a, b, strict=True):
        neighbours[u].add(count_a + v)
        neighbours[count_a + v].add(u)
    found = [-1] * (count_a + count_b)
    k = -1
    for start in range(count_a + count_b):
        if found[start] >= 0:
            continue
        k += 1
        found[start] = k
        frontier = [start]
        while frontier:
            reached = {w for vertex in frontier for w in neighbours[vertex] if found[w] < 0}
            for w in reached:
                found[w] = k
            frontier = list(reached)
    return found


def test_connected_components_agree_with_a_breadth_first_search() -> None:
    rng = np.random.default_rng(9)
    for _ in range(50):
        count_a = int(rng.integers(1, 16))
        count_b = int(rng.integers(1, 16))
        m = int(rng.integers(1, 26))
        a = list(range(count_a)) + rng.integers(0, count_a, count_b + m).tolist()
        b = (
            rng.integers(0, count_b, count_a).tolist()
            + list(range(count_b))
            + rng.integers(0, count_b, m).tolist()
        )
        found = bipartite_components(
            np.array(a, dtype=np.int64), np.array(b, dtype=np.int64), count_a, count_b
        )
        assert found.tolist() == breadth_first_components(a, b, count_a, count_b)
    # A path through 2,000 levels with shuffled numbers is one component.
    first = rng.permutation(1000)
    second = rng.permutation(1000)
    path = bipartite_components(
        np.concatenate([first, first[1:]]), np.concatenate([second, second[:-1]]), 1000, 1000
    )
    assert bool((path == 0).all())


def test_connectivity_resolves_its_components_by_the_levels_of_interaction_factors() -> None:
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 9.0),
            "subject": ["s1", "s1", "s2", "s2", "s3", "s3", "s4", "s4"],
            "item": ["i1", "i2", "i1", "i2", "i1", "i2", "i1", "i2"],
            "session": ["a", "a", "a", "a", "b", "b", "b", "b"],
        }
    )
    declaration = {
        "vocabulary": "0.1.0",
        "units": [{"name": "subject", "columns": ["subject"], "role": "participant"}],
    }
    found = structure_findings(
        data,
        "y ~ 1 + (1 | subject) + (1 | item:session)",
        "structure.connectivity",
        declaration=declaration,
    )[0]
    assert found["scope"] == {"first": "item:session", "second": "subject"}
    assert found["statistics"]["components"]["value"] == 2
    assert found["statistics"]["components"]["count_class"] == "person"
    assert found["message"]["id"] == "disconnected"


def test_cluster_sizes_takes_the_quantiles_at_positions_ceil_j_times_p() -> None:
    # Seven levels of 1 to 7 rows: positions ceil(7/4) = 2, ceil(7/2) = 4 and
    # ceil(21/4) = 6.
    g = [f"g{i}" for i in range(1, 8) for _ in range(i)]
    data = pd.DataFrame({"y": np.arange(1.0, len(g) + 1.0), "g": g})
    values = statistic_values(
        structure_findings(data, "y ~ 1 + (1 | g)", "structure.cluster_sizes")[0]
    )
    quantiles = ("smallest", "lower_quartile", "median", "upper_quartile", "largest")
    assert [values[name] for name in quantiles] == [1, 2, 4, 6, 7]
    assert values["effective_size"] == (28 - 140 / 28) / 6
    # One level: the quotient is 0/0.
    data = pd.DataFrame({"y": [1.0, 2, 3], "g": ["a", "a", "a"]})
    values = statistic_values(
        structure_findings(data, "y ~ 1 + (1 | g)", "structure.cluster_sizes")[0]
    )
    assert values["effective_size"] == "NaN"
    assert [values[name] for name in quantiles] == [3, 3, 3, 3, 3]


def test_cluster_sizes_rounds_the_positions_of_its_quantiles_up() -> None:
    # For each J from 1 to 12, the sizes 1 to J give the quantile p as the size
    # at position ceil(J x p), which is that position itself.
    for j in range(1, 13):
        g = [f"g{i:02d}" for i in range(1, j + 1) for _ in range(i)]
        data = pd.DataFrame({"y": np.arange(1.0, len(g) + 1.0), "g": g})
        values = statistic_values(
            structure_findings(data, "y ~ 1 + (1 | g)", "structure.cluster_sizes")[0]
        )
        expected = [-(-j * p // 4) for p in (1, 2, 3)]
        assert [values[n] for n in ("lower_quartile", "median", "upper_quartile")] == expected


def test_the_intraclass_correlation_follows_its_definition() -> None:
    rng = np.random.default_rng(4)
    g = rng.choice([f"g{i}" for i in range(1, 7)], 40)
    levels = sorted(set(g.tolist()))
    x = np.round(rng.normal(size=40) + np.array([levels.index(v) + 1 for v in g]), 2)
    data = pd.DataFrame({"y": np.arange(1.0, 41.0), "x": x, "g": g})
    values = statistic_values(
        structure_findings(data, "y ~ x + (1 | g)", "structure.within_between")[0]
    )
    frame = pd.DataFrame({"x": x, "g": g})
    sizes = frame.groupby("g")["x"].size().to_numpy()
    means = frame.groupby("g")["x"].mean().to_numpy()
    ssb = float(np.sum(sizes * (means - x.mean()) ** 2))
    ssw = float(np.sum((x - frame.groupby("g")["x"].transform("mean").to_numpy()) ** 2))
    j = len(sizes)
    msb = ssb / (j - 1)
    msw = ssw / (40 - j)
    n0 = (40 - float(np.sum(sizes**2)) / 40) / (j - 1)
    assert values["icc"] == pytest.approx((msb - msw) / (msb + (n0 - 1) * msw), rel=1e-12)
    assert values["within_share"] == pytest.approx(ssw / (ssb + ssw), rel=1e-12)


def test_the_intraclass_correlation_is_the_same_at_extreme_magnitudes() -> None:
    # The column is divided by its largest absolute value before any square,
    # so that values near 1e300 or 1e-300 give the statistics of the same data
    # at unit scale instead of NaN or an absent share.
    rng = np.random.default_rng(7)
    g = [f"g{i}" for i in range(1, 7) for _ in range(10)]
    x = rng.normal(size=60) + np.repeat(rng.normal(size=6), 10)
    base = pd.DataFrame({"y": np.arange(1.0, 61.0), "x": x, "g": g})
    expected = statistic_values(
        structure_findings(base, "y ~ x + (1 | g)", "structure.within_between")[0]
    )
    for scale in (1e-310, 1e-200, 1e160, 1e300):
        data = base.copy()
        data["x"] = x * scale
        values = statistic_values(
            structure_findings(data, "y ~ x + (1 | g)", "structure.within_between")[0]
        )
        for name in ("within_share", "icc"):
            assert values[name] == pytest.approx(expected[name], rel=1e-12), (scale, name)


def test_the_intraclass_correlation_is_absent_or_nan_by_its_definition() -> None:
    # A column constant over the design sample has neither statistic, and one
    # row per level makes the correlation NaN while the share is 0.
    data = pd.DataFrame({"y": [1.0, 2, 3, 4], "x": [5.0] * 4, "g": ["a", "a", "b", "b"]})
    values = statistic_values(
        structure_findings(data, "y ~ 0 + x + (1 | g)", "structure.within_between")[0]
    )
    assert "icc" not in values and "within_share" not in values
    data = pd.DataFrame({"y": [1.0, 2, 3, 4], "x": [1.0, 2, 3, 4], "g": ["a", "b", "c", "d"]})
    values = statistic_values(
        structure_findings(data, "y ~ x + (1 | g)", "structure.within_between")[0]
    )
    assert values["icc"] == "NaN"
    assert values["within_share"] == 0
    assert values["multi_row_levels"] == 0
    assert "status" not in values


def test_label_incidence_classifies_every_relation_of_two_columns() -> None:
    # Six rows over two grouping columns, the second grouping column given as
    # the rows to keep, with the relation that each arrangement gives.
    cases = {
        "identical": (["a", "a", "b", "b", "c", "c"], ["p", "p", "q", "q", "r", "r"]),
        "first_nested_in_second": (["a", "a", "b", "b", "c", "c"], ["p", "p", "p", "p", "q", "q"]),
        "second_nested_in_first": (["a", "a", "a", "a", "b", "b"], ["p", "p", "q", "q", "r", "r"]),
        "crossed": (["a", "b", "a", "b", "a", "b"], ["p", "p", "q", "q", "r", "r"]),
        "partially_crossed": (["a", "b", "a", "b", "c", "c"], ["p", "p", "q", "q", "q", "r"]),
    }
    for relation, (first, second) in cases.items():
        data = pd.DataFrame({"y": np.arange(1.0, 7.0), "f": first, "s": second})
        formula = "y ~ 1 + (1 | f) + (1 | s)"
        found = structure_findings(data, formula, "structure.label_incidence")[0]
        assert statistic_values(found)["relation"] == relation, relation


def test_aliased_factors_compares_partitions_and_columns_by_value() -> None:
    # 'session' equals 'subject' after relabelling, and x and z, the slopes of
    # the two factors, hold the same values in every row, so the two factors
    # share a column although the columns' names differ.
    data = pd.DataFrame(
        {
            "y": np.arange(1.0, 9.0),
            "x": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "z": [1.0, 2, 3, 4, 5, 6, 7, 8],
            "subject": ["s1", "s1", "s2", "s2", "s3", "s3", "s4", "s4"],
            "session": ["k4", "k4", "k3", "k3", "k2", "k2", "k1", "k1"],
        }
    )
    found = structure_findings(
        data, "y ~ x + (0 + x | subject) + (0 + z | session)", "structure.aliased_factors"
    )[0]
    values = statistic_values(found)
    assert values["partition"] == "identical"
    assert values["shared_columns"] is True
    assert found["message"]["id"] == "aliased"
    data["z"] = [1.0, 2, 3, 4, 5, 6, 7, 9]
    found = structure_findings(
        data, "y ~ x + (0 + x | subject) + (0 + z | session)", "structure.aliased_factors"
    )[0]
    assert statistic_values(found)["shared_columns"] is False
    assert found["message"]["id"] == "same_groups"


def test_bipartite_components_hooks_roots_in_rounds_on_long_chains() -> None:
    # A chain whose levels alternate between the two factors in decreasing
    # order of their numbers needs several rounds of hooking.
    n = 64
    first = np.array([n - 1 - i for i in range(n)] + [n - 2 - i for i in range(n - 1)])
    second = np.array([n - 1 - i for i in range(n)] + [n - 1 - i for i in range(n - 1)])
    found = bipartite_components(first, second, n, n)
    assert found.tolist() == [0] * (2 * n)
    # Isolated levels are components of their own, in the order of their
    # numbers.
    found = bipartite_components(np.array([0, 2]), np.array([1, 1]), 4, 3)
    assert found.tolist() == breadth_first_components([0, 2], [1, 1], 4, 3)
    assert list(itertools.islice(found.tolist(), 4)) == [0, 1, 0, 2]
