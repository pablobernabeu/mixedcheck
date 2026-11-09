"""The design and analysis samples, the design matrices X and Z, the response,
offset and weight vectors and the sequential rule for aliased columns
(docs/spec/ir.md, Samples, Design matrices and Sequential rule).

Every value of X and Z is computed element by element in double arithmetic,
in the order that ir.md fixes, with numpy's elementwise operations, which
round each operation once as IEEE 754 requires. No sum or product of a
column passes through BLAS or a pandas reduction.
"""

from __future__ import annotations

import math
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, TypeAlias

from mixedcheck._declaration import version_supported
from mixedcheck._errors import MixedcheckError, display_text, finish_issues, raise_issue
from mixedcheck._formula_ir import ModelTable, design_rows, level_label, model_table
from mixedcheck._json_read import parse_json_bytes
from mixedcheck._json_write import canonical_bytes
from mixedcheck._numbers import format_number
from mixedcheck._schema import schema_issues
from mixedcheck._unicode import comparison_form, sort_identifiers

if TYPE_CHECKING:
    import numpy
    import pandas

    Array: TypeAlias = numpy.ndarray[Any, Any]

_IR_VERSION = re.compile(r"0\.1\.(0|[1-9][0-9]*)")


def design_matrices(ir: Mapping[str, Any], data: pandas.DataFrame) -> dict[str, Any]:
    """Build the design matrices of an IR.

    Builds, for the data, the design and analysis samples of an IR that
    :func:`formula_ir` returned and the matrices and vectors of the model: the
    fixed-effects matrix X, with the columns that the sequential rule drops
    named separately, the random-effects matrix Z and the response, trials,
    offset and weight vectors.

    The design sample holds the rows in which no column that the IR reads is
    missing, other than the response and the trials column, and no sample
    column of the IR is missing. The analysis sample holds the rows of the
    design sample in which the response is present and, with a trials column,
    the trials are present and either above 0 or not finite.
    :func:`design_samples` gives the two samples alone. X and Z have one row
    for each row of the design sample, in the order of the data. X has the
    fixed-part columns of the IR, computed in double arithmetic in the order
    the IR specification fixes, and the sequential rule drops each column
    whose values are all 0 or whose residual after projection onto the
    columns kept before it is at most 1e-7 times its norm, once the column is
    divided by its largest absolute value. Z has, for each random term in IR order, one
    column for each level of its grouping factor in the design sample and
    each column of the term, the columns of one level together, with one
    stored entry for each row and column of the term, zero or not.

    Args:
        ir: An IR, as :func:`formula_ir` returns it with the data. Its version
            and structure are checked, and a mean centring rule must hold its
            constant.
        data: A pandas DataFrame with the columns that the IR reads, under the
            rules of :func:`formula_ir`.

    Returns:
        A dict with these members:

        - ``design_sample`` and ``analysis_sample``: the positions of the rows
          of ``data`` in each sample, as for ``DataFrame.iloc``, in numpy
          int64 arrays counted from 0. The R package counts them from 1.
        - ``x``: a two-dimensional numpy float64 array in column-major order,
          as R stores a matrix, with one row for each row of the design
          sample and one column for each column of the fixed part.
        - ``x_columns``: the names of the columns of ``x``, in order, as the
          IR names them.
        - ``x_dropped``: the names of the columns of ``x`` that the sequential
          rule drops, in column order.
        - ``z``: a ``scipy.sparse.csc_array`` with one row for each row of the
          design sample and the columns described by ``z_columns``.
        - ``z_columns``: a pandas DataFrame with one row for each column of
          ``z`` and the columns ``term``, the position of its random term in
          ``ir["random"]``, counted from 0 (from 1 in R), ``level``, the label
          of its level, which for several grouping variables joins their
          labels by ':', with each backslash and ':' in a label preceded by a
          backslash, and ``column``, the name of the column of the random
          term.
        - ``response`` and ``trials``: numpy float64 arrays with one value for
          each row of the analysis sample, or ``None``. The response is the
          response itself, its natural logarithm for the transform 'log', 1
          and 0 for True and False, or, with a declared event level, 1 where
          the value equals the event level and 0 otherwise. A response of
          strings without an event level has no response vector.
        - ``offset`` and ``weights``: numpy float64 arrays with one value for
          each row of the design sample, or ``None`` when the IR has no
          offsets or weights. The offset is the sum of the offsets in IR
          order, with the natural logarithm for the transform 'log'.

    Raises:
        MixedcheckError: A problem with one issue: E6073 for NaN or an infinity
            in a numeric column that the IR reads in a row of the design
            sample, other than the response and the trials column, checked
            by column in code-point order, then E6077 for the first column of
            X and then of Z with a value that is not finite, such as a
            product beyond the largest double, E6071 for the logarithm of a
            value that is not positive in an offset, in IR order, E6072 for a
            weight that is not positive, E6073 for NaN or an infinity in the
            response and then the trials column in a row of the analysis
            sample and E6071 for a response written with log(). An IR that is
            not valid gives the codes of the schema area.
        TypeError: An argument of the wrong type.
        ValueError: Data that do not hold the columns or levels of the IR.

    Examples:
        >>> import pandas as pd
        >>> data = pd.DataFrame(
        ...     {
        ...         "y": [1.5, 2.25, 3, 2.5, 4, 3.5],
        ...         "cond": ["A", "B", "A", "B", "A", "B"],
        ...         "subject": ["s1", "s1", "s2", "s2", "s3", "s3"],
        ...     }
        ... )
        >>> ir = formula_ir("y ~ cond + (1 + cond | subject)", data=data)
        >>> matrices = design_matrices(ir, data)
        >>> matrices["x"].tolist()
        [[1.0, 0.0], [1.0, 1.0], [1.0, 0.0], [1.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
        >>> matrices["z_columns"]["level"].tolist()
        ['s1', 's1', 's2', 's2', 's3', 's3']
        >>> matrices["z"].toarray()[1].tolist()
        [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]
    """
    import numpy as np
    import pandas as pd

    if not isinstance(data, pd.DataFrame):
        raise TypeError("'data' must be a pandas DataFrame.")
    value = ir_input(ir)
    table = model_table(data, [])
    model = design_model(value, table)
    design = model.design
    analysis = model.analysis
    # E6073 in the design sample, by column in code-point order.
    checked = list(
        dict.fromkeys(
            [key for key, p in model.predictors.items() if p["kind"] == "numeric"]
            + [
                key
                for term in model.random
                for key in term["grouping"]
                if table.types[model.column(key)] == "number"
            ]
            + [o["variable"] for o in model.offsets]
            + ([model.weights] if model.weights is not None else [])
        )
    )
    for key in sort_identifiers(checked):
        if not bool(np.isfinite(table.values[model.column(key)][design]).all()):
            raise_issue("E6073", {"column": key})
    values = design_variable_values(model, table, design)
    columns = value["fixed"]["columns"]
    # Column-major, as in R, so that each column is contiguous when it is
    # written and when the sequential rule reads it.
    x = np.empty((len(design), len(columns)), dtype=np.float64, order="F")
    fixed_names = [column["name"] for column in columns]
    # E6077 for the first column of X, then of Z, with a value that is not
    # finite. Each column is checked before it is written into X.
    for k, column in enumerate(columns):
        computed = design_column_values(value["fixed"]["terms"], column, values, len(design))
        if not bool(np.isfinite(computed).all()):
            raise_issue("E6077", {"column": fixed_names[k]})
        x[:, k] = computed
    z, z_columns = design_z(model, table, design, values)
    kept = sequential_rule(x)
    offset = None
    for o in model.offsets:
        v = table.values[model.column(o["variable"])][design]
        if o["transform"] == "log":
            if bool((v <= 0).any()):
                raise_issue("E6071", {"column": o["variable"]})
            v = platform_log(v)
        offset = v.copy() if offset is None else offset + v
    weights = None
    if model.weights is not None:
        weights = table.values[model.column(model.weights)][design].copy()
        if bool((weights <= 0).any()):
            raise_issue("E6072", {"column": model.weights})
    response, trials = design_response(value, model, table, analysis)
    return {
        "design_sample": design,
        "analysis_sample": analysis,
        "x": x,
        "x_columns": fixed_names,
        "x_dropped": [name for name, keep in zip(fixed_names, kept, strict=True) if not keep],
        "z": z,
        "z_columns": z_columns,
        "response": response,
        "trials": trials,
        "offset": offset,
        "weights": weights,
    }


def design_samples(ir: Mapping[str, Any], data: pandas.DataFrame) -> dict[str, Any]:
    """The design and analysis samples of an IR.

    Determines, for the data, the design and analysis samples of an IR that
    :func:`formula_ir` returned, without building the design matrices. The
    samples are determined before X, Z and the vectors, so this function
    reports them even when :func:`design_matrices` would raise E6071, E6072,
    E6073 or E6077 for the values of the rows.

    The design sample holds the rows in which no column that the IR reads is
    missing, other than the response and the trials column, and no sample
    column of the IR is missing. The analysis sample holds the rows of the
    design sample in which the response is present and, with a trials column,
    the trials are present and either above 0 or not finite.

    Args:
        ir: An IR, as :func:`formula_ir` returns it with the data. Its version
            and structure are checked, and a mean centring rule must hold its
            constant.
        data: A pandas DataFrame with the columns that the IR reads, under the
            rules of :func:`formula_ir`.

    Returns:
        A dict with the members ``design_sample`` and ``analysis_sample``: the
        positions of the rows of ``data`` in each sample, as for
        ``DataFrame.iloc``, in numpy int64 arrays counted from 0. The R
        package counts them from 1.

    Raises:
        MixedcheckError: An IR that is not valid, with the codes of the schema
            area.
        TypeError: An argument of the wrong type.
        ValueError: Data that do not hold the columns or levels of the IR.

    Examples:
        >>> import pandas as pd
        >>> data = pd.DataFrame({"y": [1.5, None, 3, 2.5], "x": [1, 2, None, 4]}, dtype=object)
        >>> ir = formula_ir("y ~ x", data=data)
        >>> samples = design_samples(ir, data)
        >>> samples["design_sample"].tolist(), samples["analysis_sample"].tolist()
        ([0, 1, 3], [0, 3])
    """
    import pandas as pd

    if not isinstance(data, pd.DataFrame):
        raise TypeError("'data' must be a pandas DataFrame.")
    model = design_model(ir_input(ir), model_table(data, []))
    return {"design_sample": model.design, "analysis_sample": model.analysis}


def ir_input(ir: Any) -> dict[str, Any]:
    """An IR passed in: written and read again in the hashable profile, so that
    it holds the values that the strict reader returns, then checked for its
    version (E1441) and against ir.schema.json. A mean centring rule without
    its constant cannot be applied."""
    value = parse_json_bytes(canonical_bytes(ir, "hashable"), "hashable")
    version = value.get("ir_version") if isinstance(value, dict) else None
    if isinstance(version, str) and not version_supported(version, _IR_VERSION):
        raise_issue("E1441", {"version": version, "supported": "0.1.x"}, pointer="/ir_version")
    raw = schema_issues(value, "urn:mixedcheck:schema:ir")
    if raw:
        raise MixedcheckError(finish_issues(raw))
    assert isinstance(value, dict)
    for name, predictor in value["predictors"].items():
        centring = predictor.get("centring", {})
        if centring.get("rule") == "mean" and "constant" not in centring:
            raise ValueError(
                f"The centring of '{display_text(name)}' has no constant. Build the IR with "
                "formula_ir() and the data first."
            )
    return value


@dataclass
class DesignModel:
    """What the matrices need from an IR and the data: the column of each key,
    the predictors, the random terms, the offsets, the weights and the samples."""

    column: Callable[[str], int]
    predictors: dict[str, Any]
    random: list[dict[str, Any]]
    offsets: list[dict[str, Any]]
    weights: str | None
    design: Array
    analysis: Array


def design_model(ir: dict[str, Any], table: ModelTable) -> DesignModel:
    """The columns, samples and parts of an IR for the data."""
    import numpy as np

    def column(key: str) -> int:
        j = table.index(key)
        if j is None:
            raise ValueError(
                f"The column '{display_text(key)}' that the IR reads is not in 'data'."
            )
        return j

    predictors: dict[str, Any] = ir["predictors"]
    for key, p in predictors.items():
        j = column(key)
        if p["kind"] == "numeric":
            wanted = "number"
        else:
            first = p["levels"][0]
            wanted = (
                "string"
                if isinstance(first, str)
                else "boolean"
                if isinstance(first, bool)
                else "number"
            )
        if table.types[j] != wanted and not bool(table.missing[j].all()):
            raise ValueError(
                f"The column '{display_text(key)}' of 'data' does not hold the {wanted} values "
                "that the IR reads."
            )
    random: list[dict[str, Any]] = ir["random"]
    offsets: list[dict[str, Any]] = ir["offsets"]
    weights = ir["weights"]["variable"] if "weights" in ir else None
    sample_columns = list(ir.get("sample_columns", []))
    read = list(
        dict.fromkeys(
            list(predictors)
            + [key for term in random for key in term["grouping"]]
            + [o["variable"] for o in offsets]
            + ([weights] if weights is not None else [])
            + sample_columns
        )
    )
    response = ir.get("response")
    extra = []
    if response is not None:
        extra.append(response["variable"])
        if "trials" in response:
            extra.append(response["trials"])
    for key in read + extra:
        column(key)
    numbers = [o["variable"] for o in offsets] + ([weights] if weights is not None else [])
    if response is not None and "trials" in response:
        numbers.append(response["trials"])
    for key in numbers:
        if table.types[column(key)] != "number":
            raise ValueError(f"The column '{display_text(key)}' of 'data' does not hold numbers.")
    design = design_rows(table, read)
    analysis = design
    if response is not None:
        j = column(response["variable"])
        analysis = analysis[~table.missing[j][analysis]]
        if "trials" in response:
            t = column(response["trials"])
            trials = table.values[t][analysis]
            with np.errstate(invalid="ignore"):
                kept = ~(np.isfinite(trials) & (trials <= 0))
            analysis = analysis[~table.missing[t][analysis] & kept]
    return DesignModel(
        column, predictors, random, offsets, weights, design, analysis.astype(np.int64)
    )


@dataclass
class _Values:
    """The values of each predictor in the rows of a sample: a numeric
    predictor centred by its rule and, for a categorical predictor, the
    position of each row's level among its levels, from 0."""

    values: dict[str, Array]
    predictors: dict[str, Any]


def design_variable_values(model: DesignModel, table: ModelTable, rows: Array) -> _Values:
    """The values of each predictor in the rows of a sample. A value outside
    the levels is refused."""
    import numpy as np

    out: dict[str, Array] = {}
    for key, p in model.predictors.items():
        v = table.values[model.column(key)][rows]
        if p["kind"] == "numeric":
            if p["centring"]["rule"] != "none":
                # The double nearest to the decimal constant, which float()
                # rounds correctly. A value beyond the largest double gives
                # E6077 once the columns are built.
                with np.errstate(over="ignore", invalid="ignore"):
                    v = v - float(p["centring"]["constant"]["value"])
            out[key] = v
            continue
        positions = _level_positions(v, p["levels"])
        if positions is None:
            raise ValueError(
                f"The column '{display_text(key)}' of 'data' holds a value that is not one of "
                "its levels in the IR."
            )
        out[key] = positions
    return _Values(out, model.predictors)


def _level_positions(values: Array, levels: list[Any]) -> Array | None:
    """The position of each value among the levels, from 0, comparing strings
    after NFC and numbers by value, or None when a value is not a level."""
    import numpy as np

    first = levels[0]
    lookup: dict[Any, int]
    if isinstance(first, str):
        lookup = {level: i for i, level in enumerate(levels)}
        distinct = {value: lookup.get(comparison_form(value), -1) for value in set(values.tolist())}
    elif isinstance(first, bool):
        lookup = {bool(level): i for i, level in enumerate(levels)}
        distinct = {value: lookup.get(bool(value), -1) for value in set(values.tolist())}
    else:
        lookup = {float(level): i for i, level in enumerate(levels)}
        distinct = {value: lookup.get(float(value), -1) for value in set(values.tolist())}
    positions = np.fromiter(
        (distinct[value] for value in values.tolist()), dtype=np.int64, count=len(values)
    )
    if bool((positions < 0).any()):
        return None
    return positions


def _level_index(levels: list[Any], level: Any) -> int:
    """The position of a level of the IR among the levels of its predictor."""
    for i, candidate in enumerate(levels):
        if isinstance(candidate, bool) or isinstance(level, bool):
            if isinstance(candidate, bool) and isinstance(level, bool) and candidate is level:
                return i
        elif candidate == level:
            return i
    raise ValueError(
        f"The level '{display_text(level_label(level))}' is not one of the levels in the IR."
    )


def design_column_values(
    terms: list[dict[str, Any]], column: dict[str, Any], values: _Values, rows: int
) -> Array:
    """The values of one column of a part (ir.md, X): 1 for '(Intercept)', and
    otherwise the product of the values of the term's variables, multiplied
    from the left in double arithmetic."""
    import numpy as np

    term = terms[column["term"]]
    if not term["variables"]:
        return np.ones(rows, dtype=np.float64)
    result: Array | None = None
    for variable in term["variables"]:
        key = variable["variable"]
        v = values.values[key]
        if "coding" in variable:
            v = level_values(v, variable["coding"], column["levels"][key], values.predictors[key])
        if result is None:
            result = v
        else:
            with np.errstate(over="ignore", invalid="ignore"):
                result = result * v
    assert result is not None
    return result


def level_values(position: Array, coding: str, level: Any, predictor: dict[str, Any]) -> Array:
    """The values that a categorical variable takes in the column of one level,
    for rows whose levels are at the positions given: its contrast (ir.md,
    Contrasts) or its indicator."""
    import numpy as np

    levels = predictor["levels"]
    target = _level_index(levels, level)
    hit: Array = position == target
    if coding == "indicator" or predictor["contrast"] == "treatment":
        return hit.astype(np.float64)
    reference = _level_index(levels, predictor["reference"])
    k = len(levels)
    if predictor["contrast"] == "sum":
        return np.where(hit, 1.0, np.where(position == reference, -1.0, 0.0))
    # Simple contrasts: (k - 1)/k and 1/k are quotients of two integers,
    # rounded once, and -1/k is the negation of 1/k.
    inverse = 1 / k
    return np.where(hit, (k - 1) / k, -inverse)


def design_z(
    model: DesignModel, table: ModelTable, rows: Array, values: _Values
) -> tuple[Any, pandas.DataFrame]:
    """Z (ir.md, Z): for each random term in IR order, J x q columns, ordered
    by level and, within a level, by the term's columns. Returns the matrix
    and the description of its columns."""
    import numpy as np
    import pandas as pd
    from scipy import sparse

    n = len(rows)
    row_parts: list[Array] = []
    column_parts: list[Array] = []
    value_parts: list[Array] = []
    terms: list[int] = []
    levels: list[str] = []
    names: list[str] = []
    start = 0
    for t, term in enumerate(model.random):
        codes, labels = grouping_levels(table, term["grouping"], rows, model.column)
        q = len(term["columns"])
        for c, column in enumerate(term["columns"]):
            v = design_column_values(term["terms"], column, values, n)
            if not bool(np.isfinite(v).all()):
                raise_issue("E6077", {"column": column["name"]})
            row_parts.append(np.arange(n, dtype=np.int64))
            column_parts.append(start + codes * q + c)
            value_parts.append(v)
        column_names = [column["name"] for column in term["columns"]]
        for label in labels:
            for name in column_names:
                terms.append(t)
                levels.append(label)
                names.append(name)
        start += len(labels) * q
    if row_parts:
        data = np.concatenate(value_parts)
        indices = (np.concatenate(row_parts), np.concatenate(column_parts))
    else:
        data = np.zeros(0, dtype=np.float64)
        indices = (np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.int64))
    z = sparse.coo_array((data, indices), shape=(n, start)).tocsc()
    described = pd.DataFrame(
        {
            "term": pd.Series(terms, dtype=np.int64),
            "level": pd.Series(levels, dtype=object),
            "column": pd.Series(names, dtype=object),
        }
    )
    return z, described


def grouping_levels(
    table: ModelTable, keys: list[str], rows: Array, column: Callable[[str], int]
) -> tuple[Array, list[str]]:
    """The levels of a grouping factor in the rows of a sample (ir.md, Z): the
    distinct combinations of the values of its variables, ordered by the first
    variable, then the second, numbers by value, strings by code point after
    NFC and false before true. Returns the position of each row's level among
    the levels, from 0, and the label of each level: the label of its one
    variable, or the labels of its variables joined by ':', each with a
    backslash and ':' escaped by a backslash."""
    import numpy as np

    n = len(rows)
    ranks: list[Array] = []
    texts: list[list[str]] = []
    for key in keys:
        j = column(key)
        v = table.values[j][rows]
        kind = table.types[j]
        if kind == "string":
            forms = {value: comparison_form(value) for value in set(v.tolist())}
            distinct: list[Any] = sort_identifiers(set(forms.values()))
            position = {form: i for i, form in enumerate(distinct)}
            rank = np.fromiter(
                (position[forms[value]] for value in v.tolist()), dtype=np.int64, count=n
            )
            text = list(distinct)
        elif kind == "boolean":
            present = set(v.tolist())
            distinct = [flag for flag in (False, True) if flag in present]
            rank = np.searchsorted(np.array(distinct, dtype=bool), v).astype(np.int64)
            text = ["true" if flag else "false" for flag in distinct]
        else:
            # Adding 0 turns negative zero into zero.
            numbers = v + 0.0
            unique = np.unique(numbers)
            rank = np.searchsorted(unique, numbers).astype(np.int64)
            text = [format_number(float(number)) for number in unique]
        if len(keys) > 1:
            text = [label.replace("\\", "\\\\").replace(":", "\\:") for label in text]
        ranks.append(rank)
        texts.append(text)
    if n == 0:
        return np.zeros(0, dtype=np.int64), []
    unique_rows, codes = np.unique(np.column_stack(ranks), axis=0, return_inverse=True)
    labels = [
        ":".join(texts[v][int(rank)] for v, rank in enumerate(level)) for level in unique_rows
    ]
    return codes.reshape(-1).astype(np.int64), labels


def design_response(
    ir: dict[str, Any], model: DesignModel, table: ModelTable, analysis: Array
) -> tuple[Array | None, Array | None]:
    """The response and trials vectors of the analysis sample (ir.md, Response,
    offsets and weights)."""
    import numpy as np

    response = ir.get("response")
    if response is None:
        return None, None
    j = model.column(response["variable"])
    kind = table.types[j]
    v = table.values[j][analysis]
    trials = None
    if kind == "number" and not bool(np.isfinite(v).all()):
        raise_issue("E6073", {"column": response["variable"]})
    if "trials" in response:
        trials = table.values[model.column(response["trials"])][analysis].copy()
        if not bool(np.isfinite(trials).all()):
            raise_issue("E6073", {"column": response["trials"]})
    if "event_level" in response:
        event = response["event_level"]
        if isinstance(event, str):
            if kind == "string":
                form = comparison_form(event)
                hit = np.fromiter(
                    (comparison_form(value) == form for value in v.tolist()),
                    dtype=bool,
                    count=len(v),
                )
            else:
                hit = np.zeros(len(v), dtype=bool)
        else:
            hit = v == float(event) if kind == "number" else np.zeros(len(v), dtype=bool)
        return hit.astype(np.float64), trials
    if kind == "boolean":
        return v.astype(np.float64), trials
    if kind == "string":
        return None, trials
    if response["transform"] == "log":
        if bool((v <= 0).any()):
            raise_issue("E6071", {"column": response["variable"]})
        return platform_log(v), trials
    return v.copy(), trials


def platform_log(values: Array) -> Array:
    """The natural logarithm of each value with the platform's log(), as R
    computes it, rather than numpy's own implementation (ir.md, Response,
    offsets and weights)."""
    import numpy as np

    return np.fromiter((math.log(v) for v in values.tolist()), dtype=np.float64, count=len(values))


# --- The sequential rule ----------------------------------------------------------


def sequential_rule(x: Array, tolerance: float = 1e-7) -> list[bool]:
    """The sequential rule for aliased columns (ir.md, Sequential rule).

    Each column in turn is dropped when its values are all 0. Otherwise it is
    divided by its largest absolute value, so that its squares neither
    overflow nor underflow, and dropped when the norm of its residual after
    orthogonal projection onto the columns kept so far is at most
    ``tolerance`` times its norm. The steps are those of sequential_rule() in
    the R package, one by one:

    1. The largest absolute value of each column is found, and each column
       that is not all 0 is divided by it, which gives the scaled columns V.
    2. When there are more than twice as many rows as columns in V, V is
       replaced by Q'V, its coordinates in the orthonormal factor Q of the
       Householder QR with column pivoting of LAPACK's DGEQP3, which
       ``scipy.linalg.qr(pivoting=True)`` calls as R's
       ``qr(LAPACK = TRUE)`` does: the triangular factor R, with its columns
       put back in the order of V. Q'V keeps every norm and inner product up
       to an error near the rounding error of the column, and the next step
       then works on as many rows as there are columns.
    3. Each column of V in turn is projected out of an orthonormal basis of
       the columns kept so far with two passes of Gram-Schmidt, and when its
       residual is kept, the residual divided by its norm joins the basis.
       Norms and inner products are computed with ``numpy.dot()`` and ``@``,
       which call BLAS, as ``crossprod()`` and ``%*%`` do in R.

    The two packages call the same LAPACK routine and BLAS operations on the
    same values, so that they differ only in the rounding of their BLAS and
    LAPACK. Returns whether each column is kept.
    """
    import numpy as np
    from scipy import linalg

    n, p = x.shape
    kept = [False] * p
    if n == 0 or p == 0:
        return kept
    # The largest of the largest value and the negated smallest value is the
    # largest absolute value, found without a copy of X.
    largest = np.maximum(x.max(axis=0), -x.min(axis=0))
    candidates = np.flatnonzero(largest > 0)
    m = len(candidates)
    if m == 0:
        return kept
    v = np.empty((n, m), dtype=np.float64, order="F")
    for k, j in enumerate(candidates.tolist()):
        np.divide(x[:, j], largest[j], out=v[:, k])
    if n > 2 * m:
        # mode='raw' returns the same m x m factor R from the same call to
        # DGEQP3 as mode='r', without the n x m array of the triangle padded
        # with zeros that mode='r' returns. V is column-major, so that DGEQP3
        # overwrites it in place.
        _, r_factor, pivot = linalg.qr(
            v, overwrite_a=True, mode="raw", pivoting=True, check_finite=False
        )
        v = np.asfortranarray(r_factor[:, np.argsort(pivot)])
    basis = np.empty((v.shape[0], m), dtype=np.float64, order="F")
    k = 0
    for j in range(m):
        r = v[:, j]
        norm_v = math.sqrt(float(np.dot(r, r)))
        if k:
            # The kept columns are one contiguous block of the column-major
            # basis, used without a copy.
            q = basis[:, :k]
            for _ in range(2):
                r = r - q @ (q.T @ r)
        norm_r = math.sqrt(float(np.dot(r, r)))
        if norm_r > tolerance * norm_v:
            kept[int(candidates[j])] = True
            basis[:, k] = r / norm_r
            k += 1
    return kept
