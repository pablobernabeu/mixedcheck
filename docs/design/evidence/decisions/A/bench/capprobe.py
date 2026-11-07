"""Probe engine capabilities by calling them on sleepstudy (and cbpp where relevant)."""
import warnings, inspect, json, sys
import numpy as np, pandas as pd
warnings.simplefilter("ignore")
d = pd.read_csv("data/sleep.csv", dtype={"Subject": str})
out = {}
def probe(name, fn):
    try:
        v = fn(); out[name] = "OK: " + str(v)[:160].replace("\n", " ")
    except Exception as e:
        out[name] = f"FAIL: {type(e).__name__}: {str(e)[:160]}"
# ---- statsmodels
import statsmodels.formula.api as smf
from statsmodels.regression.mixed_linear_model import MixedLM, MixedLMResults
r = smf.mixedlm("Reaction ~ Days", d, groups=d["Subject"], re_formula="~Days").fit()
probe("sm.X", lambda: r.model.exog.shape)
probe("sm.Z(exog_re)", lambda: r.model.exog_re.shape)
probe("sm.ranef", lambda: list(r.random_effects.items())[0])
probe("sm.ranef_condvar", lambda: list(r.random_effects_cov.items())[0][1].shape)
probe("sm.simulate", lambda: hasattr(r.model, "simulate") or hasattr(r, "simulate"))
probe("sm.loglike_callable", lambda: inspect.signature(r.model.loglike))
probe("sm.weights_kw", lambda: "weights" in inspect.signature(MixedLM.__init__).parameters)
probe("sm.offset_kw", lambda: "offset" in inspect.signature(MixedLM.__init__).parameters)
probe("sm.df_method", lambda: [a for a in dir(r) if "satter" in a.lower() or "kenward" in a.lower() or a == "df_resid"])
probe("sm.converged", lambda: r.converged)
probe("sm.profile_re", lambda: hasattr(r, "profile_re"))
probe("sm.hessian", lambda: hasattr(r.model, "hessian"))
probe("sm.pass_unknown_kwarg_to_MixedLM", lambda: MixedLM(r.model.endog, r.model.exog, r.model.groups, weights=np.ones(len(d))))
# ---- mixedlm
import mixedlm as mlm
m = mlm.lmer("Reaction ~ Days + (Days | Subject)", d)
probe("mixedlm.getME_X_Z", lambda: (m.getME("X").shape, m.getME("Z").shape))
probe("mixedlm.ranef_condVar", lambda: type(m.ranef(condVar=True).condVar))
probe("mixedlm.simulate", lambda: np.asarray(m.simulate(nsim=2, seed=1)).shape)
probe("mixedlm.bootMer", lambda: inspect.signature(mlm.bootMer))
probe("mixedlm.satterthwaite_df", lambda: mlm.satterthwaite_df(m))
probe("mixedlm.kenward_roger_df", lambda: mlm.kenward_roger_df(m))
probe("mixedlm.devfun(as_function)", lambda: m.as_function()(m.theta))
probe("mixedlm.checkConv", lambda: str(mlm.checkConv(m))[:120])
probe("mixedlm.isSingular", lambda: m.isSingular())
probe("mixedlm.hatvalues", lambda: np.asarray(m.hatvalues())[:3])
probe("mixedlm.allFit", lambda: inspect.signature(m.allFit))
probe("mixedlm.lmerControl_check_options", lambda: [p for p in inspect.signature(mlm.lmerControl).parameters][:30])
# ---- glmm
import glmm
g = glmm.fit(d, "Reaction ~ Days + (Days | Subject)")
probe("glmm.model_matrix(X)", lambda: glmm.model_matrix(d, "~ Days")[0].shape)
probe("glmm.model_matrix_with_RE", lambda: glmm.model_matrix(d, "~ Days + (Days | Subject)"))
probe("glmm.ranef_postvar", lambda: np.asarray(g.ranef_blocks[0]["postvar"]).shape)
probe("glmm.simulate", lambda: g.simulate(nsim=2, seed=1).shape)
probe("glmm.coef_df(Satterthwaite)", lambda: g.coef_df)
probe("glmm.kenward_roger", lambda: [a for a in dir(g) if "kenward" in a.lower() or "kr" == a.lower()])
probe("glmm.profile_confint", lambda: str(g.profile_confint())[:150])
probe("glmm.objective_callable", lambda: [a for a in dir(glmm) if "deviance" in a.lower() or "objective" in a.lower() or "loglik" in a.lower()])
probe("glmm.residuals_types", lambda: inspect.signature(g.residuals))
probe("glmm.diagnostics", lambda: g.diagnostics)
probe("glmm.kernel_parts.condvar", lambda: type(g._kernel_parts["condvar"]))
# ---- gpboost
import gpboost as gpb
X = np.column_stack([np.ones(len(d)), d["Days"].values.astype(float)])
gm = gpb.GPModel(group_data=d[["Subject"]].values, likelihood="gaussian", matrix_inversion_method="cholesky")
gm.fit(y=d["Reaction"].values, X=X)
probe("gpboost.predict_training_RE", lambda: inspect.signature(gm.predict_training_data_random_effects))
probe("gpboost.RE_with_var", lambda: gm.predict_training_data_random_effects(predict_var=True).shape)
probe("gpboost.nll_callable", lambda: inspect.signature(gm.neg_log_likelihood))
probe("gpboost.simulate", lambda: [a for a in dir(gm) if "sim" in a.lower()])
probe("gpboost.REML_option", lambda: "REML" in (gpb.GPModel.__init__.__doc__ or "") or "reml" in (gpb.GPModel.fit.__doc__ or "").lower())
json.dump(out, open("out/capprobe.json", "w"), indent=1)
for k, v in out.items(): print(f"{k:38s} {v}")
