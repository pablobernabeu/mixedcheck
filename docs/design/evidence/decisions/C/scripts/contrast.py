"""WCAG 2.x contrast ratios of candidate plot colours against light and dark backgrounds.

Key C (Q5). Relative luminance and contrast ratio as defined in WCAG 2.2
(sRGB linearisation threshold 0.04045; ratio (L1 + 0.05) / (L2 + 0.05)).
Usage: python3 -I contrast.py <out_csv>
"""
import csv
import sys

def lum(hexcol):
    h = hexcol.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)

okabe_ito = {
    "black": "#000000", "orange": "#E69F00", "sky blue": "#56B4E9",
    "bluish green": "#009E73", "yellow": "#F0E442", "blue": "#0072B2",
    "vermillion": "#D55E00", "reddish purple": "#CC79A7", "grey": "#999999",
}
backgrounds = {"white": "#FFFFFF", "dark #121212": "#121212", "dark #1E1E1E": "#1E1E1E"}
rows = []
for name, col in okabe_ito.items():
    r = {"colour": name, "hex": col}
    for bn, bg in backgrounds.items():
        r[f"vs {bn}"] = round(ratio(col, bg), 2)
    r["passes_3to1_white"] = r["vs white"] >= 3
    r["passes_3to1_dark121212"] = r["vs dark #121212"] >= 3
    rows.append(r)
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader(); w.writerows(rows)
for r in rows:
    print(r)
both = [r["colour"] for r in rows if r["passes_3to1_white"] and r["passes_3to1_dark121212"]]
print("passes 3:1 on white and on #121212:", both)
