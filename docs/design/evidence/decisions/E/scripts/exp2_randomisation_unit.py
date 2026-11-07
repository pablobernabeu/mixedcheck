"""Experiment E2: can the randomisation unit be inferred from the data?

Rule R1 (the obvious inference): the randomisation unit is the coarsest
candidate grouping level within which treatment is constant in every cluster;
if treatment varies within every candidate level, the unit is the row.

Scenarios (all outcome-free):
  S1 school-randomised CRT with a small rate of miscoded or contaminated rows
  S2 individually randomised trial in families (mostly singletons)
  S3 class-randomised trial, complete randomisation of classes ignoring school
  S4 stepped-wedge trial (treatment switches on within clusters over time)
For each, report how often R1 returns the true unit.

Usage: python -I exp2_randomisation_unit.py <out_csv> [n_rep]
"""
import csv
import sys

import numpy as np


def r1(levels, treat):
    """levels: list of (name, codes) from coarsest to finest; returns name."""
    for name, codes in levels:
        ok = True
        # treatment constant within every cluster of this level?
        order = np.argsort(codes, kind="stable")
        c, t = codes[order], treat[order]
        bounds = np.flatnonzero(np.diff(c)) + 1
        for seg in np.split(t, bounds):
            if seg.min() != seg.max():
                ok = False
                break
        if ok:
            return name
    return "row"


def s1(rng, p_err, J=20, K=3, n=20):
    school = np.repeat(np.arange(J), K * n)
    klass = np.repeat(np.arange(J * K), n)
    arm = rng.permutation(np.r_[np.zeros(J // 2), np.ones(J - J // 2)])
    treat = arm[school].astype(int)
    flip = rng.random(treat.size) < p_err
    treat[flip] = 1 - treat[flip]
    return r1([("school", school), ("class", klass)], treat) == "school"


def s2(rng, F, sizes=(1, 2, 3), probs=(0.6, 0.3, 0.1)):
    fs = rng.choice(sizes, size=F, p=probs)
    fam = np.repeat(np.arange(F), fs)
    treat = rng.integers(0, 2, fam.size)          # individual randomisation
    return r1([("family", fam)], treat) == "row"  # truth: individual (row)


def s3(rng, k, J=10, n=20):
    school = np.repeat(np.arange(J), k * n)
    klass = np.repeat(np.arange(J * k), n)
    C = J * k
    arm = rng.permutation(np.r_[np.zeros(C // 2), np.ones(C - C // 2)])
    treat = arm[klass].astype(int)
    got = r1([("school", school), ("class", klass)], treat)
    return got == "class" or (k == 1 and got == "school")  # k = 1: aliased


def s4(rng, J=10, T=5, n=20):
    school = np.repeat(np.arange(J), T * n)
    period = np.tile(np.repeat(np.arange(T), n), J)
    start = rng.integers(1, T, J)                 # each school crosses over once
    treat = (period >= start[school]).astype(int)
    sp = school * T + period
    got = r1([("school", school), ("school_period", sp)], treat)
    return got == "school"  # truth: the school is randomised (to a sequence)


def main():
    out = sys.argv[1]
    n_rep = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    rng = np.random.default_rng(20261107)
    rows = []
    for p in (0.0, 0.0005, 0.001, 0.005):
        ok = np.mean([s1(rng, p) for _ in range(n_rep)])
        rows.append(("S1 school CRT, row miscoding rate", p, ok))
    for F in (10, 20, 50, 200):
        ok = np.mean([s2(rng, F) for _ in range(n_rep)])
        rows.append(("S2 individual randomisation in families, n families", F, ok))
    for k in (1, 2, 3):
        ok = np.mean([s3(rng, k) for _ in range(n_rep)])
        rows.append(("S3 class randomisation ignoring school, classes per school", k, ok))
    ok = np.mean([s4(rng) for _ in range(n_rep)])
    rows.append(("S4 stepped wedge, 10 schools x 5 periods", 0, ok))
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["scenario", "parameter", "p_R1_returns_true_unit", "n_rep", "mcse"])
        for sc, par, ok in rows:
            w.writerow([sc, par, round(float(ok), 4), n_rep,
                        round(float(np.sqrt(ok * (1 - ok) / n_rep)), 4)])
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
