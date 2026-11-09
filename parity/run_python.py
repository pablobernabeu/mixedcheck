"""Runs the conformance corpora with the installed Python package for the
parity harness (parity/README.md).

Usage: python run_python.py PLAN OUTPUT

PLAN is the JSON file that parity.py writes, with the corpus directory, the
corpus files to run with the kind of their cases and the vendored files of
spec/ to read. OUTPUT receives one JSON object per line: first a header that
describes the run, then one record for each case and part of a case, with the
outcome that the package gave. Every string of an outcome is written as the
lower-case hexadecimal digits of its UTF-8 bytes, so that run_r.R and this
script write identical records for identical outcomes. The harness reads the
corpora with the package's own strict reader, as the package tests do.
"""

from __future__ import annotations

import json
import math
import platform
import struct
import sys
import tempfile
import warnings
from collections.abc import Callable
from importlib.resources import files
from pathlib import Path
from typing import Any

import mixedcheck
from mixedcheck import (
    MixedcheckError,
    MixedcheckWarning,
    canonical_bytes,
    canonical_hash,
    commitment_key_id,
    design_matrices,
    design_samples,
    formula_ir,
    hash_bytes,
    hash_file,
    keyed_commitment,
    read_json_strict,
    read_registry,
    read_table,
    spec_versions,
    validate_declaration,
)
from mixedcheck._hash import hmac_sha256, json_pointer_get
from mixedcheck._numbers import decimal_string
from mixedcheck._unicode import (
    compare_identifiers,
    comparison_form,
    is_normalisable,
    sort_identifiers,
)

LANGUAGE = "Python"
MODES = ("plain", "data", "hashable")


class UnexpectedOutcome(Exception):
    """A step that the corpus expects to succeed failed."""


def encode(x: Any) -> Any:
    """The outcome with every string and byte string as hexadecimal digits."""
    if isinstance(x, bytes):
        return x.hex()
    if isinstance(x, str):
        return x.encode("utf-8", "surrogatepass").hex()
    if isinstance(x, dict):
        return {key: encode(value) for key, value in x.items()}
    if isinstance(x, list | tuple):
        return [encode(value) for value in x]
    return x


def outcome_of(compute: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    """Call compute and return its outcome, the issues of a MixedcheckError or
    the text of any other error, with the issues of any MixedcheckWarning."""
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            outcome = compute()
        except MixedcheckError as err:
            outcome = {"issues": err.issues}
        except Exception as err:
            outcome = {"error": f"{type(err).__name__}: {err}"}
    raised = [
        issue
        for warning in caught
        if isinstance(warning.message, MixedcheckWarning)
        for issue in warning.message.issues
    ]
    if raised:
        outcome["warnings"] = raised
    return encode(outcome)


def bits_double(bits: str) -> float:
    """The double whose bits are given as 16 hexadecimal digits."""
    return struct.unpack(">d", bytes.fromhex(bits))[0]


def double_bits(value: Any) -> str:
    """The 16 hexadecimal digits of the bits of a double."""
    return struct.pack(">d", float(value)).hex()


def canonical(value: Any, profile: str) -> dict[str, Any]:
    """The canonical bytes of a value in a profile and its hash."""
    return {"canonical": canonical_bytes(value, profile), "sha256": canonical_hash(value, profile)}


def canonical_of_value_read(value: Any, profile: str) -> dict[str, Any]:
    """The canonical bytes and hash of a value that a reader returned, which
    must be writable in the profile in which it was read."""
    try:
        return canonical(value, profile)
    except MixedcheckError as err:
        codes = ", ".join(issue["code"] for issue in err.issues)
        raise UnexpectedOutcome(f"writing the value read gave {codes}") from err


# Cases of json/, numbers/format.json and read.json and unicode/.


def reader_source(case: dict[str, Any], scratch: Path) -> bytes | str:
    if "input" in case:
        return case["input"].encode("utf-8")
    if "input_hex" in case:
        return bytes.fromhex(case["input_hex"])
    if case["file"] == "missing":
        return str(scratch / "mixedcheck-no-such-file.json")
    if case["file"] == "directory":
        return str(scratch)
    raise ValueError(f"Unknown file case '{case['file']}'.")


def pointer_tokens(pointer: str) -> list[str]:
    if pointer == "":
        return []
    return [token.replace("~1", "/").replace("~0", "~") for token in pointer[1:].split("/")]


def set_at_pointer(x: Any, tokens: list[str], value: Any) -> Any:
    if not tokens:
        return value
    index: Any = int(tokens[0]) if isinstance(x, list) else tokens[0]
    x[index] = set_at_pointer(x[index], tokens[1:], value)
    return x


def substitute(x: Any, substitution: dict[str, Any]) -> Any:
    pointer = substitution["pointer"]
    if "double" in substitution:
        replacement: Any = bits_double(substitution["double"])
    elif "wrap" in substitution:
        replacement = json_pointer_get(x, pointer)
        for _ in range(substitution["wrap"]):
            replacement = [replacement]
    elif "python_string" in substitution:
        replacement = "".join(chr(point) for point in substitution["python_string"])
    elif "python_int" in substitution:
        replacement = int(substitution["python_int"])
    else:
        raise ValueError("Substitution not available in Python.")
    return set_at_pointer(x, pointer_tokens(pointer), replacement)


def writer_value(case: dict[str, Any]) -> Any:
    if "double" in case:
        value = bits_double(case["double"])
    else:
        value = read_json_strict(case["json"].encode("utf-8"), "plain")
    for substitution in case.get("substitutions", []):
        value = substitute(value, substitution)
    return value


def run_json(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    modes = [mode for mode in MODES if mode in case["expected"]]
    if "json" in case or "double" in case:
        return {
            mode: outcome_of(lambda mode=mode: canonical(writer_value(case), mode))
            for mode in modes
        }
    source = reader_source(case, context["scratch"])
    outcomes = {}
    for mode in modes:

        def read(mode: str = mode) -> dict[str, Any]:
            value = read_json_strict(source, mode)
            outcome = canonical_of_value_read(value, mode)
            if "bits" in case["expected"][mode]:
                outcome["bits"] = double_bits(value)
            return outcome

        outcomes[mode] = outcome_of(read)
    return outcomes


def run_decimal(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        return {"decimal": decimal_string(bits_double(case["double"]), case["digits"])}

    return {"value": outcome_of(compute)}


def run_normalisation(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        return {
            "normalisable": is_normalisable(case["string"]),
            "form": comparison_form(case["string"]),
        }

    return {"value": outcome_of(compute)}


def run_order(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        if "first" in case:
            return {"order": compare_identifiers(case["first"], case["second"])}
        return {"sorted": list(sort_identifiers(case["strings"]))}

    return {"value": outcome_of(compute)}


# Cases of hash/ and hmac/.


def message_bytes(case: dict[str, Any]) -> bytes:
    if "message_hex" in case:
        return bytes.fromhex(case["message_hex"])
    return case["message"].encode("utf-8")


def run_sha256(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if "input_hex" in case:
        data = bytes.fromhex(case["input_hex"])
    else:
        data = case["input"].encode("utf-8")
    data *= case.get("repeat", 1)
    path = context["scratch"] / "sha256-input"

    def from_file() -> dict[str, Any]:
        path.write_bytes(data)
        return {"sha256": hash_file(str(path))}

    return {
        "memory": outcome_of(lambda: {"sha256": hash_bytes(data)}),
        "file": outcome_of(from_file),
    }


def run_section(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        document = read_json_strict(case["input"].encode("utf-8"), "hashable")
        return canonical(json_pointer_get(document, case["pointer"]), "hashable")

    return {"value": outcome_of(compute)}


def run_hmac(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        digest = hmac_sha256(bytes.fromhex(case["key_hex"]), message_bytes(case))
        if "truncate" in case:
            digest = digest[: 2 * case["truncate"]]
        return {"digest": digest}

    return {"value": outcome_of(compute)}


def run_commitment(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    def compute() -> dict[str, Any]:
        if "covers" in case:
            return {
                "commitment": keyed_commitment(message_bytes(case), case["key"], case["covers"])
            }
        return {"key_id": commitment_key_id(case["key"])}

    return {"value": outcome_of(compute)}


# Cases of declarations/ and yaml/.


def run_declaration(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    path = context["directory"] / case["path"]

    def compute() -> dict[str, Any]:
        value = validate_declaration(str(path), minimal=case.get("minimal", False))
        return canonical_of_value_read(value, "hashable")

    return {"value": outcome_of(compute)}


# Cases of tables/.


def table_path(case: dict[str, Any], context: dict[str, Any]) -> str:
    if "path" in case:
        return str(context["directory"] / case["path"])
    if case["file"] == "missing":
        return str(context["scratch"] / "mixedcheck-no-such-file.csv")
    if case["file"] == "directory":
        return str(context["scratch"])
    raise ValueError(f"Unknown file case '{case['file']}'.")


def real_value(value: float) -> str:
    """A double as the 16 hexadecimal digits of its bits, with negative zero
    as zero, or as 'NaN', 'Infinity' or '-Infinity'."""
    if math.isnan(value):
        return "NaN"
    if math.isinf(value):
        return "Infinity" if value > 0 else "-Infinity"
    return double_bits(value + 0.0)


def real_values(values: Any) -> list[str]:
    return [real_value(float(value)) for value in values]


def column_value(value: Any) -> Any:
    """A value of a column as the table corpus writes it, by its type: None
    as null, strings and booleans as themselves, an int as an integer and a
    float as its bits (real_value())."""
    if value is None or isinstance(value, bool | int | str):
        return value
    if isinstance(value, float):
        return real_value(value)
    raise UnexpectedOutcome(f"a column holds a value of the type {type(value).__name__}")


def table_columns(frame: Any) -> list[dict[str, Any]]:
    """The columns of a DataFrame that read_table() returned, in order, each
    with its name, its type and its values. Every column must have dtype
    object, and the keys of attrs['types'] must be the column names."""
    names = list(frame.columns)
    types = frame.attrs.get("types")
    if not isinstance(types, dict) or list(types) != names:
        raise UnexpectedOutcome("attrs['types'] does not name the columns in order")
    columns = []
    for position, name in enumerate(names):
        series = frame.iloc[:, position]
        if series.dtype.kind != "O":
            raise UnexpectedOutcome(f"the column '{name}' has the dtype {series.dtype}")
        values = [column_value(value) for value in series.tolist()]
        columns.append({"name": name, "type": types[name], "values": values})
    return columns


def rows_from_0(rows: Any) -> list[int]:
    """Row positions, which Python counts from 0 as the corpora do."""
    return [int(row) for row in rows]


def run_table(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    path = table_path(case, context)
    read: list[Any] = []

    def columns() -> dict[str, Any]:
        read.append(read_table(path, case.get("declaration")))
        return {"columns": table_columns(read[0])}

    outcomes = {"value": outcome_of(columns)}
    if "formula" in case:

        def samples() -> dict[str, Any]:
            if not read:
                raise UnexpectedOutcome("the table was not read")
            ir = formula_ir(case["formula"], case.get("declaration"), read[0])
            samples = design_samples(ir, read[0])
            return {
                "design_sample": rows_from_0(samples["design_sample"]),
                "analysis_sample": rows_from_0(samples["analysis_sample"]),
            }

        outcomes["samples"] = outcome_of(samples)
    return outcomes


# Cases of formulas/.


SPECIAL_VALUES = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}


def formula_data_frame(data: dict[str, list[Any]]) -> Any:
    """The DataFrame of a formula case, as read_table() returns a table: one
    column of dtype object for each member of its data, with None for null
    and the strings 'NaN', 'Infinity' and '-Infinity' of a column of numbers as
    the special values."""
    import pandas

    columns = {}
    for name, values in data.items():
        numbers = any(isinstance(v, int | float) and not isinstance(v, bool) for v in values)
        if numbers:
            values = [SPECIAL_VALUES[v] if isinstance(v, str) else v for v in values]
        columns[name] = pandas.Series(values, dtype=object)
    return pandas.DataFrame(columns)


def matrices_outcome(m: dict[str, Any]) -> dict[str, Any]:
    """The design matrices as the formula corpus writes them, with the number
    of entries that Z stores."""
    from scipy import sparse

    z = m["z"]
    if not isinstance(z, sparse.csc_array):
        raise UnexpectedOutcome("Z is not a scipy.sparse.csc_array")
    described = m["z_columns"]
    return {
        "rows": rows_from_0(m["design_sample"]),
        "x": [real_values(row) for row in m["x"].tolist()],
        "x_columns": list(m["x_columns"]),
        "x_dropped": list(m["x_dropped"]),
        "z": [real_values(row) for row in z.toarray().tolist()],
        "z_columns": [
            {"term": int(term), "level": level, "column": column}
            for term, level, column in zip(
                described["term"].tolist(),
                described["level"].tolist(),
                described["column"].tolist(),
                strict=True,
            )
        ],
        "z_stored": int(z.nnz),
    }


def run_formula(case: dict[str, Any], context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    data = formula_data_frame(case["data"]) if "data" in case else None
    built: list[Any] = []

    def ir() -> dict[str, Any]:
        built.append(
            formula_ir(
                case["formula"],
                case.get("declaration"),
                data,
                case.get("coding"),
                case.get("weights"),
                case.get("sample_columns"),
            )
        )
        return canonical(built[0], "hashable")

    outcomes = {"ir": outcome_of(ir)}
    expected = case["expected"]
    # The design matrices, or the issue that they report beside the IR.
    if "matrices" not in expected and not ("ir" in expected and "issue" in expected):
        return outcomes
    matrices: list[dict[str, Any]] = []

    def design() -> dict[str, Any]:
        if not built:
            raise UnexpectedOutcome("formula_ir() gave no IR")
        matrices.append(design_matrices(built[0], data))
        return matrices_outcome(matrices[0])

    def vectors() -> dict[str, Any]:
        if not matrices:
            raise UnexpectedOutcome("design_matrices() gave no matrices")
        names = ("response", "trials", "offset", "weights")
        reals = {
            name: None if matrices[0][name] is None else real_values(matrices[0][name])
            for name in names
        }
        return {"reals": reals}

    outcomes["matrices"] = outcome_of(design)
    if "matrices" in expected:
        outcomes["vectors"] = outcome_of(vectors)
    return outcomes


RUNNERS: dict[str, Callable[[dict[str, Any], dict[str, Any]], dict[str, dict[str, Any]]]] = {
    "json": run_json,
    "decimal": run_decimal,
    "normalisation": run_normalisation,
    "order": run_order,
    "sha256": run_sha256,
    "section": run_section,
    "hmac": run_hmac,
    "commitment": run_commitment,
    "declaration": run_declaration,
    "table": run_table,
    "formula": run_formula,
}


def run_artefacts(artefacts: list[str]) -> list[dict[str, Any]]:
    """Read each vendored file of spec/ installed with the package in the data
    profile, and the registry and the versions as the package loads them."""
    records = []
    spec = files("mixedcheck") / "_spec"
    for name in artefacts:

        def read(name: str = name) -> dict[str, Any]:
            entry = spec.joinpath(*name.split("/"))
            return canonical_of_value_read(read_json_strict(entry.read_bytes(), "data"), "data")

        records.append(
            {"file": "artefacts", "id": name, "part": "data", "outcome": outcome_of(read)}
        )
    records.append(
        {
            "file": "artefacts",
            "id": "read_registry()",
            "part": "hashable",
            "outcome": outcome_of(lambda: canonical(read_registry(), "hashable")),
        }
    )
    records.append(
        {
            "file": "artefacts",
            "id": "spec_versions()",
            "part": "value",
            "outcome": outcome_of(lambda: {"value": spec_versions()}),
        }
    )
    return records


def yaml_version() -> str | None:
    try:
        import yaml
    except ImportError:
        return None
    return str(yaml.__version__)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: python run_python.py PLAN OUTPUT", file=sys.stderr)
        return 2
    plan = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    corpus = Path(plan["corpus"])
    header = {
        "run": LANGUAGE,
        "language": LANGUAGE,
        "package": mixedcheck.__version__,
        "interpreter": f"Python {platform.python_version()}",
        "yaml": yaml_version(),
    }
    records: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="mixedcheck-parity-") as scratch:
        for corpus_file in plan["corpora"]:
            name = corpus_file["file"]
            directory = corpus / name.split("/")[0]
            context = {"scratch": Path(scratch), "directory": directory}
            try:
                cases = read_json_strict(str(corpus / name), "data")["cases"]
            except Exception as err:
                error = {"error": f"The corpus file cannot be read: {type(err).__name__}: {err}"}
                records.append({"file": name, "id": None, "part": None, "outcome": encode(error)})
                continue
            runner = RUNNERS[corpus_file["kind"]]
            for case in cases:
                if LANGUAGE not in case.get("languages", [LANGUAGE]):
                    continue
                for part, outcome in runner(case, context).items():
                    records.append(
                        {"file": name, "id": case["id"], "part": part, "outcome": outcome}
                    )
        records.extend(run_artefacts(plan["artefacts"]))
    with open(argv[2], "w", encoding="ascii", newline="\n") as out:
        out.write(json.dumps(header, sort_keys=True) + "\n")
        for record in records:
            out.write(json.dumps(record, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
