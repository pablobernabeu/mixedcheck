"""Tests of rehash_results.py, run from the repository root with

    python3 -m unittest discover -s spec/tools -v

Each test copies the results corpus and the compiled registry into a temporary
directory, changes the copy and checks that the script restores it.
"""

from __future__ import annotations

import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import rehash_results as rr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def snapshot(root: Path) -> dict[str, bytes]:
    return rr.corpus_files(root)


def rewrite(root: Path) -> list[str]:
    """Apply the script's rewrites without vendoring, which needs the whole tree."""
    changed, problems = rr.plan(root)
    if problems:
        raise AssertionError(problems)
    for name, data in changed.items():
        (root / rr.CORPUS / name).write_bytes(data)
    return sorted(changed)


def check(root: Path) -> int:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return rr.main(["--check", "--root", str(root)])


class RehashResultsTestCase(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        shutil.copytree(ROOT / rr.CORPUS, self.root / rr.CORPUS)
        registry = self.root / rr.REGISTRY
        registry.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / rr.REGISTRY, registry)
        self.original = snapshot(self.root)

    def test_the_corpus_is_up_to_date(self) -> None:
        self.assertEqual(check(self.root), 0)
        self.assertEqual(rewrite(self.root), [])

    def test_a_change_to_the_registry_is_followed_and_undone(self) -> None:
        registry = self.root / rr.REGISTRY
        registry_bytes = registry.read_bytes()
        registry.write_bytes(registry_bytes + b"\n")
        self.assertEqual(check(self.root), 1)
        changed = rewrite(self.root)
        self.assertIn("valid/001.json", changed)
        self.assertIn("sidecar/nokey_sidecar.json", changed)
        self.assertEqual(check(self.root), 0)
        updated = snapshot(self.root)
        new_hash = rr.digest(registry.read_bytes())
        self.assertIn(new_hash, updated["valid/001.json"])
        # The documents of W7090 keep the other hash that they record, and the
        # sidecar of a case that expects E1321 at /results_hash still records
        # the hash of a file other than its case's document.
        for name in ("registry/001.json", "sidecar/other_registry.json"):
            self.assertEqual(updated[name], self.original[name], name)
        other = rr.RESULTS_HASH.search(updated["sidecar/other_hash_sidecar.json"])
        assert other is not None
        self.assertNotEqual(other.group(1), rr.digest(updated["sidecar/file.json"]))
        registry.write_bytes(registry_bytes)
        self.assertEqual(check(self.root), 1)
        rewrite(self.root)
        self.assertEqual(snapshot(self.root), self.original)

    def test_a_document_edited_by_hand_is_restored(self) -> None:
        path = self.root / rr.CORPUS / "sidecar" / "nokey.json"
        recorded = rr.digest((self.root / rr.REGISTRY).read_bytes())
        path.write_bytes(path.read_bytes().replace(recorded, b"sha256:" + b"ab" * 32))
        self.assertEqual(check(self.root), 1)
        self.assertEqual(rewrite(self.root), ["sidecar/nokey.json"])
        self.assertEqual(snapshot(self.root), self.original)

    def test_a_sidecar_that_does_not_match_its_document_is_reported(self) -> None:
        path = self.root / rr.CORPUS / "sidecar" / "file_sidecar.json"
        found = rr.RESULTS_HASH.search(path.read_bytes())
        assert found is not None
        path.write_bytes(path.read_bytes().replace(found.group(1), b"sha256:" + b"cd" * 32))
        self.assertEqual(check(self.root), 1)
        changed, problems = rr.plan(self.root)
        self.assertEqual(changed, {})
        self.assertTrue(any("file_sidecar.json" in problem for problem in problems))


if __name__ == "__main__":
    unittest.main()
