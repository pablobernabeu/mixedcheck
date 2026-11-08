# Does the statsmodels 0.15.0 MixedLM fixed-effect naming depend on SM_FORMULA_ENGINE?
# Run twice with different env values; print exog names and a boolean-predictor case.
import os, sys, warnings
import numpy as np, pandas as pd
import statsmodels.formula.api as smf
warnings.filterwarnings("ignore")
rng = np.random.default_rng(1)
n_g, n_per = 30, 8
g = np.repeat(np.arange(n_g), n_per)
cond = np.tile(np.array(["b", "a", "c", "a"]), n_g * n_per // 4)
flag = rng.random(n_g * n_per) > 0.5           # boolean predictor
x = rng.normal(size=n_g * n_per)
y = 0.5 * (cond == "b") + 0.3 * x + rng.normal(size=n_g)[g] + rng.normal(size=n_g * n_per)
df = pd.DataFrame(dict(y=y, cond=cond, flag=flag, x=x, g=g.astype(str)))
m = smf.mixedlm("y ~ cond + flag + x", df, groups="g")
r = m.fit(reml=True)
print("SM_FORMULA_ENGINE=", os.environ.get("SM_FORMULA_ENGINE"), "| exog_names:", m.exog_names)
print("fe_params:", [round(v, 6) for v in r.fe_params.values])
print("REML llf:", round(r.llf, 8))
