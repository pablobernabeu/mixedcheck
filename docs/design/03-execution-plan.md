# Execution plan

This plan turns the decisions in 02-decisions.md into milestones for a single maintainer. Each milestone ends at a gate, a set of conditions that must hold before the next one starts, rather than at a date. Revise the plan whenever a gate exposes a problem, and delete items from the open-checks section once they are resolved.

Work happens in three places. Implementation runs in cloud sessions or locally. Checks that need sites blocked in the cloud sessions (CRAN, R-universe, publishers and Oxford's internal pages) run in the local session or in GitHub Actions, whose runners can install current CRAN packages. Simulation studies run on ARC. Jobs go to the htc cluster with `sbatch --clusters=htc`, never on a login node, and heavy material lives under /data/educ-intract/educ1242/.

Each component is built in R first. Rscript then writes JSON fixtures, and the Python port is developed against those fixtures. Parity is enforced at milestone gates rather than on every commit.

CI is tiered. A minimal set of jobs runs on every push, the full matrix runs nightly, and the accessibility and PDF checks run before releases.

## Milestones

| Milestone | Content | Where | Gate |
|---|---|---|---|
| M0 Foundations | Maintainer decisions and Oxford approvals, monorepo skeleton, licences, CI, vendoring checks, governance notes, repository made public | Cloud and local | Both empty packages pass CI on every platform, and each vendoring check fails on a deliberate mismatch |
| H0 Environment and pilot | Apptainer image, ARC limits, rerun of the benchmark and the ladder simulations with current engines | Local and ARC | Objective-match tolerances, memory classes and the cost of H1 re-estimated with lme4 ≥ 2.1-0 |
| M1 Specifications | Cross-cutting conventions, schema bundle, registry compiler, declaration vocabulary 0.1, IR and formula grammar, conformance corpora | Cloud | Both languages validate every corpus with identical error codes and hashes |
| M2 Stream B core | Strict readers, canonicalisation, formula parser, design matrices, T0 and T1 audits, results object and writer, pathology zoo | Cloud | Exact parity on all zoo fixtures, clean R CMD check with and without Suggests and under LC_ALL=C, and Python tests on 3.11 to 3.15 |
| M3 Plan object | Ceiling, protected set, ladder, stopping-rule menu, terminal states, design-plan hash and execution binding, preregistration text, access log, draft_design() and builders | Cloud | Identical design-plan hashes across languages on the zoo, and every plan validates |
| M3b Convergence-triage core | Optimisation statuses, scale-free rank and second-optimiser restarts for lme4 fits in R | Cloud | Statuses agree with the H0 benchmark, and the stopping rule can run end to end in R |
| R0 Release 0.x | Stream B with the results object, console output and preregistration text, privacy-filtered | Cloud and local | CRAN incoming checks pass, the name is confirmed and plans are marked 'not for preregistration' until plan versioning is in place |
| P1 Stage 1 Registered Report | Protocol for the ladder and stopping-rule study (V5 with the V3 criteria it needs) | Local | Submitted, or deposited on OSF if the regular route is chosen |
| M4 Reports | Shared Mustache renderer, view model and privacy filter, inline SVG layouts, aggregated CSV per figure, accessibility | Cloud | Golden reports agree across languages and pass axe-core and HTML validation |
| M5 Stream A (Gaussian) | Reference evaluator, adapters, objective-match gate, residual and random-effect diagnostics, plan execution, reconciliation with Stream B | Cloud | Conformance corpus passes in CI with current engines, and the check code is frozen at a v0.9 tag |
| M6 Validation, phase 1 | V1, V2, V3, V5 and V7 on ARC under preregistration | ARC | OSF deposit for V1, V2 and V7 before their runs, in-principle acceptance before the V5 runs, and results archived with a DOI |
| R1 Release 1.0 | Validated thresholds with provenance in the registry, both packages released, Stage 2 submission | Cloud and local | Every shipped threshold has validation provenance, and every other check is labelled descriptive |
| M7 JOSS paper | Software paper for both packages | Local | More than six months of public history and research use beyond the tool's own papers |
| M8 GLMMs (1.1) | R first on lme4 ≥ 2.1-0 and glmmTMB, then studies V8 to V10 | Cloud and ARC | The M5 and M6 gates applied to the GLMM checks |

Some work is deferred until after 1.0 unless a gate shows it is needed sooner:

- the .qmd export with its Typst and PDF/UA checks
- PNG export
- studies V4 and V6
- masked execution
- the dyad, EEG and intensive-longitudinal declaration blocks
- the prediction goal
- in-house Satterthwaite df

Until scheduled, each of these returns `not_available('planned <version>')`.

## Versions

| Milestone | R package | Python package | Registry and schemas |
|---|---|---|---|
| R0 | 0.1 | 0.1 | 0.1 |
| M4 | 0.2 | 0.2 | 0.2 |
| R1 | 1.0 | 1.0 | 1.0 |
| M8 | 1.1 | 1.1 | 1.1 |

Parity is defined per registry version. Both packages are released together whenever the registry's minor version changes, and patch releases may go out independently. Each results object records the package, registry, schema and canonicaliser versions.

## M0. Foundations

The maintainer settles the choices listed at the end of 02-decisions.md first, because the name appears in every file and making the repository public is a public release of its contents. The steps are:

1. Oxford's approval for open-source release and the copyright holder.
2. The name checks.
3. An update of LICENSE.
4. The repository goes public, which starts the six-month clock for JOSS.

The skeleton follows the layout in Q7. r/ holds a minimal R package: DESCRIPTION with Depends R ≥ 4.2.0 and Imports Matrix, jsonlite, cli and utf8, the two-line licence stub and testthat. python/ holds a pyproject package with a src layout, requires-python ≥ 3.11, numpy, pandas and scipy as dependencies, and empty extras. spec/, fixtures/, parity/, sim/ and paper/ exist with short README files. A .gitattributes file fixes LF line endings for every shared artefact, and REUSE-style licence files mark any directory whose contents are not MIT.

CI uses GitHub Actions with path filters. The R workflow runs R CMD check on Ubuntu (devel, release, oldrel-1 and 4.2), Windows and macOS (release), plus one job with `_R_CHECK_DEPENDS_ONLY_=true` and one under LC_ALL=C. The Python workflow runs Python 3.11 to 3.15 at both the lowest-direct and the latest resolutions. A parity workflow compares the SHA-256 of every vendored artefact with its source in spec/ or fixtures/ and fails on any mismatch. The artefacts covered are the registry, the schemas, the Mustache templates and CSS, the zoo fixtures and the conformance corpora.

Short CONTRIBUTING, code-of-conduct, governance and succession notes give JOSS the signals of open development it looks for in single-author projects. Each release is archived on Zenodo, with a CITATION file in the repository. An organisation-owned repository would also reduce the risk of depending on one person.

## H0. Environment and pilot

H0 runs in the local session, in parallel with M1, because every later budget and tolerance depends on it.

The R environment is an Apptainer image built off-cluster with portable compiler flags from a dated package snapshot. It contains R ≥ 4.5 (current glmmTMB needs it through Deriv), LC_ALL=C.UTF-8, lme4 ≥ 2.1-0, glmmTMB ≥ 1.1.15, lmerTest, pbkrtest and clubSandwich, and a Python environment with the candidate engines. The image and a lockfile are archived with every result.

On ARC, the pilot checks the R module, the Apptainer runtime, the array and QoS limits, the credit balance and the CPU feature names. It then runs three things:

- the 27-model benchmark from evidence/decisions/A/bench, which fixes the objective-match tolerances and the registered offsets
- the random-effects simulations from evidence/decisions/B/sim, which show how current lme4 handles singular rungs and cs()
- a six-task array of V1 with the real suite overhead, which fixes the memory classes and the cost of H1

## M1. Specifications

Cross-cutting conventions come first, because every reader and writer in both languages depends on them. They are:

- the six status fields
- the hash taxonomy and the two JSON profiles
- centring constants stored as decimal strings
- the split between the design-plan hash and the execution binding
- the disclosure_unit, event_level, trials and exposure fields
- the Unicode policy
- SHA-256 from cli in R

They are recorded in docs/spec/conventions.md.

One schema bundle under spec/ holds the registry entry, declaration, plan, results and estimates schemas, with shared definitions and the two profiles. The access log is a section of the results document.

A registry entry has a stable ID and version, a tier (T0, T1 or T2), the statistic and comparison exactly as computed, an assessability rule and thresholds with their sources and validation provenance. It also lists remedies, links in the dependency graph and message templates, and classifies every count it reports as a person count or a non-person count. Entries are authored in YAML, read with every scalar as a string and compiled to canonical JSON by one script under spec/tools/. The compiled JSON is the only form the packages read.

The declaration vocabulary 0.1 starts from the draft in evidence/decisions/E/schema, with the corrections recorded in 02-decisions.md.

The IR specification defines how a formula and a declaration become terms, columns and grouping factors. It covers:

- the lme4 grammar the suite accepts
- contrast coding with explicit reference levels
- centring rules and constants
- the analysis sample
- factor-level order (declared levels first, otherwise code-point order after NFC)
- the rejection of `||` on factors
- the sequential rule for dropping aliased columns

Conformance corpora sit under fixtures/conformance/. They cover formula strings with their expected IR, valid and invalid documents with expected error codes, the JSON and table edge cases from the review, Unicode and C-locale cases, and number-formatting cases.

## M2. Stream B core

Both languages implement the same pipeline:

1. strict readers for the declaration and the data
2. canonicalisation of identifiers, missing-value tokens and level order
3. the formula parser, written in-house, with reformulas used only as a test oracle in R
4. the design matrices X and Z
5. the audits
6. the results object and its writer

The T0 audits are:

- label incidence for every pair of grouping factors
- evidence on ID scope when it is undeclared
- aliased grouping factors and factors with one row per level
- within and between status with informative-group counts and predictor ICCs
- the identifiability verdict from the projected Gram matrix
- the level-specific df budget, J ≤ q and confounding with the residual when there is one observation per unit and cell
- rank deficiency and empty cells under the sequential aliasing rule
- term-level GVIF and scale disparity
- differences between the raw data and the analysis sample
- labels that differ only in Unicode form
- duplicates against the declared observation key

The T1 audits sit behind the outcome-access argument.

The pathology zoo grows from the ten prototypes to the thirty planned fixtures. Each has a clean matched negative and expectations derived from the generating design. Parsing-hazard, C-locale and attribute-consistency fixtures join it. The generators live in sim/ so that the simulation studies reuse them. Disclosure-attack tests on the privacy filter run in CI.

## M3 and M3b. Plan object and convergence triage

The ladder generator implements Q3. It freezes coding and centring, sets rung 0 and the protected set from the declared roles, applies the fixed reduction order with release-1 encodings and gives the identifiability verdict for every rung. Without declared estimands it returns the ceiling and the verdicts and labels the ladder exploratory.

The stopping-rule menu holds the localised protected back-off (the default), protected LRT(.2) and no reduction. The terminal states are 'no confirmatory model' and, in R for nested designs, CR2. The plan carries a design-plan hash and an execution binding, and the generated preregistration text lists the declarations the user must supply. `draft_design()` and the code-first builders write declarations in both languages.

M3b adds the convergence-triage core for lme4 fits in R: optimisation statuses from the gap to the best objective found, a scale-free rank criterion and second-optimiser restarts. The stopping rule then runs end to end in R, which is enough to preregister V3 and V5 and submit the Stage 1 report while M4 and M5 continue.

## R0 and P1

Stream B ships to CRAN, PyPI and R-universe as 0.1, with the results object, console output and the preregistration text, all passed through the privacy filter. Examples and tests use only bundled zoo fixtures and stay within CRAN's limits of two cores and short run times. Plans written by 0.x releases are marked 'not for preregistration' until the plan schema and canonicaliser carry versions that later releases can verify. Early users also give JOSS its evidence of research use.

P1 is the Stage 1 Registered Report, or the OSF preregistration if the maintainer chooses the regular route. It covers the ladder and stopping-rule study (V5, with the V3 criteria it depends on), and it is written in the local session from the H0 results.

## M4. Reports

The renderer is an in-house Mustache subset tested against the language-independent Mustache specification tests. A shared view model formats every number in printf style and applies the single privacy filter to everything that leaves the package: figures, alternative text, long descriptions, data tables, methods text and metadata.

Inline SVG figures use three layouts (band, bar and matrix). Their coordinates are computed by shared logic and stored in the results, and the aggregated CSV behind each figure is always written. Strings are compared exactly only for values computed from shared inputs. Other values are compared at reporting precision, with a near-threshold status.

Monorepo CI runs axe-core and an HTML validator on golden reports. Reports ship as 0.2.

## M5. Stream A for Gaussian LMMs

The reference evaluator is built in R first, on Matrix and CHOLMOD, and validated against lme4's deviance function. The Python port covers what the objective-match gate needs for statsmodels fits and bring-your-own estimates.

The adapters are:

- lme4 objects (lmerMod, lmerModLmerTest and afex mixed objects)
- statsmodels MixedLM (≥ 0.15.0), with the coefficient map built by numeric column matching
- bring-your-own JSON
- at most one experimental Rust-engine adapter, chosen by the rule in Q1

The glmmTMB method is registered and returns `not_available('planned 1.1')`. The availability guard sits in the generic, and a test diagnoses a saved .rds fit with lme4 absent.

The diagnostics are:

- the objective-match gate with registered tolerances and offsets
- convergence triage from M3b, with a boundary probe for small q
- marginal, conditional and studentised residuals with P-based quantities
- predicted random effects with both conditional variances labelled
- heteroscedasticity by cluster-size stratum on studentised residuals
- within-unit semivariograms
- cluster influence by one-step approximation, with exact refits as an option
- the design df everywhere and Satterthwaite df through lmerTest in R only, labelled engine-specific

Stream A executes a Stream B plan in both languages, logs every rung and reports the selected model, the protected rung and the adjacent rung as pre-declared sensitivity analyses. When rung 0 cannot be expressed in statsmodels, Python returns not_available and names the bring-your-own and R routes. When a plan file is supplied, Stream A reconciles the plan with the fitted model by hash.

The benchmark becomes the conformance corpus under fixtures/conformance/engines/. Simulated data are committed, real datasets are generated by Rscript in CI, and reference values come from current CRAN versions. The gate freezes the check code at a v0.9 tag, which is the version the preregistrations describe.

## M6. Validation, phase 1

All simulation programmes share one codebase in sim/. The zoo generators serve as the data-generating mechanisms, with one SLURM runner, one results schema and one register of studies with memory classes. The SLURM templates, cost model and protocol tables in evidence/decisions/F and F-verify are its starting point.

Studies V1, V2 and V7 are preregistered on OSF and run once the v0.9 code is frozen. V3 and V5 run after in-principle acceptance of the Stage 1 report. V2 starts with the priority modules:

- the omitted slope
- the omitted randomisation level in cluster-randomised trials
- reused nested labels
- small-cluster heteroscedasticity
- the conflation of within and between effects
- influence, with exact refits only in its own module at 2,000 replicates
- residual autocorrelation

V7 includes agreement on the rung reached in nested and crossed variance-component designs, and the conformance study of engines runs as a separate memory class, with one large-n timing study on a high-memory node. Thresholds are set on the calibration half, confirmed on the held-out half with the metamodel rule and written into the registry with their provenance. Python takes on the validated thresholds only once V7 shows that both languages compute the same statistics. Python Stream A development continues while the phase 1 jobs run.

Each study is a SLURM job array on the htc short partition. Each task gets one core and 2 GB unless its memory class says otherwise, and tasks run for 2 to 4 hours, with at most 500 tasks per array and a concurrency throttle. Each chunk uses an L'Ecuyer-CMRG stream and each replicate a substream.

Chunks write to $SCRATCH and are copied to /data/educ-intract/educ1242/<package>-sim/, and completion is checked against that directory. Raw replicate results are mirrored off ARC and archived with a DOI, because ARC keeps no backups.

## R1, M7 and M8

Release 1.0 ships both packages. Checks are ranked by V2 priority early on, so that it is known in advance which ones will ship as descriptive if phase 1 runs late. The Stage 2 report and the regular preregistered article report phase 1. Cross-engine conformance results belong to V7 in the validation paper, and the JOSS paper describes only the software.

GLMM support (1.1) is built in R first, on lme4 ≥ 2.1-0 and glmmTMB, using the engines' objective functions or a Laplace and AGQ evaluator written in R. It covers:

- Gaussian glmmTMB fits
- simulation-based quantile residuals with shared draws for parity
- dispersion and zero checks against predeclared candidate families
- the separation check in Stream A

Studies V8 to V10 validate them. Python GLMMs remain bring-your-own until a Rust engine meets the promotion rule.

## Risks

| Risk | Mitigation |
|---|---|
| Maintainer capacity | Milestone gates, Stream B released first, R built first, GLMMs after 1.0, the deferred list above, and scope cut at a gate rather than spread thin |
| Two numerical cores | Evaluator built and validated in R, with the Python port limited to what the objective-match gate needs |
| Upstream changes, from lme4 defaults and glmmTMB scales to statsmodels naming and young Rust engines | Engines in Suggests and extras, objective-match gate, expected-disagreement registry, conformance corpus in CI against current releases, experimental adapters non-gating with upper version bounds, sentinel validation cells rerun at major engine releases |
| Parity drift | One schema bundle, shared corpora, exact parity for deterministic outputs, tolerance tiers per output, golden tests in both packages |
| CI growth to about 30 jobs | Tiered CI: a minimal set on every push, the full matrix nightly, accessibility and PDF checks before releases |
| Certification creep, with clean reports treated as approval | No badges, scores or 'assumptions were met', a statement of what could not be assessed in every report, and banned phrases in generated text |
| Option shopping among contested methods | Choices declared in the plan before the outcome is seen, alternatives reported in a fixed order, a log of views generated |
| Disclosure of participant data | One privacy filter, keyed commitments in place of hashes, an internal sidecar, shareable files by default, disclosure tests in CI, and the data protection officer's view obtained in writing |
| CRAN archival | Small hard dependency closure, engine tests skipped when engines are absent, fit-based goldens kept off CRAN, files written only to tempdir() in examples and tests |
| JOSS scrutiny of a single-author project, and a bus factor of one | Public history from M0, releases, tests, CI, governance and succession notes, research use in the maintainer's own analyses |
| AI-assisted code reproducing GPL source | Clean-room rule, a provenance entry for every algorithm that records any AI assistance, and the AI-usage disclosure that JOSS requires |
| Reference-checking backlog | One block in the local session before any preregistration, with full reads of the papers listed below |

## Open checks

Each item needs the local session, CI with network access or ARC. Delete an item once it is resolved, and record the outcome in 02-decisions.md if it changes a decision.

Maintainer decisions and Oxford procedures:

- the choices at the end of 02-decisions.md
- Oxford's rules on copyright and open-source release
- the data protection officer's view on publishing shareable reports
- where any restricted data may be analysed, and under which agreement

Registries and current software:

- `pak::pkg_name_check()` and the R-universe search for the chosen name
- the live CRAN policy revision
- the H0 reruns with current engines
- R 4.2.0, 4.2.3 and 4.3.3 in rocker images, testing whether lme4 2.x installs with the bundled Matrix
- optional tests of pymer4 through conda, MixedModels.jl through juliacall and fastglmm from R-universe

ARC: module and Apptainer availability, array and QoS limits, the credit allocation for the project and the CPU feature names.

Venues and policies:

- JSS's policy on software already published in JOSS
- Registered Report acceptance for simulation studies at Behavior Research Methods and AMPPS
- Oxford's coverage under the Springer Nature and APA open-access agreements
- the AMPPS article charge

Privacy and reporting standards:

- the primary UK output-checking guidance (ONS Secure Research Service, DfE and the SDC Handbook)
- the ICO's anonymisation guidance
- the identifiability provisions of the Data (Use and Access) Act 2025
- the wording of the CONSORT 2010 cluster extension and whether a cluster extension aligned with CONSORT 2025 exists
- Quarto's alternative-text behaviour for Word and Typst
- browser support for tagged print-to-PDF
- screen-reader testing of a prototype report

Data licences: OSF project 4p8hz, LSHTM Data Compass, Many Labs 2, the ERP CORE terms and the openESM datasets.

These papers need reading in full before their content is used. They are in the evidence tables but not yet cited as sources:

- Meteyard and Davies (2020), the checklist and survey figures
- Bono et al. (2021), the GLMM reporting rates
- Matuschek et al. (2017), the design and the α of .2
- Barr et al. (2013), the Type I error figures
- Scandola and Tidoni (2024), the procedure and simulation grids
- Luo and Li (2023)
- Eager and Roy (2017), the conditions
- Greven and Kneib (2010)
- Oberauer (2022)
- Verissimo (2023)
- Seedorff et al. (2019)
- Goldstein et al. (1993), for the Exam data
- Flay et al. (1988), for the smoking-prevention trial
- the boundary-test, residual and Laplace-accuracy papers listed in evidence/decisions/F/tables/open_items_local_session.csv

Some metadata are still incomplete: the DOI of Bradley (1978), the issue and pages of Siepe et al. (2024), the page range of the pbkrtest article and the DOIs flagged in evidence/decisions/A-verify.
