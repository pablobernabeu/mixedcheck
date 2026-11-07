import numpy as np, pandas as pd, gpboost as gpb, inspect
d = pd.read_csv("data/sleep.csv", dtype={"Subject": str})
X = np.column_stack([np.ones(len(d)), d["Days"].values.astype(float)]); y = d["Reaction"].values
m = gpb.GPModel(group_data=d[["Subject"]].values, group_rand_coef_data=d[["Days"]].values.astype(float), ind_effect_group_rand_coef=[1], likelihood="gaussian")
m.fit(y=y, X=X, params={"trace": False})
cp = m.get_cov_pars().iloc[0].values; beta = m.get_coef().iloc[0].values
print("cov_pars", cp, "beta", beta)
print("current nll", m.get_current_neg_log_likelihood())
print(inspect.signature(m.neg_log_likelihood))
print("nll at est", m.neg_log_likelihood(cov_pars=cp, y=y, fixed_effects=X @ beta))
# tighter convergence
m2 = gpb.GPModel(group_data=d[["Subject"]].values, group_rand_coef_data=d[["Days"]].values.astype(float), ind_effect_group_rand_coef=[1], likelihood="gaussian")
m2.fit(y=y, X=X, params={"delta_rel_conv": 1e-10, "maxit": 5000})
print("tight: cov_pars", m2.get_cov_pars().iloc[0].values, "nll", m2.get_current_neg_log_likelihood())
