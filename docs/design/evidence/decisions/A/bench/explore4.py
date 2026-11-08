import sys, time, warnings, inspect
import numpy as np, pandas as pd
d = pd.read_csv(sys.argv[1] + "/sleep.csv", dtype={"Subject": str})
import gpboost as gpb
X = np.column_stack([np.ones(len(d)), d["Days"].values])
t=time.time()
m = gpb.GPModel(group_data=d[["Subject"]].values, group_rand_coef_data=d[["Days"]].values, ind_effect_group_rand_coef=[1], likelihood="gaussian")
m.fit(y=d["Reaction"].values, X=X)
print("gpb t", time.time()-t)
print(m.get_cov_pars(std_err=True)); print(m.get_coef(std_err=True))
print("nll", m.get_current_neg_log_likelihood())
m.summary()
# try correlated?  check for a correlation option in summary doc
print([a for a in dir(m) if not a.startswith('_')])
