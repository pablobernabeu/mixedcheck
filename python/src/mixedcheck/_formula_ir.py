"""The builder of the canonical IR (docs/spec/ir.md): expansion of the parsed
formula into terms, the kinds and levels of columns, the coding argument,
contrasts or indicators in each term, the columns and names of each part, the
centring constants and the IR document. It reports the first issue that its
stages find, in the order of ir.md (Errors).
"""

from __future__ import annotations

import math
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, cast

from mixedcheck._declaration import list_item_value, validate_declaration
from mixedcheck._errors import display_text, format_integer, raise_issue
from mixedcheck._formula_parse import (
    Call,
    Chain,
    Formula,
    Found,
    Name,
    Node,
    Number,
    Paren,
    Power,
    Summand,
    call_name_node,
    first_issue,
    formula_names,
    formula_parse,
    formula_tokens,
    is_random,
    structure_issue,
    variable_text,
)
from mixedcheck._json_write import _numpy_scalar, json_pointer
from mixedcheck._numbers import MAX_INTEGER, decimal_string
from mixedcheck._schema import is_column_name, is_decimal_string, significant_digit_count
from mixedcheck._unicode import comparison_form, has_surrogate, is_normalisable, sort_identifiers

if TYPE_CHECKING:
    import numpy
    import pandas

_CODING_MEMBERS = ("centring", "contrast", "frozen", "reference", "significant_digits", "value")
_CATEGORICAL_MEMBERS = frozenset(("contrast", "frozen", "reference"))
# The most terms that a list of terms may hold, and the most columns of a part
# and characters of a name (ir.md, Operators and Names).
FORMULA_LIMIT = 10000
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def formula_ir(
    formula: str,
    declaration: Any = None,
    data: pandas.DataFrame | None = None,
    coding: Mapping[str, Mapping[str, Any]] | None = None,
    weights: str | None = None,
    sample_columns: Sequence[str] | None = None,
) -> dict[str, Any]:
    """Build the canonical IR of a model.

    Parses an lme4-style formula with the in-house parser of mixedcheck and
    builds the canonical intermediate representation (IR) of the model, which
    both packages compute identically: the response, the coding of every
    predictor, the terms and columns of the fixed part, the random terms with
    their grouping factors and columns, the offsets, the weights and the
    further sample columns. :func:`canonical_hash` of the IR in the hashable
    profile gives its IR hash.

    The formula grammar is that of lme4 with the differences that the IR
    specification of mixedcheck lists. Terms are expanded and ordered as R
    orders them. Levels come from the declared categories or from all rows of
    the data, in code-point order after NFC normalisation, never from a
    sample, and the first level is the reference unless the coding argument
    names another. Each categorical variable is coded by its contrast or by
    indicators in each term, as in R, unless the coding argument freezes it.

    Args:
        formula: The formula, as a str of at most 10,000 characters, such as
            ``"rt ~ cond + (1 + cond | subject)"``.
        declaration: ``None``, the path of a declaration file in JSON or YAML,
            or a declaration in memory as a dict, as
            :func:`validate_declaration` accepts it. The declaration is
            validated first. The builder reads its table block, for the types
            and categories of columns, and the ``variables`` entry of the
            response, for its event level, trials and exposure. It also reads
            the units, roles and ``disclosure_unit``, for the columns that
            identify persons, which cannot be predictors.
        data: ``None``, or a pandas DataFrame, such as :func:`read_table`
            returns. Its columns hold numbers (int or float), strings or
            booleans: columns of dtype object, as :func:`read_table` returns
            them, numpy numeric and bool columns, pandas' nullable numeric,
            boolean and string columns, or a pandas categorical whose
            categories are strings. A categorical is read by its labels, as R
            reads a factor, and the order of its categories is ignored. Only
            ``None`` and ``pandas.NA`` are missing, and so is the NaN by which
            pandas' string dtype marks a missing string. NaN and the
            infinities in a float column are numbers, so a float column has no
            missing values. Strings such as '' or 'NA' that a declaration lists
            as missing values must be ``None``, as :func:`read_table` returns
            them. A column of dtype object whose values are all missing takes
            its type from the table block, then from ``attrs["types"]``, as
            :func:`read_table` sets it, and otherwise is a boolean column, as a
            logical column of ``NA`` is in R. Column names are compared after
            NFC normalisation and must differ after it. A column that the
            table block declares must hold values of its type, unless all its
            values are missing. Without data, the columns are the fields of
            the table block.
        coding: ``None``, or a dict with one entry for each predictor whose
            coding departs from the defaults, keyed by column name. An entry is
            a dict with any of the members ``contrast`` ('treatment', 'sum' or
            'simple'), ``reference`` (a level, as a str, an int or a bool) and
            ``frozen`` (True or False) for a categorical predictor and
            ``centring`` ('none', 'mean' or 'value'), ``significant_digits``
            (1 to 15, with 'mean', by default 6) and ``value`` (a decimal
            string, with 'value') for a numeric one.
        weights: ``None``, or the name of a column of precision weights.
        sample_columns: ``None``, or a list of the names of further columns
            whose missing values remove rows from the design sample. Columns
            that the IR reads already, such as the response, are left out.

    Returns:
        The IR as a dict in the form that :func:`read_json_strict` returns:
        objects as dicts, arrays as lists, strings as str, term indices,
        significant digits and integer levels as int and booleans as bool.
        Its members are ``ir_version``, ``response`` (absent for a one-sided
        formula), ``predictors``, ``fixed``, ``random``, ``offsets``,
        ``weights`` (when named) and ``sample_columns`` (when any remain), as
        the IR specification describes. Term indices count from 0 in the IR,
        in both packages.

    Raises:
        MixedcheckError: A problem with the formula or its context, whose
            ``issues`` hold one issue of the formula area: a dict with the
            ``code`` of the shared error catalogue, the rendered ``message``
            and, when the code has a location, the byte ``offset`` into the
            UTF-8 encoding of the formula, counted from 0. A declaration that
            is not valid gives the error of :func:`validate_declaration`, and
            a string with a surrogate code point gives E1206 at its JSON
            Pointer, such as /formula or /data/<column>/<row>.
        TypeError: An argument of the wrong type.
        ValueError: Data whose columns cannot be read.

    Examples:
        >>> declaration = {
        ...     "vocabulary": "0.1.0",
        ...     "table": {
        ...         "fields": [
        ...             {"name": "rt", "type": "number"},
        ...             {"name": "cond", "type": "string", "categories": ["A", "B"]},
        ...             {"name": "subject", "type": "string"},
        ...         ]
        ...     },
        ... }
        >>> ir = formula_ir(
        ...     "rt ~ cond + (1 + cond | subject)",
        ...     declaration,
        ...     coding={"cond": {"contrast": "simple"}},
        ... )
        >>> canonical_hash(ir, "hashable")
        'sha256:ae50b9fcbcdb4f4e6f1757d4cf3954a56c0864e4483bbddca58ff966c1d0322c'
        >>> [column["name"] for column in ir["fixed"]["columns"]]
        ['(Intercept)', 'cond[B]']
        >>> import pandas as pd
        >>> data = pd.DataFrame(
        ...     {"y": [1.5, 2.25, 3, 2.5], "x": [1, 2, 3, 4], "g": ["a", "a", "b", "b"]}
        ... )
        >>> ir = formula_ir("y ~ x + (1 | g)", data=data, coding={"x": {"centring": "mean"}})
        >>> ir["predictors"]["x"]["centring"]
        {'rule': 'mean', 'sample': 'design', 'constant': {'significant_digits': 6, 'value': '2.5'}}
        >>> # A function that the grammar does not support.
        >>> try:
        ...     formula_ir("y ~ log(x)", data=data)
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["code"], err.issues[0]["offset"])
        E6020 4
    """
    if not isinstance(formula, str):
        raise TypeError("'formula' must be a str.")
    import pandas as pd

    if data is not None and not isinstance(data, pd.DataFrame):
        raise TypeError("'data' must be None or a pandas DataFrame.")
    if weights is not None and not isinstance(weights, str):
        raise TypeError("'weights' must be None or a column name.")
    if sample_columns is not None and (
        isinstance(sample_columns, str)
        or not isinstance(sample_columns, Sequence)
        or not all(isinstance(name, str) for name in sample_columns)
    ):
        raise TypeError("'sample_columns' must be None or a list of column names.")
    _check_coding_argument(coding)
    if declaration is not None:
        declaration = validate_declaration(declaration)
    input_string(formula, ["formula"])
    if weights is not None:
        input_string(weights, ["weights"])
    names = list(sample_columns or [])
    for i, name in enumerate(names):
        input_string(name, ["sample_columns", str(i)])
    coding_value = coding_input(coding)
    fields = _table_fields(declaration)
    table = model_table(data, fields) if data is not None else None
    return build_formula_ir(formula, declaration, table, coding_value, weights, names)


# --- Inputs ---------------------------------------------------------------------


def input_string(text: str, path: list[str]) -> str:
    """The input boundary for a str that the caller passes in: a string with a
    surrogate code point gives E1206 at its JSON Pointer."""
    if has_surrogate(text):
        raise_issue("E1206", pointer=json_pointer(path))
    return text


def _table_fields(declaration: Any) -> list[dict[str, Any]]:
    """The fields of the declaration's table block, or none."""
    if not isinstance(declaration, dict):
        return []
    table = declaration.get("table")
    return list(table.get("fields", [])) if isinstance(table, dict) else []


def _check_coding_argument(coding: Any) -> None:
    """The coding argument must be None or a dict of dicts with non-empty str keys."""
    if coding is None:
        return
    valid = isinstance(coding, Mapping) and all(
        isinstance(key, str)
        and key != ""
        and isinstance(entry, Mapping)
        and all(isinstance(member, str) and member != "" for member in entry)
        for key, entry in coding.items()
    )
    if not valid:
        raise TypeError("'coding' must be None or a dict of dicts, one for each column.")


@dataclass
class Coding:
    """The coding argument: the comparison forms of its keys, the keys as given
    and the entries, with numpy scalars converted."""

    keys: list[str] = field(default_factory=list)
    names: list[str] = field(default_factory=list)
    entries: list[dict[str, Any]] = field(default_factory=list)

    def entry(self, key: str) -> dict[str, Any]:
        """The entry of a column, by the comparison form of its key."""
        if key in self.keys:
            return self.entries[self.keys.index(key)]
        return {}


def coding_input(coding: Mapping[str, Mapping[str, Any]] | None) -> Coding:
    """The coding argument after the input boundary, keyed by the comparison
    forms of its keys."""
    result = Coding()
    if not coding:
        return result
    names = list(coding)
    for name in names:
        input_string(name, ["coding", name])
    for name in names:
        entry = coding[name]
        for member in entry:
            input_string(member, ["coding", name, member])
        converted: dict[str, Any] = {}
        for member, value in entry.items():
            value = _numpy_scalar(value)
            if isinstance(value, str):
                input_string(value, ["coding", name, member])
            converted[member] = value
        result.entries.append(converted)
    forms = [comparison_form(name) for name in names]
    seen: set[str] = set()
    for name, form in zip(names, forms, strict=True):
        if form in seen:
            raise ValueError(f"'coding' names the column '{display_text(name)}' twice.")
        seen.add(form)
    result.keys = forms
    result.names = names
    return result


@dataclass
class ModelTable:
    """The data in the form the builder reads: the column names, their
    comparison forms and, for each column, its values (a float64 array for
    'number', a bool array for 'boolean' and an object array of str for
    'string'), its type and which values are missing."""

    names: list[str]
    keys: list[str]
    values: list[Any]
    types: list[str]
    missing: list[numpy.ndarray[Any, Any]]
    rows: int

    def index(self, key: str) -> int | None:
        """The position of a column, by the comparison form of its name."""
        try:
            return self.keys.index(key)
        except ValueError:
            return None


def model_table(data: pandas.DataFrame, fields: Sequence[Mapping[str, Any]]) -> ModelTable:
    """The data in the form the builder reads. Only None and pandas.NA are
    missing, and NaN, inf and -inf are numbers. ``fields`` are the fields of
    the declaration's table block, which give the type a column must have."""
    raw_names = list(data.columns)
    for name in raw_names:
        if not isinstance(name, str):
            raise ValueError("The columns of 'data' must have names that are str.")
    names: list[str] = raw_names
    for name in names:
        input_string(name, ["data", name])
    for name in names:
        if not is_column_name(name):
            raise ValueError(
                f"The column name '{display_text(name)}' of 'data' is not a valid column name."
            )
    keys = [comparison_form(name) for name in names]
    seen: set[str] = set()
    for key in keys:
        if key in seen:
            raise ValueError(
                f"Two columns of 'data' are named '{display_text(key)}' after NFC normalisation."
            )
        seen.add(key)
    field_keys = [comparison_form(item["name"]) for item in fields]
    attr_types = data.attrs.get("types") if isinstance(data.attrs.get("types"), dict) else None
    values: list[Any] = []
    types: list[str] = []
    missing: list[numpy.ndarray[Any, Any]] = []
    for j, (name, key) in enumerate(zip(names, keys, strict=True)):
        declared = fields[field_keys.index(key)] if key in field_keys else None
        attr_type = attr_types.get(name) if attr_types is not None else None
        column_values, column_type, column_missing = _model_column(
            data.iloc[:, j], name, declared, attr_type
        )
        values.append(column_values)
        types.append(column_type)
        missing.append(column_missing)
    return ModelTable(names, keys, values, types, missing, len(data.index))


def _field_value_type(type_name: Any) -> str:
    """The type of values that a declared or read type requires."""
    if type_name in ("integer", "number"):
        return "number"
    if type_name == "boolean":
        return "boolean"
    return "string"


# The type of the values of a column of dtype object, by the Python type of
# each value.
_VALUE_TYPES: dict[type, str | None] = {
    str: "string",
    float: "number",
    int: "number",
    bool: "boolean",
    type(None): None,
}


def _model_column(
    series: pandas.Series,
    name: str,
    declared: Mapping[str, Any] | None,
    attr_type: Any,
) -> tuple[Any, str, numpy.ndarray[Any, Any]]:
    """The values, the type and the missing values of one column."""
    import numpy as np
    import pandas as pd

    dtype = series.dtype
    n = len(series)
    column_type: str | None
    if isinstance(dtype, pd.CategoricalDtype):
        # A categorical is read by the labels of its categories, as R reads a
        # factor, so its categories must be strings, and a categorical whose
        # values are all missing is a string column, as a factor is in R.
        categories = series.cat.categories.tolist()
        if not all(isinstance(category, str) for category in categories):
            raise ValueError(
                f"The categorical column '{display_text(name)}' of 'data' has categories "
                "that are not strings. Convert them to strings."
            )
        codes = series.cat.codes.to_numpy()
        objects: list[Any] = [categories[code] if code >= 0 else None for code in codes]
        return _object_column(objects, name, declared, "string")
    if isinstance(dtype, np.dtype) and dtype.kind == "b":
        values: Any = series.to_numpy(dtype=bool)
        column_missing = np.zeros(n, dtype=bool)
        column_type = "boolean"
    elif isinstance(dtype, np.dtype) and dtype.kind in "iuf":
        values = series.to_numpy(dtype=np.float64)
        column_missing = np.zeros(n, dtype=bool)
        column_type = "number"
    elif isinstance(dtype, pd.BooleanDtype):
        column_missing = series.isna().to_numpy(dtype=bool)
        values = series.to_numpy(dtype=bool, na_value=False)
        column_type = "boolean"
    elif isinstance(dtype, pd.api.extensions.ExtensionDtype) and dtype.kind in "iuf":
        column_missing = series.isna().to_numpy(dtype=bool)
        values = series.to_numpy(dtype=np.float64, na_value=np.nan)
        column_type = "number"
    elif isinstance(dtype, pd.StringDtype):
        # A column of a string dtype whose values are all missing is a string
        # column, as a character column of NA is in R.
        column_missing = series.isna().to_numpy(dtype=bool)
        # pandas-stubs refuses na_value=None, which pandas accepts.
        objects = cast(Any, series).to_numpy(dtype=object, na_value=None).tolist()
        return _object_column(objects, name, declared, "string", column_missing)
    elif isinstance(dtype, np.dtype) and dtype.kind == "O":
        return _object_column(series.tolist(), name, declared, attr_type)
    else:
        raise ValueError(_not_values_message(name))
    return _declared_column(values, column_type, column_missing, name, declared)


def _not_values_message(name: str) -> str:
    return (
        f"The column '{display_text(name)}' of 'data' is not a column of numbers, strings "
        "or booleans."
    )


def _object_column(
    objects: list[Any],
    name: str,
    declared: Mapping[str, Any] | None,
    attr_type: Any,
    known_missing: numpy.ndarray[Any, Any] | None = None,
) -> tuple[Any, str, numpy.ndarray[Any, Any]]:
    """A column given as Python values: None and pandas.NA are missing, and
    every other value must be a number, a str or a bool, all of one type."""
    import numpy as np
    import pandas as pd

    kinds: set[str] = set()
    missing = np.zeros(len(objects), dtype=bool)
    for i, value in enumerate(objects):
        kind = _VALUE_TYPES.get(type(value), "other")
        if kind == "other":
            if value is pd.NA:
                kind = None
            else:
                value = _numpy_scalar(value)
                if isinstance(value, bool):
                    kind = "boolean"
                elif isinstance(value, int | float):
                    kind = "number"
                elif isinstance(value, str):
                    kind = "string"
                    value = str(value)
                else:
                    raise ValueError(_not_values_message(name))
                objects[i] = value
        if kind is None:
            missing[i] = True
        else:
            kinds.add(kind)
    if known_missing is not None:
        missing |= known_missing
    if len(kinds) > 1:
        raise ValueError(_not_values_message(name))
    if kinds:
        column_type = kinds.pop()
    elif declared is not None:
        column_type = _field_value_type(declared.get("type", "string"))
    elif attr_type is not None:
        column_type = _field_value_type(attr_type)
    else:
        column_type = "boolean"
    values: Any
    if column_type == "number":
        values = np.array(
            [math.nan if m else float(v) for v, m in zip(objects, missing, strict=True)],
            dtype=np.float64,
        )
    elif column_type == "boolean":
        values = np.array(
            [False if m else bool(v) for v, m in zip(objects, missing, strict=True)], dtype=bool
        )
    else:
        values = np.empty(len(objects), dtype=object)
        for i, (value, m) in enumerate(zip(objects, missing, strict=True)):
            if not m:
                input_string(value, ["data", name, str(i)])
                values[i] = value
    return _declared_column(values, column_type, missing, name, declared)


def _declared_column(
    values: Any,
    column_type: str,
    missing: numpy.ndarray[Any, Any],
    name: str,
    declared: Mapping[str, Any] | None,
) -> tuple[Any, str, numpy.ndarray[Any, Any]]:
    """A column checked against the type of its declared field: a column whose
    values are all missing takes the field's type, and any other column must
    hold values of that type."""
    import numpy as np

    if declared is None:
        return values, column_type, missing
    wanted = _field_value_type(declared.get("type", "string"))
    if bool(missing.all()):
        n = len(missing)
        if wanted == "number":
            values = np.full(n, math.nan, dtype=np.float64)
        elif wanted == "boolean":
            values = np.zeros(n, dtype=bool)
        else:
            values = np.full(n, None, dtype=object)
        return values, wanted, missing
    if column_type != wanted:
        raise ValueError(
            f"The column '{display_text(name)}' of 'data' holds {column_type} values, but the "
            f"table block declares the type '{declared.get('type', 'string')}'."
        )
    return values, column_type, missing


# --- The builder ------------------------------------------------------------------


def build_formula_ir(
    formula: str,
    declaration: Any,
    table: ModelTable | None,
    coding: Coding,
    weights: str | None,
    sample_columns: list[str],
) -> dict[str, Any]:
    """The stages of ir.md (Errors) on inputs that have crossed the boundary."""
    tree = formula_tree(formula)
    # Stage 5: expansion.
    model = formula_expand(tree)
    _raise_found(model.issue)
    # Stage 6: context, whose last pass checks the names of the assembled IR.
    context = formula_context(model, declaration, table, coding, weights, sample_columns)
    ir = ir_document(context)
    long = ir_long_name(ir)
    if long is not None:
        raise_issue("E6076", {"name": long})
    return ir


def formula_tree(formula: str) -> Formula:
    """The parsed formula after the first four stages of the builder, which
    need no data: length, tokens, syntax and structure. The issue of the first
    stage that fails is raised."""
    # Stage 1: length.
    if len(formula) > FORMULA_LIMIT:
        raise_issue("E6001")
    # Stage 2: tokens.
    tokens = formula_tokens(formula)
    if not any(token.type == "op" and token.text == "~" for token in tokens):
        raise_issue("E6008")
    # Stage 3: syntax.
    tree = formula_parse(tokens, tokens[-1].offset)
    # Stage 4: structure.
    _raise_found(structure_issue(tree))
    return tree


def formula_response_key(formula: str) -> str | None:
    """The response of a formula, as the key by which the IR names its column,
    or None for a one-sided formula, after the first four stages of the
    builder, as the validator reads the response of /inputs/model/formula."""
    tree = formula_tree(formula)
    if tree.lhs is None:
        return None
    node, _ = call_name_node(tree.lhs)
    return node.key


def ir_long_name(ir: dict[str, Any]) -> str | None:
    """The first name of an IR, in the order of its canonical serialisation,
    that has more than 10,000 characters, or None (ir.md, Names)."""
    names = [column["name"] for column in ir["fixed"]["columns"]]
    names += [term["name"] for term in ir["fixed"]["terms"]]
    for random_term in ir["random"]:
        names += [column["name"] for column in random_term["columns"]]
        names += [random_term["factor"], random_term["name"]]
        names += [term["name"] for term in random_term["terms"]]
    return next((name for name in names if len(name) > FORMULA_LIMIT), None)


def _raise_found(found: Found | None) -> None:
    if found is not None:
        code, offset, args = found
        raise_issue(code, args, offset=offset)


# --- Expansion ------------------------------------------------------------------

Term = frozenset[str]


class _ExpansionStop(Exception):
    """Stops the evaluation of a part at its first issue."""

    def __init__(self, found: Found) -> None:
        super().__init__(found[0])
        self.found = found


def _terms_union(a: list[Term], b: list[Term]) -> list[Term]:
    """Appends the terms of b that a does not hold."""
    out = list(a)
    seen = set(a)
    for term in b:
        if term not in seen:
            seen.add(term)
            out.append(term)
    return out


def _terms_interact(a: list[Term], b: list[Term]) -> list[Term]:
    """For each term of a in order and, within it, each term of b in order,
    the union of the two."""
    return _terms_union([], [x | y for x in a for y in b])


@dataclass
class Part:
    """An evaluated part: its intercept and its terms in term order, each with
    its variables in the order of their first appearance in the part."""

    intercept: bool
    terms: list[list[str]]


def evaluate_part(summands: list[Summand], order: list[str]) -> Part | Found:
    """Evaluate the summands of a part (ir.md, Operators). Returns the part,
    or its first issue. Intercept summands, random terms and offsets are left
    out of the terms."""

    def term_name(term: Term) -> str:
        return ":".join(variable_text(key) for key in order if key in term)

    def evaluate(node: Node) -> list[Term]:
        if isinstance(node, Name):
            return [frozenset((node.key,))]
        if isinstance(node, Paren):
            terms = evaluate_sum(node.arg.lhs.summands)
            if not terms:
                raise _ExpansionStop(("E6037", node.start, {}))
            return terms
        if isinstance(node, Chain):
            result = evaluate(node.operands[0])
            for (op, at), operand in zip(node.ops, node.operands[1:], strict=True):
                b = evaluate(operand)
                # The terms the operator would form, counted with repetitions.
                if op == ":":
                    count = len(result) * len(b)
                elif op == "*":
                    count = len(result) + len(b) + len(result) * len(b)
                else:
                    count = len(result) + len(b)
                if count > FORMULA_LIMIT:
                    raise _ExpansionStop(("E6038", at, {}))
                if op == ":":
                    result = _terms_interact(result, b)
                elif op == "*":
                    result = _terms_union(_terms_union(result, b), _terms_interact(result, b))
                else:
                    every = frozenset().union(*result)
                    result = _terms_union(result, [every | term for term in b])
            return result
        if isinstance(node, Power):
            base = evaluate(node.base)
            assert isinstance(node.exponent, Number)
            result = base
            for _ in range(int(node.exponent.text) - 1):
                if len(result) * len(base) > FORMULA_LIMIT:
                    raise _ExpansionStop(("E6038", node.at, {}))
                following = _terms_interact(result, base)
                if following == result:
                    break
                result = following
            return result
        raise AssertionError("Internal error: unexpected node in a part.")

    def evaluate_sum(items: list[Summand]) -> list[Term]:
        held: list[Term] = []
        for summand in items:
            expr = summand.expr
            if isinstance(expr, Number) or is_random(expr):
                continue
            if isinstance(expr, Call) and expr.name == "offset":
                continue
            terms = evaluate(expr)
            if summand.sign == "-":
                present = set(held)
                absent = [term for term in terms if term not in present]
                if absent:
                    assert summand.sign_at is not None
                    raise _ExpansionStop(("E6031", summand.sign_at, {"term": term_name(absent[0])}))
                removed = set(terms)
                held = [term for term in held if term not in removed]
            else:
                held = _terms_union(held, terms)
                if len(held) > FORMULA_LIMIT:
                    at = summand.sign_at if summand.sign_at is not None else expr.start
                    raise _ExpansionStop(("E6038", at, {}))
        return held

    intercept = True
    for summand in summands:
        if isinstance(summand.expr, Number):
            intercept = summand.expr.text == "1" and summand.sign != "-"
    try:
        terms = evaluate_sum(summands)
    except _ExpansionStop as stop:
        return stop.found
    terms = sorted(terms, key=len)
    return Part(intercept, [[key for key in order if key in term] for term in terms])


def term_name_of(variables: list[str], labels: list[str | None] | None = None) -> str:
    """The name of a term whose variables are in order, each with the level it
    carries, if any."""
    if not variables:
        return "(Intercept)"
    parts = [variable_text(variable) for variable in variables]
    if labels is not None:
        parts = [
            part if label is None else part + "[" + label + "]"
            for part, label in zip(parts, labels, strict=True)
        ]
    return ":".join(parts)


def random_term_name(intercept: bool, term_names: list[str], factor_name: str) -> str:
    """The name of a random term."""
    return " + ".join(["1" if intercept else "0", *term_names]) + " | " + factor_name


@dataclass
class Use:
    """An appearance of a name in the formula and its use."""

    key: str
    value: str
    offset: int
    use: str
    written: int = 0
    double: bool = False


@dataclass
class Response:
    key: str
    value: str
    transform: str
    offset: int
    start: int


@dataclass
class RandomTerm:
    """A random term of step 3 of ir.md (Random terms)."""

    factor: frozenset[str]
    intercept: bool
    terms: list[list[str]]
    double: bool
    written: int
    open: int
    grouping: list[str] = field(default_factory=list)
    factor_name: str = ""


@dataclass
class Offset:
    key: str
    value: str
    transform: str
    at: int | None


@dataclass
class Model:
    """The expanded formula: the response, the fixed part, the random terms,
    the offsets and every name with its use, or the first issue."""

    issue: Found | None
    response: Response | None
    fixed: Part | None
    random: list[RandomTerm]
    offsets: list[Offset]
    uses: list[Use]


def formula_expand(tree: Formula) -> Model:
    """Expand the parsed formula (ir.md, Expansion) into the response, the
    fixed part, the random terms and the offsets, with every name of the
    formula and its use. The random terms are grouped by factor in the order
    in which each factor first arises. The first issue of expansion, by
    offset and then code, is returned as the issue."""
    found: list[Found] = []
    uses: list[Use] = []

    def use(nodes: list[Name], kind: str, written: int = 0, double: bool = False) -> None:
        for node in nodes:
            uses.append(Use(node.key, node.value, node.start, kind, written, double))

    response = None
    if tree.lhs is not None:
        node, transform = call_name_node(tree.lhs)
        response = Response(node.key, node.value, transform, node.start, tree.lhs.start)
        use([node], "response" if transform == "identity" else "log_response")
    summands = tree.rhs.summands

    def kind_of(expr: Node) -> str:
        if is_random(expr):
            return "random"
        if isinstance(expr, Call):
            return "offset"
        if isinstance(expr, Number):
            return "number"
        return "fixed"

    kinds = [kind_of(summand.expr) for summand in summands]
    # The fixed part.
    fixed_nodes = [
        name
        for summand, kind in zip(summands, kinds, strict=True)
        if kind == "fixed"
        for name in formula_names(summand.expr)
    ]
    use(fixed_nodes, "predictor")
    fixed_order = list(dict.fromkeys(node.key for node in fixed_nodes))
    fixed_part = evaluate_part(
        [s for s, k in zip(summands, kinds, strict=True) if k not in ("random", "offset")],
        fixed_order,
    )
    fixed: Part | None = None
    if isinstance(fixed_part, Part):
        fixed = fixed_part
    else:
        found.append(fixed_part)
    # The random terms, in the order in which they are written.
    factors: dict[frozenset[str], list[str]] = {}

    def factor_name(key: frozenset[str]) -> str:
        return ":".join(variable_text(variable) for variable in factors[key])

    produced: list[RandomTerm] = []
    written = 0
    for summand, kind in zip(summands, kinds, strict=True):
        if kind != "random":
            continue
        written += 1
        paren = summand.expr
        assert isinstance(paren, Paren) and paren.arg.rhs is not None
        double = paren.arg.bar == "||"
        lhs_nodes = formula_names(paren.arg.lhs)
        use(lhs_nodes, "predictor", written, double)
        grouping_nodes = formula_names(paren.arg.rhs)
        use(grouping_nodes, "grouping", written)
        order = list(dict.fromkeys(node.key for node in lhs_nodes))
        part = evaluate_part(paren.arg.lhs.summands, order)
        if not isinstance(part, Part):
            found.append(part)
            continue
        grouping_seen: set[str] = set()
        repeated = None
        for node in grouping_nodes:
            if node.key in grouping_seen:
                repeated = node
                break
            grouping_seen.add(node.key)
        if repeated is not None:
            found.append(("E6033", repeated.start, {"column": repeated.value}))
            continue
        if not part.intercept and not part.terms:
            found.append(("E6034", paren.start, {}))
            continue
        segments = _slash_segments(paren.arg.rhs.summands[0].expr)
        for k in range(len(segments)):
            keys = [key for segment in segments[: k + 1] for key in segment]
            factor = frozenset(keys)
            if factor not in factors:
                factors[factor] = keys
            pieces: list[tuple[bool, list[list[str]]]]
            if double:
                pieces = [(True, [])] if part.intercept else []
                pieces += [(False, [term]) for term in part.terms]
            else:
                pieces = [(part.intercept, part.terms)]
            for intercept, terms in pieces:
                produced.append(RandomTerm(factor, intercept, terms, double, written, paren.start))
    # Duplicate random terms, before any term of a frozen factor is split.
    first_of: dict[Any, RandomTerm] = {}
    for term in produced:
        identity = (term.factor, term.intercept, frozenset(frozenset(t) for t in term.terms))
        earlier = first_of.get(identity)
        if earlier is None:
            first_of[identity] = term
            continue
        name = random_term_name(
            earlier.intercept,
            [term_name_of(t) for t in earlier.terms],
            factor_name(earlier.factor),
        )
        found.append(("E6035", term.open, {"term": name}))
    # Offsets.
    offsets: list[Offset] = []
    for summand, kind in zip(summands, kinds, strict=True):
        if kind != "offset":
            continue
        call = summand.expr
        assert isinstance(call, Call)
        name_node, transform = call_name_node(call.args[0].lhs)
        use([name_node], "offset" if transform == "identity" else "log_offset")
        for earlier_offset in offsets:
            if earlier_offset.key == name_node.key and earlier_offset.transform == transform:
                found.append(("E6036", call.start, {}))
                break
        offsets.append(Offset(name_node.key, name_node.value, transform, call.start))
    # The response after '~'.
    if response is not None:
        again = [
            u for u in uses if u.use not in ("response", "log_response") and u.key == response.key
        ]
        if again:
            first = min(again, key=lambda u: u.offset)
            found.append(("E6032", first.offset, {"column": response.value}))
    # The random terms of the IR, grouped by factor.
    factor_order = {key: position for position, key in enumerate(factors)}
    produced.sort(key=lambda term: factor_order[term.factor])
    for term in produced:
        term.grouping = factors[term.factor]
        term.factor_name = factor_name(term.factor)
    return Model(first_issue(found), response, fixed, produced, offsets, uses)


def _slash_segments(node: Node) -> list[list[str]]:
    """The segments f1, f2, ... of a grouping f1/f2/..., each the keys of its
    names joined by ':' in the order written."""
    if isinstance(node, Chain) and all(op == "/" for op, _ in node.ops):
        return [[name.key for name in formula_names(operand)] for operand in node.operands]
    return [[name.key for name in formula_names(node)]]


# --- Context --------------------------------------------------------------------


def person_columns(declaration: Any) -> set[str]:
    """The columns that identify persons (ir.md, Kinds of columns): those with
    the role 'id' and the label columns of the disclosure unit, of every unit
    with the role 'participant' and of every unit nested in one of these."""
    if not isinstance(declaration, dict):
        return set()
    keys: list[str] = []
    for name, entry in (declaration.get("variables") or {}).items():
        if isinstance(entry, dict) and entry.get("role") == "id":
            keys.append(name)
    units = declaration.get("units") or []
    unit_names = [unit["name"] for unit in units]
    roles = [unit.get("role") for unit in units]
    parents = [unit.get("nested_in") for unit in units]
    participants = [
        name for name, role in zip(unit_names, roles, strict=True) if role == "participant"
    ]
    disclosure = declaration.get("disclosure_unit")
    if disclosure is None and len(participants) == 1:
        disclosure = participants[0]
    chosen = list(dict.fromkeys(([disclosure] if disclosure is not None else []) + participants))
    while True:
        more = [
            name
            for name, parent in zip(unit_names, parents, strict=True)
            if parent in chosen and name not in chosen
        ]
        if not more:
            break
        chosen.extend(dict.fromkeys(more))
    for unit in units:
        if unit["name"] in chosen:
            keys.extend(unit["columns"])
    return {comparison_form(key) for key in keys}


def level_label(level: Any) -> str:
    """The label of a level in names: the string itself, an integer in decimal
    digits and a boolean as 'true' or 'false'."""
    if isinstance(level, str):
        return level
    if isinstance(level, bool):
        return "true" if level else "false"
    return format_integer(level)


@dataclass
class ColumnInfo:
    """The kind and levels of a column, and later its coding as a predictor."""

    key: str
    j: int | None
    kind: str = ""
    levels: list[Any] | None = None
    source: str | None = None
    reference: int = 0
    contrast: str = "treatment"
    frozen: bool = False
    centring: str = "none"
    digits: int = 6
    value_text: str | None = None
    constant: str | None = None


@dataclass
class PartColumn:
    """A column of a part: its name, its term, the level of each categorical
    variable and the label of each variable's level, or None."""

    name: str
    term: int
    levels: dict[str, Any]
    labels: list[str | None] | None


@dataclass
class PartColumns:
    """The coding and columns of a part. A part that '||' split from a term
    of a frozen factor also holds the labels and levels that its variables
    carry."""

    intercept: bool
    terms: list[list[str]]
    coding: list[dict[str, str]]
    columns: list[PartColumn]
    labels: list[str | None] | None = None
    levels: dict[str, Any] | None = None


@dataclass
class RandomPart:
    factor: frozenset[str]
    grouping: list[str]
    factor_name: str
    open: int
    part: PartColumns


@dataclass
class Context:
    response: Response | None
    declared: dict[str, Any] | None
    predictors: dict[str, ColumnInfo]
    fixed: PartColumns
    random: list[RandomPart]
    offsets: list[Offset]
    weights: str | None
    sample_columns: list[str]
    have_data: bool


def formula_context(
    model: Model,
    declaration: Any,
    table: ModelTable | None,
    coding: Coding,
    weights: str | None,
    sample_columns: list[str],
) -> Context:
    """Run the passes of ir.md (Errors, stage 6) and return what the IR needs:
    the columns and their kinds, the predictors with their coding, the parts
    with their coding and columns, the offsets, the design sample and the
    centring constants."""
    fields = _table_fields(declaration)
    field_keys = [comparison_form(item["name"]) for item in fields]
    have_data = table is not None
    persons = person_columns(declaration)
    cache: dict[str, ColumnInfo | None] = {}

    def column(key: str) -> ColumnInfo | None:
        """The kind and levels of a column, or None when it is not a column."""
        if key in cache:
            return cache[key]
        j = None
        if table is not None:
            j = table.index(key)
            if j is None:
                cache[key] = None
                return None
        position = field_keys.index(key) if key in field_keys else None
        if table is None and position is None:
            cache[key] = None
            return None
        declared_field = fields[position] if position is not None else None
        if declared_field is not None:
            type_name = declared_field.get("type", "string")
        else:
            assert table is not None and j is not None
            type_name = table.types[j]
        info = ColumnInfo(key, j)
        if declared_field is not None and "categories" in declared_field:
            info.kind = "categorical"
            info.levels = [list_item_value(item) for item in declared_field["categories"]]
            info.source = "declared"
        elif type_name == "boolean":
            info.kind = "categorical"
            info.levels = [False, True]
            info.source = "boolean"
        elif type_name in ("date", "datetime"):
            info.kind = "date"
        elif type_name in ("number", "integer"):
            info.kind = "numeric"
        else:
            info.kind = "categorical"
            info.source = "table"
            if table is not None and j is not None:
                info.levels = _table_levels(table, j)
        cache[key] = info
        return info

    def first(found: list[Found]) -> None:
        _raise_found(first_issue(found))

    uses = model.uses
    # Pass 1: columns.
    first([("E6051", u.offset, {"column": u.value}) for u in uses if column(u.key) is None])

    def frozen_by_coding(key: str) -> bool:
        return coding.entry(key).get("frozen") is True

    # The declared variables entry of the response.
    response = model.response
    declared: dict[str, Any] | None = None
    variables = declaration.get("variables") if isinstance(declaration, dict) else None
    if response is not None and variables:
        for name, entry in variables.items():
            if comparison_form(name) == response.key:
                declared = entry
                break
    # Pass 2: uses.
    found: list[Found] = []
    allowed = {
        "response": ("numeric", "categorical"),
        "log_response": ("numeric",),
        "predictor": ("numeric", "categorical"),
        "offset": ("numeric",),
        "log_offset": ("numeric",),
    }
    use_names = {
        "response": "the response",
        "log_response": "the argument of log()",
        "predictor": "a predictor",
        "offset": "an offset",
        "log_offset": "the argument of log()",
    }
    double_seen: set[int] = set()
    for u in uses:
        info = column(u.key)
        assert info is not None
        kind = info.kind
        if u.use != "grouping" and kind not in allowed[u.use]:
            args = {"column": u.value, "kind": kind, "use": use_names[u.use]}
            found.append(("E6052", u.offset, args))
        if u.use == "predictor" and u.key in persons:
            found.append(("E6068", u.offset, {"column": u.value}))
        if (
            u.use == "predictor"
            and u.double
            and u.written not in double_seen
            and kind == "categorical"
            and not frozen_by_coding(u.key)
        ):
            double_seen.add(u.written)
            found.append(("E6053", u.offset, {"column": u.value}))
    if response is not None and response.transform == "log" and declared is not None:
        members = [m for m in ("event_level", "trials", "exposure") if m in declared]
        if members:
            found.append(("E6054", response.start, {"member": members[0]}))
    first(found)

    # Pass 3: declared columns, weights and sample columns.
    def numeric_column(name: str) -> bool:
        info = column(comparison_form(name))
        return info is not None and info.kind == "numeric"

    trials = declared.get("trials") if declared is not None else None
    exposure = declared.get("exposure") if declared is not None else None
    if trials is not None and not numeric_column(trials):
        raise_issue("E6065", {"column": trials, "member": "trials"})
    if exposure is not None and not numeric_column(exposure["column"]):
        raise_issue("E6065", {"column": exposure["column"], "member": "exposure"})
    if weights is not None and not numeric_column(weights):
        raise_issue("E6066", {"column": weights})
    for name in sample_columns:
        if column(comparison_form(name)) is None:
            raise_issue("E6070", {"column": name})
    # The predictors of the IR: the columns of the terms after expansion.
    fixed = model.fixed
    assert fixed is not None
    random = model.random
    predictor_keys = sorted(
        dict.fromkeys(
            [key for term in fixed.terms for key in term]
            + [key for r in random for term in r.terms for key in term]
        )
    )

    def first_use(key: str) -> Use:
        """The first appearance of a predictor in a product of the formula."""
        return min(
            (u for u in uses if u.use == "predictor" and u.key == key), key=lambda u: u.offset
        )

    # Pass 4: the coding argument.
    predictors: dict[str, ColumnInfo] = {}
    for key in predictor_keys:
        info = column(key)
        assert info is not None
        predictors[key] = info
    check_coding(coding, predictors)
    # Pass 5: levels.
    found = []
    for key in predictor_keys:
        info = predictors[key]
        if info.kind == "categorical":
            appearance = first_use(key)
            if info.levels is None:
                found.append(("E6055", appearance.offset, {"column": appearance.value}))
            elif len(info.levels) < 2:
                found.append(("E6056", appearance.offset, {"column": appearance.value}))
            elif not all(level_writable(level) for level in info.levels):
                found.append(("E6074", appearance.offset, {"column": appearance.value}))
    first(found)
    # Pass 6: reference levels and the coding of each predictor.
    for key in predictor_keys:
        info = predictors[key]
        entry = coding.entry(key)
        if info.kind == "categorical":
            assert info.levels is not None
            position = 0
            if "reference" in entry:
                reference = entry["reference"]
                found_position = level_position(reference, info.levels)
                if found_position is None:
                    name = coding.names[coding.keys.index(key)]
                    raise_issue("E6064", {"reference": [reference], "column": name})
                position = found_position
            info.reference = position
            info.contrast = entry.get("contrast", "treatment")
            info.frozen = entry.get("frozen") is True
        else:
            info.centring = entry.get("centring", "none")
            info.digits = int(entry.get("significant_digits", 6))
            info.value_text = entry.get("value")
    # Pass 7: the exposure.
    offsets = list(model.offsets)
    if exposure is not None:
        exposure_key = comparison_form(exposure["column"])
        wanted = "log" if exposure["scale"] == "raw" else "identity"
        found = []
        for o in offsets:
            if o.key == exposure_key and o.transform != wanted:
                assert o.at is not None
                found.append(("E6057", o.at, {"column": o.value}))
        first(found)
        if not any(o.key == exposure_key and o.transform == wanted for o in offsets):
            offsets.append(Offset(exposure_key, exposure["column"], wanted, None))
    # Pass 8: size. The columns of the fixed part and of each random term,
    # counted before they are formed and before any term is split.
    fixed_coding = part_coding(fixed.intercept, fixed.terms, predictors)
    if part_size(fixed.intercept, fixed.terms, fixed_coding, predictors) > FORMULA_LIMIT:
        raise_issue("E6075", {"part": "fixed part"})
    random_coding = [part_coding(term.intercept, term.terms, predictors) for term in random]
    for term, term_coding in zip(random, random_coding, strict=True):
        if part_size(term.intercept, term.terms, term_coding, predictors) > FORMULA_LIMIT:
            name = random_term_name(
                term.intercept, [term_name_of(t) for t in term.terms], term.factor_name
            )
            raise_issue("E6075", {"part": "random term '" + name + "'"})
    # The coding and columns of each part, with the terms of frozen factors
    # that '||' gives split into their columns.
    fixed_part = part_columns(fixed.intercept, fixed.terms, predictors, fixed_coding)
    random_parts: list[RandomPart] = []
    for term, term_coding in zip(random, random_coding, strict=True):
        part = part_columns(term.intercept, term.terms, predictors, term_coding)
        split = (
            term.double
            and not term.intercept
            and len(term.terms) == 1
            and len(part.columns) > 1
            and any(predictors[key].frozen for key in term.terms[0])
        )
        if split:
            for piece_column in part.columns:
                piece = PartColumns(
                    part.intercept,
                    part.terms,
                    part.coding,
                    [piece_column],
                    piece_column.labels,
                    piece_column.levels,
                )
                random_parts.append(
                    RandomPart(term.factor, term.grouping, term.factor_name, term.open, piece)
                )
        else:
            random_parts.append(
                RandomPart(term.factor, term.grouping, term.factor_name, term.open, part)
            )
    # Pass 9: columns of random terms (E6058), then names (E6059).
    found = []
    for factor in dict.fromkeys(r.factor for r in random_parts):
        seen: list[str] = []
        for r in random_parts:
            if r.factor != factor:
                continue
            names_here = [c.name for c in r.part.columns]
            shared = [name for name in names_here if name in seen]
            if shared:
                found.append(("E6058", r.open, {"column": shared[0], "factor": r.factor_name}))
            seen.extend(names_here)
    first(found)
    for part in [fixed_part] + [r.part for r in random_parts]:
        names_seen: set[str] = set()
        for c in part.columns:
            if c.name in names_seen:
                raise_issue("E6059", {"name": c.name})
            names_seen.add(c.name)
    # Pass 10: centring. The design sample uses the sample columns of the IR,
    # which leave out the columns that the IR reads, the response and the
    # trials column among them.
    read_keys = list(
        dict.fromkeys(
            predictor_keys
            + [key for r in random for key in r.grouping]
            + [o.key for o in offsets]
            + ([comparison_form(weights)] if weights is not None else [])
        )
    )
    read_all = set(read_keys)
    if response is not None:
        read_all.add(response.key)
    if trials is not None:
        read_all.add(comparison_form(trials))
    sample_keys = sort_identifiers(
        key
        for key in dict.fromkeys(comparison_form(name) for name in sample_columns)
        if key not in read_all
    )
    design = None
    if table is not None:
        design = design_rows(table, list(dict.fromkeys(read_keys + sample_keys)))
    for key in predictor_keys:
        info = predictors[key]
        if info.kind != "numeric":
            continue
        if info.centring == "value":
            assert info.value_text is not None
            if not math.isfinite(float(info.value_text)):
                raise_issue("E6077", {"column": key})
        if info.centring != "mean" or table is None:
            continue
        assert design is not None and info.j is not None
        if len(design) == 0:
            raise_issue("E6067", {"column": key})
        values = table.values[info.j][design]
        if not bool(_all_finite(values)):
            raise_issue("E6073", {"column": key})
        total = exact_sum(values.tolist())
        constant = (
            decimal_string(total / len(values), info.digits) if math.isfinite(total) else None
        )
        if constant is None or not math.isfinite(float(constant)):
            raise_issue("E6077", {"column": key})
        info.constant = constant
    return Context(
        response=response,
        declared=declared,
        predictors=predictors,
        fixed=fixed_part,
        random=random_parts,
        offsets=offsets,
        weights=comparison_form(weights) if weights is not None else None,
        sample_columns=sample_keys,
        have_data=have_data,
    )


def _table_levels(table: ModelTable, j: int) -> list[Any]:
    """The distinct values of a column of strings in all rows, missing values
    excluded, compared and written after NFC and in code-point order."""
    values = table.values[j][~table.missing[j]]
    return list(sort_identifiers({comparison_form(value) for value in set(values.tolist())}))


def _all_finite(values: Any) -> bool:
    import numpy as np

    return bool(np.isfinite(values).all())


def design_rows(table: ModelTable, keys: list[str]) -> numpy.ndarray[Any, Any]:
    """The rows of the table, counted from 0, in which no column of the given
    keys is missing."""
    import numpy as np

    present = np.ones(table.rows, dtype=bool)
    for key in keys:
        j = table.index(key)
        assert j is not None
        present &= ~table.missing[j]
    return np.flatnonzero(present).astype(np.int64)


def exact_sum(values: list[float]) -> float:
    """The sum of finite doubles, computed exactly and rounded once to the
    nearest double, ties to even (ir.md, Centring).

    math.fsum() computes it, but raises OverflowError when a partial sum
    leaves the range of doubles. The sum is then computed in integers, each
    double scaled by 2^1074, and divided by 2^1074 with Python's correctly
    rounded division of integers. A sum beyond the largest double rounds to an
    infinity.
    """
    try:
        return math.fsum(values)
    except OverflowError:
        total = 0
        for value in values:
            numerator, denominator = value.as_integer_ratio()
            total += numerator << (1074 - denominator.bit_length() + 1)
        try:
            return total / (1 << 1074)
        except OverflowError:
            return math.inf if total > 0 else -math.inf


def level_position(reference: Any, levels: list[Any]) -> int | None:
    """The position of a reference level among the levels, compared by type
    and value and, for strings, after NFC, or None."""
    sample = levels[0]
    if isinstance(sample, str):
        if not isinstance(reference, str):
            return None
        form = comparison_form(reference)
        return next((i for i, level in enumerate(levels) if level == form), None)
    if isinstance(sample, bool):
        if not isinstance(reference, bool):
            return None
        return next((i for i, level in enumerate(levels) if level is reference), None)
    if isinstance(reference, bool) or not isinstance(reference, int | float):
        return None
    return next((i for i, level in enumerate(levels) if float(level) == float(reference)), None)


def check_coding(coding: Coding, predictors: dict[str, ColumnInfo]) -> None:
    """Pass 4 of the context (ir.md, Coding argument): the entries one at a
    time in code-point order of their keys."""
    for k in sorted(range(len(coding.keys)), key=lambda i: coding.keys[i]):
        key = coding.keys[k]
        name = coding.names[k]
        info = predictors.get(key)
        if info is None:
            raise_issue("E6061", {"column": name})
        entry = coding.entries[k]
        members = sorted(entry)
        for member in members:
            if member not in _CODING_MEMBERS or not _coding_value_valid(member, entry[member]):
                raise_issue("E6063", {"column": name, "member": member})
        for member in members:
            if (member in _CATEGORICAL_MEMBERS) != (info.kind == "categorical"):
                raise_issue("E6062", {"column": name, "member": member})
        if info.kind == "numeric":
            centring = entry.get("centring", "none")
            if "significant_digits" in entry and centring != "mean":
                raise_issue("E6063", {"column": name, "member": "significant_digits"})
            if "value" in entry and centring != "value":
                raise_issue("E6063", {"column": name, "member": "value"})
            if centring == "value" and "value" not in entry:
                raise_issue("E6063", {"column": name, "member": "centring"})


def _whole(value: Any) -> bool:
    """Whether a value is a whole number: an int or a finite float with an
    integral value, never a bool."""
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and math.isfinite(value) and value.is_integer()


def _coding_value_valid(member: str, value: Any) -> bool:
    """Whether a member of the coding argument has a valid value."""
    if member == "contrast":
        return isinstance(value, str) and value in ("treatment", "sum", "simple")
    if member == "centring":
        return isinstance(value, str) and value in ("none", "mean", "value")
    if member == "frozen":
        return isinstance(value, bool)
    if member == "reference":
        return (
            isinstance(value, str)
            or isinstance(value, bool)
            or (_whole(value) and abs(value) <= MAX_INTEGER)
        )
    if member == "significant_digits":
        return _whole(value) and 1 <= value <= 15
    if member == "value":
        return (
            isinstance(value, str)
            and is_decimal_string(value)
            and significant_digit_count(value) <= 15
        )
    return False


def level_writable(level: Any) -> bool:
    """Whether a level can be written in the IR (ir.md, Kinds of columns): a
    string without control characters whose code points Unicode 14.0 assigns.
    Integers and booleans always can."""
    if not isinstance(level, str):
        return True
    return _CONTROL.search(level) is None and is_normalisable(level)


def part_size(
    intercept: bool,
    terms: list[list[str]],
    coding: list[dict[str, str]],
    predictors: dict[str, ColumnInfo],
) -> int:
    """The number of columns of a part, counted from the coding of its terms
    without forming them: one for the intercept, and for each term the product
    of one for a numeric variable, k for a factor of k levels coded by
    indicators and k - 1 for one coded by its contrast."""
    size = int(intercept)
    for term_coding in coding:
        width = 1
        for variable, how in term_coding.items():
            levels = predictors[variable].levels
            assert levels is not None
            width *= len(levels) if how == "indicator" else len(levels) - 1
        size += width
    return size


def part_coding(
    intercept: bool, terms: list[list[str]], predictors: dict[str, ColumnInfo]
) -> list[dict[str, str]]:
    """The coding of each categorical variable in each term of a part (ir.md,
    Contrasts or indicators). ``terms`` holds the terms in term order, each with
    its variables in order."""
    coding: list[dict[str, str]] = []
    for i, term in enumerate(terms):
        entry: dict[str, str] = {}
        for variable in term:
            info = predictors[variable]
            if info.kind != "categorical":
                continue
            others = [other for other in term if other != variable]
            contrast = (
                info.frozen
                or not others
                or any(all(other in earlier for other in others) for earlier in terms[:i])
            )
            entry[variable] = "contrast" if contrast else "indicator"
        coding.append(entry)
    if not intercept:
        done = False
        for i, term in enumerate(terms):
            for variable in term:
                info = predictors[variable]
                if info.kind == "categorical" and not info.frozen:
                    coding[i][variable] = "indicator"
                    done = True
                    break
            if done:
                break
    return coding


def part_columns(
    intercept: bool,
    terms: list[list[str]],
    predictors: dict[str, ColumnInfo],
    coding: list[dict[str, str]] | None = None,
) -> PartColumns:
    """The columns of a part (ir.md, Columns of a term), from the coding of its
    terms."""
    if coding is None:
        coding = part_coding(intercept, terms, predictors)
    columns: list[PartColumn] = []
    if intercept:
        columns.append(PartColumn("(Intercept)", 0, {}, None))
    for i, term in enumerate(terms):
        pieces: list[tuple[list[str], dict[str, Any]]] = [([], {})]
        for variable in term:
            info = predictors[variable]
            options: list[tuple[str, bool, Any]]
            if info.kind == "numeric":
                options = [(variable, False, None)]
            else:
                assert info.levels is not None
                skipped = info.reference if coding[i][variable] == "contrast" else -1
                options = [
                    (variable + "[" + level_label(level) + "]", True, level)
                    for position, level in enumerate(info.levels)
                    if position != skipped
                ]
            grown: list[tuple[list[str], dict[str, Any]]] = []
            for option_name, has_level, level in options:
                for piece_names, piece_levels in pieces:
                    levels = dict(piece_levels)
                    if has_level:
                        levels[variable] = level
                    grown.append((piece_names + [option_name], levels))
            pieces = grown
        for piece_names, piece_levels in pieces:
            labels = [
                level_label(piece_levels[variable]) if variable in piece_levels else None
                for variable in term
            ]
            columns.append(
                PartColumn(":".join(piece_names), i + int(intercept), piece_levels, labels)
            )
    return PartColumns(intercept, terms, coding, columns)


# --- The IR document ------------------------------------------------------------


def ir_document(context: Context) -> dict[str, Any]:
    """Assemble the IR document (ir.md, The IR document) as a dict."""
    predictors: dict[str, Any] = {}
    for key, info in context.predictors.items():
        if info.kind == "numeric":
            centring: dict[str, Any] = {"rule": info.centring}
            if info.centring == "mean":
                centring["sample"] = "design"
                if context.have_data:
                    centring["constant"] = {
                        "significant_digits": info.digits,
                        "value": info.constant,
                    }
                else:
                    centring["significant_digits"] = info.digits
            elif info.centring == "value":
                assert info.value_text is not None
                centring["constant"] = {
                    "significant_digits": max(significant_digit_count(info.value_text), 1),
                    "value": info.value_text,
                }
            predictors[key] = {"kind": "numeric", "centring": centring}
            continue
        assert info.levels is not None
        entry: dict[str, Any] = {
            "kind": "categorical",
            "levels": list(info.levels),
            "levels_source": info.source,
            "contrast": info.contrast,
            "reference": info.levels[info.reference],
        }
        if info.frozen:
            entry["frozen"] = True
        predictors[key] = entry
    random = []
    for r in context.random:
        document = _part_document(r.part)
        term_names = [term["name"] for term in document["terms"]]
        if r.part.intercept:
            term_names = term_names[1:]
        random.append(
            {
                "name": random_term_name(r.part.intercept, term_names, r.factor_name),
                "factor": r.factor_name,
                "grouping": list(r.grouping),
                "covariance": "unstructured",
                **document,
            }
        )
    offsets = sorted(context.offsets, key=lambda o: (o.key, o.transform))
    ir: dict[str, Any] = {"ir_version": "0.1.0"}
    response = context.response
    if response is not None:
        ir["response"] = {"variable": response.key, "transform": response.transform}
        declared = context.declared or {}
        if "event_level" in declared:
            ir["response"]["event_level"] = declared["event_level"]
        if "trials" in declared:
            ir["response"]["trials"] = comparison_form(declared["trials"])
    ir["predictors"] = predictors
    ir["fixed"] = _part_document(context.fixed)
    ir["random"] = random
    ir["offsets"] = [{"variable": o.key, "transform": o.transform} for o in offsets]
    if context.weights is not None:
        ir["weights"] = {"variable": context.weights}
    if context.sample_columns:
        ir["sample_columns"] = list(context.sample_columns)
    return ir


def _part_document(part: PartColumns) -> dict[str, Any]:
    """The terms and columns of a part, as the IR document holds them."""
    terms: list[dict[str, Any]] = []
    if part.intercept:
        terms.append({"name": "(Intercept)", "variables": []})
    for i, term in enumerate(part.terms):
        labels = part.labels
        variables = []
        for v, variable in enumerate(term):
            entry: dict[str, Any] = {"variable": variable}
            coding = part.coding[i]
            if variable in coding:
                entry["coding"] = coding[variable]
                if labels is not None and labels[v] is not None:
                    assert part.levels is not None
                    entry["level"] = part.levels[variable]
            variables.append(entry)
        terms.append({"name": term_name_of(term, labels), "variables": variables})
    columns = [{"name": c.name, "term": c.term, "levels": dict(c.levels)} for c in part.columns]
    return {"terms": terms, "columns": columns}
