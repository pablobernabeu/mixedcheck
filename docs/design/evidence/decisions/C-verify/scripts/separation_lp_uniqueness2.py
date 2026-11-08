"""C-verify: degenerate separation LP (see separation_lp_uniqueness.py for the formulation).
x1 separates y completely; x2 is nonzero only in two class-1 rows far from the boundary,
with opposite signs, so its objective coefficient is 0 and b_2 can move within a range
on the optimal face. Different algorithms may report different supports.
"""
import numpy as np
from scipy.optimize import linprog
x1 = np.array([-3, -2, -1.5, -1, -0.5, 0.5, 1, 1.5, 2, 3.0])
y = (x1 > 0).astype(int); yt = 2 * y - 1
x2 = np.zeros_like(x1); x2[[8, 9]] = [1.0, -1.0]     # two class-1 rows with large margins
X = np.column_stack([np.ones_like(x1), x1, x2])
c = -(X.T @ yt); A_ub = -(yt[:, None] * X); b_ub = np.zeros(len(y)); bounds = [(-1, 1)] * 3
print("objective coefficients:", -c)
for m in ["highs-ds", "highs-ipm"]:
    for opts in [None, {"presolve": False}]:
        r = linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method=m, options=opts)
        print(m, opts, "optimum", round(-r.fun, 6), "b =", np.round(r.x, 6), "support", np.flatnonzero(np.abs(r.x) > 1e-9).tolist())
opt = -linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs").fun
A_eq = (X.T @ yt)[None, :]
for j in range(3):
    e = np.zeros(3); e[j] = 1
    lo = linprog(e, A_ub=A_ub, b_ub=b_ub, A_eq=A_eq, b_eq=[opt], bounds=bounds, method="highs").fun
    hi = -linprog(-e, A_ub=A_ub, b_ub=b_ub, A_eq=A_eq, b_eq=[opt], bounds=bounds, method="highs").fun
    print(f"b_{j}: range over the optimal face [{lo:.4f}, {hi:.4f}]")
