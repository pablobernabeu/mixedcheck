"""Time statsmodels MixedLM on the crossed variance-component model (one all-data group), dense vs
use_sparse=True, and score each fit with my independent objective."""
import json, sys, os, time, warnings, resource
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm
from specs import M
import statsmodels.formula.api as smf

A, mid = sys.argv[1], sys.argv[2]
sparse = sys.argv[3] == "sparse"
sp = M[mid]
d = load(os.path.join(A, "data"), sp["data"]).copy()
d["_one"] = 1
vc = {"subj": "0 + C(subj)", "subj__cond": "0 + C(subj):cond", "item": "0 + C(item)", "item__cond": "0 + C(item):cond"}
best = {r["model"]: min(v for v in r["scores"].values() if v is not None)
        for r in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "fresh_fits_all.json")))}
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    t0 = time.perf_counter()
    md = smf.mixedlm("y ~ cond", d, groups=d["_one"], re_formula="0", vc_formula=vc, use_sparse=sparse)
    res = md.fit(reml=bool(sp["reml"]))
    tt = time.perf_counter() - t0
names = ["(Intercept)", "cond"]
X = x_from_names(d, names)
vn = list(md.exog_vc.names); vcomp = np.asarray(res.vcomp)
covs = [[[vcomp[vn.index(k)]]] for k in ("subj", "subj__cond", "item", "item__cond")]
obj = lmm(d, d["y"].to_numpy(float), X, sp["blocks"], covs, float(res.scale), beta=res.fe_params.values, reml=bool(sp["reml"]))
rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
print(f"{mid} use_sparse={sparse}: fit {tt:.1f} s, peak RSS {rss:.0f} MB, gap to best {obj - best[mid]:.2e}, converged={res.converged}")
