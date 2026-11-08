import json
from importlib.resources import files

import pytest

import mixedcheck
from mixedcheck._vendored import _read_versions, _vendored_problems


def test_spec_versions_returns_the_versions_in_the_vendored_file():
    versions = mixedcheck.spec_versions()
    assert list(versions) == ["registry", "schemas", "canonicaliser"]
    assert all(isinstance(value, str) for value in versions.values())
    path = files("mixedcheck") / "_spec" / "versions.json"
    assert versions == json.loads(path.read_text(encoding="utf-8"))


def test_spec_versions_returns_a_new_dictionary_each_time():
    versions = mixedcheck.spec_versions()
    versions["registry"] = "changed"
    assert mixedcheck.spec_versions()["registry"] != "changed"


@pytest.mark.parametrize(
    "text",
    [
        '{"registry": 1}',
        '{"registry": null}',
        '{"registry": ["0.1.0"]}',
        '["0.1.0"]',
        '"0.1.0"',
        "{}",
        '{"registry": "0.1.0", "registry": "0.2.0"}',
        "{",
    ],
)
def test_read_versions_rejects_anything_but_an_object_of_strings(text):
    with pytest.raises(ValueError, match="must hold a JSON object whose values are strings"):
        _read_versions(text, "versions.json")


@pytest.mark.parametrize("name", ["_spec", "_fixtures"])
def test_installed_vendored_files_match_their_manifest(name):
    directory = files("mixedcheck") / name
    if name == "_spec":
        assert (directory / "MANIFEST.json").is_file()
    elif not directory.is_dir():
        pytest.skip(f"no {name} directory is installed")
    assert _vendored_problems(directory) == []


def _copy_tree(source, target):
    target.mkdir()
    for entry in source.iterdir():
        if entry.is_dir():
            _copy_tree(entry, target / entry.name)
        else:
            (target / entry.name).write_bytes(entry.read_bytes())


def test_vendored_problems_names_a_changed_missing_or_unlisted_file(tmp_path):
    directory = tmp_path / "_spec"
    _copy_tree(files("mixedcheck") / "_spec", directory)
    assert _vendored_problems(directory) == []

    (directory / "extra.txt").write_bytes(b"extra\n")
    assert _vendored_problems(directory) == ["extra.txt: not listed in MANIFEST.json"]
    (directory / "extra.txt").unlink()

    versions = directory / "versions.json"
    # The same text with CRLF line endings, as a Git checkout with line-ending
    # conversion would write it.
    versions.write_bytes(versions.read_bytes().replace(b"\n", b"\r\n"))
    assert _vendored_problems(directory) == ["versions.json: SHA-256 differs from MANIFEST.json"]

    versions.unlink()
    assert _vendored_problems(directory) == ["versions.json: missing"]

    (directory / "MANIFEST.json").unlink()
    assert _vendored_problems(directory) == ["MANIFEST.json: missing"]
