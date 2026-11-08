"""Does a row-major misreading of glmm's 3x3 varcorr (jq_REML) change the reference REML criterion, and by how much?"""
import sys, os, warnings
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm
import glmm
warnings.simplefilter("ignore")
d = load(sys.argv[1], "jq")
f = glmm.fit(d, "y ~ x1 + x2 + (1 + x1 + x2 | g)", "gaussian", reml=True)
v = np.asarray(f.varcorr[0], float); q = 3
def unpack(order):
    C = np.zeros((q, q)); k = 0
    pairs = [(r, c) for c in range(q) for r in range(c, q)] if order == "col" else [(r, c) for r in range(q) for c in range(r + 1)]
    for r, c in pairs:
        C[r, c] = C[c, r] = v[k]; k += 1
    return C
X = x_from_names(d, ["(Intercept)", "x1", "x2"]); y = d.y.to_numpy(float)
rep = -2 * f.loglik
for o in ("col", "row"):
    C = unpack(o)
    ev = np.linalg.eigvalsh(C)
    try:
        obj = lmm(d, y, X, [("g", ["1", "x1", "x2"])], [C], float(f.dispersion), reml=True)
        print(f"{o}-major unpack: min eigenvalue {ev.min():.3e}; reference REML criterion - glmm reported = {obj - rep:+.3e}")
    except Exception as e:
        print(f"{o}-major unpack: min eigenvalue {ev.min():.3e}; evaluation failed: {e!r}")
print("vech:", np.round(v, 4))
