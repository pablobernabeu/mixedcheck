"""Tests of vendor.py, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

Each test builds a small repository tree in a temporary directory and runs the
script on it as CI does, through the command line.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("vendor.py")
R_SPEC = "r/inst/spec"
PY_SPEC = "python/src/mixedcheck/_spec"
R_FIXTURES = "r/inst/fixtures"
PY_FIXTURES = "python/src/mixedcheck/_fixtures"
# A fixture with CRLF line endings and a byte-order mark, which must be copied
# unchanged and must not trip the CR check, which covers spec/ only.
CRLF_BOM = b"\xef\xbb\xbfid,y\r\n1,2\r\n"


def run(root: Path, mode: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), mode, "--root", str(root)],
        capture_output=True,
        text=True,
        check=False,
    )


class VendorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="vendor-test-"))
        self.addCleanup(shutil.rmtree, self.root)
        self.write("spec/versions.json", b'{\n  "registry": "0.0.0"\n}\n')
        self.write("spec/schemas/results.schema.json", b"{}\n")
        self.write("spec/README.md", b"Not vendored.\n")
        self.write("fixtures/zoo/Z00/data.csv", CRLF_BOM)
        self.set_list(
            [
                "spec/versions.json",
                "spec/schemas/results.schema.json",
                "fixtures/zoo/Z00/data.csv",
            ]
        )

    def write(self, relative: str, content: bytes) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def set_list(self, artefacts: list[object]) -> None:
        text = json.dumps({"artefacts": artefacts}, indent=2) + "\n"
        self.write("spec/vendoring.json", text.encode("utf-8"))

    def sync(self) -> None:
        result = run(self.root, "sync")
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_check_fails(self, *fragments: str) -> str:
        result = run(self.root, "check")
        self.assertEqual(result.returncode, 1, result.stdout)
        for fragment in fragments:
            self.assertIn(fragment, result.stderr)
        return result.stderr


class CleanTree(VendorTestCase):
    def test_check_passes_after_sync(self) -> None:
        self.sync()
        result = run(self.root, "check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("passed for 3 artefact(s)", result.stdout)

    def test_copies_are_byte_identical_and_manifests_hold_their_digests(self) -> None:
        self.sync()
        for target, source_dir, name in [
            (R_SPEC, "spec", "versions.json"),
            (PY_SPEC, "spec", "schemas/results.schema.json"),
            (R_FIXTURES, "fixtures", "zoo/Z00/data.csv"),
            (PY_FIXTURES, "fixtures", "zoo/Z00/data.csv"),
        ]:
            source = (self.root / source_dir / name).read_bytes()
            self.assertEqual((self.root / target / name).read_bytes(), source)
            manifest = json.loads((self.root / target / "MANIFEST.json").read_text("utf-8"))
            self.assertEqual(manifest["algorithm"], "sha256")
            self.assertEqual(manifest["source"], source_dir)
            self.assertEqual(manifest["files"][name], hashlib.sha256(source).hexdigest())
        self.assertEqual((self.root / R_FIXTURES / "zoo/Z00/data.csv").read_bytes(), CRLF_BOM)

    def test_unlisted_sources_are_not_vendored(self) -> None:
        self.sync()
        self.assertFalse((self.root / R_SPEC / "README.md").exists())

    def test_second_sync_changes_nothing(self) -> None:
        self.sync()
        result = run(self.root, "sync")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "vendored copies are up to date")

    def test_sync_removes_copies_of_artefacts_no_longer_listed(self) -> None:
        self.sync()
        self.set_list(["spec/versions.json"])
        self.sync()
        self.assertFalse((self.root / R_SPEC / "schemas").exists())
        self.assertFalse((self.root / R_FIXTURES).exists())
        self.assertFalse((self.root / PY_FIXTURES).exists())
        self.assertEqual(run(self.root, "check").returncode, 0)


class Mismatches(VendorTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.sync()

    def test_copy_that_differs_from_its_source(self) -> None:
        for target in (R_SPEC, PY_SPEC):
            with self.subTest(target=target):
                self.sync()
                self.write(f"{target}/versions.json", b'{\n  "registry": "9.9.9"\n}\n')
                self.assert_check_fails(f"{target}/versions.json: differs from spec/versions.json")

    def test_copy_that_differs_only_in_line_endings(self) -> None:
        self.write(f"{R_FIXTURES}/zoo/Z00/data.csv", CRLF_BOM.replace(b"\r\n", b"\n"))
        self.assert_check_fails(f"{R_FIXTURES}/zoo/Z00/data.csv: differs")

    def test_source_edited_without_sync(self) -> None:
        self.write("spec/versions.json", b'{\n  "registry": "0.1.0"\n}\n')
        self.assert_check_fails(
            f"{R_SPEC}/versions.json: differs",
            f"{PY_SPEC}/versions.json: differs",
            f"{R_SPEC}/MANIFEST.json: stale",
        )

    def test_missing_copy(self) -> None:
        (self.root / PY_SPEC / "schemas/results.schema.json").unlink()
        self.assert_check_fails(
            f"{PY_SPEC}/schemas/results.schema.json: missing copy of "
            "spec/schemas/results.schema.json"
        )

    def test_listed_source_missing(self) -> None:
        (self.root / "spec/schemas/results.schema.json").unlink()
        self.assert_check_fails(
            "spec/schemas/results.schema.json: listed in spec/vendoring.json but missing"
        )

    def test_unlisted_file_in_a_vendored_directory(self) -> None:
        self.write(f"{R_SPEC}/extra.json", b"{}\n")
        self.write(f"{PY_FIXTURES}/zoo/.DS_Store", b"")
        self.assert_check_fails(
            f"{R_SPEC}/extra.json: not listed in spec/vendoring.json",
            f"{PY_FIXTURES}/zoo/.DS_Store: not listed",
        )

    def test_file_in_a_vendored_directory_whose_source_lists_nothing(self) -> None:
        self.set_list(["spec/versions.json", "spec/schemas/results.schema.json"])
        self.assert_check_fails(
            f"{R_FIXTURES}/zoo/Z00/data.csv: not listed",
            f"{PY_FIXTURES}/MANIFEST.json: not listed",
        )

    def test_stale_manifest(self) -> None:
        manifest = self.root / R_SPEC / "MANIFEST.json"
        document = json.loads(manifest.read_text("utf-8"))
        document["files"]["versions.json"] = "0" * 64
        manifest.write_text(json.dumps(document, indent=2) + "\n", "utf-8")
        self.assert_check_fails(f"{R_SPEC}/MANIFEST.json: stale")

    def test_manifest_missing_an_entry(self) -> None:
        manifest = self.root / PY_FIXTURES / "MANIFEST.json"
        document = json.loads(manifest.read_text("utf-8"))
        document["files"] = {}
        manifest.write_text(json.dumps(document, indent=2) + "\n", "utf-8")
        self.assert_check_fails(f"{PY_FIXTURES}/MANIFEST.json: stale")

    def test_missing_manifest(self) -> None:
        (self.root / PY_SPEC / "MANIFEST.json").unlink()
        self.assert_check_fails(f"{PY_SPEC}/MANIFEST.json: missing")

    def test_carriage_return_in_a_spec_source(self) -> None:
        self.write("spec/versions.json", b'{\r\n  "registry": "0.0.0"\r\n}\r\n')
        self.assert_check_fails("spec/versions.json: 3 carriage return(s), the first on line 1")

    def test_carriage_return_in_an_unlisted_spec_file(self) -> None:
        self.write("spec/README.md", b"Line one.\rLine two.\n")
        self.assert_check_fails("spec/README.md: 1 carriage return(s), the first on line 1")

    def test_byte_order_mark_in_a_spec_source(self) -> None:
        self.write("spec/README.md", b"\xef\xbb\xbfNot vendored.\n")
        self.assert_check_fails("spec/README.md: starts with a byte-order mark")

    def test_copy_that_is_a_symbolic_link(self) -> None:
        copy = self.root / R_SPEC / "versions.json"
        copy.unlink()
        try:
            os.symlink(Path("../../../spec/versions.json"), copy)
        except OSError:
            self.skipTest("symbolic links are not available")
        self.assert_check_fails(f"{R_SPEC}/versions.json: a symbolic link, not a copy")
        self.sync()
        self.assertFalse(copy.is_symlink())
        self.assertEqual(run(self.root, "check").returncode, 0)

    def test_files_that_operating_systems_write_in_spec_are_ignored(self) -> None:
        self.write("spec/.DS_Store", b"\x00\r\x00")
        self.write("spec/schemas/Thumbs.db", b"\r")
        self.assertEqual(run(self.root, "check").returncode, 0)

    def test_every_problem_is_reported(self) -> None:
        self.write(f"{R_SPEC}/versions.json", b"{}\n")
        self.write(f"{PY_SPEC}/extra.json", b"{}\n")
        (self.root / R_FIXTURES / "MANIFEST.json").unlink()
        stderr = self.assert_check_fails("3 problem(s)")
        self.assertEqual(len(stderr.strip().splitlines()), 4)


class InvalidList(VendorTestCase):
    def test_invalid_entries(self) -> None:
        cases = {
            "/spec/versions.json": "is not a normalised relative POSIX path",
            "spec//versions.json": "is not a normalised relative POSIX path",
            "spec\\versions.json": "is not a normalised relative POSIX path",
            "spec/../LICENSE": "contains '.' or '..'",
            "docs/notes.md": "is not a file under spec/ or fixtures/",
            "spec": "is not a file under spec/ or fixtures/",
            "spec/vendoring.json": "is the list of artefacts itself",
            "spec/MANIFEST.json": "would overwrite the vendored MANIFEST.json",
            "spec/Manifest.json": "would overwrite the vendored MANIFEST.json",
            1: "is not a string",
        }
        for entry, message in cases.items():
            with self.subTest(entry=entry):
                self.set_list(["spec/versions.json", entry])
                self.assert_check_fails(f"spec/vendoring.json: entry {entry!r} {message}")

    def test_entries_that_the_r_package_could_not_carry(self) -> None:
        long_name = "a" * 75 + ".json"
        cases = {
            "spec/.hidden.json": "has the component '.hidden.json', which is not a portable",
            "spec/a b.json": "has the component 'a b.json', which is not a portable",
            "fixtures/caf\u00e9/data.csv": "has the component 'caf\u00e9', which is not a portable",
            "spec/Aux.json": "has the component 'Aux.json', which names a device on Windows",
            "fixtures/lpt1/data.csv": "has the component 'lpt1', which names a device",
            "spec/check/a.json": "has the component 'check', which R CMD build leaves out",
            "spec/threshold/a.json": "has the component 'threshold', which R CMD build",
            "spec/a.Rcheck/a.json": "has the component 'a.Rcheck', which R CMD build",
            "spec/schemas.BAK": "has the component 'schemas.BAK', which R CMD build",
            "spec/a.json.swp": "has the component 'a.json.swp', which R CMD build",
            f"spec/{long_name}": "is longer than 100 bytes as a path in the R package's tarball",
        }
        for entry, message in cases.items():
            with self.subTest(entry=entry):
                self.set_list(["spec/versions.json", entry])
                self.assert_check_fails(f"spec/vendoring.json: entry {entry!r} {message}")

    def test_names_that_the_r_package_carries(self) -> None:
        # R CMD build keeps a file called check and a file whose name ends in old,
        # and a path of exactly 100 bytes fits in the tarball.
        names = ["spec/schemas/check", "spec/" + "a" * 74 + ".json", "spec/_x/old.json"]
        for name in names:
            self.write(name, b"{}\n")
        self.set_list(["spec/versions.json", *names])
        self.sync()
        self.assertEqual(run(self.root, "check").returncode, 0)

    def test_paths_that_differ_only_in_case(self) -> None:
        entries = ["spec/versions.json", "spec/Versions.json", "spec/a/a.json", "spec/A/b.json"]
        self.set_list(entries)
        self.assert_check_fails(
            ": 'spec/versions.json' and 'spec/Versions.json' differ only in case",
            ": 'spec/a' and 'spec/A' differ only in case",
        )

    def test_duplicate_entry(self) -> None:
        self.set_list(["spec/versions.json", "spec/versions.json"])
        self.assert_check_fails("entry 'spec/versions.json' is listed twice")

    def test_list_that_is_not_an_object_of_artefacts(self) -> None:
        for text in ['["spec/versions.json"]', '{"artefacts": "spec/versions.json"}', "{"]:
            with self.subTest(text=text):
                self.write("spec/vendoring.json", text.encode("utf-8"))
                self.assert_check_fails("spec/vendoring.json: ")

    def test_duplicate_key_in_the_list(self) -> None:
        self.write("spec/vendoring.json", b'{"artefacts": [], "artefacts": []}\n')
        self.assert_check_fails("duplicate key 'artefacts'")


class SyncRefusals(VendorTestCase):
    def test_sync_writes_nothing_when_a_source_is_missing(self) -> None:
        (self.root / "spec/versions.json").unlink()
        result = run(self.root, "sync")
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "spec/versions.json: listed in spec/vendoring.json but missing", result.stderr
        )
        self.assertFalse((self.root / "r").exists())
        self.assertFalse((self.root / "python").exists())

    def test_sync_writes_nothing_when_a_spec_source_has_a_carriage_return(self) -> None:
        self.write("spec/versions.json", b"{}\r\n")
        result = run(self.root, "sync")
        self.assertEqual(result.returncode, 1)
        self.assertIn("carriage return", result.stderr)
        self.assertFalse((self.root / "r").exists())


if __name__ == "__main__":
    unittest.main()
