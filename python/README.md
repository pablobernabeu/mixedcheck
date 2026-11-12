# mixedcheck (Python)

The Python package of mixedcheck, which audits study designs before mixed-effects models are fitted and diagnoses and reports fitted models. It shares the registry of checks, the schemas and the test fixtures with the R package of the same name, and each component is ported from the R implementation against shared JSON fixtures.

The package is in development and has not been released. So far it provides `mixedcheck.spec_versions()`, which returns the versions of the shared specification installed with the package, the layer that every reader and writer of the package builds on, the data layer of the audits, which reads tables and builds the canonical model and its design matrices, and the audits themselves:

- `read_json_strict()` reads JSON in the hashable or data profile and reports the first problem with a stable code.
- `canonical_bytes()` writes a value by RFC 8785, with numbers in ECMAScript's shortest form, and `canonical_hash()` returns the SHA-256 hash of those bytes. `hash_bytes()` and `hash_file()` hash bytes and files.
- `new_commitment_key()`, `commitment_key_id()` and `keyed_commitment()` create commitment keys and HMAC-SHA-256 keyed commitments.
- `validate_declaration()` checks a design declaration written in JSON, in YAML (with the extra 'yaml') or in memory, and returns it, so that `canonical_hash()` gives its declaration hash.
- `read_registry()` returns the registry of checks installed with the package.
- `read_table()` reads a CSV file with the strict table reader, under the table block of a declaration or with the types inferred from the values, and returns a pandas DataFrame whose columns have dtype object, with None for a missing value, so that missing values stay apart from NaN and integers stay exact.
- `formula_ir()` parses an lme4-style formula and builds the canonical IR of the model, whose `canonical_hash()` is its IR hash, and `design_matrices()` builds its design and analysis samples, X, the sparse Z as a `scipy.sparse.csc_array` and the response, trials, offset and weight vectors. `design_samples()` returns the two samples alone.
- `audit()` runs the checks of the registry on the design of a model in the 14 steps of the [execution plan](https://github.com/pablobernabeu/lmecheck/blob/main/docs/design/03-execution-plan.md) (M2) and returns a `Results` object, whose printed form shows the banner of its privacy mode and one line for each finding, with the results document and its internal sidecar. `write_results()` writes the document as its canonical bytes and the sidecar, which holds the commitment key, under file names that show which file may be shared. Internal mode writes every value, so that its documents must stay on the analyst's machine. Shareable mode, the default, passes the findings through the privacy filter, which the package does not have yet, so that a shareable run stops with an internal error.
- `validate_results()` validates a results document, from a file, in memory or in a `Results` object, and verifies its internal sidecar against it and, given the data of the run, every commitment that it records.

A problem is raised as `mixedcheck.MixedcheckError`, a subclass of ValueError, whose `issues` hold the codes of the shared error catalogue with their messages and locations. The functions have the same names and arguments as in the R package and give the same codes, bytes and hashes. `design_matrices()` and `design_samples()` number rows, and `design_matrices()` random terms, from 0 in Python and from 1 in R, whereas indices inside the IR count from 0 in both, and a missing value is None in Python and `NA` in R. The tests run every case of the JSON, number, Unicode, hash, HMAC, declaration, YAML, table and formula corpora, every case of the audit corpus in internal mode and every case of the results corpus. The [parity harness](https://github.com/pablobernabeu/lmecheck/tree/main/parity) of the repository checks that both packages agree on every case of the corpora, apart from the shareable runs of the audit corpus, which wait for the privacy filter.

```python
import tempfile
from pathlib import Path

import mixedcheck

mixedcheck.spec_versions()
value = mixedcheck.read_json_strict(b'{"b": [1.50, true], "a": "x"}', "hashable")
mixedcheck.canonical_bytes(value, "hashable")
mixedcheck.canonical_hash(value, "hashable")
declaration = mixedcheck.validate_declaration({"vocabulary": "0.1.0", "goal": "exploratory"})
mixedcheck.canonical_hash(declaration, "hashable")
path = Path(tempfile.mkdtemp()) / "data.csv"
path.write_bytes(b"id,cond,rt\n1,A,512.5\n2,B,\n3,A,498\n4,B,530\n")
table = mixedcheck.read_table(path)
table.attrs["types"]
ir = mixedcheck.formula_ir("rt ~ cond", data=table)
mixedcheck.canonical_hash(ir, "hashable")
mixedcheck.design_matrices(ir, table)["x"]
```

An audit in internal mode, with a commitment key given so that the document can be repeated:

```python
import pandas as pd

data = pd.DataFrame(
    {
        "y": [2.1, 3.4, 1.8, 2.9, 3.3, 4.1],
        "x": [1, 2, 3, 4, 5, 6],
        "subject": ["s1", "s1", "s2", "s2", "s3", "s3"],
        "trial": [1, 2, 1, 2, 1, 2],
    }
)
declaration = {"vocabulary": "0.1.0", "observation": {"key": ["subject", "trial"]}}
results = mixedcheck.audit(
    data, "y ~ x + (1 | subject)", declaration, privacy="internal", key=bytes(range(32)).hex()
)
print(results)
directory = Path(tempfile.mkdtemp())
path = directory / "audit.internal.json"
sidecar = directory / "audit.sidecar.internal.json"
mixedcheck.write_results(results, path, sidecar)
# The document and its sidecar are valid, and the commitments agree with the data.
mixedcheck.validate_results(path, sidecar, data, declaration)
```

It needs Python 3.11 or later, with numpy, pandas and scipy. To install the package from a clone of the repository, with PyYAML for declarations written in YAML:

```bash
python -m pip install "./python[yaml]"
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design documents and both packages. Changes are listed in [CHANGELOG.md](https://github.com/pablobernabeu/lmecheck/blob/main/python/CHANGELOG.md). The package is MIT-licensed.
