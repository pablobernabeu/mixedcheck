"""Multi-start global check of the 'best known objective' for the small boundary designs: profiled ML/REML
deviance over the relative Cholesky factor theta (sigma^2 and beta profiled), 200 random starts, Nelder-Mead
then L-BFGS-B polish. Written independently from report A's code."""
import json, sys, os
import numpy as np
from scipy import optimize
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names
from specs import M

A = sys.argv[1]
best = {r["model"]: min(v for v in r["scores"].values() if v is not None)
        for r in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "fresh_fits_all.json")))}

def zt(d, g, terms):
    lev = sorted(d[g].unique()); idx = d[g].map({l: i for i, l in enumerate(lev)}).to_numpy()
    T = np.column_stack([np.ones(len(d)) if t == "1" else d[t].to_numpy(float) for t in terms])
    return idx, T, len(lev)

def make_dev(mid):
    sp = M[mid]; d = load(os.path.join(A, "data"), sp["data"])
    y = d[sp["y"]].to_numpy(float)
    names = ["(Intercept)"] + [c for c in {"nearsing": ["t"], "jq": ["x1", "x2"], "sleep": ["Days"]}[sp["data"]]]
    X = x_from_names(d, names); n, p = X.shape
    blocks = [zt(d, g, terms) for g, terms in sp["blocks"]]
    sizes = [T.shape[1] for _, T, _ in blocks]
    def unpack(th):
        Ls, k = [], 0
        for q in sizes:
            L = np.zeros((q, q)); L[np.tril_indices(q)] = th[k:k + q * (q + 1) // 2]; k += q * (q + 1) // 2; Ls.append(L)
        return Ls
    def dev(th):
        Vt = np.eye(n)
        for (idx, T, J), L in zip(blocks, unpack(th)):
            S = L @ L.T
            for j in range(J):
                r = idx == j
                Vt[np.ix_(r, r)] += T[r] @ S @ T[r].T
        c = np.linalg.cholesky(Vt)
        ld = 2 * np.sum(np.log(np.diag(c)))
        Vi = np.linalg.inv(Vt)
        XtVX = X.T @ Vi @ X
        b = np.linalg.solve(XtVX, X.T @ Vi @ y); r = y - X @ b; pw = r @ Vi @ r
        if sp["reml"]:
            s2 = pw / (n - p)
            return (n - p) * np.log(2 * np.pi * s2) + ld + np.linalg.slogdet(XtVX)[1] + (n - p)
        s2 = pw / n
        return n * np.log(2 * np.pi * s2) + ld + n
    npar = sum(q * (q + 1) // 2 for q in sizes)
    return dev, npar

rng = np.random.default_rng(2026)
for mid in ["nearsing_REML", "nearsing_ML", "nearsing_zcp_ML", "jq_REML", "sleep_REML"]:
    dev, k = make_dev(mid)
    vals = []
    for s in range(200):
        x0 = rng.normal(0, 1.5, k)
        r1 = optimize.minimize(dev, x0, method="Nelder-Mead", options=dict(maxiter=20000, xatol=1e-10, fatol=1e-12))
        r2 = optimize.minimize(dev, r1.x, method="L-BFGS-B")
        vals.append(min(r1.fun, r2.fun))
    vals = np.array(vals)
    print(f"{mid:16s} multistart min {vals.min():.8f} | best engine {best[mid]:.8f} | min - best {vals.min() - best[mid]:+.2e} | "
          f"share of starts within 1e-4 of best: {np.mean(vals - best[mid] <= 1e-4):.2f}")
