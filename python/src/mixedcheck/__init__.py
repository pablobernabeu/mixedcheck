"""mixedcheck: design audits and diagnostics for mixed-effects models.

The registry of checks, the schemas and the test fixtures are shared with the
R package of the same name.
"""

from mixedcheck._audit import audit
from mixedcheck._declaration import validate_declaration
from mixedcheck._design import design_matrices, design_samples
from mixedcheck._errors import MixedcheckError, MixedcheckWarning
from mixedcheck._formula_ir import formula_ir
from mixedcheck._hash import (
    commitment_key_id,
    hash_bytes,
    hash_file,
    keyed_commitment,
    new_commitment_key,
)
from mixedcheck._json_read import read_json_strict
from mixedcheck._json_write import canonical_bytes, canonical_hash
from mixedcheck._registry import read_registry
from mixedcheck._results import Results, write_results
from mixedcheck._results_validate import validate_results
from mixedcheck._table import read_table
from mixedcheck._vendored import spec_versions
from mixedcheck._version import __version__
from mixedcheck._zoo import pathology_zoo

__all__ = [
    "MixedcheckError",
    "MixedcheckWarning",
    "Results",
    "__version__",
    "audit",
    "canonical_bytes",
    "canonical_hash",
    "commitment_key_id",
    "design_matrices",
    "design_samples",
    "formula_ir",
    "hash_bytes",
    "hash_file",
    "keyed_commitment",
    "new_commitment_key",
    "pathology_zoo",
    "read_json_strict",
    "read_registry",
    "read_table",
    "spec_versions",
    "validate_declaration",
    "validate_results",
    "write_results",
]
