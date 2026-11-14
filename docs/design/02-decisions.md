# Decision record

This record resolves the ten questions raised at the end of 01-design-review.md. The decisions rest on six research reports, one adversarial verifier per report and a consistency critic (evidence/decisions/README.md). The verifiers reran experiments and checked the reports' claims and sources. Some experiments were not rerun, and many references in the evidence files remain unverified. The critic found conflicts between the decisions, which are resolved here and in the cross-cutting conventions. Where a verifier or the critic corrected a report, the correction is adopted. Items that need the local session (paywalled papers, current CRAN versions and HPC runs) are listed in 03-execution-plan.md.

Three status values are used. 'Decided' means the evidence settles the question. 'Provisional' means a named check could still change the decision. 'Maintainer' means the choice belongs to the maintainer, with a recommended default.

## Summary

| Question | Decision | Status |
|---|---|---|
| Q1 Python engine | Engine-agnostic contract with a suite-owned reference evaluator. Version 1.0 ships a statsmodels adapter, a bring-your-own-estimates protocol and at most one experimental adapter for a Rust engine | Decided, parity tiers provisional |
| Q2 Model scope | Stream B audits for every outcome type from 0.x. Stream A diagnoses Gaussian LMMs in 1.0 and GLMMs from 1.1, with further families and covariance structures later, R first | Decided |
| Q3 Stream B output | A plan object with a ceiling, identifiability verdicts, an outcome-free ladder with a protected set, a registered stopping rule, a terminal state and two hashes. Outcome-blind by default | Decided, default rule provisional until study H1 |
| Q4 Declarations | Optional by default and required for confirmatory goals, outcome-blind and preregistration exports, and trial features. Canonical JSON with JSON Schema, RFC 8785 hashing and a Frictionless table subset | Decided |
| Q5 Reports | A results object, a self-contained static HTML report and an optional engine-free .qmd export. One privacy filter with shareable output by default and two tiers of protection, and WCAG 2.2 AA | Decided, privacy settings: maintainer |
| Q6 Dependencies | Independent computation, engines in Suggests with the availability guard in the generic, opt-in external cross-checks and no package split | Decided |
| Q7 Names and layout | mixedcheck in both languages, chosen by the maintainer with lmecheck as the fallback, in a monorepo with vendored shared artefacts | Decided, name provisional until the registry checks |
| Q8 Domains and corpus | Nested education data and crossed designs drive the defaults, and a four-layer corpus is built around a simulated pathology zoo | Decided |
| Q9 Validation and papers | Preregistered validation on ARC, a Stage 1 Registered Report on the ladder study and a JOSS paper for the software | Decided, venue facts provisional, paper route: maintainer, at P1 |
| Q10 Versions and licence | R ≥ 4.2.0, Python ≥ 3.11 with SPEC 0 floors, MIT for everything that ships, with clean-room implementation | Decided |

Further choices within these questions are listed, each with a recommended default, under 'Decisions for the maintainer' before the references, for the maintainer to settle or confirm.

## Cross-cutting conventions

The reports used the same words and hashes for different things. The conventions below apply to every component in both languages, and the M1 specifications (03-execution-plan.md) write them down formally.

Every finding carries six independent status fields:

| Field | Values |
|---|---|
| Availability | available, or not_available with a reason: engine, package, capability or declaration missing, not expressible by the engine, too large, suppressed for privacy or planned for a later version |
| Assessability | adequate, weak or not_assessable, with the reason (prerequisite unmet or low detection) |
| Finding | consistent with the model, detectable but inconsequential, or consequential |
| Optimisation | at_optimum, near_optimum, not_converged, not_certified, objective_unavailable, objective_offset_registered or contract_mismatch |
| Threshold proximity | clear or near_threshold |
| Validation | validated (study, language, engine and version range), descriptive or outside_validated_range |

The value not_assessable therefore has one meaning only, and suppression for privacy is reported as not_available with its own reason.

Hashes follow one taxonomy. Public hashes cover the compiled registry, the declaration (SHA-256 of its RFC 8785 form), the canonical IR, the language-neutral design plan, the engine-specific execution binding of a plan and the written results file. Anything computed from person-level data appears in shareable files only as a keyed commitment (HMAC-SHA-256), with the key held in an internal sidecar. This covers the analysis table, a raw data file and the outcome column in the access log. An unkeyed hash of person-level data works as an oracle. In the critic's test on a class of 20 pupils, one unknown binary outcome was recovered at once from the column hash and the other 19 values. A brute-force search over all 2^20 possible columns recovered the whole outcome column from the hash alone in 1.6 s.

JSON documents follow one of two profiles. Declarations and plans use the 'hashable' profile, which allows strings, booleans, integers within ±2^53 and decimals with at most 15 significant digits, and no nulls or non-finite values. Results and estimates use the 'data' profile, which allows nulls with status objects, doubles written at shortest round-trip precision and an explicit encoding of non-finite values.

Centring constants are stored as decimal strings at a declared precision, and the fit uses that rounded value. Prospective plans store the centring rule rather than a number.

Strings are UTF-8. Readers validate the bytes and mark strings as UTF-8 without re-encoding them. Writers and hashers refuse unmarked non-ASCII strings. This matters because, in R under a C locale, which batch jobs often use, a UTF-8 identifier read without a declared encoding was written to JSON as the literal text '<c3><a9>' and hashed differently from the same identifier in Python.

Identifiers and level labels are compared after NFC normalisation, so that labels differing only in their Unicode form are reported rather than silently split. In R, SHA-256 comes from cli, because base R gains it only in 4.5.0, and NFC comes from utf8. Both gave byte-identical results to Python's hashlib and unicodedata.

Results are always returned as an object. Files are written only to a path the user gives, or to the temporary directory in examples and tests, as CRAN requires. A written report consists of a shareable results file and, when needed, a separate internal sidecar. The sidecar holds observation keys, the labels of predicted random effects, the pseudonym map and the commitment key. Rows are identified by the declared observation key, never by position, because R and Python index rows differently.

## Q1. Python engine strategy

Python Stream A is engine-agnostic. The suite owns the canonical intermediate representation (IR) of the model, a fitted-model contract and a sparse reference evaluator of the Gaussian ML and REML objectives with weights and offsets.

Engines only supply estimates, through adapters. The evaluator is built in R first, on Matrix and CHOLMOD, and validated against lme4's deviance function. The Python port covers what the objective-match gate needs for statsmodels fits and bring-your-own estimates.

Version 1.0 ships three things:

1. A statsmodels MixedLM adapter (statsmodels ≥ 0.15.0) for fits that users already have, within what MixedLM can represent. That means one grouping factor with correlated slopes, nested variance components, crossed intercepts and uncorrelated crossed slopes through variance components with `use_sparse=True`, and a Gaussian offset absorbed into the response. The optimiser used is recorded. The coefficient map is built by matching design columns numerically to IR columns, not by parsing names, because statsmodels 0.15.0 names the same column 'flag[T.True]' or 'flag' depending on the formula engine set at fit time.
2. A bring-your-own-estimates protocol, a JSON file in the contract schema, for any other engine.
3. At most one experimental adapter for a Rust-based engine, glmm or mixedlm. The choice is made at implementation time by a rule declared now: fewest contract fields the suite must reconstruct, then no break in the engine's Python API over its last three releases, then label fidelity and wheel coverage. The adapter is non-gating in CI and has upper version bounds.

An Rscript route that fits through the suite's own R package is documented as an example for Python users who have R, rather than shipped as a supported adapter. There is no dependency on pymer4, juliacall or gpboost. gpboost may later serve only as an engine-specific adapter (Q2), never as a parity reference. Cross-language parity tests in CI use JSON fixtures generated by Rscript. GLMM evaluation and adapters arrive with version 1.1.

A benchmark of 27 models compared each engine with lme4 1.1-35.1 and glmmTMB 1.1.8 under one engine-independent objective. That objective reproduced every LMM criterion reported by lme4, and every unweighted LMM criterion reported by glmmTMB, to within 4e-10. glmmTMB's weighted LMM criteria differed by about 2,134 units, because glmmTMB treats Gaussian weights differently (below). glmmTMB also reported no criterion for two fits. The objective reproduced glmmTMB's Laplace values to within 1.5e-12 on two datasets and to within 1.4e-8 on the third, a crossed binary design. lme4 1.1-35.1's reported Laplace values differed from it by up to 1.6e-3, and its nAGQ = 25 values omitted normalising constants (84 and 1,681 units on two datasets). lme4 2.1-0 changed both.

The verifier reimplemented the objective independently and agreed within 4.4e-11. They also ran 200 random starts on each of five small designs. No start reached an objective more than 1e-12 below the best value the engines found, and all ended within 1e-4 of it.

glmm 0.8.0 and mixedlm 1.3.0 reached the best objective on all 27 models. Both are under a year old and appear to have a single maintainer each. Both changed behaviour or public names between minor releases, although glmm's changelog states that its Python and R fit objects kept their fields.

statsmodels 0.15.0 could represent only 19 of the 27 models. It fitted two of them, the cbpp GLMMs, only through its approximate Bayesian mixed GLMs, because it has no likelihood-based GLMM. The other eight need crossed correlated slopes (four models, one of them the crossed binary GLMM), prior weights (two) or an offset in a Poisson GLMM (two). Even with sparse matrices, its crossed variance-component fits were about 24 to 27 times slower than lme4 (2.7 to 2.8 s against 0.11 to 0.12 s at 2,400 rows, and 23.6 s against 0.86 s at 12,000 rows). Its convergence flag is unreliable near the boundary. With its default optimiser, it stopped 0.013 to 1.16 deviance units short of the optimum on all four near-singular designs and reported convergence on two of them. Nelder–Mead reached the optimum on three of the four, and lbfgs reported convergence at gaps of 0.06 to 0.22.

pymer4 does not support installation with pip, and rpy2 is tied to specific R versions. gpboost's default likelihood is approximate, 0.08 to 0.69 deviance units from exact.

Every adapter supplies the following fields:

- engine, engine version, adapter version and contract version
- the IR hash and the analysis-sample observation keys
- a map from engine coefficients to canonical IR columns, with aliasing flags
- the criterion (REML, ML, Laplace, AGQ with its number of nodes, nAGQ = 0, variational Bayes or MAP) and whether the reported likelihood is exact
- the semantics of the weights (precision, frequency or log-likelihood multiplier)
- the fixed effects
- the absolute covariance matrix of each random-effects block, in canonical order, with its packing order declared
- the residual variance or dispersion, in the registry's parameterisation
- the reported objective, with its constant convention
- the covariance matrix of the fixed effects, with a method label
- the raw convergence output

Optional capabilities are flagged: X and Z, labelled predicted random effects, an objective function, refit, simulate and df. A missing capability yields not_available.

Each contract field answers a discrepancy seen in the benchmark. glmmTMB treats Gaussian weights as log-likelihood multipliers unless they are mapped through its dispersion formula, and the mapping depends on the version (−log w before 1.1.9 and −0.5 log w from 1.1.9). Standard-error conventions differ by up to 2.4% between engines. mixedlm loses factor labels and drops a different aliased column from lme4. Reading glmm's covariance in the wrong order shifted the REML criterion by 2.3 units, yet still produced a positive-definite matrix.

The suite then evaluates its own objective at the reported estimates and compares it with the reported value. Tolerances depend on the criterion and the engine version and are stored in the registry, for example max(1e-6·|dev|, 1e-6) for LMMs. Known engine conventions are registered as offsets, such as the Laplace deviance of lme4 before 2.1-0.

A failed comparison yields an optimisation status rather than a crash. Stream A stops only above the scale of the semantic errors the benchmark found, the smallest of which was 0.08 deviance units. The suite also measures the gap to the best objective found, recomputes the predicted random effects, residuals and P-based quantities itself, and reports two conditional variances separately: one with the fixed effects held fixed and one that includes their uncertainty. The two differed by up to 24% on sleepstudy.

Small-sample inference in version 1.0 is split by language. R reports Satterthwaite df through lmerTest in Suggests, labelled engine-specific. Python reports the design df and marks Satterthwaite df as not computed. An in-house version follows after 1.0 and is validated against lmerTest.

Parity tiers are assigned from a conformance corpus, never in advance, and recorded in the registry's list of expected disagreements. Each assignment is specific to an engine, version range, optimiser setting, adapter mapping and output class. The tolerance tier requires two conditions: the common objective within max(1e-4, 1e-9·|dev|) of the best known value, and fixed effects within 0.01 standard errors. Standard errors are compared only under the same convention, or after the suite has recomputed them.

The current assignments rest on one replicate per design and on superseded engine versions. lme4 2.1-0 changed the Laplace deviance and GLMM standard errors, and glmmTMB 1.1.9 moved the Gaussian dispersion to the standard-deviation scale. The assignments are therefore provisional until they are regenerated with current versions and replicates in the H0 pilot and in V7.

A Rust-based Python engine becomes 'supported', and the documented default for new Python fits, only when three conditions hold. It must pass the conformance corpus at the tolerance tier on three consecutive releases, the fields its adapter reads must not have broken for 12 months, and it must have a second active maintainer or an institutional home.

If no engine qualifies, bring-your-own estimates and the R route remain the supported paths for GLMMs in Python. From 1.1, the experimental adapter may also carry GLMMs, labelled experimental. Because glmm already validates itself against a large grid of reference fits, cross-engine conformance is reported in the validation paper as supporting evidence (Q9).

## Q2. Model scope

From the first 0.x release, Stream B audits cover every outcome type in both languages with exact parity, except the per-coefficient bounds of the separation check, which are compared within tolerances stored in the registry. The types are Gaussian, binary, binomial with trials, counts with exposure, bounded scores, ordinal items and positive durations.

T0 checks come from declarations: type, event level, trials, exposure and bounds. T1 checks read the outcome only marginally or by cluster: constant clusters, minority events per cluster and the shares of boundary and zero values. T2 checks relate the outcome to the predictors. The separation check for binary outcomes is one of them, a linear program on the fixed-effects matrix after incomplete rows are removed, so it is deferred in outcome-blind mode. Its output is a verdict with per-coefficient bounds over the optimal face, because different solver settings returned different optimal vertices for the same problem. It runs in Stream B's exploratory mode from 0.x, with lpSolve in Suggests in R and scipy's HiGHS solver in Python, each with the settings that its registry entry fixes (03-execution-plan.md, M2).

Version 1.0 of Stream A diagnoses Gaussian LMMs only. In R, these are lme4 objects (lmerMod, lmerModLmerTest and afex mixed objects). In Python, they are statsmodels MixedLM fits, bring-your-own estimates and fits from the experimental Rust-engine adapter. The glmmTMB method is registered in 1.0 but returns not_available with the reason 'planned 1.1'. When a single Likert item is about to be modelled as metric, Stream B warns at T0 (Liddell & Kruschke, 2018) and states that Stream A cannot yet diagnose cumulative-link models.

After 1.0, version 1.1 adds Gaussian glmmTMB fits and Bernoulli, binomial-with-trials and Poisson GLMMs, built in R first on lme4 ≥ 2.1-0 and glmmTMB. Python covers them through the routes in Q1. Version 1.2 adds negative binomial (NB1 and NB2), Gamma, lognormal, beta, beta-binomial and ordered beta families. R comes first, and Python follows through a promoted engine, since glmm and mixedlm already fit some of these families. For families that no other Python engine fits, such as beta and beta-binomial, Python may use an engine-specific gpboost adapter. Version 1.3 adds structured covariance terms (`diag()`, `cs()` and `ar1()` in lme4 2.x, and ar1, ou, toep and cs in glmmTMB) and calibrates the within-unit semivariogram check, which ships in 1.0 as a diagnostic, against them. Ordinal cumulative-link mixed models, zero-inflated and hurdle models (which first need per-component fields in the contract) and an nlme adapter are candidates for version 2, started on demand. Bayesian fits, GAMMs, multiple-membership models, nonlinear mixed models and multilevel SEM are not planned for 1.x, and every report states where coverage ends.

A model class is promoted only after its checks have false-flag and detection rates validated on the HPC. Stream B is released to CRAN and PyPI as soon as it is complete, so that feedback arrives before Stream A is finished (03-execution-plan.md, R0). Releases are gated by maintainer time (Q9).

GLMM diagnostics in version 1.0 would have no supported Python counterpart, because statsmodels has no frequentist GLMM and the Rust-based engines that fit GLMMs, glmm and mixedlm, have no supported adapter. GLMMs also cost more to fit and to triage. In a 1,600-row crossed design with maximal random effects, the median Bernoulli glmer fit took 1.94 s, about 11 times as long as lmer.

Triage of singular and non-converged fits is core version 1.0 work even for Gaussian models. Over 100 correctly specified datasets, lmer warned in 14% of fits, Bernoulli glmer in 59% and Bernoulli glmmTMB in 67%. With the residual standard deviation set to the logistic latent value (π/√3), lmer warned in 52% of fits. Most of the difference therefore reflects the information in the data rather than the family.

One decision rule is fixed now. If the maintainer's own accuracy data need binary GLMM diagnostics before version 1.1, an R-only module for Bernoulli and binomial glmer comes forward. It covers reporting and convergence triage and offers residual checks only as an opt-in DHARMa cross-check. Python reports not_available.

The published reviews of LMM and GLMM usage cited in the research report could be read only through abstracts and search snippets, and the verifier could not reach them. They are listed for the local session, and no claim about prevalence enters the paper until they have been read.

## Q3. Stream B output and outcome-blind operation

Stream B never returns a single recommended formula. It returns a plan object with six parts:

1. the design-implied ceiling for each grouping factor, with the number of informative groups behind each term and the level-specific df budget
2. identifiability verdicts for the ceiling and every rung, exact for Gaussian LMMs whose covariance parameters enter linearly and only a necessary condition for GLMMs
3. a deterministic ladder of nested rungs built without the outcome, with an explicit protected set
4. a stopping rule chosen from a registry menu
5. a declared terminal state for when the protected rung fails
6. two hashes, described below

The first hash is a language-neutral design-plan hash. It covers the IR of every rung, the protected set, the rule and its version, the terminal state and the declaration hash, and it must match across languages. The second is an execution binding, which records the engine, its version, the optimiser settings and how each rung is encoded for that engine. A rung that an engine cannot express is reported as not_available with the reason 'not expressible by the engine', never skipped.

The confirmatory model is defined as the result of applying rule R to ladder L, and the user, not the package, declares it primary. Without declared estimands, the protected set cannot be defined. Stream B then returns the ceiling and the verdicts, labels the ladder exploratory and executes no rule. The plan and the report both state that the rule's operating characteristics are known only for the simulated conditions until HPC study H1 has run.

Building the ladder starts by freezing the coding of factors, as numeric contrast columns, and the centring constants, with a record of the sample they came from. Zero-correlation structures change with the coding. In a simulation run for this record (evidence/decisions/B, Sim 4), a zero-correlation fit gave different REML criteria (1773.66 against 1774.99), slope standard errors and df under 0/1 and ±0.5 coding. Rung 0 is the ceiling restricted to identifiable terms.

The protected set, never removed by the ladder, contains:

- the random intercepts of replication and randomisation units
- the by-unit slopes of focal within-unit effects (Barr et al., 2013)
- for a focal interaction, the slope of the highest-order combination of within-unit factors it contains (Barr, 2013)
- the lower-level slope of any focal cross-level interaction (Heisig & Schaeffer, 2019)

Unprotected terms are reduced in a fixed order. Correlations are simplified before variances are removed. Nuisance terms go before anything protected, and higher-order terms before their marginal terms. The order among nuisance terms is a hypothesis for study H2, which varies the slope variances asymmetrically, because omitting correlated nuisance slopes can cost precision (Heisig et al., 2017).

From the first 0.x release, each reduction step uses encodings that all 1.0 engines can express. Numeric slopes become separate uncorrelated terms. For a factor slope with three or more levels, the step after the unstructured matrix is complex random intercepts, (1 | g) + (1 | g:f), with the implied restriction to non-negative correlation stated in the plan. lme4 1.1-35, the version Ubuntu 24.04 ships, has no `cs()` or `diag()`. Rungs written with them, including compound symmetry on the cell indicators, therefore wait for structured-covariance support in version 1.3.

Rung 0 may still contain terms that an engine cannot express. In Python, a plan whose rung 0 statsmodels cannot express (crossed correlated slopes, for example) returns not_available and names the bring-your-own and R routes, rather than starting lower on the ladder. Study V7 tests whether the two languages reach the same rung (Q9).

The default stopping rule is a localised, protected back-off. It reads only the suite's own optimisation statuses and scale-free rank, never engine flags. The ladder steps down in only two cases. The first is non-convergence, which the suite judges by the gap to the best objective found, with a second optimiser as the restart for large q. A fit at near_optimum counts as converged, and its gap is logged. A fit that is not_certified counts as converged only when the second optimiser reaches the same objective within the registry tolerance. V3 tests both choices. The second case is a boundary direction in unprotected terms. If the null space of a random-effects block loads, above a registry tolerance, only on unprotected terms, the ladder steps to the next pre-specified rung that drops those terms. If the null space involves protected terms, the rung is accepted and the zero-variance directions are named.

Decisions use the best objective found, whether by the engine or by the suite's probe, and both values are logged. `diagnose(fit)` never replaces the user's estimates. When Stream A executes a plan, it logs every rung and reports the selected model, the protected rung and the adjacent rung as pre-declared sensitivity analyses.

If the protected rung itself fails, the plan ends in its declared terminal state. The first 0.x release offers two. 'No confirmatory model' reports the failure beside any alternative the user computes outside the suite. For nested designs in R, cluster-robust CR2 inference through clubSandwich in Suggests (Pustejovsky & Tipton, 2018) is also available, labelled engine-specific. Bayesian and penalised terminal alternatives are documented but not implemented. The plan validator rejects any terminal state that the installed version cannot run.

The registered alternatives are protected likelihood-ratio selection at α = .2 (the level reportedly used by Matuschek et al., 2017, still to be confirmed from the full text), protected AIC, no reduction (the ceiling) and an unprotected back-off. The unprotected back-off is available only by explicit opt-in and is flagged in the package's report. The first 0.x release ships neither protected AIC nor the unprotected back-off.

The evidence supports the protected set more firmly than any particular rule. Dropping a focal slope produced Type I error rates of .226 and .187, against .054 and .035 for a nuisance slope. An intercepts-only model reached .200 in a 24-subject by 16-item design and .348 in a 48 by 32 design. A rule that stepped down whenever any block was rank-deficient removed non-zero nuisance slopes in 40 to 45% of datasets when a protected slope had zero variance, at a cost of up to 2.6 power points. The default rule is localised for that reason. Localised back-off, protected LRT(.2) and protected AIC differed by at most .005 in all 14 conditions of the verifier's simulation. That simulation used lme4's absolute singularity tolerance rather than the scale-free criterion adopted here, so V3 and V5 retest the rule.

The choice among the protected rules is therefore a judgement, revisited after study H1. The revisit uses one preregistered rule shared with V1: Type I error predicted by a metamodel with simultaneous bands over the design region, an acceptable band of .025 to .075, and comparison with the ceiling. A naive rule such as 'switch if any cell exceeds .06' would trigger in 63% of 50-cell grids at 2,000 replicates per cell, even for a rule whose true rate is .05. Power is compared after size adjustment.

Stream B runs outcome-blind (T0) by default, in the spirit of blind analysis (MacCoun & Perlmutter, 2015), because the ceiling, the verdicts, the ladder and the plan need no outcome. T1 checks, which read the outcome marginally or by cluster, are enabled only by an explicit outcome-access argument together with the design-plan hash of a frozen plan. Without a plan, they run in a mode labelled exploratory, and a plan created afterwards is stamped as planned after outcome inspection. T2 checks, which relate the outcome to predictors or to a fitted model, run only in Stream A or in an explicit exploratory mode.

The access log, a section of the results document, records the plan hash, each tier accessed, a keyed commitment to the outcome column and the reason given. The report header shows the highest tier accessed before the plan was frozen. Credibility comes from depositing the plan with a third party such as OSF or Zenodo. A hash chain would add nothing that the person controlling the files could not rewrite. For secondary data, the user attests to their prior knowledge of the outcome. Plans written by 0.x releases are marked 'not for preregistration' until the plan schema and the canonicaliser carry versions that later releases can verify.

Masked execution selects and freezes the rung before revealing any estimates. For Gaussian LMMs, the REML and profiled ML likelihoods depend on the outcome only through residuals orthogonal to X, so masking cannot change the rung an automated rule selects. Masking only keeps the focal estimate from the analyst and is therefore an attestation. In Sim 5, refitting with a shifted focal effect left the singularity and warning flags unchanged in 799 of 800 REML fits, and the singularity flag in 798 of 800 ML fits. Masking is deferred to after 1.0, as a two-step API, and GLMMs are excluded until study H9.

The first 0.x release contains:

- the ladder generator and per-rung identifiability
- the localised default rule, protected LRT(.2) and the no-reduction rule
- the two terminal states
- the plan hashes with generated preregistration text
- the access log

A protected set as such is not new. buildmer's `include` argument and lme4's guidance on singular fits already point that way, and the lme4 documentation states that there is not yet consensus on how to choose a random-effects specification. The novelty lies in the outcome-free ladder, the plan contract and their validation.

## Q4. Design declarations

Declarations are optional by default and required in the three situations set out below. Checks whose inputs the data determine run every time: label incidence (nested, crossed or partially crossed), cluster sizes, rank and connectivity. Two properties are inferred with tolerance and reported with 'inferred' wording: the level at which each predictor varies (within or between units) and candidate keys among ID-typed columns. Other properties cannot be read from the data and come only from a declaration:

- whether repeated labels denote the same unit (ID scope)
- whether and at what level assignment was randomised, and the blocking
- the roles of variables and their timing relative to assignment
- the event level, trials and exposure of the outcome
- the disclosure unit for privacy rules
- the focal estimands, dyad roles and the EEG reference

Without a declaration, such a check reports not_available with the reason 'declaration missing', names the field to declare and never recodes. For an undeclared ID scope, the report adds outcome-free evidence, such as whether unit attributes stay consistent across outer units. In mlmRev's Exam data, 269 of 322 shared student labels change sex across schools, whereas in a crossed psycholinguistic dataset none of 600 items changes its frequency or length.

A minimal declaration becomes mandatory in three situations: a confirmatory goal, outcome-blind and preregistration exports, and trial features (cluster-randomised, stepped-wedge and partially nested designs). A `draft_design()` function in both languages writes a declaration pre-filled from inference and marks the inferred entries. The draft counts as a declaration only after the user accepts it, and in outcome-blind mode it reads only ID-typed and right-hand-side columns. A code-first builder in both languages writes the same JSON.

Every design tool reviewed takes structure as a declared input rather than inferring it, including DeclareDesign (Blair et al., 2019) and simr (Green & MacLeod, 2016). Reused labels and genuine crossing produce identical incidence patterns.

The data can show whether a treatment varies within or between units. A rule requiring 99% agreement within clusters recovered the school level in 99.3 to 100% of 2,000 replicates with up to 0.5% of rows miscoded. The data cannot show whether assignment was randomised, what the blocks were or which unit was assigned when small clusters are aliased.

Getting the ID scope wrong matters. In a 20-school design with reused class labels and class-level treatment, coding the classes as crossed gave Type I error rates of 13 to 34% in the conditions where the likelihood would have favoured the true nested structure. Using the outcome to choose between nested and crossed coding is nonetheless excluded on the outcome-blind principle.

Each dataset has one canonical JSON declaration in the hashable profile. JSON Schema (draft 2020-12) is the normative specification. Each package ships a hand-written validator, tested against a shared corpus of valid and invalid files with expected error codes, and the jsonschema library serves as the oracle in CI. Third-party validators cannot be relied on, because they disagree. fastjsonschema, for example, ignored `dependentRequired`.

The table block is a subset of the Frictionless Table Schema v2: field types, categories and their order, missing values including labelled sentinel codes, and primary and unique keys. Categories are not allowed on ID-role columns, so declarations carry no identifiers. Three caveats are documented: the default `fieldsMatch` is 'exact', an absent type means 'any', and R's frictionless package lacks categories.

Readers in both languages apply the conventions above together with these rules:

- rejection of a byte-order mark, of duplicate keys, of keys outside the Basic Multilingual Plane and of lone surrogates
- the number limits of the hashable profile
- the Frictionless lexical defaults, applied explicitly
- numbers written by the ECMAScript rules of RFC 8785, exponents included, in an in-house serialiser tested against the RFC's vectors in both languages

An R and Python prototype gave identical hashes for six example declarations and for the tables of the nine prototypes of zoo fixtures in the evidence (E/zoo) and the matched negative of Z01. Without these rules, however, it diverged on 5 of 8 new declaration edge cases and on 4 of 9 table edge cases.

YAML is accepted for authoring only. It is read with every scalar as a string, through yaml in Suggests in R and PyYAML as an extra in Python, and then converted to JSON.

Vocabulary 0.1 is a core of eight blocks:

- table
- units, with `nested_in`, `id_scope`, membership and role, and a `disclosure_unit` naming the unit that the privacy rules count, by default the unit with role 'participant'
- crossings
- observation: the unit of one row, its key and its time
- assignment: column, unit, level within or between units, randomisation and blocks
- variables: role, `derived_from`, bounds, measurement level, and for outcomes the event level, trials and exposure (raw or logged)
- estimands: term, kind, focal flag and outcome
- provenance: creation date, author, an outcome-seen attestation and a keyed commitment to the data

Unknown keys are errors, including inside table field descriptors. The validators also enforce these rules in code, with conformance tests: non-empty estimands, at least one outcome and one assigned role, referential integrity, the absence of cycles, an observation time whenever membership changes over time, and an assignment block for cluster-randomised, stepped-wedge and partially nested designs.

Any 0.1.x version is accepted. Dyad, EEG, imputation and time-zone detail follow in 0.2 or later. The report's draft schema, with examples and invalid files, is in evidence/decisions/E/schema. It predates the verifier's corrections and still has dyad, EEG and imputation blocks and a `schema_version` fixed at 0.1.0.

## Q5. Reports, privacy and accessibility

The canonical output is the results object, serialised as JSON in the data profile when it is written. The default human-readable output is one self-contained HTML file built from a logic-less Mustache template shared by both languages. Formatting is done beforehand in printf style, so that rendered strings can be compared across languages. The file contains no scripts, makes no external requests and has a print stylesheet for saving it as PDF from a browser. Chromium has tagged such PDFs since version 87, and other browsers have not been checked.

An optional export writes an engine-free Quarto Markdown folder with no code chunks. Values come from a generated metadata file, and the results JSON is included with its SHA-256. Users render it with their own Quarto to HTML, Word or PDF through Typst.

Word and Typst output require Quarto 1.11 or later, because earlier versions dropped figure alternative text in Word and failed on some images with alternative text in Typst. With an older Quarto, the export warns and falls back to HTML. The package never calls LaTeX and never depends on Quarto. In R, quarto (≥ 1.5.0) is in Suggests, guarded by `requireNamespace()` and `quarto_available()`. In Python, the command-line tool is found with `shutil.which()`. The export is scheduled after 1.0 (03-execution-plan.md).

Both packages also produce a preregistration block, which combines Stream B outputs with the declarations the user must supply. They also generate methods text and APA-style tables only from the results, with mandatory elements and banned phrases such as 'assumptions were met'. JARS-Quant (Appelbaum et al., 2018) informs the minimum content, pending a full reading of its tables. Reports show no badges or aggregate scores, and every report states what could not be assessed.

Figures are static and aggregated. Version 1.0 has no interactive plots, because in an experiment run for this record (evidence/decisions/C), an interactive HTML plot embedded every exact value and identifier. Figures are drawn as inline SVG from the shared view model, using three fixed layouts (bands, bars and matrices), so the core report needs no plotting package. Their coordinates are computed by shared logic and stored in the results. The aggregated CSV behind each figure is always written, because that is what output checkers in trusted research environments need. PNG copies are optional: in R through base graphics or rsvg in Suggests, and in Python through a matplotlib extra. They are scheduled after 1.0 (03-execution-plan.md, Milestones). ggplot2 and matplotlib versions of the figures are optional `plot()` methods.

Across languages, strings and figure coordinates must match exactly when they are computed from shared inputs. Other values are compared at reporting precision with the near_threshold status, because aggregates computed separately in each language can differ in the last digit.

One privacy filter in the shared view model applies to everything that leaves the package: figures, alternative text, long descriptions, data tables, methods text and export metadata. By default, every written file is shareable, and the shareable rules are:

- every displayed cell, bin or band contains at least k = 10 distinct members of the declared disclosure unit, or, without one, at least k distinct levels of every grouping factor
- the two largest contributors supply less than 90% of a bin's rows
- a quantile p is shown only if n·min(p, 1 − p) ≥ k
- counts of persons and cross-tabulations of person attributes are shown as '<10' below k, whereas counts of non-person units, parameters and df are shown exactly, because reporting standards require them (the registry classifies every count), apart from the counts of columns and df that give back levels that the filter hides, suppressed since 12 November 2026 (below)
- suppressed tables have every cell rounded to base 5 with the margins recomputed, or secondary suppression applies
- flagged clusters get labels that exist only in the report
- no row-level values, identifiers, minima, maxima, outliers or point plots appear
- no paths, user names or host names appear
- zeros in cross-tabulations of person attributes are treated as disclosive

A banner states that shareable output reduces disclosure risk without making the report anonymous data. Point-level detail appears only in an internal mode, which needs an explicit argument, carries a banner and a file suffix, and writes its point-level figures as PNG. All parameters are stored in the registry and recorded in the results.

The settings follow the confirmed defaults of the ACRO output-checking tool (a threshold of 10, a dominance rule of (2, 0.90), rounding to base 5 and zeros treated as disclosive). Applying the dominance rule to the rows of a bin is this project's adaptation. The export lists the counts behind each statistic for output checkers. GDPR Recital 26 treats pseudonymised data as personal data. The maintainer adopted these settings as the defaults on 8 November 2026. They are to be checked against UK data-protection law and the primary UK output-checking guidance before 1.0 (03-execution-plan.md, Open checks), and the rules of each data provider apply on top of them whenever its data are analysed.

On 11 November 2026 the maintainer chose two tiers of protection for the findings of a shareable document ([privacy.md](../spec/privacy.md), Tiers), over a full guarantee for every value and over the ACRO standard throughout. Four adversarial reviews of the filter and the disclosure-attack tests had each found inferences about design-structure counts that no rule closed, such as quantiles pinned by the rows and levels, products of crossed levels and the reals that give back the rows of a sample, and each closure added a rule, until shareable T1 and T2 documents lost within_share, the GVIF and the standard deviations in most runs and two channels remained open. Output checking as ACRO does it applies the primary rules and the secondary suppression of linear relations and does not promise protection against every inference within an output. Values derived from the outcome, those that would change if only the outcome column or its trials column changed, their values or which rows lack them, keep the full guarantee: one shareable document leaves every hidden outcome-derived value at least two possible values, and a hidden outcome-derived count a possible value of k or more unless the bounds that details state, or the firing of the rule that hides a difference below k, show it below k, whatever inference the reader makes, through the design-structure values that the document writes too. Design-structure values, which depend only on the predictors, keys, labels, grouping columns, assignments and the declaration, follow the primary rules adopted on 8 November 2026 and the secondary suppression of sums, differences and parts of totals, within a finding and across findings and samples. Other inferences about them, such as nonlinear relations, inequalities and crossed designs, are documented as residual risk in privacy.md (Guarantees) and reported by the disclosure-attack tests without failing them.

A document that writes no value of the analysis sample compares no sample with it, so that a gaussian T1 run whose outcome.constant_clusters is suppressed as a whole writes every T0 value that the primary rules allow. One whose outcome.constant_clusters is written, as for a grouping factor whose levels count non-persons beside a disclosure unit, shows the analysis sample, and the rules below apply to it. The rules that protect outcome-derived differences through design-structure values have stayed or been added: the reals and the counts of the levels that a sample loses beside the analysis sample (rule 5 of Across findings), a quantity lost there compared with no other sample, the levels of non-person items compared there when the sample loses its rows or members, the rows of a sample whose level sizes would give back, beside the analysed rows, fewer than k rows without an outcome in the levels that keep one or the analysed levels with one row, the parts of a count that the rules hide in the analysis sample, the quantities that the analysis sample loses, lost by every sample that holds its rows, and the analysis sample's levels, rows or contributors when a sample writes the levels of an item whatever rule 1 hides, hidden when that sample's exceed them by fewer than k. Such items are the combinations of two crossed columns, whose levels are the product of the columns' levels, and the items into which a categorical variable of a term, or the combination of the categorical variables of a term, fixed or random, divides the rows, whose levels the term's columns count, whatever their class. With the basis disclosure_unit, the contributors of a finding count the levels of the disclosure unit, so the rules that hide those levels hide them too. Rule 1 compares no quantity that is 0 in the larger sample, and rule 3 leaves out an item none of whose levels holds two rows of the design sample, since the outcome changes neither. The rules that protected design-structure values from nonlinear inference alone were removed: internal_only on effective_size, icc and smallest_eigenvalue, suppress_with on combinations, the rule on rows and levels outside the analysis sample, the suppression of a losing quantity below k and of missing_key_rows below k, and the clause on crossed columns outside comparisons with the analysis sample. On 12 November 2026 the coordinator closed the one linear relation between design-structure values that the filter of 11 November left open, as a decision taken under the maintainer's standing instruction to decide where the standard already settles the question. The columns that a categorical variable of a term, or the combination of the categorical variables of a term, gives the term, which df of design.collinearity, kept, columns and empty_cells of design.rank_deficiency, dimension of identifiability.levels_vs_dimension, columns of identifiability.residual_confounding and the degrees of freedom of identifiability.df_budget and assignment.design_df count, gave back the levels of an item into which the variable divides the rows, offset by the coding and the other terms, while the filter suppressed those levels. These counts now measure those levels, and the filter suppresses them with the detail 'secondary' where a count of those levels in the rows that the check reads is a person count below k, every finding with such a count fails the minimum-count or the dominance rule, or rule 1 between design-structure samples hides them, and, on rows of an assignment that are the analysis sample, where any rule of the filter hides them there (privacy.md, Across findings, rule 6), so that for them the secondary suppression of linear relations that the standard of 11 November requires takes precedence over showing df exactly. Beside the analysis sample they stay written, and the analysis sample loses its own levels of the item instead, as before, so that whether they are suppressed depends on design-structure values alone (privacy.md, Across findings, rules 1 and 6). The review of the port of the filter to Python found that the variables of a term must be matched to an item on the rows that its counts read, since a grouping column that lacks a label in one row leaves the design sample with that row and otherwise escaped the match, and that the counts of columns of the IR must be suppressed when rule 1 hides the levels of the table. A random term that '||' splits from a frozen factor has one column, whatever the levels, and its counts of columns stay written, while its scope names the levels, as accepted above.

On 13 November 2026, the coordinator accepted in the tier-A guarantee, under the maintainer's delegation, one class of determinations of outcome-derived values ([privacy.md](../spec/privacy.md), Guarantees). Beside the firing of rule 1 of Across findings, which shows fewer than k rows without an outcome, a level that the document shows to hold k rows or more of the design sample cannot have lost every outcome, so the number of such levels without any outcome takes the single value 0 and the analysed levels of their item equal its levels in the design sample. The value follows from the bound of rule 1, which the guarantee already accepts as displayed, and from design-structure values that the reader is allowed to know, such as the crossing of two columns and the written levels of the other column. It shows no outcome value and not which rows lack an outcome, only that no level of k rows or more lost every outcome, which trial reports publish as attrition anyway. The alternative, hiding the analysed and design rows and combinations of every document whose design crosses two columns, would withhold the sample sizes of designs of subjects crossed with items, the main use of crossed mixed models. On 14 November 2026, the coordinator extended the acceptance to every value that a bound shown on the rows without an outcome fixes, since these values too follow from a bound that the document displays and from design-structure values that the reader may know, show no outcome value and not which rows lack an outcome, and the alternative would withhold the sample sizes of crossed designs: k − 1 when the rows of the design sample exceed the analysed rows by fewer than k, so that the first paragraph of rule 1 hides them, or the written rows of a larger sample less the written analysed rows. A level shown to hold n rows or more then keeps n less that bound analysed rows or more, which fixes the levels with no analysed row, those with fewer than two and the counts and statuses that follow from them, as privacy.md (Guarantees) states the conditions. The rows of the analysis sample, the rows of a level, which rows lack an outcome and a count of levels that the bound leaves open keep the guarantee. The same day, the coordinator closed in the filter a value outside the class that the class gave beside a declared observation key whose columns' levels the document or the declaration gives: the product of those levels bounds the distinct key values of the design sample, and the status of keys.duplicates, which Decisions accepts, or its written duplicate_rows and duplicated_keys bound the rows that repeat one, so the analysis sample loses its rows when that bound exceeds them by fewer than k (privacy.md, Across findings, rule 1). The disclosure-attack tests accept the determinations of the class under the label kept-levels and count them apart. The maintainer can reverse the decision. A reversal removes the acceptance from privacy.md (Guarantees) and the predicate of the class from the disclosure-attack tests (R/kept.R, its verdict and its self-test), so that a determination of the class fails the run as any other leak does, and makes both filters hide the values that the bound fixes in every document whose design crosses two columns, with unit tests, corpus cases and parity. zoo-reuse keeps its gate only once the filters hide them.

In the plot experiments run for this record (evidence/decisions/C), an SVG scatter plot yielded all 300 points, and a 100-dpi PNG yielded the five most extreme residuals to within 0.04 to 0.26 units. Rasterising therefore offers no protection.

The HTML report targets WCAG 2.2 level AA (World Wide Web Consortium, 2024). The language and title are set, headings form a hierarchy, and tables have header cells and captions. Every figure has short alternative text, a long description generated from the results and its aggregated data table. Status is conveyed by text and shape, never by colour alone, and content reflows at 320 CSS pixels.

Essential marks use five colours with at least 3:1 contrast against white: blue #0072B2, vermillion #D55E00, bluish green #009E73, reddish purple #CC79A7 and black. The four chromatic colours reach only 1.12 to 1.69 against each other, so adjacent areas are separated by white gaps or outlines and labelled directly. Orange, sky blue, yellow and grey are kept for outlined fills that carry no essential information.

Monorepo CI runs axe-core and an HTML validator on golden reports. A Typst PDF/UA-1 render is checked with veraPDF once the export exists.

## Q6. Dependencies and interoperation

All diagnostic computation is independent of easystats and DHARMa. No check takes its status, threshold or severity from performance, insight or DHARMa.

Cross-checks with those packages are opt-in, through an argument whose default is none, so that installing a package never changes a report. They appear in a separate block without flags, and record the package versions, plus the seed and number of simulations for DHARMa. They stay out of severity grading, the log of rules fired and the parity claims, and include no p-value tests by default. Results can be exported as a plain long data frame.

Four reasons support keeping the computation separate. First, insight 1.7.0's convergence check, which `performance::check_convergence()` wraps, returns FALSE for non-singular fits on which lme4 skipped its derivatives, so fits whose convergence cannot be assessed would be reported as not converged. Second, insight had 22 CRAN releases and performance 13 in two years, so delegated values could change without any change to the registry version. Third, Python cannot call these functions, so every delegated value would be a permanent parity exception. Fourth, insight and performance are GPL-3, so their code can be called but not copied.

lme4 and all other engines go in Suggests, and the R package is not split. Splitting it would double the CRAN submissions and NEWS files for one maintainer, without reducing install weight any further. Imports are Matrix, jsonlite, cli (≥ 3.2.0, MIT, for SHA-256) and utf8 (Apache-2.0, for NFC), plus base packages. The research report measured the dependency closures with Matrix and jsonlite alone (evidence/decisions/D), and the verifier reproduced them:

| Imports | Closure | Note |
|---|---|---|
| Matrix and jsonlite | 3 packages | |
| Plus lme4 | 14 packages | 7 compiled and not recommended |
| Plus glmmTMB | 65 packages | |
| Plus lmerTest, pbkrtest, performance, DHARMa and ggplot2 | 118 packages | |

cli and utf8 add two small compiled packages, and cli brings in only base utils. With DHARMa added to Matrix, jsonlite and lme4, the hard dependency closure runs to 94 packages, 49 of them compiled and not recommended. A hard dependency's R floor can also move without notice. Deriv 4.3.5 began requiring R 4.5, and that requirement now reaches glmmTMB through pbkrtest and doBy.

In R CMD check, both with and without Suggests, a demonstration package showed no undeclared-dependency or S3-consistency problems. Its warnings and note came from the container locale, missing documentation and unused Imports. It dispatched lme4, lmerTest, afex and glmmTMB objects without importing lme4.

The availability guard sits in the generic. It reads the package that defines the object's class and, if that package is missing, returns not_available with the package name before dispatch. A test diagnoses a saved .rds fit with the engine absent, because S4 dispatch on an lme4 object fails before any method-level guard can run.

The lme4 formula grammar is parsed in-house in both languages. reformulas, which is GPL-3 and has compiled dependencies, is used only as a test oracle in Suggests. The HTML template renderer is an in-house Mustache subset, tested against the language-independent Mustache specification tests.

Suggests also holds yaml, lmerTest, pbkrtest, clubSandwich, glmmTMB, afex, performance, insight, DHARMa, lpSolve, openssl (for commitment keys where /dev/urandom does not exist), ggplot2, rsvg, quarto and testthat, and the packages whose datasets the R examples use. The Python package mirrors this structure. numpy, pandas and scipy are in the core. statsmodels, one Rust engine, PyYAML and matplotlib are extras. The not_available vocabulary is the same in both languages.

## Q7. Names and repository

The maintainer chose mixedcheck in both languages on 8 November 2026: the CRAN package, the PyPI distribution and import package, and the conda-forge packages r-mixedcheck and mixedcheck. lmecheck, the name under which the repository was created, is the fallback. Both names are free on CRAN (current and archived, checked case-insensitively), Bioconductor, PyPI (including its similarity rule) and conda-forge, whereas mmcheck is taken on PyPI.

CRAN names are permanent, so the name should fit the eventual scope, which extends beyond linear models to GLMMs. 'lme' and 'lmm' signal linear models only, and 'lme' also evokes `nlme::lme`, which 1.x does not cover. 'mix' suggests mixture models or MCMC mixing. 'audit' fits Stream B but undersells the diagnostics and reports.

`pak::pkg_name_check()` and an R-universe search must confirm the name before the repository goes public. They run as a GitHub Actions job, because the runners can reach CRAN and R-universe. Once M0 is merged and the checks pass, the repository is renamed mixedcheck and made public (03-execution-plan.md, M0). Renaming keeps the repository's history. No placeholder is uploaded to PyPI, because PEP 541 prohibits name squatting.

The project is one monorepo:

| Directory | Contents |
|---|---|
| r/ | the R package root |
| python/ | the pyproject root, with a src layout |
| spec/ | the schema bundle, the registry source (YAML) and the compiled JSON |
| fixtures/ | the zoo, the conformance corpora and the golden files, with provenance and per-directory licence files |
| parity/ | the cross-language harness |
| sim/ | the HPC validation code and SLURM templates, never shipped |
| paper/ | the JOSS paper |
| docs/ | the design documents and specifications |

Every shared artefact is vendored byte-identically into both packages. The registry, the schemas, the Mustache templates with their CSS and the zoo fixtures go into r/inst/ and python/src/mixedcheck/, which are installed. The conformance corpora are test material and go into r/tests/ and python/tests/, which the R tarball and the Python sdist carry but an installation does not, since installed corpora would take the R package above the 5 MB at which R CMD check reports its installed size. CI compares the SHA-256 of each vendored copy with its source in spec/ or fixtures/ and fails on any mismatch. A .gitattributes file turns off Git's line-ending conversion for these files, so that the hashes also match in Windows checkouts. The vendoring check rejects CR characters in spec/ sources, and fixtures keep their deliberate CRLF cases (03-execution-plan.md, M0).

Every install path supports subdirectories: remotes and pak references, pip's `#subdirectory=` and R-universe's `subdir` field. PyPI Trusted Publishing builds from python/. The two packages carry their own versions with language-prefixed tags (r-v*, py-v*) and share one Zenodo concept DOI. They are released together whenever the registry's minor version changes, and patch releases of either package may go out independently.

The large dual-language monorepos (arrow, xgboost and LightGBM) need build-time scripts only because they share C++ code, which this project does not. All the same-name precedents (marginaleffects, pins, vetiver, pointblank and duckdb) use separate repositories, so the projects examined include no pure R and Python monorepo. For one maintainer and one shared registry, a single repository avoids synchronising the registry and fixtures across repositories.

## Q8. Domains and test corpus

Two designs drive the defaults, the message wording and the first vignettes. The first is nested education data, including cluster-randomised and multisite trials. The second is crossed subjects-by-items designs with trial-level data. They match the maintainer's fields, span nesting and crossing, and between them exercise most Stream B checks: label scope, randomisation level, few clusters, design df, connectivity, one observation per cell and counterbalancing.

In version 1.0, the crossed vignette uses a Gaussian outcome (log response times) for Stream A, and binary accuracy appears only in Stream B audits until GLMMs arrive. After 1.0, longitudinal and intensive longitudinal data, including app logs, follow once the time, time-zone and lag infrastructure exists, and families and dyads follow, fixtures first. Single-trial EEG comes last, because the ERP CORE data (Kappenman et al., 2021) are large and carry a ShareAlike licence.

Defaults remain design-agnostic. Domain checks and wording switch on from declared features, or from data patterns with 'inferred' wording.

The test corpus has four layers:

1. A simulated pathology zoo, MIT-licensed and bundled in both packages ([fixtures/zoo/](../../fixtures/zoo/README.md)). It holds 31 fixtures, the thirty of this record and the attribute-consistency fixture Z31, and 29 clean matched negatives, since Z03N is the negative of Z03 and of Z31 and Z08 that of Z09. Each has a seeded generator in sim/zoo/, a tiny stored instance, a declaration that types its CSV, a preliminary formula and expected findings derived from the generating design rather than from the suite. The 60 CSV files total 167 KB. Parsing-hazard, C-locale and attribute-consistency fixtures join the zoo: Z18, Z19 and Z20 hold labels that the CSV must quote, sentinel codes with CR LF line endings and identifiers in two Unicode forms, and Z03, Z03N and Z31 repeat teacher labels without attributes, with constant attributes and with changing ones.
2. Public datasets from R packages, such as those in lme4, nlme, mlmRev, languageR and afex. R examples use them through Suggests, and CI materialises them for parity tests, but neither package redistributes them. The licences of the data themselves could not be determined, and several of the packages are GPL or AGPL. Vignettes shared across languages therefore use zoo fixtures, which also gets round the lack of any Python route to the languageR or afex datasets through Rdatasets.
3. Openly licensed external data, in a corpus folder that is never shipped. It has per-dataset licence files with REUSE annotations and a manifest of licence evidence. Packages and fixtures accept only CC0 or CC BY, so ShareAlike material such as ERP CORE derivatives stays in this folder, and each dataset is added only after a local licence check.
4. The maintainer's restricted data, used only for private validation. This happens inside the data's own trusted research environment, using the released packages and exporting only shareable output, or on ARC if the data agreement explicitly permits it. The data are never committed.

HPC validation grids cover only stochastic or thresholded checks. Deterministic checks are covered by unit tests, and so are the disclosure tests of the privacy filter.

## Q9. Validation on the HPC and papers

The maintainer approved simulation validation on the Oxford HPC and a paper, without co-maintainers. The validation programme follows the ADEMP structure (Morris et al., 2019) and is preregistered with the ADEMP-PreReg template (Siepe et al., 2024) after the H0 pilot. All studies share one codebase and run as SLURM job arrays on ARC's htc cluster, in a portable Apptainer image (03-execution-plan.md, H0 and M6).

| Study | Scope | Timing |
|---|---|---|
| V0 | Deterministic audits, validated by known-answer fixtures in CI | Every release |
| V1 | A Gaussian null bank on which every check runs, giving false-flag rates and family-wise flag counts | 1.0 |
| V2 | Targeted misspecification modules, giving detection rates and the consequences for focal estimands, judged on the whole check-then-act procedure rather than on detection alone (Shamsudheen & Hennig, 2023) | 1.0, priority modules first |
| V3 | The one optimisation criterion and the scale-free singularity criterion | 1.0 |
| V4 | Variance-component tests and the parametric bootstrap | After 1.0, unless 1.0 reports such tests |
| V5 | The reduction ladder (studies H1, H2 and H5) | 1.0 |
| V6 | Calibration of outcome-blind design analysis | After 1.0, since 1.0 makes no such predictions |
| V7 | Cross-language parity, including the rung reached in nested and crossed variance-component designs, and cross-engine conformance on every benchmark design (200 to 500 replicates, with preregistered certification of the optimum and the corpus versioned with the registry) | 1.0, and regenerated parity tiers gate 1.0 |
| V8 to V10 | The GLMM counterparts | 1.1 |

Failures and non-convergence count as outcomes and are never dropped (Pawel et al., 2026). The study declares itself non-neutral, because the developer evaluates their own checks. It includes comparators in their default configurations: performance, DHARMa, engine-native flags and naive variants (Boulesteix et al., 2013).

Each check is defined exactly as its registry entry before any pilot result is interpreted. The verifier showed why. A pilot ran a Bartlett test across clusters and found no inflation for the small-cluster heteroscedasticity item. The comparison the item names, by cluster-size stratum, gave false-flag rates of .07 to .18 at a nominal .05 with raw conditional residuals, and .054 to .080 with studentised ones.

The decision rules are preregistered. A test-based check at a nominal .05 is calibrated if its false-flag rate, as predicted by a metamodel, stays within an acceptable band of .025 to .075, with simultaneous bands over the design region. This acceptable band is Bradley's liberal criterion of 0.5 to 1.5 times the nominal level, labelled as a convention (Bradley, 1978), and the same rule decides V5. A descriptive flag graded consequential needs a predicted false-flag rate of at most .05. Assessability is adequate if detection reaches .80 at the smallest harmful magnitude, weak between .50 and .80 and not_assessable (low detection) below .50. Harm means coverage below .925, Type I error above .075 or relative bias above 10%, and for null estimands it means absolute bias above a registry threshold.

Thresholds are tuned on a calibration half and confirmed on a held-out half. Replicate counts follow Monte Carlo SE targets of about .005 for rates near .05 (2,000 replicates) and at most .016 for detection (1,000 replicates). The default influence check is a one-step approximation, and exact cluster-deletion refits run only in their own module, at 2,000 replicates.

Engine versions are pinned (lme4 ≥ 2.1-0), and the language, engine and version behind each threshold are stored as registry provenance. Sentinel cells are rerun at each major engine release. This matters because, since 1.1-38, lme4 skips derivative-based convergence checks for singular fits, for lmer fits with 10 or more covariance parameters, for glmer fits with 20 or more parameters and for data with 10,000 or more rows. Python takes on the validated thresholds only once V7 shows that both languages compute the same statistics.

With the cap on the H1 grid dropped, as the verifier advised, Phase 1 needs about 1,140 CPU-hours as a central estimate. This includes about 100 for V4 and V6, which the study table schedules after 1.0. The central estimate assumes current lme4 settings, Satterthwaite and Kenward–Roger inference, allFit with seven optimisers and an un-nested V6. The high band of the cost model is about twice the central figure. The one-step influence rule avoids exact influence refits in every null replicate. Added to the research report's uncapped estimate of about 1,930 CPU-hours at lme4 1.1-35.1 timings, those refits raised it by about 1,120 CPU-hours, to about 3,050.

Phase 2 (version 1.1) needs about 270 CPU-hours. The conformance study of engines has not yet been costed and is to be budgeted separately. It needs more than 2 GB per task, because statsmodels peaked at 1.6 to 1.7 GB on 40,000 rows in a run reported in 01-design-review.md. The H0 pilot re-costs H1 with the real stopping-rule walk (03-execution-plan.md, H0). Every Phase 1 scenario the verifier costed came to between 820 and 3,051 CPU-hours. Provided the project's credit allocation on ARC is confirmed, the binding constraint is therefore maintainer time rather than compute.

The recommended paper route has three parts. The first paper is a Stage 1 Registered Report on the ladder and stopping-rule study (V5, with the V3 criteria it depends on). It is submitted to Behavior Research Methods or to Advances in Methods and Practices in Psychological Science once the plan object and the R convergence-triage core exist (M3 and M3b). The ADEMP-PreReg authors list both journals as accepting Registered Reports of simulation studies. In-principle acceptance before the main runs protects a sole maintainer against unwelcome results, such as a default stopping rule that fails its preregistered criterion.

Studies V1, V2 and V7 run under an OSF preregistration that gates release 1.0 without waiting for journal review, and their results, including cross-engine conformance, go into the validation paper. That paper goes to Behavior Research Methods as a preregistered regular article, which is also the fallback route for the ladder study. Psychological Methods becomes the target only if the paper is reframed as a general comparison of diagnostic procedures.

The software paper goes to JOSS, for both packages, once the repository has more than six months of public history and evidence of research use beyond the tool's own papers. JOSS scrutinises single-author projects without community engagement, and its papers must not focus on research results. The JOSS paper therefore describes only the software, covering the diagnostic contract and the design audits. JSS is the single-paper alternative and would replace JOSS.

Venue facts beyond JOSS's own documentation remain to be confirmed on the publishers' sites in the local session (03-execution-plan.md, Open checks). The work is gated by milestones rather than months (03-execution-plan.md).

## Q10. Versions and licence

The R package declares `Depends: R (>= 4.2.0)`. The current release is R 4.6.2 (29 October 2026). The tidyverse policy of supporting the current and four previous minor versions (Averick, 2019) puts the floor at 4.2. R 4.2 also made UTF-8 the native encoding on Windows, although the encoding conventions above are still needed elsewhere, as the C-locale case shows.

CI runs these jobs:

- Ubuntu with R-devel, release, oldrel-1 and 4.2
- Windows and macOS with the release
- one job without Suggests (`_R_CHECK_DEPENDS_ONLY_=true`)
- one job under LC_ALL=C
- one job with lme4 1.1-35.1

`diagnose()` accepts lme4 ≥ 1.1-35, but results from versions below 2.1-0 carry the outside_validated_range status. Rungs that need `cs()` or `diag()`, and every GLMM feature, require lme4 ≥ 2.1-0. lme4 2.x needs headers from Matrix 1.5-0 or later, which R 4.2.0 and 4.2.1 do not bundle, and current Matrix requires R 4.4. Stream A with lme4 2.x on R 4.2 therefore needs either R 4.2.2 or later (R 4.2.2 bundles Matrix 1.5-1, as CRAN's directory of its recommended packages, src/contrib/4.2.2/Recommended, shows) or an archived Matrix between 1.5-0 and 1.6-5. glmmTMB, pbkrtest and afex cannot currently be installed from source below R 4.5, because of Deriv. The R 4.2 CI job, which resolves to 4.2.3, therefore checks core features without engines. The R floor rises only when a dependency or a feature requires it, within the five-version window.

The Python package declares `requires-python = ">=3.11"`. The rule is the oldest CPython version still receiving security fixes at the first release, but no lower than the numpy and scipy floors need. Python 3.10 reached end of life on 1 October 2026. 3.11 receives security fixes until about October 2027, after which the floor becomes 3.12.

Core dependency floors follow SPEC 0 at release time (Mueller et al., 2020). They are currently numpy ≥ 2.3, scipy ≥ 1.15.3 and pandas ≥ 2.3. The scipy floor is the patch release 1.15.3, since `scipy.optimize.linprog()` takes time quadratic in the number of variables of a program before it, which made outcome.separation take minutes from about 10,000 observations (11 November 2026). The test of the time of the check on 20,000 observations runs at every version of the matrix, so that the lowest direct resolution, which installs scipy 1.15.3, guards the floor. The statsmodels extra requires statsmodels ≥ 0.15.0. CI tests the latest resolution on Python 3.11 to 3.15 and the lowest direct resolution on 3.11, the declared minimum. The floor releases of numpy, scipy and pandas ship wheels for 3.11 to 3.13 but not for 3.14 or 3.15. CI also covers both pandas 2.3 and 3.x while 2.3 remains within SPEC 0, because pandas 3 infers a new string dtype.

Both packages, and everything else that ships (registry, schemas and simulated fixtures), are MIT-licensed. The external-data corpus in the monorepo keeps its own CC0, CC BY or CC BY-SA licences, marked per directory. The maintainer holds the copyright. R uses 'MIT + file LICENSE' with a two-line stub giving the year and copyright holder. Python uses the PEP 639 licence expression with the full text. The two licence files are kept separate.

Running GPL-2, GPL-3, AGPL-3 or LGPL dependencies does not conflict with an MIT package. The R FAQ states that the GPL restricts only the distribution of R or of programs containing its code, and the FSF lists the Expat (MIT) licence as GPL-compatible (to be confirmed on gnu.org). The network clause of the AGPL-3 binds only modified versions. CRAN distributes many permissive packages with GPL-family dependencies, 25 in a sample of 171.

Code is never copied or translated from GPL or AGPL packages. Algorithms are implemented from papers and documentation, and the provenance of each is logged. The log records any AI assistance in writing the implementation, which JOSS also requires authors to disclose. Third-party data enter shipped fixtures only under CC0 or CC BY with attribution. Any inlined third-party JavaScript, CSS or fonts would need their own notices, which the report design avoids.

## Decisions for the maintainer

The following choices rest with the maintainer. On 8 November 2026, the maintainer chose the package name, subject to the registry checks (Q7), and settled the copyright holder, repository visibility and the privacy settings. The paper route stays open until P1, with a recommended default. The other rows restate decisions recorded under Q1, Q2, Q3, Q8 and Q10 for the maintainer to confirm.

| Choice | Decision or recommended default |
|---|---|
| Copyright holder | The maintainer, as LICENSE states (Q10) |
| Repository visibility | Renamed mixedcheck and made public once M0 is merged and the name checks pass (Q7 and 03-execution-plan.md, M0). The six months of public history JOSS requires start only then (Q9) |
| First paper and gating of 1.0 | Recommended: a Stage 1 Registered Report on the ladder study after M3 and M3b, with V1, V2 and V7 under an OSF preregistration that gates 1.0 without waiting for review. Settled at P1, with the H0 results in hand (Q9) |
| Privacy settings | The shareable defaults of Q5 (k = 10 members of the disclosure unit, dominance (2, 0.90), shareable files by default, detail only in internal mode, and exact counts for non-person units, parameters and df), adopted on 8 November 2026, with the counts of columns and df that give back levels that the filter hides suppressed since 12 November 2026 and the class kept-levels accepted in the tier-A guarantee since 13 November 2026, and checked against the UK guidance before 1.0 (Q5) |
| Python route for designs statsmodels cannot express | statsmodels and bring-your-own estimates, with not_available naming the R and bring-your-own routes (Q1, Q3) |
| Terminal state when the protected rung fails | 'No confirmatory model' in both languages, plus CR2 for nested designs in R (Q3) |
| Oldest supported engines | lme4 ≥ 1.1-35 with an outside_validated_range status below 2.1-0, and lme4 ≥ 2.1-0 for structured rungs and GLMMs (Q10) |
| Where restricted data are analysed | Inside the data's own trusted research environment, or on ARC only if the agreement permits it (Q8) |
| Engine estimates versus the suite's better optimum | The walk decides on the best objective found and logs both values, and `diagnose(fit)` never replaces the user's estimates (Q3) |
| Plans from 0.x releases as preregistrations | Not until the plan schema and the canonicaliser are versioned and later releases can verify earlier plans (Q3) |
| Satterthwaite df in 1.0 | lmerTest in R, labelled engine-specific, and not computed in Python. In-house in both languages after 1.0 (Q1) |
| Early binary GLMM support | Only if the maintainer's own analyses need it before 1.1, under the rule in Q2 |

## References

Appelbaum, M., Cooper, H., Kline, R. B., Mayo-Wilson, E., Nezu, A. M., & Rao, S. M. (2018). Journal article reporting standards for quantitative research in psychology: The APA Publications and Communications Board task force report. *American Psychologist, 73*(1), 3–25. https://doi.org/10.1037/amp0000191

Averick, M. (2019, April 1). *R version support*. Tidyverse Blog. https://www.tidyverse.org/blog/2019/04/r-version-support/

Barr, D. J. (2013). Random effects structure for testing interactions in linear mixed-effects models. *Frontiers in Psychology, 4*, Article 328. https://doi.org/10.3389/fpsyg.2013.00328

Barr, D. J., Levy, R., Scheepers, C., & Tily, H. J. (2013). Random effects structure for confirmatory hypothesis testing: Keep it maximal. *Journal of Memory and Language, 68*(3), 255–278. https://doi.org/10.1016/j.jml.2012.11.001

Blair, G., Cooper, J., Coppock, A., & Humphreys, M. (2019). Declaring and diagnosing research designs. *American Political Science Review, 113*(3), 838–859. https://doi.org/10.1017/S0003055419000194

Boulesteix, A.-L., Lauer, S., & Eugster, M. J. A. (2013). A plea for neutral comparison studies in computational sciences. *PLoS ONE, 8*(4), Article e61562. https://doi.org/10.1371/journal.pone.0061562

Bradley, J. V. (1978). Robustness? *British Journal of Mathematical and Statistical Psychology, 31*(2), 144–152. https://doi.org/10.1111/j.2044-8317.1978.tb00581.x

Green, P., & MacLeod, C. J. (2016). SIMR: An R package for power analysis of generalized linear mixed models by simulation. *Methods in Ecology and Evolution, 7*(4), 493–498. https://doi.org/10.1111/2041-210X.12504

Heisig, J. P., & Schaeffer, M. (2019). Why you should always include a random slope for the lower-level variable involved in a cross-level interaction. *European Sociological Review, 35*(2), 258–279. https://doi.org/10.1093/esr/jcy053

Heisig, J. P., Schaeffer, M., & Giesecke, J. (2017). The costs of simplicity: Why multilevel models may benefit from accounting for cross-cluster differences in the effects of controls. *American Sociological Review, 82*(4), 796–827. https://doi.org/10.1177/0003122417717901

Kappenman, E. S., Farrens, J. L., Zhang, W., Stewart, A. X., & Luck, S. J. (2021). ERP CORE: An open resource for human event-related potential research. *NeuroImage, 225*, Article 117465. https://doi.org/10.1016/j.neuroimage.2020.117465

Liddell, T. M., & Kruschke, J. K. (2018). Analyzing ordinal data with metric models: What could possibly go wrong? *Journal of Experimental Social Psychology, 79*, 328–348. https://doi.org/10.1016/j.jesp.2018.08.009

MacCoun, R., & Perlmutter, S. (2015). Blind analysis: Hide results to seek the truth. *Nature, 526*(7572), 187–189. https://doi.org/10.1038/526187a

Matuschek, H., Kliegl, R., Vasishth, S., Baayen, H., & Bates, D. (2017). Balancing Type I error and power in linear mixed models. *Journal of Memory and Language, 94*, 305–315. https://doi.org/10.1016/j.jml.2017.01.001

Morris, T. P., White, I. R., & Crowther, M. J. (2019). Using simulation studies to evaluate statistical methods. *Statistics in Medicine, 38*(11), 2074–2102. https://doi.org/10.1002/sim.8086

Mueller, A. C., Sipőcz, B., Millman, J., Munk, M., Haberland, M., Bussonnier, M., Gommers, R., Barnowski, R., van der Walt, S., & Caswell, T. A. (2020). *SPEC 0: Minimum supported dependencies*. Scientific Python Ecosystem Coordination. https://scientific-python.org/specs/spec-0000/

Pawel, S., Bartoš, F., Siepe, B. S., & Lohmann, A. (2026). Handling missingness, failures, and non-convergence in simulation studies: A review of current practices and recommendations. *The American Statistician, 80*(1), 31–48. https://doi.org/10.1080/00031305.2025.2540002

Pustejovsky, J. E., & Tipton, E. (2018). Small-sample methods for cluster-robust variance estimation and hypothesis testing in fixed effects models. *Journal of Business & Economic Statistics, 36*(4), 672–683. https://doi.org/10.1080/07350015.2016.1247004

Shamsudheen, I., & Hennig, C. (2023). Should we test the model assumptions before running a model-based test? *Journal of Data Science, Statistics, and Visualisation, 3*(3). https://doi.org/10.52933/jdssv.v3i3.73

Siepe, B. S., Bartoš, F., Morris, T. P., Boulesteix, A.-L., Heck, D. W., & Pawel, S. (2024). Simulation studies for methodological research in psychology: A standardized template for planning, preregistration, and reporting. *Psychological Methods*. Advance online publication. https://doi.org/10.1037/met0000695

World Wide Web Consortium. (2024, December 12). *Web Content Accessibility Guidelines (WCAG) 2.2* (W3C Recommendation). https://www.w3.org/TR/WCAG22/
