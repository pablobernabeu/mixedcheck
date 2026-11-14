"""The results object, its printing and write_results() (documents.md, Results
document, Writing and Internal sidecar), with documents of the results
corpus."""

from __future__ import annotations

import copy
import os
from pathlib import Path
from typing import Any

import pytest
from audit_helpers import AUDIT_KEY
from corpus_helpers import corpus_directory

from mixedcheck import (
    MixedcheckError,
    Results,
    canonical_bytes,
    commitment_key_id,
    hash_bytes,
    hash_file,
    read_json_strict,
    write_results,
)
from mixedcheck._results import commitment_key_pointer, finding_line


def results_document(name: str) -> dict[str, Any]:
    document = read_json_strict(corpus_directory("results") / name, "data")
    assert isinstance(document, dict)
    return document


def example_sidecar() -> dict[str, Any]:
    return {
        "sidecar_version": "0.1.0",
        "keys": [
            {
                "created": "2026-11-08T09:05:30Z",
                "key": AUDIT_KEY,
                "key_id": commitment_key_id(AUDIT_KEY),
            }
        ],
        "pseudonyms": [],
    }


def example_results(name: str = "valid/001.json") -> Results:
    return Results(results_document(name), example_sidecar())


def errors_of(f: Any) -> list[dict[str, Any]]:
    try:
        f()
    except MixedcheckError as err:
        return err.issues
    return []


def test_printing_shows_the_banner_of_the_mode_and_one_line_for_each_finding() -> None:
    shareable = example_results()
    assert str(shareable).split("\n") == [
        "Shareable output: the privacy filter has reduced the risk of disclosure, "
        "but this report is not anonymous data.",
        "keys.duplicates: consistent. Every row has its own value of the observation key "
        "'school', 'class', 'pupil' and 'wave'.",
        "outcome.constant_clusters (factor 'school'): consistent. The outcome varies within "
        "every level of 'school' that has two or more rows.",
        "structure.label_incidence (first 'class', second 'school'): consistent. In the design "
        "sample, the relation of 'class' and 'school' from the labels is: crossed.",
    ]
    assert repr(shareable) == str(shareable)
    internal = example_results("valid/005.json")
    lines = str(internal).split("\n")
    assert lines[:2] == [
        "INTERNAL: this report holds values that the privacy filter has not checked, "
        "such as small counts and labels. Do not share it.",
        "keys.duplicates: not available (declaration_missing: /observation/key).",
    ]
    assert len(lines) == 4
    internal.document["findings"] = []
    assert str(internal).split("\n")[1] == "No findings."
    # A document whose mode is not 'shareable' prints the internal banner.
    internal.document["privacy"]["mode"] = "other"
    assert str(internal).startswith("INTERNAL:")
    # A scope value is shown after display escaping.
    finding = {
        "check": "structure.cluster_sizes",
        "scope": {"factor": "a\tb"},
        "status": {
            "availability": {"value": "not_available", "reason": "planned", "version": "1.1"}
        },
    }
    assert finding_line(finding) == (
        "structure.cluster_sizes (factor 'a\\u0009b'): not available (planned: 1.1)."
    )


def test_write_results_writes_the_canonical_bytes_and_the_sidecar_with_the_hash(
    tmp_path: Path,
) -> None:
    results = example_results()
    path = tmp_path / "audit.json"
    sidecar = tmp_path / "audit.internal.json"
    digest = write_results(results, path, sidecar)
    assert path.read_bytes() == canonical_bytes(results.document, "data")
    assert digest == hash_file(path)
    # With the registry hash of documents.md, the example there has 6,335
    # canonical bytes and the results file hash that its sidecar records.
    example = copy.deepcopy(results.document)
    example["inputs"]["registry_hash"] = (
        "sha256:872491a30d60d598962de6e7b834ab76b2aa65fbab102c6ebaaae6acdc238822"
    )
    example_bytes = canonical_bytes(example, "data")
    assert len(example_bytes) == 6335
    assert hash_bytes(example_bytes) == (
        "sha256:2be42c9598e82bd70f5c3fecacbdc2123831131b674224c2c9e86388ed21af8b"
    )
    written = read_json_strict(sidecar, "data")
    assert written["results_hash"] == digest
    assert {name: written[name] for name in results.sidecar} == results.sidecar
    assert "results_hash" not in results.sidecar
    assert sidecar.read_bytes() == canonical_bytes(written, "data")
    internal = example_results("valid/002.json")
    path = tmp_path / "audit.internal.json"
    sidecar = tmp_path / "keys.internal.json"
    assert write_results(internal, str(path), str(sidecar)) == hash_file(path)


def test_write_results_refuses_file_names_that_do_not_match_the_document(
    tmp_path: Path,
) -> None:
    shareable = example_results()
    internal = example_results("valid/002.json")

    def message(file: str, rule: str) -> str:
        return f"The {file} must be written to a file whose name {rule} '.internal.json'."

    assert errors_of(
        lambda: write_results(
            shareable, tmp_path / "audit.internal.json", tmp_path / "k.internal.json"
        )
    ) == [{"code": "E7010", "message": message("shareable results document", "does not end in")}]
    assert errors_of(
        lambda: write_results(internal, tmp_path / "audit.json", tmp_path / "k.internal.json")
    ) == [{"code": "E7010", "message": message("internal results document", "ends in")}]
    for results, name in ((shareable, "audit.json"), (internal, "audit.internal.json")):
        assert errors_of(
            lambda results=results, name=name: write_results(
                results, tmp_path / name, tmp_path / "keys.json"
            )
        ) == [{"code": "E7010", "message": message("internal sidecar", "ends in")}]
    # Only the name counts, and the suffix is compared exactly.
    issues = errors_of(
        lambda: write_results(
            internal, tmp_path / "audit.INTERNAL.JSON", tmp_path / "k.internal.json"
        )
    )
    assert issues[0]["code"] == "E7010"
    (tmp_path / "x.internal.json").mkdir()
    write_results(
        shareable, tmp_path / "x.internal.json" / "audit.json", tmp_path / "keys.internal.json"
    )
    assert sorted(os.listdir(tmp_path)) == ["keys.internal.json", "x.internal.json"]


def test_write_results_refuses_a_commitment_key_in_a_shareable_document(tmp_path: Path) -> None:
    results = example_results()
    results.document["inputs"]["data"]["analysis_table"] = example_sidecar()["keys"][0]
    assert errors_of(
        lambda: write_results(results, tmp_path / "a.json", tmp_path / "a.internal.json")
    ) == [
        {
            "code": "E1315",
            "message": "The commitment key at /inputs/data/analysis_table cannot be written to a "
            "shareable file.",
            "pointer": "/inputs/data/analysis_table",
        }
    ]
    assert os.listdir(tmp_path) == []
    nested = [[1], {"b": {"created": 1, "key": 2, "key_id": 3}}]
    assert commitment_key_pointer(nested) == "/1/b"
    assert commitment_key_pointer({"created": 1, "key": 2}) is None
    # Members are visited in the order of the canonical serialisation.
    keyed = {"created": 1, "key": 2, "key_id": 3}
    assert commitment_key_pointer({"b": keyed, "a~/": [keyed]}) == "/a~0~1/0"


def test_write_results_gives_ordinary_errors_for_arguments_of_the_wrong_type(
    tmp_path: Path,
) -> None:
    results = example_results()
    path = tmp_path / "audit.json"
    sidecar = tmp_path / "audit.internal.json"
    with pytest.raises(TypeError):
        write_results(results.document, path, sidecar)  # type: ignore[arg-type]
    with pytest.raises(TypeError):
        write_results(results, "", sidecar)
    with pytest.raises(TypeError):
        write_results(results, path, [sidecar, sidecar])  # type: ignore[arg-type]
    with pytest.raises(TypeError):
        write_results(results, path, 1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="other than 'path'"):
        write_results(
            example_results("valid/002.json"),
            sidecar,
            os.path.join(str(tmp_path), ".", sidecar.name),
        )
    # A sidecar in a missing directory: nothing is written, since the document
    # would commit to a key that no file holds.
    with pytest.raises(ValueError, match="does not exist"):
        write_results(results, path, tmp_path / "missing" / "audit.internal.json")
    assert os.listdir(tmp_path) == []
    # A sidecar that cannot be written, here because a directory has its name,
    # takes the document with it.
    sidecar.mkdir()
    with pytest.raises(OSError):
        write_results(results, path, sidecar)
    assert not path.exists()
