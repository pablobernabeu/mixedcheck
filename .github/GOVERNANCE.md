# Governance

mixedcheck has one maintainer, Pablo Bernabeu, who takes the decisions about the
project: its scope, its design, what is merged and when it is released.

## How decisions are recorded

Design decisions are recorded in `docs/design/`. The decision record
(`02-decisions.md`) gives each decision, the evidence behind it and its status:
'Decided' when the evidence settles the question, 'Provisional' when a named
check could still change it and 'Maintainer' when the choice rests with the
maintainer. The execution plan (`03-execution-plan.md`) records the milestones,
their gates, the risks and the open checks. A change to a decision is made by
editing these documents and is listed in the root `CHANGELOG.md`.

Anyone may propose a change by opening an issue or a pull request. Proposals are
discussed there, and the maintainer decides.

## Succession

No successor is named. If the maintainer can no longer maintain the packages,
the repository will be archived with a notice in its README, and the packages
will stay at their last releases. The MIT licence lets anyone continue the work
in a fork, under another name.
