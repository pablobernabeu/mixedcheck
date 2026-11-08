import sys, numpy as np, pandas as pd, gpboost as gpb
sys.path.insert(0, ".")
from common import S, design, lmm_dev
import os
MIM = os.environ.get("MIM", "default")
print("MIM", MIM)
for mid, rc in [("sleep_zcp_ML", True), ("pen_ML", False)]:
    sp = S[mid]; des = design(sp, "data"); d = des["d"]
    X = des["X"]; y = des["y"]
    if rc:
        m = gpb.GPModel(group_data=d[["Subject"]].values, group_rand_coef_data=d[["Days"]].values.astype(float), ind_effect_group_rand_coef=[1], likelihood="gaussian", matrix_inversion_method=MIM)
    else:
        m = gpb.GPModel(group_data=d[["plate", "sample"]].values, likelihood="gaussian", matrix_inversion_method=MIM)
    m.fit(y=y, X=X)
    cp = m.get_cov_pars().iloc[0].values; beta = m.get_coef().iloc[0].values
    covs = [[[v]] for v in cp[1:]]
    ref = lmm_dev(des, [np.array(c) for c in covs], cp[0], beta=beta)["dev"]
    print(mid, "gpb 2*nll", 2 * m.get_current_neg_log_likelihood(), "ref ML dev at gpb est", ref)
    # evaluate gpboost nll at a few other parameter points vs reference
    for f in [0.5, 2.0]:
        cp2 = cp.copy(); cp2[1:] *= f
        g = 2 * m.neg_log_likelihood(cov_pars=cp2, y=y, fixed_effects=X @ beta)
        r = lmm_dev(des, [np.array([[v]]) for v in cp2[1:]], cp2[0], beta=beta)["dev"]
        print("   scale", f, "gpb", g, "ref", r, "diff", g - r)
