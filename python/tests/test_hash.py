"""Targeted tests of hashing, HMAC, commitment keys and keyed commitments,
beyond the cases of the hash and HMAC corpora."""

from __future__ import annotations

import hashlib
import random
import re

import pytest

from mixedcheck import (
    MixedcheckError,
    canonical_bytes,
    canonical_hash,
    commitment_key_id,
    hash_bytes,
    hash_file,
    keyed_commitment,
    new_commitment_key,
    read_json_strict,
)
from mixedcheck._hash import hmac_sha256, json_pointer_get, verify_commitment


def code_of(f, *args):
    try:
        f(*args)
    except MixedcheckError as err:
        return err.issues[0]["code"]
    return None


def test_hash_file_reports_missing_and_unreadable_files(tmp_path):
    assert code_of(hash_file, tmp_path / "no-file") == "E1001"
    assert code_of(hash_file, tmp_path) == "E1002"
    with pytest.raises(TypeError, match="file path"):
        hash_file(1)
    with pytest.raises(TypeError, match="bytes object"):
        hash_bytes("abc")


def test_the_hash_of_a_value_covers_its_canonical_bytes(tmp_path):
    value = {"title": "study", "n": [1, 2.5]}
    assert canonical_hash(value, "hashable") == hash_bytes(canonical_bytes(value, "hashable"))
    path = tmp_path / "value.json"
    path.write_bytes(canonical_bytes(value, "hashable"))
    assert hash_file(path) == canonical_hash(value, "hashable")
    assert hash_bytes(b"") == (
        "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )


def test_hmac_sha256_handles_keys_around_the_block_size():
    message = b"message"
    # A key longer than 64 bytes is replaced by its SHA-256 digest first.
    long_key = b"\xaa" * 131
    assert hmac_sha256(long_key, message) == hmac_sha256(hashlib.sha256(long_key).digest(), message)
    # A key of up to 64 bytes is padded with zeros.
    assert hmac_sha256(bytes(range(1, 11)), message) == hmac_sha256(
        bytes(range(1, 11)) + bytes(54), message
    )
    assert hmac_sha256(b"\x01" * 64, message) != hmac_sha256(b"\x01" * 65, message)


def test_new_commitment_key_creates_a_key_and_leaves_the_random_generator_alone():
    random.seed(1)
    state = random.getstate()
    key = new_commitment_key()
    assert random.getstate() == state
    assert list(key) == ["created", "key", "key_id"]
    assert re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", key["created"])
    assert re.fullmatch(r"[0-9a-f]{64}", key["key"])
    assert key["key_id"] == commitment_key_id(key["key"])
    assert new_commitment_key()["key"] != key["key"]


def test_commitments_refuse_keys_of_the_wrong_form():
    assert code_of(commitment_key_id, None) == "E1311"
    assert code_of(commitment_key_id, ["a", "b"]) == "E1311"
    assert code_of(commitment_key_id, "0g" * 32) == "E1311"
    assert code_of(commitment_key_id, "0f" * 32 + "\n") == "E1311"
    key = "0f" * 32
    assert code_of(keyed_commitment, b"x", key.upper()) == "E1311"
    with pytest.raises(TypeError, match="bytes object"):
        keyed_commitment("text", key)
    with pytest.raises(ValueError, match="'covers' must be"):
        keyed_commitment(b"x", key, "table")
    commitment = keyed_commitment(b"abc", key)
    assert commitment["covers"] == "data_file"
    assert commitment["key_id"] == commitment_key_id(key)
    assert commitment["digest"] == hmac_sha256(bytes.fromhex(key), b"abc")


def test_verification_finds_the_key_and_compares_the_digest():
    key = "0f" * 32
    other = "1e" * 32
    keys = [
        {"created": "2026-11-08T12:00:00Z", "key": other, "key_id": commitment_key_id(other)},
        {"created": "2026-11-08T12:00:00Z", "key": key, "key_id": commitment_key_id(key)},
    ]
    commitment = keyed_commitment(b"abc", key, "outcome_column")
    assert verify_commitment(commitment, b"abc", keys) is True
    with pytest.raises(MixedcheckError) as caught:
        verify_commitment(commitment, b"abd", keys, "/access/0/commitment")
    assert caught.value.issues == [
        {
            "code": "E1314",
            "message": "The data do not match the commitment at /access/0/commitment.",
            "pointer": "/access/0/commitment",
        }
    ]
    with pytest.raises(MixedcheckError) as caught:
        verify_commitment(commitment, b"abc", keys[:1])
    assert caught.value.issues == [
        {
            "code": "E1313",
            "message": (
                f"No commitment key with the identifier '{commitment_key_id(key)}' was found."
            ),
        }
    ]


def test_json_pointers_lead_to_sections_of_a_document():
    document = read_json_strict(b'{"a/b":{"m~n":[1,{"k":2}]},"c":[]}', "plain")
    assert json_pointer_get(document, "") == document
    assert json_pointer_get(document, "/a~1b/m~0n/0") == 1
    assert json_pointer_get(document, "/c") == []
    for pointer in ("/a~1b/m~0n/2", "/a~1b/m~0n/01", "/x", "/c/" + "1" * 5000):
        with pytest.raises(ValueError, match="does not lead to a value"):
            json_pointer_get(document, pointer)
    with pytest.raises(ValueError, match="start with '/'"):
        json_pointer_get(document, "a")
