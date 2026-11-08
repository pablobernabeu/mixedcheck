import json, sys, numpy as np
from common import S, design, ref_objective
from rmap import r_est
R = json.load(open("r_reference.json"))
cache = {}
print(f"{'model':22s} {'engine':8s} {'reported':>16s} {'ref_obj':>16s} {'diff':>12s}")
for r in R["results"]:
    sp = S[r["model"]]
    des = cache.setdefault(sp["data"] + str(sp["re"]) + str(sp["fixed"]), design(sp, "data"))
    est = r_est(sp, r)
    if r["logLik"] is None:
        print(f"{r['model']:22s} {r['engine']:8s} {'NA':>16s}"); 
    ro = ref_objective(sp, des, est)
    if sp["family"] == "gaussian" and sp["reml"]:
        rep = -2 * r["logLik"] if r["logLik"] is not None else float('nan')
    else:
        rep = -2 * r["logLik"] if r["logLik"] is not None else float('nan')
    print(f"{r['model']:22s} {r['engine']:8s} {rep:16.6f} {ro['ref_dev']:16.6f} {ro['ref_dev']-rep:12.2e}  {({k: round(v,6) for k,v in ro.items() if k!='ref_dev'})}")
