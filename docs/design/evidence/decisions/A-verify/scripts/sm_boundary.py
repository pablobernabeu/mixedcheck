"""statsmodels 0.15.0 MixedLM on the four boundary designs of report A, with the default fit and with
alternative optimiser settings; each result is scored with my independent objective and compared with the
best objective found by lme4/glmm/mixedlm (out/fresh_fits_all.json). Also tests the simulation facility
MixedLM.get_distribution(...).rvs and whether weights are rejected."""
import json, sys, os, warnings, time
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm
from specs import M
import statsmodels, statsmodels.formula.api as smf

A = sys.argv[1]
best = {r["model"]: min(v for v in r["scores"].values() if v is not None)
        for r in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "fresh_fits_all.json")))}
cases = {
    "nearsing_REML": ("y ~ t", "g", "1 + t", None, True),
    "nearsing_ML": ("y ~ t", "g", "1 + t", None, False),
    "nearsing_zcp_ML": ("y ~ t", "g", "1", {"g__t": "0 + t"}, False),
    "jq_REML": ("y ~ x1 + x2", "g", "1 + x1 + x2", None, True),
}
settings = [("default", {}), ("lbfgs", dict(method=["lbfgs"])), ("bfgs", dict(method=["bfgs"])),
            ("powell", dict(method=["powell"])), ("nm", dict(method=["nm"], maxiter=20000)),
            ("lbfgs_tight", dict(method=["lbfgs"], gtol=1e-10, maxiter=5000)),
            ("cg", dict(method=["cg"]))]
out = []
for mid, (fml, grp, ref, vc, reml) in cases.items():
    sp = M[mid]
    d = load(os.path.join(A, "data"), sp["data"])
    y = d[sp["y"]].to_numpy(float)
    for name, kw in settings:
        with warnings.catch_warnings(record=True) as wl:
            warnings.simplefilter("always")
            try:
                md = smf.mixedlm(fml, d, groups=d[grp], re_formula=ref, vc_formula=vc)
                t0 = time.perf_counter(); res = md.fit(reml=reml, **kw); tt = time.perf_counter() - t0
            except Exception as e:
                out.append(dict(model=mid, setting=name, error=repr(e)[:200])); print(mid, name, "ERROR", repr(e)[:120]); continue
        names = ["(Intercept)"] + [c for c in res.fe_params.index if c != "Intercept"]
        X = x_from_names(d, names)
        beta = res.fe_params.values
        cre = np.asarray(res.cov_re)
        if vc is None:
            covs = [cre]
        else:
            covs = [cre[:1, :1], [[float(np.asarray(res.vcomp)[0])]]]
        obj = lmm(d, y, X, sp["blocks"], covs, float(res.scale), beta=beta, reml=reml)
        gap = obj - best[mid]
        wmsg = sorted(set(w.category.__name__ for w in wl))
        out.append(dict(model=mid, setting=name, obj=obj, gap=gap, converged=bool(res.converged), warnings=wmsg,
                        reported_minus_obj=-2 * float(res.llf) - obj, time=tt))
        print(f"{mid:16s} {name:12s} gap {gap:9.2e}  converged={res.converged!s:5s}  warnings={wmsg}")
# weights rejected?
d = load(os.path.join(A, "data"), "weighted")
try:
    smf.mixedlm("y ~ x", d, groups=d["g"], weights=d["w"]).fit()
    print("weights: accepted")
except Exception as e:
    print("weights:", type(e).__name__, str(e)[:120])
# simulation facility on a fitted model (sleepstudy REML)
d = load(os.path.join(A, "data"), "sleep")
md = smf.mixedlm("Reaction ~ Days", d, groups=d["Subject"], re_formula="1 + Days")
res = md.fit()
dist = md.get_distribution(res.params, res.scale, None)
sims = np.array([dist.rvs(len(d), rng=s) for s in range(2000)])
print("statsmodels get_distribution().rvs works: n_sims", sims.shape, "sim var/obs var", float(sims.var(axis=0).mean() / d["Reaction"].var()))
# compare the implied marginal variance with Z G Z' + s2 I diagonal
G = np.asarray(res.cov_re); s2 = res.scale
T = np.column_stack([np.ones(len(d)), d["Days"].to_numpy(float)])
implied = np.einsum("ij,jk,ik->i", T, G, T) + s2
print("mean |sim var / implied var - 1| =", float(np.mean(np.abs(sims.var(axis=0) / implied - 1))))
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "sm_boundary.json"), "w"), indent=1)
print("statsmodels", statsmodels.__version__)
