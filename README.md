# mixedcheck

A pair of packages, one for R and one for Python, for auditing designs before fitting mixed-effects models and for diagnosing and reporting fitted models. Both packages share one registry of checks and one results schema. The repository, created as lmecheck, holds the design, the specifications and the two packages, which so far read, write and hash the shared JSON documents, validate declarations, read data tables and build the canonical IR and design matrices of a model. The R package also audits the design of a model and writes and validates the results, and neither package diagnoses fitted models yet. Nothing has been released.

## Design

- [Design review](docs/design/01-design-review.md): critical review of the architecture, edge cases and additional features
- [Decision record](docs/design/02-decisions.md): resolved design questions, with evidence and the choices left to the maintainer
- [Execution plan](docs/design/03-execution-plan.md): milestones and gates, validation on the HPC, risks and open checks
- [Review catalogue](docs/design/evidence/review-catalogue.md): the 152 verified review items behind the design review
- [Evidence for the decisions](docs/design/evidence/decisions/README.md): benchmark, simulations, schemas, prototypes, research reports and verification verdicts behind the decision record
- [Specifications](docs/spec/conventions.md): the conventions, [error codes](docs/spec/errors.md), [declarations](docs/spec/declarations.md), [registry](docs/spec/registry.md), [results, plans and estimates](docs/spec/documents.md), [privacy filter](docs/spec/privacy.md), [canonical IR and formula grammar](docs/spec/ir.md) and [data tables](docs/spec/tables.md)
- [Provenance log](docs/provenance.md): the sources of each algorithm and any AI assistance in writing the code

## Layout

| Directory | Contents |
|---|---|
| [r/](r/README.md) | the R package |
| [python/](python/README.md) | the Python package |
| [spec/](spec/README.md) | the shared specification, with the script that vendors it into both packages |
| [fixtures/](fixtures/README.md) | the shared test fixtures |
| [parity/](parity/README.md) | the cross-language harness |
| [sim/](sim/README.md) | the validation studies on the HPC |
| [paper/](paper/README.md) | the JOSS paper |
| docs/ | the design documents in docs/design/, the specifications in docs/spec/ and the provenance log |

## Changes

- [Changelog](CHANGELOG.md): notable changes to the design and the shared specification
- [r/NEWS.md](r/NEWS.md): changes to the R package
- [python/CHANGELOG.md](python/CHANGELOG.md): changes to the Python package

## Contributing

[CONTRIBUTING.md](.github/CONTRIBUTING.md) explains how to run the checks and how shared artefacts are vendored. Decisions are taken as described in [GOVERNANCE.md](.github/GOVERNANCE.md), participation follows the [Code of Conduct](.github/CODE_OF_CONDUCT.md) and security problems are reported as described in [SECURITY.md](.github/SECURITY.md).

The repository is MIT-licensed, except for third-party material identified in the evidence for the decisions.
