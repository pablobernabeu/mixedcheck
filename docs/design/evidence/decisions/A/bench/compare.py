"""Build the comparison tables: every engine vs lme4 and vs the common reference objective."""
import json, glob, os, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import S, design, ref_objective
from rmap import r_est

HERE = os.path.dirname(os.path.abspath(__file__))
R = json.load(open(os.path.join(HERE, "r_reference.json")))
rows = []
cache = {}

def des_for(sp):
    key = (sp["data"], str(sp["re"]), str(sp["fixed"]), sp["weights"], sp["offset"], sp["trials"])
    if key not in cache:
        cache[key] = design(sp, os.path.join(HERE, "data"))
    return cache[key]

def sd_corr(C):
    C = np.atleast_2d(np.array(C, float)); sd = np.sqrt(np.clip(np.diag(C), 0, None))
    with np.errstate(invalid="ignore", divide="ignore"):
        cor = C / np.outer(sd, sd)
    return sd, cor

# R results -> rows with reference objective
for r in R["results"]:
    sp = S[r["model"]]
    est = r_est(sp, r)
    ro = ref_objective(sp, des_for(sp), dict(beta=est["beta"], covs=est["covs"], sigma2=est["sigma2"]))
    rows.append(dict(model=r["model"], engine="R:" + r["engine"], status="ok", beta=est["beta"].tolist(),
                     se=list(r["se"].values()), covs=[c.tolist() for c in est["covs"]], sigma2=est["sigma2"],
                     reported_loglik=r["logLik"], time_median=r["time_median"],
                     converged=(not r.get("warnings")) if r["engine"] == "lme4" else (r.get("pdHess") and r.get("convergence") == 0),
                     singular=r.get("singular"), n_warnings=len(r.get("warnings") or []),
                     warnings=r.get("warnings"), messages=(r.get("messages") or [])[:1], **ro))

# Python engine results
for f in sorted(glob.glob(os.path.join(HERE, "out", "*__*.json"))):
    p = json.load(open(f))
    base = dict(model=p["model"], engine=p["engine"], status=p["status"], reason=p.get("reason"),
                peak_rss_mb=p.get("peak_rss_mb"))
    if p["status"] != "ok":
        rows.append(base); continue
    t = p.get("times") or []
    base.update(beta=p["beta"], se=p["se"], covs=p["covs"], sigma2=p["sigma2"], names=p.get("names"),
                reported_loglik=p.get("reported_loglik"), time_median=float(np.median(t)) if t else None,
                time_first=t[0] if t else None, converged=p.get("converged"), singular=p.get("singular"),
                n_warnings=len(p.get("warnings") or []), warnings=(p.get("warnings") or [])[:3],
                engine_version=p.get("engine_version"),
                **{k: v for k, v in p.items() if k.startswith("ref_")})
    rows.append(base)
    for vname, v in (p.get("variants") or {}).items():
        vt = v.get("times") or []
        rows.append(dict(model=p["model"], engine=f"{p['engine']}:{vname}", status="ok", beta=v["beta"], se=v["se"],
                         covs=v["covs"], sigma2=v["sigma2"], time_median=float(np.median(vt)) if vt else None,
                         converged=None, singular=None, n_warnings=len(v.get("warnings") or []),
                         peak_rss_mb=p.get("peak_rss_mb"),
                         **{k: vv for k, vv in v.items() if k.startswith("ref_")}))

# comparisons vs lme4 and vs the best objective per model
by_model = {}
for r in rows:
    by_model.setdefault(r["model"], []).append(r)
for mid, rs in by_model.items():
    lme = [r for r in rs if r["engine"] == "R:lme4"][0]
    best = min(r["ref_dev"] for r in rs if r.get("status") == "ok" and r.get("ref_dev") is not None
               and not (isinstance(r["ref_dev"], float) and math.isnan(r["ref_dev"])))
    sdl = [sd_corr(c) for c in lme["covs"]]
    for r in rs:
        if r.get("status") != "ok":
            continue
        r["obj_gap"] = r["ref_dev"] - best
        r["obj_gap_vs_lme4"] = r["ref_dev"] - lme["ref_dev"]
        b, bl = np.array(r["beta"]), np.array(lme["beta"])
        sel = np.array(lme["se"])
        r["max_abs_dbeta_in_se"] = float(np.max(np.abs(b - bl) / sel)) if len(b) == len(bl) else None
        se = np.array(r["se"], float)
        r["max_rel_dse"] = float(np.nanmax(np.abs(se / sel - 1))) if len(se) == len(sel) else None
        dsd, dcor = [], []
        for c, (sd0, cor0) in zip(r["covs"], sdl):
            sd1, cor1 = sd_corr(c)
            scl = math.sqrt(lme["sigma2"]) if lme.get("sigma2") else 1.0
            with np.errstate(invalid="ignore", divide="ignore"):
                # relative difference; SDs at or near the boundary (< 1e-3 of the residual SD, or of 1 for
                # GLMMs) are compared on that absolute scale instead
                rel = np.abs(sd1 - sd0) / np.maximum(sd0, 1e-3 * scl)
            dsd.append(np.nanmax(rel))
            if len(sd0) > 1:
                iu = np.triu_indices(len(sd0), 1)
                dcor.append(np.nanmax(np.abs(np.nan_to_num(cor1[iu]) - np.nan_to_num(cor0[iu]))))
        r["max_rel_dsd"] = float(np.max(dsd)) if dsd else None
        r["max_abs_dcor"] = float(np.max(dcor)) if dcor else None
        if r.get("sigma2") is not None and lme.get("sigma2"):
            r["rel_dsigma"] = abs(math.sqrt(r["sigma2"]) / math.sqrt(lme["sigma2"]) - 1)
        if r.get("reported_loglik") is not None:
            r["reported_minus_ref"] = -2 * r["reported_loglik"] - r["ref_dev"]
        r["time_ratio_vs_lme4"] = (r["time_median"] / lme["time_median"]) if r.get("time_median") else None

json.dump(rows, open(os.path.join(HERE, "comparison_rows.json"), "w"), indent=1, default=float)

# ------------------------------------------------------------------ tables
def fmt(x, nd=3, sci=False):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "NA"
    if isinstance(x, bool):
        return str(x)
    if sci:
        return f"{x:.1e}"
    return f"{x:.{nd}f}"

order_eng = ["R:lme4", "R:glmmTMB", "rpy2_lme4", "glmm", "mixedlm", "statsmodels", "statsmodels:map",
             "gpboost_chol", "gpboost"]
lines = ["| model | engine | status | -2logL (common objective) | gap vs best | max abs dbeta (SE units) | max rel dSE | max rel dSD (boundary-safe) | max abs dcor | rel dsigma | reported minus common | conv | sing | warn | fit time s (median) | x lme4 |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
csv = ["model,engine,status,reason,ref_dev,obj_gap,max_abs_dbeta_in_se,max_rel_dse,max_rel_dsd,max_abs_dcor,rel_dsigma,reported_minus_ref,converged,singular,n_warnings,time_median,time_first,time_ratio_vs_lme4,peak_rss_mb,ref_dev_invariant,ref_dev_agq25_at_est,ref_dev_laplace_at_est"]
for mid in S:
    rs = by_model.get(mid, [])
    rs = sorted(rs, key=lambda r: order_eng.index(r["engine"]) if r["engine"] in order_eng else 99)
    for r in rs:
        if r.get("status") != "ok":
            lines.append(f"| {mid} | {r['engine']} | {r['status']}: {str(r.get('reason'))[:70]} |" + " |" * 13)
        else:
            lines.append("| " + " | ".join([mid, r["engine"], "ok", fmt(r["ref_dev"], 4), fmt(r["obj_gap"], sci=True),
                         fmt(r.get("max_abs_dbeta_in_se"), sci=True), fmt(r.get("max_rel_dse"), sci=True),
                         fmt(r.get("max_rel_dsd"), sci=True), fmt(r.get("max_abs_dcor"), sci=True),
                         fmt(r.get("rel_dsigma"), sci=True), fmt(r.get("reported_minus_ref"), sci=True),
                         str(r.get("converged")), str(r.get("singular")), str(r.get("n_warnings")),
                         fmt(r.get("time_median"), 4), fmt(r.get("time_ratio_vs_lme4"), 1)]) + " |")
        csv.append(",".join(str(x) for x in [mid, r["engine"], r.get("status"), json.dumps(str(r.get("reason") or "")),
                   r.get("ref_dev"), r.get("obj_gap"), r.get("max_abs_dbeta_in_se"), r.get("max_rel_dse"),
                   r.get("max_rel_dsd"), r.get("max_abs_dcor"), r.get("rel_dsigma"), r.get("reported_minus_ref"),
                   r.get("converged"), r.get("singular"), r.get("n_warnings"), r.get("time_median"),
                   r.get("time_first"), r.get("time_ratio_vs_lme4"), r.get("peak_rss_mb"),
                   r.get("ref_dev_invariant"), r.get("ref_dev_agq25_at_est"), r.get("ref_dev_laplace_at_est")]))
open(os.path.join(HERE, "benchmark_table.md"), "w").write("\n".join(lines) + "\n")
open(os.path.join(HERE, "benchmark_table.csv"), "w").write("\n".join(csv) + "\n")

# per-engine summary
summ = ["| engine | models run ok | unsupported | errors/timeouts | at optimum (gap <= 1e-4 abs or 1e-9 rel) | near (gap <= 1e-2) | worse (gap > 1e-2) | max dbeta (SE units) | max rel dSE | median fit time ratio vs lme4 |",
        "|---|---|---|---|---|---|---|---|---|---|"]
for e in order_eng:
    rs = [r for r in rows if r["engine"] == e]
    ok = [r for r in rs if r.get("status") == "ok"]
    uns = [r for r in rs if r.get("status") == "unsupported"]
    err = [r for r in rs if r.get("status") in ("error", "timeout", "crash")]
    def at(r): return r["obj_gap"] <= max(1e-4, 1e-9 * abs(r["ref_dev"]))
    a = [r for r in ok if at(r)]; nr = [r for r in ok if not at(r) and r["obj_gap"] <= 1e-2]
    w = [r for r in ok if r["obj_gap"] > 1e-2]
    mdb = max([r["max_abs_dbeta_in_se"] for r in ok if r.get("max_abs_dbeta_in_se") is not None] or [float("nan")])
    mse = max([r["max_rel_dse"] for r in ok if r.get("max_rel_dse") is not None] or [float("nan")])
    tr = np.median([r["time_ratio_vs_lme4"] for r in ok if r.get("time_ratio_vs_lme4")]) if ok else float("nan")
    summ.append(f"| {e} | {len(ok)} | {len(uns)} | {len(err)} | {len(a)} | {len(nr)} | {len(w)}: {', '.join(r['model'] for r in w)} | {fmt(mdb, sci=True)} | {fmt(mse, sci=True)} | {fmt(tr, 2)} |")
open(os.path.join(HERE, "engine_summary.md"), "w").write("\n".join(summ) + "\n")
print("\n".join(summ))
