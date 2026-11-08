"""statsmodels BinomialBayesMixedGLM on cbpp (expanded to Bernoulli rows): VB and MAP vs lme4/glmmTMB Laplace."""
import json, sys, os, warnings
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, glmm
from statsmodels.genmod.bayes_mixed_glm import BinomialBayesMixedGLM
A = sys.argv[1]
d = load(os.path.join(A, "data"), "cbpp")
rows = []
for _, r in d.iterrows():
    for j in range(int(r["size"])):
        rows.append(dict(herd=r["herd"], period=r["period"], yb=int(j < int(r["incidence"]))))
db = pd.DataFrame(rows)
R = {(r["model"], r["engine"]): r for r in json.load(open(os.path.join(A, "r_reference.json")))["results"]}
lme = R[("cbpp_laplace", "lme4")]; tmb = R[("cbpp_laplace", "glmmTMB")]
names = list(lme["beta"].keys()); X = x_from_names(d, names); y = d["incidence"].to_numpy(float); m = d["size"].to_numpy(float)
best = glmm(d, y, X, [("herd", ["1"])], [np.atleast_2d(tmb["re"]["herd"]["cov"])], np.array(list(tmb["beta"].values())), "binomial", m=m)
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    md = BinomialBayesMixedGLM.from_formula("yb ~ C(period)", {"herd": "0 + C(herd)"}, db)
    vb = md.fit_vb(); mp = md.fit_map()
k = md.k_fep
for lab, beta, sd, se in (("VB", vb.fe_mean, np.exp(vb.vcp_mean[0]), vb.fe_sd),
                          ("MAP", mp.params[:k], np.exp(mp.params[k]), np.sqrt(np.diag(mp.cov_params())[:k]))):
    obj = glmm(d, y, X, [("herd", ["1"])], [[[sd ** 2]]], beta, "binomial", m=m)
    print(f"{lab}: herd SD {sd:.4f} (glmmTMB {np.sqrt(tmb['re']['herd']['cov'][0][0]):.4f}); intercept SE/SD {se[0]:.4f} vs lme4 SE {lme['se']['(Intercept)']:.4f} "
          f"({se[0] / lme['se']['(Intercept)'] - 1:+.0%}); Laplace objective gap {obj - best:.3f}")
print("rows (Bernoulli):", len(db))
