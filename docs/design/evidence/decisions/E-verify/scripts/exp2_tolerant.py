"""Extension of report E's experiment E2 (randomisation-unit inference).

The report's rule R1 requires treatment to be constant in EVERY cluster, so a
single miscoded row breaks it. Here we compare it with two outcome-free rules
that a T0 audit could reasonably use:

  R2 (tolerant level of variation): for each candidate level from coarsest to
     finest, compute the share of rows whose treatment equals their cluster's
     modal treatment; return the coarsest level where that share >= 0.99 and
     both arms occur across clusters. Rows that deviate are listed as a
     separate finding ('treatment not constant within <level> for k rows').
  R3 (stepped-wedge pattern): within each cluster, treatment is a
     non-decreasing function of a declared or candidate time column, with
     switch times differing between clusters.

Neither rule can say whether treatment was RANDOMISED or what the blocks
were; they only estimate the level at which treatment varies.
Usage: python -I exp2_tolerant.py <report_E_scripts_dir> <out_csv> [n_rep]
"""
import csv
import sys

import numpy as np

sys.path.insert(0, sys.argv[1])
import exp2_randomisation_unit as e2  # noqa: E402  (report E's generators and R1)


def r2(levels, treat, thr=0.99):
    for name, codes in levels:
        order = np.argsort(codes, kind="stable")
        c, t = codes[order], treat[order]
        bounds = np.flatnonzero(np.diff(c)) + 1
        agree = 0
        modes = []
        for seg in np.split(t, bounds):
            m = 1 if seg.mean() >= 0.5 else 0
            modes.append(m)
            agree += int((seg == m).sum())
        if agree / t.size >= thr and len(set(modes)) == 2:
            return name
    return "row"


def s1_both(rng, p_err, J=20, K=3, n=20):
    school = np.repeat(np.arange(J), K * n)
    klass = np.repeat(np.arange(J * K), n)
    arm = rng.permutation(np.r_[np.zeros(J // 2), np.ones(J - J // 2)])
    treat = arm[school].astype(int)
    flip = rng.random(treat.size) < p_err
    treat[flip] = 1 - treat[flip]
    lv = [("school", school), ("class", klass)]
    return e2.r1(lv, treat) == "school", r2(lv, treat) == "school"


def s2_both(rng, F, sizes=(1, 2, 3), probs=(0.6, 0.3, 0.1)):
    fs = rng.choice(sizes, size=F, p=probs)
    fam = np.repeat(np.arange(F), fs)
    treat = rng.integers(0, 2, fam.size)
    lv = [("family", fam)]
    return e2.r1(lv, treat) == "row", r2(lv, treat) == "row"


def s4_r3(rng, J=10, T=5, n=20):
    school = np.repeat(np.arange(J), T * n)
    period = np.tile(np.repeat(np.arange(T), n), J)
    start = rng.integers(1, T, J)
    treat = (period >= start[school]).astype(int)
    ok = True
    switch = []
    for j in range(J):
        tj, pj = treat[school == j], period[school == j]
        o = np.argsort(pj, kind="stable")
        if np.any(np.diff(tj[o]) < 0):
            ok = False
        switch.append(int(pj[o][np.argmax(tj[o])]) if tj.max() == 1 else T)
    return ok and len(set(switch)) > 1


def main():
    out = sys.argv[2]
    n_rep = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
    rng = np.random.default_rng(20261107)
    rows = []
    for p in (0.0, 0.0005, 0.001, 0.005, 0.02):
        res = np.array([s1_both(rng, p) for _ in range(n_rep)])
        rows.append(("S1 school CRT, per-row miscoding probability", p, res[:, 0].mean(), res[:, 1].mean()))
    for F in (10, 20, 50):
        res = np.array([s2_both(rng, F) for _ in range(n_rep)])
        rows.append(("S2 individual randomisation in families, n families", F, res[:, 0].mean(), res[:, 1].mean()))
    ok = np.mean([s4_r3(rng) for _ in range(n_rep)])
    rows.append(("S4 stepped wedge detected as monotone switch pattern (R3)", 0, float("nan"), ok))
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["scenario", "parameter", "p_R1_true_unit", "p_R2_or_R3_true_unit", "n_rep"])
        for sc, par, a, b in rows:
            w.writerow([sc, par, round(float(a), 4), round(float(b), 4), n_rep])
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
