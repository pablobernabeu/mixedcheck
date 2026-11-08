"""gpboost 1.8.0: is the default likelihood for grouped random effects exact? Evaluate 2*neg_log_likelihood at
lme4's ML estimates (pen_ML, pastes_ML, sleep_zcp_ML, school_zcp_ML) under the default and Cholesky methods,
against my independent exact objective."""
import json, sys, os, warnings
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm
from specs import M
import gpboost as gpb
A = sys.argv[1]
R = {(r["model"], r["engine"]): r for r in json.load(open(os.path.join(A, "r_reference.json")))["results"]}
cases = {"pen_ML": (["plate", "sample"], [], []), "pastes_ML": (["batch", "sample"], [], []),
         "sleep_zcp_ML": (["Subject"], ["Days"], [1]), "school_zcp_ML": (["school", "schoolclass"], ["x"], [1]),
         "crossed_zcp_ML": (["subj", "item"], ["cond", "cond"], [1, 2])}
for mid, (gcols, rc, rci) in cases.items():
    sp = M[mid]; d = load(os.path.join(A, "data"), sp["data"]); r = R[(mid, "lme4")]
    names = list(r["beta"].keys()); beta = np.array(list(r["beta"].values()))
    X = x_from_names(d, names); y = d[sp["y"]].to_numpy(float)
    covs, used = [], set()
    for g, terms in sp["blocks"]:
        for nm, v in r["re"].items():
            ts = ["1" if t == "(Intercept)" else t for t in (v["terms"] if isinstance(v["terms"], list) else [v["terms"]])]
            if nm not in used and nm.split(".")[0] == g and ts == terms:
                used.add(nm); covs.append(np.atleast_2d(v["cov"])); break
    exact = lmm(d, y, X, sp["blocks"], covs, r["sigma"] ** 2, beta=beta, reml=False)
    # gpboost cov_pars order: error variance, grouped intercept variances (group order), random-coefficient variances
    inter = [float(c[0, 0]) for (g, t), c in zip(sp["blocks"], covs) if t == ["1"]]
    slope = [float(c[0, 0]) for (g, t), c in zip(sp["blocks"], covs) if t != ["1"]]
    cp = np.array([r["sigma"] ** 2] + inter + slope)
    vals = {}
    for mim in ("default", "cholesky"):
        kw = dict(group_data=d[gcols].to_numpy(), likelihood="gaussian", matrix_inversion_method=mim)
        if rc:
            kw.update(group_rand_coef_data=d[rc].to_numpy(float), ind_effect_group_rand_coef=rci)
        reps = []
        for seed in range(3):
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                m = gpb.GPModel(seed=seed, **kw) if "seed" in gpb.GPModel.__init__.__code__.co_varnames else gpb.GPModel(**kw)
                reps.append(2 * float(m.neg_log_likelihood(cov_pars=cp, y=y, fixed_effects=X @ beta)))
        vals[mim] = reps
    print(f"{mid:15s} exact {exact:.6f} | default - exact: {[f'{v - exact:+.3e}' for v in vals['default']]} | cholesky - exact: {[f'{v - exact:+.1e}' for v in vals['cholesky']]}")
