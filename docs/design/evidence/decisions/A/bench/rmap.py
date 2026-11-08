"""Map R reference results (lme4 / glmmTMB JSON) onto canonical spec blocks."""
import numpy as np
from common import S

def norm_terms(ts):
    return ["1" if t == "(Intercept)" else t for t in ts]

def r_covs(spec, r):
    used = set(); covs = []
    for g, terms in spec["re"]:
        found = None
        for name, v in r["re"].items():
            base = name.split(".")[0]
            if name in used: continue
            if base == g and norm_terms(v["terms"] if isinstance(v["terms"], list) else [v["terms"]]) == terms:
                found = name; break
        if found is None:
            raise KeyError((g, terms, list(r["re"].keys())))
        used.add(found)
        covs.append(np.atleast_2d(np.array(r["re"][found]["cov"], float)))
    return covs

def r_est(spec, r):
    beta = np.array(list(r["beta"].values()), float)
    s2 = (r["sigma"] ** 2) if spec["family"] == "gaussian" else None
    return dict(beta=beta, covs=r_covs(spec, r), sigma2=s2, names=list(r["beta"].keys()))
