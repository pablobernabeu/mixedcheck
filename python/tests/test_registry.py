"""The vendored compiled registry: loading, the checks that registry.md (The
compiled registry) gives the package tests, and the rules enforced in code on
altered copies."""

from __future__ import annotations

import copy
import hashlib
import shutil
from importlib.resources import as_file, files

import pytest

from mixedcheck import (
    MixedcheckError,
    canonical_bytes,
    read_json_strict,
    read_registry,
    spec_versions,
)
from mixedcheck._errors import finish_issues
from mixedcheck._registry import load_registry, registry_entry, registry_issues
from mixedcheck._schema import schema_issues


def entry_index(document, identifier):
    return [entry["id"] for entry in document["entries"]].index(identifier)


def codes_and_pointers(issues):
    return [f"{issue['code']} {issue.get('pointer', '')}" for issue in issues]


def test_read_registry_returns_the_vendored_registry():
    registry = read_registry()
    assert list(registry) == ["entries", "privacy", "registry_version"]
    assert registry["registry_version"] == spec_versions()["registry"]
    ids = [entry["id"] for entry in registry["entries"]]
    assert ids
    assert ids == sorted(ids)
    assert registry["privacy"]["min_count"] == 10
    again = read_registry()
    assert again == registry
    registry["privacy"]["min_count"] = 5
    assert read_registry()["privacy"]["min_count"] == 10


def test_the_vendored_registry_holds_its_canonical_bytes_and_passes_its_schema_and_rules():
    data = (files("mixedcheck") / "_spec" / "compiled" / "registry.json").read_bytes()
    registry = read_registry()
    assert canonical_bytes(registry, "hashable") == data
    assert finish_issues(schema_issues(registry, "urn:mixedcheck:schema:registry")) == []
    assert registry_issues(registry) == []


def test_registry_entry_finds_an_entry_by_identifier_and_reports_e4001_otherwise():
    assert registry_entry("structure.cluster_sizes")["id"] == "structure.cluster_sizes"
    with pytest.raises(MixedcheckError) as caught:
        registry_entry("structure.no_such_check")
    assert caught.value.issues == [
        {
            "code": "E4001",
            "message": "No registry entry has the identifier 'structure.no_such_check'.",
        }
    ]


def test_load_registry_checks_the_manifest_the_reader_and_the_version(tmp_path):
    with as_file(files("mixedcheck") / "_spec") as spec:
        directory = tmp_path / "spec"
        shutil.copytree(spec, directory)
    assert load_registry(directory) == read_registry()
    assert load_registry(str(directory)) == read_registry()

    path = directory / "compiled" / "registry.json"
    manifest_path = directory / "MANIFEST.json"
    manifest = read_json_strict(manifest_path, "data")

    def rewrite(data: bytes) -> None:
        path.write_bytes(data)
        manifest["files"]["compiled/registry.json"] = hashlib.sha256(data).hexdigest()
        manifest_path.write_bytes(canonical_bytes(manifest, "data"))

    def issues_of_load():
        try:
            load_registry(directory)
        except MixedcheckError as err:
            return err.issues
        return []

    document = read_registry()
    document["privacy"]["min_count"] = 5
    path.write_bytes(canonical_bytes(document, "hashable"))
    assert issues_of_load() == [
        {
            "code": "E1321",
            "message": (
                "The hash at /files/compiled~1registry.json does not match the content it covers."
            ),
            "pointer": "/files/compiled~1registry.json",
        }
    ]

    document = read_registry()
    document["registry_version"] = "0.2.0"
    rewrite(canonical_bytes(document, "hashable"))
    assert issues_of_load() == [
        {
            "code": "E1441",
            "message": (
                "Version '0.2.0' at /registry_version is not supported. "
                "This release reads version 0.1.x."
            ),
            "pointer": "/registry_version",
        }
    ]

    document["registry_version"] = 1
    rewrite(canonical_bytes(document, "hashable"))
    assert codes_and_pointers(issues_of_load()) == ["E1401 /registry_version"]

    rewrite(b'{"registry_version": "0.1.0", "x": null}')
    assert codes_and_pointers(issues_of_load()) == ["E1101 "]

    path.unlink()
    assert codes_and_pointers(issues_of_load()) == ["E1001 "]


def test_the_rules_across_entries_find_disorder_duplicates_unknown_links_and_cycles():
    registry = read_registry()

    document = copy.deepcopy(registry)
    document["entries"][0], document["entries"][1] = document["entries"][1], document["entries"][0]
    assert codes_and_pointers(registry_issues(document)) == ["E4017 /entries/1"]

    document = copy.deepcopy(registry)
    document["entries"][1]["id"] = document["entries"][0]["id"]
    found = codes_and_pointers(registry_issues(document))
    assert "E4003 /entries/1/id" in found
    assert "E4017 /entries/1" in found

    document = copy.deepcopy(registry)
    document["entries"][0]["links"]["requires"] = ["structure.no_such_check"]
    assert codes_and_pointers(registry_issues(document)) == ["E4004 /entries/0/links/requires/0"]

    document = copy.deepcopy(registry)
    first = entry_index(document, "assignment.constant_within_unit")
    second = entry_index(document, "labels.unicode_forms")
    document["entries"][second]["links"]["requires"] = ["assignment.constant_within_unit"]
    assert codes_and_pointers(registry_issues(document)) == [
        f"E4005 /entries/{first}/links/explained_by/0",
        f"E4005 /entries/{second}/links/requires/0",
    ]


def test_the_rules_on_one_entry_find_each_kind_of_problem():
    registry = read_registry()

    def check(document, expected):
        assert codes_and_pointers(registry_issues(document)) == expected

    document = copy.deepcopy(registry)
    i = entry_index(document, "assignment.constant_within_unit")
    prefix = f"/entries/{i}"
    entry = document["entries"][i]
    entry["reads"].append("outcome")
    entry["sample"] = "analysis"
    entry["remedies"] = entry["remedies"] + copy.deepcopy(entry["remedies"])
    entry["availability"][0]["parameter"] = "no_such_parameter"
    entry["messages"]["constant"]["template"] = "{column} {unknown} {unit} {units} {"
    entry["messages"]["constant"]["args"]["units"]["digits"] = 2
    entry["messages"]["constant"]["args"]["unit"]["name"] = "no_such_part"
    check(
        document,
        [
            f"E4004 {prefix}/availability/0/parameter",
            f"E4008 {prefix}/messages/constant/args/level",
            f"E4004 {prefix}/messages/constant/args/unit/name",
            f"E4014 {prefix}/messages/constant/args/units",
            f"E4007 {prefix}/messages/constant/template",
            f"E4009 {prefix}/messages/constant/template",
            f"E4016 {prefix}/reads",
            f"E4006 {prefix}/remedies/1/id",
            f"E4016 {prefix}/sample",
        ],
    )

    document = copy.deepcopy(registry)
    i = entry_index(document, "outcome.constant_clusters")
    prefix = f"/entries/{i}"
    entry = document["entries"][i]
    entry["thresholds"]["any"]["value"] = "1.5"
    entry["thresholds"]["many"]["value"] = "0.12345"
    entry["thresholds"]["many"]["proximity"] = "0.01"
    entry["statistics"]["constant_share"]["count_class"] = "person"
    check(
        document,
        [
            f"E4021 {prefix}/statistics/constant_share",
            f"E4012 {prefix}/thresholds/any/value",
            f"E4013 {prefix}/thresholds/many",
            f"E4012 {prefix}/thresholds/many/value",
        ],
    )

    document = copy.deepcopy(registry)
    i = entry_index(document, "design.collinearity")
    prefix = f"/entries/{i}"
    entry = document["entries"][i]
    entry["thresholds"]["high"]["validation"]["value"] = "validated"
    entry["decision"]["rules"][0]["finding"] = "consequential"
    entry["decision"]["rules"][1]["thresholds"] = ["no_such_threshold"]
    entry["decision"]["rules"][1]["message"] = "no_such_message"
    entry["statistics"]["flag"] = {"definition": "A flag.", "kind": "boolean"}
    entry["thresholds"]["moderate"]["statistic"] = "flag"
    entry["messages"]["low"]["args"]["gvif"]["name"] = "flag"
    check(
        document,
        [
            f"E4004 {prefix}/decision/rules/1/message",
            f"E4004 {prefix}/decision/rules/1/thresholds/0",
            f"E4015 {prefix}/messages/low/args/gvif/name",
            f"E4010 {prefix}/thresholds/high/validation",
            f"E4011 {prefix}/thresholds/moderate",
        ],
    )
    entry["thresholds"]["high"]["validation"]["value"] = "descriptive"
    check(
        document,
        [
            f"E4020 {prefix}/decision/rules/0/finding",
            f"E4004 {prefix}/decision/rules/1/message",
            f"E4004 {prefix}/decision/rules/1/thresholds/0",
            f"E4015 {prefix}/messages/low/args/gvif/name",
            f"E4011 {prefix}/thresholds/moderate",
        ],
    )
