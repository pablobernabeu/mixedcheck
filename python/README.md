# mixedcheck (Python)

The Python package of mixedcheck, which audits study designs before mixed-effects models are fitted and diagnoses and reports fitted models. It shares the registry of checks, the schemas and the test fixtures with the R package of the same name, and each component is ported from the R implementation against shared JSON fixtures.

The package is in development and has not been released. So far it provides `mixedcheck.spec_versions()`, which returns the versions of the shared specification installed with the package.

```python
import mixedcheck

mixedcheck.spec_versions()
```

It needs Python 3.11 or later, with numpy, pandas and scipy. To install it from a clone of the repository:

```bash
python -m pip install ./python
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design documents and both packages. Changes are listed in [CHANGELOG.md](https://github.com/pablobernabeu/lmecheck/blob/main/python/CHANGELOG.md). The package is MIT-licensed.
