"""The corpora of the canonicaliser, run from the installed package: the JSON
corpus (the strict reader in each mode and the serialiser, with the examples
of RFC 8785), the number corpus (ECMAScript formatting, correctly rounded
reading, the number rules of the hashable profile and decimal constants), the
Unicode corpus (UTF-8, normalisable strings, NFC, the order of identifiers
and the cases that a locale or an encoding could change), the hash corpus and
the HMAC corpus."""

from __future__ import annotations

from corpus_helpers import (
    bits_double,
    corpus_cases,
    parametrize_cases,
    run_json_case,
)

from mixedcheck import (
    canonical_bytes,
    canonical_hash,
    commitment_key_id,
    hash_bytes,
    hash_file,
    keyed_commitment,
    read_json_strict,
)
from mixedcheck._errors import MixedcheckError
from mixedcheck._hash import hmac_sha256, json_pointer_get
from mixedcheck._numbers import decimal_string
from mixedcheck._unicode import (
    compare_identifiers,
    comparison_form,
    is_normalisable,
    sort_identifiers,
)


def test_every_corpus_file_has_cases():
    for directory, names in {
        "json": ("rfc8785.json", "syntax.json", "values.json", "canonical.json", "writer.json"),
        "numbers": ("format.json", "read.json", "decimal_constants.json"),
        "unicode": (
            "utf8.json",
            "normalisation.json",
            "hashable.json",
            "order.json",
            "c_locale.json",
        ),
        "hash": ("sha256.json", "sections.json"),
        "hmac": ("rfc4231.json", "commitments.json"),
    }.items():
        for name in names:
            assert corpus_cases(directory, name), f"{directory}/{name}"


@parametrize_cases(
    "json", "rfc8785.json", "syntax.json", "values.json", "canonical.json", "writer.json"
)
def test_json_corpus(case, tmp_path):
    run_json_case(case, tmp_path)


@parametrize_cases("numbers", "format.json", "read.json")
def test_number_corpus(case, tmp_path):
    run_json_case(case, tmp_path)


@parametrize_cases("numbers", "decimal_constants.json")
def test_decimal_constant_corpus(case):
    x = bits_double(case["double"])
    assert decimal_string(x, case["digits"]) == case["expected"]["decimal"]


@parametrize_cases("unicode", "utf8.json", "hashable.json", "c_locale.json")
def test_unicode_reader_and_writer_corpus(case, tmp_path):
    run_json_case(case, tmp_path)


@parametrize_cases("unicode", "normalisation.json")
def test_unicode_normalisation_corpus(case):
    assert is_normalisable(case["string"]) is case["expected"]["normalisable"]
    assert comparison_form(case["string"]) == case["expected"]["form"]


@parametrize_cases("unicode", "order.json")
def test_unicode_order_corpus(case):
    if "first" in case:
        assert compare_identifiers(case["first"], case["second"]) == case["expected"]["order"]
    else:
        assert sort_identifiers(case["strings"]) == case["expected"]["sorted"]


@parametrize_cases("hash", "sha256.json")
def test_sha256_corpus_in_memory_and_as_a_file(case, tmp_path):
    if "input_hex" in case:
        data = bytes.fromhex(case["input_hex"])
    else:
        data = case["input"].encode("utf-8")
    data *= case.get("repeat", 1)
    assert hash_bytes(data) == case["expected"]["sha256"]
    path = tmp_path / "input"
    path.write_bytes(data)
    assert hash_file(path) == case["expected"]["sha256"]
    assert hash_file(str(path)) == case["expected"]["sha256"]


@parametrize_cases("hash", "sections.json")
def test_section_corpus(case):
    document = read_json_strict(case["input"].encode("utf-8"), "hashable")
    section = json_pointer_get(document, case["pointer"])
    assert canonical_bytes(section, "hashable") == case["expected"]["canonical"].encode("utf-8")
    assert canonical_hash(section, "hashable") == case["expected"]["sha256"]


def _message(case):
    if "message_hex" in case:
        return bytes.fromhex(case["message_hex"])
    return case["message"].encode("utf-8")


@parametrize_cases("hmac", "rfc4231.json")
def test_hmac_corpus(case):
    digest = hmac_sha256(bytes.fromhex(case["key_hex"]), _message(case))
    if "truncate" in case:
        digest = digest[: 2 * case["truncate"]]
    assert digest == case["expected"]["digest"]


@parametrize_cases("hmac", "commitments.json")
def test_commitment_corpus(case):
    expected = case["expected"]
    if "covers" in case:
        commitment = keyed_commitment(_message(case), case["key"], case["covers"])
        assert commitment == expected["commitment"]
    elif "issue" in expected:
        try:
            commitment_key_id(case["key"])
        except MixedcheckError as err:
            assert err.issues == [expected["issue"]]
        else:
            raise AssertionError(f"{case['id']}: expected {expected['issue']['code']}.")
    else:
        assert commitment_key_id(case["key"]) == expected["key_id"]
