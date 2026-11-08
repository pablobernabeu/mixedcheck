"""Fresh fits of glmm 0.8.0 and mixedlm 1.3.0 (my own minimal adapters), scored with my independent
objective and compared with lme4 / glmmTMB estimates from report A's r_reference.json scored the same way.
Usage: fresh_fits.py <A bench dir> <out json> [model ...]"""
import json, sys, os, time, warnings
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indep_obj import load, x_from_names, lmm, glmm as glmm_obj
from specs import M

A, OUT = sys.argv[1], sys.argv[2]
models = sys.argv[3:] or list(M)
R = json.load(open(os.path.join(A, "r_reference.json")))
RR = {(r["model"], r["engine"]): r for r in R["results"]}
# formulas (lme4 syntax), transcribed from r_reference.R
F = {"sleep": "Reaction ~ Days + (Days | Subject)", "sleep_zcp": "Reaction ~ Days + (1 | Subject) + (0 + Days | Subject)",
     "pen": "diameter ~ 1 + (1 | plate) + (1 | sample)", "pastes": "strength ~ 1 + (1 | batch) + (1 | sample)",
     "crossed": "y ~ cond + (1 + cond | subj) + (1 + cond | item)",
     "crossed_zcp": "y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)",
     "school": "y ~ x + w + (1 + x | school) + (1 | schoolclass)",
     "school_zcp": "y ~ x + w + (1 | school) + (0 + x | school) + (1 | schoolclass)",
     "nearsing": "y ~ t + (1 + t | g)", "nearsing_zcp": "y ~ t + (1 | g) + (0 + t | g)",
     "weighted": "y ~ x + (1 | g)", "jq": "y ~ x1 + x2 + (1 + x1 + x2 | g)",
     "cbpp": "period + (1 | herd)", "owls": "FoodTreatment * SexParent + (1 | Nest)",
     "binxd": "cond + (1 + cond | subj) + (1 | item)"}

MODEL2F = {'sleep_REML': 'sleep', 'sleep_ML': 'sleep', 'sleep_zcp_ML': 'sleep_zcp', 'pen_REML': 'pen', 'pen_ML': 'pen',
           'pastes_REML': 'pastes', 'pastes_ML': 'pastes', 'crossed_REML': 'crossed', 'crossed_ML': 'crossed',
           'crossed_zcp_REML': 'crossed_zcp', 'crossed_zcp_ML': 'crossed_zcp', 'crossedbig_REML': 'crossed',
           'crossedbig_zcp_REML': 'crossed_zcp', 'school_REML': 'school', 'school_ML': 'school',
           'school_zcp_ML': 'school_zcp', 'nearsing_REML': 'nearsing', 'nearsing_ML': 'nearsing',
           'nearsing_zcp_ML': 'nearsing_zcp', 'weighted_REML': 'weighted', 'weighted_ML': 'weighted', 'jq_REML': 'jq',
           'cbpp_laplace': 'cbpp', 'cbpp_agq25': 'cbpp', 'owls_pois': 'owls', 'owls_pois_agq25': 'owls',
           'binxd_laplace': 'binxd'}

def formula_for(mid):
    return F[MODEL2F[mid]]

def score(sp, d, names, beta, covs, s2):
    X = x_from_names(d, names)
    y = d[sp["y"]].to_numpy(float)
    if sp["family"] == "gaussian":
        w = d[sp["weights"]].to_numpy(float) if sp["weights"] else None
        return lmm(d, y, X, sp["blocks"], covs, s2, beta=beta, reml=sp["reml"], w=w)
    m = d[sp["trials"]].to_numpy(float) if sp["trials"] else None
    off = d[sp["offset"]].to_numpy(float) if sp["offset"] else None
    return glmm_obj(d, y, X, sp["blocks"], covs, beta, sp["family"], m=m, off=off, nagq=sp["nagq"])

def r_covs(sp, r):
    out, used = [], set()
    for g, terms in sp["blocks"]:
        for name, v in r["re"].items():
            ts = v["terms"] if isinstance(v["terms"], list) else [v["terms"]]
            ts = ["1" if t == "(Intercept)" else t for t in ts]
            if name not in used and name.split(".")[0] == g and ts == terms:
                used.add(name); out.append(np.atleast_2d(np.array(v["cov"], float))); break
    return out

def fit_glmm(sp, d, fml, mid):
    import glmm
    kw = {}
    if sp["family"] == "gaussian":
        kw["reml"] = bool(sp["reml"])
        if sp["weights"]: kw["weights"] = d[sp["weights"]].to_numpy(float)
        f = fml
    elif sp["family"] == "binomial":
        d = d.copy(); d["_fail"] = d[sp["trials"]] - d[sp["y"]]   # glmm's cbind() takes column names only
        f = f"cbind({sp['y']}, _fail) ~ " + fml
        kw["nagq"] = sp["nagq"]
    else:
        f = f"{sp['y']} ~ " + fml + f" + offset({sp['offset']})"
        kw["nagq"] = sp["nagq"]
    t = []
    for _ in range(2):
        t0 = time.perf_counter(); fit = glmm.fit(d, f, sp["family"], **kw); t.append(time.perf_counter() - t0)
    covs = []
    for g, terms in sp["blocks"]:
        for (gname, tn), v in zip(fit.re_groups, fit.varcorr):
            if gname == g:
                tn = ["1" if x == "(Intercept)" else x for x in tn]
                q = len(tn); v = np.asarray(v, float)
                C = np.zeros((q, q)); k = 0
                for c in range(q):            # column-major lower-triangular vech (documented)
                    for r_ in range(c, q):
                        C[r_, c] = C[c, r_] = v[k]; k += 1
                ix = [tn.index(x) for x in terms]
                covs.append(C[np.ix_(ix, ix)]); break
    s2 = float(fit.dispersion) if sp["family"] == "gaussian" else None
    return dict(names=list(fit.names), beta=np.asarray(fit.beta, float), se=np.asarray(fit.se, float), covs=covs, s2=s2,
                reported=-2 * float(fit.loglik), converged=bool(fit.converged), singular=bool(fit.singular), times=t,
                formula=f)

def fit_mixedlm(sp, d, fml, mid):
    import mixedlm as mlm
    kw = {}
    t = []
    for _ in range(2):
        t0 = time.perf_counter()
        if sp["family"] == "gaussian":
            if sp["weights"]: kw["weights"] = sp["weights"]
            res = mlm.lmer(fml, d, REML=bool(sp["reml"]), **kw)
        elif sp["family"] == "binomial":
            res = mlm.glmer(f"{sp['y']} / {sp['trials']} ~ " + fml, d, family=mlm.families.Binomial(), nAGQ=sp["nagq"])
        else:
            res = mlm.glmer(f"{sp['y']} ~ " + fml, d, family=mlm.families.Poisson(), nAGQ=sp["nagq"], offset=sp["offset"])
        t.append(time.perf_counter() - t0)
    groups = list(res.VarCorr().groups.values())
    covs, used = [], set()
    for g, terms in sp["blocks"]:
        for j, G in enumerate(groups):
            tn = ["1" if x == "(Intercept)" else x for x in G.term_names]
            if j not in used and getattr(G, "grouping_factor", G.name).split(".")[0] == g and all(x in tn for x in terms):
                ix = [tn.index(x) for x in terms]
                covs.append(np.asarray(G.cov, float)[np.ix_(ix, ix)])
                if len(terms) == len(tn): used.add(j)
                break
    fe = res.fixef()
    ll = res.logLik(); ll = float(getattr(ll, "value", ll))
    return dict(names=list(fe.keys()), beta=np.array(list(fe.values()), float), se=np.sqrt(np.diag(np.asarray(res.vcov()))),
                covs=covs, s2=(float(res.sigma) ** 2 if sp["family"] == "gaussian" else None), reported=-2 * ll,
                converged=bool(getattr(res, "converged", None)), singular=bool(res.isSingular()), times=t)

out = []
for mid in models:
    sp = M[mid]
    d = load(os.path.join(A, "data"), sp["data"])
    fml = formula_for(mid)
    lme = RR[(mid, "lme4")]
    rnames = list(lme["beta"].keys())
    row = dict(model=mid)
    scores = {}
    scores["lme4"] = score(sp, d, rnames, np.array(list(lme["beta"].values())), r_covs(sp, lme),
                           lme["sigma"] ** 2 if sp["family"] == "gaussian" else None)
    if (mid, "glmmTMB") in RR:
        tm = RR[(mid, "glmmTMB")]
        try:
            scores["glmmTMB"] = score(sp, d, rnames, np.array(list(tm["beta"].values())), r_covs(sp, tm),
                                      tm["sigma"] ** 2 if sp["family"] == "gaussian" else None)
        except Exception as e:
            scores["glmmTMB"] = None
    for eng, fn in (("glmm", fit_glmm), ("mixedlm", fit_mixedlm)):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            try:
                fr = fn(sp, d, fml, mid)
            except Exception as e:
                row[eng] = dict(error=repr(e)[:300]); continue
        sc = score(sp, d, rnames, fr["beta"], fr["covs"], fr["s2"])
        scores[eng] = sc
        se_l = np.array(list(lme["se"].values()))
        row[eng] = dict(obj=sc, reported_minus_obj=fr["reported"] - sc, converged=fr["converged"], singular=fr["singular"],
                        times=fr["times"], names=fr["names"],
                        max_dbeta_se=float(np.max(np.abs(fr["beta"] - np.array(list(lme["beta"].values()))) / se_l)),
                        max_rel_dse=float(np.max(np.abs(fr["se"] / se_l - 1))))
    best = min(v for v in scores.values() if v is not None)
    row["scores"] = scores
    row["gaps"] = {k: (v - best if v is not None else None) for k, v in scores.items()}
    row["lme4_time_median_A"] = lme.get("time_median")
    out.append(row)
    g = row["gaps"]
    print(f"{mid:20s} best {best:14.6f} | gaps: " + ", ".join(f"{k} {v:.1e}" for k, v in g.items() if v is not None)
          + " | conv " + ", ".join(f"{e}={row[e].get('converged')}" for e in ("glmm", "mixedlm") if "converged" in row.get(e, {}))
          + " | warm s: " + ", ".join(f"{e}={row[e]['times'][1]:.4f}" for e in ("glmm", "mixedlm") if "times" in row.get(e, {}))
          + f" | lme4(A) {lme.get('time_median')}", flush=True)
json.dump(out, open(OUT, "w"), indent=1, default=float)
