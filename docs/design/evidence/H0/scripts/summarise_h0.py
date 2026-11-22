"""Summarise the H0 pilot runs against the earlier evidence runs.

Usage: python -I summarise_h0.py RUN_DIR RESULTS_DIR OUT_DIR

RUN_DIR      the copy of docs/design/evidence/decisions in which the pilot ran
RESULTS_DIR  the project-space folder with the V1 pilot results
OUT_DIR      where the summary tables are written

Every table pairs the earlier value, as stored in the repository's evidence, with the
H0 value, so that the effect of current engines (and of the ARC hardware) can be read
directly. Inputs that are not there yet (for example while the B/sim job runs) are
skipped and reported, so the script can be rerun when they appear.
"""
import json
import math
import os
import re
import sys

import pandas as pd

run, results, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
log = []


def path(*p):
    return os.path.join(run, *p)


def classify(gap, ref_dev):
    """The objective-match classes of A/bench/compare.py (engine_summary.md)."""
    if gap is None or (isinstance(gap, float) and math.isnan(gap)):
        return None
    if gap <= max(1e-4, 1e-9 * abs(ref_dev)):
        return "at_optimum"
    return "near" if gap <= 1e-2 else "worse"


# ---------------------------------------------------------------- benchmark
def bench_rows(f):
    rows = json.load(open(f))
    d = pd.DataFrame(rows)
    d["class"] = [classify(g, r) if s == "ok" else None
                  for g, r, s in zip(d.get("obj_gap"), d.get("ref_dev"), d["status"])]
    keep = ["model", "engine", "status", "obj_gap", "class", "reported_minus_ref", "max_abs_dbeta_in_se",
            "max_rel_dse", "time_median", "time_ratio_vs_lme4", "peak_rss_mb"]
    return d[[c for c in keep if c in d.columns]]


new_f = path("A", "bench", "comparison_rows.json")
old_f = path("A", "bench", "repo_copy", "comparison_rows.json")
if os.path.exists(new_f) and os.path.exists(old_f):
    new, old = bench_rows(new_f), bench_rows(old_f)
    m = old.merge(new, on=["model", "engine"], how="outer", suffixes=("_earlier", "_h0"))
    m.sort_values(["engine", "model"]).to_csv(os.path.join(out, "bench_models_earlier_vs_h0.csv"), index=False)
    changed = m[m["class_earlier"].fillna("-") != m["class_h0"].fillna("-")]
    changed.to_csv(os.path.join(out, "bench_class_changes.csv"), index=False)

    def per_engine(d):
        ok = d[d["status"] == "ok"]
        g = ok.groupby("engine")
        return pd.DataFrame({
            "ok": g.size(),
            "at_optimum": g["class"].apply(lambda s: (s == "at_optimum").sum()),
            "near": g["class"].apply(lambda s: (s == "near").sum()),
            "worse": g["class"].apply(lambda s: (s == "worse").sum()),
            "max_gap_at_optimum": g.apply(lambda x: x.loc[x["class"] == "at_optimum", "obj_gap"].max()),
            "max_abs_dbeta_in_se": g["max_abs_dbeta_in_se"].max(),
            "max_rel_dse": g["max_rel_dse"].max(),
            "median_time_ratio_vs_lme4": g["time_ratio_vs_lme4"].median(),
        })
    pe = per_engine(old).merge(per_engine(new), left_index=True, right_index=True, how="outer",
                               suffixes=("_earlier", "_h0"))
    pe.to_csv(os.path.join(out, "bench_engines_earlier_vs_h0.csv"))
    # Offsets: an engine's reported objective (-2 log-likelihood or criterion) minus the common
    # reference objective at its own estimates. A constant offset per engine and model class is
    # what the expected-disagreement registry records; a change between runs is a finding.
    if "reported_minus_ref_h0" in m.columns:
        off = m.dropna(subset=["reported_minus_ref_h0"])[
            ["engine", "model", "reported_minus_ref_earlier", "reported_minus_ref_h0"]].copy()
        off["change"] = off["reported_minus_ref_h0"] - off["reported_minus_ref_earlier"]
        off.sort_values(["engine", "model"]).to_csv(os.path.join(out, "bench_offsets_earlier_vs_h0.csv"),
                                                    index=False)
        log.append(f"offsets: {len(off)} engine-model pairs, largest absolute change "
                   f"{off['change'].abs().max():.3g}")
    log.append(f"benchmark: {len(new)} H0 rows, {len(old)} earlier rows, {len(changed)} class changes")
else:
    log.append("benchmark: comparison_rows.json missing, skipped")

# peak memory of each engine process (run_one.py records ru_maxrss)
outs = path("A", "bench", "out")
if os.path.isdir(outs):
    rs = []
    for f in sorted(os.listdir(outs)):
        if f.endswith(".json"):
            r = json.load(open(os.path.join(outs, f)))
            rs.append({"engine": r.get("engine"), "model": r.get("model"), "status": r.get("status"),
                       "peak_rss_mb": r.get("peak_rss_mb"), "wall_total_s": r.get("wall_total_s")})
    rs = pd.DataFrame(rs)
    rs.to_csv(os.path.join(out, "bench_engine_memory.csv"), index=False)
    rs.groupby("engine")["peak_rss_mb"].agg(["median", "max"]).to_csv(
        os.path.join(out, "bench_engine_memory_by_engine.csv"))
    log.append(f"benchmark memory: {len(rs)} engine runs")

# ---------------------------------------------------------------- V1 pilot
v1_new = os.path.join(results, "V1a-pilot_summary.csv")
v1_old = path("F", "slurm", "pilot_V1a_summary.csv")
if os.path.exists(v1_new):
    a, b = pd.read_csv(v1_old), pd.read_csv(v1_new)
    m = a.merge(b, on=["cell_id", "J", "m", "cv", "icc", "tau1"], suffixes=("_earlier", "_h0"))
    flags = ["singular_lme4", "conv_msg", "bartlett_raw_flag", "cover_x", "min_eig_cor_lt_1e4"]
    outv = m[["cell_id", "J", "m", "cv", "icc", "tau1", "n_done_earlier", "n_done_h0",
              "mean_elapsed_s_earlier", "mean_elapsed_s_h0"]].copy()
    outv["time_ratio_h0_to_earlier"] = outv["mean_elapsed_s_h0"] / outv["mean_elapsed_s_earlier"]
    for f in flags:
        outv[f + "_earlier"] = m[f + "_earlier"]
        outv[f + "_h0"] = m[f + "_h0"]
    outv.to_csv(os.path.join(out, "v1_pilot_earlier_vs_h0.csv"), index=False)
    log.append("V1 pilot: time ratio per cell " +
               ", ".join(f"{x:.3f}" for x in outv["time_ratio_h0_to_earlier"]) +
               f"; flags identical: {all((m[f + '_earlier'] == m[f + '_h0']).all() for f in flags)}")
else:
    log.append("V1 pilot: summary missing, skipped")

# ---------------------------------------------------------------- timing grids
for name, keys in [("timing_raw.csv", ["design", "size", "task", "engine_family"]),
                   ("timing_raw2.csv", ["design", "size", "task", "engine_family"])]:
    fo, fn = path("F", "timing", "out", name), path("F", "timing", "out_h0", name)
    if os.path.exists(fn):
        a, b = pd.read_csv(fo), pd.read_csv(fn)
        agg = {"elapsed": ["count", "median"]}
        if "maxmem_mb" in b.columns:
            agg["maxmem_mb"] = "max"
        ga, gb = a.groupby(keys).agg(agg), b.groupby(keys).agg(agg)
        ga.columns = ["_".join(c) for c in ga.columns]
        gb.columns = ["_".join(c) for c in gb.columns]
        m = ga.merge(gb, left_index=True, right_index=True, how="outer", suffixes=("_earlier", "_h0"))
        m["median_ratio_h0_to_earlier"] = m["elapsed_median_h0"] / m["elapsed_median_earlier"]
        m.to_csv(os.path.join(out, name.replace(".csv", "_earlier_vs_h0.csv")))
        both = m.dropna(subset=["median_ratio_h0_to_earlier"])
        log.append(f"{name}: {len(both)} groups timed in both runs, median of the ratios "
                   f"{both['median_ratio_h0_to_earlier'].median():.3f}")
    else:
        log.append(f"{name}: H0 output missing, skipped")


def parse_lme4_timing(f):
    d = {}
    for line in open(f):
        mm = re.match(r"^(\S.*?)\s+([0-9.]+) s\s*$", line.strip())
        if mm:
            d[mm.group(1).strip()] = float(mm.group(2))
    return d


lo = os.path.join(run, "A-verify", "out", "lme4_timing.txt")
ln = path("F", "timing", "out_h0", "lme4_timing.txt")
if os.path.exists(ln):
    a, b = parse_lme4_timing(lo), parse_lme4_timing(ln)
    t = pd.DataFrame({"fit": list(a), "seconds_earlier": list(a.values()),
                      "seconds_h0": [b.get(k) for k in a]})
    t["ratio_h0_to_earlier"] = t["seconds_h0"] / t["seconds_earlier"]
    t.to_csv(os.path.join(out, "lme4_timing_earlier_vs_h0.csv"), index=False)
    log.append("lme4_timing: " + ", ".join(f"{r.fit} {r.ratio_h0_to_earlier:.2f}" for r in t.itertuples()))

# ---------------------------------------------------------------- B/sim
sim_pairs = [("sim1_summary_small.csv", ["S", "I", "tau1", "beta", "strategy"]),
             ("sim1_summary_large.csv", ["S", "I", "tau1", "beta", "strategy"]),
             ("sim2_summary.csv", ["J", "tau1", "b3", "n", "strategy"]),
             ("sim3_summary.csv", ["S", "m", "tau", "r", "beta1", "model"])]
for name, keys in sim_pairs:
    fo, fn = path("B", "sim", "out_repo", name), path("B", "sim", "out", name)
    if os.path.exists(fo) and os.path.exists(fn):
        a, b = pd.read_csv(fo), pd.read_csv(fn)
        m = a.merge(b, on=keys, how="outer", suffixes=("_earlier", "_h0"))
        m.to_csv(os.path.join(out, name.replace(".csv", "_earlier_vs_h0.csv")), index=False)
        log.append(f"B/sim {name}: {len(m)} rows merged on {keys}")
    else:
        log.append(f"B/sim {name}: not available yet")
for name in ["sim4_zcp_coding.txt", "sim5_reml_masking.txt", "sim6_singular_df.txt", "sim23_summary.txt"]:
    fn = path("B", "sim", "out", name)
    if os.path.exists(fn):
        with open(os.path.join(out, name.replace(".txt", "_h0.txt")), "w") as fh:
            fh.write(open(fn).read())

with open(os.path.join(out, "summary_log.txt"), "w") as fh:
    fh.write("\n".join(log) + "\n")
print("\n".join(log))
