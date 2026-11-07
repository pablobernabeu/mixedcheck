"""Independent re-implementation (written from the textbook formulas, not from report A's common.py)
of the objectives used to compare engines.

Gaussian LMM, marginal form:  y ~ N(X b + off, V),  V = Z G Z' + s2 * W^-1
  ML   : -2 log L = n log(2 pi) + log|V| + r'V^-1 r,                    r = y - off - X b
  REML : lme4 convention  (n - p) log(2 pi) + log|V| + log|X'V^-1 X| + r'V^-1 r,  r at the GLS b
GLMM (non-spherical 'b-scale' form):
  Laplace: -2 sum log p(y|b~) + b~'G^-1 b~ + log|G| + log|Z'WZ + G^-1|
  AGQ(k) : scalar random intercept only, per-group adaptive Gauss-Hermite on the b scale.
Dense V is used up to n = 3000; above that, Woodbury with dense q x q blocks.
"""
import numpy as np
import pandas as pd
from scipy import linalg, special

GROUPCOLS = {"sleep": ["Subject"], "penicillin": ["plate", "sample"], "pastes": ["batch", "cask", "sample"],
             "cbpp": ["herd", "period"], "owls": ["Nest", "FoodTreatment", "SexParent"],
             "crossed": ["subj", "item"], "crossedbig": ["subj", "item"],
             "school": ["school", "class", "schoolclass"], "nearsing": ["g"], "weighted": ["g"],
             "binxd": ["subj", "item"], "jq": ["g"]}


def load(datadir, name):
    return pd.read_csv(f"{datadir}/{name}.csv", dtype={c: str for c in GROUPCOLS[name]})


def x_from_names(d, names):
    """Build X from R coefficient names: '(Intercept)', numeric 'x', factor dummy 'fLEVEL', 'a:b'."""
    cols = []
    def one(nm):
        if nm == "(Intercept)":
            return np.ones(len(d))
        if nm in d.columns:
            return d[nm].to_numpy(float)
        for c in d.columns:            # factor dummy: column name followed by a level label
            if nm.startswith(c) and not pd.api.types.is_numeric_dtype(d[c]) and nm[len(c):] in set(d[c]):
                return (d[c] == nm[len(c):]).to_numpy(float)
        raise KeyError(nm)
    for nm in names:
        parts = nm.split(":")
        v = np.ones(len(d))
        for p in parts:
            v = v * one(p)
        cols.append(v)
    return np.column_stack(cols)


def z_block(d, group, terms):
    """Z for one block (group, [terms]) with levels in sorted order; columns level-major."""
    lev = sorted(d[group].unique())
    idx = d[group].map({l: i for i, l in enumerate(lev)}).to_numpy()
    T = np.column_stack([np.ones(len(d)) if t in ("1", "(Intercept)") else d[t].to_numpy(float) for t in terms])
    k = T.shape[1]
    Z = np.zeros((len(d), len(lev) * k))
    for a in range(k):
        Z[np.arange(len(d)), idx * k + a] = T[:, a]
    return Z, len(lev), k


def build(d, blocks, covs):
    Zs, Gs = [], []
    for (g, terms), C in zip(blocks, covs):
        Z, J, k = z_block(d, g, terms)
        Zs.append(Z)
        Gs.append(np.kron(np.eye(J), np.atleast_2d(np.asarray(C, float))))
    return np.hstack(Zs), linalg.block_diag(*Gs)


def lmm(d, y, X, blocks, covs, s2, beta=None, reml=False, w=None, off=None):
    n, p = X.shape
    w = np.ones(n) if w is None else np.asarray(w, float)
    off = np.zeros(n) if off is None else off
    Z, G = build(d, blocks, covs)
    yy = y - off
    if n <= 3000:
        V = Z @ G @ Z.T + np.diag(s2 / w)
        cV = linalg.cho_factor(V, lower=True)
        logdetV = 2 * np.sum(np.log(np.diag(cV[0])))
        Vinv = lambda A: linalg.cho_solve(cV, A)
    else:   # Woodbury: V = D + Z G Z', D = s2/w;  needs G non-singular
        Dinv = w / s2
        Ginv = linalg.inv(G)
        M = Ginv + (Z * Dinv[:, None]).T @ Z
        cM = linalg.cho_factor(M, lower=True)
        logdetV = (np.sum(np.log(s2 / w)) + np.linalg.slogdet(G)[1] + 2 * np.sum(np.log(np.diag(cM[0]))))
        def Vinv(A):
            DA = A * (Dinv[:, None] if A.ndim == 2 else Dinv)
            return DA - (Z * Dinv[:, None]) @ linalg.cho_solve(cM, Z.T @ DA)
    if reml:
        VX = Vinv(X)
        XVX = X.T @ VX
        b = linalg.solve(XVX, VX.T @ yy, assume_a="pos")
        r = yy - X @ b
        return (n - p) * np.log(2 * np.pi) + logdetV + np.linalg.slogdet(XVX)[1] + r @ Vinv(r)
    r = yy - X @ np.asarray(beta, float)
    return n * np.log(2 * np.pi) + logdetV + r @ Vinv(r)


def _ll(family, y, eta, m):
    if family == "binomial":
        mu = special.expit(eta)
        ll = special.gammaln(m + 1) - special.gammaln(y + 1) - special.gammaln(m - y + 1) + y * eta - m * np.logaddexp(0, eta)
        return ll, y - m * mu, m * mu * (1 - mu)
    mu = np.exp(eta)
    return y * eta - mu - special.gammaln(y + 1), y - mu, mu


def glmm(d, y, X, blocks, covs, beta, family, m=None, off=None, nagq=1):
    n = len(y)
    off = np.zeros(n) if off is None else off
    Z, G = build(d, blocks, covs)
    Ginv = linalg.inv(G)
    eta0 = X @ np.asarray(beta, float) + off
    b = np.zeros(Z.shape[1])
    pen = lambda bb: _ll(family, y, eta0 + Z @ bb, m)[0].sum() - 0.5 * bb @ Ginv @ bb
    for it in range(500):          # Newton with step halving on the penalised log-likelihood
        ll, s, W = _ll(family, y, eta0 + Z @ b, m)
        grad = Z.T @ s - Ginv @ b
        H = Z.T @ (Z * W[:, None]) + Ginv
        step = linalg.solve(H, grad, assume_a="pos")
        f0, t = pen(b), 1.0
        while pen(b + t * step) < f0 - 1e-13 and t > 1e-10:
            t /= 2
        b = b + t * step
        if np.max(np.abs(t * step)) < 1e-11:
            break
    ll, s, W = _ll(family, y, eta0 + Z @ b, m)
    H = Z.T @ (Z * W[:, None]) + Ginv
    lap = -2 * ll.sum() + b @ Ginv @ b + np.linalg.slogdet(G)[1] + np.linalg.slogdet(H)[1]
    if nagq == 1:
        return lap
    assert len(blocks) == 1 and len(blocks[0][1]) == 1
    sb2 = float(np.atleast_2d(covs[0])[0, 0])
    g = blocks[0][0]
    lev = sorted(d[g].unique())
    gi = d[g].map({l: i for i, l in enumerate(lev)}).to_numpy()
    xk, wk = special.roots_hermite(nagq)
    tot = 0.0
    for j in range(len(lev)):
        rows = gi == j
        hj = W[rows].sum() + 1 / sb2
        sc = np.sqrt(2.0 / hj)
        logf = []
        for x in xk:
            bb = b[j] + sc * x
            lj = _ll(family, y[rows], eta0[rows] + bb, None if m is None else m[rows])[0].sum()
            logf.append(lj - 0.5 * bb * bb / sb2 - 0.5 * np.log(2 * np.pi * sb2))
        a = np.log(wk) + xk ** 2 + np.array(logf)
        tot += np.log(sc) + special.logsumexp(a)
    return -2 * tot
