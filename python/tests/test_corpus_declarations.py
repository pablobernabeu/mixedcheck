"""The declaration and YAML corpora, run from the installed package:
declarations written in JSON and YAML, read, converted and checked in the five
stages of the validator (fixtures/conformance/declarations/README.md and
fixtures/conformance/yaml/README.md).

Reading YAML needs PyYAML, installed with the extra 'yaml'. Without it, the
YAML cases check that the bytes are refused as with PyYAML and that every
other YAML text gives E3001.
"""

from __future__ import annotations

from corpus_helpers import corpus_cases, parametrize_cases, run_declaration_case

DECLARATION_FILES = (
    "valid.json",
    "reading.json",
    "version.json",
    "structure.json",
    "references.json",
    "meaning.json",
    "precedence.json",
)
YAML_FILES = ("valid.json", "reading.json", "conversion.json", "validation.json", "precedence.json")


def test_every_corpus_file_has_cases():
    for name in DECLARATION_FILES:
        assert corpus_cases("declarations", name), name
    for name in YAML_FILES:
        assert corpus_cases("yaml", name), name


@parametrize_cases("declarations", *DECLARATION_FILES)
def test_declaration_corpus(case):
    run_declaration_case("declarations", case)


@parametrize_cases("yaml", *YAML_FILES)
def test_yaml_corpus(case):
    run_declaration_case("yaml", case)
