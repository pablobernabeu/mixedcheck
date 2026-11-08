"""The examples in the docstrings of the exported functions run as written."""

from __future__ import annotations

import doctest

import pytest

import mixedcheck
from mixedcheck import _declaration, _hash, _json_read, _json_write, _registry

MODULES = [_declaration, _hash, _json_read, _json_write, _registry]


@pytest.mark.parametrize("module", MODULES, ids=[module.__name__ for module in MODULES])
def test_the_examples_run(module):
    finder = doctest.DocTestFinder()
    runner = doctest.DocTestRunner(optionflags=doctest.ELLIPSIS)
    globs = {name: getattr(mixedcheck, name) for name in mixedcheck.__all__}
    examples = 0
    for test in finder.find(module, globs=globs):
        examples += len(test.examples)
        runner.run(test)
    assert examples > 0
    assert runner.summarize(verbose=False).failed == 0


def test_every_exported_function_has_an_example():
    for name in mixedcheck.__all__:
        value = getattr(mixedcheck, name)
        if callable(value) and not isinstance(value, type) and name != "spec_versions":
            assert ">>>" in (value.__doc__ or ""), name
