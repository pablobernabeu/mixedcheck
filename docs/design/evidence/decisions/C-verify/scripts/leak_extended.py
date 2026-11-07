"""C-verify: extend C's plot-leakage experiment (C-E13) without oracle knowledge.

1. SVG: how many significant digits does matplotlib write per marker coordinate?
2. PNG with ordinary axes, ticks and tick labels (as a user would save it): the attacker
   locates the axes frame from the image, reads the axis limits from the tick labels
   (assumed known: -40..40 and 40..160 as printed), detects markers and takes the five
   blobs with the most extreme y WITHOUT using the true values; error is then measured.
3. Quantile displays: how close are the 5%/10% and 90%/95% quantiles to the most extreme
   individual values when a bin or factor has only k = 10 subjects (C's minimum)?
4. Contrast between the essential palette colours themselves (WCAG 1.4.11 'adjacent').

Usage: <venv python> -I leak_extended.py <out_dir>
"""
import json
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import ndimage

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(20261107)          # same generator and draws as C
n = 300
fitted = rng.normal(100, 15, n).round(2)
resid = (rng.standard_t(5, n) * 4).round(3)
rep = {}

# ---------- 1. SVG coordinate precision ----------
fig, ax = plt.subplots(figsize=(5, 4), dpi=100)
ax.scatter(fitted, resid, s=6, c="black", linewidths=0)
ax.set_xlim(40, 160); ax.set_ylim(-40, 40)
svg_path = out / "scatter.svg"; fig.savefig(svg_path, format="svg"); plt.close(fig)
svg = svg_path.read_text()
grp = re.search(r'<g id="PathCollection_1">(.*?)</g>', svg, re.S).group(1)
xs = re.findall(r'<use[^>]*x="([-\d.]+)"', grp)
decimals = [len(s.split(".")[1]) if "." in s else 0 for s in xs]
rep["svg_coordinate_decimals"] = {"min": int(min(decimals)), "max": int(max(decimals)),
                                  "n_markers": len(xs), "example": xs[:3]}

# ---------- 2. PNG with ticks: attacker without oracle ----------
fig, ax = plt.subplots(figsize=(5, 4), dpi=100)
ax.scatter(fitted, resid, s=4, c="black", linewidths=0)
ax.set_xlim(40, 160); ax.set_ylim(-40, 40)
ax.set_xlabel("Fitted"); ax.set_ylabel("Residual")
png_path = out / "scatter_ticks.png"; fig.savefig(png_path, dpi=100); plt.close(fig)
img = plt.imread(png_path)[..., :3].mean(axis=2)
H, W = img.shape
dark = img < 0.5
# frame: the axes spines are the longest dark rows / columns
row_runs = dark.sum(axis=1); col_runs = dark.sum(axis=0)
rows = np.where(row_runs > 0.6 * row_runs.max())[0]
cols = np.where(col_runs > 0.6 * col_runs.max())[0]
top, bottom = rows.min(), rows.max(); left, right = cols.min(), cols.max()
inner = dark.copy()
inner[: top + 2, :] = False; inner[bottom - 1:, :] = False
inner[:, : left + 2] = False; inner[:, right - 1:] = False
lab, nlab = ndimage.label(inner)
cents = np.array(ndimage.center_of_mass(inner, lab, range(1, nlab + 1)))
# pixel centres -> data using the frame (spine centre lines) and the printed limits
x0p, x1p = left + 0.5, right + 0.5          # column centres of left/right spine
y0p, y1p = bottom + 0.5, top + 0.5          # row centres of bottom/top spine
px_x = cents[:, 1] + 0.5; px_y = cents[:, 0] + 0.5
rx = 40 + (px_x - x0p) / (x1p - x0p) * 120
ry = -40 + (y0p - px_y) / (y0p - y1p) * 80
order = np.argsort(-np.abs(ry))[:5]          # attacker's five most extreme blobs
true_ext = np.argsort(-np.abs(resid))[:5]
errs = []
for k in order:
    # nearest true point to the attacker's estimate (evaluation only)
    j = int(np.argmin(np.hypot((fitted - rx[k]) / 120, (resid - ry[k]) / 80)))
    errs.append({"est_y": round(float(ry[k]), 3), "true_y": float(resid[j]),
                 "abs_err_y": round(float(abs(ry[k] - resid[j])), 3),
                 "is_true_top5": bool(j in true_ext)})
rep["png_ticks_attacker"] = {"frame_px": [int(left), int(right), int(top), int(bottom)],
                             "blobs": int(nlab), "five_most_extreme_blobs": errs,
                             "units_per_pixel_y": round(80 / (y0p - y1p), 3)}

# ---------- 3. tail quantiles with only k subjects ----------
def q7(x, p):
    return float(np.quantile(x, p))               # R type 7 / numpy 'linear'
sim = []
rng2 = np.random.default_rng(1)
for k in (10, 20, 30, 50, 200):
    d05, d10 = [], []
    for _ in range(2000):
        x = rng2.standard_normal(k)
        xs_ = np.sort(x)
        d05.append(abs(q7(x, 0.05) - xs_[0]))      # distance from 5% quantile to the minimum
        d10.append(abs(q7(x, 0.10) - xs_[0]))
    sim.append({"n_subjects": k,
                "median_dist_q05_to_min_SD": round(float(np.median(d05)), 3),
                "median_dist_q10_to_min_SD": round(float(np.median(d10)), 3),
                "q05_uses_order_stats": f"x({int(np.floor((k-1)*0.05))+1}) and x({int(np.floor((k-1)*0.05))+2})",
                "subjects_beyond_q05": int(np.floor(k * 0.05))})
rep["tail_quantile_with_k_subjects"] = sim

# ---------- 4. contrast between palette colours ----------
def lum(h):
    h = h.lstrip("#"); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def cr(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True); return (la + 0.05) / (lb + 0.05)
pal = {"blue": "#0072B2", "vermillion": "#D55E00", "bluish green": "#009E73",
       "reddish purple": "#CC79A7", "black": "#000000"}
okabe = {"orange": "#E69F00", "sky blue": "#56B4E9", "yellow": "#F0E442", "grey": "#999999"}
rep["contrast_vs_white"] = {k: round(cr(v, "#FFFFFF"), 2) for k, v in {**pal, **okabe}.items()}
names = list(pal)
rep["contrast_between_essential_colours"] = {f"{a} / {b}": round(cr(pal[a], pal[b]), 2)
                                             for i, a in enumerate(names) for b in names[i + 1:]}
(out / "leak_extended.json").write_text(json.dumps(rep, indent=2))
print(json.dumps(rep, indent=2))
