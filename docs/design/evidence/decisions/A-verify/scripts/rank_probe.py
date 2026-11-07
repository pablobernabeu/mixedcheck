"""Rank-deficient X (x3 = x1 + x2): which column does each engine drop, and what does it flag?"""
import sys, os, warnings
import numpy as np, pandas as pd
rng = np.random.default_rng(11)
n, J = 240, 24
g = np.repeat([f"g{j:02d}" for j in range(J)], n // J)
x1, x2 = rng.normal(size=n), rng.normal(size=n)
d = pd.DataFrame(dict(g=g, x1=x1, x2=x2, x3=x1 + x2))
d["y"] = 1 + 0.5 * x1 - 0.3 * x2 + rng.normal(0, 1, J)[pd.factorize(d.g)[0]] + rng.normal(size=n)
out = sys.argv[1]
d.to_csv(out, index=False)
import glmm, mixedlm as mlm, statsmodels.formula.api as smf
with warnings.catch_warnings(record=True) as wl:
    warnings.simplefilter("always")
    f = glmm.fit(d, "y ~ x1 + x2 + x3 + (1 | g)", "gaussian", reml=True)
print("glmm   :", dict(zip(f.names, np.round(f.beta, 4))), "aliased:", f.diagnostics.get("aliased"), "| warnings:", sorted(set(w.category.__name__ for w in wl)))
with warnings.catch_warnings(record=True) as wl:
    warnings.simplefilter("always")
    r = mlm.lmer("y ~ x1 + x2 + x3 + (1 | g)", d)
print("mixedlm:", {k: round(v, 4) for k, v in r.fixef().items()}, "| warnings:", sorted(set(str(w.message)[:80] for w in wl)))
with warnings.catch_warnings(record=True) as wl:
    warnings.simplefilter("always")
    s = smf.mixedlm("y ~ x1 + x2 + x3", d, groups=d["g"]).fit()
print("statsm.:", dict(np.round(s.fe_params, 4)), "converged:", s.converged, "| bse:", list(np.round(s.bse_fe, 3)), "| warnings:", sorted(set(w.category.__name__ for w in wl)))
