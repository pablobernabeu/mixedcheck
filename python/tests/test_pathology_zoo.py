"""The accessor of the pathology zoo, pathology_zoo(), on the installed copy:
the listing and its column types, each error, the elements of a fixture and
the types of its data, the comparison with MANIFEST.json and the parsing and
locale hazards that Z18, Z19 and Z20 plant."""

from __future__ import annotations

import locale
import shutil
from collections.abc import Iterator
from importlib.resources import as_file, files
from pathlib import Path
from typing import Any

import pandas as pd
import pytest
from zoo_helpers import zoo_run

from mixedcheck import canonical_bytes, pathology_zoo, read_table, validate_declaration
from mixedcheck._zoo import zoo_fixture

INSTALLED = files("mixedcheck") / "_fixtures"
COLUMNS = ["id", "name", "title", "role", "matched", "tier", "rows", "domain", "deferred"]


@pytest.fixture(autouse=True)
def audit_time(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MIXEDCHECK_TIME", "0")


def data_file(directory: str) -> bytes:
    return (INSTALLED / "zoo" / directory / "data.csv").read_bytes()


def test_the_listing_has_the_columns_and_types_of_every_package() -> None:
    zoo = pathology_zoo()
    assert list(zoo.columns) == COLUMNS
    assert isinstance(zoo.index, pd.RangeIndex)
    for name in COLUMNS:
        dtype = {"rows": "int64", "deferred": "bool"}.get(name, "object")
        assert str(zoo[name].dtype) == dtype, name
        if dtype == "object":
            assert all(isinstance(value, str) for value in zoo[name]), name
    assert len(zoo) == 60
    assert list(zoo["id"]) == sorted(zoo["id"])
    first = zoo[zoo["id"] == "Z01"].iloc[0].to_dict()
    assert first == {
        "id": "Z01",
        "name": "reused-class-labels",
        "title": "Reused class labels across schools",
        "role": "fixture",
        "matched": "Z01N",
        "tier": "T0",
        "rows": 240,
        "domain": "education",
        "deferred": False,
    }
    assert set(zoo["matched"]) <= set(zoo["id"])


def test_a_fixture_has_its_elements_in_order_read_with_its_declaration() -> None:
    fixture = pathology_zoo("Z01")
    assert list(fixture) == [
        "id",
        "name",
        "title",
        "role",
        "matched",
        "tier",
        "data",
        "data_file",
        "declaration",
        "formula",
        "arguments",
        "expected",
    ]
    assert [fixture[name] for name in ("id", "name", "role", "matched", "tier")] == [
        "Z01",
        "reused-class-labels",
        "fixture",
        "Z01N",
        "T0",
    ]
    assert fixture["formula"] == "y ~ 1 + (1 | school) + (1 | class)"
    assert fixture["arguments"] == {"outcome_access": "T0"}
    assert fixture["expected"]["id"] == "Z01"
    assert len(fixture["data"]) == 240
    with as_file(INSTALLED / "zoo" / "Z01-reused-class-labels" / "declaration.json") as path:
        assert fixture["declaration"] == validate_declaration(path)
    with as_file(INSTALLED / "zoo" / "Z01-reused-class-labels" / "data.csv") as path:
        assert Path(fixture["data_file"]).resolve() == Path(path).resolve()
    assert read_table(fixture["data_file"], fixture["declaration"]).equals(fixture["data"])


def test_the_data_of_every_fixture_have_the_types_of_its_declared_fields() -> None:
    zoo = pathology_zoo()
    kinds: dict[str, tuple[type, ...]] = {
        "string": (str,),
        "date": (str,),
        "datetime": (str,),
        "integer": (int,),
        "number": (int, float),
        "boolean": (bool,),
    }
    arguments = {
        "T0": ["outcome_access"],
        "T1": ["outcome_access", "reason"],
        "T2": ["outcome_access", "reason", "exploratory"],
    }
    for fixture_id, rows in zip(zoo["id"], zoo["rows"], strict=True):
        fixture = pathology_zoo(fixture_id)
        data = fixture["data"]
        fields = fixture["declaration"]["table"]["fields"]
        assert list(data.columns) == [field["name"] for field in fields], fixture_id
        assert len(data) == rows, fixture_id
        for field in fields:
            column = data[field["name"]]
            assert column.dtype == object, (fixture_id, field["name"])
            allowed = kinds[field.get("type", "string")]
            for value in column:
                if value is None:
                    continue
                assert isinstance(value, allowed), (fixture_id, field["name"], value)
                if field.get("type") in ("integer", "number"):
                    assert not isinstance(value, bool), (fixture_id, field["name"])
        assert list(fixture["arguments"]) == arguments[fixture["tier"]], fixture_id


@pytest.mark.parametrize("fixture", [1, ["Z01"], ("Z01",), b"Z01", True])
def test_an_argument_that_is_not_one_identifier_is_an_error(fixture: Any) -> None:
    with pytest.raises(TypeError) as caught:
        pathology_zoo(fixture)
    assert str(caught.value) == "'fixture' must be None or one identifier, such as 'Z01'."


@pytest.mark.parametrize("fixture", ["Z99", "z01", ""])
def test_an_identifier_that_names_no_fixture_is_an_error(fixture: str) -> None:
    with pytest.raises(ValueError) as caught:
        pathology_zoo(fixture)
    assert str(caught.value) == (
        f"'{fixture}' is not an identifier of the pathology zoo. pathology_zoo() lists them."
    )


@pytest.fixture
def copy(tmp_path: Path) -> Iterator[Path]:
    with as_file(INSTALLED) as source:
        shutil.copytree(source, tmp_path / "fixtures")
    yield tmp_path / "fixtures"


def test_an_installed_file_that_is_missing_or_differs_from_the_manifest(copy: Path) -> None:
    assert zoo_fixture("Z01", copy)["id"] == "Z01"
    with (copy / "zoo" / "Z01-reused-class-labels" / "data.csv").open("ab") as file:
        file.write(b"S01,1,P241,0.00\n")
    with pytest.raises(RuntimeError) as caught:
        zoo_fixture("Z01", copy)
    assert str(caught.value) == (
        "'_fixtures/zoo/Z01-reused-class-labels/data.csv' differs from the MANIFEST.json "
        "installed with the package."
    )
    assert zoo_fixture("Z01N", copy)["id"] == "Z01N"
    (copy / "zoo" / "Z01N-unique-class-labels" / "formula.txt").unlink()
    with pytest.raises(RuntimeError) as caught:
        zoo_fixture("Z01N", copy)
    assert str(caught.value) == (
        "'_fixtures/zoo/Z01N-unique-class-labels/formula.txt' is missing from the "
        "installed package."
    )
    with (copy / "zoo" / "index.json").open("ab") as file:
        file.write(b"\n")
    with pytest.raises(RuntimeError) as caught:
        zoo_fixture(None, copy)
    assert str(caught.value) == (
        "'_fixtures/zoo/index.json' differs from the MANIFEST.json installed with the package."
    )
    (copy / "MANIFEST.json").unlink()
    with pytest.raises(RuntimeError) as caught:
        zoo_fixture(None, copy)
    assert str(caught.value) == "'_fixtures/MANIFEST.json' is missing from the installed package."


def test_z18_keeps_the_labels_that_the_csv_quotes() -> None:
    data = pathology_zoo("Z18")["data"]
    labels = set(data["class"]) | set(data["school"])
    assert {"1,2", '"3"', "1:2", "A:1"} <= labels
    text = data_file("Z18-composite-id-collision")
    assert b'"1,2"' in text
    assert b'"""3"""' in text


def test_z19_reads_its_cr_lf_records_and_its_labelled_sentinels_as_missing() -> None:
    data = pathology_zoo("Z19")["data"]
    text = data_file("Z19-sentinel-codes")
    assert text.count(b"\n") == 61
    assert text.count(b"\r\n") == 61
    missing = [pupil for pupil, pre in zip(data["pupil"], data["pre"], strict=True) if pre is None]
    assert missing == ["P02", "P09", "P13", "P18", "P24", "P37", "P46"]
    assert -99 not in set(data["pre"])
    assert sorted(set(data["group"])) == [1, 2]


def test_z20_keeps_its_decomposed_labels() -> None:
    subjects = set(pathology_zoo("Z20")["data"]["Subject"])
    assert {"José", "Zoë", "José", " s1"} <= subjects


def test_z20_gives_the_same_findings_whatever_the_collation() -> None:
    fixture = pathology_zoo("Z20")
    old = locale.setlocale(locale.LC_COLLATE)

    def run() -> bytes:
        return canonical_bytes(zoo_run(fixture, "internal")["value"].document["findings"])

    try:
        locale.setlocale(locale.LC_COLLATE, "C")
        in_c = run()
        try:
            locale.setlocale(locale.LC_COLLATE, "en_US.UTF-8")
        except locale.Error:
            pytest.skip("the system has no locale en_US.UTF-8")
        assert run() == in_c
    finally:
        locale.setlocale(locale.LC_COLLATE, old)
