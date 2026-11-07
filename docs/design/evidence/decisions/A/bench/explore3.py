import sys, time, warnings, inspect
import numpy as np, pandas as pd
d = pd.read_csv(sys.argv[1] + "/sleep.csv", dtype={"Subject": str})
import glmm
t=time.time(); f = glmm.fit(d, "Reaction ~ Days + (Days | Subject)"); print("glmm t", time.time()-t)
print("beta", f.beta, f.names); print("se", f.se)
print("varcorr", f.varcorr, "re_groups", f.re_groups, "dispersion", f.dispersion)
print("loglik", f.loglik, "deviance", f.deviance, "reml", f.reml, "objective", f.objective)
print("diagnostics", f.diagnostics)
print("converged", f.converged, "singular", f.singular, "n_eval", f.n_eval, f.n_grad, f.outer_stop, f.outer_decrement)
print("ranef_blocks keys", f.ranef_blocks[0].keys() if f.ranef_blocks else None)
print("re_term_index", f.re_term_index)
print("stddev_se", f.stddev_se)
print("warnings", f.warnings)
print("coef_df", f.coef_df)
kp = f._kernel_parts
print("kernel parts type", type(kp), (list(kp.keys()) if isinstance(kp, dict) else [a for a in dir(kp) if not a.startswith('_')]))
print(f.stddev_corr(0))
