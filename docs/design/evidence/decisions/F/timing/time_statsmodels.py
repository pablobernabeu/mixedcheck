"""Key F, task 3 (Python side): time statsmodels MixedLM on the nested design used in
time_grid.R (random intercept + slope for x by cluster) and on a small crossed design
fitted as variance components (single all-data group). Budget-guarded; single-threaded.
Usage: python -I time_statsmodels.py <out_csv> [budget_seconds]
"""
import os, sys, time, warnings
for v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(v, "1")
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

out_csv = sys.argv[1]
budget = float(sys.argv[2]) if len(sys.argv) > 2 else 240.0
rng = np.random.default_rng(20261107)
t0 = time.perf_counter()
rows = []


def gen_nested(J, m, icc=0.2, slope_sd=0.3):
    g = np.repeat(np.arange(J), m)
    n = g.size
    z = np.repeat(np.resize([-0.5, 0.5], J), m)
    x = rng.normal(0, 0.5, J)[g] + rng.normal(size=n)
    tau0 = np.sqrt(icc / (1 - icc))
    eta = 0.2 * x + 0.3 * z + 0.1 * x * z + rng.normal(0, tau0, J)[g] + rng.normal(0, slope_sd, J)[g] * x
    return pd.DataFrame({"g": g, "x": x, "z": z, "y": eta + rng.normal(size=n)})


def gen_crossed(S, I, slope_sd=0.3):
    s = np.repeat(np.arange(S), I)
    i = np.tile(np.arange(I), S)
    A = np.where((s + i) % 2 == 0, -0.5, 0.5)
    eta = (0.2 * A + rng.normal(0, 0.5, S)[s] + rng.normal(0, slope_sd, S)[s] * A
           + rng.normal(0, 0.4, I)[i] + rng.normal(0, slope_sd, I)[i] * A)
    return pd.DataFrame({"subj": s, "item": i, "A": A, "y": eta + rng.normal(size=s.size), "one": 1})


def timed(fun):
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        t = time.perf_counter()
        try:
            res = fun()
            ok = bool(getattr(res, "converged", True))
        except Exception as e:  # record failures, do not stop the grid
            res, ok = None, False
            w.append(type("W", (), {"message": f"ERROR {e}"})())
        el = time.perf_counter() - t
    return el, ok, len(w)


for J, m in [(10, 5), (30, 20), (100, 20), (100, 50)]:
    for r in range(2):
        if time.perf_counter() - t0 > budget:
            break
        d = gen_nested(J, m)
        el, ok, nw = timed(lambda: smf.mixedlm("y ~ x * z", d, groups=d["g"], re_formula="~x").fit(reml=True))
        rows.append(dict(design="nested", size=f"J{J}_m{m}", n_obs=len(d), engine_family="statsmodels_gauss",
                         rep=r + 1, elapsed=el, converged=ok, n_warn=nw))
        print(f"[{time.perf_counter()-t0:6.1f}s] nested J{J} m{m} rep{r+1}: {el:.3f}s ok={ok}", flush=True)

for S, I in [(12, 8), (24, 16)]:
    for r in range(2):
        if time.perf_counter() - t0 > budget:
            break
        d = gen_crossed(S, I)
        vc = {"subj": "0 + C(subj)", "subjA": "0 + C(subj):A", "item": "0 + C(item)", "itemA": "0 + C(item):A"}
        el, ok, nw = timed(lambda: smf.mixedlm("y ~ A", d, groups=d["one"], re_formula="0", vc_formula=vc).fit(reml=True))
        rows.append(dict(design="crossed_vc", size=f"S{S}_I{I}", n_obs=len(d), engine_family="statsmodels_gauss",
                         rep=r + 1, elapsed=el, converged=ok, n_warn=nw))
        print(f"[{time.perf_counter()-t0:6.1f}s] crossed S{S} I{I} rep{r+1}: {el:.3f}s ok={ok}", flush=True)

pd.DataFrame(rows).to_csv(out_csv, index=False)
print(f"total {time.perf_counter()-t0:.1f}s")
