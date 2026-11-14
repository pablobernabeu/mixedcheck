"""Runs the inputs of the differential test with the installed Python package
(parity/README.md, Differential test).

Usage: python run_python.py INPUTS OUTPUT SHARD SHARDS [ONLY]

INPUTS is the directory that inputs.R wrote. The runner takes the files of
inputs whose position in index.json, counted from 0, leaves the remainder
SHARD when divided by SHARDS, and with ONLY, a file with one identifier on
each line, only the inputs it names. An input of the pathology zoo is read
with pathology_zoo(), which gives its data, formula, declaration and the
arguments of its run. It runs audit() on each input in
internal and in shareable mode, at the input's k, with the commitment key
00 01 02 ... 1F and MIXEDCHECK_TIME set to 0, and writes to OUTPUT, compressed
with gzip, a header and one JSON object per line for each input and mode, as
run_r.R does.

Each column of an input becomes a column of the pandas type that holds its R
type: float64, or Float64 when it has NA, int64, or Int64 with NA, bool, or
boolean with NA, a Categorical with the levels of a factor in their order and
pandas' own type for a list of strings, so that a NaN stays a value and NA
stays missing, as in R.
"""

from __future__ import annotations

import gzip
import json
import math
import os
import platform
import sys
import time
import warnings
from collections.abc import Callable
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

import mixedcheck
from mixedcheck import MixedcheckError, MixedcheckWarning, canonical_bytes, read_json_strict
from mixedcheck._registry import registry_document, registry_hash

MODES = ("internal", "shareable")
KEY = bytes(range(32)).hex()
SPECIAL = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf, "-0": -0.0}


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


def column_series(column: dict[str, Any]) -> pd.Series:
    """A column of an input as a Series of the pandas type of its R type."""
    kind = column["type"]
    values = column["values"]
    mask = np.array([value is None for value in values], dtype=bool)
    if kind == "double":
        doubles = np.array(
            [
                0.0 if value is None else SPECIAL[value] if isinstance(value, str) else float(value)
                for value in values
            ],
            dtype=np.float64,
        )
        if mask.any():
            return pd.Series(pd.arrays.FloatingArray(doubles, mask))
        return pd.Series(doubles)
    if kind == "integer":
        integers = np.array(
            [0 if value is None else int(value) for value in values], dtype=np.int64
        )
        if mask.any():
            return pd.Series(pd.arrays.IntegerArray(integers, mask))
        return pd.Series(integers)
    if kind == "logical":
        booleans = np.array([bool(value) for value in values], dtype=bool)
        if mask.any():
            return pd.Series(pd.arrays.BooleanArray(booleans, mask))
        return pd.Series(booleans)
    if kind == "string":
        return pd.Series(values)
    if kind == "factor":
        return pd.Series(pd.Categorical(values, categories=column["levels"]))
    raise ValueError(f"Unknown column type '{kind}'.")


def input_frame(columns: list[dict[str, Any]]) -> pd.DataFrame:
    """The data frame of an input, one column for each of its columns, in
    order."""
    return pd.DataFrame({column["name"]: column_series(column) for column in columns})


def set_k(k: int) -> None:
    """Set the minimum count of the registry that the session read, which the
    filter and the document's /privacy read, as the disclosure-attack harness
    does in R."""
    registry_document()["privacy"]["min_count"] = k


def run_input(case: dict[str, Any]) -> list[dict[str, Any]]:
    set_k(case["k"])
    if "fixture" in case:
        fixture = mixedcheck.pathology_zoo(case["fixture"])
        data = fixture["data"]
        formula = fixture["formula"]
        arguments = {"declaration": fixture["declaration"], **fixture["arguments"]}
    else:
        data = input_frame(case["data"])
        formula = case["formula"]
        arguments = dict(case["arguments"])
    records = []
    for mode in MODES:

        def compute(mode: str = mode) -> dict[str, Any]:
            results = mixedcheck.audit(data, formula, privacy=mode, key=KEY, **arguments)
            document = {
                key: value
                for key, value in results.document.items()
                if key not in ("created", "software")
            }
            document["versions"] = {
                key: value for key, value in document["versions"].items() if key != "package"
            }
            return {
                "document": canonical_bytes(document, "data"),
                "sidecar": canonical_bytes(results.sidecar, "data"),
            }

        started = time.perf_counter()
        outcome = outcome_of(compute)
        milliseconds = round(1000 * (time.perf_counter() - started))
        records.append(
            {"id": case["id"], "mode": mode, "milliseconds": milliseconds, "outcome": outcome}
        )
    return records


def main(argv: list[str]) -> int:
    if len(argv) not in (5, 6):
        print("Usage: python run_python.py INPUTS OUTPUT SHARD SHARDS [ONLY]", file=sys.stderr)
        return 2
    inputs = Path(argv[1])
    shard, shards = int(argv[3]), int(argv[4])
    only = set(Path(argv[5]).read_text(encoding="utf-8").split()) if len(argv) == 6 else None
    os.environ["MIXEDCHECK_TIME"] = "0"
    index = read_json_strict(str(inputs / "index.json"), "data")
    header = {
        "run": "Python",
        "language": "Python",
        "package": mixedcheck.__version__,
        "registry_hash": registry_hash(),
        "interpreter": f"Python {platform.python_version()}",
        "pandas": pd.__version__,
        "numpy": np.__version__,
    }
    with gzip.open(argv[2], "wt", encoding="ascii", newline="\n") as out:
        out.write(json.dumps(header, sort_keys=True) + "\n")
        for position, chunk in enumerate(index["chunks"]):
            if position % shards != shard:
                continue
            if only is not None and not only.intersection(chunk["ids"]):
                continue
            for case in read_json_strict(str(inputs / chunk["file"]), "data")["inputs"]:
                if only is not None and case["id"] not in only:
                    continue
                for record in run_input(case):
                    out.write(json.dumps(record, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
