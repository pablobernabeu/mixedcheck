"""(1) statsmodels SE convention on school_REML: compare bse_fe with sigma2 (X'V^-1X)^-1 at statsmodels' own
estimates. (2) Spot-check capability claims: mixedlm as_function/REMLcrit, getME('Z'), KR/Satterthwaite df;
glmm df method and Z access."""
import sys, os, warnings, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, build
import statsmodels.formula.api as smf
warnings.simplefilter("ignore")
A = sys.argv[1]
d = load(os.path.join(A, "data"), "school")
s = smf.mixedlm("y ~ x + w", d, groups=d["school"], re_formula="1 + x", vc_formula={"schoolclass": "0 + C(schoolclass)"}).fit(reml=True)
X = x_from_names(d, ["(Intercept)", "x", "w"])
covs = [np.asarray(s.cov_re), [[float(np.asarray(s.vcomp)[0])]]]
Z, G = build(d, [("school", ["1", "x"]), ("schoolclass", ["1"])], covs)
V = Z @ G @ Z.T + s.scale * np.eye(len(d))
se_cond = np.sqrt(np.diag(np.linalg.inv(X.T @ np.linalg.solve(V, X))))
print("statsmodels bse_fe:", np.round(s.bse_fe.values, 5), "| conditional-on-theta SE at sm estimates:", np.round(se_cond, 5),
      "| ratio:", np.round(s.bse_fe.values / se_cond, 4))
R = {(r["model"], r["engine"]): r for r in json.load(open(os.path.join(A, "r_reference.json")))["results"]}
print("lme4 SE:", {k: round(v, 5) for k, v in R[("school_REML", "lme4")]["se"].items()}, "| glmmTMB SE:", {k: round(v, 5) for k, v in R[("school_REML", "glmmTMB")]["se"].items()})
import mixedlm as mlm, glmm
ds = load(os.path.join(A, "data"), "sleep")
r = mlm.lmer("Reaction ~ Days + (Days | Subject)", ds)
f = r.as_function() if hasattr(r, "as_function") else None
th = np.asarray(r.getME("theta"))
print("mixedlm as_function(theta) - REMLcrit:", (float(f(th)) - float(r.REMLcrit())) if f else "n/a", "| Z shape:", r.getME("Z").shape)
for meth in ("satterthwaite", "kenward-roger", "Satterthwaite", "KR"):
    try:
        out = r.summary(ddf=meth) if "ddf" in r.summary.__code__.co_varnames else None
    except Exception as e:
        out = None
names = [a for a in dir(r) if any(k in a.lower() for k in ("satter", "kenward", "ddf", "df"))]
print("mixedlm df-related attributes:", names[:12])
g = glmm.fit(ds, "Reaction ~ Days + (Days | Subject)", "gaussian", reml=True)
print("glmm df_method:", g.df_method, "| df:", np.round(np.asarray(g.coef_df, float), 2) if hasattr(g, "coef_df") else None)
try:
    glmm.model_matrix(ds, "Reaction ~ Days + (Days | Subject)")
    print("glmm.model_matrix with random terms: accepted")
except Exception as e:
    print("glmm.model_matrix with random terms:", type(e).__name__, str(e)[:100])
