"""Prototype generator for the 'pathology zoo' (simulated fixtures).

Each fixture is a directory with
  data.csv       the data (UTF-8, LF, '' for missing, IDs as strings)
  design.json    a design declaration (schema 0.1.0) whose 'table' block is a
                 Frictionless Table Schema v2 subset, so the CSV is typed the
                 same way in R and Python
  formula.txt    the preliminary formula a user would bring to Stream B
  expected.json  outcome-free findings that hold BY CONSTRUCTION (derived from
                 the generating design, not from running the suite), plus the
                 generating parameters and seed
Positive fixtures carry the planted problem; '_neg' fixtures are matched
negatives that must not raise it.

Usage: python -I zoo_generate.py <out_dir>
"""
import csv
import hashlib
import json
import os
import sys

import numpy as np

SCHEMA_VERSION = "0.1.0"


def write_fixture(root, fid, rows, fields, design, formula, expected, params):
    d = os.path.join(root, fid)
    os.makedirs(d, exist_ok=True)
    names = [f["name"] for f in fields]
    with open(os.path.join(d, "data.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(names)
        for r in rows:
            w.writerow(["" if r[n] is None else r[n] for n in names])
    design = {"schema_version": SCHEMA_VERSION, "title": fid,
              "table": {"fields": fields, "missingValues": [""]}, **design}
    with open(os.path.join(d, "design.json"), "w", encoding="utf-8") as fh:
        json.dump(design, fh, indent=1, ensure_ascii=False, sort_keys=True)
        fh.write("\n")
    with open(os.path.join(d, "formula.txt"), "w", encoding="utf-8") as fh:
        fh.write(formula + "\n")
    data_sha = hashlib.sha256(open(os.path.join(d, "data.csv"), "rb").read()).hexdigest()
    with open(os.path.join(d, "expected.json"), "w", encoding="utf-8") as fh:
        json.dump({"fixture": fid, "data_sha256": data_sha, "generator": params,
                   "findings": expected}, fh, indent=1, sort_keys=True)
        fh.write("\n")
    return len(rows)


def fmt(x):
    return f"{x:.6f}"


def school_class_pupil(rng, J, K, n, reuse_labels):
    rows = []
    for j in range(1, J + 1):
        for k in range(1, K + 1):
            cls = str(k) if reuse_labels else f"S{j:02d}C{k}"
            for i in range(1, n + 1):
                rows.append({"school": f"S{j:02d}", "class": cls, "pupil": f"S{j:02d}C{k}P{i:02d}"})
    return rows


def add_y(rng, rows, keys_sd, sigma=1.0):
    eff = {}
    for r in rows:
        y = 0.0
        for key_cols, sd in keys_sd:
            key = tuple(r[c] for c in key_cols)
            if key not in eff:
                eff[key] = rng.normal(0, sd)
            y += eff[key]
        r["y"] = fmt(y + rng.normal(0, sigma))
    return rows


F = lambda name, t="string", **kw: {"name": name, "type": t, **kw}


def main():
    root = sys.argv[1]
    rng = np.random.default_rng(20261107)
    made = []

    # Z01: class labels reused across schools (L1-01, L7-01) and matched negative
    for fid, reuse in (("Z01_reused_class_labels", True), ("Z01_neg_unique_class_labels", False)):
        rows = school_class_pupil(rng, J=10, K=3, n=8, reuse_labels=reuse)
        rows = add_y(rng, rows, [(("school",), 0.5), (("school", "class"), 0.4)])
        fields = [F("school"), F("class"), F("pupil"), F("y", "number")]
        design = {"units": [{"name": "school", "columns": ["school"]},
                            {"name": "class", "columns": ["class"], "nested_in": "school",
                             "id_scope": "within_parent" if reuse else "global"},
                            {"name": "pupil", "columns": ["pupil"], "nested_in": "class", "id_scope": "global"}],
                  "observation": {"unit": "pupil", "key": ["pupil"]}}
        exp = [{"check": "structure.pair_relation", "outer": "school", "inner": "class",
                "relation_from_labels": "fully crossed" if reuse else "nested",
                "share_inner_labels_in_multiple_outer": 1.0 if reuse else 0.0,
                "n_inner_labels": 3 if reuse else 30},
               {"check": "structure.declared_vs_observed",
                "status": "consistent",
                "note": "declared within_parent scope explains the reuse; composite ID school:class gives 30 classes"
                if reuse else "global IDs, nested as declared"},
               {"check": "structure.composite_groups", "term": "school:class", "n_groups": 30}]
        made.append((fid, write_fixture(root, fid, rows, fields, design,
                                        "y ~ 1 + (1 | school) + (1 | class)", exp,
                                        {"J": 10, "K": 3, "n": 8, "sd_school": 0.5, "sd_class": 0.4, "seed": 20261107})))

    # Z02: genuine mobility, 2 waves, 4 of 60 pupils change school (L7-01)
    rows = []
    movers = {"P03", "P17", "P31", "P48"}
    for i in range(1, 61):
        pid = f"P{i:02d}"
        s0 = f"S{(i - 1) // 10 + 1:02d}"
        for wave in (1, 2):
            s = s0 if (wave == 1 or pid not in movers) else f"S{((i - 1) // 10 + 1) % 6 + 1:02d}"
            rows.append({"pupil": pid, "school": s, "wave": wave})
    rows = add_y(rng, rows, [(("school",), 0.4), (("pupil",), 0.8)])
    fields = [F("pupil"), F("school"), F("wave", "integer"), F("y", "number")]
    design = {"units": [{"name": "school", "columns": ["school"]},
                        {"name": "pupil", "columns": ["pupil"], "nested_in": "school", "id_scope": "global",
                         "membership": "may_change_over_time"}],
              "observation": {"unit": "pupil", "key": ["pupil", "wave"],
                              "time": {"column": "wave", "kind": "occasion", "within": "pupil"}}}
    exp = [{"check": "structure.pair_relation", "outer": "school", "inner": "pupil",
            "relation_from_labels": "partially crossed", "share_inner_labels_in_multiple_outer": round(4 / 60, 6),
            "units_changing_outer": sorted(movers)},
           {"check": "structure.nested_formula_misspecified_for_movers", "status": "flag",
            "note": "(1|school/pupil) splits each mover into two pupils; crossed (1|school)+(1|pupil) fits occasion-level outcomes"}]
    made.append(("Z02_mobility", write_fixture(root, "Z02_mobility", rows, fields, design,
                                               "y ~ wave + (1 | school/pupil)", exp,
                                               {"movers": sorted(movers), "seed": 20261107})))

    # Z04: one class per school, so school and class partitions coincide (L1-02)
    rows = school_class_pupil(rng, J=12, K=1, n=10, reuse_labels=False)
    rows = add_y(rng, rows, [(("school",), 0.5)])
    fields = [F("school"), F("class"), F("pupil"), F("y", "number")]
    design = {"units": [{"name": "school", "columns": ["school"]},
                        {"name": "class", "columns": ["class"], "nested_in": "school", "id_scope": "global"}],
              "observation": {"unit": "pupil", "key": ["pupil"]}}
    exp = [{"check": "identifiability.aliased_grouping", "status": "error", "terms": ["(1 | school)", "(1 | class)"],
            "note": "identical partitions: only the sum of the two variances is identified"}]
    made.append(("Z04_aliased_grouping", write_fixture(root, "Z04_aliased_grouping", rows, fields, design,
                                                       "y ~ 1 + (1 | school) + (1 | class)", exp,
                                                       {"J": 12, "K": 1, "n": 10, "seed": 20261107})))

    # Z07: Latin square, one observation per subject-item pair (L1-05, L7-14)
    rows = []
    n_sub, n_item, conds = 12, 12, ("A", "B", "C")
    for s in range(n_sub):
        lst = s % 3
        for it in range(n_item):
            rows.append({"subject": f"s{s + 1:02d}", "item": f"i{it + 1:02d}", "list": f"L{lst + 1}",
                         "cond": conds[(it + lst) % 3]})
    rows = add_y(rng, rows, [(("subject",), 0.5), (("item",), 0.3)])
    fields = [F("subject"), F("item"), F("list"), F("cond", categories=list(conds)), F("y", "number")]
    design = {"features": ["crossed_experiment", "counterbalanced"],
              "units": [{"name": "subject", "columns": ["subject"]}, {"name": "item", "columns": ["item"]}],
              "crossings": [{"units": ["subject", "item"], "list": "list"}],
              "observation": {"unit": "subject", "key": ["subject", "item"]}}
    exp = [{"check": "replication.obs_per_unit_cell", "term": "(1 | subject:item)", "max_obs_per_level": 1,
            "status": "error", "family": "gaussian",
            "note": "subject:item intercept confounded with the residual"},
           {"check": "design.counterbalancing", "items_per_condition_per_list": 4, "status": "balanced"}]
    made.append(("Z07_latin_square_one_obs_per_cell",
                 write_fixture(root, "Z07_latin_square_one_obs_per_cell", rows, fields, design,
                               "y ~ cond + (1 + cond | subject) + (1 + cond | item) + (1 | subject:item)", exp,
                               {"subjects": n_sub, "items": n_item, "lists": 3, "seed": 20261107})))

    # Z08: class-randomised trial modelled with a school intercept only (L7-03)
    # Z09: same, with treatment mixed inside two declared randomisation units
    for fid, contaminate in (("Z08_crt_randomisation_level_omitted", False),
                             ("Z09_crt_treatment_mixed_within_unit", True)):
        rows = school_class_pupil(rng, J=4, K=6, n=20, reuse_labels=False)
        arms = {}
        for j in range(1, 5):
            perm = rng.permutation([0, 0, 0, 1, 1, 1])
            for k in range(1, 7):
                arms[f"S{j:02d}C{k}"] = int(perm[k - 1])
        mixed = []
        for idx, r in enumerate(rows):
            r["arm"] = "tutoring" if arms[r["class"]] else "control"
        if contaminate:
            for cls in ("S01C1", "S03C4"):
                members = [r for r in rows if r["class"] == cls]
                members[0]["arm"] = "control" if members[0]["arm"] == "tutoring" else "tutoring"
                mixed.append(cls)
        rows = add_y(rng, rows, [(("school",), np.sqrt(0.2)), (("class",), np.sqrt(0.15))])
        fields = [F("school"), F("class"), F("pupil"), F("arm", categories=["control", "tutoring"]), F("y", "number")]
        design = {"features": ["cluster_randomised"],
                  "units": [{"name": "school", "columns": ["school"]},
                            {"name": "class", "columns": ["class"], "nested_in": "school", "id_scope": "global"}],
                  "observation": {"unit": "pupil", "key": ["pupil"]},
                  "assignment": [{"column": "arm", "unit": "class", "blocks": ["school"],
                                  "scheme": "blocked_cluster", "control_level": "control"}]}
        exp = [{"check": "assignment.unit_in_random_part", "status": "flag",
                "note": "declared randomisation unit 'class' carries no random effect; school-only model rejected a true null in 31.7% of 300 replicates in the review simulation"},
               {"check": "assignment.design_df", "randomised_clusters": 24, "blocks": 4}]
        if contaminate:
            exp.append({"check": "assignment.constant_within_unit", "status": "error",
                        "units_with_mixed_assignment": mixed})
        made.append((fid, write_fixture(root, fid, rows, fields, design,
                                        "y ~ arm + (1 | school)", exp,
                                        {"J": 4, "K": 6, "n": 20, "var_school": 0.2, "var_class": 0.15,
                                         "contaminated_units": mixed, "seed": 20261107})))

    # Z11: families with one to three children (L1-09, L7-06); singletons are legitimate
    rows, sizes = [], rng.choice([1, 2, 3], size=80, p=[0.55, 0.35, 0.10])
    for f, sz in enumerate(sizes, start=1):
        for c in range(1, sz + 1):
            rows.append({"family": f"F{f:03d}", "child": f"F{f:03d}K{c}", "x": fmt(rng.normal())})
    rows = add_y(rng, rows, [(("family",), 0.7)])
    fields = [F("family"), F("child"), F("x", "number"), F("y", "number")]
    design = {"features": ["family"],
              "units": [{"name": "family", "columns": ["family"], "role": "family"}],
              "observation": {"unit": "family", "key": ["child"]}}
    n1, n2, n3 = int((sizes == 1).sum()), int((sizes == 2).sum()), int((sizes == 3).sum())
    exp = [{"check": "structure.cluster_sizes", "factor": "family", "J": 80, "singletons": n1, "pairs": n2,
            "triples": n3, "status": "info", "note": "singletons kept; only clusters with n >= 2 separate tau2 from sigma2"},
           {"check": "structure.informative_clusters_for_slope", "term": "(1 + x | family)",
            "clusters_with_n_ge_2": n2 + n3}]
    made.append(("Z11_families_singletons", write_fixture(root, "Z11_families_singletons", rows, fields, design,
                                                          "y ~ x + (1 + x | family)", exp,
                                                          {"families": 80, "size_probs": [0.55, 0.35, 0.10],
                                                           "seed": 20261107})))

    # Z13: crossed design whose incidence graph splits by group (L1-14, L7-18)
    rows = []
    for s in range(1, 21):
        grp = "g1" if s <= 10 else "g2"
        items = range(1, 9) if grp == "g1" else range(9, 17)
        for it in items:
            rows.append({"subject": f"s{s:02d}", "item": f"i{it:02d}", "group": grp})
    rows = add_y(rng, rows, [(("subject",), 0.5), (("item",), 0.5)])
    fields = [F("subject"), F("item"), F("group", categories=["g1", "g2"]), F("y", "number")]
    design = {"features": ["crossed_experiment"],
              "units": [{"name": "subject", "columns": ["subject"]}, {"name": "item", "columns": ["item"]}],
              "crossings": [{"units": ["subject", "item"]}],
              "observation": {"unit": "subject", "key": ["subject", "item"]}}
    exp = [{"check": "structure.connected_components", "pair": ["subject", "item"], "components": 2,
            "status": "flag", "note": "group is constant within each component: its effect rests on 2 components only"}]
    made.append(("Z13_disconnected_crossed", write_fixture(root, "Z13_disconnected_crossed", rows, fields, design,
                                                           "y ~ group + (1 | subject) + (1 | item)", exp,
                                                           {"subjects": 20, "items": 16, "seed": 20261107})))

    # Z17: duplicated keys from a double import, next to legitimate identical rows (L1-15, L7-19)
    rows = []
    for s in range(1, 11):
        for t in range(1, 21):
            rows.append({"subject": f"s{s:02d}", "trial": t, "cond": "A" if t % 2 else "B",
                         "acc": int(rng.random() < 0.8)})
    dup = [dict(r) for r in rows if r["subject"] == "s03" and r["trial"] <= 5]
    rows.extend(dup)
    fields = [F("subject"), F("trial", "integer"), F("cond", categories=["A", "B"]), F("acc", "integer")]
    design = {"units": [{"name": "subject", "columns": ["subject"]}],
              "observation": {"unit": "subject", "key": ["subject", "trial"]},
              "variables": {"acc": {"role": "outcome", "measurement": "binary"}}}
    no_trial = {}
    for r in rows:
        k = (r["subject"], r["cond"], r["acc"])
        no_trial[k] = no_trial.get(k, 0) + 1
    exp = [{"check": "keys.duplicate_declared_key", "status": "error", "key": ["subject", "trial"],
            "duplicated_keys": 5, "class": "identical values (possible double import)"},
           {"check": "keys.exact_duplicate_rows_without_trial", "status": "info",
            "rows_duplicated_if_trial_column_dropped": sum(v - 1 for v in no_trial.values()),
            "note": "structural duplicates without a key are expected in binary trial data"}]
    made.append(("Z17_duplicate_keys", write_fixture(root, "Z17_duplicate_keys", rows, fields, design,
                                                     "acc ~ cond + (1 + cond | subject)", exp,
                                                     {"subjects": 10, "trials": 20, "duplicated": "s03 trials 1-5",
                                                      "seed": 20261107})))
    total = 0
    for fid, n in made:
        size = os.path.getsize(os.path.join(root, fid, "data.csv"))
        total += size
        print(f"{fid}\t{n} rows\t{size} bytes")
    print(f"TOTAL data.csv bytes: {total}")


if __name__ == "__main__":
    main()
