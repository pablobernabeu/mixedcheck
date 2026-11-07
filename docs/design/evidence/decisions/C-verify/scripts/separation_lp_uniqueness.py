"""C-verify: is a separation verdict read from ONE LP solution solver-independent?

Konis-type LP for a binary outcome y (ytilde = 2y - 1) and model matrix X:
    maximise  sum_i ytilde_i x_i' b   s.t.  ytilde_i x_i' b >= 0,  -1 <= b_j <= 1.
Separation (complete or quasi-complete) iff the optimum is > 0. A common shortcut reports
as 'infinite' every coefficient with b_j != 0 in the returned optimum. If the optimum is
not unique, different solvers (or algorithms) can return different supports.
Solver-independent alternative: for each j solve max b_j and min b_j over the recession
cone {b : ytilde_i x_i' b >= 0, -1 <= b <= 1, and c'b = optimum}; j is 'infinite' iff
either bound is nonzero (computed here as the set of j that CAN be nonzero in some
optimal direction).
Usage: <python with scipy> -I separation_lp_uniqueness.py
"""
import numpy as np
from scipy.optimize import linprog

rng = np.random.default_rng(3)
n = 60
x1 = rng.normal(size=n)
y = (x1 > 0).astype(int)                       # x1 separates y completely
x2 = np.where(np.abs(x1) > 1.0, rng.normal(size=n), 0.0)  # nonzero only far from the boundary
x2 -= 0  # keep as is
# make column 2 orthogonal to ytilde so it does not enter the objective
yt = 2 * y - 1
x2 = x2 - yt * (yt @ x2) / n
X = np.column_stack([np.ones(n), x1, x2])
c = -(X.T @ yt)                                # linprog minimises
A_ub = -(yt[:, None] * X)                      # -(yt x'b) <= 0
b_ub = np.zeros(n)
bounds = [(-1, 1)] * X.shape[1]
res = {}
for m in ["highs-ds", "highs-ipm", "highs"]:
    r = linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method=m)
    res[m] = (round(-r.fun, 6), np.round(r.x, 6).tolist())
    print(m, "optimum", round(-r.fun, 6), "b =", np.round(r.x, 6), "support", np.flatnonzero(np.abs(r.x) > 1e-7).tolist())
opt = -linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs").fun
# per-coefficient bounds over the optimal face
A_eq = (X.T @ yt)[None, :]; b_eq = [opt]
for j in range(X.shape[1]):
    e = np.zeros(X.shape[1]); e[j] = 1
    lo = linprog(e, A_ub=A_ub, b_ub=b_ub, A_eq=A_eq, b_eq=b_eq, bounds=bounds, method="highs").fun
    hi = -linprog(-e, A_ub=A_ub, b_ub=b_ub, A_eq=A_eq, b_eq=b_eq, bounds=bounds, method="highs").fun
    print(f"b_{j}: range over optimal face [{lo:.4f}, {hi:.4f}]")
