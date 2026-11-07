"""Apply report A's proposed objective-match rule |reported - reference| <= max(1e-6*|dev|, 1e-6)
to every (engine, model) row of A's comparison_rows.json and list the rows that would be
declared contract_mismatch (Stream A stops)."""
import json, sys, math
rows = json.load(open(sys.argv[1]))
out = []
for r in rows:
    if r.get("status") != "ok":
        continue
    d = r.get("reported_minus_ref")
    if d is None and r["engine"].startswith("R:"):
        # R rows: reported_loglik given; recompute
        if r.get("reported_loglik") is not None:
            d = -2 * r["reported_loglik"] - r["ref_dev"]
    dev = r.get("ref_dev")
    if d is None or dev is None or (isinstance(d, float) and math.isnan(d)):
        out.append((r["model"], r["engine"], None, None, "no reported objective"))
        continue
    tol = max(1e-6 * abs(dev), 1e-6)
    flag = abs(d) > tol
    out.append((r["model"], r["engine"], d, tol, "MISMATCH" if flag else "ok"))
print(f"{'model':22s} {'engine':16s} {'reported-ref':>13s} {'tol':>9s} verdict")
for m, e, d, t, v in out:
    if v != "ok":
        ds = "NA" if d is None else f"{d:13.3e}"
        ts = "NA" if t is None else f"{t:9.1e}"
        print(f"{m:22s} {e:16s} {ds:>13s} {ts:>9s} {v}")
n_ok = sum(1 for x in out if x[4] == "ok"); n_mm = sum(1 for x in out if x[4] == "MISMATCH")
print(f"\nrows ok={n_ok} mismatch={n_mm} no-objective={len(out)-n_ok-n_mm}")
