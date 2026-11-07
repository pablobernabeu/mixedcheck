import sys, time, warnings, inspect
import numpy as np, pandas as pd
d = pd.read_csv(sys.argv[1] + "/sleep.csv", dtype={"Subject": str})
import mixedlm as mlm
r = mlm.lmer("Reaction ~ Days + (Days | Subject)", d, REML=True)
vc = r.VarCorr()
print([a for a in dir(vc) if not a.startswith('_')])
print(vars(vc).keys() if hasattr(vc,'__dict__') else None)
g = list(vc.groups.items())[0] if hasattr(vc,'groups') else None
print(g)
print("getME names doc:", (r.getME.__doc__ or '')[:1500])
for nm in ["X","Z","theta","Lambda","L","lower","devfun"]:
    try:
        v = r.getME(nm); print(nm, type(v), getattr(v,'shape',None))
    except Exception as e: print(nm, "ERR", e)
re_ = r.ranef(condVar=True)
print(type(re_), [a for a in dir(re_) if not a.startswith('_')])
print("checkConv:", mlm.checkConv(r) if hasattr(mlm,'checkConv') else None)
print("isSingular", r.isSingular(), "gradient_norm", r.gradient_norm, "optimizer", r.optimizer, "message", r.message, "n_iter", r.n_iter)
f = r.as_function() if hasattr(r,'as_function') else None
print("as_function", f, inspect.signature(r.as_function))
