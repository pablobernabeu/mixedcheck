# Design review catalogue

Verified edge cases, features and architecture points from the November 2026 design review (summarised in ../01-design-review.md). Seven reviewers, each with one lens, proposed items. One adversarial verifier per lens checked them, and a completeness critic looked for gaps. Each item gives the reviewer's claim and proposed handling, followed by the verifier's verdict and correction. Where the verdict is 'partly_correct', the correction supersedes the claim.

Sources named by reviewers were not all re-checked independently. Treat a reference here as unverified unless it also appears in the reference list of ../01-design-review.md or ../02-decisions.md. Paths beginning with 'scratchpad/' name scripts in the ephemeral review environment. The scripts were not kept, and the paths record only how a result was obtained.

## L1 Data structure, design and identifiability


### L1-01 Nesting/crossing audit: detect reused inner labels, but never auto-recode to an interaction ID

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P1). Verdict: partly_correct.


Claim. lme4 and glmmTMB read each grouping factor's levels literally. If class labels '1','2',... are reused across schools, (1|school)+(1|class) merges every class labelled '1' into one level and creates a spurious partially crossed school x class structure. (1|school/class) expands to (1|school)+(1|school:class) and gives the intended nested model whatever the coding. When class IDs are already unique, it is identical to (1|school)+(1|class). P1 overstates what the data can show, because reused labels look the same as real cross-classification (pupils who change school, teachers working in several schools, items shared across lists). Proposing an interaction ID automatically would split one real teacher or pupil into several units and silently change the model.


Handling. On the analysis sample, compute for every ordered pair of grouping factors (A, B) the number m(b) of distinct A levels per B level and the A x B incidence fill rate. Classify the pair as nested (all m = 1), fully crossed (every cell filled) or partially crossed, and report the share of B levels with m > 1. Raise 'probable implicit nesting' when most B levels have m > 1 and the labels inside each A level form short repeated sequences that overlap heavily across A levels. Raise 'mobility / multiple membership' when only a small share of B levels have m > 1, and list those units. Require a design declaration (e.g. 'nest: class in school', 'cross: subject x item') and check the data against it. Offer school:class or a/b syntax as a fix only under a 'nested' declaration. Under mobility, state that a strictly nested model is misspecified for the units listed.


Parity. Exact tier (pure data audit). Requires identical canonical IDs first (L1-20).


Verifier's correction. If class labels are reused across schools, (1|school)+(1|class) merges same-labelled classes. The result is partially crossed, or fully crossed when every school uses the same label set. The rest stands: diagnose from incidence, require a nest/cross declaration and offer school:class only under a 'nested' declaration.


Verifier's reasoning. The mechanism is right. lme4 and glmmTMB treat factor levels literally, and the a/b syntax expands to (1|a)+(1|a:b). With unique inner IDs, (1|school)+(1|class) induces the same partitions as (1|school)+(1|school:class). The warning against auto-recoding is well founded: reused labels cannot be told apart from real cross-classification. One point is imprecise: reused labels give a spurious partially crossed structure, or a fully crossed one when every school uses the same label set 1..k, which is the common case. The 'short repeated sequences' heuristic is reasonable but is pattern-matching on labels, so it should be labelled as such. The declaration-first handling is sound.


Evidence checked. Expansion of a/b and literal factor handling are standard lme4/reformulas behaviour (reformulas utils.R on GitHub raw). The reviewer's case (d) in scratchpad/L1/scripts/ident.py re-run: nested model identified (rank 3/3).


### L1-02 Aliased grouping factors and grouping factors with one row per level

Kind: edge_case. Stream: B. Priority: essential. Origin: new. Verdict: correct.


Claim. Two random-intercept terms whose grouping factors induce the same partition of the analysis sample have identical covariance bases Z_k Z_k', so only the sum of their variances is identified. Examples are one class per school and a session ID that equals the subject ID after deletion. Numerically, (1|school)+(1|school:class) with one class per school has REML-projected covariance-basis rank 2 of 3, with null vector (sigma2_school - sigma2_class). If only 2 of 10 schools have more than one class, the model is formally identified, but the class variance rests on those 2 schools alone. In a Gaussian model, a grouping factor with J = N (one row per level) duplicates the residual.


Handling. Test partition equality in both directions (A refines B and B refines A) with a label-free comparison. Report 'aliased' as an error. Report 'nearly aliased' with the number and share of outer levels that contain 2 or more inner levels, and how many observations they hold. Report J/N for every factor, and treat J = N in a Gaussian model as an error. Feed every term into the general identifiability test (L1-06).


Parity. Exact tier (pure partition logic).


Verifier's reasoning. I reproduced the numbers. One class per school gives rank 2/3 with null direction (+school, -class). With 2 of 10 schools holding 2 classes, the model is identified (cond 38). J = N with a free residual duplicates the identity basis. lme4 already stops in the J = N case for lmer (check.nobs.vs.nlev, nlev >= n), but not for glmer (allow.n = TRUE). Partition equality is the right label-free test, and aliasing of a grouping factor with a combination of others is correctly delegated to L1-06. I add two minor points. First, glmmTMB has no such nobs/nlev check, so J = N fits silently there. Second, for Poisson/binomial(>1 trial), J = N is a legitimate OLRE, and the item already allows for this by treating J = N as an error only in Gaussian models.


Evidence checked. Re-ran scratchpad/L1/scripts/ident.py case (e): rank 2/3, null {sch:+1, cls:-1}. The 2/10 schools case gave rank 3/3. lme4 modular.R checkNlevels (nlevelVec >= n unless allow.n): https://raw.githubusercontent.com/lme4/lme4/master/R/modular.R. grep of glmmTMB.R found no nobs-vs-nRE/nlev check: https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/R/glmmTMB.R


### L1-03 Within/between/partially-within status per term and grouping factor: a 'between' slope is uninterpretable, not always unidentified

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P2). Verdict: partly_correct.


Claim. For a term t (all of its model-matrix columns) and a grouping factor g, the definitions are:
- t is between-g if its columns add no rank beyond the intercept inside every level of g.
- t is within-g if they add rank in every level of g that has 2 or more rows.
- t is partially within otherwise.
For a between-g x, Z_j of (1+x|g) has rank 1 in every group, so b1j is never estimable as a slope. The marginal covariance becomes (s0^2 + 2 x_j s01 + x_j^2 s1^2) 11', a between-group variance function of x_j. P2's claim that the model is 'unidentifiable' is overstated. Numerical checks of the REML-projected basis rank give:
- binary between-subject x with a correlated slope: rank 3 of 4, unidentified (null vector 0.5*s01 - s1^2);
- binary x with an uncorrelated slope: identified, as a heteroscedastic intercept variance;
- continuous or 3-valued between-subject x with a correlated slope: identified.
Any such 'slope variance' is therefore driven by an assumed functional form for between-group heteroscedasticity.


Handling. Output a matrix of terms x grouping factors. Each cell gives the status, the number of groups in which the term varies and, for continuous predictors, the within-group share of variance. Flag 'near-between' terms that vary in only a few groups or in a small share of rows. A typical case is a school-level covariate with merge or entry errors, where a by-school slope would be 'identified' only by the few discordant rows. Exclude between-g terms from the maximal by-g structure. When a user requests a slope on a between-g term, warn with the variance-function explanation. Decide 'constant within group' with a relative floating-point tolerance written in the shared spec.


Parity. Exact tier, given an identical analysis sample and the same tolerance rule.


Verifier's correction. For a between-g predictor, the by-g 'slope' only parameterises between-group heteroscedasticity (s0^2 + 2 x_j s01 + x_j^2 s1^2). Whether it is formally identified depends on the coding and on the number of distinct x_j values:
- binary x, uncorrelated slope: identified under 0/1 coding, unidentified under +/-0.5 coding;
- binary x, correlated slope: unidentified under either coding;
- 3 or more distinct x_j values: identified.
Always warn, and never present the estimate as a slope variance.


Verifier's reasoning. The variance-function explanation is correct, as is the point that a 'between' slope is not always unidentified. But the specific claim 'binary x with an uncorrelated slope: identified' depends on the coding. With 0/1 coding, the two group types have variances s0^2 and s0^2+s1^2, so it is identified. With +/-0.5 (sum) coding, both group types have variance s0^2 + 0.25 s1^2, so it is not identified (rank 2/3, null direction 0.25*s0^2 - s1^2). Sum coding is the default many psycholinguists use. With +/-0.5 coding and a correlated slope, the rank is 3/4, but the null direction lies in (s0^2, s1^2) and s01 is identified, unlike the 0/1 case. The continuous or >=3-valued case needs at least 3 distinct x_j values across groups. Identification here comes only from the assumed quadratic-in-x_j between-group variance function, so a design auditor should treat it as 'formally identified, substantively uninterpretable'.


Evidence checked. Experiment scratchpad/L1adv/scripts/adv1.py (30 subjects x 5 obs):
- 0/1 diag: rank 3/3;
- +/-0.5 diag: rank 2/3, null {s00: 0.25, s11: -1};
- +/-0.5 us: rank 3/4, null {s00: -0.25, s11: 1}.
The reviewer's ident.py case (f) reproduced for 0/1 coding.


### L1-04 Deterministic algorithm for the design-implied maximal random-effects structure

Kind: feature. Stream: B. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. For each grouping factor g, the design-justified maximal structure (Barr et al. 2013) is the intercept plus every fixed-effect term that is within-g, interactions included. Take a cross-level interaction x:z where z is between-g. Within group j, its column z_j*x is collinear with x, so x:z adds no within-group direction and cannot have a by-g slope. Its lower-level component x does need one. Heisig and Schaeffer (2019) show by simulation that omitting this slope usually gives seriously overconfident inference for the cross-level interaction. Measuring rank increments per term (all columns of the term together) rather than per column makes the selected set invariant to contrast coding when marginality is respected.


Handling. Apply this algorithm:
1. Order terms by degree (intercept, main effects, 2-way and so on).
2. For each g and each group j, track rank(X_j) restricted to the accepted terms.
3. Accept term t for g if its columns raise rank(X_j) by t's full df in at least m_g groups (m_g is a threshold in the spec, tied to L1-07). Flag terms that are only partially accepted.
With nested factors, evaluate each level separately. For example, a predictor that is between-class but within-school gets a by-school slope only. Evaluate crossed factors separately (by-subject and by-item). Output the maximal formula in lme4 syntax with per-term counts of informative groups, and mark terms the user's formula omits. Omitted slopes for components of cross-level interactions get a specific warning. Label the result a ceiling, not a recommendation.


Parity. Exact tier. The Python formula parser (P30) must build the same term and column sets.


Verifier's correction. The design-justified ceiling for factor g is the intercept plus every term (taken with its lower-order terms in marginal order) whose columns add within-group rank in enough groups. Present it with per-term informative-group counts. Distinguish the effects being tested from nuisance within-unit covariates. Refuse to build it from non-marginal formulas, or warn that the result is coding-dependent.


Verifier's reasoning. The core logic is right. A cross-level interaction x:z with z between-g is collinear with x inside every group, so it adds no within-g direction. Heisig and Schaeffer (2019, ESR 35(2), 258-279) argue the lower-level slope should always be included, and their abstract describes omitting it as giving severely anti-conservative inference. The claim has these overstatements and gaps:
(1) Contrast-coding invariance of per-term rank increments holds only for formulas that respect marginality and when terms are tested in hierarchical order. In a non-marginal formula (e.g. x:z without x), the algorithm would accept x:z as a by-g slope.
(2) 'Every within-g term' includes nuisance within-unit covariates (trial number, centred controls). Barr et al. frame the maximal structure around the design factors relevant to the confirmatory test. A blind 'all within terms' ceiling can make q very large and should separate test-relevant from nuisance terms.
(3) The m_g threshold makes the ceiling depend on an arbitrary cut-off. The output should show per-term counts rather than silently excluding terms.
(4) The peeref URL for Barr et al. was not checkable here.


Evidence checked. Heisig & Schaeffer bibliographic data and abstract wording ('severely anti-conservative') via WebSearch snippets of the SSOAR record https://www.ssoar.info/ssoar/handle/document/64962 (the host itself was unreachable from this sandbox). Rank argument checked algebraically. No direct check of the Barr URL (host not reachable).


### L1-05 Confounding of random effects with the residual depends on coding, replication and family

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P3). Verdict: partly_correct.


Claim. P3 holds for correlated structures. With one observation per unit x level cell, (1+f|subj) has k(k+1)/2 + 1 parameters, but the per-unit k x k covariance has only k(k+1)/2 distinct entries. Numerically, a 2-level factor gives rank 3 of 4 and a 3-level factor with Helmert coding gives rank 6 of 7.

For zero-correlation structures, the answer depends on the coding. With +/-0.5 sum coding (k=2) or orthogonal Helmert contrasts (k=3), the identity matrix lies in the span of the slope bases, so the structure is unidentified. With treatment dummies, the diagonal structure is formally identified (rank 3/3 for k=2, 4/4 for k=3), but only through the arbitrary restriction that the reference-level effect and the dummy effects are uncorrelated.

The same mechanism appears in:
- (1|s)+(1|i)+(1|s:i) with one observation per subject-item pair: rank 3 of 4, null vector s2_si - s2;
- (1+time|id) with 2 waves: rank 3 of 4;
- quadratic growth with 3 waves: rank 6 of 7.
The growth models are identified with 3 and 4 waves respectively.

Replicating only a few cells restores formal identification, but only weakly. With 3 of 30 subjects replicated, the Gram condition number was 92, against 29 under full duplication.

For GLMMs without a free dispersion parameter (Poisson, binomial with more than one trial), an observation-level random effect is identified and is a standard overdispersion device. For Bernoulli responses, it is not identified.

By default, lmer stops at fit time when a term's number of random effects is >= n (check.nobs.vs.nRE = 'stop') or when nlev >= n (check.nobs.vs.nlev = 'stop'). The exact cases therefore error in R, but the weakly identified near-cases pass.


Handling. Run L1-06 on Z as coded, for the declared family. Report the number of unit x cell (and subject x item) combinations with 2 or more observations as 'effective replication'. When identification appears or disappears under recoding, say so explicitly. Emit the structural error before any engine is called, so that R and Python users get the same finding.


Parity. Engine behaviour differs (R errors, while other engines may fit silently). The pre-fit structural finding must be identical in both languages (exact tier).


Verifier's correction. The structural findings stand, but engine behaviour differs:
- lmer stops (check.nobs.vs.nRE or check.nobs.vs.nlev) for single-term exact cases: (1+f|s), (1|s:i) with one observation per pair and (1+time|id) with 2 waves.
- lmer fits silently when the unidentified structure is split across terms, e.g. (1+c||s) with +/-0.5 coding, and in near-cases.
- glmmTMB applies no nobs-vs-nRE check.
For Bernoulli responses, the OLRE is exactly unidentified under probit and only practically unidentified under logit.


Verifier's reasoning. The identification results reproduce exactly: (a) 3/4, (b) 6/7, Helmert-diag 3/4, treatment-diag 4/4, s:i 3/4, 2-wave growth 3/4, 3-wave quadratic 6/7 and condition number 92 vs 29. But the final claim 'the exact cases therefore error in R' is false for the most common zero-correlation case. lme4's default '||' handling splits (1+c||s) into (1|s)+(0+c|s). checkZdims compares each term's number of random effects with n separately. Each split term has J random effects and J < n = 2J, so lmer fits silently even though the sum-coded zero-correlation model is unidentified (I computed rank 2/3). By contrast, diag(1+c|s) (lme4 >= 2.0-1) or glmmTMB's || form one term with 2J = n random effects. lmer would stop on it, and glmmTMB has no such check. The OLRE statement is broadly right. For Bernoulli responses, it is exactly unidentified under a probit link (it rescales the linear predictor) and only practically unidentified under logit.


Evidence checked. Re-ran scratchpad/L1/scripts/ident.py: all stated ranks and the cond numbers 92.2 and 29.2 reproduced. Split-term case: scratchpad/L1adv/scripts/adv1.py gives (1|s)+(0+c|s) rank 2/3, with nRE = 30 per term and n = 60. The checkZdims loop is per term (cols[i] vs rows[i]): https://raw.githubusercontent.com/lme4/lme4/master/R/modular.R. The split default (getDoublevertDefault 'split'): https://raw.githubusercontent.com/lme4/lme4/master/R/utilities.R


### L1-06 General pre-fit identifiability test: linear independence of REML-projected covariance bases (not the rank of Z)

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. In a Gaussian LMM, V(theta) = s2*I + sum_k theta_k Z A_k Z' is linear in the elements of the G blocks. Under REML, the covariance parameters are therefore identified if and only if the projected matrices P Z A_k Z' P and P are linearly independent, where P = I - X(X'X)^- X'. Equivalently, the Gram matrix M_kl = tr(P V_k P V_l) must be nonsingular. M is twice the REML expected information at G = 0, s2 = 1.

M can be computed from W = Z'PZ without forming n x n matrices: M_kl = tr(A_k W A_l W), M_k,s = tr(A_k W), M_ss = n - rank(X). This matched the direct computation to 2e-13. The null vector names the confounded combination of parameters.

rank(Z) is the wrong criterion: the nested (1|school)+(1|class) has rank(Z) = 30 of 40 columns and is still identified (rank 3 of 3).

The projection matters. (1|g) with g also entered as a fixed effect is unidentified after projection (rank 1 of 2). Without projection (ML), the Gram matrix is nonsingular, even though the ML estimate of tau2 is then always 0. The test should therefore always use the projected form.


Handling. Run the test on the analysis sample for the user's formula and for every rung of the reduction ladder (L1-17). Report rank deficiency as an error, with the null combination written in parameter names. Report the scaled smallest eigenvalue or condition number as a design-only weak-identification index, labelled as heuristic. For GLMMs, drop the s2 basis (or use the family's dispersion parameter) and present the test as a necessary condition on the latent scale. For large q, exploit block and sparse structure, and warn about cost above a size limit. The SVD-based numerical-rank tolerance rule is written in the shared spec.


Parity. Numerical-tolerance tier (deterministic linear algebra), with the same rank-tolerance rule in R and Python.


Verifier's correction. For Gaussian LMMs with linearly parameterised G, REML identifiability holds iff {P Z A_k Z' P, P} are linearly independent. Compute this via W. For structured covariances, use the Jacobian rank at plausible theta. For GLMMs, run the test on the unprojected latent-scale bases, without an s2 basis, as a necessary condition only. For weak identification, report a scale-free index (the Gram matrix of normalised bases or the expected relative SEs from L1-18), not the raw condition number.


Verifier's reasoning. For Gaussian LMMs with covariance parameters entering V linearly (unstructured or diagonal G), the criterion is correct. REML depends on y only through K'y, whose covariance K'VK is linear in theta. M = 2 x REML information at V = I is right, and the W = Z'PZ identities hold (re-run: max difference 2.3e-13). The rank(Z) counterexample and the projection example reproduce. The claim has three problems:
(1) The GLMM extension uses the wrong bases. With the REML projection, the test is not a necessary condition for GLMMs, because mean and variance do not separate there. For example, in Poisson or binomial models, (1|g) with g also a fixed effect is identified from within-group dependence (Cov(y_i1, y_i2) = mu^2(exp(tau2)-1) given fixed alpha_j), yet the projected test flags it as unidentified. For GLMMs, use the unprojected latent-scale bases. Linear dependence there implies identical marginal distributions and hence non-identification, so the test is a valid necessary condition.
(2) The condition number of M is not scale-invariant, so it is a poor weak-identification index. The identified 4-wave quadratic growth model has cond 2.7e5 (driven by the scaling of time^2), against 92 for the weakly identified 3-of-30-replicated case.
(3) 'If and only if' is limited to linear parameterisations. For structured covariances (ar1, cs, in glmmTMB and now lme4 >= 2.0-1), local identifiability requires the Jacobian of vec(PVP) with respect to theta to have full rank. Linear dependence of the bases can also be harmless at boundary points of the parameter space.


Evidence checked. Re-ran scratchpad/L1/scripts/ident.py and wcheck.py:
- (d) rank(Z) = 30/40 but identified;
- (g) REML rank 1/2, ML rank 2/2;
- 4-wave quadratic cond 2.72e5, 3/30 replicated cond 92.2.
The GLMM counterexample is analytic: Poisson-lognormal within-group covariance.


### L1-07 Levels versus random-effect dimension: J <= q guarantees a singular fit (count informative groups, not levels)

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P4). Verdict: partly_correct.


Claim. Comparing q(q+1)/2 with J is only a heuristic. The hard constraint compares J with q: from J levels, the REML estimate of an unstructured q x q G has rank at most J-1. In balanced designs where every random-effect column also has a fixed effect, this follows from the rank (at most J-1) of the between-group scatter matrix.

Multi-start REML fits (q = 3, n_j = 30, 10 replicates per cell) gave rank(G_hat) = 1 at J = 2 and at most 2 at J = 3, in both balanced and unbalanced designs. J = 4 gave rank 3 in 5/10 (balanced) and 7/10 (unbalanced) replicates.

A single-path optimiser can hide this. On 12 datasets with J = 2, statsmodels 0.15.0 MixedLM (lbfgs, then powell) reported converged = True in all 12. In 4 of them, it returned a full-rank G_hat at a REML criterion 0.5 to 2.7 units worse than the multi-start optimum.

The informative count for a term t is J_eff(t): the number of groups whose Z_tj has full column rank (subjects who saw every factor level, or groups with 2 or more distinct x values). Only those groups inform the correlations between level-specific effects.


Handling. For each term, report q_t, q_t(q_t+1)/2, J and J_eff. Flag 'singular fit guaranteed' (error) when J <= q_t. Flag 'singular fit likely' when J_eff <= q_t, because partially informative groups still contribute a little. Warn below a spec-defined multiple of q_t and label that threshold a heuristic. Tie these flags to the post-fit singularity checks (P20), so that a non-singular fit reported despite J <= q_t is itself flagged as suspect (possible non-convergence).


Parity. Structural flags: exact tier. Post-fit singular/non-singular verdicts can differ between engines in these cases, so the report must show the structural flag first.


Verifier's correction. When every random-effect column (or at least the intercept) also appears in the fixed part, as in standard models, REML/ML give rank(G_hat) <= J-1, so J <= q_t forces a singular fit. Without fixed counterparts, the bound is J, not J-1. A fit reported as non-singular despite this is suspect. In statsmodels 0.15.0, 7 of 12 fits with J = 2 and q = 3 returned G_hat of higher rank than the multi-start optimum while reporting converged = True.


Verifier's reasoning. The statsmodels result reproduces. In a re-run of p4_cmp.py, all 12 runs reported converged = True, and 4 returned a rank-3 G_hat with REML criterion gaps of 1.59, 0.52, 2.72 and 1.40, matching '0.5 to 2.7'. The reviewer understates the problem, though: 3 more runs returned rank 2 (gaps 0.35, 0.004, 0.16), so 7 of 12 did not reach the rank-1 optimum. The 'hard constraint' rank(G_hat) <= J-1 is stated without its condition. The argument (REML/ML score equations, with sum_j Z_j'P_V y = 0) needs the random-effect columns to have fixed-effect counterparts. In my ML test with no fixed effects, J = q = 2 gave a full-rank G_hat in 8 of 10 datasets. With only a fixed intercept and no fixed slope, J = 2 still gave rank 1 in 10 of 10. The guarantee therefore holds for the usual models in which random terms are mirrored by fixed effects (at least the intercept), not unconditionally. The J_eff idea and the link to post-fit singularity checks are sound.


Evidence checked. Re-ran scratchpad/L1/scripts/p4_cmp.py (statsmodels 0.15.0): ranks (3,3,2,3,1,3,1,1,2,2,1,1), all converged = True. New tests:
- scratchpad/L1adv/scripts/adv2.py (own REML, 25 starts, J = 2, q = 2): rank 1 in 10/10 with and without a fixed slope;
- scratchpad/L1adv/scripts/adv3.py (ML, no fixed effects, J = q = 2): full rank in 8/10.


### L1-08 Replace the 'fewer than 5-6 levels' rule with design-based precision and boundary probabilities

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P5). Verdict: partly_correct.


Claim. Maas and Hox (2005) report in their abstract that only level-2 samples of 50 or fewer gave biased level-2 standard errors. Regression coefficients, variance components and their SEs were otherwise unbiased and accurate. In their conditions, few levels therefore mean imprecision and SE bias, not biased point estimates. A fixed cut-off also ignores n_j and the ICC.

In balanced one-way REML, tau2_hat = max(0, (MSB - MSW)/n) and P(tau2_hat = 0) = F_{J-1, J(n-1)}(1/(1 + n*tau2/s2)). For ML, the argument is multiplied by J/(J-1). A 40,000-replicate simulation agreed: at J=6, n=10, ICC=0.05, the exact REML value is 0.341 against 0.342 simulated, and the ML value is 0.436 against 0.437.

The relative SE of the untruncated estimator is approximately sqrt(2/(J-1)) * (1 + (1-rho)/(n*rho)). At J=5, n=20, rho=0.2, this predicts 0.85, and simulation gave 0.86. With 5 levels, the variance estimate therefore has a relative SE of about 85% even with large clusters.

The defaults differ: glmmTMB uses REML = FALSE and lmer uses REML. Under ML, boundary estimates are more frequent when J is small.


Handling. For each variance component, report J, n0 and the estimation method. For a grid of plausible ICCs (user-supplied, or a documented default grid), report the approximate relative SE and the boundary probability. Use the exact formulas for balanced intercept-only terms and L1-18 otherwise. Set warning thresholds in the spec on expected relative SE, not on raw J. Cite McNeish and Stapleton (2016) for the remedies when J is small: REML plus small-sample df corrections.


Parity. Closed-form quantities: exact or tolerance tier. State the REML/ML default difference in the report.


Verifier's correction. Report the exact boundary probability and the relative SE of the untruncated estimator, labelled as such. Cite Maas & Hox only for J >= 30-50 (biased level-2 SEs at J <= 50). For J < 30, do not claim unbiased variance components, because REML truncation biases them upward and ML biases them downward.


Verifier's reasoning. The formulas and numbers are right. My recomputation gives REML P(boundary) = 0.3412 and ML 0.4358 at J=6, n=10, ICC=.05. The relative-SE approximation gives 0.8485 against 0.8490 from the exact ANOVA variance. The Maas & Hox abstract wording is confirmed: 'a sample of 50 or less leads to biased estimates of the second-level standard errors', with the other estimates unbiased and accurate. glmmTMB's REML=FALSE default is confirmed in source. The claim has two overstatements and one unchecked source:
(1) Maas & Hox's conditions do not go down to 5-6 groups (to my knowledge the smallest was 30, but I could not confirm the grid from the full text). Their 'unbiased variance components' result therefore says nothing about J = 5. At small J, the REML estimator max(0, .) is biased upward by truncation and the ML estimator is biased downward, so 'not biased point estimates' must not be extended to the few-cluster case.
(2) The relative-SE formula describes the untruncated ANOVA estimator. When the boundary probability is 30-40%, it misdescribes the actual estimator.
(3) I could not check the McNeish & Stapleton remedy claim (REML plus small-sample df). It is listed without a checked source.


Evidence checked. scratchpad/L1adv/scripts/adv1.py (scipy F cdf and exact Var of the ANOVA estimator). Maas & Hox abstract via WebSearch snippets (https://www.citedrive.com/en/discovery/sufficient-sample-sizes-for-multilevel-modeling/). The Utrecht hosts were unreachable from the sandbox. glmmTMB REML=FALSE at lines 239/1376 of https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/R/glmmTMB.R


### L1-09 Singletons are not errors, and every structural audit runs on the analysis sample with a diff against the raw data

Kind: edge_case. Stream: B. Priority: essential. Origin: preliminary (P6). Verdict: correct.


Claim. Singleton groups are not an error. In a Gaussian random-intercept model, they contribute to the fixed effects (between-group effects especially) and to the total variance. Only groups with n_j >= 2 separate tau2 from s2. The model is unidentified only when (almost) all groups are singletons (J = N, L1-02). Dropping singletons changes the sample and the estimand.

After NA handling, lme4 silently drops unused and NA levels of grouping factors (mkBlist: factor(ff, exclude = NA)). Groups lost to listwise deletion therefore disappear without a message, and a factor can become partially within or between after deletion.


Handling. Define the analysis sample as rows complete on every formula variable, including grouping factors, weights and offsets, and compute every L1 check on it. For each grouping factor, report a raw-versus-analysis diff:
- levels lost;
- levels that became singletons;
- terms whose status changed (within to between, full to partial);
- changes in J_eff and d_g (L1-10).
Report the share of groups and of N that are singletons. Never drop singletons by default.


Parity. Exact tier. Requires identical NA semantics (L1-20) and an identical row set before any check.


Verifier's reasoning. The source confirms the mechanism: mkBlist does `if (drop.unused.levels) ff <- factor(ff, exclude=NA)`, and the model frame is built with drop.unused.levels = TRUE. Levels lost to NA removal therefore vanish, and na.omit gives no message. It is standard that singletons contribute to the fixed effects and the total variance and that only groups with n_j >= 2 separate tau2 from s2. There is one minor wording issue: formal identification of tau2 needs only one group with n_j >= 2, so '(almost) all singletons' describes weak, not absent, identification. For random-slope terms, groups with n_j < q_t inform only partially, which ties to J_eff.


Evidence checked. https://raw.githubusercontent.com/lme4/lme4/master/R/utilities.R (mkBlist at lines 97-118, drop.unused.levels <- TRUE at line 338). checkNlevels also counts levels via factor(x, exclude=NA): https://raw.githubusercontent.com/lme4/lme4/master/R/modular.R


### L1-10 Level-2 degrees-of-freedom budget: d_g = rank([X, Z_g]) - rank(X)

Kind: edge_case. Stream: B. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. The number of independent between-group contrasts left for the g-level variance after the fixed effects is d_g = rank([X, Z_g]) - rank(X), where Z_g is the indicator matrix of g. When all g-level fixed-effect columns are between-g, d_g equals J minus the number of those columns (intercept included). d_g = 0 makes the g intercept variance unidentified under REML. For example, g entered as both fixed and random gives rank 1 of 2. The same happens with a school-level factor whose levels map one-to-one onto schools, or with J-1 school-level covariates. Small budgets are common in education data: 15 schools with 10 school-level covariates leave d_g = 4. In balanced designs, the exact denominator df for between-g fixed effects equals d_g.


Handling. Report d_g for every grouping factor and the analogous rank increment for every random-slope term. Raise an error at 0 and a warning below a spec threshold. List the between-g fixed-effect terms that consume the budget. Show d_g next to J and J_eff in the Stream B specification output.


Parity. Exact tier (rank with the shared tolerance rule).


Verifier's correction. Use d_g = J - dim(span(X) ∩ span(Z_g)), computed by rank, never by counting between-g columns. Report which column combinations lie in span(Z_g). The df equivalence holds only for balanced random-intercept strata.


Verifier's reasoning. d_g = rank([X, Z_g]) - rank(X) = J - dim(span X ∩ span Z_g) is the right quantity, and d_g = 0 does make the g variance REML-unidentified (P Z_g = 0). But the shortcut 'J minus the number of between-g columns' fails whenever within-g columns combine into a between-g direction. For example, X may contain both raw x and the cluster-centred x, whose difference is the cluster mean. With J = 8 and no between column, d_g = 6, not 7. This design is common after a Mundlak/within-between decomposition (L1-11). The df statement holds only for balanced designs where the between-g effect is tested in the g-intercept stratum.


Evidence checked. scratchpad/L1adv/scripts/adv1.py: X = [1, x, x - xbar_j], J = 8, gives d_g = 6. ident.py case (g) re-run: rank 1/2.


### L1-11 Within/between decomposition: report predictor ICC and the reliability of cluster means, and compute means on the analysis sample

Kind: feature. Stream: B. Priority: valuable. Origin: preliminary (P7). Verdict: partly_correct.


Claim. For a continuous x and grouping factor g, ICC_x (the share of x variance lying between groups) sets how strongly an uncentred slope mixes within and between effects. Group-mean centring plus the cluster mean as a level-2 predictor separates the two. The contextual effect is the between effect minus the within effect (Enders & Tofighi 2007). The observed cluster mean measures the latent group mean with error. Its reliability is lambda_j = n_j*ICC_x / (1 + (n_j - 1)*ICC_x). With small clusters or a low ICC_x, the manifest between or contextual effect is biased, and this bias motivates the latent covariate approach (Lüdtke et al. 2008). Cluster means must be computed on the analysis sample, because otherwise listwise deletion makes them inconsistent. With crossed factors, there is no unique decomposition.


Handling. For each (x, g) pair, report ICC_x (ANOVA estimator, deterministic) and the distribution of lambda_j, and flag low reliability. When ICC_x is high, warn that a by-g slope for x rests on little within-group variance. Suggest the decomposition but do not apply it automatically. Record centring choices in the specification so that both languages build identical columns.


Parity. Exact tier, provided both languages compute group means after NA removal.


Verifier's correction. Report ICC_x, lambda_j and the within share. Make the source of the cluster mean (the analysis sample, all available rows or an external value) an explicit spec option that is recorded and identical across languages. Describe the uncentred slope as a weighted mix whose weights depend on ICC_x, n_j and the outcome ICC.


Verifier's reasoning. The reliability formula (Spearman-Brown / ICC(2) form) and the motivation for the latent covariate model are standard. Lüdtke et al. (2008) show that the manifest group-mean approach biases the contextual effect. I confirmed this via secondary sources but did not read the full text. The claim has three overstatements:
(1) 'Cluster means must be computed on the analysis sample' is not a methodological requirement. Using all available x values for the cluster, or a known population cluster mean, is defensible and gives more reliable means. It is a choice to be declared and applied identically in both languages.
(2) ICC_x alone does not 'set' how much an uncentred slope mixes within and between effects. In a random-intercept model, the uncentred estimator is a precision-weighted combination whose weights also depend on n_j and the outcome's variance ratio.
(3) For crossed factors, an exact decomposition exists for balanced fully crossed data (double centring). Only the unbalanced case has no unique one.


Evidence checked. WebSearch snippets: Lüdtke et al. 2008, Psychological Methods 13, 203-229 (https://acuresearchbank.acu.edu.au/item/87423/the-multilevel-latent-covariate-model-a-new-more-reliable-approach-to-group-level-effects-in-contextual-studies), and Asparouhov & Muthén slides on bias of observed centring (https://modeling.uconn.edu/wp-content/uploads/sites/1188/2018/06/Asparouhov_CentMedSlides-2.pdf). Group-mean reliability formula documented in multilevel::gmeanrel (https://rdrr.io/cran/multilevel/man/gmeanrel.html). The uio.no PDF was unreachable.


### L1-12 Rank-deficient X: report empty cells and fix the column-dropping rule, because greedy pivoted QR drops different columns from lme4

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P8). Verdict: partly_correct.


Claim. lme4's chkRank.drop.cols uses qr(X, tol = 1e-7, LAPACK = FALSE), i.e. LINPACK dqrdc2. Its limited pivoting only moves columns with near-zero norm to the right, and lme4 keeps the first rank(X) pivot columns. The column dropped is therefore the later member of a dependent set in model-matrix order. glmmTMBControl's rank_check is c('adjust','warning','stop','skip'), so 'adjust' (drop columns) is the default in current source.

P8's 'pivoted QR' is a parity risk. A greedy column-pivoted QR (LAPACK, or scipy.linalg.qr(pivoting=True)) can drop a different column. For example, take ~A + B with B nested in A (4 levels, 2 per A level, treatment coding). A left-to-right emulation of dqrdc2 keeps (Intercept, A2, B2, B3), whereas scipy's pivoted QR keeps (Intercept, A2, B2, B4). The meaning of the remaining coefficients changes with the coding and the column order.


Handling. Before fitting, report each dependent column set, the column each engine will drop and the empty cells of the factor cross-table for each interaction. The Python implementation must use a sequential rule equivalent to dqrdc2 with the same relative tolerance, as written in the spec, and never a greedy pivoted QR. When cells are empty, recommend a cell-means or collapsed-factor formulation, and warn that the 'main effects' then refer to a subset that depends on the design. lme4 never drops columns of Z, so rank deficiency in Z is left to L1-06 and L1-07.


Parity. Without a specified dropping algorithm, coefficient sets differ between R and Python. With it, exact tier on names and tolerance tier on values. Golden fixtures must include rank-deficient designs with nested and empty-cell patterns.


Verifier's correction. lme4 and dense-X glmmTMB drop the later member of each exact dependency in model-matrix order (dqrdc2, tol 1e-7). Sparse-X glmmTMB uses a different rule. A greedy pivoted QR in Python can choose differently depending on cell sizes, so implement the sequential dqrdc2-equivalent rule. Golden fixtures should include unbalanced nested and empty-cell designs, plus glmmTMB sparseX cases.


Verifier's reasoning. The lme4 behaviour is verified: chkRank.drop.cols calls qr(X, tol=1e-7, LAPACK=FALSE) and keeps pivot[1:rank]. R's qr.Rd documents dqrdc2's limited pivoting. glmmTMBControl has rank_check = c('adjust','warning','stop','skip'), so the default is 'adjust', although its own roxygen text still says 'default value is warning'. There are two problems:
(1) The divergence example is data-dependent, not structural. With balanced cells (4 per B level), scipy's pivoted QR keeps (Int, A2, B2, B3), the same as dqrdc2. The B4 result needs unequal cell sizes (the script used 5, 7, 9, 3), because greedy pivoting chooses by residual column norm. The stated example '4 levels, 2 per A level' omits this condition.
(2) glmmTMB is not simply 'like lme4'. .adjustX uses Matrix::qr. For dense X, this gives the base LINPACK pivot, but with sparseX it uses sparseQR and keeps columns by thresholding diag(R), whose order follows the fill-reducing column permutation. Dropped columns can therefore differ from lme4. Its rank tolerance (qr2rankMatrix) also differs from lme4's 1e-7.


Evidence checked. https://raw.githubusercontent.com/lme4/lme4/master/R/modular.R (lines 233-290), https://raw.githubusercontent.com/wch/r-source/trunk/src/library/base/man/qr.Rd (dqrdc2 section) and https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/R/glmmTMB.R (lines 1638, 1691, 1790-1830). Re-ran scratchpad/L1/scripts/p8.py: greedy keeps B4 with cell sizes 5/7/9/3. scratchpad/L1adv/scripts/adv1.py: balanced cells, scipy keeps B3 (same as dqrdc2).


### L1-13 '||' with a factor gives a redundant, unidentified parameterisation, and zero-correlation structures depend on coding and centring

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P18). Verdict: partly_correct.


Claim. In lme4 (formula machinery now in reformulas, default 'split' method), (f || g) expands to (1|g) + (0 + f|g). Here 0 + f produces one indicator per level with an unstructured k x k covariance, which already spans 11'. The separate intercept variance is therefore redundant. P18 understates this: it notes only that correlations remain, but the parameters are unidentified. Numerically (3 levels, 3 observations per cell), the Gram rank is 7 of 8, with a null vector of the form 'subtract c from s2_int and add c to every element of Sigma_f'. Singular or arbitrary fits follow.

Numeric contrast columns or glmmTMB's diag() give an identified diagonal structure (rank 4 of 4). reformulas also offers a 'diag_special' method that turns || into diag().

Any zero-correlation structure depends on the contrast coding (see L1-05) and on centring. Shifting x by c changes cov(b0, b1) by c*s1^2, so 'no correlation' holds only for one particular origin.


Handling. For every || or diag() term, detect factor-valued components and report the redundancy as a structural error, with the fix (numeric contrast columns). Record in the results the coding and centring under which correlations were removed. Any 'remove correlations' rung of the reduction ladder (L1-17) must fix numeric coding and centring first.


Parity. The Python parser (P30) must implement one documented expansion semantics for || (lme4 'split' or diag) and state which one. Otherwise, the same formula means different models in the two languages.


Verifier's correction. (f||g) is unidentified under lme4's default split expansion. Under glmmTMB (and under lme4 with lme4.doublevert.default = 'diag_special'), it becomes diag(f|g) on treatment-coded columns, which is identified but depends on the coding. The suite should reject a bare || on factors and require an explicit diag() with declared coding and centring. It should also record the expansion used by each engine.


Verifier's reasoning. The redundancy result reproduces: rank 7/8, with a null vector of -1 on the intercept and +1 on every Sigma_f element. The centring algebra is right. Two points are missing or imprecise:
(1) The most important parity fact is missing: within the R suite itself, glmmTMB has translated || into diag() since version 1.1.2.3, while lme4 splits it. The same formula (f||g) therefore means different models in lme4 and glmmTMB. The split form is unidentified, whereas diag on treatment coding is identified but coding-dependent.
(2) 'reformulas default split' is imprecise. reformulas::findbars_x defaults to 'diag_special', and 'split' is lme4's default via getOption('lme4.doublevert.default', 'split'). lme4 >= 2.0-1 also supports diag(), cs() and ar1() terms, and its NEWS recommends diag() over || because 'defaults may change in the future'.


Evidence checked. lme4 NEWS 2.0-1 (2026-03-05): https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd. glmmTMB NEWS 1.1.2.3: https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/inst/NEWS.Rd. reformulas findbars_x signature: https://raw.githubusercontent.com/bbolker/reformulas/main/R/utils.R. lme4 getDoublevertDefault: https://raw.githubusercontent.com/lme4/lme4/master/R/utilities.R. ident.py case (c) re-run.


### L1-14 Crossed participant x stimulus designs: incidence, connectivity, design type and effects that are between on both factors

Kind: edge_case. Stream: B. Priority: essential. Origin: new. Verdict: correct.


Claim. In subject x item designs, the subject-item incidence matrix determines what can be identified. Take a fixed effect that is between subjects and between items, for example participant groups that each saw their own stimulus set. Its SE depends on both the subject and the item variance, and its precision is limited by the number of items per level. If the bipartite incidence graph splits into components that coincide with that predictor's levels, the effect is estimable only from contrasts between components. It is then inseparable from the stimulus-set difference except through the item random-effect assumption.

Westfall, Kenny and Judd (2014) analyse five common participant x stimulus designs. They show that power approaches a maximum set by the stimulus sample as the number of participants grows. Judd, Westfall and Kenny (2012) show that ignoring stimulus variance biases inference.


Handling. For each pair of crossed factors, report:
- the incidence fill rate;
- the connected components of the bipartite graph (union-find);
- the within/between status of each fixed term on each factor;
- a design label (fully crossed, counterbalanced/Latin square, stimuli nested in condition, participants nested in condition, both nested).
Flag predictors that are constant within every component. Flag between-item predictors with few items per level, reporting items per level as the limiting sample size. Add by-item slopes for within-item predictors to the maximal structure (L1-04).


Parity. Exact tier.


Verifier's reasoning. The WKJ 2014 abstract confirms the main points. It examines five common designs and reports that power 'typically does not approach unity as the number of participants goes to infinity but instead approaches a maximum attainable power value', set by the stimulus sample. The estimability argument is sound linear algebra: an effect constant within every connected component of the incidence graph is identified only through between-component contrasts. I did not check Judd, Westfall & Kenny (2012) directly, but the claim attributed to it is the widely cited one. Union-find components and per-factor within/between status are deterministic and outcome-free.


Evidence checked. WKJ 2014 abstract wording via WebSearch snippets (JEP:General 143(5), 2020-2045, from https://experts.colorado.edu/display/pubid_92365 and https://forrt.org/curated_resources/statistical-power-and-optimal-design-in/). The colorado host was unreachable from the sandbox.


### L1-15 Duplicates: check declared keys, not whole rows

Kind: correction. Stream: B. Priority: valuable. Origin: preliminary (P15). Verdict: correct.


Claim. Exact duplicate rows indicate an error only when the data contain a column that should make rows unique (trial number, timestamp, row key) or continuous measurements. Trial-level designs without a trial index produce many identical rows legitimately. In a simulated dataset of 40 subjects x 2 conditions x 20 trials with binary accuracy and no item or trial column, 1,442 of 1,600 rows were exact duplicates. With an item column, there were none. Duplicate (unit, time) keys in longitudinal data make time-indexed residual correlation structures and lag variables ill-defined.


Handling. Ask for a declared key. A key inferred from column names may be offered only as a suggestion. Report duplicate keys as errors, and exact duplicates without a declared key as information, with the caveat above. Report duplicate (unit, time) pairs per unit. Never deduplicate automatically.


Parity. Exact tier. Floating-point columns need a defined equality rule.


Verifier's reasoning. I reproduced the simulation. With 40 x 2 x 20 binary rows and no trial column, pandas duplicated() flags 1,442 rows. At most 160 distinct rows can exist (2 outcome values per subject-condition cell), so ~1,440 duplicates are structural. Key-based checking and never deduplicating automatically are the right policy. Duplicate (unit, time) keys do break time-indexed residual structures (ar1 etc.).


Evidence checked. Inline pandas 3.1.0 run (the venv has 3.1.0) in scratchpad/L1/venv: d.duplicated().sum() = 1442.


### L1-16 Outcome-blind mode: what it can certify and what it cannot

Kind: architecture. Stream: B. Priority: essential. Origin: preliminary (P17). Verdict: partly_correct.


Claim. Everything derived from X, Z and the grouping structure can be computed without y: L1-01 to L1-14, except their outcome-dependent parts. Three things cannot:
- The analysis sample depends on missing outcomes, because listwise deletion includes y.
- Which checks apply depends on the family. For example, confounding with the residual (L1-05) arises only when the dispersion is free.
- Data-driven reduction (rePCA, LRT- or AIC-based backward selection as in Bates et al. 2015 and Matuschek et al. 2017) needs y.
A blind audit is therefore an upper bound on the information the analysis will have and cannot itself choose the final structure.


Handling. Blind mode requires a declared family and formula. It computes the audits on a 'design sample' (rows complete on predictors and IDs) and states that the results assume no missing outcomes. It refuses outcome-dependent checks and emits a hashed audit JSON for preregistration. At analysis time, Stream A re-runs the audit on the real analysis sample, reports a structured diff (groups lost, J_eff, d_g, identifiability changes) and says whether the preregistered ladder (L1-17) still applies.


Parity. Exact tier for the audit, and the audit hash must be language-independent (canonical JSON serialisation).


Verifier's correction. Blind mode can certify design-only properties of the design sample, and these upper-bound what the analysis sample will support. Which identification checks apply depends on the declared family: residual confounding for free-dispersion families and Bernoulli-specific non-identification of observation-level terms. Separation, outcome-type adequacy and outcome missingness cannot be certified.


Verifier's reasoning. The 'upper bound' claim holds. Removing rows (missing y) cannot raise J, d_g or J_eff. Nor can it turn linearly dependent projected bases into independent ones, because a dependency Σ c_k V_k ∈ {XA + A'X'} restricts to any row subset. One justification is wrong, though: 'confounding with the residual arises only when the dispersion is free' contradicts L1-05's own Bernoulli case, where a J = N term is unidentified without any dispersion parameter. Blind mode also cannot assess outcome-type mismatch (P13), separation (P14) or whether missingness in y is informative. The declared family is itself an outcome-based decision and must be stated as an assumption. The Bates et al. (2015) and Matuschek et al. (2017) references are correctly identified (arXiv 1506.04967 and JML 94, 305-315 respectively).


Evidence checked. Monotonicity argued algebraically. References checked via WebSearch: arXiv 1506.04967 listing (https://arxiv.org/abs/1506.04967) and the r-sig-ME post title 'New paper by Bates et al: Parsimonious mixed models' at https://stat.ethz.ch/pipermail/r-sig-mixed-models/2015q2/023689.html. The Matuschek et al. listing was also checked (https://arxiv.org/abs/1511.01864v2).


### L1-17 A pre-specified, design-ordered reduction ladder instead of automatic model selection

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Barr et al. (2013) argue for the design-justified maximal structure. Matuschek et al. (2017) show that maximal models can cost power, and that selection keeping only data-supported random effects can raise power without inflating Type I error in their simulations. Bates et al. (2015) propose diagnosing overparameterisation and reducing iteratively. These are different decision rules with different operating characteristics, so the suite must not embed one silently.

A ladder is an ordered, deterministic list of nested random-effects structures, from the maximal structure (L1-04) down to intercepts only. Every rung must pass L1-06, and the ladder comes with an explicit stopping rule.


Handling. Stream B emits the ladder in lme4 syntax and as canonical JSON, ordered by design information:
- drop first the component with the lowest J_eff or expected precision (L1-18);
- remove correlations only after fixing numeric coding and centring (L1-13);
- keep slopes for lower-level components of cross-level interactions as long as possible.
The user picks the stopping rule (back off on non-convergence or singularity, or an LRT or AIC criterion), and it is recorded. Stream A executes the ladder, logs every fit and reports the rung reached and why. The ladder is presented as a pre-specified procedure, not as the 'true' structure.


Parity. The ladder is deterministic (exact tier). The rung reached may differ between engines through convergence behaviour, so the report must show the per-rung outcome for each engine.


Verifier's correction. Order rungs by (a) role (nuisance before test-relevant), (b) correlations before variances once coding and centring are fixed, and (c) design information (J_eff). Label every stopping rule, convergence-based ones included, as data-dependent, and keep its operating characteristics separate from those of the maximal model.


Verifier's reasoning. The architecture is sound: an explicit, pre-registered ladder with a recorded stopping rule. The item has two problems:
(1) The default ordering 'drop first the component with lowest J_eff' can remove the by-unit slope of the effect being tested before nuisance slopes. Barr et al. stress that omitting the slope for the tested within-unit effect inflates Type I error. The ladder should keep test-relevant slopes, together with the lower-level components of cross-level interactions, until last, and drop nuisance slopes and correlations first.
(2) 'Back off on non-convergence or singularity' is itself an outcome-dependent rule. It is legitimate if pre-specified, but the report must not present it as outcome-free.
For Matuschek et al., secondary summaries confirm the power-loss and selection argument. I could not verify the full text for 'without inflating Type I error', which holds only in their simulated conditions (with LRT alpha around .2 / AIC).


Evidence checked. WebSearch snippets of Matuschek et al. 2017 (arXiv 1511.01864 and a scinapse listing). Barr et al. content from established knowledge. I could not reach the peeref URL.


### L1-18 Outcome-blind design analysis from assumed variance components

Kind: feature. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Given the actual X and Z and user-stated plausible values of theta (ICCs or variance ratios, slope SDs, correlations), the REML expected information I_kl = 0.5 * tr(P_V V_k P_V V_l) gives the expected SE of every covariance parameter on that exact design. For balanced intercept-only terms, the exact F-based boundary probabilities of L1-08 are available. Otherwise, a parametric simulation (generate y on the real design, fit the planned model and each ladder rung) estimates the probability of singular or non-converged fits and of reaching each rung. All of these are conditional on the assumed theta. Expected information is asymptotic and unreliable for small J, where simulation is preferable.


Handling. Make this an optional feature whose output states the assumptions explicitly in a table next to the results. Results feed the ladder ordering (L1-17) and the precision warnings (L1-08).


Parity. Expected information: tolerance tier. Simulation: distributional parity only (P35).


Verifier's correction. Compute expected information for the estimation method used: REML via P_V, ML via V^{-1}. This applies to Gaussian LMMs only. Prefer simulation for small J and for GLMMs. Present SEs on a scale suited to boundary-near parameters.


Verifier's reasoning. I_kl = 0.5 tr(P_V V_k P_V V_l) is the correct REML expected information. The item has three gaps:
(1) It applies only when estimation is REML. glmmTMB defaults to ML (REML=FALSE), whose information uses V^{-1} in place of P_V. The method must match the engine and settings.
(2) Wald SEs for variance parameters near zero, or at small J, are poorly behaved. Report them on the SD or log-SD scale, or use the simulation route.
(3) For GLMMs, there is no closed form, and only simulation (or a Laplace-approximated information) applies.
The item already acknowledges asymptotics and the conditioning on theta.


Evidence checked. Formula checked against the M = 2I identity verified in L1-06 (wcheck.py re-run). glmmTMB REML=FALSE default: https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/R/glmmTMB.R


### L1-19 Group-size distribution, effective group size n0 and sentinel 'giant' levels

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Mean n_j hides skew that matters for variance estimation. The unbalanced one-way ANOVA effective size n0 = (N - sum n_j^2 / N)/(J - 1), for which E(MSB) = s2 + n0*tau2, is smaller than the mean when group sizes vary. A single level holding a large share of N often signals a sentinel code for a missing ID ('0', '999', 'unknown', ''). Such a code turns all missing IDs into one giant random-effect level. The two languages may disagree here: pandas' default read_csv converts '' to NaN, which is then dropped, whereas R keeps '' as a level in character columns (see L1-20).


Handling. Report J, N, the minimum, quartiles and maximum of n_j, n0, the share of N in the largest level, and the share in singletons. Flag levels that match a sentinel list or exceed k times the median size as probable missing-ID codes, and ask the user to confirm.


Parity. Exact tier, conditional on the NA-token policy in L1-20.


Verifier's correction. Blank-ID handling depends on the reader:
- base read.csv: level '';
- readr and fread: NA;
- pandas: NaN.
The NA-token policy must be applied after reading, on the canonicalised column (L1-20), not inferred from the language.


Verifier's reasoning. n0 = (N - Σn_j²/N)/(J-1) with E(MSB) = s2 + n0 τ² is the standard unbalanced one-way result, and n0 <= mean n_j with equality only when balanced. The sentinel-level idea is sound. The cross-language claim is overgeneralised: only base R read.table/read.csv keeps '' as a level in character columns. readr::read_csv defaults to na = c('', 'NA'), so '' becomes NA. data.table::fread reads ',,' as NA for all column types, character included. Many education and psychology users read data with readr, so whether R and Python agree depends on the reader, not the language.


Evidence checked. pandas STR_NA_VALUES includes '' (venv run). readr: https://raw.githubusercontent.com/tidyverse/readr/main/R/read_delim.R (na = c("", "NA")). fread: https://raw.githubusercontent.com/Rdatatable/data.table/master/man/fread.Rd (na.strings item). read.table: https://raw.githubusercontent.com/wch/r-source/trunk/src/library/utils/man/read.table.Rd


### L1-20 Canonical ID strings, NA tokens and explicit level order in the shared spec

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. R's factor() orders default levels with order(), which for character vectors uses shell sort with the locale's collation. Python's sorted() and pandas use code-point order (verified: 'A','B','Z','a','b','e','é'). Reference levels, column order and any step that depends on order (L1-12) can therefore differ for mixed-case or accented labels.

By default, pandas read_csv treats '', 'NA', 'N/A', 'NULL', 'None', 'nan', 'null' and others as missing. R read.table's default na.strings is 'NA', and blank fields count as missing only in logical, integer, numeric and complex columns. A blank ID in a character column therefore becomes the level '' in R and NaN in pandas.

Numeric-looking IDs ('007' vs '7', 1 vs 1.0) and whitespace or case variants ('S1' vs ' s1') create spurious or collapsed levels depending on parsing.


Handling. The shared spec defines canonical ID strings: storage type, trimming and a case policy, each an explicit option and never applied silently. Detect collisions after normalisation in both directions (two raw labels mapping to one canonical label, and the reverse). Store the explicit level order of every factor in the results JSON and use it, never the language default, for contrasts and column order. Golden fixtures declare NA tokens and column types explicitly.


Parity. Prerequisite for exact parity of every L1 audit.


Verifier's correction. Add numeric-vs-string ID storage to the canonicalisation rules. State NA-token semantics per reader (base, readr, fread, pandas) and apply one policy after reading.


Verifier's reasoning. I verified these points:
- factor() takes default levels via order(y);
- order()'s 'auto' method uses radix for numeric, integer, logical and factor, and shell (locale collation) otherwise, i.e. for character;
- pandas and sorted() use code-point order (A, B, Z, a, b, e, é reproduced);
- pandas' default NA tokens include '', 'NA', 'N/A', 'NULL', 'None', 'nan', 'null';
- read.table's na.strings default is 'NA', with blank fields counted as missing only in logical, integer, numeric and complex columns.
The claim has these overstatements and omissions:
(1) 'A blank ID in a character column becomes the level '' in R' is true only for base readers. readr and fread return NA.
(2) Storage type changes the order too. factor() on a numeric ID sorts numerically (9 before 10), while string IDs in pandas sort lexicographically ('10' before '9'), so canonical type matters as much as collation.
(3) The run used pandas 3.1.0 (in the venv), not 3.0.1.
The handling (explicit level order stored in the results JSON) is correct and necessary.


Evidence checked. https://raw.githubusercontent.com/wch/r-source/trunk/src/library/base/R/factor.R (ind <- order(y)), https://raw.githubusercontent.com/wch/r-source/trunk/src/library/base/man/order.Rd (auto/radix/shell, locale collation) and read.table.Rd. pandas 3.1.0 STR_NA_VALUES and sorting run in scratchpad/L1/venv. readr and fread sources as in L1-19.


### L1-21 Forecast each engine's fit-time behaviour from the structural audit

Kind: architecture. Stream: both. Priority: valuable. Origin: new. Verdict: correct.


Claim. The same specification can error in one engine and fit silently in another. By default, lme4 control settings:
- stop if a grouping factor has fewer than 2 levels (check.nlev.gtr.1);
- stop if nlev >= n for lmer, or nlev > n for glmer (check.nobs.vs.nlev, with glmer passing allow.n = TRUE);
- stop if n <= the number of random effects of a term for lmer, or n < that number for glmer, with the message '... the random-effects parameters ... are probably unidentifiable' (check.nobs.vs.nRE);
- ignore the fewer-than-5-levels check (check.nlev.gtreq.5) and the rank(Z) check (check.nobs.vs.rankZ);
- drop rank-deficient X columns with a message (check.rankX = 'message+drop.cols').
glmmTMB adjusts a rank-deficient X by default in current source.


Handling. For each engine, Stream B records the predicted fit-time behaviour (error, drop columns or fit) derived from L1-02, L1-05, L1-06 and L1-12, so the report can explain an R error or a silent fit elsewhere with the same structural finding ID. Parity tests compare the structural findings, not engine messages.


Parity. This item turns engine-specific divergence into a documented, testable expectation.


Verifier's reasoning. All listed lme4 defaults match lmerControl source: check.nlev.gtr.1 = stop, check.nobs.vs.nlev = stop, check.nlev.gtreq.5 = ignore, check.nobs.vs.rankZ = ignore, check.nobs.vs.nRE = stop, check.rankX first option message+drop.cols. glFormula passes allow.n = TRUE, which turns >= into > and <= into <, and the quoted message stem matches wmsg(). glmmTMB's rank_check default is 'adjust' in code. Four additions are useful for the forecast:
(a) checkZdims is per term, so unidentified structures split across terms (lme4's default || split) pass;
(b) glmmTMB has no nobs-vs-nRE or nlev checks, so the exact cases that make lmer stop fit silently there;
(c) check.scaleX = 'warning' by default and check.response.not.const = 'stop' for glmer;
(d) glmmTMB's own documentation still describes rank_check's default as 'warning'.


Evidence checked. https://raw.githubusercontent.com/lme4/lme4/master/R/lmerControl.R (lines 80-90), https://raw.githubusercontent.com/lme4/lme4/master/R/modular.R (wmsg lines 37-51, checkZdims 63-85, checkNlevels 166-195, lFormula allow.n = FALSE, glFormula allow.n = TRUE line 774) and https://raw.githubusercontent.com/glmmTMB/glmmTMB/master/glmmTMB/R/glmmTMB.R (lines 1638, 1691), where no nobs check was found.


## L2 Fixed-effects specification and formula parity


### L2-01 Contrast coding decides what each fixed-effect coefficient tests: report the hypothesis matrix and the coding the engine applied

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P10). Verdict: partly_correct.


Claim. By default, R (options('contrasts') = c(unordered='contr.treatment', ordered='contr.poly')) and patsy/formulaic (Treatment) give unordered factors treatment coding with the first level as reference. In A*B, the 'A' coefficient is therefore the A effect at B's reference level, and in x*A the A coefficient is the effect at x = 0. P10 needs three corrections. (i) Sum coding turns a lower-order coefficient into an average effect only if every factor it interacts with also has centred contrasts and every continuous covariate it interacts with is centred at a meaningful value. In unbalanced data, sum-coded 'main effects' are unweighted averages of cell means, not sample-weighted marginal means. (ii) In R, the coding is session state: options('contrasts'), a factor's 'contrasts' attribute and packages such as afex that set sum contrasts. It has to be read back from the fitted design (attr(X,'contrasts')), not assumed. (iii) The hypotheses that a contrast matrix tests are given by its generalised inverse (Schad et al. 2020). Two codings with the same name can therefore test different hypotheses when the level order differs between languages. Verified in patsy 1.0.3: Sum() leaves out the last level ([[1,0],[0,1],[-1,-1]] for k=3) and Helmert() is unscaled ([[-1,-1],[1,-1],[0,2]]). These are the textbook contr.sum/contr.helmert matrices, which were not run in R.


Handling. Stream B: for each factor, output the level order, reference level, numeric contrast matrix and hypothesis matrix (Moore-Penrose pseudo-inverse of [1, C]), computed the same way in both languages. Label every lower-order coefficient in an interaction as 'simple effect at <reference level / x = value>'. Warn when treatment coding is combined with interactions and the specification or report calls those terms 'main effects'. Stream A: store in provenance the contrasts the engine applied, and print the contrast and hypothesis matrices in the report.


Parity. Contrasts are stored in the shared spec as explicit numeric matrices bound to explicit level lists, never as names such as 'sum'. Engine column labels (R 'cond1', patsy 'C(cond, Sum)[S.a]') are mapped to structured IDs (see L2-06).


Verifier's correction. Derive the label from the contrast matrix of each interacting variable: 'simple effect at reference level' for a treatment-coded partner, 'average over the levels of the partner factor (unweighted)' for centred partner contrasts and 'effect at x = <stored centring constant>' for a continuous partner. State that sum-coded lower-order effects equal unweighted averages of observed cell means only in the saturated factorial.


Verifier's reasoning. The technical claim holds. Default treatment coding uses the first level, patsy Sum() leaves out the last level and patsy Helmert() is the unscaled contr.helmert. The hypothesis matrix is the generalised inverse of [1, C], as in Schad et al. 2020, and contrasts are session state in R. The phrase 'unweighted averages of cell means' overstates the case because it holds only for the saturated factorial. In a reduced model (no interaction), the sum-coded coefficient averages model-predicted cell means, not observed ones. The handling errs in labelling every lower-order coefficient in an interaction as a 'simple effect at <reference level / x = value>'. That label is true only when the interacting factor is treatment-coded or the interacting covariate is uncentred. Under sum or Helmert coding of the partner factor, the lower-order term is an average over the partner's levels, so the label would mislead users.


Evidence checked. Read lme4 2.1-1 lFormula: X <- model.matrix(fixedform, fr, contrasts) (local copy of lme4 R/modular.R). Ran patsy 1.0.3 Poly/Sum/Helmert in scratchpad/L2adv/a1.py. Coding definitions follow from the algebra.


### L2-02 Default factor level order, and so the reference level, differs between languages, locales and file formats

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: correct.


Claim. R's factor() takes levels from order() on the unique values (base/R/factor.R). For character data, that order follows the session locale's collation. R's Comparison help page warns that en_US differs from C and that collation is language-specific (e.g. Danish 'aa' sorts after 'z'). patsy 1.0.3 and formulaic 1.2.2 sort strings by Unicode code point, and for a pandas Categorical they use the stored category order. For labels {a, B, c, b}, both Python libraries choose 'B' as the reference (verified). R in a C locale would also give 'B' (byte order), but en_US collation puts 'a' first. A CSV round trip drops relevel()/factor(levels=) information, so a reference level chosen in R silently reverts in Python, and the reverse. The same codes sort numerically when stored as numbers (9 < 10) and lexicographically when stored as strings ('10' < '9').


Handling. For every categorical, Stream B checks where its level order comes from (explicit / Categorical / implicit sort) and whether the order would differ between C and locale collation (mixed case, accented or non-ASCII labels, punctuation). It also checks for numeric-looking string labels. Implicit reference levels are warnings in confirmatory mode. The suite always writes the level list and reference level into the design manifest and applies them before building X in both languages.


Parity. Exact tier: level lists must be byte-identical across languages. Golden fixtures should include mixed-case, accented and numeric-string labels.


Verifier's reasoning. Confirmed in R's factor.R: levels <- unique(y[ind]) with ind <- order(y). For character vectors, order()'s 'auto' method uses shell sort, which follows locale collation. R's Comparison.Rd says en_US is normally different from C and that Danish 'aa' sorts as a single letter after z. patsy 1.0.3 and formulaic 1.2.2 both gave levels B, a, b, c for {a, B, c, b}, so 'B' is the reference. The CSV round-trip and numeric-string points are standard. The handling is sound.


Evidence checked. Local copies of r-source base/R/factor.R (lines 20-40) and base/man/Comparison.Rd (lines 40-44). Experiment scratchpad/L2adv/a1.py: columns g[T.a], g[T.b], g[T.c] with reference B in both libraries.


### L2-03 Ordered factors: polynomial contrasts in R, treatment contrasts in Python

Kind: edge_case. Stream: both. Priority: essential. Origin: preliminary (P10). Verdict: partly_correct.


Claim. By default, R codes ordered factors with contr.poly, whose orthogonal polynomial contrasts use scores = 1:n (stats/R/contr.poly.R) and assume equally spaced levels. patsy 1.0.3 and formulaic 1.2.2 give a pandas ordered Categorical treatment coding by default (verified: columns g[T.mid], g[T.hi]). The same data and formula therefore produce .L/.Q coefficients in R and dummy coefficients in Python. If Poly() is requested explicitly, patsy matches the standard contr.poly values for k = 4 and for k = 3, where .L = -0.7071, 0, 0.7071 and .Q = 0.4082, -0.8165, 0.4082 (verified in Python, with R reference values taken from the documented contr.poly output). Ordered factors often go unnoticed (factor(..., ordered=TRUE), cut(..., ordered_result=TRUE)). With k >= 5, cubic and higher contrasts are rarely interpretable, and default scores mis-specify unequally spaced categories (e.g. doses 0/10/100).


Handling. Detect ordered factors and report the contrast each language would apply. In confirmatory specs, require an explicit coding for ordered factors (treatment, sum, poly with scores, successive differences). Warn when ordered levels look numeric and unequally spaced, and suggest scores= or a numeric predictor.


Parity. The IR carries the numeric contrast matrix, so an ordered/unordered flag never decides the coding implicitly.


Verifier's correction. With a full set of k-1 contrasts, poly vs treatment coding, and any choice of scores, is a reparametrisation of the same fixed-effects model. Unequal spacing makes the individual linear/quadratic trend coefficients misleading but does not mis-specify the model, unless only a subset of the polynomial terms is kept (e.g. linear only) or the factor carries diag/'||' random slopes. Warn about interpretation, not misfit.


Verifier's reasoning. The software behaviour is confirmed. R's contr.poly has scores = 1:n, and a pandas ordered Categorical gets Treatment coding in both patsy and formulaic (g[T.mid], g[T.hi]). patsy Poly gives -0.7071/0/0.7071 and 0.4082/-0.8165/0.4082. The overstatement is 'default scores mis-specify unequally spaced categories'. With all k-1 polynomial contrasts in the model, the column space equals that of treatment coding for any scores. Fitted values, the ML likelihood and the fixed-effect fit are identical, so the model is not mis-specified. Scores change only what the individual .L/.Q coefficients mean and the fits that are not invariant to the basis: diag or '||' random slopes on the factor (L2-10/L2-11) and the REML criterion (L2-12). The same applies to the R-vs-Python gap, where the coefficients differ but the fixed-effects model is the same.


Evidence checked. Local copy of r-source stats/R/contr.poly.R line 19 (scores = 1:n). Experiment scratchpad/L2adv/a1.py (ordered Categorical gives Treatment in both libraries, and Poly values are as stated). Span equivalence follows from the algebra (any full-rank k-1 contrast set plus intercept spans the k indicators).


### L2-04 Levels that are unused or emptied by listwise deletion: silent reference changes, dropped contrasts, zero columns

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: correct.


Claim. lme4 calls model.frame with drop.unused.levels = TRUE (lme4 R/modular.R). model.frame.default removes empty levels after subset and na.action (stats/R/models.R). This has three consequences in R. (a) If listwise deletion removes all rows of the reference level, the next level silently becomes the reference. (b) If a factor with custom contrasts (contrasts(f) <- contr.sum(k)) loses a level, those contrasts are discarded with only the warning 'contrasts dropped from factor f due to missing levels', and the default coding is used. (c) A factor left with one level stops the fit with 'contrasts can be applied only to factors with 2 or more levels'. Python behaves differently (verified, patsy 1.0.3 / formulaic 1.2.2). Both keep unused pandas Categorical categories, producing an all-zero column and a rank-deficient X. patsy also keeps a level that appears only in rows dropped for a missing outcome, so the design is collinear with the intercept (rank 2 of 3 in the test). formulaic drops that level, as R does. Both silently drop a single-level factor term instead of raising an error.


Handling. Stream B computes levels on the final analysis sample and reports, per factor, the levels lost to deletion or subsetting, whether the reference changed and whether declared contrasts can still be honoured. In confirmatory mode, raise an error (not a warning) when the declared reference or contrast cannot be honoured or when a factor has a single level. Both packages then build X from the post-deletion level list.


Parity. Exact tier. Golden fixtures should cover unused Categorical categories, a reference level present only in NA-outcome rows, a sum-coded factor that loses a level and a single remaining level.


Verifier's reasoning. In the R source, lme4 lFormula sets mf$drop.unused.levels <- TRUE. model.frame.default drops levels after C_modelframe has applied subset and na.action. Dropping goes through x[, drop = TRUE], which calls `[.factor` and then factor(). That loses the 'contrasts' attribute, and R warns 'contrasts dropped from factor %s due to missing levels'. In the Python re-run, patsy keeps a level present only in an NA-outcome row (columns Intercept, f[T.b], f[T.c], with rank 2 of 3), and formulaic drops it. Both keep unused Categorical categories as all-zero columns (rank 2 of 3) and silently drop a single-level factor term. A coding passed through lmer's contrasts= argument survives the drop, however, because model.matrix applies it afterwards. Only the attribute set on the factor is lost.


Evidence checked. Local copies of lme4 R/modular.R line 367 and r-source stats/R/models.R lines 564-575 and base/R/factor.R lines 259-267. Experiment scratchpad/L2adv/a1.py.


### L2-05 Rank deficiency: which column gets dropped depends on the QR algorithm and on column order, so replicate lme4's rule and report the aliasing

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P8). Verdict: partly_correct.


Claim. lme4 (source, version 2.1-1) checks X with qr(X, tol = 1e-7, LAPACK = FALSE). This is LINPACK dqrdc2 with limited pivoting, which moves only near-dependent columns to the end and otherwise keeps the column order. lme4 keeps the first 'rank' pivots, so the later of two aliased columns is the one dropped. It prints 'fixed-effect model matrix is rank deficient so dropping k column(s) / coefficient(s)' (control: check.rankX). LAPACK pivoted QR (scipy.linalg.qr(pivoting=True), geqp3) pivots by column norm and can drop a different column. For X = [1, x1, x2, x3 = x1 + x2] with sd(x2) about 10*sd(x1), an in-order rule drops x3 while geqp3 drops x2 (verified). patsy also orders columns differently from R (L2-06), so even the same algorithm can drop different coefficients across languages. With an empty cell in A x B (verified for 2x3), the column dropped is the last interaction column, and the remaining interaction coefficients lose their textbook meaning.


Handling. Stream B: on the canonical column order, check rank with an in-order Gram-Schmidt (equivalent to dqrdc2) and a tolerance of 1e-7 relative to each column's norm. Report each dependency (which columns are linear combinations of which, like stats::alias), map it to empty factorial cells and propose concrete fixes (drop or reduce the interaction, collapse levels, cell-means coding). Stream A: in confirmatory mode, stop instead of letting the engine drop columns. If dropping is allowed, the suite drops the same canonical columns itself in both languages before calling the engine.


Parity. Exact tier on which columns are dropped. Python must not use numpy.linalg.matrix_rank or geqp3 to decide which columns to drop.


Verifier's correction. The column lme4 drops for an empty cell is the interaction column that becomes zero or aliased, which depends on the empty cell (e.g. A2:B2 when cell a2-b2 or a1-b2 is empty), not 'the last interaction column'. Replicate lme4's decision by porting LINPACK dqrdc2, not by an 'equivalent' Gram-Schmidt. In R, read attr(X, 'col.dropped') back as the ground truth for the golden tests.


Verifier's reasoning. The lme4 facts are confirmed. chkRank.drop.cols uses qr(X, tol = 1e-7, LAPACK = FALSE), keeps qr.X$pivot[seq_len(rank)], prints the stated message and records attr(X, 'col.dropped'). Two claims are refuted. (1) 'With an empty cell in A x B the column dropped is the last interaction column' is wrong in general, because the column dropped depends on which cell is empty. Over all six possible empty cells of a 2x3 treatment-coded design, an in-order rule drops A[T.a2]:B[T.b3] for empty cells in columns b1 or b3, but A[T.a2]:B[T.b2] for an empty cell in column b2. (2) 'In-order Gram-Schmidt (equivalent to dqrdc2)' is too strong. dqrdc2 is Householder QR with column-norm downdating, and it moves a column only when its updated norm falls below tol times the original norm. Modified Gram-Schmidt makes the same decision in exact arithmetic but can differ near the threshold. For exact parity, port dqrdc2 itself (a short routine). In the empty-cell cases, geqp3 happened to agree with the in-order rule, so the divergence the item reports comes mainly from differences in column scale.


Evidence checked. Local copy of lme4 2.1-1 R/modular.R lines 225-290. Experiment scratchpad/L2adv/a4.py: all six empty cells of a 2x3 design, in-order rule vs scipy geqp3.


### L2-06 Canonical column order and structured coefficient IDs

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: correct.


Claim. R orders terms by interaction order and then by order of appearance in the formula. patsy additionally groups terms by the numeric factors they contain (patsy's 'Differences between R and Patsy formulas' page). 'x + a + x:a' gives Intercept, a[T.q], x, x:a[T.q] in patsy 1.0.3 but Intercept, x, a[T.q], x:a[T.q] in formulaic 1.2.2, which matches R's rule here (verified). Engine column names cannot be parsed back reliably. R pastes variable and level together ('condb' could be factor 'cond' with level 'b' or factor 'con' with level 'db'), and patsy and formulaic use 'cond[T.b]'.


Handling. Define a canonical column order (R's rule) and a structured column ID: term, an ordered list of (variable, level or basis index) and contrast ID. All coefficient-level outputs in the results JSON (estimates, VIFs, dropped columns, influence) are keyed by this ID, never by position or engine label. Each package maps engine labels to IDs by constructing them, not by parsing strings.


Parity. Exact tier. Golden tests compare coefficient by ID.


Verifier's reasoning. In a re-run, 'x + a + x:a' gave Intercept, a[T.q], x, x:a[T.q] in patsy 1.0.3 and Intercept, x, a[T.q], x:a[T.q] in formulaic 1.2.2. patsy's R-comparison page (lines 41-48) describes R's two ordering rules and patsy's extra grouping by numeric factors. The label-ambiguity argument for R's pasted names is sound. Building IDs rather than parsing labels is the right design.


Evidence checked. Local copy of pydata/patsy doc/R-comparison.rst lines 41-48. Experiment scratchpad/L2adv/a1.py.


### L2-07 Terms with missing margins and intercept rules are coded differently by R, patsy and formulaic

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: correct.


Claim. The coding of a term whose lower-order margins are absent depends on the implementation. According to patsy's documentation (where R behaviour was last checked with R 2.15.0), R's model.matrix(~ 1 + a:b) for two 2-level factors has 5 columns but rank 4, while patsy and formulaic give 4 columns of rank 4 (verified). For ~ 0 + a:x + a:b with x numeric, R gives 4 columns and patsy gives 6 (verified 6 in patsy and formulaic). Intercept handling also differs. According to patsy's documentation, R reads 1 + (b - 1) as having no intercept, whereas patsy and formulaic keep it (verified). For y ~ (b - 1), patsy 1.0.3 drops the intercept (verified, contrary to its own documentation) and formulaic 1.2.2 keeps it. Formulas that break marginality (a:b without a and b, or x:f without x) are valid only as deliberate reparametrisations (nested slopes, cell means), and their coefficients test different hypotheses from the crossed parametrisation.


Handling. Stream B: flag every term with an absent lower-order margin. Classify it as deliberate nesting (a/b pattern, cell-means '0 + f') or a likely mistake, and show the hypothesis each resulting coefficient tests. Reject formulas whose intercept depends on parentheses around '-1', or rewrite them with an explicit intercept flag in the IR. The suite builds X from the IR using one documented full-rank coding algorithm, compares the engine's X with it (rank and column space) and passes the IR-built X when they differ.


Parity. Exact on rank and column space. Where R's model.matrix is over-parameterised and the IR is not, report the difference and fit with the IR matrix.


Verifier's reasoning. The Python claims were re-verified. In both libraries, '1 + a:b' gives 4 columns of rank 4, '0 + a:x + a:b' gives 6 columns and '1 + (b - 1)' keeps the intercept. 'y ~ (b - 1)' drops the intercept in patsy (columns b[r], b[s]), contradicting patsy's own documentation, which says it should have one. formulaic keeps it. The R behaviours are quoted correctly from patsy's documentation, which notes they were last checked with R 2.15.0. They were not re-run in current R, so the golden fixtures should regenerate them. The handling is sound.


Evidence checked. Local copy of patsy doc/R-comparison.rst lines 50-75 and 140-185. Experiment scratchpad/L2adv/a1.py.


### L2-08 Operator translation hazards: ^ vs **, I() evaluated as host-language code, %in%, '.', nesting

Kind: edge_case. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Python formula engines evaluate the inside of I() as Python. R's I(k^2) therefore becomes bitwise XOR. On an integer column 1..5, patsy 1.0.3 silently returns 3, 0, 1, 6, 7 (verified), and on float columns patsy and formulaic raise TypeError. At formula level, R's '^' means crossing, so x^2 is x and y ~ x + x^2 silently fits only x (R formula docs). patsy (x**2) and formulaic (x^2 and x**2) reproduce this silently (verified). patsy rejects (a+b)^2 and needs **, whereas formulaic accepts both. %in% exists in R and formulaic but not in patsy, and '.' works in formulaic (verified) but not in patsy. patsy and formulaic both expand a/b to a + a:b and (a+b)/c to a + b + a:b:c (verified). R's documentation defines a/b = a + b %in% a. The (a+b)/c case was not run in R here.


Handling. The shared parser tokenises the R-style grammar itself and produces the IR. Inside I(), it accepts only a whitelisted arithmetic sublanguage (+ - * / ^, log, exp, sqrt, abs, numeric constants) and translates it deterministically (^ becomes **). Host-language code is never passed to eval. Lint 'x^k' or 'x**k' outside I() on a single numeric variable with the message 'this is x, not x squared'. In confirmatory mode, forbid '.' or expand it to an explicit variable list and print that list. Check the expansion of every operator against R's terms() output in golden tests.


Parity. Exact on the IR term list.


Verifier's correction. Both patsy and formulaic evaluate I(k^2) as XOR on integer columns. In patsy, 'k^2' outside I() is also a Python XOR factor, which silently adds a wrong column on integer data and raises an error on floats. The lint must also catch '^' on integer columns in patsy-style input, and the parser must treat R's '**' as a synonym of '^' at formula level.


Verifier's reasoning. The item is mostly confirmed but understates the hazard. (1) Like patsy, formulaic 1.2.2 silently XORs I(k^2) on an integer column (3, 0, 1, 6, 7). (2) Outside I(), patsy does not reproduce R's 'x^2 is x'. It parses 'k^2' as a Python expression. As a result, 'k + k^2' with integer k silently adds a column 'k ^ 2' = 3, 0, 1, 6, 7, whereas with float x it raises TypeError. Only formulaic silently reduces x^2 to x, as R does. patsy's documentation says '^' 'will be interpreted as a call to the Python binary XOR operator'. The other checks showed that patsy rejects (a+b)^2, that %in% and '.' fail in patsy and work in formulaic, and that a/b expands to a + a:b and (a+b)/c to the term list a + b + a:b:c in both. R's formula.Rd defines a/b as a + b %in% a.


Evidence checked. Local copies of r-source stats/man/formula.Rd lines 56-75 and patsy doc/R-comparison.rst lines 21-29. Experiments scratchpad/L2adv/a2.py and a3.py (k + k^2 in patsy gave columns Intercept, k, 'k ^ 2' = [3, 0, 1, 6, 7], and the term list for (a+b)/c is a, b, a:b:c).


### L2-09 '||' now means different things across engines and options, and (1 + f || g) is over-parameterised

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P18). Verdict: partly_correct.


Claim. From lme4 2.0-1 (2026-03-05), lme4 supports structured covariance terms: us(), diag(), cs(), ar1(). '||' still defaults to the 'split' expansion via reformulas::expandDoubleVerts, which turns (1 + f || g) into (1|g) + (0 + f|g). For a k-level factor, (0 + f|g) is a k-dimensional unstructured block, so the correlations among level-specific effects remain. P18 is right about the default but needs two corrections. (i) '||' is now configurable: options(lme4.doublevert.default = 'diag_special') turns it into diag(). According to lme4's NEWS, afex::mixed and glmmTMB already treat '||' as diag(), so one formula string fits different models depending on engine and session option. (ii) The split expansion of (1 + f || g) is over-parameterised. Every row of the (0 + f) indicator matrix sums to 1, so the intercept variance enters the marginal covariance only through Sigma_f + sigma0^2 * 11', and sigma0^2 is not identifiable. Expect a singular fit or an arbitrary split between components. For numeric slopes, '||' is not invariant to centring (L2-11).


Handling. The IR has no '||'. The parser expands it into explicit random-effects blocks, each with an explicit covariance structure (us/diag/cs), and records which interpretation was applied. Lint '||' used with factors and the (1 + f || g) pattern, and report the number of covariance parameters per block. In R, emit diag() explicitly for lme4 >= 2.0 and glmmTMB rather than relying on '||'.


Parity. The Python side must use the same block-wise covariance structure from the IR. Results stay engine-specific where an engine cannot represent that structure.


Verifier's correction. afex::mixed gives zero-correlation factor slopes only with expand_re = TRUE (default FALSE), as a diagonal structure over the contrast-coded columns, so it depends on the coding. Record the contrast basis together with the diag() expansion in the IR.


Verifier's reasoning. lme4's NEWS confirms that 2.0-1 (2026-03-05) added us/diag/cs/ar1, kept 'split' as the '||' default and added options(lme4.doublevert.default = 'diag_special'). lFormula calls expandDoubleVerts only when getDoublevertDefault() == 'split', and expandDoubleVerts produces '1' plus '0+<term>' blocks. The non-identifiability algebra for (1 + f || g) is correct: Z0 = Z_f(I ⊗ 1_k), so the covariance depends only on Sigma_f + sigma0^2 * 11'. The statement 'afex::mixed already treats || as diag()' is an overstatement. lme4's NEWS only says the diag behaviour 'will match afex::mixed or glmmTMB'. afex::mixed has expand_re = FALSE by default, and only expand_re = TRUE converts factors to numeric contrast columns so that '||' works. By default, afex passes '||' on to lme4's split expansion. The afex expansion is diag over contrast-coded columns, so it depends on the coding (L2-10/L2-11).


Evidence checked. Local copy of lme4 inst/NEWS.Rd lines 266-300. Local copy of reformulas R/utils.R expandDoubleVerts (lines 56-90). lme4 R/modular.R lines 360-362. WebFetch of https://raw.githubusercontent.com/singmann/afex/master/R/mixed.R (signature expand_re = FALSE, and roxygen 'Allows to use "||" notation with factors').


### L2-10 lmer's contrasts= argument does not reach the random-effects design

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: correct.


Claim. In lme4 (source, version 2.1-1), the contrasts argument is used only when building the fixed-effects matrix: X <- model.matrix(fixedform, fr, contrasts). Random-effects term matrices are built in reformulas' mkReTrms via model.matrix(~ <lhs>, frloc), with no contrasts argument. A random slope for factor f therefore uses f's 'contrasts' attribute or the global options('contrasts'). So lmer(y ~ f + (1 + f | g), contrasts = list(f = 'contr.sum')) gives sum-coded fixed effects but treatment-coded random slopes. This is inferred from the source and was not run in R here. With an unstructured covariance, this is only a reparametrisation (same likelihood), but the variances and correlations are reported in a different basis from the fixed effects. With diag() or '||' structures, it changes the model.


Handling. Stream A: report the coding of each random-effects block and warn when it differs from the fixed-effects coding of the same factor. The R package should set the coding on the factor itself (attribute) from the IR's contrast matrix, so that X and Z share it, rather than passing contrasts=.


Parity. The Python package builds Z from the same IR contrast matrix.


Verifier's reasoning. The claim is confirmed from the source. lFormula passes contrasts only to X <- model.matrix(fixedform, fr, contrasts). reformulas mkBlist builds the random-effects block with mm <- mMatrix(~ <lhs>, frloc), with no contrasts argument, so the factor's attribute or options('contrasts') applies. The reparametrisation argument for unstructured covariance and the change of model under diag are correct (see L2-11 for the diag/centring experiment). As the item says, this was not run in R.


Evidence checked. Local copies of lme4 2.1-1 R/modular.R line 438 and reformulas R/mkReTrms.R lines 185-232.


### L2-11 Centring and scaling are harmless reparametrisations only with unstructured random-effects covariance

Kind: edge_case. Stream: both. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. With an unstructured random-effects covariance, replacing x by (x - c)/s is an exact reparametrisation: the ML log-likelihood is unchanged, and beta and the random-effects covariance transform linearly. With diag or '||' structures, it is not. If b0 and b1 are independent for x, then for x' = x - c, the intercept becomes b0 + c*b1, and Cov(b0 + c*b1, b1) = c*Var(b1), which is not zero. Zero-correlation models fitted on centred x and on raw x are different models with different likelihoods. Separately, in any random-slope model, the random-intercept variance (and any ICC built from it alone) refers to x = 0. With x = age in years, uncentred, it is the between-group variance at birth.


Handling. Stream B: for each predictor with a random slope, report where zero lies relative to the data (e.g. |mean|/sd and whether 0 lies inside the observed range). Warn when a zero-correlation or diag structure is proposed for a predictor whose zero is far from the data. Any simplification step that drops correlations must state the centring it assumes. Store all centring constants (grand mean, cluster means) in provenance, and label intercept-variance summaries with the value at which they are evaluated.


Parity. Centring constants come from the IR (computed on the analysis sample), so both languages fit the same parametrisation.


Verifier's correction. Shifting x (centring) is a reparametrisation only under unstructured random-effects covariance. Pure rescaling is a reparametrisation under both unstructured and diag/'||' structures. Cluster-mean centring changes the model and must be recorded as a model choice, not as a centring constant.


Verifier's reasoning. The core claim is right and was verified in statsmodels with 40 groups x 8 observations. With unstructured covariance, the ML llf was identical for raw, centred and x/10 (-565.9546). With diagonal covariance, raw gave -640.6952 and centred gave -566.1250. However, the claim treats the shift and the scale in (x - c)/s as one. Pure rescaling (c = 0) preserves a diagonal or zero-correlation structure exactly (diag x/10 gave -640.6952, same as raw), because Var(b1) is only multiplied by 1/s^2. Only the shift c breaks it. The item also misses two points. (a) Group-mean (cluster) centring, which the handling stores as a 'centring constant', is not a reparametrisation. It changes the model by separating within and between effects (cf. P7). (b) Even under unstructured covariance, rescaling changes the REML criterion (L2-12), although the estimates are the same.


Evidence checked. Experiment scratchpad/L2adv/a5.py (statsmodels 0.15.0 MixedLM, diagonal covariance via the free= argument).


### L2-12 The REML criterion changes with fixed-effects parametrisation (units and contrasts), but ML does not

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. The REML log-likelihood contains -0.5*log|X'V^-1 X|. Under X -> XA, it shifts by -log|det A|, while the REML estimates of the variance parameters stay the same. Centring alone (a unit-triangular A) leaves it unchanged, whereas rescaling or changing contrasts does not. In a verification run with statsmodels 0.15.0 MixedLM, multiplying one predictor by 1000 lowered the REML llf by exactly 6.9078 (= log 1000), and the ML llf and random-effect variance did not change. Treatment, sum and Helmert coding of the same 3-level factor gave REML llf of -369.21, -370.31 and -371.00 on identical data. REML logLik, AIC and BIC therefore depend on predictor units and coding. This applies to any implementation of the standard REML criterion, although it was demonstrated here in statsmodels only.


Handling. Stream A labels the REML criterion as parametrisation-dependent. It refuses REML-based LRT, AIC or BIC comparisons between models with different fixed-effects matrices (refit with ML), and explains that REML differences between fits that differ only in coding or scaling are artefacts.


Parity. Cross-language parity tests compare REML values only when the IR X matrices are identical. Otherwise compare ML log-likelihood and variance estimates.


Verifier's correction. Many implementations, statsmodels included, omit the +0.5*log|X'X| term of the error-contrast REML likelihood, so their REML criterion depends on units and coding. The full error-contrast form is invariant. The suite can report it (engine REML llf + 0.5*log|X'X|) for cross-language parity and for comparing fits that differ only in coding or scaling. Keep the refusal of REML comparisons between models with different column spaces.


Verifier's reasoning. The algebra and the statsmodels behaviour are confirmed. Scaling x by 1000 lowered the REML llf from -644.433 to -651.341 (difference 6.908 = log 1000). The overstatement is 'applies to any implementation of the standard REML criterion', because the dependence comes from leaving out the +0.5*log|X'X| term. Harville's error-contrast REML likelihood (the likelihood of K'y with K'X = 0 and K'K = I) includes it through log|K'VK| = log|V| + log|X'V^-1X| - log|X'X|, and is invariant to X -> XA. Adding 0.5*log|X'X| to statsmodels' REML llf gave -637.1421 at both scales. Whether an engine includes that term is implementation-specific (not checked for lme4 or glmmTMB here).


Evidence checked. Experiment scratchpad/L2adv/a5.py (statsmodels 0.15.0): the REML llf with 0.5*log|X'X| added is identical for x and 1000*x. The identity for log|K'VK| is standard linear algebra.


### L2-13 Scale disparity: replicate lme4's check exactly and keep it separate from collinearity

Kind: feature. Stream: B. Priority: valuable. Origin: preliminary (P16). Verdict: correct.


Claim. lme4's checkScaleX (source, version 2.1-1) looks only at X columns that are not entirely 0/1. It takes their SDs and warns 'Some predictor variables are on very different scales: consider rescaling' when any pairwise SD ratio, or any single SD, exceeds 1e3 or is below 1e-3 (|log| > log(1e3)). This is a heuristic about units, not a collinearity measure. The Belsley-type condition number, with columns scaled to unit length, does not change when a column is rescaled (verified: raw kappa(X) rose from 17.7 to 17312 when one column was multiplied by 1000, while the scaled kappa stayed at 6.13). Units and near-dependence must therefore be reported separately. Since lme4 1.1-38, lmerControl(autoscale = TRUE) applies scale() to every non-intercept column of X, 0/1 dummies included, and reports results on the original scale.


Handling. To anticipate the warning before fitting, Stream B reproduces checkScaleX exactly in both languages. It reports raw and scaled condition numbers side by side and suggests centring and scaling outside the formula with stored constants (L2-14) and back-transformed coefficient tables. Provenance records whether engine autoscaling was used.


Parity. Exact tier on whether the check fires.


Verifier's reasoning. The claim is confirmed against the source. checkScaleX excludes columns with all values in {0, 1}, computes the SDs of the remaining columns and fires if any |log| of a pairwise ratio or of a single SD exceeds log(1e3). The warning text matches, and lme4 now appends advice to use autoscale = TRUE. Autoscale is in NEWS for 1.1-38 ('results reported on the original data scale'). The code applies scale(X[, -1]) to all non-intercept columns when an intercept is present and to all columns otherwise. Two implementation details should be copied. Sum- or Helmert-coded columns (values -1/0/1) are not all in {0, 1}, so they are included in the SD check. The check runs after autoscaling and after rank-deficient columns are dropped.


Evidence checked. Local copies of lme4 2.1-1 R/modular.R lines 127-158 and 440-459, and inst/NEWS.Rd lines 343-381. Invariance of the unit-length-scaled condition number to column rescaling follows by construction.


### L2-14 In-formula data-dependent transforms use the wrong sample and differ in defaults

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: correct.


Claim. R's model.frame.default evaluates the formula variables (eval(predvars, data, env)) before applying subset and na.action (C_modelframe). Inside a formula, scale(x), poly(x) and bs(x) are therefore computed on rows outside the analysis sample: rows with a missing outcome, other predictor or grouping factor, and rows excluded by subset=. patsy center() and formulaic center()/bs() also use the pre-deletion rows (verified: centre 20 against an analysis-sample mean of 25, and formulaic's bs boundary knot was set to 100 by a row whose outcome was missing). Defaults also differ. R's scale() divides by the SD with n - 1, and with center = FALSE by the root mean square sqrt(sum(x^2)/(n - 1)) (base/R/scale.R). patsy standardize()/scale() uses ddof = 0 (-1.342 against R's -1.162 at x = 1 for 1:4) and with center = FALSE divides by the centred SD. formulaic scale() matches R in both cases (verified). R's poly() stops on any NA ('missing values are not allowed in 'poly''), whereas formulaic's poly() silently builds the basis from the non-missing rows (verified).


Handling. In confirmatory mode, disallow data-dependent transforms inside the formula (scale, center, poly, bs/ns, quantile cut), or have the suite evaluate them on the final analysis sample, store their constants (centre, scale, alpha/norm2, knots) in the IR and pass the resulting columns to the engine. Stream B reports, for each such transform, which sample the engine would have used and how much the constants differ.


Parity. Exact or tight-tolerance parity is only possible when the transformed columns are materialised from the IR.


Verifier's reasoning. In models.R, model.frame.default evaluates variables <- eval(predvars, data, env) before C_modelframe applies subset and na.action. A Python re-run confirmed that center(x) used the full-data mean 20, not the analysis-sample mean 25, in both patsy and formulaic. patsy standardize/scale use ddof = 0 (-1.342) and, with center=False, divide by the centred SD (0.894). formulaic scale matches R, giving -1.162, and 0.316 = 1/sqrt(sum(x^2)/(n-1)) with center=False. R's scale.R uses sqrt(sum(v^2)/max(1, n-1)). R's poly() stops on NA, whereas formulaic poly() builds the basis from the 4 non-missing rows. lme4's model frame includes the random-effects variables, so in R the transform also sees rows later dropped for an NA grouping factor.


Evidence checked. Local copies of r-source stats/R/models.R lines 506-536, base/R/scale.R and stats/R/contr.poly.R line 89. Experiments scratchpad/L2adv/a2.py and a9.py.


### L2-15 poly(): sample-dependent orthogonal basis that patsy lacks and formulaic reproduces

Kind: feature. Stream: both. Priority: valuable. Origin: new. Verdict: correct.


Claim. R's poly(x, d) returns an orthonormal basis built from the data: centre, QR of the Vandermonde matrix, normalise the columns. Its alpha and norm2 coefficients are stored in predvars for prediction (stats/R/contr.poly.R). The coefficients are not linear or quadratic effects of raw x. The basis changes with the sample, and with it every poly coefficient, the lower-order SEs and any random-slope covariance on poly terms. patsy 1.0.3 has no poly() (its builtins are I, Q, C, the contrast classes, center/standardize/scale, bs, cr/cc/te). formulaic 1.2.2's poly() matched R's poly(1:5, 2) to 7 decimals, sign convention included, and matched a re-implementation of R's algorithm on an unequally spaced x (verified). raw = TRUE corresponds to I(x^k) terms.


Handling. The IR stores each poly term as (variable, degree, raw flag, alpha, norm2), computed on the analysis sample, and both packages generate the basis from those stored values. Reports state that orthogonal-polynomial coefficients are not raw-scale effects and offer a raw-scale back-transformation. Golden tests compare against R-generated bases.


Parity. Numerical tolerance (about 1e-10) on basis columns, with signs fixed by the stored coefficients.


Verifier's reasoning. formulaic 1.2.2 poly(x, 2) on 1:5 gave (-0.632456, -0.316228, 0, 0.316228, 0.632456) and (0.534522, -0.267261, -0.534522, -0.267261, 0.534522). These match R's documented poly(1:5, 2), signs included. patsy's builtins have Poly only as a contrast, not a basis function. The orthogonal basis spans the same space as the raw polynomial, so fits are unaffected and only the coefficients and basis-specific quantities change, as the item says. The handling is sound.


Evidence checked. Experiment scratchpad/L2adv/a2.py. Local copy of r-source stats/R/contr.poly.R (poly algorithm and NA stop).


### L2-16 Splines: basis families and knot placement are not portable by default

Kind: edge_case. Stream: both. Priority: optional. Origin: new. Verdict: partly_correct.


Claim. patsy's bs() docstring states that it produces output identical to R's bs() given identical inputs and settings. patsy has no counterpart to splines::ns (natural cubic B-spline). Its cr() is an mgcv-style cubic regression spline, a different basis with different constraints. Default knots are quantiles computed on whatever rows the formula engine evaluates, which are the pre-deletion rows (L2-14). This was verified for formulaic, where a row with a missing outcome set the boundary knot. patsy's bs() raises an error when evaluated outside its stored boundary knots. Spline coefficients are specific to the basis, so only fitted curves can be compared across languages.


Handling. The IR stores the spline family, degree, interior knots and boundary knots explicitly, computed on the analysis sample. The Python package either implements ns() following R's construction or the grammar allows only spline families available in both languages. Compare fitted curves and column spaces, not individual coefficients. Stream B flags knots that depend on rows outside the analysis sample and knot intervals with very few observations.


Parity. Parity on fitted values (numerical tolerance), and coefficient parity only when the basis definitions are identical.


Verifier's correction. patsy cr() with explicit knots equal to ns()'s interior and boundary knots spans the same natural-cubic-spline space as ns(..., intercept = TRUE). Parity is possible at the level of fitted values and column space, without reimplementing ns(), as long as the knots come from the IR.


Verifier's reasoning. The claim contains two overstatements. (1) The patsy BS docstring is hedged: 'In cases where both return output at all ... they should produce identical output given identical input and parameter settings'. It does not flatly state identity. (2) 'cr() is a different basis with different constraints' and 'no counterpart to ns' are misleading. patsy's cr (mgcv-style cubic regression spline) is a natural cubic spline. With the same knots and boundary knots, its 5 columns span exactly the same space as the ESL natural-cubic-spline basis (rank of [cr, N] = 5 = rank of each), which is the space of splines::ns(..., intercept = TRUE). Column-space parity with ns is therefore achievable, and only the coefficients differ. As claimed, patsy bs() raises NotImplementedError ('some data points fall outside the outermost knots') when evaluated outside its stored knots. As a minor point, R's bs()/ns() place quantile interior knots only when df is given, and without df there are no interior knots.


Evidence checked. Experiment scratchpad/L2adv/a7.py: patsy.splines.BS docstring text, column-space equality of cr and the ESL natural spline basis, bs extrapolation error.


### L2-17 Transformation domain violations silently change N or break the fit

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. log(x) with x < 0 returns NaN. R's na.omit treats NaN as missing, as does patsy/formulaic NA handling, so those rows are dropped silently (verified: 5 rows down to 4 in patsy and formulaic). R only warns 'NaNs produced'. log(0) returns -Inf, which none of them treats as missing. patsy and formulaic keep the -Inf in X (verified), so the fit then fails or yields non-finite results. sqrt of negatives and division by zero behave the same way. In log(x + c), the choice of c changes the model.


Handling. Stream B evaluates every transformation on the analysis sample before fitting. Rows that produce NaN or +/-Inf are reported separately from genuine missingness in the N-per-model table (P12), along with any added constant c. Confirmatory mode stops on any non-finite value in X.


Parity. Exact: both languages count rows lost to transformations the same way, because the suite does the counting.


Verifier's correction. What happens to non-finite values depends on the pipeline. Used directly, patsy and formulaic drop NaN rows silently, whereas statsmodels from_formula raises an error on NaN created by a transform. Every pipeline keeps +/-Inf. Division by zero gives +/-Inf (0/0 gives NaN). Keep the handling, in which the suite evaluates transforms itself and counts NaN and Inf rows separately.


Verifier's reasoning. The claim is correct for patsy used directly: the log(-1) row was dropped (40 to 39 rows), and the log(0) -Inf stayed in X. Through statsmodels' formula interface, however, the NaN is not dropped silently: smf.mixedlm('y ~ np.log(x)', ..., groups='g').fit() raised PatsyError 'factor contains missing values'. statsmodels drops missing values in the raw variables itself and then calls patsy with NA_action='raise', so NaN created by a transformation becomes a hard error. Division by zero does not behave 'the same way' as sqrt of a negative. sqrt(-1) gives NaN, but x/0 gives +/-Inf, which is kept, and only 0/0 gives NaN, which is dropped or raises.


Evidence checked. Experiment scratchpad/L2adv/a8.py (patsy 1.0.3, statsmodels 0.15.0).


### L2-18 Variable-type errors in both directions, plus boolean handling

Kind: edge_case. Stream: B. Priority: valuable. Origin: preliminary (P11). Verdict: partly_correct.


Claim. A numeric variable with a few integer codes (condition = 1/2/3) enters R, patsy and formulaic as one linear slope, which imposes equal spacing and linearity (P11). Three points sharpen P11. (i) A binary predictor coded 1/2 has the same slope as a dummy, but its zero lies outside the data, so in interactions the other lower-order terms are evaluated at the impossible value 0. Code it 0/1 or +/-0.5. (ii) The reverse mistake is as common: numbers stored as strings (decimal commas, '<5', 'n/a', sentinel codes) turn into factors with many levels and many parameters. (iii) patsy treats a boolean as categorical (column bb[T.True]), whereas formulaic treats it as numeric (column bb) (verified). The values are the same but the type and name differ.


Handling. Stream B flags integer-valued numerics with <= 10 distinct values (configurable) and asks for a declared type. It flags character columns where >= 90% (configurable) of non-missing values parse as numbers and lists the tokens that do not parse. It also flags likely sentinel values (e.g. 99, 999, -9) and binary numerics not coded 0/1 or +/-0.5 that appear in interactions. Declared types are fixed in the IR.


Parity. The IR fixes each variable's type, so booleans and integer codes are coded identically in both languages.


Verifier's correction. Logicals are categorical in R (column 'bbTRUE') and in patsy (bb[T.True]) but numeric in formulaic (bb). The coding is the same, but the labels differ. The IR should fix booleans as 2-level categoricals with an explicit reference level, or as 0/1 numerics, as declared.


Verifier's reasoning. The boolean divergence is confirmed: patsy gives bb[T.True] and formulaic gives bb. However, the claim leaves out R. model.matrix.default treats logicals as factors (isF <- is.factor(x) || is.logical(x)) and produces a column named 'bbTRUE'. R therefore agrees with patsy, and formulaic is the outlier. The remaining points, on 1/2 binary coding putting the zero outside the data and on numbers stored as strings, are correct, and the thresholds are presented as configurable heuristics.


Evidence checked. Local copy of r-source stats/R/models.R line 623. Experiment scratchpad/L2adv/a2.py.


### L2-19 Collinearity in LMMs: use term-level GVIF, beware interaction and centring artefacts, separate pre-fit from post-fit

Kind: correction. Stream: both. Priority: valuable. Origin: preliminary (P9). Verdict: correct.


Claim. Per-column VIFs for dummy columns change with coding and reference level (verified: 1.175 with treatment coding and reference a, 1.65 with reference c, same data). The GVIF of the whole term, det(R11)*det(R22)/det(R) (Fox & Monette 1992), does not change with the coding (verified: 1.0301 under treatment, sum, Helmert and any reference). With interactions, the term-wise GVIF of a lower-order term does depend on the centring of the variables it interacts with. The GVIF of factor f in x*f was 37.9 with raw x and 1.08 with mean-centred x (verified). That inflation is non-essential collinearity with the product columns. In an LMM, a pre-fit VIF from X ignores V. A post-fit VIF from the correlation matrix of vcov(beta) = (X'V^-1 X)^-1 differs (verified: 1.07 against 1.27 for a mostly between-cluster predictor) and is the one that reflects SE inflation in the fitted model.


Handling. Stream B reports GVIF and GVIF^(1/(2*df)) per term, computed from X on the analysis sample, either in a main-effects-only version of the model or per predictor (each predictor grouped with all terms that contain it). It flags interaction-induced inflation as a coding or centring artefact and reports scaled condition indices with variance-decomposition proportions to locate dependencies. Use descriptive bands with cited conventions, not hard pass/fail cut-offs. Stream A also reports the post-fit, vcov-based GVIF.


Parity. Exact tier for pre-fit values (deterministic given the IR X) and numerical tolerance for post-fit values.


Verifier's reasoning. The claim was re-verified on a different dataset. Per-column VIFs changed with coding (treatment ref a: 1.217/1.162, ref c: 1.903/2.062, sum: 1.079/1.200, Helmert: 1.071/1.066), while the term GVIF stayed at 1.122 under every coding. For OLS, the vcov-based GVIF equals the X-based one (also 1.122), because det(R11)det(R22)/det(R) is unchanged by matrix inversion and diagonal scaling. In an LMM, the two differ only through the V weighting, which supports separating pre-fit from post-fit. The post-fit version must leave the intercept row and column out of cov2cor(vcov). Fox & Monette (1992), JASA 87(417), 178-183, is the correct reference.


Evidence checked. Experiment scratchpad/L2adv/a6.py (patsy codings, and GVIF from the X correlation matrix vs from the inverse).


### L2-20 The shared grammar must compile to a canonical design IR, and a Python formula library does not define the design

Kind: correction. Stream: infrastructure. Priority: essential. Origin: preliminary (P30). Verdict: correct.


Claim. Translating lme4 syntax into statsmodels arguments through a Python formula library cannot guarantee parity. patsy (no longer under active development according to its README, which names formulaic as successor) and formulaic differ from R and from each other in term ordering (L2-06), coding of terms with missing margins and intercept parentheses (L2-07), level handling after NA deletion and unused categories (L2-04), ordered-factor contrasts (L2-03), scale() ddof (L2-14) and the meaning of operators (L2-08). The shared contract should therefore be a versioned intermediate representation (IR) that each package's own parser produces. It fixes variable types, level lists, reference levels, numeric contrast matrices and the expanded term list in canonical order with an explicit intercept flag. It also fixes transformed columns with their stored constants, random-effects blocks with explicit covariance structure and explicit grouping-factor construction (L2-22), and the analysis-sample definition (L2-21).


Handling. Infrastructure: publish a JSON Schema for the IR next to the check registry. Implement parse(formula, data, spec) -> IR in both languages. Build X and Z from the IR in each package, and either pass the resulting columns to the engine or check the engine's matrices against the IR (same rank and column space, identical values where columns are passed directly). Golden fixtures consist of formula + data + expected IR + expected X, generated from R with attr(X,'assign') and attr(X,'contrasts'). CI fails on any IR mismatch. Syntax outside the documented grammar subset is rejected with an explanatory error.


Parity. The IR defines the exact tier for everything upstream of fitting. Fit-level tolerances apply only after the IR matches.


Verifier's reasoning. The patsy README says the project 'is no longer under active development', that 'no new feature development is planned' and that its 'spiritual successor' is formulaic. Each listed divergence was confirmed in this review: L2-03, L2-04, L2-06, L2-07 and L2-14, plus the larger operator divergence found under L2-08. One implication for the handling is that, if IR-built arrays are passed to statsmodels instead of formulas, the formula metadata for predicting on new data is lost, so prediction must also go through the IR.


Evidence checked. WebFetch of https://raw.githubusercontent.com/pydata/patsy/master/README.md. Experiments scratchpad/L2adv/a1.py, a2.py and a3.py.


### L2-21 Analysis-sample definition and NA-token parity must be owned by the suite

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: correct.


Claim. Unless the suite fixes it, the analysis sample differs between engines. lme4 builds its model frame from fixed and random-effects variables together (sub_specials replaces '|' with '+' before model.frame), so rows with NA in a grouping factor or slope variable are dropped. A Python formula library sees only the formula it is given, so grouping vectors passed separately fall outside its NA handling. Ingestion differs too. pandas.read_csv treats '', 'None', 'NA', 'n/a' and 'null' (among others) as missing by default (verified: 5 of 6 test tokens became NaN). R's read.csv uses na.strings = 'NA', and blank fields count as missing only in logical, integer, numeric and complex columns (read.table docs). In R, a blank in a character column therefore becomes the level ''. Given '', patsy also makes it a level, which becomes the reference level because it sorts first (verified).


Handling. The suite applies listwise deletion once, over the union of all model variables (fixed effects, random slopes, grouping factors, weights, offset), reports the N and groups lost per variable and passes complete data to the engines. Recommend a typed interchange format (Parquet/Arrow with dictionary-encoded categoricals that keep level order, explicit nulls) instead of CSV. Stream B flags '' and NA-like strings kept as factor levels. The data hash in provenance covers the NA-token configuration.


Parity. Exact tier on row inclusion: both packages must produce the same analysis-sample row IDs.


Verifier's reasoning. lFormula calls sub_specials(fr.form., specials = c('|', '||')) to replace bars with '+' before model.frame, so grouping and slope variables share the NA deletion. pandas.read_csv marked 'NA', '', 'n/a', 'None' and 'null' as missing and kept '-'. read.table.Rd states: 'Blank fields are also considered to be missing values in logical, integer, numeric and complex fields.' statsmodels' formula path handles missingness itself, on the raw variables (see L2-17), which gives another reason for the suite to own the deletion step.


Evidence checked. Local copies of lme4 R/modular.R lines 372-374 and r-source utils/man/read.table.Rd lines 125-128. Experiment scratchpad/L2adv/a8.py (pandas 3.1.0).


### L2-22 Building nested and interaction grouping IDs without collisions

Kind: edge_case. Stream: infrastructure. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Expanding nested grouping terms such as (1|school/class) into (1|school) + (1|school:class) needs a combined ID. Plain string concatenation collides: school '1' + class '12' and school '11' + class '2' both give '112' (verified). Even with a ':' separator, labels containing ':' collide ('a:b' + 'c' and 'a' + 'b:c'). R's ':' on factors builds the interaction from level pairs, and reformulas' mkReTrms then removes unobserved combinations (factor(ff, exclude = NA) when drop.unused.levels is set). A Python translation that concatenates strings can therefore silently merge distinct clusters, which changes the number of groups and every variance estimate.


Handling. The IR builds interaction and nested IDs from tuples of integer level codes (or another encoding that cannot collide) and checks that the number of distinct tuples equals the number of distinct combined labels. Group counts per grouping term are reported in both languages as an exact parity check. Lint labels that contain the separator. This relates to P1: once inner IDs are found to be reused across outer units, the interaction ID is built this way.


Parity. Exact tier: per-term group counts and group membership must be identical across languages.


Verifier's correction. lme4 (via reformulas %i%) builds interaction and nested grouping factors by pasting labels with ':', so labels that contain ':' can silently merge clusters in R too. The suite should build the combined grouping factor itself (tuple of codes, mapped to a collision-free label) and pass it to lme4 as a single precomputed variable. Lint or reject ':' in grouping labels.


Verifier's reasoning. The collision of plain string concatenation is trivially true. However, the claim that 'R's ':' builds the interaction from level pairs' is wrong for lme4 2.x. reformulas mkBlist rewrites ':' in the grouping term as %i%, defined as f12 <- paste(f1, f2, sep = ':') followed by factor(f12, levels = ...). The integer codes are used only to order the levels. lme4 itself therefore merges clusters whose labels collide through ':' inside labels. For example, school 'a:b' with class 'c' and school 'a' with class 'b:c' both become 'a:b:c'. This is inferred from the source and was not run in R. A collision-proof tuple encoding in the suite would therefore disagree with lme4 in exactly those cases.


Evidence checked. Local copy of reformulas R/mkReTrms.R lines 185-206 (replaceTerm ':' to %i%, and factor(ff, exclude = NA)) and lines 268-277 (definition of %i% with paste(..., sep = ':')).


## L3 Outcome types, families and GLMM-specific diagnostics


### L3-01 Outcome-type audit from declared support and measurement level, not from the shape of the marginal distribution

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P13). Verdict: partly_correct.


Claim. P13 mixes two things. (a) Support or measurement-level mismatches can be decided before fitting, and they make a family wrong whatever the fit. Examples are a binary outcome (exactly 2 distinct non-missing values), non-negative integers, a score bounded by a known maximum, ordered categories and a strictly positive duration. (b) The shape of the marginal outcome (skew, bimodality, many zeros) is not evidence against a family, because family assumptions apply to y given X and b. A strong binary predictor makes a Gaussian outcome bimodal, and random intercepts make Poisson counts zero-heavy (see L3-09). Engine coverage differs. glmer takes the stats GLM families (binomial, poisson, Gamma, inverse.gaussian, gaussian with a non-identity link), plus glmer.nb. glmmTMB adds nbinom1, nbinom2, nbinom12, betabinomial, beta_family (0<y<1), ordbeta (closed [0,1]), lognormal (y>0), tweedie, compois, genpois, truncated_* families and ziGamma. Since glmmTMB 1.1.15.2 (NEWS entry dated 2026-09-29), it also has an 'ordinal' cumulative-link family.


Handling. Infer the candidate type from storage type plus observed support: distinct-value count, sign, range checked against the declared min/max and an integer test with an explicit tolerance. Read declared metadata from a codebook: measurement level, minimum and maximum possible values, trials column and exposure column. Report inferred type, declared type, any conflict and a family x engine matrix that gives the reason for each candidate and says which engines cannot fit it. Never switch family automatically in confirmatory mode. Do not issue 'non-normal outcome' warnings from marginal skewness or normality tests of y.


Parity. Exact tier. Fix the following identically in both languages: NA handling, the integer tolerance (e.g. |y-round(y)|<1e-8) and distinct-value counting after listwise deletion on the formula variables. Golden fixtures should include integers stored as floats (2.0000000001), logical, string and factor outcomes.


Verifier's correction. Take the type from declared metadata first: measurement level, bounds, trials and exposure. Treat observed support (distinct values, integer test, range) only as a consistency check against that metadata, and tag it as outcome-marginal (T1). A support conflict should rule out families that cannot produce the observed values (for example Poisson for a value of 2.5 or beta_family for y=1) without declaring other families 'wrong'. A binary type should come from a declaration or from a factor or logical with 2 levels, not from the number of distinct values seen. The family list is complete only if it adds t_family, skewnormal, bell, combinomial and truncated_compois.


Verifier's reasoning. The engine-coverage facts match the glmmTMB master sources. The 'ordinal' family is in NEWS 'CHANGES IN VERSION 1.1.15.2 (2026-09-29)'. ordbeta is listed under 1.1.5 (2022-11-16), lognormal under 1.1.8, lognormal-hurdle under 1.1.9 and nbinom12 under 1.1.10. The list leaves out t_family, skewnormal, bell, combinomial and truncated_compois. Separating support from marginal shape is the right idea, but it is overstated in three ways. (1) 'Exactly 2 distinct values' is not a definition of binary. After listwise deletion, a binary outcome can show only 1 value, and a 2-valued variable can be a 2-point ordinal item. (2) A support mismatch does not make a family wrong 'whatever the fit'. A Gaussian model of a bounded score far from its bounds, or of large-mean counts, can be adequate. Non-negative integers that are sums of k items are binomial-with-trials, not counts. (3) Inferring type from observed support reads y and is therefore a T1 check in L3-21's own scheme. In outcome-blind mode, the type has to come from the codebook.


Evidence checked. Downloaded glmmTMB master R/family.R (definitions of ordinal, ordbeta, lognormal, ziGamma, beta_family, nbinom12, bell, combinomial, t_family, skewnormal, truncated_*) and inst/NEWS.Rd (line 79 has 'CHANGES IN VERSION 1.1.15.2 (2026-09-29)' with 'new ordinal family', and the file lists ordbeta under 1.1.5 and lognormal under 1.1.8). Files are in scratchpad/L3adv/dl/.


### L3-02 Which level counts as 'success' in a binary outcome is engine-dependent, and a mismatch flips every coefficient's sign

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: correct.


Claim. In R, a binomial glm/glmer with a factor response treats the first level as failure and all other levels as success. Levels sort alphabetically by default, so for acc in {'correct','incorrect'}, R models P(incorrect). A statsmodels formula with a string outcome models P(first level) = P('correct'). In the empirical check, the statsmodels coefficient was +1.096, identical to explicit 0/1 coding of 'correct'. The same data therefore give opposite-signed coefficients in the two languages. A numeric 1/2 coding stops R's binomial family with 'y values must be 0 <= y <= 1'. A proportion outcome given without weights produces only the warning 'non-integer #successes in a binomial glm!'.


Handling. Shared preprocessing converts every binary outcome to 0/1 using an explicitly declared event level. If none is declared, the suite refuses non-0/1 outcomes, or warns and states its choice. Every report prints 'modelled event: P(acc == "correct")'. Stream B flags 1/2 coding, logical outcomes, factors with more than 2 levels passed to binomial (R pools all non-first levels into 'success') and proportion outcomes that have no trials column.


Parity. Exact tier. The event-level mapping is part of the shared spec. A golden fixture with a string outcome whose alphabetical order puts the event first must give the same sign in R and Python.


Verifier's reasoning. Verified. glm.Rd says the first factor level denotes failure and all others success. R's binomial initialize stops with 'y values must be 0 <= y <= 1' and warns 'non-integer #successes in a %s glm!'. glmmTMB does the same for factor responses (pmin(as.numeric(yobs)-1,1)). In statsmodels, smf.glm with a string outcome modelled P(first level). For acc in {'correct','incorrect'}, the coefficients were identical to the 0/1 coding of 'correct' (0.248, 0.817). Renaming the levels so that 'a_incorrect' sorts first flipped both signs. Two points are missing. smf.logit refuses a string outcome outright (ValueError: endog has 2 columns). In glmmTMB, weights given with a factor response act as log-likelihood multipliers, not trial counts (see L3-16).


Evidence checked. r-source stats/man/glm.Rd line 143 and stats/R/family.R lines 308 and 312. glmmTMB.R lines 371-389. Experiment: scratchpad/L3adv/scripts/a1.py (statsmodels 0.15.0).


### L3-03 Detect separation by linear programming on the fixed-effects model matrix, not by looking for all-0/all-1 cells

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P14). Verdict: partly_correct.


Claim. An all-0 or all-1 cell is neither necessary nor sufficient for separation. It is not necessary: a continuous predictor can separate y completely while the cond x y crosstab has no empty cell. In the empirical check, the Konis-type LP objective was 64.0 against 0 for a non-separated control. It is not sufficient: an all-1 cell in an A x B design is quasi-separation only if the model contains the A:B interaction. With the same data, the LP objective was 17 with the interaction and 0 for the additive model. The MLE has an infinite component if and only if the data are completely or quasi-completely separated (Albert & Anderson 1984). Separation depends only on the column space of X, so it is invariant to the choice of contrasts. In a GLMM, separation in X still makes the fixed effects diverge, and random effects do not prevent it. Along the separating direction, the conditional likelihood does not decrease for any b, so neither does the integrated likelihood. All-0 or all-1 clusters (separation in Z only) do not make beta diverge, but they inflate random-effect variance estimates and leave cluster-specific slopes driven by shrinkage alone.


Handling. In Stream B, and in Stream A before fitting, run the LP check (as in detectseparation) on the exact X after listwise deletion, for binomial-type families and each binary threshold of an ordinal outcome. Report a verdict (none, quasi, complete), the separating direction and which columns and observations are affected. Separately, report clusters with no outcome variation (L3-20). After fitting, screen for |beta| above a configurable size on the logit scale (e.g. >10) or an SE that is huge relative to beta. Offer preregistrable remedies: merge sparse levels, drop the interaction or use penalised/Bayesian estimation with weakly informative priors on the fixed effects. Never remedy silently. The check uses the y-X association, so in confirmatory mode it must be a declared contingency (L3-21).


Parity. Exact tier for the verdict, which is deterministic and contrast-invariant. The separating direction and boundary set are not unique under quasi-separation, so test only the verdict across languages. Script: scratchpad/L3/scripts/t2.py


Verifier's correction. For binomial families, run the LP on the post-deletion X. For cumulative-link models, use a separation check on the ordinal likelihood itself (for example the stacked cumulative design with shared beta) or a post-fit screen for diverging beta and thresholds. Report per-split separation only as a sparsity warning, not as a verdict. Add a check for the RE variance: when a large share of clusters have no outcome variation, warn that the RE SD may be extremely large or unbounded, and report the share of constant clusters next to it.


Verifier's reasoning. The fixed-effects part is right. The Albert & Anderson existence condition, the invariance of the verdict to contrasts (only the column space of X matters) and the argument that a separating direction in X keeps the integrated GLMM likelihood non-decreasing are sound. Two parts are wrong or incomplete. (1) Running the LP on each binary split of an ordinal outcome is the wrong criterion for a proportional-odds model, because beta is shared across splits. In my test, split 1 (Y<=1) was quasi-separated by x: a binary GLM gave b=-23.9 with SE 16913. Yet the cumulative-logit MLE was finite (b=1.238, SE 0.363, the same with BFGS and Newton). Per-split separation is therefore not sufficient for divergence in a proportional-odds model. (2) 'Separation in Z only does not make estimates diverge' needs a limit. With a random-intercept logit, 30 clusters of 10 trials and fine-grid exact integration, the profile log-likelihood peaked near SD=10 on the logit scale when 20 of 30 clusters were constant. With 30 of 30 constant, it kept rising as the SD grew. The RE variance can sit at an infinite boundary, not merely be 'inflated'.


Evidence checked. Script scratchpad/L3adv/scripts/a4.py (statsmodels OrderedModel against a binary GLM on split 1). Script scratchpad/L3adv/scripts/a6.py (profile log-likelihood over RE SD for 30, 25, 20 and 10 constant clusters out of 30).


### L3-04 Hauck-Donner effect: Wald z-tests from glmer summaries are non-monotone near separation

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In binomial models, the Wald statistic shrinks towards 0 as the estimate moves further from the null (Hauck & Donner 1977). In an empirical 2x2 check with 60 per group and group 0 at 30/60 successes, Wald z peaked at 4.56 with 3-4 failures in group 1 and fell to 4.49 with 5 failures. At complete separation, it was 0.00 (p=0.999, SE=16913), and the LRT gave chi2=51.8 (p=6e-13). glmer summaries print Wald z p-values, so a separated or near-separated effect can be reported as 'non-significant' because it is huge.


Handling. For binomial, binomial-with-trials, Poisson and ordinal fits, flag terms whose SE/|beta| or |beta| exceed configurable limits, or that the LP check marks. For flagged terms, compute LRTs (drop-one refits) or profile-likelihood intervals and print them next to the Wald results with an explicit note. Never print a Wald p close to 1 for a flagged term without the warning.


Parity. LRT statistics fall in the numerical-tolerance tier when both engines use the same approximation. Wald SEs near the boundary are engine-specific, so do not test them across languages. Script: scratchpad/L3/scripts/t1.py


Verifier's correction. The Wald statistic is non-monotone in the distance from the null. Beyond a tipping point, it decreases towards 0, and at separation the SE reflects the optimiser's stopping point. For flagged terms, report the LRT and, where they exist, profile intervals, with one-sided infinite bounds stated explicitly. Do not treat the Wald SE or p as meaningful near the boundary.


Verifier's reasoning. The numbers reproduced exactly in statsmodels GLM. By number of failures in group 1, Wald z was 4.557 at 3, 4.563 at 4, 4.493 at 5 and 0.001 at 0 failures (complete separation, SE 16913.4, b 24.57). The LRT at separation was 51.78. The mechanism is overstated, though. The Wald statistic first grows with distance from the null and falls only past a tipping point, so it does not 'shrink as the estimate moves further' throughout. Hauck & Donner (1977), JASA 72(360), is confirmed as the source of the effect. Under separation, profile intervals are unbounded on one side, and the reported Wald SE is an artefact of where the optimiser stopped.


Evidence checked. Script scratchpad/L3adv/scripts/a1.py (2x2, 60 per group). WebSearch confirmed the Hauck & Donner 1977 JASA 72(360) record and the VGAM hdeff documentation.


### L3-05 Residual types for GLMMs: P21's 'robust, so no formal tests' argument applies to Gaussian LMMs only

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P21). Verdict: partly_correct.


Claim. P21's robustness argument concerns Gaussian residual distributions. In Poisson and binomial-with-trials GLMMs, the mean-variance relation is a model assumption, and violating it (overdispersion) makes SEs anticonservative. Dispersion and zero-count checks therefore deserve formal, simulation-based tests in GLMMs. Pearson and deviance residuals are poor visual diagnostics for discrete data. For Bernoulli rows, they take exactly 2 values for each fitted value (two bands). For Poisson with mean between 0.2 and 2, Pearson residuals had skewness 1.12 in the empirical check. Randomised quantile residuals (Dunn & Smyth 1996) are exactly U(0,1) under the true model, even for discrete y. On 20,000 Poisson draws, KS p was 0.13 and the SD of the normal-scale residuals was 1.008. The deterministic mid-PIT (F(y-1)+F(y))/2 is not uniform (variance 0.0714 against 1/12=0.0833, KS p ~ 1e-97), so it cannot replace randomisation in uniformity tests or QQ plots.


Handling. Give each family a default residual type in the registry. Gaussian: conditional and marginal raw/standardised residuals. Discrete and bounded families: randomised quantile residuals plus binned average residuals against fitted values for Bernoulli data. Label the residual type and conditioning level on every plot. Keep P21's 'no default normality test' for Gaussian LMMs. For GLMMs, run uniformity, dispersion and zero tests on quantile residuals by default, reported as diagnostics rather than pass/fail tests.


Parity. Pearson and deviance residuals are deterministic given the fitted values and fall in the numerical-tolerance tier. For randomised quantile residuals, see L3-06. Script: scratchpad/L3/scripts/t2.py


Verifier's correction. Keep randomised quantile residuals as the default for visual checks on discrete outcomes. Describe them as approximately uniform under a correctly specified model. When residuals are conditional on BLUPs and clusters are small, expect apparent underdispersion and non-uniformity. Report formal tests as descriptive, with effect sizes (dispersion ratio, observed/expected zeros), not as pass/fail tests. When exact null calibration matters, calibrate them by a parametric bootstrap that refits and re-predicts the REs. Tag them as T2 (L3-21).


Verifier's reasoning. The mid-PIT result holds. Its variance depends on the mean (0.0625 at lambda=0.5, 0.0745 at 1 and 0.0832 at 20). For lambda uniform on 0.2-2, the variance was 0.0709 with KS p ~ 1e-82. The claim that randomised quantile residuals are 'exactly U(0,1) under the true model' holds only at the true parameters and the true b. Dunn & Smyth themselves say 'apart from sampling variability in the estimated parameters'. In a GLMM, conditional residuals use estimated RE modes. In my test (Poisson, clusters of 4, true beta and sigma, b set to its conditional mode), the randomised quantile residuals had variance 0.0712 instead of 0.0833 and KS p = 0.001, with a conditional Pearson ratio of 0.67. At the true b, the same residuals were uniform (KS p 0.72). Formal uniformity and dispersion tests run on conditional residuals by default therefore have a non-uniform null when clusters are small. With large n, they also reject trivially, which invites outcome-dependent model switching.


Evidence checked. Script scratchpad/L3adv/scripts/a2.py. WebSearch confirmed the Dunn & Smyth (1996) abstract wording ('exactly normal, apart from sampling variability in the estimated parameters').


### L3-06 Quantile residuals: conditional vs unconditional simulation, a closed-form conditional PIT and injectable uniforms for cross-language parity

Kind: architecture. Stream: infrastructure. Priority: valuable. Origin: preliminary (P23). Verdict: partly_correct.


Claim. Simulated quantile residuals in a GLMM depend on which levels are re-simulated. Since DHARMa 0.5.0, simulateResiduals defaults to simulation conditional on all fitted random effects (n = 250 simulations). Its documentation says conditional simulation is usually more sensitive for dispersion tests and can hide misfit absorbed by the REs. Unconditional simulation tests the whole structure but has less power and induces correlated residuals. In the conditional case, the predictive distribution of y_i is the family distribution at mu_hat_i (with offset and dispersion), so the PIT interval [F(y_i-1), F(y_i)] has a closed form. No Monte Carlo is needed, so the 1/n_sim granularity disappears and only the uniform jitter is random. This weakens P35: if the API accepts a user-supplied vector of jitter uniforms, conditional quantile residuals agree across languages to floating-point tolerance. Unconditional simulation can also be made reproducible by inverse-CDF draws (qnorm for b, then the family quantile function for y) from injected uniforms.


Handling. The fitted-model contract (P32) must expose the family CDF and quantile functions at mu_hat (including dispersion and offsets), the mixture CDF for zero-inflated or hurdle components, Ĝ per grouping factor for drawing b, and a simulate(level) method. Compute conditional PIT intervals in closed form for families with closed-form CDFs in both languages (binomial, Poisson, NB1/NB2, beta, Gamma, lognormal). Fall back to simulation for compois, tweedie and similar families. Support aggregation of residuals to cluster level. Record the conditioning choice and n_sim in the results JSON.


Parity. Golden tests inject identical uniforms, which puts both conditional and unconditional residuals in the numerical-tolerance tier. Discrete quantile functions can differ by one count when a uniform falls within floating-point error of a CDF jump, so tests should allow a tiny fraction of off-by-one draws. Without injected uniforms, test in distribution only (P35).


Verifier's correction. Closed-form conditional PITs with injected uniforms give cross-language parity between the two new packages, but comparisons with DHARMa are distribution-tier only. Unconditional reproducibility also needs a fixed Cholesky factor, a fixed order of RE draws and identical quantile-function tie handling. State in the report that conditional residuals check only the observation level and are not exactly uniform under the null when clusters are small.


Verifier's reasoning. The DHARMa facts are confirmed. NEWS 0.5.0 says the default changed to conditional simulation. The vignette says 'As of DHARMa 0.5.0, the default is conditional simulation on all random effects', and simulateResiduals has the signature n = 250, simulateREs = c('conditional', ...). The vignette's table supports the sensitivity and absorption trade-off and says conditional simulation is recommended for dispersion tests. The closed-form PIT given mu_hat is correct in principle and removes the Monte Carlo error. It is not identical to DHARMa's output, which uses the empirical CDF of 250 simulations, so parity with DHARMa itself can only be distributional. Conditional PITs are also not uniform under the null with small clusters (see L3-05). The 'induces correlated residuals' point is documented in the vignette only for residual covariance structures, although within-cluster dependence in unconditional residuals follows from the same logic. The contract also needs RE terms in dispformula and ziformula (which glmmTMB allows) to be conditioned on.


Evidence checked. DHARMa master NEWS.md (line 37), vignettes/DHARMa.Rmd (lines 249-271 and 398) and R/simulateResiduals.R (line 43), downloaded to scratchpad/L3adv/dl/.


### L3-07 Dispersion checks: meaningful for Poisson and binomial with more than one trial, structurally uninformative for Bernoulli rows

Kind: feature. Stream: A. Priority: essential. Origin: new. Verdict: correct.


Claim. A single Bernoulli trial with mean p must have variance p(1-p). Observation-level overdispersion of 0/1 rows is therefore impossible, and the Pearson ratio stays near 1 whatever the cluster-level misfit. In the empirical check (200 clusters x 10 trials with unmodelled cluster heterogeneity, SD 1 on the logit scale), the aggregated-binomial Pearson chi2/df was 2.47 against 1.006 for the same data as Bernoulli rows. For Poisson and binomial-with-trials GLMMs, the Pearson ratio is only approximate. Residual df are ill-defined with random effects (conventions differ on whether to subtract the covariance parameters), and the chi-square reference is poor when expected counts are small. Underdispersion (e.g. counts with an implicit upper bound) is also possible.


Handling. Suppress the dispersion statistic for Bernoulli rows and say why. Instead, offer residuals aggregated by cluster or by cluster x design cell, as DHARMa recommends for 0/1 data. For Poisson, binomial with trials and NB, report the Pearson ratio with its df convention stated, plus a simulation-based dispersion test (conditional simulation, see L3-06), and flag both over- and underdispersion. List the candidate remedies with their caveats: NB1/NB2, beta-binomial and OLRE (see L3-08).


Parity. Fix the Pearson ratio's df convention in the shared spec so that the ratio falls in the numerical-tolerance tier. Simulation p-values fall in the distribution tier unless uniforms are injected. Script: scratchpad/L3/scripts/t1.py


Verifier's correction. Add, as a minor point, that aggregated residuals reveal misfit only along groupings that are related to it, so the aggregation key should be prespecified (cluster, or cluster x design cell).


Verifier's reasoning. The result reproduced. With 200 clusters of 10 trials and logit-scale heterogeneity SD 1, the aggregated Pearson chi2/df was 2.60, against 1.001 for the same data as Bernoulli rows. The DHARMa vignette says that 0/1 responses show no dispersion problem under misfit and that grouping residuals (which turns 0/1 into k/n) reveals it. It adds that aggregation shows misfit only if the grouping correlates with the misfit. The remaining caveats (ill-defined df, poor chi-square reference with small expected counts, possible underdispersion) are standard and accurate.


Evidence checked. Script scratchpad/L3adv/scripts/a2.py. DHARMa.Rmd lines 787-855.


### L3-08 Observation-level random effects: not identifiable for Bernoulli rows, change what the intercept means and invalidate conditional Pearson checks

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. (a) With one Bernoulli trial per row, an OLRE changes only the marginal link: P(y=1)=E[expit(eta+e)] is another monotone function of eta. Its variance is not separately identified from the scale of beta, so (1|obs) on 0/1 rows is meaningless. On aggregated binomial rows, an OLRE equals a cell-level RE in the disaggregated data. (b) In a Poisson-lognormal OLRE model, the marginal mean count is exp(beta0 + sigma^2/2), not exp(beta0). In the empirical check, mean(y)=3.70, exp(beta0)=2.72 and exp(beta0+sigma^2/2)=3.74. (c) Pearson residuals computed conditional on the OLRE modes are strongly underdispersed (ratio 0.30 with the true parameters, against 4.77 when the OLRE is ignored). The conditional Pearson ratio therefore cannot show that an OLRE 'fixed' overdispersion. (d) According to Harrison (2014, 2015), OLRE do not reduce bias in zero-inflated counts and give biased intercepts and slopes when overdispersion is beta-binomial generated. Both OLRE and beta-binomial models perform poorly with fewer than 5 levels of the random intercept.


Handling. Detect OLRE terms: a grouping factor with as many levels as rows, or one level per aggregated row. Refuse or warn for Bernoulli rows. Label marginal versus median-type predictions and add the sigma^2/2 term where appropriate. Run post-OLRE dispersion checks with the OLRE re-simulated. Suggest comparing with NB (counts) or beta-binomial (proportions with trials) and report both sets of estimates.


Parity. OLRE fits are engine-specific (Laplace on n-dimensional random effects). Test the marginal-mean transformation exactly. Script: scratchpad/L3/scripts/t2.py


Verifier's correction. For 0/1 rows, an OLRE is exactly unidentified under probit. Under logit, it is practically unidentified, because it is identified only through the shape of the link, which data barely inform. Refuse it, or warn and report it as non-estimable. All other parts stand.


Verifier's reasoning. (a) is overstated. With a probit link, an OLRE on 0/1 rows is exactly unidentified, since E[Phi(eta+sZ)] = Phi(eta/sqrt(1+s^2)) (verified numerically). With a logit link, it is only nearly unidentified. Over eta in [-4,4], the marginal link differs from the best rescaled logit by at most 0.004 (s=1) and 0.006 (s=2), so s is identified only weakly, through the shape of the link. The practical conclusion (do not fit it) stands. (b) is correct algebra. (c) is consistent with my conditional-residual test, which showed underdispersion with true parameters. (d) The Harrison papers were confirmed via WebSearch summaries of the abstracts (peerj.com is not reachable from this session). Harrison 2014 found that OLRE fail to reduce bias in zero-inflated data. Harrison 2015 found that OLRE give biased slopes and intercepts under beta-binomial overdispersion and that both models do poorly with fewer than 5 RE levels, 'particularly for variance components'. Both are ecology simulation studies.


Evidence checked. Script scratchpad/L3adv/scripts/a4.py (link-shape fit and probit identity). WebSearch results for Harrison 2014 and 2015 (UCL Discovery abstract records).


### L3-09 Many zeros do not mean zero inflation, and pre-fit zero-excess checks against a marginal Poisson are invalid with clustering

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Random intercepts and covariates produce more zeros than a Poisson with the overall mean predicts. In an empirical check (Poisson GLMM, 100 clusters x 20, random-intercept SD 1.2, no zero inflation), the observed zero share was 0.396. A Poisson at the marginal mean (1.45) predicted 0.234, and the true model's expected zero share was 0.394. Overdispersion (NB) produces the same effect. Warton (2005) found that a negative binomial without zero inflation fitted best across many zero-heavy datasets. Zero inflation can be judged only against the fitted model: compare the observed zero count with its distribution under simulation from the fitted model (DHARMa testZeroInflation), after dispersion has been addressed. A zero-inflation or hurdle component should have a substantive rationale: structural zeros, such as pupils who never attempt an item. Hurdle models treat all zeros as one process (glmmTMB truncated_* or ziGamma with ziformula), whereas zero-inflated models mix two sources of zeros. glmmTMB beta_family with ziformula allows y=0 but never y=1.


Handling. Stream B must not warn 'zero inflation' from raw zero shares. It reports the zero share overall and per cluster, plus whether exposure varies. Stream A runs the simulation-based zero test only after the dispersion check, reports observed zeros against the simulated distribution and states that a zero-inflation component is a modelling decision requiring rationale. Residuals for zero-inflated or hurdle fits use the mixture CDF.


Parity. The zero test is simulation-based: distribution tier, or tolerance tier with injected uniforms. Script: scratchpad/L3/scripts/t1.py


Verifier's correction. Do not run dispersion and zero tests in sequence. Prespecify a small candidate set (e.g. Poisson, NB2, ZINB or hurdle when there is a substantive rationale for structural zeros), report the zero and dispersion diagnostics for each candidate and log any data-driven switch under L3-21. For hurdle models, list lognormal and beta_family with ziformula alongside the truncated families and ziGamma.


Verifier's reasoning. The core point holds. A Poisson GLMM without zero inflation had an observed zero share of 0.505, against 0.249 from a Poisson at the marginal mean and about 0.47 expected under the model. Warton (2005) is confirmed (negative binomial without zero inflation fitted best), but that study was of multivariate abundance data, not GLMMs. In glmmTMB, beta_family with a ziformula allows 0 <= y < 1 (source), and hurdle = truncated family or ziGamma or lognormal plus ziformula. The weak point is the order 'zero test only after dispersion has been addressed'. The DHARMa vignette notes that zero inflation looks like overdispersion in standard residual plots. Fixing dispersion first (switching to NB) can absorb or mask structural zeros, and switching on the basis of the test results is outcome-dependent.


Evidence checked. Script scratchpad/L3adv/scripts/a2.py. glmmTMB family.R (beta_family initialize: 'y values must be 0 <= y < 1' when ziformula is given). DHARMa.Rmd line 421. WebSearch for the Warton 2005 abstract.


### L3-10 Aggregated binomial vs Bernoulli rows: identical estimates but non-comparable log-likelihoods, residual df and dispersion statistics

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: correct.


Claim. The same data as (successes, trials) rows or as 0/1 rows give identical beta (empirically identical to 6 decimals). The log-likelihoods differ by exactly sum log C(m_i, k_i), which was 234.1751 in the check (logLik -84.95 against -319.12). Deviance (42.6 vs 638.2) and residual df (48 vs 498) differ too. AIC, BIC, logLik, deviance and Pearson dispersion are therefore not comparable across representations. In a GLMM, the equivalence holds only when every random effect is at or above the aggregation level and no predictor varies within an aggregated row. Trial-level (item) covariates or item random effects prevent aggregation. R accepts cbind(k, n-k) or k/n with weights=n, and glmmTMB documents both forms. Rows with n=0 must be removed, because DHARMa refuses models with zero-weight binomial rows.


Handling. Store a canonical representation (successes, trials, an aggregation key) in the shared spec. Validate integer k, integer n >= 1 and 0 <= k <= n, and drop and report rows with n=0. Report the representation used. Block information-criterion comparisons between models fitted in different representations. In Stream B, suggest aggregation when the design allows it (it gives faster fits and makes dispersion checks possible), and say when it is impossible.


Parity. Exact tier for preprocessing. The shared spec fixes whether logLik includes the binomial coefficient (choose to include it). Python must implement the same constant so that cross-language logLik and AIC agree within tolerance. Script: scratchpad/L3/scripts/t1.py


Verifier's reasoning. Verified. In statsmodels, the aggregated minus Bernoulli log-likelihood equalled sum log C(m,k) exactly (844.1289 both ways), so statsmodels includes the binomial constant. R's binomial aic uses dbinom(round(m*y), round(m), mu, log=TRUE), so it includes the constant too. glmmTMB documents both prob ~ ..., weights=N and cbind(successes, failures). DHARMa stops with an error asking users to remove zero-weight binomial observations (n=0). The conditions for GLMM equivalence are correct: under Laplace, the conditional likelihood differs only by a constant, so estimates match.


Evidence checked. Script scratchpad/L3adv/scripts/a2.py. r-source family.R line 359. glmmTMB.R line 1263. DHARMa simulateResiduals.R line 74.


### L3-11 Bounded and proportion outcomes: binomial when a denominator exists, beta only for the open interval and ordered beta for exact 0s and 1s

Kind: feature. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. (a) A proportion of k correct out of n countable items carries a known denominator. Binomial or beta-binomial with trials uses it, whereas beta and Gaussian models on k/n discard it. Warton & Hui (2011) recommend logistic regression for binomial data and advise against the arcsine transform, as does Jaeger (2008) for accuracy data. (b) glmmTMB beta_family rejects y outside 0<y<1. With a ziformula, y=0 is allowed but y=1 never is. (c) The Smithson & Verkuilen squeeze (y(N-1)+0.5)/N depends on the sample size N. Estimates therefore change with N, and Stream B subsets and the full-data refit transform differently. glmmTMB's ordbeta family (since 1.1.5) handles the closed interval [0,1] (Kubinec 2023). (d) For slider, VAS (0-100) and percentage scales, the bounds must be declared. Bounds estimated from the observed min/max are outcome-dependent and wrong when nobody reaches the bound.


Handling. Detect values in [0,1] or within the declared bounds, a candidate denominator column and counts of exact boundary values. Recommend binomial or beta-binomial when a denominator exists, beta when all values are interior and ordbeta or zero/one-inflated beta when boundary values are present. If the squeeze is applied, record N and warn that the transform depends on N. Rescale to [0,1] using the declared bounds only.


Parity. Exact tier for detection and for the squeeze, which must use the same post-deletion N in both languages.


Verifier's correction. Recommend binomial with an observation- or person-level RE, or beta-binomial, when a denominator exists. Use beta only for interior continuous proportions without a denominator. Use ordbeta for exact 0s and 1s. Point out that one-inflation is not available through glmmTMB beta_family. Tag the boundary counts as T1.


Verifier's reasoning. (b) is confirmed in the source ('y values must be 0 < y < 1' without zi, 0 <= y < 1 with zi). (c) The squeeze formula is the standard Smithson & Verkuilen one, and its dependence on N is right. ordbeta is listed under glmmTMB 1.1.5, and the documentation notes it does not rescale automatically. Two gaps remain. First, zero/one-inflated beta is not available in glmmTMB (beta_family with zi allows only 0), so the recommendation needs an engine qualifier. Second, recommending a plain binomial whenever a denominator exists is anticonservative when there is unmodelled person- or item-level heterogeneity. In my simulation (additive on the logit scale with person noise SD 0.5, n trials = 20), a binomial GLM without REs rejected a null A:B interaction 11.5% of the time at alpha .05. Also, detecting values in [0,1] and counting boundary values read y (T1).


Evidence checked. glmmTMB family.R (beta_family, ordbeta docs) and the NEWS.Rd 1.1.5 section. Simulation scratchpad/L3adv/scripts/a7.py.


### L3-12 Ceiling and floor effects in test scores create scale-dependent ('removable') interactions and compress variance

Kind: edge_case. Stream: B. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Near a bound, additive effects on the latent (logit) scale become interactions on the raw or proportion scale. In the simulation (2x2 design, 20-item scores, no interaction on the logit scale), OLS on proportions gave A:B = -0.058 (p=2e-5), while a binomial GLM gave A:B = 0.12 (p=0.52). The share at ceiling ranged from 4% to 58% across cells. Such non-crossover interactions depend on the scale and do not support unambiguous claims about latent processes (Wagenmakers et al. 2012). A mass at the bound also compresses within-cluster and between-cluster variance and makes residuals heteroscedastic. In measurement research, more than 15% of respondents at the lowest or highest score is a common criterion for floor or ceiling effects (Terwee et al. 2007). That is a criterion for instrument quality, not a modelling rule.


Handling. From declared min/max possible scores, report the share at each bound overall, per design cell and per cluster, with a configurable threshold (default 15%, citing its origin). When item-level data exist, recommend a crossed person x item binomial GLMM (explanatory IRT, De Boeck et al. 2011). Otherwise, recommend binomial with trials or an ordinal or ordered-beta model. When an interaction is tested on a bounded scale, report it on both scales and add a removable-interaction warning.


Parity. Exact tier for the boundary shares. Script: scratchpad/L3/scripts/t2.py


Verifier's correction. Report boundary shares overall and per cluster as T1, and per-cell shares as T2. Compare the interaction on both scales using models that account for clustering (binomial GLMM with person and item REs, or beta-binomial), and add a removable-interaction note.


Verifier's reasoning. The result reproduced qualitatively. With logit-additive effects near the ceiling, OLS on proportions rejected A:B in 95% of 200 replicates. The Terwee et al. (2007) >15% floor/ceiling criterion is confirmed via reproductions of their criteria table. There are three problems. (1) The binomial comparator was a GLM that ignores person-level heterogeneity, which is anticonservative (11.5% rejection at nominal 5% in my run). The comparator should be a GLMM or beta-binomial. (2) The logit scale is also a choice, and the absence of an interaction there is not privileged. The point is that the interaction is removable and therefore not interpretable as a claim about latent processes. (3) Boundary shares per design cell condition y on X, so under L3-21's own definitions they are outcome-associational (T2), not outcome-marginal.


Evidence checked. Simulation scratchpad/L3adv/scripts/a7.py. WebSearch for the Terwee 15% criterion (secondary reproductions of the table).


### L3-13 Ordinal and Likert outcomes: detect them, recommend cumulative-link GLMMs and fix the cutpoint sign convention

Kind: feature. Stream: both. Priority: essential. Origin: preliminary (P13). Verdict: partly_correct.


Claim. Liddell & Kruschke (2018) show that metric models on ordinal data produce false alarms, misses and inversions of effect direction, including for interactions and trends, and that averaging several ordinal items does not fix this. Bürkner & Vuorre (2019) cover cumulative, sequential and adjacent-category alternatives. lme4 has no ordinal family. glmmTMB 1.1.15.2 added an 'ordinal' family with cumulative-link proportional odds, a logit link by default, the response as an ordered factor or 1-based integer codes and K-1 thresholds. Its documentation says the REML correction is 'unsettled' (allowed, with a warning) and that the variance is 'not well-defined' for this family. ordinal::clmm is the established R alternative. Sparse or empty categories within design cells cause threshold or separation problems for individual cumulative splits. Implementations write the linear predictor either as theta_k - x'beta or as theta_k + x'beta, so coefficient signs are not portable.


Handling. Detect ordered factors, and integer outcomes with few consecutive values that are declared Likert. Distinguish single items from multi-item means and sums, and send sums of dichotomous items to binomial (L3-11). Report category frequencies overall and per cell, flag empty or sparse categories and run the separation LP on each binary split. Recommend a cumulative-link GLMM and say which engines support it. After fitting, report latent-scale R²/ICC only (L3-19) and offer a proportional-odds check.


Parity. The shared spec fixes the sign convention and threshold parameterisation. A golden fixture with a known positive effect must give a positive coefficient in both languages.


Verifier's correction. Replace the per-split LP with a check on the cumulative-link likelihood, or with a post-fit divergence screen of beta and thresholds. Keep per-split and per-cell category sparsity as descriptive warnings. Fix the theta_k - x'beta convention in the spec. glmmTMB reports thresholds on the threshold scale, but vcov and profile use the internal psi scale.


Verifier's reasoning. The engine facts are confirmed in glmmTMB family.R. The ordinal response may be an ordered factor 'or 1-based integer category codes'. The default link is logit, with probit and cloglog available. There are K-1 thresholds (softmax-parameterised internally). REML is 'unsettled; it is allowed but warns', and the source issues warning('variance is not well-defined for the ordinal family'). The linear predictor enters as theta_j - eta. statsmodels OrderedModel also uses F(cut_k - x beta), so the two target engines already agree on sign. The Liddell & Kruschke claims, including that averaging items does not help, were confirmed via the abstract. The flaw is in the handling: 'run the separation LP on each binary split' is the wrong criterion for a proportional-odds model (see L3-03). In my test, per-split quasi-separation coexisted with a finite cumulative-logit MLE.


Evidence checked. glmmTMB family.R lines 152 and 526-545. statsmodels ordinal_model.py lines 50-60. Script scratchpad/L3adv/scripts/a4.py. WebSearch for the Liddell & Kruschke abstract.


### L3-14 Response times: positivity, deadline censoring (MNAR), trimming provenance and which estimand each RT model targets

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: correct.


Claim. (a) Log, Gamma, inverse-Gaussian and lognormal models need y > 0, and glmmTMB lognormal rejects y <= 0 unless a ziformula is given. (b) RTs capped at a response deadline are right-censored. Dropping timeouts makes missingness depend on the unobserved RT (MNAR), so P12's 'likelihood handles missing outcomes under MAR' does not apply. Restricting analysis to correct trials conditions on a second outcome. (c) Models differ in what they estimate. lmer(log RT) gives additive effects on mean log RT, which are multiplicative on the raw scale. A Gamma or inverse-Gaussian GLMM with identity link targets additive effects on mean RT (Lo & Andrews 2015). glmmTMB's lognormal family is parameterised by mean and SD on the data scale (sdlog^2 = log(1+(sd/mu)^2) in the source). With a constant dispersion, it therefore assumes constant raw-scale SD, whereas lmer(log y) assumes a constant coefficient of variation. They are different models, not reparameterisations. (d) Interactions are scale-dependent (L3-12).


Handling. Check for y <= 0, for heaping at the maximum or at a declared deadline and for implausibly fast responses below a configurable bound. Also check the share of timeouts per participant and cell and whether timeouts are missing. Record as provenance every trimming or exclusion rule and the rows removed per cluster and cell. For each candidate model, state the estimand: log-scale effect, mean-RT effect or median-type back-transformation. Warn when timeouts were dropped (MNAR) and when RT analyses are conditioned on accuracy.


Parity. Exact tier for the checks and exclusion counts. Back-transformations must use identical formulas in both languages.


Verifier's correction. As a minor point, state in the estimand label that, with a log link, glmmTMB lognormal effects are multiplicative on the mean, whereas lmer(log y) effects are multiplicative on the median (geometric mean).


Verifier's reasoning. The software claims are confirmed. glmmTMB lognormal stops with 'y values must be > 0 (may be =0 if ziformula is specified)'. The cpp source parameterises by data-scale mean and SD, with log-scale variance = log(1+(sd/mu)^2). Phi is therefore the raw-scale SD, and a constant phi implies a varying CV, unlike lmer(log y). R's Gamma family stops on non-positive values. The censoring/MNAR argument and the point about conditioning on accuracy are standard and correct. I confirmed Lo & Andrews (2015) as a Frontiers paper advocating GLMMs on raw RTs over transformation, but I did not verify its identity-link Gamma/IG specifics, since the search results did not show them.


Evidence checked. glmmTMB family.R lognormal(). glmmTMB.cpp lines 1213-1225. r-source family.R line 478. WebSearch for Lo & Andrews.


### L3-15 Offsets and exposure: detect them, validate them and carry them through simulation and residuals

Kind: feature. Stream: both. Priority: valuable. Origin: new. Verdict: correct.


Claim. Counts whose opportunity varies (minutes observed, words read, attempts made) need log(exposure) as an offset in a log-link model. If the count is bounded by the number of opportunities (k correct of n attempted), it is binomial with trials, not a Poisson rate. glmer adds offset() terms in the formula and the offset= argument together ('their sum is used'), so giving the same offset both ways doubles it. In statsmodels GLM, the exposure= argument is logged internally. In the empirical check, exposure=e reproduced offset=log(e) exactly, while passing exposure=log(e) moved the intercept from 0.22 to 1.48. Zero exposure gives log(0) = -Inf. Simulated or quantile residuals computed without the offset are wrong.


Handling. In Stream B, flag count outcomes with a candidate exposure or denominator column. Validate exposure > 0 with no missing values, and report how much exposure varies within and between clusters. Choose rate vs binomial by whether k <= n is structural. The shared spec holds a single offset representation (variable plus transform) that the formula parser translates. Detect duplicated offsets. Stream A passes the offset into every prediction, simulation and residual computation. An optional exploratory check fits log(exposure) as a covariate (its coefficient should be about 1 under the rate model). This check is outcome-dependent and must be labelled as such.


Parity. Exact tier for the offset vector fed to the engines. A golden test with varying exposure checks that both languages yield the same linear predictor. Script: scratchpad/L3/scripts/t2.py


Verifier's correction. Add that a mistaken exposure=log(e) shifts the intercept and can also fail outright when e < 1.


Verifier's reasoning. glmer.Rd line 85 says of the offset: 'if more than one is specified their sum is used'. In statsmodels GLM Poisson, offset=log(e) and exposure=e gave identical estimates (0.195, 0.495). Passing exposure=log(e) moved the intercept to 1.256. When any e < 1, it fails outright, because log of a negative value gives NaN ('NaN, inf or invalid value detected in endog'). The rate-versus-binomial distinction and the log(exposure)-as-covariate check are sound.


Evidence checked. lme4 man/glmer.Rd line 85. Scripts scratchpad/L3adv/scripts/a2.py and a3.py.


### L3-16 Weights mean different things in each engine and family, and sampling weights are not prior weights

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. lme4 weights are precision weights: Var(y|b) = sigma^2 W^{-1}. Rescaling them leaves beta, SEs and RE variances unchanged and rescales only sigma. In R binomial models, weights give the number of trials when the response is a proportion. In glmmTMB, binomial-type weights are sizes. For every other family, the source multiplies each observation's log-likelihood by w_i (tmp_loglik *= weights(i)), and weights are 'not automatically scaled to have sum 1'. For a Gaussian model, multiplier logL = precision logL + ((n - sum w)/2) log(2 pi phi^2) + const, so lmer and glmmTMB agree only if mean(w) = 1. In a numerical random-intercept check with mean(w) = 1, both gave b1 = 0.583. With mean(w) = 3, the precision version kept b1 = 0.583 (SE 0.065, tau 0.615). The multiplier version gave b1 = 0.573, SE 0.034 and tau 0.672, as if there were sum(w) observations. Survey or sampling weights (PISA, TIMSS) are neither. Single-level weights in lme4 or glmmTMB do not give design-consistent multilevel estimates, which need level-specific weights and pseudo-likelihood (Rabe-Hesketh & Skrondal 2006). The WeMix vignette notes that lme4's weights are precision, not sample, weights.


Handling. Require a declared weight semantics: precision, frequency, trials or sampling. Refuse sampling weights for the lme4 and glmmTMB adapters, or point to dedicated methods. Warn when glmmTMB non-binomial weights do not average 1. Offer a rescaling-invariance check (refit with 2w). Show the weight semantics in the report.


Parity. The Python adapter must implement the declared semantics explicitly. A golden fixture with mean(w) not equal to 1 catches silent semantic mismatches. Script: scratchpad/L3/scripts/t5.py


Verifier's correction. Say that lmer weights are precision weights (invariant to rescaling apart from sigma). glmer weights are prior weights: trials for proportion responses, and log-likelihood multipliers for Poisson and similar families, where rescaling changes SEs. glmmTMB weights are trials only for a numeric binomial response. Otherwise, they multiply the log-likelihood, including for factor and cbind binomial responses. Golden fixtures should cover each of these cases.


Verifier's reasoning. The algebra for a Gaussian model with multiplier weights versus precision weights is correct: the difference is ((n - sum w)/2) log(2 pi sigma^2) + const, so the two agree iff sum w = n. The glmmTMB source does tmp_loglik *= weights(i), and the documentation says 'Not automatically scaled to have sum 1'. The claim overgeneralises in two ways. (1) The statement that lme4 weights are precision weights, whose rescaling leaves beta and SEs unchanged, holds for lmer only. In glmer, prior weights for Poisson and similar families multiply the log-likelihood (R's poisson aic is -2*sum(dpois(y,mu,log=TRUE)*wt)), so rescaling changes SEs. (2) In glmmTMB, binomial weights act as sizes only for a numeric (proportion or 0/1) response. For a factor response, size is set to 1, and for cbind(s,f), size = s+f. In both cases, the weights remain log-likelihood multipliers (glmmTMB.R lines 371-389). I did not re-run the numerical b1/SE comparison, and I did not verify the WeMix vignette.


Evidence checked. glmmTMB.cpp line 1306. glmmTMB.R lines 371-389 and 1229. r-source stats/R/family.R line 165. Files in scratchpad/L3adv/dl/.


### L3-17 Laplace-approximation accuracy for binary and ordinal GLMMs with small clusters

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: correct.


Claim. Joe (2008) found that the asymptotic bias of Laplace-approximation estimates is driven mainly by how discrete the response is. It is largest for binary and ordinal outcomes and for counts concentrated near zero, and shrinks as cluster size grows. glmer defaults to nAGQ = 1 (Laplace), and nAGQ = 0 is faster but less exact. Adaptive Gauss-Hermite quadrature (nAGQ > 1) is implemented only for a single scalar random-effects term. glmmTMB integrates random effects with TMB's Laplace approximation and has no quadrature option. A binary GLMM with random slopes or crossed effects therefore cannot be checked against quadrature in either R engine.


Handling. Record the approximation (Laplace, nAGQ value or the Python method) in provenance. For binary, ordinal or low-count outcomes with small median cluster sizes (configurable), flag possible bias in the variance components. When the model has a single scalar RE, offer a refit with nAGQ of about 10-25 and report the changes in beta and the variance components. When it does not, say that no quadrature check is available and suggest an optional simulation-based bias check.


Parity. The same model fitted with different integral approximations belongs in the engine-specific tier. Cross-language GLMM tolerance tests are valid only when both sides use the same approximation, and the results JSON must say which was used.


Verifier's correction. As a minor change, present the flag as advisory and cite Joe's finding that the Laplace approximation is often adequate.


Verifier's reasoning. In glmer.Rd, nAGQ defaults to 1 (Laplace) and nAGQ=0 is 'faster but less exact'. lmer.R line 279 stops with 'nAGQ > 1 is only available for models with a single, scalar random-effects term'. glmmTMB integrates with TMB's Laplace approximation and has no quadrature argument. Joe (2008) is confirmed via its abstract: bias is driven by discreteness, binary and ordinal outcomes are worse than counts, counts concentrated near 0 are worse and bias shrinks with cluster size. The abstract also says the Laplace approximation is often adequate even for small clusters, so the flag should stay advisory.


Evidence checked. lme4 man/glmer.Rd lines 58-66 and 124-127. lme4 R/lmer.R line 279. WebSearch for the Joe 2008 abstract.


### L3-18 Label GLMM coefficients as cluster-specific and compute population-averaged effects by quadrature

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. With a non-identity link, GLMM fixed effects are subject-specific (conditional on b) and differ from population-averaged effects (Zeger, Liang & Albert 1988). For logit, a common approximation is beta_PA ≈ beta/sqrt(1 + c^2 sigma^2) with c = 16 sqrt(3)/(15 pi) ≈ 0.588. A numerical check by Gauss-Hermite integration gave an attenuation of 0.83 at sigma = 1 (approximation 0.86) and 0.61 at sigma = 2 (approximation 0.65), so the approximation understates attenuation. For log link with random intercepts only, the marginal mean is exp(eta + sigma^2/2), so slopes are unchanged and only the intercept shifts. With random slopes, sigma^2 depends on x and slopes change too. Education and psychology readers often take GLMM odds ratios as population effects.


Handling. Label coefficients and odds or rate ratios 'conditional on random effects = 0' in reports. Optionally output marginalised predictions and contrasts computed by deterministic Gauss-Hermite integration over the estimated RE distribution, rather than by simulation, and state the integration settings.


Parity. Quadrature is deterministic, so marginal effects fall in the numerical-tolerance tier given the same estimates and number of nodes. Script: scratchpad/L3/scripts/t3.py


Verifier's correction. Population-averaged logit effects depend on the covariate distribution and on where in the distribution of eta they are evaluated. Report marginal contrasts by quadrature averaged over the observed covariate values, not a single attenuation factor. With crossed or multiple REs, integrate over the summed RE variance at each prediction point.


Verifier's reasoning. c = 16 sqrt(3)/(15 pi) is about 0.588, and the log-link statements are right. But the attenuation of a logit GLMM is not a single number, because the marginal model is not exactly logistic. By Gauss-Hermite integration (80 nodes), the local attenuation of the logit slope was 0.826 (sigma=1) and 0.606 (sigma=2) at eta=0. At eta=3, it was 0.927 and 0.691, where the approximation (0.862, 0.648) overstates attenuation. A least-squares fit over eta in [-3,3] gave 0.852 and 0.624. The approximation understates attenuation only near the centre.


Evidence checked. Script scratchpad/L3adv/scripts/a3.py.


### L3-19 GLMM R² and ICC depend on a choice of distribution-specific variance that must be recorded

Kind: correction. Stream: A. Priority: valuable. Origin: preliminary (P28). Verdict: correct.


Claim. For non-Gaussian GLMMs, Nakagawa-type R² and ICC need a distribution-specific (observation-level) variance. Logit uses π²/3 and probit uses 1, both on the latent scale. For Poisson with log link, the delta method gives 1/λ and the lognormal approximation ln(1+1/λ), and there is also a trigamma method. These diverge when λ is small: at λ = 0.5, the first two give 2 and 1.10. With sigma²_f = 0.3 and sigma²_u = 0.5, marginal R² is then 0.107 (delta) or 0.158 (lognormal). R packages differ in default and in how λ is estimated, so one bare 'R²' value is not reproducible. Latent-scale ICCs for binary or ordinal outcomes differ from observed-scale ICCs. Harrison (2014) found that ignoring overdispersion inflates r².


Handling. The results JSON stores the method, the λ estimator, the latent or observed scale and every variance component. Reports print the method next to each R² and ICC. For ordinal and other families where the variance is not well-defined, report latent-scale quantities only. Do not report R² without a warning for a model that failed its dispersion check.


Parity. Exact tier once the method and inputs are fixed. Both packages implement the same formula from the shared spec and do not delegate to package defaults.


Verifier's correction. Add the trigamma value (4.93 at lambda=0.5, giving marginal R2 = 0.052) to show the range across methods.


Verifier's reasoning. The arithmetic is correct: 1/lambda = 2 and ln(1+1/lambda) = 1.0986 at lambda=0.5, giving marginal R2 of 0.107 and 0.158. The trigamma value is 4.935, giving 0.052, so the spread is even wider than stated. The MuMIn documentation lists the delta, lognormal and trigamma methods and says 'Trigamma-estimate is recommended whenever available'. A WebSearch summary of Harrison (2014)'s abstract says ignoring overdispersion can lead to overestimated r2 / predictive power.


Evidence checked. Script scratchpad/L3adv/scripts/a4.py. cran/MuMIn man/r.squaredGLMM.Rd lines 75-80.


### L3-20 How much information a binary outcome carries: minority events per cluster and per cell, and clusters with no outcome variation

Kind: feature. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. For Bernoulli data, information about within-cluster effects grows with the number of minority-class events, not with N. A participant at 100% accuracy (common in psycholinguistic and education accuracy data) contributes almost nothing to their own random slope, whose estimate is driven by shrinkage and the assumed RE distribution. Many such clusters push the random-intercept variance up and favour singular fits. Cells with few events give unstable interaction estimates even short of separation.


Handling. Report, overall and per cluster, the number of trials, the minority-class count and whether the outcome is constant. Report the fraction of clusters with no outcome variation and the counts of events and non-events per design cell. Report the minority events per fixed-effect parameter as an index only, without a hard rule. Link these to random-slope advice by flagging by-cluster slopes when most clusters have little or no variation. Suggest aggregating to binomial with trials where the design allows (L3-10). These checks read y but not y-X associations, so classify them as outcome-marginal (L3-21).


Parity. Exact tier.


Verifier's correction. Report per-cluster trial and minority counts and the share of constant clusters as T1, and per-cell event counts as T2. Warn that many constant clusters can push the RE intercept SD to very large or unbounded values. Treat 'singular fit' as a possible consequence for slopes and correlations, not a demonstrated one.


Verifier's reasoning. That constant clusters contribute little to their own slopes and inflate intercept variance is consistent with my experiment. With 20 of 30 clusters constant (10 trials each), the profile maximum was at an RE SD of about 10 on the logit scale. With all clusters constant, it kept rising with SD. But 'favour singular fits' is not demonstrated. The intercept variance moves away from 0, and singularity would come from slope variances or correlations. That remains unverified. 'Information grows with minority events, not N' is a heuristic, and events-per-variable rules are contested. Per-design-cell event counts condition y on X, so under L3-21 they are not outcome-marginal.


Evidence checked. Script scratchpad/L3adv/scripts/a6.py.


### L3-21 Outcome-blind mode cannot run the checks that matter most for GLMMs: split checks into tiers and preregister contingencies

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P17). Verdict: partly_correct.


Claim. P17 overstates what outcome-blind mode delivers for non-Gaussian outcomes. The main GLMM threats (separation, dispersion, zero inflation, boundary mass and per-cluster outcome variation) all need y. Checks should be split into three tiers. T0, design-only (no y): type and support from the codebook, declared bounds, trials and exposure columns, cluster sizes and maximum possible events per cell. T1, outcome-marginal (reads y, not y-X relations): boundary shares, zero shares, event counts and timeouts. T2, outcome-associational (conditions y on X or on a fitted model): separation, dispersion, zero-inflation tests and residual checks. Choosing a family or remedy from a T1 or T2 result is outcome-dependent model selection.


Handling. Tag every check in the registry with its tier. In outcome-blind mode, run T0 checks and emit the T1 and T2 checks as a list of 'deferred checks', each with a preregistrable decision rule. Examples are 'if the separation LP is positive, fit penalised model M2' and 'if the conditional-simulation dispersion test gives p < .01 and the ratio is > 1.5, switch Poisson to NB2'. Stream A logs every rule that is triggered, with the triggering statistic, and always reports the preregistered model next to the adapted one. T1 checks are allowed in confirmatory mode but are logged as data-dependent.


Parity. Tier tags and decision rules are stored in the shared YAML spec (P29), so both packages make the same decision from the same statistics.


Verifier's correction. Define the tiers by what is read. T0 reads no y, T1 reads y marginally or by cluster but not by any fixed-effect predictor, and T2 reads y by X or a fitted model. Move per-cell shares and counts to T2. Base decision rules on effect-size thresholds rather than p-values. Always report the preregistered model next to any adapted one.


Verifier's reasoning. The tier idea is sound, but the reviewer's own items contradict it. Per-cell boundary shares (L3-12), per-cell event counts (L3-20) and type inference from observed support (L3-01) all read y, and the per-cell ones condition y on X. Preregistered decision rules make adaptation transparent but do not remove its data dependence, so inference after selection is still conditional. The example rule 'p < .01 and ratio > 1.5' is also fragile: dispersion p-values are trivially small with large n, and they have a non-uniform null when residuals are conditional on BLUPs (L3-05). Applying rules in sequence (dispersion, then zero inflation) interacts badly (L3-09). P17 is still useful for GLMMs, because design-only checks such as rank deficiency, cluster sizes and maximum possible events per cell matter a great deal.


Evidence checked. Internal consistency check against L3-01, L3-12 and L3-20. Supporting experiments in scratchpad/L3adv/scripts/a2.py (conditional-residual null).


### L3-22 Stream A check registry keyed by engine x family x link x extra components, with a canonical dispersion parameterisation

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Valid post-fit checks depend on the family. Gaussian: P21 residual checks, plus heteroscedasticity via glmmTMB dispformula. Bernoulli: separation, Hauck-Donner screen, binned or quantile residuals, calibration and Laplace-accuracy flag, with no dispersion test. Binomial with trials: adds a dispersion test and a beta-binomial alternative (glmmTMB V = μ(1-μ)(n(φ+n)/(φ+1))). Poisson: dispersion, simulation-based zero test and offset checks. NB: glmer.nb (NB2, θ), glmmTMB nbinom2 (V = μ + μ²/φ) and nbinom1 (V = μ(1+φ)). φ or θ heading to infinity means Poisson is adequate, and nbinom1 vs nbinom2 is a substantive choice of variance function. Gamma and inverse Gaussian: y > 0 and identity-link positivity. Beta and ordbeta: bounds and precision. Ordinal: category sparsity and thresholds. Zero-inflated or hurdle: mixture-CDF residuals. Truncated families: y > 0. Dispersion parameters are not portable across engines. statsmodels' GLM NegativeBinomial family uses V = μ + αμ² (α = 1/θ) and by default fixes α at 1 instead of estimating it. A default Python NB fit is therefore not comparable with glmer.nb or nbinom2.


Handling. Each registry entry declares the applicable (engine, family, link, zi/disp/offset) combinations, the required fitted-model-contract fields (CDF, quantile function, variance function, dispersion, simulate), its tier (T0, T1 or T2, see L3-21) and its parity tier. The results JSON stores dispersion as {variance_function: 'mu+mu^2/k', k, engine_native_name, engine_native_value}. Checks that do not apply to a family are reported as 'not applicable (reason)', never silently skipped.


Parity. A canonical variance-function representation with explicit mappings (θ_glmer.nb = φ_nbinom2 = 1/α_statsmodels) makes dispersion estimates comparable within tolerance. A golden fixture with large θ tests the Poisson-limit flag in both languages.


Verifier's correction. The Poisson limit is phi -> infinity for nbinom2 (theta_glmer.nb = phi_nbinom2 = 1/alpha_NB2) and phi -> 0 for nbinom1. In statsmodels, sm.families.NegativeBinomial fixes alpha (default 1), while discrete NegativeBinomial estimates it (NB2 by default, NB1 via loglike_method). Store the variance function together with the direction of the Poisson limit.


Verifier's reasoning. The glmmTMB variance functions are confirmed in family.R: nbinom2 V = mu + mu^2/phi, nbinom1 V = mu(1+phi) and betabinomial V = mu(1-mu)(n(phi+n)/(phi+1)). The statsmodels GLM NegativeBinomial family has alpha = 1.0 fixed by default (variance(2) = 6), whereas the discrete statsmodels NegativeBinomial model estimates alpha (0.109 in my fit). What 'a default Python NB fit' means therefore depends on which class is used. The statement 'phi or theta heading to infinity means Poisson is adequate' is wrong for nbinom1: the documentation says its Poisson limit is phi = 0 and that phi has opposite meanings in nbinom1 and nbinom2.


Evidence checked. glmmTMB family.R documentation block (nbinom1 note on the meaning of phi). statsmodels 0.15.0 experiment: scratchpad/L3adv/scripts/a3.py.


## L4 Fitting, convergence, singularity and inference


### L4-01 Convergence-warning triage: what lme4 checks, what it now skips and how to classify a warning as a false positive

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P19). Verdict: partly_correct.


Claim. In lme4 2.1-0 (CRAN, 2026-10-23), checkConv() runs in this order. (1) The singularity check runs first: if any bounded parameter lies within getSingTol() = 1e-4 of its bound, the function returns at once and runs no gradient or Hessian check. (2) Derivatives are computed only when nobs < check.conv.nobsmax (1e4) and the number of optimised parameters < check.conv.nparmax (10 for lmerControl, 20 for glmerControl). These skips were introduced in 1.1-38. (3) The gradient test is max_i min(|R^-1 g|_i, |g_i|) > 2e-3, where g and H = R'R are centred finite differences (fixed step 1e-4) of the deviance with respect to theta (LMM), or theta and beta (GLMM, nAGQ > 0). (4) The Hessian tests give 'degenerate Hessian' for any eigenvalue < -1e-6, 'numerically singular' for |eigenvalue| < 1e-6 or a failed Cholesky, 'very large eigenvalue' for max eigenvalue > 1e6 and 'large eigenvalue ratio' for min/max < 1e-6. 'No convergence warning' is therefore no longer evidence that the checks ran for any fit with N >= 10,000, any lmer with >= 10 covariance parameters (e.g. (1+a+b+c|subj) on its own) or any singular fit. A bug makes the warning text 'component %d' always report 1, because the code applies which.max() to a scalar. lme4's ?convergence states that the scaled gradient grows with sample size, so warnings occur for well-behaved large fits. It names allFit as the gold standard and recommends restarting from the optimum or a slightly perturbed one. P19 is therefore correct about large-N false positives but out of date on mechanism and defaults.


Handling. For every fit, record the check status ('performed', or 'skipped: N >= nobsmax / npar >= nparmax / singular', with the threshold values), the raw engine messages and the suite's own diagnostics. The suite computes these diagnostics from the adapter's objective: gradient, scaled gradient H^-1 g, the index of the worst component (computed by the suite, never parsed from the lme4 text) and Hessian eigenvalues. Use Richardson extrapolation or the engine's AD gradient, not the fixed-step 1e-4 difference. Triage has three steps. (a) Restart from the reported optimum with tightened tolerances (nloptwrap xtol_abs = ftol_abs = 1e-8). (b) Refit with several optimisers (allFit with start_from_mle = TRUE in R, an equivalent loop in Python). (c) Declare a false positive only if every successful optimiser agrees within the parity metric of L4-19, i.e. a deviance spread below a configurable delta (suite default, not a published value) and fixed effects differing by less than a small fraction of their SE. Otherwise, report 'unresolved non-convergence' and name the parameter directions that disagree.


Parity. lme4's messages are engine-specific and must not be compared with glmmTMB or Python messages. The suite-computed gradient and Hessian on a declared parameterisation can be compared within tolerance on golden fixtures. The triage outcome category should match exactly on fixtures with a clear-cut answer.


Verifier's correction. Keep the order and the tests, with these changes. Derivatives are computed only if nobs < 1e4 and npar < nparmax. npar is the number of theta parameters for lmer (and for glmer with nAGQ = 0), and theta plus beta for glmer with nAGQ > 0, with nparmax = 10 for lmer and 20 for glmer. glmer with skipped derivatives runs no checkConv at all, so it also emits no singular message. The suite must therefore always run its own singularity check. Setting calc.derivs = TRUE does not re-enable the checks when N > nobsmax unless check.conv.nobsmax is raised too. For triage, restart with tolerances below the 1e-8 defaults (e.g. 1e-10) or with a different optimiser. Run allFit from the default starts and from perturbed starts, not only with start_from_mle = TRUE. Report agreement as 'consistent across optimisers', not as proof of convergence. Name the scaled gradient R^-1 g (as in lme4) or the Newton step H^-1 g, and say which one is used.


Verifier's reasoning. Most of the mechanism agrees with the lme4 2.1-0 source. checkConv() tests singularity first and returns before any derivative test. The skip conditions, the 2e-3 gradient test min(|R^-1 g|,|g|), the four Hessian tests and the which.max(scalar) bug (the warning always says 'component 1') are all as described. deriv12 uses a fixed central-difference step of 1e-4, and ?convergence agrees with the claim about large-N warnings and allFit. Four points are wrong or missing. (i) For glmer, npar = length(rho$lower), and updateGlmerDevfun() puts the beta bounds into rho$lower. The nparmax = 20 limit therefore counts theta plus beta when nAGQ > 0, and a glmer with many fixed effects reaches it easily. (ii) glmer runs `cc <- if (!calc.derivs) NULL else checkConv(...)`, so when the derivatives are skipped (N >= 1e4 or theta+beta >= 20), the singular-fit message is never produced either. For glmer, 'no boundary (singular) message' is therefore not evidence of a non-singular fit. lmer always calls checkConv, so it still emits the singularity message. (iii) Setting calc.derivs = TRUE computes the derivatives, but checkConv still returns NULL if nobs > check.conv.nobsmax. The NEWS describes this as 'calculated (but not checked)'. (iv) The handling step 'tighten nloptwrap to xtol_abs = ftol_abs = 1e-8' tightens nothing: since 1.1-22/23, these are the code defaults (R/utilities.R), even though ?convergence still says 1e-6. The handling has two further problems. allFit(start_from_mle = TRUE) starts every optimiser at the reported optimum, so their agreement is weak evidence (they can all stall on the same flat ridge). The handling also uses H^-1 g where lme4 uses R^-1 g.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/checkConv.R (singular-first return, the nobsmax/nparmax bail-out, which.max(maxmingrad) and checkHess thresholds). Read https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R: lmer and glmer compute calc.derivs as nobs < nobsmax && npar < nparmax with npar = length(rho$lower), glmer has 'cc <- if (!calc.derivs) NULL else checkConv(...)' and optwrap skips deriv12 when singular. Read https://raw.githubusercontent.com/cran/lme4/master/R/modular.R: updateGlmerDevfun sets rho$lower <- c(reTrms$lower, rep(-Inf, p)). Read https://raw.githubusercontent.com/cran/lme4/master/R/lmerControl.R (nparmax 10, glmer 20). Read https://raw.githubusercontent.com/cran/lme4/master/R/utilities.R: nloptwrap defaults xtol_abs = 1e-8, ftol_abs = 1e-8. Read https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd: the 1.1-22 entry says tolerances went from 1e-6 to 1e-8, and the 1.1-38 entry describes the skips. Read https://raw.githubusercontent.com/cran/lme4/master/man/convergence.Rd (stale 1e-6 defaults, allFit 'gold standard').


### L4-02 Engine-independent convergence taxonomy computed from an objective callable in the fitted-model contract

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new (P32). Verdict: partly_correct.


Claim. The engines detect and word convergence problems differently. lme4 uses finite differences of the profiled deviance. glmmTMB uses TMB automatic differentiation and re-checks a non-positive-definite sdreport Hessian with numDeriv::jacobian(obj$gr). It warns 'non-positive-definite Hessian matrix' or 'extreme or very small eigenvalues detected', and passes nlminb messages through (e.g. 'false convergence (8)'). lmerTest adds its own warnings ('Model failed to converge with k negative eigenvalues', 'Model may not have converged with k eigenvalues close to zero'), based on a numDeriv Hessian in a (theta, sigma) parameterisation with tolerance 1e-8. One lme4 fit can therefore carry warnings from two packages that disagree. Under P32, a contract holding only point estimates (y, X, Z, beta, b, variance parameters) cannot support convergence checks, df methods (L4-10), profile CIs (L4-15) or tolerance-based parity (L4-19). All of these need the objective function itself.


Handling. Extend the P32 contract with objective(par), which returns the deviance on a declared criterion (ML or REML), and an optional gradient(par). The extension also adds the parameter vector with lower and upper bounds, its parameterisation (relative Cholesky theta, log-SD, etc.), which parameters are profiled out, the integration method (exact, Laplace, AGQ(n)), the optimiser and its status, and raw messages tagged by source layer. Map everything onto suite codes in the YAML registry (P29), for example CONV.OPTIMIZER_STATUS, CONV.GRADIENT, CONV.HESSIAN_NEGATIVE, CONV.HESSIAN_SINGULAR, CONV.ILL_CONDITIONED, CONV.CHECK_SKIPPED, FIT.BOUNDARY, FIT.NESTED_INCONSISTENT (L4-09). Compute the codes from the suite's own derivatives of objective(), not from parsed messages. In R, the adapter takes the objective from lme4 update(m, devFunOnly = TRUE) / getME(m, 'devfun') and the objective and gradient from glmmTMB m$obj$fn / m$obj$gr. The Python adapter wraps its engine's log-likelihood function.


Parity. This item lets convergence findings be compared across languages. Codes computed from the shared objective on golden fixtures are exact-tier. Engine messages are stored but are engine-specific tier.


Verifier's correction. Keep the contract extension. State that derivative-based codes are tolerance-tier (or decided by threshold with a hysteresis band), not exact-tier. They are comparable across engines only after mapping both parameter vectors into one declared parameterisation and evaluating one reference objective (L4-19). For a parameter like a log-SD going to -infinity, the codes are not comparable at all. Add a cost policy that is recorded when the suite skips its own derivative checks: for example, Hessian by AD where available, otherwise Richardson only below a size limit.


Verifier's reasoning. The engine behaviour is described accurately. glmmTMB re-checks a non-PD sdreport Hessian with numDeriv::jacobian(obj$gr). It issues 'non-positive-definite Hessian matrix' if the Hessian is still bad, and 'extreme or very small eigenvalues detected' (when eigval_check is on and the Hessian is PD). It passes nlminb's fit$message through. lmerTest's as_lmerModLT uses numDeriv::hessian over c(par, sigma) with tol = 1e-8 and issues the two warnings quoted. With lme4 >= 2.0, it differentiates getME(.,'par'), which equals theta only for unstructured covariances. getME(m,'devfun') exists. The architectural argument (point estimates cannot support derivative checks, df methods, profiles or objective-based parity) is sound. The parity claim is overstated, though. Codes such as CONV.ILL_CONDITIONED or CONV.HESSIAN_SINGULAR compare finite-difference or AD eigenvalues against thresholds, so they depend on the parameterisation (theta vs log-SD) and can flip near the threshold. They are exact-tier only when the same suite-implemented objective and parameterisation are evaluated at the same point, not when each engine's own objective is wrapped. The proposal also ignores cost: lme4 skips derivatives above N = 1e4 because they are expensive, and a suite that always differentiates must budget for this.


Evidence checked. Read https://raw.githubusercontent.com/cran/glmmTMB/master/R/glmmTMB.R (lines around the pdHess block: numDeriv::jacobian(obj$gr, par), both warning texts, fit$message pass-through). Read https://raw.githubusercontent.com/cran/lmerTest/master/R/lmer.R (as_lmerModLT: tol = 1e-8, numDeriv::hessian over getVarPar = c(getME(.,'par'), sigma), the two warning strings, Moore-Penrose inverse over eigenvalues > tol). Searched https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R and found 'devfun' among the getME names.


### L4-03 Singular fits: rank deficiency belongs to a linear combination, and 'variance near 0 or correlation near +/-1' is valid only for q <= 2

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P20). Verdict: partly_correct.


Claim. A singular fit is a random-effects covariance block of less than full rank. lme4's isSingular() documentation says that for q >= 3 a model can be singular with no variance near zero and no correlation near +/-1. In a worked example (numpy), a 4x4 covariance with all SDs >= 1 and max |r| = 0.577 has eigenvalues (0, 1, 1, 2.92), so its rank is 3. isSingular() and checkConv() test whether a Cholesky-diagonal theta is < 1e-4. A rank-deficient matrix's Cholesky factor shows its zero at the last term, in model order, of the linearly dependent set. In the example, the diagonal is (1, 1, 1, 0). The term this flags therefore depends on how the terms are ordered, not on which one 'causes' the problem. rePCA() gives the SDs of orthogonal components and the rotation, which identifies the degenerate combination (Bates et al., 2015, arXiv:1506.04967). P20's 'identify the offending component' must be redefined as 'identify the null-space direction and the terms that load on it'.


Handling. For each grouping factor, eigen-decompose the estimated covariance in a scale-free form (see L4-04). Report the number of eigenvalues below a relative threshold, the eigenvector loadings of each near-null direction, the terms with non-negligible loadings and candidate simplifications. The candidates are to drop one loading term, constrain the block to diag() or fit a reduced-rank structure (glmmTMB rr(), or by dropping terms), each with its deviance change after refitting (L4-21). Report correlations near +/-1 and variances near 0 as special cases of the same analysis, never as the only test. As a pre-fit risk indicator (relevant to P4), flag blocks where the number of levels is not much larger than q. The proposed ratio threshold is heuristic.


Parity. The eigen-decomposition is deterministic given the estimates, so it is exact up to floating point. Near-singular estimates differ across engines, however (L4-05, L4-19), so compare the number of near-null directions and the set of loading terms, not the eigenvectors numerically. Eigenvector sign is arbitrary, so normalise it.


Verifier's correction. Define singularity as rank deficiency (the number of near-null directions), which does not depend on coding. Report loadings only together with the coding and centring they refer to, and treat 'which terms load' as specific to that coding. Use isSingular's structure-specific methods for diag, cs and ar1 terms. Treat rePCA output as unit-dependent and do not apply a relative eigenvalue threshold to it directly.


Verifier's reasoning. The core point is right. isSingular.Rd says that for dimension >= 3 a fit can be singular with no variance near 0 and no correlation near +/-1, and that rePCA gives the SDs of orthogonal components and the rotations. I built my own example: x4 = (x1+x2+x3)/sqrt(3) gives SDs of 1, max |r| = 0.577, eigenvalues (0,1,1,2) and Cholesky diagonal (1,1,1,0). Reordering the terms to (x4,x1,x2,x3) moves the zero onto x3, so the flagged term does depend on order. Three things are missing or overstated. (i) In lme4 >= 2.0-1, isSingular is an S3 generic with separate methods for diag, cs and ar1 structures, so 'tests whether a Cholesky-diagonal theta < 1e-4' is accurate only for unstructured terms. (ii) rePCA works on the relative covariance, so its eigenvalues and loadings depend on the predictors' units. I found that rescaling a slope by 1000 changes the min/max eigenvalue ratio from 4.7e-4 to 4.7e-10. (iii) Exact rank is invariant under any non-singular reparameterisation Z -> ZA. Near-null eigenvalues and 'which terms load' are not: they change with centring and contrast coding, and the 'scale-free form' of L4-04 removes the unit effect but not the coding effect.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/man/isSingular.Rd and https://raw.githubusercontent.com/cran/lme4/master/man/rePCA.Rd. Read the 2.0-1 entry ('isSingular() is now an S3 generic ... Covariance.diag/cs/ar1') in https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd. Ran scratchpad/L4adv/scripts/a3_sing.py: eigenvalues (0,1,1,2), Cholesky diagonal (1,1,1,0) in order 1234 and (1,0.82,0.71,0) in order 4123, and eigenvalue ratio 4.7e-4 vs 4.7e-10 after rescaling by 1000.


### L4-04 lme4's singularity tolerance depends on the predictor's units: rescaling a random-slope covariate can create or remove a 'singular' flag

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In LMMs, lme4's theta is the relative Cholesky factor, i.e. the random-effect SD divided by the residual SD. For an intercept-plus-slope term, the slope's diagonal element is sd_slope * sqrt(1 - rho^2) / sigma. The default singular tolerance is an absolute 1e-4 on theta (getSingTol()). The nloptwrap optimiser uses absolute tolerances xtol_abs = 1e-6 on theta. In an example computed from these definitions, a slope SD of 0.05 * sigma per second is theta = 0.05 when the predictor is in seconds. The same model with the predictor in milliseconds has theta = 5e-5 < 1e-4 and produces 'boundary (singular) fit'. The singular flag also skips all derivative checks (L4-01), and the optimiser's absolute xtol is then 2% of the parameter. In GLMMs with no residual scale (binomial, Poisson), theta is on the absolute link scale, so the same 1e-4 means something different again.


Handling. Compute the suite's singularity criterion in scale-free form: the eigenvalues of D Sigma D / sigma^2, where D holds the SDs of the corresponding Z columns, i.e. the variance each random-effect direction contributes on the outcome or link scale. Also compute the minimum eigenvalue of the random-effect correlation matrix. Report lme4's isSingular() result separately as an engine flag. When the two disagree, report 'engine flag likely driven by predictor units' and suggest rescaling (Stream B pre-fit SD check, L4-06).


Parity. The scale-free criterion is the same quantity in both languages and is tolerance-tier. The lme4 flag is engine-specific, and glmmTMB has no equivalent flag (L4-05).


Verifier's correction. xtol_abs is 1e-8 by default. Use D = diag(sqrt(mean(z_j^2))), or better the average variance each eigen-direction induces, mean_i(z_i' v v' z_i) * lambda / sigma^2, and declare the centring the criterion refers to. lme4's autoscale and scale warning ignore random-slope (Z) columns, so the suite's Stream B scale check must cover Z separately.


Verifier's reasoning. The mechanism is right. The slope Cholesky element is sd2*sqrt(1-rho^2)/sigma, getSingTol() is 1e-4 and rescaling seconds to milliseconds divides theta by 1000. My check gave theta22 = 2.2e-2 -> 2.2e-5. A singular flag also skips the derivative checks. Three parts are wrong. (i) nloptwrap's xtol_abs default is 1e-8, not 1e-6, so at theta = 5e-5 the tolerance is 0.02% of the parameter, not 2%. (ii) The proposed criterion D Sigma D / sigma^2 with D = 'SDs of the Z columns' fails for random intercepts: the intercept column is constant, its SD is 0 and the intercept variance vanishes from the criterion. A root-mean-square scale or the induced marginal variance is needed. Even then, the criterion and the correlation-matrix eigenvalues depend on centring the slope covariate (the intercept-slope covariance changes), so the criterion is free of units but not of parameterisation. (iii) lme4's autoscale (>= 1.1-38) does not cure this. It scales only the fixed-effects X columns (all non-intercept columns, dummies included) and leaves Z untouched, and checkScaleX does not inspect Z ('TODO: check scale of Z columns?').


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/utilities.R (getSingTol 1e-4, nloptwrap xtol_abs 1e-8). Read https://raw.githubusercontent.com/cran/lme4/master/R/modular.R: the autoscale block scales X[,-1] only, and the checkScaleX comment says Z is not checked. Arithmetic check in scratchpad/L4adv/scripts/a3_sing.py.


### L4-05 glmmTMB cannot reach the boundary: singular fits show up as huge negative log-SDs, NA/NaN SEs and NA log-likelihoods

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. glmmTMB puts random-effect SDs on the log scale (the first parameters of each term's theta are log-SDs) and correlations on an unconstrained scaled-Cholesky scale. A variance can therefore approach zero only as log-SD goes to -infinity, never exactly. lme4 constrains theta >= 0, can return exactly 0 and, for lmer, tries a restart at the boundary (restart_edge = TRUE, boundary.tol = 1e-5). glmmTMB's troubleshooting vignette lists zero variances, perfectly correlated terms and too few grouping levels as typical causes of 'non-positive-definite Hessian matrix'. It says the warning comes with NaN/NA SEs, and that logLik, AIC and BIC are intentionally set to NA to keep such fits out of model comparison. The negative log-likelihood can still be retrieved via fit$fit$objective or fit$obj$fn().


Handling. The suite's adapter for glmmTMB should read the objective directly for diagnostics but mark the fit FIT.BOUNDARY/CONV.HESSIAN_* and keep it out of IC tables unless the user opts in. It should classify boundary status with the scale-free criterion of L4-04 (e.g. an SD contributing < 1e-4 of sigma^2, or the minimum correlation eigenvalue < threshold) and suggest the reduced model (L4-21). Never report glmmTMB's tiny positive SD and lme4's exact 0 as a substantive difference.


Parity. For singular fixtures, lme4 and glmmTMB are expected to differ on SDs, correlations, SEs and logLik availability. The parity test asserts the same boundary classification and equal deviances within tolerance after both fits are evaluated in a common objective. It does not compare variance-parameter values.


Verifier's correction. Write: glmmTMB fits near the boundary usually, but not always, produce a non-PD Hessian, and logLik/AIC are NA only when pdHess is FALSE. Classify boundary status from the estimates (scale-free criterion), never from NA logLik or from warnings. For lme4, describe restart_edge as 'restart if moving off an exact boundary helps' and boundary.tol as 'snap near-boundary values to the boundary if that lowers the deviance' (lmer and glmer).


Verifier's reasoning. Several parts are confirmed. glmmTMB's unstructured parameterisation (log-SDs followed by scaled-Cholesky correlation parameters, rho = theta/sqrt(1+theta^2)) means it cannot reach SD = 0 or |r| = 1 exactly. The troubleshooting vignette lists zero variances, perfect correlations and too few levels as causes. It says that the warning is 'usually accompanied' by NaN/NA SEs, logLik and AIC, that logLik and AIC are set to NA on purpose and that the value can be retrieved via fit$fit$objective or fit$obj$fn(). Two parts are overstated. First, logLik.glmmTMB returns NA only when sdr$pdHess is FALSE. A near-singular fit whose Hessian passes the PD check (perhaps only with the 'extreme or very small eigenvalues' warning) keeps a finite logLik, so 'singular fits show up as ... NA log-likelihoods' is not reliable. Second, the lme4 mechanisms are mischaracterised. restart_edge (lmer only) restarts when a parameter sits exactly on the bound and stepping inward lowers the deviance. boundary.tol = 1e-5 (check.boundary) snaps parameters within 1e-5 of the bound onto it when that is better, and it runs for glmer too.


Evidence checked. Read https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R (logLik.glmmTMB: val <- if (sdr$pdHess) -objective else NA). Read https://raw.githubusercontent.com/cran/glmmTMB/master/vignettes/troubleshooting.rmd (lines 23-36) and https://raw.githubusercontent.com/cran/glmmTMB/master/vignettes/covstruct.rmd (line 566, parameterisation). Read https://raw.githubusercontent.com/cran/lme4/master/R/modular.R (the optimizeLmer restart_edge block, check.boundary and the optimizeGlmer call to check.boundary when boundary.tol > 0).


### L4-06 Predictor scaling: the mechanism differs between LMMs and GLMMs, and lme4 now has its own rule and autoscaling

Kind: correction. Stream: both. Priority: valuable. Origin: preliminary (P16). Verdict: partly_correct.


Claim. lme4's checkScaleX() warns 'Some predictor variables are on very different scales' when, among fixed-effect columns that are not purely 0/1 (the intercept and dummies are excluded), any pairwise ratio of column SDs is > 1e3, or any column SD is > 1e3 or < 1e-3. Since 1.1-38, [g]lmerControl(autoscale = TRUE) scales continuous covariates internally and reports results on the original scale. glmmTMB's diagnose() flags predictors with SD < 1e-3 or > 1e3 (big_sd_log10 = 3). The mechanism differs by model type. In lmer, beta is profiled out and the nonlinear optimiser sees only theta. Fixed-effect scaling therefore matters mainly through the conditioning of X and through random-slope theta magnitudes relative to absolute tolerances (L4-04). In glmer with nAGQ > 0, beta is part of the outer optimisation, and checkConv() also checks the beta block of the Hessian, so scaling acts directly. Rescaling leaves the ML log-likelihood unchanged but shifts the REML log-likelihood (L4-07).


Handling. In Stream B (pre-fit), compute SDs of the non-binary X and Z columns, apply the same 1e3 rule as a registry check and recommend centring/scaling. In Stream A, if the suite refits on scaled predictors, back-transform estimates, SEs and random-slope SDs, store the scaling constants in provenance and state that ML comparisons are unaffected while REML logLik changes by a known constant. Warn that centring is not innocuous under diag() or '||' covariance structures (L4-16): shifting a slope covariate changes the implied intercept variance and intercept-slope covariance, so it changes the model.


Parity. The pre-fit scale check is deterministic on the data and therefore exact-tier. Back-transformed estimates are tolerance-tier.


Verifier's correction. Write: lme4's autoscale standardises all non-intercept fixed-effect columns (including dummies) and back-transforms, but it does not rescale random-slope columns. For glmer, the scale of beta enters checkConv only through the joint (theta, beta) gradient and Hessian. The separate beta-block check appears to be dead code in 2.1-0 (an inference from reading the source, to be confirmed by a test in R).


Verifier's reasoning. checkScaleX is as described: it skips columns that are entirely 0/1 and warns when |log(SD ratio)| or |log SD| exceeds log(1e3). glmmTMB diagnose() uses big_sd_log10 = 3. The LMM point (beta profiled out, so fixed-only rescaling does not change the theta optimisation, and ML is invariant) is right. Two parts are wrong. (i) autoscale does not scale only 'continuous covariates'. The code applies scale() to every non-intercept column of X, 0/1 dummies and interaction columns included, and never touches Z. Its message wording also differs from the silent-rescale option of checkScaleX. (ii) From the source, the 'fixed-effect Hessian' block check in checkConv appears unreachable for glmer with nAGQ > 0. checkConv sets ntheta <- length(lbound), and glmer passes lbound = rho$lower, which already includes the beta bounds. As a result, length(coefs) > ntheta is never TRUE. The full (theta, beta) Hessian is still checked, so scaling still acts on the GLMM checks, but not through a separate beta-block test. The centring warning for diag()/'||' is correct.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/modular.R (checkScaleX, the autoscale block 'X_scaled <- scale(X[, -1])' and updateGlmerDevfun lower bounds). Read https://raw.githubusercontent.com/cran/lme4/master/R/checkConv.R (ntheta <- length(lbound) and if (length(coefs) > ntheta)). Read https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R (glmer passes lbound = rho$lower). Read https://raw.githubusercontent.com/cran/glmmTMB/master/man/diagnose.Rd.


### L4-07 REML vs ML: which comparisons need ML, why REML log-likelihoods depend on how X is parameterised and how the engines' defaults differ

Kind: edge_case. Stream: A. Priority: essential. Origin: new. Verdict: correct.


Claim. (a) The REML criterion contains log|X' V^-1 X|. If X becomes XA for a non-singular A (rescaling, a different contrast coding, reordering), the REML log-likelihood shifts by -log|det A| while the REML estimates stay the same. In an empirical check (statsmodels 0.15.0), multiplying one covariate by 1000 changed the REML llf by -6.907755 = -log(1000) and left the ML llf and the variance estimates identical. REML log-likelihoods and AICs are therefore comparable only between models with identical X, and across engines only when X is parameterised identically (contrasts, P10) and the same constants are used. (b) LRTs or ICs between models that differ in fixed effects require ML. lme4's anova.merMod refits REML fits with ML by default (refit = TRUE, with a message), including when only random effects differ. glmmTMB's anova stops with 'Can't compare REML fits with different fixed-effect components' under the default ddf = 'asymptotic'. (c) The defaults differ: lmer fits with REML = TRUE, whereas glmmTMB() defaults to REML = FALSE. glmmTMB documents that REML = TRUE for Gaussian responses matches lme4::lmer. (d) Kenward-Roger needs REML. pbkrtest silently refits an ML model with REML, while glmmTMB (1.1.15) throws an error.


Handling. Store the estimation criterion as an explicit field of every fit and pin it in Stream A specifications. Do not inherit engine defaults. Run ML refits for fixed-effect LRTs and ICs, and report that a refit was made. For random-effect LRTs with identical X, offer REML (preferred) or ML, and state which was used. Refuse to tabulate REML logLik or AIC across models whose X differ, even when the column space is the same. Report final estimates from REML by default for LMMs, given the small-sample bias of ML variance components with few clusters (Elff et al. 2021, who recommend REML and t-based inference with appropriate df).


Parity. Cross-engine parity on REML logLik requires an identical X and identical normalising constants. Prefer comparing ML deviances, or differences in REML deviance between models with identical X, where the constant cancels. Parity fixtures must set the criterion explicitly in both languages.


Verifier's correction. Add two points. glmmTMB's REML-comparison guard checks term labels only, not X, so the suite must compare the model matrices itself. lme4's ML refits in anova come with no convergence or singularity check.


Verifier's reasoning. (a) follows from REML containing log|X'V^-1X|: replacing X by XA shifts the REML log-likelihood by -log|det A|. lme4's REML deviance includes ldRX2, so it inherits this. (b) Confirmed: anovaLmer has refit = TRUE, prints 'refitting model(s) with ML (instead of REML)' and refits whenever any model is REML. glmmTMB's CompareFixef stops with the quoted message under ddf = 'asymptotic'. CompareFixef compares only sorted term labels, so REML fits with the same labels but different contrasts pass without complaint. This supports the proposed refusal rule. (c) Confirmed from glmmTMB.Rd (REML = FALSE, and 'REML=TRUE for Gaussian responses matches lme4::lmer'). (d) Confirmed: pbkrtest calls update(object, REML = TRUE) without a message (this is documented in the KRmodcomp help), and glmmTMB 1.1.15 NEWS says KR on a non-REML fit now errors. Elff et al. (2021) do recommend REML plus t with appropriate df. One addition: lme4's refitML() uses bobyqa and does not call checkConv, so the ML refits behind anova are never diagnosed (see L4-08).


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R (anovaLmer and refitML.merMod, which has no checkConv call). Read https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R (CompareFixef), https://raw.githubusercontent.com/cran/glmmTMB/master/man/glmmTMB.Rd, https://raw.githubusercontent.com/cran/glmmTMB/master/inst/NEWS.Rd (1.1.15 KR error), https://raw.githubusercontent.com/cran/pbkrtest/master/R/KR_vcovAdj.R (lines 82-83) and https://raw.githubusercontent.com/cran/pbkrtest/master/R/KR_modcomp.R. A web search of the Elff et al. abstract confirms 'REML ... and a t-distribution with appropriate degrees of freedom'.


### L4-08 ML refits are singular more often than the REML fit the user saw: every refit behind an inference must be re-diagnosed

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: correct.


Claim. ML variance estimates are shrunk towards the boundary relative to REML. For a balanced one-way random-intercept model with K = 6 clusters of n = 5, P(sigma_b^2 hat = 0) has an exact closed form via the F distribution. It is 0.251 for ML vs 0.187 for REML under sigma_b^2/sigma_e^2 = 0.25, 0.439 vs 0.348 under 0.10 and 0.661 vs 0.561 under the null. A REML fit that passes every check can therefore have a singular or non-converged ML refit inside anova(). The same applies to every other hidden refit: allFit, profile, parametric-bootstrap replicates (L4-13) and cluster-deletion refits (P24).


Handling. Apply the convergence and singularity classification (L4-01 to L4-05) to every refit the suite or engine performs for an inferential output. Attach the result to that output, e.g. 'LRT based on ML refits, reduced model singular'. For bootstrap, deletion and allFit runs, report counts of failed, singular and non-converged refits.


Parity. Classification counts on fixtures are tolerance-tier: boundary cases may flip at the margin across engines.


Verifier's correction. Treat a singular ML refit as information attached to the LRT, not as an error. Add: lme4's internal ML refits are not convergence-checked by lme4 itself.


Verifier's reasoning. I reproduced the closed-form probabilities independently. For the balanced one-way model, ML is zero iff F <= K/(K-1) and REML is zero iff F <= 1, with F ~ (1+n*lambda) F(K-1, K(n-1)). For K = 6 and n = 5, this gives 0.251/0.187, 0.439/0.348 and 0.661/0.561. The source adds support for the handling: lme4's refitML() (used by anova) re-optimises with bobyqa and never calls checkConv, so a singular or poorly converged ML refit produces no lme4 message. The statement 'ML is shrunk towards the boundary relative to REML' holds exactly in this balanced case and typically elsewhere, but it is not a general theorem for every sample in unbalanced or multi-component models. A singular ML refit also does not by itself invalidate the LRT, because the boundary MLE is legitimate. The flag should therefore be informational.


Evidence checked. Ran scratchpad/L4adv/scripts/a1_oneway.py, which reproduces 0.251/0.187, 0.439/0.348 and 0.661/0.561. Read refitML.merMod in https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R (optwrap with bobyqa, no checkConv).


### L4-09 Negative LRT statistics are silently set to zero by both R engines' anova methods

Kind: edge_case. Stream: A. Priority: essential. Origin: new. Verdict: correct.


Claim. anova.merMod (lme4 2.1-0) and anova.glmmTMB (glmmTMB 1.1.15) both order models by number of parameters and compute Chisq = 2 * pmax(0, diff(logLik)). For nested models, a larger model whose log-likelihood is below the smaller model's has not reached its optimum (or the models are not nested). This case is reported as Chisq = 0 and p = 1, with no warning.


Handling. The suite computes the raw difference, delta = logLik_large - logLik_small. If delta < -tol (tol tied to the optimiser's ftol, e.g. 1e-4 on the log-likelihood scale), emit FIT.NESTED_INCONSISTENT. Then refit the larger model starting from the smaller model's estimates, extended with zero variances or covariances and zero coefficients for the added terms. This start reproduces the smaller model's fit, so the refit cannot end lower. Also check that nesting holds and that nobs are identical.


Parity. The logic is exact in both languages. The Python side must not copy the truncation.


Verifier's correction. In the restart rule, specify a log-SD of about -10 for glmmTMB and a small positive theta for lme4 (to avoid starting exactly on the bound). Handle models with equal npar (Df = 0, p NA) as non-nested.


Verifier's reasoning. Confirmed in both engines. lme4's anovaLmer orders models by the df attribute and computes chisq <- 2 * pmax(0, c(NA_real_, diff(llk))). anova.glmmTMB orders by Df and computes chisq <- 2 * pmax(0, c(NA, diff(llk))) under ddf = 'asymptotic'. Neither warns, and pchisq(0, df, lower.tail = FALSE) = 1. lme4 already stops when nobs differ or when the data or subset objects differ. Implementation notes for the handling: in glmmTMB, a zero variance cannot be represented, so the 'extended start' needs a very negative log-SD and correlation parameters of 0. bobyqa in optwrap replaces an all-zero start with 0.001, which slightly breaks 'reproduces the smaller fit exactly'. Monotone optimisers (BOBYQA, Nelder-Mead) return the best point found, so the refit's deviance cannot exceed the start's.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R (anovaLmer) and https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R (anova.glmmTMB, line ~1539).


### L4-10 Denominator df for fixed effects: method-specific behaviour, SE adjustment, engine defaults and computational limits

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P26). Verdict: partly_correct.


Claim. Luke (2017, Behavior Research Methods 49:1494-1502) found treating t as z somewhat anticonservative, especially in smaller samples. In the same study, Kenward-Roger and Satterthwaite gave acceptable Type I error even for smaller samples, closest to .05 with REML fits. P26 omits six points. (1) KR (Kenward & Roger 1997, Biometrics 53:983-997) changes both the df and the covariance matrix of beta. It uses an adjusted covariance estimator with smaller small-sample bias, and it reproduces exact F tests where they exist. KR SEs therefore differ from model SEs. Satterthwaite in lmerTest uses the unadjusted vcov(beta). (2) KR is defined for REML-fitted LMMs (see L4-07). pbkrtest's vcovAdj inverts the dense N x N marginal covariance, which its documentation calls 'relatively slow'. One such matrix needs 8N^2 bytes (3.2 GB at N = 20,000). (3) lmerTest's Satterthwaite takes a numDeriv Hessian of the REML or ML deviance in (theta, sigma). It inverts it with a Moore-Penrose pseudo-inverse that drops eigenvalues <= 1e-8 (with a warning), so directions at the boundary are silently treated as known (L4-11). (4) Engine defaults differ. lme4 prints t without p-values. glmmTMB's summary defaults to ddf = 'asymptotic' (z statistics). Since 1.1.13, glmmTMB has experimental KR/Satterthwaite, and 1.1.15 switched Satterthwaite to a 'faster, slightly less accurate' approximation. Both methods warn for non-Gaussian families. (5) For GLMMs with fixed dispersion (binomial, Poisson), no df correction is established, and the inference is asymptotic z or a parametric bootstrap. (6) Elff et al. (2021) support REML combined with t-based inference with appropriate df for few clusters.


Handling. For each fixed effect, report the estimate, the SE (flagged when KR-adjusted), the df method, the df and the number of levels of the grouping factor at which the predictor varies, taken from P2's within/between classification. By default, use Satterthwaite for LMMs, with KR optional and refused or warned above a configurable N (memory estimate 8N^2 bytes shown). For GLMMs, the default is z with a 'few clusters' warning when the relevant number of levels is small (threshold heuristic and configurable), plus an offer of a parametric-bootstrap LRT (L4-13). Compute p-values in the suite from the declared method, never by taking over an engine's default.


Parity. Satterthwaite and KR are approximations computed differently across implementations: lmerTest uses numDeriv in (theta, sigma), glmmTMB its own approximation in log-SD space, and Python needs its own implementation from the contract's objective (L4-02). Expect tolerance-tier agreement at interior optima only (e.g. relative df difference < 1e-2). At or near the boundary, agreement is engine-specific (L4-11).


Verifier's correction. Give the memory estimate for KR via pbkrtest as about (n_varpar + 2) x 8N^2 bytes. For GLMMs, offer the between-within (design-based) df of L4-11 as an option alongside z and the parametric bootstrap, citing Li & Redden (2015), instead of saying no correction is established. Declare the df method before fitting, not after seeing the p-values.


Verifier's reasoning. Several parts are confirmed. Luke (2017) found t-as-z somewhat anticonservative in smaller samples, and KR or Satterthwaite with REML closest to .05. lmerTest uses the unadjusted vcov(model), a numDeriv Hessian over (par, sigma) and a pseudo-inverse with tol 1e-8. glmmTMB summary defaults to ddf = 'asymptotic'. Experimental KR/Satterthwaite arrived in 1.1.13, and 1.1.15 has the 'faster, slightly less accurate' Satterthwaite and the non-Gaussian warnings. The memory figure is understated. pbkrtest's vcovAdj forms SigmaInv = chol2inv(chol(Sigma)), a dense N x N matrix, plus a dense G_i %*% SigmaInv for every variance parameter. Peak memory is therefore about (number of variance parameters + 2) x 8N^2 bytes, not 8N^2. Point (5) is overstated. Li & Redden (2015) compared DDF methods for binary GLMMs in small cluster-randomised trials and recommend the between-within method, which kept nominal Type I error with as few as 10 clusters. Satterthwaite and KR were conservative. A design-based df for fixed-dispersion GLMMs therefore has published support.


Evidence checked. Read https://raw.githubusercontent.com/cran/pbkrtest/master/R/KR_vcovAdj.R (lines 112-134), https://raw.githubusercontent.com/cran/lmerTest/master/R/lmer.R, https://raw.githubusercontent.com/cran/glmmTMB/master/R/glmmTMB.R (summary.glmmTMB ddf default) and https://raw.githubusercontent.com/cran/glmmTMB/master/inst/NEWS.Rd. A web search of the Luke abstract (https://read.qxmd.com/read/27620283/evaluating-significance-in-linear-mixed-effects-models-in-r) confirmed its findings. Li P, Redden DT (2015), BMC Med Res Methodol 15:38, https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4458010/.


### L4-11 Satterthwaite df jump at a singular fit: cluster-level effects get residual df

Kind: edge_case. Stream: A. Priority: essential. Origin: new. Verdict: correct.


Claim. In lme4's parameterisation, V = sigma^2 (Z Lambda Lambda' Z' + I). For a scalar random intercept, the deviance and Cov(beta hat) are even functions of theta, so their derivatives with respect to theta vanish at theta = 0. The Satterthwaite denominator g' A g then contains only the uncertainty in sigma, and df = N - p. A numerical check used a Python reimplementation of the lmerTest-style computation (REML deviance Hessian in (theta, sigma), pseudo-inverse) with K = 10 clusters, n = 6 and a cluster-level predictor. An interior fit (theta hat = 0.92) gave df = 7.91, close to K - 2 = 8, and a boundary fit (theta hat = 0) gave df = 57.00 = N - p. A very small change in the data can therefore move a between-cluster test from ~8 to 57 df, i.e. to treating observations as independent. With glmmTMB's log-SD parameterisation, the boundary is only approached, so the df at near-singular fits depends on where the optimiser stopped.


Handling. Raise DF.BOUNDARY_DRIVEN when a fixed effect's df exceeds the number of levels of the grouping factor at which its predictor varies (from P2) and that factor's variance is at or near the boundary (L4-04 criterion). Report a design-based sensitivity df: number of clusters minus the number of cluster-level fixed-effect columns. Show both p-values and recommend the conservative one in reports.


Parity. The Satterthwaite df are engine-specific at the boundary. The design-based sensitivity df is deterministic, hence exact-tier.


Verifier's correction. No correction to the lme4/lmerTest part. Label the glmmTMB sentence as unverified. Cite the design-based df as the 'between-within' method.


Verifier's reasoning. I reimplemented the computation independently: REML deviance in (theta, sigma), central-difference Hessian, pseudo-inverse with eigenvalues > 1e-8 kept, and a numerical Jacobian of L'Cov(beta)L. The setup had K = 10, n = 6, one cluster-level predictor, N = 60 and p = 2. Every interior fit gave df = 8.00 = K - 2, including theta-hat = 0.098. Every boundary fit (theta-hat = 0) gave df = 58.00 = N - p. As theta-hat -> 0+, the df does not converge to N - p. It jumps discontinuously, because Var(theta) grows as the curvature vanishes while dCov/dtheta shrinks. A tiny change in the data can therefore move a between-cluster test from 8 to 58 df. I did not verify the sentence about glmmTMB's log-SD parameterisation. The proposed design-based df matches the between-within method supported by Li & Redden (2015).


Evidence checked. Ran scratchpad/L4adv/scripts/a2_satt.py and scratchpad/L4adv/scripts/a2b.py: df = 8.00 for theta-hat in [0.098, 1.05] and df = 58.00 at theta-hat = 0. Read https://raw.githubusercontent.com/cran/lmerTest/master/R/lmer.R.


### L4-12 Boundary tests for variance components: the 50:50 chi-bar-square is asymptotic and is itself conservative with few clusters

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P27). Verdict: partly_correct.


Claim. Self & Liang (1987, JASA 82:605-610) showed that LRT statistics on a boundary have chi-bar-square (mixture) null distributions. Stram & Lee (1994, Biometrics 50:1171-1177) applied this to longitudinal LMMs: testing k vs k+1 correlated random effects gives 0.5 chi2_k + 0.5 chi2_(k+1). That derivation assumes many independent, identically distributed cluster subvectors (Crainiceanu & Ruppert 2004, JRSS-B 66:165-185, who derive finite-sample null distributions). An exact simulation of the nominal 5% test used a balanced one-way design (400,000 replicates, MC SE about 0.0003). With K = 6 and n = 5, P(LRT = 0) was 0.661 (ML) / 0.561 (REML), and the size was 0.011/0.019 with naive chi2_1 and 0.024/0.039 with the 50:50 mixture. With the mixture, the size was 0.035/0.045 for K = 30 and 0.042/0.048 for K = 100. The mixture is therefore better than naive chi-square but still conservative with few clusters, especially with ML. When more than one parameter lies on the boundary, or a nuisance parameter does, the weights depend on the information matrix and are not 50:50. Self & Liang give a case that is not a chi-square mixture at all. lme4's and glmmTMB's anova methods both use naive pchisq with df equal to the parameter-count difference.


Handling. For variance-component tests, report the naive, mixture and best-available p-values side by side. Best-available is an exact (R)LRT for a single variance component in an LMM with independent random effects (RLRsim, see Scheipl, Greven & Kuchenhoff 2008, CSDA 52:3283-3299), otherwise a parametric bootstrap (L4-13). Apply the mixture only to the single-component or k-vs-(k+1) case and state its assumptions. Never output Wald z tests of variances. A REML-based LRT requires identical fixed effects (L4-07).


Parity. Naive and mixture p-values are deterministic given the deviances and therefore tolerance-tier. Exact-RLRT and bootstrap p-values are simulation-based, so their parity holds in distribution only (P35, L4-13).


Verifier's correction. Cite Stram & Lee (1995) as well. Describe RLRsim as exact for a single variance component, and approximate otherwise. Present one pre-declared primary p-value (exact RLRT or bootstrap where available, otherwise the mixture), with the others shown as diagnostics.


Verifier's reasoning. The simulation numbers reproduce with 400k replicates. K = 6 gives P0 = 0.661 (ML) / 0.562 (REML), naive size 0.012/0.019 and mixture size 0.024/0.039. The mixture size is 0.036/0.045 for K = 30 and 0.041/0.047 for K = 100. Both R anova methods use plain pchisq with df equal to the parameter-count difference. There are three gaps. (i) Stram & Lee published a correction (Biometrics 51(3):1196, 1995), which the item does not cite. Anyone implementing the k vs k+1 rule should check it. (ii) I could not verify that Self & Liang give a case that is 'not a chi-square mixture at all' (the PDF host was blocked). Their multi-boundary cases that I recall are chi-bar-square mixtures with information-dependent weights. (iii) RLRsim's exact (R)LRT is exact for one variance component. With further variance components, it treats the others as known (an approximation), so it is not 'exact' in that case. On the handling, printing naive, mixture and 'best' p-values side by side invites picking one after the fact, so one primary p-value should be declared in advance.


Evidence checked. Ran scratchpad/L4adv/scripts/a1_oneway.py. Read https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R and https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R (pchisq). A web search found 'Corrections: Variance Component Testing in the Longitudinal Mixed Effects Model', Biometrics 51(3):1196 (https://www.bohrium.com/paper-details/corrections-variance-component-testing-in-the-longitudinal-mixed-effects-model/812074914021376002-922).


### L4-13 Parametric bootstrap LRT done properly: refit failures, Monte Carlo error, p-values never zero, cross-language checks in distribution

Kind: feature. Stream: A. Priority: valuable. Origin: new (P35). Verdict: partly_correct.


Claim. A parametric-bootstrap LRT simulates B responses from the fitted null model, refits both models to each and compares the observed statistic with the simulated ones (pbkrtest::PBmodcomp in R). Three design facts matter. (1) Dropping replicates where the fit failed or did not converge conditions the reference distribution on fitting success, which biases it. (2) The Monte Carlo SE of p hat is sqrt(p(1-p)/B), e.g. 0.0069 at p = 0.05 and B = 1000. (3) A p-value estimated from random draws should never be exactly zero. The standard conservative estimate is (1 + #{T*_b >= T_obs})/(B + 1) (Phipson & Smyth 2010, SAGMB 9(1), art. 39). With few clusters, the observed null fit is often singular (L4-08). Simulating from it is legitimate for testing H0, but the replicate refits of the larger model will often be singular too.


Handling. Implement this as a core inferential service in both languages. Use per-replicate RNG streams derived from a master seed (recorded in provenance, P33) and parallel execution. Record the statistic, convergence code and boundary flag for each replicate. Report B, the numbers of failed, singular and non-converged replicates, the p-value with its MC SE and interval, and a sensitivity p-value computed with failed replicates counted as extreme. Allow adaptive B (stop when the MC interval clearly excludes alpha).


Parity. R and Python RNG streams differ (P35). Accept agreement in distribution, e.g. |p_R - p_Py| <= 3 sqrt(2 p(1-p)/B). For exact tests, feed both languages the same simulated response matrix from a fixture file, so the refit statistics can be compared at tolerance tier.


Verifier's correction. Use a fixed B, or a properly designed sequential Monte Carlo stopping rule (e.g. stop after h exceedances). Report failed, singular and non-converged counts, together with the sensitivity p-value that counts failures as extreme.


Verifier's reasoning. The arithmetic is right (sqrt(.05*.95/1000) = 0.0069), and so is the (1+b)/(B+1) rule (Phipson & Smyth 2010). Simulating from the null fit is the standard parametric-bootstrap LRT. Two points are overstated or missing. (1) Dropping failed replicates 'can' bias the reference distribution. Whether it does depends on whether failure is related to the statistic. Calling it biased without qualification is too strong, but the sensitivity analysis is the right response. (2) 'Adaptive B: stop when the MC interval clearly excludes alpha' is not valid as stated. Repeatedly looking at a naive interval inflates the error rate of the Monte Carlo decision. A valid sequential Monte Carlo test (e.g. Besag-Clifford-type stopping after a fixed number of exceedances) or a pre-set B is needed. I did not verify how pbkrtest::PBmodcomp handles failed refits.


Evidence checked. Arithmetic check. Phipson & Smyth reference as given (https://arxiv.org/abs/1603.05766). pbkrtest's failure handling was not inspected.


### L4-14 Information criteria for choosing random effects: known biases, n and parameter-count conventions, post-selection inference

Kind: edge_case. Stream: both. Priority: valuable. Origin: new. Verdict: correct.


Claim. (1) Greven & Kneib (2010, Biometrika 97:773-789) show that the marginal AIC is not an asymptotically unbiased estimator of the Akaike information and favours smaller models without random effects (a boundary effect). (2) The conditional AIC of Vaida & Blanchard (2005, Biometrika 92:351-370) was derived treating the random-effects covariance as known. Ignoring that estimation uncertainty biases it towards keeping any random effect not predicted to be exactly zero (Greven & Kneib propose a corrected cAIC). (3) In lme4, logLik's df = number of fixed effects + number of covariance parameters + 1 (residual scale, where present), and nobs = number of observations even for REML fits. BIC therefore uses log(N), not log(number of clusters), which is arbitrary for comparing random-effect structures. (4) REML-based AIC across different X is invalid (L4-07). glmmTMB returns NA AIC for fits with a non-positive-definite Hessian (L4-05). lme4 fixed a parameter-counting bug for structured covariances in 2.0-6 (GH #943). (5) Choosing the random-effect structure from the data trades Type I error against power (Matuschek et al. 2017, JML 94:305-315, and Bates et al. 2015, arXiv:1506.04967). Fixed-effect p-values after selection are post-selection inferences.


Handling. Any IC table must state the criterion (ML or REML), that X is identical across rows when REML is used, the n used in BIC and the parameter count per model, with any boundary parameters marked. Mark marginal-AIC choices between random-effect structures as biased towards simpler structures. When Stream B or A selects a structure by LRT or IC, store the selection path (candidates, criteria, convergence status) and flag downstream fixed-effect inference as post-selection. Point to the outcome-blind route (P17) as the alternative that avoids selection.


Parity. IC values are tolerance-tier only after the conventions (n, parameter count, constants) are harmonised and recorded. The selection path should be exact-tier on clear-cut fixtures.


Verifier's correction. No correction. Optionally add that lme4's npar counts beta for REML logLik too, and counts boundary parameters as full parameters.


Verifier's reasoning. logLik.merMod reports nobs = nobs.merMod (N, including for REML) and df = npar.merMod = length(beta) + number of covariance parameters + useSc (+1 for negative binomial). BIC therefore uses log(N). glmmTMB's logLik is NA when pdHess is FALSE, so its AIC is NA too. The NEWS for 2.0-6 records the parameter-count fix GH #943. The Greven & Kneib and Vaida & Blanchard characterisations agree with the published abstracts as I know them. Two additions: npar counts beta even for REML criteria, where beta is not in the likelihood, and boundary parameters count fully.


Evidence checked. Read logLik.merMod and npar.merMod in https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R, and logLik.glmmTMB in https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R. Read the 2.0-6 entry in https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd.


### L4-15 Confidence intervals for variance components: Wald intervals mislead in both directions, and the engines' defaults differ

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. lme4's confint.merMod defaults to method = 'profile' (alternatives 'Wald' and 'boot'). glmmTMB's confint defaults to 'wald'. For SDs, it shifts the internal log-SD parameters by +/- z * SE and back-transforms, so the interval is strictly positive and can never include 0. In glmmTMB, 'the CI excludes zero' is therefore not evidence of a non-zero variance. Wald intervals on the SD or variance scale, by contrast, can have negative lower limits near the boundary. lme4 2.1-0 fixed profile intervals that could fall outside parameter bounds, and long-standing edge-case bugs in profile.merMod/confint.thpr (GH #834). glmmTMB's troubleshooting vignette notes that Wald SEs and CIs can be useless for near-boundary parameters.


Handling. Report variance-component CIs from the profile likelihood (computed in the suite from the objective callable when the engine lacks it) or from a parametric bootstrap. At singular fits, report one-sided intervals with a lower limit of 0. Label every CI with its method and scale, and refuse to print Wald CIs for SDs or correlations without a warning.


Parity. CIs are engine-specific unless the method and scale are identical. Profile CIs computed by the suite from the shared objective are tolerance-tier.


Verifier's correction. State that lme4's Wald CIs for variance-covariance parameters are NA and that glmmTMB's profile CIs are on the theta scale and unavailable for REML fits. The suite's Python side must not produce symmetric Wald CIs on the SD scale. Document the calibration of the cut-off for boundary profile intervals.


Verifier's reasoning. Three points are confirmed. lme4's confint defaults to 'profile'. glmmTMB's defaults to 'wald' and back-transforms SDs from the log scale, so its intervals are strictly positive. The 2.1-0 NEWS describes the profile fix and GH #834. Three others are missing or wrong. (i) In lme4, method = 'Wald' returns NA for all variance-covariance parameters, so the 'negative lower limit' problem does not occur in either R engine. It is a hazard only for a Python or hand-rolled delta-method implementation. (ii) glmmTMB's profile() stops with 'can't compute profiles for REML models at the moment', so for REML glmmTMB fits the suite must compute profiles itself. glmmTMB's profile/uniroot CIs are reported on the internal theta scale (log-SD, scaled Cholesky). (iii) At a boundary, inverting the profile at the chi2_1 cut-off gives a conservative one-sided interval. A mixture-calibrated cut-off (2.71) is an option and should be stated.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/man/confint.merMod.Rd ('Wald' gives NA for var-cov). Read https://raw.githubusercontent.com/cran/glmmTMB/master/R/methods.R (confint.glmmTMB details and 'can't compute profiles for REML models'). Read https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd (2.1-0).


### L4-16 '||' means different models in lme4 and glmmTMB, and lme4 now has diag(), which depends on coding and centring

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P18). Verdict: correct.


Claim. In lme4 2.1-0, the default double-bar expansion is still semantic: (1+f||g) becomes (1|g) + (0+f|g). For a k-level factor f, the second term is an unstructured k x k covariance on indicator columns, and the separate intercept variance is redundant with it. The result is not uncorrelated and is typically overparameterised or singular. glmmTMB translates (x+y||g) to diag(x+y|g), a diagonal covariance over the model-matrix columns. lme4 2.0-1 added structured covariances, diag(), cs() and ar1(). It also added options(lme4.doublevert.default = 'diag_special') to make '||' match afex::mixed and glmmTMB, and recommends writing diag() explicitly because defaults may change. The same formula string therefore fits different models in the two R engines when f is a factor. For numeric covariates, the two expansions coincide. A diagonal structure is not invariant to contrast coding (glmmTMB's covstruct vignette shows that diag(f|g) and diag(0+f|g) imply different covariance matrices) or to centring a slope covariate. The afex::expand_re workaround in P18 is no longer the only route.


Handling. In the shared grammar (P30), define '||' as diag() over the model-matrix columns built with explicitly declared contrasts, and have both adapters emit an explicit diag(...) term (lme4 >= 2.0-1, glmmTMB). Warn when '||' is used with factors, centring is unspecified or contrasts are left at engine defaults. In Stream B, report the number of covariance parameters implied by each translation.


Parity. Parity fixtures must use the explicit diag() translation. Comparing lme4 default-'||' fits with glmmTMB '||' fits involving factors is a known mismatch that the expected-disagreement registry should list (L4-20).


Verifier's reasoning. Confirmed. lme4's getDoublevertDefault() returns getOption('lme4.doublevert.default', 'split'), and the 2.0-1 NEWS describes diag(), cs(), the 'diag_special' option and the advice to write diag() explicitly. glmmTMB NEWS says (x+y||g) is translated to diag(x+y|g). The covstruct vignette shows that diag(f|g) and diag(0+f|g) give different covariance matrices. With a factor, (1|g) + (0+f|g) is not identifiable because the indicator columns sum to the intercept. Two additions: lme4 2.0-1 also added ar1(), and diag() over treatment-contrast columns is itself a substantive modelling choice.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/utilities.R (getDoublevertDefault), the 2.0-1 entry in https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd, https://raw.githubusercontent.com/cran/glmmTMB/master/inst/NEWS.Rd (line 646) and https://raw.githubusercontent.com/cran/glmmTMB/master/vignettes/covstruct.rmd (lines 828-864).


### L4-17 GLMM likelihood approximation: Laplace vs adaptive Gauss-Hermite vs nAGQ = 0 gives materially different estimates for binary data with small clusters

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: correct.


Claim. glmer's nAGQ = 1 (default) is the Laplace approximation. nAGQ > 1 (adaptive Gauss-Hermite) is implemented only for a single scalar random-effects term. nAGQ = 0 optimises beta inside PIRLS and is documented as 'faster but less exact'. By default, glmer runs an nAGQ = 0 stage before the full fit (nAGQ0initStep = TRUE, with optimisers bobyqa then Nelder_Mead). glmmTMB uses TMB's Laplace approximation (Brooks et al. 2017). Joe (2008, CSDA 52:5066-5074) reports that Laplace bias is larger for binary and ordinal responses than for counts and shrinks with cluster size. Fits from lme4 with nAGQ = 25 and from glmmTMB can therefore legitimately differ for binary outcomes with few observations per cluster. lme4 2.0-6 symmetrised the quadrature nodes, and 2.1-0 added normalising constants for nAGQ > 1 fits, so nAGQ > 1 log-likelihoods and estimates also changed between lme4 versions.


Handling. For binomial/Bernoulli (and ordinal) GLMMs with a single scalar random effect and small mean cluster size (threshold heuristic and configurable), run an integration-accuracy sensitivity refit with nAGQ of 10-25 in R. Report the changes in beta (in SE units) and in the random-effect SD, and flag changes above a configurable fraction. For vector-valued random effects, report as a limitation that only Laplace is available. The Python side needs its own deterministic quadrature on the shared objective if this check is to have parity.


Parity. Laplace fits in lme4 and glmmTMB are tolerance-tier on the deviance. lme4 nAGQ > 1 vs any Laplace engine is engine-specific (registry, L4-20). Deterministic quadrature implemented in both languages can be tolerance-tier.


Verifier's correction. Add that lme4 2.1-0 also changed nAGQ = 1 results slightly (PIRLS refresh before the Laplace step), so Laplace parity fixtures for lme4 vs glmmTMB are version-dependent too.


Verifier's reasoning. Confirmed from source. updateGlmerDevfun stops for nAGQ > 1 unless there is a single scalar random-effects term. glmer.Rd says nAGQ = 0 is 'faster but less exact'. nAGQ0initStep defaults to TRUE, and the glmer optimisers are c('bobyqa','Nelder_Mead'). The 2.0-6 NEWS records the symmetrised nodes. The 2.1-0 NEWS records the normalising constants for nAGQ > 1 and the PIRLS weight refresh, which also changes Laplace (nAGQ = 1) estimates slightly. I did not re-read the Joe (2008) findings.


Evidence checked. Read https://raw.githubusercontent.com/cran/lme4/master/R/modular.R (updateGlmerDevfun), https://raw.githubusercontent.com/cran/lme4/master/man/glmer.Rd (line 63), https://raw.githubusercontent.com/cran/lme4/master/R/lmerControl.R and https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd.


### L4-18 Fixed-effect SEs depend on which information matrix the engine uses

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. For LMMs and nAGQ = 0 GLMMs, lme4's vcov uses RX, i.e. (X'V^-1 X)^-1 at theta hat, conditional on the variance parameters. For GLMMs with nAGQ > 0, it uses by default the finite-difference Hessian of the deviance in (theta, beta). The documentation warns this is not always more accurate. lme4 2.1-0 changed GLMM SEs 'slightly' by refreshing the PIRLS weights before the Laplace/AGQ step. glmmTMB's ML vcov is sdreport's cov.fixed: the inverse Hessian of the marginal negative log-likelihood with respect to all outer parameters (beta and variance parameters jointly). REML fits instead use the marginalised joint precision. In finite samples, the joint observed information gives SEs >= the conditional ones. In a numerical check (K = 8 unbalanced clusters, ML), the joint/conditional SE ratios were 1.0027, 1.0091 and 1.0014. Separately, lme4 <= 2.1-0 has wrong vcov(full = TRUE) and predict(se.fit = TRUE) SEs for models with more than one random-effects term (permutation bug, off by up to a factor of 4). This is fixed in development version 2.1-1. vcov() of the fixed effects is unaffected.


Handling. Record in the contract which vcov method was used. Have the suite recompute vcov(beta) by one declared method (default for LMMs: conditional (X'V^-1 X)^-1 from the variance estimates), so reported SEs do not depend on the engine. Until 2.1-1 is on CRAN, compute prediction bands in multi-term models from the contract, not with lme4 predict(se.fit = TRUE).


Parity. Engine-reported SEs in LMMs agree to roughly 1e-2 relative, not 1e-6. Suite-recomputed SEs are tolerance-tier.


Verifier's correction. Add: for glmer, the SE method changes silently with N, npar and singularity (Hessian only when derivatives were computed), so the adapter must record which branch vcov took (check whether optinfo$derivs is NULL). Replace the 1e-2 figure with 'agreement depends on the design: it was within 1% in one 8-cluster example'.


Verifier's reasoning. vcov.merMod.Rd is as described. It uses RX for LMMs and for nAGQ = 0, uses the Hessian when beta is in the deviance and warns that the Hessian is not always more accurate. The 2.1-1 vcov(full = TRUE) permutation fix (GH #1013, 'off by factors of up to 4') and the 2.1-0 SE change are in NEWS. The Schur-complement argument (joint inverse Hessian >= conditional (X'V^-1X)^-1 when the Hessian is PD) is sound. The item misses one point. vcov.merMod uses the Hessian only if optinfo$derivs$Hessian exists, and, since 1.1-38, derivatives are skipped for N >= 1e4, theta+beta >= 20 or singular fits. For such GLMMs, SEs therefore switch silently from Hessian-based to RX-based. The parity figure of '~1e-2 relative' comes from one 8-cluster example and should not be stated as a general expectation.


Evidence checked. Read vcov.merMod in https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R (hess.avail requires optinfo$derivs$Hessian) and optwrap (derivs NULL when skipped). Read https://raw.githubusercontent.com/cran/lme4/master/man/vcov.merMod.Rd and https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd (2.1-1, 2.1-0, 1.1-38).


### L4-19 Cross-engine numerical tolerance: compare the objective first, then parameters in the Hessian metric, never coordinate by coordinate

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: preliminary (P29). Verdict: partly_correct.


Claim. Optimisers stop on deviance or parameter changes. lme4's defaults are ftol_abs = 1e-6 and xtol_abs = 1e-6 for nloptwrap, rhoend = 2e-7 for bobyqa and FtolAbs = 1e-5 for Nelder_Mead. Near an optimum, a deviance error delta corresponds to a parameter error of about sqrt(2 delta / lambda) along a Hessian eigen-direction with eigenvalue lambda. For delta = 1e-5 and lambda = 1e-2, that is about 0.045. Weakly identified SDs and correlations can therefore differ substantially between engines while the deviances agree. An empirical illustration used statsmodels 0.15.0 (REML random intercept and slope, K = 12, n = 6, true optimum at correlation -1). L-BFGS reported converged = True with correlation -0.967, while Powell and Nelder-Mead reached -1.000 with a deviance 0.038 lower. The fixed effects matched to 6 decimals, and the SEs differed in the third decimal. A fit flagged 'converged' can stop short of a boundary optimum. Coordinatewise parameter tolerances would either fail healthy fits or pass this one.


Handling. Define tier-2 (comparable-fit) parity as follows. (1) Evaluate both engines' parameter vectors in one reference objective, e.g. the suite's own LMM deviance, which separates 'different optimum' from 'different objective constants'. (2) Require |delta deviance| <= delta_dev (configurable and derived from the optimisers' ftol, e.g. 1e-4 relative to max(1, |deviance|)). (3) Compare variance parameters by 0.5 * d' H d <= delta in a common parameterisation. (4) Compare fixed effects in SE units. (5) Exclude SDs below the scale-free boundary threshold (L4-04) and |r| > 0.99 from value comparisons, and compare only their boundary classification. On failure, report which engine has the lower deviance in the reference objective. That engine's fit is the better one.


Parity. This is the core rule for parity tier 2 in P29. The tiers are exact (data audits, design-based df, registry logic), tolerance (objective-based, as above), in-distribution (simulation, P35) and engine-specific (registry, L4-20).


Verifier's correction. Replace the defaults with nloptwrap ftol_abs = xtol_abs = 1e-8 (code), bobyqa rhoend 2e-7 (glmer adj) and Nelder_Mead FtolAbs 1e-5. Apply the Hessian metric only to parameters in the interior.


Verifier's reasoning. The statsmodels illustration reproduces exactly when I re-run it: lbfgs reports converged = True with llf -96.2406 and r = -0.967, while powell and nm reach llf -96.2214 and r = -1.000. The fixed effect beta_x is identical to 6 decimals, and the SEs differ in the third decimal. The sqrt(2*delta/lambda) arithmetic (0.045) is right. One stated default is wrong: nloptwrap's ftol_abs and xtol_abs have defaulted to 1e-8 since about 1.1-22/23. The 1e-6 values come from the stale ?convergence page. Nelder_Mead FtolAbs = 1e-5 is correct. The quadratic metric 0.5 d'Hd is invalid at a constrained (boundary) optimum, where the gradient is non-zero and H may be singular. The handling's exclusion rule (5) partly covers this.


Evidence checked. Re-ran scratchpad/L4/scripts/t5_flat.py with statsmodels 0.15.0 in my own venv, with the same output. Read https://raw.githubusercontent.com/cran/lme4/master/R/utilities.R (nloptwrap defaults), the 1.1-22 entry in https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd, and https://raw.githubusercontent.com/cran/lme4/master/R/optimizer.R (FtolAbs 1e-5).


### L4-20 Expected-disagreement registry keyed by engine and version, so parity tests do not demand agreement where none is expected

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new (P33). Verdict: correct.


Claim. Fitting 'the same model' with lme4, glmmTMB and another engine gives materially different results, for documented reasons, in these cases: estimation-criterion defaults (lmer REML = TRUE, glmmTMB REML = FALSE, L4-07), '||' with factors (L4-16), singular fits (exact 0 vs a small positive SD with NA SEs and NA logLik, L4-05), nAGQ > 1 (lme4 only, L4-17), the vcov(beta) method (L4-18), Wald CI scale and method (L4-15), df approximations (lmerTest vs glmmTMB's experimental KR/Satterthwaite, whose Satterthwaite approximation changed in glmmTMB 1.1.15, see L4-10 and L4-11), and REML logLik constants and X parameterisation (L4-07). Results also depend on version. lme4 2.1-0 corrected the log-likelihoods of GLMMs with estimated dispersion (Gamma, inverse Gaussian, Gaussian via glmer), which had been too large by an additive 2.0. Before that version, PIRLS weights for those families with non-identity links had been computed with dispersion fixed at 1, which 'could substantially bias' random-effect variances. The same version added normalising constants to nAGQ > 1 log-likelihoods and changed GLMM SEs slightly. lme4 1.1-38 changed when convergence checks run (L4-01). Golden fixtures produced with older engines will therefore legitimately differ from current ones.


Handling. Add to the shared spec (P29) a registry of (engine, version range, condition) entries giving the expected parity tier and, where possible, the expected direction or size of the difference. Parity tests consult it to pass, xfail with a reason or skip. Provenance (P33) must record engine and package versions, criterion, integration method, optimiser and tolerances. Golden fixtures are regenerated, with NEWS review, whenever an engine's version range changes. Reports print the registry note when a user compares across engines.


Parity. The registry defines where parity applies. Without it, cross-language CI would either fail spuriously or have to use tolerances so loose that they hide real bugs.


Verifier's correction. Add the entries listed in the reasoning.


Verifier's reasoning. Each version fact I checked is in NEWS. The 2.1-0 entry records the +2.0 log-likelihood bug for estimated-dispersion GLMMs, the dispersion-1 PIRLS weights for non-identity links, the nAGQ > 1 normalising constants and the slightly changed SEs. The 1.1-38 entry records the convergence-check skips, and the glmmTMB 1.1.15 entry records the faster Satterthwaite. The registry concept is sound. These entries should be added: the glmer SE method switches with N, npar and singularity (L4-18), glmer omits singular messages when derivatives are skipped (L4-01), nloptwrap tolerances changed in 1.1-22/23, lme4 2.0-6 symmetrised the AGQ nodes, lme4 2.1-1 fixed vcov(full = TRUE), and glmmTMB 1.1.15 KR now errors on ML fits.


Evidence checked. Read https://raw.githubusercontent.com/lme4/lme4/master/inst/NEWS.Rd and https://raw.githubusercontent.com/cran/glmmTMB/master/inst/NEWS.Rd. Read https://raw.githubusercontent.com/cran/lme4/master/DESCRIPTION (2.1-0, 2026-10-23) and https://raw.githubusercontent.com/cran/glmmTMB/master/DESCRIPTION (1.1.15.2).


### L4-21 Boundary probe: test whether a near-boundary interior solution beats the reduced-rank model

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. lme4 checks for a better boundary solution only for lmer: restart_edge = TRUE with boundary.tol = 1e-5, documented as 'Currently only implemented for lmerControl'. glmerControl sets restart_edge = FALSE. glmmTMB cannot reach the boundary at all (L4-05). Optimisers can report convergence at an interior point that is worse than the boundary optimum (L4-19: deviance 0.038 worse, correlation -0.967 vs -1.000). A near-zero SD or near-+/-1 correlation in a GLMM or glmmTMB fit may therefore be a stalled optimiser rather than a genuine interior estimate.


Handling. Whenever a block has a near-null direction (L4-03/L4-04) or |r| > 0.99, fit the corresponding reduced model through the adapter: drop the loading term, use diag() or reduce rank. Compute delta deviance = deviance(reduced) - deviance(full), with the number of parameters removed. If delta deviance <= tolerance, report 'interior estimate not supported: reduced model fits as well' and offer the reduced model as the Stream A recommendation. If delta deviance < 0 beyond tolerance, the full fit did not converge (FIT.NESTED_INCONSISTENT). Restart the full model from the reduced estimates (L4-09).


Parity. Delta deviance between the full and reduced models is tolerance-tier across engines, because the constants cancel. The recommendation is exact-tier on clear-cut fixtures.


Verifier's correction. Write: lme4 snaps to the boundary only within boundary.tol = 1e-5 (lmer and glmer), and restart_edge (lmer only) handles the reverse case. glmmTMB has neither mechanism. The suite's probe should compare against the reduced-rank or boundary model and report the deviance difference as a sensitivity result. In confirmatory mode, keep the pre-specified model unless the preregistration defined the reduction rule.


Verifier's reasoning. The premise misreads lme4. restart_edge (lmer only) is not a search for a better boundary solution. It fires only when a parameter equals its bound exactly, and restarts if stepping inward by 1e-5 lowers the deviance. The boundary search is check.boundary (boundary.tol = 1e-5): it snaps parameters within 1e-5 of the bound onto it when that lowers the deviance. It runs for lmer and also for glmer, whose second-stage optimizeGlmer passes control$boundary.tol (default 1e-5) and applies it to theta (dpars). Both mechanisms work only within 1e-5 of the bound, so neither would catch a stall like r = -0.967 (lme4 theta22 of about 0.05). The 'Optimisers can stall' point was shown with statsmodels, not with lme4 or glmmTMB. On the handling, making the reduced model 'the Stream A recommendation' when the deviance change is within tolerance is outcome-dependent re-specification of a confirmatory model. It should be reported as a sensitivity analysis unless a reduction rule was pre-registered. The right comparator for a near +/-1 correlation is the boundary/reduced-rank model, not necessarily dropping a term.


Evidence checked. Read optimizeLmer, check.boundary and optimizeGlmer in https://raw.githubusercontent.com/cran/lme4/master/R/modular.R, glmer's second-stage call in https://raw.githubusercontent.com/cran/lme4/master/R/lmer.R, and https://raw.githubusercontent.com/cran/lme4/master/man/lmerControl.Rd (restart_edge and boundary.tol docs).


## L5 Post-fit diagnostic validity and interpretation


### L5-01 Residual types answer different questions, and the robustness argument against normality tests is overstated

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P21). Verdict: partly_correct.


Claim. A Gaussian LMM has three residual types, and each checks a different assumption. (1) Marginal residuals r = y - X beta_hat check the mean structure in X and, once decorrelated (e.g. Cholesky-scaled V_hat^{-1/2} r), the overall covariance model. Var(r) = V - X(X'V^-1 X)^-1 X', so they are correlated within clusters by construction. (2) Conditional residuals e_hat = y - X beta_hat - Z b_hat check the level-1 errors. With R = sigma^2 I, e_hat = sigma^2 P y and Var(e_hat) = sigma^4 P, where P = V^-1 - V^-1 X (X'V^-1 X)^-1 X'V^-1. They therefore have unequal variances, are correlated and are confounded with b (L5-03, L5-05). (3) BLUPs b_hat check the random-effects distribution. P21's claim that LMMs are 'fairly robust' needs narrowing. Schielzeth et al. (2020) found fixed-effect estimates usually unbiased under distributional violations. However, the components that violated assumptions lost precision, random-effect variances were slightly biased upwards for bimodal generating distributions, and omitted random effects shifted their variance to other levels. Verbeke & Lesaffre (1997) show that ML estimates stay consistent under non-normal random effects. None of this covers heteroscedasticity, dependence or quantities that depend on distributional shape (prediction intervals for new observations or clusters, tail probabilities and BLUP rankings). The stronger reason not to run formal normality tests by default is that their null distribution is wrong for LMM residuals. For example, Shapiro-Wilk on raw BLUPs rejected 29% of the time at nominal 5% when the true random effects were normal (L5-04). With large N, the tests also reject trivial departures.


Handling. Compute all three residual families under canonical IDs (see L5-21). Use studentised conditional residuals by default for level-1 checks, standardised BLUPs (L5-04) for random-effects checks and decorrelated marginal residuals for mean-structure and covariance checks. Do not offer Shapiro/KS/Anderson-Darling on raw residuals, even as an option, without a simulate-and-refit calibration. Tie the relevance of each distributional check to the declared estimands. Shape checks rank low when only fixed-effect inference is reported and are upgraded when prediction intervals, cluster rankings or tail probabilities are requested.


Parity. Residuals are deterministic given (beta_hat, theta_hat), so numerical-tolerance parity is possible once both engines reach the same optimum. Engine-native residual names (e.g. 'pearson', 'response', 'deviance') are not interchangeable across lme4, glmmTMB and statsmodels, so the spec must define each type mathematically.


Verifier's correction. Keep the three-family taxonomy and the estimand-dependent relevance. Present the miscalibration of normality tests as specific to raw, unstandardised or dependent residuals (the case when cluster sizes are unequal), not as a property of all LMM residuals. If the package ever offers a test, run it only on properly standardised BLUPs or level-1 residuals, calibrate it by simulate-and-refit and report it as descriptive. State that consistency under random-effects misspecification covers point estimates, not model-based SEs.


Verifier's reasoning. The algebra holds. Var(r) = V - X(X'V^-1X)^-1X'. With R = sigma^2 I, e_hat = sigma^2 P y and Var(e_hat) = sigma^4 P V P = sigma^4 P, because PVP = P. I checked numerically that sigma^2 P = I - H, where H is the Henderson hat matrix of the conditional fit (max error 2e-16). Secondary sources and the abstract confirm the Schielzeth et al. (2020) summary that estimates are generally robust and that components that violate assumptions lose precision but stay unbiased. They also confirm that random-effect variances are slightly inflated for bimodal distributions and that omitted random effects shift variance to other levels. Secondary sources confirm the Verbeke & Lesaffre (1997) consistency result, but I could not read the full text. Three points are overstated or missing. (1) The 29% Shapiro-Wilk rejection rate belongs to one extreme design, with sizes 1 to 50 and ICC 0.13 (I got 35% with known theta). It shows that raw BLUPs pool unequal variances, but not that 'the null distribution is wrong for LMM residuals' in general. After standardisation by sqrt(lambda_j sigma_u^2), the rejection rate was 3.5%. The general problems are dependence, plug-in parameters and N-dependent power. (2) Consistency of point estimates under a non-normal random-effects distribution says nothing about the model-based SEs. (3) The DHARMa vignette itself tells users to extract the random effects and 'run e.g. a Shapiro test'. That is the practice this item warns against, so the report should say explicitly why it differs from DHARMa.


Evidence checked. Sims in scratchpad/L5adv/b.py: known-theta BLUPs, Shapiro-Wilk 35% raw vs 3.5% standardised. Hat-matrix identity in scratchpad/L5adv/h.py. Schielzeth summary via WebSearch (scholars.uky.edu, ntnuopen.ntnu.no records). Verbeke & Lesaffre 1997 bibliographic details and consistency result via WebSearch (documentserver.uhasselt.be/handle/1942/4667, arxiv.org/html/2411.19384v1). DHARMa vignette source (github florianhartig/DHARMa, vignettes/DHARMa.Rmd, line 268). I did not check Nobre & Singer or Hilden-Minton.


### L5-02 Exact orthogonality: built-in upward trend against conditional fitted values, no linear trend against included predictors

Kind: edge_case. Stream: A. Priority: essential. Origin: new. Verdict: correct.


Claim. Consider a Gaussian identity-link LMM with R = sigma^2 I, where beta_hat is the GLS estimate at theta_hat (true for ML/REML, up to optimiser tolerance). Then X' e_hat = 0 exactly. Conditional residuals have exactly zero sample correlation with every column of X and with the marginal fit X beta_hat. In a random-intercept model, sum_j w_j b_hat_j = 0 exactly for every cluster-level column w in X. Verification in statsmodels gave sums of order 1e-13. In contrast, the covariance with the conditional fit X beta_hat + Z b_hat has positive expectation: E[e_hat' Z b_hat] = sigma^2 tr(P Z G Z') >= 0. In a simulation with 60 clusters of sizes 1-10, ICC 0.5 and a correct model, mean corr(e_hat, conditional fitted) = 0.18, while corr(e_hat, X beta_hat) = 0.000. Two consequences follow. (a) The usual residual-vs-conditional-fitted plot (the lme4 default style) slopes upwards under a correct model. (b) Residual-vs-included-predictor plots cannot show a linear trend, only curvature or changes in spread.


Handling. Plot residuals against the marginal fit X beta_hat and against individual predictors by default. If the conditional fit is used, overlay a simulate-and-refit null envelope so the built-in slope is visible as expected. Run linear-trend checks against candidate omitted variables (cluster means of level-1 predictors, level-2 variables not in the model, time or order), where they carry information. When R is not sigma^2 I (prior weights, glmmTMB dispformula, residual correlation), orthogonality holds as X' R_hat^-1 e_hat = 0, so plot R_hat^{-1/2}-scaled residuals. A unit test asserts |X'e_hat| < tol on fixtures.


Parity. Because the orthogonality identity is exact and engine-independent, it is a cheap cross-language golden test of residual definitions.


Verifier's correction. State that the size of the upward slope against the conditional fit varies with the design, and loosen the X'e_hat tolerance for engines that optimise beta numerically (glmmTMB). Do not apply the exact-orthogonality unit test to GLMMs.


Verifier's reasoning. X'P = 0 gives X'e_hat = sigma^2 X'P y = 0. Because b_hat = G Z'P y, a cluster-level column x = Z w in a random-intercept model gives w'b_hat = sigma_u^2 x'P y = 0, for any R. E[e_hat'Z b_hat] = sigma^2 tr(P Z G Z' P V) = sigma^2 tr(P Z G Z'), which is >= 0. The lme4 Rd confirms that plot.merMod defaults to resid(., type='pearson') ~ fitted(.). In my statsmodels replication, max|X'e_hat| was 1.7e-13 and |sum w_j b_hat_j| was 3.7e-14. corr(e_hat, conditional fit) was 0.133 (the reviewer reported 0.18, from a different design) and corr(e_hat, X beta_hat) was 3e-18. Two minor caveats apply. The size of the slope depends on the design (ICC, cluster sizes, R2 of X). glmmTMB obtains beta_hat by joint numerical optimisation rather than an exact GLS solve, so the unit-test tolerance must be looser there. For GLMMs, the identity holds only approximately (in working-residual form at PIRLS convergence).


Evidence checked. scratchpad/L5adv/a.py: 100 REML fits, 60 clusters of size 1-10, ICC 0.5. Default form checked in lme4 man/plot.merMod.Rd on GitHub (raw.githubusercontent.com/lme4/lme4/master/man/plot.merMod.Rd).


### L5-03 Conditional residual variance shrinks in small clusters: raw or Pearson residuals produce false group-level heteroscedasticity

Kind: edge_case. Stream: A. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Var(e_hat) = sigma^4 P is not constant. In a random-intercept model, ignoring beta_hat estimation, Var(e_hat_ij) = sigma^2 [1 - sigma_u^2/(n_j sigma_u^2 + sigma^2)]. In a simulation with ICC 0.5, 60 clusters of sizes 1-10 and 200 fits, mean e_hat^2 was 0.49, 0.66, 0.75, 0.82, 0.91 for n_j = 1, 2, 3, 5, 10, against theory 0.50, 0.67, 0.75, 0.83, 0.91. Singleton clusters show about half the residual spread of large clusters under exact homoscedasticity. Residuals scaled only by sigma_hat (Pearson-type) keep this pattern, so by-cluster or by-cluster-size spread comparisons flag spurious heteroscedasticity in unbalanced designs. Spread plotted against conditional fitted values was barely affected in an unbalanced simulation with sizes 1, 2, 3 and 40 (Spearman |e| vs |fitted - mean| = 0.028 raw vs 0.025 standardised). The artefact is specific to comparisons across clusters or cluster sizes.


Handling. Before any spread comparison, compute studentised conditional residuals e_hat_i / sqrt(sigma_hat^4 P_ii), extended for leverage as in Nobre & Singer 2007. Show raw residuals only for interpretability, and base every flag on the standardised ones. Compute diag(P) sparsely (L5-21). Whenever cluster sizes differ (for example max/min n_j > 2), report spread by cluster-size stratum alongside the residuals, so users can see that small-cluster residuals are expected to be tighter.


Parity. The quantities are deterministic, so tolerance parity applies to diag(P) and the standardised residuals.


Verifier's correction. Define the studentised conditional residual as e_hat_i / (sigma_hat sqrt(1 - h_ii)), with h_ii = 1 - sigma_hat^2 P_ii, and drop the separate 'leverage extension'. Add an assessability note: in clusters with n_j <= 2, spread differences cannot be attributed to level 1. Label the stratum trigger as a convention.


Verifier's reasoning. The variance formula follows from e_ij = (1 - lambda) u + eps_ij - lambda ebar_j. My replication gave mean e_hat^2 = 0.486, 0.711, 0.748, 0.787, 0.902 for n_j = 1, 2, 3, 5, 10 (theory 0.50 to 0.91). The handling has two weak points. (1) 'Extended for leverage as in Nobre & Singer' is redundant. sigma^2 P = I - H already includes fixed-effect and random-effect leverage, so e_hat / sqrt(sigma^4 P_ii) = e_hat / (sigma sqrt(1 - h_ii)). lme4's hatvalues.merMod already computes h_ii sparsely. (2) Studentisation equalises variances but does not remove confounding. In singleton clusters, the studentised e_hat and b_hat are the same quantity up to sign and scale. Small-cluster spread comparisons therefore still mix level-1 and level-2 heteroscedasticity, and the item does not say so. The max/min > 2 trigger is an arbitrary convention.


Evidence checked. scratchpad/L5adv/a.py (variance by size). scratchpad/L5adv/h.py (H = I - sigma^2 P, max error 2e-16). lme4 source R/lmer.R hatvalues.merMod (uses L, Lambdat, Zt, RX, RZX) on GitHub. I did not check Nobre & Singer.


### L5-04 BLUP QQ plots: unbalance creates false heavy tails, shrinkage hides real non-normality, and the obvious standardisation is wrong

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P22). Verdict: partly_correct.


Claim. P22 is right but incomplete. There are two opposite failure modes and an obvious but wrong scaling. (a) Var(b_hat) = G - PEV = G Z'PZ G, which is smaller than G and differs between clusters. In a random-intercept model, Var(b_hat_j) = lambda_j sigma_u^2, where lambda_j = sigma_u^2/(sigma_u^2 + sigma^2/n_j) is the cluster's reliability. Pooling raw BLUPs from unequal clusters gives a scale mixture, which looks heavy-tailed. A simulation used sizes {1, 2, 5, 20, 50} x 20 clusters, ICC 0.13, normal true random effects and 200 fits. Raw BLUPs had excess kurtosis 0.84 and Shapiro-Wilk rejected 29% of the time at nominal 5%. After dividing by sqrt(lambda_j sigma_u^2), the figures were -0.10 and 6%. (b) Dividing by the posterior SD sqrt(PEV_j), the scale used in caterpillar plots, is wrong for checking distributional shape, because Var(b_hat_j / sqrt(PEV_j)) = lambda_j/(1 - lambda_j), which varies even more. (c) Shrinkage hides real non-normality. With bimodal true effects (+/-1 plus N(0, 0.2^2)), J = 100, n_j = 3 and sigma = 2 (reliability about 0.44), Shapiro-Wilk detected bimodality in 100% of the true effects and 4% of the BLUPs. For a random intercept, the share of Var(b_hat_j) that comes from level-1 error is exactly 1 - lambda_j. Misspecifying the random-effects shape often matters little for fixed effects but does matter for predicting the random effects themselves (McCulloch & Neuhaus 2011).


Handling. Standardise BLUPs by the marginal Var(b_hat_j) = G - PEV_j. Use the matrix square root for vector random effects, and give a per-cluster Mahalanobis distance b_hat_j' Var(b_hat_j)^-1 b_hat_j against chi^2_q for cluster-outlier screening. G - condVar from an engine that treats beta_hat as known (G Z'V^-1 Z G) differs slightly from G Z'P Z G when clusters are few. Next to every BLUP distribution plot, report the mean and range of the reliabilities lambda_j. When mean(1 - lambda_j) is high (registry threshold, e.g. > 0.5), label the random-effects distribution 'not assessable from BLUPs' rather than letting the plot imply 'looks normal'. When a grouping factor has few levels (the P5 range), replace the QQ plot with a dot plot.


Parity. These quantities are deterministic given theta_hat. Parity is tested on Var(b_hat_j) and the standardised BLUPs, not on engine-specific condVar output.


Verifier's correction. Compute Var(b_hat_j) from the contract (G Z'PZ G blocks), never as G - engine condVar. Use a pseudo-inverse with df = rank(Var(b_hat_j)), and flag clusters with rank < q as not screenable. Narrow the McCulloch & Neuhaus point: average prediction MSE is fairly robust, while predicted-effect shape and extreme-cluster predictions are not. Restrict the closed forms to Gaussian LMMs.


Verifier's reasoning. Several parts check out. Var(b_hat) = G Z'P Z G = G - PEV (Henderson). In a random-intercept model, Var(b_hat_j) = lambda_j sigma_u^2, Var(b_hat_j / sqrt(PEV_j)) = lambda_j / (1 - lambda_j) and the error share is 1 - lambda_j. My known-theta replication gave raw Shapiro-Wilk 35% and excess kurtosis 0.91, against 3.5% and -0.05 after standardisation. There are four problems. (1) The Mahalanobis-vs-chi^2_q screen needs a full-rank Var(b_hat_j). With random slopes and n_j = 1, or a slope covariate that is constant within a cluster, Var(b_hat_j) has rank < q. (2) Engine condVar does not mean the same thing across engines. The lme4 Rd says postVar is 'conditional on the estimates of the model parameters', so G - condVar_lme4 = G Z'V^-1 Z G. glmmTMB's condVar comes from TMB sdreport, which adds a J V(theta_hat) J' parameter-uncertainty term (generalised delta method). G - condVar_glmmTMB is therefore not Var(b_hat) and need not be positive semi-definite. The gap from G Z'PZ G is also driven by clusters with high leverage on beta, not only by having few clusters. (3) The McCulloch & Neuhaus point is overstated. Their companion work finds the unconditional MSE of prediction fairly robust, with losses for extreme cases such as a two-point distribution with large variance. What suffers is the shape of the predicted-effect distribution and cluster-specific prediction for extreme clusters. (4) All formulas are Gaussian-only, and GLMMs have no closed form.


Evidence checked. scratchpad/L5adv/b.py (1000 reps, sizes {1,2,5,20,50} x 20, ICC 0.13). lme4 man/ranef.Rd ('conditional on the estimates of the model parameters'). glmmTMB R/methods.R ranef uses summary(object$sdr,'random'). TMB R/sdreport.R documentation of the J V(theta) J' term (all on raw.githubusercontent.com). McCulloch & Neuhaus via WebSearch (projecteuclid.org/euclid.ss/1320066927, arxiv 1201.1980).


### L5-05 Report the fraction of confounding and gate distributional checks on it

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Because PX = 0, e_hat = sigma^2 P (Z b + eps), so conditional residuals carry part of the random effects. Loy & Hofmann (2015) define a fraction of confounding as the share of a residual vector's variance due to the other level, here tr(sigma^4 P Z G Z' P) / tr(sigma^4 P). For a single random-intercept observation, it equals (1 - lambda_j)^2 sigma_u^2 / [sigma^2 (1 - lambda_j/n_j)]. With ICC 0.5, that is 0.50 for n_j = 1 and about 0.009 for n_j = 10. Level-1 normality checks are therefore dominated by the random effects in small clusters, and BLUP checks are dominated by level-1 error when reliability is low (L5-04). Hilden-Minton (1995) constructs uncorrelated, least-confounded residuals, and Loy & Hofmann propose rotated random effects. Both are linear combinations, so they no longer map one-to-one to observations or clusters.


Handling. Compute the fraction of confounding for each residual family and each cluster-size stratum, store it in the results JSON and use it to set each distributional plot's 'assessability'. Offer least-confounded or rotated residuals as an option, for distributional checks only (not for outlier identification). Eigen-decompositions are block-diagonal in nested designs but dense in crossed designs. To limit cost, cap their use by N or fall back to blockwise computation.


Parity. The fraction of confounding is deterministic, so tolerance parity applies. Rotated residuals have sign and rotation indeterminacy (eigenvectors, repeated eigenvalues), so test parity only on invariant summaries such as sorted values or QQ quantiles.


Verifier's correction. Keep the fraction of confounding as an assessability input. Compute it at theta_hat, mark it as conditional on theta_hat and suppress it near singularity (L5-20). Attribute the least-confounded residuals to Hilden-Minton (1995) and to Loy & Hofmann's generalised-eigen approach only after checking the paper. Document the reduced dimension and the residual confounding that may remain.


Verifier's reasoning. The confounding decomposition is correct: e_hat = sigma^2 P Z b + sigma^2 P eps, with total variance sigma^4 P. My algebra reproduces the per-observation formula, with values 0.50 (n = 1, ICC 0.5) and 0.0091 (n = 10). Three caveats apply. (1) I could not retrieve the Loy & Hofmann (2015) full text. The bibliographic details are confirmed, but not their exact trace-ratio definition or the attribution of 'rotated random effects' to that paper. The search tied the least-confounded construction to Hilden-Minton (1995) and to Loy's dissertation (generalised eigen-decomposition). (2) The fraction of confounding depends on theta_hat, and that is circular when the variance components themselves are in question. Near a singular fit, it becomes unstable. (3) The documentation should state that least-confounded residuals have reduced dimension and cannot remove confounding entirely when the hat structure does not allow it.


Evidence checked. Analytic check of the single-observation formula. WebSearch confirmed the JCGS 24(4):1191-1209 citation (aloy.rbind.io/scholarship) and the HLMdiag JSS 56(5) residual taxonomy. The definitions in the full text were not verified.


### L5-06 Simulation-based quantile residuals: the conditioning choice decides what is tested, and observation-level uniformity tests are uncalibrated

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P23). Verdict: partly_correct.


Claim. 'Simulate from the fitted model' has two meanings in mixed models: unconditional (draw new b) and conditional (hold b at b_hat). Neither gives calibrated observation-level tests. A simulation fitted a correct Gaussian random-intercept LMM with statsmodels REML (nsim = 250, 200 replicates), defined the PIT as the share of simulated responses below the observed one and tested it by KS against U(0,1). (a) Under unconditional simulation at observation level, the PITs are marginally uniform but correlated within clusters. With the true parameters, KS rejected 40.5% of the time (J = 40, n = 10, ICC 0.5) and 77% (J = 20, n = 20, ICC 0.8) at nominal 5%. With plug-in fitted parameters, it rejected 0% and 21.5%. Calibration depends on the design and has no predictable direction. (b) Under conditional simulation, PITs are underdispersed, with variance 0.0795 (n = 10) and 0.0712 (n = 3) against 1/12 = 0.0833, and KS rejected about 0% of the time. (c) Under unconditional simulation aggregated to cluster sums, KS rejected 5.0% of the time with the true parameters and 0% with plug-in ones. That is valid in principle but conservative, consistent with plug-in p-values concentrating near 1/2 (Robins, van der Vaart & Ventura 2000). The conditional/unconditional distinction applies to LMMs as well as GLMMs. For discrete outcomes, the PIT needs randomisation (Dunn & Smyth 1996), so the residuals themselves depend on the seed.


Handling. Make the conditioning mode an explicit argument with no silent default, record it and print what each mode checks. The unconditional mode checks the whole hierarchical model, including the random-effects distribution. The conditional mode checks the level-1 distribution given the clusters. Do not show observation-level uniformity or dispersion p-values as tests. If a calibrated number is needed, there are two options. (i) Compute the statistic at the independent-unit level (the clusters, stating which factor for crossed designs). (ii) Calibrate by simulate-and-refit (a parametric bootstrap of the whole residual pipeline), which absorbs both dependence and plug-in effects. Report Monte Carlo error from nsim and, for discrete outcomes, the spread over k re-randomisations.


Parity. These outputs depend on the RNG, so only distributional parity is possible (P35). For example, compare the R and Python distributions of the PIT variance and the KS statistic over 200 replicate seeds on the same fixture, rather than individual residuals.


Verifier's correction. State that with true parameters, unconditional observation-level tests are anticonservative (increasingly so with ICC and n_j) and that plug-in estimation can reverse this. Also state that conditional simulation, the DHARMa default since 0.5.0, gives underdispersed PITs under a correct Gaussian LMM, so conditional dispersion statistics need simulate-and-refit calibration. Keep the conditioning mode explicit and require it in confirmatory specs.


Verifier's reasoning. My replication with true parameters and analytic PITs (nsim effectively infinite) confirms the pattern. Unconditional observation-level KS rejected 40.2% (J = 40, n = 10, ICC 0.5), 81% (J = 20, n = 20, ICC 0.8) and 11.4% (ICC 0.1). Conditional PIT variance was 0.0789 and 0.0809, below 1/12, and KS rejected 0.4% and 0.1%. Cluster-aggregated KS rejected 5.0%, 5.6% and 4.5%. With true parameters, the direction is predictable. Dependence always inflates rejection, and the inflation grows with ICC and cluster size. Only plug-in estimation makes the direction unpredictable. Robins et al. (2000) is confirmed: plug-in p-values are conservative and concentrated around 1/2 when the statistic's mean depends on theta. One fact bearing on the item is missing. DHARMa 0.5.0 and later (current 0.5.1) defaults to conditional simulation on all random effects and recommends dispersion tests only under conditional simulation. Its vignette also says residuals 'should be flat regardless of how many hierarchical levels we re-simulate'. The underdispersed conditional PITs shown here contradict that for Gaussian LMMs with finite clusters, because shrinkage makes Var(e_hat) < sigma^2. A DHARMa-style conditional dispersion test is therefore biased towards 'underdispersion', and the parity design must not copy that default without saying so.


Evidence checked. scratchpad/L5adv/d.py (2000 reps per design). DHARMa vignette source and DESCRIPTION (version 0.5.1) from github florianhartig/DHARMa, lines 245-283 and 396-398. Robins et al. abstract via WebSearch (statweb.rutgers.edu/ztan/material/robins-vandervaart-ventura.pdf). I did not check Dunn & Smyth.


### L5-07 Binary outcomes: observation-level dispersion is undefined and raw residual plots carry almost no information

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. A Bernoulli variable's variance p(1-p) is fixed by its mean, so an observation-level overdispersion check for 0/1 outcomes has nothing to detect. Extra-binomial variation exists only at aggregate level (clusters or covariate patterns), and in a GLMM the random effects already absorb part of it. Raw, Pearson and deviance residuals from logistic models are discrete and fall on two curves, so they are generally uninformative. Binned residuals (average residual against average fitted value per bin, with +/-2 SE bands, as in Gelman & Hill 2007) or cluster-aggregated simulated residuals are the informative forms. Low-mean Poisson counts behave similarly, at a milder level.


Handling. For binomial outcomes with 1 trial, suppress observation-level dispersion and uniformity checks and say why. Provide binned residual plots against fitted values and against each predictor, with the number of bins tied to N (e.g. about sqrt(N)) and a statement that about 5% of bins are expected outside the +/-2 SE band. Provide cluster-level dispersion through aggregated simulation (L5-06) and counts of all-0 and all-1 clusters (complementing P14). For binomial outcomes with more than 1 trial, observation-level dispersion is defined and the check runs.


Parity. Bin edges must be defined identically (quantile type, tie handling) in both languages for exact parity of binned summaries.


Verifier's correction. For Bernoulli outcomes, suppress the observation-level dispersion test and the pooled residual-vs-fitted uniformity test. Keep the observation-level quantile-residual plots against each predictor and against candidate omitted variables. Run aggregated dispersion checks by covariate pattern, by unmodelled groupings, or by the modelled cluster under unconditional simulation only, and record the aggregation unit.


Verifier's reasoning. The DHARMa vignette supports the core claim. For a misspecified 0/1 model, there is 'neither dispersion problems nor a misfit in the general res ~ predicted plot', and grouping the residuals turns 0/1 into k/n and reveals overdispersion. The same vignette shows the misfit 'clearly visible if we plot the residuals against the missing predictor' with quantile regression. Suppressing observation-level uniformity checks wholesale is therefore wrong, because observation-level quantile residuals plotted against predictors and candidate omitted variables are informative for binary outcomes. The second gap is that aggregating by the modelled grouping factor under conditional simulation largely tests nothing, because b_hat absorbs cluster-level excess variation. Cluster aggregation is informative only under unconditional simulation, or when aggregating by a grouping that is not in the model or by covariate patterns. I could not verify the arm::binnedplot page and bin rule (CRAN blocked). From memory, the rule is floor(sqrt(n)) for n >= 100.


Evidence checked. DHARMa vignette source, lines 787-822 (github florianhartig/DHARMa). Gelman & Hill page reference not verified.


### L5-08 Cluster influence: fixed cut-offs depend on cluster size, and theta-fixed approximations miss influence that acts through variance components

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P24). Verdict: correct.


Claim. (a) Under the null, Cook's D grows with cluster size. A simulation computed one-step cluster-deletion D with theta fixed at the truth. It used 40 clusters (10 each of sizes 2, 5, 20, 50), a level-1 and a level-2 predictor, sigma_u^2 = 0.5, sigma^2 = 1 and 300 replicates. Mean D was 0.012, 0.018, 0.036, 0.045 and P(D > 4/J = 0.1) was 1.1%, 2.1%, 7.0%, 10.5% by size, so the conventional 4/J cut-off mostly flags large clusters. (b) Approximations that hold theta fixed miss influence that acts through the variance components. A second simulation used J = 12, n = 10, one cluster with its intercept 6 SD out, a cluster-level predictor w and 50 replicates. Exact deletion and refit changed sigma_u^2_hat from 0.96 to 0.25 and SE(beta_w) from 0.343 to 0.210. The theta-fixed one-step estimate gave SE 0.367, moving in the wrong direction. (c) Influence has separate targets: fixed effects (Cook's D, MDFFITS), their precision (COVRATIO), variance components (relative change), BLUPs of other clusters, and decisions.


Handling. Run diagnostics per level of each grouping factor. Crossed designs get separate subject and item deletions. In nested designs, deleting an outer level removes all its inner levels. Use exact refits by default when the number of levels is modest (registry bound, e.g. <= 100), warm-started at theta_hat and run in parallel. Label one-step results 'beta-only, theta fixed'. Show ranks and relative magnitudes (dot plot or half-normal plot), calibrated if needed by simulate-and-refit, rather than fixed thresholds. Report decision-changing deletions: a sign change, or a CI for a declared focal parameter that starts or stops crossing 0. Record every refit's status (converged / singular / rank-deficient / failed). When a deletion makes a parameter non-estimable (the only cluster at a level of a between-cluster factor, or a factor dropping below 2 levels), report 'not estimable without this cluster', not an infinite influence value.


Parity. One-step formulas allow exact parity. Exact-refit diagnostics allow tolerance parity only when both engines converge to the same optimum, so store each refit's optimiser status and compare only refits that converged.


Verifier's correction. Make simulate-and-refit (or size-stratified) calibration the default for unbalanced designs, and use uncalibrated ranks only when sizes are similar.


Verifier's reasoning. I replicated (a) with theta fixed at the truth, which makes the GLS deletion exact. Mean D was 0.013, 0.019, 0.031, 0.047 and P(D > 0.1) was 1.6%, 2.2%, 4.9%, 11.9% for sizes 2, 5, 20, 50, in line with the claim. I did not rerun (b), but the mechanism is sound. With theta held fixed, deletion only removes information, so SE(beta_w) rises. A refit that collapses sigma_u^2 lowers it. As for the handling, much of the size dependence is real information, so uncalibrated ranks still put large clusters at the top. The 'calibrated if needed' clause should therefore be the default whenever cluster sizes differ markedly. The cited references were not individually verified.


Evidence checked. scratchpad/L5adv/e.py (300 reps, 40 clusters, sizes 2/5/20/50 x 10, p = 3).


### L5-09 Level-1 and level-2 outliers cannot be told apart in very small clusters

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In a singleton cluster, an observation's deviation is split deterministically: a fraction lambda_j goes to b_hat_j and 1 - lambda_j to e_hat_ij. A level-1 outlier and a level-2 outlier then produce identical data, and with n_j = 2 they are barely distinguishable. An extreme observation in a small cluster also pulls its own b_hat_j towards it and shrinks its own residual, a masking effect of high random-effects leverage. As a result, residual-based outlier lists under-report observations from small clusters, while BLUP-based lists attribute them to the cluster.


Handling. For each flagged observation or cluster, report n_j, lambda_j and how its deviation splits between b_hat_j and e_hat_ij. Flag 'level ambiguous' when n_j <= 2 or random-effects leverage is high. Use studentised (leverage-adjusted) conditional residuals for level-1 outliers and standardised BLUPs (L5-04) for level-2 outliers. Never drop cases automatically. Removal is only a sensitivity refit (L5-17).


Parity. The quantities are deterministic, so exact parity applies.


Verifier's correction. Treat n_j = 1 as 'level not identifiable'. For n_j = 2, report 'outlying observation not identifiable within cluster' when the two observations disagree, not 'level ambiguous'. Otherwise, base the flag on random-effects leverage (1 - h_ii, lambda_j).


Verifier's reasoning. For n_j = 1, the claim is right. The split between b_hat_j and e_hat is lambda_j and 1 - lambda_j, and level-1 and level-2 outliers cannot be identified separately. For n_j = 2, the claim is overstated. A single deviant observation (6, 0) and a shifted cluster (6, 6) are clearly distinguishable. What is ambiguous with two observations is which of them is the anomalous one when they disagree, because each could be the outlier relative to an unknown cluster mean. The masking effect of an extreme point pulling its own b_hat is correct and well known. I did not check the references.


Evidence checked. Analytic reasoning from b_hat_j = lambda_j (ybar_j - mu).


### L5-10 Heteroscedasticity: per-cluster spread is noise when clusters are small, and checks should measure impact, not significance

Kind: correction. Stream: A. Priority: valuable. Origin: preliminary (P25). Verdict: partly_correct.


Claim. Per-cluster residual SDs are almost uninformative when n_j is small. In a simulation with 50 groups, exact homoscedasticity and 2000 replicates, the median max/min within-group SD ratio was 18.3 for n_j = 3 (90th percentile 50.8), 6.1 for n_j = 5 (9.7) and 2.1 for n_j = 20 (2.5). Raw residuals add the cluster-size artefact from L5-03. An omitted random slope shows up as residual spread that grows with distance from the slope covariate's reference point. Heteroscedasticity against a predictor can therefore signal a random-effects misspecification rather than a residual variance function. A gap between cluster-robust and model-based SEs measures how much inference depends on the variance model (King & Roberts 2015). Aronow (arXiv:1609.01774) argues that such a gap is not in general a valid misspecification test, and with few clusters, robust SEs are themselves unreliable.


Handling. Assess spread on studentised conditional residuals inside simulate-and-refit envelopes against (i) declared low-cardinality grouping variables (condition, site, wave), (ii) the marginal fit and (iii) each predictor, especially candidate random-slope covariates. Do not produce per-cluster SD tables or Levene-type tests across many small clusters. As an impact measure, report the ratio of small-sample-corrected cluster-robust SEs to model-based SEs for each focal fixed effect, flagged unreliable when the number of clusters is small (link to P5). Where the engine can model the variance (glmmTMB dispformula, but not lme4), optionally fit a variance-function model as a labelled sensitivity refit and report the change in focal estimates and SEs.


Parity. Envelope parts depend on the RNG and get distributional parity. The SE ratio is deterministic once the CR estimator type (e.g. CR2 vs CR1) is fixed in the spec. Remediation suggestions must depend on the engine.


Verifier's correction. An omitted random slope appears as conditional-residual spread that increases with |x_ij - xbar_j|, and as marginal-residual variance quadratic in x with minimum at -sigma_01/sigma_1^2. Plot studentised residuals against within-cluster-centred x for candidate slope covariates.


Verifier's reasoning. I replicated the SD-ratio figures (2000 reps, 50 groups): median and 90th percentile 18.1 and 46.8 (n = 3), 6.0 and 9.9 (n = 5), 2.1 and 2.4 (n = 20). Searches confirm the Aronow arXiv note: under a correctly specified semiparametric model, robust and classical SEs can diverge, so the gap is not in general a misspecification test. The omitted-random-slope mechanism is misstated. For conditional residuals from a random-intercept fit, the random intercept absorbs u_1j xbar_j, so spread grows with the within-cluster deviation |x - xbar_j|, not with distance from x's reference point. For marginal residuals, the variance is quadratic in x with its minimum at -sigma_01/sigma_1^2, which in general is not the reference point either. In my simulation, Spearman |e_hat| was 0.047 against |x| and 0.147 against |x - xbar_j|.


Evidence checked. scratchpad/L5adv/b.py (SD ratios). scratchpad/L5adv/c.py (omitted slope). Aronow note and King & Roberts via WebSearch (arxiv.org/abs/1609.01774, gking.harvard.edu publication page).


### L5-11 Autocorrelation: conditional residuals are negatively autocorrelated by construction and can reverse the sign of true serial correlation

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P25). Verdict: correct.


Claim. Without serial correlation, conditional residuals within a cluster have negative correlation, which approaches -1/(n_j - 1) (the correlation of within-cluster demeaned residuals) as reliability tends to 1. In a balanced simulation with 60 clusters, statsmodels REML and 150 fits, mean lag-1 correlation was -0.238 (n = 5, ICC 0.8, limit -0.25), -0.117 (n = 5, ICC 0.2) and -0.110 (n = 10, ICC 0.8, limit -0.111). With true AR(1) errors of rho = 0.3 (n = 5, ICC 0.8), the naive lag-1 correlation of the conditional residuals was -0.05, with the sign reversed. ACF and Durbin-Watson-type checks on conditional residuals from short series therefore miss or invert positive serial correlation. A missing random slope for time also induces positive residual autocorrelation, so serial correlation and random-effects structure are partly confounded.


Handling. Compute temporal checks only when the user declares a time variable and a unit variable (row order is not time). Compare the observed within-unit ACF to a simulate-and-refit envelope, which reproduces the built-in negative correlation. For irregular spacing, provide the empirical semi-variogram of marginal or OLS residuals against lag in time units (Diggle 1988). State the confounding with a random slope of time in the message. Remediation depends on the engine. lme4 has no residual correlation structures, while glmmTMB offers ar1/ou-type terms.


Parity. The ACF and variogram of the observed residuals are deterministic, so exact or tolerance parity applies. Envelopes get distributional parity.


Verifier's correction. In the remediation text, say that glmmTMB autocorrelation is specified as a random-effect covariance term on an observation-level factor and that it needs care with the residual variance.


Verifier's reasoning. I replicated with true theta, 60 balanced clusters and 300 reps. Lag-1 correlation was -0.235 (n = 5, ICC 0.8), -0.124 (n = 5, ICC 0.2, analytic -0.125), -0.104 (n = 10, ICC 0.8, limit -0.111) and -0.047 under AR(1) with rho = 0.3, with the sign reversed. The -1/(n - 1) limit follows from within-cluster demeaning. An omitted time slope gives conditional residuals u_1j (t - tbar_j), which are positively correlated at short lags. A minor point on the handling is that glmmTMB's ar1()/ou() are random-effect covariance structures. Emulating residual autocorrelation applies them to an observation-level term, which raises identifiability issues with the residual variance. The DHARMa vignette also warns that conditional residuals of pure AR1/OU models can show extreme patterns. The Diggle reference was not verified.


Evidence checked. scratchpad/L5adv/c.py. DHARMa vignette table on AR1/OU conditional residuals (github source, lines 258-264).


### L5-12 Functional form and contextual effects: check BLUPs against cluster means, not only residuals against predictors

Kind: feature. Stream: A. Priority: valuable. Origin: new (P7). Verdict: partly_correct.


Claim. Because X'e_hat = 0 and sum_j w_j b_hat_j = 0 for included level-2 columns (L5-02), residual plots against included predictors can only show curvature. A pooled smoother of e_hat against x also mixes within-cluster and between-cluster curvature. An omitted contextual effect (between-cluster slope differing from within-cluster slope) appears in b_hat against the cluster mean x_bar_j, not in e_hat against x. In a simulation with within slope 0.3, between slope 1.3 and 60 clusters of size 2-14, the pooled GLS slope was 0.305, so the model silently reported the within effect. The correlation corr(b_hat_j, x_bar_j) was 0.53. This breaks the assumption that random effects are uncorrelated with the predictors, which Antonakis et al. (2021) say is commonly ignored. Adding cluster means (Mundlak 1978, Bell & Jones 2015) is the standard remedy.


Handling. For each level-1 predictor with non-trivial between-cluster variance (computed in Stream B, P7), plot e_hat against (x - x_bar_j) with a smoother and standardised b_hat against x_bar_j. For level-2 predictors, plot b_hat against w (curvature only). Report corr(b_hat, x_bar_j) and, as a labelled sensitivity refit, the change in focal coefficients (in SE units) when x_bar_j is added. Do not re-specify automatically. For large N, use binned means with intervals instead of raw scatter (P34).


Parity. The plotted quantities and the auxiliary refit are deterministic, so tolerance parity applies.


Verifier's correction. State that omitting the cluster mean yields a design-dependent weighted average of the within and between slopes, close to the within slope only when n_j sigma_u^2 / sigma^2 is large. Report the auxiliary-refit change in focal coefficients as planned.


Verifier's reasoning. The orthogonality points and the diagnostic (b_hat against xbar_j) are correct. 'The model silently reported the within effect' is design-specific. The random-intercept GLS/REML slope is a precision-weighted blend of the within and between slopes, and the weight depends on n_j and the ICC. With within 0.3 and between 1.3, my REML fits gave 0.591 (J = 60, n = 2), 0.708 (J = 200, n = 2, sigma_u^2 = 0.2) and 0.379 (J = 60, n = 8). The omitted contextual effect therefore produces an uninterpretable mixture that can sit anywhere between the two slopes. The cited references were not verified.


Evidence checked. scratchpad/L5adv/f.py (known theta) and g.py (statsmodels REML, 60 reps per design).


### L5-13 Simulation envelopes must be simultaneous (global), not pointwise

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Pointwise 95% envelopes on QQ or residual plots raise false alarms most of the time under a correct model. With iid normal data and 999 reference simulations, P(at least one QQ point outside a pointwise 95% envelope) was 0.48 for n = 50 and 0.70 for n = 400 (2000 replicates). In mixed models, the reference must also reproduce shrinkage, leverage and within-cluster dependence, so the envelope must come from simulate-and-refit replicates of the same residual type, not from N(0,1) draws. Global envelope methods (Myllymäki et al. 2017) give envelopes with simultaneous coverage.


Handling. Build QQ, ACF, variogram and smoother envelopes from B simulate-and-refit replicates (B registry-configurable, with Monte Carlo error shown). Use global rank envelopes by default, and label any pointwise band 'pointwise: about 1 in 20 points outside is expected'. Report the observed curve's global extreme rank as a descriptive number, not a pass/fail.


Parity. Envelopes depend on the RNG, so distributional parity applies. The global-envelope construction itself (ranking rule, ties) needs exact cross-language parity, tested on fixed fixtures of simulated curves.


Verifier's correction. Default to the extreme-rank-length (or continuous-rank) global envelope, so that a few hundred refits suffice. Document that the plain rank envelope needs about 2499 simulations and that plug-in envelopes are conservative.


Verifier's reasoning. I replicated the false-alarm figures: 0.476 (n = 50) and 0.704 (n = 400). Two conditions are missing. (1) Global rank envelopes need many simulations. The GET package documentation recommends nsim = 2499 for the rank envelope test on a single function, while extreme-rank-length or continuous measures need fewer. With simulate-and-refit, the rank envelope would need thousands of refits, so the default B and the ordering measure must be chosen together. (2) Envelopes from a model fitted to the same data are a Monte Carlo test of a composite null with plug-in parameters, and therefore conservative (Robins et al. 2000). That fits the item's 'descriptive, not pass/fail' framing but should be stated.


Evidence checked. scratchpad/L5adv/b.py (999 reference sims, 2000 reps). WebSearch on Myllymäki et al. 2017 (research.aalto.fi record) and GET docs (rdrr.io/cran/GET/man/GET-package.html, nsim = 2499).


### L5-14 Lineup protocol that keeps its inferential validity inside an automated report

Kind: feature. Stream: A. Priority: valuable. Origin: preliminary (P21). Verdict: partly_correct.


Claim. Lineups work as tests only under two conditions. (1) Null panels come from a parametric bootstrap of the fitted model with refitting, and the same residual type is recomputed on each (Loy, Hofmann & Cook 2017). Drawing null residuals directly from the assumed distribution omits shrinkage, leverage and the built-in correlation (L5-03, L5-11), so the real panel stands out even when the model is correct. (2) The single-viewer p-value of 1/m (0.05 for m = 20) requires a viewer who has not seen the real plot (Buja et al. 2009). A report that shows the observed residual plot elsewhere violates this condition. Lineups perform about as well as conventional tests and better under contamination (Majumder, Hofmann & Cook 2013). Conventional residual tests can be oversensitive compared with lineups (Li et al. 2024).


Handling. Provide a 'lineup first' mode in the HTML report. In this mode, the panel position is randomised with a recorded seed and the observed plot is hidden until the viewer picks a panel. The pick, the time and the panel position go into the provenance record. For large N, apply the same downsampling rule to the observed and null panels, always keeping the k most extreme points in each (P34). Count the lineups shown towards the multiplicity summary (L5-15). In static reports, show lineups without claiming a p-value.


Parity. Null panels and positions depend on the RNG, so there is no panel-level parity. Test the null-generation algorithm for distributional parity.


Verifier's correction. Label the lineup p-value as approximate (plug-in null). Record whether the viewer is the analyst, and recommend external viewers for any reported p-value. Count repeated lineups on the same data as dependent.


Verifier's reasoning. Majumder et al. (2013) is confirmed: lineups perform about as well as conventional tests, better under contamination and with higher power for large effects. Li et al. (2024), JCGS 33:1497-1511, is confirmed: conventional tests are too sensitive, and the observer should not see the data plot before the lineup. Loy, Hofmann & Cook (2017) is listed as arXiv 1502.06988. Two conditions are missing. (1) The 1/m p-value also requires the null panels to be exchangeable with the observed panel under H0. With panels drawn from a parametric bootstrap at estimated parameters, this holds only approximately (composite null), so the p-value is approximate. (2) The analyst who specified and fitted the model has usually already seen the data and residual patterns. Repeated lineups of the same data shown to the same viewer are also not independent. The 'hidden until pick' mode helps, but it does not make the analyst a naive viewer. Delegating the pick to a colleague or crowd viewers is closer to the protocol.


Evidence checked. WebSearch: Majumder et al. abstract (ideas.repec.org/a/taf/jnlasa/v108y2013i503p942-956.html). Li et al. (arxiv.org/abs/2308.05964, ANU record). Loy et al. arXiv 1502.06988 listed in results. Buja et al. 2009 not verified.


### L5-15 Multiplicity across many diagnostics: expect flags under a correct model and calibrate at the family level

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. If k checks each have a 5% false-alarm rate and are independent, P(at least one flag) = 1 - 0.95^k, which is 0.40 for k = 10, 0.64 for k = 20, 0.79 for k = 30 and 0.92 for k = 50. Diagnostics are dependent, so these figures are only indicative. Even so, a 30-check report on a well-specified model will usually show at least one flag. The nominal rate per check is itself unreliable for LMM residual tests. Observed rejection rates ranged from 0% to 77% at nominal 5% (L5-06). Per-check p-value thresholds therefore give neither error control nor a meaningful severity.


Handling. Flags never depend on p < alpha. The report states the number of checks run and the number of envelope exceedances expected under the model. Group checks by assumption family. Let the user pre-declare primary checks in the plan file (L5-17). Optionally, run a family-level calibration that applies the whole diagnostic pipeline to B simulate-and-refit datasets and reports where the observed number of exceedances falls in that null distribution. The cost is B x pipeline, so make it opt-in and parallel.


Parity. Counts of checks run and their registry IDs must match exactly across languages. Family-level calibration gets distributional parity.


Verifier's correction. Replace 'will usually show at least one flag' with: the number of flags expected under a correct model is unknown without family-level calibration. It can be large (about 79% chance of at least one with 30 independent 5% checks) or small (conservative checks).


Verifier's reasoning. The arithmetic is right: 1 - 0.95^k = 0.401, 0.642, 0.785 and 0.923. 'A 30-check report will usually show at least one flag' does not follow, however. Positive dependence among diagnostics usually lowers the familywise rate below the independence value, and actual per-check rates range from about 0% to about 81% (L5-06 replication). The expected number of flags therefore cannot be stated without the calibration that the handling already proposes. The handling itself is sound.


Evidence checked. Direct computation. Rejection-rate range from scratchpad/L5adv/d.py.


### L5-16 Grade severity by assessability, surprise and impact on declared estimands, not by significance

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. How serious a diagnostic finding is depends on (i) whether the assumption can be assessed at all (reliability, fraction of confounding, number of levels, singularity), (ii) whether the pattern exceeds what the fitted model itself produces (simulate-and-refit envelope, which absorbs the artefacts in L5-02 to L5-04 and L5-11), and (iii) how much the target inferences change. The same departure can matter or not depending on the estimand. Non-normal residuals with large N matter little for fixed-effect inference (Schielzeth et al. 2020) but matter for prediction intervals.


Handling. Require focal parameters and estimands to be declared in the Stream A spec. Without them, compute impact for all fixed effects and label it exploratory. For each check, the registry stores (a) a magnitude statistic on an interpretable scale, (b) an assessability rule and (c) an impact computation. The impact computation covers the change in focal estimates in SE units under the matching sensitivity refit or deletion, the robust/model SE ratio and whether the CI decision changes. Use ordered levels: 'not assessable', 'consistent with model', 'detectable, inconsequential', 'consequential', 'decision-changing'. Impact thresholds are documented conventions with rationale in the YAML (P29), shown in explain(id) and never presented as calibrated error rates.


Parity. Severity levels must be identical across languages for deterministic checks (exact tier). For simulation-based checks, require agreement of severity level in at least a set proportion of seeds.


Verifier's correction. Use two orthogonal fields: assessability (not assessable / weakly / adequately assessable) and finding (consistent / detectable-inconsequential / consequential). Report CI-decision changes as a separate descriptive flag. Fix the alternative model for each check in the registry, so that impact is not tuned post hoc.


Verifier's reasoning. Grading by impact on declared estimands rather than by significance is well motivated, and the Schielzeth et al. (2020) robustness summary for fixed effects is confirmed. That non-normality 'matters for prediction intervals' is sound reasoning, but it is not a Schielzeth finding. The ordered scale has a design flaw. It puts an epistemic dimension (assessability) on the same axis as severity. 'Not assessable' is not less severe than 'consistent with model'. 'Consistent with model' under low assessability or low power is easily read as reassurance. 'Decision-changing', defined by a CI crossing 0, brings back a significance threshold. Impact also depends on which alternative model the sensitivity refit uses, and that choice is itself a researcher degree of freedom.


Evidence checked. Conceptual analysis. Schielzeth summary via WebSearch (scholars.uky.edu record).


### L5-17 Prevent diagnostic-driven data dredging: no automatic re-specification, a logged specification history, pre-declared diagnostic plans

Kind: architecture. Stream: both. Priority: essential. Origin: new (P17). Verdict: correct.


Claim. Changing the model because of a diagnostic is a data-dependent analysis choice: a 'garden of forking paths' (Gelman & Loken 2013). The SEs and p-values of the final model do not account for that selection, even when every individual change looks reasonable. A UI that rewards a clean report ('fix until green') encourages this.


Handling. Stream A never changes the stated model. Every suggestion is phrased and run as a sensitivity analysis and reported next to the primary model in a primary-vs-sensitivity table (multiverse-style, Steegen et al. 2016). Every refit triggered by a diagnostic is logged in a specification history embedded in the results JSON and the report, with the check ID, the reason, the formula diff, the data hash and a timestamp. A report generated for a modified model carries a 'data-dependent specification' banner listing the changes. Support a pre-registrable diagnostic plan (YAML) that specifies the checks, the impact thresholds and pre-committed actions (e.g. 'if singular: remove the correlation first, then the slope of X') before the data are seen. Link this to Stream B's outcome-blind mode (P17). There is no single overall 'pass' indicator.


Parity. The specification-history schema is part of the shared JSON Schema (P29) and needs exact parity.


Verifier's correction. Add one sentence: pre-specified decision rules reduce analyst flexibility, but they do not make post-selection SEs valid.


Verifier's reasoning. Diagnostic-driven re-specification is a data-dependent choice, and the final model's SEs do not account for it. Logging, sensitivity tables and pre-declared plans are sound mitigations. The documentation needs one caveat. A pre-committed rule such as 'if singular, drop the correlation' is still a data-dependent selection, and inference after applying it is still conditional on that selection. Pre-specification limits forking paths but does not make the SEs selection-adjusted. I did not verify the Gelman & Loken and Steegen et al. citations.


Evidence checked. Conceptual analysis. References not checked.


### L5-18 BLUP intervals and cluster rankings understate uncertainty

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Posterior or conditional variances of BLUPs (the caterpillar-plot intervals) plug in theta_hat, and in some implementations also treat beta_hat as known. Replacing true variance ratios by estimates increases the mean squared error of the predictors (Kackar & Harville 1984), so these intervals are too narrow, most of all when clusters are few. Rankings of clusters (schools, classes, teachers) by BLUPs are very uncertain, and league-table readings are a known misuse (Goldstein & Spiegelhalter 1996).


Handling. Label caterpillar intervals 'conditional on estimated variance parameters'. Offer parametric-bootstrap intervals for BLUPs and for ranks. If ranks are shown, show rank intervals. Do not colour or flag clusters as 'significantly above/below average' from interval overlap. Sort caterpillar plots by estimate only with an explicit note that the sorted order itself is uncertain.


Parity. The plug-in conditional variances are deterministic (tolerance parity). Bootstrap intervals get distributional parity. The spec must state whether PEV includes beta_hat uncertainty (P-based vs V^-1-based).


Verifier's correction. Record, per engine, whether condVar includes beta uncertainty (P-based), theta uncertainty (TMB delta method) or neither (lme4 postVar, which conditions on beta_hat and theta_hat). Apply the 'too narrow' label only to the plug-in variants, and compute the package's own PEV from the contract for parity.


Verifier's reasoning. For lme4, the claim is right. The ranef Rd says condVar is 'conditional on the estimates of the model parameters', so it plugs in both beta_hat and theta_hat. It is not right for glmmTMB, whose ranef condVar comes from TMB sdreport. The documented sdreport covariance adds J V(theta_hat) J', the variance due to parameter estimation (generalised delta method). glmmTMB intervals therefore already include approximate parameter uncertainty, and the parity spec must record this. P-based PEV (G - G Z'PZ G) includes beta_hat uncertainty but not theta_hat uncertainty. The Kackar & Harville and Goldstein & Spiegelhalter citations were not verified.


Evidence checked. lme4 man/ranef.Rd. glmmTMB R/methods.R (ranef.glmmTMB uses summary(object$sdr,'random')). TMB R/sdreport.R roxygen documentation (all from raw.githubusercontent.com).


### L5-19 ICC and R2 with random slopes and GLMMs: values depend on the covariate, the scale and the approximation

Kind: correction. Stream: A. Priority: valuable. Origin: preliminary (P28). Verdict: partly_correct.


Claim. In a random-slope model, the cluster-level variance at covariate value x is sigma_0^2 + 2 sigma_01 x + sigma_1^2 x^2. An ICC computed from sigma_0^2 alone refers to x = 0 and changes when x is re-centred. Johnson's (2014) conditional R2 averages the random-effect variance over the observed design. It is invariant to centring when the intercept-slope covariance is estimated freely, but not under zero-correlation ('||') constraints, which make the model itself depend on centring. For GLMMs, latent-scale and observation-scale ICC/R2 differ, and the distribution-specific variance for non-Gaussian families can be approximated in several ways (Nakagawa, Johnson & Schielzeth 2017) that give different values. ICC and R2 are estimates with sampling uncertainty, and at a singular fit the ICC lies on the boundary (0).


Handling. With random slopes, report the variance partition as a function of x (curve over the observed range, Goldstein, Browne & Rasbash 2002), and add a single ICC only with 'at x = <value>' stated. Record the R2/ICC method and approximation as named IDs in the results JSON. Offer bootstrap intervals. When the fit is singular, attach a 'boundary estimate' note to any ICC or R2 involving the singular term.


Parity. The quantities are deterministic given the variance estimates, so tolerance parity applies, provided the same named approximation is used in both languages.


Verifier's correction. Attach the 'boundary estimate' note to the specific variance or correlation that is singular, and say that the ICC is 0 only when the intercept variance itself is at 0.


Verifier's reasoning. The covariate-dependent cluster variance and the dependence of an intercept-only ICC on centring are correct. Johnson's mean random-effect variance, averaged over the observed design, is invariant to re-centring under a freely estimated covariance, because z_i' Sigma z_i is reparameterisation-invariant at the ML/REML optimum. It is not invariant under '||' constraints. One statement overgeneralises: 'at a singular fit the ICC lies on the boundary (0)' holds only when the singular direction is the intercept variance. A singular fit with a correlation of +/-1, or a zero slope variance, can leave the intercept ICC well away from 0. The Nakagawa, Johnson and Goldstein references were not verified.


Evidence checked. Analytic reasoning. References not checked.


### L5-20 Singular and boundary fits: switch off the downstream diagnostics that become degenerate

Kind: feature. Stream: A. Priority: valuable. Origin: preliminary (P20). Verdict: partly_correct.


Claim. When a variance component is about 0, a correlation is about +/-1 or the relative covariance factor is rank-deficient, the BLUPs of that term are identically 0 or lie on a line. QQ plots, caterpillar plots, BLUP-vs-covariate plots, standardisation by Var(b_hat) (division by about 0), the fraction of confounding and random-effects leverage for that term are then all degenerate or undefined. In deletion diagnostics, a refit can switch between singular and non-singular, and that switch is itself the main influence finding.


Handling. In the registry, give each diagnostic declared prerequisites (non-singular term, at least k levels, converged fit, ordering variable present, etc.). When a prerequisite fails, the result is 'not assessable (reason)' with the reason code, not a plot. The influence output counts and lists singularity switches per deleted level (L5-08).


Parity. The singularity decision needs a shared tolerance rule in the spec (e.g. on the Cholesky-factor diagonal or eigenvalues of the relative covariance factor). Otherwise, R and Python will switch off different diagnostics on borderline fits.


Verifier's correction. Define singularity in the spec on a scale-invariant quantity, for example the eigenvalues of the random-effects covariance after scaling Z columns to unit SD, or of the correlation matrix together with the variance ratios relative to the variance attainable from the data. Report lme4's native isSingular alongside, for transparency. Describe singularity switches as an important influence finding, not the main one.


Verifier's reasoning. The lme4 isSingular Rd confirms the degeneracy mechanism, including that for q >= 3 a fit can be singular without any variance near 0 or correlation near +/-1. The parity point needs a correction. lme4's rule (lmer.R: singular <- min(opt$par - lower, upper - opt$par) < getSingTol(), default 1e-4) operates on theta, the relative Cholesky factor scaled by sigma. For a slope, that factor is in units of 1/x. Rescaling a slope covariate (e.g. milliseconds to seconds) changes theta by the scale factor and can flip the singularity decision for the same model. A shared rule copied from lme4 therefore inherits a dependence on predictor scale. 'That switch is itself the main influence finding' is overstated.


Evidence checked. lme4 man/isSingular.Rd. lme4 R/lmer.R line with getSingTol(). R/utilities.R getSingTol default 1e-4 (all from raw.githubusercontent.com/lme4/lme4/master).


### L5-21 Extend the fitted-model contract with P-based quantities and a canonical residual taxonomy

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new (P32). Verdict: correct.


Claim. Several diagnostics here need quantities beyond y, X, Z, beta, b and theta: studentised conditional residuals, the fraction of confounding, Var(b_hat) = G - PEV, leverage and one-step deletion. Each needs P, or V^-1 and (X'V^-1 X)^-1, plus the per-cluster PEV. A dense P is N x N, so for N = 50,000 it has 2.5e9 entries, about 20 GB in float64. These quantities must therefore come from sparse factorisations (e.g. the engine's Cholesky factor) or from block-diagonal algebra, which nested designs allow and crossed designs do not. Engine residual names do not correspond one-to-one across engines.


Handling. The P32 adapter should expose methods, not matrices: diag_P(), pev(term) and marginal_var_blup(term) (recording whether beta_hat uncertainty is included), solve_V(v), and leverage_fixed()/leverage_random(). Each method has a dense reference implementation, used only in tests, and a sparse production implementation. Define canonical residual IDs in the YAML spec (e.g. marginal_raw, marginal_cholesky, conditional_raw, conditional_pearson, conditional_studentized, blup_raw, blup_std_marginal, blup_std_posterior, quantile_sim_conditional, quantile_sim_unconditional, quantile_sim_cluster_aggregated). Every results-JSON entry records the residual ID, the scaling and the simulation conditioning.


Parity. Golden fixtures should compare diag(P), PEV and the standardised residuals across languages within numerical tolerance. Small dense fixtures allow exact checks of the sparse implementations.


Verifier's correction. Implement diag_P through hat values (1 - h_ii)/sigma^2 from the sparse penalised Cholesky factor. Use the block-diagonal algebra only as an optimisation for nested designs.


Verifier's reasoning. The memory figure is right: 50,000^2 x 8 bytes = 20 GB. A method-based adapter with dense test references is sound. Two points need sharpening. (1) With R = sigma^2 I, sigma^2 P = I - H, where H is the conditional hat matrix (verified numerically). So diag_P = (1 - h_ii)/sigma^2, and lme4's hatvalues.merMod already computes h_ii sparsely from L, Lambdat, Zt, RX and RZX. (2) Crossed designs do not need block-diagonal V, because sparse Cholesky of the q x q penalised system (lme4's approach) handles nested and crossed designs alike. Only the block-diagonal shortcuts are restricted to nested designs. The Hodges reference was not verified.


Evidence checked. scratchpad/L5adv/h.py (max |H - (I - sigma^2 P)| = 2.2e-16). lme4 R/lmer.R hatvalues.merMod source on GitHub.


### L5-22 Predictive checks need discrepancy statistics the model does not fit by construction

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. A simulation-based check is uninformative if its statistic is reproduced by construction. Examples are the overall mean, total variance and sum of residuals, cluster means under conditional simulation, and level-2 linear trends (L5-02). Plug-in parametric-bootstrap p-values are conservative when the statistic's mean depends on the parameters, and they concentrate near 1/2 (Robins, van der Vaart & Ventura 2000). The cluster-aggregated KS with plug-in parameters rejected 0% of the time under the true model (L5-06). Statistics aimed at the hierarchical structure have power against the misfits that matter.


Handling. Provide a library of hierarchical discrepancy statistics computed under unconditional simulation. Examples are the SD of cluster means relative to the pooled within-cluster SD, the skewness and max/min of cluster means, per-cluster within-SD dispersion, the proportion of all-0 and all-1 clusters (binary), the zero proportion per cluster (counts) and the within-unit lag-1 correlation. Show each as the observed value against its simulated distribution (interval plus the observed position). If a number is reported, calibrate it by simulate-and-refit (double bootstrap) and label it descriptive.


Parity. The statistic definitions get exact parity on fixed data. The simulated reference distributions get distributional parity.


Verifier's correction. Remove or demote the between/within SD ratio. State that cluster-mean statistics under conditional simulation are biased, not null. Keep shape statistics (skewness, extremes, heterogeneity of within-cluster SDs, zero or all-0/all-1 proportions, lag-1 correlation) under unconditional simulation, and state the B^2 cost of double-bootstrap calibration.


Verifier's reasoning. The principle (a discrepancy statistic must not be fitted by construction) and the Robins et al. citation are confirmed. The details have three errors. (1) Cluster means are not reproduced under conditional simulation. Simulated cluster means centre on mu + b_hat_j, but the observed ybar_j lies (1 - lambda_j)(ybar_j - mu) further out. Conditional simulation therefore makes the observed cluster means look systematically over-dispersed. That is a built-in false signal, not an uninformative statistic. (2) The overall mean and total variance are only approximately reproduced, because GLS gives 1'V^-1 r = 0, not 1'r = 0. (3) The first example in the handling, SD of cluster means relative to pooled within-cluster SD, is essentially a function of the ANOVA variance-component estimators, which equal REML in balanced designs. It is therefore close to fitted by construction and has little power. A double bootstrap also costs about B^2 refits.


Evidence checked. Analytic reasoning from b_hat_j = lambda_j (ybar_j - mu). Robins et al. abstract via WebSearch (statweb.rutgers.edu/ztan/material/robins-vandervaart-ventura.pdf).


## L6 Software architecture, packaging and reporting


### L6-01 Ship the check registry as compiled, schema-typed JSON (not YAML), vendored as byte-identical copies from a monorepo

Kind: correction. Stream: infrastructure. Priority: essential. Origin: preliminary (P29). Verdict: partly_correct.


Claim. Centralising checks (P29) is right. But vendoring YAML and parsing it at runtime in both languages causes silent parity bugs, because the two YAML loaders apply different YAML 1.1 implicit-typing rules. The reviewer verified with PyYAML 6.0.3 (a YAML 1.1 parser) that `1e-3` and `1.0e3` load as strings, `1.0e+3` as 1000.0, `no`/`NO` as False, `on` as True and `1.10` as the float 1.1. The R yaml package's implicit-type grammar (src/implicit.re) also classifies bare y/Y/n/N as booleans, which PyYAML keeps as strings. So a threshold written `1e-3` would be a string in Python. The Mustache spec project is a working precedent, authored in YAML and distributed as JSON for languages that lack good YAML tooling.


Handling. Use a monorepo with spec/ (YAML source), r/ (R package root), python/ (pyproject root), fixtures/ and parity/. A build step compiles YAML to canonical JSON (sorted keys, explicit types) and validates it against a JSON Schema that types every field, with thresholds as numbers with units and versions as strings. The build fails on any scalar whose type was inferred implicitly. Copy the JSON (no symlinks) into r/inst/spec/ and python/src/mixdiag/_spec/. Read it with jsonlite via system.file() in R and stdlib json via importlib.resources in Python, so neither package needs a YAML parser at runtime. Each package records the SHA-256 of its vendored copy, and CI fails if the copies differ from the compiled spec or from each other. Keep the R package installable from its subdirectory (remotes::install_github(subdir = 'r')). License the spec permissively so it can be vendored into both an R package (possibly GPL, since it depends on lme4) and a permissively licensed Python package.


Parity. Removes a whole class of type-coercion discrepancies, since both packages read the same bytes.


Verifier's correction. Keep compiling YAML to schema-validated JSON, but justify it with the real divergences: y/n booleans in R yaml only, comma-separated integers in R yaml, underscore integers in PyYAML, and version-like scalars such as 2026.1 or 2026.10 that become floats. `1e-3` is a string in both loaders. The build should require every version field to be quoted or schema-typed as a string. Both JSON readers must use the schema to coerce types: read with jsonlite::fromJSON(simplifyVector = FALSE) or with an explicit type map, and in Python cast numbers that are typed as double to float. A permissive spec licence is sensible, but importing lme4 does not by itself require the R package to be GPL.


Verifier's reasoning. The PyYAML behaviour is as stated. I reproduced every case with PyYAML 6.0.3: 1e-3 and 1.0e3 load as strings, 1.0e+3 as 1000.0, no/NO as False, on as True and 1.10 as 1.1, and y/n stay strings. The R yaml grammar (implicit.re) does make y/Y/n/N booleans. But the example used to show a cross-language bug is wrong. R yaml's FLOATEXP rule also needs a '.' and a signed exponent, so `1e-3` is a string in R yaml too. That is a bug both languages share, not a parity divergence. The real divergences are elsewhere. y/n are booleans in R and strings in Python. R yaml allows thousands separators (DIGITSC = [0-9,], so '1,000' becomes an integer), whereas PyYAML keeps such values as strings. Underscores work the other way: '1_000' is 1000 in PyYAML and not an integer in R yaml. Version-like scalars are a further trap: `2026.1` and `2026.10` both load as the float 2026.1 in PyYAML, which affects the registry-version example in L6-02. Compiling to JSON is sound, and the Mustache precedent is confirmed: its README says the spec is developed as YAML and JSON versions are provided best-effort. JSON still leaves some type ambiguity. jsonlite reads `5` as integer and `5.0` as double, Python as int and float. jsonlite's simplifyVector also turns arrays of objects into data frames and null into NA. So the schema, not JSON alone, must fix the types, and both readers must turn off auto-simplification. The licensing remark is overstated. Listing lme4 (GPL) in Imports does not by itself force the R package to be GPL, because a compatible licence is enough.


Evidence checked. Ran scratchpad/L6adv/t_yaml.py with PyYAML 6.0.3. Output: a:'1e-3', b:'1.0e3', c:1000.0, d:False, e:False, f:True, g:1.1, h:'y', i:'n', m(1_000):1000, n(2026.1):2026.1. Read the r-yaml implicit.re grammar (copy in scratchpad/L6/dl), in which FLOATEXP = SIGN? (DIGIT DIGITSC*)? "." DIGITSP* [eE] SIGN DIGIT+, BOOLYES and BOOLNO include y/Y/n/N, and INTCANON allows commas. Fetched the github.com/mustache/spec README, which states 'developed as a series of YAML files' and 'we also provide JSON versions of the specs on a best-effort basis'.


### L6-02 Version the registry and each check separately from the packages, and record effective thresholds in every result

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: preliminary (P29). Verdict: partly_correct.


Claim. Changing a threshold, severity or algorithm of an existing check changes outputs for unchanged inputs, so the registry needs its own version, separate from package versions, recorded in every result. The two packages' releases cannot be kept in sync: CRAN policy asks established packages to submit updates 'no more than every 1–2 months', and PyPI has no such limit. The R and Python packages will therefore often run different registry versions.


Handling. (1) Each check gets an integer check_version, bumped whenever its decision rule, threshold or algorithm changes. (2) The registry gets its own semantic version: major when some existing check can return a different status for the same input, minor when checks are added and patch for wording or docs only. (3) Every result row carries (check_id, check_version). The result header carries registry_version, registry_sha256 and the effective thresholds after user overrides. (4) Ship the current registry plus earlier threshold snapshots, so a user can reproduce an old report with registry = '2026.1' when only thresholds changed. Algorithm changes still need the old package version, and explain() should say so. (5) Define parity per registry version and keep a compatibility matrix (R x.y, Python a.b, registry). When two results carry different registry versions, the harness reports 'not comparable' rather than a mismatch.


Parity. Parity is defined between identical registry versions, not identical package versions.


Verifier's correction. Give each check a check_version and record the effective thresholds per check. Version the registry with a string-typed scheme, either semver or calendar but not both, and never as a bare YAML scalar. The parity harness should compare rows whose (check_id, check_version, effective thresholds) match and mark only the other rows 'not comparable'. Releases can be synchronised at CRAN's cadence if wanted, so independent releases are a choice, not a necessity.


Verifier's reasoning. Versioning checks and the registry separately is sound, and I confirmed the CRAN wording: once a package is established, updates 'no more than every 1--2 months' seem appropriate. But 'the two packages' releases cannot be kept in sync' is overstated. They can be synchronised by releasing Python at CRAN's pace, at some cost in agility. The proposal also contradicts itself: it says 'semantic version' but then uses a calendar-style example, registry = '2026.1'. Unless that value is a string, YAML turns it into the float 2026.1, and '2026.10' collides with it (see L6-01). The 'major' rule (any existing check can change status) will apply to almost every threshold change, so semver numbers will grow fast and carry little information. Reporting 'not comparable' for whole results whenever the registry versions differ is too coarse, because comparability can be decided per check through (check_id, check_version) and the effective thresholds. Replaying old threshold snapshots is fine, provided thresholds are stored per check_version.


Evidence checked. grep of the CRAN policy texinfo (eddelbuettel/crp copy in scratchpad/L6/dl/crp.texi), line 539: 'no more than every 1--2 months'. PyYAML loads 2026.1 as a float (L6adv/t_yaml.py).


### L6-03 'Exact parity for data audits' holds only for integer/string outputs: threshold flags and tolerance-based decisions flip across languages

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P29). Verdict: correct.


Claim. Exact parity holds only for counts, level sets and ID mappings. Any flag that compares a floating-point statistic with a threshold can flip between languages near that threshold, because algebraically identical computations differ in the last bits. The reviewer verified this: the VIF of the same predictor was 2.4440510230409385 via diag(inv(corr)) and 2.4440510230409349 via 1/(1−R²), and 0.1*3 != 0.3. Tolerance-based algorithms differ far more. R's qr() (default LINPACK dqrdc2, tol = 1e-07) treats a column as negligible when its norm after projection is small relative to tol, while numpy.linalg.matrix_rank uses SVD with tol = σ_max·max(n,p)·eps (≈4.4e-14 relative for n = 200). With x2 = x1 + 1e-9·noise (residual-norm ratio ≈ 9.5e-10, below 1e-7), numpy reports full rank 3, whereas a 1e-7 column-norm rule declares x2 deficient. The R-side behaviour is taken from ?qr, not run in R.


Handling. (1) Evaluate count-based rules in integer arithmetic: n_obs >= 5*n_groups, never mean(n_j) >= 5. (2) Store each rule's comparator (> or >=) and threshold in the registry. Compute flags on unrounded values, and store value, threshold and relative margin in the result row. (3) In the parity harness, require equal flags only when |value − threshold| > tol_abs + tol_rel·|threshold|. Inside that band, require only that the values agree, and label the row 'borderline'. (4) Specify every tolerance-dependent algorithm in the registry (rank detection, plus 'variance near 0' and 'correlation near ±1' for singularity), including column scaling, and implement it in both packages instead of relying on qr() or matrix_rank defaults. Report lme4's own rank-deficiency or column-dropping decision separately, as engine behaviour.


Parity. Prevents spurious parity failures and spurious agreement, and makes the harness deterministic for near-threshold cases.


Verifier's reasoning. I reproduced the core numerical claims. With x2 = x1 + 1e-9·noise and n = 200, numpy.linalg.matrix_rank returns 3. The relative tolerance σmax·max(n,p)·eps is 4.44e-14. |R_33|/||x2|| is 9.1e-10, far below the 1e-7 in ?qr (default LINPACK dqrdc2, tol = 1e-07), so a 1e-7 column-norm rule would flag x2. '0.1*3 != 0.3' is trivially true. I did not rerun the VIF last-digit example, but such discrepancies are expected. The handling (integer arithmetic for counts, stored comparators, a borderline band, rank and singularity algorithms specified in the registry, and lme4's own decision reported separately) is appropriate. One caveat concerns the report. Inside the band, the two languages can show users different flags, so the margin there should appear in the report as well as in the parity harness. lme4's own column dropping (via its check.rankX control) also uses a 1e-7 QR tolerance, so the shared rule should either reproduce it or explain why it differs.


Evidence checked. Ran scratchpad/L6adv/t_num.py: matrix_rank = 3, |R_kk|/colnorm = 9.14e-10, sv ratio = 4.56e-10, tol = 4.44e-14. ?qr (r-source qr.Rd, copy in scratchpad/L6/dl): qr.default(x, tol = 1e-07, LAPACK = FALSE), LINPACK dqrdc2 by default.


### L6-04 Simulation-based diagnostics: split simulate() from summarise() so the deterministic part is tested exactly

Kind: correction. Stream: A. Priority: valuable. Origin: preliminary (P35). Verdict: partly_correct.


Claim. P35 overstates the problem. The built-in RNG streams cannot be matched: R uses Mersenne-Twister with set.seed() scrambling, 'Inversion' normals and sample.kind 'Rejection' (since R 3.6.0), while numpy's Generator uses PCG64 by default. But identical simulation inputs across languages are easy to get by passing pre-generated draws. Everything downstream of the draws can then be tested exactly: randomised PIT/quantile residuals computed from a given n×nsim matrix of simulated responses plus given uniform draws, and envelope quantiles. Only the simulation step itself needs distributional testing.


Handling. Split every simulation-based check into two parts. simulate() is engine- and RNG-specific. summarise(sims, observed, u) is pure and specified in the registry, with the PIT randomisation uniforms as an input and the tie-handling rule for discrete outcomes defined. Golden fixtures include shared simulation matrices and uniforms, so summarise() must agree to within 1e-12. Distributional tests of simulate() use a fixed seed in each language (deterministic, non-flaky CI) and pre-specified equivalence margins, e.g. TOST on the mean and SD of PIT values or a bound on the KS distance, with nsim large enough that the margin is detectable. Provenance records the seed and the RNG kind, which is RNGkind() in R (including normal.kind and sample.kind) and the bit generator in numpy.


Parity. Turns most of P23 (DHARMa-style residuals) from 'distributional parity' into exact parity and leaves only the simulator in the distributional tier.


Verifier's correction. P35's headline should be 'RNG streams are impractical to match, so share the draws rather than the seeds'. Specify in the registry the simulation estimand (conditional or unconditional on b, components included) and the PIT and tie rule. Test summarise() exactly on shared matrices. Test each simulate() against shared fixture parameters, not each engine's own estimates, using pre-specified equivalence margins.


Verifier's reasoning. The R RNG facts match ?Random: Mersenne-Twister with seed scrambling, Inversion for normals and the sample.kind 'Rejection' default since R 3.6.0. numpy default_rng uses PCG64. Splitting simulate() from summarise() is sound. For discrete outcomes, the PIT with given uniforms, min + u·(max − min) with min/max = ecdf(sim)(y−1) and ecdf(sim)(y), involves only counts divided by nsim, so exact agreement is achievable. There are three overstatements. (1) 'RNG streams cannot be matched' is not strictly true. numpy still provides MT19937, and R's set.seed scrambling and its 32-bit unif_rand could be reimplemented. It is impractical and fragile, not impossible. (2) Distributional tests of simulate() across languages compare simulators fed with different fitted parameters, since the two engines' fits differ. Feed both simulators shared parameters from the fixture, or test each against the known generating distribution. (3) The simulation semantics are model logic, not RNG, and must be fixed in the registry: conditional versus unconditional simulation (resample b or condition on b̂, see lme4's re.form), whether to include dispersion and zero-inflation, and the integer-response rule. Otherwise, the 'distributional tier' compares different estimands. A fixed seed makes CI deterministic, but any upstream change in an engine or numpy can shift it, which is acceptable if documented.


Evidence checked. grep of r-source Random.Rd (copy in scratchpad/L6/dl/RNG.Rd): 'sample.kind can be "Rounding" or "Rejection"', with the pre-3.6.0 non-uniformity note and the seed scrambling text. The derivation of the discrete PIT is from first principles, not run.


### L6-05 Fit parity: compare objectives and cross-evaluate them rather than parameters (the REML log-likelihood depends on how X is parameterised)

Kind: correction. Stream: A. Priority: essential. Origin: preliminary (P29). Verdict: partly_correct.


Claim. For 'comparable fits' (same model, two engines), comparing parameter estimates against a fixed tolerance is the wrong test. Near-flat or boundary likelihoods (singular fits, correlations near ±1) let two engines stop at visibly different θ with essentially equal objectives. Objective values need care too. statsmodels MixedLM's REML llf equals the textbook restricted log-likelihood −½[(n−p)log2π + log|V| + log|X′V⁻¹X| + r′V⁻¹r] (verified to 1e-6), and that quantity changes with the parameterisation of X. Rescaling a predictor by c shifts the REML llf by −log|c|, while the ML llf and all variance estimates stay the same. The reviewer verified this: x→10x changed the REML llf by −2.302585 (= −log 10), the ML llf by 0 and the variance estimate by less than 1e-15.


Handling. Tier-2 parity checks three things, in order. (a) The objective at each engine's optimum. (b) Cross-evaluation: each engine's objective at the other engine's estimates (lme4's deviance function via devFunOnly and statsmodels MixedLM.loglike(params)). The fits count as equivalent if both differences are below 1e-4 on the deviance scale, even when θ differ. (c) Parameters, only for fits flagged non-singular and well-conditioned. A reference implementation of the textbook formula, run on small fixtures, arbitrates. Compare REML values only when X is identical (same contrasts, scaling and column order). Reports must never compare REML llf or AIC across models with different fixed effects or codings, including before and after the rescaling suggested in P16. They should print that caveat whenever two REML fits are tabulated together.


Parity. Avoids false parity failures on singular or flat fits, and makes REML-based numbers comparable only where they are meaningful.


Verifier's correction. Use objective-based parity with cross-evaluation for Gaussian LMMs, state the θ mapping explicitly and use a relative or optimiser-linked tolerance. Either compare REML only when X is identical, or compare a parameterisation-invariant REML (+½log|X'X|) defined in the registry. Do not promise tier-2 parity for GLMMs across languages. Have the report block REML comparisons across different X rather than only printing a caveat.


Verifier's reasoning. I verified the empirical claim with statsmodels 0.15.0. Rescaling x to 10x shifted the REML llf by −2.3025851 (= −log 10) and the ML llf by −2.8e-14, and changed the variance by 1.4e-16. In general, a reparameterisation X → XA shifts the REML llf by −log|det A|, so changing contrasts (treatment versus sum) shifts it too, not only scaling. A parameterisation-invariant REML (adding ½log|X'X|) could be defined in the registry as the parity quantity. Cross-evaluation is feasible for LMMs. MixedLM.loglike(params, profile_fe=True) profiles out β and σ², as lme4's devFunOnly does for lmer, but it needs θ mapped across engines: θ_lme4 = vech(chol(cov_re/σ²)) in lme4's ordering. The handling has three gaps. (1) For GLMMs, statsmodels has no Laplace or AGQ likelihood (its Bayesian mixed GLMs are variational), so tier 2 is effectively LMM-only across languages. Within R, lme4 and glmmTMB differ in their approximations, parameter sets and constants. (2) An absolute deviance tolerance of 1e-4 ignores the scale of the deviance and the optimisers' own tolerances. It should be relative or tied to the optimiser. (3) Advising never to compare REML across fixed-effect structures is standard, but 'print the caveat whenever two REML fits are tabulated' does not stop the comparison. The report should refuse to compute REML-based LRT or AIC differences across different X.


Evidence checked. Ran scratchpad/L6adv/t_opt.py: REML shift = -2.3025850929940646 vs -log10 = -2.302585092994046, ML shift = -2.8e-14, variance difference = 1.4e-16, inspect.signature(MixedLM.loglike) = (params, profile_fe=True).


### L6-06 Fitted-model contract must fix units and parameterisation, use sparse matrices, use canonical column names and declare capabilities

Kind: architecture. Stream: A. Priority: essential. Origin: preliminary (P32). Verdict: partly_correct.


Claim. Engines expose variance parameters on different scales, so the contract must fix units and parameterisation. The reviewer verified with statsmodels 0.15.0 that MixedLMResults.params reports 'g Var' = 0.5387, which equals cov_re_unscaled = τ²/σ², while cov_re = 0.5940 is τ², with scale σ² = 1.1026. lme4's θ is the relative Cholesky factor (Σ_b = σ²ΛΛ′). An adapter that reads 'the variance parameters' naively is therefore off by a factor of σ², or by a square root. Fixed-effect column names also differ by engine. R uses 'condB' and 'x:condB', patsy and formulaic use 'cond[T.B]', and formulaic's 'sort' ordering names the interaction 'cond[T.B]:x'.


Handling. Contract v1 contains the family and link, the REML flag and the objective at the optimum, plus an optional callable objective(params) for cross-evaluation. It contains β and vcov(β), the absolute covariance matrix for each grouping factor (SDs and correlations derived in shared code, engine-native parameters kept separately), σ² or dispersion, and the conditional modes b with their conditional variances. It contains X and Z as sparse matrices plus grouping index vectors (never dense Z or V) and the row indices used after NA deletion. It also contains convergence info (optimiser, codes, messages, gradient, Hessian eigenvalues if available) and residual types named by definition (conditional, marginal, Pearson, deviance). Map fixed-effect columns to canonical names built from term labels and levels (e.g. 'cond=B', 'x:cond=B'), keeping engine names as an attribute. Capability flags (e.g. has_conditional_var, objective_callable, supports_refit) let a check that needs a missing capability return status 'not_available' instead of being dropped silently. Results record contract_version.


Parity. Without canonical units and names, the same fit produces non-matching JSON from the two packages.


Verifier's correction. Write the scale relation per family: Σ_b = σ²ΛΛ' for lmer, ΛΛ' for glmer, and glmmTMB's own theta transform. Give the contract a 'component' dimension (cond, zi, disp), each with its own β, vcov and random-effects covariances. Mark capabilities per component.


Verifier's reasoning. I verified the statsmodels part: on my data, MixedLMResults.params['g Var'] equals cov_re/scale (1.6615e-10 = 1.9324e-10/1.1630). For column names, patsy gives 'x:cond[T.B]', and statsmodels with formulaic and ordering='sort' gives 'cond[T.B]:x'. R's 'x:condB' is standard model.matrix naming. The claim about lme4's θ is right only for lmer, where Σ_b = σ²ΛΛ'. For glmer (binomial or Poisson), there is no σ², so Σ_b = ΛΛ'. glmmTMB uses yet another parameterisation (log-SDs plus transformed correlation parameters) and has several model components (conditional, zero-inflation, dispersion), each with its own β and vcov. A contract keyed only on 'σ² or dispersion' and one β, vcov(β) cannot represent glmmTMB zero-inflated or dispersion models. The rest of the handling (absolute covariance matrices, sparse X/Z, row indices, capability flags, contract_version) is sound.


Evidence checked. Ran scratchpad/L6adv/t_opt.py: params 'g Var' = 1.66149e-10, cov_re = 1.93236e-10, scale = 1.16303, ratio = 1.66149e-10. With ordering 'sort', the exog_names include 'cond[T.B]:x'. The glmer and glmmTMB parameterisation comes from knowledge of lme4 and glmmTMB. I did not fetch it in this session.


### L6-07 Do not translate lme4 formulas into statsmodels formula strings: parse to a canonical AST and build design matrices yourself

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P30). Verdict: partly_correct.


Claim. P30 implies a parser that translates lme4 syntax into statsmodels formula strings. That route inherits Python formula semantics that diverge from R. The reviewer verified three divergences with statsmodels 0.15.0, patsy 1.0.3 and formulaic 1.2.2. (a) patsy raises SyntaxError for a column named `class` and NameError for `school.id` (it parses the dotted name as attribute access), whereas formulaic accepts both. Both names are common in education data. (b) patsy's standardize() uses ddof = 0, so it differs from R's scale() (n − 1 denominator) by a factor of sqrt(n/(n−1)), which is 1.069 at n = 8. formulaic's scale() matches R. (c) statsmodels has process-global options formula_engine ∈ {patsy, formulaic} (default patsy) and ordering ∈ {legacy, degree, sort, none}. With formulaic ordering 'none', `x:cond + cond + x` produces full-dummy columns x:cond[A], x:cond[B], x:cond[C] plus cond[T.B] and cond[T.C], a different parameterisation from R's.


Handling. Define the shared grammar as an explicit lme4 subset, with an EBNF in the registry: + and −, 0/1 intercepts, :, *, ^, (expr | g), (expr || g), g1/g2 nesting and g1:g2. Whitelist in-formula functions with defined semantics: log, exp, I(), scale with n − 1. Exclude poly() unless it is implemented identically in both languages. Both packages parse to a canonical JSON AST: fixed terms expanded in R's degree order, random-effects terms with nesting expanded, explicit intercept flags and the factor-versus-numeric expansion of `||` (see P18). In R, build the AST from lme4's own findbars()/nobars() and terms(). Test the Python parser against golden ASTs generated in R. The Python package builds X and Z itself from the AST, the data and the registry's contrasts, or else pins and records the formula engine and ordering locally without touching global options. It never passes a user-written formula string to patsy. Stream B warns about reserved or non-syntactic column names and backtick-quotes them in any formula it generates.


Parity. Formula interpretation is the largest single source of silent cross-language model differences (different X means a different model).


Verifier's correction. Rest the AST-first design on the global formula_engine and ordering options and on R-compatible term ordering, coding and contrasts, not on patsy being unable to quote names. patsy's Q() and standardize(ddof=1) solve (a) and (b). Correct the exception type for `school.id` to PatsyError, which wraps the evaluation failure.


Verifier's reasoning. I reproduced the observations. patsy raises SyntaxError for `class`. For `school.id`, it raises an error, though the type I saw was PatsyError (wrapping the evaluation failure), not a bare NameError. formulaic accepts both. patsy's standardize() defaults to ddof = 0 and formulaic's scale() matches ddof = 1. statsmodels.formula.options exposes formula_engine (default patsy) and ordering (default legacy). With formulaic and ordering 'none', `x:cond + cond + x` gives Intercept, x:cond[A], x:cond[B], x:cond[C], cond[T.B], cond[T.C], with no x column, a different parameterisation from R's. But reasons (a) and (b) are overstated as arguments against translation. I checked that patsy handles both names with Q('class') and Q('school.id') and that standardize(x, ddof=1) matches R. The decisive reasons are the process-global options and the ordering semantics, plus the need for exact control over contrasts. The recommended route (canonical AST, building X and Z yourself) is sound and directly supported, since statsmodels MixedLM accepts endog/exog/exog_re/exog_vc arrays without a formula. Building Z yourself also means you must map crossed random effects onto statsmodels' variance-component structure. That mapping is out of scope for me but costly to implement.


Evidence checked. Ran scratchpad/L6adv/t_form.py and t_opt.py (statsmodels 0.15.0, patsy 1.0.3, formulaic 1.2.2). patsy 'y ~ class' gives SyntaxError and 'y ~ school.id' gives PatsyError, while Q('class') and Q('school.id') work. standardize(x) matches R: False, standardize(x, ddof=1): True, formulaic scale(x): True. ordering='none' gives ['Intercept','x:cond[A]','x:cond[B]','x:cond[C]','cond[T.B]','cond[T.C]'].


### L6-08 Default factor-level order (and so the reference level) depends on language and locale, and Unicode or whitespace variants silently split levels

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Identical data can get different default reference levels in R and Python. R's factor() orders levels with order(). For character vectors, that uses the 'shell' method with the current locale's collating sequence, and only method = 'radix' gives C-locale order (per ?order, ?sort and base/R/factor.R). pandas Categorical and Python sorted() use code-point order, so for c('apple', 'Banana'), Python and R's C locale put 'Banana' first, while typical English linguistic collations put 'apple' first. The treatment-contrast reference level, and therefore the meaning of every 'main effect' (P10), then depends on language and locale. Separately, the NFC and NFD forms of 'café' print identically but are distinct levels (pandas created 2 categories), and so are trailing-space variants such as 'Control ' versus 'Control'.


Handling. The registry rule uses user-declared levels and otherwise orders by code point after NFC normalisation, implemented in R with order(method = 'radix'). Results list the levels and the reference level for each factor, and the report prints the baseline category. A new Stream B check flags levels that collide after NFC normalisation, case folding or whitespace trimming, as likely data-entry duplicates that split groups and cells. It also flags numeric-looking string levels that sort lexicographically ('10' before '2'). Record LC_COLLATE in provenance.


Parity. Without this rule, coefficients, contrasts and cell-level checks can differ between the R and Python packages while each is 'correct'.


Verifier's correction. Use existing factor levels or user-declared levels first, and otherwise code-point order after NFC, in R via order(method = 'radix'). Always apply the levels explicitly before handing data to the engine, and tell R users this may differ from their locale's default. Run CI under both C and en_US.UTF-8 locales. Report NFC and whitespace collisions as warnings and case-only collisions as notes.


Verifier's reasoning. The mechanism is right. factor() computes levels with order(y) (factor.R). ?order says that method 'auto' means radix only for short non-character vectors and shell otherwise, and that, except for radix, the character sort order depends on the locale's collating sequence. Python and pandas sort by code point, and NFC/NFD forms are distinct categories. There are four caveats. (1) In C or C.UTF-8 locales, which are common in Docker and CI, R also gives code-point order, so CI may never show the divergence that users on en_US see. Test under a non-C locale. (2) The proposed default (code-point order via radix) is an intended departure from what R users get from lm() or lmer() on the same data. Users comparing with their own lmer() call will see different reference levels. The package must write the levels into the data it passes to lme4 and state prominently that it does so. (3) Many R users pass factors whose levels were already set (read.csv no longer creates factors by default since R 4.0, but readr or haven labelled imports often set levels). Existing factor levels must be respected as 'user-declared'. (4) Flagging collisions after case folding risks false positives where case is meaningful (e.g. item codes 'a1' and 'A1'). Make it a note, not a warning. The 'sorts lexicographically' check for numeric-looking strings is valuable.


Evidence checked. grep of r-source factor.R (line 28: ind <- order(y)) and order.Rd (lines 44-46 and 60-61: auto means radix for short non-character vectors, otherwise shell, and except for radix the order depends on the locale collating sequence). Copies in scratchpad/L6/dl. The earlier t1.py output in scratchpad/L6 shows pandas making 2 categories for NFC vs NFD.


### L6-09 Default JSON writers in both languages silently lose precision or change the shape of results

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. jsonlite::toJSON defaults to digits = 4 decimal digits, so a variance of 1.234e-4 is written as 0.0001. digits = NA uses '%.15g', which fails to round-trip most doubles: 93,787 of 100,000 standard-normal draws failed in a test, versus none with '%.17g'. auto_unbox = FALSE writes scalars as one-element arrays. Numeric NA, NaN and ±Inf become the strings "NA", "NaN", "Inf" and "-Inf". For row-wise data frames, the default na = 'NA' drops the field. In Python, json.dumps writes NaN and Infinity, which is not valid JSON, unless allow_nan = False. numpy.int64 raises TypeError. pandas.to_json defaults to double_precision = 10, so 1.234567890123456e-7 is written as 0.0000001235.


Handling. Define one JSON Schema for results and write a schema-driven serialiser in each language. Unbox scalars according to the schema, write doubles with 17 significant digits (digits = I(17) or sprintf('%.17g') in R, repr in Python) and type integers as integers. Write non-finite values as null with a sibling status field, value_status ∈ {ok, nan, inf, neg_inf, not_computed}, and make missing fields explicit. CI runs round-trip tests in both directions (write in R and read in Python, and vice versa), requiring bitwise equality of doubles, and validates every golden output against the schema.


Parity. Prerequisite for any JSON-based parity test. Default settings would make tiny variances (the singular-fit diagnostics) read as 0 or as 1e-4.


Verifier's correction. Restate the precision risk: with the defaults, values roughly in (1e-5, 1e-4) lose most precision and values above 1e-4 keep only 4 decimals, while very small values keep about 5 significant digits. Either way, the default output is unsuitable. Choose one canonical number text format for both writers, e.g. '%.17g' in both or shortest round-trip in both. R has no built-in shortest-repr. Compare parsed values, never JSON bytes, unless both use the same format.


Verifier's reasoning. The claim is mostly confirmed. toJSON defaults to digits = 4 and auto_unbox = FALSE. Non-finite numerics become "NA", "NaN", "Inf" and "-Inf" strings. digits = NA uses '%.15g', and in my test 93,909 of 100,000 normal draws failed to round-trip, versus 0 with '%.17g'. json.dumps writes NaN, and numpy.int64 raises TypeError. pandas to_json writes 1.234567890123456e-7 as 0.0000001235. But the consequence for tiny variances is overstated. jsonlite's num_to_char uses fixed decimals only when 1e-5 < |x| < 2^31. For |x| <= 1e-5, it falls back to '%.*g' with ceil(max(1, log10|x|) + digits) = 5 significant digits. So a near-zero variance such as 1e-10, the typical singular-fit value, is written about right (1.0000e-10), not as 0. Only values roughly between 1e-5 and 1e-4 collapse to 0 or 0.0001. Also, 'doubles with 17 significant digits (Python: repr)' is inconsistent. repr writes the shortest round-tripping string, which in my test never matched '%.17g' text (0 of 1,000). Both round-trip bitwise, but the JSON text differs between languages, so any hash or text diff of the JSON files fails. I(17) is valid in jsonlite (sig_digits = min(17, digits)).


Evidence checked. Read jsonlite src/num_to_char.c (copy in scratchpad/L6/dl): the branch `precision > -1 && precision < 10 && fabs(val) < 2147483647 && fabs(val) > 1e-5` uses fixed decimals, otherwise `decimals = ceil(fmin(17, fmax(1, log10(fabs(val))) + precision))` with '%.*g', and NA digits gives '%.15g'. toJSON.R defaults: digits = 4, auto_unbox = FALSE. Ran scratchpad/L6adv/t_num.py: %.15g fails 93909, %.17g fails 0, repr == %.17g text 0/1000, pandas gives {"0":0.0000001235}, int64 gives TypeError and json.dumps(nan) gives NaN.


### L6-10 Two-layer parity harness: committed goldens inside each package, live cross-language diff in monorepo CI only

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new (P29). Verdict: partly_correct.


Claim. Cross-language parity tests cannot run on CRAN or on a PyPI user's machine, because neither environment has the other language. So golden outputs must be committed, and the live comparison must be a separate monorepo CI job. CRAN also requires checks to use as little CPU time as possible, which limits what layer 1 can run.


Handling. Layer 1 runs inside each package, is CRAN-safe and takes seconds. It runs the checks on tiny synthetic fixtures and compares the results with committed expected-results JSON, using the tier rules (exact, numerical tolerance per L6-03 and L6-05, engine-specific). Layer 2 runs only in monorepo CI: both packages run on the full fixture corpus, their JSON is diffed under the tier rules and a parity report is published. An intended change regenerates the goldens in a reviewed commit that also bumps the registry or check version. The corpus has, for every check, at least one positive and one negative case, plus adversarial cases: reused inner IDs, NFD strings, reserved or dotted column names, an all-NA group, singleton groups, empty interaction cells and a 10^6-row smoke test generated on the fly rather than stored. Prefer synthetic data with known generating parameters, which allows parameter-recovery tests and avoids licence questions about datasets distributed inside GPL packages. Store doubles as '%.17g' text or as dyadic rationals (exact in binary), and include a fixture self-test that parses each file in both languages and compares hashes of the parsed values.


Parity. Defines how parity is enforced continuously without requiring R in Python CI or Python on CRAN.


Verifier's correction. Keep both layers. Make layer 1 exercise every feature with tiny fixtures, as CRAN requires. Validate goldens against independent references, not only through cross-language agreement. Keep the corpus shipped in the package within CRAN's size guidance and the full corpus in the monorepo.


Verifier's reasoning. The two-layer split is sound, and the CRAN text is confirmed: 'Checking the package should take as little CPU time as possible'. But the same paragraph continues: 'do ensure that the checks that are left do exercise all the features of the package'. Layer 1 therefore cannot be so thin that it skips whole features on CRAN, and a tiny lmer fit per feature is still needed. 'Neither environment has the other language' is better put as 'cannot be relied on': CRAN machines may have Python, but a package cannot depend on it. An unaddressed risk is that goldens produced by the package itself and 'regenerated in a reviewed commit' can record bugs as expected output. At least some goldens must be validated independently (the textbook reference implementation from L6-05, hand-computed counts or parameter recovery), not only checked for agreement between R and Python. Golden JSON files shipped in the R package count towards the CRAN size guidance (5 MB for data, 10 MB tarball, both confirmed), so keep them small.


Evidence checked. grep of the CRAN policy copy (scratchpad/L6/dl/crp.texi, lines 225-262): 'as little CPU time as possible ... do ensure that the checks that are left do exercise all the features of the package', 5MB data/documentation and tarballs 'should if possible not exceed 10MB'.


### L6-11 One logic-less HTML template shared across languages, with all formatting done in a shared view model, strict escaping and a Quarto export that never refits

Kind: architecture. Stream: both. Priority: essential. Origin: preliminary (P31). Verdict: partly_correct.


Claim. A single report template can be shared across languages if the template has no logic and all formatting happens before templating. Mustache is a suitable format, with a language-agnostic spec and JSON test files. `{{x}}` HTML-escapes by default, whereas `{{{x}}}` does not. Implementations exist in R (whisker, GPL-3) and Python (chevron, whose last release was 0.14.0 in January 2021). Given chevron's age, a small in-house renderer tested against the spec's JSON tests is a fallback. If number formatting is left to each language (R format()/sprintf versus Python format), the two reports will differ even when the JSON agrees.


Handling. The pipeline is results JSON → shared view-model builder (registry formatting rules: significant digits, p-value display, message templates with placeholders) → Mustache template and CSS vendored with the registry → one self-contained HTML file with images as data URIs and no external JS, CSS, fonts or CDN calls. The file then works offline and contacts no third party when opened. Plots are drawn natively (ggplot2/matplotlib), but their inputs (bins, quantiles, plotting positions, envelopes) come from shared logic and are stored in the JSON, so they are parity-tested even though pixels are not. Escape every data-derived string (column names, level labels, IDs), because a level label containing '<script>' would otherwise execute in the report. Plots are static by default, and interactive widgets are opt-in because they embed row-level data (L6-13). The optional .qmd export reads the results JSON, verifies its SHA-256 and prints values inline. It never refits the model, so manuscript numbers stay traceable to one stored result.


Parity. The report becomes a pure function of the JSON, so report parity reduces to JSON parity plus plot-input parity.


Verifier's correction. Use Mustache with spec-tested renderers: whisker in R, pystache (maintained, spec 1.1.3) or chevron in Python, or an in-house renderer, all run against the spec's JSON tests. Allow interpolation only into HTML text and double-quoted attributes, and encode any script-embedded data with a dedicated JSON-in-HTML encoder. Implement the view-model formatting with printf semantics in both languages and parity-test the rendered strings.


Verifier's reasoning. I confirmed that the Mustache spec is language-agnostic, with YAML and JSON test files, and that its HTML-escaping test escapes & " < >. whisker is GPL-3 (version 0.4.1, published 2022-12-05). chevron's last release is 0.14.0 (2 January 2021). The claim misses a maintained Python option. pystache 0.6.8 (March 2025, MIT) states that it passes all tests of spec v1.1.3, so an in-house renderer is not the only fallback. Escaping is incomplete for some contexts. The spec's escaping does not cover single quotes, nor contexts other than HTML text and double-quoted attributes. Strings placed inside <script> (e.g. inline JSON for widgets), URLs, CSS or single-quoted attributes need context-specific encoding: escaping '</' in inline JSON and validating that data URIs are base64. The template must restrict interpolation to text and double-quoted attributes. The 'shared view-model builder' is one specification implemented twice, so formatting can still diverge (R format() and signif() versus Python round() and f-strings). Use printf-style formatting, which both delegate to C, and add parity tests on the formatted strings. Plot-input parity is a good idea.


Evidence checked. WebFetch of github.com/mustache/spec (README: YAML source plus JSON versions) and raw specs/interpolation.yml (the HTML Escaping test renders '& " < >' as '&amp; &quot; &lt; &gt;', and the single quote is not mentioned). WebFetch of the raw cran/whisker DESCRIPTION: License GPL-3, Version 0.4.1, published 2022-12-05. pypi.org/project/chevron: 0.14.0, 2 January 2021, MIT. pypi.org/project/pystache: 0.6.8, 18 March 2025, MIT, 'passes all tests in version 1.1.3 of the spec'.


### L6-12 QQ plotting positions (and therefore envelopes and lineups) differ by default between R, scipy and statsmodels

Kind: edge_case. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. The default QQ plotting positions differ, so 'the same' QQ plot or lineup is not the same across languages. R's qqnorm() uses ppoints(n) = (i − a)/(n + 1 − 2a), with a = 3/8 for n ≤ 10 and 1/2 otherwise. scipy.stats.probplot uses Filliben's estimate, and statsmodels ProbPlot defaults to a = 0, i.e. i/(n + 1). For n = 20, the lowest theoretical quantile is −1.960 (R rule), −1.824 (scipy) and −1.668 (statsmodels), and the maximum scipy-versus-R discrepancy is 0.136. Simulation envelopes, lineup null plots (P21) and any 'points outside the band' count inherit this discrepancy.


Handling. The registry defines the plotting positions (e.g. R's ppoints rule), the quantile definition for binned summaries (Hyndman–Fan type 7, which is R's default and numpy's 'linear'), the envelope construction and the binning rule (bin edges, hexbin grid size). Both packages compute these themselves and put them in the results JSON. Any count derived from a plot, such as the proportion of residuals outside an envelope, becomes a parity-tested statistic.


Parity. Without this, visual diagnostics and plot-derived counts systematically differ between packages.


Verifier's correction. Fix the plotting positions in the registry so the figures match. Rank-wise simulation envelopes and lineup comparisons do not depend on them. The parity-relevant specifications are the envelope construction (rank-wise, pointwise or simultaneous), the residual standardisation and the reference-line rule.


Verifier's reasoning. The numbers are confirmed. For n = 20, the lowest theoretical quantile is −1.960 under R's ppoints rule (a = 3/8 for n <= 10, else 1/2), −1.824 under scipy probplot's Filliben rule and −1.668 under statsmodels ProbPlot (a = 0). The maximum scipy-versus-R gap is 0.136, and the statsmodels-versus-R gap reaches 0.292. HF type 7 is R's default and numpy's 'linear'. But 'any points-outside-the-band count inherits this discrepancy' is wrong for the usual pointwise envelope. The envelope for the i-th order statistic is built from the i-th order statistics of the simulated residual sets and compared with the i-th observed order statistic. The x-coordinate (plotting position) does not enter, so the count is invariant to the plotting-position rule. The same holds within a lineup, where null and real panels share positions. Plotting positions do matter for the drawn picture, for any QQ reference line fitted by regression on the theoretical quantiles and for envelopes built analytically from normal theory (e.g. confidence bands that depend on p_i).


Evidence checked. Ran scratchpad/L6adv/t_num.py: lowest R -1.960, scipy -1.824, sm -1.668. Max diff scipy-R 0.136, sm-R 0.292. ppoints.Rd: ppoints(n, a = if(n <= 10) 3/8 else 1/2). The invariance argument follows from how a rank-wise envelope is constructed.


### L6-13 Treat the HTML/JSON report as a data export: privacy modes, pseudonymised unit labels, binned plots, no paths

Kind: feature. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. A diagnostic report leaks participant-level data through several routes. Vector plots embed per-observation coordinates. A matplotlib SVG scatter writes x/y per marker, about 107 bytes per point or 10.7 MB for 10^5 points. Interactive widgets embed raw data arrays, and influence and outlier tables list participant or school IDs. Provenance can leak absolute paths that contain user names. Under GDPR, pseudonymised data that can be re-attributed remain personal data (Recital 26), and children merit specific protection (Recital 38), which matters for school data. Small cells in design cross-tabs (e.g. a rare category × class) can single out a child even without IDs.


Handling. Offer two report modes. The default 'shareable' mode contains no row-level values, raw IDs, absolute paths, user names or host names. Units flagged by influence or outlier checks get report-local labels (unit 1, 2, ...), and the label-to-ID mapping stays only in the in-memory result object. Scatter-type plots are raster or binned (hexbin or quantile bands) above a configurable n. Cross-tab counts between 0 and k are shown as '<k', with k configurable. Empty cells (0) and the structural verdicts computed from exact counts are still reported, because the diagnostics depend on them. The 'internal' mode, available only via an explicit argument, gives full detail with a visible banner and a machine-readable contains_row_level_data: true flag in both the HTML metadata and the JSON. The results JSON offers the same two modes. Document that 'shareable' reduces disclosure risk but does not guarantee anonymity.


Parity. Privacy mode and its parameters must be part of the registry so both packages redact identically.


Verifier's correction. In 'shareable' mode, aggregate rather than rasterise: hexbins or bins with a minimum count per bin, and quantile bands, never per-point rasters for small n. Apply secondary suppression (or suppress or round the margins) whenever small cells are masked. Treat raster output only as a size measure. Cite the GDPR recitals only after checking the text, and mention other regimes (e.g. FERPA).


Verifier's reasoning. The general point stands: vector plots, widgets and ID tables embed row-level data. matplotlib SVG writes one element with coordinates per marker. I did not verify the 107 bytes per point (matplotlib is not on the allowed install list). I could not fetch the GDPR recital texts here: gdpr-info.eu and gdpr-text.com do not resolve in this session's network. My recollection of Recitals 26 and 38 matches the claim, but it is unverified here. The handling has two flaws. (1) 'Raster' is not a privacy control. A PNG scatter of a few hundred points lets anyone read each point's coordinates to pixel precision, so it reduces file size, not disclosure. Only aggregation (binning with minimum counts per bin, or quantile bands) reduces disclosure. (2) Showing small cells as '<k' while also publishing exact zeros, margins and verdicts from exact counts allows differencing: a suppressed cell can often be recovered from row and column totals minus the visible cells. Preventing that needs secondary suppression or perturbed margins. Plain GDPR framing is also EU/UK-specific, and other jurisdictions apply (e.g. FERPA for US school records). The 'no guarantee of anonymity' disclaimer is right.


Evidence checked. Tried WebFetch of gdpr-info.eu recitals 26 and 38 and gdpr-text.com recital 26: DNS resolution failed (host not in allowed network), so not verified. The SVG byte count was not reproduced. The differencing and raster arguments are analytical.


### L6-14 Accessibility: one registry-fixed palette, severity never by colour alone, alt text generated from the results, WCAG contrast checked in CI

Kind: feature. Stream: both. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Each language has its own colour-vision-deficiency-aware default. R's grDevices::palette.colors() defaults to the 'Okabe-Ito' palette, while matplotlib ships 'petroff10' and 'tableau-colorblind10'. These are different colours, so the two languages' plots will differ unless the registry fixes one palette. WCAG 2.x criteria apply directly to an HTML report: SC 1.4.1 (colour must not be the only way information is conveyed), SC 1.4.3 (text contrast ≥ 4.5:1), SC 1.4.11 (graphical objects ≥ 3:1) and SC 1.1.1 (text alternatives for non-text content).


Handling. The registry fixes the palette as hex codes (e.g. Okabe-Ito). Severity is encoded as text plus an icon or shape ('FAIL', 'WARN'), never by colour alone. Every figure gets alt text generated from the results JSON, using one template per plot type (e.g. 'Residuals vs fitted, model m1: no trend detected; 3 of 40 schools have |standardised residual| > 3'), plus an aggregated table as an alternative. Use semantic headings, a lang attribute and tables with header cells. CI computes contrast ratios for every colour pair in the template and fails if any falls below the WCAG thresholds.


Parity. Alt text and palette come from the shared spec, so they are identical across languages.


Verifier's correction. Fix one palette in the registry, but check the WCAG contrast of each colour against the background it is drawn on, not of every pair. Either exclude low-contrast Okabe-Ito members (yellow, orange, sky blue, grey on white) from marks that carry essential information, or outline them. Use shape or line type plus direct labels for distinguishing series. The 'severity never by colour alone' and alt-text measures are good.


Verifier's reasoning. I confirmed that palette.colors() defaults to palette = 'Okabe-Ito' and that matplotlib ships petroff10 and tableau-colorblind10 style files (both URLs return 200). But 'each language has its own CVD-aware default' is misleading. The defaults users get are ggplot2's hue palette and matplotlib's default prop_cycle 'tab10' (from matplotlibrc), and neither is a colour-vision-deficiency palette. R's palette() default is 'R4', and Petroff10 and Okabe-Ito are opt-in. The handling also contradicts itself: fixing Okabe-Ito and failing CI when any pair is below 3:1 cannot both hold. Against white, Okabe-Ito orange is 2.25:1, sky blue 2.31:1, yellow 1.32:1 and grey 2.85:1, all below SC 1.4.11's 3:1, and 27 of 36 colour pairs are below 3:1. SC 1.4.11 asks for 3:1 against adjacent colours (normally the background) for graphical objects needed to understand the content, not for every pair. Pair-wise distinctness under CVD is a separate goal, best met by redundant encoding (shape, line type, direct labels).


Evidence checked. Ran scratchpad/L6adv/t_num.py (WCAG relative-luminance formula). Contrast vs white: #E69F00 2.25, #56B4E9 2.31, #009E73 3.42, #F0E442 1.32, #0072B2 5.19, #D55E00 3.87, #CC79A7 3.06, #999999 2.85, with 27 of 36 pairs below 3:1. palette.Rd: palette.colors(n = NULL, palette = "Okabe-Ito", ...). matplotlibrc on main: '#axes.prop_cycle: cycler(color='tab10')'. curl returned 200 for petroff10.mplstyle and tableau-colorblind10.mplstyle.


### L6-15 CRAN constraints that shape the API: ≤2 cores, tempdir-only writes, no network, fast examples, conditional Suggests

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. CRAN policy says that examples should run for no more than a few seconds each and that checks should use as little CPU time as possible. Under the same policy, a package must never use more than two threads or cores at once and must not write anywhere except the R session's temporary directory (user data and caches only via tools::R_user_dir(), actively managed). The policy also requires Internet resources to fail gracefully and says that data and documentation should generally each stay under 5 MB and source tarballs under 10 MB. R Internals states that _R_CHECK_LIMIT_CORES_ is set to TRUE for CRAN submission checks and that spawning more than 2 children through package parallel is then an error. Writing R Extensions states that packages in Suggests, including recommended ones, must be used conditionally (requireNamespace()).


Handling. Report writers have no default output path in the working directory. Examples and tests write to tempfile(). Parallel cluster refits (P24) default to 1 worker, and users opt in with n_workers, capped at 2 when _R_CHECK_LIMIT_CORES_ is set. The package downloads no registries, templates, fonts or JavaScript at runtime. Examples use tiny fixtures or a precomputed, KB-sized result object in inst/. Heavy fits, exact influence refits and large-data tests are skipped on CRAN and run in monorepo CI. Every check that needs a Suggests package is gated with requireNamespace() and returns 'not_available'. CI includes a run with no Suggests installed. The Python package follows the same rules (no network, writes only to explicit paths) for symmetry.


Verifier's correction. Keep the handling, but also cap OpenMP and TMB threads (and set BLAS threads where possible) to at most 2 during checks. Keep at least one tiny run per feature on CRAN. Describe the size limits as guidance ('as a general rule' and 'if possible').


Verifier's reasoning. I confirmed the quoted policy text: few-seconds examples, as little CPU time as possible, 'must never use more than two simultaneously', writes only to the session's temporary directory with tools::R_user_dir() allowed, Internet resources failing gracefully, 5 MB and 10 MB. R-ints confirms _R_CHECK_LIMIT_CORES_: it is TRUE for CRAN submission checks, and spawning more than 2 children through package parallel is then an error. R-exts says suggested packages, including recommended ones, should be used conditionally, with requireNamespace() preferred. The handling has three gaps. (1) _R_CHECK_LIMIT_CORES_ applies only to parallel's child processes. The two-cores rule also covers OpenMP threads (glmmTMB/TMB can run OpenMP via glmmTMBControl(parallel = ...)) and multithreaded BLAS, so these must be capped at 2 during checks as well, not only n_workers. (2) 'Heavy fits ... skipped on CRAN' must still leave CRAN checks exercising all features (the same policy paragraph). (3) The 10 MB limit is 'should if possible', not a hard limit.


Evidence checked. grep of the CRAN policy copy (scratchpad/L6/dl/crp.texi lines 225-317): 'must never use more than two simultaneously', 'Examples should run for no more than a few seconds each', 'fail gracefully', R_user_dir, 5MB, 10MB. R-ints.texi lines 4123-4128 (_R_CHECK_LIMIT_CORES_). R-exts.texi lines 1076, 1107-1110: a recommended package in Suggests cannot be used unconditionally.


### L6-16 Dependency layering: pre-fit audits need no fitting engine, and engines, plotting and df methods are soft dependencies

Kind: architecture. Stream: infrastructure. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Stream B (pre-fit and outcome-blind audits, P17) needs no model-fitting engine, and only Stream A needs lme4 or statsmodels. statsmodels 0.15.0 itself requires formulaic, patsy, numpy, pandas, scipy and packaging (pip metadata checked). Making glmmTMB, lmerTest/pbkrtest, ggplot2 or matplotlib hard dependencies adds compiled-code install failures for users who only want audits.


Handling. In R, Imports lists stats, Matrix, lme4 (default Stream A engine) and jsonlite, and audits use only base R and Matrix. Suggests lists glmmTMB, lmerTest, pbkrtest, ggplot2, whisker (or an in-house renderer) and testthat, all used conditionally. In Python, the core dependencies are numpy, pandas and scipy, enough for the audits and for the HTML report via an in-house Mustache renderer. The extras are mixdiag[fit] (statsmodels), mixdiag[plot] (matplotlib) and mixdiag[all]. A missing optional package or engine produces a 'not_available' row that names what to install, never a silent omission or a 'pass'.


Parity. Both packages expose the same feature-gating vocabulary ('not_available' plus package name).


Verifier's correction. Either accept lme4 as a hard dependency and drop the claim that audits are engine-free at install time, or move lme4 to Suggests and gate Stream A behind requireNamespace() (or split into an audit package and a fitting package). Put the template renderer in core in both languages (in-house and spec-tested, or whisker in Imports).


Verifier's reasoning. I confirmed with pip show that statsmodels 0.15.0 requires formulaic, numpy, packaging, pandas, patsy and scipy. The layering idea is sound, but the R side does not deliver what the claim promises. With lme4 in Imports, every user who only wants audits still installs lme4 and its compiled dependencies (Rcpp, RcppEigen, minqa, nloptr), so 'pre-fit audits need no fitting engine' holds for the code but not for installation. A second inconsistency is that the HTML report is core functionality but whisker is listed in Suggests, so the default report becomes 'not_available' unless an in-house renderer is also in core. The Python side is consistent if the core includes an in-house renderer. scipy may not be needed for pure audits, though it is cheap.


Evidence checked. scratchpad/venv/bin/pip show statsmodels: 'Requires: formulaic, numpy, packaging, pandas, patsy, scipy'. lme4's compiled dependency chain is from general knowledge and was not checked in this session.


### L6-17 Scale to millions of rows and thousands of groups, where memory is the binding constraint, and record every approximation

Kind: architecture. Stream: both. Priority: valuable. Origin: preliminary (P34). Verdict: partly_correct.


Claim. P34 (compute on all data, plot downsampled) is right but incomplete: memory, not plotting, is the binding constraint. A dense Z for 10^6 rows × 5,000 groups × 2 random effects is 10^10 doubles, i.e. 80 GB. A dense marginal V is n×n, 8 TB at n = 10^6. Kenward-Roger computations invert N×N matrices, which is why emmeans disables pbkrtest by default above N = 3,000 observations (pbkrtest.limit). Exact cluster-deletion influence needs one refit per cluster. At 10^5 points, an SVG scatter is 10.7 MB (14.2 MB base64-embedded), against about 0.04 MB as PNG.


Handling. Audits are single-pass group-by aggregations: O(n), never pairwise over groups (tabulate, rowsum and split indices in R, pandas groupby and np.bincount in Python). Post-fit diagnostics use sparse X and Z with per-block computations: block-diagonal V only for single or nested grouping, sparse Cholesky for crossed designs. For degrees of freedom, fall back automatically from KR to Satterthwaite above a registry limit and to asymptotic above a second limit, recording df_method_used and the reason. For influence, use approximate or one-step deletion diagnostics by default, with exact refits for a random subset or the top-k flagged clusters and a reported agreement statistic. Plots are binned or raster above n_plot_max. Every downgrade is recorded per check ('approximate', 'subsampled', 'df_fallback') and shown in the report, so an approximate large-data report never looks identical to an exact one. Optional arguments set time and memory budgets.


Parity. Fallback limits live in the registry so both packages downgrade at the same N.


Verifier's correction. Base df fallbacks on estimated cost and on the number of clusters. Never fall back to asymptotic df when the number of clusters is below a registry limit. Prefer Satterthwaite there, or refuse with a message. Build crossing and contingency audits as sparse pair counts. Keep recording every downgrade.


Verifier's reasoning. The arithmetic is right: a dense Z of 10^6 × 10^4 is 10^10 doubles or 80 GB, and a dense V at n = 10^6 is 8 TB. emmeans' models vignette confirms that pbkrtest is disabled above pbkrtest.limit = 3000 because the computation involves inverting an N×N matrix. It also has a separate lmerTest.limit for Satterthwaite. The SVG and PNG sizes were not verified. The df fallback sequence is harmful as written. Using N (observations) to fall back to asymptotic df is exactly wrong in the few-clusters, many-observations case (e.g. 10 schools × 500 pupils), where Wald z is most anticonservative (P26). Satterthwaite via lmerTest does not need N×N inverses for lmer fits and scales well, so the fallback should be keyed to cost and should not go to asymptotic when the number of clusters is small. Also, 'never pairwise over groups' misses crossed designs. Crossing and confounding audits for two crossed factors with 10^4 levels each would build a 10^8-cell dense table. Those tables must be sparse (counts of observed pairs only).


Evidence checked. Read the emmeans models.Rmd copy (scratchpad/L6/dl, lines 336-347): 'inverting an N x N matrix ... pbkrtest is automatically disabled if N exceeds ... pbkrtest.limit ... factory default is 3000' and 'Similarly ... lmerTest.limit'. Memory arithmetic checked by hand. SVG and PNG sizes not reproduced.


### L6-18 Result object: one long table with a fixed schema and a status taxonomy that never turns 'could not check' into 'pass'

Kind: architecture. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. The result design decides whether failures are visible. If a check that crashes internally, or cannot run because a package or engine capability is missing, is silently omitted or counted as 'pass', the report says the model was checked when it was not. And without a fixed column schema, R and Python outputs cannot be diffed.


Handling. The result is one long table, defined in the registry, with the same snake_case columns in both languages: check_id, check_version, stage, target (grouping factor, term or unit), statistic, value, threshold, comparator, margin, status, severity, message, citation_keys, approx_flag. The status values are pass, note, warn, fail, error (the check crashed, traceback stored), not_applicable, not_available (missing package or capability) and skipped (by the user or by a budget). The overall verdict is the maximum severity, and the header line always shows counts of 'error' and 'not_available'. In R, it is an S3 class with print (compact, sorted by severity), summary, format, as.data.frame, tidy() via the lightweight 'generics' package, and to_json(). In Python, it is a frozen dataclass with .to_frame() (severity as an ordered CategoricalDtype), .to_json() and _repr_html_(). The CI helper assert_checks(res, fail_on = 'warn', allow = list(ID = 'justification')) raises an error in R or exits non-zero in Python (python -m mixdiag check). It prints the allowed exceptions with their justifications (the CI assertions in P33).


Parity. Identical schema and status vocabulary make results diffable and CI gates portable across languages.


Verifier's correction. Define status as an ordered enum that includes incomplete states. Report the overall verdict as a (worst status, completeness) pair and show 'incomplete' whenever error or not_available rows exist. Make assert_checks fail on error by default. Document that post-fit gates check a pre-specified model and are not a tuning loop.


Verifier's reasoning. There is no source to check. As design advice, it is mostly sound: never turning 'could not check' into 'pass' is essential. The advice has four weaknesses. (1) status (pass/note/warn/fail) and severity overlap, so their relationship must be defined, e.g. severity applies only to non-pass statuses, or the two collapse into one ordered field. (2) 'Overall verdict = maximum severity' is undefined for error, not_available and skipped. A run with errors must show 'incomplete' rather than a clean verdict that ignores them, because a count in the header is not enough. (3) A single pass/fail verdict plus CI gates such as fail_on = 'warn' invites changing the model until it passes, which is outcome-dependent model selection when the checks are post-fit. Post-fit gates should apply to the pre-specified model (L6-22), and justifications on the allow-list should be recorded in the result's provenance. (4) assert_checks should fail by default on 'error' and treat 'not_available' as configurable, not as passing.


Evidence checked. No external source. This is an analysis of the proposed design.


### L6-19 Provenance must capture every input that changes results, plus a canonical cross-language data hash

Kind: architecture. Stream: both. Priority: essential. Origin: preliminary (P33). Verdict: partly_correct.


Claim. P33's provenance list misses inputs that change results: locale collation (level order, L6-08), global options (R options('contrasts'), statsmodels formula_engine and ordering, L6-07), the BLAS/LAPACK implementation (last-digit differences), the RNG kind (R normal.kind and sample.kind), the registry version and hash, and the effective thresholds. A data hash is comparable across languages only if computed on a canonical serialisation. A hash of R serialize() output is not portable: per R Internals, the serialisation header stores the R version that wrote it, and such a hash can never match a Python hash.


Handling. The provenance block records the versions of the package, engines, main dependencies and R or Python. It also records BLAS/LAPACK identifiers, optimiser and control settings, RNG kind and seed, LC_COLLATE, relevant global options, registry version and SHA-256, effective thresholds, active plugins (L6-20) and contract version. Define a canonical data hash in the registry. Take the model's columns in declared order. Serialise each column as a type tag followed by its values: doubles as IEEE-754 little-endian bytes (with −0 and NaN payloads normalised), integers as int64, strings as UTF-8 NFC, factors as level strings in row order plus the level order, and NA as a distinct tag. Take SHA-256 over the concatenation. Report hashes of both the full design table and the analysed rows after NA deletion. Exclude paths, user names and host names by default (L6-13).


Parity. A shared data hash lets the parity harness and users confirm that the R and Python results come from the same data.


Verifier's correction. Hash semantic column types fixed by the registry, not storage types: numeric (all integer-valued and floating values encoded as float64, after a check that integers fit in 2^53), string (UTF-8 NFC), boolean, date and datetime (UTC epoch), and one missing tag that NaN maps to as well. Compute two hashes: a raw-data hash without coding and a design hash that includes levels, reference levels and contrasts.


Verifier's reasoning. I confirmed that R-ints says the serialisation header contains the format version and two R versions, so a hash of serialize() output depends on the R version and cannot match Python. The list of missing provenance items is sensible. But the canonical hash as specified will not match across languages for identical data, because storage types differ. (1) pandas turns an integer column with any missing value into float64, while R keeps it integer, so the type tags (int64 versus double) differ. (2) pandas float columns cannot tell NaN from NA, while R distinguishes NA_real_ from NaN. (3) Storage types also differ for R character versus pandas object, string or category dtype, for logicals and for Date and POSIXct versus datetime64 with time zones. (4) Including the level order in the hash means the same raw data under different default ordering (L6-08) hashes differently. That may be intended for the analysed design, but it conflates data identity with coding. The hash needs semantic types, not storage types.


Evidence checked. Read R-ints.texi (copy in scratchpad/L6/dl, lines 1148-1154): the header holds 'three integers giving the version of the format and two R versions'. pandas' int-to-float upcasting with NA and its NaN/NA conflation are documented pandas behaviour and were not rerun here.


### L6-20 Plugin checks: namespaced IDs, declared contract requirements, explicit activation, excluded from parity claims

Kind: architecture. Stream: infrastructure. Priority: valuable. Origin: preliminary (P33). Verdict: partly_correct.


Claim. User-registered checks (P33) need a defined interface. Without one, they will collide with future built-in IDs, depend on unexposed engine internals and break parity claims silently. Python's standard discovery mechanism is entry points, as defined in the PyPA specification and read via importlib.metadata. R has no equivalent, so it needs an explicit registration call. Discovering a plugin means executing third-party code, and installed plugins change results.


Handling. In plugin API v1, a check declares a namespaced ID (ext.<package>.<name>, with the bare namespace reserved for built-ins), its stage (prefit or postfit) and the contract fields and capabilities it requires. It also declares its check_version, thresholds with citation fields and message templates in the registry schema, and a pure function from (data or contract) to result rows. Python discovers plugins through the entry-point group 'mixdiag.checks' and loads them only when the user passes plugins = 'all' or names the plugins. In R, extension packages call mixdiag::register_check() in .onLoad, and activation is again explicit. Plugin results carry origin = 'extension', provenance lists active plugins, parity claims cover built-in checks only and explain() works for plugin checks from their declared metadata.


Parity. Keeps parity guarantees well defined when third-party checks are present.


Verifier's correction. Distinguish discovery (reading metadata, safe) from loading (executing code, opt-in). In R, separate registering a plugin (in .onLoad) from activating it (per call, through a plugins argument).


Verifier's reasoning. The PyPA entry-points specification and importlib.metadata are the standard Python mechanism, and R has no built-in equivalent, so an explicit registration call is reasonable. The claim contains one overstatement: discovery does not execute third-party code. Listing entry points with importlib.metadata.entry_points(group='mixdiag.checks') reads only installed metadata, and code runs only on EntryPoint.load(). The handling already loads only on opt-in, so it can safely list the available plugins without loading them. In R, registration in an extension package's .onLoad runs as soon as that namespace is loaded, even indirectly through another package's imports, so 'explicit activation' must be a separate step after registration. Namespaced IDs and excluding plugins from parity claims are sound.


Evidence checked. The PyPA entry-points spec copy in scratchpad/L6/dl/entry-points.rst was available but not re-read in this session. The discovery-versus-load distinction is how importlib.metadata works (EntryPoint.load).


### L6-21 Generate per-check documentation, explain(id) and messages from the registry, with CI enforcing completeness

Kind: feature. Stream: infrastructure. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Hand-written documentation for each check will diverge from the code and between the two languages. The registry already holds everything the documentation needs, so generating the docs from it keeps documentation, messages and thresholds identical in both packages.


Handling. Each registry entry contains a title, stage and rationale, the exact decision rule (algorithm, comparator, threshold, tolerance) and the justification for the threshold with structured references (CSL-JSON with DOI), marking thresholds that are conventions rather than evidence-based. It also contains known false-positive and false-negative scenarios, remedies, applicable families and engines, and the IDs of its positive and negative fixtures. The generated outputs are R Rd topics or a single 'checks' reference page, explain(id) printing offline from the vendored JSON, one Sphinx or MkDocs page per check for Python and the report bibliography. CI fails if an ID exists in code but not in the registry or vice versa, if a check lacks a positive or a negative fixture, or if a message template uses an undefined placeholder.


Parity. Messages and documentation are byte-identical across languages because both render the same templates.


Verifier's correction. Generate the docs from the registry in a pre-build step and commit the generated Rd files. Golden-test the rendered messages in both languages. Allow non-DOI citations and a 'convention' flag.


Verifier's reasoning. There are no sources, and as design advice it is mostly sound. Three caveats apply. (1) CRAN builds and checks from the source tarball, so generated Rd files must be produced and committed, or produced in a build step that runs before R CMD build. roxygen cannot read the JSON registry directly. (2) 'Byte-identical messages' holds only if both template renderers follow the spec exactly (whitespace and standalone-line rules, escaping) and number formatting is identical (L6-09, L6-11). So the generated messages themselves need cross-language golden tests. (3) Requiring a DOI for every threshold citation fails for thresholds that are conventions or come from books or software documentation. The schema should allow ISBN or URL and an explicit 'convention' flag, which the item already partly anticipates.


Evidence checked. No external source. This is an analysis of the proposed design and of how CRAN builds from source tarballs.


### L6-22 Enforce and record outcome-blind mode, and hand Stream A a hashed model-spec file with a preregisterable fallback ladder

Kind: feature. Stream: B. Priority: valuable. Origin: preliminary (P17). Verdict: partly_correct.


Claim. P17 is valuable, but as described, the outcome-blind guarantee is neither enforced nor recorded, and it leaks in two ways. First, the design table includes rows that listwise deletion on the outcome later removes, so N, group sizes and empty cells at fit time can differ from the audited ones. Second, any later data-driven simplification (e.g. dropping slopes after non-convergence) depends on the outcome unless the simplification path was fixed in advance.


Handling. diagnose_design() accepts only a design table. If an outcome column is named or detected, it refuses unless outcome_blind = FALSE, and it records outcome_blind: true together with the canonical hash of the design columns (L6-19). Its output is a machine-readable, hashable model-spec file in JSON. The file contains the formula AST, contrasts and reference levels, centring and scaling constants computed from the design table, the maximal design-implied random-effects structure, and a preregisterable, ordered fallback ladder of simpler random-effects structures with the convergence and singularity criteria that trigger each step. Stream A accepts spec = 'model-spec.json' and fits the first rung that meets the criteria. It reports which rung was used, any deviation from the spec, the N and groups lost relative to the audited design table, and the results of re-running the structural audits on the analysed rows.


Parity. The spec file is the shared, language-neutral contract between Stream B and Stream A in either language.


Verifier's correction. Treat outcome-blind mode as a recorded attestation tied to a hash of the design columns. Fix in the spec whether centring constants come from the design table or the analysed rows. Define the rung-selection criteria with registry-computed, engine-independent quantities. State in the report that ladder selection is pre-specified but outcome-dependent.


Verifier's reasoning. There are no sources. The two leak routes are real: listwise deletion on the outcome changes N and the cells, and later simplification depends on the outcome. But the claim that simplification 'depends on the outcome unless the path was fixed in advance' is wrong. A pre-specified fallback ladder still selects the model from the outcome, because convergence and singularity depend on y. Fixing it in advance removes researcher discretion, but it does not make the selection independent of the data, and inference after it is not exactly nominal. Report it as 'pre-specified data-dependent selection'. There are three other problems. (1) Detecting an outcome column automatically is not reliable, and a user can rename it. Record outcome-blindness as an attestation plus the hash of the design columns, not as an enforced guarantee. (2) Centring and scaling constants from the design table will differ from those of the analysed rows once outcomes are missing. The spec must say which constants apply. (3) 'First rung meeting convergence/singularity criteria' depends on the engine. lme4 and statsmodels warn under different conditions, and lme4's gradient warnings are often false positives (P19), so the two languages may pick different rungs. The criteria must be defined by registry-computed quantities (e.g. a relative-gradient threshold, the minimum eigenvalue of the random-effects covariance), not by engine warnings.


Evidence checked. No external source. This is an analysis of the selection logic. The dependence of convergence and singularity on y follows from the likelihood depending on y.


## L7 Domain workflows the suite must serve


### L7-01 Reused nested IDs vs genuine mobility and cross-classification

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P1). Verdict: partly_correct.


Claim. P1 is right that, when class labels are reused across schools, (1|school)+(1|class) makes lme4 treat class as crossed with school and merge same-labelled classes in different schools into one level. (1|school/class) expands to (1|school)+(1|school:class) and is safe however the labels are coded. But 'inner level maps to more than one outer level' has three causes in education and family data, and only one of them is a coding error. (a) Label reuse: class '1' in every school. (b) Genuine mobility: the same pupil ID appears under different schools or classes at different waves. Pupils are then neither nested nor crossed but multiple-membership, which lme4, glmmTMB and statsmodels cannot represent natively (Browne, Goldstein & Rasbash 2001). (c) Genuine crossing: siblings from one family attend different schools, or a teacher teaches in two schools. Silently building an interaction ID is wrong in cases (b) and (c).


Handling. For each pair of grouping factors, classify the structure as nested, crossed or partially crossed. Report how many inner levels map to more than one outer level and what fraction of rows they cover. If a time variable is declared, run the classification within each occasion and also across occasions. Suggest an outer:inner ID only when the pattern fits label reuse (the same small set of labels repeats under almost every outer level, and nothing is crossed within a single occasion). Otherwise, print a membership-change table (units whose cluster changes over time) and list the options: assign by a declared rule such as first or last cluster, model the structure as crossed, or use a multiple-membership model outside the supported engines. Record the chosen resolution in the results JSON.


Parity. The data audit is purely deterministic (exact tier). The classification algorithm and its tie rules must be in the shared spec.


Verifier's correction. Separate three structures. (i) Label reuse: build an outer:inner ID. (ii) Mobility with occasion-level outcomes: a cross-classified model (1|pupil)+(1|school), which all engines can fit. (iii) Mobility with an outcome attributed to several clusters: multiple membership (Browne, Goldstein & Rasbash 2001), outside the supported engines. school/class is safe only for label reuse. For genuinely crossed units, use crossed terms with globally unique IDs.


Verifier's reasoning. Case (a) is right: lme4 builds one level per distinct label, so reused class labels are merged across schools under (1|school)+(1|class), and school/class expands to school + school:class. Case (b) is wrong for the most common education situation. In longitudinal data, each occasion's outcome is measured in a single school. Occasions are then cross-classified by pupil and school, and (1|pupil)+(1|school) fits that structure directly in lme4 and glmmTMB, and in statsmodels via variance components. Multiple membership applies only when one outcome is attributed to several clusters, for example end-of-phase attainment for a pupil who attended two schools with weights. 'Cannot represent natively' is true only of that case. The claim that (1|school/class) is 'safe however the labels are coded' is false for case (c), because a teacher who teaches in two schools is split into two unrelated levels.


Evidence checked. Browne, Goldstein & Rasbash, 'Multiple membership multiple classification (MMMC) models', Statistical Modelling 1 (2001) 103-124. Confirmed via WebSearch (statmod.org abstract page listing). The page itself was blocked for WebFetch. The cross-classification and school/class points follow from how lme4 builds factor levels. I did not run R.


### L7-02 Few schools: separate an incidental top level from the level of inference

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P5). Verdict: partly_correct.


Claim. The '<5-6 levels' rule in P5 is a heuristic, not a threshold where something breaks. What a small top level costs depends on its role. If school is incidental (no school-level predictors, no inference about school variance, treatment not assigned by school), 3-10 schools can be absorbed as fixed school dummies, with random effects kept at the class and pupil levels (McNeish & Wentzel 2017 study this 'incidental third level' situation). Any school-level predictor is then perfectly collinear with the school dummies and cannot be estimated. If treatment or another predictor of interest varies only between schools, no modelling choice recovers information, because the evidence on that effect is bounded by the number of schools.


Handling. Report the number of levels per grouping factor and, for every fixed effect, the lowest level at which it varies. If the top level has few levels and no predictor varies only at that level, offer the fixed-dummy alternative and show its effect on the remaining estimates. If a predictor varies only at that level, give a 'design-limited' warning that names the number of units carrying the effect, rather than a technical fix. Never suggest fixed school effects when school-level predictors are in the formula without saying they become unidentifiable.


Parity. The audit is deterministic (exact tier). Comparing the fixed-dummy and random-intercept fits falls in the numerical-tolerance tier.


Verifier's correction. Decide between fixed school dummies and a school random intercept from the design audit, before the outcome is seen. Report the other fit only as a pre-declared sensitivity analysis. State that, with fixed dummies, every lower-level coefficient becomes a within-school effect. Give the McNeish & Wentzel citation as the source of the idea, not of specific thresholds, until the paper's results are checked.


Verifier's reasoning. These points are logically sound: school-level predictors are perfectly collinear with school dummies, and the evidence on a school-level effect is bounded by J. The McNeish & Wentzel (2017) reference exists (MBR 52(2), 200-215, seven methods for a small third level), but I could not confirm which methods they recommend or the '3-10 schools' range. The handling has two problems. First, 'show its effect on the remaining estimates' produces two fits and invites picking whichever one the user prefers. That is outcome-dependent model selection, unless the choice is made in outcome-blind mode or labelled as a sensitivity analysis. Second, fixed school dummies change the estimand of class- and pupil-level predictors to a purely within-school effect. Between-school variation in those predictors no longer contributes, which changes more than precision.


Evidence checked. WebSearch confirmed the McNeish & Wentzel citation, the DOI 10.1080/00273171.2016.1262236 and the 'seven methods' framing. The full text was not accessible, so its conclusions were not verified.


### L7-03 Cluster-randomised trials: the randomisation unit must be in the model, and df follow clusters

Kind: correction. Stream: both. Priority: essential. Origin: preliminary (P26). Verdict: partly_correct.


Claim. P26's 'few clusters gives anticonservative Wald z' is incomplete for cluster-randomised trials. The first-order error is leaving out the randomisation level. Simulation (statsmodels 0.15.0, 300 replicates): 4 schools x 6 classes x 20 pupils, treatment randomised by class within school, class variance 0.15, school variance 0.2, residual variance 1, true effect 0. A nominal .05 Wald test rejected 31.7% with only a school random intercept, 31.7% with OLS plus school dummies and 1.3% when class was also included. The information on the treatment effect is governed by the number of randomised clusters minus the cluster-level parameters, not by the number of pupils. Blocking or stratification variables used in the randomisation belong in the fixed part. The CONSORT extension for cluster trials (Campbell et al. 2012) asks for an intracluster correlation per primary outcome. The exact item wording was not checked here.


Handling. Stream B takes the declared randomisation unit and checks that treatment is constant within it. If any cluster has mixed treatment, report it as a top-severity finding. Error if the randomisation unit, or a level above it, is missing from the random part. Report a 'design df' (randomised clusters minus cluster-level fixed parameters) next to the Satterthwaite or Kenward-Roger df. Report ICC and design effect, 1+(m-1)ICC for equal cluster sizes with an unequal-size variant. Warn if declared blocking variables are absent from the formula. Offer a sensitivity check using CR2 cluster-robust SEs with small-sample df (Pustejovsky & Tipton 2018).


Parity. The design df and assignment-level check are exact. Satterthwaite and Kenward-Roger are engine-specific, so the Python side should at least report the design df.


Verifier's correction. Require that the declared randomisation unit appears as a grouping factor, or that inference is at or clustered on that unit (aggregated means, CR2). A higher level alone never satisfies the check. Make it a top-severity finding with these remedies rather than an error. Blocking factors may enter as fixed effects. For the unequal-size design effect, give the explicit formula: 1+((CV^2+1)m_bar-1)ICC.


Verifier's reasoning. I reran t5_crt.py (statsmodels 0.15.0, 300 replicates) and got exactly the reported rates: school-only 0.317, OLS with school dummies 0.317, school+class 0.013. The core point holds: omitting the randomisation level is a first-order error. Problems: (1) The handling text 'Error if the randomisation unit, or a level above it, is missing' can be read as letting a school-only model pass, which is the 31.7% failure in the simulation. The randomisation unit itself must carry a random effect, or the analysis must be at that level. (2) A hard error blocks valid analyses: cluster-level analysis of class means, GEE or CR2 cluster-robust SEs clustered at the randomisation unit, or fixed school blocks. A school random effect is not required when schools are blocks. (3) The correct model rejected only 1.3%, so Wald z was conservative here, not anticonservative. P26's direction is not universal. (4) The CONSORT cluster extension item 17a asks for an intracluster correlation coefficient for each primary outcome, per checklist reproductions.


Evidence checked. Re-ran scratchpad/L7/t5_crt.py, output {'school_only': 0.317, 'school+class': 0.013, 'ols': 0.317}. CONSORT item 17a wording seen via WebSearch in checklist reproductions (https://assets-eu.researchsquare.com/files/rs-17375/v1/Additional%20File%201.pdf). The Pustejovsky & Tipton arXiv paper was not opened.


### L7-04 Multisite trials: within-site treatment, site-varying effects, single-arm sites and the estimand

Kind: feature. Stream: both. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In multisite trials (randomisation within schools or sites), treatment is within-site. A by-site random treatment slope is therefore identifiable and is often the quantity of interest (cross-site impact variation). Generic tools miss three things. (1) A site that ends up with only one arm, by design or after attrition, contributes nothing to the within-site contrast but still affects the intercept variance. (2) When the proportion treated differs across sites, a random-intercept model partly uses between-site variation in treatment proportion, which is confounded with site differences. Fixed site intercepts with a random treatment coefficient (FIRC: y ~ 0 + site + treat + (0 + treat | site)) remove this confounding (Bloom, Raudenbush, Weiss & Porter 2017). (3) With unequal site sizes and heterogeneous effects, the precision-weighted average estimated by the LMM differs from both the unweighted site average and the person-average effect.


Handling. Stream B prints an arm-by-site table, flags single-arm sites and sites with fewer than k units per arm, and reports the spread of allocation proportions across sites. When allocation proportions vary, it suggests FIRC. Stream A reports the treatment-effect SD across sites with its interval, notes that few sites make it imprecise, and states which average-effect estimand the fitted model targets.


Parity. The tables are exact. FIRC is expressible in all engines, so its fixed effects fall in the numerical-tolerance tier.


Verifier's correction. Under random site intercepts, single-arm sites and unequal allocation proportions bring between-site comparisons into the treatment estimate. Under FIRC (fixed site intercepts), they contribute nothing to the treatment effect. Report the treatment-effect SD with a profile or bootstrap interval, plus a boundary-aware test, not a Wald interval.


Verifier's reasoning. FIRC and the multisite framing are correct, and the citation is confirmed: Bloom, Raudenbush, Weiss & Porter (2017), JREE 10(4). Point (1) is wrong under the random-intercept model. A single-arm site does contribute to the treatment estimate through between-site (inter-block) information, which is why it can bias the estimate. Simulation: 20 sites, 5 control-only, 30 people each. The random-intercept estimate was 0.2607 with all sites and 0.2506 without the single-arm sites. The fixed-site estimate was 0.2506 either way. Single-arm sites contribute nothing only under fixed site intercepts. The same run also supports point (2): with equal 50/50 allocation, random-intercept and fixed-site estimates were identical (0.25056). Point (3) is correct in principle. On the handling, a Wald interval for the cross-site SD is poor near zero, so a profile, bootstrap or boundary-aware interval should be used.


Evidence checked. scratchpad/L7adv/a2_multisite_eeg.py: 'RI all sites: 0.26066  RI two-arm sites only: 0.25056  fixed-site: 0.25056'. Bloom et al. citation confirmed by WebSearch (ies.ed.gov award page, MDRC award notice, uchicago PDF listing).


### L7-05 Partially nested designs: grouping exists in one arm only

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In education and family interventions delivered in groups (tutoring groups, parent workshops), often only the intervention arm is grouped and controls are ungrouped (Bauer, Sterba & Hallfors 2008). In the data, the group ID is then typically missing or unique per person in the control arm. A generic audit will wrongly drop controls listwise (group ID = NA) or count them as hundreds of singleton groups. The usual LMM approach is a group random effect that loads only on treated participants, e.g. (0 + treat | group), with each control in its own pseudo-group.


Handling. Detect a grouping factor whose cluster sizes differ systematically by arm: all clusters of size 1, or all NA, in one arm. Do not drop the NA-group rows. Advise the treatment-only random-effect specification, and report group counts and sizes in the treated arm only.


Parity. Deterministic detection, exact tier.


Verifier's correction. Advise (0+treat|group) with unique control IDs, plus arm-specific residual variances where the engine supports them (glmmTMB dispformula = ~treat). Flag the engine limitation in lme4 and statsmodels. Use declared design information rather than heuristics alone.


Verifier's reasoning. The partially nested design and the (0+treat|group) specification with unique control pseudo-IDs are right. lme4 drops rows with an NA grouping factor. With unique control IDs, the number of levels stays below the number of observations, so lmer's checks pass, and control rows have all-zero Z columns. The paper is confirmed: Bauer, Sterba & Hallfors (2008), MBR 43, 210-236. The handling is incomplete. Treated participants share a group experience, so their residual (level-1) variance usually differs from the controls'. The heteroscedastic-residual model is the standard partially nested specification in the follow-up literature, but I could not confirm it in the 2008 text itself. lme4 cannot fit arm-specific residual variances. glmmTMB can (dispformula = ~treat), and statsmodels MixedLM cannot directly. Detection by 'all clusters of size 1 in one arm' would also fire on cluster-randomised data where one arm is individually randomised for other reasons, so the design should be declared.


Evidence checked. lme4 source R/modular.R (checkNlevels / checkZdims, fetched from GitHub). WebSearch confirmed the Bauer, Sterba & Hallfors 2008 citation (PMC2853949, Vanderbilt PDF). PMC itself was unreachable, so the residual-variance detail was not verified.


### L7-06 Singletons and tiny clusters (families with 1-2 children) are a design property, not an error

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P6). Verdict: partly_correct.


Claim. P6 treats singleton groups as a defect. In family data, they are the norm, and in a random-intercept model they are legitimate: they inform the fixed effects and the total variance. Only clusters with at least 2 observations separate between-family from within-family variance. With about 2 observations per group, two-level models overstate the group-level variance, and estimates became reliable with about 5 per group on average (Clarke 2008). Dropping singletons changes the sample and the estimand. Random slopes by family are practically unidentifiable when almost all families have 2 or fewer observations, by the same moment-counting argument as L7-09. A resulting singular fit is a property of the design, not 'overfitting'.


Handling. Report the cluster-size distribution (count of clusters with n=1, n=2, n>=3), the number of clusters with n>=2 and the share of rows in singletons. Recommend keeping singletons. Block or warn on random slopes by a factor whose median cluster size is 2 or less. When such a factor gives a singular fit, route the message to 'design-limited' rather than 'simplify the model'. Group losses after listwise deletion (P12) are reported separately.


Parity. Exact tier.


Verifier's correction. Do not block random slopes on median cluster size. A slope is weakly identified when x takes few common values across clusters, or when within-cluster variation in x is small. Report how many clusters have n >= 2 and nonzero within-cluster variance of x. Explain that lme4's nobs-vs-nRE stop is a counting rule (overridable with check.nobs.vs.nRE = 'ignore'), not a proof of non-identification.


Verifier's reasoning. The Clarke (2008) findings are confirmed from the abstract: with two observations per group, the group-level variance is overestimated, and estimates are reliable with about five per group on average. Keeping singletons is right. The random-slope claim is wrong in general. Moment counting applies only when the predictor takes common values across clusters, as with fixed occasions. When a child-level x varies across families, slopes are identified from size-2 clusters. Simulation: 400 families of 2 with continuous x and a family random slope. Default, lbfgs, Powell and Nelder-Mead all reached llf -1248.08 with the same estimates (intercept variance 0.85, covariance 0.15, slope variance 0.27, residual 0.52) against truth (1, 0.2, 0.25, 0.49). Separately, lmer stops by default whenever nobs <= the number of random effects for a term (check.nobs.vs.nRE = 'stop'). Families of exactly 2 with (1+x|family) therefore error in lme4 even though the model is identified. The suite should explain that error, not reinforce it.


Evidence checked. scratchpad/L7adv/a1_ident.py, part A. lme4 R/lmerControl.R and R/modular.R from GitHub: check.nobs.vs.nRE = 'stop', and wmsg uses unident <- n <= cmp.val when allow.n = FALSE (lmer). Clarke 2008 abstract via WebSearch (jech.bmj.com/content/62/8/752).


### L7-07 Within/between decomposition when clusters are tiny: who informs the within effect, and how unreliable the means are

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P7). Verdict: partly_correct.


Claim. P7 misses two consequences. (a) In a Mundlak or cluster-mean-centred random-intercept model, the within coefficient equals the fixed-effects within estimator and is informed only by clusters with at least 2 observations and nonzero within-variance of x. Simulation: 300 families, 184 with one child. The Mundlak within coefficient was 0.40104, the fixed-effects within estimate was 0.40104 and the estimate from the 116 two-child families alone was 0.40104. The 'within effect' is therefore a sibling-comparison estimate in a selected subsample. (b) The between or contextual coefficient uses observed cluster means, whose reliability is ICC(2) = n*ICC(1)/(1+(n-1)*ICC(1)): 0.33 for n=2 and ICC(1)=0.2, versus 0.86 for n=25. Manifest aggregation biases the contextual effect, and the multilevel latent covariate approach corrects this (Luedtke et al. 2008). In longitudinal data, person means of a predictor with a time trend mix the trend into both components, so detrending is needed (Wang & Maxwell 2015).


Handling. For each decomposed predictor, report the predictor ICC(1), mean-reliability ICC(2) at the median cluster size, and the number of clusters and rows informing the within effect. Compare the contributing and non-contributing clusters on observed covariates. State whether cluster means were computed before or after listwise deletion (store this choice). Flag a time-varying predictor that is correlated with time before person-mean centring.


Parity. Exact tier for the counts and ICC(1) from the ANOVA estimator. A model-based ICC falls in the numerical-tolerance tier.


Verifier's correction. Report ICC(2) only together with the sampling ratio: whether the cluster is fully observed or a sample of members. Warn about manifest-aggregation bias only for sampled clusters. Note that the latent-covariate fix is outside the supported engines.


Verifier's reasoning. Part (a) is verified. On rerun, Mundlak within = FE within = two-child-only estimate = 0.40104, and singletons have xw = 0. This holds for random-intercept Gaussian models only, not with random slopes or in GLMMs. The ICC(2) arithmetic is right (0.333, 0.862). Part (b) overstates. Lüdtke et al. (2008) show that the bias of the manifest mean depends on the sampling ratio, and that the manifest approach can be more accurate when the sampling ratio approaches 100%. In family data where all children of each family are observed, the family mean has no sampling error, so applying the latent-covariate correction is inappropriate. The latent-covariate model also needs SEM-type software (Mplus, lavaan multilevel), not lme4, glmmTMB or statsmodels. Wang & Maxwell (2015) do cover detrending (Psych Methods 20, 63-83).


Evidence checked. Re-ran scratchpad/L7/t1_families.py (0.40104 three times). Lüdtke 2008 abstract via WebSearch (acuresearchbank.acu.edu.au, statmodel.com), with the sampling-ratio finding. Wang & Maxwell 2015 abstract via WebSearch (library record mentioning detrending).


### L7-08 Distinguishable dyads (parent-child): negative dependence, non-identified decompositions, APIM layout

Kind: edge_case. Stream: both. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. For distinguishable dyads, non-independence is measured by the Pearson correlation between roles (Kenny). (1) A dyad random intercept forces the within-dyad covariance to be at least 0. Simulation: 200 dyads, true correlation -0.4, role variances 1 and 4, sample r = -0.327. The statsmodels random-intercept dyad variance was 0.034, at the boundary, with converged=False. A singular-fit routine would wrongly read this as 'no dependence'. (2) With one observation per role per dyad, (0+role|dyad) plus a residual variance is not identified: 4 parameters against 3 distinct moments. In the same data, the fit returned role variances 0.418 and 3.317 with residual 0.569. The marginal 2x2 covariance was recovered, but the split between random effect and residual is arbitrary. Valid specifications are a marginal unstructured 2x2 covariance (nlme::gls with corSymm and varIdent by role) or (0+role|dyad) in glmmTMB with dispformula=~0, which fixes the residual near zero. (3) An actor-partner (APIM) analysis needs partner-predictor columns, i.e. a pairwise data layout.


Handling. Detect dyads: a grouping factor with cluster size 2 or less plus a role variable that varies within the cluster. Check that each dyad has exactly one member per role, and list duplicates and missing partners. Before fitting, report the within-dyad r and the variance ratio by role. Warn on random-intercept-only models when r < 0, and on random effect plus residual decompositions. Offer the marginal-covariance specification, and generate partner_x columns for APIM.


Parity. The audits and r are exact. The recommended marginal model is engine-specific, so record the specification in the JSON and mark the tier per engine.


Verifier's correction. Require a declared role variable and a distinguishable or indistinguishable flag. Use Pearson r for distinguishable dyads and the ICC for indistinguishable ones. Note that lmer will stop on (0+role|dyad), and recommend nlme::gls with corSymm/varIdent or glmmTMB with dispformula = ~0. Mark the Python side as lacking an equivalent marginal model.


Verifier's reasoning. I reproduced the numbers: r = -0.327, random-intercept variance 0.034 with converged False, and (0+role|dyad) variances 0.418 and 3.317 with residual 0.569. These match the observed 2x2 marginal covariance. Kenny's page confirms Pearson r for distinguishable dyads, and his materials note that variance-based methods cannot represent negative nonindependence. The glmmTMB documentation confirms that dispformula = ~0 fixes the Gaussian residual at a small value (default sqrt(.Machine$double.eps)). Gaps: (i) lmer refuses (0+role|dyad) on complete dyads by default, because nobs = nRE triggers check.nobs.vs.nRE = 'stop'. The flat-ridge problem therefore arises in statsmodels and glmmTMB, while lme4 errors. (ii) The detection rule ('cluster size <= 2 plus a within-cluster-varying role') also fires on indistinguishable dyads and on any pair with a covariate that differs (sibling sex, twin birth order). Those need the intraclass correlation, not Pearson r. (iii) On the Python side, statsmodels has no ready marginal model with an estimated unstructured 2x2 covariance.


Evidence checked. Re-ran scratchpad/L7/t2_dyads.py. glmmTMB R/glmmTMB.R roxygen from GitHub. lme4 R/modular.R. Kenny via WebSearch (https://davidakenny.net/dyad.htm, bgsu.edu slides).


### L7-09 Growth models: occasions per person, time metric and time centring

Kind: edge_case. Stream: B. Priority: essential. Origin: new (P3). Verdict: partly_correct.


Claim. This is the continuous-time analogue of P3. With two common occasions per person, random intercept variance + random slope variance + their covariance + residual variance makes 4 parameters for 3 distinct moments, so the model is not identified. Optimisers still report convergence. Simulation (300 persons, t in {0,1}): default, lbfgs and powell all gave the same REML log-likelihood (-929.562) but slope variance from 0.259 to 0.396 and residual from 0.357 to 0.426, all with converged=True. With 3 occasions, all optimisers agreed (slope variance 0.121, residual 0.45). With 2 occasions at irregular times, the model is identified but weakly. Irregular timing (assessment dates that vary within a wave) also makes wave index the wrong time metric, and elapsed time or age should be used. The intercept and the intercept-slope covariance and correlation depend on where time = 0 is placed.


Handling. Count distinct time values per unit and block a random time slope when most units have 2 or fewer occasions at common times. Flag a wave-index time variable when a date or age column varies within a wave beyond a tolerance. Report the time-zero point and warn that the intercept-slope correlation is not invariant to recentring. Classify each covariate as time-invariant or time-varying (see L7-07).


Parity. Exact tier for the audit. The flat-ridge demonstration belongs in docs, not tests.


Verifier's correction. Identification fails only when every unit has the same two time values. Even a minority of units with three or more occasions, or with varied time values, identifies the model, though possibly weakly. Warn with the number of units carrying extra information rather than blocking. Note that lmer errors on nobs <= nRE regardless of identification. Fix the 3-wave figures (slope variance 0.272, covariance 0.121).


Verifier's reasoning. The non-identification argument for two common occasions is right. My rerun reproduced the same REML llf -929.562 with slope variance from 0.259 to 0.396, all converged. Errors: (1) The 3-wave numbers are misreported. The slope variance is 0.272, and 0.121 is the intercept-slope covariance (the script prints [var0, cov, var1]). (2) 'Optimisers still report convergence' does not apply to lme4. lmer stops by default with 300 persons x 2 random effects = 600 = nobs. It also stops for the identified irregular-time 2-wave case. (3) The blocking rule 'most units have <= 2 occasions' is wrong. With 80% of persons at two waves and 20% at three, all optimisers agreed (llf -1013.335, slope variance about 0.29 against true 0.25). Identification depends on whether any units supply extra moments, not on the majority.


Evidence checked. Re-ran scratchpad/L7/t3_twowave.py. New run scratchpad/L7adv/a1_ident.py, part B. lme4 source R/lmerControl.R and R/modular.R (check.nobs.vs.nRE).


### L7-10 Attrition in longitudinal and cluster data: persons and clusters lost as well as rows, with MAR stated precisely

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P12). Verdict: partly_correct.


Claim. P12's 'missing outcomes are handled under MAR by likelihood' holds only conditionally. Dropout may depend on the person's earlier observed outcomes and on variables in the model, not on omitted variables or on the unobserved current value. Listwise deletion behaves very differently by the level at which the variable is missing. A missing time-invariant covariate removes every occasion of that person. A missing time-varying covariate removes single occasions, which effectively turns covariate missingness into outcome missingness. In cluster-randomised trials, whole-cluster dropout (a school leaving) is a separate mechanism and can differ by arm.


Handling. Report N per wave, persons lost and rows lost separately and attributed to the variable responsible, and monotone versus intermittent patterns. In cluster designs, report clusters lost per arm. Give descriptive baseline comparisons of completers and dropouts, explicitly labelled as not a test of MAR, which cannot be tested. Suggest auxiliary variables or a pattern-mixture sensitivity analysis (dropout pattern x time). Point out that missing covariates need multiple imputation or FIML outside the LMM.


Parity. Exact tier.


Verifier's correction. State that likelihood analysis is valid under MAR given the variables in the model and a correctly specified covariance structure. Complete-case deletion due to covariates is unbiased for regression coefficients if missingness is independent of the outcome given the covariates, and is otherwise potentially biased. MI or FIML are options, not requirements. Keep the reporting tables.


Verifier's reasoning. The accounting of persons, rows and clusters is right, as are the warning that MAR cannot be tested against MNAR and the time-invariant versus time-varying distinction. Three statements are imprecise or wrong. (1) Likelihood ignorability under MAR also needs a correctly specified joint model, including the covariance structure. When dropout depends on earlier outcomes, a misspecified random-effects or residual structure biases the fixed effects. (2) 'Missing covariates need MI or FIML' is too strong. Complete-case analysis of rows with missing covariates is unbiased for the regression coefficients when covariate missingness does not depend on the outcome given the covariates. It then costs efficiency, not validity. (3) Deleting occasions with a missing time-varying covariate does not 'turn covariate missingness into outcome missingness' in a way that inherits MAR. The deletion mechanism is whatever drives x's missingness. If that depends on y, the deletion is not ignorable. No sources were given and none were checked.


Evidence checked. Reasoning from standard missing-data theory (ignorability conditions, and complete-case regression validity when missingness depends only on covariates). No web source confirmed in this session.


### L7-11 Residual autocorrelation with irregular timestamps: within-unit semivariogram, not a lag-1 ACF

Kind: correction. Stream: A. Priority: valuable. Origin: preliminary (P25). Verdict: partly_correct.


Claim. For app-log and intensive longitudinal data, a lag-1 ACF or Durbin-Watson on stacked residuals is invalid: it pairs residuals across unit boundaries and treats a 1-minute gap the same as a 3-day gap. The right tool is the empirical semivariogram of within-unit residual pairs binned by time lag, as nlme::Variogram does with form = ~ time | unit, using only pairs within the same group. On the modelling side, lme4 has no residual correlation structures. glmmTMB's ar1 needs a factor of evenly spaced time levels, and its ou structure handles irregular times (via numFactor) but only positive correlation (glmmTMB covariance-structure vignette).


Handling. Sort conditional residuals by timestamp within unit. Compute the binned within-unit semivariogram and report it with the lag-gap distribution: median, maximum and share of gaps above k x the median. If dependence decays with lag, recommend ou or CAR1-type structures for irregular times. Recommend ar1 only when time levels are regular.


Parity. The semivariogram from given residuals is deterministic and needs a shared binning spec, so exact tier on fixed residuals and numerical tolerance overall.


Verifier's correction. Compute within-unit semivariograms on both marginal and conditional residuals, and label which is which. Recommend glmmTMB ou for irregular times. Recommend ar1 when times sit on a unit grid, even with gaps, provided all factor levels are retained. CAR1 is nlme-only. Python has no residual-correlation remedy in MixedLM.


Verifier's reasoning. These points are confirmed. The nlme Variogram.lme help says that, with a grouping factor, only within-group pairs are used, and residual type defaults to 'pearson'. In the glmmTMB covstruct vignette, ar1 needs unit-spaced factor levels, users are warned not to omit levels for missing times, and ou uses numFactor coordinates with rho = exp(-exp(theta2) d), always positive. Corrections: (1) Variogram.lme works on nlme lme objects, not lme4 or glmmTMB fits, so the suite must reimplement it. (2) Regular-grid data with missing occasions can still use ar1 if all levels are kept, so 'ar1 only when regular' should read 'only when on a unit grid'. (3) CAR1 (corCAR1) is nlme-only, outside the supported engines. statsmodels MixedLM has no residual correlation structures, so the Python side can diagnose but not remedy. (4) Conditional residuals are partly absorbed by random slopes and are correlated by construction in short series. A semivariogram of marginal residuals (or of an OLS fit of the mean model) is the classic exploratory tool for separating the components, so state which residuals are used.


Evidence checked. nlme man/Variogram.lme.Rd (CRAN GitHub mirror, fetched with curl). glmmTMB vignettes/covstruct.rmd from GitHub, lines 77-79 and 139-141 (ar1 unit spaced, ou rho formula, missing-levels warning).


### L7-12 Intensive longitudinal app logs: level-specific information, multiple time scales, lag construction

Kind: feature. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. With tens of thousands of log events from a few dozen children, any child-level predictor (age, SES, treatment) is informed by about J - p_between children, whatever the number of rows. Events are usually nested in sessions and days within children, which gives several candidate grouping levels and daily or weekly cycles. When the lagged outcome is used as a predictor with person-mean centring, the autoregressive effect is biased downward (Hamaker & Grasman 2015). Lags computed by row shift on stacked or unsorted data cross unit boundaries and ignore gaps.


Handling. Report, per predictor, the level at which it varies and the number of independent units informing it. Do not lead with the row count. Optionally segment sessions using a user-set gap threshold, and report the ICC at each level (event, session, day, child). Build lags inside the suite, within unit, sorted by time and with a maximum-gap rule (otherwise NA). Flag a lagged outcome combined with person-mean centring when the number of observations per person is small. Flag time-of-day and weekday structure for possible inclusion.


Parity. Session segmentation and lag construction must be specified exactly (inclusive or exclusive gap threshold, time-zone handling) to reach exact parity.


Verifier's correction. Flag a lagged outcome with person-mean centring when T per person is small, with the severity decreasing in T. Classify session and day as nested or partially crossed from the data, with a declared time zone. Mark lagged-outcome checks as outcome-aware.


Verifier's reasoning. The Hamaker & Grasman (2015) finding is confirmed: cluster-mean centring generally biases the autoregressive (within) slope downward. The level-specific N point is sound. Caveats: (1) This is a Nickell-type small-T bias that shrinks as occasions per person grow, so the flag should scale with T. (2) Events are not necessarily nested in sessions within days, because sessions can cross midnight and local time zones move day boundaries. Session and day are then partially crossed, and the L7-01 classifier should be applied rather than assuming nesting. (3) A lagged outcome is outcome-dependent, so this flag cannot run in outcome-blind mode.


Evidence checked. WebSearch on Hamaker & Grasman (https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4310502/): 'cluster mean centering will in general lead to a downward bias in the parameter estimate of the within-cluster slope (i.e., the autoregressive relationship)'. The full text was not reachable, so the T-dependence is from general Nickell-bias theory.


### L7-13 Informative cluster size and informative observation times (app usage, corpus word frequency)

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Cluster size is often caused by the phenomenon being studied. In app logs, the number of events per child reflects engagement. In corpora, a word's frequency counted in that same corpus is exactly the size of the word cluster (log tokens per word). When cluster size is related to outcomes (informative cluster size), the LMM's fixed intercept and slopes target neither the per-observation nor the per-cluster average, and a predictor that is close to log cluster size is confounded with the weighting (Seaman, Pavlou & Copas 2014). In longitudinal data, outcome-dependent observation times bias standard analyses (Pullenayegum & Lim 2016).


Handling. In outcome-blind mode, report the correlation of each predictor with log cluster size per grouping factor, and flag predictors with |r| > 0.9 or a functional identity. In outcome-aware mode, report the correlation between cluster size and the cluster-mean outcome. Suggest sensitivity analyses: log cluster size as a cluster-level covariate, and cluster-weighted estimates. For app logs, report events per child against child covariates.


Parity. Exact tier.


Verifier's correction. Informative cluster size mainly distorts the intercept, cluster-level covariate effects and heterogeneous effects. Slopes of within-cluster covariates are unaffected when cluster size relates only to the random intercept. Flag a predictor-cluster-size identity only when frequency is computed from the same data. Label the cluster-size-by-outcome correlation as outcome-aware and as a sensitivity check, not a model-selection input.


Verifier's reasoning. Both sources are confirmed: Seaman, Pavlou & Copas, Stat Med 33(30), 5371-5387 (UCL Discovery 1437178), and Pullenayegum & Lim, SMMR 25(6), 2992-3014, PMID 24855119. The claim that the LMM's 'fixed intercept and slopes target neither' average is overstated for within-cluster covariates. In a simulation with cluster size driven by the random intercept (200 clusters, 40 replicates), the LMM slope for within-cluster x was 0.494 (true 0.5), unaffected. The LMM intercept was 0.144, between the per-cluster mean (-0.011) and the per-observation mean (0.839), as claimed. The corpus 'word frequency = cluster size' identity holds only if frequency is counted from the analysed sample, not from an external norm such as SUBTLEX.


Evidence checked. scratchpad/L7adv/a4_ics.py: 'LMM intercept 0.144  LMM slope 0.494  per-obs mean 0.839  mean of cluster means -0.011'. Both citations confirmed by WebSearch.


### L7-14 Counterbalanced (Latin-square) experiments and restriction of the one-observation-per-cell rule to Gaussian

Kind: correction. Stream: B. Priority: essential. Origin: preliminary (P3). Verdict: partly_correct.


Claim. P3 is right for Gaussian LMMs. In Latin-square language experiments, each subject sees each item once, so a subject:item intercept is confounded with the residual. Condition is within-subject and within-item, but for a given item it varies only across lists, i.e. between subjects, and exclusions unbalance this. The 'likewise' does not carry over across families. With Bernoulli data, an effect with one observation per subject-item pair is an observation-level random effect. Under probit, it is exactly non-identified, because it only rescales the latent residual. Under logit, it is identified only through differences in link shape. With binomial data with more than one trial per row, or Poisson data, an observation-level random effect is an identified overdispersion term.


Handling. Detect a list variable, or infer lists from the subject-to-item-condition assignment. Report item x condition counts, subjects per list and list x condition balance after exclusions. Check that, within each list, each item appears in exactly one condition. Apply the subject:item and one-observation-per-cell rules family by family: error for Gaussian and Bernoulli, allowed as overdispersion for Poisson and multi-trial binomial.


Parity. Exact tier.


Verifier's correction. Gaussian: error (lmer errors anyway, and the suite should explain why). Bernoulli: exactly non-identified under probit, weakly identified under logit, so give a strong warning. Poisson and multi-trial binomial: allowed as overdispersion.


Verifier's reasoning. The Latin-square structure is correct, as is the confounding of subject:item with the residual in Gaussian models when there is one observation per pair. The OLRE points are also correct: an OLRE is non-identified under probit (observationally equivalent to a rescaled model), identified only through link shape under logit, and an identified overdispersion term for Poisson and multi-trial binomial. lmer already stops on the Gaussian case, because check.nobs.vs.nlev = 'stop' and nlev >= n is unidentifiable when allow.n = FALSE. glmer passes allow.n = TRUE, so a Bernoulli subject:item term fits silently. A suite check therefore adds value for Bernoulli. But for logit, the term is technically, though weakly, identified, so a hard 'error' overstates it. A strong warning with the probit equivalence explanation is accurate. No sources were given.


Evidence checked. lme4 R/modular.R from GitHub: lFormula uses allow.n = FALSE and glFormula uses allow.n = TRUE (comment 'TODO: allow.n = !useSc'). Defaults in R/lmerControl.R. The probit/logit argument is analytic.


### L7-15 Crossed subjects and items: per-factor level tables for classification, collinearity and N

Kind: feature. Stream: B. Priority: essential. Origin: preliminary (P2). Verdict: partly_correct.


Claim. P2's within/between classification has to be done separately for each crossed factor. Item properties (frequency, length, age of acquisition) are between-item, so by-item slopes for them are unidentifiable, but they are usually within-subject, so by-subject slopes are identifiable. The reverse holds for subject properties (age, vocabulary). The design-justified maximal structure (Barr et al. 2013) follows from this two-way classification. Collinearity among item properties and their effective N are item-level quantities. Trial-level VIF weights items by their number of trials, so in unbalanced data it differs from the item-level value. Ignoring stimulus variance inflates Type I error (Judd, Westfall & Kenny 2012).


Handling. Build one 'level table' per grouping factor, one row per level, holding variables constant within that level. Run classification, VIF and GVIF, and descriptives on those tables. Report N_items and N_subjects as the sample sizes for item- and subject-level predictors. Derive the maximal structure with one term per factor.


Parity. Exact tier.


Verifier's correction. Report N_items and N_subjects as the primary counts for item- and subject-level predictors. Do not call them 'the' sample size, and note that their effective information depends on both random-effect variances. Verify per subject that the property varies across the items that subject saw before declaring a by-subject slope identifiable.


Verifier's reasoning. The two-way classification and level-table approach are correct, and so is the trial- versus item-level VIF weighting point. 'Report N_items and N_subjects as the sample sizes' is an approximation. In crossed designs, the precision and effective df of an item-level predictor depend on the item variance and on the subject-by-predictor slope variance and N_subjects, not on N_items alone (the Westfall/Judd/Kenny power framework). By-subject slopes for an item property are identifiable only if each subject sees several items that differ on that property, which fails in some list designs. The Barr et al. PDF URL is a standard host. The Judd, Westfall & Kenny 2012 PubMed ID was not checked (PubMed blocked).


Evidence checked. Reasoning plus the design algebra of crossed random effects. Sources not re-verified (pubmed and pmc unreachable from this session).


### L7-16 Trial-level RT and accuracy data: scale of inference, exclusion provenance, sequential effects

Kind: feature. Stream: both. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. (a) RTs are positive and right-skewed. A log or inverse transform changes the scale on which effects are additive, so whether an interaction exists depends on the scale. A GLMM (e.g. Gamma or inverse-Gaussian with identity link) avoids transforming (Lo & Andrews 2015). (b) Error trials and trimmed trials are excluded before fitting, and not at random: harder conditions lose more trials. Exclusions can empty or thin subject x condition cells, so Stream B must see the pre-exclusion data. (c) RTs depend on practice, fatigue and the previous trial (Baayen & Milin 2010).


Handling. Ask for a declared outcome type (rt, accuracy) and a scale of inference. In Stream A, optionally refit on the alternative scale and flag a change in sign or significance for interactions. Accept an exclusion flag column, report exclusions by subject x condition and item x condition, list cells that fall below k trials and subjects removed entirely, and store the exclusion rule in provenance. Check residuals against trial number within subject and against the previous-trial RT.


Parity. The exclusion tables are exact. The alternative-scale refit is in the numerical-tolerance tier where both engines support the family, and engine-specific otherwise.


Verifier's correction. Classify the interaction of interest as crossover or removable. Run the alternative-scale fit only as a pre-declared sensitivity analysis, reported alongside the primary scale, never as a selection criterion. Keep the exclusion-provenance tables, which are sound.


Verifier's reasoning. Lo & Andrews (2015) is confirmed (Front Psychol, DOI 10.3389/fpsyg.2015.01171). It argues that transformations distort additive relationships. Overstatements: (1) 'Whether an interaction exists depends on the scale' holds only for removable (non-crossover) interactions. Crossover interactions survive any monotone transformation. (2) The handling, 'refit on the alternative scale and flag a change in sign or significance', creates a garden of forking paths. It must be a pre-declared sensitivity analysis that never replaces the declared scale of inference. (3) A Gamma or inverse-Gaussian GLMM with identity link commits to a particular mean-variance relation and often has convergence problems, so it does not 'avoid' modelling choices. I could not confirm the paper's exact family and link recommendations, or the Baayen & Milin URL.


Evidence checked. WebSearch on Lo & Andrews (https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4528092/). The full text was not reachable. Scale invariance of crossover interactions is analytic.


### L7-17 Single-trial EEG: electrodes and time windows as repeated measures within trial, retained-trial counts, and baseline as covariate

Kind: edge_case. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. Long-format EEG with one row per subject x trial x electrode (x time window) has strongly correlated residuals within a trial across electrodes. Without a subject:trial grouping level, or aggregation to regions of interest, the effective replication unit (the trial) is overcounted many times over. Artefact rejection leaves unequal trial counts per condition. LMMs tolerate this imbalance (Froemer, Maier & Abdel Rahman 2018), but subject x condition cells with very few trials still drive by-subject slopes. Alday (2019) proposes entering the baseline-interval amplitude as a covariate instead of subtracting it.


Handling. Detect when several rows share a subject x trial key and differ only by a channel or time-window variable. Error if no grouping at the trial level, or aggregation, is specified. Report retained trials per subject x condition, flagging cells below k. If a baseline column is declared, suggest the covariate approach. Cross-reference P34 for data size.


Parity. Exact tier.


Verifier's correction. Warn rather than error. Recommend ROI aggregation or per-channel/ROI models as the default. If several channels stay in one model, require that the reference scheme be declared. Note that, under average reference, a trial intercept is degenerate, and that channel dependence needs a spatial structure or aggregation.


Verifier's reasoning. Frömer et al. (2018) is confirmed: single-trial LMMs are 'robust to unequal numbers of observations per cell'. The handling's hard error is misleading. With average-referenced EEG, the values across all channels sum to zero within each trial. A subject:trial random intercept then has exactly zero variance, so the term the error demands carries no information. Channel residual dependence is spatially structured, with negative correlations under average reference, not compound symmetric. Simulation: 32 channels, 200 trials, strong common trial component. After average referencing, the maximum absolute trial mean was 3e-16, the mean off-diagonal channel correlation was -0.0322 (= -1/31) and the statsmodels trial random-intercept variance was 2.6e-11. A trial intercept captures only a common shift. With a channel subset or ROI, the sum-to-zero constraint loosens, but dependence remains structured.


Evidence checked. scratchpad/L7adv/a2_multisite_eeg.py (EEG part). WebSearch on Frömer et al. 2018 (PMC5810264, Frontiers epub).


### L7-18 Corpus data: connectedness of crossed speakers x words, Zipfian dominance, unidentifiable rare-level effects

Kind: feature. Stream: B. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. (a) With fixed effects for speakers and words, the rank of [speaker dummies | word dummies] is S + W - C, where C is the number of connected components of the bipartite speaker-word graph (verified numerically with S=45, W=65, C=3, rank 107). This is the connectedness problem of Weeks & Williams (1964), implemented in lfe::compfactor. With random effects, shrinkage makes the model estimable, but differences between components (e.g. regions with disjoint vocabularies) cannot be attributed to speakers or to words. (b) Under Zipfian imbalance, a few words and speakers supply most tokens, so fixed effects are token-weighted towards them. (c) Words with a single token contribute almost nothing to the word variance, and their BLUPs are shrunk to about zero. Speaker:word cells are mostly single tokens, as in P3.


Handling. Compute and report the connected components of every pair of crossed factors, with component sizes. When C > 1, suggest a component-level fixed effect. Report the distribution of tokens per level and the share held by the top 1%. Offer a leave-top-k-words-out sensitivity refit. Mark BLUPs of levels with fewer than k observations as not interpretable in reports.


Parity. Connected components are deterministic, so exact tier. Use scipy.sparse.csgraph in Python and igraph or a self-written union-find in R.


Verifier's correction. Report that each level's weight saturates under random effects, and give the effective weight shares (n/(sigma^2+n tau^2) normalised) after fitting. Report the shrinkage factor per level instead of asserting near-zero BLUPs. Drop or verify the Lancaster eprint source.


Verifier's reasoning. The rank identity S+W-C is verified (rerun: 45, 65, C=3, rank 107), and the connectedness and component point is sound. Two overstatements: (b) With by-word random intercepts, fixed effects are not token-weighted. A word's weight on a word-level coefficient is roughly n_w/(sigma^2 + n_w tau^2), which saturates at 1/tau^2. High-frequency words therefore cannot dominate the way they would in OLS. Token weighting applies only when tau^2 is near 0. (c) For a single-token word, the BLUP shrinkage factor is tau^2/(tau^2+sigma^2). It is near zero only when the word variance is small relative to the residual, which is often but not always the case in RT data. The Lancaster eprint 59866 could not be identified.


Evidence checked. Re-ran scratchpad/L7/t4_connect.py. The weight and shrinkage formulas are standard random-intercept algebra. WebSearch for eprints.lancs.ac.uk 59866 found no matching record.


### L7-19 Duplicates must be judged against a declared observation key, not whole rows

Kind: correction. Stream: B. Priority: valuable. Origin: preliminary (P15). Verdict: correct.


Claim. Exact duplicate rows are often legitimate, for example corpus tokens coded only by categorical variables (same speaker, word and context), binary trial data without a trial index, and concurrent app events within the timestamp resolution. Conversely, when an EEG or app table loses its electrode or event-type column, legitimate rows look like duplicates. Duplicate time points within a unit are an error only relative to the declared time resolution and design.


Handling. Require or infer an observation key (unit, time, trial, electrode, token ID). Report three classes. (i) Duplicate keys with conflicting values are an error. (ii) Duplicate keys with identical values are a possible double import. (iii) Identical rows with no key are informational only. Use the declared timestamp resolution for time-point checks.


Parity. Exact tier. Floating-point time comparisons need a shared tolerance rule.


Verifier's reasoning. Duplicates can only be judged against a declared observation key: corpus tokens, binary trials without an index, and timestamp-resolution collisions all produce legitimate identical rows. The three-class scheme is coherent. One caution is that an inferred key can make true duplicates look legitimate, because a key inferred to make rows unique is circular. Classes (i) and (ii) should therefore require a declared key, and with an inferred key, only informational output should be given.


Evidence checked. Logical analysis. No external source needed.


### L7-20 Bounded child-assessment scores and accuracy at ceiling

Kind: feature. Stream: B. Priority: valuable. Origin: preliminary (P13). Verdict: partly_correct.


Claim. In education data, a common P13 case is a count of correct answers out of a known maximum, which is binomial (cbind(correct, max - correct)) or beta-binomial rather than Gaussian. Ceiling effects at later waves compress growth, producing shrinking variance across waves, a spurious negative intercept-slope covariance and heteroscedasticity by wave. A commonly used criterion flags floor or ceiling effects when more than 15% of respondents are at the extreme (Terwee et al. 2007, with the 15% confirmed only via secondary sources). In psycholinguistic experiments, near-ceiling accuracy gives many subject x condition cells at 100%, which pushes by-subject slope variances to 0 or correlations to +/-1.


Handling. Accept declared score bounds. Report the proportion at the floor and ceiling per wave and per group, and the SD per wave. Suggest a binomial or beta-binomial model when the maximum is known. For binary accuracy, report the proportion of subject x condition and item x condition cells at 0% or 100%, and link these to singular-fit messages.


Parity. Exact tier.


Verifier's correction. Present the 15% figure as a psychometric reporting convention, not a model trigger. Prefer an item-level GLMM when item responses are available, and binomial or beta-binomial for sum scores otherwise. Report floor and ceiling shares per wave, which the simulation shows drive the spurious negative covariance.


Verifier's reasoning. The ceiling mechanism is confirmed by simulation. With five waves, a 30-point maximum and a true intercept-slope covariance of 0, the share at ceiling rose through 0, 0.03, 0.18, 0.46 and 0.70, and the SD fell from 3.47 to 2.26. The fitted intercept-slope correlation was -0.70 on observed scores against 0.01 on latent scores. Caveats: Terwee et al. (2007) is a quality criterion for health-status questionnaires (positive rating <=15% at the extremes, negative >15%, per reproductions of the table), not a statistical threshold for choosing a model. A binomial model for sum scores assumes exchangeable items with one probability per person. When item-level responses exist, an item-level (explanatory IRT-type) GLMM is preferable, and beta-binomial handles residual over- or under-dispersion only partly.


Evidence checked. scratchpad/L7adv/a3_ceiling.py. Terwee 2007 criterion via WebSearch (reproduced criteria tables, research.vu.nl copy).


### L7-21 Domain effect sizes with explicit variance denominators

Kind: feature. Stream: A. Priority: valuable. Origin: new. Verdict: partly_correct.


Claim. In cluster-randomised and multilevel education designs, a standardised mean difference depends on which SD is used: within-cluster, between-cluster or total. Hedges (2007) defines three such effect sizes, with estimators and SEs, and a 2011 paper extends this to three levels. Reports that give a bare 'd' are ambiguous and are not comparable with effect-size benchmarks.


Handling. From the fitted variance components, compute delta_W, delta_B and delta_T (and the three-level variants), always labelled with the denominator. Include ICCs at each level and the design effect. For RT studies, report effects on the response scale (ms), not only standardised.


Parity. Deterministic given the variance components, so numerical-tolerance tier.


Verifier's correction. Compute the effect sizes from unconditional (covariate-free) variance components, or label them as adjusted. Implement the five three-level effect sizes from Hedges (2011). Report the design assumptions behind each SE.


Verifier's reasoning. Hedges (2007), JEBS 32(4), 341-370, is the two-level source. Hedges (2011), JEBS 36(3), 346-380, defines five effect sizes for three-level designs, not three-level 'variants' of the same three. An important omission is that computing delta from a model that includes covariates uses residual (conditional) variance components. This inflates d relative to benchmarks, which assume unadjusted SDs. Denominators should come from unconditional variance components, or the adjustment should be stated. Hedges' SE formulas also assume specific designs (equal or known cluster sizes).


Evidence checked. WebSearch confirmed Hedges 2011 (RePEc listing, Bohrium summary 'defines five effect sizes') and the Hedges 2007 citation (econpapers). The full texts were not accessed.


### L7-22 Declared design templates that drive the checks and are checked against the data

Kind: architecture. Stream: infrastructure. Priority: essential. Origin: new. Verdict: partly_correct.


Claim. Most of the domain failures above (wrong randomisation level, role-incomplete dyads, broken counterbalancing, missing trial level in EEG, partial nesting) can only be detected if the suite is given the intended design. A generic audit cannot tell 'class reused across schools' from 'pupil moved school', or a legitimate repeated token from a duplicate.


Handling. Add a design declaration to the shared spec. It names a design type (cluster_rct, multisite, longitudinal, dyadic, crossed_experiment, ild, corpus, eeg) and keys (unit IDs, time and resolution, role, list, trial, channel, randomisation unit, blocking variables, score bounds, exclusion flag). Stream B validates the data against the declaration first and reports mismatches as top-severity findings. The declaration selects domain checks and message wording, is stored in the results JSON and provenance, and works in outcome-blind mode (P17), so it can be preregistered.


Parity. The declaration schema, its validation rules and its defaults live in the vendored YAML and JSON Schema, so both languages run the same checks.


Verifier's correction. Make the declaration compositional: a set of design features and keys, not one type. Let undeclared runs fall back to inferred structure with lower-confidence wording. Store a hash and creation time of the declaration in provenance, and flag declarations modified after an outcome-aware run.


Verifier's reasoning. A declared design is valuable and makes the outcome-blind and preregistration workflow concrete. Overstatements and design flaws: (1) Some of the listed failures can be detected without a declaration: L7-01 nesting classification, EEG key duplication, connected components. The declaration resolves ambiguity rather than being the only route to detection. (2) A single design-type enum cannot express common combinations: a multisite cluster RCT with longitudinal follow-up, longitudinal dyads, an EEG crossed experiment. (3) If the declaration is used for preregistration, it must be hashed and timestamped before the outcome is seen, or users can edit it post hoc to silence warnings.


Evidence checked. Design reasoning, cross-checked against the other items (L7-01, L7-17, L7-18), where detection works partly from data alone.


## Completeness critic

### Gaps


#### Stream A must accept models the user has already fitted, and check any refit against the original

Most users will want diagnostics on a model they have already fitted (lmerMod, lmerModLmerTest, afex 'mixed', glmmTMB, statsmodels MixedLMResults), not a second fit made by the package. A package refit can quietly differ from the user's model in its use of REML or ML, the optimiser and its control settings, per-variable contrasts() attributes and the evaluation environment of the data. In R, it can also differ in options('contrasts'), a global setting that changes the coding of every factor. The report would then describe a different model from the one the user published. Also, lme4's stored model frame keeps only the variables named in the formula, so audits that need other columns (P12 missingness, duplicates against a declared key, candidate grouping columns) cannot be run from the fitted object alone.

Suggestion. Make diagnose(fit, data = NULL) the main Stream A entry point. It fills the fitted-model contract (P32) from the object and records its control settings, contrasts and options('contrasts'). When a refit is needed (ML refits, influence, allFit), first refit the original specification and require the objective to match within tolerance before going further. If it does not match, stop with a 'refit_mismatch' status. Mark audits that need the full data as 'not_assessable' unless data is supplied.


#### Stream A should re-run the Stream B audits on its own analysis sample and reconcile them with any earlier Stream B result

Many users will skip Stream B entirely. Others will run Stream B outcome-blind on a design table and then fit Stream A on data that has since gained rows, lost rows with a missing outcome or had levels recoded. What Stream B certified earlier no longer describes the sample that was fitted. No lens defines how the results of the two streams connect. L1-21 forecasts fit-time behaviour, but nothing compares that forecast with what happened.

Suggestion. Stream A always runs the engine-free structural audits (L1, L2, L3-01/20) on the model frame it fits. If a Stream B spec file is supplied (L6-22), add a reconciliation section. It compares the spec hash with the fitted spec in a term-by-term diff that includes contrasts and RE structure, and it compares the data hash with the fitted data. It also reports the rows and groups added or lost and sets each Stream B forecast (singularity, df budget, aliasing) against the observed outcome. Label a mismatch as a reconciliation finding, not a model defect.


#### Multiply imputed data and plausible values (PISA, TIMSS, PIRLS, NAEP)

Education researchers routinely fit LMMs to m imputed datasets or to 5-10 plausible values, with weights at two levels. No lens covers this case, in which several things break. Structural audits may differ between imputations if grouping or design variables were imputed, and convergence and singularity can differ by imputation. A diagnostic run on one imputation says nothing about the pooled result. Single-level imputation of clustered data biases the ICC and between-cluster covariances towards zero, which Stream A cannot detect from the analysis model alone.

Suggestion. Accept a list of data frames or fits, or mids/mitml objects in R and a list of DataFrames in Python. Run the deterministic audits on every imputation and assert they are identical where they should be. Summarise fit diagnostics as rates across imputations (for example, 3/20 singular). Pool estimates by Rubin's rules and state which df method applies. Require the user to declare the imputation model, and warn when it ignored clustering. Treat plausible values as imputations, not as repeated measures.


#### A remedy catalogue that records engine feasibility, side effects and estimand changes

Each lens says what to detect, but only the random-effects reduction ladder (L1-17) says what to do next. Many remedies need something the declared engines may not offer. Residual AR(1) or variance functions need nlme or glmmTMB, not lme4. CLMMs (L3-13) need ordinal::clmm, which the fitted-model contract does not cover, and smooth functional forms need mgcv. Some remedies change the estimand (cluster-robust SEs, aggregation to cluster level, a population-averaged model). If the suite recommends a remedy it cannot then diagnose, the user is left with no diagnostics at all.

Suggestion. For each check ID, have the registry list remedies. The entry for each remedy records the required engine and capability, whether the suite can diagnose the result, whether the estimand changes, whether the remedy uses the outcome (which makes it exploratory unless pre-declared) and the known side effects. Include non-refit options as well: small-sample cluster-robust SEs such as CR2, regularising priors and a parametric or cluster bootstrap. When the suite cannot diagnose a remedy's result, the report says so in plain words.


#### Audit for omitted clustering

The designed checks look only at the grouping factors in the formula, and no lens checks for clustering the model ignores. Real data often carries such clustering, by rater, interviewer, testing session, classroom within school, stimulus list, recording batch or device. Leaving out an intermediate level (classes within schools) moves its variance to the neighbouring levels and can make SEs of class-level predictors too small.

Suggestion. In Stream B, find candidate grouping columns not in the formula (many repeated values, levels nested in or crossed with the modelled factors) and report how they relate to the modelled structure. This step needs no outcome. In Stream A, compute the residual ICC by each candidate factor, adjusted for multiplicity (L5-15). Report it as 'unmodelled dependence', with the remedy of adding the term only if a declared plan allows it.


#### Cross-level interactions fitted without a random slope for the level-1 component

A model that interacts a within-cluster predictor x with a between-cluster moderator w but omits (x | cluster) puts all slope heterogeneity in the residual. Simulation studies (Heisig & Schaeffer 2019, European Sociological Review, to be verified before it is added to the registry) show that the SE of the cross-level interaction is then too small. L1-04 derives the maximal structure but does not mark this specific minimum.

Suggestion. Stream B classifies each interaction as within, between or cross-level (building on L1-03), and flags any cross-level interaction whose level-1 component lacks a random slope on the same grouping factor. Severity rises when the interaction is a declared focal estimand. Mark the rule as contested against parsimony (see the contested points).


#### Nested-model comparisons on different analysis samples

When the larger model adds a covariate with missing values, listwise deletion makes the two models use different rows. LRTs, AIC differences and R² changes across models (L4-07, L4-14) are then invalid. lme4's anova.merMod stops only when the row counts differ ('models were not all fitted to the same size of dataset', lme4 R/lmer.R) and accepts equal counts made of different rows. The Python side has no such check.

Suggestion. Store a fingerprint of the analysis sample (a hash of sorted canonical row keys) with every fit. Refuse comparisons between fits with different fingerprints, and offer a refit on the common sample with the rows dropped reported. Apply the same rule to the ladder (L1-17) and to sensitivity fits.


#### Declared variable roles and time order: post-treatment covariates and outcome leakage

Data cannot show causal roles, yet several common mistakes are cheap to catch once roles are declared. Examples are adjusting a trial for a covariate measured after randomisation, a cluster-level covariate aggregated from post-treatment data and a median split on the outcome. Another is a predictor computed from the outcome, such as the cluster mean of y including the row's own value, accuracy derived from RT or standardising on the full sample including the outcome. L7-22 templates declare the design but not variable roles or measurement timing.

Suggestion. Add roles to the spec: treatment, baseline, time-varying covariate, post-treatment, mediator, outcome-derived. Warn when post-treatment or mediator variables appear as covariates in a model whose declared estimand is a total effect. In outcome-aware mode, flag predictors that are nearly exact functions of the outcome (R² close to 1 within clusters) or that contain the outcome's cluster means.


#### Import artefacts from SPSS, Stata and SAS: labelled vectors, user-defined missing codes, dates

Psychology and education data often arrive as .sav or .dta files. haven gives labelled numeric vectors and user-defined missing values (na_values, na_range), and pyreadstat exposes equivalent metadata through a different API. Sentinel codes (-9, -99, 999) kept as numbers become extreme values, false outliers and false levels, and they pass every NA-token check (L1-20, L2-21) because they are numbers. Labelled numerics lead directly to the P11 problem. Irregular timestamps (L7-11) also depend on time-zone and daylight-saving handling, which differs between R's POSIXct and pandas.

Suggestion. Read label and missing-value metadata when present, and convert to factors or NA explicitly, recording the mapping in provenance. Flag isolated values equal to common sentinels that sit far outside the bulk of the data. Store canonical timestamps as UTC with the source time zone recorded, and include them in the cross-language hash (L6-19).


#### Lock choices on contested methods before seeing the outcome, and report pre-declared alternatives as sensitivity analyses

Because the literature disagrees, the suite must offer options for the df method, R² definition, residual type, CI method, approximation and influence exclusions. Every option is also a forking path, and a user can shop until p < .05. L5-17 guards against re-specifying the model, but not against choosing inferential methods after the fact.

Suggestion. The spec holds one declared and hashed default per contested choice, fixed before the outcome is seen. The report puts the declared result first. It lists every alternative the user requested, in a fixed order, never only the chosen one, and logs which views were generated. Optionally, a sensitivity module refits pre-declared defensible alternatives (ladder rungs, df methods, leave-one-cluster-out) and reports how stable the focal estimates are. This replaces iterative re-specification.


#### Show which checks share a root cause, so one structural problem does not appear as ten findings

Checks are not independent. One sparse grouping factor can produce a singular fit, a convergence warning, a Satterthwaite df jump (L4-11), degenerate BLUP QQ plots, an unstable ICC and influence flags, all at once. L5-20 switches off degenerate diagnostics after a singular fit, but there is no general dependency model. Without one, reports read as long alarm lists and users fix symptoms.

Suggestion. Add 'explained_by' and 'suppresses' fields to the registry, forming a directed acyclic graph of checks. Group fired flags under their highest root cause. The first screen shows root causes that affect declared estimands, with downstream flags folded under them. Test the graph on the pathology fixtures (next gap).


#### Validate each check against simulations with a known answer before it ships

Severity grades, thresholds and messages (L5-16, L1-08) are only as good as each check's operating characteristics. These are how often the check fires under a correctly specified model, across a grid of designs (J, n_j, imbalance, family), and how often it fires under the misspecification it targets. No lens requires this per check. Without it, thresholds taken from papers become norms with no support.

Suggestion. Make every registry entry carry a validation simulation (code, seed, design grid, false-flag rate, detection rate) that runs in monorepo CI, not on CRAN. Publish a 'pathology zoo' of datasets with planted problems (reused IDs, empty cells, separation, omitted level, autocorrelation, informative cluster size). Use it for golden tests, the check dependency graph and teaching vignettes.


#### Licence compatibility of ported algorithms and of the shared registry

The DESCRIPTION files declare lme4 as GPL (>= 2), DHARMa as GPL (>= 3), HLMdiag as GPL-2 and glmmTMB as AGPL-3. Several items copy upstream behaviour exactly: L1-12/L2-05 copy lme4's column-dropping rule, L3-06 DHARMa-style residuals and L5-08 HLMdiag deletion diagnostics. Doing so by translating the packages' code into a permissively licensed Python package can create a derivative work. GPL-2-only and GPL-3/AGPL-3 code also cannot be combined freely. The vendored registry (P29) needs a licence that both packages can ship.

Suggestion. Decide licences before writing code. Reimplement from published papers and documented behaviour (clean-room), not from translated source, and record the provenance of each algorithm. Licence the registry and JSON Schema permissively, with text under CC-BY. Keep GPL and AGPL engines as runtime dependencies, never as copied code.


#### Phased scope, upstream breakage and a maintenance model

Two packages times three engines times several families, plus reports and a parity harness, is a very large scope for one postdoc. CRAN archives packages whose checks keep failing. glmmTMB depends on binary compatibility with TMB and Matrix, and lme4 changes its output and defaults (L4-01, L4-16), so upstream changes will cause failures. Without a release plan, the suite stays incomplete in both languages, which is a serious risk to adoption.

Suggestion. Release in stages. (1) Engine-free Stream B data audits with exact parity, which are the most distinctive and cheapest feature and have no fitting dependency (L6-16). (2) The fitted-model contract plus Gaussian LMM diagnostics on lme4. (3) The Python mirror. (4) GLMMs and glmmTMB. Keep engines in Suggests with skip_if_not_installed, and run goldens and parity in monorepo CI only. Recruit a co-maintainer per language. Write contribution rules that require a citation and a validation simulation for each check. Consider rOpenSci/pyOpenSci review for credibility.


#### Numerical reproducibility within one language across platforms

P35 and L6-03 deal with differences between languages. Within R alone, BLAS/LAPACK (reference, OpenBLAS, Accelerate, MKL), compilers and Matrix/CHOLMOD versions change optimiser paths. Near-threshold flags (singularity tolerance, gradient checks, VIF cut-offs) can then flip between CRAN check platforms and between the user's laptop and a co-author's. Parallel refits (P24, allFit, bootstraps) are reproducible only if each task gets its own RNG stream, independent of the number of workers.

Suggestion. Add a 'near_threshold' status band instead of a hard pass/fail when a statistic lies within numerical tolerance of its cut-off. Use per-task streams, with parallel::nextRNGStream or future.seed in R and numpy SeedSequence.spawn in Python. Test that results do not depend on the number of workers. Never pin goldens of fit-derived flags on CRAN.


#### Post-fit contrasts and estimated marginal means are where users draw conclusions

Researchers mostly report simple effects, pairwise contrasts and EMMs, not raw coefficients. The coefficient-level work (L2-01, L4-10) does not carry over automatically. What matters here is the df for each contrast (Satterthwaite or KR per linear combination), equal vs proportional cell weights in EMMs, averaging over covariates and over random slopes, and adjustment for multiple comparisons. Back-transformation for GLMMs also matters, because it involves the choice between cluster-specific and population-averaged effects (L3-18). Defaults differ between R and Python tools, so parity breaks exactly where conclusions are drawn.

Suggestion. Add contrasts to the spec as objects in their own right, each a hypothesis matrix L referring to canonical coefficient IDs (L2-06). Compute L-beta, its SE and its df inside the suite from the contract's vcov and df methods, recording the weighting and adjustment used. Test parity on L-beta, not on the output of downstream packages.


#### Native user experience in both languages and support for the data types each ecosystem uses

Making Python users write lme4 syntax (P30) is a barrier to adoption. Data arrive as polars, pyarrow-backed pandas, nullable Int64/boolean dtypes (where pd.NA and np.nan behave differently), pandas categoricals with unused categories, data.table and tibbles. Each handles NA and level order differently, and the parity lenses cover this only for plain types.

Suggestion. Offer a structured spec builder (dict or dataclass in Python, list in R) as well as formula strings, plus an importer for statsmodels formulas that prints its translation. Normalise every input type to the canonical IR (L2-20), with a coercion log. Return native objects with print/summary methods: S3 classes and as.data.frame in R, DataFrames and Jupyter rich display in Python.


#### Generated methods text and tables: a strong adoption driver, and also a source of harm

An auto-generated methods paragraph and APA-style table would make the suite hard to do without. Done badly, it produces lines like 'assumptions were checked and met', omits the reduction history or hides that some checks could not be assessed. Reviewers may then treat the output as a certificate.

Suggestion. Build the text strictly from the results JSON. The mandatory elements of the text are the RE structure as fitted, the reduction steps taken with the rule behind them, the estimation method and approximation, the df method and the analysis N with the groups lost. The text must also name the checks that fired or could not be assessed. Ban phrases such as 'assumptions met'. Use no aggregate scores, badges or pass marks.


#### Predictive goals need cluster-blocked validation, and prediction for existing vs new clusters

Some users (for example, education researchers forecasting student outcomes) fit LMMs for prediction, and none of the lenses covers diagnostics for this goal. Row-level cross-validation leaks cluster information, and predicting for an existing cluster (conditional on its BLUP) differs from predicting for a new one (marginal).

Suggestion. When the declared goal is prediction, replace inference-focused checks with leave-cluster-out or grouped K-fold validation and report conditional and marginal error separately. Test parity on fold assignments, which are deterministic given the declared keys.


### Design risks


- Certification creep: if reviewers and journals start treating a clean mixDiagnostics report as a quality certificate, the suite becomes a gatekeeper. Never emit aggregate scores, pass badges or 'all checks passed' headlines. Every report should state what was not or could not be assessed.

- Option shopping: offering every contested method (df, R², residual type, CI, approximation) without locking choices in advance invites post hoc selection of the most favourable result. This is distinct from re-specifying the model, which L5-17 already covers.

- Influence diagnostics used as an exclusion tool: users will delete clusters or rows the report flags. Present influence as sensitivity (the estimate with and without), require a declared exclusion rule and record every exclusion in provenance.

- Thresholds turning into norms: a cited cut-off placed in a registry (levels < 5, VIF > 10, events per cluster) will be quoted as if the package endorsed it. Ship the validation evidence with each threshold and phrase messages as design consequences, not rules.

- Alarm fatigue: dozens of correlated flags per model, many expected under a correct model (L5-15), train users to ignore the report. Countering it needs the check dependency graph and a first screen limited to root causes that affect declared estimands.

- Diagnosing a model that is not the user's own: refitting from formula plus data with different contrasts, REML setting or optimiser silently diagnoses a different model. Require diagnose(fit) to come first and an objective-match test before any refit.

- Recommendations that lead to models the suite cannot diagnose (nlme correlation structures, CLMMs, GAMMs, multiple membership) leave users with no diagnostics. The report must say explicitly where its coverage ends.

- Licence contamination: translating code from GPL-2-only (HLMdiag), GPL-3 (DHARMa) or AGPL-3 (glmmTMB) packages into a permissive Python package, or combining incompatible GPL versions, can force a relicence or removal later.

- Upstream fragility: glmmTMB/TMB/Matrix binary compatibility and changes to lme4's defaults can cause CRAN check failures and archival of the R package. Engines must be soft dependencies, and fit-based tests must stay off CRAN.

- Promising cross-language parity and then failing to deliver it erodes trust faster than not promising it. Publish the parity tier of every output (L6-03, L4-20) in the user documentation, not only in CI.

- Running out of maintainer capacity: building both languages, all engines and the reports at once risks two half-finished packages. A staged release starting with engine-free audits is safer.

- Exploratory output passed off as confirmatory: the Stream B 'diagnosed specification' will be cited as authority ('the package recommended this model'). Every recommendation must carry its rule, its source, its outcome-blind or outcome-aware status and the spec hash.

- Forcing lme4 formula syntax on Python users, and deferring support for polars and nullable dtypes, will limit adoption on PyPI whatever the methodological quality.


### Contested methodological points


- Random-effects structure: maximal as justified by the design (Barr et al. 2013, JML) vs parsimonious or data-driven reduction for power and convergence (Matuschek et al. 2017, JML, and Bates et al. 2015, arXiv 'Parsimonious mixed models') vs not selecting at all and regularising with priors. The suite should offer the ladder and the maximal model side by side, without declaring a winner.

- Singular fits: keep and report the boundary estimate vs simplify the model vs regularise (blme-style priors or a full Bayesian fit). Whether a singular fit invalidates inference on the fixed effects depends on the goal, and authors disagree.

- Convergence warnings: accept the fit when optimisers agree (allFit-style) vs simplify the model vs change the tolerances. There is no consensus on when a gradient warning can be ignored.

- Random slopes for cross-level interactions and for control covariates: required to avoid underestimated SEs vs left out for parsimony and convergence.

- Centring and within/between decomposition: group-mean vs grand-mean centring vs Mundlak-style contextual models vs econometric fixed effects. Disciplines also disagree on whether a Hausman-type test is a useful decision tool.

- Few clusters: random effects with small-sample df vs cluster dummies as fixed effects vs cluster-robust SEs with small-sample corrections vs a cluster-level (aggregated) analysis. Recommended minimum numbers of groups vary widely and depend on the estimand.

- Denominator df and small-sample inference: Kenward-Roger vs Satterthwaite vs z/LRT vs parametric bootstrap for LMMs. For GLMMs, there is no agreed small-sample correction at all.

- Selecting variance components: boundary-corrected LRT vs marginal or conditional AIC vs BIC vs cross-validation vs not testing components at all. Dropping a component because its test was nonsignificant is itself contested.

- Normality tests and residual checks: graphical only vs formal tests. Robustness arguments (Schielzeth et al. 2020) cover fixed-effect point estimates better than inference on variance components or prediction intervals.

- How much misspecifying the random-effects distribution matters: some argue that fixed-effect inference is largely robust, while others show bias for cluster-specific predictions, variance components and GLMM intercepts.

- R² and explained variance: Nakagawa-Schielzeth marginal/conditional R² vs the Rights & Sterba decomposition vs Snijders-Bosker. These answer different questions, and the choice of distribution-specific variance in GLMMs is a convention, not a fact.

- Ordinal and Likert outcomes: cumulative-link mixed models (Liddell & Kruschke 2018) vs linear models on sum scores or many-point scales, which many psychometricians defend for composites.

- Response times: LMM on log RT vs Gamma or inverse-Gaussian GLMM on raw RT vs shifted-lognormal or ex-Gaussian models. Trimming and outlier rules are contested in their own right, and each option targets a different estimand.

- Pre-post and baseline handling: ANCOVA-style adjustment vs change scores vs baseline as an outcome in a constrained longitudinal model (Lord's paradox).

- Missing data: likelihood under MAR with listwise deletion of covariates vs multilevel multiple imputation vs FIML in an SEM framework. Disagreement remains on which MNAR sensitivity analyses to make routine.

- Contrast coding defaults for factorial designs: treatment vs sum-to-zero vs custom hypothesis-driven contrasts (Schad et al. 2020). No default is neutral.

- Correlations among random effects: zero-correlation models as an early reduction step vs keeping unstructured covariances, since zero-correlation constraints are not invariant to coding and centring (L1-13, L2-11).

- GLMM approximation: Laplace vs adaptive Gauss-Hermite quadrature vs Bayesian estimation as the default for binary data with small clusters.

- Influential observations and clusters: keep and run sensitivity analyses vs remove under a rule vs robust estimation (for example, robustlmm-type down-weighting).

- Sampling weights in multilevel models: which scaling method to use for level-1 weights, and whether to use weights at all for model-based inference.

- Standardised effect sizes in LMMs: which variance component or components go in the denominator, and whether to report standardised effects at all.

- Sensitivity across many specifications (multiverse analysis) vs a single preregistered specification as the confirmatory standard.