# Execution plan

This plan turns the decisions in 02-decisions.md into milestones for a single maintainer. Each milestone ends at a gate, a set of conditions that must hold before the next one starts, rather than at a date. The plan should be revised whenever a gate exposes a problem, and items in the open-checks section should be deleted once they are resolved.

Work is done in three places. Implementation runs in cloud sessions or locally. Checks that need sites blocked in the cloud sessions (CRAN, R-universe, publishers and Oxford's internal pages) run in the local session or in GitHub Actions, whose runners can install current CRAN packages. Simulation studies run on ARC. Jobs go to the htc cluster with `sbatch --clusters=htc` and never on a login node, and heavy material lives under /data/educ-intract/educ1242/.

## Milestones

| Milestone | Content | Size | Gate |
|---|---|---|---|
| M0 Foundations | Maintainer decisions, monorepo skeleton, licences, CI matrices, registry hash check, contribution and governance notes | Small | Both empty packages pass CI on every platform, and the vendored-registry check fails on a deliberate mismatch |
| M1 Specifications | Registry schema and compiler, declaration schema 0.1, canonical IR and formula grammar, results schema, conformance corpora | Medium | Both languages load the registry and validate the declaration corpus with identical error codes and hashes |
| M2 Stream B core | Strict readers, canonicalisation, formula parser, design matrices, T0 and T1 audits, results table and JSON writer, pathology zoo | Large | Exact parity on all zoo fixtures, clean R CMD check with and without Suggests, Python tests on 3.11 to 3.15 |
| M3 Plan object | Ceiling, protected set, ladder, stopping-rule menu, plan hash, preregistration text, outcome-access log, `draft_design()` and builders | Medium | Identical ladders and plan hashes across languages on the zoo, and every plan validates against its schema |
| M4 Reports | Shared Mustache renderer, view model, inline SVG layouts, shareable and internal modes, accessibility, .qmd export | Medium | Golden reports agree across languages and pass axe-core and HTML validation |
| R0 Release 0.x | Stream B on CRAN, PyPI and R-universe | Small | CRAN incoming checks pass, the name is confirmed and the repository is public |
| M5 Stream A (Gaussian) | Reference evaluator, adapters, objective-match gate, convergence and singularity triage, residual and random-effect diagnostics, plan execution, reconciliation with Stream B | Large | Conformance corpus passes in CI with current CRAN and PyPI engines, and check code is frozen at a v0.9 tag |
| M6 Validation, phase 1 | HPC-0 pilot, preregistration or Stage 1 Registered Report, studies V1 to V7 | Large | In-principle acceptance or an OSF deposit before the main runs, and results archived with a DOI |
| R1 Release 1.0 | Thresholds and provenance from M6 in the registry, both packages released, Stage 2 submission | Medium | Every shipped threshold has validation provenance, and every unvalidated check is labelled descriptive |
| M7 JOSS paper | Software paper for both packages | Small | More than six months of public history and evidence of research use beyond the tool's own papers |
| M8 GLMMs (1.1) | Laplace and AGQ evaluator, glmer and glmmTMB adapters, simulation-based residuals with shared draws, dispersion, zero and separation checks, studies V8 to V10 | Large | The same gates as M5 and M6 for the GLMM checks |

Sizes are relative: a small milestone is a few focused weeks, a large one several months for one maintainer. Later releases (1.2 families, 1.3 structured covariances, version 2 candidates) follow the roadmap in Q2 and are planned when 1.1 ships.

## M0. Foundations

The maintainer settles the six choices listed at the end of 02-decisions.md before any package code is written, because the name appears in every file. The skeleton follows the layout in Q7.

r/ holds a minimal R package with DESCRIPTION (Depends R ≥ 4.2.0, Imports Matrix and jsonlite), a two-line licence stub and testthat. python/ holds a pyproject package with a src layout, requires-python ≥ 3.11, numpy, pandas and scipy as dependencies and empty extras. spec/, fixtures/, parity/, sim/ and paper/ exist with short README files. A .gitattributes file fixes LF line endings for vendored and fixture files. REUSE-style licence files mark any directory whose contents are not MIT.

CI uses GitHub Actions with path filters. The R workflow runs R CMD check on Ubuntu (devel, release, oldrel-1 and 4.2), Windows and macOS (release), plus one job with `_R_CHECK_DEPENDS_ONLY_=true`. The Python workflow runs Python 3.11 to 3.15 with both lowest-direct and latest resolutions. A parity workflow compares the SHA-256 of every vendored registry copy with spec/compiled/ and fails on any mismatch.

Short CONTRIBUTING, code-of-conduct and governance files give JOSS the signals of open development that it looks for in single-author projects. If the maintainer approves, the repository becomes public at the end of M0, which starts the six-month clock for JOSS.

## M1. Specifications

Four specifications are written as documents under docs/spec/ and as machine-readable schemas under spec/, because both implementations depend on them.

The registry schema defines a check entry. Each entry has a stable ID and version, a tier (T0, T1 or T2), the statistic and comparison exactly as computed, an assessability rule, thresholds with their sources and validation provenance (language, engine and version), remedies with the engine each needs and whether it changes the estimand or reads the outcome, links in the dependency graph ('explained_by' and 'suppresses') and message templates. Registry entries are authored in YAML, read with every scalar as a string and compiled to canonical JSON by one script under spec/tools/. The compiled JSON is the only form the packages read.

The declaration schema is vocabulary 0.1 from Q4. The draft in evidence/decisions/E/schema is completed with the verifier's corrections: assignment level, an outcome for each estimand, a defined observation unit, version matching on 0.1.x, a semantic layer for references and cycles, and a top-level list of inferred entries.

The canonical IR specification defines how a formula and a declaration become terms, columns and grouping factors. It covers the lme4 grammar the suite accepts, contrast coding with explicit reference levels, centring constants and their source sample, the analysis sample and its fingerprint, factor-level order (declared levels first, otherwise code-point order after NFC), the treatment of `||` (rejected for factors unless written as `diag()` with a declared coding) and the sequential rule for dropping aliased columns.

The results schema defines the long results table: check ID and version, status (an ordered set that includes 'not_available', 'error' and 'incomplete'), assessability, finding, effective thresholds, values and provenance, plus the canonical number format and the treatment of non-finite values.

Conformance corpora sit under fixtures/conformance/: formula strings with their expected IR, valid and invalid declarations with expected error codes, the JSON and table edge cases from the review, and number-formatting cases. Both languages run every corpus in CI.

## M2. Stream B core

Both languages implement the same pipeline: strict readers for the declaration and the data, canonicalisation of identifiers, missing-value tokens and level order, the formula parser, the design matrices X and Z, the audits and the writer of the results table and JSON. The formula parser is written in-house in both languages, with reformulas used only as a test oracle in R.

The T0 audits are:

- label incidence for every pair of grouping factors (nested, crossed or partially crossed)
- evidence on ID scope when it is undeclared (attribute consistency across outer units, restart numbering)
- aliased grouping factors and factors with one row per level
- within and between status of each term for each grouping factor, with informative-group counts and predictor ICCs
- the identifiability verdict from the projected Gram matrix
- the level-specific df budget, J ≤ q and confounding with the residual when there is one observation per unit and cell
- rank deficiency and empty cells under the sequential aliasing rule
- term-level GVIF and scale disparity
- differences between the raw data and the analysis sample, and duplicates against the declared observation key

The T1 audits (constant clusters, events per cluster, boundary and zero shares) sit behind the outcome-access argument.

The pathology zoo grows from the ten prototypes to the thirty planned fixtures, each with a clean matched negative and expectations derived from the generating design. Parsing-hazard and attribute-consistency fixtures are added. The zoo generators live in sim/ so that the HPC studies reuse them.

## M3. Plan object

The ladder generator implements Q3: freezing of coding and centring, rung 0, the protected set from the declared roles, the fixed reduction order and the identifiability verdict for every rung. The stopping-rule menu holds the localised protected back-off (default), protected LRT(.2) and no reduction. The plan is written as canonical JSON with a hash and as generated preregistration text that lists the user's required declarations. The outcome-access log is a plain JSON file. `draft_design()` and the code-first builders write declarations in both languages.

## M4. Reports

The renderer is an in-house Mustache subset tested against the language-independent Mustache specification tests. A shared view model formats every number in printf style. Inline SVG figures use three layouts (band, bar and matrix) with coordinates computed by shared logic and stored in the results JSON.

The shareable privacy rules and the internal mode follow Q5, with all parameters in the registry. Every figure has alternative text, a long description and its data table. The .qmd export writes a folder with metadata, SVG and PNG figures and the hashed results JSON, and refuses Word and Typst targets for Quarto below 1.11.

Monorepo CI runs axe-core and an HTML validator on golden reports. A Typst PDF/UA-1 render is checked with veraPDF in a separate, slower workflow.

## R0. Release 0.x

Stream B ships to CRAN, PyPI and R-universe as version 0.x once the name is confirmed and the repository is public. Examples and tests use only bundled zoo fixtures and finish within CRAN's time limits on two cores. Feedback from this release informs M5.

## M5. Stream A for Gaussian LMMs

The reference evaluator computes the sparse ML and REML objectives with weights and offsets in both languages. In R it uses Matrix and CHOLMOD. In Python it uses scipy, with a log-determinant that does not depend on CHOLMOD and an optional sparse-Cholesky extra.

The adapters are lme4 objects (lmerMod, lmerModLmerTest and afex mixed objects), statsmodels MixedLM, bring-your-own JSON and at most one experimental Rust-engine adapter, chosen by the rule in Q1. The availability guard sits in the generic, and a test diagnoses a saved .rds fit with lme4 absent.

The diagnostics are:

- the objective-match gate, with tolerances and registered offsets per criterion and engine version
- convergence triage from the suite's own scaled gradient and Hessian, with a second optimiser confirming the objective and a boundary probe for small q
- a scale-free singularity verdict based on rank
- marginal, conditional and studentised residuals, with P-based quantities
- predicted random effects with both conditional variances labelled
- heteroscedasticity by cluster-size stratum on studentised residuals
- within-unit semivariograms
- cluster influence, from approximations by default with exact refits as an option
- design df and Satterthwaite df from the evaluator, with Kenward–Roger through pbkrtest in R only, labelled as engine-specific

Stream A executes a Stream B plan, logs every rung, and reports the selected model, the protected rung and the adjacent rung as pre-declared sensitivity analyses. When a plan file is supplied, it reconciles the plan with the fitted model by hash.

The 27-model benchmark becomes the conformance corpus under fixtures/conformance/engines/. Simulated data are committed, real datasets are generated by Rscript at CI time, and the reference values come from current CRAN versions in CI. The gate freezes the check code at a v0.9 tag, which is the version the preregistration describes.

## M6. Validation, phase 1

Simulation code lives in sim/, uses the zoo generators and records the versions of the frozen check code, engines and packages. The R environment is an Apptainer image built off-cluster with portable compiler flags from a dated package snapshot. The image and a lockfile are archived with the results.

The work runs in four steps:

1. The HPC-0 pilot on ARC confirms the R module, the Apptainer runtime, the array and QoS limits, the credit balance and the CPU feature names. It also re-times a 20-fit subset with current lme4 and glmmTMB and runs a six-task array of V1.
2. The protocol (ADEMP, decision rules, Monte Carlo SE targets, failure handling, calibration and hold-out split, comparators) is preregistered on OSF. If the Registered Report route is chosen, it is also submitted as a Stage 1 report to Behavior Research Methods or Advances in Methods and Practices in Psychological Science.
3. After in-principle acceptance, or immediately after the OSF deposit, studies V1, V2 (priority modules first), V3, V5 and V7 run. Studies V4 and V6 run as capacity allows.
4. Thresholds are set on the calibration half, confirmed on the held-out half, and written into the registry with their provenance.

The priority V2 modules are the omitted slope, the omitted randomisation level in cluster-randomised trials, reused nested labels, small-cluster heteroscedasticity, separation of within and between effects, influence and residual autocorrelation.

Each study is a SLURM job array on the htc short partition: one core and 2 GB per task, tasks of 2 to 4 hours, at most 500 tasks per array and a concurrency throttle. Each chunk uses an L'Ecuyer-CMRG stream and each replicate a substream. Chunks write to $SCRATCH and are copied to /data/educ-intract/educ1242/mixedcheck-sim/, and completion is checked against that directory. Raw replicate results are mirrored off ARC and archived with a DOI, because ARC keeps no backups. The SLURM templates, the cost model and the protocol tables from the review are in evidence/decisions/F and F-verify and are the starting point for sim/.

## R1, M7 and M8

Release 1.0 ships both packages with every shipped threshold carrying validation provenance. Any check whose operating characteristics were not validated is labelled descriptive. The Stage 2 report, or the regular article, reports phase 1. The JOSS paper follows once its gates are met. It discloses the validation paper and describes the diagnostic contract, the design audits and cross-language parity.

GLMM support (1.1) repeats the M5 and M6 pattern for Bernoulli, binomial and Poisson models. It adds the Laplace and AGQ evaluator, the glmer and glmmTMB adapters (including Gaussian glmmTMB fits) and simulation-based quantile residuals with shared draws for parity. Dispersion and zero checks are judged against predeclared candidate families, and the separation check moves into Stream A. Studies V8 to V10 validate them.

## Risks

| Risk | Mitigation |
|---|---|
| Maintainer capacity, with two packages, a registry, reports and validation | Milestone gates, Stream B released first, GLMMs only after 1.0, scope cut at a gate rather than spread thin |
| Upstream changes (lme4 defaults, glmmTMB scales, statsmodels behaviour, young Rust engines) | Engines in Suggests and extras, objective-match gate, expected-disagreement registry, conformance corpus in CI against current releases, sentinel validation cells rerun at major engine releases |
| Parity drift between the two implementations | Shared specifications and corpora, exact parity for deterministic outputs, tolerance tiers declared per output, golden tests in both packages |
| Certification creep, with clean reports treated as approval | No badges, scores or 'assumptions were met', a statement of what could not be assessed in every report, and banned phrases in generated text |
| Option shopping among contested methods | Choices declared in the plan before the outcome is seen, alternatives reported in a fixed order, a log of views generated |
| Disclosure of participant data in reports | Shareable mode by default, thresholds from UK output-checking practice, internal mode only by explicit choice, disclosure-attack tests on ARC |
| CRAN archival after failing checks | Small hard dependency closure, engine tests skipped when engines are absent, fit-based goldens kept off CRAN |
| JOSS scrutiny of a single-author project | Public history from M0, releases, tests, CI, governance files, and research use in the maintainer's own analyses |

## Open checks

Each item below needs the local session, CI with network access or ARC. Delete an item once it is resolved and record the outcome in 02-decisions.md if it changes a decision.

The maintainer's decisions and Oxford procedures come first:

- the six choices at the end of 02-decisions.md
- Oxford's rules on copyright and open-source release
- the data protection officer's view on publishing shareable reports
- permission and a data protection impact assessment for any restricted data used on ARC

Registries and current software:

- `pak::pkg_name_check()` and the R-universe search for the chosen name
- the live CRAN policy revision
- the 27-model benchmark and the random-effects simulations (Sims 1 to 6), rerun in CI with lme4 2.1-0 or later, glmmTMB 1.1.15 or later and lmerTest 3.2-1
- R 4.2.0, 4.2.3 and 4.3.3 in rocker images, testing whether lme4 2.x installs with the bundled Matrix
- optional tests of pymer4 through conda, MixedModels.jl through juliacall and fastglmm from R-universe

ARC:

- module and Apptainer availability, array and QoS limits, the credit allocation for the project and CPU feature names
- the HPC-0 pilot

Venues and policies:

- JSS's policy on software already published in JOSS
- Registered Report acceptance for simulation studies at Behavior Research Methods and AMPPS
- Oxford's coverage under the Springer Nature and APA open-access agreements, and the AMPPS article charge

Privacy and reporting standards:

- the primary UK sources: the ONS Secure Research Service and DfE output-checking rules, the SDC Handbook, the ICO's anonymisation guidance and the identifiability provisions of the Data (Use and Access) Act 2025
- the wording of the CONSORT 2010 cluster extension, and whether a cluster extension aligned with CONSORT 2025 exists
- the Quarto alternative-text behaviour for Word and Typst, browser support for tagged print-to-PDF, and screen-reader testing of a prototype report

Data licences: OSF project 4p8hz, LSHTM Data Compass, Many Labs 2, the ERP CORE terms and the openESM datasets.

The following papers need reading in full before their content is used. These are all in the evidence tables and are not yet cited as sources:

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
- Flay et al. (1988), for the smoking-prevention trial data
- the boundary-test, residual and Laplace-accuracy papers listed in evidence/decisions/F/tables/open_items_local_session.csv

Some metadata are still incomplete: the DOI of Bradley (1978), the issue and pages of Siepe et al. (2024), the page range of the pbkrtest article and the DOIs flagged in evidence/decisions/A-verify.
