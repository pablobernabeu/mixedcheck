# Fitted-model contract v1 and initial parity tiers (key A, Q1)

## A. What any adapter must supply (R = required, O = optional capability flag)

Principle: the engine supplies estimates and declarations. The suite recomputes everything that has a closed form from its own canonical design (IR) and checks the engine against its own reference objective before any diagnostic runs.

| Field | R/O | Content and units | Why (benchmark evidence) |
|---|---|---|---|
| `engine`, `engine_version`, `adapter_version`, `contract_version` | R | Strings | Behaviour changes between versions: lme4 1.1-35 AGQ log-likelihood lacked constants (84 units on cbpp); mixedlm 1.3.0 changed GLMM estimation |
| `ir_hash` and `analysis_rows` | R | Hash of the suite's canonical model IR; integer row indices after NA handling | The suite rebuilds X and Z itself. Engines differ in reference level (C vs a), coefficient naming (`f.1` vs `fa`) and the aliased column they drop |
| `coef_map` | R | Engine coefficient name to canonical IR column, plus aliased flags | mixedlm names `f.1`/`f.2` and drops a different aliased column from lme4; statsmodels drops none |
| `criterion` | R | One of REML, ML, Laplace, AGQ(k), nAGQ0, VB, MAP, other; plus `exact_likelihood` (bool) | gpboost's default likelihood is a stochastic approximation (reported minus exact: 0.08 to 0.6 units) |
| `weights_semantics` | R | precision, frequency or log-likelihood multiplier | glmmTMB 1.1.8 treats Gaussian weights as log-likelihood multipliers (sigma 0.85 vs 2.06 in lme4: a different model) |
| `beta` | R | Estimates on canonical columns | |
| `re_cov` | R | For each IR block, the absolute covariance matrix in canonical term order, with packing order declared | glmm returns a column-major vech; my first adapter unpacked it row-major and the objective-match test caught the error on the only 3 x 3 block |
| `sigma2` or `dispersion` | R | Canonical dispersion parameterisation (catalogue L3-22) | |
| `reported_objective` | R | Engine's -2 log L or criterion at its optimum, with its constant convention | Feeds the objective-match test |
| `vcov_beta` and `vcov_method` | R | Matrix plus one of `conditional_on_theta`, `joint_observed_hessian`, `finite_difference_hessian`, `expected_information`, `posterior` | LMM: statsmodels and glmmTMB use the joint Hessian (2.4% from lme4 on a school-level predictor). GLMM: lme4 1.1-35, mixedlm and glmm/glmmTMB disagree by 1–2.2% |
| `convergence` | R | Engine flag, optimiser, iterations, raw messages tagged by source | Stored verbatim; the suite computes its own codes |
| `singular_flag_engine` | O | As reported | statsmodels and gpboost have none |
| `X`, `Z` | O | Sparse; used only to verify against the IR | glmm and gpboost do not expose Z |
| `ranef`, `condvar` | O | Labelled by level; used only to cross-check the suite's own values | mixedlm returns no level labels |
| `objective_fn(par)` | O | Callable; used for cross-evaluation | Present in mixedlm, statsmodels and gpboost; absent from glmm in Python |
| `refit(start, criterion, data_rows)` | O | Needed for influence, ML refits and allFit-style triage | Without it those checks return `not_available` |
| `simulate`, `df` | O | Engine-specific extras, recorded as such | |

Suite-side checks run on every fit:
1. Objective match: |reported_objective - reference objective at the reported estimates| <= max(1e-6 * |dev|, 1e-6). Otherwise status `contract_mismatch` and Stream A stops.
2. Optimality: the gap from the best known objective (multi-start or boundary probe for small q, catalogue L4-21), plus the reference gradient and Hessian in the interior. Statuses: `at_optimum`, `near` (gap <= 1e-2) or `not_converged`, whatever the engine's flag says.
3. Recompute in the suite: BLUPs, conditional variances (beta fixed; PEV with beta uncertainty as a separate, labelled quantity), residuals, P-based quantities, a scale-free singularity verdict, and vcov(beta) under one declared convention.

## B. Initial parity tiers from this benchmark (27 models; versions as tested)

Tiers: exact; tolerance (common objective within max(1e-4, 1e-9 * |dev|) of the best and beta within 1e-2 SE units; a tier is assigned per engine and output class); engine-specific (documented disagreement, registry entry); unavailable.

| Engine | Gaussian LMM estimates and objective | LMM SEs | GLMM Laplace estimates and objective | GLMM AGQ | GLMM SEs | Near-boundary or singular fits | Notes |
|---|---|---|---|---|---|---|---|
| lme4 1.1-35.1 (reference) | tolerance (22/22) | reference (conditional on theta) | tolerance (gaps 8.7e-6 and 3.5e-5) | estimates tolerance; reported logLik engine-specific (missing constants before 2.1-0) | engine-specific (finite differences) | tolerance | |
| glmmTMB 1.1.8 | tolerance, except crossed_ML (false convergence, gap 7.1, non-PD Hessian) and jq_REML (gap 0.014) | engine-specific (joint Hessian) | tolerance | unavailable | tolerance vs glmm | engine-specific (warns; no singular flag) | Weights: engine-specific (different model). Current CRAN 1.1.15.2 not tested |
| statsmodels 0.15.0 | tolerance for interior optima (13/13 at optimum) | engine-specific (joint Hessian) | unavailable (Bayesian only: engine-specific, not comparable) | unavailable | unavailable | engine-specific: gaps 0.013–1.16 on 4/4 designs; 2 flagged converged | Crossed correlated slopes, weights and offsets: unavailable. Crossed variance components: 130–313 x slower than lme4 |
| mixedlm 1.3.0 | tolerance (22/22) | tolerance (matches lme4 within 6e-5) | tolerance (5/5) | tolerance (2/2) | engine-specific (2.2% from lme4) | tolerance (flags singular) | Naming and aliasing differ: map through the IR |
| glmm 0.8.0 | tolerance (22/22) | tolerance (within 6e-5) | tolerance (5/5) | tolerance (2/2) | tolerance vs glmmTMB (exact Hessian) | tolerance (flags singular and pinned) | No Z or objective callable in Python |
| gpboost 1.8.0, Cholesky | near (gaps up to 3.4e-3) | engine-specific | near (gaps up to 2.8e-4) | unavailable | engine-specific | engine-specific | ML only; independent slopes only |
| gpboost 1.8.0, default | engine-specific (gap 0.12 on pastes_ML; approximate likelihood) | engine-specific | near | unavailable | engine-specific | engine-specific | Not suitable for confirmatory diagnostics |
| rpy2 to lme4 | identical to lme4 | identical | identical | identical | identical | identical | CI-only parity bridge |

Decision rule for promoting an engine to "supported": the conformance corpus passes at tolerance tier on three consecutive upstream releases; the contract fields the adapter reads have not broken for 12 months; and the upstream has more than one active maintainer or an institutional home. Until then the adapter is "experimental": an optional extra, version-pinned, and run weekly in CI against the latest release.
