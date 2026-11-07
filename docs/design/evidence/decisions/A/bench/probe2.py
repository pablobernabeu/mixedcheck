"""Behaviour probes relevant to the diagnostics contract.
(1) conditional variances of random effects vs lme4 (sleep_REML, school_REML, cbpp_laplace)
(2) rank-deficient X: which column each engine drops
(3) default reference level for an unordered string factor
"""
import json, sys, os, warnings
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import load
warnings.simplefilter("ignore")
R = json.load(open("r_reference.json"))
lme = {r["model"]: r for r in R["results"] if r["engine"] == "lme4"}
out = {}

# ---------------- (1) condvar
def cmp(name, ref_levels, ref_vals, ref_cv, eng_levels, eng_vals, eng_cv):
    idx = [list(eng_levels).index(l) for l in ref_levels]
    ev = np.asarray(eng_vals)[idx]; ec = np.asarray(eng_cv)[idx]
    rv = np.asarray(ref_vals); rc = np.asarray(ref_cv)
    return dict(max_rel_blup=float(np.max(np.abs(ev - rv)) / np.max(np.abs(rv))),
                max_rel_condvar=float(np.max(np.abs(ec / rc - 1))))

import glmm, mixedlm as mlm
import statsmodels.formula.api as smf
for mid, fml, g in [("sleep_REML", "Reaction ~ Days + (Days | Subject)", "Subject"),
                    ("school_REML", "y ~ x + w + (1 + x | school) + (1 | schoolclass)", "schoolclass")]:
    data = "sleep" if mid.startswith("sleep") else "school"
    d = load("data", data)
    rf = lme[mid]["ranef_first"]
    assert rf["group"] == g, rf["group"]
    ref_levels = rf["levels"]; ref_vals = np.array(rf["values"], float); ref_cv = np.array(rf["condvar_diag"], float)
    if ref_cv.shape[0] == 1 and ref_cv.shape[1] == len(ref_levels): ref_cv = ref_cv.T   # R t() of a vector for q = 1
    if ref_vals.ndim == 1: ref_vals = ref_vals[:, None]
    # glmm
    f = glmm.fit(d, fml)
    blk = [b for b in f.ranef_blocks if b["group"] == g][0]
    pv = np.asarray(blk["postvar"]); cvd = np.array([np.diag(np.atleast_2d(m)) for m in pv])
    out[f"condvar:{mid}:glmm"] = cmp(mid, ref_levels, ref_vals, ref_cv, [str(x) for x in blk["levels"]], np.asarray(blk["values"]), cvd)
    # mixedlm
    m = mlm.lmer(fml, d)
    rr = m.ranef(condVar=True)
    # mixedlm returns {term: array} without level labels; assume sorted level order (checked by the BLUP match)
    terms = list(rr[g].keys())
    vals = np.column_stack([rr[g][t] for t in terms])
    cvd = np.column_stack([rr.condVar[g][t] for t in terms])
    lev = sorted(d[g].unique())
    out[f"condvar:{mid}:mixedlm"] = cmp(mid, ref_levels, ref_vals, ref_cv, [str(x) for x in lev], vals, cvd)
    out[f"condvar:{mid}:mixedlm"]["note"] = "ranef/condVar returned as {term: array} without level labels; condVar gives per-term variances only"
    # statsmodels (only representable layouts)
    if mid == "sleep_REML":
        r = smf.mixedlm("Reaction ~ Days", d, groups=d["Subject"], re_formula="~Days").fit(reml=True)
        lev = list(r.random_effects.keys())
        vals = np.array([r.random_effects[k].values for k in lev])
        cvd = np.array([np.diag(np.asarray(r.random_effects_cov[k])) for k in lev])
        out[f"condvar:{mid}:statsmodels"] = cmp(mid, ref_levels, ref_vals, ref_cv, [str(x) for x in lev], vals, cvd)

# ---------------- (2) rank-deficient X and (3) level order
d = load("data", "sleep").copy()
d["a"] = d["Days"]; d["b"] = (d["Days"] % 3).astype(float); d["ab"] = d["a"] + d["b"]
rk = {}
try:
    f = glmm.fit(d, "Reaction ~ a + b + ab + (1 | Subject)")
    rk["glmm"] = dict(names=f.names, aliased=np.asarray(f.aliased).tolist(), beta=np.round(f.beta, 6).tolist())
except Exception as e:
    rk["glmm"] = f"{type(e).__name__}: {e}"
try:
    m = mlm.lmer("Reaction ~ a + b + ab + (1 | Subject)", d)
    rk["mixedlm"] = dict(fixef={k: round(float(v), 6) for k, v in m.fixef().items()})
except Exception as e:
    rk["mixedlm"] = f"{type(e).__name__}: {str(e)[:200]}"
try:
    r = smf.mixedlm("Reaction ~ a + b + ab", d, groups=d["Subject"]).fit()
    rk["statsmodels"] = dict(fe=np.round(r.fe_params.values, 6).tolist(), names=list(r.fe_params.index), converged=bool(r.converged))
except Exception as e:
    rk["statsmodels"] = f"{type(e).__name__}: {str(e)[:200]}"
out["rank_deficient_X"] = rk

d2 = load("data", "sleep").copy()
lab = np.array(["b", "a", "C"])
d2["f"] = lab[d2.index.values % 3]
lv = {}
try:
    f = glmm.fit(d2, "Reaction ~ f + (1 | Subject)"); lv["glmm"] = f.names
except Exception as e:
    lv["glmm"] = str(e)[:200]
try:
    m = mlm.lmer("Reaction ~ f + (1 | Subject)", d2); lv["mixedlm"] = list(m.fixef().keys())
except Exception as e:
    lv["mixedlm"] = str(e)[:200]
try:
    r = smf.mixedlm("Reaction ~ f", d2, groups=d2["Subject"]).fit(); lv["statsmodels"] = list(r.fe_params.index)
except Exception as e:
    lv["statsmodels"] = str(e)[:200]
out["string_factor_reference_level"] = lv
d2.to_csv("out/levels_probe.csv", index=False); d.to_csv("out/rank_probe.csv", index=False)
json.dump(out, open("out/probe2.json", "w"), indent=1, default=str)
print(json.dumps(out, indent=1, default=str))
