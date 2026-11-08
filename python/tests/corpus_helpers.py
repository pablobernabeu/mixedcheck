"""Helpers that run the cases of the conformance corpora installed with the
package (fixtures/conformance/, described in each directory's README.md)."""

from __future__ import annotations

import struct
from collections.abc import Callable
from functools import partial
from importlib.resources import as_file, files
from pathlib import Path
from typing import Any

import pytest

import mixedcheck
from mixedcheck import MixedcheckError, canonical_bytes, hash_bytes, read_json_strict
from mixedcheck._hash import json_pointer_get

PROFILES = ("plain", "data", "hashable")


def corpus_directory(directory: str):
    """The installed directory of a corpus."""
    return files("mixedcheck") / "_fixtures" / "conformance" / directory


def corpus_cases(directory: str, file: str) -> list[dict[str, Any]]:
    """The cases of a corpus file that Python runs. Cases that only another
    language can hold are left to it."""
    entry = corpus_directory(directory) / file
    cases = read_json_strict(entry.read_bytes(), "data")["cases"]
    return [case for case in cases if "Python" in case.get("languages", ["Python"])]


def parametrize_cases(directory: str, *names: str) -> pytest.MarkDecorator:
    """Parametrize a test over every case of the named files of a corpus."""
    cases = [case for name in names for case in corpus_cases(directory, name)]
    return pytest.mark.parametrize("case", cases, ids=[case["id"] for case in cases])


def bits_double(bits: str) -> float:
    """The double whose bits are given as 16 hexadecimal digits."""
    return struct.unpack(">d", bytes.fromhex(bits))[0]


def double_bits(value: float) -> str:
    """The 16 hexadecimal digits of the bits of a double."""
    return struct.pack(">d", float(value)).hex()


def capture(f: Callable[[], Any]) -> dict[str, Any]:
    """Call f and return {'value': ...}, or {'issues': ...} for a MixedcheckError."""
    try:
        return {"value": f()}
    except MixedcheckError as err:
        return {"issues": err.issues}


def special_path(kind: str, tmp_path: Path) -> str:
    """A path that does not exist, or a path to a directory."""
    if kind == "missing":
        return str(tmp_path / "mixedcheck-no-such-file.json")
    if kind == "directory":
        return str(tmp_path)
    raise ValueError(f"Unknown file case '{kind}'.")


def expect_issue(result: dict[str, Any], expected: dict[str, Any], label: str) -> None:
    """Compare the one issue reported with the expected issue exactly."""
    assert "issues" in result, f"{label}: expected {expected['code']}, got no issue."
    assert len(result["issues"]) == 1, label
    assert result["issues"][0] == expected, label


def expect_issues(result: dict[str, Any], expected: list[dict[str, Any]], label: str) -> None:
    """Compare a list of issues with the expected list exactly: the codes, the
    messages and the locations, in order."""
    assert "issues" in result, f"{label}: expected {expected[0]['code']}, got no issue."
    assert result["issues"] == expected, label


def expect_canonical(
    result: dict[str, Any], expected: dict[str, Any], profile: str, label: str
) -> None:
    """Write the value read in a profile and compare its bytes and hash."""
    assert "value" in result, f"{label}: expected canonical bytes, got {result['issues']}."
    data = canonical_bytes(result["value"], profile)
    assert data == expected["canonical"].encode("utf-8"), label
    assert hash_bytes(data) == expected["sha256"], label
    if "bits" in expected:
        assert double_bits(result["value"]) == expected["bits"], label


def run_reader_case(case: dict[str, Any], tmp_path: Path) -> None:
    """Read the input of a reader case in each mode and compare the result."""
    for profile in PROFILES:
        if profile not in case["expected"]:
            continue
        expected = case["expected"][profile]
        label = f"{case['id']} {profile}"
        if "input" in case:
            source: bytes | str = case["input"].encode("utf-8")
        elif "input_hex" in case:
            source = bytes.fromhex(case["input_hex"])
        else:
            source = special_path(case["file"], tmp_path)
        result = capture(partial(read_json_strict, source, profile))
        if "issue" in expected:
            expect_issue(result, expected["issue"], label)
        else:
            expect_canonical(result, expected, profile, label)


def _set_at_pointer(x: Any, tokens: list[str], value: Any) -> Any:
    if not tokens:
        return value
    token = tokens[0]
    index: Any = int(token) if isinstance(x, list) else token
    x[index] = _set_at_pointer(x[index], tokens[1:], value)
    return x


def _pointer_tokens(pointer: str) -> list[str]:
    if pointer == "":
        return []
    return [token.replace("~1", "/").replace("~0", "~") for token in pointer[1:].split("/")]


def _substitute(x: Any, substitution: dict[str, Any]) -> Any:
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
    return _set_at_pointer(x, _pointer_tokens(pointer), replacement)


def writer_value(case: dict[str, Any]) -> Any:
    """The value in memory of a writer case."""
    if "double" in case:
        value = bits_double(case["double"])
    else:
        value = read_json_strict(case["json"].encode("utf-8"), "plain")
    for substitution in case.get("substitutions", []):
        value = _substitute(value, substitution)
    return value


def run_writer_case(case: dict[str, Any]) -> None:
    """Write the value of a writer case in each mode and compare the result."""
    for profile in PROFILES:
        if profile not in case["expected"]:
            continue
        expected = case["expected"][profile]
        label = f"{case['id']} {profile}"
        result = capture(partial(canonical_bytes, writer_value(case), profile))
        if "issue" in expected:
            expect_issue(result, expected["issue"], label)
        else:
            assert "value" in result, f"{label}: expected canonical bytes, got {result['issues']}."
            assert result["value"] == expected["canonical"].encode("utf-8"), label
            assert hash_bytes(result["value"]) == expected["sha256"], label


def run_json_case(case: dict[str, Any], tmp_path: Path) -> None:
    """Run a reader or a writer case."""
    if "json" in case or "double" in case:
        run_writer_case(case)
    else:
        run_reader_case(case, tmp_path)


# The codes of step 1 of the YAML reader, which the reader reports whether
# PyYAML is installed or not.
BYTE_CODES = ("E1001", "E1002", "E1003", "E1201")


def run_declaration_case(directory: str, case: dict[str, Any]) -> None:
    """Run a case of the declaration or YAML corpus: a valid case gives the
    canonical bytes and the hash of the declaration as read, and an invalid
    case gives its list of issues (fixtures/conformance/declarations/README.md).

    Without PyYAML, a YAML file gives the issue of its bytes when they are
    refused and E3001 otherwise.
    """
    with as_file(corpus_directory(directory) / case["path"]) as path:
        minimal = case.get("minimal", False)
        result = capture(lambda: mixedcheck.validate_declaration(str(path), minimal=minimal))
    expected = case["expected"]
    from mixedcheck._declaration import is_yaml_path
    from mixedcheck._yaml import yaml_module, yaml_requirement

    if is_yaml_path(case["path"]) and yaml_module() is None:
        issues = expected.get("issues", [])
        if issues and issues[0]["code"] in BYTE_CODES:
            expect_issues(result, issues, case["id"])
        else:
            missing = {
                "code": "E3001",
                "message": f"Reading YAML needs the package '{yaml_requirement()}'.",
            }
            expect_issues(result, [missing], case["id"])
        return
    if "issues" in expected:
        expect_issues(result, expected["issues"], case["id"])
    else:
        expect_canonical(result, expected, "hashable", case["id"])
