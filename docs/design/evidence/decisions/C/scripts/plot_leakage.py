"""How much participant-level data do common diagnostic-plot outputs carry?

Key C (Q5). Simulates 300 children's fitted values and residuals, then
1. saves a matplotlib scatter as SVG and recovers every point from the file;
2. saves the same scatter as a 100-dpi PNG and recovers points by blob detection;
3. saves a plotly scatter as HTML and decodes the embedded arrays and hover IDs;
4. builds a binned, count-suppressed alternative (k = 10) and reports what it shows.

Usage: python -I plot_leakage.py <out_dir>
"""
import base64
import json
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import ndimage

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(20261107)
n = 300
fitted = rng.normal(100, 15, n).round(2)          # e.g. predicted reading score
resid = (rng.standard_t(5, n) * 4).round(3)        # conditional residual
ids = np.array([f"pupil_{i:04d}" for i in range(n)])
report = {}

# ---------- 1. SVG scatter: exact recovery ----------
fig, ax = plt.subplots(figsize=(5, 4), dpi=100)
ax.scatter(fitted, resid, s=6, c="black", linewidths=0)
ax.set_xlim(40, 160); ax.set_ylim(-40, 40)
ax.set_xlabel("Fitted"); ax.set_ylabel("Residual")
svg_path = out / "scatter.svg"
fig.savefig(svg_path, format="svg")
# transform data->display (points, 72 per inch in SVG) for inversion
disp = ax.transData.transform(np.column_stack([fitted, resid]))
fig_h_px = fig.get_size_inches()[1] * fig.dpi
plt.close(fig)
svg = svg_path.read_text()
# matplotlib writes scatter markers as <use xlink:href=... x="..." y="..."/> inside
# the <g id="PathCollection_1"> group (tick marks use <use> elements elsewhere)
grp = re.search(r'<g id="PathCollection_1">(.*?)</g>', svg, re.S).group(1)
uses = re.findall(r'<use[^>]*x="([-\d.]+)"[^>]*y="([-\d.]+)"', grp)
pts = np.array([[float(a), float(b)] for a, b in uses])
# SVG units are points (72/inch); display units are pixels at dpi=100
scale = 72 / 100
# Fit the affine map from SVG coordinates to data coordinates using the known data
# (an attacker would instead read it from the tick labels; two ticks per axis suffice)
A = np.column_stack([pts, np.ones(len(pts))])
coef_x, *_ = np.linalg.lstsq(A, fitted[: len(pts)], rcond=None)
coef_y, *_ = np.linalg.lstsq(A, resid[: len(pts)], rcond=None)
rec_x = A @ coef_x; rec_y = A @ coef_y
report["svg"] = {
    "file_bytes": svg_path.stat().st_size,
    "points_in_file": int(len(pts)),
    "max_abs_error_fitted": float(np.max(np.abs(rec_x - fitted[: len(pts)]))),
    "max_abs_error_resid": float(np.max(np.abs(rec_y - resid[: len(pts)]))),
    "note": "markers are written in data order, one <use> element per observation",
}

# ---------- 2. PNG scatter: recovery by blob detection ----------
fig, ax = plt.subplots(figsize=(5, 4), dpi=100)
ax.scatter(fitted, resid, s=4, c="black", linewidths=0)
ax.set_xlim(40, 160); ax.set_ylim(-40, 40)
ax.set_xticks([]); ax.set_yticks([])
for s in ax.spines.values():
    s.set_visible(False)
png_path = out / "scatter.png"
fig.canvas.draw()
bbox = ax.get_window_extent()  # pixels, origin bottom-left
fig.savefig(png_path, dpi=100)
plt.close(fig)
img = plt.imread(png_path)[..., :3].mean(axis=2)
H, W = img.shape
mask = img < 0.6
lab, nlab = ndimage.label(mask)
cents = np.array(ndimage.center_of_mass(mask, lab, range(1, nlab + 1)))  # (row, col)
sizes = ndimage.sum(mask, lab, range(1, nlab + 1))
px_x = cents[:, 1] + 0.5
px_y = (H - cents[:, 0]) - 0.5
rx = 40 + (px_x - bbox.x0) / bbox.width * 120
ry = -40 + (px_y - bbox.y0) / bbox.height * 80
true = np.column_stack([fitted, resid])
single = sizes <= np.median(sizes) * 1.5  # blobs that are one marker, not merged ones
errs = []
for x, y in zip(rx[single], ry[single]):
    dd = np.hypot((true[:, 0] - x) / 120, (true[:, 1] - y) / 80)
    j = int(np.argmin(dd))
    errs.append((abs(true[j, 0] - x), abs(true[j, 1] - y)))
errs = np.array(errs)
extreme = np.argsort(-np.abs(resid))[:5]
ext_err = []
for j in extreme:
    dd = np.hypot((rx - fitted[j]) / 120, (ry - resid[j]) / 80)
    k = int(np.argmin(dd))
    ext_err.append(float(abs(ry[k] - resid[j])))
report["png_100dpi"] = {
    "file_bytes": png_path.stat().st_size,
    "blobs_found": int(nlab), "single_marker_blobs": int(single.sum()),
    "median_abs_error_fitted": float(np.median(errs[:, 0])),
    "median_abs_error_resid": float(np.median(errs[:, 1])),
    "p95_abs_error_resid": float(np.quantile(errs[:, 1], 0.95)),
    "five_most_extreme_resid_true": [float(resid[j]) for j in extreme],
    "five_most_extreme_resid_abs_error": ext_err,
}

# ---------- 3. plotly HTML: decode embedded arrays and hover IDs ----------
import plotly.graph_objects as go
figp = go.Figure(go.Scatter(x=fitted, y=resid, mode="markers", text=ids,
                            hovertemplate="%{text}<br>fitted=%{x}<br>resid=%{y}"))
html_path = out / "scatter_plotly.html"
figp.write_html(html_path, include_plotlyjs="cdn")
html = html_path.read_text()
ids_found = sum(1 for i in ids if i in html)
dec = {}
for key in ("x", "y"):
    m = re.search(r'"%s":\{"dtype":"(\w+)","bdata":"([^"]+)"' % key, html)
    if m:
        dt, b = m.group(1), json.loads('"' + m.group(2) + '"')  # undo / escapes
        dec[key] = np.frombuffer(base64.b64decode(b), dtype=np.dtype(dt))
    else:
        m2 = re.search(r'"%s":\[([^\]]+)\]' % key, html)
        dec[key] = np.array(json.loads("[" + m2.group(1) + "]")) if m2 else None
report["plotly_html"] = {
    "file_bytes": html_path.stat().st_size,
    "external_script_cdn": bool(re.search(r'<script[^>]+src="https://cdn\.plot\.ly', html)),
    "ids_found_in_plain_text": int(ids_found),
    "x_encoding": "base64 typed array" if '"bdata"' in html else "JSON list",
    "x_exact": bool(dec["x"] is not None and np.array_equal(dec["x"], fitted)),
    "y_exact": bool(dec["y"] is not None and np.array_equal(dec["y"], resid)),
}

# ---------- 4. Binned alternative with minimum cell count ----------
k = 10
xb = np.quantile(fitted, np.linspace(0, 1, 11))          # deciles of fitted
bins = np.clip(np.searchsorted(xb, fitted, side="right") - 1, 0, 9)
rows = []
for b in range(10):
    r = resid[bins == b]
    rows.append({"bin": b, "n": int(r.size),
                 "q10": float(np.quantile(r, .10)), "q50": float(np.quantile(r, .50)),
                 "q90": float(np.quantile(r, .90)), "mean": float(r.mean()),
                 "suppressed": bool(r.size < k)})
outside = int(np.sum(np.abs(resid) > 3 * np.std(resid)))
report["binned_alternative"] = {
    "bins": rows,
    "min_bin_n": min(r["n"] for r in rows),
    "count_abs_resid_gt_3sd_reported_as_count_only": outside,
    "note": "decile bins of fitted values; residual 10/50/90% quantiles per bin; no point "
            "positions, no min/max, no IDs. Bin edges are rounded quantiles, so the extreme "
            "edges are not the sample min and max only if the outer edges are dropped or "
            "replaced by open intervals.",
}
(out / "plot_leakage.json").write_text(json.dumps(report, indent=2))
print(json.dumps({k: {kk: vv for kk, vv in v.items() if kk != 'bins'} for k, v in report.items()}, indent=2))
