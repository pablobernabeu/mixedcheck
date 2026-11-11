"""The checks of the prefix identifiability
(spec/registry/checks/identifiability.*.yaml).

identifiability.gram_rank forms the Gram matrix of the covariance parameters
in blocks, the elements of W = Z'PZ between a few levels of one random term
and the columns of the terms after it at a time, so that it never holds W
whole, and gives each value that it compares with rank_tolerance the bound on
its rounding error that the parameter defines.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from mixedcheck._checks import (
    CheckElement,
    Run,
    TermValues,
    Unavailable,
    check_element,
    check_unavailable,
    compared_values,
    factor_has_intercept,
    factor_levels,
    levels_of_full_rank,
    pair_codes,
    parameter_value,
    random_term_values,
    row_patterns,
    within_level_rank,
)
from mixedcheck._design import sequential_rule

if TYPE_CHECKING:
    import numpy

    Array = numpy.ndarray[Any, Any]

# The unit roundoff of doubles, 2^-52 as rank_tolerance writes it.
EPSILON = 2.0**-52

# The number of elements of a block of W in gram_of_bases() above which the
# levels of a random term are split into chunks, 32 MB of doubles.
GRAM_CHUNK_ELEMENTS = 2**22


def check_identifiability_gram_rank(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None] | Unavailable:
    """identifiability.gram_rank: the rank of the Gram matrix of the bases of
    the covariance parameters, projected by the fixed effects for the class
    gaussian and unprojected on the latent scale otherwise, the parameters that
    vanish and those that the eigenvectors of the vanishing eigenvalues
    confound. Each value that the entry compares with rank_tolerance carries a
    bound on its rounding error, and the finding is near_threshold when the
    value lies within its bound of the tolerance."""
    import numpy as np
    from scipy import linalg

    if run.z.shape[1] > parameter_value(entry, "max_z_columns"):
        return check_unavailable("too_large", "max_z_columns")
    if not run.ir["random"]:
        return [None]
    bases = covariance_bases(run)
    if len(bases.names) > parameter_value(entry, "max_parameters"):
        return check_unavailable("too_large", "max_parameters")
    tolerance = parameter_value(entry, "rank_tolerance")
    null_loading = parameter_value(entry, "null_loading")
    gaussian = run.family_class == "gaussian"
    scaled = scaled_random_columns(run)
    q: Array | None = None
    eta = 0.0
    if gaussian:
        kept = run.x[:, np.flatnonzero(run.x_kept)]
        if kept.shape[1]:
            # Scaling the columns leaves their span, and so P, unchanged.
            kept = np.asfortranarray(kept / np.max(np.abs(kept), axis=0))
            q, r, pivot = linalg.qr(kept, mode="economic", pivoting=True, check_finite=False)
            eta = projector_error(kept, q, r, pivot)
    zq = None if q is None else np.asarray(scaled.z.T @ q)
    n = scaled.z.shape[0]
    p = 0 if q is None else q.shape[1]
    found = gram_of_bases(scaled, zq, bases, level_margins(scaled, q), eta)
    gram = found.gram
    bound = found.bound
    names = list(bases.names)
    largest = found.largest
    diagonal = np.diag(gram)
    # A covariance parameter vanishes when its largest level ratio, or its
    # cancellation ratio, is at or below the tolerance, or when no level holds
    # a part of its unprojected basis.
    with np.errstate(divide="ignore", invalid="ignore"):
        cancellation = diagonal / found.level_sums
    held = ~np.isnan(largest)
    vanishing = ~held | (largest <= tolerance) | (diagonal <= tolerance * found.level_sums)
    # The cancellation ratio decides only for a parameter whose largest level
    # ratio exceeds the tolerance.
    decides = held & (largest > tolerance)
    values = [largest[held], cancellation[decides]]
    bounds = [found.largest_bound[held], cancellation_bound(gram, bound, found)[decides]]
    if gaussian:
        residual = residual_gram(run, bases, scaled, q, zq, found, eta)
        gram = np.block(
            [[gram, residual.cross[:, None]], [residual.cross[None, :], np.array([[residual.own]])]]
        )
        bound = np.block(
            [
                [bound, residual.cross_bound[:, None]],
                [residual.cross_bound[None, :], np.array([[residual.own_bound]])],
            ]
        )
        names.append("residual")
        # PDP is 0 exactly when P is, since D has a positive diagonal.
        vanishing = np.append(vanishing, n == p)
    total = len(names)
    others = np.flatnonzero(~vanishing)
    eigenvalues = np.zeros(0)
    confounded: list[str] = []
    if len(others):
        scale = np.sqrt(np.diag(gram)[others])
        scaled_gram = gram[np.ix_(others, others)] / np.outer(scale, scale)
        w, v = np.linalg.eigh(scaled_gram)
        # In decreasing order, as R's eigen() returns them.
        eigenvalues = w[::-1]
        vectors = v[:, ::-1]
        null = eigenvalues <= tolerance
        if bool(null.any()):
            loadings = np.sqrt(np.sum(vectors[:, null] ** 2, axis=1))
            limit = null_loading * loadings.max()
            confounded = [
                names[k] for k, load in zip(others, loadings, strict=True) if load >= limit
            ]
        values.append(eigenvalues)
        error = eigenvalue_bound(
            gram[np.ix_(others, others)], bound[np.ix_(others, others)], scaled_gram, eigenvalues
        )
        bounds.append(np.full(len(eigenvalues), error))
    rank = total - int(vanishing.sum()) - int((eigenvalues <= tolerance).sum())
    if rank < total:
        verdict = "not_identified"
    elif gaussian:
        verdict = "identified"
    else:
        verdict = "necessary_condition_met"
    statistics: dict[str, Any] = {
        "parameters": total,
        "rank": rank,
        "verdict": verdict,
        "vanishing_parameters": [name for name, gone in zip(names, vanishing, strict=True) if gone],
        "confounded_parameters": confounded,
    }
    if len(eigenvalues):
        statistics["smallest_eigenvalue"] = float(np.min(eigenvalues))
    compared = compared_values(np.concatenate(values), np.concatenate(bounds))
    return [
        check_element(
            statistics,
            rules=[verdict == "not_identified", verdict == "necessary_condition_met"],
            proximity={"rank_tolerance": compared},
        )
    ]


def projector_error(kept: Array, q: Array, r: Array, pivot: Array) -> float:
    """A bound eta on ||QQ' - Pi||_2 for the computed basis Q of the scaled
    kept columns X and the projector Pi onto the span of X (rank_tolerance):
    the departure of Q from orthonormality, ||Q'Q - I||_F with each element of
    Q'Q summed pairwise over the rows, plus p (ceiling(log2(n)) + 1) e for the
    rounding of those sums, plus, by Wedin's theorem, the residual ||X - QR||_F
    of the decomposition, with X in the order of the columns of R, plus
    (p + 2)(1 + sqrt(p)) e ||X||_F for its computation and the rounding of the
    scaling of X, divided by the smallest singular value of R."""
    import numpy as np

    n, p = kept.shape
    departure = np.zeros((p, p))
    # Columns of products at a time, at most about GRAM_CHUNK_ELEMENTS
    # elements.
    step = max(1, GRAM_CHUNK_ELEMENTS // max(n, 1))
    for i in range(p):
        for start in range(0, i + 1, step):
            stop = min(i + 1, start + step)
            sums = pairwise_sums(q[:, start:stop] * q[:, i : i + 1])
            sums[np.arange(start, stop) == i] -= 1.0
            departure[i, start:stop] = sums
            departure[start:stop, i] = sums
    residual = kept[:, pivot] - q @ r
    smallest = float(np.min(np.linalg.svd(r, compute_uv=False)))
    return float(
        math.sqrt(float(np.sum(departure**2)))
        + p * (math.ceil(math.log2(n)) + 1) * EPSILON
        + (
            math.sqrt(float(np.sum(residual**2)))
            + (p + 2) * (1 + math.sqrt(p)) * EPSILON * math.sqrt(float(np.sum(kept**2)))
        )
        / smallest
    )


def pairwise_sums(values: Array) -> Array:
    """The sums of the columns of a matrix by pairwise summation over its rows:
    the sums of its rows in pairs, then of those sums in pairs, until one
    remains, so that each element passes through at most
    ceiling(log2(rows)) additions."""
    import numpy as np

    while values.shape[0] > 1:
        if values.shape[0] % 2:
            values = np.vstack((values, np.zeros((1, values.shape[1]))))
        values = values[0::2] + values[1::2]
    if values.shape[0] == 0:
        return np.zeros(values.shape[1])
    return np.array(values[0], dtype=np.float64)


def level_margins(scaled: ScaledColumns, q: Array | None) -> list[Array]:
    """For each random term, the bound alpha_L for each level L on its share of
    the rounding error of an element of W between a column in L and a column
    in any level L', which lies within (alpha_L + alpha_L') times the root of
    the product of the sums of the squares of the two columns, apart from the
    error of the basis Q (rank_tolerance): alpha_L =
    e (n_L (1 + 2 sqrt(h_L h)) + (p + 2) h_L + 3) / 2, for n_L the rows of L,
    h_L the sum of the squares of the rows of Q in L, 0 without Q, and h the
    largest h_L over the levels of every random term."""
    import numpy as np

    n = scaled.z.shape[0]
    p = 0 if q is None else q.shape[1]
    leverage = np.zeros(n) if q is None else np.einsum("ij,ij->i", q, q)
    shares = [
        (
            np.bincount(term.level, minlength=term.count).astype(np.float64),
            np.bincount(term.level, weights=leverage, minlength=term.count),
        )
        for term in scaled.terms
    ]
    largest = max([0.0] + [float(np.max(h, initial=0.0)) for _, h in shares])
    return [
        EPSILON * (rows * (1 + 2 * np.sqrt(h * largest)) + (p + 2) * h + 3) / 2
        for rows, h in shares
    ]


def cancellation_bound(gram: Array, bound: Array, found: GramOfBases) -> Array:
    """The bound on the rounding error of the cancellation ratio M_kk / T_k of
    each covariance parameter, from the bound B_kk on M_kk and the bound V_k on
    the sum T_k of its elements in the levels, infinite when V_k reaches T_k."""
    import numpy as np

    sums = found.level_sums
    margin = found.level_sums_bound
    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = np.abs(np.diag(gram) / sums)
        out = (np.diag(bound) + ratio * margin) / (sums - margin)
    out[~(sums > margin)] = math.inf
    bounds: Array = out
    return bounds


def eigenvalue_bound(gram: Array, bound: Array, scaled_gram: Array, eigenvalues: Array) -> float:
    """The bound on the rounding error of every eigenvalue of C, by Weyl's
    inequality: the Frobenius norm of the bounds E_kl on its elements off the
    diagonal, where C_kl lies within
    (|M_kl| + B_kl) / sqrt((M_kk - B_kk)(M_ll - B_ll)) - |C_kl| of its computed
    value, plus 2^-52 times the largest eigenvalue for the solver, or Inf when
    some B_kk reaches M_kk."""
    import numpy as np

    lower = np.diag(gram) - np.diag(bound)
    if not bool((lower > 0).all()):
        return math.inf
    e = (np.abs(gram) + bound) / np.sqrt(np.outer(lower, lower)) - np.abs(scaled_gram)
    np.fill_diagonal(e, 0.0)
    return float(math.sqrt(float(np.sum(e**2))) + EPSILON * float(np.abs(eigenvalues).max()))


@dataclass
class ScaledColumns:
    """Z with each column of a random term, in every level, divided by the
    largest absolute value of that column over the design sample (z), for each
    random term the positions in Z of each of its columns in level order
    (positions), and the scaled values of its columns in each row with the
    level of the row (terms)."""

    z: Any
    positions: list[list[Array]]
    terms: list[TermValues]


def scaled_random_columns(run: Run) -> ScaledColumns:
    """Z with each column of a random term, in every level, divided by the
    largest absolute value of that column over the design sample, or left as it
    is when the column is 0 in every row, so that no product of its values
    overflows or underflows. The bases of a term's parameters cover all its
    levels alike, so the scaling multiplies the Gram matrix on both sides by a
    positive diagonal matrix, which leaves C and the vanishing ratios
    unchanged."""
    import numpy as np

    z = run.z
    divisor = np.ones(z.shape[1])
    term_of = run.z_columns["term"].to_numpy()
    positions: list[list[Array]] = []
    terms: list[TermValues] = []
    for t, term in enumerate(run.ir["random"]):
        columns = np.flatnonzero(term_of == t)
        q = len(term["columns"])
        found = random_term_values(run, t)
        largest = np.abs(found.values).max(axis=0, initial=0.0)
        largest[largest == 0] = 1.0
        divisor[columns] = np.tile(largest, len(columns) // q)
        positions.append([columns[c::q] for c in range(q)])
        terms.append(TermValues(found.values / largest, found.level, found.count))
    scaled = z.copy()
    scaled.data = z.data / divisor[np.repeat(np.arange(z.shape[1]), np.diff(z.indptr))]
    return ScaledColumns(scaled, positions, terms)


@dataclass
class Block:
    """A block of the basis of a covariance parameter: the pair of columns x
    and y of a random term, by their positions in Z in level order (x and y)
    and their positions in the term (column_x and column_y), from 0, standing
    for the sum over the levels L of e(x_L) e(y_L)'."""

    x: Array
    y: Array
    term: int
    column_x: int
    column_y: int


@dataclass
class CovarianceBases:
    """The covariance parameters of the random terms in IR order, named as the
    IR names them, each with its basis as blocks."""

    names: list[str]
    blocks: list[list[Block]]


def covariance_bases(run: Run) -> CovarianceBases:
    """The covariance parameters of the random terms in IR order (ir.md,
    Covariance parameters), each named as the IR names it and with its basis
    as blocks. A variance has the block (x, x) and a covariance the blocks
    (x, y) and (y, x)."""
    import numpy as np

    term_of = run.z_columns["term"].to_numpy()
    names: list[str] = []
    blocks: list[list[Block]] = []
    for t, term in enumerate(run.ir["random"]):
        q = len(term["columns"])
        positions = np.flatnonzero(term_of == t)
        columns = [positions[c::q] for c in range(q)]
        labels = [column["name"] for column in term["columns"]]
        for j in range(q):
            names.append(f"{term['name']}: var({labels[j]})")
            blocks.append([Block(columns[j], columns[j], t, j, j)])
            for k in range(j + 1, q):
                names.append(f"{term['name']}: cov({labels[j]}, {labels[k]})")
                blocks.append(
                    [Block(columns[j], columns[k], t, j, k), Block(columns[k], columns[j], t, k, j)]
                )
    return CovarianceBases(names, blocks)


@dataclass
class GramOfBases:
    """The Gram matrix of the covariance parameters with the values derived
    from its blocks that identifiability.gram_rank compares and bounds
    (:func:`gram_of_bases`)."""

    gram: Array
    largest: Array
    level_sums: Array
    traces: list[Array]
    bound: Array
    largest_bound: Array
    level_sums_bound: Array
    level_norms: list[Array]
    norms: Array
    offsets: list[int]
    margins: list[Array]


def gram_of_bases(
    scaled: ScaledColumns,
    zq: Array | None,
    bases: CovarianceBases,
    margins: list[Array] | None = None,
    eta: float = 0.0,
    chunk: int = GRAM_CHUNK_ELEMENTS,
) -> GramOfBases:
    """The Gram matrix M_kl = tr(A_k W A_l W) of the covariance parameters,
    with W = Z'Z - (Z'Q)(Z'Q)' for zq = Z'Q, or W = Z'Z without zq, for Z
    scaled as :func:`scaled_random_columns` scales it, for each parameter the
    largest ratio of the element tr(A_kL W A_kL W) of its basis in a level L to
    the same element of its unprojected basis, over the levels where the latter
    is not 0 (largest, NaN without such a level), and the sum of the former
    over the levels (level_sums), and, for each random term, the trace of each
    block of W between two of its columns (traces).

    For blocks (x, y) of A_k and (u, v) of A_l, the trace adds the sum over
    the levels L and L' of W[y_L, u_L'] W[v_L', x_L], the sum of the elements
    of W[y, u] times those of W[x, v]. For each random term t and each chunk of
    its levels, one sparse product forms the rows of W at the chunk's columns
    of t and the columns of t and of every term after it. For each such term
    s, the blocks between a column of t and a column of s are then the columns
    of a matrix V, so that the sum of V'V over the chunks holds every such sum,
    and for two terms with one column each this sum is the sum of the squares
    of the block, computed for all such terms s at once. V'V is summed over
    groups of rows of at most J + J' products, for the numbers of levels J of
    t and J' of s, the groups and then the chunks are summed in turn, and the
    sums of squares are summed over the rows of a chunk and then over the
    levels of s, so that each product passes through at most 2 (J + J')
    additions. W is never held whole, and the time grows with the number of
    rows times the square of the number of random terms. The blocks of Z'Z
    within a term are diagonal, since each row lies in one level.

    With the margins alpha_L of :func:`level_margins` and eta of
    :func:`projector_error`, which bound the rounding error of the elements of
    W (identifiability.gram_rank.yaml, rank_tolerance), it also returns the
    bounds on the rounding errors of the elements of M (bound), of each largest
    level ratio (largest_bound) and of each sum of the elements in the levels
    (level_sums_bound), and the sums of the squares of the columns of the
    terms in each level (level_norms) and over all levels (norms).
    """
    import numpy as np

    positions = scaled.positions
    terms = scaled.terms
    count = len(positions)
    z = scaled.z
    # The columns of Z of each term in level order and, within a level, in the
    # order of the term's columns, with the term and the column of each.
    widths = np.array([len(p) for p in positions], dtype=np.int64)
    columns = [np.column_stack(p).reshape(-1) for p in positions]
    owner = np.repeat(np.arange(count), [len(c) for c in columns])
    within = np.concatenate([np.tile(np.arange(widths[t]), terms[t].count) for t in range(count)])
    all_columns = np.concatenate(columns)
    sums: list[list[Array | None]] = [
        [
            np.zeros((widths[t] * widths[s], widths[t] * widths[s])) if s >= t else None
            for s in range(count)
        ]
        for t in range(count)
    ]
    traces: list[Array] = []
    diagonals: list[list[Array]] = []
    projected: list[list[Array]] = []
    for t in range(count):
        qt = int(widths[t])
        jt = terms[t].count
        values = terms[t].values
        level = terms[t].level
        # The diagonal of each block of Z'Z and of W within the term, an
        # element for each level, and the trace of the block of W.
        trace = np.zeros((qt, qt))
        diagonal_t: list[Array] = []
        projected_t: list[Array] = []
        for d in range(qt):
            for c in range(qt):
                product = np.bincount(level, weights=values[:, c] * values[:, d], minlength=jt)
                diagonal_t.append(product)
                if zq is not None:
                    product = product - np.einsum(
                        "ij,ij->i", zq[positions[t][c], :], zq[positions[t][d], :]
                    )
                projected_t.append(product)
                trace[c, d] = float(np.sum(product))
        traces.append(trace)
        diagonals.append(diagonal_t)
        projected.append(projected_t)
        later = np.flatnonzero(owner >= t)
        later_owner = owner[later]
        single_mask = widths[later_owner] == 1
        single = later_owner[single_mask]
        single_columns = np.flatnonzero(single_mask)
        several = list(dict.fromkeys(later_owner[(widths[later_owner] > 1) | (qt > 1)].tolist()))
        z_later = z[:, all_columns[later]]
        zq_later = None if zq is None else zq[all_columns[later], :]
        # The levels of t in chunks, so that the rows of W for a chunk hold at
        # most about chunk elements, or one level.
        per_chunk = max(1, chunk // (qt * len(later)))
        for start in range(0, jt, per_chunk):
            part = np.arange(start, min(start + per_chunk, jt))
            size = len(part)
            rows = np.concatenate([positions[t][c][part] for c in range(qt)])
            b = (z[:, rows].T @ z_later).toarray()
            if zq is not None and zq_later is not None:
                b -= zq[rows, :] @ zq_later.T
            if qt == 1 and len(single):
                block = b[:, single_columns]
                squares = np.einsum("ij,ij->j", block, block)
                by_term = np.bincount(single, weights=squares, minlength=count)
                for s in np.unique(single).tolist():
                    found_s = sums[t][s]
                    assert found_s is not None
                    found_s += by_term[s]
            for s in several:
                qs = int(widths[s])
                js = terms[s].count
                of_s = np.flatnonzero(later_owner == s)
                of_column = [of_s[within[later[of_s]] == d] for d in range(qs)]
                # The rows of V hold the levels of the chunk for each level of
                # s in turn, formed and summed in groups of the rows of g
                # levels of s, at most jt + js rows each.
                g = max(1, (jt + js) // size)
                groups = -(-js // g)
                width = qt * qs
                v = np.zeros((size, groups * g, width))
                for d in range(qs):
                    for c in range(qt):
                        v[:, :js, d * qt + c] = b[c * size : (c + 1) * size, of_column[d]]
                grouped = (
                    v.reshape(size, groups, g, width)
                    .transpose(1, 2, 0, 3)
                    .reshape(groups, g * size, width)
                )
                summed = np.zeros((width, width))
                for rows_of_group in grouped:
                    summed += rows_of_group.T @ rows_of_group
                found_s = sums[t][s]
                assert found_s is not None
                found_s += summed
            del b
    # The elements of the Gram matrix between every two blocks of the bases,
    # each the sum of the elements of W[y, u] times those of W[x, v] for
    # blocks a = (x, y) and b = (u, v), from the matrix of the two terms in
    # ascending order, with both blocks transposed when the term of a comes
    # after that of b. M_kl sums them over the blocks a of A_k and b of A_l in
    # turn, and is formed for k >= l and mirrored.
    all_blocks = [a for blocks in bases.blocks for a in blocks]
    parameters = len(bases.blocks)
    block_owner = np.repeat(np.arange(parameters), [len(blocks) for blocks in bases.blocks])
    block_term = np.array([a.term for a in all_blocks], dtype=np.int64)
    block_x = np.array([a.column_x for a in all_blocks], dtype=np.int64)
    block_y = np.array([a.column_y for a in all_blocks], dtype=np.int64)
    elements = np.zeros((len(all_blocks), len(all_blocks)))
    for t in range(count):
        of_t = np.flatnonzero(block_term == t)
        q = int(widths[t])
        for s in range(t, count):
            of_s = np.flatnonzero(block_term == s)
            matrix = sums[t][s]
            assert matrix is not None
            elements[np.ix_(of_t, of_s)] = matrix[
                block_x[of_s][None, :] * q + block_y[of_t][:, None],
                block_y[of_s][None, :] * q + block_x[of_t][:, None],
            ]
            if s > t:
                elements[np.ix_(of_s, of_t)] = matrix[
                    block_y[of_s][:, None] * q + block_x[of_t][None, :],
                    block_x[of_s][:, None] * q + block_y[of_t][None, :],
                ]

    def by_parameters(values: Array) -> Array:
        """The sums of a matrix over the blocks of each pair of parameters."""
        cells = (block_owner[:, None] * parameters + block_owner[None, :]).reshape(-1)
        summed = np.bincount(cells, weights=values.reshape(-1), minlength=parameters**2)
        return summed.reshape(parameters, parameters)

    lower = np.tril(by_parameters(elements))
    gram = lower + np.tril(lower, -1).T
    # The columns of all terms in one index, the sum of the squares of each
    # (norms) and the root sum of squares of the elements of W between every
    # two of them (frobenius), whose square the diagonal of the sum of V'V
    # holds.
    offsets = [0] + np.cumsum(widths).tolist()
    norms = np.concatenate([np.sum(term.values**2, axis=0) for term in terms])
    frobenius = np.zeros((offsets[count], offsets[count]))
    for t in range(count):
        for s in range(t, count):
            matrix = sums[t][s]
            assert matrix is not None
            block = np.sqrt(np.maximum(np.diag(matrix), 0)).reshape(widths[s], widths[t]).T
            frobenius[offsets[t] : offsets[t + 1], offsets[s] : offsets[s + 1]] = block
            frobenius[offsets[s] : offsets[s + 1], offsets[t] : offsets[t + 1]] = block.T
    # The sums of the squares of the columns of the terms in each level, and,
    # for each column c of all terms, A_c = sqrt(sum over the levels L of
    # alpha_L^2 s_cL), with s_cL its sum of squares in L.
    level_norms = [
        np.column_stack([diagonals[t][c * widths[t] + c] for c in range(widths[t])])
        for t in range(count)
    ]
    if margins is None:
        margins = [np.zeros(term.count) for term in terms]
    spreads = np.concatenate(
        [np.sqrt(np.sum(margins[t][:, None] ** 2 * level_norms[t], axis=0)) for t in range(count)]
    )
    # For the blocks a = (x, y) of A_k and b = (u, v) of A_l, the computed
    # products of W[y, u] and W[x, v], summed over the levels, differ from the
    # exact ones by at most
    # (A_y sqrt(s_u) + sqrt(s_y) A_u) G[x, v] + G[y, u] (A_x sqrt(s_v) + sqrt(s_x) A_v)
    # by the Cauchy-Schwarz inequality, for the sums of squares s of the
    # columns and G the norm of a block of W raised by the bound on the norm
    # of its error, which bounds the exact norm, and summing the products adds
    # at most 2^-51 (J + J' + 2) times the sum of their absolute values. The
    # error of the projector adds 2 eta sqrt(X_k X_l) to the whole of M_kl,
    # for X_k = tr(A_k W A_k Z'Z), the square of the norm of PZA_kZ', which
    # the sum of mu^2 over the levels below bounds.
    bx = np.array([offsets[a.term] + a.column_x for a in all_blocks], dtype=np.int64)
    by = np.array([offsets[a.term] + a.column_y for a in all_blocks], dtype=np.int64)
    block_levels = np.array([terms[a.term].count for a in all_blocks], dtype=np.float64)
    root = np.sqrt(norms)
    error_norm = np.outer(spreads, root) + np.outer(root, spreads)
    raised = frobenius + error_norm + eta * np.outer(root, root)
    f_yu = frobenius[np.ix_(by, bx)]
    f_xv = frobenius[np.ix_(bx, by)]
    pair = (
        error_norm[np.ix_(by, bx)] * raised[np.ix_(bx, by)]
        + raised[np.ix_(by, bx)] * error_norm[np.ix_(bx, by)]
        + 2.0**-51 * np.add.outer(block_levels, block_levels) * f_yu * f_xv
        + 2.0**-50 * f_yu * f_xv
    )
    bound = by_parameters(pair)
    bound = (bound + bound.T) / 2
    # For each parameter, the element tr(A_kL W A_kL W) of its basis in each
    # level L, from the diagonals of the blocks of W, and the same element of
    # its unprojected basis, from those of Z'Z: the sum over its blocks a and
    # b of the products of the diagonals of the blocks (a.y, b.x) and
    # (a.x, b.y), level by level. The former lies within 3 delta_L mu^2 of its
    # computed value, for delta_L = 2 alpha_L + eta, which bounds the error of
    # an element of W within L relative to the root of the product of the sums
    # of squares of its columns, and mu the sum over the blocks (x, y) of
    # sqrt(omega_x s_y), where s_c is the sum of the squares of column c in the
    # level and omega_c the computed diagonal element of W, or 0 when it is
    # negative, plus delta_L s_c, which bounds the exact one.

    def level_element(blocks: list[Block], diagonal: list[Array]) -> Array:
        q = int(widths[blocks[0].term])
        total: Any = 0.0
        for a in blocks:
            for b_ in blocks:
                total = total + (
                    diagonal[b_.column_x * q + a.column_y] * diagonal[b_.column_y * q + a.column_x]
                )
        return np.asarray(total, dtype=np.float64)

    largest = np.full(parameters, math.nan)
    largest_bound = np.full(parameters, math.nan)
    level_sums = np.zeros(parameters)
    level_sums_bound = np.zeros(parameters)
    whole = np.zeros(parameters)
    for k in range(parameters):
        blocks = bases.blocks[k]
        t = blocks[0].term
        q = int(widths[t])
        delta = 2 * margins[t] + eta
        part = level_element(blocks, projected[t])
        unprojected = level_element(blocks, diagonals[t])
        mu: Any = 0.0
        for a in blocks:
            own = diagonals[t][a.column_x * q + a.column_x]
            omega = np.maximum(projected[t][a.column_x * q + a.column_x], 0) + delta * own
            mu = mu + np.sqrt(omega * diagonals[t][a.column_y * q + a.column_y])
        level_sums[k] = float(np.sum(part))
        whole[k] = float(np.sum(mu**2))
        level_sums_bound[k] = 3 * float(np.sum(delta * mu**2)) + EPSILON * len(part) * float(
            np.sum(np.abs(part))
        )
        held = unprojected > 0
        if bool(held.any()):
            ratios = part[held] / unprojected[held]
            largest[k] = float(np.max(ratios))
            largest_bound[k] = float(
                np.max(delta[held] * (3 * mu[held] ** 2 / unprojected[held] + np.abs(ratios)))
            )
    bound = bound + 2 * eta * np.sqrt(np.outer(whole, whole))
    return GramOfBases(
        gram=gram,
        largest=largest,
        level_sums=level_sums,
        traces=traces,
        bound=bound,
        largest_bound=largest_bound,
        level_sums_bound=level_sums_bound,
        level_norms=level_norms,
        norms=norms,
        offsets=offsets,
        margins=margins,
    )


@dataclass
class ResidualGram:
    """The elements of the Gram matrix that involve the residual, with the
    bounds on their rounding errors."""

    cross: Array
    own: float
    cross_bound: Array
    own_bound: float


def residual_gram(
    run: Run,
    bases: CovarianceBases,
    scaled: ScaledColumns,
    q: Array | None,
    zq: Array | None,
    found: GramOfBases,
    eta: float,
) -> ResidualGram:
    """The elements of the Gram matrix that involve the residual for the class
    gaussian, tr(A_k Z'PDPZ) for each parameter k (cross) and tr(PDPD) (own),
    with the bounds on their rounding errors (cross_bound and own_bound), for D
    the identity or diag(m/w) for weights w with the smallest weight m, which
    is diag(1/w) divided by its largest element, and P = I - QQ' for an
    orthonormal basis Q of the kept fixed-effects columns, from Z scaled as
    :func:`scaled_random_columns` scales it, and eta the bound on the error of
    QQ' of :func:`projector_error`."""
    import numpy as np

    n = scaled.z.shape[0]
    k = 0 if q is None else q.shape[1]
    norms = found.norms
    offsets = found.offsets
    # The sum over the blocks (x, y) of a parameter of sqrt(s_x s_y), for the
    # sums of squares s of the columns of its term over the design sample.
    spread = np.array(
        [
            sum(
                math.sqrt(
                    float(norms[offsets[a.term] + a.column_x])
                    * float(norms[offsets[a.term] + a.column_y])
                )
                for a in blocks
            )
            for blocks in bases.blocks
        ]
    )
    if run.weights is None:
        # tr(A_k Z'PZ) sums the diagonals of the blocks of W over the levels,
        # each within 2 alpha_L sqrt(s_xL s_yL), the error of the projector
        # adds eta times the sum over the blocks of sqrt(s_x s_y), and
        # tr(PP) = n - k exactly.
        cross = np.array(
            [
                sum(float(found.traces[a.term][a.column_y, a.column_x]) for a in blocks)
                for blocks in bases.blocks
            ]
        )
        within = np.array(
            [
                sum(
                    float(
                        np.sum(
                            2
                            * found.margins[a.term]
                            * np.sqrt(
                                found.level_norms[a.term][:, a.column_x]
                                * found.level_norms[a.term][:, a.column_y]
                            )
                        )
                    )
                    for a in blocks
                )
                for blocks in bases.blocks
            ]
        )
        counts = np.array([scaled.terms[blocks[0].term].count for blocks in bases.blocks])
        return ResidualGram(
            cross=cross,
            own=float(n - k),
            cross_bound=within + (eta + EPSILON * counts) * spread,
            own_bound=0.0,
        )
    # With weights, the sums over all rows lie within n (1 + k) 2^-52 of their
    # scale and the elements of QQ' within (1 + k) 2^-52, each plus eta.
    epsilon = (1 + k) * EPSILON
    return weighted_residual_gram(
        run, bases, scaled, q, zq, found, n * epsilon + eta, epsilon + eta, spread
    )


def weighted_residual_gram(
    run: Run,
    bases: CovarianceBases,
    scaled: ScaledColumns,
    q: Array | None,
    zq: Array | None,
    found: GramOfBases,
    delta: float,
    epsilon: float,
    spread: Array,
) -> ResidualGram:
    """The elements of the Gram matrix that involve the residual with weights.

    The rows whose leverage H_rr = q_r'q_r exceeds 1/2, of which there are
    fewer than 2k since the leverages sum to k, form A, and the others B.
    Since P_rs = [r = s] - q_r'q_s, tr(PDPD) is the sum of d_r d_s P_rs^2 over
    the pairs of rows, which adds for the rows of A the products of the
    explicit elements P_rs, and for the pairs within B
    sum(d_r^2 (1 - 2 H_rr)) + ||Q_B'D_B Q_B||^2, two sums without negative
    terms. tr(A_k Z'PDPZ) adds over the levels L and the blocks (x, y) the sum
    of d_r (P z_yL)_r (P z_xL)_r, explicit for the rows of A and expanded as
    z_y'D_B z_x - z_y'D_B Q Q'z_x - z_y'Q Q'D_B z_x + z_y'Q Q'D_B Q Q'z_x for
    those of B. A row with a weight far below the others and with a leverage
    near 1, such as a row that a factor of the fixed part isolates, then
    cancels nothing, so that the elements keep their precision for weights
    that differ by many orders of magnitude. delta bounds the relative error
    of a sum over the rows and epsilon that of an element of QQ', each with
    eta, the error of the basis Q.
    """
    import numpy as np

    weights = run.weights
    assert weights is not None
    n = scaled.z.shape[0]
    count = len(bases.blocks)
    d = np.min(weights) / weights
    leverage = np.zeros(n) if q is None else np.einsum("ij,ij->i", q, q)
    a = np.flatnonzero(leverage > 0.5)
    outside = d.copy()
    outside[a] = 0.0
    largest_outside = float(np.max(outside))
    # The pairs within B.
    g = None if q is None else q.T @ (outside[:, None] * q)
    own = float(np.sum(outside**2 * (1 - 2 * leverage))) + (
        0.0 if g is None else float(np.sum(g**2))
    )
    own_bound = delta * own + 2 * epsilon * float(np.sum(outside**2))
    # The rows of A against the rows of B, in chunks of rows, each element
    # P_rs within epsilon of its computed value. Between two rows of A, P_rs is
    # taken as (PP)_rs, the inner product of their rows of P, which lies within
    # epsilon sqrt(n) (sqrt(P_rr) + sqrt(P_ss)) + 2 n epsilon^2 of the exact
    # value, so that a row that P takes to 0 gives an error of order
    # n epsilon^2, where 1 - H_rr carries one of order epsilon.
    if len(a) and q is not None:
        qa = q[a, :]
        da = d[a]
        per_chunk = max(1, GRAM_CHUNK_ELEMENTS // len(a))
        across = 0.0
        margin = 0.0
        square = np.zeros((len(a), len(a)))
        for start in range(0, n, per_chunk):
            stop = min(n, start + per_chunk)
            p_a = -(qa @ q[start:stop, :].T)
            inside = (a >= start) & (a < stop)
            p_a[np.flatnonzero(inside), a[inside] - start] += 1.0
            square += p_a @ p_a.T
            weight = 2 * outside[start:stop]
            across += float(np.sum(da * ((p_a**2) @ weight)))
            margin += float(np.sum(da * ((2 * np.abs(p_a) + epsilon) @ weight)))
        root = np.sqrt(np.abs(np.diag(square)))
        error = epsilon * math.sqrt(n) * np.add.outer(root, root) + 2 * n * epsilon**2
        products = np.outer(da, da)
        within = float(np.sum(products * square**2))
        own = own + across + within
        own_bound = (
            own_bound
            + delta * (across + within)
            + epsilon * margin
            + float(np.sum(products * (2 * np.abs(square) + error) * error))
        )
    zdq = None if q is None else np.asarray(scaled.z.T @ (outside[:, None] * q))
    cross = np.zeros(count)
    cross_bound = 2 * delta * largest_outside * spread
    for p, blocks in enumerate(bases.blocks):
        for block in blocks:
            t = block.term
            y = block.y
            x = block.x
            values = scaled.terms[t].values
            total = float(np.sum(outside * values[:, block.column_y] * values[:, block.column_x]))
            if q is not None and zq is not None and zdq is not None and g is not None:
                total = (
                    total
                    - float(np.sum(zdq[y, :] * zq[x, :]))
                    - float(np.sum(zq[y, :] * zdq[x, :]))
                    + float(np.sum((zq[y, :] @ g) * zq[x, :]))
                )
            if len(a) and q is not None and zq is not None:
                # (P z_cL)_r for the rows r of A and every level L, each within
                # 2 delta sqrt(s_cL) of its computed value.
                level = scaled.terms[t].level[a]
                qa = q[a, :]
                da = d[a]

                def residuals(c: int, positions: Array) -> Array:
                    r = -(qa @ zq[positions, :].T)  # noqa: B023
                    r[np.arange(len(a)), level] += values[a, c]  # noqa: B023
                    return r

                r_y = residuals(block.column_y, y)
                r_x = residuals(block.column_x, x)
                g_y = 2 * delta * np.sqrt(found.level_norms[t][:, block.column_y])
                g_x = 2 * delta * np.sqrt(found.level_norms[t][:, block.column_x])
                products = np.sum(r_y * r_x, axis=1)
                total += float(np.sum(da * products))
                cross_bound[p] += float(
                    np.sum(
                        da
                        * (
                            (np.abs(r_y) + g_y[None, :]) @ g_x
                            + np.abs(r_x) @ g_y
                            + delta * np.sum(np.abs(r_y * r_x), axis=1)
                        )
                    )
                )
            cross[p] += total
    return ResidualGram(cross=cross, own=own, cross_bound=cross_bound, own_bound=own_bound)


def check_identifiability_df_budget(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """identifiability.df_budget: the degrees of freedom between the levels of
    a grouping factor that remain after the fixed effects, J - k + r for the k
    kept fixed-effects columns X and the within-level rank r of X
    (:func:`within_level_rank`). A combination of the columns of X lies in the
    span of the indicators exactly when it is constant within levels, which the
    within-level rank tests without the J indicator columns, and the rank of
    the columns of the terms up to each term gives the budget after it."""
    import numpy as np

    ir = run.ir
    column_terms = np.array([column["term"] for column in ir["fixed"]["columns"]], dtype=np.int64)
    kept = np.flatnonzero(run.x_kept)
    term_of = column_terms[kept]
    names = [term["name"] for term in ir["fixed"]["terms"]]
    found: list[CheckElement | None] = []
    for element in elements:
        if not factor_has_intercept(run, element["factor"]):
            found.append(None)
            continue
        levels = factor_levels(run, element["factor"])
        j = levels.count
        within = np.array(within_level_rank(run.x[:, kept], levels.code, j), dtype=bool)
        budgets = [
            j - int((term_of <= t).sum()) + int(within[term_of <= t].sum())
            for t in range(len(names))
        ]
        consuming = [
            name for t, name in enumerate(names) if budgets[t] < (j if t == 0 else budgets[t - 1])
        ]
        budget = budgets[-1] if budgets else j
        found.append(
            check_element(
                {"levels": j, "budget": budget, "consuming_terms": consuming},
                rules=[budget == 0],
            )
        )
    return found


def check_identifiability_levels_vs_dimension(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """identifiability.levels_vs_dimension: the levels of a random term's factor
    against the number of its columns, and the levels in which its columns
    have full rank."""
    import numpy as np

    found: list[CheckElement | None] = []
    p = run.x.shape[1]
    for t in range(len(elements)):
        values = random_term_values(run, t)
        q = values.values.shape[1]
        j = values.count
        informative = int(levels_of_full_rank(values.values, values.level, j).sum())
        kept = sequential_rule(np.asfortranarray(np.hstack((run.x, values.values))))
        counterparts = not any(kept[p:])
        bound = j - 1 if counterparts else j
        statistics = {
            "dimension": q,
            "levels": j,
            "informative_levels": informative,
            "counterparts": counterparts,
            "bound": bound,
        }
        found.append(check_element(statistics, rules=[bound < q, informative <= q]))
    return found


def check_identifiability_residual_confounding(
    run: Run, entry: dict[str, Any], elements: list[dict[str, str]]
) -> list[CheckElement | None]:
    """identifiability.residual_confounding: the combinations of a level of a
    random term's factor and a pattern of the columns of its pattern terms, and
    those that hold two or more rows."""
    import numpy as np

    random = run.ir["random"]
    predictors = run.ir["predictors"]
    family = run.family_class
    found: list[CheckElement | None] = []
    for t in range(len(elements)):
        term = random[t]
        q = len(term["columns"])
        correlated = q >= 2
        if correlated:
            pattern = [t]
        else:
            pattern = [
                s
                for s, other in enumerate(random)
                if other["factor"] == term["factor"] and len(other["columns"]) == 1
            ]
        coded = all(
            predictors.get(v["variable"], {}).get("kind") == "categorical"
            for s in pattern
            for each in random[s]["terms"]
            for v in each["variables"]
        )
        if not coded:
            found.append(None)
            continue
        values = np.hstack([random_term_values(run, s).values for s in pattern])
        patterns = row_patterns(values)
        levels = factor_levels(run, term["factor"])
        cell = pair_codes(levels.code, patterns)
        sizes = np.bincount(cell)
        column = term["terms"][term["columns"][0]["term"]]
        intercept_alone = q == 1 and not column["variables"] and pattern == [t]
        replicated = int((sizes >= 2).sum())
        codes = np.full(run.table.rows, -1, dtype=np.int64)
        codes[run.design] = patterns
        statistics = {
            "columns": q,
            "correlated": correlated,
            "pattern_terms": [random[s]["name"] for s in pattern],
            "cells": len(sizes),
            "replicated_cells": replicated,
            "intercept_alone": intercept_alone,
        }
        none = replicated == 0
        latent = family in ("gaussian", "other")
        found.append(
            check_element(
                statistics,
                rules=[
                    none and latent and (correlated or intercept_alone),
                    none and family == "bernoulli",
                    none and latent,
                    none,
                ],
                items={"pattern_terms": codes},
            )
        )
    return found
