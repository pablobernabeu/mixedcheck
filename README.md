# mixedcheck

A planned pair of packages, one for R and one for Python, for auditing designs before fitting mixed-effects models and for diagnosing and reporting fitted models. Both packages share one registry of checks and one results schema. The repository, created as lmecheck, currently holds the design.

- [Design review](docs/design/01-design-review.md): critical review of the architecture, edge cases and additional features
- [Decision record](docs/design/02-decisions.md): resolved design questions, with evidence and the choices left to the maintainer
- [Execution plan](docs/design/03-execution-plan.md): milestones and gates, validation on the HPC, risks and open checks
- [Review catalogue](docs/design/evidence/review-catalogue.md): the 152 verified review items behind the design review
- [Evidence for the decisions](docs/design/evidence/decisions/README.md): benchmark, simulations, schemas, prototypes, research reports and verification verdicts behind the decision record
- [Changelog](CHANGELOG.md): notable changes to the design

The repository is MIT-licensed, except for third-party material identified in the evidence for the decisions.
