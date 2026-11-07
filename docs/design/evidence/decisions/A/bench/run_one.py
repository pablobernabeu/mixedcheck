"""Run one engine on one model in a fresh process. Usage: run_one.py ENGINE MODEL OUTJSON [REPS]"""
import sys, os, json, time, traceback, resource
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from common import S, load, design, ref_objective
eng, mid, out = sys.argv[1], sys.argv[2], sys.argv[3]
reps = int(sys.argv[4]) if len(sys.argv) > 4 else 3
spec = S[mid]
rec = dict(engine=eng, model=mid)
t_import = time.perf_counter()
try:
    import engines
    d = load(os.environ.get("BENCH_DATA", "data"), spec["data"])
    res = engines.ENGINES[eng](spec, d, reps)
    rec.update(status="ok", **res)
    est = dict(beta=np.array(res["beta"]), covs=[np.array(c) for c in res["covs"]], sigma2=res["sigma2"])
    des = design(spec, os.environ.get("BENCH_DATA", "data"))
    rec.update(ref_objective(spec, des, est))
    for vname, v in (res.get("variants") or {}).items():
        e2 = dict(beta=np.array(v["beta"]), covs=[np.array(c) for c in v["covs"]], sigma2=v["sigma2"])
        v.update(ref_objective(spec, des, e2))
except engines.Unsupported as e:
    rec.update(status="unsupported", reason=str(e))
except Exception as e:
    rec.update(status="error", reason=f"{type(e).__name__}: {e}", traceback=traceback.format_exc()[-3000:])
rec["peak_rss_mb"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
rec["wall_total_s"] = time.perf_counter() - t_import
def conv(o):
    if isinstance(o, (np.floating,)): return float(o)
    if isinstance(o, (np.integer,)): return int(o)
    if isinstance(o, np.ndarray): return o.tolist()
    if isinstance(o, (np.bool_,)): return bool(o)
    return str(o)
json.dump(rec, open(out, "w"), default=conv, indent=1)
print(eng, mid, rec["status"], rec.get("reason", "")[:200])
