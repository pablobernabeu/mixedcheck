"""Evaluate my independent objective at the lme4 / glmmTMB estimates stored in report A's r_reference.json
and compare with (a) the engine's reported -2 logLik and (b) report A's common objective (comparison_rows.json)."""
import json, sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm, glmm
from specs import M

A = sys.argv[1]  # report A bench dir
R = json.load(open(os.path.join(A, "r_reference.json")))
rows = json.load(open(os.path.join(A, "comparison_rows.json")))
aref = {(r["model"], r["engine"]): r.get("ref_dev") for r in rows if r.get("status") == "ok"}

def covs_from_r(spec, r):
    out, used = [], set()
    for g, terms in spec["blocks"]:
        for name, v in r["re"].items():
            ts = v["terms"] if isinstance(v["terms"], list) else [v["terms"]]
            ts = ["1" if t == "(Intercept)" else t for t in ts]
            if name not in used and name.split(".")[0] == g and ts == terms:
                used.add(name); out.append(np.atleast_2d(np.array(v["cov"], float))); break
        else:
            raise KeyError((g, terms))
    return out

cache = {}
print(f"{'model':20s} {'engine':8s} {'my objective':>16s} {'A common obj':>16s} {'mine - A':>10s} {'reported - mine':>15s}")
res = []
for r in R["results"]:
    sp = M[r["model"]]
    d = cache.setdefault(sp["data"], load(os.path.join(A, "data"), sp["data"]))
    names = list(r["beta"].keys()); beta = np.array(list(r["beta"].values()), float)
    X = x_from_names(d, names)
    covs = covs_from_r(sp, r)
    y = d[sp["y"]].to_numpy(float)
    if sp["family"] == "gaussian":
        w = d[sp["weights"]].to_numpy(float) if sp["weights"] else None
        mine = lmm(d, y, X, sp["blocks"], covs, r["sigma"] ** 2, beta=beta, reml=sp["reml"], w=w)
    else:
        m = d[sp["trials"]].to_numpy(float) if sp["trials"] else None
        off = d[sp["offset"]].to_numpy(float) if sp["offset"] else None
        mine = glmm(d, y, X, sp["blocks"], covs, beta, sp["family"], m=m, off=off, nagq=sp["nagq"])
    a = aref.get((r["model"], "R:" + r["engine"]))
    rep = -2 * r["logLik"] if r.get("logLik") is not None else float("nan")
    res.append(dict(model=r["model"], engine=r["engine"], mine=mine, A=a, reported=rep))
    print(f"{r['model']:20s} {r['engine']:8s} {mine:16.6f} {a if a is not None else float('nan'):16.6f} "
          f"{(mine - a) if a is not None else float('nan'):10.2e} {rep - mine:15.3e}")
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "check_ref_objective.json"), "w"), indent=1)
diffs = [abs(x["mine"] - x["A"]) for x in res if x["A"] is not None]
print("max |mine - A common objective| over", len(diffs), "rows:", max(diffs))
