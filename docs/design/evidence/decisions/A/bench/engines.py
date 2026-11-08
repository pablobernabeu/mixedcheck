"""Engine adapters. Each returns a standard dict; absolute covariance matrices aligned to spec['re']."""
import time, warnings, io, contextlib
import numpy as np
import pandas as pd
from common import S, load, CAT


class Unsupported(Exception):
    pass


def _std(beta, names, se, covs, sigma2, **kw):
    out = dict(beta=[float(b) for b in beta], names=list(names), se=[float(s) for s in se],
               covs=[np.atleast_2d(np.asarray(c, float)).tolist() for c in covs],
               sigma2=None if sigma2 is None else float(sigma2))
    out.update(kw)
    return out


def _blocks_by_group(spec):
    """Group spec blocks: {group: [(block_index, terms), ...]} in order."""
    g = {}
    for i, (grp, terms) in enumerate(spec["re"]):
        g.setdefault(grp, []).append((i, terms))
    return g


# ------------------------------------------------------------------ statsmodels MixedLM
def fit_statsmodels(spec, d, reps):
    import statsmodels
    import statsmodels.formula.api as smf
    if spec["weights"]:
        raise Unsupported("MixedLM has no prior/precision weights argument")
    if spec["offset"]:
        raise Unsupported("no offset in MixedLM or the Bayesian mixed GLMs")
    if spec["family"] != "gaussian":
        return fit_statsmodels_bayes(spec, d, reps)
    bg = _blocks_by_group(spec)
    groups = list(bg)
    fixed_rhs = " + ".join([t for t in spec["fixed"] if t != "1"]) or "1"
    fml = f"{spec['y']} ~ {fixed_rhs}"
    # choose the 'groups' factor: the one with a multi-term (correlated) block if any; the others
    # must be nested in it (statsmodels VC are within-group) or the model is fitted with one all-data group.
    corr_groups = [g for g, bl in bg.items() if any(len(t) > 1 for _, t in bl)]
    d = d.copy()
    def nested_in(inner, outer):
        return d.groupby(inner)[outer].nunique().max() == 1
    layout = None
    if len(corr_groups) > 1:
        raise Unsupported("correlated random slopes for more than one grouping factor (crossed) are not representable")
    if len(groups) == 1:
        layout = ("single", groups[0])
    elif len(corr_groups) == 1:
        outer = corr_groups[0]
        if all(nested_in(g, outer) for g in groups if g != outer):
            layout = ("nested", outer)
        else:
            raise Unsupported("correlated block plus a crossed factor is not representable")
    else:
        # all blocks are scalar: pick an outer factor in which all others nest, else one all-data group
        outer = None
        for cand in groups:
            if all(nested_in(g, cand) for g in groups if g != cand):
                outer = cand; break
        layout = ("nested", outer) if outer else ("onegroup", None)
    re_formula, vc, grp_col = None, {}, None
    if layout[0] in ("single", "nested"):
        grp_col = layout[1]
        outer_blocks = bg[grp_col]
        multi = [t for _, t in outer_blocks if len(t) > 1]
        if multi:
            terms = multi[0]
            re_formula = " + ".join(["1" if t == "1" else t for t in terms])
            if "1" not in terms:
                re_formula = "0 + " + re_formula
        else:
            # scalar blocks of the outer factor: intercept as re, slopes as vc
            has_int = any(t == ["1"] for _, t in outer_blocks)
            re_formula = "1" if has_int else "0"
            for _, t in outer_blocks:
                if t != ["1"]:
                    vc[f"{grp_col}__{t[0]}"] = f"0 + {t[0]}"
        for g in groups:
            if g == grp_col:
                continue
            for _, t in bg[g]:
                if t == ["1"]:
                    vc[g] = f"0 + C({g})"
                else:
                    vc[f"{g}__{t[0]}"] = f"0 + C({g}):{t[0]}"
    else:
        d["_one"] = 1
        grp_col = "_one"; re_formula = "0"
        for g in groups:
            for _, t in bg[g]:
                vc[g if t == ["1"] else f"{g}__{t[0]}"] = f"0 + C({g})" if t == ["1"] else f"0 + C({g}):{t[0]}"
    times = []; res = None; wlist = []
    for r in range(reps):
        with warnings.catch_warnings(record=True) as wl:
            warnings.simplefilter("always")
            t0 = time.perf_counter()
            md = smf.mixedlm(fml, d, groups=d[grp_col], re_formula=re_formula, vc_formula=vc or None)
            res = md.fit(reml=bool(spec["reml"]))
            times.append(time.perf_counter() - t0)
        wlist = [f"{w.category.__name__}: {w.message}" for w in wl]
    # map back to blocks
    covs = [None] * len(spec["re"])
    cre = np.asarray(res.cov_re)
    vnames = list(res.model.exog_vc.names) if res.model.exog_vc is not None else []
    vcomp = np.asarray(res.vcomp) if len(vnames) else np.array([])
    for i, (g, t) in enumerate(spec["re"]):
        if g == grp_col and len(t) > 1:
            covs[i] = cre
        elif g == grp_col and t == ["1"] and re_formula == "1":
            covs[i] = cre[:1, :1]
        else:
            key = g if t == ["1"] else f"{g}__{t[0]}"
            covs[i] = [[vcomp[vnames.index(key)]]]
    fe = res.fe_params
    names = list(fe.index)
    se = np.asarray(res.bse_fe)
    return _std(fe.values, names, se, covs, res.scale,
                reported_loglik=float(res.llf), reported_criterion=float(-2 * res.llf),
                converged=bool(res.converged), singular=None, warnings=wlist, times=times,
                layout=f"{layout[0]}:{grp_col}; re_formula={re_formula}; vc={vc}",
                engine_version=statsmodels.__version__)


def fit_statsmodels_bayes(spec, d, reps):
    import statsmodels
    from statsmodels.genmod.bayes_mixed_glm import BinomialBayesMixedGLM, PoissonBayesMixedGLM
    if spec["family"] != "binomial":
        raise Unsupported("family not available")
    if len(spec["re"]) != 1 or spec["re"][0][1] != ["1"]:
        raise Unsupported("only independent variance components")
    # expand aggregated binomial to Bernoulli rows (statsmodels' binomial mixed GLM takes 0/1 responses)
    rows = []
    for _, r in d.iterrows():
        k, n = int(r[spec["y"]]), int(r[spec["trials"]])
        for j in range(n):
            rr = r.copy(); rr["_yb"] = 1 if j < k else 0; rows.append(rr)
    db = pd.DataFrame(rows).reset_index(drop=True)
    g = spec["re"][0][0]
    fixed = [t for t in spec["fixed"] if t != "1"]
    fml = "_yb ~ " + " + ".join([f"C({t})" if t in CAT[spec["data"]] else t for t in fixed])
    out = {}
    for meth in ("vb", "map"):
        times = []
        with warnings.catch_warnings(record=True) as wl:
            warnings.simplefilter("always")
            for r in range(reps):
                t0 = time.perf_counter()
                md = BinomialBayesMixedGLM.from_formula(fml, {g: f"0 + C({g})"}, db)
                res = md.fit_vb() if meth == "vb" else md.fit_map()
                times.append(time.perf_counter() - t0)
        k = md.k_fep
        if meth == "vb":
            beta = res.fe_mean; sd = np.exp(res.vcp_mean[0]); se = res.fe_sd
        else:
            beta = res.params[:k]; sd = np.exp(res.params[k]); se = np.sqrt(np.diag(res.cov_params())[:k])
        out[meth] = _std(beta, md.exog_names, se, [[[sd ** 2]]], None, times=times,
                         warnings=[f"{w.category.__name__}: {w.message}" for w in wl],
                         converged=None, singular=None, nrows_bernoulli=len(db),
                         engine_version=statsmodels.__version__)
    res = out["vb"]
    res["variants"] = {"map": out["map"]}
    res["note"] = "Bayesian mixed GLM (variational Bayes; posterior means; Normal priors on fixed effects sd=2? see fe_p, vcp_p defaults); MAP variant in variants"
    return res


# ------------------------------------------------------------------ mixedlm (Rust backend)
def fit_mixedlm(spec, d, reps):
    import mixedlm as mlm
    fml = spec["formula"]
    kw = {}
    if spec["weights"]:
        kw["weights"] = spec["weights"]
    if spec["family"] == "binomial":   # mixedlm's parser rejects cbind(); README syntax is successes / trials
        fml = f"{spec['y']} / {spec['trials']} ~ " + fml.split("~", 1)[1]
    if spec["offset"]:                 # in-formula offset() is rejected; use the offset= argument
        fml = fml.replace(f" + offset({spec['offset']})", "")
        kw["offset"] = spec["offset"]
    times = []; res = None
    with warnings.catch_warnings(record=True) as wl:
        warnings.simplefilter("always")
        for r in range(reps):
            t0 = time.perf_counter()
            if spec["family"] == "gaussian":
                res = mlm.lmer(fml, d, REML=bool(spec["reml"]), **kw)
            else:
                fam = mlm.families.Binomial() if spec["family"] == "binomial" else mlm.families.Poisson()
                if spec["family"] == "binomial":
                    res = mlm.glmer(fml, d, family=fam, nAGQ=spec["nagq"], **kw)
                else:
                    res = mlm.glmer(fml, d, family=fam, nAGQ=spec["nagq"], **kw)
            times.append(time.perf_counter() - t0)
    wlist = [f"{w.category.__name__}: {w.message}" for w in wl]
    vc = res.VarCorr()
    grp = list(vc.groups.values())
    covs = []
    used = set()
    for g, t in spec["re"]:
        found = None
        for j, G in enumerate(grp):
            if j in used:
                continue
            tn = ["1" if x == "(Intercept)" else x for x in G.term_names]
            gf = getattr(G, "grouping_factor", G.name)
            if (gf == g or G.name.split(".")[0] == g) and tn == t:
                found = j; break
        if found is None:
            raise RuntimeError(f"block {g}{t} not found in {[ (G.name, G.term_names) for G in grp]}")
        used.add(found)
        covs.append(np.asarray(grp[found].cov))
    fe = res.fixef()
    vcv = np.asarray(res.vcov())
    s2 = float(res.sigma) ** 2 if spec["family"] == "gaussian" else None
    try:
        ll = float(res.logLik().value) if hasattr(res.logLik(), "value") else float(res.logLik())
    except Exception:
        ll = None
    crit = None
    try:
        crit = float(res.REMLcrit()) if spec["family"] == "gaussian" and spec["reml"] else float(res.deviance())
    except Exception:
        pass
    sing = None
    try:
        sing = bool(res.isSingular())
    except Exception:
        pass
    return _std(list(fe.values()), list(fe.keys()), np.sqrt(np.diag(vcv)), covs, s2,
                reported_loglik=ll, reported_criterion=crit, converged=bool(getattr(res, "converged", None)),
                singular=sing, warnings=wlist, times=times, optimizer=str(getattr(res, "optimizer", None)),
                message=str(getattr(res, "message", None)), engine_version=mlm.__version__)


# ------------------------------------------------------------------ glmm (Rust engine)
def fit_glmm(spec, d, reps):
    import glmm
    from importlib.metadata import version
    kw = {}
    fml = spec["formula"]
    if spec["family"] == "binomial":
        d = d.copy(); d["_prop"] = d[spec["y"]] / d[spec["trials"]]
        fml = "_prop ~ " + fml.split("~", 1)[1]
        kw["weights"] = d[spec["trials"]].values.astype(float)
    if spec["weights"]:
        kw["weights"] = d[spec["weights"]].values.astype(float)
    if spec["family"] == "gaussian":
        kw["reml"] = bool(spec["reml"])
    else:
        kw["nagq"] = spec["nagq"]
    times = []
    with warnings.catch_warnings(record=True) as wl:
        warnings.simplefilter("always")
        for r in range(reps):
            t0 = time.perf_counter()
            f = glmm.fit(d, fml, spec["family"], **kw)
            times.append(time.perf_counter() - t0)
    wlist = [f"{w.category.__name__}: {w.message}" for w in wl]
    covs = []
    merged_offdiag = []
    full = []
    for gname, terms in f.re_groups:
        tn = ["1" if x == "(Intercept)" else x for x in terms]
        k = len(tn); v = np.asarray(f.varcorr[len(full)], float)
        C = np.zeros((k, k)); iu = np.triu_indices(k); C[iu[1], iu[0]] = v; C = C + np.tril(C, -1).T  # column-major vech
        full.append((gname, tn, C))
    for g, t in spec["re"]:
        found = None
        for gname, tn, C in full:
            if gname.split(".")[0] == g and all(x in tn for x in t):
                found = (tn, C); break
        if found is None:
            raise RuntimeError(f"block {g}{t} not found in {f.re_groups}")
        tn, C = found
        ix = [tn.index(x) for x in t]
        covs.append(C[np.ix_(ix, ix)])
        if len(t) < len(tn):
            other = [i for i in range(len(tn)) if i not in ix]
            merged_offdiag.append(float(np.max(np.abs(C[np.ix_(ix, other)]))))
    s2 = float(f.dispersion) if spec["family"] == "gaussian" else None
    return _std(f.beta, f.names, f.se, covs, s2, reported_loglik=float(f.loglik),
                reported_criterion=float(f.deviance) if f.deviance == f.deviance else None,
                converged=bool(f.converged), singular=bool(f.singular), warnings=wlist + [str(x) for x in f.warnings],
                times=times, diagnostics={k: (v.tolist() if hasattr(v, "tolist") else v) for k, v in f.diagnostics.items()},
                objective=f.objective, objective_nodes=f.objective_nodes, n_eval=f.n_eval,
                merged_block_max_abs_offdiag=merged_offdiag or None,
                engine_version=version("glmm"))


# ------------------------------------------------------------------ gpboost
def fit_gpboost(spec, d, reps, mim="default"):
    import gpboost as gpb
    if spec["family"] == "gaussian" and spec["reml"]:
        raise Unsupported("gpboost estimates by maximum likelihood only (no REML)")
    bg = _blocks_by_group(spec)
    gcols, rc_cols, rc_ind, drop_int = [], [], [], []
    for gi, (g, bl) in enumerate(bg.items()):
        terms = [tuple(t) for _, t in bl]
        if any(len(t) > 1 for t in terms):
            raise Unsupported("correlated random intercept and slope (gpboost random coefficients are independent)")
        gcols.append(g)
        has_int = ("1",) in terms
        drop_int.append(not has_int)
        for t in terms:
            if t != ("1",):
                rc_cols.append(t[0]); rc_ind.append(gi + 1)
    X = None
    from common import build_X
    X, xn = build_X(d, spec["fixed"], CAT.get(spec["data"], []))
    kw = dict(group_data=d[gcols].values)
    if rc_cols:
        kw.update(group_rand_coef_data=d[rc_cols].values.astype(float), ind_effect_group_rand_coef=rc_ind)
        if any(drop_int):
            kw["drop_intercept_group_rand_effect"] = drop_int
    lik = {"gaussian": "gaussian", "binomial": "binomial_logit", "poisson": "poisson"}[spec["family"]]
    if spec["family"] == "binomial":
        y = (d[spec["y"]] / d[spec["trials"]]).values.astype(float)
        kw["weights"] = d[spec["trials"]].values.astype(float)
    else:
        y = d[spec["y"]].values.astype(float)
    if spec["weights"]:
        kw["weights"] = d[spec["weights"]].values.astype(float)
    if spec["nagq"] != 1:
        raise Unsupported("Laplace approximation only (no adaptive quadrature)")
    off = d[spec["offset"]].values.astype(float) if spec["offset"] else None
    times = []; buf = io.StringIO()
    with warnings.catch_warnings(record=True) as wl:
        warnings.simplefilter("always")
        for r in range(reps):
            t0 = time.perf_counter()
            m = gpb.GPModel(likelihood=lik, matrix_inversion_method=mim, **kw)
            m.fit(y=y, X=X, offset=off)
            times.append(time.perf_counter() - t0)
    cp = m.get_cov_pars(std_err=False)
    cf = m.get_coef(std_err=True)
    cpv = cp.iloc[0] if hasattr(cp, "iloc") else cp
    names_cp = list(cp.columns)
    covs = []
    # gpboost order: Error_var (gaussian), Group_1..Group_G intercepts, then rand coefs
    for g, t in spec["re"]:
        gi = list(bg).index(g) + 1
        if t == ["1"]:
            covs.append([[float(cp[f"Group_{gi}"].iloc[0])]])
        else:
            # rand coef: find its position among rc_cols for this group
            j = [i for i, (c, ii) in enumerate(zip(rc_cols, rc_ind)) if c == t[0] and ii == gi][0]
            cname = [c for c in names_cp if "rand_coef" in c][j]
            covs.append([[float(cp[cname].iloc[0])]])
    s2 = float(cp["Error_var"].iloc[0]) if spec["family"] == "gaussian" else None
    beta = cf.iloc[0].values; se = cf.iloc[1].values
    nll = float(m.get_current_neg_log_likelihood())
    return _std(beta, xn, se, covs, s2, reported_loglik=-nll, reported_criterion=2 * nll, converged=None,
                singular=None, warnings=[f"{w.category.__name__}: {w.message}" for w in wl], times=times,
                cov_par_names=names_cp, matrix_inversion_method=mim, engine_version=gpb.__version__)


# ------------------------------------------------------------------ lme4 through rpy2 (direct, no pymer4)
def fit_rpy2_lme4(spec, d, reps):
    import rpy2
    import rpy2.robjects as ro
    from rpy2.robjects import pandas2ri
    from rpy2.robjects.conversion import localconverter
    from rpy2.robjects.packages import importr
    importr("lme4")
    times = []
    for r in range(reps):
        t0 = time.perf_counter()
        with localconverter(ro.default_converter + pandas2ri.converter):
            rdf = ro.conversion.py2rpy(d)
        ro.globalenv["dd"] = rdf
        if spec["family"] == "gaussian":
            w = f", weights = dd${spec['weights']}" if spec["weights"] else ""
            ro.r(f"fm <- lme4::lmer({spec['formula']}, data = dd, REML = {'TRUE' if spec['reml'] else 'FALSE'}{w})")
        else:
            ro.r(f"fm <- lme4::glmer({spec['formula']}, data = dd, family = {spec['family']}, nAGQ = {spec['nagq']})")
        beta = np.array(ro.r("lme4::fixef(fm)")); names = list(ro.r("names(lme4::fixef(fm))"))
        se = np.sqrt(np.diag(np.array(ro.r("as.matrix(vcov(fm))"))))
        times.append(time.perf_counter() - t0)
    covs = []
    used = []
    nvc = int(ro.r("length(lme4::VarCorr(fm))")[0])
    vcn = list(ro.r("names(lme4::VarCorr(fm))"))
    for g, t in spec["re"]:
        for j in range(nvc):
            if j in used:
                continue
            tn = ["1" if x == "(Intercept)" else x for x in ro.r(f"colnames(lme4::VarCorr(fm)[[{j+1}]])")]
            if vcn[j].split(".")[0] == g and tn == t:
                used.append(j)
                covs.append(np.array(ro.r(f"unname(as.matrix(lme4::VarCorr(fm)[[{j+1}]]))")))
                break
    s2 = float(ro.r("sigma(fm)")[0]) ** 2 if spec["family"] == "gaussian" else None
    ll = float(ro.r("as.numeric(logLik(fm))")[0])
    return _std(beta, names, se, covs, s2, reported_loglik=ll, converged=None,
                singular=bool(ro.r("lme4::isSingular(fm)")[0]), warnings=[], times=times,
                engine_version=f"rpy2 {rpy2.__version__}; lme4 {ro.r('as.character(packageVersion(\"lme4\"))')[0]}")


ENGINES = dict(statsmodels=fit_statsmodels, mixedlm=fit_mixedlm, glmm=fit_glmm, gpboost=fit_gpboost,
               gpboost_chol=lambda spec, d, reps: fit_gpboost(spec, d, reps, mim="cholesky"),
               rpy2_lme4=fit_rpy2_lme4)
