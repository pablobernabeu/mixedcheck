"""mixedcheck: design audits and diagnostics for mixed-effects models.

The registry of checks, the schemas and the test fixtures are shared with the
R package of the same name.
"""

from mixedcheck._declaration import validate_declaration
from mixedcheck._errors import MixedcheckError, MixedcheckWarning
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
from mixedcheck._vendored import spec_versions

__version__ = "0.0.0.dev0"

__all__ = [
    "MixedcheckError",
    "MixedcheckWarning",
    "__version__",
    "canonical_bytes",
    "canonical_hash",
    "commitment_key_id",
    "hash_bytes",
    "hash_file",
    "keyed_commitment",
    "new_commitment_key",
    "read_json_strict",
    "read_registry",
    "spec_versions",
    "validate_declaration",
]
