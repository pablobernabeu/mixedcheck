"""Canonical model specs, design builders and engine-independent reference objectives.

Reference objectives (all on the -2 log-likelihood scale, full constants included):
  * LMM ML:   -2 log L(beta, Sigma_b, sigma2) for y ~ N(X beta + offset, sigma2 W^-1 + Z G Z')
  * LMM REML: Harville's restricted -2 log L(Sigma_b, sigma2) with beta profiled by GLS, for the
              canonical X built here (the same X for every engine), plus the X-invariant version
              (-2 l_R - log|X'WX|), which does not depend on how X is parameterised.
  * GLMM Laplace: lme4's nAGQ = 1 definition, -2 log f(y | b~) + ||u~||^2 + log|I + L'Z'WZL|,
              conditional modes found by Newton iterations to 1e-12.
  * GLMM AGQ(k): adaptive Gauss-Hermite quadrature, scalar random intercept only.
The functions take *absolute* covariance matrices per random-effect block, so they are free of
each engine's internal parameterisation.
"""
import numpy as np
import pandas as pd
from scipy import special, linalg

CAT = {
    "sleep": ["Subject"], "penicillin": ["plate", "sample"],
    "pastes": ["batch", "cask", "sample"], "cbpp": ["herd", "period"],
    "owls": ["Nest", "FoodTreatment", "SexParent"], "crossed": ["subj", "item"],
    "crossedbig": ["subj", "item"], "school": ["school", "class", "schoolclass"],
    "nearsing": ["g"], "weighted": ["g"], "binxd": ["subj", "item"], "jq": ["g"],
}


def load(datadir, name):
    return pd.read_csv(f"{datadir}/{name}.csv", dtype={c: str for c in CAT.get(name, [])},
                       keep_default_na=False, na_values=[""])


# fixed: list of term labels: "1", numeric column, factor column, or "A:B" interaction
# re: list of (group, [terms]); terms "1" or numeric column. Blocks are independent of each other.
S = {}
def _add(mid, **kw):
    kw.setdefault("family", "gaussian"); kw.setdefault("reml", None); kw.setdefault("nagq", 1)
    kw.setdefault("weights", None); kw.setdefault("offset", None); kw.setdefault("trials", None)
    S[mid] = kw

for reml, sfx in [(True, "REML"), (False, "ML")]:
    _add(f"sleep_{sfx}", data="sleep", y="Reaction", fixed=["1", "Days"], re=[("Subject", ["1", "Days"])],
         reml=reml, formula="Reaction ~ Days + (Days | Subject)")
    _add(f"pen_{sfx}", data="penicillin", y="diameter", fixed=["1"], re=[("plate", ["1"]), ("sample", ["1"])],
         reml=reml, formula="diameter ~ 1 + (1 | plate) + (1 | sample)")
    _add(f"pastes_{sfx}", data="pastes", y="strength", fixed=["1"], re=[("batch", ["1"]), ("sample", ["1"])],
         reml=reml, formula="strength ~ 1 + (1 | batch) + (1 | sample)")
    _add(f"crossed_{sfx}", data="crossed", y="y", fixed=["1", "cond"],
         re=[("subj", ["1", "cond"]), ("item", ["1", "cond"])], reml=reml,
         formula="y ~ cond + (1 + cond | subj) + (1 + cond | item)")
    _add(f"crossed_zcp_{sfx}", data="crossed", y="y", fixed=["1", "cond"],
         re=[("subj", ["1"]), ("subj", ["cond"]), ("item", ["1"]), ("item", ["cond"])], reml=reml,
         formula="y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)")
    _add(f"school_{sfx}", data="school", y="y", fixed=["1", "x", "w"],
         re=[("school", ["1", "x"]), ("schoolclass", ["1"])], reml=reml,
         formula="y ~ x + w + (1 + x | school) + (1 | schoolclass)")
    _add(f"nearsing_{sfx}", data="nearsing", y="y", fixed=["1", "t"], re=[("g", ["1", "t"])], reml=reml,
         formula="y ~ t + (1 + t | g)")
    _add(f"weighted_{sfx}", data="weighted", y="y", fixed=["1", "x"], re=[("g", ["1"])], reml=reml,
         weights="w", formula="y ~ x + (1 | g)")
_add("sleep_zcp_ML", data="sleep", y="Reaction", fixed=["1", "Days"],
     re=[("Subject", ["1"]), ("Subject", ["Days"])], reml=False,
     formula="Reaction ~ Days + (1 | Subject) + (0 + Days | Subject)")
_add("school_zcp_ML", data="school", y="y", fixed=["1", "x", "w"],
     re=[("school", ["1"]), ("school", ["x"]), ("schoolclass", ["1"])], reml=False,
     formula="y ~ x + w + (1 | school) + (0 + x | school) + (1 | schoolclass)")
_add("nearsing_zcp_ML", data="nearsing", y="y", fixed=["1", "t"], re=[("g", ["1"]), ("g", ["t"])], reml=False,
     formula="y ~ t + (1 | g) + (0 + t | g)")
_add("crossedbig_REML", data="crossedbig", y="y", fixed=["1", "cond"],
     re=[("subj", ["1", "cond"]), ("item", ["1", "cond"])], reml=True,
     formula="y ~ cond + (1 + cond | subj) + (1 + cond | item)")
_add("crossedbig_zcp_REML", data="crossedbig", y="y", fixed=["1", "cond"],
     re=[("subj", ["1"]), ("subj", ["cond"]), ("item", ["1"]), ("item", ["cond"])], reml=True,
     formula="y ~ cond + (1 | subj) + (0 + cond | subj) + (1 | item) + (0 + cond | item)")
for nq, sfx in [(1, "laplace"), (25, "agq25")]:
    _add(f"cbpp_{sfx}", data="cbpp", y="incidence", trials="size", fixed=["1", "period"], re=[("herd", ["1"])],
         family="binomial", nagq=nq, formula="cbind(incidence, size - incidence) ~ period + (1 | herd)")
_add("owls_pois", data="owls", y="SiblingNegotiation", fixed=["1", "FoodTreatment", "SexParent",
     "FoodTreatment:SexParent"], re=[("Nest", ["1"])], family="poisson", offset="logBroodSize",
     formula="SiblingNegotiation ~ FoodTreatment * SexParent + offset(logBroodSize) + (1 | Nest)")
_add("owls_pois_agq25", data="owls", y="SiblingNegotiation", fixed=["1", "FoodTreatment", "SexParent",
     "FoodTreatment:SexParent"], re=[("Nest", ["1"])], family="poisson", offset="logBroodSize", nagq=25,
     formula="SiblingNegotiation ~ FoodTreatment * SexParent + offset(logBroodSize) + (1 | Nest)")


def _levels(series):
    return sorted(series.unique())


def build_X(d, fixed, catcols):
    cols, names = [], []
    def factor_dummies(c):
        lev = _levels(d[c])
        return [((d[c] == l).astype(float).values, f"{c}{l}") for l in lev[1:]]
    for t in fixed:
        if t == "1":
            cols.append(np.ones(len(d))); names.append("(Intercept)")
        elif ":" in t:
            a, b = t.split(":")
            da = factor_dummies(a) if a in catcols else [(d[a].values.astype(float), a)]
            db = factor_dummies(b) if b in catcols else [(d[b].values.astype(float), b)]
            for va, na in da:
                for vb, nb in db:
                    cols.append(va * vb); names.append(f"{na}:{nb}")
        elif t in catcols:
            for v, n in factor_dummies(t):
                cols.append(v); names.append(n)
        else:
            cols.append(d[t].values.astype(float)); names.append(t)
    return np.column_stack(cols), names


def build_Z(d, re):
    """Returns list of blocks: dict(group, terms, levels, Z (n x J*k dense, level-major))."""
    blocks = []
    for g, terms in re:
        lev = _levels(d[g]); J = len(lev); k = len(terms)
        idx = d[g].map({l: i for i, l in enumerate(lev)}).values
        T = np.column_stack([np.ones(len(d)) if t == "1" else d[t].values.astype(float) for t in terms])
        Z = np.zeros((len(d), J * k))
        for a in range(k):
            Z[np.arange(len(d)), idx * k + a] = T[:, a]
        blocks.append(dict(group=g, terms=terms, levels=lev, J=J, k=k, Z=Z))
    return blocks


def design(spec, datadir):
    d = load(datadir, spec["data"])
    X, xn = build_X(d, spec["fixed"], CAT.get(spec["data"], []))
    blocks = build_Z(d, spec["re"])
    y = d[spec["y"]].values.astype(float)
    w = d[spec["weights"]].values.astype(float) if spec["weights"] else np.ones(len(d))
    off = d[spec["offset"]].values.astype(float) if spec["offset"] else np.zeros(len(d))
    m = d[spec["trials"]].values.astype(float) if spec["trials"] else None
    return dict(d=d, X=X, xnames=xn, blocks=blocks, y=y, w=w, off=off, m=m)


def _lambda(blocks, covs, scale=1.0):
    """Block-diagonal factor Lambda with Lambda Lambda' = blockdiag(I_J kron cov_b)/scale (PSD-safe)."""
    facs = []
    for b, C in zip(blocks, covs):
        C = np.atleast_2d(np.asarray(C, float)) / scale
        ev, U = np.linalg.eigh((C + C.T) / 2)
        F = U * np.sqrt(np.clip(ev, 0, None))
        facs.append(np.kron(np.eye(b["J"]), F))
    return linalg.block_diag(*facs)


def lmm_dev(des, covs, sigma2, beta=None, reml=False):
    """-2 log L (ML, needs beta) or -2 l_R (REML, beta profiled). Returns dict."""
    X, y, w = des["X"], des["y"] - des["off"], des["w"]
    Z = np.hstack([b["Z"] for b in des["blocks"]])
    sw = np.sqrt(w)
    Xt, yt, Zt = X * sw[:, None], y * sw, Z * sw[:, None]
    Lam = _lambda(des["blocks"], covs, scale=sigma2)
    ZL = Zt @ Lam
    q = ZL.shape[1]
    M = np.eye(q) + ZL.T @ ZL
    cM = linalg.cho_factor(M, lower=True)
    logdetM = 2 * np.sum(np.log(np.diag(cM[0])))
    def Vinv(A):  # V_theta^-1 A, V_theta = I + ZL ZL'
        return A - ZL @ linalg.cho_solve(cM, ZL.T @ A)
    n, p = X.shape
    sumlogw = np.sum(np.log(w))
    if reml:
        VX = Vinv(Xt); XVX = Xt.T @ VX
        cX = linalg.cho_factor(XVX, lower=True)
        bhat = linalg.cho_solve(cX, VX.T @ yt)
        r = yt - Xt @ bhat
        quad = r @ Vinv(r)
        logdetXVX = 2 * np.sum(np.log(np.diag(cX[0])))
        dev = (n - p) * np.log(2 * np.pi * sigma2) - sumlogw + logdetM + logdetXVX + quad / sigma2
        sXX = np.linalg.slogdet(Xt.T @ Xt)[1]
        return dict(dev=dev, dev_invariant=dev - sXX, beta_gls=bhat)
    r = yt - Xt @ np.asarray(beta, float)
    quad = r @ Vinv(r)
    dev = n * np.log(2 * np.pi * sigma2) - sumlogw + logdetM + quad / sigma2
    return dict(dev=dev)


def _cond_loglik(family, y, eta, m):
    if family == "binomial":
        mu = special.expit(eta)
        ll = special.gammaln(m + 1) - special.gammaln(y + 1) - special.gammaln(m - y + 1) \
            + y * eta - m * np.logaddexp(0, eta)
        d1 = y - m * mu
        W = m * mu * (1 - mu)
    elif family == "poisson":
        mu = np.exp(eta)
        ll = y * eta - mu - special.gammaln(y + 1)
        d1 = y - mu
        W = mu
    else:
        raise ValueError(family)
    return ll, d1, W


def glmm_dev(des, covs, beta, family, nagq=1, tol=1e-12, maxit=200):
    """Laplace (nagq = 1) or AGQ (scalar random intercept only) -2 log L."""
    X, y, off, m = des["X"], des["y"], des["off"], des["m"]
    Z = np.hstack([b["Z"] for b in des["blocks"]])
    Lam = _lambda(des["blocks"], covs, scale=1.0)
    ZL = Z @ Lam
    q = ZL.shape[1]
    eta0 = X @ np.asarray(beta, float) + off
    u = np.zeros(q)
    for it in range(maxit):
        ll, d1, W = _cond_loglik(family, y, eta0 + ZL @ u, m)
        g = ZL.T @ d1 - u
        H = ZL.T @ (ZL * W[:, None]) + np.eye(q)
        step = linalg.solve(H, g, assume_a="pos")
        # damped Newton on the penalised log-likelihood
        obj0 = ll.sum() - 0.5 * u @ u
        lam = 1.0
        while lam > 1e-8:
            un = u + lam * step
            lln = _cond_loglik(family, y, eta0 + ZL @ un, m)[0].sum() - 0.5 * un @ un
            if lln >= obj0 - 1e-14:
                break
            lam /= 2
        u = un
        if np.max(np.abs(lam * step)) < tol:
            break
    ll, d1, W = _cond_loglik(family, y, eta0 + ZL @ u, m)
    H = ZL.T @ (ZL * W[:, None]) + np.eye(q)
    lap = -2 * ll.sum() + u @ u + np.linalg.slogdet(H)[1]
    if nagq == 1:
        return dict(dev=lap, newton_iter=it + 1)
    # AGQ: only a single scalar block (random intercept, one grouping factor)
    assert len(des["blocks"]) == 1 and des["blocks"][0]["k"] == 1
    b = des["blocks"][0]
    sd = np.sqrt(max(float(np.atleast_2d(covs[0])[0, 0]), 0.0))
    gidx = np.argmax(b["Z"], axis=1)
    xk, wk = np.polynomial.hermite.hermgauss(nagq)  # for exp(-x^2)
    tot = 0.0
    for j in range(b["J"]):
        rows = gidx == j
        h = (sd ** 2) * np.sum(W[rows]) + 1.0   # curvature in u at the mode (u spherical)
        uj = u[j]
        vals = []
        for z in xk:
            uu = uj + np.sqrt(2.0 / h) * z
            llj = _cond_loglik(family, y[rows], eta0[rows] + sd * uu, None if m is None else m[rows])[0].sum()
            vals.append(llj - 0.5 * uu ** 2)
        vals = np.array(vals)
        a = np.log(wk) + xk ** 2 + vals
        amax = a.max()
        logint = 0.5 * np.log(2.0 / h) + amax + np.log(np.sum(np.exp(a - amax))) - 0.5 * np.log(2 * np.pi)
        tot += logint
    return dict(dev=-2 * tot, laplace_dev=lap)


def ref_objective(spec, des, est):
    """Evaluate the reference objective at an engine's estimates (dict with beta, covs, sigma2)."""
    covs = est["covs"]
    if spec["family"] == "gaussian":
        if spec["reml"]:
            out = lmm_dev(des, covs, est["sigma2"], reml=True)
            out_ml = lmm_dev(des, covs, est["sigma2"], beta=est["beta"], reml=False)
            return dict(ref_dev=out["dev"], ref_dev_invariant=out["dev_invariant"], ref_ml_dev_at_est=out_ml["dev"])
        out = lmm_dev(des, covs, est["sigma2"], beta=est["beta"], reml=False)
        return dict(ref_dev=out["dev"])
    out = glmm_dev(des, covs, est["beta"], spec["family"], nagq=spec["nagq"])
    res = dict(ref_dev=out["dev"])
    if spec["nagq"] == 1 and len(des["blocks"]) == 1 and des["blocks"][0]["k"] == 1:
        res["ref_dev_agq25_at_est"] = glmm_dev(des, covs, est["beta"], spec["family"], nagq=25)["dev"]
    if spec["nagq"] > 1:
        res["ref_dev_laplace_at_est"] = out["laplace_dev"]
    return res

_add("binxd_laplace", data="binxd", y="y", trials="n", fixed=["1", "cond"],
     re=[("subj", ["1", "cond"]), ("item", ["1"])], family="binomial",
     formula="cbind(y, n - y) ~ cond + (1 + cond | subj) + (1 | item)")
_add("jq_REML", data="jq", y="y", fixed=["1", "x1", "x2"], re=[("g", ["1", "x1", "x2"])], reml=True,
     formula="y ~ x1 + x2 + (1 + x1 + x2 | g)")
