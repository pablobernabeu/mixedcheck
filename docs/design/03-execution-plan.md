# Execution plan

This plan turns the decisions in 02-decisions.md into milestones for a single maintainer. Each milestone ends at a gate, a set of conditions that must hold before the next one starts, rather than at a date. Revise the plan whenever a gate exposes a problem.

Work happens in three places. Implementation runs in cloud sessions or locally. Checks that need sites blocked in the cloud sessions (CRAN, R-universe, publishers and Oxford's internal pages) run in the local session or in GitHub Actions, whose runners can install current CRAN packages. Simulation studies run on ARC. Jobs go to the htc cluster with `sbatch --clusters=htc`, never on a login node, and large files are kept under /data/educ-intract/educ1242/.

Each component is built in R first. Rscript then writes JSON fixtures, and the Python port is developed against those fixtures. Parity is enforced at milestone gates rather than on every commit.

## Milestones

| Milestone | Content | Where | Gate |
|---|---|---|---|
| M0 Foundations | Maintainer decisions and Oxford approvals, monorepo skeleton, licences, CI, vendoring checks, governance notes, repository made public | Cloud and local | Both empty packages pass CI on every platform, and each vendoring check fails on a deliberate mismatch |
| H0 Environment and pilot | Apptainer image, ARC limits, rerun of the benchmark and the ladder simulations with current engines | Local and ARC | Objective-match tolerances, memory classes and the cost of H1 re-estimated with lme4 ≥ 2.1-0 |
| M1 Specifications | Cross-cutting conventions, schema bundle, registry compiler, declaration vocabulary 0.1, IR and formula grammar, conformance corpora | Cloud | Both languages validate every corpus with identical error codes and hashes |
| M2 Stream B core | Strict readers, canonicalisation, formula parser, design matrices, T0 and T1 audits, the exploratory T2 separation check, results object and writer, view model and privacy filter, pathology zoo | Cloud | Exact parity on all zoo fixtures, clean R CMD check with and without Suggests and under LC_ALL=C, and Python tests on 3.11 to 3.15 |
| M3 Plan object | Ceiling, protected set, ladder, stopping-rule menu, terminal states, design-plan hash and execution binding, preregistration text, access log, draft_design() and builders | Cloud | Identical design-plan hashes across languages on the zoo, and every plan validates |
| M3b Convergence-triage core | Optimisation statuses, scale-free rank and second-optimiser restarts for lme4 fits in R | Cloud | Statuses agree with the H0 benchmark, and every step of the stopping rule runs in R |
| R0 Release 0.x | Stream B with the results object, console output and preregistration text, privacy-filtered | Cloud and local | CRAN incoming checks pass, the name is confirmed and plans are marked 'not for preregistration' until plan versioning is in place, and every unvalidated thresholded check is labelled descriptive |
| P1 Stage 1 Registered Report | Protocol for the ladder and stopping-rule study (V5 with the V3 criteria it needs) | Local | Submitted, or deposited on OSF if the regular route is chosen |
| M4 Reports | Shared Mustache renderer, inline SVG layouts, aggregated CSV per figure, accessibility | Cloud | Golden reports agree across languages and pass axe-core and HTML validation |
| M5 Stream A (Gaussian) | Reference evaluator, adapters, objective-match gate, residual and random-effect diagnostics, plan execution, reconciliation with Stream B | Cloud | Conformance corpus passes in CI with current engines, and the check code is frozen at a v0.9 tag |
| M6 Validation, phase 1 | V1, V2, V3, V5 and V7 on ARC under preregistration | ARC | OSF deposit for V1, V2 and V7 before their runs, in-principle acceptance (or OSF deposit on the regular route) before the V3 and V5 runs, and results archived with a DOI |
| R1 Release 1.0 | Validated thresholds with provenance in the registry, both packages released, Stage 2 submission | Cloud and local | Every shipped threshold has validation provenance, every other check is labelled descriptive, and parity tiers have been regenerated with current engines |
| M7 JOSS paper | Software paper for both packages | Local | More than six months of public history and research use beyond the tool's own papers |
| M8 GLMMs (1.1) | R first on lme4 ≥ 2.1-0 and glmmTMB, then studies V8 to V10 | Cloud and ARC | The M5 and M6 gates applied to the GLMM checks |

Some work is deferred until after 1.0 unless a gate shows it is needed sooner:

- the .qmd export with its Typst and PDF/UA checks
- optional PNG copies of the aggregated figures
- studies V4 and V6
- masked execution
- the dyad, EEG, imputation and intensive-longitudinal declaration blocks
- the prediction goal
- in-house Satterthwaite df
- the further families of version 1.2 (02-decisions.md, Q2)
- the structured covariance terms of version 1.3, with the rungs that use them and the calibration of the within-unit semivariogram check (02-decisions.md, Q2 and Q3)

Until scheduled, each deferred package feature returns `not_available('planned <version>')`, and a validator for vocabulary 0.1 rejects the deferred declaration blocks as unknown keys.

## Versions

| Milestone | R package | Python package | Registry and schemas |
|---|---|---|---|
| R0 | 0.1 | 0.1 | 0.1 |
| M4 | 0.2 | 0.2 | 0.2 |
| R1 | 1.0 | 1.0 | 1.0 |
| M8 | 1.1 | 1.1 | 1.1 |

Parity is defined per registry version. The two packages are released together or separately under the rule in Q7 (02-decisions.md). Each results object records the package, registry, schema and canonicaliser versions.

## M0. Foundations

The package name is settled as mixedcheck (02-decisions.md, Q7), and development proceeds in the private repository. Before the repository goes public, which is a public release of its contents, these steps follow in order:

1. Oxford's approval for open-source release and the copyright holder.
2. The name checks.
3. An update of LICENSE.
4. The repository is renamed mixedcheck and goes public, which starts the six months of public history that JOSS requires.

The skeleton follows the layout in Q7. r/ holds a minimal R package: DESCRIPTION with Depends R ≥ 4.2.0 and Imports Matrix, jsonlite, cli and utf8, the two-line licence stub and testthat (02-decisions.md, Q6 and Q10). python/ holds a pyproject package with a src layout, requires-python ≥ 3.11, numpy, pandas and scipy as dependencies, and empty extras. spec/, fixtures/, parity/, sim/ and paper/ exist with short README files. A .gitattributes file fixes LF line endings for every shared artefact, and REUSE-style licence files mark any directory whose contents are not MIT.

CI uses GitHub Actions with path filters. The R and Python workflows run the job matrix of Q10, and a vendoring workflow runs the SHA-256 check of Q7 on every vendored artefact (02-decisions.md). A minimal set of jobs runs on every push, the full matrix runs nightly, and the accessibility and PDF checks run before releases.

Short CONTRIBUTING, code-of-conduct, governance and succession notes give JOSS the signals of open development it looks for in single-author projects. Each release is archived on Zenodo, with a CITATION file in the repository. An organisation-owned repository would also reduce the risk of depending on one person.

## H0. Environment and pilot

H0 runs in the local session, in parallel with M1, because every later budget and tolerance depends on it.

The R environment is an Apptainer image built off-cluster with portable compiler flags from a dated package snapshot. It contains R ≥ 4.5, which current glmmTMB needs through Deriv and which ARC's documented module, R 4.4.0, does not provide. It also sets LC_ALL=C.UTF-8 and contains lme4 ≥ 2.1-0, glmmTMB ≥ 1.1.15, lmerTest, pbkrtest and clubSandwich, and a Python environment with the candidate engines. The image and a lockfile are archived with every result.

On ARC, the pilot checks the R module, the Apptainer runtime, the array and QoS limits, the project's credit allocation and the CPU feature names. It then runs four things:

- the 27-model benchmark from evidence/decisions/A/bench, which fixes the objective-match tolerances and the registered offsets
- the random-effects simulations from evidence/decisions/B/sim, which show how current lme4 handles singular rungs and cs()
- a six-task array of V1 with the real suite overhead, which fixes the speed multiplier and the memory classes
- a timing run of the stopping-rule walk on H1 cells, with a second optimiser and suite derivatives at every rung, which re-costs H1

## M1. Specifications

Cross-cutting conventions come first, because every reader and writer in both languages depends on them. They are recorded in docs/spec/conventions.md and cover:

- the six status fields
- the hash taxonomy and the two JSON profiles
- centring constants stored as decimal strings
- the split between the design-plan hash and the execution binding
- the disclosure_unit, event_level, trials and exposure fields
- the Unicode policy
- SHA-256 from cli in R
- RFC 8785 serialisation with ECMAScript number formatting, written in-house and tested against the RFC's vectors

One schema bundle under spec/ holds the registry entry, declaration, plan, results and estimates schemas, with shared definitions and the two profiles. The access log is a section of the results document. The declaration vocabulary 0.1 starts from the draft in evidence/decisions/E/schema, with the corrections recorded in 02-decisions.md.

A registry entry has a stable ID and version, a tier (T0, T1 or T2), the statistic and comparison exactly as computed, an assessability rule and thresholds with their sources and validation provenance. It also lists remedies, links in the dependency graph and message templates, and classifies every count it reports as a person count or a non-person count. Entries are authored in YAML, read with every scalar as a string and compiled to canonical JSON by one script under spec/tools/. The compiled JSON is the only form the packages read.

The IR specification defines how a formula and a declaration become terms, columns and grouping factors. It covers:

- the lme4 grammar the suite accepts
- contrast coding with explicit reference levels
- centring rules and constants
- the analysis sample
- factor-level order (declared levels first, otherwise code-point order after NFC)
- the rejection of `||` on factors
- the sequential rule for dropping aliased columns

Conformance corpora sit under fixtures/conformance/. They cover formula strings with their expected IR, valid and invalid documents with expected error codes, Unicode and C-locale cases and number-formatting cases. They also include the JSON and table edge cases in evidence/decisions/E/schema/edge and evidence/decisions/E-verify (edge/ and edgezoo/).

## M2. Stream B core

Both languages implement the same pipeline:

1. strict readers for the declaration and the data
2. canonicalisation of identifiers, missing-value tokens and level order
3. the formula parser, written in-house, with reformulas used only as a test oracle in R
4. the design matrices X and Z
5. the audits
6. the results object and its writer
7. the shared view model with its privacy filter

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

The T1 audits require the outcome-access argument, and the separation check runs as an exploratory T2 audit (02-decisions.md, Q2 and Q3).

The pathology zoo grows from nine prototyped fixtures, one of them (Z01) with its matched negative, to the thirty fixtures specified in Q8 (02-decisions.md). The generators live in sim/ so that the simulation studies reuse them. Disclosure-attack tests on the privacy filter run in CI.

## M3 and M3b. Plan object and convergence triage

M3 implements what Q3 (02-decisions.md) lists for the first 0.x release, and `draft_design()` and the code-first builders of Q4 write declarations in both languages. M3b adds the convergence-triage core for lme4 fits in R: optimisation statuses from the gap to the best objective found, a scale-free rank criterion and second-optimiser restarts. Every step of the stopping rule then runs in R, which is enough to preregister V3 and V5 and submit the Stage 1 report while M4 and M5 continue.

## R0 and P1

Stream B ships to CRAN, PyPI and R-universe as 0.1, with the results object, console output and the preregistration text, all passed through the privacy filter. Examples and tests use only bundled zoo fixtures and stay within CRAN's limits of two cores and short run times. Early users also give JOSS its evidence of research use.

P1 is the Stage 1 Registered Report, or the OSF preregistration if the maintainer chooses the regular route (02-decisions.md, Q9). It is written in the local session from the H0 results.

## M4. Reports

M4 builds the reports of Q5 and Q6 (02-decisions.md) on the shared view model from M2, which formats every number in printf style and applies the privacy filter. It adds the in-house Mustache renderer, the inline SVG layouts with the aggregated CSV per figure, the accessibility measures and the cross-language comparison of strings and values. Reports ship as 0.2.

## M5. Stream A for Gaussian LMMs

The reference evaluator and its Python port are built as decided in Q1 (02-decisions.md). The adapters are:

- lme4 objects (lmerMod, lmerModLmerTest and afex mixed objects)
- statsmodels MixedLM (≥ 0.15.0), with the coefficient map built by numeric column matching
- bring-your-own JSON
- at most one experimental Rust-engine adapter, chosen by the rule in Q1

As decided in Q2, the glmmTMB method is registered and returns `not_available('planned 1.1')`, and the availability guard and its test on a saved .rds fit follow Q6 (02-decisions.md).

The diagnostics are:

- the objective-match gate with registered tolerances and offsets
- convergence triage from M3b, with a boundary probe for small q
- marginal, conditional and studentised residuals with P-based quantities
- predicted random effects with both conditional variances labelled
- heteroscedasticity by cluster-size stratum on studentised residuals
- within-unit semivariograms
- cluster influence by one-step approximation, with exact refits as an option
- the design df everywhere and Satterthwaite df through lmerTest in R only, labelled engine-specific

Stream A executes Stream B plans in both languages, including their terminal states (02-decisions.md, Q3). When a plan file is supplied, Stream A reconciles the plan with the fitted model by hash.

The benchmark becomes the conformance corpus under fixtures/conformance/engines/. Simulated data are committed, real datasets are generated by Rscript in CI, and reference values come from current CRAN versions. The gate freezes the check code at a v0.9 tag, which is the version the preregistrations describe.

## M6. Validation, phase 1

All simulation programmes share one codebase in sim/, with one SLURM runner, one results schema and one register of studies with memory classes. Its starting point is the SLURM templates, cost model and protocol tables in evidence/decisions/F and F-verify, and the zoo generators serve as its data-generating mechanisms.

Studies V1, V2 and V7 are preregistered on OSF and run once the v0.9 code is frozen. V3 and V5 run after in-principle acceptance of the Stage 1 report, or after their OSF deposit if the maintainer chooses the regular route. V2 starts with the priority modules recommended in report F (evidence/decisions/reports.json, research:paper-hpc):

- M06, the omitted random slope
- M10, the omitted randomisation level in a cluster-randomised trial
- M05, the omitted contextual effect
- M01 and M09, heteroscedasticity at level 1 and by arm at level 2
- M04, AR(1) residuals in growth data
- M07, outlying clusters, with exact refits only in the influence module at 2,000 replicates
- M12, ceiling and floor censoring

Modules M02, M03, M08, M11 and M13 follow.

V7's scope, including the engine conformance study, and the threshold rules follow Q9 (02-decisions.md). The conformance study runs as a separate memory class, with one large-n timing study on a high-memory node, and its results regenerate the parity tiers. Python Stream A development continues while the phase 1 jobs run.

Each study is a SLURM job array on the htc cluster's short partition, which has a 12-hour limit. The arrays omit the CPU-generation constraint in the draft template, because the image is portable. Each task gets one core and 2 GB unless its memory class says otherwise, and tasks run for 2 to 4 hours, with at most 500 tasks per array and a concurrency throttle. If ARC's QoS limits concurrency, whole-node multi-core jobs replace the single-core arrays. Any dataset can be regenerated, because each chunk uses an L'Ecuyer-CMRG stream and each replicate a substream.

Chunks are idempotent. They write to $SCRATCH and are copied to /data/educ-intract/educ1242/<package>-sim/, and completion is checked against that directory. Because ARC keeps no backups, raw replicate results are mirrored off ARC, and the code and the raw results are archived with a DOI.

## R1, M7 and M8

Release 1.0 ships both packages. Checks are ranked by V2 priority early on, so that it is known in advance which ones will ship as descriptive if phase 1 runs late. The Stage 2 report and the validation paper (02-decisions.md, Q9) report phase 1.

GLMM support (1.1) is built in R first, on lme4 ≥ 2.1-0 and glmmTMB, using the engines' objective functions or a Laplace and AGQ evaluator written in R. It covers:

- Bernoulli, binomial-with-trials and Poisson GLMMs, and Gaussian glmmTMB fits
- simulation-based quantile residuals with shared draws for parity
- dispersion and zero checks against predeclared candidate families
- the separation check in Stream A

Studies V8 to V10 validate them. Python covers GLMMs through the routes in Q1 (02-decisions.md).

## Risks

| Risk | Mitigation |
|---|---|
| Maintainer capacity | Milestone gates, Stream B released first, R built first, GLMMs after 1.0, the deferred list above, and scope cut at a gate |
| Two numerical cores | Evaluator built and validated in R, with the Python port limited to what the objective-match gate needs |
| Upstream changes, from lme4 defaults and glmmTMB scales to statsmodels naming and young Rust engines | Engines in Suggests and extras, objective-match gate, expected-disagreement registry, conformance corpus in CI against current releases, experimental adapters non-gating with upper version bounds, sentinel validation cells rerun at major engine releases |
| Loss of cross-language parity | One schema bundle, shared corpora, exact parity for deterministic outputs, tolerance tiers per output, golden tests in both packages (02-decisions.md, Q1 and Q2) |
| CI growth to about 30 jobs | Tiered CI (M0) |
| Clean reports treated as certification or approval | No badges, scores or 'assumptions were met', a statement of what could not be assessed in every report, and banned phrases in generated text (02-decisions.md, Q5) |
| Choosing among contested methods after seeing the outcome | Choices declared in the plan before the outcome is seen, alternatives reported in a fixed order, a log of views generated |
| Disclosure of participant data | One privacy filter, keyed commitments in place of hashes, an internal sidecar, shareable files by default, disclosure tests in CI, and the data protection officer's view obtained in writing |
| CRAN archival | Small hard dependency closure, engine tests skipped when engines are absent, golden files based on fits kept off CRAN, files written only to tempdir() in examples and tests |
| JOSS scrutiny of a single-author project, and dependence on one person | Public history from M0, releases, tests, CI, governance and succession notes, research use in the maintainer's own analyses |
| AI-assisted code reproducing GPL source | Clean-room rule, a provenance entry for every algorithm that records any AI assistance, and the AI-usage disclosure that JOSS requires (02-decisions.md, Q10) |
| Reference-checking backlog | One block in the local session before any preregistration, with full reads of the papers listed below |

## Open checks

Each item needs the local session, CI with network access or ARC. Delete an item once it is resolved, and record the outcome in 02-decisions.md if it changes a decision.

The checks on maintainer decisions and Oxford procedures are:

- the choices under 'Decisions for the maintainer' in 02-decisions.md
- Oxford's rules on copyright and open-source release
- the views of the data protection officer and of data providers on publishing shareable reports
- where any restricted data may be analysed, and under which agreement

The checks on registries and current software are:

- `pak::pkg_name_check()` and the R-universe search for the chosen name
- the live CRAN policy revision
- the H0 reruns with current engines
- R 4.2.0, 4.2.2, 4.2.3 and 4.3.3 in rocker images, testing whether lme4 2.x installs with the bundled Matrix
- optional tests of pymer4 through conda, MixedModels.jl through juliacall and fastglmm from R-universe

On ARC, the environment checks of the H0 pilot remain open.

The checks on venues and their policies are:

- JSS's policy on software already published in JOSS
- Registered Report acceptance for simulation studies at Behavior Research Methods and AMPPS
- Oxford's coverage under the Springer Nature and APA open-access agreements
- the AMPPS article charge
- the scope wording of the candidate journals
- review times, including Psychological Methods' time to first decision

The checks on privacy and reporting standards are:

- the primary UK output-checking guidance (ONS Secure Research Service, DfE and the SDC Handbook)
- the ICO's anonymisation guidance
- how the UK GDPR and the Data Protection Act 2018, as amended by the Data (Use and Access) Act 2025, apply to shareable output, including the identifiability provisions of the 2025 Act
- the output rules of the data providers
- the wording of the CONSORT 2010 cluster extension and whether a cluster extension aligned with CONSORT 2025 exists
- JARS-Quant Table 1
- tagged print-to-PDF in browsers other than Chromium (02-decisions.md, Q5)
- screen-reader testing of a prototype report

The licence checks cover the FSF entries on GPL compatibility (#IfLibraryIsGPL in the GPL FAQ and #Expat in the licence list). They also cover the data licences of OSF project 4p8hz, LSHTM Data Compass, Many Labs 2, ERP CORE and the openESM datasets.

These papers need reading in full before their content is used. Three of them, Barr (2013), Barr et al. (2013) and Matuschek et al. (2017), are already cited in 02-decisions.md for points that the full texts must confirm. The others are in the evidence tables but not yet cited:

- Meteyard and Davies (2020), the checklist and survey figures
- Bono et al. (2021), the GLMM reporting rates
- Matuschek et al. (2017), the design and the α of .2
- Barr (2013), the Type I error figures for interactions
- Barr et al. (2013), the Type I error figures for the maximal model
- Scandola and Tidoni (2024), the procedure and simulation grids
- Luo and Li (2023)
- Eager and Roy (2017), the conditions
- Greven and Kneib (2010)
- Oberauer (2022)
- Veríssimo (2023)
- Seedorff et al. (2019)
- Goldstein et al. (1993), for the Exam data
- Flay et al. (1988), for the smoking-prevention trial
- the boundary-test, residual and Laplace-accuracy papers listed in evidence/decisions/F/tables/open_items_local_session.csv

The issue and pages of Siepe et al. (2024) are still missing. Before any work listed in evidence/decisions/A-verify/out/reference_checks.csv is cited, the fields that file marks as not confirmed need checking, apart from those settled by the bibliographic checks recorded in evidence/decisions/README.md.
