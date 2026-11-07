# Evidence for the decision record

Outputs of the November 2026 evidence workflow behind ../../02-decisions.md. Six research agents each answered a group of open questions with literature, documentation, source code and their own experiments. One adversarial verifier per report re-ran experiments, checked claims and checked every reference. A consistency critic then reviewed the decisions together.

`reports.json` holds every structured report and verification verdict. Where a verifier's change differs from the report, the verifier's change was adopted in the decision record.

| Folder | Question | Contents |
|---|---|---|
| A, A-verify | Q1 Python engines | 27-model benchmark against lme4 1.1-35.1 and glmmTMB 1.1.8 (scripts, reference JSON, comparison rows), capability and maintenance tables, contract and parity-tier draft |
| B, B-verify | Q3 Stream B output | Literature extraction, own simulations (Sim 1-6, verifier's v2 and v3), HPC simulation plan (H1-H10), plan-object example |
| C, C-verify | Q2 model scope, Q5 reports | Model-class matrix and roadmap, report outputs, plot types, privacy and accessibility defaults, plot-leakage and warning-rate experiments |
| D, D-verify | Q6, Q7, Q10 | Dependency footprints, Suggests experiment, name availability, monorepo precedents, version and licence notes |
| E, E-verify | Q4 declarations, Q8 data | Declaration schema draft with valid, invalid and edge-case files, inference experiments, dataset table, pathology-zoo prototype (10 fixtures) and parsing-hazard corpus |
| F, F-verify | Q9 validation and papers | Validation protocol (V0-V10), Monte Carlo SE targets, venue table, timing data, cost model and budget scenarios, SLURM templates and pilot |

Limitations. R results came from Ubuntu 24.04's R 4.3.3 with lme4 1.1-35.1 and glmmTMB 1.1.8, which predate lme4 2.x and glmmTMB 1.1.9 to 1.1.15. Behaviour of current versions was checked from source only. CRAN, R-universe, publisher sites, doi.org and Crossref were unreachable, and the web-search budget ran out during verification, so many references in these files are unverified. Only references listed in ../../02-decisions.md were confirmed for that document. Datasets distributed with lme4 and glmmTMB were deliberately left out, because those packages are GPL- or AGPL-licensed; `A/bench/r_reference.R` regenerates them from R. Absolute paths under /tmp refer to the ephemeral environment in which the scripts ran, and email addresses have been redacted.
