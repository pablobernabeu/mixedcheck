"""SHA-256 hashes, HMAC-SHA-256 and keyed commitments (docs/spec/conventions.md,
Hashes and Keyed commitments)."""

from __future__ import annotations

import hashlib
import hmac
import os
import re
import secrets
from typing import Any

from mixedcheck._errors import raise_issue
from mixedcheck._times import run_time, utc_timestamp

COVERS = ("data_file", "analysis_table", "outcome_column")

_KEY = re.compile(r"[0-9a-f]{64}")
_INDEX = re.compile(r"0|[1-9][0-9]*")


def hash_bytes(x: bytes) -> str:
    """SHA-256 hash of bytes.

    Hashes bytes held in memory and writes the hash as documents write it:
    'sha256:' followed by the 64 lower-case hexadecimal digits of the SHA-256
    digest. A str is never hashed directly, because its bytes depend on its
    encoding. Use :func:`canonical_hash` for the hash of a value.

    Args:
        x: The bytes, as a bytes object.

    Returns:
        The hash, as a str.

    Examples:
        >>> hash_bytes(b"abc")
        'sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    """
    if not isinstance(x, bytes | bytearray | memoryview):
        raise TypeError("'x' must be a bytes object.")
    return "sha256:" + hashlib.sha256(x).hexdigest()


def hash_file(path: str | os.PathLike[str]) -> str:
    """SHA-256 hash of a file.

    Hashes the bytes of a file as stored and writes the hash as documents
    write it: 'sha256:' followed by the 64 lower-case hexadecimal digits of
    the SHA-256 digest.

    Args:
        path: The path of a file.

    Returns:
        The hash, as a str.

    Raises:
        MixedcheckError: The code E1001 when the file does not exist and
            E1002 when it cannot be read.

    Examples:
        >>> import os, tempfile
        >>> path = os.path.join(tempfile.mkdtemp(), "abc.txt")
        >>> with open(path, "wb") as handle:
        ...     _ = handle.write(b"abc")
        >>> hash_file(path)
        'sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        >>> os.remove(path)
    """
    if isinstance(path, os.PathLike):
        path = os.fspath(path)
    if not isinstance(path, str):
        raise TypeError("'path' must be a file path.")
    if not os.path.exists(path):
        raise_issue("E1001")
    if os.path.isdir(path) or not os.access(path, os.R_OK):
        raise_issue("E1002")
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                digest.update(block)
    except OSError:
        raise_issue("E1002")
    return "sha256:" + digest.hexdigest()


def hmac_sha256(key: bytes, message: bytes) -> str:
    """HMAC-SHA-256 of a message under a key, by RFC 2104 with a block size of
    64 bytes, as 64 lower-case hexadecimal digits."""
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def commitment_key_bytes(key: Any) -> bytes:
    """The 32 bytes of a commitment key supplied as 64 lower-case hexadecimal
    digits, or E1311."""
    if not isinstance(key, str) or _KEY.fullmatch(key) is None:
        raise_issue("E1311")
    return bytes.fromhex(key)


def new_commitment_key() -> dict[str, str]:
    """Create a commitment key.

    A commitment key is 32 bytes, written as 64 lower-case hexadecimal digits.
    This function creates one from the operating system's secure source of
    random bytes through ``secrets.token_bytes()``, never from Python's or
    numpy's random number generators, whose state it leaves unchanged. Keys
    belong in the internal sidecar of a results document and never in a
    shareable file.

    Returns:
        A dict with the members ``created``, the UTC time of creation, ``key``
        and ``key_id``, the form in which the internal sidecar stores a key.
        The time is that of the environment variable MIXEDCHECK_TIME when it
        is set, as for :func:`audit`.

    Raises:
        MixedcheckError: The code E1312 when the operating system offers no
            secure source of random bytes, so that a key must be supplied.
        ValueError: A value of MIXEDCHECK_TIME other than a whole number of
            seconds.

    Examples:
        >>> key = new_commitment_key()
        >>> len(key["key_id"])
        16
    """
    created = utc_timestamp(run_time())
    key = random_key_bytes().hex()
    return {"created": created, "key": key, "key_id": commitment_key_id(key)}


def random_key_bytes() -> bytes:
    """32 bytes from the operating system's secure source (conventions.md,
    Keys), or E1312 when it offers none."""
    try:
        return secrets.token_bytes(32)
    except (NotImplementedError, OSError):
        raise_issue("E1312")


def commitment_key_id(key: str) -> str:
    """Identifier of a commitment key.

    The identifier of a key is the first 16 hexadecimal digits of the SHA-256
    digest of its 32 bytes, by which a verifier finds the key.

    Args:
        key: A commitment key, as 64 lower-case hexadecimal digits.

    Returns:
        The identifier, as a str.

    Raises:
        MixedcheckError: A key of another form, with the code E1311.

    Examples:
        >>> commitment_key_id("0f" * 32)
        '9b68d49bb092f712'
    """
    return hashlib.sha256(commitment_key_bytes(key)).hexdigest()[:16]


def keyed_commitment(message: bytes, key: str, covers: str = "data_file") -> dict[str, str]:
    """Keyed commitment to a message.

    A keyed commitment is the HMAC-SHA-256 of a message under a commitment
    key. Shareable files carry commitments in place of hashes of person-level
    data, because an unkeyed hash of a small data set can be reversed by
    trying every possible value. The message for 'data_file' is the bytes of a
    raw data file as stored, which ``open(path, "rb").read()`` reads.

    Args:
        message: The bytes committed to, as a bytes object.
        key: A commitment key, as 64 lower-case hexadecimal digits.
        covers: What the message is: ``"data_file"``, ``"analysis_table"`` or
            ``"outcome_column"``.

    Returns:
        A dict with the members ``algorithm``, ``covers``, ``digest`` and
        ``key_id``, the form of a keyed commitment in a results document.

    Raises:
        MixedcheckError: A key of another form, with the code E1311.

    Examples:
        >>> # The data file of fixture Z19N of the pathology zoo, as installed
        >>> # with the package. With this key, audit() writes the same
        >>> # commitment at /inputs/data/data_file when it reads the data from
        >>> # the file.
        >>> path = pathology_zoo("Z19N")["data_file"]
        >>> with open(path, "rb") as handle:
        ...     message = handle.read()
        >>> commitment = keyed_commitment(message, bytes(range(32)).hex())
        >>> commitment["key_id"], commitment["digest"]
        ('630dcd2966c43366', 'ae9d656c2b36786a72285217d271e7003070ed624e10aa16161413a4e3873ed6')
    """
    if not isinstance(message, bytes | bytearray | memoryview):
        raise TypeError("'message' must be a bytes object.")
    if covers not in COVERS:
        raise ValueError("'covers' must be 'data_file', 'analysis_table' or 'outcome_column'.")
    data = commitment_key_bytes(key)
    return {
        "algorithm": "hmac-sha256",
        "covers": covers,
        "digest": hmac_sha256(data, bytes(message)),
        "key_id": hashlib.sha256(data).hexdigest()[:16],
    }


def verify_commitment(
    commitment: dict[str, Any], message: bytes, keys: list[dict[str, Any]], pointer: str = ""
) -> bool:
    """Verify a keyed commitment against the message it covers.

    The keys are the commitment_key objects of an internal sidecar. Reports
    E1313 when no key has the commitment's identifier and E1314, at the
    pointer of the commitment, when the digest differs. Returns True otherwise.
    """
    found = [entry for entry in keys if entry.get("key_id") == commitment.get("key_id")]
    if not found:
        raise_issue("E1313", {"key_id": commitment.get("key_id")})
    digest = hmac_sha256(commitment_key_bytes(found[0]["key"]), bytes(message))
    if not hmac.compare_digest(digest, str(commitment.get("digest"))):
        raise_issue("E1314", pointer=pointer)
    return True


def json_pointer_get(x: Any, pointer: str) -> Any:
    """The value at a JSON Pointer (RFC 6901) in a value read by the strict
    reader, such as the section of a document whose hash the document records."""
    if pointer == "":
        return x
    if not pointer.startswith("/"):
        raise ValueError("A JSON Pointer must be empty or start with '/'.")
    for token in pointer[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if isinstance(x, dict):
            if token not in x:
                raise ValueError(f"The pointer '{pointer}' does not lead to a value.")
            x = x[token]
        elif isinstance(x, list):
            if _INDEX.fullmatch(token) is None or len(token) > 18 or int(token) >= len(x):
                raise ValueError(f"The pointer '{pointer}' does not lead to a value.")
            x = x[int(token)]
        else:
            raise ValueError(f"The pointer '{pointer}' does not lead to a value.")
    return x
