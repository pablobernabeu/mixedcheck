"""Exact conditional variances of random effects for school_REML at lme4's estimates.
(a) Var(b | y, beta = beta_hat): sigma2 * Lam (Lam'Z'Z Lam + I)^-1 Lam'
(b) PEV including beta uncertainty: sigma2 * Lam [C^-1]_uu Lam', C = MME in spherical form."""
import json, sys, numpy as np, pandas as pd, glmm, mixedlm as mlm
sys.path.insert(0, ".")
from common import S, design, _lambda
from rmap import r_est
R = json.load(open("r_reference.json"))
r = [x for x in R["results"] if x["model"] == "school_REML" and x["engine"] == "lme4"][0]
sp = S["school_REML"]; des = design(sp, "data"); est = r_est(sp, r)
X = des["X"]; Z = np.hstack([b["Z"] for b in des["blocks"]]); s2 = est["sigma2"]
Lam = _lambda(des["blocks"], est["covs"], scale=s2)
ZL = Z @ Lam; q = ZL.shape[1]
A = np.linalg.inv(ZL.T @ ZL + np.eye(q))
Va = s2 * Lam @ A @ Lam.T
C = np.block([[X.T @ X, X.T @ ZL], [ZL.T @ X, ZL.T @ ZL + np.eye(q)]])
Ci = np.linalg.inv(C); p = X.shape[1]
Vb = s2 * Lam @ Ci[p:, p:] @ Lam.T
# schoolclass block is the second block (after school's 2*J columns)
b0 = des["blocks"][0]; b1 = des["blocks"][1]
off = b0["J"] * b0["k"]
da = np.diag(Va)[off:off + b1["J"]]; db = np.diag(Vb)[off:off + b1["J"]]
lev = b1["levels"]
rf = r["ranef_first"]; ref = np.array(rf["condvar_diag"], float)
if ref.shape[0] == 1 and ref.shape[1] == len(rf["levels"]): ref = ref.T
ref = ref[:, 0]
idx = [lev.index(l) for l in rf["levels"]]
da, db = da[idx], db[idx]
d = des["d"]
g = glmm.fit(d, "y ~ x + w + (1 + x | school) + (1 | schoolclass)")
blk = [b for b in g.ranef_blocks if b["group"] == "schoolclass"][0]
gl = [str(x) for x in blk["levels"]]; gv = np.array([np.atleast_2d(m)[0, 0] for m in blk["postvar"]])
gv = gv[[gl.index(l) for l in rf["levels"]]]
m = mlm.lmer("y ~ x + w + (1 + x | school) + (1 | schoolclass)", d)
mv = np.asarray(m.ranef(condVar=True).condVar["schoolclass"]["(Intercept)"])
mv = mv[[sorted(d["schoolclass"].unique()).index(l) for l in rf["levels"]]]
def rel(a, b): return float(np.max(np.abs(a / b - 1)))
print("lme4 condVar vs (a) beta-fixed conditional variance :", rel(ref, da))
print("lme4 condVar vs (b) PEV incl. beta uncertainty      :", rel(ref, db))
print("glmm postvar vs (a):", rel(gv, da), " vs (b):", rel(gv, db))
print("mixedlm condVar vs (a):", rel(mv, da), " vs (b):", rel(mv, db))
# lme4's documented approach for >1 term: block-diagonal of the *per-term* conditional covariance ignoring cross-term terms?
# check: per-term (a) computed with only that term's Z (other terms marginalised out?) -> just report the pattern
i = int(np.argmax(np.abs(ref / da - 1)))
print("worst level:", rf["levels"][i], "lme4", ref[i], "(a)", da[i], "(b)", db[i], "glmm", gv[i], "mixedlm", mv[i])
