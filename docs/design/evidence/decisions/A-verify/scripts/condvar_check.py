"""Which conditional variance does each engine report? Compare with the exact beta-fixed conditional
covariance (Z'R^-1Z + G^-1)^-1 and with the PEV that includes beta uncertainty, at each engine's own estimates.
sleepstudy, Reaction ~ Days + (Days | Subject), REML."""
import sys, os, warnings
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load
import glmm, mixedlm as mlm, statsmodels.formula.api as smf
d = load(sys.argv[1], "sleep")
lev = sorted(d.Subject.unique())
y = d.Reaction.to_numpy(float); X = np.column_stack([np.ones(len(d)), d.Days.to_numpy(float)])
def truth(G, s2):
    Z = np.zeros((len(d), 2 * len(lev)))
    idx = d.Subject.map({l: i for i, l in enumerate(lev)}).to_numpy()
    Z[np.arange(len(d)), 2 * idx] = 1; Z[np.arange(len(d)), 2 * idx + 1] = d.Days
    Gb = np.kron(np.eye(len(lev)), G)
    V = Z @ Gb @ Z.T + s2 * np.eye(len(d)); Vi = np.linalg.inv(V)
    P = Vi - Vi @ X @ np.linalg.solve(X.T @ Vi @ X, X.T @ Vi)
    fixed = Gb - Gb @ Z.T @ Vi @ Z @ Gb
    pev = Gb - Gb @ Z.T @ P @ Z @ Gb
    blk = lambda M, j: M[2 * j:2 * j + 2, 2 * j:2 * j + 2]
    return [blk(fixed, j) for j in range(len(lev))], [blk(pev, j) for j in range(len(lev))]
def report(name, eng_cv, G, s2):
    fx, pv = truth(G, s2)
    e_f = max(np.max(np.abs(np.asarray(c)[np.diag_indices(len(np.atleast_2d(c)))] / np.diag(f) - 1)) for c, f in zip(eng_cv, fx))
    e_p = max(np.max(np.abs(np.asarray(c)[np.diag_indices(len(np.atleast_2d(c)))] / np.diag(p) - 1)) for c, p in zip(eng_cv, pv))
    print(f"{name:12s} max rel diff of reported cond. variances vs beta-fixed: {e_f:.1e} | vs PEV incl. beta: {e_p:.1e}")
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    f = glmm.fit(d, "Reaction ~ Days + (Days | Subject)", "gaussian", reml=True)
    v = np.asarray(f.varcorr[0]); G = np.array([[v[0], v[1]], [v[1], v[2]]])
    blk = [b for b in f.ranef_blocks if b["group"] == "Subject"][0]
    lab = [str(x) for x in blk["levels"]]
    pv = [np.atleast_2d(np.asarray(m, float)) for m in blk["postvar"]]
    print("glmm ranef_blocks postvar per level shape:", pv[0].shape)
    order = [lab.index(l) for l in lev]
    blocks = pv
    report("glmm", [blocks[i] for i in order], G, float(f.dispersion))
    r = mlm.lmer("Reaction ~ Days + (Days | Subject)", d)
    gm = list(r.VarCorr().groups.values())[0]
    re = r.ranef(condVar=True)
    print("mixedlm ranef(condVar=True) type:", type(re))
    try:
        cvm = re.condVar if hasattr(re, "condVar") else None
        print("  mixedlm condVar attr:", type(cvm), {k: np.shape(v) for k, v in (cvm.items() if isinstance(cvm, dict) else [])})
        k0 = list(cvm.keys())[0]; C = np.asarray(cvm[k0], float)
        # per-term variances only: shape (J, q) expected
        blocks_m = [np.diag(C[j]) if C.ndim == 2 else C[j] for j in range(C.shape[0])]
        report("mixedlm", blocks_m, np.asarray(gm.cov, float), float(r.sigma) ** 2)
    except Exception as e:
        print("  mixedlm condVar access failed:", repr(e)[:200])
    s = smf.mixedlm("Reaction ~ Days", d, groups=d["Subject"], re_formula="1 + Days").fit()
    rec = s.random_effects_cov
    report("statsmodels", [np.asarray(rec[l]) for l in lev], np.asarray(s.cov_re), float(s.scale))
