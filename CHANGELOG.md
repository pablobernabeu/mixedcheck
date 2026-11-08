# Changelog

Notable changes to the design of mixedcheck are recorded here, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The [design review](docs/design/01-design-review.md) tests the original two-stream architecture against statsmodels 0.15.0 and the sources of lme4, glmmTMB, performance and insight, lists the edge cases with the greatest consequences and closes with ten questions. The [review catalogue](docs/design/evidence/review-catalogue.md) keeps the 152 verified items behind it.
- The [decision record](docs/design/02-decisions.md) answers the ten questions, marks each answer 'Decided', 'Provisional' or 'Maintainer' and defines the conventions shared by both packages: six status fields, a hash taxonomy with keyed commitments for person-level data, two JSON profiles and the handling of UTF-8 and NFC.
- The [evidence for the decisions](docs/design/evidence/decisions/README.md) is the frozen record of the November 2026 research reports, their verifiers and a consistency critic: a 27-model engine benchmark, simulations, declaration schemas, a pathology-zoo prototype, SLURM templates and a cost model.
- The [execution plan](docs/design/03-execution-plan.md) turns the decisions into gated milestones, from the repository skeleton (M0) to GLMM support (M8), with validation on ARC, risks and open checks.

### Changed

- The maintainer chose mixedcheck as the name of both packages, with lmecheck as the fallback, subject to the remaining registry checks. The repository is to be renamed before it goes public.
- After the consistency critic, the plan carries a language-neutral design-plan hash and an engine-specific execution binding, declares a terminal state for a failed protected rung and uses only encodings that every 1.0 engine can express. R gains cli and utf8 as Imports. The execution plan builds each component in R first, runs the H0 environment pilot alongside M1 and places the R convergence-triage core (M3b) before the Stage 1 Registered Report.
- The roadmap returns lognormal models to version 1.2 and makes zero-inflated and hurdle models candidates for version 2. The separation check runs in M2 as an exploratory T2 audit, and the shared view model and privacy filter move into M2. V7 includes an engine conformance study whose regenerated parity tiers gate 1.0.
- A rung that an engine cannot express is reported as not_available with its reason. The unprotected back-off is available only by explicit opt-in, and the first 0.x release ships neither it nor protected AIC. Point-level detail appears only in internal mode. Only a Rust-based engine can become the supported Python engine, and gpboost may serve only as an engine-specific adapter.
- Each topic is stated fully in one document and referred to from the others. The decision record owns the decisions and their evidence, the execution plan owns sequencing, environments, risks and open checks, and the evidence README describes the evidence workflow.
- The design documents, the READMEs and the review catalogue were revised for plain British English, with paragraphs regrouped by topic and status values written as their defined identifiers.

### Fixed

- Benchmark (Q1): the common objective reproduced lme4's LMM criteria and glmmTMB's unweighted ones to within 4e-10, but glmmTMB's weighted criteria differed by about 2,134 units and lme4 1.1-35.1's Laplace values by up to 1.6e-3. statsmodels could not represent eight of the 27 models and was 24 to 27 times slower than lme4 on crossed variance components. The verifier's 200 random starts on each of five small designs found no objective more than 1e-12 below the engines' best, where the record had claimed a confirmed global optimum.
- Validation and cost (Q9): the acceptable band of .025 to .075 rests on Bradley's liberal criterion as a whole, the small-cluster heteroscedasticity check gave false-flag rates of .07 to .18 with raw residuals, and the central Phase 1 estimate of about 1,140 CPU-hours includes about 100 for V4 and V6. Compute stops being a constraint only once the project's ARC credit is confirmed.
- Other figures and attributions: the hash-oracle test recovered a whole outcome column of 20 pupils in 1.6 s, the zoo has nine prototyped fixtures and one matched negative, the 94-package closure is that of DHARMa with Matrix, jsonlite and lme4, Barr (2013) is cited for the interaction slope in the protected set, and the design review corrects its statements on formulaic's handling of emptied factor levels and on the precision of pandas' `to_json()`.
- References: Bradley (1978) gains its issue and DOI, and the evidence README records corrected metadata for Halekoh and Højsgaard (2014), Seabold and Perktold (2010) and Harville (1977), with an erratum for report A's Laplace result.
- The evidence README maps `reports.json` to the folders, lists the scripts with hard-coded paths, the material that was not kept and the byte-identical files, and identifies third-party material. Report F's copy of the JOSS submission guide was removed, because its licence notice was missing.
