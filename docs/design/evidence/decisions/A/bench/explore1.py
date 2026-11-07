import sys, time, warnings
import numpy as np, pandas as pd
d = pd.read_csv(sys.argv[1] + "/sleep.csv")
print(d.dtypes.to_dict())
import mixedlm as mlm
t=time.time(); r = mlm.lmer("Reaction ~ Days + (Days | Subject)", d, REML=True); print("mixedlm t", time.time()-t)
print(type(r)); print([a for a in dir(r) if not a.startswith('_')])
print(r.fixef()); 
vc = r.VarCorr(); print(type(vc)); print(vc)
print("REMLcrit/loglik", r.REMLcrit() if hasattr(r,'REMLcrit') else None, r.logLik() if hasattr(r,'logLik') else None)
print("theta", getattr(r,'theta',None))
print("sigma", r.sigma if not callable(getattr(r,'sigma',None)) else r.sigma())
print("vcov", r.vcov() if callable(getattr(r,'vcov',None)) else getattr(r,'vcov',None))
print("converged/optinfo", getattr(r,'converged',None), getattr(r,'optinfo',None))
